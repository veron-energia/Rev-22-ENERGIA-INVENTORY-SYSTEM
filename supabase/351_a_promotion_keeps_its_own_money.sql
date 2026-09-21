-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  NOT APPLIED TO PRODUCTION. DO NOT APPLY THIS FILE ON ITS OWN.            ║
-- ║                                                                           ║
-- ║  350 and 351 together make a package inside a promotion actually grant    ║
-- ║  its benefit. Two adversarial review rounds found money-losing defects    ║
-- ║  in them, and two remain open (see the list at the end of 352). The trap  ║
-- ║  they exist to fix is instead held shut by:                               ║
-- ║      supabase/352_a_promotion_may_not_promise_what_it_never_grants.sql    ║
-- ║  which IS applied to production.                                         ║
-- ║                                                                           ║
-- ║  When this work resumes, 352 must be reverted in the same change.        ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- 351_a_promotion_keeps_its_own_money.sql
--
-- 350 made a credit package or premium bundle inside a promotion actually grant
-- its benefit. It was never applied to production, because an adversarial
-- pre-flight found five ways it loses money or stops the till. Every one was
-- re-verified by hand against the installed function bodies before this was
-- written. 350 must not be applied without this file.
--
-- The common cause of four of the five: 350 taught ONE function that a
-- promotion line can carry a benefit, and left every other function in the
-- money path still believing that only line_kind 'credit_package' and
-- 'premium_bundle' ever do. Each of those beliefs is a hole.
--
--   1. allocate_invoice_wallet_credit skips a line only when
--        v_it.purpose in ('credit_package','premium_bundle')
--      A promotion's purpose is 'promotion', so wallet credit could pay for a
--      promotion that grants a credit package: restricted credit in, fresh
--      credit out. The customer mints money. sell_premium_bundle refuses wallet
--      credit for exactly this reason, and 350 walked around its own guard by
--      passing method 'invoice' regardless of how the line was funded.
--
--   2. refund_invoice_recorded reverses granted benefits only when
--        it.line_kind in ('credit_package','premium_bundle') or ...vouchers
--      So refunding such a promotion returned the cash AND left the credit in
--      the customer's wallet. The reversal machinery underneath is generic —
--      it works off invoice_benefit_values — only the branch test was narrow.
--
--   3. earn_invoice_commission excludes the two package kinds but NOT
--      'promotion', so the promotion line earned commission and 350's derived
--      package sale earned commission again on the same cash. Worse, it came
--      back on every correction: reconcile_invoice_commissions re-earns from
--      every credit_package_sales and premium_bundle_sales row on the invoice,
--      unconditionally.
--
--   4. promotion_original_total has no premium_bundle arm, so a bundle inside a
--      promotion is valued at zero — which is what a whole-bundle exchange pays
--      out on, and what the savings figure is computed from.
--
--   5. sell_premium_bundle raises when the bundle is not available at the store,
--      and there is NO exception handler anywhere between the settlement
--      trigger and that raise. A store-scoped or retired bundle inside a
--      promotion therefore aborts the whole settlement: the customer's payment
--      fails at the till and the invoice is stranded.
--
-- ── the decision that shapes fix 3 ───────────────────────────────────────────
--
-- Asked whose commission a package inside a promotion should earn, the business
-- chose THE PROMOTION'S OWN RATE. That is what the staff member sold and what
-- the invoice shows.
--
-- Neither sales table carries a link back to the invoice line, so there is no
-- flag to set. But both earners return early on external_paid <= 0, and so does
-- the reconcile path, because it calls the same earners. So the derived sale
-- records NO external payment — which is not a trick, it is the truth: the
-- customer paid the promotion, the promotion line took the money, and the
-- package was granted out of it. Recording cash twice was the bug.
--
-- That also deletes 350's apportionment entirely: splitting the promotion's
-- price across its packages by list price only ever existed to feed
-- external_paid, and with it gone the rounding, zero-weight, null-price and
-- same-package-twice edge cases go with it. How much each package GRANTS is
-- untouched — that always came from the package definition.

\set ON_ERROR_STOP on

-- Fail fast rather than queueing. The statements below take AccessExclusiveLock
-- on tables the till touches; without a timeout, one open transaction elsewhere
-- makes this migration wait while every settlement queues behind IT. Five
-- seconds turns that into a clean, retriable error. Re-running is safe: every
-- block below checks whether its own change is already in place.
set lock_timeout = '5s';

-- ── 0. refuse to run against a database that has not had 350 ─────────────────
do $mig$
begin
  if not exists (select 1 from pg_proc where proname = 'promotion_package_benefits_due'
                   and pronamespace = 'public'::regnamespace) then
    raise exception '351: apply 350 first; this file only fixes what 350 introduces';
  end if;
end $mig$;

-- ── 1. credit may never buy credit, including through a promotion ────────────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'allocate_invoice_wallet_credit' and p.pronamespace = 'public'::regnamespace;
  if v_src is null then raise exception '351: allocate_invoice_wallet_credit not found'; end if;
  if position('promotion_package_benefits_due' in v_src) > 0 then
    raise notice '351: wallet allocation already guarded; left alone.'; return; end if;
  if position('if v_it.purpose in (''credit_package'',''premium_bundle'') then continue; end if;' in v_src) = 0 then
    raise exception '351: allocate_invoice_wallet_credit is not the one this migration was written against';
  end if;

  v_new := replace(v_src,
    'if v_it.purpose in (''credit_package'',''premium_bundle'') then continue; end if;',
    'if v_it.purpose in (''credit_package'',''premium_bundle'') then continue; end if;' || chr(10) ||
    '    -- 351: nor through a promotion that contains one. Without this, paying' || chr(10) ||
    '    -- such a promotion from the wallet spends restricted credit and grants' || chr(10) ||
    '    -- fresh credit back — the customer mints money.' || chr(10) ||
    '    if exists (select 1 from public.promotion_package_benefits_due(v_it.id)) then continue; end if;');

  execute v_new;
end $mig$;

-- ── 2. refunding a promotion line reverses what it granted ───────────────────
-- Only the branch test is widened. Everything inside it already works off
-- invoice_benefit_values and is indifferent to the line's kind; the nested
-- assert_invoice_credit_source_evidence call stays scoped to the two direct
-- kinds, which is where that evidence exists.
--
-- The subquery is aliased ibv, NOT b. refund_invoice_recorded already declares
--   b public.invoice_benefit_values%rowtype
-- and this database runs plpgsql.variable_conflict = error, so an alias of b
-- makes b.invoice_item_id ambiguous and EVERY refund in the system raises —
-- product returns, rentals, therapy, vouchers, not only promotions. plpgsql
-- parses lazily, so nothing fails at apply time: the first cashier refund
-- afterwards is the detector. An earlier draft of this migration did exactly
-- that, and its test did not catch it because the test asserted on the
-- function's TEXT instead of performing a refund.
do $mig$
declare v_src text; v_new text;
  c_good constant text := 'from public.invoice_benefit_values ibv where ibv.invoice_item_id = it.id';
  c_bad  constant text := 'from public.invoice_benefit_values b where b.invoice_item_id = it.id';
  c_anchor constant text := 'if it.line_kind in (''credit_package'',''premium_bundle'') or public.invoice_line_has_issued_vouchers(it.id) then';
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'refund_invoice_recorded' and p.pronamespace = 'public'::regnamespace;
  if v_src is null then raise exception '351: refund_invoice_recorded not found'; end if;

  -- Already correct.
  if position(c_good in v_src) > 0 then
    raise notice '351: refund already reverses promotion-granted benefits; left alone.'; return; end if;

  -- Repair a body carrying the broken alias. The sentinel must key on the
  -- CORRECTED text, not on a '351' marker: the broken injection contains one
  -- too, so keying on that would make this file refuse to heal its own damage.
  if position(c_bad in v_src) > 0 then
    execute replace(v_src, c_bad, c_good);
    raise notice '351: repaired the ambiguous alias that was breaking every refund.';
    return;
  end if;

  if position(c_anchor in v_src) = 0 then
    raise exception '351: refund_invoice_recorded is not the one this migration was written against';
  end if;

  v_new := replace(v_src, c_anchor,
    'if it.line_kind in (''credit_package'',''premium_bundle'') or public.invoice_line_has_issued_vouchers(it.id)' || chr(10) ||
    '        -- 351: a promotion line can grant credit too, and it must be' || chr(10) ||
    '        -- reversed like any other. Without this the shop refunded the cash' || chr(10) ||
    '        -- and the customer kept the credit. Aliased ibv: this function' || chr(10) ||
    '        -- declares a variable called b.' || chr(10) ||
    '        or exists (select 1 ' || c_good || ') then');

  execute v_new;
end $mig$;

-- ── 3. the same money is commissioned once ───────────────────────────────────
do $mig$
declare v_src text; v_new text; v_old text; v_start int; v_end int;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'issue_credit_lines_for_invoice' and p.pronamespace = 'public'::regnamespace;
  if v_src is null then raise exception '351: issue_credit_lines_for_invoice not found'; end if;
  if position('promotion_package_benefits_due' in v_src) = 0 then
    raise exception '351: 350 has not been applied to this database';
  end if;
  if position('351:' in v_src) > 0 then
    raise notice '351: the issuer already records no cash on a derived sale; left alone.'; return; end if;

  -- Cut out 350's whole block, from its opening comment to the line that
  -- follows it, and put the simpler one in its place.
  v_start := position('    -- 350: packages this line owes because a promotion contains them, or' in v_src);
  v_end   := position('    if v_it.line_kind = ''credit_package'' then' in v_src);
  if v_start = 0 or v_end = 0 or v_end <= v_start then
    raise exception '351: cannot locate 350''s promotion-package block in issue_credit_lines_for_invoice';
  end if;
  v_old := substr(v_src, v_start, v_end - v_start);

  v_new := replace(v_src, v_old,
    '    -- 350/351: the packages this line owes, because a promotion contains' || chr(10) ||
    '    -- them or because the customer chose them from one of its choice' || chr(10) ||
    '    -- groups.' || chr(10) ||
    '    --' || chr(10) ||
    '    -- The derived sale records NO external payment, deliberately. The' || chr(10) ||
    '    -- customer paid the PROMOTION: that line took the money, and' || chr(10) ||
    '    -- earn_invoice_commission already pays commission on it at the' || chr(10) ||
    '    -- promotion''s own rate, which is the rule the business chose.' || chr(10) ||
    '    -- Recording cash here as well commissioned the same money twice, and' || chr(10) ||
    '    -- reconcile_invoice_commissions re-earns from every sales row on every' || chr(10) ||
    '    -- correction, so the duplicate came back each time an invoice was' || chr(10) ||
    '    -- edited. Both earners return early on external_paid <= 0, so zero is' || chr(10) ||
    '    -- the one value that closes it through every path.' || chr(10) ||
    '    --' || chr(10) ||
    '    -- What each package GRANTS is unaffected: that comes from the package' || chr(10) ||
    '    -- definition, never from what was paid.' || chr(10) ||
    '    for v_pb in select * from public.promotion_package_benefits_due(v_it.id)' || chr(10) ||
    '                 order by kind, credit_package_id, premium_bundle_id loop' || chr(10) ||
    '      for v_n in 1 .. v_pb.units loop' || chr(10) ||
    '        if v_pb.kind = ''credit_package'' then' || chr(10) ||
    '          v_res := public.issue_credit_package(v_pb.credit_package_id, v_inv.customer_id,' || chr(10) ||
    '                     v_inv.store_id, 0, p_invoice_id);' || chr(10) ||
    '        else' || chr(10) ||
    '          -- p_discount is the bundle''s whole list price: the promotion' || chr(10) ||
    '          -- covered it, so sell_premium_bundle sees nothing due and' || chr(10) ||
    '          -- nothing paid rather than refusing the sale. An empty voucher' || chr(10) ||
    '          -- choice is valid — the free vouchers become a claimable' || chr(10) ||
    '          -- entitlement, as for any bundle sold without a choice.' || chr(10) ||
    '          v_res := public.sell_premium_bundle(' || chr(10) ||
    '            v_pb.premium_bundle_id, v_inv.customer_id, v_inv.store_id,' || chr(10) ||
    '            ''[]''::jsonb, ''[]''::jsonb,' || chr(10) ||
    '            greatest(round(coalesce((select b.customer_payment_amount' || chr(10) ||
    '                                       from public.premium_bundles b' || chr(10) ||
    '                                      where b.id = v_pb.premium_bundle_id), 0), 2), 0),' || chr(10) ||
    '            0, p_invoice_id, false);' || chr(10) ||
    '        end if;' || chr(10) ||
    '        v_out := v_out || jsonb_build_object(''line_kind'', ''promotion_package'',' || chr(10) ||
    '          ''kind'', v_pb.kind, ''external'', 0, ''result'', v_res);' || chr(10) ||
    '      end loop;' || chr(10) ||
    '    end loop;' || chr(10) ||
    '' || chr(10));

  execute v_new;
end $mig$;

-- ── 4. a bundle inside a promotion is worth what it costs ────────────────────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'promotion_original_total' and p.pronamespace = 'public'::regnamespace;
  if v_src is null then raise exception '351: promotion_original_total not found'; end if;
  if position('premium_bundle' in v_src) > 0 then
    raise notice '351: promotion_original_total already values a bundle; left alone.'; return; end if;
  if position('    end if;  -- treatment contributes 0' in v_src) = 0 then
    raise exception '351: promotion_original_total is not the one this migration was written against';
  end if;

  v_new := replace(v_src,
    '    end if;  -- treatment contributes 0',
    '    elsif v_item.item_type::text = ''premium_bundle'' then' || chr(10) ||
    '      -- 351: without this a bundle inside a promotion is valued at zero,' || chr(10) ||
    '      -- and a whole-bundle exchange pays out on that figure.' || chr(10) ||
    '      select customer_payment_amount into v_price from public.premium_bundles' || chr(10) ||
    '        where id = v_item.premium_bundle_id and deleted_at is null;' || chr(10) ||
    '      v_total := v_total + coalesce(v_price,0) * v_item.quantity;' || chr(10) ||
    '    end if;  -- treatment contributes 0');

  execute v_new;
end $mig$;

-- ── 5. a package in a promotion must still be sellable when it is settled ────
-- The availability check lives inside sell_premium_bundle and raises. There is
-- no exception handler between the settlement trigger and it, so an
-- unavailable bundle does not degrade — it aborts the customer's payment.
-- Rather than catch that at the till, make it impossible to author: a package
-- may only go into a promotion if it is sellable everywhere and indefinitely,
-- and may not afterwards be retired or restricted while it is still in one.
create or replace function public.assert_package_may_sit_in_a_promotion(
  p_credit_package_id uuid, p_premium_bundle_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare b public.premium_bundles%rowtype; c public.credit_packages%rowtype;
begin
  if p_premium_bundle_id is not null then
    select * into b from public.premium_bundles where id = p_premium_bundle_id and deleted_at is null;
    if not found then raise exception 'That premium bundle no longer exists'; end if;
    if not b.is_active then
      raise exception 'Activate "%" before putting it inside a promotion; an inactive bundle cannot be issued when the promotion is paid', b.name; end if;
    if b.effective_to is not null then
      raise exception '"%" stops being available on %. A promotion cannot contain a bundle that expires, because the sale would fail at the till afterwards', b.name, b.effective_to; end if;
    if exists (select 1 from public.premium_bundle_stores s where s.bundle_id = p_premium_bundle_id) then
      raise exception '"%" is limited to certain stores. A promotion can be sold at any store, so the bundle inside it must be available at all of them', b.name; end if;
  end if;

  if p_credit_package_id is not null then
    select * into c from public.credit_packages where id = p_credit_package_id and deleted_at is null;
    if not found then raise exception 'That credit package no longer exists'; end if;
    if not c.is_active then
      raise exception 'Activate "%" before putting it inside a promotion; an inactive package cannot be issued when the promotion is paid', c.name; end if;
  end if;
end
$fn$;

revoke all on function public.assert_package_may_sit_in_a_promotion(uuid, uuid) from public, anon, authenticated;
grant execute on function public.assert_package_may_sit_in_a_promotion(uuid, uuid) to service_role;

-- 5a. enforce it when the item is authored.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'add_promotion_item' and p.pronamespace = 'public'::regnamespace;
  if v_src is null then raise exception '351: add_promotion_item not found'; end if;
  if position('assert_package_may_sit_in_a_promotion' in v_src) > 0 then
    raise notice '351: add_promotion_item already validates availability; left alone.'; return; end if;
  -- Accept either spelling of 350's premium-bundle branch. An early copy of 350
  -- compared the enum directly; the released one casts to text so the label can
  -- be resolved in the same transaction that added it. The line this migration
  -- actually anchors on is identical in both.
  if position('raise exception ''Select a premium bundle''; end if;' in v_src) = 0 then
    raise exception '351: add_promotion_item does not have 350''s premium-bundle branch';
  end if;

  v_new := replace(v_src,
    '    raise exception ''Select a premium bundle''; end if;',
    '    raise exception ''Select a premium bundle''; end if;' || chr(10) ||
    '  -- 351: a package that cannot be issued at settlement time must not be' || chr(10) ||
    '  -- allowed into a promotion at all; the failure would otherwise land on' || chr(10) ||
    '  -- a customer at the till.' || chr(10) ||
    '  if p_item_type::text in (''premium_bundle'',''credit_package'') then' || chr(10) ||
    '    perform public.assert_package_may_sit_in_a_promotion(p_credit_package_id, p_premium_bundle_id);' || chr(10) ||
    '  end if;');

  execute v_new;
end $mig$;

-- 5b. and keep it true afterwards — but only while a promotion actually needs it.
--
-- A package is "locked" only if some promotion containing it is still sellable,
-- or has already been sold on an invoice that has not been settled yet and so
-- may still have to issue it. A promotion that is deleted, deactivated or long
-- past its end date locks nothing: refusing to let an Owner retire a bundle
-- because of a promotion nobody can buy any more would be a worse bug than the
-- one this guard exists to prevent.
create or replace function public.package_locked_by_promotion(
  p_credit_package_id uuid, p_premium_bundle_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $fn$
  select p.name
    from public.promotion_items pi
    join public.promotions p on p.id = pi.promotion_id
   where ((p_premium_bundle_id is not null and pi.premium_bundle_id = p_premium_bundle_id)
       or (p_credit_package_id is not null and pi.credit_package_id = p_credit_package_id))
     and (
       (p.deleted_at is null and p.is_active
        and (p.end_date is null or p.end_date >= current_date))
       or exists (select 1
                    from public.invoice_items ii
                    join public.invoices i on i.id = ii.invoice_id
                   where ii.promotion_id = p.id
                     and i.deleted_at is null
                     and i.status in ('draft','unpaid','partially_paid'))
     )
   limit 1
$fn$;

revoke all on function public.package_locked_by_promotion(uuid, uuid) from public, anon, authenticated;
grant execute on function public.package_locked_by_promotion(uuid, uuid) to service_role;

create or replace function public.trg_package_stays_sellable_for_promotions()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare v_promo text;
begin
  if tg_table_name = 'premium_bundle_stores' then
    v_promo := public.package_locked_by_promotion(null, new.bundle_id);
    if v_promo is not null then
      raise exception 'This bundle is inside promotion "%". Remove it from that promotion before limiting the bundle to certain stores, or the promotion will fail at the till.', v_promo;
    end if;
    return new;
  end if;

  if tg_table_name = 'premium_bundles' then
    -- Only a change that makes it unsellable is interesting; ordinary edits pass.
    if new.is_active and new.deleted_at is null and new.effective_to is null then return new; end if;
    v_promo := public.package_locked_by_promotion(null, new.id);
    if v_promo is not null then
      raise exception 'This bundle is inside promotion "%". Remove it from that promotion before retiring, expiring or deleting the bundle.', v_promo;
    end if;
    return new;
  end if;

  -- credit_packages
  if new.is_active and new.deleted_at is null then return new; end if;
  v_promo := public.package_locked_by_promotion(new.id, null);
  if v_promo is not null then
    raise exception 'This credit package is inside promotion "%". Remove it from that promotion before retiring or deleting the package.', v_promo;
  end if;
  return new;
end
$fn$;

-- A trigger fires regardless of who may EXECUTE its function, so this needs no
-- caller-side grant. Supabase's default privileges hand new functions to anon
-- and authenticated, which 339 forbids and its own test catches.
revoke all on function public.trg_package_stays_sellable_for_promotions() from public, anon, authenticated;
grant execute on function public.trg_package_stays_sellable_for_promotions() to service_role;

drop trigger if exists package_stays_sellable_for_promotions on public.premium_bundles;
create trigger package_stays_sellable_for_promotions
  before update on public.premium_bundles
  for each row execute function public.trg_package_stays_sellable_for_promotions();

drop trigger if exists package_stays_sellable_for_promotions on public.credit_packages;
create trigger package_stays_sellable_for_promotions
  before update on public.credit_packages
  for each row execute function public.trg_package_stays_sellable_for_promotions();

drop trigger if exists bundle_store_scope_respects_promotions on public.premium_bundle_stores;
create trigger bundle_store_scope_respects_promotions
  before insert on public.premium_bundle_stores
  for each row execute function public.trg_package_stays_sellable_for_promotions();

-- ── 6. guards ────────────────────────────────────────────────────────────────
do $mig$
declare v_src text;
begin
  select prosrc into v_src from pg_proc where proname='allocate_invoice_wallet_credit' and pronamespace='public'::regnamespace;
  if v_src not like '%promotion_package_benefits_due%' then
    raise exception '351: wallet credit can still buy credit through a promotion'; end if;

  select prosrc into v_src from pg_proc where proname='refund_invoice_recorded' and pronamespace='public'::regnamespace;
  if v_src not like '%invoice_benefit_values ibv where ibv.invoice_item_id = it.id%' then
    raise exception '351: a refund still leaves promotion-granted credit with the customer'; end if;

  select prosrc into v_src from pg_proc where proname='issue_credit_lines_for_invoice' and pronamespace='public'::regnamespace;
  if v_src like '%earn_credit_package_commission((v_res->>''sale_id'')::uuid));%'
     and v_src like '%promotion_package_benefits_due(v_it.id)%'
     and position('351' in v_src) = 0 then
    raise exception '351: the derived sale still earns its own commission'; end if;
  if v_src like '%v_share%' and position('351' in v_src) = 0 then
    raise exception '351: the apportionment was not removed'; end if;

  select prosrc into v_src from pg_proc where proname='promotion_original_total' and pronamespace='public'::regnamespace;
  if v_src not like '%premium_bundle%' then
    raise exception '351: a bundle inside a promotion is still valued at zero'; end if;

  select prosrc into v_src from pg_proc where proname='add_promotion_item' and pronamespace='public'::regnamespace;
  if v_src not like '%assert_package_may_sit_in_a_promotion%' then
    raise exception '351: an unsellable package can still be authored into a promotion'; end if;

  if not exists (select 1 from pg_trigger where tgname='package_stays_sellable_for_promotions'
                   and tgrelid='public.premium_bundles'::regclass) then
    raise exception '351: a bundle inside a promotion can still be retired'; end if;

  if has_function_privilege('anon','public.package_locked_by_promotion(uuid,uuid)','execute')
     or has_function_privilege('authenticated','public.package_locked_by_promotion(uuid,uuid)','execute') then
    raise exception '351: package_locked_by_promotion is reachable from the client'; end if;

  if has_function_privilege('anon','public.trg_package_stays_sellable_for_promotions()','execute')
     or has_function_privilege('authenticated','public.trg_package_stays_sellable_for_promotions()','execute') then
    raise exception '351: the guard trigger function is reachable from the client'; end if;

  if has_function_privilege('anon','public.assert_package_may_sit_in_a_promotion(uuid,uuid)','execute')
     or has_function_privilege('authenticated','public.assert_package_may_sit_in_a_promotion(uuid,uuid)','execute') then
    raise exception '351: assert_package_may_sit_in_a_promotion is reachable from the client'; end if;

  raise notice '351 applied: the promotion keeps its own money, and its packages stay sellable.';
end $mig$;

notify pgrst, 'reload schema';
