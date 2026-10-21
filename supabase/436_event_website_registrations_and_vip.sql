-- 436_event_website_registrations_and_vip.sql
--
-- AN EVENT'S OWN WEBSITE: FREE REGISTRATION FOR EVERYONE, VIP PAID ON TOP,
-- THE KEY MADE ON THE EVENT PAGE (the owner's request, 20 Oct 2026: the Free
-- Two Day Health Seminar by Rev 22 Global Energia, at
-- healthtalk-rev22energia.vercel.app)
--
-- WHAT WAS WRONG / WHY
--
--   The app takes website orders for one kind of event: a paid ticket per
--   checkout, from one website signed with one secret (web-ticket-order,
--   372-415, the Alaric birthday). The seminar is free for everyone, VIP is
--   bought per person on top (by one payer for several people, or later from
--   a link in the confirmation), the VIP perks include two vouchers on each
--   VIP's own account and socks or gloves handed out at the door, and
--   PayNow or bank transfer VIPs wait for a Manager. None of that fits a
--   web_orders row (one checkout, one invoice, one ticket line), and the
--   owner wants the key made on the Event page, shown once and kept hashed.
--
-- THE RULES (the owner, 20 Oct 2026; binding)
--
--   * Mon 23 and Tue 24 Nov 2026, 9 am to 7 pm both days, store "Energia
--     Van & RoadShow"; the venue is not confirmed: the website shows "Venue
--     to be announced" until it is set. No capacity, and never a capacity or
--     "seats left" shown to customers.
--   * Everyone registers free: each person picks Day 1, Day 2 or both; one
--     person may register several, each with a name, phone and email.
--   * VIP is S$72 per person and covers both days; chosen while registering
--     or bought later (an upgrade link). It includes a S$72 offset voucher
--     (SAVE72) and a 3-in-1 voucher, issued when the payment succeeds to
--     EACH VIP's own account (one payer may pay for several; each VIP still
--     gets their own invoice line, vouchers and guest record); taken back if
--     the VIP is refunded while unused (below); socks or gloves
--     chosen at the door, recorded by staff, the stock leaving Van &
--     RoadShow then; priority for the free therapies, personalised seating,
--     a VIP name tag and dinner with the founder, Ms Veronica, shown on the
--     guest list and at check-in.
--   * Every registration creates or matches a customer and is on the guest
--     list; matching follows 432/433 (phone + same-words name links; only
--     the phone or only the email inbox belongs to someone: held for staff).
--   * VIP payment: HitPay online, invoiced as soon as it succeeds; PayNow or
--     bank transfer with a reference, waiting on Website orders for a
--     Manager to confirm the money arrived.
--   * An affiliate's link makes each new person their referral (392/425,
--     with Q19 = A: an existing customer's phone under another name is
--     flagged for staff, not counted). Commission only on VIP, at the usual
--     rate, by the app's engine.
--   * The key: an Owner creates it on a new Website tab, it is shown once
--     and kept only hashed, Owners revoke it; the tab shows the endpoint,
--     the event code, code to copy and a test mode.
--   Defaults chosen (not asked): no early bird; refunds by the app's own flow.
--
--   The owner's answers, 20 Oct 2026 (binding):
--   * A FULL REFUND of a VIP ("Refund in full" on the Invoices page, not
--     only Cancel) takes back that VIP's UNUSED S$72 (SAVE72) and 3-in-1
--     vouchers, as Cancel does; if one was already used, staff are told
--     plainly before the refund, and the used one stays recorded. The
--     person is not VIP any more (their free guest record comes back) and
--     cannot get a second set by buying VIP again without paying.
--   * The seminar runs 9:00 am to 7:00 pm both days (not 10 am).
--   * The draft event "Two Day Health Seminar (Nov)" becomes this event at
--     go-live: renamed to the full title, Van & RoadShow only, its "2 Day"
--     S$72 option kept as the VIP ticket, its "1 Day" option removed (see
--     DEPLOY ORDER; nothing in production is changed by this file).
--   * The website keeps "socks or gloves while stocks last" and "free
--     therapies subject to on-site scheduling".
--   * Kept as built (not asked): the rate limits; family members sharing a
--     phone: the first is the customer, the others wait under To match;
--     sharing an email: one confirmation; 10 people per form; the same Meta
--     Pixel as the Alaric site; a VIP who registered for one day is
--     registered for both; VIP invoices show the two vouchers as free
--     lines; each new person on a form through an affiliate's link becomes
--     that affiliate's referral.
--
--   The owner's answers, 20 Oct 2026, round 3 (binding):
--   * If the VIP's customer already used SAVE72 (as an invoice's discount
--     voucher or a line's voucher) or a 3-in-1 voucher on a LATER invoice
--     that is not cancelled or deleted, an automatic FULL refund of their VIP
--     is REFUSED on every path (the guided Refund in full and its approval,
--     and a Finance-panel refund that would pay back the VIP ticket in full),
--     with a plain message naming that later invoice; an Owner or Manager then
--     decides the amount by hand (a part refund stays possible). The app does
--     NOT start marking held vouchers as used.
--   * VIPs sold at the counter (an invoice carrying the event's VIP ticket
--     option with SAVE72 and/or 3-in-1 as free lines) follow the SAME rules as
--     website VIPs: on a full refund their unused VIP vouchers are taken back,
--     and the rule above applies to them too. The free guest record logic
--     applies only where a website free record exists.
--   * The bug from the last final check is fixed: a VIP invoice refunded (or
--     cancelled), reopened and paid again no longer reads a voucher as used on
--     its next refund (the replacements apply_reopened_invoice_vouchers made
--     are counted).
--   * Kept: the Finance panel refuses a full VIP refund once a VIP voucher is
--     recorded used (staff use Refund in full, which explains); a reopened or
--     part-paid VIP shows "payment waiting" on the website; the website's
--     terms add that the value of a used voucher is kept on a VIP refund.
--   How they read (the review of round 3, 20 Oct 2026):
--   * "Every path" includes Cancel: a cancellation whose refund pays the VIP
--     ticket back in full (its request, its approval, its refund recorded),
--     and, once cancelled, recording money back that leaves the invoice
--     holding nothing. A cancellation that pays nothing back still goes (it
--     takes the unused vouchers back itself, as before).
--   * "Used ... on a later invoice" is read from the invoices: a SAVE72 (or
--     3-in-1) given as a discount on an invoice of that customer (or of
--     whoever holds one of the VIP's vouchers) made since the VIP invoice
--     was made, while it stood paid (not while it stood cancelled or
--     refunded in full: the owner, 21 Oct 2026, R6-7); whether it was the VIP's own
--     SAVE72 or one from another offer is not known, and the message says
--     only that such a discount was given (an Owner or Manager may allow
--     the full refund anyway, with a reason: the owner, 21 Oct 2026).
--   * A counter VIP for several people (two VIP lines, or one line of two,
--     with SAVE72 x2 and the 3-in-1 x2 free): each VIP ticket refunded in
--     full takes back its share (1 of the 2 of each), not every voucher on
--     the invoice; S$72 back on a line of two is one ticket.
--   * A part refund by hand leaves the person VIP with the unused vouchers
--     (the plan and the website terms say so); there is no "End VIP" action
--     (kept as built: the owner, 21 Oct 2026).
--
--   The owner's answer, 20 Oct 2026, 18:0x (binding): NO SELF-REFERRAL
--   (its phone and email part narrowed at ~20:15, below).
--   * A person registering through an affiliate's link who is that
--     affiliate (her own customer record) by name (the same words in any
--     order, 432's customer_names_match), by phone (as 425 reads a phone,
--     an old 8-digit number included) or by email inbox (432's
--     customer_email_match_key) is not referred and no commission can come
--     from it; the registration itself goes through, and staff see a plain
--     note ("Not referred: the same name as <affiliate>, the affiliate whose
--     link (<code>) was used. No commission comes from it."; now worded "She
--     earns no commission from it.", the owner, 21 Oct 2026, answer 4). For
--     new and existing customers, for every person on a form (the others on it are
--     still referred), when staff match a held person, and so for VIP
--     bought later (her name on a phone and email no customer has is held
--     for staff since 21 Oct 2026, answer 1 below, so her VIP lands on her
--     record and earns her upline as usual). Before, only the
--     customer found by phone or email was compared, so the affiliate
--     through her own link on a phone not on file became her own referral
--     and earned tier-1 commission on her own VIP.
--   How it reads (the review of round 4, 20 Oct 2026): "existing
--     customers" is the affiliate's own record. A person matched or
--     attached to another existing customer is that customer, not her,
--     whatever name, phone or email they share with her: already a
--     customer, not referred again (392's duplicate event), and any
--     referral they already have stands (so their VIP still pays their
--     referrer, as any purchase of theirs does).
--
--   The owner's answers, 20 Oct 2026, ~20:15 (binding):
--   * A. Someone with a DIFFERENT name who registers through an affiliate's
--     link on the affiliate's OWN phone or email inbox (her mother, a
--     friend she registered) is NOT treated as the affiliate: they become
--     her referral WITH A STAFF CHECK, as Q19 (shared phones) and 425's
--     /r/<code> sign-up: flagged, an Owner or Manager confirms, then
--     counted; commission only after the confirmation, on VIP only.
--   * B. KEPT: exactly the affiliate's name (the same words in any order)
--     is her (not referred) even on another phone and email; staff see a
--     note.
--   * C. KEPT: the affiliate's own upline earns commission as usual on the
--     affiliate's own VIP.
--   * D. An existing customer (not the affiliate) who comes through her link
--     keeps any referral they already have and is not referred again;
--     staff see a plain note ("Already a customer, so not referred again
--     through this link (<code>); their existing referral (by <name>)
--     still stands." / "...; they had no referral before, and none is
--     added.").
--   * E. The test suite's check that the register answer never names who
--     was matched reads the answer without its random VIP link tokens.
--   How they read (this file, 20 Oct 2026): the affiliate is her record or
--     her name (B); her phone or email inbox only says how else she was
--     recognised. Someone else on them is held for staff, as anyone on a
--     customer's phone or email is (433); linked to her record they are
--     her (self); made a new customer, they wait (referral_outcome
--     check_waiting): no referrer yet, 392's sign-up event (phone_shared,
--     counted for the link's hourly limit) and 425's pending
--     referral_signup_checks row naming her as the referrer and among
--     those they share with, so they are on the Affiliates page's "Check
--     these sign-ups". An Owner or Manager's decision there (425's
--     decide_referral_signup_check, unchanged) is followed by a trigger:
--     a different person becomes her referral (referred_by, dated when
--     they were made a customer, as 425 dates a sign-up that waits), and
--     the engine earns her commission then on each of their website VIP
--     invoices paid in full that has earned none yet, less any part refund
--     recorded meanwhile (a VIP paid later earns as any referral's
--     purchase); the same person is never referred. An older record of
--     theirs merged into the one made for them before the check makes them
--     an existing customer (D): the check refers nobody. "Commission only
--     after the confirmation" is why the referrer is not set before the
--     check (the engine pays any referred customer's purchase at once).
--
--   The owner's answers, 21 Oct 2026, ~00:30 (binding):
--   * 1. NAME-ONLY SELF MATCH: someone through an affiliate's own link with
--     her name (the same words in any order) but a phone and email no
--     customer has is registered (a guest on the list) and HELD under To
--     match for staff, her record the candidate: attached to her record they
--     are her (not referred; her own upline earns as usual on a VIP, as C);
--     made a new customer, it is a different person, and no referral comes
--     from this link. A VIP paid while held ends with the right commission
--     once staff decide (her upline through her record, once; nothing for a
--     new person).
--   * 2. Q19 FOR ANOTHER CUSTOMER'S PHONE: as the owner's Q19 ("flagged for
--     staff to confirm, then counted"), the referral and its commission wait
--     for the staff check exactly as on the affiliate's own phone or email:
--     no referrer and no commission until an Owner or Manager confirms a
--     different person; then the commission on their fully paid VIP is
--     earned once; the same person: none.
--   * 3. SAVE72 FULL-REFUND BLOCK: stays on by default (a SAVE72 or 3-in-1
--     used on a later invoice stops an automatic full VIP refund), but an
--     Owner or Manager can override it and allow the full refund, giving a
--     reason that is recorded (audit) and shown in the plan; staff (not
--     Owner or Manager) cannot.
--   * 4. WORDING: the affiliate's own guest row says "She earns no
--     commission from it" (her upline still earns as usual).
--   * Kept as built: no "End VIP" action; a suspended affiliate's confirmed
--     referral is still made, its commission recorded as blocked; a SAVE72
--     shared on one counter invoice for several VIPs comes back only when all
--     are fully refunded.
--   How they read (this file, 21 Oct 2026): 1. hold_reason affiliate_name,
--     referral_outcome self while held; a held person recognised by her
--     name in other ways too (her name and her email inbox) is the same: her
--     record linked, herself; made a new customer, someone else, not referred
--     (the note says which). Her link switched off (a suspended affiliate) is
--     the same (the review of 21 Oct 2026): held under her name
--     (referral_outcome link_off), linked to her record she is herself (her
--     upline earns on her VIP; her row reads self, R6-6 below), made a new
--     customer nobody is referred; the note names the link as switched
--     off. 2. Someone made a customer by
--     staff on a phone already on another customer's record (phone_in_use, several name
--     matches, an old number) waits as in A: no referrer, 392's phone_shared
--     event, 425's pending check sharing with that phone's customers (not the
--     affiliate, unless it is her phone or email too); the same trigger
--     refers and earns on "different person". A held person on another
--     customer's email inbox only (not a phone) waits the same way since
--     R6-1, below. 3. The later-use rule's blocker becomes the plan's override
--     vip_voucher_used_later (Refund in full, a part refund that pays the
--     ticket back in full, Cancel): staff may ask; 417's approval, an Owner's
--     or Manager's alone, refuses it without a reason and keeps the reason on
--     the request and in its audit row; 436's trigger lets that approval's
--     refund through and writes vip_refund_used_later_allowed on the VIP
--     invoice; a Cancel approved so may have its money recorded as paid back
--     afterwards; the Finance panel still refuses a full refund. The review of
--     21 Oct 2026: once 417 stores the approval, a second row on the VIP
--     invoice (vip_refund_used_later_reason) gives the reason; a cancelled
--     VIP invoice counts only discounts given before its cancellation (the
--     cancellation took its vouchers back), so the money a Cancel approved
--     before the later invoice owes is paid back in full as usual.
--
--   The owner's answers to round 6's questions, 21 Oct 2026 (binding: "go
--   with what you recommend"):
--   * R6-1. Someone held only because their EMAIL inbox is another
--     customer's (no shared phone), through an affiliate's link on the
--     website, is treated as answer 2: made a customer by staff, no referrer
--     and a pending check; no commission until an Owner or Manager confirms
--     a different person; then their fully paid VIP earns once; the same
--     person: nothing.
--   * R6-2. 425's own /r/<code> page and 437 are not changed here (another
--     session's): a follow-up only.
--   * R6-4. Staff may still make a new customer for an affiliate_name hold;
--     the To match panel warns that a new customer earns her upline nothing
--     (the Event page's; no change here).
--   * R6-5. The commission on a VIP paid while the staff check waited is
--     dated the day an Owner or Manager confirms (Singapore), so a month
--     already paid out is not changed.
--   * R6-6. Through a switched-off (suspended) affiliate's link, once staff
--     link the held person to her own record, the guest row shows the self
--     outcome and its note, as on a live link.
--   * R6-7. After a cancelled or refunded VIP invoice is reopened, a SAVE72
--     or 3-in-1 used before the cancellation still counts: a later full
--     refund or cancel needs the Owner's or Manager's override (built here:
--     436's own event_vip_used_later, nothing else patched).
--   * F6 (cancel, reopen, cancel again under-counts vouchers in 409's and
--     417's functions) is outside 436: not fixed here; reported to them.
--   How they read (this file, 21 Oct 2026): R6-1 is staff making a customer
--     of someone held for an email inbox (433's email_in_use, or phone and
--     email): the check names those whose inbox they share, the audit row
--     and the note say "email inbox". R6-5: the engine earns as before, then
--     436 dates the rows it just made sg_today(). R6-7: a discount on an
--     invoice made while the VIP invoice stood paid counts; a time it stood
--     cancelled (invoice_cancelled) or with all its VIP tickets refunded in
--     full (436's vip_refund_vouchers row, which now says how many of how
--     many), up to the next invoice_reopened, does not (its vouchers had been
--     taken back); one VIP of two refunded leaves the other's time running.
--
--   The owner's answers, 21 Oct 2026, ~00:45 (round 7; binding: "For
--   questions, I will go with what you recommend"):
--   * The home page signs people up free; VIP is offered straight after; then
--     the thank-you page (and later the person's own VIP link page) asks each
--     person, all optional: food (No preference / Vegetarian / Vegan / Halal
--     / No beef / Other, 60), allergies (No / Yes, which, 120), for each of
--     their days the whole day or part of it (arriving and leaving around,
--     half hours within the event's hours), the talks that interest them (the
--     event's titles), what to prepare (wheelchair access, help with walking
--     or stairs, a seat near the front, other, 120), how they heard (nine
--     choices, Other 60) and a question for the speakers (300). Not asked:
--     health conditions, age, language.
--   * The answers are kept IN THE APP per guest: Guests badges (food, allergy
--     in red, part-day times, access) and the full answers in the guest's
--     detail; Check-in shows allergy, food and access; whoever can edit the
--     guests edits them on a guest's behalf, audited; a planning summary (per
--     day; VIP food and allergies for the founder's dinner; talks; how they
--     heard); in the guest export; copied to the website's sheet.
--   * The talk titles are set on the Website tab; until then a suggested
--     list (general wellness wording, no medical claims).
--   * The website saves them with its key AND the person's own VIP link
--     token; idempotent, validated, a test key's a dry run, rate-limited,
--     replay-protected and logged like the other messages; while the person
--     is registered and until the event has ended. RLS on, no client
--     grants, service role only for the website path.
--   The review of round 7 (21 Oct 2026; the owner's answers above, read
--   closer): the audit log keeps who changed a guest's answers, when, which
--   choices and WHICH free texts changed (texts_changed), not the texts
--   (allergy details, the other food, access and how-heard texts, the
--   question): Owners, Admins and Managers of every store read the audit
--   log, not only those who see the event's guests (S1). A VIP whose VIP
--   record still stands (their VIP invoice reopened, or a payment taken
--   off) is counted once, as a VIP, not also as a payment waiting (K30's
--   expression gains "and not exists (... vg.id = p.vip_guest_id and
--   vg.status = 'registered')"). A test key's VIP (the dry run's) comes on
--   every day, as a live VIP record does. The summary counts talks ignoring
--   case, as the check matches them. Through a switched-off link, the
--   affiliate matched straight away on her own record reads self too (R6-6,
--   as on a live link), the test key the same.
--   How they read (this file, 21 Oct 2026): the answers of a website person
--     sit on their first (free) guest record and follow them to their VIP
--     record; Off and off sale do not stop answers (only the event's end
--     does; event_info and person say planning_open); a save based on an
--     older version is refused with what is kept now (staff may have changed
--     them by phone); the same answers again change nothing; whoever sets the
--     venue sets the talk titles (Owner, Admin, Manager); the sync gives the
--     website a website person's answers only (staff and counter guests'
--     stay in the app); website saves are audited too, as the website (the
--     choices and which free texts changed, never the texts).
--
--   The owner's answers to the review of round 7, 21 Oct 2026 (round 8;
--   binding: "go with what you recommend"):
--   * P1. Double VIP. On the Event page's To match panel, a candidate
--     customer who is already a guest of this event says so: their days,
--     and VIP paid (the invoice number) or VIP payment waiting. When the
--     held person paid (or waits on) a VIP and the candidate already holds
--     one (paid or waiting), the window warns before linking: "Linking
--     gives <name> two VIP payments for this event. Refund one after
--     linking." Linking stays allowed (it is the right record). Once one
--     customer holds two VIP payments for the event (paid or waiting),
--     their guest rows and the Planning tab's VIP block say "Two VIP
--     payments: refund one", and the summary counts that person once.
--   * P2 (the thank-you page reads each person's VIP state again), P3 (the
--     Meta Pixel only on the live site) and P4 (the planning card's legend
--     inside its border on phones) are the website's: no change here.
--   * Kept as built: R6-5's limit (NOT COVERED), the privacy wording ("only
--     our staff", cleared within 7 days, a note of earlier choices kept),
--     and the audit keeping which free texts changed, not the texts.
--   The review of round 8 (21 Oct 2026, applied): the planning summary
--     counts such a customer once but keeps the answers and the days of
--     all their records (a counter VIP with no answers linked to a held
--     person who answered keeps her allergy and food; two transfers on two
--     free records count on both days); "Find another customer..." warns
--     as the listed candidates do, and a cancelled row is not flagged (the
--     Event page's); the website's (P3, P4) are its own.
--   How they read (this file, 21 Oct 2026): a VIP payment a customer holds
--     (event_vip_holders) is a website person's VIP invoice still standing
--     (paid; reopened or part paid: waiting), a payment of theirs not
--     invoiced yet (HitPay paid while held or in Record only, a PayNow or
--     bank transfer waiting for a Manager: waiting; a checkout opened and
--     not paid is not one), or a VIP ticket sold at the counter still on
--     the guest list (paid, or its invoice not paid yet: waiting); never a
--     test key's, a closed person's or a held person's (no customer yet:
--     the panel reads the held person's own as vip_payment). Counted once:
--     the summary counts that customer on one record (their VIP record, else
--     the first), with the answers of their records (the VIP record's, else
--     the first answered: a held person's answers stay on her free record
--     until her transfer is confirmed) and every day of their records, and
--     does not count their payments waiting apart while one of their VIP
--     records stands (two waiting count once). Invoice numbers show to those with access to the
--     website's store, as on the guest rows.
--
-- WHAT THIS DOES
--
--   1. Tables (row level security on, no policy; the service role's alone):
--      event_web_settings (one per event: code, mode Off / Record only /
--      Live, venue, store, the profile that raises the invoices, the VIP
--      ticket, the VIP vouchers, the gifts, the HitPay / PayNow / bank
--      methods, the customer source, the sync URL), event_web_keys (SHA-256
--      of each key, its hint, live or test, revoked), event_web_requests
--      (each write's request id, body md5 and answer, so a retry gets the
--      first answer; reads counted), event_registrations and
--      event_registration_people (who registered, how each was matched,
--      held for staff or not (and why: affiliate_name for her name on a
--      phone and email no customer has, 21 Oct 2026), their free and VIP
--      guest records, the referral (and, for the affiliate herself, how she
--      was recognised: referral_self_by; someone else on her phone or email,
--      or on another customer's phone, made a customer: check_waiting, then
--      check_confirmed or check_same_person), the VIP link token),
--      event_vip_orders and
--      event_vip_order_people (each VIP payment and its people, their
--      invoices), event_vip_gifts (socks or gloves given, with the Record use
--      number), event_planning_answers (one guest's planning answers, a
--      version, who changed them last; round 7) and event_web_settings' talk
--      titles (null: the suggested list).
--   2. event_web_call(key_hash, request_id, type, body): the one function the
--      new edge function event-website calls (the service role's only). It
--      checks the key by its hash (a deleted event's keys answer nothing),
--      the event code, the request id (a repeat answers as the first;
--      another body is request_conflict) and the rate (per key, 120
--      sign-ups, checkouts and transfers in 10 minutes; HitPay's payment and
--      refund notices have their own 600, so sign-ups never block a payment;
--      planning answers their own 300), then runs one message as the
--      settings' acting profile: event_info, referral_info, register,
--      person, vip_checkout, vip_paid, vip_transfer, vip_refund, sync,
--      planning_answers.
--   3. register: each person is matched as 433 matches (an exact or
--      same-words name on the phone links; the phone, the Gmail inbox or
--      several names hold them for staff; nobody makes a new customer with
--      the website's source), and goes on the guest list at once as a free
--      guest on their days. The answer never says who was matched, made,
--      held or referred. A repeat (phone + same words) with the email they
--      registered with (its inbox) adds days to a guest still on the list
--      (one staff took off stays off; the attempt is audited for staff);
--      with any other email it is "already registered" and nothing more: no
--      VIP link, id, days or names. person shows the others on the form by
--      first name, days and VIP state only, never their links or ids.
--      Through an affiliate's link each new person is her referral (392/425,
--      Q19 = A), except a person found to be the affiliate herself
--      (event_web_check_self_referral: her record, or her name in the same
--      words; then her phone and email inbox are noted too), at
--      registration, while held and when staff match them: referral_outcome
--      self, no referred_by, no referral event or check, and an audit row
--      filed under affiliate (event_registration_self_referral). Her name on
--      a phone and email no customer has is held for staff (affiliate_name,
--      her record the candidate; 21 Oct 2026; through her link switched off
--      too): linked to her record, she is herself; made a new customer,
--      someone else with her name, not referred. Someone else on her own phone or email inbox
--      (event_web_affiliate_contact), or on another customer's phone (Q19)
--      or email inbox (R6-1), is held for staff; made a customer, they wait
--      for 425's check (check_waiting; section 10). A person matched or attached to another
--      existing customer is never her (already_customer as before, a
--      duplicate event; the mark is cleared when staff attach a held one to
--      someone else). event_web_referral_note gives the plain note staff see
--      on the Guests tab, To match, the export and the Website tab's test
--      registrations: the affiliate herself ("She earns no commission from
--      it"); held under her name (what linking her record or making a new
--      customer does), or made a new customer (someone else, not referred);
--      an existing customer (their referral stands, or none is added);
--      someone else on her phone or email, or on another customer's phone
--      (held, a test key's too: what linking or making a customer does;
--      waiting; merged into another record before the check, or an older
--      record merged into theirs; checked, and why not referred when not).
--      A test key's registration says the same and writes no audit row.
--   4. VIP: one invoice per person, made out to them, at the settings'
--      store: the VIP ticket (S$72, every day) and the VIP vouchers free
--      ("Included with VIP · <event>"). The existing paid trigger issues the
--      vouchers to the person, the engine earns commission for their
--      referrer, the guest list counts the VIP ticket; the person's free
--      record is parked meanwhile ("Upgraded to VIP · INV-…") and comes back
--      by itself when that ticket is cancelled or refunded (a trigger), with
--      the days they came. One HitPay payment is a payment of the unit price
--      on each invoice with one reference; all of an order's invoices are
--      made, or none (needs review, with the reason). HitPay is invoiced at
--      once while Live; Record only keeps it; a held person's payment waits
--      and is invoiced once staff match them; PayNow and bank transfers
--      always wait for a Manager (Create invoices; an Owner or Manager may
--      enter the amount that really arrived, audited). A transfer sent again
--      with the same people, amount, reference and day answers as the first.
--   5. The Event page: event_web_settings_get / _save / set_venue,
--      event_web_key_create / _revoke (the key made here, returned once),
--      event_web_test_clear, event_web_guest_extras (VIP, To match, gift,
--      referral and VIP link per guest; three index lookups per person to
--      match, not a scan of every customer), event_registration_attach /
--      _create_customer / _close (433's To match), event_vip_orders_list /
--      _order_invoice / _order_dismiss / _order_close_refunded, and
--      event_vip_gift_give / _undo (Record use at the settings' store: a
--      USE number, a stock movement, an audit row), event_planning_list /
--      _save / _summary and event_web_set_talks (round 7, item 11). Those
--      that match people, make invoices or set orders aside also need the
--      settings' store (as 415's web_order_resolve).
--   6. The first patched function: event_ticket_line_check lets a paid VIP
--      order's invoices through when VIP was taken off sale after the
--      payment (the owner's 415 rule: money taken is honoured), as it does
--      for web_orders. Two triggers on event_guests (the VIP record follows
--      its ticket; a parked record is not restored by hand; an old VIP
--      invoice is not reopened while a newer VIP record stands) and one on
--      events (not deleted while the website is on or VIP money waits; once
--      deleted, its keys are revoked, audited).
--   7. pg_cron job event-website-sync-ping every 10 minutes (when pg_cron is
--      installed), as 381: {"event": "<code>"} to the sync URL.
--   8. A VIP refunded in full (the owner, 20 Oct 2026). The vouchers that
--      come with VIP are free lines on the VIP invoice, and the refund engine
--      (417's refund_invoice_recorded, unchanged) takes back only vouchers
--      that were paid for, so "Refund in full" left them with the customer.
--      A trigger on invoices (invoices_vip_vouchers_follow_refund) now takes
--      back a website VIP's unused vouchers once the invoice is refunded or
--      its VIP ticket paid back in full, whatever path recorded it, exactly
--      as cancel_invoice_recorded does (revoked, cancelled_unused_value, so a
--      reopened invoice gives them again only once paid again; limited stock
--      back), each audited (vip_voucher_taken_back; the invoice's row names
--      any used one kept). A used one stays as it is. One moved to another
--      customer (the Finance panel's Move) is not used: its replacement on
--      the other account is taken back, or named once used (as 417's
--      cancellation counts transferred_value). Cancel is left to take
--      them back itself, as before (also when its refund is recorded first).
--      The guided Refund / Cancel shows it first: invoice_action_plan (417's,
--      the second patched function, two anchors) adds, for such a refund,
--      "Take back the unused ... that came with VIP from ..." and the
--      vouchers under "Credits and benefits cancelled"; when one was used,
--      an override vip_voucher_used names it ("... has already used the ...
--      It stays recorded as used ..."), so the refund needs a reason. Staff
--      are told before the refund on every path: a refund that pays back
--      the VIP ticket recorded any other way (the Finance panel's refund)
--      is refused while one is used ("... has already been used ... Use
--      Refund in full on the invoice ..."); with nothing used it goes
--      through, taking them back. Only refunds written by the call being
--      run are checked: a later change to the invoice is never refused for
--      an earlier one (round 3). A partial refund that leaves
--      the VIP ticket standing changes nothing. The person's VIP state
--      reads refunded (their free record is back), so VIP can be bought
--      again, paid for: one new invoice, one new set. Their VIP invoice
--      reopened reads pending (paid only once it is paid in full again),
--      and no second VIP is sold over it (payment_waiting).
--   9. Round 3 (the owner, 20 Oct 2026). event_vip_invoice_items says which
--      lines are a VIP's: a website VIP's invoice (its ticket and free
--      voucher lines, as before), or a VIP sold at the counter (an invoice
--      with the event's VIP ticket option, the Website tab's, and one or more
--      of its VIP vouchers as free lines: that ticket and those lines; any
--      other free or paid voucher stays the normal flow's). Section 8 now
--      reads those lines, so a counter VIP refunded in full has its unused
--      VIP vouchers taken back, is shown first, and meets the used rules.
--      event_vip_take_back says what is due back: per VIP voucher line, its
--      share of the VIP tickets refunded in full (floor(tickets refunded in
--      full x the line's quantity / VIP tickets sold), less what was taken
--      back already; a ticket line counts floor(refunded / unit value)), the
--      held vouchers it takes the units from (one unit of two leaves the
--      other held: its quantity goes down, cancelled_unused_value up, stock
--      back by one), and what it cannot take back (used). A website VIP has
--      one ticket, so all of its unused vouchers, as before; the plan shows
--      "Take back 1 of the 2 unused ..." for a counter VIP for two.
--      event_vip_used_later finds a later invoice (made since the VIP
--      invoice was made, while it stood paid: not after a cancellation or a
--      refund in full of all its VIP tickets, which took the vouchers back, and
--      before the next reopening (R6-7; a discount given before a
--      cancellation still counts after the reopening); not cancelled or
--      deleted) of the VIP invoice's customer, or of anyone holding one of
--      its VIP vouchers, with one of those voucher kinds as its discount
--      voucher or a line's voucher (read from the invoices: no held voucher
--      is marked used). While there is one, the plan of a refund (or a
--      cancellation) that would pay a VIP ticket back in full carries the
--      override vip_voucher_used_later naming it (the owner, 21 Oct 2026; it
--      was a blocker: "A discount with the ... was given to ... on INV-...,
--      an invoice made after this VIP invoice (...), so the VIP ticket is not
--      refunded in full automatically. An Owner or Manager may allow the full
--      refund, giving a reason (it is recorded); or refunds less, as a part
--      refund in the Finance panel, less than the ticket (the customer then
--      stays VIP and keeps the unused VIP vouchers)."), shown among what the
--      plan does ("Owner/Manager override required: ..."). Staff may raise
--      the request (request_invoice_action_v2, 417's, unchanged); its
--      approval (resolve_invoice_action_v2, 417's, unchanged: an Owner's or
--      Manager's alone) refuses it without a reason for the override, keeps
--      the reason on the request (payload overrides) and in its audit row
--      (invoice_action_approved), and a request asked for before the later
--      invoice first shows the revised plan. The trigger refuses money paid
--      back by the statement being run that pays a VIP ticket back in full
--      (or, on a cancelled invoice, leaves it holding nothing), on every
--      path ("... Nothing was recorded."), unless that money is the approval
--      being run (the request resolve_invoice_action_v2 names in
--      invoice.therapy_reviewed, its refund rows carrying its id, an Owner or
--      Manager calling) or, on a cancelled invoice, a Cancel approved with
--      the override's reason since it was last paid; then it writes
--      vip_refund_used_later_allowed on the VIP invoice (the request, who
--      allowed it, the later invoice; the reason when the request holds it).
--      The approval's reason is stored by 417 after its refund ran, so a
--      trigger on approval_requests (approval_requests_event_vip_reason,
--      trg_event_vip_used_later_reason; as the approved request's overrides
--      are stored) adds it to the VIP invoice's audit log once
--      (vip_refund_used_later_reason). A Cancel
--      approved without the override, the discount given before the
--      cancellation: its money paid back in full is refused, saying to record
--      a part refund or to reopen it and cancel it again. Only refunds
--      written by that statement count (their created_at at or after
--      statement_timestamp()), so a later change (a payment corrected)
--      is never refused for an earlier refund. A part refund (less than the
--      ticket) still goes from the Finance panel (Owner or Manager); one that
--      completes the ticket is refused there ("... Use Refund in full on the
--      invoice: an Owner or Manager can allow it there with a reason ...").
--      invoice_action_plan's first patch adds the override line. The
--      used sums count what an invoice reopened and paid again replaced
--      (invoice_reopen_vouchers applied), so a refund after refund (or
--      cancel), reopen and pay again reads nothing used. Website orders:
--      HitPay's refund notice is also covered by money recorded as refunded
--      on the order's invoices since they were last reopened (a part refund
--      by hand), and the Event page says so.
--  10. The owner's answers ~20:15 (A, D) and 21 Oct 2026 (2: another
--      customer's phone too; R6-1: another customer's email inbox too). The trigger
--      referral_signup_checks_event_web_decided (after an update of status
--      on 425's referral_signup_checks, from pending) runs
--      trg_event_web_referral_check_decided: for each live person waiting
--      (check_waiting) on that customer, different_person sets referred_by
--      (the affiliate), referral_source affiliate_link, referral_code_used
--      and referred_at (when they were made a customer), audited
--      (referral_registered, with the check), when the record is not
--      deleted and has no referrer yet, no record made before it was merged
--      into it (merge_customer_records' customers_merged row: then they are
--      an existing customer, D), the affiliate is not deleted and no cycle
--      would be made; then, while the affiliate is their referrer,
--      earn_invoice_commission (the engine, unchanged) on each of their
--      website VIP invoices paid in full with no commission row yet, dated
--      the day of the check in Singapore (R6-5: the rows it just made get
--      invoice_paid_date sg_today()), and after it the engine's refund step,
--      adjust_invoice_line_commission_refunds (unchanged, as
--      reconcile_invoice_commissions runs it after earning), so a part
--      refund recorded while the check waited is taken off as it is for any
--      referral (S$20 back on S$72: S$7.80 and S$0.39, not S$10.80 and
--      S$0.54); the person reads check_confirmed. same_person:
--      check_same_person, nothing referred or earned. The note says why
--      someone checked was not referred (their record gone, the
--      affiliate's gone, another referrer, an older record merged in).
--  11. Planning answers (the owner, 21 Oct 2026, round 7). planning_answers
--      (event_web_planning_answers) saves each person's answers by their own
--      VIP link token, people independent: refused when the token is not this
--      key's (person_not_found), they are not registered (person_cancelled),
--      a day is not theirs (day_not_chosen), a time is outside the event's
--      hours or its half hours (outside_hours), a talk is not offered
--      (talk_not_offered) or the answers changed since the version sent
--      (changed_meanwhile, with what is kept); the whole call is closed once
--      the event has ended (event_web_planning_closed). A test key checks and
--      keeps nothing. event_planning_check is the one validator,
--      event_planning_write the one writer (a version per change, audited:
--      who, when, the choices and which free texts changed, not the texts).
--      The Event page: event_planning_list (badges, detail, export,
--      check-in), event_planning_save (a staff edit, with a note, the version
--      it was based on), event_planning_summary (per day, VIPs and VIP
--      payments still waiting, talks, how they heard, questions),
--      event_web_set_talks (Owner, Admin, Manager, as the venue). event_info
--      returns the titles (null until saved) and whether answers can be saved
--      (planning_open); person the person's own answers and planning_open;
--      sync carries a website person's answers only (staff and counter
--      guests' stay in the app); the readiness list says when the titles are
--      still the suggested ones.
--  12. Two VIP payments for one customer (round 8, the owner 21 Oct 2026:
--      P1). event_vip_holders(event) lists each VIP payment a customer holds
--      for the event (the service role's only). event_web_guest_extras
--      gives each To match candidate's place on the event (guest: their
--      days and VIP payments, paid with the invoice number or waiting; null
--      when they are not a guest), each hold's vip_payment (a payment of
--      theirs, paid or a transfer sent, waits for the match), each guest
--      row's vip_double and the list vip_doubles (customer, name, payments);
--      event_planning_summary counts such a customer once and lists them in
--      its VIP block (doubles).
--
-- NOT CHANGED
--
--   web-ticket-order and every web_order_* function, the Alaric channel and
--   its sync; event_save, the Event editor, event_guest_list,
--   event_check_in, event_delete (a trigger guards it); the commission
--   engine, voucher issuing, cancel_invoice_recorded, refund_invoice_recorded
--   and resolve_invoice_action_v2 (used as they are; a trigger follows a VIP
--   refunded in full, and one on approval_requests adds an override's reason
--   to the VIP invoice's audit log);
--   affiliate_referral_signup, /r/<code> (425's own sign-up still refers
--   someone on another customer's phone at once, with its pending check:
--   the owner's answer 2 of 21 Oct 2026 is this website's), submit_health_survey;
--   decide_referral_signup_check, referral_signup_checks_pending and
--   referral_signup_checks' rules (rows of the same shape; a trigger follows
--   a decision on a check 436 made, section 10); every existing grant.
--   Round 7: event_guest_list, event_save_guest, event_check_in and
--   event_web_guest_extras (the answers are read beside them);
--   event_web_settings_save (it keeps the talk titles as it keeps the venue);
--   reconcile_invoice_commissions and the engine (R6-5 dates the rows 436's
--   trigger had them make).
--   Round 8: event_registration_attach (linking stays allowed; the warning
--   is the Event page's), event_guest_list and the guest list's counts.
--
-- NOT COVERED (told to the owner)
--
--   * The name alone makes a person the affiliate, as the owner said (B):
--     someone else with her name in the same words is not referred through
--     her link either (staff see the note). A VIP the affiliate buys on her
--     own customer record still earns HER referrer (her upline) tier-1
--     commission, as any purchase of hers does (C). Held under her name
--     (21 Oct 2026), staff decide: a customer made for her by mistake (staff
--     pressing "make a new customer" for the affiliate herself) has no
--     referrer, so her VIP on it earns her upline nothing; merging it into
--     her record later does not pay it (a merge earns no commission); the
--     To match panel warns before (R6-4, the Event page's).
--   * Her name typed differently (an honorific such as Ms or Mdm, a typo, a
--     nickname) together with a phone and email not on her record is not
--     recognised: she becomes a new customer referred by herself and her
--     VIP earns her tier-1. On her own phone or email she is held, and
--     linking her record (or the check) catches it.
--   * Q19 for someone ELSE's phone now waits as on hers (21 Oct 2026), and
--     so does someone held for another customer's EMAIL inbox only (R6-1);
--     425's own /r/<code> sign-up and 437 still refer at once with a pending
--     check (not this file's; reported as a follow-up, R6-2).
--   * Someone waiting for the check has no referrer yet, so a referral
--     promotion does not list them until it is decided (425's sign-up lists
--     them as not counted). On the Affiliates page their row shows the
--     affiliate under "Phone already used by" (425's column) also when only
--     her email inbox is shared, and so the customers whose email inbox
--     someone held for it shares (R6-1).
--   * A VIP paid while the check waited earns its commission when an Owner
--     or Manager confirms, dated that day in Singapore (R6-5), so a month
--     already paid out is not changed. If the engine later works that
--     invoice's commission out again (a correction, refund or reopening:
--     reconcile_invoice_commissions, not 436's), what it earns again is
--     dated by the invoice's paid date, as for any invoice. Its Legacy snapshot (taken
--     when paid) stays without an affiliate. A part refund recorded while
--     it waited is taken off then (the engine's refund step), as for any
--     referral. Other purchases before the check earn nothing; after it,
--     as any referral's. A VIP sold at the counter before the check is not
--     earned then.
--   * A customer made for someone else on her phone or email who is given a
--     referrer by hand before the check: the decision then refers nobody
--     (the note says "Checked as a different person, but not referred
--     ..."). One merged into another record before the check: the check
--     stays on the merged record (425's merge), so deciding it changes
--     nothing here; the record kept is not referred through the link (as
--     any existing customer), and the note says so ("Not referred through
--     this link (<code>): the customer made for them was merged into
--     another record before the check; ..."). An older record merged INTO
--     the one made for them (that one kept) before the check: they are an
--     existing customer (D), the check refers nobody and the note says so
--     ("... an older customer record was merged into the one made for them
--     before the check, ..."); the merge does not carry the older record's
--     own referral over (merge_customer_records), so a referral it had is
--     the Owner's to carry over (reassign_customer_referrer). A record made
--     after theirs and merged into it does not stop the referral.
--   * The affiliate suspended (or no longer an active affiliate) when an
--     Owner or Manager confirms the check: the referral is still made
--     (dated when they were made a customer, as 425 dates a sign-up that
--     waited), and the engine records the commission on their VIP as
--     blocked (never paid, never released), also for a VIP paid before
--     she was suspended (kept as built: the owner, 21 Oct 2026). Her record
--     deleted meanwhile: nobody is referred, and
--     the note says why.
--   * Someone held on a phone that is already on three customers' records:
--     the held note still offers "make a new customer", and making one is
--     refused (CUSTOMER_PHONE_LIMIT, whose message says why); staff link
--     one of the records, or free the phone first.
--   * The owner's setup (DEPLOY ORDER 5-9): the draft event edited into this
--     one, SAVE72's price at Van & RoadShow (a free voucher line still needs
--     a store price), the Website tab's settings and keys.
--   * The Invoices page's Finance panel, where an Owner or Manager records a
--     refund straight away, shows no plan: with nothing used it takes the
--     unused VIP vouchers back too; once one is recorded used it refuses a
--     refund that pays the VIP ticket back in full (money already returned
--     for such a VIP is recorded through Refund in full, with a reason);
--     once one was used on a later invoice it refuses that on every path,
--     and a part refund there is the way (round 3). Showing the plan in the
--     panel itself is a change to the Invoices page, not made here.
--   * A VIP sold at the counter: staff add the vouchers by hand as free
--     lines (then the refund rules are a website VIP's, round 3); the guest
--     is VIP at the door all the same. Its guest record is the ticket's
--     (370's): there is no website free record to bring back.
--   * A 3-in-1 cannot be put on an invoice as a discount (it is not a
--     discount voucher), so the later-use rule can only find SAVE72 (or
--     another discount voucher among the VIP vouchers); a 3-in-1 used at a
--     session counts once it is recorded used (status redeemed), as before.
--   * The later-use rule cannot tell the VIP's own SAVE72 from one given at
--     the counter from another offer (production, read 20 Oct 2026: SAVE72
--     is a line voucher on 64 invoices not cancelled or deleted, for 54
--     customers, 8 of them more than once, and no customer holds a SAVE72
--     voucher): such a customer's VIP is not refunded in full automatically
--     either; an Owner or Manager allows it with a reason (21 Oct 2026).
--   * The override is given on the guided Refund in full or Cancel only. The
--     Finance panel's own refund of the VIP ticket in full stays refused
--     (its message says to use Refund in full), and so does money paid back
--     in full on a VIP invoice cancelled without the guided Cancel's
--     override when the discount was given before the cancellation (a part
--     refund goes; or an Owner or Manager reopens it and cancels it again
--     with the guided Cancel). A discount given after the cancellation is
--     not counted (the review of 21 Oct 2026). The 436 audit row written
--     during the refund names the request; the reason follows in a second
--     row (vip_refund_used_later_reason) as 417 stores the approval (a
--     Cancel's money recorded later: its row quotes the reason).
--   * A VIP invoice reopened still counts a discount given while it stood
--     paid before its cancellation or refund (R6-7); one given while it
--     stood cancelled, or with all its VIP tickets refunded in full, does
--     not. A refund in full that
--     took no VIP voucher back and found none used (all moved away) writes
--     no vip_refund_vouchers row, so a discount given after it counts once
--     the invoice is reopened (an Owner or Manager then allows the refund
--     with a reason). After a reopen the guided Cancel may also ask for
--     voucher_redeemed overrides that are not real: 417's
--     cancelled_invoice_used_value does not count what a reopen replaced
--     (F6: outside 436; passed to 417's and 434's owners, 21 Oct 2026).
--   * A part refund by hand leaves the person VIP, with the unused vouchers
--     and the VIP perks; nothing takes them back by hand, and there is no
--     "End VIP" action (kept as built: the owner, 21 Oct 2026).
--   * A voucher of which one unit of two was taken back (a counter VIP for
--     two, one refunded) cannot be moved by the Finance panel's Move until
--     the invoice is settled (417's rule for reserved cancelled units).
--   * Refunding in HitPay stays the Owner's job in HitPay; the app records
--     HitPay's refund notice and shows it until the VIP invoices are
--     cancelled or refunded here, or that much is recorded as refunded on
--     them (a part refund by hand, round 3).
--   * The live key is trusted as HitPay's word: whoever holds it can have
--     paid VIP invoices raised (each with the S$72 and 3-in-1 vouchers)
--     without money, and can read the guest list. It lives only in the
--     website's server settings (never NEXT_PUBLIC_*); revoke it on the
--     Website tab at once if it may have leaked.
--   * The website itself must limit sign-ups per visitor (a bot check or a
--     per-address limit): the app's limit is per key.
--   * Round 7 (planning answers): answers are taken while the website is Off
--     or the event off sale (the owner's rule: until the event ends). A
--     website person who also bought VIP at the counter has two guest
--     records (as today); their answers are on the website one. An earlier
--     VIP record (refunded, then VIP bought again) does not show the
--     answers; the current one does. Times saved before the event's hours
--     change stay as saved (and pass a later save unchanged); the summary
--     lists them as saved. The allergy details and the question are free
--     text: whoever sees the guests sees them; the audit log records which
--     free-text answers changed, not their text (Owners, Admins and Managers
--     of any store can read the audit log, so it keeps only the choices:
--     food, allergy yes or no, times, talks, access ticks, how they heard);
--     anyone with a person's VIP link can read and change
--     that person's answers (as their first name and days today). Each
--     planning_answers answer (with the answers) is kept in
--     event_web_requests for 7 days, as every write's answer (service role
--     only). No retention rule for planning answers yet (the owner's open
--     point): they stay with the guest, in the audit log and in the
--     website's sheet; staff clear a guest's answers by saving every
--     question as Not answered (the texts go; the audit log keeps the
--     earlier choices, not the texts).
--   * Round 8 (two VIP payments for one customer): the warning before
--     linking is on the To match candidates the panel lists, and on a
--     customer picked with "Find another customer..." (the page reads them
--     from the guest list it already has: their rows, VIP paid or waiting;
--     the review of round 8, 21 Oct 2026); their guest rows (not the
--     cancelled ones) and the Planning tab flag it after. Nothing refunds either
--     payment by itself: staff refund one (Refund in full on its invoice,
--     or a waiting order closed on Website orders). Both of their guest
--     rows stay on the list, each flagged; the Guests tab's own counts are
--     as before (the planning summary counts them once).
--
-- DEPLOY ORDER (each step with the owner's go-ahead, once Wednesday's run
-- sheet has ended at 430: production fingerprint be589a20..., 1280 functions)
--
--   1. Dry run: a copy of production as it is then; apply this file twice.
--      The first run ends with the fingerprint below; the second says
--      "already this version; left alone" and changes nothing. A refusal
--      names the function that moved since 20 Oct (re-read, re-test).
--      437 (the affiliate sign-up, built beside this) is being rebuilt
--      while this is written (20 Oct 2026): this file's figures are 436
--      alone (21 Oct 2026). Before either is applied, apply both on a copy in
--      both orders and compare the fingerprints (an earlier 437 gave the
--      same fingerprint both ways).
--   2. Apply this file (the CLI, or the MCP's apply_migration with this
--      text verbatim). It checks itself (every AFTER md5, the grants, the
--      six triggers, its self-test). Then the nudge (pg_cron is installed
--      in production):
--        select jobname, schedule, command, active from cron.job
--         where jobname = 'event-website-sync-ping';
--      One row: */10 * * * *, select public.event_web_sync_ping(), active.
--      Missing (pg_cron added later): run
--        select cron.schedule('event-website-sync-ping', '*/10 * * * *',
--                             'select public.event_web_sync_ping()');
--      It posts nothing until the event has a sync URL and is not Off; after
--      step 7, cron.job_run_details for that job shows a run every 10
--      minutes and the Website tab's latest requests show the site's sync.
--   3. supabase functions deploy event-website --no-verify-jwt (the
--      contract with planning_answers: before the website uses it)
--   4. The Event page: push main (Vercel builds it).
--   5. The Owner turns the draft into this event: Events, "Two Day Health
--      Seminar (Nov)" (made 20 Oct, no guests or invoices), Edit:
--        name   Free Two Day Health Seminar by Rev 22 Global Energia
--        days   23 and 24 Nov 2026, as they are, no capacity
--        hours  start 09:00 (it says 10:00), end 19:00 (as it is)
--        stores Energia Van & RoadShow only (untick Energia Rev 22
--               (Adelphi))
--        tickets keep "2 Day" (2 days, S$72, on sale): the VIP ticket (VIP
--               invoices show its name; it may be renamed, its days and
--               price stay); remove "1 Day" (on no invoice, so it goes)
--        no early bird; Tickets on sale on. Save.
--   6. Vouchers page: SAVE72 ("$72 discount Voucher") gets a price at
--      Energia Van & RoadShow, S$72, available (it has one only at Adelphi;
--      3-in-1 is priced at both). Without it no VIP invoice can be made.
--   7. That event's Website tab (Owner): the event code (the website's
--      ENERGIA_EVENT_CODE), Record only, store Energia Van & RoadShow,
--      invoices raised by an active Owner, Admin or Manager of the van, VIP
--      ticket "2 Day", vouchers $72 discount Voucher and 3-in-1 Vouchers,
--      gifts Energia Gloves, Energia Socks - WHITE and Energia Socks - BLACK,
--      HitPay (online), PayNow, Bank Transfer, source "Event Name" with
--      "Free Two Day Health Seminar (website)", sync URL
--      https://healthtalk-rev22energia.vercel.app/api/app/sync. Save: the
--      readiness list has no errors left. The venue once it is known.
--   7a. Website tab, Talk titles (Owner, Admin or Manager): the speakers'
--      titles once known (until then the website offers the suggested list;
--      the readiness list says so).
--   8. (Round 7: deploy the website with the new contract, its md5 equal to
--      the edge function's, c1207868..., after step 3.)
--      Create key, Test: shown once; paste it into the website's server
--      settings (ENERGIA_EVENT_API_KEY), with the address and the code the
--      tab shows. Test with HitPay's sandbox; Clear test data.
--   9. Create key, Live; swap it in; HitPay production; mode Live; revoke
--      the test key.
--
-- SAFETY
--
--   ONE statement (a single DO block), so it is atomic whatever runs it, and
--   every check comes before anything is created:
--   * every function it relies on and does not change must be as read on
--     the stack after 430 (20 Oct 2026), below; pgcrypto (extensions) and
--     pg_net must be there; the columns it reads and writes must be as read.
--   * the nine tables must all be missing, or all exactly this shape; the
--     73 new functions missing, or already this version (left alone),
--     and no other function may take their names; each text built has the
--     tested md5 before it is installed; event_ticket_line_check and
--     invoice_action_plan must each be BEFORE (patched, each anchor found
--     once) or AFTER (left alone); its six triggers missing or exactly
--     these; 425's referral_signup_checks statuses as read.
--   * afterwards every function has its AFTER md5; anon may call none; the
--     20 page functions are signed-in staff's (each starts with
--     require_active_staff, then the event and store checks), the
--     53 others the service role's alone; the tables are no
--     client's; the two patched functions keep their grants.
--   * a self-test, in a block that is always undone (it ends by raising
--     P0436, so it leaves no row): a made-up Owner, store and event with
--     website settings and keys; a registration with an exact match and an
--     email held for staff, both on the guest list; a HitPay VIP payment
--     invoiced with its voucher on the person's account, the free record
--     parked; refunded in full (refund_invoice_recorded), the voucher is
--     taken back and the free record comes back (the triggers); a test
--     key's registration changes nothing; the affiliate through her own
--     link, under her name in other words on a phone and email not on file,
--     is held for staff with her record as the candidate and nobody's
--     referral (no customer made); someone else on her phone is held,
--     made a customer waits for the check with no referrer, and is her
--     referral once an Owner checks them as a different person; no answer
--     carries a capacity; a person's planning answers saved by their token,
--     following them to their VIP record and counted in the summary;
--     event_info says answers are open with no titles saved; a test key's
--     answers kept nowhere; the held person's candidate who paid VIP is
--     already a guest with that VIP payment (round 8). A second run
--     changes nothing.
--
-- BEFORE (the stack after 430, 20 Oct 2026; md5 of pg_get_functiondef with
-- search_path public):
--   changed
--   event_ticket_line_check(jsonb,date,uuid,integer)                 7f32dd2a6bf54bb147d6f8f728acb4f0
--   invoice_action_plan(uuid,text,jsonb)                             e117890fac11ea11435b691ca4787dec  (417's AFTER)
--   relied on, not changed
--   create_invoice_with_details(uuid,uuid,jsonb,jsonb)               0f408a1a350b68fd86cd24109c85c05b
--   record_invoice_payment(uuid,jsonb,uuid)                          c3da81f28d5a24a1c5f336527cfc33a4
--   create_customer_quick(text,text,text,text,date,text,text,text,text,uuid,uuid) 9ff9031d3b40029a19c729a512e99798
--   customer_names_match(text,text)                                  ef1af52e4888cefb6037a2291f4e011d
--   customer_name_words(text)                                        a7507abf0f15abd923dff59508b269c1
--   customer_email_match_key(text)                                   be468815c9626fff1728e2cfcd484b66
--   customer_phone_name_matches(text,text)                           1bdf8322972b6671b7cbb08bc8211f8a
--   require_resolved_customer_identity(text,text)                    5bde1a418363442ec27e2944442f5874
--   normalize_customer_phone(text)                                   b2bfac910e0c9eff402ba44e19750bee
--   normalize_customer_match_name(text)                              0572764712e179dc606c66f9f3dbaa03
--   inspect_customer_phone(text,text)                                6672c4d1963996f3b601896f4a55916e
--   set_customer_source(uuid,uuid,text,text)                         dbed868630d8ac8ed89a47838a918fa0
--   record_stock_use(text,uuid,uuid,integer,text,text)               db278faba262b0a3801944cd821a62fd
--   issue_sold_vouchers_for_invoice(uuid)                            0dbb4bc74411b6d4f0535f661a8c09ee
--   earn_invoice_commission(uuid)                                    6156b2e1ee51da5146a5a7acc16091ce
--   cancel_invoice_recorded(uuid,text,uuid)                          de52d9dbaef8ab15163bef35cb9d733d
--   reopen_invoice(uuid,text,uuid)                                   c9fcab7adfccdaeba1eb8dee4134ba47
--   event_sync_ticket_line(uuid,jsonb)                               3960c8a26f123b66c48bcca32c81244e
--   event_ticket_guests_follow_line(uuid)                            1fd8941bc9491741938c70e6dc327435
--   trg_event_guests_follow_invoice()                                013dd0eb837f1cb90b183877c914d55a
--   event_check_in(uuid,date,boolean,text,boolean)                   606cdbba5f8a6197fb1c5b216daf1e41
--   event_guest_list(uuid)                                           cbe2f3ef06fe97e59fc2e3b19fd35cac
--   event_can_run(uuid)                                              dac12d0086533bb528e847eb828809df
--   event_delete(uuid,text)                                          c1741487cf111d0a65faec47e5b2ae18
--   event_save_guest(jsonb)                                          f828b8558735696b392ae0f2e6c64a24
--   event_set_guest_cancelled(uuid,boolean,text)                     f58e462efb1f14e604ee62a7feec6b09
--   event_ticket_price(uuid,date)                                    f1bbea829863fbc743721dd82ed087ca
--   require_active_staff(text[])                                     877b3aa74cea559881979bb161c450e2
--   require_store_access(uuid)                                       f9332fd2f0092337d64501d8a647c23f
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   web_order_uuid(text)                                             2ab2b36e0b5db1f57a660efc00e33cae
--   is_owner()                                                       8eb059153c36a23f1d22b122543a7787
--   is_manager_or_above()                                            e87f6da4a7284374f0e2bc5b55c502be
--   is_owner_or_manager()                                            a98e50f1b6d3fa1e6c62cf52a8073cc8
--   user_has_store_access(uuid)                                      708992afaa6c3951f6329239b742987c
--   current_user_role()                                              519b0a33a3548f970c5d585b6e76a389
--   sg_today()                                                       1c1289f18e24d8370e9a6364c9c06fca
--   voucher_price_for(uuid,uuid,boolean)                             f19a5200cedce5cebf1544b98b3d72a9
--   public_affiliate_referral_info(text)                             17040ff07ab8e18fc9d8afe22afc9291
--   merge_customer_records(uuid,uuid,text,uuid)                      099ecf3aae30b5faaf8fb36bc15ce888
--   next_stock_use_no()                                              9387b31a3ee47b8df262b7ba1e473933
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)        e6f6c3cbf1bda3574d748bde2db5a759
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) 201f08ebf14a64cd88d411a7cfb4c9c4
--   request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)        4360d74462ed1fc950b6bd8b5157b3ae
--   invoice_charge_total(uuid)                                       8297147511ba285db2279598f3d727fb
--   event_ticket_line_refunded(uuid)                                 b9066789889c8225897ff979deefc8cc
--   invoice_discounted_line_value(uuid)                              ead4a430c3abd1e3f953912867ca4fe6
--   cancelled_invoice_used_value(uuid)                               70f684f1a8f0a4f42774394062e4df19
--   invoice_voucher_reopen_candidates(uuid)                          20405a96c8780eac6425a5dae59c29e1
--   apply_reopened_invoice_vouchers()                                71d50be41b73decceb0b20f8597dd4fa
--   adjust_invoice_line_commission_refunds(uuid,uuid[])              5959dec0fedd5fd45fb4615da413b20c
--   public function fingerprint (after 430)                          be589a20fca0f181f648e6e93c45cb4d (1280 functions)
-- AFTER (for later guards):
--   event_ticket_line_check(jsonb,date,uuid,integer)                 eb39ff10afedf8888e51b135d38ec616
--   invoice_action_plan(uuid,text,jsonb)                             4af305c7b91bcbd8c36db21130307e0f
--   event_web_open_state(uuid)                                       ef87a22efbb62f69759838db2dfc0d0c
--   event_web_person_vip_state(uuid)                                 fc0a3c9ce094fe72e69cff7f420837b6
--   event_web_person_view(uuid)                                      e4cf4ae412699afb1f3fa1011cbe0165
--   event_web_phone_holders(text)                                    614602e9cbc483d79bdef7d60aaf6a33
--   event_web_match_customer(text,text,text)                         16ec3e9f65d619b3f3feeef712bfd132
--   event_web_fill_customer(uuid,uuid)                               89488f15e0b030b9ed14c3c31049a71e
--   event_web_affiliate_contact(uuid)                                2e36126ac19182665357e2a934252db6
--   event_web_check_self_referral(uuid,uuid)                         7c13dd04c230ddedf201db59244bdaff
--   event_web_referral_note(uuid)                                    13a3b322968826b76f1b6b6065d5ebd9
--   event_web_apply_referral(uuid,uuid)                              b034075f9882cb4221e3a554e6453317
--   event_web_new_customer(uuid)                                     230f80aa30a13468cf5545398f393889
--   event_web_add_free_guest(uuid)                                   5bef6d09015c0d5fe33bbb470b885fc8
--   event_web_new_token()                                            00a860015a72b7514fef6ee342b49ed6
--   event_vip_paid_order_open(uuid)                                  f995ab9a0b358bb41a8a8acad1928d1f
--   event_web_readiness(uuid)                                        a6ce6fc9ce53de128b3ad0dc537c8d58
--   event_web_call(text,uuid,text,jsonb)                             e114ba39de4923cc52ed426e27d9bfde
--   event_web_info(uuid,jsonb)                                       ef82a257f56ea88d1ee445c4f364ffb9
--   event_web_referral_info(uuid,jsonb)                              c4b70aca816834e3754e361f8d080992
--   event_web_register(uuid,jsonb)                                   e3efd309e81d17c97f7984f7ecbaafff
--   event_web_person(uuid,jsonb)                                     d23601d1d971b665f7f158cd0100319f
--   event_web_order_answer(uuid)                                     8489cc479d277bdaa702dacba4b152c4
--   event_vip_person_problems(uuid)                                  dc4b811edcaaa4710a8a617e3f53b625
--   event_web_vip_checkout(uuid,jsonb)                               3b94aad78b7213e1af9261f326398153
--   event_vip_time_reason(uuid)                                      7141ca3fe6fc42194ca9eef5d8d8bd79
--   event_vip_dry_run(uuid)                                          85d165123d4a2149396308222a44c5bf
--   event_web_vip_paid(uuid,jsonb)                                   0628bdb6962349980eba6c74997c1a46
--   event_web_vip_transfer(uuid,jsonb)                               ec0aaa21b67316d71786e1f30456c183
--   event_web_vip_refund(uuid,jsonb)                                 642f02562f32ebdab432122a0855f14e
--   event_web_guest_key(text,uuid)                                   f178edf5e09a99d095d9e5a85b116133
--   event_web_sync(uuid,jsonb)                                       954db00575a61dd158c4457cfa235249
--   event_web_sync_ping()                                            3e053c83e3be814d359b85510459898b
--   event_vip_make_invoices(uuid,boolean)                            026c6f301e6040d9954757ba559839ba
--   event_vip_retry_after_match(uuid)                                06dafbb11f5b034dde31ef8fb9ffeedf
--   trg_event_vip_guest_follow()                                     23ebf956a5ab203637588a4b9982956c
--   trg_event_vip_parked_guest()                                     b1cc2d78ed6aac5e76ff08d9a78a0bba
--   trg_event_web_delete_guard()                                     8284956324394796fccf55d83d249035
--   event_vip_invoice_items(uuid)                                    c82b94c3d3e33cb099c192099a4129d2
--   event_vip_used_later(uuid)                                       ac92c734af54f02e3f55ebdf6489ff15
--   event_vip_take_back(uuid,jsonb,boolean)                          ec1d4d5dd2596160b12011cd6a73d14a
--   event_vip_refund_plan(uuid,text,jsonb)                           9a4d9bcce49afb1896b5d30299434acb
--   trg_event_vip_refund_vouchers()                                  f4ccb7ac32b395bda577169ad1e4f484
--   trg_event_web_referral_check_decided()                           9dea4cead38c8c990ad46f435d787520
--   trg_event_vip_used_later_reason()                                4bee8b817054a59fb18344aea69935ea
--   event_web_talk_titles(uuid)                                      db6fae95dabc4e0c695e78bbb1f3aa6b
--   event_planning_anchor(uuid)                                      86d3859360e9c2ab5f46b5752767f710
--   event_planning_days(uuid)                                        ad7c6aeb0b2fd05eec093019ef810bc7
--   event_planning_record(uuid,uuid)                                 0ac6c377d6af5a8eba08fa7e24f96703
--   event_planning_check(uuid,date[],jsonb,uuid)                     fb3f7029703f0d0bba3248bd41b6cd47
--   event_planning_write(uuid,uuid,uuid,jsonb,text,text)             d3df1e666a0ee83d30b3095379ca092e
--   event_web_planning_closed(uuid)                                  563219ee243568aebbbb7527f58e790b
--   event_web_planning_state(uuid)                                   67f23830517ff8753ac580e90d31225f
--   event_web_planning_answers(uuid,jsonb)                           104e2a5e640d882ff73762f56e2c4e38
--   event_vip_holders(uuid)                                          f8e1f118a88d311bbdbcd86d14a5046d
--   event_web_settings_get(uuid)                                     52321ea7c3856ac23d1547ee841c7bf0  (page)
--   event_web_settings_save(uuid,jsonb)                              5f8bd6ff8bb5b44099fbb35f555b6767  (page)
--   event_web_set_venue(uuid,text)                                   09657b3ac4774d22cfb9880fb1be0cb9  (page)
--   event_web_key_create(uuid,text,text)                             a6d0250df432f610d1e93f845f4a67e8  (page)
--   event_web_key_revoke(uuid,text)                                  80999f93d488af0101e1398f40514252  (page)
--   event_web_test_clear(uuid)                                       bf550db3b7b7075a71b5138d1dd47200  (page)
--   event_web_guest_extras(uuid)                                     0be416f652d2d6615818e434028f2437  (page)
--   event_registration_attach(uuid,uuid,text)                        c512d35fe6e1f58fbc8379c1a3a81972  (page)
--   event_registration_create_customer(uuid,text)                    23bc6941cd4b4db0fae101965292a324  (page)
--   event_registration_close(uuid,text)                              23baf63e59f00930214890759460a624  (page)
--   event_vip_orders_list(uuid)                                      f3b2511da3a5baba6e44d507270925a9  (page)
--   event_vip_order_invoice(uuid,integer)                            f0546047fa73876f3081003d10652dc7  (page)
--   event_vip_order_dismiss(uuid,text,boolean)                       c5dd53c43bc64fe3731db16f7be5f24f  (page)
--   event_vip_order_close_refunded(uuid,text,boolean)                e3c7156008dd05b2930f4781163fe286  (page)
--   event_vip_gift_give(uuid,uuid,date,uuid)                         6b8f9ed88f81a687bd82acd13e0275bc  (page)
--   event_vip_gift_undo(uuid,text)                                   c7356f0cba4cfddc7f91ba2db5860b99  (page)
--   event_planning_list(uuid)                                        592fd9cf5b9d6e8cb636d5aa5ec96676  (page)
--   event_planning_save(uuid,jsonb,integer,text)                     69e6b1b0eef3dfea899973545951757d  (page)
--   event_planning_summary(uuid)                                     dcdbde542fc6dd791ce9c01eb1f7096c  (page)
--   event_web_set_talks(uuid,jsonb)                                  5a4725dfef9621c569bb6fa35f3a6bb8  (page)
--   public function fingerprint (after 430 + 436)                    0e7e9dee71d0559fb447bab0f4ddec3d (1353 functions)
--
-- Test: scripts/event-website/tests/event-website.sql (begin ... rollback;
-- it installs this file itself, twice; round 7: sections PL and RQ; round
-- 8: section DV),
-- event-website-separate-tx.sql beside
-- it (one action per transaction, so what depends on time is run as it
-- happens; it commits, so only on a throwaway copy, with -v throwaway=1), and
-- the edge function's Deno tests.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The new functions, as pg_get_functiondef gives them back (search_path public) ──
  c_sigs constant text[] := array[
    'event_web_open_state(uuid)',
    'event_web_person_vip_state(uuid)',
    'event_web_person_view(uuid)',
    'event_web_phone_holders(text)',
    'event_web_match_customer(text,text,text)',
    'event_web_fill_customer(uuid,uuid)',
    'event_web_affiliate_contact(uuid)',
    'event_web_check_self_referral(uuid,uuid)',
    'event_web_referral_note(uuid)',
    'event_web_apply_referral(uuid,uuid)',
    'event_web_new_customer(uuid)',
    'event_web_add_free_guest(uuid)',
    'event_web_new_token()',
    'event_vip_paid_order_open(uuid)',
    'event_web_readiness(uuid)',
    'event_web_call(text,uuid,text,jsonb)',
    'event_web_info(uuid,jsonb)',
    'event_web_referral_info(uuid,jsonb)',
    'event_web_register(uuid,jsonb)',
    'event_web_person(uuid,jsonb)',
    'event_web_order_answer(uuid)',
    'event_vip_person_problems(uuid)',
    'event_web_vip_checkout(uuid,jsonb)',
    'event_vip_time_reason(uuid)',
    'event_vip_dry_run(uuid)',
    'event_web_vip_paid(uuid,jsonb)',
    'event_web_vip_transfer(uuid,jsonb)',
    'event_web_vip_refund(uuid,jsonb)',
    'event_web_guest_key(text,uuid)',
    'event_web_sync(uuid,jsonb)',
    'event_web_sync_ping()',
    'event_vip_make_invoices(uuid,boolean)',
    'event_vip_retry_after_match(uuid)',
    'trg_event_vip_guest_follow()',
    'trg_event_vip_parked_guest()',
    'trg_event_web_delete_guard()',
    'event_vip_invoice_items(uuid)',
    'event_vip_used_later(uuid)',
    'event_vip_take_back(uuid,jsonb,boolean)',
    'event_vip_refund_plan(uuid,text,jsonb)',
    'trg_event_vip_refund_vouchers()',
    'trg_event_web_referral_check_decided()',
    'trg_event_vip_used_later_reason()',
    'event_web_talk_titles(uuid)',
    'event_planning_anchor(uuid)',
    'event_planning_days(uuid)',
    'event_planning_record(uuid,uuid)',
    'event_planning_check(uuid,date[],jsonb,uuid)',
    'event_planning_write(uuid,uuid,uuid,jsonb,text,text)',
    'event_web_planning_closed(uuid)',
    'event_web_planning_state(uuid)',
    'event_web_planning_answers(uuid,jsonb)',
    'event_vip_holders(uuid)',
    'event_web_settings_get(uuid)',
    'event_web_settings_save(uuid,jsonb)',
    'event_web_set_venue(uuid,text)',
    'event_web_key_create(uuid,text,text)',
    'event_web_key_revoke(uuid,text)',
    'event_web_test_clear(uuid)',
    'event_web_guest_extras(uuid)',
    'event_registration_attach(uuid,uuid,text)',
    'event_registration_create_customer(uuid,text)',
    'event_registration_close(uuid,text)',
    'event_vip_orders_list(uuid)',
    'event_vip_order_invoice(uuid,integer)',
    'event_vip_order_dismiss(uuid,text,boolean)',
    'event_vip_order_close_refunded(uuid,text,boolean)',
    'event_vip_gift_give(uuid,uuid,date,uuid)',
    'event_vip_gift_undo(uuid,text)',
    'event_planning_list(uuid)',
    'event_planning_save(uuid,jsonb,integer,text)',
    'event_planning_summary(uuid)',
    'event_web_set_talks(uuid,jsonb)'];
  c_md5s constant text[] := array[
    'ef87a22efbb62f69759838db2dfc0d0c',
    'fc0a3c9ce094fe72e69cff7f420837b6',
    'e4cf4ae412699afb1f3fa1011cbe0165',
    '614602e9cbc483d79bdef7d60aaf6a33',
    '16ec3e9f65d619b3f3feeef712bfd132',
    '89488f15e0b030b9ed14c3c31049a71e',
    '2e36126ac19182665357e2a934252db6',
    '7c13dd04c230ddedf201db59244bdaff',
    '13a3b322968826b76f1b6b6065d5ebd9',
    'b034075f9882cb4221e3a554e6453317',
    '230f80aa30a13468cf5545398f393889',
    '5bef6d09015c0d5fe33bbb470b885fc8',
    '00a860015a72b7514fef6ee342b49ed6',
    'f995ab9a0b358bb41a8a8acad1928d1f',
    'a6ce6fc9ce53de128b3ad0dc537c8d58',
    'e114ba39de4923cc52ed426e27d9bfde',
    'ef82a257f56ea88d1ee445c4f364ffb9',
    'c4b70aca816834e3754e361f8d080992',
    'e3efd309e81d17c97f7984f7ecbaafff',
    'd23601d1d971b665f7f158cd0100319f',
    '8489cc479d277bdaa702dacba4b152c4',
    'dc4b811edcaaa4710a8a617e3f53b625',
    '3b94aad78b7213e1af9261f326398153',
    '7141ca3fe6fc42194ca9eef5d8d8bd79',
    '85d165123d4a2149396308222a44c5bf',
    '0628bdb6962349980eba6c74997c1a46',
    'ec0aaa21b67316d71786e1f30456c183',
    '642f02562f32ebdab432122a0855f14e',
    'f178edf5e09a99d095d9e5a85b116133',
    '954db00575a61dd158c4457cfa235249',
    '3e053c83e3be814d359b85510459898b',
    '026c6f301e6040d9954757ba559839ba',
    '06dafbb11f5b034dde31ef8fb9ffeedf',
    '23ebf956a5ab203637588a4b9982956c',
    'b1cc2d78ed6aac5e76ff08d9a78a0bba',
    '8284956324394796fccf55d83d249035',
    'c82b94c3d3e33cb099c192099a4129d2',
    'ac92c734af54f02e3f55ebdf6489ff15',
    'ec1d4d5dd2596160b12011cd6a73d14a',
    '9a4d9bcce49afb1896b5d30299434acb',
    'f4ccb7ac32b395bda577169ad1e4f484',
    '9dea4cead38c8c990ad46f435d787520',
    '4bee8b817054a59fb18344aea69935ea',
    'db6fae95dabc4e0c695e78bbb1f3aa6b',
    '86d3859360e9c2ab5f46b5752767f710',
    'ad7c6aeb0b2fd05eec093019ef810bc7',
    '0ac6c377d6af5a8eba08fa7e24f96703',
    'fb3f7029703f0d0bba3248bd41b6cd47',
    'd3df1e666a0ee83d30b3095379ca092e',
    '563219ee243568aebbbb7527f58e790b',
    '67f23830517ff8753ac580e90d31225f',
    '104e2a5e640d882ff73762f56e2c4e38',
    'f8e1f118a88d311bbdbcd86d14a5046d',
    '52321ea7c3856ac23d1547ee841c7bf0',
    '5f8bd6ff8bb5b44099fbb35f555b6767',
    '09657b3ac4774d22cfb9880fb1be0cb9',
    'a6d0250df432f610d1e93f845f4a67e8',
    '80999f93d488af0101e1398f40514252',
    'bf550db3b7b7075a71b5138d1dd47200',
    '0be416f652d2d6615818e434028f2437',
    'c512d35fe6e1f58fbc8379c1a3a81972',
    '23bc6941cd4b4db0fae101965292a324',
    '23baf63e59f00930214890759460a624',
    'f3b2511da3a5baba6e44d507270925a9',
    'f0546047fa73876f3081003d10652dc7',
    'c5dd53c43bc64fe3731db16f7be5f24f',
    'e3c7156008dd05b2930f4781163fe286',
    '6b8f9ed88f81a687bd82acd13e0275bc',
    'c7356f0cba4cfddc7f91ba2db5860b99',
    '592fd9cf5b9d6e8cb636d5aa5ec96676',
    '69e6b1b0eef3dfea899973545951757d',
    'dcdbde542fc6dd791ce9c01eb1f7096c',
    '5a4725dfef9621c569bb6fa35f3a6bb8'];
  -- true: a function of the Event page (signed-in staff; it checks the caller); false: the server's.
  c_client constant boolean[] := array[false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true];
  c_defs constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.event_web_open_state(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e public.events%rowtype; s public.event_web_settings%rowtype; o public.event_ticket_options%rowtype;
  v_now timestamp := now() at time zone 'Asia/Singapore';
  v_days jsonb; v_last date; v_count integer; v_open integer; v_reason text;
begin
  -- 436: judged in Singapore. A day can be chosen until its daily end (the
  -- whole day when the event has none); the event has ended once its last
  -- day has. "Tickets on sale" off closes registration and VIP alike; the
  -- VIP ticket's own On sale closes VIP alone; mode Off closes both.
  select * into e from public.events where id = p_event_id;
  select * into s from public.event_web_settings where event_id = p_event_id;
  if s.vip_option_id is not null then
    select * into o from public.event_ticket_options where id = s.vip_option_id and event_id = p_event_id;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'date', d.day, 'label', 'Day ' || d.n,
           'open', v_now < d.day + coalesce(e.daily_end, time '00:00')
                           + case when e.daily_end is null then interval '1 day' else interval '0' end)
           order by d.day), '[]'::jsonb),
         max(d.day), count(*)
    into v_days, v_last, v_count
    from (select dd.day, row_number() over (order by dd.day) as n
            from public.event_days dd where dd.event_id = p_event_id) d;
  select count(*) into v_open from jsonb_array_elements(v_days) x where (x->>'open')::boolean;
  v_reason := case
    when e.id is null or e.deleted_at is not null then 'event_deleted'
    when s.event_id is null or s.mode = 'off' then 'website_off'
    when not e.is_active then 'off_sale'
    when v_open = 0 then 'ended' end;
  return jsonb_build_object(
    'closed_reason', v_reason,
    'registration_open', v_reason is null,
    'days', (select coalesce(jsonb_agg(x || jsonb_build_object('open', (x->>'open')::boolean and v_reason is null)
                                       order by x->>'date'), '[]'::jsonb)
               from jsonb_array_elements(v_days) x),
    'last_day', v_last,
    'mode', coalesce(s.mode, 'off'),
    'vip_option_id', o.id,
    'vip_price_cents', case when o.id is null then 0
                            else round(public.event_ticket_price(o.id, public.sg_today()) * 100)::integer end,
    'vip_on_sale', v_reason is null and o.id is not null and o.is_active and o.days_count = v_count);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_person_vip_state(p_person_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436: paid while their VIP invoice is paid (not deleted); pending while a
  -- payment for them waits (a checkout not expired, an order a Manager has
  -- not dealt with, or their VIP invoice reopened and not paid again yet);
  -- refunded when their VIP invoice was cancelled or refunded and nothing
  -- else holds them. A test key's dry run counts as what a live key would
  -- have done.
  select case
    when exists (select 1 from public.event_vip_order_people op
                   join public.event_vip_orders o on o.id = op.order_ref
                   join public.invoices i on i.id = op.invoice_id
                  where op.person_id = p_person_id and o.status = 'invoiced'
                    and i.deleted_at is null and i.status::text in ('paid', 'completed_foc'))
      or exists (select 1 from public.event_vip_order_people op
                   join public.event_vip_orders o on o.id = op.order_ref
                  where op.person_id = p_person_id and o.status = 'test' and o.test_would = 'invoiced')
      then 'paid'
    when exists (select 1 from public.event_vip_order_people op
                   join public.event_vip_orders o on o.id = op.order_ref
                  where op.person_id = p_person_id
                    and ((o.status = 'pending' and o.expires_at > now())
                         or o.status in ('recorded', 'needs_review')
                         or (o.status = 'test' and o.test_would in ('recorded', 'needs_review'))))
      -- A VIP invoice reopened (or part paid) and not paid in full again.
      or exists (select 1 from public.event_vip_order_people op
                   join public.event_vip_orders o on o.id = op.order_ref
                   join public.invoices i on i.id = op.invoice_id
                  where op.person_id = p_person_id and o.status = 'invoiced'
                    and i.deleted_at is null and i.status::text not in ('paid', 'completed_foc', 'cancelled', 'refunded'))
      then 'pending'
    when exists (select 1 from public.event_vip_order_people op
                   join public.event_vip_orders o on o.id = op.order_ref
                  where op.person_id = p_person_id and o.status = 'invoiced')
      then 'refunded'
    else 'none' end
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_person_view(p_person_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; fg public.event_guests%rowtype; vg public.event_guests%rowtype;
  v_state text; v_open jsonb; v_reason text; v_days jsonb;
begin
  select * into p from public.event_registration_people where id = p_person_id;
  if not found then return null; end if;
  select * into fg from public.event_guests where id = p.free_guest_id;
  select * into vg from public.event_guests where id = p.vip_guest_id;
  v_state := public.event_web_person_vip_state(p.id);
  v_open := public.event_web_open_state(p.event_id);
  -- The days they are coming: their VIP record's while it stands, else their
  -- free one's, else what they chose (a test registration has no record; a
  -- test person the dry run made VIP comes every day, as a live VIP record
  -- does: the review of round 7, 21 Oct 2026).
  v_days := coalesce(
    case when p.is_test and v_state = 'paid' then
      (select jsonb_agg(d.day order by d.day) from public.event_days d where d.event_id = p.event_id) end,
    (select jsonb_agg(gd.day order by gd.day) from public.event_guest_days gd
      where gd.guest_id = case when vg.status = 'registered' then vg.id else fg.id end),
    (select jsonb_agg(d order by d) from unnest(p.days) d));
  v_reason := case
    when v_state = 'paid' then 'already_vip'
    when v_state = 'pending' then 'payment_waiting'
    when p.match = 'closed'
         or (fg.id is not null and fg.status = 'cancelled' and coalesce(fg.cancelled_reason, '') not like 'Upgraded to VIP%'
             and coalesce(vg.status, 'cancelled') <> 'registered') then 'cancelled'
    when v_open->>'closed_reason' in ('website_off', 'event_deleted', 'ended') then 'closed'
    when not coalesce((v_open->>'vip_on_sale')::boolean, false) then 'vip_off_sale' end;
  return jsonb_build_object('person_id', p.id, 'upgrade_token', p.upgrade_token, 'first_name', p.first_name,
    'days', coalesce(v_days, '[]'::jsonb), 'vip', v_state, 'can_upgrade', v_reason is null, 'reason', v_reason);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_phone_holders(p_phone_norm text)
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436: as 425's affiliate sign-up reads them. An old number can be read as
  -- this one only when its digits (less any leading 0) end this number's
  -- digits, so only those few are inspected: inspecting all ~8,000 old
  -- numbers took over a second per person, and a form may hold ten.
  select coalesce(array_agg(x.id order by x.created_at, x.id), '{}'::uuid[])
    from (select c.id, c.created_at from public.customers c
           where c.deleted_at is null and public.normalize_customer_phone(c.phone) = p_phone_norm
          union
          select o.id, o.created_at
            from (select c.id, c.created_at, c.phone, ltrim(regexp_replace(c.phone, '\D', '', 'g'), '0') as d
                    from public.customers c
                   where c.deleted_at is null and c.phone ~ '^[\s().0-9-]+$') o
           where length(o.d) >= 6
             and right(regexp_replace(p_phone_norm, '\D', '', 'g'), length(o.d)) = o.d
             and public.normalize_customer_phone(o.phone) is null
             and (public.inspect_customer_phone(o.phone)->'candidates') ? p_phone_norm) x
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_match_customer(p_phone_norm text, p_name text, p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_matches uuid[]; v_kind text; v_holders uuid[]; v_email_key text; v_email_holders uuid[]; v_legacy uuid[];
begin
  begin
    perform public.require_resolved_customer_identity(p_phone_norm, p_name);
  exception when raise_exception then
    if sqlerrm <> 'AMBIGUOUS_CUSTOMER_MATCH' then raise; end if;
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_legacy
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) is null
       and public.normalize_customer_match_name(c.full_name) = public.normalize_customer_match_name(p_name)
       and (public.inspect_customer_phone(c.phone)->'candidates') ? p_phone_norm;
    return jsonb_build_object('kind', 'held', 'hold_reason', 'legacy_ambiguous', 'candidates', to_jsonb(v_legacy));
  end;
  v_matches := public.customer_phone_name_matches(p_phone_norm, p_name);
  v_holders := public.event_web_phone_holders(p_phone_norm);
  if cardinality(v_matches) > 0 then
    v_kind := 'exact';
  else
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_matches
      from public.customers c
     where c.id = any (v_holders) and public.customer_names_match(c.full_name, p_name);
    v_kind := 'same_words';
  end if;
  if cardinality(v_matches) = 1 then
    return jsonb_build_object('kind', v_kind, 'customer_id', v_matches[1]);
  end if;
  if cardinality(v_matches) > 1 then
    return jsonb_build_object('kind', 'held', 'hold_reason', 'several_name_matches', 'candidates', to_jsonb(v_matches));
  end if;
  v_email_key := public.customer_email_match_key(p_email);
  select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_email_holders
    from public.customers c
   where v_email_key is not null and c.deleted_at is null and public.customer_email_match_key(c.email) = v_email_key;
  if cardinality(v_holders) > 0 or cardinality(v_email_holders) > 0 then
    return jsonb_build_object('kind', 'held',
      'hold_reason', case when cardinality(v_holders) > 0 and cardinality(v_email_holders) > 0 then 'phone_and_email_in_use'
                          when cardinality(v_holders) > 0 then 'phone_in_use' else 'email_in_use' end,
      'candidates', (select coalesce(jsonb_agg(distinct x), '[]'::jsonb) from unnest(v_holders || v_email_holders) x));
  end if;
  return jsonb_build_object('kind', 'new');
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_fill_customer(p_customer_id uuid, p_person_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; s public.event_web_settings%rowtype;
  v_src public.customer_source_options%rowtype;
begin
  select * into p from public.event_registration_people where id = p_person_id;
  select * into s from public.event_web_settings where event_id = p.event_id;
  select * into v_src from public.customer_source_options where id = s.source_option_id and is_active;
  update public.customers
     set email             = coalesce(nullif(btrim(email), ''), nullif(btrim(p.email), '')),
         source_option_id  = coalesce(source_option_id, v_src.id),
         source_label      = case when source_option_id is null and v_src.id is not null then v_src.label else source_label end,
         source_details    = case when source_option_id is null and v_src.id is not null then s.source_details else source_details end,
         source_updated_at = case when source_option_id is null and v_src.id is not null then now() else source_updated_at end,
         updated_at        = now()
   where id = p_customer_id
     and ((nullif(btrim(email), '') is null and nullif(btrim(p.email), '') is not null)
          or (source_option_id is null and v_src.id is not null));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_affiliate_contact(p_person_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436: which of the referring affiliate's own phone (as 425 reads a phone,
  -- an old 8-digit number included) and email inbox (432's
  -- customer_email_match_key) the person typed, through a valid link; null
  -- when neither. Alone they do not make the person the affiliate (the
  -- owner, 20 Oct 2026, ~20:15): someone else on them becomes her referral
  -- only once an Owner or Manager checks them (event_web_new_customer).
  select nullif(array_remove(array[
           case when public.normalize_customer_phone(a.phone) = p.phone_norm
                  or (public.normalize_customer_phone(a.phone) is null and a.phone ~ '^[\s().0-9-]+$'
                      and (public.inspect_customer_phone(a.phone)->'candidates') ? p.phone_norm) then 'phone' end,
           case when public.customer_email_match_key(a.email) = public.customer_email_match_key(p.email) then 'email' end],
           null), '{}'::text[])
    from public.event_registration_people p
    join public.event_registrations r on r.id = p.registration_ref
    join public.customers a on a.id = r.referrer_customer_id
   where p.id = p_person_id and r.referral_state = 'valid'
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_check_self_referral(p_person_id uuid, p_customer_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; r public.event_registrations%rowtype; a public.customers%rowtype;
  v_by text[] := '{}';
begin
  select * into p from public.event_registration_people where id = p_person_id;
  select * into r from public.event_registrations where id = p.registration_ref;
  select * into a from public.customers where id = r.referrer_customer_id;
  if a.id is not null and (p_customer_id is null or p_customer_id = a.id) then
    if p_customer_id = a.id then v_by := v_by || 'customer'::text; end if;
    if nullif(public.normalize_customer_match_name(a.full_name), '') = public.normalize_customer_match_name(p.full_name)
       or public.customer_names_match(a.full_name, p.full_name) then v_by := v_by || 'name'::text; end if;
    -- The owner, 20 Oct 2026, ~20:15: her phone or email inbox alone does not
    -- make a person her (someone else on them is her referral once checked);
    -- with her record or her name they only say how else she was recognised.
    if cardinality(v_by) > 0 then
      v_by := v_by || coalesce(public.event_web_affiliate_contact(p.id), '{}'::text[]);
    end if;
  end if;
  if cardinality(v_by) = 0 then v_by := null; end if;
  if p.referral_self_by is distinct from v_by then
    update public.event_registration_people set referral_self_by = v_by, updated_at = now() where id = p.id;
    if p.referral_self_by is null and not p.is_test then
      perform public.write_audit_ex('event_registration_people', p.id, 'event_registration_self_referral', null,
        jsonb_build_object('registration_id', r.registration_id, 'referral_code', r.referral_code,
                           'referrer_customer_id', r.referrer_customer_id, 'self_by', to_jsonb(v_by), 'customer_id', p_customer_id),
        'affiliate', public.event_web_referral_note(p.id),
        (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
    end if;
  end if;
  return v_by is not null;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_referral_note(p_person_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436: the plain note staff see about a person's referral through a link
  -- (Guests, To match, the export, the Website tab's test registrations, the
  -- self-referral audit row), or none: the affiliate herself; an existing
  -- customer, not referred again (the owner, 20 Oct 2026, ~20:15); someone
  -- else on her phone or email inbox, held (a test key's too), waiting for
  -- the check, merged into another record before it (or an older record
  -- merged into theirs: an existing customer), checked (and why not
  -- referred, when not). The owner, 21 Oct 2026: her own row says "She
  -- earns no commission from it" (her own referrer still earns on her VIP);
  -- held under her name (a phone and email not on her record), what linking
  -- her record or making a new customer does; made a new customer, someone
  -- else with her name, not referred through the link; someone on another
  -- customer's phone waits for the check too (Q19), and someone held for
  -- another customer's email inbox (R6-1). Her link switched off: the same
  -- notes, the link named as switched off.
  select case
    when 'customer' = any (p.referral_self_by) then
      format('Not referred: this is %s, the affiliate whose link (%s) was used. She earns no commission from it.',
             coalesce(a.full_name, 'the affiliate'), y.link)
    when p.referral_self_by is not null and p.customer_id is not null then
      format('Not referred: the same %s as %s, the affiliate whose link (%s) was used, but staff made them a separate '
             || 'customer (someone else), so no referral or commission comes from this link.',
             y.self_how, coalesce(a.full_name, 'the affiliate'), y.link)
    when p.referral_self_by is not null then
      format('Not referred: the same %s as %s, the affiliate whose link (%s) was used. If this is %s, link her record: '
             || 'she earns no commission from it. If it is someone else, make a new customer: they are not referred '
             || 'through this link either.',
             y.self_how, coalesce(a.full_name, 'the affiliate'), y.link, coalesce(a.full_name, 'the affiliate'))
    when r.referral_state <> 'valid' then null
    when coalesce(p.referral_outcome, p.test_outcome->>'referral') = 'already_customer' then
      case when p.customer_id is null then
             format('Already a customer, so not referred again through this link (%s); any referral they already have still stands.',
                    r.referral_code)
           when c.referred_by is not null then
             format('Already a customer, so not referred again through this link (%s); their existing referral (by %s) still stands.',
                    r.referral_code, coalesce(cr.full_name, 'another customer'))
           else
             format('Already a customer, so not referred again through this link (%s); they had no referral before, and none is added.',
                    r.referral_code) end
    when x.how is not null and ((p.match = 'held' and p.referral_outcome = 'held')
                                or (p.is_test and p.test_outcome->>'referral' = 'held')) then
      format('Shares the %s of %s, the affiliate whose link (%s) was used. If this is %s, link that record: not referred. '
             || 'If it is someone else, make a new customer: they become %s''s referral once an Owner or Manager checks them '
             || 'as a different person (Affiliates page), and no commission comes before that.',
             x.how, coalesce(a.full_name, 'the affiliate'), r.referral_code, coalesce(a.full_name, 'the affiliate'),
             coalesce(a.full_name, 'the affiliate'))
    when x.how is null and ((p.match = 'held' and p.referral_outcome = 'held')
                            or (p.is_test and p.test_outcome->>'referral' = 'held'))
         and coalesce(p.hold_reason, p.test_outcome->>'hold_reason')
             in ('phone_in_use', 'phone_and_email_in_use', 'several_name_matches', 'legacy_ambiguous') then
      format('Their phone is on another customer''s record. If this is that customer, link their record: an existing customer '
             || 'is not referred through this link (%s). If it is someone else, make a new customer: they become %s''s referral '
             || 'once an Owner or Manager checks them as a different person (Affiliates page), and no commission comes before that.',
             r.referral_code, coalesce(a.full_name, 'the affiliate'))
    when x.how is null and ((p.match = 'held' and p.referral_outcome = 'held')
                            or (p.is_test and p.test_outcome->>'referral' = 'held'))
         and coalesce(p.hold_reason, p.test_outcome->>'hold_reason') = 'email_in_use' then
      format('Their email inbox is on another customer''s record. If this is that customer, link their record: an existing '
             || 'customer is not referred through this link (%s). If it is someone else, make a new customer: they become %s''s '
             || 'referral once an Owner or Manager checks them as a different person (Affiliates page), and no commission comes '
             || 'before that.', r.referral_code, coalesce(a.full_name, 'the affiliate'))
    when p.referral_outcome = 'check_waiting'
         and not exists (select 1 from public.referral_signup_checks k where k.customer_id = p.customer_id and k.status = 'pending') then
      format('Not referred through this link (%s): the customer made for them was merged into another record before the check; '
             || 'any referral that record has still stands.', r.referral_code)
    when p.referral_outcome = 'check_confirmed' and c.referred_by = r.referrer_customer_id then
      format('Referred by %s (link %s) once an Owner or Manager checked them as a different person; commission on their VIP comes from then.',
             coalesce(a.full_name, 'the affiliate'), r.referral_code)
    when p.referral_outcome in ('check_waiting', 'check_confirmed')
         and exists (select 1 from public.audit_logs l
                       join public.customers m on m.id = case when l.new_data->>'merged_from' ~ '^[0-9a-f-]{36}$'
                                                              then (l.new_data->>'merged_from')::uuid end
                      where l.record_id = p.customer_id and l.action = 'customers_merged' and m.created_at < c.created_at
                        and (p.referral_outcome = 'check_waiting'
                             or l.created_at <= (select k.decided_at from public.referral_signup_checks k
                                                  where k.customer_id = p.customer_id and k.status <> 'pending'))) then
      format('Not referred through this link (%s): an older customer record was merged into the one made for them before the check, '
             || 'so they are an existing customer; any referral that older record had is the Owner''s to carry over.', r.referral_code)
    when p.referral_outcome = 'check_waiting' and x.how is null then
      format('Waiting for a check: %s on another customer''s record. They become %s''s referral (link %s) '
             || 'once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
             case when p.hold_reason = 'email_in_use' then 'their email inbox is' else 'their phone is' end,
             coalesce(a.full_name, 'the affiliate'), r.referral_code)
    when p.referral_outcome = 'check_waiting' then
      format('Waiting for a check: shares the %s of %s, the affiliate whose link (%s) was used. They become %s''s referral '
             || 'once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
             x.how, coalesce(a.full_name, 'the affiliate'), r.referral_code,
             coalesce(a.full_name, 'the affiliate'))
    when p.referral_outcome = 'check_confirmed' then
      format('Checked as a different person, but not referred by %s (link %s): %s.',
             coalesce(a.full_name, 'the affiliate'), r.referral_code,
             case when c.id is null or c.deleted_at is not null then 'their customer record is no longer there'
                  when a.id is null or a.deleted_at is not null then 'the affiliate''s customer record is no longer there'
                  when c.referred_by is not null then format('their customer record has another referrer (%s)', coalesce(cr.full_name, 'another customer'))
                  else 'the referral could not be made (their record had another referrer then, or it would make a loop in the referral chain)' end)
    when p.referral_outcome = 'check_same_person' then
      format('Not referred: an Owner or Manager checked them as the same person as a customer who already had this phone or email (link %s). No commission comes from it.',
             r.referral_code) end
    from public.event_registration_people p
    join public.event_registrations r on r.id = p.registration_ref
    left join public.customers a on a.id = r.referrer_customer_id
    left join public.customers c on c.id = p.customer_id
    left join public.customers cr on cr.id = c.referred_by
    cross join lateral (
      select nullif(regexp_replace(array_to_string(array(select case b when 'email' then 'email inbox' else b end
                                                           from unnest(public.event_web_affiliate_contact(p.id)) with ordinality u(b, n)
                                                          order by n), ', '),
                                   ', ([^,]*)$', ' and \1'), '') as how) x
    cross join lateral (
      select regexp_replace(array_to_string(array(select case b when 'email' then 'email inbox' else b end
                                                    from unnest(p.referral_self_by) with ordinality u(b, n) order by n), ', '),
                            ', ([^,]*)$', ' and \1') as self_how,
             r.referral_code || case when r.referral_state = 'link_off' then ', switched off' else '' end as link) y
   where p.id = p_person_id
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_apply_referral(p_person_id uuid, p_customer_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; r public.event_registrations%rowtype;
begin
  select * into p from public.event_registration_people where id = p_person_id;
  select * into r from public.event_registrations where id = p.registration_ref;
  if r.referral_state = 'none' then return null; end if;
  if r.referral_state <> 'valid' then
    -- Held under the affiliate's name through her link switched off (the
    -- review of 21 Oct 2026): linked to her record she is herself ('self', as
    -- on a live link: the owner, 21 Oct 2026, R6-6), linked to anyone else the
    -- mark goes (the note says which); not referred either way. Matched on
    -- her own record straight away (her phone and details) she is herself too
    -- (the review of round 7, 21 Oct 2026).
    if r.referral_state = 'link_off'
       and (p.referral_self_by is not null or p_customer_id = r.referrer_customer_id) then
      if public.event_web_check_self_referral(p.id, p_customer_id) then return 'self'; end if;
    end if;
    return r.referral_state;
  end if;
  if public.event_web_check_self_referral(p.id, p_customer_id) then return 'self'; end if;
  -- An existing customer who is not the affiliate (the owner, 20 Oct 2026,
  -- ~20:15): not referred again, and any referral they already have stands
  -- (392's duplicate event); staff see a plain note (event_web_referral_note).
  insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
  values (r.referral_code, r.referrer_customer_id, p.phone_norm, 'duplicate');
  return 'already_customer';
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_new_customer(p_person_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; r public.event_registrations%rowtype;
  s public.event_web_settings%rowtype; v_ref uuid; v_outcome text; v_holders uuid[]; v_cust uuid;
  v_wait boolean := false; v_shares uuid[]; v_mail_holders uuid[] := '{}';
begin
  select * into p from public.event_registration_people where id = p_person_id;
  select * into r from public.event_registrations where id = p.registration_ref;
  select * into s from public.event_web_settings where event_id = p.event_id;
  v_holders := public.event_web_phone_holders(p.phone_norm);
  -- Held for their email inbox (433's hold), whoever has it now, read before their own record
  -- is made (432's key, as event_web_match_customer reads it; the owner, 21 Oct 2026, R6-1).
  if p.hold_reason in ('email_in_use', 'phone_and_email_in_use') and public.customer_email_match_key(p.email) is not null then
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_mail_holders
      from public.customers c
     where c.deleted_at is null and public.customer_email_match_key(c.email) = public.customer_email_match_key(p.email);
  end if;
  if r.referral_state = 'valid' and public.event_web_check_self_referral(p.id, null) then
    -- Her name in the same words: no referral, no check, no commission. Made
    -- a customer by staff from To match, they are someone else with her name
    -- (the owner, 21 Oct 2026): not referred through this link either.
    v_outcome := 'self';
  elsif r.referral_state = 'valid' then
    if exists (select 1 from public.customer_affiliates ca
                where ca.customer_id = r.referrer_customer_id and ca.deleted_at is null
                  and ca.status = 'active' and not ca.manually_suspended) then
      perform pg_advisory_xact_lock(hashtextextended('referral-link:' || r.referrer_customer_id::text, 0));
      if (select count(*) from public.referral_signup_events e
           where e.referrer_customer_id = r.referrer_customer_id and e.outcome in ('created', 'phone_shared')
             and e.created_at > now() - interval '1 hour') >= 20 then
        insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
        values (r.referral_code, r.referrer_customer_id, p.phone_norm, 'link_limit');
        v_outcome := 'link_limit';
      else
        v_ref := r.referrer_customer_id;
        -- Someone else on the affiliate's own phone or email inbox (the owner,
        -- 20 Oct 2026, ~20:15), or on another customer's phone (Q19 = A; the
        -- owner, 21 Oct 2026) or held for another customer's email inbox (the
        -- owner, 21 Oct 2026, R6-1): her referral only once an Owner or
        -- Manager checks them as a different person, and no commission before
        -- that (trg_event_web_referral_check_decided).
        v_wait := public.event_web_affiliate_contact(p.id) is not null or cardinality(v_holders) > 0
                  or cardinality(v_mail_holders) > 0;
      end if;
    else
      v_outcome := 'link_off';
    end if;
  elsif r.referral_state in ('link_off', 'unknown_code') then
    v_outcome := r.referral_state;
  end if;
  v_cust := (public.create_customer_quick(p.first_name, p.last_name, p.phone_norm, p.email, null, null, null, null, null,
               case when v_wait then null else v_ref end,
               public.web_order_uuid('event-reg-customer:' || p.id::text))->>'customer_id')::uuid;
  if v_ref is not null and v_wait then
    -- No referrer yet: the check (425's list on the Affiliates page) names the
    -- affiliate as the referrer, and those they share a phone or email inbox
    -- with (the affiliate too when it is her phone or email inbox).
    v_shares := v_holders || array(select m from unnest(v_mail_holders) m where not (m = any (v_holders)))
                || case when v_ref = any (v_holders || v_mail_holders) or public.event_web_affiliate_contact(p.id) is null
                        then '{}'::uuid[] else array[v_ref] end;
    insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, normalized_phone, outcome)
    values (r.referral_code, v_ref, v_cust, p.phone_norm, 'phone_shared');
    insert into public.referral_signup_checks(customer_id, referrer_customer_id, referral_code, normalized_phone, phone_shared_with)
    values (v_cust, v_ref, r.referral_code, p.phone_norm, v_shares);
    perform public.write_audit_ex('customers', v_cust, 'referral_check_waiting', null,
      jsonb_build_object('referrer_customer_id', v_ref, 'referral_code', r.referral_code, 'source', 'event_website',
                         'registration_id', r.registration_id, 'shares', to_jsonb(public.event_web_affiliate_contact(p.id)),
                         'phone_shared_with', to_jsonb(v_shares)),
      'affiliate', case when public.event_web_affiliate_contact(p.id) is not null
                        then 'Shares the affiliate''s own phone or email: referred once an Owner or Manager checks them as a different person'
                        when cardinality(v_holders) > 0
                        then 'Their phone is on another customer''s record: referred once an Owner or Manager checks them as a different person'
                        else 'Their email inbox is on another customer''s record: referred once an Owner or Manager checks them as a different person' end,
      null);
    v_outcome := 'check_waiting';
  elsif v_ref is not null then
    -- Nobody has their phone (Q19's check is above): referred at once.
    update public.customers set referral_source = 'affiliate_link', referral_code_used = r.referral_code
     where id = v_cust;
    insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, normalized_phone, outcome)
    values (r.referral_code, v_ref, v_cust, p.phone_norm, 'created');
    perform public.write_audit_ex('customers', v_cust, 'referral_registered', null,
      jsonb_build_object('referred_by', v_ref, 'referral_code', r.referral_code, 'source', 'event_website',
                         'registration_id', r.registration_id),
      'affiliate', null, null);
    v_outcome := 'created';
  end if;
  if s.source_option_id is not null
     and exists (select 1 from public.customer_source_options o where o.id = s.source_option_id and o.is_active) then
    perform public.set_customer_source(v_cust, s.source_option_id, s.source_details, null);
  end if;
  return jsonb_build_object('customer_id', v_cust, 'referral_outcome', v_outcome);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_add_free_guest(p_person_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; r public.event_registrations%rowtype; v_id uuid;
begin
  select * into p from public.event_registration_people where id = p_person_id;
  select * into r from public.event_registrations where id = p.registration_ref;
  insert into public.event_guests (event_id, name, phone, customer_id, source, registered_by, notes, created_by, updated_by)
  values (p.event_id, p.full_name, p.phone_norm, p.customer_id, 'free', null,
          'Website · ' || r.registration_id || ' · ' || p.position || ' of ' || r.people_count, auth.uid(), auth.uid())
  returning id into v_id;
  insert into public.event_guest_days (guest_id, day) select v_id, d from unnest(p.days) d;
  update public.event_registration_people set free_guest_id = v_id, updated_at = now() where id = p.id;
  perform public.write_audit_ex('event_guests', v_id, 'event_guest_added', null,
    jsonb_build_object('event_id', p.event_id, 'days', to_jsonb(p.days), 'source', 'website',
                       'registration_id', r.registration_id), 'events', null, null);
  return v_id;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_new_token()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select 'vip_' || string_agg(substr('abcdefghijklmnopqrstuvwxyz234567', (get_byte(x.b, i) % 32) + 1, 1), '' order by i)
    from (select extensions.gen_random_bytes(26) as b) x, generate_series(0, 25) i
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_paid_order_open(p_event_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.event_vip_orders o
                  where o.id::text = coalesce(current_setting('energia.paid_vip_order', true), '')
                    and o.event_id = p_event_id and o.status in ('pending', 'recorded', 'needs_review'))
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_readiness(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.event_web_settings%rowtype; e public.events%rowtype; o public.event_ticket_options%rowtype;
  v_blocking jsonb := '[]'; v_errors jsonb := '[]'; v_warnings jsonb := '[]'; v_days integer; x uuid; v_name text;
  v_pj jsonb;
begin
  select * into e from public.events where id = p_event_id;
  select * into s from public.event_web_settings where event_id = p_event_id;
  if s.event_id is null then
    return jsonb_build_object('blocking', '[]'::jsonb, 'errors', jsonb_build_array('The website settings are not saved yet.'),
                              'warnings', '[]'::jsonb);
  end if;
  select count(*) into v_days from public.event_days where event_id = p_event_id;
  if not exists (select 1 from public.event_stores es where es.event_id = p_event_id and es.store_id = s.store_id) then
    v_blocking := v_blocking || to_jsonb('The store is not one of the event''s stores.'::text); end if;
  if not exists (select 1 from public.profiles pr
                  where pr.id = s.acting_profile_id and pr.is_active and pr.deleted_at is null
                    and coalesce(pr.invitation_status, 'accepted') = 'accepted'
                    and pr.role in ('owner', 'admin', 'manager')
                    and (pr.role in ('owner', 'admin')
                         or exists (select 1 from public.user_store_assignments usa
                                     where usa.user_id = pr.id and usa.store_id = s.store_id))) then
    v_errors := v_errors || to_jsonb('The person who raises the invoices must be an active Owner, Admin or Manager of the store.'::text); end if;
  if s.vip_option_id is null then
    v_errors := v_errors || to_jsonb('Choose the VIP ticket.'::text);
  else
    select * into o from public.event_ticket_options where id = s.vip_option_id;
    if o.id is null or o.event_id <> p_event_id then
      v_blocking := v_blocking || to_jsonb('The VIP ticket is not a ticket of this event.'::text);
    else
      if o.days_count <> v_days then
        v_errors := v_errors || to_jsonb(format('The VIP ticket covers %s day(s), but the event has %s: VIP covers every day.', o.days_count, v_days)); end if;
      if o.price <= 0 then v_errors := v_errors || to_jsonb('The VIP ticket has no price.'::text); end if;
      if not o.is_active then v_warnings := v_warnings || to_jsonb('The VIP ticket is off sale: the website does not sell VIP.'::text); end if;
    end if;
  end if;
  if cardinality(s.vip_voucher_ids) = 0 then
    v_warnings := v_warnings || to_jsonb('No vouchers come with VIP.'::text); end if;
  foreach x in array s.vip_voucher_ids loop
    select v.name into v_name from public.vouchers v where v.id = x and v.is_active and v.deleted_at is null;
    if v_name is null then
      v_blocking := v_blocking || to_jsonb('A VIP voucher is not an active voucher.'::text);
    else
      v_pj := public.voucher_price_for(s.store_id, x, true);
      if not coalesce((v_pj->>'has_price')::boolean, false) then
        v_errors := v_errors || to_jsonb(format('"%s" has no price at the store: give it one on the Vouchers page (it is free on the VIP invoice, but needs a price there).', v_name)); end if;
    end if;
  end loop;
  foreach x in array s.gift_product_ids loop
    select pr.name into v_name from public.products pr where pr.id = x and pr.is_active and pr.deleted_at is null;
    if v_name is null then
      v_blocking := v_blocking || to_jsonb('A gift is not an active product.'::text);
    elsif coalesce((select si.current_qty from public.store_inventory si where si.store_id = s.store_id and si.product_id = x), 0) <= 0 then
      v_warnings := v_warnings || to_jsonb(format('"%s" has no stock at the store.', v_name));
    end if;
  end loop;
  if cardinality(s.gift_product_ids) = 0 then
    v_warnings := v_warnings || to_jsonb('No gifts (socks or gloves) are chosen for VIPs.'::text); end if;
  if s.hitpay_payment_method_id is null
     or not exists (select 1 from public.payment_methods pm where pm.id = s.hitpay_payment_method_id and pm.is_active and pm.deleted_at is null) then
    v_errors := v_errors || to_jsonb('Choose an active payment method for HitPay payments.'::text); end if;
  if s.paynow_payment_method_id is not null
     and not exists (select 1 from public.payment_methods pm where pm.id = s.paynow_payment_method_id and pm.is_active and pm.deleted_at is null) then
    v_errors := v_errors || to_jsonb('The PayNow payment method is not active.'::text); end if;
  if s.bank_payment_method_id is not null
     and not exists (select 1 from public.payment_methods pm where pm.id = s.bank_payment_method_id and pm.is_active and pm.deleted_at is null) then
    v_errors := v_errors || to_jsonb('The bank transfer payment method is not active.'::text); end if;
  if s.paynow_payment_method_id is null then
    v_warnings := v_warnings || to_jsonb('No PayNow method: PayNow VIP orders cannot be invoiced until one is chosen.'::text); end if;
  if s.bank_payment_method_id is null then
    v_warnings := v_warnings || to_jsonb('No bank transfer method: bank transfer VIP orders cannot be invoiced until one is chosen.'::text); end if;
  if s.source_option_id is not null then
    if not exists (select 1 from public.customer_source_options so where so.id = s.source_option_id and so.is_active) then
      v_errors := v_errors || to_jsonb('The customer source is not active.'::text);
    elsif exists (select 1 from public.customer_source_options so where so.id = s.source_option_id and so.requires_details)
          and nullif(btrim(coalesce(s.source_details, '')), '') is null then
      v_blocking := v_blocking || to_jsonb('The customer source needs its details.'::text);
    end if;
  else
    v_warnings := v_warnings || to_jsonb('No customer source: new customers from the website get none.'::text);
  end if;
  if not exists (select 1 from public.event_web_keys k where k.event_id = p_event_id and k.kind = 'live' and k.revoked_at is null) then
    v_warnings := v_warnings || to_jsonb('No live key yet.'::text); end if;
  if s.sync_url is null then
    v_warnings := v_warnings || to_jsonb('No sync URL: the app does not nudge the website to update its sheet.'::text); end if;
  if exists (select 1 from public.event_days d where d.event_id = p_event_id and d.capacity is not null) then
    v_warnings := v_warnings || to_jsonb('A day has a capacity. The website never shows it, and does not stop at it.'::text); end if;
  if e.daily_start is null or e.daily_end is null then
    v_warnings := v_warnings || to_jsonb('The event has no start or finish time, so the website shows no hours: set them with Edit event.'::text); end if;
  if not e.is_active then
    v_warnings := v_warnings || to_jsonb('The event''s Tickets on sale is off: the website takes no registrations.'::text); end if;
  if s.talk_titles is null then
    v_warnings := v_warnings || to_jsonb('The talk titles are the suggested list: set the real ones under Talk titles once the speakers'' titles are known.'::text); end if;
  if s.mode = 'off' then
    v_warnings := v_warnings || to_jsonb('The website is Off: it takes no registrations or payments.'::text); end if;
  return jsonb_build_object('blocking', v_blocking, 'errors', v_blocking || v_errors, 'warnings', v_warnings);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_call(p_key_hash text, p_request_id uuid, p_type text, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  k public.event_web_keys%rowtype; s public.event_web_settings%rowtype; v_prev public.event_web_requests%rowtype;
  v_write boolean := p_type in ('register', 'vip_checkout', 'vip_paid', 'vip_transfer', 'vip_refund', 'planning_answers');
  -- 436: what the public pages set off (a form, a checkout, a transfer) has
  -- one budget; HitPay's notices (vip_paid, vip_refund, read back from HitPay
  -- by the website first) have their own, and so have planning answers (300;
  -- round 7), so neither sign-ups nor answers crowd out the other or a payment.
  v_budget text := case when p_type in ('register', 'vip_checkout', 'vip_transfer') then 'public'
                        when p_type = 'planning_answers' then 'planning' else 'hitpay' end;
  v_md5 text; v_answer jsonb; v_sub text; v_n integer; v_oldest timestamptz;
begin
  if p_type is null or p_type not in ('event_info', 'referral_info', 'register', 'person', 'vip_checkout', 'vip_paid',
                                      'vip_transfer', 'vip_refund', 'sync', 'planning_answers') then
    return jsonb_build_object('ok', false, 'error', 'invalid_request', 'field', 'type'); end if;
  if jsonb_typeof(p_body) is distinct from 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid_request', 'field', 'body'); end if;
  -- 436: the key, by its SHA-256 only; one answer for unknown and revoked.
  select * into k from public.event_web_keys where key_hash = p_key_hash and revoked_at is null;
  if not found then return jsonb_build_object('ok', false, 'error', 'bad_key'); end if;
  select * into s from public.event_web_settings where event_id = k.event_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'bad_key'); end if;
  -- A deleted event's keys answer nothing (its delete also revokes them).
  if exists (select 1 from public.events e where e.id = k.event_id and e.deleted_at is not null) then
    return jsonb_build_object('ok', false, 'error', 'bad_key'); end if;
  if (p_body->>'event') is distinct from s.code then
    return jsonb_build_object('ok', false, 'error', 'wrong_event'); end if;
  if k.last_used_at is null or k.last_used_at < now() - interval '1 minute' then
    update public.event_web_keys set last_used_at = now() where id = k.id;
  end if;
  if v_write then
    if p_request_id is null then
      return jsonb_build_object('ok', false, 'error', 'invalid_request', 'field', 'x-energia-request-id'); end if;
    -- The same request twice at once waits for the first.
    perform pg_advisory_xact_lock(hashtextextended('event-web-request:' || k.id::text || ':' || p_request_id::text, 0));
    v_md5 := md5(p_body::text);
    select * into v_prev from public.event_web_requests where key_id = k.id and request_id = p_request_id;
    if found then
      if v_prev.body_md5 is distinct from v_md5 or v_prev.type <> p_type then
        return jsonb_build_object('ok', false, 'error', 'request_conflict'); end if;
      if v_prev.response is not null then return v_prev.response; end if;
      -- Its answer was purged (after 7 days): the business ids answer again.
    else
      select count(*), min(received_at) into v_n, v_oldest from public.event_web_requests
       where key_id = k.id and is_write and received_at > now() - interval '10 minutes'
         and (case when type in ('register', 'vip_checkout', 'vip_transfer') then 'public'
                   when type = 'planning_answers' then 'planning' else 'hitpay' end) = v_budget;
      if v_n >= (case v_budget when 'public' then 120 when 'planning' then 300 else 600 end) then
        return jsonb_build_object('ok', false, 'error', 'too_many_requests',
          'retry_after_seconds', greatest(1, ceil(600 - extract(epoch from now() - v_oldest)))::integer);
      end if;
    end if;
  end if;

  -- As the settings' acting profile, so the audit log and the customer and
  -- invoice functions see an active Owner, Admin or Manager.
  v_sub := current_setting('request.jwt.claim.sub', true);
  perform set_config('request.jwt.claim.sub', s.acting_profile_id::text, true);
  v_answer := case p_type
    when 'event_info' then public.event_web_info(k.id, p_body)
    when 'referral_info' then public.event_web_referral_info(k.id, p_body)
    when 'register' then public.event_web_register(k.id, p_body)
    when 'person' then public.event_web_person(k.id, p_body)
    when 'vip_checkout' then public.event_web_vip_checkout(k.id, p_body)
    when 'vip_paid' then public.event_web_vip_paid(k.id, p_body)
    when 'vip_transfer' then public.event_web_vip_transfer(k.id, p_body)
    when 'vip_refund' then public.event_web_vip_refund(k.id, p_body)
    when 'planning_answers' then public.event_web_planning_answers(k.id, p_body)
    else public.event_web_sync(k.id, p_body) end;
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);

  if v_write then
    insert into public.event_web_requests (key_id, request_id, type, is_write, body_md5, outcome, response)
    values (k.id, p_request_id, p_type, true, v_md5, coalesce(v_answer->>'status', v_answer->>'error'), v_answer)
    on conflict (key_id, request_id) do update set response = excluded.response, outcome = excluded.outcome;
  else
    insert into public.event_web_requests (key_id, request_id, type, is_write, outcome)
    values (k.id, gen_random_uuid(), p_type, false, coalesce(v_answer->>'status', v_answer->>'error'));
  end if;
  -- A few hundred old rows at a time: answers after 7 days, rows after 60.
  delete from public.event_web_requests
   where ctid in (select ctid from public.event_web_requests where received_at < now() - interval '60 days' limit 300);
  update public.event_web_requests set response = null
   where ctid in (select ctid from public.event_web_requests
                   where response is not null and received_at < now() - interval '7 days' limit 300);
  return v_answer;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_info(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.event_web_keys%rowtype; s public.event_web_settings%rowtype; e public.events%rowtype; v jsonb;
begin
  select * into k from public.event_web_keys where id = p_key_id;
  select * into s from public.event_web_settings where event_id = k.event_id;
  select * into e from public.events where id = k.event_id;
  v := public.event_web_open_state(e.id);
  return jsonb_build_object('ok', true, 'test', k.kind = 'test', 'status', 'ok', 'event', jsonb_build_object(
    'code', s.code, 'title', e.name, 'days', v->'days',
    'daily_start', to_char(e.daily_start, 'HH24:MI'), 'daily_end', to_char(e.daily_end, 'HH24:MI'),
    'time_zone', 'Asia/Singapore', 'venue', s.venue,
    -- 436 (round 7): the talks the website asks about (null until saved: it offers the suggested
    -- list) and whether planning answers can be saved (until the event has ended).
    'talk_titles', to_jsonb(s.talk_titles), 'planning_open', public.event_web_planning_closed(e.id) is null,
    'registration_open', (v->>'registration_open')::boolean, 'closed_reason', v->'closed_reason',
    'vip', jsonb_build_object('price_cents', (v->>'vip_price_cents')::integer, 'currency', 'SGD',
                              'on_sale', (v->>'vip_on_sale')::boolean, 'covers', 'all_days')));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_referral_info(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  v := public.public_affiliate_referral_info(upper(btrim(coalesce(p_body->>'code', ''))));
  return jsonb_build_object('ok', true, 'test', (select k.kind = 'test' from public.event_web_keys k where k.id = p_key_id),
    'status', 'ok', 'valid', coalesce((v->>'valid')::boolean, false),
    'first_name', case when coalesce((v->>'valid')::boolean, false) then nullif(v->>'affiliate_name', '') end,
    'accepting', coalesce((v->>'accepting')::boolean, false));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_register(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  k public.event_web_keys%rowtype; s public.event_web_settings%rowtype; e public.events%rowtype;
  r public.event_registrations%rowtype; p public.event_registration_people%rowtype; v_prev public.event_registration_people%rowtype;
  v_test boolean; v_reg jsonb := p_body->'registration'; v_people jsonb; v_regid text; v_pmd5 text; v_state jsonb;
  v_open date[]; v_problems jsonb := '[]'; x jsonb; i integer; j integer; v_n integer;
  v_norms text[] := '{}'; v_names text[] := '{}'; v_days date[]; v_phone text; v_code text; v_ca public.customer_affiliates%rowtype;
  v_ref_state text := 'none'; v_ref uuid; v_m jsonb; v_new jsonb; v_rows jsonb := '[]'; v_union date[]; v_answer jsonb;
  v_guest public.event_guests%rowtype; v_outcome text; v_mail_ok boolean; v_self boolean;
begin
  select * into k from public.event_web_keys where id = p_key_id;
  select * into s from public.event_web_settings where event_id = k.event_id;
  select * into e from public.events where id = k.event_id;
  v_test := k.kind = 'test';
  v_people := v_reg->'people';
  v_regid := v_reg->>'registration_id';
  v_pmd5 := md5(v_people::text);
  if v_regid !~ '^REG-[0-9]{8}-[0-9A-F]{8}$' or jsonb_typeof(v_people) <> 'array'
     or jsonb_array_length(v_people) not between 1 and 10 then
    raise exception using errcode = '22023', message = 'event_web_register: malformed registration'; end if;
  v_state := public.event_web_open_state(e.id);
  if v_state->>'closed_reason' is not null then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'closed', 'reason', v_state->>'closed_reason'); end if;

  v_n := jsonb_array_length(v_people);
  v_open := array(select (d->>'date')::date from jsonb_array_elements(v_state->'days') d where (d->>'open')::boolean);
  for x, i in select t.v, t.n::integer from jsonb_array_elements(v_people) with ordinality t(v, n) loop
    if (x->>'position')::integer is distinct from i then
      raise exception using errcode = '22023', message = 'event_web_register: positions are not 1..n in order'; end if;
    v_phone := public.normalize_customer_phone(x->>'phone');
    v_norms := v_norms || coalesce(v_phone, '');
    v_names := v_names || btrim(btrim(coalesce(x->>'first_name', '')) || ' ' || btrim(coalesce(x->>'last_name', '')));
    if v_phone is null then
      v_problems := v_problems || jsonb_build_object('position', i, 'field', 'phone', 'code', 'phone_not_accepted',
        'message', 'This phone number could not be read. Enter it with its country code, e.g. +65 9123 4567.');
    end if;
    v_days := array(select distinct (d #>> '{}')::date from jsonb_array_elements(x->'days') d order by 1);
    if cardinality(v_days) = 0 or not (v_days <@ v_open) then
      v_problems := v_problems || jsonb_build_object('position', i, 'field', 'days', 'code', 'day_closed',
        'message', 'A chosen day can no longer be chosen. Choose another day.');
    end if;
  end loop;
  for i in 1 .. v_n loop
    for j in i + 1 .. v_n loop
      if v_norms[i] <> '' and v_norms[i] = v_norms[j]
         and (public.normalize_customer_match_name(v_names[i]) = public.normalize_customer_match_name(v_names[j])
              or public.customer_names_match(v_names[i], v_names[j])) then
        v_problems := v_problems || jsonb_build_object('position', j, 'field', 'people', 'code', 'same_person_twice',
          'message', format('Person %s is the same as person %s (same phone and name).', j, i));
      end if;
    end loop;
  end loop;
  if jsonb_array_length(v_problems) > 0 then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'invalid', 'problems', v_problems); end if;

  -- 162's lock on each phone (sorted, so two forms cannot deadlock), then the event's.
  for v_phone in select distinct u from unnest(v_norms) u order by 1 loop
    perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_phone, 0));
  end loop;
  perform pg_advisory_xact_lock(hashtextextended('event-registration:' || e.id::text, 0));

  -- The same form again answers as it did; other people under its id are refused.
  select * into r from public.event_registrations where event_id = e.id and registration_id = v_regid;
  if found then
    if r.people_md5 = v_pmd5 and r.is_test = v_test and r.answer is not null then return r.answer; end if;
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'invalid', 'problems', jsonb_build_array(
      jsonb_build_object('position', null, 'field', 'registration_id', 'code', 'id_reused',
        'message', 'This form was already sent with other people. Open the form again to register them.')));
  end if;
  if exists (select 1 from public.event_registrations where registration_id = v_regid) then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'invalid', 'problems', jsonb_build_array(
      jsonb_build_object('position', null, 'field', 'registration_id', 'code', 'id_reused',
        'message', 'This form was already sent. Open the form again to register.')));
  end if;

  -- The referral link, read once for the form (392's rules).
  v_code := nullif(upper(btrim(coalesce(v_reg->>'referral_code', ''))), '');
  if v_code is not null then
    select ca.* into v_ca from public.customer_affiliates ca
      join public.customers c on c.id = ca.customer_id and c.deleted_at is null
     where ca.referral_code = v_code and ca.deleted_at is null;
    if v_ca.id is null then v_ref_state := 'unknown_code';
    elsif v_ca.manually_suspended or v_ca.status <> 'active' then v_ref_state := 'link_off'; v_ref := v_ca.customer_id;
    else v_ref_state := 'valid'; v_ref := v_ca.customer_id; end if;
  end if;
  insert into public.event_registrations (event_id, registration_id, is_test, key_id, submitted_at, referral_code,
                                          referrer_customer_id, referral_state, people_count, people_md5)
  values (e.id, v_regid, v_test, k.id, nullif(v_reg->>'submitted_at', '')::timestamptz, v_code, v_ref, v_ref_state,
          v_n, v_pmd5)
  returning * into r;

  for x, i in select t.v, t.n::integer from jsonb_array_elements(v_people) with ordinality t(v, n) loop
    v_days := array(select distinct (d #>> '{}')::date from jsonb_array_elements(x->'days') d order by 1);
    -- Already registered for this event (this phone, the same words).
    select p2.* into v_prev from public.event_registration_people p2
     where p2.event_id = e.id and p2.is_test = v_test and p2.match <> 'closed' and p2.phone_norm = v_norms[i]
       and (public.normalize_customer_match_name(p2.full_name) = public.normalize_customer_match_name(v_names[i])
            or public.customer_names_match(p2.full_name, v_names[i]))
     order by p2.created_at limit 1;
    if v_prev.id is not null then
      -- 436: only the email they registered with (its inbox, as 433 compares
      -- them) reaches their record. Anyone else who knows a phone and a name
      -- is told "already registered" and gets nothing: no VIP link, no days,
      -- no names (the person's confirmation email has their link).
      v_mail_ok := v_prev.email is not null
        and public.customer_email_match_key(v_prev.email)
            = public.customer_email_match_key(nullif(lower(btrim(coalesce(x->>'email', ''))), ''));
      if not coalesce(v_mail_ok, false) then
        v_rows := v_rows || jsonb_build_object('position', i, 'person_id', null, 'upgrade_token', null, 'days', null,
          'already_registered', true, 'vip', null);
        v_prev := null;
        continue;
      end if;
      -- Their days are added, nothing else; while their VIP record stands it
      -- covers every day. A guest staff took off the list stays off (staff
      -- put them back): the attempt is noted for staff.
      v_union := array(select distinct d from unnest(v_prev.days || v_days) d order by 1);
      if v_test or exists (select 1 from public.event_guests g where g.id = v_prev.vip_guest_id and g.status = 'registered') then
        update public.event_registration_people set days = v_union, updated_at = now() where id = v_prev.id;
      else
        select * into v_guest from public.event_guests where id = v_prev.free_guest_id for update;
        if v_guest.id is not null and v_guest.status = 'registered' then
          update public.event_registration_people set days = v_union, updated_at = now() where id = v_prev.id;
          insert into public.event_guest_days (guest_id, day) select v_guest.id, d from unnest(v_days) d
          on conflict (guest_id, day) do nothing;
        elsif v_guest.id is not null and coalesce(v_guest.cancelled_reason, '') not like 'Upgraded to VIP%' then
          perform public.write_audit_ex('event_guests', v_guest.id, 'event_guest_register_again_refused',
            jsonb_build_object('status', v_guest.status, 'cancelled_reason', v_guest.cancelled_reason),
            jsonb_build_object('event_id', e.id, 'source', 'website', 'registration_id', v_regid, 'days', to_jsonb(v_days)), 'events',
            'Registered again on the website after staff took them off the list: left off (restore them on the Guests tab if they may come)', null);
        end if;
        v_guest := null;
      end if;
      v_rows := v_rows || jsonb_build_object('position', i, 'person_id', v_prev.id, 'upgrade_token', v_prev.upgrade_token,
        'days', (public.event_web_person_view(v_prev.id))->'days', 'already_registered', true,
        'vip', public.event_web_person_vip_state(v_prev.id));
      v_prev := null;
      continue;
    end if;

    insert into public.event_registration_people (registration_ref, event_id, position, is_test, first_name, last_name,
        full_name, phone, phone_norm, email, days, vip_requested, match, upgrade_token)
    values (r.id, e.id, i, v_test, btrim(x->>'first_name'), nullif(btrim(coalesce(x->>'last_name', '')), ''), v_names[i],
            btrim(x->>'phone'), v_norms[i], nullif(lower(btrim(coalesce(x->>'email', ''))), ''), v_days,
            coalesce((x->>'vip')::boolean, false), case when v_test then 'test' else 'held' end, public.event_web_new_token())
    returning * into p;
    v_m := public.event_web_match_customer(p.phone_norm, p.full_name, p.email);
    -- 436 (the owner, 21 Oct 2026): the affiliate's name (the same words) on
    -- a phone and email no customer has is held for staff, her record the
    -- one to link: linked, she is herself (not referred; her own referrer
    -- earns on her VIP as usual); made a new customer, someone else with her
    -- name, not referred through this link. Her link switched off too (the
    -- review of 21 Oct 2026): nobody is referred through it either way.
    if v_m->>'kind' = 'new' and r.referral_state in ('valid', 'link_off')
       and public.event_web_check_self_referral(p.id, null) then
      v_m := jsonb_build_object('kind', 'held', 'hold_reason', 'affiliate_name',
                                'candidates', jsonb_build_array(r.referrer_customer_id));
    end if;
    if v_test then
      -- 436: a test key changes nothing: what a live key would have done is kept
      -- (her own record matched through her switched-off link: self, as
      -- event_web_apply_referral says).
      v_self := (r.referral_state = 'valid'
                 or (r.referral_state = 'link_off' and v_m->>'kind' in ('exact', 'same_words')
                     and (v_m->>'customer_id')::uuid = r.referrer_customer_id))
                and public.event_web_check_self_referral(p.id, case when v_m->>'kind' in ('exact', 'same_words')
                                                                    then (v_m->>'customer_id')::uuid end);
      update public.event_registration_people
         set test_outcome = jsonb_build_object(
               'match', case when v_m->>'kind' = 'new' then 'new_customer' else v_m->>'kind' end,
               'hold_reason', v_m->'hold_reason',
               'referral', case when r.referral_state = 'none' then null
                                when v_self then 'self'
                                when r.referral_state <> 'valid' then r.referral_state
                                when v_m->>'kind' = 'held' then 'held'
                                when v_m->>'kind' = 'new' then 'created'
                                else 'already_customer' end)
       where id = p.id;
    else
      if v_m->>'kind' in ('exact', 'same_words') then
        perform public.event_web_fill_customer((v_m->>'customer_id')::uuid, p.id);
        v_outcome := public.event_web_apply_referral(p.id, (v_m->>'customer_id')::uuid);
        update public.event_registration_people
           set customer_id = (v_m->>'customer_id')::uuid, match = v_m->>'kind', referral_outcome = v_outcome
         where id = p.id;
      elsif v_m->>'kind' = 'held' then
        -- Her name is not referred, whether staff attach her to her record or
        -- make a customer of them (someone else with her name; attached to
        -- another existing customer, they are that customer: already_customer);
        -- anyone else's referral waits for them (made a customer on her own
        -- phone or email inbox, or on another customer's phone: until an
        -- Owner or Manager checks them).
        v_self := r.referral_state = 'valid' and public.event_web_check_self_referral(p.id, null);
        update public.event_registration_people
           set match = 'held', hold_reason = v_m->>'hold_reason',
               candidate_customer_ids = array(select (c #>> '{}')::uuid from jsonb_array_elements(v_m->'candidates') c),
               referral_outcome = case when v_self then 'self'
                                       when r.referral_state = 'valid' then 'held'
                                       when r.referral_state <> 'none' then r.referral_state end
         where id = p.id;
      else
        v_new := public.event_web_new_customer(p.id);
        update public.event_registration_people
           set customer_id = (v_new->>'customer_id')::uuid, match = 'new_customer',
               referral_outcome = v_new->>'referral_outcome'
         where id = p.id;
      end if;
      perform public.event_web_add_free_guest(p.id);
    end if;
    v_rows := v_rows || jsonb_build_object('position', i, 'person_id', p.id, 'upgrade_token', p.upgrade_token,
      'days', to_jsonb(v_days), 'already_registered', false, 'vip', 'none');
  end loop;

  -- The answer never says who was matched, made, held or referred.
  v_answer := jsonb_build_object('ok', true, 'test', v_test, 'status', 'registered', 'registration_id', v_regid,
                                 'people', v_rows);
  update public.event_registrations set answer = v_answer where id = r.id;
  return v_answer;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_person(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.event_web_keys%rowtype; p public.event_registration_people%rowtype; r public.event_registrations%rowtype;
  v_group jsonb;
begin
  select * into k from public.event_web_keys where id = p_key_id;
  select * into p from public.event_registration_people
   where upgrade_token = p_body->>'upgrade_token' and event_id = k.event_id and is_test = (k.kind = 'test');
  if not found then
    return jsonb_build_object('ok', true, 'test', k.kind = 'test', 'status', 'not_found'); end if;
  select * into r from public.event_registrations where id = p.registration_ref;
  select coalesce(jsonb_agg(jsonb_build_object('position', x.pos, 'first_name', v.v->>'first_name', 'days', v.v->'days',
                                               'vip', v.v->'vip', 'can_upgrade', v.v->'can_upgrade') order by x.pos), '[]'::jsonb)
    into v_group
    from (select distinct (a->>'person_id')::uuid as id, (a->>'position')::integer as pos
            from jsonb_array_elements(coalesce(r.answer->'people', '[]'::jsonb)) a
           where a->>'person_id' is not null) x
    cross join lateral (select public.event_web_person_view(x.id) as v) v
   where x.id <> p.id
     and exists (select 1 from public.event_registration_people q where q.id = x.id and q.match <> 'closed');
  return jsonb_build_object('ok', true, 'test', k.kind = 'test', 'status', 'ok',
    'person', public.event_web_person_view(p.id), 'group', v_group,
    'vip_price_cents', (public.event_web_open_state(k.event_id)->>'vip_price_cents')::integer,
    -- 436 (round 7): this person's own planning answers (never the others'), and whether they can answer.
    'planning', case when p.is_test then null
                     else public.event_planning_record(coalesce(p.free_guest_id, p.vip_guest_id), p.id) - 'plan_id' - 'staff_id' end,
    'planning_open', public.event_web_planning_state(p.id) = 'open');
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_order_answer(p_order uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('ok', true, 'test', o.is_test, 'status', o.status, 'order_id', o.order_id,
    'review_reason', case when o.status in ('needs_review', 'refused', 'dismissed') then o.review_reason end,
    'reason', o.refusal, 'test_note', o.test_note,
    'people', coalesce((select jsonb_agg(jsonb_build_object('person_id', p.id, 'first_name', p.first_name,
                          'invoice_no', i.invoice_no, 'vip', public.event_web_person_vip_state(p.id)) order by op.position)
                          from public.event_vip_order_people op
                          join public.event_registration_people p on p.id = op.person_id
                          left join public.invoices i on i.id = op.invoice_id
                         where op.order_ref = o.id), '[]'::jsonb))
    from public.event_vip_orders o where o.id = p_order
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_person_problems(p_order uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb := '[]'; r record; v_view jsonb; v_other text; v_inv_paid boolean;
begin
  for r in select op.position, p.* from public.event_vip_order_people op
             join public.event_registration_people p on p.id = op.person_id
            where op.order_ref = p_order order by op.position loop
    v_view := public.event_web_person_view(r.id);
    -- A VIP invoice of theirs still stands: paid (already VIP), or reopened
    -- and waiting to be paid again (a second VIP is not sold over it).
    if v_view->>'vip' in ('paid', 'pending') then
      v_other := null;
      select o.order_id, i.status::text in ('paid', 'completed_foc') into v_other, v_inv_paid
        from public.event_vip_order_people op2
        join public.event_vip_orders o on o.id = op2.order_ref
        join public.invoices i on i.id = op2.invoice_id
       where op2.person_id = r.id and o.id <> p_order and o.status = 'invoiced'
         and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
       order by i.status::text in ('paid', 'completed_foc') desc, o.created_at desc limit 1;
      if v_other is not null and v_inv_paid then
        v := v || jsonb_build_object('position', r.position, 'person_id', r.id, 'code', 'already_vip',
          'text', format('Person %s on this order is already VIP (%s)', r.position, v_other));
        continue;
      elsif v_other is not null then
        v := v || jsonb_build_object('position', r.position, 'person_id', r.id, 'code', 'payment_waiting',
          'text', format('Person %s on this order has a VIP invoice waiting to be paid (%s)', r.position, v_other));
        continue;
      end if;
    end if;
    select o.order_id into v_other from public.event_vip_order_people op2 join public.event_vip_orders o on o.id = op2.order_ref
     where op2.person_id = r.id and o.id <> p_order
       and ((o.status = 'pending' and o.expires_at > now()) or o.status in ('recorded', 'needs_review'))
     order by o.created_at desc limit 1;
    if v_other is not null then
      v := v || jsonb_build_object('position', r.position, 'person_id', r.id, 'code', 'payment_waiting',
        'text', format('Person %s on this order has another VIP payment waiting (%s)', r.position, v_other));
    elsif v_view->>'reason' = 'cancelled' then
      v := v || jsonb_build_object('position', r.position, 'person_id', r.id, 'code', 'person_cancelled',
        'text', format('Person %s on this order is no longer registered (cancelled or closed)', r.position));
    end if;
  end loop;
  return v;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_vip_checkout(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  k public.event_web_keys%rowtype; e public.events%rowtype; o public.event_vip_orders%rowtype;
  v_test boolean; v jsonb := p_body->'order'; v_order_id text; v_tokens text[]; v_state jsonb; v_ids uuid[];
  v_missing integer; v_unit integer; v_problems jsonb; t text; p public.event_registration_people%rowtype; i integer := 0;
  v_people jsonb := '[]';
begin
  select * into k from public.event_web_keys where id = p_key_id;
  select * into e from public.events where id = k.event_id;
  v_test := k.kind = 'test';
  v_order_id := v->>'order_id';
  v_tokens := array(select x #>> '{}' from jsonb_array_elements(v->'upgrade_tokens') x);
  perform pg_advisory_xact_lock(hashtextextended('event-vip-order:' || v_order_id, 0));
  select * into o from public.event_vip_orders where order_id = v_order_id;
  if found then
    if o.event_id = e.id and o.is_test = v_test and o.provider = 'hitpay'
       and array(select x from unnest(v_tokens) x order by 1)
           = array(select p2.upgrade_token from public.event_vip_order_people op join public.event_registration_people p2 on p2.id = op.person_id
                    where op.order_ref = o.id order by 1) then
      return jsonb_build_object('ok', true, 'test', v_test, 'status', 'ok', 'order_id', o.order_id,
        'unit_price_cents', o.unit_amount_cents, 'total_cents', o.amount_total_cents, 'currency', 'SGD',
        'expires_at', o.expires_at,
        'people', (select jsonb_agg(jsonb_build_object('person_id', p2.id, 'first_name', p2.first_name) order by op.position)
                     from public.event_vip_order_people op join public.event_registration_people p2 on p2.id = op.person_id
                    where op.order_ref = o.id));
    end if;
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'reason', 'id_reused', 'person_ids', '[]'::jsonb);
  end if;
  if coalesce((v->>'livemode')::boolean, false) = v_test then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'reason', 'livemode_mismatch', 'person_ids', '[]'::jsonb); end if;
  v_state := public.event_web_open_state(e.id);
  if v_state->>'closed_reason' in ('website_off', 'event_deleted', 'ended') then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'reason', 'closed', 'person_ids', '[]'::jsonb); end if;
  if not (v_state->>'vip_on_sale')::boolean then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'reason', 'vip_off_sale', 'person_ids', '[]'::jsonb); end if;
  -- The people, held while this runs, so two checkouts cannot both take them.
  select array_agg(p2.id order by p2.id) into v_ids from public.event_registration_people p2
   where p2.upgrade_token = any (v_tokens) and p2.event_id = e.id and p2.is_test = v_test;
  v_missing := cardinality(v_tokens) - coalesce(cardinality(v_ids), 0);
  if v_missing > 0 then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'reason', 'person_not_found', 'person_ids', '[]'::jsonb); end if;
  perform 1 from public.event_registration_people where id = any (v_ids) order by id for update;
  v_unit := (v_state->>'vip_price_cents')::integer;
  insert into public.event_vip_orders (event_id, order_id, provider, status, is_test, livemode, key_id, unit_amount_cents,
      quantity, amount_total_cents, payer_name, payer_email, payer_phone, checkout_opened_at, expires_at, body_md5)
  values (e.id, v_order_id, 'hitpay', 'pending', v_test, (v->>'livemode')::boolean, k.id, v_unit, cardinality(v_tokens),
          v_unit * cardinality(v_tokens), btrim(v->'payer'->>'name'), lower(btrim(v->'payer'->>'email')),
          nullif(btrim(coalesce(v->'payer'->>'phone', '')), ''), (v->>'checkout_opened_at')::timestamptz,
          (v->>'checkout_opened_at')::timestamptz + interval '70 minutes', md5(v::text))
  returning * into o;
  foreach t in array v_tokens loop
    i := i + 1;
    select * into p from public.event_registration_people where upgrade_token = t;
    insert into public.event_vip_order_people (order_ref, person_id, position) values (o.id, p.id, i);
    v_people := v_people || jsonb_build_object('person_id', p.id, 'first_name', p.first_name);
  end loop;
  v_problems := public.event_vip_person_problems(o.id);
  if jsonb_array_length(v_problems) > 0 then
    -- Nothing is kept: the website shows why.
    delete from public.event_vip_orders where id = o.id;
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'reason', v_problems->0->>'code',
      'person_ids', (select jsonb_agg(distinct x->'person_id') from jsonb_array_elements(v_problems) x
                      where x->>'code' = v_problems->0->>'code'));
  end if;
  return jsonb_build_object('ok', true, 'test', v_test, 'status', 'ok', 'order_id', o.order_id,
    'unit_price_cents', v_unit, 'total_cents', o.amount_total_cents, 'currency', 'SGD', 'expires_at', o.expires_at,
    'people', v_people);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_time_reason(p_order uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when o.paid_at > o.paid_received_at + interval '5 minutes'
      then 'HitPay''s payment time is later than when the payment arrived'
    when o.checkout_opened_at > least(o.paid_at + interval '1 minute', o.paid_received_at)
      then 'The checkout opened after it was paid, or after the payment arrived'
    when o.paid_at - o.checkout_opened_at > interval '2 hours'
      then 'It was paid more than 2 hours after the checkout opened'
    when now() - o.paid_at > interval '7 days'
      then 'It was paid more than 7 days ago' end
    || '. Check the payment in HitPay before creating its invoices'
    from public.event_vip_orders o where o.id = p_order
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_dry_run(p_order uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.event_vip_orders%rowtype; s public.event_web_settings%rowtype; v_reasons text[] := '{}'; r record;
  v_would text; v_note text; v_ready jsonb; v_method text;
begin
  select * into o from public.event_vip_orders where id = p_order;
  select * into s from public.event_web_settings where event_id = o.event_id;
  v_ready := public.event_web_readiness(o.event_id);
  select v_reasons || coalesce(array_agg(x #>> '{}'), '{}') into v_reasons
    from jsonb_array_elements(v_ready->'errors') x where (x #>> '{}') not like 'No live key%';
  if o.amount_paid_cents is distinct from o.amount_total_cents then
    v_reasons := v_reasons || format('S$%s was paid, but %s × VIP costs S$%s', to_char(coalesce(o.amount_paid_cents, 0) / 100.0, 'FM999990.00'),
      o.quantity, to_char(o.amount_total_cents / 100.0, 'FM999990.00')); end if;
  if o.provider = 'hitpay' and public.event_vip_time_reason(o.id) is not null then
    v_reasons := v_reasons || public.event_vip_time_reason(o.id); end if;
  for r in select op.position, p.test_outcome from public.event_vip_order_people op
             join public.event_registration_people p on p.id = op.person_id where op.order_ref = o.id order by op.position loop
    if r.test_outcome->>'match' = 'held' then
      v_reasons := v_reasons || format('Person %s would wait for staff to match them to a customer', r.position); end if;
  end loop;
  v_method := (select pm.name from public.payment_methods pm
                where pm.id = case o.provider when 'hitpay' then s.hitpay_payment_method_id
                                              when 'paynow' then s.paynow_payment_method_id else s.bank_payment_method_id end);
  if cardinality(v_reasons) > 0 then
    v_would := 'needs_review';
    v_note := 'A live key would have kept this for a Manager: ' || array_to_string(v_reasons, '; ') || '.';
  elsif o.provider <> 'hitpay' then
    v_would := 'recorded';
    v_note := format('A live key would have kept this %s for a Manager to confirm the money arrived, then made %s invoice(s) of S$%s paid by %s.',
      case o.provider when 'paynow' then 'PayNow transfer' else 'bank transfer' end, o.quantity,
      to_char(o.unit_amount_cents / 100.0, 'FM999990.00'), coalesce(v_method, 'its method'));
  elsif s.mode = 'record_only' then
    v_would := 'recorded';
    v_note := 'A live key would have recorded this payment (the website is Record only): no invoice yet.';
  else
    v_would := 'invoiced';
    v_note := format('A live key would have made %s invoice(s) of S$%s (VIP ticket, with %s voucher(s) free), paid by %s.',
      o.quantity, to_char(o.unit_amount_cents / 100.0, 'FM999990.00'), cardinality(s.vip_voucher_ids), coalesce(v_method, 'HitPay'));
  end if;
  return jsonb_build_object('would', v_would, 'note', v_note);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_vip_paid(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  k public.event_web_keys%rowtype; s public.event_web_settings%rowtype; e public.events%rowtype;
  o public.event_vip_orders%rowtype; v jsonb := p_body->'payment'; v_test boolean; v_tokens text[]; v_state jsonb;
  v_unit integer; v_ids uuid[]; t text; i integer := 0; v_pid uuid; v_reasons text[] := '{}'; v_dry jsonb; x jsonb;
  v_missing integer; v_new boolean := false;
begin
  select * into k from public.event_web_keys where id = p_key_id;
  select * into s from public.event_web_settings where event_id = k.event_id;
  select * into e from public.events where id = k.event_id;
  v_test := k.kind = 'test';
  v_tokens := array(select x2 #>> '{}' from jsonb_array_elements(v->'upgrade_tokens') x2);
  perform pg_advisory_xact_lock(hashtextextended('event-vip-order:' || (v->>'order_id'), 0));
  select * into o from public.event_vip_orders where order_id = v->>'order_id' for update;
  if found and (o.event_id <> e.id or o.is_test <> v_test or o.provider <> 'hitpay') then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'order_id', v->>'order_id',
      'review_reason', 'This order id belongs to another order', 'reason', 'id_reused', 'test_note', null, 'people', '[]'::jsonb);
  end if;
  if found and o.hitpay_payment_request_id is not null then
    if o.hitpay_payment_request_id = v->>'payment_request_id' then
      return public.event_web_order_answer(o.id); end if;
    -- A second payment for one order: kept for a Manager, never invoiced twice.
    perform public.write_audit_ex('event_vip_orders', o.id, 'event_vip_second_payment', null,
      jsonb_build_object('order_id', o.order_id, 'payment_request_id', v->>'payment_request_id',
                         'amount_cents', (v->>'amount_cents')::integer), 'events', null, s.store_id);
    if o.status <> 'invoiced' then
      update public.event_vip_orders set status = 'needs_review', updated_at = now(),
             review_reason = concat_ws('. ', review_reason, 'A second HitPay payment came for this order: refund one in HitPay')
       where id = o.id;
    end if;
    return public.event_web_order_answer(o.id);
  end if;
  if not found then
    -- The checkout's message was lost: the order is recorded now from the
    -- payment (money was taken, so a failed check waits for a Manager).
    v_new := true;
    v_unit := (public.event_web_open_state(e.id)->>'vip_price_cents')::integer;
    insert into public.event_vip_orders (event_id, order_id, provider, status, is_test, livemode, key_id, unit_amount_cents,
        quantity, amount_total_cents, payer_name, payer_email, payer_phone, checkout_opened_at, expires_at)
    values (e.id, v->>'order_id', 'hitpay', 'pending', v_test, (v->>'livemode')::boolean, k.id, v_unit,
            greatest(cardinality(v_tokens), 1), v_unit * greatest(cardinality(v_tokens), 1), btrim(v->'payer'->>'name'),
            lower(btrim(v->'payer'->>'email')), nullif(btrim(coalesce(v->'payer'->>'phone', '')), ''), null, null)
    returning * into o;
    foreach t in array v_tokens loop
      i := i + 1;
      v_pid := (select p.id from public.event_registration_people p
                 where p.upgrade_token = t and p.event_id = e.id and p.is_test = v_test);
      if v_pid is not null then
        insert into public.event_vip_order_people (order_ref, person_id, position) values (o.id, v_pid, i)
        on conflict do nothing;
      end if;
    end loop;
    v_missing := cardinality(v_tokens) - (select count(*) from public.event_vip_order_people where order_ref = o.id);
  end if;
  update public.event_vip_orders
     set hitpay_payment_request_id = v->>'payment_request_id', hitpay_payment_id = nullif(v->>'payment_id', ''),
         amount_paid_cents = (v->>'amount_cents')::integer, livemode = (v->>'livemode')::boolean,
         paid_at = (v->>'paid_at')::timestamptz, paid_received_at = now(),
         paid_on = ((v->>'paid_at')::timestamptz at time zone 'Asia/Singapore')::date,
         reference = v->>'payment_request_id', updated_at = now()
   where id = o.id
  returning * into o;

  if not o.livemode and not v_test then
    update public.event_vip_orders set status = 'refused', refusal = 'livemode_mismatch', review_reason = 'A HitPay test payment'
     where id = o.id;
  elsif o.livemode and v_test then
    update public.event_vip_orders set status = 'needs_review',
           review_reason = 'A real payment came through the website''s TEST key: refund it in HitPay, or have an Owner switch the website to its live key'
     where id = o.id;
  elsif v_test then
    v_dry := public.event_vip_dry_run(o.id);
    update public.event_vip_orders set status = 'test', test_would = v_dry->>'would', test_note = v_dry->>'note' where id = o.id;
  elsif s.mode = 'off' or e.deleted_at is not null then
    update public.event_vip_orders set status = 'refused', review_reason = 'The website is off' where id = o.id;
  else
    if v_new and v_missing > 0 then
      v_reasons := v_reasons || format('%s VIP link(s) in this payment are not people of this event', v_missing); end if;
    for x in select y from jsonb_array_elements(public.event_vip_person_problems(o.id)) y loop
      v_reasons := v_reasons || (x->>'text');
    end loop;
    if public.event_vip_time_reason(o.id) is not null then v_reasons := v_reasons || public.event_vip_time_reason(o.id); end if;
    if o.amount_paid_cents <> o.amount_total_cents then
      v_reasons := v_reasons || format('HitPay charged S$%s, but %s × VIP costs S$%s',
        to_char(o.amount_paid_cents / 100.0, 'FM999990.00'), o.quantity, to_char(o.amount_total_cents / 100.0, 'FM999990.00'));
    end if;
    if cardinality(v_reasons) > 0 then
      update public.event_vip_orders set status = 'needs_review', review_reason = array_to_string(v_reasons, '. ') where id = o.id;
    elsif s.mode = 'record_only' then
      update public.event_vip_orders set status = 'recorded', review_reason = null where id = o.id;
    else
      update public.event_vip_orders set status = 'recorded' where id = o.id;
      perform public.event_vip_make_invoices(o.id, false);
    end if;
  end if;
  return public.event_web_order_answer(o.id);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_vip_transfer(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  k public.event_web_keys%rowtype; e public.events%rowtype; o public.event_vip_orders%rowtype; v jsonb := p_body->'order';
  v_test boolean; v_tokens text[]; v_state jsonb; v_ids uuid[]; v_unit integer; v_total integer; v_reasons text[] := '{}';
  t text; i integer := 0; x jsonb; v_dry jsonb; v_paid_on date; v_day date; v_same text; v_status text;
begin
  select * into k from public.event_web_keys where id = p_key_id;
  select * into e from public.events where id = k.event_id;
  v_test := k.kind = 'test';
  v_tokens := array(select y #>> '{}' from jsonb_array_elements(v->'upgrade_tokens') y);
  v_paid_on := (v->>'paid_on')::date;
  perform pg_advisory_xact_lock(hashtextextended('event-vip-order:' || (v->>'order_id'), 0));
  select * into o from public.event_vip_orders where order_id = v->>'order_id';
  if found then
    -- 436: the same order again (the same people, method, amount, reference
    -- and day; submitted_at or the payer's details may differ) answers as the
    -- first did; anything else under its id is id_reused.
    if o.event_id = e.id and o.is_test = v_test and o.provider = v->>'method'
       and (o.body_md5 = md5(v::text)
            or (o.amount_paid_cents is not distinct from (v->>'amount_cents')::integer
                and o.reference is not distinct from btrim(v->>'reference')
                and o.paid_on is not distinct from v_paid_on
                and array(select y from unnest(v_tokens) y order by 1)
                    = array(select p2.upgrade_token from public.event_vip_order_people op
                              join public.event_registration_people p2 on p2.id = op.person_id
                             where op.order_ref = o.id order by 1))) then
      return public.event_web_order_answer(o.id); end if;
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'order_id', v->>'order_id',
      'review_reason', null, 'reason', 'id_reused', 'test_note', null, 'people', '[]'::jsonb);
  end if;
  v_state := public.event_web_open_state(e.id);
  if v_state->>'closed_reason' in ('website_off', 'event_deleted', 'ended') then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'order_id', v->>'order_id',
      'review_reason', null, 'reason', 'closed', 'test_note', null, 'people', '[]'::jsonb); end if;
  select array_agg(p.id) into v_ids from public.event_registration_people p
   where p.upgrade_token = any (v_tokens) and p.event_id = e.id and p.is_test = v_test;
  if coalesce(cardinality(v_ids), 0) <> cardinality(v_tokens) then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'refused', 'order_id', v->>'order_id',
      'review_reason', null, 'reason', 'person_not_found', 'test_note', null, 'people', '[]'::jsonb); end if;
  perform 1 from public.event_registration_people where id = any (v_ids) order by id for update;
  v_unit := (v_state->>'vip_price_cents')::integer;
  v_total := v_unit * cardinality(v_tokens);
  insert into public.event_vip_orders (event_id, order_id, provider, status, is_test, livemode, key_id, unit_amount_cents,
      quantity, amount_total_cents, amount_paid_cents, payer_name, payer_email, payer_phone, checkout_opened_at,
      paid_received_at, paid_on, reference, body_md5)
  values (e.id, v->>'order_id', v->>'method', 'recorded', v_test, not v_test, k.id, v_unit, cardinality(v_tokens), v_total,
          (v->>'amount_cents')::integer, btrim(v->'payer'->>'name'), lower(btrim(v->'payer'->>'email')),
          nullif(btrim(coalesce(v->'payer'->>'phone', '')), ''), (v->>'submitted_at')::timestamptz, now(), v_paid_on,
          btrim(v->>'reference'), md5(v::text))
  returning * into o;
  foreach t in array v_tokens loop
    i := i + 1;
    insert into public.event_vip_order_people (order_ref, person_id, position)
    select o.id, p.id, i from public.event_registration_people p where p.upgrade_token = t;
  end loop;
  if v_test then
    v_dry := public.event_vip_dry_run(o.id);
    update public.event_vip_orders set status = 'test', test_would = v_dry->>'would', test_note = v_dry->>'note' where id = o.id;
    return public.event_web_order_answer(o.id);
  end if;
  -- Every reason it waits for a Manager (as 380's staff link).
  if o.amount_paid_cents <> v_total then
    v_reasons := v_reasons || format('S$%s was paid, but %s × VIP costs S$%s', to_char(o.amount_paid_cents / 100.0, 'FM999990.00'),
      o.quantity, to_char(v_total / 100.0, 'FM999990.00')); end if;
  v_day := ((v->>'submitted_at')::timestamptz at time zone 'Asia/Singapore')::date;
  if v_paid_on > public.sg_today() then
    v_reasons := v_reasons || format('The date paid (%s) is after today', to_char(v_paid_on, 'DD Mon YYYY'));
  elsif v_paid_on < v_day - 60 then
    v_reasons := v_reasons || format('The date paid (%s) is more than 60 days before the order', to_char(v_paid_on, 'DD Mon YYYY'));
  end if;
  select o2.order_id into v_same from public.event_vip_orders o2
   where o2.event_id = e.id and o2.id <> o.id and o2.provider in ('paynow', 'bank') and not o2.is_test
     and o2.status not in ('refused', 'dismissed') and o2.created_at > now() - interval '24 hours'
     and public.normalize_customer_phone(o2.payer_phone) = public.normalize_customer_phone(o.payer_phone)
     and array(select op.person_id from public.event_vip_order_people op where op.order_ref = o2.id order by 1)
         = array(select op.person_id from public.event_vip_order_people op where op.order_ref = o.id order by 1)
   order by o2.created_at limit 1;
  if v_same is not null then v_reasons := v_reasons || ('Possibly the same as ' || v_same); end if;
  for x in select y from jsonb_array_elements(public.event_vip_person_problems(o.id)) y loop
    v_reasons := v_reasons || (x->>'text');
  end loop;
  select v_reasons || coalesce(array_agg(format('Person %s on this order is still to be matched to a customer (Guests, To match)', op.position)
                                         order by op.position), '{}')
    into v_reasons
    from public.event_vip_order_people op join public.event_registration_people p on p.id = op.person_id
   where op.order_ref = o.id and p.match = 'held';
  if not (v_state->>'vip_on_sale')::boolean then v_reasons := v_reasons || 'VIP is off sale'::text; end if;
  v_status := case when cardinality(v_reasons) > 0 then 'needs_review' else 'recorded' end;
  update public.event_vip_orders set status = v_status,
         review_reason = case when cardinality(v_reasons) > 0 then array_to_string(v_reasons, '. ') end
   where id = o.id;
  return public.event_web_order_answer(o.id);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_vip_refund(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.event_web_keys%rowtype; o public.event_vip_orders%rowtype; v jsonb := p_body->'refund'; v_test boolean;
begin
  select * into k from public.event_web_keys where id = p_key_id;
  v_test := k.kind = 'test';
  select * into o from public.event_vip_orders
   where order_id = v->>'order_id' and event_id = k.event_id and is_test = v_test and provider = 'hitpay'
     and hitpay_payment_request_id = v->>'payment_request_id'
   for update;
  if not found then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'not_found', 'order_id', v->>'order_id'); end if;
  if (v->>'refunded_cents_total')::integer > o.refunded_cents_total then
    update public.event_vip_orders
       set refunded_cents_total = (v->>'refunded_cents_total')::integer, refund_noted_at = (v->>'refunded_at')::timestamptz,
           updated_at = now()
     where id = o.id returning * into o;
    perform public.write_audit_ex('event_vip_orders', o.id, 'event_vip_refund_noted', null,
      jsonb_build_object('order_id', o.order_id, 'refunded_cents_total', o.refunded_cents_total), 'events', null,
      (select s.store_id from public.event_web_settings s where s.event_id = o.event_id));
  end if;
  return jsonb_build_object('ok', true, 'test', v_test, 'status', 'noted', 'order_id', o.order_id,
                            'refunded_cents_total', o.refunded_cents_total);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_guest_key(p_prefix text, p_guest uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p_prefix || '-' || upper(substr(replace(g.id::text, '-', ''), 1,
           case when exists (select 1 from public.event_guests g2
                              where g2.event_id = g.event_id and g2.id <> g.id
                                and substr(replace(g2.id::text, '-', ''), 1, 8) = substr(replace(g.id::text, '-', ''), 1, 8)
                                and (g2.created_at, g2.id) < (g.created_at, g.id)) then 12 else 8 end))
    from public.event_guests g where g.id = p_guest
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_sync(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.event_web_keys%rowtype; s public.event_web_settings%rowtype; e public.events%rowtype; v_test boolean;
  v_people jsonb; v_orders jsonb; v_free jsonb := '[]'; v_counter jsonb := '[]';
begin
  select * into k from public.event_web_keys where id = p_key_id;
  select * into e from public.events where id = k.event_id;
  v_test := k.kind = 'test';
  update public.event_web_settings
     set last_sync_at = case when v_test then last_sync_at else now() end,
         last_test_sync_at = case when v_test then now() else last_test_sync_at end
   where event_id = k.event_id
     and coalesce(case when v_test then last_test_sync_at else last_sync_at end, '-infinity'::timestamptz)
         <= now() - interval '60 seconds'
  returning * into s;
  if not found then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'too_soon'); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'key', p.id::text, 'source', 'website', 'registration_id', r.registration_id, 'position', p.position,
      'group_size', r.people_count, 'registered_at', coalesce(r.submitted_at, p.created_at),
      'name', p.full_name, 'phone', p.phone, 'email', p.email,
      'days', coalesce((select jsonb_agg(gd.day order by gd.day) from public.event_guest_days gd where gd.guest_id = g.id),
                       (select jsonb_agg(d order by d) from unnest(p.days) d)),
      'status', case when p.match = 'closed' or g.status = 'cancelled' then 'cancelled' else 'registered' end,
      'cancelled_reason', case when p.match = 'closed' then coalesce(p.resolution_note, 'Closed by staff')
                               when g.status = 'cancelled' then g.cancelled_reason end,
      'vip', public.event_web_person_vip_state(p.id),
      'vip_invoice_no', vo.invoice_no, 'vip_method', vo.method, 'vip_order_id', vo.order_id,
      'referral_code', case when r.referral_state <> 'none' then r.referral_code end,
      'registered_by', null,
      -- 436 (round 7): a website person's planning answers, by person (a test key's: none)
      'planning', case when p.is_test then null
                       else public.event_planning_record(coalesce(p.free_guest_id, p.vip_guest_id), p.id) - 'plan_id' - 'staff_id' end)
      order by r.created_at, p.position), '[]'::jsonb)
    into v_people
    from public.event_registration_people p
    join public.event_registrations r on r.id = p.registration_ref
    left join public.event_guests vg on vg.id = p.vip_guest_id
    left join public.event_guests g on g.id = case when vg.status = 'registered' then vg.id else p.free_guest_id end
    left join lateral (select o.order_id, i.invoice_no,
                              case o.provider when 'hitpay' then 'HitPay' when 'paynow' then 'PayNow' else 'Bank Transfer' end as method
                         from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
                         left join public.invoices i on i.id = op.invoice_id
                        where op.person_id = p.id
                          and (o.status in ('invoiced', 'recorded', 'needs_review', 'test')
                               or (o.status = 'pending' and o.expires_at > now()))
                        order by (o.status = 'invoiced') desc, o.created_at desc limit 1) vo on true
   where p.event_id = e.id and p.is_test = v_test;

  if not v_test then
    select coalesce(jsonb_agg(jsonb_build_object(
        'key', public.event_web_guest_key(case when g.source = 'free' then 'GUEST' else 'TICKET' end, g.id),
        'source', case when g.source = 'free' then 'staff' else 'counter' end,
        'registration_id', null, 'position', null, 'group_size', null, 'registered_at', g.created_at,
        'name', g.name, 'phone', g.phone, 'email', c.email,
        'days', coalesce((select jsonb_agg(gd.day order by gd.day) from public.event_guest_days gd where gd.guest_id = g.id), '[]'::jsonb),
        'status', g.status, 'cancelled_reason', g.cancelled_reason,
        'vip', case when g.source = 'ticket' and g.ticket_option_id = s.vip_option_id then
                      case when i.deleted_at is not null or i.status::text in ('cancelled', 'refunded') then 'refunded'
                           when i.status::text in ('paid', 'completed_foc') then 'paid' else 'pending' end
                    else 'none' end,
        'vip_invoice_no', case when g.source = 'ticket' and g.ticket_option_id = s.vip_option_id then i.invoice_no end,
        'vip_method', null, 'vip_order_id', null, 'referral_code', null,
        'registered_by', rb.full_name,
        -- 436 (round 7): staff and counter guests' answers stay in the app (the sheet never lists them)
        'planning', null) order by g.created_at, g.id), '[]'::jsonb)
      into v_free
      from public.event_guests g
      left join public.customers c on c.id = g.customer_id
      left join public.invoices i on i.id = g.invoice_id
      left join public.profiles rb on rb.id = g.registered_by
     where g.event_id = e.id
       and not exists (select 1 from public.event_registration_people p
                        where p.free_guest_id = g.id or p.vip_guest_id = g.id);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'order_id', o.order_id, 'provider', o.provider, 'status', o.status,
      'amount_cents', coalesce(o.amount_paid_cents, o.amount_total_cents),
      'paid_at', o.paid_at, 'paid_on', o.paid_on, 'reference', o.reference,
      'invoice_nos', coalesce((select jsonb_agg(i.invoice_no order by op.position) from public.event_vip_order_people op
                                 join public.invoices i on i.id = op.invoice_id where op.order_ref = o.id), '[]'::jsonb),
      'refunded_cents_total', o.refunded_cents_total,
      'person_ids', coalesce((select jsonb_agg(op.person_id order by op.position) from public.event_vip_order_people op
                               where op.order_ref = o.id), '[]'::jsonb)) order by o.created_at), '[]'::jsonb)
    into v_orders
    from public.event_vip_orders o
   where o.event_id = e.id and o.is_test = v_test and (o.status <> 'pending' or o.expires_at > now());

  return jsonb_build_object('ok', true, 'test', v_test, 'status', 'ok',
    'event', jsonb_build_object('code', s.code, 'title', e.name,
               'days', coalesce((select jsonb_agg(d.day order by d.day) from public.event_days d where d.event_id = e.id), '[]'::jsonb),
               'venue', s.venue),
    'people', v_people || v_free, 'vip_orders', v_orders);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_sync_ping()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n integer := 0;
begin
  for r in select s.code, s.sync_url from public.event_web_settings s join public.events e on e.id = s.event_id
            where s.sync_url is not null and s.mode <> 'off' and e.deleted_at is null
              and (select max(d.day) from public.event_days d where d.event_id = s.event_id) + 14 >= public.sg_today()
            order by s.code loop
    perform net.http_post(url := r.sync_url, body := jsonb_build_object('event', r.code),
                          headers := jsonb_build_object('Content-Type', 'application/json'),
                          timeout_milliseconds := 10000);
    n := n + 1;
  end loop;
  return n;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_make_invoices(p_order_id uuid, p_reviewed boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  o public.event_vip_orders%rowtype; s public.event_web_settings%rowtype; e public.events%rowtype;
  opt public.event_ticket_options%rowtype; r record; v_prev text; v_state text; v_reason text; v_method uuid;
  v_days date[]; v_items jsonb; v_inv uuid; v_inv_no text; v_total numeric; v_line uuid; v_vipg uuid; v_paid date;
  v_unmatched boolean := false; v_count integer; x uuid; v_vname text; v_foc text; v_today date := public.sg_today();
begin
  select * into o from public.event_vip_orders where id = p_order_id for update;
  if not found then raise exception 'VIP order not found'; end if;
  if o.status = 'invoiced' or o.is_test or o.status not in ('recorded', 'needs_review') then
    return jsonb_build_object('status', o.status, 'review_reason', o.review_reason,
      'invoice_nos', coalesce((select jsonb_agg(i.invoice_no order by op.position) from public.event_vip_order_people op
                                 join public.invoices i on i.id = op.invoice_id where op.order_ref = o.id), '[]'::jsonb));
  end if;
  select * into s from public.event_web_settings where event_id = o.event_id;
  select * into e from public.events where id = o.event_id;
  v_prev := current_setting('request.jwt.claim.sub', true);
  perform set_config('request.jwt.claim.sub', s.acting_profile_id::text, true);
  begin
    -- Times that do not hang together wait for a person (373), unless a
    -- Manager has looked (Create invoices).
    if not p_reviewed and o.provider = 'hitpay' and public.event_vip_time_reason(o.id) is not null then
      raise exception 'EVENT_VIP_REVIEW: %', public.event_vip_time_reason(o.id); end if;
    if not exists (select 1 from public.profiles pr where pr.id = s.acting_profile_id and pr.is_active and pr.deleted_at is null
                     and coalesce(pr.invitation_status, 'accepted') = 'accepted' and pr.role in ('owner', 'admin', 'manager'))
       or not public.user_has_store_access(s.store_id) then
      raise exception 'EVENT_VIP_REVIEW: The person who raises the website''s invoices is not an active Owner, Admin or Manager of the store'; end if;
    select * into opt from public.event_ticket_options where id = s.vip_option_id and event_id = e.id;
    select array_agg(d.day order by d.day) into v_days from public.event_days d where d.event_id = e.id;
    if opt.id is null then raise exception 'EVENT_VIP_REVIEW: The website settings have no VIP ticket'; end if;
    if opt.days_count <> coalesce(cardinality(v_days), 0) then
      raise exception 'EVENT_VIP_REVIEW: The VIP ticket does not cover every day of the event'; end if;
    foreach x in array s.vip_voucher_ids loop
      select v.name into v_vname from public.vouchers v where v.id = x and v.is_active and v.deleted_at is null;
      if v_vname is null then raise exception 'EVENT_VIP_REVIEW: A VIP voucher is no longer active'; end if;
      if not coalesce((public.voucher_price_for(s.store_id, x, true)->>'has_price')::boolean, false) then
        raise exception 'EVENT_VIP_REVIEW: "%" has no price at the store. Give it one on the Vouchers page, then Create invoices', v_vname; end if;
    end loop;
    v_method := case o.provider when 'hitpay' then s.hitpay_payment_method_id
                                when 'paynow' then s.paynow_payment_method_id else s.bank_payment_method_id end;
    if v_method is null or not exists (select 1 from public.payment_methods pm where pm.id = v_method and pm.is_active and pm.deleted_at is null) then
      raise exception 'EVENT_VIP_REVIEW: The website settings have no active % payment method',
        case o.provider when 'hitpay' then 'HitPay' when 'paynow' then 'PayNow' else 'bank transfer' end; end if;
    select count(*) into v_count from public.event_vip_order_people where order_ref = o.id;
    if v_count = 0 or v_count <> o.quantity then
      raise exception 'EVENT_VIP_REVIEW: The order''s people are not all people of this event'; end if;
    if coalesce(o.amount_paid_cents, -1) <> o.unit_amount_cents * o.quantity then
      raise exception 'EVENT_VIP_REVIEW: The invoices would be S$% but S$% was paid, so nothing was invoiced%',
        to_char(o.unit_amount_cents * o.quantity / 100.0, 'FM999990.00'), to_char(coalesce(o.amount_paid_cents, 0) / 100.0, 'FM999990.00'),
        case when o.provider in ('paynow', 'bank')
             then '. If the buyer typed the amount wrong, enter what arrived when you create the invoices; if what arrived is not '
                  || o.quantity || ' × S$' || to_char(o.unit_amount_cents / 100.0, 'FM999990.00')
                  || ', dismiss this order and send the VIP link again for the people actually paid for'
             else '' end; end if;
    for r in select op.position, p.* from public.event_vip_order_people op
               join public.event_registration_people p on p.id = op.person_id
              where op.order_ref = o.id order by op.position loop
      if r.match = 'closed' then
        raise exception 'EVENT_VIP_REVIEW: Person % on this order was closed by staff', r.position; end if;
      if r.customer_id is null or not exists (select 1 from public.customers c where c.id = r.customer_id and c.deleted_at is null) then
        v_unmatched := true;
        raise exception 'EVENT_VIP_REVIEW: Person % on this order is still to be matched to a customer (Guests, To match). It is invoiced once they are', r.position; end if;
      if exists (select 1 from public.event_vip_order_people op2 join public.event_vip_orders o2 on o2.id = op2.order_ref
                   join public.invoices i on i.id = op2.invoice_id
                  where op2.person_id = r.id and o2.id <> o.id and o2.status = 'invoiced'
                    and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')) then
        raise exception 'EVENT_VIP_REVIEW: Person % on this order is already VIP', r.position; end if;
    end loop;

    -- The money is taken: this order's VIP tickets pass the On sale check
    -- (event_ticket_line_check, 415's rule) while its invoices are made.
    perform set_config('energia.paid_vip_order', o.id::text, true);
    v_paid := least(case when o.provider = 'hitpay' then (o.paid_at at time zone 'Asia/Singapore')::date else o.paid_on end, v_today);
    v_foc := 'Included with VIP · ' || e.name;
    for r in select op.position, p.* from public.event_vip_order_people op
               join public.event_registration_people p on p.id = op.person_id
              where op.order_ref = o.id order by op.position loop
      -- One invoice per person, made out to them: the VIP ticket covering
      -- every day, and the VIP vouchers free.
      v_items := jsonb_build_array(jsonb_build_object(
          'kind', 'event_ticket', 'event_ticket_option_id', opt.id, 'quantity', 1, 'event_days', to_jsonb(v_days),
          'attendees', jsonb_build_array(jsonb_build_object('name', r.full_name, 'phone', r.phone_norm, 'customer_id', r.customer_id))))
        || coalesce((select jsonb_agg(jsonb_build_object('kind', 'voucher', 'voucher_id', vid, 'quantity', 1,
                                                         'is_foc', true, 'foc_reason', v_foc) order by n)
                       from unnest(s.vip_voucher_ids) with ordinality u(vid, n)), '[]'::jsonb);
      v_inv := public.create_invoice_with_details(s.store_id, r.customer_id, v_items, jsonb_build_object(
        'business_date', v_paid::text,
        'notes', 'Website VIP · ' || o.order_id || ' · '
                 || case o.provider when 'hitpay' then 'HitPay ' || coalesce(o.hitpay_payment_id, o.hitpay_payment_request_id)
                                    when 'paynow' then 'PayNow ref ' || coalesce(o.reference, '')
                                    else 'Bank ref ' || coalesce(o.reference, '') end
                 || ' · ' || r.position || ' of ' || o.quantity,
        'manual_discount', 0,
        'request_id', public.web_order_uuid('event-vip-invoice:' || o.order_id || ':' || r.id::text)));
      select total_amount, invoice_no into v_total, v_inv_no from public.invoices where id = v_inv;
      if v_total <> round(o.unit_amount_cents / 100.0, 2) then
        raise exception 'EVENT_VIP_REVIEW: The invoice would be S$% but S$% was paid for each person, so nothing was invoiced',
          to_char(v_total, 'FM999990.00'), to_char(o.unit_amount_cents / 100.0, 'FM999990.00'); end if;
      if v_total > 0 then
        perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object(
          'payment_method_id', v_method, 'amount', v_total,
          'reference', case when o.provider = 'hitpay' then coalesce(o.hitpay_payment_id, o.hitpay_payment_request_id) else o.reference end,
          'payment_date', v_paid)),
          public.web_order_uuid('event-vip-payment:' || o.order_id || ':' || r.id::text));
      end if;
      select ii.id into v_line from public.invoice_items ii
       where ii.invoice_id = v_inv and ii.line_kind = 'event_ticket' limit 1;
      select g.id into v_vipg from public.event_guests g where g.invoice_item_id = v_line order by g.line_position limit 1;
      -- Their free record's check-ins go onto the VIP record, which is now
      -- theirs; the free one is parked (it comes back if the VIP is cancelled).
      update public.event_guest_days vd
         set attended_at = fd.attended_at, checked_in_by = fd.checked_in_by, check_in_code = fd.check_in_code
        from public.event_guest_days fd
       where fd.guest_id = r.free_guest_id and vd.guest_id = v_vipg and vd.day = fd.day
         and fd.attended_at is not null and vd.attended_at is null;
      update public.event_guests g set notes = coalesce(g.notes, (select f.notes from public.event_guests f where f.id = r.free_guest_id))
       where g.id = v_vipg;
      perform set_config('energia.vip_guest_follow', '1', true);
      update public.event_guests
         set status = 'cancelled', cancelled_reason = 'Upgraded to VIP · ' || v_inv_no, cancelled_at = now(),
             updated_at = now(), updated_by = auth.uid()
       where id = r.free_guest_id and status = 'registered';
      perform set_config('energia.vip_guest_follow', '', true);
      update public.event_registration_people set vip_guest_id = v_vipg, updated_at = now() where id = r.id;
      update public.event_vip_order_people set invoice_id = v_inv, invoice_item_id = v_line
       where order_ref = o.id and person_id = r.id;
    end loop;
    perform set_config('energia.paid_vip_order', '', true);
    update public.event_vip_orders
       set status = 'invoiced', review_reason = null, waiting_for_match = false, updated_at = now(), updated_by = auth.uid()
     where id = o.id;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_reason = message_text;
    perform set_config('energia.paid_vip_order', '', true);
    perform set_config('energia.vip_guest_follow', '', true);
    -- Passing faults: the caller tries again.
    if v_state in ('23505', '40001', '40P01', '55P03', '57014', '53300') and v_reason not like 'EVENT_VIP_REVIEW:%' then
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      raise;
    end if;
    update public.event_vip_orders
       set status = 'needs_review', review_reason = regexp_replace(v_reason, '^EVENT_VIP_REVIEW:\s*', ''),
           waiting_for_match = v_unmatched, updated_at = now()
     where id = o.id;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
  select * into o from public.event_vip_orders where id = p_order_id;
  return jsonb_build_object('status', o.status, 'review_reason', o.review_reason,
    'invoice_nos', coalesce((select jsonb_agg(i.invoice_no order by op.position) from public.event_vip_order_people op
                               join public.invoices i on i.id = op.invoice_id where op.order_ref = o.id), '[]'::jsonb));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_retry_after_match(p_person_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v jsonb := '[]'; a jsonb;
begin
  for r in select o.id, o.order_id from public.event_vip_orders o
             join public.event_vip_order_people op on op.order_ref = o.id
             join public.event_web_settings s on s.event_id = o.event_id
            where op.person_id = p_person_id and o.status = 'needs_review' and o.waiting_for_match
              and o.provider = 'hitpay' and not o.is_test and coalesce(o.livemode, false) and s.mode = 'live'
            order by o.created_at loop
    a := public.event_vip_make_invoices(r.id, false);
    v := v || jsonb_build_object('order_id', r.order_id, 'status', a->>'status', 'review_reason', a->>'review_reason');
  end loop;
  return v;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.trg_event_vip_guest_follow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype;
begin
  if new.status is not distinct from old.status then return null; end if;
  select * into p from public.event_registration_people where vip_guest_id = new.id;
  if not found and new.status = 'registered' and new.source = 'ticket' and new.invoice_item_id is not null then
    -- 436: an older VIP invoice of theirs reopened once a newer one was
    -- cancelled (the parked-guest trigger refuses it while a newer one
    -- stands): that ticket's record is their VIP record again.
    select p2.* into p from public.event_vip_order_people op
      join public.event_registration_people p2 on p2.id = op.person_id
     where op.invoice_item_id = new.invoice_item_id
     order by p2.created_at limit 1;
    if p.id is not null then
      update public.event_registration_people set vip_guest_id = new.id, updated_at = now() where id = p.id;
    end if;
  end if;
  if p.id is null or p.free_guest_id is null then return null; end if;
  perform set_config('energia.vip_guest_follow', '1', true);
  if new.status = 'cancelled' then
    insert into public.event_guest_days (guest_id, day, attended_at, checked_in_by, check_in_code)
    select p.free_guest_id, d.day, d.attended_at, d.checked_in_by, d.check_in_code
      from public.event_guest_days d where d.guest_id = new.id and d.attended_at is not null
    on conflict (guest_id, day) do update
      set attended_at = coalesce(event_guest_days.attended_at, excluded.attended_at),
          checked_in_by = case when event_guest_days.attended_at is null then excluded.checked_in_by else event_guest_days.checked_in_by end,
          check_in_code = case when event_guest_days.attended_at is null then excluded.check_in_code else event_guest_days.check_in_code end;
    update public.event_guests
       set status = 'registered', cancelled_reason = null, cancelled_at = null, updated_at = now()
     where id = p.free_guest_id and status = 'cancelled' and cancelled_reason like 'Upgraded to VIP%';
  else
    update public.event_guest_days vd
       set attended_at = fd.attended_at, checked_in_by = fd.checked_in_by, check_in_code = fd.check_in_code
      from public.event_guest_days fd
     where fd.guest_id = p.free_guest_id and vd.guest_id = new.id and vd.day = fd.day
       and fd.attended_at is not null and vd.attended_at is null;
    update public.event_guests
       set status = 'cancelled', cancelled_at = now(), updated_at = now(),
           cancelled_reason = 'Upgraded to VIP · ' || coalesce((select i.invoice_no from public.invoices i where i.id = new.invoice_id), '')
     where id = p.free_guest_id and status = 'registered';
  end if;
  perform set_config('energia.vip_guest_follow', '', true);
  return null;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.trg_event_vip_parked_guest()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_newer text;
begin
  if old.status = 'cancelled' and new.status = 'registered'
     and coalesce(current_setting('energia.vip_guest_follow', true), '') <> '1'
     and coalesce(old.cancelled_reason, '') like 'Upgraded to VIP%'
     and exists (select 1 from public.event_registration_people p
                   join public.event_guests vg on vg.id = p.vip_guest_id
                  where p.free_guest_id = old.id and vg.status = 'registered') then
    raise exception '% is a VIP guest: their VIP record is on the list', old.name;
  end if;
  if old.status = 'cancelled' and new.status = 'registered' and old.source = 'ticket' and old.invoice_item_id is not null then
    select coalesce(i.invoice_no, 'another invoice') into v_newer
      from public.event_vip_order_people op
      join public.event_registration_people p on p.id = op.person_id
      join public.event_guests vg on vg.id = p.vip_guest_id
      left join public.invoices i on i.id = vg.invoice_id
     where op.invoice_item_id = old.invoice_item_id and p.vip_guest_id <> old.id and vg.status = 'registered'
     limit 1;
    if v_newer is not null then
      raise exception '% already has a newer VIP record (%). Cancel or refund it before reopening this invoice.', old.name, v_newer;
    end if;
  end if;
  return new;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.trg_event_web_delete_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer; k public.event_web_keys%rowtype;
begin
  if old.deleted_at is null and new.deleted_at is not null then
    if exists (select 1 from public.event_web_settings s where s.event_id = new.id and s.mode <> 'off') then
      raise exception 'The website still takes registrations for "%". Switch it Off on the Website tab, then delete the event.', new.name;
    end if;
    select count(*) into n from public.event_vip_orders o
     where o.event_id = new.id
       and ((o.status = 'pending' and o.expires_at > now() and not o.is_test)
            or o.status in ('recorded', 'needs_review') and (not o.is_test or coalesce(o.livemode, false))
            or (o.status = 'refused' and coalesce(o.livemode, false) and coalesce(o.amount_paid_cents, 0) > 0
                and o.refusal is null));
    if n > 0 then
      raise exception 'The website of "%" has % VIP payment(s) waiting. Create their invoices, or close them as refunded, first.', new.name, n;
    end if;
    -- 436: its keys stop with it (the Website tab no longer shows a deleted
    -- event, so they could not be revoked there).
    for k in select * from public.event_web_keys where event_id = new.id and revoked_at is null loop
      update public.event_web_keys set revoked_at = now(), revoked_by = auth.uid(), revoked_reason = 'Event deleted' where id = k.id;
      perform public.write_audit_ex('event_web_keys', k.id, 'event_web_key_revoked',
        jsonb_build_object('kind', k.kind, 'key_hint', k.key_hint), jsonb_build_object('revoked', true), 'events', 'Event deleted',
        (select s.store_id from public.event_web_settings s where s.event_id = new.id));
    end loop;
  end if;
  return new;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_invoice_items(p_invoice_id uuid)
 RETURNS TABLE(invoice_item_id uuid, kind text, voucher_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with web as (
    select exists (select 1 from public.event_vip_order_people op where op.invoice_id = p_invoice_id) as yes),
  counter as (
    select it.id, it.line_kind::text as line_kind, it.voucher_id
      from public.invoice_items it
     where it.invoice_id = p_invoice_id
       and ((it.line_kind = 'event_ticket'
             and exists (select 1 from public.event_web_settings s where s.vip_option_id = it.event_ticket_option_id))
            or (it.line_kind = 'voucher' and coalesce(it.is_foc, false)
                and exists (select 1 from public.invoice_items t
                              join public.event_web_settings s on s.vip_option_id = t.event_ticket_option_id
                             where t.invoice_id = p_invoice_id and t.line_kind = 'event_ticket'
                               and it.voucher_id = any (s.vip_voucher_ids)))))
  select it.id, case when it.line_kind = 'event_ticket' then 'ticket' else 'voucher' end, it.voucher_id
    from public.invoice_items it, web
   where web.yes and it.invoice_id = p_invoice_id
     and (it.line_kind = 'event_ticket' or (it.line_kind = 'voucher' and coalesce(it.is_foc, false)))
  union all
  select c.id, case when c.line_kind = 'event_ticket' then 'ticket' else 'voucher' end, c.voucher_id
    from counter c, web
   where not web.yes and exists (select 1 from counter c2 where c2.line_kind = 'voucher')
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_used_later(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('invoice_id', l.id, 'invoice_no', l.invoice_no, 'voucher', vo.name,
                            'customer_id', l.customer_id, 'holder', c.full_name)
    from public.invoices i
    join public.invoices l on l.id <> i.id and l.created_at >= i.created_at
                          and l.deleted_at is null and l.status::text <> 'cancelled'
    join public.vouchers vo on vo.id in (select x.voucher_id from public.event_vip_invoice_items(i.id) x where x.kind = 'voucher')
    left join public.customers c on c.id = l.customer_id
   where i.id = p_invoice_id
     -- Every time the VIP invoice stood paid counts, also before it was
     -- cancelled or refunded and then reopened (the owner, 21 Oct 2026, R6-7).
     -- Not a time it stood cancelled, or with every VIP ticket on it refunded
     -- in full (436's vip_refund_vouchers row saying so): its VIP vouchers were
     -- taken back then, so a discount given after that and before the next
     -- reopening is not theirs (one given in the same moment as it still
     -- counts; the review of 21 Oct 2026). One VIP of two refunded leaves the
     -- other's time running.
     and not exists (select 1 from public.audit_logs a
                       where a.record_id = i.id and a.table_name = 'invoices' and a.created_at < l.created_at
                         and (a.action = 'invoice_cancelled'
                              or (a.action = 'vip_refund_vouchers'
                                  and (a.new_data->>'tickets_refunded')::integer >= (a.new_data->>'tickets')::integer))
                         and not exists (select 1 from public.audit_logs o
                                          where o.record_id = i.id and o.table_name = 'invoices' and o.action = 'invoice_reopened'
                                            and o.created_at >= a.created_at and o.created_at <= l.created_at))
     and (l.customer_id = i.customer_id
          or l.customer_id in (select v.customer_id from public.invoice_benefit_values b
                                 join public.event_vip_invoice_items(i.id) x on x.invoice_item_id = b.invoice_item_id and x.kind = 'voucher'
                                 join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
                                where b.invoice_id = i.id))
     and (l.discount_voucher_id = vo.id
          or exists (select 1 from public.invoice_items li where li.invoice_id = l.id and li.line_voucher_id = vo.id))
   order by l.created_at, l.invoice_no, vo.name
   limit 1
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_take_back(p_invoice_id uuid, p_lines jsonb, p_all boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare x record; r record; v_lines jsonb := case when jsonb_typeof(p_lines) = 'array' then p_lines else '[]'::jsonb end;
  v_t int := 0; v_f int := 0; v_target int; v_taken int; v_left int; v_n int; v_rows jsonb; v_out jsonb := '[]';
  v_used jsonb; v_user text;
begin
  for x in select it.id, greatest(coalesce(it.quantity, 1), 1) as qty, coalesce(public.invoice_discounted_line_value(it.id), 0) as val
             from public.event_vip_invoice_items(p_invoice_id) t
             join public.invoice_items it on it.id = t.invoice_item_id
            where t.kind = 'ticket'
            order by it.id loop
    v_t := v_t + x.qty;
    if x.val > 0 then
      v_f := v_f + least(x.qty, greatest(floor((public.event_ticket_line_refunded(x.id)
               + coalesce((select sum(coalesce((l->>'amount')::numeric, 0)) from jsonb_array_elements(v_lines) l
                            where l->>'invoice_item_id' = x.id::text), 0) + 0.005) * x.qty / x.val), 0))::int;
    end if;
  end loop;
  if coalesce(p_all, false) then v_f := v_t; end if;
  for x in select it.id, it.voucher_id, vo.name, greatest(coalesce(it.quantity, 1), 1) as qty
             from public.event_vip_invoice_items(p_invoice_id) t
             join public.invoice_items it on it.id = t.invoice_item_id
             join public.vouchers vo on vo.id = it.voucher_id
            where t.kind = 'voucher'
            order by vo.name, it.id loop
    v_target := case when v_t > 0 then (v_f * x.qty) / v_t else 0 end;
    select coalesce(sum(b.cancelled_unused_value), 0)::int into v_taken
      from public.invoice_benefit_values b
     where b.invoice_id = p_invoice_id and b.invoice_item_id = x.id and b.reward_voucher_id is not null;
    v_left := greatest(v_target - v_taken, 0);
    v_rows := '[]';
    for r in select v.id, v.quantity, v.customer_id, c.full_name
               from public.customer_reward_vouchers v
               left join public.customers c on c.id = v.customer_id
              where v.status = 'held' and v.quantity > 0
                and v.id in (select b.reward_voucher_id from public.invoice_benefit_values b
                              where b.invoice_id = p_invoice_id and b.invoice_item_id = x.id)
              order by v.id loop
      exit when v_left <= 0;
      v_n := least(r.quantity, v_left);
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('reward_voucher_id', r.id, 'customer_id', r.customer_id,
                  'holder', r.full_name, 'held', r.quantity, 'take', v_n));
      v_left := v_left - v_n;
    end loop;
    select coalesce(jsonb_agg(u.id order by u.id), '[]'::jsonb), (array_agg(u.full_name order by u.id))[1] into v_used, v_user
      from (select distinct v.id, c.full_name
              from public.invoice_benefit_values b
              join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
              left join public.customers c on c.id = v.customer_id
             where b.invoice_id = p_invoice_id and b.invoice_item_id = x.id
               and (case when v.status = 'held' then v.quantity else 0 end) + b.cancelled_unused_value
                   + coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                                where t.source_benefit_id = b.id and t.replacement_benefit_id is not null), 0)
                   + coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                                where q.benefit_id = b.id and q.applied_at is not null), 0) < b.granted_value) u;
    v_out := v_out || jsonb_build_array(jsonb_build_object('invoice_item_id', x.id, 'voucher_id', x.voucher_id, 'voucher', x.name,
               'quantity', x.qty, 'target', v_target, 'taken', v_taken, 'rows', v_rows, 'short', v_left,
               'used', v_used, 'user', v_user));
  end loop;
  return jsonb_build_object('tickets', v_t, 'full', v_f, 'lines', v_out);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_refund_plan(p_invoice_id uuid, p_action text, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i public.invoices%rowtype; x jsonb; r jsonb; v_refund numeric; v_lines jsonb; v_later jsonb; v_tb jsonb; v_now int;
  v_later_ov jsonb; v_take int; v_held int;
  v_sum jsonb := '[]'; v_ben jsonb := '[]'; v_used text[] := '{}'; v_back text[] := '{}'; v_holder text;
begin
  if p_action is null or p_action not in ('cancel', 'refund_full', 'refund_partial') then return '{}'::jsonb; end if;
  select * into i from public.invoices where id = p_invoice_id;
  if not found or i.deleted_at is not null or i.status::text in ('cancelled', 'refunded')
     or not exists (select 1 from public.event_vip_invoice_items(i.id) x where x.kind = 'voucher') then
    return '{}'::jsonb; end if;
  v_lines := case when jsonb_typeof(p_lines) = 'array' then p_lines else '[]'::jsonb end;
  select coalesce(sum(coalesce((l->>'amount')::numeric, 0)), 0) into v_refund from jsonb_array_elements(v_lines) l;
  -- Once this is recorded: the VIP tickets refunded in full (the invoice
  -- owing nothing counts every one), against those refunded in full now.
  -- The trigger below reads the same.
  v_now := (public.event_vip_take_back(i.id, '[]', false)->>'full')::int;
  v_tb := public.event_vip_take_back(i.id, v_lines, v_refund > 0.005 and public.invoice_charge_total(i.id) - v_refund <= 0);
  if (v_tb->>'full')::int <= v_now then return '{}'::jsonb; end if;
  -- A VIP voucher kind given as a discount on a later invoice (round 3): not
  -- refunded in full automatically. The owner, 21 Oct 2026: an Owner or
  -- Manager may allow it, giving a reason (this override; 417's approval
  -- asks them for it and records it), or refund less; staff cannot.
  v_later := public.event_vip_used_later(i.id);
  v_later_ov := case when v_later is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later',
      'invoice_no', v_later->>'invoice_no',
      'message', 'A discount with the ' || (v_later->>'voucher') || ' was given' || coalesce(' to ' || (v_later->>'holder'), '')
        || ' on ' || (v_later->>'invoice_no') || ', an invoice made after this VIP invoice (' || i.invoice_no || '), so the VIP ticket '
        || 'is not refunded in full automatically. An Owner or Manager may allow the full refund, giving a reason (it is '
        || 'recorded); or refunds less, as a part refund in the Finance panel, less than the ticket (the customer then stays '
        || 'VIP and keeps the unused VIP vouchers).')) end;
  if p_action = 'cancel' then return jsonb_build_object('overrides', v_later_ov, 'blockers', '[]'::jsonb); end if;
  for x in select * from jsonb_array_elements(v_tb->'lines') loop
    for r in select * from jsonb_array_elements(x->'rows') loop
      v_take := (r->>'take')::int; v_held := (r->>'held')::int;
      if not (x->>'voucher') = any (v_back) then v_back := v_back || (x->>'voucher'); end if;
      v_sum := v_sum || to_jsonb(case when v_take = v_held and v_held = 1 then 'Take back the unused '
                                      when v_take = v_held then 'Take back the ' || v_held || ' unused '
                                      else 'Take back ' || v_take || ' of the ' || v_held || ' unused ' end
                                 || (x->>'voucher') || ' that came with VIP' || coalesce(' from ' || (r->>'holder'), '') || '.');
      v_ben := v_ben || jsonb_build_array(jsonb_build_object('kind', 'voucher', 'holder', r->>'holder', 'holder_id', r->>'customer_id',
                 'credit_removed', null, 'units_revoked', v_take, 'accounting_value', 0,
                 'line', (x->>'voucher') || ', included with VIP'));
    end loop;
    -- Used: a unit it should take back is no longer held.
    if (x->>'short')::int > 0 then
      v_used := v_used || (x->>'voucher');
      v_holder := coalesce(v_holder, x->>'user');
    end if;
  end loop;
  return jsonb_build_object('summary', v_sum, 'benefits', v_ben, 'overrides', v_later_ov ||
    case when cardinality(v_used) = 0 then '[]'::jsonb else jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used',
      'message', coalesce(v_holder, 'This customer') || ' has already used the ' || array_to_string(v_used, ' and the ')
        || ' that came with VIP (' || i.invoice_no || '). '
        || case when cardinality(v_used) = 1 then 'It stays' else 'They stay' end || ' recorded as used and cannot be taken back'
        || case when cardinality(v_back) > 0 then '; only the unused ' || array_to_string(v_back, ' and the ')
                  || case when cardinality(v_back) = 1 then ' is' else ' are' end || ' taken back with this refund'
                else '' end
        || '. Give a reason to go ahead with this refund, or refund less.')) end,
    'blockers', '[]'::jsonb);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.trg_event_vip_refund_vouchers()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare x jsonb; r jsonb; v public.customer_reward_vouchers%rowtype; v_back jsonb := '[]'; v_used jsonb := '[]'; v_reason text;
  v_later jsonb; v_tb jsonb; v_stmt jsonb; v_full_now boolean := false; v_short boolean := false; v_take int;
  v_req uuid; v_by uuid; v_why text;
begin
  if new.deleted_at is not null
     or not exists (select 1 from public.event_vip_invoice_items(new.id) x where x.kind = 'voucher') then
    return null; end if;
  -- Money paid back by this statement (the call being run): does it pay a
  -- VIP ticket back in full?
  if coalesce(new.paid_amount, 0) < coalesce(old.paid_amount, 0)
     and exists (select 1 from public.invoice_refunds rf where rf.invoice_id = new.id and rf.created_at >= statement_timestamp()) then
    if new.status::text = 'cancelled' then
      v_full_now := coalesce(new.paid_amount, 0) <= 0.005
        and exists (select 1 from public.invoice_benefit_values b
                      join public.event_vip_invoice_items(new.id) xi on xi.invoice_item_id = b.invoice_item_id and xi.kind = 'voucher'
                     where b.invoice_id = new.id);
    else
      select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id', l.value->>'invoice_item_id',
                                                   'amount', -coalesce((l.value->>'amount')::numeric, 0))), '[]'::jsonb)
        into v_stmt
        from public.invoice_refunds rf
        cross join lateral jsonb_array_elements(coalesce(rf.outcome->'lines', '[]')) l
       where rf.invoice_id = new.id and rf.created_at >= statement_timestamp()
         and not coalesce((l.value->>'overpayment')::boolean, false);
      v_full_now := (public.event_vip_take_back(new.id, '[]', new.status::text = 'refunded')->>'full')::int
                    > (public.event_vip_take_back(new.id, v_stmt, old.status::text = 'refunded')->>'full')::int;
    end if;
  end if;
  -- Round 3: a VIP voucher kind given as a discount on a later invoice. The
  -- owner, 21 Oct 2026: refused unless an Owner or Manager allowed it with a
  -- reason: the approval of the guided Refund or Cancel being run (417's
  -- resolve_invoice_action_v2, an Owner's or Manager's alone, names it and
  -- refuses one without the reason its plan's override
  -- vip_voucher_used_later asks for; the refund it records carries its id,
  -- and the request may read approved already, as the refund completes it),
  -- or, once such a Cancel was approved, the money it owes paid back. A
  -- discount given after a cancellation is not counted (event_vip_used_later).
  if v_full_now then
    v_later := public.event_vip_used_later(new.id);
    if v_later is not null then
      select a.id, case when x.in_resolve then auth.uid() else a.approved_by end,
             (select nullif(btrim(q->>'reason'), '') from jsonb_array_elements(
                case when jsonb_typeof(a.payload->'overrides') = 'array' then a.payload->'overrides' else '[]'::jsonb end) q
               where q->>'code' = 'vip_voucher_used_later' limit 1)
        into v_req, v_by, v_why
        from public.approval_requests a
        cross join lateral (
          select a.id::text = coalesce(nullif(current_setting('invoice.therapy_reviewed', true), ''), '-')
                 and a.status::text in ('pending', 'approved') and public.is_owner_or_manager()
                 and exists (select 1 from public.invoice_refunds rf
                              where rf.invoice_id = new.id and rf.request_id = a.id and rf.created_at >= statement_timestamp())
                 as in_resolve) x
       where a.related_record_id = new.id and a.request_type in ('invoice_cancel', 'invoice_refund')
         and (x.in_resolve
              or (new.status::text = 'cancelled' and a.status::text = 'approved' and a.payload->>'action' = 'cancel'
                  and a.approved_at >= coalesce(new.reopened_at, new.created_at)
                  and exists (select 1 from jsonb_array_elements(
                                case when jsonb_typeof(a.payload->'overrides') = 'array' then a.payload->'overrides' else '[]'::jsonb end) q
                               where q->>'code' = 'vip_voucher_used_later' and nullif(btrim(coalesce(q->>'reason', '')), '') is not null)))
       order by x.in_resolve desc, a.created_at desc limit 1;
      if v_req is null and new.status::text = 'cancelled' then
        raise exception 'A discount with the % was given% on %, an invoice made after the VIP invoice % and before it was cancelled, so the money it holds is not all paid back here: it was cancelled without an Owner''s or Manager''s override for that. Record a part refund, less than it holds; or an Owner or Manager reopens the invoice and cancels it again with the guided Cancel. Nothing was recorded.',
          v_later->>'voucher', coalesce(' to ' || (v_later->>'holder'), ''), v_later->>'invoice_no', new.invoice_no;
      elsif v_req is null then
        raise exception 'A discount with the % was given% on %, an invoice made after the VIP invoice %, so the VIP ticket is not refunded in full here. Use Refund in full on the invoice: an Owner or Manager can allow it there with a reason. Or record a part refund, less than the ticket (the customer stays VIP and keeps the unused VIP vouchers). Nothing was recorded.',
          v_later->>'voucher', coalesce(' to ' || (v_later->>'holder'), ''), v_later->>'invoice_no', new.invoice_no;
      end if;
      perform public.write_audit_ex('invoices', new.id, 'vip_refund_used_later_allowed', null,
        jsonb_build_object('request_id', v_req, 'allowed_by', v_by, 'reason', v_why, 'later_invoice_id', v_later->'invoice_id',
                           'later_invoice_no', v_later->'invoice_no', 'voucher', v_later->'voucher', 'holder', v_later->'holder'),
        'events', 'VIP refunded in full on an Owner''s or Manager''s override: a discount with the ' || (v_later->>'voucher')
          || ' was given on ' || (v_later->>'invoice_no') || coalesce(' (' || v_why || ')', ' (the reason is on the approved request)'),
        new.store_id);
    end if;
  end if;
  if new.status::text = 'cancelled' then return null; end if;
  -- A guided cancellation records its refund first (resolve_invoice_action_v2,
  -- which names its request here): the cancellation that follows at once
  -- takes them back itself, as it always has.
  if exists (select 1 from public.approval_requests a
              where a.id::text = coalesce(nullif(current_setting('invoice.therapy_reviewed', true), ''), '-')
                and a.related_record_id = new.id and a.payload->>'action' = 'cancel') then
    return null; end if;
  v_reason := 'VIP refunded in full · ' || coalesce(new.invoice_no, '');
  perform 1 from public.customer_reward_vouchers cv
   where cv.status = 'held'
     and cv.id in (select b.reward_voucher_id from public.invoice_benefit_values b
                     join public.event_vip_invoice_items(new.id) xi on xi.invoice_item_id = b.invoice_item_id and xi.kind = 'voucher'
                    where b.invoice_id = new.id)
   order by cv.id for update;
  -- What is due back now: the share of each VIP voucher line for the VIP
  -- tickets refunded in full, less what was taken back before (read before
  -- taking back, which moves what is held into what was taken back).
  v_tb := public.event_vip_take_back(new.id, '[]', new.status::text = 'refunded');
  select coalesce(bool_or((l->>'short')::int > 0), false),
         coalesce((select jsonb_agg(distinct u.value) from jsonb_array_elements(v_tb->'lines') l2,
                     jsonb_array_elements(l2->'used') u where (l2->>'short')::int > 0), '[]'::jsonb)
    into v_short, v_used
    from jsonb_array_elements(v_tb->'lines') l;
  if v_full_now and v_short
     and not exists (select 1 from public.invoice_refunds rf
                       join public.approval_requests a on a.id = rf.request_id
                      where rf.invoice_id = new.id and rf.created_at >= statement_timestamp()
                        and a.related_record_id = new.id and a.payload->>'action' in ('refund_full', 'refund_partial')) then
    raise exception 'A voucher that came with VIP on % has already been used, so this refund is not recorded here. Use Refund in full on the invoice: it says which voucher first and asks for a reason.', new.invoice_no;
  end if;
  for x in select * from jsonb_array_elements(v_tb->'lines') loop
    for r in select * from jsonb_array_elements(x->'rows') loop
      select * into v from public.customer_reward_vouchers where id = (r->>'reward_voucher_id')::uuid;
      v_take := least((r->>'take')::int, v.quantity);
      continue when v.status is distinct from 'held' or v_take <= 0;
      update public.invoice_benefit_values set cancelled_unused_value = cancelled_unused_value + v_take where reward_voucher_id = v.id;
      if v_take >= v.quantity then
        update public.customer_reward_vouchers set status = 'revoked', notes = concat_ws(E'\n', notes, v_reason || ': taken back unused')
         where id = v.id;
      else
        update public.customer_reward_vouchers set quantity = quantity - v_take,
               notes = concat_ws(E'\n', notes, v_reason || ': ' || v_take || ' of ' || v.quantity || ' taken back unused')
         where id = v.id;
      end if;
      if exists (select 1 from public.vouchers where id = v.voucher_id and qty_type = 'limited') then
        update public.voucher_store_stock set current_qty = current_qty + v_take where store_id = v.store_id and voucher_id = v.voucher_id;
      end if;
      perform public.write_audit_ex('customer_reward_vouchers', v.id, 'vip_voucher_taken_back',
        jsonb_build_object('status', v.status, 'quantity', v.quantity, 'voucher_id', v.voucher_id, 'customer_id', v.customer_id),
        jsonb_build_object('status', case when v_take >= v.quantity then 'revoked' else 'held' end, 'units_taken_back', v_take,
                           'invoice_id', new.id, 'invoice_no', new.invoice_no), 'events', v_reason, new.store_id);
      v_back := v_back || jsonb_build_array(v.id);
    end loop;
  end loop;
  if jsonb_array_length(v_back) > 0 or (v_full_now and jsonb_array_length(v_used) > 0) then
    -- (the invoice's VIP tickets and those refunded in full now: once all are, the VIP invoice
    -- stands refunded until it is reopened; event_vip_used_later reads it, R6-7)
    perform public.write_audit_ex('invoices', new.id, 'vip_refund_vouchers', null,
      jsonb_build_object('taken_back', v_back, 'used_kept', v_used, 'tickets', v_tb->'tickets', 'tickets_refunded', v_tb->'full'),
      'events', v_reason, new.store_id);
  end if;
  return null;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.trg_event_web_referral_check_decided()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; r public.event_registrations%rowtype; c public.customers%rowtype;
  v_inv uuid; v_ok boolean;
begin
  -- 436 (the owner, 20 Oct 2026, ~20:15; 21 Oct 2026): someone else on the
  -- affiliate's own phone or email inbox, or on another customer's phone
  -- (Q19), whom staff made a customer through her link (check_waiting,
  -- event_web_new_customer) becomes her referral only once an
  -- Owner or Manager checks them as a different person (425's
  -- decide_referral_signup_check, unchanged), dated when they were made a
  -- customer (as 425 dates a sign-up that waits for its check). The
  -- commission on their website VIP comes then: the engine, once, on each
  -- VIP invoice of theirs paid in full that has earned none yet, dated the
  -- day of the check in Singapore (the owner, 21 Oct 2026, R6-5: a month
  -- already paid out stays as it was); a VIP paid later earns as any
  -- referral's purchase. Checked as the same person:
  -- never referred, nothing earned. An older record merged into the one made
  -- for them before the check makes them an existing customer (the owner's
  -- D): not referred through the link; that record's own referral is the
  -- Owner's to carry over (merge_customer_records does not).
  for p in select * from public.event_registration_people
            where customer_id = new.customer_id and referral_outcome = 'check_waiting' and not is_test
            order by created_at, id for update loop
    select * into r from public.event_registrations where id = p.registration_ref;
    if new.status = 'different_person' then
      select * into c from public.customers where id = new.customer_id for update;
      v_ok := c.deleted_at is null and c.referred_by is null
              and new.referrer_customer_id is not distinct from r.referrer_customer_id
              and exists (select 1 from public.customers a where a.id = r.referrer_customer_id and a.deleted_at is null)
              and not exists (select 1 from public.audit_logs l
                                join public.customers m on m.id = case when l.new_data->>'merged_from' ~ '^[0-9a-f-]{36}$'
                                                                       then (l.new_data->>'merged_from')::uuid end
                               where l.record_id = c.id and l.action = 'customers_merged' and m.created_at < c.created_at)
              and not exists (with recursive up(id, n) as (
                                select r.referrer_customer_id, 0
                                union all
                                select u.referred_by, up.n + 1 from public.customers u join up on u.id = up.id
                                 where u.referred_by is not null and up.n < 100)
                              select 1 from up where up.id = c.id);
      if v_ok then
        update public.customers
           set referred_by = r.referrer_customer_id, referral_source = 'affiliate_link', referral_code_used = r.referral_code,
               referred_at = c.created_at
         where id = c.id;
        perform public.write_audit_ex('customers', c.id, 'referral_registered', null,
          jsonb_build_object('referred_by', r.referrer_customer_id, 'referral_code', r.referral_code, 'source', 'event_website',
                             'registration_id', r.registration_id, 'check_id', new.id, 'checked', new.status),
          'affiliate', 'Referred once an Owner or Manager checked them as a different person',
          (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
      end if;
      if (select cc.referred_by from public.customers cc where cc.id = new.customer_id) = r.referrer_customer_id then
        for v_inv in select i.id from public.event_vip_order_people op
                       join public.event_vip_orders o on o.id = op.order_ref
                       join public.invoices i on i.id = op.invoice_id
                      where op.person_id = p.id and o.status = 'invoiced' and i.customer_id = new.customer_id
                        and i.deleted_at is null and i.status::text = 'paid'
                        and not exists (select 1 from public.commissions cm where cm.invoice_id = i.id)
                      order by i.created_at, i.id loop
          perform public.earn_invoice_commission(v_inv);
          -- A part refund recorded while the check waited: the engine's own
          -- refund step after earning (as reconcile_invoice_commissions runs
          -- it), on this invoice's rows, all just made.
          perform public.adjust_invoice_line_commission_refunds(v_inv, null);
          -- Dated the day an Owner or Manager confirmed (Singapore), not the
          -- day the VIP was paid (the owner, 21 Oct 2026, R6-5): all of this
          -- invoice's rows were made just now (it had none).
          update public.commissions set invoice_paid_date = public.sg_today() where invoice_id = v_inv;
        end loop;
      end if;
      update public.event_registration_people set referral_outcome = 'check_confirmed', updated_at = now() where id = p.id;
    else
      update public.event_registration_people set referral_outcome = 'check_same_person', updated_at = now() where id = p.id;
    end if;
  end loop;
  return null;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.trg_event_vip_used_later_reason()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_why text;
begin
  -- 436 (the owner, 21 Oct 2026, answer 3; the review of 21 Oct 2026): the
  -- reason an Owner or Manager gave for allowing a VIP's full refund though a
  -- VIP voucher kind was given on a later invoice. 417's approval stores it
  -- on the request only after its refund ran, so the VIP invoice's
  -- vip_refund_used_later_allowed row (written during that refund) names
  -- the request without it (the refund may already have marked the request
  -- approved); this adds the reason to the VIP invoice's audit log, once, as
  -- the approved request's overrides are stored.
  select nullif(btrim(q->>'reason'), '') into v_why
    from jsonb_array_elements(case when jsonb_typeof(new.payload->'overrides') = 'array'
                                   then new.payload->'overrides' else '[]'::jsonb end) q
   where q->>'code' = 'vip_voucher_used_later' and nullif(btrim(q->>'reason'), '') is not null
   limit 1;
  if v_why is null
     or not exists (select 1 from public.audit_logs a
                     where a.record_id = new.related_record_id and a.table_name = 'invoices'
                       and a.action = 'vip_refund_used_later_allowed'
                       and a.new_data->>'request_id' = new.id::text and a.new_data->>'reason' is null)
     or exists (select 1 from public.audit_logs a
                 where a.record_id = new.related_record_id and a.table_name = 'invoices'
                   and a.action = 'vip_refund_used_later_reason' and a.new_data->>'request_id' = new.id::text) then
    return null; end if;
  perform public.write_audit_ex('invoices', new.related_record_id, 'vip_refund_used_later_reason', null,
    jsonb_build_object('request_id', new.id, 'reason', v_why, 'allowed_by', new.approved_by),
    'events', 'The reason given for refunding the VIP in full on an Owner''s or Manager''s override: ' || v_why,
    (select i.store_id from public.invoices i where i.id = new.related_record_id));
  return null;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_talk_titles(p_event_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436 (round 7): the talks offered (Q4): the Website tab's titles once saved ('{}': none),
  -- else the suggested list (general wellness wording, no medical claims; the owner, 21 Oct
  -- 2026). The contract's SUGGESTED_TALK_TITLES is the same list (a test compares them).
  select coalesce((select s.talk_titles from public.event_web_settings s where s.event_id = p_event_id),
                  array['Sleep better, stress less', 'Healthy joints, back and muscles',
                        'Good circulation for everyday energy', 'Caring for your eyes',
                        'Ageing well and staying active', 'Eating well for long-term health',
                        'Women''s wellness']::text[])
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_planning_anchor(p_guest_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436 (round 7): whose answers a guest record shows. A website person's are on their first
  -- (free) record, so they follow them to their VIP record and back; any other guest's are on
  -- their own record.
  select coalesce((select p.free_guest_id from public.event_registration_people p
                    where p.vip_guest_id = p_guest_id and p.free_guest_id is not null
                    order by p.created_at limit 1), p_guest_id)
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_planning_days(p_anchor uuid)
 RETURNS date[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436 (round 7): the days the answers are about: a website person's VIP record's while it
  -- stands (every day), else their free record's; any other guest's own days.
  select coalesce(array_agg(gd.day order by gd.day), '{}'::date[])
    from public.event_guest_days gd
   where gd.guest_id = coalesce((select vg.id from public.event_registration_people p
                                   join public.event_guests vg on vg.id = p.vip_guest_id and vg.status = 'registered'
                                  where p.free_guest_id = p_anchor order by p.created_at limit 1), p_anchor)
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_planning_record(p_guest_id uuid, p_person_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436 (round 7): a guest's answers as the contract's PlanningRecord, with plan_id and
  -- staff_id for the Event page (callers strip them for the website), or null while none.
  -- By the website person when one is given, else by the guest's record (each by its key).
  select jsonb_build_object('plan_id', a.id, 'staff_id', a.staff_id, 'version', a.version,
           'answers', jsonb_build_object('food', a.food, 'food_other', a.food_other, 'allergy', a.allergy,
             'allergy_details', a.allergy_details, 'timing', a.timing, 'talks', to_jsonb(a.talks),
             'access', to_jsonb(a.access), 'access_other', a.access_other, 'heard_from', a.heard_from,
             'heard_from_other', a.heard_from_other, 'question', a.question),
           'updated_at', a.updated_at, 'updated_by', a.answered_by)
    from public.event_planning_answers a
   where a.id = coalesce((select a1.id from public.event_planning_answers a1
                           where p_person_id is not null and a1.person_id = p_person_id),
                         (select a2.id from public.event_planning_answers a2
                           where p_guest_id is not null and a2.guest_id = public.event_planning_anchor(p_guest_id)))
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_planning_check(p_event_id uuid, p_days date[], p_answers jsonb, p_saved_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e public.events%rowtype; sv public.event_planning_answers%rowtype; v_titles text[]; v_problems jsonb := '[]';
  v_food text; v_food_other text; v_allergy text; v_allergy_details text; v_access text[] := '{}'; v_access_other text;
  v_heard text; v_heard_other text; v_question text; v_talks text[] := '{}'; v_timing jsonb := '[]'; v_seen date[] := '{}';
  t jsonb; v_day date; v_whole boolean; v_arrive time; v_leave time; v_x text; v_t text; v_hours text; v_match text;
begin
  -- 436 (round 7): one guest's answers checked and put in one form (the owner, 21 Oct 2026:
  -- Q1-Q7, A2), the website's and staff's alike. Every question is optional; a key left out is
  -- not answered. One-line texts are trimmed, their inner whitespace made one space; the
  -- question keeps its line breaks. A text that goes with a choice is kept only with it (Other,
  -- Yes), else dropped. A part of the day from the daily start to the daily end is the whole
  -- day. Days by date, talks in the list's order, spelled as the list spells them. A day's
  -- timing or a talk already kept for this guest passes again as it is, so a later change of
  -- the hours or of the titles never blocks a save. Times are "around": never checked against
  -- the clock today.
  if jsonb_typeof(p_answers) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'The answers are missing'; end if;
  select * into e from public.events where id = p_event_id;
  select * into sv from public.event_planning_answers where id = p_saved_id;
  v_titles := public.event_web_talk_titles(p_event_id);
  v_hours := to_char(e.daily_start, 'FMHH12:MI am') || ' and ' || to_char(e.daily_end, 'FMHH12:MI am');

  -- Q1 food (and its Other text)
  v_x := nullif(btrim(coalesce(p_answers->>'food', '')), '');
  if v_x is not null and v_x not in ('no_preference', 'vegetarian', 'vegan', 'halal', 'no_beef', 'other') then
    v_problems := v_problems || jsonb_build_object('field', 'food', 'code', 'bad_choice', 'message', 'Choose one of the food choices.');
  else
    v_food := v_x;
  end if;
  if v_food = 'other' then
    v_food_other := nullif(btrim(regexp_replace(coalesce(p_answers->>'food_other', ''), '\s+', ' ', 'g')), '');
    if char_length(v_food_other) > 60 then
      v_problems := v_problems || jsonb_build_object('field', 'food_other', 'code', 'too_long',
        'message', 'The other food preference is at most 60 characters.');
    end if;
  end if;

  -- Q2 allergies (and which)
  v_x := nullif(btrim(coalesce(p_answers->>'allergy', '')), '');
  if v_x is not null and v_x not in ('no', 'yes') then
    v_problems := v_problems || jsonb_build_object('field', 'allergy', 'code', 'bad_choice', 'message', 'Choose No or Yes for allergies.');
  else
    v_allergy := v_x;
  end if;
  if v_allergy = 'yes' then
    v_allergy_details := nullif(btrim(regexp_replace(coalesce(p_answers->>'allergy_details', ''), '\s+', ' ', 'g')), '');
    if char_length(v_allergy_details) > 120 then
      v_problems := v_problems || jsonb_build_object('field', 'allergy_details', 'code', 'too_long',
        'message', 'The allergies are at most 120 characters.');
    end if;
  end if;

  -- Q3 timing, one per day the guest is coming
  if jsonb_typeof(p_answers->'timing') not in ('array', 'null') then
    v_problems := v_problems || jsonb_build_object('field', 'timing', 'code', 'bad_choice', 'message', 'The timing is a list of days.');
  elsif jsonb_typeof(p_answers->'timing') = 'array' then
    for t in select y.value from jsonb_array_elements(p_answers->'timing') y loop
      begin
        v_day := (t->>'date')::date;
        v_whole := coalesce((t->>'whole_day')::boolean, true);
        v_arrive := case when not v_whole then (t->>'arrive')::time end;
        v_leave := case when not v_whole then (t->>'leave')::time end;
      exception when others then
        v_problems := v_problems || jsonb_build_object('field', 'timing', 'code', 'outside_hours',
          'message', format('Choose arriving and leaving times between %s.', coalesce(v_hours, 'the event''s hours')));
        continue;
      end;
      if v_day is null then
        v_problems := v_problems || jsonb_build_object('field', 'timing', 'code', 'bad_choice', 'message', 'Each day''s timing needs its date.');
      elsif v_day = any (v_seen) then
        v_problems := v_problems || jsonb_build_object('field', 'timing', 'code', 'bad_choice', 'message', 'One answer per day.');
      elsif not coalesce(v_day = any (p_days), false) then
        v_problems := v_problems || jsonb_build_object('field', 'timing', 'code', 'day_not_chosen',
          'message', format('%s is not one of the days they are coming.', to_char(v_day, 'FMDy DD Mon')));
      elsif v_whole or (v_arrive = e.daily_start and v_leave = e.daily_end) then
        v_timing := v_timing || jsonb_build_object('date', v_day, 'whole_day', true, 'arrive', null, 'leave', null);
        v_seen := v_seen || v_day;
      elsif v_arrive is not null and v_leave is not null and sv.id is not null
            and sv.timing @> jsonb_build_array(jsonb_build_object('date', v_day, 'whole_day', false,
                  'arrive', to_char(v_arrive, 'HH24:MI'), 'leave', to_char(v_leave, 'HH24:MI'))) then
        -- kept already as it is: passes even if the hours changed since
        v_timing := v_timing || jsonb_build_object('date', v_day, 'whole_day', false,
                      'arrive', to_char(v_arrive, 'HH24:MI'), 'leave', to_char(v_leave, 'HH24:MI'));
        v_seen := v_seen || v_day;
      elsif v_arrive is null or v_leave is null
            or e.daily_start is null or e.daily_end is null
            or v_leave <= v_arrive or v_arrive < e.daily_start or v_leave > e.daily_end
            or v_arrive > e.daily_end - interval '30 minutes' or v_leave < e.daily_start + interval '30 minutes'
            or extract(epoch from v_arrive - e.daily_start)::integer % 1800 <> 0
            or (v_leave <> e.daily_end and extract(epoch from v_leave - e.daily_start)::integer % 1800 <> 0) then
        v_problems := v_problems || jsonb_build_object('field', 'timing', 'code', 'outside_hours',
          'message', case when e.daily_start is null or e.daily_end is null
                          then 'Part-day times cannot be kept yet: the event has no daily hours (Edit event).'
                          else format('Choose arriving and leaving times between %s, on the half hour, leaving after arriving.', v_hours) end);
      else
        v_timing := v_timing || jsonb_build_object('date', v_day, 'whole_day', false,
                      'arrive', to_char(v_arrive, 'HH24:MI'), 'leave', to_char(v_leave, 'HH24:MI'));
        v_seen := v_seen || v_day;
      end if;
    end loop;
    v_timing := (select coalesce(jsonb_agg(x.value order by x.value->>'date'), '[]'::jsonb) from jsonb_array_elements(v_timing) x);
  end if;

  -- Q4 talks: the event's titles now, or one already kept for this guest
  if jsonb_typeof(p_answers->'talks') not in ('array', 'null') then
    v_problems := v_problems || jsonb_build_object('field', 'talks', 'code', 'bad_choice', 'message', 'The talks are a list.');
  elsif jsonb_typeof(p_answers->'talks') = 'array' then
    for v_x in select y.value #>> '{}' from jsonb_array_elements(p_answers->'talks') y loop
      v_t := nullif(btrim(regexp_replace(coalesce(v_x, ''), '\s+', ' ', 'g')), '');
      continue when v_t is null;
      v_match := (select z from unnest(v_titles) z where lower(z) = lower(v_t) limit 1);
      if v_match is null then
        v_match := (select z from unnest(sv.talks) z where lower(z) = lower(v_t) limit 1);
      end if;
      if v_match is null then
        v_problems := v_problems || jsonb_build_object('field', 'talks', 'code', 'talk_not_offered',
          'message', format('"%s" is not one of the talks now.', v_t));
      elsif not (v_match = any (v_talks)) then
        v_talks := v_talks || v_match;
      end if;
    end loop;
    if cardinality(v_talks) > 20 then
      v_problems := v_problems || jsonb_build_object('field', 'talks', 'code', 'bad_choice', 'message', 'At most 20 talks.');
    end if;
    v_talks := array(select y from unnest(v_talks) y order by array_position(v_titles, y) nulls last, lower(y));
  end if;

  -- Q5 what to prepare (in the list's order, each once) and other needs
  if jsonb_typeof(p_answers->'access') not in ('array', 'null') then
    v_problems := v_problems || jsonb_build_object('field', 'access', 'code', 'bad_choice', 'message', 'Choose from the listed needs.');
  elsif jsonb_typeof(p_answers->'access') = 'array' then
    if exists (select 1 from jsonb_array_elements(p_answers->'access') y
                where jsonb_typeof(y.value) <> 'string' or y.value #>> '{}' not in ('wheelchair', 'walking_help', 'front_seat')) then
      v_problems := v_problems || jsonb_build_object('field', 'access', 'code', 'bad_choice', 'message', 'Choose from the listed needs.');
    else
      v_access := array(select u.c from unnest(array['wheelchair', 'walking_help', 'front_seat']) with ordinality u(c, n)
                         where p_answers->'access' ? u.c order by u.n);
    end if;
  end if;
  v_access_other := nullif(btrim(regexp_replace(coalesce(p_answers->>'access_other', ''), '\s+', ' ', 'g')), '');
  if char_length(v_access_other) > 120 then
    v_problems := v_problems || jsonb_build_object('field', 'access_other', 'code', 'too_long',
      'message', 'The other needs are at most 120 characters.');
  end if;

  -- Q6 how they heard (and its Other text)
  v_x := nullif(btrim(coalesce(p_answers->>'heard_from', '')), '');
  if v_x is not null and v_x not in ('tiktok', 'facebook', 'instagram', 'google', 'whatsapp', 'friend_family', 'staff', 'email', 'other') then
    v_problems := v_problems || jsonb_build_object('field', 'heard_from', 'code', 'bad_choice',
      'message', 'Choose one of the listed answers for how they heard.');
  else
    v_heard := v_x;
  end if;
  if v_heard = 'other' then
    v_heard_other := nullif(btrim(regexp_replace(coalesce(p_answers->>'heard_from_other', ''), '\s+', ' ', 'g')), '');
    if char_length(v_heard_other) > 60 then
      v_problems := v_problems || jsonb_build_object('field', 'heard_from_other', 'code', 'too_long',
        'message', 'How they heard is at most 60 characters.');
    end if;
  end if;

  -- Q7 a question for the speakers (its line breaks kept)
  v_question := nullif(btrim(replace(replace(coalesce(p_answers->>'question', ''), E'\r\n', E'\n'), E'\r', E'\n'), E' \t\n'), '');
  if char_length(v_question) > 300 then
    v_problems := v_problems || jsonb_build_object('field', 'question', 'code', 'too_long', 'message', 'The question is at most 300 characters.');
  end if;

  return jsonb_build_object('problems', v_problems, 'answers', jsonb_build_object('food', v_food, 'food_other', v_food_other,
    'allergy', v_allergy, 'allergy_details', v_allergy_details, 'timing', v_timing, 'talks', to_jsonb(v_talks),
    'access', to_jsonb(v_access), 'access_other', v_access_other, 'heard_from', v_heard, 'heard_from_other', v_heard_other,
    'question', v_question));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_planning_write(p_event_id uuid, p_guest_id uuid, p_person_id uuid, p_answers jsonb, p_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.event_planning_answers%rowtype; n public.event_planning_answers%rowtype; v_old jsonb; v_new jsonb;
  v_texts constant text[] := array['food_other', 'allergy_details', 'access_other', 'heard_from_other', 'question'];
begin
  -- 436 (round 7): the website's planning_answers and the Event page's staff edit write here,
  -- with p_answers in event_planning_check's form. A version per change; every change audited
  -- (staff: who, their note, what was there before; the website: as the website). The audit
  -- keeps the choices but not the free texts, only which of them changed (texts_changed):
  -- Owners, Admins and Managers of any store read the audit log (the review of round 7, 21 Oct
  -- 2026). The same answers again change nothing.
  if p_by is null or p_by not in ('guest', 'staff') or p_guest_id is null then
    raise exception using errcode = '22023', message = 'event_planning_write: whose answers?'; end if;
  perform pg_advisory_xact_lock(hashtextextended('event-planning:' || p_guest_id::text, 0));
  select * into o from public.event_planning_answers where guest_id = p_guest_id for update;
  v_old := case when o.id is not null then public.event_planning_record(o.guest_id, null)->'answers' end;
  if o.id is not null and v_old = p_answers then
    return public.event_planning_record(o.guest_id, null) || jsonb_build_object('changed', false); end if;
  if o.id is null then
    insert into public.event_planning_answers (event_id, guest_id, person_id, food, food_other, allergy, allergy_details,
        timing, talks, access, access_other, heard_from, heard_from_other, question, version, answered_by, staff_id)
    values (p_event_id, p_guest_id, p_person_id, p_answers->>'food', p_answers->>'food_other', p_answers->>'allergy',
            p_answers->>'allergy_details', coalesce(p_answers->'timing', '[]'::jsonb),
            array(select u.x from jsonb_array_elements_text(coalesce(p_answers->'talks', '[]'::jsonb)) with ordinality u(x, n) order by u.n),
            array(select u.x from jsonb_array_elements_text(coalesce(p_answers->'access', '[]'::jsonb)) with ordinality u(x, n) order by u.n),
            p_answers->>'access_other', p_answers->>'heard_from', p_answers->>'heard_from_other', p_answers->>'question',
            1, p_by, case when p_by = 'staff' then auth.uid() end)
    returning * into n;
  else
    update public.event_planning_answers
       set event_id = p_event_id, person_id = coalesce(person_id, p_person_id),
           food = p_answers->>'food', food_other = p_answers->>'food_other', allergy = p_answers->>'allergy',
           allergy_details = p_answers->>'allergy_details', timing = coalesce(p_answers->'timing', '[]'::jsonb),
           talks = array(select u.x from jsonb_array_elements_text(coalesce(p_answers->'talks', '[]'::jsonb)) with ordinality u(x, n) order by u.n),
           access = array(select u.x from jsonb_array_elements_text(coalesce(p_answers->'access', '[]'::jsonb)) with ordinality u(x, n) order by u.n),
           access_other = p_answers->>'access_other', heard_from = p_answers->>'heard_from',
           heard_from_other = p_answers->>'heard_from_other', question = p_answers->>'question',
           version = o.version + 1, answered_by = p_by, staff_id = case when p_by = 'staff' then auth.uid() end,
           updated_at = now()
     where id = o.id
    returning * into n;
  end if;
  v_new := public.event_planning_record(n.guest_id, null);
  perform public.write_audit_ex('event_planning_answers', n.id,
    case when o.id is null then 'event_planning_added' else 'event_planning_changed' end,
    v_old - v_texts,
    ((v_new->'answers') - v_texts)
      || jsonb_build_object('texts_changed', to_jsonb(array(select t.k from unnest(v_texts) with ordinality t(k, o)
                                                            where (v_old->>t.k) is distinct from (v_new->'answers'->>t.k)
                                                            order by t.o)),
                            'event_id', n.event_id, 'guest_id', n.guest_id,
                            'person_id', n.person_id, 'version', n.version,
                            'source', case when p_by = 'staff' then 'staff' else 'website' end),
    'events', coalesce(nullif(btrim(coalesce(p_note, '')), ''), case when p_by = 'guest' then 'Answered on the website' end),
    (select s.store_id from public.event_web_settings s where s.event_id = p_event_id));
  return v_new || jsonb_build_object('changed', true);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_planning_closed(p_event_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436 (round 7): why planning answers are closed for the whole event, or null while they are
  -- open (A1, the owner 21 Oct 2026: until the event has ended, i.e. its last day's daily end in
  -- Singapore, the whole day when it has none, as event_web_open_state judges a day). The
  -- website switched Off or the event off sale do not close them.
  select case
           when e.id is null or e.deleted_at is not null then 'event_deleted'
           when x.last_day is null
             or (now() at time zone 'Asia/Singapore')
                >= x.last_day + coalesce(e.daily_end, time '00:00')
                   + case when e.daily_end is null then interval '1 day' else interval '0' end then 'ended'
         end
    from (select 1) one
    left join public.events e on e.id = p_event_id
    left join lateral (select max(d.day) as last_day from public.event_days d where d.event_id = p_event_id) x on true
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_planning_state(p_person_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; v text;
begin
  -- 436 (round 7): whether a person can answer now (A1): 'open' while they are registered,
  -- until the event has ended; else 'ended', 'event_deleted' or 'cancelled' (taken off the
  -- list, or closed by staff). A test key's person has no guest record: open unless closed.
  select * into p from public.event_registration_people where id = p_person_id;
  if not found then return 'cancelled'; end if;
  v := public.event_web_planning_closed(p.event_id);
  if v is not null then return v; end if;
  if p.match = 'closed'
     or (not p.is_test and not exists (select 1 from public.event_guests g
                                        where g.id in (p.free_guest_id, p.vip_guest_id) and g.status = 'registered')) then
    return 'cancelled'; end if;
  return 'open';
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_planning_answers(p_key_id uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  k public.event_web_keys%rowtype; e public.events%rowtype; v_test boolean; v_people jsonb := p_body->'planning'->'people';
  x jsonb; i integer; p public.event_registration_people%rowtype; v_state text; v_anchor uuid; v_cur jsonb; v_c jsonb;
  v_days date[]; v_reason text; v_w jsonb; v_rows jsonb := '[]'; v_closed text;
begin
  -- 436 (round 7, the owner 21 Oct 2026: A1): each person's planning answers, by their own VIP
  -- link token among this key's people (a test key's among its test people), each person on
  -- their own (one refused never stops another), in the order sent: person_not_found,
  -- person_cancelled (not registered any more), the first of day_not_chosen, outside_hours or
  -- talk_not_offered, the same answers as kept (saved, nothing written), changed_meanwhile (the
  -- version sent is not the one kept: what is kept is returned), test (what would be kept,
  -- nothing kept), saved. The whole call is closed once the event has ended or was deleted.
  select * into k from public.event_web_keys where id = p_key_id;
  select * into e from public.events where id = k.event_id;
  v_test := k.kind = 'test';
  if jsonb_typeof(v_people) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'event_web_planning_answers: malformed planning'; end if;
  if jsonb_array_length(v_people) not between 1 and 10
     or (select count(distinct y.value->>'upgrade_token') from jsonb_array_elements(v_people) y) <> jsonb_array_length(v_people)
     or exists (select 1 from jsonb_array_elements(v_people) y
                 where case when jsonb_typeof(y.value->'version') = 'number'
                            then (y.value->>'version')::numeric not between 0 and 1000000
                                 or (y.value->>'version')::numeric <> trunc((y.value->>'version')::numeric)
                            else true end) then
    raise exception using errcode = '22023', message = 'event_web_planning_answers: malformed planning'; end if;
  -- The event first (event_web_planning_closed, as the person's state): ended or deleted answers the whole call.
  v_closed := public.event_web_planning_closed(e.id);
  if v_closed is not null then
    return jsonb_build_object('ok', true, 'test', v_test, 'status', 'closed', 'reason', v_closed); end if;
  -- One person's answers at a time, people in a fixed order (event_planning_write takes the same lock).
  for p in select q.* from public.event_registration_people q
            where q.event_id = e.id and q.is_test = v_test
              and q.upgrade_token in (select y.value->>'upgrade_token' from jsonb_array_elements(v_people) y)
            order by coalesce(q.free_guest_id, q.vip_guest_id, q.id) loop
    perform pg_advisory_xact_lock(hashtextextended('event-planning:' || coalesce(p.free_guest_id, p.vip_guest_id, p.id)::text, 0));
  end loop;
  for x, i in select t.v, t.n::integer from jsonb_array_elements(v_people) with ordinality t(v, n) loop
    p := null;
    select * into p from public.event_registration_people
     where upgrade_token = x->>'upgrade_token' and event_id = e.id and is_test = v_test;
    if p.id is null then
      v_rows := v_rows || jsonb_build_object('person_id', null, 'status', 'refused', 'reason', 'person_not_found', 'planning', null);
      continue; end if;
    -- live: their first (free) record; a test key's person has none (nothing is kept for them)
    v_anchor := case when v_test then null else coalesce(p.free_guest_id, p.vip_guest_id) end;
    v_cur := case when v_test then null else public.event_planning_record(v_anchor, p.id) end;
    v_state := public.event_web_planning_state(p.id);
    if v_state <> 'open' then
      v_rows := v_rows || jsonb_build_object('person_id', p.id, 'status', 'refused', 'reason', 'person_cancelled',
                                             'planning', v_cur - 'plan_id' - 'staff_id');
      continue; end if;
    v_days := array(select (d.value #>> '{}')::date from jsonb_array_elements(public.event_web_person_view(p.id)->'days') d);
    v_c := public.event_planning_check(e.id, v_days, x->'answers', (v_cur->>'plan_id')::uuid);
    -- The edge function refuses wrong choices and lengths (400); what it lets through and the
    -- database still refuses is a contract break, final: class 22.
    if exists (select 1 from jsonb_array_elements(v_c->'problems') pr where pr.value->>'code' in ('bad_choice', 'too_long')) then
      raise exception using errcode = '22023', message = 'event_web_planning_answers: answers outside the contract'; end if;
    v_reason := (select pr.value->>'code' from jsonb_array_elements(v_c->'problems') with ordinality pr(value, n) order by pr.n limit 1);
    if v_reason is not null then
      v_rows := v_rows || jsonb_build_object('person_id', p.id, 'status', 'refused', 'reason', v_reason,
                                             'planning', v_cur - 'plan_id' - 'staff_id');
    elsif v_cur is not null and v_cur->'answers' = v_c->'answers' then
      v_rows := v_rows || jsonb_build_object('person_id', p.id, 'status', 'saved', 'reason', null,
                                             'planning', v_cur - 'plan_id' - 'staff_id');
    elsif coalesce((v_cur->>'version')::integer, 0) <> (x->>'version')::numeric then
      v_rows := v_rows || jsonb_build_object('person_id', p.id, 'status', 'refused', 'reason', 'changed_meanwhile',
                                             'planning', v_cur - 'plan_id' - 'staff_id');
    elsif v_test then
      v_rows := v_rows || jsonb_build_object('person_id', p.id, 'status', 'test', 'reason', null,
        'planning', jsonb_build_object('version', coalesce((v_cur->>'version')::integer, 0) + 1, 'answers', v_c->'answers',
                                       'updated_at', now(), 'updated_by', 'guest'));
    else
      v_w := public.event_planning_write(e.id, v_anchor, p.id, v_c->'answers', 'guest', null);
      v_rows := v_rows || jsonb_build_object('person_id', p.id, 'status', 'saved', 'reason', null,
                                             'planning', v_w - 'plan_id' - 'staff_id' - 'changed');
    end if;
  end loop;
  -- Never says whether anyone is a customer, matched, held or referred.
  return jsonb_build_object('ok', true, 'test', v_test, 'status', 'ok', 'people', v_rows);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_holders(p_event_id uuid)
 RETURNS TABLE(customer_id uuid, state text, invoice_id uuid, invoice_no text, person_id uuid, guest_id uuid, since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 436 (round 8, the owner 21 Oct 2026: P1): each VIP payment of the event that a customer
  -- holds, paid or waiting, so the Event page can say when one customer has two (one to
  -- refund): a website person's VIP invoice still standing (paid; or reopened or part paid:
  -- waiting) and each of their VIP payments not invoiced yet (a HitPay payment or a transfer
  -- waiting for a Manager; a checkout opened but not paid is not a payment); and a VIP ticket
  -- sold at the counter still on the guest list (paid, or its invoice not paid yet: waiting).
  -- Not a test key's, a closed person's, or someone held (no customer yet: the To match panel
  -- shows their own payment).
  select p.customer_id, case when i.status::text in ('paid', 'completed_foc') then 'paid' else 'waiting' end,
         i.id, i.invoice_no, p.id, coalesce(p.vip_guest_id, p.free_guest_id), o.created_at
    from public.event_registration_people p
    join public.event_vip_order_people op on op.person_id = p.id
    join public.event_vip_orders o on o.id = op.order_ref
    left join public.invoices i on i.id = op.invoice_id and o.status = 'invoiced'
   where p.event_id = p_event_id and not p.is_test and p.match <> 'closed' and p.customer_id is not null
     and ((o.status = 'invoiced' and i.id is not null and i.deleted_at is null
           and i.status::text not in ('cancelled', 'refunded'))
          or o.status in ('recorded', 'needs_review'))
  union all
  select g.customer_id, case when i.status::text in ('paid', 'completed_foc') then 'paid' else 'waiting' end,
         i.id, i.invoice_no, null::uuid, g.id, g.created_at
    from public.event_web_settings s
    join public.event_guests g on g.event_id = s.event_id and g.source = 'ticket' and g.ticket_option_id = s.vip_option_id
    join public.invoices i on i.id = g.invoice_id
   where s.event_id = p_event_id and g.status = 'registered' and g.customer_id is not null
     and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
     and not exists (select 1 from public.event_registration_people p2 where p2.vip_guest_id = g.id)
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_settings_get(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.event_web_settings%rowtype; e public.events%rowtype; v_settings jsonb;
begin
  perform public.require_active_staff('{owner,admin,manager}');
  select * into e from public.events where id = p_event_id and deleted_at is null;
  if not found then raise exception 'Event not found'; end if;
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  select * into s from public.event_web_settings where event_id = p_event_id;
  if s.event_id is not null then
    v_settings := to_jsonb(s) - 'last_sync_at' - 'last_test_sync_at' || jsonb_build_object(
      'last_sync_at', s.last_sync_at, 'last_test_sync_at', s.last_test_sync_at,
      'store_name', (select st.name from public.stores st where st.id = s.store_id),
      'acting_name', (select pr.full_name from public.profiles pr where pr.id = s.acting_profile_id),
      'vip_option_name', (select o.name from public.event_ticket_options o where o.id = s.vip_option_id),
      'source_label', (select so.label from public.customer_source_options so where so.id = s.source_option_id),
      'site_url', substring(s.sync_url from '^(https://[^/]+)'));
  end if;
  return jsonb_build_object(
    'event_id', e.id, 'event_name', e.name,
    'settings', v_settings,
    'readiness', public.event_web_readiness(p_event_id),
    'endpoint_path', '/functions/v1/event-website',
    'keys', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'kind', k.kind, 'key_hint', k.key_hint, 'label', k.label,
                         'created_at', k.created_at, 'created_by_name', cb.full_name, 'last_used_at', k.last_used_at,
                         'revoked_at', k.revoked_at, 'revoked_by_name', rb.full_name, 'revoked_reason', k.revoked_reason)
                         order by k.revoked_at nulls first, k.created_at desc)
                        from public.event_web_keys k
                        left join public.profiles cb on cb.id = k.created_by
                        left join public.profiles rb on rb.id = k.revoked_by
                       where k.event_id = p_event_id), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('type', q.type, 'received_at', q.received_at, 'outcome', q.outcome,
                             'kind', q.kind, 'is_write', q.is_write) order by q.received_at desc)
                            from (select r.type, r.received_at, r.outcome, k.kind, r.is_write
                                    from public.event_web_requests r join public.event_web_keys k on k.id = r.key_id
                                   where k.event_id = p_event_id
                                   order by r.received_at desc limit 40) q), '[]'::jsonb),
    'test', jsonb_build_object(
      'registrations', coalesce((select jsonb_agg(jsonb_build_object('registration_id', r.registration_id,
                            'submitted_at', r.submitted_at, 'created_at', r.created_at, 'referral_code', r.referral_code,
                            'referral_state', r.referral_state,
                            'people', (select coalesce(jsonb_agg(jsonb_build_object('person_id', p.id, 'position', p.position,
                                          'full_name', p.full_name, 'phone', p.phone, 'email', p.email, 'days', to_jsonb(p.days),
                                          'vip', public.event_web_person_vip_state(p.id), 'test_outcome', p.test_outcome,
                                          'referral_note', public.event_web_referral_note(p.id))
                                          order by p.position), '[]'::jsonb)
                                         from public.event_registration_people p where p.registration_ref = r.id))
                            order by r.created_at desc)
                           from public.event_registrations r where r.event_id = p_event_id and r.is_test), '[]'::jsonb),
      'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'order_id', o.order_id, 'provider', o.provider,
                            'status', o.status, 'livemode', o.livemode, 'amount_total', o.amount_total_cents / 100.0,
                            'amount_paid', o.amount_paid_cents / 100.0, 'test_note', o.test_note, 'test_would', o.test_would,
                            'review_reason', o.review_reason, 'created_at', o.created_at)
                            order by o.created_at desc)
                           from public.event_vip_orders o where o.event_id = p_event_id and o.is_test), '[]'::jsonb)),
    'choices', jsonb_build_object(
      'stores', coalesce((select jsonb_agg(jsonb_build_object('id', st.id, 'name', st.name) order by st.name)
                            from public.event_stores es join public.stores st on st.id = es.store_id
                           where es.event_id = p_event_id), '[]'::jsonb),
      'profiles', coalesce((select jsonb_agg(jsonb_build_object('id', pr.id, 'full_name', pr.full_name, 'role', pr.role) order by pr.full_name)
                              from public.profiles pr
                             where pr.is_active and pr.deleted_at is null and coalesce(pr.invitation_status, 'accepted') = 'accepted'
                               and pr.role in ('owner', 'admin', 'manager')), '[]'::jsonb),
      'options', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'days_count', o.days_count,
                             'price', o.price, 'is_active', o.is_active) order by o.sort_order, o.name)
                             from public.event_ticket_options o where o.event_id = p_event_id), '[]'::jsonb),
      'vouchers', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'code', v.code,
                              'priced_at_store', s.store_id is not null
                                 and coalesce((public.voucher_price_for(s.store_id, v.id, true)->>'has_price')::boolean, false))
                              order by v.name)
                              from public.vouchers v where v.is_active and v.deleted_at is null), '[]'::jsonb),
      'products', coalesce((select jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.name, 'sku', pr.sku,
                              'stock', (select si.current_qty from public.store_inventory si
                                         where si.product_id = pr.id and si.store_id = s.store_id)) order by pr.name)
                              from public.products pr
                             where pr.is_active and pr.deleted_at is null
                               and (pr.id = any (coalesce(s.gift_product_ids, '{}'))
                                    or exists (select 1 from public.store_inventory si
                                                join public.event_stores es on es.store_id = si.store_id and es.event_id = p_event_id
                                               where si.product_id = pr.id and si.current_qty > 0))), '[]'::jsonb),
      'methods', coalesce((select jsonb_agg(jsonb_build_object('id', pm.id, 'name', pm.name) order by pm.name)
                             from public.payment_methods pm where pm.is_active and pm.deleted_at is null
                              and not coalesce(pm.is_wallet_credit, false)), '[]'::jsonb),
      'sources', coalesce((select jsonb_agg(jsonb_build_object('id', so.id, 'label', so.label, 'requires_details', so.requires_details)
                             order by so.sort_order, so.label)
                             from public.customer_source_options so where so.is_active), '[]'::jsonb)),
    'can_manage', public.is_owner(),
    'can_clear_tests', public.is_owner_or_manager(),
    'can_set_venue', public.is_manager_or_above(),
    -- 436 (round 7): the talk titles the website asks about (Q4), the suggested list shown until saved.
    'talks', jsonb_build_object('titles', to_jsonb(public.event_web_talk_titles(p_event_id)),
                                'saved', s.talk_titles is not null, 'suggested', to_jsonb(public.event_web_talk_titles(null))),
    'can_set_talks', public.is_manager_or_above() and s.event_id is not null);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_settings_save(p_event_id uuid, p_settings jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.events%rowtype; s0 public.event_web_settings%rowtype; s1 public.event_web_settings%rowtype;
  v_ready jsonb; v_code text; v_mode text; v_venue text; v_sync text; v_ids uuid[];
begin
  perform public.require_active_staff('{owner}');
  select * into e from public.events where id = p_event_id and deleted_at is null for update;
  if not found then raise exception 'Event not found'; end if;
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  if jsonb_typeof(p_settings) is distinct from 'object' then raise exception 'Settings are missing'; end if;
  select * into s0 from public.event_web_settings where event_id = p_event_id for update;
  v_code := upper(btrim(coalesce(p_settings->>'code', '')));
  if v_code !~ '^[A-Z0-9][A-Z0-9-]{2,39}$' then
    raise exception 'The event code is 3 to 40 capital letters, digits and dashes, starting with a letter or digit (e.g. HEALTH-SEMINAR-NOV26)'; end if;
  if exists (select 1 from public.event_web_settings x where x.code = v_code and x.event_id <> p_event_id) then
    raise exception 'Another event''s website already uses the code %', v_code; end if;
  v_mode := coalesce(nullif(p_settings->>'mode', ''), 'off');
  if v_mode not in ('off', 'record_only', 'live') then raise exception 'The mode is Off, Record only or Live'; end if;
  v_venue := nullif(btrim(coalesce(p_settings->>'venue', '')), '');
  if char_length(v_venue) > 300 then raise exception 'The venue is at most 300 characters'; end if;
  v_sync := nullif(btrim(coalesce(p_settings->>'sync_url', '')), '');
  if v_sync is not null and v_sync !~ '^https://[^[:space:]]+$' then
    raise exception 'The sync URL must start with https://'; end if;
  if nullif(p_settings->>'store_id', '') is null then raise exception 'Choose the store'; end if;
  if nullif(p_settings->>'acting_profile_id', '') is null then raise exception 'Choose who raises the invoices'; end if;
  insert into public.event_web_settings as w (event_id, code, mode, venue, store_id, acting_profile_id, vip_option_id,
      vip_voucher_ids, gift_product_ids, hitpay_payment_method_id, paynow_payment_method_id, bank_payment_method_id,
      source_option_id, source_details, sync_url, created_by, updated_by)
  values (p_event_id, v_code, v_mode, v_venue, (p_settings->>'store_id')::uuid, (p_settings->>'acting_profile_id')::uuid,
          nullif(p_settings->>'vip_option_id', '')::uuid,
          -- Each list keeps the order it was chosen in, once each.
          array(select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(p_settings->'vip_voucher_ids', '[]')) with ordinality t(x, n)
                 group by 1 order by min(n)),
          array(select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(p_settings->'gift_product_ids', '[]')) with ordinality t(x, n)
                 group by 1 order by min(n)),
          nullif(p_settings->>'hitpay_payment_method_id', '')::uuid, nullif(p_settings->>'paynow_payment_method_id', '')::uuid,
          nullif(p_settings->>'bank_payment_method_id', '')::uuid, nullif(p_settings->>'source_option_id', '')::uuid,
          nullif(btrim(coalesce(p_settings->>'source_details', '')), ''), v_sync, auth.uid(), auth.uid())
  on conflict (event_id) do update
     -- The venue is kept unless the settings carry one (a Manager may have set it meanwhile).
     set code = excluded.code, mode = excluded.mode,
         venue = case when p_settings ? 'venue' then excluded.venue else w.venue end, store_id = excluded.store_id,
         acting_profile_id = excluded.acting_profile_id, vip_option_id = excluded.vip_option_id,
         vip_voucher_ids = excluded.vip_voucher_ids, gift_product_ids = excluded.gift_product_ids,
         hitpay_payment_method_id = excluded.hitpay_payment_method_id,
         paynow_payment_method_id = excluded.paynow_payment_method_id,
         bank_payment_method_id = excluded.bank_payment_method_id, source_option_id = excluded.source_option_id,
         source_details = excluded.source_details, sync_url = excluded.sync_url,
         updated_by = auth.uid(), updated_at = now()
  returning * into s1;
  v_ready := public.event_web_readiness(p_event_id);
  if jsonb_array_length(v_ready->'blocking') > 0 then
    raise exception '%', v_ready->'blocking'->>0; end if;
  if v_mode <> 'off' and jsonb_array_length(v_ready->'errors') > 0 then
    raise exception 'Before the website can be switched on: %', v_ready->'errors'->>0; end if;
  perform public.write_audit_ex('event_web_settings', p_event_id, 'event_web_settings_saved',
    case when s0.event_id is null then null else to_jsonb(s0) - 'last_sync_at' - 'last_test_sync_at' - 'updated_at' end,
    to_jsonb(s1) - 'last_sync_at' - 'last_test_sync_at' - 'updated_at', 'events', null, s1.store_id);
  return jsonb_build_object('ok', true, 'readiness', v_ready);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_set_venue(p_event_id uuid, p_venue text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.event_web_settings%rowtype; v_venue text := nullif(btrim(coalesce(p_venue, '')), '');
begin
  perform public.require_active_staff('{owner,admin,manager}');
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  select * into s from public.event_web_settings where event_id = p_event_id for update;
  if not found then raise exception 'Save the website settings first'; end if;
  if char_length(v_venue) > 300 then raise exception 'The venue is at most 300 characters'; end if;
  update public.event_web_settings set venue = v_venue, updated_by = auth.uid(), updated_at = now() where event_id = p_event_id;
  perform public.write_audit_ex('event_web_settings', p_event_id, 'event_web_venue_set',
    jsonb_build_object('venue', s.venue), jsonb_build_object('venue', v_venue), 'events', null, s.store_id);
  return jsonb_build_object('ok', true, 'venue', v_venue);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_key_create(p_event_id uuid, p_kind text, p_label text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.event_web_settings%rowtype; v_key text; v_id uuid; v_hint text;
begin
  perform public.require_active_staff('{owner}');
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  select * into s from public.event_web_settings where event_id = p_event_id;
  if not found then raise exception 'Save the website settings first'; end if;
  if p_kind is null or p_kind not in ('live', 'test') then raise exception 'A key is live or test'; end if;
  v_key := 'evk_' || p_kind || '_'
           || translate(rtrim(encode(extensions.gen_random_bytes(32), 'base64'), '='), '+/', '-_');
  v_hint := 'evk_' || p_kind || '_' || substr(v_key, 10, 4) || '…' || right(v_key, 4);
  insert into public.event_web_keys (event_id, kind, key_hash, key_hint, label, created_by)
  values (p_event_id, p_kind, encode(extensions.digest(v_key, 'sha256'), 'hex'), v_hint,
          nullif(btrim(coalesce(p_label, '')), ''), auth.uid())
  returning id into v_id;
  perform public.write_audit_ex('event_web_keys', v_id, 'event_web_key_created', null,
    jsonb_build_object('event_id', p_event_id, 'kind', p_kind, 'key_hint', v_hint, 'label', nullif(btrim(coalesce(p_label, '')), '')),
    'events', null, s.store_id);
  return jsonb_build_object('key_id', v_id, 'kind', p_kind, 'key_hint', v_hint, 'key', v_key);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_key_revoke(p_key_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.event_web_keys%rowtype;
begin
  perform public.require_active_staff('{owner}');
  select * into k from public.event_web_keys where id = p_key_id for update;
  if not found then raise exception 'Key not found'; end if;
  if not public.event_can_run(k.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  if k.revoked_at is not null then raise exception 'This key is already revoked'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason for revoking the key'; end if;
  update public.event_web_keys set revoked_at = now(), revoked_by = auth.uid(), revoked_reason = btrim(p_reason)
   where id = k.id;
  perform public.write_audit_ex('event_web_keys', k.id, 'event_web_key_revoked',
    jsonb_build_object('kind', k.kind, 'key_hint', k.key_hint), jsonb_build_object('revoked', true),
    'events', btrim(p_reason), (select s.store_id from public.event_web_settings s where s.event_id = k.event_id));
  return jsonb_build_object('ok', true);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_test_clear(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n_orders integer; n_regs integer; n_requests integer;
begin
  perform public.require_active_staff('{owner,manager}');
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  delete from public.event_vip_orders where event_id = p_event_id and is_test and not coalesce(livemode, false);
  get diagnostics n_orders = row_count;
  delete from public.event_registrations r where r.event_id = p_event_id and r.is_test
     and not exists (select 1 from public.event_registration_people p join public.event_vip_order_people op on op.person_id = p.id
                      where p.registration_ref = r.id);
  get diagnostics n_regs = row_count;
  delete from public.event_web_requests q using public.event_web_keys k
   where k.id = q.key_id and k.event_id = p_event_id and k.kind = 'test';
  get diagnostics n_requests = row_count;
  perform public.write_audit_ex('event_web_settings', p_event_id, 'event_web_test_cleared', null,
    jsonb_build_object('registrations', n_regs, 'orders', n_orders, 'requests', n_requests), 'events', null,
    (select s.store_id from public.event_web_settings s where s.event_id = p_event_id));
  return jsonb_build_object('registrations', n_regs, 'orders', n_orders, 'requests', n_requests);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_guest_extras(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.event_web_settings%rowtype; v_access boolean; v_vh jsonb; v_dbl uuid[];
begin
  perform public.require_active_staff();
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  select * into s from public.event_web_settings where event_id = p_event_id;
  if not found then
    return jsonb_build_object('settings', null, 'guests', '[]'::jsonb, 'holds', '[]'::jsonb, 'gift_choices', '[]'::jsonb,
                              'vip_doubles', '[]'::jsonb,
                              'can_close_holds', public.is_owner_or_manager(), 'can_undo_gifts', public.is_owner_or_manager());
  end if;
  v_access := public.user_has_store_access(s.store_id);
  -- 436 round 8 (the owner, 21 Oct 2026: P1): the VIP payments customers hold (paid or
  -- waiting); a customer with two is flagged (one to refund) and counted once.
  select coalesce(jsonb_agg(to_jsonb(h)), '[]'::jsonb) into v_vh from public.event_vip_holders(p_event_id) h;
  select coalesce(array_agg(d.customer_id), '{}'::uuid[]) into v_dbl
    from (select h.customer_id from jsonb_to_recordset(v_vh) h(customer_id uuid)
           group by h.customer_id having count(*) > 1) d;
  return jsonb_build_object(
    'settings', jsonb_build_object('store_id', s.store_id,
                  'store_name', (select st.name from public.stores st where st.id = s.store_id),
                  'vip_option_id', s.vip_option_id, 'mode', s.mode, 'code', s.code, 'venue', s.venue,
                  'site_url', substring(s.sync_url from '^(https://[^/]+)'), 'gift_store_access', v_access),
    'guests', coalesce((
      select jsonb_agg(x.j) from (
        -- website people: their free and VIP records
        select jsonb_build_object('guest_id', g.id, 'person_id', p.id, 'website', true, 'is_test', p.is_test,
                 'registration_id', r.registration_id, 'position', p.position, 'group_size', r.people_count,
                 'parked', g.id = p.free_guest_id and g.status = 'cancelled' and coalesce(g.cancelled_reason, '') like 'Upgraded to VIP%',
                 'vip', public.event_web_person_vip_state(p.id),
                 'vip_guest', g.id = p.vip_guest_id,
                 'vip_double', coalesce(p.customer_id = any (v_dbl), false),
                 'vip_invoice_no', case when v_access then (select i.invoice_no from public.event_vip_order_people op
                                     join public.event_vip_orders o on o.id = op.order_ref join public.invoices i on i.id = op.invoice_id
                                    where op.person_id = p.id and o.status = 'invoiced' order by o.created_at desc limit 1) end,
                 'vip_waiting', (select o.provider from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
                                  where op.person_id = p.id and o.status in ('recorded', 'needs_review') order by o.created_at desc limit 1),
                 'hold', case when p.match = 'held' then jsonb_build_object('reason', p.hold_reason, 'held_at', p.created_at) end,
                 'closed', p.match = 'closed',
                 'match', p.match,
                 'typed_email', p.email,
                 'referral', case when r.referral_state <> 'none' then jsonb_build_object('code', r.referral_code,
                               'state', r.referral_state, 'outcome', p.referral_outcome,
                               'affiliate_name', (select c.full_name from public.customers c where c.id = r.referrer_customer_id),
                               'note', public.event_web_referral_note(p.id)) end,
                 'upgrade_token', case when p.match <> 'closed' and public.event_web_person_vip_state(p.id) in ('none', 'refunded')
                                       then p.upgrade_token end,
                 'gift', (select jsonb_build_object('gift_id', gf.id, 'product_id', gf.product_id, 'product_name', pr.name,
                             'use_no', gf.use_no, 'day', gf.day, 'given_at', gf.given_at, 'given_by_name', gb.full_name)
                            from public.event_vip_gifts gf join public.products pr on pr.id = gf.product_id
                            left join public.profiles gb on gb.id = gf.given_by
                           where gf.guest_id = g.id and gf.undone_at is null)) as j
          from public.event_registration_people p
          join public.event_registrations r on r.id = p.registration_ref
          join public.event_guests g on g.id in (p.free_guest_id, p.vip_guest_id)
         where p.event_id = p_event_id
        union all
        -- VIP tickets sold at the counter
        select jsonb_build_object('guest_id', g.id, 'person_id', null, 'website', false, 'is_test', false,
                 'registration_id', null, 'position', null, 'group_size', null, 'parked', false,
                 'vip', case when i.deleted_at is not null or i.status::text in ('cancelled', 'refunded') then 'refunded'
                             when i.status::text in ('paid', 'completed_foc') then 'paid' else 'pending' end,
                 'vip_guest', true, 'vip_invoice_no', case when v_access then i.invoice_no end, 'vip_waiting', null,
                 'vip_double', coalesce(g.customer_id = any (v_dbl), false),
                 'hold', null, 'closed', false, 'match', null, 'typed_email', null, 'referral', null, 'upgrade_token', null,
                 'gift', (select jsonb_build_object('gift_id', gf.id, 'product_id', gf.product_id, 'product_name', pr.name,
                             'use_no', gf.use_no, 'day', gf.day, 'given_at', gf.given_at, 'given_by_name', gb.full_name)
                            from public.event_vip_gifts gf join public.products pr on pr.id = gf.product_id
                            left join public.profiles gb on gb.id = gf.given_by
                           where gf.guest_id = g.id and gf.undone_at is null))
          from public.event_guests g
          left join public.invoices i on i.id = g.invoice_id
         where g.event_id = p_event_id and g.source = 'ticket' and g.ticket_option_id = s.vip_option_id
           and not exists (select 1 from public.event_registration_people p where p.vip_guest_id = g.id)) x), '[]'::jsonb),
    -- The customers a held person may be: those they were held for (425's
    -- holders, old numbers included, read once at registration), and whoever
    -- has their phone or their email's inbox now (as 433's list).
    'holds', coalesce((
      with keys as materialized (
        select x.id, public.customer_email_match_key(x.email) as k
          from public.customers x where x.deleted_at is null and x.email is not null)
      select jsonb_agg(jsonb_build_object('person_id', p.id, 'guest_id', p.free_guest_id, 'registration_id', r.registration_id,
               'position', p.position, 'group_size', r.people_count, 'held_at', p.created_at, 'reason', p.hold_reason,
               'full_name', p.full_name, 'phone', p.phone, 'phone_norm', p.phone_norm, 'email', p.email, 'days', to_jsonb(p.days),
               'referral_note', public.event_web_referral_note(p.id),
               'vip_waiting', exists (select 1 from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
                                       where op.person_id = p.id and o.status in ('recorded', 'needs_review', 'pending')),
               -- round 8: a VIP payment of theirs (paid, or a transfer sent) waits for the match
               'vip_payment', exists (select 1 from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
                                       where op.person_id = p.id and o.status in ('recorded', 'needs_review')),
               'candidates', coalesce((
                 select jsonb_agg(jsonb_build_object('customer_id', c.id, 'full_name', c.full_name, 'phone', c.phone,
                          'email', c.email, 'created_at', c.created_at,
                          'phone_matches', coalesce(public.normalize_customer_phone(c.phone) = p.phone_norm, false)
                                           or (public.normalize_customer_phone(c.phone) is null and c.id = any (p.candidate_customer_ids)
                                               and p.hold_reason in ('phone_in_use', 'phone_and_email_in_use')),
                          'email_matches', coalesce(public.customer_email_match_key(c.email) = public.customer_email_match_key(p.email), false),
                          'name_matches', coalesce(public.normalize_customer_match_name(c.full_name) = public.normalize_customer_match_name(p.full_name)
                                                   or public.customer_names_match(c.full_name, p.full_name), false),
                          -- round 8: already a guest of this event: their days, and each VIP payment
                          -- they hold (paid with its invoice, or waiting)
                          'guest', (select case when gd.days is not null or gv.vips is not null
                                                then jsonb_build_object('days', coalesce(gd.days, '[]'::jsonb),
                                                                        'vips', coalesce(gv.vips, '[]'::jsonb)) end
                                      from (select jsonb_agg(distinct d.day order by d.day) as days
                                              from public.event_guests g2 join public.event_guest_days d on d.guest_id = g2.id
                                             where g2.event_id = p_event_id and g2.customer_id = c.id and g2.status = 'registered') gd,
                                           (select jsonb_agg(jsonb_build_object('state', h.state,
                                                     'invoice_no', case when v_access then h.invoice_no end)
                                                     order by h.since, h.invoice_no) as vips
                                              from jsonb_to_recordset(v_vh) h(customer_id uuid, state text, invoice_no text, since timestamptz)
                                             where h.customer_id = c.id) gv))
                          order by c.created_at)
                   -- 436: three lookups joined (the phone by its index), not one
                   -- scan of every customer per held person.
                   from (select unnest(p.candidate_customer_ids) as id
                         union
                         select c2.id from public.customers c2
                          where c2.deleted_at is null and public.normalize_customer_phone(c2.phone) = p.phone_norm
                         union
                         select keys.id from keys where keys.k = (select public.customer_email_match_key(p.email))) m
                   join public.customers c on c.id = m.id
                  where c.deleted_at is null), '[]'::jsonb))
             order by p.created_at, p.position)
        from public.event_registration_people p
        join public.event_registrations r on r.id = p.registration_ref
       where p.event_id = p_event_id and p.match = 'held' and not p.is_test), '[]'::jsonb),
    'gift_choices', coalesce((select jsonb_agg(jsonb_build_object('product_id', pr.id, 'name', pr.name,
                       'stock', coalesce((select si.current_qty from public.store_inventory si
                                           where si.store_id = s.store_id and si.product_id = pr.id), 0)) order by u.n)
                     from unnest(s.gift_product_ids) with ordinality u(id, n)
                     join public.products pr on pr.id = u.id), '[]'::jsonb),
    -- round 8: customers holding two VIP payments for this event (paid or waiting): refund one
    'vip_doubles', coalesce((
      select jsonb_agg(jsonb_build_object('customer_id', c.id, 'full_name', c.full_name, 'vips', d.vips) order by c.full_name, c.id)
        from (select h.customer_id, jsonb_agg(jsonb_build_object('state', h.state,
                       'invoice_no', case when v_access then h.invoice_no end) order by h.since, h.invoice_no) as vips
                from jsonb_to_recordset(v_vh) h(customer_id uuid, state text, invoice_no text, since timestamptz)
               where h.customer_id = any (v_dbl)
               group by h.customer_id) d
        join public.customers c on c.id = d.customer_id), '[]'::jsonb),
    'can_close_holds', public.is_owner_or_manager(),
    'can_undo_gifts', public.is_owner_or_manager());
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_registration_attach(p_person_id uuid, p_customer_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; c public.customers%rowtype; r public.event_registrations%rowtype;
  v_outcome text; v_retry jsonb;
begin
  perform public.require_active_staff('{owner,admin,manager,staff}');
  select * into p from public.event_registration_people where id = p_person_id;
  if not found then raise exception 'Registration not found'; end if;
  if not public.event_can_run(p.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  -- 436: as 415's web_order_resolve: the store the website's customers and
  -- invoices are made at (a match may invoice a waiting VIP payment).
  if not public.user_has_store_access((select s.store_id from public.event_web_settings s where s.event_id = p.event_id)) then
    raise exception 'You do not have access to this event''s store' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_note, ''))) < 3 then
    raise exception 'Add a short note on how you confirmed this is the same person.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || p.phone_norm, 0));
  perform pg_advisory_xact_lock(hashtextextended('event-registration:' || p.event_id::text, 0));
  select * into p from public.event_registration_people where id = p_person_id for update;
  if p.match <> 'held' then raise exception 'This registration is not waiting to be matched.'; end if;
  select * into c from public.customers where id = p_customer_id for update;
  if not found or c.deleted_at is not null then raise exception 'Customer not found.'; end if;
  select * into r from public.event_registrations where id = p.registration_ref;
  perform public.event_web_fill_customer(c.id, p.id);
  update public.event_guests set customer_id = c.id, updated_at = now(), updated_by = auth.uid()
   where id in (p.free_guest_id, p.vip_guest_id);
  v_outcome := public.event_web_apply_referral(p.id, c.id);
  update public.event_registration_people
     set customer_id = c.id, match = 'staff_attached', resolved_by = auth.uid(), resolved_at = now(),
         resolution_note = btrim(p_note), referral_outcome = v_outcome, updated_at = now()
   where id = p.id;
  perform public.write_audit_ex('event_registration_people', p.id, 'event_registration_matched',
    jsonb_build_object('typed_name', p.full_name, 'typed_phone', p.phone, 'typed_email', p.email),
    jsonb_build_object('customer_id', c.id, 'hold_reason', p.hold_reason, 'registration_id', r.registration_id,
                       'suggested_customer', c.id = any (p.candidate_customer_ids), 'referral_outcome', v_outcome),
    'events', btrim(p_note), (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
  v_retry := public.event_vip_retry_after_match(p.id);
  return jsonb_build_object('ok', true, 'customer_id', c.id, 'vip_orders', v_retry);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_registration_create_customer(p_person_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; r public.event_registrations%rowtype; v_new jsonb; v_retry jsonb;
begin
  perform public.require_active_staff('{owner,admin,manager,staff}');
  select * into p from public.event_registration_people where id = p_person_id;
  if not found then raise exception 'Registration not found'; end if;
  if not public.event_can_run(p.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  if not public.user_has_store_access((select s.store_id from public.event_web_settings s where s.event_id = p.event_id)) then
    raise exception 'You do not have access to this event''s store' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || p.phone_norm, 0));
  perform pg_advisory_xact_lock(hashtextextended('event-registration:' || p.event_id::text, 0));
  select * into p from public.event_registration_people where id = p_person_id for update;
  if p.match <> 'held' then raise exception 'This registration is not waiting to be matched.'; end if;
  select * into r from public.event_registrations where id = p.registration_ref;
  -- Q19 = A: on a phone in use under another customer's name, or on the
  -- affiliate's own phone or email inbox under another name, her referral
  -- only once an Owner or Manager checks them (the owner, 20 and 21 Oct
  -- 2026); her name: not referred (someone else with her name, as staff
  -- make a customer of them here).
  v_new := public.event_web_new_customer(p.id);
  update public.event_guests set customer_id = (v_new->>'customer_id')::uuid, updated_at = now(), updated_by = auth.uid()
   where id in (p.free_guest_id, p.vip_guest_id);
  update public.event_registration_people
     set customer_id = (v_new->>'customer_id')::uuid, match = 'staff_created', resolved_by = auth.uid(), resolved_at = now(),
         resolution_note = nullif(btrim(coalesce(p_note, '')), ''), referral_outcome = v_new->>'referral_outcome',
         updated_at = now()
   where id = p.id;
  perform public.write_audit_ex('event_registration_people', p.id, 'event_registration_customer_created', null,
    jsonb_build_object('customer_id', v_new->>'customer_id', 'hold_reason', p.hold_reason, 'held_for', to_jsonb(p.candidate_customer_ids),
                       'registration_id', r.registration_id, 'referral_outcome', v_new->>'referral_outcome'),
    'events', nullif(btrim(coalesce(p_note, '')), ''), (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
  v_retry := public.event_vip_retry_after_match(p.id);
  return jsonb_build_object('ok', true, 'customer_id', v_new->>'customer_id', 'vip_orders', v_retry);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_registration_close(p_person_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; v_state text; v_inv_no text;
begin
  perform public.require_active_staff('{owner,manager}');
  select * into p from public.event_registration_people where id = p_person_id for update;
  if not found then raise exception 'Registration not found'; end if;
  if not public.event_can_run(p.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  if not public.user_has_store_access((select s.store_id from public.event_web_settings s where s.event_id = p.event_id)) then
    raise exception 'You do not have access to this event''s store' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason'; end if;
  if p.match = 'closed' then raise exception 'This registration is already closed.'; end if;
  v_state := public.event_web_person_vip_state(p.id);
  if v_state = 'paid' then raise exception '% is VIP: cancel or refund their VIP invoice instead.', p.full_name; end if;
  if v_state = 'pending' then
    -- Their VIP invoice not paid in full (reopened): that invoice, not Website orders.
    select i.invoice_no into v_inv_no from public.event_vip_order_people op
      join public.event_vip_orders o on o.id = op.order_ref
      join public.invoices i on i.id = op.invoice_id
     where op.person_id = p.id and o.status = 'invoiced' and i.deleted_at is null
       and i.status::text not in ('paid', 'completed_foc', 'cancelled', 'refunded')
     order by i.created_at desc limit 1;
    if v_inv_no is not null then
      raise exception '%''s VIP invoice % is waiting to be paid: cancel or refund it instead.', p.full_name, v_inv_no; end if;
    raise exception 'A VIP payment for % is waiting: deal with it on Website orders first.', p.full_name;
  end if;
  if exists (select 1 from public.event_guest_days gd where gd.guest_id = p.free_guest_id and gd.attended_at is not null) then
    raise exception '% has already checked in. Undo the check-in first if they did not come.', p.full_name; end if;
  update public.event_guests set status = 'cancelled', cancelled_reason = 'Closed: ' || btrim(p_reason), cancelled_at = now(),
         updated_at = now(), updated_by = auth.uid()
   where id = p.free_guest_id and status = 'registered';
  update public.event_registration_people
     set match = 'closed', resolved_by = auth.uid(), resolved_at = now(), resolution_note = btrim(p_reason), updated_at = now()
   where id = p.id;
  perform public.write_audit_ex('event_registration_people', p.id, 'event_registration_closed',
    jsonb_build_object('match', p.match, 'hold_reason', p.hold_reason), jsonb_build_object('match', 'closed'),
    'events', btrim(p_reason), (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
  return jsonb_build_object('ok', true);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_orders_list(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.event_web_settings%rowtype; v_access boolean;
begin
  perform public.require_active_staff('{owner,admin,manager}');
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  select * into s from public.event_web_settings where event_id = p_event_id;
  if not found then return jsonb_build_object('settings', null, 'orders', '[]'::jsonb, 'can_close', public.is_owner_or_manager()); end if;
  v_access := public.user_has_store_access(s.store_id);
  return jsonb_build_object(
    'settings', jsonb_build_object('mode', s.mode, 'code', s.code,
      'store_name', (select st.name from public.stores st where st.id = s.store_id),
      'hitpay_method_name', (select pm.name from public.payment_methods pm where pm.id = s.hitpay_payment_method_id),
      'paynow_method_name', (select pm.name from public.payment_methods pm where pm.id = s.paynow_payment_method_id),
      'bank_method_name', (select pm.name from public.payment_methods pm where pm.id = s.bank_payment_method_id)),
    'can_close', public.is_owner_or_manager(),
    'orders', coalesce((select jsonb_agg(jsonb_build_object(
        'id', o.id, 'order_id', o.order_id, 'provider', o.provider, 'status', o.status, 'is_test', o.is_test,
        'livemode', o.livemode, 'unit_amount', o.unit_amount_cents / 100.0, 'quantity', o.quantity,
        'amount_total', o.amount_total_cents / 100.0, 'amount_paid', o.amount_paid_cents / 100.0,
        'payer_name', o.payer_name, 'payer_email', o.payer_email, 'payer_phone', o.payer_phone,
        'checkout_opened_at', o.checkout_opened_at, 'expires_at', o.expires_at,
        'expired', o.status = 'pending' and o.expires_at <= now(),
        'paid_at', o.paid_at, 'paid_on', o.paid_on, 'reference', o.reference,
        'hitpay_payment_request_id', o.hitpay_payment_request_id, 'hitpay_payment_id', o.hitpay_payment_id,
        'review_reason', o.review_reason, 'refusal', o.refusal, 'waiting_for_match', o.waiting_for_match,
        'test_note', o.test_note, 'test_would', o.test_would,
        'refunded_total', o.refunded_cents_total / 100.0, 'refund_noted_at', o.refund_noted_at,
        -- HitPay's refund is covered once the order's invoices are cancelled,
        -- refunded or deleted for that much, or (round 3: an Owner or Manager
        -- refunding part of a VIP whose voucher was used) that much money is
        -- recorded as refunded on them since they were last reopened.
        'refund_covered', o.refunded_cents_total <= coalesce((select round(sum(
                                                                case when i.deleted_at is not null or i.status::text in ('cancelled', 'refunded')
                                                                     then i.total_amount
                                                                     else coalesce((select sum(rf.amount) from public.invoice_refunds rf
                                                                                     where rf.invoice_id = i.id
                                                                                       and (i.reopened_at is null or rf.created_at > i.reopened_at)), 0) end) * 100)
                                                              from public.event_vip_order_people op
                                                              join public.invoices i on i.id = op.invoice_id
                                                             where op.order_ref = o.id), 0),
        'created_at', o.created_at,
        'people', coalesce((select jsonb_agg(jsonb_build_object('person_id', p.id, 'position', op.position,
                     'name', p.full_name, 'phone', p.phone, 'email', p.email, 'match', p.match, 'hold_reason', p.hold_reason,
                     'customer_id', p.customer_id, 'customer_name', c.full_name, 'days', to_jsonb(p.days),
                     'invoice_id', case when v_access then i.id end, 'invoice_no', case when v_access then i.invoice_no end,
                     'invoice_status', i.status) order by op.position)
                    from public.event_vip_order_people op
                    join public.event_registration_people p on p.id = op.person_id
                    left join public.customers c on c.id = p.customer_id
                    left join public.invoices i on i.id = op.invoice_id
                   where op.order_ref = o.id), '[]'::jsonb))
        order by o.created_at desc)
        from public.event_vip_orders o where o.event_id = p_event_id), '[]'::jsonb));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_order_invoice(p_order_id uuid, p_amount_cents integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.event_vip_orders%rowtype; v jsonb;
begin
  perform public.require_active_staff('{owner,admin,manager}');
  select * into o from public.event_vip_orders where id = p_order_id for update;
  if not found then raise exception 'VIP order not found'; end if;
  if not public.event_can_run(o.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  if not public.user_has_store_access((select s.store_id from public.event_web_settings s where s.event_id = o.event_id)) then
    raise exception 'You do not have access to this event''s store' using errcode = '42501'; end if;
  if o.is_test then raise exception 'A test order is never invoiced'; end if;
  if o.status not in ('recorded', 'needs_review') then raise exception 'This order is not waiting for its invoices'; end if;
  if p_amount_cents is not null and p_amount_cents is distinct from o.amount_paid_cents then
    if o.provider not in ('paynow', 'bank') then
      raise exception 'Only a PayNow or bank transfer''s amount is entered here: HitPay''s is what HitPay charged'; end if;
    perform public.require_active_staff('{owner,manager}');
    if p_amount_cents < 0 or p_amount_cents > 1000000 then raise exception 'Enter the amount that arrived'; end if;
    update public.event_vip_orders set amount_paid_cents = p_amount_cents, updated_at = now(), updated_by = auth.uid()
     where id = o.id;
    perform public.write_audit_ex('event_vip_orders', o.id, 'event_vip_order_amount_corrected',
      jsonb_build_object('amount_paid_cents', o.amount_paid_cents),
      jsonb_build_object('order_id', o.order_id, 'amount_paid_cents', p_amount_cents, 'amount_total_cents', o.amount_total_cents),
      'events', 'The amount that arrived, entered when creating the invoices',
      (select s.store_id from public.event_web_settings s where s.event_id = o.event_id));
  end if;
  v := public.event_vip_make_invoices(o.id, true);
  perform public.write_audit_ex('event_vip_orders', o.id, 'event_vip_order_invoiced',
    jsonb_build_object('status', o.status, 'review_reason', o.review_reason),
    jsonb_build_object('order_id', o.order_id, 'status', v->>'status', 'invoice_nos', v->'invoice_nos', 'review_reason', v->>'review_reason'),
    'events', null, (select s.store_id from public.event_web_settings s where s.event_id = o.event_id));
  return v;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_order_dismiss(p_order_id uuid, p_reason text, p_dismiss boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.event_vip_orders%rowtype;
begin
  perform public.require_active_staff('{owner,admin,manager}');
  select * into o from public.event_vip_orders where id = p_order_id for update;
  if not found then raise exception 'VIP order not found'; end if;
  if not public.event_can_run(o.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  if not public.user_has_store_access((select s.store_id from public.event_web_settings s where s.event_id = o.event_id)) then
    raise exception 'You do not have access to this event''s store' using errcode = '42501'; end if;
  if o.provider = 'hitpay' and not o.is_test then
    raise exception 'A HitPay payment took money: create its invoices, or close it as refunded.'; end if;
  if coalesce(p_dismiss, true) then
    if o.status not in ('recorded', 'needs_review', 'test') then raise exception 'This order cannot be dismissed now'; end if;
    if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason (at least 3 characters)'; end if;
    if btrim(p_reason) ilike 'Refunded outside the app:%' then raise exception 'Use Close as refunded for a refund'; end if;
    update public.event_vip_orders
       set status_before_dismiss = status, reason_before_dismiss = review_reason, status = 'dismissed',
           review_reason = btrim(p_reason), updated_at = now(), updated_by = auth.uid()
     where id = o.id;
  else
    if o.status <> 'dismissed' or coalesce(o.review_reason, '') like 'Refunded outside the app:%' then
      raise exception 'This order is not dismissed'; end if;
    update public.event_vip_orders
       set status = coalesce(status_before_dismiss, 'needs_review'), review_reason = reason_before_dismiss,
           status_before_dismiss = null, reason_before_dismiss = null, updated_at = now(), updated_by = auth.uid()
     where id = o.id;
  end if;
  perform public.write_audit_ex('event_vip_orders', o.id,
    case when coalesce(p_dismiss, true) then 'event_vip_order_dismissed' else 'event_vip_order_restored' end,
    jsonb_build_object('status', o.status, 'review_reason', o.review_reason),
    (select jsonb_build_object('order_id', x.order_id, 'status', x.status, 'review_reason', x.review_reason)
       from public.event_vip_orders x where x.id = o.id),
    'events', nullif(btrim(coalesce(p_reason, '')), ''), (select s.store_id from public.event_web_settings s where s.event_id = o.event_id));
  return jsonb_build_object('ok', true);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_order_close_refunded(p_order_id uuid, p_reason text, p_close boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.event_vip_orders%rowtype;
begin
  perform public.require_active_staff('{owner,manager}');
  select * into o from public.event_vip_orders where id = p_order_id for update;
  if not found then raise exception 'VIP order not found'; end if;
  if not public.event_can_run(o.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  if not public.user_has_store_access((select s.store_id from public.event_web_settings s where s.event_id = o.event_id)) then
    raise exception 'You do not have access to this event''s store' using errcode = '42501'; end if;
  if coalesce(p_close, true) then
    if not (o.status in ('recorded', 'needs_review')
            or (o.status = 'refused' and coalesce(o.livemode, false) and coalesce(o.amount_paid_cents, 0) > 0)) then
      raise exception 'Only an order still waiting, with money taken, is closed as refunded'; end if;
    if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason (at least 3 characters)'; end if;
    update public.event_vip_orders
       set status_before_dismiss = status, reason_before_dismiss = review_reason, status = 'dismissed',
           review_reason = 'Refunded outside the app: ' || btrim(p_reason), updated_at = now(), updated_by = auth.uid()
     where id = o.id;
  else
    if o.status <> 'dismissed' or coalesce(o.review_reason, '') not like 'Refunded outside the app:%' then
      raise exception 'This order was not closed as refunded'; end if;
    update public.event_vip_orders
       set status = coalesce(status_before_dismiss, 'needs_review'), review_reason = reason_before_dismiss,
           status_before_dismiss = null, reason_before_dismiss = null, updated_at = now(), updated_by = auth.uid()
     where id = o.id;
  end if;
  perform public.write_audit_ex('event_vip_orders', o.id,
    case when coalesce(p_close, true) then 'event_vip_order_closed_refunded' else 'event_vip_order_reopened' end,
    jsonb_build_object('status', o.status, 'review_reason', o.review_reason),
    (select jsonb_build_object('order_id', x.order_id, 'status', x.status, 'review_reason', x.review_reason)
       from public.event_vip_orders x where x.id = o.id),
    'events', nullif(btrim(coalesce(p_reason, '')), ''), (select s.store_id from public.event_web_settings s where s.event_id = o.event_id));
  return jsonb_build_object('ok', true);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_gift_give(p_guest_id uuid, p_product_id uuid, p_day date, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.event_guests%rowtype; s public.event_web_settings%rowtype; e public.events%rowtype;
  gf public.event_vip_gifts%rowtype; v_use jsonb; v_use_id uuid; v_day date := p_day; v_name text;
begin
  perform public.require_active_staff();
  if p_request_id is not null then
    select * into gf from public.event_vip_gifts where request_id = p_request_id;
    if found then
      return jsonb_build_object('gift_id', gf.id, 'use_no', gf.use_no, 'product_id', gf.product_id,
        'product_name', (select pr.name from public.products pr where pr.id = gf.product_id), 'replayed', true);
    end if;
  end if;
  select * into g from public.event_guests where id = p_guest_id for update;
  if not found then raise exception 'Guest not found'; end if;
  if not public.event_can_run(g.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  select * into s from public.event_web_settings where event_id = g.event_id;
  if not found then raise exception 'This event has no website settings, so no VIP gifts'; end if;
  perform public.require_store_access(s.store_id);
  select * into e from public.events where id = g.event_id;
  if g.status <> 'registered' or g.source <> 'ticket' or g.ticket_option_id is distinct from s.vip_option_id then
    raise exception '% is not a VIP guest', g.name; end if;
  select * into gf from public.event_vip_gifts where guest_id = g.id and undone_at is null;
  if found then
    raise exception '% already has their gift (%, %)', g.name,
      (select pr.name from public.products pr where pr.id = gf.product_id), gf.use_no; end if;
  if p_product_id is null or not (p_product_id = any (s.gift_product_ids)) then
    raise exception 'Choose one of the event''s VIP gifts'; end if;
  -- The day it was given: the day picked at the door, else today when today
  -- is a day of the event (a gift handed over before the event has none).
  if v_day is null then
    v_day := (select d.day from public.event_days d where d.event_id = g.event_id and d.day = public.sg_today());
  elsif not exists (select 1 from public.event_days d where d.event_id = g.event_id and d.day = v_day) then
    raise exception '% is not a day of this event', to_char(v_day, 'DD Mon YYYY'); end if;
  v_use := public.record_stock_use('store', s.store_id, p_product_id, 1, 'Event gift',
                                   e.name || ' · VIP gift · ' || g.name);
  select id into v_use_id from public.stock_uses where use_no = v_use->>'use_no';
  select pr.name into v_name from public.products pr where pr.id = p_product_id;
  insert into public.event_vip_gifts (event_id, guest_id, guest_name, person_id, product_id, stock_use_id, use_no, day,
                                      given_by, request_id)
  values (g.event_id, g.id, g.name, (select p.id from public.event_registration_people p where p.vip_guest_id = g.id),
          p_product_id, v_use_id, v_use->>'use_no', v_day, auth.uid(), p_request_id)
  returning * into gf;
  perform public.write_audit_ex('event_guests', g.id, 'event_vip_gift_given', null,
    jsonb_build_object('event_id', g.event_id, 'gift_id', gf.id, 'product', v_name, 'use_no', gf.use_no, 'day', v_day),
    'events', null, s.store_id);
  return jsonb_build_object('gift_id', gf.id, 'use_no', gf.use_no, 'product_id', p_product_id, 'product_name', v_name,
                            'remaining', (v_use->>'remaining')::integer, 'replayed', false);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_vip_gift_undo(p_gift_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare gf public.event_vip_gifts%rowtype;
begin
  perform public.require_active_staff('{owner,manager}');
  select * into gf from public.event_vip_gifts where id = p_gift_id for update;
  if not found then raise exception 'Gift not found'; end if;
  if not public.event_can_run(gf.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  if gf.undone_at is not null then raise exception 'This gift is already undone'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason'; end if;
  update public.event_vip_gifts set undone_at = now(), undone_by = auth.uid(), undone_reason = btrim(p_reason)
   where id = gf.id;
  perform public.write_audit_ex('event_guests', gf.guest_id, 'event_vip_gift_undone',
    jsonb_build_object('gift_id', gf.id, 'use_no', gf.use_no), jsonb_build_object('undone', true), 'events', btrim(p_reason),
    (select s.store_id from public.event_web_settings s where s.event_id = gf.event_id));
  return jsonb_build_object('ok', true, 'use_no', gf.use_no,
    'message', format('Put the item back with Stock, Adjust (an adjustment request), quoting %s.', gf.use_no));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_planning_list(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.events%rowtype;
begin
  -- 436 (round 7, the owner 21 Oct 2026: S1, S3): every guest record of the event that shows
  -- planning answers (both records of a website VIP), with the titles and hours the staff form
  -- needs, for the Guests tab's badges and detail, the export and check-in. Whoever sees the
  -- event's guests (event_can_run, as event_guest_list).
  perform public.require_active_staff();
  select * into e from public.events where id = p_event_id;
  if not found then raise exception 'Event not found'; end if;
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  return jsonb_build_object(
    'talk_titles', to_jsonb(public.event_web_talk_titles(p_event_id)),
    'talk_titles_saved', exists (select 1 from public.event_web_settings s where s.event_id = p_event_id and s.talk_titles is not null),
    'hours', jsonb_build_object('daily_start', to_char(e.daily_start, 'HH24:MI'), 'daily_end', to_char(e.daily_end, 'HH24:MI')),
    'guests', coalesce((
      select jsonb_agg(jsonb_build_object('guest_id', g.id, 'days', to_jsonb(public.event_planning_days(a.guest_id)),
               'staff_name', pr.full_name) || (public.event_planning_record(g.id, null) - 'staff_id') order by g.id)
        from public.event_guests g
        cross join lateral (select public.event_planning_anchor(g.id) as anchor offset 0) an
        join public.event_planning_answers a on a.guest_id = an.anchor
        left join public.profiles pr on pr.id = a.staff_id
       where g.event_id = p_event_id), '[]'::jsonb));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_planning_save(p_guest_id uuid, p_answers jsonb, p_version integer, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.event_guests%rowtype; v_note text; v_anchor uuid; v_person uuid; v_cur jsonb; v_c jsonb;
begin
  -- 436 (round 7, the owner 21 Oct 2026: S1): a guest's answers changed on the Event page on
  -- their behalf (told by phone), by whoever can edit the guests (event_can_run, as
  -- event_save_guest; also a cancelled guest's, also after the event), with a note; audited
  -- (who, when, the old answers). A website person's answers are on their first record, so their
  -- VIP record edits the same answers. Based on the version shown: answers changed since are
  -- refused, saying by whom and when.
  perform public.require_active_staff();
  select * into g from public.event_guests where id = p_guest_id;
  if not found then raise exception 'Guest not found'; end if;
  if not exists (select 1 from public.events e where e.id = g.event_id and e.deleted_at is null) then
    raise exception 'Event not found'; end if;
  if not public.event_can_run(g.event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  if char_length(v_note) > 200 then raise exception 'The note is at most 200 characters'; end if;
  v_anchor := public.event_planning_anchor(g.id);
  select p.id into v_person from public.event_registration_people p
   where not p.is_test and coalesce(p.free_guest_id, p.vip_guest_id) = v_anchor order by p.created_at limit 1;
  perform pg_advisory_xact_lock(hashtextextended('event-planning:' || v_anchor::text, 0));
  v_cur := public.event_planning_record(v_anchor, null);
  v_c := public.event_planning_check(g.event_id, public.event_planning_days(v_anchor), p_answers, (v_cur->>'plan_id')::uuid);
  if jsonb_array_length(v_c->'problems') > 0 then
    raise exception using errcode = '22023',
      message = (select string_agg(pr.value->>'message', ' ' order by pr.n) from jsonb_array_elements(v_c->'problems') with ordinality pr(value, n)); end if;
  if v_cur is not null and v_cur->'answers' = v_c->'answers' then
    return jsonb_build_object('ok', true, 'guest_id', g.id, 'changed', false) || (v_cur - 'staff_id'); end if;
  if coalesce((v_cur->>'version')::integer, 0) <> coalesce(p_version, 0) then
    raise exception '%', format('These answers were changed %s on %s since you opened them. Close this and open them again.',
      case when v_cur->>'updated_by' = 'staff'
           then 'by ' || coalesce((select pr.full_name from public.profiles pr where pr.id = (v_cur->>'staff_id')::uuid), 'staff')
           else 'by the guest on the website' end,
      to_char((v_cur->>'updated_at')::timestamptz at time zone 'Asia/Singapore', 'DD Mon YYYY, FMHH12:MI am')); end if;
  return jsonb_build_object('ok', true, 'guest_id', g.id)
         || (public.event_planning_write(g.event_id, v_anchor, v_person, v_c->'answers', 'staff', v_note) - 'staff_id');
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_planning_summary(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.events%rowtype; s public.event_web_settings%rowtype; v_titles text[]; v_out jsonb; v_access boolean;
begin
  -- 436 (round 7, the owner 21 Oct 2026: S2): the planning summary of the event's registered
  -- guests (a website VIP once, on their VIP record): per day the food counts, the other food
  -- texts, allergies, who arrives late or leaves early (by time) and the access needs; the VIPs'
  -- food and allergies (the founder's dinner; VIP payments still waiting counted apart); the
  -- talks (every listed title, and chosen ones no longer listed; ignoring case, as the check
  -- matches them); how they heard; the questions for the speakers. Whoever sees the event's guests.
  -- Round 8 (the owner, 21 Oct 2026: P1): a customer holding two VIP payments for the event
  -- (paid or waiting) is counted once (on their VIP record, else the first), with the answers
  -- of their records and all their days, and the VIP block names them ("Two VIP payments:
  -- refund one").
  perform public.require_active_staff();
  select * into e from public.events where id = p_event_id and deleted_at is null;
  if not found then raise exception 'Event not found'; end if;
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  select * into s from public.event_web_settings where event_id = p_event_id;
  v_titles := public.event_web_talk_titles(p_event_id);
  v_access := s.event_id is not null and public.user_has_store_access(s.store_id);
  with dbl as materialized (
         select h.customer_id from public.event_vip_holders(p_event_id) h group by h.customer_id having count(*) > 1),
       -- such a customer is counted once (their VIP record, else the first) with the answers of
       -- their records (the VIP record's, else the first answered) and every day of their records
       -- (the review of round 8, 21 Oct 2026)
       g as materialized (
         select x.guest_id, x.name, x.customer_id, x.vip, x.ids,
                a.id as plan_id, a.food, a.food_other, a.allergy, a.allergy_details, a.timing, a.talks, a.access,
                a.access_other, a.heard_from, a.heard_from_other, a.question
           from (
             select y.guest_id, y.name, y.customer_id, y.vip,
                    row_number() over (partition by y.one order by y.vip desc, y.created_at, y.guest_id) as rn,
                    first_value(y.ans_id) over (partition by y.one order by y.ans_id is null, y.vip desc, y.created_at, y.guest_id
                                                rows between unbounded preceding and unbounded following) as best_ans,
                    array_agg(y.guest_id) over (partition by y.one) as ids
               from (
                 select gg.id as guest_id, gg.name, gg.customer_id, gg.created_at,
                        coalesce(gg.ticket_option_id = s.vip_option_id, false) as vip, ax.id as ans_id,
                        case when gg.customer_id in (select dbl.customer_id from dbl) then gg.customer_id else gg.id end as one
                   from public.event_guests gg
                   cross join lateral (select public.event_planning_anchor(gg.id) as anchor offset 0) an
                   left join public.event_planning_answers ax on ax.guest_id = an.anchor
                  where gg.event_id = p_event_id and gg.status = 'registered') y) x
           left join public.event_planning_answers a on a.id = x.best_ans
          where x.rn = 1),
       dd as (select d.day, row_number() over (order by d.day)::integer as n from public.event_days d where d.event_id = p_event_id),
       gd as materialized (
         select g.*, d.day from g
          cross join lateral (select distinct gdy.day from public.event_guest_days gdy where gdy.guest_id = any (g.ids)) d),
       pt as materialized (
         select gd.guest_id, gd.name, gd.vip, gd.day, (t.value->>'arrive')::time as arrive, (t.value->>'leave')::time as leave
           from gd cross join lateral jsonb_array_elements(coalesce(gd.timing, '[]'::jsonb)) t
          where (t.value->>'date')::date = gd.day and not coalesce((t.value->>'whole_day')::boolean, true))
  select jsonb_build_object(
    'event_id', p_event_id,
    'hours', jsonb_build_object('daily_start', to_char(e.daily_start, 'HH24:MI'), 'daily_end', to_char(e.daily_end, 'HH24:MI')),
    'registered', (select count(*) from g),
    'answered', (select count(*) from g where g.plan_id is not null),
    'days', coalesce((select jsonb_agg(jsonb_build_object(
        'day', dd.day, 'label', 'Day ' || dd.n,
        'registered', (select count(*) from gd where gd.day = dd.day),
        'answered', (select count(*) from gd where gd.day = dd.day and gd.plan_id is not null),
        'food', (select jsonb_build_object('no_preference', count(*) filter (where gd.food = 'no_preference'),
                   'vegetarian', count(*) filter (where gd.food = 'vegetarian'), 'vegan', count(*) filter (where gd.food = 'vegan'),
                   'halal', count(*) filter (where gd.food = 'halal'), 'no_beef', count(*) filter (where gd.food = 'no_beef'),
                   'other', count(*) filter (where gd.food = 'other'), 'not_said', count(*) filter (where gd.food is null))
                   from gd where gd.day = dd.day),
        'food_other', (select coalesce(jsonb_agg(jsonb_build_object('guest_id', gd.guest_id, 'name', gd.name, 'text', gd.food_other,
                         'vip', gd.vip) order by gd.name, gd.guest_id), '[]'::jsonb)
                         from gd where gd.day = dd.day and gd.food = 'other'),
        'allergies', (select coalesce(jsonb_agg(jsonb_build_object('guest_id', gd.guest_id, 'name', gd.name, 'text', gd.allergy_details,
                        'vip', gd.vip) order by gd.name, gd.guest_id), '[]'::jsonb)
                        from gd where gd.day = dd.day and gd.allergy = 'yes'),
        'late', (select coalesce(jsonb_agg(jsonb_build_object('guest_id', pt.guest_id, 'name', pt.name, 'time', to_char(pt.arrive, 'HH24:MI'),
                   'vip', pt.vip) order by pt.arrive, pt.name, pt.guest_id), '[]'::jsonb)
                   from pt where pt.day = dd.day and pt.arrive > coalesce(e.daily_start, time '00:00')),
        'early', (select coalesce(jsonb_agg(jsonb_build_object('guest_id', pt.guest_id, 'name', pt.name, 'time', to_char(pt.leave, 'HH24:MI'),
                    'vip', pt.vip) order by pt.leave, pt.name, pt.guest_id), '[]'::jsonb)
                    from pt where pt.day = dd.day and pt.leave < coalesce(e.daily_end, time '24:00')),
        'access', (select coalesce(jsonb_agg(jsonb_build_object('guest_id', gd.guest_id, 'name', gd.name, 'needs', to_jsonb(gd.access),
                     'other', gd.access_other, 'vip', gd.vip) order by gd.name, gd.guest_id), '[]'::jsonb)
                     from gd where gd.day = dd.day and (cardinality(gd.access) > 0 or gd.access_other is not null)))
        order by dd.day) from dd), '[]'::jsonb),
    'vip', case when s.event_id is not null then jsonb_build_object(
        'count', (select count(*) from g where g.vip),
        'answered', (select count(*) from g where g.vip and g.plan_id is not null),
        'food', (select jsonb_build_object('no_preference', count(*) filter (where g.food = 'no_preference'),
                   'vegetarian', count(*) filter (where g.food = 'vegetarian'), 'vegan', count(*) filter (where g.food = 'vegan'),
                   'halal', count(*) filter (where g.food = 'halal'), 'no_beef', count(*) filter (where g.food = 'no_beef'),
                   'other', count(*) filter (where g.food = 'other'), 'not_said', count(*) filter (where g.food is null))
                   from g where g.vip),
        'food_other', (select coalesce(jsonb_agg(jsonb_build_object('guest_id', g.guest_id, 'name', g.name, 'text', g.food_other,
                         'vip', true) order by g.name, g.guest_id), '[]'::jsonb)
                         from g where g.vip and g.food = 'other'),
        'allergies', (select coalesce(jsonb_agg(jsonb_build_object('guest_id', g.guest_id, 'name', g.name, 'text', g.allergy_details,
                        'vip', true) order by g.name, g.guest_id), '[]'::jsonb)
                        from g where g.vip and g.allergy = 'yes'),
        -- VIP payments still waiting (PayNow, bank or HitPay not confirmed yet): counted apart;
        -- someone whose VIP record stands (their VIP invoice reopened or part paid) is counted
        -- once, as the VIP they are (the review of round 7, 21 Oct 2026)
        'waiting', (select count(distinct case when p.customer_id in (select dbl.customer_id from dbl) then p.customer_id else p.id end)
                      from public.event_registration_people p where p.event_id = p_event_id and not p.is_test
                      and p.match <> 'closed' and public.event_web_person_vip_state(p.id) = 'pending'
                      and not exists (select 1 from public.event_guests vg
                                       where vg.id = p.vip_guest_id and vg.status = 'registered')
                      -- round 8: one customer with two VIP payments is counted once, as the VIP
                      -- they are when one of their VIP records stands
                      and not exists (select 1 from g where g.vip and g.customer_id = p.customer_id
                                                       and p.customer_id in (select dbl.customer_id from dbl))),
        -- round 8: each customer holding two VIP payments for this event (one to refund)
        'doubles', (select coalesce(jsonb_agg(jsonb_build_object('customer_id', c.id, 'name', c.full_name, 'vips', (
                        select jsonb_agg(jsonb_build_object('state', h.state, 'invoice_no', case when v_access then h.invoice_no end)
                                         order by h.since, h.invoice_no)
                          from public.event_vip_holders(p_event_id) h where h.customer_id = c.id))
                        order by c.full_name, c.id), '[]'::jsonb)
                      from dbl join public.customers c on c.id = dbl.customer_id)) end,
    'talks', coalesce((select jsonb_agg(jsonb_build_object('title', t.title, 'count', t.cnt, 'listed', t.listed)
                         order by t.cnt desc, t.pos nulls last, lower(t.title))
                         from (select l.title, l.pos, true as listed,
                                      (select count(*) from g
                                        where exists (select 1 from unnest(g.talks) gt where lower(gt) = lower(l.title))) as cnt
                                 from unnest(v_titles) with ordinality l(title, pos)
                               union all
                               select min(x.title), null::bigint, false, count(*)
                                 from g cross join unnest(g.talks) x(title)
                                where not exists (select 1 from unnest(v_titles) v where lower(v) = lower(x.title))
                                group by lower(x.title)) t), '[]'::jsonb),
    'heard_from', (select jsonb_build_object('tiktok', count(*) filter (where g.heard_from = 'tiktok'),
                     'facebook', count(*) filter (where g.heard_from = 'facebook'),
                     'instagram', count(*) filter (where g.heard_from = 'instagram'),
                     'google', count(*) filter (where g.heard_from = 'google'),
                     'whatsapp', count(*) filter (where g.heard_from = 'whatsapp'),
                     'friend_family', count(*) filter (where g.heard_from = 'friend_family'),
                     'staff', count(*) filter (where g.heard_from = 'staff'),
                     'email', count(*) filter (where g.heard_from = 'email'),
                     'other', count(*) filter (where g.heard_from = 'other'),
                     'not_said', count(*) filter (where g.heard_from is null)) from g),
    'heard_from_other', (select coalesce(jsonb_agg(jsonb_build_object('guest_id', g.guest_id, 'name', g.name, 'text', g.heard_from_other)
                           order by g.name, g.guest_id), '[]'::jsonb)
                           from g where g.heard_from = 'other' and g.heard_from_other is not null),
    'questions', (select coalesce(jsonb_agg(jsonb_build_object('guest_id', g.guest_id, 'name', g.name, 'text', g.question, 'vip', g.vip)
                    order by g.name, g.guest_id), '[]'::jsonb)
                    from g where g.question is not null))
    into v_out;
  return v_out;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_set_talks(p_event_id uuid, p_titles jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.event_web_settings%rowtype; v_new text[]; x text; v_t text;
begin
  -- 436 (round 7, the owner 21 Oct 2026: S4, Q4): the talk titles the website asks about, set
  -- on the Website tab by an Owner, Admin or Manager (as the venue): in order, each once (any
  -- case), at most 20 of at most 120 characters; [] = do not ask about talks; null = back to the
  -- suggested list. Answers already given keep their titles. Audited.
  perform public.require_active_staff('{owner,admin,manager}');
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  select * into s from public.event_web_settings where event_id = p_event_id for update;
  if not found then raise exception 'Save the website settings first'; end if;
  if p_titles is null or jsonb_typeof(p_titles) = 'null' then
    v_new := null;
  elsif jsonb_typeof(p_titles) <> 'array' then
    raise exception 'The talk titles are a list';
  else
    v_new := '{}';
    for x in select y.value from jsonb_array_elements_text(p_titles) y loop
      v_t := nullif(btrim(regexp_replace(coalesce(x, ''), '\s+', ' ', 'g')), '');
      continue when v_t is null;
      if char_length(v_t) > 120 then raise exception 'A talk title is at most 120 characters: %', left(v_t, 40) || '…'; end if;
      if exists (select 1 from unnest(v_new) y where lower(y) = lower(v_t)) then
        raise exception 'Each talk title only once: %', v_t; end if;
      v_new := v_new || v_t;
    end loop;
    if cardinality(v_new) > 20 then raise exception 'At most 20 talk titles'; end if;
  end if;
  update public.event_web_settings set talk_titles = v_new, updated_by = auth.uid(), updated_at = now() where event_id = p_event_id;
  perform public.write_audit_ex('event_web_settings', p_event_id, 'event_web_talks_set',
    jsonb_build_object('talk_titles', to_jsonb(s.talk_titles)), jsonb_build_object('talk_titles', to_jsonb(v_new)),
    'events', null, s.store_id);
  return jsonb_build_object('ok', true, 'talk_titles', to_jsonb(public.event_web_talk_titles(p_event_id)), 'saved', v_new is not null);
end $function$
$def$];

  -- ── event_ticket_line_check: its one anchor and patch ───────────────────────
  c_lc constant text := 'public.event_ticket_line_check(jsonb,date,uuid,integer)';
  c_lc_before constant text := '7f32dd2a6bf54bb147d6f8f728acb4f0';
  c_lc_after constant text := 'eb39ff10afedf8888e51b135d38ec616';
  c_lc_anchor constant text := $a$         and not exists (select 1 from public.web_orders w join public.web_order_channels c on c.key = w.channel
                          where w.id::text = current_setting('energia.paid_web_order', true)
                            and c.event_id = e.id and w.status in ('recorded', 'needs_review'))
$a$;
  c_lc_patch constant text := $r$         and not exists (select 1 from public.web_orders w join public.web_order_channels c on c.key = w.channel
                          where w.id::text = current_setting('energia.paid_web_order', true)
                            and c.event_id = e.id and w.status in ('recorded', 'needs_review'))
         -- 436: so is a paid VIP order's, while event_vip_make_invoices
         -- makes its invoices (it alone sets energia.paid_vip_order).
         and not public.event_vip_paid_order_open(e.id)
$r$;

  -- ── invoice_action_plan: its two anchors and patches (each anchor once) ─────
  c_pl constant text := 'public.invoice_action_plan(uuid,text,jsonb)';
  c_pl_before constant text := 'e117890fac11ea11435b691ca4787dec';
  c_pl_after constant text := '4af305c7b91bcbd8c36db21130307e0f';
  c_pl_anchor1 constant text := $a1$ -- 363: a therapy override's default amount is its line's figure after the
 -- money cap, so the pre-filled amount is one that can be taken.
$a1$;
  c_pl_patch1 constant text := $r1$ -- 436 (the Owner, 20 Oct 2026): a VIP's vouchers are free lines on their
 -- VIP invoice (a website VIP's, or one sold at the counter), so no money
 -- goes back for them. A refund that leaves the VIP ticket refunded in full
 -- takes back those not used yet (436's trigger on invoices, as a
 -- cancellation does); one recorded used stays recorded, is named here
 -- first, and the refund then needs a reason; one of those kinds given as a
 -- discount on a later invoice needs an Owner's or Manager's override, with
 -- a reason (the Owner, 21 Oct 2026), or a part refund instead.
 v_sum:=v_sum||coalesce(public.event_vip_refund_plan(i.id,p_action,v_sel)->'summary','[]'::jsonb);
 v_over:=v_over||coalesce(public.event_vip_refund_plan(i.id,p_action,v_sel)->'overrides','[]'::jsonb);
 v_block:=v_block||coalesce(public.event_vip_refund_plan(i.id,p_action,v_sel)->'blockers','[]'::jsonb);
 -- 363: a therapy override's default amount is its line's figure after the
 -- money cap, so the pre-filled amount is one that can be taken.
$r1$;
  c_pl_anchor2 constant text := $a2$        from jsonb_array_elements(v_sel) ll,
             jsonb_array_elements(coalesce(ll->'benefits','[]'::jsonb)) bb) s),
$a2$;
  c_pl_patch2 constant text := $r2$        from jsonb_array_elements(v_sel) ll,
             jsonb_array_elements(coalesce(ll->'benefits','[]'::jsonb)) bb) s)
      -- 436: a VIP's vouchers that the refund takes back
      ||coalesce(public.event_vip_refund_plan(i.id,p_action,v_sel)->'benefits','[]'::jsonb),
$r2$;

  -- ── The tables, as this migration makes them (columns; constraints by md5) ──
  c_tables constant text[] := array['event_web_settings', 'event_web_keys', 'event_web_requests', 'event_registrations', 'event_registration_people', 'event_vip_orders', 'event_vip_order_people', 'event_vip_gifts', 'event_planning_answers'];
  c_shapes constant text[] := array[
    'acting_profile_id uuid not null|bank_payment_method_id uuid|code text not null|created_at timestamp with time zone not null|created_by uuid|event_id uuid not null|gift_product_ids uuid[] not null|hitpay_payment_method_id uuid|last_sync_at timestamp with time zone|last_test_sync_at timestamp with time zone|mode text not null|paynow_payment_method_id uuid|source_details text|source_option_id uuid|store_id uuid not null|sync_url text|talk_titles text[]|updated_at timestamp with time zone not null|updated_by uuid|venue text|vip_option_id uuid|vip_voucher_ids uuid[] not null',
    'created_at timestamp with time zone not null|created_by uuid not null|event_id uuid not null|id uuid not null|key_hash text not null|key_hint text not null|kind text not null|label text|last_used_at timestamp with time zone|revoked_at timestamp with time zone|revoked_by uuid|revoked_reason text',
    'body_md5 text|is_write boolean not null|key_id uuid not null|outcome text|received_at timestamp with time zone not null|request_id uuid not null|response jsonb|type text not null',
    'answer jsonb|created_at timestamp with time zone not null|event_id uuid not null|id uuid not null|is_test boolean not null|key_id uuid|people_count integer not null|people_md5 text not null|referral_code text|referral_state text not null|referrer_customer_id uuid|registration_id text not null|submitted_at timestamp with time zone',
    'candidate_customer_ids uuid[] not null|created_at timestamp with time zone not null|customer_id uuid|days date[] not null|email text|event_id uuid not null|first_name text not null|free_guest_id uuid|full_name text not null|hold_reason text|id uuid not null|is_test boolean not null|last_name text|match text not null|phone text not null|phone_norm text not null|position integer not null|referral_outcome text|referral_self_by text[]|registration_ref uuid not null|resolution_note text|resolved_at timestamp with time zone|resolved_by uuid|test_outcome jsonb|updated_at timestamp with time zone not null|upgrade_token text not null|vip_guest_id uuid|vip_requested boolean not null',
    'amount_paid_cents integer|amount_total_cents integer not null|body_md5 text|checkout_opened_at timestamp with time zone|created_at timestamp with time zone not null|event_id uuid not null|expires_at timestamp with time zone|hitpay_payment_id text|hitpay_payment_request_id text|id uuid not null|is_test boolean not null|key_id uuid|livemode boolean|order_id text not null|paid_at timestamp with time zone|paid_on date|paid_received_at timestamp with time zone|payer_email text|payer_name text|payer_phone text|provider text not null|quantity integer not null|reason_before_dismiss text|reference text|refund_noted_at timestamp with time zone|refunded_cents_total integer not null|refusal text|review_reason text|status text not null|status_before_dismiss text|test_note text|test_would text|unit_amount_cents integer not null|updated_at timestamp with time zone not null|updated_by uuid|waiting_for_match boolean not null',
    'invoice_id uuid|invoice_item_id uuid|order_ref uuid not null|person_id uuid not null|position integer not null',
    'day date|event_id uuid not null|given_at timestamp with time zone not null|given_by uuid|guest_id uuid|guest_name text not null|id uuid not null|person_id uuid|product_id uuid not null|request_id uuid|stock_use_id uuid|undone_at timestamp with time zone|undone_by uuid|undone_reason text|use_no text',
    'access text[] not null|access_other text|allergy text|allergy_details text|answered_by text not null|created_at timestamp with time zone not null|event_id uuid not null|food text|food_other text|guest_id uuid not null|heard_from text|heard_from_other text|id uuid not null|person_id uuid|question text|staff_id uuid|talks text[] not null|timing jsonb not null|updated_at timestamp with time zone not null|version integer not null'];
  c_cons constant text[] := array['3e83d3fa119f5999789b6fb8c9e459b0', 'ca58ac13e0f5c1f8fb5ce25e1088c8fb', '61fc0699d98b9cf9d320968abb900b39', '53ee7fee3ee9f8bfae737171b31aff7c', '7643ed9f78c25bbd51a19a4fec0dc3ed', '74a469774620ad8eb8bb71114fb4f0ae', '594f6dfe5211fbd90ab02513b32d2fa3', '568c42c27bbf09c20ee3af206767c89b', 'a780392f64337eafb557c5ecce6852aa'];
  c_trigs constant text[] := array[
    'CREATE TRIGGER event_guests_vip_follow AFTER UPDATE OF status ON public.event_guests FOR EACH ROW WHEN ((old.status IS DISTINCT FROM new.status)) EXECUTE FUNCTION trg_event_vip_guest_follow()',
    'CREATE TRIGGER event_guests_vip_parked BEFORE UPDATE OF status ON public.event_guests FOR EACH ROW EXECUTE FUNCTION trg_event_vip_parked_guest()',
    'CREATE TRIGGER events_web_delete_guard BEFORE UPDATE OF deleted_at ON public.events FOR EACH ROW EXECUTE FUNCTION trg_event_web_delete_guard()',
    'CREATE TRIGGER invoices_vip_vouchers_follow_refund AFTER UPDATE OF status, paid_amount ON public.invoices FOR EACH ROW WHEN (((new.status IS DISTINCT FROM old.status) OR (new.paid_amount IS DISTINCT FROM old.paid_amount))) EXECUTE FUNCTION trg_event_vip_refund_vouchers()',
    'CREATE TRIGGER referral_signup_checks_event_web_decided AFTER UPDATE OF status ON public.referral_signup_checks FOR EACH ROW WHEN (((old.status = ''pending''::text) AND (new.status <> ''pending''::text))) EXECUTE FUNCTION trg_event_web_referral_check_decided()',
    'CREATE TRIGGER approval_requests_event_vip_reason AFTER UPDATE OF payload ON public.approval_requests FOR EACH ROW WHEN (((new.status = ''approved''::approval_status) AND (new.request_type = ANY (ARRAY[''invoice_refund''::text, ''invoice_cancel''::text])) AND ((old.payload -> ''overrides''::text) IS DISTINCT FROM (new.payload -> ''overrides''::text)))) EXECUTE FUNCTION trg_event_vip_used_later_reason()'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; k int; v_new int[] := '{}'; v_tables_new boolean; v_patch boolean := false;
  v_lc_acl text; v_missing int; d2 text; v_pl_patch boolean := false; v_pl_acl text;
  -- the self-test's made-up records
  t_owner uuid; t_store uuid; t_event uuid; t_opt uuid; t_pm uuid; t_cust uuid; t_live text; t_test text;
  t_ans jsonb; t_p1 uuid; t_p2 uuid; t_tok text; t_free uuid; t_vip uuid; t_ph1 text; t_ph2 text; t_ph3 text; t_ph4 text; t_sfx text;
  t_phones text[]; t_vch uuid; t_inv uuid; t_item uuid; t_pay uuid;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 20 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is installed unless all pass ─────────────────────
  for r in select * from (values
      ('create_invoice_with_details(uuid,uuid,jsonb,jsonb)', '0f408a1a350b68fd86cd24109c85c05b'),
      ('record_invoice_payment(uuid,jsonb,uuid)', 'c3da81f28d5a24a1c5f336527cfc33a4'),
      ('create_customer_quick(text,text,text,text,date,text,text,text,text,uuid,uuid)', '9ff9031d3b40029a19c729a512e99798'),
      ('customer_names_match(text,text)', 'ef1af52e4888cefb6037a2291f4e011d'),
      ('customer_name_words(text)', 'a7507abf0f15abd923dff59508b269c1'),
      ('customer_email_match_key(text)', 'be468815c9626fff1728e2cfcd484b66'),
      ('customer_phone_name_matches(text,text)', '1bdf8322972b6671b7cbb08bc8211f8a'),
      ('require_resolved_customer_identity(text,text)', '5bde1a418363442ec27e2944442f5874'),
      ('normalize_customer_phone(text)', 'b2bfac910e0c9eff402ba44e19750bee'),
      ('normalize_customer_match_name(text)', '0572764712e179dc606c66f9f3dbaa03'),
      ('inspect_customer_phone(text,text)', '6672c4d1963996f3b601896f4a55916e'),
      ('set_customer_source(uuid,uuid,text,text)', 'dbed868630d8ac8ed89a47838a918fa0'),
      ('record_stock_use(text,uuid,uuid,integer,text,text)', 'db278faba262b0a3801944cd821a62fd'),
      ('issue_sold_vouchers_for_invoice(uuid)', '0dbb4bc74411b6d4f0535f661a8c09ee'),
      ('earn_invoice_commission(uuid)', '6156b2e1ee51da5146a5a7acc16091ce'),
      ('cancel_invoice_recorded(uuid,text,uuid)', 'de52d9dbaef8ab15163bef35cb9d733d'),
      ('reopen_invoice(uuid,text,uuid)', 'c9fcab7adfccdaeba1eb8dee4134ba47'),
      ('event_sync_ticket_line(uuid,jsonb)', '3960c8a26f123b66c48bcca32c81244e'),
      ('event_ticket_guests_follow_line(uuid)', '1fd8941bc9491741938c70e6dc327435'),
      ('trg_event_guests_follow_invoice()', '013dd0eb837f1cb90b183877c914d55a'),
      ('event_check_in(uuid,date,boolean,text,boolean)', '606cdbba5f8a6197fb1c5b216daf1e41'),
      ('event_guest_list(uuid)', 'cbe2f3ef06fe97e59fc2e3b19fd35cac'),
      ('event_can_run(uuid)', 'dac12d0086533bb528e847eb828809df'),
      ('event_delete(uuid,text)', 'c1741487cf111d0a65faec47e5b2ae18'),
      ('event_save_guest(jsonb)', 'f828b8558735696b392ae0f2e6c64a24'),
      ('event_set_guest_cancelled(uuid,boolean,text)', 'f58e462efb1f14e604ee62a7feec6b09'),
      ('event_ticket_price(uuid,date)', 'f1bbea829863fbc743721dd82ed087ca'),
      ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
      ('require_store_access(uuid)', 'f9332fd2f0092337d64501d8a647c23f'),
      ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
      ('web_order_uuid(text)', '2ab2b36e0b5db1f57a660efc00e33cae'),
      ('is_owner()', '8eb059153c36a23f1d22b122543a7787'),
      ('is_manager_or_above()', 'e87f6da4a7284374f0e2bc5b55c502be'),
      ('is_owner_or_manager()', 'a98e50f1b6d3fa1e6c62cf52a8073cc8'),
      ('user_has_store_access(uuid)', '708992afaa6c3951f6329239b742987c'),
      ('current_user_role()', '519b0a33a3548f970c5d585b6e76a389'),
      ('sg_today()', '1c1289f18e24d8370e9a6364c9c06fca'),
      ('voucher_price_for(uuid,uuid,boolean)', 'f19a5200cedce5cebf1544b98b3d72a9'),
      ('public_affiliate_referral_info(text)', '17040ff07ab8e18fc9d8afe22afc9291'),
      ('merge_customer_records(uuid,uuid,text,uuid)', '099ecf3aae30b5faaf8fb36bc15ce888'),
      ('next_stock_use_no()', '9387b31a3ee47b8df262b7ba1e473933'),
      ('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', 'e6f6c3cbf1bda3574d748bde2db5a759'),
      ('resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)', '201f08ebf14a64cd88d411a7cfb4c9c4'),
      ('request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)', '4360d74462ed1fc950b6bd8b5157b3ae'),
      ('invoice_charge_total(uuid)', '8297147511ba285db2279598f3d727fb'),
      ('event_ticket_line_refunded(uuid)', 'b9066789889c8225897ff979deefc8cc'),
      ('invoice_discounted_line_value(uuid)', 'ead4a430c3abd1e3f953912867ca4fe6'),
      ('cancelled_invoice_used_value(uuid)', '70f684f1a8f0a4f42774394062e4df19'),
      ('invoice_voucher_reopen_candidates(uuid)', '20405a96c8780eac6425a5dae59c29e1'),
      ('apply_reopened_invoice_vouchers()', '71d50be41b73decceb0b20f8597dd4fa'),
      ('adjust_invoice_line_commission_refunds(uuid,uuid[])', '5959dec0fedd5fd45fb4615da413b20c')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '436: public.% is missing or not the version this was tested against (the stack after 430). Re-read it and re-test before applying.', r.fn;
    end if;
  end loop;
  if to_regprocedure('extensions.digest(text,text)') is null or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception '436: pgcrypto is not in the extensions schema'; end if;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    raise exception '436: pg_net (net.http_post) is missing; 381 installs it'; end if;

  -- The columns 436 reads and writes, as read on 20 Oct 2026.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values
      ('events', 'id uuid'), ('events', 'name text'), ('events', 'daily_start time without time zone'),
      ('events', 'daily_end time without time zone'), ('events', 'is_active boolean'), ('events', 'deleted_at timestamp with time zone'),
      ('event_days', 'event_id uuid'), ('event_days', 'day date'), ('event_days', 'capacity integer'),
      ('event_stores', 'event_id uuid'), ('event_stores', 'store_id uuid'),
      ('event_ticket_options', 'event_id uuid'), ('event_ticket_options', 'days_count integer'),
      ('event_ticket_options', 'price numeric(12,2)'), ('event_ticket_options', 'is_active boolean'),
      ('event_guests', 'event_id uuid'), ('event_guests', 'name text'), ('event_guests', 'phone text'),
      ('event_guests', 'customer_id uuid'), ('event_guests', 'source text'), ('event_guests', 'invoice_id uuid'),
      ('event_guests', 'invoice_item_id uuid'), ('event_guests', 'ticket_option_id uuid'), ('event_guests', 'line_position integer'),
      ('event_guests', 'registered_by uuid'), ('event_guests', 'notes text'), ('event_guests', 'status text'),
      ('event_guests', 'cancelled_reason text'), ('event_guests', 'cancelled_at timestamp with time zone'),
      ('event_guests', 'created_by uuid'), ('event_guests', 'updated_by uuid'),
      ('event_guest_days', 'guest_id uuid'), ('event_guest_days', 'day date'),
      ('event_guest_days', 'attended_at timestamp with time zone'), ('event_guest_days', 'checked_in_by uuid'),
      ('event_guest_days', 'check_in_code text'),
      ('customers', 'full_name text'), ('customers', 'phone text'), ('customers', 'email text'), ('customers', 'referred_by uuid'),
      ('customers', 'referral_source text'), ('customers', 'referral_code_used text'), ('customers', 'source_option_id uuid'),
      ('customers', 'source_label text'), ('customers', 'source_details text'),
      ('customers', 'source_updated_at timestamp with time zone'), ('customers', 'deleted_at timestamp with time zone'),
      ('customer_affiliates', 'customer_id uuid'), ('customer_affiliates', 'referral_code text'),
      ('customer_affiliates', 'status text'), ('customer_affiliates', 'manually_suspended boolean'),
      ('referral_signup_events', 'referral_code text'), ('referral_signup_events', 'referrer_customer_id uuid'),
      ('referral_signup_events', 'new_customer_id uuid'), ('referral_signup_events', 'normalized_phone text'),
      ('referral_signup_events', 'outcome text'), ('referral_signup_checks', 'customer_id uuid'),
      ('referral_signup_checks', 'referrer_customer_id uuid'), ('referral_signup_checks', 'referral_code text'),
      ('referral_signup_checks', 'normalized_phone text'), ('referral_signup_checks', 'phone_shared_with uuid[]'),
      ('referral_signup_checks', 'status text'),
      ('stock_uses', 'use_no text'), ('stock_uses', 'store_id uuid'), ('store_inventory', 'current_qty integer'),
      ('invoices', 'invoice_no text'), ('invoices', 'total_amount numeric(12,2)'), ('invoice_items', 'event_days date[]'),
      ('invoice_items', 'event_ticket_option_id uuid'), ('payment_methods', 'is_wallet_credit boolean'),
      ('customer_source_options', 'requires_details boolean'), ('profiles', 'invitation_status text'),
      ('vouchers', 'deleted_at timestamp with time zone'), ('products', 'deleted_at timestamp with time zone'),
      -- a website VIP refunded in full (the Owner, 20 Oct 2026)
      ('invoices', 'status invoice_status'), ('invoices', 'paid_amount numeric(12,2)'), ('invoices', 'deleted_at timestamp with time zone'),
      ('invoices', 'store_id uuid'), ('invoice_items', 'is_foc boolean'), ('invoice_items', 'line_kind invoice_line_kind'),
      ('invoice_benefit_values', 'invoice_id uuid'), ('invoice_benefit_values', 'invoice_item_id uuid'),
      ('invoice_benefit_values', 'reward_voucher_id uuid'), ('invoice_benefit_values', 'granted_value numeric(12,2)'),
      ('invoice_benefit_values', 'cancelled_unused_value numeric(12,2)'), ('customer_reward_vouchers', 'status text'),
      ('customer_reward_vouchers', 'quantity integer'), ('customer_reward_vouchers', 'voucher_id uuid'),
      ('customer_reward_vouchers', 'store_id uuid'), ('customer_reward_vouchers', 'customer_id uuid'),
      ('customer_reward_vouchers', 'notes text'), ('vouchers', 'qty_type voucher_qty_type'),
      ('voucher_store_stock', 'current_qty integer'), ('approval_requests', 'related_record_id uuid'),
      ('approval_requests', 'payload jsonb'),
      -- a VIP sold at the counter, a VIP voucher used on a later invoice, an
      -- invoice reopened and paid again (the Owner, 20 Oct 2026, round 3)
      ('invoices', 'customer_id uuid'), ('invoices', 'created_at timestamp with time zone'),
      ('invoices', 'discount_voucher_id uuid'), ('invoice_items', 'line_voucher_id uuid'), ('invoice_items', 'voucher_id uuid'),
      ('invoice_reopen_vouchers', 'benefit_id uuid'), ('invoice_reopen_vouchers', 'quantity integer'),
      ('invoice_reopen_vouchers', 'applied_at timestamp with time zone'), ('invoices', 'reopened_at timestamp with time zone'),
      ('invoice_refunds', 'amount numeric(12,2)'), ('invoice_refunds', 'created_at timestamp with time zone'),
      -- a counter VIP for several, each VIP's share; the refund written by the call being run
      ('invoice_items', 'quantity integer'), ('invoice_refunds', 'invoice_id uuid'), ('invoice_refunds', 'outcome jsonb'),
      ('invoice_refunds', 'request_id uuid'), ('invoice_benefit_transfers', 'source_benefit_id uuid'),
      ('invoice_benefit_transfers', 'replacement_benefit_id uuid'), ('invoice_benefit_transfers', 'transferred_value numeric(12,2)'),
      -- someone else on the affiliate's own phone or email: referred once checked (the Owner, 20 Oct 2026, ~20:15)
      ('referral_signup_checks', 'id uuid'), ('referral_signup_checks', 'decided_at timestamp with time zone'),
      ('customers', 'referred_at timestamp with time zone'), ('customers', 'created_at timestamp with time zone'),
      ('commissions', 'invoice_id uuid'),
      -- an older record merged into theirs before the check (merge_customer_records' audit row)
      ('audit_logs', 'record_id uuid'), ('audit_logs', 'action text'), ('audit_logs', 'new_data jsonb'),
      ('audit_logs', 'created_at timestamp with time zone'), ('audit_logs', 'table_name text'),
      -- an Owner's or Manager's override of the later-use rule (the Owner, 21 Oct 2026)
      ('approval_requests', 'id uuid'), ('approval_requests', 'request_type text'), ('approval_requests', 'status approval_status'),
      ('approval_requests', 'approved_by uuid'), ('approval_requests', 'approved_at timestamp with time zone'),
      ('approval_requests', 'created_at timestamp with time zone'),
      -- planning answers name the staff member; the commission earned on a check is dated then (round 7)
      ('profiles', 'full_name text'), ('commissions', 'invoice_paid_date date')) x(t, c)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attnum > 0 and not a.attisdropped
                        and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.c);
  if v is not null then
    raise exception '436: these columns are missing or not as read on 20 Oct 2026: %', v; end if;
  -- The sign-up check's decisions, as 425 made them (436's trigger follows them).
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.referral_signup_checks'::regclass and c.conname = 'referral_signup_checks_status_check')
     is distinct from 'CHECK ((status = ANY (ARRAY[''pending''::text, ''different_person''::text, ''same_person''::text])))' then
    raise exception '436: referral_signup_checks'' statuses are not 425''s (pending, different_person, same_person)'; end if;

  -- The tables: all missing, or all exactly this migration's.
  select count(*) into n from unnest(c_tables) t where to_regclass('public.' || t) is not null;
  if n not in (0, cardinality(c_tables)) then
    raise exception '436: only % of its % tables exist: re-check what was applied', n, cardinality(c_tables); end if;
  v_tables_new := n = 0;
  if not v_tables_new then
    for k in 1 .. cardinality(c_tables) loop
      select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                        '|' order by a.attname) into v
        from pg_attribute a where a.attrelid = ('public.' || c_tables[k])::regclass and a.attnum > 0 and not a.attisdropped;
      if v is distinct from c_shapes[k] then
        raise exception '436: public.% exists and is not this migration''s (%)', c_tables[k], v; end if;
      select md5(string_agg(conname || ' ' || pg_get_constraintdef(oid), '|' order by conname)) into v
        from pg_constraint where conrelid = ('public.' || c_tables[k])::regclass;
      if v is distinct from c_cons[k] then
        raise exception '436: the constraints of public.% are not this migration''s', c_tables[k]; end if;
    end loop;
    raise notice '436: its tables are already there, as this migration makes them; left alone';
  end if;

  -- The new functions: each text is the tested one; each is missing, or
  -- already this version (left alone); no other function takes their names.
  for k in 1 .. cardinality(c_sigs) loop
    if md5(c_defs[k]) <> c_md5s[k] then
      raise exception '436: the text of public.% is not the tested one (md5 %)', c_sigs[k], md5(c_defs[k]); end if;
    if to_regprocedure('public.' || c_sigs[k]) is null then
      v_new := v_new || k;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]))) <> c_md5s[k] then
      raise exception '436: public.% exists and is not this migration''s version', c_sigs[k];
    end if;
  end loop;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in (select split_part(s, '(', 1) from unnest(c_sigs) s)
     and not (p.oid::regprocedure::text = any (c_sigs));
  if v is not null then raise exception '436: another function takes one of its names: %', v; end if;
  if cardinality(v_new) not in (0, cardinality(c_sigs)) then
    raise notice '436: % of its % functions were already there (left alone)', cardinality(c_sigs) - cardinality(v_new), cardinality(c_sigs);
  end if;

  -- event_ticket_line_check: BEFORE (patched) or AFTER (left alone).
  d := pg_get_functiondef(c_lc::regprocedure);
  if md5(d) = c_lc_after then
    raise notice '436: % is already this version; left alone', c_lc;
  elsif md5(d) <> c_lc_before then
    raise exception '436: % is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_lc, md5(d);
  else
    n := (length(d) - length(replace(d, c_lc_anchor, ''))) / length(c_lc_anchor);
    if n <> 1 then raise exception '436: the anchor of % was found % times, not once', c_lc, n; end if;
    d := replace(d, c_lc_anchor, c_lc_patch);
    if md5(d) <> c_lc_after then
      raise exception '436: the text built for % is not the tested one (md5 %)', c_lc, md5(d); end if;
    v_patch := true;
  end if;
  select coalesce(p.proacl::text, '') into v_lc_acl from pg_proc p where p.oid = c_lc::regprocedure;

  -- invoice_action_plan (417's): BEFORE (patched, each anchor once) or AFTER (left alone).
  d2 := pg_get_functiondef(c_pl::regprocedure);
  if md5(d2) = c_pl_after then
    raise notice '436: % is already this version; left alone', c_pl;
  elsif md5(d2) <> c_pl_before then
    raise exception '436: % is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_pl, md5(d2);
  else
    n := (length(d2) - length(replace(d2, c_pl_anchor1, ''))) / length(c_pl_anchor1);
    if n <> 1 then raise exception '436: the first anchor of % was found % times, not once', c_pl, n; end if;
    n := (length(d2) - length(replace(d2, c_pl_anchor2, ''))) / length(c_pl_anchor2);
    if n <> 1 then raise exception '436: the second anchor of % was found % times, not once', c_pl, n; end if;
    d2 := replace(replace(d2, c_pl_anchor1, c_pl_patch1), c_pl_anchor2, c_pl_patch2);
    if md5(d2) <> c_pl_after then
      raise exception '436: the text built for % is not the tested one (md5 %)', c_pl, md5(d2); end if;
    v_pl_patch := true;
  end if;
  select coalesce(p.proacl::text, '') into v_pl_acl from pg_proc p where p.oid = c_pl::regprocedure;

  -- The triggers: each missing, or exactly this migration's.
  for r in select * from (values (1, 'event_guests', 'event_guests_vip_follow'), (2, 'event_guests', 'event_guests_vip_parked'),
                                 (3, 'events', 'events_web_delete_guard'), (4, 'invoices', 'invoices_vip_vouchers_follow_refund'),
                                 (5, 'referral_signup_checks', 'referral_signup_checks_event_web_decided'),
                                 (6, 'approval_requests', 'approval_requests_event_vip_reason')) x(i, t, name) loop
    select pg_get_triggerdef(tg.oid) into v from pg_trigger tg where tg.tgname = r.name and not tg.tgisinternal;
    if v is not null and v <> c_trigs[r.i] then
      raise exception '436: a trigger % exists and is not this migration''s (%)', r.name, v; end if;
  end loop;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  if v_tables_new then
    create table public.event_web_settings (
      event_id uuid primary key references public.events(id),
      code text not null constraint event_web_settings_code_check check (code ~ '^[A-Z0-9][A-Z0-9-]{2,39}$'),
      mode text not null default 'off' constraint event_web_settings_mode_check check (mode in ('off', 'record_only', 'live')),
      venue text constraint event_web_settings_venue_check check (venue is null or (venue = btrim(venue) and char_length(venue) between 1 and 300)),
      store_id uuid not null references public.stores(id),
      acting_profile_id uuid not null references public.profiles(id),
      vip_option_id uuid references public.event_ticket_options(id) on delete set null,
      vip_voucher_ids uuid[] not null default '{}'::uuid[],
      gift_product_ids uuid[] not null default '{}'::uuid[],
      hitpay_payment_method_id uuid references public.payment_methods(id),
      paynow_payment_method_id uuid references public.payment_methods(id),
      bank_payment_method_id uuid references public.payment_methods(id),
      source_option_id uuid references public.customer_source_options(id),
      source_details text,
      sync_url text constraint event_web_settings_sync_url_check check (sync_url is null or sync_url ~ '^https://[^[:space:]]+$'),
      -- 436 (round 7): the talks the website asks about (Q4): null until saved (the suggested list); '{}': none.
      talk_titles text[] constraint event_web_settings_talks_check
        check (talk_titles is null or (cardinality(talk_titles) <= 20 and array_position(talk_titles, null) is null)),
      last_sync_at timestamptz,
      last_test_sync_at timestamptz,
      created_by uuid references public.profiles(id) on delete set null,
      created_at timestamptz not null default now(),
      updated_by uuid references public.profiles(id) on delete set null,
      updated_at timestamptz not null default now(),
      constraint event_web_settings_code_key unique (code));

    create table public.event_web_keys (
      id uuid primary key default gen_random_uuid(),
      event_id uuid not null references public.events(id),
      kind text not null constraint event_web_keys_kind_check check (kind in ('live', 'test')),
      key_hash text not null constraint event_web_keys_hash_check check (key_hash ~ '^[0-9a-f]{64}$'),
      key_hint text not null,
      label text,
      created_by uuid not null references public.profiles(id),
      created_at timestamptz not null default now(),
      last_used_at timestamptz,
      revoked_at timestamptz,
      revoked_by uuid references public.profiles(id),
      revoked_reason text,
      constraint event_web_keys_hash_key unique (key_hash),
      constraint event_web_keys_revoked_check check ((revoked_at is null) = (revoked_by is null)));
    create index event_web_keys_event_idx on public.event_web_keys (event_id);

    create table public.event_web_requests (
      key_id uuid not null references public.event_web_keys(id) on delete cascade,
      request_id uuid not null,
      type text not null,
      is_write boolean not null,
      body_md5 text,
      outcome text,
      response jsonb,
      received_at timestamptz not null default now(),
      constraint event_web_requests_pkey primary key (key_id, request_id));
    create index event_web_requests_key_time_idx on public.event_web_requests (key_id, received_at desc);
    create index event_web_requests_time_idx on public.event_web_requests (received_at);

    create table public.event_registrations (
      id uuid primary key default gen_random_uuid(),
      event_id uuid not null references public.events(id),
      registration_id text not null constraint event_registrations_id_check check (registration_id ~ '^REG-[0-9]{8}-[0-9A-F]{8}$'),
      is_test boolean not null default false,
      key_id uuid references public.event_web_keys(id) on delete set null,
      submitted_at timestamptz,
      referral_code text,
      referrer_customer_id uuid references public.customers(id) on delete set null,
      referral_state text not null default 'none'
        constraint event_registrations_referral_check check (referral_state in ('valid', 'link_off', 'unknown_code', 'none')),
      people_count integer not null constraint event_registrations_people_check check (people_count between 1 and 10),
      people_md5 text not null,
      answer jsonb,
      created_at timestamptz not null default now(),
      constraint event_registrations_event_reg_key unique (event_id, registration_id));

    create table public.event_registration_people (
      id uuid primary key default gen_random_uuid(),
      registration_ref uuid not null references public.event_registrations(id) on delete cascade,
      event_id uuid not null references public.events(id),
      position integer not null constraint event_registration_people_position_check check (position between 1 and 10),
      is_test boolean not null default false,
      first_name text not null,
      last_name text,
      full_name text not null,
      phone text not null,
      phone_norm text not null,
      email text,
      days date[] not null constraint event_registration_people_days_check check (cardinality(days) >= 1),
      vip_requested boolean not null default false,
      customer_id uuid references public.customers(id) on delete set null,
      match text not null constraint event_registration_people_match_check
        check (match in ('exact', 'same_words', 'new_customer', 'held', 'staff_attached', 'staff_created', 'closed', 'test')),
      hold_reason text constraint event_registration_people_hold_check
        check (hold_reason is null or hold_reason in ('phone_in_use', 'email_in_use', 'phone_and_email_in_use',
                                                      'several_name_matches', 'legacy_ambiguous', 'affiliate_name')),
      candidate_customer_ids uuid[] not null default '{}'::uuid[],
      resolved_by uuid references public.profiles(id) on delete set null,
      resolved_at timestamptz,
      resolution_note text,
      free_guest_id uuid references public.event_guests(id) on delete set null,
      vip_guest_id uuid references public.event_guests(id) on delete set null,
      referral_outcome text constraint event_registration_people_referral_check
        check (referral_outcome is null or referral_outcome in ('created', 'phone_shared', 'already_customer', 'self',
                                                                'link_off', 'unknown_code', 'link_limit', 'held',
                                                                'check_waiting', 'check_confirmed', 'check_same_person')),
      -- No self-referral (the owner, 20 Oct 2026): how a person who came through
      -- an affiliate's link was found to be that affiliate (their customer record
      -- is hers; the same words in the name; her phone; her email inbox).
      referral_self_by text[] constraint event_registration_people_self_check
        check (referral_self_by is null
               or (cardinality(referral_self_by) between 1 and 4 and referral_self_by <@ array['customer', 'name', 'phone', 'email'])),
      upgrade_token text not null constraint event_registration_people_token_check check (upgrade_token ~ '^vip_[a-z2-7]{26}$'),
      test_outcome jsonb,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      constraint event_registration_people_token_key unique (upgrade_token),
      constraint event_registration_people_position_key unique (registration_ref, position));
    create index event_registration_people_event_idx on public.event_registration_people (event_id);
    create index event_registration_people_phone_idx on public.event_registration_people (phone_norm);
    create index event_registration_people_customer_idx on public.event_registration_people (customer_id) where customer_id is not null;
    create index event_registration_people_free_idx on public.event_registration_people (free_guest_id) where free_guest_id is not null;
    create index event_registration_people_vip_idx on public.event_registration_people (vip_guest_id) where vip_guest_id is not null;

    create table public.event_vip_orders (
      id uuid primary key default gen_random_uuid(),
      event_id uuid not null references public.events(id),
      order_id text not null constraint event_vip_orders_order_check check (order_id ~ '^VIP-[0-9]{8}-[0-9A-F]{8}$'),
      provider text not null constraint event_vip_orders_provider_check check (provider in ('hitpay', 'paynow', 'bank')),
      status text not null constraint event_vip_orders_status_check
        check (status in ('pending', 'recorded', 'invoiced', 'needs_review', 'refused', 'dismissed', 'test')),
      is_test boolean not null default false,
      livemode boolean,
      key_id uuid references public.event_web_keys(id) on delete set null,
      unit_amount_cents integer not null constraint event_vip_orders_unit_check check (unit_amount_cents >= 0),
      quantity integer not null constraint event_vip_orders_quantity_check check (quantity between 1 and 10),
      amount_total_cents integer not null constraint event_vip_orders_total_check check (amount_total_cents >= 0),
      amount_paid_cents integer,
      payer_name text,
      payer_email text,
      payer_phone text,
      checkout_opened_at timestamptz,
      expires_at timestamptz,
      hitpay_payment_request_id text,
      hitpay_payment_id text,
      paid_at timestamptz,
      paid_received_at timestamptz,
      paid_on date,
      reference text,
      review_reason text,
      refusal text constraint event_vip_orders_refusal_check
        check (refusal is null or refusal in ('vip_off_sale', 'closed', 'already_vip', 'payment_waiting', 'person_cancelled',
                                              'person_not_found', 'livemode_mismatch', 'id_reused')),
      waiting_for_match boolean not null default false,
      status_before_dismiss text,
      reason_before_dismiss text,
      test_note text,
      test_would text,
      refunded_cents_total integer not null default 0 constraint event_vip_orders_refunded_check check (refunded_cents_total >= 0),
      refund_noted_at timestamptz,
      body_md5 text,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      updated_by uuid references public.profiles(id) on delete set null,
      constraint event_vip_orders_order_key unique (order_id),
      constraint event_vip_orders_payment_request_key unique (hitpay_payment_request_id));
    create index event_vip_orders_event_idx on public.event_vip_orders (event_id, status);

    create table public.event_vip_order_people (
      order_ref uuid not null references public.event_vip_orders(id) on delete cascade,
      person_id uuid not null references public.event_registration_people(id) on delete cascade,
      position integer not null,
      invoice_id uuid references public.invoices(id) on delete set null,
      invoice_item_id uuid,
      constraint event_vip_order_people_pkey primary key (order_ref, person_id));
    create index event_vip_order_people_person_idx on public.event_vip_order_people (person_id);
    create index event_vip_order_people_invoice_idx on public.event_vip_order_people (invoice_id) where invoice_id is not null;

    create table public.event_vip_gifts (
      id uuid primary key default gen_random_uuid(),
      event_id uuid not null references public.events(id),
      guest_id uuid references public.event_guests(id) on delete set null,
      guest_name text not null,
      person_id uuid references public.event_registration_people(id) on delete set null,
      product_id uuid not null references public.products(id),
      stock_use_id uuid references public.stock_uses(id) on delete set null,
      use_no text,
      day date,
      given_by uuid references public.profiles(id) on delete set null,
      given_at timestamptz not null default now(),
      undone_at timestamptz,
      undone_by uuid references public.profiles(id) on delete set null,
      undone_reason text,
      request_id uuid,
      constraint event_vip_gifts_request_key unique (request_id),
      constraint event_vip_gifts_undone_check check ((undone_at is null) = (undone_by is null)));
    create unique index event_vip_gifts_one_active_idx on public.event_vip_gifts (guest_id) where undone_at is null;
    create index event_vip_gifts_event_idx on public.event_vip_gifts (event_id);
    create table public.event_planning_answers (
      id uuid primary key default gen_random_uuid(),
      event_id uuid not null references public.events(id),
      -- whose: a website person's FIRST (free) guest record, any other guest's own record (event_planning_anchor)
      guest_id uuid not null references public.event_guests(id) on delete cascade,
      person_id uuid references public.event_registration_people(id) on delete set null,
      food text constraint event_planning_answers_food_check
        check (food is null or food in ('no_preference', 'vegetarian', 'vegan', 'halal', 'no_beef', 'other')),
      food_other text constraint event_planning_answers_food_other_check
        check (food_other is null or (food = 'other' and food_other = btrim(food_other) and char_length(food_other) between 1 and 60)),
      allergy text constraint event_planning_answers_allergy_check check (allergy is null or allergy in ('no', 'yes')),
      allergy_details text constraint event_planning_answers_allergy_details_check
        check (allergy_details is null or (allergy = 'yes' and allergy_details = btrim(allergy_details)
                                           and char_length(allergy_details) between 1 and 120)),
      -- [{"date": "2026-11-23", "whole_day": false, "arrive": "14:00", "leave": "19:00"}, ...], one per day, by date
      timing jsonb not null default '[]'::jsonb constraint event_planning_answers_timing_check
        check (case when jsonb_typeof(timing) = 'array' then jsonb_array_length(timing) <= 31 else false end),
      talks text[] not null default '{}'::text[] constraint event_planning_answers_talks_check
        check (cardinality(talks) <= 20 and array_position(talks, null) is null),
      access text[] not null default '{}'::text[] constraint event_planning_answers_access_check
        check (access <@ array['wheelchair', 'walking_help', 'front_seat']::text[] and array_position(access, null) is null),
      access_other text constraint event_planning_answers_access_other_check
        check (access_other is null or (access_other = btrim(access_other) and char_length(access_other) between 1 and 120)),
      heard_from text constraint event_planning_answers_heard_check
        check (heard_from is null or heard_from in ('tiktok', 'facebook', 'instagram', 'google', 'whatsapp',
                                                    'friend_family', 'staff', 'email', 'other')),
      heard_from_other text constraint event_planning_answers_heard_other_check
        check (heard_from_other is null or (heard_from = 'other' and heard_from_other = btrim(heard_from_other)
                                            and char_length(heard_from_other) between 1 and 60)),
      question text constraint event_planning_answers_question_check
        check (question is null or (question = btrim(question) and char_length(question) between 1 and 300)),
      version integer not null default 1 constraint event_planning_answers_version_check check (version >= 1),
      answered_by text not null constraint event_planning_answers_by_check check (answered_by in ('guest', 'staff')),
      staff_id uuid references public.profiles(id) on delete set null,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      constraint event_planning_answers_guest_key unique (guest_id),
      constraint event_planning_answers_person_key unique (person_id),
      -- a website save never names staff; a staff row's staff_id may go null when the profile is deleted
      constraint event_planning_answers_staff_check check (answered_by = 'staff' or staff_id is null));
    create index event_planning_answers_event_idx on public.event_planning_answers (event_id);
    comment on table public.event_web_settings is
      '436: an event''s website: its code, mode, venue, store, the profile that raises its invoices, VIP ticket, vouchers, gifts, payment methods, customer source, sync URL.';
    comment on table public.event_web_keys is
      '436: the keys an event''s website uses, kept as their SHA-256 only (a key is shown once, on the Event page''s Website tab).';
    comment on table public.event_web_requests is
      '436: each write the website sent (request id, body md5, the answer for 7 days) and each read, for replays, the rate and the Website tab.';
    comment on table public.event_registrations is '436: a registration form sent by an event''s website (1 to 10 people).';
    comment on table public.event_registration_people is
      '436: one registered person: how they were matched to a customer, held for staff or not, their free and VIP guest records, the referral, their VIP link token.';
    comment on table public.event_vip_orders is '436: a VIP payment (HitPay, PayNow or bank transfer) for 1 to 10 registered people.';
    comment on table public.event_vip_order_people is '436: the people of a VIP payment, and each one''s invoice.';
    comment on table public.event_vip_gifts is '436: the socks or gloves a VIP was given at the door (a Record use), or undone.';
    comment on table public.event_planning_answers is
      '436: a guest''s answers to the planning questions (food, allergies, timing per day, talks, what to prepare, how they heard, a question for the speakers), one row per guest; a website person''s on their first (free) record. Staff edits audited.';
    foreach v in array c_tables loop
      execute format('alter table public.%I enable row level security', v);
      execute format('revoke all on table public.%I from public, anon, authenticated', v);
      execute format('grant all on table public.%I to service_role', v);
    end loop;
  end if;

  foreach k in array v_new loop
    execute c_defs[k];
    if c_client[k] then
      execute format('revoke all on function public.%s from public, anon', c_sigs[k]);
      execute format('grant execute on function public.%s to authenticated, service_role', c_sigs[k]);
    else
      execute format('revoke all on function public.%s from public, anon, authenticated', c_sigs[k]);
      execute format('grant execute on function public.%s to service_role', c_sigs[k]);
    end if;
  end loop;
  if v_patch then execute d; end if;
  if v_pl_patch then execute d2; end if;

  if not exists (select 1 from pg_trigger where tgname = 'event_guests_vip_follow' and not tgisinternal) then
    create trigger event_guests_vip_follow after update of status on public.event_guests
      for each row when (old.status is distinct from new.status) execute function public.trg_event_vip_guest_follow();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'event_guests_vip_parked' and not tgisinternal) then
    create trigger event_guests_vip_parked before update of status on public.event_guests
      for each row execute function public.trg_event_vip_parked_guest();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'events_web_delete_guard' and not tgisinternal) then
    create trigger events_web_delete_guard before update of deleted_at on public.events
      for each row execute function public.trg_event_web_delete_guard();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'invoices_vip_vouchers_follow_refund' and not tgisinternal) then
    create trigger invoices_vip_vouchers_follow_refund after update of status, paid_amount on public.invoices
      for each row when (new.status is distinct from old.status or new.paid_amount is distinct from old.paid_amount)
      execute function public.trg_event_vip_refund_vouchers();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'referral_signup_checks_event_web_decided' and not tgisinternal) then
    create trigger referral_signup_checks_event_web_decided after update of status on public.referral_signup_checks
      for each row when (old.status = 'pending' and new.status <> 'pending')
      execute function public.trg_event_web_referral_check_decided();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'approval_requests_event_vip_reason' and not tgisinternal) then
    create trigger approval_requests_event_vip_reason after update of payload on public.approval_requests
      for each row when (new.status = 'approved' and new.request_type in ('invoice_refund', 'invoice_cancel')
                         and (old.payload -> 'overrides') is distinct from (new.payload -> 'overrides'))
      execute function public.trg_event_vip_used_later_reason();
  end if;

  -- The nudge every 10 minutes, where pg_cron is installed (production; 381's).
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'event-website-sync-ping' and schedule = '*/10 * * * *'
                     and command = 'select public.event_web_sync_ping()') then
      perform cron.schedule('event-website-sync-ping', '*/10 * * * *', 'select public.event_web_sync_ping()');
    end if;
  else
    raise notice '436: pg_cron is not installed here, so the sync nudge is not scheduled';
  end if;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]))) <> c_md5s[k] then
      raise exception '436: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_sigs[k], 'execute') is distinct from c_client[k]
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '436: the grants of public.% are not as tested', c_sigs[k]; end if;
  end loop;
  if md5(pg_get_functiondef(c_lc::regprocedure)) <> c_lc_after then
    raise exception '436: % was installed with an md5 other than the tested one', c_lc; end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = c_lc::regprocedure) is distinct from v_lc_acl then
    raise exception '436: the grants of % changed', c_lc; end if;
  if md5(pg_get_functiondef(c_pl::regprocedure)) <> c_pl_after then
    raise exception '436: % was installed with an md5 other than the tested one', c_pl; end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = c_pl::regprocedure) is distinct from v_pl_acl then
    raise exception '436: the grants of % changed', c_pl; end if;
  for k in 1 .. cardinality(c_tables) loop
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                      '|' order by a.attname) into v
      from pg_attribute a where a.attrelid = ('public.' || c_tables[k])::regclass and a.attnum > 0 and not a.attisdropped;
    if v is distinct from c_shapes[k] then raise exception '436: public.% is not as tested (%)', c_tables[k], v; end if;
    if not (select relrowsecurity from pg_class where oid = ('public.' || c_tables[k])::regclass)
       or exists (select 1 from pg_policy where polrelid = ('public.' || c_tables[k])::regclass)
       or has_table_privilege('anon', 'public.' || c_tables[k], 'select,insert,update,delete')
       or has_table_privilege('authenticated', 'public.' || c_tables[k], 'select,insert,update,delete')
       or not has_table_privilege('service_role', 'public.' || c_tables[k], 'select,insert,update,delete') then
      raise exception '436: public.% is not reachable as tested', c_tables[k]; end if;
  end loop;
  for r in select * from (values (1, 'event_guests_vip_follow'), (2, 'event_guests_vip_parked'), (3, 'events_web_delete_guard'),
                                 (4, 'invoices_vip_vouchers_follow_refund'), (5, 'referral_signup_checks_event_web_decided'),
                                 (6, 'approval_requests_event_vip_reason')) x(i, name) loop
    if (select pg_get_triggerdef(tg.oid) from pg_trigger tg where tg.tgname = r.name and not tg.tgisinternal) is distinct from c_trigs[r.i] then
      raise exception '436: the trigger % is not as tested', r.name; end if;
  end loop;

  -- ── 4. Behaviour, as the website's edge function, in a block that is always undone ──
  -- Made-up records only ("436 check", @example.invalid, fictional phones);
  -- it ends by raising P0436, which undoes all it wrote.
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_sfx := upper(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(9000, 9999) g
             where not exists (select 1 from public.customers c
                                where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(g::text, 4, '0'))
             limit 4) y;
    t_ph1 := t_phones[1]; t_ph2 := t_phones[2]; t_ph3 := t_phones[3]; t_ph4 := t_phones[4];
    insert into auth.users (id, email) values (gen_random_uuid(), '436-check-' || lower(t_sfx) || '@example.invalid')
      returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '436 check', u.email, 'owner', true from auth.users u where u.id = t_owner;
    insert into public.stores (name, code, country_code) values ('436 check ' || t_sfx, '436-' || t_sfx, 'SG') returning id into t_store;
    insert into public.events (name, daily_start, daily_end, is_active) values ('436 check ' || t_sfx, '09:00', '19:00', true)
      returning id into t_event;
    insert into public.event_days (event_id, day, capacity) values (t_event, public.sg_today() + 30, 40), (t_event, public.sg_today() + 31, null);
    insert into public.event_stores (event_id, store_id) values (t_event, t_store);
    insert into public.event_ticket_options (event_id, name, days_count, price) values (t_event, 'VIP', 2, 72) returning id into t_opt;
    insert into public.payment_methods (name, is_active) values ('436 check HitPay ' || t_sfx, true) returning id into t_pm;
    insert into public.customers (full_name, phone, email) values ('Check Existing', t_ph1, '436-check-' || lower(t_sfx) || '@example.invalid')
      returning id into t_cust;
    insert into public.vouchers (name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('436 check voucher ' || t_sfx, '436CHK' || t_sfx, 'normal', 'unlimited', 10, true) returning id into t_vch;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vch, t_store, 10, true);
    insert into public.event_web_settings (event_id, code, mode, store_id, acting_profile_id, vip_option_id, vip_voucher_ids,
                                           hitpay_payment_method_id)
    values (t_event, 'CHECK436-' || t_sfx, 'live', t_store, t_owner, t_opt, array[t_vch], t_pm);
    t_live := 'evk_live_' || rpad(t_sfx, 43, 'L');
    t_test := 'evk_test_' || rpad(t_sfx, 43, 'T');
    insert into public.event_web_keys (event_id, kind, key_hash, key_hint, created_by)
    values (t_event, 'live', encode(extensions.digest(t_live, 'sha256'), 'hex'), '436 check', t_owner),
           (t_event, 'test', encode(extensions.digest(t_test, 'sha256'), 'hex'), '436 check', t_owner);

    -- event_info: no capacity, no count.
    t_ans := public.event_web_call(encode(extensions.digest(t_live, 'sha256'), 'hex'), null, 'event_info',
               jsonb_build_object('type', 'event_info', 'event', 'CHECK436-' || t_sfx));
    if t_ans->'event'->>'registration_open' <> 'true' or t_ans::text ~* 'capacity|registered"' then
      raise exception '436: the self-test''s event_info is not as tested: %', t_ans; end if;
    -- A registration: an exact match, and an email that is a customer's (held).
    t_ans := public.event_web_call(encode(extensions.digest(t_live, 'sha256'), 'hex'), gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK436-' || t_sfx, 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || t_sfx, 'submitted_at', now(),
        'referral_code', null, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Check', 'last_name', 'Existing', 'phone', t_ph1,
                             'email', 'one-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', true),
          jsonb_build_object('position', 2, 'first_name', 'Check', 'last_name', 'Family', 'phone', t_ph2,
                             'email', '436-check-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 31), 'vip', false)))));
    t_p1 := (t_ans->'people'->0->>'person_id')::uuid;
    t_p2 := (t_ans->'people'->1->>'person_id')::uuid;
    t_tok := t_ans->'people'->0->>'upgrade_token';
    if t_ans->>'status' <> 'registered'
       or (select (match, customer_id) is distinct from ('exact'::text, t_cust) from public.event_registration_people where id = t_p1)
       or (select (match, hold_reason, customer_id) is distinct from ('held'::text, 'email_in_use'::text, null::uuid)
             from public.event_registration_people where id = t_p2)
       or (select count(*) from public.event_guests g join public.event_registration_people p on p.free_guest_id = g.id
            where p.id in (t_p1, t_p2) and g.status = 'registered') <> 2 then
      raise exception '436: the self-test''s registration is not as tested: %', t_ans; end if;
    -- 436 (round 7): the person's planning answers, by their own VIP link token: kept on their first record.
    t_ans := public.event_web_call(encode(extensions.digest(t_live, 'sha256'), 'hex'), gen_random_uuid(), 'planning_answers',
      jsonb_build_object('type', 'planning_answers', 'event', 'CHECK436-' || t_sfx, 'planning', jsonb_build_object(
        'submitted_at', now(), 'people', jsonb_build_array(jsonb_build_object('upgrade_token', t_tok, 'version', 0,
          'answers', jsonb_build_object('food', 'vegetarian', 'food_other', null, 'allergy', 'yes', 'allergy_details', 'Peanuts',
            'timing', jsonb_build_array(jsonb_build_object('date', public.sg_today() + 30, 'whole_day', false,
                                                           'arrive', '14:00', 'leave', '19:00')),
            'talks', jsonb_build_array('Caring for your eyes'), 'access', '[]'::jsonb, 'access_other', null,
            'heard_from', 'tiktok', 'heard_from_other', null, 'question', null))))));
    if t_ans->>'status' <> 'ok' or t_ans->'people'->0->>'status' <> 'saved'
       or (t_ans->'people'->0->'planning'->>'version') <> '1'
       or not exists (select 1 from public.event_planning_answers a join public.event_registration_people p on p.free_guest_id = a.guest_id
                       where p.id = t_p1 and a.person_id = t_p1 and a.food = 'vegetarian' and a.answered_by = 'guest') then
      raise exception '436: the self-test''s planning answers are not as tested: %', t_ans; end if;
    -- event_info: answers open, no talk titles saved yet (the website offers the suggested list).
    t_ans := public.event_web_call(encode(extensions.digest(t_live, 'sha256'), 'hex'), null, 'event_info',
               jsonb_build_object('type', 'event_info', 'event', 'CHECK436-' || t_sfx))->'event';
    if t_ans->'planning_open' is distinct from 'true'::jsonb or t_ans->'talk_titles' is distinct from 'null'::jsonb then
      raise exception '436: the self-test''s event_info is not as tested: %', t_ans; end if;
    -- VIP through HitPay: invoiced, the voucher on their account, the free
    -- record parked; refunded in full (the Owner, 20 Oct 2026), the voucher
    -- is taken back and the free record comes back.
    t_ans := public.event_web_call(encode(extensions.digest(t_live, 'sha256'), 'hex'), gen_random_uuid(), 'vip_checkout',
      jsonb_build_object('type', 'vip_checkout', 'event', 'CHECK436-' || t_sfx, 'order', jsonb_build_object(
        'order_id', 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || t_sfx, 'upgrade_tokens', jsonb_build_array(t_tok),
        'payer', jsonb_build_object('name', 'Check Existing', 'email', 'one-' || lower(t_sfx) || '@example.invalid', 'phone', null),
        'livemode', true, 'checkout_opened_at', now() - interval '2 minutes')));
    if t_ans->>'status' <> 'ok' or t_ans->>'total_cents' <> '7200' then
      raise exception '436: the self-test''s checkout is not as tested: %', t_ans; end if;
    t_ans := public.event_web_call(encode(extensions.digest(t_live, 'sha256'), 'hex'), gen_random_uuid(), 'vip_paid',
      jsonb_build_object('type', 'vip_paid', 'event', 'CHECK436-' || t_sfx, 'payment', jsonb_build_object(
        'order_id', 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || t_sfx, 'provider', 'hitpay',
        'payment_request_id', gen_random_uuid(), 'payment_id', gen_random_uuid(), 'amount_cents', 7200, 'currency', 'SGD',
        'livemode', true, 'paid_at', now() - interval '1 minute', 'upgrade_tokens', jsonb_build_array(t_tok),
        'payer', jsonb_build_object('name', 'Check Existing', 'email', 'one-' || lower(t_sfx) || '@example.invalid', 'phone', null))));
    select p.free_guest_id, p.vip_guest_id into t_free, t_vip from public.event_registration_people p where p.id = t_p1;
    select g.invoice_id into t_inv from public.event_guests g where g.id = t_vip;
    if t_ans->>'status' <> 'invoiced' or t_vip is null
       or (select status from public.event_guests where id = t_free) <> 'cancelled'
       or (select i.status::text from public.invoices i where i.id = t_inv) <> 'paid'
       or (select count(*) from public.customer_reward_vouchers v
            where v.customer_id = t_cust and v.voucher_id = t_vch and v.status = 'held') <> 1 then
      raise exception '436: the self-test''s VIP payment is not as tested: %', t_ans; end if;
    -- The answers follow the person to their VIP record, and the summary counts them once.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    t_ans := public.event_planning_summary(t_event);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    if public.event_planning_anchor(t_vip) <> t_free or t_ans->'days'->0->'food'->>'vegetarian' <> '1'
       or jsonb_array_length(t_ans->'days'->0->'late') <> 1 or jsonb_array_length(t_ans->'vip'->'allergies') <> 1 then
      raise exception '436: the self-test''s planning summary is not as tested: %', t_ans; end if;
    -- Round 8: the held person's candidate (who just paid VIP) is already a guest, with that VIP payment.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    t_ans := public.event_web_guest_extras(t_event);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    if (select c->'guest' from jsonb_array_elements(t_ans->'holds') h, jsonb_array_elements(h->'candidates') c
         where (h->>'person_id')::uuid = t_p2 and (c->>'customer_id')::uuid = t_cust)
       is distinct from jsonb_build_object('days', jsonb_build_array(public.sg_today() + 30, public.sg_today() + 31),
                                           'vips', jsonb_build_array(jsonb_build_object('state', 'paid',
                                                     'invoice_no', (select i.invoice_no from public.invoices i where i.id = t_inv))))
       or t_ans->'vip_doubles' is distinct from '[]'::jsonb then
      raise exception '436: the self-test''s To match candidate is not as tested: %', t_ans; end if;
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv and it.line_kind = 'event_ticket';
    select ip.id into t_pay from public.invoice_payments ip where ip.invoice_id = t_inv;
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 72)),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 72)), '[]'::jsonb, '436 check', gen_random_uuid());
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    if (select i.status::text from public.invoices i where i.id = t_inv) <> 'refunded'
       or (select status from public.event_guests where id = t_vip) <> 'cancelled'
       or (select status from public.event_guests where id = t_free) <> 'registered'
       or exists (select 1 from public.customer_reward_vouchers v where v.customer_id = t_cust and v.voucher_id = t_vch and v.status <> 'revoked') then
      raise exception '436: the self-test''s VIP refunded in full did not take the voucher back and bring the free record back'; end if;
    -- The test key changes nothing.
    t_ans := public.event_web_call(encode(extensions.digest(t_test, 'sha256'), 'hex'), gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK436-' || t_sfx, 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx), 1, 8)),
        'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Check', 'last_name', 'Test', 'phone', t_ph3,
                             'email', 'test-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false)))));
    if t_ans->>'status' <> 'registered' or t_ans->>'test' <> 'true'
       or exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = t_ph3)
       or exists (select 1 from public.event_guests g where g.phone = t_ph3) then
      raise exception '436: the self-test''s test key changed something: %', t_ans; end if;
    -- The test key's planning answers: what would be kept, kept nowhere.
    t_ans := public.event_web_call(encode(extensions.digest(t_test, 'sha256'), 'hex'), gen_random_uuid(), 'planning_answers',
      jsonb_build_object('type', 'planning_answers', 'event', 'CHECK436-' || t_sfx, 'planning', jsonb_build_object(
        'submitted_at', now(), 'people', jsonb_build_array(jsonb_build_object(
          'upgrade_token', t_ans->'people'->0->>'upgrade_token', 'version', 0,
          'answers', jsonb_build_object('food', 'halal', 'food_other', null, 'allergy', null, 'allergy_details', null,
            'timing', '[]'::jsonb, 'talks', '[]'::jsonb, 'access', '[]'::jsonb, 'access_other', null,
            'heard_from', null, 'heard_from_other', null, 'question', null))))));
    if t_ans->>'status' <> 'ok' or t_ans->'people'->0->>'status' <> 'test'
       or t_ans->'people'->0->'planning'->'answers'->>'food' <> 'halal'
       or exists (select 1 from public.event_planning_answers a where a.food = 'halal' and a.event_id = t_event) then
      raise exception '436: the self-test''s test key kept planning answers: %', t_ans; end if;
    -- No self-referral (the owner, 20 and 21 Oct 2026): the affiliate through
    -- her own link, under her name in other words on a phone and email not on
    -- file, is held for staff with her record to link, and nobody's referral.
    insert into public.customer_affiliates (customer_id, status, referral_code) values (t_cust, 'active', 'CHK' || t_sfx);
    t_ans := public.event_web_call(encode(extensions.digest(t_live, 'sha256'), 'hex'), gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK436-' || t_sfx, 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5('self' || t_sfx), 1, 8)),
        'submitted_at', now(), 'referral_code', 'CHK' || t_sfx, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Existing', 'last_name', 'Check', 'phone', t_ph4,
                             'email', 'self-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false)))));
    t_p1 := (t_ans->'people'->0->>'person_id')::uuid;
    if t_ans->>'status' <> 'registered'
       or (select (p.match, p.hold_reason, p.candidate_customer_ids, p.customer_id, p.referral_outcome, p.referral_self_by)
                  is distinct from ('held'::text, 'affiliate_name'::text, array[t_cust], null::uuid, 'self'::text, array['name'])
             from public.event_registration_people p where p.id = t_p1)
       or exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = t_ph4)
       or exists (select 1 from public.referral_signup_events e where e.referral_code = 'CHK' || t_sfx) then
      raise exception '436: the self-test''s affiliate through her own link was not held for staff, or was referred: %', t_ans; end if;
    -- Someone else on her own phone (the owner, 20 Oct 2026, ~20:15): held;
    -- made a customer by staff, her referral waits for the check (no
    -- referrer yet); checked as a different person, then referred.
    t_ans := public.event_web_call(encode(extensions.digest(t_live, 'sha256'), 'hex'), gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK436-' || t_sfx, 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5('kin' || t_sfx), 1, 8)),
        'submitted_at', now(), 'referral_code', 'CHK' || t_sfx, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Kin', 'last_name', 'Relative', 'phone', t_ph1,
                             'email', 'kin-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 31), 'vip', false)))));
    t_p2 := (t_ans->'people'->0->>'person_id')::uuid;
    if t_ans->>'status' <> 'registered'
       or (select (p.match, p.hold_reason, p.referral_outcome, p.referral_self_by) is distinct from
                  ('held'::text, 'phone_in_use'::text, 'held'::text, null::text[])
             from public.event_registration_people p where p.id = t_p2) then
      raise exception '436: the self-test''s relative on the affiliate''s phone is not held for staff: %', t_ans; end if;
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform public.event_registration_create_customer(t_p2, '436 check');
    select p.customer_id into t_free from public.event_registration_people p where p.id = t_p2;
    if (select p.referral_outcome from public.event_registration_people p where p.id = t_p2) is distinct from 'check_waiting'
       or (select c.referred_by from public.customers c where c.id = t_free) is not null
       or not exists (select 1 from public.referral_signup_checks k
                       where k.customer_id = t_free and k.status = 'pending' and k.referrer_customer_id = t_cust) then
      raise exception '436: the self-test''s relative made a customer is not waiting for the check'; end if;
    perform public.decide_referral_signup_check((select k.id from public.referral_signup_checks k where k.customer_id = t_free),
                                                'different_person', '436 check');
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    if (select c.referred_by from public.customers c where c.id = t_free) is distinct from t_cust
       or (select p.referral_outcome from public.event_registration_people p where p.id = t_p2) is distinct from 'check_confirmed' then
      raise exception '436: the self-test''s relative checked as a different person was not referred'; end if;
    raise exception using errcode = 'P0436', message = '436: self-test done, undone';
  exception when sqlstate 'P0436' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');

end $mig$;
