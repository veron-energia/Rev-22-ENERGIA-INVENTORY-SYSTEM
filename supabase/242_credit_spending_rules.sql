-- =====================================================================
-- ENERGIA — WHAT EACH KIND OF CREDIT MAY PAY FOR
--
-- The rule, which is not configurable:
--
--   source           balance  may pay for
--   ---------------- -------- ------------------------------------------------
--   credit package   paid     individual therapy sessions, therapy-session
--                             vouchers
--   credit package   bonus    own-brand products
--   premium bundle   paid     anything supported EXCEPT new credit packages
--                             and premium bundles
--   premium bundle   bonus    same as premium-bundle paid
--
-- Provenance already exists and is used rather than reinvented:
-- customer_credit_lots.source_type is 'credit_package' or 'premium_bundle' and
-- source_record_id is the catalogue row, both written at grant time. The
-- category column is already 'paid' or 'bonus'.
--
-- What the existing code already gets right, and is left alone:
--   * allocate_invoice_wallet_credit already refuses to fund credit_package and
--     premium_bundle lines from any wallet credit, so "no buying packages with
--     credit" is enforced already;
--   * it allocates per line against the line's unfunded amount, after discount,
--     takes lots FOR UPDATE, and leaves any shortfall to another payment method.
--
-- What was missing is the source-and-category matrix, and one dangerous
-- default: credit_lot_allows() treats an empty usage_restrictions as "spendable
-- on anything". A lot whose provenance cannot be established therefore spent
-- freely. Section 3 stops that: an unidentifiable lot is refused and reported
-- for review rather than assumed unrestricted.
--
-- Classification uses the real models — products.product_type for own-brand,
-- vouchers.voucher_kind for session versus money-off — never a name.
--
-- No amount is changed anywhere in this file. Run AFTER 240.
-- =====================================================================

set check_function_bodies = off;

-- An individual therapy session on an invoice line points at a service. This is
-- the discriminator that keeps an unlimited-therapy line from being mistaken
-- for a session, which matters because they have opposite credit eligibility.
alter table public.invoice_items
  add column if not exists therapy_service_id uuid references public.therapy_services(id);

comment on column public.invoice_items.therapy_service_id is
  'Set on a line_kind = ''therapy'' line that sells ONE individual session. An '
  'unlimited-therapy line leaves it null. Credit eligibility depends on the '
  'difference, so it must not be inferred from a name or a price.';

-- ---------------------------------------------------------------------
-- 1. The policy a lot carries, derived from its provenance.
-- ---------------------------------------------------------------------
create or replace function public.credit_lot_policy(p_source_type text, p_category text, p_has_source boolean)
returns text language sql immutable as $function$
  select case
    when p_source_type = 'credit_package' and not p_has_source then 'needs_review'
    when p_source_type = 'premium_bundle' and not p_has_source then 'needs_review'
    when p_source_type = 'credit_package' and p_category = 'paid'  then 'package_paid'
    when p_source_type = 'credit_package' and p_category = 'bonus' then 'package_bonus'
    when p_source_type = 'premium_bundle' then 'bundle_any'
    -- Sources this system creates for reasons unrelated to packages keep the
    -- behaviour they have always had. Listed explicitly: an unrecognised value
    -- must not fall through to "unrestricted".
    when p_source_type in ('manual','manual_legacy','manual_use','exchange',
                           'invoice_cancel_benefit','invoice_benefit_refund',
                           'adjustment','opening_balance','transfer')
      then 'open'
    else 'needs_review'
  end
$function$;

comment on function public.credit_lot_policy(text,text,boolean) is
  'The spending policy for a credit lot. An unrecognised or unverifiable source '
  'returns needs_review, which blocks spending until a person confirms it — '
  'guessing "unrestricted" is how a restricted balance quietly becomes cash.';

create or replace function public.credit_lot_policy_for(p_lot_id uuid)
returns text language sql stable set search_path = public as $function$
  select public.credit_lot_policy(l.source_type, l.category, l.source_record_id is not null)
    from public.customer_credit_lots l where l.id = p_lot_id
$function$;

-- ---------------------------------------------------------------------
-- 2. What a single purchased thing is, in the terms the matrix uses.
--
-- Read from the actual classification models. A product is own-brand because
-- products.product_type says so; a voucher is a session voucher because
-- vouchers.voucher_kind says 'normal'; a therapy line is an individual session
-- because it names a service.
-- ---------------------------------------------------------------------
create or replace function public.purchase_category(
  p_purpose text, p_product_id uuid default null, p_voucher_id uuid default null,
  p_therapy_service_id uuid default null)
returns text language sql stable set search_path = public as $function$
  select case p_purpose
    when 'product' then
      case (select p.product_type::text from public.products p where p.id = p_product_id)
        when 'own' then 'own_product'
        when 'third_party' then 'third_party_product'
        when 'no_commission' then 'other_product'
        else 'unknown' end
    when 'voucher' then
      case (select v.voucher_kind::text from public.vouchers v where v.id = p_voucher_id)
        when 'normal' then 'session_voucher'
        when 'fixed_discount' then 'money_voucher'
        when 'percentage_discount' then 'money_voucher'
        else 'unknown' end
    when 'therapy' then
      case when p_therapy_service_id is not null then 'therapy_session' else 'unlimited_therapy' end
    when 'credit_package' then 'credit_package'
    when 'premium_bundle' then 'premium_bundle'
    when 'promotion' then 'promotion'
    else 'unknown'
  end
$function$;

-- ---------------------------------------------------------------------
-- 3. The matrix itself.
-- ---------------------------------------------------------------------
create or replace function public.credit_policy_allows(p_policy text, p_category text)
returns boolean language sql immutable as $function$
  select case p_policy
    when 'package_paid' then p_category in ('therapy_session','session_voucher')
    when 'package_bonus' then p_category = 'own_product'
    when 'bundle_any' then p_category not in ('credit_package','premium_bundle','unknown')
    when 'open' then p_category not in ('credit_package','premium_bundle','unknown')
    when 'needs_review' then false
    else false
  end
$function$;

create or replace function public.credit_policy_reason(p_policy text, p_category text)
returns text language sql immutable as $function$
  select case
    when public.credit_policy_allows(p_policy, p_category) then null
    when p_policy = 'needs_review' then
      'This balance came from a source this system cannot identify, so it cannot be spent until someone confirms where it came from.'
    when p_policy = 'package_paid' then
      'Credit-package paid credit can only pay for individual therapy sessions and therapy-session vouchers.'
    when p_policy = 'package_bonus' then
      'Credit-package bonus credit can only pay for own-brand products.'
    when p_category in ('credit_package','premium_bundle') then
      'Credit cannot be used to buy another credit package or premium bundle.'
    when p_category = 'unknown' then
      'This item is not classified, so no credit balance can be checked against it.'
    else 'This balance cannot pay for this item.'
  end
$function$;

-- ---------------------------------------------------------------------
-- 4. A whole invoice line, including a composite one.
--
-- A promotion is a wrapper around other things, so it cannot be used to launder
-- eligibility: a restricted balance may fund a promotion line only if EVERY
-- component of it would have been eligible on its own. A promotion with no
-- recorded components cannot be checked, so it is refused rather than assumed.
-- ---------------------------------------------------------------------
create or replace function public.credit_lot_line_allowed(p_lot_id uuid, p_invoice_item_id uuid)
returns boolean language plpgsql stable set search_path = public as $function$
declare
  v_policy text := public.credit_lot_policy_for(p_lot_id);
  v_it record; v_purpose text; v_cat text; v_components integer; v_bad integer;
begin
  if v_policy is null then return false; end if;

  select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
    into v_it from public.invoice_items ii where ii.id = p_invoice_item_id;
  if not found then return false; end if;
  v_purpose := v_it.purpose;

  if v_purpose <> 'promotion' then
    v_cat := public.purchase_category(v_purpose, v_it.product_id, v_it.voucher_id, v_it.therapy_service_id);
    return public.credit_policy_allows(v_policy, v_cat);
  end if;

  -- Composite. An unrestricted-enough policy still has to clear every part.
  select count(*),
         count(*) filter (where not public.credit_policy_allows(v_policy,
           public.purchase_category(
             case when s.product_id is not null then 'product'
                  when s.voucher_id is not null then 'voucher'
                  else 'unknown' end,
             s.product_id, s.voucher_id, null)))
    into v_components, v_bad
    from public.invoice_promotion_selections s
   where s.invoice_item_id = p_invoice_item_id;

  if coalesce(v_components, 0) = 0 then
    -- Nothing recorded to check. An 'open' or bundle policy keeps its existing
    -- freedom; a package-restricted one does not get the benefit of the doubt.
    return v_policy in ('open','bundle_any');
  end if;
  return v_bad = 0;
end $function$;

create or replace function public.credit_lot_line_reason(p_lot_id uuid, p_invoice_item_id uuid)
returns text language plpgsql stable set search_path = public as $function$
declare
  v_policy text := public.credit_lot_policy_for(p_lot_id);
  v_it record; v_cat text;
begin
  if public.credit_lot_line_allowed(p_lot_id, p_invoice_item_id) then return null; end if;
  select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
    into v_it from public.invoice_items ii where ii.id = p_invoice_item_id;
  if not found then return 'That invoice line no longer exists.'; end if;

  if v_it.purpose = 'promotion' then
    return case when v_policy in ('open','bundle_any')
      then 'This promotion contains items this balance cannot pay for, and the parts cannot be separated safely. Use another payment method for this line.'
      else public.credit_policy_reason(v_policy, 'promotion')
           || ' A promotion containing other items does not change that.' end;
  end if;
  v_cat := public.purchase_category(v_it.purpose, v_it.product_id, v_it.voucher_id, v_it.therapy_service_id);
  return public.credit_policy_reason(v_policy, v_cat);
end $function$;

-- ---------------------------------------------------------------------
-- 5. Enforcement, added to the existing allocation rather than replacing it.
--
-- The function is fetched, one condition is inserted into its lot filter, and it
-- is re-created. Restating the whole body here would be a second copy free to
-- drift from the one migration 82 maintains — and the surrounding logic
-- (per-line open amounts, FOR UPDATE, bonus-first ordering) is already correct
-- and must not be disturbed.
-- ---------------------------------------------------------------------
do $$
declare f text; v_anchor text;
begin
  select pg_get_functiondef('public.allocate_invoice_wallet_credit(uuid,numeric,text)'::regprocedure) into f;

  v_anchor := 'and public.credit_lot_allows(l.usage_restrictions, v_purpose, v_vid)';
  if position(v_anchor in f) = 0 then
    raise exception 'allocate_invoice_wallet_credit does not have the expected lot filter — check migration 82';
  end if;
  if position('credit_lot_line_allowed' in f) > 0 then
    return;                                  -- already patched; running twice is fine
  end if;

  f := replace(f, v_anchor,
    v_anchor || chr(10) ||
    '         -- Migration 242: the source-and-category matrix. A lot may only' || chr(10) ||
    '         -- fund a line its provenance permits.' || chr(10) ||
    '         and public.credit_lot_line_allowed(l.id, v_it.id)');
  execute f;
end $$;

-- consume_customer_credit is the non-invoice path (a direct spend with a stated
-- purpose). It has no invoice line to inspect, so it gets the component-level
-- check with what it does know.
do $$
declare f text; v_anchor text; sig text;
begin
  select p.oid::regprocedure::text into sig from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'consume_customer_credit'
   order by p.pronargs desc limit 1;
  if sig is null then return; end if;

  select pg_get_functiondef(sig::regprocedure) into f;
  v_anchor := 'and public.credit_lot_allows(usage_restrictions, p_purpose, p_voucher_id)';
  if position(v_anchor in f) = 0 then return; end if;      -- a different shape; leave it
  if position('credit_policy_allows' in f) > 0 then return; end if;

  f := replace(f, v_anchor,
    v_anchor || chr(10) ||
    '       and public.credit_policy_allows(' || chr(10) ||
    '             public.credit_lot_policy(source_type, category, source_record_id is not null),' || chr(10) ||
    '             public.purchase_category(p_purpose, null, p_voucher_id, null))');
  execute f;
end $$;

-- ---------------------------------------------------------------------
-- 6. What a customer's balances may actually be spent on, for the interface.
--
-- The point of showing this is that "S$400 available" is misleading when S$300
-- of it can only buy own-brand products. The usable figure is per policy, and
-- the reason travels with it.
-- ---------------------------------------------------------------------
create or replace function public.customer_credit_eligibility(p_customer_id uuid)
returns table (
  lot_id uuid, category text, source_type text, source_name text,
  policy text, policy_label text, remaining numeric,
  needs_review boolean, allowed_categories text[], explanation text)
language sql stable security definer set search_path = public as $function$
  select l.id, l.category, l.source_type,
         coalesce(cp.name, pb.name, l.reference_no, l.source_type),
         public.credit_lot_policy(l.source_type, l.category, l.source_record_id is not null),
         case public.credit_lot_policy(l.source_type, l.category, l.source_record_id is not null)
           when 'package_paid'  then 'Therapy sessions and therapy vouchers only'
           when 'package_bonus' then 'Own-brand products only'
           when 'bundle_any'    then 'Anything except new credit packages and premium bundles'
           when 'open'          then 'Anything except new credit packages and premium bundles'
           else 'Needs review before it can be spent' end,
         l.remaining_amount,
         public.credit_lot_policy(l.source_type, l.category, l.source_record_id is not null) = 'needs_review',
         coalesce((select array_agg(c order by c) from unnest(array[
             'own_product','third_party_product','other_product','session_voucher',
             'money_voucher','therapy_session','unlimited_therapy','promotion']) c
            where public.credit_policy_allows(
              public.credit_lot_policy(l.source_type, l.category, l.source_record_id is not null), c)), '{}'),
         public.credit_policy_reason(
           public.credit_lot_policy(l.source_type, l.category, l.source_record_id is not null), 'unknown')
    from public.customer_credit_lots l
    left join public.credit_packages cp
      on l.source_type = 'credit_package' and cp.id = l.source_record_id
    left join public.premium_bundles pb
      on l.source_type = 'premium_bundle' and pb.id = l.source_record_id
   where l.customer_id = p_customer_id and l.status = 'active' and l.remaining_amount > 0
   order by l.category, l.effective_date
$function$;

-- ---------------------------------------------------------------------
-- 7. Historical balances: what the rules mean for money already granted.
--
-- Read-only, and it changes no amount. §10 of the brief is explicit that these
-- rules apply to existing balances and that a balance whose source cannot be
-- reconstructed must be visibly held for review rather than assumed free.
-- ---------------------------------------------------------------------
create or replace function public.credit_eligibility_diagnostic()
returns table (
  policy text, lots bigint, customers bigint, total_remaining numeric,
  meaning text, action_needed text)
language sql stable security definer set search_path = public as $function$
  select p.policy, count(*), count(distinct l.customer_id),
         round(sum(l.remaining_amount), 2),
         case p.policy
           when 'package_paid'  then 'Credit-package paid credit — therapy sessions and therapy vouchers only.'
           when 'package_bonus' then 'Credit-package bonus credit — own-brand products only.'
           when 'bundle_any'    then 'Premium-bundle credit — anything but new packages and bundles.'
           when 'open'          then 'Granted for a reason unrelated to packages; unchanged by this migration.'
           else 'Source cannot be identified.' end,
         case p.policy
           when 'needs_review' then 'Spending is blocked until someone confirms where this balance came from. No amount has been changed.'
           else 'None. The restriction applies from now on; the balance is untouched.' end
    from public.customer_credit_lots l
    cross join lateral (select public.credit_lot_policy(
      l.source_type, l.category, l.source_record_id is not null) as policy) p
   where l.status = 'active' and l.remaining_amount > 0
     and public.is_manager_or_above()
   group by p.policy
   order by 4 desc nulls last
$function$;

-- The individual lots that cannot be spent until reviewed, so the list is
-- actionable rather than a count.
create or replace function public.credit_lots_needing_review()
returns table (lot_id uuid, customer_id uuid, customer_name text, category text,
               source_type text, source_record_id uuid, remaining numeric,
               granted_on date, reference_no text, reason text)
language sql stable security definer set search_path = public as $function$
  select l.id, l.customer_id, c.full_name, l.category, l.source_type, l.source_record_id,
         l.remaining_amount, l.effective_date, l.reference_no,
         case when l.source_record_id is null
                and l.source_type in ('credit_package','premium_bundle')
              then 'Says it came from a ' || replace(l.source_type, '_', ' ')
                   || ' but does not say which one, so its restriction cannot be established.'
              else 'Source type "' || l.source_type || '" is not one this system recognises.' end
    from public.customer_credit_lots l
    left join public.customers c on c.id = l.customer_id
   where l.status = 'active' and l.remaining_amount > 0
     and public.credit_lot_policy(l.source_type, l.category, l.source_record_id is not null) = 'needs_review'
     and public.is_manager_or_above()
   order by l.remaining_amount desc
$function$;

grant execute on function public.credit_lot_policy(text,text,boolean) to authenticated;
grant execute on function public.credit_lot_policy_for(uuid) to authenticated;
grant execute on function public.purchase_category(text,uuid,uuid,uuid) to authenticated;
grant execute on function public.credit_policy_allows(text,text) to authenticated;
grant execute on function public.credit_policy_reason(text,text) to authenticated;
grant execute on function public.credit_lot_line_allowed(uuid,uuid) to authenticated;
grant execute on function public.credit_lot_line_reason(uuid,uuid) to authenticated;
grant execute on function public.customer_credit_eligibility(uuid) to authenticated;
grant execute on function public.credit_eligibility_diagnostic() to authenticated;
grant execute on function public.credit_lots_needing_review() to authenticated;

do $$
declare v_review integer; v_amount numeric;
begin
  select count(*), coalesce(round(sum(remaining_amount), 2), 0) into v_review, v_amount
    from public.customer_credit_lots l
   where l.status = 'active' and l.remaining_amount > 0
     and public.credit_lot_policy(l.source_type, l.category, l.source_record_id is not null) = 'needs_review';
  if v_review > 0 then
    raise notice 'HOLD: % credit lot(s) totalling S$% cannot be identified and are blocked from new spending until reviewed. No amount was changed. See credit_lots_needing_review().', v_review, v_amount;
  else
    raise notice 'Every active credit lot has an identifiable source.';
  end if;
end $$;
