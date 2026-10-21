-- One-off repair: write in the refunds the old Refund button never recorded.
--
-- Audit finding INVOICES-AFTER-12; the Owner's answer of 9 Oct 2026 (Q1 = A):
-- "Write each of the 9 old-way refunds in now, dated the day each was
-- approved, paid back the way the customer paid. Nothing shows as held; the
-- next Xero file gets 9 payment+refund pairs in Aug/Sep that cancel out."
--
-- WHAT IS WRONG
--
--   Nine sales were refunded through the request approved before the guided
--   Refund / Cancel existed (approved 12 Aug to 9 Sep 2026, Singapore). That
--   path set each invoice to refunded and never wrote the refund itself:
--     INV-2026-0028   395.00   one payment
--     INV-2026-0047   610.00   one payment
--     INV-2026-0110  4059.00   one payment
--     INV-2026-0132    61.00   one payment
--     INV-2026-0140    61.00   two payments
--     INV-2026-0160   610.00   one payment
--     INV-2026-0174  1666.67   one payment
--     INV-2026-0184   264.80   two payments
--     INV-2026-0202   327.00   one payment
--   S$8,054.47 in all, eleven payments, none of them wallet credit. Each
--   invoice still shows the whole amount as held (paid_amount = total =
--   invoice_net_received) with S$0 refunded; the list's paid total and the
--   Excel "Net payments held" count it; the Xero export leaves the payments
--   out as legacy_refund_left_out. Dashboard and Reports are right already:
--   a refunded invoice is not a sale.
--
-- WHAT THIS DOES
--
--   For each of the eleven payments, one invoice_refunds row: the payment's
--   amount, against that payment (paid back the way the customer paid), no
--   credit returned, by the Owner or Manager who approved the old request,
--   dated when they approved it (created_at), naming that request
--   (request_id), with the reason "Recorded later: refunded through the old
--   request approved on <day>". Then each invoice's paid_amount becomes what
--   invoice_net_received gives (S$0), as for every refund recorded since,
--   with one audit row per invoice (legacy_refund_recorded). Nothing else:
--   no stock, no credit, no commission (none of the nine has any commission
--   left), no status change.
--   Afterwards each invoice holds S$0 and shows S$X refunded; the Xero
--   export lists each payment and its refund (a credit note dated on the
--   refund's Singapore day), which cancel out.
--
-- SAFETY
--
--   One DO block, so it is atomic: it changes everything or nothing. It
--   refuses unless exactly these nine invoices exist, not deleted, each
--   refunded, holding all it was paid, with no refund row, eleven payments
--   (receipts, none wallet credit, none corrected) totalling S$8,054.47, and
--   each with exactly one approved request from before the guided workflow
--   (no plan) whose approver has a profile, and none blocked by the
--   invoice's legacy refund guard (assert_legacy_refund_allowed: the
--   customer's Legacy therapy from the paid day activated, or an Affiliate
--   reward voucher from that day redeemed). Run a second time it finds the
--   refunds already written as this writes them, says so and changes
--   nothing; anything in between is refused. It prints counts and amounts
--   only, never a name.
--
-- RUN: after 417 (it does not need 417, but goes with it), as the database
-- owner (the SQL editor, the MCP execute_sql tool, or psql as postgres),
-- before the early-November Xero import. NOT RUN YET. Run the dry run
-- first (scripts/repairs/legacy-refunds-backfill-dry-run.sql, read only):
-- run this only if it shows 11 payments, S$8,054.47 and ok on every row.
-- Run it BEFORE the INV-2026-0174 clean-up (Q14; batch B08's
-- scripts/therapy/repair-invoice-0174-test.sql STEP 2). INV-2026-0174 is one
-- of the nine: its refund is written in first, then the clean-up withdraws
-- what that sale issued.
-- Test (fixtures only): scripts/repairs/tests/legacy-refunds-backfill.sql
-- (the dry run too).

do $repair$
declare
  c_invoices constant text[] := array['INV-2026-0028', 'INV-2026-0047', 'INV-2026-0110', 'INV-2026-0132', 'INV-2026-0140',
                                       'INV-2026-0160', 'INV-2026-0174', 'INV-2026-0184', 'INV-2026-0202'];
  c_total constant numeric := 8054.47;
  c_payments constant int := 11;
  c_mark constant text := 'Recorded later: refunded through the old request approved on ';
  v_path text := current_setting('search_path');
  i record; p record; q record; n int; n_rows int := 0; v_sum numeric; v_day text; v_refunds jsonb;
begin
  perform set_config('search_path', 'public', true);

  -- ── Already done? Every payment has its refund, written by this. ─────────
  select count(*), coalesce(sum(r.amount), 0) into n, v_sum
    from public.invoice_refunds r join public.invoices x on x.id = r.invoice_id
   where x.invoice_no = any (c_invoices) and r.reason like c_mark || '%';
  if n = c_payments and v_sum = c_total
     and (select count(*) from public.invoice_refunds r join public.invoices x on x.id = r.invoice_id
           where x.invoice_no = any (c_invoices)) = c_payments
     and not exists (select 1 from public.invoices x where x.invoice_no = any (c_invoices)
                      and (x.paid_amount <> 0 or public.invoice_net_received(x.id) <> 0)) then
    raise notice 'legacy refunds: already recorded (% refunds, S$%); nothing changed', n, to_char(v_sum, 'FM999999990.00');
    perform set_config('search_path', v_path, true);
    return;
  end if;

  -- ── Guards: nothing changes unless all pass ─────────────────────────────
  if (select count(*) from public.invoices x where x.invoice_no = any (c_invoices)) <> 9 then
    raise exception 'legacy refunds: the nine invoices are not all there, or a number is used twice; nothing was changed'; end if;
  for i in select x.* from public.invoices x where x.invoice_no = any (c_invoices) order by x.invoice_no for update loop
    if i.deleted_at is not null or i.status::text <> 'refunded' then
      raise exception 'legacy refunds: % is no longer a refunded invoice; nothing was changed', i.invoice_no; end if;
    if exists (select 1 from public.invoice_refunds r where r.invoice_id = i.id) then
      raise exception 'legacy refunds: % already has a refund recorded; nothing was changed', i.invoice_no; end if;
    if i.paid_amount <> i.total_amount or public.invoice_net_received(i.id) <> i.total_amount then
      raise exception 'legacy refunds: % no longer holds exactly its total; nothing was changed', i.invoice_no; end if;
    if exists (select 1 from public.invoice_payments ip
                 left join public.payment_methods m on m.id = ip.payment_method_id
                where ip.invoice_id = i.id
                  and (ip.entry_kind <> 'receipt' or coalesce(m.is_wallet_credit, false)
                       or exists (select 1 from public.invoice_payments k where k.corrects_payment_id = ip.id))) then
      raise exception 'legacy refunds: % has a payment that is not a plain receipt; nothing was changed', i.invoice_no; end if;
    if (select count(*) from public.approval_requests a
         where a.related_record_id = i.id and a.request_type in ('invoice_refund', 'invoice_cancel')) <> 1
       or not exists (select 1 from public.approval_requests a join public.profiles pr on pr.id = a.approved_by
                       where a.related_record_id = i.id and a.request_type = 'invoice_refund' and a.status = 'approved'
                         and a.payload->'plan' is null and a.approved_at is not null) then
      raise exception 'legacy refunds: % does not have exactly one approved old-style refund request; nothing was changed', i.invoice_no; end if;
    -- The invoice's refund guard (legacy_refund_guard) runs when paid_amount
    -- comes down below. Asked here first, so a refusal names the invoice.
    begin
      perform public.assert_legacy_refund_allowed(i.id);
    exception when others then
      raise exception 'legacy refunds: % is blocked by the legacy refund guard (%); nothing was changed', i.invoice_no, sqlerrm;
    end;
  end loop;
  select count(*), coalesce(sum(ip.amount), 0) into n, v_sum
    from public.invoice_payments ip join public.invoices x on x.id = ip.invoice_id
   where x.invoice_no = any (c_invoices);
  if n <> c_payments or v_sum <> c_total
     or (select sum(x.total_amount) from public.invoices x where x.invoice_no = any (c_invoices)) <> c_total then
    raise exception 'legacy refunds: % payments of S$% found, not % of S$%; nothing was changed',
      n, to_char(v_sum, 'FM999999990.00'), c_payments, to_char(c_total, 'FM999999990.00'); end if;

  -- ── Change ───────────────────────────────────────────────────────────────
  for i in select x.* from public.invoices x where x.invoice_no = any (c_invoices) order by x.invoice_no loop
    select a.* into q from public.approval_requests a
     where a.related_record_id = i.id and a.request_type = 'invoice_refund' and a.status = 'approved';
    v_day := to_char((q.approved_at at time zone 'Asia/Singapore')::date, 'FMDD Mon YYYY');
    v_refunds := '[]'::jsonb;
    for p in select ip.* from public.invoice_payments ip where ip.invoice_id = i.id order by ip.created_at, ip.id loop
      insert into public.invoice_refunds (invoice_id, payment_id, amount, reason, kind, refunded_by, request_id,
                                          credit_returned, outcome, created_at)
      values (i.id, p.id, p.amount, c_mark || v_day, 'allocated', q.approved_by, q.id, 0,
              jsonb_build_object('legacy_backfill', true, 'approved_at', q.approved_at,
                                 'note', 'Refunded through the old request; written in by the 417 repair (the Owner, 9 Oct 2026)'),
              q.approved_at);
      v_refunds := v_refunds || jsonb_build_array(jsonb_build_object('payment_id', p.id, 'amount', p.amount));
      n_rows := n_rows + 1;
    end loop;
    update public.invoices set paid_amount = public.invoice_net_received(i.id) where id = i.id;
    perform public.write_audit_ex('invoices', i.id, 'legacy_refund_recorded',
      jsonb_build_object('paid_amount', i.paid_amount, 'refunded', 0),
      jsonb_build_object('paid_amount', public.invoice_net_received(i.id), 'refunds', v_refunds,
                         'request_id', q.id, 'refunded_on', (q.approved_at at time zone 'Asia/Singapore')::date),
      'refunds', c_mark || v_day, i.store_id);
  end loop;

  -- ── Afterwards: each holds nothing and shows its total refunded ─────────
  if exists (select 1 from public.invoices x where x.invoice_no = any (c_invoices)
              and (x.paid_amount <> 0 or public.invoice_net_received(x.id) <> 0 or x.status::text <> 'refunded'
                   or (select sum(r.amount) from public.invoice_refunds r where r.invoice_id = x.id) <> x.total_amount)) then
    raise exception 'legacy refunds: an invoice does not read as fully refunded afterwards; nothing was changed'; end if;
  raise notice 'legacy refunds: % refunds written on 9 invoices, S$% in all; each now holds S$0',
    n_rows, to_char(c_total, 'FM999999990.00');
  perform set_config('search_path', v_path, true);
end $repair$;
