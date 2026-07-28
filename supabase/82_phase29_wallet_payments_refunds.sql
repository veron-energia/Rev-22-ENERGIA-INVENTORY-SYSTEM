-- =====================================================================
-- ENERGIA — PHASE 29: WALLET PAYMENTS, COMMISSION ALLOCATION,
--                      REFUNDS AND EXCHANGES
--
-- Wallet credit becomes a real payment method that can be combined with cash,
-- PayNow, card or anything else on one invoice. Credit is consumed lot by lot
-- (Bonus first, then oldest eligible), the exact lot behind every invoice line
-- is recorded, and commission is calculated only on the portion NOT funded by
-- credit. Settled invoices, their payments, allocations and ledger entries are
-- locked. Refunds return credit to the very lots it came from.
--
-- Additive and idempotent. Run AFTER 81.
-- (Numbered 82 to stay sequential — 76 is already the Phase 25 visibility fix.)
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The five system wallet payment methods. They cannot be deleted.
-- ---------------------------------------------------------------------
alter table public.payment_methods add column if not exists wallet_category text
  check (wallet_category is null or wallet_category in ('paid','bonus','legacy','promotional','exchange'));
alter table public.payment_methods add column if not exists is_system boolean not null default false;

insert into public.payment_methods (name, is_active, is_wallet_credit, wallet_category, is_system)
select v.name, true, true, v.cat, true
  from (values
    ('Wallet — Paid Credit','paid'),
    ('Wallet — Bonus Credit','bonus'),
    ('Wallet — Legacy Credit','legacy'),
    ('Wallet — Promotional/FOC Credit','promotional'),
    ('Wallet — Exchange Credit','exchange')) as v(name, cat)
 where not exists (select 1 from public.payment_methods m
                    where m.is_system and m.wallet_category = v.cat);

create or replace function public.trg_protect_system_payment_methods()
returns trigger language plpgsql as $function$
begin
  if tg_op = 'DELETE' then
    if coalesce(old.is_system,false) then
      raise exception 'System wallet payment methods cannot be deleted'; end if;
    return old;
  end if;
  if coalesce(old.is_system,false) then
    if new.deleted_at is not null then
      raise exception 'System wallet payment methods cannot be deleted'; end if;
    if new.is_wallet_credit is distinct from old.is_wallet_credit
       or new.wallet_category is distinct from old.wallet_category
       or new.is_system is distinct from old.is_system then
      raise exception 'A system wallet payment method cannot be reconfigured';
    end if;
  end if;
  return new;
end $function$;

drop trigger if exists protect_system_payment_methods on public.payment_methods;
create trigger protect_system_payment_methods before update or delete on public.payment_methods
  for each row execute function public.trg_protect_system_payment_methods();

-- ---------------------------------------------------------------------
-- 2. Exact per-line, per-lot credit allocations. Never balance-only.
-- ---------------------------------------------------------------------
create table if not exists public.invoice_line_credit_allocations (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id),
  invoice_item_id uuid references public.invoice_items(id),
  lot_id uuid not null references public.customer_credit_lots(id),
  ledger_entry_id uuid references public.customer_credit_ledger(id),
  customer_id uuid not null references public.customers(id),
  category text not null,
  amount numeric(12,2) not null check (amount > 0),
  reversed_amount numeric(12,2) not null default 0 check (reversed_amount >= 0),
  locked_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id),
  constraint ilca_reversal_within_amount check (reversed_amount <= amount)
);
create index if not exists idx_ilca_invoice on public.invoice_line_credit_allocations (invoice_id);
create index if not exists idx_ilca_item on public.invoice_line_credit_allocations (invoice_item_id);
alter table public.invoice_line_credit_allocations enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='invoice_line_credit_allocations' and policyname='read line credit allocations') then
    create policy "read line credit allocations" on public.invoice_line_credit_allocations
      for select to authenticated using (public.can_view_customer_credit());
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. What purpose an invoice line represents for credit eligibility.
-- ---------------------------------------------------------------------
create or replace function public.invoice_line_credit_purpose(p_line_kind text)
returns text language sql immutable as $function$
  select case p_line_kind
    when 'product' then 'product'
    when 'voucher' then 'voucher'
    when 'promotion' then 'promotion'
    when 'therapy' then 'therapy'
    when 'credit_package' then 'credit_package'
    when 'premium_bundle' then 'premium_bundle'
    else p_line_kind end
$function$;

-- ---------------------------------------------------------------------
-- 4. Allocate wallet credit across the invoice's lines.
--    Order: Bonus Credit first, then the oldest eligible lot.
--    A lot that is not eligible for a line's category is skipped.
-- ---------------------------------------------------------------------
create or replace function public.allocate_invoice_wallet_credit(
  p_invoice_id uuid, p_amount numeric, p_category text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_it record; v_lot record;
  v_remaining numeric; v_line_open numeric; v_take numeric;
  v_wallet uuid; v_entry uuid; v_alloc jsonb := '[]'::jsonb; v_total numeric := 0;
  v_purpose text; v_vid uuid;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.customer_id is null then
    raise exception 'Wallet credit needs a customer on the invoice'; end if;
  if v_inv.status not in ('draft','unpaid','partially_paid') then
    raise exception 'Wallet credit can only be applied to an unsettled invoice'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'The wallet amount must be positive'; end if;

  v_wallet := public.ensure_customer_wallet(v_inv.customer_id);
  v_remaining := round(p_amount, 2);

  for v_it in
    select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
      from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and coalesce(ii.line_total,0) > 0
     order by ii.id
  loop
    exit when v_remaining <= 0;

    -- A credit product can never be funded by wallet credit.
    if v_it.purpose in ('credit_package','premium_bundle') then continue; end if;

    -- How much of this line is still unfunded by credit.
    select round(coalesce(v_it.line_total,0) - coalesce(v_it.line_discount,0)
                 - coalesce(sum(a.amount),0), 2)
      into v_line_open
      from public.invoice_line_credit_allocations a
     where a.invoice_item_id = v_it.id;
    if coalesce(v_line_open,0) <= 0 then continue; end if;

    v_purpose := v_it.purpose;
    v_vid := v_it.voucher_id;

    -- Bonus Credit first, then the oldest eligible lot.
    for v_lot in
      select l.* from public.customer_credit_lots l
       where l.customer_id = v_inv.customer_id and l.status = 'active'
         and l.remaining_amount > 0
         and (p_category is null or l.category = p_category)
         and public.credit_lot_allows(l.usage_restrictions, v_purpose, v_vid)
       order by (l.category = 'bonus') desc, l.effective_date, l.created_at
       for update
    loop
      exit when v_remaining <= 0 or v_line_open <= 0;
      v_take := least(v_lot.remaining_amount, v_line_open, v_remaining);
      if v_take <= 0 then continue; end if;

      insert into public.customer_credit_ledger (
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, note, created_by)
      values (v_wallet, v_inv.customer_id, 'use', v_lot.category, v_take, v_lot.id,
        'invoice_payment', p_invoice_id, v_inv.store_id,
        'Invoice ' || v_inv.invoice_no, auth.uid())
      returning id into v_entry;

      update public.customer_credit_lots
         set remaining_amount = remaining_amount - v_take, updated_at = now()
       where id = v_lot.id;

      insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
      values (v_entry, v_lot.id, v_inv.customer_id, v_take);

      insert into public.invoice_line_credit_allocations (
        invoice_id, invoice_item_id, lot_id, ledger_entry_id, customer_id,
        category, amount, created_by)
      values (p_invoice_id, v_it.id, v_lot.id, v_entry, v_inv.customer_id,
        v_lot.category, v_take, auth.uid());

      v_alloc := v_alloc || jsonb_build_object('invoice_item_id', v_it.id,
        'lot_id', v_lot.id, 'category', v_lot.category, 'amount', v_take);
      v_line_open := v_line_open - v_take;
      v_remaining := v_remaining - v_take;
      v_total := v_total + v_take;
    end loop;
  end loop;

  if v_remaining > 0.001 then
    raise exception 'Only % of the requested % could be funded by eligible credit', v_total, round(p_amount,2);
  end if;

  return jsonb_build_object('allocated', round(v_total,2), 'allocations', v_alloc);
end $function$;

-- How much of an invoice (or one line) was funded by credit.
create or replace function public.invoice_credit_funded(p_invoice_id uuid, p_item_id uuid default null)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  select coalesce(sum(a.amount - a.reversed_amount), 0)
    from public.invoice_line_credit_allocations a
   where a.invoice_id = p_invoice_id
     and (p_item_id is null or a.invoice_item_id = p_item_id)
$function$;

-- ---------------------------------------------------------------------
-- 5. Paying with a mixture of wallet credit and normal methods.
--    Wallet rows are recorded as ordinary payments against the system
--    wallet methods, so the invoice settles through the existing flow.
-- ---------------------------------------------------------------------
create or replace function public.pay_invoice_with_wallet(
  p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_p jsonb; v_m public.payment_methods%rowtype;
  v_wallet_total numeric := 0; v_res jsonb;
begin
  -- Consume the credit first, so commission can net it out.
  for v_p in select * from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
    select * into v_m from public.payment_methods where id = (v_p->>'payment_method_id')::uuid;
    if not found then raise exception 'Payment method not found'; end if;
    if coalesce(v_m.is_wallet_credit,false) then
      perform public.allocate_invoice_wallet_credit(
        p_invoice_id, (v_p->>'amount')::numeric, v_m.wallet_category);
      v_wallet_total := v_wallet_total + (v_p->>'amount')::numeric;
    end if;
  end loop;

  -- Then settle the invoice normally with every payment row.
  v_res := public.pay_invoice(p_invoice_id, p_payments);
  return v_res || jsonb_build_object('wallet_funded', round(v_wallet_total,2));
end $function$;

-- ---------------------------------------------------------------------
-- 6. Commission is calculated only on the portion NOT funded by credit.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'earn_invoice_commission';
  if v_def is null then raise exception 'earn_invoice_commission is missing'; end if;

  if position('invoice_line_credit_allocations' in v_def) = 0 then
    v_def := replace(v_def,
      '           coalesce(p.product_type::text, ''own'') as ptype',
      '           coalesce(p.product_type::text, ''own'') as ptype,' || chr(10) ||
      '           coalesce((select sum(a.amount - a.reversed_amount)' || chr(10) ||
      '                       from public.invoice_line_credit_allocations a' || chr(10) ||
      '                      where a.invoice_item_id = ii.id), 0) as wallet_funded');
    v_def := replace(v_def,
      '    v_line_net := v_item.line_total - coalesce(v_item.line_discount,0);',
      '    -- Wallet-funded value never earns commission.' || chr(10) ||
      '    v_line_net := greatest(v_item.line_total - coalesce(v_item.line_discount,0)' || chr(10) ||
      '                           - coalesce(v_item.wallet_funded,0), 0);');
    if position('invoice_line_credit_allocations' in v_def) = 0
       or position('wallet_funded,0), 0)' in v_def) = 0 then
      raise exception 'could not net wallet credit out of earn_invoice_commission';
    end if;
    execute v_def;
  end if;
end $patch$;

-- ---------------------------------------------------------------------
-- 7. Locking a settled invoice: payments, allocations and ledger.
-- ---------------------------------------------------------------------
create or replace function public.lock_settled_invoice(p_invoice_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  update public.invoices set locked_at = coalesce(locked_at, now())
   where id = p_invoice_id and status in ('paid','completed_foc');
  update public.invoice_payments set locked_at = coalesce(locked_at, now())
   where invoice_id = p_invoice_id;
  update public.invoice_line_credit_allocations set locked_at = coalesce(locked_at, now())
   where invoice_id = p_invoice_id;
end $function$;

create or replace function public.trg_lock_invoice_payments()
returns trigger language plpgsql as $function$
begin
  if tg_op = 'DELETE' then
    if old.locked_at is not null then
      raise exception 'A payment on a settled invoice cannot be deleted'; end if;
    return old;
  end if;
  if old.locked_at is not null
     and (new.amount is distinct from old.amount
          or new.payment_method_id is distinct from old.payment_method_id
          or new.invoice_id is distinct from old.invoice_id) then
    raise exception 'A payment on a settled invoice cannot be edited';
  end if;
  return new;
end $function$;
drop trigger if exists lock_invoice_payments on public.invoice_payments;
create trigger lock_invoice_payments before update or delete on public.invoice_payments
  for each row execute function public.trg_lock_invoice_payments();

create or replace function public.trg_lock_line_credit_allocations()
returns trigger language plpgsql as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'A credit allocation cannot be deleted — post a reversal instead';
  end if;
  if old.locked_at is not null then
    -- Only a reversal may move, and it may only ever increase.
    if new.amount is distinct from old.amount or new.lot_id is distinct from old.lot_id
       or new.invoice_item_id is distinct from old.invoice_item_id
       or new.category is distinct from old.category then
      raise exception 'A locked credit allocation cannot be edited';
    end if;
    if new.reversed_amount < old.reversed_amount then
      raise exception 'A credit reversal cannot be undone';
    end if;
  end if;
  return new;
end $function$;
drop trigger if exists lock_line_credit_allocations on public.invoice_line_credit_allocations;
create trigger lock_line_credit_allocations before update or delete on public.invoice_line_credit_allocations
  for each row execute function public.trg_lock_line_credit_allocations();

-- Lock everything as soon as the invoice settles.
create or replace function public.trg_lock_on_settle()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.status in ('paid','completed_foc') and old.status is distinct from new.status then
    perform public.lock_settled_invoice(new.id);
  end if;
  return null;
end $function$;
drop trigger if exists lock_on_settle on public.invoices;
create trigger lock_on_settle after update on public.invoices
  for each row execute function public.trg_lock_on_settle();

-- ---------------------------------------------------------------------
-- 8. Exchange credit enters the same wallet.
-- ---------------------------------------------------------------------
create or replace function public.grant_exchange_credit(
  p_exchange_id uuid, p_customer_id uuid, p_amount numeric, p_store_id uuid,
  p_invoice_id uuid default null, p_purposes jsonb default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_lot uuid; v_restrict jsonb;
begin
  if coalesce(p_amount,0) <= 0 then raise exception 'The exchange credit amount must be positive'; end if;
  -- Exchange credit keeps whatever usage eligibility it was configured with;
  -- with none given it behaves as unrestricted store credit.
  v_restrict := case when p_purposes is null then '{}'::jsonb
                     else jsonb_build_object('allowed_purposes', p_purposes,
                                             'allowed_voucher_ids', '[]'::jsonb,
                                             'source', 'exchange') end;
  v_lot := public.grant_customer_credit(p_customer_id, 'exchange', p_amount,
    'product_exchange', p_exchange_id, p_store_id, public.sg_today(), null,
    'Exchange credit', null, null, auth.uid(), v_restrict);
  update public.customer_credit_lots set source_record_id = coalesce(p_exchange_id, p_invoice_id)
   where id = v_lot;
  return v_lot;
end $function$;

-- ---------------------------------------------------------------------
-- 9. Refunding a credit purchase (package or bundle).
--    Only possible while none of the benefit has been used.
-- ---------------------------------------------------------------------
create or replace function public.credit_purchase_refund_blockers(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_b text[] := '{}'; v_n integer; v_cust uuid;
begin
  select customer_id into v_cust from public.invoices where id = p_invoice_id;

  -- Credit issued BY THIS SALE that has already been partly spent. The lot is
  -- identified from the sale record, never from the catalogue id, so another
  -- customer's purchase of the same package can never be mistaken for this one.
  select count(*) into v_n
    from public.credit_package_sales s
    join public.customer_credit_lots l on l.id = s.credit_lot_id
   where s.invoice_id = p_invoice_id
     and l.remaining_amount < l.original_amount;
  if v_n > 0 then v_b := array_append(v_b, 'Credit from this purchase has already been used'); end if;

  select count(*) into v_n
    from public.premium_bundle_sales s
    join public.customer_credit_lots l
      on l.id in (s.paid_credit_lot_id, s.bonus_credit_lot_id)
   where s.invoice_id = p_invoice_id
     and l.remaining_amount < l.original_amount;
  if v_n > 0 then v_b := array_append(v_b, 'Credit from this purchase has already been used'); end if;

  -- Reward vouchers from this sale that have been redeemed.
  select count(*) into v_n from public.customer_reward_vouchers crv
   where crv.status = 'redeemed'
     and (crv.source_id in (select id from public.premium_bundle_sales where invoice_id = p_invoice_id)
          or crv.entitlement_id in (
               select e.id from public.therapy_entitlements e
                join public.credit_package_sales s on s.customer_id = e.customer_id
               where s.invoice_id = p_invoice_id and e.earner_kind = 'credit_package'));
  if v_n > 0 then v_b := array_append(v_b, 'A reward voucher from this purchase has been redeemed'); end if;

  -- Package-derived reward units already claimed or activated.
  select count(*) into v_n from public.therapy_entitlements e
   where e.earner_kind = 'credit_package' and e.customer_id = v_cust
     and e.status not in ('pending_activation','cancelled')
     and exists (select 1 from public.credit_package_sales s
                  where s.invoice_id = p_invoice_id and s.customer_id = e.customer_id);
  if v_n > 0 then v_b := array_append(v_b, 'A reward unit from this purchase has already been claimed or activated'); end if;

  return jsonb_build_object('can_refund', array_length(v_b,1) is null, 'blockers', to_jsonb(v_b));
end $function$;

create or replace function public.refund_credit_purchase(p_invoice_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_chk jsonb;
  v_lot record; v_crv record; v_n integer := 0; v_credit numeric := 0;
  v_sale uuid; v_vouchers integer := 0; v_units integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can refund a credit purchase'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required'; end if;
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;

  v_chk := public.credit_purchase_refund_blockers(p_invoice_id);
  if not (v_chk->>'can_refund')::boolean then
    raise exception 'This purchase cannot be refunded: %',
      array_to_string(array(select jsonb_array_elements_text(v_chk->'blockers')), '; ');
  end if;

  -- Reverse only the lots THIS sale created, identified from the sale records.
  for v_lot in
    select l.* from public.credit_package_sales s
      join public.customer_credit_lots l on l.id = s.credit_lot_id
     where s.invoice_id = p_invoice_id and l.status = 'active'
    union all
    select l.* from public.premium_bundle_sales s
      join public.customer_credit_lots l
        on l.id in (s.paid_credit_lot_id, s.bonus_credit_lot_id)
     where s.invoice_id = p_invoice_id and l.status = 'active'
  loop
    v_credit := v_credit + v_lot.remaining_amount;
    perform public.reverse_credit_lot(v_lot.id, p_reason, 'Credit purchase refunded');
    v_n := v_n + 1;
  end loop;

  -- Cancel unclaimed reward units from this sale.
  update public.therapy_entitlements
     set status = 'cancelled'
   where customer_id = v_inv.customer_id
     and earner_kind = 'credit_package'
     and status = 'pending_activation'
     and exists (select 1 from public.credit_package_sales s
                  where s.invoice_id = p_invoice_id and s.customer_id = v_inv.customer_id);
  v_units := coalesce((select count(*) from public.therapy_entitlements
     where customer_id = v_inv.customer_id and earner_kind = 'credit_package'
       and status = 'cancelled'), 0);

  -- Cancel unredeemed reward vouchers from this sale and restore their stock.
  for v_crv in
    select crv.* from public.customer_reward_vouchers crv
     where crv.status = 'held'
       and (crv.source_id in (select id from public.premium_bundle_sales where invoice_id = p_invoice_id)
            or crv.entitlement_id in (
                 select e.id from public.therapy_entitlements e
                  where e.customer_id = v_inv.customer_id and e.earner_kind = 'credit_package'
                    and exists (select 1 from public.credit_package_sales s
                                 where s.invoice_id = p_invoice_id)))
  loop
    if v_crv.store_id is not null then
      update public.voucher_store_stock
         set current_qty = current_qty + v_crv.quantity, updated_at = now()
       where voucher_id = v_crv.voucher_id and store_id = v_crv.store_id;
    end if;
    update public.customer_reward_vouchers set status = 'revoked' where id = v_crv.id;
    v_vouchers := v_vouchers + v_crv.quantity;
  end loop;

  -- Reverse commission earned on this invoice (staff and both affiliate tiers).
  update public.commissions set status = 'reversed'
   where invoice_id = p_invoice_id and status in ('earned','blocked');
  update public.staff_commissions set status = 'reversed'
   where invoice_id = p_invoice_id and status in ('earned','blocked');

  perform public.write_audit_ex('invoices', p_invoice_id, 'credit_purchase_refunded', null,
    jsonb_build_object('credit_reversed', v_credit, 'lots', v_n,
      'vouchers_returned', v_vouchers, 'reason', p_reason), 'credit', p_reason, v_inv.store_id);

  return jsonb_build_object('success', true, 'credit_reversed', round(v_credit,2),
    'lots_reversed', v_n, 'vouchers_returned', v_vouchers,
    'note', 'Refund the original external payment using the normal refund flow.');
end $function$;

-- ---------------------------------------------------------------------
-- 10. Refunding a purchase that was funded by wallet credit.
--     The credit-funded part goes back to the very lots it came from —
--     never as cash. The external part is returned proportionally.
-- ---------------------------------------------------------------------
create or replace function public.refund_credit_funded_item(
  p_invoice_item_id uuid, p_amount numeric, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_it public.invoice_items%rowtype; v_inv public.invoices%rowtype;
  v_line_net numeric; v_credit numeric; v_external numeric;
  v_credit_share numeric; v_cash_share numeric;
  v_a record; v_take numeric; v_left numeric; v_wallet uuid; v_entry uuid;
  v_returned jsonb := '[]'::jsonb;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can refund a credit-funded purchase'; end if;
  select * into v_it from public.invoice_items where id = p_invoice_item_id;
  if not found then raise exception 'Invoice line not found'; end if;
  select * into v_inv from public.invoices where id = v_it.invoice_id;

  v_line_net := round(coalesce(v_it.line_total,0) - coalesce(v_it.line_discount,0), 2);
  if coalesce(p_amount,0) <= 0 or round(p_amount,2) > v_line_net then
    raise exception 'The refund amount must be between 0 and %', v_line_net; end if;

  v_credit := public.invoice_credit_funded(v_it.invoice_id, p_invoice_item_id);
  v_external := greatest(v_line_net - v_credit, 0);

  -- Split the refund in the same proportion the line was funded.
  if v_line_net > 0 then
    v_credit_share := round(round(p_amount,2) * (v_credit / v_line_net), 2);
  else
    v_credit_share := 0;
  end if;
  v_cash_share := round(round(p_amount,2) - v_credit_share, 2);

  if v_credit_share > 0 then
    v_wallet := public.ensure_customer_wallet(v_inv.customer_id);
    v_left := v_credit_share;
    -- Return to the original lots, largest contribution first.
    for v_a in
      select * from public.invoice_line_credit_allocations
       where invoice_item_id = p_invoice_item_id
         and amount > reversed_amount
       order by amount desc
       for update
    loop
      exit when v_left <= 0;
      v_take := least(v_a.amount - v_a.reversed_amount, v_left);
      if v_take <= 0 then continue; end if;

      -- The credit goes back into the very lot it came from. No expiry: the
      -- lot has no expiry field, so returned credit never expires.
      update public.customer_credit_lots
         set remaining_amount = remaining_amount + v_take,
             status = 'active', updated_at = now()
       where id = v_a.lot_id;

      insert into public.customer_credit_ledger (
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, reason, note, created_by, approved_by)
      values (v_wallet, v_inv.customer_id, 'reverse', v_a.category, v_take, v_a.lot_id,
        'invoice_refund', v_it.invoice_id, v_inv.store_id, p_reason,
        'Credit returned from a refund', auth.uid(), auth.uid())
      returning id into v_entry;

      update public.invoice_line_credit_allocations
         set reversed_amount = reversed_amount + v_take
       where id = v_a.id;

      v_returned := v_returned || jsonb_build_object('lot_id', v_a.lot_id,
        'category', v_a.category, 'amount', v_take);
      v_left := v_left - v_take;
    end loop;
  end if;

  perform public.write_audit_ex('invoice_items', p_invoice_item_id, 'credit_funded_refund', null,
    jsonb_build_object('amount', round(p_amount,2), 'to_credit', v_credit_share,
      'to_external', v_cash_share, 'reason', p_reason), 'credit', p_reason, v_inv.store_id);

  return jsonb_build_object('success', true,
    'refund_amount', round(p_amount,2),
    'returned_to_credit', v_credit_share,
    'refundable_externally', v_cash_share,
    'lots', v_returned,
    'note', 'The credit-funded portion was returned to its original lots and is not refundable as cash.');
end $function$;

notify pgrst, 'reload schema';
