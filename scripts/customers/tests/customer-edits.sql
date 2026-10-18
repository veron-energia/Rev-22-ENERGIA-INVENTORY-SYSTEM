-- 418: a customer edit is saved by update_customer and recorded, and the
-- date of birth follows the Owner's rule (9 Oct 2026, Q9 A).
--
--   * Owners, Managers and Staff (and the old Admin role) add and edit
--     customers and change their phone; Inventory Managers do not (the
--     Owner, 9 Oct 2026: stock and products only).
--   * Any member of staff who edits customers may fill in a missing date of
--     birth. Changing or clearing one already filled in needs an Owner or a
--     Manager (not Admin), and a reason. Every change is recorded with the
--     old and the new date.
--   * Every edit writes one audit row with the old and new value of each
--     field that changed; an edit that changes nothing writes nothing.
--   * A phone change needs a reason, which goes into the phone history.
--   * An edit made on an older copy of the customer is refused, and
--     update_customer locks the row before it checks.
--   * A referrer may be set when there is none; changing or removing one is
--     refused (Correct Referrer does it).
--   * is_referrer is never written, and "Is Referrer" in search_customers is
--     "has referred someone or is an affiliate".
--   * Staff no longer write the customers table directly; Add goes through
--     create_customer_quick, which no longer sets is_referrer and records the
--     new customer as 'customer_created'.
--
-- Disposable database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own against a
-- database with production's schema (406 to 414 in; 418 refuses without
-- 414). On a copy of production from before 414, pass a file that applies
-- it (run right after the begin below):
--   psql -v ON_ERROR_STOP=1 [-v prelude=/path/to/414.sql] -f scripts/customers/tests/customer-edits.sql
-- Fixture names carry T418, phones +659141 8xxx, emails @sig.invalid; every
-- name, phone and date is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif
\ir ../../../supabase/418_customer_edits_audited_and_phone_search.sql

create temp table t418(k text primary key, id uuid not null);
create function pg_temp.id(p text) returns uuid language sql stable as $f$ select id from t418 where k = p $f$;

-- Run p_sql as p_who and say what happened: 'ok' and the result, or the
-- SQLSTATE and the message. p_who is a login key (the API role
-- authenticated, as a signed-in browser), 'anon' or 'server' (no login).
create function pg_temp.try(p_who text, p_sql text) returns text language plpgsql as $f$
declare v_out text; v_state text; v_msg text;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    if p_who = 'server' then
      perform set_config('request.jwt.claims', '', true);
    elsif p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.id(p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v_out;
    execute 'reset role';
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || chr(9) || v_msg;
  end;
end $f$;

create function pg_temp.check(p_ok boolean, p_what text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL: %', p_what; end if;
end $f$;

-- update_customer as p_who, with the customer's id and its updated_at as read now.
create function pg_temp.edit(p_who text, p_key text, p_changes jsonb, p_reason text default null,
                             p_fresh boolean default true) returns text language plpgsql as $f$
declare v_at timestamptz;
begin
  select updated_at into v_at from public.customers where id = pg_temp.id(p_key);
  return pg_temp.try(p_who, format('select public.update_customer(%L::uuid, %L::jsonb, %L, %L::timestamptz)::text',
    pg_temp.id(p_key), p_changes, p_reason, case when p_fresh then v_at end));
end $f$;

-- ===== Fixture =====
do $$
declare k text; v uuid; st uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner', 'manager', 'staff', 'invman', 'admin', 'inactive', 'nostaff'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 't418-' || k || '@sig.invalid') returning id into v;
    insert into t418 values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active)
  select pg_temp.id(x.k), 'T418 ' || x.k, 't418-' || x.k || '@sig.invalid', x.role::public.user_role, x.active
    from (values ('owner', 'owner', true), ('manager', 'manager', true), ('staff', 'staff', true),
                 ('invman', 'inventory_manager', true), ('admin', 'admin', true), ('inactive', 'staff', false)) x(k, role, active);
  insert into public.stores(name, code, country_code) values ('T418 Store', 'T418S', 'SG') returning id into st;
  insert into t418 values ('store', st);

  insert into public.customers(first_name, last_name, phone) values ('T418', 'Nodob', '+6591418001') returning id into v;
  insert into t418 values ('nodob', v);
  insert into public.customers(first_name, last_name, phone, date_of_birth) values ('T418', 'Hasdob', '+6591418002', '1980-05-06') returning id into v;
  insert into t418 values ('hasdob', v);
  insert into public.customers(first_name, last_name, phone) values ('T418', 'Invman', '+6591418003') returning id into v;
  insert into t418 values ('invcust', v);
  insert into public.customers(first_name, last_name, phone, gender, gender_other, is_referrer)
    values ('T418', 'Plain', '+6591418004', 'other', 'T418 described', true) returning id into v;
  insert into t418 values ('plain', v);
  insert into public.customers(first_name, last_name, phone) values ('T418', 'Referrer', '+6591418005') returning id into v;
  insert into t418 values ('ref', v);
  insert into public.customers(first_name, last_name, phone) values ('T418', 'Other Referrer', '+6591418006') returning id into v;
  insert into t418 values ('ref2', v);
  insert into public.customers(first_name, last_name, phone, referred_by) values ('T418', 'Friend', '+6591418007', pg_temp.id('ref')) returning id into v;
  insert into t418 values ('friend', v);
  insert into public.customers(first_name, last_name, phone) values ('T418', 'Affiliate', '+6591418008') returning id into v;
  insert into t418 values ('aff', v);
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at) values (v, 'active', st, now());
  insert into public.customers(first_name, last_name, phone, deleted_at) values ('T418', 'Gone', '+6591418009', now()) returning id into v;
  insert into t418 values ('gone', v);
  insert into public.customers(first_name, last_name, phone) values ('T418', 'Phone', '+6591418010') returning id into v;
  insert into t418 values ('phone', v);
  insert into public.customers(first_name, last_name, phone) values ('T418', 'Admin', '+6591418011') returning id into v;
  insert into t418 values ('admincust', v);
  raise notice 'Fixture: 7 logins, 1 store, 11 customers';
end $$;

-- ===== 1. The date of birth (the Owner's rule) =====
do $$
declare v text; a record;
begin
  -- Staff fill in a missing date: allowed and recorded (old: none).
  v := pg_temp.edit('staff', 'nodob', '{"date_of_birth": "1991-02-03"}');
  perform pg_temp.check(v like 'ok%', '1a staff could not fill in a missing date of birth: ' || v);
  select * into a from public.audit_logs where record_id = pg_temp.id('nodob') and action = 'customer_updated';
  perform pg_temp.check(a.old_data = '{"date_of_birth": null}'::jsonb and a.new_data = '{"date_of_birth": "1991-02-03"}'::jsonb
                        and a.changed_by = pg_temp.id('staff') and a.actor_role = 'staff' and a.module = 'customers',
                        '1a the fill-in was not recorded with its old and new date');
  -- ... and once filled in, staff may not change it or clear it.
  v := pg_temp.edit('staff', 'nodob', '{"date_of_birth": "1991-02-04"}', 'Typo');
  perform pg_temp.check(v like '42501%Only an Owner or Manager can change a date of birth%', '1b staff changed a date of birth: ' || v);
  v := pg_temp.edit('staff', 'hasdob', '{"date_of_birth": null}', 'Clear it');
  perform pg_temp.check(v like '42501%', '1b staff cleared a date of birth: ' || v);
  v := pg_temp.edit('staff', 'hasdob', '{"date_of_birth": ""}', 'Clear it');
  perform pg_temp.check(v like '42501%', '1b staff cleared a date of birth with an empty value: ' || v);
  -- An Inventory Manager edits no customer (the Owner, 9 Oct 2026): not a
  -- missing date of birth, nor anything else.
  v := pg_temp.edit('invman', 'invcust', '{"date_of_birth": "1970-01-01"}');
  perform pg_temp.check(v like '42501%Your role cannot do this%', '1c an Inventory Manager filled in a date of birth: ' || v);
  v := pg_temp.edit('invman', 'invcust', '{"notes": "T418 note"}');
  perform pg_temp.check(v like '42501%', '1c an Inventory Manager edited a customer: ' || v);
  perform pg_temp.check((select date_of_birth is null and notes is null from public.customers where id = pg_temp.id('invcust'))
                        and not exists (select 1 from public.audit_logs where record_id = pg_temp.id('invcust')),
                        '1c an Inventory Manager''s refused edit left a change or an audit row');
  -- The old Admin role edits customers, and fills in a missing date, but is
  -- not an Owner or Manager: a filled-in date stays.
  v := pg_temp.edit('admin', 'admincust', '{"date_of_birth": "1975-03-04", "notes": "T418 admin"}');
  perform pg_temp.check(v like 'ok%', '1c an Admin could not edit a customer: ' || v);
  v := pg_temp.edit('admin', 'admincust', '{"date_of_birth": "1975-03-05"}', 'Typo');
  perform pg_temp.check(v like '42501%Only an Owner or Manager can change a date of birth%', '1c an Admin changed a date of birth: ' || v);
  -- A Manager needs a reason.
  v := pg_temp.edit('manager', 'hasdob', '{"date_of_birth": "1980-05-07"}');
  perform pg_temp.check(v like 'P0001%A reason is required to change a date of birth%', '1d a Manager changed a date with no reason: ' || v);
  v := pg_temp.edit('manager', 'hasdob', '{"date_of_birth": "1980-05-07"}', '   ');
  perform pg_temp.check(v like 'P0001%A reason is required%', '1d a blank reason was taken: ' || v);
  v := pg_temp.edit('manager', 'hasdob', '{"date_of_birth": "1980-05-07"}', 'Customer showed her IC');
  perform pg_temp.check(v like 'ok%', '1d a Manager with a reason was refused: ' || v);
  perform pg_temp.check((select date_of_birth from public.customers where id = pg_temp.id('hasdob')) = date '1980-05-07', '1d the date was not saved');
  select * into a from public.audit_logs where record_id = pg_temp.id('hasdob') and action = 'customer_updated';
  perform pg_temp.check(a.old_data->>'date_of_birth' = '1980-05-06' and a.new_data->>'date_of_birth' = '1980-05-07'
                        and a.reason = 'Customer showed her IC' and a.changed_by = pg_temp.id('manager'),
                        '1d the change was not recorded with its old and new date and the reason');
  -- An Owner may clear it, with a reason.
  v := pg_temp.edit('owner', 'hasdob', '{"date_of_birth": null}', 'Entered on the wrong customer');
  perform pg_temp.check(v like 'ok%' and (select date_of_birth from public.customers where id = pg_temp.id('hasdob')) is null,
                        '1e an Owner could not clear a date: ' || v);
  perform pg_temp.check((select count(*) from public.audit_logs where record_id = pg_temp.id('hasdob') and action = 'customer_updated') = 2,
                        '1e every change is one audit row');
  -- A login that is not staff, a deactivated one, and the anon key: refused.
  v := pg_temp.edit('nostaff', 'nodob', '{"notes": "x"}');
  perform pg_temp.check(v like '42501%', '1f a login with no staff profile edited a customer: ' || v);
  v := pg_temp.edit('inactive', 'nodob', '{"notes": "x"}');
  perform pg_temp.check(v like '42501%', '1f a deactivated login edited a customer: ' || v);
  v := pg_temp.edit('anon', 'nodob', '{"notes": "x"}');
  perform pg_temp.check(v like '42501%', '1f the anon key edited a customer: ' || v);
  -- The rule on its own is internal: no client may call it.
  v := pg_temp.try('owner', format('select public.assert_customer_dob_change(%L::uuid, null, ''x'')::text', pg_temp.id('nodob')));
  perform pg_temp.check(v like '42501%', '1g a signed-in login may call assert_customer_dob_change: ' || v);
  -- The server (no login) passes the role test but still needs a reason.
  v := pg_temp.try('server', format('select public.assert_customer_dob_change(%L::uuid, date ''2000-01-01'', null)::text', pg_temp.id('nodob')));
  perform pg_temp.check(v like 'P0001%A reason is required%', '1g the server changed a date without a reason: ' || v);
  v := pg_temp.try('server', format('select public.assert_customer_dob_change(%L::uuid, date ''2000-01-01'', ''Checked'')::text', pg_temp.id('nodob')));
  perform pg_temp.check(v like 'ok%', '1g the server with a reason was refused: ' || v);
  -- Called inside another function for a signed-in Inventory Manager (as the
  -- survey's Edit details will): a date that does not change passes; filling
  -- one in is refused.
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.id('invman'), 'role', 'authenticated')::text, true);
  begin
    perform public.assert_customer_dob_change(pg_temp.id('invcust'), null, null);
  exception when others then
    raise exception 'FAIL: 1h an unchanged date was refused for an Inventory Manager: %', sqlerrm;
  end;
  begin
    perform public.assert_customer_dob_change(pg_temp.id('invcust'), date '1970-01-01', null);
    raise exception 'FAIL: 1h an Inventory Manager filled in a date of birth through assert_customer_dob_change';
  exception when insufficient_privilege then
    if sqlerrm not like 'Only Owners, Managers and Staff%' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  -- It changes nothing itself.
  perform pg_temp.check((select date_of_birth from public.customers where id = pg_temp.id('nodob')) = date '1991-02-03',
                        '1g assert_customer_dob_change changed the date itself');
  raise notice 'PASS 1: staff fill in a missing date of birth; only an Owner or Manager, with a reason, changes or clears one; an Inventory Manager edits nothing, an Admin edits but keeps a filled-in date; each change is one audit row with the old and new date; the rule alone is internal';
end $$;

-- ===== 2. Every other field =====
do $$
declare v text; v_at timestamptz; v_n int;
begin
  -- Only the listed fields: is_referrer, the source and the rest are refused.
  v := pg_temp.edit('owner', 'plain', '{"is_referrer": false}');
  perform pg_temp.check(v like 'P0001%The field "is_referrer" cannot be changed here%', '2a is_referrer was accepted: ' || v);
  v := pg_temp.edit('owner', 'plain', '{"notes": "x", "source_option_id": null}');
  perform pg_temp.check(v like 'P0001%source_option_id%', '2a another field was accepted: ' || v);
  v := pg_temp.try('owner', format('select public.update_customer(%L::uuid, ''["notes"]''::jsonb)::text', pg_temp.id('plain')));
  perform pg_temp.check(v like 'P0001%list of fields%', '2a a list that is not an object was accepted: ' || v);
  -- An edit that changes nothing writes nothing.
  select updated_at into v_at from public.customers where id = pg_temp.id('plain');
  v := pg_temp.edit('staff', 'plain', '{"first_name": " T418 ", "last_name": "Plain", "phone": "+6591418004", "email": ""}');
  perform pg_temp.check(v like 'ok%"changed": []%', '2b a no-change edit changed something: ' || v);
  perform pg_temp.check((select updated_at from public.customers where id = pg_temp.id('plain')) = v_at
                        and not exists (select 1 from public.audit_logs where record_id = pg_temp.id('plain')),
                        '2b a no-change edit wrote the row or an audit entry');
  -- A name change rebuilds the whole name, and records both.
  v := pg_temp.edit('staff', 'plain', '{"first_name": "  T418  ", "last_name": "Plainer  "}');
  perform pg_temp.check(v like 'ok%' and (select full_name from public.customers where id = pg_temp.id('plain')) = 'T418 Plainer',
                        '2c the name was not saved and joined: ' || v);
  perform pg_temp.check(exists (select 1 from public.audit_logs where record_id = pg_temp.id('plain') and action = 'customer_updated'
                                  and old_data = '{"last_name": "Plain", "full_name": "T418 Plain"}'::jsonb
                                  and new_data = '{"last_name": "Plainer", "full_name": "T418 Plainer"}'::jsonb),
                        '2c the name change was not recorded old and new');
  perform pg_temp.check((select is_referrer from public.customers where id = pg_temp.id('plain')), '2c is_referrer was touched');
  v := pg_temp.edit('staff', 'plain', '{"first_name": "  "}');
  perform pg_temp.check(v like 'P0001%A first name is required%', '2c a blank first name was taken: ' || v);
  -- Gender: the description stays only beside Other.
  v := pg_temp.edit('staff', 'plain', '{"gender": "male"}');
  perform pg_temp.check(v like 'ok%' and (select gender_other from public.customers where id = pg_temp.id('plain')) is null,
                        '2d gender other was kept beside Male: ' || v);
  v := pg_temp.edit('staff', 'plain', '{"gender": "robot"}');
  perform pg_temp.check(v like 'P0001%Gender must be%', '2d an unknown gender was taken: ' || v);
  v := pg_temp.edit('staff', 'plain', '{"date_of_birth": "1990-13-40"}');
  perform pg_temp.check(v like 'P0001%not a valid date%', '2d a bad date was taken: ' || v);
  v := pg_temp.edit('staff', 'plain', '{"is_active": "no"}');
  perform pg_temp.check(v like 'P0001%Active must be true or false%', '2d a bad Active was taken: ' || v);
  v := pg_temp.edit('staff', 'plain', '{"is_active": false, "occupation": " T418 Teacher ", "email": "t418-plain@sig.invalid"}');
  perform pg_temp.check(v like 'ok%' and (select not is_active and occupation = 'T418 Teacher' from public.customers where id = pg_temp.id('plain')),
                        '2d Active and occupation were not saved: ' || v);
  -- A stale copy is refused, and nothing is saved.
  v := pg_temp.try('staff', format('select public.update_customer(%L::uuid, ''{"notes": "stale"}''::jsonb, null, %L::timestamptz)::text',
    pg_temp.id('plain'), now() - interval '1 day'));
  perform pg_temp.check(v like 'P0001%STALE_CUSTOMER%', '2e a stale edit was saved: ' || v);
  perform pg_temp.check((select notes from public.customers where id = pg_temp.id('plain')) is null, '2e the stale edit left a change');
  -- update_customer itself locks the row before it compares updated_at, so
  -- two edits at the same time cannot both pass the stale check.
  -- (assert_customer_dob_change has its own lock; this is update_customer's.)
  perform pg_temp.check(pg_get_functiondef('public.update_customer(uuid,jsonb,text,timestamptz)'::regprocedure)
                          ~ 'select \* into v_old from public\.customers c where c\.id = p_customer_id for update;',
                        '2e update_customer does not lock the customer''s row');
  -- A deleted customer is refused.
  v := pg_temp.edit('owner', 'gone', '{"notes": "x"}');
  perform pg_temp.check(v like 'P0001%has been deleted%', '2f a deleted customer was edited: ' || v);
  v := pg_temp.try('owner', format('select public.update_customer(%L::uuid, ''{}''::jsonb)::text', gen_random_uuid()));
  perform pg_temp.check(v like 'P0001%does not exist%', '2f an unknown customer: ' || v);
  raise notice 'PASS 2: only the listed fields; no change writes nothing; names, gender, Active and occupation save and are recorded; a stale or deleted customer is refused';
end $$;

-- ===== 3. Phone and referrer =====
do $$
declare v text;
begin
  v := pg_temp.edit('staff', 'phone', '{"phone": "+65 9141 8099"}');
  perform pg_temp.check(v like 'P0001%A reason is required to change a customer''s phone number%', '3a a phone changed with no reason: ' || v);
  v := pg_temp.edit('staff', 'phone', '{"phone": "+65 9141 8099"}', 'New number');
  perform pg_temp.check(v like 'ok%' and (select phone from public.customers where id = pg_temp.id('phone')) = '+6591418099',
                        '3a the phone was not saved as +65…: ' || v);
  perform pg_temp.check(exists (select 1 from public.customer_phone_history h where h.customer_id = pg_temp.id('phone')
                                  and h.phone = '+6591418010' and h.reason = 'New number' and h.changed_by = pg_temp.id('staff')),
                        '3a the old phone and the reason are not in the phone history');
  perform pg_temp.check(exists (select 1 from public.audit_logs where record_id = pg_temp.id('phone') and action = 'customer_updated'
                                  and old_data = '{"phone": "+6591418010"}'::jsonb and new_data = '{"phone": "+6591418099"}'::jsonb
                                  and reason = 'New number'), '3a the phone change was not recorded');
  -- The same number written differently is no change.
  v := pg_temp.edit('staff', 'phone', '{"phone": "+65 9141-8099"}');
  perform pg_temp.check(v like 'ok%"changed": []%', '3a the same number in another form counted as a change: ' || v);
  v := pg_temp.edit('staff', 'phone', '{"phone": ""}', 'x');
  perform pg_temp.check(v like 'P0001%Phone number is required%', '3a an empty phone was taken: ' || v);

  -- A referrer may be set when there is none, dated now.
  v := pg_temp.edit('staff', 'plain', format('{"referred_by": "%s"}', pg_temp.id('ref'))::jsonb);
  perform pg_temp.check(v like 'ok%' and (select referred_by = pg_temp.id('ref') and referred_at = now()
                                           from public.customers where id = pg_temp.id('plain')),
                        '3b a first referrer was not set and dated: ' || v);
  -- Changing or removing it is Correct Referrer's.
  v := pg_temp.edit('owner', 'plain', format('{"referred_by": "%s"}', pg_temp.id('ref2'))::jsonb);
  perform pg_temp.check(v like 'P0001%already has a referrer%', '3c a referrer was changed: ' || v);
  v := pg_temp.edit('owner', 'plain', '{"referred_by": null}');
  perform pg_temp.check(v like 'P0001%already has a referrer%', '3c a referrer was removed: ' || v);
  v := pg_temp.edit('staff', 'nodob', format('{"referred_by": "%s"}', pg_temp.id('gone'))::jsonb);
  perform pg_temp.check(v like 'P0001%not on the customer list%', '3c a deleted referrer was taken: ' || v);
  v := pg_temp.edit('staff', 'nodob', format('{"referred_by": "%s"}', pg_temp.id('nodob'))::jsonb);
  perform pg_temp.check(v like 'P0001%cannot be referred by themselves%' or v like 'P0001%their own referrer%', '3c a self-referral was taken: ' || v);
  raise notice 'PASS 3: a phone change needs a reason and goes into the phone history; a referrer may be set once, not changed here';
end $$;

-- ===== 4. The table is written by the functions only =====
do $$
declare v text; r jsonb;
begin
  v := pg_temp.try('staff', 'insert into public.customers(full_name, phone) values (''T418 Direct'', ''+6591418020'') returning id::text');
  perform pg_temp.check(v like '42501%', '4a staff still add customers to the table directly: ' || v);
  v := pg_temp.try('owner', format('with u as (update public.customers set date_of_birth = ''2001-01-01'' where id = %L returning 1) select count(*)::text from u', pg_temp.id('nodob')));
  perform pg_temp.check(v like '42501%', '4a an Owner still changes customers in the table directly: ' || v);
  v := pg_temp.try('anon', 'insert into public.customers(full_name, phone) values (''T418 Anon'', ''+6591418021'') returning id::text');
  perform pg_temp.check(v like '42501%', '4a the anon key adds customers: ' || v);
  v := pg_temp.try('staff', format('select full_name from public.customers where id = %L', pg_temp.id('nodob')));
  perform pg_temp.check(v = 'ok' || chr(9) || 'T418 Nodob', '4b staff no longer read customers: ' || v);
  perform pg_temp.check(not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customers' and cmd <> 'SELECT'),
                        '4b a write rule is still on customers');

  -- Add: create_customer_quick, as any member of staff, with no is_referrer.
  v := pg_temp.try('staff', format('select public.create_customer_quick(''T418'', ''Added'', ''+65 9141 8030'', null, ''1999-09-09'', null, null, null, null, %L::uuid, %L::uuid)::text',
    pg_temp.id('ref'), gen_random_uuid()));
  perform pg_temp.check(v like 'ok%', '4c staff could not add a customer: ' || v);
  r := split_part(v, chr(9), 2)::jsonb;
  perform pg_temp.check((select not is_referrer and referred_by = pg_temp.id('ref') and date_of_birth = '1999-09-09' and phone = '+6591418030'
                           from public.customers where id = (r->>'customer_id')::uuid), '4c the new customer is not as entered, or is marked a referrer');
  -- The history says the customer was added, not where from (the Customers
  -- page, the Invoices page and website orders all use this).
  perform pg_temp.check((select string_agg(a.action, ',') from public.audit_logs a where a.record_id = (r->>'customer_id')::uuid) = 'customer_created',
                        '4c the new customer is not recorded once as customer_created');
  -- An Inventory Manager adds no customer (the Owner, 9 Oct 2026), here or
  -- on the Invoices page; the old Admin role still does.
  v := pg_temp.try('invman', format('select public.create_customer_quick(''T418'', ''Added Two'', ''+6591418031'', null, null, null, null, null, null, null, %L::uuid)::text', gen_random_uuid()));
  perform pg_temp.check(v like '42501%Your role cannot do this%', '4c an Inventory Manager added a customer: ' || v);
  perform pg_temp.check(not exists (select 1 from public.customers where phone = '+6591418031'), '4c the refused add left a customer');
  v := pg_temp.try('admin', format('select public.create_customer_quick(''T418'', ''Added Three'', ''+6591418033'', null, null, null, null, null, null, null, %L::uuid)::text', gen_random_uuid()));
  perform pg_temp.check(v like 'ok%', '4c an Admin could not add a customer: ' || v);
  v := pg_temp.try('nostaff', format('select public.create_customer_quick(''T418'', ''Nope'', ''+6591418032'', null, null, null, null, null, null, null, %L::uuid)::text', gen_random_uuid()));
  perform pg_temp.check(v like '42501%', '4c a login with no staff profile added a customer: ' || v);
  raise notice 'PASS 4: no login writes the customers table directly; staff still read it; Add goes through create_customer_quick (not for Inventory Managers), which does not mark a referrer and records customer_created';
end $$;

-- ===== 5. "Is Referrer" in the list and the exports =====
do $$
declare v_ref boolean; v_aff boolean; v_plain boolean; v_friend boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.id('staff'), 'role', 'authenticated')::text, true);
  select s.is_referrer into v_ref from public.search_customers('T418 Referrer', null, 50, 0) s where s.id = pg_temp.id('ref');
  select s.is_referrer into v_aff from public.search_customers('T418 Affiliate', null, 50, 0) s where s.id = pg_temp.id('aff');
  select s.is_referrer into v_friend from public.search_customers('T418 Friend', null, 50, 0) s where s.id = pg_temp.id('friend');
  update public.customers set referred_by = null, is_referrer = true where id = pg_temp.id('plain');
  select s.is_referrer into v_plain from public.search_customers('T418 Plainer', null, 50, 0) s where s.id = pg_temp.id('plain');
  perform pg_temp.check(v_ref and v_aff and not v_friend and not v_plain,
    format('5 Is Referrer: referrer %s, affiliate %s, friend %s, flag only %s', v_ref, v_aff, v_friend, v_plain));
  -- A referrer whose friends are all deleted is not one.
  update public.customers set deleted_at = now() where referred_by = pg_temp.id('ref');
  select s.is_referrer into v_ref from public.search_customers('T418 Referrer', null, 50, 0) s where s.id = pg_temp.id('ref');
  perform pg_temp.check(not v_ref, '5 a deleted friend still makes a referrer');
  -- An affiliate whose affiliate record is deleted is not one either.
  update public.customer_affiliates set deleted_at = now(), status = 'soft_deleted' where customer_id = pg_temp.id('aff');
  select s.is_referrer into v_aff from public.search_customers('T418 Affiliate', null, 50, 0) s where s.id = pg_temp.id('aff');
  perform pg_temp.check(not v_aff, '5 a deleted affiliate record still makes a referrer');
  raise notice 'PASS 5: Is Referrer is has referred someone (not deleted) or is an affiliate (record not deleted), not the stored flag';
end $$;

-- ===== 6. Change phone: Owners, Managers and Staff, not Inventory Managers =====
do $$
declare v text;
begin
  v := pg_temp.try('invman', format('select public.change_customer_phone(%L::uuid, ''+6591418041'', ''New number'')::text', pg_temp.id('invcust')));
  perform pg_temp.check(v like '42501%Your role cannot do this%', '6 an Inventory Manager changed a phone: ' || v);
  perform pg_temp.check((select phone from public.customers where id = pg_temp.id('invcust')) = '+6591418003', '6 the refused change left a new phone');
  v := pg_temp.try('staff', format('select public.change_customer_phone(%L::uuid, ''+6591418041'', null)::text', pg_temp.id('invcust')));
  perform pg_temp.check(v like 'P0001%A reason is required%', '6 a phone changed with no reason: ' || v);
  v := pg_temp.try('staff', format('select public.change_customer_phone(%L::uuid, ''+65 9141 8041'', ''New number'')::text', pg_temp.id('invcust')));
  perform pg_temp.check(v like 'ok%' and (select phone from public.customers where id = pg_temp.id('invcust')) = '+6591418041',
                        '6 staff could not change a phone: ' || v);
  v := pg_temp.try('admin', format('select public.change_customer_phone(%L::uuid, ''+6591418042'', ''New number'')::text', pg_temp.id('invcust')));
  perform pg_temp.check(v like 'ok%', '6 an Admin could not change a phone: ' || v);
  v := pg_temp.try('nostaff', format('select public.change_customer_phone(%L::uuid, ''+6591418043'', ''x'')::text', pg_temp.id('invcust')));
  perform pg_temp.check(v like '42501%', '6 a login with no staff profile changed a phone: ' || v);
  v := pg_temp.try('server', format('select public.change_customer_phone(%L::uuid, ''+6591418043'', ''x'')::text', pg_temp.id('invcust')));
  perform pg_temp.check(v like 'P0001%Not authorized%', '6 the server, with no login, changed a phone: ' || v);
  raise notice 'PASS 6: Change phone is for Owners, Managers, Staff and Admins with a reason; an Inventory Manager, a login with no staff profile and the server with no login are refused';
end $$;

rollback;
