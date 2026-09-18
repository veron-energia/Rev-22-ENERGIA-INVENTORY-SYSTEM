-- Onboarding uses the details it already has (333).
--
-- The verification link opened on a phone rarely lands in the browser that
-- filled the form, so the browser's copy of name and phone is often gone. The
-- account has its own copy, stored at sign-up. Disposable database only.
begin;
do $$
declare u1 uuid:=gen_random_uuid(); u2 uuid:=gen_random_uuid(); u3 uuid:=gen_random_uuid(); u4 uuid:=gen_random_uuid();
 r jsonb; c uuid; msg text;
begin
 -- u1: signed up through the form; the account carries the details.
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
  values(u1,'meta-1@sig.invalid',now(),jsonb_build_object('first_name','Mei','last_name','Tan','phone','+6591920001','role_hint','affiliate'));
 -- u2: an older account with no metadata at all.
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values(u2,'meta-2@sig.invalid',now(),'{}'::jsonb);
 -- u3: metadata present, but the form on the verify screen says something else.
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
  values(u3,'meta-3@sig.invalid',now(),jsonb_build_object('first_name','Wrong','last_name','Name','phone','+6591920003'));
 -- u4: the sign-up stored only a phone, no name.
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
  values(u4,'meta-4@sig.invalid',now(),jsonb_build_object('phone','+6591920004'));

 -- ---- the browser lost its copy: the account's own details are enough -----
 perform set_config('request.jwt.claim.sub',u1::text,true);
 r:=complete_affiliate_onboarding('','','',true);
 if r->>'status'<>'active' then raise exception 'FAIL: onboarding from metadata did not activate: %', r; end if;
 select id into c from customers where full_name='Mei Tan' and phone='+6591920001' and deleted_at is null;
 if c is null then raise exception 'FAIL: the customer was not created from the account''s details'; end if;
 if not exists (select 1 from affiliate_accounts where auth_user_id=u1 and customer_id=c) then raise exception 'FAIL: no affiliate account'; end if;

 -- ---- asked again? already onboarded answers without any details ---------
 r:=complete_affiliate_onboarding(null,null,null,true);
 if not (r->>'already')::boolean or r->>'status'<>'active' then raise exception 'FAIL: an existing affiliate was not answered as already onboarded: %', r; end if;
 if (select count(*) from customers where phone='+6591920001' and deleted_at is null)<>1 then raise exception 'FAIL: a second customer was created'; end if;

 -- ---- nothing anywhere: a clear, stable refusal the screen can act on -----
 perform set_config('request.jwt.claim.sub',u2::text,true);
 begin
  r:=complete_affiliate_onboarding('','','',true);
  raise exception 'FAIL: onboarding with no details at all was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like 'DETAILS_REQUIRED:%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 -- ...and once the person types them, it works as before.
 r:=complete_affiliate_onboarding('Old','Account','+6591920002',true);
 if r->>'status'<>'active' then raise exception 'FAIL: typed details were not accepted: %', r; end if;

 -- ---- what the person types wins over what the account holds ---------------
 perform set_config('request.jwt.claim.sub',u3::text,true);
 r:=complete_affiliate_onboarding('Right','Person','+6591920013',true);
 if not exists (select 1 from customers where full_name='Right Person' and phone='+6591920013') then
  raise exception 'FAIL: explicit details did not override the account metadata'; end if;
 if exists (select 1 from customers where full_name='Wrong Name') then raise exception 'FAIL: metadata was used despite explicit details'; end if;

 -- ---- half a record is not enough: name still required ---------------------
 perform set_config('request.jwt.claim.sub',u4::text,true);
 begin
  r:=complete_affiliate_onboarding('','','',true);
  raise exception 'FAIL: a phone with no name was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like 'DETAILS_REQUIRED:%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;

 -- ---- metadata can never make a staff login an affiliate ------------------
 update auth.users set raw_user_meta_data = raw_user_meta_data || '{"role_hint":"owner"}' where id=u1;
 perform set_config('request.jwt.claim.sub',u1::text,true);
 r:=complete_affiliate_onboarding(null,null,null,true);
 if not (r->>'already')::boolean then raise exception 'FAIL: metadata changed the outcome'; end if;
 if exists (select 1 from profiles where id=u1) then raise exception 'FAIL: a profile appeared from metadata'; end if;

 raise notice 'PASS: onboarding completes from the account''s own details when the browser has none, answers an existing affiliate without asking, refuses with DETAILS_REQUIRED only when nothing is known, lets typed details override the account, and grants nothing from metadata';
end $$;
rollback;
