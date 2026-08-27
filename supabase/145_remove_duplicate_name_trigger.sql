-- =====================================================================
-- ENERGIA — MY NAME TRIGGER WAS A DUPLICATE
--
-- Migration 144 added a BEFORE trigger on customers, customer_name_parts, to
-- keep first_name/last_name and full_name consistent.
--
-- That work was already being done. trg_sync_person_name() has existed since
-- migration 92 and is attached to BOTH customers and health_surveys, with the
-- same rule: parts supplied, the whole follows; only a whole supplied, split it.
--
-- So customers carried two BEFORE triggers doing the same job. They agree, so
-- the outcome is right, but two triggers computing the same column is exactly
-- the sort of thing that makes a later change behave unpredictably — and it
-- doubles the work on every customer write.
--
-- I should have looked for an existing trigger before adding one. Mine goes;
-- the original stays.
--
-- The backfill in 144 was still worth doing and is untouched.
--
-- Additive and idempotent.
-- =====================================================================

do $$
begin
  if exists (
    select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where c.relname = 'customers' and t.tgname = 'sync_customer_name'
       and not t.tgisinternal
  ) then
    drop trigger if exists customer_name_parts on public.customers;
    drop function if exists public.trg_customer_name_parts();
    raise notice 'Removed the duplicate name trigger — sync_customer_name already does this';
  else
    -- The original is missing, so mine is doing real work. Keep it.
    raise notice 'sync_customer_name is not present — keeping customer_name_parts';
  end if;
end $$;

-- Whichever survives, a customer must end up with both the parts and the whole.
do $$
declare v_n integer;
begin
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where c.relname = 'customers' and not t.tgisinternal
     and t.tgname in ('sync_customer_name', 'customer_name_parts');
  if v_n = 0 then
    raise exception 'No name trigger on customers — the parts and full name could drift apart';
  end if;
  raise notice 'Confirmed: exactly % name trigger(s) on customers', v_n;
end $$;

notify pgrst, 'reload schema';
