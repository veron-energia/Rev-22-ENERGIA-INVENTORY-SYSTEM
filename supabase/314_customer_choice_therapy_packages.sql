begin;
-- =====================================================================
-- A PACKAGE THE CUSTOMER CHOOSES THE BENEFIT OF
--
-- A therapy package has always granted one fixed thing: a period of unlimited
-- therapy, or a quantity of vouchers. This adds a third kind that offers both
-- and lets the customer pick -- at the till, or later -- while each purchased
-- unit provides exactly one of them, never both.
--
-- Two decisions shape everything below.
--
-- First, a unit is the thing that has a benefit. create_purchased_therapy_for
-- _invoice already writes one purchased_therapy_entitlements row per unit and
-- tops up rather than duplicating on a re-run, so two of Package C were always
-- two rows. Choice is recorded on the row that already exists rather than in a
-- new table keyed by line and quantity.
--
-- Second, choosing vouchers does not build a second voucher system. It creates
-- an ordinary therapy_entitlements voucher row -- the same record a legacy
-- reward produces -- so claim_entitlement_vouchers, partial claims, the Voucher
-- Claim document, the deadline and revocation on refund all apply unchanged.
-- The purchased unit holds a pointer to it. There is one balance, in the place
-- that already owned balances.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Packages may now offer a choice.
-- ---------------------------------------------------------------------
alter table public.unlimited_therapy_packages
  drop constraint if exists utp_entitlement_kind_check;
alter table public.unlimited_therapy_packages
  add constraint utp_entitlement_kind_check
  check (entitlement_kind = any (array['unlimited','voucher','choice']));

-- The single voucher_id stays for the voucher-only packages that use it. A
-- choice package draws from a list instead, because the customer is choosing.
alter table public.unlimited_therapy_packages
  drop constraint if exists utp_voucher_shape_check;
alter table public.unlimited_therapy_packages
  add constraint utp_voucher_shape_check
  check (entitlement_kind <> 'voucher'
         or (coalesce(voucher_qty,0) > 0 and voucher_id is not null));
alter table public.unlimited_therapy_packages
  drop constraint if exists utp_choice_shape_check;
alter table public.unlimited_therapy_packages
  add constraint utp_choice_shape_check
  check (entitlement_kind <> 'choice'
         or (coalesce(voucher_qty,0) > 0 and coalesce(duration_months,0) > 0));

comment on column public.unlimited_therapy_packages.entitlement_kind is
  'unlimited | voucher | choice. A choice package offers both; each purchased unit takes one.';

-- ---------------------------------------------------------------------
-- 2. What a choice package may be taken as.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_package_vouchers (
  package_id uuid not null references public.unlimited_therapy_packages(id) on delete cascade,
  voucher_id uuid not null references public.vouchers(id),
  primary key (package_id, voucher_id)
);

create table if not exists public.therapy_package_services (
  package_id uuid not null references public.unlimited_therapy_packages(id) on delete cascade,
  service_id uuid not null references public.therapy_services(id),
  primary key (package_id, service_id)
);

alter table public.therapy_package_vouchers enable row level security;
alter table public.therapy_package_services enable row level security;
do $$ begin
  create policy "read therapy package vouchers" on public.therapy_package_vouchers
    for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "read therapy package services" on public.therapy_package_services
    for select to authenticated using (true);
exception when duplicate_object then null; end $$;
grant select on public.therapy_package_vouchers to authenticated;
grant select on public.therapy_package_services to authenticated;

-- ---------------------------------------------------------------------
-- 3. What each purchased unit is, and what it was sold with.
--
-- The snapshot columns are the point: a package is editable and a unit
-- outlives the edit, so what the customer may choose is frozen at purchase.
-- ---------------------------------------------------------------------
alter table public.purchased_therapy_entitlements
  add column if not exists unit_index integer,
  add column if not exists unit_count integer,
  add column if not exists offered_choices text[],
  add column if not exists benefit_choice text,
  add column if not exists benefit_chosen_by uuid references public.profiles(id),
  add column if not exists benefit_chosen_at timestamptz,
  add column if not exists voucher_qty_snapshot integer,
  add column if not exists eligible_voucher_ids uuid[],
  add column if not exists eligible_service_ids uuid[],
  add column if not exists voucher_entitlement_id uuid references public.therapy_entitlements(id),
  add column if not exists choice_deadline date;

alter table public.purchased_therapy_entitlements
  drop constraint if exists pte_benefit_choice_check;
alter table public.purchased_therapy_entitlements
  add constraint pte_benefit_choice_check
  check (benefit_choice is null or benefit_choice = any (array['unlimited','voucher']));

-- One effective benefit per unit: a unit that took vouchers may not also be
-- running therapy, and the pointer only exists on the voucher path.
alter table public.purchased_therapy_entitlements
  drop constraint if exists pte_one_benefit_check;
alter table public.purchased_therapy_entitlements
  add constraint pte_one_benefit_check
  check (
    -- Only where a choice actually existed. A voucher-ONLY package has always
    -- stamped its units active on payment, because there is nothing to
    -- activate, and that bookkeeping is not this constraint's business.
    (benefit_choice is distinct from 'voucher')
    or (coalesce(array_length(offered_choices, 1), 0) < 2)
    or (activation_date is null and scheduled_date is null)
  );
alter table public.purchased_therapy_entitlements
  drop constraint if exists pte_voucher_link_check;
alter table public.purchased_therapy_entitlements
  add constraint pte_voucher_link_check
  check (voucher_entitlement_id is null or benefit_choice = 'voucher');

comment on column public.purchased_therapy_entitlements.benefit_choice is
  'null while the choice is pending; unlimited or voucher once made. A unit never has both.';
comment on column public.purchased_therapy_entitlements.offered_choices is
  'What this unit was sold as choosable, frozen at purchase.';

create index if not exists pte_pending_choice_idx
  on public.purchased_therapy_entitlements(customer_id)
  where benefit_choice is null;

-- ---------------------------------------------------------------------
-- 4. Every switch is kept, with its reason.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_benefit_choice_history (
  id uuid primary key default gen_random_uuid(),
  purchased_entitlement_id uuid not null
    references public.purchased_therapy_entitlements(id) on delete cascade,
  previous_choice text,
  new_choice text not null,
  reason text not null,
  changed_by uuid references public.profiles(id),
  changed_at timestamptz not null default now(),
  source_invoice_id uuid references public.invoices(id)
);
create index if not exists tbch_unit_idx
  on public.therapy_benefit_choice_history(purchased_entitlement_id);
alter table public.therapy_benefit_choice_history enable row level security;
do $$ begin
  create policy "read therapy benefit choice history" on public.therapy_benefit_choice_history
    for select to authenticated using (
      exists (select 1 from public.purchased_therapy_entitlements p
               where p.id = purchased_entitlement_id
                 and public.user_has_store_access(p.store_id)));
exception when duplicate_object then null; end $$;
grant select on public.therapy_benefit_choice_history to authenticated;


-- ---------------------------------------------------------------------
-- 5. Configuring one. Same permission as any therapy package.
-- ---------------------------------------------------------------------
create or replace function public.upsert_therapy_package_choice(
  p_id uuid, p_name text, p_sku text, p_description text, p_is_active boolean,
  p_duration_months integer, p_voucher_qty integer,
  p_voucher_ids uuid[], p_service_ids uuid[])
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage therapy packages'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'A package name is required'; end if;
  if coalesce(p_duration_months,0) <= 0 then
    raise exception 'Set how many calendar months the unlimited therapy runs'; end if;
  if coalesce(p_voucher_qty,0) <= 0 then
    raise exception 'Set how many vouchers the package grants'; end if;
  if p_voucher_ids is null or array_length(p_voucher_ids,1) is null then
    raise exception 'Choose at least one voucher the customer may pick from'; end if;

  -- A choice is only real if both sides can actually be taken.
  if exists (select 1 from unnest(p_voucher_ids) v
              where not exists (select 1 from public.vouchers x
                                 where x.id = v and x.is_active and x.deleted_at is null)) then
    raise exception 'One of the chosen vouchers is inactive or deleted'; end if;
  if p_service_ids is not null and exists (
       select 1 from unnest(p_service_ids) s
        where not exists (select 1 from public.therapy_services x where x.id = s)) then
    raise exception 'One of the chosen therapy services no longer exists'; end if;

  if p_id is null then
    insert into public.unlimited_therapy_packages
      (name, sku, description, is_active, duration_months, entitlement_kind, voucher_qty, created_by, updated_by)
    values (trim(p_name), nullif(trim(coalesce(p_sku,'')),''), p_description,
            coalesce(p_is_active,true), p_duration_months, 'choice', p_voucher_qty, auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.unlimited_therapy_packages
       set name = trim(p_name), sku = nullif(trim(coalesce(p_sku,'')),''),
           description = p_description, is_active = coalesce(p_is_active,true),
           duration_months = p_duration_months, entitlement_kind = 'choice',
           voucher_qty = p_voucher_qty, updated_by = auth.uid(), updated_at = now()
     where id = p_id and deleted_at is null
     returning id into v_id;
    if v_id is null then raise exception 'Package not found'; end if;
  end if;

  -- Replacing these lists changes what FUTURE purchases may choose from.
  -- Units already sold carry their own snapshot and are untouched.
  delete from public.therapy_package_vouchers where package_id = v_id;
  insert into public.therapy_package_vouchers(package_id, voucher_id)
    select v_id, unnest(p_voucher_ids) on conflict do nothing;
  delete from public.therapy_package_services where package_id = v_id;
  if p_service_ids is not null then
    insert into public.therapy_package_services(package_id, service_id)
      select v_id, unnest(p_service_ids) on conflict do nothing;
  end if;

  perform public.write_audit('unlimited_therapy_packages', v_id,
    case when p_id is null then 'therapy_choice_package_created' else 'therapy_choice_package_updated' end,
    null, jsonb_build_object('name', trim(p_name), 'duration_months', p_duration_months,
                             'voucher_qty', p_voucher_qty,
                             'vouchers', to_jsonb(p_voucher_ids), 'services', to_jsonb(p_service_ids)));
  return v_id;
end $$;
grant execute on function public.upsert_therapy_package_choice(uuid,text,text,text,boolean,integer,integer,uuid[],uuid[]) to authenticated;

-- ---------------------------------------------------------------------
-- 6. What a package offers, for the screen that has to describe it.
--
-- Described from the package itself rather than from an example, so the words
-- on the invoice say "10 vouchers" because the package says 10.
-- ---------------------------------------------------------------------
create or replace function public.therapy_package_offer(p_package_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare pk public.unlimited_therapy_packages%rowtype; v_vouchers jsonb; v_services jsonb;
begin
  select * into pk from public.unlimited_therapy_packages
   where id = p_package_id and deleted_at is null;
  if not found then raise exception 'Package not found'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('voucher_id', v.id, 'name', v.name)
                            order by v.name), '[]'::jsonb)
    into v_vouchers
    from public.therapy_package_vouchers pv
    join public.vouchers v on v.id = pv.voucher_id
   where pv.package_id = p_package_id;

  select coalesce(jsonb_agg(jsonb_build_object('service_id', s.id, 'name', s.name)
                            order by s.name), '[]'::jsonb)
    into v_services
    from public.therapy_package_services ps
    join public.therapy_services s on s.id = ps.service_id
   where ps.package_id = p_package_id;

  return jsonb_build_object(
    'package_id', pk.id, 'name', pk.name, 'sku', pk.sku,
    'description', pk.description, 'kind', pk.entitlement_kind,
    'offers_choice', pk.entitlement_kind = 'choice',
    'duration_months', pk.duration_months,
    'voucher_qty', pk.voucher_qty,
    'eligible_vouchers', v_vouchers,
    'eligible_services', v_services,
    'unlimited_label', case when coalesce(pk.duration_months,0) = 1
                            then 'Unlimited therapy — 1 calendar month'
                            else 'Unlimited therapy — ' || pk.duration_months || ' calendar months' end,
    'voucher_label', case when coalesce(pk.voucher_qty,0) = 1
                          then 'Vouchers — 1 voucher'
                          else 'Vouchers — ' || pk.voucher_qty || ' vouchers' end);
end $$;
grant execute on function public.therapy_package_offer(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 6b. Unit numbering, across the invoice.
--
-- "Unit 1 of 2" has to count the units of a package on the whole invoice,
-- because a therapy line is always quantity 1 and two units are two lines.
-- Ordering is by creation then id so the numbering is stable across re-runs.
-- ---------------------------------------------------------------------
create or replace function public.renumber_therapy_units(p_invoice_id uuid)
returns void language sql security definer set search_path to 'public' as $$
  update public.purchased_therapy_entitlements t
     set unit_index = r.idx, unit_count = r.total
    from (select e.id,
                 row_number() over (partition by e.invoice_id, e.package_id
                                    order by e.created_at, e.id) as idx,
                 count(*)    over (partition by e.invoice_id, e.package_id) as total
            from public.purchased_therapy_entitlements e
           where e.invoice_id = p_invoice_id) r
   where t.id = r.id
     and (t.unit_index is distinct from r.idx or t.unit_count is distinct from r.total);
$$;
revoke all on function public.renumber_therapy_units(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 7. The purchase freezes the terms onto each unit.
--
-- Patched in place by content: this issuer's per-unit top-up and its price and
-- deadline handling are correct and must not be disturbed.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.create_purchased_therapy_for_invoice(uuid)'::regprocedure) into f;
  if position('offered_choices' in f) = 0 then
    f := replace(f,
      '        package_name, duration_months, price_snapshot, price_mode,
        purchase_date, activation_deadline, status, created_by, updated_by)',
      '        package_name, duration_months, price_snapshot, price_mode,
        purchase_date, activation_deadline, status, created_by, updated_by,
        unit_index, unit_count, offered_choices, benefit_choice, choice_deadline,
        voucher_qty_snapshot, eligible_voucher_ids, eligible_service_ids)');
    f := replace(f,
      '        v_deadline::date, ''pending_activation'', auth.uid(), auth.uid());',
      '        v_deadline::date, ''pending_activation'', auth.uid(), auth.uid(),
        v_have + v_i, v_due.qty,
        case when v_pkg.entitlement_kind = ''choice'' then array[''unlimited'',''voucher'']
             when v_pkg.entitlement_kind = ''voucher'' then array[''voucher'']
             else array[''unlimited''] end,
        -- A package that offers no choice has already made it.
        case when v_pkg.entitlement_kind = ''choice'' then null
             when v_pkg.entitlement_kind = ''voucher'' then ''voucher''
             else ''unlimited'' end,
        v_deadline::date,
        v_pkg.voucher_qty,
        case when v_pkg.entitlement_kind = ''choice''
             then (select coalesce(array_agg(voucher_id),''{}'')
                     from public.therapy_package_vouchers where package_id = v_pkg.id)
             when v_pkg.voucher_id is not null then array[v_pkg.voucher_id]
             else ''{}'' end,
        (select coalesce(array_agg(service_id),''{}'')
           from public.therapy_package_services where package_id = v_pkg.id));');
    -- A therapy line is always quantity 1 (create_invoice enforces it), so two
    -- units of the same package are two lines. Numbering therefore has to be
    -- worked out across the invoice, not within a line, which is what the
    -- renumber step below does once every row exists.
    f := replace(f,
      '  if v_n > 0 then',
      '  perform public.renumber_therapy_units(p_invoice_id);
  if v_n > 0 then');
    if position('offered_choices' in f) = 0 or position('renumber_therapy_units' in f) = 0 then
      raise exception 'create_purchased_therapy_for_invoice does not match what 314 expects — align it by hand'; end if;
    execute f;
    raise notice 'create_purchased_therapy_for_invoice now snapshots the offered terms per unit';
  end if;
end $do$;

-- Units created before this migration carry no snapshot and no choice. Their
-- benefit is not in doubt -- their package grants one thing -- so it is filled
-- in from the package's own kind. A 'choice' package cannot appear here,
-- because none existed before this migration.
update public.purchased_therapy_entitlements p
   set benefit_choice = case when k.entitlement_kind = 'voucher' then 'voucher' else 'unlimited' end,
       offered_choices = case when k.entitlement_kind = 'voucher' then array['voucher'] else array['unlimited'] end,
       unit_index = coalesce(p.unit_index, 1),
       unit_count = coalesce(p.unit_count, 1),
       choice_deadline = coalesce(p.choice_deadline, p.activation_deadline)
  from public.unlimited_therapy_packages k
 where k.id = p.package_id
   and p.benefit_choice is null
   and k.entitlement_kind in ('unlimited','voucher');

-- ---------------------------------------------------------------------
-- 8. Retry protection.
--
-- A disabled button is not protection: a retried request, a double submit or a
-- reconnecting client can all arrive twice. Each choosing call carries a
-- request id, and the second one with the same id is refused rather than
-- creating a second voucher entitlement.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_choice_requests (
  request_id uuid primary key,
  purchased_entitlement_id uuid not null
    references public.purchased_therapy_entitlements(id) on delete cascade,
  action text not null,
  requested_by uuid references public.profiles(id),
  requested_at timestamptz not null default now()
);
alter table public.therapy_choice_requests enable row level security;

-- ---------------------------------------------------------------------
-- 9. Recording the customer's choice.
--
-- Choosing vouchers does not mint a new kind of balance: it creates the same
-- therapy_entitlements voucher row a legacy reward creates, so the existing
-- claim engine, partial claims, Voucher Claim document, deadline and
-- revocation all apply to it unchanged.
--
-- Nothing here starts therapy. Choosing unlimited records the choice and stops;
-- the existing activation workflow, with its own date rules, overlap check and
-- holiday calendar, is still what starts it.
-- ---------------------------------------------------------------------
create or replace function public.choose_therapy_benefit(
  p_purchased_id uuid, p_choice text, p_request_id uuid default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare e public.purchased_therapy_entitlements%rowtype; v_ent uuid; v_no text;
begin
  if p_choice not in ('unlimited','voucher') then
    raise exception 'Choose either unlimited therapy or vouchers'; end if;

  if p_request_id is not null then
    begin
      insert into public.therapy_choice_requests(request_id, purchased_entitlement_id, action, requested_by)
      values (p_request_id, p_purchased_id, 'choose', auth.uid());
    exception when unique_violation then
      raise exception 'That choice has already been submitted'; end;
  end if;

  -- for update: two tills, or a retry racing the original, must not both choose.
  select * into e from public.purchased_therapy_entitlements
   where id = p_purchased_id for update;
  if not found then raise exception 'Purchased package not found'; end if;
  if not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;
  if e.status in ('cancelled','refunded') then
    raise exception 'This purchase was %; nothing can be chosen against it', e.status; end if;
  if e.benefit_choice is not null then
    raise exception 'A benefit has already been chosen for this unit'; end if;
  if e.offered_choices is null or not (p_choice = any(e.offered_choices)) then
    raise exception 'This purchase was not sold with % as an option', p_choice; end if;
  if e.choice_deadline is not null and public.sg_today() > e.choice_deadline then
    raise exception 'The deadline for choosing (%) has passed', e.choice_deadline; end if;

  if p_choice = 'voucher' then
    -- The allowance lives where every other voucher allowance lives.
    v_no := public.next_legacy_entitlement_no();
    insert into public.therapy_entitlements (
      entitlement_no, customer_id, store_id, rule_id, package_name,
      entitlement_kind, duration_months, voucher_qty, qualifying_amount,
      qualified_value, forfeited_value, activation_deadline, status,
      created_by, qualification_group_id, earner_kind,
      eligible_voucher_ids, claim_source_type, claim_source_invoice_id)
    values (
      v_no, e.customer_id, e.store_id, null,
      e.package_name || ' — vouchers',
      'voucher', 1, coalesce(e.voucher_qty_snapshot,0), 0,
      coalesce(e.price_snapshot,0), 0, e.choice_deadline,
      'pending_activation', auth.uid(),
      md5('therapy_unit:' || e.id::text)::uuid, 'therapy_package',
      e.eligible_voucher_ids, 'therapy_package', e.invoice_id)
    returning id into v_ent;
  end if;

  update public.purchased_therapy_entitlements
     set benefit_choice = p_choice,
         benefit_chosen_by = auth.uid(),
         benefit_chosen_at = now(),
         voucher_entitlement_id = v_ent,
         updated_by = auth.uid(), updated_at = now()
   where id = p_purchased_id;

  insert into public.therapy_benefit_choice_history
    (purchased_entitlement_id, previous_choice, new_choice, reason, changed_by, source_invoice_id)
  values (p_purchased_id, null, p_choice,
          coalesce(nullif(trim(coalesce(p_note,'')),''), 'Initial choice'), auth.uid(), e.invoice_id);

  perform public.write_audit_ex('purchased_therapy_entitlements', p_purchased_id,
    'therapy_benefit_chosen', jsonb_build_object('choice', null),
    jsonb_build_object('choice', p_choice, 'voucher_entitlement_id', v_ent),
    'therapy', p_note, e.store_id);

  return jsonb_build_object('success', true, 'choice', p_choice,
    'voucher_entitlement_id', v_ent,
    'state', public.purchased_therapy_unit_state(p_purchased_id));
end $$;
grant execute on function public.choose_therapy_benefit(uuid,text,uuid,text) to authenticated;

-- ---------------------------------------------------------------------
-- 10. Everything the counter needs about one unit.
--
-- Voucher figures are read from the voucher entitlement rather than copied, so
-- this and the claim panel cannot disagree.
-- ---------------------------------------------------------------------
create or replace function public.purchased_therapy_unit_state(p_purchased_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare e public.purchased_therapy_entitlements%rowtype; v_vouchers jsonb;
        v_elig jsonb; v_svc jsonb; v_switchable boolean; v_blocked text;
begin
  select * into e from public.purchased_therapy_entitlements where id = p_purchased_id;
  if not found then raise exception 'Purchased package not found'; end if;
  if not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;

  if e.voucher_entitlement_id is not null then
    v_vouchers := public.entitlement_voucher_state(e.voucher_entitlement_id);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('voucher_id', v.id, 'name', v.name) order by v.name), '[]'::jsonb)
    into v_elig from public.vouchers v
   where v.id = any(coalesce(e.eligible_voucher_ids, '{}'::uuid[]));
  select coalesce(jsonb_agg(jsonb_build_object('service_id', s.id, 'name', s.name) order by s.name), '[]'::jsonb)
    into v_svc from public.therapy_services s
   where s.id = any(coalesce(e.eligible_service_ids, '{}'::uuid[]));

  -- Switching is only safe while nothing has been committed on either side.
  -- 'scheduled' counts as committed: a start date is a promise to the customer
  -- and to the overlap check, even though the period has not begun.
  v_blocked := case
    when e.status in ('cancelled','refunded') then 'This purchase was ' || e.status || '.'
    when e.benefit_choice is null then 'No benefit has been chosen yet.'
    when array_length(coalesce(e.offered_choices,'{}'),1) is null
      or array_length(e.offered_choices,1) < 2 then 'This package only ever offered one benefit.'
    when e.activation_date is not null or e.scheduled_date is not null
      or e.status in ('scheduled','active','expired')
      then 'Therapy has already been activated or scheduled. Use the correction or refund workflow.'
    when coalesce((v_vouchers->>'claimed')::int, 0) > 0
      then 'Vouchers from this unit have already been claimed. Use the correction or refund workflow.'
    else null end;
  v_switchable := v_blocked is null;

  return jsonb_build_object(
    'purchased_id', e.id,
    'entitlement_no', e.entitlement_no,
    'customer_id', e.customer_id,
    'store_id', e.store_id,
    'package_id', e.package_id,
    'package_name', e.package_name,
    'unit_index', coalesce(e.unit_index,1),
    'unit_count', coalesce(e.unit_count,1),
    'unit_label', e.package_name || ' — Unit ' || coalesce(e.unit_index,1)
                  || ' of ' || coalesce(e.unit_count,1),
    'invoice_id', e.invoice_id,
    'invoice_item_id', e.invoice_item_id,
    'offered_choices', to_jsonb(coalesce(e.offered_choices,'{}')),
    'offers_choice', coalesce(array_length(e.offered_choices,1),0) > 1,
    'benefit_choice', e.benefit_choice,
    'choice_pending', e.benefit_choice is null,
    'benefit_chosen_at', e.benefit_chosen_at,
    'choice_deadline', e.choice_deadline,
    'choice_deadline_passed', e.choice_deadline is not null and public.sg_today() > e.choice_deadline,
    'status', e.status,
    'duration_months', e.duration_months,
    'scheduled_date', e.scheduled_date,
    'activation_date', e.activation_date,
    'expiry_date', e.expiry_date,
    'activation_deadline', e.activation_deadline,
    'voucher_qty', coalesce(e.voucher_qty_snapshot,0),
    'voucher_entitlement_id', e.voucher_entitlement_id,
    'vouchers', v_vouchers,
    'eligible_vouchers', v_elig,
    'eligible_services', v_svc,
    'can_switch', v_switchable,
    'switch_blocked_reason', v_blocked,
    'switch_requires_role', 'owner_or_manager');
end $$;
grant execute on function public.purchased_therapy_unit_state(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 11. Switching a choice that has not been used.
--
-- Owner or Manager only, reason required, and atomic: the previous benefit is
-- withdrawn and the replacement created in one statement pair inside one
-- transaction, so there is never a moment when a unit offers both.
-- ---------------------------------------------------------------------
create or replace function public.switch_therapy_benefit(
  p_purchased_id uuid, p_new_choice text, p_reason text, p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare e public.purchased_therapy_entitlements%rowtype; v_state jsonb;
        v_prev text; v_old_ent uuid; v_new_ent uuid; v_claimed int;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can switch a chosen benefit' using errcode='42501'; end if;
  if p_new_choice not in ('unlimited','voucher') then
    raise exception 'Choose either unlimited therapy or vouchers'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Give a reason for the switch; it is kept with the purchase'; end if;

  if p_request_id is not null then
    begin
      insert into public.therapy_choice_requests(request_id, purchased_entitlement_id, action, requested_by)
      values (p_request_id, p_purchased_id, 'switch', auth.uid());
    exception when unique_violation then
      raise exception 'That switch has already been submitted'; end;
  end if;

  select * into e from public.purchased_therapy_entitlements
   where id = p_purchased_id for update;
  if not found then raise exception 'Purchased package not found'; end if;
  if not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;

  v_state := public.purchased_therapy_unit_state(p_purchased_id);
  if not (v_state->>'can_switch')::boolean then
    raise exception '%', coalesce(v_state->>'switch_blocked_reason', 'This benefit cannot be switched'); end if;
  if e.benefit_choice = p_new_choice then
    raise exception 'That is already the chosen benefit'; end if;

  v_prev := e.benefit_choice;
  v_old_ent := e.voucher_entitlement_id;

  -- Withdraw the old side first, in the same transaction as creating the new.
  if v_prev = 'voucher' and v_old_ent is not null then
    select public.entitlement_claimed_qty(v_old_ent) into v_claimed;
    if v_claimed > 0 then
      raise exception 'Vouchers from this unit have already been claimed'; end if;
    update public.therapy_entitlements
       set status = 'cancelled',
           revoked_qty = coalesce(voucher_qty,0),
           revoked_at = now(),
           revoked_reason = 'Benefit switched to unlimited therapy: ' || trim(p_reason)
     where id = v_old_ent;
  end if;

  if p_new_choice = 'voucher' then
    insert into public.therapy_entitlements (
      entitlement_no, customer_id, store_id, rule_id, package_name,
      entitlement_kind, duration_months, voucher_qty, qualifying_amount,
      qualified_value, forfeited_value, activation_deadline, status,
      created_by, qualification_group_id, earner_kind,
      eligible_voucher_ids, claim_source_type, claim_source_invoice_id)
    values (
      public.next_legacy_entitlement_no(), e.customer_id, e.store_id, null,
      e.package_name || ' — vouchers',
      'voucher', 1, coalesce(e.voucher_qty_snapshot,0), 0,
      coalesce(e.price_snapshot,0), 0, e.choice_deadline,
      'pending_activation', auth.uid(),
      md5('therapy_unit_switch:' || e.id::text || ':' || now()::text)::uuid, 'therapy_package',
      e.eligible_voucher_ids, 'therapy_package', e.invoice_id)
    returning id into v_new_ent;
  end if;

  update public.purchased_therapy_entitlements
     set benefit_choice = p_new_choice,
         benefit_chosen_by = auth.uid(),
         benefit_chosen_at = now(),
         voucher_entitlement_id = v_new_ent,
         updated_by = auth.uid(), updated_at = now()
   where id = p_purchased_id;

  insert into public.therapy_benefit_choice_history
    (purchased_entitlement_id, previous_choice, new_choice, reason, changed_by, source_invoice_id)
  values (p_purchased_id, v_prev, p_new_choice, trim(p_reason), auth.uid(), e.invoice_id);

  perform public.write_audit_ex('purchased_therapy_entitlements', p_purchased_id,
    'therapy_benefit_switched',
    jsonb_build_object('choice', v_prev, 'voucher_entitlement_id', v_old_ent),
    jsonb_build_object('choice', p_new_choice, 'voucher_entitlement_id', v_new_ent,
                       'reason', trim(p_reason)),
    'therapy', trim(p_reason), e.store_id);

  return jsonb_build_object('success', true, 'previous_choice', v_prev,
    'new_choice', p_new_choice, 'voucher_entitlement_id', v_new_ent,
    'state', public.purchased_therapy_unit_state(p_purchased_id));
end $$;
grant execute on function public.switch_therapy_benefit(uuid,text,text,uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 12. Therapy only starts on a unit that chose therapy.
--
-- The constraint already stops a voucher unit carrying an activation date;
-- this refuses it with a sentence a person can act on, and refuses a unit whose
-- customer has not chosen at all.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.activate_purchased_therapy(uuid,date,text,text,text,boolean)'::regprocedure) into f;
  if position('benefit_choice' in f) = 0 then
    f := replace(f,
      '  if e.status in (''active'',''expired'',''cancelled'',''refunded'') then
    raise exception ''Entitlement is already %'', e.status; end if;',
      '  if e.status in (''active'',''expired'',''cancelled'',''refunded'') then
    raise exception ''Entitlement is already %'', e.status; end if;
  -- One benefit per unit: therapy cannot start on a unit that took vouchers,
  -- and a unit with no choice yet has nothing to start.
  if e.benefit_choice = ''voucher'' then
    raise exception ''This unit was taken as vouchers, so therapy cannot be activated on it''; end if;
  if e.benefit_choice is null then
    raise exception ''Choose a benefit for this unit before activating therapy''; end if;');
    if position('benefit_choice' in f) = 0 then
      raise exception 'activate_purchased_therapy does not match what 314 expects — align it by hand'; end if;
    execute f;
    raise notice 'activate_purchased_therapy now requires the unit to have chosen therapy';
  end if;
end $do$;

-- ---------------------------------------------------------------------
-- 13. A refund or cancellation takes the unused benefit with it.
--
-- Whatever the unit had -- a pending choice, an unstarted therapy right, or an
-- unclaimed voucher allowance -- stops being available. Claimed vouchers are
-- left to the existing refund rules, which already know how to value them.
-- Nothing is deleted: the history is the evidence.
-- ---------------------------------------------------------------------
create or replace function public.revoke_therapy_unit_benefit(
  p_purchased_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare e public.purchased_therapy_entitlements%rowtype; v_claimed int := 0; v_revoked int := 0;
begin
  select * into e from public.purchased_therapy_entitlements where id = p_purchased_id for update;
  if not found then raise exception 'Purchased package not found'; end if;

  if e.voucher_entitlement_id is not null then
    v_claimed := public.entitlement_claimed_qty(e.voucher_entitlement_id);
    v_revoked := greatest(coalesce((select voucher_qty from public.therapy_entitlements
                                     where id = e.voucher_entitlement_id),0)
                          - v_claimed
                          - coalesce((select revoked_qty from public.therapy_entitlements
                                       where id = e.voucher_entitlement_id),0), 0);
    if v_revoked > 0 then
      update public.therapy_entitlements
         set revoked_qty = coalesce(revoked_qty,0) + v_revoked,
             revoked_at = now(),
             revoked_reason = coalesce(p_reason,'Purchase reversed'),
             status = case when v_claimed = 0 then 'cancelled' else status end
       where id = e.voucher_entitlement_id;
    end if;
  end if;

  perform public.write_audit_ex('purchased_therapy_entitlements', p_purchased_id,
    'therapy_unit_benefit_revoked',
    jsonb_build_object('choice', e.benefit_choice, 'claimed', v_claimed),
    jsonb_build_object('revoked_vouchers', v_revoked, 'reason', p_reason),
    'therapy', p_reason, e.store_id);

  return jsonb_build_object('revoked_vouchers', v_revoked, 'kept_claimed', v_claimed);
end $$;
revoke all on function public.revoke_therapy_unit_benefit(uuid,text) from public, anon, authenticated;

-- Driven by the unit's own status, so a reversal reached by any route revokes,
-- and revoking twice withdraws nothing further.
create or replace function public.trg_revoke_therapy_unit_on_close()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.status in ('cancelled','refunded')
     and coalesce(old.status,'') is distinct from new.status then
    perform public.revoke_therapy_unit_benefit(new.id, 'Purchase ' || new.status);
  end if;
  return new;
end $$;

drop trigger if exists revoke_therapy_unit_on_close on public.purchased_therapy_entitlements;
create trigger revoke_therapy_unit_on_close
  after update of status on public.purchased_therapy_entitlements
  for each row execute function public.trg_revoke_therapy_unit_on_close();

-- A cancelled or refunded unit is also closed to choosing, which
-- choose_therapy_benefit already refuses; this keeps the invoice-level
-- cancellation reaching units that were never individually refunded.
create or replace function public.revoke_therapy_units_for_invoice(
  p_invoice_id uuid, p_reason text)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare r record; v_n integer := 0;
begin
  for r in select id from public.purchased_therapy_entitlements
            where invoice_id = p_invoice_id
              and status not in ('cancelled','refunded','active','expired')
            for update
  loop
    update public.purchased_therapy_entitlements
       set status = 'cancelled', updated_by = auth.uid(), updated_at = now()
     where id = r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
grant execute on function public.revoke_therapy_units_for_invoice(uuid,text) to authenticated;

-- ---------------------------------------------------------------------
-- 14. The Purchased tab, in one query.
--
-- Voucher figures come from the voucher entitlement, so the list and the claim
-- panel always agree. A pending choice is a state, not a fault, and is
-- reported as one.
-- ---------------------------------------------------------------------
create or replace function public.purchased_therapy_units(
  p_store_id uuid default null, p_customer_id uuid default null, p_pending_only boolean default false)
returns table (
  purchased_id uuid, entitlement_no text, customer_id uuid, customer_name text,
  store_id uuid, package_name text, unit_index integer, unit_count integer, unit_label text,
  invoice_id uuid, invoice_no text,
  offers_choice boolean, benefit_choice text, choice_pending boolean,
  choice_deadline date, choice_deadline_passed boolean,
  status text, duration_months integer, scheduled_date date, activation_date date,
  expiry_date date, activation_deadline date, days_remaining integer,
  voucher_entitlement_id uuid, voucher_entitled integer, voucher_claimed integer,
  voucher_remaining integer)
language sql stable security definer set search_path to 'public' as $$
  select e.id, e.entitlement_no, e.customer_id, c.full_name, e.store_id,
         e.package_name, coalesce(e.unit_index,1), coalesce(e.unit_count,1),
         e.package_name || ' — Unit ' || coalesce(e.unit_index,1) || ' of ' || coalesce(e.unit_count,1),
         e.invoice_id, i.invoice_no,
         coalesce(array_length(e.offered_choices,1),0) > 1,
         e.benefit_choice,
         e.benefit_choice is null,
         e.choice_deadline,
         e.choice_deadline is not null and public.sg_today() > e.choice_deadline,
         e.status, e.duration_months, e.scheduled_date, e.activation_date,
         e.expiry_date, e.activation_deadline,
         case when e.expiry_date is not null and e.status in ('active','scheduled')
              then greatest((e.expiry_date - public.sg_today())::integer, 0) end,
         e.voucher_entitlement_id,
         case when e.voucher_entitlement_id is not null
              then coalesce((select voucher_qty from public.therapy_entitlements
                              where id = e.voucher_entitlement_id),0) end,
         case when e.voucher_entitlement_id is not null
              then public.entitlement_claimed_qty(e.voucher_entitlement_id) end,
         case when e.voucher_entitlement_id is not null
              then greatest(coalesce((select voucher_qty from public.therapy_entitlements
                                       where id = e.voucher_entitlement_id),0)
                            - public.entitlement_claimed_qty(e.voucher_entitlement_id)
                            - coalesce((select revoked_qty from public.therapy_entitlements
                                         where id = e.voucher_entitlement_id),0), 0) end
    from public.purchased_therapy_entitlements e
    join public.customers c on c.id = e.customer_id
    left join public.invoices i on i.id = e.invoice_id
   where public.user_has_store_access(e.store_id)
     and (p_store_id is null or e.store_id = p_store_id)
     and (p_customer_id is null or e.customer_id = p_customer_id)
     and (not coalesce(p_pending_only,false) or e.benefit_choice is null)
   order by e.created_at desc, coalesce(e.unit_index,1)
$$;
grant execute on function public.purchased_therapy_units(uuid,uuid,boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 15. Units whose history cannot be reconstructed, for review.
--
-- The backfill above filled in a benefit for every unit whose package grants
-- only one thing. Anything it could not settle is reported rather than guessed
-- from today's catalogue.
-- ---------------------------------------------------------------------
create or replace function public.therapy_choice_reconciliation()
returns table (
  purchased_id uuid, entitlement_no text, customer_name text, package_name text,
  status text, issue text)
language sql stable security definer set search_path to 'public' as $$
  select e.id, e.entitlement_no, c.full_name, e.package_name, e.status,
         case
           when e.benefit_choice is null and coalesce(array_length(e.offered_choices,1),0) = 0
             then 'No benefit recorded and no offered choices; the original package terms are unknown'
           when e.benefit_choice is null and public.sg_today() > coalesce(e.choice_deadline, e.activation_deadline)
             then 'Choice never made and the deadline has passed'
           when e.benefit_choice is null then 'Choice still pending'
           when e.benefit_choice = 'voucher' and e.voucher_entitlement_id is null
             then 'Recorded as vouchers but no voucher allowance exists'
           when e.benefit_choice = 'unlimited' and e.voucher_entitlement_id is not null
             then 'Recorded as unlimited therapy but a voucher allowance is attached'
         end as issue
    from public.purchased_therapy_entitlements e
    join public.customers c on c.id = e.customer_id
   where public.user_has_store_access(e.store_id)
     and (
       (e.benefit_choice is null)
       or (e.benefit_choice = 'voucher' and e.voucher_entitlement_id is null)
       or (e.benefit_choice = 'unlimited' and e.voucher_entitlement_id is not null)
     )
   order by e.created_at
$$;
grant execute on function public.therapy_choice_reconciliation() to authenticated;

-- ---------------------------------------------------------------------
-- 16. The choice made while preparing the invoice.
--
-- Recorded on the line as an INTENT, not as a benefit. Nothing is issued and
-- nothing starts here: the units do not exist until the invoice is paid, and
-- the intent is applied at that point by the same code path any later choice
-- uses. "Choose later" is simply the absence of an intent.
-- ---------------------------------------------------------------------
alter table public.invoice_items
  add column if not exists therapy_benefit_intent text;
alter table public.invoice_items
  drop constraint if exists invoice_items_therapy_intent_check;
alter table public.invoice_items
  add constraint invoice_items_therapy_intent_check
  check (therapy_benefit_intent is null
         or therapy_benefit_intent = any (array['unlimited','voucher']));
comment on column public.invoice_items.therapy_benefit_intent is
  'What the customer said they wanted at the till. Applied when the units are created at payment. Null means they will choose later.';

do $do$
declare f text;
begin
  select pg_get_functiondef('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)'::regprocedure) into f;
  if position('therapy_benefit_intent' in f) = 0 then
    f := replace(f,
      '        (invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         plan_name_snapshot, plan_months_snapshot,',
      '        (invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         plan_name_snapshot, plan_months_snapshot, therapy_benefit_intent,');
    f := replace(f,
      '              v_therapy_name, v_therapy_months,',
      '              v_therapy_name, v_therapy_months,
              nullif(v_item->>''therapy_benefit_intent'','''')::text,');
    if position('therapy_benefit_intent' in f) = 0 then
      raise exception 'create_invoice does not match what 314 expects — align it by hand'; end if;
    execute f;
    raise notice 'create_invoice now records the benefit chosen at the till';
  end if;
end $do$;

-- ---------------------------------------------------------------------
-- 17. Applying an intent once the units exist.
--
-- Runs after create_purchased_therapy_for_invoice, so it acts on real units
-- and goes through exactly the checks a counter choice goes through. An intent
-- that cannot be honoured -- the package was not sold as a choice, the unit was
-- reversed -- is skipped rather than forced, and the unit simply stays pending.
-- ---------------------------------------------------------------------
create or replace function public.apply_therapy_benefit_intents(p_invoice_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare r record; v_n integer := 0;
begin
  for r in
    select e.id as unit_id, ii.therapy_benefit_intent as intent
      from public.purchased_therapy_entitlements e
      join public.invoice_items ii on ii.id = e.invoice_item_id
     where e.invoice_id = p_invoice_id
       and e.benefit_choice is null
       and ii.therapy_benefit_intent is not null
       and e.status not in ('cancelled','refunded')
       and ii.therapy_benefit_intent = any(coalesce(e.offered_choices,'{}'))
  loop
    perform public.choose_therapy_benefit(r.unit_id, r.intent, null,
      'Chosen while the invoice was prepared');
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke all on function public.apply_therapy_benefit_intents(uuid) from public, anon, authenticated;

-- The issuer applies them as its last act, so a paid invoice leaves the counter
-- with the customer's choice already recorded.
do $do$
declare f text;
begin
  select pg_get_functiondef('public.create_purchased_therapy_for_invoice(uuid)'::regprocedure) into f;
  if position('apply_therapy_benefit_intents' in f) = 0 then
    f := replace(f,
      '  perform public.renumber_therapy_units(p_invoice_id);',
      '  perform public.renumber_therapy_units(p_invoice_id);
  perform public.apply_therapy_benefit_intents(p_invoice_id);');
    if position('apply_therapy_benefit_intents' in f) = 0 then
      raise exception 'create_purchased_therapy_for_invoice does not match what 314 expects — align it by hand'; end if;
    execute f;
    raise notice 'create_purchased_therapy_for_invoice now applies the till choice';
  end if;
end $do$;

notify pgrst,'reload schema';
commit;
