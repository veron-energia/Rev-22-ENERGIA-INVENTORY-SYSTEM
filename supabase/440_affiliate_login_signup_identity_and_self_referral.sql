-- 440_affiliate_login_signup_identity_and_self_referral.sql
--
-- WHAT AN AFFILIATE LOGIN SIGNED UP WITH IS KEPT ON THE SERVER, WHERE SHE
-- CANNOT EDIT IT, AND THE NO-SELF-REFERRAL CHECKS READ IT: THE /r/<code>
-- REFERRAL PAGE (425) AND, WHEN 439 IS IN, THE SEMINAR WEBSITE (the Owner's
-- answers, 21 Oct 2026)
--
-- WHAT WAS WRONG
--
--   * 439 made the seminar website's no-self-referral check (436) compare the
--     affiliate LOGIN's own details too: its email now (auth.users.email) and
--     the name and phone in its raw_user_meta_data. A signed-in user changes
--     her own raw_user_meta_data whenever she likes (supabase.auth.updateUser
--     with { data }), so those recognised her only while she left them as
--     she signed up (439's NOT COVERED asked whether the server should keep
--     its own copy).
--   * 425's /r/<code> referral page compared only the referrer's customer
--     record (its phone with its name, or the same words). 437's rule 7 joins
--     a login to a family member's record on the phone alone, and staff may
--     change a record's name, phone or email afterwards; so an affiliate
--     whose login details are not her record's could refer herself there
--     (her own name on her own mobile, say) and earn on herself (439's
--     NOT COVERED: "425's /r/<code> page still compares only the record").
--
-- THE OWNER'S ANSWERS (21 Oct 2026)
--
--   (A) "Keep an uneditable copy of sign-up details": the server keeps its
--       own copy of what each affiliate login typed at sign-up (first and
--       last name, phone, email), which the affiliate cannot edit (her
--       raw_user_meta_data must not be the source). Written when the
--       affiliate account is made or joined (complete_affiliate_onboarding:
--       the name and phone typed on the Join/Verify page; the email from
--       auth.users at that moment), and every existing affiliate login is
--       backfilled once, from raw_user_meta_data and auth.users.email as
--       they are today, marked as a backfill. No client grant can change it;
--       only server-side code writes it. One service-role helper gives, for a
--       referrer's customer record, the sign-up details of its live
--       affiliate login(s).
--   (B) "Referral page checks the login too": affiliate_referral_signup
--       treats a sign-up as the affiliate referring herself also when it
--       matches what the referrer's login signed up with: a name of the same
--       words (customer_names_match), or its phone (normalize_customer_phone),
--       or its email inbox (customer_email_match_key); not only the
--       referrer's record. What a self match answers today stays exactly as
--       it is; only what counts as self is wider.
--   (C) With 439 in, its two login checks (event_web_affiliate_contact,
--       event_web_check_self_referral) read the copy instead of
--       raw_user_meta_data and the login's email now. Without 439 this part
--       is skipped, with a notice: 439 must go FIRST (439 after 440 still
--       installs, but reads raw_user_meta_data until 440 is run again).
--
-- HOW THEY READ (this file, 21 Oct 2026)
--
--   * One copy per sign-up of a login: a row each time
--     complete_affiliate_onboarding makes or joins an affiliate account for
--     it (once; a second press answers "already" and writes nothing). A
--     login an Owner unlinked (378) gets a second row at its next sign-in,
--     when it is made an account again; the first stays (both are what she
--     typed). Rows are never changed; a login deleted in Supabase (Auth,
--     Users) takes its rows with it.
--   * "What she typed": the name and phone the sign-up used, as 437 takes
--     them: the page's (p_first_name, p_last_name, p_phone), else what the
--     sign-up function stored on the account (437: arguments first). The
--     copy says which (name_from, phone_from: 'arguments' or
--     'user_metadata'). The email is auth.users.email at that moment,
--     trimmed and in lower case (as 437 reads it). The phone is kept as
--     typed; it is compared through normalize_customer_phone.
--   * The backfill: every login with an affiliate account (70 on 20 Oct
--     2026, as 437 counted them), and every login with a pending claim and
--     no account yet (claims from before 437, which staff can still resolve
--     with resolve_affiliate_account_claim, unchanged: that login then
--     already has its copy), from raw_user_meta_data's first_name and
--     last_name (else full_name) and phone, and auth.users.email, as they
--     are when this runs; source 'backfill'. A value the login does not
--     have is left empty, and the login is then recognised by the rest.
--     The run that makes the table copies all of them. Every later run
--     copies again, the same way, only a login that has an affiliate account
--     and no copy yet (a sign-up still running 437's text while this file
--     went in, a pending claim staff resolved since, an account made by
--     hand), from its metadata and email as they are then. A login that
--     signed up and has neither (the unconfirmed sign-ups of 20 Oct, say)
--     gets its copy when it finishes signing up.
--   * Her "live" login(s): those on the referrer's record now
--     (affiliate_accounts.customer_id; one per record), with every copy of
--     each. A login an Owner unlinked is not on it any more, so not hers;
--     the login's own state (banned, signed out) does not matter: it still
--     says who she is.
--   * /r/<code>: the sign-up's name has the same words as a copy's name, or
--     its phone is a copy's phone, or its email is a copy's inbox: she is
--     herself. Exactly what a self match on her record answers today: ok
--     false, "You cannot refer yourself.", nothing written (no customer, no
--     referral_signup_events row). Checked where the record check is: after
--     the link is found valid and the phone and name are resolved (an
--     AMBIGUOUS_CUSTOMER_MATCH still comes first), before "already
--     registered" (as for her record).
--   * The seminar website: the copy's name is her login's name (439's B);
--     its phone and email inbox are her login's (439's A: someone else on
--     them waits for a check); nothing else in 439 changes. Her login email
--     now no longer counts (the copy's does).
--
-- WHAT THIS DOES
--
--   1. Table public.affiliate_signup_identities (new): auth_user_id (the
--      login; deleted with it), affiliate_account_id and customer_id (the
--      account made or joined and its record then; no foreign key, so a
--      merge or an unlink leaves the row as written), first_name, last_name,
--      full_name, phone, email, source ('onboarding' or 'backfill'),
--      name_from and phone_from, created_at. Row level security on, no
--      policy; anon and authenticated hold nothing on it; the service role
--      may only read it. A trigger refuses every UPDATE, whoever runs it
--      (SIGNUP_DETAILS_KEPT, 42501): only the owner's server code inserts.
--   2. trg_affiliate_signup_identity_kept() (new): that trigger.
--   3. affiliate_login_signup_details(customer) (new, the service role's
--      alone): the copies of the logins now on that record (auth_user_id,
--      first_name, last_name, full_name, phone, email, source, recorded_at),
--      oldest first.
--   4. complete_affiliate_onboarding (437's), patched at one anchor: right
--      after it makes the affiliate account, it writes the copy (source
--      'onboarding'): for a new customer, a phone join and a fresh record
--      alike. Nothing else in it changes (the answer, the audit row, the
--      rules).
--   5. affiliate_referral_signup (425's /r/<code>), patched at one anchor:
--      its self check is "her record (as before) or her login's copy (B)".
--   6. With 439 in: event_web_affiliate_contact and
--      event_web_check_self_referral (439's), each patched at one anchor:
--      the login's part reads affiliate_login_signup_details (the copy's
--      phone and email; the copy's name) instead of raw_user_meta_data and
--      auth.users.email. Their callers follow unchanged.
--   7. The backfill (above): every affiliate login, and each pending claim
--      with no account, in the first run; in any later run, only a login
--      with an account and no copy.
--
-- NOT CHANGED
--
--   * The ten functions 436 pins (customer_names_match, customer_name_words,
--     customer_email_match_key, customer_phone_name_matches,
--     require_resolved_customer_identity, normalize_customer_phone,
--     normalize_customer_match_name, create_customer_quick,
--     public_affiliate_referral_info, merge_customer_records); 438's two
--     (cancelled_invoice_used_value, invoice_action_plan); update_customer;
--     the commission engine; everything 430 pins; 437's other functions
--     (the list, Link, the claims) and its table; resolve_affiliate_account_
--     claim and unlink_affiliate_account; event_web_referral_note and
--     every other 436/439 function.
--   * Who may call what: complete_affiliate_onboarding (signed-in logins and
--     the service role) and affiliate_referral_signup (the anon key too: the
--     page and the old seminar site) keep their grants; the 439 pair stay the
--     service role's.
--   * Supabase Auth, the Edge Functions and the pages (no deploy but this).
--
-- NOT COVERED (told to the Owner)
--
--   * (B) taken as answered: the login's phone ALONE, or its email inbox
--     ALONE, makes a /r/<code> sign-up "herself". A family member who signs
--     up through her link on the phone her login signed up with (a household
--     phone; usually her record's too) is now told "You cannot refer
--     yourself." and nothing is made (before: made a customer, referred,
--     and, when a record has the phone, listed for an Owner or Manager to
--     check, 425's Q19). Staff add such a person on the Customers page and
--     set the referrer by hand (reassign_customer_referrer). The seminar
--     website (436/439) still treats the login's phone or inbox alone as
--     "someone else, waiting for a check", not as herself. The phone and
--     inbox of her RECORD alone keep 425's rule (a check), as before. The
--     old seminar site (rev22-energia-seminar, which calls this function)
--     lists such a guest as "Not added: this is the affiliate themselves".
--     Owner's decision, open: whether /r/ should follow the seminar rule
--     for the login's phone and inbox.
--   * (B) also makes the /r/ form answer "You cannot refer yourself." to
--     anyone who has an affiliate's code and types the phone, or the email,
--     her login signed up with: it tells them that number or address is
--     hers. A refused sign-up writes no event (as for her record), so the
--     per-phone limit does not count such tries. Before 440 the same was
--     true only of her record's phone together with its name.
--   * A copy is only as true as what was typed: a sign-up under a name that
--     is not hers is kept as typed; a name typed differently later (an
--     honorific, a typo, a nickname) is not the same words.
--   * The backfill copies the metadata as it is on the day this runs: a
--     login that changed it before then is copied as changed. A login with
--     no name or phone in its metadata is copied without (the email still
--     counts).
--   * event_web_referral_note (439) still names the login, in its wording
--     only ("or Rachel Testmum, whose affiliate login is on her record"),
--     from raw_user_meta_data: it decides nothing, but after an edit the
--     wording can name the edited name. (A small follow-up for the 439
--     session, through the helper; not in this file.)
--   * Without 439 (or with 439 run after this file) the seminar website
--     reads the login's metadata, as 439 has it; running this file again
--     after 439 patches its two functions (step 6).
--   * A sign-up already running when this file goes in runs 437's text to
--     its end: nothing here waits for it (it holds no lock this file takes).
--     If it commits after the backfill, this file still commits, and that
--     login has an affiliate account with no copy, so it is not compared at
--     all (on /r/, nor with 439 on the seminar website), until this file is
--     run again (DEPLOY ORDER, step 3). That run copies it from its metadata
--     and email as they are then ('backfill'), not from what the Join page
--     sent. The chance is small (a sign-up overlapping an apply of well under
--     a second), but nothing fails when it happens.
--   * The same for a login given an affiliate account other than through
--     complete_affiliate_onboarding after this file: a pending claim from
--     before 437 resolved by staff (its login already has the first run's
--     copy, so nothing is missing), or an account made by hand in SQL (no
--     copy, and not compared, until this file is run again).
--   * After step 6, 439 cannot be run again (its guards accept only 436's or
--     its own AFTER of the two); nor 437 or 425 (theirs, of the function they
--     changed). 439's own suite (event-website-439.sql) checks its AFTER
--     md5s (G3) and builds its logins straight into auth.users with
--     metadata and no sign-up (L1-L4, L7), so those checks fail once step 6
--     is in, by design: such a login has no copy (9 checks on 21 Oct 2026:
--     G3, L1 three, L2 two, L3, L4, L7; its L9, through the sign-up, passes).
--     440's suite runs those cases through the sign-up.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * each new function is missing or this version; no other function takes
--     the name of a new or a changed one;
--   * complete_affiliate_onboarding and affiliate_referral_signup are their
--     BEFORE (patched: the anchor found exactly once, the text built has the
--     tested AFTER md5) or already the AFTER (left alone); anything else is
--     refused, with the installed md5 and the patched one when the anchor is
--     found once (to re-pin);
--   * the 439 pair: both missing (no 436) or both 436's AFTER (no 439):
--     skipped, with a notice; each 439's AFTER (patched as above) or this
--     file's AFTER (left alone), with 439's event_web_kept_customer at its
--     AFTER; any other mix is refused;
--   * the functions relied on and not changed are as read on production on
--     21 Oct 2026 (below);
--   * the table is missing, or exactly this shape (columns, constraints,
--     index, trigger); the columns read on auth.users, affiliate_accounts
--     and affiliate_account_claims are as read.
--   Afterwards: every md5 is the AFTER one; the changed functions keep their
--   grants (ACLs compared); the two new ones are the service role's alone;
--   the table is closed to anon and authenticated, read-only for the
--   service role, row level security on with no policy, its UPDATE trigger
--   enabled; after the backfill (every run), every login with an affiliate
--   account has a copy (a sign-up that finishes in between makes the run
--   fail, changing nothing: run it again); the 439 pair, when patched, read
--   no raw_user_meta_data. Then a self-test, in a block that is always undone (it ends by
--   raising P0440, so it leaves no row): a made-up login (@example.invalid)
--   signs up on an unused fictional phone (a new customer): one copy, as
--   typed, with its email; it edits its metadata (updateUser) and the copy
--   stays; an UPDATE of the copy is refused; through its own link, its
--   login email on another phone and another name, and its login's name on
--   another phone, are each "You cannot refer yourself."; the name and
--   phone it edited into its metadata are someone else: registered. A
--   second run changes nothing (it copies only a login that has an account
--   and no copy, as above).
--   Locks: the run that makes the table takes SHARE ROW EXCLUSIVE on
--   auth.users (the table's foreign key to it). If a transaction is writing
--   auth.users at that moment (a sign-in or a sign-up), this waits up to 5s
--   and then fails on the lock timeout, changing nothing (run it again);
--   while it waits, Supabase Auth's writes queue behind it. Every run takes
--   ACCESS EXCLUSIVE on affiliate_signup_identities (row level security is
--   set again), so a sign-up writing its copy at that moment waits for this
--   run to end.
--
-- DEPLOY ORDER (each with the Owner's go-ahead)
--
--   After 437 (it patches 437's complete_affiliate_onboarding; before 437
--   it refuses as a whole) and 425; independent of 438 (neither touches the
--   other's functions). 439 FIRST when it goes live the same day:
--     production now (436, 437, 438)  -> 439 -> 440   (all of A, B, C)
--   440 before 439 also goes in (A and B, with a notice that C was skipped);
--   439 then installs too (it pins none of 440's functions) but reads
--   raw_user_meta_data; run 440 again after it, which then patches only the
--   439 pair (C) and ends at the fingerprint of 439 -> 440.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second says "already
--      this version; left alone" for each function and changes nothing.
--   2. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   3. A minute later, count the affiliate logins with no copy (expect 0):
--        select count(*) from public.affiliate_accounts a
--         where not exists (select 1 from public.affiliate_signup_identities i
--                            where i.auth_user_id = a.auth_user_id);
--      If it is not 0 (a sign-up was still running 437's text while 2 went
--      in: NOT COVERED), run this file once more: it copies those logins
--      ('backfill', from their metadata and email as they are then) and
--      changes nothing else.
--   No page, Edge Function or setting changes.
--
-- BEFORE (production, 21 Oct 2026: 436, 437 and 438 in; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   complete_affiliate_onboarding(text,text,text,boolean)          88ee10799d1c93ce93d0056740f05e01  (437's AFTER)
--   affiliate_referral_signup(text,text,text,text,text,text)       35def9a1a663d6180d15ab8ea049de35  (425's AFTER)
--   event_web_affiliate_contact(uuid)                              e4adbd007d847daee24e8d5d28b96b75  (439's AFTER; 436's
--                                                                    2e36126ac19182665357e2a934252db6: skipped)
--   event_web_check_self_referral(uuid,uuid)                       11475114504d5bab79981ed8bb8c12b0  (439's AFTER; 436's
--                                                                    7c13dd04c230ddedf201db59244bdaff: skipped)
--   relied on, not changed
--   customer_names_match(text,text)                                ef1af52e4888cefb6037a2291f4e011d
--   customer_name_words(text)                                      a7507abf0f15abd923dff59508b269c1
--   customer_email_match_key(text)                                 be468815c9626fff1728e2cfcd484b66
--   normalize_customer_phone(text)                                 b2bfac910e0c9eff402ba44e19750bee
--   normalize_customer_match_name(text)                            0572764712e179dc606c66f9f3dbaa03
--   customer_phone_name_matches(text,text)                         1bdf8322972b6671b7cbb08bc8211f8a
--   require_resolved_customer_identity(text,text)                  5bde1a418363442ec27e2944442f5874
--   inspect_customer_phone(text,text)                              6672c4d1963996f3b601896f4a55916e
--   event_web_kept_customer(uuid)                                  cb0720c1088df9209da45e46b91601f4  (439's; only with 439)
--   public function fingerprint, production now                    f9464b8e06c2769987a3050cd7278900 (1363 functions)
--   ... with 439                                                   41618db239b4b192c90631ea847a412d (1364)
-- AFTER (for later guards)
--   affiliate_login_signup_details(uuid)                           71e6d6f9ab2b474450b5c00f60f14bb4  (new)
--   trg_affiliate_signup_identity_kept()                           b8c77a682d1a99783bfa708471c9f27e  (new)
--   complete_affiliate_onboarding(text,text,text,boolean)          43084deab54968eacaf1793c470fd08f
--   affiliate_referral_signup(text,text,text,text,text,text)       a3deac154f5144cffb34fab871f076c6
--   event_web_affiliate_contact(uuid)                              3c81727e93dc5b73ca1d8833d95f75bb  (with 439)
--   event_web_check_self_referral(uuid,uuid)                       2a5ab36c3d878197c21221a9a1ff193f  (with 439)
--   public function fingerprint, worked out on copies of production (21 Oct 2026):
--     production now -> 440                                        0a3b04c7ea60d6642f68b8b19fa18758 (1365)
--     production now -> 439 -> 440                                 bbbfcbb99f38cb278a58e2496abe0a4f (1366)
--     production now -> 440 -> 439                                 a0e8ab806f950f5527b11e9265b5d663 (1366)
--     production now -> 440 -> 439 -> 440                          bbbfcbb99f38cb278a58e2496abe0a4f (1366) (the same as 439 -> 440)
--
-- Test: scripts/affiliate-signup/tests/login-identity-440.sql (begin ...
-- rollback; it installs this file, then runs it three more times: its
-- backfill part, and the later run that copies an account left with none,
-- need that; run with -v nomig=1 where it is in; its seminar part runs
-- where 439 is in, and fails, as it should, on 440 -> 439 until this file
-- is run again).
-- Checked on copies of production (21 Oct 2026), with and without 439:
-- 437's straight-in-437.sql (-v nomig=1), 436's event-website.sql
-- (-v skip_install=1), 438's reopen-recancel-438.sql
-- (-v mig=supabase/438_reopened_and_moved_benefits_count_as_unused.sql),
-- scripts/permissions/tests/function-grants.sql and
-- staff-only-functions.sql (both list 440's), and 392's booking-label.sql,
-- 432's no-duplicate-customers.sql, 378's staff-claims.sql and 379's
-- reject-protects.sql pass with it (the last four once their pins accept
-- 440's AFTER md5s: booking-label.sql that of affiliate_referral_signup,
-- and scripts/affiliate-claims/tests/sign-up-before-437.sql, which the
-- other three include, that of complete_affiliate_onboarding, for which it
-- puts 432's text back as it does for 437's); 439's event-website-439.sql
-- (-v skip_install=1) passes on production now -> 440 -> 439, and after
-- step 6 fails G3 and its metadata-only login cases, by design (NOT
-- COVERED). 425's shared-phone-425.sql (also in npm run
-- test:affiliate-signup) installs 425 on every run, and 425 already refuses
-- on production now, with or without 440 (its pin of is_owner_or_manager);
-- run with -v mig=/dev/null (no install), its 35 checks pass with 440 as
-- without.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The new functions, as pg_get_functiondef gives them back ─────────────
  c_new_sig constant text[] := array['affiliate_login_signup_details(uuid)', 'trg_affiliate_signup_identity_kept()'];
  c_new_md5 constant text[] := array['71e6d6f9ab2b474450b5c00f60f14bb4', 'b8c77a682d1a99783bfa708471c9f27e'];
  c_new_def constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.affiliate_login_signup_details(p_customer_id uuid)
 RETURNS TABLE(auth_user_id uuid, first_name text, last_name text, full_name text, phone text, email text, source text, recorded_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 440 (the Owner, 21 Oct 2026, A): what each affiliate login now on this
  -- customer record signed up with, as the server copied it
  -- (affiliate_signup_identities: written by complete_affiliate_onboarding
  -- when the account was made or joined, or by 440's one backfill from the
  -- login as it was on the day 440 went in). Never her user metadata, which
  -- she can change herself (updateUser), nor her login email now. A login an
  -- Owner unlinked is no longer on the record, so not hers; one that signed
  -- up more than once (an unlink, then the next sign-in) gives each copy.
  -- For the self-referral checks (affiliate_referral_signup, and 439's
  -- event_web_affiliate_contact and event_web_check_self_referral); the
  -- service role's alone.
  select i.auth_user_id, i.first_name, i.last_name, i.full_name, i.phone, i.email, i.source, i.created_at
    from public.affiliate_accounts aa
    join public.affiliate_signup_identities i on i.auth_user_id = aa.auth_user_id
   where aa.customer_id = p_customer_id
   order by i.created_at, i.id
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.trg_affiliate_signup_identity_kept()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  -- 440 (the Owner, 21 Oct 2026, A): what an affiliate login signed up with
  -- is kept as it was written. No one changes it, server code included (a
  -- login deleted in Supabase takes its rows with it).
  raise exception 'SIGNUP_DETAILS_KEPT: what an affiliate login signed up with is kept as it was written and cannot be changed'
    using errcode = '42501';
end $function$
$def$];

  -- ── The functions patched, each at one anchor ────────────────────────────
  -- signature, BEFORE md5, AFTER md5, whether it is 439's (skipped without
  -- 439), the anchor and what replaces it.
  c_sig constant text[] := array[
    'complete_affiliate_onboarding(text,text,text,boolean)',
    'affiliate_referral_signup(text,text,text,text,text,text)',
    'event_web_affiliate_contact(uuid)',
    'event_web_check_self_referral(uuid,uuid)'];
  c_before constant text[] := array[
    '88ee10799d1c93ce93d0056740f05e01', '35def9a1a663d6180d15ab8ea049de35',
    'e4adbd007d847daee24e8d5d28b96b75', '11475114504d5bab79981ed8bb8c12b0'];
  c_after constant text[] := array['43084deab54968eacaf1793c470fd08f', 'a3deac154f5144cffb34fab871f076c6', '3c81727e93dc5b73ca1d8833d95f75bb', '2a5ab36c3d878197c21221a9a1ff193f'];
  -- 436's AFTER of the 439 pair: 439 is not in (skipped).
  c_at436 constant text[] := array[null, null, '2e36126ac19182665357e2a934252db6', '7c13dd04c230ddedf201db59244bdaff'];
  c_is439 constant boolean[] := array[false, false, true, true];
  c_anchor constant text[] := array[
-- complete_affiliate_onboarding: the account is made
$a1$  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status, last_login_at, email_verified_at)
    values (v_uid, v_cust, v_aff.id, 'claimed', now(), v_verified)
    returning * into v_acct;
$a1$,
-- affiliate_referral_signup: the self check
$a2$  if v_ref_cust = any (v_matches) then
    return jsonb_build_object('ok',false,'message','You cannot refer yourself.');
  end if;
$a2$,
-- event_web_affiliate_contact: her login's phone and email
$a3$              select u.raw_user_meta_data->>'phone', u.email
                from public.affiliate_accounts aa join auth.users u on u.id = aa.auth_user_id
               where aa.customer_id in (select mine.id from mine)) x) h
$a3$,
-- event_web_check_self_referral: her login's name
$a4$              select 'login', coalesce(nullif(btrim(coalesce(u.raw_user_meta_data->>'first_name', '') || ' '
                                                   || coalesce(u.raw_user_meta_data->>'last_name', '')), ''),
                                       nullif(btrim(coalesce(u.raw_user_meta_data->>'full_name', '')), '')), 2
                from public.affiliate_accounts aa join auth.users u on u.id = aa.auth_user_id
               where aa.customer_id in (select mine.id from mine)) x
$a4$];
  c_patch constant text[] := array[
$r1$  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status, last_login_at, email_verified_at)
    values (v_uid, v_cust, v_aff.id, 'claimed', now(), v_verified)
    returning * into v_acct;

  -- 440 (the Owner, 21 Oct 2026, A): the server's own copy of what this login
  -- signed up with, which she cannot edit (her raw_user_meta_data she can,
  -- with updateUser): the name and phone this sign-up used (the page's,
  -- else the account's, as above) and the login's email now. Written once,
  -- with the account, for a new customer, a phone join and a fresh record
  -- alike; nothing changes it (affiliate_signup_identities). The
  -- no-self-referral checks read it (affiliate_login_signup_details).
  insert into public.affiliate_signup_identities (auth_user_id, affiliate_account_id, customer_id, first_name, last_name,
      full_name, phone, email, source, name_from, phone_from)
    values (v_uid, v_acct.id, v_cust, v_first, v_last, v_name, v_raw_phone, v_email, 'onboarding',
      case when nullif(btrim(coalesce(p_first_name, '')), '') is null and nullif(btrim(coalesce(p_last_name, '')), '') is null
           then 'user_metadata' else 'arguments' end,
      case when nullif(btrim(coalesce(p_phone, '')), '') is null then 'user_metadata' else 'arguments' end);
$r1$,
$r2$  -- 440 (the Owner, 21 Oct 2026, B): she is herself also when the sign-up
  -- matches what the referrer's affiliate login signed up with (the server's
  -- own copy, which she cannot edit; affiliate_login_signup_details): a name
  -- of the same words (customer_names_match), its phone
  -- (normalize_customer_phone) or its email inbox (customer_email_match_key).
  -- The answer is the one her record gives, as before.
  if v_ref_cust = any (v_matches)
     or exists (select 1 from public.affiliate_login_signup_details(v_ref_cust) d
                 where public.customer_names_match(d.full_name, v_name)
                    or public.normalize_customer_phone(d.phone) = v_norm
                    or public.customer_email_match_key(d.email) = public.customer_email_match_key(v_email)) then
    return jsonb_build_object('ok',false,'message','You cannot refer yourself.');
  end if;
$r2$,
$r3$              -- 440 (the Owner, 21 Oct 2026, A and C): her login's phone and email as
              -- it signed up with them (the server's own copy, which she cannot edit),
              -- not its user metadata or its email now
              select d.phone, d.email
                from mine cross join lateral public.affiliate_login_signup_details(mine.id) d) x) h
$r3$,
$r4$              -- 440 (the Owner, 21 Oct 2026, A and C): the name her login signed up
              -- with (the server's own copy, which she cannot edit), not its user metadata
              select 'login', d.full_name, 2
                from mine cross join lateral public.affiliate_login_signup_details(mine.id) d) x
$r4$];

  -- ── Relied on, not changed (production, 21 Oct 2026) ─────────────────────
  c_relied constant text[] := array[
    'customer_names_match(text,text)', 'customer_name_words(text)', 'customer_email_match_key(text)',
    'normalize_customer_phone(text)', 'normalize_customer_match_name(text)', 'customer_phone_name_matches(text,text)',
    'require_resolved_customer_identity(text,text)', 'inspect_customer_phone(text,text)'];
  c_relied_md5 constant text[] := array[
    'ef1af52e4888cefb6037a2291f4e011d', 'a7507abf0f15abd923dff59508b269c1', 'be468815c9626fff1728e2cfcd484b66',
    'b2bfac910e0c9eff402ba44e19750bee', '0572764712e179dc606c66f9f3dbaa03', '1bdf8322972b6671b7cbb08bc8211f8a',
    '5bde1a418363442ec27e2944442f5874', '6672c4d1963996f3b601896f4a55916e'];
  c_kept_sig constant text := 'event_web_kept_customer(uuid)';
  c_kept_md5 constant text := 'cb0720c1088df9209da45e46b91601f4';

  -- ── The table, as information_schema and the catalogue give it ───────────
  c_table_shape constant text :=
    'id uuid NO gen_random_uuid()|auth_user_id uuid NO |affiliate_account_id uuid YES |customer_id uuid YES '
    || '|first_name text YES |last_name text YES |full_name text YES |phone text YES |email text YES '
    || '|source text NO |name_from text YES |phone_from text YES |created_at timestamp with time zone NO now()';
  c_constraints constant text[] := array['affiliate_signup_identities_pkey', 'affiliate_signup_identities_auth_user_id_fkey',
    'affiliate_signup_identities_source_check', 'affiliate_signup_identities_from_check',
    'affiliate_signup_identities_onboarding_check'];
  c_trigger_def constant text :=
    'CREATE TRIGGER affiliate_signup_identities_kept BEFORE UPDATE ON public.affiliate_signup_identities '
    || 'FOR EACH ROW EXECUTE FUNCTION trg_affiliate_signup_identity_kept()';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v_names text[]; v text; d text; d2 text; i int; n int;
  v_do boolean[] := array[false, false, false, false];   -- patched in this run
  v_defs text[] := array[null, null, null, null]::text[];
  v_acls text[] := array[null, null, null, null]::text[];
  v_c text;                     -- the 439 pair: 'no_436', 'no_439', 'patch' or 'done'
  v_created boolean := false; v_backfilled int := 0; v_backfilled_claims int := 0;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_u1 uuid; t_cust uuid; t_code text; t_mail text; t_ans jsonb; t_row jsonb;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The new functions' texts are the tested ones; each is missing or this.
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(c_new_def[i]) <> c_new_md5[i] then
      raise exception '440: the text of public.% is not the tested one (md5 %)', c_new_sig[i], md5(c_new_def[i]); end if;
    if to_regprocedure('public.' || c_new_sig[i]) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '440: public.% exists and is not this migration''s (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
  end loop;

  -- No other function takes one of these names.
  v_names := array(select split_part(s, '(', 1) from unnest(c_new_sig || c_sig) s);
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any (v_names)
     and p.oid::regprocedure::text <> all (c_new_sig || c_sig);
  if v is not null then raise exception '440: another function takes one of these names: %', v; end if;

  -- The 439 pair: which state it is in.
  if to_regprocedure('public.' || c_sig[3]) is null and to_regprocedure('public.' || c_sig[4]) is null then
    v_c := 'no_436';
  elsif to_regprocedure('public.' || c_sig[3]) is not null and to_regprocedure('public.' || c_sig[4]) is not null
        and md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[3]))) = c_at436[3]
        and md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[4]))) = c_at436[4] then
    v_c := 'no_439';
  elsif to_regprocedure('public.' || c_sig[3]) is not null and to_regprocedure('public.' || c_sig[4]) is not null
        and md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[3]))) in (c_before[3], c_after[3])
        and md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[4]))) in (c_before[4], c_after[4]) then
    v_c := case when md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[3]))) = c_after[3]
                 and md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[4]))) = c_after[4] then 'done' else 'patch' end;
    if to_regprocedure('public.' || c_kept_sig) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_kept_sig))) <> c_kept_md5 then
      raise exception '440: 439''s public.% is missing or not the version this was tested against', c_kept_sig; end if;
  else
    raise exception '440: public.% (md5 %) and public.% (md5 %) are neither 436''s, nor 439''s, nor this file''s versions. Re-read them and re-test before applying.',
      c_sig[3], coalesce(md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[3]))), 'missing'),
      c_sig[4], coalesce(md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[4]))), 'missing');
  end if;

  -- Each function to patch: its BEFORE (patched here) or its AFTER (left).
  for i in 1 .. cardinality(c_sig) loop
    if c_is439[i] and v_c in ('no_436', 'no_439') then continue; end if;
    if to_regprocedure('public.' || c_sig[i]) is null then
      raise exception '440: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then continue; end if;
    n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
    if n <> 1 then
      raise exception '440: public.% is not the version this was tested against (md5 %), and its anchor is found % times, not once. Re-read it and re-test before applying.', c_sig[i], md5(d), n; end if;
    d2 := replace(d, c_anchor[i], c_patch[i]);
    if md5(d) <> c_before[i] then
      raise exception '440: public.% is not the version this was tested against (md5 %; patched it would be md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d), md5(d2); end if;
    if md5(d2) <> c_after[i] then
      raise exception '440: the text built for public.% is not the tested one (md5 %)', c_sig[i], md5(d2); end if;
    v_do[i] := true; v_defs[i] := d2;
  end loop;

  -- The functions relied on are as read.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '440: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '440: auth.uid() must be there'; end if;
  -- The columns read.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('auth', 'users', 'id', 'uuid'), ('auth', 'users', 'email', 'character varying(255)'),
                 ('auth', 'users', 'raw_user_meta_data', 'jsonb'),
                 ('public', 'affiliate_accounts', 'id', 'uuid'), ('public', 'affiliate_accounts', 'auth_user_id', 'uuid'),
                 ('public', 'affiliate_accounts', 'customer_id', 'uuid'),
                 ('public', 'affiliate_account_claims', 'auth_user_id', 'uuid'),
                 ('public', 'affiliate_account_claims', 'status', 'text')) x(s, t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass(x.s || '.' || x.t) and a.attname = x.c
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '440: these columns are missing or not as read on 21 Oct 2026: %', v; end if;

  -- affiliate_signup_identities: missing, or exactly this shape.
  if to_regclass('public.affiliate_signup_identities') is not null then
    select string_agg(c.column_name || ' ' || c.data_type || ' ' || c.is_nullable || ' ' || coalesce(c.column_default, ''), '|'
                      order by c.ordinal_position) into v
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'affiliate_signup_identities';
    if v is distinct from c_table_shape then
      raise exception '440: public.affiliate_signup_identities exists and is not this migration''s table (%)', v; end if;
    if (select count(*) from pg_constraint where conrelid = 'public.affiliate_signup_identities'::regclass
          and conname = any (c_constraints)) <> cardinality(c_constraints)
       or (select count(*) from pg_constraint where conrelid = 'public.affiliate_signup_identities'::regclass) <> cardinality(c_constraints)
       or to_regclass('public.affiliate_signup_identities_login') is null then
      raise exception '440: public.affiliate_signup_identities is missing one of its constraints or its index, or has another'; end if;
    if (select string_agg(pg_get_triggerdef(t.oid), ' | ') from pg_trigger t
         where t.tgrelid = 'public.affiliate_signup_identities'::regclass and not t.tgisinternal) is distinct from c_trigger_def then
      raise exception '440: public.affiliate_signup_identities does not have exactly its UPDATE trigger'; end if;
  end if;

  -- What may call each function patched here now (kept as it is).
  for i in 1 .. cardinality(c_sig) loop
    v_acls[i] := (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig[i]));
  end loop;

  -- ── Changes ─────────────────────────────────────────────────────────────
  -- 2. The trigger function first (the table's trigger names it).
  if to_regprocedure('public.' || c_new_sig[2]) is null then execute c_new_def[2];
  else raise notice '440: public.% is already this version; left alone', c_new_sig[2]; end if;
  -- 1. The table.
  if to_regclass('public.affiliate_signup_identities') is null then
    create table public.affiliate_signup_identities (
      id uuid primary key default gen_random_uuid(),
      auth_user_id uuid not null references auth.users(id) on delete cascade,
      -- No foreign keys to the account or the customer: an unlink deletes the
      -- account, and merge_customer_records moves every column that has one;
      -- the row keeps what was signed up with, as written.
      affiliate_account_id uuid,
      customer_id uuid,
      first_name text,
      last_name text,
      full_name text,
      phone text,
      email text,
      source text not null,
      name_from text,
      phone_from text,
      created_at timestamptz not null default now(),
      constraint affiliate_signup_identities_source_check check (source in ('onboarding', 'backfill')),
      constraint affiliate_signup_identities_from_check check (
        (name_from is null or name_from in ('arguments', 'user_metadata'))
        and (phone_from is null or phone_from in ('arguments', 'user_metadata'))),
      constraint affiliate_signup_identities_onboarding_check check (source <> 'onboarding' or (
        affiliate_account_id is not null and customer_id is not null and full_name is not null and phone is not null
        and email is not null and name_from is not null and phone_from is not null))
    );
    create index affiliate_signup_identities_login on public.affiliate_signup_identities (auth_user_id);
    create trigger affiliate_signup_identities_kept before update on public.affiliate_signup_identities
      for each row execute function public.trg_affiliate_signup_identity_kept();
    comment on table public.affiliate_signup_identities is
      '440: what each affiliate login signed up with (name, phone, email), copied by the server when its affiliate account '
      'was made or joined (complete_affiliate_onboarding), or by 440''s one backfill; never changed (an UPDATE is refused). '
      'Its own user metadata the login can edit; this it cannot (the Owner, 21 Oct 2026). Read through '
      'affiliate_login_signup_details by the no-self-referral checks. No client role holds it.';
    v_created := true;
  end if;
  alter table public.affiliate_signup_identities enable row level security;
  revoke all on table public.affiliate_signup_identities from public, anon, authenticated, service_role;
  grant select on table public.affiliate_signup_identities to service_role;

  -- 3. The helper (it reads the table, so after it).
  if to_regprocedure('public.' || c_new_sig[1]) is null then execute c_new_def[1];
  else raise notice '440: public.% is already this version; left alone', c_new_sig[1]; end if;
  for i in 1 .. cardinality(c_new_sig) loop
    execute format('revoke all on function public.%s from public, anon, authenticated', c_new_sig[i]);
    execute format('grant execute on function public.%s to service_role', c_new_sig[i]);
  end loop;

  -- 7. The backfill, from the login's metadata and email as they are now
  -- (source 'backfill'). Every run: each login with an affiliate account and
  -- no copy yet (in the run that made the table, all of them; in a later
  -- one, a sign-up that was still running 437's text while this file went
  -- in, a pending claim staff resolved since, or an account made by hand).
  -- The run that made the table also copies each login with a pending claim
  -- and no account yet.
  with ins as (
    insert into public.affiliate_signup_identities (auth_user_id, affiliate_account_id, customer_id, first_name, last_name,
        full_name, phone, email, source, name_from, phone_from)
    select u.id, a.id, a.customer_id, m.first_name, m.last_name,
           coalesce(nullif(btrim(coalesce(m.first_name, '') || ' ' || coalesce(m.last_name, '')), ''), m.full_name),
           m.phone, nullif(lower(btrim(coalesce(u.email, ''))), ''), 'backfill',
           case when m.first_name is not null or m.last_name is not null or m.full_name is not null then 'user_metadata' end,
           case when m.phone is not null then 'user_metadata' end
      from auth.users u
      left join public.affiliate_accounts a on a.auth_user_id = u.id
      cross join lateral (
        select nullif(btrim(coalesce(u.raw_user_meta_data ->> 'first_name', '')), '') as first_name,
               nullif(btrim(coalesce(u.raw_user_meta_data ->> 'last_name', '')), '') as last_name,
               nullif(btrim(coalesce(u.raw_user_meta_data ->> 'full_name', '')), '') as full_name,
               nullif(btrim(coalesce(u.raw_user_meta_data ->> 'phone', '')), '') as phone) m
     where (a.id is not null
            and not exists (select 1 from public.affiliate_signup_identities x where x.auth_user_id = u.id))
        or (v_created and a.id is null
            and exists (select 1 from public.affiliate_account_claims c where c.auth_user_id = u.id and c.status = 'pending'))
    returning affiliate_account_id)
  select count(*)::int, (count(*) filter (where ins.affiliate_account_id is null))::int
    into v_backfilled, v_backfilled_claims from ins;
  if v_created then
    raise notice '440: the backfill copied % login(s): % with an affiliate account, % with a pending claim only',
      v_backfilled, v_backfilled - v_backfilled_claims, v_backfilled_claims;
  elsif v_backfilled > 0 then
    raise notice '440: % affiliate login(s) had no copy (a sign-up still running when 440 first went in, a pending claim staff resolved since, or an account made by hand); copied now from their metadata and email as they are today (source ''backfill'')',
      v_backfilled;
  else
    raise notice '440: every affiliate login already has its copy; none added';
  end if;

  -- 4-6. The functions patched.
  for i in 1 .. cardinality(c_sig) loop
    if v_do[i] then execute v_defs[i];
    elsif c_is439[i] and v_c in ('no_436', 'no_439') then null;
    else raise notice '440: public.% is already this version; left alone', c_sig[i]; end if;
  end loop;
  if v_c = 'no_439' then
    raise notice '440: 439 is not installed (event_web_affiliate_contact and event_web_check_self_referral are 436''s), so (C) is skipped. Put 439 in first; after 439, run this file again to patch them.';
  elsif v_c = 'no_436' then
    raise notice '440: 436 is not installed (no event website), so (C) is skipped.';
  end if;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '440: public.% was installed with an md5 other than the tested one', c_new_sig[i]; end if;
    if has_function_privilege('anon', to_regprocedure('public.' || c_new_sig[i]), 'execute')
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_new_sig[i]), 'execute')
       or not has_function_privilege('service_role', to_regprocedure('public.' || c_new_sig[i]), 'execute') then
      raise exception '440: public.% is not the service role''s alone', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if c_is439[i] and v_c in ('no_436', 'no_439') then continue; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_after[i] then
      raise exception '440: public.% was installed with an md5 other than the tested one (%)', c_sig[i], md5(d); end if;
    if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acls[i] then
      raise exception '440: the grants of public.% changed', c_sig[i]; end if;
    if c_is439[i] and (strpos(d, 'raw_user_meta_data->>') > 0 or strpos(d, 'public.affiliate_login_signup_details(') = 0) then
      raise exception '440: public.% still reads the login''s user metadata', c_sig[i]; end if;
  end loop;
  if has_table_privilege('anon', 'public.affiliate_signup_identities', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.affiliate_signup_identities', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'public.affiliate_signup_identities', 'insert,update,delete,truncate,references,trigger')
     or not has_table_privilege('service_role', 'public.affiliate_signup_identities', 'select')
     or not (select relrowsecurity from pg_class where oid = 'public.affiliate_signup_identities'::regclass)
     or exists (select 1 from pg_policy where polrelid = 'public.affiliate_signup_identities'::regclass)
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'public.affiliate_signup_identities'::regclass
                      and t.tgname = 'affiliate_signup_identities_kept' and t.tgenabled = 'O') then
    raise exception '440: public.affiliate_signup_identities is open to a client role, or its UPDATE trigger is not on'; end if;
  -- Every run: after the backfill, every login with an affiliate account has
  -- a copy (one that finished signing up in between, on 437's text, makes
  -- this run fail and change nothing: run it again).
  select count(*) into n from public.affiliate_accounts a
   where not exists (select 1 from public.affiliate_signup_identities x where x.auth_user_id = a.auth_user_id);
  if n > 0 then
    raise exception '440: % affiliate login(s) have no copy after the backfill (a sign-up finished while this ran); nothing was changed: run this file again', n;
  end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("440 Check", @example.invalid, fictional phones no
  -- customer uses); it ends by raising P0440, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select p as x from unnest(array['+61491570120', '+61491570121', '+61491570122', '+61491570123',
                                            '+61491570124', '+61491570125', '+61491570126', '+61491570127']) p
             where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = p)
               and not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) is null
                                  and c.phone ~ '^[\s().0-9-]+$'
                                  and (public.inspect_customer_phone(c.phone) -> 'candidates') ? p)
             limit 3) y;
    if cardinality(t_phones) is distinct from 3 then
      raise exception '440: the self-test found no unused fictional phones'; end if;
    t_mail := '440-check-1-' || t_sfx || '@example.invalid';
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (gen_random_uuid(), t_mail, now(), '{"affiliate_email_unverified": true}'::jsonb, '{}'::jsonb)
    returning id into t_u1;

    -- A sign-up on a phone no one has: a new customer, and one copy, as typed,
    -- with the login's email.
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_u1::text, true);
    t_ans := public.complete_affiliate_onboarding('440 Check', 'Self ' || t_sfx, t_phones[1], true);
    t_cust := (t_ans ->> 'customer_id')::uuid; t_code := t_ans ->> 'referral_code';
    if t_ans ->> 'status' <> 'active' or not (t_ans ->> 'new_customer')::boolean or t_code is null
       or (select count(*) from public.affiliate_signup_identities x where x.auth_user_id = t_u1) <> 1
       or not exists (select 1 from public.affiliate_signup_identities x
                       where x.auth_user_id = t_u1 and x.source = 'onboarding' and x.customer_id = t_cust
                         and x.affiliate_account_id = (select a.id from public.affiliate_accounts a where a.auth_user_id = t_u1)
                         and x.first_name = '440 Check' and x.last_name = 'Self ' || t_sfx
                         and x.full_name = '440 Check Self ' || t_sfx and x.phone = t_phones[1] and x.email = t_mail
                         and x.name_from = 'arguments' and x.phone_from = 'arguments') then
      raise exception '440: the self-test''s sign-up did not write its copy as tested: %', t_ans; end if;
    select to_jsonb(x) into t_row from public.affiliate_signup_identities x where x.auth_user_id = t_u1;
    -- She edits her own metadata (what updateUser does); the copy stays. An
    -- UPDATE of the copy is refused, server code included.
    update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Someone', 'last_name', 'Else ' || t_sfx,
                                                                   'phone', t_phones[3])
     where id = t_u1;
    begin
      update public.affiliate_signup_identities set full_name = 'Someone Else ' || t_sfx where auth_user_id = t_u1;
      raise exception '440: the self-test could rewrite the copy';
    exception when insufficient_privilege then null;
    end;
    if (select to_jsonb(x) from public.affiliate_signup_identities x where x.auth_user_id = t_u1) is distinct from t_row
       or (select count(*) from public.affiliate_login_signup_details(t_cust)) <> 1
       or (select d.full_name from public.affiliate_login_signup_details(t_cust) d) <> '440 Check Self ' || t_sfx then
      raise exception '440: the self-test''s copy changed, or the helper does not give it'; end if;

    -- /r/<code>: her login's email on another phone under another name, and
    -- her login's name on another phone, are herself, as her record is.
    t_ans := public.affiliate_referral_signup(t_code, 'Other', 'Person ' || t_sfx, t_phones[2], t_mail, null);
    if t_ans is distinct from jsonb_build_object('ok', false, 'message', 'You cannot refer yourself.') then
      raise exception '440: the self-test''s sign-up on her login''s email was not refused as herself: %', t_ans; end if;
    t_ans := public.affiliate_referral_signup(t_code, 'Self ' || t_sfx, '440 Check', t_phones[2], 'other-' || t_mail, null);
    if t_ans is distinct from jsonb_build_object('ok', false, 'message', 'You cannot refer yourself.') then
      raise exception '440: the self-test''s sign-up under her login''s name was not refused as herself: %', t_ans; end if;
    if exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = t_phones[2])
       or exists (select 1 from public.referral_signup_events e where e.normalized_phone = t_phones[2]) then
      raise exception '440: the self-test''s refused sign-ups left a row'; end if;
    -- The name and phone she edited into her metadata are someone else's:
    -- registered, referred by her record.
    t_ans := public.affiliate_referral_signup(t_code, 'Someone', 'Else ' || t_sfx, t_phones[3], 'someone-' || t_mail, null);
    if t_ans ->> 'outcome' is distinct from 'registered'
       or not exists (select 1 from public.customers c
                       where public.normalize_customer_phone(c.phone) = t_phones[3] and c.referred_by = t_cust) then
      raise exception '440: the self-test''s stranger (her edited metadata) was not registered: %', t_ans; end if;
    raise exception using errcode = 'P0440', message = '440: self-test done, undone';
  exception when sqlstate 'P0440' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
