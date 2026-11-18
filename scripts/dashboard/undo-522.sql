-- UNDO of 522 (with the user's go-ahead). It puts dashboard_alerts_summary() back to its text
-- before 522 (md5 71c01b00…, as 502 left it and 521 kept it): the Dashboard's seven TikTok
-- counts count every store's records again, for any staff login. Its grants stay as they are.
--
-- It refuses, with nothing changed, unless dashboard_alerts_summary() is exactly 522's version
-- (so a later version is never overwritten). One transaction, all or nothing; it waits at most
-- 5 seconds for a lock. The 522 row in supabase_migrations.schema_migrations stays; with the
-- user's OK, remove that one row (found by its name, 522_dashboard_tiktok_counts_follow_the_store)
-- or record this UNDO beside it.
--
-- ROLLBACK ORDER, to undo 502 where 522 is in: this file first, then scripts/therapy/undo-502.sql
-- (which refuses while 522 is in). The suites of 502 run this file inside their own transaction
-- where 522 is in (everything there is rolled back): they test 502, not these counts.
-- The patch texts below are 522's, the other way round: each 522 text is found exactly once and
-- put back as it was.
do $undo$
declare
  c_sig constant text := 'dashboard_alerts_summary()';
  c_522 constant text := 'b614ad8c75f8012e069ec72a5be06aa9';
  c_before_522 constant text := '71c01b0053937347a63b311b7eca5734';
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
  v_acl text; d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  if to_regprocedure('public.' || c_sig) is null then raise exception 'UNDO 522: public.% is missing', c_sig; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) <> c_522 then
    raise exception 'UNDO 522: public.% is not 522''s version (md5 %). Nothing changed.', c_sig, md5(d); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));
  for i in 1 .. cardinality(c_new) loop
    if (length(d) - length(replace(d, c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 522: patch % does not find 522''s text exactly once in public.%', i, c_sig; end if;
    d := replace(d, c_new[i], c_anchor[i]);
  end loop;
  if md5(d) <> c_before_522 then
    raise exception 'UNDO 522: the text put back is not the one before 522 (md5 %). Nothing changed.', md5(d); end if;

  -- 2. Put back
  execute d;

  -- 3. Checks after
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_before_522 then
    raise exception 'UNDO 522: public.% was put back with an md5 other than the one before 522', c_sig; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception 'UNDO 522: the grants of public.% changed', c_sig; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
