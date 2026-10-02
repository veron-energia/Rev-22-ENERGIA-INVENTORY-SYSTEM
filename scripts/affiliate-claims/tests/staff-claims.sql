-- Staff handle affiliate account claims; an Owner unlinks a wrong link (378).
--
--   S1 Staff list the Pending and the Rejected Account Claims.
--   S2 A phone in any format the app accepts is one number on both sides:
--      the claim's (as sign-up stored it) and the customer's (legacy rows
--      kept theirs as typed).
--   S3 Staff resolve a claim to the customer whose phone was entered; the
--      audit row says the phones matched.
--   S4 Staff are refused a customer with another phone, with no phone, a
--      deleted customer, a customer who already has a portal login, and a
--      claim whose login is a staff login; the note is still required.
--      Nothing is written by a refusal. The last four refuse Owners and
--      Managers too, with a sentence instead of a raw database error.
--   S5 Staff reject and delete claims.
--   S6 Owners and Managers still link any customer.
--   S7 Admin, Inventory Manager, a deactivated or deleted staff login and an
--      affiliate login are refused, as before.
--   U  Unlink: an Owner only (not a Manager, staff, an Admin or a deactivated
--      Owner), with a reason. Only the login's link goes: the affiliate
--      record, its code, commissions, referred customers and the claim
--      history stay; an audit row says who, which customer, which login,
--      when it last signed in (Supabase Auth's record) and why. The login no
--      longer opens the portal for the customer.
--   R  The unlinked login can claim again: its next sign-up check parks a new
--      pending claim, flagged "previously unlinked". Staff cannot link it back
--      to that customer; an Owner may and a Manager does, to the same
--      affiliate record and code. Staff cannot link a new login to that
--      customer either (the list flags a claim that suggests them); an Owner
--      or Manager can. Sign-up still links a login whose verified email, phone
--      and name match one customer; but once an Owner has unlinked a login
--      from that customer, such a sign-up parks a pending claim instead (for
--      the unlinked login, and for a new login whose email staff put on the
--      customer's record), and staff cannot resolve it; a login with a
--      rejected claim is told it was unsuccessful.
--   F  Only an unlink's own audit row counts (written by
--      unlink_affiliate_account for an Owner): rows written through
--      write_audit, by staff or by an Owner, or written for a Manager, change
--      nothing for the Resolve check, the pending list or sign-up.
--   S8 Staff cannot resolve their own claim (its phone is their work or
--      personal phone, or its email is their profile email or their personal
--      email); another staff member, a Manager or an Owner can, and an
--      Owner's or Manager's own numbers and emails do not hold them up (as
--      before). Every resolve's audit row records each of the five
--      comparisons. Their login's email is compared too, as a backstop: the
--      claims here that carry a staff login's email are inserted directly,
--      since sign-up never makes one. Emptying their own profile hides their
--      personal details, and the audit row then shows false against a
--      profile filled in again later; that row is the only record of it.
--   S9 Staff cannot link a customer whose phone was changed after the person
--      signed up (a change before both their claim and their login, or the
--      same number rewritten in another format, does not count); a Manager or
--      Owner can, and the audit row says so. Deleting the claim and letting
--      the person sign in again does not reset it: it counts from when their
--      login was made.
--   S10 When several customers in use share the phone entered, staff link
--      only the suggested customer; a deleted customer does not count (even
--      one that had the phone since), nor one that had the phone before the
--      person signed up; one that had it since does (moving the other
--      sharer's phone away does not help); a Manager or Owner links any of
--      them. Staff are refused when an earlier claim of the login, deleted
--      or rejected, suggested another sharer or no one (renaming customers,
--      deleting the claim and letting the person sign in again changes whom
--      the new claim suggests); not when it suggested the same customer, nor
--      when the phone is not shared. The resolve audit row records how many
--      shared the phone, whether the customer was the suggested one and
--      whether an earlier claim suggested another.
--   S11 Staff delete only pending claims and claims a staff member rejected;
--      a rejection by an Owner or Manager (or by no one recorded) is theirs.
--   S12 Closing a claim whose login is already linked writes an audit row.
--   G  Who may call what.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Needs 378 (install it after "begin;" on a
-- database that does not have it yet). Every name, phone and email below is
-- invented; the phones are +65 8378 01xx.
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
create function pg_temp.link_check(claim text, cust text) returns jsonb language sql as
$$ select public.affiliate_claim_link_check(pg_temp.fx(claim), pg_temp.fx(cust)) $$;
create function pg_temp.linked_to(login text) returns uuid language sql as
$$ select customer_id from public.affiliate_accounts where auth_user_id = pg_temp.fx(login) $$;
create function pg_temp.claim_status(claim text) returns text language sql as
$$ select status from public.affiliate_account_claims where id = pg_temp.fx(claim) $$;
create function pg_temp.has_affiliate(cust text) returns boolean language sql as
$$ select exists (select 1 from public.customer_affiliates where customer_id = pg_temp.fx(cust)) $$;
create function pg_temp.pending_ids() returns uuid[] language sql as
$$ select coalesce(array_agg((e->>'claim_id')::uuid), '{}') from jsonb_array_elements(public.affiliate_pending_claims()) e $$;
create function pg_temp.rejected_ids() returns uuid[] language sql as
$$ select coalesce(array_agg((e->>'claim_id')::uuid), '{}') from jsonb_array_elements(public.affiliate_rejected_claims()) e $$;
create function pg_temp.onboard(login text, first text, last text, phone text) returns text language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user(login);
  r := public.complete_affiliate_onboarding(first, last, phone, true);
  return coalesce(r->>'status', '?');
exception when others then return 'ERROR: ' || sqlerrm;
end$$;
-- The words the Resolve window shows staff; the database says the same.
insert into tx values ('phone_msg', 'Only an Owner or Manager can link this claim to a customer whose phone differs from the one entered.');
insert into tx values ('own_msg', 'You cannot resolve your own claim. Ask an Owner or Manager.');
insert into tx values ('unlinked_msg', 'An Owner unlinked this login from this customer. Only an Owner or Manager can link it again.');
insert into tx values ('changed_msg', 'This customer''s phone was changed after the person signed up. Only an Owner or Manager can link this claim to them.');
insert into tx values ('shared_msg', 'Several customers share this phone. Only an Owner or Manager can link it to a customer other than the suggested one.');
insert into tx values ('cust_unlinked_msg', 'An Owner unlinked a login from this customer before. Only an Owner or Manager can link a login to them.');
insert into tx values ('delete_msg', 'Only an Owner or Manager can remove a rejection they made.');
insert into tx values ('earlier_msg', 'This person''s earlier claim suggested a different customer. Only an Owner or Manager can link it.');

select pg_temp.check(to_regprocedure('public.unlink_affiliate_account(uuid,text)') is not null
    and to_regprocedure('public.affiliate_claim_link_check(uuid,uuid)') is not null,
  'S0 378 is installed');
select pg_temp.check(not exists (select 1 from public.customers where public.normalize_customer_phone(phone) like '+65837801__'),
  'S0 no customer uses the test phones +65 8378 01xx (the checks below assume so)');

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); k text; u uuid;
begin
  insert into tx values ('sfx', sfx);
  -- Staff and other roles.
  foreach k in array array['o','m','s','s2','a','im','sd','sx','od'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 's378-' || k || '-' || sfx || '@tests.invalid', now());
  end loop;
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('o'),  'S378 Owner',           's378-o-'  || sfx || '@tests.invalid', 'owner'),
    (pg_temp.fx('m'),  'S378 Manager',         's378-m-'  || sfx || '@tests.invalid', 'manager'),
    (pg_temp.fx('s'),  'S378 Staff',           's378-s-'  || sfx || '@tests.invalid', 'staff'),
    (pg_temp.fx('s2'), 'S378 Second Staff',    's378-s2-' || sfx || '@tests.invalid', 'staff'),
    (pg_temp.fx('a'),  'S378 Admin',           's378-a-'  || sfx || '@tests.invalid', 'admin'),
    (pg_temp.fx('im'), 'S378 Stock Keeper',    's378-im-' || sfx || '@tests.invalid', 'inventory_manager'),
    (pg_temp.fx('sd'), 'S378 Former Staff',    's378-sd-' || sfx || '@tests.invalid', 'staff'),
    (pg_temp.fx('sx'), 'S378 Deleted Staff',   's378-sx-' || sfx || '@tests.invalid', 'staff'),
    (pg_temp.fx('od'), 'S378 Former Owner',    's378-od-' || sfx || '@tests.invalid', 'owner');
  update profiles set is_active = false where id in (pg_temp.fx('sd'), pg_temp.fx('od'));
  -- The staff member's own numbers and personal email (S8).
  update profiles set personal_phone = '+65 8378 0141', work_phone = '83780142',
                      personal_email = 's378-sp-' || sfx || '@tests.invalid'
   where id = pg_temp.fx('s');
  -- A second staff member whose profile still has an old email: their login's
  -- email and their profile's email both count as theirs.
  update profiles set email = 's378-s2old-' || sfx || '@tests.invalid' where id = pg_temp.fx('s2');
  -- A Manager's and an Owner's own numbers and email (S8: not a rule for them).
  update profiles set personal_email = 's378-mp-' || sfx || '@tests.invalid' where id = pg_temp.fx('m');
  update profiles set work_phone = '+6583780148' where id = pg_temp.fx('o');
  update profiles set deleted_at = now() where id = pg_temp.fx('sx');
  -- Affiliate portal logins: no profiles row, except l7 (a staff login whose
  -- claim was parked before 320 refused staff at sign-up).
  foreach k in array array['l1','l2','l3','l4','l5','l6','l7','l8','l9','lh','f1','f2','f3','f4','f5',
                           'ls1','ls2','ls3','ls4','ls5','ls6','ls7','ls8','lc1','lc2','lc3','lsh1','lsh2','lsh3','lone','ldo','ldm','ldn','lds',
                           'lrs','l1n','l9n','l9r','lfk','lfa','ldau','lnul','lsame','lrj','lrjn','lres','lsolo'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 's378-' || k || '-' || sfx || '@tests.invalid', now());
  end loop;
  -- S9: a login made three hours ago (its first claim is two hours old).
  -- S10: one made a day ago.
  update auth.users set created_at = now() - interval '3 hours' where id = pg_temp.fx('lrs');
  update auth.users set created_at = now() - interval '1 day' where id = pg_temp.fx('lone');
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('l7'), 'S378 Staff Who Signed Up', 's378-l7-' || sfx || '@tests.invalid', 'staff');
  update profiles set is_active = false where id = pg_temp.fx('l7');
end $$;
select pg_temp.as_user('o');

-- Customers. Most are saved through the phone policy (stored as +65…);
-- the "legacy" ones keep their phone as typed, as rows from before the
-- policy do, so both sides of the comparison see raw formats.
do $$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('Ola Othertest', '+6583780102') returning id into c; insert into fx values ('cOther', c);
  insert into customers(full_name, phone) values ('Dee Deletedtest', '+6583780105') returning id into c; insert into fx values ('cDel', c);
  update customers set deleted_at = now() where id = c;
  insert into customers(full_name, phone) values ('Hal Haslogintest', '+6583780106') returning id into c; insert into fx values ('cHas', c);
  insert into customers(full_name, phone) values ('Sid Stafflogintest', '+6583780107') returning id into c; insert into fx values ('cStaffLogin', c);
  insert into customers(full_name, phone) values ('Rea Rejecttest', '+6583780108') returning id into c; insert into fx values ('cReject', c);
  insert into customers(full_name, phone, email) values ('Sam Selftest', '+6583780109', 's378-l9-' || pg_temp.tx('sfx') || '@tests.invalid')
    returning id into c; insert into fx values ('cSelf', c);
  insert into customers(full_name, phone) values ('Fay Formattest', '+6583780125') returning id into c; insert into fx values ('cF5', c);
  -- S8: customers with the staff member's own numbers, and two more.
  insert into customers(full_name, phone) values ('Sel Selftest', '+6583780141') returning id into c; insert into fx values ('cSelfP', c);
  insert into customers(full_name, phone) values ('Sew Selftest', '+6583780142') returning id into c; insert into fx values ('cSelfW', c);
  insert into customers(full_name, phone) values ('See Selftest', '+6583780143') returning id into c; insert into fx values ('cSelfE', c);
  insert into customers(full_name, phone) values ('Sep Selftest', '+6583780144') returning id into c; insert into fx values ('cSelfE2', c);
  insert into customers(full_name, phone) values ('Sea Selftest', '+6583780145') returning id into c; insert into fx values ('cSelfA', c);
  insert into customers(full_name, phone) values ('Seb Selftest', '+6583780146') returning id into c; insert into fx values ('cSelfB', c);
  insert into customers(full_name, phone) values ('Sem Selftest', '+6583780147') returning id into c; insert into fx values ('cSelfM', c);
  insert into customers(full_name, phone) values ('Seo Selftest', '+6583780148') returning id into c; insert into fx values ('cSelfO', c);
  -- S9: a phone that will be changed to the one entered; one changed before
  -- the claim was made.
  insert into customers(full_name, phone) values ('Cha Changetest', '+6583780151') returning id into c; insert into fx values ('cChg', c);
  insert into customers(full_name, phone) values ('Col Changetest', '+6583780153') returning id into c; insert into fx values ('cOld', c);
  -- S9: the customer whose phone staff change, before the claim is deleted
  -- and the person signs in again.
  insert into customers(full_name, phone) values ('Res Resigntest', '+6583780181') returning id into c; insert into fx values ('cRs', c);
  -- S10: two customers in use and a deleted one share a phone; one in use and
  -- a deleted one share another.
  insert into customers(full_name, phone) values ('Sha Sharetest', '+6583780161') returning id into c; insert into fx values ('cShA', c);
  insert into customers(full_name, phone) values ('Shb Sharetest', '+6583780161') returning id into c; insert into fx values ('cShB', c);
  insert into customers(full_name, phone) values ('Shd Sharetest', '+6583780161') returning id into c; insert into fx values ('cShD', c);
  update customers set deleted_at = now() where id = c;
  insert into customers(full_name, phone) values ('One Sharetest', '+6583780162') returning id into c; insert into fx values ('cOne', c);
  insert into customers(full_name, phone) values ('Ond Sharetest', '+6583780162') returning id into c; insert into fx values ('cOneDel', c);
  update customers set deleted_at = now() where id = c;
  -- A customer who had +6583780162 two days ago, before that person signed
  -- up, and has another number now (the history row is below).
  insert into customers(full_name, phone) values ('Onp Sharetest', '+6583780167') returning id into c; insert into fx values ('cOnePast', c);
  -- A deleted customer who had +6583780162 an hour ago, after that person
  -- signed up (the history row is below).
  insert into customers(full_name, phone) values ('Odh Sharetest', '+6583780168') returning id into c; insert into fx values ('cOneDelPast', c);
  update customers set deleted_at = now() where id = c;
  -- Two more in use share a phone; the claim suggests the first.
  insert into customers(full_name, phone) values ('Sta Sharetest', '+6583780163') returning id into c; insert into fx values ('cSh3A', c);
  insert into customers(full_name, phone) values ('Stb Sharetest', '+6583780163') returning id into c; insert into fx values ('cSh3B', c);
  -- S10: a mother and daughter share a phone (staff will swap their names);
  -- two more share another; one customer has a phone of her own.
  insert into customers(full_name, phone) values ('Mae Nametest', '+6583780195') returning id into c; insert into fx values ('cMum', c);
  insert into customers(full_name, phone) values ('Dot Nametest', '+6583780195') returning id into c; insert into fx values ('cDot', c);
  insert into customers(full_name, phone) values ('Rja Rejkepttest', '+6583780196') returning id into c; insert into fx values ('cRjA', c);
  insert into customers(full_name, phone) values ('Rjb Rejkepttest', '+6583780196') returning id into c; insert into fx values ('cRjB', c);
  insert into customers(full_name, phone) values ('Sol Solotest', '+6583780197') returning id into c; insert into fx values ('cSolo', c);
  -- F: a customer with a pending claim, and one whose email, phone and name
  -- match a login (sign-up links it by itself).
  insert into customers(full_name, phone) values ('Fik Forgetest', '+6583780191') returning id into c; insert into fx values ('cFk', c);
  insert into customers(full_name, phone, email) values ('Fau Forgetest', '+6583780192', 's378-lfa-' || pg_temp.tx('sfx') || '@tests.invalid')
    returning id into c; insert into fx values ('cFa', c);
end $$;
set local session_replication_role = replica;
with c as (insert into customers(full_name, phone) values ('Ana Claimtest', '+65 8378 0101') returning id) insert into fx select 'cMatch', id from c;
with c as (insert into customers(full_name, phone) values ('Nia Nophonetest', '') returning id) insert into fx select 'cNo', id from c;
with c as (insert into customers(full_name, phone) values ('Fen Formattest', '+65 8378 0121') returning id) insert into fx select 'cF1', id from c;
with c as (insert into customers(full_name, phone) values ('Fio Formattest', '(+65) 8378-0122') returning id) insert into fx select 'cF2', id from c;
with c as (insert into customers(full_name, phone) values ('Fox Formattest', '0065 8378 0123') returning id) insert into fx select 'cF3', id from c;
with c as (insert into customers(full_name, phone) values ('Fru Formattest', '83780124') returning id) insert into fx select 'cF4', id from c;
with c as (insert into customers(full_name, phone) values ('Cre Changetest', '83780154') returning id) insert into fx select 'cRef', id from c;
set local session_replication_role = origin;

-- cMatch is already an affiliate with history: a code, a referred customer,
-- an invoice and a commission. Unlinking must leave all of it.
do $$
declare st uuid; b uuid; inv uuid; ca uuid;
begin
  insert into customer_affiliates(customer_id, status, activated_at, referral_code)
    values (pg_temp.fx('cMatch'), 'active', now(), public.generate_affiliate_referral_code()) returning id into ca;
  insert into fx values ('caMatch', ca);
  insert into stores(name, code, country_code) values ('S378 Store ' || pg_temp.tx('sfx'), 'S378' || upper(pg_temp.tx('sfx')), 'SG') returning id into st;
  insert into customers(full_name, phone, referred_by) values ('Bea Buyertest', '+6583780110', pg_temp.fx('cMatch')) returning id into b;
  insert into fx values ('cBuyer', b);
  insert into invoices(invoice_no, store_id, customer_id, created_by, status, total_amount, paid_amount)
    values ('S378-INV-' || pg_temp.tx('sfx'), st, b, pg_temp.fx('o'), 'paid', 100, 100) returning id into inv;
  insert into commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, line_amount, rate, commission_amount, status)
    values (inv, b, pg_temp.fx('cMatch'), 'tier1', 100, 0.1, 10, 'earned');
  -- cHas already has a portal login (lh).
  insert into customer_affiliates(customer_id, status, activated_at, referral_code)
    values (pg_temp.fx('cHas'), 'active', now(), public.generate_affiliate_referral_code()) returning id into ca;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('lh'), pg_temp.fx('cHas'), ca, 'claimed');
end $$;

-- The claims, as sign-up parks them (older ones kept the digits as typed).
do $$
declare r record; c uuid;
begin
  for r in select * from (values
      ('k1', 'l1', '83780101',      'Ana Claimtest',     'cMatch',      null, '0'),
      ('k2', 'l2', '+6583780112',   'Ola Othertest',     null,          null, '0'),
      ('k3', 'l3', '+6583780103',   'Nia Nophonetest',   null,          null, '0'),
      ('k4', 'l4', null,            'Nia Nophonetest',   null,          null, '0'),
      ('k5', 'l5', '+6583780105',   'Dee Deletedtest',   null,          null, '0'),
      ('k6', 'l6', '+6583780106',   'Hal Haslogintest',  'cHas',        null, '0'),
      ('k7', 'l7', '+6583780107',   'Sid Stafflogintest','cStaffLogin', null, '0'),
      ('k8', 'l8', '+6583780108',   'Rea Rejecttest',    'cReject',     null, '0'),
      ('kf1','f1', '6583780121',    'Fen Formattest',    null,          null, '0'),
      ('kf2','f2', '+65 8378 0122', 'Fio Formattest',    null,          null, '0'),
      ('kf3','f3', '+65-8378-0123', 'Fox Formattest',    null,          null, '0'),
      ('kf4','f4', '+6583780124',   'Fru Formattest',    null,          null, '0'),
      ('kf5','f5', '+6583780126',   'Fay Formattest',    null,          null, '0'),
      -- S8: the staff member's personal phone (in another format), their work
      -- phone, their own email (in capitals), their personal email.
      ('ks1','ls1','6583780141',    'Sel Selftest',      null,          null, '0'),
      ('ks2','ls2','+6583780142',   'Sew Selftest',      null,          null, '0'),
      ('ks3','ls3','+6583780143',   'See Selftest',      null,          upper('s378-s-' || pg_temp.tx('sfx') || '@tests.invalid'), '0'),
      ('ks4','ls4','+6583780144',   'Sep Selftest',      null,          's378-sp-' || pg_temp.tx('sfx') || '@tests.invalid', '0'),
      -- The second staff member's login email, and their profile's old email.
      ('ks5','ls5','+6583780145',   'Sea Selftest',      null,          's378-s2-' || pg_temp.tx('sfx') || '@tests.invalid', '0'),
      ('ks6','ls6','+6583780146',   'Seb Selftest',      null,          's378-s2old-' || pg_temp.tx('sfx') || '@tests.invalid', '0'),
      -- The Manager's personal email; the Owner's work phone.
      ('ks7','ls7','+6583780147',   'Sem Selftest',      null,          's378-mp-' || pg_temp.tx('sfx') || '@tests.invalid', '0'),
      ('ks8','ls8','+6583780148',   'Seo Selftest',      null,          null, '0'),
      -- S9: made an hour ago.
      ('kc1','lc1','+6583780152',   'Cha Changetest',    'cChg',        null, '1 hour'),
      ('kc2','lc2','+6583780153',   'Col Changetest',    'cOld',        null, '1 hour'),
      ('kc3','lc3','+6583780154',   'Cre Changetest',    'cRef',        null, '1 hour'),
      -- S9: made two hours ago, by a login made three hours ago.
      ('krs1','lrs','+6583780182',  'Res Resigntest',    null,          null, '2 hours'),
      -- S10: one suggests cShA, one suggests no one.
      ('ksh1','lsh1','+6583780161', 'Sha Sharetest',     'cShA',        null, '0'),
      ('ksh2','lsh2','+6583780161', 'Shx Sharetest',     null,          null, '0'),
      ('kone','lone','+6583780162', 'One Sharetest',     null,          null, '0'),
      ('ksh3','lsh3','+6583780163', 'Sta Sharetest',     'cSh3A',       null, '0'),
      -- S11: to be rejected by an Owner, a Manager, staff; kdn below.
      ('kdo','ldo','+6583780171',   'Dor Deletetest',    null,          null, '0'),
      ('kdm','ldm','+6583780172',   'Dem Deletetest',    null,          null, '0'),
      ('kds','lds','+6583780174',   'Des Deletetest',    null,          null, '0'),
      -- S12: a login that is already linked (lh, to cHas).
      ('kt', 'lh', '+6583780106',   'Hal Haslogintest',  'cHas',        null, '0'),
      -- S10: claims that staff delete (one suggests no one, one Dot); one
      -- suggesting Rjb from a login whose earlier claim, still kept, was
      -- rejected; one whose phone no one else has.
      ('knul1','lnul','+6583780195','Nel Nametest',      null,          null, '0'),
      ('ksame1','lsame','+6583780195','Dot Nametest',    'cDot',        null, '0'),
      ('krj','lrj', '+6583780196',  'Rjb Rejkepttest',   'cRjB',        null, '0'),
      ('krjn','lrjn','+6583780196', 'Rjb Rejkepttest',   'cRjB',        null, '0'),
      ('kres','lres','+6583780196', 'Rjb Rejkepttest',   'cRjB',        null, '0'),
      ('ksolo1','lsolo','+6583780197','Sal Solotest',    null,          null, '0'),
      -- F: a claim for a customer whose unlink rows will be forged.
      ('kfk','lfk', '+6583780191',  'Fik Forgetest',     'cFk',         null, '0')) t(k, login, phone, name, cand, email, age)
  loop
    insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name, created_at)
      values (pg_temp.fx(r.login), r.phone, coalesce(r.email, (select email from auth.users where id = pg_temp.fx(r.login))),
              pg_temp.fx(r.cand), r.name, now() - r.age::interval)
      returning id into c;
    insert into fx values (r.k, c);
  end loop;
  -- S11: a claim rejected with no one recorded (as some older ones are).
  insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, entered_name, status, rejected_at, rejection_reason)
    values (pg_temp.fx('ldn'), '+6583780173', (select email from auth.users where id = pg_temp.fx('ldn')), 'Den Deletetest',
            'rejected', now(), 'Rejected before it was recorded who did')
    returning id into c;
  insert into fx values ('kdn', c);
  -- S10: lrj's earlier claim, suggesting Rja, was rejected (with no audit
  -- row, as older ones were) and is still kept.
  insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name,
                                       status, rejected_at, rejection_reason, created_at)
    values (pg_temp.fx('lrj'), '+6583780196', (select email from auth.users where id = pg_temp.fx('lrj')), pg_temp.fx('cRjA'),
            'Rja Rejkepttest', 'rejected', now() - interval '1 hour', 'Could not reach them', now() - interval '2 hours')
    returning id into c;
  insert into fx values ('krj0', c);
  -- lrjn's rejected claim, still kept, suggested no one.
  insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, entered_name, status, rejected_at, rejection_reason, created_at)
    values (pg_temp.fx('lrjn'), '+6583780196', (select email from auth.users where id = pg_temp.fx('lrjn')), 'Rj Rejkepttest',
            'rejected', now() - interval '1 hour', 'Could not reach them', now() - interval '2 hours')
    returning id into c;
  insert into fx values ('krjn0', c);
  -- lres's earlier claim, suggesting Rja, was resolved (the login was linked
  -- then, and is not now).
  insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name,
                                       status, resolved_at, resolution_note, created_at)
    values (pg_temp.fx('lres'), '+6583780196', (select email from auth.users where id = pg_temp.fx('lres')), pg_temp.fx('cRjA'),
            'Rja Rejkepttest', 'resolved', now() - interval '1 hour', 'Checked', now() - interval '2 hours')
    returning id into c;
  insert into fx values ('kres0', c);
  -- R: l9r has a rejected claim.
  insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, entered_name, status, rejected_at, rejection_reason)
    values (pg_temp.fx('l9r'), '+6583780109', (select email from auth.users where id = pg_temp.fx('l9r')), 'Sam Selftest',
            'rejected', now(), 'Not Sam')
    returning id into c;
  insert into fx values ('k9r0', c);
  -- S9: a phone change recorded two hours ago, before kc2 was made.
  insert into customer_phone_history(customer_id, phone, reason, created_at)
    values (pg_temp.fx('cOld'), '+6583780159', 'Changed before the claim', now() - interval '2 hours');
  -- S10: cOnePast had +6583780162 until two days ago, before lone was made.
  insert into customer_phone_history(customer_id, phone, reason, created_at)
    values (pg_temp.fx('cOnePast'), '+6583780162', 'Changed before the person signed up', now() - interval '2 days');
  -- S10: cOneDelPast had +6583780162 until an hour ago, after lone was made,
  -- and has been deleted since.
  insert into customer_phone_history(customer_id, phone, reason, created_at)
    values (pg_temp.fx('cOneDelPast'), '+6583780162', 'Changed after the person signed up', now() - interval '1 hour');
end $$;

-- ═════ S1 Staff list the claims ═════
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err('select public.affiliate_pending_claims()') is null
    and pg_temp.pending_ids() @> array[pg_temp.fx('k1'), pg_temp.fx('k2'), pg_temp.fx('k7'), pg_temp.fx('k8')],
  'S1 staff list the pending claims');
select pg_temp.check((select e->>'entered_phone' = '83780101' and e->>'entered_name' = 'Ana Claimtest' and e->>'candidate_name' = 'Ana Claimtest'
                        from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx('k1')),
  'S1 with what the person entered and the likely customer, as Owners and Managers see them');
select pg_temp.check(pg_temp.err('select public.affiliate_rejected_claims()') is null,
  'S1 staff list the rejected claims (checked with a rejected claim in S5)');

-- ═════ S2 One number in any format ═════
select pg_temp.check((pg_temp.link_check('kf1', 'cF1')->>'phones_match')::boolean and pg_temp.link_check('kf1', 'cF1')->>'problem' is null
    and (pg_temp.link_check('kf2', 'cF2')->>'phones_match')::boolean and pg_temp.link_check('kf2', 'cF2')->>'problem' is null
    and (pg_temp.link_check('kf3', 'cF3')->>'phones_match')::boolean and pg_temp.link_check('kf3', 'cF3')->>'problem' is null
    and (pg_temp.link_check('kf4', 'cF4')->>'phones_match')::boolean and pg_temp.link_check('kf4', 'cF4')->>'problem' is null,
  'S2 "6583780121" = "+65 8378 0121", "+65 8378 0122" = "(+65) 8378-0122", "+65-8378-0123" = "0065 8378 0123", "+6583780124" = "83780124": staff may link each');
select pg_temp.check(not (pg_temp.link_check('kf5', 'cF5')->>'phones_match')::boolean
    and pg_temp.link_check('kf5', 'cF5')->>'problem' = pg_temp.tx('phone_msg'),
  'S2 one digit apart is another phone, and the check says why staff cannot link it');
select pg_temp.check((select pg_temp.link_check('kf4', 'cF4') ?& array['entered_phone','customer_phone','customer_name','phones_match','problem'])
    and pg_temp.link_check('kf4', 'cF4')->>'entered_phone' = '+6583780124' and pg_temp.link_check('kf4', 'cF4')->>'customer_phone' = '83780124',
  'S2 the check returns both phones as they are kept, for the Resolve window to show side by side');

-- ═════ S3 Staff resolve to the customer with the phone entered ═════
select pg_temp.check(pg_temp.resolve('k1', 'cMatch') is null, 'S3 staff resolve "83780101" to the customer whose phone is "+65 8378 0101"');
select pg_temp.check(pg_temp.linked_to('l1') = pg_temp.fx('cMatch') and pg_temp.claim_status('k1') = 'resolved'
    and (select resolved_by from affiliate_account_claims where id = pg_temp.fx('k1')) = pg_temp.fx('s'),
  'S3 the login is linked, the claim resolved by the staff member');
select pg_temp.check((select (select affiliate_id from affiliate_accounts where auth_user_id = pg_temp.fx('l1')) = pg_temp.fx('caMatch')),
  'S3 to the customer''s existing affiliate record (its code is kept)');
select pg_temp.check(exists (select 1 from audit_logs where table_name = 'affiliate_account_claims' and record_id = pg_temp.fx('k1')
                                and action = 'affiliate_claim_resolved' and changed_by = pg_temp.fx('s') and actor_role = 'staff'
                                and (new_data->>'phones_match')::boolean and reason = 'Checked the phone with the person'
                                and not (new_data->>'phone_changed_since_claim')::boolean
                                and not (new_data->>'previously_unlinked')::boolean
                                and (new_data->>'customers_sharing_phone')::int = 1
                                and (new_data->>'suggested_customer')::boolean
                                and not (new_data->>'earlier_claim_other_customer')::boolean),
  'S3 the audit row names the staff member and says the phones matched (and the phone was not changed, the login never unlinked, one customer had the phone, the suggested one, and no earlier claim suggested another)');

-- ═════ S4 What staff may not link ═════
select pg_temp.check(pg_temp.resolve('k2', 'cOther') = pg_temp.tx('phone_msg'),
  'S4 staff refused a customer whose phone differs, in the words the page shows');
select pg_temp.check(pg_temp.resolve('k3', 'cNo') = pg_temp.tx('phone_msg'), 'S4 staff refused a customer with no phone');
select pg_temp.check(pg_temp.resolve('k4', 'cNo') = pg_temp.tx('phone_msg'),
  'S4 no phone entered and no phone on the customer is not a match either');
select pg_temp.check(pg_temp.resolve('k5', 'cDel') = 'This customer record has been deleted. Link the claim to the customer record that is in use.',
  'S4 staff refused a deleted customer (whose phone matches)');
select pg_temp.check((select r->>'customer_name' is null and r->>'customer_phone' is null and (r->>'customer_deleted')::boolean
                             and r->>'problem' like 'This customer record has been deleted.%'
                        from pg_temp.link_check('k5', 'cDel') r),
  'S4 and the check does not give staff the deleted customer''s name or phone');
select pg_temp.check(pg_temp.resolve('k6', 'cHas') = 'This customer already has an affiliate portal login. A customer can have only one; if that one is wrong, an Owner can unlink it first.',
  'S4 staff refused a customer who already has a portal login (whose phone matches), with a sentence');
select pg_temp.check(pg_temp.resolve('k7', 'cStaffLogin') = 'This login belongs to a member of staff, so it cannot also be an affiliate account.',
  'S4 staff refused a claim whose login is a staff login (whose phone matches)');
select pg_temp.check(pg_temp.resolve('k8', 'cReject', '  ') = 'A verification note is required',
  'S4 the verification note is still required');
select pg_temp.check(pg_temp.claim_status('k2') = 'pending' and pg_temp.claim_status('k3') = 'pending' and pg_temp.claim_status('k5') = 'pending'
    and pg_temp.claim_status('k6') = 'pending' and pg_temp.claim_status('k7') = 'pending' and pg_temp.claim_status('k8') = 'pending'
    and pg_temp.linked_to('l2') is null and pg_temp.linked_to('l3') is null and pg_temp.linked_to('l5') is null
    and pg_temp.linked_to('l6') is null and pg_temp.linked_to('l7') is null
    and not pg_temp.has_affiliate('cOther') and not pg_temp.has_affiliate('cNo') and not pg_temp.has_affiliate('cDel')
    and not pg_temp.has_affiliate('cStaffLogin'),
  'S4 a refusal writes nothing: the claims stay pending, no login is linked, no affiliate record is made');
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.resolve('k5', 'cDel') = 'This customer record has been deleted. Link the claim to the customer record that is in use.'
    and pg_temp.resolve('k6', 'cHas') = 'This customer already has an affiliate portal login. A customer can have only one; if that one is wrong, an Owner can unlink it first.'
    and pg_temp.resolve('k7', 'cStaffLogin') = 'This login belongs to a member of staff, so it cannot also be an affiliate account.'
    and pg_temp.resolve('k8', 'cReject', '') = 'A verification note is required',
  'S4 an Owner is refused the same four (the login check, a deleted customer, the raw unique-constraint error before 378)');
select pg_temp.check((select r->>'customer_name' = 'Dee Deletedtest' and r->>'customer_phone' = '+6583780105'
                        from pg_temp.link_check('k5', 'cDel') r),
  'S4 an Owner still sees the deleted customer''s name and phone in the check');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.resolve('k6', 'cHas') like 'This customer already has an affiliate portal login.%'
    and pg_temp.resolve('k5', 'cDel') like 'This customer record has been deleted.%'
    and pg_temp.resolve('k7', 'cStaffLogin') like 'This login belongs to a member of staff%',
  'S4 and so is a Manager');
select pg_temp.check(pg_temp.err(format('select public.resolve_affiliate_account_claim(%L, %L, %L)', pg_temp.fx('k2'), gen_random_uuid(), 'x')) = 'Customer not found',
  'S4 a customer that does not exist is named as such');

-- ═════ S5 Staff reject and delete ═════
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err(format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('k8'), '')) = 'A reason is required',
  'S5 rejecting still needs a reason');
select pg_temp.run('reject', format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('k8'), 'Could not reach the person'));
select pg_temp.check(pg_temp.tx('reject') = 'ok' and pg_temp.claim_status('k8') = 'rejected'
    and (select rejected_by from affiliate_account_claims where id = pg_temp.fx('k8')) = pg_temp.fx('s'),
  'S5 staff reject a claim');
select pg_temp.check(pg_temp.rejected_ids() @> array[pg_temp.fx('k8')] and not (pg_temp.pending_ids() @> array[pg_temp.fx('k8')]),
  'S5 it moves from Pending to Rejected Account Claims, for staff too');
select pg_temp.run('delete', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('k8')));
select pg_temp.check(pg_temp.tx('delete') = 'ok'
    and not exists (select 1 from affiliate_account_claims where id = pg_temp.fx('k8'))
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('k8') and action = 'affiliate_claim_deleted' and actor_role = 'staff'),
  'S5 staff delete a rejected claim, with an audit row');
select pg_temp.run('delete', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kf5')));
select pg_temp.check(pg_temp.tx('delete') = 'ok'
    and not exists (select 1 from affiliate_account_claims where id = pg_temp.fx('kf5')),
  'S5 and a pending one');
select pg_temp.check(pg_temp.err(format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('k1'))) like 'A resolved claim cannot be deleted%',
  'S5 a resolved claim still cannot be deleted (it is the account history)');

-- ═════ S6 Owners and Managers link any customer ═════
select pg_temp.as_user('m');
select pg_temp.check((pg_temp.link_check('k2', 'cOther')->>'problem') is null and not (pg_temp.link_check('k2', 'cOther')->>'phones_match')::boolean,
  'S6 for a Manager the check allows another phone, and still says the phones differ');
insert into tx values ('mgr_other', coalesce(pg_temp.resolve('k2', 'cOther', 'Verified in person; changed number'), 'ok'));
select pg_temp.check(pg_temp.tx('mgr_other') = 'ok' and pg_temp.linked_to('l2') = pg_temp.fx('cOther'),
  'S6 a Manager links a customer whose phone differs');
select pg_temp.check(exists (select 1 from audit_logs where record_id = pg_temp.fx('k2') and action = 'affiliate_claim_resolved'
                                and actor_role = 'manager' and not (new_data->>'phones_match')::boolean),
  'S6 and the audit row says the phones differed');
select pg_temp.as_user('o');
insert into tx values ('own_nophone', coalesce(pg_temp.resolve('k3', 'cNo', 'Verified by email'), 'ok'));
select pg_temp.check(pg_temp.tx('own_nophone') = 'ok' and pg_temp.linked_to('l3') = pg_temp.fx('cNo'),
  'S6 an Owner links a customer with no phone');
select pg_temp.check(pg_temp.pending_ids() @> array[pg_temp.fx('k4')] and pg_temp.err('select public.affiliate_rejected_claims()') is null,
  'S6 Owners still list the claims');

-- ═════ S7 Everyone else is refused, as before ═════
do $$
declare who text; e text; msgs text := '';
begin
  foreach who in array array['a','im','sd','sx','lh'] loop
    perform pg_temp.as_user(who);
    foreach e in array array[
        'select public.affiliate_pending_claims()',
        'select public.affiliate_rejected_claims()',
        format('select public.resolve_affiliate_account_claim(%L, %L, %L)', pg_temp.fx('kf1'), pg_temp.fx('cF1'), 'x'),
        format('select public.affiliate_claim_link_check(%L, %L)', pg_temp.fx('kf1'), pg_temp.fx('cF1')),
        format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('kf1'), 'x'),
        format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kf1'))] loop
      if pg_temp.err(e) is null or pg_temp.err(e) not similar to '%(Owner or Manager|Owner, Manager or Staff)%' then
        msgs := msgs || who || ': ' || coalesce(pg_temp.err(e), 'allowed') || ' (' || left(e, 50) || '); ';
      end if;
    end loop;
  end loop;
  perform pg_temp.check(msgs = '', 'S7 Admin, Inventory Manager, a deactivated staff login, a deleted staff login and an affiliate login are refused every claim function by the role check' || coalesce(': ' || nullif(msgs, ''), ''));
  perform pg_temp.check(pg_temp.claim_status('kf1') = 'pending' and pg_temp.linked_to('f1') is null, 'S7 and nothing changed');
end $$;

-- ═════ S8 Not their own claim ═════
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' = pg_temp.tx('own_msg') and (r->>'own_claim')::boolean and (r->>'phones_match')::boolean
                        from pg_temp.link_check('ks1', 'cSelfP') r)
    and pg_temp.resolve('ks1', 'cSelfP') = pg_temp.tx('own_msg'),
  'S8 staff cannot resolve a claim whose phone is their personal phone ("6583780141" = "+65 8378 0141"), in the owner''s words');
select pg_temp.check(pg_temp.resolve('ks2', 'cSelfW') = pg_temp.tx('own_msg'),
  'S8 nor one whose phone is their work phone ("+6583780142" = "83780142")');
select pg_temp.check(pg_temp.resolve('ks3', 'cSelfE') = pg_temp.tx('own_msg'),
  'S8 nor one whose email is their own email (in capitals)');
select pg_temp.check(pg_temp.resolve('ks4', 'cSelfE2') = pg_temp.tx('own_msg'),
  'S8 nor one whose email is their personal email');
select pg_temp.check(pg_temp.claim_status('ks1') = 'pending' and pg_temp.claim_status('ks2') = 'pending'
    and pg_temp.claim_status('ks3') = 'pending' and pg_temp.claim_status('ks4') = 'pending'
    and pg_temp.linked_to('ls1') is null and pg_temp.linked_to('ls2') is null
    and pg_temp.linked_to('ls3') is null and pg_temp.linked_to('ls4') is null,
  'S8 nothing is linked');
select pg_temp.as_user('s2');
select pg_temp.check((select r->>'problem' is null and not (r->>'own_claim')::boolean from pg_temp.link_check('ks1', 'cSelfP') r)
    and pg_temp.resolve('ks1', 'cSelfP', 'Checked by a colleague') is null and pg_temp.linked_to('ls1') = pg_temp.fx('cSelfP'),
  'S8 another member of staff resolves it');
select pg_temp.check(pg_temp.resolve('ks5', 'cSelfA') = pg_temp.tx('own_msg'),
  'S8 (backstop: sign-up never makes such a claim) a staff member cannot resolve a claim with their login''s email');
select pg_temp.check(pg_temp.resolve('ks6', 'cSelfB') = pg_temp.tx('own_msg'),
  'S8 nor one with the email on their profile, where that differs');
select pg_temp.as_user('o');
select pg_temp.check((select r->>'problem' is null from pg_temp.link_check('ks3', 'cSelfE') r),
  'S8 an Owner may link one');
select pg_temp.check((select r->>'problem' is null and (r->>'own_claim')::boolean from pg_temp.link_check('ks8', 'cSelfO') r)
    and pg_temp.resolve('ks8', 'cSelfO', 'Owner''s own') is null and pg_temp.linked_to('ls8') = pg_temp.fx('cSelfO'),
  'S8 an Owner is not held up by their own work phone (as before)');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.resolve('ks2', 'cSelfW', 'Checked by the Manager') is null and pg_temp.linked_to('ls2') = pg_temp.fx('cSelfW'),
  'S8 and a Manager links one');
select pg_temp.check((select r->>'problem' is null and (r->>'own_claim')::boolean from pg_temp.link_check('ks7', 'cSelfM') r)
    and pg_temp.resolve('ks7', 'cSelfM', 'Manager''s own') is null and pg_temp.linked_to('ls7') = pg_temp.fx('cSelfM'),
  'S8 nor is a Manager by their own personal email (as before)');
-- Each resolve's audit row keeps the five comparisons, as they stood.
create function pg_temp.own_audit(claim text) returns jsonb language sql as
$$ select new_data->'own_contact_match' || jsonb_build_object('own_claim', new_data->'own_claim')
     from audit_logs where table_name = 'affiliate_account_claims' and record_id = pg_temp.fx(claim)
      and action = 'affiliate_claim_resolved' $$;
select pg_temp.check(pg_temp.own_audit('k1') = '{"auth_email": false, "profile_email": false, "personal_email": false,
                                                 "work_phone": false, "personal_phone": false, "own_claim": false}'::jsonb,
  'S8 a resolve''s audit row records own_claim and each of the five own-contact comparisons (staff, not their own: all false)');
select pg_temp.check(pg_temp.own_audit('ks7') = '{"auth_email": false, "profile_email": false, "personal_email": true,
                                                  "work_phone": false, "personal_phone": false, "own_claim": true}'::jsonb
    and pg_temp.own_audit('ks8') = '{"auth_email": false, "profile_email": false, "personal_email": false,
                                     "work_phone": true, "personal_phone": false, "own_claim": true}'::jsonb
    and pg_temp.own_audit('ks1') = '{"auth_email": false, "profile_email": false, "personal_email": false,
                                     "work_phone": false, "personal_phone": false, "own_claim": false}'::jsonb,
  'S8 the Manager''s own personal email and the Owner''s own work phone are on their rows; a colleague''s resolve of staff''s claim is not their own');

-- A staff member empties the contact details on their own profile (the
-- profile row is theirs to update) to resolve their own claims.
select pg_temp.as_user('s');
update profiles set email = 's378-snew-' || pg_temp.tx('sfx') || '@tests.invalid',
                    personal_email = null, personal_phone = null, work_phone = null
 where id = pg_temp.fx('s');
select pg_temp.check((select r->>'problem' = pg_temp.tx('own_msg')
                             and r->'own_contact_match' = '{"auth_email": true, "profile_email": false, "personal_email": false,
                                                            "work_phone": false, "personal_phone": false}'::jsonb
                        from pg_temp.link_check('ks3', 'cSelfE') r)
    and pg_temp.resolve('ks3', 'cSelfE') = pg_temp.tx('own_msg') and pg_temp.linked_to('ls3') is null,
  'S8 (backstop: sign-up never makes a claim with a staff login''s email) after the profile is emptied, the login''s email still counts');
insert into tx values ('own_emptied', coalesce(pg_temp.resolve('ks4', 'cSelfE2', 'Checked'), 'ok'));
select pg_temp.check(pg_temp.tx('own_emptied') = 'ok' and pg_temp.linked_to('ls4') = pg_temp.fx('cSelfE2')
    and pg_temp.own_audit('ks4') = '{"auth_email": false, "profile_email": false, "personal_email": false,
                                     "work_phone": false, "personal_phone": false, "own_claim": false}'::jsonb,
  'S8 (as reported) with their personal email emptied, their own personal-email claim goes through; the audit row, its only record, says no detail matched then');
update profiles set email = 's378-s-' || pg_temp.tx('sfx') || '@tests.invalid', personal_email = 's378-sp-' || pg_temp.tx('sfx') || '@tests.invalid',
                    personal_phone = '+65 8378 0141', work_phone = '83780142'
 where id = pg_temp.fx('s');
select pg_temp.check((select lower(p.personal_email) = lower(cl.verified_email)
                        from profiles p, affiliate_account_claims cl where p.id = pg_temp.fx('s') and cl.id = pg_temp.fx('ks4'))
    and (pg_temp.link_check('ks4', 'cSelfE2')->'own_contact_match'->>'personal_email')::boolean
    and not (pg_temp.own_audit('ks4')->>'personal_email')::boolean,
  'S8 once they fill it in again, the profile matches the claim while the audit row says it did not: the restore shows');

-- ═════ S9 A phone changed since the person signed up ═════
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.link_check('kc1', 'cChg')->>'problem' = pg_temp.tx('phone_msg'),
  'S9 (setup) staff cannot link kc1 to cChg: the phones differ');
-- Staff are allowed to edit customers: they change the phone to the one entered.
update customers set phone = '+6583780152' where id = pg_temp.fx('cChg');
select pg_temp.check((select count(*) from customer_phone_history where customer_id = pg_temp.fx('cChg')) = 1,
  'S9 (setup) the change is in the phone history');
select pg_temp.check((select (r->>'phones_match')::boolean and (r->>'phone_changed_since_claim')::boolean and r->>'problem' = pg_temp.tx('changed_msg')
                        from pg_temp.link_check('kc1', 'cChg') r)
    and pg_temp.resolve('kc1', 'cChg') = pg_temp.tx('changed_msg')
    and pg_temp.claim_status('kc1') = 'pending' and pg_temp.linked_to('lc1') is null,
  'S9 now the phones match, but staff are refused: the customer''s phone was changed after the person signed up');
select pg_temp.check((select (r->>'phones_match')::boolean and not (r->>'phone_changed_since_claim')::boolean and r->>'problem' is null
                        from pg_temp.link_check('kc2', 'cOld') r),
  'S9 a change made before the claim (and before the login) does not count');
update customers set phone = '+6583780154' where id = pg_temp.fx('cRef');
select pg_temp.check((select count(*) from customer_phone_history where customer_id = pg_temp.fx('cRef') and phone = '83780154') = 1
    and (select (r->>'phones_match')::boolean and not (r->>'phone_changed_since_claim')::boolean and r->>'problem' is null
           from pg_temp.link_check('kc3', 'cRef') r)
    and pg_temp.resolve('kc3', 'cRef') is null and pg_temp.linked_to('lc3') = pg_temp.fx('cRef'),
  'S9 the same number rewritten in the standard format ("83780154" to "+6583780154") is not a change: staff link it');
select pg_temp.as_user('o');
select pg_temp.check((select r->>'problem' is null and (r->>'phone_changed_since_claim')::boolean from pg_temp.link_check('kc1', 'cChg') r),
  'S9 for an Owner the check allows it, and says the phone was changed');
select pg_temp.as_user('m');
insert into tx values ('mgr_changed', coalesce(pg_temp.resolve('kc1', 'cChg', 'Customer confirmed the new number'), 'ok'));
select pg_temp.check(pg_temp.tx('mgr_changed') = 'ok' and pg_temp.linked_to('lc1') = pg_temp.fx('cChg')
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('kc1') and action = 'affiliate_claim_resolved' and actor_role = 'manager'
                   and (new_data->>'phones_match')::boolean and (new_data->>'phone_changed_since_claim')::boolean),
  'S9 a Manager links it, and the audit row says the phone was changed since the claim');
-- Deleting the claim does not reset the clock. lrs's login was made three
-- hours ago and its claim two hours ago; staff change cRs's phone to the one
-- it entered (an hour ago, between the two claims), delete the refused claim,
-- and the person signs in again, which parks a new claim suggesting cRs.
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.link_check('krs1', 'cRs')->>'problem' = pg_temp.tx('phone_msg'),
  'S9 (setup) staff cannot link krs1 to cRs: the phones differ');
update customers set phone = '+6583780182' where id = pg_temp.fx('cRs');
update customer_phone_history set created_at = now() - interval '1 hour' where customer_id = pg_temp.fx('cRs');
select pg_temp.run('del_rs', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('krs1')));
select pg_temp.check(pg_temp.tx('del_rs') = 'ok' and pg_temp.claim_status('krs1') is null,
  'S9 (setup) staff delete the refused pending claim');
insert into tx values ('rs_again', pg_temp.onboard('lrs', 'Res', 'Resigntest', '+65 8378 0182'));
insert into fx select 'krs2', id from affiliate_account_claims where auth_user_id = pg_temp.fx('lrs') and status = 'pending';
select pg_temp.check(pg_temp.tx('rs_again') = 'pending_verification' and pg_temp.fx('krs2') is not null
    and (select candidate_customer_id = pg_temp.fx('cRs') and created_at = now() from affiliate_account_claims where id = pg_temp.fx('krs2')),
  'S9 (setup) the person signs in again: a new claim, made after the change, suggesting cRs');
select pg_temp.as_user('s');
select pg_temp.check((select (r->>'phones_match')::boolean and (r->>'suggested_customer')::boolean
                             and (r->>'phone_changed_since_claim')::boolean and r->>'problem' = pg_temp.tx('changed_msg')
                        from pg_temp.link_check('krs2', 'cRs') r)
    and pg_temp.resolve('krs2', 'cRs') = pg_temp.tx('changed_msg')
    and pg_temp.claim_status('krs2') = 'pending' and pg_temp.linked_to('lrs') is null,
  'S9 staff are still refused: the change came after the person''s login was made, though before this claim');
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.link_check('krs2', 'cRs')->>'problem' is null,
  'S9 an Owner may link it');

-- ═════ S10 A phone several customers share ═════
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' is null and (r->>'customers_sharing_phone')::int = 2 and (r->>'suggested_customer')::boolean
                        from pg_temp.link_check('ksh1', 'cShA') r),
  'S10 two customers in use share the phone (the deleted third does not count); staff may link the suggested one');
select pg_temp.check((select (r->>'phones_match')::boolean and r->>'problem' = pg_temp.tx('shared_msg') from pg_temp.link_check('ksh1', 'cShB') r)
    and pg_temp.resolve('ksh1', 'cShB') = pg_temp.tx('shared_msg') and pg_temp.linked_to('lsh1') is null,
  'S10 but not the other customer with that phone, in the owner''s words');
select pg_temp.check(pg_temp.link_check('ksh2', 'cShA')->>'problem' = pg_temp.tx('shared_msg')
    and pg_temp.link_check('ksh2', 'cShB')->>'problem' = pg_temp.tx('shared_msg'),
  'S10 a claim that suggests no one: staff link neither');
select pg_temp.check((select r->>'problem' is null and (r->>'customers_sharing_phone')::int = 1 from pg_temp.link_check('kone', 'cOne') r),
  'S10 one customer in use, a deleted one with the same phone, a deleted one that had it since the person signed up, and one that had it only before: not shared, staff may link it');
-- Staff move the suggested sharer's phone away, so the chosen one looks like
-- the only customer with it, then put it back.
select pg_temp.check(pg_temp.link_check('ksh3', 'cSh3B')->>'problem' = pg_temp.tx('shared_msg'),
  'S10 (setup) staff cannot link ksh3 to cSh3B, which shares the phone with the suggested cSh3A');
update customers set phone = '+6583780169' where id = pg_temp.fx('cSh3A');
select pg_temp.check((select (r->>'customers_sharing_phone')::int = 2 and (r->>'phones_match')::boolean
                             and not (r->>'phone_changed_since_claim')::boolean and r->>'problem' = pg_temp.tx('shared_msg')
                        from pg_temp.link_check('ksh3', 'cSh3B') r)
    and pg_temp.resolve('ksh3', 'cSh3B') = pg_temp.tx('shared_msg') and pg_temp.linked_to('lsh3') is null,
  'S10 with the other sharer''s phone moved away, it still counts (it had the number since the person signed up): staff are refused');
update customers set phone = '+6583780163' where id = pg_temp.fx('cSh3A');
select pg_temp.check((pg_temp.link_check('ksh3', 'cSh3B')->>'customers_sharing_phone')::int = 2
    and pg_temp.resolve('ksh3', 'cSh3B') = pg_temp.tx('shared_msg') and pg_temp.linked_to('lsh3') is null,
  'S10 and after it is put back (the customer whose phone and history both have it counts once)');
select pg_temp.check(pg_temp.resolve('ksh1', 'cShA') is null and pg_temp.linked_to('lsh1') = pg_temp.fx('cShA'),
  'S10 staff link the suggested customer');
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.link_check('ksh2', 'cShB')->>'problem' is null,
  'S10 for an Owner the check allows another customer with the phone');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.resolve('ksh2', 'cShB', 'Asked which family member') is null and pg_temp.linked_to('lsh2') = pg_temp.fx('cShB'),
  'S10 a Manager links one');
select pg_temp.check(exists (select 1 from audit_logs where record_id = pg_temp.fx('ksh1') and action = 'affiliate_claim_resolved' and actor_role = 'staff'
                                and (new_data->>'customers_sharing_phone')::int = 2 and (new_data->>'suggested_customer')::boolean
                                and not (new_data->>'earlier_claim_other_customer')::boolean)
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('ksh2') and action = 'affiliate_claim_resolved' and actor_role = 'manager'
                   and (new_data->>'customers_sharing_phone')::int = 2 and not (new_data->>'suggested_customer')::boolean),
  'S10 the resolve audit rows say how many customers shared the phone and whether the one linked was the suggested one');

-- Staff steer whom a claim suggests: the daughter signs up with the name
-- of Dot, who shares a phone with her mother Mae. Staff swap the two names
-- round, delete the claim, and the daughter's next visit parks a new claim,
-- which now suggests Mae.
insert into tx values ('dau1', pg_temp.onboard('ldau', 'Dot', 'Nametest', '+65 8378 0195'));
insert into fx select 'kdau1', id from affiliate_account_claims where auth_user_id = pg_temp.fx('ldau') and status = 'pending';
select pg_temp.check(pg_temp.tx('dau1') = 'pending_verification'
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('kdau1')) = pg_temp.fx('cDot'),
  'S10 (setup) the daughter signs up as Dot: a pending claim suggesting Dot');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.link_check('kdau1', 'cMum')->>'problem' = pg_temp.tx('shared_msg'),
  'S10 (setup) staff cannot link her to Mae, who shares the phone');
update customers set full_name = 'Dorothy Nametest' where id = pg_temp.fx('cDot');
update customers set full_name = 'Dot Nametest' where id = pg_temp.fx('cMum');
select pg_temp.run('del_dau', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kdau1')));
insert into tx values ('dau2', pg_temp.onboard('ldau', 'Dot', 'Nametest', '+65 8378 0195'));
insert into fx select 'kdau2', id from affiliate_account_claims where auth_user_id = pg_temp.fx('ldau') and status = 'pending';
select pg_temp.check(pg_temp.tx('del_dau') = 'ok' and pg_temp.tx('dau2') = 'pending_verification'
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('kdau2')) = pg_temp.fx('cMum'),
  'S10 (setup) staff swap the names, delete the claim; her next visit parks a claim that suggests Mae');
select pg_temp.as_user('s');
select pg_temp.check((select (r->>'phones_match')::boolean and (r->>'suggested_customer')::boolean
                             and (r->>'customers_sharing_phone')::int = 2 and not (r->>'phone_changed_since_claim')::boolean
                             and (r->>'earlier_claim_other_customer')::boolean and r->>'problem' = pg_temp.tx('earlier_msg')
                        from pg_temp.link_check('kdau2', 'cMum') r)
    and pg_temp.resolve('kdau2', 'cMum') = pg_temp.tx('earlier_msg')
    and pg_temp.claim_status('kdau2') = 'pending' and pg_temp.linked_to('ldau') is null,
  'S10 staff are refused Mae, now the suggested customer: her deleted claim suggested Dot, in the owner''s words');
select pg_temp.check(pg_temp.link_check('kdau2', 'cDot')->>'problem' = pg_temp.tx('shared_msg'),
  'S10 and Dot, no longer the suggested one, as before');
update customers set full_name = 'Mae Nametest' where id = pg_temp.fx('cMum');
update customers set full_name = 'Dot Nametest' where id = pg_temp.fx('cDot');
select pg_temp.check(pg_temp.resolve('kdau2', 'cMum') = pg_temp.tx('earlier_msg') and pg_temp.linked_to('ldau') is null,
  'S10 still after the names are put back');
-- An earlier claim that suggested no one counts too.
select pg_temp.run('del_nul', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('knul1')));
with c as (insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
             values (pg_temp.fx('lnul'), '+6583780195', (select email from auth.users where id = pg_temp.fx('lnul')), pg_temp.fx('cMum'), 'Mae Nametest')
             returning id)
insert into fx select 'knul2', id from c;
select pg_temp.check(pg_temp.tx('del_nul') = 'ok'
    and pg_temp.link_check('knul2', 'cMum')->>'problem' = pg_temp.tx('earlier_msg')
    and pg_temp.resolve('knul2', 'cMum') = pg_temp.tx('earlier_msg'),
  'S10 staff are refused when the deleted claim suggested no one and the new one suggests Mae');
-- A rejected claim still kept, suggesting another sharer.
select pg_temp.check((select (r->>'earlier_claim_other_customer')::boolean and r->>'problem' = pg_temp.tx('earlier_msg')
                        from pg_temp.link_check('krj', 'cRjB') r)
    and pg_temp.resolve('krj', 'cRjB') = pg_temp.tx('earlier_msg') and pg_temp.linked_to('lrj') is null,
  'S10 staff are refused when the login''s rejected claim, still kept, suggested another sharer');
select pg_temp.check(pg_temp.link_check('krjn', 'cRjB')->>'problem' = pg_temp.tx('earlier_msg')
    and pg_temp.resolve('krjn', 'cRjB') = pg_temp.tx('earlier_msg') and pg_temp.linked_to('lrjn') is null,
  'S10 or suggested no one');
select pg_temp.check((select r->>'problem' is null and not (r->>'earlier_claim_other_customer')::boolean from pg_temp.link_check('kres', 'cRjB') r),
  'S10 (as the rule stands) an earlier claim that was resolved, not deleted or rejected, does not count');
-- Not refused: the deleted claim suggested the same customer.
select pg_temp.run('del_same', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('ksame1')));
with c as (insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
             values (pg_temp.fx('lsame'), '+6583780195', (select email from auth.users where id = pg_temp.fx('lsame')), pg_temp.fx('cDot'), 'Dot Nametest')
             returning id)
insert into fx select 'ksame2', id from c;
select pg_temp.check(pg_temp.tx('del_same') = 'ok'
    and (select r->>'problem' is null and not (r->>'earlier_claim_other_customer')::boolean from pg_temp.link_check('ksame2', 'cDot') r)
    and pg_temp.resolve('ksame2', 'cDot') is null and pg_temp.linked_to('lsame') = pg_temp.fx('cDot'),
  'S10 staff link a login whose deleted claim suggested the same customer');
-- Not refused: no one else has the phone.
select pg_temp.run('del_solo', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('ksolo1')));
with c as (insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
             values (pg_temp.fx('lsolo'), '+6583780197', (select email from auth.users where id = pg_temp.fx('lsolo')), pg_temp.fx('cSolo'), 'Sol Solotest')
             returning id)
insert into fx select 'ksolo2', id from c;
select pg_temp.check(pg_temp.tx('del_solo') = 'ok'
    and (select r->>'problem' is null and (r->>'earlier_claim_other_customer')::boolean and (r->>'customers_sharing_phone')::int = 1
           from pg_temp.link_check('ksolo2', 'cSolo') r)
    and pg_temp.resolve('ksolo2', 'cSolo') is null and pg_temp.linked_to('lsolo') = pg_temp.fx('cSolo'),
  'S10 staff link a customer no one else shares the phone with, whatever the earlier claim suggested');
select pg_temp.as_user('m');
select pg_temp.check((select r->>'problem' is null and (r->>'earlier_claim_other_customer')::boolean from pg_temp.link_check('kdau2', 'cMum') r),
  'S10 for a Manager the check allows it, and says an earlier claim suggested another customer');
select pg_temp.as_user('o');
insert into tx values ('own_dau', coalesce(pg_temp.resolve('kdau2', 'cMum', 'Asked the daughter in the shop'), 'ok'));
select pg_temp.check(pg_temp.tx('own_dau') = 'ok' and pg_temp.linked_to('ldau') = pg_temp.fx('cMum')
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('kdau2') and action = 'affiliate_claim_resolved' and actor_role = 'owner'
                   and (new_data->>'customers_sharing_phone')::int = 2 and (new_data->>'suggested_customer')::boolean
                   and (new_data->>'earlier_claim_other_customer')::boolean),
  'S10 an Owner links it, and the audit row says two shared the phone, the customer was the suggested one, and an earlier claim suggested another');

-- ═════ S11 Whose rejections staff may delete ═════
select pg_temp.as_user('o');
select pg_temp.run('rej_o', format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('kdo'), 'Not the customer'));
select pg_temp.as_user('m');
select pg_temp.run('rej_m', format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('kdm'), 'Not the customer'));
select pg_temp.as_user('s');
select pg_temp.run('rej_s', format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('kds'), 'Could not reach them'));
select pg_temp.check(pg_temp.tx('rej_o') = 'ok' and pg_temp.tx('rej_m') = 'ok' and pg_temp.tx('rej_s') = 'ok'
    and pg_temp.claim_status('kdo') = 'rejected' and pg_temp.claim_status('kdm') = 'rejected'
    and pg_temp.claim_status('kds') = 'rejected' and pg_temp.claim_status('kdn') = 'rejected',
  'S11 (setup) rejected by an Owner, a Manager, staff, and by no one recorded');
select pg_temp.check((select bool_and(case (e->>'claim_id')::uuid when pg_temp.fx('kds') then (e->>'rejected_by_staff')::boolean
                                                         else not (e->>'rejected_by_staff')::boolean end)
                             and count(*) = 4
                        from jsonb_array_elements(public.affiliate_rejected_claims()) e
                       where (e->>'claim_id')::uuid in (pg_temp.fx('kdo'), pg_temp.fx('kdm'), pg_temp.fx('kds'), pg_temp.fx('kdn'))),
  'S11 the Rejected list says which a staff member rejected (for the page to offer staff Delete only there)');
select pg_temp.check(pg_temp.err(format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kdo'))) = pg_temp.tx('delete_msg')
    and pg_temp.claim_status('kdo') = 'rejected',
  'S11 staff cannot delete an Owner''s rejection, in the owner''s words');
select pg_temp.check(pg_temp.err(format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kdm'))) = pg_temp.tx('delete_msg')
    and pg_temp.claim_status('kdm') = 'rejected',
  'S11 nor a Manager''s');
select pg_temp.check(pg_temp.err(format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kdn'))) = pg_temp.tx('delete_msg')
    and pg_temp.claim_status('kdn') = 'rejected',
  'S11 nor one rejected by no one recorded');
select pg_temp.as_user('s2');
select pg_temp.run('del_s', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kds')));
select pg_temp.check(pg_temp.tx('del_s') = 'ok' and pg_temp.claim_status('kds') is null,
  'S11 staff delete a rejection another staff member made');
select pg_temp.as_user('m');
select pg_temp.run('del_mo', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kdo')));
select pg_temp.check(pg_temp.tx('del_mo') = 'ok' and pg_temp.claim_status('kdo') is null,
  'S11 a Manager deletes an Owner''s rejection, as before');
select pg_temp.as_user('o');
select pg_temp.run('del_om', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kdm')));
select pg_temp.run('del_on', format('select public.delete_affiliate_account_claim(%L)', pg_temp.fx('kdn')));
select pg_temp.check(pg_temp.tx('del_om') = 'ok' and pg_temp.claim_status('kdm') is null
    and pg_temp.tx('del_on') = 'ok' and pg_temp.claim_status('kdn') is null,
  'S11 an Owner deletes a Manager''s rejection and an unrecorded one, as before');

-- ═════ S12 Closing a claim whose login is already linked ═════
select pg_temp.as_user('s');
select pg_temp.run('tidy', format('select public.resolve_affiliate_account_claim(%L, %L, %L)', pg_temp.fx('kt'), pg_temp.fx('cOther'), 'Already has a login; closing'));
select pg_temp.check(pg_temp.tx('tidy') = 'ok' and pg_temp.claim_status('kt') = 'resolved' and pg_temp.linked_to('lh') = pg_temp.fx('cHas'),
  'S12 (as before) the claim is closed and the login stays where it is');
select pg_temp.check(exists (select 1 from audit_logs where table_name = 'affiliate_account_claims' and record_id = pg_temp.fx('kt')
                                and action = 'affiliate_claim_resolved' and changed_by = pg_temp.fx('s') and actor_role = 'staff'
                                and (new_data->>'already_linked')::boolean
                                and new_data->>'customer_id' = pg_temp.fx('cHas')::text
                                and new_data->>'chosen_customer_id' = pg_temp.fx('cOther')::text
                                and reason = 'Already has a login; closing'),
  'S12 and now an audit row says who closed it, the customer the login is linked to and the one chosen');

-- ═════ F Only an Owner's unlink counts ═════
-- write_audit is open to every signed-in user and takes the role from their
-- profile. Rows shaped like an unlink, for cFk (with kfk's login) and for
-- cFa: one written by staff and one by an Owner through write_audit, and
-- one written through write_audit_ex for a Manager (no signed-in user can
-- call that; this runs as the database owner).
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' is null and not (r->>'customer_previously_unlinked')::boolean from pg_temp.link_check('kfk', 'cFk') r),
  'F (setup) staff may link kfk to cFk');
do $$
declare who text; cust text;
begin
  foreach cust in array array['cFk','cFa'] loop
    foreach who in array array['s','o'] loop
      perform pg_temp.as_user(who);
      perform public.write_audit('affiliate_accounts', gen_random_uuid(), 'affiliate_login_unlinked',
        jsonb_build_object('customer_id', pg_temp.fx(cust), 'auth_user_id', pg_temp.fx('lfk')), null);
    end loop;
    perform pg_temp.as_user('m');
    perform public.write_audit_ex('affiliate_accounts', gen_random_uuid(), 'affiliate_login_unlinked',
      jsonb_build_object('customer_id', pg_temp.fx(cust), 'auth_user_id', pg_temp.fx('lfk')), null, 'affiliate', 'not an unlink', null);
  end loop;
end $$;
select pg_temp.check((select count(*) filter (where actor_role = 'staff' and module is null) = 2
                         and count(*) filter (where actor_role = 'owner' and module is null) = 2
                         and count(*) filter (where actor_role = 'manager' and module = 'affiliate') = 2 and count(*) = 6
                        from audit_logs where action = 'affiliate_login_unlinked'
                         and old_data->>'customer_id' in (pg_temp.fx('cFk')::text, pg_temp.fx('cFa')::text)),
  'F (setup) six rows shaped like an unlink: staff and an Owner through write_audit (signed-in users may call it), a Manager through write_audit_ex');
select pg_temp.check(has_function_privilege('authenticated', 'public.write_audit(text,uuid,text,jsonb,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'execute'),
  'F (as relied on) signed-in users may call write_audit, which leaves module empty, but not write_audit_ex');
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' is null and not (r->>'previously_unlinked')::boolean and not (r->>'customer_previously_unlinked')::boolean
                        from pg_temp.link_check('kfk', 'cFk') r),
  'F the Resolve check ignores them: neither this login nor this customer counts as unlinked');
select pg_temp.check((select not (e->>'previously_unlinked')::boolean and e->'unlinked_customer_ids' = '[]'::jsonb
                             and not (e->>'suggested_customer_unlinked')::boolean
                        from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx('kfk')),
  'F nor does the pending list flag the claim');
select pg_temp.check(pg_temp.resolve('kfk', 'cFk') is null and pg_temp.linked_to('lfk') = pg_temp.fx('cFk'),
  'F staff link it');
select pg_temp.check(pg_temp.onboard('lfa', 'Fau', 'Forgetest', '+65 8378 0192') = 'active' and pg_temp.linked_to('lfa') = pg_temp.fx('cFa'),
  'F sign-up still links a login whose email, phone and name match cFa by itself');

-- ═════ U Unlink ═════
-- Before: the customer's record, code, commissions and referred customer.
select pg_temp.as_user('o');
-- Supabase Auth's record of the last sign-in; affiliate_accounts.last_login_at
-- is only set when the link is made (now).
update auth.users set last_sign_in_at = '2026-09-30 08:00:00+00' where id = pg_temp.fx('l1');
insert into tx values ('before', (select jsonb_build_object(
  'affiliate', (select to_jsonb(ca) - 'updated_at' from customer_affiliates ca where ca.customer_id = pg_temp.fx('cMatch')),
  'commissions', (select jsonb_agg(to_jsonb(k) order by k.id) from commissions k where k.referrer_customer_id = pg_temp.fx('cMatch')),
  'referred', (select jsonb_agg(c.id) from customers c where c.referred_by = pg_temp.fx('cMatch')),
  'claim', (select to_jsonb(cl) from affiliate_account_claims cl where cl.id = pg_temp.fx('k1')))::text));
select pg_temp.check((select (tx.v::jsonb->'commissions'->0->>'commission_amount')::numeric = 10 and tx.v::jsonb->'affiliate'->>'referral_code' is not null
                        from tx where k = 'before'),
  'U (setup) the affiliate has a code and a commission of 10.00');
select pg_temp.check((select r->>'login_email' = (select email from auth.users where id = pg_temp.fx('l1'))
                          and (r->>'linked')::boolean and jsonb_array_length(r->'claims') = 1
                          and r->'claims'->0->>'resolved_by_name' = 'S378 Staff'
                          and r->'claims'->0->>'resolution_note' = 'Checked the phone with the person'
                        from public.affiliate_portal_login(pg_temp.fx('cMatch')) r),
  'U an Owner sees which login a customer has, and the claim that linked it (who resolved it, their note)');
select pg_temp.check((select (r->>'last_sign_in_at')::timestamptz = '2026-09-30 08:00:00+00' and not (r ? 'last_login_at')
                        from public.affiliate_portal_login(pg_temp.fx('cMatch')) r),
  'U it says when the login last signed in, from Supabase Auth (not the date the link was made)');
do $$
declare who text; bad text := '';
begin
  foreach who in array array['m','s','a','im','od','l1'] loop
    perform pg_temp.as_user(who);
    if coalesce(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)', pg_temp.fx('cMatch'), 'wrong person')), '') <> 'Only an Owner can unlink an affiliate login' then
      bad := bad || who || ' '; end if;
    if coalesce(pg_temp.err(format('select public.affiliate_portal_login(%L)', pg_temp.fx('cMatch'))), '') <> 'Only an Owner can see or unlink an affiliate login' then
      bad := bad || who || '(read) '; end if;
  end loop;
  perform pg_temp.as_user('o');
  perform pg_temp.check(bad = '' and pg_temp.linked_to('l1') = pg_temp.fx('cMatch'),
    'U a Manager, staff, an Admin, an Inventory Manager, a deactivated Owner and the affiliate are refused unlink and the login read' || coalesce(': ' || nullif(bad, ''), ''));
end $$;
select pg_temp.check(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)', pg_temp.fx('cMatch'), '   ')) = 'A reason is required to unlink a login'
    and pg_temp.err(format('select public.unlink_affiliate_account(%L, null)', pg_temp.fx('cMatch'))) = 'A reason is required to unlink a login'
    and pg_temp.linked_to('l1') = pg_temp.fx('cMatch'),
  'U a reason is required');
select pg_temp.check(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)', pg_temp.fx('cReject'), 'x')) = 'This customer has no portal login linked.'
    and pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)', gen_random_uuid(), 'x')) = 'Customer not found',
  'U a customer with no login, or no such customer, is named as such');
select pg_temp.check((select r->>'login_email' = (select email from auth.users where id = pg_temp.fx('l1')) and (r->>'ok')::boolean
                        from public.unlink_affiliate_account(pg_temp.fx('cMatch'), '  Linked to the wrong Ana  ') r),
  'U an Owner unlinks the login, and is told which login it was');
select pg_temp.check(pg_temp.linked_to('l1') is null and not exists (select 1 from affiliate_accounts where customer_id = pg_temp.fx('cMatch')),
  'U the link is gone');
select pg_temp.check((select jsonb_build_object(
    'affiliate', (select to_jsonb(ca) - 'updated_at' from customer_affiliates ca where ca.customer_id = pg_temp.fx('cMatch')),
    'commissions', (select jsonb_agg(to_jsonb(k) order by k.id) from commissions k where k.referrer_customer_id = pg_temp.fx('cMatch')),
    'referred', (select jsonb_agg(c.id) from customers c where c.referred_by = pg_temp.fx('cMatch')),
    'claim', (select to_jsonb(cl) from affiliate_account_claims cl where cl.id = pg_temp.fx('k1')))) = pg_temp.tx('before')::jsonb,
  'U the affiliate record, its code and status, the commission, the referred customer and the resolved claim are exactly as they were');
select pg_temp.check(exists (select 1 from audit_logs
                              where table_name = 'affiliate_accounts' and action = 'affiliate_login_unlinked'
                                and changed_by = pg_temp.fx('o') and actor_role = 'owner' and reason = 'Linked to the wrong Ana'
                                and old_data->>'customer_id' = pg_temp.fx('cMatch')::text
                                and old_data->>'customer_name' = 'Ana Claimtest'
                                and old_data->>'login_email' = (select email from auth.users where id = pg_temp.fx('l1'))
                                and old_data->>'auth_user_id' = pg_temp.fx('l1')::text
                                and old_data->'resolved_claim_ids' = jsonb_build_array(pg_temp.fx('k1'))
                                and (old_data->>'last_sign_in_at')::timestamptz = '2026-09-30 08:00:00+00'
                                and not (old_data ? 'last_login_at')
                                and new_data is null),
  'U the audit row: who, which customer, which login (email), when it last signed in, the claim that linked it, and the reason');
select pg_temp.check((select not (r->>'linked')::boolean from public.affiliate_portal_login(pg_temp.fx('cMatch')) r)
    and pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)', pg_temp.fx('cMatch'), 'again')) = 'This customer has no portal login linked.',
  'U afterwards the customer shows no login, and a second unlink says so');
select pg_temp.as_user('l1');
select pg_temp.check(public.current_affiliate_customer_id() is null
    and pg_temp.err('select public.affiliate_portal_me()') = 'Not an affiliate account'
    and pg_temp.err('select public.affiliate_portal_earnings()') = 'Not an affiliate account',
  'U the unlinked login no longer resolves to the customer: the portal answers "Not an affiliate account"');

-- ═════ R Linked again ═════
-- The person signs in again; the verify page runs the sign-up check with the
-- details saved at sign-up. Their email is on no customer, so the match is
-- not certain: a new pending claim, as the first time.
select pg_temp.check(pg_temp.onboard('l1', 'Ana', 'Claimtest', '+65 8378 0101') = 'pending_verification',
  'R the unlinked login can claim again: its next sign-up check parks a new pending claim');
select pg_temp.as_user('s');
insert into fx select 'k1b', id from affiliate_account_claims where auth_user_id = pg_temp.fx('l1') and status = 'pending';
select pg_temp.check(pg_temp.fx('k1b') is not null and pg_temp.pending_ids() @> array[pg_temp.fx('k1b')]
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('k1b')) = pg_temp.fx('cMatch')
    and pg_temp.claim_status('k1') = 'resolved',
  'R staff see it in Pending Account Claims; the first claim stays resolved, as history');
select pg_temp.check((select (e->>'previously_unlinked')::boolean and e->'unlinked_customer_ids' = jsonb_build_array(pg_temp.fx('cMatch')::text)
                        from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx('k1b'))
    and (select not (e->>'previously_unlinked')::boolean and e->'unlinked_customer_ids' = '[]'::jsonb
           from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx('kf1')),
  'R the pending list flags it "previously unlinked", from that customer (and not a claim from a login never unlinked)');
select pg_temp.check((select (r->>'phones_match')::boolean and (r->>'previously_unlinked')::boolean and r->>'unlinked_at' is not null
                             and r->>'problem' = pg_temp.tx('unlinked_msg')
                        from pg_temp.link_check('k1b', 'cMatch') r),
  'R staff cannot link it to the customer an Owner unlinked it from, though the phones match, in the owner''s words');
select pg_temp.check(not (pg_temp.link_check('k1b', 'cOther')->>'previously_unlinked')::boolean,
  'R the flag is for that customer only');
select pg_temp.check(pg_temp.resolve('k1b', 'cMatch', 'Phoned the number on file') = pg_temp.tx('unlinked_msg')
    and pg_temp.claim_status('k1b') = 'pending' and pg_temp.linked_to('l1') is null,
  'R and Save is refused: the login stays unlinked');
select pg_temp.as_user('s2');
select pg_temp.check(pg_temp.resolve('k1b', 'cMatch', 'Phoned the number on file') = pg_temp.tx('unlinked_msg'),
  'R by any member of staff');
-- The person (or anyone) makes a new login and signs up as Ana again.
insert into tx values ('new_login', pg_temp.onboard('l1n', 'Ana', 'Claimtest', '+65 8378 0101'));
insert into fx select 'k1n', id from affiliate_account_claims where auth_user_id = pg_temp.fx('l1n') and status = 'pending';
select pg_temp.check(pg_temp.tx('new_login') = 'pending_verification'
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('k1n')) = pg_temp.fx('cMatch'),
  'R (setup) a new login signs up as Ana: a pending claim suggesting her');
select pg_temp.as_user('s');
select pg_temp.check((select (e->>'suggested_customer_unlinked')::boolean and not (e->>'previously_unlinked')::boolean
                        from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx('k1n'))
    and (select (e->>'suggested_customer_unlinked')::boolean
           from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx('k1b'))
    and (select not (e->>'suggested_customer_unlinked')::boolean
           from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx('kc2'))
    and (select not (e->>'suggested_customer_unlinked')::boolean
           from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx('kf1')),
  'R the pending list flags every claim that suggests a customer an Owner unlinked a login from (not one suggesting another customer, or no one)');
select pg_temp.check((select (r->>'phones_match')::boolean and not (r->>'previously_unlinked')::boolean
                             and (r->>'customer_previously_unlinked')::boolean and r->>'customer_unlinked_at' is not null
                             and r->>'problem' = pg_temp.tx('cust_unlinked_msg')
                        from pg_temp.link_check('k1n', 'cMatch') r)
    and pg_temp.resolve('k1n', 'cMatch', 'Phoned the number on file') = pg_temp.tx('cust_unlinked_msg')
    and pg_temp.claim_status('k1n') = 'pending' and pg_temp.linked_to('l1n') is null,
  'R staff cannot link a new login to the customer an Owner unlinked a login from, though the phones match, in the owner''s words');
select pg_temp.check(not (pg_temp.link_check('k1n', 'cOther')->>'customer_previously_unlinked')::boolean,
  'R that is for that customer only');
select pg_temp.as_user('s2');
select pg_temp.check(pg_temp.resolve('k1n', 'cMatch', 'Phoned the number on file') = pg_temp.tx('cust_unlinked_msg'),
  'R by any member of staff');
select pg_temp.as_user('m');
select pg_temp.check((select r->>'problem' is null and (r->>'customer_previously_unlinked')::boolean from pg_temp.link_check('k1n', 'cMatch') r),
  'R a Manager may link a new login to her');
select pg_temp.as_user('o');
select pg_temp.check((select r->>'problem' is null and (r->>'previously_unlinked')::boolean from pg_temp.link_check('k1b', 'cMatch') r)
    and (select (e->>'previously_unlinked')::boolean from jsonb_array_elements(public.affiliate_pending_claims()) e
          where (e->>'claim_id')::uuid = pg_temp.fx('k1b'))
    and (select r->>'problem' is null and (r->>'customer_previously_unlinked')::boolean from pg_temp.link_check('k1n', 'cMatch') r)
    and (select (e->>'suggested_customer_unlinked')::boolean from jsonb_array_elements(public.affiliate_pending_claims()) e
          where (e->>'claim_id')::uuid = pg_temp.fx('k1n')),
  'R an Owner sees the flags too, and may link either login');
select pg_temp.as_user('m');
insert into tx values ('relink', coalesce(pg_temp.resolve('k1b', 'cMatch', 'Phoned the number on file'), 'ok'));
select pg_temp.check(pg_temp.tx('relink') = 'ok' and pg_temp.linked_to('l1') = pg_temp.fx('cMatch')
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('k1b') and action = 'affiliate_claim_resolved'
                   and actor_role = 'manager' and (new_data->>'previously_unlinked')::boolean
                   and (new_data->>'customer_previously_unlinked')::boolean),
  'R a Manager links it again, and the audit row says it had been unlinked');
select pg_temp.check((select affiliate_id from affiliate_accounts where auth_user_id = pg_temp.fx('l1')) = pg_temp.fx('caMatch')
    and (select referral_code from customer_affiliates where customer_id = pg_temp.fx('cMatch')) = pg_temp.tx('before')::jsonb->'affiliate'->>'referral_code'
    and (select count(*) from customer_affiliates where customer_id = pg_temp.fx('cMatch')) = 1,
  'R to the same affiliate record and referral code; nothing new is minted');
select pg_temp.as_user('l1');
select pg_temp.check(public.current_affiliate_customer_id() = pg_temp.fx('cMatch'), 'R and the login opens the portal for the customer again');
-- A login whose own sign-up matched the customer outright.
insert into tx values ('self1', pg_temp.onboard('l9', 'Sam', 'Selftest', '+65 8378 0109'));
select pg_temp.check(pg_temp.tx('self1') = 'active' and pg_temp.linked_to('l9') = pg_temp.fx('cSelf'),
  'R (setup) a sign-up whose verified email, phone and name match one customer links without a claim');
select pg_temp.as_user('o');
select pg_temp.run('self_unlink', format('select public.unlink_affiliate_account(%L, %L)', pg_temp.fx('cSelf'), 'test'));
select pg_temp.check(pg_temp.tx('self_unlink') = 'ok' and pg_temp.linked_to('l9') is null,
  'R (setup) an Owner unlinks it');
insert into tx values ('self2', pg_temp.onboard('l9', 'Sam', 'Selftest', '+65 8378 0109'));
insert into fx select 'k9b', id from affiliate_account_claims where auth_user_id = pg_temp.fx('l9') and status = 'pending';
select pg_temp.check(pg_temp.tx('self2') = 'pending_verification' and pg_temp.linked_to('l9') is null
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('k9b')) = pg_temp.fx('cSelf'),
  'R such a login is not linked straight back: its next sign-up check parks a pending claim suggesting the customer, though its email, phone and name still match');
select pg_temp.as_user('s');
select pg_temp.check((select (e->>'previously_unlinked')::boolean and (e->>'suggested_customer_unlinked')::boolean
                        from jsonb_array_elements(public.affiliate_pending_claims()) e where (e->>'claim_id')::uuid = pg_temp.fx('k9b'))
    and pg_temp.link_check('k9b', 'cSelf')->>'problem' = pg_temp.tx('unlinked_msg')
    and pg_temp.resolve('k9b', 'cSelf', 'Email, phone and name match') = pg_temp.tx('unlinked_msg')
    and pg_temp.linked_to('l9') is null and pg_temp.claim_status('k9b') = 'pending',
  'R it is flagged, and staff cannot resolve it');
-- Staff put a new login's email on the customer's record (the Customers page
-- lets them); that login signs up as Sam.
update customers set email = 's378-l9n-' || pg_temp.tx('sfx') || '@tests.invalid' where id = pg_temp.fx('cSelf');
insert into tx values ('self_new', pg_temp.onboard('l9n', 'Sam', 'Selftest', '+65 8378 0109'));
insert into fx select 'k9n', id from affiliate_account_claims where auth_user_id = pg_temp.fx('l9n') and status = 'pending';
select pg_temp.check(pg_temp.tx('self_new') = 'pending_verification' and pg_temp.linked_to('l9n') is null
    and (select candidate_customer_id from affiliate_account_claims where id = pg_temp.fx('k9n')) = pg_temp.fx('cSelf'),
  'R a new login whose email staff put on the customer''s record is not linked by sign-up either: a pending claim');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.resolve('k9n', 'cSelf', 'Email, phone and name match') = pg_temp.tx('cust_unlinked_msg')
    and pg_temp.linked_to('l9n') is null,
  'R and staff cannot resolve it');
-- A login with a rejected claim is told it was unsuccessful, as for any
-- claim sign-up cannot settle.
update customers set email = 's378-l9r-' || pg_temp.tx('sfx') || '@tests.invalid' where id = pg_temp.fx('cSelf');
select pg_temp.check(pg_temp.onboard('l9r', 'Sam', 'Selftest', '+65 8378 0109') = 'rejected' and pg_temp.linked_to('l9r') is null
    and not exists (select 1 from affiliate_account_claims where auth_user_id = pg_temp.fx('l9r') and status = 'pending'),
  'R a login with a rejected claim, whose email is on the record, is told verification was unsuccessful; nothing is linked or parked');
select pg_temp.as_user('o');
update customers set email = 's378-l9-' || pg_temp.tx('sfx') || '@tests.invalid' where id = pg_temp.fx('cSelf');
select pg_temp.check(pg_temp.resolve('k9b', 'cSelf', 'Sam confirmed in the shop') is null and pg_temp.linked_to('l9') = pg_temp.fx('cSelf'),
  'R an Owner links it back');

-- ═════ G Who may call what ═════
select pg_temp.check(not has_function_privilege('anon', 'public.affiliate_claim_link_check(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.unlink_affiliate_account(uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_portal_login(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_claim_staff()', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_claim_link_check(uuid,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.unlink_affiliate_account(uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_portal_login(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.affiliate_claim_staff()', 'execute')
    and has_function_privilege('authenticated', 'public.resolve_affiliate_account_claim(uuid,uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_pending_claims()', 'execute')
    and not has_function_privilege('anon', 'public.resolve_affiliate_account_claim(uuid,uuid,text)', 'execute'),
  'G signed-in users call the page''s functions (which check who they are); the staff test is internal; nothing is open to anon');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All staff affiliate claim checks passed.';
end $$;
rollback;
