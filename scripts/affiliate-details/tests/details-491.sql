-- An affiliate changes their own name, phone and email (491; the user, 3 Nov
-- 2026), beyond 491's own self-test.
--
--   E1 The routes: free (unverified, own record), verify_first (unverified,
--      joined to an existing record), code (verified, proven), staff
--      (verified, not proven), closed (a staff login).
--   E2 One open request at a time; at most 5 a day.
--   E3 A code: 5 tries, then the request ends; a minute between sends, 5
--      sends a step; an expired code ends the request.
--   E4 The staff route: codes, then it waits; only an active Owner or
--      Manager decides; a rejection needs a note; an approval applies.
--   E5 What the portal reads: the details and the latest request, never a
--      code or its hash; the staff list for an Owner or Manager only.
--   E6 An email another login or customer has is refused.
--   E7 The phone flag: shown until a payout is recorded after the change.
--   E8 The login's email put back while 'applying' keeps its verification.
--
-- Run on a copy of production with 491 in (createdb -T of a template equal
-- to it; never the template itself):
--   psql -d <copy> -v ON_ERROR_STOP=1 -f scripts/affiliate-details/tests/details-491.sql
-- Every check runs, then the file fails if any did. Everything is rolled
-- back. Fixtures are invented (the repository is public).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k=key $$;
-- Sign in as someone, as the portal or the staff app does.
create function pg_temp.as_user(uid uuid) returns void language sql as
$$ select set_config('request.jwt.claim.sub', uid::text, true),
          set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true) $$;

-- ═════ Fixtures (invented) ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); ph text[]; v uuid; c uuid; u uuid; srr text;
begin
  ph := array(select '+6125550' || lpad(n::text, 4, '0') from generate_series(3000, 9999) n
               where not exists (select 1 from customers x where public.normalize_customer_phone(x.phone) = '+6125550' || lpad(n::text, 4, '0'))
                 and not exists (select 1 from affiliate_signup_identities i where public.normalize_customer_phone(i.phone) = '+6125550' || lpad(n::text, 4, '0'))
               order by n limit 9);
  for i in 1 .. 9 loop insert into tx values ('ph' || i, ph[i]); end loop;
  insert into tx values ('sfx', sfx);
  -- Staff: an Owner and a Staff member.
  insert into auth.users(id, email) values (gen_random_uuid(), 'e491-owner-' || sfx || '@example.invalid') returning id into u;
  insert into profiles(id, full_name, email, role, is_active) values (u, 'E491 Owner', 'e491-owner-' || sfx || '@example.invalid', 'owner', true);
  insert into fx values ('owner', u);
  insert into auth.users(id, email) values (gen_random_uuid(), 'e491-staff-' || sfx || '@example.invalid') returning id into u;
  insert into profiles(id, full_name, email, role, is_active) values (u, 'E491 Staff', 'e491-staff-' || sfx || '@example.invalid', 'staff', true);
  insert into fx values ('staff', u);
  srr := current_setting('session_replication_role');
  -- A: unverified, the record its own sign-up made (free).
  insert into auth.users(id, email) values (gen_random_uuid(), 'e491-a-' || sfx || '@example.invalid') returning id into u;
  insert into customers(first_name, last_name, full_name, phone, email) values ('Ann', 'Test', 'Ann Test', ph[1], 'e491-a-' || sfx || '@example.invalid') returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), 'E491A' || upper(sfx)) returning id into v;
  set local session_replication_role = replica;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (u, c, v, 'claimed');
  execute format('set local session_replication_role = %L', srr);
  insert into fx values ('a', u), ('a_cust', c);
  -- B: verified, joined to a record made a month before (not its own), whose email is another (staff route).
  insert into auth.users(id, email) values (gen_random_uuid(), 'e491-b-' || sfx || '@example.invalid') returning id into u;
  insert into customers(first_name, last_name, full_name, phone, email, created_at) values ('Ben', 'Test', 'Ben Test', ph[2], 'e491-b-record-' || sfx || '@example.invalid', now() - interval '30 days') returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), 'E491B' || upper(sfx)) returning id into v;
  set local session_replication_role = replica;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status, email_verified_at) values (u, c, v, 'claimed', now());
  execute format('set local session_replication_role = %L', srr);
  insert into fx values ('b', u), ('b_cust', c);
  -- C: unverified, joined to an existing record (verify first).
  insert into auth.users(id, email) values (gen_random_uuid(), 'e491-c-' || sfx || '@example.invalid') returning id into u;
  insert into customers(first_name, last_name, full_name, phone, created_at) values ('Cal', 'Test', 'Cal Test', ph[3], now() - interval '30 days') returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), 'E491C' || upper(sfx)) returning id into v;
  set local session_replication_role = replica;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (u, c, v, 'claimed');
  execute format('set local session_replication_role = %L', srr);
  insert into fx values ('c', u), ('c_cust', c);
  -- D: a staff login that also has an account (closed).
  insert into customers(first_name, last_name, full_name, phone) values ('Dee', 'Test', 'Dee Test', ph[4]) returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), 'E491D' || upper(sfx)) returning id into v;
  set local session_replication_role = replica;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('staff'), c, v, 'claimed');
  execute format('set local session_replication_role = %L', srr);
  -- Another customer, holding a phone and an email.
  insert into customers(full_name, phone, email) values ('E491 Other', ph[5], 'e491-other-' || sfx || '@example.invalid') returning id into c;
  insert into fx values ('other', c);
end $$;

-- ═════ E1 The routes ═════
do $$
begin
  perform pg_temp.check(public.affiliate_detail_state(pg_temp.fx('a'))->>'route' = 'free', 'E1 unverified on its own record: free');
  perform pg_temp.check(public.affiliate_detail_state(pg_temp.fx('c'))->>'route' = 'verify_first', 'E1 unverified on an existing record: verify first');
  perform pg_temp.check(public.affiliate_detail_change_start(pg_temp.fx('c'), '{"first_name": "Callum"}')->>'error' = 'verify_first', 'E1 and its start is refused');
  perform pg_temp.check(public.affiliate_detail_state(pg_temp.fx('b'))->>'route' = 'staff', 'E1 verified but not proven: staff');
  perform pg_temp.check(public.affiliate_detail_state(pg_temp.fx('staff'))->>'route' = 'closed', 'E1 a staff login: closed');
  update affiliate_accounts set email_verified_at = now() where auth_user_id = pg_temp.fx('a');
  perform pg_temp.check(public.affiliate_detail_state(pg_temp.fx('a'))->>'route' = 'code', 'E1 verified and proven: code');
end $$;

-- ═════ E2 One at a time; 5 a day ═════
do $$
declare r jsonb;
begin
  r := public.affiliate_detail_change_start(pg_temp.fx('a'), '{"first_name": "Anne"}');
  insert into tx values ('e2_id', r->>'request_id');
  perform pg_temp.check(public.affiliate_detail_change_start(pg_temp.fx('a'), '{"last_name": "Other"}')->>'error' = 'open_request', 'E2 a second request while one is open is refused');
  perform pg_temp.check((public.affiliate_detail_change_cancel(pg_temp.fx('a'), (r->>'request_id')::uuid))->>'status' = 'cancelled', 'E2 cancel');
  for i in 1 .. 4 loop
    r := public.affiliate_detail_change_start(pg_temp.fx('a'), jsonb_build_object('first_name', 'Anne' || repeat('e', i)));
    perform public.affiliate_detail_change_cancel(pg_temp.fx('a'), (r->>'request_id')::uuid);
  end loop;
  perform pg_temp.check(public.affiliate_detail_change_start(pg_temp.fx('a'), '{"first_name": "Annie"}')->>'error' = 'too_many_requests', 'E2 the sixth request in a day is refused');
  delete from affiliate_detail_changes where auth_user_id = pg_temp.fx('a');
end $$;

-- ═════ E3 Codes: tries, sends, expiry ═════
do $$
declare r jsonb; rid uuid;
begin
  r := public.affiliate_detail_change_start(pg_temp.fx('a'), '{"first_name": "Anne"}');
  rid := (r->>'request_id')::uuid;
  perform pg_temp.check(public.affiliate_detail_change_resend(pg_temp.fx('a'), rid)->>'error' = 'wait', 'E3 a resend within a minute waits');
  for i in 1 .. 4 loop
    r := public.affiliate_detail_change_verify(pg_temp.fx('a'), rid, '0000' || lpad(i::text, 2, '0'));
  end loop;
  perform pg_temp.check(r->>'error' = 'wrong_code' and (r->>'tries_left')::int = 1, 'E3 four wrong codes leave one try (' || r::text || ')');
  r := public.affiliate_detail_change_verify(pg_temp.fx('a'), rid, '000009');
  perform pg_temp.check(r->>'error' = 'too_many_tries' and (select status from affiliate_detail_changes where id = rid limit 1) is not null, 'E3 the fifth ends the request');
  perform pg_temp.check((select status from affiliate_detail_changes d where d.id = rid) = 'expired', 'E3 it is no longer open');
  -- sends: a minute apart, 5 a step
  r := public.affiliate_detail_change_start(pg_temp.fx('a'), '{"first_name": "Anne"}');
  rid := (r->>'request_id')::uuid;
  update affiliate_detail_changes set code_sent_at = now() - interval '2 minutes', code_sends = 4 where affiliate_detail_changes.id = rid;
  perform pg_temp.check(public.affiliate_detail_change_resend(pg_temp.fx('a'), rid)->'send'->>'to' is not null, 'E3 a fifth send after a minute');
  update affiliate_detail_changes set code_sent_at = now() - interval '2 minutes' where affiliate_detail_changes.id = rid;
  perform pg_temp.check(public.affiliate_detail_change_resend(pg_temp.fx('a'), rid)->>'error' = 'too_many_sends', 'E3 no sixth send');
  -- expiry
  update affiliate_detail_changes set code_expires_at = now() - interval '1 second' where affiliate_detail_changes.id = rid;
  perform pg_temp.check(public.affiliate_detail_change_verify(pg_temp.fx('a'), rid, '123456')->>'error' = 'expired', 'E3 an expired code ends the request');
  delete from affiliate_detail_changes where auth_user_id = pg_temp.fx('a');
end $$;

-- ═════ E4 The staff route ═════
do $$
declare r jsonb; rid uuid;
begin
  r := public.affiliate_detail_change_start(pg_temp.fx('b'), jsonb_build_object('phone', pg_temp.tx('ph6')));
  rid := (r->>'request_id')::uuid;
  perform pg_temp.check(r->>'next' = 'code' and r->'send'->>'to' like 'e491-b-%', 'E4 the staff route sends a code to the login first');
  r := public.affiliate_detail_change_verify(pg_temp.fx('b'), rid, r->'send'->>'code');
  perform pg_temp.check(r->>'next' = 'pending_staff', 'E4 then it waits for staff (' || r::text || ')');
  perform pg_temp.check(public.affiliate_detail_change_decide(pg_temp.fx('staff'), rid, true, null)->>'error' = 'not_allowed', 'E4 a Staff member cannot decide');
  perform pg_temp.check(public.affiliate_detail_change_decide(pg_temp.fx('owner'), rid, false, '')->>'error' = 'note_required', 'E4 a rejection needs a note');
  r := public.affiliate_detail_change_decide(pg_temp.fx('owner'), rid, true, 'Checked at the counter');
  perform pg_temp.check(r->>'next' = 'apply', 'E4 an Owner approves: apply');
  r := public.affiliate_detail_change_finish(rid, true, null);
  perform pg_temp.check(r->>'status' = 'applied' and (select public.normalize_customer_phone(phone) from customers where id = pg_temp.fx('b_cust')) = pg_temp.tx('ph6'),
    'E4 and the new phone is on the record');
  perform pg_temp.check(exists (select 1 from audit_logs l where l.record_id = pg_temp.fx('b_cust') and l.action = 'customer_details_changed_by_affiliate'
                                  and l.changed_by = pg_temp.fx('owner') and l.reason = 'Approved by staff'), 'E4 the Audit Log names the Owner who approved');
  perform pg_temp.check(exists (select 1 from customer_phone_history h where h.customer_id = pg_temp.fx('b_cust') and h.reason = 'Changed by the affiliate in the portal'),
    'E4 the phone history says why');
  -- a rejection
  r := public.affiliate_detail_change_start(pg_temp.fx('b'), '{"first_name": "Benny"}');
  rid := (r->>'request_id')::uuid;
  perform public.affiliate_detail_change_verify(pg_temp.fx('b'), rid, r->'send'->>'code');
  r := public.affiliate_detail_change_decide(pg_temp.fx('owner'), rid, false, 'Not the same person');
  perform pg_temp.check(r->>'status' = 'rejected' and (select first_name from customers where id = pg_temp.fx('b_cust')) = 'Ben', 'E4 a rejection changes nothing');
  insert into tx values ('b_rejected', rid::text);
  -- requests seconds apart, as at a real counter (in one transaction all share one time)
  update affiliate_detail_changes set created_at = now() + interval '1 second' where id = rid;
end $$;

-- ═════ E5 What the portal and staff read ═════
do $$
declare r jsonb; e text;
begin
  perform pg_temp.as_user(pg_temp.fx('b'));
  r := public.affiliate_portal_details();
  perform pg_temp.check(r->>'route' = 'staff' and r->>'first_name' = 'Ben' and r->'request'->>'status' = 'rejected'
      and r->'request'->>'decision_note' = 'Not the same person', 'E5 the portal sees its details and the rejection with its note');
  perform pg_temp.check(r::text !~ 'code_hash' and r->'request' ? 'code_for' and not (r::text ~ '"[0-9]{6}"'), 'E5 never a code or its hash');
  perform pg_temp.as_user(pg_temp.fx('staff'));
  begin perform public.affiliate_detail_change_requests(); exception when others then e := sqlstate; end;
  perform pg_temp.check(e = '42501', 'E5 a Staff member cannot list requests');
  perform pg_temp.as_user(pg_temp.fx('owner'));
  perform pg_temp.check(jsonb_typeof(public.affiliate_detail_change_requests()) = 'array', 'E5 an Owner can');
end $$;

-- ═════ E6 Emails in use ═════
do $$
begin
  perform pg_temp.check(public.affiliate_detail_check(pg_temp.fx('a'), jsonb_build_object('email', 'e491-b-' || pg_temp.tx('sfx') || '@example.invalid'))->>'error' = 'email_in_use',
    'E6 another login''s email is refused');
  perform pg_temp.check(public.affiliate_detail_check(pg_temp.fx('a'), jsonb_build_object('email', upper('e491-other-' || pg_temp.tx('sfx') || '@example.invalid')))->>'error' = 'email_in_use',
    'E6 another customer''s email is refused, whatever its case');
  perform pg_temp.check(public.affiliate_detail_check(pg_temp.fx('a'), '{"email": "not an email"}')->>'error' = 'email_invalid', 'E6 a malformed email is refused');
  perform pg_temp.check(public.affiliate_detail_check(pg_temp.fx('a'), '{"last_name": "D/O Raj"}') ? 'changes', 'E6 "D/O" is allowed in a name');
end $$;

-- ═════ E7 The phone flag until the next payout ═════
do $$
declare r jsonb;
begin
  perform pg_temp.as_user(pg_temp.fx('owner'));
  r := public.affiliate_self_phone_change(pg_temp.fx('b_cust'));
  perform pg_temp.check(r->>'new_phone' = pg_temp.tx('ph6') and r->>'old_phone' = pg_temp.tx('ph2'), 'E7 the phone the affiliate changed is flagged (' || coalesce(r::text, 'null') || ')');
  insert into commission_payouts (payout_month, referrer_customer_id, total_tier1, total_tier2, total_amount, status, paid_at, created_at, payment_date, version, allocation_state)
  values (date_trunc('month', now())::date, pg_temp.fx('b_cust'), 1, 0, 1, 'paid', now() + interval '1 minute', now() + interval '1 minute', current_date, 1, 'verified');
  perform pg_temp.check(public.affiliate_self_phone_change(pg_temp.fx('b_cust')) is null, 'E7 after a payout, no longer flagged');
end $$;

-- ═════ E8 The login's email put back while 'applying' ═════
do $$
declare r jsonb; rid uuid; old text;
begin
  select email into old from auth.users where id = pg_temp.fx('a');
  r := public.affiliate_detail_change_start(pg_temp.fx('a'), jsonb_build_object('email', 'e491-a-new-' || pg_temp.tx('sfx') || '@example.invalid'));
  rid := (r->>'request_id')::uuid;
  r := public.affiliate_detail_change_verify(pg_temp.fx('a'), rid, r->'send'->>'code');
  r := public.affiliate_detail_change_verify(pg_temp.fx('a'), rid, r->'send'->>'code');
  perform pg_temp.check(r->>'next' = 'apply', 'E8 both codes right: apply');
  update auth.users set email = r->'apply'->>'login_email' where id = pg_temp.fx('a');
  update auth.users set email = old where id = pg_temp.fx('a');   -- the record could not be saved: put back
  perform pg_temp.check((select email_verified_at from affiliate_accounts where auth_user_id = pg_temp.fx('a')) is not null,
    'E8 changing and putting back the email while applying keeps the account verified');
  perform public.affiliate_detail_change_finish(rid, false, 'record not saved');
  perform pg_temp.check((select status from affiliate_detail_changes d where d.id = rid) = 'failed', 'E8 and the request is marked failed');
end $$;

do $$
declare n int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
  raise notice 'ALL PASSED: routes, limits, codes, the staff route, what is read, emails in use, the phone flag and the put-back';
end $$;
rollback;
