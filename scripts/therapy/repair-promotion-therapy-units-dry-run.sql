-- Dry run of the promotion therapy repair (scripts/therapy/repair-promotion-
-- therapy-units.sql, which goes with 417). It changes nothing: it only
-- reads. Run it before the repair, as the database owner.
--
-- Every row must say ok = true before the repair is run (or done = true
-- after it). The repair itself re-checks the same conditions and refuses
-- if anything moved.

select e.entitlement_no, i.invoice_no, i.status as invoice_status, e.status as unit_status,
       e.invoice_item_id is null as detached,
       public.therapy_unit_consumed(e.id) as used,
       e.voucher_entitlement_id is not null as has_vouchers,
       case e.entitlement_no when 'UTP-0000002' then 'cancelled' else 'refunded' end as becomes,
       e.status = case e.entitlement_no when 'UTP-0000002' then 'cancelled' else 'refunded' end as done,
       case e.entitlement_no
         when 'UTP-0000002' then i.status = 'paid' and e.status = 'pending_activation' and e.invoice_item_id is null
                                 and not public.therapy_unit_consumed(e.id) and e.voucher_entitlement_id is null
                                 -- the line's own unit is still there to keep
                                 and exists (select 1 from public.purchased_therapy_entitlements k
                                              join public.invoice_items ii on ii.id = k.invoice_item_id
                                             where k.invoice_id = i.id and k.entitlement_no = 'UTP-0000003'
                                               and k.status = 'pending_activation' and ii.line_kind = 'promotion')
                                 -- and the line grants exactly one
                                 and coalesce((select sum(d.qty) from public.invoice_therapy_entitlements_due(i.id) d), 0) = 1
         else i.status = 'refunded' and e.status = 'pending_activation' and e.invoice_item_id is not null
              and not public.therapy_unit_consumed(e.id) and e.voucher_entitlement_id is null
       end as ok
  from public.purchased_therapy_entitlements e
  join public.invoices i on i.id = e.invoice_id
 where (e.entitlement_no, i.invoice_no) in (('UTP-0000006', 'INV-2026-0160'), ('UTP-0000012', 'INV-2026-0304'),
                                            ('UTP-0000002', 'INV-2026-0086'))
 order by 1;
