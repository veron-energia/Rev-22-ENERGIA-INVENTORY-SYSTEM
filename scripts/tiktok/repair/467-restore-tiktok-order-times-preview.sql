-- 467 repair, preview: what 467-restore-tiktok-order-times.sql would put
-- right, counts only (no order id, no name). Read only: a plain select, safe
-- to run any time, through the MCP execute_sql tool too (which does not show
-- the repair's own notices). Run after 467 is in: before it, "right" below
-- is the old reading, and every count is 0.
--
-- One row per column, then the total. "times" is what the repair counts and
-- what repair467.expect must be set to; "rows" are rows with at least one of
-- them. "moves_month" counts the times whose Singapore month changes (every
-- swap does, but 05/05 is never swapped); "stored_in_future" those stored
-- after now.
with x as (
  select o.id, o.confirmed, b.deleted_at is not null as deleted_file, k,
         (to_jsonb(o)->>k)::timestamptz as stored,
         public.tiktok_parse_time(o.raw->>k) as right_
    from public.tiktok_order_rows o
    join public.tiktok_import_batches b on b.id = o.batch_id,
         unnest(array['rts_time', 'created_time', 'paid_time', 'shipped_time', 'delivered_time', 'cancelled_time']) k
), d as (select * from x where stored is distinct from right_)
select coalesce(k, 'all six') as column_,
       count(*) as times,
       count(distinct id) as rows,
       count(distinct id) filter (where confirmed) as confirmed_rows,
       count(distinct id) filter (where deleted_file) as rows_of_deleted_files,
       count(*) filter (where date_trunc('month', stored at time zone 'Asia/Singapore')
                              is distinct from date_trunc('month', right_ at time zone 'Asia/Singapore')) as moves_month,
       count(*) filter (where stored > now()) as stored_in_future,
       count(*) filter (where right_ is null) as right_is_null
  from d
 group by rollup (k)
 order by k nulls last;
