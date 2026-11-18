-- 521_tiktok_imports_and_alerts_follow_the_store.sql
--
-- AN INVENTORY MANAGER'S TIKTOK WORK, AND EACH LOGIN'S STOCK ALERT, KEEP TO THEIR STORES
--
--   From the security audit of 17 Nov 2026 (finding L6, the rest after 520).
--   The BEFORE md5s and the rule below were compared with production on 18 Nov 2026 (head 520)
--   and match. If production differs when this is applied, it refuses and changes nothing.
--   (The number 521 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   520 made the TikTok tables readable by Staff and Inventory Managers for their own stores
--   only, as the user decided on 18 Nov 2026. Three things still went past that:
--   * tiktok_access_check(), the check every TikTok import step makes (stage a file, refresh,
--     confirm, delete a staged row, include settled lines, map a SKU, the batch counts), let
--     an Inventory Manager work at every store, and thirteen TikTok report functions (the
--     import list, the settlement lines and totals, the lines left out, the Reports page's
--     TikTok reports) gave an Inventory Manager every store's. On the TikTok Import page an
--     Inventory Manager could choose any store and import there, and then could not read
--     what they had imported.
--   * tiktok_negative_stock_alerts(), the Dashboard's negative-stock list (and the count in
--     its Operations alerts), listed every store's negative stock to any staff login.
--   * data_removal_reconciliation, the log of data-removal runs, was readable by any staff
--     login.
--
-- THE RULES (the user, 18 Nov 2026)
--
--   * TikTok records: Staff and Inventory Managers their own stores; Owners, Admins and
--     Managers every store (as 520).
--   * The negative-stock alert: each login's stores (every store for an Owner, Admin or
--     Manager).
--   * The data-removal log: Owners and Managers (and Admins, as wherever Managers read).
--
-- WHAT THIS DOES
--
--   * tiktok_access_check: an Owner, Admin or Manager passes at every store; Staff and
--     Inventory Managers at the stores they work at ("You can only import TikTok sales for
--     your assigned store", as Staff were told).
--   * The thirteen reports: an Inventory Manager reads the stores they work at, as Staff do.
--   * tiktok_negative_stock_alerts: the stores this login works at; every store for an
--     Owner, Admin or Manager.
--   * The read rule of data_removal_reconciliation: Owners, Admins and Managers.
--   The TikTok Import page lists an Inventory Manager's own stores, as it does Staff's.
--
-- WHAT THIS LEAVES ALONE
--
--   * Owners, Admins, Managers and Staff: what each can do and read in these functions is
--     unchanged, except the stock alert (Staff were already kept to their stores by the rest).
--   * dashboard_alerts_summary(): its other TikTok counts (imported orders, unmatched SKUs
--     and the rest) still count every store for any login; its negative-stock count follows
--     the alert.
--   * The grants of every function. No page reads the data-removal log.
--   * Production on 18 Nov 2026 has no Inventory Manager, and every Staff login works at
--     both stores: no page shows anyone anything different today.
--
-- UNDO
--
--   Run this block's function part with c_before and c_after swapped, each c_anchor with its
--   c_new, and c_im_anchor with c_im_new; and alter policy "read data removal log" on
--   public.data_removal_reconciliation using ((select current_user_role()) is not null).
--   A later migration changing any of these functions must pin 521's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/tiktok-and-alerts-follow-the-store-521.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  c_sig constant text[] := array[
    'tiktok_access_check(uuid)',
    'tiktok_negative_stock_alerts()',
    'report_tiktok_import_discrepancies(uuid)',
    'report_tiktok_imports(uuid,date,date)',
    'report_tiktok_orders_by_status(uuid)',
    'report_tiktok_qty_sold(uuid,date,date)',
    'report_tiktok_recon_exceptions(uuid)',
    'report_tiktok_settlement(uuid,date,date)',
    'report_tiktok_settlement_by_store(date,date)',
    'report_tiktok_settlement_daily(uuid,date,date)',
    'report_tiktok_stock_activity(uuid,date,date)',
    'report_tiktok_unmatched_skus(uuid)',
    'tiktok_left_out_settlement(uuid,date,date)',
    'tiktok_settlement_eligible(uuid)',
    'tiktok_settlement_totals(integer,integer,uuid)'];
  c_before constant text[] := array[
    '94b85ae013171b13947013b6e1c06036',
    'e220e1441d930f34f58163ff5993db97',
    '84ecc5182639d20a262ebfffc0cf33c0',
    '0c0fb0887dcc6204831e1d32e6f2e186',
    'f9c2248e88ea1b71d9ea685a364380eb',
    '74c3a1b458ee670cdafb856a3d4b6c3e',
    '25679e40e7ffa5dea26f08876f22178a',
    '06072a902440f379f18a5e608b489f48',
    '4eb124122be86f74b986a449631b6c3c',
    '92b545546e959c8233a972ba61c1f2ee',
    '9260a1dd1b7ee6261fb745a8730a3959',
    'a35d7f8b0681add47e40f4fffea264ef',
    '272fa4fb2d681ac95f0f8ce84c040e9e',
    '910a1d4e8dae21f1f2954101c9101729',
    'f45cb4f6ec3bb410768ed4ebc96a8a0f'];
  c_after constant text[] := array[
    '85e207b126a3296ccfdb12f27d46faae',
    '6abcf753a83a083724154164e6ac6ff0',
    'da9b60005801ab3c281b130db6336d57',
    '6026f74fe5007dca4cc68f02ceba5a15',
    'dd6299c859a71e13f9c54ea19e6f0064',
    'c7173a37536b1350890341c9d7c1cacf',
    'aef2f88ed10388b85388c501db195a1a',
    '99611f8408c14c1df194c410277b2ad0',
    'd22c5abdae4879d345a4c4ca11572ac5',
    'f4fc891dc7ff361c8c6125082e8738aa',
    '9f0b953e3462e99ecea38dd6b2453e40',
    '3dbdb12ca4eef07b60b3f9610ff5ad90',
    '66ddb78ad59d87bd3881b23a500df068',
    '6f075978c47f735dae44e499e74b18b5',
    '9bb45e064e1e9f2b468ec847564a39bb'];
  -- The patches of the access check (1) and the stock alert (2), each found exactly once.
  c_fn constant int[] := array[1, 2, 2];
  c_anchor constant text[] := array[
$a$  if v_role in ('owner','manager','admin','inventory_manager') then return; end if;
  -- staff: assigned store only$a$,
$a$   where si.current_qty < 0
$a$,
$a$   where vs.current_qty < 0
$a$];
  c_new constant text[] := array[
$n$  -- 521: an Owner, Admin or Manager at every store; Staff and Inventory Managers at the
  -- stores they work at (security audit of 17 Nov 2026, L6; the user, 18 Nov 2026).
  if v_role in ('owner','manager','admin') then return; end if;
  -- staff and inventory managers: assigned stores only$n$,
$n$   where si.current_qty < 0
     -- 521: the stores this login works at; every store for an Owner, Admin or Manager
     and (public.is_manager_or_above() or si.store_id = any (public.current_user_store_ids()))
$n$,
$n$   where vs.current_qty < 0
     and (public.is_manager_or_above() or vs.store_id = any (public.current_user_store_ids()))
$n$];
  -- The thirteen reports (3 to 15): an Inventory Manager no longer reads every store's. The
  -- text is found in each the number of times given, and it ends its line every time.
  c_im_fn constant int[] := array[3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
  c_im_times constant int[] := array[1, 1, 1, 1, 3, 1, 1, 1, 2, 1, 1, 1, 1];
  c_im_anchor constant text :=
    $a$public.current_user_role() in ('owner','manager','admin','inventory_manager')$a$ || E'\n';
  c_im_new constant text :=
    $n$public.current_user_role() in ('owner','manager','admin')  -- 521: an Inventory Manager, their stores$n$ || E'\n';
  -- The read rule of the data-removal log, as pg_get_expr shows it before and after.
  c_rule_before constant text := '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)';
  c_rule_after constant text := '( SELECT is_manager_or_above() AS is_manager_or_above)';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[15]);
  v_make boolean[] := array_fill(false, array[15]);
  v_acl text[] := array_fill(null::text, array[15]);
  v_alter boolean := false;
  d text; i int; n int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  -- The rule: open to every staff login (changed), or 521's already (left alone).
  select pg_get_expr(p.polqual, p.polrelid) into d
    from pg_policy p
   where p.polrelid = 'public.data_removal_reconciliation'::regclass and p.polname = 'read data removal log'
     and p.polcmd = 'r' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid];
  if d = c_rule_before then
    v_alter := true;
  elsif d = c_rule_after then
    raise notice '521: the rule "read data removal log" is already 521''s; left alone';
  else
    raise exception '521: the rule "read data removal log" on public.data_removal_reconciliation is not the one this was tested against (%). Re-read it before applying.', coalesce(d, 'missing');
  end if;

  -- The functions it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '521: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '521: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '521: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '521: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_im_fn) loop
    if v_make[c_im_fn[i]] then
      n := (length(v_def[c_im_fn[i]]) - length(replace(v_def[c_im_fn[i]], c_im_anchor, ''))) / length(c_im_anchor);
      if n <> c_im_times[i] then
        raise exception '521: public.% lets an Inventory Manager read every store % times, not %', c_sig[c_im_fn[i]], n, c_im_times[i]; end if;
      v_def[c_im_fn[i]] := replace(v_def[c_im_fn[i]], c_im_anchor, c_im_new);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '521: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;
  if v_alter then
    alter policy "read data removal log" on public.data_removal_reconciliation
      using ((select public.is_manager_or_above()));
  end if;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '521: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '521: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  select pg_get_expr(p.polqual, p.polrelid) into d
    from pg_policy p
   where p.polrelid = 'public.data_removal_reconciliation'::regclass and p.polname = 'read data removal log'
     and p.polcmd = 'r' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid];
  if d is distinct from c_rule_after then
    raise exception '521: the rule "read data removal log" is not as tested: %', coalesce(d, '(missing)'); end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
