-- =====================================================================
-- ENERGIA — HEALTH SURVEY: MATCH EXISTING CUSTOMER BY CANONICAL PHONE
--
-- A customer created through an Affiliate personal referral link (/r/:code)
-- exists BEFORE they complete a Health Survey. The public survey used to reject
-- any known phone with DUPLICATE_PHONE, which wrongly blocked those referral
-- customers. This migration:
--
--   1. Adds ONE canonical phone helper — normalize_customer_phone() — used by
--      every matching path (survey, referral signup, and a collision diagnostic).
--   2. Rewrites submit_health_survey() so a known phone with NO prior survey
--      attaches to the existing customer (never a duplicate, never overwriting
--      referral ownership); a known phone WITH a survey returns
--      HEALTH_SURVEY_ALREADY_EXISTS; an ambiguous legacy match returns
--      AMBIGUOUS_CUSTOMER_MATCH for staff resolution; an unknown phone creates
--      the customer + survey as before.
--   3. Points affiliate_referral_signup() at the same canonical helper.
--
-- The existing raw UNIQUE(customers.phone) is kept. No customer records are
-- merged; legacy collisions are surfaced via customer_phone_collisions() for
-- Owner/Manager. Additive and idempotent. Run AFTER 156.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. Canonical phone helper. Deterministic; never guesses a country code for
--    ambiguous international numbers. New data arrives E.164 from the frontend
--    PhoneInput, so it normalizes to itself; this mainly rescues legacy rows.
--      +65 9123 4567 / (+65) 9123-4567 / +6591234567  -> +6591234567
--      0065 9123 4567                                 -> +6591234567
--      91234567   (bare 8-digit SG)                   -> +6591234567
--      6591234567 (SG with cc, no +)                  -> +6591234567
--      anything else without a +                      -> digits, as-is
--    IMMUTABLE so it can back an expression index.
-- =====================================================================
create or replace function public.normalize_customer_phone(p_phone text)
returns text language plpgsql immutable set search_path to 'public' as $function$
declare v text; v_plus boolean;
begin
  if p_phone is null then return null; end if;
  v := regexp_replace(p_phone, '[^0-9+]', '', 'g');   -- keep only digits and '+'
  v_plus := left(v, 1) = '+';
  v := replace(v, '+', '');                            -- strip stray '+' signs
  if v = '' then return null; end if;

  if v_plus then
    return '+' || v;                                   -- already had a country code
  elsif left(v, 2) = '00' then
    return '+' || substr(v, 3);                        -- 00 international prefix
  elsif length(v) = 8 then
    return '+65' || v;                                 -- bare SG local number
  elsif length(v) = 10 and left(v, 2) = '65' then
    return '+' || v;                                   -- SG number with cc, no '+'
  else
    return v;                                          -- can't safely canonicalize
  end if;
end $function$;

-- Match performance for the normalized comparisons below (non-unique on
-- purpose: legacy data may contain genuine collisions — see the diagnostic).
create index if not exists idx_customers_phone_norm
  on public.customers (public.normalize_customer_phone(phone));

-- =====================================================================
-- 2. Owner/Manager diagnostic: active, non-deleted customers whose phones
--    normalize to the same canonical value (would-be duplicates). Never merges
--    anything — surfaces them so financial history can be reconciled by hand.
-- =====================================================================
create or replace function public.customer_phone_collisions()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_rows jsonb;
begin
  if not public.is_owner_or_manager() then raise exception 'Owner or Manager only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'canonical_phone', norm,
           'customer_ids', ids,
           'names', names,
           'count', cnt) order by cnt desc), '[]'::jsonb)
    into v_rows
  from (
    select public.normalize_customer_phone(phone) as norm,
           jsonb_agg(id order by created_at) as ids,
           jsonb_agg(full_name order by created_at) as names,
           count(*) as cnt
      from public.customers
     where deleted_at is null and public.normalize_customer_phone(phone) is not null
     group by public.normalize_customer_phone(phone)
    having count(*) > 1
  ) g;
  return v_rows;
end $function$;

-- =====================================================================
-- 3. submit_health_survey — rebuilt from the deployed (migration 63) definition,
--    preserving every validation, source, symptom, PDF and audit step. Only the
--    customer-matching branch changes.
-- =====================================================================
create or replace function public.submit_health_survey(
  p_token text, p_payload jsonb, p_symptoms jsonb, p_pdf_base64 text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_l public.survey_links%rowtype;
  v_phone text; v_norm text; v_name text; v_email text; v_cust_id uuid; v_id uuid; v_no text;
  v_sym jsonb; v_sex text; v_gender customer_gender;
  v_src public.customer_source_options%rowtype;
  v_src_id uuid; v_src_details text;
  v_match_count int; v_matched boolean := false; v_created boolean := false;
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

  -- ---- Customer matching by CANONICAL phone (replaces DUPLICATE_PHONE) ----
  select count(*) into v_match_count
    from public.customers
   where deleted_at is null and public.normalize_customer_phone(phone) = v_norm;

  if v_match_count > 1 then
    -- Legacy ambiguity: never attach private health data to a guessed record.
    raise exception 'AMBIGUOUS_CUSTOMER_MATCH';

  elsif v_match_count = 1 then
    -- Existing customer (e.g. an affiliate-referral customer). Reuse them.
    select id into v_cust_id from public.customers
     where deleted_at is null and public.normalize_customer_phone(phone) = v_norm
     limit 1;
    v_matched := true;

    -- Already completed an initial survey? (by customer_id, and defensively by
    -- canonical phone for legacy surveys with a null customer_id).
    if exists (select 1 from public.health_surveys where customer_id = v_cust_id)
       or exists (select 1 from public.health_surveys
                   where customer_id is null
                     and public.normalize_customer_phone(phone) = v_norm) then
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
    -- No customer: create one (unchanged behaviour), storing canonical phone.
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

-- =====================================================================
-- 4. affiliate_referral_signup — same canonical helper for its existing-phone
--    and self-referral checks. All other guarantees are preserved verbatim:
--    first valid referral wins, no self-referral, no re-parenting an existing
--    customer, suspension check, honeypot, per-phone throttle, audit.
-- =====================================================================
create or replace function public.affiliate_referral_signup(
  p_code text, p_first_name text, p_last_name text, p_phone text, p_email text,
  p_honeypot text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_ca public.customer_affiliates%rowtype; v_ref_cust uuid; v_phone text; v_norm text; v_email text;
  v_name text; v_new uuid; v_recent int;
begin
  if coalesce(btrim(p_honeypot),'') <> '' then
    insert into public.referral_signup_events(referral_code, outcome) values (p_code, 'honeypot');
    return jsonb_build_object('ok', true);
  end if;

  v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_norm  := public.normalize_customer_phone(p_phone);
  v_email := nullif(lower(btrim(coalesce(p_email,''))), '');
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  if v_phone = '' or v_name = '' then raise exception 'Please enter your name and phone number'; end if;

  select count(*) into v_recent from public.referral_signup_events
   where normalized_phone = v_norm and created_at > now() - interval '10 minutes';
  if v_recent >= 3 then
    return jsonb_build_object('ok', true, 'message', 'Registration received.');
  end if;

  select * into v_ca from public.customer_affiliates where referral_code = btrim(p_code) and deleted_at is null;
  if not found or v_ca.manually_suspended or v_ca.status <> 'active' then
    insert into public.referral_signup_events(referral_code, normalized_phone, outcome) values (p_code, v_norm, 'rejected');
    return jsonb_build_object('ok', false,
      'message', 'This referral link is not accepting new registrations right now. Please contact Energia.');
  end if;
  v_ref_cust := v_ca.customer_id;

  -- Self-referral (by canonical phone or email).
  if exists (select 1 from public.customers where id = v_ref_cust
              and (public.normalize_customer_phone(phone) = v_norm
                   or (v_email is not null and lower(btrim(email)) = v_email))) then
    return jsonb_build_object('ok', false, 'message', 'You cannot refer yourself.');
  end if;

  -- Existing phone (canonical): never hijack / re-parent from an anonymous form.
  if exists (select 1 from public.customers where public.normalize_customer_phone(phone) = v_norm) then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (p_code, v_ref_cust, v_norm, 'duplicate');
    return jsonb_build_object('ok', true,
      'message', 'This customer is already registered with Energia. Please contact us if you need help with your referral registration.');
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

grant execute on function public.normalize_customer_phone(text) to anon, authenticated;
grant execute on function public.customer_phone_collisions() to authenticated;
grant execute on function public.affiliate_referral_signup(text,text,text,text,text,text) to anon, authenticated;

do $$
begin
  if public.normalize_customer_phone('+65 9123 4567') <> '+6591234567' then raise exception 'norm E.164 spacing failed'; end if;
  if public.normalize_customer_phone('91234567')       <> '+6591234567' then raise exception 'norm bare SG failed'; end if;
  if public.normalize_customer_phone('(+65) 9123-4567')<> '+6591234567' then raise exception 'norm punctuation failed'; end if;
  if public.normalize_customer_phone('006591234567')   <> '+6591234567' then raise exception 'norm 00-prefix failed'; end if;
  if public.normalize_customer_phone('6591234567')     <> '+6591234567' then raise exception 'norm cc-no-plus failed'; end if;
  if public.normalize_customer_phone('+60123456789')   <> '+60123456789' then raise exception 'norm MY passthrough failed'; end if;
  raise notice 'Confirmed: canonical phone helper + health-survey existing-customer matching installed.';
end $$;

notify pgrst, 'reload schema';
