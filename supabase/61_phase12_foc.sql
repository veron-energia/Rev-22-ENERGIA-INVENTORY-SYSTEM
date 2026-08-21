-- =====================================================================
-- ENERGIA — PHASE 12: FOC (FREE OF CHARGE)
--
-- Adds full and partial FOC to every sellable line kind:
--   product / voucher / promotion / membership / unlimited therapy,
--   plus rentals, exchange top-ups and refund top-up invoices.
--
-- CORE MODEL
-- ----------
-- A line keeps its FULL `quantity` (so stock, entitlements and bundle
-- components behave exactly as a paid sale) and gains `foc_quantity`.
--
--     line_gross  = what the line would have cost with no FOC
--     foc_amount  = round(line_gross * foc_quantity / quantity, 2)
--     line_total  = line_gross - foc_amount        <-- CHARGED value only
--
-- Because `line_total` now holds the charged value, every downstream
-- calculation inherits FOC correctly with no further change:
--   * subtotal / total_amount   -> exclude FOC        (money)
--   * line + invoice discounts  -> apply to paid value only
--   * earn_invoice_commission   -> base is line_total - line_discount => 0 on FOC
--   * earn_staff_commission     -> base is invoices.total_amount      => 0 on FOC
--   * invoice_required_stock    -> reads `quantity`   => FOC still deducts stock
--
-- `foc_amount` is the FOC value BEFORE any discount, and
-- `foc_original_unit_price` snapshots the unit price at the moment FOC
-- was applied, so a receipt/report can always show what was given away.
--
-- A fully-FOC invoice has total_amount = 0, cannot take a payment, and is
-- closed with confirm_foc_invoice() -> status 'completed_foc'.
-- A mixed invoice keeps a positive balance and settles through pay_invoice
-- as normal, charging the paid value only.
--
-- Additive + idempotent. Run AFTER 60.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 0. Invoice status for a fully-FOC, no-payment closure.
--    (Referenced only inside function bodies below — never in top-level
--     DDL/DML in this same transaction.)
-- ---------------------------------------------------------------------
do $$ begin alter type invoice_status add value if not exists 'completed_foc'; exception when others then null; end $$;

-- ---------------------------------------------------------------------
-- 1. Configurable FOC reasons.
-- ---------------------------------------------------------------------
create table if not exists public.foc_reasons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  label text not null,
  requires_note boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_foc_reasons_active on public.foc_reasons(is_active, sort_order);

alter table public.foc_reasons enable row level security;
drop policy if exists "read foc reasons" on public.foc_reasons;
create policy "read foc reasons" on public.foc_reasons for select to authenticated using (true);

-- Starter set (idempotent; owner can edit/deactivate/add more).
insert into public.foc_reasons (code, label, requires_note, sort_order) values
  ('staff_welfare',    'Staff Welfare',                 false, 10),
  ('customer_goodwill','Customer Goodwill / Service Recovery', false, 20),
  ('marketing_sample', 'Marketing Sample / Demo',       false, 30),
  ('warranty_replace', 'Warranty Replacement',          false, 40),
  ('promotional_gift', 'Promotional Gift',              false, 50),
  ('damaged_item',     'Damaged / Expired Stock',       true,  60),
  ('management_appr',  'Management Approval',           true,  70),
  ('other',            'Other',                         true,  99)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- 2. FOC columns.
-- ---------------------------------------------------------------------
-- Invoice lines
alter table public.invoice_items add column if not exists foc_quantity integer not null default 0;
alter table public.invoice_items add column if not exists is_foc boolean not null default false;          -- full-line FOC
alter table public.invoice_items add column if not exists foc_amount numeric(12,2) not null default 0;    -- FOC value BEFORE discounts
alter table public.invoice_items add column if not exists foc_original_unit_price numeric(12,2);          -- snapshot at time of FOC
alter table public.invoice_items add column if not exists foc_reason_id uuid references public.foc_reasons(id);
alter table public.invoice_items add column if not exists foc_reason text;
alter table public.invoice_items add column if not exists foc_by uuid references public.profiles(id);
alter table public.invoice_items add column if not exists foc_at timestamptz;

-- Invoice header rollups
alter table public.invoices add column if not exists has_foc boolean not null default false;
alter table public.invoices add column if not exists is_full_foc boolean not null default false;
alter table public.invoices add column if not exists foc_total numeric(12,2) not null default 0;
alter table public.invoices add column if not exists foc_confirmed_at timestamptz;
alter table public.invoices add column if not exists foc_confirmed_by uuid references public.profiles(id);

-- Rentals (fee waived; every other rental rule unchanged)
alter table public.rentals add column if not exists is_foc boolean not null default false;
alter table public.rentals add column if not exists foc_amount numeric(12,2) not null default 0;
alter table public.rentals add column if not exists foc_reason_id uuid references public.foc_reasons(id);
alter table public.rentals add column if not exists foc_reason text;
alter table public.rentals add column if not exists foc_by uuid references public.profiles(id);
alter table public.rentals add column if not exists foc_at timestamptz;

-- Exchange top-ups
alter table public.product_exchanges add column if not exists is_foc boolean not null default false;
alter table public.product_exchanges add column if not exists foc_amount numeric(12,2) not null default 0;
alter table public.product_exchanges add column if not exists foc_reason_id uuid references public.foc_reasons(id);
alter table public.product_exchanges add column if not exists foc_reason text;
alter table public.product_exchanges add column if not exists foc_by uuid references public.profiles(id);
alter table public.product_exchanges add column if not exists foc_at timestamptz;

-- FOC quantity can never exceed the line quantity (existing rows are all 0).
do $$ begin
  alter table public.invoice_items add constraint chk_invoice_items_foc_qty
    check (foc_quantity >= 0 and foc_quantity <= quantity);
exception when duplicate_object then null; when others then null; end $$;

create index if not exists idx_invoice_items_foc on public.invoice_items(invoice_id) where foc_quantity > 0;
create index if not exists idx_invoices_has_foc on public.invoices(has_foc) where has_foc = true;

-- ---------------------------------------------------------------------
-- 3. Reason management (Owner/Manager) + mandatory-reason resolver.
-- ---------------------------------------------------------------------
create or replace function public.upsert_foc_reason(
  p_code text, p_label text, p_requires_note boolean default false,
  p_sort_order integer default 100, p_is_active boolean default true,
  p_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_code text; v_label text;
begin
  if auth.uid() is not null and not public.is_owner_or_manager() then
    raise exception 'Only Owner or Manager can manage FOC reasons'; end if;
  v_code := nullif(trim(coalesce(p_code,'')),'');
  v_label := nullif(trim(coalesce(p_label,'')),'');
  if v_code is null then raise exception 'A FOC reason code is required'; end if;
  if v_label is null then raise exception 'A FOC reason label is required'; end if;

  if p_id is not null then
    update public.foc_reasons
       set code = v_code, label = v_label, requires_note = coalesce(p_requires_note,false),
           sort_order = coalesce(p_sort_order,100), is_active = coalesce(p_is_active,true),
           updated_at = now()
     where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'FOC reason not found'; end if;
  else
    insert into public.foc_reasons (code, label, requires_note, sort_order, is_active, created_by)
    values (v_code, v_label, coalesce(p_requires_note,false), coalesce(p_sort_order,100),
            coalesce(p_is_active,true), auth.uid())
    on conflict (code) do update
      set label = excluded.label, requires_note = excluded.requires_note,
          sort_order = excluded.sort_order, is_active = excluded.is_active, updated_at = now()
    returning id into v_id;
  end if;

  perform public.write_audit('foc_reasons', v_id, 'foc_reason_saved', null,
    jsonb_build_object('code', v_code, 'label', v_label, 'active', coalesce(p_is_active,true)));
  return v_id;
end $$;

create or replace function public.set_foc_reason_active(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_owner_or_manager() then
    raise exception 'Only Owner or Manager can manage FOC reasons'; end if;
  update public.foc_reasons set is_active = coalesce(p_active,true), updated_at = now() where id = p_id;
  if not found then raise exception 'FOC reason not found'; end if;
  perform public.write_audit('foc_reasons', p_id, 'foc_reason_active_changed', null,
    jsonb_build_object('active', p_active));
end $$;

create or replace function public.active_foc_reasons()
returns table (id uuid, code text, label text, requires_note boolean, sort_order integer)
language sql stable security definer set search_path = public as $$
  select id, code, label, requires_note, sort_order
  from public.foc_reasons where is_active = true order by sort_order, label
$$;

-- Mandatory FOC reason. Returns the resolved human-readable reason text.
-- A reason is ALWAYS required; reasons flagged requires_note also demand a note.
create or replace function public.foc_reason_resolve(p_reason_id uuid, p_reason_text text)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_r public.foc_reasons%rowtype; v_note text;
begin
  v_note := nullif(trim(coalesce(p_reason_text,'')),'');
  if p_reason_id is null and v_note is null then
    raise exception 'A FOC reason is required';
  end if;
  if p_reason_id is null then
    return v_note;   -- free-text reason
  end if;
  select * into v_r from public.foc_reasons where id = p_reason_id;
  if not found then raise exception 'FOC reason not found'; end if;
  if not v_r.is_active then raise exception 'FOC reason "%" is no longer active', v_r.label; end if;
  if v_r.requires_note and v_note is null then
    raise exception 'FOC reason "%" requires an explanatory note', v_r.label;
  end if;
  return case when v_note is null then v_r.label else v_r.label || ' — ' || v_note end;
end $$;

-- =====================================================================
-- 4. Invoice FOC rollup + money rebuild.
--    line_total already holds the CHARGED value, so subtotal/discount/
--    total follow the existing A4 money model untouched.
-- =====================================================================
create or replace function public.recalc_invoice_foc(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_foc numeric; v_sub numeric;
  v_charged_lines integer; v_foc_lines integer;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  select coalesce(sum(foc_amount),0), coalesce(sum(line_total),0)
    into v_foc, v_sub
    from public.invoice_items where invoice_id = p_invoice_id;

  select count(*) filter (where foc_quantity > 0),
         count(*) filter (where coalesce(line_total,0) > 0)
    into v_foc_lines, v_charged_lines
    from public.invoice_items where invoice_id = p_invoice_id;

  update public.invoices
     set subtotal = v_sub,
         foc_total = v_foc,
         has_foc = (v_foc_lines > 0),
         is_full_foc = (v_foc_lines > 0 and v_charged_lines = 0)
   where id = p_invoice_id;

  -- Rebuild discounts on the PAID value only, then the total.
  if v_inv.manual_discount is not null then
    perform public.refresh_invoice_discount_total(p_invoice_id);
  end if;
  -- Discounts can never exceed the charged value.
  update public.invoices set discount_total = least(coalesce(discount_total,0), v_sub)
   where id = p_invoice_id;
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0))
   where i.id = p_invoice_id;
end $$;

-- =====================================================================
-- 5. Apply / remove FOC on an existing invoice line.
--    Staff may apply FOC directly (no approval step), on any line kind,
--    for any invoice that has not yet been settled.
-- =====================================================================
create or replace function public.apply_line_foc(
  p_invoice_item_id uuid,
  p_foc_quantity integer default null,      -- null or >= quantity => full FOC
  p_reason_id uuid default null,
  p_reason_text text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype;
  v_gross numeric; v_foc_qty integer; v_foc_amt numeric; v_new_total numeric;
  v_reason text; v_role user_role;
begin
  select * into v_li from public.invoice_items where id = p_invoice_item_id for update;
  if not found then raise exception 'Invoice line not found'; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;

  v_role := public.current_user_role();
  if auth.uid() is not null then
    if v_role is null then raise exception 'No profile for current user'; end if;
    if v_role = 'inventory_manager' then
      raise exception 'Inventory Manager cannot apply FOC'; end if;
    if not public.user_has_store_access(v_inv.store_id) then
      raise exception 'You do not have access to this invoice''s store'; end if;
  end if;

  if v_inv.deleted_at is not null then raise exception 'Invoice has been deleted'; end if;
  if v_inv.status in ('paid','cancelled','refunded','completed_foc') then
    raise exception 'FOC cannot be changed on a % invoice', v_inv.status; end if;
  if v_inv.locked_at is not null then raise exception 'Invoice is locked'; end if;

  -- Mandatory reason (validated before anything is written).
  v_reason := public.foc_reason_resolve(p_reason_id, p_reason_text);

  v_foc_qty := coalesce(p_foc_quantity, v_li.quantity);
  if v_foc_qty <= 0 then raise exception 'FOC quantity must be greater than zero'; end if;
  if v_foc_qty > v_li.quantity then
    raise exception 'FOC quantity (%) cannot exceed the line quantity (%)', v_foc_qty, v_li.quantity; end if;

  -- Gross = current charged value + any FOC already on the line.
  v_gross := coalesce(v_li.line_total,0) + coalesce(v_li.foc_amount,0);
  v_foc_amt := round(v_gross * v_foc_qty::numeric / nullif(v_li.quantity,0)::numeric, 2);
  v_new_total := round(v_gross - v_foc_amt, 2);

  update public.invoice_items
     set foc_quantity = v_foc_qty,
         is_foc = (v_foc_qty = quantity),
         foc_amount = v_foc_amt,
         foc_original_unit_price = coalesce(foc_original_unit_price, unit_price),
         foc_reason_id = p_reason_id,
         foc_reason = v_reason,
         foc_by = auth.uid(),
         foc_at = now(),
         line_total = v_new_total,
         -- Discounts apply to the PAID value only.
         line_discount = case when line_voucher_id is not null
                              then public.voucher_discount_amount(line_voucher_id, v_new_total)
                              else line_discount end
   where id = p_invoice_item_id;

  perform public.recalc_invoice_foc(v_li.invoice_id);
  select * into v_inv from public.invoices where id = v_li.invoice_id;

  perform public.write_audit_ex('invoice_items', p_invoice_item_id, 'foc_applied',
    jsonb_build_object('line_total', v_li.line_total, 'foc_quantity', v_li.foc_quantity,
                       'foc_amount', v_li.foc_amount),
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'line_kind', v_li.line_kind,
                       'quantity', v_li.quantity, 'foc_quantity', v_foc_qty,
                       'foc_amount', v_foc_amt, 'line_total', v_new_total,
                       'full_foc', (v_foc_qty = v_li.quantity)),
    'foc', v_reason, v_inv.store_id);

  return jsonb_build_object('success', true, 'foc_quantity', v_foc_qty, 'foc_amount', v_foc_amt,
    'line_total', v_new_total, 'invoice_total', v_inv.total_amount,
    'invoice_foc_total', v_inv.foc_total, 'is_full_foc', v_inv.is_full_foc);
end $$;

create or replace function public.remove_line_foc(p_invoice_item_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype; v_gross numeric;
begin
  select * into v_li from public.invoice_items where id = p_invoice_item_id for update;
  if not found then raise exception 'Invoice line not found'; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id for update;

  if auth.uid() is not null then
    if public.current_user_role() = 'inventory_manager' then
      raise exception 'Inventory Manager cannot change FOC'; end if;
    if not public.user_has_store_access(v_inv.store_id) then
      raise exception 'You do not have access to this invoice''s store'; end if;
  end if;
  if v_inv.status in ('paid','cancelled','refunded','completed_foc') then
    raise exception 'FOC cannot be changed on a % invoice', v_inv.status; end if;
  if coalesce(v_li.foc_quantity,0) = 0 then raise exception 'This line has no FOC to remove'; end if;

  v_gross := coalesce(v_li.line_total,0) + coalesce(v_li.foc_amount,0);

  update public.invoice_items
     set foc_quantity = 0, is_foc = false, foc_amount = 0,
         foc_reason_id = null, foc_reason = null, foc_by = null, foc_at = null,
         line_total = v_gross,
         line_discount = case when line_voucher_id is not null
                              then public.voucher_discount_amount(line_voucher_id, v_gross)
                              else line_discount end
   where id = p_invoice_item_id;

  perform public.recalc_invoice_foc(v_li.invoice_id);
  select * into v_inv from public.invoices where id = v_li.invoice_id;

  perform public.write_audit_ex('invoice_items', p_invoice_item_id, 'foc_removed',
    jsonb_build_object('foc_quantity', v_li.foc_quantity, 'foc_amount', v_li.foc_amount),
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'line_total', v_gross),
    'foc', p_reason, v_inv.store_id);

  return jsonb_build_object('success', true, 'line_total', v_gross,
    'invoice_total', v_inv.total_amount, 'is_full_foc', v_inv.is_full_foc);
end $$;

-- =====================================================================
-- 6. create_invoice — FOC-aware.
--    Same signature (no overload risk). Each item in p_items may carry:
--        "foc_quantity": <int>     (partial FOC; omit or 0 for none)
--        "is_foc": true            (shorthand for full-line FOC)
--        "foc_reason_id": <uuid>   and/or "foc_reason": <text>
--    Every validation branch from migration 54 is preserved verbatim;
--    only the FOC parsing, the charged-value maths and the new snapshot
--    columns are added.
-- =====================================================================
-- Retire two obsolete create_invoice overloads left behind by earlier phases
-- (6-arg from migration 00, 7-arg from migration 17). All three matched a
-- 6-argument call, making it ambiguous — "function is not unique". The app
-- always passes all 8 named parameters, so only the 8-arg version is real.
drop function if exists public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text);
drop function if exists public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid);

create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null,
  p_discount_voucher_id uuid default null, p_service_staff jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_promo_id uuid;
  v_qty integer; v_price numeric; v_subtotal numeric := 0; v_line_total numeric;
  v_invoice_id uuid; v_invoice_no text; v_manual numeric := coalesce(p_discount_total,0);
  v_has_promo boolean := false; v_promo public.promotions%rowtype;
  v_line_voucher uuid; v_line_disc numeric; v_line_disc_sum numeric := 0;
  v_lv public.vouchers%rowtype; v_discount numeric;
  v_grp record; v_sel jsonb; v_opt jsonb; v_provided integer; v_required integer;
  v_item_id uuid; v_sel_group uuid; v_ok boolean; v_topup numeric;
  v_ptype text; v_third_sum numeric := 0; v_discountable numeric; v_wbase numeric;
  v_ss jsonb; v_ss_id uuid; v_ss_role user_role;
  v_ms jsonb; v_is_member boolean; v_membership_count integer := 0;
  v_plan_id uuid; v_mp jsonb; v_member_id text; v_owned_id text; v_is_renewal boolean := false;
  v_mode_ovr text; v_ovr_reason text; v_pj jsonb; v_use_member boolean; v_mode text;
  v_therapy_pkg uuid; v_therapy_name text; v_therapy_months integer;
  -- FOC additions
  v_foc_qty integer; v_foc_amt numeric; v_gross numeric;
  v_foc_rid uuid; v_foc_rtext text; v_foc_resolved text; v_foc_total numeric := 0;
begin
  if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if public.current_user_role() = 'inventory_manager'
     and exists (select 1 from jsonb_array_elements(p_items) x
                  where coalesce((x->>'foc_quantity')::integer,0) > 0 or coalesce((x->>'is_foc')::boolean,false)) then
    raise exception 'Inventory Manager cannot apply FOC';
  end if;

  v_ms := public.customer_membership_status(p_customer_id);
  select count(*) into v_membership_count
    from jsonb_array_elements(p_items) x where coalesce(x->>'kind','product') = 'membership';
  if v_membership_count > 1 then raise exception 'Only one membership line is allowed per invoice'; end if;
  v_is_member := coalesce((v_ms->>'is_member')::boolean, false) or v_membership_count = 1;

  if v_membership_count = 1 then
    if coalesce((v_ms->>'has_future_renewal')::boolean, false) then
      raise exception 'This customer already has a scheduled renewal'; end if;
    v_is_renewal := coalesce((v_ms->>'is_member')::boolean, false);
    select member_id into v_owned_id from public.member_ids where customer_id = p_customer_id;
  end if;

  -- PASS 1: validate + price + accumulate CHARGED value.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;
    v_mode_ovr := nullif(v_item->>'price_mode_override','');
    v_ovr_reason := nullif(trim(coalesce(v_item->>'override_reason','')),'');
    if v_mode_ovr is not null and v_mode_ovr not in ('member','non_member') then
      raise exception 'Invalid price mode override'; end if;
    if v_mode_ovr is not null and v_ovr_reason is null then
      raise exception 'An override reason is required when overriding a line price mode'; end if;
    v_use_member := coalesce(v_mode_ovr = 'member', v_is_member);

    -- FOC parsing + mandatory reason.
    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);
    if coalesce((v_item->>'is_foc')::boolean,false) then v_foc_qty := v_qty; end if;
    if v_foc_qty < 0 then raise exception 'FOC quantity cannot be negative'; end if;
    if v_foc_qty > v_qty then
      raise exception 'FOC quantity (%) cannot exceed the line quantity (%)', v_foc_qty, v_qty; end if;
    if v_foc_qty > 0 then
      v_foc_rid := nullif(v_item->>'foc_reason_id','')::uuid;
      v_foc_rtext := nullif(trim(coalesce(v_item->>'foc_reason','')),'');
      perform public.foc_reason_resolve(v_foc_rid, v_foc_rtext);
    end if;

    if v_kind = 'membership' then
      if v_qty <> 1 then raise exception 'A membership line must have quantity 1'; end if;
      if v_mode_ovr is not null then raise exception 'Member/Non-Member override does not apply to a membership line'; end if;
      v_plan_id := (v_item->>'plan_id')::uuid;
      v_mp := public.membership_price_for(p_store_id, v_plan_id);
      if not coalesce((v_mp->>'found')::boolean,false) then raise exception 'Membership plan not found'; end if;
      if coalesce((v_mp->>'is_system')::boolean,false) or coalesce((v_mp->>'is_complimentary')::boolean,false) then
        raise exception 'Plan "%" is protected and cannot be sold', v_mp->>'plan_name'; end if;
      if not coalesce((v_mp->>'is_active')::boolean,false) then
        raise exception 'Plan "%" is not active', v_mp->>'plan_name'; end if;
      if not coalesce((v_mp->>'available')::boolean,false) or (v_mp->>'fee') is null then
        raise exception 'Plan "%" has no active price at this store', v_mp->>'plan_name'; end if;

      v_member_id := nullif(trim(coalesce(v_item->>'member_id','')),'');
      if v_is_renewal then
        if v_member_id is not null and v_owned_id is not null and v_member_id <> v_owned_id then
          raise exception 'Renewal must keep the existing Member ID (%)', v_owned_id; end if;
      elsif v_member_id is not null then
        if not public.member_id_available(v_member_id, p_customer_id) then
          raise exception 'Member ID % is already taken', v_member_id; end if;
      end if;
      v_gross := (v_mp->>'fee')::numeric;

    elsif v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;
      if not v_is_member and v_mode_ovr is null then
        raise exception 'Promotions are for members only. Add a membership to this invoice or apply a manual override.'; end if;

      for v_grp in select * from public.promotion_choice_groups where promotion_id = v_promo_id
      loop
        v_required := v_grp.choose_qty * v_qty;
        v_provided := 0;
        for v_sel in select * from jsonb_array_elements(coalesce(v_item->'selections','[]'::jsonb))
        loop
          if (v_sel->>'group_id')::uuid = v_grp.id then
            for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
            loop
              if coalesce((v_opt->>'quantity')::integer,0) <= 0 then continue; end if;
              if v_grp.item_kind = 'voucher' then
                select exists (
                  select 1 from public.promotion_choice_options o
                  where o.group_id = v_grp.id
                    and (v_opt->>'voucher_id') is not null and o.voucher_id = (v_opt->>'voucher_id')::uuid
                ) into v_ok;
                if not v_ok then raise exception 'A selected voucher does not belong to choice group "%"', v_grp.label; end if;
              else
                if (v_opt->>'product_id') is null then raise exception 'Choice group "%" expects product selections', v_grp.label; end if;
                select exists (
                  select 1 from public.store_product_prices
                  where store_id = p_store_id and product_id = (v_opt->>'product_id')::uuid
                    and is_active = true and deleted_at is null
                ) into v_ok;
                if not v_ok then
                  raise exception 'Product "%" has no price at this store, so it cannot be chosen in "%"',
                    (select name from public.products where id = (v_opt->>'product_id')::uuid), v_grp.label;
                end if;
              end if;
              v_provided := v_provided + (v_opt->>'quantity')::integer;
            end loop;
          end if;
        end loop;
        if v_provided <> v_required then
          raise exception 'Choice group "%" requires % selection(s), got %', v_grp.label, v_required, v_provided;
        end if;
      end loop;

      v_pj := public.promotion_price_for(p_store_id, v_promo_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_promo.name,
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections', v_use_member);
      v_gross := ((v_pj->>'price')::numeric * v_qty) + v_topup;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      perform 1 from public.vouchers where id = v_voucher_id and is_active = true and deleted_at is null;
      if not found then raise exception 'Voucher not found or inactive'; end if;
      v_pj := public.voucher_price_for(p_store_id, v_voucher_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Voucher "%" is missing its % price at this store',
          (select name from public.vouchers where id = v_voucher_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    elsif v_kind = 'therapy' then
      if v_qty <> 1 then raise exception 'A therapy line must have quantity 1'; end if;
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      perform 1 from public.unlimited_therapy_packages where id = v_therapy_pkg and is_active = true and deleted_at is null;
      if not found then raise exception 'Therapy package not found or inactive'; end if;
      if exists (select 1 from public.purchased_therapy_entitlements
                  where customer_id = p_customer_id and package_id = v_therapy_pkg
                    and status in ('active','scheduled','pending_activation')) then
        raise exception 'This customer already has a current entitlement for this therapy package'; end if;
      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Therapy package "%" is missing its % price at this store',
          (select name from public.unlimited_therapy_packages where id = v_therapy_pkg),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    else
      v_product_id := (v_item->>'product_id')::uuid;
      select p.product_type::text into v_ptype from public.products p where p.id = v_product_id;
      v_pj := public.product_price_for(p_store_id, v_product_id, v_use_member);
      if not coalesce((v_pj->>'found')::boolean,false) then
        raise exception 'No price set for "%" in this store',
          (select name from public.products where id = v_product_id); end if;
      if v_mode_ovr is null and not coalesce((v_pj->>'eligible')::boolean,false) then
        raise exception 'Product "%" is % — not sellable to this customer without a manual override',
          (select name from public.products where id = v_product_id),
          replace(v_pj->>'eligibility','_',' '); end if;
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Product "%" is missing its % price at this store',
          (select name from public.products where id = v_product_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price * v_qty;
    end if;

    -- FOC split (uniform across every line kind).
    v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
    v_line_total := round(v_gross - v_foc_amt, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_foc_total := v_foc_total + v_foc_amt;

    -- Third-party + per-line voucher rules operate on the CHARGED value.
    if v_kind not in ('membership','promotion','voucher','therapy') then
      if v_ptype = 'third_party' then v_third_sum := v_third_sum + v_line_total; end if;
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      if v_line_voucher is not null then
        if v_ptype = 'third_party' then
          raise exception 'Discounts cannot be applied to third-party products ("%")',
            (select name from public.products where id = v_product_id);
        end if;
        select * into v_lv from public.vouchers where id = v_line_voucher and deleted_at is null;
        if not found then raise exception 'Line voucher not found'; end if;
        if v_lv.voucher_kind = 'normal' then raise exception 'Voucher "%" is not a discount voucher', v_lv.name; end if;
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
        v_line_disc_sum := v_line_disc_sum + v_line_disc;
      end if;
    end if;
  end loop;

  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;

  -- Discounts apply to the paid value only (v_subtotal is already net of FOC).
  v_discountable := v_subtotal - v_third_sum;
  v_discount := v_manual + v_line_disc_sum;
  if p_discount_voucher_id is not null then
    v_wbase := v_discountable - v_manual - v_line_disc_sum;
    if v_wbase < 0 then v_wbase := 0; end if;
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_wbase);
  end if;
  if v_discount > v_discountable then v_discount := v_discountable; end if;
  if v_discount < 0 then v_discount := 0; end if;

  v_invoice_no := public.next_invoice_no();
  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, manual_discount, total_amount, paid_amount, notes, discount_voucher_id,
     foc_total, has_foc, is_full_foc)
  values (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
          v_subtotal, v_discount, v_manual, v_subtotal - v_discount, 0, p_notes, p_discount_voucher_id,
          v_foc_total, v_foc_total > 0, (v_foc_total > 0 and v_subtotal <= 0))
  returning id into v_invoice_id;

  for v_ss in select * from jsonb_array_elements(coalesce(p_service_staff, '[]'::jsonb))
  loop
    v_ss_id := (v_ss#>>'{}')::uuid;
    if v_ss_id is null then continue; end if;
    select role into v_ss_role from public.profiles where id = v_ss_id and is_active = true and deleted_at is null;
    if v_ss_role is null then raise exception 'A selected service staff was not found or is inactive'; end if;
    if v_ss_role not in ('owner','manager','staff') then
      raise exception 'Service staff must be Owner, Manager, or Staff (got %)', v_ss_role;
    end if;
    insert into public.invoice_service_staff (invoice_id, staff_id)
    values (v_invoice_id, v_ss_id) on conflict (invoice_id, staff_id) do nothing;
  end loop;

  -- PASS 2: insert lines with permanent snapshots (incl. FOC snapshots).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    v_mode_ovr := nullif(v_item->>'price_mode_override','');
    v_ovr_reason := nullif(trim(coalesce(v_item->>'override_reason','')),'');
    v_use_member := coalesce(v_mode_ovr = 'member', v_is_member);
    v_mode := case when v_use_member then 'member' else 'non_member' end;

    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);
    if coalesce((v_item->>'is_foc')::boolean,false) then v_foc_qty := v_qty; end if;
    v_foc_rid := nullif(v_item->>'foc_reason_id','')::uuid;
    v_foc_rtext := nullif(trim(coalesce(v_item->>'foc_reason','')),'');
    v_foc_resolved := case when v_foc_qty > 0 then public.foc_reason_resolve(v_foc_rid, v_foc_rtext) else null end;

    if v_kind = 'membership' then
      v_plan_id := (v_item->>'plan_id')::uuid;
      v_mp := public.membership_price_for(p_store_id, v_plan_id);
      v_price := (v_mp->>'fee')::numeric;
      v_gross := v_price;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      v_member_id := case when v_is_renewal then v_owned_id
                          else nullif(trim(coalesce(v_item->>'member_id','')),'') end;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total,
         membership_plan_id, price_source, price_source_id, store_id_snapshot,
         plan_name_snapshot, plan_months_snapshot, member_id_snapshot, original_price,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'membership', null, 1, v_price, v_line_total,
              v_plan_id, 'membership', (v_mp->>'source_id')::uuid, p_store_id,
              v_mp->>'plan_name', (v_mp->>'duration_months')::integer, v_member_id, v_price,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
      if not v_is_renewal and v_member_id is not null then
        perform public.reserve_member_id(v_member_id, p_customer_id, v_invoice_id);
      end if;

    elsif v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      v_pj := public.promotion_price_for(p_store_id, v_promo_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections', v_use_member);
      v_gross := (v_price * v_qty) + v_topup;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total, topup_amount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, v_line_total, v_topup,
              v_mode, case when v_mode_ovr is null then 'promotion' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      returning id into v_item_id;

      for v_sel in select * from jsonb_array_elements(coalesce(v_item->'selections','[]'::jsonb))
      loop
        v_sel_group := (v_sel->>'group_id')::uuid;
        for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
        loop
          if coalesce((v_opt->>'quantity')::integer,0) <= 0 then continue; end if;
          insert into public.invoice_promotion_selections (invoice_item_id, group_id, product_id, voucher_id, quantity)
          values (v_item_id, v_sel_group,
                  nullif(v_opt->>'product_id','')::uuid, nullif(v_opt->>'voucher_id','')::uuid,
                  (v_opt->>'quantity')::integer);
        end loop;
      end loop;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      v_pj := public.voucher_price_for(p_store_id, v_voucher_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_line_total,
              v_mode, case when v_mode_ovr is null then 'voucher' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);

    elsif v_kind = 'therapy' then
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      select name, duration_months into v_therapy_name, v_therapy_months
        from public.unlimited_therapy_packages where id = v_therapy_pkg;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         plan_name_snapshot, plan_months_snapshot,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'therapy', null, v_therapy_pkg, 1, v_price, v_line_total,
              v_mode, case when v_mode_ovr is null then 'therapy' else 'manual_override' end,
              v_therapy_pkg, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_therapy_name, v_therapy_months,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      v_pj := public.product_price_for(p_store_id, v_product_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total, line_voucher_id, line_discount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total, v_line_voucher, v_line_disc,
              v_mode, case when v_mode_ovr is null then 'product' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo, 'third_party_total', v_third_sum,
                       'is_member_pricing', v_is_member, 'has_membership_line', v_membership_count = 1,
                       'is_renewal', v_is_renewal,
                       'foc_total', v_foc_total, 'is_full_foc', (v_foc_total > 0 and v_subtotal <= 0)));
  if v_foc_total > 0 then
    perform public.write_audit_ex('invoices', v_invoice_id, 'invoice_foc_created', null,
      jsonb_build_object('invoice_no', v_invoice_no, 'foc_total', v_foc_total,
                         'charged_total', v_subtotal - v_discount),
      'foc', null, p_store_id);
  end if;
  return v_invoice_id;
end; $$;

-- =====================================================================
-- 7. reprice_invoice_lines — FOC-aware.
--    pay_invoice reprices before taking money; without this the FOC split
--    would be overwritten by `line_total = price * quantity`.
--    Gross is repriced, then the FOC share is re-derived from the SAME
--    foc_quantity so the customer keeps exactly what was given free.
-- =====================================================================
create or replace function public.reprice_invoice_lines(p_invoice_id uuid, p_is_member boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_li record; v_pj jsonb; v_new numeric;
  v_changes jsonb := '[]'::jsonb; v_subtotal numeric; v_mode text;
  v_old_line_disc numeric; v_new_line_disc numeric;
  v_old_sub numeric; v_old_disc numeric; v_old_total numeric;
  v_line_member boolean; v_new_topup numeric;
  v_gross numeric; v_foc numeric; v_charged numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  v_mode := case when p_is_member then 'member' else 'non_member' end;
  v_old_sub := v_inv.subtotal; v_old_disc := v_inv.discount_total; v_old_total := v_inv.total_amount;
  select coalesce(sum(coalesce(line_discount,0)),0) into v_old_line_disc
    from public.invoice_items where invoice_id = p_invoice_id;

  for v_li in
    select ii.*, p.name as pname, pr.name as prname, vo.name as voname
      from public.invoice_items ii
      left join public.products p on p.id = ii.product_id
      left join public.promotions pr on pr.id = ii.promotion_id
      left join public.vouchers vo on vo.id = ii.voucher_id
     where ii.invoice_id = p_invoice_id
       and ii.line_kind in ('product','voucher','promotion')
       and coalesce(ii.price_overridden,false) = false
       -- Synthetic lines have no catalogue item to reprice against. The
       -- refund top-up line from migration 55 is line_kind='product' with a
       -- NULL product_id; repricing it raised 'Product "<NULL>" has no price
       -- row at this store', which made EVERY top-up invoice unpayable.
       and coalesce(ii.price_source,'') <> 'topup'
       and not (ii.line_kind = 'product' and ii.product_id is null)
       and not (ii.line_kind = 'voucher' and ii.voucher_id is null)
       and not (ii.line_kind = 'promotion' and ii.promotion_id is null)
  loop
    v_line_member := p_is_member;

    if v_li.line_kind = 'product' then
      v_pj := public.product_price_for(v_inv.store_id, v_li.product_id, v_line_member);
      if not coalesce((v_pj->>'found')::boolean,false) then raise exception 'Product "%" has no price row at this store', v_li.pname; end if;
      if not coalesce((v_pj->>'eligible')::boolean,false) then
        raise exception 'Product "%" is % — not sellable to this customer without a manual override', v_li.pname, replace(v_pj->>'eligibility','_',' '); end if;
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Product "%" is missing its % price at this store', v_li.pname, case when v_line_member then 'Member' else 'Non-Member' end; end if;
      v_new := (v_pj->>'price')::numeric;
      if v_new is distinct from v_li.unit_price or v_li.price_mode is distinct from v_mode then
        v_changes := v_changes || jsonb_build_object('item_id', v_li.id, 'kind','product','name', v_li.pname,
          'old_price', v_li.unit_price, 'new_price', v_new, 'reason','price mode changed');
      end if;
      v_gross := v_new * v_li.quantity;
      v_foc := case when coalesce(v_li.foc_quantity,0) > 0
                    then round(v_gross * v_li.foc_quantity::numeric / v_li.quantity::numeric, 2) else 0 end;
      v_charged := round(v_gross - v_foc, 2);
      update public.invoice_items set unit_price = v_new,
        line_total = v_charged, foc_amount = v_foc,
        line_discount = case when line_voucher_id is not null then public.voucher_discount_amount(line_voucher_id, v_charged) else line_discount end,
        price_mode = v_mode, price_source='product', price_source_id=(v_pj->>'source_id')::uuid,
        store_id_snapshot = v_inv.store_id,
        member_price_snapshot=(v_pj->>'member_price')::numeric, non_member_price_snapshot=(v_pj->>'non_member_price')::numeric,
        original_price = coalesce(original_price, v_li.unit_price)
       where id = v_li.id;

    elsif v_li.line_kind = 'voucher' then
      v_pj := public.voucher_price_for(v_inv.store_id, v_li.voucher_id, v_line_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Voucher "%" is missing its % price at this store', v_li.voname, case when v_line_member then 'Member' else 'Non-Member' end; end if;
      v_new := (v_pj->>'price')::numeric;
      if v_new is distinct from v_li.unit_price or v_li.price_mode is distinct from v_mode then
        v_changes := v_changes || jsonb_build_object('item_id', v_li.id, 'kind','voucher','name', v_li.voname,
          'old_price', v_li.unit_price, 'new_price', v_new, 'reason','price mode changed'); end if;
      v_gross := v_new * v_li.quantity;
      v_foc := case when coalesce(v_li.foc_quantity,0) > 0
                    then round(v_gross * v_li.foc_quantity::numeric / v_li.quantity::numeric, 2) else 0 end;
      v_charged := round(v_gross - v_foc, 2);
      update public.invoice_items set unit_price=v_new, line_total=v_charged, foc_amount=v_foc,
        price_mode=v_mode, price_source='voucher', price_source_id=(v_pj->>'source_id')::uuid,
        store_id_snapshot=v_inv.store_id,
        member_price_snapshot=(v_pj->>'member_price')::numeric, non_member_price_snapshot=(v_pj->>'non_member_price')::numeric,
        original_price=coalesce(original_price, v_li.unit_price)
       where id = v_li.id;

    else -- promotion
      v_pj := public.promotion_price_for(v_inv.store_id, v_li.promotion_id, v_line_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_li.prname, case when v_line_member then 'Member' else 'Non-Member' end; end if;
      perform public.assert_promotion_choices_ok(v_li.id, v_inv.store_id, v_line_member, coalesce(v_li.price_overridden,false));
      v_new := (v_pj->>'price')::numeric;
      v_new_topup := public.promotion_selections_topup(
        v_li.promotion_id, v_inv.store_id,
        (select coalesce(jsonb_agg(jsonb_build_object('group_id', g.group_id,
                   'options', g.options)), '[]'::jsonb)
           from (select s.group_id,
                        jsonb_agg(jsonb_build_object('product_id', s.product_id,
                          'voucher_id', s.voucher_id, 'quantity', s.quantity)) as options
                   from public.invoice_promotion_selections s
                  where s.invoice_item_id = v_li.id
                  group by s.group_id) g),
        v_line_member);
      if v_new is distinct from v_li.unit_price or coalesce(v_new_topup,0) is distinct from coalesce(v_li.topup_amount,0)
         or v_li.price_mode is distinct from v_mode then
        v_changes := v_changes || jsonb_build_object('item_id', v_li.id, 'kind','promotion','name', v_li.prname,
          'old_price', v_li.unit_price, 'new_price', v_new,
          'old_topup', coalesce(v_li.topup_amount,0), 'new_topup', coalesce(v_new_topup,0),
          'reason', case when v_li.price_mode is distinct from v_mode then 'price mode changed' else 'top-up recalculated' end);
      end if;
      v_gross := (v_new * v_li.quantity) + coalesce(v_new_topup,0);
      v_foc := case when coalesce(v_li.foc_quantity,0) > 0
                    then round(v_gross * v_li.foc_quantity::numeric / v_li.quantity::numeric, 2) else 0 end;
      v_charged := round(v_gross - v_foc, 2);
      update public.invoice_items set unit_price=v_new, topup_amount=v_new_topup,
        line_total=v_charged, foc_amount=v_foc,
        price_mode=v_mode, price_source='promotion', price_source_id=(v_pj->>'source_id')::uuid,
        store_id_snapshot=v_inv.store_id,
        member_price_snapshot=(v_pj->>'member_price')::numeric, non_member_price_snapshot=(v_pj->>'non_member_price')::numeric,
        original_price=coalesce(original_price, v_li.unit_price)
       where id = v_li.id;
    end if;
  end loop;

  -- Rebuild money (A4 model). subtotal is the CHARGED value; FOC is rolled up separately.
  select coalesce(sum(line_total),0) into v_subtotal from public.invoice_items where invoice_id = p_invoice_id;
  select coalesce(sum(coalesce(line_discount,0)),0) into v_new_line_disc from public.invoice_items where invoice_id = p_invoice_id;
  update public.invoices set subtotal = v_subtotal where id = p_invoice_id;
  if v_inv.manual_discount is not null then
    perform public.refresh_invoice_discount_total(p_invoice_id);
  else
    update public.invoices set discount_total = greatest(0, coalesce(discount_total,0) + (v_new_line_disc - v_old_line_disc)) where id = p_invoice_id;
  end if;
  update public.invoices set discount_total = least(coalesce(discount_total,0), v_subtotal) where id = p_invoice_id;
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0)) where i.id = p_invoice_id;

  -- Refresh the FOC rollup from the repriced lines.
  update public.invoices i
     set foc_total = coalesce(f.foc,0),
         has_foc = coalesce(f.foc_lines,0) > 0,
         is_full_foc = (coalesce(f.foc_lines,0) > 0 and coalesce(f.charged_lines,0) = 0)
    from (select coalesce(sum(foc_amount),0) as foc,
                 count(*) filter (where foc_quantity > 0) as foc_lines,
                 count(*) filter (where coalesce(line_total,0) > 0) as charged_lines
            from public.invoice_items where invoice_id = p_invoice_id) f
   where i.id = p_invoice_id;

  if exists (select 1 from public.invoices where id = p_invoice_id and total_amount + 0.001 < paid_amount) then
    raise exception 'Repricing would reduce the total below the amount already paid'; end if;

  select * into v_inv from public.invoices where id = p_invoice_id;
  if v_inv.subtotal is distinct from v_old_sub or v_inv.discount_total is distinct from v_old_disc
     or v_inv.total_amount is distinct from v_old_total then
    if jsonb_array_length(v_changes) = 0 then
      v_changes := v_changes || jsonb_build_object('item_id', null, 'kind','invoice','name','Invoice totals',
        'old_total', v_old_total, 'new_total', v_inv.total_amount, 'reason','totals recalculated');
    end if;
  end if;
  return v_changes;
end $$;

-- =====================================================================
-- 7b. invoice_required_stock — ignore synthetic lines.
--     Same root cause as the repricing fix above: the refund top-up line
--     is line_kind='product' with a NULL product_id, so it was demanding
--     stock for a non-existent product ("Insufficient store stock for
--     <NULL>") and blocking settlement of every top-up invoice.
--     Real product/voucher/promotion lines are unaffected.
-- =====================================================================
create or replace function public.invoice_required_stock(p_invoice_id uuid)
returns table (kind text, item_id uuid, quantity bigint)
language sql stable security definer set search_path = public as $$
  with expanded as (
    select 'product'::text as kind, ii.product_id as item_id, ii.quantity::bigint as quantity
    from public.invoice_items ii
    where ii.invoice_id = p_invoice_id and ii.line_kind = 'product'
      and ii.product_id is not null
    union all
    select 'voucher', ii.voucher_id, ii.quantity::bigint
    from public.invoice_items ii
    join public.vouchers v on v.id = ii.voucher_id and v.qty_type = 'limited'
    where ii.invoice_id = p_invoice_id and ii.line_kind = 'voucher'
    union all
    select s.kind, s.item_id, (s.quantity)::bigint
    from public.invoice_items ii
    cross join lateral public.promotion_stock_items(ii.promotion_id, ii.quantity) s
    where ii.invoice_id = p_invoice_id and ii.line_kind::text in ('promotion', 'premium_bundle')  -- a bundle carries a
      -- promotion_id and keeps its contents in promotion_items exactly as a
      -- promotion does; expanding only 'promotion' meant a bundle consumed
      -- no stock at all, on corrections and on ordinary sales alike.
      and ii.promotion_id is not null
    union all
    select 'product', ips.product_id, ips.quantity::bigint
    from public.invoice_promotion_selections ips
    join public.invoice_items ii on ii.id = ips.invoice_item_id
    where ii.invoice_id = p_invoice_id and ips.product_id is not null
    union all
    select 'voucher', ips.voucher_id, ips.quantity::bigint
    from public.invoice_promotion_selections ips
    join public.invoice_items ii on ii.id = ips.invoice_item_id
    join public.vouchers v on v.id = ips.voucher_id and v.qty_type = 'limited'
    where ii.invoice_id = p_invoice_id and ips.voucher_id is not null
  )
  select kind, item_id, sum(quantity) as quantity
  from expanded
  where item_id is not null
  group by kind, item_id
$$;

-- =====================================================================
-- 8. confirm_foc_invoice — close a fully-FOC invoice with NO payment.
--    Mirrors pay_invoice's full-settlement path exactly (stock, member ID,
--    membership activation, voucher redemptions, commissions, audit) but
--    takes no money and ends at status 'completed_foc'.
--    Covers ordinary FOC sales AND fully-FOC refund top-up invoices.
-- =====================================================================
create or replace function public.confirm_foc_invoice(p_invoice_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_req record; v_available integer; v_li record;
  v_ms jsonb; v_is_member boolean; v_memline record; v_changes jsonb;
  v_owned_id text; v_resv public.member_id_reservations%rowtype;
  v_start date; v_expiry date; v_months integer;
  v_prev_id uuid; v_prev_expiry date; v_is_renewal boolean := false;
  v_new_membership uuid; v_use_member_id text; v_old_total numeric;
begin
  -- 1. Lock invoice.
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.deleted_at is not null then raise exception 'Invoice has been deleted'; end if;

  -- 2. Access + role.
  if auth.uid() is not null then
    if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
    if public.current_user_role() = 'inventory_manager' then
      raise exception 'Inventory Manager cannot confirm FOC invoices'; end if;
    if not public.user_has_store_access(v_inv.store_id) then
      raise exception 'No access to this invoice''s store'; end if;
  end if;

  -- 3. State gates.
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  if v_inv.status = 'completed_foc' then raise exception 'This FOC invoice has already been confirmed'; end if;
  if v_inv.customer_id is null then raise exception 'Invoice has no customer'; end if;
  if not coalesce(v_inv.has_foc,false) then raise exception 'This invoice has no FOC lines'; end if;
  if coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'This invoice already has payments — settle it through payment, not FOC confirmation'; end if;
  if coalesce(v_inv.total_amount,0) > 0.001 then
    raise exception 'This invoice still has a payable balance of %.2f — only a fully FOC invoice can be confirmed without payment',
      v_inv.total_amount; end if;

  -- 4. Lock membership rows, then re-derive membership context.
  perform 1 from public.customer_memberships
    where customer_id = v_inv.customer_id and deleted_at is null for update;
  select * into v_memline from public.invoice_membership_line(p_invoice_id) limit 1;
  v_ms := public.customer_membership_status(v_inv.customer_id);
  v_is_member := coalesce((v_ms->>'is_member')::boolean, false) or (v_memline.plan_id is not null);

  -- 5. Reprice (keeps eligibility + FOC snapshots honest); surface any change.
  v_old_total := v_inv.total_amount;
  v_changes := public.reprice_invoice_lines(p_invoice_id, v_is_member);
  select * into v_inv from public.invoices where id = p_invoice_id;
  if jsonb_array_length(v_changes) > 0 then
    perform public.write_audit('invoices', p_invoice_id, 'foc_price_review', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'changes', v_changes));
    return jsonb_build_object('success', false, 'review_required', true,
      'old_total', v_old_total, 'new_total', v_inv.total_amount, 'changes', v_changes);
  end if;
  if coalesce(v_inv.total_amount,0) > 0.001 then
    raise exception 'Repricing left a payable balance of %.2f — this is no longer a fully FOC invoice', v_inv.total_amount; end if;

  -- 6. Membership line + Member ID (same rules as a paid membership).
  if v_memline.plan_id is not null then
    if v_memline.plan_months is null or v_memline.unit_price is null then
      raise exception 'Membership line is missing its plan snapshot — remove and re-add the membership line'; end if;
    select member_id into v_owned_id from public.member_ids where customer_id = v_inv.customer_id;
    v_is_renewal := v_owned_id is not null;
    if v_is_renewal then
      select * into v_resv from public.member_id_reservations where customer_id = v_inv.customer_id limit 1;
      if v_resv.member_id is not null and v_resv.member_id <> v_owned_id then
        raise exception 'This customer already owns Member ID % — the reservation for % conflicts',
          v_owned_id, v_resv.member_id; end if;
      v_use_member_id := v_owned_id;
    else
      select * into v_resv from public.member_id_reservations
        where invoice_id = p_invoice_id and customer_id = v_inv.customer_id limit 1;
      if v_resv.member_id is null then
        raise exception 'A Member ID must be assigned before a membership invoice can be confirmed'; end if;
      v_use_member_id := v_resv.member_id;
    end if;
  end if;

  -- 7. Members-only promotion gate (unchanged by FOC).
  if not coalesce((v_ms->>'is_member')::boolean,false) and v_memline.plan_id is null then
    if exists (select 1 from public.invoice_items ii
                where ii.invoice_id = p_invoice_id and ii.line_kind::text in ('promotion', 'premium_bundle')  -- a bundle carries a
      -- promotion_id and keeps its contents in promotion_items exactly as a
      -- promotion does; expanding only 'promotion' meant a bundle consumed
      -- no stock at all, on corrections and on ordinary sales alike.
                  and coalesce(ii.price_overridden,false) = false) then
      raise exception 'Promotions are for members only. Add a membership to this invoice or apply a manual override.';
    end if;
  end if;

  -- 8. Stock check — FOC consumes real stock, so the same gate applies.
  for v_req in select * from public.invoice_required_stock(p_invoice_id)
  loop
    if v_req.kind = 'product' then
      select current_qty into v_available from public.store_inventory
        where store_id = v_inv.store_id and product_id = v_req.item_id for update;
      if coalesce(v_available,0) < v_req.quantity then
        raise exception 'Insufficient store stock for % (have %, need % incl. bundles). FOC blocked.',
          (select name from public.products where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
      end if;
    else
      select current_qty into v_available from public.voucher_store_stock
        where store_id = v_inv.store_id and voucher_id = v_req.item_id for update;
      if coalesce(v_available,0) < v_req.quantity then
        raise exception 'Insufficient voucher stock for % (have %, need % incl. bundles). FOC blocked.',
          (select name from public.vouchers where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
      end if;
    end if;
  end loop;

  -- 9. Deduct stock (products, vouchers, promotion components alike).
  for v_req in select * from public.invoice_required_stock(p_invoice_id)
  loop
    if v_req.kind = 'product' then
      update public.store_inventory set current_qty = current_qty - v_req.quantity, updated_at = now()
        where store_id = v_inv.store_id and product_id = v_req.item_id;
      insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
      values (v_req.item_id, 'store_sale', v_inv.store_id, p_invoice_id, v_req.quantity,
              'FOC — '||v_inv.invoice_no, auth.uid());
    else
      update public.voucher_store_stock set current_qty = current_qty - v_req.quantity, updated_at = now()
        where store_id = v_inv.store_id and voucher_id = v_req.item_id;
      perform public.write_audit('vouchers', v_req.item_id, 'voucher_sold', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no, 'qty', v_req.quantity, 'foc', true));
    end if;
  end loop;

  -- 10. Close the invoice (no payment rows are written).
  update public.invoices
     set status = 'completed_foc', paid_amount = 0, paid_at = now(), locked_at = now(),
         foc_confirmed_at = now(), foc_confirmed_by = auth.uid()
   where id = p_invoice_id;

  -- 11. Voucher redemptions (a FOC line can still carry a discount voucher).
  if v_inv.discount_voucher_id is not null then
    insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
    values (v_inv.discount_voucher_id, p_invoice_id, v_inv.customer_id,
            coalesce(v_inv.discount_total,0) - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0),
            auth.uid());
    perform public.write_audit('vouchers', v_inv.discount_voucher_id, 'voucher_redeemed', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'foc', true));
  end if;
  for v_li in select line_voucher_id, line_discount from public.invoice_items
    where invoice_id = p_invoice_id and line_voucher_id is not null
  loop
    insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
    values (v_li.line_voucher_id, p_invoice_id, v_inv.customer_id, v_li.line_discount, auth.uid());
    perform public.write_audit('vouchers', v_li.line_voucher_id, 'voucher_redeemed', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'line_discount', v_li.line_discount, 'foc', true));
  end loop;

  -- 12. Membership activates exactly as a paid one would.
  if v_memline.plan_id is not null then
    v_months := v_memline.plan_months;
    select id, expiry_date into v_prev_id, v_prev_expiry
      from public.customer_memberships
      where customer_id = v_inv.customer_id and deleted_at is null
        and status <> 'cancelled' and start_date is not null and expiry_date is not null
        and expiry_date >= public.sg_today()
      order by expiry_date desc limit 1;
    if v_prev_id is not null then
      v_start := public.membership_renewal_start(v_prev_expiry);
      v_is_renewal := true;
    else
      v_start := public.sg_today();
    end if;
    v_expiry := public.membership_expiry(v_start, v_months);

    insert into public.customer_memberships (
      customer_id, plan_id, store_id, member_id, source, invoice_id, invoice_item_id,
      fee_snapshot, start_date, expiry_date, status, is_renewal, previous_membership_id,
      activated_at, created_by)
    values (
      v_inv.customer_id, v_memline.plan_id, v_inv.store_id, v_use_member_id,
      case when v_is_renewal then 'renewal' else 'sale' end,
      p_invoice_id, v_memline.item_id,
      v_memline.unit_price, v_start, v_expiry, 'active',
      v_is_renewal, v_prev_id, now(), auth.uid())
    returning id into v_new_membership;

    update public.invoice_items set member_id_snapshot = v_use_member_id
      where id = v_memline.item_id and member_id_snapshot is null;
    if not (v_owned_id is not null) then
      perform public.commit_member_id(v_use_member_id, v_inv.customer_id);
    end if;

    perform public.write_audit_ex('customer_memberships', v_new_membership, 'membership_activated',
      null, jsonb_build_object('plan', v_memline.plan_id, 'start', v_start, 'expiry', v_expiry,
                               'renewal', v_is_renewal, 'member_id', v_use_member_id,
                               'invoice_no', v_inv.invoice_no, 'foc', true),
      'membership', p_note, v_inv.store_id);
  end if;

  -- 13. Commissions. Both bases are the CHARGED value, which is zero here,
  --      so these are deliberate no-ops that keep the code path identical.
  perform public.earn_invoice_commission(p_invoice_id);
  perform public.earn_staff_commission(p_invoice_id);

  -- 14. Audit.
  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_foc_confirmed', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'foc_total', v_inv.foc_total,
                       'membership_created', (v_new_membership is not null),
                       'is_topup', coalesce(v_inv.is_topup,false)),
    'foc', p_note, v_inv.store_id);

  return jsonb_build_object('success', true, 'status', 'completed_foc',
    'foc_total', v_inv.foc_total, 'paid_amount', 0, 'membership_id', v_new_membership);
end $$;

-- =====================================================================
-- 9. Settlement-path integrations for the new status.
-- =====================================================================
-- (a) pay_invoice — migration 48b's body, re-issued with Phase 12 guards:
--     a confirmed FOC invoice can never take money, and a fully-FOC invoice
--     is routed to Confirm FOC Invoice. Mixed invoices are unaffected and
--     charge the paid value only, because line_total already excludes FOC.
create or replace function public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_req record; v_available integer; v_li record;
  v_ms jsonb; v_is_member boolean; v_memline record; v_will_be_full boolean;
  v_old_total numeric; v_changes jsonb;
  v_owned_id text; v_resv public.member_id_reservations%rowtype;
  v_start date; v_expiry date; v_months integer;
  v_prev_id uuid; v_prev_expiry date; v_is_renewal boolean := false;
  v_new_membership uuid; v_use_member_id text;
begin
  -- 1. Lock invoice.
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  -- 2. Role/store access.
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
  -- 3. Editable/payable + customer present.
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  -- Phase 12: a confirmed FOC invoice is closed; a fully-FOC invoice has no balance.
  if v_inv.status = 'completed_foc' then
    raise exception 'This invoice was completed as FOC and cannot take a payment'; end if;
  if coalesce(v_inv.is_full_foc,false) and coalesce(v_inv.total_amount,0) <= 0.001 then
    raise exception 'This invoice is fully FOC — use Confirm FOC Invoice instead of taking a payment'; end if;
  if v_inv.customer_id is null then raise exception 'Invoice has no customer'; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then raise exception 'At least one payment is required'; end if;

  -- 4. Lock the customer's membership rows (renewal decisions are made on them).
  perform 1 from public.customer_memberships
    where customer_id = v_inv.customer_id and deleted_at is null for update;

  -- 5. Recheck membership + same-invoice membership line.
  select * into v_memline from public.invoice_membership_line(p_invoice_id) limit 1;
  v_ms := public.customer_membership_status(v_inv.customer_id);
  v_is_member := coalesce((v_ms->>'is_member')::boolean, false) or (v_memline.plan_id is not null);

  -- 6. Reprice all applicable non-overridden lines (strict prices + eligibility
  --    enforced inside; raises with the line name if anything is missing).
  v_old_total := v_inv.total_amount;
  v_changes := public.reprice_invoice_lines(p_invoice_id, v_is_member);
  select * into v_inv from public.invoices where id = p_invoice_id;   -- fresh totals

  -- 7. If anything changed, persist the repriced invoice, record NO payment,
  --    and return a structured review request.
  if jsonb_array_length(v_changes) > 0 then
    perform public.write_audit('invoices', p_invoice_id, 'payment_price_review', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'old_total', v_old_total,
                         'new_total', v_inv.total_amount, 'changes', v_changes));
    return jsonb_build_object(
      'success', false, 'review_required', true,
      'old_total', v_old_total, 'new_total', v_inv.total_amount, 'changes', v_changes);
  end if;

  -- 8. Validate the membership line + its snapshots.
  if v_memline.plan_id is not null then
    if v_memline.plan_months is null or v_memline.unit_price is null then
      raise exception 'Membership line is missing its plan snapshot — remove and re-add the membership line'; end if;
    select member_id into v_owned_id from public.member_ids where customer_id = v_inv.customer_id;
    v_is_renewal := v_owned_id is not null;

    -- 9. Member ID before ANY payment (partial included).
    if v_is_renewal then
      -- Renewal reuses the permanent ID; a conflicting reservation is an error.
      select * into v_resv from public.member_id_reservations
        where customer_id = v_inv.customer_id limit 1;
      if v_resv.member_id is not null and v_resv.member_id <> v_owned_id then
        raise exception 'This customer already owns Member ID % — the reservation for % conflicts',
          v_owned_id, v_resv.member_id; end if;
      v_use_member_id := v_owned_id;
    else
      select * into v_resv from public.member_id_reservations
        where invoice_id = p_invoice_id and customer_id = v_inv.customer_id limit 1;
      if v_resv.member_id is null then
        raise exception 'A Member ID must be assigned before any payment can be taken on a membership invoice'; end if;
      v_use_member_id := v_resv.member_id;
    end if;
  end if;

  -- 10./11. Prices + eligibility were enforced during reprice; promotion gate:
  if not coalesce((v_ms->>'is_member')::boolean,false) and v_memline.plan_id is null then
    if exists (select 1 from public.invoice_items ii
                where ii.invoice_id = p_invoice_id and ii.line_kind::text in ('promotion', 'premium_bundle')  -- a bundle carries a
      -- promotion_id and keeps its contents in promotion_items exactly as a
      -- promotion does; expanding only 'promotion' meant a bundle consumed
      -- no stock at all, on corrections and on ordinary sales alike.
                  and coalesce(ii.price_overridden,false) = false) then
      raise exception 'Promotions are for members only. Add a membership to this invoice or apply a manual override.';
    end if;
  end if;

  -- 13. Validate payment amounts.
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;
  v_already_paid := v_inv.paid_amount;
  v_new_paid := v_already_paid + v_total_paying;
  if v_new_paid > v_inv.total_amount + 0.001 then raise exception 'Payment exceeds remaining balance'; end if;
  v_will_be_full := v_new_paid >= v_inv.total_amount - 0.001;

  -- 12. Stock check (only matters when this payment completes the invoice).
  if v_will_be_full then
    for v_req in select * from public.invoice_required_stock(p_invoice_id)
    loop
      if v_req.kind = 'product' then
        select current_qty into v_available from public.store_inventory
          where store_id = v_inv.store_id and product_id = v_req.item_id for update;
        if coalesce(v_available,0) < v_req.quantity then
          raise exception 'Insufficient store stock for % (have %, need % incl. bundles). Payment blocked.',
            (select name from public.products where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
        end if;
      else
        select current_qty into v_available from public.voucher_store_stock
          where store_id = v_inv.store_id and voucher_id = v_req.item_id for update;
        if coalesce(v_available,0) < v_req.quantity then
          raise exception 'Insufficient voucher stock for % (have %, need % incl. bundles). Payment blocked.',
            (select name from public.vouchers where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
        end if;
      end if;
    end loop;
  end if;

  -- 14. Record payments.
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  if v_will_be_full then
    -- 15. Deduct stock.
    for v_req in select * from public.invoice_required_stock(p_invoice_id)
    loop
      if v_req.kind = 'product' then
        update public.store_inventory set current_qty = current_qty - v_req.quantity, updated_at = now()
          where store_id = v_inv.store_id and product_id = v_req.item_id;
        insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
        values (v_req.item_id, 'store_sale', v_inv.store_id, p_invoice_id, v_req.quantity, 'Sale — '||v_inv.invoice_no, auth.uid());
      else
        update public.voucher_store_stock set current_qty = current_qty - v_req.quantity, updated_at = now()
          where store_id = v_inv.store_id and voucher_id = v_req.item_id;
        perform public.write_audit('vouchers', v_req.item_id, 'voucher_sold', null,
          jsonb_build_object('invoice_no', v_inv.invoice_no, 'qty', v_req.quantity));
      end if;
    end loop;

    -- 16. Mark paid + lock.
    update public.invoices set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    -- Voucher redemptions (preserved).
    if v_inv.discount_voucher_id is not null then
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_inv.discount_voucher_id, p_invoice_id, v_inv.customer_id,
              v_inv.discount_total - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0),
              auth.uid());
      perform public.write_audit('vouchers', v_inv.discount_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no));
    end if;
    for v_li in select line_voucher_id, line_discount from public.invoice_items
      where invoice_id = p_invoice_id and line_voucher_id is not null
    loop
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_li.line_voucher_id, p_invoice_id, v_inv.customer_id, v_li.line_discount, auth.uid());
      perform public.write_audit('vouchers', v_li.line_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no, 'line_discount', v_li.line_discount));
    end loop;

    -- 17. Create the membership / future renewal FROM SNAPSHOTS.
    if v_memline.plan_id is not null then
      v_months := v_memline.plan_months;
      -- Renewal starts the day after the LATEST applicable expiry (rows locked
      -- in step 4). Applicable = dated, not cancelled, not deleted, not ended.
      select id, expiry_date into v_prev_id, v_prev_expiry
        from public.customer_memberships
        where customer_id = v_inv.customer_id and deleted_at is null
          and status <> 'cancelled' and start_date is not null and expiry_date is not null
          and expiry_date >= public.sg_today()
        order by expiry_date desc limit 1;

      if v_prev_id is not null then
        v_start := public.membership_renewal_start(v_prev_expiry);
        v_is_renewal := true;
      else
        v_start := public.sg_today();
      end if;
      v_expiry := public.membership_expiry(v_start, v_months);

      insert into public.customer_memberships (
        customer_id, plan_id, store_id, member_id, source, invoice_id, invoice_item_id,
        fee_snapshot, start_date, expiry_date, status, is_renewal, previous_membership_id,
        activated_at, created_by)
      values (
        v_inv.customer_id, v_memline.plan_id, v_inv.store_id, v_use_member_id,
        case when v_is_renewal then 'renewal' else 'sale' end,
        p_invoice_id, v_memline.item_id,
        v_memline.unit_price, v_start, v_expiry, 'active',
        v_is_renewal, v_prev_id, now(), auth.uid())
      returning id into v_new_membership;

      -- Keep the line snapshot complete for printing.
      update public.invoice_items set member_id_snapshot = v_use_member_id
        where id = v_memline.item_id and member_id_snapshot is null;

      -- 18. Commit a NEW reservation to permanent ownership; renewals already own.
      if not (v_owned_id is not null) then
        perform public.commit_member_id(v_use_member_id, v_inv.customer_id);
      end if;

      perform public.write_audit_ex('customer_memberships', v_new_membership, 'membership_activated',
        null, jsonb_build_object('plan', v_memline.plan_id, 'start', v_start, 'expiry', v_expiry,
                                 'renewal', v_is_renewal, 'member_id', v_use_member_id,
                                 'invoice_no', v_inv.invoice_no),
        'membership', null, v_inv.store_id);
    end if;

    -- 19. Commissions (membership line = Own Product, earns normally).
    perform public.earn_invoice_commission(p_invoice_id);
    perform public.earn_staff_commission(p_invoice_id);

    -- 20. Audit.
    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no,
                         'membership_created', (v_new_membership is not null),
                         'foc_total', coalesce(v_inv.foc_total,0),
                         'mixed_foc', coalesce(v_inv.has_foc,false)));
    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid,
                              'membership_id', v_new_membership);
  else
    -- Partial payment: money recorded, NOTHING activates, no stock moves.
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid' where id = p_invoice_id;
    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));
    return jsonb_build_object('success', true, 'status', 'partially_paid', 'paid_amount', v_new_paid,
                              'remaining', v_inv.total_amount - v_new_paid);
  end if;
end; $$;

-- (b) Therapy entitlements are created on payment by a trigger; a FOC
--     therapy line must create its entitlement the same way.
create or replace function public.trg_create_therapy_on_paid() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status in ('paid','completed_foc') and old.status is distinct from new.status then
    if exists (select 1 from public.invoice_items where invoice_id = new.id and line_kind = 'therapy') then
      perform public.create_purchased_therapy_for_invoice(new.id);
    end if;
  end if;
  return null;
end $$;

drop trigger if exists create_therapy_on_paid on public.invoices;
create trigger create_therapy_on_paid
  after update on public.invoices
  for each row execute function public.trg_create_therapy_on_paid();

-- (c) A FOC purchase is still a purchase: keep the exchange window open.
create or replace function public.exchange_ineligibility_reason(p_invoice_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_paid_date date; v_deadline date;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return 'Invoice not found'; end if;
  if v_inv.deleted_at is not null then return 'Invoice has been deleted'; end if;
  if v_inv.status not in ('paid','completed_foc') then return 'Invoice is not fully paid'; end if;
  if v_inv.paid_at is null then return 'Invoice has no payment date'; end if;
  v_paid_date := (v_inv.paid_at at time zone 'Asia/Singapore')::date;
  v_deadline := v_paid_date + 4;
  if public.sg_today() > v_deadline then
    return 'Exchange window has closed (5 days from purchase, by ' || to_char(v_deadline, 'DD Mon YYYY') || ')';
  end if;
  return '';
end $$;

-- =====================================================================
-- 10. FOC exchange top-up.
--     The 7-arg version from migration 33 is dropped first: keeping both
--     would make a 7-argument call ambiguous once defaults are added.
-- =====================================================================
drop function if exists public.create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text);

create or replace function public.create_product_exchange(
  p_original_invoice_id uuid,
  p_processing_store_id uuid,
  p_returned jsonb,        -- [{invoice_item_id, quantity}]
  p_replacement jsonb,     -- [{product_id, quantity}]
  p_payments jsonb default '[]'::jsonb,  -- [{payment_method_id, amount, reference}]
  p_reason text default null,
  p_notes text default null,
  p_foc boolean default false,                -- waive the top-up
  p_foc_reason_id uuid default null,
  p_foc_reason text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype;
  v_reason text; v_line jsonb; v_ex_id uuid; v_no text;
  v_item public.invoice_items%rowtype; v_ptype product_type; v_side_type product_type;
  v_price numeric; v_qty integer; v_avail integer;
  v_credit numeric := 0; v_repl numeric := 0; v_topup numeric; v_nonref numeric := 0;
  v_pay_sum numeric := 0; v_prod_id uuid; v_role user_role;
  v_foc_amt numeric := 0; v_foc_text text;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile for current user'; end if;

  -- Eligibility.
  v_reason := public.exchange_ineligibility_reason(p_original_invoice_id);
  if v_reason <> '' then raise exception '%', v_reason; end if;

  select * into v_inv from public.invoices where id = p_original_invoice_id for update;

  -- Staff may only process for their assigned store.
  if v_role = 'staff' and public.my_assigned_store_id() is distinct from p_processing_store_id then
    raise exception 'You can only process exchanges for your assigned store';
  end if;
  if not public.user_has_store_access(p_processing_store_id) then
    raise exception 'You do not have access to the processing store';
  end if;

  if p_returned is null or jsonb_array_length(p_returned) = 0 then raise exception 'Select at least one item to return'; end if;
  if p_replacement is null or jsonb_array_length(p_replacement) = 0 then raise exception 'Select at least one replacement product'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required for the exchange'; end if;

  -- ---- Returned side: validate items, determine product type, credit ----
  for v_line in select * from jsonb_array_elements(p_returned)
  loop
    select * into v_item from public.invoice_items
      where id = (v_line->>'invoice_item_id')::uuid and invoice_id = p_original_invoice_id for update;
    if not found then raise exception 'A returned item is not part of the original invoice'; end if;
    if v_item.line_kind <> 'product' then raise exception 'Bundle/voucher lines are handled in the bundle exchange (3B), not here'; end if;
    if v_item.exchanged_at is not null then raise exception 'An item on this invoice has already been exchanged'; end if;
    v_qty := coalesce((v_line->>'quantity')::integer, v_item.quantity);
    if v_qty <> v_item.quantity then raise exception 'Return the full quantity of the purchased line in 3A'; end if;

    select product_type into v_ptype from public.products where id = v_item.product_id;
    if v_side_type is null then v_side_type := v_ptype;
    elsif v_side_type <> v_ptype then raise exception 'All returned items must be the same product type'; end if;

    -- Credit = current processing-store price * qty.
    select selling_price into v_price from public.store_product_prices
      where store_id = p_processing_store_id and product_id = v_item.product_id and is_active = true;
    if v_price is null then raise exception 'Returned product has no active price at the processing store'; end if;
    v_credit := v_credit + v_price * v_item.quantity;
  end loop;

  -- ---- Replacement side: validate type match + stock, compute total ----
  for v_line in select * from jsonb_array_elements(p_replacement)
  loop
    v_prod_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Replacement quantity must be greater than zero'; end if;

    select product_type into v_ptype from public.products where id = v_prod_id;
    if v_ptype is null then raise exception 'Replacement product not found'; end if;
    if v_ptype <> v_side_type then
      raise exception 'Own products may only be exchanged for own products, and third-party for third-party';
    end if;

    select selling_price into v_price from public.store_product_prices
      where store_id = p_processing_store_id and product_id = v_prod_id and is_active = true;
    if v_price is null then raise exception 'A replacement product has no active price at the processing store'; end if;
    v_repl := v_repl + v_price * v_qty;

    select current_qty into v_avail from public.store_inventory
      where store_id = p_processing_store_id and product_id = v_prod_id for update;
    if coalesce(v_avail, 0) < v_qty then raise exception 'Insufficient replacement stock at the processing store'; end if;
  end loop;

  -- ---- Money ----
  v_topup := round(v_repl - v_credit, 2);
  if v_topup > 0 then
    if coalesce(p_foc,false) then
      -- Phase 12: FOC exchange top-up — closes with no payment at all.
      if public.current_user_role() = 'inventory_manager' then
        raise exception 'Inventory Manager cannot apply FOC'; end if;
      v_foc_text := public.foc_reason_resolve(p_foc_reason_id, p_foc_reason);
      v_foc_amt := v_topup;
      v_topup := 0;
    else
      select coalesce(sum((x->>'amount')::numeric), 0) into v_pay_sum from jsonb_array_elements(p_payments) x;
      if round(v_pay_sum, 2) <> v_topup then
        raise exception 'Top-up payment (%.2f) must equal the amount due (%.2f)', v_pay_sum, v_topup;
      end if;
    end if;
    v_nonref := 0;
  elsif v_topup < 0 then
    v_nonref := -v_topup; v_topup := 0;   -- non-refundable, no money moves
  else
    v_topup := 0; v_nonref := 0;
  end if;

  -- ---- Create exchange header ----
  v_no := 'EX-' || to_char(now() at time zone 'Asia/Singapore', 'YYYYMMDD') || '-' || substr(gen_random_uuid()::text, 1, 6);
  insert into public.product_exchanges
    (exchange_no, original_invoice_id, customer_id, processing_store_id, affiliate_id,
     returned_credit_total, replacement_total, topup_amount, nonrefundable_amount,
     status, reason, notes, created_by, locked_at,
     is_foc, foc_amount, foc_reason_id, foc_reason, foc_by, foc_at)
  values (v_no, p_original_invoice_id, v_inv.customer_id, p_processing_store_id, v_inv.affiliate_id,
     v_credit, v_repl, v_topup, v_nonref, 'completed', p_reason, p_notes, auth.uid(), now(),
     v_foc_amt > 0, v_foc_amt, case when v_foc_amt > 0 then p_foc_reason_id end,
     case when v_foc_amt > 0 then v_foc_text end,
     case when v_foc_amt > 0 then auth.uid() end, case when v_foc_amt > 0 then now() end)
  returning id into v_ex_id;

  -- ---- Returned items: record, mark exchanged, add stock back ----
  for v_line in select * from jsonb_array_elements(p_returned)
  loop
    select * into v_item from public.invoice_items where id = (v_line->>'invoice_item_id')::uuid;
    select selling_price into v_price from public.store_product_prices
      where store_id = p_processing_store_id and product_id = v_item.product_id and is_active = true;

    insert into public.product_exchange_items (exchange_id, direction, original_invoice_item_id, product_id, quantity, unit_price, line_total)
    values (v_ex_id, 'returned', v_item.id, v_item.product_id, v_item.quantity, v_price, v_price * v_item.quantity);

    update public.invoice_items set exchanged_at = now(), exchange_id = v_ex_id where id = v_item.id;

    insert into public.store_inventory (store_id, product_id, current_qty)
      values (p_processing_store_id, v_item.product_id, v_item.quantity)
      on conflict (store_id, product_id) do update set current_qty = public.store_inventory.current_qty + excluded.current_qty, updated_at = now();

    insert into public.stock_movements (product_id, movement_type, to_store_id, quantity, notes, created_by)
      values (v_item.product_id, 'exchange_return_in', p_processing_store_id, v_item.quantity, 'Exchange ' || v_no || ' — returned', auth.uid());
  end loop;

  -- ---- Replacement items: record, deduct stock ----
  for v_line in select * from jsonb_array_elements(p_replacement)
  loop
    v_prod_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    select selling_price into v_price from public.store_product_prices
      where store_id = p_processing_store_id and product_id = v_prod_id and is_active = true;

    insert into public.product_exchange_items (exchange_id, direction, product_id, quantity, unit_price, line_total)
    values (v_ex_id, 'replacement', v_prod_id, v_qty, v_price, v_price * v_qty);

    update public.store_inventory set current_qty = current_qty - v_qty, updated_at = now()
      where store_id = p_processing_store_id and product_id = v_prod_id;

    insert into public.stock_movements (product_id, movement_type, from_store_id, quantity, notes, created_by)
      values (v_prod_id, 'exchange_replacement_out', p_processing_store_id, v_qty, 'Exchange ' || v_no || ' — replacement', auth.uid());
  end loop;

  -- ---- Top-up payments ----
  if v_topup > 0 then
    for v_line in select * from jsonb_array_elements(p_payments)
    loop
      insert into public.product_exchange_payments (exchange_id, payment_method_id, amount, reference)
      values (v_ex_id, nullif(v_line->>'payment_method_id','')::uuid, (v_line->>'amount')::numeric, nullif(v_line->>'reference',''));
    end loop;
  end if;

  perform public.write_audit_ex('product_exchanges', v_ex_id, 'exchange_completed', null,
    jsonb_build_object('exchange_no', v_no, 'credit', v_credit, 'replacement', v_repl, 'topup', v_topup, 'nonrefundable', v_nonref, 'foc_amount', v_foc_amt),
    'exchanges', p_reason, p_processing_store_id);

  return jsonb_build_object('success', true, 'id', v_ex_id, 'exchange_no', v_no,
    'credit', v_credit, 'replacement', v_repl, 'topup', v_topup, 'nonrefundable', v_nonref,
    'foc_amount', v_foc_amt, 'is_foc', v_foc_amt > 0);
end $$;

-- =====================================================================
-- 11. FOC rental — fee waived, every other rental rule unchanged.
--     Mirrors pay_rental: same stock gate, same stock deduction, same
--     'paid' status, so activate / return / late-fee all behave normally.
-- =====================================================================
create or replace function public.foc_rental(
  p_rental_id uuid, p_reason_id uuid default null, p_reason text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r public.rentals%rowtype; v_avail integer; v_reason text;
begin
  if auth.uid() is not null and not public.is_owner_or_manager() then
    raise exception 'Only Owner or Manager can manage rentals'; end if;
  select * into v_r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if v_r.status <> 'draft' then raise exception 'Only draft rentals can be made FOC (current: %)', v_r.status; end if;
  if coalesce(v_r.is_foc,false) then raise exception 'This rental is already FOC'; end if;

  v_reason := public.foc_reason_resolve(p_reason_id, p_reason);

  select current_qty into v_avail from public.special_product_stock
    where special_product_id = v_r.special_product_id and warehouse_id = v_r.warehouse_id for update;
  if coalesce(v_avail,0) < v_r.quantity then
    raise exception 'Insufficient special stock (have %, need %)', coalesce(v_avail,0), v_r.quantity;
  end if;
  update public.special_product_stock set current_qty = current_qty - v_r.quantity, updated_at = now()
    where special_product_id = v_r.special_product_id and warehouse_id = v_r.warehouse_id;

  -- Status 'paid' with a zero fee: the rental lifecycle is untouched.
  update public.rentals
     set status = 'paid', paid_at = now(), payment_method_id = null, payment_reference = null,
         is_foc = true, foc_amount = v_r.rental_fee, foc_reason_id = p_reason_id,
         foc_reason = v_reason, foc_by = auth.uid(), foc_at = now()
   where id = p_rental_id;

  perform public.write_audit_ex('rentals', p_rental_id, 'rental_foc', null,
    jsonb_build_object('rental_no', v_r.rental_no, 'waived_fee', v_r.rental_fee,
                       'quantity', v_r.quantity),
    'foc', v_reason, null);

  return jsonb_build_object('success', true, 'rental_no', v_r.rental_no,
    'waived_fee', v_r.rental_fee, 'status', 'paid');
end $$;

-- =====================================================================
-- 12. Receipt / printing support.
--     Everything a printed receipt needs to show the FOC breakdown.
-- =====================================================================
create or replace function public.invoice_foc_details(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_lines jsonb;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('found', false); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'item_id', t.id,
           'line_kind', t.line_kind,
           'description', t.description,
           'quantity', t.quantity,
           'foc_quantity', t.foc_quantity,
           'paid_quantity', t.quantity - t.foc_quantity,
           'unit_price', t.unit_price,
           'foc_original_unit_price', t.foc_original_unit_price,
           'normal_value', round(t.line_total + t.foc_amount, 2),
           'foc_value', t.foc_amount,
           'charged_value', t.line_total,
           'line_discount', coalesce(t.line_discount,0),
           'is_full_foc', t.is_foc,
           'foc_reason', t.foc_reason
         ) order by t.rn), '[]'::jsonb)
    into v_lines
  from (
    select ii.id, ii.line_kind, ii.quantity, ii.foc_quantity, ii.unit_price,
           ii.foc_original_unit_price, ii.line_total, ii.foc_amount, ii.line_discount,
           ii.is_foc, ii.foc_reason,
           coalesce(p.name, pr.name, vo.name, ii.plan_name_snapshot, 'Item') as description,
           row_number() over (order by ii.ctid) as rn
      from public.invoice_items ii
      left join public.products p on p.id = ii.product_id
      left join public.promotions pr on pr.id = ii.promotion_id
      left join public.vouchers vo on vo.id = ii.voucher_id
     where ii.invoice_id = p_invoice_id
  ) t;

  return jsonb_build_object(
    'found', true,
    'invoice_no', v_inv.invoice_no,
    'status', v_inv.status,
    'has_foc', coalesce(v_inv.has_foc,false),
    'is_full_foc', coalesce(v_inv.is_full_foc,false),
    'foc_total', coalesce(v_inv.foc_total,0),
    'normal_value', round(coalesce(v_inv.subtotal,0) + coalesce(v_inv.foc_total,0), 2),
    'charged_subtotal', coalesce(v_inv.subtotal,0),
    'discount_total', coalesce(v_inv.discount_total,0),
    'total_amount', coalesce(v_inv.total_amount,0),
    'paid_amount', coalesce(v_inv.paid_amount,0),
    'foc_confirmed_at', v_inv.foc_confirmed_at,
    'lines', v_lines);
end $$;

-- =====================================================================
-- 13. FOC reports — normal value vs FOC value.
-- =====================================================================
create or replace function public.report_foc_summary(
  p_from date default null, p_to date default null, p_store_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_from date; v_to date; v_res jsonb; v_by_kind jsonb; v_by_reason jsonb;
begin
  v_from := coalesce(p_from, public.sg_today() - 30);
  v_to   := coalesce(p_to,   public.sg_today());

  select jsonb_build_object(
           'invoice_count', count(distinct i.id),
           'full_foc_invoices', count(distinct i.id) filter (where i.is_full_foc),
           'mixed_foc_invoices', count(distinct i.id) filter (where i.has_foc and not i.is_full_foc),
           'foc_value', coalesce(sum(ii.foc_amount),0),
           'charged_value', coalesce(sum(ii.line_total),0),
           'normal_value', coalesce(sum(ii.foc_amount + ii.line_total),0),
           'foc_units', coalesce(sum(ii.foc_quantity),0))
    into v_res
  from public.invoices i
  join public.invoice_items ii on ii.invoice_id = i.id
  where i.deleted_at is null
    and coalesce(i.has_foc,false) = true
    and i.status in ('paid','completed_foc')
    and (i.paid_at at time zone 'Asia/Singapore')::date between v_from and v_to
    and (p_store_id is null or i.store_id = p_store_id);

  select coalesce(jsonb_agg(x order by x->>'line_kind'), '[]'::jsonb) into v_by_kind
  from (
    select jsonb_build_object('line_kind', ii.line_kind,
             'foc_value', coalesce(sum(ii.foc_amount),0),
             'foc_units', coalesce(sum(ii.foc_quantity),0),
             'lines', count(*)) as x
    from public.invoices i
    join public.invoice_items ii on ii.invoice_id = i.id
    where i.deleted_at is null and ii.foc_quantity > 0
      and i.status in ('paid','completed_foc')
      and (i.paid_at at time zone 'Asia/Singapore')::date between v_from and v_to
      and (p_store_id is null or i.store_id = p_store_id)
    group by ii.line_kind
  ) s;

  select coalesce(jsonb_agg(y order by (y->>'foc_value')::numeric desc), '[]'::jsonb) into v_by_reason
  from (
    select jsonb_build_object('reason', coalesce(fr.label, 'Free text / other'),
             'foc_value', coalesce(sum(ii.foc_amount),0),
             'lines', count(*)) as y
    from public.invoices i
    join public.invoice_items ii on ii.invoice_id = i.id
    left join public.foc_reasons fr on fr.id = ii.foc_reason_id
    where i.deleted_at is null and ii.foc_quantity > 0
      and i.status in ('paid','completed_foc')
      and (i.paid_at at time zone 'Asia/Singapore')::date between v_from and v_to
      and (p_store_id is null or i.store_id = p_store_id)
    group by coalesce(fr.label, 'Free text / other')
  ) s2;

  return coalesce(v_res, '{}'::jsonb)
         || jsonb_build_object('from', v_from, 'to', v_to,
                               'by_kind', v_by_kind, 'by_reason', v_by_reason);
end $$;

create or replace function public.report_foc_lines(
  p_from date default null, p_to date default null, p_store_id uuid default null
) returns table (
  invoice_id uuid, invoice_no text, invoice_status invoice_status, store_id uuid,
  customer_name text, line_kind text, description text,
  quantity integer, foc_quantity integer, unit_price numeric,
  normal_value numeric, foc_value numeric, charged_value numeric,
  is_full_foc boolean, foc_reason text, foc_by_name text, settled_at timestamptz
) language sql stable security definer set search_path = public as $$
  select i.id, i.invoice_no, i.status, i.store_id,
         c.full_name,
         ii.line_kind,
         coalesce(p.name, pr.name, vo.name, ii.plan_name_snapshot, 'Item'),
         ii.quantity, ii.foc_quantity, ii.unit_price,
         round(ii.line_total + ii.foc_amount, 2),
         ii.foc_amount, ii.line_total,
         ii.is_foc, ii.foc_reason, pf.full_name, i.paid_at
    from public.invoices i
    join public.invoice_items ii on ii.invoice_id = i.id
    left join public.customers c on c.id = i.customer_id
    left join public.products p on p.id = ii.product_id
    left join public.promotions pr on pr.id = ii.promotion_id
    left join public.vouchers vo on vo.id = ii.voucher_id
    left join public.profiles pf on pf.id = ii.foc_by
   where i.deleted_at is null
     and ii.foc_quantity > 0
     and i.status in ('paid','completed_foc')
     and (i.paid_at at time zone 'Asia/Singapore')::date
         between coalesce(p_from, public.sg_today() - 30) and coalesce(p_to, public.sg_today())
     and (p_store_id is null or i.store_id = p_store_id)
   order by i.paid_at desc, i.invoice_no
$$;

notify pgrst, 'reload schema';
