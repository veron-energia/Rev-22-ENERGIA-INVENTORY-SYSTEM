-- =====================================================================
-- ENERGIA — STAFF ASSIGNED TO SEVERAL STORES
--
-- user_store_assignments has always allowed a staff member several stores
-- (unique on user_id + store_id), and user_has_store_access() already grants
-- access to ANY assigned store. Only the UI helper narrowed it:
-- my_assigned_store_id() returns the first assignment with `limit 1`, so the
-- invoice form locked staff to one store however many they were assigned.
--
-- This adds a plural helper. The singular one is kept and unchanged so nothing
-- calling it breaks; it now simply means "the default store to preselect".
--
-- Additive and idempotent. Run AFTER 95.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Every store the signed-in user may raise an invoice for.
--
-- Owners, Admins and Managers are not assignment-scoped, so they get every
-- active store — which matches what user_has_store_access() permits them.
-- ---------------------------------------------------------------------
create or replace function public.my_assigned_stores()
returns table(store_id uuid, store_name text, is_default boolean)
language sql stable security definer set search_path to 'public' as $function$
  with me as (
    select p.id, p.role from public.profiles p
     where p.id = auth.uid() and p.is_active = true
  ),
  scoped as (
    -- Staff: only their assignments, oldest first so the default is stable.
    select s.id, s.name, row_number() over (order by usa.created_at, s.name) as rn
      from public.user_store_assignments usa
      join public.stores s on s.id = usa.store_id
      join me on me.id = usa.user_id
     where me.role not in ('owner','admin','manager')
       and s.deleted_at is null and coalesce(s.is_active, true)
    union all
    -- Owner / Admin / Manager: every active store.
    select s.id, s.name, row_number() over (order by s.name) as rn
      from public.stores s, me
     where me.role in ('owner','admin','manager')
       and s.deleted_at is null and coalesce(s.is_active, true)
  )
  select scoped.id, scoped.name, scoped.rn = 1
    from scoped
   order by scoped.rn
$function$;

-- Kept for existing callers; now documented as "the store to preselect".
comment on function public.my_assigned_store_id() is
  'The staff member''s DEFAULT store (their first assignment). Use my_assigned_stores() when the user may choose among several.';

-- ---------------------------------------------------------------------
-- A staff member with several stores must say WHICH store the stock is for.
-- The chosen store is validated against their own assignments, so the
-- parameter cannot be used to request stock into somebody else's store.
--
-- The old two-argument call still works and keeps its meaning: with no store
-- given, the default assignment is used.
-- ---------------------------------------------------------------------
do $$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_staff_transfer_request';
  if v_def is null then
    raise notice 'create_staff_transfer_request not present — skipping';
    return;
  end if;
  if position('p_store_id' in v_def) > 0 then
    raise notice 'create_staff_transfer_request already accepts a store';
    return;
  end if;

  -- Add the parameter and swap the store resolution for a validated one.
  v_def := replace(v_def,
    'create_staff_transfer_request(p_lines jsonb, p_note text DEFAULT NULL::text)',
    'create_staff_transfer_request(p_lines jsonb, p_note text DEFAULT NULL::text, p_store_id uuid DEFAULT NULL::uuid)');

  v_def := replace(v_def,
    '  v_store_id := public.my_assigned_store_id();',
    '  -- A specific store may be requested, but only one this user is assigned to.'
    || chr(10) ||
    '  if p_store_id is not null then' || chr(10) ||
    '    if not exists (select 1 from public.user_store_assignments usa' || chr(10) ||
    '                    where usa.user_id = auth.uid() and usa.store_id = p_store_id) then' || chr(10) ||
    '      raise exception ''You are not assigned to that store.'';' || chr(10) ||
    '    end if;' || chr(10) ||
    '    v_store_id := p_store_id;' || chr(10) ||
    '  else' || chr(10) ||
    '    v_store_id := public.my_assigned_store_id();' || chr(10) ||
    '  end if;');

  if position('p_store_id' in v_def) = 0 then
    raise exception 'Could not add the store parameter to create_staff_transfer_request';
  end if;
  execute v_def;
  -- The two-argument version must go, or every existing call is ambiguous.
  drop function if exists public.create_staff_transfer_request(jsonb, text);
  raise notice 'create_staff_transfer_request now accepts an optional assigned store';
end $$;

notify pgrst, 'reload schema';
