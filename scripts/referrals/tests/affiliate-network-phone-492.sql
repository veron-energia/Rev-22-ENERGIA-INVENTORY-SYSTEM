-- My Network shows every direct referral's (Tier 1) phone number to an active affiliate whose login is proven, not
-- only those told on the /r/ page; a number someone asked to hide stays hidden; never a Tier 2 number (492).
--
-- The user, for the Owner, 3 Nov 2026 (the 492 file's header has the answers): a Tier 1 row carries its stored number
-- when (a) the affiliate is active, (b) the login's link to its record is proven (affiliate_login_link_proof), (c) the
-- value is a number, and (d) no withdrawn mark (referral_phone_notices) is on the record or holds the number it holds
-- now; else 'phone' is null. Tier 2 has no 'phone' key. 484's "told at sign-up" and "the number typed then" are gone.
--
--   N  The rule: under a proven, active affiliate every Tier 1 number shows, however the referral came (set by staff,
--      the seminar website, the /r/ page) and whatever number it holds now (told, then changed by staff); no number,
--      a placeholder, a LEGACY- value: none; deleted: no row; one with spaces: as stored, trimmed; a withdrawn mark
--      on the record: none; a withdrawn mark holding the number on another record: none. Suspended, inactive, not
--      proven: none; proven by a verified email: shown; another affiliate sees only its own; Tier 2: no key and no
--      number anywhere. Every other key and value and the row order are what 484's body answers on the same records
--      (its text embedded, md5 070d1b48...), whose only number here is the told one's.
--   H  The header's hide and show blocks, exactly as written: as written (the zero id) each changes nothing; a
--      referral never told: a 'hide-request' row of their own, withdrawn, hides their number on their record and on
--      every record holding it (another affiliate's household record), with an Audit Log row; shown again: the row
--      removed, both shown. A told referral: the mark withdrawn, no row made; shown again: restored. Told, then the
--      number changed: a row for the number held now and the mark withdrawn. The number they gave (c_phone, typed
--      with spaces): hidden on the record that holds it. Refused: no number and no mark; a number that is no number;
--      a show again when someone else asked to hide it too (the number stays hidden). Under 484's body (UNDO) every
--      hidden number stays hidden.
--   U  UNDO, exactly as the header writes it: 484's My Network back (md5 070d1b48..., grants kept, only the told
--      referral's number); a second run stops at its guard; the file again shows every number.
--   G  The md5 and the grants; 492 twice (the second: already this version; left alone; the first changes My Network
--      only, and its self-test leaves no row and moves no sequence); refusals, nothing changed: a My Network neither
--      484's nor 492's, an overload, a grant to signed out, a relied-on function changed, the marks table of another
--      shape, no 484 history row.
--   X  Signed out is refused My Network; a login with no affiliate account: "Not an affiliate account".
--
-- Disposable local database only: a copy of production as it is (491 in: it installs 492 twice), or one where 492 is
-- in (-v skip_install=1); everything is rolled back. A copy without production's stores gets made-up RETAIL-ADELPHI
-- and ADELPHI-VAN stores for the run, and one without 484's history row gets it for the run. Every name and email is
-- invented (@example.invalid); phones are ACMA's fictional range (+61 2 5550 ....), found free at run time. Every
-- check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 [-v skip_install=1] -f scripts/referrals/tests/affiliate-network-phone-492.sql
\set ON_ERROR_STOP on
begin;
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
-- The marks table's description, as 484 and 492 read it.
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
-- Set the request as the API sets it: 'server' (none), 'anon' (signed out), or a login (a fixture key: signed in,
-- role authenticated, auth.uid() that login).
create function pg_temp.as_who(who text) returns void language plpgsql as
$$begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  if who = 'server' then
    perform set_config('request.jwt.claims', '', true);
  elsif who = 'anon' then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
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
create function pg_temp.net(who text) returns jsonb language sql as
$$ select case when pg_temp.state(r) = 'ok' then pg_temp.body(r)::jsonb else jsonb_build_object('error', r) end
     from pg_temp.try_as(who, 'select public.affiliate_portal_network()::text') r $$;
-- The 'phone' of a Tier 1 row by name: its JSON text ('null' when the key is there with no number), 'missing' when
-- the key is absent, 'norow' when no such row.
create function pg_temp.t1(who text, cname text) returns text language sql as
$$ select coalesce((select case when r ? 'phone' then coalesce(r ->> 'phone', 'null') else 'missing' end
                      from jsonb_array_elements(pg_temp.net(who) -> 'tier1') r where r ->> 'customer_name' = cname), 'norow') $$;
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad((pg_temp.tx('phbase')::int + n)::text, 4, '0') $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 't492-' || lower(tag) || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
create function pg_temp.code(key text) returns text language sql as $$ select pg_temp.tx(key || '_code') $$;
create function pg_temp.cid(cname text) returns uuid language sql as
$$ select id from public.customers where full_name = cname and deleted_at is null $$;
-- A sign-up as the pages make it: 'wrap' (the /r/ page: the wrapper with its notice), 'old' (the seminar website: six
-- named keys), signed out. The answer, or {"error": SQLSTATE, "message": ...}.
create function pg_temp.signup(how text, p_code text, p_first text, p_last text, p_phone text) returns jsonb language plpgsql as
$$declare v jsonb;
begin
  begin
    perform pg_temp.as_who('anon');
    if how = 'wrap' then
      v := public.affiliate_referral_signup_with_notice(p_code := p_code, p_first_name := p_first, p_last_name := p_last,
             p_phone := p_phone, p_email := null, p_notice := 'r-page-2026-11', p_honeypot := null);
    else
      v := public.affiliate_referral_signup(p_code := p_code, p_first_name := p_first, p_last_name := p_last,
             p_phone := p_phone, p_email := null, p_honeypot := null);
    end if;
    perform pg_temp.as_server();
  exception when others then
    perform pg_temp.as_server();
    v := jsonb_build_object('error', sqlstate, 'message', sqlerrm);
  end;
  return v;
end$$;

-- 484's text of My Network (its c_net_def, md5 070d1b48...): 492's UNDO re-applies it; N compares with it.
create function pg_temp.net484_def() returns text language sql immutable as $tn$ select $n484$CREATE OR REPLACE FUNCTION public.affiliate_portal_network()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_t1 jsonb; v_t2 jsonb;
  -- 480 (the Owner, 29 Oct 2026): each one's cal.com booking, its moment and
  -- state only (calcom_customer_bookings, as the staff Downline reads it).
  v_book jsonb;
  -- 484 (the Owner, 31 Oct 2026, answers 1 and 2): whether this login is
  -- shown any Tier 1 number at all: the affiliate is active (not suspended,
  -- not removed) and the login's link to its record is proven
  -- (affiliate_login_link_proof, read for the login itself: auth.uid()).
  v_phones boolean;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  v_phones := public.affiliate_is_active(v_me) and public.affiliate_login_link_proof(auth.uid(), v_me) is not null;

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
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none'),
           -- 484 (the Owner, 31 Oct and 1 Nov 2026): the stored number, trimmed,
           -- only when v_phones and the referral signed up through the /r/ page
           -- while it said this referrer would see their number (a mark in
           -- referral_phone_notices naming this referrer), the record still holds
           -- the number typed then, and they have not asked to hide it (no
           -- withdrawn mark). Otherwise null (a dash on the page). Tier 2: no
           -- phone key at all.
           'phone', case when v_phones and btrim(c.phone) ~ '[0-9]' and btrim(c.phone) !~* '^(AFF-.{8}|LEGACY-.*)$'
                          and exists (select 1 from public.referral_phone_notices n
                                       where n.customer_id = c.id and n.referrer_customer_id = v_me and n.withdrawn_at is null
                                         and n.phone = public.normalize_customer_phone(c.phone))
                          and not exists (select 1 from public.referral_phone_notices w
                                           where w.customer_id = c.id and w.withdrawn_at is not null)
                         then btrim(c.phone) end
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
$n484$::text $tn$;
-- The header's blocks, word for word (the 492 file's HOW TO HIDE and UNDO).
create function pg_temp.hide_sql() returns text language sql immutable as $tb1$ select $b1$do $hide$
declare
  c_customer constant uuid := '00000000-0000-0000-0000-000000000000';  -- the referral who asked
  c_phone constant text := null;  -- or the number they gave, with its country code (else the one on their record)
  c_asked constant text := 'by phone, 4 Nov 2026';                     -- how and when they asked
  v_phone text; v_ref uuid; v_new uuid; n int;
begin
  select public.normalize_customer_phone(coalesce(c_phone, c.phone)), coalesce(c.referred_by, c.id)
    into v_phone, v_ref from public.customers c where c.id = c_customer;
  if not found then
    raise exception '492 hide: % is not a customer (fill in the referral who asked); nothing changed', c_customer;
  end if;
  if c_phone is not null and v_phone is null then
    raise exception '492 hide: % is not a number that can be matched; nothing changed', c_phone;
  end if;
  if v_phone is null and not exists (select 1 from public.referral_phone_notices k where k.customer_id = c_customer) then
    raise exception '492 hide: % holds no number that can be matched and has no mark (set c_phone to the number they gave); nothing changed', c_customer;
  end if;
  -- A withdrawn row of their own holding the number, made when none of theirs holds it.
  if v_phone is not null
     and not exists (select 1 from public.referral_phone_notices k where k.customer_id = c_customer and k.phone = v_phone) then
    insert into public.referral_phone_notices (customer_id, referrer_customer_id, phone, notice_version, referral_code, withdrawn_at)
    values (c_customer, v_ref, v_phone, 'hide-request', '', now()) returning id into v_new;
  end if;
  -- Their marks and the marks holding the number: those not hidden yet are withdrawn; one Audit Log row on each
  -- record, naming who asked, the rows withdrawn now (the one made here among them) and those hidden already.
  with m as (
    select k.id, k.customer_id, k.withdrawn_at is not null and k.id is distinct from v_new as already
      from public.referral_phone_notices k
     where k.customer_id = c_customer or k.phone = v_phone
  ), w as (
    update public.referral_phone_notices k set withdrawn_at = now() from m where k.id = m.id and k.withdrawn_at is null
  )
  insert into public.audit_logs (table_name, record_id, action, new_data, module)
  select 'customers', m.customer_id, 'referral_phone_hidden',
         jsonb_build_object('marks_withdrawn', count(*) filter (where not m.already),
                            'mark_ids', coalesce(jsonb_agg(m.id order by m.id) filter (where not m.already), '[]'),
                            'hidden_already', coalesce(jsonb_agg(m.id order by m.id) filter (where m.already), '[]'),
                            'made_for_hide', v_new, 'asked_by', c_customer, 'asked', c_asked, 'version', 492), 'affiliate'
    from m group by m.customer_id;
  get diagnostics n = row_count;
  raise notice '492 hide: done for % on % record(s)', c_customer, n;
end $hide$;
$b1$::text $tb1$;
create function pg_temp.show_sql() returns text language sql immutable as $tb2$ select $b2$do $show$
declare
  c_customer constant uuid := '00000000-0000-0000-0000-000000000000';  -- the referral who asked
  c_asked constant text := 'by phone, 5 Nov 2026';                     -- how and when they asked
  n int;
begin
  -- Only what their own hide withdrew or made; none of it if someone else also asked to hide it (the Owner decides).
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
    raise exception '492 show: % row(s) that % asked to hide, someone else also asked to hide (the Audit Log''s referral_phone_hidden rows); ask the Owner; nothing changed', n, c_customer;
  end if;
  -- The rows their hide made are removed (they were no notice); the marks it withdrew are restored.
  with s as (
    select k.id, k.customer_id, k.notice_version = 'hide-request' as made
      from public.referral_phone_notices k
     where k.withdrawn_at is not null
       and exists (select 1 from public.audit_logs l
                    where l.table_name = 'customers' and l.action = 'referral_phone_hidden'
                      and l.new_data ->> 'asked_by' = c_customer::text and (l.new_data -> 'mark_ids') @> to_jsonb(k.id))
  ), d as (
    delete from public.referral_phone_notices k using s where k.id = s.id and s.made
  ), u as (
    update public.referral_phone_notices k set withdrawn_at = null from s where k.id = s.id and not s.made
  )
  insert into public.audit_logs (table_name, record_id, action, new_data, module)
  select 'customers', s.customer_id, 'referral_phone_shown_again',
         jsonb_build_object('marks_restored', count(*) filter (where not s.made),
                            'mark_ids', coalesce(jsonb_agg(s.id order by s.id) filter (where not s.made), '[]'),
                            'hide_rows_removed', coalesce(jsonb_agg(s.id order by s.id) filter (where s.made), '[]'),
                            'asked_by', c_customer, 'asked', c_asked, 'version', 492), 'affiliate'
    from s group by s.customer_id;
  get diagnostics n = row_count;
  if n = 0 then
    raise exception '492 show: % has no mark withdrawn at their request; nothing changed', c_customer;
  end if;
  raise notice '492 show: done for % on % record(s)', c_customer, n;
end $show$;
$b2$::text $tb2$;
create function pg_temp.undo_sql() returns text language sql immutable as $tb3$ select $b3$do $undo$
begin
  perform set_config('search_path', 'public', true);
  if md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure)) <> '5506f7291146534551a25e52a1e7820b' then
    raise exception 'UNDO 492: public.affiliate_portal_network() is not 492''s version (md5 %); nothing changed',
      md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure));
  end if;
end $undo$;
$b3$::text $tb3$;
-- A block of the header with its customer filled in (the zero id replaced).
create function pg_temp.for_customer(q text, id uuid) returns text language sql as
$$ select replace(q, '''00000000-0000-0000-0000-000000000000''', quote_literal(id::text)) $$;
-- The hide block with the number they gave filled in (its c_phone null replaced).
create function pg_temp.with_phone(q text, phone text) returns text language sql as
$$ select replace(q, 'c_phone constant text := null;', 'c_phone constant text := ' || quote_literal(phone) || ';') $$;
create function pg_temp.hide(cname text) returns void language sql as
$$ select pg_temp.exec(pg_temp.for_customer(pg_temp.hide_sql(), pg_temp.cid(cname))) $$;
create function pg_temp.show(cname text) returns void language sql as
$$ select pg_temp.exec(pg_temp.for_customer(pg_temp.show_sql(), pg_temp.cid(cname))) $$;

-- ═════ Fixture: affiliates and their referrals (as the server) ═════
set local client_min_messages = warning;
do $$
declare g int; gone text[];
begin
  perform pg_temp.as_server();
  -- Letters only, so no run of digits in a code or an id can be read as a phone number.
  perform pg_temp.put('sfx', translate(lower(substr(md5(gen_random_uuid()::text), 1, 8)), '0123456789', 'ghijklmnop'));
  -- A hundred free fictional phones in a row (+61 2 5550 nnnn): no customer's, in use or deleted, and no active booking's.
  gone := array(select public.normalize_customer_phone(c.phone) from public.customers c where c.deleted_at is not null);
  for g in 1000 .. 9800 by 100 loop
    continue when exists (select 1 from public.customers c
                           where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                                 between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 99)::text, 4, '0'));
    continue when exists (select 1 from unnest(gone) y(ph)
                           where y.ph between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 99)::text, 4, '0'));
    continue when exists (select 1 from public.calcom_bookings b
                           where b.status = 'active'
                             and b.phone_key between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 99)::text, 4, '0'));
    perform pg_temp.put('phbase', g::text);
    exit;
  end loop;
  if pg_temp.tx('phbase') is null then raise exception 'no free fictional phones'; end if;
end $$;
do $$
declare v uuid;
begin
  -- A login with no affiliate account.
  insert into auth.users (id, email) values (gen_random_uuid(), pg_temp.mail('nolink')) returning id into v;
  perform pg_temp.putx('nolink', v);
  -- The Adelphi centre and the Van & RoadShow, and 484's migration row, as production has them (a copy without them
  -- gets them for this run).
  insert into public.stores (name, code, country_code) values ('T492 Adelphi centre', 'RETAIL-ADELPHI', 'SG'),
                                                              ('T492 Van and RoadShow', 'ADELPHI-VAN', 'SG')
    on conflict (code) do nothing;
  if not exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261102000820') then
    insert into supabase_migrations.schema_migrations (version, name) values ('20261102000820', '484_affiliate_network_shows_tier1_phone');
  end if;
end $$;
-- An affiliate: its record (made p_age ago: '0' = with its account, in this transaction: own_record), an active
-- affiliate record with a made-up code, a login and its portal account (triggers off for that statement only: no
-- welcome WhatsApp).
create function pg_temp.mk_aff(key text, n int, p_age interval) returns void language plpgsql as
$$declare v_c uuid; v_a uuid; v_u uuid := gen_random_uuid(); v_acct uuid; v_srr text := current_setting('session_replication_role');
begin
  insert into public.customers (full_name, phone, email, created_at)
    values ('T492 Aff ' || key, pg_temp.ph(n), pg_temp.mail(key), now() - p_age) returning id into v_c;
  insert into public.customer_affiliates (customer_id, status, activated_at, referral_code)
    values (v_c, 'active', now(), 'T492' || upper(key) || upper(pg_temp.tx('sfx'))) returning id into v_a;
  insert into auth.users (id, email) values (v_u, pg_temp.mail(key));
  set local session_replication_role = replica;
  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status)
    values (v_u, v_c, v_a, 'claimed') returning id into v_acct;
  execute format('set local session_replication_role = %L', v_srr);
  perform pg_temp.putx(key, v_c); perform pg_temp.putx(key || '_aff', v_a);
  perform pg_temp.putx(key || '_login', v_u); perform pg_temp.putx(key || '_acct', v_acct);
  perform pg_temp.put(key || '_code', 'T492' || upper(key) || upper(pg_temp.tx('sfx')));
end$$;
-- A and B: proven (own_record), active. C suspended, I inactive, D not proven (its record 30 days older than its
-- account, nothing else proves it), E proven by its verified email (the record's, 30 days old).
select pg_temp.mk_aff('a', 0, '0 seconds'), pg_temp.mk_aff('b', 1, '0 seconds'), pg_temp.mk_aff('c', 2, '0 seconds'),
       pg_temp.mk_aff('i', 3, '0 seconds'), pg_temp.mk_aff('d', 4, '30 days'), pg_temp.mk_aff('e', 5, '30 days');
update public.customer_affiliates set manually_suspended = true, status = 'suspended_manual' where id = pg_temp.fx('c_aff');
update public.customer_affiliates set status = 'inactive' where id = pg_temp.fx('i_aff');
update public.affiliate_accounts set email_verified_at = now() where id = pg_temp.fx('e_acct');
-- A's Tier 1: through the /r/ page (told: a mark), the seminar website (no mark), and set by staff.
select pg_temp.put('s_told', pg_temp.signup('wrap', pg_temp.code('a'), 'T492', 'Told', pg_temp.ph(10))::text),
       pg_temp.put('s_changed', pg_temp.signup('wrap', pg_temp.code('a'), 'T492', 'Changed', pg_temp.ph(13))::text),
       pg_temp.put('s_seminar', pg_temp.signup('old', pg_temp.code('a'), 'T492', 'Seminar', pg_temp.ph(12))::text);
do $$
declare v_srr text := current_setting('session_replication_role');
begin
  insert into public.customers (full_name, phone, referred_by) values
    ('T492 Plain', pg_temp.ph(11), pg_temp.fx('a')),
    ('T492 Spaces', pg_temp.ph(15), pg_temp.fx('a')),
    ('T492 No Phone', pg_temp.ph(19), pg_temp.fx('a')),
    ('T492 Placeholder', pg_temp.ph(16), pg_temp.fx('a')),
    ('T492 Legacy', pg_temp.ph(17), pg_temp.fx('a')),
    ('T492 Deleted', pg_temp.ph(18), pg_temp.fx('a')),
    ('T492 House', pg_temp.ph(20), pg_temp.fx('a')),
    -- B's: its own; the same number as A's T492 House (a household); one holding the number T492 Giver gives.
    ('T492 B Ref', pg_temp.ph(30), pg_temp.fx('b')),
    ('T492 B House', pg_temp.ph(20), pg_temp.fx('b')),
    ('T492 B Given', pg_temp.ph(31), pg_temp.fx('b')),
    ('T492 C Ref', pg_temp.ph(32), pg_temp.fx('c')),
    ('T492 I Ref', pg_temp.ph(33), pg_temp.fx('i')),
    ('T492 D Ref', pg_temp.ph(34), pg_temp.fx('d')),
    ('T492 E Ref', pg_temp.ph(35), pg_temp.fx('e')),
    -- Nobody's referral: asks to hide a number held by T492 B Given.
    ('T492 Giver', pg_temp.ph(36), null);
  -- Tier 2 under T492 Plain.
  insert into public.customers (full_name, phone, referred_by) values ('T492 Tier Two', pg_temp.ph(40), pg_temp.cid('T492 Plain'));
  -- Staff change T492 Changed's number after it was told; T492 Deleted is deleted. With triggers off for those
  -- statements (the phone policy refuses or rewrites them now, as legacy records still hold them): the placeholder,
  -- the LEGACY- value, a blank, and a number kept as typed with spaces.
  update public.customers set phone = pg_temp.ph(14) where id = pg_temp.cid('T492 Changed');
  update public.customers set deleted_at = now() where id = pg_temp.cid('T492 Deleted');
  set local session_replication_role = replica;
  update public.customers set phone = 'AFF-' || pg_temp.tx('sfx') where id = pg_temp.cid('T492 Placeholder');
  update public.customers set phone = 'LEGACY-' || pg_temp.tx('sfx') where id = pg_temp.cid('T492 Legacy');
  update public.customers set phone = '' where id = pg_temp.cid('T492 No Phone');
  update public.customers set phone = '  +61 2 5550 ' || right(pg_temp.ph(15), 4) || ' ' where id = pg_temp.cid('T492 Spaces');
  execute format('set local session_replication_role = %L', v_srr);
end $$;
set local client_min_messages = notice;
select pg_temp.check(pg_temp.tx('s_told')::jsonb ->> 'outcome' = 'registered' and pg_temp.tx('s_changed')::jsonb ->> 'outcome' = 'registered'
    and pg_temp.tx('s_seminar')::jsonb ->> 'outcome' = 'registered'
    and (select count(*) from public.referral_phone_notices n where n.customer_id in (pg_temp.cid('T492 Told'), pg_temp.cid('T492 Changed'))) = 2
    and not exists (select 1 from public.referral_phone_notices n where n.customer_id = pg_temp.cid('T492 Seminar')),
  'F the fixture: /r/ sign-ups marked (Told, Changed), the seminar website''s not: ' || pg_temp.tx('s_told') || ' ' || pg_temp.tx('s_seminar'));

-- ═════ I Install (where 492 is not in) ═════
\if :{?skip_install}
\else
create temp table b492 as select * from pg_temp.fn_md5s();
create temp table r492 as select pg_temp.row_counts() as before, pg_temp.seqs() as seq_before;
\ir ../../../supabase/492_affiliate_network_shows_every_tier1_phone.sql
create temp table m492 as select * from pg_temp.fn_md5s();
alter table r492 add column after1 jsonb, add column seq_after1 jsonb;
update r492 set after1 = pg_temp.row_counts(), seq_after1 = pg_temp.seqs();
\ir ../../../supabase/492_affiliate_network_shows_every_tier1_phone.sql
create temp table m492b as select * from pg_temp.fn_md5s();
select pg_temp.check((select string_agg(b.fn || ' ' || b.md5 || ' -> ' || m.md5, '; ') from b492 b join m492 m using (fn) where m.md5 <> b.md5)
                     = 'affiliate_portal_network() 070d1b485d32cec99fa627b816a91b4a -> 5506f7291146534551a25e52a1e7820b'
    and (select count(*) from b492) = (select count(*) from m492)
    and not exists (select 1 from b492 b join m492 m using (fn) where m.acl <> b.acl)
    and not exists (select 1 from m492 m join m492b n using (fn) where n.md5 <> m.md5 or n.acl <> m.acl)
    and (select before = after1 and seq_before = seq_after1 from r492),
  'I1 492 changes My Network alone (484''s -> 492''s), its grants and every other function as they were; its self-test leaves no row and moves no sequence; the second run changes nothing');
\endif
select pg_temp.check(pg_temp.md5_of('affiliate_portal_network()') = '5506f7291146534551a25e52a1e7820b'
    and pg_temp.acl_of('affiliate_portal_network()') = array['authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres']
    and not has_function_privilege('anon', 'public.affiliate_portal_network()', 'execute')
    and pg_temp.tbl_desc() = 'ec6de1ddd64fb06b87b401b9f7a55984',
  'G1 My Network at 492''s md5, its grants as before (signed-in logins, the owner, the service role; not signed out); the marks table as 484 left it');

-- ═════ N The rule ═════
select pg_temp.check(pg_temp.t1('a_login', 'T492 Plain') = pg_temp.ph(11) and pg_temp.t1('a_login', 'T492 Told') = pg_temp.ph(10)
    and pg_temp.t1('a_login', 'T492 Seminar') = pg_temp.ph(12) and pg_temp.t1('a_login', 'T492 Changed') = pg_temp.ph(14)
    and pg_temp.t1('a_login', 'T492 House') = pg_temp.ph(20),
  'N1 a proven, active affiliate sees every Tier 1 number: set by staff, told on /r/, the seminar website''s, the number staff changed to');
select pg_temp.check(pg_temp.t1('a_login', 'T492 Spaces') = '+61 2 5550 ' || right(pg_temp.ph(15), 4)
    and pg_temp.t1('a_login', 'T492 No Phone') = 'null' and pg_temp.t1('a_login', 'T492 Placeholder') = 'null'
    and pg_temp.t1('a_login', 'T492 Legacy') = 'null' and pg_temp.t1('a_login', 'T492 Deleted') = 'norow',
  'N2 as stored, trimmed (spaces kept inside); no number, a placeholder, a LEGACY- value: a dash; deleted: no row');
select pg_temp.check(pg_temp.t1('c_login', 'T492 C Ref') = 'null' and pg_temp.t1('i_login', 'T492 I Ref') = 'null'
    and pg_temp.t1('d_login', 'T492 D Ref') = 'null' and pg_temp.t1('e_login', 'T492 E Ref') = pg_temp.ph(35)
    and pg_temp.t1('b_login', 'T492 B Ref') = pg_temp.ph(30) and pg_temp.t1('b_login', 'T492 Plain') = 'norow'
    and pg_temp.t1('a_login', 'T492 B Ref') = 'norow',
  'N3 suspended, inactive, not proven: a dash; proven by a verified email: shown; each affiliate sees its own referrals only');
select pg_temp.check((select bool_and(not (r ? 'phone')) from jsonb_array_elements(pg_temp.net('a_login') -> 'tier2') r)
    and jsonb_array_length(pg_temp.net('a_login') -> 'tier2') = 1
    and strpos(pg_temp.net('a_login')::text, substr(pg_temp.ph(40), 2)) = 0
    and strpos(pg_temp.net('a_login')::text, substr(pg_temp.ph(0), 2)) = 0
    and strpos(pg_temp.net('a_login')::text, substr(pg_temp.ph(13), 2)) = 0,
  'N4 Tier 2 has no phone key, and no Tier 2 number, the affiliate''s own or the number typed before a change shows anywhere');
-- 484's body on the same records (installed for the calls, then undone): every key but 'phone', every value and the
-- order are the same; 484 shows the told number only (Changed's number is no longer the one typed).
select pg_temp.net('a_login') as n492 \gset
savepoint n5;
select pg_temp.exec(pg_temp.net484_def());
select pg_temp.md5_of('affiliate_portal_network()') as n5_md5, pg_temp.net('a_login') as n484 \gset
rollback to savepoint n5;
select pg_temp.check(:'n5_md5' = '070d1b485d32cec99fa627b816a91b4a'
    and (select jsonb_agg(r - 'phone') from jsonb_array_elements((:'n492'::jsonb) -> 'tier1') r)
        = (select jsonb_agg(r - 'phone') from jsonb_array_elements((:'n484'::jsonb) -> 'tier1') r)
    and (:'n492'::jsonb) -> 'tier2' = (:'n484'::jsonb) -> 'tier2'
    and (select array_agg(r ->> 'customer_name' order by r ->> 'customer_name') from jsonb_array_elements((:'n484'::jsonb) -> 'tier1') r
          where r ->> 'phone' is not null) = array['T492 Told']
    and pg_temp.md5_of('affiliate_portal_network()') = '5506f7291146534551a25e52a1e7820b',
  'N5 every other key, value and the order as 484''s body answers on the same records, where only the told referral''s number showed');

-- ═════ H The header's hide and show blocks ═════
-- As written (the zero id), each changes nothing.
savepoint h0;
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.hide_sql());
\set ON_ERROR_STOP on
\set h0_hide :LAST_ERROR_MESSAGE
rollback to savepoint h0;
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.show_sql());
\set ON_ERROR_STOP on
\set h0_show :LAST_ERROR_MESSAGE
rollback to savepoint h0;
select pg_temp.check(:'h0_hide' = '492 hide: 00000000-0000-0000-0000-000000000000 is not a customer (fill in the referral who asked); nothing changed'
    and :'h0_show' = '492 show: 00000000-0000-0000-0000-000000000000 has no mark withdrawn at their request; nothing changed',
  'H1 as written (the zero id), the hide and the show block change nothing: ' || :'h0_hide');
-- Never told (no mark): a row of their own, withdrawn, holding their number; hidden on their record and on B's
-- household record with the same number; an Audit Log row on their record. Shown again: the row removed, both shown.
select pg_temp.put('h2_marks0', (select count(*)::text from public.referral_phone_notices));
select pg_temp.hide('T492 House');
select pg_temp.put('h2_a', pg_temp.t1('a_login', 'T492 House')), pg_temp.put('h2_b', pg_temp.t1('b_login', 'T492 B House')),
       pg_temp.put('h2_row', (select string_agg(n.notice_version || '/' || n.referral_code || '/' || (n.withdrawn_at is not null)::text
                                                || '/' || (n.phone = pg_temp.ph(20))::text || '/' || (n.referrer_customer_id = pg_temp.fx('a'))::text, ',')
                                from public.referral_phone_notices n where n.customer_id = pg_temp.cid('T492 House'))),
       pg_temp.put('h2_audit', (select string_agg((l.new_data ->> 'marks_withdrawn') || '/' || jsonb_array_length(l.new_data -> 'mark_ids')
                                                  || '/' || jsonb_array_length(l.new_data -> 'hidden_already') || '/' || (l.new_data ->> 'version')
                                                  || '/' || ((l.new_data ->> 'made_for_hide') is not null)::text || '/' || l.module, ',')
                                  from public.audit_logs l where l.record_id = pg_temp.cid('T492 House') and l.action = 'referral_phone_hidden'));
select pg_temp.show('T492 House');
select pg_temp.check(pg_temp.tx('h2_a') = 'null' and pg_temp.tx('h2_b') = 'null' and pg_temp.tx('h2_row') = 'hide-request//true/true/true'
    and pg_temp.tx('h2_audit') = '1/1/0/492/true/affiliate'
    and pg_temp.t1('a_login', 'T492 House') = pg_temp.ph(20) and pg_temp.t1('b_login', 'T492 B House') = pg_temp.ph(20)
    and (select count(*)::text from public.referral_phone_notices) = pg_temp.tx('h2_marks0')
    and exists (select 1 from public.audit_logs l where l.record_id = pg_temp.cid('T492 House') and l.action = 'referral_phone_shown_again'
                 and l.new_data ->> 'marks_restored' = '0' and jsonb_array_length(l.new_data -> 'hide_rows_removed') = 1),
  'H2 never told: a withdrawn hide-request row of their own hides their number on their record and on another affiliate''s record holding it, with an Audit Log row; shown again: the row removed, both shown: '
    || pg_temp.tx('h2_row') || ' ' || pg_temp.tx('h2_audit'));
-- Told (their mark holds the number they hold now): the mark withdrawn, no row made; shown again: restored.
select pg_temp.hide('T492 Told');
select pg_temp.put('h3_hidden', pg_temp.t1('a_login', 'T492 Told')),
       pg_temp.put('h3_rows', (select string_agg(n.notice_version || '/' || (n.withdrawn_at is not null)::text, ',')
                                 from public.referral_phone_notices n where n.customer_id = pg_temp.cid('T492 Told')));
select pg_temp.show('T492 Told');
select pg_temp.check(pg_temp.tx('h3_hidden') = 'null' and pg_temp.tx('h3_rows') = 'r-page-2026-11/true'
    and pg_temp.t1('a_login', 'T492 Told') = pg_temp.ph(10)
    and (select string_agg(n.notice_version || '/' || (n.withdrawn_at is null)::text, ',')
           from public.referral_phone_notices n where n.customer_id = pg_temp.cid('T492 Told')) = 'r-page-2026-11/true',
  'H3 told: their mark withdrawn and no row made (a dash); shown again: the mark restored, the number back');
-- Told, then the number changed: a row for the number held now, and the mark (the old number) withdrawn.
select pg_temp.hide('T492 Changed');
select pg_temp.check(pg_temp.t1('a_login', 'T492 Changed') = 'null'
    and (select string_agg(n.notice_version || '/' || (n.phone = pg_temp.ph(14))::text || '/' || (n.withdrawn_at is not null)::text, ',' order by n.notice_version)
           from public.referral_phone_notices n where n.customer_id = pg_temp.cid('T492 Changed')) = 'hide-request/true/true,r-page-2026-11/false/true',
  'H4 told, then their number changed: a row for the number they hold now and their mark withdrawn: a dash');
-- The number they gave (c_phone, typed with spaces): hidden on the record that holds it (B's), which is not theirs.
select pg_temp.exec(pg_temp.with_phone(pg_temp.for_customer(pg_temp.hide_sql(), pg_temp.cid('T492 Giver')), '+61 2 5550 ' || right(pg_temp.ph(31), 4)));
select pg_temp.check(pg_temp.t1('b_login', 'T492 B Given') = 'null' and pg_temp.t1('b_login', 'T492 B Ref') = pg_temp.ph(30)
    and exists (select 1 from public.referral_phone_notices n where n.customer_id = pg_temp.cid('T492 Giver') and n.phone = pg_temp.ph(31)
                 and n.withdrawn_at is not null and n.notice_version = 'hide-request' and n.referrer_customer_id = pg_temp.cid('T492 Giver')),
  'H5 the number they gave (typed with spaces): hidden on the record holding it; their row names them where they have no referrer');
-- Refused, nothing changed: no number and no mark; a number that is no number.
savepoint h6;
\set ON_ERROR_STOP off
select pg_temp.hide('T492 No Phone');
\set ON_ERROR_STOP on
\set h6_none :LAST_ERROR_MESSAGE
rollback to savepoint h6;
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.with_phone(pg_temp.for_customer(pg_temp.hide_sql(), pg_temp.cid('T492 Plain')), '0'));
\set ON_ERROR_STOP on
\set h6_bad :LAST_ERROR_MESSAGE
rollback to savepoint h6;
select pg_temp.check(:'h6_none' like '492 hide: % holds no number that can be matched and has no mark (set c_phone to the number they gave); nothing changed'
    and :'h6_bad' = '492 hide: 0 is not a number that can be matched; nothing changed'
    and pg_temp.t1('a_login', 'T492 Plain') = pg_temp.ph(11),
  'H6 refused, nothing changed: no number and no mark; a number that is no number: ' || :'h6_none');
-- Both holders of a household number ask: the second's request is recorded (hidden already); the first's show again
-- is refused (someone else asked too) and the number stays hidden.
select pg_temp.hide('T492 House');
select pg_temp.hide('T492 B House');
savepoint h7;
\set ON_ERROR_STOP off
select pg_temp.show('T492 House');
\set ON_ERROR_STOP on
\set h7_msg :LAST_ERROR_MESSAGE
rollback to savepoint h7;
select pg_temp.check(:'h7_msg' like '492 show: 1 row(s) that % asked to hide, someone else also asked to hide%nothing changed'
    and pg_temp.t1('a_login', 'T492 House') = 'null' and pg_temp.t1('b_login', 'T492 B House') = 'null'
    and exists (select 1 from public.audit_logs l where l.record_id = pg_temp.cid('T492 House') and l.action = 'referral_phone_hidden'
                 and l.new_data ->> 'asked_by' = pg_temp.cid('T492 B House')::text and jsonb_array_length(l.new_data -> 'hidden_already') = 1),
  'H7 both holders of a number ask: the second recorded (hidden already); the first''s show again refused, the number stays hidden: ' || :'h7_msg');
-- Under 484's body (UNDO), every number hidden here stays hidden.
savepoint h8;
select pg_temp.exec(pg_temp.net484_def());
select pg_temp.t1('a_login', 'T492 House') as h8_house, pg_temp.t1('a_login', 'T492 Changed') as h8_changed,
       pg_temp.t1('b_login', 'T492 B Given') as h8_given, pg_temp.t1('b_login', 'T492 B House') as h8_bhouse \gset
rollback to savepoint h8;
select pg_temp.check(:'h8_house' = 'null' and :'h8_changed' = 'null' and :'h8_given' = 'null' and :'h8_bhouse' = 'null',
  'H8 under 484''s My Network (UNDO) every number hidden here stays hidden');

-- ═════ U UNDO, as the header writes it ═════
savepoint u1;
select pg_temp.exec(pg_temp.undo_sql());
select pg_temp.exec(pg_temp.net484_def());
select pg_temp.md5_of('affiliate_portal_network()') as u1_md5, array_to_string(pg_temp.acl_of('affiliate_portal_network()'), ',') as u1_acl,
       pg_temp.t1('a_login', 'T492 Plain') as u1_plain, pg_temp.t1('a_login', 'T492 Told') as u1_told \gset
savepoint u1b;
\set ON_ERROR_STOP off
select pg_temp.exec(pg_temp.undo_sql());
\set ON_ERROR_STOP on
\set u1_again :LAST_ERROR_MESSAGE
rollback to savepoint u1b;
\ir ../../../supabase/492_affiliate_network_shows_every_tier1_phone.sql
select pg_temp.md5_of('affiliate_portal_network()') as u1_back, pg_temp.t1('a_login', 'T492 Plain') as u1_plain_back \gset
rollback to savepoint u1;
select pg_temp.check(:'u1_md5' = '070d1b485d32cec99fa627b816a91b4a' and :'u1_acl' = 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'
    and :'u1_plain' = 'null' and :'u1_told' = pg_temp.ph(10)
    and :'u1_again' like 'UNDO 492: public.affiliate_portal_network() is not 492''s version (md5 070d1b485d32cec99fa627b816a91b4a); nothing changed'
    and :'u1_back' = '5506f7291146534551a25e52a1e7820b' and :'u1_plain_back' = pg_temp.ph(11),
  'U1 UNDO: 484''s My Network back (grants kept; only the told number); a second run stops at its guard; the file again shows every number: ' || :'u1_again');

-- ═════ G Refusals, nothing changed ═════
-- Each in a savepoint: the file stops with its message and My Network is as it was.
create function pg_temp.g_state() returns text language sql as
$$ select pg_temp.md5_of('affiliate_portal_network()') || ' ' || pg_temp.tbl_desc() $$;
select pg_temp.g_state() as g_before \gset
savepoint g2;
select pg_temp.exec(replace(pg_temp.net484_def(), 'v_book jsonb;', 'v_book jsonb; -- another version'));
\set ON_ERROR_STOP off
\ir ../../../supabase/492_affiliate_network_shows_every_tier1_phone.sql
\set ON_ERROR_STOP on
\set g2_msg :LAST_ERROR_MESSAGE
rollback to savepoint g2;
savepoint g3;
create function public.affiliate_portal_network(p int) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/492_affiliate_network_shows_every_tier1_phone.sql
\set ON_ERROR_STOP on
\set g3_msg :LAST_ERROR_MESSAGE
rollback to savepoint g3;
savepoint g4;
grant execute on function public.affiliate_portal_network() to anon;
\set ON_ERROR_STOP off
\ir ../../../supabase/492_affiliate_network_shows_every_tier1_phone.sql
\set ON_ERROR_STOP on
\set g4_msg :LAST_ERROR_MESSAGE
rollback to savepoint g4;
savepoint g5;
comment on function public.affiliate_is_active(uuid) is null;
select pg_temp.exec(replace(pg_get_functiondef('public.affiliate_is_active(uuid)'::regprocedure), 'AS $function$', E'AS $function$\n-- changed'));
\set ON_ERROR_STOP off
\ir ../../../supabase/492_affiliate_network_shows_every_tier1_phone.sql
\set ON_ERROR_STOP on
\set g5_msg :LAST_ERROR_MESSAGE
rollback to savepoint g5;
savepoint g6;
alter table public.referral_phone_notices add column t492_extra int;
\set ON_ERROR_STOP off
\ir ../../../supabase/492_affiliate_network_shows_every_tier1_phone.sql
\set ON_ERROR_STOP on
\set g6_msg :LAST_ERROR_MESSAGE
rollback to savepoint g6;
savepoint g7;
delete from supabase_migrations.schema_migrations where version = '20261102000820';
\set ON_ERROR_STOP off
\ir ../../../supabase/492_affiliate_network_shows_every_tier1_phone.sql
\set ON_ERROR_STOP on
\set g7_msg :LAST_ERROR_MESSAGE
rollback to savepoint g7;
select pg_temp.check(:'g2_msg' like '492: public.affiliate_portal_network() is neither 484''s (md5 070d1b485d32cec99fa627b816a91b4a) nor this file''s (md5 5506f7291146534551a25e52a1e7820b): found md5 %',
  'G2 a My Network neither 484''s nor 492''s is refused: ' || :'g2_msg');
select pg_temp.check(:'g3_msg' = '492: another function takes the name of My Network: affiliate_portal_network(integer)',
  'G3 an overload of My Network is refused: ' || :'g3_msg');
select pg_temp.check(:'g4_msg' like '492: the grants of public.affiliate_portal_network() are not as read on 3 Nov 2026%',
  'G4 a grant to signed out is refused: ' || :'g4_msg');
select pg_temp.check(:'g5_msg' like '492: public.affiliate_is_active(uuid) is missing or not the version this was tested against.%',
  'G5 a relied-on function changed is refused: ' || :'g5_msg');
select pg_temp.check(:'g6_msg' like '492: public.referral_phone_notices is missing or not 484''s (description md5 %',
  'G6 the marks table of another shape is refused: ' || :'g6_msg');
select pg_temp.check(:'g7_msg' like '492: 484 (20261102000820) is not recorded in supabase_migrations.schema_migrations.%',
  'G7 a database without 484''s history row is refused: ' || :'g7_msg');
select pg_temp.check(pg_temp.g_state() = :'g_before', 'G8 after the refusals My Network and the marks table are as they were');

-- ═════ X Who may ═════
select pg_temp.check(pg_temp.state(pg_temp.try_as('anon', 'select public.affiliate_portal_network()::text')) = '42501'
    and pg_temp.try_as('nolink', 'select public.affiliate_portal_network()::text') = 'P0001' || chr(9) || 'Not an affiliate account',
  'X1 signed out is refused My Network; a login with no affiliate account: "Not an affiliate account"');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 492 checks passed.';
end $$;
rollback;
