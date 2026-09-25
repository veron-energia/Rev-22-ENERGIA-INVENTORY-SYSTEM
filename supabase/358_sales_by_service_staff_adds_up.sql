-- 358_sales_by_service_staff_adds_up.sql
--
-- WHAT WAS WRONG
--
-- The "Sales by Service Staff" report did not add up to revenue. On 24 Sep 2026
-- all-time revenue was S$122,016.30 and the staff column came to S$121,059.29:
--
--   * S$957.00 — invoices with no "Served by" recorded were dropped entirely
--     (INV-2026-0074 S$500 part payment, INV-2026-0185 S$457);
--   * S$0.01  — each person's equal share was a float, rounded on its own.
--
-- Part payments made last month were never moved into this month, and the
-- caption still said receipts used the invoice business date (they have used
-- the payment date since migration 292).
--
-- THE RULE, as the owner decided it:
--   * every dollar of revenue is credited to someone: the invoice's service
--     staff, split equally to the cent, or, when none is recorded, the person
--     who created the invoice;
--   * part payments are credited in the month the money arrives; earlier part
--     payments that were never registered are credited in the current month,
--     the same month their commission is registered (357).
--
-- WHAT THIS DOES
--
--   * invoice_sales_credit_split: who is credited with an amount on an invoice,
--     to the cent. The odd cents go to people in a fixed per-invoice order, so a
--     payment correction reverses its receipt person by person.
--   * invoice_staff_sales_ledger: invoice_sales_ledger() — the same events the
--     "Recognized invoice sales" headline adds up — split to people. It reads
--     that ledger rather than restating it, so it cannot drift from revenue.
--   * report_sales_by_service_staff: the report, server-side, with its own
--     reconciliation: revenue + earlier receipts credited here − receipts
--     credited to another period = staff total, difference always 0.
--   * sales_credit_backfill: the one table that says an invoice's earlier money
--     is credited on a later date than it arrived. Per invoice, so a payment
--     correction or refund dated before the move goes with the receipts.
--     Written only by the part-payment registration.
--   * commission_instalment_backfill (357) now also moves the report credit: the
--     same review lists, per person, the earlier receipts that will be credited
--     this month, and registering records them, so both are registered in the
--     same month. (Later events can still land in different months: a
--     correction dated before the move is credited with the moved receipts,
--     while paid-out commission taken back for it is dated the day it happens.)
--
-- NOT CHANGED
--
--   * invoice_sales_ledger and the revenue headline: read, never changed.
--   * Wallet-credit spend still earns no staff sales credit (the money was
--     counted when the credit was bought). The report shows it as a separate,
--     uncounted figure so the gap is visible. Whether to credit it is the
--     owner's decision.
--   * A cancelled or fully refunded invoice still leaves every period, as it
--     does from revenue (migration 294).
--   * Editing "Served by" still moves the invoice's earlier receipts to the new
--     staff.
--
-- SAFETY
--
-- Needs 357. The one replaced function is guarded by the md5 of its 357
-- version. New functions are internal (service_role) except the report, which
-- checks the caller's role itself.

-- Plain SQL: applies through the Supabase migration tool or the SQL editor as one
-- transaction. From psql, run with -v ON_ERROR_STOP=1.
set lock_timeout = '5s';

do $mig$
begin
  if to_regprocedure('public.commission_instalment_backfill(boolean,date,numeric)') is null
     and to_regprocedure('public.commission_instalment_backfill(boolean,date,numeric,numeric)') is null then
    raise exception '358: apply 357 first'; end if;
end $mig$;

-- ── 1. invoices whose earlier money is credited on a later date ─────────────
-- One row per invoice registered with its commission. Everything on it dated
-- before moved_before (the first day of the registration month) — receipts,
-- payment corrections and refunds, whenever they were recorded — is credited on
-- credited_on. Per invoice, not per payment: a correction recorded later with
-- the original payment's date, or an earlier refund, moves with the receipts,
-- so no month is left holding a reversal without its receipt.
create table if not exists public.sales_credit_backfill (
  invoice_id    uuid primary key references public.invoices(id) on delete cascade,
  moved_before  date not null,
  credited_on   date not null,
  amount        numeric(12,2) not null,
  batch_id      uuid not null,
  reason        text not null,
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  constraint sales_credit_backfill_moves_forward check (credited_on >= moved_before)
);
comment on table public.sales_credit_backfill is
  'An invoice whose revenue dated before moved_before is credited to staff sales on credited_on: part payments registered after the fact (358). Written only by commission_instalment_backfill.';
alter table public.sales_credit_backfill enable row level security;
drop policy if exists "managers read sales credit backfill" on public.sales_credit_backfill;
create policy "managers read sales credit backfill" on public.sales_credit_backfill
  for select to authenticated using (public.is_manager_or_above());
revoke all on public.sales_credit_backfill from anon;
revoke insert, update, delete, truncate on public.sales_credit_backfill from authenticated;

-- ── 2. who is credited with an amount on an invoice, to the cent ────────────
create or replace function public.invoice_sales_credit_split(p_invoice_id uuid, p_amount numeric)
returns table(staff_id uuid, attribution text, share numeric)
language sql stable security definer set search_path = public as $$
  -- 358: service staff, or the creator when none is recorded; shares add up exactly.
  with who as (
    select iss.staff_id, 'service_staff'::text as attribution
      from public.invoice_service_staff iss where iss.invoice_id = p_invoice_id
    union all
    select i.created_by, 'creator'::text
      from public.invoices i
     where i.id = p_invoice_id
       and not exists (select 1 from public.invoice_service_staff x where x.invoice_id = p_invoice_id)
  ), ranked as (
    select w.staff_id, w.attribution,
           row_number() over (order by md5(p_invoice_id::text || w.staff_id::text)) as k,
           count(*) over () as n
      from who w
  )
  select r.staff_id, r.attribution,
         round(sign(p_amount) * ((c.cents / r.n) + case when r.k <= c.cents % r.n then 1 else 0 end) / 100.0, 2)
    from ranked r cross join (select round(abs(p_amount) * 100)::bigint as cents) c
$$;

-- ── 3. the revenue ledger, split to people ──────────────────────────────────
create or replace function public.invoice_staff_sales_ledger()
returns table(invoice_id uuid, event_id uuid, event_kind text, sales_date date, credited_on date,
              staff_id uuid, attribution text, staff_count integer, event_amount numeric, amount numeric)
language sql stable security definer set search_path = public as $$
  -- 358: reads invoice_sales_ledger(), so revenue here is revenue on the headline.
  select l.invoice_id, l.event_id, l.event_kind, l.sales_date,
         case when b.invoice_id is not null and l.sales_date < b.moved_before then b.credited_on else l.sales_date end,
         s.staff_id, s.attribution, (count(*) over (partition by l.event_id))::integer, l.amount, s.share
    from public.invoice_sales_ledger() l
    left join public.sales_credit_backfill b on b.invoice_id = l.invoice_id
    cross join lateral public.invoice_sales_credit_split(l.invoice_id, l.amount) s
$$;

-- ── 4. the report ───────────────────────────────────────────────────────────
-- The period is the date each receipt is credited: the day the money arrived,
-- or the registration date for an earlier part payment.
create or replace function public.report_sales_by_service_staff(
  p_from date default null, p_to date default null, p_store_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- 358
declare v jsonb;
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner, Admin or Manager can view sales by service staff'; end if;
  with sl as (
    select s.* from public.invoice_staff_sales_ledger() s
      join public.invoices i on i.id = s.invoice_id
     where p_store_id is null or i.store_id = p_store_id
  ), inp as (
    select sl.*,
           (p_from is null or sl.sales_date  >= p_from) and (p_to is null or sl.sales_date  <= p_to) as sold_in,
           (p_from is null or sl.credited_on >= p_from) and (p_to is null or sl.credited_on <= p_to) as credited_in
      from sl
  ), ev as (
    select distinct on (inp.event_id) inp.event_id, inp.event_amount, inp.sold_in, inp.credited_in from inp
  ), per_inv as (
    select inp.staff_id, inp.invoice_id, sum(inp.amount) as credited, sum(inp.event_amount) as touched,
           bool_or(inp.attribution = 'creator') as via_creator
      from inp where inp.credited_in group by inp.staff_id, inp.invoice_id
  ), per_staff as (
    select pi.staff_id, p.full_name as staff_name, coalesce(p.is_active, true) as is_active,
           count(*) filter (where pi.credited > 0) as invoices_served,
           sum(pi.credited) as shared_sales,
           sum(pi.touched) as receipts_on_invoices_served,
           coalesce(sum(pi.credited) filter (where pi.via_creator), 0) as credited_as_creator,
           coalesce((select sum(x.amount) from inp x
                      where x.credited_in and not x.sold_in and x.staff_id = pi.staff_id), 0) as backfilled_in
      from per_inv pi left join public.profiles p on p.id = pi.staff_id
     group by pi.staff_id, p.full_name, p.is_active
  )
  select jsonb_build_object(
    'basis', 'Money received, on the day it was received (refunds on the refund date), split equally to the cent among the invoice''s service staff, or credited to the person who created the invoice when none is recorded. Earlier part payments registered later are credited on the registration date. Wallet-credit spend is not counted.',
    'from', p_from, 'to', p_to, 'store_id', p_store_id,
    'revenue',      (select coalesce(sum(ev.event_amount), 0) from ev where ev.sold_in),
    'backfill_in',  (select coalesce(sum(ev.event_amount), 0) from ev where ev.credited_in and not ev.sold_in),
    'backfill_out', (select coalesce(sum(ev.event_amount), 0) from ev where ev.sold_in and not ev.credited_in),
    'staff_total',  (select coalesce(sum(ps.shared_sales), 0) from per_staff ps),
    'credited_as_creator', (select coalesce(sum(ps.credited_as_creator), 0) from per_staff ps),
    -- Information only: purchases paid with wallet credit in the period.
    'wallet_credit_not_counted', (
      select coalesce(sum(case when pay.entry_kind = 'correction_reversal' then -pay.amount else pay.amount end), 0)
        from public.invoice_payments pay
        join public.payment_methods m on m.id = pay.payment_method_id
        join public.invoices i on i.id = pay.invoice_id
       where coalesce(m.is_wallet_credit, false)
         and i.deleted_at is null and public.invoice_counts_as_sale(i.status::text)
         and public.user_has_store_access(i.store_id)
         and (p_store_id is null or i.store_id = p_store_id)
         and (p_from is null or public.payment_sales_date(pay.effective_at, pay.created_at) >= p_from)
         and (p_to   is null or public.payment_sales_date(pay.effective_at, pay.created_at) <= p_to)),
    'rows', coalesce((select jsonb_agg(to_jsonb(ps) order by ps.shared_sales desc, ps.staff_name) from per_staff ps), '[]'::jsonb))
  into v;
  return v || jsonb_build_object('difference',
    (v->>'staff_total')::numeric - ((v->>'revenue')::numeric + (v->>'backfill_in')::numeric - (v->>'backfill_out')::numeric));
end $$;

-- ── 5. registering earlier part payments also moves their staff-sales credit ──
-- Receipts that arrived before this month, on invoices still being paid, are
-- credited to staff sales on the registration date — the same invoices and the
-- same month as their commission. The review lists them per person (ledger
-- 'sales'), and registering needs their total back too.
do $mig$
declare v_md5 text;
begin
  if to_regprocedure('public.commission_instalment_backfill(boolean,date,numeric,numeric)') is not null then
    raise notice '358: commission_instalment_backfill already moves staff-sales credit; left alone.'; return; end if;
  v_md5 := md5(pg_get_functiondef('public.commission_instalment_backfill(boolean,date,numeric)'::regprocedure));
  if v_md5 <> '1660570c8c678a13f0a3e4de92d0c12d' then
    raise exception '358: commission_instalment_backfill is not the 357 version this was tested against (md5 %)', v_md5; end if;
  drop function public.commission_instalment_backfill(boolean,date,numeric);
end $mig$;

create or replace function public.commission_instalment_backfill(
  p_apply boolean default false, p_credit_date date default null,
  p_expected_total numeric default null, p_expected_sales numeric default null)
returns table(ledger text, beneficiary_id uuid, beneficiary_name text, invoice_id uuid, invoice_no text,
              earned_amount numeric, blocked_amount numeric, credit_date date)
language plpgsql security definer set search_path = public as $$
-- 357, 358: commission on earlier part payments, and their staff-sales credit.
declare v_date date := coalesce(p_credit_date, public.sg_today()); v_rows jsonb := '[]'::jsonb;
        v_total numeric; v_sales_total numeric; v_inv record; v_one jsonb; v_moves jsonb; v_batch uuid := gen_random_uuid();
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner, Admin or Manager can review part-payment commission'; end if;
  if p_apply then
    if not public.is_owner_or_manager() then
      raise exception 'Only an Owner or Manager can register part-payment commission'; end if;
    if date_trunc('month', v_date::timestamp) <> date_trunc('month', public.sg_today()::timestamp)
       or v_date > public.sg_today() then
      raise exception 'The credit date must be in the current month and not later than today'; end if;
    -- One registration at a time.
    perform 1 from public.app_settings a where a.id = true for update;
  end if;
  -- Registered once. After that every part payment earns and counts as it
  -- arrives, and there is nothing earlier left to register.
  if (select a.instalment_commission_from from public.app_settings a where a.id = true) is not null then
    if p_apply then
      raise exception 'Part-payment commission is already on; there is nothing earlier left to register.'; end if;
    return;
  end if;

  -- Registering locks every invoice it will touch first, in one fixed order,
  -- before it takes any commission lock: a part payment recorded meanwhile then
  -- waits for its invoice instead of deadlocking with the loop below.
  if p_apply then
    perform 1 from public.invoices x
     where public.invoice_instalment_commission_active(x.id)
     order by x.id for update;
  end if;

  -- Commission: bring every invoice still being paid to its target.
  for v_inv in select x.id, x.invoice_no from public.invoices x
                where public.invoice_instalment_commission_active(x.id) order by x.invoice_no loop
    select coalesce(jsonb_agg(jsonb_build_object('ledger', s.o_ledger, 'beneficiary', s.o_beneficiary,
             'invoice_id', v_inv.id, 'invoice_no', v_inv.invoice_no, 'status', s.o_status, 'amount', s.o_amount)), '[]'::jsonb)
      into v_one
      from public.sync_instalment_commissions(v_inv.id, 'Earlier part payments registered', v_date, true, true) s;
    v_rows := v_rows || v_one;
  end loop;
  select coalesce(sum((e->>'amount')::numeric) filter (where e->>'status' = 'earned'), 0) into v_total
    from jsonb_array_elements(v_rows) e;

  -- Staff sales: everything dated before this month on the invoices still
  -- being paid (receipts, corrections, refunds), per person, not yet moved.
  select coalesce(jsonb_agg(jsonb_build_object('invoice_id', e.invoice_id, 'invoice_no', i.invoice_no,
           'staff_id', e.staff_id, 'amount', e.amount)), '[]'::jsonb)
    into v_moves
    from public.invoice_staff_sales_ledger() e
    join public.invoices i on i.id = e.invoice_id
   where public.invoice_instalment_commission_active(e.invoice_id)
     and e.sales_date < date_trunc('month', v_date::timestamp)::date
     and not exists (select 1 from public.sales_credit_backfill b where b.invoice_id = e.invoice_id);
  select coalesce(sum((e->>'amount')::numeric), 0) into v_sales_total from jsonb_array_elements(v_moves) e;

  if p_apply then
    if p_expected_total is null or round(p_expected_total, 2) <> round(v_total, 2) then
      raise exception 'The part-payment total is now %, not the % that was reviewed. Run the review again.',
        round(v_total, 2), p_expected_total; end if;
    if round(coalesce(p_expected_sales, 0), 2) <> round(v_sales_total, 2) then
      raise exception 'The earlier receipts to credit now total %, not the % that was reviewed. Run the review again.',
        round(v_sales_total, 2), coalesce(p_expected_sales, 0); end if;
    for v_inv in select distinct (e->>'invoice_id')::uuid as id from jsonb_array_elements(v_rows) e loop
      perform * from public.sync_instalment_commissions(v_inv.id, 'Earlier part payments registered', v_date, false, true);
    end loop;
    insert into public.sales_credit_backfill(invoice_id, moved_before, credited_on, amount, batch_id, reason, created_by)
    select m.invoice_id, date_trunc('month', v_date::timestamp)::date, v_date, sum(m.amount),
           v_batch, 'Part payments received before this month, registered with their commission', auth.uid()
      from jsonb_to_recordset(v_moves) as m(invoice_id uuid, amount numeric)
     group by m.invoice_id
    -- (named constraint: invoice_id is also this function's output column)
    on conflict on constraint sales_credit_backfill_pkey do nothing;
    update public.app_settings a set instalment_commission_from = coalesce(a.instalment_commission_from, v_date)
     where a.id = true;
    perform public.write_audit_ex('commissions', null, 'instalment_commission_backfilled', null,
      jsonb_build_object('credit_date', v_date, 'earned_total', v_total,
                         'invoices', (select count(distinct e->>'invoice_id') from jsonb_array_elements(v_rows) e),
                         'sales_invoices_moved', (select count(distinct e->>'invoice_id') from jsonb_array_elements(v_moves) e),
                         'sales_total_moved', v_sales_total,
                         'batch_id', v_batch),
      'commission', 'Earlier part payments registered; part payments now earn as they arrive', null);
  end if;

  return query
    select q.ledger, q.beneficiary,
           case when q.ledger = 'affiliate' then (select c.full_name from public.customers c where c.id = q.beneficiary)
                else (select p.full_name from public.profiles p where p.id = q.beneficiary) end,
           q.invoice_id, q.invoice_no, q.earned, q.blocked, v_date
      from (select e.ledger, e.beneficiary, e.invoice_id, e.invoice_no,
                   coalesce(sum(e.amount) filter (where e.status = 'earned'), 0) as earned,
                   coalesce(sum(e.amount) filter (where e.status = 'blocked'), 0) as blocked
              from jsonb_to_recordset(v_rows) as e(ledger text, beneficiary uuid, invoice_id uuid, invoice_no text, status text, amount numeric)
             group by e.ledger, e.beneficiary, e.invoice_id, e.invoice_no
            union all
            select 'sales'::text, m.staff_id, m.invoice_id, m.invoice_no, sum(m.amount), 0::numeric
              from jsonb_to_recordset(v_moves) as m(invoice_id uuid, invoice_no text, staff_id uuid, amount numeric)
             group by m.staff_id, m.invoice_id, m.invoice_no) q
     -- A total order, so the page can read it in pages of 1,000.
     order by q.ledger, 3, q.beneficiary, q.invoice_no, q.invoice_id;
end $$;

-- ── 6. grants ───────────────────────────────────────────────────────────────
revoke all on function public.invoice_sales_credit_split(uuid,numeric) from public, anon, authenticated;
revoke all on function public.invoice_staff_sales_ledger() from public, anon, authenticated;
revoke all on function public.report_sales_by_service_staff(date,date,uuid) from public, anon, authenticated;
revoke all on function public.commission_instalment_backfill(boolean,date,numeric,numeric) from public, anon, authenticated;
grant execute on function public.invoice_sales_credit_split(uuid,numeric) to service_role;
grant execute on function public.invoice_staff_sales_ledger() to service_role;
grant execute on function public.report_sales_by_service_staff(date,date,uuid) to authenticated, service_role;
grant execute on function public.commission_instalment_backfill(boolean,date,numeric,numeric) to authenticated, service_role;

-- ── 7. guards ───────────────────────────────────────────────────────────────
do $mig$
begin
  if to_regprocedure('public.commission_instalment_backfill(boolean,date,numeric)') is not null then
    raise exception '358: the 357 backfill signature is still present'; end if;
  if has_function_privilege('anon', 'public.report_sales_by_service_staff(date,date,uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.invoice_staff_sales_ledger()', 'execute')
     or has_function_privilege('anon', 'public.commission_instalment_backfill(boolean,date,numeric,numeric)', 'execute') then
    raise exception '358: grants are wider than intended'; end if;
  -- The split adds up exactly, whatever the amount and head count.
  if exists (select 1 from (values (10.00), (10.01), (-0.01), (0.02), (1234.57)) a(amt)
              where (select sum(s.share) from public.invoice_sales_credit_split(
                       (select id from public.invoices limit 1), a.amt) s) is distinct from a.amt
                and exists (select 1 from public.invoices)) then
    raise exception '358: invoice_sales_credit_split does not add up'; end if;
end $mig$;
