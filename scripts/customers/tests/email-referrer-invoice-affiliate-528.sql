-- A customer's email needs a reason, and an affiliate's or a portal login's an Owner or
-- Manager; Staff add a referrer only on the day the customer is made; only an Owner or Manager
-- changes the affiliate on an invoice already made (528; security audit of 17 Nov 2026, M11;
-- the user, 19 Nov 2026).
--
-- Every call is made as the page makes it: a signed-in login (the API role authenticated, with
-- its JWT), through update_customer (Edit on the Customers page), update_survey_particulars_v2
-- (Edit details on a health survey), create_customer_quick (Add), create_invoice_with_details
-- (New Invoice), set_invoice_affiliate (the Affiliate box of the invoice view) and
-- reassign_customer_referrer (Correct Referrer). The logins: an Owner, a Manager, Staff, the old
-- Admin role, an Inventory Manager, and a login with no staff profile.
--
--   H  customer_is_affiliate_or_portal_login: an affiliate (a customer_affiliates row not
--      deleted, active or suspended) or a portal login (an affiliate_accounts row, claimed or
--      disabled) is one; a plain customer, or one whose affiliate record is deleted, is not.
--      Staff may ask it; a login with no staff profile and the anon key may not.
--   E  update_customer's email: every change (added, changed, removed) needs a reason, kept in
--      its audit row; an unchanged email sent again needs none. Staff and the old Admin role
--      change a plain customer's; an affiliate's or a portal login's they may not (42501),
--      reason or not, and nothing is written; an Owner or Manager may, with a reason. Other
--      fields of an affiliate stay Staff's. An Inventory Manager edits nothing, as before.
--   S  update_survey_particulars_v2: a survey's new email that goes onto its customer follows
--      the same rule; a survey with no customer, or an email the customer has already, does not.
--   R  update_customer's referrer: Staff add one to a customer made today (Singapore date: one
--      made at 00:01 today, which is yesterday in UTC, too), not to one made before today
--      (23:59 yesterday included), nor does the old Admin role; an Owner or Manager adds one to
--      any. Changing one stays refused (Correct Referrer, Owner/Manager); Add with a referrer
--      stays Staff's.
--   I  set_invoice_affiliate: Staff, the old Admin role, an Inventory Manager and a login with
--      no profile are refused (42501), the invoice and its history unchanged; a Manager and an
--      Owner change it, with its revision and audit rows. New Invoice with an affiliate by Staff
--      still works, and none of the three invoice makers calls set_invoice_affiliate.
--   C  correct_invoice (the user, 19 Nov 2026: "Owner/Manager for every change"): in Edit
--      Invoice on an unpaid invoice and in a correction of a paid one (377), Staff (and the old
--      Admin role) may not change the affiliate, to another or to none; nothing is written. The
--      affiliate the invoice has, sent again, is no change; Staff still correct a paid invoice
--      when they leave it alone; a Manager and an Owner change it.
--   G  528's AFTER md5s, the new function's, the grants (unchanged; the new one: signed-in
--      logins and the service role), the relied-on functions unchanged.
--   U  scripts/customers/undo-528.sql puts the four functions back (their BEFORE md5s and
--      grants) and drops the new one; 528 again makes them as 528 did.
--   M  528 a second time changes nothing (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (@example.invalid); phones are the fictional +61 491 570 ... range. Run it on a copy of
-- production as it is (after 527): it applies 528 twice; with -v skip_install=1 where 528 is
-- already in; with -v control=1 on a copy WITHOUT 528 (it does not install it, skips G, U and
-- M, and fails on exactly the checks 528 makes pass; see the end of this file). Every check
-- runs, then the file fails if any did.
\set ON_ERROR_STOP on
begin;
\if :{?control}
do $$ begin
  if position('-- 528 (security audit' in pg_get_functiondef('public.update_customer(uuid,jsonb,text,timestamptz)'::regprocedure)) > 0 then
    raise exception 'control: 528 is in on this copy; run -v control=1 on a copy without it'; end if;
end $$;
\elif :{?skip_install}
\else
\ir ../../../supabase/528_email_referrer_and_invoice_affiliate_need_owner_or_manager.sql
create temp table m528 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
\ir ../../../supabase/528_email_referrer_and_invoice_affiliate_need_owner_or_manager.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create temp table tx(k text primary key, v text);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
-- Fictional phones: +61 491 570 nnn, one block per run.
create function pg_temp.ph(n int) returns text language sql as
$$ select '+61491570' || lpad(((pg_temp.tx('phbase')::int + n) % 1000)::text, 3, '0') $$;
create function pg_temp.mail(key text) returns text language sql as
$$ select 'm528-' || lower(key) || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;

-- Run p_sql as p_who and say what happened: 'ok' and the result, or the SQLSTATE and the
-- message. p_who is a login key (the API role authenticated, as a signed-in browser) or 'anon'.
create function pg_temp.try(p_who text, p_sql text) returns text language plpgsql as $f$
declare v_out text; v_state text; v_msg text;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    if p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.fx('u:' || p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v_out;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    perform set_config('request.jwt.claims', '', true);
    return v_state || chr(9) || v_msg;
  end;
end $f$;
-- update_customer as p_who, with the customer's updated_at as read now (as the page sends it).
create function pg_temp.edit(p_who text, p_key text, p_changes jsonb, p_reason text default null) returns text language plpgsql as $f$
declare v_at timestamptz;
begin
  select updated_at into v_at from public.customers where id = pg_temp.fx('c:' || p_key);
  return pg_temp.try(p_who, format('select public.update_customer(%L::uuid, %L::jsonb, %L, %L::timestamptz)::text',
    pg_temp.fx('c:' || p_key), p_changes, p_reason, v_at));
end $f$;
create function pg_temp.survey(p_who text, p_key text, p_changes jsonb, p_reason text default null) returns text language sql as $f$
  select pg_temp.try(p_who, format('select public.update_survey_particulars_v2(%L::uuid, %L::jsonb, %L)::text',
    pg_temp.fx('s:' || p_key), p_changes, p_reason)) $f$;
create function pg_temp.set_aff(p_who text, p_aff text) returns text language sql as $f$
  select pg_temp.try(p_who, format('select public.set_invoice_affiliate(%L::uuid, %L::uuid)::text',
    pg_temp.fx('i:staff'), case when p_aff is not null then pg_temp.fx('a:' || p_aff) end)) $f$;
create function pg_temp.helper(p_who text, p_key text) returns text language sql as $f$
  select pg_temp.try(p_who, format('select public.customer_is_affiliate_or_portal_login(%L::uuid)::text', pg_temp.fx('c:' || p_key))) $f$;
create function pg_temp.email_of(p_key text) returns text language sql as $f$
  select email from public.customers where id = pg_temp.fx('c:' || p_key) $f$;
create function pg_temp.ref_of(p_key text) returns uuid language sql as $f$
  select referred_by from public.customers where id = pg_temp.fx('c:' || p_key) $f$;
-- The customer_updated audit rows of a customer (by whom, reason, the email or referrer before and after).
create function pg_temp.audits(p_key text) returns text language sql as $f$
  select coalesce(string_agg(concat_ws('|', (select k from fx where v = l.changed_by and k like 'u:%'), coalesce(l.reason, '-'),
                                       coalesce(l.old_data ->> 'email', '-'), coalesce(l.new_data ->> 'email', '-'),
                                       case when l.new_data ? 'referred_by' then 'ref' end), ' ' order by l.created_at, l.id), '-')
    from public.audit_logs l where l.record_id = pg_temp.fx('c:' || p_key) and l.action = 'customer_updated' $f$;
-- 'ok' or the SQLSTATE, then the message's start (enough to compare).
create function pg_temp.is(p_out text, p_want text) returns boolean language sql as $f$
  select p_out like p_want $f$;

-- ═════ Fixtures ═════
-- The logins (an Owner, a Manager, Staff, the old Admin role, an Inventory Manager, a login with
-- no staff profile, two portal logins), a store they all work at, a S$100 product, the customers.
do $$
declare w text; v uuid; st uuid; p uuid; a uuid; d0 timestamptz;
begin
  perform set_config('request.jwt.claims', '', true);
  insert into tx values ('sfx', lower(substr(md5(gen_random_uuid()::text), 1, 6))),
                        ('phbase', (floor(random() * 900))::int::text);
  foreach w in array array['owner', 'manager', 'staff', 'admin', 'invman', 'nostaff', 'portal1', 'portal2'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), pg_temp.mail('login-' || w)) returning id into v;
    insert into fx values ('u:' || w, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active)
  select pg_temp.fx('u:' || x.k), 'M528 ' || x.k, pg_temp.mail('login-' || x.k), x.role::public.user_role, true
    from (values ('owner', 'owner'), ('manager', 'manager'), ('staff', 'staff'), ('admin', 'admin'),
                 ('invman', 'inventory_manager')) x(k, role);
  insert into public.stores(name, code, country_code) values ('M528 Store', 'M528' || upper(substr(pg_temp.tx('sfx'), 1, 3)), 'SG') returning id into st;
  insert into fx values ('st', st);
  insert into public.user_store_assignments(user_id, store_id)
  select pg_temp.fx('u:' || r.login), st from unnest(array['owner', 'manager', 'staff', 'admin', 'invman']) r(login);
  perform set_config('request.jwt.claim.sub', pg_temp.fx('u:owner')::text, true);
  insert into public.products(name, sku, product_type) values ('M528 Item', 'M528-' || pg_temp.tx('sfx'), 'own') returning id into p;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 50);
  perform public.set_product_prices(st, p, 100, 100, 'available');
  perform set_config('request.jwt.claim.sub', '', true);
  insert into fx values ('p', p);

  -- The customers (their emails and the day they were made below).
  d0 := (public.sg_today()::timestamp) at time zone 'Asia/Singapore';  -- 00:00 today in Singapore
  foreach w in array array['plain', 'plain2', 'plainadm', 'aff', 'affsus', 'affdel', 'portal', 'portaldis', 'ref', 'ref2',
                           'today', 'old', 'oldadm', 'oldmgr', 'oldown', 'sgmid', 'sgyest', 'hasref', 'buyer', 'splain', 'saff'] loop
    insert into public.customers(full_name, first_name, last_name, phone, email, created_at)
    values ('M528 ' || w, 'M528', w, pg_temp.ph((select count(*) from fx where fx.k like 'c:%')::int),
            case when w in ('plain2', 'aff', 'affsus', 'affdel', 'portal', 'portaldis', 'splain', 'saff') then pg_temp.mail(w) end,
            case when w in ('old', 'oldadm', 'oldmgr', 'oldown') then now() - interval '2 days'
                 when w = 'sgmid' then d0 + interval '1 minute'      -- 00:01 today in Singapore: yesterday in UTC
                 when w = 'sgyest' then d0 - interval '1 minute'     -- 23:59 yesterday in Singapore
                 else now() end)
    returning id into v;
    insert into fx values ('c:' || w, v);
  end loop;
  update public.customers set referred_by = pg_temp.fx('c:ref') where id = pg_temp.fx('c:hasref');
  -- The affiliates (active, suspended, deleted), and the portal logins (claimed, disabled) with no affiliate record.
  foreach w in array array['aff', 'affsus', 'affdel', 'ref', 'ref2', 'saff'] loop
    insert into public.customer_affiliates(customer_id, status, store_id, activated_at, deleted_at)
    values (pg_temp.fx('c:' || w), case when w = 'affsus' then 'suspended_manual' else 'active' end, st, now(),
            case when w = 'affdel' then now() end)
    returning id into a;
    insert into fx values ('a:' || w, a);
  end loop;
  insert into public.affiliate_accounts(auth_user_id, customer_id, status)
  values (pg_temp.fx('u:portal1'), pg_temp.fx('c:portal'), 'claimed'), (pg_temp.fx('u:portal2'), pg_temp.fx('c:portaldis'), 'disabled');
  -- Two health surveys with a customer (a plain one, an affiliate), one with none.
  insert into public.health_surveys(survey_no, customer_id, full_name, first_name, phone, email)
  values ('M528-S1-' || pg_temp.tx('sfx'), pg_temp.fx('c:splain'), 'M528 splain', 'M528', pg_temp.ph(100), pg_temp.mail('splain'))
  returning id into v;
  insert into fx values ('s:plain', v);
  insert into public.health_surveys(survey_no, customer_id, full_name, first_name, phone, email)
  values ('M528-S2-' || pg_temp.tx('sfx'), pg_temp.fx('c:saff'), 'M528 saff', 'M528', pg_temp.ph(101), pg_temp.mail('saff'))
  returning id into v;
  insert into fx values ('s:aff', v);
  insert into public.health_surveys(survey_no, customer_id, full_name, first_name, phone, email)
  values ('M528-S3-' || pg_temp.tx('sfx'), null, 'M528 nocust', 'M528', pg_temp.ph(102), null)
  returning id into v;
  insert into fx values ('s:nocust', v);
end $$;

-- ═════ H The helper ═════
select pg_temp.check(pg_temp.helper('owner', 'plain') = E'ok\tfalse' and pg_temp.helper('owner', 'affdel') = E'ok\tfalse'
    and pg_temp.helper('staff', 'aff') = E'ok\ttrue' and pg_temp.helper('staff', 'affsus') = E'ok\ttrue'
    and pg_temp.helper('staff', 'portal') = E'ok\ttrue' and pg_temp.helper('staff', 'portaldis') = E'ok\ttrue'
    and pg_temp.helper('invman', 'aff') = E'ok\ttrue',
  'H1 an affiliate (active or suspended) or a portal login (claimed or disabled) is one; a plain customer or a deleted affiliate record is not: '
  || concat_ws(' ', pg_temp.helper('owner', 'plain'), pg_temp.helper('staff', 'aff'), pg_temp.helper('staff', 'portaldis')));
select pg_temp.check(pg_temp.is(pg_temp.helper('nostaff', 'aff'), E'42501\t%') and pg_temp.is(pg_temp.helper('anon', 'aff'), E'42501\t%'),
  'H2 a login with no staff profile and the anon key may not ask it: '
  || concat_ws(' ', pg_temp.helper('nostaff', 'aff'), pg_temp.helper('anon', 'aff')));

-- ═════ E update_customer: the email ═════
-- (Each call is made, in order, before what it is checked against is read.)
do $$
declare v text; v2 text; v3 text;
begin
  v := pg_temp.edit('staff', 'plain', jsonb_build_object('email', pg_temp.mail('plain-new')));
  perform pg_temp.check(pg_temp.is(v, E'P0001\tA reason is required to change a customer''s email') and pg_temp.email_of('plain') is null,
    'E1 Staff adding an email with no reason is refused, and nothing is saved: ' || v);
  v := pg_temp.edit('staff', 'plain', jsonb_build_object('email', pg_temp.mail('plain-new')), 'Customer gave it at the counter');
  perform pg_temp.check(v like E'ok\t%' and pg_temp.email_of('plain') = pg_temp.mail('plain-new')
      and pg_temp.audits('plain') = 'u:staff|Customer gave it at the counter|-|' || pg_temp.mail('plain-new'),
    'E2 Staff change a plain customer''s email with a reason; the audit row holds the reason and the old and new email: ' || pg_temp.audits('plain'));
  v := pg_temp.edit('staff', 'plain2', '{"email": null}');
  v2 := pg_temp.edit('staff', 'plain2', jsonb_build_object('email', pg_temp.mail('plain2'), 'notes', 'M528 note'));
  perform pg_temp.check(pg_temp.is(v, E'P0001\tA reason is required to change a customer''s email')
      and pg_temp.email_of('plain2') = pg_temp.mail('plain2') and v2 like E'ok\t%"changed": ["notes"]%',
    'E3 removing an email needs a reason too; the same email sent again with another change needs none: ' || v || ' / ' || v2);
  v := pg_temp.edit('staff', 'aff', jsonb_build_object('email', pg_temp.mail('aff-new')), 'Asked by phone');
  perform pg_temp.check(pg_temp.is(v, E'42501\tOnly an Owner or Manager can change the email of an affiliate or a customer with a portal login')
      and pg_temp.email_of('aff') = pg_temp.mail('aff') and pg_temp.audits('aff') = '-',
    'E4 Staff may not change an affiliate''s email, even with a reason; nothing is saved or written: ' || v);
  v := pg_temp.edit('staff', 'affsus', jsonb_build_object('email', pg_temp.mail('x1')), 'r');
  v2 := pg_temp.edit('staff', 'portal', jsonb_build_object('email', pg_temp.mail('x2')), 'r');
  v3 := pg_temp.edit('staff', 'portaldis', '{"email": null}', 'r');
  perform pg_temp.check(pg_temp.is(v, E'42501\tOnly an Owner or Manager%') and pg_temp.is(v2, E'42501\tOnly an Owner or Manager%')
      and pg_temp.is(v3, E'42501\tOnly an Owner or Manager%')
      and pg_temp.email_of('affsus') = pg_temp.mail('affsus') and pg_temp.email_of('portal') = pg_temp.mail('portal')
      and pg_temp.email_of('portaldis') = pg_temp.mail('portaldis'),
    'E5 nor a suspended affiliate''s, a claimed portal login''s or a disabled one''s (removing it included): ' || concat_ws(' / ', v, v2, v3));
  v := pg_temp.edit('staff', 'affdel', jsonb_build_object('email', pg_temp.mail('affdel-new')), 'New inbox');
  perform pg_temp.check(v like E'ok\t%' and pg_temp.email_of('affdel') = pg_temp.mail('affdel-new'),
    'E5b a customer whose affiliate record is deleted (and who has no portal login) is a plain customer: ' || v);
  v := pg_temp.edit('admin', 'aff', jsonb_build_object('email', pg_temp.mail('x3')), 'r');
  v2 := pg_temp.edit('admin', 'plainadm', jsonb_build_object('email', pg_temp.mail('plainadm')), 'Typed in');
  v3 := pg_temp.edit('admin', 'plainadm', '{"email": null}');
  perform pg_temp.check(pg_temp.is(v, E'42501\tOnly an Owner or Manager%') and v2 like E'ok\t%' and pg_temp.is(v3, E'P0001\tA reason is required%'),
    'E6 the old Admin role is not an Owner or Manager: as Staff (a plain customer''s with a reason; not an affiliate''s): ' || concat_ws(' / ', v, v2, v3));
  v := pg_temp.edit('manager', 'aff', jsonb_build_object('email', pg_temp.mail('aff-new')));
  v2 := pg_temp.edit('manager', 'aff', jsonb_build_object('email', pg_temp.mail('aff-new')), 'Affiliate lost the old inbox');
  v3 := pg_temp.edit('owner', 'portal', jsonb_build_object('email', pg_temp.mail('portal-new')), 'Owner checked ID');
  perform pg_temp.check(pg_temp.is(v, E'P0001\tA reason is required to change a customer''s email') and v2 like E'ok\t%' and v3 like E'ok\t%'
      and pg_temp.audits('aff') = 'u:manager|Affiliate lost the old inbox|' || pg_temp.mail('aff') || '|' || pg_temp.mail('aff-new')
      and pg_temp.email_of('portal') = pg_temp.mail('portal-new'),
    'E7 a Manager and an Owner change an affiliate''s or a portal login''s email, with a reason only: ' || pg_temp.audits('aff'));
  v := pg_temp.edit('invman', 'plain', jsonb_build_object('email', pg_temp.mail('x4')), 'r');
  v2 := pg_temp.edit('nostaff', 'plain', jsonb_build_object('email', pg_temp.mail('x5')), 'r');
  perform pg_temp.check(pg_temp.is(v, E'42501\tYour role cannot do this.') and pg_temp.is(v2, E'42501\t%'),
    'E8 an Inventory Manager and a login with no staff profile edit no customer, as before: ' || v || ' / ' || v2);
  v := pg_temp.edit('staff', 'affsus', '{"notes": "M528 staff note", "occupation": "M528 Nurse"}');
  perform pg_temp.check(v like E'ok\t%' and (select notes = 'M528 staff note' from public.customers where id = pg_temp.fx('c:affsus')),
    'E9 Staff still edit an affiliate''s other details (no reason needed): ' || v);
end $$;

-- ═════ S update_survey_particulars_v2: the email the customer gets ═════
do $$
declare v text; v2 text;
begin
  v := pg_temp.survey('staff', 'plain', jsonb_build_object('email', pg_temp.mail('splain-new')));
  perform pg_temp.check(pg_temp.is(v, E'P0001\tA reason is required to change a customer''s email') and pg_temp.email_of('splain') = pg_temp.mail('splain'),
    'S1 a survey''s new email for its customer needs a reason: ' || v);
  v := pg_temp.survey('staff', 'plain', jsonb_build_object('email', pg_temp.mail('splain-new')), 'Typo on the form');
  perform pg_temp.check(v like E'ok\t%' and pg_temp.email_of('splain') = pg_temp.mail('splain-new')
      and exists (select 1 from public.audit_logs l where l.record_id = pg_temp.fx('s:plain') and l.action = 'survey_particulars_edited'
                     and l.reason = 'Typo on the form' and l.new_data -> 'customer' ->> 'email' = pg_temp.mail('splain-new')),
    'S2 with a reason Staff change a plain customer''s email from the survey; the audit row holds the reason: ' || v);
  v := pg_temp.survey('staff', 'aff', jsonb_build_object('email', pg_temp.mail('saff-new')), 'r');
  perform pg_temp.check(pg_temp.is(v, E'42501\tOnly an Owner or Manager%') and pg_temp.email_of('saff') = pg_temp.mail('saff')
      and (select email from public.health_surveys where id = pg_temp.fx('s:aff')) = pg_temp.mail('saff'),
    'S3 Staff may not change an affiliate''s email from the survey; neither the survey nor the customer changes: ' || v);
  v := pg_temp.survey('manager', 'aff', jsonb_build_object('email', pg_temp.mail('saff-new')), 'Checked with the affiliate');
  perform pg_temp.check(v like E'ok\t%' and pg_temp.email_of('saff') = pg_temp.mail('saff-new'), 'S4 a Manager may, with a reason: ' || v);
  -- The survey's email set to the one its customer has already (the customer's own Edit changed it).
  update public.customers set email = pg_temp.mail('splain-same') where id = pg_temp.fx('c:splain');
  v := pg_temp.survey('staff', 'nocust', jsonb_build_object('email', pg_temp.mail('nocust')));
  v2 := pg_temp.survey('staff', 'plain', jsonb_build_object('email', pg_temp.mail('splain-same'), 'occupation', 'M528 Chef'));
  perform pg_temp.check(v like E'ok\t%' and v2 like E'ok\t%' and v2 like '%"customer_changed": ["occupation"]%',
    'S5 no reason when no customer''s email changes (a survey with no customer; an email the customer has already): ' || v || ' / ' || v2);
end $$;

-- ═════ R update_customer: the referrer ═════
do $$
declare v text; v2 text; v3 text; v4 text;
begin
  v := pg_temp.edit('staff', 'today', jsonb_build_object('referred_by', pg_temp.fx('c:ref')));
  perform pg_temp.check(v like E'ok\t%' and pg_temp.ref_of('today') = pg_temp.fx('c:ref') and pg_temp.audits('today') = 'u:staff|-|-|-|ref',
    'R1 Staff add a referrer to a customer made today (no reason), recorded: ' || v || ' ' || pg_temp.audits('today'));
  v := pg_temp.edit('staff', 'old', jsonb_build_object('referred_by', pg_temp.fx('c:ref')));
  v2 := pg_temp.edit('admin', 'oldadm', jsonb_build_object('referred_by', pg_temp.fx('c:ref')));
  perform pg_temp.check(pg_temp.is(v, E'42501\tOnly an Owner or Manager can add a referrer to a customer created before today. Use Correct Referrer.')
      and pg_temp.is(v2, E'42501\tOnly an Owner or Manager can add a referrer%')
      and pg_temp.ref_of('old') is null and pg_temp.audits('old') = '-' and pg_temp.ref_of('oldadm') is null,
    'R2 Staff and the old Admin role may not add one to a customer made before today; nothing is saved: ' || v || ' / ' || v2);
  v := pg_temp.edit('manager', 'oldmgr', jsonb_build_object('referred_by', pg_temp.fx('c:ref')));
  v2 := pg_temp.edit('owner', 'oldown', jsonb_build_object('referred_by', pg_temp.fx('c:ref2')));
  perform pg_temp.check(v like E'ok\t%' and v2 like E'ok\t%'
      and pg_temp.ref_of('oldmgr') = pg_temp.fx('c:ref') and pg_temp.ref_of('oldown') = pg_temp.fx('c:ref2'),
    'R3 a Manager and an Owner add one to a customer made before today: ' || v || ' / ' || v2);
  v := pg_temp.edit('staff', 'sgmid', jsonb_build_object('referred_by', pg_temp.fx('c:ref')));
  v2 := pg_temp.edit('staff', 'sgyest', jsonb_build_object('referred_by', pg_temp.fx('c:ref')));
  perform pg_temp.check(v like E'ok\t%' and pg_temp.is(v2, E'42501\tOnly an Owner or Manager can add a referrer%')
      and ((select created_at from public.customers where id = pg_temp.fx('c:sgmid')) at time zone 'UTC')::date < public.sg_today(),
    'R4 the day is Singapore''s: made at 00:01 today (yesterday in UTC) Staff may; made at 23:59 yesterday they may not: ' || v || ' / ' || v2);
  v := pg_temp.edit('owner', 'hasref', jsonb_build_object('referred_by', pg_temp.fx('c:ref2')));
  v2 := pg_temp.edit('owner', 'hasref', '{"referred_by": null}');
  v3 := pg_temp.edit('staff', 'hasref', jsonb_build_object('referred_by', pg_temp.fx('c:ref'), 'notes', 'M528'));
  v4 := pg_temp.try('staff', format('select public.reassign_customer_referrer(%L::uuid, %L::uuid, %L)::text',
                                    pg_temp.fx('c:hasref'), pg_temp.fx('c:ref2'), 'r'));
  perform pg_temp.check(pg_temp.is(v, E'P0001\tThis customer already has a referrer%') and pg_temp.is(v2, E'P0001\tThis customer already has a referrer%')
      and v3 like E'ok\t%"changed": ["notes"]%' and pg_temp.is(v4, E'P0001\tOnly Owner or Manager can correct a referrer')
      and pg_temp.ref_of('hasref') = pg_temp.fx('c:ref'),
    'R5 changing or removing a referrer is refused here as before (Correct Referrer, Owner/Manager); the same one sent again is no change: '
    || concat_ws(' / ', v, v2, v3, v4));
  v := pg_temp.try('staff', format('select public.create_customer_quick(%L, %L, %L, %L, null, null, null, null, null, %L::uuid, %L::uuid)::text',
                                  'M528', 'Added', pg_temp.ph(200), pg_temp.mail('added'), pg_temp.fx('c:ref'), gen_random_uuid()));
  perform pg_temp.check(v like E'ok\t%'
      and exists (select 1 from public.customers c where c.phone = pg_temp.ph(200) and c.referred_by = pg_temp.fx('c:ref')
                     and c.email = pg_temp.mail('added')),
    'R6 Add (create_customer_quick) by Staff with a referrer and an email works as before: ' || v);
end $$;

-- ═════ I set_invoice_affiliate ═════
do $$
declare v text; v2 text; v3 text; v4 text; v5 text; v6 text;
begin
  v := pg_temp.try('staff', format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
    pg_temp.fx('st'), pg_temp.fx('c:buyer'),
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('p'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today(), 'affiliate_id', pg_temp.fx('a:aff'))));
  if v like E'ok\t%' then insert into fx values ('i:staff', split_part(v, chr(9), 2)::uuid); end if;
  perform pg_temp.check(v like E'ok\t%'
      and (select affiliate_id = pg_temp.fx('a:aff') and status = 'unpaid' and created_by = pg_temp.fx('u:staff')
             from public.invoices where id = pg_temp.fx('i:staff')),
    'I1 Staff make a New Invoice with an affiliate chosen, as before: ' || v);
  perform pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                                      and p.proname in ('create_invoice_with_details', 'create_invoice', 'create_split_credit_package_invoices',
                                                        'create_split_premium_bundle_invoices')
                                      and p.prosrc like '%set_invoice_affiliate%'),
    'I2 none of the invoice makers calls set_invoice_affiliate (choosing it while making stays Staff''s)');
  v := pg_temp.set_aff('staff', 'ref');
  v2 := pg_temp.set_aff('staff', null);
  v3 := pg_temp.set_aff('staff', 'aff');
  v4 := pg_temp.set_aff('admin', 'ref');
  v5 := pg_temp.set_aff('invman', 'ref');
  v6 := pg_temp.set_aff('nostaff', 'ref');
  perform pg_temp.check(pg_temp.is(v, E'42501\tOnly an Owner or Manager can change the affiliate on an invoice after it is made')
      and pg_temp.is(v2, E'42501\tOnly an Owner or Manager%') and pg_temp.is(v3, E'42501\tOnly an Owner or Manager%')
      and pg_temp.is(v4, E'42501\tOnly an Owner or Manager%') and pg_temp.is(v5, E'42501\tOnly an Owner or Manager%')
      and pg_temp.is(v6, E'42501\tOnly an Owner or Manager%')
      and (select affiliate_id = pg_temp.fx('a:aff') and coalesce(edit_count, 0) = 0 from public.invoices where id = pg_temp.fx('i:staff'))
      and not exists (select 1 from public.invoice_revisions where invoice_id = pg_temp.fx('i:staff'))
      and not exists (select 1 from public.audit_logs where record_id = pg_temp.fx('i:staff') and action = 'invoice_affiliate_set'),
    'I3 Staff (changing, clearing, the same one), the old Admin role, an Inventory Manager and a login with no profile are refused; nothing written: '
    || concat_ws(' / ', v, v2, v3, v4, v5, v6));
  v := pg_temp.set_aff('manager', 'ref');
  perform pg_temp.check(v like E'ok\t%'
      and (select affiliate_id = pg_temp.fx('a:ref') from public.invoices where id = pg_temp.fx('i:staff'))
      and exists (select 1 from public.audit_logs where record_id = pg_temp.fx('i:staff') and action = 'invoice_affiliate_set'
                     and changed_by = pg_temp.fx('u:manager') and new_data ->> 'affiliate_id' = pg_temp.fx('a:ref')::text),
    'I4 a Manager changes it, with its revision and audit rows: ' || v);
  v := pg_temp.set_aff('owner', null);
  perform pg_temp.check(v like E'ok\t%' and (select affiliate_id is null from public.invoices where id = pg_temp.fx('i:staff'))
      and (select count(*) from public.invoice_revisions where invoice_id = pg_temp.fx('i:staff')) = 2,
    'I4b an Owner clears it, with its revision row: ' || v);
  v := pg_temp.set_aff('manager', 'affsus');
  perform pg_temp.check(pg_temp.is(v, E'P0001\tThat affiliate is not active and cannot be selected'),
    'I5 an Owner''s or Manager''s choice is still checked as before (an affiliate not active is refused): ' || v);
end $$;

-- ═════ C correct_invoice: the affiliate in a correction (the user, 19 Nov 2026: "Owner/Manager for every change") ═════
-- The invoice's lines as the correction form sends them back (each saved line with its id and price).
create function pg_temp.lines(inv uuid) returns jsonb language sql as
$$ select jsonb_agg(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text, 'product_id', product_id,
                                       'quantity', quantity, 'unit_price', unit_price) order by id)
     from public.invoice_items where invoice_id = inv $$;
create function pg_temp.correct(p_who text, p_inv text, p_header jsonb, p_reason text default null) returns text language sql as $f$
  select pg_temp.try(p_who, format('select public.correct_invoice(%L::uuid, %L::jsonb, %L::jsonb, %L, %L::uuid)::text',
    pg_temp.fx('i:' || p_inv), pg_temp.lines(pg_temp.fx('i:' || p_inv)), p_header, p_reason, gen_random_uuid())) $f$;
create function pg_temp.aff_of(p_inv text) returns text language sql as $f$
  select coalesce((select k from fx where v = i.affiliate_id and k like 'a:%'), 'none') || '|' || i.affiliate_selection_explicit
    from public.invoices i where i.id = pg_temp.fx('i:' || p_inv) $f$;
do $$
declare v text; v2 text; v3 text; m uuid; inv uuid; n0 int; e0 int;
begin
  -- Two more sales made by Staff: one left unpaid with an affiliate chosen, one paid in full
  -- (in cash, recorded by the Owner) with none.
  foreach v in array array['cunpaid', 'cpaid'] loop
    v2 := pg_temp.try('staff', format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
      pg_temp.fx('st'), pg_temp.fx('c:buyer'),
      jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('p'), 'quantity', 1)),
      jsonb_build_object('business_date', public.sg_today()) || case when v = 'cunpaid' then jsonb_build_object('affiliate_id', pg_temp.fx('a:aff')) else '{}' end));
    insert into fx values ('i:' || v, split_part(v2, chr(9), 2)::uuid);
  end loop;
  insert into public.payment_methods(name, is_active) values ('M528 Cash ' || pg_temp.tx('sfx'), true) returning id into m;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('u:owner')::text, true);
  perform public.pay_invoice(pg_temp.fx('i:cpaid'), jsonb_build_array(jsonb_build_object('payment_method_id', m, 'amount', 100)));
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.check((select status::text from public.invoices where id = pg_temp.fx('i:cpaid')) = 'paid'
      and pg_temp.aff_of('cunpaid') = 'a:aff|false',
    'C0 fixture: an unpaid invoice with an affiliate chosen at New Invoice, and a paid one with none: ' || pg_temp.aff_of('cunpaid'));

  select count(*) into n0 from public.invoice_revisions where invoice_id = pg_temp.fx('i:cunpaid');
  select coalesce(edit_count, 0) into e0 from public.invoices where id = pg_temp.fx('i:cunpaid');
  v := pg_temp.correct('staff', 'cunpaid', jsonb_build_object('affiliate_id', pg_temp.fx('a:ref')));
  v2 := pg_temp.correct('staff', 'cunpaid', jsonb_build_object('affiliate_id', ''));
  v3 := pg_temp.correct('admin', 'cunpaid', jsonb_build_object('affiliate_id', pg_temp.fx('a:ref')));
  perform pg_temp.check(pg_temp.is(v, E'42501\tOnly an Owner or Manager can change the affiliate on an invoice after it is made')
      and pg_temp.is(v2, E'42501\tOnly an Owner or Manager can change the affiliate%')
      and pg_temp.is(v3, E'42501\tOnly an Owner or Manager can change the affiliate%')
      and pg_temp.aff_of('cunpaid') = 'a:aff|false'
      and (select count(*) from public.invoice_revisions where invoice_id = pg_temp.fx('i:cunpaid')) = n0
      and (select coalesce(edit_count, 0) from public.invoices where id = pg_temp.fx('i:cunpaid')) = e0,
    'C1 Edit Invoice on an unpaid invoice: Staff and the old Admin role may not change the affiliate (another, or none); nothing written: '
    || concat_ws(' / ', v, v2, v3));
  v := pg_temp.correct('staff', 'cunpaid', jsonb_build_object('affiliate_id', pg_temp.fx('a:aff'), 'notes', 'M528 note'));
  perform pg_temp.check(v like E'ok\t%' and (select notes from public.invoices where id = pg_temp.fx('i:cunpaid')) = 'M528 note'
      and pg_temp.aff_of('cunpaid') like 'a:aff|%',
    'C2 the affiliate the invoice has, sent again with another change, is no change: Staff save it: ' || left(v, 80));

  v := pg_temp.correct('staff', 'cpaid', jsonb_build_object('affiliate_id', pg_temp.fx('a:ref')), 'Referrer missed at the till');
  v2 := pg_temp.correct('staff', 'cpaid', jsonb_build_object('affiliate_id', null), 'No affiliate');
  perform pg_temp.check(pg_temp.is(v, E'42501\tOnly an Owner or Manager can change the affiliate on an invoice after it is made')
      and pg_temp.is(v2, E'42501\tOnly an Owner or Manager can change the affiliate%')
      and pg_temp.aff_of('cpaid') = 'none|false'
      and not exists (select 1 from public.invoice_revisions where invoice_id = pg_temp.fx('i:cpaid')),
    'C3 a paid invoice Staff may correct (377): they may not add an affiliate, nor set none; nothing written: ' || v || ' / ' || v2);
  v := pg_temp.correct('staff', 'cpaid', jsonb_build_object('notes', 'M528 corrected by Staff'), 'Note added');
  perform pg_temp.check(v like E'ok\t%' and (select notes from public.invoices where id = pg_temp.fx('i:cpaid')) = 'M528 corrected by Staff'
      and pg_temp.aff_of('cpaid') = 'none|false',
    'C4 Staff still correct a paid invoice when they leave the affiliate alone: ' || left(v, 80));
  v := pg_temp.correct('manager', 'cpaid', jsonb_build_object('affiliate_id', pg_temp.fx('a:ref')), 'Referrer missed at the till');
  v2 := pg_temp.correct('owner', 'cunpaid', jsonb_build_object('affiliate_id', pg_temp.fx('a:ref2')));
  perform pg_temp.check(v like E'ok\t%' and v2 like E'ok\t%'
      and pg_temp.aff_of('cpaid') = 'a:ref|true' and pg_temp.aff_of('cunpaid') = 'a:ref2|true',
    'C5 a Manager (a paid invoice) and an Owner (an unpaid one) change it in a correction: ' || left(v, 60) || ' / ' || left(v2, 60));
end $$;

-- ═════ G Grants and md5s ═════
\if :{?control}
\else
select pg_temp.check(md5(pg_get_functiondef('public.update_customer(uuid,jsonb,text,timestamptz)'::regprocedure)) = '0d988feda9c7b39cf7fd23790d7eac56'
    and md5(pg_get_functiondef('public.update_survey_particulars_v2(uuid,jsonb,text)'::regprocedure)) = 'c8df8ff415d633bd29a1d6cd752eff73'
    and md5(pg_get_functiondef('public.set_invoice_affiliate(uuid,uuid)'::regprocedure)) = 'fc8ee382615ab8779fe9283656f1ba26'
    and md5(pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) = 'aaf592490eb5d13ca2ccb0544f48f647'
    and md5(pg_get_functiondef('public.customer_is_affiliate_or_portal_login(uuid)'::regprocedure)) = '1482d6488135976f8ffec3ec684bbc70',
  'G1 the four functions and the new one are 528''s (AFTER md5s)');
select pg_temp.check((select bool_and((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x)
                                      = 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres')
                        from pg_proc p where p.oid in ('public.update_customer(uuid,jsonb,text,timestamptz)'::regprocedure,
                                                       'public.update_survey_particulars_v2(uuid,jsonb,text)'::regprocedure,
                                                       'public.set_invoice_affiliate(uuid,uuid)'::regprocedure,
                                                       'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure,
                                                       'public.customer_is_affiliate_or_portal_login(uuid)'::regprocedure))
    and not has_function_privilege('anon', 'public.customer_is_affiliate_or_portal_login(uuid)', 'execute'),
  'G2 the grants: signed-in logins and the service role, as before; the new function the same (not anon)');
select pg_temp.check(md5(pg_get_functiondef('public.require_active_staff(text[])'::regprocedure)) = '877b3aa74cea559881979bb161c450e2'
    and md5(pg_get_functiondef('public.is_owner_or_manager()'::regprocedure)) = 'a98e50f1b6d3fa1e6c62cf52a8073cc8'
    and md5(pg_get_functiondef('public.sg_today()'::regprocedure)) = '1c1289f18e24d8370e9a6364c9c06fca'
    and md5(pg_get_functiondef('public.affiliate_login_link_proof(uuid,uuid)'::regprocedure)) = '2484fb464733c124213b96152837a660'
    and md5(pg_get_functiondef('public.link_affiliate_signup(uuid,uuid,text,uuid,boolean)'::regprocedure)) = '198780b31301695db55c4a39ba9618f8'
    and md5(pg_get_functiondef('public.reassign_customer_referrer(uuid,uuid,text)'::regprocedure)) = '9b32f3bef5b4f17897aae637e343c208'
    and md5(pg_get_functiondef('public.create_customer_quick(text,text,text,text,date,text,text,text,text,uuid,uuid)'::regprocedure)) = '9ff9031d3b40029a19c729a512e99798'
    and md5(pg_get_functiondef('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)'::regprocedure)) = '0d60261bf337a1716dab9307b2f52fea',
  'G3 what 528 relies on and leaves alone (staff check, Owner or Manager, the Singapore day, the link proof, the sign-up link, Correct Referrer, Add, New Invoice) is as tested');

-- ═════ U Undo, and 528 again ═════
\ir ../undo-528.sql
select pg_temp.check(md5(pg_get_functiondef('public.update_customer(uuid,jsonb,text,timestamptz)'::regprocedure)) = '6511100316418394409d8baf1d2b52e0'
    and md5(pg_get_functiondef('public.update_survey_particulars_v2(uuid,jsonb,text)'::regprocedure)) = '45ebc42b54405810b104d4c0c292dcf5'
    and md5(pg_get_functiondef('public.set_invoice_affiliate(uuid,uuid)'::regprocedure)) = 'eb4dc4b9b7eda73ef75a122d48dcdb6a'
    and md5(pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) = 'cea93a5dd73d429f6437f4c9a8fcaa52'
    and to_regprocedure('public.customer_is_affiliate_or_portal_login(uuid)') is null
    and (select bool_and((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x)
                         = 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres')
           from pg_proc p where p.oid in ('public.update_customer(uuid,jsonb,text,timestamptz)'::regprocedure,
                                          'public.update_survey_particulars_v2(uuid,jsonb,text)'::regprocedure,
                                          'public.set_invoice_affiliate(uuid,uuid)'::regprocedure,
                                          'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)),
  'U1 undo-528 puts the four functions back (their BEFORE md5s) with their grants, and drops the new one');
select pg_temp.check(pg_temp.set_aff('staff', 'aff') like E'ok\t%',
  'U2 after the undo Staff change an invoice''s affiliate again (the rule before 528)');
\ir ../../../supabase/528_email_referrer_and_invoice_affiliate_need_owner_or_manager.sql
select pg_temp.check(md5(pg_get_functiondef('public.update_customer(uuid,jsonb,text,timestamptz)'::regprocedure)) = '0d988feda9c7b39cf7fd23790d7eac56'
    and md5(pg_get_functiondef('public.update_survey_particulars_v2(uuid,jsonb,text)'::regprocedure)) = 'c8df8ff415d633bd29a1d6cd752eff73'
    and md5(pg_get_functiondef('public.set_invoice_affiliate(uuid,uuid)'::regprocedure)) = 'fc8ee382615ab8779fe9283656f1ba26'
    and md5(pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) = 'aaf592490eb5d13ca2ccb0544f48f647'
    and md5(pg_get_functiondef('public.customer_is_affiliate_or_portal_login(uuid)'::regprocedure)) = '1482d6488135976f8ffec3ec684bbc70'
    and pg_temp.is(pg_temp.set_aff('staff', 'ref'), E'42501\tOnly an Owner or Manager%'),
  'U3 528 again after the undo: the same five functions, and Staff refused again');

-- ═════ M 528 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m528 m
                                   full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) n
                                     on n.fn = m.fn
                                  where m.fn is null or n.fn is null or m.md5 <> n.md5 or m.acl is distinct from n.acl),
  'M1 running 528 a second time (and the undo and 528 again) left every function and its rights as 528 made them');
\endif
\endif

-- With -v control=1 (a copy without 528) exactly these 20 fail, the fault 528 closes: H1 and H2
-- (no helper); E1, E3, E4, E5, E6, E7, S1, S3, R2, R4, I3, C1 and C3 (each saved what 528
-- refuses); E2, S2, I4, I4b and C4 only follow from those (the earlier call had already saved the
-- change).
do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 528 checks passed.';
end $$;
rollback;
