-- An affiliate who cannot open their current email changes it with a code to the new email and an Owner's or
-- Manager's approval (493; the user, 6 Nov 2026), beyond 493's own self-test.
--
--   I   493 twice: the first run adds one column and one function and replaces the staff list, nothing else, and leaves
--       no row and moves no sequence; the second changes nothing.
--   L1  A verified, proven login: the code goes to the new email only, the row says so, nothing changes yet.
--   L2  Another code: to the new email, a minute apart; a wrong code says how many tries are left.
--   L3  The right code: it waits for staff; the new inbox is proven, the current one is not; nothing changes yet.
--   L4  What the portal reads: the request and its new email, never a code or its hash.
--   L5  The staff list says the current inbox is lost (and not for a request made the usual way), for an Owner or
--       Manager only.
--   L6  A member of Staff cannot decide; a rejection needs a note, changes nothing, and the affiliate sees the note;
--       they can then ask again.
--   L7  Approved: the login's email (as Supabase Auth's admin API changes it, known as the portal's own) and the
--       record's change, the account stays verified, the Audit Log row names the Owner, the old address is told.
--   L8  An unverified login joined to an existing record: 491's start still refuses it, this one does not; approved,
--       it is verified and the link is proven by that email.
--   L9  A verified login that is not proven (491's staff route): the same way; a Manager decides.
--   L10 Refused, nothing made: a free login, a staff login, not an affiliate; no new email; only a name; the login's own
--       email; an email another login or customer has; a bad email; an open request; 5 requests a day.
--   L11 The address on their own record can become the login's, both ways (the user's own case, 6 Nov 2026: the login
--       and the record held different addresses).
--   G   The grants; the column; refusals, nothing changed: a relied-on function changed, a staff list neither 491's nor
--       493's, a new function of another text, an overload of its name.
--
-- Run on a copy of production (createdb -T of a template equal to it; never the template itself): where 492 is the head
-- it installs 493 twice; where 493 is in, with -v skip_install=1:
--   psql -d <copy> -v ON_ERROR_STOP=1 [-v skip_install=1] -f scripts/affiliate-details/tests/details-lost-inbox-493.sql
-- Every check runs, then the file fails if any did. Everything is rolled back. Fixtures are invented (the repository
-- is public): names E493 ..., @example.invalid, ACMA's fictional +61 2 5550 phones.
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
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 'e493-' || tag || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
-- Sign in as someone, as the portal or the staff app does; and back to the server.
create function pg_temp.as_user(uid uuid) returns void language sql as
$$ select set_config('request.jwt.claim.sub', uid::text, true),
          set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true) $$;
create function pg_temp.as_server() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true) $$;
create function pg_temp.fn_md5s() returns table(fn text, md5 text, acl text) language sql set search_path = public as
$$ select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)),
          coalesce((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x), '')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
create function pg_temp.seqs() returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(s.schemaname || '.' || s.sequencename, s.last_value), '{}'::jsonb)
     from pg_sequences s where s.schemaname in ('public', 'auth') $$;
create function pg_temp.rows() returns jsonb language sql as
$$ select jsonb_build_object('customers', (select count(*) from public.customers), 'changes', (select count(*) from public.affiliate_detail_changes),
          'audit', (select count(*) from public.audit_logs), 'users', (select count(*) from auth.users)) $$;

-- ═════ I Install (where 493 is not in) ═════
\if :{?skip_install}
\else
create temp table b493 as select * from pg_temp.fn_md5s();
create temp table r493 as select pg_temp.rows() as rows0, pg_temp.seqs() as seq0;
\ir ../../../supabase/493_affiliate_email_change_without_current_inbox.sql
create temp table m493 as select * from pg_temp.fn_md5s();
alter table r493 add column rows1 jsonb, add column seq1 jsonb;
update r493 set rows1 = pg_temp.rows(), seq1 = pg_temp.seqs();
\ir ../../../supabase/493_affiliate_email_change_without_current_inbox.sql
create temp table n493 as select * from pg_temp.fn_md5s();
select pg_temp.check((select string_agg(b.fn || ' -> ' || m.md5, '; ') from b493 b join m493 m using (fn) where m.md5 <> b.md5)
                     = 'affiliate_detail_change_requests() -> e9f550aecf6c16f3b6512eef000664a3'
    and (select string_agg(m.fn || ' ' || m.md5 || ' ' || m.acl, '; ') from m493 m where not exists (select 1 from b493 b where b.fn = m.fn))
        = 'affiliate_detail_change_start_lost_inbox(uuid,jsonb) 9ebb75d3cd775feeaed55a6d60910ffe postgres=X/postgres,service_role=X/postgres'
    and not exists (select 1 from b493 b join m493 m using (fn) where m.acl <> b.acl)
    and not exists (select 1 from b493 b where not exists (select 1 from m493 m where m.fn = b.fn))
    and not exists (select 1 from m493 m join n493 n using (fn) where n.md5 <> m.md5 or n.acl <> m.acl)
    and (select count(*) from m493) = (select count(*) from n493)
    and (select rows0 = rows1 and seq0 = seq1 from r493),
  'I 493 adds one function and replaces the staff list alone, every other function and grant as they were; its self-test leaves no row and moves no sequence; the second run changes nothing');
\endif

-- ═════ Fixtures (invented) ═════
set local client_min_messages = warning;
do $$
declare sfx text := translate(lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)), '0123456789', 'ghijklmnop'); ph text[]; u uuid;
begin
  ph := array(select '+6125550' || lpad(n::text, 4, '0') from generate_series(3000, 9999) n
               where not exists (select 1 from customers x where public.normalize_customer_phone(x.phone) = '+6125550' || lpad(n::text, 4, '0'))
                 and not exists (select 1 from affiliate_signup_identities i where public.normalize_customer_phone(i.phone) = '+6125550' || lpad(n::text, 4, '0'))
               order by n limit 12);
  for i in 1 .. 12 loop insert into tx values ('ph' || i, ph[i]); end loop;
  insert into tx values ('sfx', sfx);
  foreach sfx in array array['owner', 'manager', 'staff'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), pg_temp.mail(sfx)) returning id into u;
    insert into profiles(id, full_name, email, role, is_active) values (u, 'E493 ' || sfx, pg_temp.mail(sfx), sfx::public.user_role, true);
    insert into fx values (sfx, u);
  end loop;
  -- A login with no affiliate account; another customer holding an email.
  insert into auth.users(id, email) values (gen_random_uuid(), pg_temp.mail('nolink')) returning id into u;
  insert into fx values ('nolink', u);
  insert into customers(full_name, phone, email) values ('E493 Other', pg_temp.tx('ph12'), pg_temp.mail('othercust'));
end $$;
-- An affiliate: a login, its record (made p_age ago, '0 seconds' = with its account: its own sign-up made it), an active
-- affiliate record and its portal account (triggers off for that statement only: no welcome WhatsApp).
create function pg_temp.mk(key text, n int, p_age interval, p_verified boolean, p_record_email text default null) returns void language plpgsql as
$$declare v_c uuid; v_a uuid; v_u uuid; v_srr text := current_setting('session_replication_role');
begin
  insert into auth.users(id, email) values (gen_random_uuid(), pg_temp.mail(key)) returning id into v_u;
  insert into customers(first_name, last_name, full_name, phone, email, created_at)
    values ('E493', initcap(translate(key, '0123456789', 'abcdefghij')), 'E493 ' || key, pg_temp.tx('ph' || n), coalesce(p_record_email, pg_temp.mail(key)), now() - p_age) returning id into v_c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code)
    values (v_c, 'active', now(), 'E493' || upper(translate(key, '0123456789', 'abcdefghij')) || upper(pg_temp.tx('sfx'))) returning id into v_a;
  set local session_replication_role = replica;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status, email_verified_at)
    values (v_u, v_c, v_a, 'claimed', case when p_verified then now() end);
  execute format('set local session_replication_role = %L', v_srr);
  insert into fx values (key, v_u), (key || '_cust', v_c);
end$$;
-- code: verified, its own record. codex: the same, for approvals. verifyf: unverified, joined to an existing record.
-- staffr: verified, joined to an existing record whose email is another. free: unverified, its own record. differs: verified,
-- its own record, which holds another address (the user's own case). limits: for the refusals.
select pg_temp.mk('code', 1, '0 seconds', true), pg_temp.mk('codex', 2, '0 seconds', true), pg_temp.mk('verifyf', 3, '30 days', false),
       pg_temp.mk('staffr', 4, '30 days', true, pg_temp.mail('staffr-record')), pg_temp.mk('free', 5, '0 seconds', false),
       pg_temp.mk('differs', 6, '0 seconds', true, pg_temp.mail('differs-record')), pg_temp.mk('limits', 7, '0 seconds', true);
set local client_min_messages = notice;
do $$
begin
  perform pg_temp.check(public.affiliate_detail_state(pg_temp.fx('code'))->>'route' = 'code' and public.affiliate_detail_state(pg_temp.fx('verifyf'))->>'route' = 'verify_first'
      and public.affiliate_detail_state(pg_temp.fx('staffr'))->>'route' = 'staff' and public.affiliate_detail_state(pg_temp.fx('free'))->>'route' = 'free'
      and public.affiliate_detail_state(pg_temp.fx('differs'))->>'route' = 'code',
    'F the fixture''s routes: code, verify_first, staff, free, and code on a record with another address');
end $$;

-- ═════ L1–L4 A code to the new email only; it waits for staff ═════
do $$
declare r jsonb; rid uuid; c text; row public.affiliate_detail_changes%rowtype; p jsonb;
begin
  r := public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('code'), jsonb_build_object('email', upper(pg_temp.mail('code-new')), 'first_name', 'Coded'));
  rid := (r->>'request_id')::uuid; c := r->'send'->>'code';
  select * into row from affiliate_detail_changes where id = rid;
  perform pg_temp.check(r->>'next' = 'code' and r->>'route' = 'staff' and r->'send'->>'to' = pg_temp.mail('code-new') and r->'send'->>'purpose' = 'new' and c ~ '^[0-9]{6}$'
      and row.route = 'staff' and row.status = 'awaiting_code' and row.current_inbox_lost and row.code_for = 'new' and row.code_sends = 1
      and row.old_login_email = pg_temp.mail('code') and row.new_email = pg_temp.mail('code-new') and row.new_first_name = 'Coded',
    'L1 the code goes to the new email only (tidied to lower case), the row says the inbox is lost and on the staff route: ' || (r - 'send')::text);
  perform pg_temp.check(public.affiliate_detail_change_resend(pg_temp.fx('code'), rid)->>'error' = 'wait', 'L2 another code waits a minute');
  update affiliate_detail_changes set code_sent_at = now() - interval '2 minutes' where id = rid;
  r := public.affiliate_detail_change_resend(pg_temp.fx('code'), rid);
  c := r->'send'->>'code';
  perform pg_temp.check(r->'send'->>'to' = pg_temp.mail('code-new') and r->'send'->>'purpose' = 'new' and c ~ '^[0-9]{6}$',
    'L2 and goes to the new email too');
  perform pg_temp.check(public.affiliate_detail_change_verify(pg_temp.fx('code'), rid, case when c = '000000' then '111111' else '000000' end)->>'tries_left' = '4',
    'L2 a wrong code says how many tries are left');
  r := public.affiliate_detail_change_verify(pg_temp.fx('code'), rid, c);
  select * into row from affiliate_detail_changes where id = rid;
  perform pg_temp.check(r->>'next' = 'pending_staff' and row.status = 'pending_staff' and row.new_proven_at is not null and row.current_proven_at is null and row.code_hash is null,
    'L3 the right code: it waits for staff; the new inbox is proven, the current one is not');
  perform pg_temp.check((select email from auth.users where id = pg_temp.fx('code')) = pg_temp.mail('code')
      and (select email from customers where id = pg_temp.fx('code_cust')) = pg_temp.mail('code')
      and (select first_name from customers where id = pg_temp.fx('code_cust')) = 'E493'
      and (select email_verified_at is not null from affiliate_accounts where auth_user_id = pg_temp.fx('code')),
    'L3 and nothing has changed yet');
  perform pg_temp.as_user(pg_temp.fx('code'));
  p := public.affiliate_portal_details();
  perform pg_temp.as_server();
  perform pg_temp.check(p->>'route' = 'code' and p->'request'->>'status' = 'pending_staff' and p->'request'->>'new_email' = pg_temp.mail('code-new')
      and not (p->'request' ? 'code_hash') and strpos(p::text, c) = 0,
    'L4 the portal reads the request and its new email, never a code or its hash');
  insert into tx values ('l_rid', rid::text);
end $$;

-- ═════ L5 The staff list ═════
do $$
declare v jsonb; r jsonb; rid uuid; denied text;
begin
  -- A request made the usual way (491's staff route), to compare.
  r := public.affiliate_detail_change_start(pg_temp.fx('staffr'), '{"first_name": "Usual"}');
  rid := (r->>'request_id')::uuid;
  perform public.affiliate_detail_change_verify(pg_temp.fx('staffr'), rid, r->'send'->>'code');
  perform pg_temp.as_user(pg_temp.fx('owner'));
  v := public.affiliate_detail_change_requests();
  perform pg_temp.as_server();
  perform pg_temp.check((select (x->'current_inbox_lost')::boolean and (x->'new_email_proven')::boolean and x->'old'->>'login_email' = pg_temp.mail('code')
                                and x->'new'->>'email' = pg_temp.mail('code-new')
                           from jsonb_array_elements(v) x where x->>'id' = pg_temp.tx('l_rid'))
      and (select not (x->'current_inbox_lost')::boolean from jsonb_array_elements(v) x where x->>'id' = rid::text),
    'L5 the staff list says the current inbox is lost, and not for a request made the usual way');
  perform public.affiliate_detail_change_cancel(pg_temp.fx('staffr'), rid);
  perform pg_temp.as_user(pg_temp.fx('staff'));
  begin
    perform public.affiliate_detail_change_requests();
    denied := 'answered';
  exception when others then denied := sqlstate;
  end;
  perform pg_temp.as_server();
  perform pg_temp.check(denied = '42501', 'L5 a member of Staff is refused the list: ' || denied);
end $$;

-- ═════ L6 Decisions ═════
do $$
declare r jsonb; rid uuid := pg_temp.tx('l_rid')::uuid; p jsonb;
begin
  perform pg_temp.check(public.affiliate_detail_change_decide(pg_temp.fx('staff'), rid, true, null)->>'error' = 'not_allowed', 'L6 a member of Staff cannot decide');
  perform pg_temp.check(public.affiliate_detail_change_decide(pg_temp.fx('owner'), rid, false, '  ')->>'error' = 'note_required', 'L6 a rejection needs a note');
  r := public.affiliate_detail_change_decide(pg_temp.fx('owner'), rid, false, 'Please come to the counter');
  perform pg_temp.as_user(pg_temp.fx('code'));
  p := public.affiliate_portal_details();
  perform pg_temp.as_server();
  perform pg_temp.check(r->>'status' = 'rejected' and p->'request'->>'status' = 'rejected' and p->'request'->>'decision_note' = 'Please come to the counter'
      and (select email from auth.users where id = pg_temp.fx('code')) = pg_temp.mail('code')
      and (select email from customers where id = pg_temp.fx('code_cust')) = pg_temp.mail('code'),
    'L6 rejected: nothing changes, and the affiliate sees the note');
  r := public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('code'), jsonb_build_object('email', pg_temp.mail('code-new')));
  perform pg_temp.check(r->>'next' = 'code', 'L6 and they can ask again');
  perform public.affiliate_detail_change_cancel(pg_temp.fx('code'), (r->>'request_id')::uuid);
end $$;

-- ═════ L7 Approved ═════
do $$
declare r jsonb; rid uuid; c text; v_was timestamptz; a public.affiliate_accounts%rowtype; l public.audit_logs%rowtype;
begin
  r := public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('codex'), jsonb_build_object('email', pg_temp.mail('codex-new')));
  rid := (r->>'request_id')::uuid;
  perform public.affiliate_detail_change_verify(pg_temp.fx('codex'), rid, r->'send'->>'code');
  select email_verified_at into v_was from affiliate_accounts where auth_user_id = pg_temp.fx('codex');
  r := public.affiliate_detail_change_decide(pg_temp.fx('owner'), rid, true, null);
  perform pg_temp.check(r->>'next' = 'apply' and r->'apply'->>'login_email' = pg_temp.mail('codex-new') and r->'apply'->>'old_login_email' = pg_temp.mail('codex'),
    'L7 approved: the plan changes the login''s email');
  update auth.users set email = pg_temp.mail('codex-new') where id = pg_temp.fx('codex');
  select * into a from affiliate_accounts where auth_user_id = pg_temp.fx('codex');
  perform pg_temp.check(a.email_verified_at = v_was and a.login_email_changed_at is null, 'L7 the trigger knows the change as the portal''s own');
  r := public.affiliate_detail_change_finish(rid, true, null);
  select * into a from affiliate_accounts where auth_user_id = pg_temp.fx('codex');
  select * into l from audit_logs where record_id = pg_temp.fx('codex_cust') and action = 'customer_details_changed_by_affiliate' order by created_at desc limit 1;
  perform pg_temp.check(r->>'status' = 'applied' and r->'notify'->>'to' = pg_temp.mail('codex') and (r->'notify'->>'login_email_changed')::boolean
      and (select email from customers where id = pg_temp.fx('codex_cust')) = pg_temp.mail('codex-new')
      and a.email_verified_at is not null and a.login_email_changed_at is not null
      and (select raw_app_meta_data ? 'affiliate_email_verified_at' from auth.users where id = pg_temp.fx('codex'))
      and l.changed_by = pg_temp.fx('owner') and l.reason = 'Approved by staff' and l.new_data->>'email' = pg_temp.mail('codex-new'),
    'L7 the login and the record changed, verified, the Audit Log row names the Owner, the old address is told');
end $$;

-- ═════ L8 Unverified, joined to an existing record ═════
do $$
declare r jsonb; rid uuid;
begin
  perform pg_temp.check(public.affiliate_detail_change_start(pg_temp.fx('verifyf'), jsonb_build_object('email', pg_temp.mail('verifyf-new')))->>'error' = 'verify_first',
    'L8 491''s start still says verify first');
  r := public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('verifyf'), jsonb_build_object('email', pg_temp.mail('verifyf-new')));
  rid := (r->>'request_id')::uuid;
  perform pg_temp.check(r->'send'->>'to' = pg_temp.mail('verifyf-new'), 'L8 this one sends the code to the new email');
  r := public.affiliate_detail_change_verify(pg_temp.fx('verifyf'), rid, r->'send'->>'code');
  perform pg_temp.check(r->>'next' = 'pending_staff', 'L8 and it waits for staff');
  r := public.affiliate_detail_change_decide(pg_temp.fx('manager'), rid, true, null);
  update auth.users set email = r->'apply'->>'login_email' where id = pg_temp.fx('verifyf');
  r := public.affiliate_detail_change_finish(rid, true, null);
  perform pg_temp.check(r->>'status' = 'applied'
      and (select email_verified_at is not null from affiliate_accounts where auth_user_id = pg_temp.fx('verifyf'))
      and public.affiliate_login_link_proof(pg_temp.fx('verifyf'), pg_temp.fx('verifyf_cust')) = 'verified_email'
      and public.affiliate_detail_state(pg_temp.fx('verifyf'))->>'route' = 'code',
    'L8 approved by a Manager: verified, and the link is proven by that email');
end $$;

-- ═════ L9 Verified, not proven ═════
do $$
declare r jsonb; rid uuid;
begin
  r := public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('staffr'), jsonb_build_object('email', pg_temp.mail('staffr-new')));
  rid := (r->>'request_id')::uuid;
  perform pg_temp.check(r->'send'->>'to' = pg_temp.mail('staffr-new') and r->'send'->>'purpose' = 'new', 'L9 a login that is not proven: the code goes to the new email');
  r := public.affiliate_detail_change_verify(pg_temp.fx('staffr'), rid, r->'send'->>'code');
  perform pg_temp.check(r->>'next' = 'pending_staff', 'L9 and it waits for staff');
  perform public.affiliate_detail_change_cancel(pg_temp.fx('staffr'), rid);
end $$;

-- ═════ L10 Refused, nothing made ═════
do $$
declare n0 bigint := (select count(*) from affiliate_detail_changes); u uuid := pg_temp.fx('limits'); r jsonb;
  created_before bigint;
begin
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('free'), jsonb_build_object('email', pg_temp.mail('x')))->>'error' = 'not_allowed',
    'L10 a free login has no need of it');
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('nolink'), jsonb_build_object('email', pg_temp.mail('x')))->>'error' = 'not_allowed',
    'L10 not an affiliate');
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(u, '{}'::jsonb)->>'error' = 'no_change', 'L10 nothing asked for');
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(u, '{"first_name": "Named"}')->>'error' = 'new_email_required', 'L10 only a name: no new email');
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(u, jsonb_build_object('email', pg_temp.mail('limits')))->>'error' = 'no_change', 'L10 the login''s own email');
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('differs'), jsonb_build_object('email', pg_temp.mail('differs')))->>'error' = 'new_email_required',
    'L10 the login''s own email on a record with another address: no new email either');
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(u, jsonb_build_object('email', pg_temp.mail('owner')))->>'error' = 'email_in_use', 'L10 another login''s email');
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(u, jsonb_build_object('email', pg_temp.mail('othercust')))->>'error' = 'email_in_use', 'L10 another customer''s email');
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(u, '{"email": "not an email"}')->>'error' = 'email_invalid', 'L10 a bad email');
  perform pg_temp.check((select count(*) from affiliate_detail_changes) = n0, 'L10 none of these made a request');
  r := public.affiliate_detail_change_start_lost_inbox(u, jsonb_build_object('email', pg_temp.mail('limits-new')));
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(u, jsonb_build_object('email', pg_temp.mail('limits-other')))->>'error' = 'open_request', 'L10 one open request at a time');
  perform public.affiliate_detail_change_cancel(u, (r->>'request_id')::uuid);
  insert into affiliate_detail_changes(auth_user_id, customer_id, route, status)
    select u, pg_temp.fx('limits_cust'), 'code', 'cancelled' from generate_series(1, 4);
  perform pg_temp.check(public.affiliate_detail_change_start_lost_inbox(u, jsonb_build_object('email', pg_temp.mail('limits-new')))->>'error' = 'too_many_requests', 'L10 5 requests a day, the usual ones counted');
end $$;
savepoint l10b;
do $$
declare v_a uuid; v_srr text := current_setting('session_replication_role');
begin
  perform pg_temp.check(public.affiliate_detail_state(pg_temp.fx('owner'))->>'route' = 'not_affiliate'
      and public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('owner'), jsonb_build_object('email', pg_temp.mail('x')))->>'error' = 'not_allowed',
    'L10 a staff login with no account is refused');
  -- A staff login that also has an account: closed (491's route), refused too. Undone after.
  select id into v_a from customer_affiliates where customer_id = pg_temp.fx('free_cust');
  delete from affiliate_accounts where auth_user_id = pg_temp.fx('free');
  set local session_replication_role = replica;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('manager'), pg_temp.fx('free_cust'), v_a, 'claimed');
  execute format('set local session_replication_role = %L', v_srr);
  perform pg_temp.check(public.affiliate_detail_state(pg_temp.fx('manager'))->>'route' = 'closed'
      and public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('manager'), jsonb_build_object('email', pg_temp.mail('x')))->>'error' = 'not_allowed',
    'L10 a staff login that also has an account (closed) is refused');
end $$;
rollback to savepoint l10b;

-- ═════ L11 The address on their own record can become the login's ═════
do $$
declare r jsonb; rid uuid;
begin
  -- The usual way: both codes.
  r := public.affiliate_detail_change_start(pg_temp.fx('differs'), jsonb_build_object('email', pg_temp.mail('differs-record')));
  rid := (r->>'request_id')::uuid;
  perform pg_temp.check(r->'send'->>'to' = pg_temp.mail('differs') and r->'send'->>'purpose' = 'current', 'L11 the usual way: the first code to the login''s email');
  r := public.affiliate_detail_change_verify(pg_temp.fx('differs'), rid, r->'send'->>'code');
  perform pg_temp.check(r->'send'->>'to' = pg_temp.mail('differs-record') and r->'send'->>'purpose' = 'new', 'L11 the second to the address on the record');
  r := public.affiliate_detail_change_verify(pg_temp.fx('differs'), rid, r->'send'->>'code');
  perform pg_temp.check(r->'apply'->>'login_email' = pg_temp.mail('differs-record'), 'L11 and the plan changes the login''s email to it');
  update auth.users set email = pg_temp.mail('differs-record') where id = pg_temp.fx('differs');
  r := public.affiliate_detail_change_finish(rid, true, null);
  perform pg_temp.check(r->>'status' = 'applied' and (select email_verified_at is not null from affiliate_accounts where auth_user_id = pg_temp.fx('differs')),
    'L11 applied, and still verified');
  -- The same address by the lost-inbox way, back on a fresh start: it may name the record's address too.
  update auth.users set email = pg_temp.mail('differs') where id = pg_temp.fx('differs');
  update affiliate_accounts set email_verified_at = now() where auth_user_id = pg_temp.fx('differs');
  r := public.affiliate_detail_change_start_lost_inbox(pg_temp.fx('differs'), jsonb_build_object('email', pg_temp.mail('differs-record')));
  perform pg_temp.check(r->>'next' = 'code' and r->'send'->>'to' = pg_temp.mail('differs-record'), 'L11 the lost-inbox way may name the address on the record');
  perform public.affiliate_detail_change_cancel(pg_temp.fx('differs'), (r->>'request_id')::uuid);
end $$;

-- ═════ G Grants, the column, refusals ═════
select pg_temp.check(not has_function_privilege('anon', 'public.affiliate_detail_change_start_lost_inbox(uuid,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.affiliate_detail_change_start_lost_inbox(uuid,jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.affiliate_detail_change_start_lost_inbox(uuid,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_detail_change_requests()', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_detail_change_requests()', 'execute')
    and not has_column_privilege('authenticated', 'public.affiliate_detail_changes', 'current_inbox_lost', 'select')
    and not has_column_privilege('anon', 'public.affiliate_detail_changes', 'current_inbox_lost', 'select')
    and (select a.attnotnull and pg_get_expr(d.adbin, d.adrelid) = 'false' from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
          where a.attrelid = 'public.affiliate_detail_changes'::regclass and a.attname = 'current_inbox_lost'),
  'G1 the new function is the service role''s alone, the staff list as before, the column closed to browsers, not null, default false');
create function pg_temp.g_state() returns text language sql set search_path = public as
$$ select md5(string_agg(f.fn || f.md5 || f.acl, '|' order by f.fn)) from pg_temp.fn_md5s() f $$;
select pg_temp.g_state() as g_before \gset
savepoint g2;
select pg_temp.check(true, 'G2 refusals follow (each prints an ERROR, as expected)');
do $$ begin
  execute replace(pg_get_functiondef('public.affiliate_detail_state(uuid)'::regprocedure), 'AS $function$', E'AS $function$\n-- changed');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/493_affiliate_email_change_without_current_inbox.sql
\set ON_ERROR_STOP on
\set g2_msg :LAST_ERROR_MESSAGE
rollback to savepoint g2;
savepoint g3;
do $$ begin
  execute replace(pg_get_functiondef('public.affiliate_detail_change_requests()'::regprocedure), 'AS $function$', E'AS $function$\n-- changed');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/493_affiliate_email_change_without_current_inbox.sql
\set ON_ERROR_STOP on
\set g3_msg :LAST_ERROR_MESSAGE
rollback to savepoint g3;
savepoint g4;
do $$ begin
  execute replace(pg_get_functiondef('public.affiliate_detail_change_start_lost_inbox(uuid,jsonb)'::regprocedure), 'AS $function$', E'AS $function$\n-- changed');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/493_affiliate_email_change_without_current_inbox.sql
\set ON_ERROR_STOP on
\set g4_msg :LAST_ERROR_MESSAGE
rollback to savepoint g4;
savepoint g5;
create function public.affiliate_detail_change_start_lost_inbox(p int) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/493_affiliate_email_change_without_current_inbox.sql
\set ON_ERROR_STOP on
\set g5_msg :LAST_ERROR_MESSAGE
rollback to savepoint g5;
select pg_temp.check(:'g2_msg' like '493: public.affiliate_detail_state(uuid) is missing or not the version this was tested against.%',
  'G2 a relied-on function changed is refused: ' || :'g2_msg');
select pg_temp.check(:'g3_msg' like '493: public.affiliate_detail_change_requests() is neither 491''s nor this file''s (found md5 %',
  'G3 a staff list of another version is refused: ' || :'g3_msg');
select pg_temp.check(:'g4_msg' like '493: public.affiliate_detail_change_start_lost_inbox exists and is not this file''s (found md5 %',
  'G4 a new function of another text is refused: ' || :'g4_msg');
select pg_temp.check(:'g5_msg' = '493: another function takes the name affiliate_detail_change_start_lost_inbox',
  'G5 an overload of its name is refused: ' || :'g5_msg');
select pg_temp.check(pg_temp.g_state() = :'g_before', 'G6 after the refusals every function and grant is as it was');

do $$
declare n int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
  raise notice 'ALL PASSED: a code to the new email only, the wait for staff, decisions, approval, unverified and unproven logins, refusals, the address on the record';
end $$;
rollback;
