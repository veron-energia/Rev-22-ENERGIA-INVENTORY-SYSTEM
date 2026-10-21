-- The affiliate sign-up as it was before 437, for the claim suites.
--
-- 437 (the Owner, 20 Oct 2026) lets every sign-up straight in: sign-up
-- (complete_affiliate_onboarding) no longer parks an account claim for staff.
-- The claim functions themselves (the Pending and Rejected lists, Resolve,
-- Reject, Delete, the link check and Unlink, 378 and 379) are unchanged and
-- still settle the claims made before 437. The suites that test them make
-- their claims the way people did: by signing up. So on a database with 437
-- they include this file first, inside their own transaction, which puts the
-- 432 sign-up back (production's text of 20 Oct 2026, md5 ff59dd1f...) until
-- their rollback. On a database without 437 it changes nothing. With 440 in
-- (437's sign-up that also keeps the copy of what the login signed up with)
-- it does the same: the 432 text writes no copy, which those suites never read.
--
-- Included by scripts/affiliate-claims/tests/staff-claims.sql,
-- scripts/affiliate-claims/tests/reject-protects.sql and
-- scripts/affiliate-signup/tests/no-duplicate-customers.sql. Never run it on
-- its own against a real database: it is only for a rolled-back test.
do $before437$
declare
  c_437 constant text := '88ee10799d1c93ce93d0056740f05e01';  -- 437's AFTER (21 Oct 2026, AFF-SIGNUP-18)
  c_440 constant text := '43084deab54968eacaf1793c470fd08f';  -- 440's AFTER (21 Oct 2026; 437's, patched)
  c_432 constant text := 'ff59dd1f8a6ca7397efea5880c6a87a7';
  c_def constant text := $def$CREATE OR REPLACE FUNCTION public.complete_affiliate_onboarding(p_first_name text, p_last_name text, p_phone text, p_agree boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_email text; v_confirmed timestamptz; v_phone text; v_name text;
  v_cust uuid; v_aff public.customer_affiliates%rowtype; v_acct public.affiliate_accounts%rowtype;
  v_matches uuid[]; v_email_matches int; v_phone_cust uuid; v_phone_email text; v_code text; v_suspended boolean := false;
  -- 432: the email as compared, how the name matched, how many customers in
  -- use have the phone, whom a parked claim suggests, the claim parked, and
  -- whether a customer was created.
  v_email_key text; v_name_match text; v_holders int; v_suggest uuid; v_claim uuid; v_created boolean := false;
  v_meta jsonb; v_first text; v_last text; v_raw_phone text;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  -- Staff or Affiliate, never both. Checked before anything is written, so a
  -- refused attempt leaves no customer, membership or claim behind.
  if exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'STAFF_ACCOUNT: This is a staff login, so it cannot also be an affiliate account. Sign out and use a personal email address, or ask an Owner to set the affiliate up against the right customer record.'
      using errcode = '42501';
  end if;
  if not coalesce(p_agree, false) then raise exception 'You must agree to the Affiliate terms to continue'; end if;

  select email, email_confirmed_at into v_email, v_confirmed from auth.users where id = v_uid;
  if v_email is null then raise exception 'No email on the authenticated account'; end if;
  if v_confirmed is null then raise exception 'Please verify your email before completing signup'; end if;

  v_email := lower(btrim(v_email));

  -- Already onboarded? Answer before asking for anything (333).
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id = v_acct.affiliate_id;
    return jsonb_build_object('status', case when v_aff.manually_suspended then 'suspended' else 'active' end,
      'customer_id', v_acct.customer_id, 'referral_code', v_aff.referral_code, 'already', true);
  end if;

  -- Arguments first; otherwise what the sign-up stored on the account (333).
  select raw_user_meta_data into v_meta from auth.users where id = v_uid;
  v_first     := nullif(btrim(coalesce(p_first_name, '')), '');
  v_last      := nullif(btrim(coalesce(p_last_name,  '')), '');
  v_raw_phone := nullif(btrim(coalesce(p_phone,      '')), '');
  if v_first is null and v_last is null then
    v_first := nullif(btrim(coalesce(v_meta->>'first_name', '')), '');
    v_last  := nullif(btrim(coalesce(v_meta->>'last_name',  '')), '');
  end if;
  if v_raw_phone is null then v_raw_phone := nullif(btrim(coalesce(v_meta->>'phone', '')), ''); end if;

  v_name  := btrim(coalesce(v_first, '') || ' ' || coalesce(v_last, ''));
  v_phone := public.normalize_customer_phone(v_raw_phone);
  if v_name = '' or v_raw_phone is null then
    raise exception 'DETAILS_REQUIRED: Enter your name and a valid international phone number.'; end if;
  if v_phone is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;

  -- Already onboarded? Idempotent.
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id = v_acct.affiliate_id;
    return jsonb_build_object('status', case when v_aff.manually_suspended then 'suspended' else 'active' end,
      'customer_id', v_acct.customer_id, 'referral_code', v_aff.referral_code, 'already', true);
  end if;

  -- Serialize onboarding for one auth user and identity; recheck idempotency.
  perform pg_advisory_xact_lock(hashtextextended('affiliate-onboarding:' || v_uid::text,0));
  select * into v_acct from public.affiliate_accounts where auth_user_id=v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id=v_acct.affiliate_id;
    return jsonb_build_object('status',case when v_aff.manually_suspended then 'suspended' else 'active' end,
      'customer_id',v_acct.customer_id,'referral_code',v_aff.referral_code,'already',true);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_phone,0));
  perform public.require_resolved_customer_identity(v_phone,v_name);
  v_matches := public.customer_phone_name_matches(v_phone,v_name);
  -- 432: when no customer with this phone has the name exactly as typed, one
  -- whose name has the same words counts too (customer_names_match): in any
  -- order (as written, with a patronymic such as bin or s/o), with
  -- neighbouring words together or apart, whatever the case and punctuation,
  -- and leaving out a note in brackets. "Koh Ann Lee" is "Ann Lee Koh", and
  -- "Ong Meiling" is "Mei Ling (Orchard) Ong".
  if cardinality(v_matches) = 0 then
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_matches
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_phone
       and public.customer_names_match(c.full_name, v_name);
    if cardinality(v_matches) > 0 then v_name_match := 'same_words'; end if;
  else
    v_name_match := 'exact';
  end if;
  -- 432: an email is compared as the inbox it reaches
  -- (customer_email_match_key): a Gmail address with or without dots or a
  -- +tag, or at googlemail.com, is one address. Others are compared as written.
  v_email_key := public.customer_email_match_key(v_email);
  select count(*) into v_email_matches from public.customers
   where public.customer_email_match_key(email)=v_email_key and deleted_at is null;
  if cardinality(v_matches)=1 then
    v_phone_cust := v_matches[1];
    select public.customer_email_match_key(email) into v_phone_email from public.customers where id=v_phone_cust;
  end if;
  -- 432: how many customers in use have this phone.
  select count(*) into v_holders from public.customers
   where deleted_at is null and public.normalize_customer_phone(phone) = v_phone;

  -- 432: a new customer only when no customer in use has this phone either.
  -- When one has it, but neither the name nor the email matched, the sign-up
  -- is parked below as a pending claim: staff check whether it is the same
  -- person under another spelling, or someone sharing the phone (whose own
  -- record an Owner or Manager then links, as before). Up to 3 customers may
  -- share a phone, so the phone alone links no one.
  if v_email_matches = 0 and cardinality(v_matches) = 0 and v_holders = 0 then
    insert into public.customers (full_name, phone, email, is_active)
      values (v_name, v_phone, v_email, true)
      returning id into v_cust;
    v_created := true;
  elsif v_email_matches = 1 and v_phone_cust is not null and v_phone_email = v_email_key
        -- 432: never for a login whose claim was rejected: below, it is told
        -- verification was unsuccessful, whatever its details match now. Nor
        -- to a customer who already has a portal login (one each): that
        -- sign-up is parked below, for staff to sort out.
        and not exists (select 1 from public.affiliate_account_claims
                         where auth_user_id = v_uid and status = 'rejected')
        and not exists (select 1 from public.affiliate_accounts a where a.customer_id = v_phone_cust)
        -- 378: not to a customer an Owner unlinked a login from (the unlink's
        -- audit row, as affiliate_claim_link_check reads it). That sign-up
        -- falls to the branch below and is parked as a pending claim
        -- suggesting the customer, so the link goes through Resolve, where
        -- staff are refused for them.
        and not exists (select 1 from public.audit_logs l
                         where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
                           and l.actor_role = 'owner' and l.module = 'affiliate'
                           and l.old_data->>'customer_id' = v_phone_cust::text)
        -- 379: nor to a customer an Owner or Manager rejected a claim for (the
        -- rejection's audit row, as affiliate_claim_link_check reads it). That
        -- sign-up is parked as a pending claim suggesting them too, or, for a
        -- login with a rejected claim, told it was unsuccessful.
        and not exists (select 1 from public.audit_logs l
                         where l.table_name = 'affiliate_account_claims' and l.action = 'affiliate_claim_rejected'
                           and l.actor_role in ('owner', 'manager') and l.module = 'affiliate'
                           and l.new_data->>'candidate_customer_id' = v_phone_cust::text) then
    v_cust := v_phone_cust;
  else
    -- Ambiguous. If this user was already rejected, do NOT re-park a pending
    -- claim — tell them it was unsuccessful. Otherwise park exactly one pending.
    if exists (select 1 from public.affiliate_account_claims where auth_user_id = v_uid and status = 'rejected') then
      return jsonb_build_object('status', 'rejected',
        'message', 'Account verification was unsuccessful. Please contact Energia for assistance.');
    end if;
    -- 432: whom the claim suggests: the one customer matched by phone and
    -- name; failing that, when the email matched no one either, the one
    -- customer who has this phone. A phone several share suggests no one
    -- without a name match: staff may link only the suggested customer on a
    -- shared phone (378), so the phone alone never lets them choose.
    v_suggest := v_phone_cust;
    if v_suggest is null and v_email_matches = 0 and cardinality(v_matches) = 0 and v_holders = 1 then
      select c.id into v_suggest from public.customers c
       where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_phone;
    end if;
    insert into public.affiliate_account_claims (auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
      values (v_uid, v_phone, v_email, v_suggest, v_name)
      on conflict do nothing                          -- one-pending index (mig 156)
      returning id into v_claim;
    -- 432: the Audit Log keeps the claim parked and why (nothing when this
    -- login's pending claim was there already). Written straight into
    -- audit_logs, with no one signed in recorded (write_audit_ex records the
    -- caller, who must be staff); it cannot stop the sign-up.
    if v_claim is not null then
      begin
        insert into public.audit_logs (table_name, record_id, action, new_data, module)
        values ('affiliate_account_claims', v_claim, 'affiliate_claim_parked',
          jsonb_build_object('auth_user_id', v_uid, 'candidate_customer_id', v_suggest,
            'reason', case
              when cardinality(v_matches) > 1 then 'several_name_matches'
              when v_phone_cust is not null and v_email_matches = 1 and v_phone_email = v_email_key
                   and exists (select 1 from public.affiliate_accounts a where a.customer_id = v_phone_cust)
                then 'customer_has_login'
              when v_phone_cust is not null and v_email_matches = 1 and v_phone_email = v_email_key then 'protected_customer'
              when v_phone_cust is not null and v_email_matches = 0 then 'email_not_on_record'
              when v_phone_cust is not null and v_email_matches > 1 then 'email_on_several_records'
              when v_phone_cust is not null then 'email_on_another_record'
              when v_email_matches > 0 then 'email_only'
              else 'phone_in_use' end,
            'name_match', v_name_match, 'email_matches', v_email_matches, 'phone_holders', v_holders),
          'affiliate');
      exception when others then
        raise warning '432: the sign-up audit row was not saved: %', sqlerrm;
      end;
    end if;
    return jsonb_build_object('status', 'pending_verification',
      'message', 'We found an existing Energia customer record that needs identity verification. Please contact Energia to complete account linking.');
  end if;

  select * into v_aff from public.customer_affiliates where customer_id = v_cust and deleted_at is null;
  if not found then
    v_code := public.generate_affiliate_referral_code();
    insert into public.customer_affiliates (customer_id, status, manually_suspended, activated_at, referral_code)
      values (v_cust, 'active', false, now(), v_code)
      returning * into v_aff;
  else
    v_suspended := v_aff.manually_suspended;
    if v_aff.referral_code is null then
      update public.customer_affiliates set referral_code = public.generate_affiliate_referral_code(), updated_at = now()
       where id = v_aff.id returning * into v_aff;
    end if;
  end if;

  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status, last_login_at)
    values (v_uid, v_cust, v_aff.id, 'claimed', now())
    returning * into v_acct;

  -- 432: written straight into audit_logs, with no one signed in recorded.
  -- Through write_audit_ex it was never saved: that records the caller as
  -- changed_by, which must be a staff profile, a portal login has none, and
  -- the error was swallowed. It still cannot stop the sign-up. It says how
  -- the customer was found: created, or by the name exactly or by the same
  -- words, and by the email exactly or as the same inbox.
  begin
    insert into public.audit_logs (table_name, record_id, action, new_data, module)
    values ('affiliate_accounts', v_acct.id, 'affiliate_portal_claimed',
      jsonb_build_object('customer_id', v_cust, 'affiliate_id', v_aff.id, 'auth_user_id', v_uid,
        'new_customer', v_created, 'name_match', v_name_match,
        'email_match', case when v_created then null
                            when (select lower(btrim(c.email)) from public.customers c where c.id = v_cust) = v_email then 'exact'
                            else 'same_inbox' end),
      'affiliate');
  exception when others then
    raise warning '432: the sign-up audit row was not saved: %', sqlerrm;
  end;

  return jsonb_build_object('status', case when v_suspended then 'suspended' else 'active' end,
    'customer_id', v_cust, 'referral_code', v_aff.referral_code, 'already', false);
end $function$
$def$;
  d text := md5(pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure));
begin
  if md5(c_def) <> c_432 then raise exception 'sign-up-before-437: the 432 text is not the one read (md5 %)', md5(c_def); end if;
  if d = c_432 then return; end if;
  if d not in (c_437, c_440) then raise exception 'sign-up-before-437: complete_affiliate_onboarding is neither 432''s, nor 437''s, nor 440''s (md5 %)', d; end if;
  execute c_def;
  if md5(pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure)) <> c_432 then
    raise exception 'sign-up-before-437: the 432 sign-up did not go back as read'; end if;
  raise notice 'sign-up-before-437: the 432 sign-up is back until this test''s rollback';
end $before437$;
