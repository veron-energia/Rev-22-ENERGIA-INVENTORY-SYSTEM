begin;
-- =====================================================================
-- TWO TABLES THAT WERE NEVER LOCKED
--
-- Every table in public has row-level security except two:
--
--   commission_corrections        (68)   the commission clawback ledger
--   credit_package_progress_lots  (328)  which released paid-credit lot
--                                        belongs to which invoice line
--
-- Neither was ever switched on — there is no "disable row level security"
-- anywhere; the create table statements simply never enabled it. Supabase
-- grants select, insert, update and delete on new public tables to anon and
-- authenticated, so with no RLS these two tables were readable and writable by
-- anyone holding the publishable key that ships inside the browser bundle. No
-- login required.
--
-- What that exposed: commission_corrections holds customer_id, staff_id,
-- payout_id, amount and reason for every clawback. credit_package_progress_lots
-- is what credit_package_released_paid_credit reads to decide how much credit a
-- package has already released, so rewriting it changes how much credit the
-- system believes it owes.
--
-- Nothing legitimate loses access. Neither table is named anywhere in src/.
-- Every database consumer is a SECURITY DEFINER function owned by postgres —
-- credit_package_released_paid_credit, invoice_credit_lot_ids,
-- release_credit_package_paid_credit, repair_credit_package_progress_lots,
-- writeoff_released_credit_on_close — and the table owner is not subject to its
-- own policies, so they are unaffected. commission_corrections is read by no
-- function at all.
--
-- So the correct end state is RLS on with no policy: deny by default, reached
-- only through the definer functions. Fourteen other tables in this schema are
-- already in exactly that state.
-- =====================================================================
alter table public.commission_corrections       enable row level security;
alter table public.credit_package_progress_lots enable row level security;

do $$
declare v_open text := '';
begin
  -- Nothing in public may be left without row-level security.
  select string_agg(c.relname, ', ' order by c.relname) into v_open
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if v_open is not null then
    raise exception '342: still without row-level security: %', v_open;
  end if;

  -- And these two must have no policy: a policy here would be a way in that
  -- the definer functions do not need.
  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and tablename in ('commission_corrections','credit_package_progress_lots')) then
    raise exception '342: a policy was added to a table that should be reachable only through its definer functions';
  end if;

  raise notice '342: commission_corrections and credit_package_progress_lots are now deny-by-default; every table in public has row-level security';
end $$;

commit;
