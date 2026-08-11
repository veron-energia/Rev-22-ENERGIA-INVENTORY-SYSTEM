-- =====================================================================
-- ENERGIA — BILL TO SOURCE LINE · STORE ON A CORRECTION · COMMISSION REBASE
--
-- 1. BILL TO now shows the AFFILIATE if the invoice has one, otherwise the
--    customer's source, otherwise "(-)". Previously it printed
--    "(Referrer, Source)", which showed a dash for affiliate sales because the
--    affiliate lives on the invoice, not on the customer.
--
-- 2. edit_paid_invoice() can move an invoice to a different STORE. That is a
--    real correction (a sale rung up at the wrong till), and it has to move the
--    stock too: returned at the old store, deducted at the new one.
--
-- 3. rebase_staff_commissions() recalculates PAST staff commission onto the
--    store-staff basis introduced in migration 101.
--
--    This one deserves care. It does NOT rewrite history: the original rows are
--    marked reversed and kept, and fresh rows are written. Anything already
--    PAID OUT is left completely alone — a payout that has happened is a fact,
--    not a number to be recalculated. Only unpaid commission is rebased.
--
-- Additive and idempotent. Run AFTER 102.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The Bill To source line.
-- ---------------------------------------------------------------------
create or replace function public.invoice_bill_to_source(p_invoice_id uuid)
returns text language sql stable security definer set search_path to 'public' as $function$
  select coalesce(
    -- An affiliate on the invoice wins: it is the most specific attribution.
    -- invoices.affiliate_id points at customer_affiliates, so the name comes
    -- from the customer behind that affiliate record.
    nullif(trim(public.join_person_name(ac.first_name, ac.last_name)), ''),
    nullif(trim(ac.full_name), ''),
    -- Otherwise how the customer came to us.
    nullif(trim(c.source_label), ''),
    nullif(trim(so.label), ''),
    '-')
  from public.invoices i
  left join public.customer_affiliates ca on ca.id = i.affiliate_id
  left join public.customers ac on ac.id = ca.customer_id
  left join public.customers c on c.id = i.customer_id
  left join public.customer_source_options so on so.id = c.source_option_id
  where i.id = p_invoice_id
$function$;

-- "First Last (Affiliate | Source | -)" for the printed document.
create or replace function public.invoice_bill_to(p_invoice_id uuid)
returns text language sql stable security definer set search_path to 'public' as $function$
  select coalesce(public.join_person_name(c.first_name, c.last_name), c.full_name, '—')
         || ' (' || public.invoice_bill_to_source(p_invoice_id) || ')'
    from public.invoices i
    join public.customers c on c.id = i.customer_id
   where i.id = p_invoice_id
$function$;

-- ---------------------------------------------------------------------
-- 2. A correction may also move the invoice to another store.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'edit_paid_invoice';
  if v_def is null then raise exception 'edit_paid_invoice not found'; end if;
  if position('p_store_id' in v_def) > 0 then
    raise notice 'edit_paid_invoice already accepts a store'; return;
  end if;

  v_new := replace(v_def,
    'p_service_staff uuid[] DEFAULT NULL::uuid[])',
    'p_service_staff uuid[] DEFAULT NULL::uuid[], p_store_id uuid DEFAULT NULL::uuid)');

  -- Stock has to follow the invoice. It is returned to the OLD store before the
  -- move and deducted from the NEW one afterwards, which the existing
  -- restore/deduct pair already does either side of the line rebuild.
  v_new := replace(v_new,
    '  update public.invoices set status = ''unpaid'' where id = p_invoice_id;',
    '  -- Moving store: the stock was returned to the old store just above, and'
    || chr(10) ||
    '  -- will be deducted from the new one below, so the move is safe here.'
    || chr(10) ||
    '  if p_store_id is not null and p_store_id <> v_inv.store_id then'
    || chr(10) ||
    '    if not exists (select 1 from public.stores s where s.id = p_store_id'
    || chr(10) ||
    '                    and s.deleted_at is null) then'
    || chr(10) ||
    '      raise exception ''That store does not exist'';'
    || chr(10) ||
    '    end if;'
    || chr(10) ||
    '    update public.invoices set store_id = p_store_id where id = p_invoice_id;'
    || chr(10) ||
    '    select * into v_inv from public.invoices where id = p_invoice_id;'
    || chr(10) ||
    '  end if;'
    || chr(10) ||
    '  update public.invoices set status = ''unpaid'' where id = p_invoice_id;');

  if position('That store does not exist' in v_new) = 0 then
    raise exception 'Could not add the store move to edit_paid_invoice';
  end if;
  execute v_new;
  drop function if exists public.edit_paid_invoice(uuid, jsonb, text, numeric, uuid[]);
  raise notice 'edit_paid_invoice can now move an invoice between stores';
end $patch$;

-- ---------------------------------------------------------------------
-- 3. Rebase past staff commission onto the store-staff basis.
--
--    Scope is deliberately narrow:
--      * only invoices whose commission is still 'earned' (never paid out);
--      * a date range, so it can be run for one month at a time and checked;
--      * the old rows are reversed and KEPT, never deleted.
--
--    Paid-out commission is untouched. Recalculating money that has already
--    changed hands would misstate what was actually paid.
-- ---------------------------------------------------------------------
create or replace function public.rebase_staff_commissions(
  p_from date default null, p_to date default null, p_dry_run boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv record; v_n integer := 0; v_before numeric := 0; v_after numeric := 0;
  v_skipped integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can rebase commission'; end if;

  for v_inv in
    select distinct sc.invoice_id, sc.store_id
      from public.staff_commissions sc
     where sc.status = 'earned'
       and sc.payout_id is null
       and (p_from is null or sc.invoice_paid_date >= p_from)
       and (p_to   is null or sc.invoice_paid_date <= p_to)
  loop
    -- An invoice with any paid-out commission is left entirely alone, so a
    -- partly-settled month is never half-rewritten.
    if exists (select 1 from public.staff_commissions sc2
                where sc2.invoice_id = v_inv.invoice_id
                  and (sc2.payout_id is not null or sc2.status = 'paid')) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    select coalesce(sum(commission_amount),0) into v_before
      from public.staff_commissions
     where invoice_id = v_inv.invoice_id and status = 'earned';

    if not p_dry_run then
      perform public.reverse_staff_commission(v_inv.invoice_id,
        'Rebased onto the store-staff basis');
      perform public.earn_staff_commission(v_inv.invoice_id);
    end if;

    v_n := v_n + 1;
  end loop;

  if not p_dry_run then
    select coalesce(sum(commission_amount),0) into v_after
      from public.staff_commissions sc
     where sc.status = 'earned' and sc.payout_id is null
       and (p_from is null or sc.invoice_paid_date >= p_from)
       and (p_to   is null or sc.invoice_paid_date <= p_to);

    perform public.write_audit_ex('staff_commissions', null, 'staff_commission_rebased', null,
      jsonb_build_object('invoices', v_n, 'skipped_paid', v_skipped,
        'from', p_from, 'to', p_to), 'commission', null, null);
  end if;

  return jsonb_build_object(
    'dry_run', p_dry_run,
    'invoices_affected', v_n,
    'invoices_skipped_already_paid', v_skipped,
    'unpaid_total_after', case when p_dry_run then null else round(v_after,2) end);
end $function$;

-- What a rebase would do, per staff member, before committing to it.
create or replace function public.preview_staff_commission_rebase(
  p_from date default null, p_to date default null)
returns table(staff_name text, current_unpaid numeric, invoices integer)
language sql stable security definer set search_path to 'public' as $function$
  select p.full_name, round(sum(sc.commission_amount), 2), count(distinct sc.invoice_id)::integer
    from public.staff_commissions sc
    join public.profiles p on p.id = sc.staff_id
   where sc.status = 'earned' and sc.payout_id is null
     and (p_from is null or sc.invoice_paid_date >= p_from)
     and (p_to   is null or sc.invoice_paid_date <= p_to)
   group by p.full_name
   order by sum(sc.commission_amount) desc
$function$;

notify pgrst, 'reload schema';
