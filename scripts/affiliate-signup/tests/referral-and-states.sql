-- The referral form is not the affiliate form, and it says so.
--
-- /r/:code registers a CUSTOMER under an affiliate. For somebody already
-- registered it creates nothing — which was being reported as "Registration
-- Successful". The reply now names its outcome so the screen can tell the two
-- apart. Referral ownership is never changed from an anonymous form.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare mgr uuid:=gen_random_uuid(); aff_cust uuid; aff uuid; code text;
 existing uuid; existing_ref uuid; r jsonb; n int; before_n int;
begin
 insert into auth.users(id,email,email_confirmed_at) values(mgr,'rs-mgr@sig.invalid',now());
 insert into profiles(id,full_name,email,role) values(mgr,'Manager','rs-mgr@sig.invalid','manager');
 perform set_config('request.jwt.claim.sub',mgr::text,true);

 insert into customers(full_name,phone,email) values('Ref Affiliate','+6591310001','ra@sig.invalid') returning id into aff_cust;
 insert into customer_affiliates(customer_id,status,activated_at,referral_code)
  values(aff_cust,'active',now(),generate_affiliate_referral_code()) returning id, referral_code into aff, code;

 -- someone already registered, referred by somebody ELSE
 insert into customers(full_name,phone,email) values('Prior Referrer','+6591310009','pr@sig.invalid') returning id into existing_ref;
 insert into customers(full_name,phone,email,referred_by)
  values('Already Here','+6591310002','ah@sig.invalid',existing_ref) returning id into existing;

 -- ---- a genuinely new registration -----------------------------------------
 select count(*) into before_n from customers;
 r:=affiliate_referral_signup(code,'New','Person','+6591310003','np@sig.invalid',null);
 if (r->>'outcome')<>'registered' then
  raise exception 'A real registration did not report outcome=registered, got %', r->>'outcome'; end if;
 if (select count(*) from customers)<>before_n+1 then
  raise exception 'A referral registration did not create exactly one customer'; end if;

 -- ---- somebody already registered ------------------------------------------
 select count(*) into before_n from customers;
 r:=affiliate_referral_signup(code,'Already','Here','+6591310002','ah@sig.invalid',null);
 if (r->>'ok')::boolean is not true then
  raise exception 'The existing-customer reply should not be an error'; end if;
 if (r->>'outcome')<>'already_registered' then
  raise exception 'An existing customer was not reported as already_registered, got %', r->>'outcome'; end if;
 if (r->>'message') like '%successful%' then
  raise exception 'The existing-customer message still claims success'; end if;
 -- nothing was created
 if (select count(*) from customers)<>before_n then
  raise exception 'The existing-customer path created a customer'; end if;
 -- and their referral ownership is untouched
 if (select referred_by from customers where id=existing)<>existing_ref then
  raise exception 'An anonymous form changed an existing customer''s referrer'; end if;
 -- and no affiliate membership was invented for them
 if exists(select 1 from customer_affiliates where customer_id=existing and deleted_at is null) then
  raise exception 'Referral registration created an affiliate membership'; end if;

 -- ---- a referral registration never makes anyone an affiliate --------------
 if exists(select 1 from customer_affiliates a join customers c on c.id=a.customer_id
            where c.phone='+6591310003' and a.deleted_at is null) then
  raise exception 'A new referral registration was turned into an affiliate'; end if;

 -- ---- an affiliate membership that already exists is reused, not doubled ---
 declare u uuid:=gen_random_uuid(); c_aff uuid; begin
  insert into auth.users(id,email,email_confirmed_at) values(u,'reuse@sig.invalid',now());
  insert into customers(full_name,phone,email) values('Reuse Me','+6591310004','reuse@sig.invalid') returning id into c_aff;
  insert into customer_affiliates(customer_id,status,activated_at,referral_code)
   values(c_aff,'active',now(),generate_affiliate_referral_code());
  perform set_config('request.jwt.claim.sub',u::text,true);
  r:=complete_affiliate_onboarding('Reuse','Me','+6591310004',true);
  if (r->>'status')<>'active' then raise exception 'An existing membership blocked onboarding'; end if;
  if (select count(*) from customer_affiliates where customer_id=c_aff and deleted_at is null)<>1 then
   raise exception 'Onboarding created a second affiliate membership'; end if;
 end;

 -- ---- a suspended membership is reported, not silently activated -----------
 declare u2 uuid:=gen_random_uuid(); c_sus uuid; begin
  insert into auth.users(id,email,email_confirmed_at) values(u2,'susp@sig.invalid',now());
  insert into customers(full_name,phone,email) values('Susp Ended','+6591310005','susp@sig.invalid') returning id into c_sus;
  insert into customer_affiliates(customer_id,status,manually_suspended,activated_at,referral_code)
   values(c_sus,'active',true,now(),generate_affiliate_referral_code());
  perform set_config('request.jwt.claim.sub',u2::text,true);
  r:=complete_affiliate_onboarding('Susp','Ended','+6591310005',true);
  if (r->>'status')<>'suspended' then
   raise exception 'A suspended membership was reported as %', r->>'status'; end if;
  if (select manually_suspended from customer_affiliates where customer_id=c_sus) is not true then
   raise exception 'Onboarding lifted the suspension'; end if;
 end;

 raise notice 'PASS: a referral registration names its outcome, an existing customer creates nothing and keeps their referrer, no referral becomes an affiliate by itself, an existing membership is reused rather than doubled, and a suspended one is reported without being activated';
end $$;
rollback;
