begin;
-- =====================================================================
-- VOUCHERS SOLD INSIDE A PROMOTION NEED AN OWNER
--
-- A voucher LINE has always issued properly: issue_sold_vouchers_for_invoice
-- writes a customer_reward_vouchers row and an invoice_benefit_values row
-- recording who holds the units and what was paid for them.
--
-- A voucher delivered inside a PROMOTION got neither. The stock left the store
-- -- deduct_invoice_stock works from the line's captured components -- but
-- nothing recorded who now holds it. Two consequences, both reproducible on a
-- promotion sold seconds ago rather than on old data:
--
--   * invoice_untracked_voucher() reports the line as untracked, because the
--     evidence it looks for genuinely is not there, so correct_invoice refuses
--     any customer or store change on the invoice. That is the reported
--     "Review the original issued voucher units..." refusal. The guard is
--     right; the issuance was incomplete.
--   * The customer holds vouchers the system cannot name, so the refund and
--     transfer paths that work from these records cannot see them either.
--
-- This issues the missing ownership record. It does NOT touch stock: the units
-- already left the store at sale, and deducting again would take them twice.
-- Nothing is minted; what was sold is simply written down.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. What a promotion line actually sold, from the line's OWN snapshot.
--
-- invoice_stock_components is captured when the line is created, from the
-- promotion as it stood THEN. Reading the promotion's contents today would
-- describe a package that may since have changed, which is exactly what must
-- not happen, so this only ever reads the line's captured components.
-- ---------------------------------------------------------------------
create or replace function public.invoice_promotion_voucher_components(p_invoice_id uuid)
returns table (invoice_item_id uuid, voucher_id uuid, units integer)
language sql stable security definer set search_path to 'public' as $$
  select sc.invoice_item_id, sc.item_id, sum(sc.quantity)::int
    from public.invoice_stock_components sc
    join public.invoice_items it on it.id = sc.invoice_item_id
   where it.invoice_id = p_invoice_id
     and it.line_kind = 'promotion'
     and sc.kind = 'voucher'
   group by sc.invoice_item_id, sc.item_id
  having sum(sc.quantity) > 0
$$;
grant execute on function public.invoice_promotion_voucher_components(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Recording the owner.
--
-- Idempotent per (line, voucher): paying twice, a replayed trigger, a
-- reopening or a retried reconciliation must not hand over a second set.
--
-- The paid value is split across the line's voucher components by UNITS, not
-- by catalogue price. A price split would read today's prices for a sale made
-- months ago; units come from the line's own snapshot and cannot drift.
-- ---------------------------------------------------------------------
create or replace function public.issue_promotion_vouchers_for_invoice(p_invoice_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; r record; rv uuid; n integer := 0;
        v_line_value numeric; v_line_units integer; v_paid numeric;
begin
  select * into i from public.invoices where id = p_invoice_id;
  if not found or i.customer_id is null then return 0; end if;

  for r in select * from public.invoice_promotion_voucher_components(p_invoice_id) loop
    -- Already recorded for this line and this voucher: nothing to do.
    if exists (select 1 from public.customer_reward_vouchers
                where source_type = 'invoice_promotion_voucher'
                  and source_id = r.invoice_item_id
                  and voucher_id = r.voucher_id) then continue; end if;

    select coalesce(sum(units),0) into v_line_units
      from public.invoice_promotion_voucher_components(p_invoice_id)
     where invoice_item_id = r.invoice_item_id;
    v_line_value := coalesce(public.invoice_discounted_line_value(r.invoice_item_id), 0);
    v_paid := case when v_line_units > 0
                   then round(v_line_value * r.units::numeric / v_line_units, 2) else 0 end;

    insert into public.customer_reward_vouchers
      (customer_id, voucher_id, store_id, quantity, status, issued_by,
       source_type, source_id, notes)
    values (i.customer_id, r.voucher_id, i.store_id, r.units, 'held', auth.uid(),
            'invoice_promotion_voucher', r.invoice_item_id,
            'Included in a promotion on invoice ' || coalesce(i.invoice_no,'(no number)'))
    returning id into rv;

    insert into public.invoice_benefit_values
      (invoice_id, invoice_item_id, reward_voucher_id, paid_value, granted_value, evidence, created_by)
    values (p_invoice_id, r.invoice_item_id, rv, v_paid, r.units,
            'Promotion component recorded from the invoice line''s captured contents', auth.uid());

    n := n + 1;
  end loop;

  if n > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'promotion_voucher_units_issued', null,
      jsonb_build_object('records', n), 'invoices', null, i.store_id);
  end if;
  return n;
end $$;
revoke all on function public.issue_promotion_vouchers_for_invoice(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. The same trigger that issues sold vouchers now issues these too.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.issue_sold_vouchers_for_invoice(uuid)'::regprocedure) into f;
  if position('issue_promotion_vouchers_for_invoice' in f) = 0 then
    f := replace(f,
      ' if n>0 then',
      ' -- Vouchers delivered inside a promotion are issued by the same event.
 n := n + public.issue_promotion_vouchers_for_invoice(p_invoice_id);

 if n>0 then');
    if position('issue_promotion_vouchers_for_invoice' in f) = 0 then
      raise exception 'issue_sold_vouchers_for_invoice does not match what 315 expects — align it by hand'; end if;
    execute f;
    raise notice 'issue_sold_vouchers_for_invoice now also records promotion voucher ownership';
  end if;
end $do$;

-- ---------------------------------------------------------------------
-- 4. Invoices sold before this, for review.
--
-- Read-only. It reports what each paid promotion line sold and whether an
-- owner is recorded, so a person can see the scale before anything is written.
-- ---------------------------------------------------------------------
create or replace function public.promotion_voucher_ownership_review(p_invoice_id uuid default null)
returns table (
  invoice_id uuid, invoice_no text, business_date date, customer_name text, store_id uuid,
  invoice_item_id uuid, promotion_name text, voucher_name text, units integer,
  owner_recorded boolean, status text)
language sql stable security definer set search_path to 'public' as $$
  select i.id, i.invoice_no, i.business_date, c.full_name, i.store_id,
         comp.invoice_item_id, pr.name, v.name, comp.units,
         exists (select 1 from public.customer_reward_vouchers crv
                  where crv.source_type = 'invoice_promotion_voucher'
                    and crv.source_id = comp.invoice_item_id
                    and crv.voucher_id = comp.voucher_id) as owner_recorded,
         case
           when i.status in ('cancelled','refunded') then 'reversed_invoice'
           when exists (select 1 from public.customer_reward_vouchers crv
                         where crv.source_type = 'invoice_promotion_voucher'
                           and crv.source_id = comp.invoice_item_id
                           and crv.voucher_id = comp.voucher_id) then 'recorded'
           when not exists (select 1 from public.invoice_payments p where p.invoice_id = i.id)
             then 'unpaid_nothing_issued'
           else 'needs_owner_record'
         end as status
    from public.invoices i
    join public.customers c on c.id = i.customer_id
    cross join lateral public.invoice_promotion_voucher_components(i.id) comp
    join public.invoice_items it on it.id = comp.invoice_item_id
    left join public.promotions pr on pr.id = it.promotion_id
    join public.vouchers v on v.id = comp.voucher_id
   where i.deleted_at is null
     and (p_invoice_id is null or i.id = p_invoice_id)
     and public.user_has_store_access(i.store_id)
   order by i.business_date nulls last, i.invoice_no, v.name
$$;
grant execute on function public.promotion_voucher_ownership_review(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Writing those owner records. Owner or Manager, audited, idempotent.
--
-- This records ownership of units that ALREADY left the store. It mints no
-- voucher and restores no stock -- the evidence establishes neither is needed.
-- An unpaid invoice is skipped: nothing was issued for it.
-- ---------------------------------------------------------------------
create or replace function public.reconcile_promotion_voucher_ownership(
  p_invoice_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; v_n integer;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can reconcile voucher ownership' using errcode='42501'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Give a reason; it is kept with the reconciliation'; end if;

  select * into i from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(i.store_id) then
    raise exception 'No access to this store'; end if;
  if not exists (select 1 from public.invoice_payments where invoice_id = i.id) then
    raise exception 'Nothing was issued for an unpaid invoice, so there is no ownership to record'; end if;
  if i.status in ('cancelled','refunded') then
    raise exception 'This invoice was %; recording ownership on it would contradict the reversal', i.status; end if;

  v_n := public.issue_promotion_vouchers_for_invoice(p_invoice_id);

  perform public.write_audit_ex('invoices', p_invoice_id, 'promotion_voucher_ownership_reconciled',
    null, jsonb_build_object('records', v_n, 'reason', trim(p_reason)),
    'invoices', trim(p_reason), i.store_id);

  return jsonb_build_object('success', true, 'records_created', v_n,
    'still_untracked', public.invoice_untracked_voucher(p_invoice_id));
end $$;
grant execute on function public.reconcile_promotion_voucher_ownership(uuid,text) to authenticated;

notify pgrst,'reload schema';
commit;
