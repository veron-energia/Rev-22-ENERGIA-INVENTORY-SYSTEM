-- 381_website_sync_pings.sql
--
-- THE INVENTORY TELLS AN EVENT WEBSITE TO SYNC, EVERY 10 MINUTES (2 Oct 2026)
--
--   380 lets an event website ask for its orders' invoice numbers and the
--   tickets sold at the counter (web_order_sync), so the website can keep its
--   Google sheet complete. The website runs on Vercel's Hobby plan, whose cron
--   runs at most once a day, so the inventory nudges it instead:
--
--   1. web_order_channels.sync_url: where a channel's website takes the nudge
--      (https only). Null, as every channel starts, means no nudges.
--   2. web_order_sync_ping() posts {"channel": "<key>"} to each channel's
--      sync_url while the channel is not off and until 14 days after the
--      event's last day (Singapore). The post is not signed and carries
--      nothing else: it only asks the website to sync, and the website then
--      asks web_order_sync through the signed edge function, which answers at
--      most once a minute. With no sync_url anywhere it does nothing.
--   3. pg_cron runs it every 10 minutes (job 'web-order-sync-ping'), through
--      pg_net, which sends the posts after the job's transaction commits.
--
-- Separate from 380 so 380 can be applied without it. It installs pg_net and
-- pg_cron (available on the project, not yet installed). Re-runnable: the
-- extensions, the column and the check are only added when missing, the
-- function is replaced, and cron.schedule replaces a job of the same name.
-- Apply in one transaction (the Supabase migration tool does). To start the
-- nudges for a channel, an Owner sets its sync_url (e.g. the website's
-- https://<site>/api/inventory/sync); to stop them, set it back to null.

set lock_timeout = '5s';

do $$ begin
  if to_regprocedure('public.web_order_sync(text)') is null then
    raise exception '381: apply 380 (staff-link orders) first'; end if;
end $$;

-- ── 1. The extensions (as Supabase installs them) ──────────────────────────
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
-- Installing pg_net makes Supabase (its grant_pg_net_access trigger, as
-- supabase_admin) grant anon and authenticated the net schema and
-- net.http_get / net.http_post, as on every project with pg_net. This file
-- runs as postgres, which cannot take back supabase_admin's grants (a revoke
-- only warns "no privileges could be revoked"), and nothing here needs them:
-- the ping runs as its owner. Those roles reach net.* only through SQL, never
-- through the API, while the net schema is not one the API exposes: keep it
-- out of the project's exposed schemas.

-- ── 2. Where a channel's website takes the nudge ───────────────────────────
alter table public.web_order_channels add column if not exists sync_url text;
alter table public.web_order_channels drop constraint if exists web_order_channels_sync_url;
alter table public.web_order_channels add constraint web_order_channels_sync_url
  check (sync_url is null or sync_url ~ '^https://[^[:space:]]+$');

-- ── 3. The nudge ───────────────────────────────────────────────────────────
-- Asks each channel's website to sync: those with a sync_url, not off, until
-- 14 days after the event's last day. Returns how many were asked. pg_net
-- queues each post and sends it after this transaction commits.
create or replace function public.web_order_sync_ping()
returns integer language plpgsql security definer set search_path to 'public' as $f$
declare ch record; n integer := 0;
begin
  for ch in select c.key, c.sync_url from public.web_order_channels c
             where c.sync_url is not null and c.mode <> 'off'
               and (select max(d.day) from public.event_days d where d.event_id = c.event_id) + 14
                   >= (now() at time zone 'Asia/Singapore')::date
             order by c.key loop
    perform net.http_post(url := ch.sync_url, body := jsonb_build_object('channel', ch.key),
                          headers := jsonb_build_object('Content-Type', 'application/json'),
                          timeout_milliseconds := 10000);
    n := n + 1;
  end loop;
  return n;
end $f$;
revoke all on function public.web_order_sync_ping() from public, anon, authenticated;
grant execute on function public.web_order_sync_ping() to service_role;

-- ── 4. Every 10 minutes ────────────────────────────────────────────────────
select cron.schedule('web-order-sync-ping', '*/10 * * * *', 'select public.web_order_sync_ping()');

notify pgrst, 'reload schema';
