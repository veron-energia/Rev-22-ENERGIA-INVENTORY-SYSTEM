-- 392_referral_booking_names_the_affiliate.sql
--
-- WHAT THE OWNER ASKED (5 Oct 2026)
--
-- An appointment booked through an affiliate's referral link should show the
-- affiliate first in the calendar. cal.com's title for the free giveaway is
--
--   John Lim +6591234567 Rev22 Energia Recharge Centre … FREE Therapies and eBooks Giveaway Bundle …
--
-- and for somebody who registered through Jane Tan's link it should read
--
--   (Jane Tan) John Lim +6591234567 Rev22 Energia Recharge Centre … FREE Therapies …
--
-- Staff were typing the bracket in by hand, not always with the referrer's
-- name. (The names here are invented.)
--
-- HOW (the Owner's choice, 5 Oct 2026: cal.com only)
--
-- cal.com builds the calendar title from the event type's "Calendar event
-- name". The free giveaway gets a hidden booking question, `affiliate`, and
-- its title starts with {affiliate}. The referral page (/r/<code>) now sends a
-- new registration straight to that booking page with their details and
-- "(Jane Tan) " filled in, instead of to energia.sg/ty. For that the page needs
-- the referrer's name, which only the database has:
-- public_affiliate_referral_info gives a signed-out visitor the first name only.
-- The name goes to the person who has just registered under that referrer, in
-- answer to that registration; the Owner accepted that the customer sees it in
-- cal.com's own confirmation and reminders.
--
-- WHAT THIS DOES
--
--   * affiliate_calendar_label(text): a customer's name as it is printed on a
--     booking. Staff keep notes in brackets inside full_name ("(intern)", the
--     branch, an event code), so bracketed notes and stray brackets are
--     dropped, as are { } and $, which mean something to cal.com's title
--     template, and the spaces are tidied. A name with nothing left is null.
--     Reached only from inside affiliate_referral_signup (339: service_role
--     only).
--   * affiliate_referral_signup: a registration that created a customer now
--     answers { ok, outcome: 'registered', message, affiliate_label }.
--     affiliate_label is the referrer's label. outcome is what 319 meant to
--     add: its replace landed on the honeypot's reply, so a real registration
--     never named its outcome. scripts/affiliate-signup/tests/
--     referral-and-states.sql expects one, but its check let a missing
--     outcome through; booking-label.sql compares the whole reply.
--
-- NOT CHANGED
--
--   * Who is registered, under whom, and every other reply: the honeypot,
--     already registered, a link not accepting registrations, self-referral,
--     too many attempts and the exceptions.
--   * public_affiliate_referral_info: still the first name only.
--   * Customers linked to an affiliate by staff, people already registered,
--     and later bookings from a plain cal.com link: no affiliate in the title
--     (the Owner, 5 Oct 2026).
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block), so
-- it is atomic however it is run. The guard and the anchor are checked, and the
-- patched text built, before anything is installed. md5(pg_get_functiondef)
-- of affiliate_referral_signup must be the production version read on 5 Oct
-- 2026 (BEFORE), or already this migration's version (AFTER), which is left
-- alone so a re-run changes nothing. An affiliate_calendar_label that is not
-- this one refuses. After installing, both must have their AFTER md5 and the
-- grants are checked. The patch is executed as CREATE OR REPLACE, which keeps
-- owner and grants. Functions only; no data changes.
--
-- BEFORE (production, 5 Oct 2026, md5 of pg_get_functiondef):
--   affiliate_referral_signup(text,text,text,text,text,text)  56be564ea5fccf831b7752ff164b2e0d
-- AFTER (for later guards):
--   affiliate_referral_signup(text,text,text,text,text,text)  5b8363a3f87a4c89f2866f3ba0f32b55
--   affiliate_calendar_label(text)                            af4eecdcf978c19b3effb6af3a897165
--
-- Test: scripts/affiliate-signup/tests/booking-label.sql.

set lock_timeout = '5s';

do $mig$
declare
  c_signup constant text := 'public.affiliate_referral_signup(text,text,text,text,text,text)';
  c_label constant text := 'public.affiliate_calendar_label(text)';
  c_before constant text := '56be564ea5fccf831b7752ff164b2e0d';
  c_after constant text := '5b8363a3f87a4c89f2866f3ba0f32b55';
  c_label_after constant text := 'af4eecdcf978c19b3effb6af3a897165';
  c_anchor constant text :=
       E'  return jsonb_build_object(''ok'', true, ''message'', ''Registration successful.'');\n';
  c_patch constant text :=
       E'  -- 392: the outcome, as 319 meant, and the referrer as a booking prints\n'
    || E'  -- them, which the referral page passes on to the booking page.\n'
    || E'  return jsonb_build_object(''ok'', true, ''outcome'', ''registered'',\n'
    || E'    ''message'', ''Registration successful.'',\n'
    || E'    ''affiliate_label'', (select public.affiliate_calendar_label(c.full_name)\n'
    || E'                          from public.customers c\n'
    || E'                         where c.id = v_ref_cust and c.deleted_at is null));\n';
  c_label_def constant text := $def$
create or replace function public.affiliate_calendar_label(p_full_name text)
returns text
language sql
immutable
set search_path = public
as $fn$
  -- 392: a customer's name as a booking prints it. Notes in brackets go,
  -- stray brackets and cal.com's template characters ({ } $) go, and one
  -- space separates the words. Nothing left is null.
  select nullif(btrim(regexp_replace(regexp_replace(regexp_replace(coalesce(p_full_name, ''),
           '(\([^()]*\)|\[[^][]*\])', ' ', 'g'),
           '[][(){}$]', '', 'g'),
           '\s+', ' ', 'g')), '')
$fn$
$def$;
  d text; v text; n int;
begin
  -- ── Guards, anchor and patched text: nothing is installed unless all pass ──
  if to_regprocedure(c_signup) is null then
    raise exception '392: % is missing', c_signup; end if;
  d := pg_get_functiondef(to_regprocedure(c_signup));
  v := md5(d);
  if v = c_after then
    raise notice '392: % already names the referrer; left alone', c_signup;
  elsif v <> c_before then
    raise exception '392: % is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_signup, v;
  else
    n := (length(d) - length(replace(d, c_anchor, ''))) / length(c_anchor);
    if n <> 1 then
      raise exception '392: the registration reply of % was found % times, not once', c_signup, n; end if;
    d := replace(d, c_anchor, c_patch);
  end if;
  if to_regprocedure(c_label) is not null
     and md5(pg_get_functiondef(to_regprocedure(c_label))) <> c_label_after then
    raise exception '392: a different % already exists (md5 %)', c_label,
      md5(pg_get_functiondef(to_regprocedure(c_label))); end if;

  -- ── Install ───────────────────────────────────────────────────────────────
  execute c_label_def;
  execute format('revoke all on function %s from public, anon, authenticated', c_label);
  execute format('grant execute on function %s to service_role', c_label);
  if v <> c_after then
    execute d;
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  v := md5(pg_get_functiondef(to_regprocedure(c_signup)));
  if v <> c_after then
    raise exception '392: % was installed with md5 %, not the tested %', c_signup, v, c_after; end if;
  v := md5(pg_get_functiondef(to_regprocedure(c_label)));
  if v <> c_label_after then
    raise exception '392: % was installed with md5 %, not the tested %', c_label, v, c_label_after; end if;
  if not has_function_privilege('anon', c_signup, 'execute') then
    raise exception '392: the referral page can no longer register anybody'; end if;
  if has_function_privilege('anon', c_label, 'execute')
     or has_function_privilege('authenticated', c_label, 'execute') then
    raise exception '392: % is callable by a client role', c_label; end if;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
