-- 485_forms_do_not_fill_affiliate_record_email.sql
--
-- A FORM'S EMAIL NO LONGER GOES ONTO A CUSTOMER RECORD THAT HAS A PORTAL
-- LOGIN OR AN AFFILIATE RECORD: NOT FROM THE QR HEALTH FORM, NOT FROM THE
-- EVENT WEBSITE'S REGISTRATION, AND NOT WHEN STAFF ATTACH OR LINK A HELD ONE
-- (the Owner, 2 Nov 2026)
--
-- WHY
--   484 shows an affiliate the phone numbers of the direct referrals the /r/
--   page told, and only when the affiliate's portal login is proven to be its
--   record's. One proof is (d), verified_email: the login's email is verified
--   and is the record's email (customer_email_match_key: the same inbox).
--   Forms fill a record's blank email with the email typed: the QR health
--   form (submit_health_survey, signed out, for a record it finds by phone
--   and name) and the event website's registration (event_web_fill_customer,
--   for the record a registration names) with no staff step; and staff
--   attaching a held QR form (attach_held_health_survey) or linking a held
--   registration (event_registration_attach, which calls
--   event_web_fill_customer). So a login that 437 joined to a record on the
--   phone alone (not proven: no number shows) could put its own inbox on
--   that record through a form, verify it, and be proven; and an email put on
--   an affiliate's record before any login joins it works the same way later.
--   These are the two orders in 484's NOT COVERED (Q4). A staff attach or
--   link decides whose FORM it is, not whose LOGIN: it is not one of the
--   staff decisions 484 counts as proof (a claim resolved, Same person, Link
--   to this customer), yet the email it copied would prove the login.
--   Reach on 2 Nov 2026: none. Both of 484's monitoring counts read 0, but
--   they count only records and logins still open to a plant, not one
--   already done (once a form fills the email, the row leaves both counts).
--   A one-off check that day of the 14 portal logins proven only by (d)
--   found none whose record's email came from a form on a referrer's or an
--   affiliate's record, in either order.
--   The Owner (2 Nov 2026): accept it for now, read both counts at each
--   review, and close it soon after 484; and (asked again the same day) the
--   staff attach and link do not copy the email either. This file closes it.
--
-- THE RULE (the Owner, 2 Nov 2026)
--   No form's email goes onto a customer record that has a portal login (an
--   affiliate_accounts row for it, claimed or disabled) or an affiliate
--   record (a customer_affiliates row for it, in any status: suspended and
--   deleted ones too): not from the QR form, not from the registration, and
--   not when staff attach a held QR form or link a held registration to it.
--   Everything else these fill, they fill as before, and on any other record
--   they fill a blank email as before. The email typed stays where it always
--   was: on the form (health_surveys.email; staff see it on the survey's
--   detail) and on the registration (event_registration_people.email; staff
--   see it under To match while it waits, and, once staff link it, in that
--   link's Audit Log entry (its Excel export); one the website matched by
--   itself shows it nowhere in the app). Staff put an
--   email on such a record themselves, in Edit customer, when it is really
--   theirs: a decision about the email itself. Nothing copies it for them
--   (the survey's Edit details copies only what was changed).
--
-- WHAT THIS DOES
--   Replaces three functions with their tested texts, each made from
--   production's own text by the smallest edit:
--   * submit_health_survey(text,jsonb,jsonb,text) (468's): when the form
--     finds a record by its phone and name, the email is set only if it is
--     null and the record has neither a portal login nor an affiliate record
--     (before: coalesce(email, v_email)). Every other line is unchanged: the
--     matching, the holds, the form row, the reply and the Audit Log entry.
--   * event_web_fill_customer(uuid,uuid) (436's): the same for the email of
--     the record a registration names. Its two callers are the website's
--     registration (event_web_register, the server's) and staff linking a
--     held registration on the Event page (event_registration_attach); both
--     follow the rule. The record is still updated only when there is
--     something to fill, so one with a portal login or an affiliate record
--     and a source already set is not touched (not even its updated_at). When
--     such a record is updated for its source, its email stays exactly as it
--     was (before, a filled email was also trimmed and an empty one
--     cleared).
--   * attach_held_health_survey(uuid,uuid,text) (419's): staff attaching a
--     held QR form fill the same record's other empty details as before, but
--     not its email (before: coalesce(email, nullif(btrim(v_s.email), ''))).
--   CREATE OR REPLACE keeps the three functions' grants (checked again as
--   sets). The pages (pushed with this file in DEPLOY ORDER step 3, after
--   the apply): the Event page's and the Surveys page's attach dialogs say
--   that an affiliate's email, even a former affiliate's, is not filled.
--
-- NOT CHANGED
--   * Edit customer (update_customer) and the survey's Particulars
--     (update_survey_particulars_v2): staff typing an email is a decision
--     about the email itself, and stays theirs.
--   * A record a form makes (someone new) gets the email typed, as before: a
--     new record has no portal login.
--   * Every other function; no table, index, column or grant.
--
-- NOT COVERED (told to the Owner)
--   * A record with neither a portal login nor an affiliate record still
--     takes a blank email from the forms. If a login later joins it on the
--     phone and verifies that inbox, the login is proven (d). Even so, no
--     number shows for referrals made before the record had an affiliate
--     record: 484's marks name the referrer whose link a person signed up
--     through, and a record with no affiliate record has no link (unless a
--     merge brings another record's marks: see A merge, below). 484's
--     first monitoring count counts such records that have referrals only
--     while their email is blank, not once a form has filled it.
--   * The other side of the rule: a login that 437 joined on the phone alone
--     to a record with no email can no longer prove itself by sending a form
--     with its own email and verifying it (that is order (2), and a genuine
--     one looks the same as a planted one). Staff put the login's email on
--     the record in Edit customer, after which verifying proves it; or Same
--     person, a merge into a record whose email staff know is the login's,
--     or an Owner's Unlink then Link to this customer. The 9
--     unproven logins of 2 Nov 2026 all have records with an email, so none
--     of them is affected; nobody is told why the Phone column does not
--     appear.
--   * The phone-and-email rules (468's QR form, 469's sign-up, event matcher
--     and onboarding, 466's record email, the sign-up candidate list,
--     calcom_booking_owner on a shared phone, the event website's
--     self-referral check) cannot use an email that only a form typed for
--     such a record: a later form or registration under another name waits
--     for staff (phone_in_use) instead of matching, and so on. Such a record
--     also exports to Xero with no contact email until staff add one. Reach on
--     2 Nov 2026: none (none of the 5 records with a login and no email has a
--     survey, a registration, a shared phone, an open hold or anyone signed
--     up through its link; 2 have 3 referrals set by staff without a link,
--     which these rules do not read; no Xero download yet).
--   * A login made at the same moment as a form: the QR form, the website's
--     registration and the portal's own sign-up (complete_affiliate_onboarding)
--     all take the same lock on the normalized phone
--     ('customer-identity:<phone>'), so a self-service join and a form on the
--     same phone run one after the other. A staff join or activation is not
--     behind that lock: a QR form or a registration that runs while one is in
--     flight (not yet committed) does not see it and fills the email, which
--     ends as if the form had come first (the first bullet). (The
--     registration's fill checks in one statement and fills in the next, the
--     QR form in one.) The staff attach and link lock the record first, so
--     they wait for a join in flight and see it. Keep 484's two monitoring
--     counts at each review (they show what is still open, not a plant
--     already done).
--   * A merge. An Owner's or Manager's merge that keeps a record whose email
--     a form typed while it had neither a portal login nor an affiliate
--     record, and retires one with a login, an affiliate record or /r/ marks,
--     moves them onto that email: a login on the kept record (moved, or
--     joined later on the phone alone) that verifies the inbox is proven
--     (d), and the moved marks' numbers show, including referrals made
--     before the kept record had an affiliate record. A merge decides that
--     two records are one person, not whose login it is. It was the same
--     before this file (485 changes no merge). Reach on 2 Nov 2026: no merge
--     since 484. Until a guard exists, staff check that the kept record's
--     email is the affiliate's before such a merge, or keep the record that
--     holds the portal login.
--
-- SAFETY
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the three functions are production's of 2 Nov 2026 (BEFORE: all
--     replaced) or all this file's (AFTER: "already this version; left
--     alone", nothing changed); anything else is refused, a mix included;
--   * no other function takes any of their names; the grants, compared as
--     sets, are as read: the QR form's are anon, authenticated, the owner and
--     the service role; the registration fill's are the owner's and the
--     service role's; the staff attach's are authenticated, the owner and
--     the service role (the function itself refuses any signed-in login that
--     is not active staff);
--   * the columns the new lines read are there, of the types read.
--   Afterwards: the three functions have their AFTER md5s and their grants
--   as before.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0485, so it leaves no row and takes no number from any sequence):
--   made-up customers ("485 Check ...", fictional phones +61 2 5550 nnnn
--   that no customer, in use or deleted, holds), each with no email: one with
--   an affiliate record, one with a portal login (its welcome-WhatsApp
--   trigger off for that one insert) and a plain one. As the signed-out QR
--   page, a form for each by name and phone, then one for someone new: the
--   affiliate's and the login's records keep no email and still take the
--   occupation; the plain record and the new customer take the email typed;
--   each form keeps its email. As the event website's server, a registration
--   for each (the plain record's email emptied again, the email typed with
--   spaces around it): only the plain record takes it, trimmed. Then two
--   more records with no email and no survey, an affiliate's and a plain one:
--   a form under another name with each one's phone waits for staff, and is
--   attached to that record as the server would (the server passes the staff
--   check): both take the occupation, only the plain record the
--   email. A second run changes nothing ("already this version; left alone";
--   its self-test runs and is undone again).
--   Locks: the lock timeout is 2 s, so a sign-up or form queued behind it
--   still goes through. Replacing a function locks its catalogue row only (a
--   call already running keeps the old version to its end). The self-test
--   locks only its own rows, its fictional phones' identity locks and (key
--   share) the store it uses.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--   1. Dry run on a copy of production as it is then (rc480_live plus
--      production's two store codes, 480's history row, and 483, 482 and 484
--      applied from their files with their history rows; its public
--      fingerprint and grant list must equal production's): apply this file
--      wrapped, then again. The first run ends at the AFTER fingerprint
--      below; the second says "already this version; left alone" and
--      changes nothing.
--   2. Apply wrapped: begin; this file; insert into
--      supabase_migrations.schema_migrations (version, name, statements)
--      values (<version>, '485_forms_do_not_fill_affiliate_record_email',
--      array[<this file>]); commit. Build the wrapper with the file embedded
--      as a literal (Python), never with $(cat ...) or a psql backtick
--      variable, which drop the final newline. Run it as postgres: the Supabase CLI's
--      db query --linked does (checked 2 Nov 2026), and the self-test needs
--      SET ROLE anon, session_replication_role and INSERT on auth.users.
--      Read the row back at once, and before any retry:
--        select md5(array_to_string(statements, '')), cardinality(statements)
--          from supabase_migrations.schema_migrations
--         where name = '485_forms_do_not_fill_affiliate_record_email';
--      It must give this file's md5 and 1 (a row means the apply committed:
--      never apply again). Checks: the three AFTER md5s and grants below;
--      the fingerprint and the grant list (AFTER); no "485 Check" customer.
--   3. Commit and push, in one push, this file, its suites
--      (scripts/survey/tests/affiliate-email-485.sql,
--      affiliate-email-485.test.mjs and the 485 test added to
--      survey-holds-panel.test.mjs), the edits to
--      scripts/survey/tests/to-match-468.sql and qr-holds.sql (they accept
--      this file's AFTERs), and the two dialog sentences
--      (src/components/events/RegistrationHoldsPanel.tsx and
--      src/components/SurveyHoldsPanel.tsx). The sentences are true only
--      once this file is in: push after step 2. Then check that the live
--      bundle carries both sentences.
--   468's, 436's, 439's, 469's and 419's files pin these functions' BEFORE
--   md5s: none of them runs again over this file (by design: nothing to
--   re-run).
--
-- BEFORE (production, 2 Nov 2026, head 20261102000820 (484); md5 of
-- pg_get_functiondef with search_path public)
--   submit_health_survey(text,jsonb,jsonb,text)    014a970de2e5dee64e4027459cac5280  (468's AFTER)
--   event_web_fill_customer(uuid,uuid)             89488f15e0b030b9ed14c3c31049a71e  (436's)
--   attach_held_health_survey(uuid,uuid,text)      53aabcdd564da445131633c41bef8249  (419's AFTER)
--   public function fingerprint                    893e854b4baf8b653dcf13bdcda2a356 (1398 functions)
--   grant list                                     e68aa1abc012f3e4539dd315b96a1ea1
-- AFTER (for later guards)
--   submit_health_survey(text,jsonb,jsonb,text)    860743f4f2e92f669e257121de0a9308
--     grants, as a set: {anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}
--   event_web_fill_customer(uuid,uuid)             4cefb8a7ae96aa5836041cf57cb3f33f
--     grants, as a set: {postgres=X/postgres,service_role=X/postgres}
--   attach_held_health_survey(uuid,uuid,text)      8a66d8e6d7008c79d94c5b20ffecb4df
--     grants, as a set: {authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}
--   public function fingerprint                    d5bcc0cef63fe73c19cf2c9a949b05d5 (1398, worked out on a
--                                                  production-equal copy, 2 Nov 2026)
--   grant list                                     e68aa1abc012f3e4539dd315b96a1ea1 (unchanged)
--
-- UNDO (with the Owner's go-ahead). Run the lines between the two markers
-- below with their leading "--   " removed, after putting this file's md5
-- as applied (its history row's) in place of <M>. It stops unless the three
-- functions are this file's; rebuilds production's texts of 2 Nov 2026 by
-- swapping each edit back, and runs them only if their md5s are the BEFORE
-- ones; and deletes every 485 history row holding the file. The 485 suite's
-- U section runs it as written. Then revert the dialog sentences (a pages
-- commit): they would say an affiliate's email is not filled when it is.
--   ---- UNDO 485 begins ----
--   begin;
--   set local lock_timeout = '2s';
--   do $undo$
--   declare
--     c_sig constant text[] := array['submit_health_survey(text,jsonb,jsonb,text)', 'event_web_fill_customer(uuid,uuid)',
--                                    'attach_held_health_survey(uuid,uuid,text)'];
--     c_before constant text[] := array['014a970de2e5dee64e4027459cac5280', '89488f15e0b030b9ed14c3c31049a71e', '53aabcdd564da445131633c41bef8249'];
--     c_after constant text[] := array['860743f4f2e92f669e257121de0a9308', '4cefb8a7ae96aa5836041cf57cb3f33f', '8a66d8e6d7008c79d94c5b20ffecb4df'];
--     -- this file's md5 as applied (its history row's): fill in before running
--     c_m constant text := '<M>';
--     v_def text; v_path text := current_setting('search_path'); n int;
--   begin
--     perform set_config('search_path', 'public', true);
--     for i in 1 .. 3 loop
--       if to_regprocedure('public.' || c_sig[i]) is null
--          or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) is distinct from c_after[i] then
--         raise exception 'UNDO 485: public.% is not 485''s version; nothing changed', c_sig[i]; end if;
--     end loop;
--     -- The QR form: 485's lines back to 468's.
--     v_def := replace(pg_get_functiondef(to_regprocedure('public.' || c_sig[1])),
--   $s_new$    -- Fill ONLY currently-empty, safe fields. NEVER touch full_name, phone, or
--       -- any referral attribution (referred_by / referred_at / referral_source /
--       -- referral_code_used).
--       -- 485 (the Owner, 2 Nov 2026): nor the email of a record that has a portal
--       -- login or an affiliate record: 484's proof (d) takes a login whose
--       -- verified email is its record's as proven, so a form must not put an
--       -- email there. The form keeps the email typed; staff may copy it.
--       update public.customers
--          set email             = case when email is null
--                                        and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
--                                        and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
--                                       then v_email else email end,
--   $s_new$,
--   $s_old$    -- Fill ONLY currently-empty, safe fields. NEVER touch full_name, phone, or
--       -- any referral attribution (referred_by / referred_at / referral_source /
--       -- referral_code_used).
--       update public.customers
--          set email             = coalesce(email, v_email),
--   $s_old$);
--     if md5(v_def) <> c_before[1] then
--       raise exception 'UNDO 485: the rebuilt public.% is not 468''s (md5 %); nothing changed', c_sig[1], md5(v_def); end if;
--     execute v_def;
--     -- The registration's fill: 485's three edits back to 436's.
--     v_def := replace(replace(replace(pg_get_functiondef(to_regprocedure('public.' || c_sig[2])),
--   $e_new1$  v_src public.customer_source_options%rowtype;
--     -- 485 (the Owner, 2 Nov 2026): the record has a portal login or an affiliate
--     -- record, so the registration leaves its email as it is (484's proof (d)
--     -- reads it); the registration keeps the email typed.
--     v_keep_email boolean;
--   begin
--   $e_new1$,
--   $e_old1$  v_src public.customer_source_options%rowtype;
--   begin
--   $e_old1$),
--   $e_new2$  v_keep_email := exists (select 1 from public.affiliate_accounts a where a.customer_id = p_customer_id)
--                     or exists (select 1 from public.customer_affiliates f where f.customer_id = p_customer_id);
--     update public.customers
--        set email             = case when v_keep_email then email
--                                     else coalesce(nullif(btrim(email), ''), nullif(btrim(p.email), '')) end,
--   $e_new2$,
--   $e_old2$  update public.customers
--        set email             = coalesce(nullif(btrim(email), ''), nullif(btrim(p.email), '')),
--   $e_old2$),
--   $e_new3$     and ((not v_keep_email and nullif(btrim(email), '') is null and nullif(btrim(p.email), '') is not null)
--   $e_new3$,
--   $e_old3$     and ((nullif(btrim(email), '') is null and nullif(btrim(p.email), '') is not null)
--   $e_old3$);
--     if md5(v_def) <> c_before[2] then
--       raise exception 'UNDO 485: the rebuilt public.% is not 436''s (md5 %); nothing changed', c_sig[2], md5(v_def); end if;
--     execute v_def;
--     -- Staff attaching a held QR form: 485's lines back to 419's.
--     v_def := replace(pg_get_functiondef(to_regprocedure('public.' || c_sig[3])),
--   $a_new$  v_gender := case when v_s.sex in ('male', 'female') then v_s.sex::public.customer_gender end;
--     -- 485 (the Owner, 2 Nov 2026): never the email of a record that has a portal
--     -- login or an affiliate record. Attaching decides whose form this is, not
--     -- whose login, and 484's proof (d) reads that email; staff add it in Edit
--     -- customer when it is theirs. The form keeps the email typed.
--     update public.customers
--        set email             = case when email is null
--                                      and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
--                                      and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
--                                     then nullif(btrim(v_s.email), '') else email end,
--   $a_new$,
--   $a_old$  v_gender := case when v_s.sex in ('male', 'female') then v_s.sex::public.customer_gender end;
--     update public.customers
--        set email             = coalesce(email, nullif(btrim(v_s.email), '')),
--   $a_old$);
--     if md5(v_def) <> c_before[3] then
--       raise exception 'UNDO 485: the rebuilt public.% is not 419''s (md5 %); nothing changed', c_sig[3], md5(v_def); end if;
--     execute v_def;
--     for i in 1 .. 3 loop
--       if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i] then
--         raise exception 'UNDO 485: public.% did not go back to its version before 485', c_sig[i]; end if;
--     end loop;
--     -- Every 485 history row holding this file's text.
--     delete from supabase_migrations.schema_migrations
--      where name = '485_forms_do_not_fill_affiliate_record_email' and md5(array_to_string(statements, '')) = c_m;
--     get diagnostics n = row_count;
--     if n < 1 then raise exception 'UNDO 485: no 485 history row holds the text with md5 %; nothing changed', c_m; end if;
--     raise notice 'UNDO 485: the three functions are back to their versions before 485; % history row(s) deleted', n;
--     perform set_config('search_path', v_path, true);
--   end $undo$;
--   commit;
--   ---- UNDO 485 ends ----
--
-- Test: scripts/survey/tests/affiliate-email-485.sql (begin ... rollback; it
-- installs this file twice where it is not in, or with -v skip_install=1
-- where it is); the dialog sentences: affiliate-email-485.test.mjs and
-- survey-holds-panel.test.mjs (the Surveys window as rendered).

set lock_timeout = '2s';

do $mig$
declare
  -- ── The three functions this changes: production's (BEFORE, 2 Nov 2026) -> this file's (AFTER) ──
  c_sig constant text[] := array['submit_health_survey(text,jsonb,jsonb,text)', 'event_web_fill_customer(uuid,uuid)',
                                 'attach_held_health_survey(uuid,uuid,text)'];
  c_name constant text[] := array['submit_health_survey', 'event_web_fill_customer', 'attach_held_health_survey'];
  c_before constant text[] := array['014a970de2e5dee64e4027459cac5280', '89488f15e0b030b9ed14c3c31049a71e', '53aabcdd564da445131633c41bef8249'];
  c_after constant text[] := array['860743f4f2e92f669e257121de0a9308', '4cefb8a7ae96aa5836041cf57cb3f33f', '8a66d8e6d7008c79d94c5b20ffecb4df'];
  -- Their grants, kept (compared as sets, sorted): the QR form is a signed-out endpoint; the registration's fill is
  -- the server's only (the website's, and staff linking a held registration reach it through
  -- event_registration_attach); staff attach a held QR form signed in (the function checks they are active staff).
  c_acl constant text[] := array['anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
                                 'postgres=X/postgres,service_role=X/postgres',
                                 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_def1 constant text :=
$d1$CREATE OR REPLACE FUNCTION public.submit_health_survey(p_token text, p_payload jsonb, p_symptoms jsonb, p_pdf_base64 text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_l public.survey_links%rowtype;
  v_phone text; v_norm text; v_name text; v_email text; v_cust_id uuid; v_id uuid; v_no text;
  v_sym jsonb; v_sex text; v_gender customer_gender;
  v_src public.customer_source_options%rowtype;
  v_src_id uuid; v_src_details text;
  v_matches uuid[]; v_match_count int; v_matched boolean := false; v_created boolean := false;
  -- 433: how the name matched, the email as compared, the customers who have
  -- the phone or the email's inbox, and why the form waits for staff, for whom.
  v_name_match text; v_email_key text; v_phone_holders uuid[]; v_email_holders uuid[];
  v_hold text; v_candidates uuid[];
  -- 419: the name as typed in two parts; the consultant's record the form goes
  -- into (Q10), the form's answers as a survey row, and what that gave back.
  v_first text; v_last text; v_into uuid; v_form public.health_surveys%rowtype; v_signed jsonb;
  -- 468: the customers in use with both this phone and this email's inbox.
  v_both uuid[];
begin
  select * into v_l from public.survey_links where token = p_token;
  if not found then raise exception 'This survey link is not recognised.'; end if;
  if not v_l.is_active then raise exception 'This survey link has been deactivated.'; end if;
  if v_l.expires_at is not null and v_l.expires_at < now() then
    raise exception 'This survey link has expired.'; end if;

  v_name  := nullif(trim(p_payload->>'full_name'), '');
  -- 419 (CUSTOMERS-8): the form sends the first and the last name as typed. A
  -- customer the form makes, and a form held for staff, keep them as typed;
  -- before, the whole name was split at its first space. A page loaded before
  -- 419 sends only the whole name, which is split as before.
  v_first := nullif(trim(p_payload->>'first_name'), '');
  v_last  := nullif(trim(p_payload->>'last_name'), '');
  if v_first is not null then
    v_name := public.join_person_name(v_first, v_last);
  else
    v_last := null;
  end if;
  v_phone := nullif(trim(p_payload->>'phone'), '');
  v_email := nullif(trim(p_payload->>'email'), '');
  if v_name is null then raise exception 'Name is required.'; end if;
  if v_phone is null then raise exception 'Mobile number is required.'; end if;
  if v_email is null then raise exception 'Email is required.'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Please enter a valid email address.'; end if;
  if nullif(p_payload->>'signature_data','') is null then raise exception 'Signature is required.'; end if;

  v_src_id := nullif(p_payload->>'source_option_id','')::uuid;
  v_src_details := nullif(trim(p_payload->>'source_details'), '');
  -- 419 (CUSTOMERS-12): an event's link names how its customers heard about us
  -- (Event or RoadShow, chosen when the link was made). That source, with the
  -- event's name as the details, is recorded, whatever the page sent. Older
  -- links, and a link whose source was later switched off, keep the
  -- customer's own answer.
  if nullif(btrim(v_l.event_name), '') is not null and v_l.source_option_id is not null
     and exists (select 1 from public.customer_source_options o where o.id = v_l.source_option_id and o.is_active) then
    v_src_id := v_l.source_option_id;
    v_src_details := btrim(v_l.event_name);
  end if;
  if v_src_id is null then raise exception 'Please tell us how you heard about us.'; end if;
  select * into v_src from public.customer_source_options where id = v_src_id and is_active = true;
  if not found then raise exception 'That source option is not available.'; end if;
  if v_src.requires_details and v_src_details is null then
    raise exception 'Please add a few details for "%".', v_src.label; end if;

  v_sex := nullif(p_payload->>'sex','');
  v_gender := case when v_sex in ('male','female') then v_sex::customer_gender else null end;
  v_norm := public.normalize_customer_phone(v_phone);

  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm, 0));
  perform public.require_resolved_customer_identity(v_norm,v_name);
  v_matches := public.customer_phone_name_matches(v_norm,v_name);
  -- 433: as at sign-up (432), when no customer with this phone has the name
  -- exactly as typed, one whose name has the same words counts too
  -- (customer_names_match): in any order (as written, with a patronymic such
  -- as bin or s/o), with neighbouring words together or apart, whatever the
  -- case and punctuation, and leaving out a note in brackets.
  if cardinality(v_matches) = 0 then
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_matches
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_norm
       and public.customer_names_match(c.full_name, v_name);
    if cardinality(v_matches) > 0 then v_name_match := 'same_words'; end if;
  else
    v_name_match := 'exact';
  end if;
  v_match_count := cardinality(v_matches);
  -- 468 (the Owner, 24 Oct 2026): the phone and the email's inbox
  -- (customer_email_match_key, as 433 compares emails) both belong to just
  -- one customer in use: the form is theirs, as a phone and name match is,
  -- whatever name was typed. It takes their name parts, as a form staff
  -- attach does; the phone and email typed stay on it. Below: it fills none
  -- of their details, and when they already have a survey it waits for
  -- staff instead of being refused. The name comes first: one customer with
  -- it is the one. When it matched several, that one customer with both
  -- must be one of them (then it is a name match); one of another name does
  -- not take a form whose name points at others (it waits, as today).
  -- Several with both and no name match (a duplicate record): the form
  -- waits for staff, as below; with several namesakes, those with both wait
  -- beside them. An Owner or Manager may delete a duplicate from To match.
  -- An old record whose phone cannot be read does not have the phone, as in
  -- 433.
  if v_match_count <> 1 then
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_both
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_norm
       and public.customer_email_match_key(c.email) = public.customer_email_match_key(v_email);
    if cardinality(v_both) = 1 and (v_match_count = 0 or v_both[1] = any (v_matches)) then
      if v_match_count = 0 then v_name_match := 'phone_and_email'; end if;
      v_matches := v_both;
      v_match_count := 1;
    elsif cardinality(v_both) > 1 and v_match_count > 1 then
      select array_agg(distinct x order by x) into v_matches from unnest(v_matches || v_both) x;
      v_match_count := cardinality(v_matches);
    end if;
  end if;

  -- 433: the person sent this form before (this phone, this name as typed)
  -- and it was held: it still waits for staff, or it is now the survey of a
  -- customer in use (attached, made into a customer, or moved to the kept
  -- record by a merge). Refused as a customer's second survey is. One that
  -- was closed, or whose customer was deleted, is not the person's survey.
  if exists (select 1 from public.health_survey_holds h
               join public.health_surveys s on s.id = h.survey_id
               left join public.customers c on c.id = s.customer_id
              where h.typed_phone = v_norm
                -- 468 (the Owner, 24 Oct 2026): not a form that waits because
                -- the one customer with its phone and email already had a
                -- survey (below; such a form is never refused). Counting it
                -- would refuse a second form under the same name only when
                -- the customer had a survey before the first, and so tell.
                and h.reason <> 'phone_and_email_customer_has_survey'
                and (public.normalize_customer_match_name(h.typed_full_name) = public.normalize_customer_match_name(v_name)
                     or public.customer_names_match(h.typed_full_name, v_name))
                and ((h.resolved_at is null and s.customer_id is null)
                     or (s.customer_id is not null and c.deleted_at is null)
                     -- 419: or staff attached it and its answers went into the
                     -- record of a customer in use (Q10).
                     or (h.resolution = 'attached' and s.customer_id is null
                         and exists (select 1 from public.customers x
                                      where x.id = h.resolved_customer_id and x.deleted_at is null)))) then
    raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
  end if;

  if v_match_count > 1 then
    -- Legacy ambiguity: never attach private health data to a guessed record.
    -- 433: the form is kept and held for staff, who attach it to the right
    -- one of them; it used to be refused, and the person sent to staff.
    v_hold := 'several_name_matches';
    v_candidates := v_matches;

  elsif v_match_count = 1 then
    -- Existing customer (e.g. an affiliate-referral customer). Reuse them.
    v_cust_id := v_matches[1]; -- only after cardinality = 1
    v_matched := true;

    -- Already completed an initial survey? (by customer_id, and defensively by
    -- canonical phone for legacy surveys with a null customer_id).
    -- 419 (Q10, the Owner, 9 Oct 2026): a consultant's record the customer has
    -- not signed takes the form (health_survey_sign_into_record, below). Any
    -- other survey of theirs is their one survey, as before.
    select hs.id into v_into from public.health_surveys hs
     where hs.customer_id = v_cust_id and hs.source = 'consultant' and hs.signature_data is null;
    if exists (select 1 from public.health_surveys where customer_id = v_cust_id and id is distinct from v_into)
       or exists (select 1 from public.health_surveys
                   where customer_id is null
                     and public.normalize_customer_phone(phone) = v_norm
                     and public.normalize_customer_match_name(full_name) = public.normalize_customer_match_name(v_name)
                     -- 433: a form held for staff is not a legacy one: one still
                     -- waiting is refused above, and one an Owner or Manager
                     -- closed is no longer the person's survey.
                     and not exists (select 1 from public.health_survey_holds h
                                      where h.survey_id = health_surveys.id)) then
      if v_name_match is distinct from 'phone_and_email' then
        raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
      end if;
      -- 468 (the Owner, 24 Oct 2026): found by the phone and the email alone
      -- (the name picked no one), the form is not refused: it is kept with no
      -- customer and waits quietly under To match with them; the reply is
      -- the same as for any form, so it tells no one a survey exists. Staff
      -- decide (a new customer from it, or an Owner or Manager closes it).
      v_hold := 'phone_and_email_customer_has_survey';
      v_candidates := array[v_cust_id];
      v_cust_id := null; v_matched := false; v_into := null;
    end if;

    -- Fill ONLY currently-empty, safe fields. NEVER touch full_name, phone, or
    -- any referral attribution (referred_by / referred_at / referral_source /
    -- referral_code_used).
    -- 485 (the Owner, 2 Nov 2026): nor the email of a record that has a portal
    -- login or an affiliate record: 484's proof (d) takes a login whose
    -- verified email is its record's as proven, so a form must not put an
    -- email there. The form keeps the email typed; staff may copy it.
    update public.customers
       set email             = case when email is null
                                     and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
                                     and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
                                    then v_email else email end,
           date_of_birth     = coalesce(date_of_birth, nullif(p_payload->>'date_of_birth','')::date),
           gender            = coalesce(gender, v_gender),
           occupation        = coalesce(occupation, nullif(trim(p_payload->>'occupation'),'')),
           source_option_id  = coalesce(source_option_id, v_src.id),
           source_label      = coalesce(source_label, v_src.label),
           source_details    = coalesce(source_details, v_src_details),
           source_updated_at = case when source_option_id is null then now() else source_updated_at end,
           updated_at        = now()
     where id = v_cust_id
       -- 468 (the Owner, 24 Oct 2026): only when the name found them. A form
       -- found by the phone and the email alone fills none of the customer's
       -- details; the form keeps what was typed.
       and v_name_match is distinct from 'phone_and_email';

  else
    if exists(select 1 from public.health_surveys where customer_id is null
      and public.normalize_customer_phone(phone)=v_norm
      and public.normalize_customer_match_name(full_name)=public.normalize_customer_match_name(v_name)
      -- 433: a form held for staff is not a legacy one (see above).
      and not exists (select 1 from public.health_survey_holds h where h.survey_id = health_surveys.id)) then
      raise exception 'AMBIGUOUS_CUSTOMER_MATCH';
    end if;
    -- 433: no phone-plus-name match, but a customer in use has this phone, or
    -- this email's inbox (customer_email_match_key): the person may be them
    -- under another name, or someone sharing their phone or email. The form
    -- is kept and held for staff, who attach it or make a new customer from
    -- it (health_survey_holds); nothing is guessed. The email is not
    -- verified, so it never attaches a form by itself.
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_phone_holders
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_norm;
    v_email_key := public.customer_email_match_key(v_email);
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_email_holders
      from public.customers c
     where c.deleted_at is null and public.customer_email_match_key(c.email) = v_email_key;
    if cardinality(v_phone_holders) > 0 or cardinality(v_email_holders) > 0 then
      v_hold := case when cardinality(v_phone_holders) > 0 and cardinality(v_email_holders) > 0 then 'phone_and_email_in_use'
                     when cardinality(v_phone_holders) > 0 then 'phone_in_use'
                     else 'email_in_use' end;
      select coalesce(array_agg(distinct x order by x), '{}'::uuid[]) into v_candidates
        from unnest(v_phone_holders || v_email_holders) as x;
    else
    -- No phone-plus-name match: create a new customer subject to capacity.
    insert into public.customers (full_name, first_name, last_name, phone, email, date_of_birth, gender, occupation,
                                  source_option_id, source_label, source_details, source_updated_at)
    values (v_name, v_first, v_last, coalesce(v_norm, v_phone), v_email,
            nullif(p_payload->>'date_of_birth','')::date, v_gender,
            nullif(trim(p_payload->>'occupation'), ''),
            v_src.id, v_src.label, v_src_details, now())
    returning id into v_cust_id;
    v_created := true;
    end if;
  end if;

  if v_into is not null then
    -- 419 (Q10): the customer's own answers go into the consultant's record
    -- they had not signed; the consultant's work stays.
    v_form.survey_link_id := v_l.id;
    v_form.store_id := v_l.store_id;
    v_form.event_name := coalesce(nullif(trim(p_payload->>'event_name'),''), v_l.event_name);
    v_form.date_of_birth := nullif(p_payload->>'date_of_birth','')::date;
    v_form.age := nullif(p_payload->>'age','')::integer;
    v_form.sex := v_sex;
    v_form.phone := coalesce(v_norm, v_phone);
    v_form.email := v_email;
    v_form.occupation := nullif(trim(p_payload->>'occupation'),'');
    v_form.has_medical_condition := (p_payload->>'has_medical_condition')::boolean;
    v_form.drinks_alcohol := (p_payload->>'drinks_alcohol')::boolean;
    v_form.smokes := (p_payload->>'smokes')::boolean;
    v_form.on_treatment := (p_payload->>'on_treatment')::boolean;
    v_form.treatment_list := nullif(trim(p_payload->>'treatment_list'),'');
    v_form.others_text := nullif(trim(p_payload->>'others_text'),'');
    v_form.consent_newsletter_email := coalesce((p_payload->>'consent_newsletter_email')::boolean, false);
    v_form.consent_marketing_email := coalesce((p_payload->>'consent_marketing_email')::boolean, false);
    v_form.consent_marketing_sms := coalesce((p_payload->>'consent_marketing_sms')::boolean, false);
    v_form.consent_marketing_phone := coalesce((p_payload->>'consent_marketing_phone')::boolean, false);
    v_form.signature_data := p_payload->>'signature_data';
    v_form.signed_date := coalesce(nullif(p_payload->>'signed_date','')::date, public.sg_today());
    v_form.ip_address := nullif(p_payload->>'ip_address','');
    v_form.device_info := nullif(p_payload->>'device_info','');
    v_form.source_option_id := v_src.id;
    v_form.source_label := v_src.label;
    v_form.source_details := v_src_details;
    v_form.submitted_at := now();
    v_signed := public.health_survey_sign_into_record(v_into, v_form, p_symptoms, p_pdf_base64);
    v_id := v_into;
    v_no := v_signed->>'survey_no';
  else
    v_no := 'HS-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);

    -- 419 (CUSTOMERS-8): a form with a customer of its own (made just now) or
    -- none yet (held for staff) keeps the name parts as typed; a form for a
    -- customer found takes theirs (trg_survey_inherit_customer), as before.
    insert into public.health_surveys (
      survey_no, store_id, survey_link_id, customer_id, event_name,
      full_name, first_name, last_name, date_of_birth, age, sex, phone, email, occupation,
      has_medical_condition, drinks_alcohol, smokes, on_treatment, treatment_list, others_text,
      consent_newsletter_email, consent_marketing_email, consent_marketing_sms, consent_marketing_phone,
      signature_data, signed_date, ip_address, device_info,
      source_option_id, source_label, source_details)
    values (
      v_no, v_l.store_id, v_l.id, v_cust_id, coalesce(nullif(trim(p_payload->>'event_name'),''), v_l.event_name),
      v_name, case when v_created or v_cust_id is null then v_first end,
      case when v_created or v_cust_id is null then v_last end,
      nullif(p_payload->>'date_of_birth','')::date, nullif(p_payload->>'age','')::integer,
      v_sex, coalesce(v_norm, v_phone), v_email, nullif(trim(p_payload->>'occupation'),''),
      (p_payload->>'has_medical_condition')::boolean, (p_payload->>'drinks_alcohol')::boolean,
      (p_payload->>'smokes')::boolean, (p_payload->>'on_treatment')::boolean,
      nullif(trim(p_payload->>'treatment_list'),''), nullif(trim(p_payload->>'others_text'),''),
      coalesce((p_payload->>'consent_newsletter_email')::boolean, false),
      coalesce((p_payload->>'consent_marketing_email')::boolean, false),
      coalesce((p_payload->>'consent_marketing_sms')::boolean, false),
      coalesce((p_payload->>'consent_marketing_phone')::boolean, false),
      p_payload->>'signature_data',
      coalesce(nullif(p_payload->>'signed_date','')::date, public.sg_today()),
      nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''),
      v_src.id, v_src.label, v_src_details)
    returning id into v_id;

    if p_symptoms is not null then
      for v_sym in select * from jsonb_array_elements(p_symptoms) loop
        insert into public.health_survey_symptoms (survey_id, option_id, duration_text)
        values (v_id, (v_sym->>'option_id')::uuid, nullif(trim(v_sym->>'duration_text'),''))
        on conflict do nothing;
      end loop;
    end if;

    if p_pdf_base64 is not null and length(p_pdf_base64) > 0 then
      if length(p_pdf_base64) > 8000000 then raise exception 'The signed document is too large.'; end if;
      insert into public.health_survey_pdfs (survey_id, pdf_base64, byte_size)
      values (v_id, p_pdf_base64, length(p_pdf_base64));
      update public.health_surveys set pdf_url = 'stored' where id = v_id;
    end if;
  end if;

  -- 433: a held form waits for staff, with the customers it may belong to and
  -- the phone and name as typed.
  if v_hold is not null then
    insert into public.health_survey_holds (survey_id, reason, candidate_customer_ids,
                                            typed_full_name, typed_phone, typed_email)
    values (v_id, v_hold, coalesce(v_candidates, '{}'::uuid[]), v_name, v_norm, v_email);
  end if;

  insert into public.audit_logs (table_name, record_id, action, new_data, module, store_id, ip_address, device_info)
  values ('health_surveys', v_id, 'health_survey_submitted',
          jsonb_build_object('survey_no', v_no, 'customer_id', v_cust_id, 'source', 'public_qr',
                             'customer_source', v_src.label,
                             'customer_created', v_created, 'customer_matched', v_matched,
                             -- 433: held for staff, why, how the name matched, and
                             -- the name as typed.
                             'held_for_staff', v_hold is not null, 'hold_reason', v_hold,
                             'name_match', v_name_match, 'typed_name', v_name,
                             -- 468: how many customers in use had both the
                             -- phone and the email, when looked at (the name
                             -- matched none, or several).
                             'phone_and_email_customers', cardinality(v_both),
                             -- 419: into a consultant's record (Q10), and
                             -- whether that record was empty.
                             'signed_into_record', v_into is not null,
                             'record_was_empty', (v_signed->>'record_was_empty')::boolean),
          'health_survey', v_l.store_id,
          nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''));

  -- 433: the reply no longer says whether a customer was found or made (the
  -- Audit Log row above does): a form held for staff would otherwise tell
  -- anyone with the link whether a phone or email is a customer's. The page
  -- reads only survey_no.
  -- 419 (CUSTOMERS-16): the page could not build the signed PDF (it says why
  -- in pdf_error), so none is stored; staff see this row in the Audit Log.
  if p_pdf_base64 is null or length(p_pdf_base64) = 0 then
    insert into public.audit_logs (table_name, record_id, action, new_data, module, store_id, ip_address, device_info)
    values ('health_surveys', v_id, 'signed_pdf_missing',
            jsonb_build_object('survey_no', v_no, 'reason', left(nullif(trim(p_payload->>'pdf_error'), ''), 200)),
            'health_survey', v_l.store_id,
            nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''));
  end if;

  return jsonb_build_object('success', true, 'survey_no', v_no, 'survey_id', v_id);
end $function$
$d1$;
  c_def2 constant text :=
$d2$CREATE OR REPLACE FUNCTION public.event_web_fill_customer(p_customer_id uuid, p_person_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype; s public.event_web_settings%rowtype;
  v_src public.customer_source_options%rowtype;
  -- 485 (the Owner, 2 Nov 2026): the record has a portal login or an affiliate
  -- record, so the registration leaves its email as it is (484's proof (d)
  -- reads it); the registration keeps the email typed.
  v_keep_email boolean;
begin
  select * into p from public.event_registration_people where id = p_person_id;
  select * into s from public.event_web_settings where event_id = p.event_id;
  select * into v_src from public.customer_source_options where id = s.source_option_id and is_active;
  v_keep_email := exists (select 1 from public.affiliate_accounts a where a.customer_id = p_customer_id)
                  or exists (select 1 from public.customer_affiliates f where f.customer_id = p_customer_id);
  update public.customers
     set email             = case when v_keep_email then email
                                  else coalesce(nullif(btrim(email), ''), nullif(btrim(p.email), '')) end,
         source_option_id  = coalesce(source_option_id, v_src.id),
         source_label      = case when source_option_id is null and v_src.id is not null then v_src.label else source_label end,
         source_details    = case when source_option_id is null and v_src.id is not null then s.source_details else source_details end,
         source_updated_at = case when source_option_id is null and v_src.id is not null then now() else source_updated_at end,
         updated_at        = now()
   where id = p_customer_id
     and ((not v_keep_email and nullif(btrim(email), '') is null and nullif(btrim(p.email), '') is not null)
          or (source_option_id is null and v_src.id is not null));
end $function$
$d2$;
  c_def3 constant text :=
$d3$CREATE OR REPLACE FUNCTION public.attach_held_health_survey(p_survey_id uuid, p_customer_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_h public.health_survey_holds%rowtype; v_s public.health_surveys%rowtype; v_c public.customers%rowtype;
        v_gender public.customer_gender; v_existing text;
        -- 419: the customer's unsigned consultant record that takes the form (Q10).
        v_into uuid; v_syms jsonb; v_pdf text; v_signed jsonb;
begin
  -- 433: staff attach a QR form waiting for them to the customer it belongs
  -- to (the owner, 16 Oct 2026: any staff). The customer's empty details are
  -- filled from the form, never their name or phone, as the form does itself
  -- when it finds the customer. Then the form is attached and carries the
  -- customer's name, as a survey does whenever its customer's name is edited
  -- (trg_sync_customer_to_surveys), so that saving its details never renames
  -- the customer; the phone and email typed stay on it (TikTok attendance
  -- reads them). What was typed is kept in the hold and the Audit Log row. A
  -- customer has one health survey.
  perform public.require_active_staff('{owner,admin,manager,staff}');
  if p_note is null or btrim(p_note) = '' then
    raise exception 'Add a short note on how you confirmed this is the same person.'; end if;

  select * into v_h from public.health_survey_holds where survey_id = p_survey_id for update;
  if not found then raise exception 'This form is not waiting to be matched.'; end if;
  if v_h.resolved_at is not null then raise exception 'This form has already been dealt with.'; end if;
  select * into v_s from public.health_surveys where id = p_survey_id for update;
  if v_s.customer_id is not null then raise exception 'This form is already attached to a customer.'; end if;

  select * into v_c from public.customers where id = p_customer_id for update;
  if not found or v_c.deleted_at is not null then raise exception 'Customer not found.'; end if;
  -- 419 (Q10, the Owner, 9 Oct 2026): a consultant's record the customer has
  -- not signed takes the form's answers (health_survey_sign_into_record). Any
  -- other survey is their one survey, as before.
  select x.survey_no, case when x.source = 'consultant' and x.signature_data is null then x.id end
    into v_existing, v_into
    from public.health_surveys x where x.customer_id = v_c.id;
  if v_existing is not null and v_into is null then
    raise exception 'This customer already has a health survey (%). A customer can have only one.', v_existing; end if;

  v_gender := case when v_s.sex in ('male', 'female') then v_s.sex::public.customer_gender end;
  -- 485 (the Owner, 2 Nov 2026): never the email of a record that has a portal
  -- login or an affiliate record. Attaching decides whose form this is, not
  -- whose login, and 484's proof (d) reads that email; staff add it in Edit
  -- customer when it is theirs. The form keeps the email typed.
  update public.customers
     set email             = case when email is null
                                   and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
                                   and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
                                  then nullif(btrim(v_s.email), '') else email end,
         date_of_birth     = coalesce(date_of_birth, v_s.date_of_birth),
         gender            = coalesce(gender, v_gender),
         occupation        = coalesce(occupation, nullif(btrim(v_s.occupation), '')),
         source_option_id  = coalesce(source_option_id, v_s.source_option_id),
         source_label      = coalesce(source_label, v_s.source_label),
         source_details    = coalesce(source_details, v_s.source_details),
         source_updated_at = case when source_option_id is null and v_s.source_option_id is not null
                                  then now() else source_updated_at end,
         updated_at        = now()
   where id = v_c.id;
  -- The customer's name parts exactly as they are (a one-word name has no
  -- last name), so the form's whole name is the customer's; a customer with
  -- no name at all leaves the form's.
  if v_into is not null then
    -- 419 (Q10): the form's answers, symptoms and signed PDF go into the
    -- customer's record. The form itself is kept as it was sent, with no
    -- customer; its hold below says it was attached, and to whom.
    select coalesce(jsonb_agg(jsonb_build_object('option_id', y.option_id, 'duration_text', y.duration_text)), '[]'::jsonb)
      into v_syms
      from public.health_survey_symptoms y where y.survey_id = v_s.id;
    select p.pdf_base64 into v_pdf from public.health_survey_pdfs p where p.survey_id = v_s.id;
    v_signed := public.health_survey_sign_into_record(v_into, v_s, v_syms, v_pdf);
  else
    update public.health_surveys set
      customer_id = v_c.id,
      first_name  = case when nullif(trim(coalesce(v_c.full_name, '')), '') is not null then v_c.first_name else first_name end,
      last_name   = case when nullif(trim(coalesce(v_c.full_name, '')), '') is not null then v_c.last_name else last_name end,
      full_name   = coalesce(nullif(trim(coalesce(v_c.full_name, '')), ''), full_name)
     where id = v_s.id;
  end if;
  update public.health_survey_holds
     set resolved_at = now(), resolved_by = auth.uid(), resolution = 'attached',
         resolved_customer_id = v_c.id, resolution_note = btrim(p_note)
   where survey_id = v_s.id;

  perform public.write_audit_ex('health_surveys', v_s.id, 'health_survey_matched',
    jsonb_build_object('typed_name', v_s.full_name, 'typed_phone', v_s.phone, 'typed_email', v_s.email),
    jsonb_build_object('customer_id', v_c.id, 'survey_no', v_s.survey_no, 'hold_reason', v_h.reason,
                       'suggested_customer', v_c.id = any (v_h.candidate_customer_ids),
                       -- 419: the record its answers went into (Q10).
                       'signed_into_survey_no', v_signed->>'survey_no'),
    'health_survey', btrim(p_note), v_s.store_id);
  return jsonb_build_object('ok', true, 'customer_id', v_c.id, 'survey_no', v_s.survey_no,
                            'signed_into_survey_no', v_signed->>'survey_no');
end $function$
$d3$;

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v_role text := current_user;
  v text; v_md5 text[] := '{}'; v_oid regprocedure; v_state text;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_ph text[]; t_store uuid; t_src uuid; t_uid uuid; t_srr text; t_c uuid[] := '{}';
  t_id uuid; t_ev uuid; t_reg uuid; t_ans jsonb; t_err text; t_got text; t_held uuid[] := '{}';
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──
  if md5(c_def1) <> c_after[1] or md5(c_def2) <> c_after[2] or md5(c_def3) <> c_after[3] then
    raise exception '485: the texts are not the tested ones (md5 %, %, %)', md5(c_def1), md5(c_def2), md5(c_def3); end if;
  for i in 1 .. 3 loop
    v_oid := to_regprocedure('public.' || c_sig[i]);
    if v_oid is null then raise exception '485: public.% is missing', c_sig[i]; end if;
    v_md5 := v_md5 || md5(pg_get_functiondef(v_oid));
    select string_agg(p.oid::regprocedure::text, ', ') into v
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = c_name[i] and p.oid <> v_oid;
    if v is not null then raise exception '485: another function takes the name of public.%: %', c_sig[i], v; end if;
    if (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid)
       is distinct from c_acl[i] then
      raise exception '485: the grants of public.% are not as read on 2 Nov 2026', c_sig[i]; end if;
  end loop;
  -- All BEFORE (replace all three) or all AFTER ("already this version"); anything else is refused.
  v_state := case when v_md5 = c_before then 'before' when v_md5 = c_after then 'after' end;
  if v_state is null then
    raise exception '485: public.% (md5 %), public.% (md5 %) and public.% (md5 %) are not all production''s versions of 2 Nov 2026 nor all this file''s. Re-read them and re-test before applying.',
      c_sig[1], v_md5[1], c_sig[2], v_md5[2], c_sig[3], v_md5[3]; end if;
  -- The columns the new lines read.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customers', 'id', 'uuid'), ('customers', 'email', 'text'), ('affiliate_accounts', 'customer_id', 'uuid'),
                 ('customer_affiliates', 'customer_id', 'uuid'), ('event_registration_people', 'email', 'text'),
                 ('health_surveys', 'email', 'text')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '485: these columns are missing or not as read on 2 Nov 2026: %', v; end if;

  -- ── Change ──
  if v_state = 'before' then
    execute c_def1;
    execute c_def2;
    execute c_def3;
    raise notice '485: public.%, public.% and public.% replaced (a form, or staff attaching one, no longer fills the email of a record with a portal login or an affiliate record)',
      c_sig[1], c_sig[2], c_sig[3];
  else
    raise notice '485: public.%, public.% and public.% are already this version; left alone', c_sig[1], c_sig[2], c_sig[3];
  end if;

  -- ── Afterwards ──
  for i in 1 .. 3 loop
    v_oid := to_regprocedure('public.' || c_sig[i]);
    if v_oid is null or md5(pg_get_functiondef(v_oid)) <> c_after[i] then
      raise exception '485: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid)
       is distinct from c_acl[i] then
      raise exception '485: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ──
  begin
    -- As the server (no request).
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- Six fictional phones in a row (+61 2 5550 nnnn) that no customer, in use or deleted, holds: range scans of
    -- the partial phone indexes, as 482's.
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '485: the self-test found no free fictional phones'; end if;
    t_ph := array(select '+6125550' || lpad((t_base + n)::text, 4, '0') from generate_series(0, 5) n);
    select s.id into t_store from public.stores s where s.deleted_at is null order by s.id limit 1;
    if t_store is null then raise exception '485: the self-test found no store in use'; end if;
    insert into public.customer_source_options (label) values ('485 Check ' || t_sfx) returning id into t_src;
    insert into public.survey_links (token, store_id) values ('485chk-' || t_sfx, t_store);
    -- Three records with no email: an affiliate's (an affiliate record, no login), a portal login's (no affiliate
    -- record) and a plain one. The fourth phone is someone new.
    insert into public.customers (full_name, phone) values ('485 Check Affiliate', t_ph[1]) returning id into t_id;
    t_c := t_c || t_id;
    insert into public.customer_affiliates (customer_id) values (t_id);
    insert into public.customers (full_name, phone) values ('485 Check Login', t_ph[2]) returning id into t_id;
    t_c := t_c || t_id;
    insert into auth.users (id, email) values (gen_random_uuid(), '485chk-login-' || t_sfx || '@example.invalid') returning id into t_uid;
    -- The portal account with triggers off for this statement only (its trigger would queue a welcome WhatsApp and
    -- take a number from the outbox's sequence, which an undone block does not give back).
    t_srr := current_setting('session_replication_role');
    set local session_replication_role = replica;
    insert into public.affiliate_accounts (auth_user_id, customer_id) values (t_uid, t_id);
    execute format('set local session_replication_role = %L', t_srr);
    insert into public.customers (full_name, phone) values ('485 Check Plain', t_ph[3]) returning id into t_id;
    t_c := t_c || t_id;

    -- The QR form, signed out as the public page sends it, for each of the three by their name and phone, then for
    -- someone new.
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    begin
      execute 'set local role anon';
      for i in 1 .. 4 loop
        t_ans := public.submit_health_survey('485chk-' || t_sfx, jsonb_build_object(
                   'first_name', '485 Check', 'last_name', (array['Affiliate', 'Login', 'Plain', 'New'])[i], 'phone', t_ph[i],
                   'email', '485chk-q' || i || '-' || t_sfx || '@example.invalid', 'signature_data', 'data:image/png;base64,AAAA',
                   'source_option_id', t_src, 'occupation', '485 Check'), null, null);
        if (t_ans ->> 'success') is distinct from 'true' then raise exception 'form % answered %', i, t_ans; end if;
      end loop;
    exception when others then t_err := sqlstate || ' ' || sqlerrm;
    end;
    execute format('set local role %I', v_role);
    perform set_config('request.jwt.claims', '', true);
    if t_err is not null then raise exception '485: the self-test''s QR forms failed: %', t_err; end if;
    -- The affiliate's and the login's records keep no email and take the rest; the plain record and someone new
    -- take the email typed; each form keeps the email typed.
    select string_agg(c.full_name || ': ' || coalesce(c.email, '-') || ', ' || coalesce(c.occupation, '-'), ' | ' order by c.full_name)
      into t_got from public.customers c where c.deleted_at is null and c.phone = any (t_ph);
    if t_got is distinct from '485 Check Affiliate: -, 485 Check | 485 Check Login: -, 485 Check | 485 Check New: 485chk-q4-'
         || t_sfx || '@example.invalid, 485 Check | 485 Check Plain: 485chk-q3-' || t_sfx || '@example.invalid, 485 Check'
       or (select count(*) from public.health_surveys s
            where s.phone = any (t_ph) and s.email = '485chk-q' || array_position(t_ph, s.phone) || '-' || t_sfx || '@example.invalid') <> 4 then
      raise exception '485: the self-test''s QR forms filled: %', t_got; end if;

    -- The event website's registration, as its server, for the same three (the plain record's email emptied again;
    -- the email typed with spaces around it).
    update public.customers set email = null where id = t_c[3];
    insert into public.events (name) values ('485 Check ' || t_sfx) returning id into t_ev;
    insert into public.event_registrations (event_id, registration_id, people_count, people_md5)
      values (t_ev, 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(t_sfx), 3, md5(t_sfx)) returning id into t_reg;
    for i in 1 .. 3 loop
      insert into public.event_registration_people (registration_ref, event_id, position, first_name, full_name, phone, phone_norm,
             days, match, upgrade_token, email, customer_id)
      values (t_reg, t_ev, i, '485 Check', '485 Check ' || (array['Affiliate', 'Login', 'Plain'])[i], t_ph[i], t_ph[i],
              array[public.sg_today()], 'exact', 'vip_' || translate(substr(md5(t_sfx || i) || md5(i || t_sfx), 1, 26), '0189', 'wxyz'),
              ' 485chk-e' || i || '-' || t_sfx || '@example.invalid ', t_c[i])
      returning id into t_id;
      perform public.event_web_fill_customer(t_c[i], t_id);
    end loop;
    select string_agg(c.full_name || ': ' || coalesce(c.email, '-'), ' | ' order by c.full_name) into t_got
      from public.customers c where c.id = any (t_c);
    if t_got is distinct from '485 Check Affiliate: - | 485 Check Login: - | 485 Check Plain: 485chk-e3-' || t_sfx || '@example.invalid' then
      raise exception '485: the self-test''s registrations filled: %', t_got; end if;

    -- Staff attaching a held QR form (as the server, which the staff check lets through): two more records with
    -- no email and no survey, an affiliate's and a plain one; a form under another name with each one's phone
    -- waits for staff (433: the phone is a customer's), and is attached to that record.
    insert into public.customers (full_name, phone) values ('485 Check Held Affiliate', t_ph[5]) returning id into t_id;
    t_c := t_c || t_id;
    insert into public.customer_affiliates (customer_id) values (t_id);
    insert into public.customers (full_name, phone) values ('485 Check Held Plain', t_ph[6]) returning id into t_id;
    t_c := t_c || t_id;
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    begin
      execute 'set local role anon';
      for i in 1 .. 2 loop
        t_ans := public.submit_health_survey('485chk-' || t_sfx, jsonb_build_object(
                   'first_name', '485 Held', 'last_name', (array['One', 'Two'])[i], 'phone', t_ph[4 + i],
                   'email', '485chk-h' || i || '-' || t_sfx || '@example.invalid', 'signature_data', 'data:image/png;base64,AAAA',
                   'source_option_id', t_src, 'occupation', '485 Check'), null, null);
        if (t_ans ->> 'success') is distinct from 'true' then raise exception 'held form % answered %', i, t_ans; end if;
        t_held := t_held || (t_ans ->> 'survey_id')::uuid;
      end loop;
    exception when others then t_err := sqlstate || ' ' || sqlerrm;
    end;
    execute format('set local role %I', v_role);
    perform set_config('request.jwt.claims', '', true);
    if t_err is not null then raise exception '485: the self-test''s held QR forms failed: %', t_err; end if;
    if (select count(*) from public.health_survey_holds h where h.survey_id = any (t_held) and h.resolved_at is null) <> 2 then
      raise exception '485: the self-test''s forms under another name did not wait for staff'; end if;
    perform public.attach_held_health_survey(t_held[1], t_c[4], '485 check');
    perform public.attach_held_health_survey(t_held[2], t_c[5], '485 check');
    select string_agg(c.full_name || ': ' || coalesce(c.email, '-') || ', ' || coalesce(c.occupation, '-'), ' | ' order by c.full_name)
      into t_got from public.customers c where c.id in (t_c[4], t_c[5]);
    if t_got is distinct from '485 Check Held Affiliate: -, 485 Check | 485 Check Held Plain: 485chk-h2-' || t_sfx || '@example.invalid, 485 Check' then
      raise exception '485: the self-test''s staff attach filled: %', t_got; end if;

    raise exception using errcode = 'P0485', message = '485: self-test done, undone';
  exception when sqlstate 'P0485' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
end $mig$;
