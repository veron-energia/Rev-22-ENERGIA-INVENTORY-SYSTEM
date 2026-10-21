-- 437_affiliate_signup_straight_in.sql
--
-- AFFILIATE SIGN-UP GOES STRAIGHT IN: THE PHONE FINDS THE CUSTOMER, THE EMAIL
-- IS VERIFIED LATER, AND A FRESH RECORD THAT MAY BE SOMEONE ALREADY THERE IS
-- LISTED FOR AN OWNER OR MANAGER (the Owner's decisions, 20 Oct 2026; the
-- Owner's answers of 21 Oct 2026, AFF-SIGNUP-15..18)
--
-- WHAT WAS WRONG
--
--   Pressing Create Account on /affiliate/join made a login that could not
--   sign in until its email link was opened, and the link often never was:
--   on 20 Oct 2026, 14 people who signed up had never verified their email,
--   and 2 who had were still not in (production, read only; counts only).
--   Sign-up then linked a login to a customer by itself only when the
--   verified email, the phone and the name all pointed at one customer
--   (432); everyone else waited on a claim for staff ("needs identity
--   verification"), or got a second record of themselves.
--
-- THE RULES (the Owner, 20 Oct 2026; keys AFF-SIGNUP-1..8)
--
--   1. Create Account takes the person straight to the affiliate dashboard.
--      No waiting for an email. (The sign-up function, not this file, makes
--      the login already confirmed; Supabase Auth's "Confirm email" stays
--      on.)
--   2. The email is verified later, from the affiliate Account page: a
--      "Send verification email" button, and the page shows verified or not.
--   3. Until then the affiliate can do everything: the portal, the referral
--      link, commission, payouts. Nothing here waits on it.
--   4. An email that already has a login: the sign-up page says so and
--      offers Sign in and Reset password (the sign-up function and the page).
--   5. The people stuck after signing up are let in at their next sign-in,
--      like a new sign-up. (The 14 unconfirmed logins also need the one-off
--      scripts/repairs/affiliate-stuck-signups-437.sql, with the Owner's
--      go-ahead; the 2 confirmed ones need nothing.)
--   6. Linking a new affiliate on a fresh record to the customer already
--      there is done later by an Owner or Manager from the Affiliates page:
--      a list of affiliates on fresh records that may match a customer (by
--      phone, email or name), with "Link to this customer". Linking joins the
--      fresh record into the existing customer through merge_customer_records,
--      unchanged; the affiliate login then belongs to that customer, and
--      referrals made meanwhile come with it. Audited. The affiliate does
--      nothing.
--   7. At sign-up, when the phone belongs to exactly one customer, the login
--      joins that customer at once, on the phone alone. (The Owner was told
--      that, the email being unverified, anyone typing a customer's phone
--      gets into that account, and chose this.)
--   8. When several customers share the phone, it joins the one whose name
--      has the same words as the name typed (432's customer_names_match; the
--      name exactly as typed first); otherwise a fresh record, listed for
--      staff. The person never sees the other names.
--   A phone no customer has gives a fresh record (a new customer).
--   Kept, as before (the stated defaults): a customer an Owner unlinked a
--   login from (378) or an Owner or Manager rejected a claim for (379) is
--   never joined by itself; nor is a customer who already has a portal login
--   (one each). Both give a fresh record, listed for staff. A staff login
--   cannot become an affiliate (320). A login whose claim was rejected stays
--   rejected. Every join, fresh record and staff link writes an audit row.
--
-- LINKING A SIGN-UP (the Owner's answers, 20 Oct 2026; keys AFF-SIGNUP-9,
-- 12..14)
--
--   9.  As built: linked to a customer with an affiliate record of their
--       own, the customer keeps it and its code, and the new record's code
--       is retired; only while the new record has no referral, sale or
--       commission, otherwise Keep separate.
--   12. Link copies the email they signed up with onto the customer when the
--       customer has none, unless another customer in use already has it
--       (the app's email match key, customer_email_match_key): then it is
--       left, and the answer says so. The Link box shows both phones (the
--       customer's and the one they signed up with) and a tick box "use the
--       phone they signed up with", unticked to start. Ticked, the customer's
--       phone becomes that one, the way a phone change is made on the
--       Customers page (a reason, the phone history, at most 3 customers to
--       a phone). If that change is refused, the whole link is refused, with
--       a message to untick the box: nothing is half done. The link's audit
--       row records what was copied and changed. A retry with the same
--       request id answers "replayed" and changes nothing.
--   13. A sign-up with the very same name (the same words, 432's rule) and
--       phone as a customer whose record already has an affiliate login
--       still goes straight in (7 and 8 unchanged). The list flags the pair
--       (twin) and says that, until it is sorted out, this person's website
--       registrations, VIP payments (436) and QR health forms (433) wait
--       under To match; and the fix: an Owner first unlinks the wrong login
--       from the customer (Unlink login, 378), then links the sign-up.
--   14. Retiring the new record's code on Link stays (9), and the Link box
--       warns: "Links shared with code <new code> will stop crediting
--       anyone. Ask them to share code <customer's code> instead." No alias:
--       codes are looked up as before.
--
-- THE OWNER'S ANSWERS, 21 OCT 2026 (after the final review of 436, 437 and
-- 438 together; keys AFF-SIGNUP-15..18)
--
--   15. Fix 16..18 in this file before it goes live (it is the last step of
--       today's run sheet).
--   16. The Link box's "use the phone they signed up with" starts TICKED
--       when the email they signed up with cannot be copied onto the
--       customer (the customer keeps their own, or another customer has it)
--       or when registrations or forms of this sign-up wait under To match
--       (436's seminar registrations and 433's QR health forms held with the
--       fresh record as a candidate); otherwise unticked. The server says
--       which and why; staff can still change it. Unticked, the box says
--       plainly that a later website or referral-page registration on the
--       sign-up phone becomes a new customer and, through another
--       affiliate's link, can earn that affiliate commission (for a seminar
--       VIP at once).
--   17. Link earns the commission the fresh record's paid invoices missed:
--       for each paid invoice the merge moves onto the customer with no
--       commission row at all, when the customer has a referrer, as the
--       engine earns it at payment, dated the Link day; the invoices and
--       amounts are in the link's audit row and its answer, and the page
--       shows them. Never twice.
--   18. A login the phone alone joined to a customer (7) under a name that
--       is not the record's (not the same words) stays joined, and is listed
--       as "may be someone else", with the name typed and the record's: Same
--       person closes it with a note; if it is someone else, an Owner
--       unlinks the login and the person gets a record of their own at
--       their next sign-in. Never Link.
--   (Two seminar follow-ups, To match following a Link and the
--   no-self-referral check comparing the login's own details, are 436's,
--   for the other session after go-live: NOT COVERED below.)
--
-- WHAT THIS DOES
--
--   1. complete_affiliate_onboarding (the verify page calls it, signed in as
--      the new login, straight after Create Account or at the next sign-in)
--      applies 7 and 8:
--        * one customer in use has the phone, and no other's stored number
--          could be it: joined (rule 'phone'); when the name typed is not
--          the record's (neither the same name nor the same words,
--          customer_names_match), the join stays and it is listed as "may
--          be someone else" ('phone_other_name', AFF-SIGNUP-18);
--        * several have it: the one with the name exactly as typed, else the
--          one with the same words ('phone_and_name', 'phone_and_same_words');
--          none or more than one: a fresh record, listed ('shared_phone');
--        * only a customer whose stored 8-digit number could be this one
--          (Singapore or Malaysia, as 425 reads it): a fresh record, listed
--          ('phone_unconfirmed'); such a customer also counts as sharing
--          the phone, so the phone alone does not join anyone then;
--        * the customer picked has a portal login, is protected (378, 379) or
--          had their affiliate record removed: a fresh record, listed
--          ('customer_has_login', 'protected_customer', 'affiliate_removed');
--        * no one has the phone: a fresh record; listed when a customer in
--          use has the same inbox ('email_match') or a name with the same
--          words ('name_match'), or an earlier claim of this login suggested
--          someone ('earlier_claim').
--      It never answers "pending verification" any more, and no longer
--      parks claims; the person is never told that they are listed. A
--      pending claim of the login is closed ('resolved',
--      "437: let in at sign-in") and whom it suggested is listed. A login
--      with a rejected claim is told "unsuccessful", whatever it enters
--      (before, a phone and an email no customer had still made it a
--      customer). A second call answers "already" and changes nothing.
--      When 3 customers already have the phone, a fresh record is refused by
--      the phone rule (CUSTOMER_PHONE_LIMIT), as before, and the page asks for
--      another number. Its audit row ('affiliate_portal_claimed') says which
--      rule joined the customer or that a fresh record was made, why it is
--      listed, the claims closed and whether the email counts as verified.
--      It no longer calls require_resolved_customer_identity (which stopped
--      a sign-up with AMBIGUOUS_CUSTOMER_MATCH): that case is now a fresh
--      record, listed.
--   2. The app's own "email verified" (2): affiliate_accounts gains
--      email_verified_at. Sign-up sets it when Supabase Auth confirmed the
--      login through its own email link (every login before this), and
--      leaves it empty for a login the sign-up function or the repair
--      confirmed (they mark app_metadata.affiliate_email_unverified, which
--      only the server can set), unless that session itself came from an
--      emailed link. The 70 affiliate accounts of 20 Oct get the date their
--      login was confirmed (all verified their email to get in).
--      confirm_affiliate_email() sets it for the signed-in affiliate when
--      the session was opened from an emailed link (the token's amr: a
--      sign-in link, a reset, an invitation or a sign-up link) in the last 30
--      minutes, the window 429 uses; the Account page's email holds such a
--      link. affiliate_email_verification_needed(email), for the service role
--      only, tells auth-resend-verification whether to send it.
--      Once verified, the login keeps it too (app_metadata
--      affiliate_email_verified_at, and the "unverified" mark goes), so the
--      account made at its next sign-in after an Owner unlinks it (378)
--      starts verified from the same date.
--   3. The list (6): table affiliate_signup_matches, one open entry per
--      login, with the fresh record, why, and the customers it may be; or,
--      for a phone-only join under another name (18), the customer joined
--      and the name typed. For an Owner or Manager (each starts with
--      require_active_staff):
--        affiliate_signup_matches_open()      the open entries, each with its
--          candidates (listed at sign-up, or with the record's phone now), how
--          each matches (phone, email, name), and why one cannot be linked;
--          and what the Link box shows: the phone and email they signed up
--          with (entered_phone, login_email) beside each customer's, what
--          Link would do with the email (email_on_link: 'copy', 'keep_own',
--          'in_use' or 'none'), the new record's code (referral_code) and
--          each customer's own (own_referral_code, retires_new_code), and the
--          twin flag (13): 'twin' and 'twin_customer_id' on the entry, 'twin'
--          on the customer, for a customer in use with the very same phone, a
--          name of the same words (customer_names_match) or the same name,
--          and an affiliate login of their own. Who else has the inbox an
--          entry's login signed up with is read once for the whole list,
--          not once per entry (the key has no index; the page waits on it).
--          AFF-SIGNUP-16: per entry what waits under To match ('waiting':
--          'seminar', 436's event_registration_people still held with the
--          fresh record among their candidates, read by name only when that
--          table is there, null when it is not; 'qr', 433's
--          health_survey_holds still open naming it), read once for the
--          whole list; per customer how the phone box starts
--          (use_signup_phone_default) and why (use_signup_phone_why:
--          'email_keep_own', 'email_in_use', 'waiting_seminar', 'waiting_qr';
--          or 'same_phone' / 'no_signup_phone', no box). AFF-SIGNUP-18: a
--          phone-only join under another name has kind 'may_be_someone_else'
--          (the others 'fresh_record'), the customer it joined, the name
--          typed, and no candidates;
--        link_affiliate_signup(entry, customer, note, request id,
--                              use the sign-up phone, default false)
--          merge_customer_records(customer, fresh record): the login, the
--          affiliate record and its code, referrals and commissions move to
--          the customer; the fresh record is retired. Both records are
--          locked first, in the merge's order, so what it decides (the email,
--          the phone, the audit row's "before") is what it then changes: an
--          email Staff save meanwhile is seen, or waits. A customer with an
--          affiliate record of their own (an Owner unlinked the login that
--          had it, 378, or the phone joined someone else's login to it
--          first) keeps it and its code: the login moves onto it and the
--          fresh record's own, unused, is retired before the merge (the
--          merge refuses two affiliates). Only while the fresh record has
--          done nothing as an affiliate (affiliate_signup_fresh_history:
--          no referral, sale, exchange, commission, payout, settlement or
--          campaign reward); otherwise which code survives is the merge's
--          "decision about real money", and it is refused. Refused too for
--          a customer not listed for the entry, one with a portal login, or
--          one whose affiliate record was removed (the unique affiliate
--          record per customer could not take a second). Then (12) one
--          update_customer (418, the Customers page's Edit, unchanged) puts
--          on the customer, with the merge's reason: the email they signed
--          up with (their login's) when the customer has none and no other
--          customer in use has it (otherwise it is left, 'email_not_copied'
--          says why and a note in the answer says so); and, ticked, the phone
--          they signed up with (the entry's entered_phone), unless the
--          customer has it already: the old number goes into the phone
--          history with that reason (audit_customer_phone_change) and the
--          phone rule applies (enforce_customer_phone_policy). It comes after
--          the merge, so the fresh record's place on that phone passes to the
--          customer; the rule can then refuse it only when 3 other customers
--          hold the phone (staff changed the fresh record's since). Refused,
--          the merge, the retired code and everything else are undone too
--          (each is in the same block), and the answer is ok false,
--          phone_refused, with a message to untick the box. A retry with the
--          same request id answers "replayed", changes and earns nothing, and
--          says what the link did (the email, the phone, the notes and the
--          commission lists below, read back from its audit row), so the page
--          shows it after a lost answer too.
--          AFF-SIGNUP-17: then, when the customer has a referrer, each paid
--          invoice the merge moved from the fresh record that has no
--          commission row at all (asked again with the invoice locked)
--          earns its commission as at payment, through the engine's own
--          functions, unchanged, in the order reconcile_invoice_commissions
--          runs them: earn_invoice_commission for its lines (tier 1 the
--          invoice's chosen affiliate or else the customer's referrer, tier
--          2 tier 1's referrer, nothing on a customer's own purchase or on an
--          invoice that names no affiliate on purpose, a blocked row for a
--          referrer who may not earn; it leaves out credit package and
--          premium bundle lines), earn_credit_package_commission and
--          earn_premium_bundle_commission for each package and bundle sale
--          on it the merge moved to the customer (as payment earns them
--          through issue_credit_lines_for_invoice: on the money paid less
--          what was refunded of it, by the same rules), then
--          adjust_invoice_line_commission_refunds for a refund already
--          recorded; its rows are dated the Link day in Singapore
--          (sg_today(); the engine itself dates by the day the invoice was
--          paid; 436 dates a VIP earned at a check the same way, R6-5). Each
--          invoice on its own (a savepoint): one the engine refuses keeps
--          none of its rows, so nothing is half earned, and is named with
--          why; the link stands (the merge is right whatever the commission;
--          undoing it would lose the Owner's answer for a commission
--          question). The answer and the audit row list commission_earned
--          (invoice, rows by tier and referrer, amount) and
--          commission_not_earned ('none_due': the engine's rules give none;
--          'refused', with the message), and commission_dated. An invoice
--          with any commission row is left alone; a replay earns nothing.
--          A phone-only join (18) is refused: no new record;
--        keep_affiliate_signup_separate(entry, note)  "not the same person"
--          (a family member, say), with a reason; nothing else changes.
--          Refused for a phone-only join (18): the login is on the
--          customer's own record;
--        confirm_affiliate_signup_same_person(entry, note)  AFF-SIGNUP-18:
--          a phone-only join under another name checked as the customer
--          after all: the entry is closed ('same_person'), with the note;
--          nothing else changes. Only for such an entry, still open, whose
--          login is still on that customer. (Someone else: an Owner's Unlink
--          login, 378; the entry then leaves the list, and goes at the
--          login's next sign-in, which gives it a record of its own.)
--      Each writes its own audit row ('affiliate_signup_linked', with the
--      customer's phone and email before and after, whether the box was
--      ticked, what was copied or changed, the notes in the answer, and the
--      commission earned or not, which a replay reads back;
--      'affiliate_signup_kept_separate'; 'affiliate_signup_same_person');
--      the merge writes its own ('customers_merged'), and the change of the
--      customer its own ('customer_updated').
--      A login an Owner unlinked from its customer (378) gets a new entry
--      at its next sign-in when it is listed again; the stale one goes
--      either way.
--      The table has no foreign key to customers on purpose:
--      merge_customer_records moves every column that has one, and the entry
--      must keep naming the fresh record it was made for.
--   4. A login the sign-up made is never a staff invitation's login while
--      its email is not verified (invite_user_provisioned): sign-up confirms
--      whatever address is typed (1), so someone who signs up on another
--      person's address and writes "invited_to" into their own metadata
--      would otherwise get that login made the invitee's (429 reuses an
--      uninvited login with that metadata), and the invitee would set their
--      password on a login someone else holds tokens for. It answers
--      login_in_use (admin-invite-user then says the login cannot be used,
--      LOGIN_NOT_REUSABLE, and sends nothing); nor is such a login given a
--      cancelled profile when its invitation was cancelled during set-up
--      (413), which a later invitation would reuse.
--
-- NOT CHANGED
--
--   * customer_names_match, customer_name_words, customer_email_match_key,
--     customer_phone_name_matches, require_resolved_customer_identity,
--     normalize_customer_phone, normalize_customer_match_name,
--     create_customer_quick, public_affiliate_referral_info and
--     merge_customer_records (436 pins them), and every function 430 pins
--     (invite_user_reusable_login among them: admin-invite-user always
--     provisions the login it returns, and stops on login_in_use).
--   * update_customer and the phone triggers it fires
--     (audit_customer_phone_change, enforce_customer_phone_policy): Link
--     calls update_customer as the Customers page does (12); it is pinned
--     below, not changed. How referral codes are looked up (14: no alias).
--   * The commission engine (17): earn_invoice_commission,
--     earn_credit_package_commission, earn_premium_bundle_commission,
--     adjust_invoice_line_commission_refunds and sg_today(); Link calls
--     them, pinned below, not changed (neither 436 nor 438 changes them).
--     Staff commission and reconcile_invoice_commissions are not called.
--   * Nothing of 436 or 438 is read or changed except 436's
--     event_registration_people, read by name (dynamic SQL, only when it is
--     there) for the waiting count (16); 433's health_survey_holds is read
--     as production has it.
--   * invite_user_begin, invite_user_accept, invite_user_cancel and the
--     Edge Functions (admin-invite-user needs no redeploy for 4).
--   * The claim functions (resolve, reject, delete, the claim lists, the
--     link check, unlink) and their rules: pending claims made before this
--     can still be resolved there until the person signs in.
--   * The referral sign-up (/r/:code, affiliate_referral_signup) and the
--     seminar websites.
--   * Who may call what: complete_affiliate_onboarding and
--     invite_user_provisioned keep their grants.
--   * Supabase Auth settings.
--
-- NOT COVERED (reported to the owner)
--
--   * 7 is as decided: anyone who types a customer's phone at sign-up is let
--     into that customer's affiliate account, with their history in the
--     portal. The welcome WhatsApp (394) still goes to the customer's phone.
--   * With no email to verify first (1, 3), anyone can sign up with an
--     address that is not theirs; its owner then gets the login back with
--     Reset password (the link goes to the mailbox). The sign-up page tells
--     a second sign-up that the address is in use (4).
--   * A fresh record made on a phone 3 customers share cannot be made (the
--     phone rule); the person enters another number.
--   * Candidates are found when the person signs up (by phone, email and
--     name, at most 10) and, on the list, also by the record's phone now; a
--     customer added later under the same name or email is not listed.
--   * An affiliate who changes their login email later keeps the verified
--     date (the portal has no email change).
--   * Linking to a customer with an affiliate record of their own keeps the
--     customer's record and code and retires the new, unused one (confirmed
--     by the Owner, AFF-SIGNUP-9). When the new record has already referred
--     someone, sold or earned, or the customer's record was removed, the
--     Affiliates page says why and the sign-up can only be kept separate
--     until the money question is settled by hand.
--   * (14) Links already shared with a retired code find no one afterwards:
--     a referral sign-up or a seminar registration made with it gets no
--     referrer (the Owner: no alias for now). The Link box warns first.
--   * (12) "The phone they signed up with" is the one the entry kept at
--     sign-up, not one staff put on the fresh record since. Unticked, the
--     customer keeps their phone, and website forms and sign-ups made with
--     the sign-up phone no longer find the person: a later registration on
--     it becomes a new customer and, through another affiliate's link, can
--     earn that affiliate commission (the Link box says so, 16).
--     The email copied is the login's; a customer with an email keeps
--     theirs, even a different one. When another customer has that inbox,
--     the email is left and staff sort it out on the Customers page.
--   * (13) The twin flag is shown, not acted on: the sign-up still goes in
--     on a fresh record. Website registrations and QR forms already waiting
--     under To match stay there after the link until staff attach them to
--     the customer. Two records with one name and phone where neither has a
--     login are not flagged (they can be linked straight away). An Owner
--     alone can unlink a login (378), so a Manager sees the fix but cannot
--     do its first step.
--   * An address someone signed up with as an affiliate and never verified
--     cannot be invited as staff (LOGIN_NOT_REUSABLE) until its owner
--     verifies it, or an Owner deletes that login in Supabase (Auth, Users):
--     such a login is marked affiliate_email_unverified and has no profile.
--   * The seminar side, for the other session after go-live (the Owner, 21
--     Oct 2026; 436 is final today): (a) To match does not follow a Link:
--     registrations and QR forms held with the fresh record as a candidate
--     keep it after the merge retires it, so they show no candidate until
--     staff attach them (436 follow-up: map a retired candidate to the
--     record that kept it); ticking the phone box (16) keeps new ones
--     finding the person meanwhile. (b) 436's no-self-referral check
--     compares the referrer's record only, not the affiliate login's own
--     name, phone and email (436 follow-up); the "may be someone else" list
--     (18) shows staff such logins.
--   * (16) The waiting count is of holds that name the fresh record among
--     their candidates; one held before the fresh record existed, or found
--     only by a live lookup of the phone, is not counted. The default is a
--     suggestion: the server takes what the page sends
--     (p_use_signup_phone, false when not sent).
--   * (17) Only invoices that are paid (status paid) when Link runs: one
--     part paid earns when it is paid in full, by the engine, dated that
--     day; one cancelled, refunded, or waiting on a cancellation or refund
--     request earns nothing here. Credit package and premium bundle lines
--     earn too, through their own functions, as at payment; a share of a
--     split package given to another customer stays as payment left it.
--     Staff commission is not touched. An invoice the engine refuses is
--     named in the answer and needs an Owner to look at its commission (the
--     link is done). The commission is dated the Link day, so it falls in
--     the Link day's month even when the invoice was paid in an earlier one,
--     and the Link changes no month already paid out. If the engine later
--     works that invoice's commission out again (a correction, a refund or a
--     reopening, through reconcile_invoice_commissions, not 437's), what it
--     earns again is dated by the invoice's paid date, as for any invoice,
--     so it can then fall in an earlier month, even one already paid out,
--     where it shows as owed; the total is unchanged (as 436 says of its
--     R6-5 VIP commission).
--   * (18) Only a join on the phone alone (rule 'phone') is checked; a
--     name with an honorific, a typo or a nickname reads as another name, so
--     staff answer Same person. While it is listed the person already sees
--     the customer's portal (7, as the Owner chose), and referrals made with
--     the customer's code meanwhile are the customer's. After an Owner
--     unlinks the login the entry leaves the list and is removed at the
--     login's next sign-in, which lets the person straight in on a record
--     of their own (no claim is made, so there is none to reject; the
--     Unlink window says so). Those referrals, the affiliate record and its
--     code stay with the customer. A Manager sees the fix, but only an Owner
--     can unlink.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), so it is
--   atomic whatever runs it, and every check comes before anything changes:
--   * complete_affiliate_onboarding and invite_user_provisioned must be the
--     versions read on production on 20 Oct 2026 (BEFORE) or already these
--     (AFTER, left alone); each new function missing or already this one,
--     and no other function may take their names. Each text is checked against its AFTER md5 before it
--     is installed.
--   * The functions relied on and not changed must be as read on the stack
--     after 430 (20 Oct 2026), below (the commission engine among them:
--     neither 436 nor 438 changes it); so this goes in after 430. It does
--     not depend on 436 or 438, nor they on it: it goes before, between or
--     after them (438 after 436).
--   * affiliate_signup_matches must be missing or exactly this shape (an
--     earlier draft's, without 'phone_other_name' and 'same_person', stops
--     it), and affiliate_accounts.email_verified_at missing or a
--     timestamptz.
--   * 433's health_survey_holds must have survey_id, candidate_customer_ids
--     (uuid[]) and resolved_at; 436's event_registration_people, when it is
--     there, id, match, is_test and candidate_customer_ids (uuid[]).
--   * link_affiliate_signup has five arguments; no other function may take
--     its name (an earlier draft's four-argument one would stop this).
--   Afterwards every function has its AFTER md5; the two changed ones keep
--   their grants; anon may call none of the new ones; the four list
--   functions (the list, Link, Keep separate, Same person) and
--   confirm_affiliate_email are for signed-in logins, the five helpers for
--   the service role alone; the new table is no client's.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0437, so it leaves no row): three made-up logins (@example.invalid), a
--   made-up customer on an unused fictional phone and a made-up invitation;
--   the first login joins that customer on the phone alone, unverified,
--   under another name, so it is listed "may be someone else" (18), once;
--   the second gets a fresh record, unlisted; a session from an emailed link
--   verifies the first, which its login keeps; the third, made by the
--   sign-up and saying it was invited, is refused by the invitation, and,
--   the invitation cancelled, given no profile. A second run changes
--   nothing.
--
-- BEFORE (production, 20 Oct 2026, head 20261018065120; md5 of
-- pg_get_functiondef with search_path public):
--   changed
--   complete_affiliate_onboarding(text,text,text,boolean)        ff59dd1f8a6ca7397efea5880c6a87a7
--   invite_user_provisioned(uuid,uuid)                           7219cae03a5a758402e79762baf46f42  (429's AFTER; pinned by
--                                                                  neither 430 nor 436)
--   relied on, not changed (the stack after 430, 20 Oct 2026)
--   customer_names_match(text,text)                              ef1af52e4888cefb6037a2291f4e011d
--   customer_name_words(text)                                    a7507abf0f15abd923dff59508b269c1
--   customer_email_match_key(text)                               be468815c9626fff1728e2cfcd484b66
--   normalize_customer_phone(text)                               b2bfac910e0c9eff402ba44e19750bee
--   normalize_customer_match_name(text)                          0572764712e179dc606c66f9f3dbaa03
--   inspect_customer_phone(text,text)                            6672c4d1963996f3b601896f4a55916e
--   merge_customer_records(uuid,uuid,text,uuid)                  099ecf3aae30b5faaf8fb36bc15ce888
--   require_active_staff(text[])                                 877b3aa74cea559881979bb161c450e2
--   is_owner_or_manager()                                        a98e50f1b6d3fa1e6c62cf52a8073cc8  (430's AFTER)
--   current_user_role()                                          519b0a33a3548f970c5d585b6e76a389
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   generate_affiliate_referral_code()                           29ae3d463f13788ccf88a952eb3e70b8
--   update_customer(uuid,jsonb,text,timestamp with time zone)    6511100316418394409d8baf1d2b52e0  (418; AFF-SIGNUP-12)
--   audit_customer_phone_change()                                414b5857bccb5b06d7ef3278dc754617  (fired by it)
--   enforce_customer_phone_policy()                              009273025173c6666a0ecf0408cb7ce1  (fired by it)
--   earn_invoice_commission(uuid)                                6156b2e1ee51da5146a5a7acc16091ce  (AFF-SIGNUP-17; the same
--   adjust_invoice_line_commission_refunds(uuid,uuid[])          5959dec0fedd5fd45fb4615da413b20c   with 436, 438 or both)
--   sg_today()                                                   1c1289f18e24d8370e9a6364c9c06fca
--   earn_credit_package_commission(uuid)                         13ce59fd892c027338a41de4113ae55d  (AFF-SIGNUP-17; 383's
--   earn_premium_bundle_commission(uuid)                         b75ffbea70fd020e75d1ddf4f7b06ba1   AFTER; the same with
--                                                                  436, 438 or both)
--   public function fingerprint (production, 20 Oct 2026)        78e592e12fe890cd3d4ff2cd847e7f7f
-- AFTER (for later guards):
--   affiliate_session_from_email_link()                          d0f5ab3b19eecc6211262821bcbee600  (new)
--   affiliate_signup_candidates(uuid,text,text,text)             a9233b065de981e00e76143c0aa94ac7  (new)
--   affiliate_signup_match_kinds(uuid,text,text,text)            2157bdf60e165a7ace6d9ee2c476ab92  (new)
--   affiliate_signup_fresh_history(uuid,uuid)                    48f892efdc678c40ad3a3dd8b97a0c32  (new)
--   affiliate_email_verification_needed(text)                    d6173ed6952e48c7a1b67cd106f45b71  (new)
--   confirm_affiliate_email()                                    431ff39aa4fe42ec9b1442e65a044676  (new)
--   complete_affiliate_onboarding(text,text,text,boolean)        88ee10799d1c93ce93d0056740f05e01
--   affiliate_signup_matches_open()                              e6c198839c224ca62dce59d3cb4bfb4e  (new)
--   link_affiliate_signup(uuid,uuid,text,uuid,boolean)           198780b31301695db55c4a39ba9618f8  (new)
--   keep_affiliate_signup_separate(uuid,text)                    45b09a6843b0c569e90447485e238a78  (new)
--   confirm_affiliate_signup_same_person(uuid,text)              a9a1f6c2d37284e1e19d898ebdd203e6  (new)
--   invite_user_provisioned(uuid,uuid)                           6b895cc341bacbe9e115e28982d661e3
--   public function fingerprint, worked out on copies of production (21
--   Oct 2026; 436 FINAL, file md5 507b0c98a7b22d5b2c26ee1355cec49b; 438
--   file md5 eb8df158a53c66ba0d8b9b1c5e0ab636):
--     the stack after 430 (production now + 417, 434, 422, 423, 419, 425,
--     426, 430)                                                   be589a20fca0f181f648e6e93c45cb4d (1280 functions)
--     ... then 437                                                b20ca7048ab2bcaa3d57f6ee2826dd72 (1290)
--     ... then 436 and 437, in either order                       dd044aa3a1e0b7f77c460cf0a475c40d (1363)
--     ... then 436, 437 and 438 in any allowed order (436 437 438,
--         436 438 437, 437 436 438)                               f9464b8e06c2769987a3050cd7278900 (1363)
--     ... then 437 and 438, in either order (no 436)              165bef9a08e801aa36e7bccb2a896ee7 (1290)
--     (436 alone 0e7e9dee71d0559fb447bab0f4ddec3d 1353; 436 and 438
--     90001617fefe0c0cf92b7eec7548ae4f 1353; 438 alone
--     5dab2dce6f2665297dc387a2e106fb54 1280: this file changes none of
--     theirs, and the function lists and grants are identical whatever the
--     order)
--
-- DEPLOY ORDER (each with the Owner's go-ahead)
--
--   1. This file, after 430 (Wednesday's run sheet), before, between or
--      after 436 and 438 (438 after 436).
--   2. The pages (push main; Vercel): AffiliateJoinPage, AffiliateVerifyPage,
--      AffiliateAccountPage, AffiliateLoginPage, AffiliatesPage, AuthContext,
--      App.tsx and src/lib/affiliateEmail.ts. Before step 3 the old sign-up function still answers, and
--      the Join page then shows the old "check your email" screen. The
--      Affiliates page reads the new fields (waiting, the phone box's
--      default, kind, the commission earned) and works without them; its
--      Unlink window says what an unlink leads to with this file in (a
--      record of their own at the next sign-in, no claim).
--   3. supabase functions deploy auth-signup-request --no-verify-jwt
--      supabase functions deploy auth-resend-verification --no-verify-jwt
--      (their shared code changed: flows.ts, admin.ts, pipeline.ts,
--      templates.ts, liveDeps.ts). auth-request-recovery shares flows.ts and
--      pipeline.ts and the others admin.ts or templates.ts, with no change in
--      what they do: they need no redeploy. admin-invite-user needs none
--      either (WHAT THIS DOES 4 is in the database alone).
--   4. The one-off repair for the 14 unconfirmed logins, dry run first:
--      scripts/repairs/affiliate-stuck-signups-437.sql. It needs only step 1,
--      so it can run any time after it; until it runs, those 14 cannot sign
--      in with their password (the login page offers to send their sign-up
--      link again, which still finishes the sign-up, or to contact Energia).
--   Steps 2-3 need step 1: the pages read email_verified_at and the new
--   functions, and work without them (no badge, no list).
--
-- Test: scripts/affiliate-signup/tests/straight-in-437.sql (begin ...
-- rollback; it installs this file twice; its seminar part runs where 436 is
-- in and is skipped, with a NOTE, where it is not); the Affiliates page:
-- scripts/affiliate-claims/tests/affiliates-page-437.test.mjs.

set lock_timeout = '5s';

do $mig$
declare
  -- The functions this installs, in order: signature, BEFORE md5 (null:
  -- new), AFTER md5, who may call a new one (true: signed-in logins; false:
  -- the service role alone; a changed one keeps its grants), and the text
  -- (as pg_get_functiondef gives it back).
  c_sig constant text[] := array[
    'affiliate_session_from_email_link()',
    'affiliate_signup_candidates(uuid,text,text,text)',
    'affiliate_signup_match_kinds(uuid,text,text,text)',
    'affiliate_signup_fresh_history(uuid,uuid)',
    'affiliate_email_verification_needed(text)',
    'confirm_affiliate_email()',
    'complete_affiliate_onboarding(text,text,text,boolean)',
    'affiliate_signup_matches_open()',
    'link_affiliate_signup(uuid,uuid,text,uuid,boolean)',
    'keep_affiliate_signup_separate(uuid,text)',
    'confirm_affiliate_signup_same_person(uuid,text)',
    'invite_user_provisioned(uuid,uuid)'];
  c_before constant text[] := array[null, null, null, null, null, null,
    'ff59dd1f8a6ca7397efea5880c6a87a7', null, null, null, null, '7219cae03a5a758402e79762baf46f42'];
  c_after constant text[] := array[
    'd0f5ab3b19eecc6211262821bcbee600',
    'a9233b065de981e00e76143c0aa94ac7',
    '2157bdf60e165a7ace6d9ee2c476ab92',
    '48f892efdc678c40ad3a3dd8b97a0c32',
    'd6173ed6952e48c7a1b67cd106f45b71',
    '431ff39aa4fe42ec9b1442e65a044676',
    '88ee10799d1c93ce93d0056740f05e01',
    'e6c198839c224ca62dce59d3cb4bfb4e',
    '198780b31301695db55c4a39ba9618f8',
    '45b09a6843b0c569e90447485e238a78',
    'a9a1f6c2d37284e1e19d898ebdd203e6',
    '6b895cc341bacbe9e115e28982d661e3'];
  c_client constant boolean[] := array[false, false, false, false, false, true, true, true, true, true, true, false];
  c_def constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.affiliate_session_from_email_link()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 437: whether the caller's session was opened from an emailed link in the
  -- last 30 minutes, as the token's "amr" records it: a sign-in link (the
  -- Account page's verification email), a password reset, an invitation, or
  -- the sign-up link of the old flow. Opening one shows the person reads that
  -- mailbox. The 30 minutes are auth-change-password's and
  -- auth-accept-invitation's (429).
  select coalesce((
    select bool_or(e ->> 'method' in ('magiclink', 'otp', 'recovery', 'invite', 'email/signup')
                   and coalesce(e ->> 'timestamp', '') ~ '^[0-9]{1,12}(\.[0-9]+)?$'
                   and to_timestamp((e ->> 'timestamp')::double precision)
                       between now() - interval '30 minutes' and now() + interval '1 minute')
      from jsonb_array_elements(case when jsonb_typeof(auth.jwt() -> 'amr') = 'array'
                                     then auth.jwt() -> 'amr' else '[]'::jsonb end) e), false)
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_signup_candidates(p_fresh uuid, p_phone text, p_name text, p_email text)
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 437: the customers in use a sign-up's fresh record may be (at most 10):
  -- those with its phone, those whose stored number could be it (an 8-digit
  -- number that could be Singapore or Malaysia, as 425 reads it), those with
  -- the same inbox (customer_email_match_key), and those whose name has the
  -- same words (customer_names_match), in that order, oldest first.
  with w as (
    select public.normalize_customer_phone(p_phone) as ph,
           public.customer_email_match_key(p_email) as ek,
           public.customer_name_words(p_name) as words),
  c as (
    select c.id, 1 as rank, c.created_at from public.customers c, w
     where c.deleted_at is null and w.ph is not null and public.normalize_customer_phone(c.phone) = w.ph
    union all
    select c.id, 2, c.created_at from public.customers c, w
     where c.deleted_at is null and w.ph is not null and public.normalize_customer_phone(c.phone) is null
       and c.phone ~ '^[\s().0-9-]+$' and (public.inspect_customer_phone(c.phone) -> 'candidates') ? w.ph
    union all
    select c.id, 3, c.created_at from public.customers c, w
     where c.deleted_at is null and w.ek is not null and public.customer_email_match_key(c.email) = w.ek
    union all
    -- A first look that costs little: every word typed is in the record's
    -- name written together, cleaned as customer_name_words cleans it. Only
    -- those are compared word for word.
    select c.id, 4, c.created_at from public.customers c, w
     where c.deleted_at is null and cardinality(w.words) > 0
       and (select bool_and(strpos(regexp_replace(regexp_replace(lower(left(coalesce(c.full_name, ''), 200)),
                                                                '\([^)]*\)', ' ', 'g'),
                                                 '[[:space:][:punct:]$+<=>^`|~]+', '', 'g'), x) > 0)
              from unnest(w.words) x)
       and public.customer_names_match(c.full_name, p_name)),
  d as (
    select distinct on (c.id) c.id, c.rank, c.created_at from c
     where c.id is distinct from p_fresh
     order by c.id, c.rank),
  t as (select d.id, d.rank, d.created_at from d order by d.rank, d.created_at, d.id limit 10)
  select coalesce(array_agg(t.id order by t.rank, t.created_at, t.id), '{}'::uuid[]) from t
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_signup_match_kinds(p_customer uuid, p_phone text, p_name text, p_email text)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 437: how a customer may be a sign-up's fresh record: 'phone' (the same
  -- number, or a stored number that could be it), 'email' (the same inbox)
  -- and 'name' (the name exactly, or the same words). Empty: neither.
  select coalesce((
    select array_remove(array[
      case when public.normalize_customer_phone(c.phone) = public.normalize_customer_phone(p_phone) then 'phone'
           when public.normalize_customer_phone(c.phone) is null and public.normalize_customer_phone(p_phone) is not null
                and c.phone ~ '^[\s().0-9-]+$'
                and (public.inspect_customer_phone(c.phone) -> 'candidates') ? public.normalize_customer_phone(p_phone) then 'phone' end,
      case when public.customer_email_match_key(c.email) = public.customer_email_match_key(p_email) then 'email' end,
      case when (public.normalize_customer_match_name(p_name) <> ''
                 and public.normalize_customer_match_name(c.full_name) = public.normalize_customer_match_name(p_name))
                or public.customer_names_match(c.full_name, p_name) then 'name' end], null)
      from public.customers c where c.id = p_customer), '{}'::text[])
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_signup_fresh_history(p_fresh uuid, p_affiliate uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 437: what a sign-up's fresh record (p_fresh, its affiliate record
  -- p_affiliate) has done as an affiliate: 'referrals' (a customer it
  -- referred, deleted or not), 'sales' (an invoice under its affiliate
  -- record or naming it as the affiliate), 'exchanges', 'commission'
  -- (earned, or a correction), 'payouts' (paid, or a deduction settled) and
  -- 'rewards' (a referral campaign's). Empty: nothing. Linked to a customer
  -- with an affiliate record of their own, the fresh record's is retired only
  -- while this is empty (link_affiliate_signup).
  select array_remove(array[
    case when exists (select 1 from public.customers r where r.referred_by = p_fresh) then 'referrals' end,
    case when exists (select 1 from public.invoices i where i.affiliate_id = p_affiliate)
           or exists (select 1 from public.invoices i where i.affiliate_snapshot_customer_id = p_fresh) then 'sales' end,
    case when exists (select 1 from public.product_exchanges x where x.exchange_affiliate_id = p_affiliate) then 'exchanges' end,
    case when exists (select 1 from public.commissions c where c.referrer_customer_id = p_fresh)
           or exists (select 1 from public.commission_corrections c where c.customer_id = p_fresh) then 'commission' end,
    case when exists (select 1 from public.commission_payouts p where p.referrer_customer_id = p_fresh)
           or exists (select 1 from public.affiliate_deduction_settlements s where s.referrer_customer_id = p_fresh) then 'payouts' end,
    case when exists (select 1 from public.referral_campaign_rewards w where w.referrer_customer_id = p_fresh) then 'rewards' end],
    null)
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_email_verification_needed(p_email text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 437: whether the address belongs to a confirmed login with an affiliate
  -- account whose email is not verified yet. auth-resend-verification asks
  -- it (with the service key) before it sends the Account page's
  -- verification email; the answer never reaches the browser.
  select exists (select 1 from auth.users u
                   join public.affiliate_accounts a on a.auth_user_id = u.id
                  where lower(btrim(u.email)) = lower(btrim(coalesce(p_email, '')))
                    and u.deleted_at is null and u.email_confirmed_at is not null
                    and a.email_verified_at is null)
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.confirm_affiliate_email()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid(); v_acct public.affiliate_accounts%rowtype;
begin
  -- 437 (the Owner, 20 Oct 2026): an affiliate verifies their email later,
  -- from the Account page. Its email holds a sign-in link to
  -- /affiliate/verify; a session opened from it in the last 30 minutes marks
  -- the email verified. Nothing waits on it: the portal, the referral link,
  -- commission and payouts work the same before.
  if v_uid is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid for update;
  if not found then return jsonb_build_object('verified', false, 'reason', 'not_affiliate'); end if;
  if v_acct.email_verified_at is not null then
    return jsonb_build_object('verified', true, 'already', true, 'verified_at', v_acct.email_verified_at);
  end if;
  if not public.affiliate_session_from_email_link() then
    return jsonb_build_object('verified', false, 'reason', 'not_from_email_link');
  end if;
  update public.affiliate_accounts set email_verified_at = now(), updated_at = now()
   where id = v_acct.id returning * into v_acct;
  -- Kept on the login too (app_metadata, which only the server writes), so
  -- the account made at its next sign-in after an Owner unlinks it (378)
  -- starts verified; and the login no longer counts as one the sign-up
  -- confirmed on an address nobody proved (invite_user_provisioned).
  update auth.users
     set raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified')
                             || jsonb_build_object('affiliate_email_verified_at', v_acct.email_verified_at)
   where id = v_uid;
  -- Written straight into audit_logs (an affiliate has no staff profile for
  -- write_audit_ex to record), as sign-up's own rows are (432).
  begin
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, module)
    values ('affiliate_accounts', v_acct.id, 'affiliate_email_verified',
      jsonb_build_object('email_verified_at', null),
      jsonb_build_object('auth_user_id', v_uid, 'customer_id', v_acct.customer_id,
                         'email_verified_at', v_acct.email_verified_at),
      'affiliate');
  exception when others then
    raise warning '437: the email verification audit row was not saved: %', sqlerrm;
  end;
  return jsonb_build_object('verified', true, 'already', false, 'verified_at', v_acct.email_verified_at);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.complete_affiliate_onboarding(p_first_name text, p_last_name text, p_phone text, p_agree boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_email text; v_confirmed timestamptz; v_app jsonb; v_meta jsonb;
  v_first text; v_last text; v_raw_phone text; v_name text; v_phone text;
  v_acct public.affiliate_accounts%rowtype; v_aff public.customer_affiliates%rowtype;
  v_code text; v_suspended boolean := false;
  -- 437: the customers in use with the phone, those whose stored number could
  -- be it, those the name picks, the customer joined and by which rule, why a
  -- fresh record is listed for staff and whom it may be, the pending claims
  -- closed, the list entry, and whether the email counts as verified.
  v_holders uuid[]; v_maybe uuid[]; v_named uuid[]; v_target uuid; v_rule text; v_reason text;
  v_cust uuid; v_created boolean := false; v_cands uuid[] := '{}'::uuid[]; v_claim_cands uuid[] := '{}'::uuid[];
  v_claims int := 0; v_match uuid; v_verified timestamptz;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  -- Staff or Affiliate, never both. Checked before anything is written.
  if exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'STAFF_ACCOUNT: This is a staff login, so it cannot also be an affiliate account. Sign out and use a personal email address, or ask an Owner to set the affiliate up against the right customer record.'
      using errcode = '42501';
  end if;
  if not coalesce(p_agree, false) then raise exception 'You must agree to the Affiliate terms to continue'; end if;

  select lower(btrim(u.email)), u.email_confirmed_at, coalesce(u.raw_app_meta_data, '{}'::jsonb),
         coalesce(u.raw_user_meta_data, '{}'::jsonb)
    into v_email, v_confirmed, v_app, v_meta
    from auth.users u where u.id = v_uid;
  if coalesce(v_email, '') = '' then raise exception 'No email on the authenticated account'; end if;
  -- 437: a login is confirmed before it can sign in at all ("Confirm email"
  -- stays on in Supabase Auth); the sign-up function creates it confirmed.
  -- Kept as a backstop.
  if v_confirmed is null then raise exception 'Please verify your email before completing signup'; end if;

  -- Already onboarded? Answer before asking for anything (333).
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id = v_acct.affiliate_id;
    return jsonb_build_object('status', case when v_aff.manually_suspended then 'suspended' else 'active' end,
      'customer_id', v_acct.customer_id, 'referral_code', v_aff.referral_code, 'already', true,
      'email_verified', v_acct.email_verified_at is not null);
  end if;

  -- 437: a login whose claim was rejected stays rejected, whatever it enters
  -- (before, a phone and an email no customer had still made it a customer).
  if exists (select 1 from public.affiliate_account_claims where auth_user_id = v_uid and status = 'rejected') then
    return jsonb_build_object('status', 'rejected',
      'message', 'Account verification was unsuccessful. Please contact Energia for assistance.');
  end if;

  -- Arguments first; otherwise what the sign-up stored on the account (333).
  v_first     := nullif(btrim(coalesce(p_first_name, '')), '');
  v_last      := nullif(btrim(coalesce(p_last_name,  '')), '');
  v_raw_phone := nullif(btrim(coalesce(p_phone,      '')), '');
  if v_first is null and v_last is null then
    v_first := nullif(btrim(coalesce(v_meta->>'first_name', '')), '');
    v_last  := nullif(btrim(coalesce(v_meta->>'last_name',  '')), '');
  end if;
  if v_raw_phone is null then v_raw_phone := nullif(btrim(coalesce(v_meta->>'phone', '')), ''); end if;

  v_name  := btrim(coalesce(v_first, '') || ' ' || coalesce(v_last, ''));
  v_phone := public.normalize_customer_phone(v_raw_phone);
  if v_name = '' or v_raw_phone is null then
    raise exception 'DETAILS_REQUIRED: Enter your name and a valid international phone number.'; end if;
  if v_phone is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;

  -- One sign-up at a time for this login, then for this phone; asked again
  -- under the lock, so a second press of Create Account answers "already".
  perform pg_advisory_xact_lock(hashtextextended('affiliate-onboarding:' || v_uid::text, 0));
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id = v_acct.affiliate_id;
    return jsonb_build_object('status', case when v_aff.manually_suspended then 'suspended' else 'active' end,
      'customer_id', v_acct.customer_id, 'referral_code', v_aff.referral_code, 'already', true,
      'email_verified', v_acct.email_verified_at is not null);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_phone, 0));

  -- 437 (the Owner, 20 Oct 2026, 7): the customers in use with this phone,
  -- and those whose stored number could be it (an 8-digit number that could
  -- be Singapore or Malaysia, as 425 reads it). One customer has it, and no
  -- other may: join them on the phone alone.
  select coalesce(array_agg(c.id order by c.created_at, c.id), '{}'::uuid[]) into v_holders
    from public.customers c
   where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_phone;
  select coalesce(array_agg(c.id order by c.created_at, c.id), '{}'::uuid[]) into v_maybe
    from public.customers c
   where c.deleted_at is null and public.normalize_customer_phone(c.phone) is null
     and c.phone ~ '^[\s().0-9-]+$'
     and (public.inspect_customer_phone(c.phone) -> 'candidates') ? v_phone;

  if cardinality(v_holders) = 1 and cardinality(v_maybe) = 0 then
    v_target := v_holders[1]; v_rule := 'phone';
  elsif cardinality(v_holders) > 0 then
    -- 8: several may have it. Join the one with the name exactly as typed;
    -- failing that, the one whose name has the same words (432's
    -- customer_names_match). Otherwise a fresh record, listed for staff.
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_named
      from public.customers c
     where c.id = any (v_holders) and public.normalize_customer_match_name(v_name) <> ''
       and public.normalize_customer_match_name(c.full_name) = public.normalize_customer_match_name(v_name);
    if cardinality(v_named) = 1 then
      v_target := v_named[1]; v_rule := 'phone_and_name';
    elsif cardinality(v_named) = 0 then
      select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_named
        from public.customers c
       where c.id = any (v_holders) and public.customer_names_match(c.full_name, v_name);
      if cardinality(v_named) = 1 then v_target := v_named[1]; v_rule := 'phone_and_same_words'; end if;
    end if;
    if v_target is null then v_reason := 'shared_phone'; end if;
  elsif cardinality(v_maybe) > 0 then
    -- Only a stored number that could be this one: not joined on it.
    v_reason := 'phone_unconfirmed';
  end if;

  -- The safeguards kept: never joined by itself to a customer who already
  -- has a portal login (one each), one an Owner unlinked a login from (378),
  -- one an Owner or Manager rejected a claim for (379), or one whose
  -- affiliate record was removed. A fresh record instead, listed for staff.
  if v_target is not null then
    v_reason := case
      when exists (select 1 from public.affiliate_accounts a where a.customer_id = v_target) then 'customer_has_login'
      when exists (select 1 from public.audit_logs l
                    where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
                      and l.actor_role = 'owner' and l.module = 'affiliate'
                      and l.old_data->>'customer_id' = v_target::text)
        or exists (select 1 from public.audit_logs l
                    where l.table_name = 'affiliate_account_claims' and l.action = 'affiliate_claim_rejected'
                      and l.actor_role in ('owner', 'manager') and l.module = 'affiliate'
                      and l.new_data->>'candidate_customer_id' = v_target::text) then 'protected_customer'
      when exists (select 1 from public.customer_affiliates ca
                    where ca.customer_id = v_target and ca.deleted_at is not null) then 'affiliate_removed'
    end;
    if v_reason is not null then v_target := null; v_rule := null; end if;
  end if;

  if v_target is not null then
    v_cust := v_target;
  else
    -- A fresh record. When 3 customers already have the phone, the phone
    -- rule (CUSTOMER_PHONE_LIMIT) refuses it, and the person enters another.
    insert into public.customers (full_name, phone, email, is_active)
      values (v_name, v_phone, v_email, true)
      returning id into v_cust;
    v_created := true; v_rule := 'fresh';
  end if;

  select * into v_aff from public.customer_affiliates where customer_id = v_cust and deleted_at is null;
  if not found then
    v_code := public.generate_affiliate_referral_code();
    insert into public.customer_affiliates (customer_id, status, manually_suspended, activated_at, referral_code)
      values (v_cust, 'active', false, now(), v_code)
      returning * into v_aff;
  else
    v_suspended := v_aff.manually_suspended;
    if v_aff.referral_code is null then
      update public.customer_affiliates set referral_code = public.generate_affiliate_referral_code(), updated_at = now()
       where id = v_aff.id returning * into v_aff;
    end if;
  end if;

  -- 437 (2): the app's own "email verified". Yes, from that day, when the
  -- login says it was verified before (app_metadata
  -- affiliate_email_verified_at: an account an Owner unlinked, 378); yes
  -- when Supabase Auth confirmed the login through its email link (every
  -- login before 437); no when the sign-up function or the 437 repair
  -- confirmed it (app_metadata.affiliate_email_unverified; the server alone
  -- sets either); yes now when this session was opened from an emailed link,
  -- which the login then keeps too.
  v_verified := case
    when coalesce(v_app->>'affiliate_email_verified_at', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
      then (v_app->>'affiliate_email_verified_at')::timestamptz
    when coalesce(v_app->>'affiliate_email_unverified', '') = 'true' then null
    else v_confirmed end;
  if v_verified is null and public.affiliate_session_from_email_link() then
    v_verified := now();
    update auth.users
       set raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified')
                               || jsonb_build_object('affiliate_email_verified_at', v_verified)
     where id = v_uid;
  end if;

  -- An entry still open for this login is for a customer it is no longer on
  -- (an Owner unlinked it: it had no account until now). It goes; an entry
  -- made below takes its place.
  delete from public.affiliate_signup_matches where auth_user_id = v_uid and status = 'open';

  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status, last_login_at, email_verified_at)
    values (v_uid, v_cust, v_aff.id, 'claimed', now(), v_verified)
    returning * into v_acct;

  -- 437 (5): a pending claim of this login is settled the new way: closed,
  -- the person in. Whom it suggested is listed with a fresh record.
  with closed as (
    update public.affiliate_account_claims
       set status = 'resolved', resolved_at = now(),
           resolution_note = '437: let in at sign-in (the Owner, 20 Oct 2026)'
     where auth_user_id = v_uid and status = 'pending'
    returning candidate_customer_id)
  select count(*)::int, coalesce(array_agg(candidate_customer_id) filter (where candidate_customer_id is not null), '{}'::uuid[])
    into v_claims, v_claim_cands from closed;

  -- 437 (6): a fresh record that may be a customer already there is listed
  -- on the Affiliates page, for an Owner or Manager to link or keep apart.
  -- The person is not told, and never sees the other names.
  if v_created then
    v_cands := public.affiliate_signup_candidates(v_cust, v_phone, v_name, v_email);
    v_cands := v_cands || coalesce(array(
      select x from unnest(v_claim_cands) x
       where x <> all (v_cands) and x <> v_cust
         and exists (select 1 from public.customers c where c.id = x and c.deleted_at is null)), '{}'::uuid[]);
    if v_reason is null and cardinality(v_cands) > 0 then
      v_reason := case
        when exists (select 1 from public.customers c where c.id = any (v_cands)
                      and public.customer_email_match_key(c.email) = public.customer_email_match_key(v_email)) then 'email_match'
        when exists (select 1 from public.customers c where c.id = any (v_cands) and c.id <> all (v_claim_cands)) then 'name_match'
        else 'earlier_claim' end;
    end if;
    if v_reason is not null then
      insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, entered_phone, entered_name, reason, candidate_ids)
        values (v_uid, v_cust, v_phone, v_name, v_reason, v_cands)
        on conflict do nothing
        returning id into v_match;
    end if;
  elsif v_rule = 'phone'
        and not exists (select 1 from public.customers c
                         where c.id = v_cust
                           and ((public.normalize_customer_match_name(v_name) <> ''
                                 and public.normalize_customer_match_name(c.full_name) = public.normalize_customer_match_name(v_name))
                                or public.customer_names_match(c.full_name, v_name))) then
    -- AFF-SIGNUP-18 (the Owner, 21 Oct 2026): joined on the phone alone (7)
    -- under a name that is not the record's (not the same words): the join
    -- stays as it is, and it is listed for an Owner or Manager as "may be
    -- someone else" (a family member on the household phone, say), with the
    -- name typed and the record's. Same person closes the entry
    -- (confirm_affiliate_signup_same_person); someone else: an Owner unlinks
    -- the login (378) and the person gets a record of their own at their
    -- next sign-in. It is never linked (there is no new record to merge):
    -- the entry names the customer joined. The person is not told.
    v_reason := 'phone_other_name';
    insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, entered_phone, entered_name, reason, candidate_ids)
      values (v_uid, v_cust, v_phone, v_name, v_reason, '{}'::uuid[])
      on conflict do nothing
      returning id into v_match;
  end if;

  -- Written straight into audit_logs, with no one signed in recorded (432).
  -- It cannot stop the sign-up. It says which rule joined the customer or
  -- that a fresh record was made, and why it is listed.
  begin
    insert into public.audit_logs (table_name, record_id, action, new_data, module)
    values ('affiliate_accounts', v_acct.id, 'affiliate_portal_claimed',
      jsonb_build_object('customer_id', v_cust, 'affiliate_id', v_aff.id, 'auth_user_id', v_uid,
        'new_customer', v_created, 'rule', v_rule, 'listed_for_staff', v_reason, 'match_id', v_match,
        'claims_closed', v_claims, 'email_verified', v_verified is not null, 'version', 437),
      'affiliate');
  exception when others then
    raise warning '437: the sign-up audit row was not saved: %', sqlerrm;
  end;

  return jsonb_build_object('status', case when v_suspended then 'suspended' else 'active' end,
    'customer_id', v_cust, 'referral_code', v_aff.referral_code, 'already', false,
    'new_customer', v_created, 'email_verified', v_verified is not null);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_signup_matches_open()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb; v_keys text[]; v_fresh uuid[];
        v_sem jsonb := '{}'::jsonb; v_qr jsonb := '{}'::jsonb; v_sem_on boolean := false;
begin
  -- 437 (the Owner, 20 Oct 2026, 6): affiliates who signed up on a fresh
  -- record that may be a customer already there, for an Owner or Manager on
  -- the Affiliates page. Each with the customers it may be: those listed at
  -- sign-up, and anyone with the record's phone now; and how each matches.
  -- And what the Link box shows (AFF-SIGNUP-12..14): the phone and email
  -- they signed up with (entered_phone, login_email) beside each customer's,
  -- what Link would do with the email, the new record's code and each
  -- customer's own (linked to them, the new one is retired), and the twin
  -- flag: a customer with the very same phone and a name of the same words
  -- who already has an affiliate login.
  -- AFF-SIGNUP-16 (the Owner, 21 Oct 2026): what waits under To match for
  -- each fresh record ('waiting': seminar registrations and QR health forms
  -- held with it as a candidate), and for each customer whether the Link
  -- box's "use the phone they signed up with" starts ticked, and why
  -- (use_signup_phone_default, use_signup_phone_why): ticked when the email
  -- they signed up with cannot be copied onto the customer (they keep their
  -- own, 'email_keep_own', or another customer has it, 'email_in_use'), or
  -- when something of this sign-up waits under To match ('waiting_seminar',
  -- 'waiting_qr'); otherwise unticked. No box when the customer has that
  -- phone already ('same_phone').
  -- AFF-SIGNUP-18: a login joined to a customer on the phone alone under
  -- another name ('phone_other_name', kind 'may_be_someone_else'): the name
  -- typed beside the record's, and no customer to link (it is never merged).
  perform public.require_active_staff(array['owner', 'manager']);
  -- The inboxes the open entries' logins signed up with
  -- (customer_email_match_key).
  select coalesce(array_agg(distinct k.ek) filter (where k.ek is not null), '{}'::text[]) into v_keys
    from public.affiliate_signup_matches m
    join auth.users u on u.id = m.auth_user_id
    cross join lateral (select public.customer_email_match_key(u.email) as ek) k
   where m.status = 'open';
  -- AFF-SIGNUP-16: what waits under To match for each fresh record listed,
  -- read once for the whole list: 433's QR health forms still held with it
  -- as a candidate, and 436's seminar registrations still held with it as a
  -- candidate. 436 may come after this file, so its table is read by name,
  -- only when it is there (seminar: null when it is not).
  select coalesce(array_agg(distinct m.fresh_customer_id), '{}'::uuid[]) into v_fresh
    from public.affiliate_signup_matches m
   where m.status = 'open' and m.reason <> 'phone_other_name';
  v_sem_on := to_regclass('public.event_registration_people') is not null;
  if cardinality(v_fresh) > 0 then
    select coalesce(jsonb_object_agg(f.id, f.n), '{}'::jsonb) into v_qr
      from (select x.id, count(distinct h.survey_id) as n
              from public.health_survey_holds h
              cross join lateral unnest(h.candidate_customer_ids) x(id)
             where h.resolved_at is null and x.id = any (v_fresh)
             group by x.id) f;
    if v_sem_on then
      begin
        execute $q$
          select coalesce(jsonb_object_agg(f.id, f.n), '{}'::jsonb)
            from (select x.id, count(distinct p.id) as n
                    from public.event_registration_people p
                    cross join lateral unnest(p.candidate_customer_ids) x(id)
                   where p.match = 'held' and not p.is_test and x.id = any ($1)
                   group by x.id) f$q$
          into v_sem using v_fresh;
      exception when undefined_table or undefined_column then
        v_sem_on := false; v_sem := '{}'::jsonb;
      end;
    end if;
  end if;
  with holders as materialized (
    -- The customers in use with one of those inboxes, read once for the whole
    -- list (the page waits on it). The key has no index, so it is worked out
    -- only for an address that, trimmed and in lower case, or read as a Gmail
    -- address (no dots, no +tag), is one of those inboxes: the two things the
    -- key can be (customer_email_match_key as 432 wrote it; 437 pins it).
    select e.id, public.customer_email_match_key(e.email) as ek
      from public.customers e
     where cardinality(v_keys) > 0 and e.deleted_at is null and e.email is not null
       and (lower(btrim(e.email)) = any (v_keys)
            or replace(split_part(split_part(lower(btrim(e.email)), '@', 1), '+', 1), '.', '') || '@gmail.com' = any (v_keys)))
  select coalesce(jsonb_agg(x.j order by x.created_at, x.id), '[]'::jsonb) into v
    from (
      select m.id, m.created_at, jsonb_build_object(
        'match_id', m.id, 'signed_up_at', m.created_at, 'reason', m.reason,
        -- AFF-SIGNUP-18: 'may_be_someone_else' for a login joined on the
        -- phone alone under another name (the customer is the record it
        -- joined, entered_name the name typed); otherwise 'fresh_record'.
        'kind', case when m.reason = 'phone_other_name' then 'may_be_someone_else' else 'fresh_record' end,
        'entered_name', m.entered_name, 'entered_phone', m.entered_phone,
        'customer_id', c.id, 'customer_name', c.full_name, 'phone', c.phone, 'email', c.email,
        'login_email', u.email, 'referral_code', ca.referral_code,
        'referrals', (select count(*) from public.customers r where r.referred_by = c.id and r.deleted_at is null),
        -- AFF-SIGNUP-13: until it is sorted out, 436's website registrations,
        -- VIP payments and 433's QR health forms find two customers with this
        -- phone and name, and wait under To match.
        'twin', m.reason <> 'phone_other_name' and cardinality(tw.ids) > 0,
        'twin_customer_id', case when m.reason <> 'phone_other_name' then tw.ids[1] end,
        -- AFF-SIGNUP-16: held under To match with the fresh record as a
        -- candidate (seminar null before 436).
        'waiting', case when m.reason <> 'phone_other_name'
                        then jsonb_build_object('seminar', case when v_sem_on then wt.seminar end, 'qr', wt.qr) end,
        'candidates', case when m.reason = 'phone_other_name' then '[]'::jsonb else coalesce((
          select jsonb_agg(jsonb_build_object(
                   'customer_id', k.id, 'name', k.full_name, 'phone', k.phone, 'email', k.email,
                   'created_at', k.created_at,
                   'matched_by', to_jsonb(public.affiliate_signup_match_kinds(k.id, c.phone, c.full_name, u.email)),
                   'has_login', exists (select 1 from public.affiliate_accounts aa where aa.customer_id = k.id),
                   'protected', exists (select 1 from public.audit_logs l
                                         where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
                                           and l.actor_role = 'owner' and l.module = 'affiliate'
                                           and l.old_data->>'customer_id' = k.id::text)
                             or exists (select 1 from public.audit_logs l
                                         where l.table_name = 'affiliate_account_claims' and l.action = 'affiliate_claim_rejected'
                                           and l.actor_role in ('owner', 'manager') and l.module = 'affiliate'
                                           and l.new_data->>'candidate_customer_id' = k.id::text),
                   -- The customer's own affiliate record (a login an Owner
                   -- unlinked leaves it), kept with its code when they are
                   -- linked: the new record's is retired (AFF-SIGNUP-9), and
                   -- links shared with it stop crediting anyone (14).
                   'own_referral_code', (select ck.referral_code from public.customer_affiliates ck
                                          where ck.customer_id = k.id and ck.deleted_at is null),
                   'retires_new_code', exists (select 1 from public.customer_affiliates ck
                                                where ck.customer_id = k.id and ck.deleted_at is null),
                   -- What Link does with the email they signed up with (12):
                   -- 'copy' (the customer has none), 'keep_own', 'in_use'
                   -- (another customer has it: left) or 'none'.
                   'email_on_link', el.eol,
                   -- AFF-SIGNUP-16: how the Link box's phone tick starts.
                   'use_signup_phone_default', cardinality(pb.why) > 0
                                               and not (pb.why && array['same_phone', 'no_signup_phone']),
                   'use_signup_phone_why', to_jsonb(pb.why),
                   'twin', k.id = any (tw.ids),
                   'problem', case
                     when exists (select 1 from public.affiliate_accounts aa where aa.customer_id = k.id)
                       then 'This customer already has an affiliate login.'
                     when exists (select 1 from public.customer_affiliates ck where ck.customer_id = k.id and ck.deleted_at is not null)
                       then 'This customer''s affiliate record was removed, so the new affiliate cannot be linked to them here. Keep them separate.'
                     when exists (select 1 from public.customer_affiliates ck where ck.customer_id = k.id)
                          and cardinality(h.history) > 0
                       then 'This customer already has an affiliate record of their own, and the new record already has '
                            || array_to_string(h.history, ', ')
                            || '. Which referral code and commission history to keep is a decision about money: settle that first.'
                   end)
                 order by (k.id = any (m.candidate_ids)) desc, k.created_at, k.id)
            from public.customers k
            cross join lateral (
              select case
                when nullif(btrim(coalesce(k.email, '')), '') is not null then 'keep_own'
                when public.customer_email_match_key(u.email) is null then 'none'
                when exists (select 1 from unnest(eh.ids) x where x <> k.id) then 'in_use'
                else 'copy' end as eol) el
            cross join lateral (
              select case
                when public.normalize_customer_phone(m.entered_phone) is null then array['no_signup_phone']
                when public.normalize_customer_phone(k.phone) = public.normalize_customer_phone(m.entered_phone)
                  then array['same_phone']
                else array_remove(array[
                  case el.eol when 'keep_own' then 'email_keep_own' when 'in_use' then 'email_in_use' end,
                  case when wt.seminar > 0 then 'waiting_seminar' end,
                  case when wt.qr > 0 then 'waiting_qr' end], null) end as why) pb
           where k.deleted_at is null and k.id <> c.id
             and (k.id = any (m.candidate_ids)
                  or public.normalize_customer_phone(k.phone) = public.normalize_customer_phone(c.phone))), '[]'::jsonb) end
      ) as j
        from public.affiliate_signup_matches m
        join public.affiliate_accounts a on a.auth_user_id = m.auth_user_id and a.customer_id = m.fresh_customer_id
        join public.customers c on c.id = m.fresh_customer_id and c.deleted_at is null
        left join auth.users u on u.id = m.auth_user_id
        left join public.customer_affiliates ca on ca.id = a.affiliate_id
        -- What the new record has done as an affiliate since (referrals,
        -- sales, commission...): with it, a customer with an affiliate record
        -- of their own cannot be linked here.
        cross join lateral (select public.affiliate_signup_fresh_history(c.id, a.affiliate_id) as history) h
        -- The other customers in use with the inbox they signed up with.
        cross join lateral (
          select coalesce(array_agg(h.id), '{}'::uuid[]) as ids
            from holders h
           where h.id <> c.id and h.ek = public.customer_email_match_key(u.email)) eh
        -- The twins: the very same phone, a name with the same words (or the
        -- same name), and an affiliate login of their own.
        cross join lateral (
          select coalesce(array_agg(t.id order by t.created_at, t.id), '{}'::uuid[]) as ids
            from public.customers t
           where t.deleted_at is null and t.id <> c.id
             and public.normalize_customer_phone(t.phone) = public.normalize_customer_phone(c.phone)
             and exists (select 1 from public.affiliate_accounts aa where aa.customer_id = t.id)
             and ((public.normalize_customer_match_name(c.full_name) <> ''
                   and public.normalize_customer_match_name(t.full_name) = public.normalize_customer_match_name(c.full_name))
                  or public.customer_names_match(t.full_name, c.full_name))) tw
        -- AFF-SIGNUP-16: what waits under To match for this fresh record.
        cross join lateral (select coalesce((v_sem ->> c.id::text)::int, 0) as seminar,
                                   coalesce((v_qr ->> c.id::text)::int, 0) as qr) wt
       where m.status = 'open') x;
  return v;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.link_affiliate_signup(p_match_id uuid, p_customer_id uuid, p_note text, p_request_id uuid, p_use_signup_phone boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.affiliate_signup_matches%rowtype; a public.affiliate_accounts%rowtype; k public.customers%rowtype;
        v_fresh public.customers%rowtype; v_email text; v_note text := nullif(btrim(coalesce(p_note, '')), '');
        v_res jsonb; v_kaff public.customer_affiliates%rowtype; v_faff public.customer_affiliates%rowtype;
        v_history text[]; v_aff_before uuid; v_code_retired text; n int;
        -- AFF-SIGNUP-12: what the link puts on the customer (the email they
        -- signed up with, the phone when ticked), why the email is left, the
        -- reason kept with the merge and the change, the step under way, and
        -- the customer's phone and email afterwards.
        v_changes jsonb := '{}'::jsonb; v_email_skip text; v_phone text; v_reason text; v_step text;
        v_after public.customers%rowtype; v_notes text[] := '{}'::text[];
        -- AFF-SIGNUP-17: the fresh record's invoices the merge moves, the one
        -- being earned and its package and bundle sales, the Link day, and
        -- what was earned or not, per invoice; on a replay, what the link did
        -- (its audit row).
        v_moved_inv uuid[]; r_inv record; r_sale record; v_i public.invoices%rowtype; v_today date; v_rows jsonb;
        v_earned jsonb := '[]'::jsonb; v_not_earned jsonb := '[]'::jsonb; v_done jsonb;
begin
  -- 437 (the Owner, 20 Oct 2026, 6): an Owner or Manager links an affiliate
  -- on a fresh record to the customer already there. The fresh record joins
  -- that customer through merge_customer_records, unchanged: the affiliate
  -- login, the affiliate record and its referral code, and the referrals
  -- made meanwhile come with it; the fresh record is retired. The affiliate
  -- does nothing.
  -- A customer with an affiliate record of their own (a login an Owner
  -- unlinked leaves it, 378) keeps it, with its code: the login moves onto it
  -- and the fresh record's own, unused one is retired, then the merge runs.
  -- Only while the fresh record has done nothing as an affiliate (no
  -- referral, sale, exchange, commission, payout, settlement or reward);
  -- otherwise which code and history to keep is a decision about money.
  -- AFF-SIGNUP-12 (the Owner, 20 Oct 2026): the email they signed up with is
  -- copied onto the customer when the customer has none, unless another
  -- customer in use has it already (customer_email_match_key): then it is
  -- left, and the answer says so. Ticked on the Link box
  -- (p_use_signup_phone), the customer's phone becomes the one they signed
  -- up with, the way the Customers page changes a phone (update_customer: a
  -- reason, the phone history, at most 3 customers to a phone). Refused, the
  -- whole link is refused and nothing changes. Unticked, the customer keeps
  -- their phone.
  -- AFF-SIGNUP-17 (the Owner, 21 Oct 2026): a paid invoice the merge moves
  -- that earned no commission at all (the fresh record had no referrer)
  -- earns it now when the customer has a referrer, dated the Link day; see
  -- below. A phone-only join listed as "may be someone else" (AFF-SIGNUP-18)
  -- has no new record and is never linked.
  perform public.require_active_staff(array['owner', 'manager']);
  if p_request_id is null then raise exception 'A request id is required'; end if;
  if p_customer_id is null then raise exception 'Choose the customer to link to'; end if;
  select * into m from public.affiliate_signup_matches where id = p_match_id for update;
  if not found then raise exception 'This sign-up is not listed any more. Reload the page.'; end if;
  if m.status = 'linked' and m.decision_request_id = p_request_id then
    -- A retry after a lost answer: nothing is linked, changed or earned
    -- again, and the answer says what the link did, read back from its
    -- audit row (the commission it earned or not, the email and the phone).
    select l.new_data into v_done from public.audit_logs l
     where l.record_id = m.id and l.table_name = 'affiliate_signup_matches' and l.action = 'affiliate_signup_linked'
       and l.new_data ->> 'request_id' = p_request_id::text
     order by l.created_at desc, l.id desc limit 1;
    return jsonb_build_object('ok', true, 'replayed', true, 'customer_id', m.linked_customer_id,
      'retired', m.fresh_customer_id, 'moved', v_done -> 'moved',
      'kept_own_affiliate', coalesce((v_done ->> 'kept_own_affiliate')::boolean, false),
      'email_copied', case when (v_done ->> 'email_copied')::boolean then v_done ->> 'customer_email' end,
      'email_not_copied', v_done ->> 'email_not_copied',
      'phone_changed', coalesce((v_done ->> 'phone_changed')::boolean, false), 'phone', v_done ->> 'customer_phone',
      'notes', coalesce(v_done -> 'notes', '[]'::jsonb),
      'commission_dated', v_done -> 'commission_dated',
      'commission_earned', coalesce(v_done -> 'commission_earned', '[]'::jsonb),
      'commission_not_earned', coalesce(v_done -> 'commission_not_earned', '[]'::jsonb));
  end if;
  if m.reason = 'phone_other_name' then
    return jsonb_build_object('ok', false, 'message', 'This sign-up was joined to the customer on the phone alone, so there is no new record to link. If it is the same person, press Same person; if it is someone else, an Owner unlinks the login (Unlink login).');
  end if;
  if m.status <> 'open' then
    return jsonb_build_object('ok', false, 'message', case m.status
      when 'linked' then 'This sign-up was linked to a customer already. Reload the page.'
      else 'This sign-up was kept as a separate customer already. Reload the page.' end);
  end if;
  select * into a from public.affiliate_accounts where auth_user_id = m.auth_user_id for update;
  -- Both records are locked before anything is read from them, in the
  -- merge's order (the lower id first): a change saved meanwhile (Staff
  -- adding the customer's email, say) comes first and is seen here, or
  -- waits for the link. So what is decided below, and the audit row's
  -- "before", is what the merge and the change then find.
  perform 1 from public.customers where id = least(p_customer_id, m.fresh_customer_id) for update;
  perform 1 from public.customers where id = greatest(p_customer_id, m.fresh_customer_id) for update;
  select * into v_fresh from public.customers where id = m.fresh_customer_id;
  if a.id is null or a.customer_id is distinct from m.fresh_customer_id or v_fresh.id is null or v_fresh.deleted_at is not null then
    return jsonb_build_object('ok', false, 'message', 'This affiliate''s record has changed since the sign-up was listed. Reload the page.');
  end if;
  select * into k from public.customers where id = p_customer_id;
  if k.id is null or k.deleted_at is not null then
    return jsonb_build_object('ok', false, 'message', 'That customer was not found, or is deleted.');
  end if;
  if k.id = m.fresh_customer_id then
    return jsonb_build_object('ok', false, 'message', 'That is the affiliate''s own record.');
  end if;
  select lower(btrim(u.email)) into v_email from auth.users u where u.id = m.auth_user_id;
  -- Only a customer listed for this sign-up: one listed when it was made, or
  -- one whose phone, email or name matches the record now.
  if not (k.id = any (m.candidate_ids)
          or cardinality(public.affiliate_signup_match_kinds(k.id, v_fresh.phone, v_fresh.full_name, v_email)) > 0) then
    return jsonb_build_object('ok', false, 'message', 'Link only to a customer listed for this sign-up.');
  end if;
  if exists (select 1 from public.affiliate_accounts x where x.customer_id = k.id) then
    return jsonb_build_object('ok', false, 'message', 'This customer already has an affiliate login.');
  end if;
  v_aff_before := a.affiliate_id;
  select * into v_kaff from public.customer_affiliates where customer_id = k.id;
  if found then
    if v_kaff.deleted_at is not null then
      return jsonb_build_object('ok', false, 'message', 'This customer''s affiliate record was removed, so the new affiliate cannot be linked to them here. Keep them separate.');
    end if;
    select * into v_faff from public.customer_affiliates where id = a.affiliate_id;
    if v_faff.id is null or v_faff.customer_id is distinct from m.fresh_customer_id then
      return jsonb_build_object('ok', false, 'message', 'This affiliate''s record has changed since the sign-up was listed. Reload the page.');
    end if;
    v_history := public.affiliate_signup_fresh_history(m.fresh_customer_id, a.affiliate_id);
    if cardinality(v_history) > 0 then
      return jsonb_build_object('ok', false, 'message', 'This customer already has an affiliate record of their own, and the new record already has '
        || array_to_string(v_history, ', ') || '. Which referral code and commission history to keep is a decision about money: settle that first.');
    end if;
  end if;

  -- AFF-SIGNUP-12: the email they signed up with (their login's), when the
  -- customer has none and no other customer in use has it.
  if nullif(btrim(coalesce(k.email, '')), '') is not null then
    v_email_skip := 'customer_has_email';
  elsif public.customer_email_match_key(v_email) is null then
    v_email_skip := 'no_email';
  elsif exists (select 1 from public.customers c
                 where c.deleted_at is null and c.id <> k.id and c.id <> m.fresh_customer_id
                   and public.customer_email_match_key(c.email) = public.customer_email_match_key(v_email)) then
    v_email_skip := 'in_use';
    v_notes := v_notes || ('The email they signed up with, ' || v_email || ', was not copied onto ' || k.full_name
                           || ': another customer already has it.');
  else
    v_changes := v_changes || jsonb_build_object('email', v_email);
  end if;
  -- Ticked: the phone they signed up with (as the entry kept it), unless the
  -- customer has it already.
  if coalesce(p_use_signup_phone, false) then
    v_phone := public.normalize_customer_phone(m.entered_phone);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'message', 'No phone was kept from their sign-up. Untick "use the phone they signed up with" and link again.');
    end if;
    if public.normalize_customer_phone(k.phone) is distinct from v_phone then
      v_changes := v_changes || jsonb_build_object('phone', v_phone);
    end if;
  end if;
  v_reason := 'Affiliate sign-up linked to the customer already there (Affiliates page)' || coalesce(': ' || v_note, '');
  -- AFF-SIGNUP-17: the fresh record's invoices, which the merge moves onto
  -- the customer (read with both records locked).
  v_moved_inv := array(select i.id from public.invoices i where i.customer_id = m.fresh_customer_id order by i.created_at, i.id);

  -- All of it, or nothing: a phone the phone rule refuses undoes the merge
  -- too, and the new record's code retired just before it, so every step
  -- that changes something stays inside this block (the refusal returns
  -- from it). The phone changes after the merge, so the fresh record's place
  -- on it (the merge retires it) passes to the customer.
  begin
    if v_kaff.id is not null then
      -- The login moves onto the customer's own affiliate record; the fresh
      -- record's, unused, goes, so the merge sees one affiliate.
      v_code_retired := v_faff.referral_code;
      update public.affiliate_accounts set affiliate_id = v_kaff.id, updated_at = now() where id = a.id;
      delete from public.customer_affiliates where id = v_faff.id and customer_id = m.fresh_customer_id;
      get diagnostics n = row_count;
      if n <> 1 then raise exception '437: the new record''s affiliate record could not be retired; nothing was changed'; end if;
    end if;

    v_res := public.merge_customer_records(k.id, m.fresh_customer_id, v_reason, p_request_id);
    if not exists (select 1 from public.affiliate_accounts x where x.auth_user_id = m.auth_user_id and x.customer_id = k.id
                      and (v_kaff.id is null or x.affiliate_id = v_kaff.id)) then
      raise exception '437: the merge did not move the affiliate login; nothing was changed';
    end if;

    if v_changes <> '{}'::jsonb then
      -- No stale-edit check (null): the customer has been locked since it
      -- was read above.
      v_step := 'customer';
      perform public.update_customer(k.id, v_changes, v_reason, null);
      v_step := null;
    end if;
  exception when sqlstate '23514' then
    if v_step = 'customer' and sqlerrm like 'CUSTOMER_PHONE_LIMIT:%' then
      return jsonb_build_object('ok', false, 'phone_refused', true, 'message',
        'The phone they signed up with, ' || v_phone || ', already belongs to 3 customers, so it cannot become '
        || k.full_name || '''s phone. Nothing was linked or changed. Untick "use the phone they signed up with" and link again.');
    end if;
    raise;
  end;
  select * into v_after from public.customers where id = k.id;

  -- AFF-SIGNUP-17 (the Owner, 21 Oct 2026): a paid invoice the fresh record
  -- bought earned no commission (it had no referrer). Moved onto a customer
  -- who has one, it earns it now, as at payment, through the engine's own
  -- functions, unchanged, in the order reconcile_invoice_commissions runs
  -- them: earn_invoice_commission for its lines (tier 1 the invoice's chosen
  -- affiliate or else the customer's referrer, tier 2 tier 1's referrer, no
  -- commission on a customer's own purchase or on an invoice that names no
  -- affiliate on purpose, a referrer who may not earn gets a blocked row; it
  -- leaves out credit package and premium bundle lines), then
  -- earn_credit_package_commission and earn_premium_bundle_commission for
  -- each package and bundle sale on it that the merge moved to the customer
  -- (as payment earns them, through issue_credit_lines_for_invoice: on the
  -- money paid less what was refunded of it, by the same rules; a share of
  -- a split package given to someone else is theirs, and stays as payment
  -- left it), then the refund step
  -- (adjust_invoice_line_commission_refunds) for a refund already recorded;
  -- all dated the Link day in Singapore (the engine dates by the day the
  -- invoice was paid; 436 dates a VIP earned at a check the same way, R6-5),
  -- so the Link does not change a month already paid out. (If the engine
  -- later works that invoice out again, a correction, a refund or a
  -- reopening through reconcile_invoice_commissions, what it earns again is
  -- dated by the invoice's paid date, as for any invoice.) Only a paid
  -- invoice with no commission row at all, asked again with it locked: one
  -- with any row is left alone, and a replay (same request id, answered
  -- above) earns nothing. Each invoice on its own: one the engine refuses
  -- keeps none of its rows (nothing half earned), is named in the answer,
  -- and the link stands.
  if v_after.referred_by is not null then
    v_today := public.sg_today();
    for r_inv in select i.id, i.invoice_no from public.invoices i
                  where i.id = any (v_moved_inv) and i.customer_id = k.id and i.deleted_at is null and i.status::text = 'paid'
                    and not exists (select 1 from public.commissions c where c.invoice_id = i.id)
                  order by i.paid_at nulls last, i.invoice_no, i.id loop
      begin
        select * into v_i from public.invoices where id = r_inv.id for update;
        continue when v_i.status::text <> 'paid' or v_i.deleted_at is not null or v_i.customer_id <> k.id
                      or exists (select 1 from public.commissions c where c.invoice_id = r_inv.id);
        perform public.earn_invoice_commission(r_inv.id);
        for r_sale in select s.id from public.credit_package_sales s where s.invoice_id = r_inv.id and s.customer_id = k.id
                       order by s.sold_at, s.id loop
          perform public.earn_credit_package_commission(r_sale.id);
        end loop;
        for r_sale in select s.id from public.premium_bundle_sales s where s.invoice_id = r_inv.id and s.customer_id = k.id
                       order by s.sold_at, s.id loop
          perform public.earn_premium_bundle_commission(r_sale.id);
        end loop;
        perform public.adjust_invoice_line_commission_refunds(r_inv.id, null);
        update public.commissions set invoice_paid_date = v_today where invoice_id = r_inv.id;
        select coalesce(jsonb_agg(jsonb_build_object('tier', t.tier, 'referrer_customer_id', t.referrer_customer_id,
                                                     'referrer_name', t.referrer_name, 'status', t.status,
                                                     'block_reason', t.block_reason, 'amount', t.amount)
                                  order by t.tier, t.referrer_name, t.status), '[]'::jsonb)
          into v_rows
          from (select c.tier::text as tier, c.referrer_customer_id, rc.full_name as referrer_name, c.status::text as status,
                       c.block_reason, sum(c.commission_amount) as amount
                  from public.commissions c left join public.customers rc on rc.id = c.referrer_customer_id
                 where c.invoice_id = r_inv.id
                 group by 1, 2, 3, 4, 5) t;
        if v_rows = '[]'::jsonb then
          v_not_earned := v_not_earned || jsonb_build_array(jsonb_build_object('invoice_id', r_inv.id,
            'invoice_no', r_inv.invoice_no, 'why', 'none_due'));
        else
          v_earned := v_earned || jsonb_build_array(jsonb_build_object('invoice_id', r_inv.id,
            'invoice_no', r_inv.invoice_no, 'paid_at', v_i.paid_at, 'dated', v_today, 'rows', v_rows,
            'amount', (select coalesce(sum(c.commission_amount), 0) from public.commissions c
                        where c.invoice_id = r_inv.id and c.status::text = 'earned')));
        end if;
      exception when others then
        v_not_earned := v_not_earned || jsonb_build_array(jsonb_build_object('invoice_id', r_inv.id,
          'invoice_no', r_inv.invoice_no, 'why', 'refused', 'message', sqlerrm));
      end;
    end loop;
  end if;

  update public.affiliate_signup_matches
     set status = 'linked', decided_at = now(), decided_by = auth.uid(), decision_note = v_note,
         linked_customer_id = k.id, decision_request_id = p_request_id
   where id = m.id;
  perform public.write_audit_ex('affiliate_signup_matches', m.id, 'affiliate_signup_linked',
    jsonb_build_object('status', 'open', 'fresh_customer_id', m.fresh_customer_id, 'reason', m.reason,
                       'customer_phone', k.phone, 'customer_email', k.email),
    jsonb_build_object('status', 'linked', 'customer_id', k.id, 'fresh_customer_id', m.fresh_customer_id,
                       'auth_user_id', m.auth_user_id, 'moved', v_res->'moved', 'request_id', p_request_id,
                       'affiliate_id_before', v_aff_before, 'affiliate_id', coalesce(v_kaff.id, v_aff_before),
                       'referral_code_kept', v_kaff.referral_code, 'referral_code_retired', v_code_retired,
                       'customer_phone', v_after.phone, 'customer_email', v_after.email,
                       'use_signup_phone', coalesce(p_use_signup_phone, false), 'phone_changed', v_changes ? 'phone',
                       'email_copied', v_changes ? 'email', 'email_not_copied', v_email_skip,
                       'kept_own_affiliate', v_kaff.id is not null, 'notes', to_jsonb(v_notes),
                       'referrer_customer_id', v_after.referred_by, 'commission_dated', v_today,
                       'commission_earned', v_earned, 'commission_not_earned', v_not_earned),
    'affiliate', v_note);
  return jsonb_build_object('ok', true, 'customer_id', k.id, 'retired', m.fresh_customer_id, 'moved', v_res->'moved',
    'kept_own_affiliate', v_kaff.id is not null,
    'email_copied', v_changes->>'email', 'email_not_copied', v_email_skip,
    'phone_changed', v_changes ? 'phone', 'phone', v_after.phone, 'notes', to_jsonb(v_notes),
    'commission_dated', v_today, 'commission_earned', v_earned, 'commission_not_earned', v_not_earned);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.keep_affiliate_signup_separate(p_match_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.affiliate_signup_matches%rowtype; v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  -- 437: an Owner or Manager answers that the affiliate on a fresh record is
  -- not the customer listed (a family member sharing the phone, say). It
  -- leaves the list; nothing else changes. Not for a phone-only join listed
  -- as "may be someone else" (AFF-SIGNUP-18): there the login is on the
  -- customer's own record, so keeping it "separate" would leave it there.
  perform public.require_active_staff(array['owner', 'manager']);
  if v_note is null then raise exception 'Say why they are a different person; it is kept in the Audit Log'; end if;
  select * into m from public.affiliate_signup_matches where id = p_match_id for update;
  if not found then raise exception 'This sign-up is not listed any more. Reload the page.'; end if;
  if m.reason = 'phone_other_name' then
    return jsonb_build_object('ok', false, 'message', 'This sign-up was joined to the customer on the phone alone, so there is no separate record to keep. If it is someone else, an Owner unlinks the login (Unlink login) and they get a record of their own at their next sign-in; if it is the same person, press Same person.');
  end if;
  if m.status <> 'open' then
    return jsonb_build_object('ok', false, 'message', case m.status
      when 'linked' then 'This sign-up was linked to a customer already. Reload the page.'
      else 'This sign-up was kept as a separate customer already. Reload the page.' end);
  end if;
  update public.affiliate_signup_matches
     set status = 'kept_separate', decided_at = now(), decided_by = auth.uid(), decision_note = v_note
   where id = m.id;
  perform public.write_audit_ex('affiliate_signup_matches', m.id, 'affiliate_signup_kept_separate',
    jsonb_build_object('status', 'open', 'fresh_customer_id', m.fresh_customer_id, 'reason', m.reason),
    jsonb_build_object('status', 'kept_separate', 'fresh_customer_id', m.fresh_customer_id,
                       'auth_user_id', m.auth_user_id, 'candidate_ids', to_jsonb(m.candidate_ids)),
    'affiliate', v_note);
  return jsonb_build_object('ok', true);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.confirm_affiliate_signup_same_person(p_match_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.affiliate_signup_matches%rowtype; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_name text;
begin
  -- 437 (AFF-SIGNUP-18, the Owner, 21 Oct 2026): a login joined to a
  -- customer on the phone alone under another name is listed as "may be
  -- someone else". An Owner or Manager who checked that it is the customer
  -- (another way of writing the name, say) closes the entry here, with a
  -- note; nothing else changes. If it is someone else, an Owner unlinks the
  -- login instead (unlink_affiliate_account, 378): the entry then leaves the
  -- list, and the person gets a record of their own at their next sign-in.
  perform public.require_active_staff(array['owner', 'manager']);
  if v_note is null then raise exception 'Say how you checked it is the same person; it is kept in the Audit Log'; end if;
  select * into m from public.affiliate_signup_matches where id = p_match_id for update;
  if not found then raise exception 'This sign-up is not listed any more. Reload the page.'; end if;
  if m.reason <> 'phone_other_name' then
    return jsonb_build_object('ok', false, 'message', 'Same person is only for a sign-up joined to a customer on the phone alone. Use Link to this customer or Keep separate.');
  end if;
  if m.status <> 'open' then
    return jsonb_build_object('ok', false, 'message', 'This sign-up was checked already. Reload the page.');
  end if;
  if not exists (select 1 from public.affiliate_accounts a where a.auth_user_id = m.auth_user_id and a.customer_id = m.fresh_customer_id) then
    return jsonb_build_object('ok', false, 'message', 'This login is not on that customer any more (an Owner unlinked it). Reload the page.');
  end if;
  select c.full_name into v_name from public.customers c where c.id = m.fresh_customer_id;
  update public.affiliate_signup_matches
     set status = 'same_person', decided_at = now(), decided_by = auth.uid(), decision_note = v_note
   where id = m.id;
  perform public.write_audit_ex('affiliate_signup_matches', m.id, 'affiliate_signup_same_person',
    jsonb_build_object('status', 'open', 'customer_id', m.fresh_customer_id, 'reason', m.reason),
    jsonb_build_object('status', 'same_person', 'customer_id', m.fresh_customer_id, 'customer_name', v_name,
                       'entered_name', m.entered_name, 'auth_user_id', m.auth_user_id),
    'affiliate', v_note);
  return jsonb_build_object('ok', true);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.invite_user_provisioned(p_invitation_id uuid, p_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare inv public.user_invitations%rowtype; v_store uuid;
begin
  perform set_config('energia.profile_privilege_change', 'on', true);

  select * into inv from public.user_invitations where id = p_invitation_id for update;
  if not found then raise exception 'Invitation not found'; end if;
  if inv.status <> 'pending' then
    -- 413: cancelled while its login was being made. The login exists now:
    -- tie it to the invitation and, unless it is already someone's (a profile
    -- or an affiliate account), close it as a cancelled invitee. 412 then
    -- signs it out and blocks it, and its invitation link is refused. The
    -- Edge Function sends no email for this answer.
    if inv.status = 'cancelled' and inv.auth_user_id is null then
      update public.user_invitations
         set auth_user_id = p_auth_user_id, updated_at = now()
       where id = p_invitation_id;
      if not exists (select 1 from public.profiles p where p.id = p_auth_user_id)
         and not exists (select 1 from public.affiliate_accounts a where a.auth_user_id = p_auth_user_id)
         -- 437: nor a login the affiliate sign-up made whose email is not
         -- verified yet: a cancelled profile on it would let a later
         -- invitation use that login again.
         and not exists (select 1 from auth.users u where u.id = p_auth_user_id
                          and coalesce(u.raw_app_meta_data ->> 'affiliate_email_unverified', '') = 'true') then
        -- 429: removed too (a deleted date), as invite_user_cancel now does,
        -- so the address can be invited again.
        insert into public.profiles (id, full_name, email, role, is_active,
                                     work_phone, personal_phone, personal_email, invitation_status, deleted_at)
        values (p_auth_user_id, inv.full_name, inv.email, inv.role, false,
                inv.work_phone, inv.personal_phone, inv.personal_email, 'cancelled', now())
        on conflict do nothing;
        if found then
          update public.user_invitations set profile_id = p_auth_user_id where id = p_invitation_id;
        end if;
      end if;
    end if;
    return jsonb_build_object('outcome', inv.status, 'message','This invitation is no longer pending.');
  end if;

  -- 429: a login that is already someone's (a live member of staff's
  -- profile, or an affiliate account) is never made an invitee. Nothing is
  -- tied and no email is sent.
  -- 437: nor a login the affiliate sign-up made whose email is not verified
  -- yet (app_metadata affiliate_email_unverified, which only the server
  -- sets). The sign-up confirms whatever address is typed, so whoever made
  -- it may not own the mailbox, and the invitee would set up their password
  -- on a login someone else holds.
  if exists (select 1 from public.affiliate_accounts a where a.auth_user_id = p_auth_user_id)
     or exists (select 1 from auth.users u where u.id = p_auth_user_id
                 and coalesce(u.raw_app_meta_data ->> 'affiliate_email_unverified', '') = 'true')
     or exists (select 1 from public.profiles p where p.id = p_auth_user_id and p.deleted_at is null
                 and coalesce(p.invitation_status, 'accepted') not in ('pending', 'cancelled')) then
    return jsonb_build_object('outcome','login_in_use',
      'message','That login already belongs to someone in this system. No email was sent.');
  end if;

  -- 429: the login of someone invited before who never accepted (their
  -- invitation was cancelled), or of a member of staff who was removed (the
  -- Owner, 10 Oct 2026), is used again, so their history stays linked to it.
  -- What their profile was is kept in the audit log first. Then it is put
  -- back as this invitation's: pending, switched off, not removed, with this
  -- invitation's stores only. 412 then lifts the block it placed when they
  -- were cancelled or removed, so the new link works.
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  select 'profiles', p.id, 'user_invitation_login_reused',
         jsonb_build_object('full_name', p.full_name, 'role', p.role, 'is_active', p.is_active,
                            'invitation_status', p.invitation_status, 'deleted_at', p.deleted_at,
                            'store_ids', (select coalesce(jsonb_agg(s.store_id order by s.store_id), '[]')
                                            from public.user_store_assignments s where s.user_id = p.id)),
         jsonb_build_object('invitation_id', inv.id, 'role', inv.role, 'invitation_status', 'pending',
                            'store_ids', to_jsonb(coalesce(inv.store_ids, '{}'))),
         inv.invited_by
    from public.profiles p
   where p.id = p_auth_user_id and (p.deleted_at is not null or p.invitation_status = 'cancelled');

  insert into public.profiles (id, full_name, email, role, is_active,
                               work_phone, personal_phone, personal_email, invitation_status)
  values (p_auth_user_id, inv.full_name, inv.email, inv.role, false,
          inv.work_phone, inv.personal_phone, inv.personal_email, 'pending')
  on conflict (id) do update
    set full_name = excluded.full_name, role = excluded.role,
        work_phone = excluded.work_phone, personal_phone = excluded.personal_phone,
        personal_email = excluded.personal_email,
        is_active = false, invitation_status = 'pending', deleted_at = null,
        updated_at = now();

  delete from public.user_store_assignments s
   where s.user_id = p_auth_user_id and not (s.store_id = any (coalesce(inv.store_ids, '{}')));

  foreach v_store in array coalesce(inv.store_ids, '{}') loop
    insert into public.user_store_assignments (user_id, store_id)
    values (p_auth_user_id, v_store) on conflict (user_id, store_id) do nothing;
  end loop;

  update public.user_invitations
     set auth_user_id = p_auth_user_id, profile_id = p_auth_user_id, updated_at = now()
   where id = p_invitation_id;

  return jsonb_build_object('outcome','provisioned','invitation_id', p_invitation_id);
end $function$
$def$];
  -- The functions relied on and not changed, as the stack after 430 has them.
  c_relied constant text[] := array[
    'customer_names_match(text,text)', 'customer_name_words(text)', 'customer_email_match_key(text)',
    'normalize_customer_phone(text)', 'normalize_customer_match_name(text)', 'inspect_customer_phone(text,text)',
    'merge_customer_records(uuid,uuid,text,uuid)', 'require_active_staff(text[])', 'is_owner_or_manager()',
    'current_user_role()', 'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'generate_affiliate_referral_code()',
    -- AFF-SIGNUP-12: the Customers page's change of a customer (418), with
    -- the phone history and the 3-per-phone rule its update fires.
    'update_customer(uuid,jsonb,text,timestamp with time zone)', 'audit_customer_phone_change()',
    'enforce_customer_phone_policy()',
    -- AFF-SIGNUP-17: the commission engine and its refund step, which Link
    -- calls as payment and 436's check do, and the Singapore day it dates by;
    -- and the engine's package and bundle commission, which payment earns
    -- through issue_credit_lines_for_invoice.
    'earn_invoice_commission(uuid)', 'adjust_invoice_line_commission_refunds(uuid,uuid[])', 'sg_today()',
    'earn_credit_package_commission(uuid)', 'earn_premium_bundle_commission(uuid)'];
  c_relied_md5 constant text[] := array[
    'ef1af52e4888cefb6037a2291f4e011d', 'a7507abf0f15abd923dff59508b269c1', 'be468815c9626fff1728e2cfcd484b66',
    'b2bfac910e0c9eff402ba44e19750bee', '0572764712e179dc606c66f9f3dbaa03', '6672c4d1963996f3b601896f4a55916e',
    '099ecf3aae30b5faaf8fb36bc15ce888', '877b3aa74cea559881979bb161c450e2', 'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '519b0a33a3548f970c5d585b6e76a389', 'c705c733e213a27f0dc32d54322cc855', '29ae3d463f13788ccf88a952eb3e70b8',
    '6511100316418394409d8baf1d2b52e0', '414b5857bccb5b06d7ef3278dc754617', '009273025173c6666a0ecf0408cb7ce1',
    '6156b2e1ee51da5146a5a7acc16091ce', '5959dec0fedd5fd45fb4615da413b20c', '1c1289f18e24d8370e9a6364c9c06fca',
    '13ce59fd892c027338a41de4113ae55d', 'b75ffbea70fd020e75d1ddf4f7b06ba1'];
  -- The new table's columns, as information_schema gives them.
  c_table_shape constant text :=
    'id uuid NO gen_random_uuid()|auth_user_id uuid NO |fresh_customer_id uuid NO |entered_phone text YES '
    || '|entered_name text YES |reason text NO |candidate_ids ARRAY NO ''{}''::uuid[]|status text NO ''open''::text'
    || '|created_at timestamp with time zone NO now()|decided_at timestamp with time zone YES '
    || '|decided_by uuid YES |decision_note text YES |linked_customer_id uuid YES |decision_request_id uuid YES ';
  c_constraints constant text[] := array['affiliate_signup_matches_pkey', 'affiliate_signup_matches_auth_user_id_fkey',
    'affiliate_signup_matches_decided_by_fkey', 'affiliate_signup_matches_reason_check',
    'affiliate_signup_matches_status_check', 'affiliate_signup_matches_decided_check'];
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v_acls text[] := '{}'::text[]; v_names text[]; v text; d text; i int; v_added boolean := false;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_u1 uuid; t_u2 uuid; t_u3 uuid; t_inv uuid; t_cust uuid; t_ans jsonb;
begin
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- Each text is the tested one.
  for i in 1 .. cardinality(c_sig) loop
    if md5(c_def[i]) <> c_after[i] then
      raise exception '437: the text of public.% is not the tested one (md5 %)', c_sig[i], md5(c_def[i]); end if;
  end loop;

  -- Each changed function is the BEFORE or the AFTER version; each new one
  -- is missing or the AFTER version.
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      if c_before[i] is not null then raise exception '437: public.% is missing', c_sig[i]; end if;
    else
      d := md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i])));
      if d <> c_after[i] and d is distinct from c_before[i] then
        raise exception '437: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_sig[i], d;
      end if;
    end if;
  end loop;

  -- No other function takes one of these names.
  v_names := array(select split_part(s, '(', 1) from unnest(c_sig) s);
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any (v_names)
     and p.oid::regprocedure::text <> all (c_sig);
  if v is not null then raise exception '437: another function takes one of these names: %', v; end if;

  -- The functions relied on are as the stack after 430 has them.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '437: public.% is missing or not the version this was tested against (430 must be in first). Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if to_regprocedure('auth.jwt()') is null or to_regprocedure('auth.uid()') is null then
    raise exception '437: auth.jwt() and auth.uid() must be there'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'auth' and table_name = 'users'
        and column_name in ('raw_app_meta_data', 'raw_user_meta_data', 'email_confirmed_at', 'deleted_at')) <> 4 then
    raise exception '437: auth.users is not as read'; end if;

  -- affiliate_signup_matches: missing, or exactly this shape.
  if to_regclass('public.affiliate_signup_matches') is not null then
    select string_agg(c.column_name || ' ' || c.data_type || ' ' || c.is_nullable || ' ' || coalesce(c.column_default, ''), '|'
                      order by c.ordinal_position) into v
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'affiliate_signup_matches';
    if v is distinct from c_table_shape then
      raise exception '437: public.affiliate_signup_matches exists and is not this migration''s table (%)', v; end if;
    if (select count(*) from pg_constraint where conrelid = 'public.affiliate_signup_matches'::regclass
          and conname = any (c_constraints)) <> cardinality(c_constraints)
       or (select count(*) from pg_constraint where conrelid = 'public.affiliate_signup_matches'::regclass) <> cardinality(c_constraints)
       or to_regclass('public.affiliate_signup_matches_one_open') is null then
      raise exception '437: public.affiliate_signup_matches is missing one of its constraints, or has another'; end if;
    -- AFF-SIGNUP-18: its reasons and states include the phone-only join
    -- under another name and its Same person answer.
    if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.affiliate_signup_matches'::regclass
          and conname = 'affiliate_signup_matches_reason_check') not like '%''phone_other_name''%'
       or (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.affiliate_signup_matches'::regclass
          and conname = 'affiliate_signup_matches_status_check') not like '%''same_person''%' then
      raise exception '437: public.affiliate_signup_matches is an earlier draft''s (no phone_other_name or same_person)'; end if;
  end if;
  -- AFF-SIGNUP-16: what the list reads of what waits under To match: 433's
  -- QR holds (in production), and 436's seminar registrations when 436 is
  -- in (it may come after this file).
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'health_survey_holds'
         and ((column_name = 'survey_id' and udt_name = 'uuid') or (column_name = 'candidate_customer_ids' and udt_name = '_uuid')
              or (column_name = 'resolved_at' and udt_name = 'timestamptz'))) <> 3 then
    raise exception '437: public.health_survey_holds (433) is missing or not as read'; end if;
  if to_regclass('public.event_registration_people') is not null
     and (select count(*) from information_schema.columns
           where table_schema = 'public' and table_name = 'event_registration_people'
             and ((column_name = 'id' and udt_name = 'uuid') or (column_name = 'match' and udt_name = 'text')
                  or (column_name = 'is_test' and udt_name = 'bool')
                  or (column_name = 'candidate_customer_ids' and udt_name = '_uuid'))) <> 4 then
    raise exception '437: public.event_registration_people (436) is not as read'; end if;
  -- affiliate_accounts.email_verified_at: missing, or a timestamptz with no default.
  select c.data_type || ' ' || c.is_nullable || ' ' || coalesce(c.column_default, '') into v
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'affiliate_accounts' and c.column_name = 'email_verified_at';
  if v is not null and v <> 'timestamp with time zone YES ' then
    raise exception '437: public.affiliate_accounts.email_verified_at exists and is not this migration''s column (%)', v; end if;

  -- What may call each changed function now (kept as it is).
  for i in 1 .. cardinality(c_sig) loop
    v_acls := v_acls || (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig[i]));
  end loop;

  -- ── Changes ─────────────────────────────────────────────────────────────
  -- The app's own "email verified" (2). Added once; the accounts there then
  -- get the date their login was confirmed through its email link.
  if not exists (select 1 from information_schema.columns where table_schema = 'public'
                  and table_name = 'affiliate_accounts' and column_name = 'email_verified_at') then
    alter table public.affiliate_accounts add column email_verified_at timestamptz;
    v_added := true;
  end if;
  comment on column public.affiliate_accounts.email_verified_at is
    '437: when the affiliate''s email was verified (the Account page''s link, or Supabase''s own sign-up link before 437). '
    'Empty: not yet. Nothing waits on it (the Owner, 20 Oct 2026).';
  if v_added then
    update public.affiliate_accounts a set email_verified_at = u.email_confirmed_at
      from auth.users u
     where u.id = a.auth_user_id and a.email_verified_at is null and u.email_confirmed_at is not null
       and coalesce(u.raw_app_meta_data ->> 'affiliate_email_unverified', '') <> 'true';
  end if;

  -- The list of fresh records that may be a customer already there (6).
  if to_regclass('public.affiliate_signup_matches') is null then
    create table public.affiliate_signup_matches (
      id uuid primary key default gen_random_uuid(),
      auth_user_id uuid not null references auth.users(id) on delete cascade,
      -- No foreign key: merge_customer_records moves every column that has
      -- one to customers, and this must keep naming the fresh record.
      fresh_customer_id uuid not null,
      entered_phone text,
      entered_name text,
      reason text not null,
      candidate_ids uuid[] not null default '{}'::uuid[],
      status text not null default 'open',
      created_at timestamptz not null default now(),
      decided_at timestamptz,
      decided_by uuid references public.profiles(id),
      decision_note text,
      linked_customer_id uuid,
      decision_request_id uuid,
      -- 'phone_other_name' (AFF-SIGNUP-18): a login joined to a customer on
      -- the phone alone under another name; fresh_customer_id then names
      -- that customer, and 'same_person' is its Same person answer.
      constraint affiliate_signup_matches_reason_check check (reason in ('shared_phone', 'phone_unconfirmed',
        'customer_has_login', 'protected_customer', 'affiliate_removed', 'email_match', 'name_match', 'earlier_claim',
        'phone_other_name')),
      constraint affiliate_signup_matches_status_check check (status in ('open', 'linked', 'kept_separate', 'same_person')),
      constraint affiliate_signup_matches_decided_check check ((status = 'open') = (decided_at is null))
    );
    create unique index affiliate_signup_matches_one_open on public.affiliate_signup_matches (auth_user_id)
      where status = 'open';
    comment on table public.affiliate_signup_matches is
      '437: an affiliate who signed up on a fresh record that may be a customer already there (phone, email or name), '
      'for an Owner or Manager on the Affiliates page to link (merge_customer_records) or keep separate (the Owner, 20 Oct 2026). '
      'Also a login joined to a customer on the phone alone under another name (phone_other_name), listed as "may be someone else". '
      'Read and written only through complete_affiliate_onboarding, affiliate_signup_matches_open, link_affiliate_signup, '
      'keep_affiliate_signup_separate and confirm_affiliate_signup_same_person.';
  end if;
  alter table public.affiliate_signup_matches enable row level security;
  revoke all on table public.affiliate_signup_matches from public, anon, authenticated;
  grant all on table public.affiliate_signup_matches to service_role;

  -- The functions, each left alone when it is already this version.
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      execute c_def[i];
    end if;
    if c_before[i] is null then
      if c_client[i] then
        execute format('revoke all on function public.%s from public, anon', c_sig[i]);
        execute format('grant execute on function public.%s to authenticated, service_role', c_sig[i]);
      else
        execute format('revoke all on function public.%s from public, anon, authenticated', c_sig[i]);
        execute format('grant execute on function public.%s to service_role', c_sig[i]);
      end if;
    end if;
  end loop;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '437: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if c_before[i] is not null then
      if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acls[i] then
        raise exception '437: the grants of public.% changed', c_sig[i]; end if;
    elsif has_function_privilege('anon', to_regprocedure('public.' || c_sig[i]), 'execute')
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_sig[i]), 'execute') <> c_client[i]
       or not has_function_privilege('service_role', to_regprocedure('public.' || c_sig[i]), 'execute') then
      raise exception '437: public.% is not callable by exactly whom it is for', c_sig[i];
    end if;
  end loop;
  if has_table_privilege('anon', 'public.affiliate_signup_matches', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.affiliate_signup_matches', 'select,insert,update,delete,truncate,references,trigger')
     or not (select relrowsecurity from pg_class where oid = 'public.affiliate_signup_matches'::regclass) then
    raise exception '437: public.affiliate_signup_matches is open to a client role'; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("437 check", @example.invalid, fictional phones no
  -- customer uses); it ends by raising P0437, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select p as x from unnest(array['+61491570110', '+61491570313', '+61491571266', '+61491571491',
                                            '+61491571804', '+61491572549', '+61491572665', '+61491578957']) p
             where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = p)
               and not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) is null
                                  and c.phone ~ '^[\s().0-9-]+$'
                                  and (public.inspect_customer_phone(c.phone) -> 'candidates') ? p)
             limit 2) y;
    if cardinality(t_phones) is distinct from 2 then
      raise exception '437: the self-test found no unused fictional phones'; end if;
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (gen_random_uuid(), '437-check-1-' || t_sfx || '@example.invalid', now(),
            '{"affiliate_email_unverified": true}'::jsonb, '{}'::jsonb)
    returning id into t_u1;
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (gen_random_uuid(), '437-check-2-' || t_sfx || '@example.invalid', now(),
            '{"affiliate_email_unverified": true}'::jsonb,
            jsonb_build_object('first_name', '437 Check', 'last_name', 'New ' || t_sfx, 'phone', t_phones[2]))
    returning id into t_u2;
    insert into public.customers (full_name, phone, email) values ('437 Check Existing ' || t_sfx, t_phones[1], null)
      returning id into t_cust;

    -- 7: the phone alone joins the one customer who has it; the email is
    -- not verified.
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_u1::text, true);
    t_ans := public.complete_affiliate_onboarding('Another', 'Name ' || t_sfx, t_phones[1], true);
    if t_ans->>'status' <> 'active' or (t_ans->>'customer_id')::uuid <> t_cust or (t_ans->>'new_customer')::boolean
       or (t_ans->>'email_verified')::boolean or (t_ans->>'already')::boolean then
      raise exception '437: the self-test''s phone join is not as tested: %', t_ans; end if;
    -- AFF-SIGNUP-18: under another name, so it is listed "may be someone else".
    if not exists (select 1 from public.affiliate_signup_matches m where m.auth_user_id = t_u1 and m.status = 'open'
                     and m.reason = 'phone_other_name' and m.fresh_customer_id = t_cust) then
      raise exception '437: the self-test''s phone join under another name is not listed'; end if;
    t_ans := public.complete_affiliate_onboarding('Another', 'Name ' || t_sfx, t_phones[1], true);
    if not (t_ans->>'already')::boolean or (t_ans->>'customer_id')::uuid <> t_cust
       or (select count(*) from public.affiliate_signup_matches m where m.auth_user_id = t_u1) <> 1 then
      raise exception '437: the self-test''s second press is not as tested: %', t_ans; end if;
    -- A password session does not verify the email; one from an emailed
    -- link does.
    if (public.confirm_affiliate_email()->>'verified')::boolean then
      raise exception '437: the self-test''s password session verified the email'; end if;
    perform set_config('request.jwt.claims', jsonb_build_object('sub', t_u1, 'role', 'authenticated',
      'amr', jsonb_build_array(jsonb_build_object('method', 'magiclink', 'timestamp', floor(extract(epoch from now()))::bigint)))::text, true);
    t_ans := public.confirm_affiliate_email();
    if not (t_ans->>'verified')::boolean or (t_ans->>'already')::boolean
       or (select email_verified_at from public.affiliate_accounts where auth_user_id = t_u1) is null
       or (select raw_app_meta_data ? 'affiliate_email_unverified'
                  or not (raw_app_meta_data ? 'affiliate_email_verified_at') from auth.users where id = t_u1) then
      raise exception '437: the self-test''s email verification is not as tested: %', t_ans; end if;

    -- A phone no one has, details from the account: a fresh record, not
    -- listed (no one it may be).
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', t_u2::text, true);
    t_ans := public.complete_affiliate_onboarding(null, null, null, true);
    if t_ans->>'status' <> 'active' or not (t_ans->>'new_customer')::boolean
       or not exists (select 1 from public.customers c where c.id = (t_ans->>'customer_id')::uuid
                        and c.full_name = '437 Check New ' || t_sfx and c.phone = t_phones[2])
       or exists (select 1 from public.affiliate_signup_matches m where m.auth_user_id = t_u2) then
      raise exception '437: the self-test''s fresh record is not as tested: %', t_ans; end if;

    -- A login the sign-up made on an address, its email not verified, is
    -- not given to a staff invitation for that address, even when it says
    -- it was invited; nor, the invitation cancelled meanwhile, a profile.
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (gen_random_uuid(), '437-check-3-' || t_sfx || '@example.invalid', now(),
            '{"affiliate_email_unverified": true}'::jsonb, '{"invited_to": "energia_internal"}'::jsonb)
    returning id into t_u3;
    insert into public.user_invitations (request_id, email, email_normalized, full_name, role, status)
    values ('437-check-' || t_sfx, '437-check-3-' || t_sfx || '@example.invalid',
            '437-check-3-' || t_sfx || '@example.invalid', '437 Check Invitee', 'manager', 'pending')
    returning id into t_inv;
    t_ans := public.invite_user_provisioned(t_inv, t_u3);
    if t_ans->>'outcome' is distinct from 'login_in_use' or exists (select 1 from public.profiles where id = t_u3)
       or (select auth_user_id from public.user_invitations where id = t_inv) is not null then
      raise exception '437: the self-test''s invitation of a sign-up login is not as tested: %', t_ans; end if;
    update public.user_invitations set status = 'cancelled', cancelled_at = now() where id = t_inv;
    t_ans := public.invite_user_provisioned(t_inv, t_u3);
    if t_ans->>'outcome' is distinct from 'cancelled' or exists (select 1 from public.profiles where id = t_u3) then
      raise exception '437: the self-test''s cancelled invitation of a sign-up login is not as tested: %', t_ans; end if;
    raise exception using errcode = 'P0437', message = '437: self-test done, undone';
  exception when sqlstate 'P0437' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
