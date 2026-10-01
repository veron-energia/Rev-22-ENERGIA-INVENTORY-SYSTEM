-- TikTok's Wednesday payouts for Xero (374).
--
--   X1 A reporting month gives each of its Wednesdays, each paying out the
--      week from the Thursday before through that Wednesday; a line settled on
--      a Wednesday is in that Wednesday's payout, a line settled on the
--      Thursday after is in the next one.
--   X2 Each week's sales, fees, ads and payout are Total Revenue, Total Fee,
--      Total Expense and Total Income over its lines (ads and fee rows,
--      refunds), and the month's payouts add up to its Total Income.
--   X3 Every store together.
--   X4 Only counted lines: a staged file, and a line left unticked at
--      confirmation, count in no payout; the left-out line (and a left-out
--      restatement, by its difference) is reported on its week. An unknown
--      TikTok type, a line moving money in or out of the balance and a line
--      not in SGD (but not one with no currency) are reported too. A counted
--      line with no settled date is in no week but reported. Days of a week
--      that no confirmed file reaches are listed. The month's Total Income is
--      given as tiktok_settlement_totals works it out.
--   X5 A week whose Wednesday is not over is marked so.
--   X6 Only active Owners and Managers; a month is required.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Fixtures carry a random suffix. The month under
-- test (September 2026) must hold no other TikTok lines; the run says so if it
-- does.
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
-- One row of TikTok's income export.
create function pg_temp.ln(ord text, typ text, settle text, rev text, fee text, adj text, settled text, cur text default 'SGD')
returns jsonb language sql as
$$ select jsonb_build_object('order_id', 'X374-' || ord || '-' || pg_temp.tx('sfx'), 'transaction_type', typ,
     'related_order_id', 'X374-' || ord || '-' || pg_temp.tx('sfx'),
     'settlement_amount', settle, 'revenue_amount', rev, 'fee_amount', fee, 'adjustment_amount', adj,
     'currency', cur, 'order_created_time', '2026/08/20', 'settled_time', settled) $$;
create function pg_temp.stage(store text, file text, rows jsonb) returns uuid language sql as
$$ select public.stage_tiktok_settlement(pg_temp.fx(store), 'X374 ' || file || '.xlsx', 'Settlement', rows) $$;
create function pg_temp.pick(b uuid, nos int[]) returns jsonb language sql as
$$ select coalesce(jsonb_agg(id::text order by row_no), '[]'::jsonb) from public.tiktok_settlement_rows
    where batch_id = b and row_no = any(nos) $$;
create function pg_temp.week(m jsonb, d text) returns jsonb language sql as
$$ select w from jsonb_array_elements(m->'weeks') w where w->>'payout_date' = d $$;
-- payout_date: revenue / fee / expense / payout / tiktok_net / rows
create function pg_temp.fig(m jsonb, d text) returns text language sql as
$$ select concat_ws(' / ', w->>'revenue', w->>'fee', w->>'expense', w->>'payout', w->>'tiktok_net', w->>'row_count')
     from jsonb_array_elements(m->'weeks') w where w->>'payout_date' = d $$;

-- ═════ Fixtures ═════
do $$
declare o uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); a uuid:=gen_random_uuid();
 od uuid:=gen_random_uuid();
 sfx text:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6)); st uuid; st2 uuid;
begin
 insert into auth.users(id,email) values
   (o,'x374-o-'||lower(sfx)||'@tests.invalid'),(m,'x374-m-'||lower(sfx)||'@tests.invalid'),
   (s,'x374-s-'||lower(sfx)||'@tests.invalid'),(a,'x374-a-'||lower(sfx)||'@tests.invalid'),
   (od,'x374-od-'||lower(sfx)||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (o,'X374 Owner','x374-o-'||lower(sfx)||'@tests.invalid','owner'),
   (m,'X374 Manager','x374-m-'||lower(sfx)||'@tests.invalid','manager'),
   (s,'X374 Staff','x374-s-'||lower(sfx)||'@tests.invalid','staff'),
   (a,'X374 Admin','x374-a-'||lower(sfx)||'@tests.invalid','admin'),
   (od,'X374 Former Owner','x374-od-'||lower(sfx)||'@tests.invalid','owner');
 update profiles set is_active = false where id = od;
 insert into stores(name,code,country_code) values('X374 Store '||sfx,'X374'||sfx,'SG') returning id into st;
 insert into stores(name,code,country_code) values('X374 Other '||sfx,'X374O'||sfx,'SG') returning id into st2;
 insert into user_store_assignments(user_id,store_id) values(s,st);
 insert into fx values('o',o),('m',m),('s',s),('a',a),('od',od),('st',st),('st2',st2);
 insert into tx values('sfx',sfx);
end $$;
select pg_temp.as_user('o');
select pg_temp.check(not exists (select 1 from public.tiktok_settlement_rows
                                  where settled_time >= '2026-08-27'::date::timestamp at time zone 'Asia/Singapore'
                                    and settled_time <  '2026-10-01'::date::timestamp at time zone 'Asia/Singapore'),
  'X0 September 2026 holds no other TikTok lines (the checks below assume so)');

-- September 2026 (Thu 27 Aug – Wed 30 Sep): Wednesdays 2, 9, 16, 23 and 30 Sep.
do $$
declare b uuid;
begin
 -- Week of Wed 2 Sep: Thursday 27 Aug and the Wednesday itself.
 -- Week of Wed 9 Sep: Thursday 3 Sep, and an ad taken on the Wednesday.
 -- Week of Wed 16 Sep: a fee row, a refund, and an order of the other store.
 -- Week of Wed 23 Sep: a TikTok type the app does not know, and a reserve.
 b := pg_temp.stage('st', 'main', jsonb_build_array(
   pg_temp.ln('A', 'Order', '80.00', '100.00', '-20.00', '0', '2026/08/27'),
   pg_temp.ln('B', 'Order', '40.00', '50.00', '-10.00', '0', '2026/09/02'),
   pg_temp.ln('C', 'Order', '24.00', '30.00', '-6.00', '0', '2026/09/03'),
   pg_temp.ln('AD1', 'GMV payment for TikTok Ads', '-50.00', '0', '0', '-50.00', '2026/09/09'),
   pg_temp.ln('FEE1', 'Affiliate Shop Ads commission', '-3.00', '0', '0', '-3.00', '2026/09/14'),
   pg_temp.ln('R1', 'Refund', '-8.00', '-10.00', '2.00', '0', '2026/09/16'),
   pg_temp.ln('RS1', 'Reserve', '-30.00', '0', '0', '-30.00', '2026/09/20'),
   pg_temp.ln('U1', 'GMV payment for Promote', '-5.00', '0', '0', '-5.00', '2026/09/22')));
 perform public.confirm_tiktok_settlement_batch(b, null);
 b := pg_temp.stage('st2', 'other store', jsonb_build_array(
   pg_temp.ln('D', 'Order', '160.00', '200.00', '-40.00', '0', '2026/09/15')));
 perform public.confirm_tiktok_settlement_batch(b, null);
 -- Week of Wed 30 Sep: F counted, E left unticked at confirmation.
 b := pg_temp.stage('st', 'left out', jsonb_build_array(
   pg_temp.ln('F', 'Order', '8.00', '10.00', '-2.00', '0', '2026/09/29'),
   pg_temp.ln('E', 'Order', '12.00', '15.00', '-3.00', '0', '2026/09/29')));
 perform public.confirm_tiktok_settlement_batch(b, pg_temp.pick(b, array[1]));
 -- A file staged and never confirmed, on Wed 23 Sep, a day no confirmed file reaches.
 b := pg_temp.stage('st', 'never confirmed', jsonb_build_array(
   pg_temp.ln('G', 'Order', '99.00', '110.00', '-11.00', '0', '2026/09/23')));
 insert into fx values ('staged', b);
exception when others then perform pg_temp.check(false, 'fixtures raised: ' || sqlerrm);
end $$;

-- ═════ X1 The Wednesdays and their weeks ═════
do $$ declare m jsonb := public.tiktok_xero_payouts(2026, 9); begin
  insert into tx values ('sep', m::text);
end $$;
select pg_temp.check((select string_agg(w->>'payout_date' || ':' || (w->>'week_start') || '..' || (w->>'week_end'), ' ' order by w->>'payout_date')
                        from jsonb_array_elements(pg_temp.tx('sep')::jsonb->'weeks') w)
                     = '2026-09-02:2026-08-27..2026-09-02 2026-09-09:2026-09-03..2026-09-09 2026-09-16:2026-09-10..2026-09-16 '
                       || '2026-09-23:2026-09-17..2026-09-23 2026-09-30:2026-09-24..2026-09-30',
  'X1 September''s Wednesdays are 2, 9, 16, 23 and 30 Sep, each paying out Thursday to Wednesday');
select pg_temp.check((pg_temp.tx('sep')::jsonb->>'period_start', pg_temp.tx('sep')::jsonb->>'period_end') = ('2026-08-27', '2026-09-30'),
  'X1 the month is the reporting month (27 Aug – 30 Sep)');
select pg_temp.check(pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-02') = '150.00 / 30.00 / 0.00 / 120.00 / 120.00 / 2',
  'X1 Wed 2 Sep pays out Thu 27 Aug and the Wednesday itself: 150.00 - 30.00 = 120.00, got ' || pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-02'));

-- ═════ X2 The figures ═════
select pg_temp.check(pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-09') = '30.00 / 6.00 / 50.00 / -26.00 / -26.00 / 2',
  'X2 Wed 9 Sep: the Thursday after (3 Sep) and the ad taken on the Wednesday, a negative week: -26.00, got '
    || pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-09'));
select pg_temp.check(pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-16') = '190.00 / 41.00 / 0.00 / 149.00 / 149.00 / 3',
  'X2 Wed 16 Sep: a fee row (3.00), a refund (-10.00 with 2.00 of fees back) and an order: 149.00, got '
    || pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-16'));
select pg_temp.check((select (t->>'income')::numeric from public.tiktok_settlement_totals(2026, 9, null) t)
                       = (pg_temp.tx('sep')::jsonb->>'income')::numeric
    and (pg_temp.tx('sep')::jsonb->>'income')::numeric = 251.00
    and (select sum((w->>'payout')::numeric) from jsonb_array_elements(pg_temp.tx('sep')::jsonb->'weeks') w) = 251.00,
  'X2 the month''s payouts add up to its Total Income, 251.00, got ' || (pg_temp.tx('sep')::jsonb->>'income'));
select pg_temp.check((select (t->>'revenue')::numeric = 380.00 and (t->>'fee')::numeric = 79.00 and (t->>'expense')::numeric = 50.00
                        from public.tiktok_settlement_totals(2026, 9, null) t)
    and (select sum((w->>'revenue')::numeric) || '/' || sum((w->>'fee')::numeric) || '/' || sum((w->>'expense')::numeric)
           from jsonb_array_elements(pg_temp.tx('sep')::jsonb->'weeks') w) = '380.00/79.00/50.00',
  'X2 its sales, fees and ads add up to the month''s Total Revenue, Fee and Expense');

-- ═════ X3 Every store together ═════
select pg_temp.check((select (t->>'revenue')::numeric from public.tiktok_settlement_totals(2026, 9, pg_temp.fx('st2')) t) = 200.00
    and (pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-16')->>'revenue')::numeric = 190.00,
  'X3 the other store''s order (200.00) is in Wed 16 Sep''s payout with the first store''s lines');

-- ═════ X4 Only counted lines; what to read first ═════
select pg_temp.check(pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-23') = '0.00 / 0.00 / 0.00 / 0.00 / -35.00 / 2'
    and (pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-23')->>'unknown_count')::int = 1
    and (pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-23')->>'balance_movement_count')::int = 1,
  'X4 Wed 23 Sep: the staged file counts nowhere; the unknown type and the reserve add nothing but are reported (TikTok''s own total -35.00), got '
    || pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-23'));
select pg_temp.check(pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-02')->'uncovered_days' = '[]'::jsonb
    and pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-23')->'uncovered_days' = '["2026-09-23"]'::jsonb
    and pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-30')->'uncovered_days'
        = '["2026-09-24", "2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28", "2026-09-30"]'::jsonb,
  'X4 the days no confirmed file reaches are listed (a file reaches from its first to its last settled day; the staged one reaches nothing), got '
    || (pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-23')->>'uncovered_days') || ' / ' || (pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-30')->>'uncovered_days'));
select pg_temp.check((pg_temp.tx('sep')::jsonb->>'month_income')::numeric = 251.00,
  'X4 the month''s Total Income for every store, as tiktok_settlement_totals works it out, is given: 251.00, got ' || (pg_temp.tx('sep')::jsonb->>'month_income'));
select pg_temp.check(pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-30') = '10.00 / 2.00 / 0.00 / 8.00 / 8.00 / 1'
    and (pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-30')->>'left_out_count')::int = 1
    and (pg_temp.week(pg_temp.tx('sep')::jsonb, '2026-09-30')->>'left_out_settlement')::numeric = 12.00,
  'X4 Wed 30 Sep counts F (8.00) and reports E, left out at confirmation (12.00), got '
    || pg_temp.fig(pg_temp.tx('sep')::jsonb, '2026-09-30'));
select pg_temp.check((select sum((w->>'left_out_count')::int) from jsonb_array_elements(pg_temp.tx('sep')::jsonb->'weeks') w)
                       = (select (t->>'left_out_count')::int from public.tiktok_settlement_totals(2026, 9, null) t),
  'X4 the weeks report the same left-out lines as the month''s totals');
do $$
declare b uuid; m jsonb;
begin
 b := pg_temp.stage('st', 'odd', jsonb_build_array(
   pg_temp.ln('Y', 'Order', '9.00', '10.00', '-1.00', '0', '2026/09/24', 'MYR'),
   pg_temp.ln('W', 'Order', '9.00', '10.00', '-1.00', '0', '2026/09/24', ''),
   pg_temp.ln('Z', 'Order', '9.00', '10.00', '-1.00', '0', '')));
 perform public.confirm_tiktok_settlement_batch(b, null);
 m := public.tiktok_xero_payouts(2026, 9);
 perform pg_temp.check((pg_temp.week(m, '2026-09-30')->>'other_currency_count')::int = 1
     and (m->>'undated_count')::int = (select count(*) from public.tiktok_settlement_eligible(null) where settled_time is null)
     and (m->>'undated_count')::int >= 1,
   format('X4 a line not in SGD (not one with no currency) is reported on its week, and counted lines with no settled date are reported, got %s / %s',
     pg_temp.week(m, '2026-09-30')->>'other_currency_count', m->>'undated_count'));
exception when others then perform pg_temp.check(false, 'X4 raised: ' || sqlerrm);
end $$;

-- A line TikTok restated, left unticked: reported by its difference (368).
do $$
declare b uuid; m jsonb;
begin
 b := pg_temp.stage('st', 'restated one', jsonb_build_array(
   pg_temp.ln('K', 'Order', '20.00', '25.00', '-5.00', '0', '2026/11/05')));
 perform public.confirm_tiktok_settlement_batch(b, null);
 b := pg_temp.stage('st', 'restated two', jsonb_build_array(
   pg_temp.ln('K', 'Order', '25.00', '30.00', '-5.00', '0', '2026/11/05')));
 perform public.confirm_tiktok_settlement_batch(b, '[]'::jsonb);
 m := public.tiktok_xero_payouts(2026, 11);
 perform pg_temp.check((pg_temp.week(m, '2026-11-11')->>'left_out_count')::int = 1
     and (pg_temp.week(m, '2026-11-11')->>'left_out_settlement')::numeric = 5.00
     and (pg_temp.week(m, '2026-11-11')->>'left_out_settlement')::numeric
         = (public.tiktok_settlement_totals(2026, 11, null)->>'left_out_settlement')::numeric
     and (pg_temp.week(m, '2026-11-11')->>'payout')::numeric = 20.00,
   format('X4 a restatement left unticked is reported by its difference (5.00) as the month''s totals do, and the line it restates still counts, got %s / %s / %s',
     pg_temp.week(m, '2026-11-11')->>'left_out_count', pg_temp.week(m, '2026-11-11')->>'left_out_settlement', pg_temp.week(m, '2026-11-11')->>'payout'));
exception when others then perform pg_temp.check(false, 'X4 restatement raised: ' || sqlerrm);
end $$;

-- ═════ X5 A week whose Wednesday is not over ═════
do $$
declare b uuid; m jsonb; d date := public.sg_today(); pay date; y int; mo int;
begin
 pay := d + ((3 - extract(isodow from d)::int + 7) % 7);
 select r.year, r.month into y, mo from public.tiktok_reporting_month(d::timestamp at time zone 'Asia/Singapore') r;
 b := pg_temp.stage('st', 'today', jsonb_build_array(
   pg_temp.ln('T', 'Order', '8.00', '10.00', '-2.00', '0', to_char(d, 'YYYY/MM/DD'))));
 perform public.confirm_tiktok_settlement_batch(b, null);
 m := public.tiktok_xero_payouts(y, mo);
 perform pg_temp.check((pg_temp.week(m, pay::text)->>'finished')::boolean = false
     and (pg_temp.week(m, pay::text)->>'row_count')::int >= 1
     and (select bool_and((w->>'finished')::boolean = ((w->>'payout_date')::date < d)) from jsonb_array_elements(m->'weeks') w),
   format('X5 a line settled today is in the payout of %s, which is not over; only Wednesdays before today are', pay));
 perform pg_temp.check((select bool_and((w->>'finished')::boolean) from jsonb_array_elements(pg_temp.tx('sep')::jsonb->'weeks') w),
   'X5 every Wednesday of September 2026 is over');
exception when others then perform pg_temp.check(false, 'X5 raised: ' || sqlerrm);
end $$;

-- ═════ X6 Who may ═════
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.err('select public.tiktok_xero_payouts(2026, 9)') is null,
  'X6 a Manager may');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err('select public.tiktok_xero_payouts(2026, 9)') ~ 'Only an Owner or Manager',
  'X6 staff may not');
select pg_temp.as_user('a');
select pg_temp.check(pg_temp.err('select public.tiktok_xero_payouts(2026, 9)') ~ 'Only an Owner or Manager',
  'X6 an Admin may not (as for the invoice Xero export)');
select pg_temp.as_user('od');
select pg_temp.check(pg_temp.err('select public.tiktok_xero_payouts(2026, 9)') ~ 'Only an Owner or Manager',
  'X6 an Owner who has been deactivated may not');
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.check(pg_temp.err('select public.tiktok_xero_payouts(2026, 9)') ~ 'Only an Owner or Manager',
  'X6 no one signed in may not');
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.err('select public.tiktok_xero_payouts(2026, 13)') ~ 'Choose a reporting month'
    and pg_temp.err('select public.tiktok_xero_payouts(null, 9)') ~ 'Choose a reporting month',
  'X6 a month is required');
select pg_temp.check(not has_function_privilege('anon', 'public.tiktok_xero_payouts(integer,integer)', 'execute')
    and has_function_privilege('authenticated', 'public.tiktok_xero_payouts(integer,integer)', 'execute'),
  'X6 signed-in users can call it (it checks the role); the anon key cannot');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All TikTok payout checks passed.';
end $$;
rollback;
