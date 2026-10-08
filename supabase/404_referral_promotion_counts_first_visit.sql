-- 404_referral_promotion_counts_first_visit.sql
--
-- WHAT WAS WRONG (found 8 Oct 2026)
--
--   398 counted a Tier 1 friend in a referral promotion only when the friend
--   was REFERRED in the promotion's window (the Singapore date of
--   referred_at, else of created_at for older links without a date) and
--   also first visited the centre in it. The Owner tracks the promotion by
--   the FIRST VISIT: a friend referred in August or September who first
--   comes to the centre in October is a friend the October promotion is
--   for, and 398 left them out. On production on 8 Oct 2026 the October
--   promotion counted 3 friends, for 2 referrers; by the first visit it is
--   6 (3 of them referred before October), for 3 referrers, and 2 friends
--   referred in October had not visited yet (3 when read again later that
--   day; see THE RULES for the final figures).
--
--   Beside the count, the report and the affiliate portal gave every friend
--   referred in the window ("referred in the window"). Under the first-visit
--   rule that is not the figure that matters: a friend referred earlier can
--   count, and one referred in the window who already visited before it
--   never will.
--
--   Two more things the Owner set the same day: a friend who was already a
--   paying customer before the promotion is not a new friend it is for; and
--   a visit through the centre's own QR link was dated by the date typed on
--   the form, which a customer can fill in as they like, rather than the day
--   the form was actually sent.
--
-- THE RULES (the Owner, 8 Oct 2026, final)
--
--   1. A Tier 1 friend counts for their referrer when the friend's first
--      visit for the promotion (rule 6) is within the promotion's window
--      (starts_on to ends_on), whatever their referral date: a friend
--      referred in August who first visits in October counts.
--   2. The referral must be recorded by the end of the window: the
--      Singapore date of coalesce(referred_at, created_at) is on or before
--      ends_on. A referrer set after the window (in November, say) does not
--      raise that promotion's count.
--   3. The report lists, for each referrer, the friends who count (1 and 2)
--      and the friends referred in the window (the same Singapore date
--      within it) who have not visited yet (no visit at all), shown as not
--      counted: "Not yet visited" while the promotion runs; after it ends,
--      that they did not visit during it. Friends who fit neither (a first
--      visit before the window, say, or one after it) are not listed. The
--      referrers listed are those with at least one friend listed.
--   4. Everything else is as it was: the tiers, the highest tier only,
--      rewards only after the window ends and for the tier reached under
--      this count, Owner/Manager only, the portal showing the signed-in
--      affiliate's own counts and no names. The visit rule itself (which
--      surveys are visits, and the first visit the Customers page shows:
--      customer_centre_visits) does not change.
--   5. A past customer never counts and is not listed (neither as counted
--      nor as not yet visited): a friend with an invoice, not deleted, whose
--      status shows money was taken, paid or partially_paid, and whose
--      business date (else the Singapore date it was created: 200 older
--      invoices on production have no business date) is before the window's
--      first day. These do NOT make a past customer: cancelled, refunded,
--      unpaid, draft and FOC (completed_foc) invoices, nor a request to
--      cancel or refund that is still waiting (cancellation_requested,
--      refund_requested; production, 8 Oct 2026: none). An invoice dated in
--      the window excludes nobody. The invoice is read as it is now, by its
--      date and its status, not by the day it was paid (paid_at) or its
--      amount: one dated before the window and paid during it makes a past
--      customer, and so does a S$0 invoice marked paid. Production, 8 Oct
--      2026: 5 paid or part-paid invoices are dated before October and were
--      paid in it, and 2 paid invoices are for S$0; none of them is the only
--      such invoice of a Tier 1 friend, so reading them otherwise would
--      change nobody today. Production, 8 Oct 2026: 20 of the 73 Tier
--      1 friends are past customers, but none of them is a friend the
--      October promotion would list, so this removes nobody today; none of
--      the 73 has an FOC invoice dated before October, alone or beside a paid
--      one, so counting FOC as well would remove nobody today either.
--   6. A visit through the centre's own link (the public form; visit kind
--      centre_link) counts for the promotion on the Singapore day the form
--      was sent (health_surveys.submitted_at), never on the date typed on it
--      (signed_date). A consultant's visit and an event survey's later visit
--      keep their dates (they come from system timestamps). A friend's first
--      visit for the promotion is the earliest of all their visits dated
--      this way, not the Customers page's first visit re-dated: one whose
--      earliest visit by the date typed is a form sent later than a
--      consultant's visit is dated by the consultant's visit. So it can be
--      earlier or later than the Customers page's first visit, which keeps
--      the date on the form. Production, 8 Oct 2026: no form's sending day
--      differs from its signed date, so this re-dates nobody today (and
--      production holds one survey per customer, uq_health_survey_customer).
--
--   Production, 8 Oct 2026, the October promotion under rules 1 to 6: 9
--   friends listed for 5 referrers; 6 counted (3 of them referred before
--   October), for 3 referrers; 3 referred in October not yet visited.
--
-- WHAT THIS DOES
--
--   * customer_centre_visit_days() (new; internal, the service role's
--     alone, 339; no overload): the visit rule, moved out of
--     customer_centre_visits word for word: one row for every survey that
--     is a visit, with the customer, the survey, its kind, its date under
--     the rule (visit_on, the Customers page's date), when it was submitted
--     (submitted_at) and the Singapore day of that (sent_on, the day a
--     public form was sent). The rule is written there and nowhere else.
--   * customer_centre_visits() (replaced whole; internal, its grants kept):
--     each customer's earliest row of customer_centre_visit_days, picked in
--     the same order as before (the visit's date, then when the survey was
--     submitted, then its id). Same columns, same rows: tested on every
--     fixture against the version before this, and on production on 8 Oct
--     2026 the new picking run inline gave the same 164 rows as
--     customer_centre_visits(), 0 different either way. search_customers
--     and customer_downline_visits read it and are not changed.
--   * referral_campaign_friends(promotion) (replaced whole; internal, the
--     service role's alone, as before): the same columns. Its rows are rule
--     3's list without the past customers (rule 5); counted is rules 1 and
--     2. first_visit_on is now the first visit for the promotion (rule 6),
--     read from customer_centre_visit_days; it is null exactly for the
--     friends not yet visited, who are the only ones not counted.
--     referred_on is still the referral's Singapore date (else the
--     customer's creation), now possibly before the window. It is still the
--     one place the counting is written: the report, the reward and the
--     portal read it. As rule 3 says, a friend referred in the window is
--     listed only while they have no visit at all: one who first visits
--     after the window ends is listed (not counted) until that visit, then
--     not at all, so the friends not counted can still go down after the
--     end. The friends counted, and so the reward, do not move with that;
--     like any change to a referral or a survey, an invoice of the friend's
--     dated (or re-dated) before the window later still moves them (rule 5).
--   * referral_campaign_report(promotion) (patched; Owner/Manager, as
--     before): each referrer also carries not_yet_visited, the friends
--     referred in the window who have not visited yet (the page's second
--     figure, in place of "referred in the window"). referred_in_window is
--     still sent, for the page live before this: it is now the friends
--     listed who were referred in the window (398: every friend referred in
--     the window, all of whom it listed). The referrers, the friends and the
--     standing come from referral_campaign_friends as before, so they follow
--     the new rules, and each friend's first_visit_on is the promotion's.
--   * affiliate_portal_campaign_progress() (patched; the signed-in affiliate
--     alone, as before): also not_yet_visited, and referred_in_window as the
--     report gives it. Counts only, no names. Past customers are in neither.
--   * give_referral_campaign_reward is not changed: it counts
--     referral_campaign_friends' counted at the moment it is called, so a
--     reward is for the tier reached under the new count.
--
-- NOT CHANGED
--
--   * Which surveys are visits and the first visit every screen shows
--     (customer_centre_visits' rows; search_customers' Visited filter and
--     first visit date; the downline's visits), the referral date and its
--     trigger (tg_customers_referral_date: a staff login cannot write a
--     referral date, so rule 2 holds), referral_campaign_standing (the
--     tiers), give_referral_campaign_reward, void_referral_campaign_reward,
--     the 'provisional' / 'final' / 'not_started' status, and which
--     promotion the report and the portal show.
--   * No table, column, row or index. The one new grant is the service
--     role's on customer_centre_visit_days. No reward has been given
--     (production, 8 Oct 2026: none recorded), so none was given under the
--     old count.
--   * The report's and the portal's keys: every key they returned is still
--     there; not_yet_visited is added.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block),
-- so it is atomic however it is run. Every guard and anchor is checked, and
-- every new text built, before anything is installed. md5(pg_get_
-- functiondef) of each changed function must be the production version read
-- on 8 Oct 2026 (BEFORE), or already this migration's version (AFTER), which
-- is left alone so a re-run changes nothing; customer_centre_visit_days must
-- be missing or already this version (any other text refuses). The functions
-- relied on but not changed must be the versions read on 8 Oct 2026, the
-- referral-date trigger must be on customers, and the invoice statuses must
-- be the nine read on 8 Oct 2026 (a new one would need the Owner to say
-- whether it means money was taken). Every anchor must match exactly once.
-- The new texts are executed as CREATE OR REPLACE with the same arguments
-- and result types, which keeps owner and grants; no overload is added
-- (another function of any of the five names refuses). The new function is
-- revoked from public, anon and authenticated and granted to service_role
-- (339), as customer_centre_visits is. The definitions are read and compared
-- with the search path set to public. After installing, the five functions
-- must have their AFTER md5 and the grants they had:
-- customer_centre_visit_days, customer_centre_visits and
-- referral_campaign_friends the service role's alone (the new one's grants
-- exactly customer_centre_visits'); the report and the portal's progress
-- signed-in logins' and the service role's (each checks who is asking),
-- none callable signed out. No data changes.
--
-- BEFORE (production, 8 Oct 2026, md5 of pg_get_functiondef; 398's AFTER):
--   customer_centre_visits()                                  05b4a9bb5fb955f4c00b62e4966c96d2
--   referral_campaign_friends(uuid)                           6e88ab96e57e661d8a06eabb41e65874
--   referral_campaign_report(text)                            b791ae0aa41975da55a66fc488df64cb
--   affiliate_portal_campaign_progress()                      7548c77bb887aec7227540ef15a0f14b
--   customer_centre_visit_days()                              (missing)
--   (relied on, not changed)
--   give_referral_campaign_reward(text,uuid,uuid,jsonb,text)  db5bae60bc6bf65d2ae206a031ff62eb
--   referral_campaign_standing(integer[],integer)             43e8860ba8fade528ded701cfbeea12f
--   search_customers(text,text,integer,integer,text,date,date) df63c717eab1825017e2567679f3e135
--   customer_downline_visits(uuid)                            1125dc56d3964c4b54a61ce88448ad65
--   tg_customers_referral_date()                              5ea2010a7b31efd4db32474723f814f6
--   sg_today()                                                1c1289f18e24d8370e9a6364c9c06fca
--   is_owner_or_manager()                                     125dec10ce33b84ff5fb40a9bd455235
--   current_affiliate_customer_id()                           51695acf5f26ce3918d6003d0c980b0f
-- AFTER (for later guards):
--   customer_centre_visit_days()                              2129857d6ff9f29dcf2cbccc9f13e5bc
--   customer_centre_visits()                                  c07a5a0cbbf52ba45e5dc911b20002da
--   referral_campaign_friends(uuid)                           1e1b7dd4fca94364b1c840915c1f61db
--   referral_campaign_report(text)                            d09b6aa2147125d9d4571de774fa1bcf
--   affiliate_portal_campaign_progress()                      f80c238a0bcf14de9463a26db3b12bc1
--
-- DEPLOY ORDER: this, then the page, straight after (pushing to main deploys
-- it). The page live now keeps working: the report still sends
-- referred_in_window, and every friend it lists as not counted has no visit,
-- which it already shows as "No visit yet". Until the new page is out it
-- is wrong in two ways: its rule text and the portal's still state 398's
-- rule (referred in the window) beside friends counted who were referred
-- earlier, and say nothing of past customers or of a form dated the day it
-- was sent (its "First visit" for a friend is the promotion's); and its
-- "{n} referred in the window" counts only the friends listed who were
-- referred in the window, so it leaves out one referred in the window who
-- first visited before it, or is a past customer (production, 8 Oct 2026:
-- none). The new page against a database without this reads
-- not_yet_visited when it is sent, else counts the friends listed without a
-- visit; its portal line about friends not yet visited shows only when the
-- figure is sent. But its rule text and the portal's would state these
-- rules while the counts are still 398's (referred in the window, past
-- customers counted, a form dated by the date typed on it), which is why
-- this goes first.
--
-- Test: scripts/referrals/tests/visits-and-october.sql (398, then this).

set lock_timeout = '5s';

do $mig$
declare
  -- ── The visit rule, moved out of customer_centre_visits word for word ──────
  c_days_def constant text := $def$
create or replace function public.customer_centre_visit_days()
returns table(customer_id uuid, survey_id uuid, visit_kind text, visit_on date,
              submitted_at timestamptz, sent_on date)
language sql
stable
security definer
set search_path = public
as $fn$
  -- 398: THE rule for "visited the centre" and its date (the Owner, 6 Oct
  -- 2026); 404 moved it here from customer_centre_visits, unchanged, so the
  -- rule is written in one place. customer_centre_visits picks each
  -- customer's first visit from these rows, as before; a referral promotion
  -- reads them itself (referral_campaign_friends).
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
  -- One row for every such survey: visit_on is its date under the rule (the
  -- date the Customers page shows), submitted_at when the survey was
  -- submitted (or the consultant's record made), and sent_on the Singapore
  -- day of that: for (1), the day the form was sent, which a referral
  -- promotion dates the visit by (the Owner, 8 Oct 2026), never the date
  -- typed on the form.
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
  select q.customer_id, q.id, q.kind, q.visit_on, q.submitted_at,
         (q.submitted_at at time zone 'Asia/Singapore')::date
    from q
   where q.visit_on is not null
$fn$
$def$;

  -- ── Each customer's first visit, picked from those rows as before ──────────
  c_visits_def constant text := $def$
create or replace function public.customer_centre_visits()
returns table(customer_id uuid, first_visit_on date, survey_id uuid, visit_kind text)
language sql
stable
security definer
set search_path = public
as $fn$
  -- 398: THE rule for "visited the centre" and its date (the Owner, 6 Oct
  -- 2026). Every screen reads a customer's first visit from here.
  -- 404: the rule itself is written in customer_centre_visit_days, unchanged
  -- (one row for every survey that is a visit, with its date). One row per
  -- customer: the earliest such survey, picked exactly as before (its date,
  -- then when the survey was submitted, then its id).
  select distinct on (d.customer_id) d.customer_id, d.visit_on, d.survey_id, d.visit_kind
    from public.customer_centre_visit_days() d
   order by d.customer_id, d.visit_on, d.submitted_at, d.survey_id
$fn$
$def$;

  -- ── The counting, replaced whole ───────────────────────────────────────────
  c_friends_def constant text := $def$
create or replace function public.referral_campaign_friends(p_campaign_id uuid)
returns table(referrer_customer_id uuid, friend_customer_id uuid, referred_on date,
              first_visit_on date, counted boolean)
language sql
stable
security definer
set search_path = public
as $fn$
  -- 404: a referral promotion's counting (the Owner, 8 Oct 2026), the only
  -- place it is written. A Tier 1 friend (customers.referred_by, the
  -- referrer not deleted) counts for their referrer when their first visit
  -- for the promotion (below) is in the window, whenever they were referred,
  -- as long as the referral was recorded by the window's last day: a
  -- referrer set after the window does not raise its count. The referral's
  -- date is the Singapore date of referred_at, else of created_at for older
  -- links without a date. The rows are the friends who count and, not
  -- counted, the friends referred in the window who have not visited yet (no
  -- visit at all). Nobody else is listed: not a friend whose first visit is
  -- before the window or after it, nor one referred after it. A Tier 2
  -- friend is nobody's Tier 1 here and counts for no one but their own
  -- referrer. (398 counted only friends referred in the window and listed
  -- every one of them.)
  -- A past customer is neither counted nor listed: a friend with an invoice,
  -- not deleted, whose status shows money was taken (paid or
  -- partially_paid) and whose business date, else the Singapore date it was
  -- created, is before the window's first day. Cancelled, refunded, unpaid,
  -- draft and FOC invoices, and a request to cancel or refund, do not make a
  -- past customer.
  -- The first visit for the promotion is the earliest of the friend's visits
  -- (customer_centre_visit_days, the visit rule), each on its own date,
  -- except that a visit through the centre's own link counts on the
  -- Singapore day the form was sent, never the date typed on it. It can
  -- differ from the first visit the Customers page shows
  -- (customer_centre_visits), which keeps the date on the form.
  with v as (
    select d.customer_id,
           min(case when d.visit_kind = 'centre_link' then d.sent_on else d.visit_on end) as first_visit_on
      from public.customer_centre_visit_days() d
     group by d.customer_id
  ),
  f as (
    select c.referred_by, c.id,
           (coalesce(c.referred_at, c.created_at) at time zone 'Asia/Singapore')::date as referred_on,
           v.first_visit_on, rc.starts_on, rc.ends_on
      from public.referral_campaigns rc
      join public.customers c on c.deleted_at is null and c.referred_by is not null
      join public.customers r on r.id = c.referred_by and r.deleted_at is null
      left join v on v.customer_id = c.id
     where rc.id = p_campaign_id
       and not exists (select 1 from public.invoices i
                        where i.customer_id = c.id and i.deleted_at is null
                          and i.status in ('paid', 'partially_paid')
                          and coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date)
                              < rc.starts_on)
  ),
  k as (
    select f.*, coalesce(f.first_visit_on between f.starts_on and f.ends_on
                         and f.referred_on <= f.ends_on, false) as counts
      from f
  )
  select k.referred_by, k.id, k.referred_on, k.first_visit_on, k.counts
    from k
   where k.counts
      or (k.first_visit_on is null and k.referred_on between k.starts_on and k.ends_on)
$fn$
$def$;

  -- ── Anchors and their replacements ─────────────────────────────────────────
  c_report_head_a constant text :=
       E'-- (else the first). Every referrer with a friend referred in the window:\n'
    || E'-- friends counted, tier reached, next tier, the reward if given, and each\n'
    || E'-- friend (the drill-down). "provisional" until the window has ended.\n';
  c_report_head_r constant text :=
       E'-- (else the first). Every referrer with a friend listed (404: one who\n'
    || E'-- counts, or one referred in the window who has not visited yet; see\n'
    || E'-- referral_campaign_friends): friends counted, friends not yet visited,\n'
    || E'-- tier reached, next tier, the reward if given, and each friend (the\n'
    || E'-- drill-down). "provisional" until the window has ended.\n';
  c_report_per_a constant text :=
       E'    select f.referrer_customer_id as rid, (count(*) filter (where f.counted))::int as counted,\n'
    || E'           count(*)::int as referred\n';
  c_report_per_r constant text :=
       E'    -- 404: beside the friends counted, the friends referred in the window\n'
    || E'    -- who have not visited yet (the Owner, 8 Oct 2026). referred_in_window,\n'
    || E'    -- kept for the page before 404, is the friends listed who were referred\n'
    || E'    -- in the window.\n'
    || E'    select f.referrer_customer_id as rid, (count(*) filter (where f.counted))::int as counted,\n'
    || E'           (count(*) filter (where f.first_visit_on is null))::int as not_yet_visited,\n'
    || E'           (count(*) filter (where f.referred_on between rc.starts_on and rc.ends_on))::int as referred\n';
  c_report_keys_a constant text :=
       E'             ''counted'', per.counted, ''referred_in_window'', per.referred)\n';
  c_report_keys_r constant text :=
       E'             ''counted'', per.counted, ''not_yet_visited'', per.not_yet_visited,\n'
    || E'             ''referred_in_window'', per.referred)\n';

  c_portal_decl_a constant text :=
       E'  v_today date := public.sg_today(); v_count int; v_ref int; w public.referral_campaign_rewards%rowtype;\n';
  c_portal_decl_r constant text :=
       E'  v_today date := public.sg_today(); v_count int; v_ref int; w public.referral_campaign_rewards%rowtype;\n'
    || E'  v_waiting int;  -- 404: friends referred in the window who have not visited yet\n';
  c_portal_count_a constant text :=
       E'  select (count(*) filter (where f.counted))::int, count(*)::int into v_count, v_ref\n'
    || E'    from public.referral_campaign_friends(rc.id) f where f.referrer_customer_id = v_me;\n';
  c_portal_count_r constant text :=
       E'  -- 404: the friends counted, the friends referred in the window who have\n'
    || E'  -- not visited yet, and (kept for the page before 404) the friends listed\n'
    || E'  -- who were referred in the window (the Owner, 8 Oct 2026).\n'
    || E'  select (count(*) filter (where f.counted))::int, (count(*) filter (where f.first_visit_on is null))::int,\n'
    || E'         (count(*) filter (where f.referred_on between rc.starts_on and rc.ends_on))::int\n'
    || E'    into v_count, v_waiting, v_ref\n'
    || E'    from public.referral_campaign_friends(rc.id) f where f.referrer_customer_id = v_me;\n';
  c_portal_keys_a constant text :=
       E'      ''counted'', v_count, ''referred_in_window'', v_ref,\n';
  c_portal_keys_r constant text :=
       E'      ''counted'', v_count, ''not_yet_visited'', v_waiting, ''referred_in_window'', v_ref,\n';

  c_days_after constant text := '2129857d6ff9f29dcf2cbccc9f13e5bc';
  c_visits_after constant text := 'c07a5a0cbbf52ba45e5dc911b20002da';
  c_friends_after constant text := '1e1b7dd4fca94364b1c840915c1f61db';
  c_report_after constant text := 'd09b6aa2147125d9d4571de774fa1bcf';
  c_portal_after constant text := 'f80c238a0bcf14de9463a26db3b12bc1';
  -- The invoice statuses read on 8 Oct 2026; rule 5 counts paid and
  -- partially_paid alone as money taken.
  c_statuses constant text :=
    'draft,unpaid,partially_paid,paid,cancellation_requested,cancelled,refund_requested,refunded,completed_foc';

  v_path text := current_setting('search_path');
  r record; d text; v text; n int; k int; i int; v_bad text; v_new_days boolean := false;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 8 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and new texts: nothing is installed unless all pass ────
  -- In install order: the rule, the first visit that reads it, the counting
  -- that reads it, then what reads the counting.
  for r in select * from (values
    ('customer_centre_visit_days()', null::text, c_days_after, c_days_def, null::text[]),
    ('customer_centre_visits()', '05b4a9bb5fb955f4c00b62e4966c96d2', c_visits_after, c_visits_def, null::text[]),
    ('referral_campaign_friends(uuid)', '6e88ab96e57e661d8a06eabb41e65874', c_friends_after, c_friends_def, null::text[]),
    ('referral_campaign_report(text)', 'b791ae0aa41975da55a66fc488df64cb', c_report_after, null::text,
     array[[c_report_head_a, c_report_head_r], [c_report_per_a, c_report_per_r], [c_report_keys_a, c_report_keys_r]]),
    ('affiliate_portal_campaign_progress()', '7548c77bb887aec7227540ef15a0f14b', c_portal_after, null::text,
     array[[c_portal_decl_a, c_portal_decl_r], [c_portal_count_a, c_portal_count_r], [c_portal_keys_a, c_portal_keys_r]])
  ) x(fn, before_md5, after_md5, whole, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      if r.before_md5 is not null then
        raise exception '404: public.% is missing', r.fn; end if;
      -- The new function, not there yet.
      v_new_days := true;
      v_fns := v_fns || r.fn;
      v_defs := v_defs || r.whole;
      continue;
    end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '404: public.% is already this version; left alone', r.fn;
      continue;
    elsif r.before_md5 is null then
      raise exception '404: public.% already exists with another text (md5 %). Re-read it and re-test before applying.', r.fn, v;
    elsif v <> r.before_md5 then
      raise exception '404: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    if r.edits is null then
      d := r.whole;
    else
      for k in 1 .. array_length(r.edits, 1) loop
        n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
        if n <> 1 then
          raise exception '404: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
        d := replace(d, r.edits[k][1], r.edits[k][2]);
      end loop;
    end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;
  -- Relied on, not changed: the versions read on 8 Oct 2026 (the reward,
  -- which counts the friends counted; the tiers; the Customers page's search
  -- and the downline, which read customer_centre_visits, whose rows do not
  -- change; the referral date, which a staff login cannot write, so a
  -- referrer set after the window is dated after it; today in Singapore;
  -- who is asking).
  for r in select * from (values
    ('give_referral_campaign_reward(text,uuid,uuid,jsonb,text)', 'db5bae60bc6bf65d2ae206a031ff62eb'),
    ('referral_campaign_standing(integer[],integer)', '43e8860ba8fade528ded701cfbeea12f'),
    ('search_customers(text,text,integer,integer,text,date,date)', 'df63c717eab1825017e2567679f3e135'),
    ('customer_downline_visits(uuid)', '1125dc56d3964c4b54a61ce88448ad65'),
    ('tg_customers_referral_date()', '5ea2010a7b31efd4db32474723f814f6'),
    ('sg_today()', '1c1289f18e24d8370e9a6364c9c06fca'),
    ('is_owner_or_manager()', '125dec10ce33b84ff5fb40a9bd455235'),
    ('current_affiliate_customer_id()', '51695acf5f26ce3918d6003d0c980b0f')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '404: public.% is missing or not the version read on 8 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.customers'::regclass and t.tgname = 'trg_customers_referral_date'
                    and not t.tgisinternal and t.tgenabled = 'O') then
    raise exception '404: the referral-date trigger is not on public.customers'; end if;
  if (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e
       where e.enumtypid = 'public.invoice_status'::regtype) is distinct from c_statuses then
    raise exception '404: the invoice statuses are not the ones read on 8 Oct 2026 (%). Ask the Owner which of them mean money was taken.',
      (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e
        where e.enumtypid = 'public.invoice_status'::regtype); end if;
  -- No other function takes these names (the API picks an overload by name).
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('customer_centre_visit_days', 'customer_centre_visits', 'referral_campaign_friends',
                                'referral_campaign_report', 'affiliate_portal_campaign_progress')
              and p.oid::regprocedure::text not in ('customer_centre_visit_days()', 'customer_centre_visits()',
                                                    'referral_campaign_friends(uuid)', 'referral_campaign_report(text)',
                                                    'affiliate_portal_campaign_progress()')) then
    raise exception '404: another overload of customer_centre_visit_days, customer_centre_visits, referral_campaign_friends, referral_campaign_report or affiliate_portal_campaign_progress exists'; end if;
  select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text) into v_acl
    from pg_proc p where p.oid in ('public.customer_centre_visits()'::regprocedure,
                                   'public.referral_campaign_friends(uuid)'::regprocedure,
                                   'public.referral_campaign_report(text)'::regprocedure,
                                   'public.affiliate_portal_campaign_progress()'::regprocedure);

  -- ── Install: the rule first, then what reads it ───────────────────────────
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;
  if v_new_days then
    revoke all on function public.customer_centre_visit_days() from public, anon, authenticated;
    grant execute on function public.customer_centre_visit_days() to service_role;
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('customer_centre_visit_days()', c_days_after),
    ('customer_centre_visits()', c_visits_after),
    ('referral_campaign_friends(uuid)', c_friends_after),
    ('referral_campaign_report(text)', c_report_after),
    ('affiliate_portal_campaign_progress()', c_portal_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '404: installed with md5s other than the tested ones: %', v_bad; end if;
  -- The grants they had: the rule, the first visit and the counting are
  -- internal (the service role's alone, the new rule's exactly as the first
  -- visit's); the report and the portal's progress are signed-in logins'
  -- (each checks who is asking) and the service role's; none is callable
  -- signed out.
  if (select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p where p.oid in ('public.customer_centre_visits()'::regprocedure,
                                       'public.referral_campaign_friends(uuid)'::regprocedure,
                                       'public.referral_campaign_report(text)'::regprocedure,
                                       'public.affiliate_portal_campaign_progress()'::regprocedure))
     is distinct from v_acl then
    raise exception '404: the grants of the changed functions changed'; end if;
  if (select p.proacl::text from pg_proc p where p.oid = 'public.customer_centre_visit_days()'::regprocedure)
     is distinct from (select p.proacl::text from pg_proc p where p.oid = 'public.customer_centre_visits()'::regprocedure)
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                 where p.oid = 'public.customer_centre_visit_days()'::regprocedure and a.grantee = 0) then
    raise exception '404: public.customer_centre_visit_days() is not granted exactly as customer_centre_visits()'; end if;
  foreach v in array array['customer_centre_visit_days()', 'customer_centre_visits()', 'referral_campaign_friends(uuid)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '404: public.% is not the service role''s alone', v; end if;
  end loop;
  foreach v in array array['referral_campaign_report(text)', 'affiliate_portal_campaign_progress()'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '404: public.% is not signed-in logins'' and the service role''s alone', v; end if;
  end loop;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
