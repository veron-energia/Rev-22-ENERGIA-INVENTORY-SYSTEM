-- 405: public affiliate sign-up and verification resends are paused; password
-- recovery is not. Disposable local database only; everything is rolled back.
--   psql -v ON_ERROR_STOP=1 -f scripts/permissions/tests/auth-email-pause.sql
\set ON_ERROR_STOP on
begin;
-- 531 (security audit of 17 Nov 2026, M6) changed auth_email_reserve, whose version 405 pins, so
-- 405 cannot run again where 531 is in: its pause rows are put in as 405 puts them, and the checks
-- below hold the same (the pause is still looked at first).
select position('-- 531 (security audit' in pg_get_functiondef('public.auth_email_reserve(text,text,text)'::regprocedure)) > 0 as has_531 \gset
\if :has_531
insert into public.auth_email_pauses (action, reason)
values ('signup', 'Public affiliate sign-up paused until the security fix is live (the Owner, 9 Oct 2026)'),
       ('resend', 'Verification resends paused with sign-up (the Owner, 9 Oct 2026)')
on conflict (action) do nothing;
\else
\ir ../../../supabase/405_pause_affiliate_signup.sql
\ir ../../../supabase/405_pause_affiliate_signup.sql
\endif
do $$
declare r jsonb; v_events_before bigint; v_events_after bigint;
begin
  select count(*) into v_events_before from public.auth_email_rate_events;
  -- signup and resend refuse before taking a slot
  begin
    perform public.auth_email_reserve('signup', 'test-email-hash-405', 'test-ip-hash-405');
    raise exception 'FAIL 1: signup was not refused';
  exception when others then
    if sqlerrm not like 'AUTH_EMAIL_PAUSED: signup%' then raise exception 'FAIL 1: unexpected error %', sqlerrm; end if;
  end;
  begin
    perform public.auth_email_reserve('resend', 'test-email-hash-405', null);
    raise exception 'FAIL 2: resend was not refused';
  exception when others then
    if sqlerrm not like 'AUTH_EMAIL_PAUSED: resend%' then raise exception 'FAIL 2: unexpected error %', sqlerrm; end if;
  end;
  select count(*) into v_events_after from public.auth_email_rate_events;
  if v_events_after <> v_events_before then raise exception 'FAIL 3: a paused request took a rate-limit slot'; end if;
  -- recovery still works as before
  r := public.auth_email_reserve('recovery', 'test-email-hash-405', 'test-ip-hash-405');
  if (r->>'allowed')::boolean is not true then raise exception 'FAIL 4: recovery was refused: %', r; end if;
  -- reopening is deleting the rows
  delete from public.auth_email_pauses where action in ('signup', 'resend');
  r := public.auth_email_reserve('signup', 'test-email-hash-405b', null);
  if (r->>'allowed')::boolean is not true then raise exception 'FAIL 5: signup still refused after reopening: %', r; end if;
  -- clients cannot read or change the pauses
  if has_table_privilege('authenticated', 'public.auth_email_pauses', 'delete')
     or has_table_privilege('anon', 'public.auth_email_pauses', 'select') then
    raise exception 'FAIL 6: a client role can reach auth_email_pauses'; end if;
  raise notice 'PASS: signup and resend paused (no slot taken), recovery open, reopening works, the pauses are server-only';
end $$;
rollback;
