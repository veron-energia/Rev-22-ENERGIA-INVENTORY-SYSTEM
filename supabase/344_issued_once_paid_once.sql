begin;
-- =====================================================================
-- ISSUED ONCE, PAID ONCE
--
-- Two places where the code says "this cannot happen twice" and only a
-- sequential replay is actually stopped.
--
-- 1. VOUCHER ISSUANCE
--
-- issue_sold_vouchers_for_invoice and issue_promotion_vouchers_for_invoice
-- both guard themselves like this:
--
--     -- Idempotent: paying twice, a replayed trigger or a reopening must not
--     -- hand the customer a second set of units.
--     if exists (select 1 from public.customer_reward_vouchers
--                 where source_type = '...' and source_id = it.id) then continue; end if;
--
-- The read takes no lock and there is no unique index behind it — idx_crv_source
-- is a plain btree. Two settlements of the same invoice at the same instant (a
-- double-tap, a retried request, a reopening racing a payment) both read "not
-- there" and both insert. The customer receives two sets, and two
-- invoice_benefit_values rows follow them.
--
-- This is the failure 298 fixed for approval requests, where four sessions
-- submitting one request id produced four approvals: "Checks in application
-- code cannot fix this; only the database can." The same answer applies here.
--
-- 2. STAFF COMMISSION PAYOUT
--
-- Affiliate commissions are serialized by a trigger that takes an advisory
-- lock on every write to commissions. staff_commissions never got the
-- equivalent, and create_staff_commission_payout reads then writes:
--
--     select coalesce(sum(commission_amount), 0) into v_total     -- no lock
--       from public.staff_commissions where ... payout_id is null ...;
--     insert into public.staff_commission_payouts ...;
--     update public.staff_commissions set status = 'paid', payout_id = ...;
--
-- Two concurrent calls both compute the same total and both insert a payout.
-- The second UPDATE then blocks, and on re-evaluating "payout_id is null"
-- updates nothing — leaving a second payout row carrying a full month's total
-- with no commission attached to it. A payout report reads that as the month
-- paid twice. staff_commission_payouts has no unique constraint to catch it.
--
-- The lock is used rather than a unique index on (staff_id, payout_month)
-- because whether a corrective second payout in one month is legitimate is a
-- business rule, and this migration does not decide it.
-- =====================================================================

-- ---- 1. issued once -------------------------------------------------------
do $$
declare v_dupes int;
begin
  select count(*) into v_dupes from (
    select source_type, source_id, voucher_id
      from public.customer_reward_vouchers
     where source_id is not null
       and source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     group by 1,2,3 having count(*) > 1) d;
  if v_dupes > 0 then
    -- Refuse rather than merge: which of a customer's duplicate voucher units
    -- is the real one is not something a migration may decide.
    raise exception '344: % invoice line(s) already have vouchers issued more than once. Reconcile them before adding the constraint that prevents it.', v_dupes;
  end if;
end $$;

create unique index if not exists customer_reward_vouchers_issued_once
  on public.customer_reward_vouchers (source_type, source_id, voucher_id)
  where source_id is not null
    and source_type in ('invoice_voucher_sale','invoice_promotion_voucher');

-- ---- 2. paid once ---------------------------------------------------------
-- The same mechanism the affiliate side already uses, with its own key so the
-- two do not block each other.
create or replace function public.staff_payout_lock()
returns void language sql security definer set search_path to 'public' as
$$ select pg_advisory_xact_lock(728041903111::bigint) $$;

create or replace function public.staff_commission_write_lock()
returns trigger language plpgsql security definer set search_path to 'public' as
$$ begin perform public.staff_payout_lock(); return null; end $$;

-- PostgreSQL grants EXECUTE on a new function to PUBLIC, and anon inherits
-- that. 339 turned that default into an allowlist, and the rule it leaves
-- behind is that every migration must say who may call what it creates. These
-- two are internal: the trigger function is reached by the trigger, and the
-- lock is called from inside a SECURITY DEFINER function, where nested calls
-- run as the owner. So neither needs a grant to anybody.
revoke all on function public.staff_payout_lock() from public, anon, authenticated;
revoke all on function public.staff_commission_write_lock() from public, anon, authenticated;
grant execute on function public.staff_payout_lock() to service_role;
grant execute on function public.staff_commission_write_lock() to service_role;

drop trigger if exists staff_commission_serialization on public.staff_commissions;
create trigger staff_commission_serialization
  before insert or delete or update on public.staff_commissions
  for each statement execute function public.staff_commission_write_lock();

-- The payout function must hold that lock BEFORE it reads the total, or the
-- read and the allocation are not one atomic unit and two callers still agree
-- on a stale figure.
do $$
declare
  v_oid oid; v_src text; v_new text;
  v_anchor constant text := '  if not public.is_owner_or_manager() then raise exception ''Only Owner or Manager can mark staff commission paid''; end if;';
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_staff_commission_payout';
  if v_oid is null then
    raise notice '344: create_staff_commission_payout is not installed here; nothing to anchor';
    return;
  end if;

  v_src := pg_get_functiondef(v_oid);
  if v_src ~ 'staff_payout_lock' then
    raise notice '344: create_staff_commission_payout already takes the payout lock';
    return;
  end if;
  if position(v_anchor in v_src) = 0 then
    raise exception '344: create_staff_commission_payout no longer opens the way this migration expects; add the lock by hand';
  end if;

  v_new := replace(v_src, v_anchor,
    v_anchor || E'\n' ||
    '  -- One payout at a time: the total below and the allocation that follows' || E'\n' ||
    '  -- must be one atomic unit, or two callers read the same figure and each' || E'\n' ||
    '  -- writes a payout for the whole month.' || E'\n' ||
    '  perform public.staff_payout_lock();');
  execute v_new;
  raise notice '344: create_staff_commission_payout now takes the payout lock before reading the total';
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.staff_commissions'::regclass
                    and tgname = 'staff_commission_serialization') then
    raise exception '344: staff_commissions is still written without serialization';
  end if;
  if not exists (select 1 from pg_indexes
                  where schemaname='public' and indexname='customer_reward_vouchers_issued_once') then
    raise exception '344: nothing stops a voucher being issued twice for one invoice line';
  end if;
  -- And this migration's own new functions did not become endpoints, which is
  -- the trap 339 documents and which this migration fell into on first write.
  if has_function_privilege('anon', 'public.staff_payout_lock()', 'execute')
     or has_function_privilege('anon', 'public.staff_commission_write_lock()', 'execute') then
    raise exception '344: the lock functions this migration created are callable without signing in';
  end if;

  raise notice '344: an invoice line can issue its vouchers once, and staff commission payouts are serialized';
end $$;

notify pgrst, 'reload schema';
commit;
