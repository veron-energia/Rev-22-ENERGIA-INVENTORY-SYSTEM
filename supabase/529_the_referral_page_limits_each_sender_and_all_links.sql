-- 529_the_referral_page_limits_each_sender_and_all_links.sql
--
-- THE REFERRAL PAGE LIMITS EACH SENDER AND ALL LINKS TOGETHER, COUNTS EVERY TRY, AND REFUSES
-- ODD NAMES AND EMAILS
--
--   From the security audit of 17 Nov 2026 (finding M3).
--   The BEFORE md5 and the relied-on md5s below are those of production after 528 (the local
--   copy of 19 Nov 2026). If production differs when this is applied, it refuses and changes
--   nothing.
--   (The number 529 is this file's name and its errors' prefix; if it changes at commit, change
--   it there, in the 529 comments it writes into affiliate_referral_signup (and so its AFTER
--   md5, also in scripts/affiliate-signup/undo-529.sql and in the suites that know it), and
--   in the name and path of its suite.)
--
-- WHAT WAS WRONG
--
--   The public referral page /r/<code> (src/pages/ReferralSignupPage.tsx) calls
--   affiliate_referral_signup_with_notice, which calls affiliate_referral_signup; both can be
--   called signed out (the anon key) and run as their owner. Its only limits were 20 new
--   customers through one link in an hour (425) and 3 tries on one phone in 10 minutes. There
--   was no limit for one sender, and none across all links: anyone could try as often as they
--   liked with a new phone each time, through any link, and fill the customer list. And a
--   number already on file was answered "already registered" BEFORE any limit (442: "never
--   limited"), so a caller could test names and emails against a number without end and learn
--   which are on file. Two answers that say something about a number on file were raised as
--   errors (AMBIGUOUS_CUSTOMER_MATCH: several records with that phone and name;
--   CUSTOMER_PHONE_LIMIT: 3 customers have the phone, and the name typed is none of them); a
--   raised error rolls back the event row with it, so those tries were never counted (once a
--   number was full, which two sign-ups can make it, names could be tried on it without end).
--   Names and emails were taken as typed: any length, web addresses, '<', '>' and control
--   characters in a name, and anything at all as an email; and an event row kept the code as
--   typed, however long.
--
-- THE RULE (the user, 19 Nov 2026)
--
--   1. "Per sender + overall": one connection may try at most 10 times an hour, whatever the
--      answer; all links together make at most 30 new customers an hour (outcomes created,
--      phone_shared, self). Past either, the page says to try again later.
--   2. "Yes, count every try": the sender's limit and the phone's existing 3-per-10-minutes
--      limit apply before the "already registered" answer as well, with the same message
--      whether or not the number is on file. The "already registered" answer itself stays (an
--      earlier decision). This replaces 442's "never limited" for tries on details already on
--      file.
--   3. "Later, all three forms": no challenge (such as Turnstile) now.
--   4. "Refuse odd input": the name (first and last together, trimmed) at most 100
--      characters, refused if it has a web address ('://' or 'www.'), '<', '>' or control
--      characters; the email optional, but one given must look like name@domain.tld and be at
--      most 254 characters. Plain messages that say what to fix.
--   Left as it is (the Owner's 425 rule): a different name on a known number still makes a
--   record, for staff to check.
--
-- WHAT THIS DOES
--
--   * public.referral_sender_salt, new: one row holding a secret salt, 64 hex characters made at
--     random (from gen_random_uuid) when 529 runs, never in a file. Row level security on, no
--     policy, every privilege revoked from public, anon, authenticated and service_role: only
--     the owner (and so affiliate_referral_signup, which runs as the owner) reads it. A second
--     run keeps the salt it finds. Without it the sign-up refuses with a 529 error, rather than
--     count no sender.
--   * referral_signup_events gets a column sender_key: who tried, as the hex sha256 of the salt
--     and the sender's address, never the address itself (a check allows only 64 hex
--     characters or null); without the salt a key cannot be traced back to an address by
--     trying every address. The sender's address is the one Cloudflare, in front of Supabase,
--     puts in the request header cf-connecting-ip (PostgREST hands it over in the setting
--     request.headers). x-forwarded-for is never read: its first entry is whatever the sender
--     writes. An IPv4 address is one sender; an IPv6 address counts as its /64 (one home or
--     phone network gets a whole /64), an IPv4 address written as IPv6 (::ffff:a.b.c.d) as the
--     IPv4 address. No header, or one that is not a single address: no sender (null); the try
--     is recorded without one and the sender's limit does not apply (a call from inside the
--     database or a suite; every call through the API is expected to carry it).
--     Two indexes for the new counts: (sender_key, created_at) where there is a sender, and
--     (created_at) for the new customers (created, phone_shared, self).
--     The table stays as it is otherwise: row level security on, read by an Owner or Manager
--     only (its one policy), its grants unchanged.
--   * affiliate_referral_signup, in this order:
--       1. the sender (above), then the phone's lock and the sender's lock;
--       2. the sender's limit: 10 tries recorded from this sender in the last hour (any
--          outcome but this refusal) -> {ok:false, message:'Too many registration attempts
--          from this connection. Please try again in an hour, or contact Energia.'}; the
--          refusal is recorded ('sender_limit') at most once an hour for a sender, so trying
--          again and again adds nothing;
--       3. the honeypot, recorded with the sender, its pretend success as before;
--       4. the input: a phone that is not valid and a blank name raise their errors as before;
--          then the name and email rules above -> {ok:false, message} saying what to fix,
--          recorded ('invalid');
--       5. the link: not accepting -> as before ('rejected', now with the sender);
--       6. the phone's limit, 3 tries on the phone in 10 minutes, now before anything is
--          matched: the same message whether or not the number is on file; its refusal is
--          recorded ('phone_limit') but not counted by the phone's limit itself, so trying
--          again does not keep the number shut;
--       7. a phone and name that match several records (AMBIGUOUS_CUSTOMER_MATCH, from
--          require_resolved_customer_identity, caught by that message alone, or from the match
--          itself) -> {ok:false, message:'More than one customer has this phone number and
--          name. Ask staff to verify and select the correct customer record.'}, the words the
--          page showed for that error, recorded ('ambiguous');
--       8. matching and "already registered", as before (now inside both limits above; the
--          comments 442 wrote there say so);
--       9. a phone 3 customers have already (CUSTOMER_PHONE_LIMIT) -> {ok:false, message:'This
--          phone number already belongs to 3 non-deleted customers across Energia. Enter a
--          different valid number.'}, the words the page showed for that error, recorded
--          ('phone_full'); then the link's limit, as before;
--      10. new: at most 30 new customers an hour through all links together (created,
--          phone_shared and self; the event website's referrals are counted too, as the link's
--          limit counts them) -> {ok:false, message:'Registrations are very busy right now.
--          Please try again in an hour, or contact Energia.'}, recorded ('all_links_limit');
--          one lock for all links, taken last, so two sign-ups cannot both take the 30th place;
--      11. the rest as before. Every event row it writes carries the sender, and at most 64
--          characters of the code typed (left(btrim(p_code), 64); the link is still looked up
--          by the whole code, as before). 'ambiguous' and 'phone_full' rows carry the phone, so
--          both the sender's and the phone's limits count them.
--     Why the phone's lock comes before the sender's limit (the order asked for had the
--     sender's limit first): affiliate_referral_signup_with_notice takes the phone's lock
--     before it calls this, so a sender's lock taken before the phone's could wait the other
--     way round against it. Nothing is answered or recorded before the sender's limit.
--   * Its grants (signed out, signed in, the service role) are unchanged.
--
-- WHAT THIS LEAVES ALONE
--
--   * affiliate_referral_signup_with_notice (the page's call): unchanged; it passes the answer
--     on as it is, and marks a customer only when one was made.
--   * Two errors stay raised, as before, and so are not recorded: a phone that is not valid
--     (CUSTOMER_PHONE_REVIEW) and a blank name. They say nothing about what is on file (nothing
--     on file is read before them), and the page checks both before calling. Any other error
--     raised inside (require_resolved_customer_identity's included) is raised as before.
--   * The person sees the same words as before for every answer: "already registered" and the
--     others word for word, and the two errors turned into answers in the words the page showed
--     for them (phoneErrorMessage); a different name on a known number still makes a record for
--     staff to check (425). The audit entries, the customer and its check keep the code as
--     before.
--   * The event website's referral functions (event_web_apply_referral, event_web_new_customer):
--     not limited by the sender or by all links; their rows have no sender.
--   * Every row already written (no sender for them); no data changes.
--
-- UNDO
--
--   scripts/affiliate-signup/undo-529.sql (it refuses unless affiliate_referral_signup is
--   529's version and the tables are as 529 left them): the function is put back exactly as it
--   was, the column sender_key is dropped with its check and its index, the index for all links
--   is dropped, and public.referral_sender_salt is dropped (its salt is gone for good; 529 run
--   again makes a new one). The rows written while 529 was in stay, with their outcomes
--   ('sender_limit', 'invalid', 'phone_limit', 'ambiguous', 'phone_full', 'all_links_limit';
--   the old function's phone count would then count every one of them that has the phone as a
--   try). The page needs no undo: it checks the
--   same rules before calling, which only stops what the database would refuse. A later
--   migration changing affiliate_referral_signup must pin 529's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/affiliate-signup/tests/referral-limits-529.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the patched one relies on, as tested: the phone as the lock and the counts key it
  -- (normalize_customer_phone), the page's call, which takes the phone's lock before it calls
  -- the sign-up and passes its answer on (affiliate_referral_signup_with_notice), and the check
  -- whose error AMBIGUOUS_CUSTOMER_MATCH the sign-up now catches by its exact message and
  -- answers (require_resolved_customer_identity).
  c_relied constant text[] := array[
    'normalize_customer_phone(text)',
    'affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)',
    'require_resolved_customer_identity(text,text)'];
  c_relied_md5 constant text[] := array[
    'b2bfac910e0c9eff402ba44e19750bee',
    'f64347f2ccc993438f0cdb1655c7cc0f',
    '5bde1a418363442ec27e2944442f5874'];
  -- The function patched.
  c_sig constant text[] := array[
    'affiliate_referral_signup(text,text,text,text,text,text)'];
  c_before constant text[] := array[
    '2942e3d4d0e8c76600c3e0ad5e15cc2b'];
  c_after constant text[] := array[
    '00d528c6f4cc9240b2cf2f82ea2bd487'];
  -- Its grants, before and after (signed out, signed in, the service role, as before).
  c_acl constant text := 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  -- The events table: its columns, indexes and constraints before 529, and after.
  c_cols_before constant text :=
    'id uuid NO,referral_code text YES,referrer_customer_id uuid YES,new_customer_id uuid YES,normalized_phone text YES,outcome text NO,created_at timestamp with time zone NO';
  c_cols_after constant text := c_cols_before || ',sender_key text YES';
  c_idx_before constant text[] := array[
    'CREATE INDEX idx_referral_events_code_time ON public.referral_signup_events USING btree (referral_code, created_at)',
    'CREATE INDEX idx_referral_events_phone_time ON public.referral_signup_events USING btree (normalized_phone, created_at)',
    'CREATE UNIQUE INDEX referral_signup_events_pkey ON public.referral_signup_events USING btree (id)'];
  c_idx_after constant text[] := array[
    'CREATE INDEX idx_referral_events_all_links_time ON public.referral_signup_events USING btree (created_at) WHERE (outcome = ANY (ARRAY[''created''::text, ''phone_shared''::text, ''self''::text]))',
    'CREATE INDEX idx_referral_events_code_time ON public.referral_signup_events USING btree (referral_code, created_at)',
    'CREATE INDEX idx_referral_events_phone_time ON public.referral_signup_events USING btree (normalized_phone, created_at)',
    'CREATE INDEX idx_referral_events_sender_time ON public.referral_signup_events USING btree (sender_key, created_at) WHERE (sender_key IS NOT NULL)',
    'CREATE UNIQUE INDEX referral_signup_events_pkey ON public.referral_signup_events USING btree (id)'];
  c_con_before constant text[] := array[
    'referral_signup_events_pkey PRIMARY KEY (id)'];
  c_con_after constant text[] := array[
    'referral_signup_events_pkey PRIMARY KEY (id)',
    'referral_signup_events_sender_key_is_a_hash CHECK (((sender_key IS NULL) OR (sender_key ~ ''^[0-9a-f]{64}$''::text)))'];
  -- The salt table, as 529 makes it: one row, the owner's alone (no API role reads it).
  c_salt_cols constant text := 'id boolean NO,salt text NO,created_at timestamp with time zone NO';
  c_salt_con constant text[] := array[
    'referral_sender_salt_is_hex CHECK ((salt ~ ''^[0-9a-f]{64}$''::text))',
    'referral_sender_salt_one_row CHECK (id)',
    'referral_sender_salt_pkey PRIMARY KEY (id)'];
  c_salt_acl constant text := 'postgres=arwdDxtm/postgres';
  -- Seven patches, each found exactly once in the function:
  --   1. the start: the sender, the sender's limit, the honeypot, the input, the link, the phone's limit, several records
  --   2. the 442 comment on a try as herself
  --   3. details already on file: the comment and the event
  --   4. a phone 3 customers have is answered and recorded; the phone's limit is no longer here (it moved up, above)
  --   5. the link's limit records the sender; then the limit for all links
  --   6. a try as herself records the sender
  --   7. a new customer records the sender
  c_fn constant int[] := array[1, 1, 1, 1, 1, 1, 1];
  c_anchor constant text[] := array[
-- 1 the start: the sender, the sender's limit, the honeypot, the input, the link, the phone's limit, several records
$a$  v_by_email boolean := false;  -- 469: those on file were found by the phone and the email
begin
  if coalesce(btrim(p_honeypot),'') <> '' then
    insert into public.referral_signup_events(referral_code, outcome) values (btrim(p_code), 'honeypot');
    return jsonb_build_object('ok', true, 'outcome', 'registered');
  end if;

  v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_norm  := public.normalize_customer_phone(p_phone);
  v_email := nullif(lower(btrim(coalesce(p_email,''))), '');
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;
  if v_name = '' then raise exception 'Please enter your name'; end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm,0));


  select * into v_ca from public.customer_affiliates where referral_code = btrim(p_code) and deleted_at is null;
  if not found or v_ca.manually_suspended or v_ca.status <> 'active' then
    insert into public.referral_signup_events(referral_code, normalized_phone, outcome) values (btrim(p_code), v_norm, 'rejected');
    return jsonb_build_object('ok', false,
      'message', 'This referral link is not accepting new registrations right now. Please contact Energia.');
  end if;
  v_ref_cust := v_ca.customer_id;

  perform public.require_resolved_customer_identity(v_norm,v_name);
  v_matches := public.customer_phone_name_matches(v_norm,v_name);
  if cardinality(v_matches) > 1 then raise exception 'AMBIGUOUS_CUSTOMER_MATCH'; end if;
$a$,
-- 2 the 442 comment on a try as herself
$a$  -- hers, up to where a customer would be made: on details already on file,
  -- "already registered", never limited (below: an event 'self_known' in
  -- place of 'duplicate'); else the phone's 3 customers, the phone's limit
  -- and the link's limit, as for a new customer; then, in place of the
$a$,
-- 3 details already on file: the comment and the event
$a$  -- 442: a try as herself on details already on file (her record, or
  -- someone on file typed with her login's name, phone or email) is
  -- answered as anyone on file is, and never limited either; it is recorded
  -- as 'self_known' in place of 'duplicate' (the phone's limit counts both,
  -- the link's neither), with the Audit Log entry.
  if cardinality(v_matches) >= 1 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, case when cardinality(v_self) > 0 then 'self_known' else 'duplicate' end);
$a$,
-- 4 a phone 3 customers have is answered and recorded; the phone's limit is no longer here (it moved up, above)
$a$  if (select used from public.customer_phone_capacity where phone=v_norm) >= 3 then
    raise exception 'CUSTOMER_PHONE_LIMIT: This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.';
  end if;
  select count(*) into v_recent from public.referral_signup_events
   where normalized_phone=v_norm and created_at > now()-interval '10 minutes';
  if v_recent >= 3 then
    return jsonb_build_object('ok',false,'message','Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.');
  end if;
  -- 425: at most 20 new customers through one link in an hour, counted by
$a$,
-- 5 the link's limit records the sender; then the limit for all links
$a$    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, 'link_limit');
    return jsonb_build_object('ok', false, 'message',
      'This referral link has had many registrations in the last hour. Please try again later or contact Energia.');
  end if;
$a$,
-- 6 a try as herself records the sender
$a$    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, 'self');
$a$,
-- 7 a new customer records the sender
$a$  insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, normalized_phone, outcome)
    values (btrim(p_code), v_ref_cust, v_new, v_norm, case when cardinality(v_holders) > 0 then 'phone_shared' else 'created' end);
$a$];
  c_new constant text[] := array[
-- 1 the start: the sender, the sender's limit, the honeypot, the input, the link, the phone's limit, several records
$n$  v_by_email boolean := false;  -- 469: those on file were found by the phone and the email
  -- 529: who is trying (a salted one-way hash of the sender's address, or null), what is wrong
  -- with the name or the email typed, if anything, whether the phone and name match several
  -- records, and the code as the events keep it (at most 64 characters of what was typed).
  v_ip inet; v_sender text; v_bad text; v_salt text; v_ambiguous boolean := false;
  v_code text := left(btrim(p_code), 64);
begin
  -- 529 (security audit of 17 Nov 2026, M3; the user, 19 Nov 2026: "Per sender + overall",
  -- "Yes, count every try", "Refuse odd input"): every try that is answered is recorded with
  -- its sender, and limited. First the sender's limit, 10 tries an hour whatever the answer;
  -- then the phone's, 3 tries in 10 minutes, before anything is matched, so a number on file
  -- and one that is not get the same answer from it; then, after the link's limit, at most 30
  -- new customers an hour through all links together. This replaces 442's "never limited" for
  -- tries on details already on file: they are answered "already registered" as before, but
  -- only inside the sender's and the phone's limits.
  --
  -- The sender: the address Cloudflare, in front of Supabase, puts in cf-connecting-ip (never
  -- x-forwarded-for, whose first entry the sender writes). An IPv4 address is one sender; an
  -- IPv6 address, its /64. Only a one-way hash is kept (referral_signup_events.sender_key),
  -- never the address: sha256 of a secret salt and the address, the salt made when 529 ran and
  -- kept in public.referral_sender_salt, which no API role can read (never in a file), so the
  -- hash cannot be turned back into an address by trying every one. No salt: this refuses,
  -- rather than count nobody. No such header, or one that is not a single address (a call from
  -- inside the database, a suite): null, the try is recorded without a sender, and the sender's
  -- limit does not apply.
  select s.salt into v_salt from public.referral_sender_salt s where s.id;
  if v_salt is null or v_salt !~ '^[0-9a-f]{64}$' then
    raise exception '529: the sender salt (public.referral_sender_salt) is missing, so no sender can be counted. Run 529 again.';
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

  v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_norm  := public.normalize_customer_phone(p_phone);
  v_email := nullif(lower(btrim(coalesce(p_email,''))), '');
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  -- 529: the phone's lock first (the page's call, affiliate_referral_signup_with_notice, takes
  -- it before it calls this), then the sender's, so two calls never wait for each other's
  -- locks the other way round. Two tries from one sender wait for each other, so the sender's
  -- count is exact.
  if v_norm is not null then
    perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm,0));
  end if;
  if v_sender is not null then
    perform pg_advisory_xact_lock(hashtextextended('referral-sender:' || v_sender, 0));
    -- 529: at most 10 tries an hour from one sender, whatever each was answered (the
    -- refusals of this limit itself are not counted). Past it, the refusal is recorded at most
    -- once an hour for the sender, so trying again and again adds nothing.
    if (select count(*) from public.referral_signup_events e
         where e.sender_key = v_sender and e.outcome <> 'sender_limit'
           and e.created_at > now() - interval '1 hour') >= 10 then
      if not exists (select 1 from public.referral_signup_events e
                      where e.sender_key = v_sender and e.outcome = 'sender_limit'
                        and e.created_at > now() - interval '1 hour') then
        insert into public.referral_signup_events(referral_code, sender_key, outcome)
          values (v_code, v_sender, 'sender_limit');
      end if;
      return jsonb_build_object('ok', false, 'message',
        'Too many registration attempts from this connection. Please try again in an hour, or contact Energia.');
    end if;
  end if;

  if coalesce(btrim(p_honeypot),'') <> '' then
    insert into public.referral_signup_events(referral_code, sender_key, outcome) values (v_code, v_sender, 'honeypot');
    return jsonb_build_object('ok', true, 'outcome', 'registered');
  end if;

  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;
  if v_name = '' then raise exception 'Please enter your name'; end if;
  -- 529 ("Refuse odd input"; the page checks the same before it calls,
  -- src/lib/referral/signupInput.mjs): the name (first and last together, trimmed) at most 100
  -- characters, with no web address ('://' or 'www.'), no '<' or '>' and no control
  -- characters; the email may be left out, but one typed is at most 254 characters and looks
  -- like name@domain.tld. Refused with a message that says what to fix, and recorded (the
  -- sender's limit counts it).
  v_bad := case
    when char_length(v_name) > 100 then
      'Please shorten your name: your first and last name together can be at most 100 characters.'
    when strpos(v_name, '://') > 0 or strpos(lower(v_name), 'www.') > 0 then
      'Please enter just your name, without a web address.'
    when v_name ~ '[<>\u0001-\u001f\u007f-\u009f]' then
      'Please enter your name without the characters < and > or other special characters.'
    when char_length(btrim(p_email)) > 254 then
      'Please enter an email address of at most 254 characters, or leave the email blank.'
    when v_email !~ '^[^@ <>\u0001-\u001f\u007f-\u009f]+@[^@ .<>\u0001-\u001f\u007f-\u009f]+(\.[^@ .<>\u0001-\u001f\u007f-\u009f]+)*\.[^@ .<>\u0001-\u001f\u007f-\u009f]{2,}$' then
      'Please check your email address: it should look like name@example.com. Or leave the email blank.'
  end;
  if v_bad is not null then
    insert into public.referral_signup_events(referral_code, sender_key, outcome) values (v_code, v_sender, 'invalid');
    return jsonb_build_object('ok', false, 'message', v_bad);
  end if;

  select * into v_ca from public.customer_affiliates where referral_code = btrim(p_code) and deleted_at is null;
  if not found or v_ca.manually_suspended or v_ca.status <> 'active' then
    insert into public.referral_signup_events(referral_code, normalized_phone, sender_key, outcome) values (v_code, v_norm, v_sender, 'rejected');
    return jsonb_build_object('ok', false,
      'message', 'This referral link is not accepting new registrations right now. Please contact Energia.');
  end if;
  v_ref_cust := v_ca.customer_id;

  -- 529 ("Yes, count every try"): the phone's limit, 3 tries on the phone in 10 minutes, now
  -- before anything is matched (it came after "already registered" and the phone's 3
  -- customers): a number on file and one that is not get the same answer here. Its own
  -- refusals ('phone_limit') are recorded, for the sender's count and for staff, but not
  -- counted here, so trying again does not keep the number shut.
  select count(*) into v_recent from public.referral_signup_events
   where normalized_phone=v_norm and created_at > now()-interval '10 minutes' and outcome <> 'phone_limit';
  if v_recent >= 3 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'phone_limit');
    return jsonb_build_object('ok',false,'message','Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.');
  end if;

  -- 529 ("Yes, count every try"): a phone and name that match several records
  -- (AMBIGUOUS_CUSTOMER_MATCH, from require_resolved_customer_identity or from the match itself)
  -- is answered, in the words the page showed for that error, and recorded ('ambiguous', with
  -- the phone and the sender), so both limits count it. It was raised, which rolled its event
  -- back with it, so such tries were never counted. Any other error is raised as before.
  begin
    perform public.require_resolved_customer_identity(v_norm,v_name);
  exception when raise_exception then
    if sqlerrm is distinct from 'AMBIGUOUS_CUSTOMER_MATCH' then raise; end if;
    v_ambiguous := true;
  end;
  if not v_ambiguous then
    v_matches := public.customer_phone_name_matches(v_norm,v_name);
    v_ambiguous := cardinality(v_matches) > 1;
  end if;
  if v_ambiguous then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'ambiguous');
    return jsonb_build_object('ok', false, 'message',
      'More than one customer has this phone number and name. Ask staff to verify and select the correct customer record.');
  end if;
$n$,
-- 2 the 442 comment on a try as herself
$n$  -- hers, up to where a customer would be made: on details already on file,
  -- "already registered" (below: an event 'self_known' in place of
  -- 'duplicate'; 529 replaced 442's "never limited" here: the sender's and
  -- the phone's limits, above, come first); else the phone's 3 customers,
  -- the link's limit and 529's limit for all links, as for a new customer;
  -- then, in place of the
$n$,
-- 3 details already on file: the comment and the event
$n$  -- 442: a try as herself on details already on file (her record, or
  -- someone on file typed with her login's name, phone or email) is
  -- answered as anyone on file is; it is recorded as 'self_known' in place
  -- of 'duplicate' (the phone's limit counts both, the link's neither), with
  -- the Audit Log entry. 529 (the user, 19 Nov 2026, "Yes, count every
  -- try"): neither is "never limited" any more: the sender's and the
  -- phone's limits (above) come before this answer, and both count it.
  if cardinality(v_matches) >= 1 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, case when cardinality(v_self) > 0 then 'self_known' else 'duplicate' end);
$n$,
-- 4 a phone 3 customers have is answered and recorded; the phone's limit is no longer here (it moved up, above)
$n$  -- 529 ("Yes, count every try"): a phone 3 customers have already (CUSTOMER_PHONE_LIMIT) is
  -- answered, in the words the page showed for that error, and recorded ('phone_full', with the
  -- phone and the sender), so both limits count it. It was raised and so never counted: once a
  -- number was full, names could be tried on it without end (a wrong name gets this answer, the
  -- right one "already registered").
  if (select used from public.customer_phone_capacity where phone=v_norm) >= 3 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'phone_full');
    return jsonb_build_object('ok', false, 'message',
      'This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.');
  end if;
  -- 529: the phone's limit is above, before anything is matched.
  -- 425: at most 20 new customers through one link in an hour, counted by
$n$,
-- 5 the link's limit records the sender; then the limit for all links
$n$    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'link_limit');
    return jsonb_build_object('ok', false, 'message',
      'This referral link has had many registrations in the last hour. Please try again later or contact Energia.');
  end if;
  -- 529 ("Per sender + overall"): at most 30 new customers an hour through all links together
  -- (created, phone_shared and self, as the link's limit counts them; the event website's
  -- referrals are counted too, as there). Past it: refused, and recorded ('all_links_limit').
  -- One lock for all links, taken last (after the phone's and the link's), so two sign-ups
  -- cannot both take the 30th place.
  perform pg_advisory_xact_lock(hashtextextended('referral-all-links', 0));
  if (select count(*) from public.referral_signup_events e
       where e.outcome in ('created', 'phone_shared', 'self')
         and e.created_at > now() - interval '1 hour') >= 30 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'all_links_limit');
    return jsonb_build_object('ok', false, 'message',
      'Registrations are very busy right now. Please try again in an hour, or contact Energia.');
  end if;
$n$,
-- 6 a try as herself records the sender
$n$    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'self');
$n$,
-- 7 a new customer records the sender
$n$  insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, normalized_phone, sender_key, outcome)
    values (v_code, v_ref_cust, v_new, v_norm, v_sender, case when cardinality(v_holders) > 0 then 'phone_shared' else 'created' end);
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  v_add_table boolean := false;
  v_add_salt boolean := false;
  v_cols text; v_idx text[]; v_con text[];
  v_tbl_acl text; v_policies text;
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table or function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '529: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  -- sha256 (built in since PostgreSQL 11) makes the sender's hash.
  if to_regprocedure('pg_catalog.sha256(bytea)') is null then
    raise exception '529: pg_catalog.sha256(bytea) is missing'; end if;
  -- The events table: as before 529 (the column, its check and the two indexes are added), or
  -- as 529 left it (left alone); anything else refuses. Row level security on.
  if to_regclass('public.referral_signup_events') is null then
    raise exception '529: public.referral_signup_events is missing'; end if;
  v_cols := (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
               from information_schema.columns where table_schema = 'public' and table_name = 'referral_signup_events');
  v_idx := (select array_agg(pg_get_indexdef(x.indexrelid) order by pg_get_indexdef(x.indexrelid))
              from pg_index x where x.indrelid = 'public.referral_signup_events'::regclass);
  v_con := (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
              from pg_constraint c where c.conrelid = 'public.referral_signup_events'::regclass);
  if v_cols = c_cols_before and v_idx = c_idx_before and v_con = c_con_before then
    v_add_table := true;
  elsif v_cols = c_cols_after and v_idx = c_idx_after and v_con = c_con_after then
    raise notice '529: public.referral_signup_events already has sender_key, its check and both indexes; left alone';
  else
    raise exception '529: public.referral_signup_events is not as tested (columns %; indexes %; constraints %). Re-read it before applying.',
      v_cols, v_idx, v_con;
  end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.referral_signup_events'::regclass) then
    raise exception '529: row level security is off on public.referral_signup_events'; end if;
  v_tbl_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                  from pg_class c, unnest(c.relacl) x where c.oid = 'public.referral_signup_events'::regclass);
  v_policies := (select coalesce(string_agg(p.polname || ' ' || p.polcmd::text || ' ' || p.polpermissive::text || ' ' || p.polroles::text
                                            || ' ' || coalesce(pg_get_expr(p.polqual, p.polrelid), '')
                                            || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''), ',' order by p.polname), '')
                   from pg_policy p where p.polrelid = 'public.referral_signup_events'::regclass);
  -- The salt table: missing (made, with a new random salt), or as 529 made it with its one
  -- row (left alone: the salt is kept, so the senders already recorded keep their keys).
  if to_regclass('public.referral_sender_salt') is null then
    v_add_salt := true;
  elsif (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
           from information_schema.columns where table_schema = 'public' and table_name = 'referral_sender_salt') = c_salt_cols
        and (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
               from pg_constraint c where c.conrelid = 'public.referral_sender_salt'::regclass) = c_salt_con
        and (select c.relrowsecurity from pg_class c where c.oid = 'public.referral_sender_salt'::regclass)
        and not exists (select 1 from pg_policy p where p.polrelid = 'public.referral_sender_salt'::regclass)
        and (select coalesce(string_agg(x::text, ',' order by x::text), '')
               from pg_class c, unnest(c.relacl) x where c.oid = 'public.referral_sender_salt'::regclass) = c_salt_acl
        and (select count(*) from public.referral_sender_salt) = 1
        and (select bool_and(s.id and s.salt ~ '^[0-9a-f]{64}$') from public.referral_sender_salt s) then
    raise notice '529: public.referral_sender_salt is already there with its salt; left alone (the salt is kept)';
  else
    raise exception '529: a table public.referral_sender_salt is there, but not as 529 makes it (its columns, checks, one row, row level security with no policy, the owner''s alone). Re-read it before applying.';
  end if;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '529: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if v_acl[i] is distinct from c_acl then
      raise exception '529: the grants of public.% are not the tested ones (%). Re-read them before applying.', c_sig[i], v_acl[i]; end if;
    if md5(d) = c_after[i] then
      raise notice '529: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '529: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  -- The function reads the column and the salt, so all three are as before or all as 529 left them.
  if v_add_table is distinct from v_make[1] or v_add_salt is distinct from v_make[1] then
    raise exception '529: public.affiliate_referral_signup, public.referral_signup_events and public.referral_sender_salt are not all before 529 or all after it. Re-read them before applying.';
  end if;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '529: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '529: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install: the salt, the column, its check and the indexes first (the patched function
  --    reads, writes and counts them)
  if v_add_salt then
    create table public.referral_sender_salt (
      id boolean primary key default true constraint referral_sender_salt_one_row check (id),
      salt text not null constraint referral_sender_salt_is_hex check (salt ~ '^[0-9a-f]{64}$'),
      created_at timestamp with time zone not null default now());
    alter table public.referral_sender_salt enable row level security;
    revoke all on table public.referral_sender_salt from public, anon, authenticated, service_role;
    comment on table public.referral_sender_salt is
      '529: the secret salt of referral_signup_events.sender_key (sha256 of it and the sender''s address), made at random when 529 ran. Never in a file; no API role reads it (row level security on, no policy, no grant). affiliate_referral_signup reads it; without it, it refuses.';
    -- Three random UUIDs (gen_random_uuid: the server's strong random source), hashed.
    insert into public.referral_sender_salt(salt)
    values (encode(sha256(convert_to(gen_random_uuid()::text || gen_random_uuid()::text || gen_random_uuid()::text, 'UTF8')), 'hex'));
  end if;
  if v_add_table then
    alter table public.referral_signup_events
      add column sender_key text
      constraint referral_signup_events_sender_key_is_a_hash check (sender_key is null or sender_key ~ '^[0-9a-f]{64}$');
    comment on column public.referral_signup_events.sender_key is
      '529: who tried, as the hex sha256 of a secret salt (public.referral_sender_salt) and the sender''s address (cf-connecting-ip; an IPv6 address as its /64), never the address itself. Null when the call carried no such address. affiliate_referral_signup counts it: 10 tries an hour from one sender.';
    create index idx_referral_events_sender_time on public.referral_signup_events (sender_key, created_at)
      where sender_key is not null;
    create index idx_referral_events_all_links_time on public.referral_signup_events (created_at)
      where outcome in ('created', 'phone_shared', 'self');
  end if;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'referral_sender_salt') is distinct from c_salt_cols
     or (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
           from pg_constraint c where c.conrelid = 'public.referral_sender_salt'::regclass) is distinct from c_salt_con
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.referral_sender_salt'::regclass)
     or exists (select 1 from pg_policy p where p.polrelid = 'public.referral_sender_salt'::regclass)
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_class c, unnest(c.relacl) x where c.oid = 'public.referral_sender_salt'::regclass) is distinct from c_salt_acl
     or has_table_privilege('anon', 'public.referral_sender_salt', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.referral_sender_salt', 'select,insert,update,delete')
     or has_table_privilege('service_role', 'public.referral_sender_salt', 'select,insert,update,delete')
     or (select count(*) from public.referral_sender_salt) <> 1 then
    raise exception '529: public.referral_sender_salt is not as tested after making it (one row, the owner''s alone)'; end if;
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'referral_signup_events') is distinct from c_cols_after
     or (select array_agg(pg_get_indexdef(x.indexrelid) order by pg_get_indexdef(x.indexrelid))
           from pg_index x where x.indrelid = 'public.referral_signup_events'::regclass) is distinct from c_idx_after
     or (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
           from pg_constraint c where c.conrelid = 'public.referral_signup_events'::regclass) is distinct from c_con_after then
    raise exception '529: public.referral_signup_events is not as tested after adding sender_key'; end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.referral_signup_events'::regclass)
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_class c, unnest(c.relacl) x where c.oid = 'public.referral_signup_events'::regclass) is distinct from v_tbl_acl
     or (select coalesce(string_agg(p.polname || ' ' || p.polcmd::text || ' ' || p.polpermissive::text || ' ' || p.polroles::text
                                    || ' ' || coalesce(pg_get_expr(p.polqual, p.polrelid), '')
                                    || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''), ',' order by p.polname), '')
           from pg_policy p where p.polrelid = 'public.referral_signup_events'::regclass) is distinct from v_policies then
    raise exception '529: the row level security, grants or policies of public.referral_signup_events changed'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '529: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '529: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '529: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
