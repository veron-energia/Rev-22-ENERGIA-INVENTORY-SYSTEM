-- Apply after 161. Full function replacements preserve survey and referral history.
begin;
set local check_function_bodies = on;
alter table public.affiliate_account_claims add column if not exists entered_name text;

-- An unresolved legacy candidate with the same name must be reviewed before
-- a public flow creates a second identity under an explicit country code.
create or replace function public.require_resolved_customer_identity(p_phone text,p_name text)
returns void language plpgsql stable security definer set search_path=public as $fn$
begin
  if exists(select 1 from public.customers where deleted_at is null
    and public.normalize_customer_phone(phone) is null
    and public.normalize_customer_match_name(full_name)=public.normalize_customer_match_name(p_name)
    and (public.inspect_customer_phone(phone)->'candidates') ? p_phone) then
    raise exception 'AMBIGUOUS_CUSTOMER_MATCH';
  end if;
end $fn$;
revoke all on function public.require_resolved_customer_identity(text,text) from public,anon,authenticated;

create or replace function public.submit_health_survey(
  p_token text, p_payload jsonb, p_symptoms jsonb, p_pdf_base64 text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_l public.survey_links%rowtype;
  v_phone text; v_norm text; v_name text; v_email text; v_cust_id uuid; v_id uuid; v_no text;
  v_sym jsonb; v_sex text; v_gender customer_gender;
  v_src public.customer_source_options%rowtype;
  v_src_id uuid; v_src_details text;
  v_matches uuid[]; v_match_count int; v_matched boolean := false; v_created boolean := false;
begin
  select * into v_l from public.survey_links where token = p_token;
  if not found then raise exception 'This survey link is not recognised.'; end if;
  if not v_l.is_active then raise exception 'This survey link has been deactivated.'; end if;
  if v_l.expires_at is not null and v_l.expires_at < now() then
    raise exception 'This survey link has expired.'; end if;

  v_name  := nullif(trim(p_payload->>'full_name'), '');
  v_phone := nullif(trim(p_payload->>'phone'), '');
  v_email := nullif(trim(p_payload->>'email'), '');
  if v_name is null then raise exception 'Name is required.'; end if;
  if v_phone is null then raise exception 'Mobile number is required.'; end if;
  if v_email is null then raise exception 'Email is required.'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Please enter a valid email address.'; end if;
  if nullif(p_payload->>'signature_data','') is null then raise exception 'Signature is required.'; end if;

  v_src_id := nullif(p_payload->>'source_option_id','')::uuid;
  v_src_details := nullif(trim(p_payload->>'source_details'), '');
  if v_src_id is null then raise exception 'Please tell us how you heard about us.'; end if;
  select * into v_src from public.customer_source_options where id = v_src_id and is_active = true;
  if not found then raise exception 'That source option is not available.'; end if;
  if v_src.requires_details and v_src_details is null then
    raise exception 'Please add a few details for "%".', v_src.label; end if;

  v_sex := nullif(p_payload->>'sex','');
  v_gender := case when v_sex in ('male','female') then v_sex::customer_gender else null end;
  v_norm := public.normalize_customer_phone(v_phone);

  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm, 0));
  perform public.require_resolved_customer_identity(v_norm,v_name);
  v_matches := public.customer_phone_name_matches(v_norm,v_name);
  v_match_count := cardinality(v_matches);

  if v_match_count > 1 then
    -- Legacy ambiguity: never attach private health data to a guessed record.
    raise exception 'AMBIGUOUS_CUSTOMER_MATCH';

  elsif v_match_count = 1 then
    -- Existing customer (e.g. an affiliate-referral customer). Reuse them.
    v_cust_id := v_matches[1]; -- only after cardinality = 1
    v_matched := true;

    -- Already completed an initial survey? (by customer_id, and defensively by
    -- canonical phone for legacy surveys with a null customer_id).
    if exists (select 1 from public.health_surveys where customer_id = v_cust_id)
       or exists (select 1 from public.health_surveys
                   where customer_id is null
                     and public.normalize_customer_phone(phone) = v_norm
                     and public.normalize_customer_match_name(full_name) = public.normalize_customer_match_name(v_name)) then
      raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
    end if;

    -- Fill ONLY currently-empty, safe fields. NEVER touch full_name, phone, or
    -- any referral attribution (referred_by / referred_at / referral_source /
    -- referral_code_used).
    update public.customers
       set email             = coalesce(email, v_email),
           date_of_birth     = coalesce(date_of_birth, nullif(p_payload->>'date_of_birth','')::date),
           gender            = coalesce(gender, v_gender),
           occupation        = coalesce(occupation, nullif(trim(p_payload->>'occupation'),'')),
           source_option_id  = coalesce(source_option_id, v_src.id),
           source_label      = coalesce(source_label, v_src.label),
           source_details    = coalesce(source_details, v_src_details),
           source_updated_at = case when source_option_id is null then now() else source_updated_at end,
           updated_at        = now()
     where id = v_cust_id;

  else
    if exists(select 1 from public.health_surveys where customer_id is null
      and public.normalize_customer_phone(phone)=v_norm
      and public.normalize_customer_match_name(full_name)=public.normalize_customer_match_name(v_name)) then
      raise exception 'AMBIGUOUS_CUSTOMER_MATCH';
    end if;
    -- No phone-plus-name match: create a new customer subject to capacity.
    insert into public.customers (full_name, phone, email, date_of_birth, gender, occupation,
                                  source_option_id, source_label, source_details, source_updated_at)
    values (v_name, coalesce(v_norm, v_phone), v_email,
            nullif(p_payload->>'date_of_birth','')::date, v_gender,
            nullif(trim(p_payload->>'occupation'), ''),
            v_src.id, v_src.label, v_src_details, now())
    returning id into v_cust_id;
    v_created := true;
  end if;

  v_no := 'HS-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);

  insert into public.health_surveys (
    survey_no, store_id, survey_link_id, customer_id, event_name,
    full_name, date_of_birth, age, sex, phone, email, occupation,
    has_medical_condition, drinks_alcohol, smokes, on_treatment, treatment_list, others_text,
    consent_newsletter_email, consent_marketing_email, consent_marketing_sms, consent_marketing_phone,
    signature_data, signed_date, ip_address, device_info,
    source_option_id, source_label, source_details)
  values (
    v_no, v_l.store_id, v_l.id, v_cust_id, coalesce(nullif(trim(p_payload->>'event_name'),''), v_l.event_name),
    v_name, nullif(p_payload->>'date_of_birth','')::date, nullif(p_payload->>'age','')::integer,
    v_sex, coalesce(v_norm, v_phone), v_email, nullif(trim(p_payload->>'occupation'),''),
    (p_payload->>'has_medical_condition')::boolean, (p_payload->>'drinks_alcohol')::boolean,
    (p_payload->>'smokes')::boolean, (p_payload->>'on_treatment')::boolean,
    nullif(trim(p_payload->>'treatment_list'),''), nullif(trim(p_payload->>'others_text'),''),
    coalesce((p_payload->>'consent_newsletter_email')::boolean, false),
    coalesce((p_payload->>'consent_marketing_email')::boolean, false),
    coalesce((p_payload->>'consent_marketing_sms')::boolean, false),
    coalesce((p_payload->>'consent_marketing_phone')::boolean, false),
    p_payload->>'signature_data',
    coalesce(nullif(p_payload->>'signed_date','')::date, public.sg_today()),
    nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''),
    v_src.id, v_src.label, v_src_details)
  returning id into v_id;

  if p_symptoms is not null then
    for v_sym in select * from jsonb_array_elements(p_symptoms) loop
      insert into public.health_survey_symptoms (survey_id, option_id, duration_text)
      values (v_id, (v_sym->>'option_id')::uuid, nullif(trim(v_sym->>'duration_text'),''))
      on conflict do nothing;
    end loop;
  end if;

  if p_pdf_base64 is not null and length(p_pdf_base64) > 0 then
    if length(p_pdf_base64) > 8000000 then raise exception 'The signed document is too large.'; end if;
    insert into public.health_survey_pdfs (survey_id, pdf_base64, byte_size)
    values (v_id, p_pdf_base64, length(p_pdf_base64));
    update public.health_surveys set pdf_url = 'stored' where id = v_id;
  end if;

  insert into public.audit_logs (table_name, record_id, action, new_data, module, store_id, ip_address, device_info)
  values ('health_surveys', v_id, 'health_survey_submitted',
          jsonb_build_object('survey_no', v_no, 'customer_id', v_cust_id, 'source', 'public_qr',
                             'customer_source', v_src.label,
                             'customer_created', v_created, 'customer_matched', v_matched),
          'health_survey', v_l.store_id,
          nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''));

  return jsonb_build_object('success', true, 'survey_no', v_no, 'survey_id', v_id,
                            'customer_created', v_created, 'customer_matched', v_matched);
end $function$;

create or replace function public.affiliate_referral_signup(
  p_code text, p_first_name text, p_last_name text, p_phone text, p_email text,
  p_honeypot text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_ca public.customer_affiliates%rowtype; v_ref_cust uuid; v_phone text; v_norm text; v_email text;
  v_name text; v_new uuid; v_recent int; v_matches uuid[];
begin
  if coalesce(btrim(p_honeypot),'') <> '' then
    insert into public.referral_signup_events(referral_code, outcome) values (p_code, 'honeypot');
    return jsonb_build_object('ok', true);
  end if;

  v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_norm  := public.normalize_customer_phone(p_phone);
  v_email := nullif(lower(btrim(coalesce(p_email,''))), '');
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;
  if v_name = '' then raise exception 'Please enter your name'; end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm,0));


  select * into v_ca from public.customer_affiliates where referral_code = btrim(p_code) and deleted_at is null;
  if not found or v_ca.manually_suspended or v_ca.status <> 'active' then
    insert into public.referral_signup_events(referral_code, normalized_phone, outcome) values (p_code, v_norm, 'rejected');
    return jsonb_build_object('ok', false,
      'message', 'This referral link is not accepting new registrations right now. Please contact Energia.');
  end if;
  v_ref_cust := v_ca.customer_id;

  perform public.require_resolved_customer_identity(v_norm,v_name);
  v_matches := public.customer_phone_name_matches(v_norm,v_name);
  if cardinality(v_matches) > 1 then raise exception 'AMBIGUOUS_CUSTOMER_MATCH'; end if;
  -- A shared household phone alone does not identify the referrer. Check the
  -- uniquely matched customer ID only after ambiguity has been ruled out.
  if cardinality(v_matches)=1 and v_matches[1]=v_ref_cust then
    return jsonb_build_object('ok',false,'message','You cannot refer yourself.');
  end if;

  -- Existing identity: never change referral ownership from an anonymous form.
  if cardinality(v_matches) = 1 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (p_code, v_ref_cust, v_norm, 'duplicate');
    return jsonb_build_object('ok', true,
      'message', 'This customer is already registered with Energia. Please contact us if you need help with your referral registration.');
  end if;

  if (select used from public.customer_phone_capacity where phone=v_norm) >= 3 then
    raise exception 'CUSTOMER_PHONE_LIMIT: This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.';
  end if;
  select count(*) into v_recent from public.referral_signup_events
   where normalized_phone=v_norm and created_at > now()-interval '10 minutes';
  if v_recent >= 3 then
    return jsonb_build_object('ok',false,'message','Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.');
  end if;

  insert into public.customers (full_name, phone, email, is_active, referred_by,
      referred_at, referral_source, referral_code_used)
    values (v_name, coalesce(v_norm, v_phone), v_email, true, v_ref_cust, now(), 'affiliate_link', btrim(p_code))
    returning id into v_new;

  insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, normalized_phone, outcome)
    values (p_code, v_ref_cust, v_new, v_norm, 'created');

  begin
    perform public.write_audit_ex('customers', v_new, 'referral_registered', null,
      jsonb_build_object('referred_by', v_ref_cust, 'referral_code', btrim(p_code), 'source', 'affiliate_link'),
      'affiliate', null, null);
  exception when others then null; end;

  return jsonb_build_object('ok', true, 'message', 'Registration successful.');
end $function$;

create or replace function public.complete_affiliate_onboarding(
  p_first_name text, p_last_name text, p_phone text, p_agree boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_uid uuid := auth.uid();
  v_email text; v_confirmed timestamptz; v_phone text; v_name text;
  v_cust uuid; v_aff public.customer_affiliates%rowtype; v_acct public.affiliate_accounts%rowtype;
  v_matches uuid[]; v_email_matches int; v_phone_cust uuid; v_phone_email text; v_code text; v_suspended boolean := false;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if not coalesce(p_agree, false) then raise exception 'You must agree to the Affiliate terms to continue'; end if;

  select email, email_confirmed_at into v_email, v_confirmed from auth.users where id = v_uid;
  if v_email is null then raise exception 'No email on the authenticated account'; end if;
  if v_confirmed is null then raise exception 'Please verify your email before completing signup'; end if;

  v_email := lower(btrim(v_email));
  v_phone := public.normalize_customer_phone(p_phone);
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  if v_name = '' then raise exception 'Name is required'; end if;
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
  select count(*) into v_email_matches from public.customers
   where lower(btrim(email))=v_email and deleted_at is null;
  if cardinality(v_matches)=1 then
    v_phone_cust := v_matches[1];
    select lower(btrim(email)) into v_phone_email from public.customers where id=v_phone_cust;
  end if;

  if v_email_matches = 0 and cardinality(v_matches) = 0 then
    insert into public.customers (full_name, phone, email, is_active)
      values (v_name, v_phone, v_email, true)
      returning id into v_cust;
  elsif v_email_matches = 1 and v_phone_cust is not null and v_phone_email = v_email then
    v_cust := v_phone_cust;
  else
    -- Ambiguous. If this user was already rejected, do NOT re-park a pending
    -- claim — tell them it was unsuccessful. Otherwise park exactly one pending.
    if exists (select 1 from public.affiliate_account_claims where auth_user_id = v_uid and status = 'rejected') then
      return jsonb_build_object('status', 'rejected',
        'message', 'Account verification was unsuccessful. Please contact Energia for assistance.');
    end if;
    insert into public.affiliate_account_claims (auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
      values (v_uid, v_phone, v_email, v_phone_cust, v_name)
      on conflict do nothing;                         -- one-pending index (mig 156)
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

  begin
    perform public.write_audit_ex('affiliate_accounts', v_acct.id, 'affiliate_portal_claimed', null,
      jsonb_build_object('customer_id', v_cust, 'affiliate_id', v_aff.id, 'auth_user_id', v_uid,
        'new_customer', (v_email_matches = 0 and v_phone_cust is null)), 'affiliate', null, null);
  exception when others then null; end;

  return jsonb_build_object('status', case when v_suspended then 'suspended' else 'active' end,
    'customer_id', v_cust, 'referral_code', v_aff.referral_code, 'already', false);
end $function$;

create or replace function public.affiliate_pending_claims()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_rows jsonb;
begin
  if not coalesce(public.is_owner_or_manager(),false) then raise exception 'Owner or Manager only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'claim_id', cl.id, 'verified_email', cl.verified_email, 'entered_phone', cl.entered_phone,
    'entered_name', cl.entered_name,
    'candidate_customer_id', cl.candidate_customer_id,
    'candidate_name', (select full_name from public.customers where id = cl.candidate_customer_id),
    'created_at', cl.created_at) order by cl.created_at), '[]'::jsonb) into v_rows
  from public.affiliate_account_claims cl where cl.status = 'pending';
  return v_rows;
end $function$;

notify pgrst,'reload schema';
commit;
