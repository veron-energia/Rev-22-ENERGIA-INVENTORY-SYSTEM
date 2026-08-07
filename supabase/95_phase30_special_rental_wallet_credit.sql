-- =====================================================================
-- ENERGIA — PHASE 30 (part 2): WALLET CREDIT ON SPECIAL PRODUCTS AND RENTALS
--
-- Special Products and Rentals keep their own pages and their own records;
-- this adds wallet payment to them rather than converting them into invoice
-- lines, which would have rewritten two working flows.
--
-- Rules enforced here:
--   * the lot must permit the 'special_product' or 'rental' purpose;
--   * exact per-lot allocations are stored, so a refund can return credit to
--     the lots it came from;
--   * credit-funded value earns NO commission;
--   * external paid Special Product value still qualifies for Legacy Therapy;
--     rental value never does.
--
-- Additive and idempotent. Run AFTER 94.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Where credit was spent outside the invoice system.
-- ---------------------------------------------------------------------
create table if not exists public.special_credit_allocations (
  id uuid primary key default gen_random_uuid(),
  doc_kind text not null check (doc_kind in ('special_sale','rental','rental_late_fee')),
  doc_id uuid not null,
  customer_id uuid not null references public.customers(id),
  lot_id uuid not null references public.customer_credit_lots(id),
  ledger_entry_id uuid references public.customer_credit_ledger(id),
  category text not null,
  amount numeric(14,2) not null check (amount > 0),
  reversed_amount numeric(14,2) not null default 0,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_special_credit_alloc_doc
  on public.special_credit_allocations (doc_kind, doc_id);
alter table public.special_credit_allocations enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='special_credit_allocations' and policyname='read special credit allocations') then
    create policy "read special credit allocations" on public.special_credit_allocations
      for select to authenticated using (true);
  end if;
end $$;

-- How much of a special sale or rental the wallet paid for.
alter table public.special_sales add column if not exists credit_funded numeric(14,2) not null default 0;
alter table public.rentals      add column if not exists credit_funded numeric(14,2) not null default 0;

-- ---------------------------------------------------------------------
-- 2. Spend wallet credit against a special sale or a rental.
--    Bonus Credit first, then the oldest eligible lot — the same order the
--    invoice path uses, so a customer cannot get a different answer depending
--    on which screen the sale was made from.
-- ---------------------------------------------------------------------
-- consume_customer_credit already chooses lots and records the ledger; it is
-- called once and its allocation list is mirrored into
-- special_credit_allocations so a refund can find the exact lots.
--
-- Its ordering is also corrected here to Bonus-first, matching
-- allocate_invoice_wallet_credit. Without this a customer would see different
-- lots consumed depending on whether they bought from the invoice screen or
-- the Special Products screen.
-- Bonus-first ordering, so a customer sees the same lots consumed whether
-- they buy from the invoice screen or the Special Products screen. The body
-- is otherwise migration 79's verbatim, including the allocations insert and
-- the original error wording, which callers and tests depend on.
create or replace function public.consume_customer_credit(
  p_customer_id uuid, p_amount numeric, p_source_type text default 'manual_use',
  p_source_record_id uuid default null, p_store_id uuid default null,
  p_category text default null, p_note text default null,
  p_purpose text default 'general', p_voucher_id uuid default null)
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
     and (p_category is null or category = p_category)
     and public.credit_lot_allows(usage_restrictions, p_purpose, p_voucher_id);
  if v_avail < round(p_amount,2) then
    raise exception 'Insufficient credit for this purchase: % usable, % required', v_avail, p_amount;
  end if;

  v_take := round(p_amount,2);
  for v_l in
    select id, category, remaining_amount from public.customer_credit_lots
     where customer_id = p_customer_id and status = 'active' and remaining_amount > 0
       and (p_category is null or category = p_category)
       and public.credit_lot_allows(usage_restrictions, p_purpose, p_voucher_id)
     -- Bonus Credit is spent before anything else, matching
     -- allocate_invoice_wallet_credit. Everything else about this function is
     -- unchanged from migration 79 — only the ordering differs.
     order by case when category = 'bonus' then 0 else 1 end,
              effective_date, created_at for update
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
         set remaining_amount = remaining_amount - v_use, updated_at = now() where id = v_l.id;
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

create or replace function public.pay_special_with_credit(
  p_doc_kind text, p_doc_id uuid, p_customer_id uuid, p_amount numeric,
  p_store_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_purpose text; v_res jsonb; v_a jsonb; v_total numeric := 0;
begin
  if p_customer_id is null then raise exception 'Wallet credit needs a customer'; end if;
  if round(coalesce(p_amount,0),2) <= 0 then return jsonb_build_object('funded', 0); end if;

  v_purpose := case p_doc_kind
    when 'special_sale' then 'special_product'
    when 'rental' then 'rental'
    when 'rental_late_fee' then 'rental'
    else null end;
  if v_purpose is null then raise exception 'Unknown document kind "%"', p_doc_kind; end if;

  v_res := public.consume_customer_credit(
    p_customer_id, round(p_amount,2), p_doc_kind, p_doc_id, p_store_id,
    null, 'Wallet payment: ' || replace(p_doc_kind,'_',' '), v_purpose, null);

  -- Mirror the exact per-lot split so a refund returns credit where it came from.
  for v_a in select * from jsonb_array_elements(coalesce(v_res->'allocations','[]'::jsonb))
  loop
    insert into public.special_credit_allocations
      (doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
    values (p_doc_kind, p_doc_id, p_customer_id,
      (v_a->>'lot_id')::uuid, v_a->>'category', (v_a->>'amount')::numeric, auth.uid());
    v_total := round(v_total + (v_a->>'amount')::numeric, 2);
  end loop;

  if p_doc_kind = 'special_sale' then
    update public.special_sales set credit_funded = credit_funded + v_total where id = p_doc_id;
  else
    update public.rentals set credit_funded = credit_funded + v_total where id = p_doc_id;
  end if;

  perform public.write_audit_ex(p_doc_kind, p_doc_id, 'paid_with_wallet_credit', null,
    jsonb_build_object('amount', v_total, 'purpose', v_purpose), 'credit', null, p_store_id);

  return jsonb_build_object('funded', v_total, 'allocations', v_res->'allocations');
end $function$;

-- ---------------------------------------------------------------------
-- 3. How much of a special sale counts toward Legacy Therapy.
--    External payment only; rentals never qualify.
-- ---------------------------------------------------------------------
create or replace function public.special_sale_qualifying_amount(p_sale_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  select greatest(round(coalesce(s.total_amount,0) - coalesce(s.credit_funded,0), 2), 0)
    from public.special_sales s
   where s.id = p_sale_id and s.status <> 'cancelled'
$function$;

-- ---------------------------------------------------------------------
-- 4. Refunding credit-funded value returns it to the lots it came from.
-- ---------------------------------------------------------------------
create or replace function public.refund_special_credit(p_doc_kind text, p_doc_id uuid)
returns numeric language plpgsql security definer set search_path to 'public' as $function$
declare v_a record; v_total numeric := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can refund wallet credit'; end if;

  for v_a in
    select * from public.special_credit_allocations
     where doc_kind = p_doc_kind and doc_id = p_doc_id
       and amount > coalesce(reversed_amount, 0)
  loop
    update public.customer_credit_lots
       set remaining_amount = remaining_amount + (v_a.amount - v_a.reversed_amount),
           updated_at = now()
     where id = v_a.lot_id;

    insert into public.customer_credit_ledger
      (wallet_id, customer_id, lot_id, entry_type, category, amount, source_type,
       source_record_id, note, created_by)
    select l.wallet_id, v_a.customer_id, v_a.lot_id, 'reverse', v_a.category,
           (v_a.amount - v_a.reversed_amount), p_doc_kind, p_doc_id,
           'Refund of wallet-funded ' || replace(p_doc_kind,'_',' '), auth.uid()
      from public.customer_credit_lots l where l.id = v_a.lot_id;

    v_total := round(v_total + (v_a.amount - v_a.reversed_amount), 2);
    update public.special_credit_allocations set reversed_amount = amount where id = v_a.id;
  end loop;

  if p_doc_kind = 'special_sale' then
    update public.special_sales set credit_funded = greatest(credit_funded - v_total, 0) where id = p_doc_id;
  else
    update public.rentals set credit_funded = greatest(credit_funded - v_total, 0) where id = p_doc_id;
  end if;

  return v_total;
end $function$;

notify pgrst, 'reload schema';
