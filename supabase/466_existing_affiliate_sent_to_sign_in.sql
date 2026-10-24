-- 466_existing_affiliate_sent_to_sign_in.sql
--
-- AN AFFILIATE SIGN-UP WITH THE EMAIL OR PHONE OF AN EXISTING AFFILIATE IS
-- SENT TO SIGN IN, AND NOTHING IS MADE (the Owner, 24 Oct 2026)
--
-- WHAT WAS WRONG
--
--   On /affiliate/join, Create Account (the Edge Function
--   auth-signup-request) checks only that the email typed is not already a
--   login (437's email_in_use). A phone is not checked before the login is
--   made: an affiliate who signs up again with another email and her own
--   phone gets a second login, and complete_affiliate_onboarding (437) then
--   makes that login a second affiliate on a fresh customer record, listed
--   for staff ('customer_has_login'), while her real account stays as it
--   is. The same for the email her record or her sign-up holds, when it is
--   not her login's.
--
-- THE RULES (the Owner, 24 Oct 2026)
--
--   The request, exactly: "For affiliate sign up, if the phone number or
--   email is already used to sign up, reroute them to the sign in page
--   instead of signing up for them."
--   The Owner's answers, the same day:
--   1. "Already used" means an EXISTING AFFILIATE only: the email of any
--      affiliate login, or the phone or email an affiliate signed up with
--      (440's uneditable copy, affiliate_signup_identities) or has on their
--      customer record. A normal customer who is not an affiliate yet still
--      signs up with their phone exactly as today (437 decision 7: a phone
--      matching one customer joins that record).
--   2. Straight to the Sign in page (/affiliate/login), with a short message
--      on top and the email filled in when it was the email that matched.
--      Nothing is created (no login, no customer, no claim).
--   3. When only the PHONE matches (they typed another email), the message
--      shows a MASKED hint of the affiliate's LOGIN email, e.g.
--      "s•••@rev22.com.sg", to help them remember.
--   4. Privacy accepted: the form tells anyone whether a phone (as it
--      already does an email) belongs to an affiliate account. Tries stay
--      rate-limited (the database-backed limits the sign-up function already
--      reserves before it does anything: 3 per email in 15 minutes, 30 per
--      network in an hour) and each such try is logged for staff: an Audit
--      Log row on the matched affiliate's record.
--   Defaults where the answers leave a choice (each put to the Owner):
--   a. Several affiliates on the phone: no hint; the message says the phone
--      already has an affiliate account, to sign in with the email they used
--      or reset the password.
--   b. The mask: the first character of the part before the @, then "•••",
--      the @ and the whole domain; a one-character part gives "•••@domain".
--   c. An email that is ANY login's (a member of staff, a sign-up that never
--      finished, a login with no affiliate account) keeps today's answer
--      (email_in_use, the sign-up function's own check), now a redirect to
--      Sign in. Only the phone, and the emails of records and copies, are
--      matched against affiliates alone.
--   d. A closed, suspended or not yet verified affiliate still counts (they
--      sign in, and the portal says how their account stands).
--   e. The /r/<code> referral page (a customer referral, not an affiliate
--      account) is unchanged.
--   f. Phones through the app's own normalisation (normalize_customer_phone),
--      not raw text: "+65 9123 4567", "6591234567" and "91234567" are one
--      phone.
--   g. An email on an affiliate's record or sign-up copy (the same address,
--      or the same Gmail inbox: customer_email_match_key) that is not her
--      login email: sent to Sign in like an email match, but nothing filled
--      in (that address cannot sign in) and the masked login email shown
--      when it is one login. A Gmail address spelt another way (dots, a
--      +tag) than ANY login's, an affiliate's or staff's, is a new email
--      (only the same address counts there), so the answer never tells an
--      affiliate's login from staff's; the phone is still checked.
--   h. An affiliate's stored 8-digit number that could be Singapore or
--      Malaysia (437's "maybe" holder) counts when the phone typed is one of
--      its readings.
--   i. A customer who shares the phone with an affiliate but is not one (a
--      family member on a household phone, with a record of her own) still
--      signs up as today (answer 1, second sentence; 437's 8 joins her own
--      record by name) when the name she types is her record's (as typed or
--      the same words) and not the name of an affiliate on that phone (that
--      affiliate's record or sign-up copy). Anyone else typing the phone
--      (no record of her own on it, no name, or an affiliate's own name) is
--      sent to Sign in. In production on 24 Oct 2026 (counts only): 8 such
--      customers; 5 would sign up as today under their record's name, 3 have
--      a name that is also an affiliate's on that phone (most likely the
--      affiliate's own second record) and would be sent to Sign in.
--
-- HOW IT READS (this file, 24 Oct 2026)
--
--   * An affiliate is a login with an affiliate account (affiliate_accounts),
--     whatever the account's, the affiliate record's or the login's state
--     (d); a login deleted in Supabase is nobody. A customer with an
--     affiliate record and no login is not one: 437 still joins them by
--     phone, as today.
--   * What is compared, for each affiliate login: the email typed with its
--     login email ('login_email': that address itself, trimmed and in lower
--     case, as Supabase compares it), and, as that address or through the
--     app's inbox key (customer_email_match_key, as 432 and 440 compare
--     emails), with the email of its sign-up copy ('signup_email'; the copy
--     read through 440's helper affiliate_login_signup_details, as the
--     no-self-referral checks read it, never the table itself) and its
--     customer record's ('record_email'). The inbox key is not used when
--     some login (anyone's) has that inbox under another spelling (g). The
--     phone typed (normalize_customer_phone), with the phone of its copy
--     ('signup_phone') and its record's ('record_phone'), and, for a stored
--     8-digit number that could be Singapore or Malaysia, its readings
--     ('signup_phone_unconfirmed', 'record_phone_unconfirmed', h).
--   * The answer, the email first:
--       - the email typed is an affiliate's login email: 'email', login_email
--         true (the sign-up function answers it as today's email_in_use,
--         and the page fills it in);
--       - else, the email typed is another login's (c): nothing (the
--         sign-up function's own check answers email_in_use; nothing of an
--         affiliate is told, so nothing is logged);
--       - else, an email kind: 'email', login_email false (g);
--       - else, a phone kind: 'phone', unless the name typed is that of a
--         customer of her own on the phone with no login, and is no
--         affiliate's on it (i): nothing (the sign-up goes on; 437 joins
--         her record);
--       - else nothing.
--     Names are compared as 437 picks among the customers on a phone: as
--     typed (normalize_customer_match_name), or the same words
--     (customer_names_match). The name is the sign-up's first and last name,
--     as complete_affiliate_onboarding puts them together; with no name
--     passed, a phone match is always 'phone'.
--     With the answer, email_hint: the masked login email (b) when exactly
--     one affiliate login is matched by what was answered and the email
--     typed is not that login's (3, g); several logins, no hint (a); none
--     either when the mask is not of the shape the sign-up function shows
--     (an address with a domain outside a-z, 0-9, dot and dash, say), so
--     the Audit Log never says a hint was shown that was not.
--   * Logged: one Audit Log row per affiliate account matched by what was
--     answered (not by what was not told): table 'customers', the record its
--     account is on, action 'affiliate_signup_sent_to_sign_in', module
--     'affiliate', with what was answered, all it matched, the account and
--     login, the phone typed (normalised), the email and the name typed (at
--     most 200 characters each), whether a hint was shown, how many logins
--     matched, the sign-up function's request id (the request_id of its
--     auth_email_deliveries row, which holds the outcome) and the version.
--     Written straight into audit_logs with no one signed in (the Audit Log
--     shows "System"), as 437 and 442 do; best effort (a row that cannot be
--     saved never turns the refusal into a sign-up).
--   * Nothing else is written: no login (the sign-up function asks this
--     before it makes one), no customer, no claim, no list entry.
--
-- WHAT THIS DOES
--
--   affiliate_signup_existing(p_phone text, p_email text, p_name text
--   default null, p_request_id uuid default null) (new, the service role's
--   alone): the answer above, as jsonb {matched: 'email' | 'phone' | null,
--   login_email, email_hint, affiliates}, and the Audit Log rows.
--   With it, in the same change (not in this file): the sign-up function asks
--   it (with the phone, the email and the name typed, and its request id),
--   together with its own login check, before anything else and answers 409
--   'email_in_use' (an affiliate's login email; today's body, with matched
--   'email') or 409 'affiliate_exists' (matched 'email' or 'phone',
--   email_hint, and the message); the Join page sends the person to
--   /affiliate/login with the message (from the page's own words, never
--   from the address bar, and announced to screen readers) and, for
--   email_in_use, the email filled in; Back from there brings the form back
--   as it was typed, without the passwords.
--
-- NOT CHANGED
--
--   * complete_affiliate_onboarding (437/440) and its rules for anyone who
--     reaches it: a customer who is not an affiliate still joins their
--     record by phone (437's 7 and 8); every other function; every table.
--   * auth_email_user_state and the limiter (auth_email_reserve); the
--     resend and recovery functions.
--   * /r/<code> (affiliate_referral_signup, public_affiliate_referral_info)
--     and the seminar websites (e).
--
-- NOT COVERED (told to the Owner)
--
--   * (i) The name tells a family member from the affiliate. A family member
--     on an affiliate's phone with no record of her own (or none under the
--     name she types) is sent to Sign in (before: a fresh record listed for
--     staff); she can sign up with a phone of her own and staff Link her
--     record (437's 6). An affiliate who types a name that is no affiliate
--     record's or copy's on her phone but is that of a second record of hers
--     there is let through, and 437 joins that record: a second affiliate
--     account, as before 466.
--   * The limits count tries per email and per network, not per phone:
--     someone changing email and network can test phones at the network
--     rate. Each try that tells is in the Audit Log.
--   * Checked at Create Account only. Two people signing up at the same
--     moment on one new phone both get logins, as today.
--   * A login with no affiliate account (a sign-up from before 437 that
--     never signed in, or a sign-in that failed after Create Account) is not
--     an affiliate. Its email is sent to Sign in as any login's is (c; the
--     Join page's Sign in button did the same before), and its first sign-in
--     still finishes the sign-up through complete_affiliate_onboarding,
--     unchanged: on an existing affiliate's phone, that makes a second
--     affiliate account. In production on 24 Oct 2026 (counts only): 16 such
--     logins (made 4 Sep to 19 Oct, none ever signed in, no claims); 6 of
--     them signed up with a phone an existing affiliate has (4 under the
--     same name as that affiliate). For staff to review before go-live; a
--     guard at sign-in would be a later migration.
--   * A hint is the login email as it is now; an affiliate who changed her
--     login email is shown the new one.
--   * (g) An affiliate who types her Gmail login spelt another way (no dots,
--     a +tag) with a phone that is no affiliate's gets a new login, as
--     before 466 (437/432 then deal with it at her first sign-in); her
--     phone, or her record's or her copy's address as it is written, still
--     sends her to Sign in. In production on 24 Oct 2026 (counts only): 97
--     logins, 55 of them Gmail (6 no affiliate's); no two logins share an
--     inbox; 1 affiliate record holds a Gmail address that is a login's
--     inbox spelt another way (matched when typed as the record has it).
--   * Timing: the sign-up function asks this and its own login check at
--     once on every path, so an affiliate's login email and staff's take the
--     same round trips. What is left: when an affiliate matches, this writes
--     her Audit Log row before answering. On a local copy of production's
--     functions (made-up rows) that is about 0.3 to 0.6 ms more than a staff
--     email (40 calls each): far less than a request's own network jitter,
--     but not proven unmeasurable over many tries (3 per email in 15
--     minutes, 30 per network in an hour).
--   * The Audit Log row keeps the email typed in clear (the delivery rows
--     keep only a keyed hash), for the staff follow-up the Owner asked for;
--     managers and above read it. It does not keep the network: tries from
--     one network across many emails are linked only through the limiter
--     (30 an hour), not in the Audit Log.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text below is the tested one; the function is missing or exactly
--     this version (left alone); no other function takes its name;
--   * the functions it calls are as read on production on 24 Oct 2026
--     (below), and the columns it reads and writes are there, of the types
--     read.
--   Afterwards: its md5 is the AFTER one; anon, authenticated and PUBLIC
--   cannot execute it, the service role can. Then a self-test, in a block
--   that is always undone (it ends by raising P0466, so it leaves no row):
--   a made-up affiliate (@example.invalid, fictional phones no customer or
--   copy uses) is found by her record's phone (with the hint, and the
--   request id given on its Audit Log row), her copy's phone in another
--   form, her login email in capitals (no hint, login email), her record's
--   email (with the hint); a phone and email nobody has find nothing; a
--   made-up customer of her own on the affiliate's phone (no login) typing
--   her own name finds nothing, and the affiliate's own name on that phone
--   is still the phone; each answer that matched wrote one Audit Log row,
--   the others none, and no login or customer was made by the calls. Its
--   made-up affiliate account queues its welcome WhatsApp (394's trigger),
--   undone with the rest; only the outbox's id sequence moves on by one each
--   run (a sequence is never rolled back: a gap in affiliate_whatsapp_outbox
--   ids, nothing sent, no row left). A second run changes nothing else
--   ("already this version; left alone"). Takes no lock beyond the
--   function's own creation and the self-test's new rows.
--
-- DEPLOY ORDER (each with the Owner's go-ahead)
--
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second says
--      "already this version; left alone" and changes nothing.
--   2. Apply 466 (the CLI, or the MCP's apply_migration with this text
--      verbatim). The sign-up function running now never calls it.
--   3. Deploy auth-signup-request (its new text calls this function; before
--      2 every sign-up would answer 503, nothing made):
--        supabase functions deploy auth-signup-request --no-verify-jwt
--   4. Deploy the pages (Vercel: AffiliateJoinPage, AffiliateLoginPage,
--      lib/auth-email). 3 and 4 in either order: a page from before answers
--      email_in_use as today and shows affiliate_exists's message on the
--      form; a page from after, with the sign-up function from before,
--      redirects on email_in_use and never meets affiliate_exists.
--
-- BEFORE (production, 24 Oct 2026: head 20261024045047, 467 after 465; md5
-- of pg_get_functiondef with search_path public)
--   new
--   affiliate_signup_existing(text,text,text,uuid)                   missing
--   relied on, not changed
--   normalize_customer_phone(text)                                   b2bfac910e0c9eff402ba44e19750bee
--   inspect_customer_phone(text,text)                                6672c4d1963996f3b601896f4a55916e
--   customer_email_match_key(text)                                   be468815c9626fff1728e2cfcd484b66
--   affiliate_login_signup_details(uuid)                             71e6d6f9ab2b474450b5c00f60f14bb4  (440's)
--   normalize_customer_match_name(text)                              0572764712e179dc606c66f9f3dbaa03
--   customer_names_match(text,text)                                  ef1af52e4888cefb6037a2291f4e011d  (432's)
--   public function fingerprint, production now (467 in)             732a3805a2fafa035c5a46068026c81f (1380 functions)
--     ... at 465, before 467                                         0b8580cda1e2c697a1e9219f95ed3046 (1380)
-- AFTER (for later guards)
--   affiliate_signup_existing(text,text,text,uuid)                   27e3b1ad5a583bc6421d783b5a7db45a
--   public function fingerprint, worked out on copies of production (24 Oct 2026):
--     production now (467 in) -> 466                                 41a2fcab90c95090a71c688d7f0a17cd (1381)
--     at 465, before 467 -> 466                                      33a691036d4958319d72d6ca6fe1a43c (1381)
--   (467, TikTok order times, and 466 touch none of each other's functions.)
--
-- Test: scripts/affiliate-signup/tests/existing-affiliate-466.sql (begin ...
-- rollback; it installs this file twice, or with -v skip_install=1 where it
-- is in). Edge: supabase/functions/_shared/auth-email/tests (deno). Pages:
-- scripts/affiliate-signup/tests/existing-affiliate-pages-466.test.mjs.

set lock_timeout = '5s';

do $mig$
declare
  c_sig constant text := 'affiliate_signup_existing(text,text,text,uuid)';
  c_md5 constant text := '27e3b1ad5a583bc6421d783b5a7db45a';
  c_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.affiliate_signup_existing(p_phone text, p_email text, p_name text DEFAULT NULL::text, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  -- 466 (the Owner, 24 Oct 2026): what of an affiliate sign-up an existing
  -- affiliate account already has, asked by the sign-up function
  -- (auth-signup-request, with the service key) before any login is made.
  -- An affiliate is a login with an affiliate account, whatever its state.
  -- The email typed is compared, through the app's inbox key
  -- (customer_email_match_key), with each such login's email, the email it
  -- signed up with (440's copy, read through affiliate_login_signup_details)
  -- and its customer record's; the phone typed, through
  -- normalize_customer_phone, with the phone it signed up with and its
  -- record's (a stored 8-digit number that could be Singapore or Malaysia
  -- counts when the phone typed is one of its readings, as 437 reads it).
  -- A Gmail inbox that some login has under another spelling (dots, a
  -- +tag), whoever's login it is, is compared as typed, not by inbox: the
  -- answer must not tell an affiliate's login from staff's.
  -- The email first. An email that is the login of someone who
  -- is not an affiliate (staff, a sign-up not finished) is the sign-up
  -- function's own email_in_use, not this. A phone alone is not an
  -- affiliate's for a customer of her own on it who is not one (a family
  -- member on the household phone): the name typed has the same words as
  -- her record's and as no affiliate's on the phone; 437 then joins her
  -- record, as today. Nothing is made; each affiliate matched gets an Audit
  -- Log row on their record, with the sign-up function's request id.
  c_email_kinds constant text[] := array['login_email', 'signup_email', 'record_email'];
  c_phone_kinds constant text[] := array['signup_phone', 'record_phone', 'signup_phone_unconfirmed', 'record_phone_unconfirmed'];
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_key text := public.customer_email_match_key(p_email);
  v_phone text := public.normalize_customer_phone(p_phone);
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_name_key text := public.normalize_customer_match_name(p_name);
  v_hits jsonb; v_kinds text[]; v_answered text; v_login_email boolean := false;
  v_logins uuid[] := '{}'::uuid[]; v_login text; v_local text; v_domain text; v_hint text; r record;
begin
  if v_key is not null
     and exists (select 1 from auth.users u
                  where u.deleted_at is null and lower(btrim(u.email)) is distinct from v_email
                    and public.customer_email_match_key(u.email) = v_key) then
    v_key := null;
  end if;

  -- Each affiliate login and what of the sign-up it already has.
  select coalesce(jsonb_agg(jsonb_build_object('account_id', h.account_id, 'auth_user_id', h.auth_user_id,
                      'customer_id', h.customer_id, 'login_email', h.login_email, 'kinds', to_jsonb(h.kinds))
                    order by h.created_at, h.account_id), '[]'::jsonb)
    into v_hits
    from (
      select a.id as account_id, a.auth_user_id, a.customer_id, a.created_at, lower(btrim(u.email)) as login_email,
             array_remove(array[
               case when v_email is not null and lower(btrim(u.email)) = v_email then 'login_email' end,
               case when v_email is not null
                         and exists (select 1 from public.affiliate_login_signup_details(a.customer_id) i
                                      where i.auth_user_id = a.auth_user_id
                                        and (public.customer_email_match_key(i.email) = v_key
                                             or lower(btrim(i.email)) = v_email)) then 'signup_email' end,
               case when v_email is not null
                         and (public.customer_email_match_key(c.email) = v_key or lower(btrim(c.email)) = v_email)
                    then 'record_email' end,
               case when v_phone is not null
                         and exists (select 1 from public.affiliate_login_signup_details(a.customer_id) i
                                      where i.auth_user_id = a.auth_user_id
                                        and public.normalize_customer_phone(i.phone) = v_phone) then 'signup_phone' end,
               case when v_phone is not null and public.normalize_customer_phone(c.phone) = v_phone then 'record_phone' end,
               case when v_phone is not null
                         and exists (select 1 from public.affiliate_login_signup_details(a.customer_id) i
                                      where i.auth_user_id = a.auth_user_id
                                        and public.normalize_customer_phone(i.phone) is null
                                        and i.phone ~ '^[\s().0-9-]+$'
                                        and (public.inspect_customer_phone(i.phone) -> 'candidates') ? v_phone)
                    then 'signup_phone_unconfirmed' end,
               case when v_phone is not null and public.normalize_customer_phone(c.phone) is null
                         and c.phone ~ '^[\s().0-9-]+$'
                         and (public.inspect_customer_phone(c.phone) -> 'candidates') ? v_phone
                    then 'record_phone_unconfirmed' end
             ]::text[], null) as kinds
        from public.affiliate_accounts a
        join auth.users u on u.id = a.auth_user_id and u.deleted_at is null
        left join public.customers c on c.id = a.customer_id and c.deleted_at is null
    ) h
   where cardinality(h.kinds) > 0;

  if exists (select 1 from jsonb_array_elements(v_hits) h where h -> 'kinds' ? 'login_email') then
    -- The email typed is an affiliate's own login: Sign in with it.
    v_answered := 'email'; v_login_email := true; v_kinds := c_email_kinds;
  elsif v_email is not null
        and exists (select 1 from auth.users u where lower(btrim(u.email)) = v_email and u.deleted_at is null) then
    -- Another login's email (staff, a sign-up not finished): the sign-up
    -- function answers it itself (email_in_use). Nothing of an affiliate is
    -- told, so nothing is logged.
    return jsonb_build_object('matched', null, 'login_email', false, 'email_hint', null, 'affiliates', 0);
  elsif exists (select 1 from jsonb_array_elements(v_hits) h where h -> 'kinds' ?| c_email_kinds) then
    v_answered := 'email'; v_kinds := c_email_kinds;
  elsif exists (select 1 from jsonb_array_elements(v_hits) h where h -> 'kinds' ?| c_phone_kinds) then
    -- A customer of her own on the phone who is not an affiliate (no login):
    -- the name typed is her record's (as typed, or the same words, as 437
    -- picks among those on a phone), and not the name of an affiliate the
    -- phone matched (her record's or her sign-up's: an affiliate typing her
    -- own name is sent to Sign in even with a second record of her on the
    -- phone). She signs up as today; nothing of an affiliate is told.
    if v_name is not null
       and exists (select 1 from public.customers c
                    where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_phone
                      and not exists (select 1 from public.affiliate_accounts a where a.customer_id = c.id)
                      and ((v_name_key <> '' and public.normalize_customer_match_name(c.full_name) = v_name_key)
                           or public.customer_names_match(c.full_name, v_name)))
       and not exists (select 1 from jsonb_array_elements(v_hits) h
                         left join public.customers ac on ac.id = (h ->> 'customer_id')::uuid
                        where h -> 'kinds' ?| c_phone_kinds
                          and (((v_name_key <> '' and public.normalize_customer_match_name(ac.full_name) = v_name_key)
                                or public.customer_names_match(ac.full_name, v_name))
                               or exists (select 1 from public.affiliate_login_signup_details((h ->> 'customer_id')::uuid) i
                                           where i.auth_user_id = (h ->> 'auth_user_id')::uuid
                                             and ((v_name_key <> '' and public.normalize_customer_match_name(i.full_name) = v_name_key)
                                                  or public.customer_names_match(i.full_name, v_name))))) then
      return jsonb_build_object('matched', null, 'login_email', false, 'email_hint', null, 'affiliates', 0);
    end if;
    v_answered := 'phone'; v_kinds := c_phone_kinds;
  else
    return jsonb_build_object('matched', null, 'login_email', false, 'email_hint', null, 'affiliates', 0);
  end if;

  select coalesce(array_agg(distinct (h ->> 'auth_user_id')::uuid), '{}'::uuid[]) into v_logins
    from jsonb_array_elements(v_hits) h where h -> 'kinds' ?| v_kinds;

  -- A hint of the one login's email, when the email typed is not it: the
  -- first character of the part before the @, then ••• and the whole domain.
  if cardinality(v_logins) = 1 and not v_login_email then
    select h ->> 'login_email' into v_login from jsonb_array_elements(v_hits) h
     where (h ->> 'auth_user_id')::uuid = v_logins[1] limit 1;
    v_local := substring(v_login from '^(.*)@[^@]*$');
    v_domain := substring(v_login from '@([^@]*)$');
    if v_local is not null and coalesce(v_domain, '') <> '' then
      v_hint := case when char_length(v_local) > 1 then left(v_local, 1) else '' end || '•••@' || v_domain;
    end if;
  end if;
  -- Only a hint of the shape the sign-up function shows (its EMAIL_HINT_RE,
  -- in ASCII here) is given, so the Audit Log says a hint was shown only
  -- when it was.
  if v_hint is not null
     and not (char_length(v_hint) <= 256
              and v_hint ~ '^[!-~]?•••@[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$'
              and v_hint !~ '^[@<>"''`\\]') then
    v_hint := null;
  end if;

  -- Staff see each try: an Audit Log row on each affiliate's record,
  -- written straight into audit_logs with no one signed in ("System"), as
  -- 442 does. Best effort: a row not saved never turns this into a sign-up.
  for r in select (h ->> 'account_id')::uuid as account_id, (h ->> 'auth_user_id')::uuid as auth_user_id,
                  (h ->> 'customer_id')::uuid as customer_id, h -> 'kinds' as kinds
             from jsonb_array_elements(v_hits) h where h -> 'kinds' ?| v_kinds loop
    begin
      insert into public.audit_logs (table_name, record_id, action, new_data, module)
      values ('customers', r.customer_id, 'affiliate_signup_sent_to_sign_in',
              jsonb_build_object('answered', v_answered, 'matched', r.kinds, 'affiliate_account_id', r.account_id,
                'auth_user_id', r.auth_user_id,
                'phone', coalesce(v_phone, nullif(left(btrim(coalesce(p_phone, '')), 40), '')),
                'email', left(v_email, 200), 'name', left(v_name, 200), 'email_hint_shown', v_hint is not null,
                'affiliates_matched', cardinality(v_logins), 'source', 'affiliate_join', 'request_id', p_request_id,
                'version', 466),
              'affiliate');
    exception when others then
      raise warning '466: the Audit Log row of a sign-up sent to Sign in was not saved: %', sqlerrm;
    end;
  end loop;

  return jsonb_build_object('matched', v_answered, 'login_email', v_login_email, 'email_hint', v_hint,
                            'affiliates', cardinality(v_logins));
end $function$
$def$;

  -- ── Relied on, not changed (production, 24 Oct 2026) ─────────────────────
  c_relied constant text[] := array['normalize_customer_phone(text)', 'inspect_customer_phone(text,text)',
    'customer_email_match_key(text)', 'affiliate_login_signup_details(uuid)',
    'normalize_customer_match_name(text)', 'customer_names_match(text,text)'];
  c_relied_md5 constant text[] := array['b2bfac910e0c9eff402ba44e19750bee', '6672c4d1963996f3b601896f4a55916e',
    'be468815c9626fff1728e2cfcd484b66', '71e6d6f9ab2b474450b5c00f60f14bb4',
    '0572764712e179dc606c66f9f3dbaa03', 'ef1af52e4888cefb6037a2291f4e011d'];

  v_path text := current_setting('search_path');
  v text; n int;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_u uuid; t_cust uuid; t_aff uuid; t_acct uuid; t_mail text; t_rec text;
  t_ans jsonb; t_logs int; t_users int; t_custs int; t_req uuid := gen_random_uuid();
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  if md5(c_def) <> c_md5 then
    raise exception '466: the text of public.% is not the tested one (md5 %)', c_sig, md5(c_def); end if;
  if to_regprocedure('public.' || c_sig) is not null
     and md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_md5 then
    raise exception '466: public.% exists and is not this migration''s (md5 %). Re-read it and re-test before applying.', c_sig,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))); end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = split_part(c_sig, '(', 1)
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '466: another function takes this name: %', v; end if;

  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '466: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The columns read and written.
  select string_agg(x.s || '.' || x.t || '.' || x.c, ', ') into v
    from (values ('auth', 'users', 'id', 'uuid'), ('auth', 'users', 'email', 'character varying(255)'),
                 ('auth', 'users', 'deleted_at', 'timestamp with time zone'),
                 ('public', 'affiliate_accounts', 'id', 'uuid'), ('public', 'affiliate_accounts', 'auth_user_id', 'uuid'),
                 ('public', 'affiliate_accounts', 'customer_id', 'uuid'),
                 ('public', 'affiliate_accounts', 'created_at', 'timestamp with time zone'),
                 ('public', 'customers', 'id', 'uuid'), ('public', 'customers', 'phone', 'text'),
                 ('public', 'customers', 'full_name', 'text'),
                 ('public', 'customers', 'email', 'text'), ('public', 'customers', 'deleted_at', 'timestamp with time zone'),
                 ('public', 'audit_logs', 'table_name', 'text'), ('public', 'audit_logs', 'record_id', 'uuid'),
                 ('public', 'audit_logs', 'action', 'text'), ('public', 'audit_logs', 'new_data', 'jsonb'),
                 ('public', 'audit_logs', 'module', 'text')) x(s, t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass(x.s || '.' || x.t) and a.attname = x.c
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '466: these columns are missing or not as read on 24 Oct 2026: %', v; end if;

  -- ── Change ──────────────────────────────────────────────────────────────
  if to_regprocedure('public.' || c_sig) is null then execute c_def;
  else raise notice '466: public.% is already this version; left alone', c_sig; end if;
  execute format('revoke all on function public.%s from public, anon, authenticated', c_sig);
  execute format('grant execute on function public.%s to service_role', c_sig);

  -- ── Afterwards ──────────────────────────────────────────────────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_md5 then
    raise exception '466: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if has_function_privilege('anon', to_regprocedure('public.' || c_sig), 'execute')
     or has_function_privilege('authenticated', to_regprocedure('public.' || c_sig), 'execute')
     or has_function_privilege('public', to_regprocedure('public.' || c_sig), 'execute')
     or not has_function_privilege('service_role', to_regprocedure('public.' || c_sig), 'execute') then
    raise exception '466: public.% is not the service role''s alone', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("466 Check", @example.invalid, fictional phones no
  -- customer or sign-up copy uses); it ends by raising P0466, which undoes
  -- all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select p as x from unnest(array['+61491570460', '+61491570461', '+61491570462', '+61491570463',
                                            '+61491570464', '+61491570465', '+61491570466', '+61491570467']) p
             where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = p)
               and not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) is null
                                  and c.phone ~ '^[\s().0-9-]+$'
                                  and (public.inspect_customer_phone(c.phone) -> 'candidates') ? p)
               and not exists (select 1 from public.affiliate_signup_identities i
                                where public.normalize_customer_phone(i.phone) = p)
             limit 3) y;
    if cardinality(t_phones) is distinct from 3 then
      raise exception '466: the self-test found no unused fictional phones'; end if;
    t_mail := 'z466-check-' || t_sfx || '@example.invalid';
    t_rec := 'z466-record-' || t_sfx || '@example.invalid';
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (gen_random_uuid(), t_mail, now(), '{"affiliate_email_unverified": true}'::jsonb, '{}'::jsonb)
    returning id into t_u;
    insert into public.customers (full_name, phone, email, is_active)
    values ('466 Check ' || t_sfx, t_phones[1], t_rec, true) returning id into t_cust;
    insert into public.customer_affiliates (customer_id, status, manually_suspended, activated_at, referral_code)
    values (t_cust, 'active', false, now(), upper('Z466' || t_sfx)) returning id into t_aff;
    insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status)
    values (t_u, t_cust, t_aff, 'claimed') returning id into t_acct;
    insert into public.affiliate_signup_identities (auth_user_id, affiliate_account_id, customer_id, first_name, last_name,
        full_name, phone, email, source, name_from, phone_from)
    values (t_u, t_acct, t_cust, '466', 'Check ' || t_sfx, '466 Check ' || t_sfx,
            '+61 ' || substr(t_phones[2], 4, 3) || ' ' || substr(t_phones[2], 7, 3) || ' ' || substr(t_phones[2], 10),
            t_mail, 'onboarding', 'arguments', 'arguments');
    -- A customer of her own on the affiliate's record phone, with no login
    -- (a family member on the household phone).
    insert into public.customers (full_name, phone, is_active)
    values ('466 Kin ' || t_sfx, t_phones[1], true);
    select count(*) into t_users from auth.users;
    select count(*) into t_custs from public.customers;

    -- Her record's phone, with another email and no name: the phone, and the
    -- hint; its Audit Log row carries the request id given.
    t_ans := public.affiliate_signup_existing(t_phones[1], 'someone-' || t_mail, null, t_req);
    if t_ans is distinct from jsonb_build_object('matched', 'phone', 'login_email', false,
                                                 'email_hint', 'z•••@example.invalid', 'affiliates', 1) then
      raise exception '466: the self-test''s record phone was not found as tested: %', t_ans; end if;
    -- The phone she signed up with (kept as typed, with spaces), typed in E.164.
    t_ans := public.affiliate_signup_existing(t_phones[2], 'someone-' || t_mail);
    if t_ans ->> 'matched' is distinct from 'phone' or t_ans ->> 'email_hint' is distinct from 'z•••@example.invalid' then
      raise exception '466: the self-test''s sign-up phone was not found as tested: %', t_ans; end if;
    -- Her login email, in capitals: the email itself, no hint.
    t_ans := public.affiliate_signup_existing(t_phones[3], upper(t_mail));
    if t_ans is distinct from jsonb_build_object('matched', 'email', 'login_email', true, 'email_hint', null, 'affiliates', 1) then
      raise exception '466: the self-test''s login email was not found as tested: %', t_ans; end if;
    -- Her record's email: an email, not her login's, with the hint.
    t_ans := public.affiliate_signup_existing(t_phones[3], t_rec);
    if t_ans is distinct from jsonb_build_object('matched', 'email', 'login_email', false,
                                                 'email_hint', 'z•••@example.invalid', 'affiliates', 1) then
      raise exception '466: the self-test''s record email was not found as tested: %', t_ans; end if;
    -- A phone and an email nobody has: nothing.
    t_ans := public.affiliate_signup_existing(t_phones[3], 'nobody-' || t_mail);
    if t_ans ->> 'matched' is not null then
      raise exception '466: the self-test''s stranger was matched: %', t_ans; end if;
    -- The family member on that phone, under her own record's name (in
    -- capitals): nothing (she signs up as today).
    t_ans := public.affiliate_signup_existing(t_phones[1], 'kin-' || t_mail, upper('466 Kin ' || t_sfx));
    if t_ans is distinct from jsonb_build_object('matched', null, 'login_email', false, 'email_hint', null, 'affiliates', 0) then
      raise exception '466: the self-test''s family member was not let through: %', t_ans; end if;
    -- The affiliate's own name on that phone: still the phone.
    t_ans := public.affiliate_signup_existing(t_phones[1], 'someone-' || t_mail, '466 Check ' || t_sfx);
    if t_ans is distinct from jsonb_build_object('matched', 'phone', 'login_email', false,
                                                 'email_hint', 'z•••@example.invalid', 'affiliates', 1) then
      raise exception '466: the self-test''s affiliate under her own name was let through: %', t_ans; end if;
    select count(*) into t_logs from public.audit_logs l
     where l.table_name = 'customers' and l.record_id = t_cust and l.action = 'affiliate_signup_sent_to_sign_in'
       and l.module = 'affiliate' and l.changed_by is null and l.new_data ->> 'version' = '466'
       and (l.new_data ->> 'affiliate_account_id')::uuid = t_acct;
    if t_logs <> 5 or (select count(*) from auth.users) <> t_users or (select count(*) from public.customers) <> t_custs then
      raise exception '466: the self-test wrote % Audit Log rows (expected 5), or made a login or a customer', t_logs; end if;
    if (select count(*) from public.audit_logs l
         where l.record_id = t_cust and l.action = 'affiliate_signup_sent_to_sign_in'
           and l.new_data ->> 'request_id' = t_req::text and (l.new_data ->> 'email_hint_shown')::boolean) <> 1 then
      raise exception '466: the self-test''s Audit Log row does not carry its request id and the hint shown'; end if;
    raise exception using errcode = 'P0466', message = '466: self-test done, undone';
  exception when sqlstate 'P0466' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
