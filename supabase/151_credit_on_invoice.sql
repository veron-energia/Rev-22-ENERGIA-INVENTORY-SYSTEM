-- =====================================================================
-- ENERGIA — PHASE 31: CREDIT PACKAGES & PREMIUM BUNDLES ARE BOUGHT ON
--                     A NORMAL INVOICE (New Invoice → Items)
--
-- Until now a Credit Package or Premium Bundle was sold through the
-- dedicated create_credit_purchase_invoice() RPC (the "Buy Credit"
-- modal). They are now ordinary, non-stock invoice line kinds selected
-- inside the normal New Invoice screen, so a single invoice may mix a
-- product, a voucher, a credit package and a premium bundle, is served
-- by the invoice-level "Served by" staff, and pays through the normal
-- payment flow.
--
-- Design: rather than rewrite create_invoice / update_invoice (already
-- assembled by successive pg_get_functiondef patches — see 99 and 106),
-- this migration injects two new branches into each of their two loops
-- (pricing + insert), reusing the EXACT snapshot and validation logic
-- from create_credit_purchase_invoice (migration 81). The lines it
-- writes are byte-for-byte the same shape the old RPC produced, so:
--   * the paid-invoice trigger (trg_create_therapy_on_paid) still issues
--     Paid Credit / Bonus Credit / reward vouchers exactly once, only
--     when the invoice becomes paid or Completed FOC (issue_credit_lines_
--     for_invoice keys off line_kind + credit_issued_at);
--   * the wallet-credit block trigger (block_wallet_credit_on_credit_lines)
--     still refuses wallet payment on any invoice carrying such a line;
--   * earn_invoice_commission still skips them (migration 81 patch), and
--     the package/bundle functions book their own commission on external
--     money only.
--
-- Nothing here rebuilds the wallet. create_credit_purchase_invoice is
-- kept for backward compatibility but is no longer used by the UI.
--
-- Additive and idempotent. Run AFTER 150.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Teach create_invoice / update_invoice the two credit line kinds.
--
--    Each function loops TWICE over p_items: once to validate + price,
--    once to insert. The product branch marker (`v_else`) is textually
--    identical in both, so the definition is split at the SECOND loop
--    marker and each half patched with what it actually needs — the same
--    technique migration 106 used for special products and rentals.
--
--    Reuses only variables already declared in both functions
--    (v_kind, v_qty, v_product_id, v_price, v_gross, v_line_total,
--    v_sel, v_pj, v_invoice_id), so no declare-block surgery is needed.
-- ---------------------------------------------------------------------
do $patch$
declare
  v_name text; v_def text; v_head text; v_tail text; v_new text;
  v_split integer; v_marker text; v_else text; v_store text;
begin
  v_else   := '    else' || chr(10) || '      v_product_id := (v_item->>''product_id'')::uuid;';
  v_marker := 'v_kind := coalesce(v_item->>''kind'',''product'');';

  foreach v_name in array array['create_invoice','update_invoice'] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_name;
    if v_def is null then
      raise notice '% not found — skipping', v_name; continue;
    end if;
    if position('credit_package_id'')::uuid' in v_def) > 0 then
      raise notice '% already handles credit packages and premium bundles', v_name; continue;
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
      raise exception 'Could not add the credit line kinds to % — its item loop was not in the expected shape', v_name;
    end if;
    if position('''credit_package'',''premium_bundle'') then' in v_new) = 0 then
      raise warning '% : credit lines were added but the third-party/voucher exclusion guard was not found — check its item loop', v_name;
    end if;

    execute v_new;
    raise notice '% now prices and records credit packages and premium bundles', v_name;
  end loop;
end $patch$;

-- ---------------------------------------------------------------------
-- 2. Protect a PAID credit line from the correction flow.
--
--    edit_paid_invoice() sets the invoice back to 'unpaid', rebuilds
--    every line through update_invoice (which deletes and re-inserts
--    them, clearing credit_issued_at), then re-settles it — which would
--    issue the credit a SECOND time and create duplicate wallet lots
--    without reversing the first. Since the correction mechanism cannot
--    safely unwind already-issued credit, refuse the whole correction
--    when the invoice carries a credit line and point the user at a
--    refund instead. Ordinary invoices are unaffected.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'edit_paid_invoice';
  if v_def is null then
    raise notice 'edit_paid_invoice not found — skipping'; return;
  end if;
  if position('cannot be corrected here once paid' in v_def) > 0 then
    raise notice 'edit_paid_invoice already guards credit lines'; return;
  end if;

  v_new := replace(v_def,
    '  v_old_total := coalesce(v_inv.total_amount, 0);',
       '  -- A paid Credit Package / Premium Bundle has already issued its' || chr(10)
    || '  -- credit and wallet lots; the correction flow cannot unwind those' || chr(10)
    || '  -- safely, so it is refused rather than allowed to double-issue.' || chr(10)
    || '  if exists (select 1 from public.invoice_items ii' || chr(10)
    || '              where ii.invoice_id = p_invoice_id' || chr(10)
    || '                and ii.line_kind in (''credit_package'',''premium_bundle'')) then' || chr(10)
    || '    raise exception ''This invoice contains a Credit Package or Premium Bundle, which cannot be corrected here once paid — its credit has already been issued. Refund the invoice instead.'';' || chr(10)
    || '  end if;' || chr(10)
    || '  v_old_total := coalesce(v_inv.total_amount, 0);');

  if position('cannot be corrected here once paid' in v_new) = 0 then
    raise exception 'Could not add the credit-line guard to edit_paid_invoice — anchor not found';
  end if;
  execute v_new;
  raise notice 'edit_paid_invoice now refuses to corrupt paid credit lines';
end $patch$;

-- ---------------------------------------------------------------------
-- 3. The dedicated credit-purchase RPC is now legacy. The UI no longer
--    calls it; create_invoice / update_invoice handle these lines. It is
--    kept so historical callers and any external integration keep working.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname='public' and p.proname='create_credit_purchase_invoice') then
    comment on function public.create_credit_purchase_invoice(uuid, uuid, jsonb, uuid, numeric, text)
      is 'DEPRECATED (Phase 31): Credit Packages and Premium Bundles are now bought directly on a normal invoice via create_invoice/update_invoice. Retained only for backward compatibility; the UI no longer depends on it.';
  end if;
end $$;

notify pgrst, 'reload schema';
