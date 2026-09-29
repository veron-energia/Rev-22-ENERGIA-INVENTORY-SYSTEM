-- Put back the TikTok settlement lines the app stopped counting (goes with 368).
--
-- PROPOSED, NOT RUN. Run it on production only with the owner's go-ahead, AFTER
-- 368 is applied, and after reading 2026-09-29-settlement-lines-preview.sql.
-- One transaction. Every step checks the exact state it expects and the whole
-- repair refuses (and changes nothing) if anything differs, so it cannot run
-- twice. Each change writes an audit row.
--
-- WHY THIS EXISTS
--
--   A. September, S$238.35. TikTok's income export has one row per order line.
--      Re-importing an overlapping file on 29 Sep 2026 (income_20260929124212
--      over income_20260929123117) compared each row with ONE current row of
--      its order, so a second line of the order became an "update" of the
--      first and confirming it took the first out of the totals:
--        order ...838068 (settled 15 Sep): lines 236.02 + 135.12. Counted now:
--          135.12 (file 1, row 14) + 135.12 (file 2, row 14, an "update" of
--          file 1 row 13). File 1 row 13 (236.02) no longer counts. -100.90.
--        order ...285244 (settled 18 Sep): lines 137.45 + 64.17 + 64.17.
--          Counted now: 64.17 (file 1, row 10) + 64.17 (file 2, row 10, an
--          "update" of file 1 row 9). File 1 row 9 (137.45) no longer counts.
--          -137.45.
--      Fix: file 1 row 13 and row 9 count again; file 2 row 14 stops counting
--      (it is the same line as file 1 row 14). File 2 row 10 stays: it is the
--      order's second 64.17 item, which file 1 had marked "Duplicate Row".
--
--   B. August, S$450.25. Four lines settled on 1-3 Aug 2026 (117.80 + 259.54
--      on one order, 65.26, 7.65) were staged as "New — Pending Order" in
--      income_20260819175611 (rows 17-20) and again in income_20260828162029
--      (rows 28-31). Both files were confirmed with them unticked, so they
--      count nowhere. The owner decided on 29 Sep 2026 that they count in
--      August: they are included through include_tiktok_settlement_rows (368),
--      which re-checks that each is still left out.
--
-- NOT TOUCHED: every other row; the stored values of every row (confirmed rows
-- are immutable, only which of them count changes); the 30-31 Jul settlements
-- that no imported file holds (the owner will import that file).
--
-- EXPECTED: August's Total Income +450.25 and September's +238.35 on the
-- TikTok tab (and TikTok's net settlement the same), checked before commit.

begin;
set local lock_timeout = '5s';
-- Run as the Owner applying it: their profile id (profiles.id) goes here. The
-- repair refuses anyone else, and the audit rows name them.
select set_config('request.jwt.claim.sub', 'OWNER-PROFILE-ID', true);

do $repair$
declare
  c_f62a constant uuid := 'f62aba80-b316-441c-b70e-03b02ab86dff';  -- income_20260929123117
  c_aa39 constant uuid := 'aa394428-7c89-4cff-a89c-40e67c61c883';  -- income_20260929124212
  c_b0b6 constant uuid := 'b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9';  -- income_20260819175611
  c_reason constant text := 'Owner decision 29 Sep 2026: the settlement lines of 1-3 Aug 2026 count in August '
                            || '(left out at confirmation of income_20260819175611 and income_20260828162029)';
  v_store uuid; v_sub text;
  a13 public.tiktok_settlement_rows%rowtype; a14 public.tiktok_settlement_rows%rowtype;
  u14 public.tiktok_settlement_rows%rowtype;
  b9 public.tiktok_settlement_rows%rowtype; b10 public.tiktok_settlement_rows%rowtype;
  u10 public.tiktok_settlement_rows%rowtype;
  v_aug_ids uuid[]; v_aug_amounts numeric[]; n int;
  aug_before jsonb; sep_before jsonb; aug_after jsonb; sep_after jsonb; v_inc jsonb;
begin
  -- ── who, and is 368 in place ──
  v_sub := current_setting('request.jwt.claim.sub', true);
  if coalesce(v_sub, '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    raise exception 'Put the applying Owner''s profile id in the set_config line first; refusing'; end if;
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'The profile id given is not an active Owner; refusing'; end if;
  if to_regprocedure('public.include_tiktok_settlement_rows(uuid[],text)') is null
     or position('368:' in pg_get_functiondef('public.stage_tiktok_settlement(uuid,text,text,jsonb)'::regprocedure)) = 0 then
    raise exception '368 is not applied; apply it first. Refusing'; end if;

  -- ── the four files, and one store's settlement lines held still ──
  select b.store_id into v_store from public.tiktok_import_batches b where b.id = c_f62a;
  if (select count(*) from public.tiktok_import_batches b
       where b.id in (c_f62a, c_aa39, c_b0b6, 'a45ca9ff-d32f-45ec-a570-0208c1eaea3b')
         and b.store_id = v_store and b.file_kind = 'settlement' and b.status = 'confirmed' and b.deleted_at is null) <> 4 then
    raise exception 'The four settlement files are not all confirmed files of one store; refusing'; end if;
  perform 1 from public.tiktok_import_batches b
   where b.store_id = v_store and b.file_kind = 'settlement' order by b.id for update;

  -- ── A. order ...838068: file 1 rows 13 and 14, file 2 row 14 ──
  select * into a13 from public.tiktok_settlement_rows where batch_id = c_f62a and row_no = 13 for update;
  select * into a14 from public.tiktok_settlement_rows where batch_id = c_f62a and row_no = 14 for update;
  select * into u14 from public.tiktok_settlement_rows where batch_id = c_aa39 and row_no = 14 for update;
  if a13.id is null or a14.id is null or u14.id is null
     or not (a13.confirmed and not a13.is_current and not a13.excluded and a13.staging_status = 'New — Matched'
             and a13.settlement_amount = 236.02 and a13.revenue_amount = 282.53 and a13.fee_amount = -46.51)
     or not (a14.confirmed and a14.is_current and not a14.excluded and a14.settlement_amount = 135.12
             and a14.order_id = a13.order_id and a14.settled_time = a13.settled_time)
     or not (u14.confirmed and u14.is_current and not u14.excluded
             and u14.staging_status = 'Updated — Requires Confirmation' and u14.previous_row_id = a13.id
             and (u14.order_id, u14.transaction_type, u14.related_order_id, u14.settlement_amount, u14.revenue_amount,
                  u14.fee_amount, u14.adjustment_amount, u14.refund_amount, u14.currency, u14.order_created_time,
                  u14.settled_time)
                 is not distinct from
                 (a14.order_id, a14.transaction_type, a14.related_order_id, a14.settlement_amount, a14.revenue_amount,
                  a14.fee_amount, a14.adjustment_amount, a14.refund_amount, a14.currency, a14.order_created_time,
                  a14.settled_time))
     or (select array_agg(r.id order by r.id) from public.tiktok_settlement_rows r
          where r.store_id = v_store and r.order_id = a13.order_id and r.confirmed and r.is_current)
        is distinct from (select array_agg(x order by x) from unnest(array[a14.id, u14.id]) x) then
    raise exception 'Order ...838068 is not as found on 29 Sep 2026 (file 1 row 13 not counted; file 1 row 14 and file 2 row 14 counted, the latter an update of row 13); refusing'; end if;

  -- ── A. order ...285244: file 1 rows 9 and 10, file 2 row 10 ──
  select * into b9  from public.tiktok_settlement_rows where batch_id = c_f62a and row_no = 9 for update;
  select * into b10 from public.tiktok_settlement_rows where batch_id = c_f62a and row_no = 10 for update;
  select * into u10 from public.tiktok_settlement_rows where batch_id = c_aa39 and row_no = 10 for update;
  if b9.id is null or b10.id is null or u10.id is null
     or not (b9.confirmed and not b9.is_current and not b9.excluded and b9.staging_status = 'New — Matched'
             and b9.settlement_amount = 137.45 and b9.revenue_amount = 164.05 and b9.fee_amount = -26.60)
     or not (b10.confirmed and b10.is_current and not b10.excluded and b10.settlement_amount = 64.17
             and b10.order_id = b9.order_id and b10.settled_time = b9.settled_time)
     or not (u10.confirmed and u10.is_current and not u10.excluded
             and u10.staging_status = 'Updated — Requires Confirmation' and u10.previous_row_id = b9.id
             and (u10.order_id, u10.transaction_type, u10.related_order_id, u10.settlement_amount, u10.revenue_amount,
                  u10.fee_amount, u10.adjustment_amount, u10.refund_amount, u10.currency, u10.order_created_time,
                  u10.settled_time)
                 is not distinct from
                 (b10.order_id, b10.transaction_type, b10.related_order_id, b10.settlement_amount, b10.revenue_amount,
                  b10.fee_amount, b10.adjustment_amount, b10.refund_amount, b10.currency, b10.order_created_time,
                  b10.settled_time))
     or (select array_agg(r.id order by r.id) from public.tiktok_settlement_rows r
          where r.store_id = v_store and r.order_id = b9.order_id and r.confirmed and r.is_current)
        is distinct from (select array_agg(x order by x) from unnest(array[b10.id, u10.id]) x) then
    raise exception 'Order ...285244 is not as found on 29 Sep 2026 (file 1 row 9 not counted; file 1 row 10 and file 2 row 10 counted, the latter an update of row 9); refusing'; end if;

  -- ── B. 1-3 Aug: income_20260819175611 rows 17-20 ──
  select array_agg(r.id order by r.row_no), array_agg(r.settlement_amount order by r.row_no), count(*)
    into v_aug_ids, v_aug_amounts, n
    from public.tiktok_settlement_rows r
   where r.batch_id = c_b0b6 and r.row_no between 17 and 20
     and not r.confirmed and not r.is_current and r.excluded and r.staging_status = 'New — Pending Order';
  if n <> 4 or v_aug_amounts <> array[7.65, 65.26, 117.80, 259.54]::numeric[] then
    raise exception 'income_20260819175611 rows 17-20 are no longer the four unticked lines of 7.65, 65.26, 117.80 and 259.54; refusing'; end if;
  if (select count(*) from public.tiktok_settlement_left_out_rows(v_store) l
       where l.id = any(v_aug_ids) and l.left_out >= 1) <> 4 then
    raise exception 'The four lines of 1-3 Aug are not all left out any more (counted since?); refusing'; end if;

  aug_before := public.tiktok_settlement_totals(2026, 8, v_store);
  sep_before := public.tiktok_settlement_totals(2026, 9, v_store);

  -- ── A. the two September orders count their lines again ──
  update public.tiktok_settlement_rows set is_current = true where id = a13.id;
  perform public.write_audit_ex('tiktok_settlement_rows', a13.id, 'tiktok_settlement_line_restored',
    jsonb_build_object('is_current', false),
    jsonb_build_object('is_current', true, 'settlement_amount', a13.settlement_amount,
                       'repair', 'a second line of its order, taken out by a re-import that treated it as an earlier version'),
    'tiktok_import', 'TikTok exports one row per order line; 368 stops re-imports replacing lines', v_store);
  update public.tiktok_settlement_rows set is_current = false where id = u14.id;
  perform public.write_audit_ex('tiktok_settlement_rows', u14.id, 'tiktok_settlement_line_withdrawn',
    jsonb_build_object('is_current', true),
    jsonb_build_object('is_current', false, 'settlement_amount', u14.settlement_amount, 'same_line_as', a14.id,
                       'repair', 'the same order line as one already counted, imported again as an update of another line'),
    'tiktok_import', 'TikTok exports one row per order line; 368 stops re-imports replacing lines', v_store);
  update public.tiktok_settlement_rows set is_current = true where id = b9.id;
  perform public.write_audit_ex('tiktok_settlement_rows', b9.id, 'tiktok_settlement_line_restored',
    jsonb_build_object('is_current', false),
    jsonb_build_object('is_current', true, 'settlement_amount', b9.settlement_amount,
                       'repair', 'a second line of its order, taken out by a re-import that treated it as an earlier version'),
    'tiktok_import', 'TikTok exports one row per order line; 368 stops re-imports replacing lines', v_store);

  -- ── B. the 1-3 Aug lines count in August (audited by the function) ──
  v_inc := public.include_tiktok_settlement_rows(v_aug_ids, c_reason);
  if (v_inc->>'included')::int <> 4 or (v_inc->>'settlement')::numeric <> 450.25 then
    raise exception 'Including the 1-3 Aug lines gave %; refusing', v_inc; end if;

  -- ── the result, before anything is committed ──
  aug_after := public.tiktok_settlement_totals(2026, 8, v_store);
  sep_after := public.tiktok_settlement_totals(2026, 9, v_store);
  if (aug_after->>'income')::numeric - (aug_before->>'income')::numeric <> 450.25
     or (aug_after->>'tiktok_net_settlement')::numeric - (aug_before->>'tiktok_net_settlement')::numeric <> 450.25
     or (sep_after->>'income')::numeric - (sep_before->>'income')::numeric <> 238.35
     or (sep_after->>'tiktok_net_settlement')::numeric - (sep_before->>'tiktok_net_settlement')::numeric <> 238.35
     or (aug_after->>'left_out_count')::int <> 0 then
    raise exception 'Unexpected result: August income % -> %, September income % -> %, August left out %; refusing',
      aug_before->>'income', aug_after->>'income', sep_before->>'income', sep_after->>'income', aug_after->>'left_out_count'; end if;
  raise notice 'Repaired. August Total Income % -> % (+450.25); September % -> % (+238.35).',
    aug_before->>'income', aug_after->>'income', sep_before->>'income', sep_after->>'income';
end $repair$;

-- ── verification (inside the transaction; the DO block has already checked) ──
-- The lines each affected order counts now.
select r.order_id, count(*) as lines, sum(r.settlement_amount) as settlement,
       string_agg(r.settlement_amount::text, ' + ' order by r.settlement_amount desc) as amounts
  from public.tiktok_settlement_rows r
 where r.confirmed and r.is_current and not r.excluded
   and r.order_id in (select x.order_id from public.tiktok_settlement_rows x
                       where (x.batch_id, x.row_no) in (('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid, 13),
                                                         ('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid, 9),
                                                         ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 17),
                                                         ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 18),
                                                         ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 19)))
 group by r.order_id order by min(r.settled_time);
-- August and September on the TikTok tab.
select t->>'period_start' as period_start, t->>'period_end' as period_end, t->>'income' as total_income,
       t->>'tiktok_net_settlement' as tiktok_net, t->>'left_out_count' as left_out_lines
  from (select public.tiktok_settlement_totals(2026, m,
                 (select store_id from public.tiktok_import_batches where id = 'f62aba80-b316-441c-b70e-03b02ab86dff')) t
          from (values (8), (9)) v(m)) z;
-- The audit rows written.
select action, count(*) from public.audit_logs
 where action in ('tiktok_settlement_line_restored', 'tiktok_settlement_line_withdrawn', 'tiktok_settlement_included')
   and created_at >= now() group by action order by action;

commit;
