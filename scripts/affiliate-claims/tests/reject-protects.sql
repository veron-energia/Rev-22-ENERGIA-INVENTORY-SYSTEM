-- An Owner's or Manager's Reject protects the suggested customer (379).
--
-- The owner's decision, 2 Oct 2026: "Yes, make Reject protect the customer
-- too". Once an Owner or a Manager rejects a claim, the customer it suggested
-- is protected the way an Owner's Unlink protects one (378).
--
--   P1 After an Owner rejects a claim, staff cannot link a new login to the
--      customer it suggested, though everything else would allow it (the
--      phones match, it is the suggested customer, no one shares the phone),
--      nor any login whichever customer its claim suggests or whatever
--      phone it entered, in the owner's words. Before the rejection staff
--      could. Any member of staff is refused; nothing is written. An Owner
--      and a Manager may still link one, and the resolve audit row says the
--      customer had been protected.
--   P2 The same after a Manager rejects one.
--   P3 A staff member's rejection protects no one: staff link a new login to
--      that customer, and the audit row says it was not protected.
--   P4 A rejected claim that suggested no one protects no one, not even the
--      customer whose phone it entered.
--   P5 Only the rejection's own audit row counts (written by
--      reject_affiliate_account_claim for an Owner or Manager): rows written
--      through write_audit, by staff or by an Owner, and rows written through
--      write_audit_ex for staff or an Admin (or for an Owner under another
--      action, or on another table), change nothing for the Resolve check,
--      the pending list or sign-up. Nobody signed in can write such a row into audit_logs
--      directly, or change or delete the one a rejection wrote.
--   P6 Deleting the rejected claim does not lift the protection: the person
--      signs in again, the new claim is flagged and staff are refused.
--   P7 Sign-up no longer links a login by itself to a protected customer
--      whose verified email, phone and name all match: it parks a pending
--      claim suggesting them (and the login whose claim was rejected is told
--      verification was unsuccessful). A customer never rejected, one a
--      member of staff rejected a claim for, and one with forged rows are
--      still linked by sign-up, as before.
--   P8 Pending Account Claims flag every claim whose suggested customer is
--      protected (suggested_customer_rejected), and no other. So do Rejected
--      Account Claims, beside who rejected each (rejected_by_staff).
--   P9 An Owner takes over a staff member's rejection: it becomes theirs
--      (rejected_by, rejected_at), the staff member's reason is kept and the
--      Owner's added below it, the same protecting audit row is written (with
--      the staff rejection in old_data), and from then on staff cannot link a
--      login to the customer, nor delete the rejection. Before that, staff
--      could link one; and no member of staff can take over a rejection. Once
--      it is the Owner's, an Owner or Manager is told "already rejected", as
--      for any Owner's or Manager's rejection.
--   P10 The same for a Manager; a reason that says the same as the staff
--      member's is not added twice; sign-up then parks a pending claim for
--      that customer instead of linking a login whose email, phone and name
--      match.
--   P11 Reject locks the suggested customer's row (as Unlink and Resolve
--      do), when it rejects and when it takes over, and changes nothing in
--      it.
--   P12 Nobody signed in can change a customer's id (staff, Manager or
--      Owner, directly under RLS): "A customer's id cannot be changed." So a
--      protected customer whose rejected claim was deleted cannot shed the
--      protection by being given a new id, and sign-up still parks a claim
--      for them. Ordinary edits (name, phone, email) still work for staff, and
--      the service role (no signed-in user) is not affected.
--   G  Each patched function keeps its grants; the trigger function is no
--      endpoint.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Needs 377, 378 and 379 (install them after
-- "begin;" on a database that does not have them yet). Every name, phone and
-- email below is invented; the phones are +65 8379 02xx.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
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
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
-- Does something and keeps the outcome ('ok' or the error) for the next
-- statement to check: a statement does not see what it did itself.
create function pg_temp.run(key text, q text) returns void language sql as
$$ insert into tx values (key, coalesce(pg_temp.err(q), 'ok')) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.resolve(claim text, cust text, note text default 'Checked the phone with the person') returns text language sql as
$$ select pg_temp.err(format('select public.resolve_affiliate_account_claim(%L, %L, %L)', pg_temp.fx(claim), pg_temp.fx(cust), note)) $$;
create function pg_temp.reject(claim text, reason text default 'Not the customer') returns text language sql as
$$ select coalesce(pg_temp.err(format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx(claim), reason)), 'ok') $$;
-- Rejects and keeps the answer (or the error) under the key given.
create function pg_temp.reject_as(key text, claim text, reason text) returns void language plpgsql as
$$declare r jsonb; begin
  r := public.reject_affiliate_account_claim(pg_temp.fx(claim), reason);
  insert into tx values (key, r::text) on conflict (k) do update set v = excluded.v;
exception when others then
  insert into tx values (key, 'ERROR: ' || sqlerrm) on conflict (k) do update set v = excluded.v;
end$$;
create function pg_temp.rejected(claim text) returns jsonb language sql as
$$ select e from jsonb_array_elements(public.affiliate_rejected_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx(claim) $$;
create function pg_temp.rejection_rows(claim text) returns int language sql as
$$ select count(*)::int from audit_logs where table_name = 'affiliate_account_claims' and record_id = pg_temp.fx(claim)
      and action = 'affiliate_claim_rejected' $$;
-- The customer row's lock word and place: a lock taken by a (sub)transaction
-- changes xmax; an update would also move the row (ctid).
create function pg_temp.row_lock(cust text) returns text language sql as
$$ select xmax::text || '@' || ctid::text from public.customers where id = pg_temp.fx(cust) $$;
create function pg_temp.link_check(claim text, cust text) returns jsonb language sql as
$$ select public.affiliate_claim_link_check(pg_temp.fx(claim), pg_temp.fx(cust)) $$;
create function pg_temp.linked_to(login text) returns uuid language sql as
$$ select customer_id from public.affiliate_accounts where auth_user_id = pg_temp.fx(login) $$;
create function pg_temp.claim_status(claim text) returns text language sql as
$$ select status from public.affiliate_account_claims where id = pg_temp.fx(claim) $$;
create function pg_temp.pending(claim text) returns jsonb language sql as
$$ select e from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx(claim) $$;
create function pg_temp.resolve_audit(claim text) returns jsonb language sql as
$$ select new_data from audit_logs where table_name = 'affiliate_account_claims' and record_id = pg_temp.fx(claim)
      and action = 'affiliate_claim_resolved' $$;
-- The sign-up check the verify page runs, as the login; keeps the claim it
-- parks (if any) under the key given.
create function pg_temp.onboard(login text, first text, last text, phone text, claim_key text default null) returns text language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user(login);
  r := public.complete_affiliate_onboarding(first, last, phone, true);
  if claim_key is not null then
    insert into fx select claim_key, id from public.affiliate_account_claims
     where auth_user_id = pg_temp.fx(login) and status = 'pending'
    on conflict (k) do update set v = excluded.v;
  end if;
  return coalesce(r->>'status', '?');
exception when others then return 'ERROR: ' || sqlerrm;
end$$;
-- The words the Resolve window shows staff; the database says the same.
insert into tx values ('rejected_msg', 'An Owner or Manager rejected a claim for this customer. Only an Owner or Manager can link a login to them.');
insert into tx values ('delete_msg', 'Only an Owner or Manager can remove a rejection they made.');
insert into tx values ('already_json', '{"ok": false, "already": true, "message": "This claim has already been rejected."}');
insert into tx values ('id_msg', 'A customer''s id cannot be changed.');

select pg_temp.check(position('379:' in (select prosrc from pg_proc where oid = to_regprocedure('public.affiliate_claim_link_check(uuid,uuid)'))) > 0
    and position('379:' in (select prosrc from pg_proc where oid = to_regprocedure('public.complete_affiliate_onboarding(text,text,text,boolean)'))) > 0
    and position('379:' in (select prosrc from pg_proc where oid = to_regprocedure('public.reject_affiliate_account_claim(uuid,text)'))) > 0
    and position('379:' in (select prosrc from pg_proc where oid = to_regprocedure('public.affiliate_rejected_claims()'))) > 0
    and exists (select 1 from pg_trigger where tgrelid = 'public.customers'::regclass and tgname = 'trg_customers_id_fixed'),
  'P0 379 is installed');
select pg_temp.check(not exists (select 1 from public.customers where public.normalize_customer_phone(phone) like '+65837902__'),
  'P0 no customer uses the test phones +65 8379 02xx (the checks below assume so)');

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); k text; u uuid;
begin
  insert into tx values ('sfx', sfx);
  foreach k in array array['o','m','s','s2','a'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 's379-' || k || '-' || sfx || '@tests.invalid', now());
  end loop;
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('o'),  'S379 Owner',        's379-o-'  || sfx || '@tests.invalid', 'owner'),
    (pg_temp.fx('m'),  'S379 Manager',      's379-m-'  || sfx || '@tests.invalid', 'manager'),
    (pg_temp.fx('s'),  'S379 Staff',        's379-s-'  || sfx || '@tests.invalid', 'staff'),
    (pg_temp.fx('s2'), 'S379 Second Staff', 's379-s2-' || sfx || '@tests.invalid', 'staff'),
    (pg_temp.fx('a'),  'S379 Admin',        's379-a-'  || sfx || '@tests.invalid', 'admin');
  -- Affiliate portal logins (no profiles row).
  foreach k in array array['lO1','lO2','lO3','lO4','lM1','lM2','lS1','lS2','lN1','lN2','lF','lD1',
                           'lP1','lP2','lPM1','lPM2','lA','lSA1','lSA','lFA',
                           'lT1','lT2','lU1','lU2','lR1','lR2','lL1','lL2','lFr'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 's379-' || lower(k) || '-' || sfx || '@tests.invalid', now());
  end loop;
end $$;
select pg_temp.as_user('o');

-- Customers, each with a phone of their own. cP, cPM, cA, cSA and cFA carry
-- the email of the login that will sign up as them.
do $$
declare c uuid; sfx text := pg_temp.tx('sfx');
begin
  insert into customers(full_name, phone) values ('Oda Rejtest', '+6583790201') returning id into c; insert into fx values ('cO', c);
  insert into customers(full_name, phone) values ('Mia Rejtest', '+6583790202') returning id into c; insert into fx values ('cM', c);
  insert into customers(full_name, phone) values ('Sia Rejtest', '+6583790203') returning id into c; insert into fx values ('cS', c);
  insert into customers(full_name, phone) values ('Nod Rejtest', '+6583790204') returning id into c; insert into fx values ('cN', c);
  insert into customers(full_name, phone) values ('Fay Rejtest', '+6583790205') returning id into c; insert into fx values ('cF', c);
  insert into customers(full_name, phone) values ('Dee Rejtest', '+6583790206') returning id into c; insert into fx values ('cD', c);
  insert into customers(full_name, phone, email) values ('Pia Rejtest', '+6583790207', 's379-lp2-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cP', c);
  insert into customers(full_name, phone, email) values ('Pim Rejtest', '+6583790211', 's379-lpm2-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cPM', c);
  insert into customers(full_name, phone, email) values ('Ava Rejtest', '+6583790208', 's379-la-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cA', c);
  insert into customers(full_name, phone, email) values ('Sal Rejtest', '+6583790209', 's379-lsa-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cSA', c);
  insert into customers(full_name, phone, email) values ('Fal Rejtest', '+6583790210', 's379-lfa-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cFA', c);
  -- P9-P12.
  insert into customers(full_name, phone) values ('Tia Rejtest', '+6583790212') returning id into c; insert into fx values ('cT', c);
  insert into customers(full_name, phone, email) values ('Uma Rejtest', '+6583790213', 's379-lu2-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cU', c);
  insert into customers(full_name, phone) values ('Lee Rejtest', '+6583790214') returning id into c; insert into fx values ('cL', c);
  insert into customers(full_name, phone) values ('Lou Rejtest', '+6583790215') returning id into c; insert into fx values ('cL2', c);
  insert into customers(full_name, phone, email) values ('Rex Rejtest', '+6583790216', 's379-lr2-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cR', c);
  insert into customers(full_name, phone) values ('Kim Rejtest', '+6583790217') returning id into c; insert into fx values ('cK', c);
end $$;

-- The claims that will be rejected, as sign-up parks them: the first from
-- each customer's phone and suggesting them (kN1 suggests no one, though its
-- phone is cN's).
do $$
declare r record; c uuid;
begin
  for r in select * from (values
      ('kO1', 'lO1', '+6583790201', 'Oda Rejtest', 'cO'),
      ('kM1', 'lM1', '+6583790202', 'Mia Rejtest', 'cM'),
      ('kS1', 'lS1', '+6583790203', 'Sia Rejtest', 'cS'),
      ('kN1', 'lN1', '+6583790204', 'Nob Rejtest', null),
      ('kD1', 'lD1', '+6583790206', 'Dee Rejtest', 'cD'),
      ('kP1', 'lP1', '+6583790207', 'Pia Rejtest', 'cP'),
      ('kPM1','lPM1','+6583790211', 'Pim Rejtest', 'cPM'),
      ('kSA1','lSA1','+6583790209', 'Sal Rejtest', 'cSA'),
      ('kT1', 'lT1', '+6583790212', 'Tia Rejtest', 'cT'),
      ('kU1', 'lU1', '+6583790213', 'Uma Rejtest', 'cU'),
      ('kL1', 'lL1', '+6583790214', 'Lee Rejtest', 'cL'),
      ('kR1', 'lR1', '+6583790216', 'Rex Rejtest', 'cR'),
      ('kFr', 'lFr', '+6583790205', 'Fay Rejtest', 'cF'),
      -- Two more for cO: one suggesting no one, and one whose phone differs.
      ('kO3', 'lO3', '+6583790201', 'Odette Rejtest', null),
      ('kO4', 'lO4', '+6583790299', 'Oda Rejtest', null)) t(k, login, phone, name, cand)
  loop
    insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
      values (pg_temp.fx(r.login), r.phone, (select email from auth.users where id = pg_temp.fx(r.login)), pg_temp.fx(r.cand), r.name)
      returning id into c;
    insert into fx values (r.k, c);
  end loop;
end $$;

-- ═════ P1 An Owner's rejection ═════
-- A new login signs up as Oda: her email is not on the record, so sign-up
-- parks a claim suggesting her.
insert into tx values ('onb_O', pg_temp.onboard('lO2', 'Oda', 'Rejtest', '+65 8379 0201', 'kO2'));
select pg_temp.check(pg_temp.tx('onb_O') = 'pending_verification'
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('kO2')) = pg_temp.fx('cO'),
  'P1 (setup) a new login signs up as Oda: a pending claim suggesting her');
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' is null and not (r->>'customer_previously_rejected')::boolean and r->>'customer_rejected_at' is null
                        from pg_temp.link_check('kO2', 'cO') r)
    and not (pg_temp.pending('kO2')->>'suggested_customer_rejected')::boolean,
  'P1 (setup) before any rejection, staff may link it, and the list does not flag it');
select pg_temp.as_user('o');
insert into tx values ('rej_O', pg_temp.reject('kO1'));
select pg_temp.check(pg_temp.tx('rej_O') = 'ok' and pg_temp.claim_status('kO1') = 'rejected',
  'P1 (setup) an Owner rejects the first claim suggesting Oda');
select pg_temp.check(exists (select 1 from audit_logs where table_name = 'affiliate_account_claims' and record_id = pg_temp.fx('kO1')
                                and action = 'affiliate_claim_rejected' and changed_by = pg_temp.fx('o') and actor_role = 'owner'
                                and module = 'affiliate' and new_data->>'candidate_customer_id' = pg_temp.fx('cO')::text
                                and new_data->>'auth_user_id' = pg_temp.fx('lO1')::text and reason = 'Not the customer'),
  'P1 (as relied on) Reject writes the row that counts: for an Owner, module ''affiliate'', with the customer the claim suggested');
select pg_temp.as_user('s');
select pg_temp.check((select (r->>'phones_match')::boolean and (r->>'suggested_customer')::boolean
                             and (r->>'customers_sharing_phone')::int = 1 and not (r->>'phone_changed_since_claim')::boolean
                             and not (r->>'previously_unlinked')::boolean and not (r->>'customer_previously_unlinked')::boolean
                             and not (r->>'own_claim')::boolean and not (r->>'earlier_claim_other_customer')::boolean
                             and (r->>'customer_previously_rejected')::boolean
                             and (r->>'customer_rejected_at')::timestamptz =
                                 (select created_at from audit_logs where record_id = pg_temp.fx('kO1') and action = 'affiliate_claim_rejected')
                             and r->>'problem' = pg_temp.tx('rejected_msg')
                        from pg_temp.link_check('kO2', 'cO') r),
  'P1 now staff cannot link the new login to Oda, though the phones match, she is the suggested customer and no one shares the phone, in the owner''s words; the check says when she was protected');
select pg_temp.check(pg_temp.resolve('kO2', 'cO') = pg_temp.tx('rejected_msg')
    and pg_temp.claim_status('kO2') = 'pending' and pg_temp.linked_to('lO2') is null
    and not exists (select 1 from customer_affiliates where customer_id = pg_temp.fx('cO'))
    and pg_temp.resolve_audit('kO2') is null,
  'P1 and Save is refused: nothing is linked, no affiliate record is made, no audit row');
select pg_temp.check((pg_temp.pending('kO2')->>'suggested_customer_rejected')::boolean
    and not (pg_temp.pending('kO2')->>'suggested_customer_unlinked')::boolean,
  'P1 the pending list flags the new login''s claim (as rejected, not as unlinked)');
select pg_temp.check(pg_temp.link_check('kO3', 'cO')->>'problem' = pg_temp.tx('rejected_msg')
    and pg_temp.resolve('kO3', 'cO') = pg_temp.tx('rejected_msg') and pg_temp.linked_to('lO3') is null,
  'P1 nor any other login: a claim from her phone that suggests no one');
select pg_temp.check((select not (r->>'phones_match')::boolean and r->>'problem' = pg_temp.tx('rejected_msg') from pg_temp.link_check('kO4', 'cO') r),
  'P1 and a claim with another phone is refused for the rejection first (before the phone rule)');
select pg_temp.as_user('s2');
select pg_temp.check(pg_temp.resolve('kO2', 'cO') = pg_temp.tx('rejected_msg') and pg_temp.linked_to('lO2') is null,
  'P1 by any member of staff');
select pg_temp.as_user('o');
select pg_temp.check((select r->>'problem' is null and (r->>'customer_previously_rejected')::boolean from pg_temp.link_check('kO2', 'cO') r)
    and pg_temp.link_check('kO4', 'cO')->>'problem' is null,
  'P1 for an Owner the check allows it, and says the customer was protected');
select pg_temp.as_user('m');
insert into tx values ('mgr_O', coalesce(pg_temp.resolve('kO2', 'cO', 'Manager checked in person'), 'ok'));
select pg_temp.check(pg_temp.tx('mgr_O') = 'ok' and pg_temp.linked_to('lO2') = pg_temp.fx('cO') and pg_temp.claim_status('kO2') = 'resolved',
  'P1 a Manager links the new login to Oda (an Owner rejected the claim)');
select pg_temp.check((pg_temp.resolve_audit('kO2')->>'customer_previously_rejected')::boolean
    and (pg_temp.resolve_audit('kO2')->>'phones_match')::boolean,
  'P1 and the resolve audit row says an Owner or Manager had rejected a claim for her');

-- ═════ P2 A Manager's rejection ═════
insert into tx values ('onb_M', pg_temp.onboard('lM2', 'Mia', 'Rejtest', '+65 8379 0202', 'kM2'));
select pg_temp.check(pg_temp.tx('onb_M') = 'pending_verification'
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('kM2')) = pg_temp.fx('cM'),
  'P2 (setup) a new login signs up as Mia: a pending claim suggesting her');
select pg_temp.as_user('m');
insert into tx values ('rej_M', pg_temp.reject('kM1'));
select pg_temp.check(pg_temp.tx('rej_M') = 'ok'
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('kM1') and action = 'affiliate_claim_rejected' and actor_role = 'manager'),
  'P2 (setup) a Manager rejects the first claim suggesting Mia');
select pg_temp.as_user('s');
select pg_temp.check((select (r->>'phones_match')::boolean and (r->>'customer_previously_rejected')::boolean and r->>'problem' = pg_temp.tx('rejected_msg')
                        from pg_temp.link_check('kM2', 'cM') r)
    and pg_temp.resolve('kM2', 'cM') = pg_temp.tx('rejected_msg') and pg_temp.linked_to('lM2') is null,
  'P2 staff cannot link the new login to Mia');
select pg_temp.check((pg_temp.pending('kM2')->>'suggested_customer_rejected')::boolean,
  'P2 and the pending list flags her claim');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.link_check('kM2', 'cM')->>'problem' is null, 'P2 for a Manager the check allows it');
select pg_temp.as_user('o');
insert into tx values ('own_M', coalesce(pg_temp.resolve('kM2', 'cM', 'Owner checked in person'), 'ok'));
select pg_temp.check(pg_temp.tx('own_M') = 'ok' and pg_temp.linked_to('lM2') = pg_temp.fx('cM')
    and (pg_temp.resolve_audit('kM2')->>'customer_previously_rejected')::boolean,
  'P2 an Owner links it, and the audit row says so');

-- ═════ P3 A staff member's rejection ═════
insert into tx values ('onb_S', pg_temp.onboard('lS2', 'Sia', 'Rejtest', '+65 8379 0203', 'kS2'));
select pg_temp.check(pg_temp.tx('onb_S') = 'pending_verification' and pg_temp.fx('kS2') is not null,
  'P3 (setup) a new login signs up as Sia: a pending claim');
select pg_temp.as_user('s2');
insert into tx values ('rej_S', pg_temp.reject('kS1'));
select pg_temp.check(pg_temp.tx('rej_S') = 'ok'
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('kS1') and action = 'affiliate_claim_rejected'
                   and actor_role = 'staff' and module = 'affiliate' and new_data->>'candidate_customer_id' = pg_temp.fx('cS')::text),
  'P3 (setup) a member of staff rejects the first claim suggesting Sia');
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' is null and not (r->>'customer_previously_rejected')::boolean from pg_temp.link_check('kS2', 'cS') r)
    and not (pg_temp.pending('kS2')->>'suggested_customer_rejected')::boolean,
  'P3 that protects no one: staff may link a new login to Sia, and the list does not flag it');
select pg_temp.check(pg_temp.resolve('kS2', 'cS') is null and pg_temp.linked_to('lS2') = pg_temp.fx('cS')
    and not (pg_temp.resolve_audit('kS2')->>'customer_previously_rejected')::boolean,
  'P3 staff link it, and the audit row says she was not protected');

-- ═════ P4 A rejected claim that suggested no one ═════
select pg_temp.as_user('o');
insert into tx values ('rej_N', pg_temp.reject('kN1'));
select pg_temp.check(pg_temp.tx('rej_N') = 'ok'
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('kN1') and action = 'affiliate_claim_rejected'
                   and actor_role = 'owner' and new_data ? 'candidate_customer_id' and new_data->>'candidate_customer_id' is null),
  'P4 (setup) an Owner rejects a claim from Nod''s phone that suggested no one');
insert into tx values ('onb_N', pg_temp.onboard('lN2', 'Nod', 'Rejtest', '+65 8379 0204', 'kN2'));
select pg_temp.check(pg_temp.tx('onb_N') = 'pending_verification' and pg_temp.fx('kN2') is not null,
  'P4 (setup) a new login signs up as Nod: a pending claim');
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' is null and not (r->>'customer_previously_rejected')::boolean from pg_temp.link_check('kN2', 'cN') r)
    and not (pg_temp.pending('kN2')->>'suggested_customer_rejected')::boolean
    and pg_temp.resolve('kN2', 'cN') is null and pg_temp.linked_to('lN2') = pg_temp.fx('cN'),
  'P4 it protects no one, not the customer whose phone it entered: staff link the new login to Nod');

-- ═════ P5 Only the rejection's own audit row counts ═════
-- Rows shaped like an Owner's rejection of a claim suggesting cF and cFA:
-- through write_audit by staff and by an Owner (signed-in users could call it
-- until 406; it leaves module empty), and through write_audit_ex for staff and for an
-- Admin, for an Owner under another action, and for an Owner with the right
-- action on another table (no signed-in user can call write_audit_ex; this
-- runs as the database owner).
do $$
declare cust text; who text;
begin
  foreach cust in array array['cF','cFA'] loop
    foreach who in array array['s','o'] loop
      perform pg_temp.as_user(who);
      perform public.write_audit('affiliate_account_claims', gen_random_uuid(), 'affiliate_claim_rejected', null,
        jsonb_build_object('auth_user_id', gen_random_uuid(), 'candidate_customer_id', pg_temp.fx(cust)));
    end loop;
    foreach who in array array['s','a'] loop
      perform pg_temp.as_user(who);
      perform public.write_audit_ex('affiliate_account_claims', gen_random_uuid(), 'affiliate_claim_rejected', null,
        jsonb_build_object('auth_user_id', gen_random_uuid(), 'candidate_customer_id', pg_temp.fx(cust)), 'affiliate', 'not a rejection', null);
    end loop;
    perform pg_temp.as_user('o');
    perform public.write_audit_ex('affiliate_account_claims', gen_random_uuid(), 'affiliate_claim_resolved', null,
      jsonb_build_object('auth_user_id', gen_random_uuid(), 'candidate_customer_id', pg_temp.fx(cust)), 'affiliate', 'not a rejection', null);
    -- The rejection's action, for an Owner, with module 'affiliate', but on
    -- another table: only a row on affiliate_account_claims counts.
    perform public.write_audit_ex('affiliate_accounts', gen_random_uuid(), 'affiliate_claim_rejected', null,
      jsonb_build_object('auth_user_id', gen_random_uuid(), 'candidate_customer_id', pg_temp.fx(cust)), 'affiliate', 'not a rejection', null);
  end loop;
end $$;
select pg_temp.check((select count(*) filter (where actor_role = 'staff' and module is null) = 2
                         and count(*) filter (where actor_role = 'owner' and module is null) = 2
                         and count(*) filter (where actor_role = 'staff' and module = 'affiliate') = 2
                         and count(*) filter (where actor_role = 'admin' and module = 'affiliate') = 2
                         and count(*) filter (where actor_role = 'owner' and module = 'affiliate' and action = 'affiliate_claim_resolved') = 2
                         and count(*) = 10
                        from audit_logs where table_name = 'affiliate_account_claims'
                         and new_data->>'candidate_customer_id' in (pg_temp.fx('cF')::text, pg_temp.fx('cFA')::text))
    and (select count(*) = 2 from audit_logs where table_name = 'affiliate_accounts' and action = 'affiliate_claim_rejected'
            and actor_role = 'owner' and module = 'affiliate'
            and new_data->>'candidate_customer_id' in (pg_temp.fx('cF')::text, pg_temp.fx('cFA')::text)),
  'P5 (setup) twelve rows shaped like a rejection: staff and an Owner through write_audit, staff and an Admin through write_audit_ex, an Owner''s under another action, and an Owner''s rejection row on another table');
-- 406 took write_audit from signed-in users (X-7); the rows above stand for
-- ones written before that, and for any a server function writes.
select pg_temp.check(not has_function_privilege('authenticated', 'public.write_audit(text,uuid,text,jsonb,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.write_audit(text,uuid,text,jsonb,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'execute'),
  'P5 (as relied on) no signed-in user may call write_audit (since 406) or write_audit_ex');
-- Nor can anyone signed in write such a row into audit_logs directly, or
-- change or delete the row the Owner's rejection of kO1 wrote (RLS: read only).
do $$
declare u uuid; n int; got text := '';
  cf uuid := pg_temp.fx('cF'); ko1 uuid := pg_temp.fx('kO1');
  users uuid[] := array[pg_temp.fx('s'), pg_temp.fx('o')];
begin
  foreach u in array users loop
    perform set_config('request.jwt.claim.sub', u::text, true);
    execute 'set local role authenticated';
    begin
      insert into public.audit_logs(table_name, record_id, action, new_data, actor_role, module)
        values ('affiliate_account_claims', gen_random_uuid(), 'affiliate_claim_rejected',
                jsonb_build_object('candidate_customer_id', cf), 'owner', 'affiliate');
      got := got || 'inserted ';
    exception when others then null; end;
    begin
      update public.audit_logs set new_data = jsonb_build_object('candidate_customer_id', null)
       where record_id = ko1 and action = 'affiliate_claim_rejected';
      get diagnostics n = row_count; if n > 0 then got := got || 'updated '; end if;
    exception when others then null; end;
    begin
      delete from public.audit_logs where record_id = ko1 and action = 'affiliate_claim_rejected';
      get diagnostics n = row_count; if n > 0 then got := got || 'deleted '; end if;
    exception when others then null; end;
    execute 'reset role';
  end loop;
  insert into tx values ('rls', got);
end $$;
select pg_temp.check(pg_temp.tx('rls') = ''
    and (select count(*) from audit_logs where record_id = pg_temp.fx('kO1') and action = 'affiliate_claim_rejected'
            and new_data->>'candidate_customer_id' = pg_temp.fx('cO')::text) = 1
    and not exists (select 1 from audit_logs where table_name = 'affiliate_account_claims' and action = 'affiliate_claim_rejected'
                       and actor_role = 'owner' and module = 'affiliate'
                       and new_data->>'candidate_customer_id' = pg_temp.fx('cF')::text),
  'P5 (as relied on) staff and an Owner, signed in, cannot write such a row into audit_logs directly, nor change or delete the one the Owner''s rejection wrote' || coalesce(': ' || nullif(pg_temp.tx('rls'), ''), ''));
insert into tx values ('onb_F', pg_temp.onboard('lF', 'Fay', 'Rejtest', '+65 8379 0205', 'kF'));
select pg_temp.check(pg_temp.tx('onb_F') = 'pending_verification' and pg_temp.fx('kF') is not null,
  'P5 (setup) a login signs up as Fay: a pending claim');
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' is null and not (r->>'customer_previously_rejected')::boolean from pg_temp.link_check('kF', 'cF') r),
  'P5 the Resolve check ignores them: staff may link the login to Fay');
select pg_temp.check(not (pg_temp.pending('kF')->>'suggested_customer_rejected')::boolean,
  'P5 nor does the pending list flag the claim');
-- A member of staff rejects another claim suggesting Fay: the Rejected list
-- does not count the forged rows either.
insert into tx values ('rej_Fr', pg_temp.reject('kFr', 'Not Fay'));
select pg_temp.check(pg_temp.tx('rej_Fr') = 'ok' and not (pg_temp.rejected('kFr')->>'suggested_customer_rejected')::boolean,
  'P5 nor does the Rejected list say Fay is protected');
select pg_temp.check(pg_temp.resolve('kF', 'cF') is null and pg_temp.linked_to('lF') = pg_temp.fx('cF'),
  'P5 staff link it');
insert into tx values ('onb_FA', pg_temp.onboard('lFA', 'Fal', 'Rejtest', '+65 8379 0210'));
select pg_temp.check(pg_temp.tx('onb_FA') = 'active' and pg_temp.linked_to('lFA') = pg_temp.fx('cFA'),
  'P5 nor does sign-up: it still links a login whose email, phone and name match Fal by itself');

-- ═════ P6 Deleting the rejected claim does not lift it ═════
select pg_temp.as_user('o');
insert into tx values ('rej_D', pg_temp.reject('kD1'));
select pg_temp.check(pg_temp.tx('rej_D') = 'ok', 'P6 (setup) an Owner rejects the claim suggesting Dee');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err(format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kD1'))) = pg_temp.tx('delete_msg')
    and pg_temp.claim_status('kD1') = 'rejected',
  'P6 (as 378) staff cannot delete an Owner''s rejection');
select pg_temp.as_user('m');
select pg_temp.run('del_D', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kD1')));
select pg_temp.check(pg_temp.tx('del_D') = 'ok' and pg_temp.claim_status('kD1') is null
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('kD1') and action = 'affiliate_claim_rejected' and actor_role = 'owner'),
  'P6 (setup) a Manager deletes the rejected claim; the rejection''s audit row stays');
insert into tx values ('onb_D', pg_temp.onboard('lD1', 'Dee', 'Rejtest', '+65 8379 0206', 'kD2'));
select pg_temp.check(pg_temp.tx('onb_D') = 'pending_verification'
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('kD2')) = pg_temp.fx('cD'),
  'P6 (setup) the person signs in again: a new pending claim suggesting Dee');
select pg_temp.as_user('s');
select pg_temp.check((pg_temp.pending('kD2')->>'suggested_customer_rejected')::boolean
    and (select (r->>'customer_previously_rejected')::boolean and r->>'problem' = pg_temp.tx('rejected_msg') from pg_temp.link_check('kD2', 'cD') r)
    and pg_temp.resolve('kD2', 'cD') = pg_temp.tx('rejected_msg') and pg_temp.linked_to('lD1') is null,
  'P6 the claim is flagged and staff are still refused');
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.link_check('kD2', 'cD')->>'problem' is null, 'P6 an Owner may still link it');

-- ═════ P7 Sign-up ═════
select pg_temp.as_user('o');
insert into tx values ('rej_P', pg_temp.reject('kP1'));
select pg_temp.check(pg_temp.tx('rej_P') = 'ok', 'P7 (setup) an Owner rejects a claim suggesting Pia');
-- A new login whose email is on Pia's record, with her phone and name.
insert into tx values ('onb_P2', pg_temp.onboard('lP2', 'Pia', 'Rejtest', '+65 8379 0207', 'kP2'));
select pg_temp.check(pg_temp.tx('onb_P2') = 'pending_verification'
    and pg_temp.linked_to('lP2') is null
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('kP2')) = pg_temp.fx('cP')
    and not exists (select 1 from customer_affiliates where customer_id = pg_temp.fx('cP')),
  'P7 sign-up does not link a login whose verified email, phone and name all match Pia: it parks a pending claim suggesting her');
select pg_temp.as_user('s');
select pg_temp.check((pg_temp.pending('kP2')->>'suggested_customer_rejected')::boolean
    and pg_temp.resolve('kP2', 'cP', 'Email, phone and name match') = pg_temp.tx('rejected_msg') and pg_temp.linked_to('lP2') is null,
  'P7 it is flagged, and staff cannot resolve it');
-- Staff put the rejected login's email on Pia's record; it signs in again.
update customers set email = 's379-lp1-' || pg_temp.tx('sfx') || '@tests.invalid' where id = pg_temp.fx('cP');
insert into tx values ('onb_P1', pg_temp.onboard('lP1', 'Pia', 'Rejtest', '+65 8379 0207'));
select pg_temp.check(pg_temp.tx('onb_P1') = 'rejected' and pg_temp.linked_to('lP1') is null
    and not exists (select 1 from affiliate_account_claims where auth_user_id = pg_temp.fx('lP1') and status = 'pending'),
  'P7 the login whose claim was rejected, its email now on the record, is told verification was unsuccessful; nothing is linked or parked');
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.resolve('kP2', 'cP', 'Pia confirmed in the shop') is null and pg_temp.linked_to('lP2') = pg_temp.fx('cP'),
  'P7 an Owner links it');
select pg_temp.as_user('m');
insert into tx values ('rej_PM', pg_temp.reject('kPM1'));
insert into tx values ('onb_PM2', pg_temp.onboard('lPM2', 'Pim', 'Rejtest', '+65 8379 0211', 'kPM2'));
select pg_temp.check(pg_temp.tx('rej_PM') = 'ok' and pg_temp.tx('onb_PM2') = 'pending_verification' and pg_temp.linked_to('lPM2') is null
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('kPM2')) = pg_temp.fx('cPM'),
  'P7 the same after a Manager rejected a claim suggesting Pim: sign-up parks a pending claim, though email, phone and name match');
insert into tx values ('onb_A', pg_temp.onboard('lA', 'Ava', 'Rejtest', '+65 8379 0208'));
select pg_temp.check(pg_temp.tx('onb_A') = 'active' and pg_temp.linked_to('lA') = pg_temp.fx('cA'),
  'P7 a customer no one rejected a claim for: sign-up still links a login whose email, phone and name match, as before');
select pg_temp.as_user('s');
insert into tx values ('rej_SA', pg_temp.reject('kSA1'));
select pg_temp.check(pg_temp.tx('rej_SA') = 'ok', 'P7 (setup) a member of staff rejects a claim suggesting Sal');
insert into tx values ('onb_SA', pg_temp.onboard('lSA', 'Sal', 'Rejtest', '+65 8379 0209'));
select pg_temp.check(pg_temp.tx('onb_SA') = 'active' and pg_temp.linked_to('lSA') = pg_temp.fx('cSA'),
  'P7 a staff member''s rejection does not stop sign-up linking a login whose email, phone and name match Sal');

-- ═════ P8 The pending list ═════
-- kO3 and kO4 (still pending) suggest no one.
select pg_temp.as_user('s');
select pg_temp.check((select bool_and(case when (e->>'claim_id')::uuid = pg_temp.fx('kD2') then (e->>'suggested_customer_rejected')::boolean
                                           else not (e->>'suggested_customer_rejected')::boolean end) and count(*) = 3
                        from jsonb_array_elements(public.affiliate_pending_claims()) e
                       where (e->>'claim_id')::uuid in (pg_temp.fx('kD2'), pg_temp.fx('kO3'), pg_temp.fx('kO4'))),
  'P8 the pending list flags the claim suggesting a protected customer, and not the claims that suggest no one');
select pg_temp.check((select bool_and(e ? 'suggested_customer_rejected') and bool_and(e ? 'suggested_customer_unlinked')
                        from jsonb_array_elements(public.affiliate_pending_claims()) e),
  'P8 every pending row says it, beside 378''s flags');
select pg_temp.as_user('m');
select pg_temp.check((pg_temp.pending('kD2')->>'suggested_customer_rejected')::boolean, 'P8 Owners and Managers see the flag too');
-- The Rejected list says the same, beside who rejected each claim.
select pg_temp.as_user('s');
select pg_temp.check((select count(*) > 0 and bool_and(e ? 'suggested_customer_rejected') and bool_and(e ? 'rejected_by_staff')
                        from jsonb_array_elements(public.affiliate_rejected_claims()) e),
  'P8 every rejected row says whether its likely customer is protected, beside 378''s rejected_by_staff');
select pg_temp.check((pg_temp.rejected('kO1')->>'suggested_customer_rejected')::boolean
    and not (pg_temp.rejected('kO1')->>'rejected_by_staff')::boolean
    and (pg_temp.rejected('kM1')->>'suggested_customer_rejected')::boolean
    and not (pg_temp.rejected('kS1')->>'suggested_customer_rejected')::boolean
    and (pg_temp.rejected('kS1')->>'rejected_by_staff')::boolean
    and not (pg_temp.rejected('kSA1')->>'suggested_customer_rejected')::boolean
    and not (pg_temp.rejected('kN1')->>'suggested_customer_rejected')::boolean,
  'P8 the Rejected list: an Owner''s or Manager''s rejection protects its likely customer, a staff member''s does not, and one that suggested no one protects no one');
select pg_temp.as_user('o');
select pg_temp.check((pg_temp.rejected('kO1')->>'suggested_customer_rejected')::boolean
    and not (pg_temp.rejected('kS1')->>'suggested_customer_rejected')::boolean,
  'P8 Owners and Managers see the same');

-- ═════ P9 An Owner takes over a staff member's rejection ═════
select pg_temp.as_user('s');
insert into tx values ('rej_T', pg_temp.reject('kT1', 'Wrong number'));
-- As if it was made yesterday (now() is the same all through this run).
update affiliate_account_claims set rejected_at = now() - interval '1 day' where id = pg_temp.fx('kT1');
select pg_temp.check(pg_temp.tx('rej_T') = 'ok' and pg_temp.rejection_rows('kT1') = 1
    and (select rejected_by = pg_temp.fx('s') from affiliate_account_claims where id = pg_temp.fx('kT1')),
  'P9 (setup) a member of staff rejects the first claim suggesting Tia');
insert into tx values ('onb_T', pg_temp.onboard('lT2', 'Tia', 'Rejtest', '+65 8379 0212', 'kT2'));
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.tx('onb_T') = 'pending_verification'
    and pg_temp.link_check('kT2', 'cT')->>'problem' is null
    and (pg_temp.rejected('kT1')->>'rejected_by_staff')::boolean
    and not (pg_temp.rejected('kT1')->>'suggested_customer_rejected')::boolean,
  'P9 (setup) a new login signs up as Tia: staff could link it, and the Rejected list shows a staff rejection that protects no one');
-- No member of staff can take it over: another one, or the one who made it.
select pg_temp.as_user('s2');
select pg_temp.reject_as('stf_T2', 'kT1', 'Impostor');
select pg_temp.as_user('s');
select pg_temp.reject_as('stf_T1', 'kT1', 'Impostor');
select pg_temp.check(pg_temp.tx('stf_T2') = pg_temp.tx('already_json') and pg_temp.tx('stf_T1') = pg_temp.tx('already_json')
    and pg_temp.rejection_rows('kT1') = 1
    and (select rejected_by = pg_temp.fx('s') and rejection_reason = 'Wrong number' and rejected_at = now() - interval '1 day'
           from affiliate_account_claims where id = pg_temp.fx('kT1'))
    and pg_temp.link_check('kT2', 'cT')->>'problem' is null,
  'P9 a member of staff cannot take a rejection over: "already rejected", nothing written, Tia still not protected'
    || ': ' || coalesce(pg_temp.tx('stf_T2'), '') || ' / ' || coalesce(pg_temp.tx('stf_T1'), ''));
select pg_temp.as_user('o');
select pg_temp.reject_as('own_T', 'kT1', '  Impostor: Tia made no account ');
select pg_temp.check(pg_temp.tx('own_T') = '{"ok": true, "taken_over": true}',
  'P9 an Owner takes the staff member''s rejection over: ' || coalesce(pg_temp.tx('own_T'), ''));
select pg_temp.check((select status = 'rejected' and rejected_by = pg_temp.fx('o') and rejected_at = now()
                             and rejection_reason = E'Wrong number\nConfirmed by an Owner: Impostor: Tia made no account'
                        from affiliate_account_claims where id = pg_temp.fx('kT1')),
  'P9 the rejection is now the Owner''s (their name and time); the staff member''s reason is kept and the Owner''s added on a line of its own');
select pg_temp.check(pg_temp.rejection_rows('kT1') = 2
    and exists (select 1 from audit_logs where table_name = 'affiliate_account_claims' and record_id = pg_temp.fx('kT1')
                   and action = 'affiliate_claim_rejected' and changed_by = pg_temp.fx('o') and actor_role = 'owner' and module = 'affiliate'
                   and new_data = jsonb_build_object('auth_user_id', pg_temp.fx('lT1'), 'candidate_customer_id', pg_temp.fx('cT'))
                   and old_data->>'rejected_by' = pg_temp.fx('s')::text and (old_data->>'rejected_by_staff')::boolean
                   and old_data->>'rejection_reason' = 'Wrong number'
                   and (old_data->>'rejected_at')::timestamptz = now() - interval '1 day'
                   and reason = '  Impostor: Tia made no account '),
  'P9 and the same protecting audit row is written, for the Owner, with the staff rejection in old_data');
select pg_temp.as_user('s');
select pg_temp.check((select (r->>'customer_previously_rejected')::boolean and r->>'problem' = pg_temp.tx('rejected_msg') from pg_temp.link_check('kT2', 'cT') r)
    and pg_temp.resolve('kT2', 'cT') = pg_temp.tx('rejected_msg') and pg_temp.linked_to('lT2') is null
    and (pg_temp.pending('kT2')->>'suggested_customer_rejected')::boolean,
  'P9 now staff cannot link the new login to Tia, and the pending list flags it');
select pg_temp.check(not (pg_temp.rejected('kT1')->>'rejected_by_staff')::boolean
    and (pg_temp.rejected('kT1')->>'suggested_customer_rejected')::boolean,
  'P9 the Rejected list shows an Owner''s or Manager''s rejection that protects Tia');
select pg_temp.check(pg_temp.err(format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kT1'))) = pg_temp.tx('delete_msg')
    and pg_temp.claim_status('kT1') = 'rejected',
  'P9 and staff can no longer delete it');
-- Once an Owner's or Manager's, a rejection answers "already rejected" to an
-- Owner or Manager too, and nothing is written or changed.
select pg_temp.as_user('o');
select pg_temp.reject_as('own_T2', 'kT1', 'Again');
select pg_temp.reject_as('own_M1', 'kM1', 'Again');
select pg_temp.as_user('m');
select pg_temp.reject_as('mgr_T', 'kT1', 'Again');
select pg_temp.reject_as('mgr_O1', 'kO1', 'Again');
select pg_temp.check(pg_temp.tx('own_T2') = pg_temp.tx('already_json') and pg_temp.tx('mgr_T') = pg_temp.tx('already_json')
    and pg_temp.tx('mgr_O1') = pg_temp.tx('already_json') and pg_temp.tx('own_M1') = pg_temp.tx('already_json')
    and pg_temp.rejection_rows('kT1') = 2 and pg_temp.rejection_rows('kO1') = 1 and pg_temp.rejection_rows('kM1') = 1
    and (select rejected_by = pg_temp.fx('o') and rejection_reason = E'Wrong number\nConfirmed by an Owner: Impostor: Tia made no account'
           from affiliate_account_claims where id = pg_temp.fx('kT1'))
    and (select rejected_by = pg_temp.fx('m') from affiliate_account_claims where id = pg_temp.fx('kM1'))
    and (select rejected_by = pg_temp.fx('o') from affiliate_account_claims where id = pg_temp.fx('kO1')),
  'P9 an Owner''s or Manager''s rejection still answers "already rejected" to an Owner or Manager; nothing written or changed');

-- ═════ P10 A Manager takes over a staff member's rejection ═════
select pg_temp.as_user('s');
insert into tx values ('rej_U', pg_temp.reject('kU1', 'Not her'));
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.tx('rej_U') = 'ok' and pg_temp.reject('kU1', '   ') = 'A reason is required'
    and pg_temp.rejection_rows('kU1') = 1
    and (select rejected_by = pg_temp.fx('s') from affiliate_account_claims where id = pg_temp.fx('kU1')),
  'P10 taking over needs a reason too, as every rejection does; without one nothing is written');
select pg_temp.reject_as('mgr_U', 'kU1', ' Not her ');
select pg_temp.check(pg_temp.tx('mgr_U') = '{"ok": true, "taken_over": true}'
    and (select rejected_by = pg_temp.fx('m') and rejection_reason = 'Not her' from affiliate_account_claims where id = pg_temp.fx('kU1'))
    and exists (select 1 from audit_logs where table_name = 'affiliate_account_claims' and record_id = pg_temp.fx('kU1')
                   and action = 'affiliate_claim_rejected' and actor_role = 'manager' and module = 'affiliate'
                   and new_data->>'candidate_customer_id' = pg_temp.fx('cU')::text and old_data->>'rejected_by' = pg_temp.fx('s')::text),
  'P10 a Manager takes over a staff member''s rejection; a reason that says the same is not added twice');
-- Uma's record carries the email of the login that now signs up with her
-- phone and name: before, sign-up linked such a login by itself (P7, Sal).
insert into tx values ('onb_U', pg_temp.onboard('lU2', 'Uma', 'Rejtest', '+65 8379 0213', 'kU2'));
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.tx('onb_U') = 'pending_verification' and pg_temp.linked_to('lU2') is null
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('kU2')) = pg_temp.fx('cU')
    and pg_temp.resolve('kU2', 'cU') = pg_temp.tx('rejected_msg') and pg_temp.linked_to('lU2') is null,
  'P10 sign-up parks a pending claim instead of linking a login whose email, phone and name match Uma, and staff cannot resolve it');

-- ═════ P11 Reject locks the suggested customer's row ═════
-- kL1 (pending, suggesting Lee), and a staff member's rejection of a claim
-- suggesting Lou made before 379 (so without any lock on Lou's row).
with i as (
  insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name,
                                       status, rejected_by, rejected_at, rejection_reason)
  values (pg_temp.fx('lL2'), '+6583790215', (select email from auth.users where id = pg_temp.fx('lL2')), pg_temp.fx('cL2'), 'Lou Rejtest',
          'rejected', pg_temp.fx('s'), now() - interval '2 days', 'Could not reach her')
  returning id)
insert into fx select 'kL2', id from i;
insert into tx values ('lock_L', pg_temp.row_lock('cL')), ('lock_L2', pg_temp.row_lock('cL2'));
select pg_temp.as_user('o');
select pg_temp.reject_as('own_L', 'kL1', 'Not Lee');
select pg_temp.reject_as('own_L2', 'kL2', 'Not Lou');
select pg_temp.check(pg_temp.tx('own_L') = '{"ok": true}' and pg_temp.tx('own_L2') = '{"ok": true, "taken_over": true}',
  'P11 (setup) an Owner rejects a claim suggesting Lee, and takes over a staff member''s rejection of one suggesting Lou');
select pg_temp.check(split_part(pg_temp.row_lock('cL'), '@', 1) <> split_part(pg_temp.tx('lock_L'), '@', 1)
    and split_part(pg_temp.row_lock('cL'), '@', 2) = split_part(pg_temp.tx('lock_L'), '@', 2),
  'P11 rejecting locked Lee''s row (as Unlink and Resolve lock it), and did not change it: '
    || pg_temp.tx('lock_L') || ' -> ' || pg_temp.row_lock('cL'));
select pg_temp.check(split_part(pg_temp.row_lock('cL2'), '@', 1) <> split_part(pg_temp.tx('lock_L2'), '@', 1)
    and split_part(pg_temp.row_lock('cL2'), '@', 2) = split_part(pg_temp.tx('lock_L2'), '@', 2),
  'P11 taking over locked Lou''s row too, and did not change it: '
    || pg_temp.tx('lock_L2') || ' -> ' || pg_temp.row_lock('cL2'));

-- ═════ P12 Nobody signed in changes a customer's id ═════
-- Rex: an Owner rejects the claim suggesting him and a Manager deletes it, so
-- no claim refers to him any more (nothing else does either).
select pg_temp.as_user('o');
insert into tx values ('rej_R', pg_temp.reject('kR1', 'Impostor'));
select pg_temp.as_user('m');
select pg_temp.run('del_R', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kR1')));
select pg_temp.check(pg_temp.tx('rej_R') = 'ok' and pg_temp.tx('del_R') = 'ok' and pg_temp.claim_status('kR1') is null
    and not exists (select 1 from affiliate_account_claims where candidate_customer_id = pg_temp.fx('cR')),
  'P12 (setup) an Owner rejects the claim suggesting Rex and a Manager deletes it: no claim refers to him');
-- Staff, a Manager and an Owner, signed in, give Rex (protected) and Kim (not)
-- a new id directly, as the API would let them (RLS lets them update a
-- customer).
do $$
declare n int; got text := ''; who text; u uuid;
  rex uuid := pg_temp.fx('cR'); kim uuid := pg_temp.fx('cK');
begin
  foreach who in array array['s','m','o'] loop
    u := pg_temp.fx(who);
    perform set_config('request.jwt.claim.sub', u::text, true);
    execute 'set local role authenticated';
    begin
      update public.customers set id = gen_random_uuid() where id = rex;
      get diagnostics n = row_count; got := got || who || ':changed ' || n || ' ';
    exception when others then got := got || who || ':' || sqlerrm || ' '; end;
    begin
      update public.customers set id = gen_random_uuid(), notes = 'New id' where id = kim;
      get diagnostics n = row_count; got := got || who || ':changed ' || n || ' ';
    exception when others then got := got || who || ':' || sqlerrm || ' '; end;
    execute 'reset role';
  end loop;
  insert into tx values ('rekey', got);
end $$;
select pg_temp.check(pg_temp.tx('rekey') = replace('s:M s:M m:M m:M o:M o:M ', 'M', pg_temp.tx('id_msg'))
    and exists (select 1 from customers where id = pg_temp.fx('cR') and full_name = 'Rex Rejtest')
    and exists (select 1 from customers where id = pg_temp.fx('cK') and notes is distinct from 'New id'),
  'P12 staff, a Manager and an Owner cannot change a customer''s id, protected or not, in those words: ' || pg_temp.tx('rekey'));
-- Ordinary edits still work for staff, as the Customers page makes them
-- (and an update that sets the id to itself, as an upsert does).
do $$
declare n1 int; n2 int; got text := ''; kim uuid := pg_temp.fx('cK'); sfx text := pg_temp.tx('sfx'); u uuid := pg_temp.fx('s');
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  execute 'set local role authenticated';
  begin
    update public.customers
       set first_name = 'Kimberly', last_name = 'Rejtest', full_name = 'Kimberly Rejtest',
           email = 's379-kim-' || sfx || '@tests.invalid', phone = '+6583790218', notes = 'Moved house'
     where id = kim;
    get diagnostics n1 = row_count;
    update public.customers set id = id, notes = 'Moved house again' where id = kim;
    get diagnostics n2 = row_count;
    got := n1 || ',' || n2;
  exception when others then got := sqlerrm; end;
  execute 'reset role';
  insert into tx values ('edit', got);
end $$;
select pg_temp.check(pg_temp.tx('edit') = '1,1'
    and exists (select 1 from customers where id = pg_temp.fx('cK') and full_name = 'Kimberly Rejtest'
                   and email = 's379-kim-' || pg_temp.tx('sfx') || '@tests.invalid'
                   and public.normalize_customer_phone(phone) = '+6583790218' and notes = 'Moved house again'),
  'P12 staff still edit a customer''s name, email and phone (and an update naming the same id is fine): ' || pg_temp.tx('edit'));
-- So the protection stays on Rex: a login whose email, phone and name match
-- him still only parks a claim.
insert into tx values ('onb_R', pg_temp.onboard('lR2', 'Rex', 'Rejtest', '+65 8379 0216', 'kR2'));
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.tx('onb_R') = 'pending_verification' and pg_temp.linked_to('lR2') is null
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('kR2')) = pg_temp.fx('cR')
    and pg_temp.link_check('kR2', 'cR')->>'problem' = pg_temp.tx('rejected_msg'),
  'P12 so Rex stays protected after his rejected claim was deleted: sign-up parks a claim, and staff cannot link it');
-- Without a signed-in user (the service role, migrations, server jobs) an id
-- can still be changed.
do $$
declare c uuid; c2 uuid; got text;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role service_role';
  begin
    insert into public.customers(full_name, phone) values ('Ned Rejtest', '+6583790219') returning id into c;
    update public.customers set id = gen_random_uuid() where id = c returning id into c2;
    got := case when c2 is not null and c2 <> c then 'changed' else 'not changed' end;
  exception when others then got := sqlerrm; end;
  execute 'reset role';
  insert into tx values ('svc', got);
end $$;
select pg_temp.check(pg_temp.tx('svc') = 'changed', 'P12 the service role (no signed-in user) is not affected: ' || pg_temp.tx('svc'));
-- The lock follows the signed-in user, not the database role: as the table
-- owner (no SET ROLE, as an Owner's server-side block runs) with a member of
-- staff signed in, the id change is still refused.
do $$
declare c uuid; got text;
begin
  perform pg_temp.as_user('s');
  insert into public.customers(full_name, phone) values ('Nia Rejtest', '+6583790239') returning id into c;
  begin
    update public.customers set id = gen_random_uuid() where id = c;
    got := 'changed';
  exception when others then got := sqlerrm; end;
  insert into tx values ('owner_role_signed_in', got);
end $$;
select pg_temp.check(pg_temp.tx('owner_role_signed_in') = 'A customer''s id cannot be changed.',
  'P12 as the table owner with a member of staff signed in, the id change is refused too: ' || pg_temp.tx('owner_role_signed_in'));
select pg_temp.as_user('o');

-- ═════ G Grants ═════
select pg_temp.check(has_function_privilege('authenticated', 'public.affiliate_claim_link_check(uuid,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_pending_claims()', 'execute')
    and has_function_privilege('authenticated', 'public.resolve_affiliate_account_claim(uuid,uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'public.complete_affiliate_onboarding(text,text,text,boolean)', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_claim_link_check(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_pending_claims()', 'execute')
    and not has_function_privilege('anon', 'public.resolve_affiliate_account_claim(uuid,uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.complete_affiliate_onboarding(text,text,text,boolean)', 'execute')
    and has_function_privilege('authenticated', 'public.reject_affiliate_account_claim(uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_rejected_claims()', 'execute')
    and not has_function_privilege('anon', 'public.reject_affiliate_account_claim(uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_rejected_claims()', 'execute'),
  'G the patched functions keep their grants: signed-in users call them, anon does not');
select pg_temp.check(not has_function_privilege('authenticated', 'public.tg_customers_id_fixed()', 'execute')
    and not has_function_privilege('anon', 'public.tg_customers_id_fixed()', 'execute')
    and (select tgenabled = 'O' and tgtype = 19 from pg_trigger where tgrelid = 'public.customers'::regclass and tgname = 'trg_customers_id_fixed'),
  'G the trigger function is no endpoint, and the trigger is on: before each update of a customer');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All reject-protects checks passed.';
end $$;
rollback;
