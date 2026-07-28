-- =====================================================================
-- ENERGIA — PHASE 26: GLOBAL CUSTOMER CREDIT WALLET AND LEGACY BALANCES
--
-- One global wallet per customer, usable at every store, holding credit in
-- five categories. Every grant is a LOT with an original and a remaining
-- amount; every movement is an append-only LEDGER entry; consumption records
-- which lot funded it. Nothing expires, nothing transfers between customers,
-- no balance may go negative, and nothing is editable after posting —
-- corrections are made with reversing or adjustment entries.
--
-- Tables: customer_credit_wallets, customer_credit_lots,
--         customer_credit_ledger, customer_credit_allocations,
--         customer_credit_adjustments, customer_credit_statements
--
-- Visibility: Owner, Manager, and Staff with authorised store access.
-- Admin and Inventory Manager are deliberately excluded.
--
-- Additive and idempotent. Run AFTER 76.
-- (Numbered 77 to stay sequential — 73 is already Phase 24.)
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Who may see and who may manage a wallet.
-- ---------------------------------------------------------------------
create or replace function public.can_view_customer_credit()
returns boolean language sql stable security definer set search_path to 'public' as $function$
  select exists (
    select 1 from public.profiles p
     where p.id = auth.uid() and p.is_active = true
       and (
         p.role in ('owner','manager')
         or (p.role = 'staff' and exists (
               select 1 from public.user_store_assignments usa
                where usa.user_id = p.id))
       ))
$function$;

-- Admin and Inventory Manager are intentionally not included above.
create or replace function public.can_manage_customer_credit()
returns boolean language sql stable security definer set search_path to 'public' as $function$
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active = true
                    and p.role in ('owner','manager'))
$function$;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
create table if not exists public.customer_credit_wallets (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique references public.customers(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A lot is one grant of credit. It carries its own remaining balance and is
-- immutable except for that balance.
create table if not exists public.customer_credit_lots (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.customer_credit_wallets(id),
  customer_id uuid not null references public.customers(id),
  category text not null check (category in ('paid','bonus','legacy','promotional','exchange')),
  original_amount numeric(12,2) not null check (original_amount > 0),
  remaining_amount numeric(12,2) not null check (remaining_amount >= 0),
  source_type text not null,
  source_record_id uuid,
  store_id uuid references public.stores(id),
  usage_restrictions jsonb not null default '{}'::jsonb,
  original_purchase_date date,
  effective_date date not null default (now() at time zone 'Asia/Singapore')::date,
  reference_no text,
  reason text,
  note text,
  status text not null default 'active' check (status in ('active','reversed')),
  reversal_of_lot_id uuid references public.customer_credit_lots(id),
  is_locked boolean not null default false,
  created_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credit_lot_remaining_within_original check (remaining_amount <= original_amount)
);
create index if not exists idx_credit_lots_customer on public.customer_credit_lots (customer_id, category);
create index if not exists idx_credit_lots_fifo on public.customer_credit_lots (customer_id, effective_date, created_at);
-- Reference numbers are unique per manual source.
create unique index if not exists uq_credit_lot_manual_legacy_ref
  on public.customer_credit_lots (reference_no) where source_type = 'manual_legacy';
create unique index if not exists uq_credit_lot_manual_adjustment_ref
  on public.customer_credit_lots (reference_no) where source_type = 'manual_adjustment';

-- Append-only record of every movement.
create table if not exists public.customer_credit_ledger (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.customer_credit_wallets(id),
  customer_id uuid not null references public.customers(id),
  entry_type text not null check (entry_type in ('grant','use','reverse','adjust_increase','adjust_decrease')),
  category text not null check (category in ('paid','bonus','legacy','promotional','exchange')),
  amount numeric(12,2) not null check (amount > 0),
  lot_id uuid references public.customer_credit_lots(id),
  source_type text not null,
  source_record_id uuid,
  store_id uuid references public.stores(id),
  effective_date date not null default (now() at time zone 'Asia/Singapore')::date,
  reference_no text,
  reason text,
  note text,
  reverses_entry_id uuid references public.customer_credit_ledger(id),
  created_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
-- A monotonic posting sequence. created_at cannot order the ledger because
-- now() is fixed for a whole transaction, so several entries posted together
-- would share a timestamp and sort arbitrarily.
alter table public.customer_credit_ledger add column if not exists entry_seq bigserial;
create index if not exists idx_credit_ledger_customer on public.customer_credit_ledger (customer_id, effective_date, entry_seq);

-- Which lot funded which usage.
create table if not exists public.customer_credit_allocations (
  id uuid primary key default gen_random_uuid(),
  ledger_entry_id uuid not null references public.customer_credit_ledger(id),
  lot_id uuid not null references public.customer_credit_lots(id),
  customer_id uuid not null references public.customers(id),
  amount numeric(12,2) not null check (amount > 0),
  created_at timestamptz not null default now()
);
create index if not exists idx_credit_alloc_lot on public.customer_credit_allocations (lot_id);

-- Manual adjustments made by an Owner or Manager.
create table if not exists public.customer_credit_adjustments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  category text not null check (category in ('paid','bonus','legacy','promotional','exchange')),
  direction text not null check (direction in ('increase','decrease')),
  amount numeric(12,2) not null check (amount > 0),
  reason text not null,
  note text,
  reference_no text not null,
  effective_date date not null,
  ledger_entry_id uuid references public.customer_credit_ledger(id),
  lot_id uuid references public.customer_credit_lots(id),
  created_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create unique index if not exists uq_credit_adjustment_ref on public.customer_credit_adjustments (reference_no);

-- Issued statement snapshots.
create table if not exists public.customer_credit_statements (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  period_from date,
  period_to date,
  closing_balances jsonb not null,
  closing_total numeric(12,2) not null,
  issued_at timestamptz not null default now(),
  issued_by uuid references public.profiles(id)
);

-- ---------------------------------------------------------------------
-- 3. RLS — read for Owner/Manager/authorised Staff, no direct writes.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['customer_credit_wallets','customer_credit_lots','customer_credit_ledger',
                           'customer_credit_allocations','customer_credit_adjustments',
                           'customer_credit_statements']
  loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t
                    and policyname='view customer credit') then
      execute format($f$create policy "view customer credit" on public.%I
                        for select to authenticated using (public.can_view_customer_credit())$f$, t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 4. Immutability. The ledger is append-only; a lot may only have its
--    remaining balance (and lock/status) moved by the functions below.
-- ---------------------------------------------------------------------
create or replace function public.trg_credit_ledger_immutable()
returns trigger language plpgsql as $function$
begin
  raise exception 'Credit ledger entries cannot be % — post a reversing or adjustment entry instead',
    case when tg_op = 'DELETE' then 'deleted' else 'edited' end;
end $function$;

drop trigger if exists credit_ledger_immutable on public.customer_credit_ledger;
create trigger credit_ledger_immutable before update or delete on public.customer_credit_ledger
  for each row execute function public.trg_credit_ledger_immutable();

create or replace function public.trg_credit_lot_immutable()
returns trigger language plpgsql as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Credit lots cannot be deleted — post a reversing entry instead';
  end if;
  if new.customer_id is distinct from old.customer_id then
    raise exception 'Credit cannot be transferred to another customer';
  end if;
  if new.category is distinct from old.category
     or new.original_amount is distinct from old.original_amount
     or new.source_type is distinct from old.source_type
     or new.source_record_id is distinct from old.source_record_id
     or new.store_id is distinct from old.store_id
     or new.effective_date is distinct from old.effective_date
     or new.reference_no is distinct from old.reference_no
     or new.original_purchase_date is distinct from old.original_purchase_date
     or new.created_by is distinct from old.created_by
     or new.approved_by is distinct from old.approved_by
     or new.created_at is distinct from old.created_at then
    raise exception 'A posted credit lot cannot be edited — post a reversing or adjustment entry instead';
  end if;
  return new;
end $function$;

drop trigger if exists credit_lot_immutable on public.customer_credit_lots;
create trigger credit_lot_immutable before update or delete on public.customer_credit_lots
  for each row execute function public.trg_credit_lot_immutable();

create or replace function public.trg_credit_alloc_immutable()
returns trigger language plpgsql as $function$
begin
  raise exception 'Credit allocations cannot be changed once recorded';
end $function$;
drop trigger if exists credit_alloc_immutable on public.customer_credit_allocations;
create trigger credit_alloc_immutable before update or delete on public.customer_credit_allocations
  for each row execute function public.trg_credit_alloc_immutable();

-- ---------------------------------------------------------------------
-- 5. Wallet creation — exactly one per customer.
-- ---------------------------------------------------------------------
create or replace function public.ensure_customer_wallet(p_customer_id uuid)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid;
begin
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  select id into v_id from public.customer_credit_wallets where customer_id = p_customer_id;
  if v_id is not null then return v_id; end if;
  insert into public.customer_credit_wallets (customer_id) values (p_customer_id)
  on conflict (customer_id) do update set updated_at = now()
  returning id into v_id;
  return v_id;
end $function$;

-- ---------------------------------------------------------------------
-- 6. Balances — per category and combined.
-- ---------------------------------------------------------------------
create or replace function public.customer_credit_balances(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_cats jsonb; v_total numeric;
begin
  if not public.can_view_customer_credit() then
    raise exception 'You do not have access to customer credit';
  end if;
  select coalesce(jsonb_object_agg(c.category, c.bal), '{}'::jsonb), coalesce(sum(c.bal),0)
    into v_cats, v_total
    from (select l.category, sum(l.remaining_amount) as bal
            from public.customer_credit_lots l
           where l.customer_id = p_customer_id and l.status = 'active'
           group by l.category) c;
  return jsonb_build_object(
    'customer_id', p_customer_id,
    'categories', jsonb_build_object(
      'paid', coalesce((v_cats->>'paid')::numeric, 0),
      'bonus', coalesce((v_cats->>'bonus')::numeric, 0),
      'legacy', coalesce((v_cats->>'legacy')::numeric, 0),
      'promotional', coalesce((v_cats->>'promotional')::numeric, 0),
      'exchange', coalesce((v_cats->>'exchange')::numeric, 0)),
    'available_total', coalesce(v_total,0));
end $function$;

-- ---------------------------------------------------------------------
-- 7. Granting credit. Used by manual entry, adjustments and (later) sales.
-- ---------------------------------------------------------------------
create or replace function public.grant_customer_credit(
  p_customer_id uuid, p_category text, p_amount numeric, p_source_type text,
  p_source_record_id uuid default null, p_store_id uuid default null,
  p_effective_date date default null, p_reference_no text default null,
  p_reason text default null, p_note text default null,
  p_original_purchase_date date default null, p_approved_by uuid default null,
  p_usage_restrictions jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_wallet uuid; v_lot uuid; v_eff date;
begin
  if coalesce(p_amount,0) <= 0 then raise exception 'Credit amount must be greater than zero'; end if;
  if p_category not in ('paid','bonus','legacy','promotional','exchange') then
    raise exception 'Unknown credit category "%"', p_category; end if;
  v_wallet := public.ensure_customer_wallet(p_customer_id);
  v_eff := coalesce(p_effective_date, public.sg_today());

  insert into public.customer_credit_lots (
    wallet_id, customer_id, category, original_amount, remaining_amount,
    source_type, source_record_id, store_id, usage_restrictions,
    original_purchase_date, effective_date, reference_no, reason, note,
    created_by, approved_by)
  values (v_wallet, p_customer_id, p_category, round(p_amount,2), round(p_amount,2),
    p_source_type, p_source_record_id, p_store_id, coalesce(p_usage_restrictions,'{}'::jsonb),
    p_original_purchase_date, v_eff, p_reference_no, p_reason, p_note,
    auth.uid(), p_approved_by)
  returning id into v_lot;

  insert into public.customer_credit_ledger (
    wallet_id, customer_id, entry_type, category, amount, lot_id,
    source_type, source_record_id, store_id, effective_date,
    reference_no, reason, note, created_by, approved_by)
  values (v_wallet, p_customer_id, 'grant', p_category, round(p_amount,2), v_lot,
    p_source_type, p_source_record_id, p_store_id, v_eff,
    p_reference_no, p_reason, p_note, auth.uid(), p_approved_by);

  perform public.write_audit_ex('customer_credit_lots', v_lot, 'credit_granted', null,
    jsonb_build_object('customer', p_customer_id, 'category', p_category,
      'amount', p_amount, 'source', p_source_type, 'reference', p_reference_no),
    'credit', p_reason, p_store_id);
  return v_lot;
end $function$;

-- ---------------------------------------------------------------------
-- 8. Manual legacy opening balances (Owner/Manager only, no commission).
-- ---------------------------------------------------------------------
create or replace function public.add_legacy_credit(
  p_customer_id uuid, p_category text, p_amount numeric,
  p_original_purchase_date date, p_store_id uuid, p_reference_no text,
  p_note text, p_effective_date date default null, p_approved_by uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_lot uuid; v_approver uuid;
begin
  if not public.can_manage_customer_credit() then
    raise exception 'Only an Owner or Manager can enter old-client balances';
  end if;
  -- Opening balances are only meaningful for these categories.
  if p_category not in ('paid','bonus','legacy') then
    raise exception 'An opening balance may only be Paid, Bonus or Legacy credit';
  end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if p_original_purchase_date is null then raise exception 'The original purchase date is required'; end if;
  if p_store_id is null then raise exception 'The store is required'; end if;
  if coalesce(trim(p_reference_no),'') = '' then raise exception 'A reference number is required'; end if;
  if coalesce(trim(p_note),'') = '' then raise exception 'A supporting note is required'; end if;

  -- Owner/Manager may create and confirm directly; both actors are recorded
  -- even when they are the same person.
  v_approver := coalesce(p_approved_by, auth.uid());

  if exists (select 1 from public.customer_credit_lots
              where source_type = 'manual_legacy' and reference_no = trim(p_reference_no)) then
    raise exception 'Reference number "%" has already been used for a manual legacy entry', trim(p_reference_no);
  end if;

  v_lot := public.grant_customer_credit(
    p_customer_id, p_category, p_amount, 'manual_legacy', null, p_store_id,
    coalesce(p_effective_date, p_original_purchase_date), trim(p_reference_no),
    'Old-client opening balance', p_note, p_original_purchase_date, v_approver);
  return v_lot;
end $function$;

-- ---------------------------------------------------------------------
-- 9. Manual adjustments (Owner/Manager only).
-- ---------------------------------------------------------------------
create or replace function public.adjust_customer_credit(
  p_customer_id uuid, p_category text, p_direction text, p_amount numeric,
  p_reason text, p_reference_no text, p_effective_date date default null,
  p_note text default null, p_store_id uuid default null, p_approved_by uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare
  v_wallet uuid; v_lot uuid; v_entry uuid; v_adj uuid; v_eff date;
  v_left numeric; v_take numeric; v_l record; v_approver uuid;
begin
  if not public.can_manage_customer_credit() then
    raise exception 'Only an Owner or Manager can adjust customer credit';
  end if;
  if p_direction not in ('increase','decrease') then raise exception 'Direction must be increase or decrease'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required'; end if;
  if coalesce(trim(p_reference_no),'') = '' then raise exception 'A reference number is required'; end if;

  v_eff := coalesce(p_effective_date, public.sg_today());
  v_approver := coalesce(p_approved_by, auth.uid());
  v_wallet := public.ensure_customer_wallet(p_customer_id);

  if p_direction = 'increase' then
    v_lot := public.grant_customer_credit(p_customer_id, p_category, p_amount,
      'manual_adjustment', null, p_store_id, v_eff, trim(p_reference_no),
      p_reason, p_note, null, v_approver);
    select id into v_entry from public.customer_credit_ledger
     where lot_id = v_lot and entry_type = 'grant' limit 1;
  else
    -- Decrease draws down existing lots of that category, oldest first, and
    -- can never take the balance below zero.
    select coalesce(sum(remaining_amount),0) into v_left
      from public.customer_credit_lots
     where customer_id = p_customer_id and category = p_category and status = 'active';
    if v_left < round(p_amount,2) then
      raise exception 'Cannot decrease % credit by % — only % is available', p_category, p_amount, v_left;
    end if;

    insert into public.customer_credit_ledger (
      wallet_id, customer_id, entry_type, category, amount, source_type,
      store_id, effective_date, reference_no, reason, note, created_by, approved_by)
    values (v_wallet, p_customer_id, 'adjust_decrease', p_category, round(p_amount,2),
      'manual_adjustment', p_store_id, v_eff, trim(p_reference_no), p_reason, p_note,
      auth.uid(), v_approver)
    returning id into v_entry;

    v_take := round(p_amount,2);
    for v_l in
      select id, remaining_amount from public.customer_credit_lots
       where customer_id = p_customer_id and category = p_category
         and status = 'active' and remaining_amount > 0
       order by effective_date, created_at
       for update
    loop
      exit when v_take <= 0;
      if v_l.remaining_amount >= v_take then
        update public.customer_credit_lots
           set remaining_amount = remaining_amount - v_take, updated_at = now()
         where id = v_l.id;
        insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
        values (v_entry, v_l.id, p_customer_id, v_take);
        v_take := 0;
      else
        update public.customer_credit_lots
           set remaining_amount = 0, updated_at = now() where id = v_l.id;
        insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
        values (v_entry, v_l.id, p_customer_id, v_l.remaining_amount);
        v_take := v_take - v_l.remaining_amount;
      end if;
    end loop;
  end if;

  insert into public.customer_credit_adjustments (
    customer_id, category, direction, amount, reason, note, reference_no,
    effective_date, ledger_entry_id, lot_id, created_by, approved_by)
  values (p_customer_id, p_category, p_direction, round(p_amount,2), p_reason, p_note,
    trim(p_reference_no), v_eff, v_entry, v_lot, auth.uid(), v_approver)
  returning id into v_adj;

  perform public.write_audit_ex('customer_credit_adjustments', v_adj, 'credit_adjusted', null,
    jsonb_build_object('customer', p_customer_id, 'category', p_category,
      'direction', p_direction, 'amount', p_amount, 'reference', trim(p_reference_no)),
    'credit', p_reason, p_store_id);
  return v_adj;
end $function$;

-- ---------------------------------------------------------------------
-- 10. Spending credit. Global across stores, oldest lot first, never negative.
-- ---------------------------------------------------------------------
create or replace function public.consume_customer_credit(
  p_customer_id uuid, p_amount numeric, p_source_type text default 'manual_use',
  p_source_record_id uuid default null, p_store_id uuid default null,
  p_category text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_wallet uuid; v_entry uuid; v_take numeric; v_avail numeric; v_l record;
  v_used jsonb := '[]'::jsonb;
begin
  if coalesce(p_amount,0) <= 0 then raise exception 'Amount must be greater than zero'; end if;
  v_wallet := public.ensure_customer_wallet(p_customer_id);

  select coalesce(sum(remaining_amount),0) into v_avail
    from public.customer_credit_lots
   where customer_id = p_customer_id and status = 'active'
     and (p_category is null or category = p_category);
  if v_avail < round(p_amount,2) then
    raise exception 'Insufficient credit: % available, % requested', v_avail, p_amount;
  end if;

  v_take := round(p_amount,2);
  for v_l in
    select id, category, remaining_amount from public.customer_credit_lots
     where customer_id = p_customer_id and status = 'active' and remaining_amount > 0
       and (p_category is null or category = p_category)
     order by effective_date, created_at
     for update
  loop
    exit when v_take <= 0;
    declare v_use numeric := least(v_l.remaining_amount, v_take);
    begin
      insert into public.customer_credit_ledger (
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, note, created_by)
      values (v_wallet, p_customer_id, 'use', v_l.category, v_use, v_l.id,
        p_source_type, p_source_record_id, p_store_id, p_note, auth.uid())
      returning id into v_entry;

      update public.customer_credit_lots
         set remaining_amount = remaining_amount - v_use, updated_at = now()
       where id = v_l.id;
      insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
      values (v_entry, v_l.id, p_customer_id, v_use);

      v_used := v_used || jsonb_build_object('lot_id', v_l.id, 'category', v_l.category, 'amount', v_use);
      v_take := v_take - v_use;
    end;
  end loop;

  return jsonb_build_object('success', true, 'amount', round(p_amount,2), 'allocations', v_used,
    'balance_after', (select coalesce(sum(remaining_amount),0) from public.customer_credit_lots
                       where customer_id = p_customer_id and status = 'active'));
end $function$;

-- ---------------------------------------------------------------------
-- 11. Reversing a lot. The unused part is withdrawn; nothing is edited.
-- ---------------------------------------------------------------------
create or replace function public.reverse_credit_lot(
  p_lot_id uuid, p_reason text, p_note text default null, p_reference_no text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare l public.customer_credit_lots%rowtype; v_entry uuid; v_amt numeric;
begin
  if not public.can_manage_customer_credit() then
    raise exception 'Only an Owner or Manager can reverse credit';
  end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required'; end if;
  select * into l from public.customer_credit_lots where id = p_lot_id for update;
  if not found then raise exception 'Credit lot not found'; end if;
  if l.status = 'reversed' then raise exception 'That credit has already been reversed'; end if;

  v_amt := l.remaining_amount;
  if v_amt <= 0 then raise exception 'That credit has already been fully used and cannot be reversed'; end if;

  insert into public.customer_credit_ledger (
    wallet_id, customer_id, entry_type, category, amount, lot_id,
    source_type, source_record_id, store_id, effective_date,
    reference_no, reason, note, created_by, approved_by)
  values (l.wallet_id, l.customer_id, 'reverse', l.category, v_amt, l.id,
    'reversal', l.id, l.store_id, public.sg_today(),
    p_reference_no, p_reason, p_note, auth.uid(), auth.uid())
  returning id into v_entry;

  update public.customer_credit_lots
     set remaining_amount = 0, status = 'reversed', is_locked = true, updated_at = now()
   where id = p_lot_id;

  perform public.write_audit_ex('customer_credit_lots', p_lot_id, 'credit_reversed',
    jsonb_build_object('remaining', v_amt), jsonb_build_object('reason', p_reason),
    'credit', p_reason, l.store_id);
  return v_entry;
end $function$;

-- ---------------------------------------------------------------------
-- 12. Statement with running balances.
-- ---------------------------------------------------------------------
-- The row shape changed when the posting sequence was added, so the previous
-- version must be dropped rather than replaced.
drop function if exists public.customer_credit_statement(uuid, date, date);

create or replace function public.customer_credit_statement(
  p_customer_id uuid, p_from date default null, p_to date default null)
returns table(
  entry_seq bigint, entry_date date, created_at timestamptz, description text, source text,
  category text, credit_added numeric, credit_used numeric, credit_reversed numeric,
  lot_remaining numeric, wallet_balance numeric, reference_no text, note text)
language plpgsql stable security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare v_run numeric := 0; v_e record;
begin
  if not public.can_view_customer_credit() then
    raise exception 'You do not have access to customer credit';
  end if;
  for v_e in
    select e.*,
           case e.entry_type
             when 'grant' then 'Credit added'
             when 'adjust_increase' then 'Adjustment — increase'
             when 'use' then 'Credit used'
             when 'adjust_decrease' then 'Adjustment — decrease'
             when 'reverse' then 'Credit reversed'
           end as descr
      from public.customer_credit_ledger e
     where e.customer_id = p_customer_id
       and (p_from is null or e.effective_date >= p_from)
       and (p_to is null or e.effective_date <= p_to)
     order by e.effective_date, e.entry_seq
  loop
    if v_e.entry_type in ('grant','adjust_increase') then
      v_run := v_run + v_e.amount;
    else
      v_run := v_run - v_e.amount;
    end if;
    return query select
      v_e.entry_seq, v_e.effective_date, v_e.created_at,
      v_e.descr || coalesce(' — ' || v_e.reason, ''),
      v_e.source_type, v_e.category,
      case when v_e.entry_type in ('grant','adjust_increase') then v_e.amount else null end,
      case when v_e.entry_type in ('use','adjust_decrease') then v_e.amount else null end,
      case when v_e.entry_type = 'reverse' then v_e.amount else null end,
      (select l.remaining_amount from public.customer_credit_lots l where l.id = v_e.lot_id),
      round(v_run,2), v_e.reference_no, v_e.note;
  end loop;
end $function$;

-- Save a statement snapshot.
create or replace function public.issue_customer_credit_statement(
  p_customer_id uuid, p_from date default null, p_to date default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_bal jsonb;
begin
  if not public.can_view_customer_credit() then
    raise exception 'You do not have access to customer credit'; end if;
  v_bal := public.customer_credit_balances(p_customer_id);
  insert into public.customer_credit_statements
    (customer_id, period_from, period_to, closing_balances, closing_total, issued_by)
  values (p_customer_id, p_from, p_to, v_bal->'categories',
          (v_bal->>'available_total')::numeric, auth.uid())
  returning id into v_id;
  return v_id;
end $function$;

notify pgrst, 'reload schema';
