begin;
-- =====================================================================
-- REASSIGNING AN INVOICE MOVES THE BENEFITS THAT CAME WITH IT
--
-- correct_invoice already moved purchased therapy to the new customer when the
-- invoice was reassigned, and already refused when that therapy had been
-- consumed. Vouchers and credit were left behind: the invoice changed hands
-- and the benefits stayed with the previous customer, who had not bought them.
--
-- Unused benefits now follow the invoice. Anything already used, claimed,
-- spent or committed does NOT move silently -- the correction is refused and
-- names what is in the way, so it goes through transfer_invoice_unused_benefit,
-- the existing Owner/Manager, reasoned, request-id-protected path that records
-- the resolution. Nothing is reset, no deadline moves, no history is rewritten.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. What this invoice's benefits are, and whether they can still move.
--
-- Read-only. correct_invoice uses it to decide, and the screen uses it to say
-- what a reassignment would do before anybody confirms.
-- ---------------------------------------------------------------------
create or replace function public.invoice_transferable_benefits(p_invoice_id uuid)
returns table (
  kind text, record_id uuid, description text, units numeric,
  movable boolean, blocking boolean, blocked_reason text)
language sql stable security definer set search_path to 'public' as $$
  -- Three states, not two. A benefit is either still wholly unused (it moves
  -- with the invoice), wholly consumed (there is nothing to move and nothing
  -- to strand, so the usage simply stays where it happened), or PARTLY used --
  -- the only genuinely ambiguous case, where a remainder would move while the
  -- history stayed behind. Only that last one stops the correction.
  select 'voucher', crv.id,
         v.name || ' × ' || crv.quantity, crv.quantity::numeric,
         crv.status = 'held' and crv.redeemed_at is null,
         false,
         case when crv.status <> 'held' or crv.redeemed_at is not null
              then 'Already ' || coalesce(nullif(crv.status,''),'used')
                   || '; it stays with the original customer' end
    from public.customer_reward_vouchers crv
    join public.vouchers v on v.id = crv.voucher_id
   where crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and crv.source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
  union all
  select 'credit', l.id,
         initcap(l.category) || ' credit ' || l.remaining_amount::text,
         l.remaining_amount,
         l.remaining_amount = l.original_amount and l.status = 'active',
         -- Partly spent: some left, some gone.
         l.remaining_amount > 0 and l.remaining_amount < l.original_amount,
         case when l.remaining_amount = 0 then 'Fully spent; it stays with the original customer'
              when l.remaining_amount < l.original_amount then 'Partly spent'
              when l.status <> 'active' then 'Not active' end
    from public.customer_credit_lots l
   where l.source_record_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
      or l.source_record_id in (select package_id from public.credit_package_sales where invoice_id = p_invoice_id)
  union all
  select 'voucher_allowance', e.id,
         e.package_name || ' — ' || coalesce(e.voucher_qty,0) || ' voucher(s)',
         coalesce(e.voucher_qty,0)::numeric,
         public.entitlement_claimed_qty(e.id) = 0 and e.status <> 'cancelled',
         public.entitlement_claimed_qty(e.id) > 0
           and public.entitlement_claimed_qty(e.id) < coalesce(e.voucher_qty,0),
         case when public.entitlement_claimed_qty(e.id) >= coalesce(e.voucher_qty,0)
                   and coalesce(e.voucher_qty,0) > 0
                then 'Fully claimed; it stays with the original customer'
              when public.entitlement_claimed_qty(e.id) > 0 then 'Partly claimed'
              when e.status = 'cancelled' then 'Cancelled' end
    from public.therapy_entitlements e
   where e.claim_source_invoice_id = p_invoice_id
  union all
  select 'therapy_unit', p.id,
         p.package_name || ' — ' || coalesce(p.status,''), 1,
         p.status in ('pending_activation','scheduled'),
         false,
         case when p.status not in ('pending_activation','scheduled')
              then 'Therapy is ' || p.status end
    from public.purchased_therapy_entitlements p
   where p.invoice_id = p_invoice_id
$$;
grant execute on function public.invoice_transferable_benefits(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Moving them, as part of the same transaction as the correction.
--
-- Only the records this invoice's own lines produced. A customer's unrelated
-- balances are never touched, because everything here is keyed by this
-- invoice's items.
-- ---------------------------------------------------------------------
create or replace function public.move_invoice_benefits_to_customer(
  p_invoice_id uuid, p_customer_id uuid, p_store_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_blocked text; v_v int := 0; v_c int := 0; v_a int := 0; v_wallet uuid;
        r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
begin
  -- Anything committed stops the whole move rather than half of it.
  select string_agg(description || ' (' || blocked_reason || ')', '; ')
    into v_blocked
    from public.invoice_transferable_benefits(p_invoice_id)
   where blocking;
  if v_blocked is not null then
    raise exception 'These benefits have already been used and cannot move with the invoice: %. Resolve each one through the benefit transfer review before reassigning.', v_blocked
      using errcode='P0001'; end if;

  -- Vouchers: the holder changes, the source, deadline and history do not.
  update public.customer_reward_vouchers
     set customer_id = p_customer_id, store_id = p_store_id
   where source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
     and status = 'held' and redeemed_at is null;
  get diagnostics v_v = row_count;

  -- Credit is never repointed. A posted lot is immutable -- its customer,
  -- category, original amount, source and store cannot be edited, and the
  -- ledger behind it is append-only. Moving it is therefore the operation
  -- transfer_invoice_unused_benefit already performs: draw the original down to
  -- nothing, record that decrease, issue a replacement to the new customer
  -- carrying the category, restrictions and original purchase date, and record
  -- that grant. Bonus credit cannot become unrestricted paid credit this way.
  v_wallet := public.ensure_customer_wallet(p_customer_id);
  for r_lot in
    select l.* from public.customer_credit_lots l
     where (l.source_record_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
         or l.source_record_id in (select package_id from public.credit_package_sales where invoice_id = p_invoice_id))
       and l.remaining_amount = l.original_amount
       and l.remaining_amount > 0
       and l.status = 'active'
     for update
  loop
    v_new_lot := gen_random_uuid();

    update public.customer_credit_lots
       set remaining_amount = 0, updated_at = now()
     where id = r_lot.id;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (r_lot.wallet_id, r_lot.customer_id, 'adjust_decrease', r_lot.category,
            r_lot.remaining_amount, r_lot.id, 'invoice_reassignment_out', p_invoice_id,
            r_lot.store_id, p_reason, auth.uid(), auth.uid());

    insert into public.customer_credit_lots
    select (jsonb_populate_record(null::public.customer_credit_lots, to_jsonb(r_lot) || jsonb_build_object(
      'id', v_new_lot, 'wallet_id', v_wallet, 'customer_id', p_customer_id, 'store_id', p_store_id,
      'original_amount', r_lot.remaining_amount, 'remaining_amount', r_lot.remaining_amount,
      'source_type', 'invoice_reassignment', 'source_record_id', p_invoice_id,
      'reference_no', null, 'reason', p_reason, 'reversal_of_lot_id', null,
      'created_by', auth.uid(), 'approved_by', auth.uid(),
      'created_at', now(), 'updated_at', now()))).*;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (v_wallet, p_customer_id, 'grant', r_lot.category, r_lot.remaining_amount,
            v_new_lot, 'invoice_reassignment_in', p_invoice_id, p_store_id,
            p_reason, auth.uid(), auth.uid());

    v_c := v_c + 1;
  end loop;

  -- Unclaimed voucher allowances.
  update public.therapy_entitlements
     set customer_id = p_customer_id, store_id = p_store_id
   where claim_source_invoice_id = p_invoice_id
     and status <> 'cancelled'
     and public.entitlement_claimed_qty(id) = 0;
  get diagnostics v_a = row_count;

  if v_v + v_c + v_a > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_benefits_followed_reassignment',
      null, jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a,
                               'to_customer', p_customer_id, 'reason', p_reason),
      'invoices', p_reason, p_store_id);
  end if;

  return jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a);
end $$;
revoke all on function public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. The correction calls it wherever it already moved therapy.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('move_invoice_benefits_to_customer' in f) = 0 then
    f := replace(f,
      ' if (n.customer_id,n.store_id) is distinct from (i.customer_id,i.store_id) then
   update public.purchased_therapy_entitlements set customer_id=n.customer_id,store_id=n.store_id,updated_at=now()
    where invoice_id=i.id and status in (''pending_activation'',''scheduled'');
 end if;',
      ' if (n.customer_id,n.store_id) is distinct from (i.customer_id,i.store_id) then
   update public.purchased_therapy_entitlements set customer_id=n.customer_id,store_id=n.store_id,updated_at=now()
    where invoice_id=i.id and status in (''pending_activation'',''scheduled'');
   -- The vouchers, credit and allowances this invoice produced follow it. The
   -- call refuses the whole correction if any of them has been used.
   perform public.move_invoice_benefits_to_customer(i.id,n.customer_id,n.store_id,
     coalesce(p_reason,''Invoice reassigned''));
 end if;');
    if position('move_invoice_benefits_to_customer' in f) = 0 then
      raise exception 'correct_invoice does not match what 316 expects — align it by hand'; end if;
    execute f;
    raise notice 'correct_invoice now moves unused benefits with the invoice';
  end if;
end $do$;

notify pgrst,'reload schema';
commit;
