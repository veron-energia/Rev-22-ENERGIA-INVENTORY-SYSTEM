-- 482_downline_and_network_show_visited_without_booking.sql
--
-- THE DOWNLINE AND THE AFFILIATE PORTAL'S MY NETWORK SHOW A GREY "CAME IN"
-- FOR SOMEONE WHO HAS COME IN WITHOUT A CAL.COM BOOKING, NOT A RED "NO
-- BOOKING" (the Owner, 30 Oct 2026; the word and its grey, 31 Oct 2026)
--
-- THE RULE (the Owner, 30 Oct 2026)
--
--   What staff saw: rows where the customer clearly came in (Visited: Yes)
--   but the Booking column said a red "No booking". Their appointments were
--   typed into Google Calendar by staff, not booked on cal.com, so no cal.com
--   booking exists for them (480 reads cal.com bookings only).
--   The Owner's choice: someone who has ALREADY COME IN but has NO cal.com
--   booking shows a grey "Came in" (no date) in the Booking column, on both
--   screens (the staff Downline, Tier 1 and Tier 2; the affiliate portal's
--   My Network, Tier 1 and Tier 2). The red "No booking" stays only for
--   people who have never come in and have no booking. A booking's states
--   do not change: upcoming, came and miss are as 480 left them (a customer
--   with a booking keeps it, even a Miss when they came on another day).
--   The Visited and First visit columns, and the visit rule itself
--   (customer_centre_visit_days, customer_centre_visits), stay exactly as
--   they are. Counting staff-typed calendar appointments as bookings was
--   considered and not chosen.
--   "Has come in": the same evidence 480's 'came' uses, on ANY Singapore day
--   up to and including today:
--   (a) a visit day by THE visit rule, customer_centre_visit_days()
--       (398/404, unchanged); or
--   (b) an invoice of theirs at the Adelphi centre: the store in use
--       (deleted_at null) coded RETAIL-ADELPHI, looked up by its code, never
--       a stored id (the Van & RoadShow, ADELPHI-VAN, does not count); not
--       deleted; settled (paid, partially_paid, completed_foc,
--       refund_requested, refunded; not draft, unpaid,
--       cancellation_requested or cancelled); its Singapore business day
--       (invoices.business_date, else the Singapore date it was made) on or
--       before today; and not an online or event order (no web order, VIP
--       order person or event guest names it).
--   Purchases only at the van, a roadshow or online do not count: those
--   customers keep "No booking".
--
-- WHAT THIS DOES
--
--   Replaces ONE function, public.calcom_customer_bookings(uuid[], date), THE
--   rule both screens read (480). Where it answered 'none' (no active booking
--   picked for the customer), it now answers 'visited' when the customer has
--   come in as above, else 'none'. Everything else it answers is 480's: which
--   customers it answers for, which booking it picks and whose booking it is
--   (the CTEs t, mt, mk, d, b and pick are 480's word for word;
--   calcom_booking_owner follows merges), 'upcoming', 'came' and 'miss', its
--   signature and return columns, LANGUAGE sql STABLE SECURITY DEFINER, its
--   search path and its grants (the owner and the service role; no client
--   role). The evidence is read once for both uses, with 480's filters: the
--   customers whose evidence matters (ev) are the owners of a past booking
--   (came or miss: that day, as before) and, now, everyone asked about with
--   no booking (visited or none: any day up to today); one with an upcoming
--   booking needs none and is not looked up. Their visit days (v: one call
--   of customer_centre_visit_days(), as before) and their settled Adelphi
--   purchase days (paid: by idx_invoices_customer) are kept up to today, so
--   'came' still matches the booking's own day and 'visited' any of them.
--   customer_downline_visits(uuid) and affiliate_portal_network() are NOT
--   changed (their md5s stay 480's): each already passes the state through
--   (coalesce(state, 'none')), so both screens answer 'visited' for such rows
--   with every other key, value and the row order as before. Their in-body
--   comments still list four states (upcoming, came, miss or none): a fifth,
--   'visited', now reaches them through calcom_customer_bookings (written
--   here and in the DESIGN notes, not in their bodies, so they stay byte for
--   byte as they are).
--   The value 'visited' is shown as "Came in" (the Owner, 31 Oct 2026, so it
--   is never read as the Visited column): the database's value stays
--   'visited'; only the pages word it. With it, not in this file (the
--   pages): booking.mjs/.d.mts word 'visited' as "Came in" (no date; the
--   export's Booking Status "Came in", Booking empty); BookingCell shows
--   that word in var(--text-secondary), the grey of a past booking's date in
--   the same cell, not bold, no badge, never red; one short sentence in each
--   screen's note.
--
-- WHAT THE PERSON SEES (user-facing)
--
--   Staff, Owners, Managers (Downline) and affiliates (My Network): in the
--   Booking column, a grey "Came in" for someone with no cal.com booking who
--   has come to the centre (not bold in the tables; on My Network's phone
--   cards bold, like every value there); the red "No booking" only for
--   someone who has never come in. Bookings show as before (the date and
--   time; grey when they came; a red Miss badge when they missed). The
--   Downline's note adds: "Came in under Booking means they have no cal.com
--   booking but have come to the centre (a visit, or a purchase at the
--   centre)."; My Network's: "Came in means they have come to the centre
--   without a booking." Both sentences go live with the pages (DEPLOY
--   ORDER). The Downline's Excel export: Booking empty, Booking Status
--   "Came in".
--   Production (482's rule run inline, read only; counts only), customers in
--   use with a referrer: 30 Oct 2026, 153: 110 'none'; 44 of them become
--   'visited' (36 by a visit day, 8 by a settled Adelphi purchase only); 66
--   stay 'none' (6 with settled purchases elsewhere only: the van, a
--   roadshow or online; 60 with nothing); the other 43 keep their state (14
--   upcoming, 21 came, 8 miss). 31 Oct 2026, 157: 112 'none'; 47 become
--   'visited' (38 by a visit day, 9 by an Adelphi purchase only); 65 stay
--   'none' (6 elsewhere only, 59 with nothing); 45 keep their state (14
--   upcoming, 22 came, 9 miss); no 'visited' without the evidence and no
--   'none' with it.
--   A customer who only bought at the centre (no visit by the visit rule)
--   reads Visited "No" beside Booking "Came in" on the Downline (9 on 31
--   Oct): the two words differ, and the note says Came in includes a
--   purchase at the centre. The Visited and First visit columns and the
--   tier headings' "N visited" stay as they are: they count the visit rule
--   only (the Owner, 31 Oct 2026).
--
-- NOT CHANGED
--
--   * The visit rule (customer_centre_visit_days) and Visited / First visit
--     (customer_centre_visits); customer_downline_visits and
--     affiliate_portal_network (byte for byte: pinned below); the bookings
--     table, the webhook, the calendar fill and catch-up, whose booking it is
--     (calcom_booking_owner) and the merge trail.
--   * Who may call anything: the two screens as before; the state rule the
--     service role's alone (and the two screens', which call it as its
--     owner).
--
-- NOT COVERED (told to the Owner)
--
--   * A visit dated after today (a survey whose typed signed date is in the
--     future) makes Visited "Yes" with that First visit date (the Visited
--     column has no date limit) but counts for the Booking's "Came in" only
--     from that day. Production, 30 and 31 Oct 2026: no visit and no invoice
--     is dated after today.
--   * A staff-typed appointment in Google Calendar is still not a booking:
--     before such a customer comes in, they read "No booking" (the Owner's
--     choice: counting those appointments needs a daily sync and rules for
--     deliveries and deleted events).
--   * A merge moves the merged record's surveys and invoices to the kept
--     record (merge_customer_records), so they count for the kept record, as
--     for 'came'. A record deleted with Delete keeps its own: they count for
--     no one in use.
--   * A purchase counts at the Adelphi centre only, while a store in use is
--     coded RETAIL-ADELPHI (this file refuses to run otherwise; if the code
--     were changed later, or that store deleted, purchases would simply stop
--     counting, as for 'came': the test suite's V4b).
--   * The Downline's Excel export carries no note (the export has no caption
--     option): there a purchase-only customer's row reads Visited "No"
--     beside Booking Status "Came in" with nothing to explain it.
--   * A customer with only cancelled or rescheduled-away bookings has no
--     booking to show (480): 'visited' when they have come in, else 'none'.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * 480 is recorded as applied (supabase_migrations.schema_migrations
--     holds 20261030052953);
--   * calcom_customer_bookings(uuid[], date) is 480's (BEFORE: replaced by
--     the tested text) or already this file's (AFTER: "already this version;
--     left alone", nothing changed); anything else is refused; no other
--     function takes its name; its grants (compared as sets, never as text)
--     are the owner's and the service role's, none for anon or
--     authenticated;
--   * the functions it relies on are as read on 30 Oct 2026 (the visit rule
--     as 480 pins it, the owner rule, the phone and email readers, sg_today,
--     and the two screens' functions at 480's AFTER, which pass the state
--     through; the guard also accepts affiliate_portal_network at the AFTER
--     of 484's first draft of 31 Oct 2026, 1fa56957..., which passes the
--     state the same way: that draft was never applied and is on hold, to
--     be rebuilt and applied after this file, so production meets 480's);
--     the columns it reads are there, of the types read; the invoice
--     statuses are the nine read; exactly one store in use is coded
--     RETAIL-ADELPHI.
--   No table, index, column, grant or other function is changed; CREATE OR
--   REPLACE keeps the function's grants (re-checked afterwards, as sets).
--   Afterwards: the function has its AFTER md5, its grants are as before,
--   the two screens' functions are still as they were (480's).
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0482, so it leaves no row and takes no number from any sequence):
--   made-up customers ("482 Check ...", fictional phones +61 2 5550 ....
--   that no customer, in use or deleted, and no active booking holds: range
--   scans of the partial phone indexes) under a made-up referrer: in Tier 1
--   one with a visit three days ago and no booking (visited), one with
--   nothing (none), one with an upcoming booking and an earlier visit
--   (upcoming), one with a booking two days ago and a visit on another day
--   (miss); in Tier 2 one with a visit today (visited) and one whose only
--   visit is dated two days ahead (none; visited from that day). The state
--   rule and the Downline (both tiers, as the server) are checked. The
--   self-test makes no invoice (an invoice's triggers reach stock, therapy,
--   vouchers and commissions): the purchase evidence is checked by the test
--   suite. A second run changes nothing ("already this version; left
--   alone"; its self-test runs again and is undone again). Locks: the
--   function's catalogue row while it is replaced (a caller already running
--   keeps 480's version to its end); the self-test's rows only. Measured on
--   a copy holding 13,232 made-up customers, 500,250 audit rows, 4,000
--   invoices and 3,500 bookings: 0.13 s, then 0.06 s for the second run.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead; one go-ahead may cover
-- steps 2 and 3 together if the Owner agrees)
--
--   1. Dry run on a copy of production as it is then (the rc480_live
--      template is schema only: add production's two stores by their codes,
--      RETAIL-ADELPHI and ADELPHI-VAN, and 480's row in
--      supabase_migrations.schema_migrations, which a copy built with psql
--      does not hold; then what landed after 480: since 31 Oct 2026 483,
--      applied from its file with its history row (20261031082541); its
--      public fingerprint must equal production's): apply this file twice;
--      the first run ends at the fingerprint below, the second says "already
--      this version; left alone" and changes nothing.
--   2. The pages FIRST (push #1): commit and push exactly
--        src/lib/referral/booking.mjs, src/lib/referral/booking.d.mts
--        src/components/referrals/BookingCell.tsx
--        src/components/referrals/DownlineModal.tsx
--        src/pages/AffiliateNetworkPage.tsx
--        src/styles/globals.css (a comment)
--        scripts/referrals/tests/downline-booking-480.test.mjs
--        scripts/referrals/tests/downline-booking-482.test.mjs
--        scripts/referrals/tests/affiliate-network-phone-484.test.mjs
--        scripts/referrals/preview/supabase-stub.ts, vite.visits-preview.config.mts
--      (not this file, not 484's, no SQL suite; a push to main is a Vercel
--      deploy). On the database before 482 they show what they show today
--      (no 'visited' value is sent yet), except one new sentence in each
--      note, what "Came in" means: the note sentences go live with the
--      pages, while no row shows "Came in" until 482 is applied.
--      AffiliateNetworkPage also carries 484's Tier 1 Phone column, card
--      line and note sentence (the Owner, 31 Oct 2026), shown only once the
--      database sends a Tier 1 number. None does before 484 (480's
--      affiliate_portal_network, which this file leaves as it is, sends no
--      'phone'), so after this push, and after this file, My Network shows
--      no Phone column, no Phone line and no sentence about phone numbers.
--   3. In the same sitting, as soon as Vercel reports the pages deploy
--      Ready, apply 482 wrapped: begin; this file; insert into
--      supabase_migrations.schema_migrations (version, name, statements)
--      values (<version>, '482_downline_and_network_show_visited_without_booking',
--      array[<this file>]); commit (or the MCP's apply_migration with this
--      text verbatim: either way its history row holds this file's text as
--      its one statement, as 480's does, which UNDO's guard reads). Build
--      the wrapper with the file embedded as a literal (Python), never with
--      cat or a psql backtick variable: they drop the final newline. Then
--      read the row back:
--        select md5(array_to_string(statements, '')), cardinality(statements)
--          from supabase_migrations.schema_migrations
--         where name = '482_downline_and_network_show_visited_without_booking';
--      It must give this file's md5 (md5 -q of it; the DESIGN notes and the
--      apply report record it) and 1. If the md5 differs, record the value
--      read as UNDO's <M> (or set the row's statements to the exact text,
--      guarded on the md5 read, as was done for 416); if no row comes back
--      (the file was run with plain psql), insert it. Checks afterwards:
--      calcom_customer_bookings 14987e9e...; customer_downline_visits
--      ea3f28ea... and affiliate_portal_network d1c387fb... unchanged; the
--      grant list bbebe230... (unchanged) and the fingerprint (AFTER,
--      below). From then on, the rows of those who came in without a booking
--      (47 on 31 Oct) read a grey "Came in" instead of a red "No booking".
--   4. Commit and push this file, scripts/referrals/tests/downline-booking-482.sql
--      and the 480 suite's edit (scripts/referrals/tests/downline-booking-480.sql:
--      it accepts 482's AFTER and 480's earlier refusal on a 482 database).
--   484 (My Network shows Tier 1 customers' phones) is ON HOLD and was never
--   applied: it will be rebuilt to the Owner's answers of 31 Oct 2026 (a
--   number only where the affiliate login's link to its customer record is
--   proven, none while the affiliate is suspended, and only for referrals
--   who signed up after the /r/ page told them their referrer would see it)
--   and go out later with its own push (#2: the /r/ notice, the rebuilt 484
--   and its tests). It replaces another function, affiliate_portal_network,
--   and comes after this file.
--   If 482 were applied BEFORE the pages: the live pages (2b31b0d's; 838b700,
--   483's commit, left them as they were) do not know 'visited' and show
--   those rows as "—" (grey, as for a database before 480) with blank
--   Booking and Booking Status in the export, until the pages are pushed:
--   never a false "No booking" or a wrong date, but not "Came in" either.
--   Hence the pages first.
--
-- BEFORE (production, 30 Oct 2026: head 20261030052953, 480; read again
-- 31 Oct 2026 after 483 landed: every md5 below the same; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   calcom_customer_bookings(uuid[],date)                             2e651a5d2367ba26bfd9e8e00d95823e  (480's AFTER)
--   relied on, not changed
--   customer_centre_visit_days()                                      2129857d6ff9f29dcf2cbccc9f13e5bc  (404's, as 480 pins it)
--   calcom_booking_owner(text,text)                                   959a5a8280ac20155068b3fa9aae73f3  (480's)
--   normalize_customer_phone(text)                                    b2bfac910e0c9eff402ba44e19750bee
--   customer_email_match_key(text)                                    be468815c9626fff1728e2cfcd484b66
--   sg_today()                                                        1c1289f18e24d8370e9a6364c9c06fca
--   customer_downline_visits(uuid)                                    ea3f28ea932506eda6937fa687298d6d  (480's AFTER)
--   affiliate_portal_network()                                        d1c387fb852392da041b5d8207655879  (480's AFTER)
--     also accepted: 484's first draft, never applied (on hold)       1fa5695730a5f17a6249811a09d064e2
--   public function fingerprint, production now (480, then 483: 31 Oct
--   2026, head 20261031082541)                                        93185a28ecc013afa5214340fdb2fa04 (1396 functions)
--     (480 alone, before 483 landed)                                  6a7a72ebbb3a21e3a0df0ddd84efbcce (1396)
--   grant list (oid::regprocedure||'='||proacl, '|', by signature)    bbebe2306b314118ddd6473d16d2fc11
-- AFTER (for later guards)
--   calcom_customer_bookings(uuid[],date)                             14987e9e9f033290010042a5632bc81c
--   its grants, as a set                                              {postgres=X/postgres,service_role=X/postgres}
--   public function fingerprint, worked out on copies of production (30 Oct
--   2026, and again 31 Oct and 1 Nov 2026):
--     production now (480 and 483) -> 482                             240ab0c40d3c3447a11b7b2712e13c88 (1396)
--     without 483: 480 -> 482                                         35655169991c9dcb0b332c0ddf9b5f30 (1396)
--     (the rebuilt 484, which comes after this file, records its own)
--   grant list                                                        bbebe2306b314118ddd6473d16d2fc11 (unchanged)
--   483 (another session's: capture_invoice_stock_components only)
--   landed on 31 Oct 2026 (20261031082541) and touches none of this
--   file's pins. HANDOFF's 479 and 481 (therapy and stock functions, and a
--   new helper invoice_refunded_stock(uuid)) may land first too: they change
--   the global fingerprint (and 481 the function count and grant list), but
--   none of this file's pins; recompute the "production now" line then.
--
-- UNDO (with the Owner's go-ahead), in one transaction: begin;
--   0. stop unless the function is this file's (md5 of pg_get_functiondef,
--      search_path public, = 14987e9e9f033290010042a5632bc81c), so a later
--      version is never overwritten;
--   1. re-apply 480's body of the function: the text between $n3$ and $n3$
--      in supabase/480_downline_and_network_show_calcom_booking.sql (its
--      c_new_defs[3]; that text's own md5 is
--      2e651a5d2367ba26bfd9e8e00d95823e), run as one statement; CREATE OR
--      REPLACE keeps the grants;
--   2. delete 482's history row, guarded on its statements md5:
--        delete from supabase_migrations.schema_migrations
--         where name = '482_downline_and_network_show_visited_without_booking'
--           and md5(array_to_string(statements, '')) = '<M>';
--      exactly one row, else roll back. <M> is the md5 of this file as
--      applied (md5 -q of it: a file cannot hold its own md5, so the DESIGN
--      notes and the apply report record it), or the value step 3's
--      read-back gave;
--   commit. The function's md5 then reads 2e651a5d... again and the history
--   no longer says 482 is in (a later re-apply is recorded anew).
--   The pages: the Booking cells need nothing (they show "Came in" only when
--   the database says 'visited'), but the two note sentences ("Came in under
--   Booking means ..." on the Downline, "Came in means ..." on My Network)
--   would explain a word no row shows: revert those two sentences (a pages
--   commit), or accept a stale sentence until the pages next change.
--
-- Test: scripts/referrals/tests/downline-booking-482.sql (begin ...
-- rollback; it installs this file twice where 480 is in and 482 is not, or
-- with -v skip_install=1 where it is in). The 480 suite runs with
-- -v skip_install=1 on a 482 database (it accepts 482's AFTER, and 480's
-- own refusal there). Pages: scripts/referrals/tests/downline-booking-482.test.mjs
-- and downline-booking-480.test.mjs; affiliate-network-phone-484.test.mjs
-- checks that My Network shows nothing of a phone while the database sends
-- no Tier 1 number.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The one function this changes: 480's (BEFORE) -> this file's (AFTER) ──
  c_sig constant text := 'calcom_customer_bookings(uuid[],date)';
  c_before constant text := '2e651a5d2367ba26bfd9e8e00d95823e';
  c_after constant text := '14987e9e9f033290010042a5632bc81c';
  c_def constant text :=
$d1$CREATE OR REPLACE FUNCTION public.calcom_customer_bookings(p_customer_ids uuid[], p_today date DEFAULT NULL::date)
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
  -- order, VIP order or event guest names it); else 'miss'.
  -- 482 (the Owner, 30 Oct 2026): no booking: 'visited' when they have come
  -- in by the same evidence on any Singapore day up to today (a visit day,
  -- or such an invoice dated then), else 'none'. A customer with a booking
  -- keeps its state, whatever they did on other days.
  -- Whose booking it is: calcom_booking_owner, which also follows a merge,
  -- so the bookings under the phone or inbox of a record a merge retired
  -- into one of them (along a chain) are read too. p_today: today in
  -- Singapore unless given (the tests).
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
  -- Whose evidence is read (482: once, for both): the owner of a past
  -- booking (came or miss: that day) and each one with no booking (visited
  -- or none: any day up to today); never one with an upcoming booking.
  ev as materialized (
    select pick.owner as id from pick cross join d where pick.day < d.today
    union
    select t.id from t where not exists (select 1 from pick where pick.owner = t.id)
  ),
  v as materialized (
    select x.customer_id, x.visit_on
      from public.customer_centre_visit_days() x
     cross join d
     where x.customer_id in (select ev.id from ev)
       and x.visit_on <= d.today
  ),
  paid as materialized (
    select distinct i.customer_id, coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date) as day
      from ev
     cross join d
      join public.invoices i on i.customer_id = ev.id
     where i.deleted_at is null
       and i.status in ('paid', 'partially_paid', 'completed_foc', 'refund_requested', 'refunded')
       and i.store_id = (select s.id from public.stores s where s.code = 'RETAIL-ADELPHI' and s.deleted_at is null)
       and coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date) <= d.today
       and not exists (select 1 from public.web_orders o where o.invoice_id = i.id)
       and not exists (select 1 from public.event_vip_order_people o where o.invoice_id = i.id)
       and not exists (select 1 from public.event_guests o where o.invoice_id = i.id)
  )
  select t.id, pick.start_at,
         case when pick.owner is null then
                case when t.id in (select v.customer_id from v) or t.id in (select paid.customer_id from paid) then 'visited'
                     else 'none'
                end
              when pick.day >= d.today then 'upcoming'
              when exists (select 1 from v where v.customer_id = t.id and v.visit_on = pick.day)
                or exists (select 1 from paid where paid.customer_id = t.id and paid.day = pick.day) then 'came'
              else 'miss'
         end
    from t
   cross join d
    left join pick on pick.owner = t.id
$function$
$d1$;
  -- Its grants, kept (compared as sets): the owner and the service role; no client role.
  c_acl constant text[] := array['postgres=X/postgres', 'service_role=X/postgres'];

  -- ── Relied on, not changed (production, 30 Oct 2026) ───────────────────
  -- The visit rule (as 480 pins it), the owner rule and the readers the state
  -- rule calls, and the two screens' functions, which pass its state through.
  -- The portal's: 480's, or 484's (it adds the Tier 1 phone and passes the
  -- state the same way, so either file may go first); a comma between md5s
  -- accepts either.
  c_relied constant text[] := array['customer_centre_visit_days()', 'calcom_booking_owner(text,text)',
    'normalize_customer_phone(text)', 'customer_email_match_key(text)', 'sg_today()',
    'customer_downline_visits(uuid)', 'affiliate_portal_network()'];
  c_relied_md5 constant text[] := array['2129857d6ff9f29dcf2cbccc9f13e5bc', '959a5a8280ac20155068b3fa9aae73f3',
    'b2bfac910e0c9eff402ba44e19750bee', 'be468815c9626fff1728e2cfcd484b66', '1c1289f18e24d8370e9a6364c9c06fca',
    'ea3f28ea932506eda6937fa687298d6d', 'd1c387fb852392da041b5d8207655879,1fa5695730a5f17a6249811a09d064e2'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; v_md5 text; v_oid regprocedure;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_ph text[]; t_ref uuid; t_a uuid; t_b uuid; t_c uuid; t_d uuid; t_e uuid; t_f uuid;
  t_today date; t_ans jsonb; t_rows jsonb;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  if md5(c_def) <> c_after then
    raise exception '482: the text of public.% is not the tested one (md5 %)', c_sig, md5(c_def); end if;

  -- Two IFs: PL/pgSQL prepares a whole condition before it runs it, so one
  -- that names a missing table fails there, before any of it is evaluated.
  if to_regclass('supabase_migrations.schema_migrations') is null then
    raise exception '482: 480 (20261030052953) is not recorded in supabase_migrations.schema_migrations. Apply 480 first (a copy built with psql: add its row as production has it).';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261030052953') then
    raise exception '482: 480 (20261030052953) is not recorded in supabase_migrations.schema_migrations. Apply 480 first (a copy built with psql: add its row as production has it).';
  end if;

  v_oid := to_regprocedure('public.' || c_sig);
  if v_oid is null then raise exception '482: public.% is missing (480 makes it)', c_sig; end if;
  v_md5 := md5(pg_get_functiondef(v_oid));
  if v_md5 not in (c_before, c_after) then
    raise exception '482: public.% is neither 480''s version (production, 30 Oct 2026) nor this file''s (md5 %). Re-read it and re-test before applying.',
      c_sig, v_md5; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'calcom_customer_bookings' and p.oid <> v_oid;
  if v is not null then raise exception '482: another function takes the name of public.%: %', c_sig, v; end if;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid) is distinct from c_acl
     or has_function_privilege('anon', v_oid, 'execute') or has_function_privilege('authenticated', v_oid, 'execute') then
    raise exception '482: the grants of public.% are not as read on 30 Oct 2026 (the owner and the service role only)', c_sig; end if;

  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or not (md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) = any (string_to_array(c_relied_md5[i], ','))) then
      raise exception '482: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The columns read.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customers', 'id', 'uuid'), ('customers', 'phone', 'text'), ('customers', 'email', 'text'),
                 ('customers', 'deleted_at', 'timestamp with time zone'),
                 ('calcom_bookings', 'uid', 'text'), ('calcom_bookings', 'start_at', 'timestamp with time zone'),
                 ('calcom_bookings', 'status', 'text'), ('calcom_bookings', 'phone_key', 'text'), ('calcom_bookings', 'email_key', 'text'),
                 ('audit_logs', 'record_id', 'uuid'), ('audit_logs', 'table_name', 'text'), ('audit_logs', 'action', 'text'),
                 ('audit_logs', 'new_data', 'jsonb'), ('audit_logs', 'created_at', 'timestamp with time zone'),
                 ('stores', 'id', 'uuid'), ('stores', 'code', 'text'), ('stores', 'deleted_at', 'timestamp with time zone'),
                 ('invoices', 'id', 'uuid'), ('invoices', 'customer_id', 'uuid'), ('invoices', 'store_id', 'uuid'),
                 ('invoices', 'status', 'invoice_status'), ('invoices', 'deleted_at', 'timestamp with time zone'),
                 ('invoices', 'business_date', 'date'), ('invoices', 'created_at', 'timestamp with time zone'),
                 ('web_orders', 'invoice_id', 'uuid'), ('event_vip_order_people', 'invoice_id', 'uuid'),
                 ('event_guests', 'invoice_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '482: these columns are missing or not as read on 30 Oct 2026: %', v; end if;
  -- The invoice statuses as read (the rule sorts each of them), and the Adelphi centre (by its code, never an id).
  if (select array_agg(e.enumlabel::text order by e.enumsortorder) from pg_enum e where e.enumtypid = to_regtype('public.invoice_status'))
     is distinct from array['draft', 'unpaid', 'partially_paid', 'paid', 'cancellation_requested', 'cancelled', 'refund_requested',
                            'refunded', 'completed_foc'] then
    raise exception '482: the invoice statuses are not the nine read on 30 Oct 2026. Re-read them and re-test before applying.'; end if;
  if (select count(*) from public.stores s where s.code = 'RETAIL-ADELPHI' and s.deleted_at is null) <> 1 then
    raise exception '482: exactly one store in use must be coded RETAIL-ADELPHI (the Adelphi centre); found %',
      (select count(*) from public.stores s where s.code = 'RETAIL-ADELPHI' and s.deleted_at is null); end if;

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_md5 = c_before then
    execute c_def;
    raise notice '482: public.% replaced (480''s -> 482''s: ''visited'' for someone with no booking who has come in)', c_sig;
  else
    raise notice '482: public.% is already this version; left alone', c_sig;
  end if;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  v_oid := to_regprocedure('public.' || c_sig);
  if v_oid is null or md5(pg_get_functiondef(v_oid)) <> c_after then
    raise exception '482: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid) is distinct from c_acl
     or has_function_privilege('anon', v_oid, 'execute') or has_function_privilege('authenticated', v_oid, 'execute') then
    raise exception '482: the grants of public.% changed', c_sig; end if;
  for i in 1 .. cardinality(c_relied) loop
    if not (md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) = any (string_to_array(c_relied_md5[i], ','))) then
      raise exception '482: public.% changed', c_relied[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  begin
    -- As the server (no request): require_active_staff lets it through.
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_today := public.sg_today();
    -- Seven fictional phones in a row (+61 2 5550 nnnn) that no customer, in
    -- use or deleted, and no active booking holds: range scans of
    -- idx_customers_phone_norm, idx_customers_deleted_phone_norm and
    -- calcom_bookings_phone_key_idx (all partial, hence the conditions),
    -- never a pass reading every customer's phone.
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
    if t_base is null then raise exception '482: the self-test found no free fictional phones'; end if;
    t_ph := array(select '+6125550' || lpad((t_base + n)::text, 4, '0') from generate_series(0, 6) n);
    insert into public.customers (full_name, phone) values ('482 Check Referrer', t_ph[1]) returning id into t_ref;
    insert into public.customers (full_name, phone, referred_by) values ('482 Check Visited', t_ph[2], t_ref) returning id into t_a;
    insert into public.customers (full_name, phone, referred_by) values ('482 Check None', t_ph[3], t_ref) returning id into t_b;
    insert into public.customers (full_name, phone, referred_by) values ('482 Check Upcoming', t_ph[4], t_ref) returning id into t_c;
    insert into public.customers (full_name, phone, referred_by) values ('482 Check Missed', t_ph[5], t_ref) returning id into t_d;
    insert into public.customers (full_name, phone, referred_by) values ('482 Check Today', t_ph[6], t_a) returning id into t_e;
    insert into public.customers (full_name, phone, referred_by) values ('482 Check Later', t_ph[7], t_a) returning id into t_f;
    -- Visits by the visit rule: a consultant's survey with an answer, dated
    -- the Singapore day it was made.
    insert into public.health_surveys (survey_no, customer_id, full_name, phone, source, submitted_at, remarks_condition)
    select 'HS-482CHK-' || t_sfx || '-' || x.k, x.id, x.nm, x.ph, 'consultant', x.at, '482 check'
      from (values ('a', t_a, '482 Check Visited', t_ph[2], ((t_today - 3) + time '11:00') at time zone 'Asia/Singapore'),
                   ('c', t_c, '482 Check Upcoming', t_ph[4], ((t_today - 3) + time '11:00') at time zone 'Asia/Singapore'),
                   ('d', t_d, '482 Check Missed', t_ph[5], ((t_today - 5) + time '11:00') at time zone 'Asia/Singapore'),
                   ('e', t_e, '482 Check Today', t_ph[6], now()),
                   ('f', t_f, '482 Check Later', t_ph[7], now() + interval '2 days')) x(k, id, nm, ph, at);
    -- Two bookings, as the webhook stores them: in three days, and two days ago.
    insert into public.calcom_bookings (uid, start_at, end_at, status, phone_key, source, last_event_at, last_trigger)
    values ('482chk' || t_sfx || 'c', ((t_today + 3) + time '14:00') at time zone 'Asia/Singapore',
            ((t_today + 3) + time '15:00') at time zone 'Asia/Singapore', 'active', public.normalize_customer_phone(t_ph[4]),
            'webhook', now() - interval '1 day', 'BOOKING_CREATED'),
           ('482chk' || t_sfx || 'd', ((t_today - 2) + time '11:00') at time zone 'Asia/Singapore',
            ((t_today - 2) + time '12:00') at time zone 'Asia/Singapore', 'active', public.normalize_customer_phone(t_ph[5]),
            'webhook', now() - interval '5 days', 'BOOKING_CREATED');

    select jsonb_object_agg(b.customer_id, jsonb_build_array(b.booking_state, b.booking_at)) into t_ans
      from public.calcom_customer_bookings(array[t_a, t_b, t_c, t_d, t_e, t_f]) b;
    if t_ans is distinct from jsonb_build_object(
         t_a, jsonb_build_array('visited', null), t_b, jsonb_build_array('none', null),
         t_c, jsonb_build_array('upcoming', ((t_today + 3) + time '14:00') at time zone 'Asia/Singapore'),
         t_d, jsonb_build_array('miss', ((t_today - 2) + time '11:00') at time zone 'Asia/Singapore'),
         t_e, jsonb_build_array('visited', null), t_f, jsonb_build_array('none', null))
       or (select b.booking_state from public.calcom_customer_bookings(array[t_f], t_today + 2) b) is distinct from 'visited' then
      raise exception '482: the self-test''s states are not as tested: %', t_ans; end if;

    t_ans := public.customer_downline_visits(t_ref);
    select jsonb_object_agg(r ->> 'name', jsonb_build_array(r ->> 'booking_state', r -> 'booking_at')) into t_rows
      from (select jsonb_array_elements(t_ans -> 'tier1') r union all select jsonb_array_elements(t_ans -> 'tier2')) x;
    if t_rows is distinct from jsonb_build_object(
         '482 Check Visited', jsonb_build_array('visited', null),
         '482 Check None', jsonb_build_array('none', null),
         '482 Check Upcoming', jsonb_build_array('upcoming', to_jsonb(((t_today + 3) + time '14:00') at time zone 'Asia/Singapore')),
         '482 Check Missed', jsonb_build_array('miss', to_jsonb(((t_today - 2) + time '11:00') at time zone 'Asia/Singapore')),
         '482 Check Today', jsonb_build_array('visited', null),
         '482 Check Later', jsonb_build_array('none', null))
       or (select count(*) from jsonb_array_elements(t_ans -> 'tier1') r
            where r ?& array['customer_id', 'name', 'phone', 'joined_on', 'joined_from_created', 'visited', 'first_visit_on',
                             'booking_at', 'booking_state']
              and (select count(*) from jsonb_object_keys(r)) = 9) <> 4
       or (select count(*) from jsonb_array_elements(t_ans -> 'tier2') r
            where r ?& array['parent_id', 'parent_name', 'booking_at', 'booking_state']
              and (select count(*) from jsonb_object_keys(r)) = 11) <> 2 then
      raise exception '482: the self-test''s Downline is not as tested: %', t_rows; end if;

    raise exception using errcode = 'P0482', message = '482: self-test done, undone';
  exception when sqlstate 'P0482' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
end $mig$;
