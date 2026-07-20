-- =====================================================================
-- ENERGIA — 49: PHASE 4 FINAL CORRECTIONS (database)
--
-- 47/48/48b/48c are executed and untouched. This additive migration fixes
-- the remaining Phase 4 issues from the verification report. Idempotent;
-- historical paid invoices, payments, stock, commission, referral and audit
-- history are all preserved.
--
-- NOTE ON NUMBERING: the original plan reserved 49 for Phase 5. Phase 4's
-- corrections consumed 48b/48c, so this Phase 4 file takes 49 and Phase 5
-- will begin at 50. (Recorded in the report.)
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- A. Promotion top-up regression — restore the 21b "listed option pays no
--    top-up" rule inside the mode-aware 4-arg function.
-- =====================================================================
create or replace function public.promotion_selections_topup(
  p_promotion_id uuid, p_store_id uuid, p_selections jsonb, p_is_member boolean
) returns numeric language plpgsql stable security definer set search_path = public as $$
declare
  v_grp record; v_sel jsonb; v_opt jsonb; v_baseline numeric; v_price numeric;
  v_topup numeric := 0; v_qty integer; v_pj jsonb;
begin
  for v_grp in select * from public.promotion_choice_groups
    where promotion_id = p_promotion_id and item_kind = 'product'
  loop
    -- Baseline = cheapest LISTED option at this store in the applied mode.
    select min(case when p_is_member then spp.member_price else spp.non_member_price end)
      into v_baseline
    from public.promotion_choice_options o
    join public.store_product_prices spp
      on spp.product_id = o.product_id and spp.store_id = p_store_id
     and spp.is_active = true and spp.deleted_at is null
    where o.group_id = v_grp.id and o.product_id is not null;
    if v_baseline is null then continue; end if;

    for v_sel in select * from jsonb_array_elements(coalesce(p_selections,'[]'::jsonb))
    loop
      if (v_sel->>'group_id')::uuid <> v_grp.id then continue; end if;
      for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
      loop
        v_qty := coalesce((v_opt->>'quantity')::integer, 0);
        if v_qty <= 0 or (v_opt->>'product_id') is null then continue; end if;

        -- 21b RULE (restored): a selected product that IS one of the group's
        -- listed included options never pays a top-up.
        if exists (
          select 1 from public.promotion_choice_options o
          where o.group_id = v_grp.id and o.product_id = (v_opt->>'product_id')::uuid
        ) then continue; end if;

        -- Unlisted allowed pick: price it strictly in the applied mode.
        v_pj := public.product_price_for(p_store_id, (v_opt->>'product_id')::uuid, p_is_member);
        if not coalesce((v_pj->>'has_price')::boolean, false) then
          raise exception 'Product "%" is missing its % price at this store (needed for the bundle top-up)',
            (select name from public.products where id = (v_opt->>'product_id')::uuid),
            case when p_is_member then 'Member' else 'Non-Member' end;
        end if;
        v_price := (v_pj->>'price')::numeric;
        if v_price > v_baseline then v_topup := v_topup + (v_price - v_baseline) * v_qty; end if;
      end loop;
    end loop;
  end loop;
  return round(v_topup, 2);
end $$;

-- =====================================================================
-- L. Promotion choice eligibility resolver (used by create + reprice).
--    Enforces Member-Only / Non-Member-Only on each chosen product in the
--    applied mode; override lifts it only when the promotion line itself is
--    overridden. Missing/inactive/wrong-store price blocks.
-- =====================================================================
create or replace function public.assert_promotion_choices_ok(
  p_invoice_item_id uuid, p_store_id uuid, p_is_member boolean, p_overridden boolean
) returns void language plpgsql stable security definer set search_path = public as $$
declare v_s record; v_pj jsonb;
begin
  for v_s in
    select s.product_id, s.voucher_id, p.name as pname
    from public.invoice_promotion_selections s
    left join public.products p on p.id = s.product_id
    where s.invoice_item_id = p_invoice_item_id and s.product_id is not null
  loop
    v_pj := public.product_price_for(p_store_id, v_s.product_id, p_is_member);
    if not coalesce((v_pj->>'found')::boolean,false) then
      raise exception 'Promotion choice "%" has no price row at this store', v_s.pname; end if;
    if not p_overridden and not coalesce((v_pj->>'eligible')::boolean,false) then
      raise exception 'Promotion choice "%" is % — not allowed for this customer without a line override',
        v_s.pname, replace(v_pj->>'eligibility','_',' '); end if;
    if not coalesce((v_pj->>'has_price')::boolean,false) then
      raise exception 'Promotion choice "%" is missing its % price at this store', v_s.pname,
        case when p_is_member then 'Member' else 'Non-Member' end; end if;
  end loop;
end $$;

-- =====================================================================
-- B/G. reprice_invoice_lines v3 — recompute promotion top-ups from stored
--   selections in the applied mode, enforce choice eligibility, and report
--   financially-relevant changes (top-up, discount, subtotal, total) even
--   when no unit price moved.
-- =====================================================================
create or replace function public.reprice_invoice_lines(p_invoice_id uuid, p_is_member boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_li record; v_pj jsonb; v_new numeric;
  v_changes jsonb := '[]'::jsonb; v_subtotal numeric; v_mode text;
  v_old_line_disc numeric; v_new_line_disc numeric;
  v_old_sub numeric; v_old_disc numeric; v_old_total numeric;
  v_line_member boolean; v_new_topup numeric;
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
  loop
    -- Overridden lines keep their explicit mode; non-overridden follow member.
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
      update public.invoice_items set unit_price = v_new,
        line_total = (v_new * quantity),
        line_discount = case when line_voucher_id is not null then public.voucher_discount_amount(line_voucher_id, v_new*quantity) else line_discount end,
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
      update public.invoice_items set unit_price=v_new, line_total=(v_new*quantity),
        price_mode=v_mode, price_source='voucher', price_source_id=(v_pj->>'source_id')::uuid,
        store_id_snapshot=v_inv.store_id,
        member_price_snapshot=(v_pj->>'member_price')::numeric, non_member_price_snapshot=(v_pj->>'non_member_price')::numeric,
        original_price=coalesce(original_price, v_li.unit_price)
       where id = v_li.id;

    else -- promotion: reprice base AND recompute top-up from stored selections
      v_pj := public.promotion_price_for(v_inv.store_id, v_li.promotion_id, v_line_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_li.prname, case when v_line_member then 'Member' else 'Non-Member' end; end if;
      -- Eligibility on each chosen product (override state from the line).
      perform public.assert_promotion_choices_ok(v_li.id, v_inv.store_id, v_line_member, coalesce(v_li.price_overridden,false));
      v_new := (v_pj->>'price')::numeric;
      -- Rebuild the selections jsonb the topup function expects.
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
      update public.invoice_items set unit_price=v_new, topup_amount=v_new_topup,
        line_total=(v_new*quantity) + coalesce(v_new_topup,0),
        price_mode=v_mode, price_source='promotion', price_source_id=(v_pj->>'source_id')::uuid,
        store_id_snapshot=v_inv.store_id,
        member_price_snapshot=(v_pj->>'member_price')::numeric, non_member_price_snapshot=(v_pj->>'non_member_price')::numeric,
        original_price=coalesce(original_price, v_li.unit_price)
       where id = v_li.id;
    end if;
  end loop;

  -- Rebuild money (A4 model): subtotal gross, discount rebuilt once, total floored.
  select coalesce(sum(line_total),0) into v_subtotal from public.invoice_items where invoice_id = p_invoice_id;
  select coalesce(sum(coalesce(line_discount,0)),0) into v_new_line_disc from public.invoice_items where invoice_id = p_invoice_id;
  update public.invoices set subtotal = v_subtotal where id = p_invoice_id;
  if v_inv.manual_discount is not null then
    perform public.refresh_invoice_discount_total(p_invoice_id);
  else
    update public.invoices set discount_total = greatest(0, coalesce(discount_total,0) + (v_new_line_disc - v_old_line_disc)) where id = p_invoice_id;
  end if;
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0)) where i.id = p_invoice_id;

  if exists (select 1 from public.invoices where id = p_invoice_id and total_amount + 0.001 < paid_amount) then
    raise exception 'Repricing would reduce the total below the amount already paid'; end if;

  -- G: report discount/subtotal/total moves even if no unit price changed.
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
-- H. Block deletion of partially-paid invoices; keep paid block.
-- =====================================================================
create or replace function public.delete_invoice(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_pays integer;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access'; end if;
  -- Recheck payment existence AFTER the lock (race-safe).
  select count(*) into v_pays from public.invoice_payments where invoice_id = p_invoice_id;
  if v_inv.status = 'paid' or v_inv.status = 'partially_paid'
     or coalesce(v_inv.paid_amount,0) > 0 or v_pays > 0 then
    raise exception 'Invoices with a recorded payment cannot be deleted — use the cancel/refund workflow';
  end if;
  update public.invoices set deleted_at = now() where id = p_invoice_id;
  perform public.write_audit('invoices', p_invoice_id, 'invoice_deleted', to_jsonb(v_inv), null);
end; $$;

-- =====================================================================
-- I. Server-side permanent Member ID reuse + conflicting-reservation fix.
-- =====================================================================
-- Authoritative owned-ID lookup.
create or replace function public.customer_owned_member_id(p_customer_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select member_id from public.member_ids where customer_id = p_customer_id
$$;

-- Reserve: if the customer already OWNS an id, forbid reserving a different
-- one (their permanent id is reused). Replace a conflicting reservation safely.
create or replace function public.reserve_member_id(
  p_member_id text, p_customer_id uuid, p_invoice_id uuid default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_id text; v_inv public.invoices%rowtype; v_owned text; v_role user_role;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile'; end if;
  if v_role = 'inventory_manager' then raise exception 'Inventory Manager cannot manage Member IDs'; end if;
  v_id := nullif(trim(p_member_id), '');
  if v_id is null then raise exception 'Member ID is required'; end if;

  v_owned := public.customer_owned_member_id(p_customer_id);
  if v_owned is not null and v_owned <> v_id then
    raise exception 'This customer permanently owns Member ID % — it must be reused (cannot reserve a different ID)', v_owned;
  end if;

  if p_invoice_id is not null then
    select * into v_inv from public.invoices where id = p_invoice_id for update;
    if not found then raise exception 'Invoice not found'; end if;
    if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
    if v_inv.customer_id <> p_customer_id then raise exception 'The reservation customer does not match the invoice customer'; end if;
    -- H: never touch reservations once any payment exists.
    if v_inv.status in ('paid','cancelled','refunded') or coalesce(v_inv.paid_amount,0) > 0
       or exists (select 1 from public.invoice_payments where invoice_id = p_invoice_id) then
      raise exception 'A payment has been recorded — the Member ID can no longer be changed'; end if;
  elsif not public.is_manager_or_above() then
    raise exception 'Only a Manager or above can reserve a Member ID without an invoice';
  end if;

  if exists (select 1 from public.member_ids where member_id = v_id and customer_id <> p_customer_id) then
    raise exception 'Member ID % is already assigned to another customer', v_id; end if;
  if exists (select 1 from public.member_id_reservations where member_id = v_id and customer_id <> p_customer_id) then
    raise exception 'Member ID % is currently reserved for another customer', v_id; end if;
  if v_owned = v_id then return; end if;  -- already owned by this customer

  delete from public.member_id_reservations where customer_id = p_customer_id and member_id <> v_id;
  insert into public.member_id_reservations (member_id, customer_id, invoice_id, reserved_by)
  values (v_id, p_customer_id, p_invoice_id, auth.uid())
  on conflict (member_id) do update
    set invoice_id = excluded.invoice_id, reserved_at = now(), reserved_by = auth.uid()
    where public.member_id_reservations.customer_id = excluded.customer_id;
end $$;

-- Explicit "replace a conflicting reservation on this invoice" flow (I).
create or replace function public.replace_invoice_member_id(
  p_invoice_id uuid, p_new_member_id text
) returns void language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.status in ('paid','cancelled','refunded') or coalesce(v_inv.paid_amount,0) > 0
     or exists (select 1 from public.invoice_payments where invoice_id = p_invoice_id) then
    raise exception 'A payment has been recorded — the Member ID can no longer be changed'; end if;
  delete from public.member_id_reservations where invoice_id = p_invoice_id;
  perform public.reserve_member_id(p_new_member_id, v_inv.customer_id, p_invoice_id);
end $$;

-- H: reservation-release trigger must NOT fire once any payment exists.
create or replace function public.trg_release_reservations_dead_invoice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(old.paid_amount,0) > 0 then return null; end if;   -- keep ID once paid into
  if exists (select 1 from public.invoice_payments where invoice_id = new.id) then return null; end if;
  if (new.deleted_at is not null and old.deleted_at is null)
     or (new.status = 'cancelled' and old.status is distinct from 'cancelled') then
    delete from public.member_id_reservations where invoice_id = new.id;
  end if;
  return null;
end $$;

-- =====================================================================
-- F. Database-level role enforcement — inventory_manager blocked from all
--    Phase 4 pricing/membership actions. (override + reserve already gate;
--    add the membership-line + create_invoice guards here.)
-- =====================================================================
-- Guard trigger: no inventory_manager may write a membership line, and a
-- membership line must be qty=1, non-stock, with plan + store-price snapshot (J).
create or replace function public.trg_membership_line_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.line_kind = 'membership' then
    if public.current_user_role() = 'inventory_manager' then
      raise exception 'Inventory Manager cannot sell memberships'; end if;
    if new.quantity <> 1 then raise exception 'A membership line must have quantity exactly 1'; end if;
    if new.product_id is not null then raise exception 'A membership line is non-stock (no product)'; end if;
    if new.membership_plan_id is null then raise exception 'Membership line requires a plan'; end if;
    if new.plan_months_snapshot is null or new.plan_name_snapshot is null then
      raise exception 'Membership line requires plan snapshots'; end if;
  end if;
  return new;
end $$;

drop trigger if exists membership_line_guard on public.invoice_items;
create trigger membership_line_guard
  before insert or update on public.invoice_items
  for each row execute function public.trg_membership_line_guard();

-- =====================================================================
-- J. Membership quantity / single-line constraints (table-level).
-- =====================================================================
-- qty=1 for membership lines (validated for new/updated rows via CHECK NOT
-- VALID so historical rows are untouched).
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chk_membership_qty_one') then
    alter table public.invoice_items
      add constraint chk_membership_qty_one
      check (line_kind <> 'membership' or quantity = 1) not valid;
  end if;
end $$;
-- one membership line per invoice already enforced by uq_invoice_one_membership (48b).

notify pgrst, 'reload schema';

-- =====================================================================
-- E. Create-time override audit + correct original_price.
--    create_invoice (48b) stamps overridden lines but (a) set original_price
--    to the override price and (b) wrote no line_price_overridden audit row.
--    Rather than rewrite that large function, we expose a helper the frontend
--    calls right after creation for each overridden line, and we also make
--    create_invoice-produced rows self-correct: original_price should hold the
--    AUTOMATIC price. We compute it from the snapshots.
-- =====================================================================
create or replace function public.audit_create_time_override(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype;
        v_auto_member boolean; v_auto_price numeric; v_ms jsonb;
begin
  select * into v_li from public.invoice_items where id = p_item_id;
  if not found or not coalesce(v_li.price_overridden,false) then return; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id;

  -- Automatic mode = what the customer would get without the override.
  v_ms := public.customer_membership_status(v_inv.customer_id);
  v_auto_member := coalesce((v_ms->>'is_member')::boolean,false)
                   or exists (select 1 from public.invoice_items x
                               where x.invoice_id = v_inv.id and x.line_kind = 'membership');
  v_auto_price := case when v_auto_member then v_li.member_price_snapshot else v_li.non_member_price_snapshot end;

  -- original_price should reflect the AUTOMATIC price, not the applied override.
  update public.invoice_items
     set original_price = coalesce(v_auto_price, original_price)
   where id = p_item_id;

  perform public.write_audit_ex('invoice_items', p_item_id, 'line_price_overridden',
    jsonb_build_object('previous_mode', case when v_auto_member then 'member' else 'non_member' end,
                       'previous_price', v_auto_price),
    jsonb_build_object('new_mode', v_li.price_mode, 'applied_price', v_li.unit_price,
                       'member_snapshot', v_li.member_price_snapshot,
                       'non_member_snapshot', v_li.non_member_price_snapshot,
                       'reason', v_li.override_reason, 'line_kind', v_li.line_kind,
                       'source_id', v_li.price_source_id, 'invoice_item_id', p_item_id,
                       'invoice_id', v_inv.id, 'customer_id', v_inv.customer_id),
    'pricing', v_li.override_reason, v_inv.store_id);
end $$;

notify pgrst, 'reload schema';
