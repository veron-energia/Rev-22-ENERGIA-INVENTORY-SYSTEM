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

-- 350_a_package_inside_a_promotion_grants_it.sql
--
-- WHAT WAS WRONG
--
-- The promotion editor offered "Credit package" in its Included items dropdown.
-- You could pick one, save it, sell the promotion, take the customer's money —
-- and the customer received nothing. Not a partial grant, not a late grant:
-- nothing. The package sat in promotion_items as decoration.
--
-- Three independent checks agreed on that before this migration was written:
--
--   1. create_invoice never reads promotion_items when it builds the lines, so
--      no credit_package line is ever created from a promotion's contents;
--   2. issue_credit_lines_for_invoice — the only thing that grants credit —
--      gated on `line_kind in ('credit_package','premium_bundle')`, and a
--      promotion sells as line_kind 'promotion';
--   3. in production, all 220 promotion lines ever sold are line_kind
--      'promotion', none carries a credit_package_id, and none has ever issued
--      a unit of credit.
--
-- The only reason this never cost the business money is that nobody had built
-- such a promotion yet: promotion_items holds 106 product, 23 voucher, 7
-- therapy and 3 promotion rows, and zero credit_package rows. The trap was
-- loaded and had not yet been stepped on.
--
-- WHAT THIS DOES
--
-- Closes it by making the offer true rather than by withdrawing it, and adds
-- Premium bundle to the same dropdown, which is what was asked for.
--
-- The design deliberately creates NO derived invoice_items. The obvious
-- implementation — expand a promotion's packages into real credit_package /
-- premium_bundle child lines so the existing machinery fires unchanged — is
-- the one that must not be used here, because update_invoice_internal deletes
-- every invoice_item whose id is absent from the incoming payload:
--
--   delete from public.invoice_items ii where invoice_id = p_invoice_id
--     and not exists(select 1 from jsonb_array_elements(p_items) x
--                     where nullif(x->>'invoice_item_id','')::uuid = ii.id);
--
-- A derived child line is never in that payload. Every correction would delete
-- it and re-create it with a fresh id and credit_issued_at = null — issuing a
-- $15,000 bundle's credit a second time, on a correction that was only meant
-- to fix a typo. Setting promotion_id on such a child to dodge that is no
-- safer: twenty functions read invoice_items.promotion_id, including
-- capture_invoice_stock_components, ensure_invoice_stock_deducted and
-- earn_invoice_commission, so the child would double-count stock and
-- commission.
--
-- Instead the benefit is issued from the PROMOTION line itself, and
-- credit_issued_at is stamped on that line. That line is in p_items, survives
-- the correction delete, and keeps its flag — so idempotency across a
-- correction is a property of the design rather than a rule somebody has to
-- remember. update_invoice_internal and create_invoice are not touched at all.
--
-- This follows the convention the repository already uses for the same problem
-- one benefit over: invoice_therapy_entitlements_due expands a promotion's
-- fixed contents (and its choices) into the therapy entitlements they owe,
-- rather than inventing lines. Packages now do the same.
--
-- FOUR THINGS FALL OUT OF STAMPING A PROMOTION LINE, AND THREE ARE WANTED
--
--   correct_invoice already refuses to drop a line with credit_issued_at that
--     the new payload does not match — so a promotion that granted credit can
--     no longer be quietly swapped out in a correction. Wanted.
--   refund_invoice_recorded already refuses to cash such an invoice out as an
--     unallocated overpayment. Wanted.
--   invoice_benefit_review_options_internal filters to the two package kinds,
--     so promotion lines are invisible to it. No effect.
--   cancel_invoice_recorded REFUSES to cancel an invoice holding an issued
--     line with no invoice_benefit_values row. That one is a hard requirement,
--     not a bonus: without the capture_invoice_benefit_values change below,
--     these invoices would become impossible to cancel. It is handled.
--
-- Only promotions that actually contain a package are stamped, so every
-- promotion already sold behaves exactly as it did yesterday.
--
-- WHAT IS NOT IN SCOPE
--
-- Premium bundle is added to a promotion's Included items, not to its choice
-- groups. Adding it to choice groups would mean teaching create_invoice and
-- update_invoice_internal to record a sixth selection kind, and create_invoice
-- is the riskiest function in this system; that is a separate change with its
-- own tests. Credit package choices, which migration 349 already records in
-- invoice_promotion_selections, ARE issued by this migration — so the trap is
-- closed on the choice path too, without touching the till.

\set ON_ERROR_STOP on

-- Fail fast rather than queueing. The statements below take AccessExclusiveLock
-- on tables the till touches; without a timeout, one open transaction elsewhere
-- makes this migration wait while every settlement queues behind IT. Five
-- seconds turns that into a clean, retriable error. Re-running is safe: every
-- block below checks whether its own change is already in place.
set lock_timeout = '5s';

-- ── 1. the kind itself ───────────────────────────────────────────────────────
-- Committed on its own so the value is usable by everything below it.
alter type public.promotion_item_type add value if not exists 'premium_bundle';

alter table public.promotion_items
  add column if not exists premium_bundle_id uuid references public.premium_bundles(id);

-- ── 2. what a line owes ──────────────────────────────────────────────────────
-- The packages due from one invoice line, from a promotion's fixed contents
-- and from what the customer chose out of its choice groups. Quantities
-- multiply the way invoice_therapy_entitlements_due multiplies them: two of
-- the promotion means two of what it contains.
--
-- `weight` is the package's own list price, used only to split the cash the
-- customer actually handed over across several packages in one promotion. It
-- never decides how MUCH credit is granted — issue_credit_package reads that
-- from the package definition (pk.paid_credit_amount and its bonus), and
-- sell_premium_bundle from the bundle. The promotion's price is what was paid;
-- the package's definition is what is owed. That is the same rule already
-- chosen for a promotion's vouchers.
create or replace function public.promotion_package_benefits_due(p_invoice_item_id uuid)
returns table (kind text, credit_package_id uuid, premium_bundle_id uuid, units integer, weight numeric)
language sql
stable
security definer
set search_path = public
as $fn$
  -- (a) part of a promotion's FIXED contents.
  select case when pi.credit_package_id is not null then 'credit_package' else 'premium_bundle' end,
         pi.credit_package_id,
         pi.premium_bundle_id,
         greatest(coalesce(ii.quantity, 1), 1) * greatest(coalesce(pi.quantity, 1), 1),
         coalesce(cp.customer_price, pb.customer_payment_amount, 0)
           * greatest(coalesce(ii.quantity, 1), 1) * greatest(coalesce(pi.quantity, 1), 1)
    from public.invoice_items ii
    join public.promotion_items pi on pi.promotion_id = ii.promotion_id
    left join public.credit_packages cp on cp.id = pi.credit_package_id
    left join public.premium_bundles pb on pb.id = pi.premium_bundle_id
   where ii.id = p_invoice_item_id
     and ii.line_kind::text in ('promotion', 'premium_bundle')
     and (pi.credit_package_id is not null or pi.premium_bundle_id is not null)

  union all

  -- (b) CHOSEN from one of its choice groups. Only credit packages can be
  --     chosen today; see "what is not in scope" above.
  select 'credit_package',
         ips.credit_package_id,
         null::uuid,
         greatest(coalesce(ips.quantity, 1), 1),
         coalesce(cp.customer_price, 0) * greatest(coalesce(ips.quantity, 1), 1)
    from public.invoice_promotion_selections ips
    join public.credit_packages cp on cp.id = ips.credit_package_id
   where ips.invoice_item_id = p_invoice_item_id
     and ips.credit_package_id is not null
$fn$;

-- 339 made EXECUTE an allowlist rather than a default. A new function is
-- granted to PUBLIC on creation, which would trip 339's own guard, so the
-- grant is stated rather than inherited — and Supabase's default privileges
-- grant anon and authenticated EXPLICITLY, so revoking PUBLIC alone leaves the
-- function reachable from the browser. Both roles are named. This helper is only ever called from
-- inside SECURITY DEFINER functions, so it needs no caller-side grant; the
-- guard at the bottom asserts that those callers really are DEFINER.
revoke all on function public.promotion_package_benefits_due(uuid) from public, anon, authenticated;
grant execute on function public.promotion_package_benefits_due(uuid) to service_role;

-- ── 3. issue them ────────────────────────────────────────────────────────────
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'issue_credit_lines_for_invoice' and p.pronamespace = 'public'::regnamespace;
  if v_src is null then raise exception '350: issue_credit_lines_for_invoice not found'; end if;
  -- Re-runnable: the anchors below exist only in the pre-350 text.
  if position('promotion_package_benefits_due' in v_src) > 0 then
    raise notice '350: issue_credit_lines_for_invoice already carries the promotion packages; left alone.';
    return;
  end if;

  -- (a) room for the new locals.
  if position('v_s record; v_share_ext numeric; v_line numeric;' in v_src) = 0 then
    raise exception '350: the declare block of issue_credit_lines_for_invoice is not the one this migration was written against';
  end if;
  v_new := replace(v_src,
    'v_s record; v_share_ext numeric; v_line numeric;',
    'v_s record; v_share_ext numeric; v_line numeric;' || chr(10) ||
    '  v_pb record; v_pbtot numeric; v_left numeric; v_share numeric;');

  -- (b) let a promotion line in. Nothing else about the gate changes: a line
  --     whose credit has already been issued is still skipped, and the row is
  --     still locked for update.
  if position('       and line_kind in (''credit_package'',''premium_bundle'')' || chr(10) ||
              '       and credit_issued_at is null' in v_new) = 0 then
    raise exception '350: the gate of issue_credit_lines_for_invoice is not the one this migration was written against';
  end if;
  v_new := replace(v_new,
    '       and line_kind in (''credit_package'',''premium_bundle'')' || chr(10) ||
    '       and credit_issued_at is null',
    '       and credit_issued_at is null' || chr(10) ||
    '       and (line_kind in (''credit_package'',''premium_bundle'')' || chr(10) ||
    '            or exists (select 1 from public.promotion_package_benefits_due(invoice_items.id)))');

  -- (c) a promotion line must not fall into the premium_bundle branch, which
  --     is what the bare `else` would do to it.
  if position(chr(10) || '    else' || chr(10) || '      -- premium_bundle' in v_new) = 0 then
    raise exception '350: the premium_bundle branch of issue_credit_lines_for_invoice is not where this migration expects it';
  end if;
  v_new := replace(v_new,
    chr(10) || '    else' || chr(10) || '      -- premium_bundle',
    chr(10) || '    elsif v_it.line_kind = ''premium_bundle'' then' || chr(10) || '      -- premium_bundle');

  -- (d) issue whatever the promotion contains, before the direct handling.
  --     A premium_bundle line that itself contains packages gets both, which
  --     is why this is a separate block rather than another branch.
  if position('    if v_it.line_kind = ''credit_package'' then' in v_new) = 0 then
    raise exception '350: the credit_package branch of issue_credit_lines_for_invoice is not where this migration expects it';
  end if;
  v_new := replace(v_new,
    '    if v_it.line_kind = ''credit_package'' then',
    '    -- 350: packages this line owes because a promotion contains them, or' || chr(10) ||
    '    -- because the customer chose them from one of its choice groups. The' || chr(10) ||
    '    -- cash the customer actually paid is split across them by list price;' || chr(10) ||
    '    -- how much credit each one GRANTS comes from the package definition.' || chr(10) ||
    '    select coalesce(sum(weight), 0) into v_pbtot' || chr(10) ||
    '      from public.promotion_package_benefits_due(v_it.id);' || chr(10) ||
    '    v_left := v_external;' || chr(10) ||
    '    for v_pb in select * from public.promotion_package_benefits_due(v_it.id)' || chr(10) ||
    '                 order by kind, credit_package_id, premium_bundle_id loop' || chr(10) ||
    '      v_share := case when v_pbtot > 0' || chr(10) ||
    '                      then round(v_external * coalesce(v_pb.weight, 0) / v_pbtot, 2)' || chr(10) ||
    '                      else 0 end;' || chr(10) ||
    '      if v_share > v_left then v_share := v_left; end if;' || chr(10) ||
    '      v_left := v_left - v_share;' || chr(10) ||
    '      for v_n in 1 .. v_pb.units loop' || chr(10) ||
    '        -- Only the first unit carries the cash; the rest were given away' || chr(10) ||
    '        -- by the promotion and are recorded as paid nothing.' || chr(10) ||
    '        if v_pb.kind = ''credit_package'' then' || chr(10) ||
    '          v_res := public.issue_credit_package(v_pb.credit_package_id, v_inv.customer_id,' || chr(10) ||
    '                     v_inv.store_id, case when v_n = 1 then v_share else 0 end, p_invoice_id);' || chr(10) ||
    '          v_res := v_res || jsonb_build_object(''commission'',' || chr(10) ||
    '            public.earn_credit_package_commission((v_res->>''sale_id'')::uuid));' || chr(10) ||
    '        else' || chr(10) ||
    '          -- The promotion is a discount on the bundle: p_discount closes' || chr(10) ||
    '          -- the gap between list price and what was actually paid, which' || chr(10) ||
    '          -- is what sell_premium_bundle checks. An empty voucher choice is' || chr(10) ||
    '          -- valid — the bundle''s free vouchers become a claimable' || chr(10) ||
    '          -- entitlement, the same as any bundle sold without a choice.' || chr(10) ||
    '          v_res := public.sell_premium_bundle(' || chr(10) ||
    '            v_pb.premium_bundle_id, v_inv.customer_id, v_inv.store_id,' || chr(10) ||
    '            jsonb_build_array(jsonb_build_object(''method'', ''invoice'',' || chr(10) ||
    '              ''amount'', case when v_n = 1 then v_share else 0 end)),' || chr(10) ||
    '            ''[]''::jsonb,' || chr(10) ||
    '            greatest(round(coalesce((select b.customer_payment_amount from public.premium_bundles b' || chr(10) ||
    '                                      where b.id = v_pb.premium_bundle_id), 0)' || chr(10) ||
    '                           - case when v_n = 1 then v_share else 0 end, 2), 0),' || chr(10) ||
    '            0, p_invoice_id, false);' || chr(10) ||
    '        end if;' || chr(10) ||
    '        v_out := v_out || jsonb_build_object(''line_kind'', ''promotion_package'',' || chr(10) ||
    '          ''kind'', v_pb.kind, ''external'', case when v_n = 1 then v_share else 0 end,' || chr(10) ||
    '          ''result'', v_res);' || chr(10) ||
    '      end loop;' || chr(10) ||
    '    end loop;' || chr(10) ||
    '' || chr(10) ||
    '    if v_it.line_kind = ''credit_package'' then');

  execute v_new;
end $mig$;

-- ── 3b. and actually call it ─────────────────────────────────────────────────
-- The settlement trigger carries its OWN copy of the narrow condition, so
-- widening the issuer above is not enough: for an invoice whose only credit-
-- bearing line is a promotion, the issuer would never be reached at all. This
-- was caught by scripts/promotions/tests/promotion-package-benefits.sql, which
-- settles a real invoice rather than calling the issuer directly — testing it
-- directly would have passed against a system that still granted nothing.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'trg_create_therapy_on_paid' and p.pronamespace = 'public'::regnamespace;
  if v_src is null then raise exception '350: trg_create_therapy_on_paid not found'; end if;
  if position('promotion_package_benefits_due' in v_src) > 0 then
    raise notice '350: trg_create_therapy_on_paid already reaches promotion packages; left alone.';
    return;
  end if;

  if position('    if exists (select 1 from public.invoice_items' || chr(10) ||
              '                where invoice_id = new.id' || chr(10) ||
              '                  and line_kind in (''credit_package'',''premium_bundle'')) then' in v_src) = 0 then
    raise exception '350: the settlement trigger is not the one this migration was written against';
  end if;

  v_new := replace(v_src,
    '    if exists (select 1 from public.invoice_items' || chr(10) ||
    '                where invoice_id = new.id' || chr(10) ||
    '                  and line_kind in (''credit_package'',''premium_bundle'')) then',
    '    if exists (select 1 from public.invoice_items ii' || chr(10) ||
    '                where ii.invoice_id = new.id' || chr(10) ||
    '                  and (ii.line_kind in (''credit_package'',''premium_bundle'')' || chr(10) ||
    '                       or exists (select 1 from public.promotion_package_benefits_due(ii.id)))) then');

  execute v_new;
end $mig$;

-- ── 4. keep such an invoice cancellable ──────────────────────────────────────
-- capture_invoice_benefit_values finds the sales this transaction created by
-- matching them against the LINE's own credit_package_id / premium_bundle_id.
-- A promotion line has neither, so without this it would record nothing — and
-- cancel_invoice_recorded refuses to cancel an invoice holding an issued line
-- with no invoice_benefit_values row. The invoice would be uncancellable
-- forever. The match is widened to the packages the line owes; the direct case
-- is left exactly as it was.
do $mig$
declare v_src text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'capture_invoice_benefit_values' and p.pronamespace = 'public'::regnamespace;
  if v_src is null then raise exception '350: capture_invoice_benefit_values not found'; end if;
  if position('promotion_package_benefits_due' in v_src) > 0 then
    raise notice '350: capture_invoice_benefit_values already promotion-aware; left alone.';
    return;
  end if;

  if position('where c.invoice_id=it.invoice_id and c.package_id=it.credit_package_id and c.sold_at>=transaction_timestamp()' in v_src) = 0
     or position('where b.invoice_id=it.invoice_id and b.bundle_id=it.premium_bundle_id and b.sold_at>=transaction_timestamp()' in v_src) = 0 then
    raise exception '350: capture_invoice_benefit_values is not the one this migration was written against';
  end if;

  v_new := replace(v_src,
    'where c.invoice_id=it.invoice_id and c.package_id=it.credit_package_id and c.sold_at>=transaction_timestamp()',
    'where c.invoice_id=it.invoice_id and c.sold_at>=transaction_timestamp()' || chr(10) ||
    '     and (c.package_id=it.credit_package_id or exists(' || chr(10) ||
    '          select 1 from public.promotion_package_benefits_due(it.id) d' || chr(10) ||
    '           where d.credit_package_id = c.package_id))');

  v_new := replace(v_new,
    'where b.invoice_id=it.invoice_id and b.bundle_id=it.premium_bundle_id and b.sold_at>=transaction_timestamp()',
    'where b.invoice_id=it.invoice_id and b.sold_at>=transaction_timestamp()' || chr(10) ||
    '     and (b.bundle_id=it.premium_bundle_id or exists(' || chr(10) ||
    '          select 1 from public.promotion_package_benefits_due(it.id) d' || chr(10) ||
    '           where d.premium_bundle_id = b.bundle_id))');

  execute v_new;
end $mig$;

-- ── 5. let the editor author one ─────────────────────────────────────────────
-- add_promotion_item grows a parameter. PostgREST resolves an overload by the
-- SET OF PARAMETER NAMES in the request, so leaving the old signature in place
-- would make every call ambiguous and return PGRST203 — which is exactly how
-- 339 took transfer requests down for six attempts before 348 cleaned it up.
-- The old signature is dropped in the same transaction that creates the new
-- one, so there is no window in which both are resolvable.
begin;

create or replace function public.add_promotion_item(
  p_promotion_id uuid,
  p_item_type public.promotion_item_type,
  p_product_id uuid,
  p_voucher_id uuid,
  p_child_promotion_id uuid,
  p_treatment_name text,
  p_quantity integer,
  p_notes text,
  p_therapy_package_id uuid,
  p_credit_package_id uuid,
  p_premium_bundle_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare v_id uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit a promotion'; end if;
  if coalesce(p_quantity,0) <= 0 then raise exception 'Quantity must be greater than zero'; end if;

  if p_item_type = 'product' and p_product_id is null then
    raise exception 'Select a product'; end if;
  if p_item_type = 'voucher' and p_voucher_id is null then
    raise exception 'Select a voucher'; end if;
  if p_item_type = 'promotion' then
    if p_child_promotion_id is null then raise exception 'Select a promotion'; end if;
    perform public.validate_promotion_child(p_promotion_id, p_child_promotion_id);
  end if;
  if p_item_type = 'treatment' and coalesce(trim(p_treatment_name),'') = '' then
    raise exception 'Enter a treatment name'; end if;
  if p_item_type = 'therapy' and p_therapy_package_id is null then
    raise exception 'Select a therapy package'; end if;
  if p_item_type = 'credit_package' and p_credit_package_id is null then
    raise exception 'Select a credit package'; end if;
  -- Compared as text on purpose. A plpgsql body is validated when the function
  -- is created, and a freshly added enum label cannot be resolved inside the
  -- same transaction that added it. Casting to text keeps this creatable no
  -- matter how the migration is applied — psql statement by statement, or
  -- through an API that wraps each call in its own transaction.
  if p_item_type::text = 'premium_bundle' and p_premium_bundle_id is null then
    raise exception 'Select a premium bundle'; end if;

  insert into public.promotion_items (
    promotion_id, item_type, product_id, voucher_id, child_promotion_id,
    treatment_name, quantity, notes, therapy_package_id, credit_package_id,
    premium_bundle_id)
  values (p_promotion_id, p_item_type, p_product_id, p_voucher_id, p_child_promotion_id,
    nullif(trim(coalesce(p_treatment_name,'')),''), p_quantity, p_notes,
    p_therapy_package_id, p_credit_package_id, p_premium_bundle_id)
  returning id into v_id;

  perform public.write_audit_ex('promotion_items', v_id, 'promotion_item_added', null,
    jsonb_build_object('promotion', p_promotion_id, 'type', p_item_type, 'quantity', p_quantity),
    'catalogue', null, null);
  return v_id;
end
$fn$;

drop function if exists public.add_promotion_item(
  uuid, public.promotion_item_type, uuid, uuid, uuid, text, integer, text, uuid, uuid);

revoke all on function public.add_promotion_item(
  uuid, public.promotion_item_type, uuid, uuid, uuid, text, integer, text, uuid, uuid, uuid) from public, anon;
grant execute on function public.add_promotion_item(
  uuid, public.promotion_item_type, uuid, uuid, uuid, text, integer, text, uuid, uuid, uuid)
  to authenticated, service_role;

commit;

-- ── 6. guards ────────────────────────────────────────────────────────────────
do $mig$
declare v_n integer;
begin
  -- the kind exists
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  where t.typname = 'promotion_item_type' and e.enumlabel = 'premium_bundle') then
    raise exception '350: promotion_item_type still has no premium_bundle';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'promotion_items'
                    and column_name = 'premium_bundle_id') then
    raise exception '350: promotion_items.premium_bundle_id was not added';
  end if;

  -- exactly one add_promotion_item, or the till gets a 300 back
  select count(*) into v_n from pg_proc
   where proname = 'add_promotion_item' and pronamespace = 'public'::regnamespace;
  if v_n <> 1 then
    raise exception '350: % overloads of add_promotion_item; PostgREST needs exactly one', v_n;
  end if;

  -- the issuer really does look at promotion lines now
  if (select p.prosrc from pg_proc p where p.proname = 'issue_credit_lines_for_invoice'
       and p.pronamespace = 'public'::regnamespace) not like '%promotion_package_benefits_due%' then
    raise exception '350: issue_credit_lines_for_invoice still ignores promotion packages';
  end if;
  if (select p.prosrc from pg_proc p where p.proname = 'capture_invoice_benefit_values'
       and p.pronamespace = 'public'::regnamespace) not like '%promotion_package_benefits_due%' then
    raise exception '350: capture_invoice_benefit_values would leave such an invoice uncancellable';
  end if;

  -- the trigger must actually reach the issuer for a promotion-only invoice
  if (select p.prosrc from pg_proc p where p.proname = 'trg_create_therapy_on_paid'
       and p.pronamespace = 'public'::regnamespace) not like '%promotion_package_benefits_due%' then
    raise exception '350: the settlement trigger still never calls the issuer for a promotion';
  end if;

  -- a promotion line must not be treated as a bundle
  if (select p.prosrc from pg_proc p where p.proname = 'issue_credit_lines_for_invoice'
       and p.pronamespace = 'public'::regnamespace) not like '%elsif v_it.line_kind = ''premium_bundle'' then%' then
    raise exception '350: the premium_bundle branch still catches every non-credit_package line';
  end if;

  -- The helper is granted to service_role only, so it is safe without a
  -- caller-side grant ONLY while every caller is SECURITY DEFINER and runs as
  -- the owner. The settlement trigger is a caller too: if it ever becomes
  -- invoker-rights, every staff settlement would fail with a permission error
  -- that no psql test would catch, because psql runs as the superuser.
  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace
                and p.proname in ('issue_credit_lines_for_invoice','capture_invoice_benefit_values',
                                  'trg_create_therapy_on_paid')
                and not p.prosecdef) then
    raise exception '350: a caller of promotion_package_benefits_due is not SECURITY DEFINER; it now needs its own grant';
  end if;

  -- 339 still holds: the new helper is not an endpoint
  if has_function_privilege('anon', 'public.promotion_package_benefits_due(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.promotion_package_benefits_due(uuid)', 'execute') then
    raise exception '350: promotion_package_benefits_due is reachable from the client';
  end if;

  raise notice '350 applied: a credit package or premium bundle inside a promotion now grants what it promises.';
end $mig$;

notify pgrst, 'reload schema';
