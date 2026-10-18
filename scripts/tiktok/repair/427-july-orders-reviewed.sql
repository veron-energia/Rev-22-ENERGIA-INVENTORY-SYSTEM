-- 427 repair: the TikTok orders of 25 to 30 July 2026, left as they are.
--
-- TikTok settled (paid out) six lines for five orders placed between 25 and
-- 30 July 2026 (S$798.46 in all), at Energia Rev 22 (Adelphi). Their order
-- file was uploaded on 3 Aug and deleted on 11 Aug without being confirmed,
-- so the app never took their stock off. The Owner said on 9 Oct 2026 (Q20):
-- they were sold before the app tracked TikTok stock; leave them. (The
-- audit and the question counted "six July orders, seven lines": the seventh
-- line is the 28 August order (Singapore time; the audit's "27 August"),
-- which has a repair of its own.) This
-- records that, through tiktok_settlement_review_record (427), as the Owner
-- named below: each line is reviewed as needing no stock taken off, with the
-- reason below, audited. The lines then leave the Dashboard's "Settled with
-- no imported order" and the TikTok Reconciliation tab's exceptions. No
-- stock, order or settlement row is changed.
--
-- The ids are not in this file (the repository is public): the hand-off
-- lists them. Before running, in the same session, give them:
--   select set_config('repair427.actor', '<the Owner''s profile id>', false),
--          set_config('repair427.store', '<Adelphi''s store id>', false),
--          set_config('repair427.july_rows', '[
--            {"id": "<settlement line id>", "order_id": "<TikTok order id>", "amount": 340.99},
--            ... the six lines ...
--          ]', false);
-- The settings last for the session only: where each run is a session of
-- its own (the MCP execute_sql tool, the SQL editor), send the set_config
-- lines and this file's text together, in one run.
--
-- Run it once, after 427, as the database owner (the SQL editor, the MCP
-- execute_sql tool, or psql as postgres), with the Owner's go-ahead. It is
-- one statement, so it is atomic. It acts only while the six lines given
-- are the six read on 10 Oct 2026 (six lines, five orders, the amounts
-- below, ordered between 24 and 31 July 2026) and are still confirmed,
-- current, at the store given and waiting for their order, and the actor
-- given is an active Owner; otherwise it changes nothing and says why.
-- A second run changes nothing (lines already reviewed are left as they
-- are). It prints amounts and ids only (a notice), never a name.
-- Expected on production (10 Oct 2026): "6 settlement lines (5 orders,
-- S$798.46) reviewed as needing no stock taken off; still settled with no
-- imported order: 1" (the 28 August order, the Owner's "27 August" one).
--
-- repair427.actor is the Owner account the reviews are recorded under
-- (reviewed_by, and the audit rows): the hand-off names the Owner login used
-- for the earlier owner actions run this way (414's repair). Give the other
-- Owner's id instead if the Owner wants it recorded under theirs.
--
-- To check afterwards (ids and amounts only):
--   select r.settlement_row_id, r.decision, r.reviewed_by, r.reviewed_at
--     from public.tiktok_settlement_reviews r order by r.reviewed_at;
--   -- expected: the six ids given, 'no_stock_needed'

do $repair$
declare
  c_reason constant text := 'Sold before the app tracked TikTok stock (orders of 25 to 30 July 2026): left as they are, no stock taken off (the Owner, 9 Oct 2026, Q20).';
  -- The six lines' settlement amounts, as read on 10 Oct 2026 (S$798.46 in all).
  c_amounts constant numeric[] := '{7.22,7.65,65.26,117.80,259.54,340.99}';
  c_record_after constant text := '2d681e62d3c71e35f00bb872603fdf88';  -- 427's AFTER
  c_alerts_after constant text := '2b632d0dcc23b82c6ef4e1438271debf';  -- 427's AFTER
  v_path text := current_setting('search_path');
  c_actor uuid; c_store uuid; c_rows jsonb;
  v_ids uuid[]; v_n int; v_reviewed int; v_bad text; v_res jsonb; v_left int;
begin
  perform set_config('search_path', 'public', true);
  if to_regprocedure('public.tiktok_settlement_review_record(uuid[],text,uuid)') is null
     or md5(pg_get_functiondef('public.tiktok_settlement_review_record(uuid[],text,uuid)'::regprocedure)) <> c_record_after
     or md5(pg_get_functiondef('public.dashboard_alerts_summary()'::regprocedure)) <> c_alerts_after then
    raise exception '427 repair: 427 is not in (its functions are missing or not its versions); apply 427 first'; end if;

  -- The ids, given in the session (the hand-off lists them).
  begin
    c_actor := nullif(btrim(coalesce(current_setting('repair427.actor', true), '')), '')::uuid;
    c_store := nullif(btrim(coalesce(current_setting('repair427.store', true), '')), '')::uuid;
    c_rows  := nullif(btrim(coalesce(current_setting('repair427.july_rows', true), '')), '')::jsonb;
  exception when others then
    raise exception '427 repair: repair427.actor and repair427.store must be ids and repair427.july_rows JSON; nothing was changed'; end;
  if c_actor is null or c_store is null or c_rows is null then
    raise exception '427 repair: give the ids first (repair427.actor, repair427.store, repair427.july_rows; the hand-off lists them); nothing was changed'; end if;
  if jsonb_typeof(c_rows) <> 'array'
     or exists (select 1 from jsonb_array_elements(c_rows) x
                 where jsonb_typeof(x) <> 'object' or coalesce(x->>'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                    or nullif(btrim(coalesce(x->>'order_id', '')), '') is null
                    or coalesce(x->>'amount', '') !~ '^[0-9]+(\.[0-9]{1,2})?$') then
    raise exception '427 repair: repair427.july_rows must list each line as {"id": ..., "order_id": ..., "amount": ...}; nothing was changed'; end if;
  if (select count(distinct x->>'id') from jsonb_array_elements(c_rows) x) <> 6 or jsonb_array_length(c_rows) <> 6
     or (select count(distinct x->>'order_id') from jsonb_array_elements(c_rows) x) <> 5
     or (select array_agg((x->>'amount')::numeric order by (x->>'amount')::numeric) from jsonb_array_elements(c_rows) x) <> c_amounts then
    raise exception '427 repair: repair427.july_rows is not the six lines read on 10 Oct 2026 (six lines, five orders, S$798.46: %); nothing was changed', c_amounts; end if;
  if not exists (select 1 from public.profiles p where p.id = c_actor and p.role = 'owner' and p.is_active and p.deleted_at is null) then
    raise exception '427 repair: repair427.actor is not an active Owner; nothing was changed'; end if;

  select array_agg((x->>'id')::uuid) into v_ids from jsonb_array_elements(c_rows) x;

  -- Every line as read: the same order, amount and store, confirmed and current.
  select string_agg(coalesce(s.id::text, x->>'id'), ', ') into v_bad
    from jsonb_array_elements(c_rows) x
    left join public.tiktok_settlement_rows s on s.id = (x->>'id')::uuid
   where s.id is null or s.store_id <> c_store or s.order_id is distinct from x->>'order_id'
      or s.settlement_amount is distinct from (x->>'amount')::numeric or not s.confirmed or not s.is_current
      or s.txn_class is distinct from 'order'
      or (s.order_created_time at time zone 'Asia/Singapore')::date not between date '2026-07-24' and date '2026-07-31';
  if v_bad is not null then
    raise exception '427 repair: these lines are not as given or as read on 10 Oct 2026 (missing, changed, superseded or at another store): %; nothing was changed', v_bad; end if;

  -- A second run: all six reviewed already; leave them as they are.
  select count(*) into v_reviewed from public.tiktok_settlement_reviews r where r.settlement_row_id = any (v_ids);
  if v_reviewed = cardinality(v_ids) then
    raise notice '427 repair: already recorded (6 lines reviewed); nothing changed';
    perform set_config('search_path', v_path, true);
    return;
  end if;
  if v_reviewed > 0 then
    raise exception '427 repair: % of the 6 lines were already reviewed; nothing was changed. Re-read them with the Owner.', v_reviewed; end if;

  -- Only the case the Owner decided on: all still waiting for their order.
  select count(*) into v_n from public.tiktok_settlement_rows s where s.id = any (v_ids) and s.match_status = 'pending';
  if v_n <> cardinality(v_ids) then
    raise exception '427 repair: % of the 6 lines are no longer waiting for their order (was an order file imported since?); nothing was changed. Re-read them with the Owner.', cardinality(v_ids) - v_n; end if;
  if exists (select 1 from public.tiktok_order_state st
              where st.store_id = c_store and st.order_id in (select x->>'order_id' from jsonb_array_elements(c_rows) x)) then
    raise exception '427 repair: stock was taken off for one of these orders since; nothing was changed. Re-read them with the Owner.'; end if;

  v_res := public.tiktok_settlement_review_record(v_ids, c_reason, c_actor);
  if (v_res->>'reviewed')::int <> 6 then
    raise exception '427 repair: % lines were reviewed, not 6; nothing was changed', v_res->>'reviewed'; end if;

  select count(distinct (r.store_id, coalesce(r.order_id, r.related_order_id, r.adjustment_id, r.id::text))) into v_left
    from public.tiktok_settlement_rows r
   where r.confirmed and r.is_current and r.match_status = 'pending'
     and not exists (select 1 from public.tiktok_settlement_reviews v where v.settlement_row_id = r.id);
  raise notice '427 repair: 6 settlement lines (5 orders, S$%) reviewed as needing no stock taken off; still settled with no imported order: %',
    (select to_char(sum((x->>'amount')::numeric), 'FM999999990.00') from jsonb_array_elements(c_rows) x), v_left;
  perform set_config('search_path', v_path, true);
end $repair$;
