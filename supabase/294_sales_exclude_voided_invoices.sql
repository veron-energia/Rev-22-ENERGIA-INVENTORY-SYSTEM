begin;
-- =====================================================================
-- A CANCELLED INVOICE WAS STILL A SALE
--
-- Reported: "refunded, cancelled and not paid invoices are in the sale."
-- Measured, one invoice per status, in an isolated database:
--
--   unpaid            0.00   already excluded -- it has no payments at all
--   partially_paid  150.00   correct
--   cancelled       100.00   COUNTED, AND COUNTED FOREVER
--   refunded          0.00 net, but 100.00 left sitting in the original
--                            month and -100.00 dropped into the refund month
--
-- So one of the three named statuses was genuinely wrong, and a second was
-- wrong about WHEN rather than about how much.
--
-- The cause is that invoice_sales_ledger() never looked at the invoice's
-- status. It counted every receipt whose invoice was not deleted. Cancelling
-- an invoice deliberately leaves its payments in place -- cancel_invoice_recorded
-- returns 'Payments remain recorded. Record any actual refund separately.' --
-- so cancelling removed the invoice from the business without removing its
-- money from the sales figure.
--
-- The rule already existed elsewhere in the same dashboard:
--   dashboard_summary.discount_today -> status in ('paid','partially_paid','completed_foc')
-- The sales ledger was the outlier, which is why one tile disagreed with another.
--
-- WHICH STATUSES COUNT
--
--   paid, partially_paid      money received and kept
--   completed_foc             a zero-value invoice; contributes 0 either way,
--                             kept so a receipt recorded against one is never
--                             silently dropped, and matches discount_today
--   cancellation_requested    a REQUEST, not a decision. The money is still
--   refund_requested          held. resolve_invoice_action() puts the invoice
--                             straight back to paid/partially_paid when the
--                             request is rejected, so excluding these would
--                             make a month's sales fall when staff click
--                             "request cancellation" and rise again on refusal.
--
--   draft, unpaid             nothing received; already contributed 0
--   cancelled                 voided; its receipts stop counting
--   refunded                  fully returned; the receipt and the refund both
--                             stop counting, so a cross-month refund no longer
--                             leaves a sale in one month and a bare negative in
--                             another. Net across all time is unchanged (0).
--
-- A PARTIAL refund does not reach this rule: such an invoice keeps status
-- 'paid'. Verified -- 400 received, 100 refunded, status 'paid', 300 counted.
-- Money genuinely kept after a partial refund is never dropped.
--
-- THE ONE CONSEQUENCE TO BE AWARE OF
--
-- If an invoice was cancelled while the business kept the customer's money and
-- no refund was ever recorded, that money now leaves Sales. Sales will be lower
-- than cash banked by exactly that amount. That is the intended reading -- a
-- cancelled invoice is not a sale -- but it is a real difference, so
-- report_cancelled_retained_receipts() below lists every such invoice.
--
-- No payment, refund, invoice, commission or payout is created, altered or
-- deleted. Reporting only, and reversible by restoring the two functions.
--
-- Requires 292 and 293. Idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- One definition of "this invoice's money is a sale", in one place.
-- ---------------------------------------------------------------------
create or replace function public.invoice_counts_as_sale(p_status text)
returns boolean language sql immutable as $$
 select coalesce(p_status,'') in
   ('paid','partially_paid','completed_foc','cancellation_requested','refund_requested')
$$;
comment on function public.invoice_counts_as_sale(text) is
 'Whether an invoice in this status contributes to Sales. Excludes draft/unpaid (nothing received), cancelled (voided) and refunded (fully returned).';
grant execute on function public.invoice_counts_as_sale(text) to authenticated;

-- ---------------------------------------------------------------------
-- The shared sales basis. Every sales figure in the system reads this:
-- sales_between, invoice_net_sales_between, dashboard_sales,
-- dashboard_sales_by_store, dashboard_sales_series, dashboard_summary and
-- report_sales_reconciliation. Filtering here filters all seven at once.
-- ---------------------------------------------------------------------
do $do$
declare f text; v_old text; v_new text; v_hits int;
begin
 select pg_get_functiondef('public.invoice_sales_ledger()'::regprocedure) into f;
 if position('invoice_counts_as_sale' in f)>0 then
  raise notice 'invoice_sales_ledger already excludes voided invoices'; return; end if;

 -- Both branches -- receipts and refunds -- are anchored on the same test, so
 -- a cancelled invoice loses its receipt AND its refund and cannot go negative.
 v_old:='i.deleted_at is null';
 v_new:='i.deleted_at is null and public.invoice_counts_as_sale(i.status::text)';
 v_hits:=(length(f)-length(replace(f,v_old,'')))/length(v_old);
 if v_hits<>2 then
  raise exception 'Expected the receipt and refund branches of invoice_sales_ledger to test deleted_at, found % — align them by hand', v_hits;
 end if;
 execute replace(f,v_old,v_new);
 raise notice 'sales now count only invoices whose money is a sale';
end $do$;

-- ---------------------------------------------------------------------
-- items_sold and discount_total sit beside the sales figure under the same
-- period selector. 293 put them on the same DATE; they now use the same
-- STATUS, so a cancelled invoice cannot leave its items behind after its
-- money has gone.
-- ---------------------------------------------------------------------
do $do$
declare f text; v_old text; v_new text; v_hits int;
begin
 select pg_get_functiondef('public.dashboard_sales(text,date,date,uuid)'::regprocedure) into f;
 if position('invoice_counts_as_sale' in f)>0 then
  raise notice 'dashboard tiles already share the sales status rule'; return; end if;

 v_old:='and exists(select 1 from public.invoice_payments p where p.invoice_id=i.id)';
 v_new:='and public.invoice_counts_as_sale(i.status::text) and exists(select 1 from public.invoice_payments p where p.invoice_id=i.id)';
 v_hits:=(length(f)-length(replace(f,v_old,'')))/length(v_old);
 if v_hits<>2 then
  raise exception 'Expected items_sold and discount_total to test for payments, found % — align them by hand', v_hits;
 end if;
 f:=replace(f,v_old,v_new);

 -- The stated basis has to match what the numbers now do.
 f:=replace(f,'Actual eligible receipts by the day they were received; refunds by refund date',
              'Actual eligible receipts by the day they were received; refunds by refund date; cancelled and fully refunded invoices excluded');
 execute f;
 raise notice 'items and discounts follow the same status rule as sales';
end $do$;

-- ---------------------------------------------------------------------
-- Money kept on a cancelled invoice, which Sales no longer shows.
--
-- Empty is the expected result: cancelling normally follows a refund, or
-- corrects an invoice that was never really paid. A non-empty result is not a
-- fault in this change -- it is money the business is holding against an
-- invoice it has voided, and each row needs either a recorded refund or the
-- invoice reopening.
-- ---------------------------------------------------------------------
create or replace function public.report_cancelled_retained_receipts(
  p_store_id uuid default null, p_from date default null, p_to date default null)
returns table(invoice_no text, store_id uuid, cancelled_on date, received numeric, refunded numeric, retained numeric)
language sql stable security definer set search_path to 'public' as $$
 select i.invoice_no, i.store_id,
        public.invoice_sales_day(i.id),
        coalesce(rc.received,0), coalesce(rf.refunded,0),
        round(coalesce(rc.received,0)-coalesce(rf.refunded,0),2)
   from public.invoices i
   left join lateral (
     select sum(case when p.entry_kind='correction_reversal' then -p.amount else p.amount end) received
       from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id
      where p.invoice_id=i.id and not coalesce(m.is_wallet_credit,false)) rc on true
   left join lateral (
     select sum(r.amount-coalesce(r.credit_returned,0)) refunded
       from public.invoice_refunds r where r.invoice_id=i.id and r.payment_id is not null) rf on true
  where i.deleted_at is null and i.status='cancelled'
    and public.user_has_store_access(i.store_id)
    and (p_store_id is null or i.store_id=p_store_id)
    and round(coalesce(rc.received,0)-coalesce(rf.refunded,0),2) > 0
    and (p_from is null or public.invoice_sales_day(i.id)>=p_from)
    and (p_to is null or public.invoice_sales_day(i.id)<=p_to)
  order by 6 desc, 1
$$;
grant execute on function public.report_cancelled_retained_receipts(uuid,date,date) to authenticated;

notify pgrst,'reload schema';
commit;
