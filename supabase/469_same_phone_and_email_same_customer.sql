-- 469_same_phone_and_email_same_customer.sql
--
-- THE SAME PHONE AND THE SAME EMAIL ARE THE SAME CUSTOMER: THE REFERRAL LINK,
-- THE AFFILIATE SIGN-UP AND THE SEMINAR WEBSITE MAKE NO SECOND RECORD (the
-- Owner, 24 Oct 2026)
--
-- WHAT WAS WRONG
--
--   Each of the three public forms finds a customer already on file by the
--   phone together with the NAME (as typed, or the same words: 432's
--   customer_names_match). Someone who typed their phone and their email
--   exactly as their record has them, but their name another way (an English
--   name for a Chinese one, a shorter name, a nickname), was not found:
--   * the referral link (/r/<code>, affiliate_referral_signup) made a second
--     customer, referred by the link's affiliate (425's phone_shared check);
--   * the affiliate sign-up (/affiliate/join, complete_affiliate_onboarding,
--     437) joined them only when theirs was the one record on the phone;
--     on a shared phone it made a fresh record, listed for staff;
--   * the seminar website (event_web_register / event_web_match_customer,
--     436) held them under To match ('phone_and_email_in_use') until staff
--     attached them.
--   Production, 24 Oct 2026 (read only; counts only): 2 of the 80 customers
--   the referral link made had an older customer with the same phone and
--   email inbox; 1 of the 5 fresh records affiliate sign-up made; and the 3
--   seminar registrations held 'phone_and_email_in_use' where exactly one
--   customer has both were all attached by staff to that customer.
--
-- THE RULES (the Owner, 24 Oct 2026)
--
--   The request, exactly: "Not only for the health survey but also for the
--   affiliate link, if both phone number and email are the same, the
--   customer should not duplicate, it should lead to the same customer."
--   The Owner's answers, the same day:
--   1. All three forms: the referral link /r/<code>; the affiliate sign-up
--      (Join; 466's check, which sends an EXISTING AFFILIATE to Sign in
--      before anything is made, stays as it is); the seminar website.
--   2. The referrer: "No, keep the current referrer rule". An existing
--      customer reached through a referral link is told they are already
--      registered; a public form never changes anyone's referrer (the first
--      valid referral wins).
--   3. Several customers sharing that phone AND that email: "No new record;
--      staff sort it". The referral link answers "already registered" (no
--      record made) with an Audit Log entry for staff; the affiliate sign-up
--      waits on a claim for staff (as 432 parked claims); the seminar
--      registration is held for staff (as today).
--   The Owner's answers to the review, later the same day:
--   4. The seminar website: a sign-up under ANOTHER name whose phone and
--      email are a customer's who is already on this event's guest list in
--      any way (a website sign-up, a guest staff added, a ticket guest from
--      an invoice, or a guest staff took off the list) is held for staff,
--      never linked into a second guest row. A sign-up under the same name
--      keeps today's rules.
--   5. Namesakes, one reading for the three forms and 468's QR health form:
--      two or more customers on the phone with the name typed, and exactly
--      one customer of ANOTHER name with the phone and the email: the
--      sign-up waits for staff (the referral link: no record made, its
--      answer for several, as before; the affiliate sign-up: a pending
--      claim; the seminar: a hold). One of the namesakes with the email and
--      a customer of another name with the phone and the email too: it waits
--      for staff too.
--   6. The referral link telling whether a phone and an email are on file
--      together (NOT COVERED, below): accepted by the Owner on 24 Oct 2026;
--      kept as documented.
--   How it reads (this file, 24 Oct 2026):
--   * "The same phone and the same email": a customer in use whose phone is
--     the phone typed, as each form already reads phones
--     (normalize_customer_phone; a stored 8-digit number that could be
--     Singapore or Malaysia counted where that form counts it), and whose
--     email is the email typed as 432 compares emails
--     (customer_email_match_key: trimmed, any case; a Gmail address with or
--     without dots or a +tag, or at googlemail.com, is one inbox). For the
--     affiliate sign-up the email is the login's (the address it signed up
--     with).
--   * It decides only where the name did not: a customer the name already
--     picks (as typed, or the same words) is picked as before, and an old
--     8-digit number with the name is still held or refused first, as
--     before. When the name picks SEVERAL customers on the phone (5, as 468
--     reads it for the QR health form, built the same day), every customer
--     with the phone and the email counts, not only the namesakes: exactly
--     one, and it is one of the namesakes, is the person; one of another
--     name, or several (a namesake among them or not), and the sign-up or
--     registration waits for staff; none, as before. On the referral link a
--     name several records have exactly stays refused as ambiguous, and one
--     several have in other words stays "already registered", as before
--     (nothing is made either way; the email is not looked at). A phone
--     alone, an email alone or a name alone are as before.
--   * Defaults where the answers leave a choice (each put to the Owner):
--     a. The referral link says "already registered" word for word in both
--        cases (one record or several): another answer would tell a stranger
--        that a phone and an email belong to several records.
--     b. The affiliate sign-up that waits for staff is told what a parked
--        claim was told before 437 ("We found an existing Energia customer
--        record that needs identity verification. Please contact Energia to
--        complete account linking."); the verify page already shows it
--        ("Identity verification needed").
--     c. The affiliate sign-up also waits for staff (no second affiliate
--        account on a fresh record) when the one customer with the phone and
--        the email already has a portal login, and when the only one has a
--        stored number that only could be it (437 never joins such a record
--        by itself). A customer an Owner unlinked a login from (378), one an
--        Owner or Manager rejected a claim for (379) and one whose affiliate
--        record was removed get a fresh record, listed for staff, as before:
--        an Owner or Manager has already decided about them.
--     d. The seminar website keeps today's hold for several
--        ('phone_and_email_in_use', with the same candidates): no new hold
--        reason, nothing new on To match.
--
-- WHAT THIS DOES
--
--   1. affiliate_referral_signup (the referral link): after the name (as
--      typed, then the same words) found nobody among the customers with
--      the phone (425's holders, an old 8-digit number that could be it
--      included), those of them whose email is the email typed count as on
--      file. One or more: the existing "already registered" answer, word for
--      word, with its event ('duplicate'; 442's 'self_known' with its Audit
--      Log entry when the referrer is among them or the sign-up matches her
--      login), never limited, nothing made or changed, no referral, no check:
--      exactly the path a phone with the same name takes. Several: also one
--      Audit Log entry on each of those records ('referral_signup_several_
--      records', module 'affiliate', with the matched records, the code,
--      the referrer, the phone, the name and email typed at most 200
--      characters each, and the signed-in login if any), written straight
--      into audit_logs as 442's entries are, best effort, at most once an
--      hour on each record (a try again within the hour gets the same
--      answer and its 'duplicate' event, and adds no entry: repeated tries
--      cannot bury the entries staff read).
--      442 reads "herself" from these too: the referrer's own record found
--      by her phone and email under another name is herself on details on
--      file ('self_known', answered at once, as 442 answers her record found
--      by its name), where before it went on to the limits (as 'self', or
--      a new customer on her phone listed for 425's check when her login's
--      details did not match).
--   2. complete_affiliate_onboarding (the affiliate sign-up): after 437's
--      picks (the one customer with the phone; else the name as typed, else
--      the same words), when they picked no one, the customers with the
--      phone or a stored number that could be it (437's holders and "maybe"
--      holders) whose email is the login's decide:
--        * exactly one, with the phone itself: joined (rule
--          'phone_and_email' in the audit row 'affiliate_portal_claimed'),
--          then the same safeguards as any join (a portal login, 378, 379, a
--          removed affiliate record);
--        * several, or one whose stored number only could be it: no record;
--          a pending claim (below);
--        (when the name matched several customers on the phone (5): the one
--        customer with the phone and the email is joined only when it is one
--        of them; one of another name, or several: a pending claim
--        suggesting no one, reason 'several_name_matches'; none: a fresh
--        record, listed, as before.)
--      And a customer 437 picked who already has a portal login, when that
--      customer has the phone and the email: a pending claim suggesting
--      them, not a fresh record. Protected (378, 379) and removed: a fresh
--      record, listed, as before.
--      The claim: one pending claim per login (affiliate_account_claims; the
--      one-pending index, on conflict nothing), suggesting the one customer
--      (none when several could be the person, as 432: on a shared phone
--      staff link only a suggested customer, 378), and the first time: the
--      login's sign-up
--      copy (440's affiliate_signup_identities: the name and phone this
--      sign-up used and the login's email, no account yet, source
--      'backfill', the shape 440's backfill gave a login with a pending
--      claim) and its Audit Log entry ('affiliate_claim_parked', as 432
--      wrote it, reason 'several_phone_and_email', 'several_name_matches',
--      'phone_unconfirmed_and_email' or 'customer_has_login', the customers
--      with the phone and the email and the namesakes, version 469); the
--      answer {status 'pending_verification',
--      message (b)}. A second sign-in answers the same and adds nothing.
--      Staff resolve, reject or delete it on the Affiliates page (Pending
--      claims) as any claim: those functions and their 378/379 checks are
--      not changed (staff link only the suggested customer on a shared
--      phone; an Owner or Manager links a claim that suggests no one); a
--      resolved claim's login is in at its next sign-in ("already"), and
--      its copy is then read by the no-self-referral checks (440, 442: her
--      Join name, her phone or her login email on her own link is herself)
--      as for any affiliate login.
--   3. event_web_match_customer (the seminar website, one decision point):
--      the records holding both the phone (event_web_phone_holders, an old
--      number that could be it included) and the email inbox, a record a
--      merge retired holding its phone and inbox for the record that kept it
--      (as 441 reads them). After the name found nobody (an old number with
--      the name is held first, as before): exactly one, holding both itself:
--      that customer, kind 'phone_and_email'; otherwise today's hold
--      ('phone_and_email_in_use' with today's candidates). When the name
--      found several (5): exactly one, holding both itself, and it is one of
--      them: that customer, kind 'phone_and_email'; otherwise today's hold
--      ('several_name_matches' with the namesakes; when several hold both,
--      with those too).
--      event_web_register links kind 'phone_and_email' as it links a name
--      match ('exact', 'same_words'): their email onto the record when it has
--      none and the seminar's source (event_web_fill_customer), the referral
--      through a link (event_web_apply_referral: an existing customer is
--      'already_customer', the affiliate herself 'self'; nobody's referrer is
--      changed), the free guest record; and a test key records it as what a
--      live key would have done. But a customer found by the phone and the
--      email who is already on this event's list in any way (4): a guest of
--      theirs on this event, whatever its source or state (a website
--      sign-up's, one staff added (event_save_guest), a ticket guest from an
--      invoice, one staff took off the list), or a sign-up of theirs for it
--      whatever its state (an earlier person in the same form too), is held
--      for staff: 'phone_and_email_in_use' with that customer, or, under a
--      name several customers on the phone have, 'several_name_matches' with
--      them (that sign-up's hold before 469). Never a second guest row; a
--      sign-up under another name does not put back someone staff took off
--      (449's "Hold for staff to decide"; 450's VIP gate stays); two people
--      in one form are two people. A test key sees this event's guests as a
--      live key does. event_registration_people.match may now be
--      'phone_and_email' (its check constraint, otherwise the same).
--   The Event page (src/components/events/model.ts, testOutcomeText) says
--   it for a test key: "A live key would have linked to the customer with
--   this phone and email address." Nothing else on any page changes.
--
-- WHAT THE PERSON SEES (user-facing)
--
--   * Referral link: the "already registered" message (as for a phone with
--     their name) where before they were registered as a new customer.
--   * Affiliate sign-up: the dashboard of their record (one customer), or
--     "Identity verification needed" (several; a portal login already on
--     their record; an old 8-digit number; a name several customers on the
--     phone have, with another's email) where before they went straight in
--     on a fresh record.
--   * Seminar website: nothing different (the answer never says who was
--     matched); staff no longer find them under To match, unless that
--     customer is already on this event's list (held, as before).
--
-- NOT CHANGED
--
--   * The name rules and their order (customer_phone_name_matches,
--     require_resolved_customer_identity, customer_names_match), how phones
--     and emails are read (normalize_customer_phone, inspect_customer_phone,
--     customer_email_match_key, event_web_phone_holders): pinned below.
--   * 466 (affiliate_signup_existing and the sign-up function): an existing
--     affiliate is still sent to Sign in before anything is made.
--   * The referral rules: the referrer is never changed from a public form;
--     the phone's 10-minute limit, the link's hour limit and the phone's 3
--     customers count as before (an "already registered" answer is never
--     limited, as before); 442's self-refusal and its Audit Log entries.
--   * 436/439/440/442's seminar referral rules (event_web_apply_referral,
--     event_web_check_self_referral, event_web_new_customer); To match, its
--     holds, Attach, Make a customer and Close.
--   * The claim functions (Pending claims, Resolve, Reject, Delete, the link
--     check, Unlink), 437's list of fresh records and Link.
--   * submit_health_survey and the QR health form's holds (468's, built at
--     the same time) and the credit functions (462/463, applied after 466
--     on 24 Oct 2026): not read or changed. No function is added.
--   * Grants: each changed function keeps its own (the referral sign-up: the
--     anon key's; the affiliate sign-up: signed-in logins'; the seminar
--     functions: the service role's alone).
--   * The edge functions (event-website, auth-signup-request) and the
--     seminar website: contract.md5 c120786884a6ca208881acc90a339996 stays.
--
-- NOT COVERED (told to the Owner)
--
--   * Someone who types another person's phone and email (both on that
--     person's record) under any name is now that person: on the referral
--     link "already registered" (as a name match was), on the seminar
--     website registered on that person's record (436 already lets the
--     email reach the person's registration), on the affiliate sign-up
--     joined to that record when it is the only one with the phone (437's
--     rule 7 already joins on the phone alone) or, on a shared phone, now
--     joined by the email too (the email is not verified first: 437's NOT
--     COVERED).
--   * The referral link now also tells anyone who has a link whether an
--     email is on a customer with a given phone, as it already tells for a
--     name: a right email (any name typed; Gmail spellings folded) is
--     "already registered", a wrong one is "registered" (a customer made)
--     or, past the phone's limit or its 3 customers, "Too many registration
--     attempts" / CUSTOMER_PHONE_LIMIT. As 425 and 442 have it, "already
--     registered" is never limited and a refused try writes nothing (the
--     phone's 10-minute limit can be filled with a made-up code without
--     making a customer), so the check can be repeated without end at no
--     cost; each right guess leaves only a 'duplicate' event. Hiding it
--     (e.g. counting 'duplicate' answers per phone and then giving the
--     limit message) would change 425/442's "never limited" rule for name
--     matches too. The Owner accepted this on 24 Oct 2026 (6): it stays as
--     documented here.
--   * A household that shares one phone AND one email (production, 24 Oct
--     2026: 6 such groups of 2 customers, 12 customers, the phone as read
--     and the email inbox) cannot be told apart by these forms: each try
--     waits for staff (affiliate sign-up), is held (seminar) or is "already
--     registered" with an entry for staff (referral link). Staff give each
--     person their own email, or merge.
--   * Namesakes (5): production on 24 Oct 2026 has 2 phones with two
--     customers of one name, and on neither a customer of another name with
--     any email: 5 changes nothing there today.
--   * The affiliate sign-up that waits on a claim does not get in until
--     staff act; if staff delete the claim, the next sign-in parks it again
--     (the same details, and one more sign-up copy with it); a rejected
--     claim stays "unsuccessful" (as before). Until staff resolve it the
--     login has no affiliate account, so no link of her own to refer
--     herself through.
--   * An email typed differently but not as the same Gmail inbox (another
--     domain, a typo) is another email: as before.
--   * The seminar's "already registered for this event" (449's same phone and
--     same name) is not changed, and a sign-up whose name picks one customer
--     keeps 449's rules (4: a sign-up under the same name keeps today's
--     rules): when that
--     customer is on the list only as a guest staff added or a ticket guest,
--     it is linked and given a second (website) guest row, and one staff
--     took off is put back that way, as before 469. Someone found by the
--     phone and the email whose customer is on the list in any way is held
--     for staff (WHAT THIS DOES 3). A test key sees this event's guests as
--     a live key does, but not its own earlier test sign-ups (test rows have
--     no customer and no guest; 449's check, too, sees test rows alone), so
--     a second test sign-up of one person under another name reports a link.
--     One whose earlier sign-up for the event is itself still held (no
--     customer on it yet) is linked by a later sign-up under another name:
--     staff see the earlier hold, as for any hold.
--   * A record whose phone could not be read at all (not 8 digits) has no
--     phone for these forms: as before.
--   * A household member with no record of their own who types the
--     household's shared phone and shared email (both on a relative's
--     record) under their own name is now that relative on all three forms
--     (the rule as asked); one with a record of their own under their name is
--     found by the name first, as before.
--   * A claim for a customer who already has a portal login cannot be
--     resolved to that customer (one login each, as before): staff tell the
--     person to sign in with that login (Reset password if needed), then
--     delete or reject the claim; or an Owner unlinks the other login first
--     (378).
--   * Self-referral on the seminar website is decided as before
--     (event_web_check_self_referral): linked to the affiliate's own record
--     by her phone and email, she is herself ('self').
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the four functions are each production's version of 24 Oct 2026
--     (BEFORE: patched, each anchor found exactly once, the text built having
--     the tested md5) or already this file's (AFTER: left alone); anything
--     else is refused;
--   * the functions they rely on and do not change are as read on 24 Oct
--     2026; the columns read and written (event_guests' event and customer
--     among them), the one-pending-claim index,
--     440's sign-up copy table (its check constraints, and no unique index
--     but its key: one copy per claim parked) and event_registration_people's
--     match check are as read (the check: as read, or already this file's);
--   * afterwards each function has its AFTER md5 and its own grants, and the
--     check allows exactly this file's values.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0469, so it leaves no row): made-up customers ("469 Check ...",
--   @example.invalid, fictional phones no customer uses) on each form: one
--   record with the phone and the email under another name (no new customer;
--   the referral link says "already registered" and changes no referrer; the
--   affiliate sign-up joins it; the seminar links it, 'already_customer'
--   through the link); two such records (the referral link, twice: the same
--   answer and one entry on each, not two; the affiliate sign-up: one
--   pending claim with one sign-up copy, the same answer again); the phone
--   alone with another email (the referral link still makes a customer,
--   phone_shared); the name of two customers on a phone with the email of a
--   third of another name (the affiliate sign-up waits on a claim
--   suggesting no one; the seminar holds it 'several_name_matches' with the
--   two); the seminar again under another name with the linked customer's
--   phone and email, and under another name with the phone and email of a
--   customer staff added to the list (each held, 'phone_and_email_in_use',
--   no second guest on the record). Only one sequence moves on:
--   affiliate_whatsapp_outbox_id_seq, by one each run (394's welcome
--   WhatsApp trigger on the made-up affiliate account; a sequence is never
--   rolled back: a gap in the outbox's ids, nothing sent, no row left; the
--   self-test runs on every run, as 466's does). A second run changes
--   nothing else ("already this version; left alone" for each). Locks:
--   event_registration_people for the check's swap (ACCESS EXCLUSIVE while
--   its rows, 7 in production on 24 Oct 2026, are validated; the 5 s lock
--   timeout makes it wait at most that, then fail with nothing changed).
--
-- DEPLOY ORDER (each with the Owner's go-ahead)
--
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below (or the one worked out
--      then, when 468 or anything else is in first: 468 touches none of these
--      functions), the second says "already this version; left alone" for
--      each and changes nothing.
--   2. Apply 469 (the CLI, or the MCP's apply_migration with this text
--      verbatim). No edge function is deployed; the seminar website is not
--      changed.
--   3. Deploy the pages (Vercel: the Event page's test-key wording only).
--      Before 3, a test key's row reads "A live key would have
--      phone_and_email."; nothing else waits on it.
--
-- BEFORE (production, 24 Oct 2026: head 20261024102018, 463 (462 and 463
-- went in after 466 that day and change none of what this file reads); md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   affiliate_referral_signup(text,text,text,text,text,text)        c76573912de0a4ded29e81e5c56c96d3  (442's)
--   complete_affiliate_onboarding(text,text,text,boolean)           43084deab54968eacaf1793c470fd08f  (440's)
--   event_web_match_customer(text,text,text)                        9da726006d8055983491b5ec1da1679b  (441's)
--   event_web_register(uuid,jsonb)                                  3aad1ad2a8a91732d330b2ef149bf969  (450's)
--   event_registration_people_match_check                           exact, same_words, new_customer, held,
--                                                                   staff_attached, staff_created, closed, test
--   relied on, not changed: listed in the guard below (normalize_customer_phone
--   b2bfac91..., customer_email_match_key be468815..., customer_names_match
--   ef1af52e..., event_web_phone_holders 614602e9..., and the rest)
--   public function fingerprint, production now (463)              6d96407cdeb903712a2d7be7016aa9a6 (1387 functions)
--     (at 466, before 462 and 463: 41a2fcab90c95090a71c688d7f0a17cd, 1381)
--   (all re-read on production after 462 and 463, 24 Oct 2026: as above; 462
--   changed merge_customer_records (2e0c9852... -> ba05c2b1...), which this file
--   does not read or pin; its test merges records through it)
-- AFTER (for later guards)
--   affiliate_referral_signup(text,text,text,text,text,text)        2942e3d4d0e8c76600c3e0ad5e15cc2b
--   complete_affiliate_onboarding(text,text,text,boolean)           1b9dfc819b860dcb19244063a4628f47
--   event_web_match_customer(text,text,text)                        63bfaf4520406af9f67d3d81c3342baf
--   event_web_register(uuid,jsonb)                                  c188a2dc82b9eb08fc9d01f1e5c15e13
--   event_registration_people_match_check                           the same with phone_and_email after same_words
--   public function fingerprint, worked out on a copy of production (24 Oct 2026):
--     production now (463) -> 469                                   5c7bbfd706187129f2b3bfc210dd431b (1387)
--     (at 466, before 462 and 463: 41a2fcab... -> 4d6167fd8b5a9f71875f8c5eedb21ed7, 1381)
--     (production now with 468's file of 24 Oct 2026 (md5 8cd878ba95584bd0f064c4d2a37739b4), in
--     either order: f9d0ddcb2dceb08fd4ba502d8487f0bf, 1387)
--   (Nothing of 462/463 (credit) or 468 (the QR health form) is read or
--   changed here, and this file adds no function: whichever goes first, the
--   others' guards are unaffected; the fingerprint is then worked out again.)
--
-- Test: scripts/affiliate-signup/tests/phone-and-email-469.sql (begin ...
-- rollback; it installs this file twice, or with -v skip_install=1 where it
-- is in). Earlier suites accept 469's AFTER md5s where they pin these
-- functions (run them with skip_install / nomig where their file is in).
-- 449's file, run again after this one, refuses (it checks the match check
-- as it read it): run its suite with -v skip_install=1.

set lock_timeout = '5s';

do $mig$
declare
  c_sigs constant text[] := array[
    'affiliate_referral_signup(text,text,text,text,text,text)',
    'complete_affiliate_onboarding(text,text,text,boolean)',
    'event_web_match_customer(text,text,text)',
    'event_web_register(uuid,jsonb)'];
  c_before constant text[] := array[
    'c76573912de0a4ded29e81e5c56c96d3', '43084deab54968eacaf1793c470fd08f',
    '9da726006d8055983491b5ec1da1679b', '3aad1ad2a8a91732d330b2ef149bf969'];
  c_after constant text[] := array[
    '2942e3d4d0e8c76600c3e0ad5e15cc2b', '1b9dfc819b860dcb19244063a4628f47',
    '63bfaf4520406af9f67d3d81c3342baf', 'c188a2dc82b9eb08fc9d01f1e5c15e13'];
  -- Who may call each (kept as it is): the referral page with the anon key,
  -- the affiliate sign-up signed in, the seminar functions the service role alone.
  c_anon constant boolean[] := array[true, false, false, false];
  c_auth constant boolean[] := array[true, true, false, false];
  -- Which function each anchor is in.
  c_fn constant int[] := array[1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4];
  c_anchor constant text[] := array[
$a01$  v_self text[];  -- 442: what in the sign-up is the referrer herself (440's rule), if anything
begin
$a01$,
$a02$     where c.id = any (v_holders) and public.customer_names_match(c.full_name, v_name);
  end if;
$a02$,
$a03$      exception when others then null;
      end;
    end if;
    return jsonb_build_object('ok', true, 'outcome', 'already_registered',
      'message', 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.');
  end if;

  if (select used from public.customer_phone_capacity where phone=v_norm) >= 3 then
$a03$,
$a04$  v_claims int := 0; v_match uuid; v_verified timestamptz;
begin
$a04$,
$a05$    v_reason := 'phone_unconfirmed';
  end if;

$a05$,
$a06$    if v_reason is not null then v_target := null; v_rule := null; end if;
  end if;

  if v_target is not null then
    v_cust := v_target;
  else
$a06$,
$a07$  v_merged_phone uuid[]; v_merged_mail uuid[];
begin
$a07$,
$a08$  if cardinality(v_matches) > 1 then
    return jsonb_build_object('kind', 'held', 'hold_reason', 'several_name_matches', 'candidates', to_jsonb(v_matches));
  end if;
$a08$,
$a09$    from k
   where k.kept is not null;
$a09$,
$a10$    v_m := public.event_web_match_customer(p.phone_norm, p.full_name, p.email);
$a10$,
$a11$                 or (r.referral_state = 'link_off' and v_m->>'kind' in ('exact', 'same_words')
$a11$,
$a12$                and public.event_web_check_self_referral(p.id, case when v_m->>'kind' in ('exact', 'same_words')
$a12$,
$a13$      if v_m->>'kind' in ('exact', 'same_words') then
        perform public.event_web_fill_customer((v_m->>'customer_id')::uuid, p.id);
$a13$];
  c_patch constant text[] := array[
$p01$  v_self text[];  -- 442: what in the sign-up is the referrer herself (440's rule), if anything
  v_by_email boolean := false;  -- 469: those on file were found by the phone and the email
begin
$p01$,
$p02$     where c.id = any (v_holders) and public.customer_names_match(c.full_name, v_name);
  end if;
  -- 469 (the Owner, 24 Oct 2026: "if both phone number and email are the
  -- same, the customer should not duplicate, it should lead to the same
  -- customer"): nobody with this phone has the name, as typed or in the same
  -- words. A customer with this phone (v_holders: one whose 8-digit number
  -- could be it too, as above) whose email is the email typed
  -- (customer_email_match_key: a Gmail inbox however it is written) is the
  -- person, whatever the name: "already registered", below, exactly as for
  -- the name (the referrer is never changed). Several such records: the same
  -- answer, and an Audit Log entry on each for staff (below). No email typed,
  -- or no one with this phone has it: as before.
  if cardinality(v_matches) = 0 and public.customer_email_match_key(v_email) is not null then
    select coalesce(array_agg(c.id order by c.created_at, c.id), '{}'::uuid[]) into v_matches
      from public.customers c
     where c.id = any (v_holders)
       and public.customer_email_match_key(c.email) = public.customer_email_match_key(v_email);
    v_by_email := cardinality(v_matches) > 0;
  end if;
$p02$,
$p03$      exception when others then null;
      end;
    end if;
    -- 469: several records have this phone and the email typed, so nobody
    -- can tell which one is the person: the same answer, nothing made or
    -- changed, and on each record an Audit Log entry for staff to sort out
    -- (merge them, or put each one's own email on it), at most once an hour
    -- on each record: a try again within the hour (the same answer; its
    -- event, above, counts every try) adds no entry. Written straight into
    -- audit_logs, as the entry above; best effort: it never changes the
    -- answer.
    if v_by_email and cardinality(v_matches) > 1 then
      begin
        insert into public.audit_logs(table_name, record_id, action, new_data, changed_by, actor_role, module)
        select 'customers', m.id, 'referral_signup_several_records',
               jsonb_build_object('referral_code', btrim(p_code), 'source', 'affiliate_link',
                                  'outcome', case when cardinality(v_self) > 0 then 'self_known' else 'duplicate' end,
                                  'matched', 'phone_and_email', 'customer_ids', to_jsonb(v_matches),
                                  'referrer_customer_id', v_ref_cust, 'phone', v_norm, 'name', left(v_name, 200),
                                  'email', left(v_email, 200), 'signed_in_login', auth.uid(), 'version', 469),
               (select p.id from public.profiles p where p.id = auth.uid()),
               public.current_user_role()::text, 'affiliate'
          from unnest(v_matches) as m(id)
         where not exists (select 1 from public.audit_logs l
                            where l.record_id = m.id and l.action = 'referral_signup_several_records'
                              and l.created_at > now() - interval '1 hour');
      exception when others then null;
      end;
    end if;
    return jsonb_build_object('ok', true, 'outcome', 'already_registered',
      'message', 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.');
  end if;

  if (select used from public.customer_phone_capacity where phone=v_norm) >= 3 then
$p03$,
$p04$  v_claims int := 0; v_match uuid; v_verified timestamptz;
  -- 469: the customers with the phone (or a stored number that could be it)
  -- and the login's email inbox; why the sign-up waits for staff instead of
  -- getting an account, whom the claim suggests, and the claim parked.
  v_pe uuid[] := '{}'::uuid[]; v_park text; v_suggest uuid; v_claim uuid;
begin
$p04$,
$p05$    v_reason := 'phone_unconfirmed';
  end if;

  -- 469 (the Owner, 24 Oct 2026: "if both phone number and email are the
  -- same, the customer should not duplicate, it should lead to the same
  -- customer"): when the phone and the name picked no one (above), the
  -- customers with the phone, or a stored number that could be it, whose
  -- email is the login's (customer_email_match_key: a Gmail inbox however it
  -- is written) decide. Exactly one, with the phone itself: joined (rule
  -- 'phone_and_email'), with the safeguards below as for any join. Several,
  -- or one whose stored number only could be it (never joined by itself, as
  -- above): no fresh record; the sign-up waits on a claim for staff (below).
  -- When the name matched SEVERAL customers on the phone (the Owner, later
  -- the same day: as 468 reads it for the QR health form), all the customers
  -- with the phone and the email count, not only those: exactly one, and it
  -- is one of the namesakes: joined to it; one of another name, or several
  -- (a namesake among them or not): no fresh record, the sign-up waits on a
  -- claim for staff suggesting no one (reason 'several_name_matches'); none:
  -- as before (a fresh record, listed). No email match: as before.
  if public.customer_email_match_key(v_email) is not null and cardinality(v_holders || v_maybe) > 0 then
    select coalesce(array_agg(c.id order by c.created_at, c.id), '{}'::uuid[]) into v_pe
      from public.customers c
     where c.id = any (v_holders || v_maybe)
       and public.customer_email_match_key(c.email) = public.customer_email_match_key(v_email);
  end if;
  if v_target is null and cardinality(v_pe) = 1 and v_pe[1] = any (v_holders)
     and (coalesce(cardinality(v_named), 0) <= 1 or v_pe[1] = any (v_named)) then
    v_target := v_pe[1]; v_rule := 'phone_and_email';
  elsif v_target is null and cardinality(v_pe) > 0 then
    v_park := case when coalesce(cardinality(v_named), 0) > 1 then 'several_name_matches'
                   when cardinality(v_pe) > 1 then 'several_phone_and_email'
                   else 'phone_unconfirmed_and_email' end;
    v_suggest := case when cardinality(v_pe) = 1 and coalesce(cardinality(v_named), 0) <= 1 then v_pe[1] end;
  end if;

$p05$,
$p06$    -- 469: a customer with a portal login who has this phone and this email
    -- is the person signing up again (466 sends most of them to Sign in
    -- first): not a second affiliate account on a fresh record, but a claim
    -- for staff (below), suggesting them. A protected customer (378, 379) or
    -- one whose affiliate record was removed: a fresh record, listed, as
    -- before (an Owner or Manager has already decided about them).
    if v_reason = 'customer_has_login' and v_target = any (v_pe) then
      v_park := 'customer_has_login'; v_suggest := v_target;
    end if;
    if v_reason is not null then v_target := null; v_rule := null; end if;
  end if;

  -- 469: waits for staff, nothing made: a pending claim of this login (one
  -- at a time: a second sign-in finds it and answers the same) suggesting
  -- the one customer (none when several could be the person, as 432: on a
  -- shared phone staff link only a suggested customer, 378; an Owner or
  -- Manager links one that suggests no one), and the first time the login's
  -- sign-up copy (440's, below) and an Audit Log entry
  -- ('affiliate_claim_parked', 432's), written straight into audit_logs
  -- with no one signed in recorded. The verify page shows "Identity
  -- verification needed"; on the Affiliates page staff resolve, reject or
  -- delete it as any claim (378 and 379 unchanged).
  if v_park is not null then
    insert into public.affiliate_account_claims (auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
      values (v_uid, v_phone, v_email, v_suggest, v_name)
      on conflict do nothing
      returning id into v_claim;
    if v_claim is not null then
      -- 440's copy of what this login signed up with (the name and phone
      -- this sign-up used, the login's email), as 440 copied a pending
      -- claim's login: no account yet (source 'backfill'). Once staff
      -- resolve the claim the login has an account on that record, and the
      -- no-self-referral checks read this copy (affiliate_login_signup_details),
      -- as for any affiliate login. One with each claim parked.
      insert into public.affiliate_signup_identities (auth_user_id, affiliate_account_id, customer_id, first_name, last_name,
          full_name, phone, email, source, name_from, phone_from)
        values (v_uid, null, null, v_first, v_last, v_name, v_raw_phone, v_email, 'backfill',
          case when nullif(btrim(coalesce(p_first_name, '')), '') is null and nullif(btrim(coalesce(p_last_name, '')), '') is null
               then 'user_metadata' else 'arguments' end,
          case when nullif(btrim(coalesce(p_phone, '')), '') is null then 'user_metadata' else 'arguments' end);
      begin
        insert into public.audit_logs (table_name, record_id, action, new_data, module)
        values ('affiliate_account_claims', v_claim, 'affiliate_claim_parked',
          jsonb_build_object('auth_user_id', v_uid, 'candidate_customer_id', v_suggest, 'reason', v_park,
            'phone_and_email_customers', to_jsonb(v_pe), 'name_matches', to_jsonb(coalesce(v_named, '{}'::uuid[])),
            'phone_holders', cardinality(v_holders),
            'phone_unconfirmed_holders', cardinality(v_maybe), 'version', 469),
          'affiliate');
      exception when others then
        raise warning '469: the parked claim''s audit row was not saved: %', sqlerrm;
      end;
    end if;
    return jsonb_build_object('status', 'pending_verification',
      'message', 'We found an existing Energia customer record that needs identity verification. Please contact Energia to complete account linking.');
  end if;

  if v_target is not null then
    v_cust := v_target;
  else
$p06$,
$p07$  v_merged_phone uuid[]; v_merged_mail uuid[];
  v_both uuid[];  -- 469: the customers with the phone and the email inbox
begin
$p07$,
$p08$  -- 469: the name matched several customers on the phone: decided below,
  -- once the records with the phone and the email inbox are known (held
  -- 'several_name_matches' as before, unless the email picks one of them).
$p08$,
$p09$    from k
   where k.kept is not null;
  -- 469 (the Owner, 24 Oct 2026: "if both phone number and email are the
  -- same, the customer should not duplicate, it should lead to the same
  -- customer"): the records that hold both the phone (event_web_phone_holders:
  -- an old number that could be it included) and the email inbox. First the
  -- live records holding both themselves; when exactly one does, a
  -- merged-away record's phone or inbox counts as held by the record that
  -- kept it (441, just above): another record may hold both through one. (A
  -- merged-away record is followed only then, when it can change the
  -- answer: following one reads the Audit Log, 441's P.)
  v_both := array(select x from unnest(v_holders) x where x = any (v_email_holders));
  if cardinality(v_both) = 1 and cardinality(v_merged_phone) + cardinality(v_merged_mail) > 0 then
    v_both := array(select distinct h.id
                      from unnest(v_holders || array(select public.event_web_kept_customer(x) from unnest(v_merged_phone) x)) h(id)
                     where h.id = any (v_email_holders || array(select public.event_web_kept_customer(x) from unnest(v_merged_mail) x)));
  end if;
  -- The name matched several customers on the phone (the Owner, later the
  -- same day: as 468 reads it for the QR health form): exactly one record
  -- holds both (then it holds them itself, above) and it is one of those:
  -- that customer (kind 'phone_and_email', the namesakes with it for
  -- event_web_register). Otherwise held as before ('several_name_matches',
  -- the namesakes the candidates): one of another name holds both, or
  -- several do (a namesake among them or not; then they are candidates too).
  if cardinality(v_matches) > 1 then
    if cardinality(v_both) = 1 and v_both[1] = any (v_matches) then
      return jsonb_build_object('kind', 'phone_and_email', 'customer_id', v_both[1], 'name_matches', to_jsonb(v_matches));
    end if;
    return jsonb_build_object('kind', 'held', 'hold_reason', 'several_name_matches',
      'candidates', to_jsonb(v_matches || case when cardinality(v_both) > 1
                                               then array(select b from unnest(v_both) b where b <> all (v_matches) order by b)
                                               else '{}'::uuid[] end));
  end if;
  -- No live record has the phone with the name (above): exactly one record
  -- holds both (then it holds them itself): that customer, whatever the name
  -- (kind 'phone_and_email', linked as a name match is). Otherwise held for
  -- staff, as before ('phone_and_email_in_use' when several, below).
  if cardinality(v_both) = 1 then
    return jsonb_build_object('kind', 'phone_and_email', 'customer_id', v_both[1]);
  end if;
$p09$,
$p10$    v_m := public.event_web_match_customer(p.phone_norm, p.full_name, p.email);
    -- 469 (the Owner, 24 Oct 2026): found by the phone and the email (the
    -- name picked no one, or several), but that customer is already on this
    -- event's list in any way: a guest of theirs on this event, whatever its
    -- source or state (a website sign-up's, one staff added, a ticket guest
    -- from an invoice, one staff took off the list), or a sign-up of theirs
    -- for it (whatever its state; an earlier person in this form too): held
    -- for staff, never linked into a second guest row. Under another name:
    -- 'phone_and_email_in_use', that customer the candidate; under a name
    -- several customers on the phone have: 'several_name_matches', those the
    -- candidates (that sign-up's hold before 469). A sign-up does not put
    -- back someone staff took off (449), and two people in one form are two
    -- people. A sign-up whose name picks one customer keeps 449's rules. A
    -- test key sees this event's guests as a live key does (its own earlier
    -- test sign-ups have no customer: not those).
    if v_m->>'kind' = 'phone_and_email' and (
         exists (select 1 from public.event_guests g
                  where g.event_id = e.id and g.customer_id = (v_m->>'customer_id')::uuid)
         or exists (select 1 from public.event_registration_people p3
                     where p3.event_id = e.id and p3.is_test = v_test and p3.id <> p.id
                       and p3.customer_id = (v_m->>'customer_id')::uuid)) then
      v_m := case when v_m ? 'name_matches'
                  then jsonb_build_object('kind', 'held', 'hold_reason', 'several_name_matches', 'candidates', v_m->'name_matches')
                  else jsonb_build_object('kind', 'held', 'hold_reason', 'phone_and_email_in_use',
                                          'candidates', jsonb_build_array(v_m->'customer_id')) end;
    end if;
$p10$,
$p11$                 or (r.referral_state = 'link_off' and v_m->>'kind' in ('exact', 'same_words', 'phone_and_email')
$p11$,
$p12$                and public.event_web_check_self_referral(p.id, case when v_m->>'kind' in ('exact', 'same_words', 'phone_and_email')
$p12$,
$p13$      -- 469: found by the phone and the email ('phone_and_email'): linked as
      -- a name match is (the referral rules alike).
      if v_m->>'kind' in ('exact', 'same_words', 'phone_and_email') then
        perform public.event_web_fill_customer((v_m->>'customer_id')::uuid, p.id);
$p13$];
  c_con_before constant text := 'CHECK ((match = ANY (ARRAY[''exact''::text, ''same_words''::text, ''new_customer''::text, ''held''::text, ''staff_attached''::text, ''staff_created''::text, ''closed''::text, ''test''::text])))';
  c_con_after constant text := 'CHECK ((match = ANY (ARRAY[''exact''::text, ''same_words''::text, ''phone_and_email''::text, ''new_customer''::text, ''held''::text, ''staff_attached''::text, ''staff_created''::text, ''closed''::text, ''test''::text])))';
  c_known constant jsonb := jsonb_build_object('ok', true, 'outcome', 'already_registered',
    'message', 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.');
  c_pending constant jsonb := jsonb_build_object('status', 'pending_verification',
    'message', 'We found an existing Energia customer record that needs identity verification. Please contact Energia to complete account linking.');

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; k int; i int; v_con text;
  v_texts text[] := array[null, null, null, null]::text[];
  v_acls text[] := array[null, null, null, null]::text[];
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_code text; t_ref uuid; t_h1 uuid; t_h2 uuid; t_mail text; t_ans jsonb;
  t_u1 uuid; t_u2 uuid; t_j1 uuid; t_j2 uuid; t_k1 uuid; t_k2 uuid;
  t_owner uuid; t_store uuid; t_event uuid; t_live text; t_hash text; t_s1 uuid; t_s2 uuid; t_p1 uuid; t_p2 uuid;
  t_u3 uuid; t_n1 uuid; t_n2 uuid; t_g1 uuid;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 24 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is changed unless all pass ─────────────────────────
  -- What it relies on and does not change: as production had it on 24 Oct 2026 (466; 462 and 463 change none of them).
  for r in select * from (values
      ('normalize_customer_phone(text)', 'b2bfac910e0c9eff402ba44e19750bee'),
      ('inspect_customer_phone(text,text)', '6672c4d1963996f3b601896f4a55916e'),
      ('customer_email_match_key(text)', 'be468815c9626fff1728e2cfcd484b66'),
      ('customer_names_match(text,text)', 'ef1af52e4888cefb6037a2291f4e011d'),
      ('normalize_customer_match_name(text)', '0572764712e179dc606c66f9f3dbaa03'),
      ('customer_phone_name_matches(text,text)', '1bdf8322972b6671b7cbb08bc8211f8a'),
      ('require_resolved_customer_identity(text,text)', '5bde1a418363442ec27e2944442f5874'),
      ('current_user_role()', '519b0a33a3548f970c5d585b6e76a389'),
      ('affiliate_login_signup_details(uuid)', '71e6d6f9ab2b474450b5c00f60f14bb4'),
      ('affiliate_calendar_label(text)', 'af4eecdcf978c19b3effb6af3a897165'),
      ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
      ('affiliate_signup_candidates(uuid,text,text,text)', 'a9233b065de981e00e76143c0aa94ac7'),
      ('generate_affiliate_referral_code()', '29ae3d463f13788ccf88a952eb3e70b8'),
      ('affiliate_session_from_email_link()', 'd0f5ab3b19eecc6211262821bcbee600'),
      ('affiliate_signup_existing(text,text,text,uuid)', '27e3b1ad5a583bc6421d783b5a7db45a'),
      ('affiliate_claim_link_check(uuid,uuid)', '251b1bd9f7175301750d65be4dd01b0e'),
      ('resolve_affiliate_account_claim(uuid,uuid,text)', '29a68a4d2282995f367b715089736c6c'),
      ('event_web_phone_holders(text)', '614602e9cbc483d79bdef7d60aaf6a33'),
      ('event_web_kept_customer(uuid)', 'cb0720c1088df9209da45e46b91601f4'),
      ('event_web_fill_customer(uuid,uuid)', '89488f15e0b030b9ed14c3c31049a71e'),
      ('event_web_apply_referral(uuid,uuid)', 'b034075f9882cb4221e3a554e6453317'),
      ('event_web_check_self_referral(uuid,uuid)', '2a5ab36c3d878197c21221a9a1ff193f'),
      ('event_web_new_customer(uuid)', 'a253f76a9db721212a9c110bc41ff483'),
      ('event_web_add_free_guest(uuid)', '5bef6d09015c0d5fe33bbb470b885fc8'),
      ('event_web_call(text,uuid,text,jsonb)', 'e114ba39de4923cc52ed426e27d9bfde')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '469: public.% is missing or not the version this was tested against (production, 24 Oct 2026). Re-read it and re-test before applying.', r.fn;
    end if;
  end loop;

  -- The columns 469 reads and writes, as read on 24 Oct 2026.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values
      ('public.customers', 'id uuid'), ('public.customers', 'phone text'), ('public.customers', 'email text'),
      ('public.customers', 'full_name text'), ('public.customers', 'created_at timestamp with time zone'),
      ('public.customers', 'deleted_at timestamp with time zone'), ('public.customers', 'referred_by uuid'),
      ('public.affiliate_account_claims', 'id uuid'), ('public.affiliate_account_claims', 'auth_user_id uuid'),
      ('public.affiliate_account_claims', 'entered_phone text'), ('public.affiliate_account_claims', 'verified_email text'),
      ('public.affiliate_account_claims', 'candidate_customer_id uuid'), ('public.affiliate_account_claims', 'entered_name text'),
      ('public.affiliate_account_claims', 'status text'),
      ('public.audit_logs', 'table_name text'), ('public.audit_logs', 'record_id uuid'), ('public.audit_logs', 'action text'),
      ('public.audit_logs', 'new_data jsonb'), ('public.audit_logs', 'changed_by uuid'), ('public.audit_logs', 'actor_role text'),
      ('public.audit_logs', 'module text'), ('public.audit_logs', 'created_at timestamp with time zone'),
      ('public.affiliate_signup_identities', 'auth_user_id uuid'), ('public.affiliate_signup_identities', 'affiliate_account_id uuid'),
      ('public.affiliate_signup_identities', 'customer_id uuid'), ('public.affiliate_signup_identities', 'first_name text'),
      ('public.affiliate_signup_identities', 'last_name text'), ('public.affiliate_signup_identities', 'full_name text'),
      ('public.affiliate_signup_identities', 'phone text'), ('public.affiliate_signup_identities', 'email text'),
      ('public.affiliate_signup_identities', 'source text'), ('public.affiliate_signup_identities', 'name_from text'),
      ('public.affiliate_signup_identities', 'phone_from text'),
      ('public.event_registration_people', 'id uuid'), ('public.event_registration_people', 'event_id uuid'),
      ('public.event_registration_people', 'is_test boolean'),
      ('public.event_registration_people', 'match text'), ('public.event_registration_people', 'customer_id uuid'),
      ('public.event_guests', 'event_id uuid'), ('public.event_guests', 'customer_id uuid')) x(t, c)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass(x.t) and a.attnum > 0 and not a.attisdropped
                        and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.c);
  if v is not null then
    raise exception '469: these columns are missing or not as read on 24 Oct 2026: %', v; end if;
  if not exists (select 1 from pg_index x
                  where x.indrelid = 'public.affiliate_account_claims'::regclass and x.indisunique
                    and x.indexrelid = to_regclass('public.uq_affiliate_claims_one_pending')
                    and pg_get_indexdef(x.indexrelid) like '%(auth_user_id) WHERE (status = ''pending''::text)') then
    raise exception '469: the one-pending-claim-per-login index (uq_affiliate_claims_one_pending) is not as read on 24 Oct 2026'; end if;
  -- 440's sign-up copy table: its checks as read (a parked claim's copy is
  -- 'backfill' with no account), and no unique index but its key.
  if (select md5(string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), E'\n' order by c.conname))
        from pg_constraint c
       where c.conrelid = 'public.affiliate_signup_identities'::regclass and c.contype = 'c')
       is distinct from '2f0316541e65a1e8f00509e84c47e41b'
     or (select count(*) from pg_index x
          where x.indrelid = 'public.affiliate_signup_identities'::regclass and x.indisunique and not x.indisprimary) <> 0 then
    raise exception '469: public.affiliate_signup_identities (440''s sign-up copies) is not as read on 24 Oct 2026'; end if;
  v_con := (select pg_get_constraintdef(c.oid) from pg_constraint c
             where c.conrelid = 'public.event_registration_people'::regclass
               and c.conname = 'event_registration_people_match_check');
  if v_con = c_con_after then
    raise notice '469: event_registration_people_match_check already allows phone_and_email; left alone';
  elsif v_con is distinct from c_con_before then
    raise exception '469: event_registration_people_match_check is not as read on 24 Oct 2026: %', v_con;
  end if;

  -- The four: BEFORE (production's, 24 Oct 2026) patched, each anchor once; or AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    if to_regprocedure('public.' || c_sigs[k]) is null then
      raise exception '469: public.% is missing', c_sigs[k]; end if;
    d := pg_get_functiondef(('public.' || c_sigs[k])::regprocedure);
    v_acls[k] := (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure);
    if md5(d) = c_after[k] then
      raise notice '469: public.% is already this version; left alone', c_sigs[k];
    elsif md5(d) <> c_before[k] then
      raise exception '469: public.% is not the version in production on 24 Oct 2026 (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d);
    else
      for i in 1 .. cardinality(c_fn) loop
        continue when c_fn[i] <> k;
        n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
        if n <> 1 then raise exception '469: anchor % of public.% was found % times, not once', i, c_sigs[k], n; end if;
        d := replace(d, c_anchor[i], c_patch[i]);
      end loop;
      if md5(d) <> c_after[k] then
        raise exception '469: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
      v_texts[k] := d;
    end if;
  end loop;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  if v_con = c_con_before then
    alter table public.event_registration_people
      drop constraint event_registration_people_match_check,
      add constraint event_registration_people_match_check
        check (match = any (array['exact', 'same_words', 'phone_and_email', 'new_customer', 'held',
                                  'staff_attached', 'staff_created', 'closed', 'test']));
  end if;
  for k in 1 .. cardinality(c_sigs) loop
    if v_texts[k] is not null then execute v_texts[k]; end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(('public.' || c_sigs[k])::regprocedure)) <> c_after[k] then
      raise exception '469: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute') is distinct from c_anon[k]
       or has_function_privilege('authenticated', 'public.' || c_sigs[k], 'execute') is distinct from c_auth[k]
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '469: the grants of public.% changed', c_sigs[k]; end if;
  end loop;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.event_registration_people'::regclass
         and c.conname = 'event_registration_people_match_check') is distinct from c_con_after then
    raise exception '469: event_registration_people_match_check is not as this file makes it'; end if;

  -- ── 4. Self-test, in a block that is always undone ──────────────────────
  -- Made-up records only ("469 Check ...", @example.invalid, fictional
  -- phones no customer uses and no recent sign-up event names); it ends by
  -- raising P0469, which undoes all it wrote.
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select p as x from unnest(array['+61491570690', '+61491570691', '+61491570692', '+61491570693',
                                            '+61491570694', '+61491570695', '+61491570696', '+61491570697',
                                            '+61491570698', '+61491570699']) p
             where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = p)
               and not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) is null
                                  and c.phone ~ '^[\s().0-9-]+$'
                                  and (public.inspect_customer_phone(c.phone) -> 'candidates') ? p)
               and not exists (select 1 from public.referral_signup_events e
                                where e.normalized_phone = p and e.created_at > now() - interval '1 hour')
             limit 8) y;
    if cardinality(t_phones) is distinct from 8 then
      raise exception '469: the self-test found no unused fictional phones'; end if;

    -- 1. The referral link: a record with the phone and the email, another name typed.
    insert into public.customers (full_name, phone) values ('469 Check Referrer', t_phones[1]) returning id into t_ref;
    t_code := 'CHK469' || upper(t_sfx);
    insert into public.customer_affiliates (customer_id, status, referral_code) values (t_ref, 'active', t_code);
    t_mail := '469-check-h-' || t_sfx || '@example.invalid';
    insert into public.customers (full_name, phone, email) values ('469 Check Holder', t_phones[2], t_mail) returning id into t_h1;
    perform set_config('request.jwt.claim.role', 'anon', true);
    t_ans := public.affiliate_referral_signup(t_code, 'Quite', 'Another ' || t_sfx, t_phones[2], ' ' || upper(t_mail) || ' ', null);
    if t_ans is distinct from c_known
       or (select count(*) from public.customers c where c.deleted_at is null and c.phone = t_phones[2]) <> 1
       or (select c.referred_by from public.customers c where c.id = t_h1) is not null
       or (select count(*) from public.referral_signup_events e
            where e.normalized_phone = t_phones[2] and e.outcome = 'duplicate' and e.referrer_customer_id = t_ref) <> 1
       or exists (select 1 from public.audit_logs l where l.action = 'referral_signup_several_records' and l.record_id = t_h1) then
      raise exception '469: the self-test''s referral sign-up on a record''s phone and email was not "already registered": %', t_ans; end if;
    -- Two records with that phone and email: the same answer, an entry on each.
    perform set_config('request.jwt.claim.role', 'service_role', true);
    insert into public.customers (full_name, phone, email) values ('469 Check Second', t_phones[2], t_mail) returning id into t_h2;
    perform set_config('request.jwt.claim.role', 'anon', true);
    t_ans := public.affiliate_referral_signup(t_code, 'Quite', 'Another ' || t_sfx, t_phones[2], t_mail, null);
    if t_ans is distinct from c_known
       or (select count(*) from public.customers c where c.deleted_at is null and c.phone = t_phones[2]) <> 2
       or (select count(*) from public.audit_logs l
            where l.action = 'referral_signup_several_records' and l.table_name = 'customers' and l.module = 'affiliate'
              and l.record_id in (t_h1, t_h2) and l.new_data -> 'customer_ids' @> to_jsonb(array[t_h1, t_h2])
              and jsonb_array_length(l.new_data -> 'customer_ids') = 2
              and l.new_data ->> 'referrer_customer_id' = t_ref::text and l.changed_by is null) <> 2 then
      raise exception '469: the self-test''s referral sign-up on two records'' phone and email was not answered and recorded as tested: %', t_ans; end if;
    -- The phone alone, with another email: a new customer, as before (425's check).
    t_ans := public.affiliate_referral_signup(t_code, 'Quite', 'Another ' || t_sfx, t_phones[2],
                                              '469-check-o-' || t_sfx || '@example.invalid', null);
    if t_ans ->> 'outcome' is distinct from 'registered'
       or not exists (select 1 from public.customers c
                       where c.phone = t_phones[2] and c.referred_by = t_ref and c.full_name = 'Quite Another ' || t_sfx)
       or not exists (select 1 from public.referral_signup_events e
                       where e.normalized_phone = t_phones[2] and e.outcome = 'phone_shared') then
      raise exception '469: the self-test''s referral sign-up on the phone alone was not registered as before: %', t_ans; end if;
    -- The two records' phone and email again, under yet another name: the same
    -- answer, and no second entry on either (at most one an hour on each).
    t_ans := public.affiliate_referral_signup(t_code, 'Yet', 'Another ' || t_sfx, t_phones[2], upper(t_mail), null);
    if t_ans is distinct from c_known
       or (select count(*) from public.audit_logs l
            where l.action = 'referral_signup_several_records' and l.record_id in (t_h1, t_h2)) <> 2
       or (select count(*) from public.referral_signup_events e
            where e.normalized_phone = t_phones[2] and e.outcome = 'duplicate') <> 3 then
      raise exception '469: the self-test''s referral sign-up on two records'' phone and email, tried again, added an entry: %', t_ans; end if;

    -- 2. The affiliate sign-up: two records on one phone, one with the login's email.
    perform set_config('request.jwt.claim.role', 'service_role', true);
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (gen_random_uuid(), '469-check-j-' || t_sfx || '@example.invalid', now(), '{"affiliate_email_unverified": true}'::jsonb, '{}'::jsonb)
    returning id into t_u1;
    insert into public.customers (full_name, phone) values ('469 Check Family', t_phones[3]) returning id into t_j1;
    insert into public.customers (full_name, phone, email)
    values ('469 Check Joiner', t_phones[3], upper('469-check-j-' || t_sfx || '@example.invalid')) returning id into t_j2;
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_u1::text, true);
    t_ans := public.complete_affiliate_onboarding('Typed', 'Otherwise ' || t_sfx, t_phones[3], true);
    if t_ans ->> 'status' is distinct from 'active' or (t_ans ->> 'customer_id')::uuid is distinct from t_j2
       or (t_ans ->> 'new_customer')::boolean is distinct from false
       or (select a.customer_id from public.affiliate_accounts a where a.auth_user_id = t_u1) is distinct from t_j2
       or (select count(*) from public.customers c where c.deleted_at is null and c.phone = t_phones[3]) <> 2
       or not exists (select 1 from public.audit_logs l
                       where l.action = 'affiliate_portal_claimed' and l.new_data ->> 'auth_user_id' = t_u1::text
                         and l.new_data ->> 'rule' = 'phone_and_email') then
      raise exception '469: the self-test''s affiliate sign-up was not joined to the record with the phone and the email: %', t_ans; end if;
    -- Two records with the phone and the login's email: a pending claim, no record; again: the same.
    perform set_config('request.jwt.claim.role', 'service_role', true);
    perform set_config('request.jwt.claim.sub', '', true);
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (gen_random_uuid(), '469-check-k-' || t_sfx || '@example.invalid', now(), '{"affiliate_email_unverified": true}'::jsonb, '{}'::jsonb)
    returning id into t_u2;
    insert into public.customers (full_name, phone, email)
    values ('469 Check One', t_phones[4], '469-check-k-' || t_sfx || '@example.invalid') returning id into t_k1;
    insert into public.customers (full_name, phone, email)
    values ('469 Check Two', t_phones[4], '469-check-k-' || t_sfx || '@example.invalid') returning id into t_k2;
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_u2::text, true);
    for i in 1 .. 2 loop
      t_ans := public.complete_affiliate_onboarding('Typed', 'Otherwise ' || t_sfx, t_phones[4], true);
      if t_ans is distinct from c_pending then
        raise exception '469: the self-test''s affiliate sign-up on two records was answered %', t_ans; end if;
    end loop;
    if (select count(*) from public.affiliate_account_claims cl
         where cl.auth_user_id = t_u2 and cl.status = 'pending' and cl.candidate_customer_id is null
           and cl.entered_phone = t_phones[4]) <> 1
       or (select count(*) from public.affiliate_account_claims cl where cl.auth_user_id = t_u2) <> 1
       or exists (select 1 from public.affiliate_accounts a where a.auth_user_id = t_u2)
       or (select count(*) from public.customers c where c.deleted_at is null and c.phone = t_phones[4]) <> 2
       or (select count(*) from public.audit_logs l
            where l.action = 'affiliate_claim_parked' and l.new_data ->> 'auth_user_id' = t_u2::text
              and l.new_data ->> 'reason' = 'several_phone_and_email' and l.new_data ->> 'version' = '469') <> 1
       or (select count(*) from public.affiliate_signup_identities x where x.auth_user_id = t_u2) <> 1
       or not exists (select 1 from public.affiliate_signup_identities x
                       where x.auth_user_id = t_u2 and x.source = 'backfill' and x.affiliate_account_id is null
                         and x.customer_id is null and x.full_name = 'Typed Otherwise ' || t_sfx and x.phone = t_phones[4]
                         and x.email = '469-check-k-' || t_sfx || '@example.invalid'
                         and x.name_from = 'arguments' and x.phone_from = 'arguments') then
      raise exception '469: the self-test''s affiliate sign-up on two records did not wait on one claim with one sign-up copy, making nothing'; end if;
    -- The name of two customers on one phone, the login's email on a third
    -- of another name (5): a pending claim suggesting no one, no record.
    perform set_config('request.jwt.claim.role', 'service_role', true);
    perform set_config('request.jwt.claim.sub', '', true);
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (gen_random_uuid(), '469-check-n-' || t_sfx || '@example.invalid', now(), '{"affiliate_email_unverified": true}'::jsonb, '{}'::jsonb)
    returning id into t_u3;
    insert into public.customers (full_name, phone) values ('469 Check Namesake', t_phones[7]) returning id into t_n1;
    insert into public.customers (full_name, phone) values ('469 Check Namesake', t_phones[7]) returning id into t_n2;
    insert into public.customers (full_name, phone, email)
    values ('469 Check Elsewise', t_phones[7], '469-check-n-' || t_sfx || '@example.invalid');
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_u3::text, true);
    t_ans := public.complete_affiliate_onboarding('469 Check', 'Namesake', t_phones[7], true);
    if t_ans is distinct from c_pending
       or (select count(*) from public.affiliate_account_claims cl
            where cl.auth_user_id = t_u3 and cl.status = 'pending' and cl.candidate_customer_id is null) <> 1
       or exists (select 1 from public.affiliate_accounts a where a.auth_user_id = t_u3)
       or (select count(*) from public.customers c where c.deleted_at is null and c.phone = t_phones[7]) <> 3
       or (select count(*) from public.audit_logs l
            where l.action = 'affiliate_claim_parked' and l.new_data ->> 'auth_user_id' = t_u3::text
              and l.new_data ->> 'reason' = 'several_name_matches') <> 1 then
      raise exception '469: the self-test''s affiliate sign-up under two customers'' name with a third''s email did not wait on a claim: %', t_ans; end if;
    -- The seminar, the same: held for the two.
    t_ans := public.event_web_match_customer(t_phones[7], '469 Check Namesake', '469-check-n-' || t_sfx || '@example.invalid');
    if t_ans is distinct from jsonb_build_object('kind', 'held', 'hold_reason', 'several_name_matches',
                                                 'candidates', to_jsonb(array(select x from unnest(array[t_n1, t_n2]) x order by x))) then
      raise exception '469: the self-test''s seminar match under two customers'' name with a third''s email was not held for the two: %', t_ans; end if;

    -- 3. The seminar website: through the referral link, a record with the
    -- phone and the email under another name (its household's other record
    -- on that phone has no email), and someone new.
    perform set_config('request.jwt.claim.role', 'service_role', true);
    perform set_config('request.jwt.claim.sub', '', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '469-check-owner-' || t_sfx || '@example.invalid')
      returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '469 check', u.email, 'owner', true from auth.users u where u.id = t_owner;
    insert into public.stores (name, code, country_code) values ('469 check ' || t_sfx, '469-' || t_sfx, 'SG') returning id into t_store;
    insert into public.events (name, daily_start, daily_end, is_active) values ('469 check ' || t_sfx, '09:00', '19:00', true)
      returning id into t_event;
    insert into public.event_days (event_id, day) values (t_event, public.sg_today() + 30);
    insert into public.event_stores (event_id, store_id) values (t_event, t_store);
    insert into public.event_web_settings (event_id, code, mode, store_id, acting_profile_id)
    values (t_event, 'CHECK469-' || upper(t_sfx), 'live', t_store, t_owner);
    t_live := 'evk_live_' || rpad(t_sfx, 43, 'L');
    t_hash := encode(extensions.digest(t_live, 'sha256'), 'hex');
    insert into public.event_web_keys (event_id, kind, key_hash, key_hint, created_by)
    values (t_event, 'live', t_hash, '469 check', t_owner);
    insert into public.customers (full_name, phone, email)
    values ('469 Check Seminar', t_phones[5], '469-check-s-' || t_sfx || '@example.invalid') returning id into t_s1;
    insert into public.customers (full_name, phone) values ('469 Check Household', t_phones[5]) returning id into t_s2;
    t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK469-' || upper(t_sfx), 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(t_sfx), 'submitted_at', now(),
        'referral_code', t_code, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Quite', 'last_name', 'Another', 'phone', t_phones[5],
                             'email', upper('469-check-s-' || t_sfx || '@example.invalid'),
                             'days', jsonb_build_array(public.sg_today() + 30), 'vip', false),
          jsonb_build_object('position', 2, 'first_name', 'Plain', 'last_name', 'Person', 'phone', t_phones[6],
                             'email', '469-check-p-' || t_sfx || '@example.invalid',
                             'days', jsonb_build_array(public.sg_today() + 30), 'vip', false)))));
    t_p1 := (t_ans -> 'people' -> 0 ->> 'person_id')::uuid;
    t_p2 := (t_ans -> 'people' -> 1 ->> 'person_id')::uuid;
    if t_ans ->> 'status' is distinct from 'registered'
       or (select (p.match, p.customer_id, p.referral_outcome, p.hold_reason)
                  is distinct from ('phone_and_email'::text, t_s1, 'already_customer'::text, null::text)
             from public.event_registration_people p where p.id = t_p1)
       or (select c.referred_by from public.customers c where c.id = t_s1) is not null
       or (select count(*) from public.customers c where c.deleted_at is null and c.phone = t_phones[5]) <> 2
       or (select (p.match, p.referral_outcome) is distinct from ('new_customer'::text, 'created'::text)
             from public.event_registration_people p where p.id = t_p2) then
      raise exception '469: the self-test''s seminar registration is not as tested (linked by the phone and the email): %', t_ans; end if;
    -- The same phone and email again under another name: that customer is on
    -- this event's list already, so held for staff, no second guest on it.
    t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK469-' || upper(t_sfx), 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'again'), 1, 8)),
        'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Yet', 'last_name', 'Another', 'phone', t_phones[5],
                             'email', '469-check-s-' || t_sfx || '@example.invalid',
                             'days', jsonb_build_array(public.sg_today() + 30), 'vip', false)))));
    t_p2 := (t_ans -> 'people' -> 0 ->> 'person_id')::uuid;
    if t_ans ->> 'status' is distinct from 'registered'
       or (select (p.match, p.customer_id, p.hold_reason, p.candidate_customer_ids)
                  is distinct from ('held'::text, null::uuid, 'phone_and_email_in_use'::text, array[t_s1])
             from public.event_registration_people p where p.id = t_p2)
       or (select count(*) from public.event_guests g where g.event_id = t_event and g.customer_id = t_s1) <> 1 then
      raise exception '469: the self-test''s second seminar sign-up of a customer on the list was not held: %', t_ans; end if;
    -- A customer staff added to this event's list (4): a sign-up under
    -- another name with their phone and email is held, no second guest.
    insert into public.customers (full_name, phone, email)
    values ('469 Check Staffadded', t_phones[8], '469-check-g-' || t_sfx || '@example.invalid') returning id into t_g1;
    insert into public.event_guests (event_id, name, phone, customer_id, source)
    values (t_event, '469 Check Staffadded', t_phones[8], t_g1, 'free');
    t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK469-' || upper(t_sfx), 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'staff'), 1, 8)),
        'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Some', 'last_name', 'Body', 'phone', t_phones[8],
                             'email', '469-check-g-' || t_sfx || '@example.invalid',
                             'days', jsonb_build_array(public.sg_today() + 30), 'vip', false)))));
    t_p2 := (t_ans -> 'people' -> 0 ->> 'person_id')::uuid;
    if t_ans ->> 'status' is distinct from 'registered'
       or (select (p.match, p.customer_id, p.hold_reason, p.candidate_customer_ids)
                  is distinct from ('held'::text, null::uuid, 'phone_and_email_in_use'::text, array[t_g1])
             from public.event_registration_people p where p.id = t_p2)
       or (select count(*) from public.event_guests g where g.event_id = t_event and g.customer_id = t_g1) <> 1 then
      raise exception '469: the self-test''s seminar sign-up of a customer staff added to the list was not held: %', t_ans; end if;

    raise exception using errcode = 'P0469', message = '469: self-test done, undone';
  exception when sqlstate 'P0469' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
