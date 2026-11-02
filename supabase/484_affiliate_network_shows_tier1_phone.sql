-- 484_affiliate_network_shows_tier1_phone.sql
--
-- MY NETWORK SHOWS A DIRECT REFERRAL'S (TIER 1) PHONE NUMBER ONLY WHEN THE
-- REFERRAL WAS TOLD ON THE /r/ PAGE THAT THEIR REFERRER WOULD SEE IT, THE
-- LOGIN'S LINK TO ITS RECORD IS PROVEN AND THE AFFILIATE IS ACTIVE; NEVER A
-- TIER 2 NUMBER (the Owner, 31 Oct and 1 Nov 2026)
--
-- (This rebuilds 484's first draft of 31 Oct 2026, which was never applied
-- or committed: that draft sent every Tier 1 number.)
--
-- THE RULE (the Owner's written answers)
--
--   31 Oct 2026 (second round):
--   1. A Tier 1 phone shows only when the affiliate login's link to its
--      customer record is PROVEN: its own sign-up made the record, staff
--      resolved its claim or said "Same person" (or linked its sign-up), or
--      a verified login email equals the record's; otherwise a dash.
--   2. A suspended (or removed) affiliate sees no numbers.
--   3. PDPA: a notice on the /r/ sign-up page; numbers only for referrals who
--      signed up with that notice; every existing referral shows a dash.
--   4. (Done in 482's pages: My Network's Phone column stays hidden until a
--      number arrives.)
--   5. The notice is on the app's /r/ page ONLY. Seminar-website sign-ups
--      (its /signup/<code> calls affiliate_referral_signup with six keys and
--      the public key), event registrations and referrers set by staff show
--      a dash. Tier 2 never gets a phone from the server.
--   1 Nov 2026 (third round):
--   Q1 The /r/ notice is the FULL notice with the opt-out sentence, exactly
--      (version 'r-page-2026-11'). With the inviter's first name
--      (public_affiliate_referral_info.affiliate_name, not blank), {First}
--      being that name:
--        "When you register, {First}, who invited you, will be able to see
--        your name, phone number, bookings and visits, and how much you spend
--        with Energia, in their Energia affiliate account, so they can help
--        you with your visit. They never see your email. If you would rather
--        they did not see your number, tell Energia and we will hide it."
--      With no name (blank, or still loading):
--        "When you register, the person who invited you will be able to see
--        your name, phone number, bookings and visits, and how much you spend
--        with Energia, in their Energia affiliate account, so they can help
--        you with your visit. They never see your email. If you would rather
--        they did not see your number, tell Energia and we will hide it."
--      It is a notice, not consent: no tick box, no "agree". My Network's
--      note sentence (shown only while a Tier 1 number is shown) becomes
--      exactly: "A phone number shows only for a direct referral who
--      registered through your link after being told you would see it. Use
--      it only to help them with their visit." (in place of "Phone numbers
--      are shown for your direct referrals only."). The Owner was told that
--      the inviter's own referrer (the Tier 2 view) also sees the name,
--      bookings and spend but never the number, and asked for no sentence
--      about it.
--   Q2 The 9 logins joined on the phone alone (437) that are not proven:
--      nothing new now (verifying the email on the Account page, or an
--      Owner's Unlink then Link, stay the routes); no new staff button.
--   Q3 Only the number TYPED under the notice shows: if staff later change a
--      told referral's number, a dash (changed back: shown again). A household
--      number (the outcome phone_shared: a phone another customer already
--      holds) shows at once.
--   Q4 The planted-email gap of proof (d) is accepted for now (NOT COVERED
--      gives the monitoring query; close it only if that count rises above
--      0). That answer was given on the order "a blank email filled, then a
--      phone join". The review of 2 Nov 2026 found the reverse order too ("a
--      phone join, then the login fills its own record's blank email"),
--      which that count cannot see: NOT COVERED now describes both orders
--      and gives a second count, and the question goes back to the Owner
--      with the go-ahead.
--   The opt-out ("tell Energia and we will hide it") is done by the
--   developer through the MCP until a staff button exists: HOW TO HIDE ONE
--   REFERRAL'S NUMBER, below.
--
--   So, on the affiliate portal's My Network, a Tier 1 row (a customer in
--   use whose referred_by is the record the login is joined to) carries
--   'phone': its stored number, trimmed (as the staff Downline shows it),
--   only when ALL of these hold; otherwise the key is there with no number
--   (null: a dash on the page):
--   a. the affiliate is active (affiliate_is_active: an affiliate record not
--      removed, not suspended, status active);
--   b. the login's link to its record is proven
--      (affiliate_login_link_proof(auth.uid(), the record) is not null);
--   c. the customer carries a mark (referral_phone_notices) that names THIS
--      referrer and is not withdrawn: the /r/ page made the customer after
--      showing the notice;
--   d. the mark's number (normalized) is the number the record holds now
--      (normalize_customer_phone), and the stored value is a number;
--   e. no mark on the customer is withdrawn (they asked to hide it).
--   Tier 2 rows carry no 'phone' key at all. The staff Downline
--   (customer_downline_visits) is unchanged.
--
-- THE PROOF (affiliate_login_link_proof(login, record) returns the reason,
-- or null when the link is not proven; only rows the server writes are read,
-- each tied to the login's current portal account, status 'claimed', and to
-- that record or any record an Owner or Manager merged into it, followed
-- through the customers_merged rows of the Audit Log, at most 20 deep):
--   own_record      a record in that chain was made in the same transaction
--                   as the account (created_at equal: both default now();
--                   complete_affiliate_onboarding makes both at once);
--   claim_resolved  a claim of the login, status resolved, resolved_by set
--                   (a staff profile: Owner, Manager or Staff), resolved at
--                   the account's created_at (resolve_affiliate_account_claim
--                   makes the account in that transaction; 437's let-in
--                   closes with resolved_by null and does not count);
--   same_person     staff decided the login's sign-up list entry, after the
--                   account was made: 'same_person' on a record in the
--                   chain, or 'linked' to one;
--   verified_email  the account's email_verified_at is set and the login's
--                   email is the record's (customer_email_match_key: the
--                   same inbox, Gmail spellings one).
--   An Owner's Unlink deletes the account, so the next account has a later
--   created_at and older proofs no longer count for it.
--
-- WHY A MARK, AND WHY A SEPARATE SIGN-UP FUNCTION
--
--   The database cannot tell the /r/ page from the seminar website: both
--   call affiliate_referral_signup with the same public key and the same six
--   named keys, and event registrations set referral_source 'affiliate_link'
--   too. So "told" is recorded at the moment of the sign-up, by the call the
--   /r/ page makes: affiliate_referral_signup_with_notice, the six arguments
--   plus p_notice, the notice's version. It calls affiliate_referral_signup
--   UNCHANGED (its checks, limits, answers and errors are the same) and, when
--   that call made a customer (created or phone_shared), marks that customer
--   in the same transaction: the referrer it was made under, the number
--   typed (normalized), the version and the code. Only a version listed in
--   the function (c_notices, each naming one reviewed wording; now only
--   'r-page-2026-11') counts; null, blank, an unknown version, another case
--   or spaces sign up exactly as before, with no mark (never refused). The
--   customer is found as the one made now (created_at = now()), in use, on
--   that number, through that link (referral_source 'affiliate_link', the
--   code, a referrer), and not among those that were there before the call
--   (read after taking the phone's advisory lock, the same one the sign-up
--   takes, so a sign-up on the same number in flight elsewhere is seen). It
--   does not read referral_signup_events (442's suite keeps that table's
--   readers to the sign-up functions). affiliate_referral_signup itself is
--   NOT changed (md5 2942e3d4... before and after, the same grants): the
--   seminar website keeps calling it, its sign-ups can never be marked, and
--   no signed-out endpoint is dropped or re-created (an overload of it, a
--   seventh argument, would make six-key calls ambiguous: PGRST203).
--
-- WHAT THIS DOES
--
--   * New table public.referral_phone_notices (the marks): customer_id (the
--     record the /r/ sign-up made), referrer_customer_id (whose link),
--     phone (the number typed, normalized: E.164), notice_version,
--     referral_code (as typed, trimmed), created_at, withdrawn_at (set when
--     the referral asks for the number to be hidden). Both customer columns
--     reference customers ON DELETE CASCADE, so merge_customer_records' loop
--     over the foreign keys to customers moves a mark with its record and
--     with its referrer (no change to the merge); no unique key and no
--     customer <> referrer check, so no legitimate merge can fail on it.
--     Indexes on both customer columns. Row level security on, no policy;
--     revoked from public, anon, authenticated and the service role, then
--     SELECT granted to the service role (production's default privileges
--     grant every new table ALL to anon, authenticated and service_role).
--   * New function public.affiliate_login_link_proof(uuid, uuid) returns
--     text (THE PROOF, above): LANGUAGE sql STABLE SECURITY DEFINER, search
--     path public; executable by the owner and the service role only.
--   * New function public.affiliate_referral_signup_with_notice(p_code,
--     p_first_name, p_last_name, p_phone, p_email, p_notice, p_honeypot
--     default null), all text, returns jsonb (affiliate_referral_signup's
--     answer, unchanged): plpgsql SECURITY DEFINER, search path public;
--     executable as affiliate_referral_signup is (signed out, signed in, the
--     owner, the service role).
--   * Replaces public.affiliate_portal_network() (480's): made from 480's
--     exact text (md5 d1c387fb...) by three hunks: v_phones declared,
--     v_phones set once per call (a and b), and the Tier 1 'phone' key (c,
--     d, e). Everything else is 480's: signature, plpgsql STABLE SECURITY
--     DEFINER, search path, who the affiliate is, "Not an affiliate
--     account", the rows, every other key, value and the order, the
--     bookings, and the grants (kept by CREATE OR REPLACE).
--
-- WHAT THE PERSON SEES (user-facing)
--
--   Affiliates: at apply nothing changes. There are no marks yet, so every
--   Tier 1 row carries 'phone': null and the pages of push #1 (5d3fa72) show
--   no Phone column, card line or sentence to anyone. After push #2 (the /r/
--   notice), someone who registers through the /r/ link of an active
--   affiliate whose login is proven shows their number on that affiliate's
--   My Network (the Phone column, the card line and the sentence appear for
--   that affiliate). Everyone registered before, by the seminar website, by
--   an event registration or by staff stays a dash. People registering on /r/:
--   the notice above the button (Q1). Staff: nothing changes.
--   Production, 1 Nov 2026 (read only, counts only): 86 portal logins, all
--   claimed. Proven and active 76: claim_resolved 45 (22 with Tier 1
--   customers, 112 rows), own_record 16 (5, 7), verified_email 14 (8, 34),
--   same_person 1 (0); own_record but suspended 1 (no Tier 1); not proven 9
--   (all 437 phone joins; 4 with Tier 1 customers, 5 rows). 158 Tier 1 rows
--   (93 customers in use came through a link), 84 Tier 2 rows, 0 marks.
--   Sign-ups that made a customer: 17 in the last 7 days (the /r/ page and
--   the seminar website together); phone_shared: 2 ever.
--
-- NOT CHANGED
--
--   * affiliate_referral_signup (the seminar website's call): byte for byte,
--     the same grants; customer_downline_visits (the staff Downline);
--     calcom_customer_bookings (480's or 482's, passed through);
--     current_affiliate_customer_id; every other portal function (purchases,
--     earnings, payouts, the dashboard: no phone); the merge; every other
--     table and grant.
--
-- NOT COVERED (told to the Owner)
--
--   * The mark is the page's claim. The public key ships in the browser, so
--     any caller can send a listed p_notice. A referrer who types a friend's
--     details into their own link "tells" nobody, but already knows the
--     number: no number leaks this way. As with any web form, the evidence
--     can be false.
--   * The wrapper relies on affiliate_referral_signup's insert (469's shape:
--     the record made now, the normalized phone, the code, 'affiliate_link'
--     and the referrer). A later change to it that alters that stops the
--     marks silently (no number: the safe direction); its md5 is pinned here
--     and the 484 suite's S and E checks must run whenever it changes.
--   * Proof (d) can be planted (Q4), in either order and with no staff step,
--     because the QR health survey and the event registration form fill a
--     blank email on a record: (1) the blank email of a referrer's record
--     (or of an affiliate record) that has no portal login is filled first;
--     someone then joins that record on the phone (437) and verifies that
--     inbox; (2) a login that 437 joined on the phone alone to a record with
--     no email (not proven, so a dash) fills that email itself, through the
--     QR form with the record's name (the portal shows the login that name)
--     when the record has no survey, or through the event form, and then
--     verifies its own inbox (confirm_affiliate_email). Either way it is then
--     proven (verified_email). Reach on 2 Nov 2026: 0 and 0 (the 9 logins
--     not proven all hold a record with an email). Monitoring queries (read
--     only, counts only; run both with each review; the second needs 484
--     in): the first counts order (1)'s records, the second order (2)'s
--     logins:
--       select count(*) from public.customers r
--        where r.deleted_at is null
--          and (exists (select 1 from public.customers t where t.referred_by = r.id and t.deleted_at is null)
--               or exists (select 1 from public.customer_affiliates f where f.customer_id = r.id and f.deleted_at is null))
--          and not exists (select 1 from public.affiliate_accounts a where a.customer_id = r.id)
--          and nullif(btrim(coalesce(r.email, '')), '') is null;
--       select count(*) from public.affiliate_accounts a join public.customers c on c.id = a.customer_id
--        where a.status = 'claimed' and nullif(btrim(coalesce(c.email, '')), '') is null
--          and public.affiliate_login_link_proof(a.auth_user_id, a.customer_id) is null;
--     If either rises above 0: stop the QR survey and the event form from
--     filling a blank email on a record that has a portal login or an
--     affiliate record (a small follow-up migration with a 484 suite case;
--     not a guard on (d) itself, which would take the proof from logins
--     proven today by their verified email).
--   * Proof (d) assumes Supabase Auth's "Confirm email" stays on (437 keeps
--     it on), so an address change counts only once the new inbox confirms
--     it; with it off, a changed address would count unproven.
--   * Silent phone joins (Q2): 9 logins are not proven (4 with Tier 1
--     customers, 5 rows); 7 of them can prove themselves by verifying their
--     email on the Account page, the other 2 only by an Owner's Unlink, a
--     new sign-in and "Link to this customer". Nobody is told why the Phone
--     column does not appear.
--   * Staff decisions carry proof: a wrong claim resolution, Same person,
--     Link or merge proves the link, as it already shows names and spend. A
--     wrong merge can move a mark, but the number then shows only if the
--     kept record holds the typed number under the referrer the mark names.
--   * A household number (Q3: phone_shared, 2 ever) also belongs to another
--     customer, who was not told.
--   * No re-telling: a told referral whose number staff change shows a dash
--     (Q3); existing referrals stay a dash for good (registering again through
--     /r/ answers "already registered" and makes no mark, by design, so a
--     referrer cannot turn untold referrals into told ones by typing their
--     details).
--   * Deploy order: push #2 before this file is in: the page falls back to
--     affiliate_referral_signup on PGRST202 only and registers the person
--     with no mark (a dash). 482's file refuses to run again over this file (it
--     pins My Network at 480's or 484's first draft): there is nothing to
--     re-run, 482 being in.
--   * The apply takes SHARE ROW EXCLUSIVE on customers until it commits (the
--     table's foreign keys): customer writes, the /r/ and seminar sign-ups
--     included, wait for it; reads do not. Its lock timeout is 2 s, under
--     the API's statement timeout for signed-out calls (3 s; 8 s signed
--     in), so a sign-up queued behind a waiting apply still goes through;
--     once taken, the lock is held about 0.1 s (the dry run). If the apply
--     stops at the lock timeout, nothing changed: retry.
--   * Pins: 14 relied-on md5s; another session's change to one of them makes
--     this refuse (intended: re-read and re-test).
--   * Hiding a number (the opt-out) is MCP-only (below); there is no staff
--     button. Someone with no mark of their own can still have their number
--     shown on another record's row (a household number: Q3): hide it by
--     number (c_phone). A request is recorded only where a mark is found
--     (hidden now, or hidden already); should a later merge bring a mark
--     onto a record that asked when it had none, hide it then. Show again
--     restores only what that person's own request hid, and changes nothing
--     (ask the Owner) for a mark someone else also asked to hide.
--   * The proof follows merges through customers_merged rows of the Audit
--     Log: pruning those rows would drop the proofs that rely on them (no
--     number: the safe direction).
--   * A notice, not legal advice: the /r/ text is a notice, not consent;
--     take legal advice if the Owner wants it.
--   * Old tabs keep sending six keys for a while after push #2: those
--     sign-ups correctly show a dash.
--   * TRUNCATE (outside 484): anon and authenticated hold TRUNCATE on
--     affiliate_accounts, affiliate_account_claims, customer_affiliates and
--     customers (the Supabase default; row level security does not govern
--     TRUNCATE). The API exposes no truncate, so it is no path today; worth
--     a separate tidy-up. referral_phone_notices grants them nothing at all.
--   * Numbers are shown as stored, as staff see them (an older number kept
--     without a country code reads as typed, though a marked one is the
--     normalized number typed at sign-up). The portal keeps no record of who
--     looked at a number, and nothing stops an affiliate copying it.
--   * AFFILIATE_PORTAL.md (a note in the main checkout, not in the
--     repository) still says the portal shows no phone; it needs that line
--     changed when it is next edited.
--
-- HOW TO HIDE ONE REFERRAL'S NUMBER (the opt-out: "tell Energia and we will
-- hide it"; with the Owner's go-ahead naming the customer who asked)
--
--   First, read only: where does their number show? Their own marks, and
--   the marks on the number they gave (a household number shows on the row
--   of the person who typed it), not hidden yet:
--     select count(*) from public.referral_phone_notices
--      where (customer_id = '<id>' or phone = public.normalize_customer_phone('<their number>'))
--        and withdrawn_at is null;
--   Then run this through the MCP's execute_sql as one statement, with the
--   referral's customer id (from the Customers page), their number (with
--   its country code) when a mark on another record holds it (else c_phone
--   stays null), and how they asked filled in (as written, with the zero
--   id, it changes nothing). It withdraws those marks and writes an Audit
--   Log row on each record it touched, naming who asked and the marks:
--     do $hide$
--     declare
--       c_customer constant uuid := '00000000-0000-0000-0000-000000000000';  -- the referral who asked
--       c_phone constant text := null;  -- or the number they gave, with its country code: hidden on every record holding it
--       c_asked constant text := 'by phone, 3 Nov 2026';                     -- how and when they asked
--       n int;
--     begin
--       if not exists (select 1 from public.customers c where c.id = c_customer) then
--         raise exception '484 hide: % is not a customer (fill in the referral who asked); nothing changed', c_customer;
--       end if;
--       if c_phone is not null and public.normalize_customer_phone(c_phone) is null then
--         raise exception '484 hide: % is not a number that can be matched; nothing changed', c_phone;
--       end if;
--       -- Their marks and the marks on that number: those not hidden yet are withdrawn; one Audit Log row on each record,
--       -- naming who asked, the marks withdrawn now and those hidden already.
--       with m as (
--         select k.id, k.customer_id, k.withdrawn_at is not null as already
--           from public.referral_phone_notices k
--          where k.customer_id = c_customer or k.phone = public.normalize_customer_phone(c_phone)
--       ), w as (
--         update public.referral_phone_notices k set withdrawn_at = now() from m where k.id = m.id and not m.already
--       )
--       insert into public.audit_logs (table_name, record_id, action, new_data, module)
--       select 'customers', m.customer_id, 'referral_phone_hidden',
--              jsonb_build_object('marks_withdrawn', count(*) filter (where not m.already),
--                                 'mark_ids', coalesce(jsonb_agg(m.id order by m.id) filter (where not m.already), '[]'),
--                                 'hidden_already', coalesce(jsonb_agg(m.id order by m.id) filter (where m.already), '[]'),
--                                 'asked_by', c_customer, 'asked', c_asked, 'version', 484), 'affiliate'
--         from m group by m.customer_id;
--       get diagnostics n = row_count;
--       if n = 0 and c_phone is null then
--         raise exception '484 hide: % has no mark to withdraw (their number may still show on another record: check by number, then set c_phone); nothing changed', c_customer;
--       elsif n = 0 then
--         raise exception '484 hide: % has no mark to withdraw, and no mark holds %; nothing changed', c_customer, c_phone;
--       end if;
--       raise notice '484 hide: done for % on % record(s)', c_customer, n;
--     end $hide$;
--   From then on no affiliate sees that number on those records (a dash),
--   also after a merge (a withdrawn mark on a customer hides its number
--   whatever other mark it carries). The marks stay: they are the evidence
--   that the notice was given. Check afterwards with the query above: 0.
--   To show it again (only if they ask for that), the same way. It restores
--   only the marks their own hide withdrew, and changes nothing (ask the
--   Owner) when someone else also asked to hide one of them:
--     do $show$
--     declare
--       c_customer constant uuid := '00000000-0000-0000-0000-000000000000';  -- the referral who asked
--       c_asked constant text := 'by phone, 4 Nov 2026';                     -- how and when they asked
--       n int;
--     begin
--       -- Only the marks their own hide withdrew; none of them if someone else also asked to hide it (the Owner decides).
--       select count(*) into n
--         from public.referral_phone_notices k
--        where k.withdrawn_at is not null
--          and exists (select 1 from public.audit_logs l
--                       where l.table_name = 'customers' and l.action = 'referral_phone_hidden'
--                         and l.new_data ->> 'asked_by' = c_customer::text and (l.new_data -> 'mark_ids') @> to_jsonb(k.id))
--          and exists (select 1 from public.audit_logs l
--                       where l.table_name = 'customers' and l.action = 'referral_phone_hidden'
--                         and l.new_data ->> 'asked_by' is distinct from c_customer::text
--                         and ((l.new_data -> 'mark_ids') @> to_jsonb(k.id) or (l.new_data -> 'hidden_already') @> to_jsonb(k.id)));
--       if n > 0 then
--         raise exception '484 show: % mark(s) that % asked to hide, someone else also asked to hide (the Audit Log''s referral_phone_hidden rows); ask the Owner; nothing changed', n, c_customer;
--       end if;
--       with s as (
--         update public.referral_phone_notices k set withdrawn_at = null
--          where k.withdrawn_at is not null
--            and exists (select 1 from public.audit_logs l
--                         where l.table_name = 'customers' and l.action = 'referral_phone_hidden'
--                           and l.new_data ->> 'asked_by' = c_customer::text and (l.new_data -> 'mark_ids') @> to_jsonb(k.id))
--         returning k.id, k.customer_id
--       )
--       insert into public.audit_logs (table_name, record_id, action, new_data, module)
--       select 'customers', s.customer_id, 'referral_phone_shown_again',
--              jsonb_build_object('marks_restored', count(*), 'mark_ids', jsonb_agg(s.id order by s.id),
--                                 'asked_by', c_customer, 'asked', c_asked, 'version', 484), 'affiliate'
--         from s group by s.customer_id;
--       get diagnostics n = row_count;
--       if n = 0 then
--         raise exception '484 show: % has no mark withdrawn at their request; nothing changed', c_customer;
--       end if;
--       raise notice '484 show: done for % on % record(s)', c_customer, n;
--     end $show$;
--   The 484 suite runs both blocks exactly as written here (R3, by record
--   and by number).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the md5 of each of the three embedded function texts;
--   * 480 is recorded as applied (20261030052953; two IFs, so a database
--     without the history table gets this file's own message);
--   * where the database stands: BEFORE (My Network 480's d1c387fb..., the
--     only BEFORE accepted, and none of the three new objects), NUMBERS OFF
--     (My Network 480's, the three objects this file's: My Network is
--     replaced again) or AFTER (all four this file's: "already this version;
--     left alone"); anything else, 484's first draft (1fa56957...) included,
--     is refused, saying what it found;
--   * no other function takes the name of My Network, the proof or the
--     wrapper, and affiliate_referral_signup is the one six-argument
--     function of its name (an overload would make named calls ambiguous);
--     its grants and My Network's, compared as sets;
--   * the 14 functions relied on, at the md5s read on 1 Nov 2026
--     (c_relied: calcom_customer_bookings 480's or 482's); the 30 columns
--     the new functions read, of their types; the proof's footing:
--     customers.created_at and affiliate_accounts.created_at default now();
--     affiliate_accounts, affiliate_account_claims and customer_affiliates
--     have row level security on and no policy that inserts, updates or
--     deletes; anon and authenticated hold nothing on
--     affiliate_signup_matches, no INSERT, UPDATE, DELETE or TRUNCATE on
--     audit_logs and no INSERT or UPDATE on customers.
--   Afterwards: the three md5s; the four grant sets (the proof's, the
--   wrapper's, My Network's, affiliate_referral_signup's); the proof not
--   executable by anon or authenticated; the table's description md5, no
--   right for anon or authenticated, SELECT only for the service role; the
--   relied-on unchanged.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0484: no row left, no sequence moved, no message queued): made-up
--   records ("484 Check ...", eight fictional phones +61 2 5550 .... that no
--   customer, in use or deleted, and no active booking holds: range scans of
--   the partial phone indexes): an affiliate whose record and portal account
--   are made in one transaction (proven: own_record) with the login's email
--   on its record, not verified; an active affiliate record with a made-up
--   code. Signed out, with named arguments, as the pages call them: the
--   wrapper with 'r-page-2026-11' (registered), the old function with six
--   keys as the seminar website (registered), the wrapper with
--   'r-page-2099-01' (registered, no mark), the told person again (already
--   registered), a phone '0' (CUSTOMER_PHONE_REVIEW, nothing made): exactly
--   one mark (the told one: this referrer, its number, the version, the
--   code), and the two functions' answers carry the same keys. Then a Tier 2
--   customer under the told one, a referral set by staff, 484's first
--   draft's placeholder (AFF- and 8 characters, written with triggers off
--   for that statement), marks that must not count (for the seminar
--   referral: one naming another referrer, one with another number; for the
--   unknown one: a valid mark beside a withdrawn one). Called as that
--   affiliate (role authenticated, auth.uid() its login) three times: told,
--   proven and active: only the told row has its number; the record made a
--   day before the account (not proven): no number; proven again but
--   suspended: no number; each time 480's keys, 'phone' on Tier 1 only, and
--   no other fixture number anywhere. Signed out is refused My Network, the
--   proof and the table; signed in, the proof and the table; a login with no
--   affiliate account gets "Not an affiliate account". Two writes run with
--   session_replication_role = replica for that statement only: the portal
--   account (its trigger queues a welcome WhatsApp and takes a number from
--   affiliate_whatsapp_outbox_id_seq, which an undone block does not give
--   back) and the placeholder (the phone policy refuses one now). On
--   Supabase the postgres role may set it (supautils), and is a member of
--   anon and authenticated (checked on production, 1 Nov 2026).
--   Measured on the dry run: on the production-equal copy (schema only)
--   0.11 s wrapped (the self-test included), 0.10 s for the second run; on
--   a copy seeded with 13,399 made-up customers, 7,040 Audit Log rows and
--   500 invoices, 0.09 s, then 0.07 s. My Network there, for an affiliate
--   with 20 Tier 1 and 30 Tier 2 rows: median 8.0 ms (480's 7.7 ms), 8.8 ms
--   with every Tier 1 number shown.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead where it says so)
--
--   0. The Owner's answers (above) and the go-ahead for this file and for
--      push #2 (the /r/ notice).
--   1. Before applying, re-read supabase_migrations.schema_migrations and
--      origin/main (parallel sessions): 482 is in (20261101151909), and the
--      BEFORE md5s below still hold.
--   2. Dry run on a copy of production as it is then (rc480_live, the two
--      stores RETAIL-ADELPHI and ADELPHI-VAN with made-up names, 480's
--      history row, 483 and 482 each applied wrapped with its own row; its
--      fingerprint must equal production's: 240ab0c4.../1396 on 1 Nov
--      2026): apply this file wrapped as in step 3, then the plain file
--      again ("already this version; left alone"); time them; then run
--      scripts/referrals/tests/affiliate-network-phone-484.sql with
--      -v skip_install=1.
--   3. At a quiet moment (about 3 sign-ups a day), apply this file wrapped:
--      begin; this file; insert into supabase_migrations.schema_migrations
--      (version, name, statements) values (<version>,
--      '484_affiliate_network_shows_tier1_phone', array[<this file>]);
--      commit (preferred where psql reaches production; or the MCP's
--      apply_migration with this text verbatim: either way its history row
--      holds this file's text as its one statement, which UNDO's guard
--      reads). Build the wrapper with Python, the file embedded as a
--      dollar-quoted literal, never with cat or a psql backtick variable:
--      they drop the final newline. Read the row back:
--        select version, md5(array_to_string(statements, '')), cardinality(statements)
--          from supabase_migrations.schema_migrations
--         where name = '484_affiliate_network_shows_tier1_phone';
--      It must give one row, this file's md5 (md5 -q of it; the apply
--      report records it) and 1. After an unclear result (a timeout, a lost
--      connection), run this read before anything else: a row means the
--      apply committed, so do not apply again (a second apply records a
--      second row; UNDO level 2 deletes both). If the md5 differs, read the
--      stored statement back and diff it against this file: accept the
--      value read as UNDO's <M> only if the differences are whitespace or
--      comments; otherwise run UNDO level 1 at once, check that no customer
--      named "484 Check ..." exists (the self-test's records), and
--      investigate. If no row comes back after a plain psql run, insert it.
--   4. Read-only checks: the three AFTER md5s and the table's description
--      md5; the grant sets; anon and authenticated hold nothing on
--      referral_phone_notices, the service role only SELECT;
--      affiliate_referral_signup still 2942e3d4... with its grants; 0 marks;
--      the fingerprint and the grant list (AFTER, below). Then the probe,
--      signed out with the public key, which writes nothing (the number is
--      refused before anything is written):
--        POST /rest/v1/rpc/affiliate_referral_signup_with_notice
--        {"p_code":"X","p_first_name":"Probe","p_last_name":"Check","p_phone":"0",
--         "p_email":null,"p_notice":"r-page-2026-11","p_honeypot":null}
--      It must answer 400 with CUSTOMER_PHONE_REVIEW. A 404 PGRST202 means
--      the API's schema cache has not reloaded yet: wait, probe again, and
--      do not push #2 until it answers 400.
--   5. Commit #3: this file, scripts/referrals/tests/affiliate-network-phone-484.sql,
--      scripts/permissions/tests/function-grants.sql and
--      scripts/permissions/tests/staff-only-functions.sql (both fail
--      without 484 in the database, so they land now), and the 480 and 482
--      SQL suites' edits (scripts/referrals/tests/downline-booking-480.sql,
--      scripts/referrals/tests/downline-booking-482.sql: they accept this
--      file's AFTER and a Tier 1 'phone' that is null in their fixtures).
--      It changes no page.
--   6. Then push #2 (the /r/ page's notice and its call, with the fallback
--      on PGRST202 only; My Network's sentence; their tests): a push to main
--      is a Vercel deploy.
--   7. After the deploy (read only, counts only): the live /r/ bundle
--      carries the notice; after the first real /r/ sign-up:
--      select count(*) from public.referral_phone_notices >= 1, and for a
--      proven, active referrer My Network's Tier 1 rows with a number >= 1
--      (the Phone column appears for that affiliate).
--
-- BEFORE (production, read on 1 Nov 2026 at 23:21 SGT and again at the start
-- and the end of this build, 1-2 Nov 2026: head 20261101151909, 482; md5 of
-- pg_get_functiondef with search_path public)
--   changed: affiliate_portal_network() d1c387fb852392da041b5d8207655879
--     (480's AFTER, the only BEFORE accepted)
--   new, none of them there: referral_phone_notices,
--     affiliate_login_link_proof(uuid,uuid),
--     affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)
--   relied on, not changed: c_relied / c_relied_md5 below (14 functions),
--     among them affiliate_referral_signup(text,text,text,text,text,text)
--     2942e3d4d0e8c76600c3e0ad5e15cc2b (the only function of its name;
--     {anon,authenticated,postgres,service_role}=X)
--   public function fingerprint: 240ab0c40d3c3447a11b7b2712e13c88 (1396)
--   grant list (oid::regprocedure||'='||proacl, '|', by signature):
--     bbebe2306b314118ddd6473d16d2fc11
-- AFTER (for later guards)
--   affiliate_portal_network(): 070d1b485d32cec99fa627b816a91b4a
--     grants, as a set: {authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}
--   affiliate_login_link_proof(uuid,uuid): 2484fb464733c124213b96152837a660
--     grants, as a set: {postgres=X/postgres,service_role=X/postgres}
--   affiliate_referral_signup_with_notice(text x 7): f64347f2ccc993438f0cdb1655c7cc0f
--     grants, as a set: {anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}
--   referral_phone_notices, its description (the query in the checks): ec6de1ddd64fb06b87b401b9f7a55984
--     grants, as a set: {postgres=arwdDxtm/postgres,service_role=r/postgres};
--     row level security on, no policy
--   affiliate_referral_signup(text,text,text,text,text,text): 2942e3d4d0e8c76600c3e0ad5e15cc2b
--     (unchanged, the same grants)
--   public function fingerprint, worked out on copies of production (1 Nov
--   2026), production now (480, 483, 482) -> 484: 893e854b4baf8b653dcf13bdcda2a356 (1398 functions: the two new ones added)
--   grant list: e68aa1abc012f3e4539dd315b96a1ea1 (the two new functions' grants added; every other grant unchanged)
--
-- UNDO (each level with the Owner's go-ahead; neither touches
-- affiliate_referral_signup; the 484 suite's U section runs both exactly as
-- written here)
--   Level 1, NUMBERS OFF (use this first if anything is wrong), in one
--   transaction: begin;
--     0. stop unless My Network is this file's, so a later version is never
--        overwritten:
--     do $undo1$
--     begin
--       perform set_config('search_path', 'public', true);
--       if md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure)) <> '070d1b485d32cec99fa627b816a91b4a' then
--         raise exception 'UNDO 484 (1): public.affiliate_portal_network() is not 484''s version (md5 %); nothing changed',
--           md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure));
--       end if;
--     end $undo1$;
--     1. re-apply 480's text of My Network: the text between $c2$ and
--        $c2$ in supabase/480_downline_and_network_show_calcom_booking.sql (its
--        c_chg_defs[2]; that text's own md5 is
--        d1c387fb852392da041b5d8207655879), run as one statement; CREATE OR
--        REPLACE keeps the grants;
--   commit. My Network then reads d1c387fb... and sends no 'phone' key; the
--   pages of push #1 hide the Phone column by themselves. The table and its
--   marks, the proof, the sign-up with notice and the history row stay: the
--   /r/ page keeps registering people and recording who was told. Level 1
--   again stops at its step 0. Running this file again (plain, or wrapped
--   without a new history row) recognises NUMBERS OFF and replaces My
--   Network again: numbers back on.
--   Level 2, REMOVE (after level 1, in the same transaction or later).
--   First revert push #2 and wait until that Vercel deploy is live: the
--   page falls back to affiliate_referral_signup on PGRST202 only, and
--   while level 2 runs, and until the API reloads its schema cache after
--   it, a call to the sign-up with notice answers 42P01 or 42883, which the
--   page shows as an error (the person is not registered). Level 2 takes
--   an ACCESS EXCLUSIVE lock on customers for a moment (dropping the table
--   removes its four foreign-key triggers there): reads and writes of
--   customers wait for it, at most 2 s (its lock timeout); if it stops at
--   the lock timeout, nothing changed: retry. One statement, with <M> =
--   this file's md5 as applied (DEPLOY ORDER 3); it refuses while the table
--   holds any mark (withdrawn or not: they are the evidence that the notice
--   was given) unless c_discard_marks is set on the Owner's explicit word
--   to discard them; it deletes every history row of 484 holding that text
--   (two, if the apply was repeated):
--     do $undo2$
--     declare
--       c_m constant text := '<M>';                  -- this file's md5 as applied (DEPLOY ORDER 3)
--       c_discard_marks constant boolean := false;   -- true only on the Owner's explicit word to discard the marks
--       n int;
--     begin
--       perform set_config('lock_timeout', '2s', true);
--       perform set_config('search_path', 'public', true);
--       if md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure)) <> 'd1c387fb852392da041b5d8207655879'
--          or md5(pg_get_functiondef(to_regprocedure('public.affiliate_login_link_proof(uuid,uuid)'))) is distinct from '2484fb464733c124213b96152837a660'
--          or md5(pg_get_functiondef(to_regprocedure('public.affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)')))
--             is distinct from 'f64347f2ccc993438f0cdb1655c7cc0f'
--          or to_regclass('public.referral_phone_notices') is null then
--         raise exception 'UNDO 484 (2): My Network is not 480''s (run level 1 first), or the proof, the sign-up with notice or the table is not 484''s; nothing changed';
--       end if;
--       select count(*) into n from public.referral_phone_notices;
--       if n > 0 and not c_discard_marks then
--         raise exception 'UNDO 484 (2): referral_phone_notices holds % mark(s), the evidence that the notice was given; keep level 1, or set c_discard_marks on the Owner''s explicit word; nothing changed', n;
--       end if;
--       drop function public.affiliate_referral_signup_with_notice(text,text,text,text,text,text,text);
--       drop function public.affiliate_login_link_proof(uuid,uuid);
--       drop table public.referral_phone_notices;
--       delete from supabase_migrations.schema_migrations
--        where name = '484_affiliate_network_shows_tier1_phone' and md5(array_to_string(statements, '')) = c_m;
--       get diagnostics n = row_count;
--       if n < 1 then
--         raise exception 'UNDO 484 (2): no history row for 484 holds this file''s text (md5 %); nothing changed', c_m;
--       end if;
--       raise notice 'UNDO 484 (2): the sign-up with notice, the proof and referral_phone_notices dropped; % history row(s) of 484 deleted', n;
--     end $undo2$;
--   The catalogue is then exactly as before 484 (the dry run compared every
--   function's md5 and grants, every table, column, constraint, index,
--   trigger, policy, sequence and comment, and the history). A later
--   re-apply of this file makes all four again, recorded anew. After level
--   2, revert commit #3 as a whole (git revert: this file, its suite and
--   the four suite edits) or apply this file again: commit #3's
--   function-grants.sql and staff-only-functions.sql fail on a database
--   without 484 (the signed-out endpoint is no longer reachable; a named
--   function is not callable).
--
-- Test: scripts/referrals/tests/affiliate-network-phone-484.sql (begin ...
-- rollback; it installs this file twice where 482 is in and 484 is not, or
-- runs with -v skip_install=1 where 484 is in). The 480 and 482 suites run
-- with -v skip_install=1 on a 484 database (they accept this file's AFTER
-- and a Tier 1 'phone' that is null in their fixtures); function-grants.sql
-- and staff-only-functions.sql list the wrapper among the signed-out
-- endpoints and need 484 in the database. Pages (push #2): the referral
-- notice test, and affiliate-network-phone-484.test.mjs.

set lock_timeout = '2s';

do $mig$
declare
  -- ── What this makes or changes ──
  -- My Network: 480's (BEFORE, the only version accepted) -> this file's (AFTER).
  c_net constant text := 'affiliate_portal_network()';
  c_net_before constant text := 'd1c387fb852392da041b5d8207655879';
  c_net_after constant text := '070d1b485d32cec99fa627b816a91b4a';
  c_net_def constant text :=
$d1$CREATE OR REPLACE FUNCTION public.affiliate_portal_network()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_t1 jsonb; v_t2 jsonb;
  -- 480 (the Owner, 29 Oct 2026): each one's cal.com booking, its moment and
  -- state only (calcom_customer_bookings, as the staff Downline reads it).
  v_book jsonb;
  -- 484 (the Owner, 31 Oct 2026, answers 1 and 2): whether this login is
  -- shown any Tier 1 number at all: the affiliate is active (not suspended,
  -- not removed) and the login's link to its record is proven
  -- (affiliate_login_link_proof, read for the login itself: auth.uid()).
  v_phones boolean;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  v_phones := public.affiliate_is_active(v_me) and public.affiliate_login_link_proof(auth.uid(), v_me) is not null;

  select coalesce(jsonb_object_agg(b.customer_id, jsonb_build_object('at', b.booking_at, 'state', b.booking_state)), '{}'::jsonb)
    into v_book
    from public.calcom_customer_bookings(array(
           select c.id from public.customers c where c.referred_by = v_me and c.deleted_at is null
           union
           select c.id from public.customers c join public.customers p on p.id = c.referred_by
            where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null)) b;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier1',
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id
                                  and cm.status in ('earned','paid')),
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none'),
           -- 484 (the Owner, 31 Oct and 1 Nov 2026): the stored number, trimmed,
           -- only when v_phones and the referral signed up through the /r/ page
           -- while it said this referrer would see their number (a mark in
           -- referral_phone_notices naming this referrer), the record still holds
           -- the number typed then, and they have not asked to hide it (no
           -- withdrawn mark). Otherwise null (a dash on the page). Tier 2: no
           -- phone key at all.
           'phone', case when v_phones and btrim(c.phone) ~ '[0-9]' and btrim(c.phone) !~* '^(AFF-.{8}|LEGACY-.*)$'
                          and exists (select 1 from public.referral_phone_notices n
                                       where n.customer_id = c.id and n.referrer_customer_id = v_me and n.withdrawn_at is null
                                         and n.phone = public.normalize_customer_phone(c.phone))
                          and not exists (select 1 from public.referral_phone_notices w
                                           where w.customer_id = c.id and w.withdrawn_at is not null)
                         then btrim(c.phone) end
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t1
    from public.customers c where c.referred_by = v_me and c.deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier2',
           'parent_name', p.full_name,
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id and cm.status in ('earned','paid')),
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none')
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t2
    from public.customers c
    join public.customers p on p.id = c.referred_by
   where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null;

  return jsonb_build_object('tier1', v_t1, 'tier2', v_t2);
end $function$
$d1$;
  -- Its grants, kept by CREATE OR REPLACE (compared as sets): signed-in logins (the portal), the owner and the
  -- service role; not signed out.
  c_net_acl constant text[] := array['authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres'];
  -- The proof of a login's link to its record (answer 1): new; the owner's and the service role's alone.
  c_proof constant text := 'affiliate_login_link_proof(uuid,uuid)';
  c_proof_after constant text := '2484fb464733c124213b96152837a660';
  c_proof_def constant text :=
$d2$CREATE OR REPLACE FUNCTION public.affiliate_login_link_proof(p_auth_user_id uuid, p_customer_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 484 (the Owner, 31 Oct 2026, answer 1): why this portal login's link to
  -- this customer record is proven, or null when it is not. Only rows the
  -- server writes are read.
  with recursive acct as (
    select a.id, a.auth_user_id, a.customer_id, a.created_at, a.email_verified_at
      from public.affiliate_accounts a
     where a.auth_user_id = p_auth_user_id and a.customer_id = p_customer_id and a.status = 'claimed'
  ), rec(id, n) as (
    -- the record, and every record an Owner or Manager merged into it
    select acct.customer_id, 0 from acct
    union
    select (l.new_data ->> 'merged_from')::uuid, rec.n + 1
      from rec join public.audit_logs l on l.record_id = rec.id
     where l.table_name = 'customers' and l.action = 'customers_merged'
       and l.new_data ->> 'merged_from' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       and rec.n < 20
  )
  select case
    -- (a) the record was made by this login's own sign-up (the same transaction as this account)
    when exists (select 1 from acct, rec join public.customers c on c.id = rec.id where c.created_at = acct.created_at)
      then 'own_record'
    -- (b) staff resolved a claim of this login, in the transaction that made this account
    when exists (select 1 from acct, public.affiliate_account_claims cl
                  where cl.auth_user_id = acct.auth_user_id and cl.status = 'resolved'
                    and cl.resolved_by is not null and cl.resolved_at = acct.created_at)
      then 'claim_resolved'
    -- (c) staff said Same person (or linked the sign-up) for this login on this record, while this account existed
    when exists (select 1 from acct, public.affiliate_signup_matches m
                  where m.auth_user_id = acct.auth_user_id and m.decided_by is not null
                    and m.decided_at >= acct.created_at
                    and ((m.status = 'same_person' and m.fresh_customer_id in (select rec.id from rec))
                      or (m.status = 'linked' and m.linked_customer_id in (select rec.id from rec))))
      then 'same_person'
    -- (d) the login's email is verified and is the record's email (the same inbox)
    when exists (select 1 from acct join auth.users u on u.id = acct.auth_user_id
                   join public.customers c on c.id = acct.customer_id
                  where acct.email_verified_at is not null
                    and public.customer_email_match_key(u.email) is not null
                    and public.customer_email_match_key(u.email) = public.customer_email_match_key(c.email))
      then 'verified_email'
  end
$function$
$d2$;
  c_proof_acl constant text[] := array['postgres=X/postgres', 'service_role=X/postgres'];
  -- The /r/ page's sign-up with its notice: new; signed out, signed-in logins and the service role may call it,
  -- exactly as they may call affiliate_referral_signup.
  c_wrap constant text := 'affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)';
  c_wrap_after constant text := 'f64347f2ccc993438f0cdb1655c7cc0f';
  c_wrap_def constant text :=
$d3$CREATE OR REPLACE FUNCTION public.affiliate_referral_signup_with_notice(p_code text, p_first_name text, p_last_name text, p_phone text, p_email text, p_notice text, p_honeypot text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  -- 484 (the Owner, 31 Oct and 1 Nov 2026): the notices a page may name, each
  -- the exact wording that told the person their referrer would see their
  -- phone number. 'r-page-2026-11': the app's /r/ page's full notice with its
  -- opt-out sentence (1 Nov 2026). Any other value (none, blank, unknown,
  -- another case, spaces): the sign-up goes ahead exactly as
  -- affiliate_referral_signup's, with no mark.
  c_notices constant text[] := array['r-page-2026-11'];
  v_notice text := case when p_notice = any (c_notices) then p_notice end;
  v_norm text := public.normalize_customer_phone(p_phone);
  v_code text := btrim(coalesce(p_code, ''));
  v_before uuid[] := '{}'::uuid[];
  v_ans jsonb;
begin
  -- The customers made before this call with this phone at this transaction's
  -- moment (none from the API, where one call is one transaction), so that
  -- only this call's is marked. The phone's lock first, the one
  -- affiliate_referral_signup takes (it takes it again: an advisory lock is
  -- re-entrant), so a sign-up on the same phone in flight elsewhere has
  -- finished and is seen here.
  if v_notice is not null and v_norm is not null then
    perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm, 0));
    select coalesce(array_agg(c.id), '{}'::uuid[]) into v_before
      from public.customers c
     where c.deleted_at is null and c.created_at = now() and public.normalize_customer_phone(c.phone) = v_norm;
  end if;
  -- The sign-up: affiliate_referral_signup's checks, limits, answers and errors, unchanged.
  v_ans := public.affiliate_referral_signup(p_code, p_first_name, p_last_name, p_phone, p_email, p_honeypot);
  -- The customer it made (created / phone_shared; no other outcome makes one): made now, in use, with this
  -- number, through this link. Marked told, for the referrer it was made under and this number.
  if v_notice is not null and v_norm is not null then
    insert into public.referral_phone_notices (customer_id, referrer_customer_id, phone, notice_version, referral_code)
    select c.id, c.referred_by, v_norm, v_notice, v_code
      from public.customers c
     where c.deleted_at is null and c.created_at = now() and public.normalize_customer_phone(c.phone) = v_norm
       and c.id <> all (v_before)
       and c.referral_source = 'affiliate_link' and c.referral_code_used = v_code and c.referred_by is not null;
  end if;
  return v_ans;
end $function$
$d3$;
  c_wrap_acl constant text[] := array['anon=X/postgres', 'authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres'];
  -- The sign-up the wrapper calls and the seminar website calls: NOT changed (its md5 is pinned below, with the
  -- relied on); the only function of its name; its grants, as a set.
  c_signup constant text := 'affiliate_referral_signup(text,text,text,text,text,text)';
  c_signup_acl constant text[] := array['anon=X/postgres', 'authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres'];
  -- The marks: a new table. The md5 of its description as read back (its columns, constraints, indexes, row level
  -- security on and not forced, its grants as a set, no policy, no trigger, owner postgres); comments do not enter it.
  c_tbl_after constant text := 'ec6de1ddd64fb06b87b401b9f7a55984';

  -- ── Relied on, not changed (production, 1 Nov 2026) ──
  -- Who the affiliate is; the staff Downline (left alone); the booking state rule My Network passes through (480's
  -- or 482's: a comma between md5s accepts either); whether an affiliate is active (answer 2); the sign-up the
  -- wrapper calls (its checks, answers and the customer it makes); the writers of the rows each proof reads (the
  -- sign-up that makes a record and its account in one transaction, staff's claim resolution, staff's Same person
  -- and Link, the Unlink that deletes an account, the email verification); the merge (it moves the marks along
  -- their foreign keys and writes the customers_merged rows the proof follows); the email inbox key; the phone
  -- normalizer the marks are written and compared with.
  c_relied constant text[] := array[
    'current_affiliate_customer_id()', 'customer_downline_visits(uuid)', 'calcom_customer_bookings(uuid[],date)',
    'affiliate_is_active(uuid)', 'affiliate_referral_signup(text,text,text,text,text,text)',
    'complete_affiliate_onboarding(text,text,text,boolean)', 'resolve_affiliate_account_claim(uuid,uuid,text)',
    'confirm_affiliate_signup_same_person(uuid,text)', 'link_affiliate_signup(uuid,uuid,text,uuid,boolean)',
    'unlink_affiliate_account(uuid,text)', 'confirm_affiliate_email()', 'merge_customer_records(uuid,uuid,text,uuid)',
    'customer_email_match_key(text)', 'normalize_customer_phone(text)'];
  c_relied_md5 constant text[] := array[
    '51695acf5f26ce3918d6003d0c980b0f', 'ea3f28ea932506eda6937fa687298d6d',
    '2e651a5d2367ba26bfd9e8e00d95823e,14987e9e9f033290010042a5632bc81c',
    '2ba3ff0aa858045718cbb3719b959685', '2942e3d4d0e8c76600c3e0ad5e15cc2b',
    '1b9dfc819b860dcb19244063a4628f47', '29a68a4d2282995f367b715089736c6c',
    'a9a1f6c2d37284e1e19d898ebdd203e6', '198780b31301695db55c4a39ba9618f8',
    '7e6b57e5e15e32d6f3ca7ab7f181e370', '431ff39aa4fe42ec9b1442e65a044676', 'ba05c2b1fb4c0e14d369c01d06a635b0',
    'be468815c9626fff1728e2cfcd484b66', 'b2bfac910e0c9eff402ba44e19750bee'];
  -- The columns the three new functions read (schema.table.column type).
  c_cols constant text[] := array[
    'public.customers.id uuid', 'public.customers.phone text', 'public.customers.email text',
    'public.customers.created_at timestamp with time zone', 'public.customers.deleted_at timestamp with time zone',
    'public.customers.referred_by uuid', 'public.customers.referral_source text', 'public.customers.referral_code_used text',
    'public.affiliate_accounts.id uuid', 'public.affiliate_accounts.auth_user_id uuid', 'public.affiliate_accounts.customer_id uuid',
    'public.affiliate_accounts.status text', 'public.affiliate_accounts.created_at timestamp with time zone',
    'public.affiliate_accounts.email_verified_at timestamp with time zone',
    'public.affiliate_account_claims.auth_user_id uuid', 'public.affiliate_account_claims.status text',
    'public.affiliate_account_claims.resolved_by uuid', 'public.affiliate_account_claims.resolved_at timestamp with time zone',
    'public.affiliate_signup_matches.auth_user_id uuid', 'public.affiliate_signup_matches.fresh_customer_id uuid',
    'public.affiliate_signup_matches.linked_customer_id uuid', 'public.affiliate_signup_matches.status text',
    'public.affiliate_signup_matches.decided_by uuid', 'public.affiliate_signup_matches.decided_at timestamp with time zone',
    'public.audit_logs.record_id uuid', 'public.audit_logs.table_name text', 'public.audit_logs.action text',
    'public.audit_logs.new_data jsonb', 'auth.users.id uuid', 'auth.users.email character varying(255)'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v_role text := current_user;
  v text; v_md5 text; v_pmd5 text; v_wmd5 text; v_oid regprocedure; v_state text; v_tbl text;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_ph text[]; t_code text; t_mail text; t_me uuid; t_aff uuid; t_uid uuid;
  t_told uuid; t_sem uuid; t_unk uuid; t_srr text; t_ans jsonb; t_a1 jsonb; t_a2 jsonb; t_a3 jsonb; t_a4 jsonb;
  t_err text; t_err2 text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──
  if md5(c_net_def) <> c_net_after then
    raise exception '484: the text of public.% is not the tested one (md5 %)', c_net, md5(c_net_def); end if;
  if md5(c_proof_def) <> c_proof_after then
    raise exception '484: the text of public.% is not the tested one (md5 %)', c_proof, md5(c_proof_def); end if;
  if md5(c_wrap_def) <> c_wrap_after then
    raise exception '484: the text of public.% is not the tested one (md5 %)', c_wrap, md5(c_wrap_def); end if;

  -- Two IFs: PL/pgSQL prepares a whole condition before it runs it, so one that names a missing table fails
  -- there, before any of it is evaluated.
  if to_regclass('supabase_migrations.schema_migrations') is null then
    raise exception '484: 480 (20261030052953) is not recorded in supabase_migrations.schema_migrations. Apply 480 first (a copy built with psql: add its row as production has it).';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261030052953') then
    raise exception '484: 480 (20261030052953) is not recorded in supabase_migrations.schema_migrations. Apply 480 first (a copy built with psql: add its row as production has it).';
  end if;

  -- Where this database stands. BEFORE: My Network 480's and none of the three new things; AFTER: all four this
  -- file's ("already this version; left alone"); NUMBERS OFF (UNDO's first level): My Network 480's again and the
  -- other three this file's (My Network is replaced again). Anything else (484's first draft of 31 Oct 2026
  -- included) is refused.
  select md5(concat_ws(E'\n',
    (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end
                       || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), ''), ', ' order by a.attnum)
       from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
      where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped),
    (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ', ' order by c.conname) from pg_constraint c where c.conrelid = t.oid),
    (select string_agg(pg_get_indexdef(i.indexrelid), ', ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = t.oid),
    'rls ' || t.relrowsecurity::text || ' force ' || t.relforcerowsecurity::text,
    'acl ' || coalesce((select string_agg(x::text, ',' order by x::text) from unnest(t.relacl) x), ''),
    'policies ' || (select count(*) from pg_policy p where p.polrelid = t.oid)::text,
    'triggers ' || (select count(*) from pg_trigger g where g.tgrelid = t.oid and not g.tgisinternal)::text,
    'owner ' || pg_get_userbyid(t.relowner)))
    into v_tbl from pg_class t where t.oid = to_regclass('public.referral_phone_notices');
  v_oid := to_regprocedure('public.' || c_net);
  if v_oid is null then raise exception '484: public.% is missing (155 makes it, 480 the version this replaces)', c_net; end if;
  v_md5 := md5(pg_get_functiondef(v_oid));
  v_pmd5 := md5(pg_get_functiondef(to_regprocedure('public.' || c_proof)));
  v_wmd5 := md5(pg_get_functiondef(to_regprocedure('public.' || c_wrap)));
  if v_md5 = c_net_before and v_pmd5 is null and v_wmd5 is null and to_regclass('public.referral_phone_notices') is null then
    v_state := 'before';
  elsif v_md5 in (c_net_before, c_net_after) and v_pmd5 is not distinct from c_proof_after
        and v_wmd5 is not distinct from c_wrap_after and v_tbl is not distinct from c_tbl_after then
    v_state := case when v_md5 = c_net_after then 'after' else 'off' end;
  else
    raise exception '484: this database is neither before 484 (My Network 480''s, md5 d1c387fb..., and none of referral_phone_notices, affiliate_login_link_proof and affiliate_referral_signup_with_notice) nor this file''s (found: My Network md5 %, the notices table %, the proof %, the sign-up with notice %). Re-read it and re-test before applying.',
      v_md5, coalesce(v_tbl, 'missing'), coalesce(v_pmd5, 'missing'), coalesce(v_wmd5, 'missing');
  end if;
  -- No other function takes these names (an overload makes the API's named calls ambiguous), and the sign-up the
  -- wrapper calls is the one six-argument function of its name.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('affiliate_portal_network', 'affiliate_login_link_proof', 'affiliate_referral_signup_with_notice',
                       'affiliate_referral_signup')
     and p.oid::regprocedure::text not in (c_net, c_proof, c_wrap, c_signup);
  if v is not null then raise exception '484: another function takes one of these names: %', v; end if;
  if to_regprocedure('public.' || c_signup) is null then
    raise exception '484: public.% is missing (the sign-up the wrapper calls)', c_signup; end if;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_signup))
     is distinct from c_signup_acl then
    raise exception '484: the grants of public.% are not as read on 1 Nov 2026 (signed out, signed-in logins, the owner and the service role)', c_signup; end if;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid) is distinct from c_net_acl
     or has_function_privilege('anon', v_oid, 'execute') then
    raise exception '484: the grants of public.% are not as read on 1 Nov 2026 (signed-in logins, the owner and the service role; not signed out)', c_net; end if;

  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or not (md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) = any (string_to_array(c_relied_md5[i], ','))) then
      raise exception '484: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  select string_agg(x.c, ', ' order by x.n) into v
    from unnest(c_cols) with ordinality x(c, n)
   where not exists (select 1 from pg_attribute a join pg_class t on t.oid = a.attrelid join pg_namespace s on s.oid = t.relnamespace
                      where s.nspname || '.' || t.relname || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.c
                        and a.attnum > 0 and not a.attisdropped);
  if v is not null then raise exception '484: these columns are missing or not as read on 1 Nov 2026: %', v; end if;

  -- What the proof's anchors stand on (production, 1 Nov 2026): a record and its account made in one transaction
  -- carry the same created_at (both default now()); clients cannot write the rows the proof reads: the accounts,
  -- the claims and the affiliate records have row level security on with no policy that inserts, updates or
  -- deletes; the sign-up list is the server's alone; the Audit Log and customers take no client write.
  if (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
       where d.adrelid = 'public.customers'::regclass and a.attname = 'created_at') is distinct from 'now()'
     or (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
          where d.adrelid = 'public.affiliate_accounts'::regclass and a.attname = 'created_at') is distinct from 'now()' then
    raise exception '484: customers.created_at and affiliate_accounts.created_at must both default to now() (the proof compares them), as read on 1 Nov 2026'; end if;
  select string_agg(x.t, ', ' order by x.t) into v
    from unnest(array['affiliate_accounts', 'affiliate_account_claims', 'customer_affiliates']) x(t)
   where not coalesce((select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || x.t)), false)
      or exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.' || x.t) and p.polcmd in ('a', 'w', 'd', '*'));
  if v is not null then
    raise exception '484: row level security is off, or a policy lets a client write, on: % (as read on 1 Nov 2026: on, with SELECT policies only)', v; end if;
  if has_any_column_privilege('anon', 'public.affiliate_signup_matches', 'select,insert,update,references')
     or has_any_column_privilege('authenticated', 'public.affiliate_signup_matches', 'select,insert,update,references')
     or has_table_privilege('anon', 'public.affiliate_signup_matches', 'delete,truncate,trigger')
     or has_table_privilege('authenticated', 'public.affiliate_signup_matches', 'delete,truncate,trigger')
     or has_any_column_privilege('anon', 'public.audit_logs', 'insert,update')
     or has_any_column_privilege('authenticated', 'public.audit_logs', 'insert,update')
     or has_table_privilege('anon', 'public.audit_logs', 'delete,truncate')
     or has_table_privilege('authenticated', 'public.audit_logs', 'delete,truncate')
     or has_any_column_privilege('anon', 'public.customers', 'insert,update')
     or has_any_column_privilege('authenticated', 'public.customers', 'insert,update') then
    raise exception '484: a client role holds a right the proof relies on it not holding (affiliate_signup_matches: none; audit_logs: no insert, update, delete or truncate; customers: no insert or update), as read on 1 Nov 2026'; end if;

  -- ── Change ──
  if v_state = 'before' then
    -- The marks (answers 3 and 4): one row for each customer the /r/ page made after showing its notice. Server
    -- only: no client role holds it, the service role may read it. Its two foreign keys let a merge
    -- (merge_customer_records' catalogue loop) move a mark with the record and the referrer it names; a hard
    -- delete takes the marks with it.
    create table public.referral_phone_notices (
      id uuid primary key default gen_random_uuid(),
      customer_id uuid not null references public.customers(id) on delete cascade,
      referrer_customer_id uuid not null references public.customers(id) on delete cascade,
      phone text not null,
      notice_version text not null,
      referral_code text not null,
      created_at timestamptz not null default now(),
      withdrawn_at timestamptz,
      constraint referral_phone_notices_version_check check (notice_version ~ '^[a-z0-9][a-z0-9._-]{0,39}$'),
      constraint referral_phone_notices_phone_check check (phone ~ '^\+[0-9]{6,15}$')
    );
    create index referral_phone_notices_customer on public.referral_phone_notices (customer_id);
    create index referral_phone_notices_referrer on public.referral_phone_notices (referrer_customer_id);
    alter table public.referral_phone_notices enable row level security;
    revoke all on table public.referral_phone_notices from public, anon, authenticated, service_role;
    grant select on table public.referral_phone_notices to service_role;
    comment on table public.referral_phone_notices is
      '484: who was told at sign-up, on the /r/ page, that their referrer would see their phone number (notice_version names the exact wording), for which referrer and which number; withdrawn_at: they asked for it to be hidden. Server only.';
    execute c_proof_def;
    execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_proof);
    execute format('grant execute on function public.%s to service_role', c_proof);
    execute c_wrap_def;
    execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_wrap);
    execute format('grant execute on function public.%s to anon, authenticated, service_role', c_wrap);
    execute c_net_def;
    raise notice '484: referral_phone_notices, affiliate_login_link_proof and affiliate_referral_signup_with_notice made; public.% replaced (480''s -> 484''s: a Tier 1 number only when told at sign-up, the login proven and the affiliate active)', c_net;
  elsif v_state = 'off' then
    execute c_net_def;
    raise notice '484: public.% replaced again (numbers back on); the notices, the proof and the sign-up with notice were in already', c_net;
  else
    raise notice '484: already this version; left alone';
  end if;

  -- ── Afterwards ──
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_net))) is distinct from c_net_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_proof))) is distinct from c_proof_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_wrap))) is distinct from c_wrap_after then
    raise exception '484: a function was installed with an md5 other than the tested one'; end if;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_net)) is distinct from c_net_acl
     or (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_proof)) is distinct from c_proof_acl
     or (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_wrap)) is distinct from c_wrap_acl
     or (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_signup)) is distinct from c_signup_acl
     or has_function_privilege('anon', to_regprocedure('public.' || c_net), 'execute')
     or has_function_privilege('anon', to_regprocedure('public.' || c_proof), 'execute')
     or has_function_privilege('authenticated', to_regprocedure('public.' || c_proof), 'execute') then
    raise exception '484: the grants are not as tested'; end if;
  select md5(concat_ws(E'\n',
    (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end
                       || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), ''), ', ' order by a.attnum)
       from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
      where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped),
    (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ', ' order by c.conname) from pg_constraint c where c.conrelid = t.oid),
    (select string_agg(pg_get_indexdef(i.indexrelid), ', ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = t.oid),
    'rls ' || t.relrowsecurity::text || ' force ' || t.relforcerowsecurity::text,
    'acl ' || coalesce((select string_agg(x::text, ',' order by x::text) from unnest(t.relacl) x), ''),
    'policies ' || (select count(*) from pg_policy p where p.polrelid = t.oid)::text,
    'triggers ' || (select count(*) from pg_trigger g where g.tgrelid = t.oid and not g.tgisinternal)::text,
    'owner ' || pg_get_userbyid(t.relowner)))
    into v_tbl from pg_class t where t.oid = to_regclass('public.referral_phone_notices');
  if v_tbl is distinct from c_tbl_after
     or has_any_column_privilege('anon', 'public.referral_phone_notices', 'select,insert,update,references')
     or has_any_column_privilege('authenticated', 'public.referral_phone_notices', 'select,insert,update,references')
     or has_table_privilege('anon', 'public.referral_phone_notices', 'delete,truncate,trigger')
     or has_table_privilege('authenticated', 'public.referral_phone_notices', 'delete,truncate,trigger')
     or has_any_column_privilege('service_role', 'public.referral_phone_notices', 'insert,update,references')
     or has_table_privilege('service_role', 'public.referral_phone_notices', 'delete,truncate,trigger')
     or not has_table_privilege('service_role', 'public.referral_phone_notices', 'select') then
    raise exception '484: public.referral_phone_notices is not as tested (description md5 %)', v_tbl; end if;
  for i in 1 .. cardinality(c_relied) loop
    if not (md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) = any (string_to_array(c_relied_md5[i], ','))) then
      raise exception '484: public.% changed', c_relied[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ──
  begin
    -- Written as the server (no request).
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- Eight fictional phones in a row (+61 2 5550 nnnn) that no customer, in use or deleted, and no active booking
    -- holds: range scans of idx_customers_phone_norm, idx_customers_deleted_phone_norm and
    -- calcom_bookings_phone_key_idx (all partial, hence the conditions), never a pass reading every customer's phone.
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.calcom_bookings k
                        where k.status = 'active'
                          and k.phone_key between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '484: the self-test found no free fictional phones'; end if;
    t_ph := array(select '+6125550' || lpad((t_base + n)::text, 4, '0') from generate_series(0, 7) n);
    t_code := '484CHECK' || upper(t_sfx);
    t_mail := '484-check-' || t_sfx || '@example.invalid';
    -- The affiliate: its record made with its portal account in one transaction (proven: its own sign-up made it),
    -- holding the login's email, which is not verified (no proof by itself); an active affiliate record with a
    -- made-up code; a login.
    insert into public.customers (full_name, phone, email) values ('484 Check Affiliate', t_ph[1], t_mail) returning id into t_me;
    insert into public.customer_affiliates (customer_id, status, activated_at, referral_code)
      values (t_me, 'active', now(), t_code) returning id into t_aff;
    insert into auth.users (id, email) values (gen_random_uuid(), t_mail) returning id into t_uid;
    -- The portal account with triggers off for this statement only (its trigger would queue a welcome WhatsApp and
    -- take a number from the outbox's sequence, which an undone block does not give back).
    t_srr := current_setting('session_replication_role');
    set local session_replication_role = replica;
    insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (t_uid, t_me, t_aff, 'claimed');
    execute format('set local session_replication_role = %L', t_srr);

    -- Signed out, as the pages call them: /r/ with its notice (told); the seminar website's six keys to the old
    -- function; /r/ naming a notice no migration has listed; the told person again; a number that is no number.
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    begin
      execute 'set local role anon';
      t_a1 := public.affiliate_referral_signup_with_notice(p_code := t_code, p_first_name := '484 Check', p_last_name := 'Told',
                p_phone := t_ph[2], p_email := null, p_notice := 'r-page-2026-11', p_honeypot := null);
      t_a2 := public.affiliate_referral_signup(p_code := t_code, p_first_name := '484 Check', p_last_name := 'Seminar',
                p_phone := t_ph[3], p_email := null, p_honeypot := null);
      t_a3 := public.affiliate_referral_signup_with_notice(p_code := t_code, p_first_name := '484 Check', p_last_name := 'Unknown',
                p_phone := t_ph[4], p_email := null, p_notice := 'r-page-2099-01', p_honeypot := null);
      t_a4 := public.affiliate_referral_signup_with_notice(p_code := t_code, p_first_name := '484 Check', p_last_name := 'Told',
                p_phone := t_ph[2], p_email := null, p_notice := 'r-page-2026-11', p_honeypot := null);
      begin
        perform public.affiliate_referral_signup_with_notice(p_code := t_code, p_first_name := '484 Check', p_last_name := 'Probe',
                  p_phone := '0', p_email := null, p_notice := 'r-page-2026-11', p_honeypot := null);
        t_err2 := 'answered';
      exception when others then t_err2 := sqlstate || ' ' || sqlerrm;
      end;
    exception when others then t_err := sqlstate || ' ' || sqlerrm;
    end;
    execute format('set local role %I', v_role);
    perform set_config('request.jwt.claims', '', true);
    if t_err is not null then raise exception '484: the self-test''s sign-ups failed: %', t_err; end if;
    select c.id into t_told from public.customers c where c.referred_by = t_me and c.full_name = '484 Check Told' and c.deleted_at is null;
    select c.id into t_sem from public.customers c where c.referred_by = t_me and c.full_name = '484 Check Seminar' and c.deleted_at is null;
    select c.id into t_unk from public.customers c where c.referred_by = t_me and c.full_name = '484 Check Unknown' and c.deleted_at is null;
    if t_a1 ->> 'outcome' is distinct from 'registered' or t_a2 ->> 'outcome' is distinct from 'registered'
       or t_a3 ->> 'outcome' is distinct from 'registered' or t_a4 ->> 'outcome' is distinct from 'already_registered'
       or t_told is null or t_sem is null or t_unk is null
       or t_err2 not like 'P0001 CUSTOMER_PHONE_REVIEW%'
       or exists (select 1 from public.customers c where c.full_name = '484 Check Probe')
       or (select count(*) from public.referral_phone_notices n where n.referrer_customer_id = t_me or n.customer_id = t_me) <> 1
       or not exists (select 1 from public.referral_phone_notices n
                       where n.customer_id = t_told and n.referrer_customer_id = t_me and n.phone = t_ph[2]
                         and n.notice_version = 'r-page-2026-11' and n.referral_code = t_code and n.withdrawn_at is null)
       or (select array_agg(k order by k collate "C") from jsonb_object_keys(t_a1) k)
          is distinct from (select array_agg(k order by k collate "C") from jsonb_object_keys(t_a2) k) then
      raise exception '484: the self-test''s sign-ups are not as tested: % / % / % / % / %', t_a1, t_a2, t_a3, t_a4, t_err2; end if;

    -- My Network's fixture: a Tier 2 customer under the told one; a referral staff set (no sign-up); a Tier 1
    -- record holding 484's first draft's placeholder (AFF- and 8 characters: the phone policy refuses one now, so
    -- written with triggers off for that statement only); and marks that must not count: for the seminar
    -- referral one naming another referrer (the told customer stands in) and one with another number, and for the
    -- unknown-notice referral a valid one beside a withdrawn one (it asked for its number to be hidden).
    insert into public.customers (full_name, phone, referred_by) values ('484 Check Tier Two', t_ph[5], t_told);
    insert into public.customers (full_name, phone, referred_by) values ('484 Check Staff Set', t_ph[6], t_me);
    insert into public.customers (full_name, phone, referred_by) values ('484 Check Placeholder', t_ph[7], t_me);
    set local session_replication_role = replica;
    update public.customers set phone = 'AFF-' || t_sfx where full_name = '484 Check Placeholder' and referred_by = t_me;
    execute format('set local session_replication_role = %L', t_srr);
    insert into public.referral_phone_notices (customer_id, referrer_customer_id, phone, notice_version, referral_code, withdrawn_at)
      values (t_sem, t_told, t_ph[3], 'r-page-2026-11', t_code, null), (t_sem, t_me, t_ph[8], 'r-page-2026-11', t_code, null),
             (t_unk, t_me, t_ph[4], 'r-page-2026-11', t_code, null), (t_unk, t_me, t_ph[4], 'r-page-2026-11', t_code, now());

    -- As the affiliate, as the portal calls it: signed in (the API's role authenticated), auth.uid() its login.
    -- 1: told, proven, active; 2: the link not proven (the record made before the account, nothing else proves
    -- it); 3: proven again, suspended (never reactivated here: reactivation queues a WhatsApp and takes a sequence
    -- number).
    for i in 1 .. 3 loop
      if i = 2 then
        update public.customers set created_at = now() - interval '1 day' where id = t_me;
      elsif i = 3 then
        update public.customers set created_at = now() where id = t_me;
        update public.customer_affiliates set manually_suspended = true, status = 'suspended_manual' where id = t_aff;
      end if;
      t_err := null;
      perform set_config('request.jwt.claims', json_build_object('sub', t_uid, 'role', 'authenticated')::text, true);
      begin
        execute 'set local role authenticated';
        t_ans := public.affiliate_portal_network();
      exception when others then t_err := sqlstate || ' ' || sqlerrm;
      end;
      execute format('set local role %I', v_role);
      perform set_config('request.jwt.claims', '', true);
      if t_err is not null then raise exception '484: the self-test''s call as the affiliate failed: %', t_err; end if;
      if t_ans is null
         or jsonb_array_length(t_ans -> 'tier1') <> 5 or jsonb_array_length(t_ans -> 'tier2') <> 1
         -- the told referral: its number while proven and active; else the key with no number
         or (select r -> 'phone' from jsonb_array_elements(t_ans -> 'tier1') r where r ->> 'customer_name' = '484 Check Told')
            is distinct from (case when i = 1 then to_jsonb(t_ph[2]) else 'null'::jsonb end)
         -- every other Tier 1 row: the key with no number (the seminar website's, the unknown notice's, the
         -- withdrawn one, staff's and the placeholder)
         or exists (select 1 from jsonb_array_elements(t_ans -> 'tier1') r
                     where r ->> 'customer_name' <> '484 Check Told' and r -> 'phone' is distinct from 'null'::jsonb)
         -- every row: 480's keys, and 'phone' on Tier 1 only
         or exists (select 1 from jsonb_array_elements(t_ans -> 'tier1') r
                     where (select array_agg(k order by k collate "C") from jsonb_object_keys(r) k)
                           is distinct from array['booking_at', 'booking_state', 'customer_name', 'joined_at', 'phone', 'purchases',
                                                  'referral_date', 'tier', 'total_spent', 'your_commission'])
         or exists (select 1 from jsonb_array_elements(t_ans -> 'tier2') r
                     where (select array_agg(k order by k collate "C") from jsonb_object_keys(r) k)
                           is distinct from array['booking_at', 'booking_state', 'customer_name', 'joined_at', 'parent_name', 'purchases',
                                                  'referral_date', 'tier', 'total_spent', 'your_commission'])
         -- no other number anywhere: not the affiliate's own, the seminar one's, the unknown one's, the Tier 2
         -- customer's, staff's, the placeholder's (or what it held) or a mark's other number
         or (select bool_or(strpos(t_ans::text, substr(t_ph[k], 2)) > 0) from unnest(array[1, 3, 4, 5, 6, 7, 8]) k)
         or strpos(t_ans::text, 'AFF-') > 0
         or (i > 1 and strpos(t_ans::text, substr(t_ph[2], 2)) > 0) then
        raise exception '484: the self-test''s My Network (% of 3: told and proven, not proven, suspended) is not as tested: %', i, t_ans; end if;
    end loop;

    -- Signed out: My Network, the proof and the notices refused (no grant); a signed-in login: the proof and the
    -- notices refused; a login with no affiliate account: as before.
    for i in 1 .. 5 loop
      t_err := null;
      perform set_config('request.jwt.claims', case when i <= 3 then '{"role":"anon"}'
                                                    else json_build_object('sub', t_uid, 'role', 'authenticated')::text end, true);
      begin
        execute case when i <= 3 then 'set local role anon' else 'set local role authenticated' end;
        if i = 1 then perform public.affiliate_portal_network();
        elsif i in (2, 4) then perform public.affiliate_login_link_proof(t_uid, t_me);
        else perform count(*) from public.referral_phone_notices;
        end if;
        t_err := 'answered';
      exception when insufficient_privilege then t_err := '42501';
                when others then t_err := sqlstate || ' ' || sqlerrm;
      end;
      execute format('set local role %I', v_role);
      perform set_config('request.jwt.claims', '', true);
      if t_err is distinct from '42501' then
        raise exception '484: the self-test''s call % of 5 (signed out: My Network, the proof, the notices; signed in: the proof, the notices) was not refused: %', i, t_err; end if;
    end loop;
    t_err := null;
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
    begin
      execute 'set local role authenticated';
      perform public.affiliate_portal_network();
      t_err := 'answered';
    exception when others then t_err := sqlstate || ' ' || sqlerrm;
    end;
    execute format('set local role %I', v_role);
    perform set_config('request.jwt.claims', '', true);
    if t_err is distinct from 'P0001 Not an affiliate account' then
      raise exception '484: the self-test''s login with no affiliate account was not refused as before: %', t_err; end if;

    raise exception using errcode = 'P0484', message = '484: self-test done, undone';
  exception when sqlstate 'P0484' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
end $mig$;
