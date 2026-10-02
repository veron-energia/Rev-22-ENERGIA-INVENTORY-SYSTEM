-- 382_free_guests_in_the_sync.sql
--
-- FREE GUESTS COME TO THE WEBSITE'S SHEET TOO (the owner's request, 2 Oct
-- 2026: "add the free guests to the tab too")
--
--   380 lets an event website ask for its orders and the tickets sold at the
--   counter (web_order_sync), which it writes to the event's Google tab. Free
--   guests (event_guests with source 'free', added on the Event page's Guests
--   tab) were not in that answer, so the tab never had them, while the
--   owner's older tabs list them with "Free" as the invoice number.
--
--   Now web_order_sync's 'ok' answer also carries "free": every free guest of
--   the channel's event, cancelled ones too, oldest first (created_at, id),
--   each as {order_id, name, phone, email, days, status, registered_by,
--   notes, date}:
--   1. order_id is the guest's row on the sheet, and never changes: "FREE-"
--      and the first 8 hex digits of the guest's id, in capitals. Should two
--      free guests of one event share those 8 (practically never), the later
--      one (created_at, id) takes 12, so the earlier keeps its key.
--   2. phone is the guest's, else their customer's; email is their
--      customer's, else none.
--   3. days are the days they are coming; status is 'registered' or
--      'cancelled' (the website only marks a cancelled guest on a row it
--      already has, and takes the mark off when they are restored).
--   4. registered_by is the name of the staff member who registered them,
--      notes their notes, and date the day they were added (Singapore).
--   Attendance stays on the Event page: it is not sent.
--
--   Nothing else changes: the event, the orders, the counter sales, the
--   once-a-minute limit and the too_soon and refused answers are 380's, word
--   for word. Only the service role may call it, as before.
--
-- DEPLOY ORDER: any. The edge function deployed now keeps only the keys it
-- knows, so it drops "free" until the new one (which passes it on, and sends
-- none for a database without this) is deployed; the website reads "free" as
-- optional.
--
-- SAFETY: web_order_sync must be 380's (md5 of prosrc, as in production on
-- 2 Oct 2026) or this file's own, so it can be run again; the check runs
-- before anything changes. Apply in one transaction (the Supabase migration
-- tool does). No table changes. NOTE: running 380 again after this puts back
-- 380's web_order_sync (380 does not guard it); run this again after it.
--
-- AFTER (md5(prosrc), checked on a local copy whose web_order_sync matched
-- production, 2 Oct 2026):
--   web_order_sync(text)  66c1e0a731ef9972242401dc21df7afe

set lock_timeout = '5s';

-- ── 0. The version this was tested against ─────────────────────────────────
do $$ begin
  if to_regprocedure('public.web_order_sync(text)') is null then
    raise exception '382: apply 380 (staff-link orders) first'; end if;
  -- 380's (production's), or this file's own (a second run).
  if (select md5(prosrc) from pg_proc where oid = 'public.web_order_sync(text)'::regprocedure)
     <> all (array['8ef0796822369dbceac26c16556506a7', '66c1e0a731ef9972242401dc21df7afe']) then
    raise exception '382: public.web_order_sync(text) is not the version this was tested against'; end if;
end $$;

-- ── 1. The sync, with the free guests ──────────────────────────────────────
-- What the website's sheet needs: the event, every website and staff-link
-- order (not refused, not test) with its invoice and people, every invoice
-- that sold tickets to the event at the counter (no website order's),
-- deleted ones too once a sync has listed them (invoice_status 'deleted',
-- their people cancelled), and (382) every free guest of the event. People
-- come by their numbers on the sheet, given here the first time. At most once
-- a minute per channel: sooner is 'too_soon', with nothing else.
create or replace function public.web_order_sync(p_channel text)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype;
begin
  -- One sync at a time per channel. Not FOR UPDATE: every new web order
  -- takes a key-share lock on its channel, which that would wait for.
  select * into ch from public.web_order_channels where key = p_channel for no key update;
  if not found then return jsonb_build_object('status', 'refused'); end if;
  if ch.last_sync_at > now() - interval '60 seconds' then return jsonb_build_object('status', 'too_soon'); end if;
  update public.web_order_channels set last_sync_at = now() where key = ch.key;
  perform public.web_order_number_people(ch.event_id, null);
  return jsonb_build_object(
    'status', 'ok',
    'event', (select jsonb_build_object('name', e.name,
                       'days', coalesce((select jsonb_agg(to_char(d.day, 'YYYY-MM-DD') order by d.day)
                                           from public.event_days d where d.event_id = e.id), '[]'::jsonb))
                from public.events e where e.id = ch.event_id),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id', o.stripe_session_id, 'provider', o.provider, 'status', o.status,
               'invoice_no', i.invoice_no,
               'invoice_status', case when i.id is null then null when i.deleted_at is not null then 'deleted' else i.status::text end,
               'date', to_char(coalesce(o.paid_on, (o.paid_at at time zone 'Asia/Singapore')::date), 'YYYY-MM-DD'),
               'buyer_name', o.buyer_name, 'buyer_phone', o.buyer_phone, 'buyer_email', o.buyer_email,
               'ticket', o.ticket, 'quantity', o.quantity,
               'method', case when o.provider = 'door' then public.web_order_door_method_name(o.door_method)
                              else public.web_order_provider_name(o.provider) end,
               'reference', case when o.provider = 'door' then o.payment_reference else o.stripe_payment_intent end,
               'staff_name', sp.full_name,
               'people', case when i.id is not null then public.web_order_invoice_people(i.id, ch.event_id, o, false)
                              else public.web_order_sync_people(o, ch) end)
             order by o.paid_at, o.created_at)
        from public.web_orders o
        left join public.invoices i on i.id = o.invoice_id
        left join public.profiles sp on sp.id = o.staff_profile_id
       where o.channel = ch.key and o.status <> 'refused' and o.livemode), '[]'::jsonb),
    'counter', coalesce((
      select jsonb_agg(jsonb_build_object(
               'invoice_no', i.invoice_no,
               'invoice_status', case when i.deleted_at is not null then 'deleted' else i.status::text end,
               'date', to_char(i.business_date, 'YYYY-MM-DD'),
               'customer_name', c.full_name, 'phone', c.phone, 'email', c.email,
               'methods', public.web_order_invoice_methods(i.id),
               'staff_name', coalesce((select string_agg(p.full_name, ', ' order by p.full_name)
                                         from public.invoice_service_staff ss join public.profiles p on p.id = ss.staff_id
                                        where ss.invoice_id = i.id),
                                      (select p.full_name from public.profiles p where p.id = i.created_by)),
               'people', public.web_order_invoice_people(i.id, ch.event_id, null, true))
             order by i.business_date, i.invoice_no)
        from public.invoices i
        left join public.customers c on c.id = i.customer_id
       where (i.deleted_at is null
              or exists (select 1 from public.web_order_sync_positions n where n.event_id = ch.event_id and n.invoice_id = i.id))
         and i.id in (select g.invoice_id from public.event_guests g
                       where g.event_id = ch.event_id and g.source = 'ticket' and g.invoice_id is not null)
         and not exists (select 1 from public.web_orders w where w.invoice_id = i.id)), '[]'::jsonb),
    -- 382: every free guest of the event, cancelled ones too, oldest first.
    -- The key is FREE- and the first 8 hex digits of the guest's id; when an
    -- earlier free guest of the event has the same 8, the later one takes 12.
    'free', coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id', 'FREE-' || upper(left(f.hex, case when f.nth = 1 then 8 else 12 end)),
               'name', f.name, 'phone', f.phone, 'email', f.email, 'days', f.days, 'status', f.status,
               'registered_by', f.registered_by, 'notes', f.notes, 'date', f.added_on)
             order by f.created_at, f.id)
        from (select g.id, g.created_at, g.name, g.status, replace(g.id::text, '-', '') as hex,
                     row_number() over (partition by left(replace(g.id::text, '-', ''), 8) order by g.created_at, g.id) as nth,
                     coalesce(nullif(btrim(g.phone), ''), nullif(btrim(c.phone), '')) as phone,
                     nullif(btrim(c.email), '') as email,
                     coalesce((select jsonb_agg(to_char(gd.day, 'YYYY-MM-DD') order by gd.day)
                                 from public.event_guest_days gd where gd.guest_id = g.id), '[]'::jsonb) as days,
                     rb.full_name as registered_by, nullif(btrim(g.notes), '') as notes,
                     to_char((g.created_at at time zone 'Asia/Singapore')::date, 'YYYY-MM-DD') as added_on
                from public.event_guests g
                left join public.customers c on c.id = g.customer_id
                left join public.profiles rb on rb.id = g.registered_by
               where g.event_id = ch.event_id and g.source = 'free') f), '[]'::jsonb));
end $f$;

-- ── 2. Who may call it ─────────────────────────────────────────────────────
-- As 380 left it: the service role (the edge function) only.
revoke all on function public.web_order_sync(text) from public, anon, authenticated;
grant execute on function public.web_order_sync(text) to service_role;

notify pgrst, 'reload schema';
