begin;
-- =====================================================================
-- SINGLE-CUSTOMER CREDIT PACKAGES AND PREMIUM BUNDLES COULD NOT BE SOLD
--
-- Reported: creating either from the invoice screen with "Single Customer"
-- fails with
--     No price set for "<NULL>" in this store
-- while "Split Across Customers" works.
--
-- The message is the ordinary PRODUCT pricing branch of create_invoice,
-- reached because the line's kind matched none of the known branches. It then
-- read product_id, which a package line does not carry, and the name of a NULL
-- product renders as <NULL>.
--
-- WHY that branch was reachable, confirmed by reading the live catalogue
-- read-only rather than assuming:
--
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   8 args
--     the one create_invoice_with_details actually calls.
--     credit_package branch: ABSENT.   premium_bundle branch: ABSENT.
--
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)         7 args
--     an old overload nothing calls.
--     credit_package branch: present.  premium_bundle branch: present.
--
-- Migration 151, which added those branches, selected the function to patch by
-- NAME only:
--
--     select pg_get_functiondef(p.oid) into v_def
--       from pg_proc p ... where p.proname = v_name;
--
-- With two overloads installed that reads an arbitrary row. In this database
-- it read the 7-argument overload, patched that, and reported success, while
-- the function the application actually calls never gained the branches. A
-- clean install has only one overload, which is why every test environment
-- passes and only the live database fails -- and why the defect survived.
--
-- Split Across Customers was unaffected because it does not go through
-- create_invoice at all: it calls create_split_credit_package_invoices.
--
-- This re-runs 151's patch, unchanged in what it inserts, over EVERY overload
-- of create_invoice and update_invoice, skipping any that already has the
-- branches and any whose item loop is not in the expected shape. It is the
-- same defensive loop migration 244 adopted after the identical trap.
--
-- No catalogue, price, invoice or benefit record is touched.
-- Idempotent: re-running reports "already handles" and changes nothing.
-- =====================================================================

create or replace function public.repair_create_invoice_package_branches()
returns jsonb language plpgsql as $patch$
declare
  r record; v_patched integer := 0; v_already integer := 0; v_skipped integer := 0;
  v_name text; v_def text; v_head text; v_tail text; v_new text;
  v_split integer; v_marker text; v_else text; v_store text;
begin
  v_else   := '    else' || chr(10) || '      v_product_id := (v_item->>''product_id'')::uuid;';
  v_marker := 'v_kind := coalesce(v_item->>''kind'',''product'');';

  for r in
    select p.oid, p.proname, p.oid::regprocedure::text as sig, pg_get_functiondef(p.oid) as def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.proname in ('create_invoice','update_invoice')
     order by p.oid
  loop
    v_name := r.proname; v_def := r.def;
    if position('credit_package_id'')::uuid' in v_def) > 0 then
      v_already := v_already + 1;
      raise notice '% already handles credit packages and premium bundles', r.sig; continue;
    end if;
    if position(v_else in v_def) = 0 or position(v_marker in v_def) = 0 then
      -- An overload whose item loop is not in the expected shape. Left alone;
      -- guessing where to insert a pricing branch would mis-price invoices.
      v_skipped := v_skipped + 1;
      raise notice 'left unchanged (item loop not in the expected shape): %', r.sig; continue;
    end if;

    -- The store the line is snapshotted against: the argument in
    -- create_invoice, the locked original in update_invoice.
    v_store := case when v_name = 'create_invoice' then 'p_store_id' else 'v_old.store_id' end;

    -- Split at the SECOND occurrence of the loop marker (the insert loop).
    v_split := position(v_marker in substr(v_def, position(v_marker in v_def) + length(v_marker)))
               + position(v_marker in v_def) + length(v_marker) - 1;
    v_head := substr(v_def, 1, v_split - 1);
    v_tail := substr(v_def, v_split);

    -- ---- PASS 1 (pricing + validation) : compute v_gross ----
    v_head := replace(v_head, v_else,
         '    elsif v_kind = ''credit_package'' then' || chr(10)
      || '      if v_qty <> 1 then raise exception ''A credit package line must have quantity 1''; end if;' || chr(10)
      || '      v_product_id := (v_item->>''credit_package_id'')::uuid;' || chr(10)
      || '      if not exists (select 1 from public.credit_packages where id = v_product_id and deleted_at is null) then' || chr(10)
      || '        raise exception ''Credit package not found''; end if;' || chr(10)
      || '      if not exists (select 1 from public.credit_packages_for_store(' || v_store || ') x where x.id = v_product_id) then' || chr(10)
      || '        raise exception ''Credit package "%" is not available at this store'',' || chr(10)
      || '          (select name from public.credit_packages where id = v_product_id); end if;' || chr(10)
      || '      select customer_price into v_price from public.credit_packages where id = v_product_id;' || chr(10)
      || '      v_gross := v_price * v_qty;' || chr(10)
      || chr(10)
      || '    elsif v_kind = ''premium_bundle'' then' || chr(10)
      || '      if v_qty <> 1 then raise exception ''A premium bundle line must have quantity 1''; end if;' || chr(10)
      || '      v_product_id := (v_item->>''premium_bundle_id'')::uuid;' || chr(10)
      || '      if not exists (select 1 from public.premium_bundles where id = v_product_id and deleted_at is null) then' || chr(10)
      || '        raise exception ''Premium bundle not found''; end if;' || chr(10)
      || '      if not exists (select 1 from public.premium_bundles_for_store(' || v_store || ') x where x.id = v_product_id) then' || chr(10)
      || '        raise exception ''Premium bundle "%" is not available at this store'',' || chr(10)
      || '          (select name from public.premium_bundles where id = v_product_id); end if;' || chr(10)
      || '      v_sel := coalesce(v_item->''voucher_selection'', ''[]''::jsonb);' || chr(10)
      || '      v_pj := public.validate_bundle_voucher_selection(v_product_id, ' || v_store || ', v_sel);' || chr(10)
      || '      if not (v_pj->>''complete'')::boolean then' || chr(10)
      || '        raise exception ''Select exactly % reward voucher(s) for "%" — % chosen'',' || chr(10)
      || '          v_pj->>''required_qty'',' || chr(10)
      || '          (select name from public.premium_bundles where id = v_product_id),' || chr(10)
      || '          v_pj->>''selected_qty''; end if;' || chr(10)
      || '      if not (v_pj->>''stock_ok'')::boolean then' || chr(10)
      || '        raise exception ''Not enough voucher stock for "%": %'',' || chr(10)
      || '          (select name from public.premium_bundles where id = v_product_id),' || chr(10)
      || '          array_to_string(array(select jsonb_array_elements_text(v_pj->''shortages'')), ''; ''); end if;' || chr(10)
      || '      select customer_payment_amount into v_price from public.premium_bundles where id = v_product_id;' || chr(10)
      || '      v_gross := v_price * v_qty;' || chr(10)
      || chr(10) || v_else);

    -- ---- PASS 2 (insert) : write the line with its permanent snapshots ----
    v_tail := replace(v_tail, v_else,
         '    elsif v_kind = ''credit_package'' then' || chr(10)
      || '      v_product_id := (v_item->>''credit_package_id'')::uuid;' || chr(10)
      || '      select customer_price into v_price from public.credit_packages where id = v_product_id;' || chr(10)
      || '      v_line_total := round(v_price * v_qty, 2);' || chr(10)
      || '      insert into public.invoice_items' || chr(10)
      || '        (invoice_id, line_kind, quantity, unit_price, line_total, price_source, price_source_id,' || chr(10)
      || '         store_id_snapshot, original_price, credit_package_id,' || chr(10)
      || '         credit_paid_snapshot, credit_voucher_qty_snapshot, plan_name_snapshot)' || chr(10)
      || '      select v_invoice_id, ''credit_package''::public.invoice_line_kind, 1, v_price, v_line_total, ''credit_package'', v_product_id,' || chr(10)
      || '             ' || v_store || ', v_price, v_product_id, pk.paid_credit_amount, null, pk.name' || chr(10)
      || '        from public.credit_packages pk where pk.id = v_product_id;' || chr(10)
      || chr(10)
      || '    elsif v_kind = ''premium_bundle'' then' || chr(10)
      || '      v_product_id := (v_item->>''premium_bundle_id'')::uuid;' || chr(10)
      || '      v_sel := coalesce(v_item->''voucher_selection'', ''[]''::jsonb);' || chr(10)
      || '      select customer_payment_amount into v_price from public.premium_bundles where id = v_product_id;' || chr(10)
      || '      v_line_total := round(v_price * v_qty, 2);' || chr(10)
      || '      insert into public.invoice_items' || chr(10)
      || '        (invoice_id, line_kind, quantity, unit_price, line_total, price_source, price_source_id,' || chr(10)
      || '         store_id_snapshot, original_price, premium_bundle_id,' || chr(10)
      || '         credit_paid_snapshot, credit_bonus_snapshot, credit_voucher_qty_snapshot,' || chr(10)
      || '         bundle_voucher_selection, plan_name_snapshot)' || chr(10)
      || '      select v_invoice_id, ''premium_bundle''::public.invoice_line_kind, 1, v_price, v_line_total, ''premium_bundle'', v_product_id,' || chr(10)
      || '             ' || v_store || ', v_price, v_product_id, b.paid_credit_amount, b.bonus_credit_amount,' || chr(10)
      || '             b.free_voucher_qty, v_sel, b.name' || chr(10)
      || '        from public.premium_bundles b where b.id = v_product_id;' || chr(10)
      || chr(10) || v_else);

    v_new := v_head || v_tail;

    -- Credit lines are non-stock: they must skip the third-party and
    -- per-line voucher rules (those set/read v_ptype, which is a product
    -- concept). Extend whichever exclusion guard this build already has.
    v_new := replace(v_new,
      'if v_kind not in (''promotion'',''voucher'',''therapy'',''special_product'',''rental'') then',
      'if v_kind not in (''promotion'',''voucher'',''therapy'',''special_product'',''rental'',''credit_package'',''premium_bundle'') then');
    -- Fallback for a build where special products / rentals were never added.
    if position('''credit_package'',''premium_bundle'') then' in v_new) = 0 then
      v_new := replace(v_new,
        'if v_kind not in (''promotion'',''voucher'',''therapy'') then',
        'if v_kind not in (''promotion'',''voucher'',''therapy'',''credit_package'',''premium_bundle'') then');
    end if;

    if position('credit_package_id'')::uuid' in v_new) = 0 then
      raise exception 'Could not add the credit line kinds to % — its item loop was not in the expected shape', r.sig;
    end if;
    if position('''credit_package'',''premium_bundle'') then' in v_new) = 0 then
      raise warning '% : credit lines were added but the third-party/voucher exclusion guard was not found — check its item loop', r.sig;
    end if;

    execute v_new;
    v_patched := v_patched + 1;
    raise notice 'now prices and records credit packages and premium bundles: %', r.sig;
  end loop;

  if v_patched = 0 and v_already = 0 then
    raise exception 'No create_invoice/update_invoice overload could be given the credit line kinds';
  end if;
  return jsonb_build_object('patched',v_patched,'already_correct',v_already,'left_unchanged',v_skipped);
end $patch$;

comment on function public.repair_create_invoice_package_branches() is
 'Gives every create_invoice/update_invoice overload the credit-package and premium-bundle branches. Safe to re-run: an overload that already has them is reported and left alone.';
-- Deliberately granted to nobody: this rewrites functions and is an operator
-- action, not something the application may call.
revoke all on function public.repair_create_invoice_package_branches() from public;

do $run$
declare r jsonb;
begin
  r := public.repair_create_invoice_package_branches();
  raise notice '302: % overload(s) patched, % already correct, % left unchanged',
    r->>'patched', r->>'already_correct', r->>'left_unchanged';
end $run$;


notify pgrst,'reload schema';
commit;
