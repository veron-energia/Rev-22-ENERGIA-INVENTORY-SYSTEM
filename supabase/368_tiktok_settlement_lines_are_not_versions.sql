-- 368_tiktok_settlement_lines_are_not_versions.sql
--
-- WHAT WAS WRONG (TikTok Payouts against the app's Total Income, 29 Sep 2026)
--
--  1. TikTok's income export has ONE ROW PER ORDER LINE (item). The row repeats
--     the Order/Adjustment ID and carries no line id, and two identical rows
--     are two identical items, both paid. Staging took the order as the unit:
--     (a) a repeated identical row in one file was a "Duplicate Row" and was
--         excluded, so a real line was lost;
--     (b) every row was compared with ONE current row of its order (the
--         highest version, an arbitrary pick among lines), so re-importing an
--         overlapping file made a second line with other amounts an "Updated"
--         row, and confirming it took the order's OTHER line out of the
--         totals. On 29 Sep 2026 two September orders lost S$100.90 and
--         S$137.45 this way (a separate repair puts them back).
--  2. A file is compared with the lines counted when it is staged, and it is
--     confirmed later. Confirmation counted its rows as staged even when
--     another file had changed their orders in between: two files staged
--     before either was confirmed counted the lines they share twice, and two
--     files restating one line each replaced it, so both restatements
--     counted. Two confirmations of one store could also run at once, each
--     blind to the lines the other was counting.
--  3. Settlement rows left unticked at confirmation (the rule: only matched
--     orders and platform finance rows are pre-ticked) counted nowhere and
--     could never be taken in: S$450.25 settled on 1-3 Aug 2026 sat in two
--     confirmed files, excluded, and no screen said so.
--
-- WHAT THIS CHANGES (as the owner decided, 29 Sep 2026)
--
--   1. stage_tiktok_settlement: every row of a file is a line. A file's rows
--      for an order are matched against the order's current confirmed lines in
--      the store as a multiset: a row is "Already Imported" when an identical
--      current line (every field compared as before) is not yet claimed by an
--      earlier row of the file. A row left over is "Updated — Requires
--      Confirmation" only when it pairs one to one with a leftover current
--      line of the same order settled at the same moment (TikTok restating
--      that line); anything else is a new line (Matched / Pending Order / No
--      Match Needed as before). It compares under the same store-wide lock
--      confirmation and inclusion take, so it never sees half of one.
--   2. confirm_tiktok_settlement_batch:
--      - first locks every settlement batch of the store, as
--        include_tiktok_settlement_rows does, so one store's lines are
--        counted by one confirmation or inclusion at a time;
--      - refuses the whole file, which is then deleted and staged again, when
--        a row it would count is out of date: another batch has counted a
--        line of the row's order (confirmed or included) since this file was
--        staged, or the row is an update of a line that no longer counts;
--      - otherwise, a selected new row identical to a current line of another
--        batch that this file has not claimed (a line counted again without
--        being confirmed since, as a repair does) is skipped as already
--        imported, claiming that line. It is counted in "skipped" and in a new
--        "already_imported" count.
--   3. Left-out lines: a line staged in a confirmed, not deleted batch as one
--      to count (new or updated), never confirmed, not counted since, and not
--      restated by a confirmed file uploaded later (one that holds rows of its
--      order settled at the same moment, none of them identical to it); an
--      update only while the line it restates still counts. Per identical
--      line, the most of it any such file holds, less the identical current
--      lines, floored at 0. Counting a left-out line changes the totals by its
--      settlement, or, for an update, by the difference from the line it
--      replaces (its net change).
--        tiktok_left_out_settlement(store, from, to) lists them by Singapore
--          settled date (one row per line left out, a row of the latest file),
--          with the settlement an update replaces and the net change;
--        include_tiktok_settlement_rows(ids, reason), for Owners and Managers,
--          counts them under the store lock, re-checking each against the
--          lines already counted, refusing an update whose line another
--          batch has replaced, and refusing a row whose file is out of date
--          (another file has counted a line of its order since it was
--          uploaded: that file is uploaded again, and the row stays listed
--          until then); its "settlement" is the net change;
--        tiktok_settlement_totals adds left_out_count and left_out_settlement
--          (the net change) for the period. The pre-tick rule at confirmation
--          is unchanged.
--
-- NOT CHANGED: parsing, "Invalid Row", order matching, reconciliation and the
-- audit rows of staging; every other step, key and count of confirmation (a
-- file that is not out of date confirms as before); every other key of
-- tiktok_settlement_totals; the rows already stored.
--
-- SAFETY: each patched function is guarded by the md5 of its production version
-- (29 Sep 2026) and by anchors that must occur exactly once; a function already
-- carrying "368:" is left alone. The rule that finds left-out lines is internal:
-- no client role can call it.

set lock_timeout = '5s';

-- ── 1. staging: a file's rows are lines ────────────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a_dup text; a_from text; a_to text; a_after text; a_ins text; p1 int; p2 int;
begin
  d := pg_get_functiondef('public.stage_tiktok_settlement(uuid,text,text,jsonb)'::regprocedure);
  if position('368:' in d) > 0 then raise notice '368: stage_tiktok_settlement already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'b93b703cf41a5859e18559158eaf6a8b' then
    raise exception '368: stage_tiktok_settlement is not the version this was tested against (md5 %)', v_md5; end if;
  a_dup := $a$    -- Duplicate inside THIS file. An order id ALONE is not enough: TikTok
    -- can settle one order across two lines (an order payment plus a later
    -- adjustment, or two instalments), and rejecting the second lost real money.
    -- A row counts as a duplicate only when it repeats the same order with the
    -- same type, related order AND amount.
    v_dup := v_status is null and exists (select 1 from public.tiktok_settlement_rows r
              where r.batch_id = v_batch
                and r.order_id = v_oaid
                and coalesce(r.transaction_type, '') = coalesce(v_type, '')
                and r.related_order_id is not distinct from v_related
                and coalesce(r.settlement_amount, 0) = coalesce(v_settle, 0));
    if v_dup then v_status := 'Duplicate Row'; end if;
$a$;
  -- The comparison with the order's one current row, from its comment to the
  -- end of the new-row branch.
  a_from := $a$      -- Compare against the CURRENT confirmed version of this transaction.
$a$;
  a_to := $a$                         else 'New — Pending Order' end;
      end if;
$a$;
  a_after := $a$  end loop;

  update public.tiktok_import_batches set row_count = v_no where id = v_batch;
$a$;
  a_ins := $a$  insert into public.tiktok_import_batches (store_id, file_kind, file_name, sheet_name, uploaded_by)
$a$;
  n := (length(d) - length(replace(d, a_ins, ''))) / length(a_ins);
  if n <> 1 then raise exception '368: stage_tiktok_settlement batch anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a_dup, ''))) / length(a_dup);
  if n <> 1 then raise exception '368: stage_tiktok_settlement duplicate anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a_from, ''))) / length(a_from);
  if n <> 1 then raise exception '368: stage_tiktok_settlement comparison anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a_to, ''))) / length(a_to);
  if n <> 1 then raise exception '368: stage_tiktok_settlement new-row anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a_after, ''))) / length(a_after);
  if n <> 1 then raise exception '368: stage_tiktok_settlement loop-end anchor found % times', n; end if;

  d := replace(d, a_ins, $r$  -- 368: a file is compared with what is counted while no confirmation or
  -- inclusion of this store is under way: the same store-wide lock, taken in
  -- the same order. Otherwise a confirmation committing mid-way could leave
  -- this file compared with lines it never saw, stamped as staged after them.
  perform 1 from public.tiktok_import_batches b
   where b.file_kind = 'settlement' and b.store_id = p_store_id
   order by b.id
     for update;
$r$ || a_ins);
  d := replace(d, a_dup, $r$    -- 368: no row of a file duplicates another. The export has one row per
    -- order line (item), repeating the Order/Adjustment ID with no line id, so
    -- two identical rows are two identical items, both paid.
$r$);
  p1 := position(a_from in d);
  p2 := position(a_to in d);
  if p2 < p1 then raise exception '368: stage_tiktok_settlement anchors out of order'; end if;
  d := substr(d, 1, p1 - 1) || $r$      -- 368: a row is one settlement LINE. It is already imported when the
      -- order has an identical current line (every compared field equal)
      -- that no earlier row of this file has claimed: lines compare as a
      -- multiset, claimed in file order, and the claim is the row's
      -- previous_row_id. A row left over is new here; once every row is in,
      -- a leftover row restating a leftover line of its order becomes an
      -- update of it (below the loop).
      select c.* into v_cur from public.tiktok_settlement_rows c
       where c.store_id = p_store_id and c.order_id = v_oaid and c.is_current and c.confirmed
         and c.transaction_type   is not distinct from v_type
         and c.settlement_amount  is not distinct from v_settle
         and c.revenue_amount     is not distinct from v_rev
         and c.fee_amount         is not distinct from v_fees
         and c.adjustment_amount  is not distinct from v_adj
         and c.refund_amount      is not distinct from v_ref
         and c.currency           is not distinct from v_curr
         and c.related_order_id   is not distinct from v_related
         and c.order_created_time is not distinct from v_created
         and c.settled_time       is not distinct from v_settled
         and not exists (select 1 from public.tiktok_settlement_rows f
                          where f.batch_id = v_batch and f.previous_row_id = c.id)
       order by c.confirmed_at, c.row_no, c.id
       limit 1;
      if found then
        v_prev_id := v_cur.id; v_prev_ver := v_cur.version_no;
        v_status := 'Already Imported';
      else
        v_status := case when v_match is not null then 'New — Matched'
                         when v_class = 'finance' then 'New — No Match Needed'
                         else 'New — Pending Order' end;
      end if;
$r$ || substr(d, p2 + length(a_to));
  d := replace(d, a_after, $r$  end loop;

  -- 368: a restated settlement. A row of this file left new, whose order has
  -- a current line no row of the file claimed, settled at the same moment, is
  -- TikTok restating that line: it becomes an update of it, paired one to one
  -- (the file's rows in file order, the order's lines in the order they were
  -- confirmed). Any other new row is a line of its own: another item, or an
  -- instalment settled at another time.
  with leftover_rows as (
    select r.*, row_number() over (partition by r.order_id, r.settled_time order by r.row_no) as k
      from public.tiktok_settlement_rows r
     where r.batch_id = v_batch and r.staging_status like 'New — %'),
  leftover_lines as (
    select c.*, row_number() over (partition by c.order_id, c.settled_time
                                   order by c.confirmed_at, c.row_no, c.id) as k
      from public.tiktok_settlement_rows c
     where c.store_id = p_store_id and c.is_current and c.confirmed
       and c.order_id in (select f.order_id from leftover_rows f)
       and not exists (select 1 from public.tiktok_settlement_rows x
                        where x.batch_id = v_batch and x.previous_row_id = c.id))
  update public.tiktok_settlement_rows r
     set staging_status = 'Updated — Requires Confirmation',
         version_no = c.version_no + 1,
         previous_row_id = c.id,
         value_diff = (
           select coalesce(jsonb_object_agg(v.field, jsonb_build_object('old', v.o, 'new', v.n))
                           filter (where v.o is distinct from v.n), '{}'::jsonb)
             from (values
               ('transaction_type',    to_jsonb(c.transaction_type),  to_jsonb(f.transaction_type)),
               ('settlement_amount',   to_jsonb(c.settlement_amount), to_jsonb(f.settlement_amount)),
               ('revenue_amount',      to_jsonb(c.revenue_amount),    to_jsonb(f.revenue_amount)),
               ('fee_amount',          to_jsonb(c.fee_amount),        to_jsonb(f.fee_amount)),
               ('adjustment_amount',   to_jsonb(c.adjustment_amount), to_jsonb(f.adjustment_amount)),
               ('refund_amount',       to_jsonb(c.refund_amount),     to_jsonb(f.refund_amount)),
               ('currency',            to_jsonb(c.currency),          to_jsonb(f.currency)),
               ('related_order_id',    to_jsonb(c.related_order_id),  to_jsonb(f.related_order_id)),
               ('order_created_time',  to_jsonb(c.order_created_time),to_jsonb(f.order_created_time)),
               ('settled_time',        to_jsonb(c.settled_time),      to_jsonb(f.settled_time))
             ) as v(field, o, n))
    from leftover_rows f
    join leftover_lines c on c.order_id = f.order_id
                         and c.settled_time is not distinct from f.settled_time and c.k = f.k
   where r.id = f.id;

  update public.tiktok_import_batches set row_count = v_no where id = v_batch;
$r$);
  execute d;
end $mig$;

-- ── 2. confirmation: a file out of date is staged again ────────────────────
do $mig$
declare d text; n int; v_md5 text; a_lock text; a_decl text; a_step text; a_keys text;
begin
  d := pg_get_functiondef('public.confirm_tiktok_settlement_batch(uuid,jsonb)'::regprocedure);
  if position('368:' in d) > 0 then raise notice '368: confirm_tiktok_settlement_batch already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '4eef8f3ece142daa994337d558cf07c3' then
    raise exception '368: confirm_tiktok_settlement_batch is not the version this was tested against (md5 %)', v_md5; end if;
  a_lock := $a$  select * into v_b from public.tiktok_import_batches where id = p_batch_id and deleted_at is null for update;
$a$;
  a_decl := $a$  v_pending integer := 0; v_unrec integer := 0;
begin
$a$;
  a_step := $a$    -- The previous version steps aside; the new one becomes current.
$a$;
  a_keys := $a$'unreconciled', v_unrec)$a$;
  n := (length(d) - length(replace(d, a_lock, ''))) / length(a_lock);
  if n <> 1 then raise exception '368: confirm_tiktok_settlement_batch lock anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a_decl, ''))) / length(a_decl);
  if n <> 1 then raise exception '368: confirm_tiktok_settlement_batch declare anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a_step, ''))) / length(a_step);
  if n <> 1 then raise exception '368: confirm_tiktok_settlement_batch step anchor found % times', n; end if;
  -- the audit row and the result
  n := (length(d) - length(replace(d, a_keys, ''))) / length(a_keys);
  if n <> 2 then raise exception '368: confirm_tiktok_settlement_batch result anchor found % times', n; end if;
  d := replace(d, a_lock, $r$  -- 368: one store's lines are counted by one confirmation or inclusion at
  -- a time. Every settlement batch of the store is locked first, in the order
  -- include_tiktok_settlement_rows locks them, so two of them cannot deadlock
  -- or count a line each without seeing the other's.
  perform 1 from public.tiktok_import_batches b
   where b.file_kind = 'settlement'
     and b.store_id = (select x.store_id from public.tiktok_import_batches x where x.id = p_batch_id)
   order by b.id
     for update;
$r$ || a_lock);
  d := replace(d, a_decl, $r$  v_pending integer := 0; v_unrec integer := 0;
  v_line record; v_already integer := 0;
begin
$r$);
  d := replace(d, a_step, $r$    -- 368: the file was compared with the lines counted when it was staged.
    -- If another batch has counted a line of this row's order since (confirmed
    -- or included it), or the line this row updates no longer counts, that
    -- comparison is out of date: the whole file is refused, to be staged again.
    if exists (select 1 from public.tiktok_settlement_rows c
                where c.store_id = v_row.store_id and c.order_id = v_row.order_id
                  and c.is_current and c.confirmed and c.batch_id <> p_batch_id
                  and c.confirmed_at > v_b.uploaded_at) then
      raise exception 'Another file changed order % (row % of %) after this file was staged. Delete this staged file and upload it again, so it is compared with what is counted now',
        v_row.order_id, v_row.row_no, v_b.file_name;
    end if;
    if v_row.staging_status = 'Updated — Requires Confirmation'
       and not exists (select 1 from public.tiktok_settlement_rows p
                        where p.id = v_row.previous_row_id and p.is_current and p.confirmed) then
      raise exception 'Another file replaced the line that row % of % updates (order %) after this file was staged. Delete this staged file and upload it again, so it is compared with what is counted now',
        v_row.row_no, v_b.file_name, v_row.order_id;
    end if;

    -- 368: a line counted again since this file was staged without being
    -- confirmed since (a repair making an earlier line current) is counted
    -- already. Lines compare as a multiset: a new row identical to a current
    -- line of its order (every field staging compares) that this file has not
    -- claimed claims it, as staging would have, and is skipped as imported.
    if v_row.staging_status like 'New — %' then
      select c.id, c.version_no into v_line
        from public.tiktok_settlement_rows c
       where c.store_id = v_row.store_id and c.order_id = v_row.order_id
         and c.is_current and c.confirmed and c.batch_id <> p_batch_id
         and c.transaction_type   is not distinct from v_row.transaction_type
         and c.settlement_amount  is not distinct from v_row.settlement_amount
         and c.revenue_amount     is not distinct from v_row.revenue_amount
         and c.fee_amount         is not distinct from v_row.fee_amount
         and c.adjustment_amount  is not distinct from v_row.adjustment_amount
         and c.refund_amount      is not distinct from v_row.refund_amount
         and c.currency           is not distinct from v_row.currency
         and c.related_order_id   is not distinct from v_row.related_order_id
         and c.order_created_time is not distinct from v_row.order_created_time
         and c.settled_time       is not distinct from v_row.settled_time
         and not exists (select 1 from public.tiktok_settlement_rows x
                          where x.batch_id = p_batch_id and x.previous_row_id = c.id)
       order by c.confirmed_at, c.row_no, c.id
       limit 1;
      if found then
        update public.tiktok_settlement_rows
           set staging_status = 'Already Imported', excluded = true,
               previous_row_id = v_line.id, version_no = v_line.version_no + 1
         where id = v_row.id;
        v_skipped := v_skipped + 1; v_already := v_already + 1;
        continue;
      end if;
    end if;

    -- The previous version steps aside; the new one becomes current.
$r$);
  d := replace(d, a_keys, $r$'unreconciled', v_unrec, 'already_imported', v_already)$r$);
  execute d;
end $mig$;

-- ── 3. left-out lines ──────────────────────────────────────────────────────
-- Internal: every row that could count a left-out line, with how many of its
-- line are left out (left_out) and its place among the rows of that line, the
-- latest file first (k). The rows k <= left_out stand for the lines left out.
create or replace function public.tiktok_settlement_left_out_rows(p_store_id uuid default null)
returns table(id uuid, left_out integer, k integer)
language sql stable security definer set search_path to 'public' as $f$
  -- 368: a line left out at confirmation was staged in a confirmed, not
  -- deleted batch as one to count (new, or an update), was never confirmed,
  -- and is not counted since. A file row is a line (TikTok exports one row per
  -- item), so identical rows are counted: per identical line, the most of it
  -- any such file holds (its rows staged to count or already imported) less
  -- the identical current lines, floored at 0. An unticked update can be taken
  -- only while the line it restates is still current. A line TikTok has
  -- restated since is not left out: a confirmed file uploaded later holds rows
  -- of its order settled at the same moment, and none of them is this line
  -- (an export holds every line settled in its range).
  with cand as (
    select r.id, r.batch_id, r.row_no, b.uploaded_at, r.store_id, r.order_id, r.transaction_type,
           r.related_order_id, r.settlement_amount, r.revenue_amount, r.fee_amount,
           r.adjustment_amount, r.refund_amount, r.currency, r.settled_time
      from public.tiktok_settlement_rows r
      join public.tiktok_import_batches b on b.id = r.batch_id
     where b.file_kind = 'settlement' and b.status = 'confirmed' and b.deleted_at is null
       and not r.confirmed
       and r.staging_status in ('New — Matched', 'New — Pending Order', 'New — No Match Needed',
                                'Updated — Requires Confirmation')
       and (p_store_id is null or r.store_id = p_store_id)
       and (r.staging_status <> 'Updated — Requires Confirmation'
            or exists (select 1 from public.tiktok_settlement_rows p
                        where p.id = r.previous_row_id and p.is_current and p.confirmed))
       and not exists (
         select 1 from public.tiktok_import_batches lb
          where lb.store_id = r.store_id and lb.file_kind = 'settlement' and lb.status = 'confirmed'
            and lb.deleted_at is null and lb.uploaded_at > b.uploaded_at
            and exists (select 1 from public.tiktok_settlement_rows s
                         where s.batch_id = lb.id and s.order_id = r.order_id
                           and s.settled_time is not distinct from r.settled_time
                           and s.staging_status is distinct from 'Invalid Row')
            and not exists (select 1 from public.tiktok_settlement_rows s
                             where s.batch_id = lb.id and s.order_id = r.order_id
                               and s.staging_status is distinct from 'Invalid Row'
                               and (s.transaction_type, s.related_order_id, s.settlement_amount, s.revenue_amount,
                                    s.fee_amount, s.adjustment_amount, s.refund_amount, s.currency, s.settled_time)
                                   is not distinct from
                                   (r.transaction_type, r.related_order_id, r.settlement_amount, r.revenue_amount,
                                    r.fee_amount, r.adjustment_amount, r.refund_amount, r.currency, r.settled_time)))
  )
  select c.id,
         greatest(0,
           (select max(z.n) from (
              select count(*)::int as n
                from public.tiktok_settlement_rows s
               where s.store_id = c.store_id and s.order_id = c.order_id
                 and s.batch_id in (select c2.batch_id from cand c2
                                     where (c2.store_id, c2.order_id, c2.transaction_type, c2.related_order_id,
                                            c2.settlement_amount, c2.revenue_amount, c2.fee_amount,
                                            c2.adjustment_amount, c2.refund_amount, c2.currency, c2.settled_time)
                                           is not distinct from
                                           (c.store_id, c.order_id, c.transaction_type, c.related_order_id,
                                            c.settlement_amount, c.revenue_amount, c.fee_amount,
                                            c.adjustment_amount, c.refund_amount, c.currency, c.settled_time))
                 and s.staging_status in ('New — Matched', 'New — Pending Order', 'New — No Match Needed',
                                          'Updated — Requires Confirmation', 'Already Imported')
                 and (s.transaction_type, s.related_order_id, s.settlement_amount, s.revenue_amount,
                      s.fee_amount, s.adjustment_amount, s.refund_amount, s.currency, s.settled_time)
                     is not distinct from
                     (c.transaction_type, c.related_order_id, c.settlement_amount, c.revenue_amount,
                      c.fee_amount, c.adjustment_amount, c.refund_amount, c.currency, c.settled_time)
               group by s.batch_id) z)
           - (select count(*)::int
                from public.tiktok_settlement_rows x
               where x.store_id = c.store_id and x.order_id = c.order_id and x.is_current and x.confirmed
                 and (x.transaction_type, x.related_order_id, x.settlement_amount, x.revenue_amount,
                      x.fee_amount, x.adjustment_amount, x.refund_amount, x.currency, x.settled_time)
                     is not distinct from
                     (c.transaction_type, c.related_order_id, c.settlement_amount, c.revenue_amount,
                      c.fee_amount, c.adjustment_amount, c.refund_amount, c.currency, c.settled_time))),
         (row_number() over (partition by c.store_id, c.order_id, c.transaction_type, c.related_order_id,
                                          c.settlement_amount, c.revenue_amount, c.fee_amount,
                                          c.adjustment_amount, c.refund_amount, c.currency, c.settled_time
                             order by c.uploaded_at desc, c.row_no, c.id))::int
    from cand c
$f$;

-- The left-out lines of a store (every visible store when none is given), by
-- the Singapore date TikTok settled them, both ends inclusive. An update also
-- gives the settlement of the line it replaces (replaces_settlement); either
-- way net_change is what counting the line changes the totals by. Dropped
-- first so that a database holding an earlier draft of it takes these columns.
drop function if exists public.tiktok_left_out_settlement(uuid, date, date);
create or replace function public.tiktok_left_out_settlement(p_store_id uuid, p_from date, p_to date)
returns table(row_id uuid, batch_id uuid, file_name text, store_id uuid, order_id text,
              transaction_type text, settled_time timestamptz, settled_date date,
              settlement_amount numeric, revenue_amount numeric, fee_amount numeric,
              adjustment_amount numeric, currency text, match_status text, staging_status text,
              replaces_settlement numeric, net_change numeric)
language plpgsql stable security definer set search_path to 'public' as $f$
begin
  -- 368: who may see a store's TikTok import may see what it left out.
  if p_store_id is not null then perform public.tiktok_access_check(p_store_id);
  elsif public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  return query
    select r.id, r.batch_id, b.file_name, r.store_id, r.order_id, r.transaction_type, r.settled_time,
           (r.settled_time at time zone 'Asia/Singapore')::date,
           r.settlement_amount, r.revenue_amount, r.fee_amount, r.adjustment_amount, r.currency,
           r.match_status, r.staging_status,
           p.settlement_amount, r.settlement_amount - coalesce(p.settlement_amount, 0)
      from public.tiktok_settlement_left_out_rows(p_store_id) l
      join public.tiktok_settlement_rows r on r.id = l.id
      join public.tiktok_import_batches b on b.id = r.batch_id
      left join public.tiktok_settlement_rows p
        on p.id = r.previous_row_id and r.staging_status = 'Updated — Requires Confirmation'
     where l.k <= l.left_out
       and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
            or public.user_has_store_access(r.store_id))
       and (p_from is null or (r.settled_time at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to is null or (r.settled_time at time zone 'Asia/Singapore')::date <= p_to)
     order by r.settled_time, r.order_id, b.uploaded_at desc, r.row_no;
end $f$;

-- Count left-out lines, as confirming them would have. Owners and Managers.
create or replace function public.include_tiktok_settlement_rows(p_row_ids uuid[], p_reason text)
returns jsonb
language plpgsql security definer set search_path to 'public' as $f$
declare
  v_id uuid; v_row public.tiktok_settlement_rows%rowtype; v_file text; v_replaced numeric;
  v_included integer := 0; v_updates integer := 0; v_sum numeric := 0;
begin
  if coalesce(public.current_user_role()::text, '') not in ('owner','manager') then
    raise exception 'Only Owners and Managers can include left-out settlement lines'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'Give a reason for including these settlement lines'; end if;
  if p_row_ids is null or cardinality(p_row_ids) = 0 then raise exception 'No rows to include'; end if;
  if (select count(distinct x) from unnest(p_row_ids) x) <> cardinality(p_row_ids) then
    raise exception 'A row is listed more than once'; end if;

  -- 368: one store's lines are counted by one confirmation or inclusion at a
  -- time (confirmation takes the same lock, in the same order), so a line
  -- cannot be counted twice.
  perform 1 from public.tiktok_import_batches b
   where b.file_kind = 'settlement'
     and b.store_id in (select r.store_id from public.tiktok_settlement_rows r where r.id = any(p_row_ids))
   order by b.id
     for update;

  foreach v_id in array p_row_ids loop
    select * into v_row from public.tiktok_settlement_rows where id = v_id for update;
    if not found then raise exception 'Settlement row not found'; end if;
    perform public.tiktok_access_check(v_row.store_id);
    select b.file_name into v_file from public.tiktok_import_batches b where b.id = v_row.batch_id;
    -- An update of a line that no longer counts (another batch replaced it)
    -- would count a second version of that line.
    if v_row.staging_status = 'Updated — Requires Confirmation'
       and not exists (select 1 from public.tiktok_settlement_rows p
                        where p.id = v_row.previous_row_id and p.is_current and p.confirmed) then
      raise exception 'Row % of % updates a line that another file has replaced since; it cannot be included',
        v_row.row_no, coalesce(v_file, 'its file'); end if;
    -- The row's file was compared with the lines counted when it was staged.
    -- If another file has counted a line of this order since, that comparison
    -- is out of date (the row may restate a line now counted): the file is to
    -- be uploaded again, as confirmation requires. The row stays listed as
    -- left out until then, so the money is not silently dropped.
    if exists (select 1 from public.tiktok_settlement_rows c
                where c.store_id = v_row.store_id and c.order_id = v_row.order_id
                  and c.is_current and c.confirmed and c.batch_id <> v_row.batch_id
                  and c.confirmed_at > (select b.uploaded_at from public.tiktok_import_batches b
                                         where b.id = v_row.batch_id)) then
      raise exception 'Another file has counted a line of order % since % was uploaded. Upload that file again, so its rows are compared with what is counted now',
        v_row.order_id, coalesce(v_file, 'its file'); end if;
    -- Re-checked for every row, after the ones before it are counted.
    if coalesce((select l.left_out from public.tiktok_settlement_left_out_rows(v_row.store_id) l
                  where l.id = v_id), 0) < 1 then
      raise exception 'Row % of % is not a left-out settlement line: it is counted already, or it was never staged to count in a confirmed file',
        v_row.row_no, coalesce(v_file, 'its file'); end if;

    -- An update replaces the line it restates, as confirming it would have,
    -- and changes the totals by the difference.
    v_replaced := null;
    if v_row.staging_status = 'Updated — Requires Confirmation' then
      select p.settlement_amount into v_replaced from public.tiktok_settlement_rows p where p.id = v_row.previous_row_id;
      update public.tiktok_settlement_rows set is_current = false where id = v_row.previous_row_id;
      v_updates := v_updates + 1;
    end if;
    update public.tiktok_settlement_rows
       set confirmed = true, confirmed_at = now(), is_current = true, excluded = false
     where id = v_id;

    perform public.write_audit_ex('tiktok_settlement_rows', v_id, 'tiktok_settlement_included',
      jsonb_build_object('confirmed', false, 'is_current', false, 'excluded', v_row.excluded),
      jsonb_build_object('file', v_file, 'row_no', v_row.row_no, 'order_id', v_row.order_id,
                         'staging_status', v_row.staging_status, 'settlement_amount', v_row.settlement_amount,
                         'settled_time', v_row.settled_time,
                         'replaces_row_id', case when v_row.staging_status = 'Updated — Requires Confirmation'
                                                 then v_row.previous_row_id end),
      'tiktok_import', p_reason, v_row.store_id);
    v_included := v_included + 1;
    v_sum := v_sum + coalesce(v_row.settlement_amount, 0) - coalesce(v_replaced, 0);
  end loop;

  return jsonb_build_object('success', true, 'included', v_included, 'skipped', 0,
                            'versioned_updates', v_updates, 'settlement', round(v_sum, 2));
end $f$;

-- ── 4. the month's totals say what was left out ────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a_cte text; a_keys text;
begin
  d := pg_get_functiondef('public.tiktok_settlement_totals(integer,integer,uuid)'::regprocedure);
  if position('368:' in d) > 0 then raise notice '368: tiktok_settlement_totals already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'aab0f7ca73358ff78eac43e00428a0fd' then
    raise exception '368: tiktok_settlement_totals is not the version this was tested against (md5 %)', v_md5; end if;
  a_cte := $a$          where settled_time is null
       )
  select jsonb_build_object(
$a$;
  a_keys := $a$    'needs_review', (a.unknown_count > 0 or u.n > 0 or a.currency_count > 1)
  ) from agg a, undated u
$a$;
  n := (length(d) - length(replace(d, a_cte, ''))) / length(a_cte);
  if n <> 1 then raise exception '368: tiktok_settlement_totals undated anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a_keys, ''))) / length(a_keys);
  if n <> 1 then raise exception '368: tiktok_settlement_totals result anchor found % times', n; end if;
  d := replace(d, a_cte, $r$          where settled_time is null
       ),
       -- 368: settled money of the period left out at confirmation (unticked
       -- rows of confirmed files not counted since), as counting it would
       -- change the totals: a new line by its settlement, an update by the
       -- difference from the line it replaces.
       left_out as (
         select count(*)::int as n,
                coalesce(sum(r.settlement_amount - coalesce(p.settlement_amount, 0)), 0) as amount
           from public.tiktok_settlement_left_out_rows(p_store_id) l
           join public.tiktok_settlement_rows r on r.id = l.id
           left join public.tiktok_settlement_rows p
             on p.id = r.previous_row_id and r.staging_status = 'Updated — Requires Confirmation'
           cross join rng
          where l.k <= l.left_out
            and r.settled_time >= rng.start_at
            and r.settled_time <  rng.end_at_exclusive
            and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
                 or public.user_has_store_access(r.store_id))
       )
  select jsonb_build_object(
$r$);
  d := replace(d, a_keys, $r$    'needs_review', (a.unknown_count > 0 or u.n > 0 or a.currency_count > 1),
    -- 368: what the period left out, so the page can say so.
    'left_out_count', lo.n,
    'left_out_settlement', round(lo.amount, 2)
  ) from agg a, undated u, left_out lo
$r$);
  execute d;
end $mig$;

-- ── 5. who may call what (339: functions are not endpoints by default) ──────
revoke all on function public.tiktok_settlement_left_out_rows(uuid) from public, anon, authenticated;
grant execute on function public.tiktok_settlement_left_out_rows(uuid) to service_role;

revoke all on function public.tiktok_left_out_settlement(uuid,date,date) from public, anon;
grant execute on function public.tiktok_left_out_settlement(uuid,date,date) to authenticated, service_role;
revoke all on function public.include_tiktok_settlement_rows(uuid[],text) from public, anon;
grant execute on function public.include_tiktok_settlement_rows(uuid[],text) to authenticated, service_role;

notify pgrst, 'reload schema';
