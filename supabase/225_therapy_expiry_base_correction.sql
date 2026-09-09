-- =====================================================================
-- ENERGIA — CORRECTION: THIS SYSTEM HAS ONE CALENDAR-MONTH CONVENTION
--
--     function public.membership_expiry(date, integer) does not exist
--
-- Migration 220 introduced therapy_base_expiry() with a 'purchased' branch that
-- calls membership_expiry(), on the strength of migration 53 still calling it.
-- Migration 53 is superseded. Phase 19 DROPPED membership_expiry, and migration
-- 72 exists precisely because activating a purchased therapy then failed with
-- the error above; it replaced the call with therapy_expiry().
--
-- So there are not two conventions here. There is one — therapy_expiry() — and
-- every purchased entitlement in this database had its expiry computed with it.
-- My earlier note claiming a 29-February difference between the two described a
-- migration this database never ran.
--
-- Why the tests did not catch it: the local fixture created membership_expiry by
-- copying it out of migration 45, so the test database had a function production
-- does not. The fixture has been corrected to match what is installed, and it now
-- reproduces this error without this file.
--
-- Nothing recalculates here and no expiry moves: every purchased expiry was
-- already computed with therapy_expiry(), so this makes the code agree with the
-- data rather than changing the data.
--
-- p_convention is kept so migrations 221, 222 and 223 keep working unchanged.
-- It no longer selects anything, and the check at the end of this file asserts
-- that both values agree — if membership_expiry is ever reinstalled, that check
-- fails and this is the function to revisit.
--
-- Additive, idempotent. Run AFTER 220-224.
-- =====================================================================

set check_function_bodies = off;

create or replace function public.therapy_base_expiry(
  p_start date, p_months integer, p_convention text default 'legacy')
returns date language sql stable set search_path = public as $function$
  -- One convention, for both purchased and Legacy entitlements:
  -- start + months - 1 day, inclusive. See the header for why.
  select public.therapy_expiry(p_start, p_months)
$function$;

do $$
declare v_a date; v_b date;
begin
  select public.therapy_base_expiry('2024-02-29', 12, 'legacy'),
         public.therapy_base_expiry('2024-02-29', 12, 'purchased')
    into v_a, v_b;
  if v_a is distinct from v_b then
    raise exception 'therapy_base_expiry still branches on convention (% vs %)', v_a, v_b;
  end if;
  if v_a <> public.therapy_expiry('2024-02-29', 12) then
    raise exception 'therapy_base_expiry no longer agrees with therapy_expiry';
  end if;
  raise notice 'Expiry base: one convention, therapy_expiry(). 2024-02-29 + 12 months = % (inclusive).', v_a;
end $$;
