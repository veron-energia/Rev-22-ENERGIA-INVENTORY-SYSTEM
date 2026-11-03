-- 492_affiliate_network_shows_every_tier1_phone.sql
--
-- MY NETWORK SHOWS EVERY DIRECT REFERRAL'S (TIER 1) PHONE NUMBER, NOT ONLY
-- THOSE TOLD ON THE /r/ PAGE THAT THEIR REFERRER WOULD SEE IT, TO AN ACTIVE
-- AFFILIATE WHOSE LOGIN IS PROVEN; A NUMBER SOMEONE ASKED TO HIDE STAYS
-- HIDDEN; NEVER A TIER 2 NUMBER (the user, for the Owner, 3 Nov 2026)
--
-- THE RULE (the user's answers in chat, 3 Nov 2026)
--
--   "For affiliate, first tier should be able to see the phone number."
--   1. Which referrals: all Tier 1 referrals, also those never told on the
--      /r/ page that their referrer would see it (the seminar website's
--      sign-ups, event registrations, referrers set by staff, everyone
--      registered before 484's notice). The Owner accepts the PDPA point.
--      This replaces 484's answer 3 (numbers only for referrals told at
--      sign-up) and its Q3 (only the number typed under the notice).
--   2. Safeguards: both of 484's stay (its answers 1 and 2): numbers only
--      while the affiliate is active and the login's link to its record is
--      proven.
--
--   So, on the affiliate portal's My Network, a Tier 1 row (a customer in
--   use whose referred_by is the record the login is joined to) carries
--   'phone': its stored number, trimmed (as the staff Downline shows it),
--   when ALL of these hold; otherwise the key is there with no number (null:
--   a dash on the page):
--   a. the affiliate is active (affiliate_is_active), as in 484;
--   b. the login's link to its record is proven
--      (affiliate_login_link_proof(auth.uid(), the record) is not null), as
--      in 484;
--   c. the stored value is a number (a digit, and not a placeholder: AFF-
--      and 8 characters, or LEGACY-...), as in 484;
--   d. nobody asked to hide it: no withdrawn mark (referral_phone_notices)
--      on the record (484's e), and no withdrawn mark holding the number the
--      record holds now (normalize_customer_phone): a number hidden is hidden
--      on every record that holds it (a household number).
--   Gone: 484's c (an unwithdrawn mark naming this referrer) and d (the
--   record still holds the number typed under the notice). Tier 2 rows carry
--   no 'phone' key, as before. The staff Downline is unchanged. The /r/ page
--   goes on showing its notice and recording who was told: the marks stay as
--   the evidence that the notice was given, and no longer decide whether a
--   number shows.
--
-- WHAT THIS DOES
--
--   * Replaces public.affiliate_portal_network() (484's, md5 070d1b48..., the
--     only BEFORE accepted): made from 484's exact text by one hunk, the
--     Tier 1 'phone' key (its comment and its condition). Everything else is
--     484's: signature, plpgsql STABLE SECURITY DEFINER, search path,
--     v_phones (a and b), "Not an affiliate account", the rows, every other
--     key, value and the order, the bookings, and the grants (kept by CREATE
--     OR REPLACE).
--   * Nothing else: no table, column, grant or other function changes.
--     484's hide block (its header) still hides a referral who has a mark;
--     the blocks below replace it, as they also hide someone who has none.
--
-- WHAT THE PERSON SEES (user-facing)
--
--   Affiliates: at apply, an active affiliate whose login is proven sees the
--   number of each direct referral who has one: My Network's Phone column,
--   card line and sentence appear (482's and 484's pages show them once a
--   Tier 1 number arrives). The pages pushed with this file say so: My
--   Network's sentence becomes "Phone numbers show for your direct referrals
--   only. A dash means there is no number to show. Use them only to help
--   them with their visit.", and the Rules page's "Your referrals' details"
--   changes to match. Staff: nothing changes.
--   Production, 3 Nov 2026 (read only, counts only): 88 portal logins, all
--   claimed. Proven and active 77: claim_resolved 45 (22 with Tier 1
--   customers, 112 rows), own_record 17 (5, 7), verified_email 14 (9, 35),
--   same_person 1 (0); own_record but suspended 1 (no Tier 1); not proven 10
--   (5 with Tier 1 customers, 6 rows). Under proven, active logins every one
--   of the 154 Tier 1 rows holds a number and none is hidden: 154 numbers
--   shown to 36 affiliates where 1 shows now; the 6 rows of the logins not
--   proven stay a dash. Marks: 1, none withdrawn.
--
-- NOT CHANGED
--
--   * referral_phone_notices (its rows, its shape and its grants), the proof
--     (affiliate_login_link_proof), the /r/ sign-up with notice and
--     affiliate_referral_signup, customer_downline_visits (the staff
--     Downline), calcom_customer_bookings, current_affiliate_customer_id,
--     affiliate_is_active, every other portal function, the merge, every
--     table and grant.
--
-- NOT COVERED (told to the user)
--
--   * PDPA: most of these referrals were never told that their referrer
--     would see their number; the Owner accepts it (answer 1). The seminar
--     website's sign-up page (another repository) shows no notice; its
--     sign-ups' numbers show from now on.
--   * The opt-out stays the developer's, through the MCP, with the blocks
--     below; there is no staff button. A referral never told was never told
--     either that they may ask.
--   * By number: a withdrawn mark hides the number it holds on every record
--     holding it, also on a record that comes to hold that number later for
--     another reason (a number given up and taken by someone else): a dash,
--     the safe direction.
--   * Not proven (10 logins, 5 with Tier 1 customers, 6 rows): as with 484,
--     nobody is told why the Phone column does not appear; verifying the
--     email proves a login whose email is its record's.
--   * 484's NOT COVERED on the proof (a planted email, Supabase Auth's
--     Confirm email staying on, staff decisions, merges followed through the
--     Audit Log), on household numbers, on numbers shown as stored, and on no
--     record of who looked at a number, applies unchanged.
--   * Pins: 6 relied-on md5s and the table's description; another session's
--     change to one of them makes this refuse (intended: re-read and
--     re-test).
--
-- HOW TO HIDE ONE REFERRAL'S NUMBER (the opt-out; with the Owner's go-ahead
-- naming the customer who asked)
--
--   First, read only: where does their number show? The Tier 1 rows holding
--   it (on their record, or on another record with the same number):
--     select count(*) from public.customers c
--      where c.deleted_at is null and c.referred_by is not null
--        and (c.id = '<id>' or public.normalize_customer_phone(c.phone) = public.normalize_customer_phone('<their number>'));
--   Then run this through the MCP's execute_sql as one statement, with the
--   referral's customer id (from the Customers page), c_phone only when the
--   number they gave is not the one on their record (with its country code),
--   and how they asked filled in (as written, with the zero id, it changes
--   nothing). The number is hidden on every record holding it: their marks
--   and the marks holding it are withdrawn, and, when none of their own
--   holds it (they were never told, or their number changed since), one
--   withdrawn row is made for them ('hide-request': no notice was given).
--   An Audit Log row on each record it touched names who asked and the rows:
--     do $hide$
--     declare
--       c_customer constant uuid := '00000000-0000-0000-0000-000000000000';  -- the referral who asked
--       c_phone constant text := null;  -- or the number they gave, with its country code (else the one on their record)
--       c_asked constant text := 'by phone, 4 Nov 2026';                     -- how and when they asked
--       v_phone text; v_ref uuid; v_new uuid; n int;
--     begin
--       select public.normalize_customer_phone(coalesce(c_phone, c.phone)), coalesce(c.referred_by, c.id)
--         into v_phone, v_ref from public.customers c where c.id = c_customer;
--       if not found then
--         raise exception '492 hide: % is not a customer (fill in the referral who asked); nothing changed', c_customer;
--       end if;
--       if c_phone is not null and v_phone is null then
--         raise exception '492 hide: % is not a number that can be matched; nothing changed', c_phone;
--       end if;
--       if v_phone is null and not exists (select 1 from public.referral_phone_notices k where k.customer_id = c_customer) then
--         raise exception '492 hide: % holds no number that can be matched and has no mark (set c_phone to the number they gave); nothing changed', c_customer;
--       end if;
--       -- A withdrawn row of their own holding the number, made when none of theirs holds it.
--       if v_phone is not null
--          and not exists (select 1 from public.referral_phone_notices k where k.customer_id = c_customer and k.phone = v_phone) then
--         insert into public.referral_phone_notices (customer_id, referrer_customer_id, phone, notice_version, referral_code, withdrawn_at)
--         values (c_customer, v_ref, v_phone, 'hide-request', '', now()) returning id into v_new;
--       end if;
--       -- Their marks and the marks holding the number: those not hidden yet are withdrawn; one Audit Log row on each
--       -- record, naming who asked, the rows withdrawn now (the one made here among them) and those hidden already.
--       with m as (
--         select k.id, k.customer_id, k.withdrawn_at is not null and k.id is distinct from v_new as already
--           from public.referral_phone_notices k
--          where k.customer_id = c_customer or k.phone = v_phone
--       ), w as (
--         update public.referral_phone_notices k set withdrawn_at = now() from m where k.id = m.id and k.withdrawn_at is null
--       )
--       insert into public.audit_logs (table_name, record_id, action, new_data, module)
--       select 'customers', m.customer_id, 'referral_phone_hidden',
--              jsonb_build_object('marks_withdrawn', count(*) filter (where not m.already),
--                                 'mark_ids', coalesce(jsonb_agg(m.id order by m.id) filter (where not m.already), '[]'),
--                                 'hidden_already', coalesce(jsonb_agg(m.id order by m.id) filter (where m.already), '[]'),
--                                 'made_for_hide', v_new, 'asked_by', c_customer, 'asked', c_asked, 'version', 492), 'affiliate'
--         from m group by m.customer_id;
--       get diagnostics n = row_count;
--       raise notice '492 hide: done for % on % record(s)', c_customer, n;
--     end $hide$;
--   From then on no affiliate sees that number on those records (a dash),
--   also after a merge, and also under 484's My Network after an UNDO (a
--   withdrawn mark on a record hides its number there). The marks stay: they
--   are the evidence that the notice was given. Check afterwards with the
--   query above: no row shows it on My Network (affiliate_portal_network as
--   that referrer's login, or the 492 suite's way of reading it).
--   To show it again (only if they ask for that), the same way. It removes
--   the rows their hide made and restores the marks it withdrew (also those
--   a 484 hide withdrew), and changes nothing (ask the Owner) when someone
--   else also asked to hide one of them:
--     do $show$
--     declare
--       c_customer constant uuid := '00000000-0000-0000-0000-000000000000';  -- the referral who asked
--       c_asked constant text := 'by phone, 5 Nov 2026';                     -- how and when they asked
--       n int;
--     begin
--       -- Only what their own hide withdrew or made; none of it if someone else also asked to hide it (the Owner decides).
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
--         raise exception '492 show: % row(s) that % asked to hide, someone else also asked to hide (the Audit Log''s referral_phone_hidden rows); ask the Owner; nothing changed', n, c_customer;
--       end if;
--       -- The rows their hide made are removed (they were no notice); the marks it withdrew are restored.
--       with s as (
--         select k.id, k.customer_id, k.notice_version = 'hide-request' as made
--           from public.referral_phone_notices k
--          where k.withdrawn_at is not null
--            and exists (select 1 from public.audit_logs l
--                         where l.table_name = 'customers' and l.action = 'referral_phone_hidden'
--                           and l.new_data ->> 'asked_by' = c_customer::text and (l.new_data -> 'mark_ids') @> to_jsonb(k.id))
--       ), d as (
--         delete from public.referral_phone_notices k using s where k.id = s.id and s.made
--       ), u as (
--         update public.referral_phone_notices k set withdrawn_at = null from s where k.id = s.id and not s.made
--       )
--       insert into public.audit_logs (table_name, record_id, action, new_data, module)
--       select 'customers', s.customer_id, 'referral_phone_shown_again',
--              jsonb_build_object('marks_restored', count(*) filter (where not s.made),
--                                 'mark_ids', coalesce(jsonb_agg(s.id order by s.id) filter (where not s.made), '[]'),
--                                 'hide_rows_removed', coalesce(jsonb_agg(s.id order by s.id) filter (where s.made), '[]'),
--                                 'asked_by', c_customer, 'asked', c_asked, 'version', 492), 'affiliate'
--         from s group by s.customer_id;
--       get diagnostics n = row_count;
--       if n = 0 then
--         raise exception '492 show: % has no mark withdrawn at their request; nothing changed', c_customer;
--       end if;
--       raise notice '492 show: done for % on % record(s)', c_customer, n;
--     end $show$;
--   The 492 suite runs both blocks exactly as written here (H).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the md5 of the embedded function text;
--   * 484 is recorded as applied (20261102000820; two IFs, so a database
--     without the history table gets this file's own message);
--   * where the database stands: BEFORE (My Network 484's 070d1b48..., the
--     only BEFORE accepted) or AFTER (this file's: "already this version;
--     left alone"); anything else is refused, saying what it found;
--   * no other function takes My Network's name; its grants, compared as a
--     set, and not signed out;
--   * the 6 functions relied on, at the md5s read on 3 Nov 2026, and
--     referral_phone_notices' description (its columns, constraints,
--     indexes, row level security, grants, policies, triggers and owner).
--   Afterwards: the md5; the grants, as a set; the relied-on unchanged.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0492: no row left, no sequence moved, no message queued): made-up
--   records ("492 Check ...", seven fictional phones +61 2 5550 .... that no
--   customer, in use or deleted, and no active booking holds: range scans of
--   the partial phone indexes): an affiliate whose record and portal account
--   are made in one transaction (proven: own_record) and an active affiliate
--   record; Tier 1 referrals set by staff: one with a number and no mark, one
--   with a mark naming another referrer, one with a withdrawn mark, one whose
--   number a withdrawn mark on another record holds, one with a placeholder
--   (written with triggers off for that statement), and a Tier 2 customer.
--   Called as that affiliate (role authenticated, auth.uid() its login) three
--   times: proven and active: the first two rows' numbers and no other;
--   the record made a day before the account (not proven): no number;
--   proven again but suspended: no number; each time 484's keys, 'phone' on
--   Tier 1 only, and no other fixture number anywhere. Signed out is refused
--   My Network; a login with no affiliate account gets "Not an affiliate
--   account". The portal account and the placeholder are written with
--   session_replication_role = replica for that statement only (484's
--   reasons: the welcome WhatsApp's sequence number, the phone policy).
--   Measured on the dry run: see DEPLOY ORDER 2.
--
-- DEPLOY ORDER (each step with the user's go-ahead where it says so)
--
--   0. The user's go-ahead for this file, its pages and the wording push.
--   1. Before applying, re-read supabase_migrations.schema_migrations and
--      origin/main (parallel sessions; message the session holding 487/488):
--      491 is the head (20261103053945) and the BEFORE md5s below still hold.
--   2. Dry run on a copy of production as it is then (rc491_live: its
--      fingerprint must equal production's, 3b9d2f33.../1414 on 3 Nov 2026):
--      apply this file wrapped as in step 3, then the plain file again
--      ("already this version; left alone"); time them; then run
--      scripts/referrals/tests/affiliate-network-phone-492.sql with
--      -v skip_install=1, and the 480, 482 and 484 suites the same way.
--   3. Apply this file wrapped: begin; this file; insert into
--      supabase_migrations.schema_migrations (version, name, statements)
--      values (<version>, '492_affiliate_network_shows_every_tier1_phone',
--      array[<this file>]); commit, built with Python, the file embedded as
--      a dollar-quoted literal (never with cat or a psql backtick variable:
--      they drop the final newline). Read the row back:
--        select version, md5(array_to_string(statements, '')), cardinality(statements)
--          from supabase_migrations.schema_migrations
--         where name = '492_affiliate_network_shows_every_tier1_phone';
--      It must give one row, this file's md5 (md5 -q of it) and 1. After an
--      unclear result (a timeout, a lost connection), run this read before
--      anything else: a row means the apply committed, so do not apply again.
--   4. Read-only checks: the AFTER md5 and grants; the fingerprint and the
--      grant list (AFTER, below); the counts of WHAT THE PERSON SEES.
--   5. Commit and push this file, its suite, the 480, 482 and 484 suites'
--      edits and the pages (My Network's sentence, the Rules page): a push to
--      main is a Vercel deploy. Until it is live, My Network's old sentence
--      ("... after being told you would see it") shows beside every number:
--      push straight after step 4.
--
-- BEFORE (production, read on 3 Nov 2026 after 491: head 20261103053945;
-- md5 of pg_get_functiondef with search_path public)
--   changed: affiliate_portal_network() 070d1b485d32cec99fa627b816a91b4a
--     (484's AFTER, the only BEFORE accepted)
--     grants, as a set: {authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}
--   relied on, not changed: c_relied / c_relied_md5 below (6 functions), and
--     referral_phone_notices' description ec6de1ddd64fb06b87b401b9f7a55984
--   public function fingerprint: 3b9d2f339b0338a1f8979471162bb6c9 (1414)
--   grant list (oid::regprocedure||'='||proacl, '|', by signature):
--     a888e7b83372dc4a0b75e6f0f6980d96
-- AFTER (for later guards)
--   affiliate_portal_network(): 5506f7291146534551a25e52a1e7820b
--     grants, as a set: unchanged
--   public function fingerprint, worked out on a copy of production (3 Nov
--   2026), 491 -> 492: e42b527b89bff668e886be7770063519 (1414 functions: none added)
--   grant list: a888e7b83372dc4a0b75e6f0f6980d96 (unchanged)
--
-- UNDO (with the user's go-ahead; the 492 suite's U section runs it exactly
-- as written here)
--   NUMBERS AS 484 (only referrals told at sign-up), in one transaction:
--   begin;
--     0. stop unless My Network is this file's, so a later version is never
--        overwritten:
--     do $undo$
--     begin
--       perform set_config('search_path', 'public', true);
--       if md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure)) <> '5506f7291146534551a25e52a1e7820b' then
--         raise exception 'UNDO 492: public.affiliate_portal_network() is not 492''s version (md5 %); nothing changed',
--           md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure));
--       end if;
--     end $undo$;
--     1. re-apply 484's text of My Network: the text between $d1$ and $d1$
--        in supabase/484_affiliate_network_shows_tier1_phone.sql (its
--        c_net_def; that text's own md5 is 070d1b485d32cec99fa627b816a91b4a),
--        run as one statement; CREATE OR REPLACE keeps the grants;
--   commit. My Network then shows a number only for a referral told at
--   sign-up (one, today), and every number hidden stays hidden (a withdrawn
--   mark on a record hides it there; the hide block also withdraws the marks
--   holding the number on other records). The history row and any
--   'hide-request' rows stay. Running this file again (plain, or wrapped
--   without a new history row) finds BEFORE and shows every number again.
--   UNDO again stops at its step 0.
--
-- Test: scripts/referrals/tests/affiliate-network-phone-492.sql (begin ...
-- rollback; it installs this file twice where 491 is in and 492 is not, or
-- runs with -v skip_install=1 where 492 is in). The 480, 482 and 484 suites
-- run on a 492 database too (they accept this file's AFTER; the 484 suite
-- puts 484's My Network back for its run, as UNDO does). Pages:
-- affiliate-network-phone-484.test.mjs (now the 492 sentence) and
-- rules-page-490.test.mjs.

set lock_timeout = '2s';

do $mig$
declare
  -- ── What this changes ──
  -- My Network: 484's (BEFORE, the only version accepted) -> this file's (AFTER).
  c_net constant text := 'affiliate_portal_network()';
  c_net_before constant text := '070d1b485d32cec99fa627b816a91b4a';
  c_net_after constant text := '5506f7291146534551a25e52a1e7820b';
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
           -- 492 (the Owner, 3 Nov 2026): the stored number, trimmed, of every
           -- direct referral, when v_phones, unless they asked to hide it: a
           -- withdrawn mark in referral_phone_notices on the record, or one that
           -- holds the number the record holds now (a number hidden is hidden on
           -- every record holding it). Otherwise null (a dash on the page). Tier
           -- 2: no phone key at all.
           'phone', case when v_phones and btrim(c.phone) ~ '[0-9]' and btrim(c.phone) !~* '^(AFF-.{8}|LEGACY-.*)$'
                          and not exists (select 1 from public.referral_phone_notices w
                                           where w.withdrawn_at is not null
                                             and (w.customer_id = c.id or w.phone = public.normalize_customer_phone(c.phone)))
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
  -- The marks (484), read for a hide: their columns, constraints, indexes, row level security, grants, policies,
  -- triggers and owner, as read on 3 Nov 2026 (484's AFTER).
  c_tbl constant text := 'ec6de1ddd64fb06b87b401b9f7a55984';

  -- ── Relied on, not changed (production, 3 Nov 2026) ──
  -- Who the affiliate is; whether it is active (answer 2); the proof of the login's link (answer 2); the bookings
  -- My Network passes through (482's); the phone normalizer a hide is compared with; the spend shown.
  c_relied constant text[] := array[
    'current_affiliate_customer_id()', 'affiliate_is_active(uuid)', 'affiliate_login_link_proof(uuid,uuid)',
    'calcom_customer_bookings(uuid[],date)', 'normalize_customer_phone(text)', '_aff_settled_spend(uuid)'];
  c_relied_md5 constant text[] := array[
    '51695acf5f26ce3918d6003d0c980b0f', '2ba3ff0aa858045718cbb3719b959685', '2484fb464733c124213b96152837a660',
    '14987e9e9f033290010042a5632bc81c', 'b2bfac910e0c9eff402ba44e19750bee', '965c7d50c02c712fc4433a898d212e19'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v_role text := current_user;
  v text; v_md5 text; v_oid regprocedure; v_state text; v_tbl text;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_ph text[]; t_code text; t_mail text; t_me uuid; t_aff uuid; t_uid uuid; t_srr text;
  t_plain uuid; t_other uuid; t_hid uuid; t_ans jsonb; t_err text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──
  if md5(c_net_def) <> c_net_after then
    raise exception '492: the text of public.% is not the tested one (md5 %)', c_net, md5(c_net_def); end if;

  -- Two IFs: PL/pgSQL prepares a whole condition before it runs it, so one that names a missing table fails
  -- there, before any of it is evaluated.
  if to_regclass('supabase_migrations.schema_migrations') is null then
    raise exception '492: 484 (20261102000820) is not recorded in supabase_migrations.schema_migrations. Apply 484 first (a copy built with psql: add its row as production has it).';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261102000820') then
    raise exception '492: 484 (20261102000820) is not recorded in supabase_migrations.schema_migrations. Apply 484 first (a copy built with psql: add its row as production has it).';
  end if;

  -- Where this database stands: BEFORE, My Network 484's; AFTER, this file's ("already this version; left alone").
  -- Anything else is refused.
  v_oid := to_regprocedure('public.' || c_net);
  if v_oid is null then raise exception '492: public.% is missing (155 makes it, 484 the version this replaces)', c_net; end if;
  v_md5 := md5(pg_get_functiondef(v_oid));
  if v_md5 = c_net_before then v_state := 'before';
  elsif v_md5 = c_net_after then v_state := 'after';
  else
    raise exception '492: public.% is neither 484''s (md5 %) nor this file''s (md5 %): found md5 %. Re-read it and re-test before applying.',
      c_net, c_net_before, c_net_after, v_md5;
  end if;
  -- No other function takes its name (an overload makes the API's calls ambiguous); its grants as read.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'affiliate_portal_network' and p.oid <> v_oid;
  if v is not null then raise exception '492: another function takes the name of My Network: %', v; end if;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid) is distinct from c_net_acl
     or has_function_privilege('anon', v_oid, 'execute') then
    raise exception '492: the grants of public.% are not as read on 3 Nov 2026 (signed-in logins, the owner and the service role; not signed out)', c_net; end if;
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '492: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
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
  if v_tbl is distinct from c_tbl then
    raise exception '492: public.referral_phone_notices is missing or not 484''s (description md5 %). Re-read it and re-test before applying.', coalesce(v_tbl, 'missing');
  end if;

  -- ── Change ──
  if v_state = 'before' then
    execute c_net_def;
    raise notice '492: public.% replaced (484''s -> 492''s: every Tier 1 number, the login proven and the affiliate active, unless hidden)', c_net;
  else
    raise notice '492: already this version; left alone';
  end if;

  -- ── Afterwards ──
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_net))) is distinct from c_net_after then
    raise exception '492: My Network was installed with an md5 other than the tested one'; end if;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_net)) is distinct from c_net_acl
     or has_function_privilege('anon', to_regprocedure('public.' || c_net), 'execute') then
    raise exception '492: the grants are not as tested'; end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '492: public.% changed', c_relied[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ──
  begin
    -- Written as the server (no request).
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- Seven fictional phones in a row (+61 2 5550 nnnn) that no customer, in use or deleted, and no active booking
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
    if t_base is null then raise exception '492: the self-test found no free fictional phones'; end if;
    t_ph := array(select '+6125550' || lpad((t_base + n)::text, 4, '0') from generate_series(0, 6) n);
    t_code := '492CHECK' || upper(t_sfx);
    t_mail := '492-check-' || t_sfx || '@example.invalid';
    -- The affiliate: its record made with its portal account in one transaction (proven: its own sign-up made it),
    -- holding the login's email, which is not verified; an active affiliate record with a made-up code; a login.
    insert into public.customers (full_name, phone, email) values ('492 Check Affiliate', t_ph[1], t_mail) returning id into t_me;
    insert into public.customer_affiliates (customer_id, status, activated_at, referral_code)
      values (t_me, 'active', now(), t_code) returning id into t_aff;
    insert into auth.users (id, email) values (gen_random_uuid(), t_mail) returning id into t_uid;
    -- The portal account with triggers off for this statement only (its trigger would queue a welcome WhatsApp and
    -- take a number from the outbox's sequence, which an undone block does not give back).
    t_srr := current_setting('session_replication_role');
    set local session_replication_role = replica;
    insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (t_uid, t_me, t_aff, 'claimed');
    execute format('set local session_replication_role = %L', t_srr);

    -- Its Tier 1, all set by staff (no sign-up, so nobody was told): a number and no mark; a mark naming another
    -- referrer (it decides nothing now); a withdrawn mark (they asked to hide it); a number a withdrawn mark on
    -- another record holds (hidden by number); 484's first draft's placeholder (AFF- and 8 characters: the phone
    -- policy refuses one now, so written with triggers off for that statement only). A Tier 2 customer.
    insert into public.customers (full_name, phone, referred_by) values ('492 Check Plain', t_ph[2], t_me) returning id into t_plain;
    insert into public.customers (full_name, phone, referred_by) values ('492 Check Other Mark', t_ph[3], t_me) returning id into t_other;
    insert into public.customers (full_name, phone, referred_by) values ('492 Check Hidden', t_ph[4], t_me) returning id into t_hid;
    insert into public.customers (full_name, phone, referred_by) values ('492 Check Same Number', t_ph[5], t_me);
    insert into public.customers (full_name, phone, referred_by) values ('492 Check Placeholder', t_ph[6], t_me);
    set local session_replication_role = replica;
    update public.customers set phone = 'AFF-' || t_sfx where full_name = '492 Check Placeholder' and referred_by = t_me;
    execute format('set local session_replication_role = %L', t_srr);
    insert into public.customers (full_name, phone, referred_by) values ('492 Check Tier Two', t_ph[7], t_plain);
    insert into public.referral_phone_notices (customer_id, referrer_customer_id, phone, notice_version, referral_code, withdrawn_at)
      values (t_other, t_plain, t_ph[3], 'r-page-2026-11', t_code, null),
             (t_hid, t_me, t_ph[4], 'r-page-2026-11', t_code, now()),
             (t_hid, t_me, t_ph[5], 'hide-request', '', now());
    -- (the last: a withdrawn row on Hidden's record holding Same Number's number, as a hide by number makes one: it
    -- hides that number on every record holding it)

    -- As the affiliate, as the portal calls it: signed in (the API's role authenticated), auth.uid() its login.
    -- 1: proven, active; 2: the link not proven (the record made before the account, nothing else proves it);
    -- 3: proven again, suspended (never reactivated here: reactivation queues a WhatsApp and takes a sequence
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
      if t_err is not null then raise exception '492: the self-test''s call as the affiliate failed: %', t_err; end if;
      if t_ans is null
         or jsonb_array_length(t_ans -> 'tier1') <> 5 or jsonb_array_length(t_ans -> 'tier2') <> 1
         -- Plain and Other Mark: their numbers while proven and active; else the key with no number
         or (select r -> 'phone' from jsonb_array_elements(t_ans -> 'tier1') r where r ->> 'customer_name' = '492 Check Plain')
            is distinct from (case when i = 1 then to_jsonb(t_ph[2]) else 'null'::jsonb end)
         or (select r -> 'phone' from jsonb_array_elements(t_ans -> 'tier1') r where r ->> 'customer_name' = '492 Check Other Mark')
            is distinct from (case when i = 1 then to_jsonb(t_ph[3]) else 'null'::jsonb end)
         -- the hidden one, the number hidden on another record, the placeholder: the key with no number
         or exists (select 1 from jsonb_array_elements(t_ans -> 'tier1') r
                     where r ->> 'customer_name' not in ('492 Check Plain', '492 Check Other Mark') and r -> 'phone' is distinct from 'null'::jsonb)
         -- every row: 484's keys, and 'phone' on Tier 1 only
         or exists (select 1 from jsonb_array_elements(t_ans -> 'tier1') r
                     where (select array_agg(k order by k collate "C") from jsonb_object_keys(r) k)
                           is distinct from array['booking_at', 'booking_state', 'customer_name', 'joined_at', 'phone', 'purchases',
                                                  'referral_date', 'tier', 'total_spent', 'your_commission'])
         or exists (select 1 from jsonb_array_elements(t_ans -> 'tier2') r
                     where (select array_agg(k order by k collate "C") from jsonb_object_keys(r) k)
                           is distinct from array['booking_at', 'booking_state', 'customer_name', 'joined_at', 'parent_name', 'purchases',
                                                  'referral_date', 'tier', 'total_spent', 'your_commission'])
         -- no other number anywhere: not the affiliate's own, the hidden ones, the placeholder's (or what it held), the
         -- Tier 2 customer's
         or (select bool_or(strpos(t_ans::text, substr(t_ph[k], 2)) > 0) from unnest(array[1, 4, 5, 6, 7]) k)
         or strpos(t_ans::text, 'AFF-') > 0
         or (i > 1 and (strpos(t_ans::text, substr(t_ph[2], 2)) > 0 or strpos(t_ans::text, substr(t_ph[3], 2)) > 0)) then
        raise exception '492: the self-test''s My Network (% of 3: proven and active, not proven, suspended) is not as tested: %', i, t_ans; end if;
    end loop;

    -- Signed out: My Network refused (no grant); a login with no affiliate account: as before.
    t_err := null;
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    begin
      execute 'set local role anon';
      perform public.affiliate_portal_network();
      t_err := 'answered';
    exception when insufficient_privilege then t_err := '42501';
              when others then t_err := sqlstate || ' ' || sqlerrm;
    end;
    execute format('set local role %I', v_role);
    perform set_config('request.jwt.claims', '', true);
    if t_err is distinct from '42501' then
      raise exception '492: the self-test''s signed-out call to My Network was not refused: %', t_err; end if;
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
      raise exception '492: the self-test''s login with no affiliate account was not refused as before: %', t_err; end if;

    raise exception using errcode = 'P0492', message = '492: self-test done, undone';
  exception when sqlstate 'P0492' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
end $mig$;
