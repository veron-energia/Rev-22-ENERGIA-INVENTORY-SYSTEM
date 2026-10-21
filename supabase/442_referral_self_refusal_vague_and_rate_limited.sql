-- 442_referral_self_refusal_vague_and_rate_limited.sql
--
-- A SIGN-UP ON /r/<code> THAT IS THE AFFILIATE HERSELF IS NO LONGER TOLD SO,
-- AND HER TRIES COUNT IN THE SIGN-UP LIMITS (the Owner, 21 Oct 2026: "Go
-- live now, fix it next")
--
-- WHAT WAS WRONG
--
--   * affiliate_referral_signup (the /r/<code> page, and the old seminar site
--     rev22-energia-seminar, both with the anon key) answers a sign-up that is
--     the referrer herself with {ok:false, message:'You cannot refer
--     yourself.'}. Since 440 that is a sign-up matching her record (its phone
--     with its name) OR what her affiliate login signed up with: a name of
--     the same words, the phone, or the email inbox, each ALONE. So anyone
--     who has an affiliate's code (it is on every link she shares) can type a
--     phone or an email and learn from the answer whether it is the one her
--     login signed up with, or whether a name is hers (440's NOT COVERED).
--   * Such a try writes nothing (no referral_signup_events row), so the
--     per-phone limit (3 tries on one phone in 10 minutes) and the per-link
--     limit (20 new customers through one link in an hour) never count it:
--     the test can be repeated without end.
--
-- THE OWNER'S ANSWER (21 Oct 2026, with 440 going live)
--
--   "Go live now, fix it next": a follow-up that (1) gives a vaguer refusal
--   for a self match on /r/<code>, so the answer does not reveal that the
--   phone, email or name is the affiliate's own, and (2) counts those tries
--   in the sign-up rate limit.
--
-- HOW IT READS (this file, 21 Oct 2026; reviewed the same day)
--
--   * Who counts as herself does not change (440's rule: her record; her
--     login's sign-up name, phone or email inbox). Only where she is
--     answered, what she is answered, and what is written, change.
--   * Where: a try as herself goes exactly the way the same details would go
--     if they were not hers, through every answer the call gives before a
--     customer would be made:
--       - the honeypot, a phone or name refused, a link not accepting,
--         AMBIGUOUS_CUSTOMER_MATCH: as for anyone;
--       - details already on file (the phone with a name of the same words;
--         her record is one such): "already registered", as for anyone on
--         file, and never limited, as for anyone on file; recorded as an
--         event 'self_known' in place of 'duplicate';
--       - a phone 3 customers already have: the CUSTOMER_PHONE_LIMIT error,
--         writing nothing, as for anyone;
--       - the phone's limit (any 3 events on the phone in the last 10
--         minutes): "Too many registration attempts for this phone number.
--         Please wait 10 minutes or contact Energia.", writing nothing, as
--         for anyone;
--       - the link's limit (20 new customers AND self tries through one link
--         in the last hour; before: new customers only): "This referral link
--         has had many registrations in the last hour. Please try again later
--         or contact Energia." and a 'link_limit' event, as for anyone;
--       - past all of these, where a new customer would be made: no customer;
--         an event 'self' (which both limits count, as they count a new
--         customer) and the "already registered" answer.
--     So wherever the same details would not have made a customer, a try as
--     herself gets the very answer, and leaves the limits in the very state,
--     that the same details would if they were not hers.
--   * The answer, where a customer would have been made: exactly, word for
--     word, what someone already registered is told by the same call:
--       {"ok": true, "outcome": "already_registered", "message": "This phone
--        number is already registered with Energia, so no new registration
--        was created. Nothing about your existing record has changed."}
--     Chosen because:
--       - it is the commonest answer of this call after "Registration
--         successful" (anyone already on file who opens a link), and the
--         JSON is the same as a real "already registered";
--       - for a genuine affiliate who tries her own link (to see how it
--         works, or for herself) it is true and calm: the page (unchanged)
--         shows "You are already registered" and that nothing changed, and
--         does not send her to the booking page; she is on file. What she is
--         no longer told is WHY no referral was made (that she cannot refer
--         herself); staff can tell her, and they see her tries (below);
--       - the alternatives were worse for her: "This referral link is not
--         accepting new registrations right now" would tell her that her own
--         link is switched off (she might stop sharing it, or call the
--         centre), while the page above it says it is accepting; "Too many
--         registration attempts" or the link's hourly answer are wrong on the
--         first try; pretending success ("Registration successful") would
--         send her to the booking page as a new friend and, for the seminar
--         site, record a customer that was never made; a new sentence shared
--         with other answers would change what genuine visitors are told and
--         how the seminar site reads them.
--   * What it still tells (the Owner's point (1) is met only in part): the
--     one difference left between a try as herself and the same try by
--     someone else is that last answer: "already registered" where the other
--     would be "Registration successful" (and a new customer). On details
--     nobody has on file (a phone no customer has, or a name not on file for
--     that phone) nobody else can be "already registered", so a caller who
--     chose those details and typed one real candidate (an email, a name, a
--     phone) is told FOR CERTAIN, in one call, whether it is hers. The JSON
--     is a real "already registered"'s; the caller's own choice of the other
--     details gives it away. What 442 takes away is the plain "You cannot
--     refer yourself", and every free or unrecorded try: each try that can
--     tell her apart is either a new customer (a wrong guess: made, referred
--     by her) or a 'self' event (a right one: in the Audit Log), and both
--     limits count both (3 per phone in 10 minutes; 20 per link in an hour,
--     new customers and self tries together). Every other route a review
--     found (a phone 3 customers have, details on file past the phone's
--     limit, a link at its limit) now answers a right and a wrong guess
--     alike. Hiding the last difference too is the Owner's choice (NOT
--     COVERED, first item).
--   * The old seminar site (rev22-energia-seminar, src/lib/referrals.ts, not
--     changed here) reads ok:true with outcome "already_registered" as
--     "existing": for ANY self match (the affiliate herself, or a guest who
--     used her login's email, name or phone) its Referrals tab now says "Not
--     added: already an Energia customer, so nothing was changed" where it
--     said "Not added: this is the affiliate themselves" (its /refer
--     yourself/ rule no longer matches anything); on a phone 3 customers
--     have, "Not added, staff to check: this number already belongs to 3
--     customers", as for anyone; the guest's free seat is booked either way,
--     as before.
--   * Counted: the events, both written with the code as the link reads it,
--     her record as the referrer, the phone typed, and no customer:
--       - 'self': a try as herself that got as far as a new customer would.
--         Both limits count it (the phone's counts every event; the link's
--         now counts 'created', 'phone_shared' and 'self');
--       - 'self_known': a try as herself on details on file. The phone's
--         limit counts it, as it counts 'duplicate'; the link's does not, as
--         it does not count 'duplicate'.
--   * Never a referral: no customer, no referral_signup_checks row, nobody's
--     referred_by changes. Every reader of referral_signup_events, as read
--     on 21 Oct 2026: this function (the two limits above; nothing else of it
--     reads the table) and 436's event website: event_web_new_customer (its
--     own per-link limit, which counts 'created' and 'phone_shared' only, so
--     no /r/ self try counts there) and event_web_apply_referral (writes
--     only). (The event website has an answer of its own called 'self'; it is
--     never an event.) No view, page, Edge Function or seminar code reads the
--     table. Promotions, commission, the Referrals and Affiliates pages, the
--     portal and the reports read customers.referred_by and the checks, which
--     a self try never writes. Owners and Managers can read the events (its
--     row level security, aff_events_mgr_read); no page lists them.
--   * Staff see each recorded try ('self' and 'self_known'): an Audit Log
--     entry on her record (table customers, record her customer id, action
--     'referral_self_signup_refused', module 'affiliate'), with the event
--     ('outcome': 'self' or 'self_known'), what matched ('record',
--     'login_name', 'login_phone', 'login_email'), the phone, the name and
--     the email typed (each at most 200 characters), the code, and the login
--     signed in, if any. It is written straight into audit_logs:
--     write_audit_ex names the caller (auth.uid()) as changed_by, which must
--     be a member of staff, so it fails for her own login signed in (as it
--     does today, silently, for "referral_registered" entries made while an
--     affiliate is signed in). Here changed_by is the caller only when she is
--     staff (a Manager at the counter), else empty (the Audit Log shows
--     "System"). Best effort, as the entry for a registration is: should it
--     fail, the answer and the event stand. Managers and Owners read the
--     Audit Log; the caller learns nothing from it (the answer is the same
--     JSON). A try refused by a limit or by the 3-customer rule is not in the
--     Audit Log, as no sign-up refused by them is.
--
-- WHAT THIS DOES
--
--   affiliate_referral_signup(text,text,text,text,text,text), patched at five
--   anchors, nothing else:
--   1. its declarations: v_self (what matched, if anything);
--   2. the self check (440's text): who is herself as before, kept in
--      v_self; nothing is answered there any more;
--   3. "already registered" (details on file): a try as herself writes
--      'self_known' in place of 'duplicate', and the Audit Log entry; the
--      answer is the one anyone on file gets;
--   4. the per-link limit (425's count): 'self' counts with 'created' and
--      'phone_shared';
--   5. just before a new customer would be made (after the 3-customer rule,
--      the phone's limit and the link's limit): a try as herself writes
--      'self' and the Audit Log entry and is answered "already registered".
--   Its grants (anon, authenticated, service_role) are kept.
--
-- NOT CHANGED
--
--   * Every answer a sign-up that is not her gets, and their order: the
--     honeypot, a phone or name refused, a link not accepting,
--     AMBIGUOUS_CUSTOMER_MATCH, someone already registered (a 'duplicate'
--     event, never limited), the phone's 3-customer rule, the phone's limit,
--     the link's limit (which now also counts self tries), a new customer
--     (with 425's check when the phone is someone else's), "Registration
--     successful" with the label.
--   * Every other function: the ten 436 pins, 437's, 438's, 439's and 440's
--     other functions (complete_affiliate_onboarding, the copy table and its
--     helper), event_web_new_customer and event_web_apply_referral (whose
--     link limit therefore does not count /r/ self tries), the commission
--     engine; the tables (referral_signup_events has no check on what an
--     event says; audit_logs as it is).
--   * The pages: ReferralSignupPage.tsx already shows an "already
--     registered" answer as "You are already registered" with its message,
--     and the CUSTOMER_PHONE_LIMIT error as the phone's message
--     (phoneErrorMessage), as for anyone. The seminar site (its own
--     repository) is not changed.
--
-- NOT COVERED (told to the Owner)
--
--   * The one-call check above. On details nobody has on file, "already
--     registered" can only mean a try as herself, so whoever has her code is
--     told for certain, in one call, whether an email, a name or a phone is
--     what her login signed up with (or a name and phone are her record's).
--     442 limits it and leaves a trace; it does not hide it:
--       - each try that tells counts in both limits: at most 3 per phone in
--         10 minutes and 20 per link in an hour (new customers and self tries
--         together); past them every try gets what a new sign-up would;
--       - a wrong guess makes a real customer referred by her (in her portal
--         and the staff views until staff remove it); a right one makes a
--         'self' event and an Audit Log entry;
--       - on a phone 3 customers have, on details on file, or past a limit,
--         right and wrong guesses get the same answer (nothing to learn).
--     The Owner's choice, to hide it fully (each changes what a genuine
--     affiliate trying her own link is told):
--       (a) keep 442 as it is (above);
--       (b) answer a try as herself on details nobody has the way a new
--           sign-up is answered ("Registration successful." with her label):
--           a genuine affiliate is sent to the booking page as a new friend,
--           the seminar site records a customer that was never made, and,
--           unless the pretend sign-up is remembered, a second try with the
--           same details is "registered" again where a real new customer
--           would be "already registered", which moves the check to the
--           second try;
--       (c) make the customer anyway, held for staff like 425's check (a
--           duplicate of her, or her family member's real record), so every
--           answer and every later try is a new sign-up's: hides it fully, at
--           the cost of a record per try that staff merge or remove.
--   * A genuine new guest who matches only what her login signed up with (an
--     affiliate typing her own email for a parent who has none, autofill on
--     her phone, a family member on her phone) is told "already registered"
--     though nobody is on file for them. The /r/ page shows "You are already
--     registered" and does not send them to booking; the seminar site's
--     Referrals tab shows "Not added: already an Energia customer, so nothing
--     was changed", with no "add them by hand" hint (before 442 it said "this
--     is the affiliate themselves", which staff might question next to
--     another name). Nothing is written wrongly (they were not registered
--     before 442 either). Staff find them in the Audit Log: action
--     'referral_self_signup_refused', matched holding 'login_email',
--     'login_name' or 'login_phone' next to a name typed that is not hers;
--     and add them by hand on the Customers page (reassign_customer_referrer).
--     No staff list or filter of these entries is added here.
--   * On details already on file a try as herself is never limited (as for
--     anyone on file), and each is recorded: someone who repeats it fills the
--     events and the Audit Log, as repeated 'duplicate' tries already fill
--     the events.
--   * A try as herself refused by a limit or by the 3-customer rule leaves no
--     Audit Log entry (as no sign-up refused by them does; the 3-customer
--     error undoes everything the call wrote). Staff see only the
--     'link_limit' event the link's limit writes, as for anyone.
--   * Anyone with her code can use up her link's hour with 20 self tries
--     (her phone, email or name on 20 phones no one has); genuine friends are
--     then refused for up to an hour. 20 made-up sign-ups could already do
--     that (and made 20 customers); this adds a way that makes none.
--   * The event website (436's per-link limit) does not count /r/ self
--     tries (it was not changed); its own self matches write no event and
--     its guests are not told.
--   * A genuine affiliate who tries her own link is not told that she cannot
--     refer herself (she is told she is registered); on a phone 3 customers
--     have, under a name not on file there, she gets the 3-customer error, as
--     anyone would. The page's "already registered" screen offers "Want to
--     become an affiliate instead?", which reads oddly to an affiliate (not
--     changed).
--   * The time a try takes is not the same: a self try writes an event and
--     an Audit Log entry where a sign-up that is not her writes a customer
--     (with its triggers), an event and its entry, or a 'duplicate' event
--     alone. Not measured, not padded.
--   * The Audit Log entry is best effort (see above): if it fails, only the
--     event remains.
--   * 440 cannot be run again after this file (its guard of this function
--     accepts only 425's or its own text; refused, changing nothing). 440's
--     DEPLOY ORDER step 3 (the count of affiliate logins with no sign-up
--     copy, expected 0) must therefore be done first: this file refuses to
--     patch while any affiliate login has no copy, and says to run 440 once
--     more.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * no other function takes the name; the function is its BEFORE (patched:
--     each anchor found exactly once, no patch holding another's anchor, the
--     text built has the tested AFTER md5) or already the AFTER (left alone,
--     with a notice); anything else is refused with the installed md5 and the
--     patched one (to re-pin);
--   * the functions relied on and not changed are as read on production on
--     21 Oct 2026 (below); auth.uid() is there;
--   * the only functions (any schema but a session's temporary ones) whose
--     text names referral_signup_events are this one and the event website's
--     two (pinned below), and no view depends on the table;
--   * the columns read and written (referral_signup_events, audit_logs,
--     profiles.id) are as read; referral_signup_events has no check
--     constraint (so 'self' and 'self_known' are accepted); both tables have
--     row level security with exactly their read rule for staff (as read);
--   * when this run patches: every affiliate login has its sign-up copy
--     (440), as above.
--   Afterwards: the md5 is the AFTER one, the grants are as they were, and
--   the function's text names no "refer yourself". Then a self-test, in a
--   block that is always undone (it ends by raising P0442, so it leaves no
--   row): a made-up affiliate (@example.invalid) signs up on an unused
--   fictional phone; through her link, signed out, her login's email on
--   another such phone is told "already registered" (the exact JSON), with a
--   'self' event and an Audit Log entry; signed in as her login, her login's
--   name on that phone: the same, recorded; a third try: the same; a fourth
--   on that phone: the phone's limit, writing nothing; no customer, nobody
--   referred; a stranger is registered, and on a second try is told exactly
--   what her tries were told; the stranger's details with her login's email,
--   twice (past the phone's 3 tries), and with another email: each that same
--   answer, never limited, two 'self_known' events with their entries and a
--   'duplicate'; on a phone 3 customers have (three sign-ups through her
--   link), her login's email and another email under names not on file both
--   get the CUSTOMER_PHONE_LIMIT error, word for word the same, writing
--   nothing. A second run changes nothing.
--   Locks: the function is replaced (its catalogue row, held to the end of
--   the apply); no table is locked but for the rows the self-test writes and
--   undoes. Its advisory locks (its fictional phones, its made-up affiliate's
--   link) are released with its rows when its block is undone (the P0442),
--   before the apply commits. A sign-up running at that moment finishes on
--   the text it started with.
--
-- DEPLOY ORDER (with the Owner's go-ahead)
--
--   After 440 (it patches 440's text; before 440 it refuses as a whole), and
--   after 440's DEPLOY ORDER step 3 (the count of affiliate logins with no
--   copy is 0):
--     production now (... 436, 438, 437, 439, 440) -> 442
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second says "already
--      this version; left alone" and changes nothing.
--   2. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   No page, Edge Function or setting changes. Tell the seminar site's
--   maintainer that its Referrals tab now says "Not added: already an
--   Energia customer, so nothing was changed" for any self match: the
--   affiliate herself, or a guest who used her login's email, name or phone
--   (a real new guest among them is not added; staff find them in the Audit
--   Log, action 'referral_self_signup_refused', matched holding
--   'login_email', 'login_name' or 'login_phone' next to a name that is not
--   hers, and add them by hand), and that its /refer yourself/ rule no
--   longer matches anything (optional tidy-up there, e.g. a note to check an
--   "existing" row whose name differs from the customer's).
--
-- BEFORE (production, 21 Oct 2026: ... 436, 438, 437, 439, 440 in; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   affiliate_referral_signup(text,text,text,text,text,text)       a3deac154f5144cffb34fab871f076c6  (440's AFTER)
--   relied on, not changed
--   customer_names_match(text,text)                                ef1af52e4888cefb6037a2291f4e011d
--   customer_email_match_key(text)                                 be468815c9626fff1728e2cfcd484b66
--   normalize_customer_phone(text)                                 b2bfac910e0c9eff402ba44e19750bee
--   customer_phone_name_matches(text,text)                         1bdf8322972b6671b7cbb08bc8211f8a
--   require_resolved_customer_identity(text,text)                  5bde1a418363442ec27e2944442f5874
--   inspect_customer_phone(text,text)                              6672c4d1963996f3b601896f4a55916e
--   affiliate_login_signup_details(uuid)                           71e6d6f9ab2b474450b5c00f60f14bb4  (440's)
--   current_user_role()                                            519b0a33a3548f970c5d585b6e76a389
--   complete_affiliate_onboarding(text,text,text,boolean)          43084deab54968eacaf1793c470fd08f  (440's AFTER; the self-test)
--   event_web_new_customer(uuid)                                   a253f76a9db721212a9c110bc41ff483  (reads the events)
--   event_web_apply_referral(uuid,uuid)                            b034075f9882cb4221e3a554e6453317  (writes them)
--   public function fingerprint, production now                    bbbfcbb99f38cb278a58e2496abe0a4f (1366 functions)
-- AFTER (for later guards)
--   affiliate_referral_signup(text,text,text,text,text,text)       c76573912de0a4ded29e81e5c56c96d3
--   public function fingerprint, production now -> 442, worked out on copies
--   of production (21 Oct 2026; a second run the same)            c2dac6760bd1be258563f69203c30279 (1366)
--
-- Test: scripts/affiliate-signup/tests/referral-self-442.sql (begin ...
-- rollback; it installs this file twice; run with -v nomig=1 where it is in).
-- Checked on copies of production (21 Oct 2026), with 442 and without:
-- 440's login-identity-440.sql (-v nomig=1), 437's straight-in-437.sql
-- (-v nomig=1), 425's shared-phone-425.sql (-v mig=/dev/null), 392's
-- booking-label.sql, referral-and-states.sql and the rest of npm run
-- test:affiliate-signup, scripts/referrals/tests/customer-paging.sql, 436's
-- event-website.sql (-v skip_install=1), and scripts/permissions/tests
-- function-grants.sql, staff-only-functions.sql, role-guards.sql and
-- rls-policies.sql pass. The four suites that pinned the old answer or md5
-- (440's R0, R1-3, B6, B7, G3; 392's self-referral and md5 checks; 425's W2)
-- accept 442's answer now, keeping what they check (herself, nothing made,
-- nobody referred; since 442 one 'self' or 'self_known' event per try).
-- Three suites expect a database from before a migration production already
-- has, and fail the same way with and without 442: scripts/referrals/tests/
-- visits-and-october.sql (398 refuses to install), scripts/commissions/
-- tests/affiliates-425.sql (-v mig=/dev/null: its 7 before-425 checks; its
-- grant check of this function passes) and scripts/permissions/tests/
-- policy-initplan.sql (-v mig=/dev/null: X-10, "430 changed nothing").

set lock_timeout = '5s';

do $mig$
declare
  -- ── The function patched, at five anchors ───────────────────────────────
  c_sig constant text := 'affiliate_referral_signup(text,text,text,text,text,text)';
  c_before constant text := 'a3deac154f5144cffb34fab871f076c6';   -- 440's AFTER
  c_after constant text := 'c76573912de0a4ded29e81e5c56c96d3';
  c_anchor constant text[] := array[
-- 1. The declarations: what matched, if anything
$a1$  v_holders uuid[];  -- 425: the customers in use who have this phone already
$a1$,
-- 2. The self check (440's text): no longer answered there
$a2$  -- 440 (the Owner, 21 Oct 2026, B): she is herself also when the sign-up
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
$a2$,
-- 3. "Already registered" (details on file): a try as herself is recorded
$a3$  if cardinality(v_matches) >= 1 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, 'duplicate');
$a3$,
-- 4. The per-link limit of a sign-up (425's): tries as herself count too
$a4$  if (select count(*) from public.referral_signup_events e
       where e.referrer_customer_id = v_ref_cust and e.outcome in ('created', 'phone_shared')
         and e.created_at > now() - interval '1 hour') >= 20 then
$a4$,
-- 5. Just before a new customer is made: a try as herself stops there
$a5$  -- 425: the phone belongs to a customer in use under another name
$a5$];
  c_patch constant text[] := array[
$r1$  v_holders uuid[];  -- 425: the customers in use who have this phone already
  v_self text[];  -- 442: what in the sign-up is the referrer herself (440's rule), if anything
$r1$,
$r2$  -- 440 (the Owner, 21 Oct 2026, B): she is herself also when the sign-up
  -- matches what the referrer's affiliate login signed up with (the server's
  -- own copy, which she cannot edit; affiliate_login_signup_details): a name
  -- of the same words (customer_names_match), its phone
  -- (normalize_customer_phone) or its email inbox (customer_email_match_key).
  -- 442 (the Owner, 21 Oct 2026, "go live now, fix it next"): who is herself
  -- is as 440 has it (v_self says what matched: 'record', 'login_name',
  -- 'login_phone', 'login_email'), but she is no longer told so here. A try
  -- as herself goes the way the same details would go if they were not
  -- hers, up to where a customer would be made: on details already on file,
  -- "already registered", never limited (below: an event 'self_known' in
  -- place of 'duplicate'); else the phone's 3 customers, the phone's limit
  -- and the link's limit, as for a new customer; then, in place of the
  -- customer, an event 'self' (both limits count it, as they count a new
  -- customer) and the "already registered" answer (below). Each try that
  -- gets that far is in the Audit Log on her record, for staff. It is never
  -- a referral: no customer, no check, nobody referred. This does not hide
  -- everything: on details nobody has on file, "already registered" can only
  -- be a try as herself, so a caller who chose those details still learns
  -- that something typed is hers; what 442 takes away is the plain answer,
  -- and every try that tells her apart is counted by both limits and logged.
  select array_remove(array[
           case when v_ref_cust = any (v_matches) then 'record' end,
           case when bool_or(public.customer_names_match(d.full_name, v_name)) then 'login_name' end,
           case when bool_or(public.normalize_customer_phone(d.phone) = v_norm) then 'login_phone' end,
           case when bool_or(public.customer_email_match_key(d.email) = public.customer_email_match_key(v_email))
                then 'login_email' end], null)
    into v_self
    from public.affiliate_login_signup_details(v_ref_cust) d;
$r2$,
$r3$  -- 442: a try as herself on details already on file (her record, or
  -- someone on file typed with her login's name, phone or email) is
  -- answered as anyone on file is, and never limited either; it is recorded
  -- as 'self_known' in place of 'duplicate' (the phone's limit counts both,
  -- the link's neither), with the Audit Log entry.
  if cardinality(v_matches) >= 1 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, case when cardinality(v_self) > 0 then 'self_known' else 'duplicate' end);
    if cardinality(v_self) > 0 then
      -- For staff (the Audit Log, on her record): the event, what matched
      -- and what was typed. Whoever calls (signed out, her own login signed
      -- in, staff), so not through write_audit_ex, whose changed_by must be a
      -- member of staff. Best effort, as the entry for a registration
      -- (below): it never changes the answer.
      begin
        insert into public.audit_logs(table_name, record_id, action, new_data, changed_by, actor_role, module)
        values ('customers', v_ref_cust, 'referral_self_signup_refused',
                jsonb_build_object('referral_code', btrim(p_code), 'source', 'affiliate_link', 'outcome', 'self_known',
                                   'matched', to_jsonb(v_self), 'phone', v_norm, 'name', left(v_name, 200),
                                   'email', left(v_email, 200), 'signed_in_login', auth.uid()),
                (select p.id from public.profiles p where p.id = auth.uid()),
                public.current_user_role()::text, 'affiliate');
      exception when others then null;
      end;
    end if;
$r3$,
$r4$  -- 442: a try as the referrer herself that got as far as a new customer
  -- ('self', below) counts here too, as a new customer does.
  if (select count(*) from public.referral_signup_events e
       where e.referrer_customer_id = v_ref_cust and e.outcome in ('created', 'phone_shared', 'self')
         and e.created_at > now() - interval '1 hour') >= 20 then
$r4$,
$r5$  -- 442: a try as herself that has passed every check a new customer
  -- passes (above): in place of the customer, an event 'self', which both
  -- limits count as they count a new customer, the Audit Log entry (as for
  -- 'self_known', above), and what someone already registered is told,
  -- word for word.
  if cardinality(v_self) > 0 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, 'self');
    begin
      insert into public.audit_logs(table_name, record_id, action, new_data, changed_by, actor_role, module)
      values ('customers', v_ref_cust, 'referral_self_signup_refused',
              jsonb_build_object('referral_code', btrim(p_code), 'source', 'affiliate_link', 'outcome', 'self',
                                 'matched', to_jsonb(v_self), 'phone', v_norm, 'name', left(v_name, 200),
                                 'email', left(v_email, 200), 'signed_in_login', auth.uid()),
              (select p.id from public.profiles p where p.id = auth.uid()),
              public.current_user_role()::text, 'affiliate');
    exception when others then null;
    end;
    return jsonb_build_object('ok', true, 'outcome', 'already_registered',
      'message', 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.');
  end if;

  -- 425: the phone belongs to a customer in use under another name
$r5$];
  -- The answers a self try may get, as the function gives them elsewhere
  -- (the self-test compares them).
  c_known constant jsonb := jsonb_build_object('ok', true, 'outcome', 'already_registered',
    'message', 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.');
  c_too_many constant jsonb := jsonb_build_object('ok', false,
    'message', 'Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.');

  -- ── Relied on, not changed (production, 21 Oct 2026) ─────────────────────
  c_relied constant text[] := array[
    'customer_names_match(text,text)', 'customer_email_match_key(text)', 'normalize_customer_phone(text)',
    'customer_phone_name_matches(text,text)', 'require_resolved_customer_identity(text,text)',
    'inspect_customer_phone(text,text)', 'affiliate_login_signup_details(uuid)', 'current_user_role()',
    'complete_affiliate_onboarding(text,text,text,boolean)',
    'event_web_new_customer(uuid)', 'event_web_apply_referral(uuid,uuid)'];
  c_relied_md5 constant text[] := array[
    'ef1af52e4888cefb6037a2291f4e011d', 'be468815c9626fff1728e2cfcd484b66', 'b2bfac910e0c9eff402ba44e19750bee',
    '1bdf8322972b6671b7cbb08bc8211f8a', '5bde1a418363442ec27e2944442f5874',
    '6672c4d1963996f3b601896f4a55916e', '71e6d6f9ab2b474450b5c00f60f14bb4', '519b0a33a3548f970c5d585b6e76a389',
    '43084deab54968eacaf1793c470fd08f',
    'a253f76a9db721212a9c110bc41ff483', 'b034075f9882cb4221e3a554e6453317'];
  -- Every function that names referral_signup_events (any schema), as read.
  c_readers constant text[] := array['affiliate_referral_signup(text,text,text,text,text,text)',
    'event_web_apply_referral(uuid,uuid)', 'event_web_new_customer(uuid)'];
  -- Who may read the events and the Audit Log (staff), as read.
  c_events_policy constant text := 'aff_events_mgr_read r ( SELECT is_owner_or_manager() AS is_owner_or_manager)';
  c_audit_policy constant text := 'read audit logs r ( SELECT is_manager_or_above() AS is_manager_or_above)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; d2 text; i int; j int; n int;
  v_do boolean := false; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_u1 uuid; t_cust uuid; t_code text; t_mail text; t_ans jsonb; t_self jsonb;
  t_err text[] := '{}';
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- One function of this name.
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = split_part(c_sig, '(', 1)
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '442: another function takes the name: %', v; end if;
  if to_regprocedure('public.' || c_sig) is null then raise exception '442: public.% is missing', c_sig; end if;

  -- Its BEFORE (patched here) or its AFTER (left alone).
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) <> c_after then
    d2 := d;
    for i in 1 .. cardinality(c_anchor) loop
      n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
      if n <> 1 then
        raise exception '442: public.% is not the version this was tested against (md5 %), and its anchor % is found % times, not once. Re-read it and re-test before applying.',
          c_sig, md5(d), i, n; end if;
      -- No patch holds another anchor's text, so each is replaced once, in
      -- whatever order.
      for j in 1 .. cardinality(c_patch) loop
        if j <> i and strpos(c_patch[j], c_anchor[i]) > 0 then
          raise exception '442: patch % holds anchor %', j, i; end if;
      end loop;
    end loop;
    for i in 1 .. cardinality(c_anchor) loop
      d2 := replace(d2, c_anchor[i], c_patch[i]);
    end loop;
    if md5(d) <> c_before then
      raise exception '442: public.% is not the version this was tested against (md5 %; patched it would be md5 %). Re-read it and re-test before applying.',
        c_sig, md5(d), md5(d2); end if;
    if md5(d2) <> c_after then
      raise exception '442: the text built for public.% is not the tested one (md5 %)', c_sig, md5(d2); end if;
    v_do := true;
  end if;

  -- The functions relied on are as read.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '442: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '442: auth.uid() must be there'; end if;

  -- Nothing else reads referral_signup_events: these three functions (none
  -- counts 'self' or 'self_known' as a referral) and no view.
  -- (A session's own temporary functions, a test suite's helpers, are not
  -- counted.)
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ilike '%referral_signup_events%' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_readers));
  if v is not null then
    raise exception '442: other functions read referral_signup_events (%); check that they do not count ''self'' or ''self_known'' as a referral, then re-test', v; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.oid::regprocedure::text = any (c_readers) and p.prosrc ilike '%referral_signup_events%') <> cardinality(c_readers) then
    raise exception '442: the functions that read referral_signup_events are not as read on 21 Oct 2026'; end if;
  select string_agg(distinct rw.ev_class::regclass::text, ', ') into v
    from pg_depend dp join pg_rewrite rw on rw.oid = dp.objid
   where dp.classid = 'pg_rewrite'::regclass and dp.refobjid = 'public.referral_signup_events'::regclass
     and rw.ev_class <> 'public.referral_signup_events'::regclass;
  if v is not null then raise exception '442: views read referral_signup_events (%); check them, then re-test', v; end if;

  -- The columns read and written.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('referral_signup_events', 'referral_code', 'text'), ('referral_signup_events', 'referrer_customer_id', 'uuid'),
                 ('referral_signup_events', 'new_customer_id', 'uuid'), ('referral_signup_events', 'normalized_phone', 'text'),
                 ('referral_signup_events', 'outcome', 'text'), ('referral_signup_events', 'created_at', 'timestamp with time zone'),
                 ('audit_logs', 'table_name', 'text'), ('audit_logs', 'record_id', 'uuid'), ('audit_logs', 'action', 'text'),
                 ('audit_logs', 'new_data', 'jsonb'), ('audit_logs', 'changed_by', 'uuid'), ('audit_logs', 'actor_role', 'text'),
                 ('audit_logs', 'module', 'text'), ('profiles', 'id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '442: these columns are missing or not as read on 21 Oct 2026: %', v; end if;
  -- An event may be 'self' or 'self_known' (no check on what it says).
  if exists (select 1 from pg_constraint where conrelid = 'public.referral_signup_events'::regclass and contype = 'c') then
    raise exception '442: referral_signup_events has a check constraint now; make sure it allows ''self'' and ''self_known'', then re-test'; end if;
  -- Staff can read what is written for them; no client can write it.
  if not (select relrowsecurity from pg_class where oid = 'public.referral_signup_events'::regclass)
     or (select string_agg(polname || ' ' || polcmd::text || ' ' || pg_get_expr(polqual, polrelid), ' | ')
           from pg_policy where polrelid = 'public.referral_signup_events'::regclass) is distinct from c_events_policy
     or not (select relrowsecurity from pg_class where oid = 'public.audit_logs'::regclass)
     or (select string_agg(polname || ' ' || polcmd::text || ' ' || pg_get_expr(polqual, polrelid), ' | ')
           from pg_policy where polrelid = 'public.audit_logs'::regclass) is distinct from c_audit_policy then
    raise exception '442: who may read referral_signup_events or audit_logs is not as read on 21 Oct 2026'; end if;

  -- When this run patches: every affiliate login has its sign-up copy (440).
  -- After this file 440 cannot be run again, and it is 440 that copies a
  -- login left without one (440's DEPLOY ORDER, step 3).
  if v_do then
    select count(*) into n from public.affiliate_accounts a
     where not exists (select 1 from public.affiliate_signup_identities x where x.auth_user_id = a.auth_user_id);
    if n > 0 then
      raise exception '442: % affiliate login(s) have no sign-up copy. Run 440 once more first (it copies them; after 442 it refuses), then this file', n;
    end if;
  end if;

  -- What may call it now (kept as it is).
  v_acl := (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig));

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_do then execute d2;
  else raise notice '442: public.% is already this version; left alone', c_sig; end if;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) <> c_after then
    raise exception '442: public.% was installed with an md5 other than the tested one (%)', c_sig, md5(d); end if;
  if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception '442: the grants of public.% changed', c_sig; end if;
  if strpos(d, 'refer yourself') > 0 then
    raise exception '442: public.% still names a self-referral in an answer', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("442 Check", @example.invalid, fictional phones no
  -- customer and no recent event uses); it ends by raising P0442, which
  -- undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select p as x from unnest(array['+61491570130', '+61491570131', '+61491570132', '+61491570133',
                                            '+61491570134', '+61491570135', '+61491570136', '+61491570137',
                                            '+61491570138', '+61491570139']) p
             where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = p)
               and not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) is null
                                  and c.phone ~ '^[\s().0-9-]+$'
                                  and (public.inspect_customer_phone(c.phone) -> 'candidates') ? p)
               and not exists (select 1 from public.referral_signup_events e
                                where e.normalized_phone = p and e.created_at > now() - interval '1 hour')
             limit 4) y;
    if cardinality(t_phones) is distinct from 4 then
      raise exception '442: the self-test found no unused fictional phones'; end if;
    t_mail := '442-check-1-' || t_sfx || '@example.invalid';
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (gen_random_uuid(), t_mail, now(), '{"affiliate_email_unverified": true}'::jsonb, '{}'::jsonb)
    returning id into t_u1;
    -- An affiliate signs up (a new customer on a phone no one has).
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_u1::text, true);
    t_ans := public.complete_affiliate_onboarding('442 Check', 'Self ' || t_sfx, t_phones[1], true);
    t_cust := (t_ans ->> 'customer_id')::uuid; t_code := t_ans ->> 'referral_code';
    if t_ans ->> 'status' <> 'active' or t_code is null then
      raise exception '442: the self-test''s affiliate did not sign up: %', t_ans; end if;

    -- Through her link, signed out: her login's email on another phone under
    -- another name is herself; she is told what someone registered is told.
    perform set_config('request.jwt.claim.role', 'anon', true);
    perform set_config('request.jwt.claim.sub', '', true);
    t_self := public.affiliate_referral_signup(t_code, 'Other', 'Person ' || t_sfx, t_phones[2], t_mail, null);
    if t_self is distinct from c_known then
      raise exception '442: the self-test''s sign-up on her login''s email was not given the registered answer: %', t_self; end if;
    if (select count(*) from public.referral_signup_events e
         where e.normalized_phone = t_phones[2] and e.outcome = 'self' and e.referrer_customer_id = t_cust
           and e.referral_code = t_code and e.new_customer_id is null) <> 1
       or (select count(*) from public.referral_signup_events e where e.normalized_phone = t_phones[2]) <> 1
       or not exists (select 1 from public.audit_logs l
                       where l.action = 'referral_self_signup_refused' and l.record_id = t_cust and l.table_name = 'customers'
                         and l.new_data -> 'matched' = '["login_email"]'::jsonb and l.new_data ->> 'phone' = t_phones[2]
                         and l.new_data ->> 'outcome' = 'self' and l.changed_by is null) then
      raise exception '442: the self-test''s try was not recorded (a ''self'' event and an Audit Log entry)'; end if;
    -- Signed in as herself, her login's name on that phone: the same answer,
    -- and recorded too (her login is no member of staff).
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_u1::text, true);
    t_ans := public.affiliate_referral_signup(t_code, '442 Check', 'Self ' || t_sfx, t_phones[2], null, null);
    if t_ans is distinct from c_known
       or not exists (select 1 from public.audit_logs l
                       where l.action = 'referral_self_signup_refused' and l.record_id = t_cust
                         and l.new_data -> 'matched' = '["login_name"]'::jsonb and l.new_data ->> 'signed_in_login' = t_u1::text) then
      raise exception '442: the self-test''s signed-in try was not answered or recorded as tested: %', t_ans; end if;
    -- A third try on that phone; then the phone's limit refuses a fourth,
    -- with the very answer a sign-up gets, and writes nothing.
    perform set_config('request.jwt.claim.role', 'anon', true);
    perform set_config('request.jwt.claim.sub', '', true);
    t_ans := public.affiliate_referral_signup(t_code, 'Self ' || t_sfx, '442 Check', t_phones[2], null, null);
    if t_ans is distinct from c_known then
      raise exception '442: the self-test''s third try was answered %', t_ans; end if;
    t_ans := public.affiliate_referral_signup(t_code, '442 Check', 'Self ' || t_sfx, t_phones[2], null, null);
    if t_ans is distinct from c_too_many
       or (select count(*) from public.referral_signup_events e where e.normalized_phone = t_phones[2]) <> 3 then
      raise exception '442: the self-test''s fourth try on one phone was not refused by the phone''s limit: %', t_ans; end if;
    if exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = t_phones[2])
       or exists (select 1 from public.customers c where c.referred_by = t_cust) then
      raise exception '442: the self-test''s tries made a customer or a referral'; end if;

    -- Someone else: registered, referred; again: already registered, the
    -- same answer, word for word, as her tries got.
    t_ans := public.affiliate_referral_signup(t_code, 'Someone', 'Else ' || t_sfx, t_phones[3], null, null);
    if t_ans ->> 'outcome' is distinct from 'registered'
       or not exists (select 1 from public.customers c
                       where public.normalize_customer_phone(c.phone) = t_phones[3] and c.referred_by = t_cust) then
      raise exception '442: the self-test''s stranger was not registered: %', t_ans; end if;
    t_ans := public.affiliate_referral_signup(t_code, 'Someone', 'Else ' || t_sfx, t_phones[3], null, null);
    if t_ans is distinct from t_self then
      raise exception '442: someone already registered is told % and her try %: not the same', t_ans, t_self; end if;
    -- The stranger's details (on file) with her login's email: herself on
    -- details on file, answered as anyone on file is and never limited
    -- (the 3rd and 4th tries on that phone), each a 'self_known' event with
    -- its entry; with another email (the 5th): the same answer, a 'duplicate'.
    t_ans := public.affiliate_referral_signup(t_code, 'Someone', 'Else ' || t_sfx, t_phones[3], t_mail, null);
    if t_ans is distinct from c_known then
      raise exception '442: the self-test''s try on details on file was answered %', t_ans; end if;
    t_ans := public.affiliate_referral_signup(t_code, 'Someone', 'Else ' || t_sfx, t_phones[3], upper(t_mail), null);
    if t_ans is distinct from c_known then
      raise exception '442: the self-test''s try on details on file, past the phone''s 3 tries, was answered %', t_ans; end if;
    t_ans := public.affiliate_referral_signup(t_code, 'Someone', 'Else ' || t_sfx, t_phones[3],
                                              '442-check-2-' || t_sfx || '@example.invalid', null);
    if t_ans is distinct from c_known
       or (select count(*) from public.referral_signup_events e
            where e.normalized_phone = t_phones[3] and e.outcome = 'self_known' and e.referrer_customer_id = t_cust
              and e.new_customer_id is null) <> 2
       or (select count(*) from public.referral_signup_events e where e.normalized_phone = t_phones[3] and e.outcome = 'duplicate') <> 2
       or (select count(*) from public.audit_logs l
            where l.action = 'referral_self_signup_refused' and l.record_id = t_cust and l.new_data ->> 'phone' = t_phones[3]
              and l.new_data ->> 'outcome' = 'self_known' and l.new_data -> 'matched' = '["login_email"]'::jsonb) <> 2 then
      raise exception '442: the self-test''s tries on details on file were not answered and recorded as tested: %', t_ans; end if;
    -- A phone 3 customers have (three sign-ups through her link): her login's
    -- email under a name not on file there gets the very error a new sign-up
    -- gets, and so does another email; neither writes anything.
    for i in 1 .. 3 loop
      t_ans := public.affiliate_referral_signup(t_code, 'Fill' || chr(96 + i), 'Phone ' || t_sfx, t_phones[4], null, null);
      if t_ans ->> 'outcome' is distinct from 'registered' then
        raise exception '442: the self-test could not fill a phone: %', t_ans; end if;
    end loop;
    foreach v in array array[t_mail, '442-check-3-' || t_sfx || '@example.invalid'] loop
      begin
        t_ans := public.affiliate_referral_signup(t_code, 'Probe', 'Four ' || t_sfx, t_phones[4], v, null);
        t_err := t_err || ('answered ' || t_ans::text);
      exception when others then t_err := t_err || sqlerrm;
      end;
    end loop;
    if cardinality(t_err) <> 2 or t_err[1] is distinct from t_err[2] or t_err[1] not like 'CUSTOMER_PHONE_LIMIT:%'
       or (select count(*) from public.referral_signup_events e where e.normalized_phone = t_phones[4]) <> 3
       or exists (select 1 from public.audit_logs l
                   where l.action = 'referral_self_signup_refused' and l.new_data ->> 'phone' = t_phones[4]) then
      raise exception '442: on a phone 3 customers have, her try and another were not refused alike, writing nothing: %', t_err; end if;
    raise exception using errcode = 'P0442', message = '442: self-test done, undone';
  exception when sqlstate 'P0442' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
