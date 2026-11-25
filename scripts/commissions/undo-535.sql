-- UNDO of 535 (with the user's go-ahead). It puts the ten functions 535 patched back exactly as
-- they were before 535 (md5s below), by taking 535's text out again; drops the two helpers 535
-- made (invoice_affiliate_rates_for, record_invoice_affiliate_rates), the seventeen constraints on the
-- packages', bundles', their sales' and the settings' rates, the three audit triggers
-- (audit_direct_change on app_settings, credit_packages and premium_bundles) and the table public.invoice_affiliate_rates; and grants
-- EXECUTE on apply_commission_rebase_all() and set_staff_commission_rate(numeric) to
-- authenticated again. Afterwards a Manager can again change the four commission rates, every
-- invoice is worked out at the current rates on its next correction, reconcile or part payment
-- (an invoice re-priced after a rate change), a package's or bundle's own rates take any number
-- from anyone who manages packages and their audit row keeps only the name, and a signed-in
-- login can call the two closed functions straight (the security audit's M12 open again).
--
-- WHAT HAPPENS TO THE KEPT RATES: the table is dropped with every rate it holds, the backfilled
-- ones (535's own, the settings rates when 535 went in) and the ones kept since by invoices that
-- first earned while 535 was in. It says how many of each, and how many differ from the settings
-- now: those invoices are the ones the next correction would re-price. Commission rows already
-- written keep their amounts and their rate; nothing is worked out again here. If 535 is applied
-- again after this, its backfill gives every invoice with commission rows the settings of that
-- day (and refuses if a standing row carries another rate).
--
-- FIRST put back the pages of before 535 if they were changed for it.
--
-- A later migration that uses 535's helpers or reads invoice_affiliate_rates (538, say) must be
-- undone first: this refuses while another function does.
--
-- It refuses, with nothing changed, unless each of the ten functions and the two helpers is
-- exactly 535's (so a later version is never overwritten), no other function calls the helpers,
-- the table and the seventeen constraints are 535's, the grants are as tested, and the two closed functions' grants are 535's.
-- One transaction, all or nothing; it waits at most 5 seconds for a lock. The 535 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row (found by
-- its name, 535_only_an_owner_changes_commission_rates_and_an_invoice_keeps_its_own) or record
-- this UNDO beside it.
do $undo$
declare
  c_sig constant text[] := array[
    'set_commission_rates(numeric,numeric,numeric,numeric)',
    'earn_invoice_commission(uuid)',
    'earn_credit_package_commission(uuid)',
    'earn_premium_bundle_commission(uuid)',
    'invoice_affiliate_commission_preview(uuid)',
    'invoice_package_commission_preview(uuid)',
    'sync_instalment_commissions(uuid,text,date,boolean,boolean)',
    'upsert_credit_package(uuid,text,numeric,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,numeric,text,uuid[],uuid[],boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,numeric)',
    'upsert_premium_bundle(uuid,text,numeric,numeric,numeric,integer,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,text,uuid[],uuid[])',
    'trg_audit_direct_change()'];
  c_before constant text[] := array[
    'ce795196aaf6fadb1bfca52e2cafaa88',
    '40b040e35b23940bb19e14e53bdd4daa',
    'ad9bbf2183d6e19da85e7f59ce4a4b6e',
    '39429d3a496274811dce3c3f5f7ca29b',
    '072803880358cb84d7f148a06a27596e',
    '966e8b7166607aa1d986f20fbbbc1e52',
    '88d7b122778801a0d5eea0b6dd8395b7',
    'a2e8ec73a38b60ae7c05f573fba25ea8',
    '2202746851bc5bdd424c1c52fda86056',
    'b2ac8670825d1daf73a27c74e64bd66a'];
  c_535 constant text[] := array[
    '6f21984954600ef460aec9bdf4b4fdd2',
    '762c06868e2c2256f008b9468b8a255b',
    '44d10e4bcceb9a94080f1802c1da946f',
    '86ea3b1215ed6fd896bfd63ceba21152',
    '927b9e2129e354c0f061a713083cdb54',
    'ef34e72a6bffaebb33af83f2b38f2ade',
    '98fbe647100e8890957f098c6d90fca4',
    '51dfbba874668b8d0c75c3d72c859aab',
    'c08e7ed4eed6d8d5772dfcb2305439b6',
    '5dcea97b6479d9bb6a53adfa9dfbcba4'];
  -- Their grants, before and after (unchanged).
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres'];
  -- The two functions closed to logins, their md5s (unchanged) and their grants before.
  c_closed constant text[] := array[
    'apply_commission_rebase_all()',
    'set_staff_commission_rate(numeric)'];
  c_closed_md5 constant text[] := array[
    '48272cee4f2c9810d66b1e63d0cb8f97',
    '84a406c3d260930b444825f1f694b481'];
  c_closed_acl_before constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_new_sig constant text[] := array[
    'invoice_affiliate_rates_for(uuid)',
    'record_invoice_affiliate_rates(uuid,numeric,numeric,numeric,numeric)'];
  c_new_md5 constant text[] := array[
    '64e6ed85a8f169477fc85bd8452da453',
    'ae5132e23be0b0acbdec3d92e500bd4c'];
  -- The tables 532's trigger is attached to here, and the trigger as it must read.
  c_trg_table constant text[] := array['app_settings', 'credit_packages', 'premium_bundles'];
  c_trg_def constant text := 'CREATE TRIGGER audit_direct_change AFTER INSERT OR DELETE OR UPDATE ON public.%s FOR EACH ROW '
    || 'WHEN ((CURRENT_USER = ANY (ARRAY[''anon''::name, ''authenticated''::name, ''service_role''::name]))) '
    || 'EXECUTE FUNCTION trg_audit_direct_change()';
  c_table_comment constant text :=
    '535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026: "An invoice keeps the commission rates it first earned at"): '
    'the four affiliate commission rates (app_settings commission_tier1/2_own/third_rate) an invoice first earned at, kept '
    'by record_invoice_affiliate_rates and read by invoice_affiliate_rates_for in every function that works out affiliate '
    'commission. backfilled: kept by 535 for an invoice that had commission rows before it (the settings then). No login '
    'reads or writes it.';
  c_con_table constant text[] := array[
    'credit_packages', 'credit_packages', 'credit_packages',
    'premium_bundles', 'premium_bundles', 'premium_bundles',
    'credit_package_sales', 'credit_package_sales', 'credit_package_sales',
    'premium_bundle_sales', 'premium_bundle_sales', 'premium_bundle_sales',
    'app_settings', 'app_settings', 'app_settings', 'app_settings', 'app_settings'];
  c_con_col constant text[] := array[
    'tier1_rate', 'tier2_rate', 'staff_commission_rate',
    'tier1_rate', 'tier2_rate', 'staff_commission_rate',
    'tier1_rate_snapshot', 'tier2_rate_snapshot', 'staff_rate_snapshot',
    'tier1_rate_snapshot', 'tier2_rate_snapshot', 'staff_rate_snapshot',
    'commission_tier1_own_rate', 'commission_tier1_third_rate', 'commission_tier2_own_rate',
    'commission_tier2_third_rate', 'staff_commission_rate'];
  -- Twenty-one patches, each found exactly once in its function:
  --    1 set_commission_rates: Owner only
  --    2 earn_invoice_commission: the invoice's rates
  --    3 earn_invoice_commission: keep them once it has a row
  --    4 earn_credit_package_commission: its variables
  --    5 earn_credit_package_commission: the snapshot, else the invoice's rates
  --    6 earn_credit_package_commission: keep them with the tier 1 row
  --    7 earn_premium_bundle_commission: its variables
  --    8 earn_premium_bundle_commission: the snapshot, else the invoice's rates
  --    9 earn_premium_bundle_commission: keep them with the tier 1 row
  --   10 invoice_affiliate_commission_preview: the invoice's rates
  --   11 invoice_package_commission_preview: a settled line's rate from its sale
  --   12 invoice_package_commission_preview: the invoice's rates
  --   13 sync_instalment_commissions: keep them the first time a part payment earns
  --   14 upsert_credit_package: its variables
  --   15 upsert_credit_package: Owner only for the rates, 0 to 100
  --   16 upsert_credit_package: the audit row's old and new rates
  --   17 upsert_premium_bundle: its variables
  --   18 upsert_premium_bundle: Owner only for the rates, 0 to 100
  --   19 upsert_premium_bundle: the audit row's old and new rates
  --   20 trg_audit_direct_change: the three tables' entry names
  --   21 trg_audit_direct_change: app_settings filed under no record
  c_fn constant int[] := array[1, 2, 2, 3, 3, 3, 4, 4, 4, 5, 6, 6, 7, 8, 8, 8, 9, 9, 9, 10, 10];
  c_anchor constant text[] := array[
-- 1 set_commission_rates: Owner only
$a$  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit commission rates'; end if;
$a$,
-- 2 earn_invoice_commission: the invoice's rates
$a$  -- Editable commission rates (fall back to the historical defaults).
  select coalesce(commission_tier1_own_rate, 15), coalesce(commission_tier1_third_rate, 4.5),
         coalesce(commission_tier2_own_rate, 5), coalesce(commission_tier2_third_rate, 5),
         coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third, v_machine_new
    from public.app_settings where id = true;
$a$,
-- 3 earn_invoice_commission: keep them once it has a row
$a$  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
$a$,
-- 4 earn_credit_package_commission: its variables
$a$  -- 527: each tier's status and, when blocked, its reason
$a$,
-- 5 earn_credit_package_commission: the snapshot, else the invoice's rates
$a$  v_ptype := public.package_commission_classification();
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;
$a$,
-- 6 earn_credit_package_commission: keep them with the tier 1 row
$a$    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
$a$,
-- 7 earn_premium_bundle_commission: its variables
$a$  -- 527: each tier's status and, when blocked, its reason
$a$,
-- 8 earn_premium_bundle_commission: the snapshot, else the invoice's rates
$a$  v_ptype := public.package_commission_classification();
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;
$a$,
-- 9 earn_premium_bundle_commission: keep them with the tier 1 row
$a$    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
$a$,
-- 10 invoice_affiliate_commission_preview: the invoice's rates
$a$  -- Editable commission rates (fall back to the historical defaults).
  select coalesce(commission_tier1_own_rate, 15), coalesce(commission_tier1_third_rate, 4.5),
         coalesce(commission_tier2_own_rate, 5), coalesce(commission_tier2_third_rate, 5),
         coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third, v_machine_new
    from public.app_settings where id = true;
$a$,
-- 11 invoice_package_commission_preview: a settled line's rate from its sale
$a$    select ii.id as item_id, coalesce(cp.tier1_rate, pb.tier1_rate) as def_r1,
           coalesce(cp.tier2_rate, pb.tier2_rate) as def_r2,
           ii.credit_issued_at is null as unsettled   -- 476
      from public.invoice_items ii
      left join public.credit_packages cp on cp.id = ii.credit_package_id
      left join public.premium_bundles pb on pb.id = ii.premium_bundle_id
$a$,
-- 12 invoice_package_commission_preview: the invoice's rates
$a$    select coalesce(v_it.def_r1, case when v_cls = 'third_party' then a.commission_tier1_third_rate else a.commission_tier1_own_rate end),
           coalesce(v_it.def_r2, case when v_cls = 'third_party' then a.commission_tier2_third_rate else a.commission_tier2_own_rate end)
      into v_r1, v_r2 from public.app_settings a where a.id = true;
$a$,
-- 13 sync_instalment_commissions: keep them the first time a part payment earns
$a$  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_targets
    from public.invoice_instalment_commission_targets(p_invoice_id) t;
$a$,
-- 14 upsert_credit_package: its variables
$a$declare v_id uuid; v_s uuid; v_v uuid;
$a$,
-- 15 upsert_credit_package: Owner only for the rates, 0 to 100
$a$    raise exception 'Only an Owner or Manager can manage credit packages'; end if;
$a$,
-- 16 upsert_credit_package: the audit row's old and new rates
$a$    null, jsonb_build_object('name', trim(p_name)), 'catalogue', null, null);
$a$,
-- 17 upsert_premium_bundle: its variables
$a$declare v_id uuid; v_qual numeric; v_qty integer;
$a$,
-- 18 upsert_premium_bundle: Owner only for the rates, 0 to 100
$a$    raise exception 'Only an Owner or Manager can manage premium bundles'; end if;
$a$,
-- 19 upsert_premium_bundle: the audit row's old and new rates
$a$  perform public.write_audit_ex('premium_bundles', v_id, 'premium_bundle_upserted', null,
    jsonb_build_object('name', p_name, 'payment', p_customer_payment_amount,
      'paid_credit', p_paid_credit_amount, 'bonus_credit', p_bonus_credit_amount,
      'vouchers', v_qty, 'classification', p_commission_classification), 'credit', null, null);
$a$,
-- 20 trg_audit_direct_change: the three tables' entry names
$a$    when 'suppliers' then 'supplier'
    else tg_table_name end;
$a$,
-- 21 trg_audit_direct_change: app_settings filed under no record
$a$  else
    v_record := (v_row ->> 'id')::uuid;
  end if;
$a$];
  c_new constant text[] := array[
-- 1 set_commission_rates: Owner only
$n$  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit commission rates'; end if;
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): only an Owner changes the
  -- affiliate commission rates (an Admin is not an Owner). Managers still read them.
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can change the commission rates.' using errcode = '42501'; end if;
$n$,
-- 2 earn_invoice_commission: the invoice's rates
$n$  -- Editable commission rates (fall back to the historical defaults).
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026: "An invoice keeps the
  -- commission rates it first earned at"): the four rates are the ones kept for this invoice
  -- when it first earned affiliate commission; an invoice that has not earned yet reads the
  -- current settings, as before, and keeps them below once it has a commission row. So a
  -- correction, a reconcile or an affiliate change after a rate change works it out at the
  -- rates it first earned at. machine_commission_from (489) is read as before.
  -- Until its rates are kept, the invoice is locked first, so another earning of it (a caller
  -- that did not lock it) waits and then reads the rates this one keeps.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id) then
    perform 1 from public.invoices i535 where i535.id = p_invoice_id for update;
  end if;
  select r.tier1_own, r.tier1_third, r.tier2_own, r.tier2_third
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third
    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
$n$,
-- 3 earn_invoice_commission: keep them once it has a row
$n$  -- 535 (security audit of 17 Nov 2026, M12): the first time this invoice has a commission row,
  -- the rates it was worked out at are kept with it (when some are kept already, nothing changes).
  if exists (select 1 from public.commissions c535 where c535.invoice_id = p_invoice_id) then
    perform public.record_invoice_affiliate_rates(p_invoice_id, v_rate_t1_own, v_rate_t1_third,
      v_rate_t2_own, v_rate_t2_third);
  end if;
  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
$n$,
-- 4 earn_credit_package_commission: its variables
$n$  -- 527: each tier's status and, when blocked, its reason
  -- 535: the invoice's four affiliate rates (invoice_affiliate_rates_for), kept with its first row
  v535_t1_own numeric; v535_t1_third numeric; v535_t2_own numeric; v535_t2_third numeric;
$n$,
-- 5 earn_credit_package_commission: the snapshot, else the invoice's rates
$n$  v_ptype := public.package_commission_classification();
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): the sale's own snapshot
  -- rate (the package's rate when it was sold) comes first, as before; without one, the
  -- invoice's rates: those kept when it first earned affiliate commission, else the current
  -- settings, kept below with the tier 1 row. Until its rates are kept, the invoice is locked
  -- first, so another earning of it waits and then reads the rates this one keeps.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
  end if;
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then r.tier1_third else r.tier1_own end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then r.tier2_third else r.tier2_own end),
         r.tier1_own, r.tier1_third, r.tier2_own, r.tier2_third
    into v_r1, v_r2, v535_t1_own, v535_t1_third, v535_t2_own, v535_t2_third
    from public.invoice_affiliate_rates_for(s.invoice_id) r;
$n$,
-- 6 earn_credit_package_commission: keep them with the tier 1 row
$n$    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
    -- 535 (security audit of 17 Nov 2026, M12): the invoice keeps the settings rates it first
    -- earned at (when some are kept already, nothing changes).
    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
$n$,
-- 7 earn_premium_bundle_commission: its variables
$n$  -- 527: each tier's status and, when blocked, its reason
  -- 535: the invoice's four affiliate rates (invoice_affiliate_rates_for), kept with its first row
  v535_t1_own numeric; v535_t1_third numeric; v535_t2_own numeric; v535_t2_third numeric;
$n$,
-- 8 earn_premium_bundle_commission: the snapshot, else the invoice's rates
$n$  v_ptype := public.package_commission_classification();
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): the sale's own snapshot
  -- rate (the bundle's rate when it was sold) comes first, as before; without one, the
  -- invoice's rates: those kept when it first earned affiliate commission, else the current
  -- settings, kept below with the tier 1 row. Until its rates are kept, the invoice is locked
  -- first, so another earning of it waits and then reads the rates this one keeps.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
  end if;
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then r.tier1_third else r.tier1_own end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then r.tier2_third else r.tier2_own end),
         r.tier1_own, r.tier1_third, r.tier2_own, r.tier2_third
    into v_r1, v_r2, v535_t1_own, v535_t1_third, v535_t2_own, v535_t2_third
    from public.invoice_affiliate_rates_for(s.invoice_id) r;
$n$,
-- 9 earn_premium_bundle_commission: keep them with the tier 1 row
$n$    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
    -- 535 (security audit of 17 Nov 2026, M12): the invoice keeps the settings rates it first
    -- earned at (when some are kept already, nothing changes).
    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
$n$,
-- 10 invoice_affiliate_commission_preview: the invoice's rates
$n$  -- Editable commission rates (fall back to the historical defaults).
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): the invoice's rates, as
  -- earn_invoice_commission reads them: those kept when it first earned affiliate commission,
  -- else the current settings. A part payment after a rate change earns at the same rates.
  select r.tier1_own, r.tier1_third, r.tier2_own, r.tier2_third
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third
    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
$n$,
-- 11 invoice_package_commission_preview: a settled line's rate from its sale
$n$    -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): a settled line's own rate
    -- is its sale's snapshot (the package's or bundle's rate when it was sold, or none), as
    -- earn_credit_package_commission and earn_premium_bundle_commission read it, so a later change
    -- to the package does not re-price it; the line's latest sale. A line not yet settled reads
    -- the package's rate, which its settlement will snapshot.
    select ii.id as item_id,
           case when sl535.found then sl535.r1 else coalesce(cp.tier1_rate, pb.tier1_rate) end as def_r1,
           case when sl535.found then sl535.r2 else coalesce(cp.tier2_rate, pb.tier2_rate) end as def_r2,
           ii.credit_issued_at is null as unsettled   -- 476
      from public.invoice_items ii
      left join public.credit_packages cp on cp.id = ii.credit_package_id
      left join public.premium_bundles pb on pb.id = ii.premium_bundle_id
      left join lateral (
             select true as found, x.r1, x.r2
               from (select cs.tier1_rate_snapshot as r1, cs.tier2_rate_snapshot as r2, cs.sold_at, cs.id
                       from public.credit_package_sales cs
                      where cs.invoice_item_id = ii.id and ii.line_kind = 'credit_package'
                     union all
                     select bs.tier1_rate_snapshot, bs.tier2_rate_snapshot, bs.sold_at, bs.id
                       from public.premium_bundle_sales bs
                      where bs.invoice_item_id = ii.id and ii.line_kind = 'premium_bundle') x
              order by x.sold_at desc nulls last, x.id desc
              limit 1) sl535 on true
$n$,
-- 12 invoice_package_commission_preview: the invoice's rates
$n$    -- 535 (security audit of 17 Nov 2026, M12): without the line's own rate, the invoice's rates:
    -- those kept when it first earned affiliate commission, else the current settings.
    select coalesce(v_it.def_r1, case when v_cls = 'third_party' then a.tier1_third else a.tier1_own end),
           coalesce(v_it.def_r2, case when v_cls = 'third_party' then a.tier2_third else a.tier2_own end)
      into v_r1, v_r2 from public.invoice_affiliate_rates_for(p_invoice_id) a;
$n$,
-- 13 sync_instalment_commissions: keep them the first time a part payment earns
$n$  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_targets
    from public.invoice_instalment_commission_targets(p_invoice_id) t;
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026: "An invoice keeps the
  -- commission rates it first earned at"): the first time a part payment earns this invoice
  -- affiliate commission (an affiliate target, none kept yet), the rates the targets were worked
  -- out at are kept with it and the targets are read again from what was kept, so the next
  -- instalment, a correction or a reconcile after a rate change pays the rest at the same rates.
  -- A dry run keeps nothing.
  if not p_dry_run
     and exists (select 1 from jsonb_array_elements(v_targets) t535 where t535->>'ledger' = 'affiliate')
     and not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id) then
    perform public.record_invoice_affiliate_rates(p_invoice_id, r535.tier1_own, r535.tier1_third,
              r535.tier2_own, r535.tier2_third)
       from public.invoice_affiliate_rates_for(p_invoice_id) r535;
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_targets
      from public.invoice_instalment_commission_targets(p_invoice_id) t;
  end if;
$n$,
-- 14 upsert_credit_package: its variables
$n$declare v_id uuid; v_s uuid; v_v uuid;
  -- 535: the package's own rates as stored before this save, and the audit row's old rates
  v535_t1 numeric; v535_t2 numeric; v535_staff numeric; v535_old jsonb;
$n$,
-- 15 upsert_credit_package: Owner only for the rates, 0 to 100
$n$    raise exception 'Only an Owner or Manager can manage credit packages'; end if;
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): a package's own commission
  -- rates (tier 1, tier 2, staff) are the Owner's: anyone else's save must leave them as stored
  -- (read with the row locked; a new package: none given). And they are none, or 0 to 100.
  if p_id is not null then
    select cp.tier1_rate, cp.tier2_rate, cp.staff_commission_rate
      into v535_t1, v535_t2, v535_staff
      from public.credit_packages cp where cp.id = p_id for update;
    if found then
      v535_old := jsonb_build_object('tier1_rate', v535_t1, 'tier2_rate', v535_t2,
                                     'staff_commission_rate', v535_staff);
    end if;
  end if;
  if public.current_user_role() is distinct from 'owner'
     and (p_tier1_rate is distinct from v535_t1 or p_tier2_rate is distinct from v535_t2
          or p_staff_commission_rate is distinct from v535_staff) then
    raise exception 'Only an Owner can set a package''s or bundle''s own commission rates.' using errcode = '42501'; end if;
  if p_tier1_rate < 0 or p_tier1_rate > 100 then
    raise exception 'A package''s or bundle''s Tier 1 rate must be between 0 and 100.'; end if;
  if p_tier2_rate < 0 or p_tier2_rate > 100 then
    raise exception 'A package''s or bundle''s Tier 2 rate must be between 0 and 100.'; end if;
  if p_staff_commission_rate < 0 or p_staff_commission_rate > 100 then
    raise exception 'A package''s or bundle''s Staff commission rate must be between 0 and 100.'; end if;
$n$,
-- 16 upsert_credit_package: the audit row's old and new rates
$n$    -- 535 (security audit of 17 Nov 2026, M12): the old rates (none for a new package) and the
    -- new ones as stored, with the name as before.
    v535_old,
    (select jsonb_build_object('name', trim(p_name), 'tier1_rate', cp.tier1_rate, 'tier2_rate', cp.tier2_rate,
                               'staff_commission_rate', cp.staff_commission_rate)
       from public.credit_packages cp where cp.id = v_id),
    'catalogue', null, null);
$n$,
-- 17 upsert_premium_bundle: its variables
$n$declare v_id uuid; v_qual numeric; v_qty integer;
  -- 535: the bundle's own rates as stored before this save, and the audit row's old rates
  v535_t1 numeric; v535_t2 numeric; v535_staff numeric; v535_old jsonb;
$n$,
-- 18 upsert_premium_bundle: Owner only for the rates, 0 to 100
$n$    raise exception 'Only an Owner or Manager can manage premium bundles'; end if;
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): a bundle's own commission
  -- rates (tier 1, tier 2, staff) are the Owner's: anyone else's save must leave them as stored
  -- (read with the row locked; a new bundle: none given). And they are none, or 0 to 100.
  if p_id is not null then
    select pb.tier1_rate, pb.tier2_rate, pb.staff_commission_rate
      into v535_t1, v535_t2, v535_staff
      from public.premium_bundles pb where pb.id = p_id for update;
    if found then
      v535_old := jsonb_build_object('tier1_rate', v535_t1, 'tier2_rate', v535_t2,
                                     'staff_commission_rate', v535_staff);
    end if;
  end if;
  if public.current_user_role() is distinct from 'owner'
     and (p_tier1_rate is distinct from v535_t1 or p_tier2_rate is distinct from v535_t2
          or p_staff_commission_rate is distinct from v535_staff) then
    raise exception 'Only an Owner can set a package''s or bundle''s own commission rates.' using errcode = '42501'; end if;
  if p_tier1_rate < 0 or p_tier1_rate > 100 then
    raise exception 'A package''s or bundle''s Tier 1 rate must be between 0 and 100.'; end if;
  if p_tier2_rate < 0 or p_tier2_rate > 100 then
    raise exception 'A package''s or bundle''s Tier 2 rate must be between 0 and 100.'; end if;
  if p_staff_commission_rate < 0 or p_staff_commission_rate > 100 then
    raise exception 'A package''s or bundle''s Staff commission rate must be between 0 and 100.'; end if;
$n$,
-- 19 upsert_premium_bundle: the audit row's old and new rates
$n$  -- 535 (security audit of 17 Nov 2026, M12): the old rates (none for a new bundle) and the new
  -- ones as stored, with what it recorded before.
  perform public.write_audit_ex('premium_bundles', v_id, 'premium_bundle_upserted', v535_old,
    jsonb_build_object('name', p_name, 'payment', p_customer_payment_amount,
      'paid_credit', p_paid_credit_amount, 'bonus_credit', p_bonus_credit_amount,
      'vouchers', v_qty, 'classification', p_commission_classification)
    || (select jsonb_build_object('tier1_rate', pb.tier1_rate, 'tier2_rate', pb.tier2_rate,
                                  'staff_commission_rate', pb.staff_commission_rate)
          from public.premium_bundles pb where pb.id = v_id),
    'credit', null, null);
$n$,
-- 20 trg_audit_direct_change: the three tables' entry names
$n$    when 'suppliers' then 'supplier'
    -- 535 (security audit of 17 Nov 2026, M12): the commission rates and the packages' and
    -- bundles' own rates, changed straight on their tables
    when 'app_settings' then 'settings'
    when 'credit_packages' then 'credit_package'
    when 'premium_bundles' then 'premium_bundle'
    else tg_table_name end;
$n$,
-- 21 trg_audit_direct_change: app_settings filed under no record
$n$  elsif tg_table_name = 'app_settings' then
    -- 535 (security audit of 17 Nov 2026, M12): the one settings row's id is true, not a uuid; its
    -- entry is filed under no record, as set_commission_rates files its own.
    v_record := null;
  else
    v_record := (v_row ->> 'id')::uuid;
  end if;
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[10]);
  v_n_back int; v_n_earned int; v_n_differ int;
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      raise exception 'undo 535: public.% is missing. Nothing was changed.', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_before[i] then
      raise exception 'undo 535: public.% is already its version of before 535; 535 is not in. Nothing was changed.', c_sig[i]; end if;
    if md5(d) <> c_535[i] then
      raise exception 'undo 535: public.% is not 535''s version (md5 %). Nothing was changed.', c_sig[i], md5(d); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo 535: the grants of public.% are not the tested ones. Nothing was changed.', c_sig[i]; end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception 'undo 535: public.% is missing or not 535''s. Nothing was changed.', c_new_sig[i]; end if;
  end loop;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
     and p.oid not in (select to_regprocedure('public.' || x) from unnest(c_sig || c_new_sig) x)
     and (pg_get_functiondef(p.oid) like '%invoice_affiliate_rates%');
  if d is not null then
    raise exception 'undo 535: 535''s table or helpers are also used by %. Nothing was changed.', d; end if;
  if to_regclass('public.invoice_affiliate_rates') is null
     or obj_description(to_regclass('public.invoice_affiliate_rates'), 'pg_class') is distinct from c_table_comment then
    raise exception 'undo 535: public.invoice_affiliate_rates is missing or not 535''s. Nothing was changed.'; end if;
  for i in 1 .. cardinality(c_con_table) loop
    if not exists (select 1 from pg_constraint k
                    where k.conrelid = to_regclass('public.' || c_con_table[i])
                      and k.conname = c_con_table[i] || '_' || c_con_col[i] || '_0_100') then
      raise exception 'undo 535: the constraint %_%_0_100 is missing. Nothing was changed.', c_con_table[i], c_con_col[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_trg_table) loop
    if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = to_regclass('public.' || c_trg_table[i])
           and t.tgname = 'audit_direct_change') is distinct from format(c_trg_def, c_trg_table[i]) then
      raise exception 'undo 535: the audit trigger on public.% is missing or not 535''s. Nothing was changed.', c_trg_table[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i])) is distinct from 'postgres=X/postgres,service_role=X/postgres'
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_closed[i]))) <> c_closed_md5[i] then
      raise exception 'undo 535: the grants or text of public.% are not 535''s. Nothing was changed.', c_closed[i]; end if;
  end loop;
  for i in reverse cardinality(c_fn) .. 1 loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'undo 535: 535''s text % is not found exactly once in public.%. Nothing was changed.', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'undo 535: public.% without 535''s text is not its version of before 535 (md5 %). Nothing was changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- What is dropped with the table
  select count(*) filter (where r.backfilled), count(*) filter (where not r.backfilled),
         count(*) filter (where (r.tier1_own_rate, r.tier1_third_rate, r.tier2_own_rate, r.tier2_third_rate)
                                is distinct from (a.commission_tier1_own_rate, a.commission_tier1_third_rate,
                                                  a.commission_tier2_own_rate, a.commission_tier2_third_rate))
    into v_n_back, v_n_earned, v_n_differ
    from public.invoice_affiliate_rates r cross join public.app_settings a where a.id = true;
  raise notice 'undo 535: dropping the kept rates of % invoice(s) (% backfilled by 535, % kept since); % differ from the settings now and would be re-priced at their next correction, reconcile or part payment.',
    v_n_back + v_n_earned, v_n_back, v_n_earned, v_n_differ;

  -- 2. Put back (the triggers first: they call 532's function, put back below)
  for i in 1 .. cardinality(c_trg_table) loop
    execute format('drop trigger audit_direct_change on public.%I', c_trg_table[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    execute format('drop function public.%s', c_new_sig[i]);
  end loop;
  drop table public.invoice_affiliate_rates;
  for i in 1 .. cardinality(c_con_table) loop
    execute format('alter table public.%I drop constraint %I', c_con_table[i], c_con_table[i] || '_' || c_con_col[i] || '_0_100');
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    execute format('grant execute on function public.%s to authenticated', c_closed[i]);
  end loop;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo 535: public.% is not as before 535 after putting it back', c_sig[i]; end if;
  end loop;
  if exists (select 1 from pg_trigger t where t.tgname = 'audit_direct_change'
                and t.tgrelid in (select to_regclass('public.' || x) from unnest(c_trg_table) x)) then
    raise exception 'undo 535: an audit trigger 535 added is still there'; end if;
  for i in 1 .. cardinality(c_closed) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i])) is distinct from c_closed_acl_before then
      raise exception 'undo 535: the grants of public.% are not as before 535', c_closed[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
