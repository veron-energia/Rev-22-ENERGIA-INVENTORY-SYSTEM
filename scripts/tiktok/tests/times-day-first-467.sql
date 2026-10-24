-- TikTok's order times are read day first, whatever the day (467), and the repair that puts right the
-- times stored before it (scripts/tiktok/repair/467-restore-tiktok-order-times.sql).
--
--   P  Before 467 (the bug, reproduced): a file staged with the old tiktok_parse_time stores a day of 12
--      or less month first ('03/10/2026' as 10 March), a day of 13 and on right, a day equal to its month
--      right by chance; 'D/M/YYYY H:MI' month first too. One file confirmed (its rows immutable), one
--      staged, one staged and deleted, as production holds them.
--   M  467 twice: the first run changes tiktok_parse_time alone, the second nothing; each leaves no row and
--      uses no sequence (its self-test); the AFTER md5; IMMUTABLE plpgsql, no security definer, the
--      search_path set; the grants as before (signed-in staff and the service role, never anon).
--   G  The rule, under DateStyle 'ISO, MDY', 'ISO, DMY' and 'SQL, DMY' alike: DD/MM/YYYY day first (the
--      day alone, HH24:MI[:SS], fractions, AM/PM, '.' or '-' between); not a real date or time is null;
--      year first as before (YYYY/MM/DD, ISO with a T); two short numbers first ('01/07/26') null; text
--      with no digit null; empty null.
--   N  After 467: a new order file stores its times day first; a settlement file ('YYYY/MM/DD') stores its
--      order-created and settled times as before.
--   V  The preview (467-restore-tiktok-order-times-preview.sql): the times, rows, confirmed rows, rows of
--      deleted files, month moves, future times, per column and in all.
--   R  The repair: without the go-ahead it changes nothing; with it but without an Owner, without the
--      count or with another count: refused, nothing changed; a stored time that neither reading explains
--      (a row edited by hand): refused naming it, nothing changed; with all of it: the six times put right
--      on exactly the rows counted (a failure after the trigger is switched off undoes all of it, the
--      switch-off included), nothing else of any row changed (confirmed rows included), one audit
--      row per row (the times as they were and are, by the Owner given), the immutability trigger on
--      again (a confirmed row still refuses an update), no stock, state or other row touched, no sequence
--      used; a second run finds nothing to put right.
--
-- Disposable local database only (production as it is on 24 Oct 2026: 465 in); everything is rolled back.
-- Every name, email, order id and SKU is invented (T467, @example.com). It installs, inside this
-- transaction, production's bodies of current_user_role, user_has_store_access, require_active_staff and
-- resolve_tiktok_physical_return (the same block as shipped-then-cancelled-465.sql), then 465 (a shared
-- local database may not hold it), the fixtures with the old tiktok_parse_time, then 467 twice.
-- Run on its own, from the repository (V reads the preview file through git rev-parse):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/tiktok/tests/times-day-first-467.sql
-- Every check runs, then the file fails if any did.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

-- ═════ Production's bodies (24 Oct 2026) of the helpers a local copy may hold older ═════
CREATE OR REPLACE FUNCTION public.current_user_role()
 RETURNS user_role
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 406: the role of an ACTIVE member of staff, else null. A deactivated
  -- employee, a pending or cancelled invitee and a deleted profile are nobody,
  -- as in user_admin_role(). Every policy and function that reads this takes
  -- null to mean "not staff".
  select p.role from public.profiles p
   where p.id = auth.uid() and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted'
$function$;
CREATE OR REPLACE FUNCTION public.user_has_store_access(target_store_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: as before, every store for an active Owner or Admin, and their
  -- assigned stores for any other active member of staff. Active as in
  -- current_user_role(): active, not deleted, invitation accepted (before
  -- 430 it asked only "active").
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  -- STABLE. A read rule asks current_user_store_ids() once per query instead
  -- of calling this per row.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and (p.role in ('owner', 'admin')
                         or exists (select 1 from public.user_store_assignments usa
                                     where usa.user_id = p.id and usa.store_id = target_store_id)))
$function$;
CREATE OR REPLACE FUNCTION public.require_active_staff(p_roles text[] DEFAULT NULL::text[])
 RETURNS user_role
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role;
begin
  -- 406: the first statement of a staff page's server function. Being signed
  -- in does not make a login staff: affiliates sign in, a login could be
  -- created by anyone, and a deactivated employee keeps their password. Only an
  -- active, accepted, not-deleted profile passes (as in user_admin_role), and
  -- with p_roles only a profile whose role is one of them. Refused: 42501.
  --
  -- The server is not a login. The service role (website orders, the Edge
  -- Functions), pg_cron and migrations carry neither the anon nor the
  -- authenticated role, and pass; a request from a browser always carries one.
  if coalesce(auth.role(), '') not in ('anon', 'authenticated') then
    return null;
  end if;
  select p.role into v_role from public.profiles p
   where p.id = auth.uid() and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted';
  if v_role is null then
    raise exception 'Only active Energia staff can do this.' using errcode = '42501';
  end if;
  if p_roles is not null and not (v_role::text = any (p_roles)) then
    raise exception 'Your role cannot do this.' using errcode = '42501';
  end if;
  return v_role;
end
$function$;
revoke all on function public.require_active_staff(text[]) from public, anon, authenticated;
grant execute on function public.require_active_staff(text[]) to service_role;
CREATE OR REPLACE FUNCTION public.resolve_tiktok_physical_return(p_return_id uuid, p_restock boolean, p_reason text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_pr public.tiktok_physical_returns%rowtype; v_row public.tiktok_order_rows%rowtype; v_role user_role;
begin
  perform public.require_active_staff();  -- 406: active staff only
  v_role := public.current_user_role();
  select * into v_pr from public.tiktok_physical_returns where id = p_return_id for update;
  if not found then raise exception 'Physical return not found'; end if;
  -- Spec: Owner, Manager, or Staff assigned to the store.
  if not (v_role in ('owner','manager')
          or (v_role = 'staff' and public.user_has_store_access(v_pr.store_id))) then
    raise exception 'Only Owners, Managers or Staff assigned to this store can confirm physical returns'; end if;
  if v_pr.status <> 'awaiting' then raise exception 'This physical return is already resolved'; end if;

  if p_restock then
    if v_pr.order_row_id is not null then
      select * into v_row from public.tiktok_order_rows where id = v_pr.order_row_id;
      perform public.apply_tiktok_stock_delta(
        v_pr.store_id, v_row.matched_kind, v_row.matched_id, -v_pr.expected_qty,
        v_row.id, v_pr.order_id, v_pr.seller_sku, 'TikTok physical return');
    end if;
    update public.tiktok_order_state
       set deducted_qty = greatest(0, deducted_qty - v_pr.expected_qty), updated_at = now()
     where store_id = v_pr.store_id and order_id = v_pr.order_id and seller_sku = v_pr.seller_sku;
    update public.tiktok_physical_returns
       set status = 'restocked', resolved_by = auth.uid(), resolved_at = now(),
           resolution_reason = nullif(trim(coalesce(p_reason,'')),''), resolution_note = nullif(trim(coalesce(p_note,'')),'')
     where id = p_return_id;
  else
    if coalesce(p_reason,'') not in ('damaged','lost','not_received','other') then
      raise exception 'No Stock Return requires a reason: damaged, lost, not_received or other'; end if;
    if p_reason = 'other' and nullif(trim(coalesce(p_note,'')),'') is null then
      raise exception 'Please describe the reason when choosing "other"'; end if;
    update public.tiktok_physical_returns
       set status = 'no_restock', resolved_by = auth.uid(), resolved_at = now(),
           resolution_reason = p_reason, resolution_note = nullif(trim(coalesce(p_note,'')),'')
     where id = p_return_id;
  end if;

  perform public.write_audit_ex('tiktok_physical_returns', p_return_id,
    case when p_restock then 'tiktok_physical_return_restocked' else 'tiktok_physical_return_no_restock' end,
    null,
    jsonb_build_object('order_id', v_pr.order_id, 'seller_sku', v_pr.seller_sku,
                       'expected_qty', v_pr.expected_qty, 'reason', p_reason, 'note', p_note),
    'tiktok_import', p_reason, v_pr.store_id);
end $function$;

-- ═════ Helpers ═════
create temp table results(n serial, ok boolean, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  insert into results(ok, msg) values (coalesce(ok, false), msg);
  if ok is distinct from true then raise notice 'FAIL  %', msg; else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.row_counts() returns jsonb language plpgsql as
$$declare r record; n bigint; v jsonb := '{}'::jsonb;
begin
  for r in select c.oid::regclass::text as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname in ('public', 'auth') and c.relkind = 'r' order by 1 loop
    execute format('select count(*) from %s', r.t) into n;
    v := v || jsonb_build_object(r.t, n);
  end loop;
  return v;
end$$;
create function pg_temp.seqs() returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(sequencename, coalesce(last_value, 0)), '{}'::jsonb) from pg_sequences where schemaname = 'public' $$;
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language plpgsql as
$$begin
  perform set_config('search_path', 'public', true);
  return query select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
                 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
end$$;
-- An order row as the Import page sends it (the order id gets the run's suffix).
create function pg_temp.ln(ord text, st text, times jsonb) returns jsonb language sql as
$$ select jsonb_build_object('order_id', 'T467-' || pg_temp.tx('sfx') || '-' || ord, 'seller_sku', pg_temp.tx('sku'),
     'quantity', '1', 'order_status', pg_temp.tx(st), 'product_name', 'T467 item') || times $$;
create function pg_temp.oid_(ord text) returns text language sql as $$ select 'T467-' || pg_temp.tx('sfx') || '-' || ord $$;
create function pg_temp.stage(rows jsonb, file text) returns uuid language sql as
$$ select public.stage_tiktok_orders(pg_temp.fx('store'), 'T467 ' || file || '.csv', null, rows) $$;
-- A row's six times (rts, created, paid, shipped, delivered, cancelled; '-' none), and the same from literals.
create function pg_temp.times(ord text) returns text language sql as
$$ select array_to_string(array[r.rts_time, r.created_time, r.paid_time, r.shipped_time, r.delivered_time, r.cancelled_time]::text[], ' ', '-')
     from public.tiktok_order_rows r where r.order_id = pg_temp.oid_(ord) and r.store_id = pg_temp.fx('store') $$;
create function pg_temp.ts(variadic v text[]) returns text language sql as
$$ select array_to_string(v::timestamptz[]::text[], ' ', '-') $$;
create function pg_temp.row_id(ord text) returns uuid language sql as
$$ select id from public.tiktok_order_rows where order_id = pg_temp.oid_(ord) and store_id = pg_temp.fx('store') $$;
-- Every row of the table, whole (to tell what a run changed).
create function pg_temp.table_md5() returns text language sql as
$$ select md5(coalesce(string_agg(to_jsonb(o)::text, '|' order by o.id), '')) from public.tiktok_order_rows o $$;
create function pg_temp.others_md5() returns text language sql as
$$ select md5(coalesce(string_agg((to_jsonb(o) - array['rts_time', 'created_time', 'paid_time', 'shipped_time', 'delivered_time', 'cancelled_time'])::text, '|' order by o.id), ''))
     from public.tiktok_order_rows o $$;
create function pg_temp.trg_on() returns boolean language sql as
$$ select exists (select 1 from pg_trigger where tgrelid = 'public.tiktok_order_rows'::regclass and tgname = 'tiktok_row_immutable' and tgenabled = 'O') $$;
-- The repair's settings, for the next run.
create function pg_temp.settings(go text, actor text, expect text) returns void language sql as
$$ select set_config('repair467.go', coalesce(go, ''), false), set_config('repair467.actor', coalesce(actor, ''), false),
          set_config('repair467.expect', coalesce(expect, ''), false) $$;

-- The fixture rows' times as TikTok gives them, and what each must be stored as (UTC), month first
-- (before 467) and day first.
create temp table want(ord text primary key, old text, new text);
insert into want values
  ('A', pg_temp.ts('2026-04-10 07:00:00+00', '2026-03-10 02:00:00+00', '2026-03-10 02:01:00+00', '2026-05-10 01:00:00+00', '2026-08-10 04:00:00+00', null),
        pg_temp.ts('2026-10-04 07:00:00+00', '2026-10-03 02:00:00+00', '2026-10-03 02:01:00+00', '2026-10-05 01:00:00+00', '2026-10-08 04:00:00+00', null)),
  ('B', pg_temp.ts('2026-09-22 03:00:00+00', '2026-09-20 13:30:00+00', '2026-09-20 13:31:00+00', '2026-09-23 02:00:00+00', '2026-09-26 08:00:00+00', null),
        pg_temp.ts('2026-09-22 03:00:00+00', '2026-09-20 13:30:00+00', '2026-09-20 13:31:00+00', '2026-09-23 02:00:00+00', '2026-09-26 08:00:00+00', null)),
  ('C', pg_temp.ts(null, '2026-07-06 23:07:07+00', '2026-07-06 23:08:00+00', null, null, '2026-09-07 10:00:00+00'),
        pg_temp.ts(null, '2026-07-06 23:07:07+00', '2026-07-06 23:08:00+00', null, null, '2026-07-09 10:00:00+00')),
  ('D', pg_temp.ts(null, '2026-02-11 00:00:00+00', '2026-02-11 00:05:00+00', null, null, null),
        pg_temp.ts(null, '2026-11-02 00:00:00+00', '2026-11-02 00:05:00+00', null, null, null)),
  ('F', pg_temp.ts(null, '2026-01-09 01:15:00+00', null, null, null, null),
        pg_temp.ts(null, '2026-09-01 01:15:00+00', null, null, null, null)),
  ('E', pg_temp.ts(null, '2026-12-08 04:00:00+00', '2026-12-08 04:00:30+00', null, null, null),
        pg_temp.ts(null, '2026-08-12 04:00:00+00', '2026-08-12 04:00:30+00', null, null, null));
-- The eleven times stored month first that the repair must put right (for the future count).
create temp table swapped(v timestamptz);
insert into swapped values ('2026-04-10 07:00:00+00'), ('2026-03-10 02:00:00+00'), ('2026-03-10 02:01:00+00'), ('2026-05-10 01:00:00+00'),
  ('2026-08-10 04:00:00+00'), ('2026-09-07 10:00:00+00'), ('2026-02-11 00:00:00+00'), ('2026-02-11 00:05:00+00'),
  ('2026-01-09 01:15:00+00'), ('2026-12-08 04:00:00+00'), ('2026-12-08 04:00:30+00');

-- ═════ Fixtures (invented) ═════
do $$
declare o constant uuid := gen_random_uuid(); m constant uuid := gen_random_uuid(); st uuid;
  sfx constant text := lower(substr(md5(gen_random_uuid()::text), 1, 6)); p uuid;
begin
  insert into tx values ('sfx', sfx), ('sku', 'T467-SOAP-' || sfx),
    ('delivered', 'T467 Delivered ' || sfx), ('toship', 'T467 To Ship ' || sfx), ('cancel', 'T467 Canceled ' || sfx);
  insert into auth.users(id, email) values (o, 't467-owner-' || sfx || '@example.com'), (m, 't467-manager-' || sfx || '@example.com');
  insert into public.profiles(id, full_name, email, role, is_active)
  values (o, 'T467 Owner', 't467-owner-' || sfx || '@example.com', 'owner', true),
         (m, 'T467 Manager', 't467-manager-' || sfx || '@example.com', 'manager', true);
  insert into public.stores(name, code, country_code) values ('T467 Store ' || sfx, 'T467' || sfx, 'SG') returning id into st;
  insert into public.products(name, sku) values ('T467 Soap ' || sfx, 'T467P' || sfx) returning id into p;
  insert into fx values ('owner', o), ('manager', m), ('store', st), ('soap', p);
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 50);
  insert into public.tiktok_sku_aliases(store_id, seller_sku, target_kind, target_id, created_by)
  values (st, pg_temp.tx('sku'), 'product', p, o);
  insert into public.tiktok_status_mappings(status_label, status_norm, action, marks_shipped)
  select x.l, public.tiktok_norm_status(x.l), x.a, x.s
    from (values (pg_temp.tx('delivered'), 'deduct', true), (pg_temp.tx('toship'), 'deduct', false),
                 (pg_temp.tx('cancel'), 'return', false)) x(l, a, s);
end $$;
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);

-- ═════ 465 (production holds it; a shared local database may not) ═════
select (select md5 from pg_temp.fn_md5s() where fn = 'stage_tiktok_orders(uuid,text,text,jsonb)') = '9cad8a716950fdaab791f6f42cdddf7c' as has_465 \gset
\if :has_465
\else
\ir ../../../supabase/465_tiktok_shipped_then_cancelled_waits_for_return.sql
\endif
select set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);

-- ═════ P: before 467, the bug ═════
select pg_temp.check((select md5 from pg_temp.fn_md5s() where fn = 'tiktok_parse_time(text)') = 'd7b6de34d5f955479a4f97ea9df38b0c',
  'P tiktok_parse_time is the version production holds (64), as 467 expects');
select pg_temp.check(current_setting('DateStyle') = 'ISO, MDY', 'P DateStyle is production''s, ISO, MDY');
do $$ declare b uuid; r jsonb; begin
  b := pg_temp.stage(jsonb_build_array(
    pg_temp.ln('A', 'delivered', jsonb_build_object('created_time', '03/10/2026 10:00:00', 'paid_time', '03/10/2026 10:01:00',
      'rts_time', '04/10/2026 15:00:00', 'shipped_time', '05/10/2026 09:00:00', 'delivered_time', '08/10/2026 12:00:00')),
    pg_temp.ln('B', 'delivered', jsonb_build_object('created_time', '20/09/2026 21:30:00', 'paid_time', '20/09/2026 21:31:00',
      'rts_time', '22/09/2026 11:00:00', 'shipped_time', '23/09/2026 10:00:00', 'delivered_time', '26/09/2026 16:00:00')),
    pg_temp.ln('C', 'cancel', jsonb_build_object('created_time', '07/07/2026 07:07:07', 'paid_time', '07/07/2026 07:08:00',
      'cancelled_time', '09/07/2026 18:00:00'))), 'file 1');
  r := public.confirm_tiktok_batch(b, null, false, null);
  insert into fx values ('file1', b);
  b := pg_temp.stage(jsonb_build_array(
    pg_temp.ln('D', 'toship', jsonb_build_object('created_time', '02/11/2026 08:00:00', 'paid_time', '02/11/2026 08:05:00')),
    pg_temp.ln('F', 'toship', jsonb_build_object('created_time', '01/09/2026 9:15'))), 'file 2');
  insert into fx values ('file2', b);
  b := pg_temp.stage(jsonb_build_array(
    pg_temp.ln('E', 'toship', jsonb_build_object('created_time', '12/08/2026 12:00:00', 'paid_time', '12/08/2026 12:00:30'))), 'file 3');
  perform public.delete_tiktok_batch(b);
  insert into fx values ('file3', b);
end $$;
select pg_temp.check(pg_temp.times(w.ord) = w.old, 'P row ' || w.ord || ' stored as the old function reads it: ' || coalesce(pg_temp.times(w.ord), 'missing'))
  from want w order by w.ord;
select pg_temp.check((select bool_and(confirmed) from public.tiktok_order_rows where batch_id = pg_temp.fx('file1'))
                     and (select count(*) from public.tiktok_order_rows where batch_id = pg_temp.fx('file1')) = 3,
  'P file 1 confirmed: its three rows are immutable');
select pg_temp.check(pg_temp.err(format('update public.tiktok_order_rows set created_time = created_time where id = %L', pg_temp.row_id('A')))
                     like 'Confirmed import rows are immutable%', 'P a confirmed row refuses an update');
select pg_temp.check((select bool_and(not confirmed) from public.tiktok_order_rows where batch_id in (pg_temp.fx('file2'), pg_temp.fx('file3')))
                     and (select deleted_at is not null from public.tiktok_import_batches where id = pg_temp.fx('file3')),
  'P file 2 staged, file 3 staged and deleted');

-- ═════ M: install 467 (twice) ═════
create temp table snap(k text primary key, v jsonb);
insert into snap select 'rows', pg_temp.row_counts();
insert into snap select 'seqs', pg_temp.seqs();
insert into tx select 'table', pg_temp.table_md5();
create temp table md5_before as select * from pg_temp.fn_md5s();
\ir ../../../supabase/467_tiktok_times_read_day_first.sql
create temp table md5_once as select * from pg_temp.fn_md5s();
select pg_temp.check((select v from snap where k = 'rows') = pg_temp.row_counts(), 'M 467 leaves no row (its self-test is undone)');
select pg_temp.check((select v from snap where k = 'seqs') = pg_temp.seqs(), 'M 467 uses no sequence');
select pg_temp.check(pg_temp.table_md5() = pg_temp.tx('table'), 'M 467 changes no stored time');
select pg_temp.check(current_setting('DateStyle') = 'ISO, MDY', 'M 467 leaves the DateStyle as it was');
insert into tx select 'changed', string_agg(coalesce(a.fn, b.fn) || case when a.fn is null then ' added' when b.fn is null then ' dropped' else ' changed' end,
                                            ', ' order by coalesce(a.fn, b.fn) collate "C")
  from md5_before a full join md5_once b on b.fn = a.fn where a.md5 is distinct from b.md5;
select pg_temp.check(pg_temp.tx('changed') = 'tiktok_parse_time(text) changed',
  'M its first run changes tiktok_parse_time alone: ' || coalesce(pg_temp.tx('changed'), 'nothing'));
\ir ../../../supabase/467_tiktok_times_read_day_first.sql
select pg_temp.check(not exists (select 1 from md5_once a full join pg_temp.fn_md5s() b on b.fn = a.fn where a.md5 is distinct from b.md5),
  'M a second run changes nothing');
select set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select pg_temp.check((select md5 from pg_temp.fn_md5s() where fn = 'tiktok_parse_time(text)') = '9ab3b68b4fc30013d6bc75294d68bc66', 'M AFTER md5');
select pg_temp.check(p.provolatile = 'i' and not p.prosecdef and l.lanname = 'plpgsql' and p.proconfig = array['search_path=public'],
  'M IMMUTABLE plpgsql, no security definer, search_path public')
  from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = 'public.tiktok_parse_time(text)'::regprocedure;
select pg_temp.check(has_function_privilege('authenticated', 'public.tiktok_parse_time(text)', 'execute')
                     and has_function_privilege('service_role', 'public.tiktok_parse_time(text)', 'execute')
                     and not has_function_privilege('anon', 'public.tiktok_parse_time(text)', 'execute'),
  'M grants: signed-in staff and the service role, never anon');

-- ═════ G: the rule, under three DateStyles ═════
create temp table ex(t text, want timestamptz);
insert into ex values
  ('11/10/2026 19:02:31', '2026-10-11 11:02:31+00'), ('13/10/2026 15:32:09', '2026-10-13 07:32:09+00'),
  ('05/05/2026 08:00:00', '2026-05-05 00:00:00+00'), ('01/07/2026', '2026-06-30 16:00:00+00'),
  ('1/7/2026 9:05', '2026-07-01 01:05:00+00'), (' 01/07/2026 13:45 ', '2026-07-01 05:45:00+00'),
  ('02/03/2026 01:45:00 PM', '2026-03-02 05:45:00+00'), ('02/03/2026 12:10 AM', '2026-03-01 16:10:00+00'),
  ('02/03/2026 12:10 pm', '2026-03-02 04:10:00+00'), ('02/03/2026 00:10 AM', null), ('02/03/2026 13:10 PM', null),
  ('09.08.2026 10:00:00', '2026-08-09 02:00:00+00'), ('09-08-2026  10:00:00.250', '2026-08-09 02:00:00.25+00'),
  ('31/12/2026 23:59:59', '2026-12-31 15:59:59+00'), ('29/02/2028 10:00', '2028-02-29 02:00:00+00'),
  ('31/02/2026 10:00:00', null), ('29/02/2026', null), ('05/13/2026 10:00:00', null), ('00/07/2026', null),
  ('01/07/2026 25:00', null), ('01/07/2026 10:60', null),
  ('2026/09/07', '2026-09-06 16:00:00+00'), ('2026-07-01 13:45:00', '2026-07-01 05:45:00+00'),
  ('2026/07/01 13:45', '2026-07-01 05:45:00+00'), ('2026-07-01T13:45:00', '2026-07-01 05:45:00+00'),
  ('2026-13-01', null), ('1 Jul 2026 13:45', '2026-07-01 05:45:00+00'),
  ('01/07/26', null), ('01 07 2026', null), ('now', null), ('epoch', null), ('', null), ('   ', null), (null, null);
do $$ declare s text; e record; got timestamptz; begin
  foreach s in array array['ISO, MDY', 'ISO, DMY', 'SQL, DMY'] loop
    perform set_config('DateStyle', s, true);
    for e in select * from ex loop
      got := public.tiktok_parse_time(e.t);
      perform pg_temp.check(got is not distinct from e.want,
        format('G %s: %s -> %s', s, coalesce(quote_literal(e.t), 'null'), coalesce(got::text, 'null')));
    end loop;
  end loop;
  perform set_config('DateStyle', 'ISO, MDY', true);
end $$;

-- ═════ N: after 467, files store their times day first ═════
do $$ declare b uuid; begin
  b := pg_temp.stage(jsonb_build_array(
    pg_temp.ln('N', 'delivered', jsonb_build_object('created_time', '03/10/2026 10:00:00', 'paid_time', '03/10/2026 10:01:00',
      'rts_time', '04/10/2026 15:00:00', 'shipped_time', '05/10/2026 09:00:00', 'delivered_time', '08/10/2026 12:00:00'))), 'file 4');
  perform pg_temp.check(pg_temp.times('N') = (select new from want where ord = 'A'),
    'N a file staged after 467 stores its times day first: ' || coalesce(pg_temp.times('N'), 'missing'));
  -- Staged only (as an unconfirmed file is): the repair has nothing to do for it.
  b := public.stage_tiktok_settlement(pg_temp.fx('store'), 'T467 settlement.xlsx', 'Order details', jsonb_build_array(
    jsonb_build_object('order_id', pg_temp.oid_('A'), 'transaction_type', 'Order', 'settlement_amount', '9.50',
      'revenue_amount', '10.00', 'fee_amount', '-0.50', 'currency', 'SGD',
      'order_created_time', '2026/10/03', 'settled_time', '2026/10/09')));
  perform pg_temp.check((select (order_created_time, settled_time) = ('2026-10-02 16:00:00+00'::timestamptz, '2026-10-08 16:00:00+00'::timestamptz)
                           from public.tiktok_settlement_rows where batch_id = b),
    'N a settlement file''s YYYY/MM/DD times are read as before');
end $$;

-- ═════ V: the preview ═════
\set preview_sql `cat "$(git rev-parse --show-toplevel)/scripts/tiktok/repair/467-restore-tiktok-order-times-preview.sql"`
create temp table pv as :preview_sql
select pg_temp.check((select (times, rows, confirmed_rows, rows_of_deleted_files, moves_month, right_is_null)
                        = (11::bigint, 5::bigint, 2::bigint, 1::bigint, 11::bigint, 0::bigint) from pv where column_ = 'all six'),
  'V in all: 11 times on 5 rows (A and C confirmed, E of a deleted file), every one a month off: '
  || (select row_to_json(pv)::text from pv where column_ = 'all six'));
select pg_temp.check((select stored_in_future from pv where column_ = 'all six') = (select count(*) from swapped where v > now()),
  'V the times stored in the future are counted');
select pg_temp.check((select jsonb_object_agg(column_, times) from pv where column_ <> 'all six')
                     = '{"created_time": 4, "paid_time": 3, "rts_time": 1, "shipped_time": 1, "delivered_time": 1, "cancelled_time": 1}',
  'V by column: ' || (select jsonb_object_agg(column_, times)::text from pv where column_ <> 'all six'));

-- ═════ R: the repair ═════
\set repair_sql `cat "$(git rev-parse --show-toplevel)/scripts/tiktok/repair/467-restore-tiktok-order-times.sql"`
delete from snap; delete from tx where k = 'table';
insert into snap select 'rows', pg_temp.row_counts();
insert into snap select 'seqs', pg_temp.seqs();
insert into tx select 'table', pg_temp.table_md5();
insert into tx select 'others', pg_temp.others_md5();
-- R1 without the go-ahead: checks, counts, changes nothing.
select pg_temp.settings(null, null, null);
\ir ../repair/467-restore-tiktok-order-times.sql
select pg_temp.check(pg_temp.table_md5() = pg_temp.tx('table') and (select v from snap where k = 'rows') = pg_temp.row_counts() and pg_temp.trg_on(),
  'R1 without the go-ahead nothing changes');
-- R2 refusals: no Owner, a Manager, no count, another count.
select pg_temp.settings('yes', null, '11');
select pg_temp.check(pg_temp.err(:'repair_sql') like '%repair467.actor is not an active Owner%', 'R2 refused without an Owner');
select pg_temp.settings('yes', 'not-an-id', '11');
select pg_temp.check(pg_temp.err(:'repair_sql') like '%repair467.actor must be a profile id%', 'R2 refused with an actor that is not an id');
select pg_temp.settings('yes', pg_temp.fx('manager')::text, '11');
select pg_temp.check(pg_temp.err(:'repair_sql') like '%repair467.actor is not an active Owner%', 'R2 refused with a Manager');
select pg_temp.settings('yes', pg_temp.fx('owner')::text, null);
select pg_temp.check(pg_temp.err(:'repair_sql') like '%give repair467.expect%', 'R2 refused without the approved count');
select pg_temp.settings('yes', pg_temp.fx('owner')::text, '10');
select pg_temp.check(pg_temp.err(:'repair_sql') like '%11 time(s) to put right now, not the 10 approved%', 'R2 refused with another count');
select pg_temp.check(pg_temp.table_md5() = pg_temp.tx('table') and (select v from snap where k = 'rows') = pg_temp.row_counts() and pg_temp.trg_on(),
  'R2 each refusal changes nothing and leaves the trigger on');
-- R3 a stored time neither reading explains (a staged row edited by hand): refused, naming it.
update public.tiktok_order_rows set created_time = '2026-01-01 00:00:00+00' where id = pg_temp.row_id('D');
select pg_temp.settings('yes', pg_temp.fx('owner')::text, '11');
select pg_temp.err(:'repair_sql') as r3 \gset
select pg_temp.check(:'r3' like '%neither 467''s reading%' || pg_temp.row_id('D') || ' created_time%', 'R3 refused, naming the row and column: ' || :'r3');
update public.tiktok_order_rows set created_time = '2026-02-11 00:00:00+00' where id = pg_temp.row_id('D');
select pg_temp.check(pg_temp.table_md5() = pg_temp.tx('table') and pg_temp.trg_on(), 'R3 nothing changed (the hand edit put back)');
-- R3b a failure after the trigger is switched off (an update the table refuses): all of it undone, the trigger on.
alter table public.tiktok_order_rows add constraint t467_refuse check (created_time is distinct from '2026-10-03 02:00:00+00') not valid;
select pg_temp.settings('yes', pg_temp.fx('owner')::text, '11');
select pg_temp.err(:'repair_sql') as r3b \gset
select pg_temp.check(:'r3b' like '%t467_refuse%', 'R3b the update is refused after the switch-off: ' || :'r3b');
select pg_temp.check(pg_temp.table_md5() = pg_temp.tx('table') and pg_temp.trg_on()
                     and (select count(*) from public.audit_logs where action = 'tiktok_order_times_restored') = 0,
  'R3b all of it undone: no time changed, no audit row, the trigger on');
alter table public.tiktok_order_rows drop constraint t467_refuse;
-- R4 with the go-ahead.
select pg_temp.settings('yes', pg_temp.fx('owner')::text, '11');
\ir ../repair/467-restore-tiktok-order-times.sql
select pg_temp.check(pg_temp.times(w.ord) = w.new, 'R4 row ' || w.ord || ' read day first: ' || coalesce(pg_temp.times(w.ord), 'missing'))
  from want w order by w.ord;
select pg_temp.check(pg_temp.times('N') = (select new from want where ord = 'A'), 'R4 the row staged after 467 is untouched');
select pg_temp.check(pg_temp.others_md5() = pg_temp.tx('others'), 'R4 nothing but the six times changed, on any row');
select pg_temp.check(pg_temp.trg_on(), 'R4 the immutability trigger is on again');
select pg_temp.check(pg_temp.err(format('update public.tiktok_order_rows set created_time = created_time where id = %L', pg_temp.row_id('A')))
                     like 'Confirmed import rows are immutable%', 'R4 a confirmed row still refuses an update');
select pg_temp.check((select count(*) from public.audit_logs a where a.action = 'tiktok_order_times_restored') = 5
                     and (select bool_and(a.changed_by = pg_temp.fx('owner') and a.actor_role = 'owner' and a.table_name = 'tiktok_order_rows'
                                           and a.module = 'tiktok_import' and a.store_id = pg_temp.fx('store'))
                            from public.audit_logs a where a.action = 'tiktok_order_times_restored'),
  'R4 one audit row per row put right (5), by the Owner given');
select pg_temp.check((select (a.old_data->>'created_time')::timestamptz = '2026-03-10 02:00:00+00'
                             and (a.new_data->>'created_time')::timestamptz = '2026-10-03 02:00:00+00'
                             and (select count(*) from jsonb_object_keys(a.old_data)) = 5
                             and not a.old_data ? 'cancelled_time'
                        from public.audit_logs a where a.action = 'tiktok_order_times_restored' and a.record_id = pg_temp.row_id('A')),
  'R4 row A''s audit row holds its five times as they were and are');
select pg_temp.check((select jsonb_object_keys(a.old_data) from public.audit_logs a
                       where a.action = 'tiktok_order_times_restored' and a.record_id = pg_temp.row_id('C')) = 'cancelled_time',
  'R4 row C''s audit row holds its cancelled time alone');
select (select jsonb_object_agg(a.key, b.value::bigint - a.value::bigint) from jsonb_each_text((select v from snap where k = 'rows')) a
          full join jsonb_each_text(pg_temp.row_counts()) b using (key) where a.value is distinct from b.value)::text as r4_rows \gset
select pg_temp.check(:'r4_rows'::jsonb = jsonb_build_object('audit_logs'::regclass::text, 5),
  'R4 no row added or removed but the 5 audit rows (no stock, state or other row touched): ' || :'r4_rows');
select pg_temp.check((select v from snap where k = 'seqs') = pg_temp.seqs(), 'R4 no sequence used');
select pg_temp.check((select qty from (select current_qty as qty from public.store_inventory
                       where store_id = pg_temp.fx('store') and product_id = pg_temp.fx('soap')) s) = 48,
  'R4 stock as file 1 left it (A and B, 50 -> 48)');
-- R5 the preview, and a second run: nothing to put right.
insert into tx select 'after', pg_temp.table_md5();
create temp table pv2 as :preview_sql
select pg_temp.check((select times from pv2 where column_ = 'all six') = 0, 'R5 the preview counts nothing left');
\ir ../repair/467-restore-tiktok-order-times.sql
select pg_temp.check(pg_temp.table_md5() = pg_temp.tx('after') and pg_temp.trg_on()
                     and (select count(*) from public.audit_logs a where a.action = 'tiktok_order_times_restored') = 5,
  'R5 a second run changes nothing');

do $$ declare v_failed int; v_all int; begin
  select count(*) filter (where not ok), count(*) into v_failed, v_all from results;
  if v_failed > 0 then
    raise exception '% of % check(s) failed: %', v_failed, v_all, (select string_agg(msg, '; ' order by n) from results where not ok); end if;
  raise notice 'All % 467 checks passed.', v_all;
end $$;
rollback;
