-- 454_affiliate_portal_seminar_link.sql
--
-- THE AFFILIATE PORTAL SHOWS EACH AFFILIATE THEIR SHORT SEMINAR LINK
-- (<site>/<referral code>) BESIDE THEIR FREE THERAPY LINK (the owner's change
-- list, 22 Oct 2026, item 8)
--
-- WHAT WAS WRONG / WHY
--
--   An affiliate's referral code already works on the seminar website: its
--   /signup/<code> page says who invited the visitor and sends the code with
--   the registration, and the app's rules decide whether it counts (436, 439,
--   440, 449, 450: a new person becomes the affiliate's referral, an existing
--   customer keeps their own referrer, a self-referral is refused or held,
--   commission only on VIP). But no affiliate was shown that link anywhere.
--   The portal's My Referral QR page (AffiliateReferralPage.tsx) shows only
--   the app's /r/<code> page (the free therapy giveaway, 392), and
--   affiliate_portal_referral_info (155; no later file redefines it) returns
--   referral_code, accepting and direct_referrals: nothing about events. The
--   seminar site's address is known only from the Event page's Website tab
--   (event_web_settings.sync_url; event_web_settings_get reads site_url from
--   it).
--   The seminar site itself gains the short address /<CODE> in its own
--   repository (src/app/[code]/page.tsx: a code shaped as the app makes them
--   goes to /signup/<CODE>; another word shaped like a code, such as a page
--   name typed in capitals, goes to the event page itself, which keeps no
--   code, so an earlier affiliate's link stays the visitor's; anything that
--   can't be a code is the 404 page). No database change is needed for that:
--   event_web_register takes registration.referral_code whatever address it
--   came from.
--
-- THE RULES (binding)
--
--   The owner's change list, 22 Oct 2026, item 8: "Affiliate referral code as
--   the seminar link (healthtalk-rev22energia.vercel.app/<code>)", with the
--   portal showing each affiliate their seminar link(s), copied and shared
--   like the existing link, and the existing card labelled as the free
--   therapy link. The owner, 22 Oct 2026: an unknown code still shows the
--   seminar page (as /signup/<code> does today); that is the site's, which
--   hands /<CODE> to /signup/<CODE> (another word shaped like a code to the
--   event page itself, which keeps no code).
--   How it reads (this file, 22 Oct 2026):
--   * A link is listed for each event whose website takes registrations now,
--     as the website itself judges it (event_web_open_state's closed_reason
--     is null: the event not deleted, its website not Off (Record only or
--     Live), tickets on sale, and a day still open, in Singapore time). So it
--     appears while the website is switched on and disappears once the
--     event is over, with no change for the next seminar.
--   * The address is the site's: the origin of the Website tab's sync URL,
--     read as event_web_settings_get reads site_url (substring(sync_url from
--     '^(https://[^/]+)')), then '/' and the affiliate's referral code. No
--     sync URL: no link (the site's address is not known).
--   * Only a code the site's short link takes as one gets a link: the shape
--     generate_affiliate_referral_code (155) gives every code, EN and six of
--     0-9 and A-Z without I, L, O and U (^EN[0-9A-HJKMNP-TV-Z]{6}$; the site's
--     [code] page tests the same). So the portal never shows a link the site
--     answers with its 404 page or its event page without the code.
--   * One link per address. The site serves one event (its own event code),
--     so when two events taking registrations share a site (the next seminar
--     set up on it before this one ends), the link is listed once, under the
--     event the site last synced as (event_web_settings.last_sync_at, which
--     only the site's own sync sets), else the earliest.
--   * Each link carries the event's name, its first and last day and the
--     address: nothing else (no store, venue, counts or other people).
--   * The page shows them while the affiliate is accepting referrals, as it
--     does the free therapy link (a suspended affiliate's link is switched
--     off on the website too: event_web_referral_info, unchanged).
--
-- WHAT THIS DOES
--
--   1. affiliate_portal_referral_info() (the affiliate portal's; signed-in
--      logins call it, and it refuses anyone but a claimed affiliate login,
--      as before): its three keys are as they were, and it adds
--      'seminar_links', a JSON array (empty when there is none or the
--      affiliate has no code) of {event_name, first_day, last_day, url}, one
--      per address, ordered by first day. Patched at one anchor.
--   The page (src/pages/AffiliateReferralPage.tsx) shows one QR card per link
--   ("Your link for <event>", Copy Link / PNG / Share, as the existing card)
--   under the existing one, now titled "Your free therapy link".
--
-- NOT CHANGED
--
--   Every other function, table and grant: the event website's functions
--   (event_web_referral_info, public_affiliate_referral_info,
--   event_web_register and the referral rules: not called here, not pinned),
--   event_web_open_state and current_affiliate_customer_id (used as they
--   are, pinned below), generate_affiliate_referral_code (its shape relied
--   on, and the self-test's code; pinned), the Website tab, the Edge Function
--   and the shared contract. affiliate_portal_referral_info keeps its grant
--   (signed-in logins and the service role; never anon).
--
-- NOT COVERED (to tell the owner)
--
--   * The site's short link must be live before affiliates are told: until
--     the seminar site's /<CODE> page is deployed, the portal's link answers
--     the site's 404 page (/signup/<CODE> works today). Deploy the site
--     first, check /<a real code> on its preview, then apply this file.
--   * The link is built from the Website tab's sync URL. If the site is
--     served on another address than the one the app syncs to (a custom
--     domain while sync stays on vercel.app), the portal shows the sync
--     address; it works, but is not the custom domain.
--   * An event whose tickets are switched off (Tickets on sale) shows no
--     link while off, as the site takes no registrations then.
--   * Two events taking registrations on one site: one link, named after the
--     event the site last synced as. When the site is moved to the next
--     event before the current one ends, the card keeps the current event's
--     name until the site's first sync as the next one (minutes, as the app
--     pings it every 10); the address is the same and registers for the
--     event the site serves.
--   * The short link's code shape is the app's (EN and six characters), on
--     both sides: if the app ever made codes of another shape, the site's
--     [code] page and this file would change together (until then the portal
--     shows no seminar link for such a code, rather than a link that loses
--     the referral). A made-up word of that shape (/ENTRANCE) still goes to
--     /signup/<it> and replaces the visitor's earlier code, as typing
--     /signup/<anything> always has; other words shaped like a code (/Terms,
--     /speakers) go to the event page and replace nothing.
--   * The old seminar site (rev22-energia-seminar, 19-20 Oct, over) is not
--     touched: it gets no short link.
--
-- DEPLOY ORDER (each step with the owner's go-ahead)
--
--   After the seminar site's short-link change is deployed and checked.
--   Production now: after 450 (63219badeea67a5d401d5af2aeb88f19, 1371
--   functions). It pins only the four functions below, which 436 to 450
--   leave as read here, and no other file's function; files numbered before
--   it that change none of the four do not change what it does (they change
--   the fingerprint after it).
--   1. Dry run on a copy of production as it is then: apply this file twice.
--      The first run changes affiliate_portal_referral_info alone; the
--      second says "already this version; left alone" and changes nothing.
--   2. Apply this file (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself (the AFTER md5, the grant, its self-test,
--      which leaves no row).
--   3. Then the app's page (AffiliateReferralPage.tsx). The page reads a
--      missing seminar_links as none, so it may also go first.
--
-- SAFETY
--
--   ONE statement (a single DO block), atomic whatever runs it; every check
--   before anything is changed:
--   * the functions it relies on and does not change are as read on a copy
--     of production after 450 (below); the columns it reads are as read.
--   * affiliate_portal_referral_info is 155's (patched, its anchor found
--     once, the text built has the tested md5) or already this file's AFTER
--     (left alone); anything else is refused.
--   * afterwards its md5 is the AFTER one and its grant is unchanged
--     (signed-in logins and the service role; not anon).
--   * a self-test, in a block that is always undone (it ends by raising
--     P0454, so it leaves no row): a made-up Owner, store, affiliate login
--     (its code from generate_affiliate_referral_code) and four events on one
--     site, one whose website is Live with a day ahead, one Off, one Record
--     only that is over, one Record only that starts later: the affiliate is
--     given exactly one link, the first one's (<its site>/<code>, its name
--     and days), the three keys as before; an Owner's login is still refused.
--     Its affiliate login queues a welcome WhatsApp (394's trigger), undone
--     with the rest.
--   It reads only, apart from the function and the self-test's rows (undone).
--   Locks: the function's catalogue row, to the end of the apply; a portal
--   page loading at that moment finishes on the text it started with.
--
-- BEFORE (a copy of production after 450, pg_get_functiondef with search_path public):
--   changed
--   affiliate_portal_referral_info()                               558a9a0704dae06ee120fadf989e2445  (155)
--   relied on, not changed
--   current_affiliate_customer_id()                                51695acf5f26ce3918d6003d0c980b0f
--   event_web_open_state(uuid)                                     ef87a22efbb62f69759838db2dfc0d0c  (436)
--   generate_affiliate_referral_code()                             29ae3d463f13788ccf88a952eb3e70b8  (155)
--   public function fingerprint (production after 450)             63219badeea67a5d401d5af2aeb88f19 (1371 functions)
-- AFTER (for later guards):
--   affiliate_portal_referral_info()                               42453f972e0349eb1353e231a659fa55
--   public function fingerprint (production after 450, then 454)   fae0684784edf48c6d90aef7d87987fe (1371 functions)
--
-- Test: scripts/referrals/tests/portal-seminar-link-454.sql (begin ... rollback; it installs
-- this file twice, or -v skip_install=1 where it is installed); scripts/permissions/tests/
-- function-grants.sql and staff-only-functions.sql, and 442's referral-self-442.sql (-v nomig=1), pass with it.
-- The page: node --test scripts/referrals/tests/portal-and-signup-425.test.mjs.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The function it changes: BEFORE (155's) and AFTER ──
  c_sig constant text := 'affiliate_portal_referral_info()';
  c_before constant text := '558a9a0704dae06ee120fadf989e2445';
  c_after constant text := '42453f972e0349eb1353e231a659fa55';
  -- its anchor (found once in the BEFORE text) and its patch
  c_anchor constant text[] := array[
$a01$    'direct_referrals', (select count(*) from public.customers where referred_by = v_me and deleted_at is null));
$a01$];
  c_patch constant text[] := array[
$p01$    'direct_referrals', (select count(*) from public.customers where referred_by = v_me and deleted_at is null),
    -- 454 (the owner, 22 Oct 2026, item 8): the affiliate's short link to each
    -- seminar website taking registrations now, as the website judges it
    -- (event_web_open_state: the event not deleted, its website not Off,
    -- tickets on sale, a day still open), on the site's address (the Website
    -- tab's sync URL, read as event_web_settings_get reads site_url) and the
    -- code, when the site's short link takes it as one (the shape
    -- generate_affiliate_referral_code makes). One link per address: the site
    -- serves one event, the one it last synced as (else the earliest).
    -- The event's name and days and the public address only.
    'seminar_links', (select coalesce(jsonb_agg(jsonb_build_object(
                               'event_name', l.name, 'first_day', l.first_day, 'last_day', l.last_day, 'url', l.url)
                             order by l.first_day, l.name, l.id), '[]'::jsonb)
                        from (select distinct on (lower(u.url)) e.id, e.name, d.first_day, d.last_day, u.url
                                from public.event_web_settings s
                                join public.events e on e.id = s.event_id
                                cross join lateral (select substring(s.sync_url from '^(https://[^/]+)') || '/' || v_a.referral_code as url) u
                                cross join lateral (select min(dd.day) as first_day, max(dd.day) as last_day
                                                      from public.event_days dd where dd.event_id = e.id) d
                               where v_a.referral_code ~ '^EN[0-9A-HJKMNP-TV-Z]{6}$'
                                 and u.url is not null
                                 and public.event_web_open_state(e.id)->>'closed_reason' is null
                               order by lower(u.url), s.last_sync_at desc nulls last, d.first_day, e.id) l));
$p01$];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; i int; v_text text; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_owner uuid; t_user uuid; t_store uuid; t_cust uuid; t_aff uuid; t_code text;
  t_ev1 uuid; t_ev2 uuid; t_ev3 uuid; t_ev4 uuid; t_site text; t_ans jsonb; t_mine jsonb; t_err text;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 22 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is changed unless all pass ──────────────────────
  -- What it relies on and does not change: as on production after 450.
  for r in select * from (values
      ('current_affiliate_customer_id()', '51695acf5f26ce3918d6003d0c980b0f'),
      ('event_web_open_state(uuid)', 'ef87a22efbb62f69759838db2dfc0d0c'),
      ('generate_affiliate_referral_code()', '29ae3d463f13788ccf88a952eb3e70b8')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '454: public.% is missing or not the version this was tested against (production after 450). Re-read it and re-test before applying.', r.fn;
    end if;
  end loop;

  -- The columns 454 reads, as read on 22 Oct 2026.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values
      ('public.customer_affiliates', 'customer_id uuid'), ('public.customer_affiliates', 'referral_code text'),
      ('public.event_web_settings', 'event_id uuid'), ('public.event_web_settings', 'sync_url text'),
      ('public.event_web_settings', 'last_sync_at timestamp with time zone'),
      ('public.events', 'id uuid'), ('public.events', 'name text'),
      ('public.event_days', 'event_id uuid'), ('public.event_days', 'day date')) x(t, c)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass(x.t) and a.attnum > 0 and not a.attisdropped
                        and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.c);
  if v is not null then
    raise exception '454: these columns are missing or not as read on 22 Oct 2026: %', v; end if;

  -- The function: BEFORE (patched, its anchor once) or AFTER (left alone).
  if to_regprocedure('public.' || c_sig) is null then
    raise exception '454: public.% is missing (is 155 applied?)', c_sig; end if;
  d := pg_get_functiondef(('public.' || c_sig)::regprocedure);
  v_acl := (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sig)::regprocedure);
  if md5(d) = c_after then
    raise notice '454: public.% is already this version; left alone', c_sig;
  elsif md5(d) <> c_before then
    raise exception '454: public.% is not 155''s version (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  else
    for i in 1 .. cardinality(c_anchor) loop
      n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
      if n <> 1 then raise exception '454: anchor % of public.% was found % times, not once', i, c_sig, n; end if;
      d := replace(d, c_anchor[i], c_patch[i]);
    end loop;
    if md5(d) <> c_after then
      raise exception '454: the text built for public.% is not the tested one (md5 %)', c_sig, md5(d); end if;
    v_text := d;
  end if;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  if v_text is not null then execute v_text; end if;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  if md5(pg_get_functiondef(('public.' || c_sig)::regprocedure)) <> c_after then
    raise exception '454: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sig)::regprocedure) is distinct from v_acl
     or has_function_privilege('anon', 'public.' || c_sig, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_sig, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_sig, 'execute') then
    raise exception '454: the grants of public.% changed (signed-in logins and the service role; not anon)', c_sig; end if;

  -- ── 4. Behaviour, in a block that is always undone ──────────────────────
  -- Made-up records only ("454 check", @example.invalid, *.example.com);
  -- it ends by raising P0454, which undoes all it wrote.
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_sfx := upper(substr(md5(gen_random_uuid()::text), 1, 8));
    t_code := public.generate_affiliate_referral_code();
    t_site := 'https://seminar-454-' || lower(t_sfx) || '.example.com';
    insert into auth.users (id, email) values (gen_random_uuid(), '454-owner-' || lower(t_sfx) || '@example.invalid')
      returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '454 check', u.email, 'owner', true from auth.users u where u.id = t_owner;
    insert into public.stores (name, code, country_code) values ('454 check ' || t_sfx, '454-' || t_sfx, 'SG') returning id into t_store;
    -- The affiliate and their login.
    insert into auth.users (id, email) values (gen_random_uuid(), '454-aff-' || lower(t_sfx) || '@example.invalid')
      returning id into t_user;
    insert into public.customers (full_name, phone)
    select 'Check Affiliate ' || t_sfx, '+6125550' || lpad(g::text, 4, '0') from generate_series(4540, 5539) g
     where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(g::text, 4, '0'))
     limit 1
    returning id into t_cust;
    insert into public.customer_affiliates (customer_id, status, referral_code) values (t_cust, 'active', t_code)
      returning id into t_aff;
    insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (t_user, t_cust, t_aff, 'claimed');
    -- Four events on one site: Live with a day ahead (listed), Off (not), Record only and over (not),
    -- Record only and later (open, but the same address: listed once, under the earliest, as none has synced).
    insert into public.events (name, daily_start, daily_end, is_active) values ('454 check live ' || t_sfx, '09:00', '19:00', true)
      returning id into t_ev1;
    insert into public.events (name, daily_start, daily_end, is_active) values ('454 check off ' || t_sfx, '09:00', '19:00', true)
      returning id into t_ev2;
    insert into public.events (name, daily_start, daily_end, is_active) values ('454 check over ' || t_sfx, '09:00', '19:00', true)
      returning id into t_ev3;
    insert into public.events (name, daily_start, daily_end, is_active) values ('454 check next ' || t_sfx, '09:00', '19:00', true)
      returning id into t_ev4;
    insert into public.event_days (event_id, day)
    values (t_ev1, public.sg_today() + 30), (t_ev1, public.sg_today() + 31), (t_ev2, public.sg_today() + 30), (t_ev3, public.sg_today() - 3),
           (t_ev4, public.sg_today() + 40);
    insert into public.event_web_settings (event_id, code, mode, store_id, acting_profile_id, sync_url)
    values (t_ev1, 'CHECK454-' || t_sfx, 'live', t_store, t_owner, t_site || '/api/app/sync'),
           (t_ev2, 'CHECK454B-' || t_sfx, 'off', t_store, t_owner, t_site || '/api/app/sync'),
           (t_ev3, 'CHECK454C-' || t_sfx, 'record_only', t_store, t_owner, t_site || '/api/app/sync'),
           (t_ev4, 'CHECK454D-' || t_sfx, 'record_only', t_store, t_owner, t_site || '/api/app/sync');
    perform set_config('request.jwt.claim.sub', t_user::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    t_ans := public.affiliate_portal_referral_info();
    select coalesce(jsonb_agg(x), '[]'::jsonb) into t_mine
      from jsonb_array_elements(t_ans->'seminar_links') x where x->>'url' like t_site || '/%';
    if t_ans - 'seminar_links' is distinct from jsonb_build_object('referral_code', t_code, 'accepting', true, 'direct_referrals', 0)
       or jsonb_typeof(t_ans->'seminar_links') is distinct from 'array'
       or t_mine is distinct from jsonb_build_array(jsonb_build_object(
            'event_name', '454 check live ' || t_sfx, 'first_day', public.sg_today() + 30, 'last_day', public.sg_today() + 31,
            'url', t_site || '/' || t_code)) then
      raise exception '454: the self-test''s portal answer is not as tested (one link, to the Live event, listed once): %', t_ans; end if;
    -- Anyone but a claimed affiliate login is refused, as before.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    begin
      perform public.affiliate_portal_referral_info();
    exception when others then t_err := sqlerrm;
    end;
    if t_err is distinct from 'Not an affiliate account' then
      raise exception '454: the self-test''s Owner login was not refused as before: %', coalesce(t_err, 'answered'); end if;
    raise exception using errcode = 'P0454', message = '454: self-test done, undone';
  exception when sqlstate 'P0454' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
