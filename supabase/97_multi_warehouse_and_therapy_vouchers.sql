-- =====================================================================
-- ENERGIA — MULTI-WAREHOUSE TRANSFER APPROVAL, AND THERAPY PACKAGE REWARDS
--
-- PART A. One transfer request can now be filled from SEVERAL warehouses.
--   Previously approve_transfer() took a single p_source_warehouse_id, so a
--   request whose products were spread across warehouses had to be split into
--   separate requests by hand. The source now lives on the LINE, and a single
--   line may also be split across warehouses when no one warehouse holds
--   enough.
--
-- PART B. A Therapy Package can grant vouchers instead of unlimited months,
--   mirroring how Legacy Therapy rules already work (entitlement_kind,
--   voucher_qty). Existing packages stay 'unlimited', which is what they do
--   today, so nothing changes for live data.
--
-- Additive and idempotent. Run AFTER 96.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- PART A — MULTI-WAREHOUSE TRANSFERS
-- =====================================================================

-- Where each line is actually drawn from. A line may have several rows when
-- the quantity is split across warehouses.
create table if not exists public.transfer_line_sources (
  id uuid primary key default gen_random_uuid(),
  line_id uuid not null references public.transfer_request_lines(id) on delete cascade,
  source_type public.location_type not null,
  source_id uuid not null,
  quantity integer not null check (quantity > 0),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_transfer_line_sources_line on public.transfer_line_sources (line_id);
alter table public.transfer_line_sources enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='transfer_line_sources' and policyname='read transfer line sources') then
    create policy "read transfer line sources" on public.transfer_line_sources
      for select to authenticated using (true);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Which warehouses can supply a product, and how much each holds.
-- This is what makes the approval screen usable: the approver sees where the
-- stock actually is instead of guessing a warehouse and being refused.
-- ---------------------------------------------------------------------
create or replace function public.product_stock_by_warehouse(p_product_id uuid)
returns table(warehouse_id uuid, warehouse_name text, available integer)
language sql stable security definer set search_path to 'public' as $function$
  select w.id, w.name, coalesce(wi.current_qty, 0)::integer
    from public.warehouses w
    left join public.warehouse_inventory wi
      on wi.warehouse_id = w.id and wi.product_id = p_product_id
   where w.deleted_at is null
   order by coalesce(wi.current_qty, 0) desc, w.name
$function$;

-- Everything an approver needs for one request, in a single call.
create or replace function public.transfer_request_sourcing(p_request_id uuid)
returns table(
  line_id uuid, product_id uuid, product_name text, product_sku text,
  requested integer, approved integer,
  warehouse_id uuid, warehouse_name text, available integer, allocated integer)
language sql stable security definer set search_path to 'public' as $function$
  select l.id, l.product_id, p.name, p.sku,
         l.quantity, coalesce(l.approved_quantity, l.quantity),
         w.id, w.name, coalesce(wi.current_qty, 0)::integer,
         coalesce((select sum(ts.quantity) from public.transfer_line_sources ts
                    where ts.line_id = l.id and ts.source_id = w.id), 0)::integer
    from public.transfer_request_lines l
    join public.products p on p.id = l.product_id
    cross join public.warehouses w
    left join public.warehouse_inventory wi
      on wi.warehouse_id = w.id and wi.product_id = l.product_id
   where l.transfer_request_id = p_request_id
     and w.deleted_at is null
   order by p.name, coalesce(wi.current_qty, 0) desc, w.name
$function$;

-- ---------------------------------------------------------------------
-- Approve, drawing each line from one or several warehouses.
--
--   p_line_sources = [{ "line_id": "...", "sources": [ {"warehouse_id":"...","quantity":3}, ... ] }]
--
-- Passing nothing keeps the old behaviour: everything comes from
-- p_source_warehouse_id, so existing callers are unaffected.
-- ---------------------------------------------------------------------
create or replace function public.approve_transfer_multi(
  p_request_id uuid,
  p_approved_lines jsonb default null,
  p_note text default null,
  p_source_warehouse_id uuid default null,
  p_line_sources jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_req public.transfer_requests%rowtype;
  v_entry jsonb; v_src jsonb; v_line public.transfer_request_lines%rowtype;
  v_line_id uuid; v_wh uuid; v_qty integer; v_sum integer; v_approved integer;
  v_have integer; v_short text[] := '{}'; v_used uuid[] := '{}';
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can approve a transfer'; end if;

  select * into v_req from public.transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.status <> 'pending' then
    raise exception 'This request is % and can no longer be approved', v_req.status; end if;

  -- No per-line sourcing given: defer to the original single-warehouse path so
  -- nothing about the existing behaviour changes.
  if p_line_sources is null or jsonb_array_length(p_line_sources) = 0 then
    return public.approve_transfer(p_request_id, p_approved_lines, p_note, p_source_warehouse_id);
  end if;

  -- Record the split, validating each warehouse actually holds the stock.
  for v_entry in select * from jsonb_array_elements(p_line_sources)
  loop
    v_line_id := (v_entry->>'line_id')::uuid;
    select * into v_line from public.transfer_request_lines
     where id = v_line_id and transfer_request_id = p_request_id;
    if not found then raise exception 'Line % does not belong to this request', v_line_id; end if;

    v_approved := coalesce(v_line.approved_quantity, v_line.quantity);
    v_sum := 0;
    delete from public.transfer_line_sources where line_id = v_line_id;

    for v_src in select * from jsonb_array_elements(coalesce(v_entry->'sources','[]'::jsonb))
    loop
      v_wh := (v_src->>'warehouse_id')::uuid;
      v_qty := coalesce((v_src->>'quantity')::integer, 0);
      if v_qty <= 0 then continue; end if;

      select coalesce(current_qty,0) into v_have from public.warehouse_inventory
       where warehouse_id = v_wh and product_id = v_line.product_id;
      if coalesce(v_have,0) < v_qty then
        v_short := array_append(v_short,
          (select name from public.products where id = v_line.product_id)
          || ' at ' || (select name from public.warehouses where id = v_wh)
          || ' (need ' || v_qty || ', have ' || coalesce(v_have,0) || ')');
      end if;

      insert into public.transfer_line_sources (line_id, source_type, source_id, quantity, created_by)
      values (v_line_id, 'warehouse', v_wh, v_qty, auth.uid());
      v_sum := v_sum + v_qty;
      if not (v_wh = any(v_used)) then v_used := array_append(v_used, v_wh); end if;
    end loop;

    -- The split must account for exactly the approved quantity, or stock and
    -- paperwork disagree from the outset.
    if v_sum <> v_approved then
      raise exception 'Line "%" is approved for % but % was allocated across warehouses',
        (select name from public.products where id = v_line.product_id), v_approved, v_sum;
    end if;
  end loop;

  if array_length(v_short,1) is not null then
    raise exception 'Not enough stock: %', array_to_string(v_short, '; ');
  end if;

  -- Approve through the existing path, which owns the status change, the stock
  -- movements and the audit trail. A single source warehouse is still recorded
  -- on the header for continuity; the per-line detail is the authority.
  return public.approve_transfer(p_request_id, p_approved_lines, p_note,
                                 coalesce(p_source_warehouse_id, v_used[1]))
         || jsonb_build_object('warehouses_used', array_length(v_used,1),
                               'multi_source', array_length(v_used,1) > 1);
end $function$;

-- =====================================================================
-- PART B — THERAPY PACKAGES MAY GRANT VOUCHERS
-- =====================================================================

alter table public.unlimited_therapy_packages
  add column if not exists entitlement_kind text not null default 'unlimited';
alter table public.unlimited_therapy_packages
  add column if not exists voucher_qty integer;
alter table public.unlimited_therapy_packages
  add column if not exists voucher_id uuid references public.vouchers(id);

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'utp_entitlement_kind_check') then
    alter table public.unlimited_therapy_packages
      add constraint utp_entitlement_kind_check
      check (entitlement_kind in ('unlimited','voucher'));
  end if;
  -- A voucher package must say how many, and of what.
  if not exists (select 1 from pg_constraint where conname = 'utp_voucher_shape_check') then
    alter table public.unlimited_therapy_packages
      add constraint utp_voucher_shape_check
      check (entitlement_kind <> 'voucher'
             or (coalesce(voucher_qty,0) > 0 and voucher_id is not null));
  end if;
end $$;

-- Existing packages keep granting unlimited months, exactly as before.
update public.unlimited_therapy_packages
   set entitlement_kind = 'unlimited'
 where entitlement_kind is null;

-- ---------------------------------------------------------------------
-- Managing a package. The old signature is dropped first, or existing calls
-- become ambiguous — a trap this project has hit repeatedly.
-- ---------------------------------------------------------------------
drop function if exists public.upsert_unlimited_therapy_package(uuid, text, integer, text, boolean);

create or replace function public.upsert_unlimited_therapy_package(
  p_id uuid, p_name text, p_duration_months integer,
  p_description text default null, p_is_active boolean default true,
  p_entitlement_kind text default null, p_voucher_qty integer default null,
  p_voucher_id uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_kind text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage therapy packages'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'A package name is required'; end if;

  v_kind := coalesce(nullif(trim(p_entitlement_kind),''), 'unlimited');
  if v_kind not in ('unlimited','voucher') then
    raise exception 'The package must grant either unlimited therapy or vouchers'; end if;
  if v_kind = 'voucher' then
    if coalesce(p_voucher_qty,0) <= 0 then
      raise exception 'A voucher package needs a voucher quantity greater than zero'; end if;
    if p_voucher_id is null then
      raise exception 'Choose which voucher this package grants'; end if;
  end if;
  if v_kind = 'unlimited' and coalesce(p_duration_months,0) <= 0 then
    raise exception 'An unlimited therapy package needs a duration in months'; end if;

  if p_id is null then
    insert into public.unlimited_therapy_packages
      (name, duration_months, description, is_active, created_by,
       entitlement_kind, voucher_qty, voucher_id)
    values (trim(p_name), coalesce(p_duration_months, 1), p_description,
      coalesce(p_is_active, true), auth.uid(),
      v_kind, case when v_kind = 'voucher' then p_voucher_qty end,
      case when v_kind = 'voucher' then p_voucher_id end)
    returning id into v_id;
  else
    update public.unlimited_therapy_packages set
      name = trim(p_name),
      duration_months = coalesce(p_duration_months, duration_months),
      description = p_description,
      is_active = coalesce(p_is_active, is_active),
      entitlement_kind = v_kind,
      voucher_qty = case when v_kind = 'voucher' then p_voucher_qty end,
      voucher_id  = case when v_kind = 'voucher' then p_voucher_id end,
      updated_by = auth.uid(), updated_at = now()
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Therapy package not found'; end if;
  end if;

  perform public.write_audit_ex('unlimited_therapy_packages', v_id,
    case when p_id is null then 'therapy_package_created' else 'therapy_package_updated' end,
    null, jsonb_build_object('name', trim(p_name), 'kind', v_kind), 'catalogue', null, null);
  return v_id;
end $function$;

-- ---------------------------------------------------------------------
-- When a voucher package is bought, issue its vouchers rather than creating a
-- months-based entitlement. Hooked onto the existing purchased-therapy row so
-- the invoice, refund and reporting paths are untouched.
-- ---------------------------------------------------------------------
create or replace function public.trg_issue_therapy_package_vouchers()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare pk public.unlimited_therapy_packages%rowtype;
begin
  select * into pk from public.unlimited_therapy_packages where id = new.package_id;
  if not found or coalesce(pk.entitlement_kind,'unlimited') <> 'voucher' then return new; end if;
  if coalesce(pk.voucher_qty,0) <= 0 or pk.voucher_id is null then return new; end if;

  insert into public.customer_reward_vouchers
    (customer_id, voucher_id, entitlement_id, store_id, quantity, status, issued_by, notes,
     source_type, source_id)
  values (new.customer_id, pk.voucher_id, null, new.store_id, pk.voucher_qty, 'held', auth.uid(),
    'Therapy package: ' || pk.name, 'therapy_package', new.id);

  -- The entitlement row itself is not a months-based one; mark it so reports
  -- and the activation screen do not offer to activate it.
  update public.purchased_therapy_entitlements
     set status = 'active', activation_date = public.sg_today(),
         expiry_date = null, updated_at = now()
   where id = new.id;

  perform public.write_audit_ex('purchased_therapy_entitlements', new.id,
    'therapy_package_vouchers_issued', null,
    jsonb_build_object('voucher_qty', pk.voucher_qty, 'package', pk.name),
    'therapy', null, new.store_id);
  return new;
end $function$;

drop trigger if exists issue_therapy_package_vouchers on public.purchased_therapy_entitlements;
create trigger issue_therapy_package_vouchers
  after insert on public.purchased_therapy_entitlements
  for each row execute function public.trg_issue_therapy_package_vouchers();

-- ---------------------------------------------------------------------
-- Raise a request WITHOUT naming a source, so the warehouses are chosen at
-- approval. This is the point of multi-warehouse sourcing: with a single
-- header source, create_transfer_request refuses the moment one warehouse
-- cannot cover a line, which is exactly the case being solved.
--
-- Staff requests already defer the source; this offers the same to an Owner
-- or Manager raising the request themselves.
-- ---------------------------------------------------------------------
create or replace function public.create_deferred_transfer_request(
  p_dest_type public.location_type, p_dest_id uuid,
  p_lines jsonb, p_note text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_l jsonb; v_ids uuid[] := '{}';
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can raise a transfer for approval'; end if;
  if p_dest_id is null then raise exception 'Choose a destination'; end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one product'; end if;

  -- A store destination still needs prices, or the stock cannot be sold on
  -- arrival. Checked here rather than at approval, when it is too late.
  if p_dest_type = 'store' then
    for v_l in select * from jsonb_array_elements(p_lines) loop
      v_ids := array_append(v_ids, (v_l->>'product_id')::uuid);
    end loop;
    perform public.assert_transfer_prices_ok(p_dest_id, v_ids);
  end if;

  insert into public.transfer_requests
    (transfer_type, source_type, source_id, dest_type, dest_id, status, note, requested_by)
  values (
    case when p_dest_type = 'store' then 'warehouse_to_store' else 'warehouse_to_warehouse' end,
    null, null, p_dest_type, p_dest_id, 'pending', p_note, auth.uid())
  returning id into v_id;

  for v_l in select * from jsonb_array_elements(p_lines) loop
    if coalesce((v_l->>'quantity')::integer, 0) <= 0 then continue; end if;
    insert into public.transfer_request_lines (transfer_request_id, product_id, quantity)
    values (v_id, (v_l->>'product_id')::uuid, (v_l->>'quantity')::integer);
  end loop;

  perform public.write_audit_ex('transfer_requests', v_id, 'transfer_requested', null,
    jsonb_build_object('dest', p_dest_id, 'source', 'deferred to approval'),
    'inventory', p_note, case when p_dest_type = 'store' then p_dest_id end);
  return v_id;
end $function$;

notify pgrst, 'reload schema';
