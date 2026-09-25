-- 355_a_discounted_credit_purchase_grants_what_was_paid.sql
--
-- WHAT WAS WRONG
--
-- "A credit package cannot be discounted." Checked against every discount
-- mechanism on real invoices, the truth was worse for bundles and different
-- for packages:
--
--   * A DISCOUNTED PREMIUM BUNDLE COULD NEVER BE COMPLETED. The issuer called
--     sell_premium_bundle with a discount of 0, so it demanded the full list
--     price, raised "The bundle needs 15000.00 but only 11006.00 was paid
--     externally" inside the payment trigger, and rolled the payment back.
--     INV-2026-0292 ($15,000 bundle, S$3,994 manual discount) is in exactly this
--     state: its final payment would be refused today.
--
--   * A DISCOUNTED CREDIT PACKAGE SETTLED, BUT OVER-GRANTED. issue_credit_package
--     ignored what was paid and always granted the package's full paid credit,
--     so a $500 package sold for $400 handed over $500.
--
--   * A per-line voucher on a credit line was silently dropped: no discount and
--     no error.
--
-- THE RULE, as the owner decided it: a discounted credit package or premium
-- bundle grants PAID credit equal to what was actually paid for it. Bonus
-- credit and free vouchers are unchanged.
--
-- WHAT THIS DOES
--
-- 0. invoice_item_external_value allocates each discount the way it was given:
--    a line voucher to its own line only, the manual discount across every line,
--    a discount voucher across the lines it may fund (never third-party). The
--    old flat proration let a product's own line voucher reduce the package
--    beside it. The three issuers stop carrying private copies of the old
--    formula and call this one.
-- 1. credit_line_paid_entitlement(line) is the single definition of what a
--    credit line's paid credit is worth: the defined paid credit, scaled by what
--    was actually paid for the line. An FOC portion counts as a gift of the
--    package, not a discount on it — the behaviour saved FOC credit purchases
--    have always had, kept deliberately (see "not changed" below).
-- 2-6. Every place that decides how much paid credit to release or grant asks
--    that function, per LINE: the part-payment release (327), the settlement
--    issuers, and the split-customer children. issue_credit_package and
--    sell_premium_bundle learn which line they are issuing, so each line
--    subtracts only its OWN earlier releases (the old code summed releases
--    across every line of the same package, so two $500 lines paid 600 then
--    400 left the customer holding 600).
-- 7. A credit line added during a correction records the catalogue price as its
--    original price, so an owner's price override on it counts as a discount.
-- 8. A line voucher or FOC on a NEW credit line is refused with a clear message
--    instead of being silently dropped. Lines kept unchanged in a correction are
--    never checked, so correcting an invoice that already has an FOC'd package
--    keeps working. FOC is read from the line's own data, not a local variable:
--    the legacy 7-argument create_invoice never declared v_foc_qty, and a
--    reference to it would install cleanly and then fail at the till.
-- 9. A discount given AFTER paid credit was already released can leave the line
--    worth less than the customer holds. correct_invoice now takes back the
--    unspent excess, and refuses — saying why — if it has been spent.
--
-- NOT CHANGED, DELIBERATELY
--
-- "Make FOC" on a saved invoice still gives a credit package or bundle away with
-- its full credit, as today. Whether FOC should stay a gift, be forbidden, or be
-- treated as a 100% discount is an open business question for the owner.
--
-- SAFETY
--
-- issue_credit_package and sell_premium_bundle are dropped and recreated with
-- one extra parameter that defaults to NULL. Neither is granted to anon or
-- authenticated, and only two functions call them, so no client can reach them
-- and PostgREST can never see two candidates. Every edit below goes through
-- pg_temp.p355, which refuses unless its anchor occurs exactly the expected
-- number of times: an edit that no longer applies stops the migration instead
-- of silently doing nothing. Every block is re-runnable.

-- Plain SQL: applies through the Supabase migration tool or the SQL editor as one
-- transaction. From psql, run with -v ON_ERROR_STOP=1.
set lock_timeout = '5s';

-- One guarded edit. Raises unless the anchor occurs exactly p_expect times.
create or replace function pg_temp.p355(p_def text, p_anchor text, p_repl text,
                                        p_where text, p_expect int default 1)
returns text language plpgsql as $f$
declare n int;
begin
  if coalesce(length(p_anchor), 0) = 0 then
    raise exception '355: empty anchor at %', p_where; end if;
  n := (length(p_def) - length(replace(p_def, p_anchor, ''))) / length(p_anchor);
  if n <> p_expect then
    raise exception '355: % — anchor found % times, expected %: %',
      p_where, n, p_expect, left(p_anchor, 90); end if;
  return replace(p_def, p_anchor, p_repl);
end $f$;

-- ── 0. the money attributable to one line ───────────────────────────────────
create or replace function public.invoice_item_external_value(p_invoice_item_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_it public.invoice_items%rowtype; v_inv public.invoices%rowtype;
  v_line_disc_sum numeric; v_manual numeric; v_voucher numeric; v_net numeric;
  v_voucher_base numeric; v_third boolean; v_ext numeric;
begin
  select * into v_it from public.invoice_items where id = p_invoice_item_id;
  if not found then return 0; end if;
  select * into v_inv from public.invoices where id = v_it.invoice_id;

  select coalesce(sum(coalesce(x.line_discount,0)),0) into v_line_disc_sum
    from public.invoice_items x where x.invoice_id = v_it.invoice_id;
  v_manual  := least(greatest(coalesce(v_inv.manual_discount,0),0), greatest(coalesce(v_inv.subtotal,0),0));
  v_voucher := greatest(coalesce(v_inv.discount_total,0) - v_line_disc_sum - v_manual, 0);
  v_net := coalesce(v_it.line_total,0) - coalesce(v_it.line_discount,0);
  v_third := v_it.line_kind = 'product' and exists (
    select 1 from public.products pr where pr.id = v_it.product_id and pr.product_type::text = 'third_party');

  select coalesce(sum(coalesce(x.line_total,0) - coalesce(x.line_discount,0)),0) into v_voucher_base
    from public.invoice_items x
   where x.invoice_id = v_it.invoice_id
     and not (x.line_kind = 'product' and exists (
       select 1 from public.products pr where pr.id = x.product_id and pr.product_type::text = 'third_party'));

  v_ext := v_net
    - case when coalesce(v_inv.subtotal,0) > 0
           then v_manual * coalesce(v_it.line_total,0) / v_inv.subtotal else 0 end
    - case when v_voucher > 0 and not v_third and v_voucher_base > 0
           then v_voucher * v_net / v_voucher_base else 0 end;
  return greatest(round(v_ext, 2), 0);
end $fn$;
revoke all on function public.invoice_item_external_value(uuid) from public, anon, authenticated;
grant execute on function public.invoice_item_external_value(uuid) to service_role;

-- ── 0b. the issuers stop carrying their own copy of the old proration ───────
do $mig$
declare f text; fn text; n int;
begin
  foreach fn in array array['public.issue_credit_lines_for_invoice(uuid)',
                            'public.issue_credit_package_invoice_item(uuid)',
                            'public.issue_premium_bundle_invoice_item(uuid)'] loop
    f := pg_get_functiondef(fn::regprocedure);
    if position('v_external := public.invoice_item_external_value(v_it.id);' in f) > 0 then
      raise notice '355: % already uses invoice_item_external_value; left alone.', fn; continue; end if;
    n := length(f);
    f := regexp_replace(f,
      'v_external := round\(coalesce\(v_it\.line_total,0\)\s+- case when coalesce\(v_inv\.subtotal,0\) > 0\s+then coalesce\(v_inv\.discount_total,0\) \* \(coalesce\(v_it\.line_total,0\) / v_inv\.subtotal\)\s+else 0 end, 2\);',
      'v_external := public.invoice_item_external_value(v_it.id);');
    if length(f) = n then raise exception '355: % — the external-value anchor is missing', fn; end if;
    execute f;
  end loop;
end $mig$;

-- ── 1. one definition of what a credit line's paid credit is worth ──────────
create or replace function public.credit_line_paid_entitlement(p_invoice_item_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_it public.invoice_items%rowtype; v_full numeric; v_gross numeric; v_paid numeric;
begin
  select * into v_it from public.invoice_items where id = p_invoice_item_id;
  if not found or v_it.line_kind not in ('credit_package','premium_bundle') then return 0; end if;

  -- The paid credit the line was sold with, before any discount.
  v_full := coalesce(v_it.credit_paid_snapshot,
    case when v_it.line_kind = 'credit_package'
         then (select pk.paid_credit_amount from public.credit_packages pk where pk.id = v_it.credit_package_id)
         else (select pb.paid_credit_amount from public.premium_bundles pb where pb.id = v_it.premium_bundle_id) end, 0);

  -- The undiscounted price that paid credit corresponds to.
  v_gross := coalesce(
    (select a.payment_amount from public.credit_package_split_allocations a where a.id = v_it.credit_split_allocation_id),
    (select a.payment_amount from public.premium_bundle_split_allocations a where a.id = v_it.bundle_split_allocation_id),
    coalesce(v_it.original_price, v_it.unit_price) * v_it.quantity);
  if coalesce(v_gross, 0) <= 0 then return greatest(v_full, 0); end if;

  -- What the customer actually pays for the line after a price correction and
  -- its share of every invoice-level discount. An FOC portion is a gift of the
  -- package, not a discount on it, so it still carries its credit.
  v_paid := public.invoice_item_external_value(p_invoice_item_id) + coalesce(v_it.foc_amount, 0);
  return greatest(round(v_full * least(v_paid, v_gross) / v_gross, 2), 0);
end $fn$;
revoke all on function public.credit_line_paid_entitlement(uuid) from public, anon, authenticated;
grant execute on function public.credit_line_paid_entitlement(uuid) to service_role;

-- ── 2. part-payment release never targets more than the entitlement ─────────
do $mig$
declare f text;
begin
  f := pg_get_functiondef('public.release_credit_package_paid_credit(uuid)'::regprocedure);
  if position('credit_line_paid_entitlement' in f) > 0 then
    raise notice '355: release_credit_package_paid_credit already capped; left alone.'; return; end if;
  f := pg_temp.p355(f,
    $a$    v_entitled := coalesce(v_it.credit_paid_snapshot, pk.paid_credit_amount, 0);$a$,
    $a$    v_entitled := public.credit_line_paid_entitlement(v_it.id);$a$,
    'release_credit_package_paid_credit');
  execute f;
end $mig$;

-- ── 3. issue_credit_package learns which line it is issuing ─────────────────
do $mig$
declare f text;
begin
  if to_regprocedure('public.issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)') is not null then
    raise notice '355: issue_credit_package already takes a line; left alone.'; return; end if;
  f := pg_get_functiondef('public.issue_credit_package(uuid,uuid,uuid,numeric,uuid)'::regprocedure);

  f := pg_temp.p355(f, $a$p_invoice_id uuid DEFAULT NULL::uuid)$a$,
       $a$p_invoice_id uuid DEFAULT NULL::uuid, p_invoice_item_id uuid DEFAULT NULL::uuid)$a$,
       'issue_credit_package signature');
  f := pg_temp.p355(f, $a$  v_bonus numeric;
begin$a$, $a$  v_bonus numeric; v_credit numeric;
begin$a$, 'issue_credit_package declare');
  f := pg_temp.p355(f,
    $a$  if p_customer_id is null then raise exception 'A customer is required to issue package credit'; end if;
$a$,
    $a$  if p_customer_id is null then raise exception 'A customer is required to issue package credit'; end if;
  -- 355: without a line this is the full package (legacy and non-invoice paths).
  v_credit := coalesce(pk.paid_credit_amount, 0);
$a$, 'issue_credit_package default credit');
  f := pg_temp.p355(f,
    $a$    if p_invoice_id is not null then
      select coalesce(sum(public.credit_package_released_paid_credit(it.id)), 0) into v_released$a$,
    $a$    if p_invoice_item_id is not null then
      -- 355: this line's own entitlement (what was actually paid for it), less
      -- what THIS line has already released — never another line's.
      v_credit := public.credit_line_paid_entitlement(p_invoice_item_id);
      v_released := public.credit_package_released_paid_credit(p_invoice_item_id);
    elsif p_invoice_id is not null then
      select coalesce(sum(public.credit_package_released_paid_credit(it.id)), 0) into v_released$a$,
    'issue_credit_package per-line release');
  f := pg_temp.p355(f, $a$v_remaining := round(coalesce(pk.paid_credit_amount,0) - v_released, 2);$a$,
                       $a$v_remaining := round(v_credit - v_released, 2);$a$, 'issue_credit_package remaining');
  f := pg_temp.p355(f, $a$pk.customer_price, pk.paid_credit_amount, pk.commission_classification,$a$,
                       $a$pk.customer_price, v_credit, pk.commission_classification,$a$, 'issue_credit_package sale snapshot');
  f := pg_temp.p355(f, $a$'credit', pk.paid_credit_amount,$a$, $a$'credit', v_credit,$a$, 'issue_credit_package audit');
  f := pg_temp.p355(f, $a$'credit_issued', pk.paid_credit_amount,$a$, $a$'credit_issued', v_credit,$a$, 'issue_credit_package return');

  drop function public.issue_credit_package(uuid,uuid,uuid,numeric,uuid);
  execute f;
  revoke all on function public.issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid) from public, anon, authenticated;
  grant execute on function public.issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid) to service_role;
end $mig$;

-- ── 4. sell_premium_bundle learns which line it is issuing ──────────────────
do $mig$
declare f text;
begin
  if to_regprocedure('public.sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)') is not null then
    raise notice '355: sell_premium_bundle already takes a line; left alone.'; return; end if;
  f := pg_get_functiondef('public.sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean)'::regprocedure);

  f := pg_temp.p355(f, $a$p_is_completed_foc boolean DEFAULT false)$a$,
       $a$p_is_completed_foc boolean DEFAULT false, p_invoice_item_id uuid DEFAULT NULL::uuid)$a$,
       'sell_premium_bundle signature');
  f := pg_temp.p355(f, $a$  v_comm jsonb;
begin$a$, $a$  v_comm jsonb; v_paid_total numeric; v_paid_credit numeric;
begin$a$, 'sell_premium_bundle declare');
  f := pg_temp.p355(f,
    $a$  if not coalesce(p_is_completed_foc,false) and round(v_external,2) < v_due then$a$,
    $a$  -- 355: sold on an invoice, the line's own charge after its discount and
  -- FOC is what is due, and its paid credit is what was actually paid. Before
  -- this the discount was ignored here, so a discounted bundle was refused.
  v_paid_total := coalesce(b.paid_credit_amount, 0);
  if p_invoice_item_id is not null then
    v_due := public.invoice_item_external_value(p_invoice_item_id);
    v_paid_total := public.credit_line_paid_entitlement(p_invoice_item_id);
  end if;
  v_paid_credit := greatest(round(v_paid_total - case when p_invoice_item_id is null then 0
    else public.credit_package_released_paid_credit(p_invoice_item_id) end, 2), 0);
  if not coalesce(p_is_completed_foc,false) and round(v_external,2) < v_due then$a$,
    'sell_premium_bundle due');
  f := pg_temp.p355(f,
    $a$  if b.paid_credit_amount > 0 then
    v_paid_lot := public.grant_customer_credit(p_customer_id, 'paid', b.paid_credit_amount,$a$,
    $a$  if v_paid_credit > 0 then
    v_paid_lot := public.grant_customer_credit(p_customer_id, 'paid', v_paid_credit,$a$,
    'sell_premium_bundle paid lot');
  f := pg_temp.p355(f, $a$b.customer_payment_amount, b.paid_credit_amount, b.bonus_credit_amount, b.free_voucher_qty,$a$,
                       $a$b.customer_payment_amount, v_paid_total, b.bonus_credit_amount, b.free_voucher_qty,$a$,
                       'sell_premium_bundle sale snapshot');
  -- Twice on purpose: once in the audit entry, once in the return value.
  f := pg_temp.p355(f, $a$'paid_credit', b.paid_credit_amount,$a$, $a$'paid_credit', v_paid_total,$a$,
                       'sell_premium_bundle audit+return', 2);

  drop function public.sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean);
  execute f;
  revoke all on function public.sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid) from public, anon, authenticated;
  grant execute on function public.sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid) to service_role;
end $mig$;

-- ── 5. the invoice issuer passes the line to both ───────────────────────────
do $mig$
declare f text; n int;
begin
  f := pg_get_functiondef('public.issue_credit_lines_for_invoice(uuid)'::regprocedure);
  if position('coalesce(v_it.unit_price,0), v_it.id);' in f) > 0 then
    raise notice '355: issue_credit_lines_for_invoice already passes the line; left alone.'; return; end if;
  n := length(f);
  f := regexp_replace(f,
    '(v_res := public\.issue_credit_package\(v_it\.credit_package_id, v_inv\.customer_id,\s+v_inv\.store_id, v_external, p_invoice_id)\);',
    '\1, v_it.id);');
  if length(f) = n then raise exception '355: issue_credit_lines_for_invoice — package call anchor missing'; end if;
  f := pg_temp.p355(f, $a$coalesce(v_it.foc_amount,0) >= coalesce(v_it.unit_price,0));$a$,
                       $a$coalesce(v_it.foc_amount,0) >= coalesce(v_it.unit_price,0), v_it.id);$a$,
                       'issue_credit_lines_for_invoice bundle call');
  execute f;
end $mig$;

-- ── 6. split-customer children: allocated paid credit follows the money too ─
do $mig$
declare f text; fn text;
begin
  foreach fn in array array['public.issue_credit_package_invoice_item(uuid)',
                            'public.issue_premium_bundle_invoice_item(uuid)'] loop
    f := pg_get_functiondef(fn::regprocedure);
    if position('credit_line_paid_entitlement' in f) > 0 then
      raise notice '355: % already uses the entitlement; left alone.', fn; continue; end if;
    f := pg_temp.p355(f, $a$  v_paid  := coalesce(v_it.credit_paid_snapshot, 0);$a$,
                         $a$  v_paid  := public.credit_line_paid_entitlement(v_it.id);$a$, fn);
    execute f;
  end loop;
end $mig$;

-- ── 7. a credit line added in a correction keeps its catalogue price ────────
do $mig$
declare f text;
begin
  f := pg_get_functiondef('public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'::regprocedure);
  if position('v_old.store_id, pk.customer_price, v_product_id' in f) > 0 then
    raise notice '355: update_invoice_internal already records the catalogue price; left alone.'; return; end if;
  f := pg_temp.p355(f, $a$v_old.store_id, v_price, v_product_id, pk.paid_credit_amount, null, pk.name$a$,
                       $a$v_old.store_id, pk.customer_price, v_product_id, pk.paid_credit_amount, null, pk.name$a$,
                       'update_invoice_internal package original_price');
  f := pg_temp.p355(f, $a$v_old.store_id, v_price, v_product_id, b.paid_credit_amount, b.bonus_credit_amount,$a$,
                       $a$v_old.store_id, b.customer_payment_amount, v_product_id, b.paid_credit_amount, b.bonus_credit_amount,$a$,
                       'update_invoice_internal bundle original_price');
  execute f;
end $mig$;

-- ── 8. say no, instead of silently dropping, on a NEW credit line ───────────
-- Every create_invoice overload production has, plus the correction path. FOC
-- is read from v_item directly: the legacy 7-argument overload never declared
-- v_foc_qty. Both ways a line can ask for FOC are refused: foc_quantity, and
-- is_foc (which the invoice functions treat as the whole quantity FOC). Kept
-- lines in a correction `continue` before reaching this code.
do $mig$
declare fn regprocedure; pname text; f text; k text; guard text; refuse_new text;
begin
  for fn, pname in
    select p.oid::regprocedure, p.proname from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('create_invoice','update_invoice_internal')
     order by p.proname, p.pronargs
  loop
    f := pg_get_functiondef(fn);
    if position('cannot be made FOC when the invoice is created' in f) > 0 then
      raise notice '355: % already refuses these; left alone.', fn; continue; end if;
    foreach k in array array['credit package','premium bundle'] loop
      guard := format($g$if v_qty <> 1 then raise exception 'A %s line must have quantity 1'; end if;$g$, k);
      refuse_new := format($r$
      if coalesce(nullif(v_item->>'foc_quantity','')::integer, 0) > 0
         or coalesce(nullif(v_item->>'is_foc','')::boolean, false) then
        raise exception 'A %s cannot be made FOC when the invoice is created. Save the invoice and use Make FOC, or give a manual discount.'; end if;
      if nullif(v_item->>'line_voucher_id','') is not null then
        raise exception 'A line voucher cannot discount a %s. Use a manual discount or an invoice discount voucher.'; end if;$r$, k, k);
      if pname = 'update_invoice_internal' then
        -- A line already on the invoice keeps its FOC: it changes only through
        -- Make FOC / Undo FOC. A kept line reaches this code only when it no
        -- longer matches what was saved (matching and price-only lines
        -- `continue` earlier), and a non-matching credit line is rewritten at
        -- full price. So a line given free cannot be edited here at all (its
        -- FOC, its reason, a bundle's voucher choice...), and a line that was
        -- not free cannot become free here. Without this, a correction
        -- re-charged a package or bundle that was given away while the line
        -- still said FOC.
        f := pg_temp.p355(f, guard, guard || format($r$
      if nullif(v_item->>'invoice_item_id','') is not null
         and exists (select 1 from public.invoice_items ii355
                      where ii355.id = nullif(v_item->>'invoice_item_id','')::uuid and ii355.invoice_id = p_invoice_id) then
        if exists (select 1 from public.invoice_items ii355
                    where ii355.id = nullif(v_item->>'invoice_item_id','')::uuid
                      and (coalesce(ii355.foc_quantity, 0) > 0
                           or coalesce(nullif(v_item->>'foc_quantity','')::integer, 0) > 0
                           or coalesce(nullif(v_item->>'is_foc','')::boolean, false))) then
          raise exception 'This %s''s FOC can only be changed with Make FOC or Undo FOC on the saved invoice, and a %s given free cannot be edited in a correction. Undo FOC first, or keep the line exactly as it is.'; end if;
      else$r$, k, k) || refuse_new || E'
      end if;',
          format('%s — %s guard', fn, k));
      else
        f := pg_temp.p355(f, guard, guard || refuse_new, format('%s — %s guard', fn, k));
      end if;
    end loop;
    execute f;
  end loop;
end $mig$;

-- ── 9. a later discount cannot leave released credit above the line's worth ─
-- 356 replaces this with a version that also follows customer moves and can
-- cap to the money received (a third argument). A re-run of 355 after 356 must
-- not bring back this two-argument version beside it: the calls would become
-- ambiguous.
do $mig$
begin
  if to_regprocedure('public.trim_released_paid_credit(uuid,text,boolean)') is not null then
    raise notice '355: 356''s trim_released_paid_credit is installed; left alone.'; return; end if;
  execute $f$
create or replace function public.trim_released_paid_credit(p_invoice_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $body$
declare
  v_it record; v_lot record; v_excess numeric; v_take numeric; v_out jsonb := '[]'::jsonb;
begin
  for v_it in
    select x.id from public.invoice_items x
     where x.invoice_id = p_invoice_id
       and x.line_kind in ('credit_package','premium_bundle')
       and x.credit_issued_at is null
     order by x.id
  loop
    v_excess := round(public.credit_package_released_paid_credit(v_it.id)
                      - public.credit_line_paid_entitlement(v_it.id), 2);
    if v_excess <= 0 then continue; end if;
    for v_lot in
      select l.*, pl.lot_id as link_lot
        from public.credit_package_progress_lots pl
        join public.customer_credit_lots l on l.id = pl.lot_id
       where pl.invoice_item_id = v_it.id and l.status = 'active' and l.remaining_amount > 0
       order by l.created_at desc, l.id desc
       for update of l
    loop
      exit when v_excess <= 0;
      v_take := least(v_lot.remaining_amount, v_excess);
      insert into public.customer_credit_ledger(
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, reason, created_by, approved_by)
      values (v_lot.wallet_id, v_lot.customer_id, 'adjust_decrease', v_lot.category, v_take, v_lot.id,
        'invoice_discount_released_credit', p_invoice_id, v_lot.store_id, p_reason, auth.uid(), auth.uid());
      update public.customer_credit_lots set remaining_amount = remaining_amount - v_take, updated_at = now()
       where id = v_lot.id;
      update public.credit_package_progress_lots set released_amount = released_amount - v_take
       where lot_id = v_lot.link_lot;
      v_excess := round(v_excess - v_take, 2);
      v_out := v_out || jsonb_build_object('invoice_item_id', v_it.id, 'lot_id', v_lot.id, 'taken_back', v_take);
    end loop;
    if v_excess > 0 then
      raise exception 'CREDIT_ALREADY_SPENT: S$% of the paid credit this discount removes has already been spent. Refund the payment instead of discounting it.', v_excess;
    end if;
  end loop;
  if jsonb_array_length(v_out) > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'released_credit_trimmed_by_discount', null,
      jsonb_build_object('lots', v_out), 'credit', p_reason,
      (select store_id from public.invoices where id = p_invoice_id));
  end if;
  return jsonb_build_object('trimmed', v_out);
end $body$;
$f$;
  execute 'revoke all on function public.trim_released_paid_credit(uuid, text) from public, anon, authenticated';
  execute 'grant execute on function public.trim_released_paid_credit(uuid, text) to service_role';
end $mig$;

do $mig$
declare f text;
begin
  f := pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure);
  if position('trim_released_paid_credit' in f) > 0 then
    raise notice '355: correct_invoice already trims; left alone.'; return; end if;
  f := pg_temp.p355(f,
    $a$  perform set_config('invoice.manual_discount_reason','',true);
 end if;$a$,
    $a$  perform set_config('invoice.manual_discount_reason','',true);
  -- 355: a discount may not leave released paid credit above what the line is now worth.
  perform public.trim_released_paid_credit(i.id, coalesce(p_reason,'Invoice corrected'));
 end if;$a$, 'correct_invoice trim');
  execute f;
end $mig$;

-- ── 10. guards ──────────────────────────────────────────────────────────────
do $mig$
declare v_n int;
begin
  -- exactly one of each issuer, and neither reachable from a client
  select count(*) into v_n from pg_proc where proname = 'issue_credit_package' and pronamespace = 'public'::regnamespace;
  if v_n <> 1 then raise exception '355: % issue_credit_package overloads, expected 1', v_n; end if;
  select count(*) into v_n from pg_proc where proname = 'sell_premium_bundle' and pronamespace = 'public'::regnamespace;
  if v_n <> 1 then raise exception '355: % sell_premium_bundle overloads, expected 1', v_n; end if;

  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace
                and p.proname in ('issue_credit_package','sell_premium_bundle','credit_line_paid_entitlement',
                                  'invoice_item_external_value','trim_released_paid_credit')
                and (has_function_privilege('anon', p.oid, 'execute')
                  or has_function_privilege('authenticated', p.oid, 'execute'))) then
    raise exception '355: an internal credit function is reachable from the client'; end if;

  -- staff can still create and correct invoices
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
               and p.proname = 'create_invoice'
               and not has_function_privilege('authenticated', p.oid, 'execute')) then
    raise exception '355: staff lost access to a create_invoice overload'; end if;

  -- every create_invoice overload refuses these now, not just the one tested locally
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
               and p.proname in ('create_invoice','update_invoice_internal')
               and position('cannot be made FOC when the invoice is created' in p.prosrc) = 0) then
    raise exception '355: an invoice-writing function still silently drops FOC on a credit line'; end if;

  raise notice '355 applied: a discounted credit purchase grants what was paid, and a discounted bundle can be completed.';
end $mig$;

notify pgrst, 'reload schema';
