-- 411: the Xero sales export's own append-only list of money events, and the
-- record of what was downloaded (audit finding REPORTS-1).
--
-- The rules (the Owner approved fixing REPORTS-1, 9 Oct 2026): every payment
-- received is exported on its own date whatever happens to the invoice later;
-- refunds, including those made on a cancellation, are credit notes on the day
-- the refund was recorded; a payment correction is dated the day it was made; a
-- cancellation alone moves no money; wallet credit and deleted invoices are
-- not listed; invoices refunded before refunds were recorded stay out (shown,
-- never exported); a refund with no payment source is shown and never
-- exported. So a period that was exported never changes later. Every download
-- is recorded, and the review says what is already downloaded (for any store:
-- a paid invoice can move to another store), what vanished or moved, and what
-- was entered after its period was downloaded. A document already downloaded
-- is recorded again only when the page asks for it again, and downloads are
-- recorded one at a time.
--
-- Disposable local database only; everything is rolled back. The migration is
-- applied (twice) inside this transaction, so run the file on its own:
--   psql -v ON_ERROR_STOP=1 -f scripts/xero/tests/sales-events.sql
-- On a local database that has drifted from production, pass a file that
-- installs production's payment, refund and cancellation functions, run right
-- after the begin below:
--   psql -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Every name, phone, number and amount here is invented, and every date is in
-- 2019 so no other row of a shared database falls between them.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

-- The flows below are driven through production's functions as 411 meets them
-- (9 Oct 2026, after 408-410: refund_invoice_recorded at 409's AFTER md5 and
-- cancel_invoice_recorded at 410's).
do $$
declare r record;
begin
  for r in select * from (values
    ('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', 'b0a99345c0f2e635391ac1c251634d95'),
    ('cancel_invoice_recorded(uuid,text,uuid)', 'e8ce9cc4f62896bff144893fdc42225d'),
    ('correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', '63efea7ed4721721b598f2e1237b8f6c'),
    ('remove_invoice_payment(uuid,text,uuid)', '29abf78aed704abb31b3faefd4153a28'),
    ('record_invoice_payment(uuid,jsonb,uuid)', '95a02a1685af524ecf0201b4ed7f9a67')) x(fn, md5)
  loop
    if md5(pg_get_functiondef(('public.' || r.fn)::regprocedure)) <> r.md5 then
      raise exception 'public.% is not production''s version: run with -v prelude=... (see the header)', r.fn; end if;
  end loop;
end $$;

create temp table t411_ledger_md5 as
  select md5(pg_get_functiondef('public.invoice_sales_ledger()'::regprocedure)) as md5;
\ir ../../../supabase/411_xero_sales_export_events.sql

-- ===== 1. The migration creates nothing else and re-runs as a no-op =====
create temp table t411_before as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
create temp table t411_shape_before as
  select c.relname::text as t, a.attname::text as col, format_type(a.atttypid, a.atttypmod) as ty, a.attnotnull,
         c.relrowsecurity, coalesce(array_to_string(c.relacl, ','), '') as acl
    from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
   where c.relnamespace = 'public'::regnamespace and c.relname in ('xero_sales_exports', 'xero_sales_export_documents');
\ir ../../../supabase/411_xero_sales_export_events.sql
do $$
declare n int;
begin
  select count(*) into n from (
    (select fn, md5, acl from t411_before
     except select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), coalesce(array_to_string(p.proacl, ','), '')
              from pg_proc p where p.pronamespace = 'public'::regnamespace)
    union all
    (select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), coalesce(array_to_string(p.proacl, ','), '')
       from pg_proc p where p.pronamespace = 'public'::regnamespace
     except select fn, md5, acl from t411_before)) d;
  if n <> 0 then raise exception '1: the second run changed % function(s) or grant(s)', n; end if;
  select count(*) into n from (
    (select * from t411_shape_before
     except select c.relname::text, a.attname::text, format_type(a.atttypid, a.atttypmod), a.attnotnull,
                   c.relrowsecurity, coalesce(array_to_string(c.relacl, ','), '')
              from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
             where c.relnamespace = 'public'::regnamespace and c.relname in ('xero_sales_exports', 'xero_sales_export_documents'))
    union all
    (select c.relname::text, a.attname::text, format_type(a.atttypid, a.atttypmod), a.attnotnull,
            c.relrowsecurity, coalesce(array_to_string(c.relacl, ','), '')
       from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
      where c.relnamespace = 'public'::regnamespace and c.relname in ('xero_sales_exports', 'xero_sales_export_documents')
     except select * from t411_shape_before)) d;
  if n <> 0 then raise exception '1: the second run changed the tables (% difference(s))', n; end if;
  if (select count(*) from t411_shape_before) <> 11 + 8 then
    raise exception '1: the tables do not have the 19 columns expected'; end if;
  if exists (select 1 from public.xero_sales_exports) or exists (select 1 from public.xero_sales_export_documents) then
    raise exception '1: the migration wrote a row'; end if;
  -- The Sales report keeps its own ledger.
  if md5(pg_get_functiondef('public.invoice_sales_ledger()'::regprocedure)) <> (select md5 from t411_ledger_md5) then
    raise exception '1: invoice_sales_ledger changed'; end if;
end $$;

-- ===== 2. Grants: the rule is internal, the page's three are staff's, the tables closed =====
do $$
declare v text;
begin
  if has_function_privilege('anon', 'public.xero_sales_event_rows(date,date)', 'execute')
     or has_function_privilege('authenticated', 'public.xero_sales_event_rows(date,date)', 'execute')
     or not has_function_privilege('service_role', 'public.xero_sales_event_rows(date,date)', 'execute') then
    raise exception '2: xero_sales_event_rows must be the service role''s alone'; end if;
  foreach v in array array['xero_sales_events(date,date,uuid)', 'xero_sales_export_review(date,date,uuid)',
                           'record_xero_sales_export(date,date,uuid,jsonb,uuid)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '2: % must be signed-in logins'' and the service role''s only', v; end if;
  end loop;
  foreach v in array array['xero_sales_exports', 'xero_sales_export_documents'] loop
    if has_table_privilege('anon', 'public.' || v, 'select,insert,update,delete')
       or has_table_privilege('authenticated', 'public.' || v, 'select,insert,update,delete')
       or not (select relrowsecurity from pg_class where oid = ('public.' || v)::regclass) then
      raise exception '2: % must be closed to clients with RLS on', v; end if;
  end loop;
  -- A signed-in login reading the record directly is refused.
  begin
    perform set_config('role', 'authenticated', true);
    perform count(*) from public.xero_sales_exports;
    raise exception '2: a signed-in login read xero_sales_exports';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ===== Fixture: people, two stores, customers, methods, a product =====
create temp table t411_ids(k text primary key, v uuid);
do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); s uuid := gen_random_uuid();
        im uuid := gen_random_uuid(); pm_ uuid := gen_random_uuid();
        sa uuid; sb uuid; c1 uuid; c2 uuid; cash uuid; card uuid; wallet uuid; p uuid;
begin
  insert into auth.users(id, email) values
    (o, 't411-owner@sig.invalid'), (m, 't411-manager@sig.invalid'), (s, 't411-staff@sig.invalid'),
    (im, 't411-inactive@sig.invalid'), (pm_, 't411-pending@sig.invalid');
  insert into public.profiles(id, full_name, email, role) values
    (o, 'T411 Owner', 't411-owner@sig.invalid', 'owner'),
    (m, 'T411 Manager', 't411-manager@sig.invalid', 'manager'),
    (s, 'T411 Staff', 't411-staff@sig.invalid', 'staff');
  insert into public.profiles(id, full_name, email, role, is_active) values
    (im, 'T411 Inactive', 't411-inactive@sig.invalid', 'manager', false);
  insert into public.profiles(id, full_name, email, role, invitation_status) values
    (pm_, 'T411 Pending', 't411-pending@sig.invalid', 'manager', 'pending');
  insert into public.stores(name, code, country_code) values ('T411 Store A', 'T411A', 'SG') returning id into sa;
  insert into public.stores(name, code, country_code) values ('T411 Store B', 'T411B', 'SG') returning id into sb;
  insert into public.user_store_assignments(user_id, store_id) values (m, sa), (s, sa), (im, sa), (im, sb), (pm_, sa);
  insert into public.customers(full_name, phone, email, address)
    values ('T411 Tan Mei', '+6591400111', 't411-mei@sig.invalid', '1 Fixture Road') returning id into c1;
  insert into public.customers(full_name, phone) values ('T411 Lim Ah Kow', '+6591400112') returning id into c2;
  insert into public.payment_methods(name, is_active) values ('T411 Cash', true) returning id into cash;
  insert into public.payment_methods(name, is_active) values ('T411 Card', true) returning id into card;
  insert into public.payment_methods(name, is_active, is_wallet_credit, wallet_category)
    values ('T411 Wallet', true, true, 'paid') returning id into wallet;
  insert into public.products(name, sku, product_type) values ('T411 Item', 'T411-ITEM', 'own') returning id into p;
  insert into public.store_inventory(store_id, product_id, current_qty) values (sa, p, 500), (sb, p, 500);
  perform set_config('request.jwt.claim.sub', o::text, true);
  perform public.set_product_prices(sa, p, 100, 100, 'available');
  perform public.set_product_prices(sb, p, 100, 100, 'available');
  insert into t411_ids values ('owner', o), ('manager', m), ('staff', s), ('inactive', im), ('pending', pm_),
    ('store_a', sa), ('store_b', sb), ('c1', c1), ('c2', c2), ('cash', cash), ('card', card), ('wallet', wallet), ('product', p);
end $$;
create or replace function pg_temp.t411(p_k text) returns uuid language sql stable as
  $$ select v from t411_ids where k = p_k $$;
create or replace function pg_temp.t411_as(p_k text) returns void language sql as
  $$ select set_config('request.jwt.claim.sub', (select v from t411_ids where k = p_k)::text, true); $$;

-- An invoice of n items paid in one go on a date, the payment recorded that day.
create or replace function pg_temp.t411_sale(p_k text, p_store text, p_customer text, p_qty int, p_method text,
                                              p_amount numeric, p_day date) returns uuid language plpgsql as $$
declare inv uuid;
begin
  inv := public.create_invoice_with_details(pg_temp.t411(p_store), pg_temp.t411(p_customer),
           jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.t411('product'), 'quantity', p_qty)),
           jsonb_build_object('business_date', p_day));
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id', pg_temp.t411(p_method), 'amount', p_amount, 'payment_date', p_day)), gen_random_uuid());
  update public.invoice_payments set created_at = (p_day + time '10:00') at time zone 'Asia/Singapore'
   where invoice_id = inv;
  insert into t411_ids values (p_k, inv);
  return inv;
end $$;

-- ===== 3. August 2019: the receipts =====
do $$
declare inv uuid;
begin
  perform pg_temp.t411_as('owner');
  perform pg_temp.t411_sale('inv_a', 'store_a', 'c1', 1, 'cash', 100, '2019-08-10');   -- refunded in September
  perform pg_temp.t411_sale('inv_b', 'store_a', 'c1', 2, 'card', 200, '2019-08-20');   -- cancelled, part refunded
  perform pg_temp.t411_sale('inv_c', 'store_b', 'c2', 3, 'cash', 300, '2019-08-15');   -- payment corrected
  perform pg_temp.t411_sale('inv_e', 'store_a', 'c1', 1, 'cash', 100, '2019-08-12');   -- refunded the old way
  perform pg_temp.t411_sale('inv_f', 'store_a', 'c1', 1, 'cash', 100, '2019-08-14');   -- deleted (older data)
  perform pg_temp.t411_sale('inv_g', 'store_b', 'c2', 1, 'cash', 100, '2019-08-16');   -- refund with no source
  perform pg_temp.t411_sale('inv_i', 'store_a', 'c1', 1, 'card', 100, '2019-08-26');   -- deleted after download
  -- A part payment in cash, the rest in wallet credit (written as the
  -- allocator would leave it; the wallet's own bookkeeping is not under test).
  perform pg_temp.t411_sale('inv_d', 'store_a', 'c1', 1, 'cash', 60, '2019-08-18');
  insert into public.invoice_payments(invoice_id, payment_method_id, amount, received_by, effective_at, created_at)
  values (pg_temp.t411('inv_d'), pg_temp.t411('wallet'), 40, pg_temp.t411('owner'),
          timestamp '2019-08-18 00:00' at time zone 'Asia/Singapore', timestamptz '2019-08-18 11:00+08');
  -- Refunded before refunds were recorded: status refunded, no refund row.
  update public.invoices set status = 'refunded' where id = pg_temp.t411('inv_e');
  -- Deleted with its payment, as older data can be (delete_invoice now refuses).
  update public.invoices set deleted_at = timestamptz '2019-08-14 12:00+08' where id = pg_temp.t411('inv_f');
end $$;

-- The August list, read before anything else happens to these invoices.
create temp table t411_aug as
  select e.* from public.xero_sales_events('2019-08-01', '2019-08-31') e
   where e.invoice_id in (select v from t411_ids where k like 'inv_%');
create temp table t411_ledger_aug as
  select l.* from public.invoice_sales_ledger() l
   where l.invoice_id in (select v from t411_ids where k like 'inv_%') and l.sales_date between '2019-08-01' and '2019-08-31';

do $$
declare n int; v numeric; r record;
begin
  -- Every receipt on its own day, wallet credit left out, the deleted invoice
  -- left out, the old-way refund shown as left out.
  for r in select * from (values
    ('inv_a', 'receipt', date '2019-08-10', 100.00), ('inv_b', 'receipt', date '2019-08-20', 200.00),
    ('inv_c', 'receipt', date '2019-08-15', 300.00), ('inv_d', 'receipt', date '2019-08-18', 60.00),
    ('inv_e', 'legacy_refund_left_out', date '2019-08-12', 100.00), ('inv_g', 'receipt', date '2019-08-16', 100.00),
    ('inv_i', 'receipt', date '2019-08-26', 100.00)) x(k, kind, day, amount)
  loop
    select count(*) into n from t411_aug a
     where a.invoice_id = pg_temp.t411(r.k) and a.event_kind = r.kind and a.document_date = r.day and a.amount = r.amount;
    if n <> 1 then raise exception '3: % should have one % of % on %, has %', r.k, r.kind, r.amount, r.day, n; end if;
  end loop;
  if (select count(*) from t411_aug) <> 7 then
    raise exception '3: August should list 7 events, lists %', (select count(*) from t411_aug); end if;
  if exists (select 1 from t411_aug where invoice_id = pg_temp.t411('inv_f')) then
    raise exception '3: a deleted invoice was listed'; end if;
  if exists (select 1 from t411_aug a join public.invoice_payments p on p.id = a.event_id
              where p.payment_method_id = pg_temp.t411('wallet')) then
    raise exception '3: a wallet-credit payment was listed'; end if;
  -- Xero numbers as the page has always written them; none for the old-way refund.
  if exists (select 1 from t411_aug a join public.invoices i on i.id = a.invoice_id
              where a.event_kind = 'receipt'
                and a.document_number is distinct from i.invoice_no || '-PAY-' || replace(a.event_id::text, '-', '')) then
    raise exception '3: a receipt''s document number is not <invoice>-PAY-<event>'; end if;
  if exists (select 1 from t411_aug where event_kind = 'legacy_refund_left_out' and document_number is not null) then
    raise exception '3: a left-out payment has a document number'; end if;
  -- The contact is the invoice's customer.
  if (select contact_name || '|' || contact_email || '|' || contact_address from t411_aug
       where invoice_id = pg_temp.t411('inv_a')) <> 'T411 Tan Mei|t411-mei@sig.invalid|1 Fixture Road' then
    raise exception '3: the contact is not the invoice''s customer'; end if;
  -- recorded_at is when the payment was written.
  if (select recorded_at from t411_aug where invoice_id = pg_temp.t411('inv_b')) <> timestamptz '2019-08-20 10:00+08' then
    raise exception '3: recorded_at is not when the payment was written'; end if;
end $$;

-- ===== 4. September 2019: a refund, a cancellation with a refund, corrections =====
do $$
declare inv uuid; it uuid; pay uuid; mv jsonb; v jsonb; wpay uuid;
begin
  perform pg_temp.t411_as('owner');
  -- inv_a: refunded in full on 5 Sep (the guided refund's own function).
  inv := pg_temp.t411('inv_a');
  select id into it from public.invoice_items where invoice_id = inv;
  select id into pay from public.invoice_payments where invoice_id = inv;
  select jsonb_build_array(jsonb_build_object('movement_id', id, 'sellable_quantity', 1)) into mv
    from public.stock_movements where invoice_id = inv and movement_type = 'store_sale' limit 1;
  perform public.refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', it, 'amount', 100)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 100)), mv, 'Customer changed mind', gen_random_uuid());
  update public.invoice_refunds set created_at = timestamptz '2019-09-05 11:00+08' where invoice_id = inv;
  if (select status from public.invoices where id = inv) <> 'refunded' then raise exception '4: inv_a is not refunded'; end if;

  -- inv_b: cancelled (no money moves), then S$150 of the S$200 returned on 2 Sep.
  inv := pg_temp.t411('inv_b');
  v := public.cancel_invoice_recorded(inv, 'Order cancelled', gen_random_uuid());
  select id into it from public.invoice_items where invoice_id = inv;
  select id into pay from public.invoice_payments where invoice_id = inv;
  perform public.refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', it, 'amount', 150)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 150)), '[]'::jsonb, 'Cancellation refund', gen_random_uuid());
  update public.invoice_refunds set created_at = timestamptz '2019-09-02 12:00+08' where invoice_id = inv;
  if (select status from public.invoices where id = inv) <> 'cancelled' then raise exception '4: inv_b is not cancelled'; end if;

  -- inv_c: its 15 Aug payment corrected to S$250 on 3 Sep (dated 15 Aug).
  inv := pg_temp.t411('inv_c');
  select id into pay from public.invoice_payments where invoice_id = inv;
  perform public.correct_invoice_payment(pay, 250, '2019-08-15', pg_temp.t411('cash'), 'Amount typed wrong', gen_random_uuid());
  update public.invoice_payments set created_at = timestamptz '2019-09-03 09:00+08'
   where invoice_id = inv and entry_kind <> 'receipt';

  -- inv_d: its cash part removed on 4 Sep; its wallet part returned to the wallet.
  inv := pg_temp.t411('inv_d');
  select id into pay from public.invoice_payments where invoice_id = inv and payment_method_id = pg_temp.t411('cash');
  select id into wpay from public.invoice_payments where invoice_id = inv and payment_method_id = pg_temp.t411('wallet');
  perform public.remove_invoice_payment(pay, 'Recorded on the wrong invoice', gen_random_uuid());
  update public.invoice_payments set created_at = timestamptz '2019-09-04 09:00+08'
   where invoice_id = inv and entry_kind = 'correction_reversal';
  insert into public.invoice_refunds(invoice_id, payment_id, amount, credit_returned, reason, kind, refunded_by, created_at)
  values (inv, wpay, 40, 40, 'Back to the wallet', 'allocated', pg_temp.t411('owner'), timestamptz '2019-09-04 10:00+08');

  -- inv_g: an older refund written with no payment source.
  insert into public.invoice_refunds(invoice_id, amount, reason, kind, refunded_by, created_at)
  values (pg_temp.t411('inv_g'), 40, 'Old refund', 'legacy', pg_temp.t411('owner'), timestamptz '2019-09-06 10:00+08');

  -- The customer of inv_c is deleted.
  update public.customers set deleted_at = now() where id = pg_temp.t411('c2');
end $$;

do $$
declare n int; r record; v_old numeric; v_new numeric;
begin
  perform pg_temp.t411_as('owner');
  -- THE point: August reads exactly as it did before September happened.
  select count(*) into n from (
    (select event_kind, event_id, invoice_id, document_number, document_date, amount from t411_aug
     except
     select e.event_kind, e.event_id, e.invoice_id, e.document_number, e.document_date, e.amount
       from public.xero_sales_events('2019-08-01', '2019-08-31') e
      where e.invoice_id in (select v from t411_ids where k like 'inv_%'))
    union all
    (select e.event_kind, e.event_id, e.invoice_id, e.document_number, e.document_date, e.amount
       from public.xero_sales_events('2019-08-01', '2019-08-31') e
      where e.invoice_id in (select v from t411_ids where k like 'inv_%')
     except
     select event_kind, event_id, invoice_id, document_number, document_date, amount from t411_aug)) d;
  if n <> 0 then raise exception '4: August changed after September''s refunds and corrections (% difference(s))', n; end if;
  -- ...whereas the Sales report's ledger, which keeps its own rule, did move.
  select coalesce(sum(amount), 0) into v_old from t411_ledger_aug;
  select coalesce(sum(l.amount), 0) into v_new from public.invoice_sales_ledger() l
   where l.invoice_id in (select v from t411_ids where k like 'inv_%') and l.sales_date between '2019-08-01' and '2019-08-31';
  if v_old <> 860 or v_new <> 450 then
    raise exception '4: expected the Sales ledger''s August to move from 860 to 450 (the bug this fixes), got % -> %', v_old, v_new; end if;

  -- September: the credit notes and corrections on the days they happened.
  for r in select * from (values
    ('inv_a', 'refund', date '2019-09-05', -100.00), ('inv_b', 'refund', date '2019-09-02', -150.00),
    ('inv_c', 'correction_reversal', date '2019-09-03', -300.00), ('inv_c', 'correction_replacement', date '2019-09-03', 250.00),
    ('inv_d', 'correction_reversal', date '2019-09-04', -60.00), ('inv_g', 'refund_unsourced', date '2019-09-06', -40.00)) x(k, kind, day, amount)
  loop
    select count(*) into n from public.xero_sales_events('2019-09-01', '2019-09-30') e
     where e.invoice_id = pg_temp.t411(r.k) and e.event_kind = r.kind and e.document_date = r.day and e.amount = r.amount;
    if n <> 1 then raise exception '4: % should have one % of % on %, has %', r.k, r.kind, r.amount, r.day, n; end if;
  end loop;
  select count(*) into n from public.xero_sales_events('2019-09-01', '2019-09-30') e
   where e.invoice_id in (select v from t411_ids where k like 'inv_%');
  if n <> 6 then raise exception '4: September should list 6 events (the wallet refund gives nothing back), lists %', n; end if;
  -- Numbers: REF, REV, ADJ; none for a refund with no source.
  if exists (select 1 from public.xero_sales_events('2019-09-01', '2019-09-30') e
              where e.invoice_id in (select v from t411_ids where k like 'inv_%')
                and e.document_number is distinct from
                    case e.event_kind when 'refund' then e.invoice_no || '-REF-' || replace(e.event_id::text, '-', '')
                                      when 'correction_reversal' then e.invoice_no || '-REV-' || replace(e.event_id::text, '-', '')
                                      when 'correction_replacement' then e.invoice_no || '-ADJ-' || replace(e.event_id::text, '-', '')
                    end) then
    raise exception '4: a September document number is not <invoice>-REF|REV|ADJ-<event>'; end if;
  -- A deleted customer keeps their name on the export.
  if (select min(contact_name) from public.xero_sales_events('2019-09-01', '2019-09-30') e
       where e.invoice_id = pg_temp.t411('inv_c')) is distinct from 'T411 Lim Ah Kow' then
    raise exception '4: a deleted customer lost their name'; end if;
  -- Over both months: what came in less what went back, per invoice.
  for r in select * from (values ('inv_a', 0.00), ('inv_b', 50.00), ('inv_c', 250.00), ('inv_d', 0.00)) x(k, net)
  loop
    if (select coalesce(sum(e.amount), 0) from public.xero_sales_events('2019-08-01', '2019-09-30') e
         where e.invoice_id = pg_temp.t411(r.k) and e.event_kind in ('receipt', 'refund', 'correction_reversal', 'correction_replacement'))
       <> r.net then
      raise exception '4: % should net %', r.k, r.net; end if;
  end loop;
end $$;

-- ===== 5. Who may read it, and which stores =====
do $$
declare n int;
begin
  -- A Manager sees their own store's events only.
  perform pg_temp.t411_as('manager');
  select count(*) into n from public.xero_sales_events('2019-08-01', '2019-09-30') e
   where e.store_id = pg_temp.t411('store_b');
  if n <> 0 then raise exception '5: a Manager saw another store''s events'; end if;
  select count(*) into n from public.xero_sales_events('2019-08-01', '2019-09-30') e
   where e.invoice_id in (select v from t411_ids where k like 'inv_%');
  if n <> 8 then raise exception '5: the Manager should see store A''s 8 events, sees %', n; end if;
  select count(*) into n from public.xero_sales_events('2019-08-01', '2019-09-30', pg_temp.t411('store_b'));
  if n <> 0 then raise exception '5: a Manager read another store by asking for it'; end if;
  begin
    perform public.xero_sales_export_review('2019-08-01', '2019-08-31', pg_temp.t411('store_b'));
    raise exception '5: review of a store the Manager cannot see was answered';
  exception when others then
    if sqlerrm <> 'That store is not accessible' then raise; end if;
  end;
  -- The Owner, one store.
  perform pg_temp.t411_as('owner');
  select count(*) into n from public.xero_sales_events('2019-08-01', '2019-09-30', pg_temp.t411('store_b'));
  if n <> 5 then raise exception '5: store B should have 5 events, has %', n; end if;
  -- Staff, an inactive Manager and a Manager still invited are refused by all three.
  for n in 1 .. 3 loop
    perform pg_temp.t411_as((array['staff', 'inactive', 'pending'])[n]);
    begin
      perform count(*) from public.xero_sales_events('2019-08-01', '2019-08-31');
      raise exception '5: % read the events', (array['staff', 'inactive', 'pending'])[n];
    exception when insufficient_privilege then null;
    end;
    begin
      perform public.xero_sales_export_review('2019-08-01', '2019-08-31');
      raise exception '5: % read the review', (array['staff', 'inactive', 'pending'])[n];
    exception when insufficient_privilege then null;
    end;
    begin
      perform public.record_xero_sales_export('2019-08-01', '2019-08-31', null,
        '[{"event_kind":"receipt"}]'::jsonb, gen_random_uuid());
      raise exception '5: % recorded a download', (array['staff', 'inactive', 'pending'])[n];
    exception when insufficient_privilege then null;
    end;
  end loop;
  -- Signed out.
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform count(*) from public.xero_sales_events('2019-08-01', '2019-08-31');
    raise exception '5: a signed-out caller read the events';
  exception when insufficient_privilege then null;
  end;
  -- The dates.
  perform pg_temp.t411_as('owner');
  begin
    perform count(*) from public.xero_sales_events('2019-08-31', '2019-08-01');
    raise exception '5: an end before the start was answered';
  exception when others then
    if sqlerrm <> 'The end date cannot be before the start date' then raise; end if;
  end;
  begin
    perform count(*) from public.xero_sales_events(null, '2019-08-01');
    raise exception '5: a missing start was answered';
  exception when others then
    if sqlerrm <> 'Choose a start and an end date' then raise; end if;
  end;
end $$;

-- ===== 6. Recording a download =====
create temp table t411_rec(k text primary key, v jsonb);
do $$
declare docs jsonb; v jsonb; req uuid := gen_random_uuid(); n int;
begin
  perform pg_temp.t411_as('owner');
  -- What the page would send for August, all stores: every exportable event.
  select jsonb_agg(jsonb_build_object('event_kind', e.event_kind, 'event_id', e.event_id, 'document_number', e.document_number,
                                      'document_date', e.document_date, 'amount', e.amount) order by e.document_date, e.event_id)
    into docs
    from public.xero_sales_events('2019-08-01', '2019-08-31') e
   where e.event_kind in ('receipt', 'refund', 'correction_reversal', 'correction_replacement');
  if jsonb_array_length(docs) <> 6 then raise exception '6: expected 6 August documents to record, got %', jsonb_array_length(docs); end if;
  if exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.objsubid = 1
                and l.classid::bigint = ((hashtextextended('xero-sales-export', 0) >> 32) & 4294967295)
                and l.objid::bigint = (hashtextextended('xero-sales-export', 0) & 4294967295)) then
    raise exception '6: the export lock is held before any download'; end if;
  v := public.record_xero_sales_export('2019-08-01', '2019-08-31', null, docs, req);
  -- Downloads are recorded one at a time: the call takes the export's
  -- transaction lock, so two at once cannot both find a document new.
  if not exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.objsubid = 1
                    and l.granted and l.mode = 'ExclusiveLock'
                    and l.classid::bigint = ((hashtextextended('xero-sales-export', 0) >> 32) & 4294967295)
                    and l.objid::bigint = (hashtextextended('xero-sales-export', 0) & 4294967295)) then
    raise exception '6: recording a download did not take the export lock'; end if;
  if (v->>'document_count')::int <> 6 or (v->>'net_total')::numeric <> 860 then
    raise exception '6: the record should hold 6 documents for S$860, holds %', v; end if;
  insert into t411_rec values ('aug', v), ('aug_docs', docs), ('aug_req', to_jsonb(req));
  -- What was stored is what the export lists.
  select count(*) into n from public.xero_sales_export_documents d
    join public.xero_sales_exports x on x.id = d.export_id
   where x.id = (v->>'export_id')::uuid and x.exported_by = pg_temp.t411('owner')
     and x.from_date = '2019-08-01' and x.to_date = '2019-08-31' and x.store_id is null
     and pg_temp.t411('store_a') = any(x.covered_store_ids) and pg_temp.t411('store_b') = any(x.covered_store_ids)
     and exists (select 1 from jsonb_array_elements(docs) j
                  where j->>'event_id' = d.event_id::text and j->>'document_number' = d.document_number
                    and (j->>'document_date')::date = d.document_date and (j->>'amount')::numeric = d.amount);
  if n <> 6 then raise exception '6: the stored documents are not the ones sent (% of 6)', n; end if;
  if (select net_total from public.xero_sales_exports where id = (v->>'export_id')::uuid) <> 860 then
    raise exception '6: the stored net total is not S$860'; end if;
  -- Downloads in one transaction share now(); give this one its own time.
  update public.xero_sales_exports set exported_at = timestamptz '2019-09-01 10:00+08' where id = (v->>'export_id')::uuid;
  -- The same request again: the same record, nothing new.
  v := public.record_xero_sales_export('2019-08-01', '2019-08-31', null, docs, req);
  if not coalesce((v->>'replayed')::boolean, false) or v->>'export_id' <> (select t.v->>'export_id' from t411_rec t where k = 'aug')
     or (select count(*) from public.xero_sales_exports) <> 1 then
    raise exception '6: a repeated request was not answered with the same record: %', v; end if;
  -- The same request with other documents is refused.
  begin
    perform public.record_xero_sales_export('2019-08-01', '2019-08-31', null, docs - 0, req);
    raise exception '6: a request ID was reused for other documents';
  exception when others then
    if sqlerrm <> 'This request ID was already used for a different download' then raise; end if;
  end;
end $$;

do $$
declare docs jsonb := (select v from t411_rec where k = 'aug_docs'); one jsonb; bad jsonb;
        legacy jsonb; msgs text[] := '{}'; m text; t record;
begin
  perform pg_temp.t411_as('owner');
  one := docs->0;
  select jsonb_build_object('event_kind', e.event_kind, 'event_id', e.event_id, 'document_number', 'X-1',
                            'document_date', e.document_date, 'amount', e.amount) into legacy
    from public.xero_sales_events('2019-08-01', '2019-08-31') e where e.event_kind = 'legacy_refund_left_out' limit 1;
  for t in select * from (values
    ('another amount', jsonb_build_array(one || jsonb_build_object('amount', (one->>'amount')::numeric + 1)), '% document(s) are not what the export lists now%'),
    ('another date', jsonb_build_array(one || jsonb_build_object('document_date', '2019-08-02')), '% document(s) are not what the export lists now%'),
    ('another number', jsonb_build_array(one || jsonb_build_object('document_number', 'INV-OTHER')), '% document(s) are not what the export lists now%'),
    ('a left-out payment', jsonb_build_array(legacy), '% document(s) are not what the export lists now%'),
    ('an unknown event', jsonb_build_array(one || jsonb_build_object('event_id', gen_random_uuid())), '% document(s) are not what the export lists now%'),
    ('another kind', jsonb_build_array(one || jsonb_build_object('event_kind', 'refund')), '% document(s) are not what the export lists now%'),
    ('a duplicate', jsonb_build_array(one, one), 'A document is listed twice'),
    ('a blank field', jsonb_build_array(one - 'document_number'), 'Every document needs its kind, event, number, date and amount'),
    ('nothing', '[]'::jsonb, 'A download records at least one document')) x(label, payload, msg)
  loop
    begin
      perform public.record_xero_sales_export('2019-08-01', '2019-08-31', null, t.payload, gen_random_uuid());
      raise exception '6: % was recorded', t.label;
    exception when others then
      if sqlerrm not like t.msg then raise exception '6: % was refused with "%"', t.label, sqlerrm; end if;
    end;
  end loop;
  begin
    perform public.record_xero_sales_export('2019-08-01', '2019-08-31', null, docs, null);
    raise exception '6: a download with no request ID was recorded';
  exception when others then
    if sqlerrm <> 'A request ID is required' then raise; end if;
  end;
  -- A Manager cannot record another store's document, even unasked.
  perform pg_temp.t411_as('manager');
  select jsonb_build_array(jsonb_build_object('event_kind', e.event_kind, 'event_id', e.event_id, 'document_number', e.document_number,
                                              'document_date', e.document_date, 'amount', e.amount)) into bad
    from t411_aug e where e.invoice_id = pg_temp.t411('inv_c');
  begin
    perform public.record_xero_sales_export('2019-08-01', '2019-08-31', null, bad, gen_random_uuid());
    raise exception '6: a Manager recorded another store''s document';
  exception when others then
    if sqlerrm not like '1 document(s) are not what the export lists now%' then raise; end if;
  end;
  if (select count(*) from public.xero_sales_exports) <> 1 then raise exception '6: a refused download left a record'; end if;
end $$;

-- ===== 7. The review: already downloaded, vanished, entered late =====
do $$
declare v jsonb; late uuid; n int;
begin
  perform pg_temp.t411_as('owner');
  v := public.xero_sales_export_review('2019-08-01', '2019-08-31');
  if jsonb_array_length(v->'exports') <> 1 or jsonb_array_length(v->'downloads') <> 6
     or jsonb_array_length(v->'vanished') <> 0 or jsonb_array_length(v->'missed') <> 0
     or v->>'recorded_since' is null then
    raise exception '7: right after the download the review should show 1 export, 6 downloads and nothing else: %', v; end if;
  if v->'exports'->0->>'exported_by' <> 'T411 Owner' or (v->'exports'->0->>'document_count')::int <> 6 then
    raise exception '7: the export is not described: %', v->'exports'->0; end if;
  if exists (select 1 from jsonb_array_elements(v->'downloads') d where (d->>'times')::int <> 1) then
    raise exception '7: a document counts more than one download'; end if;
  if (v->'exports'->0->>'net_total')::numeric <> 860
     or not (v->'exports'->0->'covered_store_ids' @> jsonb_build_array(pg_temp.t411('store_a'), pg_temp.t411('store_b'))) then
    raise exception '7: the Owner should see the whole download: %', v->'exports'->0; end if;
  -- A Manager of store A sees that download's store A part only: its count,
  -- total and stores, never store B's takings.
  perform pg_temp.t411_as('manager');
  v := public.xero_sales_export_review('2019-08-01', '2019-08-31');
  if jsonb_array_length(v->'exports') <> 1 or (v->'exports'->0->>'document_count')::int is distinct from 4
     or (v->'exports'->0->>'net_total')::numeric is distinct from 460
     or v->'exports'->0->'covered_store_ids' is distinct from jsonb_build_array(pg_temp.t411('store_a'))
     or jsonb_array_length(v->'downloads') <> 4 then
    raise exception '7: a Manager of store A should see 4 documents for S$460 of the August download, store A alone: %', v; end if;
  perform pg_temp.t411_as('owner');

  -- A payment dated 25 Aug, written on 7 Sep: after August was downloaded.
  late := pg_temp.t411_sale('inv_h', 'store_a', 'c1', 1, 'cash', 70, '2019-08-25');
  update public.invoice_payments set created_at = timestamptz '2019-09-07 10:00+08' where invoice_id = late;
  -- A downloaded receipt's invoice deleted afterwards (older data could be),
  -- and a downloaded receipt re-dated to July (an edit nothing makes today).
  update public.invoices set deleted_at = now() where id = pg_temp.t411('inv_i');
  update public.invoice_payments set effective_at = timestamp '2019-07-30 00:00' at time zone 'Asia/Singapore'
   where invoice_id = pg_temp.t411('inv_g');

  v := public.xero_sales_export_review('2019-08-01', '2019-08-31');
  -- The late one is not among the downloads (the page shows it as new in a
  -- period already downloaded); the deleted one vanished.
  if exists (select 1 from jsonb_array_elements(v->'downloads') d
              where d->>'event_id' in (select id::text from public.invoice_payments where invoice_id = late)) then
    raise exception '7: a payment entered after the download counts as downloaded'; end if;
  if jsonb_array_length(v->'vanished') <> 2
     or not exists (select 1 from jsonb_array_elements(v->'vanished') x
                     where x->>'event_id' = (select id::text from public.invoice_payments where invoice_id = pg_temp.t411('inv_i'))
                       and x->>'now_date' is null and x->>'document_date' = '2019-08-26')
     or not exists (select 1 from jsonb_array_elements(v->'vanished') x
                     where x->>'event_id' = (select id::text from public.invoice_payments where invoice_id = pg_temp.t411('inv_g') and entry_kind = 'receipt')
                       and x->>'now_date' = '2019-07-30' and (x->>'now_amount')::numeric = 100 and x->>'document_date' = '2019-08-16') then
    raise exception '7: the deleted invoice''s receipt (gone) and the re-dated receipt (now 30 Jul) should be the ones vanished: %', v->'vanished'; end if;

  -- Exporting September: the late August payment is offered (missed), with
  -- what the page needs to add it; nothing of September is downloaded yet.
  v := public.xero_sales_export_review('2019-09-01', '2019-09-30');
  if jsonb_array_length(v->'missed') <> 1 or v->'missed'->0->>'invoice_id' <> late::text
     or v->'missed'->0->>'document_date' <> '2019-08-25' or (v->'missed'->0->>'amount')::numeric <> 70
     or v->'missed'->0->>'contact_name' <> 'T411 Tan Mei'
     or v->'missed'->0->>'document_number' not like '%-PAY-%' then
    raise exception '7: September''s review should offer the late August payment: %', v->'missed'; end if;
  if jsonb_array_length(v->'downloads') <> 0 or jsonb_array_length(v->'exports') <> 0 then
    raise exception '7: September has no download yet: %', v; end if;
  -- Store B alone: the late payment is store A's, so it is not offered.
  v := public.xero_sales_export_review('2019-09-01', '2019-09-30', pg_temp.t411('store_b'));
  if jsonb_array_length(v->'missed') <> 0 then raise exception '7: store B was offered store A''s payment'; end if;
  -- A Manager of store A is offered it too.
  perform pg_temp.t411_as('manager');
  v := public.xero_sales_export_review('2019-09-01', '2019-09-30');
  if jsonb_array_length(v->'missed') <> 1 then raise exception '7: the Manager was not offered their store''s late payment'; end if;
end $$;

-- ===== 8. Recording September with the late August payment; then nothing is missed =====
do $$
declare docs jsonb; v jsonb; n int;
begin
  perform pg_temp.t411_as('owner');
  select jsonb_agg(jsonb_build_object('event_kind', e.event_kind, 'event_id', e.event_id, 'document_number', e.document_number,
                                      'document_date', e.document_date, 'amount', e.amount))
    into docs
    from (select e.* from public.xero_sales_events('2019-09-01', '2019-09-30') e
           where e.event_kind in ('receipt', 'refund', 'correction_reversal', 'correction_replacement')
          union all
          select e.* from public.xero_sales_events('2019-08-25', '2019-08-25') e
           where e.invoice_id = pg_temp.t411('inv_h')) e;
  if jsonb_array_length(docs) <> 6 then raise exception '8: expected 5 September documents and the late one, got %', jsonb_array_length(docs); end if;
  v := public.record_xero_sales_export('2019-09-01', '2019-09-30', null, docs, gen_random_uuid());
  if (v->>'document_count')::int <> 6 or (v->>'net_total')::numeric <> -290 then
    raise exception '8: September''s record should hold 6 documents for -S$290, holds %', v; end if;
  update public.xero_sales_exports set exported_at = timestamptz '2019-10-01 10:00+08' where id = (v->>'export_id')::uuid;
  v := public.xero_sales_export_review('2019-09-01', '2019-09-30');
  if jsonb_array_length(v->'missed') <> 0 or jsonb_array_length(v->'downloads') <> 5 or jsonb_array_length(v->'exports') <> 1 then
    raise exception '8: after recording, September should have 5 downloads and miss nothing: %', v; end if;
  -- August now holds the late one among its downloads, from the September file.
  v := public.xero_sales_export_review('2019-08-01', '2019-08-31');
  if not exists (select 1 from jsonb_array_elements(v->'downloads') d
                  where d->>'event_id' in (select id::text from public.invoice_payments where invoice_id = pg_temp.t411('inv_h'))) then
    raise exception '8: the late August payment is not among August''s downloads once downloaded'; end if;
  if jsonb_array_length(v->'exports') <> 1 then
    raise exception '8: only the August download overlaps August'; end if;
  -- A document already downloaded goes into another file only when asked
  -- for again; unasked, the download is refused and nothing is recorded.
  begin
    perform public.record_xero_sales_export('2019-08-01', '2019-08-31', pg_temp.t411('store_a'),
      (select jsonb_agg(d) from jsonb_array_elements((select t.v from t411_rec t where t.k = 'aug_docs')) d
        where d->>'event_id' = (select id::text from public.invoice_payments where invoice_id = pg_temp.t411('inv_a') and entry_kind = 'receipt')),
      gen_random_uuid());
    raise exception '8: a document already downloaded was recorded again unasked';
  exception when others then
    if sqlerrm not like '1 document(s) in this file were downloaded already (the latest: INV-%-PAY-%, by T411 Owner on 1 Sep 2019, 10:00). Nothing was recorded or downloaded. Export again to see what is new.' then
      raise exception '8: refused with "%"', sqlerrm; end if;
  end;
  if (select count(*) from public.xero_sales_exports) <> 2 then raise exception '8: a refused download left a record'; end if;
  -- Downloaded twice, asked for: one entry, counted twice, with its latest download.
  v := public.record_xero_sales_export('2019-08-01', '2019-08-31', pg_temp.t411('store_a'),
    (select jsonb_agg(d || '{"redownload": true}'::jsonb) from jsonb_array_elements((select t.v from t411_rec t where t.k = 'aug_docs')) d
      where d->>'event_id' = (select id::text from public.invoice_payments where invoice_id = pg_temp.t411('inv_a') and entry_kind = 'receipt')),
    gen_random_uuid());
  update public.xero_sales_exports set exported_at = timestamptz '2019-10-02 10:00+08' where id = (v->>'export_id')::uuid;
  v := public.xero_sales_export_review('2019-08-01', '2019-08-31');
  if jsonb_array_length(v->'downloads') <> 7 then
    raise exception '8: August should list its 6 downloaded documents and the late one, once each; lists %',
      jsonb_array_length(v->'downloads'); end if;
  select (d->>'times')::int into n from jsonb_array_elements(v->'downloads') d
   where d->>'event_id' = (select id::text from public.invoice_payments where invoice_id = pg_temp.t411('inv_a') and entry_kind = 'receipt');
  if n <> 2 or jsonb_array_length(v->'exports') <> 2 then
    raise exception '8: a document downloaded twice should count 2 (got %) with 2 exports', n; end if;
  if (select (d->>'exported_at')::timestamptz from jsonb_array_elements(v->'downloads') d
       where d->>'event_id' = (select id::text from public.invoice_payments where invoice_id = pg_temp.t411('inv_a') and entry_kind = 'receipt'))
     <> timestamptz '2019-10-02 10:00+08' then
    raise exception '8: a document downloaded twice should show its latest download'; end if;
  if (v->>'recorded_since')::timestamptz <> timestamptz '2019-09-01 10:00+08' then
    raise exception '8: recorded_since should be the first download'; end if;
end $$;

-- ===== 9. A download for one store covers that store only =====
do $$
declare docs jsonb; v jsonb; ja uuid; jb uuid;
begin
  perform pg_temp.t411_as('owner');
  ja := pg_temp.t411_sale('inv_j', 'store_a', 'c1', 1, 'cash', 30, '2019-07-10');
  -- July downloaded for store A alone.
  select jsonb_agg(jsonb_build_object('event_kind', e.event_kind, 'event_id', e.event_id, 'document_number', e.document_number,
                                      'document_date', e.document_date, 'amount', e.amount))
    into docs from public.xero_sales_events('2019-07-01', '2019-07-31', pg_temp.t411('store_a')) e;
  v := public.record_xero_sales_export('2019-07-01', '2019-07-31', pg_temp.t411('store_a'), docs, gen_random_uuid());
  if (v->>'document_count')::int <> 1 then raise exception '9: July store A should record 1 document, %', v; end if;
  if (select covered_store_ids from public.xero_sales_exports where id = (v->>'export_id')::uuid) <> array[pg_temp.t411('store_a')] then
    raise exception '9: a one-store download must cover that store alone'; end if;
  -- Then a store B payment dated in July, and a store A one, both entered later.
  jb := pg_temp.t411_sale('inv_k', 'store_b', 'c2', 1, 'cash', 40, '2019-07-12');
  perform pg_temp.t411_sale('inv_l', 'store_a', 'c1', 1, 'cash', 50, '2019-07-13');
  v := public.xero_sales_export_review('2019-09-01', '2019-09-30');
  -- Store A's late July payment is offered; store B's July was never
  -- downloaded, so its payment is not "entered after a download".
  if exists (select 1 from jsonb_array_elements(v->'missed') x where x->>'invoice_id' = jb::text) then
    raise exception '9: a payment of a store the July download did not cover was offered as missed'; end if;
  if not exists (select 1 from jsonb_array_elements(v->'missed') x where x->>'invoice_id' = pg_temp.t411('inv_l')::text) then
    raise exception '9: store A''s late July payment was not offered'; end if;
  if exists (select 1 from jsonb_array_elements(v->'missed') x where x->>'invoice_id' = ja::text) then
    raise exception '9: a downloaded July payment was offered as missed'; end if;
  -- July for store B: no download overlaps it.
  v := public.xero_sales_export_review('2019-07-01', '2019-07-31', pg_temp.t411('store_b'));
  if jsonb_array_length(v->'exports') <> 0 or jsonb_array_length(v->'downloads') <> 0 then
    raise exception '9: store B''s July was never downloaded: %', v; end if;
end $$;

-- ===== 10. An invoice moved to another store after its documents were downloaded =====
do $$
declare inv uuid; docs jsonb; v jsonb; doc jsonb;
begin
  perform pg_temp.t411_as('owner');
  -- October 2019, store A alone: a card payment, downloaded for store A.
  inv := pg_temp.t411_sale('inv_m', 'store_a', 'c1', 1, 'card', 90, '2019-10-10');
  select jsonb_agg(jsonb_build_object('event_kind', e.event_kind, 'event_id', e.event_id, 'document_number', e.document_number,
                                      'document_date', e.document_date, 'amount', e.amount))
    into docs from public.xero_sales_events('2019-10-01', '2019-10-31', pg_temp.t411('store_a')) e;
  if coalesce(jsonb_array_length(docs), 0) <> 1 then raise exception '10: October store A should hold 1 document, %', docs; end if;
  doc := docs->0;
  v := public.record_xero_sales_export('2019-10-01', '2019-10-31', pg_temp.t411('store_a'), docs, gen_random_uuid());
  update public.xero_sales_exports set exported_at = timestamptz '2019-11-01 10:00+08' where id = (v->>'export_id')::uuid;
  -- The paid invoice moves to store B, as correct_invoice does for an Owner or Manager.
  update public.invoices set store_id = pg_temp.t411('store_b') where id = inv;
  if not exists (select 1 from public.xero_sales_events('2019-10-01', '2019-10-31', pg_temp.t411('store_b')) e
                  where e.event_id = (doc->>'event_id')::uuid and e.document_number = doc->>'document_number') then
    raise exception '10: the moved document should be store B''s now, with the same number'; end if;
  -- Store B: the document is known as downloaded (for store A); nothing is new,
  -- vanished or missed, and the store A download is listed with store B's part.
  v := public.xero_sales_export_review('2019-10-01', '2019-10-31', pg_temp.t411('store_b'));
  if jsonb_array_length(v->'downloads') <> 1 or v->'downloads'->0->>'event_id' is distinct from doc->>'event_id'
     or (v->'downloads'->0->>'times')::int is distinct from 1
     or jsonb_array_length(v->'vanished') <> 0 or jsonb_array_length(v->'missed') <> 0 then
    raise exception '10: store B''s review should know the moved document as downloaded: %', v; end if;
  if jsonb_array_length(v->'exports') <> 1 or (v->'exports'->0->>'document_count')::int is distinct from 1
     or (v->'exports'->0->>'net_total')::numeric is distinct from 90 or v->'exports'->0->'covered_store_ids' is distinct from '[]'::jsonb
     or v->'exports'->0->>'store_id' is distinct from pg_temp.t411('store_a')::text then
    raise exception '10: store B''s review should list the store A download that holds its document: %', v->'exports'; end if;
  -- Store A: the document moved away (not gone), to store B, which the Owner sees.
  v := public.xero_sales_export_review('2019-10-01', '2019-10-31', pg_temp.t411('store_a'));
  if jsonb_array_length(v->'vanished') <> 1 or v->'vanished'->0->>'event_id' is distinct from doc->>'event_id'
     or (v->'vanished'->0->>'moved')::boolean is not true
     or v->'vanished'->0->>'now_store_id' is distinct from pg_temp.t411('store_b')::text
     or v->'vanished'->0->>'now_date' is distinct from '2019-10-10' or (v->'vanished'->0->>'now_amount')::numeric is distinct from 90 then
    raise exception '10: store A''s review should say the document moved to store B: %', v->'vanished'; end if;
  -- All stores: downloaded once, nothing vanished.
  v := public.xero_sales_export_review('2019-10-01', '2019-10-31');
  if jsonb_array_length(v->'vanished') <> 0 or jsonb_array_length(v->'downloads') <> 1 then
    raise exception '10: all stores should hold the document once and miss nothing: %', v; end if;
  -- A deleted invoice's document is gone, not moved (section 7).
  v := public.xero_sales_export_review('2019-08-01', '2019-08-31');
  if exists (select 1 from jsonb_array_elements(v->'vanished') x where (x->>'moved')::boolean) then
    raise exception '10: a gone or re-dated document was called moved: %', v->'vanished'; end if;
  -- Exporting store B does not hand the document over again unasked...
  begin
    perform public.record_xero_sales_export('2019-10-01', '2019-10-31', pg_temp.t411('store_b'), docs, gen_random_uuid());
    raise exception '10: a document downloaded for store A was recorded again for store B unasked';
  exception when others then
    if sqlerrm <> format('1 document(s) in this file were downloaded already (the latest: %s, by T411 Owner on 1 Nov 2019, 10:00). Nothing was recorded or downloaded. Export again to see what is new.', doc->>'document_number') then
      raise exception '10: refused with "%"', sqlerrm; end if;
  end;
  -- ...only when asked for again.
  v := public.record_xero_sales_export('2019-10-01', '2019-10-31', pg_temp.t411('store_b'),
         jsonb_build_array(doc || '{"redownload": true}'::jsonb), gen_random_uuid());
  if (v->>'document_count')::int is distinct from 1
     or (select count(*) from public.xero_sales_export_documents d where d.event_id = (doc->>'event_id')::uuid) <> 2 then
    raise exception '10: the document asked for again should be recorded a second time: %', v; end if;
  update public.xero_sales_exports set exported_at = timestamptz '2019-11-02 11:00+08' where id = (v->>'export_id')::uuid;
  -- Unasked again: refused, naming its latest download.
  begin
    perform public.record_xero_sales_export('2019-10-01', '2019-10-31', pg_temp.t411('store_b'), docs, gen_random_uuid());
    raise exception '10: a document downloaded twice was recorded a third time unasked';
  exception when others then
    if sqlerrm <> format('1 document(s) in this file were downloaded already (the latest: %s, by T411 Owner on 2 Nov 2019, 11:00). Nothing was recorded or downloaded. Export again to see what is new.', doc->>'document_number') then
      raise exception '10: refused with "%"', sqlerrm; end if;
  end;
  -- A Manager of store A alone: moved, to a store they cannot see, so unnamed;
  -- and the store B download is not listed to them.
  perform pg_temp.t411_as('manager');
  v := public.xero_sales_export_review('2019-10-01', '2019-10-31');
  if jsonb_array_length(v->'vanished') <> 1 or (v->'vanished'->0->>'moved')::boolean is not true
     or v->'vanished'->0->'now_store_id' is distinct from 'null'::jsonb then
    raise exception '10: the Manager should see the document moved to a store not named: %', v->'vanished'; end if;
  if jsonb_array_length(v->'exports') <> 1 or (v->'exports'->0->>'document_count')::int is distinct from 1 then
    raise exception '10: the Manager should see the store A download alone: %', v->'exports'; end if;
end $$;

-- ===== 11. Two downloads of the same dates at once: the second is refused =====
do $$
declare docs jsonb; v jsonb;
begin
  perform pg_temp.t411_as('owner');
  perform pg_temp.t411_sale('inv_n', 'store_a', 'c1', 1, 'card', 100, '2019-06-10');
  -- The Owner (all stores) and the Manager (store A) both loaded June while
  -- nothing of it was downloaded; the Owner downloads first.
  select jsonb_agg(jsonb_build_object('event_kind', e.event_kind, 'event_id', e.event_id, 'document_number', e.document_number,
                                      'document_date', e.document_date, 'amount', e.amount))
    into docs from public.xero_sales_events('2019-06-01', '2019-06-30') e;
  if coalesce(jsonb_array_length(docs), 0) <> 1 then raise exception '11: June should hold 1 document, %', docs; end if;
  v := public.record_xero_sales_export('2019-06-01', '2019-06-30', null, docs, gen_random_uuid());
  update public.xero_sales_exports set exported_at = timestamptz '2019-07-01 09:30+08' where id = (v->>'export_id')::uuid;
  perform pg_temp.t411_as('manager');
  begin
    perform public.record_xero_sales_export('2019-06-01', '2019-06-30', pg_temp.t411('store_a'), docs, gen_random_uuid());
    raise exception '11: the second download of the same document was recorded';
  exception when others then
    if sqlerrm <> format('1 document(s) in this file were downloaded already (the latest: %s, by T411 Owner on 1 Jul 2019, 09:30). Nothing was recorded or downloaded. Export again to see what is new.', docs->0->>'document_number') then
      raise exception '11: refused with "%"', sqlerrm; end if;
  end;
  if exists (select 1 from public.xero_sales_exports where exported_by = pg_temp.t411('manager')) then
    raise exception '11: a refused download left a record'; end if;
  -- The same request again is still the same record, not a refusal.
  perform pg_temp.t411_as('owner');
  if not coalesce((public.record_xero_sales_export('2019-06-01', '2019-06-30', null, docs,
                     (select request_id from public.xero_sales_exports where id = (v->>'export_id')::uuid))->>'replayed')::boolean, false) then
    raise exception '11: a repeated request was not replayed'; end if;
end $$;

select 'xero sales events (411): all checks passed' as result;
rollback;
