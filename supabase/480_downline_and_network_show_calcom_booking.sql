-- 480_downline_and_network_show_calcom_booking.sql
--
-- THE DOWNLINE AND THE AFFILIATE PORTAL'S MY NETWORK SHOW EACH CUSTOMER'S
-- CAL.COM BOOKING: ITS DATE AND TIME, "MISS" WHEN THEY DID NOT COME, "NO
-- BOOKING" WHEN THERE IS NONE (the Owner, 29 Oct 2026)
--
-- THE RULES (the Owner, 29 Oct 2026)
--
--   The request, exactly: "add one more feature which is the booking date
--   that the customer has done using cal.com. This should be able to see by
--   staff, owner, manager and the customer's affiliate. If there is no
--   booking yet, show no booking with red colour. If they miss their
--   booking, show "miss" with red colour badge." Two screens: the staff
--   "Downline — <name>" window (customer_downline_visits, with its Excel
--   export) and the affiliate portal's My Network (affiliate_portal_network),
--   Tier 1 and Tier 2 on both.
--   The Owner's answers, the same day:
--   A. Source: cal.com sends each booking. An account-level cal.com webhook
--      (all of Energia's event types) posts BOOKING_CREATED,
--      BOOKING_RESCHEDULED and BOOKING_CANCELLED (and PING; anything else is
--      answered and ignored) to a new Edge Function, calcom-webhook, which
--      checks cal.com's signature and stores the booking. A booking belongs
--      to a customer by its WhatsApp number (the booking question
--      "WhatsApp-Number"; the attendee's phone or the "smsReminderNumber"
--      answer only when it has none), then by email. Bookings made before
--      the webhook existed are filled from Google Calendar, where cal.com
--      writes each booking (title "{affiliate}{Scheduler} {WhatsApp-Number}
--      {Location} {Event type title}", the booking link with its uid in the
--      description), by the uid so a later webhook for the same booking
--      updates the same row (G: the same call catches up every month). The
--      fill is run later, with the Owner's go-ahead (not by this file).
--   B. Which booking: the customer's NEXT booking whose Singapore day is
--      today or later; if none, their MOST RECENT past one. Cancelled and
--      rescheduled-away bookings are ignored entirely.
--   C. Miss: the booking's Singapore day is over (from the Singapore
--      midnight after it), it was not cancelled, and that Singapore day the
--      customer has no visit by THE visit rule (customer_centre_visit_days,
--      398/404) and no purchase at the centre (E). A no-show staff marked
--      "Cxl" in the Google Calendar title still counts as a miss (cal.com
--      never hears of that edit); in the fill a "Cxl" title is therefore not
--      a cancellation: only a cancelled Google event, a cal.com cancellation,
--      or (G) a booking gone from the calendar that the Owner cancels, is. A
--      past booking with a visit or a purchase that day shows its date
--      plainly (came). Today's booking is upcoming until the day is over.
--   D. A customer with no booking, or only cancelled or rescheduled-away
--      ones: "No booking", in red.
--   The Owner's answers, second round, the same day:
--   E. Came also counts a purchase at the Adelphi centre that day ("Survey,
--      or paid at Adelphi"): an invoice of the customer's at the centre
--      whose Singapore business day (invoices.business_date; when it has
--      none, the Singapore date it was made) is the booking's day. The
--      centre is the store in use (deleted_at null) coded RETAIL-ADELPHI
--      (production: one, "Energia Rev 22 (Adelphi)"), never a stored id; the
--      Van & RoadShow (ADELPHI-VAN) does not count. The invoice is not
--      deleted, its money or FOC was settled (paid, partially_paid,
--      completed_foc, refund_requested, refunded; not draft, unpaid,
--      cancellation_requested or cancelled), and it is not an online or
--      event order (no web order, VIP order person or event guest names
--      it). Only the booking's state reads it: Visited and First visit
--      (customer_centre_visits) and the visit rule are as they were.
--   F. A merged record's booking follows the merge ("Yes, it follows the
--      merge"): only when no customer in use holds the booking's phone, nor
--      (for the email step) its email inbox, the deleted records holding the
--      phone (else the inbox) are each followed along the trail
--      merge_customer_records leaves in audit_logs (the kept record's
--      customers_merged row naming the merged one in merged_from), from one
--      kept record to the next (A into B, then B into C: C), to a customer in
--      use; exactly one such customer is the person, otherwise no one. A
--      record deleted with Delete (not a merge) is never followed.
--      merge_customer_records and the audit log are not changed.
--   G. Every month, the calendar is caught up, each run with the Owner's OK
--      after a dry run: Google Calendar lists only events that exist (a
--      cancelled booking's event, or the old one of a booking rescheduled
--      to a new uid, is deleted by cal.com), so the fill reads ONE fully
--      listed window, orders each event by Google's 'updated' time against
--      the last change applied to its booking (the webhook's or a fill's),
--      never brings back a cancelled or rescheduled-away booking, reports an
--      active booking in the window the calendar no longer carries
--      (missing_from_calendar) and cancels those only when the Owner says so
--      after seeing the dry run. The first fill is the same call.
--   Who sees it: the staff window exactly as today (Owners, Admins,
--   Managers and Staff: require_active_staff; Inventory Managers, logins
--   that are not active staff and signed-out callers refused); the portal
--   exactly as today (the signed-in affiliate's own Tier 1 and Tier 2). Only
--   the booking's start and its state reach these screens: never its phone,
--   email, answers, title or affiliate label.
--
-- WHAT THIS DOES
--
--   1. public.calcom_bookings (new): one row per cal.com booking uid with its
--      start and end, its status (active, cancelled, rescheduled), the
--      booking it was rescheduled to, its event type (id, slug), the phone
--      as normalize_customer_phone reads it and the email inbox as
--      customer_email_match_key reads it (an active row only; nothing else:
--      no name, answers, title or payload), what made its last change
--      (webhook, backfill), and that change's moment (cal.com's createdAt,
--      or the Google event's 'updated') and, for the webhook, its trigger.
--      Row-level security on with no policy; anon and authenticated hold
--      nothing on it (Supabase's default grants are revoked, as 402 did for
--      the ads engine); the service role may only read it. Indexes: the uid;
--      the phone and the email of active rows. And three indexes on
--      customers: customer_email_match_key(email) of the customers in use
--      (the phone already has idx_customers_phone_norm), and the phone and
--      the email inbox of the deleted ones (F reads them for a booking no one
--      in use holds; without them each such booking read every deleted
--      record's phone: 3.6 s for a 600-person downline on a copy with 300
--      deleted records, 0.12 s with them).
--   2. calcom_booking_ingest(jsonb) (new, the service role's alone): one
--      webhook body ({triggerEvent, createdAt, payload}). CREATED stores the
--      booking; RESCHEDULED with an old uid (payload.rescheduleUid or
--      fromReschedule) stores the new booking and marks the old one
--      rescheduled (stored as such even when never seen), and with none (or
--      its own uid) moves the booking to its new time; CANCELLED marks it
--      cancelled (stored as such even when never seen, so a late CREATED
--      cannot bring it back); anything else: 'ignored'. The phone: the
--      WhatsApp-Number answer, else the attendee's phone, else the
--      smsReminderNumber answer, passing over a number the centre keeps as
--      its own (ads_excluded_phones, as the calendar fill does); the email:
--      the answer, else the attendee's; only text is read. Idempotent: the
--      same event again changes nothing; an event older than the last change
--      applied to a row (by the webhook or the fill) changes nothing
--      ('stale'); a cancelled or rescheduled-away row stays so. Malformed
--      input: SQLSTATE 22023 naming the field, never a value (the Edge
--      Function also refuses a booking without createdAt; one handed in here
--      without it is taken as sent now). Answers {result, previous?} with no
--      personal data. Through calcom_booking_apply (new, no one's endpoint)
--      and calcom_parse_time (new, no one's endpoint: an ISO 8601 moment with
--      its zone, or null).
--   3. calcom_booking_backfill(jsonb, timestamptz, timestamptz, timestamptz,
--      boolean, text[], boolean) (new, the service role's alone): the fill
--      and its monthly catch-up (G), one call: every Google Calendar event of
--      ONE window [p_from, p_to) of at most 400 days, as the Calendar API or
--      its connector lists them (id, summary, description, start and end
--      {dateTime[, timeZone]}, status, updated), at most 5000, and when the
--      listing began (p_listed_at). A dry run (writes nothing) unless
--      p_dry_run => false. Per event: the uid from the LAST cal.com booking
--      or reschedule link in the description (an event without one is
--      skipped unless the last argument says otherwise: then 'gcal:<event
--      id>'); the start and end with their offset, or without one in the
--      zone timeZone names; an all-day event, or one whose id, start, end or
--      updated cannot be read or whose updated is later than now, is skipped
--      and counted (never an error for the call); one with no updated is
--      timed when the listing began. Each event is applied only when its
--      'updated' is newer than the last change applied to its booking, from
--      either source: a uid not seen before is created (its phone from the
--      title only, the first word holding a number, as ads_extract_phones
--      finds numbers and normalize_customer_phone reads them; no email), an
--      active booking whose start or end differ is moved, else unchanged;
--      an older event changes nothing: unchanged when it agrees, else stale
--      and listed (kept_newer); a cancelled or rescheduled-away booking stays
--      so (terminal); a "Cxl" title is still a booking; an event Google
--      lists cancelled cancels it. A booking listed more than once (a staff
--      Duplicate in Google copies cal.com's link): the copy starting at the
--      stored start, else a stored booking's copy updated last or a new
--      booking's earliest; each other copy is listed (repeated_uid). An
--      active booking whose start is in the window, that no listed event
--      carries and that has not changed since p_listed_at is reported
--      (missing_from_calendar), and cancelled only on a real run that names
--      its uid in p_cancel_uids (the uids the Owner agreed to cancel after
--      the dry run; a named uid not missing in that run is left alone and
--      counted). Answers counts per outcome and the changes made (or that a
--      dry run would make): {uid, change, old_start, new_start}, the missing
--      bookings first, at most 500 (truncated), uids and times only.
--   4. calcom_booking_owner(text, text) (new, the service role's; PL/pgSQL,
--      so its queries' plans are kept between the calls one screen makes):
--      whose booking it is, worked out whenever it is read (never stored):
--      customers in use with the phone, exactly one; several: narrowed by
--      the email inbox, exactly one; no customer with the phone: the one
--      customer in use with the email inbox; neither held by anyone in use:
--      the merge trail (F); otherwise no one.
--   5. calcom_customer_bookings(uuid[], date) (new, the service role's): THE
--      rule both screens read: for each customer asked about, the booking
--      to show and its state (upcoming, came, miss, none), as in B-E; the
--      bookings under the phone or inbox of a record a merge retired into
--      one of them are read too (F).
--   6. customer_downline_visits(uuid) and affiliate_portal_network(): each
--      asks 5 once for Tier 1 and Tier 2 together and adds two keys to every
--      row: booking_at (the booking's start, or null) and booking_state
--      (upcoming, came, miss or none). Every key they had, the order of the
--      rows, the role checks, SECURITY DEFINER, the search path and the
--      grants are as they were.
--   With it, not in this file: the Edge Function
--   supabase/functions/calcom-webhook (cal.com's x-cal-signature-256: an
--   HMAC-SHA256 of the raw body with CALCOM_WEBHOOK_SECRET; 503
--   not_configured until that secret is set; 400 for a booking without a
--   readable createdAt), the Downline window (a Booking column in both
--   tables, Booking and Booking Status in the export, one sentence in its
--   note) and My Network (a Booking column, and a Booking line on each card,
--   both tiers, and one sentence above them; below 1200 px the page shows
--   its cards instead of the tables, so Your Commission never needs a
--   sideways scroll).
--
-- WHAT THE PERSON SEES (user-facing)
--
--   Staff, Owners, Managers (Downline): a Booking column: "Sat 31 Oct 2026,
--   2:00 pm" for an upcoming booking; the date in grey for a past one they
--   came to (a visit or a purchase at the centre that day); the date with a
--   red "Miss" badge for one they missed; "No booking" in red. The note:
--   "Miss means no visit and no purchase at the centre were recorded on that
--   booking's day." The export has Booking and Booking Status (Upcoming,
--   Came, Miss, No booking). Affiliates (My Network): the same Booking
--   column (a Booking line on each card on a phone, a phone held sideways or
--   a tablet: the page shows its cards below 1200 px), and the same meaning
--   of Miss above the tables. Until bookings arrive (the webhook) or are
--   filled (the calendar fill), every row reads "No booking": hence the
--   pages go out last (DEPLOY ORDER 7).
--
-- NOT CHANGED
--
--   * The visit rule (customer_centre_visit_days, customer_centre_visits:
--     Visited and First visit), how phones and emails are read
--     (normalize_customer_phone, inspect_customer_phone,
--     customer_email_match_key), ads_extract_phones, sg_today,
--     require_active_staff, current_affiliate_customer_id, and what a merge
--     writes (merge_customer_records, write_audit): pinned below.
--   * merge_customer_records, delete_customer, the audit log and every other
--     function. Bookings are matched to customers whenever they are read, so
--     a deletion, a merge and a customer made after the booking need nothing
--     done to the bookings.
--   * Who may call the two screens' functions, and everything they answered
--     before (only two keys are added to each row).
--
-- NOT COVERED (told to the Owner)
--
--   * cal.com does not send a failed webhook again: a booking lost that way
--     is unknown until a later event for it, or until the next calendar
--     catch-up (G) creates it (or reports it missing, when it was
--     cancelled).
--   * A booking whose phone several customers in use share, and whose email
--     inbox is on none or several of them, belongs to no one, and so does
--     one whose phone and email are nobody's (in use, or by a merge): it
--     shows on no row. Production, 29 Oct 2026 (counts only): 16 phones are
--     shared by customers in use. Rows the calendar fill made carry no
--     email, so they are matched by the phone alone. A stored phone that
--     cannot be read (inspect_customer_phone: an 8-digit number that could
--     be Singapore or Malaysia; 47 such, plus 79 written with + that do not
--     read; 7,830 LEGACY placeholders) matches no booking by phone.
--   * The merge trail (F) is read where merge_customer_records writes it:
--     the kept record's customers_merged row, written in the transaction
--     that retired the merged record, so its created_at is the merged
--     record's deleted_at (production, 29 Oct 2026: 18 of 18 merges). A
--     merged record restored and later deleted with Delete is therefore not
--     followed; one whose deleted_at was changed by hand is not either. Two
--     deleted records on one phone merged into two different customers:
--     the booking is no one's.
--   * "Cxl" in a Google Calendar title is never read as a cancellation (C),
--     also when staff wrote it because the customer phoned to cancel: that
--     booking shows Miss. Only cal.com's cancellation, a Google event listed
--     cancelled, or a booking the Owner cancels as missing from the calendar
--     (G) cancels.
--   * Only BOOKING_CREATED, BOOKING_RESCHEDULED and BOOKING_CANCELLED are
--     read; a booking that needs confirmation (BOOKING_REQUESTED) shows
--     when cal.com sends its BOOKING_CREATED, and BOOKING_REJECTED or
--     cal.com's own no-show marks are not read. A customer's own reschedule
--     on an event type that needs confirmation (or has a price) is not seen
--     as one by the webhook: cal.com cancels the old booking without a
--     webhook and sends the new one, once confirmed, as BOOKING_CREATED with
--     no link to the old one; the next catch-up reports the old one missing
--     from the calendar (cancelled when the Owner says so). Seated event
--     types are not read correctly: every seat's CREATED and CANCELLED
--     carries the one booking uid, so a new seat takes the booking from the
--     earlier one and one seat's cancellation cancels it for all. DEPLOY
--     ORDER 5 checks the event types first.
--   * The catch-up (G) knows only the calendar it is given: a booking of an
--     event type cal.com writes to another calendar (or to none) is reported
--     missing every month; list that calendar too (in the same call), or
--     leave those uids out of p_cancel_uids. A window listed in part (a page
--     left out) reports bookings missing that are not: the dry run shows
--     each one (DEPLOY ORDER 6 stops there when more are missing than
--     expected), and a real run cancels only the uids p_cancel_uids names,
--     so a page missing from the real run's listing alone is reported, never
--     cancelled. A booking moved by staff in Google from inside the window
--     to outside it is reported missing. A booking the webhook stored after
--     a fill read its event as newer is left as the fill wrote it (cal.com
--     sends each webhook within seconds, so only one delivered late can meet
--     this). A booking listed more than once (a staff Duplicate copies
--     cal.com's link) is read from its copy at the stored start; when no
--     copy is there (cal.com's event dragged in Google, then duplicated),
--     from the copy updated last, which may be the Duplicate: the other
--     copies are listed (repeated_uid) for the Owner to see. One Google
--     event listed twice (it changed while the pages were listed) keeps the
--     stored time until the next catch-up.
--   * A number the centre keeps as its own (ads_excluded_phones) is no one's
--     in the webhook and in the fill: a filled booking made with one still
--     belongs to no one (the fill has no email); a booking staff make with
--     one and the customer's own email goes to the customer with that email
--     inbox; a number added to ads_excluded_phones later does not re-read
--     the rows already stored.
--   * A visit or a purchase on another day than the booking does not make
--     the booking "came"; the visit rule is the one every screen uses
--     (398/404). A purchase counts at the Adelphi centre only, and only
--     while a store in use is coded RETAIL-ADELPHI.
--   * The three new customers indexes are on customer_email_match_key(email)
--     and normalize_customer_phone(phone), as idx_customers_phone_norm is: a
--     later change to either function must rebuild them (REINDEX).
--   * The fill's uid comes from the LAST cal.com booking or reschedule link
--     in the event description (cal.com writes its own manage link after the
--     attendee's notes and answers, which may hold an older link), and a new
--     booking's phone from the title (both read on the Owner's word, not
--     from the live calendar: run it as a dry run first and look at the
--     counts); a new event whose title holds no number (staff rewrote it) is
--     skipped (one already stored is still moved); a booking already stored
--     keeps its phone and email; hand-typed appointments with no cal.com
--     link are skipped unless the Owner decides otherwise.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the two functions changed are each production's version of 29 Oct
--     2026 (BEFORE, replaced by the tested text) or already this file's
--     (AFTER: left alone), with their grants as read; anything else is
--     refused;
--   * the six new functions are missing or exactly this file's, and no
--     other function takes their names; the table is missing or exactly
--     this file's (its columns, checks and indexes); the three customers
--     indexes are missing or exactly this file's;
--   * the functions relied on are as read on 29 Oct 2026, the columns read
--     are there, of the types read, the invoice statuses are the nine read,
--     and exactly one store in use is coded RETAIL-ADELPHI.
--   Afterwards: every function has its AFTER md5; the changed two keep
--   their grants (signed-in logins and the service role; not signed out);
--   ingest, backfill, owner and the state rule: the service role's alone;
--   apply and parse_time: no one's (the owner's); the table has the shape
--   tested, row-level security on, no policy, nothing for anon or
--   authenticated, SELECT alone for the service role; the three customers
--   indexes are as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0480, so it leaves no row): made-up customers ("480 Check ...",
--   @example.invalid, fictional phones +61 2 5550 .... that no customer,
--   in use or deleted, and no active booking holds: range scans of the
--   three partial phone indexes, never a pass reading every customer's
--   phone) under a made-up referrer:
--   an upcoming booking, a past one with a consultant's survey that day
--   (came), a past one with none (miss), none, a booking made with the phone
--   of a record merged into a Tier 1 member (the merge written as
--   merge_customer_records writes it: write_audit's customers_merged row and
--   the record's deleted_at in one transaction), and in Tier 2 a
--   cancelled-only one (none), through the ingest; the same event again
--   (unchanged), an older one (stale), a reschedule to a new uid (the old
--   one rescheduled away); the state rule and the Downline's new keys for
--   both tiers; a dry run of the calendar catch-up in a window of 2098
--   (a new booking, an event without a link, an active booking the
--   calendar does not carry, named for cancelling with a uid that is not
--   missing: counts and changes, the missing one first, no row). The self-test
--   makes no invoice (an invoice's triggers reach stock, therapy, vouchers
--   and commissions): the purchase rule (E) is checked by the test suite.
--   A second run changes nothing ("already this version; left alone" for
--   each). Locks: the customers table for the three new indexes (SHARE,
--   while about 13,000 rows are read; the 5 s lock timeout makes it wait at
--   most that for a write in progress, then fail with nothing changed). The
--   SHARE lock is held to the end, a second run too (CREATE INDEX IF NOT
--   EXISTS takes it), so no customer can be added or changed until the file
--   ends: well under a second, measured on a copy holding 13,232 made-up
--   customers (300 deleted, 250 of them merged) and 500,000 audit rows.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   1. Dry run on a copy of production as it is then, WITH production's
--      customer rows (about 13,000; a schema-only copy such as the rc475_live
--      template holds none and cannot show how long the customers lock is
--      held; it also holds no store: add RETAIL-ADELPHI and ADELPHI-VAN
--      first): apply this file twice; the first run ends at the fingerprint
--      below, the second says "already this version; left alone" for each
--      and changes nothing; each run takes well under a second (SAFETY). A
--      run that takes seconds is holding every customer write: stop there.
--   2. Apply 480 (the CLI, or the MCP's apply_migration with this text
--      verbatim). The pages from before show nothing new. Then commit and
--      push ONLY the server side: this file, supabase/functions/calcom-webhook/,
--      package.json (check:calcom-webhook), and the tests
--      scripts/referrals/tests/downline-booking-480.sql,
--      scripts/customers/tests/staff-profile-453.sql and
--      scripts/permissions/tests/function-grants.sql. Not the page files
--      (step 7): a push to main is a Vercel deploy (DEPLOYMENT.md).
--   3. Deploy the Edge Function (it calls calcom_booking_ingest; before 2 it
--      would answer 503):
--        supabase functions deploy calcom-webhook --no-verify-jwt
--      Until 4 it answers every call 503 not_configured.
--   4. Set the secret CALCOM_WEBHOOK_SECRET in the Supabase function
--      secrets (a long random value; never in a file or a shell history:
--      `supabase secrets set --env-file <file>`).
--   5. In cal.com, first check every event type on the account (the webhook
--      covers all of them: the free, AW and MEOL giveaways, Livestreaming,
--      the 15/30-min and Secret meetings): Requires confirmation off (also
--      its "less than ... notice" and free-email options), no price, no
--      seats, and which Google calendar each writes its bookings to. If any
--      needs confirmation, has a price or seats, or writes elsewhere, stop
--      and ask the Owner before adding the webhook (NOT COVERED). Then
--      (account level, Settings > Developer > Webhooks; "Clear all triggers"
--      first, the dialog ticks every one): a webhook to
--      https://<project>.supabase.co/functions/v1/calcom-webhook with the
--      same secret, no custom payload template (cal.com's own body is what
--      is read and signed), triggers Booking created, Booking rescheduled,
--      Booking cancelled only; cal.com's Ping test must answer 200
--      {"ok":true,"result":"pong"}.
--   6. The first fill, then the same every month (G), each with the Owner's
--      OK: the calendar cal.com writes its bookings to (the ads engine's
--      default calendar, ads_ingest_calendar_event; its id is not written in
--      this repository); the window, Singapore midnights: first fill, from
--      the day of the first cal.com booking to 180 days ahead; every month,
--      from 45 days ago to 180 days ahead. p_listed_at is the database's
--      now(), read just before the first page is listed; every list call
--      has the window as its start and end (unbounded, the connector
--      silently lists about two weeks), and every page is listed. The events
--      are never typed by hand: a script turns the pages the connector saved
--      into ONE call file kept outside this repository (it holds phone
--      numbers; deleted after the run), run from the Owner's terminal with
--      psql or `supabase db query --linked -f <file>`, never pasted into an
--      MCP call. calcom_booking_backfill(events, p_from, p_to, p_listed_at)
--      as a dry run (the default) first; stop and list again unless
--      skipped_bad_shape is 0, events is the number the script kept and
--      missing_from_calendar is a handful at most (the webhook closes a
--      booking cal.com cancels or moves to a new uid, so one is missing
--      only when its webhook was lost, staff deleted its event in Google or
--      its event type writes to another calendar); else its counts and
--      changes to the Owner; on their OK the same file with p_dry_run =>
--      false, and p_cancel_uids => the uids of the missing bookings the
--      Owner agreed to cancel (none otherwise). Over 5000 events or 400
--      days: smaller windows, each listed whole and run without
--      p_cancel_uids; then each window's file again as a dry run: only a
--      booking still missing then may be named (one moved across windows
--      reads as missing from one of them until the other has run).
--   7. The pages LAST, only after step 6's real fill has run and the Owner
--      has checked its counts: commit and push
--        src/components/referrals/BookingCell.tsx
--        src/components/referrals/DownlineModal.tsx
--        src/lib/referral/booking.mjs, src/lib/referral/booking.d.mts
--        src/pages/AffiliateNetworkPage.tsx, src/styles/globals.css
--        scripts/referrals/tests/downline-booking-480.test.mjs
--        scripts/referrals/preview/main.tsx, scripts/referrals/preview/supabase-stub.ts
--        vite.visits-preview.config.mts
--      Pushed any earlier (with step 2, or even before it), they show every
--      Tier 1 and Tier 2 member as a red "No booking" to staff and to every
--      affiliate until the fill has run (from 2 the database answers 'none'
--      until bookings arrive; a webhook before the fill brings only its own
--      bookings). A page from before shows nothing new, and one from after
--      on a database without 480 shows "—", never a false "No booking".
--
-- BEFORE (production, 29 Oct 2026: head 20261029060840, 478; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   customer_downline_visits(uuid)                                    5bee190a80a8e9624e7d15e16eb95ca1  (453's)
--   affiliate_portal_network()                                        eb2903a3a331a03cdef61782ba35ec36
--   new: calcom_parse_time(text), calcom_booking_owner(text,text),
--   calcom_customer_bookings(uuid[],date), calcom_booking_apply(text,text,
--   timestamptz,timestamptz,bigint,text,text,text,timestamptz,text,text),
--   calcom_booking_ingest(jsonb), calcom_booking_backfill(jsonb,timestamptz,
--   timestamptz,timestamptz,boolean,text[],boolean): missing; table
--   public.calcom_bookings and indexes idx_customers_email_match_key,
--   idx_customers_deleted_phone_norm, idx_customers_deleted_email_match_key:
--   missing
--   relied on, not changed
--   normalize_customer_phone(text)                                    b2bfac910e0c9eff402ba44e19750bee
--   inspect_customer_phone(text,text)                                 6672c4d1963996f3b601896f4a55916e
--   customer_email_match_key(text)                                    be468815c9626fff1728e2cfcd484b66
--   customer_centre_visit_days()                                      2129857d6ff9f29dcf2cbccc9f13e5bc  (404's)
--   customer_centre_visits()                                          c07a5a0cbbf52ba45e5dc911b20002da  (404's)
--   sg_today()                                                        1c1289f18e24d8370e9a6364c9c06fca
--   ads_extract_phones(text)                                          b93776dba353519d18d12384f7883e3b
--   ads_normalize_phone(text,text)                                    a61154d7e66e01b273e8b9911a213a2c
--   require_active_staff(text[])                                      877b3aa74cea559881979bb161c450e2  (406's)
--   current_affiliate_customer_id()                                   51695acf5f26ce3918d6003d0c980b0f
--   merge_customer_records(uuid,uuid,text,uuid)                       ba05c2b1fb4c0e14d369c01d06a635b0  (462's)
--   write_audit(text,uuid,text,jsonb,jsonb)                           b194f839993670c5b5dd28e934c2a829  (431's)
--   public function fingerprint, production now (478)                 eae7f82fcf73b53d97945020e755721a (1390 functions)
-- AFTER (for later guards)
--   customer_downline_visits(uuid)                                    ea3f28ea932506eda6937fa687298d6d
--   affiliate_portal_network()                                        d1c387fb852392da041b5d8207655879
--   calcom_parse_time(text)                                           773399bc477ceb3476dd84a6a9251f2d
--   calcom_booking_owner(text,text)                                   959a5a8280ac20155068b3fa9aae73f3
--   calcom_customer_bookings(uuid[],date)                             2e651a5d2367ba26bfd9e8e00d95823e
--   calcom_booking_apply(text,text,timestamptz,timestamptz,bigint,text,text,text,timestamptz,text,text)
--                                                                     844d56ae966ca4e1e633e070e0195256
--   calcom_booking_ingest(jsonb)                                      55d6b6b8b7509911a225f494313212d9
--   calcom_booking_backfill(jsonb,timestamptz,timestamptz,timestamptz,boolean,text[],boolean)
--                                                                     b68af462ad32de7af3f8b98a8491a7e1
--   table public.calcom_bookings shape (columns, checks, indexes)     32e6a37c4ddd3627b7dc2c84405477f6
--   public function fingerprint, worked out on a copy of production (29 Oct 2026):
--     production now (478) -> 480                                     6a7a72ebbb3a21e3a0df0ddd84efbcce (1396)
--
-- Test: scripts/referrals/tests/downline-booking-480.sql (begin ...
-- rollback; it installs this file twice, or with -v skip_install=1 where it
-- is in). Edge: supabase/functions/calcom-webhook (deno test). Pages:
-- scripts/referrals/tests/downline-booking-480.test.mjs. Earlier suites
-- accept 480's AFTER md5s where they pin these functions
-- (scripts/customers/tests/staff-profile-453.sql: run it with -v
-- skip_install=1 once 480 is in; 453's file then refuses, as it should).

set lock_timeout = '5s';

do $mig$
declare
  -- ── The two functions this changes: production's (BEFORE) -> this file's (AFTER) ──
  c_chg_sigs constant text[] := array['customer_downline_visits(uuid)', 'affiliate_portal_network()'];
  c_chg_before constant text[] := array['5bee190a80a8e9624e7d15e16eb95ca1', 'eb2903a3a331a03cdef61782ba35ec36'];
  c_chg_after constant text[] := array['ea3f28ea932506eda6937fa687298d6d', 'd1c387fb852392da041b5d8207655879'];
  c_chg_defs constant text[] := array[
$c1$CREATE OR REPLACE FUNCTION public.customer_downline_visits(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 398: a referrer's downline with visits (the Owner, 6 Oct 2026),
-- for Owners, Admins, Managers and Staff (453; 398: Owner/Manager only).
-- Tier 1: customers they referred; Tier 2: customers
-- those referred. Each with name, phone, joined (the Singapore date of the
-- referral, else of the customer's creation for older links without a
-- date), visited and the first visit date (customer_centre_visits).
-- 480 (the Owner, 29 Oct 2026): and each one's cal.com booking, its moment
-- (booking_at) and state (booking_state: upcoming, came, miss or none), as
-- calcom_customer_bookings works them out for both tiers at once.
declare
  v_name text; v_phone text; v_t1 jsonb; v_t2 jsonb;
  v_book jsonb;
begin
  -- 453 (the Owner, 22 Oct 2026): the roles that add and edit customers
  -- (418) see a downline, its phones and its export; an Inventory Manager, a
  -- login that is not active staff and a signed-out caller are refused
  -- (42501), as for the Profile's figures.
  perform public.require_active_staff('{owner,admin,manager,staff}');
  select c.full_name, c.phone into v_name, v_phone from public.customers c where c.id = p_customer_id;
  if not found then raise exception 'Customer not found'; end if;

  select coalesce(jsonb_object_agg(b.customer_id, jsonb_build_object('at', b.booking_at, 'state', b.booking_state)), '{}'::jsonb)
    into v_book
    from public.calcom_customer_bookings(array(
           select c.id from public.customers c where c.referred_by = p_customer_id and c.deleted_at is null
           union
           select c.id from public.customers c join public.customers p on p.id = c.referred_by
            where p.referred_by = p_customer_id and c.deleted_at is null and p.deleted_at is null)) b;

  with v as (select x.customer_id, x.first_visit_on from public.customer_centre_visits() x)
  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_id', c.id, 'name', c.full_name, 'phone', c.phone,
           'joined_on', (coalesce(c.referred_at, c.created_at) at time zone 'Asia/Singapore')::date,
           'joined_from_created', c.referred_at is null,
           'visited', v.first_visit_on is not null, 'first_visit_on', v.first_visit_on,
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none'))
           order by coalesce(c.referred_at, c.created_at) desc, c.full_name, c.id), '[]'::jsonb)
    into v_t1
    from public.customers c
    left join v on v.customer_id = c.id
   where c.referred_by = p_customer_id and c.deleted_at is null;

  with v as (select x.customer_id, x.first_visit_on from public.customer_centre_visits() x)
  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_id', c.id, 'name', c.full_name, 'phone', c.phone,
           'parent_id', p.id, 'parent_name', p.full_name,
           'joined_on', (coalesce(c.referred_at, c.created_at) at time zone 'Asia/Singapore')::date,
           'joined_from_created', c.referred_at is null,
           'visited', v.first_visit_on is not null, 'first_visit_on', v.first_visit_on,
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none'))
           order by coalesce(c.referred_at, c.created_at) desc, c.full_name, c.id), '[]'::jsonb)
    into v_t2
    from public.customers c
    join public.customers p on p.id = c.referred_by
    left join v on v.customer_id = c.id
   where p.referred_by = p_customer_id and c.deleted_at is null and p.deleted_at is null;

  return jsonb_build_object('customer_id', p_customer_id, 'name', v_name, 'phone', v_phone,
    'tier1', v_t1, 'tier2', v_t2);
end $function$
$c1$,
$c2$CREATE OR REPLACE FUNCTION public.affiliate_portal_network()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_t1 jsonb; v_t2 jsonb;
  -- 480 (the Owner, 29 Oct 2026): each one's cal.com booking, its moment and
  -- state only (calcom_customer_bookings, as the staff Downline reads it).
  v_book jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;

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
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none')
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
$c2$];
  -- Their grants, kept: signed-in logins and the service role, not signed out.
  c_chg_acl constant text[] := array['authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres'];

  -- ── The new functions ───────────────────────────────────────────────────
  c_new_sigs constant text[] := array['calcom_parse_time(text)',
    'calcom_booking_owner(text,text)',
    'calcom_customer_bookings(uuid[],date)',
    'calcom_booking_apply(text,text,timestamp with time zone,timestamp with time zone,bigint,text,text,text,timestamp with time zone,text,text)',
    'calcom_booking_ingest(jsonb)',
    'calcom_booking_backfill(jsonb,timestamp with time zone,timestamp with time zone,timestamp with time zone,boolean,text[],boolean)'];
  c_new_md5 constant text[] := array['773399bc477ceb3476dd84a6a9251f2d',
    '959a5a8280ac20155068b3fa9aae73f3',
    '2e651a5d2367ba26bfd9e8e00d95823e',
    '844d56ae966ca4e1e633e070e0195256',
    '55d6b6b8b7509911a225f494313212d9',
    'b68af462ad32de7af3f8b98a8491a7e1'];
  -- The service role may call it (the Edge Function, the calendar fill, the
  -- tests); otherwise it is only reached from inside the functions above.
  c_new_service constant boolean[] := array[false, true, true, false, true, true];
  c_new_defs constant text[] := array[
$n1$CREATE OR REPLACE FUNCTION public.calcom_parse_time(p_text text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
-- 480: a moment as cal.com and Google Calendar write it (ISO 8601 with its
-- zone: 2026-10-31T06:00:00Z, 2026-10-31T14:00:00+08:00), or null. A text
-- without its own zone, a word PostgreSQL would read as a moment ('now',
-- 'infinity'), or a year before 2000 or from 2100 is not one.
declare v timestamptz;
begin
  if p_text is null
     or p_text !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}(:?\d{2})?)$' then
    return null;
  end if;
  begin
    v := p_text::timestamptz;
  exception when others then
    return null;
  end;
  if v < '2000-01-01 00:00:00+00' or v >= '2100-01-01 00:00:00+00' then return null; end if;
  return v;
end
$function$
$n1$,
$n2$CREATE OR REPLACE FUNCTION public.calcom_booking_owner(p_phone_key text, p_email_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 480: whose cal.com booking this is (the Owner, 29 Oct 2026), worked out
-- whenever it is read, so a deletion or a customer made after the booking
-- needs nothing else. Customers in use whose phone, as
-- normalize_customer_phone reads it, is the booking's: exactly one is the
-- person; several are narrowed to those whose email inbox is the booking's
-- (customer_email_match_key, 432), exactly one is the person, else no one.
-- No customer in use with the phone (or no phone on the booking): the one
-- customer in use with the booking's email inbox; two or more: no one.
-- A merged record's booking follows the merge (the Owner, 29 Oct 2026):
-- only when no customer in use holds the phone and none holds the email
-- inbox, the deleted records holding the phone (when none of them leads to a
-- customer in use: those holding the inbox) are each followed to the record
-- that kept them, along the trail merge_customer_records leaves: the kept
-- record's audit row customers_merged naming the retired one in merged_from,
-- written when the merge retired it (the row's created_at is the retired
-- record's deleted_at), from one kept record to the next (A into B, then B
-- into C: C), at most 20 steps, never back to a record already passed.
-- Exactly one customer in use at the ends is the person, else no one. A
-- record deleted any other way (Delete, or restored after its merge and
-- deleted again) is not followed.
declare v_ids uuid[]; v_keys text[]; v_from uuid[]; v_leg int;
begin
  if p_phone_key is not null then
    select coalesce(array_agg(c.id), '{}'), coalesce(array_agg(public.customer_email_match_key(c.email)), '{}')
      into v_ids, v_keys
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) = p_phone_key;
    if cardinality(v_ids) = 1 then return v_ids[1]; end if;
    if cardinality(v_ids) > 1 then
      select coalesce(array_agg(x.id), '{}') into v_ids from unnest(v_ids, v_keys) x(id, k) where x.k = p_email_key;
      return case when cardinality(v_ids) = 1 then v_ids[1] end;
    end if;
  end if;
  if p_email_key is not null then
    select coalesce(array_agg(c.id), '{}') into v_ids
      from public.customers c
     where c.deleted_at is null and c.email is not null and public.customer_email_match_key(c.email) = p_email_key;
    if cardinality(v_ids) > 0 then return case when cardinality(v_ids) = 1 then v_ids[1] end; end if;
  end if;
  -- No one in use holds either: the merge trail, by the phone, then by the inbox.
  for v_leg in 1 .. 2 loop
    if v_leg = 1 then
      continue when p_phone_key is null;
      select coalesce(array_agg(c.id), '{}') into v_from
        from public.customers c
       where c.deleted_at is not null and public.normalize_customer_phone(c.phone) = p_phone_key;
    else
      continue when p_email_key is null;
      select coalesce(array_agg(c.id), '{}') into v_from
        from public.customers c
       where c.deleted_at is not null and c.email is not null and public.customer_email_match_key(c.email) = p_email_key;
    end if;
    continue when cardinality(v_from) = 0;
    with recursive w(id, n, seen) as (
      select f.id, 0, array[f.id] from unnest(v_from) f(id)
      union all
      select m.kept, w.n + 1, w.seen || m.kept
        from w
        join public.customers c on c.id = w.id and c.deleted_at is not null
       cross join lateral (
          select l.record_id as kept
            from public.audit_logs l
           where l.created_at = c.deleted_at and l.action = 'customers_merged' and l.table_name = 'customers'
             and l.new_data ->> 'merged_from' = c.id::text and l.record_id is not null
           order by l.id
           limit 1) m
       where w.n < 20 and m.kept <> all (w.seen)
    )
    select coalesce(array_agg(distinct w.id), '{}') into v_ids
      from w join public.customers c on c.id = w.id and c.deleted_at is null;
    if cardinality(v_ids) > 0 then return case when cardinality(v_ids) = 1 then v_ids[1] end; end if;
  end loop;
  return null;
end
$function$
$n2$,
$n3$CREATE OR REPLACE FUNCTION public.calcom_customer_bookings(p_customer_ids uuid[], p_today date DEFAULT NULL::date)
 RETURNS TABLE(customer_id uuid, booking_at timestamp with time zone, booking_state text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 480: the one cal.com booking each customer's row shows, and its state
  -- (the Owner, 29 Oct 2026); the staff Downline and the affiliate portal's
  -- My Network both read it here. One row for each customer asked about who
  -- is in use. Bookings cancelled or rescheduled away are not read. The
  -- booking is the customer's next one whose Singapore day is today or
  -- later ('upcoming', today's until the day is over); else their most
  -- recent one: 'came' when that Singapore day they visited the centre by
  -- THE visit rule (customer_centre_visit_days, 398/404) or have an invoice
  -- at the Adelphi centre (the store in use coded RETAIL-ADELPHI, not the
  -- Van & RoadShow) dated that business day (its business_date, else the
  -- Singapore date it was made) that was settled (paid, partly paid, FOC,
  -- refund asked or refunded) and is not an online or event order (no web
  -- order, VIP order or event guest names it); else 'miss'. No booking:
  -- 'none'. Whose booking it is: calcom_booking_owner, which also follows a
  -- merge, so the bookings under the phone or inbox of a record a merge
  -- retired into one of them (along a chain) are read too. p_today: today
  -- in Singapore unless given (the tests).
  with recursive t as materialized (
    select c.id, public.normalize_customer_phone(c.phone) as phone_key,
           public.customer_email_match_key(c.email) as email_key
      from public.customers c
     where c.id = any (p_customer_ids) and c.deleted_at is null
  ),
  mt(id, n) as (
    select t.id, 0 from t
    union all
    select m.id, mt.n + 1
      from mt
      join public.audit_logs l on l.record_id = mt.id and l.action = 'customers_merged' and l.table_name = 'customers'
      join public.customers m
        on m.id = case when l.new_data ->> 'merged_from' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                       then (l.new_data ->> 'merged_from')::uuid end
       and m.deleted_at = l.created_at
     where mt.n < 20
  ),
  mk as materialized (
    select public.normalize_customer_phone(c.phone) as phone_key, public.customer_email_match_key(c.email) as email_key
      from mt join public.customers c on c.id = mt.id
     where mt.n > 0
  ),
  d as materialized (
    select coalesce(p_today, public.sg_today()) as today
  ),
  b as materialized (
    select k.uid, k.start_at, public.calcom_booking_owner(k.phone_key, k.email_key) as owner
      from public.calcom_bookings k
     where k.status = 'active'
       and (k.phone_key = any (array(select t.phone_key from t where t.phone_key is not null
                                     union select mk.phone_key from mk where mk.phone_key is not null))
            or k.email_key = any (array(select t.email_key from t where t.email_key is not null
                                        union select mk.email_key from mk where mk.email_key is not null)))
  ),
  pick as materialized (
    select distinct on (b.owner) b.owner, b.start_at, (b.start_at at time zone 'Asia/Singapore')::date as day
      from b cross join d
     where b.owner in (select t.id from t)
     order by b.owner,
              ((b.start_at at time zone 'Asia/Singapore')::date >= d.today) desc,
              case when (b.start_at at time zone 'Asia/Singapore')::date >= d.today then b.start_at end,
              b.start_at desc, b.uid
  ),
  v as materialized (
    select x.customer_id, x.visit_on
      from public.customer_centre_visit_days() x
     where x.customer_id in (select pick.owner from pick cross join d where pick.day < d.today)
  ),
  paid as materialized (
    select distinct pick.owner as customer_id, pick.day
      from pick
     cross join d
      join public.invoices i on i.customer_id = pick.owner
     where pick.day < d.today
       and i.deleted_at is null
       and i.status in ('paid', 'partially_paid', 'completed_foc', 'refund_requested', 'refunded')
       and i.store_id = (select s.id from public.stores s where s.code = 'RETAIL-ADELPHI' and s.deleted_at is null)
       and coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date) = pick.day
       and not exists (select 1 from public.web_orders o where o.invoice_id = i.id)
       and not exists (select 1 from public.event_vip_order_people o where o.invoice_id = i.id)
       and not exists (select 1 from public.event_guests o where o.invoice_id = i.id)
  )
  select t.id, pick.start_at,
         case when pick.owner is null then 'none'
              when pick.day >= d.today then 'upcoming'
              when exists (select 1 from v where v.customer_id = t.id and v.visit_on = pick.day)
                or exists (select 1 from paid where paid.customer_id = t.id and paid.day = pick.day) then 'came'
              else 'miss'
         end
    from t
   cross join d
    left join pick on pick.owner = t.id
$function$
$n3$,
$n4$CREATE OR REPLACE FUNCTION public.calcom_booking_apply(p_uid text, p_status text, p_start timestamp with time zone, p_end timestamp with time zone, p_type_id bigint, p_slug text, p_phone_key text, p_email_key text, p_at timestamp with time zone, p_trigger text, p_rescheduled_to text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
-- 480: one cal.com webhook event onto one booking row (calcom_booking_ingest
-- calls it, as the owner; it is no one's endpoint). Returns 'created',
-- 'updated', 'unchanged' or 'stale'.
--   * An event older than the last change applied to the row is stale; the
--     same moment and the same trigger again is a re-send (unchanged); the
--     same moment and another trigger: only a cancellation applies. A change
--     the calendar fill made is timed by its Google event's 'updated' (no
--     trigger), and is ordered with the webhook's events the same way.
--   * A cancelled or rescheduled-away row stays so (cal.com never brings a
--     booking back): nothing changes it.
--   * A row that is not active keeps no phone or email (it is never shown).
declare r public.calcom_bookings%rowtype;
begin
  select * into r from public.calcom_bookings k where k.uid = p_uid for update;
  if not found then
    insert into public.calcom_bookings
      (uid, start_at, end_at, status, rescheduled_to, event_type_id, event_type_slug, phone_key, email_key,
       source, last_event_at, last_trigger)
    values (p_uid, p_start, case when p_end >= p_start then p_end end, p_status,
            case when p_status = 'rescheduled' then p_rescheduled_to end, p_type_id, p_slug,
            case when p_status = 'active' then p_phone_key end, case when p_status = 'active' then p_email_key end,
            'webhook', p_at, p_trigger)
    on conflict (uid) do nothing;
    if found then return 'created'; end if;
    -- Another delivery stored it first: apply this one to that row.
    select * into r from public.calcom_bookings k where k.uid = p_uid for update;
  end if;

  if r.last_event_at is not null then
    if p_at < r.last_event_at then return 'stale'; end if;
    if p_at = r.last_event_at then
      if p_trigger = r.last_trigger then return 'unchanged'; end if;
      if p_status <> 'cancelled' then return 'stale'; end if;
    end if;
  end if;
  if r.status <> 'active' then return 'unchanged'; end if;

  update public.calcom_bookings k
     set start_at = coalesce(p_start, k.start_at),
         end_at = case when p_start is null then k.end_at when p_end >= p_start then p_end end,
         status = p_status,
         rescheduled_to = case when p_status = 'rescheduled' then p_rescheduled_to end,
         event_type_id = coalesce(p_type_id, k.event_type_id),
         event_type_slug = coalesce(p_slug, k.event_type_slug),
         phone_key = case when p_status = 'active' then coalesce(p_phone_key, k.phone_key) end,
         email_key = case when p_status = 'active' then coalesce(p_email_key, k.email_key) end,
         source = 'webhook', last_event_at = p_at, last_trigger = p_trigger, updated_at = now()
   where k.uid = p_uid;
  return 'updated';
end
$function$
$n4$,
$n5$CREATE OR REPLACE FUNCTION public.calcom_booking_ingest(p_event jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 480: one cal.com webhook (the Owner, 29 Oct 2026), handed in by the Edge
-- Function calcom-webhook with the service key after it checked cal.com's
-- signature. The body as cal.com sends it ({triggerEvent, createdAt,
-- payload}); only the booking's uid, its times, its event type, and a phone
-- and an email inbox to match it to a customer are kept (as
-- normalize_customer_phone and customer_email_match_key read them), never a
-- name, an answer or a title.
--   BOOKING_CREATED      the booking, active.
--   BOOKING_RESCHEDULED  with an old uid (payload.rescheduleUid or
--                        fromReschedule) other than its own: the new booking,
--                        active, and the old one rescheduled away (kept as
--                        such even when it was never seen, so a late
--                        BOOKING_CREATED cannot bring it back); with none, or
--                        its own: the booking moves to the new time.
--   BOOKING_CANCELLED    the booking, cancelled (also one never seen).
--   Anything else        'ignored', nothing stored.
-- The phone: the WhatsApp-Number answer; when it gives no number, the
-- attendee's phone, then the smsReminderNumber answer; a number the centre
-- keeps as its own (ads_excluded_phones, which the calendar fill leaves out
-- as ads_extract_phones does) is no one's, and the next is read. The email:
-- the email answer, else the attendee's. Only text is read. Order and
-- re-sends: calcom_booking_apply. Malformed: SQLSTATE 22023 naming the
-- field, never its value. (The Edge Function refuses a booking without
-- createdAt; one handed in here without it is taken as sent now.)
declare
  v_trigger text; v_at timestamptz; v_p jsonb; v_uid text; v_old text;
  v_start timestamptz; v_end timestamptz; v_old_start timestamptz; v_old_end timestamptz;
  v_type_id bigint; v_slug text; v_phone text; v_email text; v_res text; v_prev text; v_x jsonb;
begin
  if p_event is null or jsonb_typeof(p_event) <> 'object' then
    raise exception 'calcom_booking_ingest: the event is not a JSON object' using errcode = '22023';
  end if;
  if jsonb_typeof(p_event -> 'triggerEvent') is distinct from 'string' then
    raise exception 'calcom_booking_ingest: triggerEvent is missing' using errcode = '22023';
  end if;
  v_trigger := p_event ->> 'triggerEvent';
  if v_trigger not in ('BOOKING_CREATED', 'BOOKING_RESCHEDULED', 'BOOKING_CANCELLED') then
    return jsonb_build_object('result', 'ignored');
  end if;

  if jsonb_typeof(p_event -> 'createdAt') is null or jsonb_typeof(p_event -> 'createdAt') = 'null' then
    v_at := now();
  else
    v_at := public.calcom_parse_time(p_event ->> 'createdAt');
    if v_at is null or jsonb_typeof(p_event -> 'createdAt') <> 'string' then
      raise exception 'calcom_booking_ingest: createdAt is not a moment' using errcode = '22023';
    end if;
    if v_at > now() + interval '1 day' then
      raise exception 'calcom_booking_ingest: createdAt is more than a day ahead' using errcode = '22023';
    end if;
  end if;

  v_p := p_event -> 'payload';
  if v_p is null or jsonb_typeof(v_p) <> 'object' then
    raise exception 'calcom_booking_ingest: payload is missing' using errcode = '22023';
  end if;
  v_uid := case when jsonb_typeof(v_p -> 'uid') = 'string' then v_p ->> 'uid' end;
  if v_uid is null or v_uid !~ '^[A-Za-z0-9_-]{1,128}$' then
    raise exception 'calcom_booking_ingest: payload.uid is missing or not a booking uid' using errcode = '22023';
  end if;

  if v_p ? 'startTime' and jsonb_typeof(v_p -> 'startTime') <> 'null' then
    v_start := public.calcom_parse_time(case when jsonb_typeof(v_p -> 'startTime') = 'string' then v_p ->> 'startTime' end);
    if v_start is null then
      raise exception 'calcom_booking_ingest: payload.startTime is not a moment' using errcode = '22023';
    end if;
  end if;
  if v_start is null and v_trigger <> 'BOOKING_CANCELLED' then
    raise exception 'calcom_booking_ingest: payload.startTime is missing' using errcode = '22023';
  end if;
  v_end := public.calcom_parse_time(case when jsonb_typeof(v_p -> 'endTime') = 'string' then v_p ->> 'endTime' end);

  v_type_id := case when jsonb_typeof(v_p -> 'eventTypeId') = 'number' and v_p ->> 'eventTypeId' ~ '^[0-9]{1,15}$'
                    then (v_p ->> 'eventTypeId')::bigint end;
  v_slug := case when jsonb_typeof(v_p -> 'type') = 'string' then nullif(left(btrim(v_p ->> 'type'), 100), '') end;

  -- A booking answer is {label, value} or the value itself; only text is read.
  -- The first number that is not one of the centre's own is the phone.
  foreach v_x in array array[
      case jsonb_typeof(v_p -> 'responses' -> 'WhatsApp-Number')
        when 'object' then v_p -> 'responses' -> 'WhatsApp-Number' -> 'value' else v_p -> 'responses' -> 'WhatsApp-Number' end,
      v_p #> '{attendees,0,phoneNumber}',
      case jsonb_typeof(v_p -> 'responses' -> 'smsReminderNumber')
        when 'object' then v_p -> 'responses' -> 'smsReminderNumber' -> 'value' else v_p -> 'responses' -> 'smsReminderNumber' end,
      v_p -> 'smsReminderNumber'] loop
    v_phone := public.normalize_customer_phone(case when jsonb_typeof(v_x) = 'string' then v_x #>> '{}' end);
    exit when v_phone is not null and v_phone not in (select '+' || x.phone_e164 from public.ads_excluded_phones x);
    v_phone := null;
  end loop;
  v_x := case jsonb_typeof(v_p -> 'responses' -> 'email')
           when 'object' then v_p -> 'responses' -> 'email' -> 'value' else v_p -> 'responses' -> 'email' end;
  v_email := nullif(btrim(case when jsonb_typeof(v_x) = 'string' then v_x #>> '{}' end), '');
  if v_email is null and jsonb_typeof(v_p #> '{attendees,0,email}') = 'string' then
    v_email := nullif(btrim(v_p #>> '{attendees,0,email}'), '');
  end if;
  v_email := case when length(v_email) <= 320 then public.customer_email_match_key(v_email) end;

  if v_trigger = 'BOOKING_CREATED' then
    v_res := public.calcom_booking_apply(v_uid, 'active', v_start, v_end, v_type_id, v_slug, v_phone, v_email, v_at, v_trigger);
    return jsonb_build_object('result', v_res);
  end if;

  if v_trigger = 'BOOKING_CANCELLED' then
    v_res := public.calcom_booking_apply(v_uid, 'cancelled', v_start, v_end, v_type_id, v_slug, null, null, v_at, v_trigger);
    return jsonb_build_object('result', v_res);
  end if;

  -- BOOKING_RESCHEDULED
  v_old := coalesce(case when jsonb_typeof(v_p -> 'rescheduleUid') = 'string' then nullif(btrim(v_p ->> 'rescheduleUid'), '') end,
                    case when jsonb_typeof(v_p -> 'fromReschedule') = 'string' then nullif(btrim(v_p ->> 'fromReschedule'), '') end);
  if v_old is not null and v_old !~ '^[A-Za-z0-9_-]{1,128}$' then
    raise exception 'calcom_booking_ingest: payload.rescheduleUid is not a booking uid' using errcode = '22023';
  end if;
  v_res := public.calcom_booking_apply(v_uid, 'active', v_start, v_end, v_type_id, v_slug, v_phone, v_email, v_at, v_trigger);
  if v_old is null or v_old = v_uid then
    return jsonb_build_object('result', v_res);
  end if;
  v_old_start := public.calcom_parse_time(case when jsonb_typeof(v_p -> 'rescheduleStartTime') = 'string' then v_p ->> 'rescheduleStartTime' end);
  v_old_end := public.calcom_parse_time(case when jsonb_typeof(v_p -> 'rescheduleEndTime') = 'string' then v_p ->> 'rescheduleEndTime' end);
  v_prev := public.calcom_booking_apply(v_old, 'rescheduled', v_old_start, v_old_end, v_type_id, v_slug, null, null, v_at, v_trigger, v_uid);
  return jsonb_build_object('result', v_res, 'previous', v_prev);
end
$function$
$n5$,
$n6$CREATE OR REPLACE FUNCTION public.calcom_booking_backfill(p_events jsonb, p_from timestamp with time zone, p_to timestamp with time zone, p_listed_at timestamp with time zone, p_dry_run boolean DEFAULT true, p_cancel_uids text[] DEFAULT NULL::text[], p_include_without_uid boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 480: the calendar fill and its monthly catch-up (the Owner, 29 Oct 2026),
-- one call for both, each run with the Owner's OK and a dry run first
-- (p_dry_run, the default: nothing is written). p_events: every event Google
-- Calendar lists for ONE window [p_from, p_to) of at most 400 days (every
-- page), as the Calendar API or its connector gives them: id, summary,
-- description, start and end {dateTime[, timeZone]}, status, updated
-- (anything else is not read); at most 5000. p_listed_at: when the listing
-- began. For each event:
--   * the booking is the cal.com uid of the LAST cal.com booking or
--     reschedule link in its description (cal.com writes its own manage link
--     after the attendee's notes and answers); an event without one is
--     skipped, unless p_include_without_uid (then 'gcal:<event id>');
--   * its start and end: a dateTime with its offset, or without one in the
--     zone its timeZone names; an all-day event, or one whose id, start, end
--     or updated cannot be read, is skipped and counted (the call goes on);
--   * its moment is Google's 'updated' (p_listed_at when it has none:
--     counted; a listing shows no change made after it began); an 'updated'
--     later than now (10 minutes' leeway) cannot be one, and is a shape that
--     cannot be read. It is applied only when it is newer than the last
--     change applied to the booking, whoever made it (the webhook or a
--     fill): a booking not seen before is created; an active one whose start
--     or end differ is moved; the same is unchanged. An older event changes
--     nothing: unchanged when it agrees (cal.com writes its Google event a
--     moment before it sends the webhook), else stale, and listed as
--     kept_newer (the calendar's start, then the start kept). A booking
--     cancelled or rescheduled away stays so, whatever the calendar shows
--     (terminal). A title staff marked "Cxl" is still a booking (a no-show);
--     an event Google itself lists cancelled cancels it (one never seen is
--     kept cancelled);
--   * a booking not seen before needs a number in its title, where cal.com
--     writes the WhatsApp-Number: the first word holding one, else the first
--     number in the title (as ads_extract_phones finds numbers, the centre's
--     own left out, and normalize_customer_phone reads them); no email is
--     read; a booking already stored keeps its phone and email;
--   * a booking listed more than once (Google's Duplicate copies cal.com's
--     link too): a live copy starting when the stored booking starts keeps
--     it there; else a stored booking's copy updated last, a new booking's
--     earliest copy; each other copy is listed as repeated_uid (its start,
--     then the start of the copy read).
-- Missing from the calendar: an active booking, from either source, whose
-- start is in the window, that no listed event carries and that has not
-- changed since p_listed_at (one made after the listing began is not in
-- it): reported in every run; cancelled only on a real run, and only when
-- p_cancel_uids names it (the uids the Owner agreed to cancel after seeing
-- them in the dry run): a missing booking not named is only reported, and a
-- named uid that is not missing in this call is left alone and counted. A
-- booking outside the window is never missing.
-- Answers counts, and the changes made (or that a dry run would make) as
-- {uid, change, old_start, new_start} in Singapore time: the missing
-- bookings first (by start), then the others in the calendar's order, at
-- most 500 (truncated): uids and times, nothing else.
declare
  e jsonb; i int; v_dry boolean := coalesce(p_dry_run, true); v_zones text[] := '{}';
  a_ord int[] := '{}'; a_uid text[] := '{}'; a_gone boolean[] := '{}'; a_kind text[] := '{}';
  a_start timestamptz[] := '{}'; a_end timestamptz[] := '{}'; a_at timestamptz[] := '{}';
  v_listed text[] := '{}';
  v_part text; v_txt text; v_zone text; v_t timestamptz; v_start timestamptz; v_end timestamptz; v_at timestamptz;
  v_kind text; v_uid text; v_link text; v_gid text; v_gone boolean; v_phone text; v_title text;
  r record; k public.calcom_bookings%rowtype;
  v_changes jsonb[] := '{}'; v_missing jsonb[] := '{}';
  n_events int := 0; n_created int := 0; n_moved int := 0; n_unchanged int := 0; n_stale int := 0;
  n_cancelled int := 0; n_terminal int := 0; n_repeated int := 0; n_all_day int := 0; n_bad int := 0;
  n_gone_bare int := 0; n_no_link int := 0; n_no_phone int := 0; n_no_updated int := 0;
  n_missing int := 0; n_cancel_missing int := 0;
begin
  -- The call.
  if p_events is null or jsonb_typeof(p_events) <> 'array' then
    raise exception 'calcom_booking_backfill: the events are not a JSON array' using errcode = '22023'; end if;
  if jsonb_array_length(p_events) > 5000 then
    raise exception 'calcom_booking_backfill: at most 5000 events in one call' using errcode = '22023'; end if;
  if p_from is null or p_to is null then
    raise exception 'calcom_booking_backfill: p_from and p_to (the window listed) are needed' using errcode = '22023'; end if;
  if p_to <= p_from or p_to - p_from > interval '400 days' then
    raise exception 'calcom_booking_backfill: the window must end after it starts and last at most 400 days' using errcode = '22023'; end if;
  if p_listed_at is null or p_listed_at > now() + interval '10 minutes' then
    raise exception 'calcom_booking_backfill: p_listed_at (when the listing began) is needed and cannot be later than now' using errcode = '22023'; end if;
  if cardinality(p_cancel_uids) > 0 and jsonb_array_length(p_events) = 0 then
    raise exception 'calcom_booking_backfill: p_cancel_uids with no event listed' using errcode = '22023'; end if;

  -- The zones named by start and end times written without an offset (read once).
  if exists (select 1 from jsonb_array_elements(p_events) x(ev)
              where jsonb_typeof(x.ev) = 'object'
                and (x.ev #>> '{start,dateTime}' !~ '(Z|[+-]\d{2}(:?\d{2})?)$' or x.ev #>> '{end,dateTime}' !~ '(Z|[+-]\d{2}(:?\d{2})?)$')) then
    select coalesce(array_agg(z.name), '{}') into v_zones
      from pg_timezone_names z
     where z.name in (select x.ev #>> array[s.part, 'timeZone']
                        from jsonb_array_elements(p_events) x(ev) cross join unnest(array['start', 'end']) s(part)
                       where jsonb_typeof(x.ev) = 'object' and jsonb_typeof(x.ev #> array[s.part, 'timeZone']) = 'string');
  end if;

  -- Each event, read.
  for e, i in select x.ev, x.ord::int from jsonb_array_elements(p_events) with ordinality x(ev, ord) order by x.ord loop
    n_events := n_events + 1;
    v_kind := null; v_uid := null; v_start := null; v_end := null; v_at := null;
    v_gid := case when jsonb_typeof(e) = 'object' and jsonb_typeof(e -> 'id') = 'string' and (e ->> 'id') ~ '^[A-Za-z0-9_]{1,255}$'
                  then e ->> 'id' end;
    v_link := case when jsonb_typeof(e) = 'object' and jsonb_typeof(e -> 'description') = 'string'
                   then substring(e ->> 'description' from '.*cal\.com/(?:booking|reschedule)/([A-Za-z0-9_-]{8,128})') end;
    v_gone := (jsonb_typeof(e) = 'object' and (e ->> 'status' = 'cancelled' or e -> 'deleted' = 'true'::jsonb)) is true;
    -- Every uid the calendar carries, read or not, is listed (never missing).
    if v_link is not null then v_listed := array_append(v_listed, v_link);
    elsif v_gid is not null then v_listed := array_append(v_listed, 'gcal:' || v_gid); end if;
    if v_gid is null then
      v_kind := 'bad';
    elsif jsonb_typeof(e -> 'start') is distinct from 'object' and v_gone then
      v_kind := 'gone_bare';
    elsif jsonb_typeof(e #> '{start,dateTime}') is distinct from 'string' and jsonb_typeof(e #> '{start,date}') = 'string' then
      v_kind := 'all_day';
    else
      foreach v_part in array array['start', 'end'] loop
        v_t := null;
        v_txt := case when jsonb_typeof(e #> array[v_part, 'dateTime']) = 'string' then e #>> array[v_part, 'dateTime'] end;
        v_zone := coalesce(case when jsonb_typeof(e #> array[v_part, 'timeZone']) = 'string' then e #>> array[v_part, 'timeZone'] end,
                           case when jsonb_typeof(e #> '{start,timeZone}') = 'string' then e #>> '{start,timeZone}' end);
        if v_txt ~ '(Z|[+-]\d{2}(:?\d{2})?)$' then
          v_t := public.calcom_parse_time(v_txt);
        elsif v_txt ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?$' and v_zone = any (v_zones) then
          begin
            v_t := v_txt::timestamp at time zone v_zone;
          exception when others then v_t := null;
          end;
          if v_t < '2000-01-01 00:00:00+00' or v_t >= '2100-01-01 00:00:00+00' then v_t := null; end if;
        end if;
        if v_part = 'start' then v_start := v_t; else v_end := v_t; end if;
      end loop;
      if jsonb_typeof(e -> 'updated') is null or jsonb_typeof(e -> 'updated') = 'null' then
        v_at := p_listed_at; n_no_updated := n_no_updated + 1;
      else
        v_at := public.calcom_parse_time(case when jsonb_typeof(e -> 'updated') = 'string' then e ->> 'updated' end);
      end if;
      if v_start is null or v_end is null or v_at is null or v_at > now() + interval '10 minutes' then v_kind := 'bad'; end if;
      if v_end < v_start then v_end := null; end if;
    end if;
    v_uid := coalesce(v_link, case when coalesce(p_include_without_uid, false) and v_gid is not null then 'gcal:' || v_gid end);
    a_ord := array_append(a_ord, i); a_uid := array_append(a_uid, v_uid); a_gone := array_append(a_gone, v_gone);
    a_kind := array_append(a_kind, v_kind); a_start := array_append(a_start, v_start); a_end := array_append(a_end, v_end);
    a_at := array_append(a_at, v_at);
  end loop;

  -- Each booking's chosen copy, applied in the calendar's order: a readable
  -- live copy; of those, one starting when the stored booking starts (a
  -- staff Duplicate elsewhere moves nothing); else a stored booking's copy
  -- updated last, a new booking's earliest copy.
  for r in
    select x.ord, x.uid, x.gone, x.kind, x.st, x.en, x.at,
           case when x.uid is not null then row_number() over w end as nth,
           first_value(x.st) over w as chosen_st
      from (select u.ord, u.uid, u.gone, u.kind, u.st, u.en, u.at, b.start_at as stored_st, b.uid is not null as stored
              from unnest(a_ord, a_uid, a_gone, a_kind, a_start, a_end, a_at) u(ord, uid, gone, kind, st, en, at)
              left join public.calcom_bookings b on b.uid = u.uid) x
    window w as (partition by x.uid
                 order by (x.kind is not null), x.gone, (x.stored_st = x.st) is not true,
                          case when x.stored then x.at end desc nulls last, x.st, x.at desc nulls last, x.ord)
     order by x.ord
  loop
    if r.kind = 'bad' and r.uid is null then n_bad := n_bad + 1; continue; end if;
    if r.kind = 'gone_bare' then n_gone_bare := n_gone_bare + 1; continue; end if;
    if r.kind = 'all_day' then n_all_day := n_all_day + 1; continue; end if;
    if r.uid is null then n_no_link := n_no_link + 1; continue; end if;
    if r.nth > 1 then
      n_repeated := n_repeated + 1;
      v_changes := array_append(v_changes, jsonb_build_object('uid', r.uid, 'change', 'repeated_uid', 'old_start', r.st, 'new_start', r.chosen_st));
      continue;
    end if;
    if r.kind = 'bad' then n_bad := n_bad + 1; continue; end if;

    if v_dry then
      select * into k from public.calcom_bookings b where b.uid = r.uid;
    else
      select * into k from public.calcom_bookings b where b.uid = r.uid for update;
    end if;
    if not found then
      v_phone := null;
      if not r.gone then
        e := p_events -> (r.ord - 1);
        v_title := case when jsonb_typeof(e -> 'summary') = 'string' then e ->> 'summary' else '' end;
        select c.n into v_phone
          from (select 1 as pass, w.ord as word_no, p.ord as no, public.normalize_customer_phone('+' || p.ph) as n
                  from regexp_split_to_table(v_title, '\s+') with ordinality w(word, ord)
                 cross join lateral unnest(public.ads_extract_phones(w.word)) with ordinality p(ph, ord)
                union all
                select 2, 0, p.ord, public.normalize_customer_phone('+' || p.ph)
                  from unnest(public.ads_extract_phones(v_title)) with ordinality p(ph, ord)) c
         where c.n is not null
         order by c.pass, c.word_no, c.no
         limit 1;
        if v_phone is null then n_no_phone := n_no_phone + 1; continue; end if;
      end if;
      if not v_dry then
        insert into public.calcom_bookings (uid, start_at, end_at, status, phone_key, source, last_event_at)
        values (r.uid, r.st, r.en, case when r.gone then 'cancelled' else 'active' end, v_phone, 'backfill', r.at)
        on conflict (uid) do nothing;
        -- The webhook stored it in the same instant: its row stands.
        if not found then n_stale := n_stale + 1; continue; end if;
      end if;
      if r.gone then
        n_cancelled := n_cancelled + 1;
        v_changes := array_append(v_changes, jsonb_build_object('uid', r.uid, 'change', 'cancelled', 'old_start', r.st, 'new_start', null));
      else
        n_created := n_created + 1;
        v_changes := array_append(v_changes, jsonb_build_object('uid', r.uid, 'change', 'created', 'old_start', null, 'new_start', r.st));
      end if;
      continue;
    end if;

    if k.status <> 'active' then n_terminal := n_terminal + 1; continue; end if;
    if r.at < k.last_event_at
       or (r.at = k.last_event_at and (r.gone or (k.start_at, k.end_at) is distinct from (r.st, r.en))) then
      -- Older than the change last applied: nothing is written. Agreeing, it
      -- is unchanged; disagreeing, it is stale and listed (kept_newer).
      if not r.gone and (k.start_at, k.end_at) is not distinct from (r.st, r.en) then
        n_unchanged := n_unchanged + 1;
      else
        n_stale := n_stale + 1;
        v_changes := array_append(v_changes, jsonb_build_object('uid', r.uid, 'change', 'kept_newer',
                       'old_start', case when not r.gone then r.st end, 'new_start', k.start_at));
      end if;
      continue;
    end if;
    if r.gone then
      if not v_dry then
        update public.calcom_bookings b
           set status = 'cancelled', phone_key = null, email_key = null, rescheduled_to = null,
               source = 'backfill', last_event_at = r.at, last_trigger = null, updated_at = now()
         where b.uid = r.uid;
      end if;
      n_cancelled := n_cancelled + 1;
      v_changes := array_append(v_changes, jsonb_build_object('uid', r.uid, 'change', 'cancelled', 'old_start', k.start_at, 'new_start', null));
    elsif (k.start_at, k.end_at) is not distinct from (r.st, r.en) then
      n_unchanged := n_unchanged + 1;
    else
      if not v_dry then
        update public.calcom_bookings b
           set start_at = r.st, end_at = r.en, source = 'backfill', last_event_at = r.at, last_trigger = null, updated_at = now()
         where b.uid = r.uid;
      end if;
      n_moved := n_moved + 1;
      v_changes := array_append(v_changes, jsonb_build_object('uid', r.uid, 'change', 'moved', 'old_start', k.start_at, 'new_start', r.st));
    end if;
  end loop;

  -- Missing from the calendar: listed first (the Owner decides on them);
  -- cancelled only when p_cancel_uids names them.
  for r in
    select b.uid, b.start_at
      from public.calcom_bookings b
      left join (select distinct l.uid from unnest(v_listed) l(uid)) l on l.uid = b.uid
     where b.status = 'active' and b.start_at >= p_from and b.start_at < p_to
       and b.updated_at <= p_listed_at and l.uid is null
     order by b.start_at, b.uid
  loop
    if r.uid = any (p_cancel_uids) then
      if not v_dry then
        update public.calcom_bookings b
           set status = 'cancelled', phone_key = null, email_key = null, rescheduled_to = null, source = 'backfill',
               last_event_at = greatest(b.last_event_at, p_listed_at), last_trigger = null, updated_at = now()
         where b.uid = r.uid and b.status = 'active' and b.updated_at <= p_listed_at;
        -- Changed meanwhile (a webhook): no longer missing.
        if not found then continue; end if;
      end if;
      n_missing := n_missing + 1; n_cancel_missing := n_cancel_missing + 1;
      v_missing := array_append(v_missing, jsonb_build_object('uid', r.uid, 'change', 'cancelled_missing', 'old_start', r.start_at, 'new_start', null));
    else
      n_missing := n_missing + 1;
      v_missing := array_append(v_missing, jsonb_build_object('uid', r.uid, 'change', 'missing_from_calendar', 'old_start', r.start_at, 'new_start', null));
    end if;
  end loop;
  v_changes := v_missing || v_changes;

  return jsonb_build_object('dry_run', v_dry, 'events', n_events,
    'created', n_created, 'moved', n_moved, 'unchanged', n_unchanged, 'stale', n_stale, 'cancelled', n_cancelled,
    'terminal', n_terminal, 'repeated_uid', n_repeated, 'skipped_all_day', n_all_day, 'skipped_bad_shape', n_bad,
    'skipped_deleted_no_data', n_gone_bare, 'skipped_no_link', n_no_link, 'skipped_no_phone', n_no_phone,
    'no_updated_time', n_no_updated, 'missing_from_calendar', n_missing, 'cancelled_missing', n_cancel_missing,
    'cancel_uids_not_missing', (select count(distinct u.uid) from unnest(p_cancel_uids) u(uid) where u.uid is not null) - n_cancel_missing,
    'changes', (select coalesce(jsonb_agg(jsonb_build_object('uid', c ->> 'uid', 'change', c ->> 'change',
                         'old_start', to_char((c ->> 'old_start')::timestamptz at time zone 'Asia/Singapore', 'YYYY-MM-DD"T"HH24:MI:SS"+08:00"'),
                         'new_start', to_char((c ->> 'new_start')::timestamptz at time zone 'Asia/Singapore', 'YYYY-MM-DD"T"HH24:MI:SS"+08:00"'))
                       order by n), '[]'::jsonb)
                  from unnest(v_changes[1:500]) with ordinality x(c, n)),
    'truncated', cardinality(v_changes) > 500);
end
$function$
$n6$];

  -- ── Relied on, not changed (production, 29 Oct 2026) ───────────────────
  c_relied constant text[] := array['normalize_customer_phone(text)', 'inspect_customer_phone(text,text)',
    'customer_email_match_key(text)', 'customer_centre_visit_days()', 'customer_centre_visits()', 'sg_today()',
    'ads_extract_phones(text)', 'ads_normalize_phone(text,text)', 'require_active_staff(text[])',
    'current_affiliate_customer_id()', 'merge_customer_records(uuid,uuid,text,uuid)', 'write_audit(text,uuid,text,jsonb,jsonb)'];
  c_relied_md5 constant text[] := array['b2bfac910e0c9eff402ba44e19750bee', '6672c4d1963996f3b601896f4a55916e',
    'be468815c9626fff1728e2cfcd484b66', '2129857d6ff9f29dcf2cbccc9f13e5bc', 'c07a5a0cbbf52ba45e5dc911b20002da',
    '1c1289f18e24d8370e9a6364c9c06fca', 'b93776dba353519d18d12384f7883e3b', 'a61154d7e66e01b273e8b9911a213a2c',
    '877b3aa74cea559881979bb161c450e2', '51695acf5f26ce3918d6003d0c980b0f', 'ba05c2b1fb4c0e14d369c01d06a635b0',
    'b194f839993670c5b5dd28e934c2a829'];

  -- ── The table and the customers indexes as tested ───────────────────────
  c_shape constant text := '32e6a37c4ddd3627b7dc2c84405477f6';
  c_email_idx constant text := 'CREATE INDEX idx_customers_email_match_key ON public.customers USING btree (customer_email_match_key(email)) WHERE ((deleted_at IS NULL) AND (email IS NOT NULL))';
  -- A merged record's booking follows the merge (F): the deleted records holding a phone or an inbox, found by index.
  c_del_idx_names constant text[] := array['idx_customers_deleted_phone_norm', 'idx_customers_deleted_email_match_key'];
  c_del_idx_defs constant text[] := array[
    'CREATE INDEX idx_customers_deleted_phone_norm ON public.customers USING btree (normalize_customer_phone(phone)) WHERE (deleted_at IS NOT NULL)',
    'CREATE INDEX idx_customers_deleted_email_match_key ON public.customers USING btree (customer_email_match_key(email)) WHERE ((deleted_at IS NOT NULL) AND (email IS NOT NULL))'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; v_md5 text; v_oid regprocedure; v_shape text; v_acl text[];
  -- the self-test's made-up records
  t_sfx text; t_base int; t_ph text[]; t_ref uuid; t_a uuid; t_b uuid; t_c uuid; t_d uuid; t_e uuid;
  t_f uuid; t_g uuid; t_today date; t_ans jsonb; t_rows jsonb; t_n int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  for i in 1 .. cardinality(c_chg_sigs) loop
    if md5(c_chg_defs[i]) <> c_chg_after[i] then
      raise exception '480: the text of public.% is not the tested one (md5 %)', c_chg_sigs[i], md5(c_chg_defs[i]); end if;
    v_oid := to_regprocedure('public.' || c_chg_sigs[i]);
    if v_oid is null then raise exception '480: public.% is missing', c_chg_sigs[i]; end if;
    v_md5 := md5(pg_get_functiondef(v_oid));
    if v_md5 not in (c_chg_before[i], c_chg_after[i]) then
      raise exception '480: public.% is neither production''s version of 29 Oct 2026 nor this file''s (md5 %). Re-read it and re-test before applying.',
        c_chg_sigs[i], v_md5; end if;
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid) is distinct from c_chg_acl then
      raise exception '480: the grants of public.% are not as read on 29 Oct 2026', c_chg_sigs[i]; end if;
  end loop;

  for i in 1 .. cardinality(c_new_sigs) loop
    if md5(c_new_defs[i]) <> c_new_md5[i] then
      raise exception '480: the text of public.% is not the tested one (md5 %)', c_new_sigs[i], md5(c_new_defs[i]); end if;
    v_oid := to_regprocedure('public.' || c_new_sigs[i]);
    if v_oid is not null and md5(pg_get_functiondef(v_oid)) <> c_new_md5[i] then
      raise exception '480: public.% exists and is not this migration''s (md5 %). Re-read it and re-test before applying.',
        c_new_sigs[i], md5(pg_get_functiondef(v_oid)); end if;
    select string_agg(p.oid::regprocedure::text, ', ') into v
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = split_part(c_new_sigs[i], '(', 1)
       and p.oid <> coalesce(v_oid, 0);
    if v is not null then raise exception '480: another function takes the name of public.%: %', c_new_sigs[i], v; end if;
  end loop;

  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '480: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The columns read.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customers', 'id', 'uuid'), ('customers', 'full_name', 'text'), ('customers', 'phone', 'text'),
                 ('customers', 'email', 'text'), ('customers', 'deleted_at', 'timestamp with time zone'),
                 ('customers', 'referred_by', 'uuid'), ('customers', 'referred_at', 'timestamp with time zone'),
                 ('customers', 'created_at', 'timestamp with time zone'),
                 ('ads_excluded_phones', 'phone_e164', 'text'),
                 ('stores', 'id', 'uuid'), ('stores', 'code', 'text'), ('stores', 'deleted_at', 'timestamp with time zone'),
                 ('invoices', 'id', 'uuid'), ('invoices', 'customer_id', 'uuid'), ('invoices', 'store_id', 'uuid'),
                 ('invoices', 'status', 'invoice_status'), ('invoices', 'deleted_at', 'timestamp with time zone'),
                 ('invoices', 'business_date', 'date'), ('invoices', 'created_at', 'timestamp with time zone'),
                 ('web_orders', 'invoice_id', 'uuid'), ('event_vip_order_people', 'invoice_id', 'uuid'),
                 ('event_guests', 'invoice_id', 'uuid'),
                 ('audit_logs', 'id', 'uuid'), ('audit_logs', 'table_name', 'text'), ('audit_logs', 'record_id', 'uuid'),
                 ('audit_logs', 'action', 'text'), ('audit_logs', 'new_data', 'jsonb'),
                 ('audit_logs', 'created_at', 'timestamp with time zone')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '480: these columns are missing or not as read on 29 Oct 2026: %', v; end if;
  -- The invoice statuses as read (E sorts each of them), and the Adelphi centre (E: by its code, never an id).
  if (select array_agg(e.enumlabel::text order by e.enumsortorder) from pg_enum e where e.enumtypid = to_regtype('public.invoice_status'))
     is distinct from array['draft', 'unpaid', 'partially_paid', 'paid', 'cancellation_requested', 'cancelled', 'refund_requested',
                            'refunded', 'completed_foc'] then
    raise exception '480: the invoice statuses are not the nine read on 29 Oct 2026. Re-read them and re-test before applying.'; end if;
  if (select count(*) from public.stores s where s.code = 'RETAIL-ADELPHI' and s.deleted_at is null) <> 1 then
    raise exception '480: exactly one store in use must be coded RETAIL-ADELPHI (the Adelphi centre); found %',
      (select count(*) from public.stores s where s.code = 'RETAIL-ADELPHI' and s.deleted_at is null); end if;

  -- The table: missing, or exactly this file's.
  if to_regclass('public.calcom_bookings') is not null then
    select md5(string_agg(s.x, E'\n' order by s.x)) into v_shape from (
      select 'col ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' ' || a.attnotnull::text || ' '
             || coalesce(pg_get_expr(d.adbin, d.adrelid), '') as x
        from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
       where a.attrelid = to_regclass('public.calcom_bookings') and a.attnum > 0 and not a.attisdropped
      union all
      select 'con ' || c.conname || ' ' || pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = to_regclass('public.calcom_bookings')
      union all
      select 'idx ' || pg_get_indexdef(i.indexrelid) from pg_index i where i.indrelid = to_regclass('public.calcom_bookings')) s;
    if v_shape is distinct from c_shape then
      raise exception '480: public.calcom_bookings exists and is not this migration''s (shape %)', v_shape; end if;
  end if;
  if to_regclass('public.idx_customers_email_match_key') is not null
     and pg_get_indexdef(to_regclass('public.idx_customers_email_match_key')) <> c_email_idx then
    raise exception '480: public.idx_customers_email_match_key exists and is not this migration''s'; end if;
  for i in 1 .. cardinality(c_del_idx_names) loop
    if to_regclass('public.' || c_del_idx_names[i]) is not null
       and pg_get_indexdef(to_regclass('public.' || c_del_idx_names[i])) <> c_del_idx_defs[i] then
      raise exception '480: public.% exists and is not this migration''s', c_del_idx_names[i]; end if;
  end loop;

  -- ── Change ──────────────────────────────────────────────────────────────
  create table if not exists public.calcom_bookings (
    uid text primary key,
    start_at timestamptz,
    end_at timestamptz,
    status text not null,
    rescheduled_to text,
    event_type_id bigint,
    event_type_slug text,
    phone_key text,
    email_key text,
    source text not null,
    last_event_at timestamptz,
    last_trigger text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint calcom_bookings_uid_check check (uid ~ '^([A-Za-z0-9_-]{1,128}|gcal:[A-Za-z0-9_]{1,255})$'),
    constraint calcom_bookings_status_check check (status in ('active', 'cancelled', 'rescheduled')),
    constraint calcom_bookings_source_check check (source in ('webhook', 'backfill')),
    constraint calcom_bookings_active_start_check check (status <> 'active' or start_at is not null),
    constraint calcom_bookings_end_check check (end_at is null or (start_at is not null and end_at >= start_at)),
    constraint calcom_bookings_rescheduled_to_check check (rescheduled_to is null or (status = 'rescheduled' and rescheduled_to ~ '^[A-Za-z0-9_-]{1,128}$')),
    constraint calcom_bookings_slug_check check (event_type_slug is null or length(event_type_slug) <= 100),
    constraint calcom_bookings_phone_key_check check (phone_key is null or (status = 'active' and phone_key ~ '^\+[1-9][0-9]{6,14}$')),
    constraint calcom_bookings_email_key_check check (email_key is null or (status = 'active' and length(email_key) <= 320)),
    constraint calcom_bookings_trigger_check check (last_trigger is null or last_trigger in ('BOOKING_CREATED', 'BOOKING_RESCHEDULED', 'BOOKING_CANCELLED')),
    constraint calcom_bookings_event_check check (last_event_at is not null and (source = 'webhook') = (last_trigger is not null))
  );
  create index if not exists calcom_bookings_phone_key_idx on public.calcom_bookings (phone_key) where status = 'active';
  create index if not exists calcom_bookings_email_key_idx on public.calcom_bookings (email_key) where status = 'active';
  create index if not exists idx_customers_email_match_key on public.customers (public.customer_email_match_key(email))
    where deleted_at is null and email is not null;
  create index if not exists idx_customers_deleted_phone_norm on public.customers (public.normalize_customer_phone(phone))
    where deleted_at is not null;
  create index if not exists idx_customers_deleted_email_match_key on public.customers (public.customer_email_match_key(email))
    where deleted_at is not null and email is not null;
  alter table public.calcom_bookings enable row level security;
  revoke all on table public.calcom_bookings from public, anon, authenticated, service_role;
  grant select on table public.calcom_bookings to service_role;
  comment on table public.calcom_bookings is
    '480: cal.com bookings (webhook calcom-webhook; fill and monthly catch-up from Google Calendar); matched to customers when read (calcom_booking_owner); server only.';

  for i in 1 .. cardinality(c_new_sigs) loop
    if to_regprocedure('public.' || c_new_sigs[i]) is null then execute c_new_defs[i];
    else raise notice '480: public.% is already this version; left alone', c_new_sigs[i]; end if;
    execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sigs[i]);
    if c_new_service[i] then execute format('grant execute on function public.%s to service_role', c_new_sigs[i]); end if;
  end loop;

  for i in 1 .. cardinality(c_chg_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_chg_sigs[i]))) = c_chg_before[i] then execute c_chg_defs[i];
    else raise notice '480: public.% is already this version; left alone', c_chg_sigs[i]; end if;
  end loop;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  for i in 1 .. cardinality(c_chg_sigs) loop
    v_oid := to_regprocedure('public.' || c_chg_sigs[i]);
    if md5(pg_get_functiondef(v_oid)) <> c_chg_after[i] then
      raise exception '480: public.% was installed with an md5 other than the tested one', c_chg_sigs[i]; end if;
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid) is distinct from c_chg_acl
       or has_function_privilege('anon', v_oid, 'execute') then
      raise exception '480: the grants of public.% changed', c_chg_sigs[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new_sigs) loop
    v_oid := to_regprocedure('public.' || c_new_sigs[i]);
    if v_oid is null or md5(pg_get_functiondef(v_oid)) <> c_new_md5[i] then
      raise exception '480: public.% was installed with an md5 other than the tested one', c_new_sigs[i]; end if;
    v_acl := array['postgres=X/postgres'];
    if c_new_service[i] then v_acl := v_acl || 'service_role=X/postgres'::text; end if;
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid) is distinct from v_acl then
      raise exception '480: public.% does not have the grants tested', c_new_sigs[i]; end if;
  end loop;
  select md5(string_agg(s.x, E'\n' order by s.x)) into v_shape from (
    select 'col ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' ' || a.attnotnull::text || ' '
           || coalesce(pg_get_expr(d.adbin, d.adrelid), '') as x
      from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
     where a.attrelid = to_regclass('public.calcom_bookings') and a.attnum > 0 and not a.attisdropped
    union all
    select 'con ' || c.conname || ' ' || pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = to_regclass('public.calcom_bookings')
    union all
    select 'idx ' || pg_get_indexdef(i.indexrelid) from pg_index i where i.indrelid = to_regclass('public.calcom_bookings')) s;
  if v_shape is distinct from c_shape then
    raise exception '480: public.calcom_bookings was made with another shape (%)', v_shape; end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.calcom_bookings'::regclass)
     or exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'calcom_bookings')
     or has_table_privilege('anon', 'public.calcom_bookings', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.calcom_bookings', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'public.calcom_bookings', 'insert,update,delete,truncate,references,trigger')
     or not has_table_privilege('service_role', 'public.calcom_bookings', 'select') then
    raise exception '480: public.calcom_bookings is not server only (row-level security, no policy, the service role reading only)'; end if;
  if pg_get_indexdef(to_regclass('public.idx_customers_email_match_key')) is distinct from c_email_idx then
    raise exception '480: public.idx_customers_email_match_key is not as tested'; end if;
  for i in 1 .. cardinality(c_del_idx_names) loop
    if pg_get_indexdef(to_regclass('public.' || c_del_idx_names[i])) is distinct from c_del_idx_defs[i] then
      raise exception '480: public.% is not as tested', c_del_idx_names[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  begin
    -- As the server (no request): require_active_staff lets it through.
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_today := public.sg_today();
    -- Eight fictional phones in a row (+61 2 5550 nnnn) that no customer, in
    -- use or deleted (a merged record's booking follows the merge), and no
    -- active booking holds (a cancelled booking is no one's). Each test is a
    -- range scan of idx_customers_phone_norm, idx_customers_deleted_phone_norm
    -- and calcom_bookings_phone_key_idx (all partial, hence the conditions):
    -- never a pass reading every customer's phone, which would hold the
    -- customers lock for many minutes on production's 13,000.
    select min(g) into t_base from generate_series(4800, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.calcom_bookings k
                        where k.status = 'active'
                          and k.phone_key between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '480: the self-test found no free fictional phones'; end if;
    t_ph := array(select '+6125550' || lpad((t_base + n)::text, 4, '0') from generate_series(0, 7) n);
    insert into public.customers (full_name, phone, email) values ('480 Check Referrer', t_ph[1], '480-check-r-' || t_sfx || '@example.invalid')
      returning id into t_ref;
    insert into public.customers (full_name, phone, referred_by) values ('480 Check Upcoming', t_ph[2], t_ref) returning id into t_a;
    insert into public.customers (full_name, phone, referred_by) values ('480 Check Came', t_ph[3], t_ref) returning id into t_b;
    insert into public.customers (full_name, phone, referred_by) values ('480 Check Missed', t_ph[4], t_ref) returning id into t_c;
    insert into public.customers (full_name, phone, referred_by) values ('480 Check None', t_ph[5], t_ref) returning id into t_d;
    insert into public.customers (full_name, phone, email, referred_by)
    values ('480 Check Cancelled', t_ph[6], '480-check-e-' || t_sfx || '@example.invalid', t_a) returning id into t_e;
    insert into public.customers (full_name, phone, referred_by) values ('480 Check Kept', t_ph[7], t_ref) returning id into t_f;
    insert into public.customers (full_name, phone) values ('480 Check Merged', t_ph[8]) returning id into t_g;

    t_ans := public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CREATED', 'createdAt', now() - interval '2 hours',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'a', 'type', 'free', 'eventTypeId', 1,
        'startTime', ((t_today + 3) + time '14:00') at time zone 'Asia/Singapore',
        'endTime', ((t_today + 3) + time '15:00') at time zone 'Asia/Singapore',
        'responses', jsonb_build_object('WhatsApp-Number', jsonb_build_object('label', 'WhatsApp Number', 'value', t_ph[2])))));
    if t_ans is distinct from '{"result": "created"}'::jsonb then raise exception '480: the self-test''s booking was not created: %', t_ans; end if;
    -- The same event again: nothing changes.
    t_ans := public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CREATED', 'createdAt', now() - interval '2 hours',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'a', 'startTime', ((t_today + 3) + time '14:00') at time zone 'Asia/Singapore',
        'responses', jsonb_build_object('WhatsApp-Number', t_ph[2]))));
    if t_ans is distinct from '{"result": "unchanged"}'::jsonb then raise exception '480: the self-test''s re-sent booking changed something: %', t_ans; end if;
    -- An older event: stale.
    t_ans := public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CANCELLED', 'createdAt', now() - interval '3 hours',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'a')));
    if t_ans is distinct from '{"result": "stale"}'::jsonb then raise exception '480: the self-test''s older event was applied: %', t_ans; end if;
    -- Rescheduled to a new uid: the old one is rescheduled away.
    t_ans := public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_RESCHEDULED', 'createdAt', now() - interval '1 hour',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'b', 'rescheduleUid', '480chk' || t_sfx || 'a',
        'startTime', ((t_today + 4) + time '10:00') at time zone 'Asia/Singapore',
        'responses', jsonb_build_object('WhatsApp-Number', t_ph[2]))));
    if t_ans is distinct from '{"result": "created", "previous": "updated"}'::jsonb
       or (select k.status from public.calcom_bookings k where k.uid = '480chk' || t_sfx || 'a') is distinct from 'rescheduled' then
      raise exception '480: the self-test''s reschedule did not move the booking: %', t_ans; end if;
    -- Two days ago: came (a consultant's survey with an answer that day) and missed.
    perform public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CREATED', 'createdAt', now() - interval '5 days',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'c', 'startTime', ((t_today - 2) + time '11:00') at time zone 'Asia/Singapore',
        'attendees', jsonb_build_array(jsonb_build_object('phoneNumber', t_ph[3])))));
    perform public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CREATED', 'createdAt', now() - interval '5 days',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'd', 'startTime', ((t_today - 2) + time '11:00') at time zone 'Asia/Singapore',
        'responses', jsonb_build_object('WhatsApp-Number', t_ph[4]))));
    insert into public.health_surveys (survey_no, customer_id, full_name, phone, source, submitted_at, remarks_condition)
    values ('HS-480CHK-' || t_sfx, t_b, '480 Check Came', t_ph[3], 'consultant', ((t_today - 2) + time '12:00') at time zone 'Asia/Singapore',
            '480 check');
    -- Tier 2: booked and cancelled (matched by the email alone: its phone is not on it).
    perform public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CREATED', 'createdAt', now() - interval '2 days',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'e', 'startTime', ((t_today + 1) + time '11:00') at time zone 'Asia/Singapore',
        'responses', jsonb_build_object('email', jsonb_build_object('value', upper('480-check-e-' || t_sfx || '@example.invalid'))))));
    if (select b.booking_state from public.calcom_customer_bookings(array[t_e]) b) is distinct from 'upcoming' then
      raise exception '480: the self-test''s booking found by the email alone does not show'; end if;
    perform public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CANCELLED', 'createdAt', now() - interval '1 day',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'e')));
    -- Booked with the phone of a record then merged into a Tier 1 member: the
    -- booking follows the merge (F). The merge as merge_customer_records
    -- writes it: the record deleted and write_audit's customers_merged row on
    -- the kept record, in one transaction.
    perform public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CREATED', 'createdAt', now() - interval '1 day',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'f', 'startTime', ((t_today + 5) + time '09:00') at time zone 'Asia/Singapore',
        'responses', jsonb_build_object('WhatsApp-Number', t_ph[8]))));
    update public.customers set deleted_at = now() where id = t_g;
    perform public.write_audit('customers', t_f, 'customers_merged', null, jsonb_build_object('merged_from', t_g, 'reason', '480 check'));

    select jsonb_object_agg(b.customer_id, b.booking_state) into t_ans
      from public.calcom_customer_bookings(array[t_a, t_b, t_c, t_d, t_e, t_f]) b;
    if t_ans is distinct from jsonb_build_object(t_a, 'upcoming', t_b, 'came', t_c, 'miss', t_d, 'none', t_e, 'none', t_f, 'upcoming') then
      raise exception '480: the self-test''s states are not as tested: %', t_ans; end if;

    t_ans := public.customer_downline_visits(t_ref);
    select jsonb_object_agg(r ->> 'name', jsonb_build_array(r ->> 'booking_state', r -> 'booking_at')) into t_rows
      from (select jsonb_array_elements(t_ans -> 'tier1') r union all select jsonb_array_elements(t_ans -> 'tier2')) x;
    if t_rows is distinct from jsonb_build_object(
         '480 Check Upcoming', jsonb_build_array('upcoming', to_jsonb(((t_today + 4) + time '10:00') at time zone 'Asia/Singapore')),
         '480 Check Came', jsonb_build_array('came', to_jsonb(((t_today - 2) + time '11:00') at time zone 'Asia/Singapore')),
         '480 Check Missed', jsonb_build_array('miss', to_jsonb(((t_today - 2) + time '11:00') at time zone 'Asia/Singapore')),
         '480 Check None', jsonb_build_array('none', null),
         '480 Check Kept', jsonb_build_array('upcoming', to_jsonb(((t_today + 5) + time '09:00') at time zone 'Asia/Singapore')),
         '480 Check Cancelled', jsonb_build_array('none', null))
       or (select count(*) from jsonb_array_elements(t_ans -> 'tier1') r
            where r ?& array['customer_id', 'name', 'phone', 'joined_on', 'joined_from_created', 'visited', 'first_visit_on',
                             'booking_at', 'booking_state']
              and (select count(*) from jsonb_object_keys(r)) = 9) <> 5
       or (select count(*) from jsonb_array_elements(t_ans -> 'tier2') r
            where r ?& array['parent_id', 'parent_name', 'booking_at', 'booking_state']
              and (select count(*) from jsonb_object_keys(r)) = 11) <> 1 then
      raise exception '480: the self-test''s Downline is not as tested: %', t_rows; end if;

    -- The calendar catch-up, a dry run, in a window of 2098 that holds no
    -- real booking: a new booking (a "Cxl" title: still a booking), an event
    -- without a cal.com link (skipped), an active booking the calendar does
    -- not carry (missing), named for cancelling with a uid that is not
    -- missing: counted and listed (uids and times, the missing one first),
    -- nothing written.
    perform public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CREATED', 'createdAt', now() - interval '1 hour',
      'payload', jsonb_build_object('uid', '480chk' || t_sfx || 'h', 'startTime', '2098-06-02T02:00:00Z')));
    select count(*) into t_n from public.calcom_bookings;
    t_ans := public.calcom_booking_backfill(jsonb_build_array(
      jsonb_build_object('id', 'chk480' || t_sfx, 'status', 'confirmed', 'updated', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'summary', 'Cxl 480 Check None ' || t_ph[5] || ' Check Centre Free',
        'description', 'Manage: https://app.cal.com/booking/480chk' || t_sfx || 'g?changes=true',
        'start', jsonb_build_object('dateTime', '2098-06-01T10:00:00', 'timeZone', 'Asia/Singapore'),
        'end', jsonb_build_object('dateTime', '2098-06-01T11:00:00', 'timeZone', 'Asia/Singapore')),
      jsonb_build_object('id', 'chk480' || t_sfx || 'h', 'summary', 'Typed by hand ' || t_ph[5],
        'updated', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'start', jsonb_build_object('dateTime', '2098-06-01T12:00:00+08:00'),
        'end', jsonb_build_object('dateTime', '2098-06-01T13:00:00+08:00'))),
      '2098-01-01 00:00:00+08', '2099-01-01 00:00:00+08', now(), true,
      array['480chk' || t_sfx || 'h', '480chk' || t_sfx || 'z']);
    if t_ans is distinct from jsonb_build_object('dry_run', true, 'events', 2, 'created', 1, 'moved', 0, 'unchanged', 0, 'stale', 0,
         'cancelled', 0, 'terminal', 0, 'repeated_uid', 0, 'skipped_all_day', 0, 'skipped_bad_shape', 0,
         'skipped_deleted_no_data', 0, 'skipped_no_link', 1, 'skipped_no_phone', 0, 'no_updated_time', 0,
         'missing_from_calendar', 1, 'cancelled_missing', 1, 'cancel_uids_not_missing', 1,
         'changes', jsonb_build_array(
           jsonb_build_object('uid', '480chk' || t_sfx || 'h', 'change', 'cancelled_missing',
                              'old_start', '2098-06-02T10:00:00+08:00', 'new_start', null),
           jsonb_build_object('uid', '480chk' || t_sfx || 'g', 'change', 'created', 'old_start', null,
                              'new_start', '2098-06-01T10:00:00+08:00')),
         'truncated', false)
       or (select count(*) from public.calcom_bookings) <> t_n then
      raise exception '480: the self-test''s calendar catch-up dry run is not as tested: %', t_ans; end if;

    raise exception using errcode = 'P0480', message = '480: self-test done, undone';
  exception when sqlstate 'P0480' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
