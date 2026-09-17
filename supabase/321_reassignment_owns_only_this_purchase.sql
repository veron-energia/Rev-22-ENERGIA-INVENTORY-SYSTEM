begin;
-- =====================================================================
-- A REASSIGNMENT MOVES THIS PURCHASE'S CREDIT, AND NOTHING ELSE
--
-- 316 selected an invoice's credit lots partly by:
--
--   l.source_record_id in (select package_id from credit_package_sales
--                           where invoice_id = p_invoice_id)
--
-- A credit package lot is granted with source_record_id = the CATALOGUE
-- package id, not the sale. So that clause matched every lot ever granted from
-- that package, to every customer who had ever bought it. Reassigning one
-- customer's invoice emptied the wallets of strangers who happened to buy the
-- same product:
--
--   before   A=700  B=0     C=700
--   after    A=0    B=1400  C=0        <- C is not on the invoice at all
--
-- Reproduced exactly as reported. The preview said 1400 too, so the screen
-- agreed with the damage rather than catching it.
--
-- A second fault rode along with it. The replacement lot was written with
-- source_type='invoice_reassignment', which credit_lot_policy() does not
-- recognise, so it fell through to 'needs_review' and the transferred credit
-- could buy nothing at all. invoice_credit_transfer_origin() does not follow
-- that source type either, so the chain could not be walked back.
--
-- Ownership is now resolved from the issuance records that name the exact lots,
-- and a transfer keeps the credit's origin intact so it stays the same kind of
-- credit with the same spending rules. Only the holder changes.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Provenance for a transferred lot.
--
-- The replacement keeps its ORIGIN in source_type/source_record_id, because it
-- is still credit from that package -- that is what credit_lot_policy() and
-- credit_package_effective_rules() read. This column records the hop instead,
-- so the invoice it belongs to can still be found afterwards, and after any
-- number of further reassignments.
-- ---------------------------------------------------------------------
alter table public.customer_credit_lots
  add column if not exists reassigned_from_lot_id uuid references public.customer_credit_lots(id);

create index if not exists ccl_reassigned_from_idx
  on public.customer_credit_lots(reassigned_from_lot_id)
  where reassigned_from_lot_id is not null;

comment on column public.customer_credit_lots.reassigned_from_lot_id is
  'The lot this one replaced when its invoice was reassigned. Origin stays in source_type/source_record_id.';

-- ---------------------------------------------------------------------
-- 2. The lots that actually belong to one invoice.
--
-- Named issuance records only. A catalogue package id identifies a product, not
-- a purchase, and is never sufficient. Lots reached by an earlier reassignment
-- of the same invoice are followed through reassigned_from_lot_id.
-- ---------------------------------------------------------------------
create or replace function public.invoice_credit_lot_ids(p_invoice_id uuid)
returns table (lot_id uuid, evidence text)
language sql stable security definer set search_path to 'public' as $$
  with recursive seeded as (
    -- The exact lots the credit package sale issued.
    select s.credit_lot_id as id, 'credit_package_sale.credit_lot_id'::text as ev
      from public.credit_package_sales s
     where s.invoice_id = p_invoice_id and s.credit_lot_id is not null
    union all
    select s.bonus_credit_lot_id, 'credit_package_sale.bonus_credit_lot_id'
      from public.credit_package_sales s
     where s.invoice_id = p_invoice_id and s.bonus_credit_lot_id is not null
    union all
    -- The exact lots the premium bundle sale issued.
    select b.paid_credit_lot_id, 'premium_bundle_sale.paid_credit_lot_id'
      from public.premium_bundle_sales b
     where b.invoice_id = p_invoice_id and b.paid_credit_lot_id is not null
    union all
    select b.bonus_credit_lot_id, 'premium_bundle_sale.bonus_credit_lot_id'
      from public.premium_bundle_sales b
     where b.invoice_id = p_invoice_id and b.bonus_credit_lot_id is not null
    union all
    -- Lots granted directly against one of this invoice's own lines.
    select l.id, 'credit_lot.source_record_id = invoice_item'
      from public.customer_credit_lots l
     where l.source_record_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
  ), walked as (
    select s.id, s.ev, 1 as depth from seeded s
    union all
    -- Whatever those lots became when this invoice was reassigned before.
    select l.id, w.ev || ' → reassigned', w.depth + 1
      from public.customer_credit_lots l
      join walked w on l.reassigned_from_lot_id = w.id
     where w.depth < 12
  )
  select distinct on (id) id, ev from walked where id is not null order by id, depth desc
$$;
grant execute on function public.invoice_credit_lot_ids(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. The preview and the move read the same list.
--
-- They have to: a preview that describes a different set from the one the
-- execution touches is worse than no preview, and that is exactly how 1400
-- came to be shown and then applied.
-- ---------------------------------------------------------------------
-- Dropped first: an older install of this function returns fewer columns, and
-- create-or-replace cannot widen a return type. Dependants are functions, which
-- resolve it by name at call time, so nothing is left dangling.
drop function if exists public.invoice_transferable_benefits(uuid);
create function public.invoice_transferable_benefits(p_invoice_id uuid)
returns table (
  kind text, record_id uuid, description text, units numeric,
  movable boolean, blocking boolean, blocked_reason text)
language sql stable security definer set search_path to 'public' as $$
  -- Three states, not two. A benefit is either still wholly unused (it moves
  -- with the invoice), wholly consumed (there is nothing to move and nothing
  -- to strand, so the usage stays where it happened), or PARTLY used -- the
  -- only genuinely ambiguous case, and the only one that stops the correction.
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
         l.remaining_amount > 0 and l.remaining_amount < l.original_amount,
         case when l.remaining_amount = 0 then 'Fully spent; it stays with the original customer'
              when l.remaining_amount < l.original_amount then 'Partly spent'
              when l.status <> 'active' then 'Not active' end
    from public.customer_credit_lots l
   where l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
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
-- 4. Moving it, with the credit still being what it was.
--
-- The replacement carries the ORIGINAL source_type and source_record_id, so
-- credit_lot_policy() and credit_package_effective_rules() resolve it exactly
-- as they did before the invoice changed hands: paid package credit still buys
-- individual therapy services, bonus still buys products, bundle credit keeps
-- its own behaviour, and a configured per-package rule still applies.
-- reassigned_from_lot_id records the hop.
-- ---------------------------------------------------------------------
create or replace function public.move_invoice_benefits_to_customer(
  p_invoice_id uuid, p_customer_id uuid, p_store_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_blocked text; v_v int := 0; v_c int := 0; v_a int := 0; v_wallet uuid;
        r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
begin
  select string_agg(description || ' (' || blocked_reason || ')', '; ')
    into v_blocked
    from public.invoice_transferable_benefits(p_invoice_id)
   where blocking;
  if v_blocked is not null then
    raise exception 'These benefits have already been used and cannot move with the invoice: %. Resolve each one through the benefit transfer review before reassigning.', v_blocked
      using errcode='P0001'; end if;

  update public.customer_reward_vouchers
     set customer_id = p_customer_id, store_id = p_store_id
   where source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
     and status = 'held' and redeemed_at is null;
  get diagnostics v_v = row_count;

  v_wallet := public.ensure_customer_wallet(p_customer_id);
  for r_lot in
    select l.* from public.customer_credit_lots l
     where l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
       and l.remaining_amount = l.original_amount
       and l.remaining_amount > 0
       and l.status = 'active'
       -- Already the new owner's (a repeated request, or a no-op move).
       and l.customer_id is distinct from p_customer_id
     for update
  loop
    v_new_lot := gen_random_uuid();

    update public.customer_credit_lots
       set remaining_amount = 0, updated_at = now() where id = r_lot.id;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (r_lot.wallet_id, r_lot.customer_id, 'adjust_decrease', r_lot.category,
            r_lot.remaining_amount, r_lot.id, 'invoice_reassignment_out', p_invoice_id,
            r_lot.store_id, p_reason, auth.uid(), auth.uid());

    insert into public.customer_credit_lots
    select (jsonb_populate_record(null::public.customer_credit_lots, to_jsonb(r_lot) || jsonb_build_object(
      'id', v_new_lot, 'wallet_id', v_wallet, 'customer_id', p_customer_id,
      'original_amount', r_lot.remaining_amount, 'remaining_amount', r_lot.remaining_amount,
      -- source_type, source_record_id, usage_restrictions, category, store_id,
      -- effective_date and original_purchase_date are carried unchanged.
      'reassigned_from_lot_id', r_lot.id,
      'reference_no', null, 'reason', p_reason, 'reversal_of_lot_id', null,
      'created_by', auth.uid(), 'approved_by', auth.uid(),
      'created_at', now(), 'updated_at', now()))).*;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (v_wallet, p_customer_id, 'grant', r_lot.category, r_lot.remaining_amount,
            v_new_lot, 'invoice_reassignment_in', p_invoice_id, r_lot.store_id,
            p_reason, auth.uid(), auth.uid());

    v_c := v_c + 1;
  end loop;

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

notify pgrst,'reload schema';
commit;
