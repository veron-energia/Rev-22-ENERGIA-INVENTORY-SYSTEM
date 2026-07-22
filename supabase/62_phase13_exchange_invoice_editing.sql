-- =====================================================================
-- ENERGIA — PHASE 13: EXCHANGE INVOICES + UNPAID INVOICE EDITING
--
-- SCOPE A — Exchange Invoices
--   Every completed exchange creates a linked, locked Exchange Invoice
--   numbered  {CountryCode}-{StoreCode}-EX-INV-{Year}-{Sequence}
--   e.g.      SG-AD-EX-INV-2026-00001
--   Sequence is unique per store per year and resets annually.
--
--   Money model on the exchange invoice (drives financial reporting):
--     * replacement lines carry their FULL value  -> subtotal = gross sales
--     * the exchange deduction (returned credit applied + any FOC-waived
--       top-up) is allocated across those lines as line_discount
--     * discount_total = subtotal - top-up,  total_amount = top-up
--   Because affiliate commission is computed from (line_total -
--   line_discount) and staff commission from total_amount, BOTH commission
--   engines therefore price the exchange at the PAID TOP-UP VALUE ONLY —
--   by construction, reusing the existing battle-tested allocators
--   (third-party rates, tier-2, promotion splits) unchanged.
--
--   The invoice is created by a DEFERRED constraint trigger on
--   product_exchanges, so it fires at COMMIT — after the exchange
--   function has inserted its items and payments — and covers all three
--   exchange paths (product, bundle, bundle-component) plus any future
--   ones, without rewriting them.
--
-- SCOPE B — Unpaid Invoice Editing (further below)
--
-- Additive + idempotent. Run AFTER 61.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- A1. Mandatory country / store codes.
-- ---------------------------------------------------------------------
alter table public.stores add column if not exists country_code text not null default 'SG';
do $$ begin
  alter table public.stores add constraint chk_stores_country_code check (length(trim(country_code)) between 2 and 3);
exception when duplicate_object then null; when others then null; end $$;

-- ---------------------------------------------------------------------
-- A2. Linkage columns.
-- ---------------------------------------------------------------------
alter table public.invoices add column if not exists is_exchange boolean not null default false;
alter table public.invoices add column if not exists exchange_id uuid references public.product_exchanges(id);
alter table public.invoices add column if not exists exchange_credit_total numeric(12,2) not null default 0;
alter table public.product_exchanges add column if not exists exchange_invoice_id uuid references public.invoices(id);
create index if not exists idx_invoices_exchange on public.invoices(exchange_id) where exchange_id is not null;

-- ---------------------------------------------------------------------
-- A3. Exchange-invoice numbering.
--     {CC}-{STORE}-EX-INV-{YYYY}-{00001}; per-store, per-year; annual reset.
-- ---------------------------------------------------------------------
create or replace function public.next_exchange_invoice_no(p_store_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_cc text; v_sc text; v_year text := to_char(now() at time zone 'Asia/Singapore', 'YYYY');
  v_prefix text; v_count integer; v_next text;
begin
  select upper(trim(country_code)), upper(trim(code)) into v_cc, v_sc
    from public.stores where id = p_store_id;
  if v_cc is null or v_cc = '' then raise exception 'Store has no country code — set it before creating exchange invoices'; end if;
  if v_sc is null or v_sc = '' then raise exception 'Store has no store code — set it before creating exchange invoices'; end if;

  v_prefix := v_cc || '-' || v_sc || '-EX-INV-' || v_year || '-';
  -- Count THIS store's exchange invoices for THIS year (soft-deleted included,
  -- so numbers are never reused), then bump past any rare collision.
  select count(*) into v_count from public.invoices
    where store_id = p_store_id and is_exchange = true and invoice_no like v_prefix || '%';
  v_next := v_prefix || lpad((v_count + 1)::text, 5, '0');
  while exists (select 1 from public.invoices where invoice_no = v_next) loop
    v_count := v_count + 1;
    v_next := v_prefix || lpad((v_count + 1)::text, 5, '0');
  end loop;
  return v_next;
end $$;

-- ---------------------------------------------------------------------
-- A4. Build the Exchange Invoice for a completed exchange. Idempotent:
--     a second call for the same exchange is a no-op.
-- ---------------------------------------------------------------------
create or replace function public.create_exchange_invoice(p_exchange_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ex public.product_exchanges%rowtype;
  v_orig public.invoices%rowtype;
  v_inv_id uuid; v_no text;
  v_repl_total numeric := 0; v_deduction numeric; v_credit_applied numeric;
  v_alloc numeric := 0; v_line_disc numeric; v_running numeric := 0;
  v_li record; v_n integer; v_i integer := 0;
  v_creator_role user_role;
begin
  select * into v_ex from public.product_exchanges where id = p_exchange_id for update;
  if not found then raise exception 'Exchange not found'; end if;
  if v_ex.exchange_invoice_id is not null then return v_ex.exchange_invoice_id; end if;   -- idempotent
  if v_ex.status is distinct from 'completed' then
    raise exception 'Only a completed exchange can produce an exchange invoice'; end if;

  select * into v_orig from public.invoices where id = v_ex.original_invoice_id;

  select coalesce(sum(line_total),0), count(*) into v_repl_total, v_n
    from public.product_exchange_items where exchange_id = p_exchange_id and direction = 'replacement';

  -- Deduction = everything that is NOT paid top-up:
  --   applied returned credit + any FOC-waived amount. Never negative.
  v_credit_applied := least(coalesce(v_ex.returned_credit_total,0)
                            - coalesce(v_ex.nonrefundable_amount,0), v_repl_total);
  if v_credit_applied < 0 then v_credit_applied := 0; end if;
  v_deduction := v_repl_total - coalesce(v_ex.topup_amount,0);
  if v_deduction < 0 then v_deduction := 0; end if;
  if v_deduction > v_repl_total then v_deduction := v_repl_total; end if;

  v_no := public.next_exchange_invoice_no(v_ex.processing_store_id);

  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, manual_discount, total_amount, paid_amount, notes,
     is_exchange, exchange_id, exchange_credit_total,
     has_foc, is_full_foc, foc_total,
     paid_at, locked_at, created_at)
  values
    (v_no, v_ex.processing_store_id, v_ex.customer_id, v_ex.affiliate_id, v_ex.created_by, 'paid',
     v_repl_total, v_deduction, null, coalesce(v_ex.topup_amount,0), coalesce(v_ex.topup_amount,0),
     'Exchange ' || v_ex.exchange_no || ' of invoice ' || coalesce(v_orig.invoice_no, '?')
       || case when v_ex.reason is not null then ' — ' || v_ex.reason else '' end,
     true, p_exchange_id, v_credit_applied,
     coalesce(v_ex.is_foc,false), (coalesce(v_ex.is_foc,false) and coalesce(v_ex.topup_amount,0) = 0
                                   and v_repl_total > 0 and v_deduction >= v_repl_total),
     coalesce(v_ex.foc_amount,0),
     v_ex.created_at, now(), v_ex.created_at)
  returning id into v_inv_id;

  -- Replacement lines at FULL value; the deduction is allocated across them
  -- as line_discount (last line takes the rounding remainder), which is what
  -- scales affiliate commission down to the top-up share automatically.
  for v_li in
    select * from public.product_exchange_items
     where exchange_id = p_exchange_id and direction = 'replacement'
     order by id
  loop
    v_i := v_i + 1;
    if v_repl_total > 0 then
      if v_i < v_n then
        v_line_disc := round(v_deduction * v_li.line_total / v_repl_total, 2);
        v_running := v_running + v_line_disc;
      else
        v_line_disc := round(v_deduction - v_running, 2);   -- remainder-safe
      end if;
    else
      v_line_disc := 0;
    end if;
    insert into public.invoice_items
      (invoice_id, line_kind, product_id, quantity, unit_price, line_total,
       line_discount, price_source, store_id_snapshot, original_price)
    values
      (v_inv_id, 'product', v_li.product_id, v_li.quantity, v_li.unit_price, v_li.line_total,
       v_line_disc, 'exchange', v_ex.processing_store_id, v_li.unit_price);
  end loop;

  -- Top-up payments appear as invoice payments (locked).
  insert into public.invoice_payments
    (invoice_id, payment_method_id, amount, payment_reference, received_by, created_at, locked_at)
  select v_inv_id, payment_method_id, amount, reference, v_ex.created_by, created_at, now()
    from public.product_exchange_payments where exchange_id = p_exchange_id;

  -- The staff member who processed the exchange is its service staff, so
  -- staff commission (based on total_amount = top-up) lands with them.
  select role into v_creator_role from public.profiles where id = v_ex.created_by;
  if v_creator_role in ('owner','manager','staff') then
    insert into public.invoice_service_staff (invoice_id, staff_id)
    values (v_inv_id, v_ex.created_by) on conflict (invoice_id, staff_id) do nothing;
  end if;

  -- Commissions — both engines see the paid top-up value only:
  --   affiliate: line_total - line_discount = allocated top-up
  --   staff:     invoices.total_amount      = top-up
  perform public.earn_invoice_commission(v_inv_id);
  perform public.earn_staff_commission(v_inv_id);

  update public.product_exchanges set exchange_invoice_id = v_inv_id where id = p_exchange_id;

  perform public.write_audit_ex('invoices', v_inv_id, 'exchange_invoice_created', null,
    jsonb_build_object('invoice_no', v_no, 'exchange_no', v_ex.exchange_no,
                       'original_invoice', v_orig.invoice_no,
                       'gross_replacement', v_repl_total,
                       'exchange_credit', v_credit_applied,
                       'foc_waived', coalesce(v_ex.foc_amount,0),
                       'net_topup', coalesce(v_ex.topup_amount,0)),
    'exchange', v_ex.reason, v_ex.processing_store_id);

  return v_inv_id;
end $$;

-- ---------------------------------------------------------------------
-- A5. Deferred constraint trigger: fires at COMMIT, after the exchange
--     function has written its items and payments. Covers every exchange
--     creation path without rewriting any of them.
-- ---------------------------------------------------------------------
create or replace function public.trg_exchange_invoice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'completed' then
    perform public.create_exchange_invoice(new.id);
  end if;
  return null;
end $$;

drop trigger if exists exchange_creates_invoice on public.product_exchanges;
create constraint trigger exchange_creates_invoice
  after insert on public.product_exchanges
  deferrable initially deferred
  for each row execute function public.trg_exchange_invoice();

-- ---------------------------------------------------------------------
-- A6. One reader for the printed Exchange Invoice: everything the
--     receipt must show, in a single call.
-- ---------------------------------------------------------------------
create or replace function public.exchange_invoice_details(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_ex public.product_exchanges%rowtype;
  v_orig public.invoices%rowtype; v_ret jsonb; v_rep jsonb; v_pay jsonb;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found or not coalesce(v_inv.is_exchange,false) then return jsonb_build_object('found', false); end if;
  select * into v_ex from public.product_exchanges where id = v_inv.exchange_id;
  select * into v_orig from public.invoices where id = v_ex.original_invoice_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'product', p.name, 'quantity', i.quantity,
           'unit_price', i.unit_price, 'line_total', i.line_total) order by i.id), '[]'::jsonb)
    into v_ret
    from public.product_exchange_items i left join public.products p on p.id = i.product_id
   where i.exchange_id = v_ex.id and i.direction = 'returned';

  select coalesce(jsonb_agg(jsonb_build_object(
           'product', p.name, 'quantity', i.quantity,
           'unit_price', i.unit_price, 'line_total', i.line_total) order by i.id), '[]'::jsonb)
    into v_rep
    from public.product_exchange_items i left join public.products p on p.id = i.product_id
   where i.exchange_id = v_ex.id and i.direction = 'replacement';

  select coalesce(jsonb_agg(jsonb_build_object(
           'method', m.name, 'amount', ep.amount, 'reference', ep.reference) order by ep.created_at), '[]'::jsonb)
    into v_pay
    from public.product_exchange_payments ep left join public.payment_methods m on m.id = ep.payment_method_id
   where ep.exchange_id = v_ex.id;

  return jsonb_build_object(
    'found', true,
    'exchange_no', v_ex.exchange_no,
    'original_invoice_no', v_orig.invoice_no,
    'original_invoice_id', v_orig.id,
    'reason', v_ex.reason,
    'returned_items', v_ret,
    'returned_total', coalesce(v_ex.returned_credit_total,0),
    'replacement_items', v_rep,
    'replacement_total', (select coalesce(sum(line_total),0) from public.product_exchange_items
                           where exchange_id = v_ex.id and direction = 'replacement'),
    'exchange_credit_applied', coalesce(v_inv.exchange_credit_total,0),
    'nonrefundable', coalesce(v_ex.nonrefundable_amount,0),
    'foc_waived', coalesce(v_ex.foc_amount,0),
    'net_topup', coalesce(v_ex.topup_amount,0),
    'payments', v_pay,
    'processed_by', (select full_name from public.profiles where id = v_ex.created_by),
    'processing_store', (select name from public.stores where id = v_ex.processing_store_id));
end $$;

-- =====================================================================
-- B. UNPAID INVOICE EDITING
-- =====================================================================

-- ---------------------------------------------------------------------
-- B1. Revision history — a full snapshot (header + lines + selections +
--     service staff) is written before every successful edit.
-- ---------------------------------------------------------------------
create table if not exists public.invoice_revisions (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  revision_no integer not null,
  snapshot jsonb not null,
  edited_by uuid references public.profiles(id),
  edit_reason text,
  edited_at timestamptz not null default now(),
  unique (invoice_id, revision_no)
);
create index if not exists idx_invoice_revisions_inv on public.invoice_revisions(invoice_id, revision_no desc);
alter table public.invoice_revisions enable row level security;
drop policy if exists "read invoice revisions" on public.invoice_revisions;
create policy "read invoice revisions" on public.invoice_revisions for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- B2. Editability check, one source of truth for UI and server alike.
-- ---------------------------------------------------------------------
create or replace function public.can_edit_invoice(p_invoice_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.invoices i
    where i.id = p_invoice_id
      and i.deleted_at is null
      and i.locked_at is null
      and i.status in ('draft','unpaid')
      and coalesce(i.paid_amount,0) = 0
      and coalesce(i.is_topup,false) = false
      and coalesce(i.is_exchange,false) = false
      and not exists (select 1 from public.invoice_payments p where p.invoice_id = i.id)
      and public.user_has_store_access(i.store_id)
  )
$$;

-- ---------------------------------------------------------------------
-- B3. update_invoice — derived line-for-line from Phase 12's
--     create_invoice, so EVERY rule (membership, pricing, stock
--     eligibility, promotion choices, vouchers, therapy, discounts,
--     Member IDs, FOC) is revalidated identically on each edit. The only
--     differences: edit guards + revision snapshot at the top, children
--     replaced and the header UPDATEd (never a new number/store/date),
--     Save Earth re-applied through the canonical refresh, and an
--     invoice_edited audit that records the revision number.
-- ---------------------------------------------------------------------
create or replace function public.update_invoice(
  p_invoice_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null,
  p_discount_voucher_id uuid default null, p_service_staff jsonb default '[]'::jsonb,
  p_edit_reason text default null
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
  -- Phase 13 edit context
  v_store_id uuid; v_old public.invoices%rowtype; v_rev integer; v_snapshot jsonb;
  -- FOC additions
  v_foc_qty integer; v_foc_amt numeric; v_gross numeric;
  v_foc_rid uuid; v_foc_rtext text; v_foc_resolved text; v_foc_total numeric := 0;
begin
  -- ============ PHASE 13 EDIT GUARDS ============
  select * into v_old from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_old.deleted_at is not null then raise exception 'Invoice has been deleted'; end if;
  if coalesce(v_old.is_topup,false) then raise exception 'A refund top-up invoice is system-generated and cannot be edited'; end if;
  if coalesce(v_old.is_exchange,false) then raise exception 'An exchange invoice is system-generated and cannot be edited'; end if;
  if v_old.status not in ('draft','unpaid') then
    raise exception 'Only Draft or Unpaid invoices can be edited (this one is %)', v_old.status; end if;
  if coalesce(v_old.paid_amount,0) > 0 then
    raise exception 'This invoice has payments recorded (S$%.2f) and is locked for editing', v_old.paid_amount; end if;
  if exists (select 1 from public.invoice_payments where invoice_id = p_invoice_id) then
    raise exception 'This invoice has payment records and is locked for editing'; end if;
  if v_old.locked_at is not null then raise exception 'Invoice is locked'; end if;
  v_store_id := v_old.store_id;             -- store is NOT editable
  v_invoice_no := v_old.invoice_no;         -- invoice number is NOT editable

  -- Revision snapshot (rolled back automatically if any validation fails).
  select coalesce(max(revision_no),0) + 1 into v_rev from public.invoice_revisions where invoice_id = p_invoice_id;
  v_snapshot := jsonb_build_object(
    'invoice', to_jsonb(v_old),
    'items', (select coalesce(jsonb_agg(to_jsonb(ii) order by ii.id), '[]'::jsonb)
                from public.invoice_items ii where ii.invoice_id = p_invoice_id),
    'selections', (select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
                     from public.invoice_promotion_selections s
                     join public.invoice_items ii on ii.id = s.invoice_item_id
                    where ii.invoice_id = p_invoice_id),
    'service_staff', (select coalesce(jsonb_agg(staff_id), '[]'::jsonb)
                        from public.invoice_service_staff where invoice_id = p_invoice_id));
  insert into public.invoice_revisions (invoice_id, revision_no, snapshot, edited_by, edit_reason)
  values (p_invoice_id, v_rev, v_snapshot, auth.uid(), p_edit_reason);

  -- Free this invoice's own Member-ID reservation so re-validation is clean.
  perform public.release_member_id_reservations_for_invoice(p_invoice_id);
  -- ============ END EDIT GUARDS ============

  if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(v_store_id) then raise exception 'You do not have access to this store'; end if;
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
      v_mp := public.membership_price_for(v_store_id, v_plan_id);
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
                  where store_id = v_store_id and product_id = (v_opt->>'product_id')::uuid
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

      v_pj := public.promotion_price_for(v_store_id, v_promo_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_promo.name,
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_topup := public.promotion_selections_topup(v_promo_id, v_store_id, v_item->'selections', v_use_member);
      v_gross := ((v_pj->>'price')::numeric * v_qty) + v_topup;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      perform 1 from public.vouchers where id = v_voucher_id and is_active = true and deleted_at is null;
      if not found then raise exception 'Voucher not found or inactive'; end if;
      v_pj := public.voucher_price_for(v_store_id, v_voucher_id, v_use_member);
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
      v_pj := public.therapy_price_for(v_store_id, v_therapy_pkg, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Therapy package "%" is missing its % price at this store',
          (select name from public.unlimited_therapy_packages where id = v_therapy_pkg),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    else
      v_product_id := (v_item->>'product_id')::uuid;
      select p.product_type::text into v_ptype from public.products p where p.id = v_product_id;
      v_pj := public.product_price_for(v_store_id, v_product_id, v_use_member);
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

  -- All validation passed — now replace the invoice's contents in place.
  -- (Store, invoice number, creation date and creator are untouched.)
  delete from public.invoice_promotion_selections s
   using public.invoice_items ii
   where s.invoice_item_id = ii.id and ii.invoice_id = p_invoice_id;
  delete from public.invoice_items where invoice_id = p_invoice_id;
  delete from public.invoice_service_staff where invoice_id = p_invoice_id;

  update public.invoices
     set customer_id = p_customer_id,
         affiliate_id = p_affiliate_id,
         notes = p_notes,
         discount_voucher_id = p_discount_voucher_id,
         subtotal = v_subtotal,
         manual_discount = v_manual,
         discount_total = v_discount,
         total_amount = v_subtotal - v_discount,
         foc_total = v_foc_total,
         has_foc = v_foc_total > 0,
         is_full_foc = (v_foc_total > 0 and v_subtotal <= 0)
   where id = p_invoice_id;
  v_invoice_id := p_invoice_id;

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
      v_mp := public.membership_price_for(v_store_id, v_plan_id);
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
              v_plan_id, 'membership', (v_mp->>'source_id')::uuid, v_store_id,
              v_mp->>'plan_name', (v_mp->>'duration_months')::integer, v_member_id, v_price,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
      if not v_is_renewal and v_member_id is not null then
        perform public.reserve_member_id(v_member_id, p_customer_id, v_invoice_id);
      end if;

    elsif v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      v_pj := public.promotion_price_for(v_store_id, v_promo_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_topup := public.promotion_selections_topup(v_promo_id, v_store_id, v_item->'selections', v_use_member);
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
              (v_pj->>'source_id')::uuid, v_store_id,
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
      v_pj := public.voucher_price_for(v_store_id, v_voucher_id, v_use_member);
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
              (v_pj->>'source_id')::uuid, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);

    elsif v_kind = 'therapy' then
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      v_pj := public.therapy_price_for(v_store_id, v_therapy_pkg, v_use_member);
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
              v_therapy_pkg, v_store_id,
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
      v_pj := public.product_price_for(v_store_id, v_product_id, v_use_member);
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
              (v_pj->>'source_id')::uuid, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
    end if;
  end loop;

  -- Save Earth (columns preserved on the header) re-enters through the
  -- canonical discount refresh, capped at the charged subtotal.
  perform public.refresh_invoice_discount_total(v_invoice_id);
  update public.invoices set discount_total = least(coalesce(discount_total,0), subtotal) where id = v_invoice_id;
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0)) where i.id = v_invoice_id;

  perform public.write_audit_ex('invoices', v_invoice_id, 'invoice_edited',
    jsonb_build_object('subtotal', v_old.subtotal, 'discount_total', v_old.discount_total,
                       'total_amount', v_old.total_amount, 'customer_id', v_old.customer_id,
                       'affiliate_id', v_old.affiliate_id),
    jsonb_build_object('invoice_no', v_invoice_no, 'revision_no', v_rev,
                       'subtotal', v_subtotal, 'discount_total', v_discount,
                       'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo, 'is_member_pricing', v_is_member,
                       'has_membership_line', v_membership_count = 1, 'is_renewal', v_is_renewal,
                       'foc_total', v_foc_total),
    'invoice_edit', p_edit_reason, v_store_id);
  if v_foc_total > 0 then
    perform public.write_audit_ex('invoices', v_invoice_id, 'invoice_foc_created', null,
      jsonb_build_object('invoice_no', v_invoice_no, 'foc_total', v_foc_total,
                         'charged_total', v_subtotal - v_discount),
      'foc', null, v_store_id);
  end if;
  return v_invoice_id;
end; $$;

notify pgrst, 'reload schema';
