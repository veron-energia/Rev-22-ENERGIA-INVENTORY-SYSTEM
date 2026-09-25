-- 357_part_payments_earn_commission.sql
--
-- WHAT WAS WRONG
--
-- Staff and affiliate commission were earned only when an invoice was paid in
-- full. A customer paying $2,000 of a $5,000 invoice earned nobody anything
-- until the last dollar arrived, which could be months later.
--
-- One path did earn early, and it paid twice. Correcting a payment on a
-- part-paid invoice ran reconcile_invoice_commissions, which re-earned full
-- commission on whatever had arrived; settlement then earned the full amount
-- again on top. It is live: INV-2026-0282 carries 3 x S$8.32 from a payment
-- correction on 24 Sep 2026, and settling it would add the full 3% again.
--
-- THE RULE, as the owner decided it:
--   * money received in part earns staff and affiliate commission as it
--     arrives, on the same rules full settlement uses;
--   * part payments that were never registered are registered once, in the
--     current month, after the owner has read the dry-run totals.
--
-- WHAT THIS DOES
--
-- Commission is kept in two layers, marked by a new earning_basis column on
-- staff_commissions and commissions:
--
--   settlement  what exists today, written by the existing earn functions when
--               an invoice is fully paid.
--   instalment  while an invoice is still being paid (not fully paid, whether
--               or not it settled before): commission on the money received.
--               Each change is a new row dated the day it is registered
--               (Singapore date). Nothing already paid out is ever edited.
--
-- STAFF. A part payment's staff share goes to the store's commission staff on
-- the day it is registered, and stays with them. When the invoice is fully
-- paid, earn_staff_commission pays that day's roster only the rest of the pool
-- (the pool on the money received, less what part payments registered). The
-- invoice total is exactly the pool, and each person keeps what was theirs
-- when the money arrived.
--
-- AFFILIATES. The same referrers are paid either way, so at full payment the
-- instalment rows close with one negative row per beneficiary in that month
-- and settlement writes the full amount: part payments count in their months,
-- the rest lands when the invoice is paid, and the total is exactly what full
-- settlement pays.
--
-- MONEY LEAVING (a refund, a removed or lowered payment, a cancellation)
-- takes back unpaid part-payment commission where it stands, newest first: a
-- row is reversed, or, when only part of it goes (or part of it was already
-- paid out), the unpaid part is taken back in that row's own month. Only what
-- was already paid out is taken back as a new row, dated the day it happens.
-- (Rows do not record which payment earned them, so when an older payment is
-- removed while a newer one stands, the newest commission is what goes.) A
-- cancelled or refunded invoice squares every month: each part-payment row's
-- effect is removed in its own month, and only what was paid out is taken back
-- today, so a cancelled sale never leaves a payable balance.
--
-- Wallet credit never earns, as today.
--
-- A trigger on invoices (status or paid_amount changed) keeps the instalment
-- layer in step on every money path: part payment, final payment, correction,
-- removal, split, refund, cancel, reopen, FOC. reconcile_invoice_commissions
-- also syncs, for changes that move neither (a line or affiliate correction).
--
-- THE SWITCH (app_settings.instalment_commission_from)
--
-- Off until the owner applies the backfill. While off, invoices still being
-- paid gain nothing new, but closing still runs, so nothing can double-earn.
-- commission_instalment_backfill(false) is the dry run: per staff member and
-- per affiliate, per invoice, what would be registered. Applying it needs that
-- total back (refused if anything moved since), registers it dated in the
-- current month, and turns the switch on.
--
-- ALSO CHANGED
--
--   * reconcile_invoice_commissions: its reversals and payout adjustments
--     touch the settlement layer only, and it never earns settlement
--     commission on an invoice that is not fully paid (the double-pay path,
--     including a settled invoice that falls back to part-paid).
--   * earn_staff_commission: pays only the part of the pool part payments did
--     not already register.
--   * reearn_invoice_staff_commission / preview_commission_rebase_effect: the
--     staff rebase works on the settlement layer only, on what is left after
--     the part-payment shares.
--   * create_exchange_invoice: an exchange top-up received in part earns on
--     what arrived (the replacement invoice is inserted, not updated, so the
--     trigger cannot see it).
--   * invoice_record_payments_internal: an invoice that settled before, fell
--     back and is paid in full again, or that had money refunded while it was
--     part-paid, settles through reconcile, so its package and bundle
--     commission is earned again and line refunds count (before, Record Payment
--     earned only invoice lines and staff, on the unrefunded lines).
--
-- DATA IN THIS MIGRATION (section 11)
--
-- Commission rows already sitting on invoices still being paid were
-- written by the double-pay path. They are relabelled 'instalment'; amounts do
-- not change. In production today that is exactly the 3 staff rows on
-- INV-2026-0282 (S$24.96). Without it, settling that invoice pays them twice.
--
-- NOT CHANGED
--
--   * The settlement rules themselves (rates, tiers, eligibility, who shares).
--   * Package and bundle commission still does not check whether the referrer
--     is an activated affiliate (a separate open question for the owner); the
--     instalment layer mirrors it rather than deciding it.
--   * package_commission_diagnostic would now list a settled bundle's
--     instalment rows beside its settlement row. It is left alone because it
--     cannot be re-created as it stands: it reads credit_package_sales.created_at,
--     a column that table does not have (it has sold_at), so every call already
--     fails, in production too. Its own fix, separately.
--   * Settlement rows are still dated coalesce(paid_at, now())::date, the UTC
--     date, while the instalment close uses the Singapore date. A settlement
--     between 00:00 and 07:59 on the 1st splits across two months; totals stay
--     right.
--
-- SAFETY
--
-- Every patched function is guarded by the md5 of the production version it
-- was tested against, and carries a '357:' marker so a re-run leaves it alone.
-- New functions are granted to service_role only, except the backfill, which
-- checks the caller's role itself.

-- Plain SQL: applies through the Supabase migration tool or the SQL editor as one
-- transaction. From psql, run with -v ON_ERROR_STOP=1.
set lock_timeout = '5s';

-- ── 1. the two layers, and the switch ───────────────────────────────────────
alter table public.staff_commissions
  add column if not exists earning_basis text not null default 'settlement';
alter table public.commissions
  add column if not exists earning_basis text not null default 'settlement';
do $mig$
begin
  if not exists (select 1 from pg_constraint where conname = 'staff_commissions_earning_basis_check') then
    alter table public.staff_commissions add constraint staff_commissions_earning_basis_check
      check (earning_basis in ('settlement','instalment'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'commissions_earning_basis_check') then
    alter table public.commissions add constraint commissions_earning_basis_check
      check (earning_basis in ('settlement','instalment'));
  end if;
end $mig$;
comment on column public.staff_commissions.earning_basis is
  'settlement: earned when the invoice settled. instalment: earned on part payments while it was still being paid; closes to zero when it settles (357).';
comment on column public.commissions.earning_basis is
  'settlement: earned when the invoice settled. instalment: earned on part payments while it was still being paid; closes to zero when it settles (357).';

alter table public.app_settings
  add column if not exists instalment_commission_from date;
comment on column public.app_settings.instalment_commission_from is
  'Null: part payments earn nothing new yet (357). Set by commission_instalment_backfill when the owner registers earlier part payments; from then on part payments earn as they arrive.';

-- ── 2. the affiliate commission settlement would write, without writing it ──
-- Derived from earn_invoice_commission's own text so the rules are the same
-- rules: each of its six inserts becomes a returned row, its audit is dropped.
do $mig$
declare d text; n int; v_md5 text;
begin
  v_md5 := md5(pg_get_functiondef('public.earn_invoice_commission(uuid)'::regprocedure));
  if v_md5 <> '2e4942e9ff859b0469fdcd99faf325fd' then
    raise exception '357: earn_invoice_commission is not the version this was tested against (md5 %). Re-derive the preview against it before applying.', v_md5; end if;

  d := pg_get_functiondef('public.earn_invoice_commission(uuid)'::regprocedure);
  d := replace(d, 'FUNCTION public.earn_invoice_commission(p_invoice_id uuid)',
                  'FUNCTION public.invoice_affiliate_commission_preview(p_invoice_id uuid)');
  d := replace(d, 'RETURNS void',
    'RETURNS TABLE(o_invoice_item_id uuid, o_buyer uuid, o_referrer uuid, o_tier text, o_product_type text, o_line_amount numeric, o_rate numeric, o_amount numeric, o_status text, o_block_reason text)');
  n := (length(d) - length(replace(d, 'insert into public.commissions', ''))) / length('insert into public.commissions');
  if n <> 6 then raise exception '357: expected 6 commission inserts in earn_invoice_commission, found %', n; end if;
  d := regexp_replace(d,
    'insert into public\.commissions \(invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date\)\s*values \(p_invoice_id, ',
    'return query select ', 'g');
  n := (length(d) - length(replace(d, ', v_paid_date);', ''))) / length(', v_paid_date);');
  if n <> 6 then raise exception '357: expected 6 dated inserts, found %', n; end if;
  d := replace(d, ', v_paid_date);', ';');
  d := replace(d, '::commission_status', '::text');
  d := regexp_replace(d, 'perform public\.write_audit\(''commissions''.*?\);', '', 's');
  if d ~* 'insert into|write_audit|update public|delete from' then
    raise exception '357: the derived preview still writes'; end if;
  d := replace(d, 'AS $function$', E'AS $function$\n-- 357: derived from earn_invoice_commission (md5 2e4942e9ff859b0469fdcd99faf325fd). Writes nothing.');
  execute d;
end $mig$;

-- ── 3. package and bundle lines, while the invoice is being paid ────────────
-- Mirrors earn_credit_package_commission / earn_premium_bundle_commission,
-- which run only once the sale exists (at settlement). Basis = the line's
-- external value, the money the line is sold for. Lines already issued count
-- too: an invoice that settled and fell back to part-paid has had its
-- settlement rows reversed or offset, and the money it still holds earns here
-- like any other line's (it is only ever read while the invoice is being paid).
create or replace function public.invoice_package_commission_preview(p_invoice_id uuid)
returns table(o_invoice_item_id uuid, o_buyer uuid, o_referrer uuid, o_tier text, o_product_type text,
              o_line_amount numeric, o_rate numeric, o_amount numeric, o_status text, o_block_reason text)
language plpgsql stable security definer set search_path = public as $$
-- 357: what package/bundle settlement commission is, for the instalment layer.
declare v_inv public.invoices%rowtype; v_it record; v_t1 uuid; v_t2 uuid; v_cls text;
        v_r1 numeric; v_r2 numeric; v_base numeric; v_a1 numeric; v_a2 numeric;
begin
  select * into v_inv from public.invoices i where i.id = p_invoice_id;
  if not found then return; end if;
  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return; end if;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    select c.referred_by into v_t1 from public.customers c where c.id = v_inv.customer_id;
  end if;
  if v_t1 is null or v_t1 = v_inv.customer_id then return; end if;
  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;
  v_cls := public.package_commission_classification();

  for v_it in
    select ii.id as item_id, coalesce(cp.tier1_rate, pb.tier1_rate) as def_r1,
           coalesce(cp.tier2_rate, pb.tier2_rate) as def_r2
      from public.invoice_items ii
      left join public.credit_packages cp on cp.id = ii.credit_package_id
      left join public.premium_bundles pb on pb.id = ii.premium_bundle_id
     where ii.invoice_id = p_invoice_id
       and ii.line_kind in ('credit_package','premium_bundle')
       -- A legacy one-line split issues to several customers; it earns at settlement.
       and not exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = ii.id)
     order by ii.id
  loop
    select coalesce(v_it.def_r1, case when v_cls = 'third_party' then a.commission_tier1_third_rate else a.commission_tier1_own_rate end),
           coalesce(v_it.def_r2, case when v_cls = 'third_party' then a.commission_tier2_third_rate else a.commission_tier2_own_rate end)
      into v_r1, v_r2 from public.app_settings a where a.id = true;
    v_base := public.invoice_item_external_value(v_it.item_id);
    v_a1 := round(v_base * v_r1 / 100.0, 2);
    if coalesce(v_a1, 0) <= 0 then continue; end if;
    -- 'earned', as the package functions record it today (they do not check activation).
    return query select v_it.item_id, v_inv.customer_id, v_t1, 'tier1'::text, v_cls, v_base, v_r1, v_a1, 'earned'::text, null::text;
    if v_t2 is not null then
      v_a2 := round(v_a1 * v_r2 / 100.0, 2);
      if v_a2 > 0 then
        return query select v_it.item_id, v_inv.customer_id, v_t2, 'tier2'::text, v_cls, v_a1, v_r2, v_a2, 'earned'::text, null::text;
      end if;
    end if;
  end loop;
end $$;

-- ── 4. is the invoice still being paid? ─────────────────────────────────────
-- Still being paid = not fully paid, whether or not it settled before. An
-- invoice that settled and then fell back (a bounced payment removed, a payment
-- corrected down, a reopen below its total) is being paid again: its settlement
-- rows are reversed or offset by reconcile, and the part it still holds earns on
-- the instalment layer, so paying the rest cannot pay commission twice.
-- A cancellation or refund request on a FULLY paid invoice keeps it settled.
create or replace function public.invoice_instalment_commission_active(p_invoice_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  -- 357
  select coalesce((
    select i.deleted_at is null
       and (i.status::text in ('draft','unpaid','partially_paid')
            or (i.status::text in ('cancellation_requested','refund_requested')
                and public.invoice_net_received(i.id) < public.invoice_charge_total(i.id) - 0.001))
      from public.invoices i where i.id = p_invoice_id), false)
$$;

-- ── 5. what the instalment layer should hold now ────────────────────────────
-- Pure. Staff: one pool for the invoice, cash received x the staff rate (who
-- shares it is decided when each change lands). Affiliate: exactly what
-- settlement would write, scaled by cash received / cash due. Multiplied
-- before dividing, so rounding matches a single calculation.
create or replace function public.invoice_instalment_commission_targets(p_invoice_id uuid)
returns table(ledger text, beneficiary uuid, tier text, product_type text, invoice_item_id uuid,
              status text, rate numeric, base numeric, amount numeric, block_reason text)
language plpgsql stable security definer set search_path = public as $$
-- 357
declare v_recv numeric; v_due numeric; v_rate numeric;
begin
  if not public.invoice_instalment_commission_active(p_invoice_id) then return; end if;
  v_recv := coalesce(public.invoice_commission_basis(p_invoice_id), 0);
  if v_recv <= 0 then return; end if;
  v_due := public.invoice_charge_total(p_invoice_id)
           - coalesce((select sum(a.amount - a.reversed_amount) from public.invoice_line_credit_allocations a
                        where a.invoice_id = p_invoice_id), 0);

  select coalesce(a.staff_commission_rate, 0) into v_rate from public.app_settings a where a.id = true;
  if v_rate > 0 then
    return query select 'staff'::text, null::uuid, null::text, null::text, null::uuid, 'earned'::text,
      v_rate, v_recv, round(v_recv * v_rate / 100.0, 2), null::text;
  end if;

  if v_due <= 0 then return; end if;
  if v_recv > v_due then v_recv := v_due; end if;
  -- A refunded part of a line earns nothing, exactly as
  -- adjust_invoice_line_commission_refunds lowers settlement: each line's rows
  -- keep (line base - refunded) / line base, before scaling by money received
  -- (cash due already excludes the refund).
  return query
    with p as (select * from public.invoice_affiliate_commission_preview(p_invoice_id)
               union all
               select * from public.invoice_package_commission_preview(p_invoice_id)),
         line_base as (select p.o_invoice_item_id as item, sum(p.o_line_amount) as item_base
                         from p where p.o_tier = 'tier1' and p.o_invoice_item_id is not null
                        group by p.o_invoice_item_id),
         refunded as (select (l.value->>'invoice_item_id')::uuid as item, sum((l.value->>'amount')::numeric) as refunded_amt
                        from public.invoices i
                        join public.invoice_refunds r on r.invoice_id = i.id
                                                     and (i.reopened_at is null or r.created_at > i.reopened_at)
                        cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]'::jsonb)) l
                       where i.id = p_invoice_id and nullif(l.value->>'invoice_item_id', '') is not null
                         and not coalesce((l.value->>'overpayment')::boolean, false)
                       group by 1),
         kept as (select lb.item,
                         case when lb.item_base > 0
                              then greatest(0, lb.item_base - coalesce(rf.refunded_amt, 0)) / lb.item_base
                              else 1 end as share
                    from line_base lb left join refunded rf on rf.item = lb.item)
    select 'affiliate'::text, p.o_referrer, p.o_tier, p.o_product_type, p.o_invoice_item_id, p.o_status, p.o_rate,
           round(p.o_line_amount * coalesce(k.share, 1) * v_recv / v_due, 2),
           round(p.o_amount * coalesce(k.share, 1) * v_recv / v_due, 2), p.o_block_reason
      from p left join kept k on k.item = p.o_invoice_item_id;
end $$;

-- ── 5b. what of an affiliate commission row is still payable ────────────────
create or replace function public.commission_unpaid_amount(p_commission_id uuid)
returns numeric language sql stable security definer set search_path = public as $$
  -- 357: the row's amount, less the adjustments linked to it, less what payouts
  -- allocated to it (affiliate_payout_save's own measure). A row marked paid
  -- with no allocation recorded counts as fully paid.
  select case when (c.status::text = 'paid' or c.payout_id is not null)
                   and not exists (select 1 from public.commission_payout_allocations pa where pa.commission_id = c.id)
              then 0
              else c.commission_amount
                   + coalesce((select sum(adj.commission_amount) from public.commissions adj
                                where adj.adjusts_commission_id = c.id and adj.status::text in ('earned','paid')), 0)
                   - coalesce((select sum(pa.amount) from public.commission_payout_allocations pa
                                where pa.commission_id = c.id), 0)
         end
    from public.commissions c where c.id = p_commission_id
$$;

-- ── 5c. both commission write locks, in settlement's order ─────────────────
create or replace function public.commission_write_locks()
returns boolean language plpgsql security definer set search_path = public as $$
-- 357: the affiliate lock, then the staff lock (re-entrant within a transaction).
begin
  perform public.affiliate_payout_lock();
  perform public.staff_payout_lock();
  return true;
end $$;

-- ── 6. bring the instalment layer to its target ─────────────────────────────
-- Staff: while an invoice is being paid the layer holds the staff pool on the
-- money received; each increase is shared by the store's commission staff on
-- the day it lands, and STAYS with them. When the invoice settles, settlement
-- pays the roster only the rest of the pool (earn_staff_commission, below).
-- Affiliates: the layer holds what settlement would pay x the share received;
-- at settlement it closes with a new negative row per beneficiary and
-- settlement writes the full amount to the same people.
-- Money leaving (a refund, a removed or lowered payment, a cancellation) takes
-- back UNPAID commission where it stands, newest date first (staff: shared by
-- the unpaid holders on that date in proportion; affiliates: the row reversed,
-- or a linked negative row in the row's own month); only the part already
-- paid out is taken back as a new row dated today. Rows do not record which
-- payment earned them: when an OLDER payment is removed while a newer one
-- stands, the newer commission is what goes. A cancelled or refunded invoice
-- squares every month (see the affiliate block below).
-- Every change is dated the day it is recorded (Singapore date), as settlement
-- is: a part payment recorded with an earlier payment date earns on the day it
-- is recorded, while its staff-sales credit (358) follows the payment date.
-- Every change is dated p_credit_date (default: today in Singapore). At target
-- it writes nothing. p_register overrides the switch (the backfill); otherwise
-- the switch decides whether an invoice still being paid may gain.
create or replace function public.sync_instalment_commissions(
  p_invoice_id uuid, p_reason text, p_credit_date date default null,
  p_dry_run boolean default false, p_register boolean default null)
returns table(o_ledger text, o_beneficiary uuid, o_tier text, o_product_type text, o_item uuid,
              o_status text, o_amount numeric, o_date date)
language plpgsql security definer set search_path = public as $$
-- 357
declare
  v_inv public.invoices%rowtype;
  v_date date := coalesce(p_credit_date, public.sg_today());
  v_active boolean; v_closed boolean; v_grow boolean; v_targets jsonb;
  v_target numeric; v_rate numeric; v_rec numeric; v_delta numeric; v_staff_delta numeric := 0;
  v_n integer; v_cents bigint; v_k integer; v_need numeric; v_wrote integer := 0;
  v_gone uuid[] := '{}'; v_holders numeric; v_take numeric; dt record;
  v_blocked_now text; v_blocked_want text;
  s record; r record;
begin
  if p_dry_run then
    select * into v_inv from public.invoices i where i.id = p_invoice_id;
  else
    select * into v_inv from public.invoices i where i.id = p_invoice_id for update;
  end if;
  if not found then return; end if;

  v_active := public.invoice_instalment_commission_active(p_invoice_id);
  v_closed := v_inv.deleted_at is not null or v_inv.status::text in ('cancelled','refunded');
  -- Nearly every invoice settles in one payment: nothing to hold, nothing held.
  if not v_active
     and coalesce((select sum(sc.commission_amount) from public.staff_commissions sc
                    where sc.invoice_id = p_invoice_id and sc.earning_basis = 'instalment'
                      and sc.status in ('earned','paid')), 0) = 0
     and not exists (select 1 from public.commissions c
                      where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment'
                        and c.status in ('earned','paid')
                      group by c.referrer_customer_id, c.tier, c.product_type, c.invoice_item_id
                     having sum(c.commission_amount) <> 0)
     and not exists (select 1 from public.commissions c
                      where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment' and c.status = 'blocked')
     -- A cancelled or refunded invoice whose rows net to zero may still hold
     -- part-payment commission payable in an earlier month (squared below).
     and not (v_closed and exists (
           select 1 from public.commissions c
            where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment'
              and c.status in ('earned','paid') and c.adjusts_commission_id is null
              and coalesce(c.reversal_reason, '') not like 'Part-payment commission squared%'
              and coalesce(c.reversal_reason, '') not like 'Paid-out part-payment commission taken back%'
              and ((c.commission_amount > 0 and public.commission_unpaid_amount(c.id) > 0)
                   or (c.commission_amount < 0
                       and not exists (select 1 from public.commissions adj where adj.adjusts_commission_id = c.id
                                        and adj.status in ('earned','paid'))))))
  then return; end if;

  -- Every write to commissions / staff_commissions takes a global advisory lock
  -- (affiliate_payout_lock / staff_payout_lock, from their table triggers).
  -- Settlement and reconcile take the affiliate lock first; this writes staff
  -- rows first. So each write below first takes both, in settlement's order
  -- (commission_write_locks), or a part payment and a settlement in another
  -- store could deadlock. Only when something is written: a sync that changes
  -- nothing takes no global lock.

  v_grow := coalesce(p_register,
                     (select a.instalment_commission_from is not null from public.app_settings a where a.id = true),
                     false);
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_targets
    from public.invoice_instalment_commission_targets(p_invoice_id) t;

  -- ---------- staff: one pool per invoice ----------
  select coalesce(sum(sc.commission_amount), 0) into v_rec
    from public.staff_commissions sc
   where sc.invoice_id = p_invoice_id and sc.earning_basis = 'instalment' and sc.status in ('earned','paid');
  select coalesce(a.staff_commission_rate, 0) into v_rate from public.app_settings a where a.id = true;
  if v_active then
    select coalesce(sum(t.amount), 0) into v_target
      from jsonb_to_recordset(v_targets) as t(ledger text, amount numeric) where t.ledger = 'staff';
    if not v_grow then v_target := least(v_target, v_rec); end if;
  elsif v_closed then
    v_target := 0;
  else
    -- Settled: what part payments registered stays with those staff; it only
    -- shrinks if the money itself fell below it.
    v_target := least(v_rec, round(coalesce(public.invoice_commission_basis(p_invoice_id), 0) * v_rate / 100.0, 2));
  end if;
  v_delta := round(v_target - v_rec, 2);

  if v_delta > 0 then
    -- New money: shared to the cent by the store's commission staff on the day
    -- it lands, the odd cents going one each to the first staff by id.
    v_n := public.store_commission_staff_count(v_inv.store_id);
    if v_n = 0 then
      if not p_dry_run and not exists (
           select 1 from public.audit_logs al
            where al.table_name = 'staff_commissions' and al.record_id = p_invoice_id
              and al.action = 'staff_commission_skipped_no_staff'
              and al.new_data->>'basis' = 'instalment' and (al.new_data->>'pending')::numeric = v_delta) then
        perform public.write_audit('staff_commissions', p_invoice_id, 'staff_commission_skipped_no_staff', null,
          jsonb_build_object('invoice_no', v_inv.invoice_no, 'store_id', v_inv.store_id,
                             'basis', 'instalment', 'pending', v_delta));
      end if;
    else
      v_cents := round(v_delta * 100)::bigint; v_k := 0;
      for s in select x.staff_id from public.store_commission_staff(v_inv.store_id) x order by x.staff_id loop
        v_k := v_k + 1;
        o_ledger := 'staff'; o_beneficiary := s.staff_id; o_tier := null; o_product_type := null; o_item := null;
        o_status := 'earned'; o_date := v_date;
        o_amount := round(((v_cents / v_n) + case when v_k <= v_cents % v_n then 1 else 0 end) / 100.0, 2);
        if o_amount = 0 then continue; end if;
        if not p_dry_run then perform public.commission_write_locks();
          insert into public.staff_commissions(invoice_id, staff_id, store_id, invoice_total, share_ratio, rate,
            commission_amount, status, invoice_paid_date, earning_basis, created_at)
          values (p_invoice_id, s.staff_id, v_inv.store_id,
            case when v_rate > 0 then round(v_delta * 100.0 / v_rate, 2) else 0 end,
            round(1.0 / v_n, 6), v_rate, o_amount, 'earned', v_date, 'instalment', clock_timestamp());
          v_wrote := v_wrote + 1;
        end if;
        v_staff_delta := v_staff_delta + o_amount;
        return next;
      end loop;
    end if;
  elsif v_delta < 0 then
    v_need := -v_delta;
    -- 1) Unpaid part-payment commission is taken back where it stands, newest
    --    date first (rows do not record which payment earned them, so money
    --    leaving is matched to the newest commission, not to the payment that
    --    left). Within a date each UNPAID holder gives back in proportion to what
    --    they hold there, to the cent (cumulative rounding): their unpaid rows on
    --    that date are reversed and what each keeps is written again on the same
    --    date. Unpaid commission goes before anything already paid out (the
    --    owner's rule), so a colleague already paid for that month keeps theirs
    --    unless the unpaid shares are not enough.
    for dt in select sc.invoice_paid_date as paid_date, sum(sc.commission_amount) as date_total
                from public.staff_commissions sc
               where sc.invoice_id = p_invoice_id and sc.earning_basis = 'instalment'
                 and sc.status = 'earned' and sc.payout_id is null and sc.commission_amount > 0
               group by sc.invoice_paid_date
               order by sc.invoice_paid_date desc loop
      exit when v_need <= 0;
      v_take := least(v_need, dt.date_total);
      for r in select q.staff_id, q.held, q.held_rate, q.held_ratio, q.held_base,
                      round(v_take * sum(q.held) over (order by q.held desc, q.staff_id) / dt.date_total, 2)
                    - round(v_take * (sum(q.held) over (order by q.held desc, q.staff_id) - q.held) / dt.date_total, 2) as take
                 from (select sc.staff_id, sum(sc.commission_amount) as held, max(sc.rate) as held_rate,
                              max(sc.share_ratio) as held_ratio, sum(sc.invoice_total) as held_base
                         from public.staff_commissions sc
                        where sc.invoice_id = p_invoice_id and sc.earning_basis = 'instalment'
                          and sc.status = 'earned' and sc.payout_id is null and sc.commission_amount > 0
                          and sc.invoice_paid_date = dt.paid_date
                        group by sc.staff_id) q
                order by q.held desc, q.staff_id loop
        continue when r.take = 0;
        o_ledger := 'staff'; o_beneficiary := r.staff_id; o_tier := null; o_product_type := null; o_item := null;
        o_status := 'earned'; o_date := dt.paid_date; o_amount := -r.take;
        v_gone := v_gone || array(select sc.id from public.staff_commissions sc
                                   where sc.invoice_id = p_invoice_id and sc.earning_basis = 'instalment'
                                     and sc.status = 'earned' and sc.payout_id is null and sc.commission_amount > 0
                                     and sc.invoice_paid_date = dt.paid_date and sc.staff_id = r.staff_id);
        if not p_dry_run then perform public.commission_write_locks();
          update public.staff_commissions sc set status = 'reversed', reversed_at = now(), reversal_reason = p_reason
           where sc.invoice_id = p_invoice_id and sc.earning_basis = 'instalment'
             and sc.status = 'earned' and sc.payout_id is null and sc.commission_amount > 0
             and sc.invoice_paid_date = dt.paid_date and sc.staff_id = r.staff_id;
          v_wrote := v_wrote + 1;
          if r.held - r.take > 0 then
            insert into public.staff_commissions(invoice_id, staff_id, store_id, invoice_total, share_ratio, rate,
              commission_amount, status, invoice_paid_date, earning_basis, created_at)
            values (p_invoice_id, r.staff_id, v_inv.store_id,
              round(r.held_base * (r.held - r.take) / r.held, 2), r.held_ratio, r.held_rate,
              r.held - r.take, 'earned', dt.paid_date, 'instalment', clock_timestamp());
            v_wrote := v_wrote + 1;
          end if;
        end if;
        v_staff_delta := v_staff_delta + o_amount;
        return next;
      end loop;
      v_need := round(v_need - v_take, 2);
    end loop;
    -- 2) What is left was paid out: taken back as new rows from the holders,
    --    in proportion to what each still holds.
    if v_need > 0 then
      select coalesce(sum(q.held), 0) into v_holders
        from (select sum(sc.commission_amount) as held from public.staff_commissions sc
               where sc.invoice_id = p_invoice_id and sc.earning_basis = 'instalment'
                 and sc.status in ('earned','paid') and not (sc.id = any(v_gone))
               group by sc.staff_id having sum(sc.commission_amount) > 0) q;
      -- (v_holders is always positive here: what is held exceeds the target.
      -- Guarded anyway, so a payment can never fail on it.)
      -- Cumulative rounding: the shares add up to exactly what is taken back.
      for r in select q.staff_id, q.held, q.held_rate,
                      round(v_need * sum(q.held) over (order by q.held desc, q.staff_id) / v_holders, 2)
                    - round(v_need * (sum(q.held) over (order by q.held desc, q.staff_id) - q.held) / v_holders, 2) as take
                 from (select sc.staff_id, sum(sc.commission_amount) as held, max(sc.rate) as held_rate
                         from public.staff_commissions sc
                        where sc.invoice_id = p_invoice_id and sc.earning_basis = 'instalment'
                          and sc.status in ('earned','paid') and not (sc.id = any(v_gone))
                        group by sc.staff_id having sum(sc.commission_amount) > 0) q
                where v_holders > 0
                order by q.held desc, q.staff_id loop
        if r.take = 0 then continue; end if;
        o_amount := -r.take;
        o_ledger := 'staff'; o_beneficiary := r.staff_id; o_tier := null; o_product_type := null; o_item := null;
        o_status := 'earned'; o_date := v_date;
        if not p_dry_run then perform public.commission_write_locks();
          insert into public.staff_commissions(invoice_id, staff_id, store_id, invoice_total, share_ratio, rate,
            commission_amount, status, invoice_paid_date, earning_basis, created_at)
          values (p_invoice_id, r.staff_id, v_inv.store_id,
            case when coalesce(r.held_rate, 0) > 0 then round(o_amount * 100.0 / r.held_rate, 2) else 0 end,
            round(r.held / v_holders, 6), coalesce(r.held_rate, 0), o_amount, 'earned', v_date, 'instalment', clock_timestamp());
          v_wrote := v_wrote + 1;
        end if;
        v_staff_delta := v_staff_delta + o_amount;
        return next;
      end loop;
    end if;
  end if;

  -- ---------- affiliate: a cancelled or refunded invoice ----------
  -- Nothing of the sale stands, so nothing of its part-payment commission may
  -- stay in any month. Per beneficiary / tier / type / line, every part-payment
  -- row's effect is removed IN ITS OWN MONTH:
  --   * a positive row: what is still unpaid on it is taken back where it
  --     stands (reversed if nothing was paid against it, otherwise a linked
  --     negative row in its month);
  --   * a negative row (the close written at settlement, or an earlier take-back
  --     of paid-out commission): reversed if its month has had no payout;
  --     otherwise it was netted into that payout, so a linked positive row in
  --     the same month cancels it there.
  -- What still stands after that is exactly what was paid out, taken back by
  -- one negative row today. Nothing positive is ever dated today, so a
  -- cancelled sale never creates a payable balance.
  if v_closed then
    for s in select c.referrer_customer_id as beneficiary, c.tier::text as tier, c.product_type,
                    c.invoice_item_id as item, max(c.rate) as rate, sum(c.commission_amount) as held_amount
               from public.commissions c
              where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment' and c.status in ('earned','paid')
              group by 1, 2, 3, 4
              order by 1, 2, 3, 4
    loop
      v_need := s.held_amount;
      for r in select c.id, c.commission_amount, c.line_amount, c.invoice_paid_date,
                      c.status::text = 'earned' and c.payout_id is null
                        and not exists (select 1 from public.commission_payout_allocations pa where pa.commission_id = c.id)
                        and not exists (select 1 from public.commissions adj where adj.adjusts_commission_id = c.id
                                         and adj.status in ('earned','paid')) as untouched,
                      public.commission_unpaid_amount(c.id) as unpaid,
                      exists (select 1 from public.commission_payouts cp
                               where cp.referrer_customer_id = c.referrer_customer_id and cp.status = 'paid'
                                 and cp.payout_month = date_trunc('month', c.invoice_paid_date)::date) as month_paid
                 from public.commissions c
                where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment' and c.status in ('earned','paid')
                  and c.referrer_customer_id = s.beneficiary and c.tier::text = s.tier
                  and c.product_type is not distinct from s.product_type
                  and c.invoice_item_id is not distinct from s.item
                  -- rows written by this squaring, and rows linked to another row
                  -- (its partial take-backs and cancellations), are left as they stand
                  and c.adjusts_commission_id is null
                  and coalesce(c.reversal_reason, '') not like 'Part-payment commission squared%'
                  and coalesce(c.reversal_reason, '') not like 'Paid-out part-payment commission taken back%'
                  -- a negative row already cancelled in its month
                  and not (c.commission_amount < 0
                           and exists (select 1 from public.commissions adj where adj.adjusts_commission_id = c.id
                                        and adj.status in ('earned','paid')))
                order by c.invoice_paid_date desc, c.created_at desc, c.id desc
      loop
        o_ledger := 'affiliate'; o_beneficiary := s.beneficiary; o_tier := s.tier; o_product_type := s.product_type;
        o_item := s.item; o_status := 'earned'; o_date := r.invoice_paid_date;
        if r.commission_amount > 0 then
          continue when r.unpaid <= 0;
          o_amount := -least(r.unpaid, r.commission_amount);
          if not p_dry_run then perform public.commission_write_locks();
            if r.untouched then
              update public.commissions set status = 'reversed', reversed_at = now(), reversal_reason = p_reason
               where id = r.id;
            else
              insert into public.commissions(invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
                product_type, line_amount, rate, commission_amount, status, invoice_paid_date, earning_basis,
                adjusts_commission_id, reversal_reason, created_at)
              values (p_invoice_id, s.item, v_inv.customer_id, s.beneficiary, s.tier::commission_tier, s.product_type,
                round(r.line_amount * o_amount / r.commission_amount, 2), coalesce(s.rate, 0), o_amount, 'earned',
                r.invoice_paid_date, 'instalment', r.id, p_reason, clock_timestamp());
            end if;
            v_wrote := v_wrote + 1;
          end if;
        elsif r.commission_amount < 0 and r.untouched and not r.month_paid then
          o_amount := -r.commission_amount;
          if not p_dry_run then perform public.commission_write_locks();
            update public.commissions set status = 'reversed', reversed_at = now(), reversal_reason = p_reason
             where id = r.id;
            v_wrote := v_wrote + 1;
          end if;
        elsif r.commission_amount < 0 then
          o_amount := -r.commission_amount;
          if not p_dry_run then perform public.commission_write_locks();
            insert into public.commissions(invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
              product_type, line_amount, rate, commission_amount, status, invoice_paid_date, earning_basis,
              adjusts_commission_id, reversal_reason, created_at)
            values (p_invoice_id, s.item, v_inv.customer_id, s.beneficiary, s.tier::commission_tier, s.product_type,
              -r.line_amount, coalesce(s.rate, 0), o_amount, 'earned', r.invoice_paid_date, 'instalment',
              r.id, p_reason, clock_timestamp());
            v_wrote := v_wrote + 1;
          end if;
        else
          continue;
        end if;
        v_need := round(v_need + o_amount, 2);
        return next;
      end loop;
      -- What stands now is what was paid out: taken back today.
      if v_need > 0 then
        o_ledger := 'affiliate'; o_beneficiary := s.beneficiary; o_tier := s.tier; o_product_type := s.product_type;
        o_item := s.item; o_status := 'earned'; o_date := v_date; o_amount := -v_need;
        if not p_dry_run then perform public.commission_write_locks();
          insert into public.commissions(invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
            product_type, line_amount, rate, commission_amount, status, invoice_paid_date, earning_basis,
            reversal_reason, created_at)
          values (p_invoice_id, s.item, v_inv.customer_id, s.beneficiary, s.tier::commission_tier, s.product_type,
            case when coalesce(s.rate, 0) > 0 then round(o_amount * 100.0 / s.rate, 2) else 0 end,
            coalesce(s.rate, 0), o_amount, 'earned', v_date, 'instalment',
            'Part-payment commission squared: ' || coalesce(p_reason, 'invoice closed'), clock_timestamp());
          v_wrote := v_wrote + 1;
        end if;
        return next;
      elsif v_need < 0 then
        -- A payout was lowered after the money was recovered, so more was taken
        -- back than is now paid out. Give the difference back against the
        -- recovery rows (the squaring row, and take-backs of paid-out commission
        -- while the invoice was being paid), newest first, each in its own month
        -- and never beyond what that row still takes back, so no month becomes
        -- payable.
        for r in select c.id, c.line_amount, c.commission_amount, c.invoice_paid_date,
                        c.commission_amount + coalesce((select sum(adj.commission_amount) from public.commissions adj
                                                          where adj.adjusts_commission_id = c.id
                                                            and adj.status in ('earned','paid')), 0) as standing
                   from public.commissions c
                  where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment' and c.status in ('earned','paid')
                    and c.referrer_customer_id = s.beneficiary and c.tier::text = s.tier
                    and c.product_type is not distinct from s.product_type
                    and c.invoice_item_id is not distinct from s.item
                    and (c.reversal_reason like 'Part-payment commission squared%'
                         or c.reversal_reason like 'Paid-out part-payment commission taken back%')
                  order by c.invoice_paid_date desc, c.created_at desc, c.id desc
        loop
          exit when v_need >= 0;
          continue when r.standing >= 0;
          o_ledger := 'affiliate'; o_beneficiary := s.beneficiary; o_tier := s.tier; o_product_type := s.product_type;
          o_item := s.item; o_status := 'earned'; o_date := r.invoice_paid_date;
          o_amount := least(-v_need, -r.standing);
          if not p_dry_run then perform public.commission_write_locks();
            insert into public.commissions(invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
              product_type, line_amount, rate, commission_amount, status, invoice_paid_date, earning_basis,
              adjusts_commission_id, reversal_reason, created_at)
            values (p_invoice_id, s.item, v_inv.customer_id, s.beneficiary, s.tier::commission_tier, s.product_type,
              round(r.line_amount * o_amount / r.commission_amount, 2), coalesce(s.rate, 0), o_amount, 'earned',
              r.invoice_paid_date, 'instalment', r.id, p_reason, clock_timestamp());
            v_wrote := v_wrote + 1;
          end if;
          v_need := round(v_need + o_amount, 2);
          return next;
        end loop;
        -- Nothing left to give back against: record it once for review, never as
        -- a positive row.
        if v_need < 0 and not p_dry_run and not exists (
             select 1 from public.audit_logs al
              where al.table_name = 'invoices' and al.record_id = p_invoice_id
                and al.action = 'instalment_commission_review_required'
                and al.new_data->>'referrer' = s.beneficiary::text and al.new_data->>'tier' = s.tier
                and al.new_data->>'product_type' is not distinct from s.product_type
                and al.new_data->>'invoice_item_id' is not distinct from s.item::text
                and (al.new_data->>'left_over')::numeric = v_need) then
          perform public.write_audit_ex('invoices', p_invoice_id, 'instalment_commission_review_required', null,
            jsonb_build_object('invoice_no', v_inv.invoice_no, 'referrer', s.beneficiary, 'tier', s.tier,
                               'product_type', s.product_type, 'invoice_item_id', s.item,
                               'left_over', v_need), 'commission', p_reason, v_inv.store_id);
        end if;
      end if;
    end loop;
  end if;

  -- ---------- affiliate: earned amounts, per beneficiary / tier / type / line ----------
  -- (A cancelled or refunded invoice was squared above.)
  for s in
    with t as (select t.beneficiary, t.tier, t.product_type, t.invoice_item_id, t.rate, t.base, t.amount
                 from jsonb_to_recordset(v_targets) as t(ledger text, beneficiary uuid, tier text, product_type text,
                        invoice_item_id uuid, status text, rate numeric, base numeric, amount numeric)
                where t.ledger = 'affiliate' and t.status = 'earned'),
         held as (select c.referrer_customer_id as beneficiary, c.tier::text as tier, c.product_type, c.invoice_item_id,
                      max(c.rate) as rate, sum(c.line_amount) as base, sum(c.commission_amount) as amount
                 from public.commissions c
                where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment' and c.status in ('earned','paid')
                group by 1, 2, 3, 4)
    select coalesce(t.beneficiary, held.beneficiary) as beneficiary, coalesce(t.tier, held.tier) as tier,
           coalesce(t.product_type, held.product_type) as product_type,
           coalesce(t.invoice_item_id, held.invoice_item_id) as item,
           coalesce(t.rate, held.rate) as rate,
           round(coalesce(t.base, 0) - coalesce(held.base, 0), 2) as base_delta,
           round(coalesce(t.amount, 0) - coalesce(held.amount, 0), 2) as delta
      from t full join held
        on held.beneficiary = t.beneficiary and held.tier = t.tier
       and held.product_type is not distinct from t.product_type
       and held.invoice_item_id is not distinct from t.invoice_item_id
     where not v_closed
     order by 1, 2, 3, 4
  loop
    if s.delta = 0 then continue; end if;
    if s.delta > 0 and not v_grow then continue; end if;
    v_need := -s.delta;
    -- Money left while the invoice is still being paid: what is unpaid on the
    -- part-payment rows for this key is taken back where it stands, newest
    -- first: a row nothing was paid against and no larger than what is left is
    -- reversed; otherwise its unpaid part is taken back by a linked negative row
    -- in the row's own month. Only what was already paid out is taken back as a
    -- new row today. A settlement close instead appends one negative row,
    -- because settlement then pays the full amount to the same people in the
    -- settlement month.
    if s.delta < 0 and v_active then
      for r in select c.id, c.commission_amount, c.line_amount, c.invoice_paid_date,
                      c.status::text = 'earned' and c.payout_id is null
                        and not exists (select 1 from public.commission_payout_allocations pa where pa.commission_id = c.id)
                        and not exists (select 1 from public.commissions adj where adj.adjusts_commission_id = c.id
                                         and adj.status in ('earned','paid')) as untouched,
                      public.commission_unpaid_amount(c.id) as unpaid
                 from public.commissions c
                where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment' and c.status in ('earned','paid')
                  and c.commission_amount > 0
                  and c.referrer_customer_id = s.beneficiary and c.tier::text = s.tier
                  and c.product_type is not distinct from s.product_type
                  and c.invoice_item_id is not distinct from s.item
                order by c.invoice_paid_date desc, c.created_at desc, c.id desc loop
        exit when v_need <= 0;
        continue when r.unpaid <= 0;
        o_ledger := 'affiliate'; o_beneficiary := s.beneficiary; o_tier := s.tier; o_product_type := s.product_type;
        o_item := s.item; o_status := 'earned'; o_date := r.invoice_paid_date;
        o_amount := -least(r.unpaid, v_need);
        if not p_dry_run then perform public.commission_write_locks();
          if r.untouched and r.commission_amount <= v_need then
            update public.commissions set status = 'reversed', reversed_at = now(), reversal_reason = p_reason
             where id = r.id;
          else
            insert into public.commissions(invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
              product_type, line_amount, rate, commission_amount, status, invoice_paid_date, earning_basis,
              adjusts_commission_id, reversal_reason, created_at)
            values (p_invoice_id, s.item, v_inv.customer_id, s.beneficiary, s.tier::commission_tier, s.product_type,
              round(r.line_amount * o_amount / r.commission_amount, 2), coalesce(s.rate, 0), o_amount, 'earned',
              r.invoice_paid_date, 'instalment', r.id, p_reason, clock_timestamp());
          end if;
          v_wrote := v_wrote + 1;
        end if;
        v_need := round(v_need + o_amount, 2);
        return next;
      end loop;
    end if;
    if s.delta > 0 or v_need > 0 then
      o_ledger := 'affiliate'; o_beneficiary := s.beneficiary; o_tier := s.tier; o_product_type := s.product_type;
      o_item := s.item; o_status := 'earned'; o_date := v_date;
      o_amount := case when s.delta > 0 then s.delta else -v_need end;
      if not p_dry_run then perform public.commission_write_locks();
        insert into public.commissions(invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
          product_type, line_amount, rate, commission_amount, status, invoice_paid_date, earning_basis,
          reversal_reason, created_at)
        values (p_invoice_id, s.item, v_inv.customer_id, s.beneficiary, s.tier::commission_tier, s.product_type,
          case when s.delta > 0 then s.base_delta
               when s.delta <> 0 then round(s.base_delta * v_need / -s.delta, 2) else 0 end,
          coalesce(s.rate, 0), o_amount, 'earned', v_date, 'instalment',
          -- A take-back of commission already paid out, while the invoice is still
          -- being paid: it stands where it is recovered (a cancellation later does
          -- not move it). A settlement close row carries no marker.
          case when s.delta < 0 and v_active then 'Paid-out part-payment commission taken back: ' || coalesce(p_reason, '') end,
          clock_timestamp());
        v_wrote := v_wrote + 1;
      end if;
      return next;
    end if;
  end loop;

  -- ---------- affiliate: blocked rows are information only; replaced when changed ----------
  if v_grow or not v_active then
    select string_agg(format('%s|%s|%s|%s|%s', c.referrer_customer_id, c.tier, c.product_type, c.invoice_item_id, c.commission_amount),
                      ',' order by c.referrer_customer_id, c.tier, c.product_type, c.invoice_item_id, c.commission_amount)
      into v_blocked_now
      from public.commissions c
     where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment' and c.status = 'blocked';
    select string_agg(format('%s|%s|%s|%s|%s', t.beneficiary, t.tier, t.product_type, t.invoice_item_id, t.amount),
                      ',' order by t.beneficiary, t.tier, t.product_type, t.invoice_item_id, t.amount)
      into v_blocked_want
      from jsonb_to_recordset(v_targets) as t(ledger text, beneficiary uuid, tier text, product_type text,
             invoice_item_id uuid, status text, amount numeric)
     where t.ledger = 'affiliate' and t.status = 'blocked' and t.amount > 0;
    if v_blocked_now is distinct from v_blocked_want then
      if not p_dry_run then perform public.commission_write_locks();
        update public.commissions c set status = 'reversed', reversed_at = now(), reversal_reason = p_reason
         where c.invoice_id = p_invoice_id and c.earning_basis = 'instalment' and c.status = 'blocked';
        insert into public.commissions(invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
          product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date, earning_basis, created_at)
        select p_invoice_id, t.invoice_item_id, v_inv.customer_id, t.beneficiary, t.tier::commission_tier, t.product_type,
               t.base, t.rate, t.amount, 'blocked', t.block_reason, v_date, 'instalment', clock_timestamp()
          from jsonb_to_recordset(v_targets) as t(ledger text, beneficiary uuid, tier text, product_type text,
                 invoice_item_id uuid, status text, rate numeric, base numeric, amount numeric, block_reason text)
         where t.ledger = 'affiliate' and t.status = 'blocked' and t.amount > 0;
        v_wrote := v_wrote + 1;
      end if;
      for s in select t.beneficiary, t.tier, t.product_type, t.invoice_item_id, t.amount
                 from jsonb_to_recordset(v_targets) as t(ledger text, beneficiary uuid, tier text, product_type text,
                        invoice_item_id uuid, status text, amount numeric)
                where t.ledger = 'affiliate' and t.status = 'blocked' and t.amount > 0 loop
        o_ledger := 'affiliate'; o_beneficiary := s.beneficiary; o_tier := s.tier; o_product_type := s.product_type;
        o_item := s.invoice_item_id; o_status := 'blocked'; o_amount := s.amount; o_date := v_date;
        return next;
      end loop;
    end if;
  end if;

  if v_wrote > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'instalment_commission_synced', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'credit_date', v_date,
                         'staff_change', v_staff_delta, 'rows', v_wrote),
      'commission', p_reason, v_inv.store_id);
  end if;
end $$;

-- ── 7. every money or status change re-syncs ────────────────────────────────
create or replace function public.trg_sync_instalment_commissions()
returns trigger language plpgsql security definer set search_path = public as $$
-- 357: idempotent, so running after an explicit sync writes nothing.
begin
  if new.status is distinct from old.status
     or coalesce(new.paid_amount, 0) is distinct from coalesce(old.paid_amount, 0) then
    perform public.sync_instalment_commissions(new.id, 'Invoice money or status changed');
  end if;
  return null;
end $$;
drop trigger if exists sync_instalment_commissions on public.invoices;
create trigger sync_instalment_commissions
  after update of status, paid_amount on public.invoices
  for each row execute function public.trg_sync_instalment_commissions();

-- ── 8. reconcile: settlement layer only; never settlement rows before settling ──
do $mig$
declare d text; n int; v_md5 text;
        a_rev text := 'and payout_id is null and status in (''earned'',''blocked'');';
        a_earn text := E'if i.status not in (''cancelled'',''refunded'') then\n   perform public.earn_invoice_commission(i.id);';
        a_paid text := 'and (payout_id is not null or status=''paid'') loop';
begin
  d := pg_get_functiondef('public.reconcile_invoice_commissions(uuid,text)'::regprocedure);
  if position('357:' in d) > 0 then raise notice '357: reconcile_invoice_commissions already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'a8c50cb1ac4121b3a99d2f0a680ff65f' then
    raise exception '357: reconcile_invoice_commissions is not the version this was tested against (md5 %)', v_md5; end if;

  n := (length(d) - length(replace(d, a_rev, ''))) / length(a_rev);
  if n <> 2 then raise exception '357: reconcile reversal anchors: expected 2, found %', n; end if;
  d := replace(d, a_rev, 'and payout_id is null and status in (''earned'',''blocked'') and earning_basis=''settlement'';');

  n := (length(d) - length(replace(d, a_earn, ''))) / length(a_earn);
  if n <> 1 then raise exception '357: reconcile earn anchor: expected 1, found %', n; end if;
  d := replace(d, a_earn, E'-- 357: an invoice that is not fully paid earns on the instalment layer only.\n'
    || E' if i.status not in (''cancelled'',''refunded'') and not public.invoice_instalment_commission_active(i.id) then\n   perform public.earn_invoice_commission(i.id);');

  n := (length(d) - length(replace(d, a_paid, ''))) / length(a_paid);
  if n <> 2 then raise exception '357: reconcile payout anchors: expected 2, found %', n; end if;
  d := replace(d, a_paid, 'and (payout_id is not null or status=''paid'') and earning_basis=''settlement'' loop');

  if d !~ 'end \$function\$\s*$' then raise exception '357: reconcile end anchor missing'; end if;
  d := regexp_replace(d, 'end \$function\$\s*$',
    E' perform public.sync_instalment_commissions(i.id, p_reason);\nend $function$');
  execute d;
end $mig$;

-- ── 8b. settlement pays the staff roster only what part payments did not ────
-- Part payments registered their share of the invoice's staff pool on the
-- instalment layer, with whoever was on the roster when that money arrived,
-- and that stays with them. Settlement shares only the rest of the pool among
-- the settlement-day roster, to the cent. An invoice with no part-payment rows
-- is earned exactly as before.
do $mig$
declare d text; v_md5 text;
        a_decl text := E'  v_share numeric; v_paid_date date; v_amt numeric; v_staff record;\nbegin';
        a_body text := E'  v_share := round(1.0 / v_n, 6);\n  v_paid_date := coalesce(v_inv.paid_at, now())::date;\n';
begin
  d := pg_get_functiondef('public.earn_staff_commission(uuid)'::regprocedure);
  if position('357:' in d) > 0 then raise notice '357: earn_staff_commission already pays only the rest; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '06f52d21b97242781cf8f9103f824522' then
    raise exception '357: earn_staff_commission is not the version this was tested against (md5 %)', v_md5; end if;
  if (length(d) - length(replace(d, a_decl, ''))) / length(a_decl) <> 1
     or (length(d) - length(replace(d, a_body, ''))) / length(a_body) <> 1 then
    raise exception '357: earn_staff_commission anchors not found exactly once'; end if;
  d := replace(d, a_decl, E'  v_share numeric; v_paid_date date; v_amt numeric; v_staff record;\n  v_inst numeric; v_rest numeric; v_cents bigint; v_k integer;\nbegin');
  d := replace(d, a_body, a_body || $ins$
  -- 357: part payments already registered their share of this invoice's staff
  -- pool (instalment rows, kept by the staff on the roster when that money
  -- arrived). Settlement pays today's roster only the rest, to the cent.
  v_inst := coalesce((select sum(sc.commission_amount) from public.staff_commissions sc
                       where sc.invoice_id = p_invoice_id and sc.earning_basis = 'instalment'
                         and sc.status in ('earned','paid')), 0);
  if v_inst <> 0 then
    v_rest := round(v_inv.total_amount * v_rate / 100.0, 2) - v_inst;
    if v_rest > 0 then
      v_cents := round(v_rest * 100)::bigint; v_k := 0;
      for v_staff in select s.staff_id from public.store_commission_staff(v_inv.store_id) s order by s.staff_id
      loop
        v_k := v_k + 1;
        v_amt := ((v_cents / v_n) + case when v_k <= v_cents % v_n then 1 else 0 end) / 100.0;
        if v_amt <= 0 then continue; end if;
        insert into public.staff_commissions
          (invoice_id, staff_id, store_id, invoice_total, share_ratio, rate,
           commission_amount, status, invoice_paid_date)
        values (p_invoice_id, v_staff.staff_id, v_inv.store_id, v_inv.total_amount,
           v_share, v_rate, v_amt, 'earned', v_paid_date);
      end loop;
    end if;
    perform public.write_audit('staff_commissions', p_invoice_id, 'staff_commission_earned', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'staff_count', v_n, 'rate', v_rate,
        'basis', 'store active staff', 'registered_on_part_payments', v_inst,
        'settled_now', greatest(v_rest, 0)));
    return;
  end if;
$ins$);
  execute d;
end $mig$;

-- ── 8c. paid in full AGAIN, or after a refund: settle through reconcile ─────
-- An invoice that settled, fell back (a payment removed or corrected down, a
-- reopen) and is now paid in full again with Record Payment used to earn only
-- through earn_invoice_commission and earn_staff_commission. Package and bundle
-- commission was lost for good: the sales already exist, so issuance does not
-- earn it again, and the fall-back reversed it. Line refunds were ignored too,
-- and so were refunds recorded while the invoice was still part-paid, on a
-- first settlement. reconcile re-earns every layer, honours line refunds and
-- offsets what was paid out, exactly as a correction back up to full does.
-- Whether to go that way is decided on entry, before this payment writes
-- anything, so it holds however the calls are grouped into transactions. Any
-- other first settlement earns as before. A historical refund that needs review
-- must not stop the customer paying: then the old path runs and the review is
-- recorded.
do $mig$
declare d text; n int; v_md5 text;
  a_decl constant text := E'  v_old_total numeric; v_changes jsonb;\nbegin\n';
  a_lock constant text := E'  if not found then raise exception ''Invoice not found''; end if;\n';
  a_earn constant text := E'    perform public.earn_invoice_commission(p_invoice_id);\n    perform public.earn_staff_commission(p_invoice_id);';
begin
  d := pg_get_functiondef('public.invoice_record_payments_internal(uuid,jsonb)'::regprocedure);
  if position('357:' in d) > 0 then raise notice '357: invoice_record_payments_internal already settles through reconcile; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '1481df4254e80a17c391b2904ea1376e' then
    raise exception '357: invoice_record_payments_internal is not the version this was tested against (md5 %)', v_md5; end if;
  if (length(d) - length(replace(d, a_decl, ''))) / length(a_decl) <> 1
     or (length(d) - length(replace(d, a_lock, ''))) / length(a_lock) <> 1
     or (length(d) - length(replace(d, a_earn, ''))) / length(a_earn) <> 1 then
    raise exception '357: invoice_record_payments_internal anchors not found exactly once'; end if;
  d := replace(d, a_decl, E'  v_old_total numeric; v_changes jsonb;\n  v_reconcile357 boolean;\nbegin\n');
  d := replace(d, a_lock, a_lock || $r$  -- 357: settled before (its sales or settlement commission exist), or money
  -- was refunded since it was opened: full payment settles through reconcile.
  v_reconcile357 :=
       exists (select 1 from public.credit_package_sales cps357 where cps357.invoice_id = p_invoice_id)
    or exists (select 1 from public.premium_bundle_sales pbs357 where pbs357.invoice_id = p_invoice_id)
    or exists (select 1 from public.commissions cm357
                where cm357.invoice_id = p_invoice_id and cm357.earning_basis = 'settlement')
    or exists (select 1 from public.staff_commissions sc357
                where sc357.invoice_id = p_invoice_id and sc357.earning_basis = 'settlement')
    or exists (select 1 from public.invoice_refunds rf357
                where rf357.invoice_id = p_invoice_id
                  and (v_inv.reopened_at is null or rf357.created_at > v_inv.reopened_at));
$r$);
  d := replace(d, a_earn, $r$    if v_reconcile357 then
      begin
        perform public.reconcile_invoice_commissions(p_invoice_id, 'Paid in full');
      exception when raise_exception then
        if sqlerrm not like 'Commission review required%' then raise; end if;
        perform public.earn_invoice_commission(p_invoice_id);
        perform public.earn_staff_commission(p_invoice_id);
        perform public.write_audit_ex('invoices', p_invoice_id, 'commission_review_required', null,
          jsonb_build_object('invoice_no', v_inv.invoice_no, 'reason', sqlerrm), 'commission',
          'Paid in full: commission earned without reconciling', v_inv.store_id);
      end;
    else
      perform public.earn_invoice_commission(p_invoice_id);
      perform public.earn_staff_commission(p_invoice_id);
    end if;$r$);
  execute d;
end $mig$;

-- ── 9. the staff rebase works on the settlement layer only ──────────────────
do $mig$
declare d text; v_md5 text;
        a1 text := E'   where invoice_id = p_invoice_id\n     and (payout_id is not null or status = ''paid'');';
        a2 text := E'     and status = ''earned''\n     and payout_id is null;';
        a3 text := E'  v_pool := round(public.invoice_net_sales(p_invoice_id) * v_rate / 100.0, 2) - v_already_paid;';
begin
  d := pg_get_functiondef('public.reearn_invoice_staff_commission(uuid,text)'::regprocedure);
  if position('357:' in d) > 0 then raise notice '357: reearn_invoice_staff_commission already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '0c097bd6d5206d7408d59a5f8f044003' then
    raise exception '357: reearn_invoice_staff_commission is not the version this was tested against (md5 %)', v_md5; end if;
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1
     or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1
     or (length(d) - length(replace(d, a3, ''))) / length(a3) <> 1 then
    raise exception '357: reearn_invoice_staff_commission anchors not found exactly once'; end if;
  -- The part-payment shares stay with their holders, so the rebase pool is what is left after them.
  d := replace(d, a3, E'  v_pool := round(public.invoice_net_sales(p_invoice_id) * v_rate / 100.0, 2) - v_already_paid\n'
    || E'            - coalesce((select sum(si.commission_amount) from public.staff_commissions si\n'
    || E'                         where si.invoice_id = p_invoice_id and si.earning_basis = ''instalment''\n'
    || E'                           and si.status in (''earned'',''paid'')), 0);');
  d := replace(d, a1, E'   where invoice_id = p_invoice_id\n     and (payout_id is not null or status = ''paid'')\n     and earning_basis = ''settlement'';  -- 357: part-payment rows are not the rebase''s');
  d := replace(d, a2, E'     and status = ''earned''\n     and payout_id is null\n     and earning_basis = ''settlement'';');
  execute d;
end $mig$;

do $mig$
declare d text; v_md5 text;
        a1 text := 'and (sc.payout_id is not null or sc.status = ''paid'')), 0), 0) as pool';
        a2 text := E'     where sc.status = ''earned'' and sc.payout_id is null\n     group by sc.staff_id';
begin
  d := pg_get_functiondef('public.preview_commission_rebase_effect(date,date)'::regprocedure);
  if position('357:' in d) > 0 then raise notice '357: preview_commission_rebase_effect already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '8d5af072e79da8401faabbd5078d9760' then
    raise exception '357: preview_commission_rebase_effect is not the version this was tested against (md5 %)', v_md5; end if;
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1
     or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1 then
    raise exception '357: preview_commission_rebase_effect anchors not found exactly once'; end if;
  d := replace(d, a1, 'and (sc.payout_id is not null or sc.status = ''paid'') and sc.earning_basis = ''settlement''), 0)'
    || E'\n                    - coalesce((select sum(si.commission_amount) from public.staff_commissions si'
    || ' where si.invoice_id = i.id and si.earning_basis = ''instalment'' and si.status in (''earned'',''paid'')), 0), 0) as pool');
  d := replace(d, a2, E'     where sc.status = ''earned'' and sc.payout_id is null\n       and sc.earning_basis = ''settlement''  -- 357: the rebase touches settlement rows only\n     group by sc.staff_id');
  execute d;
end $mig$;

-- ── 10. an exchange top-up received in part earns on what arrived ───────────
do $mig$
declare d text; v_md5 text;
        a1 text := E'    perform public.earn_staff_commission(v_inv_id);\n  end if;';
begin
  d := pg_get_functiondef('public.create_exchange_invoice(uuid)'::regprocedure);
  if position('357:' in d) > 0 then raise notice '357: create_exchange_invoice already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '35f5484734ca5c14457c9db2f7027e80' then
    raise exception '357: create_exchange_invoice is not the version this was tested against (md5 %)', v_md5; end if;
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 then
    raise exception '357: create_exchange_invoice anchor not found exactly once'; end if;
  d := replace(d, a1, a1 || E'\n  -- 357: the replacement invoice is inserted, not updated, so the trigger never\n  -- sees a top-up received in part. Sync it here.\n  perform public.sync_instalment_commissions(v_inv_id, ''Exchange top-up received'');');
  execute d;
end $mig$;

-- ── 11. rows already on invoices still being paid are instalment rows ───────
-- Written by the double-pay path (a correction re-earning on a part-paid
-- invoice, or a settled invoice that fell back to part-paid). Relabelled, not
-- re-earned: amounts do not change. Production on 25 Sep 2026: the 3 staff
-- rows on INV-2026-0282, S$24.96.
do $mig$
declare v_staff int; v_aff int;
begin
  update public.staff_commissions sc set earning_basis = 'instalment'
   where sc.earning_basis = 'settlement' and sc.status in ('earned','paid','blocked')
     and public.invoice_instalment_commission_active(sc.invoice_id);
  get diagnostics v_staff = row_count;
  update public.commissions c set earning_basis = 'instalment'
   where c.earning_basis = 'settlement' and c.status in ('earned','paid','blocked')
     and public.invoice_instalment_commission_active(c.invoice_id);
  get diagnostics v_aff = row_count;
  raise notice '357: relabelled % staff and % affiliate rows on invoices still being paid', v_staff, v_aff;
end $mig$;

-- ── 12. registering earlier part payments: dry run, then apply ──────────────
-- Dry run (default) writes nothing and lists, per staff member / affiliate and
-- per invoice, what would be registered. Apply needs the dry run's earned
-- total back, so what is registered is exactly what the owner read; it dates
-- every row p_credit_date (default today; must be this month, not later than
-- today) and turns part-payment commission on.
create or replace function public.commission_instalment_backfill(
  p_apply boolean default false, p_credit_date date default null, p_expected_total numeric default null)
returns table(ledger text, beneficiary_id uuid, beneficiary_name text, invoice_id uuid, invoice_no text,
              earned_amount numeric, blocked_amount numeric, credit_date date)
language plpgsql security definer set search_path = public as $$
-- 357
declare v_date date := coalesce(p_credit_date, public.sg_today()); v_rows jsonb := '[]'::jsonb;
        v_total numeric; v_inv record; v_one jsonb;
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
  -- Registered once. After that every part payment earns as it arrives, and
  -- there is nothing earlier left to register.
  if (select a.instalment_commission_from from public.app_settings a where a.id = true) is not null then
    if p_apply then
      raise exception 'Part-payment commission is already on; there is nothing earlier left to register.'; end if;
    return;
  end if;

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

  if p_apply then
    if p_expected_total is null or round(p_expected_total, 2) <> round(v_total, 2) then
      raise exception 'The part-payment total is now %, not the % that was reviewed. Run the review again.',
        round(v_total, 2), p_expected_total; end if;
    for v_inv in select distinct (e->>'invoice_id')::uuid as id from jsonb_array_elements(v_rows) e loop
      perform * from public.sync_instalment_commissions(v_inv.id, 'Earlier part payments registered', v_date, false, true);
    end loop;
    update public.app_settings a set instalment_commission_from = coalesce(a.instalment_commission_from, v_date)
     where a.id = true;
    perform public.write_audit_ex('commissions', null, 'instalment_commission_backfilled', null,
      jsonb_build_object('credit_date', v_date, 'earned_total', v_total,
                         'invoices', (select count(distinct e->>'invoice_id') from jsonb_array_elements(v_rows) e)),
      'commission', 'Earlier part payments registered; part payments now earn as they arrive', null);
  end if;

  return query
    select e.ledger, e.beneficiary,
           case when e.ledger = 'staff' then (select p.full_name from public.profiles p where p.id = e.beneficiary)
                else (select c.full_name from public.customers c where c.id = e.beneficiary) end,
           e.invoice_id, e.invoice_no,
           coalesce(sum(e.amount) filter (where e.status = 'earned'), 0),
           coalesce(sum(e.amount) filter (where e.status = 'blocked'), 0),
           v_date
      from jsonb_to_recordset(v_rows) as e(ledger text, beneficiary uuid, invoice_id uuid, invoice_no text, status text, amount numeric)
     group by e.ledger, e.beneficiary, e.invoice_id, e.invoice_no
     order by e.ledger, 3, e.invoice_no;
end $$;

-- ── 13. grants ───────────────────────────────────────────────────────────────
-- Supabase grants new functions to anon and authenticated by default.
revoke all on function public.invoice_affiliate_commission_preview(uuid) from public, anon, authenticated;
revoke all on function public.invoice_package_commission_preview(uuid) from public, anon, authenticated;
revoke all on function public.invoice_instalment_commission_active(uuid) from public, anon, authenticated;
revoke all on function public.invoice_instalment_commission_targets(uuid) from public, anon, authenticated;
revoke all on function public.sync_instalment_commissions(uuid,text,date,boolean,boolean) from public, anon, authenticated;
revoke all on function public.trg_sync_instalment_commissions() from public, anon, authenticated;
revoke all on function public.commission_unpaid_amount(uuid) from public, anon, authenticated;
revoke all on function public.commission_write_locks() from public, anon, authenticated;
revoke all on function public.commission_instalment_backfill(boolean,date,numeric) from public, anon, authenticated;
grant execute on function public.invoice_affiliate_commission_preview(uuid) to service_role;
grant execute on function public.invoice_package_commission_preview(uuid) to service_role;
grant execute on function public.invoice_instalment_commission_active(uuid) to service_role;
grant execute on function public.invoice_instalment_commission_targets(uuid) to service_role;
grant execute on function public.sync_instalment_commissions(uuid,text,date,boolean,boolean) to service_role;
grant execute on function public.commission_unpaid_amount(uuid) to service_role;
grant execute on function public.commission_write_locks() to service_role;
grant execute on function public.commission_instalment_backfill(boolean,date,numeric) to authenticated, service_role;

-- ── 14. guards ──────────────────────────────────────────────────────────────
do $mig$
declare d text;
begin
  if not exists (select 1 from pg_trigger where tgname = 'sync_instalment_commissions'
                   and tgrelid = 'public.invoices'::regclass and not tgisinternal) then
    raise exception '357: the sync trigger is missing'; end if;
  d := pg_get_functiondef('public.reconcile_invoice_commissions(uuid,text)'::regprocedure);
  if position('sync_instalment_commissions' in d) = 0 or position('invoice_instalment_commission_active' in d) = 0 then
    raise exception '357: reconcile_invoice_commissions was not patched'; end if;
  d := pg_get_functiondef('public.invoice_affiliate_commission_preview(uuid)'::regprocedure);
  if d ~* 'insert into|write_audit' then raise exception '357: the affiliate preview writes'; end if;
  if position('357:' in pg_get_functiondef('public.earn_staff_commission(uuid)'::regprocedure)) = 0
     or position('357:' in pg_get_functiondef('public.reearn_invoice_staff_commission(uuid,text)'::regprocedure)) = 0
     or position('357:' in pg_get_functiondef('public.invoice_record_payments_internal(uuid,jsonb)'::regprocedure)) = 0 then
    raise exception '357: the staff settlement or rebase patch is missing'; end if;
  if has_function_privilege('anon', 'public.sync_instalment_commissions(uuid,text,date,boolean,boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.sync_instalment_commissions(uuid,text,date,boolean,boolean)', 'execute')
     or has_function_privilege('anon', 'public.commission_instalment_backfill(boolean,date,numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.commission_unpaid_amount(uuid)', 'execute') then
    raise exception '357: internal commission functions are callable from the API'; end if;
end $mig$;

-- ── 15. a re-run after 358 must not bring back this version ─────────────────
-- 358 replaces the backfill with one that also moves the receipts' staff-sales
-- credit (and takes one more argument). If it is installed, the copy created
-- above is an older duplicate: an ambiguous second overload for the API that
-- would register commission without moving the report. Remove it.
do $mig$
begin
  if to_regprocedure('public.commission_instalment_backfill(boolean,date,numeric,numeric)') is not null then
    drop function public.commission_instalment_backfill(boolean,date,numeric);
    raise notice '357: 358''s backfill is installed; the 357 version was not kept.';
  end if;
end $mig$;
