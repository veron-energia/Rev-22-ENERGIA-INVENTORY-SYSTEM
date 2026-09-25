-- 356_a_part_paid_bundle_releases_paid_credit.sql
--
-- WHAT WAS WRONG
--
-- A premium bundle paid in instalments released no credit until the last
-- payment. A customer who had paid $1,963 of an $11,006 bundle held nothing.
-- Credit packages have released paid credit as the money arrives since
-- migration 327; bundles were simply never included.
--
-- The cost was real. On 23 Sep 2026 staff, unable to give a part-paying bundle
-- customer the credit she had paid for, handed it over by hand as opening-
-- balance credit — $1,636 then $327, exactly the $1,963 received on
-- INV-2026-0292. See "BEFORE THIS REACHES PRODUCTION" below.
--
-- THE RULE, as the owner decided it: paid credit is released 1:1 as money
-- arrives (every bundle's paid credit equals its price); bonus credit and the
-- free vouchers are released only when the bundle is fully paid.
--
-- WHAT THIS DOES
--
-- Bundles join the machinery packages already use, rather than getting a copy
-- of it:
--
--   * credit_package_money_toward_line allocates money received across credit
--     lines of BOTH kinds. It previously answered 0 for a bundle and ignored
--     bundles queued ahead of a package. Lines that already hold released
--     credit are now served first (earliest release first, then line id as
--     before), so a line added by a correction can never take money already
--     released to another line and have it released twice.
--   * release_credit_package_paid_credit releases a bundle's paid credit with
--     the same provenance and restriction sell_premium_bundle gives it at
--     settlement, so a released lot and a settled lot are indistinguishable,
--     and records it in credit_package_progress_lots like a package release.
--   * the payment trigger calls the release for bundles too.
--
-- Because releases land in credit_package_progress_lots, everything that
-- already understands that table now understands bundles, unchanged:
--   * settlement (sell_premium_bundle, since 355) grants only entitlement minus
--     what was released, so nothing is granted twice;
--   * cancel and full refund (writeoff_released_credit_on_close) take back the
--     unspent released credit;
--   * moving an invoice's benefits to another customer follows the releases.
--
-- Split-customer bundles keep full-payment issuance, as split packages do.
--
-- KEEPING RELEASED CREDIT RIGHT ON EVERY PATH (section 3b)
--
-- Releasing credit before settlement made several older gaps in the package
-- machinery (since 327) reachable for every part-paid bundle. Fixed here, for
-- packages and bundles alike:
--   * moving the invoice to another customer before it settles: cancel, trim
--     and settlement now follow the released lot to the replacement lot;
--   * removing a part-paid credit line in a correction: its unspent released
--     credit is reclaimed (refused if any was spent), instead of the release
--     record silently disappearing and the same money being released again; on
--     a cancelled invoice, a line whose record still holds credit spent before
--     the cancellation cannot be removed or switched at all;
--   * money moving between credit lines without a payment (a correction that
--     withdraws a discount, raises a price or adds a line): released credit
--     above the money now counted toward a line goes back before anything new
--     is released, so the same money is never released to two lines;
--   * a correction that would make a SETTLED credit line worth more than it was
--     issued at is refused: a settled line is never issued again, so the extra
--     money would buy nothing;
--   * cancel, then reopen: the reclaimed credit is given back to the release
--     record, so it is released again as the money is counted;
--   * a payment corrected down or removed: unspent credit released for money
--     no longer recorded goes back (spent credit stays, as credit ahead of
--     payment, squared at settlement or written off by a cancellation);
--   * refunds after settlement: released credit gets a benefit value like the
--     settlement lot, so the remaining benefits are not overvalued, released
--     credit can be refunded or taken back, and a fully released line can be
--     cancelled;
--   * two lines of the same package or bundle: each sale now records the line
--     it was issued for, so released credit is valued and refunded against its
--     own line's sale;
--   * lines 328 repaired (the old lot keeps the release on record, a
--     replacement lot holds the credit): every path above follows the old lot
--     to its replacement.
--
-- NOT CHANGED
--
-- Refunding PART of a payment while the invoice stays open does not take
-- released credit back, then or at later payments, until the invoice settles.
-- That is true of credit packages today as well; it is a shared gap, left for
-- its own change rather than widened into this one. (It also means that on an
-- invoice with a refund, a correction that moves money between credit lines is
-- not capped to the money before the next release: squared at settlement.)
--
-- A SETTLED invoice moved to another customer and then cancelled leaves the
-- credit with the new customer, released or not: the cancel and refund
-- benefit loops read invoice_benefit_values.lot_id, which a move leaves on the
-- emptied lots. That is so in production today for every settled package and
-- bundle; 356 hands a settled line's released lots to the same loops, so they
-- share it. Its fix belongs in those loops (follow credit_lot_current), not
-- here.
--
-- BEFORE THIS REACHES PRODUCTION
--
-- Once this is live, the next payment on INV-2026-0292 or 0293 — and equally
-- any correction to them (lines, discount, even 'Served by') or any status
-- change — releases paid credit for everything received so far, including the
-- $1,963 (0292) and $2,280 (0293) staff already handed over by hand. That must
-- be recorded as already released first, in the same sitting as this
-- migration and before anyone touches either invoice:
-- scripts/credit-policy/record-credit-handed-over.sql, dry run, then the
-- owner's decision. Once a release has run, the script refuses (released_now
-- is no longer 0) and the double credit needs a manual review.
--
-- SAFETY
--
-- The two functions are replaced whole, because the release loop is being
-- restructured rather than tweaked. Each replacement is guarded by the md5 of
-- the exact version it was tested against (the post-355 text): if production
-- holds anything else, this refuses instead of overwriting it.

-- Plain SQL: applies through the Supabase migration tool or the SQL editor as one
-- transaction. From psql, run with -v ON_ERROR_STOP=1.
set lock_timeout = '5s';

-- ── 1. money received is allocated across credit lines of both kinds ────────
do $mig$
declare v_md5 text;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = 'public.credit_package_money_toward_line(uuid)'::regprocedure;
  if position('356:' in pg_get_functiondef('public.credit_package_money_toward_line(uuid)'::regprocedure)) > 0 then
    raise notice '356: credit_package_money_toward_line already counts bundles; left alone.'; return; end if;
  if v_md5 <> '2bedad3ee00bfed49d1e5c1c69087854' then
    raise exception '356: credit_package_money_toward_line is not the version this was tested against (md5 %)', v_md5; end if;

  execute $f$
create or replace function public.credit_package_money_toward_line(p_invoice_item_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $body$
declare v_it public.invoice_items%rowtype; v_received numeric; v_ahead numeric;
begin
  select * into v_it from public.invoice_items where id = p_invoice_item_id;
  -- 356: premium bundles are credit lines too.
  if not found or v_it.line_kind not in ('credit_package','premium_bundle') then return 0; end if;

  select greatest(coalesce(paid_amount,0),0) into v_received
    from public.invoices where id = v_it.invoice_id;

  -- Money toward credit lines is allocated across BOTH kinds, so a package
  -- after a bundle can never be credited with the bundle's money. Order: lines
  -- already settled, then lines already holding released credit (earliest
  -- release first), then the rest by id. A line added by a correction therefore
  -- queues behind money already released to another line, instead of taking it
  -- and having it released a second time.
  with lines as (
    select x.id as line_id, public.invoice_item_external_value(x.id) as line_value,
           x.credit_issued_at is null as unsettled,
           (select min(pl.created_at) from public.credit_package_progress_lots pl
             where pl.invoice_item_id = x.id) as first_release
      from public.invoice_items x
     where x.invoice_id = v_it.invoice_id
       and x.line_kind in ('credit_package','premium_bundle')
  ), queued as (
    select q.line_id, q.line_value,
           row_number() over (order by q.unsettled, q.first_release nulls last, q.line_id) as pos
      from lines q
  )
  select coalesce(sum(a.line_value), 0) into v_ahead
    from queued a
   where a.pos < (select m.pos from queued m where m.line_id = p_invoice_item_id);

  return least(greatest(v_received - v_ahead, 0),
               public.invoice_item_external_value(p_invoice_item_id));
end
$body$;
$f$;
end $mig$;

-- ── 2. a part-paid bundle releases its paid credit as money arrives ─────────
do $mig$
declare v_md5 text;
begin
  if position('356:' in pg_get_functiondef('public.release_credit_package_paid_credit(uuid)'::regprocedure)) > 0 then
    raise notice '356: release_credit_package_paid_credit already releases bundles; left alone.'; return; end if;
  select md5(pg_get_functiondef('public.release_credit_package_paid_credit(uuid)'::regprocedure)) into v_md5;
  if v_md5 <> 'a71b3f47c6cc35ea7f5d9a5f82e75818' then
    raise exception '356: release_credit_package_paid_credit is not the post-355 version this was tested against (md5 %). Apply 355 first.', v_md5; end if;

  execute $f$
create or replace function public.release_credit_package_paid_credit(p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $body$
declare
  v_inv public.invoices%rowtype; v_it record;
  pk public.credit_packages%rowtype; pb public.premium_bundles%rowtype;
  v_entitled numeric; v_target numeric; v_already numeric; v_delta numeric;
  v_restrict jsonb; v_vouchers uuid[]; v_lot uuid; v_out jsonb := '[]'::jsonb;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('skipped', true, 'reason', 'no invoice'); end if;
  if v_inv.status in ('cancelled','refunded') then
    return jsonb_build_object('skipped', true, 'reason', 'invoice ' || v_inv.status); end if;
  if v_inv.customer_id is null then
    return jsonb_build_object('skipped', true, 'reason', 'no customer'); end if;

  -- 356: money can move between credit lines without any payment changing: a
  -- correction withdraws a discount, raises a price or adds a line, and the
  -- money queue shifts. Released credit above the money that now counts toward
  -- its line goes back first (unspent credit only; credit already spent stays,
  -- as credit ahead of payment), so the release below never hands the same
  -- money out twice. An invoice with money refunded keeps the refund's rules
  -- (refunding part of an open invoice does not take released credit back; see
  -- NOT CHANGED), not just in the refund's own transaction: the money queue
  -- does not know which line a refund was for, so capping to it afterwards
  -- would take credit back at the next payment. Settlement squares it.
  if not exists (select 1 from public.invoice_refunds r join public.invoices ri on ri.id = r.invoice_id
                  where r.invoice_id = p_invoice_id
                    and (ri.reopened_at is null or r.created_at > ri.reopened_at)) then
    perform public.trim_released_paid_credit(p_invoice_id, 'Released credit above the money counted toward the line', true);
  end if;

  for v_it in
    select * from public.invoice_items
     where invoice_id = p_invoice_id
       -- 356: premium bundles release their paid credit as the money arrives,
       -- exactly as credit packages have since 327.
       and line_kind in ('credit_package','premium_bundle')
       -- Once the full issuance has run the line is settled; both branches of
       -- trg_create_therapy_on_paid fire on the final payment.
       and credit_issued_at is null
       -- Split lines of either kind keep full-payment issuance.
       and credit_split_allocation_id is null
       and bundle_split_allocation_id is null
       and not exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = invoice_items.id)
     order by id
     for update
  loop
    v_entitled := public.credit_line_paid_entitlement(v_it.id);
    if v_entitled <= 0 then continue; end if;
    v_target  := least(public.credit_package_money_toward_line(v_it.id), v_entitled);
    v_already := public.credit_package_released_paid_credit(v_it.id);
    v_delta   := round(v_target - v_already, 2);
    if v_delta <= 0 then continue; end if;

    if v_it.line_kind = 'credit_package' then
      select * into pk from public.credit_packages where id = v_it.credit_package_id;
      if not found then continue; end if;
      -- The same restrictions the full issuer snapshots.
      select coalesce(array_agg(voucher_id), '{}') into v_vouchers
        from public.credit_package_vouchers where package_id = pk.id;
      v_restrict := jsonb_build_object('allowed_purposes', public.credit_package_purposes(pk.id),
                                       'source', 'credit_package');
      if array_length(v_vouchers, 1) is not null and not pk.allow_voucher then
        v_restrict := v_restrict || jsonb_build_object(
          'allowed_voucher_ids', (select jsonb_agg(v::text) from unnest(v_vouchers) v));
      end if;
      -- Provenance identical to the full issuance: 242 places it as
      -- package_paid, and 309 finds the package's own rules through it.
      v_lot := public.grant_customer_credit(
        v_inv.customer_id, 'paid', v_delta, 'credit_package', pk.id, v_inv.store_id,
        public.sg_today(), null,
        'Credit package (paid so far): ' || pk.name, null, null, auth.uid(), v_restrict);
    else
      select * into pb from public.premium_bundles where id = v_it.premium_bundle_id;
      if not found then continue; end if;
      -- Exactly what sell_premium_bundle gives the bundle's paid credit at
      -- settlement: same source, same restriction. credit_lot_policy reads a
      -- premium_bundle lot with a source record as 'bundle_any', so it spends.
      v_restrict := jsonb_build_object(
        'allowed_purposes', jsonb_build_array('product','voucher','promotion','therapy','rental'),
        'allowed_voucher_ids', '[]'::jsonb, 'source', 'premium_bundle');
      v_lot := public.grant_customer_credit(
        v_inv.customer_id, 'paid', v_delta, 'premium_bundle', pb.id, v_inv.store_id,
        public.sg_today(), null,
        'Premium bundle (paid so far): ' || pb.name, null, null, auth.uid(), v_restrict);
    end if;

    insert into public.credit_package_progress_lots (lot_id, invoice_item_id, invoice_id, released_amount)
    values (v_lot, v_it.id, p_invoice_id, v_delta);

    v_out := v_out || jsonb_build_object(
      'invoice_item_id', v_it.id, 'kind', v_it.line_kind, 'lot_id', v_lot, 'released', v_delta,
      'released_total', v_already + v_delta, 'entitled', v_entitled);
  end loop;

  return jsonb_build_object('released', v_out);
end
$body$;
$f$;
end $mig$;

-- The two replacements keep their grants (create or replace preserves ACLs);
-- restated so a fresh install ends in the same place.
revoke all on function public.credit_package_money_toward_line(uuid) from public, anon, authenticated;
grant execute on function public.credit_package_money_toward_line(uuid) to service_role;
revoke all on function public.release_credit_package_paid_credit(uuid) from public, anon, authenticated;
grant execute on function public.release_credit_package_paid_credit(uuid) to service_role;

-- ── 3. the payment trigger releases for bundles too ─────────────────────────
do $mig$
declare f text; n int;
  c_anchor constant text := $a$    if exists (select 1 from public.invoice_items
                where invoice_id = new.id and line_kind = 'credit_package') then
      perform public.release_credit_package_paid_credit(new.id);
    end if;$a$;
  c_repl constant text := $a$    -- 356: premium bundles release paid credit as it is paid, like packages.
    if exists (select 1 from public.invoice_items
                where invoice_id = new.id and line_kind in ('credit_package','premium_bundle')) then
      perform public.release_credit_package_paid_credit(new.id);
    end if;
    -- 356: money recorded as received went DOWN (a payment corrected or
    -- removed): unspent paid credit released for it goes back. Credit already
    -- spent stays, as credit ahead of payment, and is squared at settlement or
    -- written off by a cancellation. A refund recorded in this transaction
    -- keeps its own rules.
    if coalesce(new.paid_amount,0) < coalesce(old.paid_amount,0)
       and new.status::text not in ('cancelled','refunded')
       and exists (select 1 from public.credit_package_progress_lots pl where pl.invoice_id = new.id)
       and not exists (select 1 from public.invoice_refunds r
                        where r.invoice_id = new.id and r.created_at >= transaction_timestamp()) then
      perform public.trim_released_paid_credit(new.id, 'Recorded payment reduced', true);
    end if;$a$;
begin
  f := pg_get_functiondef('public.trg_create_therapy_on_paid()'::regprocedure);
  if position('356:' in f) > 0 then
    raise notice '356: the payment trigger already releases for bundles; left alone.'; return; end if;
  n := (length(f) - length(replace(f, c_anchor, ''))) / length(c_anchor);
  if n <> 1 then raise exception '356: payment trigger anchor found % times, expected 1', n; end if;
  execute replace(f, c_anchor, c_repl);
end $mig$;

-- ── 3b. released credit stays right on every other path ─────────────────────
-- Before this, released credit was tracked by the lot it was first granted
-- into, and several paths lost it: moving the invoice to another customer (the
-- lot is emptied and a replacement issued), removing the line in a correction
-- (the release record was cascaded away and the money released again), a
-- cancel followed by a reopen (the reclaimed credit still counted as held), and
-- the refund valuation after settlement (released lots had no benefit value,
-- so the remaining benefits were overvalued). Shared with credit packages
-- since 327; 356 makes every part-paid bundle reach them.

-- 0) Each sale made at settlement names the invoice line it was made for, so
--    two lines of the same package or bundle are never confused (the capture
--    in d fills it in; older sales stay null and are never captured again).
alter table public.credit_package_sales add column if not exists invoice_item_id uuid;
alter table public.premium_bundle_sales add column if not exists invoice_item_id uuid;
create index if not exists credit_package_sales_invoice_item_idx on public.credit_package_sales (invoice_item_id);
create index if not exists premium_bundle_sales_invoice_item_idx on public.premium_bundle_sales (invoice_item_id);
comment on column public.credit_package_sales.invoice_item_id is
  'The invoice line this sale was issued for (356). Null on sales made before 356.';
comment on column public.premium_bundle_sales.invoice_item_id is
  'The invoice line this sale was issued for (356). Null on sales made before 356.';

-- a) The lots a released lot became, in order: the lot itself, the lot 328
--    re-granted it into (credit_package_progress_lots.replaces_lot_id: the old
--    row keeps released_amount, the replacement row holds 0), and each lot a
--    customer move issued in its place. The last one is where it is now.
create or replace function public.credit_lot_chain(p_lot_id uuid)
returns uuid[] language plpgsql stable security definer set search_path = public as $fn$
-- 356
declare v_cur uuid := p_lot_id; v_next uuid; v_chain uuid[] := array[p_lot_id];
begin
  loop
    v_next := null;
    select l.id into v_next from public.customer_credit_lots l
     where l.reassigned_from_lot_id = v_cur order by l.created_at desc, l.id desc limit 1;
    if v_next is null then
      select pl.lot_id into v_next from public.credit_package_progress_lots pl
       where pl.replaces_lot_id = v_cur order by pl.created_at desc, pl.lot_id desc limit 1;
    end if;
    exit when v_next is null or v_next = any(v_chain) or cardinality(v_chain) > 12;
    v_chain := v_chain || v_next; v_cur := v_next;
  end loop;
  return v_chain;
end $fn$;

create or replace function public.credit_lot_current(p_lot_id uuid)
returns uuid language sql stable security definer set search_path = public as $fn$
  -- 356
  select c[cardinality(c)] from (select public.credit_lot_chain(p_lot_id) as c) s;
$fn$;

-- b) Taking released credit back (a discount, or less money recorded) follows
--    moves, skips a cancelled or refunded invoice (its credit was already
--    written off), and, for money, never refuses: credit already spent stays
--    as credit ahead of payment.
drop function if exists public.trim_released_paid_credit(uuid, text);
create or replace function public.trim_released_paid_credit(p_invoice_id uuid, p_reason text, p_cap_to_money boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $fn$
-- 355, 356
declare
  v_inv public.invoices%rowtype; v_it record; v_pl record; v_lot public.customer_credit_lots%rowtype;
  v_cur uuid; v_cap numeric; v_excess numeric; v_take numeric; v_out jsonb := '[]'::jsonb;
begin
  select * into v_inv from public.invoices i where i.id = p_invoice_id;
  if not found or v_inv.status::text in ('cancelled','refunded') then
    return jsonb_build_object('trimmed', '[]'::jsonb, 'skipped', true); end if;
  for v_it in
    select x.id from public.invoice_items x
     where x.invoice_id = p_invoice_id
       and x.line_kind in ('credit_package','premium_bundle')
       and x.credit_issued_at is null
     order by x.id
  loop
    v_cap := public.credit_line_paid_entitlement(v_it.id);
    if p_cap_to_money then v_cap := least(v_cap, public.credit_package_money_toward_line(v_it.id)); end if;
    v_excess := round(public.credit_package_released_paid_credit(v_it.id) - v_cap, 2);
    if v_excess <= 0 then continue; end if;
    for v_pl in
      select pl.lot_id, pl.released_amount from public.credit_package_progress_lots pl
       where pl.invoice_item_id = v_it.id and pl.released_amount > 0
       order by pl.created_at desc, pl.lot_id desc
    loop
      exit when v_excess <= 0;
      v_cur := public.credit_lot_current(v_pl.lot_id);
      select * into v_lot from public.customer_credit_lots l where l.id = v_cur for update;
      if not found or v_lot.status <> 'active' or v_lot.remaining_amount <= 0 then continue; end if;
      v_take := least(v_lot.remaining_amount, v_excess, v_pl.released_amount);
      insert into public.customer_credit_ledger(
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, reason, created_by, approved_by)
      values (v_lot.wallet_id, v_lot.customer_id, 'adjust_decrease', v_lot.category, v_take, v_lot.id,
        case when p_cap_to_money then 'invoice_payment_released_credit' else 'invoice_discount_released_credit' end,
        p_invoice_id, v_lot.store_id, p_reason, auth.uid(), auth.uid());
      update public.customer_credit_lots set remaining_amount = remaining_amount - v_take, updated_at = now()
       where id = v_lot.id;
      update public.credit_package_progress_lots set released_amount = released_amount - v_take
       where lot_id = v_pl.lot_id;
      v_excess := round(v_excess - v_take, 2);
      v_out := v_out || jsonb_build_object('invoice_item_id', v_it.id, 'lot_id', v_lot.id, 'taken_back', v_take);
    end loop;
    if v_excess > 0 and not p_cap_to_money then
      raise exception 'CREDIT_ALREADY_SPENT: S$% of the paid credit this discount removes has already been spent. Refund the payment instead of discounting it.', v_excess;
    end if;
  end loop;
  if jsonb_array_length(v_out) > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id,
      case when p_cap_to_money then 'released_credit_trimmed_to_money' else 'released_credit_trimmed_by_discount' end,
      null, jsonb_build_object('lots', v_out), 'credit', p_reason, v_inv.store_id);
  end if;
  return jsonb_build_object('trimmed', v_out);
end $fn$;

-- b2) A settled credit line is never issued again: its paid credit was granted
--     at the value settlement recorded on its sale (355: what was paid for it;
--     before 355, the full credit). A correction that makes it worth more (the
--     invoice's discount withdrawn, the line's price raised) would ask for more
--     money and grant nothing for it. correct_invoice asks this for every
--     settled line when the invoice's discounts changed, and otherwise only for
--     settled lines whose own price went up — so changing another line, which
--     only re-spreads a discount across the lines, is not refused.
drop function if exists public.refuse_settled_credit_line_raise(uuid, uuid[]);
create or replace function public.refuse_settled_credit_line_raise(p_invoice_id uuid, p_line_ids uuid[], p_before jsonb default '{}'::jsonb)
returns void language plpgsql stable security definer set search_path = public as $fn$
-- 356: p_before maps a line id to its entitlement before this correction; a
-- line is refused only when it is now worth more than both that and what it
-- was issued at (so a later correction is not refused for an earlier,
-- allowed re-spread).
declare v_ln record;
begin
  for v_ln in
    select q.entitled, q.settled_at as issued_at, greatest(q.settled_at, coalesce(q.before_ent, q.settled_at)) as allowed_up_to from (
      select public.credit_line_paid_entitlement(x.id) as entitled,
             (p_before->>(x.id::text))::numeric as before_ent,
             greatest(
               coalesce((select max(c.credit_snapshot) from public.credit_package_sales c
                          where x.line_kind = 'credit_package' and c.invoice_id = p_invoice_id
                            and (c.invoice_item_id = x.id or (c.invoice_item_id is null and c.package_id = x.credit_package_id))), -1),
               coalesce((select max(b.paid_credit_snapshot) from public.premium_bundle_sales b
                          where x.line_kind = 'premium_bundle' and b.invoice_id = p_invoice_id
                            and (b.invoice_item_id = x.id or (b.invoice_item_id is null and b.bundle_id = x.premium_bundle_id))), -1)) as settled_at
        from public.invoice_items x
       where x.invoice_id = p_invoice_id and x.line_kind in ('credit_package','premium_bundle')
         and x.credit_issued_at is not null
         and (p_line_ids is null or x.id = any(p_line_ids))
         and x.credit_split_allocation_id is null and x.bundle_split_allocation_id is null
         and not exists (select 1 from public.invoice_credit_splits sp where sp.invoice_item_id = x.id)) q
     where q.settled_at >= 0
  loop
    if v_ln.entitled > v_ln.allowed_up_to + 0.005 then
      raise exception 'CREDIT_LINE_SETTLED: this correction makes a settled credit package or bundle worth S$% of paid credit, but it was issued S$% when it settled, and a settled line cannot be topped up. Keep its price and the invoice discount as they are, or refund the line and sell it again.', round(v_ln.entitled, 2), round(v_ln.issued_at, 2);
    end if;
  end loop;
end $fn$;

-- c) Cancel and full refund: follow moves; leave a lot a settled line recorded
--    as a benefit to the benefit loops (which also let a reopen restore it);
--    give the reclaimed amount back to the release record, so a reopened
--    invoice releases it again as its money is counted.
do $mig$
declare v_md5 text;
begin
  if position('356:' in pg_get_functiondef('public.writeoff_released_credit_on_close(uuid,text,text)'::regprocedure)) > 0 then
    raise notice '356: writeoff_released_credit_on_close already follows moves; left alone.'; return; end if;
  v_md5 := md5(pg_get_functiondef('public.writeoff_released_credit_on_close(uuid,text,text)'::regprocedure));
  if v_md5 <> '3099e17389fa768e5229838174119282' then
    raise exception '356: writeoff_released_credit_on_close is not the version this was tested against (md5 %)', v_md5; end if;
  execute $f$
create or replace function public.writeoff_released_credit_on_close(p_invoice_id uuid, p_reason text, p_event text)
returns jsonb language plpgsql security definer set search_path = public as $body$
-- 356: follows customer moves, leaves settled benefits to the benefit loops, and
-- returns the reclaimed amount to the release record.
declare
  v_pl record; v_lot public.customer_credit_lots%rowtype; v_cur uuid;
  v_take numeric; v_reclaimed numeric := 0; v_written_off numeric := 0; v_store uuid;
begin
  select i.store_id into v_store from public.invoices i where i.id = p_invoice_id;
  -- Only rows that carry a release: a 328 replacement row holds 0 and is
  -- reached through the row it replaces.
  for v_pl in
    select pl.lot_id, pl.released_amount from public.credit_package_progress_lots pl
     where pl.invoice_id = p_invoice_id and pl.released_amount > 0 order by pl.lot_id
  loop
    v_cur := public.credit_lot_current(v_pl.lot_id);
    -- A settled line's benefit row may sit on any lot along the way (a move
    -- after settlement leaves it on the emptied lot); the benefit loops own it.
    if exists (select 1 from public.invoice_benefit_values b
                where b.lot_id = any(public.credit_lot_chain(v_pl.lot_id))) then continue; end if;
    select * into v_lot from public.customer_credit_lots l where l.id = v_cur for update;
    if not found or v_lot.status = 'reversed' then continue; end if;
    v_take := greatest(v_lot.remaining_amount, 0);
    if v_take > 0 then
      insert into public.customer_credit_ledger(
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, reason, created_by, approved_by)
      values (v_lot.wallet_id, v_lot.customer_id, 'adjust_decrease', v_lot.category,
        v_take, v_lot.id, 'invoice_' || p_event || '_released_credit',
        p_invoice_id, v_lot.store_id, p_reason, auth.uid(), auth.uid());
      v_reclaimed := v_reclaimed + v_take;
      update public.credit_package_progress_lots set released_amount = greatest(released_amount - v_take, 0)
       where lot_id = v_pl.lot_id;
    end if;
    v_written_off := v_written_off + greatest(v_pl.released_amount - v_take, 0);
    update public.customer_credit_lots
       set remaining_amount = 0, status = 'reversed', is_locked = true, updated_at = now()
     where id = v_cur;
  end loop;

  if v_reclaimed > 0 or v_written_off > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'released_credit_' || p_event, null,
      jsonb_build_object('reclaimed', v_reclaimed, 'written_off', v_written_off, 'reason', p_reason),
      'credit', p_reason, v_store);
  end if;
  return jsonb_build_object('reclaimed', v_reclaimed, 'written_off', v_written_off);
end $body$;
$f$;
end $mig$;

-- d) At settlement, the credit released before it is part of what the line
--    granted: it gets a benefit row, valued per credit exactly like the
--    settlement lot, so refunds value every benefit correctly, can take the
--    released credit back, and a fully released line can still be cancelled.
do $mig$
declare v_md5 text;
begin
  if position('356:' in pg_get_functiondef('public.capture_invoice_benefit_values(uuid)'::regprocedure)) > 0 then
    raise notice '356: capture_invoice_benefit_values already counts released credit; left alone.'; return; end if;
  v_md5 := md5(pg_get_functiondef('public.capture_invoice_benefit_values(uuid)'::regprocedure));
  if v_md5 <> 'b758222e4688dbfecf7b2fa59f3c7d9a' then
    raise exception '356: capture_invoice_benefit_values is not the version this was tested against (md5 %)', v_md5; end if;
  execute $f$
create or replace function public.capture_invoice_benefit_values(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $body$
-- 356: paid credit released before settlement is captured with the settlement lots.
declare it public.invoice_items%rowtype; s record; l record; v record; rl record; parts jsonb; x jsonb;
 total_weight numeric; value_left numeric; n int; k int; paid numeric; price jsonb; v_released_done boolean := false;
begin
 select * into it from public.invoice_items where id=p_item_id;
 -- The sale(s) this line's issuance just made: not yet claimed by another line.
 -- Lines are issued and captured one at a time, so two lines of the same
 -- package or bundle each get their own sale.
 update public.credit_package_sales c set invoice_item_id=it.id
  where c.invoice_id=it.invoice_id and c.package_id=it.credit_package_id and c.sold_at>=transaction_timestamp()
    and c.invoice_item_id is null;
 update public.premium_bundle_sales b set invoice_item_id=it.id
  where b.invoice_id=it.invoice_id and b.bundle_id=it.premium_bundle_id and b.sold_at>=transaction_timestamp()
    and b.invoice_item_id is null;
 for s in
  select c.id,c.external_paid,c.credit_lot_id paid_lot,c.bonus_credit_lot_id bonus_lot,0 vouchers from public.credit_package_sales c
   where c.invoice_id=it.invoice_id and c.invoice_item_id=it.id and c.sold_at>=transaction_timestamp()
  union all select b.id,b.external_paid,b.paid_credit_lot_id,b.bonus_credit_lot_id,b.vouchers_issued from public.premium_bundle_sales b
   where b.invoice_id=it.invoice_id and b.invoice_item_id=it.id and b.sold_at>=transaction_timestamp()
  order by 1
 loop
  if exists(select 1 from public.invoice_benefit_values where lot_id in(s.paid_lot,s.bonus_lot)) then continue; end if;
  parts:='[]'; total_weight:=0;
  if not v_released_done then
   for rl in select public.credit_lot_current(pl.lot_id) as lot_id, pl.released_amount
               from public.credit_package_progress_lots pl
              where pl.invoice_item_id=it.id and pl.released_amount>0
              order by pl.created_at, pl.lot_id loop
    if exists(select 1 from public.invoice_benefit_values b where b.lot_id=rl.lot_id) then continue; end if;
    parts:=parts||jsonb_build_array(jsonb_build_object('lot_id',rl.lot_id,'granted',rl.released_amount,'weight',rl.released_amount));
    total_weight:=total_weight+rl.released_amount;
   end loop;
   v_released_done:=true;
  end if;
  for l in select * from public.customer_credit_lots where id in(s.paid_lot,s.bonus_lot) order by id loop
   parts:=parts||jsonb_build_array(jsonb_build_object('lot_id',l.id,'granted',l.original_amount,'weight',l.original_amount));
   total_weight:=total_weight+l.original_amount;
  end loop;
  for v in select * from public.customer_reward_vouchers where source_id=s.id order by id loop
   price:=public.voucher_price_for(v.store_id,v.voucher_id,true);
   if not coalesce((price->>'has_price')::boolean,false) or coalesce((price->>'price')::numeric,0)<=0 then
    perform public.write_audit_ex('invoice_items',it.id,'benefit_allocation_review_required',null,jsonb_build_object('sale_id',s.id,'reason','Voucher component has no documented value'),'refunds',null,null);
    return;
   end if;
   parts:=parts||jsonb_build_array(jsonb_build_object('reward_voucher_id',v.id,'granted',v.quantity,'weight',(price->>'price')::numeric*v.quantity));
   total_weight:=total_weight+(price->>'price')::numeric*v.quantity;
  end loop;
  if total_weight<=0 then continue; end if;
  value_left:=s.external_paid; n:=jsonb_array_length(parts); k:=0;
  for x in select * from jsonb_array_elements(parts) loop
   k:=k+1; paid:=case when k=n then value_left else round(s.external_paid*(x->>'weight')::numeric/total_weight,2) end;
   value_left:=value_left-paid;
   insert into public.invoice_benefit_values(invoice_id,invoice_item_id,lot_id,reward_voucher_id,paid_value,granted_value,evidence,created_by)
   values(it.invoice_id,it.id,(x->>'lot_id')::uuid,(x->>'reward_voucher_id')::uuid,paid,(x->>'granted')::numeric,
    'Allocated at issuance from actual discounted external payment, proportional to granted credit (including paid credit released before settlement) and voucher value; sale '||s.id,auth.uid());
  end loop;
 end loop;
end $body$;
$f$;
end $mig$;

-- e) A credit line removed in a correction while part-paid takes its released
--    credit with it: unspent credit is reclaimed, and if any was spent the
--    correction is refused (keep the line, or cancel the invoice). The release
--    record can no longer be deleted with the line behind anyone's back. A line
--    kept but switched to another package or bundle counts as removed: the old
--    product's credit, with its rules, goes back, and the money is released
--    again under the new product.
create or replace function public.reclaim_released_credit_of_removed_lines(p_invoice_id uuid, p_items jsonb, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
-- 356
declare v_pl record; v_lot public.customer_credit_lots%rowtype; v_cur uuid; v_take numeric;
        v_spent numeric := 0; v_reclaimed numeric := 0; v_lines uuid[] := '{}'; v_closed boolean;
begin
  -- A cancelled or refunded invoice already had its released credit taken back
  -- or written off when it closed: nothing is left to reclaim. A line whose
  -- release record is back at 0 can go; one still holding the credit spent and
  -- written off cannot, or a reopen would release that credit again.
  select i.status::text in ('cancelled','refunded') into v_closed from public.invoices i where i.id = p_invoice_id;
  for v_pl in
    select pl.lot_id, pl.released_amount, pl.invoice_item_id
      from public.credit_package_progress_lots pl
      join public.invoice_items ii on ii.id = pl.invoice_item_id
     where pl.invoice_id = p_invoice_id and ii.credit_issued_at is null
       and not exists (select 1 from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
                        where nullif(x->>'invoice_item_id','')::uuid = pl.invoice_item_id
                          and coalesce(x->>'kind','product') = ii.line_kind::text
                          and nullif(x->>'credit_package_id','')::uuid is not distinct from ii.credit_package_id
                          and nullif(x->>'premium_bundle_id','')::uuid is not distinct from ii.premium_bundle_id)
     order by pl.lot_id
  loop
    v_lines := v_lines || v_pl.invoice_item_id;
    -- A 328 replacement row holds 0; its lot is reached through the row it replaces.
    if v_pl.released_amount <= 0 then continue; end if;
    -- Closed: what a release row still holds is credit spent before the
    -- cancellation and written off. It is the record a reopen relies on, so it
    -- cannot be deleted with the line.
    if coalesce(v_closed, false) then v_spent := v_spent + v_pl.released_amount; continue; end if;
    v_cur := public.credit_lot_current(v_pl.lot_id);
    select * into v_lot from public.customer_credit_lots l where l.id = v_cur for update;
    v_take := 0;
    if found and v_lot.status <> 'reversed' and v_lot.remaining_amount > 0 then
      v_take := least(v_lot.remaining_amount, v_pl.released_amount);
      insert into public.customer_credit_ledger(
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, reason, created_by, approved_by)
      values (v_lot.wallet_id, v_lot.customer_id, 'adjust_decrease', v_lot.category, v_take, v_lot.id,
        'invoice_line_removed_released_credit', p_invoice_id, v_lot.store_id, p_reason, auth.uid(), auth.uid());
      update public.customer_credit_lots
         set remaining_amount = remaining_amount - v_take,
             status = case when remaining_amount - v_take <= 0 then 'reversed' else status end,
             updated_at = now()
       where id = v_lot.id;
      v_reclaimed := v_reclaimed + v_take;
    end if;
    v_spent := v_spent + greatest(v_pl.released_amount - v_take, 0);
  end loop;
  if v_spent > 0 and coalesce(v_closed, false) then
    raise exception 'CREDIT_ALREADY_SPENT: S$% of the paid credit released for a line being removed or changed was spent before this invoice was cancelled, and is on record against the line. Keep the line as it is.', round(v_spent, 2);
  end if;
  if v_spent > 0 then
    raise exception 'CREDIT_ALREADY_SPENT: S$% of the paid credit released for a line being removed or changed has already been spent. Keep the line as it is, or cancel the invoice.', round(v_spent, 2);
  end if;
  if array_length(v_lines, 1) is not null then
    delete from public.credit_package_progress_lots pl where pl.invoice_id = p_invoice_id and pl.invoice_item_id = any(v_lines);
    perform public.write_audit_ex('invoices', p_invoice_id, 'released_credit_reclaimed_line_removed', null,
      jsonb_build_object('lines', to_jsonb(v_lines), 'reclaimed', v_reclaimed), 'credit', p_reason,
      (select i.store_id from public.invoices i where i.id = p_invoice_id));
  end if;
  return jsonb_build_object('reclaimed', v_reclaimed, 'lines', to_jsonb(v_lines));
end $fn$;

do $mig$
declare f text; n int;
  c_anchor constant text := $a$  delete from public.invoice_items ii where invoice_id = p_invoice_id
    and not exists(select 1 from jsonb_array_elements(p_items) x where nullif(x->>'invoice_item_id','')::uuid=ii.id);$a$;
begin
  f := pg_get_functiondef('public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'::regprocedure);
  if position('reclaim_released_credit_of_removed_lines' in f) > 0 then
    raise notice '356: update_invoice_internal already reclaims removed lines'' credit; left alone.'; return; end if;
  n := (length(f) - length(replace(f, c_anchor, ''))) / length(c_anchor);
  if n <> 1 then raise exception '356: update_invoice_internal line-delete anchor found % times, expected 1', n; end if;
  execute replace(f, c_anchor,
    E'  -- 356: a part-paid credit line being removed takes its released paid credit with it.\n'
    || E'  perform public.reclaim_released_credit_of_removed_lines(p_invoice_id, p_items, coalesce(p_edit_reason, ''Line removed in a correction''));\n'
    || c_anchor);
end $mig$;

-- The release record is evidence: a line with released credit cannot be
-- deleted without going through the reclaim above.
do $mig$
begin
  if exists (select 1 from pg_constraint where conname = 'credit_package_progress_lots_invoice_item_id_fkey'
               and conrelid = 'public.credit_package_progress_lots'::regclass and confdeltype = 'c') then
    alter table public.credit_package_progress_lots drop constraint credit_package_progress_lots_invoice_item_id_fkey;
    alter table public.credit_package_progress_lots add constraint credit_package_progress_lots_invoice_item_id_fkey
      foreign key (invoice_item_id) references public.invoice_items(id);
  end if;
end $mig$;

-- f) A refund of released credit recalculates commission like any other
--    benefit: its sale is the sale of the same line.
do $mig$
declare v_md5 text;
begin
  if position('356:' in pg_get_functiondef('public.invoice_commission_benefit_source(uuid)'::regprocedure)) > 0 then
    raise notice '356: invoice_commission_benefit_source already traces released credit; left alone.'; return; end if;
  v_md5 := md5(pg_get_functiondef('public.invoice_commission_benefit_source(uuid)'::regprocedure));
  if v_md5 <> '8c6009f43da4a31bf5bfdf73a8ffe6fc' then
    raise exception '356: invoice_commission_benefit_source is not the version this was tested against (md5 %)', v_md5; end if;
  execute $f$
create or replace function public.invoice_commission_benefit_source(p_benefit_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $body$
-- 356: a benefit on credit released before settlement belongs to the sale of its line.
declare b public.invoice_benefit_values%rowtype; current_id uuid:=p_benefit_id;
 parents uuid[]; visited uuid[]:='{}'; sources jsonb; original_line uuid;
begin
 loop
  if current_id=any(visited) or cardinality(visited)>64 then raise exception 'Commission review required: benefit provenance contains a cycle.'; end if;
  visited:=array_append(visited,current_id);
  select * into b from public.invoice_benefit_values where id=current_id;
  if not found then raise exception 'Commission review required: the original refunded benefit allocation is missing.'; end if;
  original_line:=coalesce(original_line,b.invoice_item_id);
  if b.invoice_item_id<>original_line then raise exception 'Commission review required: benefit provenance crosses invoice lines.'; end if;
  select array_agg(distinct parent_id) into parents from (
   select t.source_benefit_id parent_id from public.invoice_benefit_transfers t where t.replacement_benefit_id=b.id
   union select q.benefit_id from public.invoice_reopen_vouchers q where q.replacement_voucher_id=b.reward_voucher_id
  ) parent;
  if coalesce(cardinality(parents),0)=0 then exit; end if;
  if cardinality(parents)<>1 then raise exception 'Commission review required: the refunded benefit has multiple possible original sources.'; end if;
  current_id:=parents[1];
 end loop;
 select jsonb_agg(to_jsonb(s)) into sources from (
  select 'credit_package'::text sale_kind,c.id sale_id,b.invoice_item_id invoice_item_id
   from public.credit_package_sales c where c.invoice_id=b.invoice_id and b.lot_id in(c.credit_lot_id,c.bonus_credit_lot_id)
  union all
  select 'premium_bundle',p.id,b.invoice_item_id from public.premium_bundle_sales p
   where p.invoice_id=b.invoice_id and (b.lot_id in(p.paid_credit_lot_id,p.bonus_credit_lot_id)
    or exists(select 1 from public.customer_reward_vouchers v where v.id=b.reward_voucher_id and v.source_id=p.id))
  union all
  -- Paid credit released before settlement: the lot is recorded against the
  -- line in credit_package_progress_lots, and the sale issued for that same
  -- line (never another line of the same product) is its source.
  select 'credit_package',c.id,b.invoice_item_id
   from public.credit_package_sales c
   where c.invoice_id=b.invoice_id and c.invoice_item_id=b.invoice_item_id and b.lot_id is not null
     and exists(select 1 from public.credit_package_progress_lots pl
                 where pl.invoice_item_id=b.invoice_item_id and b.lot_id=any(public.credit_lot_chain(pl.lot_id)))
  union all
  select 'premium_bundle',p.id,b.invoice_item_id
   from public.premium_bundle_sales p
   where p.invoice_id=b.invoice_id and p.invoice_item_id=b.invoice_item_id and b.lot_id is not null
     and exists(select 1 from public.credit_package_progress_lots pl
                 where pl.invoice_item_id=b.invoice_item_id and b.lot_id=any(public.credit_lot_chain(pl.lot_id)))
 ) s;
 if coalesce(jsonb_array_length(sources),0)<>1 then
  raise exception 'Commission review required: resolve the original paid/bonus lot or voucher source for benefit % before recalculating this refund.',p_benefit_id;
 end if;
 return sources->0;
end $body$;
$f$;
end $mig$;

-- g) Money already received counts toward a credit line added or swapped in by
--    a correction at once, not only at the next payment; and a correction may
--    not make a settled credit line worth more than it was issued at (b2).
do $mig$
declare f text; n int;
  c_decl constant text := $a$declare i public.invoices%rowtype; n public.invoices%rowtype; c record; same_lines boolean; same_header boolean;$a$;
  c_upd constant text := $a$  perform public.update_invoice_internal(i.id,n.customer_id,$a$;
  c_anchor constant text := $a$  perform public.trim_released_paid_credit(i.id, coalesce(p_reason,'Invoice corrected'));$a$;
begin
  f := pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure);
  if position('356:' in f) > 0 then raise notice '356: correct_invoice already releases for a swapped line; left alone.'; return; end if;
  if (length(f) - length(replace(f, c_decl, ''))) / length(c_decl) <> 1
     or (length(f) - length(replace(f, c_upd, ''))) / length(c_upd) <> 1 then
    raise exception '356: correct_invoice declare/update anchors not found exactly once'; end if;
  n := (length(f) - length(replace(f, c_anchor, ''))) / length(c_anchor);
  if n <> 1 then raise exception '356: correct_invoice trim anchor found % times, expected 1 (apply 355 first)', n; end if;
  f := replace(f, c_decl, c_decl || ' v356_prices jsonb; v356_worth jsonb;');
  f := replace(f, c_upd, $r$  -- 356: settled credit lines' prices and worth before this correction.
  v356_prices := (select coalesce(jsonb_object_agg(x.id::text, x.unit_price), '{}'::jsonb) from public.invoice_items x
                   where x.invoice_id = i.id and x.line_kind in ('credit_package','premium_bundle')
                     and x.credit_issued_at is not null);
  v356_worth := (select coalesce(jsonb_object_agg(x.id::text, public.credit_line_paid_entitlement(x.id)), '{}'::jsonb)
                   from public.invoice_items x
                  where x.invoice_id = i.id and x.line_kind in ('credit_package','premium_bundle')
                    and x.credit_issued_at is not null);
$r$ || c_upd);
  f := replace(f, c_anchor, c_anchor || $r$
  -- 356: a settled credit line may not be made worth more than it was issued at:
  -- every settled line when the invoice's discounts changed, otherwise those
  -- whose own price went up.
  perform public.refuse_settled_credit_line_raise(i.id,
    case when (coalesce(n.manual_discount,0),n.discount_voucher_id,coalesce(n.save_earth_applied,false),coalesce(n.save_earth_amount,0))
              is distinct from
              (coalesce(i.manual_discount,0),i.discount_voucher_id,coalesce(i.save_earth_applied,false),coalesce(i.save_earth_amount,0)) then null
         else array(select x.id from public.invoice_items x
                     where x.invoice_id = i.id and x.credit_issued_at is not null
                       and x.unit_price > coalesce((v356_prices->>(x.id::text))::numeric, x.unit_price)) end,
    -- A discount cut (manual discount lowered, voucher changed or removed, Save
    -- Earth lowered) is held to what the line was issued at; otherwise a line
    -- already worth more after an allowed re-spread is held to that.
    case when coalesce(n.manual_discount,0) < coalesce(i.manual_discount,0)
              or n.discount_voucher_id is distinct from i.discount_voucher_id
              or coalesce(n.save_earth_amount,0) < coalesce(i.save_earth_amount,0)
              or (coalesce(i.save_earth_applied,false) and not coalesce(n.save_earth_applied,false))
         then '{}'::jsonb else v356_worth end);
  -- 356: money already received counts toward a credit line this correction added or swapped in.
  perform public.release_credit_package_paid_credit(i.id);$r$);
  execute f;
end $mig$;

revoke all on function public.credit_lot_chain(uuid) from public, anon, authenticated;
revoke all on function public.refuse_settled_credit_line_raise(uuid,uuid[],jsonb) from public, anon, authenticated;
revoke all on function public.credit_lot_current(uuid) from public, anon, authenticated;
revoke all on function public.trim_released_paid_credit(uuid,text,boolean) from public, anon, authenticated;
revoke all on function public.reclaim_released_credit_of_removed_lines(uuid,jsonb,text) from public, anon, authenticated;
grant execute on function public.credit_lot_chain(uuid) to service_role;
grant execute on function public.refuse_settled_credit_line_raise(uuid,uuid[],jsonb) to service_role;
grant execute on function public.credit_lot_current(uuid) to service_role;
grant execute on function public.trim_released_paid_credit(uuid,text,boolean) to service_role;
grant execute on function public.reclaim_released_credit_of_removed_lines(uuid,jsonb,text) to service_role;

-- ── 4. guards ────────────────────────────────────────────────────────────────
do $mig$
begin
  if position('356:' in pg_get_functiondef('public.credit_package_money_toward_line(uuid)'::regprocedure)) = 0
  or position('356:' in pg_get_functiondef('public.release_credit_package_paid_credit(uuid)'::regprocedure)) = 0
  or position('356:' in pg_get_functiondef('public.trg_create_therapy_on_paid()'::regprocedure)) = 0 then
    raise exception '356: a part of the bundle release is missing'; end if;

  if position('356:' in pg_get_functiondef('public.writeoff_released_credit_on_close(uuid,text,text)'::regprocedure)) = 0
  or position('356:' in pg_get_functiondef('public.capture_invoice_benefit_values(uuid)'::regprocedure)) = 0
  or position('reclaim_released_credit_of_removed_lines' in pg_get_functiondef('public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'::regprocedure)) = 0
  or position('356:' in pg_get_functiondef('public.invoice_commission_benefit_source(uuid)'::regprocedure)) = 0
  or position('356:' in pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) = 0
  or position('refuse_settled_credit_line_raise' in pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) = 0
  or to_regprocedure('public.trim_released_paid_credit(uuid,text)') is not null
  or not exists (select 1 from information_schema.columns where table_schema = 'public'
                   and table_name = 'premium_bundle_sales' and column_name = 'invoice_item_id')
  or position('invoice_item_id=it.id' in pg_get_functiondef('public.capture_invoice_benefit_values(uuid)'::regprocedure)) = 0
  or exists (select 1 from pg_constraint where conname = 'credit_package_progress_lots_invoice_item_id_fkey' and confdeltype = 'c') then
    raise exception '356: part of keeping released credit right is missing'; end if;

  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
               and p.proname in ('credit_package_money_toward_line','release_credit_package_paid_credit',
                                 'credit_lot_current','credit_lot_chain','trim_released_paid_credit','reclaim_released_credit_of_removed_lines',
                                 'refuse_settled_credit_line_raise',
                                 'writeoff_released_credit_on_close','capture_invoice_benefit_values')
               and (has_function_privilege('anon', p.oid, 'execute')
                 or has_function_privilege('authenticated', p.oid, 'execute'))) then
    raise exception '356: an internal release function is reachable from the client'; end if;

  -- The released credit must be spendable: a premium_bundle lot with a source.
  if public.credit_lot_policy('premium_bundle','paid',true) <> 'bundle_any' then
    raise exception '356: released bundle credit would not be spendable'; end if;

  raise notice '356 applied: a part-paid premium bundle releases its paid credit as the money arrives.';
end $mig$;

notify pgrst, 'reload schema';
