-- =====================================================================
-- ENERGIA — "APPLY TO ALL UNPAID" DESTROYED COMMISSION IT DID NOT REPLACE
--
-- reearn_invoice_staff_commission() reverses every unpaid row FIRST, and only
-- afterwards works out whether it can re-earn anything:
--
--     update public.staff_commissions set status = 'reversed' ...   <-- line 61
--     ...
--     if coalesce(v_rate, 0) <= 0 then return ...;                  -- no rate
--     if v_n = 0 then return ...;                                   -- no staff
--     if v_pool <= 0 then return ...;                               -- nothing owed
--     if v_share <= 0 then return ...;                              -- rounds to zero
--
-- Four ways out, all AFTER the rows have already been cleared. Any invoice that
-- takes one of them loses its unpaid commission and gets nothing back.
--
-- That is why pressing the button repeatedly makes the total fall: each run,
-- any invoice that has drifted into one of those branches is stripped. The
-- amount can only ever go down, never recover, and no error is shown because
-- each of those returns is a "success" with a note.
--
-- The store having no active commission staff is the most likely trigger — a
-- staff member leaving, or being unassigned, silently deletes the unpaid
-- commission on every past invoice for that store the next time anyone rebases.
--
-- THE FIX: work out what will be earned BEFORE touching anything. If the
-- invoice cannot produce a new set of rows, the existing ones are left exactly
-- as they are.
--
-- Additive and idempotent.
-- =====================================================================

set check_function_bodies = off;

do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reearn_invoice_staff_commission';
  if v_def is null then raise exception 'reearn_invoice_staff_commission not found'; end if;
  if position('nothing is reversed until' in v_def) > 0 then
    raise notice 'the rebase already checks before reversing'; return;
  end if;

  -- Move the reversal to AFTER every check. The block below replaces the
  -- reversal with a marker, then puts it back once the share is known good.
  v_new := replace(v_def,
    '  update public.staff_commissions
     set status = ''reversed'', reversed_at = now(),
         reversal_reason = p_reason
   where invoice_id = p_invoice_id
     and status = ''earned''
     and payout_id is null;
  get diagnostics v_reversed = row_count;',
    '  -- Deliberately NOT reversing yet: nothing is reversed until we know a
  -- replacement can actually be created. Clearing first meant an invoice that
  -- fell out at any of the checks below lost its commission for good.
  v_reversed := 0;');

  v_new := replace(v_new,
    '  v_share := round(v_pool / v_n, 2);
  if v_share <= 0 then
    return jsonb_build_object(''reversed'', v_reversed, ''earned'', 0, ''note'', ''share rounds to zero'');
  end if;',
    '  v_share := round(v_pool / v_n, 2);
  if v_share <= 0 then
    return jsonb_build_object(''reversed'', 0, ''earned'', 0, ''note'', ''share rounds to zero — left untouched'');
  end if;

  -- Everything checked. Now it is safe to clear the old rows, because a new
  -- set is about to replace them in the same statement.
  update public.staff_commissions
     set status = ''reversed'', reversed_at = now(),
         reversal_reason = p_reason
   where invoice_id = p_invoice_id
     and status = ''earned''
     and payout_id is null;
  get diagnostics v_reversed = row_count;');

  if position('nothing is reversed until' in v_new) = 0
     or position('Everything checked. Now it is safe' in v_new) = 0 then
    raise exception 'Could not make the rebase check before reversing';
  end if;
  execute v_new;
  raise notice 'the rebase no longer clears commission it cannot replace';
end $patch$;

-- ---------------------------------------------------------------------
-- Show what an earlier run may already have destroyed: invoices that are paid,
-- have staff, but hold no earned commission and a reversal with the rebase's
-- own reason. These are candidates for having been stripped.
-- ---------------------------------------------------------------------
create or replace function public.report_rebase_stripped_invoices()
returns table(invoice_id uuid, invoice_no text, store_name text,
              reversed_amount numeric, reversed_at timestamptz, active_staff integer)
language sql stable security definer set search_path to 'public' as $function$
  select i.id, i.invoice_no, s.name,
         round(sum(sc.commission_amount), 2),
         max(sc.reversed_at),
         (select count(*)::integer from public.store_commission_staff(i.store_id))
    from public.staff_commissions sc
    join public.invoices i on i.id = sc.invoice_id
    join public.stores s on s.id = i.store_id
   where sc.status = 'reversed'
     and sc.payout_id is null
     and i.deleted_at is null
     and not exists (select 1 from public.staff_commissions x
                      where x.invoice_id = i.id and x.status = 'earned')
   group by i.id, i.invoice_no, s.name
   order by 4 desc
$function$;

do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reearn_invoice_staff_commission';
  if v_src is null or position('nothing is reversed until' in v_src) = 0 then
    raise exception 'The rebase still reverses before checking — the total would keep falling';
  end if;
  raise notice 'Confirmed: commission is only cleared when a replacement follows';
end $$;

-- ---------------------------------------------------------------------
-- THE TABLE ALSO GROWS WITHOUT LIMIT.
--
-- Every rebase reverses the existing rows (which remain, as history) and
-- inserts new ones. Press the button five times on 400 invoices with two staff
-- and the table goes from 800 rows to 4,000, none of it new information — just
-- four rounds of superseded reversals.
--
-- That growth is what made the page under-report: it read the first 1,000 rows
-- only. The page is now paginated, but the growth is worth curbing at source.
--
-- A reversal that was itself created by a rebase, was never paid, and has since
-- been superseded by another rebase of the same invoice carries nothing that
-- the surviving rows do not. Those are removed. A reversal from a genuine
-- correction or refund is kept, as is anything ever attached to a payout.
-- ---------------------------------------------------------------------
create or replace function public.prune_superseded_rebase_reversals()
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_n integer;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can tidy commission history';
  end if;

  with superseded as (
    select sc.id
      from public.staff_commissions sc
     where sc.status = 'reversed'
       and sc.payout_id is null
       -- Created by a rebase, not by a correction or refund.
       and coalesce(sc.reversal_reason, '') ilike '%rebase%'
       -- And the invoice has since been re-earned, so this row is superseded.
       and exists (select 1 from public.staff_commissions x
                    where x.invoice_id = sc.invoice_id
                      and x.status = 'earned'
                      and x.created_at > sc.reversed_at)
  )
  delete from public.staff_commissions d
   using superseded s where d.id = s.id;
  get diagnostics v_n = row_count;

  return jsonb_build_object('removed', v_n,
    'note', 'Superseded rebase reversals only. Payouts, corrections and refunds untouched.');
end $function$;

notify pgrst, 'reload schema';
