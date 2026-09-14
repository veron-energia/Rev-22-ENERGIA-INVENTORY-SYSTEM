-- An existing Energia customer becoming an affiliate.
--
-- Automatic linking happens only when the VERIFIED email uniquely identifies
-- one existing customer whose phone and name also match. Anything missing,
-- changed or ambiguous is parked for staff review rather than guessed at or
-- turned into a second customer record — and the applicant can come back after
-- review and land in the right place without registering again.
--
-- Disposable database only; everything is rolled back.
begin;
create or replace function pg_temp.onb(p_uid uuid, p_first text, p_last text, p_phone text)
returns text language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  r := public.complete_affiliate_onboarding(p_first, p_last, p_phone, true);
  return coalesce(r->>'status','?');
exception when others then return 'ERROR: ' || sqlerrm;
end $$;

do $$
declare mgr uuid:=gen_random_uuid(); u_exact uuid:=gen_random_uuid(); u_noemail uuid:=gen_random_uuid();
 u_changed uuid:=gen_random_uuid(); u_new uuid:=gen_random_uuid(); u_amb uuid:=gen_random_uuid();
 u_cap uuid:=gen_random_uuid(); u_unv uuid:=gen_random_uuid();
 c_exact uuid; c_noemail uuid; c_changed uuid; c_a uuid; c_b uuid; c1 uuid; c2 uuid; c3 uuid;
 claim uuid; r jsonb; n int; before_cust int;
begin
 insert into auth.users(id,email,email_confirmed_at) values(mgr,'mgr@sig.invalid',now());
 insert into profiles(id,full_name,email,role) values(mgr,'Manager','mgr@sig.invalid','manager');
 insert into auth.users(id,email,email_confirmed_at) values
  (u_exact,'exact@sig.invalid',now()),(u_noemail,'noemail@sig.invalid',now()),
  (u_changed,'new@sig.invalid',now()),(u_new,'brandnew@sig.invalid',now()),
  (u_amb,'amb@sig.invalid',now()),(u_cap,'cap3@sig.invalid',now());
 insert into auth.users(id,email) values(u_unv,'unverified@sig.invalid');   -- not confirmed

 -- ---- 1. verified email uniquely identifies the customer: links ------------
 insert into customers(full_name,phone,email) values('Alice Tan','+6591210001','exact@sig.invalid') returning id into c_exact;
 if pg_temp.onb(u_exact,'Alice','Tan','+6591210001')<>'active' then
  raise exception 'An exactly matching existing customer was not linked'; end if;
 if (select customer_id from affiliate_accounts where auth_user_id=u_exact)<>c_exact then
  raise exception 'Linked to the wrong customer'; end if;
 if (select count(*) from customers where phone='+6591210001' and deleted_at is null)<>1 then
  raise exception 'A duplicate customer was created for an exact match'; end if;

 -- ---- 2. existing customer with no email: parked, not duplicated -----------
 insert into customers(full_name,phone) values('Bob Lim','+6591210002') returning id into c_noemail;
 if pg_temp.onb(u_noemail,'Bob','Lim','+6591210002')<>'pending_verification' then
  raise exception 'A customer with no email on file was not sent for review'; end if;
 if (select count(*) from customers where phone='+6591210002' and deleted_at is null)<>1 then
  raise exception 'Review created a second customer record'; end if;
 if (select candidate_customer_id from affiliate_account_claims where auth_user_id=u_noemail)<>c_noemail then
  raise exception 'The claim does not point at the real customer'; end if;

 -- ---- 3. existing customer whose email changed: parked ---------------------
 insert into customers(full_name,phone,email) values('Cara Ng','+6591210003','old@sig.invalid') returning id into c_changed;
 if pg_temp.onb(u_changed,'Cara','Ng','+6591210003')<>'pending_verification' then
  raise exception 'A changed email was not sent for review'; end if;
 -- and the public form did NOT overwrite the customer's contact details
 if (select email from customers where id=c_changed)<>'old@sig.invalid' then
  raise exception 'The public signup form overwrote the customer''s email'; end if;

 -- ---- 4. two people sharing a phone with the same name: never guessed ------
 insert into customers(full_name,phone,email) values('Dee Wong','+6591210004','dee1@sig.invalid') returning id into c_a;
 insert into customers(full_name,phone,email) values('Dee Wong','+6591210004','dee2@sig.invalid') returning id into c_b;
 if pg_temp.onb(u_amb,'Dee','Wong','+6591210004')<>'pending_verification' then
  raise exception 'An ambiguous match was resolved automatically'; end if;
 if (select candidate_customer_id from affiliate_account_claims where auth_user_id=u_amb) is not null then
  raise exception 'An ambiguous claim arbitrarily picked one customer'; end if;

 -- ---- 5. a genuinely new person gets one customer --------------------------
 select count(*) into before_cust from customers;
 if pg_temp.onb(u_new,'Eve','Koh','+6591210005')<>'active' then
  raise exception 'A new applicant was not onboarded'; end if;
 if (select count(*) from customers)<>before_cust+1 then
  raise exception 'A new applicant did not create exactly one customer'; end if;

 -- ---- 6. an existing customer links even when the phone is full ------------
 insert into customers(full_name,phone,email) values('F One','+6591210006','f1@sig.invalid') returning id into c1;
 insert into customers(full_name,phone,email) values('F Two','+6591210006','f2@sig.invalid') returning id into c2;
 insert into customers(full_name,phone,email) values('F Three','+6591210006','cap3@sig.invalid') returning id into c3;
 if (select used from customer_phone_capacity where phone='+6591210006')<>3 then
  raise exception 'Expected the phone to be at capacity'; end if;
 if pg_temp.onb(u_cap,'F','Three','+6591210006')<>'active' then
  raise exception 'An existing customer could not link while the phone was full'; end if;
 if (select used from customer_phone_capacity where phone='+6591210006')<>3 then
  raise exception 'Linking consumed another phone slot'; end if;

 -- ---- 7. an unverified identity cannot claim anything ----------------------
 if pg_temp.onb(u_unv,'Bob','Lim','+6591210002') not like 'ERROR:%verify your email%' then
  raise exception 'An unverified email was allowed to proceed'; end if;

 -- ---- 8. the applicant cannot resolve their own claim ----------------------
 select id into claim from affiliate_account_claims where auth_user_id=u_noemail;
 perform set_config('request.jwt.claim.sub',u_noemail::text,true);
 begin
  perform resolve_affiliate_account_claim(claim,c_noemail,'let me in');
  raise exception 'An applicant resolved their own claim';
 exception when others then
  if sqlerrm not like '%Only Owner or Manager%' then raise; end if; end;

 -- ---- 9. staff resolve, and the applicant returns to the right place -------
 perform set_config('request.jwt.claim.sub',mgr::text,true);
 r:=resolve_affiliate_account_claim(claim,c_noemail,'Verified by phone; matches the existing record');
 if not (r->>'ok')::boolean then raise exception 'Staff could not resolve the claim'; end if;
 if pg_temp.onb(u_noemail,'Bob','Lim','+6591210002')<>'active' then
  raise exception 'The applicant could not resume after review'; end if;
 if (select customer_id from affiliate_accounts where auth_user_id=u_noemail)<>c_noemail then
  raise exception 'Resuming linked the wrong customer'; end if;
 if (select count(*) from customers where phone='+6591210002' and deleted_at is null)<>1 then
  raise exception 'Resuming created a duplicate customer'; end if;
 if (select count(*) from customer_affiliates where customer_id=c_noemail and deleted_at is null)<>1 then
  raise exception 'Resuming created a duplicate affiliate membership'; end if;

 -- ---- 10. repeating the whole thing changes nothing ------------------------
 if pg_temp.onb(u_exact,'Alice','Tan','+6591210001')<>'active' then
  raise exception 'A repeat submission broke a linked account'; end if;
 if (select count(*) from affiliate_accounts where auth_user_id=u_exact)<>1 then
  raise exception 'A repeat submission created a second account link'; end if;

 raise notice 'PASS: an exactly matching customer links, missing/changed/ambiguous details are parked for review without duplicating or overwriting anything, a new applicant gets one record, an existing customer links on a full phone without consuming a slot, unverified and self-resolution are refused, and the applicant resumes correctly after review';
end $$;
rollback;
