-- =====================================================================
-- ENERGIA — PHASE 28 (continued): CREDIT PACKAGES AND PREMIUM BUNDLES
--                                  ARE BUYABLE ON AN INVOICE
--
-- Until now a package or bundle was sold through an orchestration function
-- and never appeared on an invoice. Both are now genuine, non-stock invoice
-- line kinds: the sale creates a real invoice, is paid through the normal
-- payment flow, and the credit, bonus credit and reward vouchers are issued
-- automatically when the invoice becomes fully paid or Completed FOC.
--
-- Design note: rather than rewriting create_invoice (the single most critical
-- function in the system) the new line kinds are created by a dedicated
-- function that builds the invoice and its lines directly, and issuance is
-- hooked into the trigger that already fires when an invoice is paid. The
-- resulting invoice is an ordinary invoice — it prices, pays, reprices,
-- refunds and reports through the existing machinery.
--
-- Additive and idempotent. Run AFTER 80.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Two new non-stock line kinds.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  where t.typname = 'invoice_line_kind' and e.enumlabel = 'credit_package') then
    alter type public.invoice_line_kind rename to invoice_line_kind_pre28;
    create type public.invoice_line_kind as enum
      ('product','voucher','promotion','therapy','credit_package','premium_bundle');
    alter table public.invoice_items alter column line_kind drop default;
    alter table public.invoice_items
      alter column line_kind type public.invoice_line_kind
      using line_kind::text::public.invoice_line_kind;
    alter table public.invoice_items alter column line_kind set default 'product';
    drop type public.invoice_line_kind_pre28;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Line columns and snapshots.
-- ---------------------------------------------------------------------
alter table public.invoice_items add column if not exists credit_package_id uuid references public.credit_packages(id);
alter table public.invoice_items add column if not exists premium_bundle_id uuid references public.premium_bundles(id);
alter table public.invoice_items add column if not exists credit_paid_snapshot numeric(12,2);
alter table public.invoice_items add column if not exists credit_bonus_snapshot numeric(12,2);
alter table public.invoice_items add column if not exists credit_voucher_qty_snapshot integer;
alter table public.invoice_items add column if not exists bundle_voucher_selection jsonb;
-- Set once the benefit has been granted, so a re-paid or edited invoice can
-- never issue the same credit twice.
alter table public.invoice_items add column if not exists credit_issued_at timestamptz;

-- A payment method can be marked as wallet credit so it can be refused.
alter table public.payment_methods add column if not exists is_wallet_credit boolean not null default false;

-- ---------------------------------------------------------------------
-- 3. Creating the sale invoice.
--    p_lines: [{kind:'credit_package'|'premium_bundle', id:uuid,
--               voucher_selection:[{voucher_id,quantity}],   -- bundles
--               foc_amount:numeric}]
-- ---------------------------------------------------------------------
create or replace function public.create_credit_purchase_invoice(
  p_store_id uuid, p_customer_id uuid, p_lines jsonb,
  p_affiliate_id uuid default null, p_discount_total numeric default 0,
  p_notes text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare
  v_invoice uuid; v_no text; v_line jsonb; v_kind text; v_id uuid;
  pk public.credit_packages%rowtype; b public.premium_bundles%rowtype;
  v_price numeric; v_foc numeric; v_line_total numeric;
  v_subtotal numeric := 0; v_foc_total numeric := 0; v_check jsonb;
  v_sel jsonb; v_n integer := 0;
begin
  if p_customer_id is null then
    raise exception 'A customer is required to buy credit'; end if;
  if not public.user_has_store_access(p_store_id) then
    raise exception 'No access to this store'; end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one credit package or premium bundle'; end if;

  v_no := public.next_invoice_no();
  insert into public.invoices (invoice_no, store_id, customer_id, affiliate_id, created_by,
    status, subtotal, discount_total, total_amount, paid_amount, notes)
  values (v_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(),
    'unpaid', 0, coalesce(p_discount_total,0), 0, 0, p_notes)
  returning id into v_invoice;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_kind := coalesce(v_line->>'kind','');
    v_id := (v_line->>'id')::uuid;
    v_foc := round(coalesce((v_line->>'foc_amount')::numeric, 0), 2);

    if v_kind = 'credit_package' then
      select * into pk from public.credit_packages where id = v_id and deleted_at is null;
      if not found then raise exception 'Credit package not found'; end if;
      if not exists (select 1 from public.credit_packages_for_store(p_store_id) x where x.id = v_id) then
        raise exception 'Credit package "%" is not available at this store', pk.name; end if;
      v_price := pk.customer_price;
      if v_foc > v_price then raise exception 'The FOC amount cannot exceed the package price'; end if;
      v_line_total := round(v_price - v_foc, 2);

      insert into public.invoice_items
        (invoice_id, line_kind, quantity, unit_price, line_total, price_source, price_source_id,
         store_id_snapshot, original_price, credit_package_id,
         credit_paid_snapshot, credit_voucher_qty_snapshot,
         plan_name_snapshot, foc_quantity, is_foc, foc_amount)
      values (v_invoice, 'credit_package', 1, v_price, v_line_total, 'credit_package', v_id,
        p_store_id, v_price, v_id, pk.paid_credit_amount, null,
        pk.name, case when v_foc > 0 then 1 else 0 end, v_foc >= v_price, v_foc);

    elsif v_kind = 'premium_bundle' then
      select * into b from public.premium_bundles where id = v_id and deleted_at is null;
      if not found then raise exception 'Premium bundle not found'; end if;
      if not exists (select 1 from public.premium_bundles_for_store(p_store_id) x where x.id = v_id) then
        raise exception 'Premium bundle "%" is not available at this store', b.name; end if;

      -- The voucher mixture is chosen before payment and validated now.
      v_sel := coalesce(v_line->'voucher_selection', '[]'::jsonb);
      v_check := public.validate_bundle_voucher_selection(v_id, p_store_id, v_sel);
      if not (v_check->>'complete')::boolean then
        raise exception 'Select exactly % voucher(s) for "%" — % chosen',
          v_check->>'required_qty', b.name, v_check->>'selected_qty'; end if;
      if not (v_check->>'stock_ok')::boolean then
        raise exception 'Not enough voucher stock for "%": %', b.name,
          array_to_string(array(select jsonb_array_elements_text(v_check->'shortages')), '; '); end if;

      v_price := b.customer_payment_amount;
      if v_foc > v_price then raise exception 'The FOC amount cannot exceed the bundle price'; end if;
      v_line_total := round(v_price - v_foc, 2);

      insert into public.invoice_items
        (invoice_id, line_kind, quantity, unit_price, line_total, price_source, price_source_id,
         store_id_snapshot, original_price, premium_bundle_id,
         credit_paid_snapshot, credit_bonus_snapshot, credit_voucher_qty_snapshot,
         bundle_voucher_selection, plan_name_snapshot,
         foc_quantity, is_foc, foc_amount)
      values (v_invoice, 'premium_bundle', 1, v_price, v_line_total, 'premium_bundle', v_id,
        p_store_id, v_price, v_id, b.paid_credit_amount, b.bonus_credit_amount,
        b.free_voucher_qty, v_sel, b.name,
        case when v_foc > 0 then 1 else 0 end, v_foc >= v_price, v_foc);
    else
      raise exception 'Only credit packages and premium bundles can be added here, not "%"', v_kind;
    end if;

    v_subtotal := v_subtotal + v_line_total;
    v_foc_total := v_foc_total + v_foc;
    v_n := v_n + 1;
  end loop;

  update public.invoices
     set subtotal = v_subtotal,
         discount_total = least(coalesce(p_discount_total,0), v_subtotal),
         total_amount = greatest(v_subtotal - least(coalesce(p_discount_total,0), v_subtotal), 0),
         foc_total = v_foc_total, has_foc = v_foc_total > 0,
         is_full_foc = (v_subtotal = 0 and v_foc_total > 0)
   where id = v_invoice;

  perform public.write_audit_ex('invoices', v_invoice, 'credit_purchase_invoice_created', null,
    jsonb_build_object('invoice_no', v_no, 'lines', v_n, 'subtotal', v_subtotal),
    'credit', null, p_store_id);
  return v_invoice;
end $function$;

-- ---------------------------------------------------------------------
-- 4. Wallet credit can never pay for a credit package or premium bundle.
-- ---------------------------------------------------------------------
create or replace function public.trg_block_wallet_credit_on_credit_lines()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if exists (select 1 from public.payment_methods m
              where m.id = new.payment_method_id and coalesce(m.is_wallet_credit,false))
     and exists (select 1 from public.invoice_items ii
                  where ii.invoice_id = new.invoice_id
                    and ii.line_kind in ('credit_package','premium_bundle')) then
    raise exception 'A credit package or premium bundle cannot be paid for with wallet credit';
  end if;
  return new;
end $function$;

drop trigger if exists block_wallet_credit_on_credit_lines on public.invoice_payments;
create trigger block_wallet_credit_on_credit_lines before insert on public.invoice_payments
  for each row execute function public.trg_block_wallet_credit_on_credit_lines();

-- ---------------------------------------------------------------------
-- 5. Issue the benefit when the invoice is fully paid (or Completed FOC).
--    Idempotent: a line is only ever issued once.
-- ---------------------------------------------------------------------
create or replace function public.issue_credit_lines_for_invoice(p_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_it record; v_res jsonb;
  v_out jsonb := '[]'::jsonb; v_external numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('skipped', true); end if;
  if v_inv.status not in ('paid','completed_foc') then
    return jsonb_build_object('skipped', true, 'reason', 'invoice not settled'); end if;

  for v_it in
    select * from public.invoice_items
     where invoice_id = p_invoice_id
       and line_kind in ('credit_package','premium_bundle')
       and credit_issued_at is null
     order by id
     for update
  loop
    -- The external money attributable to this line is its charged value less
    -- its share of any invoice discount. FOC value is already excluded from
    -- line_total, so it never reaches commission.
    v_external := round(coalesce(v_it.line_total,0)
      - case when coalesce(v_inv.subtotal,0) > 0
             then coalesce(v_inv.discount_total,0) * (coalesce(v_it.line_total,0) / v_inv.subtotal)
             else 0 end, 2);
    if v_external < 0 then v_external := 0; end if;

    if v_it.line_kind = 'credit_package' then
      v_res := public.issue_credit_package(v_it.credit_package_id, v_inv.customer_id,
                                           v_inv.store_id, v_external, p_invoice_id);
      -- Commission on the external money only.
      v_res := v_res || jsonb_build_object('commission',
        public.earn_credit_package_commission((v_res->>'sale_id')::uuid));
    else
      v_res := public.sell_premium_bundle(
        v_it.premium_bundle_id, v_inv.customer_id, v_inv.store_id,
        -- The money is already recorded on the invoice, so the payment list is
        -- represented by the line's external value.
        jsonb_build_array(jsonb_build_object('method','invoice','amount', v_external)),
        coalesce(v_it.bundle_voucher_selection, '[]'::jsonb),
        0, coalesce(v_it.foc_amount,0), p_invoice_id,
        coalesce(v_it.foc_amount,0) >= coalesce(v_it.unit_price,0));
    end if;

    update public.invoice_items set credit_issued_at = now() where id = v_it.id;
    v_out := v_out || jsonb_build_object('line_kind', v_it.line_kind,
      'external', v_external, 'result', v_res);
  end loop;

  return jsonb_build_object('issued', v_out);
end $function$;

-- Hook into the trigger that already runs when an invoice is settled.
create or replace function public.trg_create_therapy_on_paid()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_day date;
begin
  if new.status in ('paid','completed_foc') and old.status is distinct from new.status then
    if exists (select 1 from public.invoice_items where invoice_id = new.id and line_kind = 'therapy') then
      perform public.create_purchased_therapy_for_invoice(new.id);
    end if;
    -- Credit packages and premium bundles grant their benefit here.
    if exists (select 1 from public.invoice_items
                where invoice_id = new.id
                  and line_kind in ('credit_package','premium_bundle')) then
      perform public.issue_credit_lines_for_invoice(new.id);
    end if;
  end if;

  if (new.status is distinct from old.status)
     or (coalesce(new.paid_amount,0) is distinct from coalesce(old.paid_amount,0)) then
    v_day := (coalesce(new.paid_at, now()) at time zone 'Asia/Singapore')::date;

    if new.status in ('paid','partially_paid') and coalesce(new.paid_amount,0) > 0
       and new.affiliate_active_on_paid is null then
      perform public.snapshot_invoice_affiliate(new.id);
    end if;

    if new.customer_id is not null and new.store_id is not null then
      perform public.recompute_legacy_qualification(new.customer_id, new.store_id, v_day);
      perform public.recompute_affiliates_for_customer_day(new.customer_id, v_day);
    end if;
  end if;

  return null;
end $function$;

-- ---------------------------------------------------------------------
-- 6. A credit line never earns ordinary line commission — the package and
--    bundle functions book their own, on external money only.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'earn_invoice_commission';
  if v_def is null then
    raise exception 'earn_invoice_commission is missing';
  end if;
  if position('credit_package' in v_def) = 0 then
    v_def := replace(v_def,
      '    where ii.invoice_id = p_invoice_id' || chr(10) || '  loop',
      '    where ii.invoice_id = p_invoice_id' || chr(10) ||
      '      and ii.line_kind not in (''credit_package'',''premium_bundle'')' || chr(10) || '  loop');
    if position('credit_package' in v_def) = 0 then
      raise exception 'could not exclude credit lines from earn_invoice_commission — check its item loop';
    end if;
    execute v_def;
  end if;
end $patch$;

-- ---------------------------------------------------------------------
-- 7. A credit line is non-stock and must not be repriced from a price list.
--    reprice_invoice_lines already limits itself to product/voucher/promotion,
--    so the new kinds are skipped; this only documents and asserts it.
-- ---------------------------------------------------------------------
do $$
begin
  if position('line_kind in (''product'',''voucher'',''promotion'')' in
      (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname='public' and p.proname='reprice_invoice_lines')) = 0 then
    raise warning 'reprice_invoice_lines no longer restricts itself to product/voucher/promotion — check that credit lines are still skipped';
  end if;
end $$;

notify pgrst, 'reload schema';
