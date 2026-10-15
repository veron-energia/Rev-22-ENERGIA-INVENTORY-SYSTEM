-- The correction summary works out the corrected total (416: INVOICES-CREATE-M1).
--
--   V1 A paid S$100.00 invoice, one pair raised to two: the summary says the
--      total goes to S$200.00 and the invoice becomes part-paid with S$100.00
--      owing, and lists the line. Nothing is saved: lines, totals,
--      edit_count, revisions, audit rows and stock are as they were, and the
--      preview switch is off again.
--   V2 S$30.00 off the same invoice: S$30.00 becomes refund due.
--   V3 A note alone: the total stays, it stays paid, no line is listed.
--   V4 Without the corrected lines the result is exactly as before 416 (no
--      'outcome', no 'total' entry).
--   V5 A refusal is what the save would be told, as a review: a stale edit;
--      a manual discount with no reason (its code apart from the sentence).
--   V6 A line removed and a line added are listed as such; on an unpaid
--      invoice the summary says what is owing.
--   V7 A correction that would raise a rental on a paid invoice raises none in
--      the summary and takes no rental number; the real save afterwards
--      works as before and does raise it.
--   V8 Corrected lines and a payment correction together: the payments
--      verdict is worked out on the corrected total (S$100.00 of S$200.00,
--      partially paid), not the total before the correction.
--   V9 A refusal from a check made after the lines, not only from the lines:
--      more pairs than the store has is refused by the save, and the summary
--      says so (checked is false) instead of promising the save.
--   V10 And the goods a part-paid customer already took: a correction that
--      takes them off is refused, and the summary says so with its code.
--
-- Needs 416 (psql -v mig=supabase/416_invoice_editing_foc_and_payment_guards.sql
-- installs it after "begin;"). Disposable database only; everything is rolled
-- back. Fixtures are invented.
\set ON_ERROR_STOP on
begin;
\if :{?prelude}
\i :prelude
\endif
\if :{?mig}
\i :mig
\endif
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
-- A sale of the socks at S$100.00 a pair, paid in cash as given.
create function pg_temp.sale(lines jsonb, paid numeric) returns uuid language plpgsql as
$$declare inv uuid;
begin
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'), lines,
    jsonb_build_object('business_date', public.sg_today()::text));
  if paid > 0 then
    perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', paid)), gen_random_uuid());
  end if;
  return inv;
end$$;
create function pg_temp.socks(q int) returns jsonb language sql as
$$ select jsonb_build_object('kind','product','product_id',pg_temp.fx('socks'),'quantity',q) $$;
-- The saved lines as the correction form sends them back, the first with patch.
create function pg_temp.lines(inv uuid, patch jsonb default '{}'::jsonb) returns jsonb language sql as
$$ select jsonb_agg(case when rn = 1 then x || patch else x end order by rn) from (
     select row_number() over (order by id) rn, jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text,
       'product_id', product_id, 'quantity', quantity, 'unit_price', unit_price) x
       from public.invoice_items where invoice_id = inv) t $$;
-- What a save would leave behind, to compare before and after a summary.
create function pg_temp.state(inv uuid) returns jsonb language sql as
$$ select jsonb_build_object(
     'invoice', (select jsonb_build_object('total', total_amount, 'status', status, 'edits', coalesce(edit_count, 0),
                   'discount', manual_discount, 'notes', notes) from public.invoices where id = inv),
     'items', (select jsonb_agg(jsonb_build_object('id', id, 'q', quantity, 't', line_total) order by id) from public.invoice_items where invoice_id = inv),
     'revisions', (select count(*) from public.invoice_revisions where invoice_id = inv),
     'audits', (select count(*) from public.audit_logs where record_id = inv),
     'moves', (select count(*) from public.stock_movements where invoice_id = inv),
     'payments', (select count(*) from public.invoice_payments where invoice_id = inv)) $$;
create function pg_temp.total(r jsonb) returns jsonb language sql as
$$ select x from jsonb_array_elements(r->'effects') x where x->>'area' = 'total' $$;

do $$
declare o uuid := gen_random_uuid(); sfx text := left(md5(random()::text), 6); st uuid; c uuid; p uuid; v uuid; wh uuid;
begin
  insert into auth.users(id,email) values (o,'cp416-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (o,'CP Owner','cp416-'||sfx||'@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name,code,country_code) values ('CP Store','CP'||sfx,'SG') returning id into st;
  insert into customers(full_name,phone) values ('CP Buyer','+61491576398') returning id into c;
  insert into products(name,sku,product_type) values ('CP Socks','CPS-'||sfx,'own') returning id into p;
  insert into store_inventory(store_id,product_id,current_qty) values (st,p,100);
  perform set_product_prices(st,p,100,100,'available');
  insert into fx values ('o',o),('A',st),('c',c),('socks',p);
  insert into products(name,sku,product_type) values ('CP Mug','CPM-'||sfx,'own') returning id into v;
  insert into store_inventory(store_id,product_id,current_qty) values (st,v,100);
  perform set_product_prices(st,v,40,40,'available');
  insert into fx values ('mug',v);
  insert into payment_methods(name,is_active) values ('CP Cash '||sfx,true) returning id into v; insert into fx values ('cash',v);
  insert into warehouses(name,code) values ('CP Warehouse','CPW'||sfx) returning id into wh;
  insert into special_products(name,sku,sale_price,rate_day,is_active) values ('CP Chair','CPC'||sfx,500,50,true) returning id into v;
  insert into special_product_stock(special_product_id,warehouse_id,current_qty) values (v,wh,5);
  insert into fx values ('chair',v);
  -- One scarf in the store, for V9.
  insert into products(name,sku,product_type) values ('CP Scarf','CPF-'||sfx,'own') returning id into v;
  insert into store_inventory(store_id,product_id,current_qty) values (st,v,1);
  perform set_product_prices(st,v,100,100,'available');
  insert into fx values ('scarf',v);
end $$;

-- ═════ V1–V4 ═════
do $$
declare inv uuid := pg_temp.sale(jsonb_build_array(pg_temp.socks(1)), 100); before jsonb; r jsonb; t jsonb; keys text;
begin
  before := pg_temp.state(inv);
  r := public.preview_invoice_correction(inv, jsonb_build_object('items', pg_temp.lines(inv, '{"quantity":2}')));
  t := pg_temp.total(r);
  perform pg_temp.check((r->'outcome'->>'checked')::boolean and (r->'outcome'->>'total_after')::numeric = 200
      and r->'outcome'->>'status_after' = 'partially_paid' and (r->'outcome'->>'outstanding_after')::numeric = 100
      and (r->'outcome'->>'refund_due_after')::numeric = 0 and not (r->>'blocking')::boolean,
    'V1 one pair raised to two: S$200.00, part-paid, S$100.00 owing: ' || (r->'outcome')::text);
  perform pg_temp.check(t->>'detail' = 'The total goes from S$100.00 to S$200.00. The invoice becomes part-paid with S$100.00 owing.'
      and t->>'change' = 'changed',
    'V1 the summary says it in a sentence: ' || coalesce(t->>'detail', 'none'));
  perform pg_temp.check(jsonb_array_length(r->'outcome'->'lines') = 1 and r->'outcome'->'lines'->0->>'change' = 'changed'
      and r->'outcome'->'lines'->0->>'label' = 'CP Socks'
      and (r->'outcome'->'lines'->0->>'quantity_before')::int = 1 and (r->'outcome'->'lines'->0->>'quantity_after')::int = 2
      and (r->'outcome'->'lines'->0->>'charged_after')::numeric = 200,
    'V1 and lists the line that changes: ' || (r->'outcome'->'lines')::text);
  perform pg_temp.check(pg_temp.state(inv) = before and coalesce(current_setting('invoice.correction_preview', true), '') = ''
      and (select current_qty from public.store_inventory where store_id = pg_temp.fx('A') and product_id = pg_temp.fx('socks')) = 99,
    'V1 nothing is saved and the preview switch is off: ' || pg_temp.state(inv)::text);

  r := public.preview_invoice_correction(inv, jsonb_build_object('items', pg_temp.lines(inv), 'manual_discount', 30,
         'manual_discount_reason', 'Loyal customer'));
  perform pg_temp.check(r->'outcome'->>'status_after' = 'paid' and (r->'outcome'->>'refund_due_after')::numeric = 30
      and (r->'outcome'->>'total_after')::numeric = 70
      and pg_temp.total(r)->>'detail' = 'The total goes from S$100.00 to S$70.00. S$30.00 becomes refund due.',
    'V2 S$30.00 off a paid S$100.00 invoice becomes refund due: ' || coalesce(pg_temp.total(r)->>'detail', (r->'needs_review')::text));

  r := public.preview_invoice_correction(inv, jsonb_build_object('items', pg_temp.lines(inv), 'notes', 'Gift wrapped'));
  perform pg_temp.check(pg_temp.total(r)->>'change' = 'unchanged' and pg_temp.total(r)->>'detail' = 'The total stays S$100.00. It stays paid.'
      and jsonb_array_length(r->'outcome'->'lines') = 0 and r->'outcome'->>'status_after' = 'paid',
    'V3 a note alone: the total stays and it stays paid: ' || coalesce(pg_temp.total(r)->>'detail', 'none'));

  r := public.preview_invoice_correction(inv, jsonb_build_object('notes', 'Gift wrapped'));
  select string_agg(k, ',' order by k) into keys from jsonb_object_keys(r) k;
  perform pg_temp.check(keys = 'affiliate,blocking,edit_count,effects,invoice_id,invoice_no,needs_review,status' and pg_temp.total(r) is null,
    'V4 without the corrected lines the result is as before: ' || keys);
  perform pg_temp.check(pg_temp.state(inv) = before, 'V2–V4 still nothing saved');
end $$;

-- ═════ V5 Refusals ═════
do $$
declare inv uuid := pg_temp.sale(jsonb_build_array(pg_temp.socks(1)), 100); r jsonb;
begin
  r := public.preview_invoice_correction(inv, jsonb_build_object('items', pg_temp.lines(inv, '{"quantity":2}'), 'expected_edit_count', 5));
  perform pg_temp.check((r->>'blocking')::boolean and r->'outcome'->>'checked' = 'false'
      and r->'needs_review' @> '[{"area":"correction","detail":"This invoice was changed by another user. Reload it before saving."}]',
    'V5 a stale edit is what the save would be told: ' || (r->'needs_review')::text);
  r := public.preview_invoice_correction(inv, jsonb_build_object('items', pg_temp.lines(inv), 'manual_discount', 30));
  perform pg_temp.check(r->'needs_review' @> '[{"area":"correction","code":"MANUAL_DISCOUNT_REASON_REQUIRED","detail":"Give the internal reason for the manual discount."}]',
    'V5 a manual discount with no reason, its code apart from the sentence: ' || (r->'needs_review')::text);
end $$;

-- ═════ V6 Removed, added, unpaid ═════
do $$
declare inv uuid := pg_temp.sale(jsonb_build_array(pg_temp.socks(1), jsonb_build_object('kind','product','product_id',pg_temp.fx('mug'),'quantity',1)), 0);
  r jsonb; items jsonb;
begin
  -- Keep the socks, drop the mug, add two more mugs as a new line.
  select jsonb_agg(x) into items from jsonb_array_elements(pg_temp.lines(inv)) x where x->>'product_id' = pg_temp.fx('socks')::text;
  items := items || jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('mug'),'quantity',2));
  r := public.preview_invoice_correction(inv, jsonb_build_object('items', items));
  perform pg_temp.check(r->'outcome'->'lines' @> '[{"change":"removed","label":"CP Mug","quantity_before":1}]'
      and r->'outcome'->'lines' @> '[{"change":"added","label":"CP Mug","quantity_after":2}]'
      and jsonb_array_length(r->'outcome'->'lines') = 2,
    'V6 a line removed and a line added are listed as such: ' || (r->'outcome'->'lines')::text);
  perform pg_temp.check(r->'outcome'->>'status_after' = 'unpaid'
      and pg_temp.total(r)->>'detail' = 'The total goes from S$140.00 to S$180.00. Nothing is paid, so S$180.00 is owing.',
    'V6 on an unpaid invoice it says what is owing: ' || coalesce(pg_temp.total(r)->>'detail', 'none'));
end $$;

-- ═════ V7 No rental from a summary ═════
do $$
declare inv uuid := pg_temp.sale(jsonb_build_array(pg_temp.socks(1)), 100); r jsonb; items jsonb; seq bigint; e text;
begin
  -- The pair swapped for the chair, rented two days at S$50.00: still S$100.00, still paid.
  items := jsonb_build_array(jsonb_build_object('kind','rental','special_product_id',pg_temp.fx('chair'),'quantity',1,
             'rental_rate_type','day','rental_periods',2));
  select last_value into seq from public.rental_no_seq;
  r := public.preview_invoice_correction(inv, jsonb_build_object('items', items));
  perform pg_temp.check(r->'outcome'->>'status_after' = 'paid' and (r->'outcome'->>'total_after')::numeric = 100
      and not exists (select 1 from public.rentals where invoice_id = inv)
      and (select last_value from public.rental_no_seq) = seq,
    'V7 the summary raises no rental and takes no rental number: ' || (r->'outcome')::text);
  begin
    perform public.correct_invoice(inv, items, '{}'::jsonb, 'Rented the chair instead', gen_random_uuid());
  exception when others then e := sqlerrm;
  end;
  perform pg_temp.check(e is null and (select count(*) from public.rentals where invoice_id = inv) = 1
      and (select status from public.invoices where id = inv) = 'paid',
    'V7 the real save afterwards works as before and raises the rental: ' || coalesce(e, 'saved'));
end $$;

-- ═════ V8 Corrected lines and a payment correction together ═════
do $$
declare inv uuid := pg_temp.sale(jsonb_build_array(pg_temp.socks(1)), 100); r jsonb; pay jsonb;
begin
  -- The S$100.00 cash payment kept as it is, sent with the pair raised to two.
  select jsonb_build_object('payment_id', id, 'amount', amount, 'payment_method_id', payment_method_id,
           'date', public.sg_today()::text) into pay
    from public.invoice_payments where invoice_id = inv;
  r := public.preview_invoice_correction(inv, jsonb_build_object('items', pg_temp.lines(inv, '{"quantity":2}'),
         'payment_corrections', jsonb_build_array(pay)));
  perform pg_temp.check(r->'effects' @> jsonb_build_array(jsonb_build_object('area', 'payments', 'change', 'partially paid',
        'detail', 'Payments will total S$100.00 of S$200.00: the invoice goes back to partially paid with S$100.00 outstanding. Benefits already issued at payment stay issued.'))
      and r->'outcome'->>'status_after' = 'partially_paid',
    'V8 the payments verdict uses the corrected total: ' || (select string_agg(x::text, ' ') from jsonb_array_elements(r->'effects') x where x->>'area' = 'payments'));
end $$;

-- ═════ V9 A refusal after the lines ═════
do $$
declare inv uuid; r jsonb; items jsonb; e text;
begin
  -- The store's one scarf sold and paid; then three asked for.
  inv := pg_temp.sale(jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('scarf'),'quantity',1)), 100);
  items := pg_temp.lines(inv, '{"quantity":3}');
  begin
    perform public.correct_invoice(inv, items, '{}'::jsonb, 'Three scarves', gen_random_uuid());
  exception when others then e := sqlerrm;
  end;
  r := public.preview_invoice_correction(inv, jsonb_build_object('items', items));
  perform pg_temp.check(e like 'Not enough stock for invoice product %'
      and (r->>'blocking')::boolean and r->'outcome'->>'checked' = 'false' and r->'outcome'->>'refusal' = e
      and r->'needs_review' @> jsonb_build_array(jsonb_build_object('area', 'correction', 'detail', e)),
    'V9 more than the store has: the save is refused and the summary says so: ' || coalesce(e, 'saved') || ' / ' || (r->'outcome')::text);
  perform pg_temp.check((select current_qty from public.store_inventory where store_id = pg_temp.fx('A') and product_id = pg_temp.fx('scarf')) = 0
      and (select quantity from public.invoice_items where invoice_id = inv) = 1,
    'V9 nothing of the try is kept');
end $$;

-- ═════ V10 Goods the customer already took ═════
do $$
declare inv uuid; r jsonb; items jsonb; e text;
begin
  -- Two pairs, S$100.00 paid and one pair taken home; then the line made one
  -- pair of socks fewer than went home (none).
  inv := pg_temp.sale(jsonb_build_array(pg_temp.socks(2)), 0);
  perform public.record_invoice_settlement(inv,
    jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.fx('cash'), 'amount', 100)),
                       'arrangements', '[]'::jsonb,
                       'handover', jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('socks'), 'qty', 1)))),
    gen_random_uuid());
  items := jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('mug'),'quantity',1));
  begin
    perform public.correct_invoice(inv, items, '{}'::jsonb, 'Mug instead', gen_random_uuid());
  exception when others then e := sqlerrm;
  end;
  r := public.preview_invoice_correction(inv, jsonb_build_object('items', items));
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'partially_paid'
      and e like 'GOODS_HANDED_OVER: %' and r->'outcome'->>'checked' = 'false' and r->'outcome'->>'refusal' = e
      and r->'needs_review' @> jsonb_build_array(jsonb_build_object('area', 'correction', 'code', 'GOODS_HANDED_OVER',
                                                                    'detail', regexp_replace(e, '^GOODS_HANDED_OVER:\s*', ''))),
    'V10 taking off goods the customer took: the save is refused and the summary says so: ' || coalesce(e, 'saved') || ' / ' || (r->'needs_review')::text);
end $$;

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All correction summary checks passed.';
end $$;
rollback;
