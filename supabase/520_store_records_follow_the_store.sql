-- 520_store_records_follow_the_store.sql
--
-- A STORE'S OPERATIONS AND TIKTOK RECORDS ARE READ BY ITS OWN STAFF
--
--   From the security audit of 17 Nov 2026 (finding L6).
--   The BEFORE rules and md5 below were compared with production on 18 Nov 2026 (head 519)
--   and match. If production differs when this is applied, it refuses and changes nothing.
--   (The number 520 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   Invoices are read store by store: Staff and Inventory Managers see their own stores'.
--   Twelve tables that carry a store were open to every staff login of every store:
--   rentals, special sales, stock uses, voucher stock per store, and the TikTok imports,
--   orders, order states, physical returns, corrections, settlement money lines, voucher
--   sales and SKU aliases. report_affiliates(), the Reports page's affiliate totals, gave
--   every affiliate's commission totals to any staff login, while the page itself is for
--   Owners, Admins and Managers.
--
-- THE RULES (the user, 18 Nov 2026, deciding the audit's questions R2 and R5 for these)
--
--   * Store operations and TikTok records: Staff and Inventory Managers see only their own
--     stores' rows, as with invoices. Owners and Admins see every store.
--   * Managers see every store's (as for transfers, prices and payouts).
--   * Customer purchases and benefits that follow the customer (credit package and bundle
--     sales, a customer's vouchers and therapy sessions, top-ups, affiliate links) stay
--     readable by all staff, as the 22 Oct 2026 decision on a customer's invoices.
--   * Prices and availability per store stay readable by all staff.
--
-- WHAT THIS DOES
--
--   * The read rule of each of the twelve tables becomes: an Owner, Admin or Manager, or a
--     member of staff of the row's store (current_user_store_ids(), as invoices use it). A
--     rental or special sale is also its source store's. The rules keep their names, roles
--     and commands; only who they let read changes.
--   * report_affiliates() refuses anyone but an Owner, Admin or Manager, as its page does.
--   The pages' own server functions read these tables with their owner's rights and are not
--   affected; the Special, Vouchers and TikTok Import pages show Staff their own stores'.
--
-- WHAT THIS LEAVES ALONE
--
--   * The customer and price tables above (the rules).
--   * Tables already limited by role: the audit log, customer credit, health surveys, staff
--     commissions. data_removal_reconciliation (a log of data-removal runs) is not changed:
--     it was not among the questions.
--   * Two old cancelled rentals with no store at all (production, 18 Nov 2026): after this
--     only Owners, Admins and Managers see them.
--
-- UNDO
--
--   For each of the twelve rules, alter policy ... using ((select current_user_role()) is not
--   null); and run this block's function part with c_before and c_after swapped and c_anchor
--   and c_new swapped. A later migration changing report_affiliates must pin 520's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/store-records-follow-the-store-520.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  c_sig constant text[] := array[
    'report_affiliates()'];
  c_before constant text[] := array[
    '6528401b1a0b1555705fad846c6a83b8'];
  c_after constant text[] := array[
    '5e69835b8ecdfaab0a86aa25da04acc4'];
  c_fn constant int[] := array[1];
  c_anchor constant text[] := array[
$a$  perform public.require_active_staff();  -- 425: an accepted invitation (406)$a$];
  c_new constant text[] := array[
$n$  -- 520: an Owner, Admin or Manager, as on the Reports page (security audit of
  -- 17 Nov 2026, L6): every affiliate's commission totals are not Staff's.
  perform public.require_active_staff('{owner,admin,manager}');  -- 425: an accepted invitation (406)$n$];
  -- The read rules: table, rule name, and the new rule's text as written.
  c_table constant text[] := array[
    'rentals', 'special_sales', 'stock_uses', 'voucher_store_stock',
    'tiktok_corrections', 'tiktok_import_batches', 'tiktok_order_rows', 'tiktok_order_state',
    'tiktok_physical_returns', 'tiktok_settlement_rows', 'tiktok_voucher_sales', 'tiktok_sku_aliases'];
  c_policy constant text[] := array[
    'read rentals', 'read special sales', 'read stock uses', 'read voucher stock',
    'read tiktok_corrections', 'read tiktok_import_batches', 'read tiktok_order_rows', 'read tiktok_order_state',
    'read tiktok_physical_returns', 'read tiktok_settlement_rows', 'read tiktok_voucher_sales', 'read tiktok_sku_aliases'];
  c_rule_before constant text := '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)';
  c_rule_store constant text :=
    '(select public.is_manager_or_above()) or store_id = any ((select public.current_user_store_ids())::uuid[])';
  c_rule_store_or_source constant text :=
    '(select public.is_manager_or_above()) or store_id = any ((select public.current_user_store_ids())::uuid[]) '
    || 'or source_store_id = any ((select public.current_user_store_ids())::uuid[])';
  -- The new rules as pg_get_expr shows them.
  c_rule_after_store constant text :=
    '(( SELECT is_manager_or_above() AS is_manager_or_above) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))';
  c_rule_after_source constant text :=
    '(( SELECT is_manager_or_above() AS is_manager_or_above) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])) OR (source_store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  v_alter boolean[] := array_fill(false, array[12]);
  v_bad text := '';
  d text; i int; v_after text;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  -- The rules: open to every staff login (changed), or 520's already (left alone).
  for i in 1 .. cardinality(c_table) loop
    v_after := case when c_table[i] in ('rentals', 'special_sales') then c_rule_after_source else c_rule_after_store end;
    select pg_get_expr(p.polqual, p.polrelid) into d
      from pg_policy p
     where p.polrelid = ('public.' || c_table[i])::regclass and p.polname = c_policy[i]
       and p.polcmd = 'r' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid];
    if d = c_rule_before then
      v_alter[i] := true;
    elsif d = v_after then
      raise notice '520: the rule "%" on public.% is already 520''s; left alone', c_policy[i], c_table[i];
    else
      raise exception '520: the rule "%" on public.% is not the one this was tested against (%). Re-read it before applying.', c_policy[i], c_table[i], coalesce(d, 'missing');
    end if;
  end loop;

  -- The function it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '520: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '520: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '520: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '520: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '520: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_table) loop
    if v_alter[i] then
      execute format('alter policy %I on public.%I using (%s)', c_policy[i], c_table[i],
        case when c_table[i] in ('rentals', 'special_sales') then c_rule_store_or_source else c_rule_store end);
    end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '520: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '520: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_table) loop
    v_after := case when c_table[i] in ('rentals', 'special_sales') then c_rule_after_source else c_rule_after_store end;
    select pg_get_expr(p.polqual, p.polrelid) into d
      from pg_policy p
     where p.polrelid = ('public.' || c_table[i])::regclass and p.polname = c_policy[i]
       and p.polcmd = 'r' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid];
    if d is distinct from v_after then
      v_bad := v_bad || format(E'\n  %s: %s', c_table[i], coalesce(d, '(missing)'));
    end if;
  end loop;
  if v_bad <> '' then
    raise exception '520: the rules are not as tested:%', v_bad; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
