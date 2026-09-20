begin;
-- =====================================================================
-- A NEGATIVE QUANTITY IS NOT A DISCOUNT
--
-- claim_entitlement_vouchers checks the size of a claim in one loop and
-- issues the vouchers in another. The two loops did not agree about what a
-- quantity is.
--
-- The check added every quantity as it found it:
--
--     v_sum := v_sum + coalesce((v_sel->>'quantity')::integer, 0);
--
-- The issue loop skipped the ones that were not positive:
--
--     if v_q <= 0 then continue; end if;
--
-- So a selection of [{A: 5}, {B: -3}] sums to 2, passes "only 2 left to
-- claim", and then issues five of voucher A. The negative line is skipped on
-- the way out but was counted on the way in. Worse, the claim is recorded as a
-- quantity of 2, so the entitlement still reads as having 2 claimed against it
-- and the extra three are invisible in every total.
--
-- Stock is only a partial backstop: the stock branch runs for tracked vouchers
-- and an 'unlimited' voucher has no ceiling to hit at all.
--
-- The application never sends such a payload — VoucherClaimPanel filters to
-- q > 0 before calling — so a quantity below one is a malformed request, and
-- the right answer is to refuse the whole claim rather than to honour part of
-- it. Two sibling functions, validate_bundle_voucher_selection and
-- sell_credit_package_with_vouchers, already skip non-positive quantities
-- BEFORE summing and so were never exposed.
--
-- Anchored on the installed text and idempotent: once rewritten, the old
-- summation line is gone and the migration finds nothing to do.
-- =====================================================================
do $$
declare
  v_oid oid;
  v_src text;
  v_new text;
  v_anchor constant text := '    v_sum := v_sum + coalesce((v_sel->>''quantity'')::integer,0);';
  v_fix constant text :=
    '    v_q := coalesce((v_sel->>''quantity'')::integer, 0);' || E'\n' ||
    '    if v_q < 1 then' || E'\n' ||
    '      raise exception ''A voucher quantity must be a whole number of at least one; got %'', v_q;' || E'\n' ||
    '    end if;' || E'\n' ||
    '    v_sum := v_sum + v_q;';
begin
  select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'claim_entitlement_vouchers';

  if v_oid is null then
    raise notice '341: claim_entitlement_vouchers is not installed here; nothing to do';
    return;
  end if;

  v_src := pg_get_functiondef(v_oid);

  if position(v_anchor in v_src) = 0 then
    -- Either already fixed, or the function has been rewritten since. Refuse to
    -- guess which.
    if v_src ~ 'A voucher quantity must be a whole number' then
      raise notice '341: claim_entitlement_vouchers already refuses a quantity below one';
      return;
    end if;
    raise exception '341: claim_entitlement_vouchers no longer contains the summation this migration was written against; review it by hand';
  end if;

  v_new := replace(v_src, v_anchor, v_fix);
  execute v_new;
  raise notice '341: claim_entitlement_vouchers now refuses a claim containing a quantity below one';
end $$;

-- The counting loop and the issuing loop must now agree: nothing may be added
-- to the total that the issue loop would skip.
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'claim_entitlement_vouchers';
  if v_src is not null and v_src ~ 'v_sum := v_sum \+ coalesce' then
    raise exception '341: the claim total is still summed without checking the quantity';
  end if;
end $$;

notify pgrst, 'reload schema';
commit;
