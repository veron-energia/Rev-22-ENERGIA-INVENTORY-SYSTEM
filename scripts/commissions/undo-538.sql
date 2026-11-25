-- UNDO of 538 (with the user's go-ahead). It puts the five functions 538 patched back exactly as
-- they were before 538 (md5s below), by taking 538's text out again; drops the seven functions 538
-- made (invoice_line_kinds_for, invoice_has_unkept_line_kinds, record_invoice_line_kinds,
-- invoice_commission_correction_apply, invoice_commission_kept_basis,
-- preview_invoice_commission_correction, correct_invoice_commission_basis) and the table
-- public.invoice_line_commission_kinds. Afterwards every invoice line is worked out again at its
-- product's type as it is then (a product's type changed and a later correction re-price an old
-- invoice, the security audit's M12 by that road open again), and the Owner's correction window
-- has nothing to call: put back the pages of before 538 first.
--
-- WHAT HAPPENS TO THE KEPT KINDS: the table is dropped with every kind it holds (the backfilled
-- ones and the ones kept since). It says how many, and how many product lines keep a kind other
-- than their product's type then: those lines would be re-priced at their next correction.
-- Commission rows already written keep their amounts; nothing is worked out again here.
--
-- Run it before scripts/commissions/undo-535.sql (which refuses while 538 uses its table and
-- helpers). It refuses, with nothing changed, unless each of the five functions and the seven new
-- ones is exactly 538's, the table is 538's, no other function uses them, and the grants are as
-- tested. One transaction, all or nothing; it waits at most 5 seconds for a lock. The 538 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row or record
-- this UNDO beside it.
do $undo$
declare
  c_sig constant text[] := array[
    'earn_invoice_commission(uuid)',
    'invoice_affiliate_commission_preview(uuid)',
    'earn_credit_package_commission(uuid)',
    'earn_premium_bundle_commission(uuid)',
    'sync_instalment_commissions(uuid,text,date,boolean,boolean)'];
  c_before constant text[] := array[
    '762c06868e2c2256f008b9468b8a255b',
    '927b9e2129e354c0f061a713083cdb54',
    '44d10e4bcceb9a94080f1802c1da946f',
    '86ea3b1215ed6fd896bfd63ceba21152',
    '98fbe647100e8890957f098c6d90fca4'];
  c_538 constant text[] := array['8d7ccdee4eae2359b56995ebf60dbcfa', 'df92dacb660319a7c4ae44b439b1adaf', 'd2d6c3a32c89a329852d2680aa66e504', '5bb0f5bf338a73f4b040dac2cf9e905c', '1f56177897bb6b67c276626128184c86'];
  c_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_new_sig constant text[] := array[
    'invoice_line_kinds_for(uuid)',
    'invoice_has_unkept_line_kinds(uuid)',
    'record_invoice_line_kinds(uuid,jsonb)',
    'invoice_commission_correction_apply(uuid,jsonb,jsonb,text)',
    'invoice_commission_kept_basis(uuid)',
    'preview_invoice_commission_correction(uuid,jsonb,jsonb)',
    'correct_invoice_commission_basis(uuid,jsonb,jsonb,text,uuid)'];
  c_new_md5 constant text[] := array['bb51dfc8861272bc615dd0630f2a9acf', 'c290de63f7dafbee0ac84cfd7c3260a8', '125d4d8fd4311f4b6683e73a99f03425', '7eef1a9a0af66041c3c9fda94a168f09', '744568fa22216bd52b92810e46a82165', '96d01915bbf6787d773ece636fb654cf', '4e8433353b98a5b824e00b39eda11c18'];
  c_table_comment constant text :=
    '538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line''s type"): the commission kind each '
    'invoice line first earned as (own, third_party, no_commission; a promotion line''s own and third-party values), kept '
    'by record_invoice_line_kinds and read by invoice_line_kinds_for in earn_invoice_commission and the part-payment '
    'preview. backfilled: kept by 538 for an invoice with kept rates (535). Corrected only by an Owner '
    '(correct_invoice_commission_basis). No login reads or writes it.';
  c_fn constant int[] := array[1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 1, 3, 4, 3, 4, 5];
  c_anchor constant text[] := array[
$a$  v_machine_new boolean;  -- 489
$a$,
$a$  v_machine_new boolean;  -- 489
$a$,
$a$    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
$a$,
$a$    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
$a$,
$a$  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join public.products p on p.id = ii.product_id
  left join public.special_products sp on sp.id = ii.special_product_id
  left join public.products mp on mp.id = sp.product_id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and p.product_type::text = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental')
             and coalesce(mp.product_type::text, 'own') = 'third_party');
$a$,
$a$  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join public.products p on p.id = ii.product_id
  left join public.special_products sp on sp.id = ii.special_product_id
  left join public.products mp on mp.id = sp.product_id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and p.product_type::text = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental')
             and coalesce(mp.product_type::text, 'own') = 'third_party');
$a$,
$a$    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           case when v_machine_new and ii.line_kind in ('special_product','rental')
                then coalesce(mp.product_type::text, 'own')
                else coalesce(p.product_type::text, 'own') end as ptype,
           coalesce((select sum(a.amount - a.reversed_amount)
                       from public.invoice_line_credit_allocations a
                      where a.invoice_item_id = ii.id), 0) as wallet_funded
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    left join public.special_products sp on sp.id = ii.special_product_id
    left join public.products mp on mp.id = sp.product_id
    where ii.invoice_id = p_invoice_id
      and ii.line_kind not in ('credit_package','premium_bundle')
      and ii.line_kind::text <> 'late_fee'  -- 396: a rental's late fee earns none
      and case when v_machine_new and ii.line_kind in ('special_product','rental')
               then coalesce(mp.product_type::text, 'own')
               else coalesce(p.product_type::text, 'own') end <> 'no_commission'
$a$,
$a$    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           case when v_machine_new and ii.line_kind in ('special_product','rental')
                then coalesce(mp.product_type::text, 'own')
                else coalesce(p.product_type::text, 'own') end as ptype,
           coalesce((select sum(a.amount - a.reversed_amount)
                       from public.invoice_line_credit_allocations a
                      where a.invoice_item_id = ii.id), 0) as wallet_funded
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    left join public.special_products sp on sp.id = ii.special_product_id
    left join public.products mp on mp.id = sp.product_id
    where ii.invoice_id = p_invoice_id
      and ii.line_kind not in ('credit_package','premium_bundle')
      and ii.line_kind::text <> 'late_fee'  -- 396: a rental's late fee earns none
      and case when v_machine_new and ii.line_kind in ('special_product','rental')
               then coalesce(mp.product_type::text, 'own')
               else coalesce(p.product_type::text, 'own') end <> 'no_commission'
$a$,
$a$      select
        coalesce(sum(case when ptype = 'third_party' then 0 else original_value end),0),
        coalesce(sum(case when ptype = 'third_party' then original_value else 0 end),0)
        into v_own_orig, v_third_orig
      from public.promotion_commission_items(v_item.promotion_id, v_inv.store_id, v_item.quantity, v_item.price_mode);

      select
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') <> 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          when s.voucher_id is not null
            then coalesce(vsp.selling_price, vv.selling_price, 0) * s.quantity
          else 0 end),0),
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') = 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          else 0 end),0)
        into v_sel_own, v_sel_third
      from public.invoice_promotion_selections s
      left join public.products pp on pp.id = s.product_id
      left join public.store_product_prices spp on spp.store_id = v_inv.store_id and spp.product_id = s.product_id
        and spp.is_active = true and spp.deleted_at is null
      left join public.vouchers vv on vv.id = s.voucher_id
      left join public.voucher_store_prices vsp on vsp.store_id = v_inv.store_id and vsp.voucher_id = s.voucher_id
        and vsp.deleted_at is null
      where s.invoice_item_id = v_item.id;
$a$,
$a$      select
        coalesce(sum(case when ptype = 'third_party' then 0 else original_value end),0),
        coalesce(sum(case when ptype = 'third_party' then original_value else 0 end),0)
        into v_own_orig, v_third_orig
      from public.promotion_commission_items(v_item.promotion_id, v_inv.store_id, v_item.quantity, v_item.price_mode);

      select
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') <> 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          when s.voucher_id is not null
            then coalesce(vsp.selling_price, vv.selling_price, 0) * s.quantity
          else 0 end),0),
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') = 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          else 0 end),0)
        into v_sel_own, v_sel_third
      from public.invoice_promotion_selections s
      left join public.products pp on pp.id = s.product_id
      left join public.store_product_prices spp on spp.store_id = v_inv.store_id and spp.product_id = s.product_id
        and spp.is_active = true and spp.deleted_at is null
      left join public.vouchers vv on vv.id = s.voucher_id
      left join public.voucher_store_prices vsp on vsp.store_id = v_inv.store_id and vsp.voucher_id = s.voucher_id
        and vsp.deleted_at is null
      where s.invoice_item_id = v_item.id;
$a$,
$a$  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id) then
    perform 1 from public.invoices i535 where i535.id = p_invoice_id for update;
$a$,
$a$    perform public.record_invoice_affiliate_rates(p_invoice_id, v_rate_t1_own, v_rate_t1_third,
      v_rate_t2_own, v_rate_t2_third);
$a$,
$a$  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
$a$,
$a$  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
$a$,
$a$    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
$a$,
$a$    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
$a$,
$a$     and not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id) then
    perform public.record_invoice_affiliate_rates(p_invoice_id, r535.tier1_own, r535.tier1_third,
              r535.tier2_own, r535.tier2_third)
       from public.invoice_affiliate_rates_for(p_invoice_id) r535;
$a$];
  c_new constant text[] := array[
$n$  v_machine_new boolean;  -- 489
  v538_kinds jsonb;  -- 538: each line's commission kind, kept or read now
$n$,
$n$  v_machine_new boolean;  -- 489
  v538_kinds jsonb;  -- 538: each line's commission kind, kept or read now
$n$,
$n$    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line's type"):
  -- each line's commission kind (own, third party, no commission; a special product's or a
  -- rental's machine; a promotion line's own and third-party values) is the one kept for it
  -- when the invoice first earned (invoice_line_commission_kinds), else read from the catalogue
  -- now, as before, and kept below once the invoice has a commission row. Read once, here, so
  -- what is kept is exactly what this run used.
  select coalesce(jsonb_agg(to_jsonb(k538)), '[]'::jsonb) into v538_kinds
    from public.invoice_line_kinds_for(p_invoice_id) k538;
$n$,
$n$    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line's type"):
  -- each line's commission kind (own, third party, no commission; a special product's or a
  -- rental's machine; a promotion line's own and third-party values) is the one kept for it
  -- when the invoice first earned (invoice_line_commission_kinds), else read from the catalogue
  -- now, as before, and kept below once the invoice has a commission row. Read once, here, so
  -- what is kept is exactly what this run used.
  select coalesce(jsonb_agg(to_jsonb(k538)), '[]'::jsonb) into v538_kinds
    from public.invoice_line_kinds_for(p_invoice_id) k538;
$n$,
$n$  -- 538: the line's kept kind (or its kind now) in place of the catalogue's.
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join jsonb_to_recordset(v538_kinds) as k538(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
    on k538.invoice_item_id = ii.id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and k538.kind = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental') and k538.kind = 'third_party');
$n$,
$n$  -- 538: the line's kept kind (or its kind now) in place of the catalogue's.
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join jsonb_to_recordset(v538_kinds) as k538(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
    on k538.invoice_item_id = ii.id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and k538.kind = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental') and k538.kind = 'third_party');
$n$,
$n$    -- 538: each line's kind (and a promotion line's own and third-party values) as kept, or now.
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           k538.kind as ptype, k538.own_value as own538, k538.third_value as third538,
           coalesce((select sum(a.amount - a.reversed_amount)
                       from public.invoice_line_credit_allocations a
                      where a.invoice_item_id = ii.id), 0) as wallet_funded
    from public.invoice_items ii
    join jsonb_to_recordset(v538_kinds) as k538(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
      on k538.invoice_item_id = ii.id
    where ii.invoice_id = p_invoice_id
      and ii.line_kind not in ('credit_package','premium_bundle')
      and ii.line_kind::text <> 'late_fee'  -- 396: a rental's late fee earns none
      and k538.kind <> 'no_commission'
$n$,
$n$    -- 538: each line's kind (and a promotion line's own and third-party values) as kept, or now.
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           k538.kind as ptype, k538.own_value as own538, k538.third_value as third538,
           coalesce((select sum(a.amount - a.reversed_amount)
                       from public.invoice_line_credit_allocations a
                      where a.invoice_item_id = ii.id), 0) as wallet_funded
    from public.invoice_items ii
    join jsonb_to_recordset(v538_kinds) as k538(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
      on k538.invoice_item_id = ii.id
    where ii.invoice_id = p_invoice_id
      and ii.line_kind not in ('credit_package','premium_bundle')
      and ii.line_kind::text <> 'late_fee'  -- 396: a rental's late fee earns none
      and k538.kind <> 'no_commission'
$n$,
$n$      -- 538: the promotion line's own and third-party values as kept, or worked out now from
      -- its items and choices as before (invoice_line_kinds_for).
      v_own_orig := coalesce(v_item.own538, 0); v_third_orig := coalesce(v_item.third538, 0);
      v_sel_own := 0; v_sel_third := 0;
$n$,
$n$      -- 538: the promotion line's own and third-party values as kept, or worked out now from
      -- its items and choices as before (invoice_line_kinds_for).
      v_own_orig := coalesce(v_item.own538, 0); v_third_orig := coalesce(v_item.third538, 0);
      v_sel_own := 0; v_sel_third := 0;
$n$,
$n$  -- 538: also until every line's kind is kept.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id)
     or public.invoice_has_unkept_line_kinds(p_invoice_id) then
    perform 1 from public.invoices i535 where i535.id = p_invoice_id for update;
$n$,
$n$    perform public.record_invoice_affiliate_rates(p_invoice_id, v_rate_t1_own, v_rate_t1_third,
      v_rate_t2_own, v_rate_t2_third);
    -- 538: and every line's kind, as this run used it (a line added later: its kind now).
    perform public.record_invoice_line_kinds(p_invoice_id, v538_kinds);
$n$,
$n$  -- 538: also until every line's kind is kept.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id)
     or public.invoice_has_unkept_line_kinds(s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
$n$,
$n$  -- 538: also until every line's kind is kept.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id)
     or public.invoice_has_unkept_line_kinds(s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
$n$,
$n$    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
    -- 538: and every line's kind on the invoice, as it is now where none is kept.
    perform public.record_invoice_line_kinds(s.invoice_id, null);
$n$,
$n$    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
    -- 538: and every line's kind on the invoice, as it is now where none is kept.
    perform public.record_invoice_line_kinds(s.invoice_id, null);
$n$,
$n$     -- 538: also the first time a line's kind is not kept yet (a line added later)
     and (not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id)
          or public.invoice_has_unkept_line_kinds(p_invoice_id)) then
    perform public.record_invoice_affiliate_rates(p_invoice_id, r535.tier1_own, r535.tier1_third,
              r535.tier2_own, r535.tier2_third)
       from public.invoice_affiliate_rates_for(p_invoice_id) r535;
    -- 538: and every line's kind, as it is now where none is kept; the targets are read again below.
    perform public.record_invoice_line_kinds(p_invoice_id, null);
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[5]);
  v_n int; v_back int; v_differ int;
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      raise exception 'undo 538: public.% is missing. Nothing was changed.', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_before[i] then
      raise exception 'undo 538: public.% is already its version of before 538; 538 is not in. Nothing was changed.', c_sig[i]; end if;
    if md5(d) <> c_538[i] then
      raise exception 'undo 538: public.% is not 538''s version (md5 %). Nothing was changed.', c_sig[i], md5(d); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception 'undo 538: the grants of public.% are not the tested ones. Nothing was changed.', c_sig[i]; end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception 'undo 538: public.% is missing or not 538''s. Nothing was changed.', c_new_sig[i]; end if;
  end loop;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
     and p.oid not in (select to_regprocedure('public.' || x) from unnest(c_sig || c_new_sig) x)
     and pg_get_functiondef(p.oid) ~ 'invoice_line_commission_kinds|invoice_line_kinds_for|invoice_has_unkept_line_kinds|record_invoice_line_kinds|invoice_commission_correction_apply|invoice_commission_kept_basis|preview_invoice_commission_correction|correct_invoice_commission_basis';
  if d is not null then
    raise exception 'undo 538: 538''s table or functions are also used by %. Nothing was changed.', d; end if;
  if to_regclass('public.invoice_line_commission_kinds') is null
     or obj_description(to_regclass('public.invoice_line_commission_kinds'), 'pg_class') is distinct from c_table_comment then
    raise exception 'undo 538: public.invoice_line_commission_kinds is missing or not 538''s. Nothing was changed.'; end if;
  for i in reverse cardinality(c_fn) .. 1 loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'undo 538: 538''s text % is not found exactly once in public.%. Nothing was changed.', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'undo 538: public.% without 538''s text is not its version of before 538 (md5 %). Nothing was changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- What is dropped with the table
  select count(*), count(*) filter (where k.backfilled),
         count(*) filter (where ii.line_kind::text = 'product' and k.kind is distinct from coalesce(p.product_type::text, 'own'))
    into v_n, v_back, v_differ
    from public.invoice_line_commission_kinds k
    join public.invoice_items ii on ii.id = k.invoice_item_id
    left join public.products p on p.id = ii.product_id;
  raise notice 'undo 538: dropping the kept kinds of % line(s) (% backfilled by 538, % kept since); % product line(s) keep a kind other than their product''s type now and would be re-priced at their next correction, reconcile or part payment.',
    v_n, v_back, v_n - v_back, v_differ;

  -- 2. Put back
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in reverse cardinality(c_new_sig) .. 1 loop
    execute format('drop function public.%s', c_new_sig[i]);
  end loop;
  drop table public.invoice_line_commission_kinds;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception 'undo 538: public.% is not as before 538 after putting it back', c_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
