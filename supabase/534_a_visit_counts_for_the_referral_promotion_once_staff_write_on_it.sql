-- 534_a_visit_counts_for_the_referral_promotion_once_staff_write_on_it.sql
--
-- FOR THE REFERRAL PROMOTION, A VISIT COUNTS ONCE AN OWNER OR MANAGER HAS WRITTEN ON THE SURVEY
--
--   From the security audit of 17 Nov 2026 (finding M5).
--   The BEFORE md5 and the relied-on md5s below are those of production after 533 (530-533 went
--   live on 24 Nov 2026, head 20261124091324, function fingerprint dee55c68.../1447), read on a
--   copy of it on 25 Nov 2026; they are the same as after 529. 537 (the affiliate WhatsApp in two
--   messages) changes none of them, so this applies the same before or after it. If production
--   differs when this is applied, it refuses and changes nothing.
--   (The number 534 is this file's name and its errors' prefix; if it changes at commit, change it
--   there, in the 534 comment it writes into referral_campaign_friends (and so its AFTER md5, also
--   in scripts/referrals/undo-534.sql and in the suites that know it), and in the name and path of
--   its suite.)
--
-- WHAT WAS WRONG
--
--   A referred friend (customers.referred_by) counts for their referrer in a referral promotion once
--   their first visit is in the promotion's window (referral_campaign_friends, 404 and 425). The
--   visits are those of customer_centre_visit_days, and two of its kinds need nobody senior:
--   * a health form sent through one of the centre's own QR links ('centre_link'). Nothing ties
--     that form to the building: the link is a web address. So two signed-out calls per made-up
--     friend raised an affiliate's tier: the referral page /r/<code> (affiliate_referral_signup)
--     makes the friend with referred_by set, and the QR form through the centre's link
--     (submit_health_survey) attaches to that friend (at once before 530; once Staff attach it
--     since 530) and is a visit dated the day it was sent;
--   * a consultant's survey with any answer on it ('consultant'). A Staff login alone makes one:
--     upsert_consultant_survey(<friend>, p_smokes := false) makes a record with one yes/no answer,
--     and update_survey_particulars_v2 writes the same answers on a record already there.
--   The reward is stock an Owner or Manager hands over (give_referral_campaign_reward, for the
--   highest tier reached).
--
-- THE RULE (the user, 24 Nov 2026: "Same test for all")
--
--   1. A visit counts for the promotion once an Owner or Manager has written on the survey. That
--      holds for every kind of visit ('centre_link', 'consultant', 'event_then_centre'), and
--      "written" is any of:
--        (a) a saved review: health_surveys.reviewed_at is set, and at least one of the findings
--            acidity_result, remarks_condition, remarks_recommendation and health_goals is not
--            blank;
--        (b) a consultant_notes row on that survey with an acidity_result, health_goals,
--            remarks_condition or remarks_recommendation that is not blank, or with an attachments
--            array that is not empty (the test customer_centre_visit_days uses for its notes);
--        (c) a health_survey_attachments row on that survey.
--      A visit's date is as before: a form through the centre's link the day it was sent
--      (sent_on), any other the visit rule's date (visit_on). A visit with none of (a), (b) or (c)
--      is not a visit for the promotion: the friend's first visit for the promotion is their
--      earliest visit that counts. It applies to every promotion, past ones included. (An event's
--      form already needs a later note or file to be a visit, so nothing changes for it.)
--   2. Promotion only. referral_campaign_friends changes and nothing else: the visit rule
--      (customer_centre_visit_days), customer_centre_visits and every "Visited" screen (the
--      Customers page, downlines, bookings) stay as they are.
--
--   Why an Owner's or Manager's writing is enough: review_health_survey, add_consultant_note and
--   add_survey_attachment require an Owner or Manager; upsert_consultant_survey refuses the findings
--   to anyone else and sets reviewed_at only when it writes them; update_survey_particulars_v2
--   writes no finding (all five pinned below). The direct write rules on the three tables ask
--   is_owner_or_manager() and nothing more (checked below; 532 removed the last one, "update
--   surveys"). Nothing a signed-out caller can run writes reviewed_at, a finding, a note or a file,
--   and only those functions do for a signed-in one (the suite checks both).
--   On production (24 Nov 2026) every consultant visit ever (95, Aug-Nov) has such writing and no
--   promotion count changes.
--
-- WHAT THIS DOES
--
--   * referral_campaign_friends(uuid): one patch, found exactly once, in its first step (the CTE
--     v, each friend's first visit for the promotion): it keeps a row of customer_centre_visit_days()
--     only when (a), (b) or (c) holds for that row's survey. A comment marked "534 (security audit"
--     says so. The dates are as before. Its grants (the owner and the service role), its return
--     type, STABLE, SECURITY DEFINER and search_path are unchanged (CREATE OR REPLACE, no DROP).
--   * So, through it and unchanged themselves: referral_campaign_report(text) (the Owner's and
--     Managers' promotion page) counts and lists by the new rule; affiliate_portal_campaign_progress()
--     (the affiliate's own progress) counts by it; give_referral_campaign_reward(...) gives the tier
--     reached by it, and refuses a referrer whose friends counted by it are fewer than the first
--     tier. A friend whose only visit has no such writing is listed as not counted yet (first visit
--     none) when they were referred in the window, as a friend with no visit is.
--
-- WHAT STAYS
--
--   * The test counts writing, not seeing. Anything an Owner or Manager writes on a survey, even
--     "not seen", makes the visit count; staff should write nothing on a form they doubt.
--   * Deleting the only file of a survey (delete_survey_attachment), or the only note, takes the
--     visit away again for the promotion.
--   * A friend whose only earlier form has no such writing has no first visit before the window,
--     so a later visit counts them as new in it. Production has 7 such forms ever (3 in August, 3 in
--     September, 1 in October), and none touches a promotion.
--   * A finished promotion's count can still rise when a form sent in its window is written on
--     later, because the date stays the day it was sent (a held form attached late can already do
--     this). A consultant's visit keeps the visit rule's date, which can be the day of a Staff
--     answer before the Owner's or Manager's writing.
--   * customer_centre_visit_days(), customer_centre_visits() and every page that shows "Visited"
--     or a first visit (the Customers page, downlines, bookings, the affiliate's network): such a
--     visit is a visit there as before, dated as before. Only the promotion's screens say "not
--     counted yet" for it.
--   * The QR form, the referral page, the review, particulars, notes and attachments functions.
--   * Rewards already given (referral_campaign_rewards) stay as they are, with the tier and count
--     recorded when they were given; an Owner can still void one (void_referral_campaign_reward).
--   * The promotion's other rules (the window, the referral by its last day, past customers, the
--     shared-phone check of 425). No data changes.
--
-- UNDO
--
--   scripts/referrals/undo-534.sql (it refuses unless referral_campaign_friends is exactly 534's):
--   the function is put back exactly as it was (b5f4f76d7d22369ee4706a4b5f9dd465), by taking 534's
--   text out again. Every visit then counts for the promotion again, with or without an Owner's or
--   Manager's writing (the security audit's M5 open again). The pages need no undo for it to work;
--   their sentences would then say more than the count does. A later migration changing
--   referral_campaign_friends must pin 534's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/referrals/tests/staff-written-visit-counts-534.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the patched one relies on, as tested: the visit rule it reads (its rows, kinds and
  -- dates); the three that read the promotion's count through it (the report, the affiliate's
  -- progress, the reward); the writers of a review, a note and a file, Owner or Manager only,
  -- which make a visit count; the consultant's record, which keeps the findings (and reviewed_at)
  -- to an Owner or Manager, and the particulars, which write no finding; and the Owner-or-Manager
  -- test of the direct write rules.
  c_relied constant text[] := array[
    'customer_centre_visit_days()',
    'referral_campaign_report(text)',
    'give_referral_campaign_reward(text,uuid,uuid,jsonb,text)',
    'affiliate_portal_campaign_progress()',
    'review_health_survey(uuid,text,text,text,text,boolean)',
    'add_consultant_note(uuid,uuid,text,text,text,text,jsonb)',
    'add_survey_attachment(uuid,text,text,text,integer,text)',
    'upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)',
    'update_survey_particulars_v2(uuid,jsonb,text)',
    'is_owner_or_manager()'];
  c_relied_md5 constant text[] := array[
    '2129857d6ff9f29dcf2cbccc9f13e5bc',
    '018b34673b2f32fd146d8d5e9c791d1a',
    'db5bae60bc6bf65d2ae206a031ff62eb',
    'cc07104f1bda30a36468f615c9fbb410',
    '46bddd90d9badfae99cff53379275e64',
    'aea5303b89708bb9d1f2d5434b9b0813',
    'a856b3463d4e9c8784e2cf1e6d2b649b',
    'e5e6922d5fbe16ee81d44246cabd9d60',
    'c8df8ff415d633bd29a1d6cd752eff73',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8'];
  -- The function patched, its md5 before and after, its grants and its return type (unchanged).
  c_sig constant text := 'referral_campaign_friends(uuid)';
  c_before constant text := 'b5f4f76d7d22369ee4706a4b5f9dd465';
  c_after constant text := '59d2cf59d32a59f02bd8504b36707a20';
  c_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_result constant text :=
    'TABLE(referrer_customer_id uuid, friend_customer_id uuid, referred_on date, first_visit_on date, counted boolean)';
  -- The tables staff write on a survey; a write rule on them may only ask is_owner_or_manager().
  c_tables constant text[] := array['health_surveys', 'consultant_notes', 'health_survey_attachments'];
  c_oom constant text := '( SELECT is_owner_or_manager() AS is_owner_or_manager)';
  -- One patch, found exactly once: each friend's first visit for the promotion.
  c_anchor constant text := $a$  with v as (
    select d.customer_id,
           min(case when d.visit_kind = 'centre_link' then d.sent_on else d.visit_on end) as first_visit_on
      from public.customer_centre_visit_days() d
     group by d.customer_id
  ),
$a$;
  c_new constant text := $n$  -- 534 (security audit of 17 Nov 2026, M5; the user, 24 Nov 2026: "Same test for all"): a
  -- visit counts for the promotion once an Owner or Manager has written on the survey: (a) a saved
  -- review with a finding (reviewed_at set, and an acidity result, condition, recommendation or
  -- health goals that is not blank); (b) a consultant note on it with one of those four or an
  -- attachment (the test the visit rule uses for notes); or (c) a file attached to it. That holds
  -- for every kind of visit: a form through the centre's own link (nothing ties it to the
  -- building, so the referral page and then the QR form, both signed out, made a friend count), a
  -- consultant's survey (a Staff login alone could make one with a yes/no answer) and an event's
  -- form with a later note or file (which already has one). Until then the visit is not one here,
  -- and the friend's first visit for the promotion is the earliest visit that counts. The dates
  -- are as before. The visit rule (customer_centre_visit_days) and every "Visited" screen are
  -- unchanged.
  with v as (
    select d.customer_id,
           min(case when d.visit_kind = 'centre_link' then d.sent_on else d.visit_on end) as first_visit_on
      from public.customer_centre_visit_days() d
     where exists (select 1 from public.health_surveys hs
                    where hs.id = d.survey_id and hs.reviewed_at is not null
                      and coalesce(nullif(btrim(hs.acidity_result), ''), nullif(btrim(hs.remarks_condition), ''),
                                   nullif(btrim(hs.remarks_recommendation), ''), nullif(btrim(hs.health_goals), ''))
                          is not null)
        or exists (select 1 from public.consultant_notes n
                    where n.survey_id = d.survey_id
                      and (coalesce(nullif(btrim(n.acidity_result), ''), nullif(btrim(n.health_goals), ''),
                                    nullif(btrim(n.remarks_condition), ''), nullif(btrim(n.remarks_recommendation), ''))
                             is not null
                           or (jsonb_typeof(n.attachments) = 'array' and jsonb_array_length(n.attachments) > 0)))
        or exists (select 1 from public.health_survey_attachments f where f.survey_id = d.survey_id)
     group by d.customer_id
  ),
$n$;

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text; v_acl text; v_bad text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '534: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  for i in 1 .. cardinality(c_tables) loop
    if to_regclass('public.' || c_tables[i]) is null then
      raise exception '534: public.% is missing', c_tables[i]; end if;
    if not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || c_tables[i])::regclass) then
      raise exception '534: row level security is off on public.%', c_tables[i]; end if;
    select string_agg(p.policyname, ', ' order by p.policyname) into v_bad
      from pg_policies p
     where p.schemaname = 'public' and p.tablename = c_tables[i] and p.cmd in ('INSERT', 'UPDATE', 'ALL')
       and (p.roles is distinct from array['authenticated']::name[]
            or coalesce(p.qual, c_oom) <> c_oom or coalesce(p.with_check, c_oom) <> c_oom);
    if v_bad is not null then
      raise exception '534: public.% has a write rule that asks more than is_owner_or_manager() (%). Re-read it before applying.', c_tables[i], v_bad; end if;
  end loop;
  if to_regprocedure('public.' || c_sig) is null then raise exception '534: public.% is missing', c_sig; end if;
  v_def := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));
  if v_acl is distinct from c_acl then
    raise exception '534: the grants of public.% are not the tested ones (%). Re-read them before applying.', c_sig, v_acl; end if;
  if pg_get_function_result(to_regprocedure('public.' || c_sig)) is distinct from c_result then
    raise exception '534: public.% does not return what it was tested with. Re-read it before applying.', c_sig; end if;
  if md5(v_def) = c_after or position('534 (security audit' in v_def) > 0 then
    raise exception '534 is already in on this database; nothing was changed.'; end if;
  if md5(v_def) <> c_before then
    raise exception '534: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, c_anchor, ''))) / length(c_anchor) <> 1 then
    raise exception '534: its patch does not find its text exactly once in public.%', c_sig; end if;
  v_def := replace(v_def, c_anchor, c_new);
  if md5(v_def) <> c_after then
    raise exception '534: the patched text of public.% is not the tested one (md5 %)', c_sig, md5(v_def); end if;
  if position('534 (security audit' in v_def) = 0 then
    raise exception '534: the patched text of public.% has no 534 marker', c_sig; end if;

  -- 2. Install
  execute v_def;

  -- 3. Checks after installing
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '534: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from c_acl
     or has_function_privilege('anon', to_regprocedure('public.' || c_sig), 'execute')
     or has_function_privilege('authenticated', to_regprocedure('public.' || c_sig), 'execute') then
    raise exception '534: the grants of public.% changed', c_sig; end if;
  if pg_get_function_result(to_regprocedure('public.' || c_sig)) is distinct from c_result
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'referral_campaign_friends') <> 1 then
    raise exception '534: public.% changed its return type or has an overload', c_sig; end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '534: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
