-- TikTok's real bank payouts from the Withdrawal records (375).
--
--   B1 A settlement file is staged with its Withdrawal records: the settled
--      lines exactly as before, the records with the file (a row without a
--      Reference ID is skipped; nothing else in a row is kept). They count
--      once the file is confirmed.
--   B2 A payout comes with the app's own figure for its week (Thursday to the
--      Wednesday on or before the day it was paid). A record in two files
--      counts once.
--   B3 A payout on another day than Wednesday belongs to the Wednesday before.
--   B4 A payout not yet transferred is listed as such.
--   B5 A finished Wednesday with no transferred payout imported is listed when
--      the app says its week pays out, or no imported file reaches it; one
--      paid after the end date still counts for it.
--   B6 A deleted file's records stop counting; the dates choose the payouts.
--   B8 A file whose lines were all imported before is confirmed for its
--      records alone. A later file never replaces a payout: the transferred
--      record from the first file is kept, and a file that disagrees on the
--      amount is named.
--   B7 Who may: whoever may import a settlement file may stage one and see
--      what it brought; only active Owners and Managers read the payouts; the
--      table is closed.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Needs 374 and 375 (install them after "begin;" on
-- a database that does not have them yet). September 2026 must hold no other
-- TikTok lines or payouts.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
-- Production's user_has_store_access (29 Sep 2026).
create or replace function public.user_has_store_access(target_store_id uuid)
 returns boolean language sql security definer set search_path to 'public' as $f$
  select exists (select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true and p.role in ('owner','admin'))
  or exists (select 1 from public.user_store_assignments usa
    join public.profiles p on p.id = usa.user_id
    where usa.user_id = auth.uid() and usa.store_id = target_store_id and p.is_active = true)
$f$;
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
$$ select set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
-- One settled line of TikTok's income export.
create function pg_temp.ln(ord text, settle text, rev text, fee text, settled text) returns jsonb language sql as
$$ select jsonb_build_object('order_id', 'B375-' || ord || '-' || pg_temp.tx('sfx'), 'transaction_type', 'Order',
     'related_order_id', 'B375-' || ord || '-' || pg_temp.tx('sfx'),
     'settlement_amount', settle, 'revenue_amount', rev, 'fee_amount', fee, 'adjustment_amount', '0',
     'currency', 'SGD', 'order_created_time', '2026/08/20', 'settled_time', settled) $$;
-- One row of the Withdrawal records sheet, as the page sends it.
create function pg_temp.wr(typ text, ref text, amount text, day text, status text default 'Transferred') returns jsonb language sql as
$$ select jsonb_build_object('transaction_type', typ, 'reference_id', 'B375' || ref || pg_temp.tx('sfx'),
     'request_time', day, 'amount', amount, 'status', status, 'success_time', day) $$;
create function pg_temp.stage(file text, lines jsonb, recs jsonb) returns uuid language sql as
$$ select public.stage_tiktok_settlement_file(pg_temp.fx('st'), 'B375 ' || file || '.xlsx', 'Order details', lines, recs) $$;
create function pg_temp.payouts(f date, t date) returns jsonb language sql as
$$ select public.tiktok_bank_payouts(f, t) $$;
create function pg_temp.payout(m jsonb, ref text) returns jsonb language sql as
$$ select p from jsonb_array_elements(m->'payouts') p where p->>'reference_id' = 'B375' || ref || pg_temp.tx('sfx') $$;

-- ═════ Fixtures ═════
do $$
declare o uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); a uuid:=gen_random_uuid();
 od uuid:=gen_random_uuid(); s2 uuid:=gen_random_uuid(); sfx text:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6)); st uuid;
begin
 insert into auth.users(id,email) values
   (o,'b375-o-'||lower(sfx)||'@tests.invalid'),(m,'b375-m-'||lower(sfx)||'@tests.invalid'),
   (s,'b375-s-'||lower(sfx)||'@tests.invalid'),(a,'b375-a-'||lower(sfx)||'@tests.invalid'),
   (od,'b375-od-'||lower(sfx)||'@tests.invalid'),(s2,'b375-s2-'||lower(sfx)||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (o,'B375 Owner','b375-o-'||lower(sfx)||'@tests.invalid','owner'),
   (m,'B375 Manager','b375-m-'||lower(sfx)||'@tests.invalid','manager'),
   (s,'B375 Staff','b375-s-'||lower(sfx)||'@tests.invalid','staff'),
   (a,'B375 Admin','b375-a-'||lower(sfx)||'@tests.invalid','admin'),
   (od,'B375 Former Owner','b375-od-'||lower(sfx)||'@tests.invalid','owner'),
   (s2,'B375 Other Staff','b375-s2-'||lower(sfx)||'@tests.invalid','staff');
 update profiles set is_active = false where id = od;
 insert into stores(name,code,country_code) values('B375 Store '||sfx,'B375'||sfx,'SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(s,st);
 insert into fx values('o',o),('m',m),('s',s),('a',a),('od',od),('s2',s2),('st',st);
 insert into tx values('sfx',sfx);
end $$;
select pg_temp.as_user('o');
select pg_temp.check(not exists (select 1 from public.tiktok_settlement_rows
                                  where settled_time >= '2026-08-27'::date::timestamp at time zone 'Asia/Singapore'
                                    and settled_time <  '2026-10-01'::date::timestamp at time zone 'Asia/Singapore')
    and not exists (select 1 from public.tiktok_balance_records where coalesce(success_date, request_date) between '2026-08-27' and '2026-09-30'),
  'B0 September 2026 holds no other TikTok lines or payouts (the checks below assume so)');

-- ═════ B1 Staged with the file, counted once it is confirmed ═════
do $$
declare b uuid; m jsonb;
begin
 b := pg_temp.stage('A', jsonb_build_array(
   pg_temp.ln('A', '80.00', '100.00', '-20.00', '2026/08/27'),
   pg_temp.ln('B', '40.00', '50.00', '-10.00', '2026/09/02')),
   jsonb_build_array(
   pg_temp.wr('Earnings', 'E1', '80', '2026/08/27'),
   pg_temp.wr('Earnings', 'E2', '40', '2026/09/02'),
   pg_temp.wr('Payments', 'P1', '-120', '2026/09/02') || jsonb_build_object('bank_account', 'BANK-ACCOUNT-NOT-KEPT'),
   jsonb_build_object('transaction_type', 'Payments', 'reference_id', '', 'amount', '-1', 'success_time', '2026/09/02')));
 insert into fx values ('bA', b);
 perform pg_temp.check((select count(*) from public.tiktok_settlement_rows where batch_id = b) = 2
     and (select count(*) from public.tiktok_balance_records where batch_id = b) = 3
     and not exists (select 1 from public.tiktok_balance_records r where batch_id = b
                       and to_jsonb(r)::text like '%BANK-ACCOUNT-NOT-KEPT%'),
   'B1 the settled lines are staged as before, and the records with the file: the one without a Reference ID is skipped, the bank account is not kept');
 perform pg_temp.check((select (transaction_type, request_date, success_date, amount, status)
                          = ('Payments', '2026-09-02'::date, '2026-09-02'::date, -120.00::numeric, 'Transferred')
                          from public.tiktok_balance_records where batch_id = b and transaction_type = 'Payments'),
   'B1 a payout keeps its type, dates (Singapore), amount and status');
 m := pg_temp.payouts('2026-09-01', '2026-09-30');
 perform pg_temp.check(jsonb_array_length(m->'payouts') = 0, 'B1 records of a file not yet confirmed do not count');
 perform public.confirm_tiktok_settlement_batch(b, null);
 m := pg_temp.payouts('2026-09-01', '2026-09-30');
 insert into tx values ('p1', (pg_temp.payout(m, 'P1'))::text);
 perform pg_temp.check(jsonb_array_length(m->'payouts') = 1
     and (pg_temp.payout(m, 'P1')->>'amount')::numeric = 120.00
     and (pg_temp.payout(m, 'P1')->>'transferred')::boolean,
   'B1 once the file is confirmed, its payout counts, as the money paid (120.00), got ' || coalesce(pg_temp.tx('p1'), 'nothing'));
exception when others then perform pg_temp.check(false, 'B1 raised: ' || sqlerrm);
end $$;

-- ═════ B2 The app's figure for the week; a record in two files counts once ═════
select pg_temp.check((pg_temp.tx('p1')::jsonb->>'paid_on', pg_temp.tx('p1')::jsonb->>'wednesday', pg_temp.tx('p1')::jsonb->>'week_start')
                       = ('2026-09-02', '2026-09-02', '2026-08-27')
    and (pg_temp.tx('p1')::jsonb->>'app_payout')::numeric = 120.00,
  'B2 the payout of Wed 2 Sep is for Thu 27 Aug – Wed 2 Sep, and the app''s figure for that week is the same, 120.00');
do $$
declare b uuid; m jsonb;
begin
 b := pg_temp.stage('B', jsonb_build_array(
   pg_temp.ln('C', '60.00', '70.00', '-10.00', '2026/09/03')),
   jsonb_build_array(
   pg_temp.wr('Payments', 'P1', '-120', '2026/09/02'),
   pg_temp.wr('Payments', 'P2', '-50', '2026/09/09')));
 perform public.confirm_tiktok_settlement_batch(b, null);
 -- One transaction has one now(): each later file is confirmed later.
 update public.tiktok_import_batches set confirmed_at = confirmed_at + interval '1 hour' where id = b;
 m := pg_temp.payouts('2026-09-01', '2026-09-30');
 perform pg_temp.check((select count(*) from jsonb_array_elements(m->'payouts') p where p->>'reference_id' like 'B375P1%') = 1,
   'B2 a payout in two files counts once');
 perform pg_temp.check((pg_temp.payout(m, 'P2')->>'amount')::numeric = 50.00
     and (pg_temp.payout(m, 'P2')->>'app_payout')::numeric = 60.00,
   'B2 a payout that differs from the app''s figure for its week comes with both: TikTok 50.00, the app 60.00');
exception when others then perform pg_temp.check(false, 'B2 raised: ' || sqlerrm);
end $$;

-- ═════ B3 B4 B5 Another day, not transferred, a Wednesday without one ═════
do $$
declare b uuid; m jsonb;
begin
 b := pg_temp.stage('C', jsonb_build_array(
   pg_temp.ln('D', '15.00', '18.00', '-3.00', '2026/09/21'),
   pg_temp.ln('E', '25.00', '30.00', '-5.00', '2026/09/28')),
   jsonb_build_array(
   pg_temp.wr('Payments', 'P3', '-30', '2026/09/17'),
   pg_temp.wr('Payments', 'P4', '-15', '2026/09/23', 'Processing')));
 perform public.confirm_tiktok_settlement_batch(b, null);
 insert into fx values ('bC', b);
 m := pg_temp.payouts('2026-09-01', '2026-09-30');
 insert into tx values ('sep', m::text);
 perform pg_temp.check((pg_temp.payout(m, 'P3')->>'paid_on', pg_temp.payout(m, 'P3')->>'wednesday', pg_temp.payout(m, 'P3')->>'week_start')
                         = ('2026-09-17', '2026-09-16', '2026-09-10'),
   'B3 a payout on a Thursday is for the week up to the Wednesday before it');
 perform pg_temp.check(not (pg_temp.payout(m, 'P4')->>'transferred')::boolean and pg_temp.payout(m, 'P4')->>'status' = 'Processing',
   'B4 a payout not yet transferred is listed as such');
 perform pg_temp.check((select string_agg(w->>'wednesday' || '=' || (w->>'app_payout'), ' ' order by w->>'wednesday')
                          from jsonb_array_elements(m->'wednesdays_without_payout') w) = '2026-09-30=25.00',
   'B5 the Wednesday the app says pays out, with no payout imported, is listed (23 Sep is not: its payout is listed as not transferred), got '
     || coalesce((select string_agg(w->>'wednesday' || '=' || (w->>'app_payout'), ' ') from jsonb_array_elements(m->'wednesdays_without_payout') w), 'none'));
exception when others then perform pg_temp.check(false, 'B3-5 raised: ' || sqlerrm);
end $$;

-- ═════ B6 A deleted file; the dates ═════
do $$
declare m jsonb;
begin
 update public.tiktok_import_batches set deleted_at = now() where id = pg_temp.fx('bC');
 m := pg_temp.payouts('2026-09-01', '2026-09-30');
 perform pg_temp.check(pg_temp.payout(m, 'P3') is null and pg_temp.payout(m, 'P4') is null and pg_temp.payout(m, 'P1') is not null,
   'B6 a deleted file''s payouts stop counting');
 perform pg_temp.check((select string_agg(w->>'wednesday' || '=' || (w->>'app_payout') || '/' || jsonb_array_length(w->'uncovered_days'), ' ' order by w->>'wednesday')
                          from jsonb_array_elements(m->'wednesdays_without_payout') w) = '2026-09-16=0.00/7 2026-09-23=15.00/7 2026-09-30=25.00/7',
   'B5 a Wednesday no imported file reaches is listed even though the app has nothing for it (16 Sep; a confirmed file''s lines still count, so 23 and 30 Sep keep their figures), got '
     || coalesce((select string_agg(w->>'wednesday' || '=' || (w->>'app_payout') || '/' || jsonb_array_length(w->'uncovered_days'), ' ') from jsonb_array_elements(m->'wednesdays_without_payout') w), 'none'));
 -- A file reaching Thu 10 – Wed 16 Sep, every line left out at confirmation.
 perform public.confirm_tiktok_settlement_batch(pg_temp.stage('F', jsonb_build_array(
   pg_temp.ln('G', '7.00', '8.00', '-1.00', '2026/09/10'), pg_temp.ln('H', '9.00', '10.00', '-1.00', '2026/09/16')), '[]'::jsonb), '[]'::jsonb);
 m := pg_temp.payouts('2026-09-01', '2026-09-30');
 perform pg_temp.check((select w->>'app_payout' || '/' || jsonb_array_length(w->'uncovered_days') || '/' || (w->>'left_out_count')
                          from jsonb_array_elements(m->'wednesdays_without_payout') w where w->>'wednesday' = '2026-09-16') = '0.00/0/2',
   'B5 a Wednesday whose lines were all left out is listed, though the file reaches it and the app has nothing for it, got '
     || coalesce((m->'wednesdays_without_payout')::text, 'none'));
 update public.tiktok_import_batches set deleted_at = null where id = pg_temp.fx('bC');
 m := pg_temp.payouts('2026-09-03', '2026-09-16');
 perform pg_temp.check((select string_agg(left(p->>'reference_id', 6), ' ' order by p->>'paid_on') from jsonb_array_elements(m->'payouts') p) = 'B375P2',
   'B6 only payouts paid between the dates (both included) count');
 perform pg_temp.check(jsonb_array_length(m->'wednesdays_without_payout') = 0,
   'B5 Wed 16 Sep is not listed when its payout was paid on Thu 17 Sep, after the end date, got ' || (m->'wednesdays_without_payout')::text);
 -- Before the first day any confirmed settlement file reaches, no file is expected.
 insert into tx values ('first', (select min((s.settled_time at time zone 'Asia/Singapore')::date)::text
   from public.tiktok_settlement_rows s join public.tiktok_import_batches b on b.id = s.batch_id
  where b.status = 'confirmed' and b.deleted_at is null and b.file_kind = 'settlement' and s.settled_time is not null));
 m := pg_temp.payouts(pg_temp.tx('first')::date - 28, pg_temp.tx('first')::date - 1);
 perform pg_temp.check(jsonb_array_length(m->'wednesdays_without_payout') = 0,
   'B5 Wednesdays before the first imported file are not listed, got ' || (m->'wednesdays_without_payout')::text);
 m := pg_temp.payouts(public.sg_today(), public.sg_today() + 7);
 perform pg_temp.check(jsonb_array_length(m->'wednesdays_without_payout') = 0,
   'B5 a Wednesday not yet over (today''s included) is not listed, got ' || (m->'wednesdays_without_payout')::text);
 perform pg_temp.check(pg_temp.err('select public.tiktok_bank_payouts(''2026-09-30'', ''2026-09-01'')') ~ 'end date cannot be before'
     and pg_temp.err('select public.tiktok_bank_payouts(''2025-01-01'', ''2026-09-01'')') ~ 'at most about a year'
     and pg_temp.err('select public.tiktok_bank_payouts(null, ''2026-09-01'')') ~ 'start and an end date',
   'B6 the dates must make sense');
exception when others then perform pg_temp.check(false, 'B6 raised: ' || sqlerrm);
end $$;

-- ═════ B8 A file already imported; a later file never replaces a payout ═════
do $$
declare b uuid; m jsonb; res jsonb;
begin
 -- The 2 Sep file again, as TikTok exports it later: its line was imported
 -- before; its records now say P1 was 1,200 and P4 was transferred.
 b := pg_temp.stage('D', jsonb_build_array(pg_temp.ln('A', '80.00', '100.00', '-20.00', '2026/08/27')),
   jsonb_build_array(
   pg_temp.wr('Earnings', 'E1', '80', '2026/08/27'),
   pg_temp.wr('Payments', 'P1', '-1200', '2026/09/02'),
   pg_temp.wr('Payments', 'P4', '-15', '2026/09/23')));
 perform pg_temp.check((select bool_and(excluded) from public.tiktok_settlement_rows where batch_id = b),
   'B8 (setup) the re-uploaded file''s line is already imported, so nothing in it can be ticked');
 perform pg_temp.check(public.tiktok_batch_balance_counts(b) = '{"payouts": 2, "others": 1}'::jsonb,
   'B8 the page is told what the file brought: 2 payouts and 1 other record, got ' || public.tiktok_batch_balance_counts(b)::text);
 res := public.confirm_tiktok_settlement_batch(b, '[]'::jsonb);
 perform pg_temp.check((select status from public.tiktok_import_batches where id = b) = 'confirmed' and (res->>'applied')::int = 0,
   'B8 it is confirmed with no line ticked, for its records alone');
 update public.tiktok_import_batches set confirmed_at = confirmed_at + interval '1 day' where id = b;
 m := pg_temp.payouts('2026-09-01', '2026-09-30');
 perform pg_temp.check((pg_temp.payout(m, 'P4')->>'transferred')::boolean and (pg_temp.payout(m, 'P4')->>'amount')::numeric = 15.00
     and pg_temp.payout(m, 'P4')->>'file_name' = 'B375 D.xlsx',
   'B8 its records count: the payout it shows transferred now is, from that file');
 perform pg_temp.check((pg_temp.payout(m, 'P1')->>'amount')::numeric = 120.00
     and pg_temp.payout(m, 'P1')->>'file_name' = 'B375 A.xlsx'
     and pg_temp.payout(m, 'P1')->'disagreeing' = '[{"amount": 1200.00, "file_name": "B375 D.xlsx"}]'::jsonb,
   'B8 a later file does not replace a payout: the first file''s 120.00 is kept, and the file saying 1,200.00 is named, got ' || (pg_temp.payout(m, 'P1'))::text);
 perform pg_temp.check(pg_temp.payout(m, 'P2')->'disagreeing' = '[]'::jsonb,
   'B8 a payout the files agree on names none (P2 is in one file)');
 b := pg_temp.stage('E', jsonb_build_array(pg_temp.ln('A', '80.00', '100.00', '-20.00', '2026/08/27')),
   jsonb_build_array(pg_temp.wr('Payments', 'P4', '-15', '2026/09/23', 'Processing')));
 perform public.confirm_tiktok_settlement_batch(b, '[]'::jsonb);
 update public.tiktok_import_batches set confirmed_at = confirmed_at + interval '2 days' where id = b;
 m := pg_temp.payouts('2026-09-01', '2026-09-30');
 perform pg_temp.check((pg_temp.payout(m, 'P4')->>'transferred')::boolean and pg_temp.payout(m, 'P4')->>'file_name' = 'B375 D.xlsx',
   'B8 an older export confirmed later, still showing the payout as Processing, does not undo its transfer');
 perform pg_temp.check((m->>'undated_payout_count')::int = 0, 'B8 (setup) no payout without a date yet');
 b := pg_temp.stage('G', jsonb_build_array(pg_temp.ln('A', '80.00', '100.00', '-20.00', '2026/08/27')),
   jsonb_build_array(pg_temp.wr('Payments', 'P9', '-9', '')));
 perform public.confirm_tiktok_settlement_batch(b, '[]'::jsonb);
 m := pg_temp.payouts('2026-09-01', '2026-09-30');
 perform pg_temp.check((m->>'undated_payout_count')::int = 1 and pg_temp.payout(m, 'P9') is null,
   'B8 a payout with no date is counted for a warning, not lost, got ' || coalesce(m->>'undated_payout_count', 'nothing'));
exception when others then perform pg_temp.check(false, 'B8 raised: ' || sqlerrm);
end $$;

-- ═════ B7 Who may ═════
select pg_temp.as_user('s');
do $$
declare b uuid;
begin
 b := pg_temp.stage('staff', jsonb_build_array(pg_temp.ln('F', '5.00', '6.00', '-1.00', '2026/09/24')),
   jsonb_build_array(pg_temp.wr('Earnings', 'E9', '5', '2026/09/24')));
 perform pg_temp.check((select count(*) from public.tiktok_balance_records where batch_id = b) = 1,
   'B7 staff of the store may stage a settlement file with its records, as before');
 perform pg_temp.check(public.tiktok_batch_balance_counts(b) = '{"payouts": 0, "others": 1}'::jsonb,
   'B7 and see what it brought');
exception when others then perform pg_temp.check(false, 'B7 staff staging raised: ' || sqlerrm);
end $$;
select pg_temp.check(pg_temp.err('select public.tiktok_bank_payouts(''2026-09-01'', ''2026-09-30'')') ~ 'Only an Owner or Manager can see the TikTok payouts',
  'B7 staff cannot read the payouts');
select pg_temp.as_user('s2');
select pg_temp.check(pg_temp.err(format('select public.tiktok_batch_balance_counts(%L)', pg_temp.fx('bA'))) ~ 'only import TikTok sales for your assigned store',
  'B7 staff of another store cannot see what a file brought');
select pg_temp.as_user('a');
select pg_temp.check(pg_temp.err('select public.tiktok_bank_payouts(''2026-09-01'', ''2026-09-30'')') ~ 'Only an Owner or Manager can see the TikTok payouts',
  'B7 an Admin cannot (as for the invoice Xero export)');
select pg_temp.as_user('od');
select pg_temp.check(pg_temp.err('select public.tiktok_bank_payouts(''2026-09-01'', ''2026-09-30'')') ~ 'Only an Owner or Manager can see the TikTok payouts',
  'B7 a deactivated Owner cannot');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.err('select public.tiktok_bank_payouts(''2026-09-01'', ''2026-09-30'')') is null, 'B7 a Manager can');
select pg_temp.check(not has_function_privilege('anon', 'public.tiktok_bank_payouts(date,date)', 'execute')
    and not has_function_privilege('anon', 'public.stage_tiktok_settlement_file(uuid,text,text,jsonb,jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.tiktok_bank_payouts(date,date)', 'execute')
    and has_function_privilege('authenticated', 'public.stage_tiktok_settlement_file(uuid,text,text,jsonb,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.tiktok_batch_balance_counts(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.tiktok_batch_balance_counts(uuid)', 'execute')
    and not has_table_privilege('authenticated', 'public.tiktok_balance_records', 'select')
    and not has_table_privilege('anon', 'public.tiktok_balance_records', 'select'),
  'B7 signed-in users call the three functions (which check who they are); nobody reads the table directly');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All TikTok bank payout checks passed.';
end $$;
rollback;
