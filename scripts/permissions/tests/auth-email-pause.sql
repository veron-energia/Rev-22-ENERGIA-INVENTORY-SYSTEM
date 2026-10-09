-- 405: public affiliate sign-up and verification resends are paused; password
-- recovery is not. Disposable local database only; everything is rolled back.
--   psql -v ON_ERROR_STOP=1 -f scripts/permissions/tests/auth-email-pause.sql
\set ON_ERROR_STOP on
begin;
\ir ../../../supabase/405_pause_affiliate_signup.sql
\ir ../../../supabase/405_pause_affiliate_signup.sql
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
