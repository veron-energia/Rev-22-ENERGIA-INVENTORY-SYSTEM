-- A TikTok settlement row is a line, not a version (368).
--
--   L1 A file's rows are lines: two identical rows of one order are two items
--      (no "Duplicate Row"), and an order's two lines both count.
--   L2 Re-importing the same file finds every row already imported and leaves
--      the totals as they were.
--   L3 An overlapping file adds its new line and takes no other line away.
--   L4 A single line restated at the same settled time is still an update of
--      it; an instalment settled at another time is a line of its own.
--   L5 A file staged before another file changed its orders is out of date:
--      confirming it is refused whole (another file counted a line of its
--      order since, or replaced the line it updates, by confirmation or by
--      inclusion), and staged again it counts each line once. A line counted
--      again without being confirmed since (a repair) is claimed at
--      confirmation. Confirming and staging lock every settlement file of the
--      store.
--   L6 Rows left unticked at confirmation are listed as left out, counted in
--      the month's totals as left out (an update by its net change), and can
--      be included once, by an Owner or Manager, with a reason; nothing else
--      can be included, and a line TikTok restated in a later file is no
--      longer left out. A left-out row whose file another file has overtaken
--      stays listed but cannot be included (its file is uploaded again).
--   L7 Who may call the new functions.
--
-- Every check runs, then the file fails if any did, so a run on the pre-368
-- functions lists what 368 changes. Disposable database only; everything is
-- rolled back. Fixtures carry a random suffix so the file can run beside other
-- suites on a shared database.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
-- Production's user_has_store_access (29 Sep 2026): Owners and Admins see every
-- store, anyone else only their assigned stores. Local databases may carry an
-- older one; this keeps the run faithful and is rolled back with the rest.
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
-- One row of TikTok's income export: an order line settled on a Singapore date.
create function pg_temp.ln(ord text, settle text, rev text, fee text, settled text) returns jsonb language sql as
$$ select jsonb_build_object('order_id', 'S368-' || ord || '-' || pg_temp.tx('sfx'), 'transaction_type', 'Order',
     'related_order_id', 'S368-' || ord || '-' || pg_temp.tx('sfx'),
     'settlement_amount', settle, 'revenue_amount', rev, 'fee_amount', fee, 'adjustment_amount', '0',
     'currency', 'SGD', 'order_created_time', '2026/07/28', 'settled_time', settled) $$;
create function pg_temp.stage(file text, rows jsonb) returns uuid language sql as
$$ select public.stage_tiktok_settlement(pg_temp.fx('st'), 'S368 ' || file || '.xlsx', 'Settlement', rows) $$;
create function pg_temp.rid(b uuid, no int) returns uuid language sql as
$$ select id from public.tiktok_settlement_rows where batch_id = b and row_no = no $$;
create function pg_temp.status(b uuid, no int) returns text language sql as
$$ select staging_status from public.tiktok_settlement_rows where batch_id = b and row_no = no $$;
create function pg_temp.pick(b uuid, nos int[]) returns jsonb language sql as
$$ select coalesce(jsonb_agg(id::text order by row_no), '[]'::jsonb) from public.tiktok_settlement_rows
    where batch_id = b and row_no = any(nos) $$;
-- The counted lines of an order: how many, and their settlement.
create function pg_temp.lines(ord text) returns text language sql as
$$ select count(*) || ' / ' || coalesce(sum(settlement_amount), 0) from public.tiktok_settlement_rows
    where store_id = pg_temp.fx('st') and order_id = 'S368-' || ord || '-' || pg_temp.tx('sfx')
      and confirmed and is_current and not excluded $$;
create function pg_temp.totals(y int, m int) returns jsonb language sql as
$$ select public.tiktok_settlement_totals(y, m, pg_temp.fx('st')) $$;

-- ═════ Fixtures ═════
do $$
declare o uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); x uuid:=gen_random_uuid();
 sfx text:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6)); st uuid;
begin
 insert into auth.users(id,email) values
   (o,'s368-o-'||lower(sfx)||'@tests.invalid'),(m,'s368-m-'||lower(sfx)||'@tests.invalid'),
   (s,'s368-s-'||lower(sfx)||'@tests.invalid'),(x,'s368-x-'||lower(sfx)||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (o,'S368 Owner','s368-o-'||lower(sfx)||'@tests.invalid','owner'),
   (m,'S368 Manager','s368-m-'||lower(sfx)||'@tests.invalid','manager'),
   (s,'S368 Staff','s368-s-'||lower(sfx)||'@tests.invalid','staff'),
   (x,'S368 Other Staff','s368-x-'||lower(sfx)||'@tests.invalid','staff');
 insert into stores(name,code,country_code) values('S368 Store '||sfx,'S368'||sfx,'SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(s,st);
 insert into fx values('o',o),('m',m),('s',s),('x',x),('st',st);
 insert into tx values('sfx',sfx);
end $$;
select pg_temp.as_user('o');

-- ═════ L1: a file's rows are lines ═════
-- Order A has two lines; order B three, two of them identical items.
do $$
declare b uuid; t jsonb;
begin
 b := pg_temp.stage('first', jsonb_build_array(
   pg_temp.ln('A','236.02','282.53','-46.51','2026/09/15'),
   pg_temp.ln('A','135.12','160.70','-25.58','2026/09/15'),
   pg_temp.ln('B','137.45','164.05','-26.60','2026/09/18'),
   pg_temp.ln('B','64.17','77.03','-12.86','2026/09/18'),
   pg_temp.ln('B','64.17','77.03','-12.86','2026/09/18')));
 insert into fx values('b1', b);
 perform pg_temp.check(pg_temp.status(b,5) = 'New — Pending Order',
   format('L1 a second identical item of an order is a line of its own, not a "Duplicate Row", got %s', pg_temp.status(b,5)));
 perform pg_temp.check((select count(*) from tiktok_settlement_rows where batch_id=b and staging_status='New — Pending Order') = 5,
   'L1 all five rows of the file are new lines');
 perform confirm_tiktok_settlement_batch(b, null);
 perform pg_temp.check(pg_temp.lines('A') = '2 / 371.14' and pg_temp.lines('B') = '3 / 265.79',
   format('L1 both of A''s lines (371.14) and all three of B''s (265.79) count, got %s and %s', pg_temp.lines('A'), pg_temp.lines('B')));
 t := pg_temp.totals(2026, 9);
 insert into tx values('net1', t->>'tiktok_net_settlement');
 perform pg_temp.check((t->>'tiktok_net_settlement')::numeric = 636.93 and (t->>'row_count')::int = 5,
   format('L1 September''s totals hold the five lines, 636.93, got %s over %s rows', t->>'tiktok_net_settlement', t->>'row_count'));
exception when others then perform pg_temp.check(false, 'L1 raised: ' || sqlerrm);
end $$;

-- ═════ L2: the same file again ═════
do $$
declare b uuid; r jsonb; t jsonb;
begin
 b := pg_temp.stage('first again', jsonb_build_array(
   pg_temp.ln('A','236.02','282.53','-46.51','2026/09/15'),
   pg_temp.ln('A','135.12','160.70','-25.58','2026/09/15'),
   pg_temp.ln('B','137.45','164.05','-26.60','2026/09/18'),
   pg_temp.ln('B','64.17','77.03','-12.86','2026/09/18'),
   pg_temp.ln('B','64.17','77.03','-12.86','2026/09/18')));
 perform pg_temp.check((select count(*) from tiktok_settlement_rows where batch_id=b and staging_status='Already Imported') = 5,
   format('L2 every row of a re-imported file is already imported, got %s',
     (select string_agg(staging_status, ', ' order by row_no) from tiktok_settlement_rows where batch_id=b)));
 perform pg_temp.check((select count(distinct previous_row_id) from tiktok_settlement_rows where batch_id=b) = 5,
   'L2 each row claims a different current line (the two identical items claim one each)');
 r := confirm_tiktok_settlement_batch(b, null);
 t := pg_temp.totals(2026, 9);
 perform pg_temp.check((r->>'applied')::int = 0 and (r->>'versioned_updates')::int = 0,
   format('L2 confirming it applies nothing, got %s applied, %s updates', r->>'applied', r->>'versioned_updates'));
 perform pg_temp.check(pg_temp.lines('A') = '2 / 371.14' and pg_temp.lines('B') = '3 / 265.79'
     and t->>'tiktok_net_settlement' = pg_temp.tx('net1'),
   format('L2 the totals are unchanged (%s), got %s; A %s, B %s', pg_temp.tx('net1'), t->>'tiktok_net_settlement',
     pg_temp.lines('A'), pg_temp.lines('B')));
exception when others then perform pg_temp.check(false, 'L2 raised: ' || sqlerrm);
end $$;

-- ═════ L3: an overlapping file adds a line ═════
-- The same lines, plus a third item of A settled the same day and a new order C.
do $$
declare b uuid; t jsonb;
begin
 b := pg_temp.stage('overlap', jsonb_build_array(
   pg_temp.ln('B','64.17','77.03','-12.86','2026/09/18'),
   pg_temp.ln('A','135.12','160.70','-25.58','2026/09/15'),
   pg_temp.ln('A','50.00','60.00','-10.00','2026/09/15'),
   pg_temp.ln('A','236.02','282.53','-46.51','2026/09/15'),
   pg_temp.ln('B','137.45','164.05','-26.60','2026/09/18'),
   pg_temp.ln('B','64.17','77.03','-12.86','2026/09/18'),
   pg_temp.ln('C','20.00','24.00','-4.00','2026/09/19')));
 perform pg_temp.check(pg_temp.status(b,3) = 'New — Pending Order' and pg_temp.status(b,7) = 'New — Pending Order',
   format('L3 A''s third item and order C are new lines, got %s and %s', pg_temp.status(b,3), pg_temp.status(b,7)));
 perform pg_temp.check((select count(*) from tiktok_settlement_rows where batch_id=b and staging_status='Already Imported') = 5,
   format('L3 the five lines already counted are already imported, whatever their order in the file, got %s',
     (select string_agg(staging_status, ', ' order by row_no) from tiktok_settlement_rows where batch_id=b)));
 perform confirm_tiktok_settlement_batch(b, null);
 t := pg_temp.totals(2026, 9);
 perform pg_temp.check(pg_temp.lines('A') = '3 / 421.14' and pg_temp.lines('B') = '3 / 265.79' and pg_temp.lines('C') = '1 / 20.00',
   format('L3 A gains its third line and loses none (421.14), B keeps 265.79, C 20.00; got %s, %s, %s',
     pg_temp.lines('A'), pg_temp.lines('B'), pg_temp.lines('C')));
 perform pg_temp.check((t->>'tiktok_net_settlement')::numeric = 706.93,
   format('L3 September = 636.93 + 50.00 + 20.00 = 706.93, got %s', t->>'tiktok_net_settlement'));
exception when others then perform pg_temp.check(false, 'L3 raised: ' || sqlerrm);
end $$;

-- ═════ L4: a restatement is an update; an instalment is a line ═════
do $$
declare b uuid; b2 uuid;
begin
 b := pg_temp.stage('restate before', jsonb_build_array(
   pg_temp.ln('D','100.00','120.00','-20.00','2026/09/21'),
   pg_temp.ln('E','40.00','48.00','-8.00','2026/09/06')));
 perform confirm_tiktok_settlement_batch(b, null);
 b2 := pg_temp.stage('restate after', jsonb_build_array(
   pg_temp.ln('D','95.00','120.00','-25.00','2026/09/21'),
   pg_temp.ln('E','30.00','36.00','-6.00','2026/09/13')));
 perform pg_temp.check(pg_temp.status(b2,1) = 'Updated — Requires Confirmation'
     and (select previous_row_id from tiktok_settlement_rows where id=pg_temp.rid(b2,1)) = pg_temp.rid(b,1)
     and (select value_diff ? 'settlement_amount' and value_diff ? 'fee_amount' and not value_diff ? 'revenue_amount'
            from tiktok_settlement_rows where id=pg_temp.rid(b2,1)),
   format('L4 a single line restated at the same settled time is an update of it, with the changed fields, got %s',
     pg_temp.status(b2,1)));
 perform pg_temp.check(pg_temp.status(b2,2) = 'New — Pending Order',
   format('L4 an instalment settled on another day is a new line, got %s', pg_temp.status(b2,2)));
 perform confirm_tiktok_settlement_batch(b2, null);
 perform pg_temp.check(pg_temp.lines('D') = '1 / 95.00' and pg_temp.lines('E') = '2 / 70.00',
   format('L4 D counts its restated 95.00 only; E both instalments, 70.00; got %s and %s', pg_temp.lines('D'), pg_temp.lines('E')));
exception when others then perform pg_temp.check(false, 'L4 raised: ' || sqlerrm);
end $$;

-- ═════ L5: a file staged before another file changed its orders ═════
-- G: two identical items and a third line; Q: one line, which the second file
-- restates. The second file holds one more of the identical items than the
-- first. Both files are staged before either is confirmed.
do $$
declare b uuid; b2 uuid; b3 uuid; probe uuid; r jsonb; ok boolean; err text; twin jsonb;
begin
 b := pg_temp.stage('twin one', jsonb_build_array(
   pg_temp.ln('G','20.00','24.00','-4.00','2026/09/22'),
   pg_temp.ln('G','20.00','24.00','-4.00','2026/09/22'),
   pg_temp.ln('G','33.00','40.00','-7.00','2026/09/22'),
   pg_temp.ln('Q','100.00','120.00','-20.00','2026/09/22')));
 twin := jsonb_build_array(
   pg_temp.ln('G','33.00','40.00','-7.00','2026/09/22'),
   pg_temp.ln('G','20.00','24.00','-4.00','2026/09/22'),
   pg_temp.ln('G','20.00','24.00','-4.00','2026/09/22'),
   pg_temp.ln('G','20.00','24.00','-4.00','2026/09/22'),
   pg_temp.ln('Q','95.00','120.00','-25.00','2026/09/22'));
 b2 := pg_temp.stage('twin two', twin);
 perform pg_temp.check((select count(*) from tiktok_settlement_rows where batch_id in (b,b2) and staging_status like 'New — %') = 9,
   'L5 both files stage every row as new (nothing is counted yet)');
 -- One transaction stamps everything alike; the second file was staged
 -- before the first was confirmed.
 update tiktok_import_batches set uploaded_at = uploaded_at - interval '1 hour' where id = b2;
 -- An empty staged file of the store, as a lock probe: nothing else touches
 -- it, so its xmax is 0 until something locks it.
 insert into tiktok_import_batches(store_id, file_kind, file_name, uploaded_by)
 values (pg_temp.fx('st'), 'settlement', 'S368 lock probe.xlsx', pg_temp.fx('o')) returning id into probe;
 perform confirm_tiktok_settlement_batch(b, null);
 perform pg_temp.check((select xmax::text from tiktok_import_batches where id = probe) <> '0',
   'L5 confirming a file locks every settlement file of its store, so another confirmation or an inclusion waits for it');
 begin
   r := confirm_tiktok_settlement_batch(b2, null);
   ok := false; err := 'confirmed: ' || r::text;
 exception when others then ok := sqlerrm like '%after this file was staged%upload it again%'; err := sqlerrm; end;
 perform pg_temp.check(ok and pg_temp.lines('G') = '3 / 73.00' and pg_temp.lines('Q') = '1 / 100.00'
     and (select status from tiktok_import_batches where id = b2) = 'staged',
   format('L5 the file staged before the first was confirmed is refused whole and counts nothing (G 3 / 73.00, Q 1 / 100.00), got G %s, Q %s: %s',
     pg_temp.lines('G'), pg_temp.lines('Q'), err));
 -- Deleted and staged again, it is compared with what counts now.
 perform delete_tiktok_batch(b2);
 b3 := pg_temp.stage('twin two again', twin);
 perform pg_temp.check((select count(*) from tiktok_settlement_rows where batch_id=b3 and staging_status='Already Imported') = 3
     and pg_temp.status(b3,4) = 'New — Pending Order' and pg_temp.status(b3,5) = 'Updated — Requires Confirmation'
     and (select previous_row_id from tiktok_settlement_rows where id=pg_temp.rid(b3,5)) = pg_temp.rid(b,4),
   format('L5 staged again, three lines are already imported, the extra item is new and Q''s restatement an update, got %s',
     (select string_agg(staging_status, ', ' order by row_no) from tiktok_settlement_rows where batch_id=b3)));
 r := confirm_tiktok_settlement_batch(b3, null);
 perform pg_temp.check(pg_temp.lines('G') = '4 / 93.00' and pg_temp.lines('Q') = '1 / 95.00'
     and (r->>'applied')::int = 2 and (r->>'versioned_updates')::int = 1,
   format('L5 and confirmed, each line counts once: G 3 x 20.00 + 33.00 = 4 / 93.00, Q its restated 95.00; got %s and %s (%s applied, %s updates)',
     pg_temp.lines('G'), pg_temp.lines('Q'), r->>'applied', r->>'versioned_updates'));
exception when others then perform pg_temp.check(false, 'L5 raised: ' || sqlerrm);
end $$;

-- A line counted again without being confirmed since (a repair making an
-- earlier line current) is claimed at confirmation, as staging would have.
do $$
declare b uuid; b2 uuid; r jsonb;
begin
 b := pg_temp.stage('counted again before', jsonb_build_array(pg_temp.ln('N','40.00','48.00','-8.00','2026/09/25')));
 perform confirm_tiktok_settlement_batch(b, null);
 -- taken out of the totals (as the pre-368 re-imports did) ...
 update tiktok_settlement_rows set is_current = false where id = pg_temp.rid(b,1);
 b2 := pg_temp.stage('counted again after', jsonb_build_array(pg_temp.ln('N','40.00','48.00','-8.00','2026/09/25')));
 update tiktok_import_batches set uploaded_at = uploaded_at + interval '1 hour' where id = b2;
 -- ... and put back by a repair while the second file waits.
 update tiktok_settlement_rows set is_current = true where id = pg_temp.rid(b,1);
 perform pg_temp.check(pg_temp.status(b2,1) = 'New — Pending Order',
   format('L5 a line that was not counted when the file was staged is new there, got %s', pg_temp.status(b2,1)));
 r := confirm_tiktok_settlement_batch(b2, null);
 perform pg_temp.check(pg_temp.lines('N') = '1 / 40.00' and (r->>'applied')::int = 0 and (r->>'already_imported')::int = 1
     and pg_temp.status(b2,1) = 'Already Imported'
     and (select previous_row_id from tiktok_settlement_rows where id=pg_temp.rid(b2,1)) = pg_temp.rid(b,1),
   format('L5 counted again since, it is skipped as already imported and names the line: N 1 / 40.00, got %s (%s applied, %s already imported)',
     pg_temp.lines('N'), r->>'applied', r->>'already_imported'));
exception when others then perform pg_temp.check(false, 'L5 counted again raised: ' || sqlerrm);
end $$;

-- Two files holding the same restatement of a line: the first replaces it;
-- the second updates a line that no longer counts. (Stamped alike, so only
-- the replaced line tells.)
do $$
declare b uuid; x uuid; y uuid; r jsonb; ok boolean; err text;
begin
 b := pg_temp.stage('restated twice before', jsonb_build_array(pg_temp.ln('P','100.00','120.00','-20.00','2026/09/26')));
 perform confirm_tiktok_settlement_batch(b, null);
 x := pg_temp.stage('restated twice one', jsonb_build_array(pg_temp.ln('P','95.00','120.00','-25.00','2026/09/26')));
 y := pg_temp.stage('restated twice two', jsonb_build_array(pg_temp.ln('P','95.00','120.00','-25.00','2026/09/26')));
 perform pg_temp.check(pg_temp.status(x,1) = 'Updated — Requires Confirmation' and pg_temp.status(y,1) = 'Updated — Requires Confirmation'
     and (select count(*) from tiktok_settlement_rows where batch_id in (x,y) and previous_row_id = pg_temp.rid(b,1)) = 2,
   'L5 both files stage the restatement as an update of the counted line');
 perform confirm_tiktok_settlement_batch(x, null);
 begin
   r := confirm_tiktok_settlement_batch(y, null);
   ok := false; err := 'confirmed: ' || r::text;
 exception when others then ok := sqlerrm like '%replaced the line%upload it again%'; err := sqlerrm; end;
 perform pg_temp.check(ok and pg_temp.lines('P') = '1 / 95.00',
   format('L5 the second file''s update of the replaced line is refused, and P counts one 95.00, got %s: %s', pg_temp.lines('P'), err));
exception when others then perform pg_temp.check(false, 'L5 restated twice raised: ' || sqlerrm);
end $$;

-- The same, when the first file's update was left unticked and then
-- included; and an inclusion after the other file replaced the line.
do $$
declare b uuid; x uuid; y uuid; r jsonb; ok boolean; err text;
begin
 b := pg_temp.stage('include then confirm before', jsonb_build_array(pg_temp.ln('W','100.00','120.00','-20.00','2026/09/27')));
 perform confirm_tiktok_settlement_batch(b, null);
 x := pg_temp.stage('include then confirm one', jsonb_build_array(pg_temp.ln('W','95.00','120.00','-25.00','2026/09/27')));
 y := pg_temp.stage('include then confirm two', jsonb_build_array(pg_temp.ln('W','95.00','120.00','-25.00','2026/09/27')));
 perform confirm_tiktok_settlement_batch(x, '[]'::jsonb);
 perform include_tiktok_settlement_rows(array[pg_temp.rid(x,1)], 'Owner decision');
 begin
   r := confirm_tiktok_settlement_batch(y, null);
   ok := false; err := 'confirmed: ' || r::text;
 exception when others then ok := sqlerrm like '%replaced the line%upload it again%'; err := sqlerrm; end;
 perform pg_temp.check(ok and pg_temp.lines('W') = '1 / 95.00',
   format('L5 a file updating a line an inclusion replaced is refused, and W counts one 95.00, got %s: %s', pg_temp.lines('W'), err));

 b := pg_temp.stage('confirm then include before', jsonb_build_array(pg_temp.ln('U','100.00','120.00','-20.00','2026/09/28')));
 perform confirm_tiktok_settlement_batch(b, null);
 x := pg_temp.stage('confirm then include one', jsonb_build_array(pg_temp.ln('U','95.00','120.00','-25.00','2026/09/28')));
 y := pg_temp.stage('confirm then include two', jsonb_build_array(pg_temp.ln('U','90.00','120.00','-30.00','2026/09/28')));
 perform confirm_tiktok_settlement_batch(x, '[]'::jsonb);
 perform confirm_tiktok_settlement_batch(y, null);
 begin
   r := include_tiktok_settlement_rows(array[pg_temp.rid(x,1)], 'Owner decision');
   ok := false; err := 'included: ' || r::text;
 exception when others then ok := sqlerrm like '%another file has replaced%'; err := sqlerrm; end;
 perform pg_temp.check(ok and pg_temp.lines('U') = '1 / 90.00',
   format('L5 an unticked update of a line another file replaced cannot be included, and U counts one 90.00, got %s: %s', pg_temp.lines('U'), err));
exception when others then perform pg_temp.check(false, 'L5 include then confirm raised: ' || sqlerrm);
end $$;

-- ═════ L6: left-out lines ═════
-- Order H settled on 2 and 3 Aug (TikTok's August), three lines, two of them
-- identical; order J in September. Both files are confirmed with J only.
do $$
declare b uuid; b2 uuid; t jsonb; n int; v numeric; ids uuid[];
begin
 b := pg_temp.stage('left out one', jsonb_build_array(
   pg_temp.ln('H','7.65','11.52','-3.87','2026/08/02'),
   pg_temp.ln('H','65.26','78.40','-13.14','2026/08/03'),
   pg_temp.ln('H','65.26','78.40','-13.14','2026/08/03'),
   pg_temp.ln('J','10.00','12.00','-2.00','2026/09/23')));
 perform confirm_tiktok_settlement_batch(b, pg_temp.pick(b, array[4]));
 b2 := pg_temp.stage('left out two', jsonb_build_array(
   pg_temp.ln('J','10.00','12.00','-2.00','2026/09/23'),
   pg_temp.ln('H','7.65','11.52','-3.87','2026/08/02'),
   pg_temp.ln('H','65.26','78.40','-13.14','2026/08/03'),
   pg_temp.ln('H','65.26','78.40','-13.14','2026/08/03')));
 perform confirm_tiktok_settlement_batch(b2, '[]'::jsonb);
 -- One transaction stamps both uploads alike; the second file came later.
 update tiktok_import_batches set uploaded_at = uploaded_at + interval '1 hour' where id = b2;
 insert into fx values('lo1', b), ('lo2', b2);

 select count(*), sum(settlement_amount), array_agg(row_id order by row_id) into n, v, ids
   from tiktok_left_out_settlement(pg_temp.fx('st'), '2026-07-30', '2026-08-26');
 perform pg_temp.check(n = 3 and v = 138.17,
   format('L6 August lists the three lines left out, 138.17, got %s / %s', n, v));
 perform pg_temp.check(ids = (select array_agg(id order by id) from tiktok_settlement_rows where batch_id=b2 and row_no in (2,3,4)),
   'L6 each is listed once, by its row in the latest file');
 perform pg_temp.check((select count(*) from tiktok_left_out_settlement(pg_temp.fx('st'), '2026-08-27', '2026-09-30')) = 0,
   'L6 September left nothing out (J was confirmed)');
 perform pg_temp.check((select settled_date from tiktok_left_out_settlement(pg_temp.fx('st'), '2026-08-02', '2026-08-02')) = '2026-08-02',
   'L6 the period is the Singapore settled date');
 t := pg_temp.totals(2026, 8);
 perform pg_temp.check((t->>'left_out_count')::int = 3 and (t->>'left_out_settlement')::numeric = 138.17
     and (t->>'tiktok_net_settlement')::numeric = 0 and (t->>'row_count')::int = 0,
   format('L6 August''s totals say 3 lines, 138.17, were left out, and count none of them, got %s / %s, net %s',
     t->>'left_out_count', t->>'left_out_settlement', t->>'tiktok_net_settlement'));
 t := pg_temp.totals(2026, 9);
 perform pg_temp.check((t->>'left_out_count')::int = 0 and (t->>'left_out_settlement')::numeric = 0,
   format('L6 September''s totals: nothing left out, got %s / %s', t->>'left_out_count', t->>'left_out_settlement'));

 -- The staff member assigned to the store sees the list; another does not.
 perform pg_temp.as_user('s');
 perform pg_temp.check((select count(*) from tiktok_left_out_settlement(pg_temp.fx('st'), null, null)) = 3,
   'L6 the store''s own staff see what it left out');
 perform pg_temp.as_user('x');
 begin
   perform count(*) from tiktok_left_out_settlement(pg_temp.fx('st'), null, null);
   perform pg_temp.check(false, 'L6 staff of another store are refused the list');
 exception when others then
   perform pg_temp.check(sqlerrm like '%assigned store%', 'L6 staff of another store are refused the list: ' || sqlerrm);
 end;
 perform pg_temp.as_user('o');
exception when others then perform pg_temp.check(false, 'L6 raised: ' || sqlerrm);
end $$;

do $$
declare b uuid:=pg_temp.fx('lo1'); b2 uuid:=pg_temp.fx('lo2'); r jsonb; t jsonb; ok boolean; err text;
begin
 -- Refused: a non-manager, no reason, a row that is not left out.
 perform pg_temp.as_user('s');
 begin
   perform include_tiktok_settlement_rows(array[pg_temp.rid(b2,2)], 'Owner decision');
   ok := false; err := 'included';
 exception when others then ok := sqlerrm like '%Owners and Managers%'; err := sqlerrm; end;
 perform pg_temp.check(ok, 'L6 staff cannot include left-out lines: ' || err);
 perform pg_temp.as_user('m');
 begin
   perform include_tiktok_settlement_rows(array[pg_temp.rid(b2,2)], '  ');
   ok := false; err := 'included';
 exception when others then ok := sqlerrm like '%reason%'; err := sqlerrm; end;
 perform pg_temp.check(ok, 'L6 a reason is required: ' || err);
 begin
   perform include_tiktok_settlement_rows(array[pg_temp.rid(b,4)], 'Owner decision');
   ok := false; err := 'included';
 exception when others then ok := sqlerrm like '%not a left-out%'; err := sqlerrm; end;
 perform pg_temp.check(ok, 'L6 a counted row cannot be included: ' || err);
 begin
   perform include_tiktok_settlement_rows(array[pg_temp.rid(b2,1)], 'Owner decision');
   ok := false; err := 'included';
 exception when others then ok := sqlerrm like '%not a left-out%'; err := sqlerrm; end;
 perform pg_temp.check(ok, 'L6 an already-imported row cannot be included: ' || err);

 -- The Manager includes 7.65 through the EARLIER file's row.
 r := include_tiktok_settlement_rows(array[pg_temp.rid(b,1)], 'Owner decision 29 Sep 2026');
 t := pg_temp.totals(2026, 8);
 perform pg_temp.check((r->>'included')::int = 1 and (t->>'tiktok_net_settlement')::numeric = 7.65
     and (t->>'left_out_count')::int = 2 and (t->>'left_out_settlement')::numeric = 130.52,
   format('L6 a Manager includes one line: August counts 7.65 and still lists 2 left out (130.52), got %s / %s / %s',
     t->>'tiktok_net_settlement', t->>'left_out_count', t->>'left_out_settlement'));
 begin
   perform include_tiktok_settlement_rows(array[pg_temp.rid(b2,2)], 'Owner decision');
   ok := false; err := 'included';
 exception when others then ok := sqlerrm like '%not a left-out%'; err := sqlerrm; end;
 perform pg_temp.check(ok, 'L6 the same line cannot be included again through the other file''s row: ' || err);

 -- Both identical items at once, then neither again.
 perform pg_temp.as_user('o');
 begin
   perform include_tiktok_settlement_rows(array[pg_temp.rid(b2,3), pg_temp.rid(b2,4), pg_temp.rid(b,2)], 'Owner decision');
   ok := false; err := 'included';
 exception when others then ok := sqlerrm like '%not a left-out%'; err := sqlerrm; end;
 perform pg_temp.check(ok and pg_temp.lines('H') = '1 / 7.65',
   'L6 three rows for two identical left-out items: refused, and nothing of it counted: ' || err);
 r := include_tiktok_settlement_rows(array[pg_temp.rid(b2,3), pg_temp.rid(b,3)], 'Owner decision 29 Sep 2026');
 t := pg_temp.totals(2026, 8);
 perform pg_temp.check((r->>'included')::int = 2 and (r->>'settlement')::numeric = 130.52 and pg_temp.lines('H') = '3 / 138.17'
     and (t->>'tiktok_net_settlement')::numeric = 138.17 and (t->>'left_out_count')::int = 0
     and (t->>'left_out_settlement')::numeric = 0,
   format('L6 both identical items included: H counts 3 / 138.17 and August lists nothing left out, got %s; %s / %s',
     pg_temp.lines('H'), t->>'left_out_count', t->>'left_out_settlement'));
 perform pg_temp.check((select count(*) from tiktok_left_out_settlement(pg_temp.fx('st'), null, null)) = 0,
   'L6 the list is empty');
 perform pg_temp.check((select count(*) from audit_logs where action='tiktok_settlement_included' and reason like 'Owner decision%'
                          and record_id in (pg_temp.rid(b,1), pg_temp.rid(b2,3), pg_temp.rid(b,3))) = 3,
   'L6 every inclusion is audited with its reason');
exception when others then perform pg_temp.check(false, 'L6 include raised: ' || sqlerrm);
end $$;

-- An update left unticked is left out by its net change; including it
-- replaces the line it restates. (October, which nothing else here settles in.)
do $$
declare b uuid; b2 uuid; r jsonb; t jsonb; v_replaces numeric; v_net numeric;
begin
 b := pg_temp.stage('update left out before', jsonb_build_array(pg_temp.ln('K','50.00','60.00','-10.00','2026/10/05')));
 perform confirm_tiktok_settlement_batch(b, null);
 b2 := pg_temp.stage('update left out after', jsonb_build_array(pg_temp.ln('K','45.00','60.00','-15.00','2026/10/05')));
 perform confirm_tiktok_settlement_batch(b2, '[]'::jsonb);
 perform pg_temp.check(pg_temp.status(b2,1) = 'Updated — Requires Confirmation'
     and (select count(*) from tiktok_left_out_settlement(pg_temp.fx('st'), '2026-10-05', '2026-10-05')) = 1,
   'L6 an unticked update is listed as left out');
 t := pg_temp.totals(2026, 10);
 perform pg_temp.check((t->>'tiktok_net_settlement')::numeric = 50.00 and (t->>'left_out_count')::int = 1
     and (t->>'left_out_settlement')::numeric = -5.00,
   format('L6 October counts K''s 50.00 and says one line, -5.00, was left out (45.00 replacing 50.00), got %s / %s / %s',
     t->>'tiktok_net_settlement', t->>'left_out_count', t->>'left_out_settlement'));
 begin
   select l.replaces_settlement, l.net_change into v_replaces, v_net
     from tiktok_left_out_settlement(pg_temp.fx('st'), '2026-10-05', '2026-10-05') l;
   perform pg_temp.check(v_replaces = 50.00 and v_net = -5.00,
     format('L6 the list gives the settlement the update replaces, 50.00, and its net change, -5.00, got %s / %s', v_replaces, v_net));
 exception when others then perform pg_temp.check(false, 'L6 the list gives what an update replaces and its net change: ' || sqlerrm);
 end;
 r := include_tiktok_settlement_rows(array[pg_temp.rid(b2,1)], 'Owner decision');
 t := pg_temp.totals(2026, 10);
 perform pg_temp.check(pg_temp.lines('K') = '1 / 45.00' and (r->>'versioned_updates')::int = 1,
   format('L6 including it replaces the line it restates: K counts 45.00 only, got %s', pg_temp.lines('K')));
 perform pg_temp.check((r->>'settlement')::numeric = -5.00 and (t->>'tiktok_net_settlement')::numeric = 45.00
     and (t->>'left_out_count')::int = 0 and (t->>'left_out_settlement')::numeric = 0,
   format('L6 the inclusion reports its net change, -5.00, and October moves by it to 45.00 with nothing left out, got %s; %s / %s / %s',
     r->>'settlement', t->>'tiktok_net_settlement', t->>'left_out_count', t->>'left_out_settlement'));
exception when others then perform pg_temp.check(false, 'L6 update raised: ' || sqlerrm);
end $$;

-- A left-out line that a later file restates (the same order settled at the
-- same moment, and not this line) is no longer left out. (November.)
do $$
declare x uuid; y uuid; t jsonb; ok boolean; err text;
begin
 x := pg_temp.stage('restated left out one', jsonb_build_array(pg_temp.ln('V','80.00','96.00','-16.00','2026/11/03')));
 perform confirm_tiktok_settlement_batch(x, '[]'::jsonb);
 perform pg_temp.check((select count(*) from tiktok_left_out_settlement(pg_temp.fx('st'), '2026-11-03', '2026-11-03')) = 1,
   'L6 a line left unticked is listed as left out');
 y := pg_temp.stage('restated left out two', jsonb_build_array(pg_temp.ln('V','75.00','96.00','-21.00','2026/11/03')));
 perform pg_temp.check(pg_temp.status(y,1) = 'New — Pending Order',
   format('L6 its restatement has no counted line to update, so it is new, got %s', pg_temp.status(y,1)));
 -- One transaction stamps both uploads alike; the second file came later.
 update tiktok_import_batches set uploaded_at = uploaded_at + interval '1 hour' where id = y;
 perform confirm_tiktok_settlement_batch(y, null);
 t := pg_temp.totals(2026, 11);
 perform pg_temp.check((select count(*) from tiktok_left_out_settlement(pg_temp.fx('st'), '2026-11-03', '2026-11-03')) = 0
     and (t->>'left_out_count')::int = 0 and (t->>'left_out_settlement')::numeric = 0
     and (t->>'tiktok_net_settlement')::numeric = 75.00,
   format('L6 once the restatement counts, the restated line is not left out: November counts 75.00 with nothing left out, got %s / %s / %s',
     t->>'tiktok_net_settlement', t->>'left_out_count', t->>'left_out_settlement'));
 begin
   perform include_tiktok_settlement_rows(array[pg_temp.rid(x,1)], 'Owner decision');
   ok := false; err := 'included';
 exception when others then ok := sqlerrm like '%not a left-out%'; err := sqlerrm; end;
 perform pg_temp.check(ok and pg_temp.lines('V') = '1 / 75.00',
   format('L6 the restated line cannot be included on top of its restatement, V counts 75.00, got %s: %s', pg_temp.lines('V'), err));
exception when others then perform pg_temp.check(false, 'L6 restated raised: ' || sqlerrm);
end $$;

-- ═════ L6: a left-out row whose file is out of date ═════
-- File x (line SZ) is staged, then file y (TikTok's restatement of SZ, and a
-- line SV), then x is confirmed; y is confirmed with only SV ticked. y is the
-- later export, so its SZ row is listed as left out, but including it would
-- count SZ twice beside x's line: it is refused until y is uploaded again.
-- Staging takes the same store-wide lock as confirmation.
do $$
declare x uuid; y uuid; r jsonb; ok boolean; err text; probe uuid;
begin
 x := pg_temp.stage('stale one', jsonb_build_array(pg_temp.ln('SZ','100.00','120.00','-20.00','2026/12/02')));
 y := pg_temp.stage('stale two', jsonb_build_array(
   pg_temp.ln('SZ','95.00','120.00','-25.00','2026/12/02'),
   pg_temp.ln('SV','30.00','36.00','-6.00','2026/12/02')));
 -- One transaction stamps everything alike: x was staged two hours before
 -- it was confirmed, y one hour before.
 update tiktok_import_batches set uploaded_at = uploaded_at - interval '2 hours' where id = x;
 update tiktok_import_batches set uploaded_at = uploaded_at - interval '1 hour' where id = y;
 perform confirm_tiktok_settlement_batch(x, null);
 perform confirm_tiktok_settlement_batch(y, pg_temp.pick(y, array[2]));
 perform pg_temp.check(pg_temp.lines('SV') = '1 / 30.00'
     and exists (select 1 from tiktok_left_out_settlement(pg_temp.fx('st'), '2026-12-02', '2026-12-02') l
                  where l.row_id = pg_temp.rid(y,1)),
   format('L6 the unticked row of the overtaken file is still listed as left out (SV counts 1 / 30.00, got %s)', pg_temp.lines('SV')));
 begin
   r := include_tiktok_settlement_rows(array[pg_temp.rid(y,1)], 'Owner decision');
   ok := false; err := 'included: ' || r::text;
 exception when others then ok := sqlerrm like '%since%was uploaded%Upload that file again%'; err := sqlerrm; end;
 perform pg_temp.check(ok and pg_temp.lines('SZ') = '1 / 100.00',
   format('L6 it cannot be included, and SZ counts one 100.00, got %s: %s', pg_temp.lines('SZ'), err));

 insert into tiktok_import_batches(store_id, file_kind, file_name, uploaded_by)
 values (pg_temp.fx('st'), 'settlement', 'S368 stage lock probe.xlsx', pg_temp.fx('o')) returning id into probe;
 perform pg_temp.stage('stage lock', jsonb_build_array(pg_temp.ln('ST','10.00','12.00','-2.00','2026/12/03')));
 perform pg_temp.check((select xmax::text from tiktok_import_batches where id = probe) <> '0',
   'L5 staging a file locks every settlement file of its store, so it never compares against half a confirmation');
exception when others then perform pg_temp.check(false, 'L6 out-of-date left-out raised: ' || sqlerrm);
end $$;

-- ═════ L7: who may call what ═════
do $$
begin
 perform pg_temp.check(to_regprocedure('public.tiktok_settlement_left_out_rows(uuid)') is not null
     and not has_function_privilege('authenticated','public.tiktok_settlement_left_out_rows(uuid)','execute')
     and not has_function_privilege('anon','public.tiktok_settlement_left_out_rows(uuid)','execute'),
   'L7 the left-out rule exists and no client role can call it');
 perform pg_temp.check(to_regprocedure('public.tiktok_left_out_settlement(uuid,date,date)') is not null
     and has_function_privilege('authenticated','public.tiktok_left_out_settlement(uuid,date,date)','execute')
     and not has_function_privilege('anon','public.tiktok_left_out_settlement(uuid,date,date)','execute')
     and has_function_privilege('authenticated','public.include_tiktok_settlement_rows(uuid[],text)','execute')
     and not has_function_privilege('anon','public.include_tiktok_settlement_rows(uuid[],text)','execute'),
   'L7 the list and the include are for signed-in staff, not the anon key');
exception when others then perform pg_temp.check(false, 'L7 raised: ' || sqlerrm);
end $$;

do $$
declare k int; msgs text;
begin
 select count(*), string_agg(f.msg, E'\n  ' order by f.n) into k, msgs from failed f;
 if k > 0 then raise exception 'FAIL: % check(s) failed:%', k, E'\n  ' || msgs; end if;
 raise notice 'PASS: 368 — a file''s rows are lines (identical items count), re-imports and overlapping files count each line once, a file out of date is refused and counts once staged again, restatements update and instalments add, left-out lines are listed, totalled by their net change and includable once by an Owner or Manager';
end $$;
rollback;
