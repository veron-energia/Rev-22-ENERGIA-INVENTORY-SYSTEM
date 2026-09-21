begin;
-- =====================================================================
-- A CHOICE IS RECORDED, WHATEVER WAS CHOSEN
--
-- 346 let a choice group offer therapy, credit packages and promotions, and 347
-- taught the till to VALIDATE a pick of any of those kinds. Neither taught it to
-- STORE one.
--
-- invoice_promotion_selections holds (invoice_item_id, group_id, product_id,
-- voucher_id, quantity, therapy_package_id) — and both writers use the column
-- list (invoice_item_id, group_id, product_id, voucher_id, quantity). So
-- therapy_package_id has never been written despite existing since 121, and
-- credit_package_id and child_promotion_id have no column at all.
--
-- The effect, had anyone sold one: the cashier picks a promotion, the pick
-- passes validation, and the row that records it has group_id and a quantity
-- with every item column null. What the customer chose is simply not written
-- down. Nothing raises. Reprinting the document would not show it, a correction
-- could not restore it — the reload path skips a row with no product or voucher
-- — and the chosen item contributes nothing to the stock components captured
-- from selections.
--
-- Nobody has sold one: 55 selection rows exist on production, all product or
-- voucher, none against a group of a new kind. This closes the hole before it
-- is reached rather than after.
-- =====================================================================
alter table public.invoice_promotion_selections
  add column if not exists credit_package_id uuid references public.credit_packages(id);
alter table public.invoice_promotion_selections
  add column if not exists child_promotion_id uuid references public.promotions(id);

-- A recorded choice must actually name something. Written as NOT VALID so the
-- 55 existing rows, which all name a product or a voucher, are not re-checked;
-- they satisfy it anyway, and this keeps the migration off the table's data.
alter table public.invoice_promotion_selections
  drop constraint if exists invoice_promotion_selections_names_one;
alter table public.invoice_promotion_selections
  add constraint invoice_promotion_selections_names_one check (
    (product_id is not null)::int + (voucher_id is not null)::int
  + (therapy_package_id is not null)::int + (credit_package_id is not null)::int
  + (child_promotion_id is not null)::int = 1
  ) not valid;

do $$
declare
  f record; v_src text; v_new text; v_fixed int := 0; v_names text := '';
  v_anchor constant text :=
'          insert into public.invoice_promotion_selections (invoice_item_id, group_id, product_id, voucher_id, quantity)
          values (v_item_id, v_sel_group,
                  nullif(v_opt->>''product_id'','''')::uuid, nullif(v_opt->>''voucher_id'','''')::uuid,
                  (v_opt->>''quantity'')::integer);';
  v_fix constant text :=
'          -- Every kind a choice group may offer, not just the two it began
          -- with. A pick that is not written down is a pick the shop cannot
          -- reprint, correct, or count stock against.
          insert into public.invoice_promotion_selections (invoice_item_id, group_id, product_id, voucher_id,
                                                           therapy_package_id, credit_package_id, child_promotion_id, quantity)
          values (v_item_id, v_sel_group,
                  nullif(v_opt->>''product_id'','''')::uuid, nullif(v_opt->>''voucher_id'','''')::uuid,
                  nullif(v_opt->>''therapy_package_id'','''')::uuid, nullif(v_opt->>''credit_package_id'','''')::uuid,
                  nullif(v_opt->>''child_promotion_id'','''')::uuid,
                  (v_opt->>''quantity'')::integer);';
begin
  for f in
    select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.prosrc like '%insert into public.invoice_promotion_selections%'
     order by p.proname
  loop
    v_src := pg_get_functiondef(f.oid);
    if v_src like '%child_promotion_id, quantity)%' then continue; end if;
    if position(v_anchor in v_src) = 0 then
      raise exception '349: % writes a selection in a shape this migration does not recognise; add the columns by hand', f.proname;
    end if;
    v_new := replace(v_src, v_anchor, v_fix);
    execute v_new;
    v_fixed := v_fixed + 1;
    v_names := v_names || f.proname || ' ';
  end loop;

  if v_fixed = 0 then
    raise notice '349: every writer already records the chosen item (already applied)';
  else
    raise notice '349: % function(s) now record what was chosen, whatever kind it is: %', v_fixed, v_names;
  end if;
end $$;

do $$
declare v_left text := '';
begin
  select string_agg(p.proname, ', ') into v_left
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
     and p.prosrc like '%insert into public.invoice_promotion_selections%'
     and p.prosrc not like '%child_promotion_id, quantity)%';
  if v_left is not null then
    raise exception '349: % still records only a product or a voucher', v_left;
  end if;
  raise notice '349: a choice of any kind is written down';
end $$;

notify pgrst, 'reload schema';
commit;
