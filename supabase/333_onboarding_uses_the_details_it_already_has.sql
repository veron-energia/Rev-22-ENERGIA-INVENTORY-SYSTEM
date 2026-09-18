begin;
-- =====================================================================
-- ONBOARDING USES THE DETAILS IT ALREADY HAS
--
-- The affiliate sign-up form stores first name, last name and phone on the
-- auth user when the account is created (auth-signup-request → generateLink
-- metadata). The browser then kept a second copy in localStorage, and the
-- verify page read only that copy. A verification link opened on a phone
-- usually opens in a different browser from the one the form was filled in —
-- the mail app's own, or a different default — so the copy was missing and
-- the person was asked for name and phone again. Every re-opened link asked
-- again, because the copy is cleared after any definitive answer.
--
-- An affiliate who already finished could be asked too: this function
-- demanded name and phone before checking whether the account existed, and
-- the portal's route guard sends anyone whose account lookup failed — a poor
-- connection — to the same screen.
--
-- Now: an existing account answers first, without asking for anything. Then
-- name and phone come from the arguments if given, else from the account's
-- own metadata. Only when neither has them is DETAILS_REQUIRED raised, and
-- the screen asks. Metadata is descriptive: the person is the authenticated,
-- verified user, and nothing read here grants a role.
--
-- Patched by anchored replacement. Idempotent.
-- =====================================================================
do $do$
declare f text;
begin
  select pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure) into f;
  if position('DETAILS_REQUIRED' in f) > 0 then return; end if;

  f := replace(f,
'  v_matches uuid[]; v_email_matches int; v_phone_cust uuid; v_phone_email text; v_code text; v_suspended boolean := false;',
'  v_matches uuid[]; v_email_matches int; v_phone_cust uuid; v_phone_email text; v_code text; v_suspended boolean := false;
  v_meta jsonb; v_first text; v_last text; v_raw_phone text;');

  f := replace(f,
'  v_email := lower(btrim(v_email));
  v_phone := public.normalize_customer_phone(p_phone);
  v_name := btrim(coalesce(p_first_name,'''') || '' '' || coalesce(p_last_name,''''));
  if v_name = '''' then raise exception ''Name is required''; end if;
  if v_phone is null then raise exception ''CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.''; end if;',
'  v_email := lower(btrim(v_email));

  -- Already onboarded? Answer before asking for anything (333).
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id = v_acct.affiliate_id;
    return jsonb_build_object(''status'', case when v_aff.manually_suspended then ''suspended'' else ''active'' end,
      ''customer_id'', v_acct.customer_id, ''referral_code'', v_aff.referral_code, ''already'', true);
  end if;

  -- Arguments first; otherwise what the sign-up stored on the account (333).
  select raw_user_meta_data into v_meta from auth.users where id = v_uid;
  v_first     := nullif(btrim(coalesce(p_first_name, '''')), '''');
  v_last      := nullif(btrim(coalesce(p_last_name,  '''')), '''');
  v_raw_phone := nullif(btrim(coalesce(p_phone,      '''')), '''');
  if v_first is null and v_last is null then
    v_first := nullif(btrim(coalesce(v_meta->>''first_name'', '''')), '''');
    v_last  := nullif(btrim(coalesce(v_meta->>''last_name'',  '''')), '''');
  end if;
  if v_raw_phone is null then v_raw_phone := nullif(btrim(coalesce(v_meta->>''phone'', '''')), ''''); end if;

  v_name  := btrim(coalesce(v_first, '''') || '' '' || coalesce(v_last, ''''));
  v_phone := public.normalize_customer_phone(v_raw_phone);
  if v_name = '''' or v_raw_phone is null then
    raise exception ''DETAILS_REQUIRED: Enter your name and a valid international phone number.''; end if;
  if v_phone is null then raise exception ''CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.''; end if;');

  if position('DETAILS_REQUIRED' in f) = 0 or position('v_meta jsonb' in f) = 0 then
    raise exception 'complete_affiliate_onboarding does not match what 333 expects — align it by hand'; end if;
  execute f;
end $do$;
commit;
