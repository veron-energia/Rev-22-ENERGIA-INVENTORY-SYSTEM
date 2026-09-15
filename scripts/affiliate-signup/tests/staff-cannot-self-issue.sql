-- A staff login cannot make itself an affiliate.
--
-- AuthContext states the rule the app is built on: a login is either Staff or
-- an Affiliate, never both. complete_affiliate_onboarding never checked it, and
-- /affiliate/verify is a public route, so a signed-in owner could reach the
-- form and come away with a live referral code, a duplicate customer under
-- their own work email, and a place in their own commission chain.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare owner_uid uuid:=gen_random_uuid(); staff_uid uuid:=gen_random_uuid();
 public_uid uuid:=gen_random_uuid(); n int; r jsonb; before_cust int;
begin
 insert into auth.users(id,email,email_confirmed_at) values
  (owner_uid,'own@sci.invalid',now()),(staff_uid,'stf@sci.invalid',now()),
  (public_uid,'pub@sci.invalid',now());
 insert into profiles(id,full_name,email,role) values
  (owner_uid,'An Owner','own@sci.invalid','owner'),
  (staff_uid,'Some Staff','stf@sci.invalid','staff');

 -- ---- an owner is refused, and nothing is left behind ----------------------
 select count(*) into before_cust from customers;
 perform set_config('request.jwt.claim.sub',owner_uid::text,true);
 begin
  perform complete_affiliate_onboarding('An','Owner','+6591930001',true);
  raise exception 'An owner was allowed to create an affiliate account';
 exception when others then
  if sqlerrm not like '%STAFF_ACCOUNT%' then raise; end if; end;
 if (select count(*) from affiliate_accounts where auth_user_id=owner_uid)<>0 then
  raise exception 'A refused attempt still created an affiliate account'; end if;
 if (select count(*) from customers)<>before_cust then
  raise exception 'A refused attempt still created a customer'; end if;
 if (select count(*) from affiliate_account_claims where auth_user_id=owner_uid)<>0 then
  raise exception 'A refused attempt still parked a claim'; end if;

 -- ---- ordinary staff too ---------------------------------------------------
 perform set_config('request.jwt.claim.sub',staff_uid::text,true);
 begin
  perform complete_affiliate_onboarding('Some','Staff','+6591930002',true);
  raise exception 'A staff member was allowed to create an affiliate account';
 exception when others then
  if sqlerrm not like '%STAFF_ACCOUNT%' then raise; end if; end;

 -- ---- a login with no profiles row is unaffected ---------------------------
 perform set_config('request.jwt.claim.sub',public_uid::text,true);
 r:=complete_affiliate_onboarding('Real','Applicant','+6591930003',true);
 if (r->>'status')<>'active' then
  raise exception 'An ordinary applicant was blocked: %', r->>'status'; end if;

 -- ---- and the review query finds an account that already holds both --------
 perform set_config('request.jwt.claim.sub',owner_uid::text,true);
 -- a separate customer, so this mirrors a real mixed account rather than
 -- colliding with the applicant's own one-account-per-customer rule
 declare c_own uuid; a_own uuid; begin
  insert into customers(full_name,phone,email) values('Owner As Customer','+6591930009','own@sci.invalid') returning id into c_own;
  insert into customer_affiliates(customer_id,status,activated_at,referral_code)
   values(c_own,'active',now(),generate_affiliate_referral_code()) returning id into a_own;
  insert into affiliate_accounts(auth_user_id,customer_id,affiliate_id,status)
   values(owner_uid,c_own,a_own,'claimed');
 end;
 select count(*) into n from staff_logins_with_affiliate_accounts() where auth_user_id=owner_uid;
 if n<>1 then raise exception 'The review query did not report the mixed account'; end if;

 raise notice 'PASS: a staff or owner login is refused and leaves no customer, account or claim behind, an ordinary applicant is unaffected, and accounts already holding both are reportable';
end $$;
rollback;
