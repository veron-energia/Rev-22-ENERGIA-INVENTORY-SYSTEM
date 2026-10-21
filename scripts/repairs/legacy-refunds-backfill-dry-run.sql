-- Dry run of scripts/repairs/legacy-refunds-backfill.sql: read only, one
-- SELECT, changes nothing. Run it first, with the same rights, and run the
-- repair only if every row has ok = true.
--
-- One row per payment of the nine invoices the repair writes in (a missing
-- invoice shows as a row with no payment and ok = false):
--   invoice_no, payment         the payment the repair refunds, in full
--   refund_day                  the Singapore day the old request was
--                               approved: the refund's date
--   approver_has_profile        the approver can be named as the refunder
--   status                      must be 'refunded'
--   holds_its_total             paid = total = net received (nothing
--                               refunded yet)
--   refund_rows                 refunds already written (must be 0)
--   refund_requests             refund or cancel requests (must be 1, an
--                               approved old-style refund)
--   plain_receipt               a receipt, not wallet credit, not corrected
--   legacy_therapy_blocking     the customer's unlimited Legacy therapy
--                               from the paid day, activated, scheduled or
--                               expired (must be 0: the invoice's refund
--                               guard refuses otherwise)
--   aff_voucher_blocking        Affiliate reward vouchers from the paid day
--                               already redeemed (must be 0, the same guard)
--   ok                          all of the above hold
--   payments, payments_total    on every row: expected 11 and 8054.47
-- Prints invoice numbers, amounts and counts only, never a name.

with nine(invoice_no) as (
  values ('INV-2026-0028'), ('INV-2026-0047'), ('INV-2026-0110'), ('INV-2026-0132'), ('INV-2026-0140'),
         ('INV-2026-0160'), ('INV-2026-0174'), ('INV-2026-0184'), ('INV-2026-0202')
), inv as (
  select n.invoice_no, i.id, i.status::text as status, i.deleted_at, i.paid_amount, i.total_amount,
         i.customer_id, i.store_id, i.affiliate_snapshot_customer_id,
         (i.paid_at at time zone 'Asia/Singapore')::date as paid_day
    from nine n
    left join public.invoices i on i.invoice_no = n.invoice_no
), req as (
  select a.related_record_id as invoice_id,
         count(*) as refund_requests,
         count(*) filter (where a.request_type = 'invoice_refund' and a.status = 'approved'
                            and a.payload->'plan' is null and a.approved_at is not null) as old_approved,
         max(a.approved_at) filter (where a.request_type = 'invoice_refund' and a.status = 'approved') as approved_at,
         coalesce(bool_or(pr.id is not null) filter (where a.request_type = 'invoice_refund' and a.status = 'approved'),
                  false) as approver_has_profile
    from public.approval_requests a
    left join public.profiles pr on pr.id = a.approved_by
   where a.request_type in ('invoice_refund', 'invoice_cancel')
     and a.related_record_id in (select id from inv where id is not null)
   group by a.related_record_id
), chk as (
  select inv.*,
         coalesce(r.refund_requests, 0) as refund_requests, coalesce(r.old_approved, 0) as old_approved,
         r.approved_at, coalesce(r.approver_has_profile, false) as approver_has_profile,
         (select count(*) from public.invoice_refunds f where f.invoice_id = inv.id) as refund_rows,
         case when inv.id is not null then public.invoice_net_received(inv.id) end as net_received,
         -- The two refusals of assert_legacy_refund_allowed, which the
         -- invoice's refund guard runs when the repair lowers paid_amount.
         case when inv.paid_day is null or inv.customer_id is null or inv.store_id is null then 0
              else (select count(*) from public.therapy_entitlements e
                     where e.qualification_group_id = public.legacy_qualification_group(inv.customer_id, inv.store_id, inv.paid_day)
                       and e.status in ('active', 'scheduled', 'expired')
                       and coalesce(e.entitlement_kind, 'unlimited') = 'unlimited') end as legacy_therapy_blocking,
         case when inv.paid_day is null or inv.affiliate_snapshot_customer_id is null then 0
              else (select count(*) from public.customer_reward_vouchers crv
                      join public.therapy_entitlements e on e.id = crv.entitlement_id
                     where e.earner_kind = 'affiliate'
                       and e.customer_id = inv.affiliate_snapshot_customer_id
                       and e.qualification_group_id =
                           md5('legacy_aff:' || inv.affiliate_snapshot_customer_id::text || ':' || inv.paid_day::text)::uuid
                       and crv.status = 'redeemed') end as aff_voucher_blocking
    from inv
    left join req r on r.invoice_id = inv.id
), pay as (
  select c.*, ip.id as payment_id, ip.amount as payment, ip.created_at as paid_on,
         (ip.id is not null and ip.entry_kind = 'receipt' and not coalesce(m.is_wallet_credit, false)
          and not exists (select 1 from public.invoice_payments k where k.corrects_payment_id = ip.id)) as plain_receipt
    from chk c
    left join public.invoice_payments ip on ip.invoice_id = c.id
    left join public.payment_methods m on m.id = ip.payment_method_id
)
select p.invoice_no,
       p.payment,
       (p.approved_at at time zone 'Asia/Singapore')::date as refund_day,
       p.approver_has_profile,
       p.status,
       coalesce(p.paid_amount = p.total_amount and p.net_received = p.total_amount, false) as holds_its_total,
       p.refund_rows,
       p.refund_requests,
       p.plain_receipt,
       p.legacy_therapy_blocking,
       p.aff_voucher_blocking,
       coalesce(p.id is not null and p.deleted_at is null and p.status = 'refunded'
                and p.paid_amount = p.total_amount and p.net_received = p.total_amount
                and p.refund_rows = 0 and p.refund_requests = 1 and p.old_approved = 1 and p.approver_has_profile
                and p.plain_receipt and p.legacy_therapy_blocking = 0 and p.aff_voucher_blocking = 0, false) as ok,
       count(p.payment_id) over () as payments,
       coalesce(sum(p.payment) over (), 0) as payments_total
  from pay p
 order by p.invoice_no, p.paid_on, p.payment_id;
