-- 424 rule 8: the day an exchange's sale counts on (the Owner, 9 Oct 2026,
-- W2-B10-EXCHANGE-DATE: SALES-EXTRAS-M3 = A).
--
--   * An exchange typed in late counts on the exchange date staff choose: the
--     replacement invoice's date, its paid date (commission, staff and
--     affiliate), its payment's date (the Sales reports' ledger and the Xero
--     export), and the Exchange Invoices report all say that day. The
--     invoice's created_at keeps the moment it was saved.
--   * Saved on the exchange date itself, nothing changes from before: the
--     paid date is the moment it was saved and the payment carries no date
--     of its own.
--   * A date before the 1st of the current month (Singapore) is refused, so a
--     month already sent to Xero is not changed; so is a date before the
--     original sale, and a future date (as before).
--   * Once the replacement invoice is made, the exchange date stays.
--   * An exchange stored with a date in the month before (never through the
--     page) is invoiced on the 1st of this month.
--   * A back-dated exchange paid in part (only through the API; the page takes
--     the whole charge) earns its part-payment commission, staff and
--     affiliate, on its exchange date.
-- Today is pinned (sg_today, as other suites do) and each exchange's saved
-- moment is set before its invoice is made, so the result is the same on any
-- day. Fixtures only (made-up names, +65914003xx phones, @sig.invalid
-- emails). Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;

-- Today in Singapore, pinned.
create or replace function public.sg_today() returns date language sql stable as $$ select date '2026-10-09' $$;
-- Acting as a signed-in person.
create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p::text, true);
end $$;
-- The exchange was saved at this moment (the creators take now()); then what
-- a commit does: make its replacement invoice.
create function pg_temp.saved_at(p_ex uuid, p_at timestamptz) returns void language plpgsql as $$
begin
  update public.product_exchanges set created_at = p_at where id = p_ex;
  update public.product_exchange_payments set created_at = p_at where exchange_id = p_ex;
  set constraints public.exchange_creates_invoice immediate;
  set constraints public.exchange_creates_invoice deferred;
end $$;
create function pg_temp.line(p_inv uuid) returns uuid language sql as
  $$ select id from public.invoice_items where invoice_id = p_inv and line_kind = 'product' order by id limit 1 $$;

do $$
declare
  own uuid := gen_random_uuid(); stf uuid := gen_random_uuid();
  st uuid; cust uuid; ref1 uuid; aff1 uuid; pm uuid; pa uuid; pb uuid;
  inv uuid; pc uuid; res jsonb; ex uuid; xinv uuid; i public.invoices%rowtype; n int; v text;
  saved constant timestamptz := timestamptz '2026-10-09 15:00:00+08';
  payload jsonb;
begin
  insert into auth.users(id, email) values (own, 'xdt-own@sig.invalid'), (stf, 'xdt-stf@sig.invalid');
  insert into profiles(id, full_name, email, role) values
    (own, 'XDT Owner', 'xdt-own@sig.invalid', 'owner'), (stf, 'XDT Staff', 'xdt-stf@sig.invalid', 'staff');
  perform pg_temp.as_user(own);
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  update app_settings set staff_commission_rate = 3 where id and staff_commission_rate <= 0;
  insert into stores(name, code, country_code) values ('XDT Store', 'XDTS', 'SG') returning id into st;
  insert into user_store_assignments(user_id, store_id) values (stf, st);
  insert into customers(full_name, phone) values ('XDT Buyer', '+61491578888') returning id into cust;
  insert into customers(full_name, phone) values ('XDT Referrer', '+61491578957') returning id into ref1;
  insert into customer_affiliates(customer_id, status, activated_at, activated_by)
    values (ref1, 'active', now(), own) returning id into aff1;
  insert into payment_methods(name, is_active) values ('XDT Cash', true) returning id into pm;
  insert into products(name, sku, product_type) values ('XDT A', 'XDTA', 'own') returning id into pa;
  insert into products(name, sku, product_type) values ('XDT B', 'XDTB', 'own') returning id into pb;
  insert into store_inventory(store_id, product_id, current_qty) values (st, pa, 50), (st, pb, 50);
  perform set_product_prices(st, pa, 100, 100, 'available');
  perform set_product_prices(st, pb, 120, 120, 'available');

  -- The original sale, dated 6 Oct.
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  update invoices set business_date = date '2026-10-06' where id = inv;
  payload := jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 20)),
    'reason', 'Size', 'served_by', jsonb_build_array(stf::text),
    'affiliate', jsonb_build_object('mode', 'set', 'id', aff1));

  -- ════ 1. Refused: the month before, before the original sale, the future ══
  foreach v in array array['2026-09-30', '2026-10-05', '2026-10-10'] loop
    begin
      perform create_exchange_with_details('product', payload || jsonb_build_object('exchange_date', v));
      raise exception 'FAIL 1: an exchange dated % was taken', v;
    exception when others then
      if sqlerrm not like (case v
           when '2026-09-30' then 'An exchange can be dated from the 1st of this month (1 Oct 2026) at the earliest.%'
           when '2026-10-05' then 'An exchange cannot be dated before the original sale (6 Oct 2026).'
           else 'An exchange cannot be dated in the future' end) then
        raise exception 'FAIL 1: an exchange dated % was refused with the wrong reason: %', v, sqlerrm;
      end if;
    end;
  end loop;
  if exists (select 1 from product_exchanges where original_invoice_id = inv) then
    raise exception 'FAIL 1: a refused exchange left a record'; end if;

  -- ════ 2. Typed in on 9 Oct, dated 7 Oct: it counts on 7 Oct ══════════════
  res := create_exchange_with_details('product', payload || jsonb_build_object('exchange_date', '2026-10-07'));
  ex := (res->>'id')::uuid;
  perform pg_temp.saved_at(ex, saved);
  select id into xinv from invoices where exchange_id = ex and is_exchange;
  select * into i from invoices where id = xinv;
  if i.business_date is distinct from date '2026-10-07' then
    raise exception 'FAIL 2: the replacement invoice is dated %, not 7 Oct', i.business_date; end if;
  if (i.paid_at at time zone 'Asia/Singapore')::date is distinct from date '2026-10-07' then
    raise exception 'FAIL 2: the replacement invoice was paid on % (Singapore), not 7 Oct', i.paid_at; end if;
  if i.created_at is distinct from saved then
    raise exception 'FAIL 2: the replacement invoice''s created_at moved: %', i.created_at; end if;
  if (select count(*) from invoice_payments p where p.invoice_id = xinv
       and p.effective_at = timestamptz '2026-10-07 00:00:00+08' and p.created_at = saved and p.amount = 20) <> 1 then
    raise exception 'FAIL 2: the top-up is not dated 7 Oct'; end if;
  -- The Sales reports' ledger and the Xero export: 7 Oct, not 9 Oct.
  if (select string_agg(l.sales_date::text || '=' || round(l.amount, 2), ',') from invoice_sales_ledger() l where l.invoice_id = xinv)
     is distinct from '2026-10-07=20.00' then
    raise exception 'FAIL 2: the Sales reports count it on %',
      (select string_agg(l.sales_date::text || '=' || l.amount, ',') from invoice_sales_ledger() l where l.invoice_id = xinv); end if;
  if not exists (select 1 from xero_sales_event_rows('2026-10-07', '2026-10-07') x
                  where x.invoice_id = xinv and x.event_kind = 'receipt' and x.amount = 20)
     or exists (select 1 from xero_sales_event_rows('2026-10-08', '2026-10-31') x where x.invoice_id = xinv) then
    raise exception 'FAIL 2: the Xero export does not date the receipt 7 Oct'; end if;
  -- Commission: staff and affiliate, dated 7 Oct.
  if not exists (select 1 from staff_commissions where invoice_id = xinv)
     or exists (select 1 from staff_commissions where invoice_id = xinv and invoice_paid_date <> date '2026-10-07') then
    raise exception 'FAIL 2: staff commission is not dated 7 Oct: %',
      (select string_agg(invoice_paid_date::text, ',') from staff_commissions where invoice_id = xinv); end if;
  if not exists (select 1 from commissions where invoice_id = xinv)
     or exists (select 1 from commissions where invoice_id = xinv and invoice_paid_date <> date '2026-10-07') then
    raise exception 'FAIL 2: affiliate commission is not dated 7 Oct: %',
      (select string_agg(invoice_paid_date::text, ',') from commissions where invoice_id = xinv); end if;
  -- The Exchange Invoices report lists it on 7 Oct, with its day.
  select count(*) into n from report_exchange_invoices(st, '2026-10-07', '2026-10-07') r
   where r.exchange_id = ex and r.exchange_date = date '2026-10-07' and r.created_at = saved;
  if n <> 1 then raise exception 'FAIL 2: the Exchange Invoices report does not list it on 7 Oct'; end if;
  select count(*) into n from report_exchange_invoices(st, '2026-10-08', '2026-10-09') r where r.exchange_id = ex;
  if n <> 0 then raise exception 'FAIL 2: the Exchange Invoices report also lists it on the day it was saved'; end if;
  -- The audit entry says the day.
  if not exists (select 1 from audit_logs where table_name = 'invoices' and record_id = xinv
                  and action = 'exchange_invoice_created' and new_data->>'business_date' = '2026-10-07') then
    raise exception 'FAIL 2: the audit entry does not say the day it counts on'; end if;

  -- ════ 3. Once its invoice is made, the date stays ═══════════════════════
  begin
    perform set_exchange_details(ex, jsonb_build_array(stf::text), '{"mode":"inherit"}'::jsonb, null, '2026-10-08', null);
    raise exception 'FAIL 3: an invoiced exchange''s date was moved';
  exception when others then
    if sqlerrm not like '%replacement invoice is already made%' then raise; end if;
  end;
  perform set_exchange_details(ex, jsonb_build_array(stf::text), '{"mode":"inherit"}'::jsonb, null, '2026-10-07', null);
  if (select exchange_date from product_exchanges where id = ex) <> date '2026-10-07' then
    raise exception 'FAIL 3: the same date was not kept'; end if;

  -- ════ 4. Saved on its own exchange date: as before ═══════════════════════
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  update invoices set business_date = date '2026-10-08' where id = inv;
  res := create_exchange_with_details('product', payload
    || jsonb_build_object('original_invoice_id', inv,
         'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv), 'quantity', 1))));
  ex := (res->>'id')::uuid;
  if (select exchange_date from product_exchanges where id = ex) <> date '2026-10-09' then
    raise exception 'FAIL 4: an exchange with no date chosen is not dated today'; end if;
  perform pg_temp.saved_at(ex, saved);
  select * into i from invoices where exchange_id = ex and is_exchange;
  if i.business_date is distinct from date '2026-10-09' or i.paid_at is distinct from saved then
    raise exception 'FAIL 4: a same-day exchange moved: dated %, paid %', i.business_date, i.paid_at; end if;
  if exists (select 1 from invoice_payments where invoice_id = i.id and effective_at is not null) then
    raise exception 'FAIL 4: a same-day exchange''s payment was given a date of its own'; end if;

  -- ════ 5. On the 1st: a date in the month before is refused, and one ══════
  -- ════    stored anyway is invoiced on the 1st ══════════════════════════════
  execute $f$create or replace function public.sg_today() returns date language sql stable as
    $q$ select date '2026-11-01' $q$ $f$;
  insert into product_exchanges (exchange_no, original_invoice_id, customer_id, processing_store_id,
                                 replacement_total, topup_amount, status, created_by, exchange_date)
    values ('XDT-5', inv, cust, st, 120, 120, 'completed', own, date '2026-10-31') returning id into ex;
  insert into product_exchange_items (exchange_id, direction, product_id, quantity, unit_price, line_total)
    values (ex, 'replacement', pb, 1, 120, 120);
  insert into product_exchange_payments (exchange_id, payment_method_id, amount) values (ex, pm, 120);
  begin
    perform set_exchange_details(ex, jsonb_build_array(stf::text), '{"mode":"none"}'::jsonb, null, '2026-10-31', null);
    raise exception 'FAIL 5: 31 Oct was taken on 1 Nov';
  exception when others then
    if sqlerrm not like 'An exchange can be dated from the 1st of this month (1 Nov 2026) at the earliest.%' then raise; end if;
  end;
  perform pg_temp.saved_at(ex, timestamptz '2026-11-01 10:00:00+08');
  select * into i from invoices where exchange_id = ex and is_exchange;
  if i.business_date is distinct from date '2026-11-01' or i.paid_at is distinct from timestamptz '2026-11-01 10:00:00+08'
     or exists (select 1 from invoice_payments where invoice_id = i.id and effective_at is not null) then
    raise exception 'FAIL 5: an exchange stored with 31 Oct is not invoiced on 1 Nov as saved: dated %, paid %', i.business_date, i.paid_at; end if;

  -- ════ 6. Back-dated and part paid: part-payment commission on its day ═════
  execute $f$create or replace function public.sg_today() returns date language sql stable as
    $q$ select date '2026-10-09' $q$ $f$;
  update app_settings set instalment_commission_from = date '2026-09-25' where id;
  insert into products(name, sku, product_type) values ('XDT C', 'XDTC', 'own') returning id into pc;
  insert into store_inventory(store_id, product_id, current_qty) values (st, pc, 50);
  perform set_product_prices(st, pc, 1000, 1000, 'available');
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  update invoices set business_date = date '2026-10-06' where id = inv;
  res := create_exchange_with_details('product', payload || jsonb_build_object(
    'original_invoice_id', inv, 'exchange_date', '2026-10-07',
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100))));
  ex := (res->>'id')::uuid;
  perform pg_temp.saved_at(ex, saved);
  select id into xinv from invoices where exchange_id = ex and is_exchange;
  if (select status::text from invoices where id = xinv) <> 'partially_paid' then
    raise exception 'FAIL 6: the replacement invoice is not part paid'; end if;
  if not exists (select 1 from staff_commissions where invoice_id = xinv and earning_basis = 'instalment')
     or exists (select 1 from staff_commissions where invoice_id = xinv and earning_basis = 'instalment'
                 and invoice_paid_date <> date '2026-10-07') then
    raise exception 'FAIL 6: part-payment staff commission is not dated 7 Oct: %',
      (select string_agg(commission_amount || '@' || invoice_paid_date, ',') from staff_commissions where invoice_id = xinv); end if;
  if not exists (select 1 from commissions where invoice_id = xinv and earning_basis = 'instalment')
     or exists (select 1 from commissions where invoice_id = xinv and earning_basis = 'instalment'
                 and invoice_paid_date <> date '2026-10-07') then
    raise exception 'FAIL 6: part-payment affiliate commission is not dated 7 Oct: %',
      (select string_agg(commission_amount || '@' || invoice_paid_date, ',') from commissions where invoice_id = xinv); end if;

  raise notice 'PASS: an exchange typed in on 9 Oct and dated 7 Oct counts on 7 Oct (invoice date, paid date, top-up, Sales ledger, Xero receipt, staff and affiliate commission, Exchange Invoices report, audit) and keeps its saved moment; 30 Sep, 5 Oct (before the sale) and 10 Oct are refused with their reasons; an invoiced exchange keeps its date; a same-day exchange is as before; on 1 Nov, 31 Oct is refused and one stored with it is invoiced on 1 Nov; a back-dated exchange paid in part earns its part-payment commission on its day';
end $$;
rollback;
