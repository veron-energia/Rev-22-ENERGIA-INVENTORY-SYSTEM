-- 375_tiktok_bank_payouts.sql
--
-- TIKTOK'S REAL BANK PAYOUTS (asked for on 1 Oct 2026; the owner's rules)
--
--   TikTok's income export has a "Withdrawal records" sheet beside the
--   settled lines: every change to the shop's TikTok balance, by type:
--     Earnings           what a day's settled lines added to the balance
--     GMV Pay Deduction  ads taken from the balance
--     Payments           money paid into the bank (every Wednesday)
--   each with TikTok's Reference ID, the date it was asked for and paid,
--   the amount and its status. The sheet also names the bank account; that
--   is never sent here and never stored.
--
--   1. The sheet is saved with the settlement file it came in
--      (stage_tiktok_settlement_file stages the settled lines exactly as
--      stage_tiktok_settlement does, and the sheet's rows with the file). A
--      record counts once its file is confirmed, and not once the file is
--      deleted; a record that is in several files counts once. A file whose
--      lines were all imported before can still be confirmed for its records
--      alone (the page asks first); tiktok_batch_balance_counts tells the page
--      what a file brought.
--   2. tiktok_bank_payouts(from, to) gives TikTok's payouts paid between two
--      dates (Owners and Managers), for the Xero export: one invoice per
--      payout, for what TikTok paid. Each payout comes with the app's own
--      figure for the week it pays out (the Thursday-to-Wednesday week up to
--      the Wednesday on or before the day it was paid, from
--      tiktok_xero_payouts, 374), so a difference shows. A later file never
--      replaces a payout: TikTok's transferred record is kept from the first
--      file confirmed with it, and any file that disagrees on its amount is
--      named, so the export leaves that payout out. It also lists the finished
--      Wednesdays between the dates with no transferred payout imported whose
--      week the app says pays out, which no imported file reaches, or whose
--      lines were left out at confirmation, and counts payouts with no date.
--
-- Nothing existing is changed.

set lock_timeout = '5s';

do $$ begin
  if to_regprocedure('public.tiktok_xero_payouts(integer,integer)') is null then
    raise exception '375: apply 374 (TikTok payouts for Xero) first'; end if;
end $$;

create table if not exists public.tiktok_balance_records (
  id               uuid primary key default gen_random_uuid(),
  batch_id         uuid not null references public.tiktok_import_batches(id) on delete cascade,
  store_id         uuid not null references public.stores(id),
  row_no           integer not null,
  transaction_type text not null,
  reference_id     text not null,
  request_date     date,
  success_date     date,
  amount           numeric(12,2) not null,
  status           text,
  created_at       timestamptz not null default now(),
  constraint tiktok_balance_records_once unique (batch_id, transaction_type, reference_id)
);
create index if not exists tiktok_balance_records_ref_idx on public.tiktok_balance_records(transaction_type, reference_id);
alter table public.tiktok_balance_records enable row level security;
revoke all on table public.tiktok_balance_records from anon, authenticated;
grant all on table public.tiktok_balance_records to service_role;

-- ── 1. Staging a settlement file with its Withdrawal records ───────────────
-- p_balance_rows: [{transaction_type, reference_id, request_time, amount,
-- status, success_time}], as the sheet has them. Any other key is ignored. A
-- row without a type, a Reference ID or an amount is skipped. Returns the
-- batch, as stage_tiktok_settlement does.
create or replace function public.stage_tiktok_settlement_file(
  p_store_id uuid, p_file_name text, p_sheet_name text, p_rows jsonb, p_balance_rows jsonb)
returns uuid language plpgsql security definer set search_path to 'public' as $f$
declare v_batch uuid; x jsonb; k bigint; v_type text; v_ref text; v_amount numeric;
begin
  -- Who may import, and the settled lines, exactly as before.
  v_batch := public.stage_tiktok_settlement(p_store_id, p_file_name, p_sheet_name, p_rows);
  if jsonb_typeof(p_balance_rows) = 'array' then
    for x, k in select e, n from jsonb_array_elements(p_balance_rows) with ordinality t(e, n) loop
      v_type := nullif(btrim(coalesce(x->>'transaction_type', '')), '');
      v_ref := nullif(btrim(coalesce(x->>'reference_id', '')), '');
      v_amount := public.tiktok_parse_amount(x->>'amount');
      if v_type is null or v_ref is null or v_amount is null then continue; end if;
      insert into public.tiktok_balance_records
        (batch_id, store_id, row_no, transaction_type, reference_id, request_date, success_date, amount, status)
      values (v_batch, p_store_id, k::integer, left(v_type, 80), left(v_ref, 80),
              (public.tiktok_parse_time(x->>'request_time') at time zone 'Asia/Singapore')::date,
              (public.tiktok_parse_time(x->>'success_time') at time zone 'Asia/Singapore')::date,
              round(v_amount, 2), nullif(left(btrim(coalesce(x->>'status', '')), 80), ''))
      on conflict (batch_id, transaction_type, reference_id) do nothing;
    end loop;
  end if;
  return v_batch;
end $f$;

-- What a file brought (for the page, before it is confirmed): whoever may
-- import the store's TikTok files.
create or replace function public.tiktok_batch_balance_counts(p_batch_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare v_store uuid;
begin
  select store_id into v_store from public.tiktok_import_batches where id = p_batch_id;
  if not found then raise exception 'Batch not found'; end if;
  perform public.tiktok_access_check(v_store);
  return (select jsonb_build_object(
            'payouts', count(*) filter (where transaction_type = 'Payments'),
            'others', count(*) filter (where transaction_type <> 'Payments'))
            from public.tiktok_balance_records where batch_id = p_batch_id);
end $f$;

-- ── 2. The payouts, for the Xero export ───────────────────────────────────
create or replace function public.tiktok_bank_payouts(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare v_weeks jsonb := '[]'::jsonb; m record; v_out jsonb; v_today date := public.sg_today();
begin
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active and p.deleted_at is null
                   and p.role in ('owner', 'manager')) then
    raise exception 'Only an Owner or Manager can see the TikTok payouts'; end if;
  if p_from is null or p_to is null then raise exception 'Choose a start and an end date'; end if;
  if p_to < p_from then raise exception 'The end date cannot be before the start date'; end if;
  if p_to - p_from > 400 then raise exception 'Choose at most about a year at a time'; end if;

  -- The app's own weeks (374) of every reporting month the dates and the
  -- week before them reach.
  for m in select distinct r.year, r.month
             from generate_series((p_from - 7)::timestamp, p_to::timestamp, interval '1 day') d,
                  lateral public.tiktok_reporting_month(d::date::timestamp at time zone 'Asia/Singapore') r loop
    v_weeks := v_weeks || (public.tiktok_xero_payouts(m.year, m.month)->'weeks');
  end loop;

  with conf as (
    select r.*, b.file_name, b.confirmed_at, b.uploaded_at
      from public.tiktok_balance_records r
      join public.tiktok_import_batches b on b.id = r.batch_id
     where b.status = 'confirmed' and b.deleted_at is null
  ),
  recs as (
    -- Each record once: TikTok's transferred one before any other, and of
    -- those the one from the first file confirmed with it.
    select distinct on (c.transaction_type, c.reference_id) c.*
      from conf c
     order by c.transaction_type, c.reference_id, (coalesce(c.status, '') = 'Transferred') desc,
              c.confirmed_at nulls last, c.uploaded_at, c.row_no
  ),
  pay as (
    select r.reference_id, coalesce(r.success_date, r.request_date) as paid_on, -r.amount as amount, r.status,
           coalesce(r.status, '') = 'Transferred' as transferred, r.file_name,
           coalesce(r.success_date, r.request_date)
             - ((extract(isodow from coalesce(r.success_date, r.request_date))::int - 3 + 7) % 7) as wednesday,
           -- Other files that give this payout another amount.
           (select coalesce(jsonb_agg(jsonb_build_object('amount', round(-o.amount, 2), 'file_name', o.file_name)
                                      order by o.confirmed_at, o.file_name), '[]'::jsonb)
              from conf o where o.transaction_type = r.transaction_type and o.reference_id = r.reference_id
               and o.amount <> r.amount) as disagreeing
      from recs r
     where r.transaction_type = 'Payments' and coalesce(r.success_date, r.request_date) is not null
  ),
  wk as (
    select distinct on ((w->>'payout_date')::date) (w->>'payout_date')::date as wednesday, w
      from jsonb_array_elements(v_weeks) w
     order by (w->>'payout_date')::date
  ),
  first_day as (
    -- The first day any confirmed settlement file reaches: no week before it is
    -- expected to have a file.
    select min((s.settled_time at time zone 'Asia/Singapore')::date) as d
      from public.tiktok_settlement_rows s
      join public.tiktok_import_batches b on b.id = s.batch_id
     where b.status = 'confirmed' and b.deleted_at is null and b.file_kind = 'settlement'
       and s.settled_time is not null
  )
  select jsonb_build_object(
    'payouts', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'reference_id', p.reference_id, 'paid_on', p.paid_on, 'amount', round(p.amount, 2), 'status', p.status,
               'transferred', p.transferred, 'file_name', p.file_name, 'disagreeing', p.disagreeing,
               'wednesday', p.wednesday, 'week_start', p.wednesday - 6,
               'app_payout', (wk.w->>'payout')::numeric,
               'app_rows', (wk.w->>'row_count')::int,
               'uncovered_days', coalesce(wk.w->'uncovered_days', '[]'::jsonb),
               'left_out_count', coalesce((wk.w->>'left_out_count')::int, 0))
             order by p.paid_on, p.reference_id), '[]'::jsonb)
        from pay p left join wk on wk.wednesday = p.wednesday
       where p.paid_on between p_from and p_to),
    -- Finished Wednesdays between the dates with no transferred payout for them
    -- (paid on any day) and none listed above, whose week the app says pays
    -- out, which an imported file should reach but does not, or whose lines
    -- were left out at confirmation.
    'wednesdays_without_payout', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'wednesday', wk.wednesday, 'week_start', wk.wednesday - 6,
               'app_payout', (wk.w->>'payout')::numeric, 'app_rows', (wk.w->>'row_count')::int,
               'uncovered_days', coalesce(wk.w->'uncovered_days', '[]'::jsonb),
               'left_out_count', coalesce((wk.w->>'left_out_count')::int, 0))
             order by wk.wednesday), '[]'::jsonb)
        from wk cross join first_day f
       where wk.wednesday between p_from and p_to
         and wk.wednesday < v_today
         and ((wk.w->>'payout')::numeric > 0
              or coalesce((wk.w->>'left_out_count')::int, 0) > 0
              or (wk.wednesday >= f.d and jsonb_array_length(coalesce(wk.w->'uncovered_days', '[]'::jsonb)) > 0))
         and not exists (select 1 from pay p
                          where p.wednesday = wk.wednesday
                            and (p.transferred or p.paid_on between p_from and p_to))),
    -- Payouts with neither date cannot be placed: they are counted, not lost.
    'undated_payout_count', (select count(*)::int from recs r
                              where r.transaction_type = 'Payments' and coalesce(r.success_date, r.request_date) is null))
    into v_out;

  return jsonb_build_object('from', p_from, 'to', p_to, 'today', v_today, 'timezone', 'Asia/Singapore') || v_out;
end $f$;

-- ── 3. Who may call what ──────────────────────────────────────────────────
-- Staging and what a file brought: whoever may import TikTok settlement files
-- (tiktok_access_check). The payouts: Owners and Managers.
revoke all on function public.stage_tiktok_settlement_file(uuid, text, text, jsonb, jsonb) from public, anon;
grant execute on function public.stage_tiktok_settlement_file(uuid, text, text, jsonb, jsonb) to authenticated, service_role;
revoke all on function public.tiktok_batch_balance_counts(uuid) from public, anon;
grant execute on function public.tiktok_batch_balance_counts(uuid) to authenticated, service_role;
revoke all on function public.tiktok_bank_payouts(date, date) from public, anon;
grant execute on function public.tiktok_bank_payouts(date, date) to authenticated, service_role;

notify pgrst, 'reload schema';
