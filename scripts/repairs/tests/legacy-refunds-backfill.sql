-- The legacy refunds repair (scripts/repairs/legacy-refunds-backfill.sql),
-- run against fixtures shaped as production was on 9 Oct 2026: nine invoices
-- refunded through the old request with no refund row, eleven payments,
-- S$8,054.47 (document numbers and amounts only; every name is invented).
--
--   0. The dry run (scripts/repairs/legacy-refunds-backfill-dry-run.sql):
--      eleven payments, S$8,054.47, ok on every row.
--   1. A refund row already on one invoice: the repair refuses, nothing kept.
--   1b. The customer's Legacy therapy from one invoice's paid day already
--      activated: the dry run shows it on that invoice only, and the repair
--      refuses, naming the invoice and the guard, and keeps nothing.
--   2. The repair: one refund per payment, its amount, against that payment,
--      by the old request's approver, dated on its approval, naming it; each
--      invoice holds S$0 and shows its total refunded; one audit row each;
--      the Xero export lists receipts and refunds that cancel out, and no
--      longer leaves the payments out.
--   3. Run again: says so and changes nothing.
--
-- Run it from the repository's root (it reads the dry run's text with cat).
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;

create temp table tlr(invoice_no text primary key, total numeric, payments numeric[], approved_at timestamptz);
insert into tlr values
  ('INV-2026-0028',  395.00, array[395.00],          '2026-08-12 09:30:51+00'),
  ('INV-2026-0047',  610.00, array[610.00],          '2026-08-13 07:13:15+00'),
  ('INV-2026-0110', 4059.00, array[4059.00],         '2026-08-27 11:22:07+00'),
  ('INV-2026-0132',   61.00, array[61.00],           '2026-08-29 11:39:49+00'),
  ('INV-2026-0140',   61.00, array[50.00, 11.00],    '2026-08-31 06:02:54+00'),
  ('INV-2026-0160',  610.00, array[610.00],          '2026-09-01 06:11:37+00'),
  ('INV-2026-0174', 1666.67, array[1666.67],         '2026-09-03 04:27:15+00'),
  ('INV-2026-0184',  264.80, array[257.00, 7.80],    '2026-09-07 04:51:30+00'),
  ('INV-2026-0202',  327.00, array[327.00],          '2026-09-09 07:05:02+00');

do $$
declare o uuid := gen_random_uuid(); s uuid := gen_random_uuid(); st uuid; c uuid; pm uuid; r record; inv uuid; a numeric;
begin
  insert into auth.users(id, email) values (o, 'tlr-owner@tests.invalid'), (s, 'tlr-staff@tests.invalid');
  insert into profiles(id, full_name, email, role, is_active) values
    (o, 'TLR Owner', 'tlr-owner@tests.invalid', 'owner', true), (s, 'TLR Staff', 'tlr-staff@tests.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name, code, country_code) values ('TLR Store', 'TLRS', 'SG') returning id into st;
  insert into customers(full_name, phone) values ('TLR Buyer', '+61491572549') returning id into c;
  insert into payment_methods(name, is_active) values ('TLR PayNow', true) returning id into pm;
  for r in select * from tlr loop
    insert into invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount, business_date, paid_at)
      values (r.invoice_no, st, c, s, 'refunded', r.total, r.total, r.total, (r.approved_at - interval '3 days')::date,
              r.approved_at - interval '3 days')
      returning id into inv;
    foreach a in array r.payments loop
      insert into invoice_payments(invoice_id, payment_method_id, amount, received_by, created_at)
        values (inv, pm, a, s, r.approved_at - interval '3 days');
    end loop;
    insert into approval_requests(request_type, status, requested_by, approved_by, related_record_id, reason, created_at, approved_at)
      values ('invoice_refund', 'approved', s, o, inv, 'Customer asked for a refund', r.approved_at - interval '1 day', r.approved_at);
  end loop;
  -- A bystander: refunded the guided way, with its refund row; never touched.
  insert into invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount, business_date)
    values ('INV-2026-9417', st, c, s, 'refunded', 50, 50, 0, '2026-09-10') returning id into inv;
  insert into invoice_payments(invoice_id, payment_method_id, amount, received_by, created_at) values (inv, pm, 50, s, '2026-09-10 02:00+00');
  insert into invoice_refunds(invoice_id, payment_id, amount, reason, kind, refunded_by, request_id, created_at)
    values (inv, (select id from invoice_payments where invoice_id = inv), 50, 'Guided refund', 'allocated', o, gen_random_uuid(), '2026-09-11 02:00+00');
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ===== 0. The dry run =====
-- Its SELECT, as a view to check (run from the repository's root).
\set tlr_dry_sql `cat scripts/repairs/legacy-refunds-backfill-dry-run.sql`
create temp view tlr_dry as :tlr_dry_sql
do $$
begin
  if (select count(*) from tlr_dry) <> 11 or exists (select 1 from tlr_dry where not ok)
     or exists (select 1 from tlr_dry where payments <> 11 or payments_total <> 8054.47) then
    raise exception 'FAIL 0: the dry run does not show eleven payments of S$8,054.47, all ok: %',
      (select jsonb_agg(to_jsonb(d)) from tlr_dry d where not d.ok); end if;
  if exists (select 1 from tlr_dry d join tlr t on t.invoice_no = d.invoice_no
              where d.refund_day <> (t.approved_at at time zone 'Asia/Singapore')::date) then
    raise exception 'FAIL 0: the dry run''s refund day is not the approval''s Singapore day'; end if;
  raise notice 'PASS 0: the dry run shows eleven payments, S$8,054.47, each ok, dated on its approval';
end $$;

-- ===== 1. Anything out of place: refused, nothing kept =====
savepoint tlr_guard;
insert into invoice_refunds(invoice_id, payment_id, amount, reason, kind, created_at)
  select x.id, (select id from invoice_payments where invoice_id = x.id limit 1), 1, 'Fixture: an extra refund', 'allocated', now()
    from invoices x where x.invoice_no = 'INV-2026-0132';
\set ON_ERROR_STOP off
\ir ../legacy-refunds-backfill.sql
\set ON_ERROR_STOP on
rollback to savepoint tlr_guard;
release savepoint tlr_guard;
select set_config('tlr.refused', :'LAST_ERROR_MESSAGE', true) as tlr_refused \gset
do $$
begin
  if current_setting('tlr.refused') not like 'legacy refunds: INV-2026-0132 already has a refund recorded; nothing was changed%' then
    raise exception 'FAIL 1: not refused as expected: %', current_setting('tlr.refused'); end if;
  if exists (select 1 from invoice_refunds r join invoices x on x.id = r.invoice_id where x.invoice_no like 'INV-2026-01%' or x.invoice_no like 'INV-2026-00%' or x.invoice_no like 'INV-2026-02%') then
    raise exception 'FAIL 1: a refused run kept something'; end if;
  raise notice 'PASS 1: with one invoice out of place the repair refuses, names it, and keeps nothing';
end $$;

-- ===== 1b. Blocked by the legacy refund guard: refused, nothing kept =====
savepoint tlr_guard;
insert into therapy_entitlements(entitlement_no, customer_id, store_id, package_name, entitlement_kind, qualifying_amount,
                                 qualified_value, activation_deadline, status, qualification_group_id)
  select 'TLR-LEGACY-1', x.customer_id, x.store_id, 'TLR Legacy', 'unlimited', 0, 0, current_date, 'active',
         legacy_qualification_group(x.customer_id, x.store_id, (x.paid_at at time zone 'Asia/Singapore')::date)
    from invoices x where x.invoice_no = 'INV-2026-0110';
do $$
begin
  if (select string_agg(distinct invoice_no, ',') from tlr_dry where not ok) is distinct from 'INV-2026-0110'
     or (select max(legacy_therapy_blocking) from tlr_dry where invoice_no = 'INV-2026-0110') <> 1 then
    raise exception 'FAIL 1b: the dry run does not show INV-2026-0110 alone as blocked: %',
      (select jsonb_agg(to_jsonb(d)) from tlr_dry d where not d.ok); end if;
end $$;
\set ON_ERROR_STOP off
\ir ../legacy-refunds-backfill.sql
\set ON_ERROR_STOP on
rollback to savepoint tlr_guard;
release savepoint tlr_guard;
select set_config('tlr.refused', :'LAST_ERROR_MESSAGE', true) as tlr_refused \gset
do $$
begin
  if current_setting('tlr.refused') not like 'legacy refunds: INV-2026-0110 is blocked by the legacy refund guard (This invoice cannot be refunded: the customer''s Legacy therapy%); nothing was changed%' then
    raise exception 'FAIL 1b: not refused as expected: %', current_setting('tlr.refused'); end if;
  if exists (select 1 from invoice_refunds r join invoices x on x.id = r.invoice_id where x.invoice_no like 'INV-2026-01%' or x.invoice_no like 'INV-2026-00%' or x.invoice_no like 'INV-2026-02%') then
    raise exception 'FAIL 1b: a refused run kept something'; end if;
  raise notice 'PASS 1b: blocked by the legacy refund guard, the repair refuses, names the invoice and the guard, and keeps nothing';
end $$;

-- ===== 2. The repair =====
\ir ../legacy-refunds-backfill.sql
do $$
declare r record; x record; ev record; n int;
begin
  -- Read as the fixture's Owner (the invoice's figures answer staff of its store).
  perform set_config('request.jwt.claim.sub', (select id::text from profiles where email = 'tlr-owner@tests.invalid'), true);
  if (select count(*) from invoice_refunds f join invoices i on i.id = f.invoice_id join tlr t on t.invoice_no = i.invoice_no) <> 11
     or (select sum(f.amount) from invoice_refunds f join invoices i on i.id = f.invoice_id join tlr t on t.invoice_no = i.invoice_no) <> 8054.47 then
    raise exception 'FAIL 2: not eleven refunds of S$8,054.47'; end if;
  for r in select t.*, i.id, i.paid_amount, i.status::text as status from tlr t join invoices i on i.invoice_no = t.invoice_no loop
    if r.paid_amount <> 0 or invoice_net_received(r.id) <> 0 or r.status <> 'refunded'
       or (invoice_financial_position(r.id)->>'refunded')::numeric <> r.total
       or (invoice_financial_position(r.id)->>'refund_due')::numeric <> 0 then
      raise exception 'FAIL 2: % does not read as fully refunded: %', r.invoice_no, invoice_financial_position(r.id); end if;
    -- Each payment refunded in full, on the approval, by its approver, naming the request.
    if exists (select 1 from invoice_payments p
                where p.invoice_id = r.id
                  and not exists (select 1 from invoice_refunds f join approval_requests a on a.id = f.request_id
                                   where f.payment_id = p.id and f.amount = p.amount and f.created_at = r.approved_at
                                     and a.related_record_id = r.id and f.refunded_by = a.approved_by and f.credit_returned = 0
                                     and f.reason = 'Recorded later: refunded through the old request approved on '
                                                    || to_char((r.approved_at at time zone 'Asia/Singapore')::date, 'FMDD Mon YYYY'))) then
      raise exception 'FAIL 2: a payment of % has no matching refund', r.invoice_no; end if;
    if (select count(*) from audit_logs where record_id = r.id and action = 'legacy_refund_recorded') <> 1 then
      raise exception 'FAIL 2: % was not audited once', r.invoice_no; end if;
  end loop;
  if (select reason from invoice_refunds f join invoices i on i.id = f.invoice_id where i.invoice_no = 'INV-2026-0028')
       <> 'Recorded later: refunded through the old request approved on 12 Aug 2026' then
    raise exception 'FAIL 2: the reason does not name the Singapore day'; end if;
  -- The bystander is untouched.
  if (select count(*) from invoice_refunds f join invoices i on i.id = f.invoice_id where i.invoice_no = 'INV-2026-9417') <> 1 then
    raise exception 'FAIL 2: a guided refund was touched'; end if;
  -- Xero: the nine are ordinary receipts and refunds now, pairs that cancel out.
  select count(*) filter (where e.event_kind = 'legacy_refund_left_out') as left_out,
         count(*) filter (where e.event_kind = 'receipt') as receipts,
         count(*) filter (where e.event_kind = 'refund') as refunds,
         coalesce(sum(e.amount) filter (where e.event_kind = 'receipt'), 0) as received,
         coalesce(sum(e.amount) filter (where e.event_kind = 'refund'), 0) as refunded
    into ev
    from xero_sales_event_rows('2026-08-01', '2026-09-30') e join tlr t on t.invoice_no = e.invoice_no;
  if ev.left_out <> 0 or ev.receipts <> 11 or ev.refunds <> 11 or ev.received <> 8054.47 or abs(ev.refunded) <> 8054.47 then
    raise exception 'FAIL 2: the Xero events are %', to_jsonb(ev); end if;
  if exists (select 1 from xero_sales_event_rows('2026-08-01', '2026-09-30') e join tlr t on t.invoice_no = e.invoice_no
              where e.event_kind = 'refund' and e.document_date <> (t.approved_at at time zone 'Asia/Singapore')::date) then
    raise exception 'FAIL 2: a refund is not dated on its approval''s Singapore day'; end if;
  -- Done: the dry run shows every payment refunded already, none ok.
  if exists (select 1 from tlr_dry where ok or refund_rows = 0) then
    raise exception 'FAIL 2: after the repair the dry run still shows a payment to refund'; end if;
  raise notice 'PASS 2: eleven refunds, one per payment, by the approver, dated and named on the old approval; each invoice holds S$0 and shows its total refunded, audited once; a guided refund is untouched; the Xero export lists eleven receipts and eleven refunds that cancel out, none left out';
end $$;

-- ===== 3. Run again: nothing changes =====
create temp table tlr_before as select f.* from invoice_refunds f;
\ir ../legacy-refunds-backfill.sql
do $$
begin
  if exists (select * from invoice_refunds except select * from tlr_before)
     or exists (select * from tlr_before except select * from invoice_refunds) then
    raise exception 'FAIL 3: a second run changed the refunds'; end if;
  if (select count(*) from audit_logs where action = 'legacy_refund_recorded') <> 9 then
    raise exception 'FAIL 3: a second run audited again'; end if;
  raise notice 'PASS 3: a second run says it is already recorded and changes nothing';
end $$;

rollback;
