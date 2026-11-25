-- UNDO of 534 (with the user's go-ahead). It puts referral_campaign_friends(uuid) back exactly as it
-- was before 534 (md5 b5f4f76d7d22369ee4706a4b5f9dd465), by taking 534's text out again. Afterwards
-- every visit counts for the referral promotion again, whether or not an Owner or Manager has
-- written on the survey: a form through the centre's QR link on the day it is sent, a consultant's
-- record with a Staff login's yes/no answer (the security audit's M5 open again). The report, the
-- affiliate's progress and the reward follow it, as they follow 534 now. Nothing written while 534
-- was in changes: a reward given stays with the tier and count recorded then.
--
-- The pages' sentences and "not counted yet" wording for 534 (ReferralPromotionPanel.tsx,
-- AffiliateNetworkPage.tsx, src/lib/referral/campaign.mjs) would then say more than the count does;
-- put back their text of before 534 too.
--
-- It refuses, with nothing changed, unless the function is exactly 534's (so a later version is
-- never overwritten) and its grants and return type are as tested. One transaction, all or
-- nothing; it waits at most 5 seconds for a lock. The 534 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row (found by
-- its name, 534_a_visit_counts_for_the_referral_promotion_once_staff_write_on_it) or record this
-- UNDO beside it.
do $undo$
declare
  c_sig constant text := 'referral_campaign_friends(uuid)';
  c_534 constant text := '59d2cf59d32a59f02bd8504b36707a20';
  c_before_534 constant text := 'b5f4f76d7d22369ee4706a4b5f9dd465';
  c_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_result constant text :=
    'TABLE(referrer_customer_id uuid, friend_customer_id uuid, referred_on date, first_visit_on date, counted boolean)';
  -- 534's text in the function, and what it replaced.
  c_534_text constant text := $n$  -- 534 (security audit of 17 Nov 2026, M5; the user, 24 Nov 2026: "Same test for all"): a
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
  c_old_text constant text := $a$  with v as (
    select d.customer_id,
           min(case when d.visit_kind = 'centre_link' then d.sent_on else d.visit_on end) as first_visit_on
      from public.customer_centre_visit_days() d
     group by d.customer_id
  ),
$a$;
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text; v_acl text;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  if to_regprocedure('public.' || c_sig) is null then raise exception 'undo 534: public.% is missing', c_sig; end if;
  v_def := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(v_def) = c_before_534 then
    raise exception 'undo 534: public.% is already as before 534; nothing was changed.', c_sig; end if;
  if md5(v_def) <> c_534 then
    raise exception 'undo 534: public.% is not 534''s version (md5 %). Nothing was changed.', c_sig, md5(v_def); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));
  if v_acl is distinct from c_acl
     or pg_get_function_result(to_regprocedure('public.' || c_sig)) is distinct from c_result then
    raise exception 'undo 534: the grants or the return type of public.% are not as tested (%). Nothing was changed.', c_sig, v_acl; end if;
  if (length(v_def) - length(replace(v_def, c_534_text, ''))) / length(c_534_text) <> 1 then
    raise exception 'undo 534: 534''s text is not found exactly once in public.%. Nothing was changed.', c_sig; end if;
  v_def := replace(v_def, c_534_text, c_old_text);
  if md5(v_def) <> c_before_534 then
    raise exception 'undo 534: public.% without 534''s text is not its version of before 534 (md5 %). Nothing was changed.', c_sig, md5(v_def); end if;

  -- 2. Put back
  execute v_def;

  -- 3. Checks after
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_before_534
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from c_acl
     or pg_get_function_result(to_regprocedure('public.' || c_sig)) is distinct from c_result then
    raise exception 'undo 534: public.% is not as before 534 after putting it back', c_sig; end if;
  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
