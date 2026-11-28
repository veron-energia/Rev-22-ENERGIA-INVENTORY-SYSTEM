-- 549_referral_page_shows_an_existing_booking.sql
--
-- THE REFERRAL PAGE TELLS SOMEBODY ALREADY REGISTERED ABOUT THEIR UPCOMING BOOKING, AND SHOWS ITS
-- TIME AND ITS BOOKING ID ONLY WHEN THE PHONE AND THE EMAIL BOTH MATCH IT
--
--   The user, 27 Nov 2026. The function fingerprint pinned below is production's after 547
--   (73d175b2e8d324bb524127497fe3d02b/1470, read with plan-backup/affiliate_rules_489/e2e493/
--   fingerprint.sql on a local copy: 546's state plus 547). If production differs when this is
--   applied, it refuses and changes nothing.
--   548 IS RESERVED by another session and not live yet. If 548 goes live first, the fingerprint
--   changes and this refuses: read 548's AFTER fingerprint, put it in c_fp_before, apply this on a
--   copy with 548, and write the new AFTER fingerprint in c_fp_after and below. The function's own
--   md5 does not change (548 does not touch anything this reads, as far as this file knows: check
--   normalize_customer_phone, customer_email_match_key, sg_today, public_affiliate_referral_info and
--   the tables named under RELIED ON against 548 before re-pinning).
--   (The number 549 is this file's name and its errors' prefix; if it changes at commit, change it
--   there, in the 549 comments it writes into referral_booking_lookup (and so its AFTER md5, also
--   in scripts/affiliate-signup/undo-549.sql and in the suite), and in the name and path of the
--   suite.)
--
-- WHAT WAS WRONG
--
--   On /r/<code> (src/pages/ReferralSignupPage.tsx, public: the anon key, nobody signed in), a
--   number already on file is answered "already registered" by affiliate_referral_signup_with_
--   notice, and the page then offers "Book your first-time appointment", even to somebody who has
--   booked already. The page has no way to know: the cal.com bookings (480's public.calcom_bookings)
--   are the server's alone, and the page knows only a typed number.
--
-- THE RULE (the user, 27 Nov 2026)
--
--   A booked person should see "the date and time and the edit function" instead of the booking
--   button. The user chose "Phone + email must match (Recommended)": the time and the booking id
--   only when the phone AND the email typed are that booking's; with no email or another one, the
--   page only says they already have an appointment and asks for the email they booked with.
--   Somebody who knows only the number must not see the time or get the booking id (the cal.com
--   uid opens reschedule and cancel).
--
-- WHAT THIS DOES
--
--   * public.referral_booking_lookup(p_code text, p_phone text, p_email text default null) returns
--     jsonb, new: plpgsql, SECURITY DEFINER, owner postgres, search_path public, pg_temp (546's
--     rule). Callable signed out and signed in and by the service role, as
--     public_affiliate_referral_info is; PUBLIC has nothing. It answers exactly one of
--       {"state":"none"}           no upcoming active booking on that phone;
--       {"state":"needs_email"}    there is one, and the email is blank, not an email, or not that
--                                  booking's email;
--       {"state":"booked","start_at":"2026-12-07T02:00:00Z","end_at":"2026-12-07T03:00:00Z",
--        "uid":"<cal.com uid>"}    the email is that booking's: start and end in UTC, ISO 8601
--                                  (end_at is null when the booking has no end); uid is null for a
--                                  booking whose uid is a 'gcal:...' fill-in from the calendar
--                                  (no cal.com links can be made for it);
--       {"state":"try_later"}      a limit is reached (the same answer whatever is on file);
--       {"state":"invalid"}        an unknown referral code, or a phone that is not a valid number.
--     It raises only for real faults (529's salt missing, say), never for these.
--   * Which booking: from calcom_bookings, status 'active', phone_key = normalize_customer_phone(
--     p_phone), its Singapore date today or later (480's "next booking", rule B: today's booking
--     still counts all day); the earliest start_at, then the uid. "booked" only when THAT booking's
--     email_key is not null and equals customer_email_match_key of the email typed (so case, spaces
--     around it and Gmail's dots and +tags do not matter, as 480 keeps email_key), and the email
--     typed looks like name@domain.tld and is at most 254 characters (529's rule for the sign-up);
--     otherwise needs_email. Only the booking's own phone_key and email_key are read: no customer
--     record and no merge is followed.
--   * The code: valid as public_affiliate_referral_info decides it (an affiliate's referral code,
--     trimmed, the affiliate record not deleted, its customer in use); whether the link is
--     accepting does not matter here.
--   * public.referral_booking_lookups, new: one row for every lookup answered (id bigint identity,
--     created_at, sender_key: 64 hex characters or null, checked; phone_key; outcome: one of the
--     five states, checked). Row level security on, no policy, every privilege revoked from
--     public, anon, authenticated and service_role, on the table and on its id sequence: only the
--     owner (and so the function) reads or writes it, as with 529's referral_sender_salt. Indexes
--     (sender_key, created_at) where there is a sender, and (phone_key, created_at).
--   * The limits, so the lookup is no oracle (modelled on 529):
--       - the sender exactly as affiliate_referral_signup works it out since 529: the address in
--         cf-connecting-ip from the setting request.headers (never x-forwarded-for), an IPv6
--         address as its /64, ::ffff:a.b.c.d as the IPv4 address, kept only as the hex sha256 of
--         529's secret salt (public.referral_sender_salt, read, not changed) and the address; no
--         such header, or one that is not a single address: no sender, and the sender's limit
--         does not apply;
--       - one sender: 10 lookups in the last hour -> try_later;
--       - one phone: 5 lookups in the last hour, from any sender -> try_later (this is what stops
--         guessing emails for one number);
--       - every lookup answered counts (try_later refusals do not); a refusal is recorded at most
--         once an hour for the sender (the sender's) or for the phone (the phone's), so hammering
--         adds nothing;
--       - advisory locks as 529 takes them: the sender's ('referral-booking-sender:' and its key)
--         before anything is counted, then the phone's ('referral-booking-phone:' and the number)
--         before the phone is counted, always in that order: two lookups cannot both take the last
--         place, and never wait for each other the other way round. They are this function's own
--         keys (529's sign-up locks are not taken, so a lookup never waits for a sign-up).
--     Order: the input (invalid; the phone left out of the row when it is not valid), the sender's
--     limit, the phone's limit, then the lookup. "invalid" is answered before the limits (it says
--     nothing about any booking; whether a code is a link is public through
--     public_affiliate_referral_info already) and recorded while the sender is within its limit,
--     so it counts; past the sender's limit it is answered but not recorded, so hammering with bad
--     input adds nothing either. An invalid code with a valid phone is recorded with the phone and
--     counts for it.
--
-- WHAT THIS LEAVES ALONE
--
--   * affiliate_referral_signup, affiliate_referral_signup_with_notice, public_affiliate_referral_
--     info, referral_signup_events and referral_sender_salt (529's objects are read, not changed;
--     the sign-up's own limits do not count lookups, and lookups do not count sign-ups).
--   * calcom_bookings and every 480 function: read only.
--   * Every other function and table; no data changes. No row is ever removed from the new table
--     (like 529's events); it grows by at most 11 rows an hour per sender.
--
-- GO-LIVE: after 547 (it refuses before it; see 548 above). The page change ships after it or with
--   it: the page calls referral_booking_lookup after "already registered" and, before this is in,
--   gets PostgREST's "function not found" (PGRST202), on which it should fall back to the booking
--   button as before.
--
-- UNDO: scripts/affiliate-signup/undo-549.sql (it refuses unless the function and the table are
--   exactly 549's): drops the function, then the table with every lookup recorded. Run it BEFORE any
--   older UNDO. A later migration that changes referral_booking_lookup must pin its AFTER md5 below.
--
-- NO SELF-TEST INSIDE; the suite is scripts/affiliate-signup/tests/referral-booking-lookup-549.sql.
--
-- BEFORE -> AFTER
--   function fingerprint (plan-backup/affiliate_rules_489/e2e493/fingerprint.sql)
--     73d175b2e8d324bb524127497fe3d02b/1470 -> da952c4a3e002f6fc20da3260b1cff95/1471
-- NEW (AFTER, md5 of pg_get_functiondef):
--   referral_booking_lookup(text,text,text)                                8385a3401954768048e293fb0fac7dbf
--   table referral_booking_lookups: its columns, constraints, indexes and grants as in the block below
-- RELIED ON, NOT CHANGED (production after 547; also inside the fingerprint):
--   normalize_customer_phone(text)                                         b2bfac910e0c9eff402ba44e19750bee
--   inspect_customer_phone(text,text)                                      6672c4d1963996f3b601896f4a55916e
--   customer_email_match_key(text)                                         be468815c9626fff1728e2cfcd484b66
--   sg_today()                                                             1c1289f18e24d8370e9a6364c9c06fca
--   public_affiliate_referral_info(text)                                   92169602d93db6534f13e2e02b113fe0
--   affiliate_referral_signup(text,text,text,text,text,text)               621707ec197bbf6ff6e85b2da17397fb
--     (its sender is copied word for word, not called; the suite compares the two keys)
--   tables: referral_sender_salt (529: id boolean, salt text, created_at; one row, 64 hex),
--     calcom_bookings (480: uid, start_at, end_at, status, phone_key, email_key), customer_affiliates
--     (referral_code, customer_id, deleted_at), customers (id, full_name, deleted_at).
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function fingerprint (every public function's pg_get_functiondef, as fingerprint.sql reads
  -- it): production's after 547, and after this.
  c_fp_before constant text := '73d175b2e8d324bb524127497fe3d02b/1470';
  c_fp_after constant text := 'da952c4a3e002f6fc20da3260b1cff95/1471';
  -- Relied on (inside the fingerprint too; checked by name so a refusal says which).
  c_relied constant text[] := array[
    'normalize_customer_phone(text)', 'inspect_customer_phone(text,text)', 'customer_email_match_key(text)',
    'sg_today()', 'public_affiliate_referral_info(text)', 'affiliate_referral_signup(text,text,text,text,text,text)'];
  c_relied_md5 constant text[] := array[
    'b2bfac910e0c9eff402ba44e19750bee', '6672c4d1963996f3b601896f4a55916e', 'be468815c9626fff1728e2cfcd484b66',
    '1c1289f18e24d8370e9a6364c9c06fca', '92169602d93db6534f13e2e02b113fe0', '621707ec197bbf6ff6e85b2da17397fb'];
  -- The columns each relied-on table must have, as 'name type'.
  c_need constant text[][] := array[
    ['referral_sender_salt', 'id boolean,salt text,created_at timestamp with time zone'],
    ['calcom_bookings', 'uid text,start_at timestamp with time zone,end_at timestamp with time zone,status text,phone_key text,email_key text'],
    ['customer_affiliates', 'customer_id uuid,referral_code text,deleted_at timestamp with time zone'],
    ['customers', 'id uuid,full_name text,deleted_at timestamp with time zone']];
  c_sig constant text := 'referral_booking_lookup(text,text,text)';
  c_def constant text := $d$CREATE OR REPLACE FUNCTION public.referral_booking_lookup(p_code text, p_phone text, p_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- 549: who is asking (529's salted one-way hash of the sender's address, or null), the phone as
  -- the bookings keep it, the lookups counted for them, and the booking found.
  v_salt text; v_ip inet; v_sender text; v_norm text; v_n integer := 0; v_typed text;
  v_uid text; v_start timestamptz; v_end timestamptz; v_email_key text; v_state text;
begin
  -- 549 (the user, 27 Nov 2026: "Phone + email must match (Recommended)"): the referral page
  -- /r/<code> asks this, signed out, after "already registered", whether the number has an
  -- upcoming cal.com booking. The time and the booking id (its uid opens reschedule and cancel on
  -- cal.com) are given only when the email typed is that booking's email too; with no email, or
  -- another one, the answer only says there is a booking. Answers, exactly:
  --   {"state":"none"}         no upcoming active booking on the phone;
  --   {"state":"needs_email"}  there is one, and the email is blank, not an email, or not its own;
  --   {"state":"booked","start_at":..,"end_at":..,"uid":..}  the email is the booking's (times in
  --                            UTC, ISO 8601; uid null for a booking filled in from the calendar,
  --                            'gcal:...', which has no cal.com links; end_at null when unknown);
  --   {"state":"try_later"}    a limit is reached, whatever is on file;
  --   {"state":"invalid"}      the code is no affiliate's link, or the phone is not a valid number.
  -- Every answer is recorded in public.referral_booking_lookups (only its owner reads it), so the
  -- lookup is limited: 10 an hour from one sender, 5 an hour on one phone (what stops guessing
  -- emails for a number). Their refusals are recorded at most once an hour for the sender or the
  -- phone and are not counted, so trying again and again adds nothing.
  --
  -- The sender, exactly as affiliate_referral_signup works it out (529): the address Cloudflare
  -- puts in cf-connecting-ip (never x-forwarded-for); IPv4 one sender, IPv6 its /64, ::ffff:a.b.c.d
  -- as the IPv4 address; kept only as sha256 of 529's secret salt and the address. No such header,
  -- or one that is not a single address: no sender, and the sender's limit does not apply.
  select s.salt into v_salt from public.referral_sender_salt s where s.id;
  if v_salt is null or v_salt !~ '^[0-9a-f]{64}$' then
    raise exception '549: the sender salt (public.referral_sender_salt) is missing, so no sender can be counted. Run 529 again.';
  end if;
  begin
    v_ip := nullif(btrim(current_setting('request.headers', true)::jsonb ->> 'cf-connecting-ip'), '')::inet;
    if family(v_ip) = 6 and v_ip <<= '::ffff:0.0.0.0/96'::inet then
      v_ip := regexp_replace(host(v_ip), '^::ffff:', '', 'i')::inet;
    end if;
    if masklen(v_ip) <> (case family(v_ip) when 4 then 32 else 128 end) then v_ip := null; end if;
  exception when others then v_ip := null;
  end;
  v_sender := case family(v_ip)
    when 4 then encode(sha256(convert_to(v_salt || '|' || host(v_ip), 'UTF8')), 'hex')
    when 6 then encode(sha256(convert_to(v_salt || '|' || host(network(set_masklen(v_ip, 64))) || '/64', 'UTF8')), 'hex')
  end;
  -- The sender's lock, then (below) the phone's: always in that order, so two lookups never wait
  -- for each other's locks the other way round, and neither limit gives its last place twice.
  if v_sender is not null then
    perform pg_advisory_xact_lock(hashtextextended('referral-booking-sender:' || v_sender, 0));
    select count(*) into v_n from public.referral_booking_lookups l
     where l.sender_key = v_sender and l.outcome <> 'try_later' and l.created_at > now() - interval '1 hour';
  end if;

  -- 1. The input. A code is valid as public_affiliate_referral_info decides (an affiliate's
  -- referral code, not deleted, its customer in use; accepting or not), and the phone as
  -- normalize_customer_phone reads it. Answered "invalid" before the limits (it says nothing about
  -- any booking); recorded (without a phone when the phone is not valid) while the sender is
  -- within its limit, so it counts as a lookup; past the limit, not recorded.
  v_norm := public.normalize_customer_phone(p_phone);
  if v_norm is null
     or not exists (select 1 from public.customer_affiliates ca
                      join public.customers c on c.id = ca.customer_id and c.deleted_at is null and c.full_name is not null
                     where ca.referral_code = btrim(p_code) and ca.deleted_at is null) then
    if v_sender is null or v_n < 10 then
      insert into public.referral_booking_lookups(sender_key, phone_key, outcome) values (v_sender, v_norm, 'invalid');
    end if;
    return jsonb_build_object('state', 'invalid');
  end if;

  -- 2. The sender's limit: 10 lookups an hour, whatever each was answered.
  if v_sender is not null and v_n >= 10 then
    if not exists (select 1 from public.referral_booking_lookups l
                    where l.sender_key = v_sender and l.outcome = 'try_later' and l.created_at > now() - interval '1 hour') then
      insert into public.referral_booking_lookups(sender_key, phone_key, outcome) values (v_sender, null, 'try_later');
    end if;
    return jsonb_build_object('state', 'try_later');
  end if;

  -- 3. The phone's limit: 5 lookups an hour on one number, from any sender.
  perform pg_advisory_xact_lock(hashtextextended('referral-booking-phone:' || v_norm, 0));
  if (select count(*) from public.referral_booking_lookups l
       where l.phone_key = v_norm and l.outcome <> 'try_later' and l.created_at > now() - interval '1 hour') >= 5 then
    if not exists (select 1 from public.referral_booking_lookups l
                    where l.phone_key = v_norm and l.outcome = 'try_later' and l.created_at > now() - interval '1 hour') then
      insert into public.referral_booking_lookups(sender_key, phone_key, outcome) values (v_sender, v_norm, 'try_later');
    end if;
    return jsonb_build_object('state', 'try_later');
  end if;

  -- 4. The booking: 480's next booking (rule B), by the booking's own phone: active, its
  -- Singapore date today or later (today's still counts all day), the earliest, then by uid.
  -- Only that booking's own email decides (customer_email_match_key, as 480 keeps email_key: case,
  -- spaces and Gmail's dots and +tags ignored); no customer record or merge is followed. An email
  -- typed must look like name@domain.tld and be at most 254 characters (529's rule).
  select b.uid, b.start_at, b.end_at, b.email_key into v_uid, v_start, v_end, v_email_key
    from public.calcom_bookings b
   where b.status = 'active' and b.phone_key = v_norm
     and (b.start_at at time zone 'Asia/Singapore')::date >= public.sg_today()
   order by b.start_at, b.uid
   limit 1;
  if v_uid is null then
    v_state := 'none';
  else
    v_typed := lower(btrim(coalesce(p_email, '')));
    v_state := case
      when v_email_key is not null and char_length(v_typed) <= 254
       and v_typed ~ '^[^@ <>\u0001-\u001f\u007f-\u009f]+@[^@ .<>\u0001-\u001f\u007f-\u009f]+(\.[^@ .<>\u0001-\u001f\u007f-\u009f]+)*\.[^@ .<>\u0001-\u001f\u007f-\u009f]{2,}$'
       and public.customer_email_match_key(v_typed) = v_email_key then 'booked'
      else 'needs_email' end;
  end if;
  insert into public.referral_booking_lookups(sender_key, phone_key, outcome) values (v_sender, v_norm, v_state);
  if v_state = 'booked' then
    return jsonb_build_object('state', 'booked',
      'start_at', to_char(v_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'end_at', to_char(v_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'uid', case when v_uid like 'gcal:%' then null else v_uid end);
  end if;
  return jsonb_build_object('state', v_state);
end
$function$
$d$;
  c_md5 constant text := '8385a3401954768048e293fb0fac7dbf';
  -- Its grants: as public_affiliate_referral_info's (signed out, signed in, the service role).
  c_acl constant text := 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  -- The table as made here.
  c_cols constant text := 'id bigint NO,created_at timestamp with time zone NO,sender_key text YES,phone_key text YES,outcome text NO';
  c_con constant text := 'referral_booking_lookups_outcome_check CHECK ((outcome = ANY (ARRAY[''none''::text, ''needs_email''::text, ''booked''::text, ''try_later''::text, ''invalid''::text]))),referral_booking_lookups_pkey PRIMARY KEY (id),referral_booking_lookups_sender_key_is_a_hash CHECK (((sender_key IS NULL) OR (sender_key ~ ''^[0-9a-f]{64}$''::text)))';
  c_idx constant text := 'CREATE INDEX referral_booking_lookups_phone_time ON public.referral_booking_lookups USING btree (phone_key, created_at),CREATE INDEX referral_booking_lookups_sender_time ON public.referral_booking_lookups USING btree (sender_key, created_at) WHERE (sender_key IS NOT NULL),CREATE UNIQUE INDEX referral_booking_lookups_pkey ON public.referral_booking_lookups USING btree (id)';
  c_tab_acl constant text := '{postgres=arwdDxtm/postgres}';
  c_seq_acl constant text := '{postgres=rwU/postgres}';
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_fp text; v_md5 text; v_cols text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy object waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass.
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || '/' || count(*) into v_fp
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
  if v_fp = c_fp_after and to_regprocedure('public.' || c_sig) is not null
     and md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) = c_md5
     and to_regclass('public.referral_booking_lookups') is not null then
    raise exception '549 is already in on this database; nothing was changed.'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'referral_booking_lookup')
     or to_regclass('public.referral_booking_lookups') is not null then
    raise exception '549: a function referral_booking_lookup or a relation referral_booking_lookups is already there, but 549 is not in as made. Re-read them before applying; nothing was changed.'; end if;
  if v_fp is distinct from c_fp_before then
    raise exception '549: the functions are not production''s after 547 (fingerprint %, expected %). Is 547 in? Has 548 gone in first (then re-pin this, see its header)? Nothing was changed.', v_fp, c_fp_before; end if;
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '549: public.% is missing or not the version this was tested against. Nothing was changed.', c_relied[i]; end if;
  end loop;
  for i in 1 .. array_length(c_need, 1) loop
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ',' order by x.ord) into v_cols
      from unnest(string_to_array(c_need[i][2], ',')) with ordinality x(col, ord)
      join pg_attribute a on a.attrelid = to_regclass('public.' || c_need[i][1]) and a.attnum > 0 and not a.attisdropped
                         and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.col;
    if v_cols is distinct from c_need[i][2] then
      raise exception '549: public.% does not have the columns this reads (%). Nothing was changed.', c_need[i][1], c_need[i][2]; end if;
  end loop;
  if (select count(*) from public.referral_sender_salt s where s.id and s.salt ~ '^[0-9a-f]{64}$') <> 1 then
    raise exception '549: 529''s sender salt (public.referral_sender_salt) is missing. Run 529 again first; nothing was changed.'; end if;
  if md5(c_def) <> c_md5 then
    raise exception '549: the function text is not the tested one (md5 %). Nothing was changed.', md5(c_def); end if;

  -- 2. Install: the table first (the function reads it).
  create table public.referral_booking_lookups (
    id bigint generated always as identity primary key,
    created_at timestamptz not null default now(),
    sender_key text,
    phone_key text,
    outcome text not null,
    constraint referral_booking_lookups_sender_key_is_a_hash check (sender_key is null or sender_key ~ '^[0-9a-f]{64}$'),
    constraint referral_booking_lookups_outcome_check check (outcome in ('none', 'needs_email', 'booked', 'try_later', 'invalid')));
  create index referral_booking_lookups_sender_time on public.referral_booking_lookups (sender_key, created_at)
    where sender_key is not null;
  create index referral_booking_lookups_phone_time on public.referral_booking_lookups (phone_key, created_at);
  alter table public.referral_booking_lookups enable row level security;
  revoke all on table public.referral_booking_lookups from public, anon, authenticated, service_role;
  revoke all on sequence public.referral_booking_lookups_id_seq from public, anon, authenticated, service_role;
  comment on table public.referral_booking_lookups is
    '549: every referral-page booking lookup answered (referral_booking_lookup), for its limits. Owner only.';
  execute c_def;
  execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_sig);
  execute format('grant execute on function public.%s to anon, authenticated, service_role', c_sig);

  -- 3. Checks after installing.
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_md5
     or (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
          where p.oid = to_regprocedure('public.' || c_sig)) is distinct from c_acl
     or (select p.proconfig from pg_proc p where p.oid = to_regprocedure('public.' || c_sig)) is distinct from array['search_path=public, pg_temp']
     or not (select p.prosecdef from pg_proc p where p.oid = to_regprocedure('public.' || c_sig))
     or (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = to_regprocedure('public.' || c_sig)) <> 'postgres' then
    raise exception '549: public.% was made other than tested (its text, grants, search path, rights or owner)', c_sig; end if;
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'referral_booking_lookups') is distinct from c_cols
     or (select string_agg(conname || ' ' || pg_get_constraintdef(oid), ',' order by conname)
           from pg_constraint where conrelid = 'public.referral_booking_lookups'::regclass) is distinct from c_con
     or (select string_agg(pg_get_indexdef(indexrelid), ',' order by pg_get_indexdef(indexrelid))
           from pg_index where indrelid = 'public.referral_booking_lookups'::regclass) is distinct from c_idx
     or (select c.relacl::text from pg_class c where c.oid = 'public.referral_booking_lookups'::regclass) is distinct from c_tab_acl
     or (select c.relacl::text from pg_class c where c.oid = 'public.referral_booking_lookups_id_seq'::regclass) is distinct from c_seq_acl
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.referral_booking_lookups'::regclass)
     or exists (select 1 from pg_policy p where p.polrelid = 'public.referral_booking_lookups'::regclass)
     or (select pg_get_userbyid(c.relowner) from pg_class c where c.oid = 'public.referral_booking_lookups'::regclass) <> 'postgres' then
    raise exception '549: public.referral_booking_lookups was made other than tested'; end if;
  if has_table_privilege('anon', 'public.referral_booking_lookups', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.referral_booking_lookups', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'public.referral_booking_lookups', 'select,insert,update,delete,truncate,references,trigger') then
    raise exception '549: an API role holds public.referral_booking_lookups'; end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '549: public.% changed', c_relied[i]; end if;
  end loop;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || '/' || count(*) into v_fp
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
  if v_fp is distinct from c_fp_after then
    raise exception '549: the function fingerprint after installing is % , not the tested %', v_fp, c_fp_after; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
