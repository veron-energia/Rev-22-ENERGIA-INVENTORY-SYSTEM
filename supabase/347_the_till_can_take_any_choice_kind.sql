begin;
-- =====================================================================
-- THE TILL CAN TAKE ANY KIND OF CHOICE
--
-- 346 let a choice group offer a promotion, and unblocked therapy and credit
-- packages, which the options table had been refusing since they were added.
-- The till still could not accept any of them.
--
-- create_invoice and update_invoice_internal each validate a promotion line's
-- selections with a two-way branch:
--
--     if v_grp.item_kind = 'voucher' then ... check it belongs to the group ...
--     else  -- assumes product
--       if (v_opt->>'product_id') is null then
--         raise exception 'Choice group "%" expects product selections', v_grp.label;
--
-- So a therapy, credit-package or promotion group is refused with a message
-- about products that the cashier can do nothing about.
--
-- WHAT A NON-PRODUCT CHOICE COSTS. Nothing extra, which is the rule a voucher
-- group already follows and the owner's decision for the rest: the promotion's
-- own price covers whichever option is picked. promotion_selections_topup only
-- ever looks at item_kind = 'product', so this needs no pricing change — a
-- non-product group contributes no top-up, by construction. Only a product
-- group surcharges a substitution, and that is unchanged.
--
-- So the validation each of these kinds needs is the one vouchers already get:
-- is the thing the cashier picked actually one of the options this group
-- offers? That is now asked once, for all four non-product kinds.
--
-- Anchored on the installed text of both functions, and idempotent.
-- =====================================================================
do $$
declare
  f record;
  v_src text; v_new text; v_fixed int := 0; v_names text := '';
  v_anchor constant text :=
'              if v_grp.item_kind = ''voucher'' then
                select exists (
                  select 1 from public.promotion_choice_options o
                  where o.group_id = v_grp.id
                    and (v_opt->>''voucher_id'') is not null and o.voucher_id = (v_opt->>''voucher_id'')::uuid
                ) into v_ok;
                if not v_ok then raise exception ''A selected voucher does not belong to choice group "%"'', v_grp.label; end if;
              else';
  v_fix constant text :=
'              if v_grp.item_kind <> ''product'' then
                -- Vouchers, therapy, credit packages and promotions are all
                -- covered by the promotion''s own price: the cashier picks from
                -- what the group offers and the bundle price stands. So the only
                -- question is whether the pick is one of the offered options.
                -- (promotion_selections_topup reads product groups only, so a
                -- non-product group contributes no top-up by construction.)
                select exists (
                  select 1 from public.promotion_choice_options o
                  where o.group_id = v_grp.id
                    and case v_grp.item_kind
                          when ''voucher'' then
                            (v_opt->>''voucher_id'') is not null and o.voucher_id = (v_opt->>''voucher_id'')::uuid
                          when ''therapy'' then
                            (v_opt->>''therapy_package_id'') is not null and o.therapy_package_id = (v_opt->>''therapy_package_id'')::uuid
                          when ''credit_package'' then
                            (v_opt->>''credit_package_id'') is not null and o.credit_package_id = (v_opt->>''credit_package_id'')::uuid
                          when ''promotion'' then
                            (v_opt->>''child_promotion_id'') is not null and o.child_promotion_id = (v_opt->>''child_promotion_id'')::uuid
                          else false
                        end
                ) into v_ok;
                if not v_ok then
                  raise exception ''A selected % does not belong to choice group "%"'',
                    replace(v_grp.item_kind, ''_'', '' ''), v_grp.label;
                end if;
              else';
begin
  for f in
    select p.oid, p.oid::regprocedure::text as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.proname in ('create_invoice','update_invoice_internal')
     order by p.proname
  loop
    v_src := pg_get_functiondef(f.oid);
    if v_src ~ 'does not belong to choice group' and v_src ~ 'item_kind <> ''product''' then
      continue;                                   -- already carries the fix
    end if;
    if position(v_anchor in v_src) = 0 then
      continue;                                   -- this overload has no choice branch
    end if;
    v_new := replace(v_src, v_anchor, v_fix);
    execute v_new;
    v_fixed := v_fixed + 1;
    v_names := v_names || f.proname || ' ';
  end loop;

  if v_fixed = 0 then
    raise notice '347: no function still refuses a non-product choice (already applied)';
  else
    raise notice '347: % function(s) now accept every kind of choice: %', v_fixed, v_names;
  end if;
end $$;

-- A tidy-up in the same area, which changes nothing today. The top-up function
-- takes p_is_member and then prices the pick with a hardcoded true. It is
-- harmless because store_product_prices has a single selling_price and
-- product_price_for returns it for member and non-member alike — no invoice has
-- ever been charged differently for it. It is still wrong, and would become a
-- real discrepancy the day a member price is introduced.
do $$
declare f record; v_src text; v_new text; v_fixed int := 0;
begin
  for f in
    select p.oid, p.oid::regprocedure::text as sig from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'promotion_selections_topup'
       and pg_get_function_arguments(p.oid) like '%p_is_member%'
  loop
    v_src := pg_get_functiondef(f.oid);
    v_new := replace(v_src,
      'public.product_price_for(p_store_id, (v_opt->>''product_id'')::uuid, true)',
      'public.product_price_for(p_store_id, (v_opt->>''product_id'')::uuid, p_is_member)');
    if v_new = v_src then continue; end if;
    execute v_new;
    v_fixed := v_fixed + 1;
  end loop;
  if v_fixed > 0 then
    raise notice '347: the top-up now prices a substitution with the caller''s member status rather than assuming member';
  end if;
end $$;

do $$
declare v_left text := '';
begin
  -- Both functions must now carry the shared non-product branch. The words
  -- "expects product selections" legitimately REMAIN, in the product branch
  -- below it, so their absence is not the thing to check for.
  -- Only the overloads that actually handle choice groups. Production carries a
  -- legacy 7-argument create_invoice, from before service staff, whose body
  -- never mentions promotion_choice_groups; it is not this migration's to
  -- change and must not be demanded of.
  select string_agg(p.oid::regprocedure::text, ', ') into v_left
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('create_invoice','update_invoice_internal')
     and p.prosrc like '%promotion_choice_groups%'
     and not (p.prosrc ~ 'item_kind <> ''product''' and p.prosrc ~ 'does not belong to choice group');
  if v_left is not null then
    raise exception '347: % still refuses a non-product choice group', v_left;
  end if;
  raise notice '347: the till accepts product, voucher, therapy, credit-package and promotion choices';
end $$;

notify pgrst, 'reload schema';
commit;
