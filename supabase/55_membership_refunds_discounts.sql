-- =====================================================================
-- ENERGIA — PHASE 7: REFUNDS, TOP-UPS & SAVE EARTH DISCOUNT
--
-- Adds: Save Earth Project discount (global default + per-invoice snapshot),
-- membership-line and product/therapy line refunds with commission reversal,
-- and mandatory top-up invoices when a refunded membership leaves member-priced
-- lines to reprice. Historical discounts on paid invoices are never rewritten.
--
-- NUMBERING: the spec names 50_membership_refunds_discounts.sql, but 50 is the
-- membership-management migration. This ships as 55 (50-54 precede it).
--
-- Additive + idempotent. Run AFTER 54.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 0. Supporting structures (created first; referenced by later sections).
-- =====================================================================

-- Refund records — never rewrite the original invoice; add refund rows.
create table if not exists public.invoice_refunds (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id),
  invoice_item_id uuid references public.invoice_items(id),
  amount numeric(12,2) not null default 0,
  reason text,
  kind text,                    -- 'membership' | 'product' | 'voucher' | 'promotion' | 'therapy' | 'whole'
  return_stock boolean,
  topup_invoice_id uuid references public.invoices(id),
  refunded_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_invrefund_invoice on public.invoice_refunds(invoice_id);
alter table public.invoice_refunds enable row level security;
drop policy if exists "read refunds" on public.invoice_refunds;
create policy "read refunds" on public.invoice_refunds for select to authenticated using (true);

-- Link a top-up invoice back to its origin.
alter table public.invoices add column if not exists topup_of_invoice_id uuid references public.invoices(id);
alter table public.invoices add column if not exists is_topup boolean not null default false;

-- Line-level-ish staff commission reversal. staff_commissions is invoice-level,
-- so we reverse a proportional share of the invoice's staff commission equal to
-- the refunded line's share of the invoice subtotal. If the whole membership is
-- refunded and it's the only line, this reverses all of it.
create or replace function public.reverse_staff_commission_line(p_invoice_item_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype; v_share numeric;
begin
  select * into v_li from public.invoice_items where id = p_invoice_item_id;
  if not found then return; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id;
  if coalesce(v_inv.subtotal,0) <= 0 then return; end if;
  v_share := least(1, greatest(0, (v_li.line_total) / v_inv.subtotal));
  -- Reduce each earned staff commission row for this invoice by the line's share;
  -- if it drops to ~0, mark reversed. (Preserves history via reversal_reason.)
  update public.staff_commissions
     set commission_amount = round(commission_amount * (1 - v_share), 2),
         status = case when round(commission_amount * (1 - v_share), 2) <= 0.005 then 'reversed'::commission_status else status end,
         reversed_at = case when round(commission_amount * (1 - v_share), 2) <= 0.005 then now() else reversed_at end,
         reversal_reason = case when round(commission_amount * (1 - v_share), 2) <= 0.005 then p_reason else reversal_reason end
   where invoice_id = v_inv.id and status = 'earned';
end $$;

-- Create a mandatory top-up invoice for a price difference. Non-stock single
-- line; earns normal Staff + Affiliate commission (may be blocked by eligibility)
-- when it is itself fully paid.
create or replace function public.create_topup_invoice(
  p_origin_invoice_id uuid, p_amount numeric, p_reason text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_origin public.invoices%rowtype; v_id uuid; v_no text;
begin
  if p_amount is null or p_amount <= 0 then return null; end if;
  select * into v_origin from public.invoices where id = p_origin_invoice_id;
  v_no := public.next_invoice_no();

  insert into public.invoices (invoice_no, store_id, customer_id, created_by, status,
    subtotal, discount_total, total_amount, paid_amount, is_topup, topup_of_invoice_id, notes)
  values (v_no, v_origin.store_id, v_origin.customer_id, auth.uid(), 'unpaid',
    p_amount, 0, p_amount, 0, true, p_origin_invoice_id,
    'Top-up for membership refund on ' || v_origin.invoice_no || ' — ' || p_reason)
  returning id into v_id;

  -- Single non-stock top-up line (priced at the difference; Own Product).
  insert into public.invoice_items (invoice_id, line_kind, product_id, quantity, unit_price, line_total,
    price_mode, price_source, store_id_snapshot, plan_name_snapshot)
  values (v_id, 'product', null, 1, p_amount, p_amount, 'non_member', 'topup', v_origin.store_id, 'Membership refund top-up');

  perform public.write_audit_ex('invoices', v_id, 'topup_invoice_created',
    null, jsonb_build_object('origin', v_origin.invoice_no, 'amount', p_amount), 'refunds', p_reason, v_origin.store_id);
  return v_id;
end $$;


-- =====================================================================
-- 1. Save Earth Project — global defaults (Owner/Manager editable).
-- =====================================================================
alter table public.app_settings add column if not exists save_earth_label text not null default 'Save Earth Project';
alter table public.app_settings add column if not exists save_earth_amount numeric(12,2) not null default 1.00;

-- Per-invoice snapshot (does not change global settings).
alter table public.invoices add column if not exists save_earth_applied boolean not null default false;
alter table public.invoices add column if not exists save_earth_label text;
alter table public.invoices add column if not exists save_earth_amount numeric(12,2) not null default 0;

create or replace function public.set_save_earth_defaults(p_label text, p_amount numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit the Save Earth defaults'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'Amount cannot be negative'; end if;
  update public.app_settings
     set save_earth_label = coalesce(nullif(trim(p_label),''), 'Save Earth Project'),
         save_earth_amount = p_amount, updated_at = now()
   where id = true;
  perform public.write_audit('app_settings', null, 'save_earth_defaults_set', null,
    jsonb_build_object('label', p_label, 'amount', p_amount));
end $$;

-- Apply / update / clear the Save Earth line on an UNPAID invoice.
-- Snapshot the global default at apply-time; per-invoice edits are allowed.
create or replace function public.set_invoice_save_earth(
  p_invoice_id uuid, p_applied boolean, p_label text default null, p_amount numeric default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_def public.app_settings%rowtype; v_label text; v_amount numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this store'; end if;
  if v_inv.status in ('paid','partially_paid','cancelled','refunded') or coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'Discounts cannot be changed after payment'; end if;

  select * into v_def from public.app_settings where id = true;
  if p_applied then
    v_label := coalesce(nullif(trim(p_label),''), v_def.save_earth_label, 'Save Earth Project');
    v_amount := coalesce(p_amount, v_def.save_earth_amount, 1);
    if v_amount < 0 then raise exception 'Save Earth amount cannot be negative'; end if;
  else
    v_label := null; v_amount := 0;
  end if;

  update public.invoices
     set save_earth_applied = p_applied, save_earth_label = v_label, save_earth_amount = v_amount
   where id = p_invoice_id;
  -- Rebuild discount_total to include Save Earth (once) + existing discounts,
  -- then recompute total floored at 0.
  perform public.refresh_invoice_discount_total(p_invoice_id);
  update public.invoices i
     set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0))
   where i.id = p_invoice_id;
end $$;

-- =====================================================================
-- 2. Make refresh_invoice_discount_total include Save Earth (once).
--    Re-create it additively: manual + line vouchers + whole voucher +
--    Save Earth. (Preserves the A4 model from 48b.)
-- =====================================================================
create or replace function public.refresh_invoice_discount_total(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_line_disc numeric; v_voucher_disc numeric := 0; v_total numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  select coalesce(sum(coalesce(line_discount,0)),0) into v_line_disc
    from public.invoice_items where invoice_id = p_invoice_id;
  if v_inv.discount_voucher_id is not null then
    v_voucher_disc := public.voucher_discount_amount(v_inv.discount_voucher_id,
      greatest(0, v_inv.subtotal - v_line_disc));
  end if;
  v_total := coalesce(v_inv.manual_discount,0) + v_line_disc + v_voucher_disc
             + case when v_inv.save_earth_applied then coalesce(v_inv.save_earth_amount,0) else 0 end;
  update public.invoices set discount_total = greatest(0, v_total) where id = p_invoice_id;
end $$;

-- =====================================================================
-- 3. Membership-line refund with commission reversal + reprice/top-up.
--    Owner/Manager direct; Staff/Admin go through request_invoice_action
--    (existing approval workflow). Only FULL membership-line refund.
-- =====================================================================
-- Method A: deduct the member/non-member price difference from the refund.
-- Method B: create a mandatory top-up invoice for the difference.
create or replace function public.refund_membership_line(
  p_invoice_id uuid, p_reason text, p_method text default 'deduct'   -- 'deduct' | 'topup'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_mline public.invoice_items%rowtype; v_memb public.customer_memberships%rowtype;
  v_diff numeric := 0; v_li record; v_pj jsonb; v_member_price numeric; v_nonmember_price numeric;
  v_refund_amt numeric; v_topup_id uuid; v_topup_no text; v_net_refund numeric; v_used_count integer;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can refund directly. Staff/Admin submit a request.'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A refund reason is required'; end if;
  if p_method not in ('deduct','topup') then raise exception 'Method must be deduct or topup'; end if;

  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.status <> 'paid' then raise exception 'Only a paid invoice''s membership can be refunded here'; end if;

  select * into v_mline from public.invoice_items where invoice_id = p_invoice_id and line_kind = 'membership' limit 1;
  if not found then raise exception 'This invoice has no membership line'; end if;

  -- The membership created by this invoice.
  select * into v_memb from public.customer_memberships where invoice_id = p_invoice_id and deleted_at is null limit 1;
  if not found then raise exception 'No membership found for this invoice'; end if;

  -- Block if the membership was already used to member-price ANOTHER paid invoice.
  select count(*) into v_used_count from public.invoice_items ii
    join public.invoices i on i.id = ii.invoice_id
   where i.customer_id = v_inv.customer_id and i.id <> p_invoice_id
     and i.status = 'paid' and ii.price_mode = 'member'
     and i.paid_at >= v_memb.start_date and i.paid_at::date <= coalesce(v_memb.expiry_date, i.paid_at::date);
  if v_used_count > 0 then
    raise exception 'This membership was already used to member-price % other paid invoice(s); it cannot be refunded', v_used_count; end if;

  -- Reprice this invoice's member-priced NON-membership lines to Non-Member and
  -- sum the price difference (what the customer should have paid without member pricing).
  for v_li in select * from public.invoice_items
               where invoice_id = p_invoice_id and line_kind in ('product','voucher','promotion','therapy')
                 and price_mode = 'member'
  loop
    v_nonmember_price := v_li.non_member_price_snapshot;
    if v_nonmember_price is not null then
      v_diff := v_diff + (v_nonmember_price - v_li.unit_price) * v_li.quantity;
    end if;
  end loop;

  -- The membership fee is refundable; the difference offsets it.
  v_refund_amt := v_mline.unit_price;

  -- Cancel the membership immediately.
  update public.customer_memberships set status = 'cancelled', cancelled_at = now(),
    cancel_reason = 'Membership refunded: ' || p_reason, updated_at = now()
   where id = v_memb.id;

  -- Reverse membership commissions (staff + affiliate) for this invoice.
  update public.commissions set status = 'reversed', reversal_reason = 'Membership refunded: ' || p_reason
   where invoice_item_id = v_mline.id and status in ('earned');
  perform public.reverse_staff_commission_line(v_mline.id, 'Membership refunded');

  if p_method = 'deduct' then
    v_net_refund := greatest(0, v_refund_amt - v_diff);
    if v_diff > v_refund_amt then
      -- Refund exhausted; remaining difference becomes a mandatory top-up.
      v_topup_id := public.create_topup_invoice(p_invoice_id, v_diff - v_refund_amt, p_reason);
    end if;
  else
    -- Method B: full refund, whole difference as a top-up.
    v_net_refund := v_refund_amt;
    if v_diff > 0 then v_topup_id := public.create_topup_invoice(p_invoice_id, v_diff, p_reason); end if;
  end if;

  -- Record the refund (money out) without rewriting the original invoice's
  -- historical discount/snapshot fields.
  insert into public.invoice_refunds (invoice_id, amount, reason, kind, refunded_by)
  values (p_invoice_id, v_net_refund, p_reason, 'membership', auth.uid())
  on conflict do nothing;

  perform public.write_audit_ex('invoices', p_invoice_id, 'membership_refunded',
    jsonb_build_object('membership', v_memb.id),
    jsonb_build_object('method', p_method, 'refund', v_net_refund, 'price_diff', v_diff, 'topup', v_topup_id),
    'refunds', p_reason, v_inv.store_id);

  return jsonb_build_object('refund_amount', v_net_refund, 'price_difference', v_diff,
    'topup_invoice_id', v_topup_id, 'membership_cancelled', true);
end $$;

-- =====================================================================
-- 4. Product / therapy line refund (line-level), commission reversal,
--    optional stock return. Original invoice stays locked.
-- =====================================================================
create or replace function public.refund_invoice_line(
  p_invoice_item_id uuid, p_reason text, p_return_stock boolean default true
) returns void language plpgsql security definer set search_path = public as $$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can refund directly. Staff/Admin submit a request.'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A refund reason is required'; end if;

  select * into v_li from public.invoice_items where id = p_invoice_item_id;
  if not found then raise exception 'Line not found'; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id for update;
  if v_inv.status <> 'paid' then raise exception 'Only paid invoices can have lines refunded'; end if;
  if v_li.line_kind = 'membership' then raise exception 'Use refund_membership_line for membership lines'; end if;

  -- Therapy: only before activation.
  if v_li.line_kind = 'therapy' then
    if exists (select 1 from public.purchased_therapy_entitlements
                where invoice_item_id = p_invoice_item_id and status in ('active','expired')) then
      raise exception 'Therapy cannot be refunded after activation'; end if;
    update public.purchased_therapy_entitlements set status = 'refunded', updated_at = now()
     where invoice_item_id = p_invoice_item_id and status in ('pending_activation','scheduled');
  end if;

  -- Return stock only for physical products, only if requested.
  if p_return_stock and v_li.line_kind = 'product' and v_li.product_id is not null then
    update public.store_inventory set current_qty = current_qty + v_li.quantity, updated_at = now()
     where store_id = v_inv.store_id and product_id = v_li.product_id;
    insert into public.stock_movements (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by)
    values (v_li.product_id, 'refund_return', v_inv.store_id, v_inv.id, v_li.quantity, 'Line refund — '||v_inv.invoice_no, auth.uid());
  end if;

  -- Reverse this line's commissions (affiliate + staff).
  update public.commissions set status = 'reversed', reversal_reason = 'Line refunded: ' || p_reason
   where invoice_item_id = p_invoice_item_id and status in ('earned');
  perform public.reverse_staff_commission_line(p_invoice_item_id, 'Line refunded');

  insert into public.invoice_refunds (invoice_id, invoice_item_id, amount, reason, kind, return_stock, refunded_by)
  values (v_inv.id, p_invoice_item_id, v_li.line_total - coalesce(v_li.line_discount,0), p_reason,
          v_li.line_kind, p_return_stock, auth.uid())
  on conflict do nothing;

  perform public.write_audit_ex('invoice_items', p_invoice_item_id, 'line_refunded',
    null, jsonb_build_object('kind', v_li.line_kind, 'return_stock', p_return_stock), 'refunds', p_reason, v_inv.store_id);
end $$;

notify pgrst, 'reload schema';
