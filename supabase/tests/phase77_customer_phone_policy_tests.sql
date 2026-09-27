-- Integration checks after 161–163; run in an isolated database only.
begin;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
do $test$
declare
  a uuid; b uuid; c uuid; d uuid; n integer; oldid uuid; r jsonb; src uuid; st uuid; ref uuid;
  existing uuid; name_count integer; payload jsonb; auth_user uuid; matches uuid[];
begin
  -- Equivalent formats, including inactive-but-not-deleted, occupy one pool.
  insert into public.customers(full_name,phone) values('Phone Test A','91237701') returning id into a;
  insert into public.customers(full_name,phone,is_active) values('Phone Test B','6591237701',false) returning id into b;
  insert into public.customers(full_name,phone) values('Phone Test C','+65 9123 7701') returning id into c;
  assert (select count(*) from public.customers where phone='+6591237701')=3,'equivalent formats not stored as E.164';
  begin
    insert into public.customers(full_name,phone) values('Fourth','+6591237701');
    raise exception 'Fourth customer unexpectedly accepted';
  exception when check_violation then assert sqlerrm like 'CUSTOMER_PHONE_LIMIT:%',sqlerrm; end;
  -- ON CONFLICT before-insert normalization must not leak a capacity claim.
  insert into public.customers(id,full_name,phone) values(a,'Phone Test A','+6591237701') on conflict(id) do update set notes='upsert test';
  assert (select used from public.customer_phone_capacity where phone='+6591237701')=3,'upsert leaked capacity';
  update public.customers set deleted_at=now(),is_active=false where id=b;
  assert (select phone from public.customers where id=b)='+6591237701','delete erased phone';
  insert into public.customers(full_name,phone) values('Phone Test D','+6591237701') returning id into d;
  begin
    perform public.restore_customer(b);
    raise exception 'Full-number restoration unexpectedly accepted';
  exception when check_violation then assert sqlerrm like 'CUSTOMER_PHONE_LIMIT:%',sqlerrm; end;
  assert (select deleted_at is not null from public.customers where id=b),'failed restore partially committed';
  perform public.restore_customer_with_phone(b,'+6591237702','Confirmed replacement number');
  assert (select deleted_at is null and phone='+6591237702' from public.customers where id=b),'replacement restore failed';
  assert exists(select 1 from public.customer_phone_history where customer_id=b and phone='+6591237701'),'restoration lost old phone';
  perform public.change_customer_phone(a,'+6591237703','Phone corrected');
  insert into public.customers(full_name,phone) values('Old number reused','+6591237701');
  assert (select used from public.customer_phone_capacity where phone='+6591237701')=3,'history consumed capacity';
  assert (select id from public.customers where id=a)=a,'phone change replaced customer ID';
  raise notice 'PASS: three limit, inactive, normalization, deleted/history exclusion, changes, restoration, upsert';

  -- Legacy conflicts are seeded before migration by the integration runner.
  if exists(select 1 from public.customers where full_name='Legacy One') then
    assert (select used from public.customer_phone_capacity where phone='+6591230001')=4,'legacy conflict not counted';
    update public.customers set notes='Unrelated edit remains possible' where full_name='Legacy One';
    begin
      insert into public.customers(full_name,phone) values('More legacy conflict','+6591230001');
      raise exception 'Overfull group admitted another customer';
    exception when check_violation then null; end;
    update public.customers set phone='+6591237704' where full_name='Legacy One';
    assert (select used from public.customer_phone_capacity where phone='+6591230001')=3,'corrective change failed';
    update public.customers set notes='Pending review unchanged' where full_name='Legacy Invalid';
    assert (select phone from public.customers where full_name='Legacy Invalid')='not-a-number','invalid legacy value guessed';
    assert exists(select 1 from public.customer_phone_migration_map where original_phone='not-a-number'),'original mapping missing';
  end if;
  assert public.normalize_customer_phone('0123456789')='+60123456789','MY domestic';
  assert public.normalize_customer_phone('60123456789')='+60123456789','MY country code';
  assert public.normalize_customer_phone('+44 7911 123456')='+447911123456','explicit country lost';
  assert public.normalize_customer_phone('93234567') is null,'ambiguous SG/MY guessed';
  assert public.inspect_customer_phone('93234567','MY')->>'normalized'='+6093234567','confirmed MY country';
  assert public.normalize_customer_phone('12345678') is null,'invalid SG guessed';
  assert public.normalize_customer_phone('123456789') is null,'unconfirmed MY guessed';
  raise notice 'PASS: legacy conflicts, corrective edits, original values, SG/MY and uncertainty';

  insert into public.customers(full_name,phone) values('  Same   Name  ','+6591237710') returning id into existing;
  insert into public.customers(full_name,phone) values('Different Name','+6591237710');
  matches:=public.customer_phone_name_matches('91237710','same name');
  assert cardinality(matches)=1 and matches[1]=existing,'exact normalized name matching';
  assert cardinality(public.customer_phone_name_matches('91237710','same nme'))=0,'fuzzy matching used';
  insert into public.customers(full_name,phone) values('same name','+6591237710');
  assert cardinality(public.customer_phone_name_matches('91237710','Same Name'))=2,'ambiguity concealed';

  insert into public.stores(name,code) values('Phone Test Store','PHONE-TEST') returning id into st;
  insert into public.customer_source_options(label) values('Phone Test Referral') returning id into src;
  insert into public.survey_links(token,store_id) values('phone-policy-test',st);
  insert into public.customers(full_name,phone) values('Referral Parent','+6591237720') returning id into ref;
  insert into public.customer_affiliates(customer_id,status,manually_suspended,referral_code) values(ref,'active',false,'PHONE-TEST-REF');
  r:=public.affiliate_referral_signup('PHONE-TEST-REF','Shared','Child','+6591237720','child@test.invalid',null);
  assert r->>'ok'='true', 'shared family phone wrongly treated as self referral';
  select id into strict existing from public.customers where full_name='Shared Child';
  assert (select referred_by from public.customers where id=existing)=ref,'referral link missing';
  payload:=jsonb_build_object('full_name',' shared   child ','phone','91237720','email','child@test.invalid','signature_data','signature','source_option_id',src);
  r:=public.submit_health_survey('phone-policy-test',payload,null,null);
  assert (r->>'customer_matched')::boolean,'survey did not match phone+name';
  assert exists(select 1 from public.health_surveys where customer_id=existing),'survey linked to wrong shared-phone customer';
  assert (select referred_by from public.customers where id=existing)=ref,'survey changed referral ownership';
  begin
    perform public.submit_health_survey('phone-policy-test',payload,null,null);
    raise exception 'Duplicate survey accepted';
  exception when others then assert sqlerrm='HEALTH_SURVEY_ALREADY_EXISTS',sqlerrm; end;
  payload:=jsonb_set(payload,'{full_name}','"New Child"');
  r:=public.submit_health_survey('phone-policy-test',payload,null,null);
  assert (r->>'customer_created')::boolean,'different name must create a new customer';
  payload:=jsonb_set(payload,'{full_name}','"Fourth Child"');
  begin
    perform public.submit_health_survey('phone-policy-test',payload,null,null);
    raise exception 'Fourth customer accepted by survey';
  exception when check_violation then assert sqlerrm like 'CUSTOMER_PHONE_LIMIT:%',sqlerrm; end;
  payload:=payload||jsonb_build_object('full_name','Same Name','phone','+6591237710');
  begin
    perform public.submit_health_survey('phone-policy-test',payload,null,null);
    raise exception 'Ambiguous survey matched';
  exception when others then assert sqlerrm='AMBIGUOUS_CUSTOMER_MATCH',sqlerrm; end;
  begin
    perform public.affiliate_referral_signup('PHONE-TEST-REF','Same','Name','+6591237710','same@test.invalid',null);
    raise exception 'Ambiguous referral matched';
  exception when others then assert sqlerrm='AMBIGUOUS_CUSTOMER_MATCH',sqlerrm; end;
  insert into public.invoices(invoice_no,store_id,customer_id,created_by,status)
    values('PHONE-TEST-INVOICE',st,existing,'00000000-0000-4000-8000-000000000001','paid');
  perform public.change_customer_phone(existing,'+6591237725','Verified customer phone correction');
  assert (select customer_id from public.invoices where invoice_no='PHONE-TEST-INVOICE')=existing,'invoice owner changed';
  assert exists(select 1 from public.health_surveys where customer_id=existing and phone='+6591237725'),'survey link/phone sync changed incorrectly';
  assert (select referred_by from public.customers where id=existing)=ref,'phone correction changed referral parent';
  raise notice 'PASS: phone/name matching, survey ownership, shared referral number, ambiguous survey/referral';

  -- Three distinct referral signups sharing one number, followed by a fourth.
  for name_count in 1..3 loop
    r:=public.affiliate_referral_signup('PHONE-TEST-REF','Referral Member',name_count::text,'+6591237728',null,null);
    assert r->>'ok'='true','shared-number referral signup rejected';
  end loop;
  begin
    perform public.affiliate_referral_signup('PHONE-TEST-REF','Referral Member','4','+6591237728',null,null);
    raise exception 'Fourth referral signup accepted';
  exception when others then assert sqlerrm like 'CUSTOMER_PHONE_LIMIT:%',sqlerrm; end;
  assert (select count(*) from public.customers where phone='+6591237728')=3,'referral capacity incorrect';
  -- Candidate legacy ambiguity must not silently create another identity.
  if exists(select 1 from public.customers where full_name='Legacy Ambiguous') then
    begin
      perform public.submit_health_survey('phone-policy-test',payload||jsonb_build_object('full_name','Legacy Ambiguous','phone','+6593234567'),null,null);
      raise exception 'Pending legacy identity was duplicated';
    exception when others then assert sqlerrm='AMBIGUOUS_CUSTOMER_MATCH',sqlerrm; end;
  end if;

  -- Identical names sharing the referrer's phone need resolution, not a
  -- guessed self-referral rejection.
  insert into public.customers(full_name,phone) values('Referral Parent','+6591237720');
  begin
    perform public.affiliate_referral_signup('PHONE-TEST-REF','Referral','Parent','+6591237720',null,null);
    raise exception 'Ambiguous referrer identity guessed';
  exception when others then assert sqlerrm='AMBIGUOUS_CUSTOMER_MATCH',sqlerrm; end;

  -- Verified email still required to attach an affiliate login to an existing
  -- identity. Same phone+name ambiguity is parked, never picked by creation time.
  auth_user:=gen_random_uuid();
  insert into auth.users(id,email,email_confirmed_at) values(auth_user,'onboard@test.invalid',now());
  perform set_config('request.jwt.claim.sub',auth_user::text,true);
  r:=public.complete_affiliate_onboarding('Same','Name','+6591237710',true);
  assert r->>'status'='pending_verification','ambiguous onboarding not parked';
  assert exists(select 1 from public.affiliate_account_claims where auth_user_id=auth_user and candidate_customer_id is null and entered_name='Same Name'),'claim guessed a customer';
  assert not exists(select 1 from public.affiliate_accounts where auth_user_id=auth_user),'account attached to guessed customer';
  perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);

  -- Stale plan fails atomically, leaving earlier valid changes unapplied.
  begin
    perform public.apply_customer_phone_review(jsonb_build_array(
      jsonb_build_object('customer_id',a,'original_phone','+6591237703','normalized_phone','+6591237730','reason','Test review'),
      jsonb_build_object('customer_id',b,'original_phone','stale value','normalized_phone','+6591237731','reason','Test review')));
    raise exception 'Stale cleanup unexpectedly accepted';
  exception when others then assert sqlerrm like 'Stale phone review%',sqlerrm; end;
  assert (select phone from public.customers where id=a)='+6591237703','cleanup partially applied';
  assert (select used from public.customer_phone_capacity where phone='+6591237703')=1,'cleanup counter partially applied';
  perform public.apply_customer_phone_review(jsonb_build_array(
    jsonb_build_object('customer_id',a,'original_phone','+6591237703','normalized_phone','+6591237730','reason','Verified cleanup')));
  assert (select phone from public.customers where id=a)='+6591237730','approved cleanup not applied';
  assert exists(select 1 from public.customer_phone_migration_map where customer_id=a and applied_phone='+6591237730'),'cleanup mapping missing';
  assert exists(select 1 from public.customer_phone_history where customer_id=a and phone='+6591237703'),'cleanup history missing';
  raise notice 'PASS: affiliate ambiguity, fourth referral rejection, pending identity, atomic stale-plan rollback and reviewed cleanup';
end $test$;
rollback;
