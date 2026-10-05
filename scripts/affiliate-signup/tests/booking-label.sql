-- A registration through an affiliate's link names the referrer for the booking (392).
--
-- The referral page sends a new registration straight to cal.com with
-- "(Referrer) " filled in, and cal.com puts it in front of the calendar title.
-- The name comes from the database: the referrer's full name without the notes
-- staff keep in brackets. Only a registration that created a customer gets it;
-- nothing else about who is registered changes. Every name here is invented.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
\ir ../../../supabase/392_referral_booking_names_the_affiliate.sql
-- Run twice: the second run must change nothing.
\ir ../../../supabase/392_referral_booking_names_the_affiliate.sql

do $$
declare mgr uuid := gen_random_uuid(); aff_cust uuid; code text; sus_code text; prior uuid;
  r jsonb; n int; c record;
begin
  -- ── The label ───────────────────────────────────────────────────────────────
  for c in select * from (values
    ('Jane Tan', 'Jane Tan'),
    ('Jane (intern) Tan', 'Jane Tan'),
    ('Mary Koh Siew Lan (Orchard)', 'Mary Koh Siew Lan'),
    ('Ali bin Abu [EV24]', 'Ali bin Abu'),
    ('(staff) Ravi Kumar', 'Ravi Kumar'),
    ('  Lee   Ah  Kow  ', 'Lee Ah Kow'),
    ('Kaur D/O Singh', 'Kaur D/O Singh'),
    ('Sean O''Neil', 'Sean O''Neil'),
    ('Ann (half a note', 'Ann half a note'),
    ('Tom {Scheduler} $1 Ng', 'Tom Scheduler 1 Ng'),
    ('A ((nested) note) B', 'A note B'),
    ('(only a note)', null),
    ('', null),
    (null, null)
  ) x(full_name, label)
  loop
    if affiliate_calendar_label(c.full_name) is distinct from c.label then
      raise exception 'FAIL: label of % is %, not %', quote_nullable(c.full_name),
        quote_nullable(affiliate_calendar_label(c.full_name)), quote_nullable(c.label); end if;
  end loop;

  -- ── Fixtures ────────────────────────────────────────────────────────────────
  insert into auth.users(id, email, email_confirmed_at) values (mgr, 'bl-mgr@sig.invalid', now());
  insert into profiles(id, full_name, email, role) values (mgr, 'Manager', 'bl-mgr@sig.invalid', 'manager');
  perform set_config('request.jwt.claim.sub', mgr::text, true);

  insert into customers(full_name, phone, email) values ('Jane (intern) Tan', '+6591392001', 'jt@sig.invalid')
    returning id into aff_cust;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code)
    values (aff_cust, 'active', now(), generate_affiliate_referral_code()) returning referral_code into code;
  insert into customers(full_name, phone, email) values ('Sue Pended', '+6591392002', 'sp@sig.invalid')
    returning id into prior;
  insert into customer_affiliates(customer_id, status, manually_suspended, activated_at, referral_code)
    values (prior, 'active', true, now(), generate_affiliate_referral_code()) returning referral_code into sus_code;
  insert into customers(full_name, phone, email) values ('Already Here', '+6591392003', 'ah@sig.invalid');

  -- ── A new registration, from the signed-out page ───────────────────────────
  execute 'set local role anon';
  r := affiliate_referral_signup(code, 'John', 'Lim', '+6591392004', 'jl@sig.invalid', null);
  execute 'reset role';
  if r is distinct from jsonb_build_object('ok', true, 'outcome', 'registered',
       'message', 'Registration successful.', 'affiliate_label', 'Jane Tan') then
    raise exception 'FAIL: a new registration answered %', r; end if;
  select count(*) into n from customers
   where phone = '+6591392004' and referred_by = aff_cust and referral_source = 'affiliate_link'
     and referral_code_used = code and deleted_at is null;
  if n <> 1 then raise exception 'FAIL: the new registration was not filed under its referrer (% rows)', n; end if;

  -- ── Every other reply is as before and names nobody ────────────────────────
  r := affiliate_referral_signup(code, 'Already', 'Here', '+6591392003', 'ah@sig.invalid', null);
  if r->>'outcome' <> 'already_registered' or r ? 'affiliate_label' then
    raise exception 'FAIL: somebody already registered got %', r; end if;
  if (select referred_by from customers where phone = '+6591392003') is not null then
    raise exception 'FAIL: an anonymous form gave an existing customer a referrer'; end if;

  r := affiliate_referral_signup(code, 'Bot', 'Bot', '+6591392005', null, 'filled');
  if r is distinct from jsonb_build_object('ok', true, 'outcome', 'registered') then
    raise exception 'FAIL: the honeypot answered %', r; end if;
  if exists (select 1 from customers where phone = '+6591392005') then
    raise exception 'FAIL: the honeypot created a customer'; end if;

  r := affiliate_referral_signup(sus_code, 'Sam', 'Wong', '+6591392006', null, null);
  if (r->>'ok')::boolean or r ? 'affiliate_label' then
    raise exception 'FAIL: a suspended link answered %', r; end if;

  r := affiliate_referral_signup(code, 'Jane (intern)', 'Tan', '+6591392001', null, null);
  if (r->>'ok')::boolean or r ? 'affiliate_label' then
    raise exception 'FAIL: a self-referral answered %', r; end if;

  -- A referrer whose notes are all there is: no label, and the registration still succeeds.
  update customers set full_name = '(walk-in)' where id = aff_cust;
  r := affiliate_referral_signup(code, 'Kim', 'Ong', '+6591392007', null, null);
  if r->>'outcome' <> 'registered' or not (r ? 'affiliate_label') or r->'affiliate_label' <> 'null'::jsonb then
    raise exception 'FAIL: a referrer with no printable name answered %', r; end if;

  -- ── Who may call what ──────────────────────────────────────────────────────
  if not has_function_privilege('anon', 'affiliate_referral_signup(text,text,text,text,text,text)', 'execute') then
    raise exception 'FAIL: the referral page can no longer register anybody'; end if;
  if has_function_privilege('anon', 'affiliate_calendar_label(text)', 'execute')
     or has_function_privilege('authenticated', 'affiliate_calendar_label(text)', 'execute') then
    raise exception 'FAIL: affiliate_calendar_label is callable by a client role'; end if;
  execute 'set local role anon';
  begin
    perform affiliate_calendar_label('x');
    raise exception 'FAIL: anon called affiliate_calendar_label';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';

  -- ── Installed as the migration says ────────────────────────────────────────
  if md5(pg_get_functiondef('affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure))
       <> '5b8363a3f87a4c89f2866f3ba0f32b55'
     or md5(pg_get_functiondef('affiliate_calendar_label(text)'::regprocedure))
       <> 'af4eecdcf978c19b3effb6af3a897165' then
    raise exception 'FAIL: the functions are not the versions 392 records'; end if;

  raise notice 'PASS: a new registration names its referrer without bracketed notes; every other reply names nobody; the label is no endpoint';
end $$;

rollback;
