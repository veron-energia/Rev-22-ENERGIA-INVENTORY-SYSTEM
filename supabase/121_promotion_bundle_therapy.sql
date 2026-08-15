-- =====================================================================
-- ENERGIA — THERAPY INSIDE A PROMOTION OR BUNDLE NEVER REACHED "PURCHASED"
--
-- create_purchased_therapy_for_invoice() looked only at invoice lines of kind
-- 'therapy':
--
--     for v_li in select * from public.invoice_items
--                  where invoice_id = p_invoice_id and line_kind = 'therapy'
--
-- A promotion or premium bundle is ONE line of kind 'promotion' /
-- 'premium_bundle'; the therapy it includes lives in promotion_items (fixed
-- contents) or promotion_choice_options (what the customer chose). Neither was
-- looked at, so the customer paid and the therapy never appeared in Purchased —
-- and, being an entitlement, it could not be redeemed either.
--
-- Reproduced before fixing: a direct purchase produced 1 entitlement; the same
-- package inside a promotion produced 0.
--
-- Two gaps are closed:
--
--   1. FIXED CONTENTS — therapy listed in promotion_items now creates an
--      entitlement per unit, for promotions and bundles alike.
--
--   2. CHOSEN CONTENTS — invoice_promotion_selections could not even record a
--      chosen therapy: it had product_id and voucher_id but no
--      therapy_package_id. The column is added, create_invoice records it, and
--      an entitlement follows.
--
-- Existing paid invoices are backfilled, so therapy already sold this way
-- appears without anyone having to re-enter it.
--
-- Additive and idempotent. Run AFTER 120.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. A chosen therapy can now be recorded against the invoice line.
-- ---------------------------------------------------------------------
alter table public.invoice_promotion_selections
  add column if not exists therapy_package_id uuid references public.unlimited_therapy_packages(id);

-- ---------------------------------------------------------------------
-- 2. Every therapy an invoice entitles the customer to, from any source.
--
--    Returns one row per entitlement that should exist, so the creation and
--    the backfill share exactly one definition of what is owed.
-- ---------------------------------------------------------------------
create or replace function public.invoice_therapy_entitlements_due(p_invoice_id uuid)
returns table(invoice_item_id uuid, therapy_package_id uuid, source text, qty integer)
language sql stable security definer set search_path to 'public' as $function$
  -- (a) Therapy bought directly.
  select ii.id, ii.therapy_package_id, 'direct', greatest(coalesce(ii.quantity, 1), 1)
    from public.invoice_items ii
   where ii.invoice_id = p_invoice_id
     and ii.line_kind::text = 'therapy'
     and ii.therapy_package_id is not null
  union all
  -- (b) Therapy that is part of a promotion or bundle's FIXED contents.
  --     Multiplied by the line quantity: two of the promotion means two.
  select ii.id, pi.therapy_package_id, 'promotion_item',
         greatest(coalesce(ii.quantity, 1), 1) * greatest(coalesce(pi.quantity, 1), 1)
    from public.invoice_items ii
    join public.promotion_items pi on pi.promotion_id = ii.promotion_id
   where ii.invoice_id = p_invoice_id
     and ii.line_kind::text in ('promotion', 'premium_bundle')
     and pi.therapy_package_id is not null
  union all
  -- (c) Therapy the customer CHOSE from a promotion's options.
  select ii.id, ips.therapy_package_id, 'promotion_choice',
         greatest(coalesce(ips.quantity, 1), 1)
    from public.invoice_items ii
    join public.invoice_promotion_selections ips on ips.invoice_item_id = ii.id
   where ii.invoice_id = p_invoice_id
     and ips.therapy_package_id is not null
$function$;

-- ---------------------------------------------------------------------
-- 3. Create the entitlements from that definition.
-- ---------------------------------------------------------------------
create or replace function public.create_purchased_therapy_for_invoice(p_invoice_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_due record; v_pkg public.unlimited_therapy_packages%rowtype;
  v_deadline date; v_n integer := 0; v_have integer; v_i integer;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return 0; end if;

  for v_due in select * from public.invoice_therapy_entitlements_due(p_invoice_id)
  loop
    select * into v_pkg from public.unlimited_therapy_packages where id = v_due.therapy_package_id;
    if not found then continue; end if;

    -- How many already exist for this line and package, so a re-run tops up to
    -- the right number rather than duplicating or skipping.
    select count(*) into v_have from public.purchased_therapy_entitlements
     where invoice_item_id = v_due.invoice_item_id
       and package_id = v_due.therapy_package_id;

    -- One year to ACTIVATE, matching the existing direct-purchase rule. The
    -- package's duration_months governs how long it runs once activated, not
    -- this deadline.
    v_deadline := (coalesce(v_inv.paid_at, now()) at time zone 'Asia/Singapore')::date
                  + interval '1 year';

    -- The price snapshot is per entitlement. Therapy included in a promotion has
    -- no separate price of its own, so it is recorded as 0 rather than
    -- attributing the whole promotion price to it.
    for v_i in 1 .. greatest(v_due.qty - v_have, 0) loop
      insert into public.purchased_therapy_entitlements (
        entitlement_no, customer_id, store_id, package_id, invoice_id, invoice_item_id,
        package_name, duration_months, price_snapshot, price_mode,
        purchase_date, activation_deadline, status, created_by, updated_by)
      values (
        public.next_purchased_therapy_no(), v_inv.customer_id, v_inv.store_id, v_pkg.id,
        p_invoice_id, v_due.invoice_item_id,
        v_pkg.name, v_pkg.duration_months,
        case when v_due.source = 'direct'
          then coalesce((select unit_price from public.invoice_items
                          where id = v_due.invoice_item_id), 0)
          else 0 end,
        (select price_mode from public.invoice_items where id = v_due.invoice_item_id),
        (coalesce(v_inv.paid_at, now()) at time zone 'Asia/Singapore')::date,
        v_deadline::date, 'pending_activation', auth.uid(), auth.uid());
      v_n := v_n + 1;
    end loop;
  end loop;

  if v_n > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'therapy_entitlements_created', null,
      jsonb_build_object('created', v_n), 'therapy', null, v_inv.store_id);
  end if;
  return v_n;
end $function$;

-- ---------------------------------------------------------------------
-- 4. Backfill invoices already paid.
--
--    Only settled invoices, and only what is missing: an entitlement already
--    activated or redeemed is never touched.
-- ---------------------------------------------------------------------
do $$
declare v_inv record; v_made integer; v_total integer := 0; v_invoices integer := 0;
begin
  for v_inv in
    select distinct i.id
      from public.invoices i
      join public.invoice_items ii on ii.invoice_id = i.id
     where i.status in ('paid','completed_foc')
       and i.deleted_at is null
       and ii.line_kind::text in ('promotion','premium_bundle')
       and (exists (select 1 from public.promotion_items pi
                     where pi.promotion_id = ii.promotion_id
                       and pi.therapy_package_id is not null)
            or exists (select 1 from public.invoice_promotion_selections ips
                        where ips.invoice_item_id = ii.id
                          and ips.therapy_package_id is not null))
  loop
    v_made := public.create_purchased_therapy_for_invoice(v_inv.id);
    if v_made > 0 then
      v_total := v_total + v_made;
      v_invoices := v_invoices + 1;
    end if;
  end loop;

  if v_total > 0 then
    raise notice 'Backfilled % therapy entitlement(s) across % paid invoice(s)', v_total, v_invoices;
  else
    raise notice 'No promotion or bundle therapy needed backfilling';
  end if;
end $$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 5. The SETTLEMENT TRIGGER had the same assumption, one level up.
--
--    trg_create_therapy_on_paid only called create_purchased_therapy_for_invoice
--    when the invoice had a line of kind 'therapy':
--
--        if exists (select 1 from public.invoice_items
--                    where invoice_id = new.id and line_kind = 'therapy') then
--
--    So for a promotion or bundle invoice the function was never called at all,
--    however well it handled those lines. Fixing the function alone changed
--    nothing — the guard has to widen too.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'trg_create_therapy_on_paid';
  if v_def is null then raise exception 'trg_create_therapy_on_paid not found'; end if;
  if position('invoice_therapy_entitlements_due' in v_def) > 0 then
    raise notice 'the settlement trigger already covers promotions and bundles'; return;
  end if;

  -- Ask the same question the creation uses: is any therapy due at all, from
  -- any source? One definition, so the two can never disagree again.
  v_new := replace(v_def,
    '    if exists (select 1 from public.invoice_items where invoice_id = new.id and line_kind = ''therapy'') then',
    '    if exists (select 1 from public.invoice_therapy_entitlements_due(new.id)) then');

  if position('invoice_therapy_entitlements_due' in v_new) = 0 then
    raise exception 'Could not widen the settlement trigger';
  end if;
  execute v_new;
  raise notice 'the settlement trigger now creates therapy from promotions and bundles too';
end $patch$;

notify pgrst, 'reload schema';
