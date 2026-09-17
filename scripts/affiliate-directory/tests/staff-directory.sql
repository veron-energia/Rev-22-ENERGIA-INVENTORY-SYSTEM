-- Staff may look up an affiliate's referral link, and nothing more (332).
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); mgr uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid();
 st uuid; c uuid; susp uuid; i int; r jsonb; keys text[]; msg text; cust uuid;
begin
 insert into auth.users(id,email) values(own,'ad-own@tests.invalid'),(mgr,'ad-mgr@tests.invalid'),(stf,'ad-stf@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','ad-own@tests.invalid','owner'),(mgr,'Manager','ad-mgr@tests.invalid','manager'),(stf,'Staff','ad-stf@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('AD Store','ADS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(mgr,st),(stf,st);

 -- 1,100 affiliates: past the API row limit, so paging is not optional.
 for i in 1..1100 loop
  insert into customers(full_name,phone) values('Dir Aff '||lpad(i::text,4,'0'),'+65'||(91200000+i)::text) returning id into cust;
  insert into customer_affiliates(customer_id,status,activated_at,referral_code) values(cust,'active',now(),generate_affiliate_referral_code());
  if i=7 then susp:=cust; end if;
 end loop;
 update customer_affiliates set manually_suspended=true, suspended_at=now(), suspend_reason='private review note' where customer_id=susp;

 -- ---- staff: the directory, paged and searched on the server -------------
 perform set_config('request.jwt.claim.sub',stf::text,true);
 r:=affiliate_staff_directory(null,50,0);
 if (r->>'total')::int<1100 then raise exception 'FAIL: staff total % is short of the 1100 created', r->>'total'; end if;
 if jsonb_array_length(r->'rows')<>50 then raise exception 'FAIL: expected a page of 50, got %', jsonb_array_length(r->'rows'); end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(r->'rows'->0) k;
 if keys<>array['customer_id','full_name','link_usable','referral_code','status'] then
  raise exception 'FAIL: staff rows expose %', keys; end if;
 if (r::text) like '%private review note%' then raise exception 'FAIL: a suspension note leaked to staff'; end if;
 r:=affiliate_staff_directory('Dir Aff 0077',50,0);
 if (r->>'total')::int<>1 or r->'rows'->0->>'full_name'<>'Dir Aff 0077' then raise exception 'FAIL: search by name did not find exactly one'; end if;
 r:=affiliate_staff_directory((select referral_code from customer_affiliates where customer_id=susp),50,0);
 if (r->>'total')::int<>1 then raise exception 'FAIL: search by code did not find the affiliate'; end if;
 if (r->'rows'->0->>'link_usable')::boolean or r->'rows'->0->>'status'<>'suspended' then
  raise exception 'FAIL: a suspended affiliate must show as suspended with an unusable link'; end if;
 r:=affiliate_staff_directory(null,50,1050);
 if jsonb_array_length(r->'rows')<50 then raise exception 'FAIL: paging past 1000 returned %', jsonb_array_length(r->'rows'); end if;

 -- ---- staff: everything else is refused at the database --------------------
 begin perform affiliate_admin_directory(); raise exception 'FAIL: staff read the admin directory';
 exception when others then if sqlerrm like 'FAIL:%' then raise; end if; if sqlerrm not ilike '%owner%manager%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if; end;
 begin perform affiliate_pending_claims(); raise exception 'FAIL: staff read pending claims';
 exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
 begin perform suspend_affiliate(susp,'staff try'); raise exception 'FAIL: staff suspended an affiliate';
 exception when others then if sqlerrm like 'FAIL:%' then raise; end if; if sqlerrm not ilike '%owner%manager%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if; end;
 begin perform reactivate_affiliate(susp); raise exception 'FAIL: staff reactivated an affiliate';
 exception when others then if sqlerrm like 'FAIL:%' then raise; end if; if sqlerrm not ilike '%owner%manager%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if; end;
 begin perform resolve_affiliate_account_claim(gen_random_uuid(),susp,'staff try'); raise exception 'FAIL: staff resolved a claim';
 exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
 begin perform reject_affiliate_account_claim(gen_random_uuid(),'staff try'); raise exception 'FAIL: staff rejected a claim';
 exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
 begin perform reassign_customer_referrer(susp,null,'staff try'); raise exception 'FAIL: staff changed a referrer';
 exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
 -- Looking never changes anything: the code is what it was.
 if (select count(distinct referral_code) from customer_affiliates where deleted_at is null)<1100 then raise exception 'FAIL: a referral code was rotated'; end if;

 -- ---- anonymous ------------------------------------------------------------
 perform set_config('request.jwt.claim.sub','',true);
 begin r:=affiliate_staff_directory(null,50,0); raise exception 'FAIL: an anonymous caller read the directory';
 exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;

 -- ---- manager and owner keep what they had ---------------------------------
 perform set_config('request.jwt.claim.sub',mgr::text,true);
 if jsonb_array_length(affiliate_admin_directory())<1100 then raise exception 'FAIL: manager lost the admin directory'; end if;
 perform reactivate_affiliate(susp);
 if (select manually_suspended from customer_affiliates where customer_id=susp) then raise exception 'FAIL: manager could not reactivate'; end if;
 r:=affiliate_staff_directory('Dir Aff 0007',50,0);
 if not (r->'rows'->0->>'link_usable')::boolean then raise exception 'FAIL: the reactivated link is not usable'; end if;
 perform set_config('request.jwt.claim.sub',own::text,true);
 if (affiliate_staff_directory(null,10,0)->>'total')::int<1100 then raise exception 'FAIL: owner cannot use the staff directory'; end if;

 raise notice 'PASS: staff search and page a company-wide directory of names, codes, status and link usability past the row limit; suspended affiliates show as such with an unusable link; nothing about money, claims or notes is returned; staff are refused every mutation and the admin views at the database; anonymous callers are refused; managers and owners keep their capabilities; no code was rotated';
end $$;
rollback;
