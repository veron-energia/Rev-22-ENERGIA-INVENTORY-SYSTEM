-- Dry run of 2026-09-29-settlement-lines.sql: what it would change. READ ONLY.
--
-- Changes nothing and needs nothing new, so it runs before 368 as well as
-- after. Three results:
--   1. every row the repair touches, and whether it is in the state the repair
--      expects (every "ok" must be true, or the repair will refuse);
--   2. each affected order's counted lines, now and after;
--   3. August and September on the TikTok tab, now and after: Total Income and
--      TikTok's net settlement, worked out from the rows the way
--      tiktok_settlement_totals works them out. Run signed in (request.jwt.claim.sub
--      set to an Owner's profile id) and "app_income_now" shows the tab's own
--      figure, which should equal "income_now".
-- Each statement repeats the list of rows, because a read-only transaction can
-- keep nothing between statements.

begin transaction read only;

-- ── 1. the rows the repair touches ──
with touch(batch_id, row_no, change) as (values
  ('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid, 13, 'counts again'),
  ('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid, 14, 'unchanged'),
  ('aa394428-7c89-4cff-a89c-40e67c61c883'::uuid, 14, 'stops counting'),
  ('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid,  9, 'counts again'),
  ('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid, 10, 'unchanged'),
  ('aa394428-7c89-4cff-a89c-40e67c61c883'::uuid, 10, 'unchanged'),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 17, 'included'),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 18, 'included'),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 19, 'included'),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 20, 'included'))
select b.file_name, t.row_no, r.order_id, (r.settled_time at time zone 'Asia/Singapore')::date as settled_sgt,
       r.settlement_amount, r.staging_status,
       (r.confirmed and r.is_current and not r.excluded) as counted_now,
       t.change,
       case t.change
         when 'counts again' then r.confirmed and not r.is_current and not r.excluded
         when 'unchanged' then r.confirmed and r.is_current and not r.excluded
         -- counted, and the same line as another counted row of its order
         when 'stops counting' then r.confirmed and r.is_current and not r.excluded
           and r.staging_status = 'Updated — Requires Confirmation'
           and exists (select 1 from public.tiktok_settlement_rows x
                        where x.store_id = r.store_id and x.order_id = r.order_id and x.id <> r.id
                          and x.confirmed and x.is_current and not x.excluded
                          and (x.transaction_type, x.related_order_id, x.settlement_amount, x.revenue_amount,
                               x.fee_amount, x.adjustment_amount, x.refund_amount, x.currency, x.settled_time)
                              is not distinct from
                              (r.transaction_type, r.related_order_id, r.settlement_amount, r.revenue_amount,
                               r.fee_amount, r.adjustment_amount, r.refund_amount, r.currency, r.settled_time))
         -- unticked in a confirmed file, no identical line counted since, and
         -- not restated by a later confirmed file (rows of the order settled
         -- at the same moment, none of them this line)
         when 'included' then not r.confirmed and r.excluded and r.staging_status = 'New — Pending Order'
           and b.status = 'confirmed' and b.deleted_at is null
           and not exists (select 1 from public.tiktok_settlement_rows x
                            where x.store_id = r.store_id and x.order_id = r.order_id
                              and x.confirmed and x.is_current
                              and (x.transaction_type, x.related_order_id, x.settlement_amount, x.revenue_amount,
                                   x.fee_amount, x.adjustment_amount, x.refund_amount, x.currency, x.settled_time)
                                  is not distinct from
                                  (r.transaction_type, r.related_order_id, r.settlement_amount, r.revenue_amount,
                                   r.fee_amount, r.adjustment_amount, r.refund_amount, r.currency, r.settled_time))
           and not exists (select 1 from public.tiktok_import_batches lb
                            where lb.store_id = r.store_id and lb.file_kind = 'settlement' and lb.status = 'confirmed'
                              and lb.deleted_at is null and lb.uploaded_at > b.uploaded_at
                              and exists (select 1 from public.tiktok_settlement_rows s
                                           where s.batch_id = lb.id and s.order_id = r.order_id
                                             and s.settled_time is not distinct from r.settled_time
                                             and s.staging_status is distinct from 'Invalid Row')
                              and not exists (select 1 from public.tiktok_settlement_rows s
                                               where s.batch_id = lb.id and s.order_id = r.order_id
                                                 and s.staging_status is distinct from 'Invalid Row'
                                                 and (s.transaction_type, s.related_order_id, s.settlement_amount,
                                                      s.revenue_amount, s.fee_amount, s.adjustment_amount,
                                                      s.refund_amount, s.currency, s.settled_time)
                                                     is not distinct from
                                                     (r.transaction_type, r.related_order_id, r.settlement_amount,
                                                      r.revenue_amount, r.fee_amount, r.adjustment_amount,
                                                      r.refund_amount, r.currency, r.settled_time)))
       end as ok
  from touch t
  left join public.tiktok_settlement_rows r on r.batch_id = t.batch_id and r.row_no = t.row_no
  left join public.tiktok_import_batches b on b.id = t.batch_id
 order by r.settled_time, r.order_id, b.uploaded_at, t.row_no;

-- ── 2. each affected order: counted lines now → after ──
with touch(batch_id, row_no, counts_after) as (values
  ('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid, 13, true),
  ('aa394428-7c89-4cff-a89c-40e67c61c883'::uuid, 14, false),
  ('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid,  9, true),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 17, true),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 18, true),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 19, true),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 20, true)),
changed as (
  select r.id, r.store_id, r.order_id, t.counts_after
    from touch t join public.tiktok_settlement_rows r on r.batch_id = t.batch_id and r.row_no = t.row_no),
lines as (
  select r.order_id, r.settled_time, r.settlement_amount,
         r.confirmed and r.is_current and not r.excluded as now,
         coalesce(c.counts_after, r.confirmed and r.is_current and not r.excluded) as after
    from public.tiktok_settlement_rows r
    left join changed c on c.id = r.id
   where (r.store_id, r.order_id) in (select store_id, order_id from changed))
select l.order_id, (min(l.settled_time) at time zone 'Asia/Singapore')::date as settled_sgt,
       count(*) filter (where l.now) as lines_now,
       coalesce(sum(l.settlement_amount) filter (where l.now), 0) as settlement_now,
       string_agg(l.settlement_amount::text, ' + ' order by l.settlement_amount desc) filter (where l.now) as now,
       count(*) filter (where l.after) as lines_after,
       coalesce(sum(l.settlement_amount) filter (where l.after), 0) as settlement_after,
       string_agg(l.settlement_amount::text, ' + ' order by l.settlement_amount desc) filter (where l.after) as after,
       coalesce(sum(l.settlement_amount) filter (where l.after), 0)
         - coalesce(sum(l.settlement_amount) filter (where l.now), 0) as change
  from lines l
 group by l.order_id
 order by min(l.settled_time), l.order_id;

-- ── 3. August and September on the TikTok tab: now → after ──
with touch(batch_id, row_no, counts_after) as (values
  ('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid, 13, true),
  ('aa394428-7c89-4cff-a89c-40e67c61c883'::uuid, 14, false),
  ('f62aba80-b316-441c-b70e-03b02ab86dff'::uuid,  9, true),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 17, true),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 18, true),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 19, true),
  ('b0b6c7a1-49e6-4970-8a18-69e84d9a2ea9'::uuid, 20, true)),
changed as (
  select r.id, t.counts_after
    from touch t join public.tiktok_settlement_rows r on r.batch_id = t.batch_id and r.row_no = t.row_no),
store as (select b.store_id from public.tiktok_import_batches b where b.id = 'f62aba80-b316-441c-b70e-03b02ab86dff'),
money as (
  -- each row's part of Total Income, as tiktok_settlement_totals adds it up
  select r.settled_time, r.settlement_amount,
         r.confirmed and r.is_current and not r.excluded as now,
         coalesce(c.counts_after, r.confirmed and r.is_current and not r.excluded) as after,
         case when k.category in ('sale','sale_refund') then coalesce(r.revenue_amount, 0) + coalesce(r.fee_amount, 0)
              when k.category in ('fee','fee_reversal') then coalesce(nullif(r.fee_amount, 0), r.adjustment_amount, 0)
              when k.category in ('ad_expense','expense_reversal') then coalesce(r.adjustment_amount, 0)
              else 0 end as income
    from public.tiktok_settlement_rows r
    cross join lateral (select public.tiktok_finance_category(r.transaction_type, r.adjustment_amount) as category) k
    left join changed c on c.id = r.id
   where r.store_id = (select store_id from store))
select p.m as month, per.start_date, per.end_date,
       coalesce(sum(x.income) filter (where x.now), 0) as income_now,
       coalesce(sum(x.income) filter (where x.after), 0) as income_after,
       coalesce(sum(x.income) filter (where x.after), 0) - coalesce(sum(x.income) filter (where x.now), 0) as income_change,
       coalesce(sum(x.settlement_amount) filter (where x.now), 0) as tiktok_net_now,
       coalesce(sum(x.settlement_amount) filter (where x.after), 0) as tiktok_net_after,
       case when public.current_user_role() is not null
            then (public.tiktok_settlement_totals(2026, p.m, (select store_id from store))->>'income')::numeric end as app_income_now
  from (values (8), (9)) p(m)
  cross join lateral public.tiktok_settlement_period(2026, p.m) per
  cross join lateral public.tiktok_settlement_period_range(2026, p.m) rng
  left join money x on x.settled_time >= rng.start_at and x.settled_time < rng.end_at_exclusive
 group by p.m, per.start_date, per.end_date
 order by p.m;

rollback;
