-- =====================================================================
-- ENERGIA — SPECIAL PRODUCTS AND RENTALS SOLD FROM THE INVOICES PAGE
--
-- Both become ordinary invoice lines, so a customer buying a corset, a special
-- product and a rental gets ONE invoice and ONE receipt instead of three
-- documents from two screens.
--
-- The flow, as specified:
--
--   1. ANYONE (staff, manager, owner) raises the invoice at a store and takes
--      payment. The customer pays there and then.
--   2. NO STOCK MOVES at that point. The sale or rental is recorded
--      'awaiting_fulfilment' with no warehouse: the goods are not reserved and
--      no warehouse is guessed at.
--   3. An OWNER or MANAGER later names the warehouse. Only then is stock
--      checked and deducted.
--
-- Waiting rather than deducting from a default was chosen deliberately: a
-- guessed warehouse would silently make one warehouse's count wrong and have to
-- be unpicked later.
--
-- Creating sales and rentals from the Special & Rentals page is retired; that
-- page keeps fulfilment, returns, late fees and cancellation.
--
-- Additive and idempotent. Run AFTER 105.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Line kinds, and the pending state.
-- ---------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid
                  where t.typname='invoice_line_kind' and e.enumlabel='special_product') then
    alter type public.invoice_line_kind add value 'special_product';
  end if;
end $$;
do $$ begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid
                  where t.typname='invoice_line_kind' and e.enumlabel='rental') then
    alter type public.invoice_line_kind add value 'rental';
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid
                  where t.typname='rental_status' and e.enumlabel='awaiting_fulfilment') then
    alter type public.rental_status add value 'awaiting_fulfilment' before 'draft';
  end if;
exception when undefined_object then
  raise notice 'rental status is not an enum here — using the existing values';
end $$;

-- The warehouse is unknown until an Owner or Manager assigns it.
alter table public.special_sales alter column warehouse_id drop not null;
alter table public.rentals       alter column warehouse_id drop not null;

-- Which invoice line each came from, so one cannot be settled twice.
alter table public.special_sales add column if not exists invoice_id uuid references public.invoices(id);
alter table public.special_sales add column if not exists invoice_item_id uuid;
alter table public.special_sales add column if not exists store_id uuid references public.stores(id);
alter table public.special_sales add column if not exists fulfilled_at timestamptz;
alter table public.special_sales add column if not exists fulfilled_by uuid references public.profiles(id);

alter table public.rentals add column if not exists invoice_id uuid references public.invoices(id);
alter table public.rentals add column if not exists invoice_item_id uuid;
alter table public.rentals add column if not exists store_id uuid references public.stores(id);
alter table public.rentals add column if not exists fulfilled_at timestamptz;
alter table public.rentals add column if not exists fulfilled_by uuid references public.profiles(id);

create index if not exists idx_special_sales_invoice on public.special_sales (invoice_id);
create index if not exists idx_rentals_invoice on public.rentals (invoice_id);

-- Invoice lines carry the special product and, for a rental, its terms.
alter table public.invoice_items add column if not exists special_product_id uuid references public.special_products(id);
alter table public.invoice_items add column if not exists rental_rate_type public.special_rate_type;
alter table public.invoice_items add column if not exists rental_periods integer;
alter table public.invoice_items add column if not exists rental_start_date date;
alter table public.invoice_items add column if not exists rental_return_date date;

-- ---------------------------------------------------------------------
-- 2. Pricing a line.
-- ---------------------------------------------------------------------
create or replace function public.special_line_price(
  p_special_product_id uuid, p_kind text,
  p_rate_type public.special_rate_type default null, p_periods integer default 1)
returns numeric language plpgsql stable security definer set search_path to 'public' as $function$
declare sp public.special_products%rowtype; v_rate numeric;
begin
  select * into sp from public.special_products
   where id = p_special_product_id and deleted_at is null;
  if not found then raise exception 'Special product not found'; end if;

  if p_kind = 'special_product' then
    if coalesce(sp.sale_price,0) <= 0 then
      raise exception '"%" has no sale price set', sp.name; end if;
    return round(sp.sale_price, 2);
  end if;

  v_rate := case p_rate_type
    when 'day' then sp.rate_day when 'week' then sp.rate_week
    when 'month' then sp.rate_month when 'year' then sp.rate_year end;
  if coalesce(v_rate,0) <= 0 then
    raise exception '"%" has no % rate set', sp.name, coalesce(p_rate_type::text,'rental'); end if;
  if coalesce(p_periods,0) <= 0 then raise exception 'The rental period must be at least 1'; end if;
  return round(v_rate * p_periods, 2);
end $function$;

-- ---------------------------------------------------------------------
-- 3. On settlement, raise the sale or rental — awaiting fulfilment.
--    No warehouse, no stock movement.
-- ---------------------------------------------------------------------
create or replace function public.create_special_docs_for_invoice(p_invoice_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_inv public.invoices%rowtype; v_it record; v_n integer := 0; v_i integer;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return 0; end if;

  for v_it in
    select ii.* from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and ii.line_kind::text in ('special_product','rental')
       and ii.special_product_id is not null
  loop
    -- Already raised for this line: never duplicate on a re-run or a correction.
    if exists (select 1 from public.special_sales where invoice_item_id = v_it.id)
       or exists (select 1 from public.rentals where invoice_item_id = v_it.id) then
      continue;
    end if;

    if v_it.line_kind::text = 'special_product' then
      -- One row per unit keeps the existing per-unit return and cancel flows.
      for v_i in 1 .. greatest(coalesce(v_it.quantity,1), 1) loop
        insert into public.special_sales
          (sale_no, special_product_id, warehouse_id, customer_id, store_id, quantity,
           unit_price, total_amount, payment_method_id, notes, status, sold_by,
           invoice_id, invoice_item_id)
        values ('SPS-' || to_char(now(),'YYYY') || '-'
           || lpad(nextval('public.special_sale_no_seq')::text, 4, '0'),
           v_it.special_product_id, null,
           v_inv.customer_id, v_inv.store_id, 1,
           round(coalesce(v_it.unit_price,0), 2), round(coalesce(v_it.unit_price,0), 2),
           null, 'From invoice ' || v_inv.invoice_no, 'pending', auth.uid(),
           p_invoice_id, v_it.id);
        v_n := v_n + 1;
      end loop;
    else
      insert into public.rentals
        (rental_no, special_product_id, warehouse_id, customer_id, store_id, quantity,
         rate_type, rate_amount, periods, rental_fee, start_date, expected_return_date,
         status, notes, created_by, invoice_id, invoice_item_id,
         late_fee_per_day, paid_at)
      select 'RNT-' || to_char(now(),'YYYY') || '-'
           || lpad(nextval('public.rental_no_seq')::text, 4, '0'),
         v_it.special_product_id, null,
         v_inv.customer_id, v_inv.store_id, greatest(coalesce(v_it.quantity,1),1),
         coalesce(v_it.rental_rate_type,'day'),
         round(coalesce(v_it.line_total,0) / greatest(coalesce(v_it.rental_periods,1),1), 2),
         greatest(coalesce(v_it.rental_periods,1),1), round(coalesce(v_it.line_total,0),2),
         coalesce(v_it.rental_start_date, public.sg_today()),
         coalesce(v_it.rental_return_date, public.sg_today() + greatest(coalesce(v_it.rental_periods,1),1)),
         'awaiting_fulfilment', 'From invoice ' || v_inv.invoice_no, auth.uid(),
         p_invoice_id, v_it.id, sp.late_fee_per_day, v_inv.paid_at
        from public.special_products sp where sp.id = v_it.special_product_id;
      v_n := v_n + 1;
    end if;
  end loop;

  if v_n > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'special_docs_awaiting_fulfilment', null,
      jsonb_build_object('count', v_n, 'invoice_no', v_inv.invoice_no),
      'special', null, v_inv.store_id);
  end if;
  return v_n;
end $function$;

-- ---------------------------------------------------------------------
-- 4. An Owner or Manager names the warehouse. Stock moves here, and only here.
-- ---------------------------------------------------------------------
create or replace function public.fulfil_special_doc(
  p_doc_kind text, p_doc_id uuid, p_warehouse_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_prod uuid; v_qty integer; v_have integer; v_name text; v_no text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can choose the warehouse'; end if;
  if p_warehouse_id is null then raise exception 'Choose a warehouse'; end if;
  if not exists (select 1 from public.warehouses where id = p_warehouse_id and deleted_at is null) then
    raise exception 'That warehouse does not exist'; end if;

  if p_doc_kind = 'special_sale' then
    select special_product_id, quantity, sale_no into v_prod, v_qty, v_no
      from public.special_sales where id = p_doc_id and warehouse_id is null
        and status not in ('cancelled') for update;
    if v_prod is null then raise exception 'That sale is not awaiting a warehouse'; end if;
  elsif p_doc_kind = 'rental' then
    select special_product_id, quantity, rental_no into v_prod, v_qty, v_no
      from public.rentals where id = p_doc_id and warehouse_id is null
        and status not in ('cancelled') for update;
    if v_prod is null then raise exception 'That rental is not awaiting a warehouse'; end if;
  else
    raise exception 'Unknown document kind "%"', p_doc_kind;
  end if;

  select name into v_name from public.special_products where id = v_prod;

  select coalesce(current_qty,0) into v_have from public.special_product_stock
   where warehouse_id = p_warehouse_id and special_product_id = v_prod for update;
  if coalesce(v_have,0) < v_qty then
    raise exception 'Not enough "%" at that warehouse: % needed, % available',
      v_name, v_qty, coalesce(v_have,0);
  end if;

  update public.special_product_stock
     set current_qty = current_qty - v_qty, updated_at = now()
   where warehouse_id = p_warehouse_id and special_product_id = v_prod;

  if p_doc_kind = 'special_sale' then
    update public.special_sales
       set warehouse_id = p_warehouse_id, status = 'completed',
           fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;
  else
    update public.rentals
       set warehouse_id = p_warehouse_id, status = 'active',
           activated_at = now(), fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;
  end if;

  perform public.write_audit_ex(p_doc_kind, p_doc_id, 'special_doc_fulfilled', null,
    jsonb_build_object('warehouse', p_warehouse_id, 'product', v_name,
      'quantity', v_qty, 'doc_no', v_no), 'special', null, null);

  return jsonb_build_object('success', true, 'doc_no', v_no,
    'warehouse_id', p_warehouse_id, 'quantity', v_qty);
end $function$;

-- Everything waiting on a warehouse, with where the stock actually is.
create or replace function public.special_docs_awaiting_fulfilment()
returns table(doc_kind text, doc_id uuid, doc_no text, invoice_no text,
              product_name text, customer_name text, store_name text,
              quantity integer, created_at timestamptz)
language sql stable security definer set search_path to 'public' as $function$
  select 'special_sale', s.id, s.sale_no, i.invoice_no, sp.name, c.full_name, st.name,
         s.quantity, s.created_at
    from public.special_sales s
    join public.special_products sp on sp.id = s.special_product_id
    left join public.invoices i on i.id = s.invoice_id
    left join public.customers c on c.id = s.customer_id
    left join public.stores st on st.id = s.store_id
   where s.warehouse_id is null and s.status <> 'cancelled'
  union all
  select 'rental', r.id, r.rental_no, i.invoice_no, sp.name, c.full_name, st.name,
         r.quantity, r.created_at
    from public.rentals r
    join public.special_products sp on sp.id = r.special_product_id
    left join public.invoices i on i.id = r.invoice_id
    left join public.customers c on c.id = r.customer_id
    left join public.stores st on st.id = r.store_id
   where r.warehouse_id is null and r.status <> 'cancelled'
  order by 9
$function$;

notify pgrst, 'reload schema';
-- ---------------------------------------------------------------------
-- 5. Teach create_invoice / update_invoice the two new line kinds.
--
--    Both functions loop TWICE over the items: once to price and validate,
--    once to insert. The `else` branch is textually identical in both, so a
--    plain replace() would patch both with the same code and the insert loop
--    would price a line it never inserted. The definition is therefore split at
--    the second loop and each half patched with what it actually needs.
-- ---------------------------------------------------------------------
do $patch$
declare
  v_name text; v_def text; v_head text; v_tail text; v_new text;
  v_split integer; v_marker text; v_else text;
begin
  v_else := '    else' || chr(10) || '      v_product_id := (v_item->>''product_id'')::uuid;';
  v_marker := 'v_kind := coalesce(v_item->>''kind'',''product'');';

  foreach v_name in array array['create_invoice','update_invoice'] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_name;
    if v_def is null then raise notice '% not found', v_name; continue; end if;
    if position('special_line_price' in v_def) > 0 then
      raise notice '% already handles special products and rentals', v_name; continue;
    end if;

    -- Split at the SECOND occurrence of the loop marker: the insert loop.
    v_split := position(v_marker in substr(v_def, position(v_marker in v_def) + length(v_marker)))
               + position(v_marker in v_def) + length(v_marker) - 1;
    v_head := substr(v_def, 1, v_split - 1);
    v_tail := substr(v_def, v_split);

    -- Pricing loop: work out the amount.
    v_head := replace(v_head, v_else,
      '    elsif v_kind in (''special_product'',''rental'') then' || chr(10)
      || '      v_gross := public.special_line_price(' || chr(10)
      || '        (v_item->>''special_product_id'')::uuid, v_kind,' || chr(10)
      || '        nullif(v_item->>''rental_rate_type'', '''')::public.special_rate_type,' || chr(10)
      || '        coalesce((v_item->>''rental_periods'')::integer, 1)) * v_qty;' || chr(10)
      || chr(10) || v_else);

    -- Insert loop: write the line, carrying the special-product details.
    v_tail := replace(v_tail, v_else,
      '    elsif v_kind in (''special_product'',''rental'') then' || chr(10)
      || '      v_price := round(public.special_line_price(' || chr(10)
      || '        (v_item->>''special_product_id'')::uuid, v_kind,' || chr(10)
      || '        nullif(v_item->>''rental_rate_type'', '''')::public.special_rate_type,' || chr(10)
      || '        coalesce((v_item->>''rental_periods'')::integer, 1)), 2);' || chr(10)
      || '      v_line_total := round(v_price * v_qty, 2);' || chr(10)
      || '      insert into public.invoice_items' || chr(10)
      || '        (invoice_id, line_kind, product_id, quantity, unit_price, line_total,' || chr(10)
      || '         store_id_snapshot, original_price, special_product_id,' || chr(10)
      || '         rental_rate_type, rental_periods, rental_start_date, rental_return_date)' || chr(10)
      || '      values (v_invoice_id, v_kind::public.invoice_line_kind, null, v_qty, v_price, v_line_total,' || chr(10)
      || '         ' || case when v_name = 'create_invoice' then 'p_store_id' else 'v_old.store_id' end || ', v_price,' || chr(10)
      || '         (v_item->>''special_product_id'')::uuid,' || chr(10)
      || '         nullif(v_item->>''rental_rate_type'', '''')::public.special_rate_type,' || chr(10)
      || '         coalesce((v_item->>''rental_periods'')::integer, 1),' || chr(10)
      || '         nullif(v_item->>''rental_start_date'', '''')::date,' || chr(10)
      || '         nullif(v_item->>''rental_return_date'', '''')::date);' || chr(10)
      || chr(10) || v_else);

    v_new := v_head || v_tail;

    -- Not products, so the third-party and per-line voucher rules skip them.
    v_new := replace(v_new,
      'if v_kind not in (''promotion'',''voucher'',''therapy'') then',
      'if v_kind not in (''promotion'',''voucher'',''therapy'',''special_product'',''rental'') then');

    if position('special_line_price' in v_new) = 0 then
      raise exception 'Could not add the new line kinds to %', v_name;
    end if;
    execute v_new;
    raise notice '% now prices and records special products and rentals', v_name;
  end loop;
end $patch$;

-- ---------------------------------------------------------------------
-- 6. Settlement raises the pending documents.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'pay_invoice';
  if v_def is null then raise exception 'pay_invoice not found'; end if;
  if position('create_special_docs_for_invoice' in v_def) > 0 then
    raise notice 'pay_invoice already raises the special documents'; return;
  end if;

  v_new := replace(v_def,
    '  perform public.earn_staff_commission(p_invoice_id);',
    '  perform public.earn_staff_commission(p_invoice_id);' || chr(10)
    || '  -- Special products and rentals become documents awaiting a warehouse.' || chr(10)
    || '  perform public.create_special_docs_for_invoice(p_invoice_id);');

  if position('create_special_docs_for_invoice' in v_new) = 0 then
    raise exception 'Could not hook the special documents into pay_invoice';
  end if;
  execute v_new;
  raise notice 'pay_invoice now raises special products and rentals awaiting fulfilment';
end $patch$;

notify pgrst, 'reload schema';
