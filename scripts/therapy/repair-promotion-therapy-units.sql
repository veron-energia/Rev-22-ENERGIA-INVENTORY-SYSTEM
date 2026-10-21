-- Close three purchased therapy units that should not be open (goes with 417,
-- which rebuilt 363).
--
-- The Owner said yes on 9 Oct 2026 (Q3 = A: "close UTP-0000006, UTP-0000012
-- and the duplicate UTP-0000002"). NOT RUN YET: run it once, after 417, as the
-- database owner (the SQL editor, the MCP execute_sql tool, or psql as
-- postgres). 417 does not need it and does not do it: 417 makes refunds and
-- cancellations close a promotion's therapy from now on; these three were
-- left open before that.
--
-- WHY THIS EXISTS
--
--   A. UTP-0000006 on INV-2026-0160. The invoice was refunded on 1 Sep 2026
--      ("Duplicated Data"; the same customer's INV-2026-0161, same bundle, holds
--      UTP-0000007) through the approval path used before the guided
--      Refund / Cancel. That path returned the stock and set the invoice to
--      refunded, and never looked at therapy: the unit is still
--      pending_activation and can be claimed. It closes as 'refunded', as 417
--      closes an unused unit on a refunded line.
--
--   B. UTP-0000012 on INV-2026-0304, refunded the same way before 417: a
--      promotion line's unit, unused, pending_activation, no vouchers. It
--      closes as 'refunded', as A.
--
--   C. UTP-0000002 on INV-2026-0086. On 27 Aug 2026 the pre-guided "edit a paid
--      invoice" path (Singlet changed to Hat 3XL) replaced the promotion line
--      with a new one. The foreign key set the old unit's invoice_item_id to
--      null, and re-paying the invoice issued UTP-0000003 for the new line. The
--      promotion grants one unit, so the customer holds two. Both are unused
--      and carry the same terms (bought 22 Aug 2026, activate by 22 Aug 2027).
--      UTP-0000002, the detached one, closes as 'cancelled' (issued in error,
--      no money of its own); UTP-0000003 stays, because it is the one every
--      refund, cancellation and correction path can find through the line.
--
--   The paths that left them no longer exist (last used 8 and 9 Sep 2026).
--
-- NOT TOUCHED: money and commission (neither refunded line has any earned
-- commission). INV-2026-0160's S$610 still shows as held until the legacy
-- refunds repair (scripts/repairs/legacy-refunds-backfill.sql) records its
-- refund.
--
-- RUNNING THIS FILE APPLIES THE REPAIR. To see the dry run only, run
-- scripts/therapy/repair-promotion-therapy-units-dry-run.sql first: it
-- changes nothing, and every row must say ok = true.
--
-- SAFETY: this is one DO block, so it is atomic. It locks the three units
-- and refuses unless each is still exactly as found on 9 Oct 2026 (number,
-- invoice, invoice status, unused, no vouchers; C detached, with UTP-0000003
-- still on the promotion line, which grants one unit), or already closed as
-- this closes it (left alone, so a second run changes nothing). It prints
-- numbers only. Test (fixtures only):
-- scripts/therapy/tests/repair-promotion-therapy-units.sql.

-- ── APPLY ─────────────────────────────────────────────────────────────────
-- The 314 trigger withdraws any vouchers (there are none) and writes its own
-- audit row.
do $apply$
declare e record; u text; v_closed int := 0; v_done int := 0; v_path text := current_setting('search_path');
begin
  perform set_config('search_path', 'public', true);
  -- A and B: an unused unit on a refunded invoice's promotion line.
  foreach u in array array['UTP-0000006:INV-2026-0160', 'UTP-0000012:INV-2026-0304'] loop
    select p.*, i.invoice_no, i.status as invoice_status into e
      from public.purchased_therapy_entitlements p join public.invoices i on i.id = p.invoice_id
     where p.entitlement_no = split_part(u, ':', 1) for update of p;
    if not found or e.invoice_no <> split_part(u, ':', 2) or e.invoice_status <> 'refunded' then
      raise exception '% is not on the refunded %; nothing was changed', split_part(u, ':', 1), split_part(u, ':', 2); end if;
    if e.status = 'refunded' then v_done := v_done + 1; continue; end if;
    if e.status <> 'pending_activation' or e.invoice_item_id is null or public.therapy_unit_consumed(e.id)
       or e.voucher_entitlement_id is not null then
      raise exception '% is no longer an unused unit on its line; nothing was changed', e.entitlement_no; end if;
    update public.purchased_therapy_entitlements set status = 'refunded', updated_at = now() where id = e.id;
    perform public.write_audit_ex('purchased_therapy_entitlements', e.id, 'closed_with_invoice',
      jsonb_build_object('status', e.status),
      jsonb_build_object('status', 'refunded', 'repair', 'promotion therapy left open by a refund made before 417'),
      'refunds', e.invoice_no || ' was refunded before a refund closed the therapy a promotion granted (417, the Owner 9 Oct 2026)',
      e.store_id);
    v_closed := v_closed + 1;
  end loop;

  -- C. UTP-0000002: the duplicate an old paid-invoice edit left detached.
  select p.*, i.invoice_no, i.status as invoice_status into e
    from public.purchased_therapy_entitlements p join public.invoices i on i.id = p.invoice_id
   where p.entitlement_no = 'UTP-0000002' for update of p;
  if not found or e.invoice_no <> 'INV-2026-0086' or e.invoice_item_id is not null then
    raise exception 'UTP-0000002 is no longer the detached unit on INV-2026-0086; nothing was changed'; end if;
  if e.status = 'cancelled' then
    v_done := v_done + 1;
  else
    if e.invoice_status <> 'paid' or e.status <> 'pending_activation'
       or public.therapy_unit_consumed(e.id) or e.voucher_entitlement_id is not null then
      raise exception 'UTP-0000002 is no longer an unused unit on the paid INV-2026-0086; nothing was changed'; end if;
    if not exists (select 1 from public.purchased_therapy_entitlements k
                     join public.invoice_items ii on ii.id = k.invoice_item_id
                    where k.invoice_id = e.invoice_id and k.entitlement_no = 'UTP-0000003'
                      and k.status = 'pending_activation' and ii.line_kind = 'promotion')
       or coalesce((select sum(d.qty) from public.invoice_therapy_entitlements_due(e.invoice_id) d), 0) <> 1 then
      raise exception 'INV-2026-0086 no longer holds exactly one unit on its line besides UTP-0000002; nothing was changed'; end if;
    update public.purchased_therapy_entitlements set status = 'cancelled', updated_at = now() where id = e.id;
    perform public.write_audit_ex('purchased_therapy_entitlements', e.id, 'duplicate_unit_cancelled',
      jsonb_build_object('status', e.status, 'invoice_item_id', null),
      jsonb_build_object('status', 'cancelled', 'kept', 'UTP-0000003',
        'repair', 'second unit issued when the paid-invoice edit of 27 Aug 2026 replaced the promotion line'),
      'therapy', 'INV-2026-0086 grants one therapy unit; UTP-0000003 is the one on its line (the Owner, 9 Oct 2026)', e.store_id);
    v_closed := v_closed + 1;
  end if;
  raise notice 'promotion therapy repair: % closed now, % already closed', v_closed, v_done;
  perform set_config('search_path', v_path, true);
end $apply$;
