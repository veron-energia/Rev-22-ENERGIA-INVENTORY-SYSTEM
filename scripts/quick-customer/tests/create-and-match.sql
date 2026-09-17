-- Creating a customer from inside an invoice, without making a second one.
--
-- The same fields and rules as the Customers page, plus two things that page
-- does not need: a look for people already on file under the phone, and
-- protection against the same creation arriving twice, because a lost response
-- and a second click are the same thing from the server's side.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); aff_uid uuid:=gen_random_uuid();
 r jsonb; c1 uuid; c2 uuid; c3 uuid; deleted_id uuid; rq uuid:=gen_random_uuid(); n int;
begin
 insert into auth.users(id,email) values(own,'qc@t.invalid'),(aff_uid,'qa@t.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','qc@t.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);

 -- ---- a genuinely new customer --------------------------------------------
 r:=create_customer_quick('Ada','Lovelace','+6591234501',null,null,null,null,null,null,null,rq);
 c1:=(r->>'customer_id')::uuid;
 if c1 is null then raise exception 'No customer was created'; end if;
 if (select full_name from customers where id=c1)<>'Ada Lovelace' then
  raise exception 'The full name was not derived from the parts'; end if;
 if not (select is_referrer from customers where id=c1) then
  raise exception 'is_referrer was not set the way the Customers page sets it'; end if;

 -- ---- the same request id again returns the same customer -----------------
 r:=create_customer_quick('Ada','Lovelace','+6591234501',null,null,null,null,null,null,null,rq);
 if not (r->>'replayed')::boolean then raise exception 'A retry was not recognised'; end if;
 if (r->>'customer_id')::uuid<>c1 then raise exception 'A retry created a different customer'; end if;
 select count(*) into n from customers where phone='+6591234501' and deleted_at is null;
 if n<>1 then raise exception 'A retry created a second record (% exist)', n; end if;

 -- ---- candidates are found before a duplicate is made ---------------------
 r:=customer_match_candidates('+6591234501','Ada Lovelace');
 if jsonb_array_length(r->'candidates')<>1 then
  raise exception 'The existing customer was not offered as a match'; end if;
 if not (r->'candidates'->0->>'name_matches')::boolean then
  raise exception 'An identical name was not flagged as matching'; end if;
 if (r->>'used')::int<>1 or (r->>'remaining')::int<>2 then
  raise exception 'The phone capacity was reported wrongly: used=% remaining=%',
    r->>'used', r->>'remaining'; end if;
 -- and it says nothing about their money
 if (r->'candidates'->0) ? 'balance' or (r->'candidates'->0) ? 'phone' then
  raise exception 'The candidate exposed more than it needs to'; end if;

 -- ---- a different person on the same phone is allowed ---------------------
 r:=create_customer_quick('Grace','Hopper','+6591234501',null,null,null,null,null,null,null,gen_random_uuid());
 c2:=(r->>'customer_id')::uuid;
 r:=create_customer_quick('Alan','Turing','+6591234501',null,null,null,null,null,null,null,gen_random_uuid());
 c3:=(r->>'customer_id')::uuid;
 if c2 is null or c3 is null then raise exception 'A shared phone blocked a different person'; end if;

 -- ---- but the fourth is refused -------------------------------------------
 begin
  perform create_customer_quick('Fourth','Person','+6591234501',null,null,null,null,null,null,null,gen_random_uuid());
  raise exception 'A fourth customer was allowed on one phone';
 exception when others then
  if sqlerrm not like '%CUSTOMER_PHONE_LIMIT%' then raise; end if; end;

 -- ---- a deleted customer does not consume a slot --------------------------
 update customers set deleted_at=now() where id=c3 returning id into deleted_id;
 r:=customer_match_candidates('+6591234501',null);
 if (r->>'used')::int<>2 then
  raise exception 'A deleted customer is still counted: used=%', r->>'used'; end if;
 if jsonb_array_length(r->'candidates')<>2 then
  raise exception 'A deleted customer is still offered as a match'; end if;
 r:=create_customer_quick('Fourth','Person','+6591234501',null,null,null,null,null,null,null,gen_random_uuid());
 if (r->>'customer_id') is null then
  raise exception 'A freed slot did not allow a new customer'; end if;

 -- ---- required fields ------------------------------------------------------
 begin
  perform create_customer_quick('','Nameless','+6591234599',null,null,null,null,null,null,null,gen_random_uuid());
  raise exception 'A customer with no first name was created';
 exception when others then
  if sqlerrm not like '%first name is required%' then raise; end if; end;
 begin
  perform create_customer_quick('No','Phone','',null,null,null,null,null,null,null,gen_random_uuid());
  raise exception 'A customer with no phone was created';
 exception when others then
  if sqlerrm not like '%Phone number is required%' then raise; end if; end;

 -- ---- a login with no staff profile is refused ----------------------------
 perform set_config('request.jwt.claim.sub',aff_uid::text,true);
 begin
  perform create_customer_quick('Not','Staff','+6591234598',null,null,null,null,null,null,null,gen_random_uuid());
  raise exception 'A non-staff login created a customer';
 exception when others then
  if sqlerrm not like '%do not have permission%' then raise; end if; end;
 begin
  perform customer_match_candidates('+6591234501',null);
  raise exception 'A non-staff login searched customers';
 exception when others then
  if sqlerrm not like '%do not have permission%' then raise; end if; end;

 raise notice 'PASS: a customer is created with the same fields and rules as the Customers page, retries return the first record rather than a second, existing people on the phone are offered without exposing their details, three may share a number and a fourth is refused, a deleted record frees its slot, and a login without a staff profile is refused';
end $$;
rollback;
