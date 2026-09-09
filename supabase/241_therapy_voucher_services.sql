-- =====================================================================
-- ENERGIA — THERAPY VOUCHERS, EXPRESSED IN SERVICES
--
-- A reward voucher today says only "a voucher". What it entitles the holder to
-- lives in its name and in whoever is at the counter. This migration lets a
-- voucher state, structurally, which therapy services it gives and in what
-- combination:
--
--   * one fixed session of Power Recharge
--   * one session chosen from Power Recharge or Foot Detox
--   * two flexible sessions chosen from the eligible services
--   * a fixed Power Recharge AND a fixed Foot Detox
--   * fixed sessions PLUS a configurable choice group
--
-- Nothing is assumed to be "any two therapies". A voucher with no definition is
-- simply not a therapy voucher, and reads that way — it is never guessed at.
--
-- ISSUANCE FREEZES THE TERMS. When a voucher is issued to a customer the whole
-- definition is copied into a snapshot: services with the names and codes they
-- had that day, quantities, choice groups, repeat rules, price and validity.
-- Editing the catalogue afterwards changes what is sold NEXT, never what a
-- customer already holds.
--
-- What this deliberately does not do: it redeems nothing. There is no action
-- here that consumes a session, because session redemption and appointment
-- booking are out of scope. The remaining-session model exists and reads
-- correctly; the only thing that currently reduces it is the existing
-- whole-voucher status on customer_reward_vouchers.
--
-- Requires 240 (therapy_services). Additive. Seeds nothing.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Which vouchers are therapy vouchers, and on what terms.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_voucher_definitions (
  voucher_id uuid primary key references public.vouchers(id) on delete cascade,

  -- Bumped on every edit. A snapshot records the version it froze, so a
  -- customer's rights can always be traced to the definition that produced them.
  version integer not null default 1 check (version > 0),

  -- How long the rights last once issued. 'none' means no expiry of its own —
  -- the voucher's own valid_until still applies where one is set.
  validity_kind text not null default 'none'
    check (validity_kind in ('none','days','months')),
  validity_value integer check (validity_value is null or validity_value > 0),

  -- How often the holder may use sessions FROM THIS VOUCHER. This sits on top
  -- of each service's own rule in 240: both have to allow a session, and the
  -- stricter one therefore decides. Same vocabulary, deliberately.
  repeat_kind text not null default 'unrestricted'
    check (repeat_kind in ('per_day','per_week','per_month','per_hours','unrestricted')),
  repeat_max_per_period integer not null default 1 check (repeat_max_per_period between 1 and 100),
  repeat_interval_hours numeric(8,2) check (repeat_interval_hours is null or repeat_interval_hours > 0),

  terms text,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint therapy_voucher_validity_value
    check ((validity_kind = 'none') = (validity_value is null)),
  constraint therapy_voucher_repeat_hours
    check (repeat_kind <> 'per_hours' or repeat_interval_hours is not null)
);

-- ---------------------------------------------------------------------
-- 2. What the voucher contains. One row per requirement, in order.
--
--    'fixed'  — this exact service, this many times.
--    'choice' — this many sessions, chosen from the services listed against it.
--
--    A voucher is the sum of its components, so every example above is
--    expressible without a special case for any of them.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_voucher_components (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.therapy_voucher_definitions(voucher_id) on delete cascade,
  sort_order integer not null check (sort_order > 0),
  component_kind text not null check (component_kind in ('fixed','choice')),

  -- Set for 'fixed'; null for 'choice', whose services are listed separately.
  service_id uuid references public.therapy_services(id),

  quantity integer not null default 1 check (quantity between 1 and 100),
  label text,

  constraint therapy_voucher_component_shape check (
    (component_kind = 'fixed'  and service_id is not null) or
    (component_kind = 'choice' and service_id is null)
  ),
  unique (voucher_id, sort_order)
);
create index if not exists idx_tvc_voucher on public.therapy_voucher_components (voucher_id);

-- The eligible services of a choice component.
create table if not exists public.therapy_voucher_component_services (
  component_id uuid not null references public.therapy_voucher_components(id) on delete cascade,
  service_id uuid not null references public.therapy_services(id),
  primary key (component_id, service_id)
);

-- A choice with nothing to choose from is not a choice, and a fixed component
-- has no list. Enforced by a trigger rather than a policy: this must hold on
-- every path into the table, including a direct insert by an Owner.
create or replace function public.trg_therapy_voucher_component_service_guard()
returns trigger language plpgsql set search_path = public as $function$
declare v_kind text;
begin
  select component_kind into v_kind
    from public.therapy_voucher_components where id = new.component_id;
  if v_kind is null then
    raise exception 'That voucher component no longer exists';
  end if;
  if v_kind <> 'choice' then
    raise exception 'Only a choice component lists eligible services';
  end if;
  return new;
end $function$;

drop trigger if exists trg_tvcs_guard on public.therapy_voucher_component_services;
create trigger trg_tvcs_guard before insert or update
  on public.therapy_voucher_component_services
  for each row execute function public.trg_therapy_voucher_component_service_guard();

-- ---------------------------------------------------------------------
-- 3. Reading a definition, whole.
-- ---------------------------------------------------------------------
create or replace function public.therapy_voucher_definition(p_voucher_id uuid)
returns jsonb language sql stable set search_path = public as $function$
  select case when d.voucher_id is null then null else jsonb_build_object(
    'voucher_id', d.voucher_id,
    'voucher_name', v.name,
    'voucher_code', v.code,
    'version', d.version,
    'selling_price', v.selling_price,
    'validity_kind', d.validity_kind,
    'validity_value', d.validity_value,
    'validity_text', case d.validity_kind
      when 'none' then 'No expiry of its own.'
      when 'days' then format('Valid for %s day(s) from issue.', d.validity_value)
      else format('Valid for %s month(s) from issue.', d.validity_value) end,
    'repeat_kind', d.repeat_kind,
    'repeat_max_per_period', d.repeat_max_per_period,
    'repeat_interval_hours', d.repeat_interval_hours,
    'repeat_text', public.therapy_frequency_description(
                     d.repeat_kind, d.repeat_max_per_period, d.repeat_interval_hours),
    'terms', d.terms,
    'sessions_per_voucher', coalesce((
      select sum(c.quantity) from public.therapy_voucher_components c
       where c.voucher_id = d.voucher_id), 0),
    'components', coalesce((
      select jsonb_agg(x order by (x->>'sort_order')::int) from (
        select jsonb_build_object(
          'sort_order', c.sort_order,
          'component_kind', c.component_kind,
          'quantity', c.quantity,
          'label', c.label,
          'services', coalesce((
            select jsonb_agg(jsonb_build_object(
                     'service_id', s.id, 'service_code', s.service_code, 'name', s.name,
                     'duration_minutes', s.duration_minutes,
                     'frequency_kind', s.frequency_kind,
                     'frequency_max_per_period', s.frequency_max_per_period,
                     'frequency_interval_hours', s.frequency_interval_hours)
                     order by s.name)
              from public.therapy_services s
             where (c.component_kind = 'fixed' and s.id = c.service_id)
                or (c.component_kind = 'choice' and s.id in (
                      select cs.service_id from public.therapy_voucher_component_services cs
                       where cs.component_id = c.id))), '[]'::jsonb)
        ) as x
        from public.therapy_voucher_components c
       where c.voucher_id = d.voucher_id) q), '[]'::jsonb)
  ) end
  from public.therapy_voucher_definitions d
  join public.vouchers v on v.id = d.voucher_id
 where d.voucher_id = p_voucher_id
$function$;

-- Plain English, for a list or an invoice line. Built from the same structure,
-- so it cannot drift from what is actually granted.
create or replace function public.therapy_voucher_summary_text(p_definition jsonb)
returns text language sql immutable as $function$
  select case when p_definition is null then null else
    coalesce(nullif(array_to_string(array(
      select case
        when c->>'component_kind' = 'fixed'
          then format('%s x %s', c->>'quantity', coalesce(c->'services'->0->>'name', 'a service'))
        else format('%s x chosen from %s', c->>'quantity',
                    coalesce(nullif((select string_agg(s->>'name', ' or ' order by s->>'name')
                                       from jsonb_array_elements(c->'services') s), ''),
                             'no eligible service'))
      end
      from jsonb_array_elements(p_definition->'components') c
      order by (c->>'sort_order')::int), ', then '), ''), 'No sessions defined.')
  end
$function$;

-- ---------------------------------------------------------------------
-- 4. Editing a definition. Owners and Managers only.
--
--    The whole structure is replaced in one call, so a definition is never
--    half-saved: a components array that fails validation leaves the previous
--    definition exactly as it was.
--
--    p_components is [{ kind, quantity, service_id, service_ids[], label }].
-- ---------------------------------------------------------------------
create or replace function public.upsert_therapy_voucher_definition(
  p_voucher_id uuid,
  p_components jsonb,
  p_validity_kind text default 'none',
  p_validity_value integer default null,
  p_repeat_kind text default 'unrestricted',
  p_repeat_max_per_period integer default 1,
  p_repeat_interval_hours numeric default null,
  p_terms text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_c jsonb; v_pos integer := 0; v_kind text; v_qty integer;
  v_component_id uuid; v_service uuid; v_ids uuid[]; v_version integer;
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can define what a therapy voucher gives';
  end if;
  perform 1 from public.vouchers where id = p_voucher_id and deleted_at is null;
  if not found then raise exception 'That voucher no longer exists'; end if;

  if p_components is null or jsonb_typeof(p_components) <> 'array'
     or jsonb_array_length(p_components) = 0 then
    -- Refused rather than defaulted. A therapy voucher whose contents nobody
    -- stated is exactly the guess this migration exists to remove.
    raise exception 'State what this voucher gives: at least one fixed session or one choice group';
  end if;

  if p_validity_kind not in ('none','days','months') then
    raise exception 'Validity must be none, days or months'; end if;
  if (p_validity_kind = 'none') <> (p_validity_value is null) then
    raise exception 'Give a validity length, or choose no expiry'; end if;
  if p_repeat_kind not in ('per_day','per_week','per_month','per_hours','unrestricted') then
    raise exception 'Choose how often sessions from this voucher may be taken'; end if;
  if p_repeat_kind = 'per_hours' and coalesce(p_repeat_interval_hours, 0) <= 0 then
    raise exception 'Enter the number of hours between sessions, for example 5'; end if;

  insert into public.therapy_voucher_definitions as d (
    voucher_id, validity_kind, validity_value, repeat_kind, repeat_max_per_period,
    repeat_interval_hours, terms, created_by, updated_by)
  values (p_voucher_id, p_validity_kind, p_validity_value, p_repeat_kind,
          coalesce(p_repeat_max_per_period, 1),
          case when p_repeat_kind = 'per_hours' then p_repeat_interval_hours else null end,
          nullif(btrim(p_terms), ''), auth.uid(), auth.uid())
  on conflict (voucher_id) do update
    set version = d.version + 1,
        validity_kind = excluded.validity_kind,
        validity_value = excluded.validity_value,
        repeat_kind = excluded.repeat_kind,
        repeat_max_per_period = excluded.repeat_max_per_period,
        repeat_interval_hours = excluded.repeat_interval_hours,
        terms = excluded.terms,
        updated_by = auth.uid(), updated_at = now()
  returning d.version into v_version;

  delete from public.therapy_voucher_components where voucher_id = p_voucher_id;

  for v_c in select * from jsonb_array_elements(p_components) loop
    v_pos := v_pos + 1;
    v_kind := coalesce(v_c->>'kind', 'fixed');
    v_qty  := coalesce((v_c->>'quantity')::integer, 1);
    if v_kind not in ('fixed','choice') then
      raise exception 'Component %: it is either a fixed session or a choice', v_pos; end if;
    if v_qty < 1 then
      raise exception 'Component %: how many sessions?', v_pos; end if;

    if v_kind = 'fixed' then
      v_service := nullif(v_c->>'service_id', '')::uuid;
      if v_service is null then
        raise exception 'Component %: choose the service this fixed session gives', v_pos; end if;
      perform 1 from public.therapy_services
        where id = v_service and deleted_at is null;
      if not found then
        raise exception 'Component %: that service no longer exists', v_pos; end if;

      insert into public.therapy_voucher_components
        (voucher_id, sort_order, component_kind, service_id, quantity, label)
      values (p_voucher_id, v_pos, 'fixed', v_service, v_qty, nullif(btrim(v_c->>'label'), ''));
    else
      select array_agg(distinct e::uuid) into v_ids
        from jsonb_array_elements_text(coalesce(v_c->'service_ids', '[]'::jsonb)) e;
      if v_ids is null or array_length(v_ids, 1) < 1 then
        raise exception 'Component %: a choice needs services to choose from', v_pos; end if;
      if exists (select 1 from unnest(v_ids) i
                  where not exists (select 1 from public.therapy_services s
                                     where s.id = i and s.deleted_at is null)) then
        raise exception 'Component %: one of those services no longer exists', v_pos; end if;

      insert into public.therapy_voucher_components
        (voucher_id, sort_order, component_kind, service_id, quantity, label)
      values (p_voucher_id, v_pos, 'choice', null, v_qty, nullif(btrim(v_c->>'label'), ''))
      returning id into v_component_id;

      insert into public.therapy_voucher_component_services (component_id, service_id)
      select v_component_id, i from unnest(v_ids) i;
    end if;
  end loop;

  perform public.write_audit('vouchers', p_voucher_id, 'therapy_voucher_definition_saved', null,
    jsonb_build_object('version', v_version,
                       'definition', public.therapy_voucher_definition(p_voucher_id)));

  return public.therapy_voucher_definition(p_voucher_id);
end $function$;

-- Removing the definition makes the voucher an ordinary voucher again. Already
-- issued snapshots are untouched — that is the whole point of a snapshot.
create or replace function public.clear_therapy_voucher_definition(p_voucher_id uuid)
returns void language plpgsql security definer set search_path = public as $function$
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can change a therapy voucher';
  end if;
  delete from public.therapy_voucher_definitions where voucher_id = p_voucher_id;
  perform public.write_audit('vouchers', p_voucher_id, 'therapy_voucher_definition_cleared',
    null, null);
end $function$;

-- ---------------------------------------------------------------------
-- 5. Issuance: the frozen copy.
--
--    One row per issued customer_reward_vouchers row. quantity there is a
--    number of vouchers, so the snapshot records both the per-voucher rights
--    and how many of them were issued.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_voucher_issues (
  id uuid primary key default gen_random_uuid(),
  reward_voucher_id uuid not null unique
    references public.customer_reward_vouchers(id) on delete cascade,
  voucher_id uuid not null references public.vouchers(id),
  customer_id uuid not null,
  definition_version integer not null,

  -- The whole definition as it stood, including service names and codes. Read
  -- this, not the catalogue, when answering what the customer holds.
  definition_snapshot jsonb not null,
  summary_text text,

  units integer not null check (units > 0),
  sessions_per_unit integer not null check (sessions_per_unit >= 0),
  sessions_total integer not null check (sessions_total >= 0),

  -- Nothing increments this yet: no redemption action exists, by design. It is
  -- here so the read model below is already shaped correctly for one.
  sessions_used integer not null default 0 check (sessions_used >= 0),

  issued_at timestamptz not null default now(),
  valid_until date,

  -- True when a Manager attached rights to a voucher issued before this
  -- migration existed, rather than the rights being frozen at issue.
  applied_retrospectively boolean not null default false,
  applied_by uuid references public.profiles(id),

  constraint therapy_voucher_issue_total
    check (sessions_total = units * sessions_per_unit),
  constraint therapy_voucher_issue_used
    check (sessions_used <= sessions_total)
);
create index if not exists idx_tvi_customer on public.therapy_voucher_issues (customer_id);
create index if not exists idx_tvi_voucher on public.therapy_voucher_issues (voucher_id);

/**
 * Freeze the current definition against an issued reward voucher.
 *
 * Silent and idempotent when there is nothing to freeze: a voucher with no
 * therapy definition is an ordinary voucher, and re-running never rewrites an
 * existing snapshot. Issuance happens inside invoice payment, so this must
 * never be a reason a paid invoice fails.
 */
create or replace function public.snapshot_therapy_voucher_issue(
  p_reward_voucher_id uuid, p_retrospective boolean default false)
returns uuid language plpgsql security definer set search_path = public as $function$
declare
  rv public.customer_reward_vouchers%rowtype;
  d public.therapy_voucher_definitions%rowtype;
  v_def jsonb; v_per integer; v_until date; v_id uuid;
begin
  select * into rv from public.customer_reward_vouchers where id = p_reward_voucher_id;
  if not found then return null; end if;

  select * into d from public.therapy_voucher_definitions where voucher_id = rv.voucher_id;
  if not found then return null; end if;             -- not a therapy voucher

  select id into v_id from public.therapy_voucher_issues
   where reward_voucher_id = p_reward_voucher_id;
  if v_id is not null then return v_id; end if;      -- already frozen; never re-frozen

  v_def := public.therapy_voucher_definition(rv.voucher_id);
  v_per := coalesce((v_def->>'sessions_per_voucher')::integer, 0);
  v_until := case d.validity_kind
    when 'days'   then (rv.issued_at at time zone 'Asia/Singapore')::date + d.validity_value
    when 'months' then ((rv.issued_at at time zone 'Asia/Singapore')::date
                        + make_interval(months => d.validity_value))::date - 1
    else null end;

  insert into public.therapy_voucher_issues (
    reward_voucher_id, voucher_id, customer_id, definition_version, definition_snapshot,
    summary_text, units, sessions_per_unit, sessions_total, issued_at, valid_until,
    applied_retrospectively, applied_by)
  values (rv.id, rv.voucher_id, rv.customer_id, d.version, v_def,
          public.therapy_voucher_summary_text(v_def),
          rv.quantity, v_per, rv.quantity * v_per, rv.issued_at, v_until,
          coalesce(p_retrospective, false),
          case when p_retrospective then auth.uid() else null end)
  on conflict (reward_voucher_id) do nothing
  returning id into v_id;

  return v_id;
end $function$;

create or replace function public.trg_snapshot_therapy_voucher_issue()
returns trigger language plpgsql set search_path = public as $function$
begin
  perform public.snapshot_therapy_voucher_issue(new.id, false);
  return null;
end $function$;

drop trigger if exists trg_therapy_voucher_issue on public.customer_reward_vouchers;
create trigger trg_therapy_voucher_issue after insert on public.customer_reward_vouchers
  for each row execute function public.trg_snapshot_therapy_voucher_issue();

/**
 * Attach rights to a voucher issued before the definition existed.
 *
 * Deliberately a separate, explicit, audited call rather than a backfill. A
 * voucher issued last year was sold on terms this table cannot know, so the
 * system will not decide on its own that today's catalogue describes it. A
 * Manager who does know says so, once, per voucher, and the snapshot records
 * that it was applied afterwards.
 */
create or replace function public.apply_therapy_voucher_rights_retrospectively(
  p_reward_voucher_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare v_id uuid;
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can attach rights to an already issued voucher';
  end if;
  if exists (select 1 from public.therapy_voucher_issues
              where reward_voucher_id = p_reward_voucher_id) then
    raise exception 'That voucher already has recorded therapy rights';
  end if;
  v_id := public.snapshot_therapy_voucher_issue(p_reward_voucher_id, true);
  if v_id is null then
    raise exception 'That voucher has no therapy-service definition to apply';
  end if;
  perform public.write_audit('customer_reward_vouchers', p_reward_voucher_id,
    'therapy_rights_applied_retrospectively', null,
    (select to_jsonb(i) from public.therapy_voucher_issues i where i.id = v_id));
  return (select to_jsonb(i) from public.therapy_voucher_issues i where i.id = v_id);
end $function$;

-- ---------------------------------------------------------------------
-- 6. What a customer actually holds.
--
--    Reads the snapshot, never the catalogue. A held voucher with no snapshot
--    is reported as exactly that — unrecorded — and never as "any two
--    therapies".
-- ---------------------------------------------------------------------
create or replace function public.customer_therapy_voucher_rights(
  p_customer_id uuid, p_as_of date default null)
returns table(
  reward_voucher_id uuid, voucher_id uuid, voucher_name text,
  status text, units integer, sessions_total integer, sessions_used integer,
  sessions_remaining integer, issued_at timestamptz, valid_until date,
  is_expired boolean, is_usable boolean, rights_recorded boolean,
  applied_retrospectively boolean, summary_text text, definition_snapshot jsonb)
language sql stable set search_path = public as $function$
  select rv.id, rv.voucher_id, v.name,
         rv.status,
         coalesce(i.units, rv.quantity),
         coalesce(i.sessions_total, 0),
         coalesce(i.sessions_used, 0),
         -- A revoked or wholly redeemed voucher has nothing left regardless of
         -- the count, which is the only signal that currently reduces it.
         case when rv.status <> 'held' then 0
              else greatest(coalesce(i.sessions_total, 0) - coalesce(i.sessions_used, 0), 0) end,
         rv.issued_at, i.valid_until,
         (i.valid_until is not null and i.valid_until < coalesce(p_as_of, current_date)),
         (rv.status = 'held'
          and i.id is not null
          and coalesce(i.sessions_total, 0) > coalesce(i.sessions_used, 0)
          and (i.valid_until is null or i.valid_until >= coalesce(p_as_of, current_date))),
         (i.id is not null),
         coalesce(i.applied_retrospectively, false),
         case when i.id is null
              then 'No therapy-service rights recorded for this voucher.'
              else i.summary_text end,
         i.definition_snapshot
    from public.customer_reward_vouchers rv
    join public.vouchers v on v.id = rv.voucher_id
    left join public.therapy_voucher_issues i on i.reward_voucher_id = rv.id
   where rv.customer_id = p_customer_id
   order by rv.issued_at desc, rv.id
$function$;

/**
 * Which services can this held voucher still be used for?
 *
 * Answers from the snapshot's components: a fixed component offers its one
 * service, a choice component offers all of its eligible services. Reported per
 * component so "one Power Recharge, then one of two" stays legible instead of
 * collapsing into a single list.
 */
create or replace function public.therapy_voucher_eligible_services(p_reward_voucher_id uuid)
returns table(sort_order integer, component_kind text, quantity integer,
              label text, service_id uuid, service_code text, service_name text)
language sql stable set search_path = public as $function$
  select (c->>'sort_order')::integer, c->>'component_kind', (c->>'quantity')::integer,
         c->>'label', (s->>'service_id')::uuid, s->>'service_code', s->>'name'
    from public.therapy_voucher_issues i
    cross join lateral jsonb_array_elements(i.definition_snapshot->'components') c
    cross join lateral jsonb_array_elements(c->'services') s
   where i.reward_voucher_id = p_reward_voucher_id
   order by (c->>'sort_order')::integer, s->>'name'
$function$;

-- Vouchers that were issued without recorded rights. The list a Manager works
-- through, rather than a silent assumption made on their behalf.
create or replace function public.therapy_vouchers_without_rights()
returns table(reward_voucher_id uuid, customer_id uuid, voucher_id uuid,
              voucher_name text, quantity integer, issued_at timestamptz,
              has_definition_now boolean)
language sql stable security definer set search_path = public as $function$
  select rv.id, rv.customer_id, rv.voucher_id, v.name, rv.quantity, rv.issued_at,
         (d.voucher_id is not null)
    from public.customer_reward_vouchers rv
    join public.vouchers v on v.id = rv.voucher_id
    left join public.therapy_voucher_issues i on i.reward_voucher_id = rv.id
    left join public.therapy_voucher_definitions d on d.voucher_id = rv.voucher_id
   where i.id is null and rv.status = 'held'
   order by rv.issued_at desc
$function$;

-- ---------------------------------------------------------------------
-- 7. Access.
-- ---------------------------------------------------------------------
alter table public.therapy_voucher_definitions enable row level security;
alter table public.therapy_voucher_components enable row level security;
alter table public.therapy_voucher_component_services enable row level security;
alter table public.therapy_voucher_issues enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='therapy_voucher_definitions' and policyname='read voucher definitions') then
    create policy "read voucher definitions" on public.therapy_voucher_definitions
      for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='therapy_voucher_components' and policyname='read voucher components') then
    create policy "read voucher components" on public.therapy_voucher_components
      for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='therapy_voucher_component_services' and policyname='read voucher component services') then
    create policy "read voucher component services" on public.therapy_voucher_component_services
      for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='therapy_voucher_issues' and policyname='read voucher issues') then
    create policy "read voucher issues" on public.therapy_voucher_issues
      for select to authenticated using (true);
  end if;
end $$;

grant execute on function public.therapy_voucher_definition(uuid) to authenticated;
grant execute on function public.therapy_voucher_summary_text(jsonb) to authenticated;
grant execute on function public.upsert_therapy_voucher_definition(uuid,jsonb,text,integer,text,integer,numeric,text) to authenticated;
grant execute on function public.clear_therapy_voucher_definition(uuid) to authenticated;
grant execute on function public.apply_therapy_voucher_rights_retrospectively(uuid) to authenticated;
grant execute on function public.customer_therapy_voucher_rights(uuid,date) to authenticated;
grant execute on function public.therapy_voucher_eligible_services(uuid) to authenticated;
grant execute on function public.therapy_vouchers_without_rights() to authenticated;
