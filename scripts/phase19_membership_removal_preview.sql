-- =====================================================================
-- PHASE 19 — MEMBERSHIP REMOVAL **PREVIEW** (READ ONLY)
--
-- Run this BEFORE migration 68 and export the results.
-- It writes nothing. It reports exactly what migration 68 would delete,
-- reverse and restore, plus the real-world amounts that a migration
-- CANNOT undo (money already collected, commission already paid out).
--
-- Safe to run any number of times. If it errors because the Membership
-- tables no longer exist, migration 68 has already been applied.
-- =====================================================================

-- ── 1. SUMMARY ───────────────────────────────────────────────────────
with recursive
seed as (
  select distinct i.id
    from public.invoices i
   where exists (select 1 from public.invoice_items ii
                  where ii.invoice_id = i.id and ii.line_kind = 'membership')
      or exists (select 1 from public.customer_memberships m where m.invoice_id = i.id)
),
edges as (
  -- Dependent invoices created FROM a membership invoice.
  select i.topup_of_invoice_id as parent, i.id as child
    from public.invoices i where i.topup_of_invoice_id is not null
  union all
  select r.invoice_id, r.topup_invoice_id
    from public.invoice_refunds r where r.topup_invoice_id is not null
  union all
  select e.original_invoice_id, e.exchange_invoice_id
    from public.product_exchanges e where e.exchange_invoice_id is not null
),
graph as (
  select id from seed
  union
  select e.child from edges e join graph g on e.parent = g.id
),
inv as (select distinct id from graph where id is not null),
mixed as (
  select i.id from public.invoices i join inv on inv.id = i.id
   where exists (select 1 from public.invoice_items ii where ii.invoice_id = i.id and ii.line_kind = 'membership')
     and exists (select 1 from public.invoice_items ii where ii.invoice_id = i.id and ii.line_kind <> 'membership')
),
-- Net product stock still deducted because of these invoices.
mv as (
  select m.product_id,
         coalesce(m.from_store_id, m.to_store_id) as store_id,
         sum(case when m.movement_type in ('store_sale','exchange_replacement_out') then m.quantity
                  when m.movement_type in ('invoice_cancel_return','invoice_refund_return','exchange_return_in') then -m.quantity
                  else 0 end) as net_out
    from public.stock_movements m join inv on inv.id = m.invoice_id
   group by 1,2
),
-- Voucher stock consumed by these invoices (direct lines + promotion picks).
vch as (
  select ii.voucher_id, i.store_id, sum(ii.quantity) as qty
    from public.invoice_items ii
    join public.invoices i on i.id = ii.invoice_id
    join inv on inv.id = i.id
   where ii.line_kind = 'voucher' and ii.voucher_id is not null
     and i.status in ('paid','partially_paid','completed_foc')
   group by 1,2
  union all
  select ps.voucher_id, i.store_id, sum(ps.quantity)
    from public.invoice_promotion_selections ps
    join public.invoice_items ii on ii.id = ps.invoice_item_id
    join public.invoices i on i.id = ii.invoice_id
    join inv on inv.id = i.id
   where ps.voucher_id is not null and i.status in ('paid','partially_paid','completed_foc')
   group by 1,2
)
select * from (
  select 1 as ord, 'Membership invoices to delete' as item,
         (select count(*) from inv)::text as count,
         (select coalesce(sum(total_amount),0) from public.invoices i join inv on inv.id=i.id)::text as amount
  union all select 2, '…of which MIXED (membership + other lines)', (select count(*) from mixed)::text,
         (select coalesce(sum(total_amount),0) from public.invoices i join mixed on mixed.id=i.id)::text
  union all select 3, 'Invoice items to delete',
         (select count(*) from public.invoice_items ii join inv on inv.id=ii.invoice_id)::text, ''
  union all select 4, 'Membership records to delete', (select count(*) from public.customer_memberships)::text, ''
  union all select 5, 'Member IDs to delete', (select count(*) from public.member_ids)::text, ''
  union all select 6, 'Member ID reservations to delete', (select count(*) from public.member_id_reservations)::text, ''
  union all select 7, 'Membership plans to delete', (select count(*) from public.membership_plans)::text, ''
  union all select 8, 'Store membership prices to delete', (select count(*) from public.membership_plan_store_prices)::text, ''
  union all select 9, 'PAYMENTS to delete (⚠ real money collected)',
         (select count(*) from public.invoice_payments p join inv on inv.id=p.invoice_id)::text,
         (select coalesce(sum(p.amount),0) from public.invoice_payments p join inv on inv.id=p.invoice_id)::text
  union all select 10, 'Refund records to delete',
         (select count(*) from public.invoice_refunds r join inv on inv.id=r.invoice_id)::text,
         (select coalesce(sum(r.amount),0) from public.invoice_refunds r join inv on inv.id=r.invoice_id)::text
  union all select 11, 'Product stock lines to restore',
         (select count(*) from mv where net_out > 0)::text,
         (select coalesce(sum(net_out),0) from mv where net_out > 0)::text
  union all select 12, 'Voucher stock lines to restore',
         (select count(distinct (voucher_id, store_id)) from vch)::text,
         (select coalesce(sum(qty),0) from vch)::text
  union all select 13, 'Therapy entitlements to delete',
         (select count(*) from public.purchased_therapy_entitlements e join inv on inv.id=e.invoice_id)::text, ''
  union all select 14, '…of which ACTIVATED (⚠ service already used)',
         (select count(*) from public.purchased_therapy_entitlements e join inv on inv.id=e.invoice_id
           where e.status not in ('pending_activation','cancelled'))::text, ''
  union all select 15, 'Rentals affected (rentals are not invoice-linked)', '0', ''
  union all select 16, 'Exchanges to reverse',
         (select count(*) from public.product_exchanges e
           where e.original_invoice_id in (select id from inv) or e.exchange_invoice_id in (select id from inv))::text, ''
  union all select 17, 'Staff commissions to delete',
         (select count(*) from public.staff_commissions c join inv on inv.id=c.invoice_id)::text,
         (select coalesce(sum(c.commission_amount),0) from public.staff_commissions c join inv on inv.id=c.invoice_id)::text
  union all select 18, 'Affiliate commissions (Tier 1/2) to delete',
         (select count(*) from public.commissions c join inv on inv.id=c.invoice_id)::text,
         (select coalesce(sum(c.commission_amount),0) from public.commissions c join inv on inv.id=c.invoice_id)::text
  union all select 19, '⚠ Commission ALREADY PAID OUT (needs correction entry)',
         (select count(*) from public.commissions c join inv on inv.id=c.invoice_id
            join public.commission_payouts po on po.id = c.payout_id where po.status = 'paid')::text,
         (select coalesce(sum(c.commission_amount),0) from public.commissions c join inv on inv.id=c.invoice_id
            join public.commission_payouts po on po.id = c.payout_id where po.status = 'paid')::text
  union all select 20, '⚠ Staff commission ALREADY PAID OUT',
         (select count(*) from public.staff_commissions c join inv on inv.id=c.invoice_id
            join public.staff_commission_payouts po on po.id = c.payout_id where po.status = 'paid')::text,
         (select coalesce(sum(c.commission_amount),0) from public.staff_commissions c join inv on inv.id=c.invoice_id
            join public.staff_commission_payouts po on po.id = c.payout_id where po.status = 'paid')::text
  union all select 21, 'Payout batches needing recalculation',
         (select count(distinct c.payout_id) from public.commissions c join inv on inv.id=c.invoice_id where c.payout_id is not null)::text, ''
  union all select 22, 'Affiliates inactive ONLY because of Membership',
         (select count(*) from public.customer_affiliates a
           where a.deleted_at is null and not coalesce(a.manually_suspended,false)
             and a.status in ('inactive_membership_expired','inactive_missing_member_id','inactive_no_membership'))::text, ''
  union all select 23, 'Audit rows to delete (membership-related)',
         (select count(*) from public.audit_logs l
           where l.table_name in ('customer_memberships','membership_plans','membership_plan_store_prices','member_ids','member_id_reservations')
              or l.action ilike '%membership%' or l.action ilike '%member_id%' or l.module = 'membership')::text, ''
  union all select 24, 'Blocked commissions to be reworded (kept BLOCKED)',
         (select count(*) from public.commissions where status = 'blocked')::text, ''
) t order by ord;

-- ── 2. UNKNOWN DEPENDENCY CHECK ──────────────────────────────────────
-- Migration 68 must NOT run if this returns any row: it means something
-- references a membership invoice in a way this migration does not handle.
with recursive
seed as (
  select distinct i.id from public.invoices i
   where exists (select 1 from public.invoice_items ii where ii.invoice_id = i.id and ii.line_kind = 'membership')
      or exists (select 1 from public.customer_memberships m where m.invoice_id = i.id)),
edges as (
  select i.topup_of_invoice_id, i.id from public.invoices i where i.topup_of_invoice_id is not null
  union all select r.invoice_id, r.topup_invoice_id from public.invoice_refunds r where r.topup_invoice_id is not null
  union all select e.original_invoice_id, e.exchange_invoice_id from public.product_exchanges e where e.exchange_invoice_id is not null),
graph as (select id from seed union select e.id from edges e join graph g on e.topup_of_invoice_id = g.id),
inv as (select distinct id from graph where id is not null)
select c.conrelid::regclass::text as referencing_table, c.conname as foreign_key,
       'Referencing table is not handled by migration 68' as problem
  from pg_constraint c
 where c.contype = 'f'
   and c.confrelid = 'public.invoices'::regclass
   and c.conrelid::regclass::text not in (
     'invoice_items','invoice_payments','invoice_refunds','invoice_revisions','invoice_service_staff',
     'stock_movements','voucher_redemptions','commissions','staff_commissions','affiliate_commissions',
     'purchased_therapy_entitlements','therapy_entitlement_invoices','product_exchanges','invoices',
     'member_id_reservations','customer_memberships','therapy_qualification_topups','invoice_promotion_selections')
   and exists (select 1 from inv);

-- ── 3. MANUAL FINANCIAL RECONCILIATION (money a migration cannot undo) ─
with recursive
seed as (
  select distinct i.id from public.invoices i
   where exists (select 1 from public.invoice_items ii where ii.invoice_id = i.id and ii.line_kind = 'membership')
      or exists (select 1 from public.customer_memberships m where m.invoice_id = i.id)),
edges as (
  select i.topup_of_invoice_id, i.id from public.invoices i where i.topup_of_invoice_id is not null
  union all select r.invoice_id, r.topup_invoice_id from public.invoice_refunds r where r.topup_invoice_id is not null
  union all select e.original_invoice_id, e.exchange_invoice_id from public.product_exchanges e where e.exchange_invoice_id is not null),
graph as (select id from seed union select e.id from edges e join graph g on e.topup_of_invoice_id = g.id),
inv as (select distinct id from graph where id is not null)
select 'customer_payment' as kind, i.invoice_no as reference, c.full_name as party,
       s.name as store, sum(p.amount) as amount,
       'Money collected from the customer; the invoice is being deleted' as note
  from public.invoice_payments p
  join public.invoices i on i.id = p.invoice_id
  join inv on inv.id = i.id
  left join public.customers c on c.id = i.customer_id
  left join public.stores s on s.id = i.store_id
 group by i.invoice_no, c.full_name, s.name
union all
select 'affiliate_commission_paid', i.invoice_no, c.full_name, null,
       sum(cm.commission_amount), 'Tier commission already paid out; correction entry required'
  from public.commissions cm
  join inv on inv.id = cm.invoice_id
  join public.invoices i on i.id = cm.invoice_id
  join public.commission_payouts po on po.id = cm.payout_id and po.status = 'paid'
  left join public.customers c on c.id = cm.referrer_customer_id
 group by i.invoice_no, c.full_name
union all
select 'staff_commission_paid', i.invoice_no, pr.full_name, null,
       sum(sc.commission_amount), 'Staff commission already paid out; correction entry required'
  from public.staff_commissions sc
  join inv on inv.id = sc.invoice_id
  join public.invoices i on i.id = sc.invoice_id
  join public.staff_commission_payouts po on po.id = sc.payout_id and po.status = 'paid'
  left join public.profiles pr on pr.id = sc.staff_id
 group by i.invoice_no, pr.full_name
union all
select 'therapy_already_used', i.invoice_no, c.full_name, null, 0,
       'Therapy entitlement was activated before removal; service was consumed'
  from public.purchased_therapy_entitlements e
  join inv on inv.id = e.invoice_id
  join public.invoices i on i.id = e.invoice_id
  left join public.customers c on c.id = i.customer_id
 where e.status not in ('pending_activation','cancelled')
union all
select 'voucher_already_redeemed', i.invoice_no, c.full_name, null, vr.discount_applied,
       'Voucher from a deleted invoice was already redeemed; stock cannot be un-used'
  from public.voucher_redemptions vr
  join inv on inv.id = vr.invoice_id
  join public.invoices i on i.id = vr.invoice_id
  left join public.customers c on c.id = vr.customer_id
 order by 1, 2;
