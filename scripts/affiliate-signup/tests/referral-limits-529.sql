-- The referral page limits each sender and all links together, counts every try, and refuses odd
-- names and emails (529; security audit of 17 Nov 2026, M3; the user, 19 Nov 2026).
--
-- Every sign-up is made as the page makes it: signed out (the anon role), through
-- affiliate_referral_signup_with_notice with the page's notice (or affiliate_referral_signup
-- directly, where said), with the request headers PostgREST hands over (request.headers); a
-- sender is the address in cf-connecting-ip.
--
--   S  One sender: 10 tries an hour, whatever the answer (new customers, "already registered",
--      the honeypot, odd input, a link not accepting); the 11th is refused with the sender's
--      message, a known number and an invalid phone too (nothing about the number is said, no
--      customer is made); another address is not affected.
--   W  The refusal is recorded once an hour per sender: hammering adds nothing, and refusals are
--      not counted as tries; an hour later the sender is answered again.
--   V  IPv6: one /64 is one sender (another address in it, written another way, shares the
--      limit), another /64 is not; an IPv4 address written as IPv6 is that IPv4 address.
--   F  x-forwarded-for is never read: alone it makes no sender (no limit, even with a limited
--      address in it), and beside cf-connecting-ip only cf-connecting-ip counts.
--   N  No header, or one that is not a single address: no sender, no sender's limit (12 tries
--      answered); an address with spaces around it is that address.
--   K  "Already registered" tries count for the sender (10 of them, then refused).
--   P  The phone's limit comes before anything is matched: after 3 tries on a number, the 4th
--      gets the same answer whether the number is on file or not ("already registered" tries
--      count and are limited); its refusals are recorded but do not keep the number shut.
--   O  All links together: 30 new customers an hour (created, phone_shared, self; older ones
--      and other outcomes not counted); the next new customer, through any link, is refused with
--      the busy message and recorded; a known number is still answered "already registered".
--   I  Input, both ways: real-world names (apostrophes, hyphens, digits, accents, Chinese,
--      Burmese) go through; a name over 100 characters (first and last together), with a web
--      address, '<', '>' or a control character is refused with its message; the email may be
--      blank, but one typed must look like name@domain.tld and be at most 254 characters. The
--      cases are those of referral-input-529.test.mjs (the page's own check).
--   H  The honeypot counts for the sender; past the limit it gets the sender's answer.
--   A  A phone and name several records have (AMBIGUOUS_CUSTOMER_MATCH, from the match and, with
--      a stand-in for the run, from require_resolved_customer_identity) and a phone 3 customers
--      have (CUSTOMER_PHONE_LIMIT) are answered in the words the page showed for those errors and
--      recorded with the phone and the sender, so both limits count them; one record, or the
--      right name on a full phone, is "already registered"; any other error is raised as before.
--      A real customer's number filled to 3 by two sign-ups: a wrong name is counted, and then the
--      right name and any other get the same "Too many".
--   C  Every event row keeps at most 64 characters of the code typed; a padded code still finds
--      its link.
--   R  No raw address is stored anywhere: sender_key is the hash of a secret salt and the
--      address (no key is an unsalted hash), the column refuses anything else; an Owner reads the
--      rows, the anon key and Staff do not. The salt: one row, row level security on, no policy,
--      no API role reads or writes it; without it the sign-up refuses with a 529 error.
--   G  529's AFTER md5, the grants, the relied-on functions, the wrapper unchanged; the table's
--      row level security and policy unchanged.
--   U  scripts/affiliate-signup/undo-529.sql puts the function and the events table back and drops
--      the salt; 529 again makes them as 529 did, with a new salt.
--   M  529 a second time changes nothing (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (@example.invalid); phones are the fictional +61 491 570 8nn range; addresses are from the
-- documentation ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 2001:db8::/32). Run it
-- on a copy of production as it is (after 528): it applies 529 twice; with -v skip_install=1
-- where 529 is already in; with -v control=1 on a copy WITHOUT 529 (it does not install it,
-- skips G, U and M, and fails on exactly the checks 529 makes pass; see the end of this file).
-- Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/affiliate-signup/tests/referral-limits-529.sql
\set ON_ERROR_STOP on
begin;
-- 546 (security audit of 17 Nov 2026, L15): where it is in, its UNDO goes first, as this file pins
-- md5s of functions it changes (only their search path); this run only, rolled back with the rest.
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as t546_in
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :t546_in
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../../permissions/undo-546.sql
\endif
\if :{?control}
do $$ begin
  if position('-- 529 (security audit' in pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)) > 0 then
    raise exception 'control: 529 is in on this copy; run -v control=1 on a copy without it'; end if;
end $$;
\elif :{?skip_install}
\else
\ir ../../../supabase/529_the_referral_page_limits_each_sender_and_all_links.sql
create temp table m529 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create temp table m529t as
  select (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
            from information_schema.columns where table_schema = 'public' and table_name = 'referral_signup_events') as cols,
         (select string_agg(pg_get_indexdef(indexrelid), ',' order by pg_get_indexdef(indexrelid))
            from pg_index where indrelid = 'public.referral_signup_events'::regclass) as idx,
         (select string_agg(conname || ' ' || pg_get_constraintdef(oid), ',' order by conname)
            from pg_constraint where conrelid = 'public.referral_signup_events'::regclass) as con;
\ir ../../../supabase/529_the_referral_page_limits_each_sender_and_all_links.sql
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
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
-- Fictional phones: +61 491 570 8nn.
create function pg_temp.ph(n int) returns text language sql as $$ select '+61491570' || (800 + n)::text $$;
create function pg_temp.mail(key text) returns text language sql as
$$ select 't529-' || lower(key) || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
create function pg_temp.code(key text) returns text language sql as $$ select pg_temp.tx('code:' || key) $$;
-- The sender key 529 keeps for an address (IPv4) or a /64 (written 'net::/64'): sha256 of its
-- secret salt and the address. Read here as the database owner; never printed. Where there is no
-- salt (a copy without 529), a key no row has.
create function pg_temp.h(k text) returns text language plpgsql as
$$declare v text; begin
  if to_regclass('public.referral_sender_salt') is null then return 'no salt'; end if;
  execute 'select salt from public.referral_sender_salt where id' into v;
  return encode(sha256(convert_to(v || '|' || k, 'UTF8')), 'hex');
end$$;
create function pg_temp.hdr(ip text) returns text language sql as $$ select json_build_object('cf-connecting-ip', ip)::text $$;
-- The events of this file's links (and its stand-ins, code 'T529SYN...'), read whether or not
-- the column sender_key is there (a copy without 529).
create function pg_temp.ev(p_sender text default null, p_outcome text default null, p_phone text default null) returns int language sql as
$$ select count(*)::int from public.referral_signup_events e
    where (e.referral_code like 'T529%' or e.referral_code is null)
      and (p_sender is null or to_jsonb(e)->>'sender_key' = p_sender)
      and (p_outcome is null or e.outcome = p_outcome)
      and (p_phone is null or e.normalized_phone = p_phone) $$;
create function pg_temp.on_phone(p text) returns int language sql as
$$ select count(*)::int from public.customers c where c.deleted_at is null and public.normalize_customer_phone(c.phone) = p $$;

-- /r/<code>, as the page calls it: signed out, with these request headers (null: none at all).
-- p_how: 'page' (the wrapper with the page's notice) or 'direct' (affiliate_referral_signup).
-- Keeps the answer (or the error) under 'r:<tag>'.
create function pg_temp.r(tag text, headers text, code text, first text, last text, phone text, email text default null,
                          honeypot text default null, p_how text default 'page') returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform set_config('request.headers', coalesce(headers, ''), true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  begin
    if p_how = 'direct' then
      r := public.affiliate_referral_signup(code, first, last, phone, email, honeypot);
    else
      r := public.affiliate_referral_signup_with_notice(code, first, last, phone, email, 'r-page-2026-11', honeypot);
    end if;
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  execute 'reset role';
  perform set_config('request.headers', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.put('r:' || tag, r::text);
  return r;
end$$;
create function pg_temp.a(tag text) returns jsonb language sql as $$ select pg_temp.tx('r:' || tag)::jsonb $$;

-- The answers.
create function pg_temp.known() returns jsonb language sql as
$$ select jsonb_build_object('ok', true, 'outcome', 'already_registered', 'message',
     'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.') $$;
create function pg_temp.sender_full() returns jsonb language sql as
$$ select jsonb_build_object('ok', false, 'message',
     'Too many registration attempts from this connection. Please try again in an hour, or contact Energia.') $$;
create function pg_temp.phone_full() returns jsonb language sql as
$$ select jsonb_build_object('ok', false, 'message', 'Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.') $$;
create function pg_temp.busy() returns jsonb language sql as
$$ select jsonb_build_object('ok', false, 'message', 'Registrations are very busy right now. Please try again in an hour, or contact Energia.') $$;
create function pg_temp.closed() returns jsonb language sql as
$$ select jsonb_build_object('ok', false, 'message', 'This referral link is not accepting new registrations right now. Please contact Energia.') $$;
create function pg_temp.fake() returns jsonb language sql as $$ select jsonb_build_object('ok', true, 'outcome', 'registered') $$;
create function pg_temp.refused(msg text) returns jsonb language sql as $$ select jsonb_build_object('ok', false, 'message', msg) $$;
create function pg_temp.registered(tag text) returns boolean language sql as
$$ select pg_temp.a(tag)->>'outcome' = 'registered' and pg_temp.a(tag)->>'message' = 'Registration successful.' $$;
-- 529's messages for odd input.
create function pg_temp.msg(k text) returns text language sql as $$ select case k
  when 'long' then 'Please shorten your name: your first and last name together can be at most 100 characters.'
  when 'web' then 'Please enter just your name, without a web address.'
  when 'odd' then 'Please enter your name without the characters < and > or other special characters.'
  when 'elong' then 'Please enter an email address of at most 254 characters, or leave the email blank.'
  when 'email' then 'Please check your email address: it should look like name@example.com. Or leave the email blank.' end $$;

-- ═════ P0 Fixtures ═════
do $$ begin insert into tx values ('sfx', lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6))); end $$;
select pg_temp.check(not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) like '+614915708__')
    and not exists (select 1 from public.referral_signup_events e where e.normalized_phone like '+614915708__'
                       or e.referral_code like 'T529%'),
  'P0 no customer and no sign-up event uses the test phones (+61491570800..899) or codes (T529...)');
do $$ declare c uuid; k text; i int := 0; begin
  -- Five referrers with a link: A, B, C, D accepting; Z suspended.
  foreach k in array array['A', 'B', 'C', 'D', 'Z'] loop
    i := i + 1;
    insert into customers(full_name, phone, email) values ('Rae Testlink' || k, pg_temp.ph(90 + i), pg_temp.mail('ref' || k))
      returning id into c;
    insert into fx values ('ref' || k, c);
    insert into customer_affiliates(customer_id, status, activated_at, referral_code, manually_suspended)
    values (c, 'active', now() - interval '30 days', upper('T529' || k || pg_temp.tx('sfx')), k = 'Z');
    insert into tx values ('code:' || k, upper('T529' || k || pg_temp.tx('sfx')));
  end loop;
  -- Customers on file, referred by nobody: Kim (01), Kai (02-06), Kay (07).
  insert into customers(full_name, phone) values ('Kim Testknown', pg_temp.ph(1));
  insert into customers(full_name, phone) values ('Kai Testknown', pg_temp.ph(2)), ('Kai Testknown', pg_temp.ph(3)),
    ('Kai Testknown', pg_temp.ph(4)), ('Kai Testknown', pg_temp.ph(5)), ('Kai Testknown', pg_temp.ph(6));
  insert into customers(full_name, phone) values ('Kay Testknown', pg_temp.ph(7));
end $$;

-- ═════ S One sender: 10 tries an hour, whatever the answer ═════
select pg_temp.r('s1', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Sam', 'Testone', pg_temp.ph(10), pg_temp.mail('s1'));
select pg_temp.r('s2', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Sal', 'Testtwo', pg_temp.ph(11), null);
select pg_temp.r('s3', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Sid', 'Testthree', pg_temp.ph(12), null, null, 'direct');
select pg_temp.r('s4', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Kim', 'Testknown', pg_temp.ph(1), null);
select pg_temp.r('s5', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Bot', 'Bot', pg_temp.ph(13), null, 'filled');
select pg_temp.r('s6', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), '<b>Sue</b>', 'Test', pg_temp.ph(14), null);
select pg_temp.r('s7', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Sue', 'Test', pg_temp.ph(14), 'not-an-email');
select pg_temp.r('s8', pg_temp.hdr('203.0.113.7'), pg_temp.code('Z'), 'Sky', 'Testclosed', pg_temp.ph(15), null);
select pg_temp.r('s9', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Sol', 'Testnine', pg_temp.ph(16), null);
select pg_temp.r('s10', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Kim', 'Testknown', pg_temp.ph(1), null);
select pg_temp.check(pg_temp.registered('s1') and pg_temp.registered('s2') and pg_temp.registered('s3') and pg_temp.registered('s9')
    and pg_temp.a('s4') = pg_temp.known() and pg_temp.a('s10') = pg_temp.known() and pg_temp.a('s5') = pg_temp.fake()
    and pg_temp.a('s6') = pg_temp.refused(pg_temp.msg('odd')) and pg_temp.a('s7') = pg_temp.refused(pg_temp.msg('email'))
    and pg_temp.a('s8') = pg_temp.closed(),
  'S1 ten tries from 203.0.113.7, each answered as before (4 new customers, 2 already registered, the honeypot, a link not accepting) or with what to fix: '
  || pg_temp.a('s6')::text || ' ' || pg_temp.a('s7')::text);
select pg_temp.check(pg_temp.ev(pg_temp.h('203.0.113.7')) = 10,
  'S2 each of the ten is recorded with the sender (' || pg_temp.ev(pg_temp.h('203.0.113.7')) || ')');
select pg_temp.r('s11', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Sia', 'Testeleven', pg_temp.ph(17), null);
select pg_temp.r('s12', pg_temp.hdr('203.0.113.7'), pg_temp.code('B'), 'Kim', 'Testknown', pg_temp.ph(1), null);
select pg_temp.r('s13', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Kim', 'Other', pg_temp.ph(1), null, null, 'direct');
select pg_temp.r('s14', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Sia', 'Testeleven', '12', null);
select pg_temp.check(pg_temp.a('s11') = pg_temp.sender_full() and pg_temp.on_phone(pg_temp.ph(17)) = 0,
  'S3 the 11th try (a new number) is refused with the sender''s message and makes nobody: ' || pg_temp.a('s11')::text);
select pg_temp.check(pg_temp.a('s12') = pg_temp.sender_full() and pg_temp.a('s13') = pg_temp.sender_full(),
  'S4 a known number, through another link and directly, gets the very same refusal: nothing about the number is said');
select pg_temp.check(pg_temp.a('s14') = pg_temp.sender_full(),
  'S5 an invalid phone from that sender too (the sender''s limit comes first)');
select pg_temp.r('s15', pg_temp.hdr('203.0.113.8'), pg_temp.code('A'), 'Sia', 'Testeleven', pg_temp.ph(17), null);
select pg_temp.check(pg_temp.registered('s15') and pg_temp.ev(pg_temp.h('203.0.113.8')) = 1,
  'S6 another address (203.0.113.8) is not affected: the same sign-up registers');

-- ═════ W The refusal is recorded once an hour; refusals are not tries ═════
select pg_temp.r('w' || g, pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Wes', 'Testhammer', pg_temp.ph(18), null) from generate_series(1, 5) g;
select pg_temp.check(pg_temp.ev(pg_temp.h('203.0.113.7'), 'sender_limit') = 1 and pg_temp.ev(pg_temp.h('203.0.113.7')) = 11
    and pg_temp.a('w5') = pg_temp.sender_full() and pg_temp.on_phone(pg_temp.ph(18)) = 0,
  'W1 nine refusals (S3-S5 and five more) add one row in all (11 rows for the sender: its 10 tries and one refusal)');
-- 61 minutes on for the refusal, 50 for the tries: still 10 tries in the hour, so still refused,
-- and the refusal is recorded again (once).
update public.referral_signup_events e set created_at = created_at - interval '61 minutes'
 where to_jsonb(e)->>'sender_key' = pg_temp.h('203.0.113.7') and e.outcome = 'sender_limit';
update public.referral_signup_events e set created_at = created_at - interval '50 minutes'
 where to_jsonb(e)->>'sender_key' = pg_temp.h('203.0.113.7') and e.outcome <> 'sender_limit';
select pg_temp.r('w6', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Wes', 'Testhammer', pg_temp.ph(18), null);
select pg_temp.r('w7', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Wes', 'Testhammer', pg_temp.ph(18), null);
select pg_temp.check(pg_temp.a('w6') = pg_temp.sender_full() and pg_temp.a('w7') = pg_temp.sender_full()
    and pg_temp.ev(pg_temp.h('203.0.113.7'), 'sender_limit') = 2,
  'W2 an hour after the first refusal, still past the limit: refused, and one more refusal row (one an hour)');
-- An hour after the tries: answered again.
update public.referral_signup_events e set created_at = created_at - interval '11 minutes'
 where to_jsonb(e)->>'sender_key' = pg_temp.h('203.0.113.7') and e.outcome <> 'sender_limit';
select pg_temp.r('w8', pg_temp.hdr('203.0.113.7'), pg_temp.code('A'), 'Wes', 'Testhammer', pg_temp.ph(18), null);
select pg_temp.check(pg_temp.registered('w8'), 'W3 once its tries are more than an hour old, the sender is answered again');

-- ═════ V IPv6: one /64 is one sender ═════
select pg_temp.r('v' || g, pg_temp.hdr('2001:db8:1:2::1'), pg_temp.code('A'), '<Vi>', 'Test', pg_temp.ph(20), null)
  from generate_series(1, 10) g;
select pg_temp.r('v11', pg_temp.hdr('2001:DB8:1:2:FFFF:FFFF:FFFF:FFFE'), pg_temp.code('A'), '<Vi>', 'Test', pg_temp.ph(20), null);
select pg_temp.r('v12', pg_temp.hdr('2001:0db8:0001:0002:0000:0000:0000:0005'), pg_temp.code('A'), 'Vic', 'Testsix', pg_temp.ph(21), null);
select pg_temp.r('v13', pg_temp.hdr('2001:db8:1:3::1'), pg_temp.code('A'), '<Vi>', 'Test', pg_temp.ph(20), null);
select pg_temp.check(pg_temp.a('v10') = pg_temp.refused(pg_temp.msg('odd'))
    and pg_temp.ev(pg_temp.h('2001:db8:1:2::/64')) = 11 and pg_temp.ev(pg_temp.h('2001:db8:1:2::/64'), 'sender_limit') = 1,
  'V1 ten tries from 2001:db8:1:2::1 are answered and recorded under its /64');
select pg_temp.check(pg_temp.a('v11') = pg_temp.sender_full() and pg_temp.a('v12') = pg_temp.sender_full()
    and pg_temp.on_phone(pg_temp.ph(21)) = 0,
  'V2 another address in the same /64 (in capitals, or written out in full) shares the limit');
select pg_temp.check(pg_temp.a('v13') = pg_temp.refused(pg_temp.msg('odd')) and pg_temp.ev(pg_temp.h('2001:db8:1:3::/64')) = 1,
  'V3 an address in another /64 (2001:db8:1:3::1) is another sender');
-- 203.0.113.9 used up through its IPv6 form.
select pg_temp.r('v20' || g, pg_temp.hdr('203.0.113.9'), pg_temp.code('A'), '<Vi>', 'Test', pg_temp.ph(20), null) from generate_series(1, 10) g;
select pg_temp.r('v31', pg_temp.hdr('::ffff:203.0.113.9'), pg_temp.code('A'), '<Vi>', 'Test', pg_temp.ph(20), null);
select pg_temp.r('v32', pg_temp.hdr('::ffff:203.0.113.10'), pg_temp.code('A'), '<Vi>', 'Test', pg_temp.ph(20), null);
select pg_temp.check(pg_temp.a('v31') = pg_temp.sender_full() and pg_temp.ev(pg_temp.h('203.0.113.10')) = 1,
  'V4 an IPv4 address written as IPv6 (::ffff:203.0.113.9) is that IPv4 address');

-- ═════ F x-forwarded-for is never read ═════
select pg_temp.r('f' || g, '{"x-forwarded-for":"198.51.100.33"}', pg_temp.code('A'), '<Fe>', 'Test', pg_temp.ph(22), null)
  from generate_series(1, 12) g;
select pg_temp.r('f13', '{"x-forwarded-for":"2001:db8:1:2::1, 203.0.113.7"}', pg_temp.code('A'), '<Fe>', 'Test', pg_temp.ph(22), null);
select pg_temp.r('f14', '{"cf-connecting-ip":"198.51.100.34","x-forwarded-for":"2001:db8:1:2::1"}', pg_temp.code('A'), '<Fe>', 'Test', pg_temp.ph(22), null);
select pg_temp.check(pg_temp.a('f12') = pg_temp.refused(pg_temp.msg('odd')) and pg_temp.ev(pg_temp.h('198.51.100.33')) = 0,
  'F1 x-forwarded-for alone makes no sender: 12 tries all answered, none under its address');
select pg_temp.check(pg_temp.a('f13') = pg_temp.refused(pg_temp.msg('odd')),
  'F2 x-forwarded-for naming a sender past its limit changes nothing');
select pg_temp.check(pg_temp.a('f14') = pg_temp.refused(pg_temp.msg('odd')) and pg_temp.ev(pg_temp.h('198.51.100.34')) = 1
    and pg_temp.ev(pg_temp.h('2001:db8:1:2::/64')) = 11,
  'F3 beside cf-connecting-ip, only cf-connecting-ip counts');

-- ═════ N No header, or one that is not a single address ═════
select pg_temp.r('n' || g, null, pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null) from generate_series(1, 12) g;
select pg_temp.r('n13', '{}', pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null);
select pg_temp.r('n14', 'not json', pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null);
select pg_temp.r('n15', '[1]', pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null);
select pg_temp.r('n16', pg_temp.hdr('203.0.113.7, 198.51.100.1'), pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null);
select pg_temp.r('n17', pg_temp.hdr('203.0.113.0/24'), pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null);
select pg_temp.r('n18', pg_temp.hdr('nonsense'), pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null);
select pg_temp.r('n19', pg_temp.hdr(''), pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null);
select pg_temp.r('n20', '{"cf-connecting-ip":12}', pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null);
select pg_temp.r('n21', pg_temp.hdr(' 2001:db8:1:2::77 '), pg_temp.code('A'), '<Ned>', 'Test', pg_temp.ph(23), null);
select pg_temp.check((select bool_and(pg_temp.a('n' || g) = pg_temp.refused(pg_temp.msg('odd'))) from generate_series(1, 20) g)
    and (select count(*) from public.referral_signup_events e
          where e.referral_code = pg_temp.code('A') and e.outcome = 'invalid' and to_jsonb(e)->>'sender_key' is null) = 20 + 13,
  'N1 no header, an empty one, one that is not JSON or names no address, a list, a network, nonsense, a number: no sender, no limit (every try answered, recorded without a sender)');
select pg_temp.check(pg_temp.a('n21') = pg_temp.sender_full(),
  'N2 an address with spaces around it is that address (a /64 past its limit)');

-- ═════ K "Already registered" tries count for the sender ═════
select pg_temp.r('k' || g, pg_temp.hdr('198.51.100.20'), pg_temp.code('B'), 'Kai', 'Testknown', pg_temp.ph(2 + (g - 1) / 3), null)
  from generate_series(1, 10) g;
select pg_temp.r('k11', pg_temp.hdr('198.51.100.20'), pg_temp.code('B'), 'Kai', 'Testknown', pg_temp.ph(6), null);
select pg_temp.check((select bool_and(pg_temp.a('k' || g) = pg_temp.known()) from generate_series(1, 10) g)
    and pg_temp.ev(pg_temp.h('198.51.100.20'), 'duplicate') = 10,
  'K1 ten "already registered" tries (three numbers three times, a fourth once) are answered and recorded');
select pg_temp.check(pg_temp.a('k11') = pg_temp.sender_full(),
  'K2 the 11th, on a number on file not yet tried, is refused with the sender''s message (before 529: never limited)');

-- ═════ P The phone's limit comes before anything is matched ═════
-- Three tries on Kay's number (on file) and on a number nobody has, through the closed link Z.
select pg_temp.r('p' || g, null, pg_temp.code('Z'), 'Kay', 'Testknown', pg_temp.ph(7), null) from generate_series(1, 3) g;
select pg_temp.r('q' || g, null, pg_temp.code('Z'), 'Uma', 'Testnew', pg_temp.ph(30), null) from generate_series(1, 3) g;
select pg_temp.r('p4', null, pg_temp.code('B'), 'Kay', 'Testknown', pg_temp.ph(7), null);
select pg_temp.r('q4', null, pg_temp.code('B'), 'Uma', 'Testnew', pg_temp.ph(30), null);
select pg_temp.r('p5', null, pg_temp.code('C'), 'Kay', 'Testknown', pg_temp.ph(7), null, null, 'direct');
select pg_temp.check(pg_temp.a('p3') = pg_temp.closed() and pg_temp.a('q3') = pg_temp.closed(),
  'P1 three tries on each number through a closed link: refused, recorded with the phone');
select pg_temp.check(pg_temp.a('p4') = pg_temp.phone_full() and pg_temp.a('q4') = pg_temp.phone_full() and pg_temp.a('p5') = pg_temp.phone_full()
    and pg_temp.on_phone(pg_temp.ph(30)) = 0,
  'P2 the 4th: the very same answer for the number on file and the number nobody has (before 529: "already registered" for Kay): '
  || pg_temp.a('p4')::text);
select pg_temp.check(pg_temp.ev(null, 'phone_limit', pg_temp.ph(7)) = 2 and pg_temp.ev(null, 'phone_limit', pg_temp.ph(30)) = 1,
  'P3 each refusal is recorded (outcome phone_limit), for the sender''s count and for staff');
-- Kim's number (her tries in S are more than an hour old now, W): three "already registered",
-- then the 4th is refused.
select pg_temp.r('p6' || g, null, pg_temp.code('C'), 'Kim', 'Testknown', pg_temp.ph(1), null) from generate_series(1, 3) g;
select pg_temp.r('p7', null, pg_temp.code('C'), 'Kim', 'Testknown', pg_temp.ph(1), null);
select pg_temp.check(pg_temp.a('p61') = pg_temp.known() and pg_temp.a('p63') = pg_temp.known() and pg_temp.a('p7') = pg_temp.phone_full(),
  'P4 "already registered" tries count for the phone and are limited: Kim''s 3rd is answered, her 4th refused (before 529: never limited)');
-- Ten minutes on for the three tries: the refusals do not keep the numbers shut.
update public.referral_signup_events e set created_at = created_at - interval '11 minutes'
 where e.normalized_phone in (pg_temp.ph(7), pg_temp.ph(30)) and e.outcome <> 'phone_limit';
select pg_temp.r('p8', null, pg_temp.code('B'), 'Kay', 'Testknown', pg_temp.ph(7), null);
select pg_temp.r('q8', null, pg_temp.code('B'), 'Uma', 'Testnew', pg_temp.ph(30), null);
select pg_temp.check(pg_temp.a('p8') = pg_temp.known() and pg_temp.registered('q8'),
  'P5 once the three tries are more than 10 minutes old, both numbers are answered again (the refusals in between are not counted)');

-- ═════ I Input, both ways ═════
-- Through the closed link Z with no sender: a name and email the rule accepts get the link's
-- answer, one it refuses gets its message. The cases are referral-input-529.test.mjs's.
create temp table names(n serial, first text, last text, want text);
insert into names(first, last, want) values
  ('Siobhan', 'O''Brien', null), ('Mary-Jane', 'Tan-Lim', null), ('Ah Kow 2', 'Lee', null), ('José', 'Muñoz', null),
  ('陈大文', '', null), ('မောင်မောင်', 'ထွန်း', null), ('Nguyễn', 'Văn An', null), ('Ann', 'Lee (Mrs)', null),
  (repeat('A', 49), repeat('B', 50), null), (repeat('A', 100), '', null), ('  Ann  ', '  Lee  ', null),
  (repeat('陈', 100), '', null), ('Dr. Ann', 'St. Clair', null), ('Ann', 'www', null), ('Ann', 'wwwLee', null),
  (repeat('A', 50), repeat('B', 50), 'long'), (repeat('A', 101), '', 'long'), (repeat('陈', 101), '', 'long'),
  ('Ann', 'https://spam.example.invalid', 'web'), ('Visit www.example.invalid', '', 'web'),
  ('WWW.EXAMPLE.INVALID', 'Lee', 'web'), ('ftp://x', '', 'web'),
  ('<b>Ann</b>', '', 'odd'), ('Ann', 'Lee >', 'odd'), ('Ann' || chr(9) || 'Lee', '', 'odd'), ('Ann' || chr(10) || 'Lee', '', 'odd'),
  ('Ann' || chr(133), 'Lee', 'odd'), ('Ann' || chr(127), '', 'odd'), ('Ann' || chr(27) || '[31m', '', 'odd');
create temp table emails(n serial, email text, want text);
insert into emails(email, want) values
  (null, null), ('', null), ('   ', null), ('ann.lee@example.invalid', null), ('Ann.Lee+promo@Example.Invalid', null),
  ('  ann@example.invalid  ', null), ('a_b-c@sub.example.invalid', null), ('o''brien@example.invalid', null),
  ('ann@xn--example.invalid', null), ('陈@例子.invalid', null), ('a@b.co', null),
  (repeat('a', 64) || '@' || repeat('b', 181) || '.invalid', null),
  (repeat('a', 64) || '@' || repeat('b', 182) || '.invalid', 'elong'),
  ('ann', 'email'), ('ann@example', 'email'), ('ann@example.c', 'email'), ('@example.invalid', 'email'),
  ('ann@@example.invalid', 'email'), ('ann@.example.invalid', 'email'), ('ann@example..invalid', 'email'),
  ('ann@example.invalid.', 'email'), ('ann lee@example.invalid', 'email'), ('<ann@example.invalid>', 'email'),
  ('ann@exa' || chr(9) || 'mple.invalid', 'email'), ('ann@example.invalid' || chr(10), 'email'),
  ('Ann <ann@example.invalid>', 'email');
select pg_temp.r('in' || n, null, pg_temp.code('Z'), first, last, pg_temp.ph(40), null) from names;
select pg_temp.r('ie' || n, null, pg_temp.code('Z'), 'Ann', 'Lee', pg_temp.ph(40), email) from emails;
select pg_temp.check(pg_temp.a('in' || n) = pg_temp.closed(),
  'I1 the name ' || left(quote_literal(first || ' ' || last), 60) || ' is accepted: ' || pg_temp.a('in' || n)::text)
  from names where want is null order by n;
select pg_temp.check(pg_temp.a('in' || n) = pg_temp.refused(pg_temp.msg(want)),
  'I2 the name ' || left(quote_literal(first || ' ' || last), 60) || ' is refused (' || want || '): ' || pg_temp.a('in' || n)::text)
  from names where want is not null order by n;
select pg_temp.check(pg_temp.a('ie' || n) = pg_temp.closed(),
  'I3 the email ' || coalesce(left(quote_literal(email), 60), 'none') || ' is accepted: ' || pg_temp.a('ie' || n)::text)
  from emails where want is null order by n;
select pg_temp.check(pg_temp.a('ie' || n) = pg_temp.refused(pg_temp.msg(want)),
  'I4 the email ' || left(quote_literal(email), 60) || ' is refused (' || want || '): ' || pg_temp.a('ie' || n)::text)
  from emails where want is not null order by n;
select pg_temp.check((select count(*) from public.referral_signup_events e where e.referral_code = pg_temp.code('Z') and e.outcome = 'invalid'
                         and e.normalized_phone is null)
                     = (select count(*) from names where want is not null) + (select count(*) from emails where want is not null),
  'I5 each refusal is recorded (outcome invalid, without the phone, so the phone''s limit does not count it)');
-- Real-world names register, through an accepting link.
select pg_temp.r('ir1', null, pg_temp.code('D'), 'Siobhan', 'O''Brien', pg_temp.ph(41), 'Siobhan.OBrien+r@example.invalid');
select pg_temp.r('ir2', null, pg_temp.code('D'), '陈大文', '', pg_temp.ph(42), null);
select pg_temp.r('ir3', null, pg_temp.code('D'), 'မောင်မောင်', 'ထွန်း', pg_temp.ph(43), null);
select pg_temp.r('ir4', null, pg_temp.code('D'), 'Mary-Jane 2', 'Tan-Lim', pg_temp.ph(44), '  ');
select pg_temp.check(pg_temp.registered('ir1') and pg_temp.registered('ir2') and pg_temp.registered('ir3') and pg_temp.registered('ir4')
    and (select full_name from customers where phone = pg_temp.ph(42)) = '陈大文'
    and (select full_name || '|' || email from customers where phone = pg_temp.ph(41)) = 'Siobhan O''Brien|siobhan.obrien+r@example.invalid'
    and (select email from customers where phone = pg_temp.ph(44)) is null,
  'I6 real-world names register as typed (the email lower-cased, a blank one none), as before');
-- An invalid phone and a blank name still raise their errors (the page checks both first).
select pg_temp.r('i7', null, pg_temp.code('D'), 'Ann', 'Lee', '12', null);
select pg_temp.r('i8', null, pg_temp.code('D'), '  ', '', pg_temp.ph(45), null);
select pg_temp.check(pg_temp.a('i7')->>'error' like 'P0001 CUSTOMER_PHONE_REVIEW%' and pg_temp.a('i8')->>'error' = 'P0001 Please enter your name',
  'I7 an invalid phone and a blank name raise their errors, as before');

-- ═════ H The honeypot counts for the sender ═════
select pg_temp.r('h' || g, pg_temp.hdr('192.0.2.50'), pg_temp.code('C'), 'Bot', 'Bot', pg_temp.ph(50 + g), null, 'http://spam.invalid') from generate_series(1, 11) g;
select pg_temp.check((select bool_and(pg_temp.a('h' || g) = pg_temp.fake()) from generate_series(1, 10) g)
    and pg_temp.ev(pg_temp.h('192.0.2.50'), 'honeypot') = 10 and pg_temp.ev(pg_temp.h('192.0.2.50'), 'sender_limit') = 1,
  'H1 ten honeypot tries get the pretend success and are recorded with the sender');
select pg_temp.check(pg_temp.a('h11') = pg_temp.sender_full(),
  'H2 the 11th gets the sender''s message (the sender''s limit comes before the honeypot)');

-- ═════ A Several records, and a full phone: answered and counted ═════
-- Amy is on file twice (two records, one phone, one name); Ben once; Fay, Fen and Fox share a
-- phone (3 customers, full); Pia is alone on hers, until two sign-ups fill it.
do $$ begin
  insert into customers(full_name, phone) values ('Amy Testtwin', pg_temp.ph(60)), ('Amy Testtwin', pg_temp.ph(60)),
    ('Ben Testsingle', pg_temp.ph(61)),
    ('Fay Testfull', pg_temp.ph(62)), ('Fen Testfull', pg_temp.ph(62)), ('Fox Testfull', pg_temp.ph(62)),
    ('Pia Testreal', pg_temp.ph(63));
end $$;
create function pg_temp.ambiguous() returns jsonb language sql as
$$ select jsonb_build_object('ok', false, 'message', 'More than one customer has this phone number and name. Ask staff to verify and select the correct customer record.') $$;
create function pg_temp.three_customers() returns jsonb language sql as
$$ select jsonb_build_object('ok', false, 'message', 'This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.') $$;
select pg_temp.r('am1', pg_temp.hdr('198.51.100.60'), pg_temp.code('B'), 'Amy', 'Testtwin', pg_temp.ph(60), null);
select pg_temp.r('am2', null, pg_temp.code('B'), 'Amy', 'Testtwin', pg_temp.ph(60), null, null, 'direct');
select pg_temp.r('am3', null, pg_temp.code('C'), 'Ben', 'Testsingle', pg_temp.ph(61), null);
select pg_temp.check(pg_temp.a('am1') = pg_temp.ambiguous() and pg_temp.a('am2') = pg_temp.ambiguous()
    and pg_temp.ev(null, 'ambiguous', pg_temp.ph(60)) = 2 and pg_temp.ev(pg_temp.h('198.51.100.60'), 'ambiguous') = 1
    and pg_temp.on_phone(pg_temp.ph(60)) = 2,
  'A1 a phone and name two records have: answered in the words the page showed for AMBIGUOUS_CUSTOMER_MATCH, and recorded (ambiguous, with the phone and the sender); nothing made: '
  || pg_temp.a('am1')::text);
select pg_temp.check(pg_temp.a('am3') = pg_temp.known(), 'A2 a phone and name one record has: "already registered", as before');
select pg_temp.r('am4', null, pg_temp.code('B'), 'Amy', 'Testtwin', pg_temp.ph(60), null);
select pg_temp.r('am5', null, pg_temp.code('B'), 'Amy', 'Testtwin', pg_temp.ph(60), null);
select pg_temp.check(pg_temp.a('am4') = pg_temp.ambiguous() and pg_temp.a('am5') = pg_temp.phone_full(),
  'A3 they count for the phone: the 3rd is answered, the 4th gets the phone''s limit');
-- require_resolved_customer_identity's AMBIGUOUS_CUSTOMER_MATCH (an old 8-digit record that could be
-- the phone, with the name): a stand-in for this run raises it for one name, another error for
-- another; everything inside is undone.
do $stub$ declare r1 jsonb; r2 jsonb; n int; begin
  begin
    execute $f$create or replace function public.require_resolved_customer_identity(p_phone text, p_name text)
      returns void language plpgsql stable security definer set search_path to 'public' as $b$
      begin
        if p_name = 'Lea Teststub' then raise exception 'AMBIGUOUS_CUSTOMER_MATCH'; end if;
        if p_name = 'Lou Teststub' then raise exception 'T529 another error'; end if;
      end $b$$f$;
    r1 := pg_temp.r('am6', pg_temp.hdr('198.51.100.61'), pg_temp.code('C'), 'Lea', 'Teststub', pg_temp.ph(64), null);
    r2 := pg_temp.r('am7', null, pg_temp.code('C'), 'Lou', 'Teststub', pg_temp.ph(65), null);
    n := pg_temp.ev(pg_temp.h('198.51.100.61'), 'ambiguous', pg_temp.ph(64));
    raise exception 'T529 undo the stand-in';
  exception when others then
    if sqlerrm <> 'T529 undo the stand-in' then raise; end if;
  end;
  insert into tx values ('am6', r1::text), ('am7', r2::text), ('am6n', n::text);
end $stub$;
select pg_temp.check(pg_temp.tx('am6')::jsonb = pg_temp.ambiguous() and pg_temp.tx('am6n') = '1',
  'A4 require_resolved_customer_identity''s AMBIGUOUS_CUSTOMER_MATCH: the same answer, recorded with the phone and the sender');
select pg_temp.check(pg_temp.tx('am7')::jsonb = jsonb_build_object('error', 'P0001 T529 another error'),
  'A5 any other error it raises is raised as before: ' || pg_temp.tx('am7'));
-- A full phone: a wrong name gets the words the page showed for CUSTOMER_PHONE_LIMIT; the right one,
-- "already registered"; both count.
select pg_temp.r('pf1', pg_temp.hdr('198.51.100.62'), pg_temp.code('C'), 'Wrong', 'Guess', pg_temp.ph(62), null);
select pg_temp.r('pf2', null, pg_temp.code('C'), 'Fay', 'Testfull', pg_temp.ph(62), null);
select pg_temp.r('pf3', null, pg_temp.code('C'), 'Other', 'Guess', pg_temp.ph(62), null, null, 'direct');
select pg_temp.r('pf4', null, pg_temp.code('C'), 'Fen', 'Testfull', pg_temp.ph(62), null);
select pg_temp.check(pg_temp.a('pf1') = pg_temp.three_customers() and pg_temp.a('pf3') = pg_temp.three_customers() and pg_temp.a('pf2') = pg_temp.known()
    and pg_temp.ev(null, 'phone_full', pg_temp.ph(62)) = 2 and pg_temp.ev(pg_temp.h('198.51.100.62'), 'phone_full') = 1
    and pg_temp.on_phone(pg_temp.ph(62)) = 3,
  'A6 a phone 3 customers have: a name not on it is answered in the words the page showed for CUSTOMER_PHONE_LIMIT and recorded (phone_full, with the phone and the sender); the right name "already registered": '
  || pg_temp.a('pf1')::text);
select pg_temp.check(pg_temp.a('pf4') = pg_temp.phone_full(),
  'A7 they count for the phone: the 4th try, the right name, gets the phone''s limit like any other');
-- Fill Pia's number to 3 with two sign-ups, then try names on it.
select pg_temp.r('pq1', null, pg_temp.code('D'), 'Junk', 'Testone', pg_temp.ph(63), null);
select pg_temp.r('pq2', null, pg_temp.code('D'), 'Junk', 'Testtwo', pg_temp.ph(63), null);
select pg_temp.r('pq3', null, pg_temp.code('D'), 'Wrong', 'Guess', pg_temp.ph(63), null);
select pg_temp.r('pq4', null, pg_temp.code('D'), 'Pia', 'Testreal', pg_temp.ph(63), null);
select pg_temp.r('pq5', null, pg_temp.code('D'), 'Another', 'Guess', pg_temp.ph(63), null);
select pg_temp.check(pg_temp.registered('pq1') and pg_temp.registered('pq2') and pg_temp.on_phone(pg_temp.ph(63)) = 3
    and pg_temp.a('pq3') = pg_temp.three_customers()
    and pg_temp.a('pq4') = pg_temp.phone_full() and pg_temp.a('pq5') = pg_temp.phone_full(),
  'A8 two sign-ups fill a real customer''s number to 3; a wrong name is answered and counted, and then the right name and any other get the same "Too many": names cannot be tested on it (before 529: the wrong names raised, uncounted, and the right one was "already registered")');

-- ═════ C The code kept is at most 64 characters ═════
select pg_temp.r('cl1', null, 'T529LONG' || repeat('x', 300), 'Cal', 'Testlong', pg_temp.ph(66), null);
select pg_temp.r('cl2', null, 'T529LONG' || repeat('y', 300), 'Bot', 'Bot', pg_temp.ph(66), null, 'filled');
select pg_temp.r('cl3', null, 'T529LONG' || repeat('z', 300), '<Cal>', 'Testlong', pg_temp.ph(66), null);
select pg_temp.r('cl4', null, ' ' || pg_temp.code('D') || '   ', 'Cleo', 'Testpadded', pg_temp.ph(67), null);
select pg_temp.check(pg_temp.a('cl1') = pg_temp.closed() and pg_temp.a('cl2') = pg_temp.fake() and pg_temp.a('cl3') = pg_temp.refused(pg_temp.msg('odd'))
    and (select array_agg(length(referral_code) order by outcome) from public.referral_signup_events where referral_code like 'T529LONG%')
        = array[64, 64, 64]
    and (select array_agg(outcome order by outcome) from public.referral_signup_events where referral_code like 'T529LONG%')
        = array['honeypot', 'invalid', 'rejected'],
  'C1 a code of 308 characters: answered as before, each row keeps its first 64 (rejected, honeypot, invalid)');
select pg_temp.check(pg_temp.registered('cl4')
    and (select referral_code from public.referral_signup_events where normalized_phone = pg_temp.ph(67)) = pg_temp.code('D'),
  'C2 a code typed with spaces around it still finds its link and is kept trimmed, as before');

-- ═════ O All links together: 30 new customers an hour ═════
-- Stand-ins (written by hand, as the event website writes its own): new customers until there
-- are 29 in the last hour; older ones and other outcomes, which are not counted.
do $$ declare v_n int; begin
  select count(*) into v_n from public.referral_signup_events
   where outcome in ('created', 'phone_shared', 'self') and created_at > now() - interval '1 hour';
  insert into tx values ('o_before', v_n::text);
  insert into public.referral_signup_events(referral_code, outcome, created_at)
  select 'T529SYN' || g, (array['created', 'phone_shared', 'self'])[1 + g % 3], now() - interval '30 minutes'
    from generate_series(1, 29 - v_n) g;
  insert into public.referral_signup_events(referral_code, outcome, created_at)
  select 'T529SYNOLD' || g, 'created', now() - interval '61 minutes' from generate_series(1, 5) g;
  insert into public.referral_signup_events(referral_code, outcome, created_at)
  select 'T529SYNDUP' || g, o, now() from generate_series(1, 3) g, unnest(array['duplicate', 'link_limit', 'rejected', 'self_known']) o;
end $$;
select pg_temp.r('o1', null, pg_temp.code('C'), 'Oli', 'Testthirty', pg_temp.ph(70), null);
select pg_temp.r('o2', pg_temp.hdr('198.51.100.70'), pg_temp.code('D'), 'Ola', 'Testbusy', pg_temp.ph(71), null);
select pg_temp.r('o3', null, pg_temp.code('A'), 'Ola', 'Testbusy', pg_temp.ph(71), null, null, 'direct');
select pg_temp.r('o4', null, pg_temp.code('C'), 'Kay', 'Testknown', pg_temp.ph(7), null);
select pg_temp.r('o5', null, pg_temp.code('C'), 'Rae', 'Testother', pg_temp.ph(6), null);
select pg_temp.check(pg_temp.tx('o_before')::int < 29 and pg_temp.registered('o1'),
  'O1 with 29 new customers in the last hour (older ones, and other outcomes, not counted), the 30th registers');
select pg_temp.check(pg_temp.a('o2') = pg_temp.busy() and pg_temp.a('o3') = pg_temp.busy() and pg_temp.on_phone(pg_temp.ph(71)) = 0,
  'O2 the 31st, through another link or directly, is refused with the busy message and makes nobody: ' || pg_temp.a('o2')::text);
select pg_temp.check(pg_temp.ev(pg_temp.h('198.51.100.70'), 'all_links_limit') = 1 and pg_temp.ev(null, 'all_links_limit', pg_temp.ph(71)) = 2,
  'O3 each refusal is recorded (outcome all_links_limit, with the phone and the sender)');
select pg_temp.check(pg_temp.a('o4') = pg_temp.known(),
  'O4 a number on file is still answered "already registered" at the limit');
select pg_temp.check(pg_temp.a('o5')->>'ok' = 'false' and pg_temp.a('o5')->>'message' like 'Registrations are very busy%'
    and not exists (select 1 from customers where full_name = 'Rae Testother'),
  'O5 a new name on a number on file (which would make a record for staff, 425) is refused too: it would be a new customer');
update public.referral_signup_events set created_at = now() - interval '61 minutes' where referral_code = 'T529SYN1';
select pg_temp.r('o6', null, pg_temp.code('D'), 'Ola', 'Testbusy', pg_temp.ph(71), null);
select pg_temp.check(pg_temp.registered('o6'), 'O6 once one of the 30 is more than an hour old, the next registers');

-- ═════ R No raw address is stored ═════
select pg_temp.check(not exists (select 1 from public.referral_signup_events e
                                  where e.referral_code like 'T529%'
                                    and (to_jsonb(e)::text ~ '203\.0\.113|198\.51\.100|192\.0\.2\.|2001:db8|2001:DB8'
                                         or (to_jsonb(e)->>'sender_key') !~ '^[0-9a-f]{64}$'))
    and not exists (select 1 from public.audit_logs l where l.created_at >= now() - interval '1 second'
                     and l.new_data::text ~ '203\.0\.113|198\.51\.100|192\.0\.2\.|2001:db8'),
  'R1 no address is stored, in the events or the Audit Log: a sender is a 64-character hash');
select pg_temp.check(pg_temp.ev(pg_temp.h('203.0.113.7')) > 0 and pg_temp.ev(pg_temp.h('2001:db8:1:2::/64')) > 0
    and not exists (select 1 from public.referral_signup_events e, unnest(array['203.0.113.7', '203.0.113.8', '2001:db8:1:2::/64']) a(k)
                     where to_jsonb(e)->>'sender_key' in (encode(sha256(convert_to(a.k, 'UTF8')), 'hex'),
                                                         encode(sha256(convert_to('|' || a.k, 'UTF8')), 'hex'),
                                                         encode(sha256(convert_to('energia-529-referral-sender:' || a.k, 'UTF8')), 'hex'))),
  'R2 the hash is of the secret salt and the address (an IPv6 address: its /64): no key is the unsalted hash of an address');
-- The salt: one row, which no API role can read. (Skipped with -v control=1: there is no salt.)
\if :{?control}
\else
create function pg_temp.salt_as(p_role text) returns text language plpgsql as $f$
declare v text; begin
  perform set_config('request.jwt.claims', json_build_object('role', p_role)::text, true);
  execute format('set local role %I', p_role);
  begin
    execute 'select count(*)::text from public.referral_sender_salt' into v;
  exception when others then v := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
select pg_temp.check(to_regclass('public.referral_sender_salt') is not null
    and (select relrowsecurity from pg_class where oid = to_regclass('public.referral_sender_salt'))
    and not exists (select 1 from pg_policy where polrelid = to_regclass('public.referral_sender_salt'))
    and (select relacl::text from pg_class where oid = to_regclass('public.referral_sender_salt')) = '{postgres=arwdDxtm/postgres}'
    and (select count(*) from pg_class c, public.referral_sender_salt s where c.oid = to_regclass('public.referral_sender_salt')
           and s.id and s.salt ~ '^[0-9a-f]{64}$') = 1,
  'R6 the salt: one row of 64 hex characters, row level security on, no policy, the owner''s alone');
select pg_temp.check(not has_table_privilege('anon', 'public.referral_sender_salt', 'select,insert,update,delete')
    and not has_table_privilege('authenticated', 'public.referral_sender_salt', 'select,insert,update,delete')
    and not has_table_privilege('service_role', 'public.referral_sender_salt', 'select,insert,update,delete')
    and pg_temp.salt_as('anon') = '42501' and pg_temp.salt_as('authenticated') = '42501' and pg_temp.salt_as('service_role') = '42501',
  'R7 no API role (anon, authenticated, service_role) can read or write it');
do $$ declare v text; begin
  begin
    delete from public.referral_sender_salt;
    perform pg_temp.r('r8', pg_temp.hdr('198.51.100.88'), pg_temp.code('A'), 'Sal', 'Testnosalt', pg_temp.ph(68), null);
    v := pg_temp.tx('r:r8');
    raise exception 'T529 put the salt back';
  exception when others then
    if sqlerrm <> 'T529 put the salt back' then raise; end if;
  end;
  insert into tx values ('r8x', v);
end $$;
select pg_temp.check(pg_temp.tx('r8x')::jsonb->>'error' like 'P0001 529: the sender salt (public.referral_sender_salt) is missing%'
    and (select count(*) from public.referral_sender_salt) = 1,
  'R8 without the salt the sign-up refuses loudly (a 529 error), rather than count no sender: ' || coalesce(pg_temp.tx('r8x'), 'no answer'));
\endif
select pg_temp.check((select count(*) from pg_constraint where conrelid = 'public.referral_signup_events'::regclass
                        and conname = 'referral_signup_events_sender_key_is_a_hash') = 1,
  'R3 a check on the column allows only a 64-character hash');
do $$ declare v_state text; begin
  begin
    execute 'insert into public.referral_signup_events(referral_code, outcome, sender_key) values (''T529RAW'', ''invalid'', ''203.0.113.7'')';
    v_state := 'ok';
  exception when others then v_state := sqlstate;
  end;
  insert into tx values ('r4', v_state);
end $$;
select pg_temp.check(pg_temp.tx('r4') = '23514', 'R4 an address written into sender_key is refused (' || pg_temp.tx('r4') || ')');
-- Who reads the events: an Owner; not the anon key, nor Staff.
do $$ declare u uuid; k text; begin
  foreach k in array array['owner', 'staff'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (u, pg_temp.mail('login-' || k), now(), '{"provider":"email"}'::jsonb, '{}'::jsonb);
    insert into profiles(id, full_name, email, role, is_active, invitation_status)
    values (u, 'T529 ' || k, pg_temp.mail('login-' || k), k::user_role, true, 'accepted');
    insert into fx values ('u:' || k, u);
  end loop;
end $$;
create function pg_temp.read_as(p_who text) returns int language plpgsql as $f$
declare v int; begin
  if p_who = 'anon' then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx('u:' || p_who), 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', pg_temp.fx('u:' || p_who)::text, true);
    execute 'set local role authenticated';
  end if;
  begin
    execute 'select count(*) from public.referral_signup_events where referral_code like ''T529%''' into v;
  exception when others then v := -1;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
select pg_temp.check(pg_temp.read_as('owner') = (select count(*) from public.referral_signup_events where referral_code like 'T529%') and pg_temp.read_as('anon') <= 0 and pg_temp.read_as('staff') = 0,
  'R5 an Owner reads the events; the anon key and Staff read none (' || pg_temp.read_as('owner') || '/' || pg_temp.read_as('anon') || '/' || pg_temp.read_as('staff') || ')');

\if :{?control}
\else
-- ═════ G What 529 is ═════
select pg_temp.check(md5(pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)) = '00d528c6f4cc9240b2cf2f82ea2bd487'
    and position('-- 529 (security audit' in pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)) > 0,
  'G1 affiliate_referral_signup is 529''s AFTER, with its marker');
select pg_temp.check((select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x
                       where p.oid = 'public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)
                     = 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'
    and (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)'::regprocedure)
                     = 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
  'G2 the grants: signed out, signed in and the service role, as before (both functions)');
select pg_temp.check(md5(pg_get_functiondef('public.affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)'::regprocedure)) = 'f64347f2ccc993438f0cdb1655c7cc0f'
    and md5(pg_get_functiondef('public.normalize_customer_phone(text)'::regprocedure)) = 'b2bfac910e0c9eff402ba44e19750bee'
    and md5(pg_get_functiondef('public.is_owner_or_manager()'::regprocedure)) = 'a98e50f1b6d3fa1e6c62cf52a8073cc8',
  'G3 the wrapper (the page''s call), normalize_customer_phone and is_owner_or_manager are as tested, unchanged');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.referral_signup_events'::regclass)
    and (select string_agg(polname || ' ' || polcmd::text || ' ' || polroles::text || ' ' || pg_get_expr(polqual, polrelid), ',')
           from pg_policy where polrelid = 'public.referral_signup_events'::regclass)
        = 'aff_events_mgr_read r {0} ( SELECT is_owner_or_manager() AS is_owner_or_manager)'
    and (select string_agg(x::text, ',' order by x::text) from pg_class c, unnest(c.relacl) x where c.oid = 'public.referral_signup_events'::regclass)
        -- 543 (security audit L15): anon and authenticated no longer hold TRUNCATE, REFERENCES, TRIGGER.
        in ('anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres',
            'anon=arwdm/postgres,authenticated=arwdm/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'),
  'G4 the events table: row level security on, its one policy (an Owner or Manager reads), its grants, as before');
select pg_temp.check((select count(*) from pg_indexes where schemaname = 'public' and tablename = 'referral_signup_events'
                        and indexname in ('idx_referral_events_sender_time', 'idx_referral_events_all_links_time')) = 2,
  'G5 the two indexes for the new counts are there');

-- ═════ U Undo, and 529 again ═════
create temp table salt_before as select md5(salt) as m from public.referral_sender_salt;
-- 530 (the QR health form's limits) reads the salt through public.request_sender(), so undo-529
-- refuses while it is in: where it is, it is undone first and put back after 529 again (below).
select to_regprocedure('public.request_sender()') is not null as u529_m530 \gset
\if :u529_m530
\ir ../../survey/undo-530.sql
\endif
\ir ../undo-529.sql
select pg_temp.check(md5(pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)) = '2942e3d4d0e8c76600c3e0ad5e15cc2b'
    and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'referral_signup_events' and column_name = 'sender_key')
    and (select count(*) from pg_indexes where schemaname = 'public' and tablename = 'referral_signup_events') = 3
    and to_regclass('public.referral_sender_salt') is null
    and (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)
        = 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
  'U1 undo-529 puts the function back (its BEFORE md5) with its grants, and drops the column, the two indexes and the salt table');
select pg_temp.r('u2', pg_temp.hdr('203.0.113.8'), pg_temp.code('Z'), '<U>', 'Test', pg_temp.ph(80), null);
select pg_temp.check(pg_temp.a('u2') = pg_temp.closed(), 'U2 after the undo, odd input is taken again (the rule before 529)');
\ir ../../../supabase/529_the_referral_page_limits_each_sender_and_all_links.sql
select pg_temp.r('u3', pg_temp.hdr('203.0.113.8'), pg_temp.code('Z'), '<U>', 'Test', pg_temp.ph(80), null);
select pg_temp.check(md5(pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)) = '00d528c6f4cc9240b2cf2f82ea2bd487'
    and pg_temp.a('u3') = pg_temp.refused(pg_temp.msg('odd')) and pg_temp.ev(pg_temp.h('203.0.113.8')) = 1
    and (select md5(salt) from public.referral_sender_salt) <> (select m from salt_before),
  'U3 529 again after the undo: its version, odd input refused, the sender recorded again under a new salt');
\if :u529_m530
\ir ../../../supabase/530_the_health_form_has_limits_and_holds_existing_customers.sql
\endif

-- ═════ M 529 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m529 m
                                   full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) n
                                     on n.fn = m.fn
                                  where m.fn is null or n.fn is null or m.md5 <> n.md5 or m.acl is distinct from n.acl)
    and (select cols from m529t) = (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
                                      from information_schema.columns where table_schema = 'public' and table_name = 'referral_signup_events')
    and (select idx from m529t) = (select string_agg(pg_get_indexdef(indexrelid), ',' order by pg_get_indexdef(indexrelid))
                                     from pg_index where indrelid = 'public.referral_signup_events'::regclass)
    and (select con from m529t) = (select string_agg(conname || ' ' || pg_get_constraintdef(oid), ',' order by conname)
                                     from pg_constraint where conrelid = 'public.referral_signup_events'::regclass),
  'M1 running 529 a second time (and the undo and 529 again) left every function, its rights and the table as 529 made them');
\endif
\endif

-- With -v control=1 (a copy without 529) exactly these fail (run 19 Nov 2026 on a copy of
-- production after 528: 39 pass, 68 fail; R6-R8, G, U and M are skipped), the fault 529 closes:
-- S2-S5, W1, W2, V1, V2, V4, F3, N2, K1, K2, P2, P3, P4, I2 (each of the 14 refused names), I4
-- (each of the 14 refused emails), I5, H1, H2, A1, A3, A4, A6, A7, A8, C1, O2, O3, O5, R2, R3 and
-- R4 (no sender, no limit per sender or for all links, the phone's limit after "already
-- registered", the two errors raised and uncounted, odd input taken, the code kept whole, no
-- column). These follow from them: S1, V3, F1, F2 and N1 (their tries are odd input, which 529
-- refuses and the old function takes), S6, W3 and O6 (a customer an earlier try made already has
-- the number, or the counts differ).
do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 529 checks passed.';
end $$;
rollback;
