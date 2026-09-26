-- Close two purchased therapy units that should not be open (goes with 363).
--
-- PROPOSED, NOT RUN. It changes records on real customers: run it only with
-- the owner's sign-off, after reading the dry run. 363 does not need it and
-- does not do it.
--
-- WHY THIS EXISTS
--
--   A. UTP-0000006 on INV-2026-0160. The invoice was refunded on 1 Sep 2026
--      ("Duplicated Data"; the same customer's INV-2026-0161, same bundle, holds
--      UTP-0000007) through the approval path used before the guided
--      Refund / Cancel. That path returned the stock and set the invoice to
--      refunded, and never looked at therapy: the unit is still
--      pending_activation and can be claimed. It closes as 'refunded', as 363
--      closes an unused unit on a refunded line.
--
--   B. UTP-0000002 on INV-2026-0086. On 27 Aug 2026 the pre-guided "edit a paid
--      invoice" path (Singlet changed to Hat 3XL) replaced the promotion line
--      with a new one. The foreign key set the old unit's invoice_item_id to
--      null, and re-paying the invoice issued UTP-0000003 for the new line. The
--      promotion grants one unit, so the customer holds two. Both are unused
--      and carry the same terms (bought 22 Aug 2026, activate by 22 Aug 2027).
--      UTP-0000002, the detached one, closes as 'cancelled' (issued in error,
--      no money of its own); UTP-0000003 stays, because it is the one every
--      refund, cancellation and correction path can find through the line.
--
--   Neither path exists any more (last used 8 and 9 Sep 2026). But a correction
--   that swaps a promotion for another item still detaches its unit today; see
--   PROMOTION_THERAPY_REFUNDS.md.
--
-- NOT TOUCHED: money. INV-2026-0160 still records S$610 received and nothing
-- returned (paid_amount 610, no invoice_refunds row). Whether that S$610 was
-- ever real is a separate question for the owner.

-- ── STEP 1: DRY RUN — changes nothing ───────────────────────────────────────
-- Every row must say ok = true.
select e.entitlement_no, i.invoice_no, i.status as invoice_status, e.status as unit_status,
       e.invoice_item_id is null as detached,
       public.therapy_unit_consumed(e.id) as used,
       e.voucher_entitlement_id is not null as has_vouchers,
       case e.entitlement_no when 'UTP-0000006' then 'refunded' else 'cancelled' end as becomes,
       case e.entitlement_no
         when 'UTP-0000006' then i.status = 'refunded' and e.status = 'pending_activation'
                                 and not public.therapy_unit_consumed(e.id) and e.voucher_entitlement_id is null
         when 'UTP-0000002' then i.status = 'paid' and e.status = 'pending_activation' and e.invoice_item_id is null
                                 and not public.therapy_unit_consumed(e.id) and e.voucher_entitlement_id is null
                                 -- the line's own unit is still there to keep
                                 and exists (select 1 from public.purchased_therapy_entitlements k
                                              join public.invoice_items ii on ii.id = k.invoice_item_id
                                             where k.invoice_id = i.id and k.entitlement_no = 'UTP-0000003'
                                               and k.status = 'pending_activation' and ii.line_kind = 'promotion')
                                 -- and the line grants exactly one
                                 and coalesce((select sum(d.qty) from public.invoice_therapy_entitlements_due(i.id) d), 0) = 1
       end as ok
  from public.purchased_therapy_entitlements e
  join public.invoices i on i.id = e.invoice_id
 where (e.entitlement_no, i.invoice_no) in (('UTP-0000006','INV-2026-0160'), ('UTP-0000002','INV-2026-0086'))
 order by 1;

-- ── STEP 2: APPLY — only after both dry-run rows say ok = true ──────────────
-- One transaction. It re-checks the same conditions and refuses if anything
-- moved since the dry run. The 314 trigger withdraws any vouchers (there are
-- none) and writes its own audit row. Uncomment to run.
--
-- begin;
-- do $apply$
-- declare e record;
-- begin
--   -- A. UTP-0000006: its invoice was refunded before a refund closed promotion therapy
--   select p.*, i.invoice_no, i.status as invoice_status into e
--     from public.purchased_therapy_entitlements p join public.invoices i on i.id = p.invoice_id
--    where p.entitlement_no = 'UTP-0000006' for update of p;
--   if not found or e.invoice_no <> 'INV-2026-0160' or e.invoice_status <> 'refunded'
--      or e.status <> 'pending_activation' or public.therapy_unit_consumed(e.id)
--      or e.voucher_entitlement_id is not null then
--     raise exception 'UTP-0000006 is no longer an unused unit on the refunded INV-2026-0160; refusing'; end if;
--   update public.purchased_therapy_entitlements set status = 'refunded', updated_at = now() where id = e.id;
--   perform public.write_audit_ex('purchased_therapy_entitlements', e.id, 'closed_with_invoice',
--     jsonb_build_object('status', e.status),
--     jsonb_build_object('status', 'refunded', 'repair', 'promotion therapy left open by the pre-guided refund of 1 Sep 2026'),
--     'refunds', 'INV-2026-0160 was refunded before a refund closed the therapy a promotion granted (363)', e.store_id);
--
--   -- B. UTP-0000002: the duplicate an old paid-invoice edit left detached
--   select p.*, i.invoice_no, i.status as invoice_status into e
--     from public.purchased_therapy_entitlements p join public.invoices i on i.id = p.invoice_id
--    where p.entitlement_no = 'UTP-0000002' for update of p;
--   if not found or e.invoice_no <> 'INV-2026-0086' or e.invoice_status <> 'paid'
--      or e.status <> 'pending_activation' or e.invoice_item_id is not null
--      or public.therapy_unit_consumed(e.id) or e.voucher_entitlement_id is not null then
--     raise exception 'UTP-0000002 is no longer a detached unused unit on INV-2026-0086; refusing'; end if;
--   if not exists (select 1 from public.purchased_therapy_entitlements k
--                    join public.invoice_items ii on ii.id = k.invoice_item_id
--                   where k.invoice_id = e.invoice_id and k.entitlement_no = 'UTP-0000003'
--                     and k.status = 'pending_activation' and ii.line_kind = 'promotion')
--      or coalesce((select sum(d.qty) from public.invoice_therapy_entitlements_due(e.invoice_id) d), 0) <> 1 then
--     raise exception 'INV-2026-0086 no longer holds exactly one unit on its line besides UTP-0000002; refusing'; end if;
--   update public.purchased_therapy_entitlements set status = 'cancelled', updated_at = now() where id = e.id;
--   perform public.write_audit_ex('purchased_therapy_entitlements', e.id, 'duplicate_unit_cancelled',
--     jsonb_build_object('status', e.status, 'invoice_item_id', null),
--     jsonb_build_object('status', 'cancelled', 'kept', 'UTP-0000003',
--       'repair', 'second unit issued when the paid-invoice edit of 27 Aug 2026 replaced the promotion line'),
--     'therapy', 'INV-2026-0086 grants one therapy unit; UTP-0000003 is the one on its line', e.store_id);
--   raise notice 'UTP-0000006 refunded; UTP-0000002 cancelled; UTP-0000003 kept';
-- end $apply$;
-- commit;
