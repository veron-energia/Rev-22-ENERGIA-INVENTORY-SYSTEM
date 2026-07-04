-- =====================================================================
-- ENERGIA — FIX: listed choice-group options must never pay a top-up
--
-- Bug: the top-up was charged to ANY chosen product priced above the
-- group's baseline, including the group's own listed options. Correct
-- rule (per spec): every LISTED option is covered by the bundle price,
-- whatever its individual price. Only products OUTSIDE the listed
-- options pay (price − baseline), where baseline = the cheapest listed
-- option at the invoice's store. Cheaper outside picks pay nothing.
--
-- Run this whole file once (safe to re-run). Already-created invoices
-- are not modified.
-- =====================================================================

create or replace function public.promotion_selections_topup(
  p_promotion_id uuid, p_store_id uuid, p_selections jsonb
) returns numeric language plpgsql stable security definer set search_path = public as $$
declare
  v_grp record; v_sel jsonb; v_opt jsonb; v_baseline numeric; v_price numeric;
  v_topup numeric := 0; v_qty integer;
begin
  for v_grp in select * from public.promotion_choice_groups
    where promotion_id = p_promotion_id and item_kind = 'product'
  loop
    select min(spp.selling_price) into v_baseline
    from public.promotion_choice_options o
    join public.store_product_prices spp
      on spp.product_id = o.product_id and spp.store_id = p_store_id
     and spp.is_active = true and spp.deleted_at is null
    where o.group_id = v_grp.id and o.product_id is not null;

    if v_baseline is null then continue; end if;

    for v_sel in select * from jsonb_array_elements(coalesce(p_selections,'[]'::jsonb))
    loop
      if (v_sel->>'group_id')::uuid <> v_grp.id then continue; end if;
      for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
      loop
        v_qty := coalesce((v_opt->>'quantity')::integer,0);
        if v_qty <= 0 or (v_opt->>'product_id') is null then continue; end if;
        -- Listed options never pay a top-up.
        if exists (
          select 1 from public.promotion_choice_options o
          where o.group_id = v_grp.id and o.product_id = (v_opt->>'product_id')::uuid
        ) then continue; end if;
        select selling_price into v_price from public.store_product_prices
          where store_id = p_store_id and product_id = (v_opt->>'product_id')::uuid
            and is_active = true and deleted_at is null;
        if v_price is not null and v_price > v_baseline then
          v_topup := v_topup + (v_price - v_baseline) * v_qty;
        end if;
      end loop;
    end loop;
  end loop;
  return round(v_topup, 2);
end; $$;

notify pgrst, 'reload schema';
