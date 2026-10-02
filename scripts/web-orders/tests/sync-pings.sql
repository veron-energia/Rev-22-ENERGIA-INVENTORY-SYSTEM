-- Website sync pings (381, on 380).
--
--   P1 With no channel's sync_url set, the ping asks no one.
--   P2 It asks each channel with a sync_url that is not off, until 14 days
--      after its event's last day (Singapore), posting {"channel": key} as
--      JSON and nothing else; an off channel, one with no sync_url, and an
--      event over for longer are left alone. Nothing is sent before the
--      transaction commits (pg_net), so this file sends nothing.
--   P3 A sync_url must be https.
--   P4 One job runs it every 10 minutes.
--   P5 No client role can run it.
--
-- Run after 381. pg_cron can only be installed in the database named by
-- cron.database_name; on a local copy that is another database, apply 381
-- with its pg_cron line replaced by a stand-in cron.job / cron.schedule (by
-- name, as pg_cron 1.6 schedules), as the 2 Oct 2026 checks did.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- The posts this transaction queued, by url.
create function pg_temp.queued(p_url text) returns jsonb language sql as
$$ select coalesce(jsonb_agg(jsonb_build_object('method', q.method, 'body', convert_from(q.body, 'utf8')::jsonb,
                                               'content_type', q.headers->>'Content-Type') order by q.id), '[]'::jsonb)
     from net.http_request_queue q where q.url = p_url $$;

-- ═════ Fixtures ═════
-- Every channel already there stops asking for this file (rolled back).
update public.web_order_channels set sync_url = null;
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; st uuid; pm uuid; k text; ev uuid; n int;
begin
  u := gen_random_uuid();
  insert into auth.users(id, email) values (u, 'p381-' || sfx || '@tests.invalid');
  insert into profiles(id, full_name, email, role) values (u, 'P381 Owner', 'p381-' || sfx || '@tests.invalid', 'owner');
  insert into stores(name, code, country_code) values ('P381 Van ' || sfx, 'P381V' || sfx, 'SG') returning id into st;
  select id into pm from public.payment_methods where name = 'Stripe (online)';
  -- Events whose last day was 10, 14 and 15 days ago, and one next week.
  foreach n in array array[-10, -14, -15, 7] loop
    insert into public.events(name) values ('P381 Event ' || n || ' ' || sfx) returning id into ev;
    insert into public.event_days(event_id, day) values (ev, pg_temp.d(n - 1)), (ev, pg_temp.d(n));
    insert into fx values ('ev' || n, ev);
  end loop;
  foreach k in array array['live', 'record', 'off', 'none', 'over', 'edge'] loop
    insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id, mode)
    values ('p381-' || k || '-' || sfx,
            pg_temp.fx(case k when 'over' then 'ev-15' when 'edge' then 'ev-14' when 'live' then 'ev7' else 'ev-10' end),
            '{}'::jsonb, st, u, pm, case k when 'off' then 'off' when 'record' then 'record_only' else 'live' end);
  end loop;
  create temp table keys(k text primary key, key text);
  insert into keys select x.kind, 'p381-' || x.kind || '-' || sfx from unnest(array['live','record','off','none','over','edge']) x(kind);
end $$;
create function pg_temp.key(k text) returns text language sql as $$ select key from keys where keys.k = $1 $$;
create function pg_temp.url(k text) returns text language sql as $$ select 'https://p381.tests.invalid/' || $1 || '/api/inventory/sync' $$;

-- ═════ P1 No sync_url, no ping ═════
do $$ declare v_before bigint; v_asked int; begin
  select count(*) into v_before from net.http_request_queue;
  v_asked := public.web_order_sync_ping();
  create temp table p1 as select v_asked as asked, (select count(*) from net.http_request_queue) - v_before as queued;
end $$;
select pg_temp.check((select (asked, queued) = (0, 0) from p1), 'P1 with no channel''s sync_url set, the ping asks no one');

-- ═════ P2 Who is asked ═════
update public.web_order_channels set sync_url = pg_temp.url(k.k) from keys k
 where web_order_channels.key = k.key and k.k <> 'none';
do $$ begin
  create temp table p2 as select public.web_order_sync_ping() as asked;
end $$;
select pg_temp.check((select asked from p2) = 3
    and pg_temp.queued(pg_temp.url('live')) = jsonb_build_array(jsonb_build_object('method', 'POST',
          'body', jsonb_build_object('channel', pg_temp.key('live')), 'content_type', 'application/json'))
    and jsonb_array_length(pg_temp.queued(pg_temp.url('record'))) = 1
    and jsonb_array_length(pg_temp.queued(pg_temp.url('edge'))) = 1,
  'P2 a live or record-only channel with a sync_url is asked, until 14 days after its event, with {"channel": key} as JSON');
select pg_temp.check(pg_temp.queued(pg_temp.url('off')) = '[]'::jsonb
    and pg_temp.queued(pg_temp.url('over')) = '[]'::jsonb
    and not exists (select 1 from net.http_request_queue where url like '%/none/%'),
  'P2 an off channel, a channel with no sync_url and an event over for more than 14 days are not asked');

-- ═════ P3 https only ═════
select pg_temp.check(
    pg_temp.err(format('update public.web_order_channels set sync_url = %L where key = %L', 'http://p381.tests.invalid/x', pg_temp.key('none')))
      ~ 'web_order_channels_sync_url'
    and pg_temp.err(format('update public.web_order_channels set sync_url = %L where key = %L', 'https://p381.tests.invalid/a b', pg_temp.key('none')))
      ~ 'web_order_channels_sync_url',
  'P3 a sync_url must be https, with no spaces');

-- ═════ P4 The job ═════
select pg_temp.check((select count(*) from cron.job where jobname = 'web-order-sync-ping') = 1
    and (select (schedule, command) = ('*/10 * * * *', 'select public.web_order_sync_ping()')
           from cron.job where jobname = 'web-order-sync-ping'),
  'P4 one job runs the ping every 10 minutes');

-- ═════ P5 Who may run it ═════
select pg_temp.check(not has_function_privilege('authenticated', 'public.web_order_sync_ping()', 'execute')
    and not has_function_privilege('anon', 'public.web_order_sync_ping()', 'execute'),
  'P5 no client role can run the ping');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All sync ping checks passed.';
end $$;
rollback;
