-- The merge preview refuses to retire the record that holds the portal login
-- or the affiliate record into a record that has neither (486).
--
-- The Owner, 2 Nov 2026 ("Build a merge guard next"): a merge decides that
-- two records are one person, not whose login it is; staff keep the
-- affiliate's record and merge the other one into it. merge_customer_records
-- runs the preview first and refuses on any blocking issue.
--
--   P  486 is installed; 484 is in (its marks table); the test phones are
--      free.
--   X  Every combination, as an active Owner, both ways round: a record with
--      a claimed portal login, a disabled one, an affiliate record active,
--      suspended, inactive or deleted, /r/ marks naming it as referrer (two,
--      one of them withdrawn; one; one withdrawn only), a login, an affiliate
--      record and a mark together, a mark naming it as the referral only, and
--      a plain one. The new issue comes exactly when the duplicate holds a
--      login, an affiliate record or marks as referrer and the record kept
--      has neither a login nor an affiliate record, last, in its words;
--      everything else (every other key, every other issue and their order)
--      is what production's preview answers (its text of 2 Nov 2026, run here
--      as a copy); can_merge is true exactly when nothing blocks.
--   E  The issues there before, in their words, alone and with the new one
--      (after them): the duplicate already deleted, the record kept deleted,
--      two affiliate records in use, a commission between the two.
--   R  merge_customer_records refuses a refused merge with "This merge needs
--      review first: <the details>" and changes nothing.
--   M  Permitted merges, end to end: keeping the affiliate's record and
--      retiring a plain one that refers a customer and is a mark's referral
--      (both follow); keeping a login's record and retiring an affiliate's
--      (the affiliate record follows); keeping an affiliate's record and
--      retiring one with a mark naming it as referrer (the mark follows).
--   L  437's Link to this customer is not refused: a fresh sign-up record
--      (a login and an affiliate record) linked to a customer with neither.
--      The same pair merged by hand, from a DO block or from a look-alike
--      link_affiliate_signup in pg_temp is refused, and changes nothing (a
--      look-alike visible by name would pass: 486's NOT COVERED).
--   D  484's UNDO level 2 situation: with referral_phone_notices dropped (in
--      a savepoint), the preview answers without an error, refuses a login's
--      or an affiliate's record as before, and a permitted merge goes
--      through.
--   G  Grants: the owner's and the service role's only.
--   U  UNDO, as written in 486's header (its DO block; the header's begin,
--      lock timeout and commit are this file's transaction): the preview goes
--      back to production's text with its grants and the history row holding
--      the text goes; a second UNDO is refused and changes nothing; 486
--      installs again.
--   I  486 installs itself here twice (unless -v skip_install=1, where it is
--      in); the second run changes nothing; the preview is its AFTER.
--
-- Every check runs, then the file fails if any did. Disposable database
-- only; everything is rolled back. Needs production as of 2 Nov 2026 (head
-- 485). Every name, phone and email below is invented: phones from the
-- ACMA's fictional range (+61 2 5550 4860 to 4899), emails @example.invalid.
--   psql -v ON_ERROR_STOP=1 [-v skip_install=1] -f scripts/customer-merge/tests/merge-guard-486.sql
\set ON_ERROR_STOP on
begin;
\if :{?skip_install}
create temp table m486 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\else
\ir ../../../supabase/486_merge_guard_keeps_the_affiliate_record.sql
create temp table m486 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\ir ../../../supabase/486_merge_guard_keeps_the_affiliate_record.sql
\endif
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
create function pg_temp.c(key text) returns uuid language sql as $$ select v from fx where k='c:'||key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k=key $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.as_staff() returns void language sql as
$$ select set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true),
          set_config('request.jwt.claim.role', 'authenticated', true),
          set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx('owner'), 'role', 'authenticated')::text, true) $$;
create function pg_temp.as_server() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', '', true),
          set_config('request.jwt.claims', '', true) $$;
create function pg_temp.mail(local text) returns text language sql as
$$ select 'z486-' || local || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
-- A customer (key c:<key>) with the next fictional phone and: plain; login (a claimed portal login, no affiliate
-- record), logindis (a disabled one); aff (an active affiliate record, no login), affsusp (suspended), affinact
-- (inactive), affdel (deleted); both (a claimed login and an active affiliate record).
create function pg_temp.cust(key text, kind text, p_referred_by uuid default null) returns uuid language plpgsql as
$$declare c uuid; u uuid; a uuid; n int := (select count(*) from fx where k like 'c:%');
begin
  if n >= 40 then raise exception 'out of fictional phones'; end if;
  insert into customers(full_name, phone, referred_by) values ('Zed486 ' || initcap(key), '+6125550' || (4860 + n), p_referred_by)
  returning id into c;
  insert into fx values ('c:' || key, c);
  if kind in ('aff', 'affsusp', 'affinact', 'affdel', 'both') then
    insert into customer_affiliates(customer_id, status, manually_suspended, deleted_at)
    values (c, case kind when 'affsusp' then 'suspended_manual' when 'affinact' then 'inactive' when 'affdel' then 'soft_deleted' else 'active' end,
            kind = 'affsusp', case when kind = 'affdel' then now() end)
    returning id into a;
    insert into fx values ('a:' || key, a);
  end if;
  if kind in ('login', 'logindis', 'both') then
    u := gen_random_uuid(); insert into fx values ('u:' || key, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, pg_temp.mail('login-' || key), now());
    -- the welcome-WhatsApp trigger off for this insert only
    set local session_replication_role = replica;
    insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
    values (u, c, a, case when kind = 'logindis' then 'disabled' else 'claimed' end);
    set local session_replication_role = origin;
  end if;
  return c;
end$$;
-- A /r/ mark: the referral (customer_id) told that the referrer would see their number.
create function pg_temp.mark(referral text, referrer text, withdrawn boolean default false) returns void language plpgsql as
$$begin
  execute 'insert into public.referral_phone_notices (customer_id, referrer_customer_id, phone, notice_version, referral_code, withdrawn_at)
           select c.id, $2, public.normalize_customer_phone(c.phone), ''r-page-2026-11'', ''Z486CODE'', $3 from public.customers c where c.id = $1'
    using pg_temp.c(referral), pg_temp.c(referrer), case when withdrawn then now() end;
end$$;
-- The preview, as the signed-in Owner (an error comes back as {"error": ...}), and production's own text of
-- 2 Nov 2026 run as a copy for comparison.
create function pg_temp.pv(keep uuid, dup uuid) returns jsonb language plpgsql as
$$begin return public.preview_customer_merge(keep, dup);
exception when others then return jsonb_build_object('error', sqlerrm); end$$;
do $before$
declare d text := $p486$CREATE OR REPLACE FUNCTION public.preview_customer_merge(p_keep uuid, p_merge uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.customers%rowtype; m public.customers%rowtype;
        v_counts jsonb := '{}'::jsonb; v_blocks jsonb := '[]'::jsonb; n bigint;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can review a customer merge' using errcode='42501'; end if;
  if p_keep = p_merge then raise exception 'Those are the same record'; end if;
  select * into k from public.customers where id = p_keep;
  if not found then raise exception 'The record to keep was not found'; end if;
  select * into m from public.customers where id = p_merge;
  if not found then raise exception 'The duplicate record was not found'; end if;

  -- What the duplicate actually holds.
  select jsonb_build_object(
    'invoices',        (select count(*) from public.invoices where customer_id = p_merge and deleted_at is null),
    'credit_lots',     (select count(*) from public.customer_credit_lots where customer_id = p_merge),
    'credit_remaining',(select coalesce(sum(remaining_amount),0) from public.customer_credit_lots
                         where customer_id = p_merge and status = 'active'),
    'vouchers',        (select coalesce(sum(quantity),0) from public.customer_reward_vouchers
                         where customer_id = p_merge and status = 'held'),
    'therapy_units',   (select count(*) from public.purchased_therapy_entitlements where customer_id = p_merge),
    'entitlements',    (select count(*) from public.therapy_entitlements where customer_id = p_merge),
    'sessions',        (select count(*) from public.customer_therapy_sessions where customer_id = p_merge),
    'commissions_as_buyer',   (select count(*) from public.commissions where buyer_customer_id = p_merge),
    'commissions_as_referrer',(select count(*) from public.commissions where referrer_customer_id = p_merge),
    'referred_customers',     (select count(*) from public.customers where referred_by = p_merge and deleted_at is null),
    'surveys',         (select count(*) from public.health_surveys where customer_id = p_merge))
  into v_counts;

  -- Things a script must not decide.
  if m.deleted_at is not null then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','duplicate_already_deleted',
      'detail','The duplicate is already deleted; nothing would move.')); end if;
  if k.deleted_at is not null then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','keeper_deleted',
      'detail','The record to keep is deleted. Restore it first.')); end if;

  if exists (select 1 from public.customer_affiliates where customer_id = p_keep and deleted_at is null)
     and exists (select 1 from public.customer_affiliates where customer_id = p_merge and deleted_at is null) then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','two_affiliate_records',
      'detail','Both records are affiliates. Which referral code and payout history survives is a decision about real money — resolve the affiliate records first, then merge.')); end if;

  -- A referral between the two would become a person referring themselves.
  select count(*) into n from public.commissions
   where (buyer_customer_id = p_keep and referrer_customer_id = p_merge)
      or (buyer_customer_id = p_merge and referrer_customer_id = p_keep);
  if n > 0 then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','commission_between_the_two',
      'detail', n || ' commission row(s) have one of these records as buyer and the other as referrer. Merging would make the person their own referrer. Review those rows first.')); end if;

  return jsonb_build_object(
    'keep', jsonb_build_object('id',k.id,'name',k.full_name,'phone',k.phone,'email',k.email,
                               'created_at',k.created_at,'referred_by',k.referred_by),
    'merge', jsonb_build_object('id',m.id,'name',m.full_name,'phone',m.phone,'email',m.email,
                                'created_at',m.created_at,'referred_by',m.referred_by),
    'moving', v_counts,
    'wallets', jsonb_build_object(
      'keep_has',  exists(select 1 from public.customer_credit_wallets where customer_id = p_keep),
      'merge_has', exists(select 1 from public.customer_credit_wallets where customer_id = p_merge)),
    'blocking', v_blocks,
    'can_merge', jsonb_array_length(v_blocks) = 0);
end $function$
$p486$;
begin
  if md5(d) <> 'f66c9d63369ef3b831ca74906a99b587' then raise exception 'the copy of production''s preview is not its text (md5 %)', md5(d); end if;
  execute replace(d, 'CREATE OR REPLACE FUNCTION public.preview_customer_merge(', 'CREATE FUNCTION pg_temp.preview_before(');
end $before$;
create function pg_temp.pb(keep uuid, dup uuid) returns jsonb language plpgsql as
$$begin return pg_temp.preview_before(keep, dup);
exception when others then return jsonb_build_object('error', sqlerrm); end$$;
-- A merge or a Link as the signed-in Owner: its answer, or 'ERROR: ' and the message.
create function pg_temp.merge(keep text, dup text) returns text language plpgsql as
$$begin return public.merge_customer_records(pg_temp.c(keep), pg_temp.c(dup), 'Same person, checked', gen_random_uuid())::text;
exception when others then return 'ERROR: ' || sqlerrm; end$$;
create function pg_temp.ok(answer text) returns boolean language sql as
$$ select case when answer like '{%' then coalesce((answer::jsonb ->> 'success')::boolean or (answer::jsonb ->> 'ok')::boolean, false) else false end $$;
-- What an answer says, without its ids: a merge's or a Link's 'moved' (and the Link's ok), else the error.
create function pg_temp.said(answer text) returns text language sql as
$$ select case when answer like '{%' then 'moved ' || coalesce(answer::jsonb -> 'moved', 'null'::jsonb)::text
                                          || coalesce(', ok ' || (answer::jsonb ->> 'ok'), '') || coalesce(', ' || (answer::jsonb ->> 'message'), '')
               else answer end $$;
-- The answer without 486's issue and without can_merge (what production's preview answers otherwise).
create function pg_temp.without_new(p jsonb) returns jsonb language sql as
$$ select jsonb_set(p, '{blocking}', coalesce((select jsonb_agg(x order by o) from jsonb_array_elements(p -> 'blocking') with ordinality e(x, o)
                                               where x ->> 'issue' is distinct from 'duplicate_has_affiliate_account'), '[]'::jsonb)) - 'can_merge' $$;
create function pg_temp.news(p jsonb) returns jsonb language sql as
$$ select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(p -> 'blocking') x where x ->> 'issue' = 'duplicate_has_affiliate_account' $$;

select pg_temp.check(md5(pg_get_functiondef('public.preview_customer_merge(uuid,uuid)'::regprocedure)) = 'b98004c9a2522d7e564d34f10ca4e574',
  'P0 486 is installed (the preview is its AFTER version)');
select pg_temp.check(to_regclass('public.referral_phone_notices') is not null, 'P0 484 is in (referral_phone_notices is there)');
select pg_temp.check(not exists (select 1 from customers where public.normalize_customer_phone(phone) between '+61255504860' and '+61255504899'),
  'P0 no customer uses the test phones +61 2 5550 4860 to 4899 (the checks below assume so)');

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); u uuid; s uuid;
begin
  insert into tx values ('sfx', sfx),
    ('tail', '; the record to keep has neither a portal login nor an affiliate record. A merge decides that two records are one person, not whose login it is: keep the affiliate''s record and merge the other one into it.');
  u := gen_random_uuid(); insert into fx values ('owner', u);
  insert into auth.users(id, email, email_confirmed_at) values (u, 'z486-o-' || sfx || '@example.invalid', now());
  insert into profiles(id, full_name, email, role, is_active) values (u, 'Z486 Owner', 'z486-o-' || sfx || '@example.invalid', 'owner', true);
  insert into stores(name, code) values ('Z486 Test Store', 'Z486' || sfx) returning id into s; insert into fx values ('store', s);
end $$;
-- X: the records of every kind; r1 to r5 are the marks' referrals (mark1 has one mark, markw one withdrawn mark),
-- raff the referrer of the mark that names 'referral' as its referral.
do $$ declare r record; begin
  for r in select * from (values (1, 'plain', 'plain'), (2, 'login', 'login'), (3, 'logindis', 'logindis'), (4, 'aff', 'aff'),
             (5, 'affsusp', 'affsusp'), (6, 'affinact', 'affinact'), (7, 'affdel', 'affdel'), (8, 'marks', 'plain'), (9, 'both', 'both'),
             (10, 'referral', 'plain'), (11, 'mark1', 'plain'), (12, 'markw', 'plain'), (13, 'r1', 'plain'), (14, 'r2', 'plain'),
             (15, 'r3', 'plain'), (16, 'r4', 'plain'), (17, 'r5', 'plain'), (18, 'raff', 'aff')) v(o, k, kind) order by o loop
    perform pg_temp.cust(r.k, r.kind);
  end loop;
  perform pg_temp.mark('r1', 'marks'); perform pg_temp.mark('r2', 'marks', true); perform pg_temp.mark('r3', 'both');
  perform pg_temp.mark('r4', 'mark1'); perform pg_temp.mark('r5', 'markw', true); perform pg_temp.mark('referral', 'raff');
end $$;
-- What each kind holds, as the rule reads it, written out (not worked out): the head of the detail when it is the
-- duplicate (null: none), and whether, kept, it has a portal login or an affiliate record.
create temp table kinds(k text primary key, holds text, keeper_has boolean);
insert into kinds values
  ('plain', null, false), ('login', 'The duplicate holds the portal login', true),
  ('logindis', 'The duplicate holds the portal login', true), ('aff', 'The duplicate holds the affiliate record', true),
  ('affsusp', 'The duplicate holds the affiliate record', true), ('affinact', 'The duplicate holds the affiliate record', true),
  ('affdel', 'The duplicate holds the affiliate record', true),
  ('marks', 'The duplicate holds 2 /r/ phone-notice mark(s) naming it as referrer', false),
  ('both', 'The duplicate holds the portal login, the affiliate record and 1 /r/ phone-notice mark(s) naming it as referrer', true),
  ('referral', null, false), ('mark1', 'The duplicate holds 1 /r/ phone-notice mark(s) naming it as referrer', false),
  ('markw', 'The duplicate holds 1 /r/ phone-notice mark(s) naming it as referrer', false);
-- E: a deleted plain record, a deleted affiliate's record, and a buyer and a referrer with a commission between them.
do $$ begin
  perform pg_temp.cust('gone', 'plain'); perform pg_temp.cust('goneaff', 'aff'); perform pg_temp.cust('cbuy', 'plain'); perform pg_temp.cust('cref', 'aff');
end $$;
update customers set deleted_at = now() where id in (pg_temp.c('gone'), pg_temp.c('goneaff'));
do $$ declare i uuid; begin
  insert into invoices(invoice_no, store_id, customer_id, created_by)
  values ('Z486-' || pg_temp.tx('sfx'), pg_temp.fx('store'), pg_temp.c('cbuy'), pg_temp.fx('owner')) returning id into i;
  insert into commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, line_amount, rate, commission_amount, status)
  values (i, pg_temp.c('cbuy'), pg_temp.c('cref'), 'tier1', 100, 15, 15, 'earned');
end $$;
-- M: the permitted merges' records.
do $$ begin
  perform pg_temp.cust('mk', 'aff'); perform pg_temp.cust('md', 'plain'); perform pg_temp.cust('mlk', 'login'); perform pg_temp.cust('mla', 'aff');
  perform pg_temp.cust('mak', 'aff'); perform pg_temp.cust('mmd', 'plain'); perform pg_temp.cust('mr', 'plain');
  perform pg_temp.cust('mrc', 'plain', pg_temp.c('md'));
  perform pg_temp.mark('md', 'raff'); perform pg_temp.mark('mr', 'mmd');
end $$;
-- L: a customer already there (plain, with an email) and a fresh sign-up record with a login and an affiliate
-- record, listed for it.
do $$ begin perform pg_temp.cust('lk', 'plain'); perform pg_temp.cust('lf', 'both'); end $$;
update customers set email = pg_temp.mail('lk') where id = pg_temp.c('lk');
insert into affiliate_signup_matches(auth_user_id, fresh_customer_id, entered_phone, entered_name, reason, candidate_ids)
values (pg_temp.fx('u:lf'), pg_temp.c('lf'), '+61255504899', 'Zed486 Lf', 'name_match', array[pg_temp.c('lk')]);
-- D: an affiliate's record and a plain one, for a permitted merge with the marks table gone.
do $$ begin perform pg_temp.cust('dk', 'aff'); perform pg_temp.cust('dd', 'plain'); end $$;

-- ═════ X  Every combination ═════
select pg_temp.as_staff();
create temp table xr as
  select kk.k as keep, dk.k as dup, kk.keeper_has, dk.holds,
         pg_temp.pv(pg_temp.c(kk.k), pg_temp.c(dk.k)) as after, pg_temp.pb(pg_temp.c(kk.k), pg_temp.c(dk.k)) as before
    from kinds kk cross join kinds dk where kk.k <> dk.k;
select pg_temp.check(count(*) = 132 and bool_and(not (after ? 'error') and not (before ? 'error')),
  'X all 132 pairs previewed by 486''s preview and by production''s, with no error: '
  || coalesce(string_agg(case when after ? 'error' or before ? 'error' then keep || '<-' || dup || ': ' || coalesce(after ->> 'error', before ->> 'error') end, '; '), 'none'))
  from xr;
select pg_temp.check(bool_and(case when holds is not null and not keeper_has
                                   then pg_temp.news(after) = jsonb_build_array(jsonb_build_object('issue', 'duplicate_has_affiliate_account',
                                                                                                  'detail', holds || pg_temp.tx('tail')))
                                        and (after -> 'blocking') -> -1 = pg_temp.news(after) -> 0
                                   else pg_temp.news(after) = '[]'::jsonb end),
  'X the duplicate ' || dup || ': the new issue, last and in its words, exactly when the record kept has neither (wrong for: '
  || coalesce(string_agg(case when not (case when holds is not null and not keeper_has
                                             then pg_temp.news(after) = jsonb_build_array(jsonb_build_object('issue', 'duplicate_has_affiliate_account',
                                                                                                             'detail', holds || pg_temp.tx('tail')))
                                                  and (after -> 'blocking') -> -1 = pg_temp.news(after) -> 0
                                             else pg_temp.news(after) = '[]'::jsonb end)
                             then keep end, ', '), 'none') || ')')
  from xr group by dup order by dup;
select pg_temp.check(bool_and(pg_temp.without_new(after) = before - 'can_merge'),
  'X the duplicate ' || dup || ': everything else is production''s answer, the issues before in their order (differs for: '
  || coalesce(string_agg(case when pg_temp.without_new(after) is distinct from before - 'can_merge' then keep end, ', '), 'none') || ')')
  from xr group by dup order by dup;
select pg_temp.check(bool_and((after ->> 'can_merge')::boolean = (jsonb_array_length(after -> 'blocking') = 0)),
  'X can_merge is true exactly when nothing blocks, in all 132 pairs')
  from xr;
select pg_temp.check((select count(*) from xr where pg_temp.news(after) <> '[]'::jsonb) = 47
    and (select bool_and((before ->> 'can_merge')::boolean and not (after ->> 'can_merge')::boolean) from xr where pg_temp.news(after) <> '[]'::jsonb),
  'X 47 of the 132 pairs are newly refused, every one of them a merge production''s preview lets through');

-- ═════ E  The issues there before ═════
create temp table er as select k, pg_temp.pv(pg_temp.c(split_part(k, '<-', 1)), pg_temp.c(split_part(k, '<-', 2))) as p
  from unnest(array['plain<-gone', 'plain<-goneaff', 'gone<-plain', 'gone<-aff', 'aff<-affsusp', 'plain<-both',
                    'cbuy<-cref', 'cref<-cbuy', 'aff<-gone']) k;
select pg_temp.check((select p -> 'blocking' from er where k = 'plain<-gone')
    = '[{"issue": "duplicate_already_deleted", "detail": "The duplicate is already deleted; nothing would move."}]'::jsonb,
  'E the duplicate already deleted: as before, alone');
select pg_temp.check((select p -> 'blocking' from er where k = 'plain<-goneaff')
    = jsonb_build_array('{"issue": "duplicate_already_deleted", "detail": "The duplicate is already deleted; nothing would move."}'::jsonb,
                        jsonb_build_object('issue', 'duplicate_has_affiliate_account',
                                           'detail', 'The duplicate holds the affiliate record' || pg_temp.tx('tail'))),
  'E the duplicate already deleted, holding an affiliate record: as before, then the new issue');
select pg_temp.check((select p -> 'blocking' from er where k = 'gone<-plain')
    = '[{"issue": "keeper_deleted", "detail": "The record to keep is deleted. Restore it first."}]'::jsonb,
  'E the record kept deleted: as before, alone');
select pg_temp.check((select p -> 'blocking' from er where k = 'gone<-aff')
    = jsonb_build_array('{"issue": "keeper_deleted", "detail": "The record to keep is deleted. Restore it first."}'::jsonb,
                        jsonb_build_object('issue', 'duplicate_has_affiliate_account',
                                           'detail', 'The duplicate holds the affiliate record' || pg_temp.tx('tail'))),
  'E the record kept deleted, the duplicate an affiliate''s: as before, then the new issue');
select pg_temp.check((select p -> 'blocking' from er where k = 'aff<-affsusp')
    = jsonb_build_array(jsonb_build_object('issue', 'two_affiliate_records',
        'detail', 'Both records are affiliates. Which referral code and payout history survives is a decision about real money — resolve the affiliate records first, then merge.')),
  'E two affiliate records in use: as before, alone (the record kept has one)');
select pg_temp.check((select p -> 'blocking' from er where k = 'cbuy<-cref')
    = jsonb_build_array(jsonb_build_object('issue', 'commission_between_the_two',
        'detail', '1 commission row(s) have one of these records as buyer and the other as referrer. Merging would make the person their own referrer. Review those rows first.'),
                        jsonb_build_object('issue', 'duplicate_has_affiliate_account',
                                           'detail', 'The duplicate holds the affiliate record' || pg_temp.tx('tail'))),
  'E a commission between the two, the duplicate the affiliate: as before, then the new issue');
select pg_temp.check((select p -> 'blocking' from er where k = 'cref<-cbuy')
    = jsonb_build_array(jsonb_build_object('issue', 'commission_between_the_two',
        'detail', '1 commission row(s) have one of these records as buyer and the other as referrer. Merging would make the person their own referrer. Review those rows first.')),
  'E a commission between the two, the affiliate kept: as before, alone');
select pg_temp.check((select (p ->> 'can_merge')::boolean = false and jsonb_array_length(p -> 'blocking') = 1 from er where k = 'aff<-gone'),
  'E an affiliate''s record kept and a deleted plain duplicate: only the issue there before');
select pg_temp.check(bool_and(p - 'blocking' - 'can_merge' = pg_temp.pb(pg_temp.c(split_part(k, '<-', 1)), pg_temp.c(split_part(k, '<-', 2))) - 'blocking' - 'can_merge'),
  'E every other key as production''s answer in these pairs too')
  from er;

-- ═════ R  The merge refuses ═════
insert into tx select 'merge:' || k, pg_temp.err(format('select public.merge_customer_records(%L, %L, %L, %L)',
                 pg_temp.c(split_part(k, '<-', 1)), pg_temp.c(split_part(k, '<-', 2)), 'Same person, checked', gen_random_uuid()))
  from unnest(array['plain<-aff', 'plain<-login', 'plain<-logindis', 'plain<-affdel', 'plain<-marks', 'referral<-both', 'marks<-affsusp',
                    'plain<-mark1', 'referral<-markw', 'cbuy<-cref']) k;
select pg_temp.check(pg_temp.tx('merge:' || k) = 'This merge needs review first: ' || d || pg_temp.tx('tail'),
  'R keeping ' || split_part(k, '<-', 1) || ' and retiring ' || split_part(k, '<-', 2) || ': refused in the new issue''s words: ' || pg_temp.tx('merge:' || k))
  from (values ('plain<-aff', 'The duplicate holds the affiliate record'), ('plain<-login', 'The duplicate holds the portal login'),
               ('plain<-logindis', 'The duplicate holds the portal login'), ('plain<-affdel', 'The duplicate holds the affiliate record'),
               ('plain<-marks', 'The duplicate holds 2 /r/ phone-notice mark(s) naming it as referrer'),
               ('referral<-both', 'The duplicate holds the portal login, the affiliate record and 1 /r/ phone-notice mark(s) naming it as referrer'),
               ('marks<-affsusp', 'The duplicate holds the affiliate record'),
               ('plain<-mark1', 'The duplicate holds 1 /r/ phone-notice mark(s) naming it as referrer'),
               ('referral<-markw', 'The duplicate holds 1 /r/ phone-notice mark(s) naming it as referrer')) t(k, d);
select pg_temp.check(pg_temp.tx('merge:cbuy<-cref') = 'This merge needs review first: 1 commission row(s) have one of these records as buyer and the other as referrer. Merging would make the person their own referrer. Review those rows first. The duplicate holds the affiliate record' || pg_temp.tx('tail'),
  'R two issues: refused with both details, joined as before: ' || pg_temp.tx('merge:cbuy<-cref'));
select pg_temp.check((select count(*) from customers c where c.id in (select v from fx where k like 'c:%') and c.deleted_at is null)
                       = (select count(*) from fx where k like 'c:%') - 2
    and (select count(*) from customer_affiliates f where f.customer_id in (pg_temp.c('aff'), pg_temp.c('affdel'), pg_temp.c('affsusp'), pg_temp.c('both'), pg_temp.c('cref'))) = 5
    and (select count(*) from affiliate_accounts a where (a.customer_id, a.auth_user_id) in ((pg_temp.c('login'), pg_temp.fx('u:login')),
                                                                                             (pg_temp.c('logindis'), pg_temp.fx('u:logindis')),
                                                                                             (pg_temp.c('both'), pg_temp.fx('u:both')))) = 3
    and (select count(*) from referral_phone_notices n where n.referrer_customer_id = pg_temp.c('marks')) = 2
    and (select count(*) from referral_phone_notices n where n.referrer_customer_id = pg_temp.c('both')) = 1
    and not exists (select 1 from audit_logs l where l.action = 'customers_merged' and l.record_id in (select v from fx where k like 'c:%')),
  'R the refused merges changed nothing: every record in use as it was, the logins, the affiliate records and the marks where they were, no merge recorded');

-- ═════ M  Permitted merges, end to end ═════
insert into tx values ('merge:mk<-md', pg_temp.merge('mk', 'md'));
insert into tx values ('merge:mlk<-mla', pg_temp.merge('mlk', 'mla'));
insert into tx values ('merge:mak<-mmd', pg_temp.merge('mak', 'mmd'));
select pg_temp.check(pg_temp.ok(pg_temp.tx('merge:mk<-md'))
    and (select deleted_at is not null from customers where id = pg_temp.c('md'))
    and (select referred_by from customers where id = pg_temp.c('mrc')) = pg_temp.c('mk')
    and (select count(*) from referral_phone_notices n where n.customer_id = pg_temp.c('mk') and n.referrer_customer_id = pg_temp.c('raff')) = 1
    and (pg_temp.tx('merge:mk<-md')::jsonb -> 'moved' ->> 'referral_phone_notices.customer_id') = '1'
    and (select id from customer_affiliates where customer_id = pg_temp.c('mk')) = pg_temp.fx('a:mk'),
  'M keeping the affiliate''s record and retiring a plain one: merged; its referral and the mark naming it as the referral follow; the affiliate record stays: '
  || pg_temp.said(pg_temp.tx('merge:mk<-md')));
select pg_temp.check(pg_temp.ok(pg_temp.tx('merge:mlk<-mla'))
    and (select deleted_at is not null from customers where id = pg_temp.c('mla'))
    and (select id from customer_affiliates where customer_id = pg_temp.c('mlk')) = pg_temp.fx('a:mla')
    and exists (select 1 from affiliate_accounts a where a.customer_id = pg_temp.c('mlk') and a.auth_user_id = pg_temp.fx('u:mlk')),
  'M keeping a portal login''s record and retiring an affiliate''s: merged; the affiliate record follows, the login stays: ' || pg_temp.said(pg_temp.tx('merge:mlk<-mla')));
select pg_temp.check(pg_temp.ok(pg_temp.tx('merge:mak<-mmd'))
    and (select deleted_at is not null from customers where id = pg_temp.c('mmd'))
    and (select referrer_customer_id from referral_phone_notices n where n.customer_id = pg_temp.c('mr')) = pg_temp.c('mak')
    and (pg_temp.tx('merge:mak<-mmd')::jsonb -> 'moved' ->> 'referral_phone_notices.referrer_customer_id') = '1',
  'M keeping an affiliate''s record and retiring one with a mark naming it as referrer: merged; the mark follows: ' || pg_temp.said(pg_temp.tx('merge:mak<-mmd')));

-- ═════ L  437's Link to this customer ═════
insert into tx values ('lpv', pg_temp.pv(pg_temp.c('lk'), pg_temp.c('lf'))::text);
insert into tx values ('lmerge', pg_temp.err(format('select public.merge_customer_records(%L, %L, %L, %L)', pg_temp.c('lk'), pg_temp.c('lf'),
                                                    'Affiliate sign-up linked to the customer already there (Affiliates page)', gen_random_uuid())));
do $$ begin
  begin
    perform public.merge_customer_records(pg_temp.c('lk'), pg_temp.c('lf'), 'From a DO block', gen_random_uuid());
    insert into tx values ('ldo', 'ok');
  exception when others then insert into tx values ('ldo', sqlerrm);
  end;
end $$;
create function pg_temp.link_affiliate_signup(p_match_id uuid, p_customer_id uuid, p_note text, p_request_id uuid,
                                              p_use_signup_phone boolean default false) returns jsonb language plpgsql as
$$declare v jsonb; f uuid := (select m.fresh_customer_id from public.affiliate_signup_matches m where m.id = p_match_id); begin
  -- the call as link_affiliate_signup makes it
  v := public.merge_customer_records(p_customer_id, f, p_note, p_request_id);
  return v;
end$$;
insert into tx values ('llook', pg_temp.err(format('select pg_temp.link_affiliate_signup(%L, %L, %L, %L)',
  (select id from affiliate_signup_matches where auth_user_id = pg_temp.fx('u:lf')), pg_temp.c('lk'), 'look-alike', gen_random_uuid())));
select pg_temp.check(pg_temp.news(pg_temp.tx('lpv')::jsonb) = jsonb_build_array(jsonb_build_object('issue', 'duplicate_has_affiliate_account',
                       'detail', 'The duplicate holds the portal login and the affiliate record' || pg_temp.tx('tail'))),
  'L the preview of the same pair, keeping the customer and retiring the fresh record: refused');
select pg_temp.check(pg_temp.tx('lmerge') = 'This merge needs review first: The duplicate holds the portal login and the affiliate record' || pg_temp.tx('tail')
    and pg_temp.tx('ldo') = pg_temp.tx('lmerge') and pg_temp.tx('llook') = pg_temp.tx('lmerge'),
  'L the same merge by hand, from a DO block and from a look-alike link_affiliate_signup in pg_temp: refused ('
  || pg_temp.tx('lmerge') || ' | ' || pg_temp.tx('ldo') || ' | ' || pg_temp.tx('llook') || ')');
select pg_temp.check(exists (select 1 from customers where id = pg_temp.c('lf') and deleted_at is null)
    and exists (select 1 from affiliate_accounts a where a.customer_id = pg_temp.c('lf') and a.auth_user_id = pg_temp.fx('u:lf'))
    and exists (select 1 from customer_affiliates f where f.customer_id = pg_temp.c('lf')),
  'L the refusals changed nothing: the fresh record, its login and its affiliate record as they were');
do $$ declare m uuid := (select id from affiliate_signup_matches where auth_user_id = pg_temp.fx('u:lf') and status = 'open'); begin
  insert into tx values ('link', public.link_affiliate_signup(m, pg_temp.c('lk'), 'Same person, checked by phone', gen_random_uuid())::text);
exception when others then insert into tx values ('link', 'ERROR: ' || sqlerrm);
end $$;
select pg_temp.check(pg_temp.ok(pg_temp.tx('link'))
    and exists (select 1 from affiliate_accounts a where a.customer_id = pg_temp.c('lk') and a.auth_user_id = pg_temp.fx('u:lf'))
    and (select id from customer_affiliates where customer_id = pg_temp.c('lk')) = pg_temp.fx('a:lf')
    and (select deleted_at is not null from customers where id = pg_temp.c('lf'))
    and (select status from affiliate_signup_matches where auth_user_id = pg_temp.fx('u:lf')) = 'linked',
  'L Link to this customer links the fresh sign-up to a customer with no affiliate record, as before: '
  || pg_temp.said(pg_temp.tx('link')));
do $$ begin
  if to_regprocedure('public.affiliate_login_link_proof(uuid,uuid)') is null then
    raise notice 'SKIP  L proof (484''s proof is not in this database)'; return; end if;
  perform pg_temp.check(public.affiliate_login_link_proof(pg_temp.fx('u:lf'), pg_temp.c('lk')) is not null,
    'L after the Link the login is proven on the customer (484): ' || coalesce(public.affiliate_login_link_proof(pg_temp.fx('u:lf'), pg_temp.c('lk')), 'not proven'));
end $$;

-- ═════ D  484's UNDO level 2 situation: no marks table ═════
savepoint d486;
drop table public.referral_phone_notices;
select pg_temp.as_staff();
select coalesce(pg_temp.news(pg_temp.pv(pg_temp.c('plain'), pg_temp.c('login'))) = jsonb_build_array(jsonb_build_object('issue', 'duplicate_has_affiliate_account',
         'detail', 'The duplicate holds the portal login' || pg_temp.tx('tail'))), false) as d_login,
       coalesce(pg_temp.news(pg_temp.pv(pg_temp.c('plain'), pg_temp.c('both'))) = jsonb_build_array(jsonb_build_object('issue', 'duplicate_has_affiliate_account',
         'detail', 'The duplicate holds the portal login and the affiliate record' || pg_temp.tx('tail'))), false) as d_both,
       coalesce(pg_temp.pv(pg_temp.c('plain'), pg_temp.c('marks')) -> 'blocking' = '[]'::jsonb, false) as d_marks,
       coalesce(pg_temp.pv(pg_temp.c('plain'), pg_temp.c('login')) ->> 'error', 'none') as d_error,
       pg_temp.merge('dk', 'dd') as d_merge
\gset
select coalesce((select deleted_at is not null from customers where id = pg_temp.c('dd')), false) as d_retired
\gset
rollback to savepoint d486;
select pg_temp.check(:'d_error' = 'none' and :'d_login'::boolean and :'d_both'::boolean,
  'D with the marks table gone, the preview answers with no error (' || :'d_error' || ') and still refuses a login''s or an affiliate''s record (no marks named)');
select pg_temp.check(:'d_marks'::boolean, 'D with the marks table gone, a record whose only hold was its marks is a plain record');
select pg_temp.check(pg_temp.ok(:'d_merge') and :'d_retired'::boolean, 'D with the marks table gone, a permitted merge goes through: ' || pg_temp.said(:'d_merge'));
select pg_temp.check(to_regclass('public.referral_phone_notices') is not null and (select count(*) from referral_phone_notices n where n.referrer_customer_id = pg_temp.c('marks')) = 2,
  'D the savepoint put the table and its marks back');
select pg_temp.as_staff();

-- ═════ G  Grants ═════
select pg_temp.check((select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
                       where p.oid = 'public.preview_customer_merge(uuid,uuid)'::regprocedure) = array['postgres=X/postgres', 'service_role=X/postgres']
    and not has_function_privilege('anon', 'public.preview_customer_merge(uuid,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.preview_customer_merge(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.merge_customer_records(uuid,uuid,text,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.merge_customer_records(uuid,uuid,text,uuid)', 'execute'),
  'G the preview and the merge stay the owner''s and the service role''s (no client role)');
select pg_temp.as_server();
select pg_temp.check(pg_temp.pv(pg_temp.c('plain'), pg_temp.c('aff')) ->> 'error' = 'Only an Owner or Manager can review a customer merge',
  'G signed out, the preview still refuses before reading anything');
select pg_temp.as_staff();

-- ═════ U  UNDO, as written in 486's header ═════
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('29991231000486', '486_merge_guard_keeps_the_affiliate_record', array['486 suite: a stand-in for the file''s text']);
insert into tx values ('undo1', pg_temp.err($u486$
do $undo$
declare
  c_sig constant text := 'preview_customer_merge(uuid,uuid)';
  c_before constant text := 'f66c9d63369ef3b831ca74906a99b587';
  c_after constant text := 'b98004c9a2522d7e564d34f10ca4e574';
  -- this file's md5 as applied (its history row's): fill in before running
  c_m constant text := 'f35677df3da8a95b4d70ef236a02ea6d';
  v_def text; v_path text := current_setting('search_path'); n int;
begin
  perform set_config('search_path', 'public', true);
  if to_regprocedure('public.' || c_sig) is null
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) is distinct from c_after then
    raise exception 'UNDO 486: public.% is not 486''s version; nothing changed', c_sig; end if;
  -- 486's block out again: production's text of 2 Nov 2026 (318's).
  v_def := replace(pg_get_functiondef(to_regprocedure('public.' || c_sig)), E'\n\n' ||
$b486$  -- 486 (the Owner, 2 Nov 2026): a merge decides that two records are one
  -- person, not whose login it is. It moves the duplicate's portal login,
  -- affiliate record and the /r/ marks naming it as referrer onto the record
  -- kept, whose email a form may have typed while it was an ordinary record;
  -- a login that then verifies that inbox is proven (484's verified_email).
  -- So the duplicate may not be the record that holds them while the record
  -- to keep has neither a portal login nor an affiliate record (any status):
  -- keep the affiliate's record and merge the other one into it. Not refused:
  -- the merge that 437's Link to this customer runs (link_affiliate_signup
  -- calls merge_customer_records, which calls this), a staff decision about
  -- whose login it is, which 484 counts as proof; it is read from the call
  -- stack, which a client cannot set (a look-alike function made by a role
  -- that can create functions can: NOT COVERED). The marks are read only
  -- while their table is there (484's UNDO level 2 drops it).
  declare
    v_login boolean := exists (select 1 from public.affiliate_accounts a where a.customer_id = p_merge);
    v_aff boolean := exists (select 1 from public.customer_affiliates f where f.customer_id = p_merge);
    v_marks bigint := 0;
    v_ctx text;
    v_held text[];
  begin
    if to_regclass('public.referral_phone_notices') is not null then
      execute 'select count(*) from public.referral_phone_notices where referrer_customer_id = $1'
        into v_marks using p_merge;
    end if;
    get diagnostics v_ctx = pg_context;
    if (v_login or v_aff or v_marks > 0)
       and not exists (select 1 from public.affiliate_accounts a where a.customer_id = p_keep)
       and not exists (select 1 from public.customer_affiliates f where f.customer_id = p_keep)
       and not coalesce(split_part(split_part(v_ctx, chr(10), 2), ' line ', 1)
                          in ('PL/pgSQL function merge_customer_records(uuid,uuid,text,uuid)',
                              'PL/pgSQL function public.merge_customer_records(uuid,uuid,text,uuid)')
                        and split_part(split_part(v_ctx, chr(10), 3), ' line ', 1)
                          in ('PL/pgSQL function link_affiliate_signup(uuid,uuid,text,uuid,boolean)',
                              'PL/pgSQL function public.link_affiliate_signup(uuid,uuid,text,uuid,boolean)'), false) then
      -- What the duplicate holds, joined as "a", "a and b" or "a, b and c".
      v_held := array_remove(array[
          case when v_login then 'the portal login' end,
          case when v_aff then 'the affiliate record' end,
          case when v_marks > 0 then v_marks || ' /r/ phone-notice mark(s) naming it as referrer' end], null);
      v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','duplicate_has_affiliate_account',
        'detail','The duplicate holds '
          || case when cardinality(v_held) = 1 then v_held[1]
                  else array_to_string(v_held[1:cardinality(v_held) - 1], ', ') || ' and ' || v_held[cardinality(v_held)] end
          || '; the record to keep has neither a portal login nor an affiliate record. A merge decides that two records are one person, not whose login it is: keep the affiliate''s record and merge the other one into it.'));
    end if;
  end;$b486$, '');
  if md5(v_def) <> c_before then
    raise exception 'UNDO 486: the rebuilt public.% is not production''s of 2 Nov 2026 (md5 %); nothing changed', c_sig, md5(v_def); end if;
  execute v_def;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_before then
    raise exception 'UNDO 486: public.% did not go back to its version before 486', c_sig; end if;
  -- Every 486 history row holding this file's text.
  delete from supabase_migrations.schema_migrations
   where name = '486_merge_guard_keeps_the_affiliate_record' and md5(array_to_string(statements, '')) = c_m;
  get diagnostics n = row_count;
  if n < 1 then raise exception 'UNDO 486: no 486 history row holds the text with md5 %; nothing changed', c_m; end if;
  raise notice 'UNDO 486: public.% is back to its version before 486; % history row(s) deleted', c_sig, n;
  perform set_config('search_path', v_path, true);
end $undo$;
$u486$));
select pg_temp.check(pg_temp.tx('undo1') = 'ok'
    and md5(pg_get_functiondef('public.preview_customer_merge(uuid,uuid)'::regprocedure)) = 'f66c9d63369ef3b831ca74906a99b587'
    and not exists (select 1 from supabase_migrations.schema_migrations where version = '29991231000486'),
  'U UNDO puts the preview back to production''s text of 2 Nov 2026 and deletes the history row: ' || pg_temp.tx('undo1'));
select pg_temp.check((select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
                       where p.oid = 'public.preview_customer_merge(uuid,uuid)'::regprocedure) = array['postgres=X/postgres', 'service_role=X/postgres'],
  'U UNDO keeps the preview''s grants');
select pg_temp.check((pg_temp.pv(pg_temp.c('plain'), pg_temp.c('aff')) ->> 'can_merge')::boolean
    and pg_temp.pv(pg_temp.c('plain'), pg_temp.c('aff')) = pg_temp.pb(pg_temp.c('plain'), pg_temp.c('aff')),
  'U after UNDO, keeping a plain record and retiring an affiliate''s previews as before 486 (not refused)');
insert into tx values ('undo2', pg_temp.err($u486$
do $undo$
declare
  c_sig constant text := 'preview_customer_merge(uuid,uuid)';
  c_before constant text := 'f66c9d63369ef3b831ca74906a99b587';
  c_after constant text := 'b98004c9a2522d7e564d34f10ca4e574';
  -- this file's md5 as applied (its history row's): fill in before running
  c_m constant text := 'f35677df3da8a95b4d70ef236a02ea6d';
  v_def text; v_path text := current_setting('search_path'); n int;
begin
  perform set_config('search_path', 'public', true);
  if to_regprocedure('public.' || c_sig) is null
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) is distinct from c_after then
    raise exception 'UNDO 486: public.% is not 486''s version; nothing changed', c_sig; end if;
  -- 486's block out again: production's text of 2 Nov 2026 (318's).
  v_def := replace(pg_get_functiondef(to_regprocedure('public.' || c_sig)), E'\n\n' ||
$b486$  -- 486 (the Owner, 2 Nov 2026): a merge decides that two records are one
  -- person, not whose login it is. It moves the duplicate's portal login,
  -- affiliate record and the /r/ marks naming it as referrer onto the record
  -- kept, whose email a form may have typed while it was an ordinary record;
  -- a login that then verifies that inbox is proven (484's verified_email).
  -- So the duplicate may not be the record that holds them while the record
  -- to keep has neither a portal login nor an affiliate record (any status):
  -- keep the affiliate's record and merge the other one into it. Not refused:
  -- the merge that 437's Link to this customer runs (link_affiliate_signup
  -- calls merge_customer_records, which calls this), a staff decision about
  -- whose login it is, which 484 counts as proof; it is read from the call
  -- stack, which a client cannot set (a look-alike function made by a role
  -- that can create functions can: NOT COVERED). The marks are read only
  -- while their table is there (484's UNDO level 2 drops it).
  declare
    v_login boolean := exists (select 1 from public.affiliate_accounts a where a.customer_id = p_merge);
    v_aff boolean := exists (select 1 from public.customer_affiliates f where f.customer_id = p_merge);
    v_marks bigint := 0;
    v_ctx text;
    v_held text[];
  begin
    if to_regclass('public.referral_phone_notices') is not null then
      execute 'select count(*) from public.referral_phone_notices where referrer_customer_id = $1'
        into v_marks using p_merge;
    end if;
    get diagnostics v_ctx = pg_context;
    if (v_login or v_aff or v_marks > 0)
       and not exists (select 1 from public.affiliate_accounts a where a.customer_id = p_keep)
       and not exists (select 1 from public.customer_affiliates f where f.customer_id = p_keep)
       and not coalesce(split_part(split_part(v_ctx, chr(10), 2), ' line ', 1)
                          in ('PL/pgSQL function merge_customer_records(uuid,uuid,text,uuid)',
                              'PL/pgSQL function public.merge_customer_records(uuid,uuid,text,uuid)')
                        and split_part(split_part(v_ctx, chr(10), 3), ' line ', 1)
                          in ('PL/pgSQL function link_affiliate_signup(uuid,uuid,text,uuid,boolean)',
                              'PL/pgSQL function public.link_affiliate_signup(uuid,uuid,text,uuid,boolean)'), false) then
      -- What the duplicate holds, joined as "a", "a and b" or "a, b and c".
      v_held := array_remove(array[
          case when v_login then 'the portal login' end,
          case when v_aff then 'the affiliate record' end,
          case when v_marks > 0 then v_marks || ' /r/ phone-notice mark(s) naming it as referrer' end], null);
      v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','duplicate_has_affiliate_account',
        'detail','The duplicate holds '
          || case when cardinality(v_held) = 1 then v_held[1]
                  else array_to_string(v_held[1:cardinality(v_held) - 1], ', ') || ' and ' || v_held[cardinality(v_held)] end
          || '; the record to keep has neither a portal login nor an affiliate record. A merge decides that two records are one person, not whose login it is: keep the affiliate''s record and merge the other one into it.'));
    end if;
  end;$b486$, '');
  if md5(v_def) <> c_before then
    raise exception 'UNDO 486: the rebuilt public.% is not production''s of 2 Nov 2026 (md5 %); nothing changed', c_sig, md5(v_def); end if;
  execute v_def;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_before then
    raise exception 'UNDO 486: public.% did not go back to its version before 486', c_sig; end if;
  -- Every 486 history row holding this file's text.
  delete from supabase_migrations.schema_migrations
   where name = '486_merge_guard_keeps_the_affiliate_record' and md5(array_to_string(statements, '')) = c_m;
  get diagnostics n = row_count;
  if n < 1 then raise exception 'UNDO 486: no 486 history row holds the text with md5 %; nothing changed', c_m; end if;
  raise notice 'UNDO 486: public.% is back to its version before 486; % history row(s) deleted', c_sig, n;
  perform set_config('search_path', v_path, true);
end $undo$;
$u486$));
select pg_temp.check(pg_temp.tx('undo2') = 'UNDO 486: public.preview_customer_merge(uuid,uuid) is not 486''s version; nothing changed'
    and md5(pg_get_functiondef('public.preview_customer_merge(uuid,uuid)'::regprocedure)) = 'f66c9d63369ef3b831ca74906a99b587',
  'U a second UNDO is refused and changes nothing: ' || pg_temp.tx('undo2'));
\ir ../../../supabase/486_merge_guard_keeps_the_affiliate_record.sql
select pg_temp.as_staff();
select pg_temp.check(pg_temp.news(pg_temp.pv(pg_temp.c('plain'), pg_temp.c('aff'))) <> '[]'::jsonb,
  'U 486 installs again after the UNDO and refuses again');

-- ═════ I  Installs ═════
select pg_temp.check(not exists (select 1 from m486 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select count(*) from m486),
  'I running 486 a second time (and again after the UNDO) changed no function (with skip_install: nothing changed during the checks)');
select pg_temp.check(md5(pg_get_functiondef('public.preview_customer_merge(uuid,uuid)'::regprocedure)) = 'b98004c9a2522d7e564d34f10ca4e574',
  'I the preview is 486''s AFTER version');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All merge-guard-486 checks passed.';
end $$;
rollback;
