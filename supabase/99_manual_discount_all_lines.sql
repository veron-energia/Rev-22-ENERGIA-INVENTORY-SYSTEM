-- =====================================================================
-- ENERGIA — MANUAL DISCOUNT APPLIES TO EVERY LINE
--
-- The manual discount shared a cap with voucher discounts:
--
--     v_discountable := v_subtotal - v_third_sum;   -- third-party excluded
--
-- so a manual discount on an invoice of third-party products was silently
-- reduced, sometimes to nothing, with no message explaining why. That rule
-- belongs to VOUCHERS — a voucher's terms should not fund somebody else's
-- goods — not to a manual discount the Owner or Manager has decided to give.
--
-- After this migration:
--   * MANUAL discount may be applied to the whole invoice: normal products,
--     third-party products, vouchers, promotions, therapy, credit packages and
--     premium bundles alike;
--   * VOUCHER discounts keep their existing base, still excluding third-party
--     products, and the per-line block on third-party lines is unchanged;
--   * the combined discount can never exceed the invoice subtotal.
--
-- Commission is unaffected: it is already computed from the discounted,
-- externally-paid value per line.
--
-- Additive and idempotent. Run AFTER 98.
-- =====================================================================

set check_function_bodies = off;

do $patch$
declare
  v_name text; v_def text; v_new text; v_count integer := 0;
begin
  foreach v_name in array array['create_invoice','update_invoice']
  loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_name;
    if v_def is null then
      raise notice '% not found — skipping', v_name; continue;
    end if;
    if position('v_manual_base' in v_def) > 0 then
      raise notice '% already allows a manual discount everywhere', v_name; continue;
    end if;

    -- Two bases instead of one: the manual discount sees the whole invoice,
    -- vouchers keep the narrower base they have always had.
    v_new := replace(v_def,
      '  v_discountable := v_subtotal - v_third_sum;',
      '  -- A manual discount is a deliberate decision by an Owner or Manager and'
      || chr(10) ||
      '  -- may be given against anything on the invoice, third-party included.'
      || chr(10) ||
      '  -- Voucher discounts keep the narrower base, since a voucher''s terms'
      || chr(10) ||
      '  -- should not fund third-party goods.'
      || chr(10) ||
      '  v_manual_base := v_subtotal;' || chr(10) ||
      '  v_discountable := v_subtotal - v_third_sum;');

    if position('v_manual_base := v_subtotal;' in v_new) = 0 then
      raise exception 'Could not introduce the manual discount base in %', v_name;
    end if;

    -- Declare it alongside the existing locals.
    v_new := replace(v_new,
      '  v_ptype text; v_third_sum numeric := 0; v_discountable numeric; v_wbase numeric;',
      '  v_ptype text; v_third_sum numeric := 0; v_discountable numeric; v_wbase numeric;'
      || chr(10) ||
      '  v_manual_base numeric; v_manual_capped numeric;');

    -- The voucher base is what remains after the manual discount, measured on
    -- the voucher's own base so it cannot spill onto third-party value.
    v_new := replace(v_new,
      '    v_wbase := v_discountable - v_manual - v_line_disc_sum;',
      '    v_wbase := v_discountable - least(v_manual, v_discountable) - v_line_disc_sum;');

    -- Cap the manual discount at the whole invoice, and the total at the same.
    v_new := replace(v_new,
      '  if v_discount > v_discountable then v_discount := v_discountable; end if;',
      '  -- The manual portion is capped by the WHOLE invoice; the rest by the'
      || chr(10) ||
      '  -- voucher base. Together they can never exceed what was charged.'
      || chr(10) ||
      '  v_manual_capped := least(v_manual, v_manual_base);' || chr(10) ||
      '  v_discount := least(v_discount - v_manual + v_manual_capped, v_manual_base);'
      || chr(10) ||
      '  if v_discount > v_manual_base then v_discount := v_manual_base; end if;');

    if position('v_manual_capped := least' in v_new) = 0 then
      raise exception 'Could not raise the discount cap in %', v_name;
    end if;

    execute v_new;
    v_count := v_count + 1;
  end loop;

  raise notice 'Manual discount now applies to every line kind in % function(s)', v_count;
end $patch$;

notify pgrst, 'reload schema';
