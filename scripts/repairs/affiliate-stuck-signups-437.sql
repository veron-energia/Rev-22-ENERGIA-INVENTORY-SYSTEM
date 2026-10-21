-- One-off repair: switch on the affiliate sign-ups stuck before 437 (goes with
-- migration 437; the Owner's decisions of 20 Oct 2026, AFF-SIGNUP-5).
--
-- PROPOSED, NOT RUN. It changes who can sign in: run it only with the Owner's
-- go-ahead, after 437 is in and after reading its dry run.
--
-- WHAT IS WRONG
--
--   Before 437, Create Account on /affiliate/join made a Supabase Auth login
--   that could not sign in until its email link was opened. On 20 Oct 2026
--   (production, read only; counts only) 14 people who signed up had never
--   opened it: their logins are still unconfirmed, so Supabase refuses their
--   password ("Email not confirmed") and they cannot get in at all. (The 2
--   others stuck that day did confirm; they need nothing: their next sign-in
--   finishes the sign-up, as 437 decides.)
--
-- THE RULE (the Owner, 20 Oct 2026)
--
--   "The people stuck after signing up are let in on their next sign-in, like
--   a new sign-up." A new sign-up's login is made already confirmed, with its
--   email not yet verified by the app. So each of these logins is confirmed
--   the same way, and marked the same way (app_metadata
--   affiliate_email_unverified), so the app shows their email as not verified
--   until they verify it from the Account page. Their next sign-in then goes
--   to /affiliate/verify, which finishes the sign-up with the details they gave
--   (437's rules: the phone finds the customer, or a fresh record).
--
-- WHAT IT DOES (one DO block, so all of it or none)
--
--   For each login that is unconfirmed, made by the affiliate sign-up
--   (raw_user_meta_data signup_source = 'affiliate_join'), not deleted, not
--   banned, with no staff profile and no affiliate account:
--     * auth.users.email_confirmed_at := now() (confirmed_at follows it: it is
--       a generated column in Supabase Auth), and
--     * raw_app_meta_data gets "affiliate_email_unverified": true;
--     * one audit row ('affiliate_signup_switched_on', module 'affiliate')
--       naming the login, no email or name.
--   It touches no password, no name, phone or email, no customer, no claim
--   and nothing else. It prints counts only.
--
-- SAFETY
--
--   * A dry run unless the session says otherwise: it writes only after
--       set energia.repair_437 = 'apply';
--     (or select set_config('energia.repair_437', 'apply', false)) in the
--     same session. Otherwise it prints what it would do and changes nothing.
--   * It refuses, changing nothing, when 437 is not in (its column and list
--     table), or when the number of logins found is not the number expected:
--     14, as read on 20 Oct 2026. Re-check with the Owner and run again;
--     energia.repair_437_expected sets another number (the test uses it).
--   * A second run finds none and says the repair is done.
--
-- HOW TO RUN
--
--   As the database owner (the SQL editor, the MCP execute_sql tool, or psql
--   as postgres). First as it is (the dry run); then, with the go-ahead:
--     begin;
--     set local energia.repair_437 = 'apply';
--     <this file>
--     commit;
--
-- Test: scripts/repairs/tests/affiliate-stuck-signups-437.sql (fixtures only).

do $repair$
declare
  c_expected constant int := coalesce(nullif(current_setting('energia.repair_437_expected', true), '')::int, 14);
  v_apply boolean := coalesce(current_setting('energia.repair_437', true), '') = 'apply';
  v_ids uuid[]; v_done int; n int;
begin
  if to_regclass('public.affiliate_signup_matches') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public'
                     and table_name = 'affiliate_accounts' and column_name = 'email_verified_at') then
    raise exception '437 repair: apply migration 437 first'; end if;

  select coalesce(array_agg(u.id order by u.created_at, u.id), '{}'::uuid[]) into v_ids
    from auth.users u
   where u.email_confirmed_at is null and u.deleted_at is null
     and coalesce(u.raw_user_meta_data ->> 'signup_source', '') = 'affiliate_join'
     and (u.banned_until is null or u.banned_until <= now())
     and not exists (select 1 from public.profiles p where p.id = u.id)
     and not exists (select 1 from public.affiliate_accounts a where a.auth_user_id = u.id);
  select count(*) into v_done from public.audit_logs
   where action = 'affiliate_signup_switched_on' and module = 'affiliate';

  if cardinality(v_ids) = 0 then
    raise notice '437 repair: no stuck sign-up to switch on (% switched on by this repair before). Nothing changed.', v_done;
    return;
  end if;
  if cardinality(v_ids) <> c_expected then
    raise exception '437 repair: found % stuck sign-ups, expected %. Nothing changed; re-check with the Owner.',
      cardinality(v_ids), c_expected;
  end if;
  if not v_apply then
    raise notice '437 repair (dry run): % stuck sign-ups would be switched on (expected %). Nothing changed.',
      cardinality(v_ids), c_expected;
    return;
  end if;

  update auth.users u
     set email_confirmed_at = now(),
         raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb) || '{"affiliate_email_unverified": true}'::jsonb,
         updated_at = now()
   where u.id = any (v_ids) and u.email_confirmed_at is null;
  get diagnostics n = row_count;
  if n <> cardinality(v_ids) then
    raise exception '437 repair: % of % logins changed while it ran. Nothing changed; run again.', n, cardinality(v_ids); end if;

  insert into public.audit_logs (table_name, record_id, action, new_data, module, reason)
  select 'auth.users', x, 'affiliate_signup_switched_on',
         jsonb_build_object('auth_user_id', x, 'email_confirmed', true, 'affiliate_email_unverified', true, 'repair', '437'),
         'affiliate', 'Stuck affiliate sign-up let in (the Owner, 20 Oct 2026)'
    from unnest(v_ids) x;
  get diagnostics n = row_count;

  raise notice '437 repair: % stuck sign-ups switched on, % audit rows written.', cardinality(v_ids), n;
end $repair$;
