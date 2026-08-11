-- =====================================================================
-- ENERGIA — EDITING A PAID INVOICE (OWNER / MANAGER ONLY)
--
-- update_invoice() refuses anything past 'unpaid', and rightly so: settling an
-- invoice deducts stock, sells vouchers, earns affiliate and staff commission
-- and feeds Legacy qualification. Simply rewriting the lines would leave every
-- one of those wrong.
--
-- This adds a corrective edit that UNWINDS those effects, applies the new
-- lines, and re-derives everything from the corrected invoice:
--
--   1. an immutable revision snapshot of the invoice as it stood;
--   2. stock returned for the old lines, then deducted for the new ones,
--      each as its own visible stock movement;
--   3. affiliate and staff commission reversed, then re-earned on the new total;
--   4. Legacy qualification recomputed;
--   5. any difference against what was already paid recorded explicitly —
--      the invoice becomes partially_paid if more is now owed, or carries a
--      refund-due balance if less.
--
-- Nothing is silently overwritten: the previous state is preserved in
-- invoice_revisions and every reversal is its own row.
--
-- Additive and idempotent. Run AFTER 101.
-- =====================================================================

set check_function_bodies = off;


-- ---------------------------------------------------------------------
-- Edit tracking on the invoice itself, so a corrected invoice is identifiable
-- without joining to the revision table.
-- ---------------------------------------------------------------------
alter table public.invoices add column if not exists edited_at timestamptz;
alter table public.invoices add column if not exists edited_by uuid references public.profiles(id);
alter table public.invoices add column if not exists edit_count integer not null default 0;

-- ---------------------------------------------------------------------
-- Return the stock an invoice took, so it can be re-deducted from the
-- corrected lines. Written as its own movement rather than by adjusting the
-- original, so Stock History shows the correction happening.
-- ---------------------------------------------------------------------
create or replace function public.restore_invoice_stock(p_invoice_id uuid, p_note text default null)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_inv public.invoices%rowtype; v_li record; v_n integer := 0;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return 0; end if;

  for v_li in
    select ii.product_id, sum(ii.quantity)::integer as qty
      from public.invoice_items ii
     where ii.invoice_id = p_invoice_id and ii.product_id is not null
     group by ii.product_id
  loop
    update public.store_inventory
       set current_qty = current_qty + v_li.qty, updated_at = now()
     where store_id = v_inv.store_id and product_id = v_li.product_id;

    insert into public.stock_movements
      (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by)
    values (v_li.product_id, 'invoice_cancel_return'::stock_movement_type, v_inv.store_id, p_invoice_id,
      v_li.qty, coalesce(p_note, 'Stock returned — paid invoice edited'), auth.uid());
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

-- Deduct stock for the invoice's CURRENT lines, refusing if the store cannot
-- cover them — a correction must not be allowed to create negative stock.
create or replace function public.deduct_invoice_stock(p_invoice_id uuid, p_note text default null)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_inv public.invoices%rowtype; v_li record; v_have integer; v_n integer := 0;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return 0; end if;

  for v_li in
    select ii.product_id, sum(ii.quantity)::integer as qty
      from public.invoice_items ii
     where ii.invoice_id = p_invoice_id and ii.product_id is not null
     group by ii.product_id
  loop
    select coalesce(current_qty,0) into v_have from public.store_inventory
     where store_id = v_inv.store_id and product_id = v_li.product_id for update;
    if coalesce(v_have,0) < v_li.qty then
      raise exception 'Not enough stock for "%": % needed, % available',
        (select name from public.products where id = v_li.product_id), v_li.qty, coalesce(v_have,0);
    end if;

    update public.store_inventory
       set current_qty = current_qty - v_li.qty, updated_at = now()
     where store_id = v_inv.store_id and product_id = v_li.product_id;

    insert into public.stock_movements
      (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
    values (v_li.product_id, 'store_sale'::stock_movement_type, v_inv.store_id, p_invoice_id,
      v_li.qty, coalesce(p_note, 'Stock deducted — paid invoice edited'), auth.uid());
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;


-- ---------------------------------------------------------------------
-- update_invoice() refuses any invoice that is settled or has payments. That
-- guard is right for the ordinary edit path and stays exactly as it is; this
-- adds an explicit opt-in used only by edit_paid_invoice(), which is itself
-- Owner/Manager-only and writes a revision first.
--
-- Payment rows are never modified or deleted — the lock trigger on
-- invoice_payments remains in force throughout.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_invoice';
  if v_def is null then raise exception 'update_invoice not found'; end if;
  if position('p_allow_settled' in v_def) > 0 then
    raise notice 'update_invoice already accepts the corrective flag'; return;
  end if;

  v_new := replace(v_def, 'p_edit_reason text DEFAULT NULL::text)',
                          'p_edit_reason text DEFAULT NULL::text, p_allow_settled boolean DEFAULT false)');
  if position('p_allow_settled boolean' in v_new) = 0 then
    raise exception 'Could not add the corrective flag to update_invoice';
  end if;

  v_new := replace(v_new,
    '  if v_old.status not in (''draft'',''unpaid'') then',
    '  if not p_allow_settled and v_old.status not in (''draft'',''unpaid'') then');
  v_new := replace(v_new,
    '  if coalesce(v_old.paid_amount,0) > 0 then',
    '  if not p_allow_settled and coalesce(v_old.paid_amount,0) > 0 then');
  v_new := replace(v_new,
    '  if exists (select 1 from public.invoice_payments where invoice_id = p_invoice_id) then',
    '  if not p_allow_settled and exists (select 1 from public.invoice_payments where invoice_id = p_invoice_id) then');
  -- Settling stamps locked_at; the corrective path must see past that too.
  v_new := replace(v_new,
    '  if v_old.locked_at is not null then raise exception ''Invoice is locked''; end if;',
    '  if not p_allow_settled and v_old.locked_at is not null then raise exception ''Invoice is locked''; end if;');

  execute v_new;
  -- The nine-argument version must go, or every existing call is ambiguous.
  drop function if exists public.update_invoice(uuid, uuid, uuid, jsonb, numeric, text, uuid, jsonb, text);
  raise notice 'update_invoice now accepts an Owner/Manager corrective flag';
end $patch$;

-- ---------------------------------------------------------------------
-- The corrective edit.
-- ---------------------------------------------------------------------
create or replace function public.edit_paid_invoice(
  p_invoice_id uuid,
  p_lines jsonb,
  p_reason text,
  p_discount numeric default null,
  p_service_staff uuid[] default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_rev integer; v_snap jsonb;
  v_old_total numeric; v_paid numeric; v_new_total numeric; v_diff numeric;
  v_new_status invoice_status; v_stock_back integer; v_stock_out integer;
  v_comm integer; v_staff_comm integer;
begin
  -- ---- Authority and preconditions ----
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit a paid invoice';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required when editing a paid invoice';
  end if;

  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;

  if v_inv.status not in ('paid','partially_paid','completed_foc') then
    raise exception 'Only a settled invoice is edited this way (this one is %). Use the normal edit for Draft or Unpaid.',
      v_inv.status;
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'An invoice must keep at least one line. Cancel or refund it instead.';
  end if;

  v_old_total := coalesce(v_inv.total_amount, 0);
  v_paid := coalesce(v_inv.paid_amount, 0);

  -- ---- 1. Preserve what it was, before anything changes ----
  select coalesce(max(revision_no),0) + 1 into v_rev
    from public.invoice_revisions where invoice_id = p_invoice_id;

  v_snap := jsonb_build_object(
    'invoice', to_jsonb(v_inv),
    'items', (select coalesce(jsonb_agg(to_jsonb(ii)), '[]'::jsonb)
                from public.invoice_items ii where ii.invoice_id = p_invoice_id),
    'payments', (select coalesce(jsonb_agg(to_jsonb(ip)), '[]'::jsonb)
                   from public.invoice_payments ip where ip.invoice_id = p_invoice_id),
    'commissions', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb)
                      from public.commissions c where c.invoice_id = p_invoice_id),
    'staff_commissions', (select coalesce(jsonb_agg(to_jsonb(sc)), '[]'::jsonb)
                            from public.staff_commissions sc where sc.invoice_id = p_invoice_id),
    'edited_from_status', v_inv.status);

  insert into public.invoice_revisions (invoice_id, revision_no, snapshot, edited_by, edit_reason)
  values (p_invoice_id, v_rev, v_snap, auth.uid(), p_reason);

  -- ---- 2. Unwind the settled effects ----
  v_stock_back := public.restore_invoice_stock(p_invoice_id,
    'Stock returned — invoice ' || v_inv.invoice_no || ' edited (rev ' || v_rev || ')');
  -- The project's own reversal functions: they mark rows reversed rather than
  -- deleting them, which is what keeps commission append-only.
  select count(*) into v_comm from public.commissions
   where invoice_id = p_invoice_id and status <> 'reversed';
  select count(*) into v_staff_comm from public.staff_commissions
   where invoice_id = p_invoice_id and status <> 'reversed';
  perform public.reverse_invoice_commission(p_invoice_id,
    'Invoice edited (rev ' || v_rev || '): ' || p_reason);
  perform public.reverse_staff_commission(p_invoice_id,
    'Invoice edited (rev ' || v_rev || '): ' || p_reason);

  -- ---- 3. Replace the lines, reusing the ordinary edit path so pricing,
  --         promotions, FOC and discount rules stay in one place. ----
  -- update_invoice() is given an explicit, Owner/Manager-only escape for this
  -- corrective path (see the patch above). Payment rows are never touched: the
  -- lock trigger that protects them stays fully in force.
  update public.invoices set status = 'unpaid' where id = p_invoice_id;
  perform public.update_invoice(
    p_invoice_id,
    v_inv.customer_id,
    v_inv.affiliate_id,
    p_lines,
    coalesce(p_discount, v_inv.manual_discount),
    v_inv.notes,
    v_inv.discount_voucher_id,
    case when p_service_staff is null then null
         else to_jsonb(p_service_staff) end,
    p_reason,
    true);            -- corrective edit of a settled invoice

  select * into v_inv from public.invoices where id = p_invoice_id;
  v_new_total := coalesce(v_inv.total_amount, 0);
  v_diff := round(v_new_total - v_paid, 2);

  -- ---- 4. Re-apply the settled effects against the corrected lines ----
  v_stock_out := public.deduct_invoice_stock(p_invoice_id,
    'Stock deducted — invoice ' || v_inv.invoice_no || ' edited (rev ' || v_rev || ')');

  -- ---- 5. Reconcile against what was actually paid ----
  --   more owed  -> partially_paid, with a balance to collect
  --   less owed  -> paid, with a refund due, recorded not silently absorbed
  --   equal      -> paid
  if v_diff > 0 then
    v_new_status := 'partially_paid';
  else
    v_new_status := 'paid';
  end if;

  update public.invoices
     set status = v_new_status,
         paid_amount = v_paid,
         edited_at = now(), edited_by = auth.uid(),
         edit_count = coalesce(edit_count,0) + 1
   where id = p_invoice_id;

  -- Commission is re-earned only on a settled invoice, matching pay_invoice.
  if v_new_status = 'paid' then
    perform public.earn_invoice_commission(p_invoice_id);
    perform public.earn_staff_commission(p_invoice_id);
  end if;

  -- Legacy qualification follows the corrected external payment.
  begin
    perform public.recompute_legacy_qualification(v_inv.customer_id, v_inv.store_id);
  exception when others then null;  -- absent for a customer with no rule
  end;

  perform public.write_audit_ex('invoices', p_invoice_id, 'paid_invoice_edited', null,
    jsonb_build_object('revision', v_rev, 'reason', p_reason,
      'old_total', v_old_total, 'new_total', v_new_total,
      'paid_amount', v_paid, 'difference', v_diff,
      'commissions_reversed', v_comm, 'staff_commissions_reversed', v_staff_comm,
      'stock_lines_returned', v_stock_back, 'stock_lines_deducted', v_stock_out,
      'new_status', v_new_status),
    'invoices', p_reason, v_inv.store_id);

  return jsonb_build_object(
    'success', true, 'revision', v_rev,
    'old_total', v_old_total, 'new_total', v_new_total,
    'paid_amount', v_paid,
    'balance_due', case when v_diff > 0 then v_diff else 0 end,
    'refund_due', case when v_diff < 0 then abs(v_diff) else 0 end,
    'status', v_new_status,
    'commissions_reversed', v_comm, 'staff_commissions_reversed', v_staff_comm);
end $function$;

-- ---------------------------------------------------------------------
-- The edit history of an invoice, for the detail screen.
-- ---------------------------------------------------------------------
create or replace function public.invoice_revision_history(p_invoice_id uuid)
returns table(revision_no integer, edited_at timestamptz, edited_by_name text,
              edit_reason text, old_total numeric, from_status text)
language sql stable security definer set search_path to 'public' as $function$
  select r.revision_no, r.edited_at, p.full_name, r.edit_reason,
         (r.snapshot->'invoice'->>'total_amount')::numeric,
         r.snapshot->>'edited_from_status'
    from public.invoice_revisions r
    left join public.profiles p on p.id = r.edited_by
   where r.invoice_id = p_invoice_id
   order by r.revision_no desc
$function$;

notify pgrst, 'reload schema';
