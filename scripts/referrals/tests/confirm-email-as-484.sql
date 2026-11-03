-- For the 484 suite on a database where 491 is in (included right after its begin, after my-network-as-484.sql).
--
-- 491 (3 Nov 2026) changed confirm_affiliate_email (a link sent before the login's email last changed no longer
-- verifies: 431ff39a... -> 8a0a7036...). 484's file pins the version before it, so running that file again (the
-- suite's G and U sections) would refuse. For the run, which is rolled back, the version 484 pinned is put back;
-- 491's own checks are in scripts/affiliate-details/tests/details-491.sql. Anywhere else this changes nothing.
do $cae484$
declare v_path text := current_setting('search_path');
begin
  perform set_config('search_path', 'public', true);
  if md5(pg_get_functiondef('public.confirm_affiliate_email()'::regprocedure)) = '8a0a7036312cf5dc22dd2beb82b3ce09' then
    execute $c484$CREATE OR REPLACE FUNCTION public.confirm_affiliate_email()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid(); v_acct public.affiliate_accounts%rowtype;
begin
  -- 437 (the Owner, 20 Oct 2026): an affiliate verifies their email later,
  -- from the Account page. Its email holds a sign-in link to
  -- /affiliate/verify; a session opened from it in the last 30 minutes marks
  -- the email verified. Nothing waits on it: the portal, the referral link,
  -- commission and payouts work the same before.
  if v_uid is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid for update;
  if not found then return jsonb_build_object('verified', false, 'reason', 'not_affiliate'); end if;
  if v_acct.email_verified_at is not null then
    return jsonb_build_object('verified', true, 'already', true, 'verified_at', v_acct.email_verified_at);
  end if;
  if not public.affiliate_session_from_email_link() then
    return jsonb_build_object('verified', false, 'reason', 'not_from_email_link');
  end if;
  update public.affiliate_accounts set email_verified_at = now(), updated_at = now()
   where id = v_acct.id returning * into v_acct;
  -- Kept on the login too (app_metadata, which only the server writes), so
  -- the account made at its next sign-in after an Owner unlinks it (378)
  -- starts verified; and the login no longer counts as one the sign-up
  -- confirmed on an address nobody proved (invite_user_provisioned).
  update auth.users
     set raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified')
                             || jsonb_build_object('affiliate_email_verified_at', v_acct.email_verified_at)
   where id = v_uid;
  -- Written straight into audit_logs (an affiliate has no staff profile for
  -- write_audit_ex to record), as sign-up's own rows are (432).
  begin
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, module)
    values ('affiliate_accounts', v_acct.id, 'affiliate_email_verified',
      jsonb_build_object('email_verified_at', null),
      jsonb_build_object('auth_user_id', v_uid, 'customer_id', v_acct.customer_id,
                         'email_verified_at', v_acct.email_verified_at),
      'affiliate');
  exception when others then
    raise warning '437: the email verification audit row was not saved: %', sqlerrm;
  end;
  return jsonb_build_object('verified', true, 'already', false, 'verified_at', v_acct.email_verified_at);
end $function$
$c484$;
    if md5(pg_get_functiondef('public.confirm_affiliate_email()'::regprocedure)) <> '431ff39aa4fe42ec9b1442e65a044676' then
      raise exception 'confirm-email-as-484: confirm_affiliate_email is not the version 484 pinned after putting it back';
    end if;
    raise notice '491 is in: confirm_affiliate_email is the version 484 pinned for this run (rolled back at the end)';
  end if;
  perform set_config('search_path', v_path, true);
end $cae484$;
