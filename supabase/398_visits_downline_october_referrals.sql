-- 398_visits_downline_october_referrals.sql
--
-- WHAT WAS MISSING (found 6 Oct 2026)
--
--   * Nothing said whether a customer had visited the centre. A health survey
--     exists for 184 customers, but it is made three ways: the public form
--     through one of the centre's own QR links, the public form through an
--     event's link (a roadshow, a health talk: 17 surveys), and the Surveys
--     page, which creates an empty "consultant" survey the moment staff open
--     a customer who has none (SurveysPage, upsert_consultant_survey with
--     every field null).
--   * customers.referred_at (when a friend was referred) is written only by
--     the sign-up link (affiliate_referral_signup, /r/:code). Staff set
--     referred_by without a date: the Customers page's Add and Edit (a direct
--     write to the table), quick create (create_customer_quick's
--     p_referred_by) and Correct Referrer (reassign_customer_referrer). 50 of
--     the 72 live referral links have no date.
--   * referrer_downline (the Commissions page's Referrers tab) checks no role.
--     It is SECURITY DEFINER and granted to every signed-in login, an
--     affiliate portal login included, so anyone signed in could list any
--     referrer's whole downline with names, phones and spend.
--   * search_customers (the Customers page's list and its Excel exports)
--     checks no role either: an affiliate portal login could page through
--     every customer's name, phone and email, which the customers table's own
--     read policy refuses it. It now also returns a health-survey date, so it
--     follows that policy.
--   * There was no downline view with visits and no October promotion.
--
-- THE RULES (the Owner, 6 Oct 2026, final)
--
--   1. "Visited the centre": the customer (the survey's customer_id) has a
--      health survey that EITHER was submitted through the public form via a
--      survey link WITHOUT an event name (the centre's own QR link) OR is a
--      staff-filled (consultant) survey with something written on it: an
--      answer, a consultant note with text or an attachment, or an attached
--      file. Not counted: the empty consultant records the Surveys page
--      creates, and a survey through an event's link (roadshow, health talk)
--      by itself; a customer surveyed at an event counts from the later day a
--      consultant note or file is written for them. One rule, in one
--      function, for every screen.
--   2. "First visit date": the date of that survey (public form: its
--      signed_date, else the Singapore date it was submitted; consultant: the
--      day its first answer, note or file was written, below; event survey:
--      the later day of its first note or file). The Customers page filters
--      on Visited (All / Visited / Not visited) and on the first visit date
--      (from - to), and its list and Excel exports show the first visit date.
--   3. The referral date is recorded from now on: whenever referred_by is set
--      or changed, by any path, referred_at becomes now() unless that path
--      sets it itself (the sign-up link keeps its own). Older links without a
--      date use customers.created_at in every calculation; no data is
--      backfilled.
--   4. A downline view, Owner/Manager only: Tier 1 and Tier 2, with name,
--      phone, joined (the referral date, else created), visited (yes/no) and
--      first visit date; on the Customers page and the Affiliates page.
--   5. The October referral promotion (reusable for a later month): a Tier 1
--      friend referred in the window (coalesce(referred_at, created_at), 1 to
--      31 Oct 2026, Singapore time) whose first qualifying visit is in the
--      same window counts for their referrer (an affiliate or a plain
--      customer). Tiers 10 / 20 / 50 / 80; the reward is for the highest tier
--      reached only and is given after the window ends. The report lists
--      referrers with their count, tier reached, next tier and the friends
--      counted, and is "provisional" until the window ends. An Owner or
--      Manager marks the reward given: the products, quantities and the store
--      they come from. That records the reward and takes the products out of
--      the store's stock as a stock use ("October referral reward - <name>"),
--      in one transaction; one reward per referrer per promotion.
--   6. The affiliate portal's network page shows the signed-in affiliate's
--      own progress: friends counted so far and the next tier, nobody else's
--      data.
--
-- WHAT "HAS ANSWERS" MEANS (rule 1)
--
--   As the Owner's rule gives it, from the survey's own record and its
--   symptoms. A consultant survey has answers when any of these holds:
--     * a text answer on the survey is not blank: acidity_result,
--       remarks_condition, remarks_recommendation, health_goals (the Survey
--       window's Save Review), treatment_list, others_text;
--     * any of the four yes/no questions has an answer (has_medical_condition,
--       drinks_alcohol, smokes, on_treatment not null; the Surveys page's
--       empty record leaves them null);
--     * it has a symptom (health_survey_symptoms).
--   And beside the answers (the Owner's decision below): a consultant note
--   (consultant_notes) with text in any of its four fields or a non-empty
--   attachments list, or an attached file (health_survey_attachments).
--   Generated PDFs of signed forms (health_survey_pdfs) are not evidence.
--   Production, read on 6 Oct 2026: 86 consultant surveys, 35 with answers
--   on the survey, 79 counting notes and files, 7 empty; 160 customers
--   visited (81 through the centre's own links, 79 consultant).
--   The public form's link is read from survey_links, not the survey's own
--   event_name: the public form lets anyone type an optional "Event" on the
--   centre's link, and 7 surveys through the centre's links carry such text
--   ("Facebook", "NA", "Ads 2026"); they are centre visits.
--
-- WHEN A CONSULTANT'S SURVEY WAS THE VISIT (rule 2)
--
--   The Surveys page creates the consultant record the moment staff open a
--   customer who has none, which can be days before the consultation; the
--   answers are saved later through the Survey window. So the visit is the
--   Singapore day the answers were first saved, read from the survey's own
--   audit rows: the first Save Review that wrote an answer
--   (health_survey_reviewed, for the review answers) and the first save of
--   its particulars (survey_particulars_edited, for the yes/no answers,
--   treatment_list, others_text and symptoms), whichever of the two holds
--   answers now, the earlier. A survey without such a row (answers written
--   when it was made) is dated the day it was made, as before; a date is
--   never earlier than that day. In production today every consultant
--   survey with answers was answered the day it was made (0 dated later), so
--   the dates are the Owner's "Singapore date it was created". (A save of
--   particulars that held no answer yet, before the answers came, dates it
--   to that save; never earlier than the record.) A note or a file dates it
--   too: the earliest of the answers' day, the first note and the first file,
--   never earlier than the day the record was made.
--
-- DECIDED BY THE OWNER WHILE THIS WAS BUILT (6 Oct 2026)
--
--   * Consultant notes with text or attachments, and attached files, count
--     as a consultant survey's answers (79 answered, 7 empty, 160 customers
--     who visited, read on 6 Oct 2026). The Survey window's "Submit as Note"
--     writes only a note, and the window clears its fields after every save,
--     so a second Save Review in the same window writes blanks over the
--     survey's review answers: many consultations are recorded as notes.
--   * A customer surveyed through an event's link counts from the later day
--     a consultant note or file is written for them (17 such surveys; none
--     has one after the event day yet).
--
-- STILL OPEN
--
--   * A friend counts when referral and first visit are both in the window,
--     in either order (as the rule says): a staff login that sets a referrer
--     on a customer with no referrer who already visited this month makes
--     them count, dated the day the referrer was set.
--
-- WHAT THIS DOES
--
--   * customer_centre_visits(): rule 1 and 2, the only place they are
--     written. One row per customer who visited: the first visit date, the
--     survey and whether it was the centre's link, a consultant, or an
--     event's survey followed by a centre note or file. Internal
--     (339); everything below reads it.
--   * tg_customers_referral_date(), trigger trg_customers_referral_date,
--     before insert or update of referred_by, referred_at on customers: rule
--     3. Every path is covered without touching it: the Customers page's Add
--     and Edit, quick create, Correct Referrer, whatever comes later.
--     referred_at now decides who counts in a promotion (and so which
--     rewards take stock out), and the customers table lets any staff login
--     insert and update rows through the API, so a login writing the table
--     directly (the API roles anon and authenticated) never sets the date
--     itself: a new or changed referrer is dated now(), and any referred_at
--     it sends is otherwise ignored (the row keeps the date it had; a new row
--     without a referrer has none). Only the database's own functions, which
--     run as their owner, may write a date of their own (the sign-up link
--     writes now(); a merge keeps each moved friend's date, below). For them
--     too, a new customer with a referrer and no referred_at, or a change of
--     referrer that leaves referred_at as it was, gets now(). Removing a
--     referrer leaves referred_at alone; it is never read without one.
--   * merge_customer_records: a merge moves the duplicate's friends to the
--     record kept, through reassign_customer_referrer. That is the same
--     referral, made when it was made, so it keeps each friend's date (the
--     transaction setting energia.keep_referral_date, set around that loop
--     only). A friend without a date keeps none and falls back to created_at.
--   * search_customers gains p_visited ('visited', 'not_visited', anything
--     else: all), p_visit_from and p_visit_to (the first visit date, both
--     ends included; a date excludes those who never visited) and returns
--     first_visit_on. The result type changes, so it is dropped and created;
--     the four-argument version is dropped in the same transaction and does
--     not come back (the new arguments have defaults, so the page now live,
--     which passes four, keeps working). It returns rows only to a staff
--     login (current_user_role() not null, the customers table's own read
--     policy); anyone else gets none.
--   * customer_downline_visits(customer): rule 4, Owner/Manager only.
--   * referrer_downline: the same rows, now only for an Owner, a Manager or
--     an Admin (affiliate_payout_access(), as referrer_earnings beside it and
--     referrer_list, which calls it, on the same Referrers tab; Admins open
--     that tab too). Staff, inventory managers and affiliate logins are
--     refused.
--   * referral_campaigns (the promotion: code, title, the stock-use reason,
--     the window, the tiers), seeded with 2026-10, "October referral
--     promotion", 1 to 31 Oct 2026, tiers 10/20/50/80. A later month is one
--     more row.
--   * referral_campaign_rewards and referral_campaign_reward_items: the
--     reward given (promotion, referrer, tier, friends counted, store, note,
--     who and when; each product, quantity and the stock use it made). One
--     reward per referrer per promotion (a unique index over those not
--     undone). Row level security on, no policies, no grants: only the
--     functions below read or write them.
--   * referral_campaign_friends(promotion): rule 5's counting, in one place:
--     every Tier 1 friend referred in the window, their first visit, and
--     whether they count. Internal.
--   * referral_campaign_standing(tiers, count): the highest tier reached, the
--     next tier and how many more to it. Internal.
--   * referral_campaign_report(promotion): the report, Owner/Manager only.
--   * give_referral_campaign_reward(...): marks the reward given, Owner or
--     Manager, only after the window has ended, for the highest tier reached;
--     takes each product out of the store's stock through record_stock_use
--     (its stock check, its store access check, its movement and audit), and
--     records the reward, all in one transaction.
--   * void_referral_campaign_reward(...): the correction path, the Owner
--     alone, with a reason: the reward is marked undone (kept, not deleted)
--     and, unless told otherwise, its products go back into the store's
--     stock with a movement. The reward can then be marked again.
--   * affiliate_portal_campaign_progress(): rule 6, for the signed-in
--     affiliate only (current_affiliate_customer_id()); counts and tiers,
--     no names.
--
-- NOT CHANGED
--
--   * No referral date is backfilled; no survey, customer or stock row is
--     changed. The 50 links without a date keep none.
--   * affiliate_referral_signup, create_customer_quick,
--     reassign_customer_referrer and the Customers page write referred_by as
--     before; the trigger dates them.
--   * affiliate_portal_network and affiliate_admin_directory are unchanged;
--     the portal's progress is a function of its own.
--   * referrer_list (the Referrers tab's list) is unchanged. It already
--     returns rows only when affiliate_payout_access() (a one-time filter, so
--     for anyone else nothing below it runs), and it calls referrer_downline
--     for each referrer's downline count: that is why referrer_downline checks
--     the same affiliate_payout_access() rather than Owner/Manager alone, so
--     an Admin's Referrers tab keeps working.
--   * No survey function changes: the Surveys page still creates an empty
--     consultant record when staff open a customer (it does not count), and
--     the Survey window still clears its fields after saving.
--   * Re-running 83_customer_search_performance.sql would bring the old
--     four-argument search_customers back beside the new one;
--     scripts/permissions/tests/function-grants.sql now fails if it is back.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block),
-- so it is atomic however it is run. Every guard and anchor is checked, and
-- every patched text built, before anything is installed. md5 of
-- pg_get_functiondef of each function patched or depended on must be the
-- production version read on 6 Oct 2026 (BEFORE), or already this
-- migration's version (AFTER), which is left alone so a re-run changes
-- nothing. A new function that exists with any other text refuses. The one
-- anchor must match exactly once. Patches are executed as CREATE OR REPLACE,
-- which keeps owner and grants; search_customers is dropped and created
-- (its result type changes) and granted again as it was. New internal
-- functions are revoked from public, anon and authenticated and granted to
-- service_role (339); the functions the pages call are granted to
-- authenticated and check the role themselves. Tables, the index, the trigger
-- and the promotion row are added only if missing; a trigger of that name
-- with another definition refuses. After installing, every function must
-- have its AFTER md5 and the grants are checked.
--
-- BEFORE (production, 6 Oct 2026, md5 of pg_get_functiondef):
--   search_customers(text,text,integer,integer)              7d9557259ab9473c0407b9eeb4493e1c  (dropped)
--   referrer_downline(uuid)                                  8a471732e7cfa41d73b9aa581c837c6a
--   merge_customer_records(uuid,uuid,text,uuid)              955179afeac18bbfe2218079258669c9
--   (called, not changed)
--   record_stock_use(text,uuid,uuid,integer,text,text)       db278faba262b0a3801944cd821a62fd
--   reassign_customer_referrer(uuid,uuid,text)               9b32f3bef5b4f17897aae637e343c208
-- AFTER (for later guards):
--   search_customers(text,text,integer,integer,text,date,date)
--                                                            df63c717eab1825017e2567679f3e135
--   referrer_downline(uuid)                                  e471bc0a0107bc1f70e8c01eea2e74d8
--   merge_customer_records(uuid,uuid,text,uuid)              a09b99d88585b5b3ab68f081fcdf01c8
--   customer_centre_visits()                                 05b4a9bb5fb955f4c00b62e4966c96d2
--   tg_customers_referral_date()                             5ea2010a7b31efd4db32474723f814f6
--   customer_downline_visits(uuid)                           1125dc56d3964c4b54a61ce88448ad65
--   referral_campaign_friends(uuid)                          6e88ab96e57e661d8a06eabb41e65874
--   referral_campaign_standing(integer[],integer)            43e8860ba8fade528ded701cfbeea12f
--   referral_campaign_report(text)                           b791ae0aa41975da55a66fc488df64cb
--   give_referral_campaign_reward(text,uuid,uuid,jsonb,text) db5bae60bc6bf65d2ae206a031ff62eb
--   void_referral_campaign_reward(uuid,text,boolean)         23bf34d722341b1811f5efe53a2d1d08
--   affiliate_portal_campaign_progress()                     7548c77bb887aec7227540ef15a0f14b
--
-- DEPLOY ORDER: 398, then the pages. The page now live keeps working with
-- 398 (search_customers' new arguments have defaults; referrer_downline
-- answers an Owner, Manager or Admin as before).
--
-- Test: scripts/referrals/tests/visits-and-october.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New functions ──────────────────────────────────────────────────────────
  c_visits_def constant text := $def$
create or replace function public.customer_centre_visits()
returns table(customer_id uuid, first_visit_on date, survey_id uuid, visit_kind text)
language sql
stable
security definer
set search_path = public
as $fn$
  -- 398: THE rule for "visited the centre" and its date (the Owner, 6 Oct
  -- 2026). Every screen and report reads it from here, nowhere else.
  -- A customer visited when one of their health surveys
  --   (1) came through the public form via one of the centre's own links (a
  --       survey link with no event name), dated its signed_date, else the
  --       Singapore date it was submitted;
  --   (2) is a consultant's survey with something written on it: an answer on
  --       the survey itself (a text answer or a Save Review answer, a yes/no
  --       answer, a symptom), a consultant note with text or an attachment,
  --       or an attached file. The empty record the Surveys page creates when
  --       staff open a customer has none of these. It is dated the Singapore
  --       day the first of them was written: the first Save Review that wrote
  --       an answer (audit health_survey_reviewed) or the first save of its
  --       particulars (audit survey_particulars_edited) for the answers it
  --       holds now, the first such note, the first file; never before the
  --       day the record was made; or
  --   (3) came through an event's link (a roadshow, a health talk), which is
  --       not a centre visit itself, and later gained a consultant note with
  --       text or an attachment, or an attached file, on a later Singapore day
  --       than the survey: that later day is the visit (staff record those at
  --       the centre).
  -- One row per customer: the earliest such survey.
  with s as (
    select hs.id, hs.customer_id, hs.source, hs.submitted_at,
           (hs.submitted_at at time zone 'Asia/Singapore')::date as made_on,
           coalesce(hs.signed_date, (hs.submitted_at at time zone 'Asia/Singapore')::date) as form_on,
           hs.source = 'public_form' and nullif(btrim(sl.event_name), '') is not null as event_link,
           coalesce(nullif(btrim(hs.acidity_result), ''), nullif(btrim(hs.remarks_condition), ''),
                    nullif(btrim(hs.remarks_recommendation), ''), nullif(btrim(hs.health_goals), '')) is not null
             as review_answer,
           coalesce(nullif(btrim(hs.treatment_list), ''), nullif(btrim(hs.others_text), '')) is not null
             or hs.has_medical_condition is not null or hs.drinks_alcohol is not null
             or hs.smokes is not null or hs.on_treatment is not null
             or exists (select 1 from public.health_survey_symptoms y where y.survey_id = hs.id)
             as particulars_answer
      from public.health_surveys hs
      left join public.survey_links sl on sl.id = hs.survey_link_id
     where hs.customer_id is not null
       and ((hs.source = 'public_form' and sl.id is not null) or hs.source = 'consultant')
  ),
  w as (
    -- What staff wrote beside a survey, by Singapore day: consultant notes
    -- with text or an attachment, and attached files.
    select n.survey_id, (n.created_at at time zone 'Asia/Singapore')::date as on_day
      from public.consultant_notes n
     where n.survey_id is not null
       and (coalesce(nullif(btrim(n.acidity_result), ''), nullif(btrim(n.health_goals), ''),
                     nullif(btrim(n.remarks_condition), ''), nullif(btrim(n.remarks_recommendation), '')) is not null
            or (jsonb_typeof(n.attachments) = 'array' and jsonb_array_length(n.attachments) > 0))
    union all
    select f.survey_id, (f.uploaded_at at time zone 'Asia/Singapore')::date
      from public.health_survey_attachments f
     where f.survey_id is not null
  ),
  q as (
    select s.customer_id, s.id, s.submitted_at,
           case when s.source = 'consultant' then 'consultant'
                when s.event_link then 'event_then_centre'
                else 'centre_link' end as kind,
           case
             when s.source = 'consultant' then
               case when s.review_answer or s.particulars_answer
                         or exists (select 1 from w where w.survey_id = s.id) then
                 greatest(s.made_on, least(
                   case when s.review_answer or s.particulars_answer then
                     greatest(s.made_on, (least(
                       case when s.review_answer then
                         (select min(a.created_at) from public.audit_logs a
                           where a.record_id = s.id and a.table_name = 'health_surveys'
                             and a.action = 'health_survey_reviewed'
                             and coalesce(nullif(btrim(a.new_data->>'acidity'), ''),
                                          nullif(btrim(a.new_data->>'condition'), ''),
                                          nullif(btrim(a.new_data->>'recommendation'), ''),
                                          nullif(btrim(a.new_data->>'health_goals'), '')) is not null) end,
                       case when s.particulars_answer then
                         (select min(a.created_at) from public.audit_logs a
                           where a.record_id = s.id and a.table_name = 'health_surveys'
                             and a.action = 'survey_particulars_edited') end)
                      at time zone 'Asia/Singapore')::date)
                   end,
                   (select min(w.on_day) from w where w.survey_id = s.id)))
               end
             when s.event_link then
               (select min(w.on_day) from w where w.survey_id = s.id and w.on_day > s.form_on)
             else s.form_on
           end as visit_on
      from s
  )
  select distinct on (q.customer_id) q.customer_id, q.visit_on, q.id, q.kind
    from q
   where q.visit_on is not null
   order by q.customer_id, q.visit_on, q.submitted_at, q.id
$fn$
$def$;
  c_referral_date_def constant text := $def$
create or replace function public.tg_customers_referral_date()
returns trigger
language plpgsql
set search_path = public
as $fn$
-- 398: the referral date is recorded from now on (the Owner, 6 Oct 2026).
-- Whenever a referrer is set or changed, by any path (the Customers page's
-- Add and Edit, quick create, Correct Referrer, whatever comes later),
-- referred_at becomes now(). It decides who counts in a referral promotion,
-- so a login writing this table directly through the API (the roles anon
-- and authenticated: the Customers page, or anyone calling the API by hand)
-- never writes it: a new or changed referrer is dated now(); otherwise the
-- row keeps the date it had (none on a new row without a referrer),
-- whatever was sent. Only the database's own functions, which run as their
-- owner, write a date of their own: the sign-up link writes now(), and a
-- merge moves the duplicate's friends to the record kept, the same
-- referrals, so merge_customer_records sets energia.keep_referral_date
-- around that move and each friend keeps their date. For them too, a
-- referrer set or changed without a date of its own is dated now().
-- Removing a referrer leaves referred_at alone; it is never read without
-- one. Older links without a date fall back to created_at wherever they are
-- counted; nothing is backfilled.
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      new.referred_at := case when new.referred_by is null then null else now() end;
    elsif new.referred_by is not null and new.referred_by is distinct from old.referred_by then
      new.referred_at := now();
    else
      new.referred_at := old.referred_at;
    end if;
    return new;
  end if;
  if coalesce(current_setting('energia.keep_referral_date', true), '') = '1' then
    return new;
  end if;
  if new.referred_by is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.referred_at is null then
      new.referred_at := now();
    end if;
  elsif new.referred_by is distinct from old.referred_by
        and new.referred_at is not distinct from old.referred_at then
    new.referred_at := now();
  end if;
  return new;
end $fn$
$def$;
  c_downline_def constant text := $def$
create or replace function public.customer_downline_visits(p_customer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
-- 398: a referrer's downline with visits (the Owner, 6 Oct 2026),
-- Owner/Manager only. Tier 1: customers they referred; Tier 2: customers
-- those referred. Each with name, phone, joined (the Singapore date of the
-- referral, else of the customer's creation for older links without a
-- date), visited and the first visit date (customer_centre_visits).
declare
  v_name text; v_phone text; v_t1 jsonb; v_t2 jsonb;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can view a downline' using errcode = '42501'; end if;
  select c.full_name, c.phone into v_name, v_phone from public.customers c where c.id = p_customer_id;
  if not found then raise exception 'Customer not found'; end if;

  with v as (select x.customer_id, x.first_visit_on from public.customer_centre_visits() x)
  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_id', c.id, 'name', c.full_name, 'phone', c.phone,
           'joined_on', (coalesce(c.referred_at, c.created_at) at time zone 'Asia/Singapore')::date,
           'joined_from_created', c.referred_at is null,
           'visited', v.first_visit_on is not null, 'first_visit_on', v.first_visit_on)
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
           'visited', v.first_visit_on is not null, 'first_visit_on', v.first_visit_on)
           order by coalesce(c.referred_at, c.created_at) desc, c.full_name, c.id), '[]'::jsonb)
    into v_t2
    from public.customers c
    join public.customers p on p.id = c.referred_by
    left join v on v.customer_id = c.id
   where p.referred_by = p_customer_id and c.deleted_at is null and p.deleted_at is null;

  return jsonb_build_object('customer_id', p_customer_id, 'name', v_name, 'phone', v_phone,
    'tier1', v_t1, 'tier2', v_t2);
end $fn$
$def$;
  c_friends_def constant text := $def$
create or replace function public.referral_campaign_friends(p_campaign_id uuid)
returns table(referrer_customer_id uuid, friend_customer_id uuid, referred_on date,
              first_visit_on date, counted boolean)
language sql
stable
security definer
set search_path = public
as $fn$
  -- 398: a referral promotion's counting (the Owner, 6 Oct 2026), the only
  -- place it is written. Every Tier 1 friend (customers.referred_by, the
  -- referrer not deleted) referred in the window: the Singapore date of
  -- referred_at, else of created_at for older links without a date. A
  -- friend counts for their referrer when their first qualifying visit
  -- (customer_centre_visits) is in the same window. A Tier 2 friend is
  -- nobody's Tier 1 here and counts for no one but their own referrer.
  select c.referred_by, c.id,
         (coalesce(c.referred_at, c.created_at) at time zone 'Asia/Singapore')::date,
         v.first_visit_on,
         coalesce(v.first_visit_on between rc.starts_on and rc.ends_on, false)
    from public.referral_campaigns rc
    join public.customers c
      on c.deleted_at is null and c.referred_by is not null
     and (coalesce(c.referred_at, c.created_at) at time zone 'Asia/Singapore')::date
         between rc.starts_on and rc.ends_on
    join public.customers r on r.id = c.referred_by and r.deleted_at is null
    left join public.customer_centre_visits() v on v.customer_id = c.id
   where rc.id = p_campaign_id
$fn$
$def$;
  c_standing_def constant text := $def$
create or replace function public.referral_campaign_standing(p_tiers integer[], p_count integer)
returns jsonb
language sql
immutable
set search_path = public
as $fn$
  -- 398: where a count stands against a promotion's tiers: the highest tier
  -- reached (the reward is for that one only), the next tier and how many
  -- more friends reach it. Null when there is none.
  select jsonb_build_object(
    'tier_reached', (select max(t) from unnest(p_tiers) t where t <= coalesce(p_count, 0)),
    'next_tier', (select min(t) from unnest(p_tiers) t where t > coalesce(p_count, 0)),
    'to_next', (select min(t) from unnest(p_tiers) t where t > coalesce(p_count, 0)) - coalesce(p_count, 0))
$fn$
$def$;
  c_report_def constant text := $def$
create or replace function public.referral_campaign_report(p_campaign text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
-- 398: a referral promotion's report (the Owner, 6 Oct 2026), Owner/Manager
-- only. p_campaign is a promotion's code; none: the latest that has started
-- (else the first). Every referrer with a friend referred in the window:
-- friends counted, tier reached, next tier, the reward if given, and each
-- friend (the drill-down). "provisional" until the window has ended.
declare
  rc public.referral_campaigns%rowtype; v_today date := public.sg_today(); v_rows jsonb; v_list jsonb;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can see the referral promotion' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_campaign, '')), '') is null then
    select * into rc from public.referral_campaigns where starts_on <= v_today order by starts_on desc limit 1;
    if not found then
      select * into rc from public.referral_campaigns order by starts_on limit 1; end if;
  else
    select * into rc from public.referral_campaigns where code = btrim(p_campaign);
  end if;
  if rc.id is null then raise exception 'Referral promotion not found'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('code', x.code, 'title', x.title,
           'starts_on', x.starts_on, 'ends_on', x.ends_on) order by x.starts_on desc), '[]'::jsonb)
    into v_list from public.referral_campaigns x;

  with f as (select * from public.referral_campaign_friends(rc.id)),
  per as (
    select f.referrer_customer_id as rid, (count(*) filter (where f.counted))::int as counted,
           count(*)::int as referred
      from f group by f.referrer_customer_id
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'referrer_customer_id', r.id, 'name', r.full_name, 'phone', r.phone,
             'is_affiliate', exists (select 1 from public.customer_affiliates ca
                                      where ca.customer_id = r.id and ca.deleted_at is null),
             'counted', per.counted, 'referred_in_window', per.referred)
           || public.referral_campaign_standing(rc.tiers, per.counted)
           || jsonb_build_object(
             'reward', (select jsonb_build_object(
                          'reward_id', w.id, 'tier', w.tier, 'friends_counted', w.friends_counted,
                          'given_at', w.given_at, 'given_by_name', gp.full_name,
                          'store_id', w.store_id, 'store_name', s.name, 'note', w.note,
                          'items', (select coalesce(jsonb_agg(jsonb_build_object(
                                       'product_id', i.product_id, 'product_name', p.name,
                                       'quantity', i.quantity, 'use_no', u.use_no) order by p.name, i.id), '[]'::jsonb)
                                      from public.referral_campaign_reward_items i
                                      join public.products p on p.id = i.product_id
                                      left join public.stock_uses u on u.id = i.stock_use_id
                                     where i.reward_id = w.id))
                          from public.referral_campaign_rewards w
                          left join public.profiles gp on gp.id = w.given_by
                          left join public.stores s on s.id = w.store_id
                         where w.campaign_id = rc.id and w.referrer_customer_id = r.id
                           and w.voided_at is null),
             'friends', (select coalesce(jsonb_agg(jsonb_build_object(
                            'customer_id', c.id, 'name', c.full_name, 'phone', c.phone,
                            'referred_on', f2.referred_on, 'first_visit_on', f2.first_visit_on,
                            'counted', f2.counted)
                            order by f2.counted desc, f2.referred_on, c.full_name, c.id), '[]'::jsonb)
                           from f f2 join public.customers c on c.id = f2.friend_customer_id
                          where f2.referrer_customer_id = r.id))
           order by per.counted desc, r.full_name, r.id), '[]'::jsonb)
    into v_rows
    from per join public.customers r on r.id = per.rid;

  return jsonb_build_object(
    'campaign', jsonb_build_object('code', rc.code, 'title', rc.title, 'reward_reason', rc.reward_reason,
      'starts_on', rc.starts_on, 'ends_on', rc.ends_on, 'tiers', to_jsonb(rc.tiers), 'today', v_today,
      'status', case when v_today > rc.ends_on then 'final'
                     when v_today < rc.starts_on then 'not_started' else 'provisional' end),
    'campaigns', v_list,
    'referrers', v_rows);
end $fn$
$def$;
  c_give_def constant text := $def$
create or replace function public.give_referral_campaign_reward(
  p_campaign text,
  p_referrer_customer_id uuid,
  p_store_id uuid,
  p_items jsonb,
  p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
-- 398: marks a referral promotion's reward given (the Owner, 6 Oct 2026).
-- Owner or Manager; only after the window has ended; for the highest tier
-- the referrer reached (referral_campaign_friends at this moment); once per
-- referrer per promotion. p_items: [{product_id, quantity}], one entry per
-- product. Each product is taken out of p_store_id's stock as a stock use
-- (record_stock_use: its stock check, its store access check, its movement
-- and its audit), reason "<promotion's reward reason> - <referrer's name>",
-- and the reward is recorded with them, all in this one transaction.
declare
  rc public.referral_campaigns%rowtype; v_name text; v_count int; v_tier int; v_reward uuid;
  e jsonb; v_pid uuid; v_qty int; v_seen uuid[] := '{}'; v_use jsonb; v_use_id uuid; v_reason text;
  v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_uses jsonb := '[]'::jsonb; v_store text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can give a referral reward' using errcode = '42501'; end if;
  select * into rc from public.referral_campaigns where code = btrim(coalesce(p_campaign, ''));
  if not found then raise exception 'Referral promotion not found'; end if;
  if public.sg_today() <= rc.ends_on then
    raise exception 'The % runs until %. Its rewards are given after it ends, for the highest tier reached.',
      rc.title, to_char(rc.ends_on, 'FMDD Mon YYYY'); end if;

  select c.full_name into v_name from public.customers c
   where c.id = p_referrer_customer_id and c.deleted_at is null for update;
  if not found then raise exception 'Referrer not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('referral-reward:' || rc.id::text || ':' || p_referrer_customer_id::text, 0));
  if exists (select 1 from public.referral_campaign_rewards w
              where w.campaign_id = rc.id and w.referrer_customer_id = p_referrer_customer_id
                and w.voided_at is null) then
    raise exception '% already has a reward recorded for the %.', v_name, rc.title; end if;

  select (count(*) filter (where f.counted))::int into v_count
    from public.referral_campaign_friends(rc.id) f where f.referrer_customer_id = p_referrer_customer_id;
  v_tier := (public.referral_campaign_standing(rc.tiers, v_count)->>'tier_reached')::int;
  if v_tier is null then
    raise exception '% has % friend(s) counted, fewer than the first tier (%).',
      v_name, v_count, (select min(t) from unnest(rc.tiers) t); end if;

  select s.name into v_store from public.stores s where s.id = p_store_id and s.deleted_at is null;
  if v_store is null then raise exception 'Choose the store the reward comes from'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Choose at least one product and its quantity'; end if;
  for e in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e->>'product_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Each reward line needs a product'; end if;
    if coalesce(e->>'quantity', '') !~ '^[0-9]{1,6}$' or (e->>'quantity')::int <= 0 then
      raise exception 'Each reward line needs a whole quantity of at least 1'; end if;
    v_pid := (e->>'product_id')::uuid;
    if v_pid = any(v_seen) then raise exception 'Each product goes on one line only'; end if;
    v_seen := v_seen || v_pid;
  end loop;

  insert into public.referral_campaign_rewards
    (campaign_id, referrer_customer_id, tier, friends_counted, store_id, note, given_by)
  values (rc.id, p_referrer_customer_id, v_tier, v_count, p_store_id, v_note, auth.uid())
  returning id into v_reward;

  v_reason := rc.reward_reason || ' — ' || v_name;
  for e in select * from jsonb_array_elements(p_items) loop
    v_pid := (e->>'product_id')::uuid; v_qty := (e->>'quantity')::int;
    v_use := public.record_stock_use('store', p_store_id, v_pid, v_qty, v_reason, v_note);
    select u.id into v_use_id from public.stock_uses u where u.use_no = v_use->>'use_no';
    if v_use_id is null then raise exception 'The stock use for the reward was not recorded'; end if;
    insert into public.referral_campaign_reward_items (reward_id, product_id, quantity, stock_use_id)
    values (v_reward, v_pid, v_qty, v_use_id);
    v_uses := v_uses || jsonb_build_object('product_id', v_pid, 'quantity', v_qty, 'use_no', v_use->>'use_no');
  end loop;

  perform public.write_audit_ex('referral_campaign_rewards', v_reward, 'referral_reward_given', null,
    jsonb_build_object('campaign', rc.code, 'referrer_customer_id', p_referrer_customer_id,
      'referrer', v_name, 'tier', v_tier, 'friends_counted', v_count, 'store_id', p_store_id,
      'items', v_uses),
    'affiliate', v_note, p_store_id);

  return jsonb_build_object('success', true, 'reward_id', v_reward, 'campaign', rc.code,
    'referrer', v_name, 'tier', v_tier, 'friends_counted', v_count, 'store_name', v_store,
    'items', v_uses);
end $fn$
$def$;
  c_void_def constant text := $def$
create or replace function public.void_referral_campaign_reward(
  p_reward_id uuid,
  p_reason text,
  p_return_stock boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
-- 398: undoes a referral reward recorded by mistake, the Owner alone, with a
-- reason. The reward is kept, marked undone, and can then be marked again.
-- With p_return_stock (the default) its products go back into the store they
-- came from, with a movement naming the stock use; without it (the products
-- did leave the store) stock is not touched.
declare
  w public.referral_campaign_rewards%rowtype; it record; v_name text; v_back jsonb := '[]'::jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_owner() then
    raise exception 'Only the Owner can undo a referral reward' using errcode = '42501'; end if;
  if v_reason is null then raise exception 'A reason is required'; end if;
  select * into w from public.referral_campaign_rewards where id = p_reward_id for update;
  if not found then raise exception 'Referral reward not found'; end if;
  if w.voided_at is not null then raise exception 'This reward was already undone'; end if;
  select c.full_name into v_name from public.customers c where c.id = w.referrer_customer_id;

  update public.referral_campaign_rewards
     set voided_at = now(), voided_by = auth.uid(), void_reason = v_reason,
         stock_put_back = coalesce(p_return_stock, true)
   where id = w.id;

  if coalesce(p_return_stock, true) then
    for it in select i.product_id, i.quantity, u.use_no
                from public.referral_campaign_reward_items i
                left join public.stock_uses u on u.id = i.stock_use_id
               where i.reward_id = w.id order by i.id loop
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (w.store_id, it.product_id, it.quantity)
      on conflict (store_id, product_id)
        do update set current_qty = public.store_inventory.current_qty + excluded.current_qty,
                      updated_at = now();
      insert into public.stock_movements (product_id, movement_type, to_store_id, quantity, notes, created_by)
      values (it.product_id, 'inventory_adjustment'::stock_movement_type, w.store_id, it.quantity,
        'Referral reward undone — ' || coalesce(it.use_no, 'stock use') || ' put back (' || v_reason || ')',
        auth.uid());
      v_back := v_back || jsonb_build_object('product_id', it.product_id, 'quantity', it.quantity, 'use_no', it.use_no);
    end loop;
  end if;

  perform public.write_audit_ex('referral_campaign_rewards', w.id, 'referral_reward_undone', to_jsonb(w),
    jsonb_build_object('referrer', v_name, 'stock_put_back', coalesce(p_return_stock, true), 'items', v_back),
    'affiliate', v_reason, w.store_id);

  return jsonb_build_object('success', true, 'reward_id', w.id, 'referrer', v_name,
    'stock_put_back', coalesce(p_return_stock, true), 'items', v_back);
end $fn$
$def$;
  c_portal_def constant text := $def$
create or replace function public.affiliate_portal_campaign_progress()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
-- 398: the signed-in affiliate's own progress in the latest referral
-- promotion that has started (the Owner, 6 Oct 2026): their friends counted
-- so far, the tier reached and the next one. Counts only, no names: their
-- Tier 1 list is already on the page, and nobody else's data is here.
declare
  v_me uuid := public.current_affiliate_customer_id(); rc public.referral_campaigns%rowtype;
  v_today date := public.sg_today(); v_count int; v_ref int; w public.referral_campaign_rewards%rowtype;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  select * into rc from public.referral_campaigns where starts_on <= v_today order by starts_on desc limit 1;
  if not found then return jsonb_build_object('campaign', null); end if;
  select (count(*) filter (where f.counted))::int, count(*)::int into v_count, v_ref
    from public.referral_campaign_friends(rc.id) f where f.referrer_customer_id = v_me;
  select * into w from public.referral_campaign_rewards x
   where x.campaign_id = rc.id and x.referrer_customer_id = v_me and x.voided_at is null;
  return jsonb_build_object(
      'campaign', jsonb_build_object('code', rc.code, 'title', rc.title, 'starts_on', rc.starts_on,
        'ends_on', rc.ends_on, 'tiers', to_jsonb(rc.tiers),
        'status', case when v_today > rc.ends_on then 'final' else 'provisional' end),
      'counted', v_count, 'referred_in_window', v_ref,
      'reward_tier', w.tier, 'reward_given_at', w.given_at)
    || public.referral_campaign_standing(rc.tiers, v_count);
end $fn$
$def$;
  c_search_def constant text := $def$
create function public.search_customers(
  p_query text default null,
  p_source text default null,
  p_limit integer default 50,
  p_offset integer default 0,
  p_visited text default null,
  p_visit_from date default null,
  p_visit_to date default null)
returns table(id uuid, full_name text, first_name text, last_name text, phone text, email text,
              address text, notes text, is_active boolean, created_at timestamptz, referred_by uuid,
              is_referrer boolean, date_of_birth date, gender text, gender_other text, occupation text,
              source_option_id uuid, source_label text, source_details text,
              first_visit_on date, total_count bigint)
language sql
stable
security definer
set search_path = public
as $fn$
  -- 398: the Customers page's list and its Excel exports, as 125/126 left
  -- it, plus the first visit (customer_centre_visits, the Owner's rule of 6
  -- Oct 2026): p_visited 'visited' or 'not_visited' (anything else: all),
  -- p_visit_from / p_visit_to on the first visit date, both ends included
  -- (a date leaves out those who never visited). Rows only for a staff
  -- login, as the customers table's own read policy.
  with q as (
    select nullif(trim(coalesce(p_query,'')),'') as term,
           public.current_user_role() is not null as staff
  ),
  visits as (
    select v.customer_id, v.first_visit_on from public.customer_centre_visits() v
  ),
  matched as (
    select c.*, vs.first_visit_on as visit_on
      from public.customers c
      cross join q
      left join visits vs on vs.customer_id = c.id
     where q.staff
       and c.deleted_at is null
       and (p_source is null or p_source = ''
            or (p_source = '__none' and c.source_option_id is null)
            or (p_source <> '__none' and c.source_option_id = nullif(p_source,'')::uuid))
       and (q.term is null
            or c.full_name ilike '%' || q.term || '%'
            or c.phone     ilike '%' || q.term || '%'
            or c.email     ilike '%' || q.term || '%'
            or c.notes     ilike '%' || q.term || '%'
            or exists (select 1 from public.customer_phone_history h
                        where h.customer_id = c.id
                          and h.phone ilike '%' || q.term || '%'))
       and (case coalesce(p_visited, '')
              when 'visited' then vs.first_visit_on is not null
              when 'not_visited' then vs.first_visit_on is null
              else true end)
       and (p_visit_from is null or vs.first_visit_on >= p_visit_from)
       and (p_visit_to is null or vs.first_visit_on <= p_visit_to)
  )
  select m.id, m.full_name, m.first_name, m.last_name, m.phone, m.email, m.address, m.notes,
         m.is_active, m.created_at, m.referred_by, m.is_referrer,
         m.date_of_birth, m.gender::text, m.gender_other, m.occupation,
         m.source_option_id, m.source_label, m.source_details,
         m.visit_on,
         count(*) over () as total_count
    from matched m
   order by m.created_at desc
   limit greatest(coalesce(p_limit, 50), 1)
  offset greatest(coalesce(p_offset, 0), 0)
$fn$
$def$;
  c_referrer_downline_def constant text := $def$
create or replace function public.referrer_downline(p_customer_id uuid)
returns table(customer_id uuid, full_name text, phone text, referred_by uuid, depth integer,
              paid_purchases integer, total_spend numeric)
language plpgsql
stable
security definer
set search_path = public
as $fn$
#variable_conflict use_column
-- 398: the Commissions page's Referrers tab, the same rows as before, now
-- only for an Owner, a Manager or an Admin (affiliate_payout_access(), as
-- referrer_earnings beside it). It was granted to every signed-in login,
-- affiliate portal logins included, and checked nothing.
begin
  if not public.affiliate_payout_access() then
    raise exception 'Commission access denied' using errcode = '42501'; end if;
  return query
  with recursive tree as (
    select c.id, c.full_name, c.phone, c.referred_by, 1 as depth
    from public.customers c
    where c.referred_by = p_customer_id and c.deleted_at is null
    union all
    select c.id, c.full_name, c.phone, c.referred_by, t.depth + 1
    from public.customers c
    join tree t on c.referred_by = t.id
    where c.deleted_at is null and t.depth < 50   -- safety bound
  )
  select
    t.id, t.full_name, t.phone, t.referred_by, t.depth,
    coalesce(inv.cnt, 0)::integer as paid_purchases,
    coalesce(inv.spend, 0)::numeric as total_spend
  from tree t
  left join lateral (
    select count(*) as cnt, sum(i.total_amount) as spend
    from public.invoices i
    where i.customer_id = t.id and i.status = 'paid' and i.deleted_at is null
  ) inv on true
  order by t.depth, t.full_name;
end $fn$
$def$;

  -- ── Anchors and their replacements ─────────────────────────────────────────
  c_merge_a constant text :=
       E'  for r in select id from public.customers\n'
    || E'            where referred_by = p_merge and id <> p_keep and deleted_at is null\n'
    || E'  loop\n'
    || E'    perform public.reassign_customer_referrer(r.id, p_keep,\n'
    || E'      ''Referrer merged from duplicate '' || p_merge::text || '': '' || trim(p_reason));\n'
    || E'  end loop;\n';
  c_merge_r constant text :=
       E'  -- 398: the duplicate''s friends are the same referrals, made when they\n'
    || E'  -- were made: each keeps their referral date (tg_customers_referral_date).\n'
    || E'  perform set_config(''energia.keep_referral_date'', ''1'', true);\n'
    || E'  for r in select id from public.customers\n'
    || E'            where referred_by = p_merge and id <> p_keep and deleted_at is null\n'
    || E'  loop\n'
    || E'    perform public.reassign_customer_referrer(r.id, p_keep,\n'
    || E'      ''Referrer merged from duplicate '' || p_merge::text || '': '' || trim(p_reason));\n'
    || E'  end loop;\n'
    || E'  perform set_config(''energia.keep_referral_date'', ''0'', true);\n';

  c_search_old constant text := 'search_customers(text,text,integer,integer)';
  c_search_new constant text := 'search_customers(text,text,integer,integer,text,date,date)';
  c_search_before constant text := '7d9557259ab9473c0407b9eeb4493e1c';
  c_search_after constant text := 'df63c717eab1825017e2567679f3e135';

  r record; d text; v text; n int; i int; v_bad text; v_install_search boolean := false;
  v_fns text[] := '{}'; v_defs text[] := '{}';
begin
  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ──
  -- search_customers: the four-argument version as read, or already replaced.
  if to_regprocedure('public.' || c_search_new) is not null then
    v := md5(pg_get_functiondef(to_regprocedure('public.' || c_search_new)));
    if v <> c_search_after then
      raise exception '398: a different public.% already exists (md5 %)', c_search_new, v; end if;
    if to_regprocedure('public.' || c_search_old) is not null then
      raise exception '398: public.% is back beside the new one. Drop it (re-running 83 brings it back) and re-run.', c_search_old; end if;
    raise notice '398: public.% is already this version; left alone', c_search_new;
  else
    if to_regprocedure('public.' || c_search_old) is null then
      raise exception '398: public.% is missing', c_search_old; end if;
    v := md5(pg_get_functiondef(to_regprocedure('public.' || c_search_old)));
    if v <> c_search_before then
      raise exception '398: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_search_old, v; end if;
    if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname = 'search_customers') <> 1 then
      raise exception '398: more than one public.search_customers exists'; end if;
    v_install_search := true;
  end if;

  -- Replaced whole (a language change) or patched by anchor.
  for r in select * from (values
    ('referrer_downline(uuid)', '8a471732e7cfa41d73b9aa581c837c6a', 'e471bc0a0107bc1f70e8c01eea2e74d8', null::text[]),
    ('merge_customer_records(uuid,uuid,text,uuid)', '955179afeac18bbfe2218079258669c9', 'a09b99d88585b5b3ab68f081fcdf01c8',
     array[[c_merge_a, c_merge_r]])
  ) x(fn, before_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '398: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '398: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '398: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    if r.edits is null then
      d := c_referrer_downline_def;
    else
      for i in 1 .. array_length(r.edits, 1) loop
        n := (length(d) - length(replace(d, r.edits[i][1], ''))) / length(r.edits[i][1]);
        if n <> 1 then
          raise exception '398: anchor % of public.% was found % times, not once', i, r.fn, n; end if;
        d := replace(d, r.edits[i][1], r.edits[i][2]);
      end loop;
    end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- Called, not changed: the version it was read at.
  for r in select * from (values
    ('record_stock_use(text,uuid,uuid,integer,text,text)', 'db278faba262b0a3801944cd821a62fd'),
    ('reassign_customer_referrer(uuid,uuid,text)', '9b32f3bef5b4f17897aae637e343c208')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '398: public.% is missing or not the version read on 6 Oct 2026', r.fn; end if;
  end loop;

  -- New: absent, or already this version.
  for r in select * from (values
    ('customer_centre_visits()', '05b4a9bb5fb955f4c00b62e4966c96d2'),
    ('tg_customers_referral_date()', '5ea2010a7b31efd4db32474723f814f6'),
    ('customer_downline_visits(uuid)', '1125dc56d3964c4b54a61ce88448ad65'),
    ('referral_campaign_friends(uuid)', '6e88ab96e57e661d8a06eabb41e65874'),
    ('referral_campaign_standing(integer[],integer)', '43e8860ba8fade528ded701cfbeea12f'),
    ('referral_campaign_report(text)', 'b791ae0aa41975da55a66fc488df64cb'),
    ('give_referral_campaign_reward(text,uuid,uuid,jsonb,text)', 'db5bae60bc6bf65d2ae206a031ff62eb'),
    ('void_referral_campaign_reward(uuid,text,boolean)', '23bf34d722341b1811f5efe53a2d1d08'),
    ('affiliate_portal_campaign_progress()', '7548c77bb887aec7227540ef15a0f14b')) x(fn, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '398: a different public.% already exists (md5 %)', r.fn,
        md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))); end if;
  end loop;
  -- No other function of these names (one overload each, 386/388/390).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('customer_centre_visits', 'tg_customers_referral_date', 'customer_downline_visits',
                       'referral_campaign_friends', 'referral_campaign_standing', 'referral_campaign_report',
                       'give_referral_campaign_reward', 'void_referral_campaign_reward',
                       'affiliate_portal_campaign_progress')
     and p.oid::regprocedure::text not in ('customer_centre_visits()', 'tg_customers_referral_date()',
       'customer_downline_visits(uuid)', 'referral_campaign_friends(uuid)',
       'referral_campaign_standing(integer[],integer)', 'referral_campaign_report(text)',
       'give_referral_campaign_reward(text,uuid,uuid,jsonb,text)',
       'void_referral_campaign_reward(uuid,text,boolean)', 'affiliate_portal_campaign_progress()');
  if v_bad is not null then
    raise exception '398: another overload exists: %', v_bad; end if;
  -- The referral-date trigger: absent, or already this one.
  select pg_get_triggerdef(t.oid) into v from pg_trigger t
   where t.tgrelid = 'public.customers'::regclass and t.tgname = 'trg_customers_referral_date' and not t.tgisinternal;
  if v is not null and v !~ ('^CREATE TRIGGER trg_customers_referral_date BEFORE INSERT OR UPDATE OF referred_by, referred_at'
                             || ' ON public\.customers FOR EACH ROW EXECUTE FUNCTION (public\.)?tg_customers_referral_date\(\)$') then
    raise exception '398: a different trigger trg_customers_referral_date is on public.customers: %', v; end if;

  -- ── The promotion and its rewards ──────────────────────────────────────────
  create table if not exists public.referral_campaigns (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    title text not null,
    reward_reason text not null,
    starts_on date not null,
    ends_on date not null,
    tiers integer[] not null,
    created_at timestamptz not null default now(),
    constraint referral_campaigns_window_check check (ends_on >= starts_on),
    constraint referral_campaigns_tiers_check check (cardinality(tiers) > 0 and 0 < all (tiers))
  );
  create table if not exists public.referral_campaign_rewards (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null references public.referral_campaigns(id),
    referrer_customer_id uuid not null references public.customers(id),
    tier integer not null check (tier > 0),
    friends_counted integer not null,
    store_id uuid not null references public.stores(id),
    note text,
    given_by uuid references public.profiles(id),
    given_at timestamptz not null default now(),
    voided_at timestamptz,
    voided_by uuid references public.profiles(id),
    void_reason text,
    stock_put_back boolean,
    constraint referral_campaign_rewards_counted_check check (friends_counted >= tier),
    constraint referral_campaign_rewards_void_check check (voided_at is null or void_reason is not null)
  );
  create unique index if not exists referral_campaign_rewards_once
    on public.referral_campaign_rewards (campaign_id, referrer_customer_id) where voided_at is null;
  create table if not exists public.referral_campaign_reward_items (
    id uuid primary key default gen_random_uuid(),
    reward_id uuid not null references public.referral_campaign_rewards(id),
    product_id uuid not null references public.products(id),
    quantity integer not null check (quantity > 0),
    stock_use_id uuid not null references public.stock_uses(id),
    constraint referral_campaign_reward_items_once unique (reward_id, product_id)
  );
  foreach v in array array['referral_campaigns', 'referral_campaign_rewards', 'referral_campaign_reward_items'] loop
    execute format('alter table public.%I enable row level security', v);
    execute format('revoke all on table public.%I from anon, authenticated', v);
  end loop;
  insert into public.referral_campaigns (code, title, reward_reason, starts_on, ends_on, tiers)
  values ('2026-10', 'October referral promotion', 'October referral reward', '2026-10-01', '2026-10-31',
          '{10,20,50,80}')
  on conflict (code) do nothing;

  -- ── Install: the helpers first, then what calls them ──────────────────────
  execute c_visits_def;
  execute c_referral_date_def;
  execute c_standing_def;
  execute c_friends_def;
  execute c_downline_def;
  execute c_report_def;
  execute c_give_def;
  execute c_void_def;
  execute c_portal_def;
  foreach v in array array['customer_centre_visits()', 'tg_customers_referral_date()',
                           'referral_campaign_friends(uuid)', 'referral_campaign_standing(integer[],integer)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', v);
    execute format('grant execute on function public.%s to service_role', v);
  end loop;
  foreach v in array array['customer_downline_visits(uuid)', 'referral_campaign_report(text)',
                           'give_referral_campaign_reward(text,uuid,uuid,jsonb,text)',
                           'void_referral_campaign_reward(uuid,text,boolean)',
                           'affiliate_portal_campaign_progress()'] loop
    execute format('revoke all on function public.%s from public, anon', v);
    execute format('grant execute on function public.%s to authenticated, service_role', v);
  end loop;
  if v_install_search then
    execute 'drop function public.' || c_search_old;
    execute c_search_def;
    execute 'revoke all on function public.' || c_search_new || ' from public, anon';
    execute 'grant execute on function public.' || c_search_new || ' to authenticated, service_role';
  end if;
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.customers'::regclass
                    and tgname = 'trg_customers_referral_date' and not tgisinternal) then
    create trigger trg_customers_referral_date before insert or update of referred_by, referred_at
      on public.customers for each row execute function public.tg_customers_referral_date();
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    (c_search_new, c_search_after),
    ('referrer_downline(uuid)', 'e471bc0a0107bc1f70e8c01eea2e74d8'),
    ('merge_customer_records(uuid,uuid,text,uuid)', 'a09b99d88585b5b3ab68f081fcdf01c8'),
    ('customer_centre_visits()', '05b4a9bb5fb955f4c00b62e4966c96d2'),
    ('tg_customers_referral_date()', '5ea2010a7b31efd4db32474723f814f6'),
    ('customer_downline_visits(uuid)', '1125dc56d3964c4b54a61ce88448ad65'),
    ('referral_campaign_friends(uuid)', '6e88ab96e57e661d8a06eabb41e65874'),
    ('referral_campaign_standing(integer[],integer)', '43e8860ba8fade528ded701cfbeea12f'),
    ('referral_campaign_report(text)', 'b791ae0aa41975da55a66fc488df64cb'),
    ('give_referral_campaign_reward(text,uuid,uuid,jsonb,text)', 'db5bae60bc6bf65d2ae206a031ff62eb'),
    ('void_referral_campaign_reward(uuid,text,boolean)', '23bf34d722341b1811f5efe53a2d1d08'),
    ('affiliate_portal_campaign_progress()', '7548c77bb887aec7227540ef15a0f14b')) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '398: installed with md5s other than the tested ones: %', v_bad; end if;
  if to_regprocedure('public.' || c_search_old) is not null then
    raise exception '398: the four-argument search_customers is still there'; end if;
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'public.customers'::regclass and t.tgname = 'trg_customers_referral_date'
         and not t.tgisinternal and t.tgenabled = 'O'
         and pg_get_triggerdef(t.oid) ~ ' BEFORE INSERT OR UPDATE OF referred_by, referred_at ON public\.customers FOR EACH ROW ') <> 1 then
    raise exception '398: the referral-date trigger is not on public.customers as tested'; end if;
  -- The pages reach what they call; the helpers are endpoints for nobody.
  foreach v in array array[c_search_new, 'referrer_downline(uuid)', 'customer_downline_visits(uuid)',
                           'referral_campaign_report(text)',
                           'give_referral_campaign_reward(text,uuid,uuid,jsonb,text)',
                           'void_referral_campaign_reward(uuid,text,boolean)',
                           'affiliate_portal_campaign_progress()'] loop
    if not has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '398: public.% is not callable by staff', v; end if;
    if has_function_privilege('anon', 'public.' || v, 'execute') then
      raise exception '398: public.% is callable signed out', v; end if;
  end loop;
  foreach v in array array['customer_centre_visits()', 'tg_customers_referral_date()',
                           'referral_campaign_friends(uuid)', 'referral_campaign_standing(integer[],integer)',
                           'merge_customer_records(uuid,uuid,text,uuid)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '398: public.% is callable by a client role', v; end if;
  end loop;
  foreach v in array array['referral_campaigns', 'referral_campaign_rewards', 'referral_campaign_reward_items'] loop
    if has_table_privilege('anon', 'public.' || v, 'select') or has_table_privilege('authenticated', 'public.' || v, 'select')
       or has_table_privilege('authenticated', 'public.' || v, 'insert') then
      raise exception '398: public.% is readable or writable by a client role', v; end if;
  end loop;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
