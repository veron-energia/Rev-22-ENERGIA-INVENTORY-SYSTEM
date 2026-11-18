-- 522_dashboard_tiktok_counts_follow_the_store.sql
--
-- THE DASHBOARD'S TIKTOK COUNTS ARE EACH LOGIN'S STORES'
--
--   From the security audit of 17 Nov 2026 (finding L6, after 520 and 521).
--   The BEFORE md5 below was compared with production on 18 Nov 2026 (head 521) and matches.
--   If production differs when this is applied, it refuses and changes nothing.
--   (The number 522 is this file's name and its errors' prefix; if it changes at commit,
--   change it there, in scripts/dashboard/undo-522.sql, in the name and paths of its suite,
--   and in the line of the three suites of 502 that runs that UNDO.)
--
-- WHAT WAS WRONG
--
--   Since 520 and 521, Staff and Inventory Managers read only their own stores' TikTok records,
--   on the TikTok Import page and through its reports. The Dashboard's Operations alerts
--   (dashboard_alerts_summary) still counted every store's TikTok records for any staff login:
--   imported orders, unmatched SKUs, files awaiting confirmation, orders awaiting settlement,
--   settlement mismatches, orders settled with no imported order, and items awaiting a
--   physical return. Each tile opens the TikTok Import page, which then showed fewer.
--
-- THE RULE (the user, 18 Nov 2026)
--
--   Those counts follow the login's stores, as the page each of them opens (the TikTok Import
--   page) shows them: Staff and Inventory Managers their own stores; Owners, Admins and
--   Managers every store. (The Dashboard's other tiles each count what their own page shows,
--   by that page's rules.)
--
-- WHAT THIS DOES
--
--   dashboard_alerts_summary(): each of the seven TikTok counts keeps to the stores this login
--   works at (current_user_store_ids(), as the read rules use it), or every store for an
--   Owner, Admin or Manager. The negative-stock count already follows 521's alert.
--
-- WHAT THIS LEAVES ALONE
--
--   * The rest of the function: the Transfers counts, customers with no source, refunded or
--     cancelled sales still holding benefits. Its grants.
--   * Production on 18 Nov 2026: every Staff login works at both stores, and there is no
--     Inventory Manager, so no one's Dashboard shows a different number today.
--   * 502's UNDO (scripts/therapy/undo-502.sql) refuses on a database where this is in, as it
--     does whenever one of the fifteen functions 502 patched has a later version (this is one).
--     To undo 502 there, run scripts/dashboard/undo-522.sql first. The three suites of 502 do
--     that for their own run, inside their transaction: they test 502, not these counts.
--
-- UNDO
--
--   scripts/dashboard/undo-522.sql (it refuses unless dashboard_alerts_summary() is 522's
--   version). A later migration changing dashboard_alerts_summary must pin 522's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/dashboard/tests/tiktok-counts-follow-the-store-522.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  c_sig constant text[] := array[
    'dashboard_alerts_summary()'];
  c_before constant text[] := array[
    '71c01b0053937347a63b311b7eca5734'];
  c_after constant text[] := array[
    'b614ad8c75f8012e069ec72a5be06aa9'];
  -- Seven patches of the one function, each found exactly once.
  c_fn constant int[] := array[1, 1, 1, 1, 1, 1, 1];
  c_anchor constant text[] := array[
$a$      'imported_orders', (select count(distinct (store_id, order_id)) from public.tiktok_order_state),$a$,
$a$                          where o.staging_status = 'Unmatched SKU'
$a$,
$a$                          where b.status = 'staged' and b.deleted_at is null),$a$,
$a$                                      where st.deducted_qty > 0
$a$,
$a$                                 where r.confirmed and r.is_current
                                   and public.tiktok_settlement_row_reconciled($a$,
$a$                                 where r.confirmed and r.is_current and r.match_status = 'pending'
$a$,
$a$(select count(*) from public.tiktok_physical_returns pr where pr.status = 'awaiting'),$a$];
  c_new constant text[] := array[
$n$      -- 522: each count is of the stores this login works at; every store for an Owner,
      -- Admin or Manager (the user, 18 Nov 2026), as the TikTok Import page shows them.
      'imported_orders', (select count(distinct (store_id, order_id)) from public.tiktok_order_state
                           where (select public.is_manager_or_above()) or store_id = any ((select public.current_user_store_ids())::uuid[])),$n$,
$n$                          where o.staging_status = 'Unmatched SKU'
                            and ((select public.is_manager_or_above()) or o.store_id = any ((select public.current_user_store_ids())::uuid[]))
$n$,
$n$                          where b.status = 'staged' and b.deleted_at is null
                            and ((select public.is_manager_or_above()) or b.store_id = any ((select public.current_user_store_ids())::uuid[]))),$n$,
$n$                                      where st.deducted_qty > 0
                                        and ((select public.is_manager_or_above()) or st.store_id = any ((select public.current_user_store_ids())::uuid[]))
$n$,
$n$                                 where r.confirmed and r.is_current
                                   and ((select public.is_manager_or_above()) or r.store_id = any ((select public.current_user_store_ids())::uuid[]))
                                   and public.tiktok_settlement_row_reconciled($n$,
$n$                                 where r.confirmed and r.is_current and r.match_status = 'pending'
                                   and ((select public.is_manager_or_above()) or r.store_id = any ((select public.current_user_store_ids())::uuid[]))
$n$,
$n$(select count(*) from public.tiktok_physical_returns pr where pr.status = 'awaiting'
                                    and ((select public.is_manager_or_above()) or pr.store_id = any ((select public.current_user_store_ids())::uuid[]))),$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '522: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '522: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '522: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '522: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '522: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '522: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '522: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
