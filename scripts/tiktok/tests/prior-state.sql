-- =====================================================================
-- The database as migration 210 finds it.
--
-- This exists because of a bug it would have caught. Migration 210 was tested
-- against a database where the TikTok report functions had never been created,
-- so `create or replace` had nothing to replace and every run was clean. On the
-- real database the functions already exist with a different row type, and
-- Postgres refuses:
--
--     ERROR: 42P13: cannot change return type of existing function
--     HINT:  Use DROP FUNCTION report_tiktok_settlement(uuid,date,date) first.
--
-- A migration that amends earlier migrations has to be tested on top of them.
-- The three report functions below are copied VERBATIM from migrations 66 and
-- 67 — not paraphrased — because the row type is the whole point: change one
-- and the test stops reproducing production.
--
-- The table and helpers are deliberately reduced. They carry the columns and
-- behaviour 210 depends on and nothing else; the disposable database has no
-- profiles, batches or RLS. Two conscious deviations from production:
--
--   * batch_id is nullable here (production makes it a not-null FK to
--     tiktok_import_batches), so a test can insert a row without a batch.
--   * current_user_role() and user_has_store_access() read session settings
--     rather than the profile of a real JWT, which is what lets the tests drive
--     role and store permission directly.
--
-- Neither deviation touches the report row types or the settled-date logic.
-- Safe to run repeatedly.
-- =====================================================================

set check_function_bodies = off;

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null
);

create table if not exists public.tiktok_settlement_rows (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid,
  store_id uuid not null references public.stores(id),
  row_no integer not null,
  order_id text,
  adjustment_id text,
  matched_order_id text,
  match_status text,
  txn_class text,
  transaction_type text,
  settlement_amount numeric(12,2),
  fee_amount numeric(12,2),
  revenue_amount numeric(12,2),
  adjustment_amount numeric(12,2),
  refund_amount numeric(12,2),
  currency text,
  settled_time timestamptz,
  order_created_time timestamptz,
  excluded boolean not null default false,
  confirmed boolean not null default false,
  is_current boolean not null default true,
  reconciled boolean,
  version_no integer not null default 1,
  raw jsonb
);

-- Role and store permission, driven by session settings so a test can be any
-- role without inventing a JWT. Signature and return type match production.
--
-- The database default is owner, so a query written without a role reads
-- everything and a permission test has to opt in to being restricted. The
-- alternative — defaulting to no access — makes every unrelated test fail with
-- zero rows and hides the real assertion, which is what it did here first.
-- sqlAs() overrides both settings for the session it runs in.
do $$ begin
  execute format('alter database %I set test.role = %L', current_database(), 'owner');
end $$;

create or replace function public.current_user_role()
returns text language sql stable as $fn$
  select nullif(current_setting('test.role', true), '')
$fn$;

create or replace function public.user_has_store_access(p_store_id uuid)
returns boolean language sql stable as $fn$
  select coalesce(
    current_setting('test.store_access', true) = 'all'
    or p_store_id::text = any (string_to_array(coalesce(current_setting('test.store_access', true), ''), ',')),
    false)
$fn$;

-- Rewind. If 210 has already run in this database its versions are installed
-- with a different row type, so they have to go before the old shapes can be
-- restored. Production never rewinds; this exists so the test can start from
-- the pre-210 state on every run, including the second one.
drop function if exists public.report_tiktok_settlement(uuid, date, date);
drop function if exists public.report_tiktok_settlement_daily(uuid, date, date);
drop function if exists public.report_tiktok_settlement_daily(uuid, date, date, text);
drop function if exists public.report_tiktok_settlement_by_store(date, date);

-- --- verbatim from migrations 66 and 67 -------------------------------
create or replace function public.report_tiktok_settlement(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (
  row_id uuid, store_name text, financial_date date,
  order_adjustment_id text, txn_class text, transaction_type text,
  matched_order_id text, match_status text,
  settlement_amount numeric, revenue_amount numeric, fee_amount numeric,
  adjustment_amount numeric, refund_amount numeric, currency text,
  reconciled boolean, version_no integer
) language sql stable security definer set search_path = public as $$
  select r.id, s.name,
         coalesce(r.order_created_time at time zone 'Asia/Singapore',
                  r.settled_time at time zone 'Asia/Singapore')::date,
         r.order_id, r.txn_class, r.transaction_type,
         r.matched_order_id, r.match_status,
         r.settlement_amount, r.revenue_amount, r.fee_amount,
         r.adjustment_amount, r.refund_amount, r.currency,
         r.reconciled, r.version_no
    from public.tiktok_settlement_rows r
    join public.stores s on s.id = r.store_id
   where r.confirmed and r.is_current
     and (p_store_id is null or r.store_id = p_store_id)
     and (p_from is null or coalesce(r.order_created_time at time zone 'Asia/Singapore',
                                     r.settled_time at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to is null or coalesce(r.order_created_time at time zone 'Asia/Singapore',
                                   r.settled_time at time zone 'Asia/Singapore')::date <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
   order by 3 desc nulls last, r.order_id
$$;

create or replace function public.report_tiktok_settlement_daily(
  p_store_id uuid default null, p_from date default null, p_to date default null,
  p_basis text default 'created'
) returns table (
  day date, transactions bigint, settlement numeric, revenue numeric, fees numeric
) language sql stable security definer set search_path = public as $$
  select d.day, count(*), coalesce(sum(r.settlement_amount),0),
         coalesce(sum(r.revenue_amount),0), coalesce(sum(r.fee_amount),0)
    from public.tiktok_settlement_rows r
    cross join lateral (select case when p_basis = 'settled'
        then (r.settled_time at time zone 'Asia/Singapore')::date
        else coalesce(r.order_created_time at time zone 'Asia/Singapore',
                      r.settled_time at time zone 'Asia/Singapore')::date end as day) d
   where r.confirmed and r.is_current and d.day is not null
     and (p_store_id is null or r.store_id = p_store_id)
     and (p_from is null or d.day >= p_from) and (p_to is null or d.day <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
   group by d.day order by d.day desc
$$;

create or replace function public.report_tiktok_settlement_by_store(
  p_from date default null, p_to date default null
) returns table (
  store_name text, transactions bigint, settlement numeric, revenue numeric, fees numeric,
  pending_count bigint, unreconciled_count bigint
) language sql stable security definer set search_path = public as $$
  select s.name, count(*), coalesce(sum(r.settlement_amount),0),
         coalesce(sum(r.revenue_amount),0), coalesce(sum(r.fee_amount),0),
         count(*) filter (where r.match_status = 'pending'),
         count(*) filter (where r.reconciled is false)
    from public.tiktok_settlement_rows r
    join public.stores s on s.id = r.store_id
   where r.confirmed and r.is_current
     and (p_from is null or coalesce(r.order_created_time, r.settled_time)::date >= p_from)
     and (p_to is null or coalesce(r.order_created_time, r.settled_time)::date <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
   group by s.name order by 3 desc
$$;
