-- =====================================================================
-- ENERGIA — SELLING AN INDIVIDUAL THERAPY SESSION
--
-- An invoice can already sell an unlimited-therapy PACKAGE: a therapy line
-- naming a package, quantity fixed at one, priced in months. It cannot sell one
-- session of Power Recharge.
--
-- 242 added invoice_items.therapy_service_id as the discriminator between the
-- two — they have opposite credit eligibility, so the difference had to be
-- recorded rather than guessed from a name. This migration builds the path that
-- actually sets it: pricing, validation, the line, and the record of what the
-- customer bought.
--
-- HOW create_invoice IS CHANGED. Not by restating it. That function is large,
-- shared, and being worked on elsewhere; a rewritten copy would silently revert
-- whatever else has landed in it. Instead its installed definition is read back
-- with pg_get_functiondef and a session branch is inserted AHEAD of the existing
-- package branch, which is left exactly as it is. If the anchors are not found
-- the migration stops rather than guessing — see the notices it raises.
--
-- What this deliberately does not do: it redeems nothing and books nothing. A
-- purchased session is recorded as purchased and unused. Consuming one needs an
-- appointment or an attendance record, neither of which exists, and inventing a
-- redemption action here would be inventing the thing that proves a customer
-- turned up.
--
-- Requires 240 and 242. Additive.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. What the line remembers.
--
-- The same reason every other line kind snapshots its price: the catalogue
-- moves, and an invoice from March must still read the way it read in March.
-- ---------------------------------------------------------------------
alter table public.invoice_items
  add column if not exists therapy_service_name_snapshot text,
  add column if not exists therapy_service_minutes_snapshot integer;

-- A therapy line is one thing or the other, never both.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'invoice_item_therapy_is_one_kind') then
    alter table public.invoice_items add constraint invoice_item_therapy_is_one_kind
      check (therapy_package_id is null or therapy_service_id is null) not valid;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. What the customer ends up holding.
-- ---------------------------------------------------------------------
create table if not exists public.customer_therapy_sessions (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  service_id uuid not null references public.therapy_services(id),
  store_id uuid references public.stores(id),
  invoice_id uuid references public.invoices(id) on delete set null,
  invoice_item_id uuid unique references public.invoice_items(id) on delete set null,

  -- Frozen at purchase, for the same reason the invoice line freezes them.
  service_name_snapshot text not null,
  service_minutes_snapshot integer,
  unit_price_snapshot numeric(12,2) not null default 0,

  quantity_purchased integer not null check (quantity_purchased > 0),
  -- Nothing increments this. No redemption action exists, deliberately; the
  -- column is here so the balance below is already shaped for one.
  quantity_used integer not null default 0 check (quantity_used >= 0),

  status text not null default 'available'
    check (status in ('available','used','cancelled','refunded')),

  purchased_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  notes text,

  constraint customer_therapy_session_used_within_purchased
    check (quantity_used <= quantity_purchased)
);
create index if not exists idx_cts_customer on public.customer_therapy_sessions (customer_id);
create index if not exists idx_cts_service on public.customer_therapy_sessions (service_id);
create index if not exists idx_cts_invoice on public.customer_therapy_sessions (invoice_id);

-- ---------------------------------------------------------------------
-- 3. Fulfilment on payment.
--
-- A separate trigger from the package one, which stays untouched. It cannot
-- collide with it either: create_purchased_therapy_for_invoice() reads only
-- lines with a therapy_package_id, and a session line has none.
-- ---------------------------------------------------------------------
create or replace function public.create_therapy_sessions_for_invoice(p_invoice_id uuid)
returns integer language plpgsql security definer set search_path = public as $function$
declare v_inv public.invoices%rowtype; v_it record; v_n integer := 0;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found or v_inv.customer_id is null then return 0; end if;

  for v_it in
    select ii.* from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and ii.line_kind::text = 'therapy'
       and ii.therapy_service_id is not null
     order by ii.id
  loop
    -- Idempotent: paying an invoice twice, or a replayed trigger, must not
    -- hand the customer a second set of sessions.
    if exists (select 1 from public.customer_therapy_sessions
                where invoice_item_id = v_it.id) then continue; end if;

    insert into public.customer_therapy_sessions (
      customer_id, service_id, store_id, invoice_id, invoice_item_id,
      service_name_snapshot, service_minutes_snapshot, unit_price_snapshot,
      quantity_purchased, purchased_at)
    values (v_inv.customer_id, v_it.therapy_service_id, v_inv.store_id, p_invoice_id, v_it.id,
      coalesce(v_it.therapy_service_name_snapshot,
               (select s.name from public.therapy_services s where s.id = v_it.therapy_service_id),
               'Therapy session'),
      coalesce(v_it.therapy_service_minutes_snapshot,
               (select s.duration_minutes from public.therapy_services s where s.id = v_it.therapy_service_id)),
      coalesce(v_it.unit_price, 0), greatest(coalesce(v_it.quantity, 1), 1),
      coalesce(v_inv.paid_at, now()));
    v_n := v_n + 1;
  end loop;

  if v_n > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'therapy_sessions_created', null,
      jsonb_build_object('created', v_n), 'therapy', null, v_inv.store_id);
  end if;
  return v_n;
end $function$;

create or replace function public.trg_create_therapy_sessions_on_paid()
returns trigger language plpgsql security definer set search_path = public as $function$
begin
  if new.status::text = 'paid' and old.status::text is distinct from 'paid' then
    perform public.create_therapy_sessions_for_invoice(new.id);
  end if;
  -- Cancelling or refunding an invoice takes back what has not been used. Used
  -- sessions are left alone: something already given cannot be un-given here,
  -- and the refund ledger is where that belongs.
  if new.status::text in ('cancelled','refunded')
     and old.status::text is distinct from new.status::text then
    update public.customer_therapy_sessions
       set status = case when new.status::text = 'cancelled' then 'cancelled' else 'refunded' end,
           notes = concat_ws(E'\n', notes, 'Invoice ' || new.status::text)
     where invoice_id = new.id and status = 'available' and quantity_used = 0;
  end if;
  return null;
end $function$;

drop trigger if exists create_therapy_sessions_on_paid on public.invoices;
create trigger create_therapy_sessions_on_paid
  after update on public.invoices
  for each row execute function public.trg_create_therapy_sessions_on_paid();

-- ---------------------------------------------------------------------
-- 4. The session branch inside create_invoice.
--
-- Inserted ahead of the package branch in both loops, so a therapy line that
-- names a service takes the new path and every other therapy line behaves
-- exactly as before. The package branch text is reproduced in the anchors only
-- so the replacement can be positioned; it is not modified.
-- ---------------------------------------------------------------------
do $$
declare
  r record;
  f text;
  v_check_anchor text;
  v_insert_anchor text;
  v_check_branch text;
  v_insert_branch text;
  v_patched integer := 0;
  v_already integer := 0;
  v_skipped integer := 0;
begin
  v_check_anchor :=
    'elsif v_kind = ''therapy'' then' || chr(10) ||
    '      if v_qty <> 1 then raise exception ''A therapy line must have quantity 1''; end if;';

  v_insert_anchor :=
    'elsif v_kind = ''therapy'' then' || chr(10) ||
    '      v_therapy_pkg := (v_item->>''therapy_package_id'')::uuid;' || chr(10) ||
    '      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);';

  -- A session line: several may be bought at once, it is priced per session
  -- from the service catalogue, and it must be offered at this store.
  v_check_branch :=
    'elsif v_kind = ''therapy'' and nullif(v_item->>''therapy_service_id'', '''') is not null then' || chr(10) ||
    '      if v_qty < 1 then raise exception ''A therapy session line needs a quantity of at least 1''; end if;' || chr(10) ||
    '      if not public.therapy_service_available_at((v_item->>''therapy_service_id'')::uuid, p_store_id) then' || chr(10) ||
    '        raise exception ''"%" is not offered at this store'',' || chr(10) ||
    '          coalesce((select s.name from public.therapy_services s' || chr(10) ||
    '                     where s.id = (v_item->>''therapy_service_id'')::uuid), ''That therapy service''); end if;' || chr(10) ||
    '      v_price := public.therapy_service_price((v_item->>''therapy_service_id'')::uuid, p_store_id);' || chr(10) ||
    '      if v_price is null then raise exception ''"%" has no price at this store'',' || chr(10) ||
    '        (select s.name from public.therapy_services s' || chr(10) ||
    '          where s.id = (v_item->>''therapy_service_id'')::uuid); end if;' || chr(10) ||
    '      v_gross := v_price * v_qty;' || chr(10) || chr(10) ||
    '    ';

  v_insert_branch :=
    'elsif v_kind = ''therapy'' and nullif(v_item->>''therapy_service_id'', '''') is not null then' || chr(10) ||
    '      v_price := public.therapy_service_price((v_item->>''therapy_service_id'')::uuid, p_store_id);' || chr(10) ||
    '      v_gross := v_price * v_qty;' || chr(10) ||
    '      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;' || chr(10) ||
    '      v_line_total := round(v_gross - v_foc_amt, 2);' || chr(10) ||
    '      insert into public.invoice_items' || chr(10) ||
    '        (invoice_id, line_kind, product_id, therapy_package_id, therapy_service_id,' || chr(10) ||
    '         quantity, unit_price, line_total, price_mode, price_source, price_source_id,' || chr(10) ||
    '         store_id_snapshot, original_price,' || chr(10) ||
    '         therapy_service_name_snapshot, therapy_service_minutes_snapshot,' || chr(10) ||
    '         price_overridden, override_reason, override_by, override_at,' || chr(10) ||
    '         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)' || chr(10) ||
    '      values (v_invoice_id, ''therapy'', null, null, (v_item->>''therapy_service_id'')::uuid,' || chr(10) ||
    '        v_qty, v_price, v_line_total, v_mode,' || chr(10) ||
    '        case when v_mode_ovr is null then ''therapy'' else ''manual_override'' end,' || chr(10) ||
    '        (v_item->>''therapy_service_id'')::uuid, p_store_id, v_price,' || chr(10) ||
    '        (select s.name from public.therapy_services s where s.id = (v_item->>''therapy_service_id'')::uuid),' || chr(10) ||
    '        (select s.duration_minutes from public.therapy_services s where s.id = (v_item->>''therapy_service_id'')::uuid),' || chr(10) ||
    '        v_mode_ovr is not null, v_ovr_reason,' || chr(10) ||
    '        case when v_mode_ovr is not null then auth.uid() end,' || chr(10) ||
    '        case when v_mode_ovr is not null then now() end,' || chr(10) ||
    '        v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,' || chr(10) ||
    '        case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,' || chr(10) ||
    '        case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);' || chr(10) || chr(10) ||
    '    ';

  -- create_invoice has SEVERAL OVERLOADS. Successive migrations added arguments,
  -- and "create or replace" with a new argument list creates a new function
  -- rather than replacing the old one, so the six-argument version from
  -- migration 09 still exists beside the current one.
  --
  -- Which is why this selects by CONTENT, not by position. Picking the first or
  -- the oldest oid patches a function nothing calls and leaves the live one
  -- untouched — the patch would appear to succeed and change nothing.
  for r in
    select p.oid, p.oid::regprocedure::text as sig, pg_get_functiondef(p.oid) as def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'create_invoice'
     order by p.oid
  loop
    if position('therapy_service_id' in r.def) > 0 then
      v_already := v_already + 1;
      continue;                                   -- this overload is already patched
    end if;

    if position(v_check_anchor in r.def) = 0 or position(v_insert_anchor in r.def) = 0 then
      -- An older overload that never had therapy support. Left exactly as it is.
      v_skipped := v_skipped + 1;
      continue;
    end if;

    f := r.def;
    f := replace(f, v_check_anchor, v_check_branch || v_check_anchor);
    f := replace(f, v_insert_anchor, v_insert_branch || v_insert_anchor);
    execute f;
    v_patched := v_patched + 1;
    raise notice 'create_invoice now sells individual therapy sessions: %', r.sig;
  end loop;

  if v_patched = 0 and v_already = 0 then
    if v_skipped = 0 then
      raise notice 'create_invoice is not installed here; the session branch was not added.';
    else
      -- Deliberately a hard stop. Adding a branch to the wrong place in this
      -- function would mis-price invoices, which is far worse than not shipping.
      raise exception 'No create_invoice overload has the expected therapy branches — '
        'add the session branch by hand rather than letting this migration guess.';
    end if;
  end if;

  if v_already > 0 and v_patched = 0 then
    raise notice 'create_invoice already sells therapy sessions; nothing to do.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Reading a customer's purchased sessions.
-- ---------------------------------------------------------------------
create or replace function public.customer_therapy_session_balance(p_customer_id uuid)
returns table(service_id uuid, service_name text, duration_minutes integer,
              purchased integer, used integer, remaining integer,
              last_purchased_at timestamptz)
language sql stable set search_path = public as $function$
  select s.service_id,
         max(s.service_name_snapshot),
         max(s.service_minutes_snapshot),
         sum(s.quantity_purchased)::integer,
         sum(s.quantity_used)::integer,
         sum(s.quantity_purchased - s.quantity_used)::integer,
         max(s.purchased_at)
    from public.customer_therapy_sessions s
   where s.customer_id = p_customer_id and s.status = 'available'
   group by s.service_id
  having sum(s.quantity_purchased - s.quantity_used) > 0
   order by max(s.purchased_at) desc
$function$;

-- ---------------------------------------------------------------------
-- 6. Access.
-- ---------------------------------------------------------------------
alter table public.customer_therapy_sessions enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='customer_therapy_sessions' and policyname='read therapy sessions') then
    create policy "read therapy sessions" on public.customer_therapy_sessions
      for select to authenticated using (true);
  end if;
end $$;

grant execute on function public.create_therapy_sessions_for_invoice(uuid) to authenticated;
grant execute on function public.customer_therapy_session_balance(uuid) to authenticated;
