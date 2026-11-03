-- My Network shows a direct referral's (Tier 1) phone number only when the referral was told on the /r/ page that
-- their referrer would see it, the login's link to its record is proven and the affiliate is active (484).
--
-- The Owner, 31 Oct and 1 Nov 2026 (the 484 file's header has the answers word for word): a Tier 1 row carries its
-- stored number only when (a) the affiliate is active, (b) the login's link to its record is proven
-- (affiliate_login_link_proof: own_record, claim_resolved, same_person or verified_email), (c) the referral carries an
-- unwithdrawn mark (referral_phone_notices) naming this referrer, written by the /r/ page's sign-up
-- (affiliate_referral_signup_with_notice) after it showed the notice 'r-page-2026-11', (d) the record still holds the
-- number typed then, and (e) no mark on it is withdrawn; else 'phone' is null. Tier 2 has no 'phone' key.
--
--   S  Every sign-up outcome through the wrapper and through affiliate_referral_signup (unchanged): created and
--      phone_shared (marked, when the notice is listed); already registered (the same name, the same words, the phone
--      and the email (469), the referrer herself on file (self_known)); a try as herself (442: 'self'); the honeypot;
--      a rejected link (unknown, suspended, inactive); the phone's 3 tries in 10 minutes; the link's 20 an hour; and
--      the errors CUSTOMER_PHONE_REVIEW, an empty name, AMBIGUOUS_CUSTOMER_MATCH and CUSTOMER_PHONE_LIMIT (none
--      marked). The notice values: only 'r-page-2026-11' marks; null, blank, spaces, another case, a padded value,
--      an unknown version do not, and are never refused. Named and positional calls; signed out and signed in. The
--      seminar website's six-key call never marks. A re-registration never marks; nor does a customer made earlier
--      in the same transaction on the same phone (the wrapper's "before" list).
--   E  For each S input, run once through each function from the same state (each run undone): the wrapper's answer
--      is the old function's, word for word, and so are its row changes (the customers, events, checks and Audit Log
--      rows it makes, every table's row count, no sequence moved), but for the one mark. Also: an existing referral
--      made in an earlier transaction registering again (no mark), and a number typed with spaces or dashes.
--   P  The proof: each reason and its near misses (a claim closed with nobody, closed later or before the account;
--      Same person before the account, an open entry, a decision with no decider, one on a record outside the chain;
--      an unverified email, another email; a disabled account; a record merged into the account's (own_record and
--      same_person through the chain), but not through an Audit Log row of another action; another login's pair;
--      Unlink then a later account: not proven, until its email is verified); a staff-role claim counts.
--   N  The rule on My Network: told (proven, active) shows the number; the household number typed shows at once;
--      the seminar's, an unknown notice's, no notice's, staff-set, placeholder and legacy rows show none; a told
--      referral under a login that is not proven shows none; suspended or removed: none; another affiliate sees only
--      its own; Tier 2 has no key and no number anywhere. Every other key and value and the row order are what 480's
--      body answers on the same records (its text embedded, md5 d1c387fb...).
--   R  After sign-up: Correct Referrer (none under the new referrer; back: shown), the number changed by staff (none;
--      back: shown), hidden and shown again with the header's exact blocks (refused where there is no mark; as
--      written they change nothing; by number, a household number asked by the other person who holds it; a show
--      again refused when someone else asked to hide it too),
--      merges (the told record into one holding the same number: shown; another number: none; the referrer's own
--      record merged: the login and the marks follow; two marked records: a withdrawal on either hides), Delete and
--      restore, a hard delete takes the marks. The referrer's own record retired into an older one with neither a
--      portal login nor an affiliate record: since 486 a merge by hand that way is refused and changes nothing (R8a);
--      the shape production has from a merge by hand of 26 Sep 2026 is made with production's merge preview of 2 Nov
--      2026 swapped in for that merge alone (R8), and through 437's Link to this customer, which 486 lets through
--      while it refuses the same merge by hand (R8b, undone after).
--   X  Who may: signed out may call the wrapper (as the old function) and nothing else of 484; a signed-in login may
--      not call the proof or read the marks; the service role reads the marks and cannot write them; grants as sets;
--      row level security on, no policy.
--   G  The md5s and the table's description; 484 twice (the second: already this version; left alone; its first run
--      makes the three and changes My Network only; the self-test leaves no row and moves no sequence); NUMBERS OFF
--      is recognised and My Network replaced again; refusals, nothing changed: a My Network neither 480's nor 484's,
--      a half-made state, a changed proof, a table of another shape, no 480 row or no history table, an overload of
--      each name or of affiliate_referral_signup, a grant to signed out or a changed sign-up grant, a relied-on
--      function changed, a column renamed, a write policy on the accounts, a client right on customers, audit_logs
--      or the sign-up list, a changed created_at default.
--   U  UNDO, exactly as the header writes it: level 1 (480's My Network back, no 'phone', grants kept; a second run
--      stops at its guard; the file again turns numbers back on); level 2 (refused before level 1 and while marks
--      exist unless told to discard them; then the catalogue is as before 484 and the history rows are gone, a
--      repeated apply's second row too; 484 again makes everything anew).
--
-- Disposable local database only: a copy of production as it is (480, 483 and 482 in: it installs 484 twice), or
-- one where 484 is in (-v skip_install=1); everything is rolled back. A copy without production's stores gets
-- made-up RETAIL-ADELPHI and ADELPHI-VAN stores for the run, and one built with psql (no migration rows past 478)
-- gets 480's row in supabase_migrations.schema_migrations, for the run. Every name and email is invented
-- (@example.invalid; Gmail addresses with made-up local parts); phones are ACMA's fictional range (+61 2 5550 ....),
-- found free at run time. Every check runs, then the file fails if any did. R8a and R8b need 486 (the merge guard)
-- in: without it they fail, and nothing else does.
-- Once 492 is in (every Tier 1 number shown, the user, 3 Nov 2026), this checks 484's rule with My Network put back
-- to 484's for the run (my-network-as-484.sql, as 492's UNDO does; -v skip_install=1); 492's own checks are in
-- affiliate-network-phone-492.sql. Once 491 is in, confirm_affiliate_email is the version 484 pinned for the run
-- (confirm-email-as-484.sql), so running 484's file again (G, U) is not refused; 491's checks are in details-491.sql.
--   psql -X -v ON_ERROR_STOP=1 [-v skip_install=1] -f scripts/referrals/tests/affiliate-network-phone-484.sql
\set ON_ERROR_STOP on
begin;
-- Where 492 is in, My Network is 484's for this run (rolled back with it).
\ir my-network-as-484.sql
-- Where 491 is in, confirm_affiliate_email is the version 484 pinned, for this run (rolled back with it).
\ir confirm-email-as-484.sql
create function pg_temp.row_counts() returns jsonb language plpgsql as
$$declare r record; n bigint; v jsonb := '{}'::jsonb;
begin
  for r in select s.nspname || '.' || c.relname as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname in ('public', 'auth') and c.relkind = 'r' order by 1 loop
    execute format('select count(*) from %s', r.t) into n;
    v := v || jsonb_build_object(r.t, n);
  end loop;
  return v;
end$$;
create function pg_temp.seqs() returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(s.schemaname || '.' || s.sequencename, s.last_value), '{}'::jsonb)
     from pg_sequences s where s.schemaname in ('public', 'auth') $$;
-- md5 of each public function's definition (and its grants), read with public alone on the search path.
create function pg_temp.fn_md5s() returns table(fn text, md5 text, acl text) language sql set search_path = public as
$$ select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)),
          coalesce((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x), '')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
create function pg_temp.md5_of(sig text) returns text language sql set search_path = public as
$$ select md5(pg_get_functiondef(to_regprocedure('public.' || sig))) $$;
create function pg_temp.acl_of(sig text) returns text[] language sql as
$$ select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || sig) $$;
-- The marks table's description, as 484 reads it (its c_tbl_after).
create function pg_temp.tbl_desc() returns text language sql set search_path = public as
$$ select md5(concat_ws(E'\n',
    (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end
                       || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), ''), ', ' order by a.attnum)
       from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
      where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped),
    (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ', ' order by c.conname) from pg_constraint c where c.conrelid = t.oid),
    (select string_agg(pg_get_indexdef(i.indexrelid), ', ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = t.oid),
    'rls ' || t.relrowsecurity::text || ' force ' || t.relforcerowsecurity::text,
    'acl ' || coalesce((select string_agg(x::text, ',' order by x::text) from unnest(t.relacl) x), ''),
    'policies ' || (select count(*) from pg_policy p where p.polrelid = t.oid)::text,
    'triggers ' || (select count(*) from pg_trigger g where g.tgrelid = t.oid and not g.tgisinternal)::text,
    'owner ' || pg_get_userbyid(t.relowner)))
  from pg_class t where t.oid = to_regclass('public.referral_phone_notices') $$;
create function pg_temp.exec(q text) returns void language plpgsql as $$begin execute q; end$$;
set local lock_timeout = '10s';
set local statement_timeout = '600s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create temp table tx(k text primary key, v text);
grant all on fx, tx to authenticated, anon, service_role;
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
-- Set the request as the API sets it: 'server' (none), 'anon' (signed out), 'service' (the service role), or a
-- login (a fixture key: signed in, role authenticated, auth.uid() that login).
create function pg_temp.as_who(who text) returns void language plpgsql as
$$begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  if who = 'server' then
    perform set_config('request.jwt.claims', '', true);
  elsif who = 'anon' then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  elsif who = 'service' then
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    execute 'set local role service_role';
  else
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;
end$$;
create function pg_temp.as_server() returns void language plpgsql as
$$begin execute 'reset role'; perform set_config('request.jwt.claims', '', true); end$$;
-- Run q as who: 'ok', a tab and the answer, or the SQLSTATE, a tab and the message.
create function pg_temp.try_as(who text, q text) returns text language plpgsql as
$$declare v_out text; v_state text; v_msg text;
begin
  begin
    perform pg_temp.as_who(who);
    execute q into v_out;
    perform pg_temp.as_server();
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    perform pg_temp.as_server();
    return v_state || chr(9) || v_msg;
  end;
end$$;
create function pg_temp.state(v text) returns text language sql as $$ select split_part(v, chr(9), 1) $$;
create function pg_temp.body(v text) returns text language sql as $$ select substr(v, position(chr(9) in v) + 1) $$;
-- An Owner's action, as the pages call it (auth.uid() the Owner, as the server role).
create function pg_temp.as_owner() returns void language sql as
$$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx('owner'), 'role', 'authenticated')::text, true) $$;
create function pg_temp.net(who text) returns jsonb language sql as
$$ select case when pg_temp.state(r) = 'ok' then pg_temp.body(r)::jsonb else jsonb_build_object('error', r) end
     from pg_temp.try_as(who, 'select public.affiliate_portal_network()::text') r $$;
-- The 'phone' of a Tier 1 row by name: its JSON text ('null' when the key is there with no number), 'missing'
-- when the key is absent, 'norow' when no such row.
create function pg_temp.t1(who text, cname text) returns text language sql as
$$ select coalesce((select case when r ? 'phone' then coalesce(r ->> 'phone', 'null') else 'missing' end
                      from jsonb_array_elements(pg_temp.net(who) -> 'tier1') r where r ->> 'customer_name' = cname), 'norow') $$;
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad((pg_temp.tx('phbase')::int + n)::text, 4, '0') $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 't484-' || lower(tag) || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
create function pg_temp.code(key text) returns text language sql as $$ select pg_temp.tx(key || '_code') $$;
-- A sign-up as the pages make it: 'wrap' (the /r/ page: the wrapper, named), 'wrap_pos' (positional, honeypot left
-- out), 'old' (the seminar website: the old function, six named keys), 'old_pos'; signed out unless who is a login.
-- The answer, or {"error": SQLSTATE, "message": ...}.
create function pg_temp.signup(how text, who text, p_code text, p_first text, p_last text, p_phone text, p_email text,
                               p_notice text, p_hp text) returns jsonb language plpgsql as
$$declare v jsonb;
begin
  begin
    perform pg_temp.as_who(who);
    if how = 'wrap' then
      v := public.affiliate_referral_signup_with_notice(p_code := p_code, p_first_name := p_first, p_last_name := p_last,
             p_phone := p_phone, p_email := p_email, p_notice := p_notice, p_honeypot := p_hp);
    elsif how = 'wrap_pos' then
      v := public.affiliate_referral_signup_with_notice(p_code, p_first, p_last, p_phone, p_email, p_notice);
    elsif how = 'old' then
      v := public.affiliate_referral_signup(p_code := p_code, p_first_name := p_first, p_last_name := p_last,
             p_phone := p_phone, p_email := p_email, p_honeypot := p_hp);
    elsif how = 'old_pos' then
      v := public.affiliate_referral_signup(p_code, p_first, p_last, p_phone, p_email);
    else raise exception 'unknown how %', how;
    end if;
    perform pg_temp.as_server();
  exception when others then
    perform pg_temp.as_server();
    v := jsonb_build_object('error', sqlstate, 'message', sqlerrm);
  end;
  return v;
end$$;
-- E: what a sign-up changed. The rows this transaction has made so far are those with created_at = now(); a run's
-- rows are those not there before it. Each table's row count, and whether any sequence moved.
create function pg_temp.e_state() returns jsonb language sql as
$$ select jsonb_build_object('counts', pg_temp.row_counts(), 'seqs', pg_temp.seqs(),
     'customers', coalesce((select jsonb_agg(c.id) from public.customers c where c.created_at = now()), '[]'),
     'events', coalesce((select jsonb_agg(e.id) from public.referral_signup_events e where e.created_at = now()), '[]'),
     'checks', coalesce((select jsonb_agg(k.id) from public.referral_signup_checks k where k.created_at = now()), '[]'),
     'audit', coalesce((select jsonb_agg(l.id) from public.audit_logs l where l.created_at = now()), '[]')) $$;
create function pg_temp.e_diff(b jsonb) returns jsonb language sql as
$$ select jsonb_build_object(
     'counts', (select coalesce(jsonb_object_agg(e.k, e.v::text::bigint - coalesce((b -> 'counts' ->> e.k)::bigint, 0)), '{}')
                  from jsonb_each(pg_temp.row_counts()) e(k, v) where e.v is distinct from b -> 'counts' -> e.k),
     'seqs_moved', (select count(*) from jsonb_each(pg_temp.seqs()) e(k, v) where e.v is distinct from b -> 'seqs' -> e.k),
     'customers', (select coalesce(jsonb_agg(jsonb_build_array(c.full_name, c.phone, c.email, c.is_active, c.referred_by,
                                     c.referral_source, c.referral_code_used, c.referred_at is not null) order by c.full_name), '[]')
                     from public.customers c where c.created_at = now() and not (b -> 'customers') @> to_jsonb(c.id)),
     'events', (select coalesce(jsonb_agg(jsonb_build_array(e.referral_code, e.referrer_customer_id, e.normalized_phone, e.outcome,
                                  e.new_customer_id is not null) order by e.outcome, e.referral_code), '[]')
                  from public.referral_signup_events e where e.created_at = now() and not (b -> 'events') @> to_jsonb(e.id)),
     'checks', (select coalesce(jsonb_agg(jsonb_build_array(k.referrer_customer_id, k.referral_code, k.normalized_phone,
                                  k.phone_shared_with, k.status)), '[]')
                  from public.referral_signup_checks k where k.created_at = now() and not (b -> 'checks') @> to_jsonb(k.id)),
     'audit', (select coalesce(jsonb_agg(jsonb_build_array(l.table_name, l.action, l.module, l.new_data, l.changed_by)
                                 order by l.action, l.new_data::text), '[]')
                 from public.audit_logs l where l.created_at = now() and not (b -> 'audit') @> to_jsonb(l.id))) $$;
-- One sign-up from the current state, undone afterwards (a block whose end raises): its answer and its changes. A
-- setup statement runs first, inside the same undone block.
create function pg_temp.e_run(how text, who text, p_code text, p_first text, p_last text, p_phone text, p_email text,
                              p_notice text, p_hp text, p_setup text default null) returns jsonb language plpgsql as
$$declare v_b jsonb; v_ans jsonb; v_chg jsonb;
begin
  begin
    if p_setup is not null then execute p_setup; end if;
    v_b := pg_temp.e_state();
    v_ans := pg_temp.signup(how, who, p_code, p_first, p_last, p_phone, p_email, p_notice, p_hp);
    v_chg := pg_temp.e_diff(v_b);
    raise exception using errcode = 'P0E84';
  exception when sqlstate 'P0E84' then null;
  end;
  return jsonb_build_object('answer', v_ans, 'changes', v_chg);
end$$;
-- The proof, as the server reads it (plpgsql: written before 484 is installed, read only when called).
create function pg_temp.proof(login text, rec text) returns text language plpgsql as
$$begin return coalesce(public.affiliate_login_link_proof(pg_temp.fx(login), pg_temp.fx(rec)), 'null'); end$$;
-- 480's text of public.affiliate_portal_network() (its c_chg_defs[2], md5 d1c387fb...): the comparison's base (N9)
-- and UNDO's first level.
create function pg_temp.apn480_def() returns text language sql immutable as $t480$ select $d480$CREATE OR REPLACE FUNCTION public.affiliate_portal_network()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_t1 jsonb; v_t2 jsonb;
  -- 480 (the Owner, 29 Oct 2026): each one's cal.com booking, its moment and
  -- state only (calcom_customer_bookings, as the staff Downline reads it).
  v_book jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;

  select coalesce(jsonb_object_agg(b.customer_id, jsonb_build_object('at', b.booking_at, 'state', b.booking_state)), '{}'::jsonb)
    into v_book
    from public.calcom_customer_bookings(array(
           select c.id from public.customers c where c.referred_by = v_me and c.deleted_at is null
           union
           select c.id from public.customers c join public.customers p on p.id = c.referred_by
            where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null)) b;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier1',
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id
                                  and cm.status in ('earned','paid')),
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none')
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t1
    from public.customers c where c.referred_by = v_me and c.deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier2',
           'parent_name', p.full_name,
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id and cm.status in ('earned','paid')),
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none')
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t2
    from public.customers c
    join public.customers p on p.id = c.referred_by
   where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null;

  return jsonb_build_object('tier1', v_t1, 'tier2', v_t2);
end $function$
$d480$::text $t480$;
-- The 484 header's own blocks, word for word (R4 and U run them): hide, show again, UNDO level 1's guard, level 2.
create function pg_temp.hide_sql() returns text language sql immutable as $tb1$ select $b1$do $hide$
declare
  c_customer constant uuid := '00000000-0000-0000-0000-000000000000';  -- the referral who asked
  c_phone constant text := null;  -- or the number they gave, with its country code: hidden on every record holding it
  c_asked constant text := 'by phone, 3 Nov 2026';                     -- how and when they asked
  n int;
begin
  if not exists (select 1 from public.customers c where c.id = c_customer) then
    raise exception '484 hide: % is not a customer (fill in the referral who asked); nothing changed', c_customer;
  end if;
  if c_phone is not null and public.normalize_customer_phone(c_phone) is null then
    raise exception '484 hide: % is not a number that can be matched; nothing changed', c_phone;
  end if;
  -- Their marks and the marks on that number: those not hidden yet are withdrawn; one Audit Log row on each record,
  -- naming who asked, the marks withdrawn now and those hidden already.
  with m as (
    select k.id, k.customer_id, k.withdrawn_at is not null as already
      from public.referral_phone_notices k
     where k.customer_id = c_customer or k.phone = public.normalize_customer_phone(c_phone)
  ), w as (
    update public.referral_phone_notices k set withdrawn_at = now() from m where k.id = m.id and not m.already
  )
  insert into public.audit_logs (table_name, record_id, action, new_data, module)
  select 'customers', m.customer_id, 'referral_phone_hidden',
         jsonb_build_object('marks_withdrawn', count(*) filter (where not m.already),
                            'mark_ids', coalesce(jsonb_agg(m.id order by m.id) filter (where not m.already), '[]'),
                            'hidden_already', coalesce(jsonb_agg(m.id order by m.id) filter (where m.already), '[]'),
                            'asked_by', c_customer, 'asked', c_asked, 'version', 484), 'affiliate'
    from m group by m.customer_id;
  get diagnostics n = row_count;
  if n = 0 and c_phone is null then
    raise exception '484 hide: % has no mark to withdraw (their number may still show on another record: check by number, then set c_phone); nothing changed', c_customer;
  elsif n = 0 then
    raise exception '484 hide: % has no mark to withdraw, and no mark holds %; nothing changed', c_customer, c_phone;
  end if;
  raise notice '484 hide: done for % on % record(s)', c_customer, n;
end $hide$;
$b1$::text $tb1$;
create function pg_temp.show_sql() returns text language sql immutable as $tb2$ select $b2$do $show$
declare
  c_customer constant uuid := '00000000-0000-0000-0000-000000000000';  -- the referral who asked
  c_asked constant text := 'by phone, 4 Nov 2026';                     -- how and when they asked
  n int;
begin
  -- Only the marks their own hide withdrew; none of them if someone else also asked to hide it (the Owner decides).
  select count(*) into n
    from public.referral_phone_notices k
   where k.withdrawn_at is not null
     and exists (select 1 from public.audit_logs l
                  where l.table_name = 'customers' and l.action = 'referral_phone_hidden'
                    and l.new_data ->> 'asked_by' = c_customer::text and (l.new_data -> 'mark_ids') @> to_jsonb(k.id))
     and exists (select 1 from public.audit_logs l
                  where l.table_name = 'customers' and l.action = 'referral_phone_hidden'
                    and l.new_data ->> 'asked_by' is distinct from c_customer::text
                    and ((l.new_data -> 'mark_ids') @> to_jsonb(k.id) or (l.new_data -> 'hidden_already') @> to_jsonb(k.id)));
  if n > 0 then
    raise exception '484 show: % mark(s) that % asked to hide, someone else also asked to hide (the Audit Log''s referral_phone_hidden rows); ask the Owner; nothing changed', n, c_customer;
  end if;
  with s as (
    update public.referral_phone_notices k set withdrawn_at = null
     where k.withdrawn_at is not null
       and exists (select 1 from public.audit_logs l
                    where l.table_name = 'customers' and l.action = 'referral_phone_hidden'
                      and l.new_data ->> 'asked_by' = c_customer::text and (l.new_data -> 'mark_ids') @> to_jsonb(k.id))
    returning k.id, k.customer_id
  )
  insert into public.audit_logs (table_name, record_id, action, new_data, module)
  select 'customers', s.customer_id, 'referral_phone_shown_again',
         jsonb_build_object('marks_restored', count(*), 'mark_ids', jsonb_agg(s.id order by s.id),
                            'asked_by', c_customer, 'asked', c_asked, 'version', 484), 'affiliate'
    from s group by s.customer_id;
  get diagnostics n = row_count;
  if n = 0 then
    raise exception '484 show: % has no mark withdrawn at their request; nothing changed', c_customer;
  end if;
  raise notice '484 show: done for % on % record(s)', c_customer, n;
end $show$;
$b2$::text $tb2$;
create function pg_temp.undo1_sql() returns text language sql immutable as $tb3$ select $b3$do $undo1$
begin
  perform set_config('search_path', 'public', true);
  if md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure)) <> '070d1b485d32cec99fa627b816a91b4a' then
    raise exception 'UNDO 484 (1): public.affiliate_portal_network() is not 484''s version (md5 %); nothing changed',
      md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure));
  end if;
end $undo1$;
$b3$::text $tb3$;
create function pg_temp.undo2_sql() returns text language sql immutable as $tb4$ select $b4$do $undo2$
declare
  c_m constant text := '<M>';                  -- this file's md5 as applied (DEPLOY ORDER 3)
  c_discard_marks constant boolean := false;   -- true only on the Owner's explicit word to discard the marks
  n int;
begin
  perform set_config('lock_timeout', '2s', true);
  perform set_config('search_path', 'public', true);
  if md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure)) <> 'd1c387fb852392da041b5d8207655879'
     or md5(pg_get_functiondef(to_regprocedure('public.affiliate_login_link_proof(uuid,uuid)'))) is distinct from '2484fb464733c124213b96152837a660'
     or md5(pg_get_functiondef(to_regprocedure('public.affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)')))
        is distinct from 'f64347f2ccc993438f0cdb1655c7cc0f'
     or to_regclass('public.referral_phone_notices') is null then
    raise exception 'UNDO 484 (2): My Network is not 480''s (run level 1 first), or the proof, the sign-up with notice or the table is not 484''s; nothing changed';
  end if;
  select count(*) into n from public.referral_phone_notices;
  if n > 0 and not c_discard_marks then
    raise exception 'UNDO 484 (2): referral_phone_notices holds % mark(s), the evidence that the notice was given; keep level 1, or set c_discard_marks on the Owner''s explicit word; nothing changed', n;
  end if;
  drop function public.affiliate_referral_signup_with_notice(text,text,text,text,text,text,text);
  drop function public.affiliate_login_link_proof(uuid,uuid);
  drop table public.referral_phone_notices;
  delete from supabase_migrations.schema_migrations
   where name = '484_affiliate_network_shows_tier1_phone' and md5(array_to_string(statements, '')) = c_m;
  get diagnostics n = row_count;
  if n < 1 then
    raise exception 'UNDO 484 (2): no history row for 484 holds this file''s text (md5 %); nothing changed', c_m;
  end if;
  raise notice 'UNDO 484 (2): the sign-up with notice, the proof and referral_phone_notices dropped; % history row(s) of 484 deleted', n;
end $undo2$;
$b4$::text $tb4$;
-- A block of the header with its customer filled in (the zero id replaced).
create function pg_temp.for_customer(q text, id uuid) returns text language sql as
$$ select replace(q, '''00000000-0000-0000-0000-000000000000''', quote_literal(id::text)) $$;
-- The hide block with the number they gave filled in (its c_phone null replaced).
create function pg_temp.with_phone(q text, phone text) returns text language sql as
$$ select replace(q, 'c_phone constant text := null;', 'c_phone constant text := ' || quote_literal(phone) || ';') $$;

-- ═════ Fixture: staff, logins, affiliates (as the server) ═════
set local client_min_messages = warning;
do $$
declare k text; v uuid; g int; gone text[];
begin
  perform pg_temp.as_server();
  -- Letters only, so no run of digits in a code or an id can be read as a phone number.
  perform pg_temp.put('sfx', translate(lower(substr(md5(gen_random_uuid()::text), 1, 8)), '0123456789', 'ghijklmnop'));
  -- Two hundred free fictional phones in a row (+61 2 5550 nnnn): no customer's, in use or deleted, and no active booking's.
  gone := array(select public.normalize_customer_phone(c.phone) from public.customers c where c.deleted_at is not null);
  for g in 1000 .. 9600 by 200 loop
    continue when exists (select 1 from public.customers c
                           where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                                 between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 199)::text, 4, '0'));
    continue when exists (select 1 from unnest(gone) y(ph)
                           where y.ph between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 199)::text, 4, '0'));
    continue when exists (select 1 from public.calcom_bookings b
                           where b.status = 'active'
                             and b.phone_key between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 199)::text, 4, '0'));
    perform pg_temp.put('phbase', g::text);
    exit;
  end loop;
  if pg_temp.tx('phbase') is null then raise exception 'no free fictional phones'; end if;
  -- An Owner and a member of Staff (staff decisions), a login with no affiliate account, a signed-in login.
  foreach k in array array['owner', 'staff', 'nolink', 'plain'] loop
    insert into auth.users (id, email) values (gen_random_uuid(), pg_temp.mail(k)) returning id into v;
    perform pg_temp.putx(k, v);
  end loop;
  insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  values (pg_temp.fx('owner'), 'T484 Owner', pg_temp.mail('owner'), 'owner'::public.user_role, true, 'accepted'),
         (pg_temp.fx('staff'), 'T484 Staff', pg_temp.mail('staff'), 'staff'::public.user_role, true, 'accepted');
  -- The Adelphi centre and the Van & RoadShow, and 480's migration row, as production has them (a copy without them
  -- gets them for this run).
  insert into public.stores (name, code, country_code) values ('T484 Adelphi centre', 'RETAIL-ADELPHI', 'SG'),
                                                              ('T484 Van and RoadShow', 'ADELPHI-VAN', 'SG')
    on conflict (code) do nothing;
  if not exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261030052953') then
    insert into supabase_migrations.schema_migrations (version, name) values ('20261030052953', '480_downline_and_network_show_calcom_booking');
  end if;
end $$;
-- An affiliate: its record (made p_age ago: '0' = with its account, in this transaction), an active affiliate record
-- with a made-up code, a login and its portal account (triggers off for that statement only: no welcome WhatsApp).
create function pg_temp.mk_aff(key text, n int, p_age interval, p_login_email text default null, p_rec_email text default null,
                               p_status text default 'claimed') returns void language plpgsql as
$$declare v_c uuid; v_a uuid; v_u uuid := gen_random_uuid(); v_acct uuid; v_srr text := current_setting('session_replication_role');
begin
  insert into public.customers (full_name, phone, email, created_at)
    values ('T484 Aff ' || key, pg_temp.ph(n), coalesce(p_rec_email, pg_temp.mail(key)), now() - p_age) returning id into v_c;
  insert into public.customer_affiliates (customer_id, status, activated_at, referral_code)
    values (v_c, 'active', now(), 'T484' || upper(key) || upper(pg_temp.tx('sfx'))) returning id into v_a;
  insert into auth.users (id, email) values (v_u, coalesce(p_login_email, pg_temp.mail(key)));
  set local session_replication_role = replica;
  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status)
    values (v_u, v_c, v_a, p_status) returning id into v_acct;
  execute format('set local session_replication_role = %L', v_srr);
  perform pg_temp.putx(key, v_c); perform pg_temp.putx(key || '_aff', v_a);
  perform pg_temp.putx(key || '_login', v_u); perform pg_temp.putx(key || '_acct', v_acct);
  perform pg_temp.put(key || '_code', 'T484' || upper(key) || upper(pg_temp.tx('sfx')));
end$$;
-- A (the main affiliate) and B: records made with their accounts (own_record); the record holds the login's email,
-- not verified. C: suspended; D: inactive (their links refuse). The proof's cases (P), most records 30 days old.
select pg_temp.mk_aff('a', 0, '0 seconds'), pg_temp.mk_aff('b', 1, '0 seconds'),
       pg_temp.mk_aff('c', 2, '0 seconds'), pg_temp.mk_aff('d', 3, '0 seconds'),
       pg_temp.mk_aff('claim', 4, '30 days'), pg_temp.mk_aff('staffclaim', 5, '30 days'), pg_temp.mk_aff('letin', 6, '30 days'),
       pg_temp.mk_aff('later', 7, '30 days'), pg_temp.mk_aff('staleclaim', 8, '30 days'), pg_temp.mk_aff('same', 9, '30 days'),
       pg_temp.mk_aff('stalesame', 10, '30 days'), pg_temp.mk_aff('linked', 11, '30 days'), pg_temp.mk_aff('open', 12, '30 days'),
       pg_temp.mk_aff('email', 13, '30 days', 't484.mail.' || pg_temp.tx('sfx') || '+portal@gmail.com',
                      't484mail' || pg_temp.tx('sfx') || '@googlemail.com'),
       pg_temp.mk_aff('unverified', 14, '30 days'), pg_temp.mk_aff('diffmail', 15, '30 days', pg_temp.mail('diffmail'), pg_temp.mail('another')),
       pg_temp.mk_aff('chain', 16, '30 days'), pg_temp.mk_aff('chainsame', 17, '30 days'),
       pg_temp.mk_aff('disabled', 18, '0 seconds', null, null, 'disabled'), pg_temp.mk_aff('relink', 19, '0 seconds');
update public.customer_affiliates set manually_suspended = true, status = 'suspended_manual' where id = pg_temp.fx('c_aff');
update public.customer_affiliates set status = 'inactive' where id = pg_temp.fx('d_aff');
do $$
declare v uuid;
begin
  -- claim_resolved: resolved by the Owner (and by Staff) in the account's transaction; near misses: closed with
  -- nobody (437's let-in), closed later (an "already linked" close), closed the day before this account.
  insert into public.affiliate_account_claims (auth_user_id, entered_phone, status, resolved_by, resolved_at, resolution_note)
  values (pg_temp.fx('claim_login'), pg_temp.ph(4), 'resolved', pg_temp.fx('owner'), now(), 'T484 checked'),
         (pg_temp.fx('staffclaim_login'), pg_temp.ph(5), 'resolved', pg_temp.fx('staff'), now(), 'T484 checked'),
         (pg_temp.fx('letin_login'), pg_temp.ph(6), 'resolved', null, now(), 'T484 let in'),
         (pg_temp.fx('later_login'), pg_temp.ph(7), 'resolved', pg_temp.fx('owner'), now() + interval '1 minute', 'T484 already linked'),
         (pg_temp.fx('staleclaim_login'), pg_temp.ph(8), 'resolved', pg_temp.fx('owner'), now() - interval '1 day', 'T484 old');
  -- same_person: decided now (after the account) on its record; near misses: decided the day before, still open.
  insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, reason, status, decided_at, decided_by, decision_note, candidate_ids)
  values (pg_temp.fx('same_login'), pg_temp.fx('same'), 'phone_other_name', 'same_person', now(), pg_temp.fx('owner'), 'T484 checked', '{}'),
         (pg_temp.fx('stalesame_login'), pg_temp.fx('stalesame'), 'phone_other_name', 'same_person', now() - interval '1 day',
          pg_temp.fx('owner'), 'T484 old', '{}');
  insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, reason, status, candidate_ids)
  values (pg_temp.fx('open_login'), pg_temp.fx('open'), 'phone_other_name', 'open', '{}');
  -- linked: staff linked the login's sign-up record (made fresh, merged away) to this record.
  insert into public.customers (full_name, phone, created_at, deleted_at) values ('T484 Fresh linked', pg_temp.ph(30), now(), now())
    returning id into v;
  insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, reason, status, decided_at, decided_by, decision_note,
                                               linked_customer_id, candidate_ids)
  values (pg_temp.fx('linked_login'), v, 'name_match', 'linked', now(), pg_temp.fx('owner'), 'T484 linked', pg_temp.fx('linked'), '{}');
  -- verified_email: verified, the record's email the same Gmail inbox; near misses: unverified, another email.
  update public.affiliate_accounts set email_verified_at = now() where id in (pg_temp.fx('email_acct'), pg_temp.fx('diffmail_acct'));
  -- Through a merge chain: the record the sign-up made (now) was merged by an Owner into the account's record
  -- (own_record through it); and a Same person decided on a record later merged into the account's (same_person).
  insert into public.customers (full_name, phone, created_at, deleted_at) values ('T484 Chain made', pg_temp.ph(31), now(), now())
    returning id into v;
  insert into public.audit_logs (table_name, record_id, action, new_data, changed_by, module)
  values ('customers', pg_temp.fx('chain'), 'customers_merged', jsonb_build_object('merged_from', v, 'reason', 'T484 duplicate'),
          pg_temp.fx('owner'), 'customers');
  insert into public.customers (full_name, phone, created_at, deleted_at) values ('T484 Chain same', pg_temp.ph(32), now() - interval '40 days', now())
    returning id into v;
  insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, reason, status, decided_at, decided_by, decision_note, candidate_ids)
  values (pg_temp.fx('chainsame_login'), v, 'phone_other_name', 'same_person', now(), pg_temp.fx('owner'), 'T484 checked', '{}');
  insert into public.audit_logs (table_name, record_id, action, new_data, changed_by, module)
  values ('customers', pg_temp.fx('chainsame'), 'customers_merged', jsonb_build_object('merged_from', v, 'reason', 'T484 duplicate'),
          pg_temp.fx('owner'), 'customers');
end $$;
-- Near misses of the proof (review, 2 Nov 2026): (c) a decision with no decider (Same person; Link), a decision naming
-- a record outside the account's chain (Same person on another record; Link to another record); and the chain followed
-- through customers_merged rows only (an Audit Log row of another action naming merged_from: a record made with the
-- account, which would be own_record through a merge).
select pg_temp.mk_aff('nodecider', 20, '30 days'), pg_temp.mk_aff('nodeclink', 21, '30 days'),
       pg_temp.mk_aff('otherrec', 22, '30 days'), pg_temp.mk_aff('otherlink', 23, '30 days'),
       pg_temp.mk_aff('nearchain', 27, '30 days');
do $$
declare v uuid; w uuid;
begin
  insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, reason, status, decided_at, decided_by, decision_note, candidate_ids)
  values (pg_temp.fx('nodecider_login'), pg_temp.fx('nodecider'), 'phone_other_name', 'same_person', now(), null, 'T484 no decider', '{}');
  insert into public.customers (full_name, phone, created_at, deleted_at) values ('T484 Fresh nodeclink', pg_temp.ph(24), now(), now())
    returning id into v;
  insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, reason, status, decided_at, decided_by, decision_note,
                                               linked_customer_id, candidate_ids)
  values (pg_temp.fx('nodeclink_login'), v, 'name_match', 'linked', now(), null, 'T484 no decider', pg_temp.fx('nodeclink'), '{}');
  insert into public.customers (full_name, phone, created_at) values ('T484 Other record', pg_temp.ph(26), now() - interval '40 days')
    returning id into w;
  insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, reason, status, decided_at, decided_by, decision_note, candidate_ids)
  values (pg_temp.fx('otherrec_login'), w, 'phone_other_name', 'same_person', now(), pg_temp.fx('owner'), 'T484 other record', '{}');
  insert into public.customers (full_name, phone, created_at, deleted_at) values ('T484 Fresh otherlink', pg_temp.ph(25), now(), now())
    returning id into v;
  insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, reason, status, decided_at, decided_by, decision_note,
                                               linked_customer_id, candidate_ids)
  values (pg_temp.fx('otherlink_login'), v, 'name_match', 'linked', now(), pg_temp.fx('owner'), 'T484 other record', w, '{}');
  insert into public.customers (full_name, phone, created_at, deleted_at) values ('T484 Near chain', pg_temp.ph(36), now(), now())
    returning id into v;
  insert into public.audit_logs (table_name, record_id, action, new_data, changed_by, module)
  values ('customers', pg_temp.fx('nearchain'), 'customers_updated', jsonb_build_object('merged_from', v, 'reason', 'T484 not a merge'),
          pg_temp.fx('owner'), 'customers');
end $$;
-- Customers already on file for the sign-up outcomes: one holding a phone (another name signs up on it: phone_shared),
-- one with the same words, one with a phone and an email (469), two twins on one phone (ambiguous), three on one
-- phone (its limit); and A's login's own sign-up details (442: a try as herself).
insert into public.customers (full_name, phone, email) values
  ('T484 Existing', pg_temp.ph(41), null), ('T484 Words Same', pg_temp.ph(60), null), ('T484 Mailer', pg_temp.ph(61), pg_temp.mail('mailer')),
  ('T484 Twin Same', pg_temp.ph(62), null), ('T484 Twin Same', pg_temp.ph(62), null),
  ('T484 Limit One', pg_temp.ph(63), null), ('T484 Limit Two', pg_temp.ph(63), null), ('T484 Limit Three', pg_temp.ph(63), null);
insert into public.affiliate_signup_identities (auth_user_id, full_name, phone, email, source)
values (pg_temp.fx('a_login'), 'T484 Aff a', pg_temp.ph(0), pg_temp.mail('a'), 'backfill');
set local client_min_messages = notice;

-- What My Network answers with 480's body on these records (installed for the calls, then undone), and before 484
-- (only when this file installs it).
\if :{?skip_install}
\else
select pg_temp.put('pre_net_md5', pg_temp.md5_of('affiliate_portal_network()'));
create temp table b484 as select * from pg_temp.fn_md5s();
create temp table r484 as select pg_temp.row_counts() as before, pg_temp.seqs() as seq_before;
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
create temp table m484 as select * from pg_temp.fn_md5s();
alter table r484 add column after1 jsonb, add column seq_after1 jsonb;
update r484 set after1 = pg_temp.row_counts(), seq_after1 = pg_temp.seqs();
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
create temp table m484b as select * from pg_temp.fn_md5s();
\endif
select pg_temp.put('marks_at_start', (select count(*)::text from public.referral_phone_notices));

-- ═════ S Every sign-up outcome; which ones mark ═════
-- The told ones (the /r/ page, the listed notice), each a new customer: under A, a new number (created), and a new
-- name on T484 Existing's number (phone_shared); under B; under the claim and unverified affiliates (proven, not).
select pg_temp.put('s_told', pg_temp.signup('wrap', 'anon', pg_temp.code('a'), 'T484', 'Told', pg_temp.ph(40), null, 'r-page-2026-11', null)::text);
select pg_temp.put('s_house', pg_temp.signup('wrap', 'anon', pg_temp.code('a'), 'T484', 'Household', pg_temp.ph(41), null, 'r-page-2026-11', null)::text);
select pg_temp.put('s_btold', pg_temp.signup('wrap', 'anon', pg_temp.code('b'), 'T484', 'Btold', pg_temp.ph(47), null, 'r-page-2026-11', null)::text);
select pg_temp.put('s_ctold', pg_temp.signup('wrap', 'anon', pg_temp.code('claim'), 'T484', 'Claimtold', pg_temp.ph(33), null, 'r-page-2026-11', null)::text);
select pg_temp.put('s_utold', pg_temp.signup('wrap', 'anon', pg_temp.code('unverified'), 'T484', 'Unvtold', pg_temp.ph(34), null, 'r-page-2026-11', null)::text);
-- The seminar website (six keys to the old function), and on the same number in this same transaction a new name
-- through /r/ (phone_shared): only the latter is marked (the wrapper's "before" list).
select pg_temp.put('s_sem', pg_temp.signup('old', 'anon', pg_temp.code('a'), 'T484', 'Seminar', pg_temp.ph(42), null, null, null)::text);
select pg_temp.put('s_sem2', pg_temp.signup('old', 'anon', pg_temp.code('a'), 'T484', 'Seminar Two', pg_temp.ph(48), null, null, null)::text);
select pg_temp.put('s_shared', pg_temp.signup('wrap', 'anon', pg_temp.code('a'), 'T484', 'Sharedtold', pg_temp.ph(48), null, 'r-page-2026-11', null)::text);
-- Notice values that are not listed: no mark, never refused.
select pg_temp.put('s_unknown', pg_temp.signup('wrap', 'anon', pg_temp.code('a'), 'T484', 'Unknown', pg_temp.ph(43), null, 'r-page-2099-01', null)::text);
select pg_temp.put('s_nonotice', pg_temp.signup('wrap', 'anon', pg_temp.code('a'), 'T484', 'Nonotice', pg_temp.ph(44), null, null, null)::text);
select pg_temp.put('s_n_' || x.k, pg_temp.signup('wrap', 'anon', pg_temp.code('a'), 'T484', 'Notice ' || x.k, pg_temp.ph(x.n), null, x.notice, null)::text)
  from (values ('blank', 65, ''), ('spaces', 66, '   '), ('upper', 67, 'R-PAGE-2026-11'), ('lead', 68, ' r-page-2026-11'),
               ('trail', 69, 'r-page-2026-11 '), ('suffix', 70, 'r-page-2026-11x')) x(k, n, notice);
-- Positional; signed in (a login that is not an affiliate's); the told person again (already registered).
select pg_temp.put('s_pos', pg_temp.signup('wrap_pos', 'anon', pg_temp.code('a'), 'T484', 'Positional', pg_temp.ph(71), null, 'r-page-2026-11', null)::text);
select pg_temp.put('s_signedin', pg_temp.signup('wrap', 'plain', pg_temp.code('a'), 'T484', 'Signedin', pg_temp.ph(72), null, 'r-page-2026-11', null)::text);
select pg_temp.put('s_again', pg_temp.signup('wrap', 'anon', pg_temp.code('a'), 'T484', 'Told', pg_temp.ph(40), null, 'r-page-2026-11', null)::text);
select pg_temp.check(pg_temp.tx(k)::jsonb ->> 'outcome' = 'registered' and pg_temp.tx(k)::jsonb ->> 'ok' = 'true',
                     'S1 registered: ' || k || ' ' || pg_temp.tx(k))
  from unnest(array['s_told', 's_house', 's_btold', 's_ctold', 's_utold', 's_sem', 's_sem2', 's_shared', 's_unknown', 's_nonotice',
                    's_n_blank', 's_n_spaces', 's_n_upper', 's_n_lead', 's_n_trail', 's_n_suffix', 's_pos', 's_signedin']) k;
select pg_temp.check(pg_temp.tx('s_again')::jsonb ->> 'outcome' = 'already_registered',
  'S2 the told person registering again: already registered (no new customer) ' || pg_temp.tx('s_again'));
select pg_temp.check((select string_agg(c.full_name || '>' || r.full_name || '>' || (n.phone = public.normalize_customer_phone(c.phone))::text
                                        || '>' || n.notice_version || '>' || (n.referral_code = c.referral_code_used)::text
                                        || '>' || (n.withdrawn_at is null)::text, ', ' order by c.full_name)
                        from public.referral_phone_notices n join public.customers c on c.id = n.customer_id
                        join public.customers r on r.id = n.referrer_customer_id where c.full_name like 'T484 %')
                     = 'T484 Btold>T484 Aff b>true>r-page-2026-11>true>true, T484 Claimtold>T484 Aff claim>true>r-page-2026-11>true>true, '
                       || 'T484 Household>T484 Aff a>true>r-page-2026-11>true>true, T484 Positional>T484 Aff a>true>r-page-2026-11>true>true, '
                       || 'T484 Sharedtold>T484 Aff a>true>r-page-2026-11>true>true, T484 Signedin>T484 Aff a>true>r-page-2026-11>true>true, '
                       || 'T484 Told>T484 Aff a>true>r-page-2026-11>true>true, T484 Unvtold>T484 Aff unverified>true>r-page-2026-11>true>true'
    and (select count(*) from public.referral_phone_notices) = pg_temp.tx('marks_at_start')::int + 8,
  'S3 exactly one mark for each told sign-up (created, phone_shared, positional, signed in), naming its referrer, the number typed (as stored), the version and the code; none for the seminar website (also the one made earlier on the same number in this transaction), an unlisted notice (null, blank, spaces, another case, padded, unknown) or registering again: '
  || (select coalesce(string_agg(c.full_name, ', ' order by c.full_name), '') from public.referral_phone_notices n join public.customers c on c.id = n.customer_id));
select pg_temp.check(exists (select 1 from public.referral_signup_checks k join public.customers c on c.id = k.customer_id
                              where c.full_name = 'T484 Household' and k.status = 'pending')
    and exists (select 1 from public.referral_signup_events e join public.customers c on c.id = e.new_customer_id
                 where c.full_name = 'T484 Household' and e.outcome = 'phone_shared')
    and (select array_agg(k order by k collate "C") from jsonb_object_keys(pg_temp.tx('s_told')::jsonb) k)
        = (select array_agg(k order by k collate "C") from jsonb_object_keys(pg_temp.tx('s_sem')::jsonb) k)
    and pg_temp.tx('s_told')::jsonb ->> 'affiliate_label' = 'T484 Aff a',
  'S4 the household sign-up is phone_shared with a pending check, as before; the wrapper''s answer has the old function''s keys and the referrer''s label');

-- ═════ E The wrapper changes what the old function changes, but for the mark ═════
-- Each input once through the old function (six keys) and once through the wrapper (the listed notice), each from the
-- same state and undone.
create temp table e_in(k text primary key, who text, code text, first text, last text, phone text, email text, hp text, setup text,
                       outcome text, marks int);
insert into e_in values
  ('created',      'anon', pg_temp.code('a'), 'T484', 'E New',       pg_temp.ph(50), null, null, null, 'registered', 1),
  ('created_mail', 'anon', pg_temp.code('a'), 'T484', 'E Mail',      pg_temp.ph(51), pg_temp.mail('e-mail'), null, null, 'registered', 1),
  ('phone_shared', 'anon', pg_temp.code('a'), 'T484', 'E Other',     pg_temp.ph(41), null, null, null, 'registered', 1),
  ('same_name',    'anon', pg_temp.code('a'), 'T484', 'Existing',    pg_temp.ph(41), null, null, null, 'already_registered', 0),
  ('same_words',   'anon', pg_temp.code('a'), 'Same', 'T484 Words',  pg_temp.ph(60), null, null, null, 'already_registered', 0),
  ('phone_email',  'anon', pg_temp.code('a'), 'T484', 'Another',     pg_temp.ph(61), pg_temp.mail('mailer'), null, null, 'already_registered', 0),
  ('self_known',   'anon', pg_temp.code('a'), 'T484 Aff', 'a',       pg_temp.ph(0), null, null, null, 'already_registered', 0),
  ('self',         'anon', pg_temp.code('a'), 'T484', 'Herself',     pg_temp.ph(52), pg_temp.mail('a'), null, null, 'already_registered', 0),
  ('honeypot',     'anon', pg_temp.code('a'), 'T484', 'E Bot',       pg_temp.ph(53), null, 'filled', null, 'registered', 0),
  ('unknown_code', 'anon', 'T484NOSUCH' || upper(pg_temp.tx('sfx')), 'T484', 'E Lost', pg_temp.ph(54), null, null, null, null, 0),
  ('suspended',    'anon', pg_temp.code('c'), 'T484', 'E Susp',      pg_temp.ph(55), null, null, null, null, 0),
  ('inactive',     'anon', pg_temp.code('d'), 'T484', 'E Inact',     pg_temp.ph(56), null, null, null, null, 0),
  ('phone_tries',  'anon', pg_temp.code('a'), 'T484', 'E Tries',     pg_temp.ph(57), null, null,
     format('insert into public.referral_signup_events (referral_code, normalized_phone, outcome) select %L, %L, ''rejected'' from generate_series(1, 3)',
            'T484X', pg_temp.ph(57)), null, 0),
  ('link_limit',   'anon', pg_temp.code('a'), 'T484', 'E Limit',     pg_temp.ph(58), null, null,
     format('insert into public.referral_signup_events (referral_code, referrer_customer_id, normalized_phone, outcome) select %L, %L::uuid, %L, ''created'' from generate_series(1, 20)',
            pg_temp.code('a'), pg_temp.fx('a'), pg_temp.ph(59)), null, 0),
  ('phone_review', 'anon', pg_temp.code('a'), 'T484', 'E Probe',     '0', null, null, null, null, 0),
  ('no_name',      'anon', pg_temp.code('a'), '', ' ',              pg_temp.ph(73), null, null, null, null, 0),
  ('ambiguous',    'anon', pg_temp.code('a'), 'T484', 'Twin Same',   pg_temp.ph(62), null, null, null, null, 0),
  ('phone_limit',  'anon', pg_temp.code('a'), 'T484', 'Limit Four',  pg_temp.ph(63), null, null, null, null, 0),
  ('signed_in',    'plain', pg_temp.code('a'), 'T484', 'E Signed',   pg_temp.ph(74), null, null, null, 'registered', 1),
  ('own_login',    'a_login', pg_temp.code('b'), 'T484', 'E Own',    pg_temp.ph(75), null, null, null, 'registered', 1),
  -- an existing referral of A's, made through the link in an EARLIER transaction (a day ago), registering again
  ('again_old',    'anon', pg_temp.code('a'), 'T484', 'E Old',       pg_temp.ph(83), null, null,
     format('insert into public.customers (full_name, phone, referred_by, referred_at, referral_source, referral_code_used, created_at) values (%L, %L, %L::uuid, now() - interval ''1 day'', ''affiliate_link'', %L, now() - interval ''1 day'')',
            'T484 E Old', pg_temp.ph(83), pg_temp.fx('a'), pg_temp.code('a')), 'already_registered', 0),
  -- a number typed with spaces, and with dashes
  ('spaced',       'anon', pg_temp.code('a'), 'T484', 'E Spaced',    '+61 2 5550 ' || right(pg_temp.ph(84), 4), null, null, null, 'registered', 1),
  ('dashed',       'anon', pg_temp.code('a'), 'T484', 'E Dashed',    '+61-2-5550-' || right(pg_temp.ph(85), 4), null, null, null, 'registered', 1);
create temp table e_out as
select i.k, i.outcome, i.marks,
       pg_temp.e_run('old', i.who, i.code, i.first, i.last, i.phone, i.email, null, i.hp, i.setup) as o,
       pg_temp.e_run('wrap', i.who, i.code, i.first, i.last, i.phone, i.email, 'r-page-2026-11', i.hp, i.setup) as w,
       pg_temp.e_run('wrap', i.who, i.code, i.first, i.last, i.phone, i.email, 'r-page-2099-01', i.hp, i.setup) as u
  from e_in i;
select pg_temp.check((e.o -> 'answer') = (e.w -> 'answer') and (e.o -> 'answer') = (e.u -> 'answer')
    and (case when e.outcome is null then e.o -> 'answer' ? 'error' or e.o -> 'answer' ->> 'ok' = 'false'
              else e.o -> 'answer' ->> 'outcome' = e.outcome end),
  format('E1 %s: the same answer from both functions (and with an unknown notice): %s', e.k, e.o -> 'answer'))
  from e_out e order by e.k;
select pg_temp.check((e.o -> 'changes') - 'counts' = (e.w -> 'changes') - 'counts'
    and (e.o -> 'changes' -> 'counts') = (e.w -> 'changes' -> 'counts') - 'public.referral_phone_notices'
    and coalesce((e.w -> 'changes' -> 'counts' ->> 'public.referral_phone_notices')::int, 0) = e.marks
    and (e.o -> 'changes') = (e.u -> 'changes')
    and (e.o -> 'changes' ->> 'seqs_moved')::int = 0 and (e.w -> 'changes' ->> 'seqs_moved')::int = 0,
  format('E2 %s: the same rows made (customers, events, checks, Audit Log, every table''s count) but %s mark; no sequence moved: %s',
         e.k, e.marks, (e.w -> 'changes') - 'customers' - 'events' - 'checks' - 'audit'))
  from e_out e order by e.k;
select pg_temp.check((select string_agg(e.k || '=' || coalesce(e.o -> 'answer' ->> 'outcome', e.o -> 'answer' ->> 'error', e.o -> 'answer' ->> 'message'), ' ' order by e.k)
                        from e_out e
                       where e.k in ('phone_review', 'no_name', 'ambiguous', 'phone_limit', 'phone_tries', 'link_limit', 'unknown_code', 'suspended', 'inactive'))
                     = 'ambiguous=P0001 inactive=This referral link is not accepting new registrations right now. Please contact Energia. '
                       || 'link_limit=This referral link has had many registrations in the last hour. Please try again later or contact Energia. '
                       || 'no_name=P0001 phone_limit=P0001 '
                       || 'phone_review=P0001 phone_tries=Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia. '
                       || 'suspended=This referral link is not accepting new registrations right now. Please contact Energia. '
                       || 'unknown_code=This referral link is not accepting new registrations right now. Please contact Energia.'
    and (select e.o -> 'answer' ->> 'message' from e_out e where e.k = 'phone_review') like 'CUSTOMER_PHONE_REVIEW%'
    and (select e.o -> 'answer' ->> 'message' from e_out e where e.k = 'ambiguous') = 'AMBIGUOUS_CUSTOMER_MATCH'
    and (select e.o -> 'answer' ->> 'message' from e_out e where e.k = 'phone_limit') like 'CUSTOMER_PHONE_LIMIT%'
    and (select e.o -> 'answer' ->> 'message' from e_out e where e.k = 'no_name') = 'Please enter your name'
    and (select (e.o -> 'changes' -> 'events') @> jsonb_build_array(jsonb_build_array(pg_temp.code('a'), pg_temp.fx('a'), pg_temp.ph(52), 'self', false))
           from e_out e where e.k = 'self')
    and (select (e.o -> 'changes' -> 'events') @> jsonb_build_array(jsonb_build_array(pg_temp.code('a'), pg_temp.fx('a'), pg_temp.ph(0), 'self_known', false))
           from e_out e where e.k = 'self_known'),
  'E3 the inputs reach the outcomes they stand for (the errors, the limits, the rejected links, a try as herself and herself on file)');

-- ═════ P The proof ═════
select pg_temp.check(pg_temp.proof(x.k || '_login', x.k) = x.want, format('P1 %s: %s (%s)', x.k, x.want, pg_temp.proof(x.k || '_login', x.k)))
  from (values ('a', 'own_record'), ('b', 'own_record'), ('claim', 'claim_resolved'), ('staffclaim', 'claim_resolved'),
               ('letin', 'null'), ('later', 'null'), ('staleclaim', 'null'), ('same', 'same_person'), ('stalesame', 'null'),
               ('linked', 'same_person'), ('open', 'null'), ('email', 'verified_email'), ('unverified', 'null'),
               ('diffmail', 'null'), ('chain', 'own_record'), ('chainsame', 'same_person'), ('disabled', 'null'),
               ('relink', 'own_record'), ('nodecider', 'null'), ('nodeclink', 'null'), ('otherrec', 'null'),
               ('otherlink', 'null'), ('nearchain', 'null')) x(k, want);
select pg_temp.check(pg_temp.proof('a_login', 'b') = 'null' and pg_temp.proof('b_login', 'a') = 'null'
    and pg_temp.proof('claim_login', 'a') = 'null' and pg_temp.proof('nolink', 'a') = 'null' and pg_temp.proof('owner', 'claim') = 'null',
  'P2 another login''s pair, a login with no account and staff: not proven');
-- Unlink (an Owner), then the same login's next account, made later: not proven; once its email is verified (the
-- record holds the login's email): verified_email.
do $$ begin
  perform pg_temp.as_owner();
  perform public.unlink_affiliate_account(pg_temp.fx('relink'), 'T484 unlink');
  perform pg_temp.as_server();
  set local session_replication_role = replica;
  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status, created_at)
  values (pg_temp.fx('relink_login'), pg_temp.fx('relink'), pg_temp.fx('relink_aff'), 'claimed', now() + interval '1 hour');
  set local session_replication_role = origin;
end $$;
select pg_temp.put('p3_unlinked', pg_temp.proof('relink_login', 'relink'));
update public.affiliate_accounts set email_verified_at = now() + interval '2 hours' where auth_user_id = pg_temp.fx('relink_login');
select pg_temp.check(pg_temp.tx('p3_unlinked') = 'null' and pg_temp.proof('relink_login', 'relink') = 'verified_email',
  'P3 after an Owner''s Unlink, the login''s next account (made later) is not proven by the old record''s making; verifying its email proves it');

-- ═════ N The rule on My Network ═════
-- The referrals were all made in this transaction (one created_at); spread them a second apart (by name) so the row
-- order the comparison with 480's body checks (created_at, newest first) is fixed. Their marks are written already.
update public.customers c set created_at = now() - make_interval(secs => x.n)
  from (select id, row_number() over (order by full_name) as n from public.customers
         where full_name like 'T484 %' and referred_by is not null and deleted_at is null) x
 where c.id = x.id;
-- A referral set by staff, a Tier 2 customer under the told one, and stored values that are no number (484's
-- first draft's AFF- placeholder and an imported LEGACY one: written with triggers off, as the phone policy refuses
-- them now) carrying a mark that cannot hold.
insert into public.customers (full_name, phone, referred_by) values ('T484 Staffset', pg_temp.ph(45), pg_temp.fx('a'));
insert into public.customers (full_name, phone, referred_by)
  select 'T484 Tiertwo', pg_temp.ph(46), c.id from public.customers c where c.full_name = 'T484 Told';
insert into public.customers (full_name, phone, referred_by) values ('T484 Placeholder', pg_temp.ph(76), pg_temp.fx('a')),
                                                                    ('T484 Legacy', pg_temp.ph(77), pg_temp.fx('a'));
insert into public.referral_phone_notices (customer_id, referrer_customer_id, phone, notice_version, referral_code)
  select c.id, pg_temp.fx('a'), pg_temp.ph(x.n), 'r-page-2026-11', pg_temp.code('a')
    from (values ('T484 Placeholder', 76), ('T484 Legacy', 77)) x(nm, n) join public.customers c on c.full_name = x.nm;
set local session_replication_role = replica;
update public.customers set phone = 'AFF-' || pg_temp.tx('sfx') where full_name = 'T484 Placeholder';
update public.customers set phone = 'LEGACY-NO-PHONE-CUST-000101' where full_name = 'T484 Legacy';
set local session_replication_role = origin;
select pg_temp.put('net_a', pg_temp.net('a_login')::text), pg_temp.put('net_b', pg_temp.net('b_login')::text);
select pg_temp.check(pg_temp.t1('a_login', 'T484 Told') = pg_temp.ph(40) and pg_temp.t1('a_login', 'T484 Household') = pg_temp.ph(41)
    and pg_temp.t1('a_login', 'T484 Sharedtold') = pg_temp.ph(48) and pg_temp.t1('a_login', 'T484 Positional') = pg_temp.ph(71)
    and pg_temp.t1('a_login', 'T484 Signedin') = pg_temp.ph(72),
  'N1 A (own_record, active): each told referral shows the number typed; the household one (phone_shared) at once');
select pg_temp.check((select bool_and(pg_temp.t1('a_login', nm) = 'null')
                        from unnest(array['T484 Seminar', 'T484 Seminar Two', 'T484 Unknown', 'T484 Nonotice', 'T484 Notice blank', 'T484 Notice spaces',
                                          'T484 Notice upper', 'T484 Notice lead', 'T484 Notice trail', 'T484 Notice suffix', 'T484 Staffset',
                                          'T484 Placeholder', 'T484 Legacy']) nm)
    and pg_temp.tx('net_a') !~ 'AFF-|LEGACY'
    and (select bool_and(strpos(pg_temp.tx('net_a'), substr(pg_temp.ph(n), 2)) = 0) from unnest(array[0, 42, 43, 44, 45, 46, 65, 66, 67, 68, 69, 70, 76, 77]) n),
  'N2 no number for the seminar website''s, an unlisted notice''s, staff''s, the placeholder''s or the legacy row''s: the key there, null; none of those numbers anywhere');
select pg_temp.check((select bool_and(r ? 'phone') from jsonb_array_elements(pg_temp.tx('net_a')::jsonb -> 'tier1') r)
    and (select bool_and(not (r ? 'phone')) from jsonb_array_elements(pg_temp.tx('net_a')::jsonb -> 'tier2') r)
    and jsonb_array_length(pg_temp.tx('net_a')::jsonb -> 'tier2') = 1,
  'N3 every Tier 1 row has the key; Tier 2 has none, and its number is nowhere (N2)');
select pg_temp.check(pg_temp.t1('b_login', 'T484 Btold') = pg_temp.ph(47) and pg_temp.tx('net_b') !~ 'T484 Told|T484 Household'
    and strpos(pg_temp.tx('net_b'), substr(pg_temp.ph(40), 2)) = 0 and strpos(pg_temp.tx('net_a'), substr(pg_temp.ph(47), 2)) = 0
    and pg_temp.t1('b_login', 'T484 E Own') = 'norow',
  'N4 B sees its own told referral, nothing of A''s; A nothing of B''s');
select pg_temp.check(pg_temp.t1('claim_login', 'T484 Claimtold') = pg_temp.ph(33) and pg_temp.t1('unverified_login', 'T484 Unvtold') = 'null',
  'N5 a told referral under a proven login (claim_resolved) shows; under a login that is not proven (an unverified phone join): none');
update public.customer_affiliates set manually_suspended = true, status = 'suspended_manual' where id = pg_temp.fx('a_aff');
select pg_temp.put('n6_susp', pg_temp.t1('a_login', 'T484 Told') || ' ' || pg_temp.t1('a_login', 'T484 Household'));
set local session_replication_role = replica;   -- lifting a suspension queues a WhatsApp otherwise
update public.customer_affiliates set manually_suspended = false, status = 'active' where id = pg_temp.fx('a_aff');
set local session_replication_role = origin;
update public.customer_affiliates set status = 'soft_deleted', deleted_at = now() where id = pg_temp.fx('a_aff');
select pg_temp.put('n6_removed', pg_temp.t1('a_login', 'T484 Told'));
update public.customer_affiliates set status = 'inactive', deleted_at = null where id = pg_temp.fx('a_aff');
select pg_temp.put('n6_inactive', pg_temp.t1('a_login', 'T484 Told'));
update public.customer_affiliates set status = 'active' where id = pg_temp.fx('a_aff');
select pg_temp.check(pg_temp.tx('n6_susp') = 'null null' and pg_temp.tx('n6_removed') = 'null' and pg_temp.tx('n6_inactive') = 'null'
    and pg_temp.t1('a_login', 'T484 Told') = pg_temp.ph(40),
  'N6 suspended, removed or inactive: no number (the rows still listed); active again: shown');
select pg_temp.check(pg_temp.net(x.who) = jsonb_build_object('error', 'P0001' || chr(9) || 'Not an affiliate account'),
  'N7 ' || x.label || ': "Not an affiliate account", as before')
  from (values ('disabled_login', 'a disabled portal account'), ('nolink', 'a login with no account'), ('owner', 'an Owner'),
               ('service', 'the service role'), ('server', 'the server')) x(who, label);
select pg_temp.check(pg_temp.state(pg_temp.try_as('anon', 'select public.affiliate_portal_network()::text')) = '42501',
  'N8 signed out cannot call My Network (42501)');
-- 480's body on the same records: every other key and value, and the order of the rows.
savepoint n9;
select pg_temp.exec(pg_temp.apn480_def());
select pg_temp.md5_of('affiliate_portal_network()') as n9_md5, pg_temp.net('a_login')::text as n9_a, pg_temp.net('b_login')::text as n9_b,
       pg_temp.net('claim_login')::text as n9_c \gset
rollback to savepoint n9;
select pg_temp.check(md5(pg_temp.apn480_def()) = 'd1c387fb852392da041b5d8207655879' and :'n9_md5' = 'd1c387fb852392da041b5d8207655879'
    and (select bool_and(
          (select jsonb_build_object('tier1', (select coalesce(jsonb_agg(r - 'phone' order by n), '[]') from jsonb_array_elements(d -> 'tier1') with ordinality t(r, n)),
                                     'tier2', d -> 'tier2') from (select pg_temp.net(x.who) as d) z) = x.base::jsonb)
           from (values ('a_login', :'n9_a'), ('b_login', :'n9_b'), ('claim_login', :'n9_c')) x(who, base))
    and (select bool_and((select array_agg(k order by k collate "C") from jsonb_object_keys(r) k)
                         = array['booking_at', 'booking_state', 'customer_name', 'joined_at', 'phone', 'purchases', 'referral_date', 'tier',
                                 'total_spent', 'your_commission'])
           from jsonb_array_elements(pg_temp.net('a_login') -> 'tier1') r)
    and (select bool_and((select array_agg(k order by k collate "C") from jsonb_object_keys(r) k)
                         = array['booking_at', 'booking_state', 'customer_name', 'joined_at', 'parent_name', 'purchases', 'referral_date', 'tier',
                                 'total_spent', 'your_commission'])
           from jsonb_array_elements(pg_temp.net('a_login') -> 'tier2') r),
  'N9 against 480''s body (its text md5 d1c387fb, installed for the calls and undone) on the same records: Tier 1 rows equal but for ''phone'', in the same order; Tier 2 the same; the keys are 480''s and ''phone'' on Tier 1 only');

-- ═════ R After sign-up ═════
-- Correct Referrer (an Owner): to B, none there and gone from A; back, shown again.
do $$ begin perform pg_temp.as_owner();
  perform public.reassign_customer_referrer((select id from public.customers where full_name = 'T484 Told'), pg_temp.fx('b'), 'T484 move');
  perform pg_temp.as_server(); end $$;
select pg_temp.put('r1', pg_temp.t1('b_login', 'T484 Told') || ' ' || pg_temp.t1('a_login', 'T484 Told'));
do $$ begin perform pg_temp.as_owner();
  perform public.reassign_customer_referrer((select id from public.customers where full_name = 'T484 Told'), pg_temp.fx('a'), 'T484 back');
  perform pg_temp.as_server(); end $$;
select pg_temp.check(pg_temp.tx('r1') = 'null norow' and pg_temp.t1('a_login', 'T484 Told') = pg_temp.ph(40),
  'R1 Correct Referrer: under the new referrer the row shows no number (the mark names A); moved back: shown again');
-- Staff change the number: none (only the number typed shows, Q3); changed back: shown.
update public.customers set phone = pg_temp.ph(78) where full_name = 'T484 Told';
select pg_temp.put('r2', pg_temp.t1('a_login', 'T484 Told'));
update public.customers set phone = pg_temp.ph(40) where full_name = 'T484 Told';
select pg_temp.check(pg_temp.tx('r2') = 'null' and pg_temp.t1('a_login', 'T484 Told') = pg_temp.ph(40),
  'R2 the number changed by staff: none; the number typed again: shown');
-- Hide (the opt-out), exactly as the header writes it; show again; refused where there is no mark.
select pg_temp.exec(pg_temp.for_customer(pg_temp.hide_sql(), (select id from public.customers where full_name = 'T484 Told')));
select pg_temp.put('r3_hidden', pg_temp.t1('a_login', 'T484 Told'));
select pg_temp.put('r3_audit', (select count(*)::text from public.audit_logs l join public.customers c on c.id = l.record_id
                                 where c.full_name = 'T484 Told' and l.action = 'referral_phone_hidden' and l.new_data ->> 'marks_withdrawn' = '1'));
select pg_temp.exec(pg_temp.for_customer(pg_temp.show_sql(), (select id from public.customers where full_name = 'T484 Told')));
savepoint r3;
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.for_customer(pg_temp.hide_sql(), (select id from public.customers where full_name = 'T484 Seminar')));
\set ON_ERROR_STOP on
\set r3_msg :LAST_ERROR_MESSAGE
rollback to savepoint r3;
select pg_temp.check(pg_temp.tx('r3_hidden') = 'null' and pg_temp.tx('r3_audit') = '1' and pg_temp.t1('a_login', 'T484 Told') = pg_temp.ph(40)
    and exists (select 1 from public.audit_logs l join public.customers c on c.id = l.record_id
                 where c.full_name = 'T484 Told' and l.action = 'referral_phone_shown_again')
    and :'r3_msg' like '484 hide: % has no mark to withdraw%nothing changed'
    and (select count(*) from public.referral_phone_notices n join public.customers c on c.id = n.customer_id where c.full_name = 'T484 Told') = 1,
  'R3 the header''s hide block: none, with an Audit Log entry, the mark kept; its show block: shown again; refused where there is no mark: ' || :'r3_msg');
-- As written (the zero id), each block changes nothing. A household number (Q3), asked by the other person who holds
-- it: T484 Existing holds the number T484 Household typed (phone_shared) and has no mark of her own. Without the
-- number: refused; by number (typed with spaces): hidden on the row that shows it, with an Audit Log row there naming
-- her; her show again: shown. Then Household hides her own, Existing asks by number again (hidden already: recorded),
-- and Household's show again changes nothing (someone else asked too): the number stays hidden. All undone after.
savepoint r3z;
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.hide_sql());
\set ON_ERROR_STOP on
\set r3z_hide :LAST_ERROR_MESSAGE
rollback to savepoint r3z;
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.show_sql());
\set ON_ERROR_STOP on
\set r3z_show :LAST_ERROR_MESSAGE
rollback to savepoint r3z;
select id as r3b_existing from public.customers where full_name = 'T484 Existing' \gset
select id as r3b_house from public.customers where full_name = 'T484 Household' \gset
savepoint r3b;
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.for_customer(pg_temp.hide_sql(), :'r3b_existing'));
\set ON_ERROR_STOP on
\set r3b_msg :LAST_ERROR_MESSAGE
rollback to savepoint r3b;
select pg_temp.exec(pg_temp.with_phone(pg_temp.for_customer(pg_temp.hide_sql(), :'r3b_existing'), '+61 2 5550 ' || right(pg_temp.ph(41), 4)));
select pg_temp.t1('a_login', 'T484 Household') as r3b_hidden,
       (select count(*) from public.audit_logs l where l.record_id = :'r3b_house' and l.action = 'referral_phone_hidden'
           and l.new_data ->> 'asked_by' = :'r3b_existing' and l.new_data ->> 'marks_withdrawn' = '1') as r3b_audit \gset
select pg_temp.exec(pg_temp.for_customer(pg_temp.show_sql(), :'r3b_existing'));
select pg_temp.t1('a_login', 'T484 Household') as r3b_shown,
       (select count(*) from public.audit_logs l where l.record_id = :'r3b_house' and l.action = 'referral_phone_shown_again'
           and l.new_data ->> 'asked_by' = :'r3b_existing') as r3b_audit2 \gset
select pg_temp.exec(pg_temp.for_customer(pg_temp.hide_sql(), :'r3b_house'));
select pg_temp.exec(pg_temp.with_phone(pg_temp.for_customer(pg_temp.hide_sql(), :'r3b_existing'), pg_temp.ph(41)));
select (select count(*) from public.audit_logs l where l.record_id = :'r3b_house' and l.action = 'referral_phone_hidden'
           and l.new_data ->> 'asked_by' = :'r3b_existing' and l.new_data ->> 'marks_withdrawn' = '0'
           and jsonb_array_length(l.new_data -> 'hidden_already') = 1) as r3b_already \gset
savepoint r3c;
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.for_customer(pg_temp.show_sql(), :'r3b_house'));
\set ON_ERROR_STOP on
\set r3c_msg :LAST_ERROR_MESSAGE
rollback to savepoint r3c;
select pg_temp.t1('a_login', 'T484 Household') as r3c_hidden \gset
rollback to savepoint r3b;
select pg_temp.check(:'r3z_hide' like '484 hide: 00000000-0000-0000-0000-000000000000 is not a customer%nothing changed'
    and :'r3z_show' = '484 show: 00000000-0000-0000-0000-000000000000 has no mark withdrawn at their request; nothing changed'
    and :'r3b_msg' like '484 hide: % has no mark to withdraw (their number may still show on another record: check by number, then set c_phone); nothing changed'
    and :'r3b_hidden' = 'null' and :'r3b_audit' = '1' and :'r3b_shown' = pg_temp.ph(41) and :'r3b_audit2' = '1' and :'r3b_already' = '1'
    and :'r3c_msg' like '484 show: 1 mark(s) that % asked to hide, someone else also asked to hide%nothing changed'
    and :'r3c_hidden' = 'null' and pg_temp.t1('a_login', 'T484 Household') = pg_temp.ph(41),
  'R3b as written each block changes nothing; a household number asked by the other person who holds it: refused without the number, hidden by number (typed with spaces) on the row that shows it, an Audit Log row there naming her, shown again by her show; after the typist hid it too and her second request (hidden already) was recorded, the typist''s show changes nothing: ' || :'r3c_msg');
-- Delete and restore (an Owner).
do $$ begin perform pg_temp.as_owner();
  perform public.delete_customer((select id from public.customers where full_name = 'T484 Positional'), 'T484 Positional', 'T484 check');
  perform pg_temp.as_server(); end $$;
select pg_temp.put('r4_deleted', pg_temp.t1('a_login', 'T484 Positional'));
do $$ begin perform pg_temp.as_owner();
  perform public.restore_customer((select id from public.customers where full_name = 'T484 Positional'));
  perform pg_temp.as_server(); end $$;
select pg_temp.check(pg_temp.tx('r4_deleted') = 'norow' and pg_temp.t1('a_login', 'T484 Positional') = pg_temp.ph(71),
  'R4 deleted: not listed; restored: listed with its number again');
-- A hard delete takes the marks with it.
insert into public.customers (full_name, phone, referred_by) values ('T484 Gone', pg_temp.ph(79), pg_temp.fx('a'));
insert into public.referral_phone_notices (customer_id, referrer_customer_id, phone, notice_version, referral_code)
  select c.id, pg_temp.fx('a'), pg_temp.ph(79), 'r-page-2026-11', pg_temp.code('a') from public.customers c where c.full_name = 'T484 Gone';
select pg_temp.put('r5_gone', (select c.id::text from public.customers c where c.full_name = 'T484 Gone'));
delete from public.customers where full_name = 'T484 Gone';
select pg_temp.check(not exists (select 1 from public.referral_phone_notices n where n.customer_id = pg_temp.tx('r5_gone')::uuid),
  'R5 a hard delete of the customer takes its marks (on delete cascade)');
-- Merges (an Owner, merge_customer_records). The told record retired into an older record of the same person, same
-- number, under A: the mark follows, the kept record shows the number; another number there: none.
insert into public.customers (full_name, phone, referred_by, created_at) values ('T484 Keep', pg_temp.ph(40), pg_temp.fx('a'), now() - interval '30 days');
do $$ declare v jsonb; begin perform pg_temp.as_owner();
  v := public.merge_customer_records((select id from public.customers where full_name = 'T484 Keep'),
                                     (select id from public.customers where full_name = 'T484 Told'), 'T484 same person', gen_random_uuid());
  perform pg_temp.as_server(); perform pg_temp.put('r6_merge', v::text); end $$;
select pg_temp.put('r6_keep', pg_temp.t1('a_login', 'T484 Keep'));
update public.customers set phone = pg_temp.ph(80) where full_name = 'T484 Keep';
select pg_temp.put('r6_other', pg_temp.t1('a_login', 'T484 Keep'));
update public.customers set phone = pg_temp.ph(40) where full_name = 'T484 Keep';
select pg_temp.check(pg_temp.tx('r6_merge')::jsonb ->> 'success' = 'true' and pg_temp.tx('r6_keep') = pg_temp.ph(40) and pg_temp.tx('r6_other') = 'null'
    and pg_temp.t1('a_login', 'T484 Told') = 'norow'
    and (select count(*) from public.referral_phone_notices n join public.customers c on c.id = n.customer_id where c.full_name = 'T484 Keep') = 1,
  'R6 the told record merged into another of the same person: the mark moved with it; the kept record shows the typed number; with another number: none');
-- Two marked records merged, one of them withdrawn: hidden; no withdrawal: the kept one's own number.
select pg_temp.signup('wrap', 'anon', pg_temp.code('a'), 'T484', 'Twin', pg_temp.ph(81), null, 'r-page-2026-11', null),
       pg_temp.signup('wrap', 'anon', pg_temp.code('a'), 'T484', 'Twinb', pg_temp.ph(82), null, 'r-page-2026-11', null);
update public.referral_phone_notices n set withdrawn_at = now() from public.customers c where c.id = n.customer_id and c.full_name = 'T484 Twinb';
do $$ declare v jsonb; begin perform pg_temp.as_owner();
  v := public.merge_customer_records((select id from public.customers where full_name = 'T484 Twin'),
                                     (select id from public.customers where full_name = 'T484 Twinb'), 'T484 twins', gen_random_uuid());
  perform pg_temp.as_server(); perform pg_temp.put('r7_merge', v::text); end $$;
select pg_temp.put('r7_hidden', pg_temp.t1('a_login', 'T484 Twin'));
update public.referral_phone_notices n set withdrawn_at = null from public.customers c where c.id = n.customer_id and c.full_name = 'T484 Twin';
select pg_temp.check(pg_temp.tx('r7_merge')::jsonb ->> 'success' = 'true' and pg_temp.tx('r7_hidden') = 'null'
    and pg_temp.t1('a_login', 'T484 Twin') = pg_temp.ph(81)
    and (select count(*) from public.referral_phone_notices n join public.customers c on c.id = n.customer_id where c.full_name = 'T484 Twin') = 2,
  'R7 two marked records merged (no key to trip): a withdrawn mark on either hides the number; none withdrawn: the kept record''s own typed number');
-- A's own record merged into an older one (A2): the referrals, the affiliate record, the login and the marks follow;
-- the login is proven through the merge (its record was made with its account). Production has this shape from a
-- merge by hand (26 Sep 2026), and 437's Link to this customer still makes it (R8b). Since 486 that merge by hand is
-- refused (R8a), so R8's merge runs with production's merge preview of 2 Nov 2026 swapped in for it alone: rebuilt
-- from the installed text by cutting 486's block out by position, from its first comment line to its "end;" before
-- the return, as event-website-439 does (so wording inside the block may change), and required to be the text 486's
-- UNDO puts back (md5 f66c9d63; where 486 is not in, the installed text is that already); then the installed text
-- put back.
insert into public.customers (full_name, phone, created_at) values ('T484 Aff a2', pg_temp.ph(90), now() - interval '60 days');
-- R8a: that merge by hand (an Owner), in a block that undoes it should it go through.
do $$ declare v jsonb; v_msg text; begin
  begin
    perform pg_temp.as_owner();
    v := public.merge_customer_records((select id from public.customers where full_name = 'T484 Aff a2'), pg_temp.fx('a'), 'T484 referrer duplicate', gen_random_uuid());
    v_msg := 'merged (undone here): ' || v::text;
    raise exception using errcode = 'P0E84';
  exception when sqlstate 'P0E84' then null;
            when others then v_msg := sqlerrm;
  end;
  perform pg_temp.as_server(); perform pg_temp.put('r8a_merge', v_msg); end $$;
select pg_temp.check(pg_temp.tx('r8a_merge') = 'This merge needs review first: The duplicate holds the portal login, the affiliate record and '
                       || (select count(*) from public.referral_phone_notices n where n.referrer_customer_id = pg_temp.fx('a'))
                       || ' /r/ phone-notice mark(s) naming it as referrer; the record to keep has neither a portal login nor an affiliate record. '
                       || 'A merge decides that two records are one person, not whose login it is: keep the affiliate''s record and merge the other one into it.'
    and (select c.deleted_at is null from public.customers c where c.id = pg_temp.fx('a'))
    and exists (select 1 from public.affiliate_accounts x where x.auth_user_id = pg_temp.fx('a_login') and x.customer_id = pg_temp.fx('a'))
    and exists (select 1 from public.customer_affiliates f where f.id = pg_temp.fx('a_aff') and f.customer_id = pg_temp.fx('a'))
    and not exists (select 1 from public.audit_logs l where l.action = 'customers_merged' and l.new_data ->> 'merged_from' = pg_temp.fx('a')::text)
    and pg_temp.t1('a_login', 'T484 Keep') = pg_temp.ph(40),
  'R8a since 486 the same merge by hand (keeping A2, with neither a portal login nor an affiliate record, and retiring A''s record) is refused and changes nothing: '
  || pg_temp.tx('r8a_merge'));
-- R8: the merge, with production's preview of 2 Nov 2026 swapped in for it alone.
do $r8$
declare v_inst text := pg_get_functiondef('public.preview_customer_merge(uuid,uuid)'::regprocedure); v_def text; v jsonb;
        v_from int; v_to int;
begin
  v_from := strpos(v_inst, E'\n\n  -- 486 (the Owner, 2 Nov 2026):');
  v_to := strpos(v_inst, E'\n  end;\n\n  return jsonb_build_object(');
  v_def := case when v_from > 0 and v_to > v_from then left(v_inst, v_from - 1) || substr(v_inst, v_to + length(E'\n  end;'))
                else v_inst end;
  perform pg_temp.put('r8_preview', md5(v_inst) || ' ' || md5(v_def));
  if md5(v_def) is distinct from 'f66c9d63369ef3b831ca74906a99b587' then
    v := jsonb_build_object('success', false, 'error', 'production''s preview of 2 Nov 2026 was not rebuilt from the installed text; no merge');
  else
    execute v_def;
    begin
      perform pg_temp.as_owner();
      v := public.merge_customer_records((select id from public.customers where full_name = 'T484 Aff a2'), pg_temp.fx('a'), 'T484 referrer duplicate', gen_random_uuid());
    exception when others then v := jsonb_build_object('success', false, 'error', sqlerrm);
    end;
    perform pg_temp.as_server();
    execute v_inst;
  end if;
  perform pg_temp.put('r8_merge', v::text);
  perform pg_temp.put('r8_back', md5(pg_get_functiondef('public.preview_customer_merge(uuid,uuid)'::regprocedure)));
end $r8$;
select pg_temp.check(pg_temp.tx('r8_merge')::jsonb ->> 'success' = 'true'
    and public.affiliate_login_link_proof(pg_temp.fx('a_login'), (select id from public.customers where full_name = 'T484 Aff a2')) = 'own_record'
    and pg_temp.t1('a_login', 'T484 Keep') = pg_temp.ph(40) and pg_temp.t1('a_login', 'T484 Household') = pg_temp.ph(41)
    and pg_temp.t1('a_login', 'T484 Seminar') = 'null'
    and not exists (select 1 from public.referral_phone_notices n where n.referrer_customer_id = pg_temp.fx('a'))
    and split_part(pg_temp.tx('r8_preview'), ' ', 2) = 'f66c9d63369ef3b831ca74906a99b587'
    and pg_temp.tx('r8_back') = split_part(pg_temp.tx('r8_preview'), ' ', 1),
  'R8 the referrer''s record merged into another: the login and the marks follow; proven through the merge; the told numbers still show, the others still none'
  || ' (merged with production''s preview of 2 Nov 2026 swapped in, the installed one put back; md5s installed, swapped in, after: '
  || pg_temp.tx('r8_preview') || ' ' || pg_temp.tx('r8_back') || coalesce('; ' || (pg_temp.tx('r8_merge')::jsonb ->> 'error'), '') || ')');
-- R8b: the same shape made by 437's Link to this customer (an Owner's or a Manager's decision about whose login it is,
-- which 486 lets through), with the merge preview as installed: a fresh sign-up record made with its account (a login
-- and an affiliate record), with a told referral and a seminar one, linked to an older customer who has neither (and
-- an email of their own, so the Link copies none). First the preview is asked about the same merge by hand, as an
-- Owner: 486's guard alone must refuse it (duplicate_has_affiliate_account), so the Link going through is 486 letting
-- it through. Read in a savepoint, then undone: the checks after see R8's state. Its sign-up listing is put in by
-- hand, as in event-website-439 and -441: 437's own sign-up would not list this older record (no shared phone, inbox
-- or same-words name).
savepoint r8b;
select pg_temp.mk_aff('lnk', 91, '0 seconds');
select pg_temp.signup('wrap', 'anon', pg_temp.code('lnk'), 'T484', 'Lnktold', pg_temp.ph(92), null, 'r-page-2026-11', null),
       pg_temp.signup('old', 'anon', pg_temp.code('lnk'), 'T484', 'Lnkseminar', pg_temp.ph(93), null, null, null);
insert into public.customers (full_name, phone, email, created_at)
  values ('T484 Lnk older', pg_temp.ph(94), pg_temp.mail('lnkolder'), now() - interval '60 days');
insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, entered_phone, entered_name, reason, candidate_ids)
  select pg_temp.fx('lnk_login'), pg_temp.fx('lnk'), pg_temp.ph(91), 'T484 Aff lnk', 'name_match', array[c.id]
    from public.customers c where c.full_name = 'T484 Lnk older';
do $$ declare v jsonb; m uuid; k uuid; begin
  m := (select x.id from public.affiliate_signup_matches x where x.auth_user_id = pg_temp.fx('lnk_login') and x.status = 'open');
  k := (select c.id from public.customers c where c.full_name = 'T484 Lnk older');
  begin
    perform pg_temp.as_owner();
    perform pg_temp.put('r8b_byhand', coalesce((select string_agg(x ->> 'issue', ',') from jsonb_array_elements(public.preview_customer_merge(k, pg_temp.fx('lnk')) -> 'blocking') x), 'none'));
  exception when others then perform pg_temp.put('r8b_byhand', 'error: ' || sqlerrm);
  end;
  begin
    perform pg_temp.as_owner();
    v := public.link_affiliate_signup(m, k, 'T484 same person', gen_random_uuid());
  exception when others then v := jsonb_build_object('ok', false, 'error', sqlerrm);
  end;
  perform pg_temp.as_server(); perform pg_temp.put('r8b_link', v::text); end $$;
select coalesce(pg_temp.tx('r8b_link')::jsonb ->> 'ok' = 'true'
    and pg_temp.md5_of('preview_customer_merge(uuid,uuid)') = split_part(pg_temp.tx('r8_preview'), ' ', 1)
    and exists (select 1 from public.affiliate_accounts x join public.customers c on c.id = x.customer_id
                 where x.auth_user_id = pg_temp.fx('lnk_login') and c.full_name = 'T484 Lnk older')
    and exists (select 1 from public.customer_affiliates f join public.customers c on c.id = f.customer_id
                 where f.id = pg_temp.fx('lnk_aff') and c.full_name = 'T484 Lnk older')
    and (select c.deleted_at is not null from public.customers c where c.id = pg_temp.fx('lnk'))
    and public.affiliate_login_link_proof(pg_temp.fx('lnk_login'), (select c.id from public.customers c where c.full_name = 'T484 Lnk older')) = 'own_record'
    and pg_temp.t1('lnk_login', 'T484 Lnktold') = pg_temp.ph(92) and pg_temp.t1('lnk_login', 'T484 Lnkseminar') = 'null'
    and not exists (select 1 from public.referral_phone_notices n where n.referrer_customer_id = pg_temp.fx('lnk'))
    and pg_temp.tx('r8b_byhand') = 'duplicate_has_affiliate_account', false) as r8b_ok,
       coalesce(pg_temp.tx('r8b_link')::jsonb ->> 'error', pg_temp.tx('r8b_link')::jsonb ->> 'message', 'linked')
         || ' (by hand: ' || coalesce(pg_temp.tx('r8b_byhand'), 'not asked') || ')' as r8b_said \gset
rollback to savepoint r8b;
select pg_temp.check(:'r8b_ok' = 't',
  'R8b the same shape made by 437''s Link to this customer, which 486 lets through (the merge preview as installed, which refuses the same merge by hand): the login, the affiliate record, the referrals and the mark follow; proven through the merge; the told number shows, the seminar''s none: '
  || :'r8b_said');

-- ═════ X Who may ═════
select pg_temp.check(pg_temp.acl_of('affiliate_login_link_proof(uuid,uuid)') = array['postgres=X/postgres', 'service_role=X/postgres']
    and pg_temp.acl_of('affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)')
        = array['anon=X/postgres', 'authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres']
    and pg_temp.acl_of('affiliate_referral_signup(text,text,text,text,text,text)')
        = array['anon=X/postgres', 'authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres']
    and pg_temp.acl_of('affiliate_portal_network()') = array['authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres']
    and (select array_agg(x::text order by x::text) from pg_class c, unnest(c.relacl) x where c.oid = 'public.referral_phone_notices'::regclass)
        = array['postgres=arwdDxtm/postgres', 'service_role=r/postgres']
    and (select c.relrowsecurity and not c.relforcerowsecurity from pg_class c where c.oid = 'public.referral_phone_notices'::regclass)
    and not exists (select 1 from pg_policy p where p.polrelid = 'public.referral_phone_notices'::regclass),
  'X1 the grants, as sets: the proof the owner''s and the service role''s; the wrapper as affiliate_referral_signup; My Network as before; the marks: the owner''s, the service role reads; row level security on, no policy');
select pg_temp.check(pg_temp.state(pg_temp.try_as(w, x.q)) = '42501', format('X2 %s cannot %s (42501)', w, x.what))
  from unnest(array['anon', 'a_login', 'plain']) w,
       (values ('call the proof', format('select public.affiliate_login_link_proof(%L, %L)', gen_random_uuid(), gen_random_uuid())),
               ('read the marks', 'select count(*)::text from public.referral_phone_notices'),
               ('write a mark', format('insert into public.referral_phone_notices (customer_id, referrer_customer_id, phone, notice_version, referral_code) values (%L, %L, %L, %L, %L) returning id::text',
                                       gen_random_uuid(), gen_random_uuid(), '+61255500000', 'r-page-2026-11', 'X'))) x(what, q);
select pg_temp.check(pg_temp.try_as('service', 'select count(*)::text from public.referral_phone_notices') = 'ok' || chr(9) || (select count(*)::text from public.referral_phone_notices)
    and pg_temp.state(pg_temp.try_as('service', 'update public.referral_phone_notices set withdrawn_at = now() returning id::text')) = '42501'
    and pg_temp.state(pg_temp.try_as('service', 'delete from public.referral_phone_notices returning id::text')) = '42501'
    and pg_temp.state(pg_temp.try_as('service', format('select public.affiliate_login_link_proof(%L, %L)', pg_temp.fx('b_login'), pg_temp.fx('b')))) = 'ok',
  'X3 the service role reads the marks and calls the proof; it cannot change a mark');

-- ═════ G md5s, 484 twice, NUMBERS OFF, refusals ═════
select pg_temp.check(pg_temp.md5_of('affiliate_portal_network()') = '070d1b485d32cec99fa627b816a91b4a'
    and pg_temp.md5_of('affiliate_login_link_proof(uuid,uuid)') = '2484fb464733c124213b96152837a660'
    and pg_temp.md5_of('affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)') = 'f64347f2ccc993438f0cdb1655c7cc0f'
    and pg_temp.tbl_desc() = 'ec6de1ddd64fb06b87b401b9f7a55984'
    and pg_temp.md5_of('affiliate_referral_signup(text,text,text,text,text,text)') = '2942e3d4d0e8c76600c3e0ad5e15cc2b'
    and pg_temp.md5_of('customer_downline_visits(uuid)') = 'ea3f28ea932506eda6937fa687298d6d'
    and pg_temp.md5_of('current_affiliate_customer_id()') = '51695acf5f26ce3918d6003d0c980b0f'
    and pg_temp.md5_of('calcom_customer_bookings(uuid[],date)') in ('2e651a5d2367ba26bfd9e8e00d95823e', '14987e9e9f033290010042a5632bc81c')
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('affiliate_portal_network', 'affiliate_login_link_proof', 'affiliate_referral_signup_with_notice', 'affiliate_referral_signup')) = 4,
  'G1 My Network, the proof and the wrapper at 484''s AFTER md5s, the marks table at its description; affiliate_referral_signup byte for byte as before, the Downline, who the affiliate is and the booking rule unchanged; one function of each name');
\if :{?skip_install}
\else
select pg_temp.check(pg_temp.tx('pre_net_md5') = 'd1c387fb852392da041b5d8207655879'
    and not exists (select 1 from m484 m full join m484b b on b.fn = m.fn where m.fn is null or b.fn is null or b.md5 <> m.md5 or b.acl <> m.acl),
  'G2 before 484 My Network was 480''s; running 484 a second time changed no function (already this version; left alone)');
select pg_temp.check((select coalesce(array_agg(m.fn || ' ' || coalesce(b.md5, 'new') || ' -> ' || m.md5 order by m.fn), '{}') from m484 m left join b484 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5 or b.acl <> m.acl)
                     = array['affiliate_login_link_proof(uuid,uuid) new -> 2484fb464733c124213b96152837a660',
                             'affiliate_portal_network() d1c387fb852392da041b5d8207655879 -> 070d1b485d32cec99fa627b816a91b4a',
                             'affiliate_referral_signup_with_notice(text,text,text,text,text,text,text) new -> f64347f2ccc993438f0cdb1655c7cc0f']
    and not exists (select 1 from b484 b left join m484 m on m.fn = b.fn where m.fn is null),
  'G3 its first run made the proof and the wrapper and changed My Network; no other function changed, none dropped, no other grant changed');
select pg_temp.check((select after1 - 'public.referral_phone_notices' = before and after1 ->> 'public.referral_phone_notices' = '0' from r484),
  'G4 484''s self-test left no row (every table of public and auth counts the same before and after it; the new table empty)');
select pg_temp.check((select seq_after1 = seq_before from r484),
  'G5 and moved no sequence: ' || (select coalesce(string_agg(k, ', '), 'none') from r484, jsonb_each(seq_after1) e(k, v) where seq_before -> k is distinct from v));
\endif
-- Run where 484 is in: "already this version; left alone", nothing changed.
create temp table m484c as select * from pg_temp.fn_md5s();
-- (Read inside the savepoint, checked after it: a check made inside a savepoint that is rolled back loses its row.)
savepoint g6;
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
select not exists (select 1 from m484c m full join pg_temp.fn_md5s() b on b.fn = m.fn where m.fn is null or b.fn is null or b.md5 <> m.md5 or b.acl <> m.acl)
       and pg_temp.tbl_desc() = 'ec6de1ddd64fb06b87b401b9f7a55984' as g6_same,
       current_setting('lock_timeout') as g6_lt \gset
rollback to savepoint g6;
select pg_temp.check(:'g6_same' = 't' and :'g6_lt' = '2s',
  'G6 484 run again where it is in changes nothing (already this version; left alone); its lock timeout is 2 s (under the API''s 3 s for signed-out calls): ' || :'g6_lt');
-- NUMBERS OFF (My Network 480's again, the rest 484's): 484 replaces My Network again, nothing else.
savepoint g7;
select pg_temp.exec(pg_temp.apn480_def());
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
select pg_temp.md5_of('affiliate_portal_network()') as g7_md5,
       (select count(*) from m484c m full join pg_temp.fn_md5s() b on b.fn = m.fn where m.fn is null or b.fn is null or b.md5 <> m.md5 or b.acl <> m.acl) as g7_diff \gset
rollback to savepoint g7;
select pg_temp.check(:'g7_md5' = '070d1b485d32cec99fa627b816a91b4a' and :'g7_diff' = '0',
  'G7 NUMBERS OFF (UNDO''s first level) is recognised: My Network replaced again with its grants, nothing else changed');
-- The refusals: each in a savepoint, the file run, its message read, everything undone.
create temp table g_ref(k text primary key, setup text, want text);
insert into g_ref values
  ('net_changed', $q$select pg_temp.exec(regexp_replace(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure), 'AS \$function\$', 'AS $function$ -- changed by the 484 suite'))$q$,
   '484: this database is neither before 484 %found: My Network md5 %Re-read it and re-test before applying.'),
  ('half_made', 'drop function public.affiliate_login_link_proof(uuid,uuid)',
   '484: this database is neither before 484 %the proof missing, the sign-up with notice f64347f2ccc993438f0cdb1655c7cc0f).%'),
  ('proof_changed', $q$select pg_temp.exec(regexp_replace(pg_get_functiondef('public.affiliate_login_link_proof(uuid,uuid)'::regprocedure), 'AS \$function\$', 'AS $function$ -- changed by the 484 suite'))$q$,
   '484: this database is neither before 484 %the proof %'),
  ('table_shape', 'alter table public.referral_phone_notices add column t484_extra text',
   '484: this database is neither before 484 %the notices table %'),
  ('no_480_row', $q$delete from supabase_migrations.schema_migrations where version = '20261030052953'$q$,
   '484: 480 (20261030052953) is not recorded in supabase_migrations.schema_migrations. Apply 480 first (a copy built with psql: add its row as production has it).'),
  ('no_history', 'alter table supabase_migrations.schema_migrations rename to schema_migrations_t484',
   '484: 480 (20261030052953) is not recorded in supabase_migrations.schema_migrations. Apply 480 first (a copy built with psql: add its row as production has it).'),
  ('net_overload', $q$create function public.affiliate_portal_network(p_x int) returns jsonb language sql as 'select ''{}''::jsonb'$q$,
   '484: another function takes one of these names: affiliate_portal_network(integer)'),
  ('proof_overload', $q$create function public.affiliate_login_link_proof(p_x text) returns text language sql as 'select null::text'$q$,
   '484: another function takes one of these names: affiliate_login_link_proof(text)'),
  ('wrap_overload', $q$create function public.affiliate_referral_signup_with_notice(a text, b text, c text, d text, e text, f text) returns jsonb language sql as 'select null::jsonb'$q$,
   '484: another function takes one of these names: affiliate_referral_signup_with_notice(text,text,text,text,text,text)'),
  ('signup_overload', $q$create function public.affiliate_referral_signup(a text, b text, c text, d text, e text, f text, g text) returns jsonb language sql as 'select null::jsonb'$q$,
   '484: another function takes one of these names: affiliate_referral_signup(text,text,text,text,text,text,text)'),
  ('net_to_anon', 'grant execute on function public.affiliate_portal_network() to anon',
   '484: the grants of public.affiliate_portal_network() are not as read on 1 Nov 2026 (signed-in logins, the owner and the service role; not signed out)'),
  ('signup_grant', 'revoke execute on function public.affiliate_referral_signup(text,text,text,text,text,text) from anon',
   '484: the grants of public.affiliate_referral_signup(text,text,text,text,text,text) are not as read on 1 Nov 2026 (signed out, signed-in logins, the owner and the service role)'),
  ('signup_changed', $q$select pg_temp.exec(regexp_replace(pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure), 'AS \$function\$', 'AS $function$ -- changed by the 484 suite'))$q$,
   '484: public.affiliate_referral_signup(text,text,text,text,text,text) is missing or not the version this was tested against. Re-read it and re-test before applying.'),
  ('downline_changed', $q$select pg_temp.exec(regexp_replace(pg_get_functiondef('public.customer_downline_visits(uuid)'::regprocedure), 'AS \$function\$', 'AS $function$ -- changed by the 484 suite'))$q$,
   '484: public.customer_downline_visits(uuid) is missing or not the version this was tested against. Re-read it and re-test before applying.'),
  ('booking_changed', $q$select pg_temp.exec(regexp_replace(pg_get_functiondef('public.calcom_customer_bookings(uuid[],date)'::regprocedure), 'AS \$function\$', 'AS $function$ -- changed by the 484 suite'))$q$,
   '484: public.calcom_customer_bookings(uuid[],date) is missing or not the version this was tested against. Re-read it and re-test before applying.'),
  ('merge_changed', $q$select pg_temp.exec(regexp_replace(pg_get_functiondef('public.merge_customer_records(uuid,uuid,text,uuid)'::regprocedure), 'AS \$function\$', 'AS $function$ -- changed by the 484 suite'))$q$,
   '484: public.merge_customer_records(uuid,uuid,text,uuid) is missing or not the version this was tested against. Re-read it and re-test before applying.'),
  ('unlink_changed', $q$select pg_temp.exec(regexp_replace(pg_get_functiondef('public.unlink_affiliate_account(uuid,text)'::regprocedure), 'AS \$function\$', 'AS $function$ -- changed by the 484 suite'))$q$,
   '484: public.unlink_affiliate_account(uuid,text) is missing or not the version this was tested against. Re-read it and re-test before applying.'),
  ('column_renamed', 'alter table public.affiliate_accounts rename column email_verified_at to email_verified_at_t484',
   '484: these columns are missing or not as read on 1 Nov 2026: public.affiliate_accounts.email_verified_at timestamp with time zone'),
  ('write_policy', 'create policy t484_insert on public.affiliate_accounts for insert to authenticated with check (true)',
   '484: row level security is off, or a policy lets a client write, on: affiliate_accounts (as read on 1 Nov 2026: on, with SELECT policies only)'),
  ('claims_rls_off', 'alter table public.affiliate_account_claims disable row level security',
   '484: row level security is off, or a policy lets a client write, on: affiliate_account_claims (as read on 1 Nov 2026: on, with SELECT policies only)'),
  ('customers_insert', 'grant insert on public.customers to authenticated',
   '484: a client role holds a right the proof relies on it not holding %'),
  ('matches_select', 'grant select (status) on public.affiliate_signup_matches to anon',
   '484: a client role holds a right the proof relies on it not holding %'),
  ('audit_update', 'grant update on public.audit_logs to authenticated',
   '484: a client role holds a right the proof relies on it not holding %'),
  ('created_default', 'alter table public.affiliate_accounts alter column created_at set default clock_timestamp()',
   '484: customers.created_at and affiliate_accounts.created_at must both default to now() (the proof compares them), as read on 1 Nov 2026');
create temp table g_msg(k text primary key, msg text);
savepoint g_audit_update;
select pg_temp.exec((select setup from g_ref where k = 'audit_update'));
\echo 'G8 audit_update: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_audit_update;
insert into g_msg values ('audit_update', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_booking_changed;
select pg_temp.exec((select setup from g_ref where k = 'booking_changed'));
\echo 'G8 booking_changed: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_booking_changed;
insert into g_msg values ('booking_changed', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_claims_rls_off;
select pg_temp.exec((select setup from g_ref where k = 'claims_rls_off'));
\echo 'G8 claims_rls_off: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_claims_rls_off;
insert into g_msg values ('claims_rls_off', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_column_renamed;
select pg_temp.exec((select setup from g_ref where k = 'column_renamed'));
\echo 'G8 column_renamed: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_column_renamed;
insert into g_msg values ('column_renamed', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_created_default;
select pg_temp.exec((select setup from g_ref where k = 'created_default'));
\echo 'G8 created_default: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_created_default;
insert into g_msg values ('created_default', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_customers_insert;
select pg_temp.exec((select setup from g_ref where k = 'customers_insert'));
\echo 'G8 customers_insert: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_customers_insert;
insert into g_msg values ('customers_insert', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_downline_changed;
select pg_temp.exec((select setup from g_ref where k = 'downline_changed'));
\echo 'G8 downline_changed: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_downline_changed;
insert into g_msg values ('downline_changed', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_half_made;
select pg_temp.exec((select setup from g_ref where k = 'half_made'));
\echo 'G8 half_made: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_half_made;
insert into g_msg values ('half_made', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_matches_select;
select pg_temp.exec((select setup from g_ref where k = 'matches_select'));
\echo 'G8 matches_select: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_matches_select;
insert into g_msg values ('matches_select', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_merge_changed;
select pg_temp.exec((select setup from g_ref where k = 'merge_changed'));
\echo 'G8 merge_changed: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_merge_changed;
insert into g_msg values ('merge_changed', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_net_changed;
select pg_temp.exec((select setup from g_ref where k = 'net_changed'));
\echo 'G8 net_changed: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_net_changed;
insert into g_msg values ('net_changed', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_net_overload;
select pg_temp.exec((select setup from g_ref where k = 'net_overload'));
\echo 'G8 net_overload: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_net_overload;
insert into g_msg values ('net_overload', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_net_to_anon;
select pg_temp.exec((select setup from g_ref where k = 'net_to_anon'));
\echo 'G8 net_to_anon: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_net_to_anon;
insert into g_msg values ('net_to_anon', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_no_480_row;
select pg_temp.exec((select setup from g_ref where k = 'no_480_row'));
\echo 'G8 no_480_row: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_no_480_row;
insert into g_msg values ('no_480_row', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_no_history;
select pg_temp.exec((select setup from g_ref where k = 'no_history'));
\echo 'G8 no_history: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_no_history;
insert into g_msg values ('no_history', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_proof_changed;
select pg_temp.exec((select setup from g_ref where k = 'proof_changed'));
\echo 'G8 proof_changed: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_proof_changed;
insert into g_msg values ('proof_changed', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_proof_overload;
select pg_temp.exec((select setup from g_ref where k = 'proof_overload'));
\echo 'G8 proof_overload: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_proof_overload;
insert into g_msg values ('proof_overload', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_signup_changed;
select pg_temp.exec((select setup from g_ref where k = 'signup_changed'));
\echo 'G8 signup_changed: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_signup_changed;
insert into g_msg values ('signup_changed', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_signup_grant;
select pg_temp.exec((select setup from g_ref where k = 'signup_grant'));
\echo 'G8 signup_grant: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_signup_grant;
insert into g_msg values ('signup_grant', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_signup_overload;
select pg_temp.exec((select setup from g_ref where k = 'signup_overload'));
\echo 'G8 signup_overload: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_signup_overload;
insert into g_msg values ('signup_overload', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_table_shape;
select pg_temp.exec((select setup from g_ref where k = 'table_shape'));
\echo 'G8 table_shape: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_table_shape;
insert into g_msg values ('table_shape', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_unlink_changed;
select pg_temp.exec((select setup from g_ref where k = 'unlink_changed'));
\echo 'G8 unlink_changed: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_unlink_changed;
insert into g_msg values ('unlink_changed', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_wrap_overload;
select pg_temp.exec((select setup from g_ref where k = 'wrap_overload'));
\echo 'G8 wrap_overload: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_wrap_overload;
insert into g_msg values ('wrap_overload', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
savepoint g_write_policy;
select pg_temp.exec((select setup from g_ref where k = 'write_policy'));
\echo 'G8 write_policy: 484 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
\set g_err :ERROR
\set g_last :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint g_write_policy;
insert into g_msg values ('write_policy', case when :'g_err' = 'true' then :'g_last' else 'not refused' end);
select pg_temp.check(m.msg like r.want, format('G8 %s: refused, nothing changed: %s', r.k, m.msg))
  from g_ref r left join g_msg m on m.k = r.k order by r.k;
select pg_temp.check(not exists (select 1 from m484c m full join pg_temp.fn_md5s() b on b.fn = m.fn where m.fn is null or b.fn is null or b.md5 <> m.md5 or b.acl <> m.acl)
    and pg_temp.tbl_desc() = 'ec6de1ddd64fb06b87b401b9f7a55984' and exists (select 1 from supabase_migrations.schema_migrations where version = '20261030052953'),
  'G9 after the refusals everything is as it was');

-- ═════ U UNDO, as the header writes it ═════
savepoint u1;
select pg_temp.exec(pg_temp.undo1_sql());
select pg_temp.exec(pg_temp.apn480_def());
select pg_temp.md5_of('affiliate_portal_network()') as u1_md5, array_to_string(pg_temp.acl_of('affiliate_portal_network()'), ',') as u1_acl,
       pg_temp.net('b_login')::text as u1_b \gset
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.undo1_sql());
\set ON_ERROR_STOP on
\set u1_again :LAST_ERROR_MESSAGE
rollback to savepoint u1;
savepoint u1b;
select pg_temp.exec(pg_temp.undo1_sql());
select pg_temp.exec(pg_temp.apn480_def());
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
select pg_temp.md5_of('affiliate_portal_network()') as u1_on, pg_temp.net('b_login')::text as u1_on_b \gset
rollback to savepoint u1b;
select pg_temp.check(:'u1_md5' = 'd1c387fb852392da041b5d8207655879' and :'u1_acl' = 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'
    and :'u1_b' !~ '"phone"' and :'u1_again' like 'UNDO 484 (1): public.affiliate_portal_network() is not 484''s version (md5 d1c387fb852392da041b5d8207655879); nothing changed'
    and :'u1_on' = '070d1b485d32cec99fa627b816a91b4a' and :'u1_on_b'::jsonb = pg_temp.net('b_login') and pg_temp.t1('b_login', 'T484 Btold') = pg_temp.ph(47),
  'U1 level 1: My Network 480''s with its grants and no ''phone'' key; a second run stops at its guard; the file again turns the numbers back on: ' || :'u1_again');
-- Level 2: refused before level 1; refused while marks exist; with them discarded on the Owner's word, everything
-- goes and the catalogue is as before 484 (every function's md5 and grants); 484 again makes all four anew.
savepoint u2;
insert into supabase_migrations.schema_migrations (version, name, statements)
  select '20991231000000', '484_affiliate_network_shows_tier1_phone', array['t484 stand-in for 484''s text']
   where not exists (select 1 from supabase_migrations.schema_migrations where name = '484_affiliate_network_shows_tier1_phone');
select md5(array_to_string(statements, '')) as u2_m from supabase_migrations.schema_migrations where name = '484_affiliate_network_shows_tier1_phone' \gset
-- A repeated apply records a second row holding the same text: level 2 deletes both.
insert into supabase_migrations.schema_migrations (version, name, statements)
  select '20991231000001', m.name, m.statements from supabase_migrations.schema_migrations m
   where m.name = '484_affiliate_network_shows_tier1_phone';
create temp table u2_pre as
select f.fn, case when f.fn = 'affiliate_portal_network()' then 'd1c387fb852392da041b5d8207655879' else f.md5 end as md5, f.acl
  from pg_temp.fn_md5s() f
 where f.fn not in ('affiliate_login_link_proof(uuid,uuid)', 'affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)');
savepoint u2a;
\set ON_ERROR_STOP off
select pg_temp.exec(replace(pg_temp.undo2_sql(), '''<M>''', quote_literal(:'u2_m')));
\set ON_ERROR_STOP on
\set u2_before_l1 :LAST_ERROR_MESSAGE
rollback to savepoint u2a;
select pg_temp.exec(pg_temp.undo1_sql());
select pg_temp.exec(pg_temp.apn480_def());
savepoint u2b;
\set ON_ERROR_STOP off
select pg_temp.exec(replace(pg_temp.undo2_sql(), '''<M>''', quote_literal(:'u2_m')));
\set ON_ERROR_STOP on
\set u2_marks :LAST_ERROR_MESSAGE
rollback to savepoint u2b;
set local lock_timeout = '10s';
select pg_temp.exec(replace(replace(pg_temp.undo2_sql(), '''<M>''', quote_literal(:'u2_m')),
                            'c_discard_marks constant boolean := false', 'c_discard_marks constant boolean := true'));
select (select count(*) from u2_pre p full join pg_temp.fn_md5s() f on f.fn = p.fn where p.fn is null or f.fn is null or f.md5 <> p.md5 or f.acl <> p.acl) as u2_diff,
       to_regclass('public.referral_phone_notices') is null as u2_no_table,
       (select count(*) from supabase_migrations.schema_migrations where name = '484_affiliate_network_shows_tier1_phone') as u2_rows,
       pg_temp.net('b_login')::text as u2_b, current_setting('lock_timeout') as u2_lt \gset
\ir ../../../supabase/484_affiliate_network_shows_tier1_phone.sql
select pg_temp.md5_of('affiliate_portal_network()') = '070d1b485d32cec99fa627b816a91b4a' and pg_temp.tbl_desc() = 'ec6de1ddd64fb06b87b401b9f7a55984'
       and pg_temp.md5_of('affiliate_login_link_proof(uuid,uuid)') = '2484fb464733c124213b96152837a660'
       and pg_temp.md5_of('affiliate_referral_signup_with_notice(text,text,text,text,text,text,text)') = 'f64347f2ccc993438f0cdb1655c7cc0f'
       and (select count(*) from public.referral_phone_notices) = 0 as u2_again \gset
rollback to savepoint u2;
select pg_temp.check(:'u2_before_l1' like 'UNDO 484 (2): My Network is not 480''s (run level 1 first)%nothing changed'
    and :'u2_marks' like 'UNDO 484 (2): referral_phone_notices holds % mark(s)%nothing changed'
    and :'u2_diff' = '0' and :'u2_no_table' = 't' and :'u2_rows' = '0' and :'u2_b' !~ '"phone"' and :'u2_again' = 't'
    and :'u2_lt' = '2s',
  'U2 level 2 (its lock timeout 2 s): refused before level 1 and while marks exist; with them discarded, the catalogue as before 484 (every function''s md5 and grants), the table and both history rows (a repeated apply''s too) gone; 484 again makes all four: ' || :'u2_marks');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 484 checks passed.';
end $$;
rollback;
