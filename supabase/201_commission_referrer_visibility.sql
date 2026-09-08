-- =====================================================================
-- 201_commission_referrer_visibility.sql
--
-- A referrer who has been deleted still shows on the Commissions page as an
-- unpaid row with no name — just "—" and an amount, with a Mark Paid button
-- next to it. You cannot see who you are about to pay.
--
-- Why it happens, in three steps:
--
--   1. commissions.referrer_customer_id is NOT NULL and references customers,
--      so the referrer always exists as a row.
--   2. Deleting a customer is a soft delete: delete_customer() sets deleted_at
--      and leaves the row (migration 139). Commission rows are untouched, so the
--      money stays owed.
--   3. The customers read policy is `using (deleted_at is null)`, so from the
--      browser that row becomes invisible — to every query, including the
--      by-id lookup the page uses to fill in names outside the first 1000
--      customers. The name resolves to nothing and renders as "—".
--
-- referrer_list() hides them too (it joins `and c.deleted_at is null`), so the
-- Referrers tab omits the person entirely while their unpaid total still counts
-- towards the headline figure.
--
-- This migration adds one narrow, read-only way to resolve those names. It does
-- not change the customers policy — deleted customers stay hidden everywhere
-- else, which is the point of the soft delete.
--
-- What it deliberately does NOT do: stop you deleting a referrer who is still
-- owed money. delete_customer() already refuses when there is wallet credit, an
-- unused therapy entitlement or an unpaid invoice; an unpaid commission is
-- arguably the same kind of debt. That is a behaviour change with a real
-- trade-off, so it is left as a separate decision rather than bundled in here.
-- =====================================================================

-- Names for referrers that appear on commission rows, including soft-deleted
-- ones. Restricted to the same audience that can read commissions in the first
-- place, so this reveals nothing to anyone who could not already see the row.
create or replace function public.commission_referrer_names(p_ids uuid[])
returns table (id uuid, full_name text, phone text, deleted_at timestamptz)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  -- Matches the commissions read policy: `using (public.is_manager_or_above())`.
  if not public.is_manager_or_above() then
    raise exception 'Only a Manager or above can view commission referrers';
  end if;

  return query
    select c.id, c.full_name, c.phone, c.deleted_at
      from public.customers c
     where c.id = any(coalesce(p_ids, '{}'::uuid[]));
end
$function$;

comment on function public.commission_referrer_names(uuid[]) is
  'Resolves referrer names for commission rows, including soft-deleted customers. Manager or above only.';

revoke all on function public.commission_referrer_names(uuid[]) from public, anon;
grant execute on function public.commission_referrer_names(uuid[]) to authenticated;

-- ---------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'commission_referrer_names') then
    raise exception 'migration 201: commission_referrer_names missing';
  end if;
  if has_function_privilege('anon', 'public.commission_referrer_names(uuid[])', 'execute') then
    raise exception 'migration 201: anon can execute commission_referrer_names';
  end if;
  if not has_function_privilege('authenticated', 'public.commission_referrer_names(uuid[])', 'execute') then
    raise exception 'migration 201: authenticated cannot execute commission_referrer_names';
  end if;
end $$;
