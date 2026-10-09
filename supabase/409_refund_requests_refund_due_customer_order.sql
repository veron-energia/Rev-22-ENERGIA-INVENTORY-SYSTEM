-- 409_refund_requests_refund_due_customer_order.sql
--
-- WHAT WAS WRONG (audit of 8 Oct 2026: INVOICES-CREATE-1 / INVOICES-AFTER-3,
-- INVOICES-CREATE-3 / INVOICES-AFTER-2, INVOICES-CREATE-6, CUSTOMERS-3)
--
--   1. Staff (every role but Owner and Manager) were given "Request Refund",
--      which still called the retired request_invoice_action. That function
--      moved the invoice itself to refund_requested (or
--      cancellation_requested) and stored no plan, so Approvals could only
--      reject it ("cannot be approved as it stands"), and rejecting it in
--      resolve_invoice_action_v2 changed the request alone: the invoice stayed
--      "Refund requested", out of the Paid filter, most sales, discount,
--      affiliate and dashboard figures, and staff could no longer correct it.
--      The guided Refund / Cancel (request_invoice_action_v2), which changes
--      nothing on the invoice until an Owner or Manager approves, was offered
--      to Owners and Managers only. Production, 9 Oct 2026: 10 requests were
--      ever raised the old way, 1 of them rejected (INV-2026-0256, 21 Sep,
--      redone by the Owner); no invoice is in refund_requested or
--      cancellation_requested and no invoice request is pending.
--   2. A cancellation approved without "the money has gone back" ticked
--      leaves a refund due that could not be recorded afterwards: the guided
--      flow refuses a cancelled invoice, and refund_invoice_recorded's only
--      line without an item (the correction overpayment) allowed no more than
--      what was paid above the invoice TOTAL, which on a cancelled invoice is
--      the wrong ceiling (nothing is charged any more). A benefit-backed line
--      (a credit package or premium bundle) that never released its benefits
--      has nothing to allocate either. Production, 9 Oct 2026:
--      INV-2026-0317 (a premium bundle, cancelled 25 Sep) holds S$1,000 with a
--      S$1,000 refund due, its only line refundable for S$0; it is the only
--      cancelled or refunded invoice with a refund due.
--   3. The Invoices list worked out Outstanding as total minus paid for every
--      status, so cancelled and refunded invoices showed their whole total as
--      owed (the invoice's own view, invoice_financial_position, says 0), and
--      an open invoice with a line refunded showed the refund as still owed
--      (the refund lowers what is held, not the total). Production, 9 Oct
--      2026, all 350 invoices: S$59,039.50 shown, S$18,916.50 real (cancelled
--      S$20,223.00 on 5 invoices, refunded S$19,900.00 on 3; no open invoice
--      has a refund yet).
--   4. search_customers ordered by created_at alone. 12,748 of the 12,936
--      customers share one of 32 import timestamps, so an OFFSET page is any
--      slice of a tie: production, 9 Oct 2026, the export's thirteen pages of
--      1,000 gave 12,936 rows but 12,810 customers (126 missing, 126 twice),
--      and the first twenty screen pages of 50 gave 675 customers out of 1,000
--      rows. customer_survey_overview ends its order on full_name, which is not
--      unique either.
--
-- THE RULES (the Owner approved the audit's "Money & stock" fixes, 9 Oct 2026)
--
--   1. Staff raise refunds and cancellations through the guided flow, as a
--      request; the retired request_invoice_action is no longer a client
--      endpoint.
--   2. Rejecting an invoice request leaves the invoice as its payments say,
--      and moves nothing else. An invoice the old request moved to
--      refund_requested or cancellation_requested goes back, on rejection, to
--      the status its payments imply, by the rule 181 used for this, without
--      ever settling it: settled before the request (paid or FOC-confirmed
--      since it was opened or last reopened, 399's rule) and held >= still
--      charged -> paid (completed_foc for a S$0 FOC invoice); otherwise
--      something held -> partially_paid, nothing -> unpaid. Where that would
--      move stock or settle the invoice (fulfilled from a warehouse, or never
--      settled but now covered by its payments) it is refused, and nothing
--      changes. A guided request never changed the invoice, so rejecting one
--      changes nothing on it.
--   3. The refund due on a cancelled or refunded invoice
--      (invoice_financial_position: everything held on a cancelled invoice;
--      what is held above what is still charged on a refunded one) can be
--      recorded as paid back, by an Owner or Manager, through the original
--      payment sources, once, with the reason in the audit history. Not on a
--      cancelled invoice whose customer already had part of it (sessions
--      delivered, therapy started, vouchers redeemed, credit spent): the
--      cancellation kept that, so not all the money held is owed back, and
--      how much is is the Owner's question (refused until then).
--   4. A cancelled, refunded or FOC invoice owes nothing, and any other owes
--      what it still charges less what it holds: the list's Outstanding is
--      that, and its total says how much of it is cancelled or refunded.
--   5. The Customers list and its exports, and the Surveys customer list,
--      page in one fixed order: newest first, then by id.
--
-- WHAT THIS DOES
--
--   * resolve_invoice_action_v2 (patched; Owner/Manager, as before): the reject
--     branch puts an invoice in refund_requested or cancellation_requested
--     back to the status its payments imply (rule 2), writes that to the
--     invoice's audit history (request_rejected_status_restored) and to the
--     rejection's, and returns it as invoice_status_restored (null when the
--     invoice was not changed). It refuses, changing nothing, where putting
--     it back would take a warehouse-fulfilled invoice's goods from the
--     warehouse again (trg_fulfil_from_warehouse runs on every move to paid)
--     or settle an invoice that was not settled before the request. The
--     approve branch is not changed.
--   * cancelled_invoice_used_value(uuid) (new, internal: the service role
--     alone, 339): what a cancelled invoice's customer already had, by the
--     tests the guided cancellation's overrides use (session_used,
--     therapy_activated, voucher_redeemed, credit_used), plus paid credit
--     released before full payment and spent.
--   * refund_invoice_recorded (patched; Owner/Manager, as before): the line
--     without an item may now be up to the refund due on a cancelled invoice
--     (everything held) or a refunded one (held above what is still charged),
--     except on a cancelled invoice with anything in
--     cancelled_invoice_used_value, which it refuses, naming what was used.
--     Everything else is as it was: it still refuses an invoice whose issued
--     credit or sold vouchers must be refunded through their benefits, every
--     source must be a current original payment within what it still holds,
--     the sources must equal the refund, a repeated request ID with the same
--     details replays and with other details refuses, and the refund is
--     audited (allocated_refund). An open invoice keeps the old ceiling
--     (paid above the total). The page's "Record refund paid" sends this.
--   * invoice_list_page (patched; signed-in logins, as before): each row's
--     outstanding is 0 for cancelled, refunded and completed_foc, and
--     otherwise what it still charges (invoice_charge_total) less what it
--     holds (paid_amount), so the rows, the summary and the Outstanding sort
--     agree with the invoice's own view; the summary also carries
--     closed_total and closed_count (the matching invoices that are
--     cancelled or refunded).
--   * search_customers and customer_survey_overview (patched; signed-in
--     logins, as before): the order ends on the id (rule 5).
--   * The customers index on created_at (idx_customers_created_at) is
--     replaced by one on (created_at desc, id desc), same predicate
--     (deleted_at is null), named idx_customers_created_at_id.
--   * request_invoice_action is revoked from public, anon and authenticated
--     and granted to service_role (339). It is kept, unchanged, for history.
--
-- NOT CHANGED
--
--   * request_invoice_action_v2, invoice_action_plan, invoice_action_request_
--     detail, cancel_invoice_recorded, the approve branch and the plan hash.
--     A legacy request (no plan) still cannot be approved: reject it and raise
--     it again from the invoice.
--   * invoice_financial_position (its refund_due is the figure rule 3 uses;
--     on a cancelled invoice with used value it still shows everything held,
--     which the page now explains instead of offering to record it),
--     invoice_net_received, invoice_charge_total, therapy_unit_consumed,
--     writeoff_released_credit_on_close, trg_fulfil_from_warehouse.
--   * No table, column or row (one index replaced, above); no request or
--     invoice is repaired. Production, 9 Oct 2026: no invoice is in a
--     requested status, so rule 2 changes none today; whether INV-2026-0317's
--     S$1,000 went back is the Owner's question (nothing is recorded for it
--     here). INV-2026-0317 has nothing used (no sessions, therapy or benefits;
--     its S$1,000 of released credit was all taken back at the cancellation),
--     so it can be recorded.
--   * search_customers' and customer_survey_overview's columns, filters and
--     totals; the invoice list's rows, keys, filters and sorts (outstanding
--     aside).
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block), so
-- it is atomic however it is run. Every guard and anchor is checked, and every
-- patched text built, before anything is installed. md5(pg_get_functiondef)
-- of each patched function must be the production version read on 9 Oct 2026
-- (BEFORE), or already this migration's version (AFTER), which is left alone
-- so a re-run changes nothing; the new helper must be absent or already this
-- version. The functions relied on but not changed must be the versions read
-- on 9 Oct 2026, the invoice statuses the nine read then, and invoices must
-- have has_foc. Every anchor must match exactly once. The patches are
-- executed as CREATE OR REPLACE with the same arguments and result types,
-- which keeps owner and grants; no overload is added (another function of
-- any of the six names refuses). The definitions are read and compared with
-- the search path set to public. The old index, if there, must be the
-- definition read on 9 Oct 2026, and the new one, if there, this
-- migration's. After installing, the five functions and the helper must have
-- their AFTER md5, the five the grants they had (signed-in logins' and the
-- service role's, none signed out), request_invoice_action and the helper
-- the service role's alone, and the index this migration's definition, the
-- old one gone. No data changes.
--
-- AFTER THE SECURITY BATCH: 406 and 407 went live first (9 Oct 2026). Of the
-- five patched here, 406 changed customer_survey_overview only (a staff check
-- as its first statement and a cap of 200 at its LIMIT line, not this one's
-- ORDER BY); the other four already checked their caller. Its BEFORE md5 is
-- 406's AFTER and its AFTER was re-taken on a copy of production after 406;
-- every other md5 here was re-read from production then and is unchanged.
-- The new helper is internal (no client calls it), so it needs no staff check.
--
-- BEFORE (production, 9 Oct 2026 after 406 and 407, md5 of pg_get_functiondef):
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)       ff29fda79f9a5e0676bc023f2f5a06e0
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)                   42de7a5ac079fe706968e90d038cd5a5
--   invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)  e41831aaf4be629986edd9495fd5b6d7
--   search_customers(text,text,integer,integer,text,date,date)                  df63c717eab1825017e2567679f3e135
--   customer_survey_overview(text,text,integer,integer)                         e84eb56b42505e2f8a34e6e7486cf6f9
--   (relied on, not changed; request_invoice_action only revoked)
--   request_invoice_action(uuid,text,boolean,text)                              ed5a3931855dab6e63004d51df008346
--   request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)                   765a7a0629df4b591ca6718a6c171224
--   invoice_financial_position(uuid)                                            8751b7a8749452b0513e475b7fdb05ce
--   invoice_net_received(uuid)                                                  f256bea69b7defa38a950753bbc248da
--   invoice_charge_total(uuid)                                                  8297147511ba285db2279598f3d727fb
--   therapy_unit_consumed(uuid)                                                 7fe942b73bd10d566383d38c923162fe
--   writeoff_released_credit_on_close(uuid,text,text)                           284a89cfb965e8028136b5f8a4f2bf08
-- AFTER (for later guards):
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)       87c838d9ef9e23f8e2cc9ef8c60b0787
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)                   b0a99345c0f2e635391ac1c251634d95
--   invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)  dffff0e40dc8874759b8f0160df7f6db
--   search_customers(text,text,integer,integer,text,date,date)                  37cfdf902b98e800446211e9a4fdbabb
--   customer_survey_overview(text,text,integer,integer)                         900cfd200ddbdcb69ce87d3b6cdbc3e5
--   cancelled_invoice_used_value(uuid) (new)                                    70f684f1a8f0a4f42774394062e4df19
--
-- DEPLOY ORDER: this, then the page, straight after (pushing to main deploys
-- it). The page live now, against this: its staff "Request Refund" calls
-- request_invoice_action, which is refused from now on ("permission denied"),
-- so staff cannot raise a request until the new page is out (the Owner and
-- Managers are unaffected); its list rows show total minus paid until then,
-- while its summary is already right; its exports become complete. The new
-- page against a database without this: staff can already raise guided
-- requests (request_invoice_action_v2 was always theirs) and the list rows
-- owe nothing on closed invoices (the page applies that part of rule 4
-- itself; part refunds wait for this), but "Record refund paid" is
-- refused for INV-2026-0317 ("Amount exceeds the correction refund due") and
-- every Customers export is refused (the page now refuses a customer met
-- twice, which the old order always produces), which is why this goes first.
--
-- Test: scripts/invoice-actions/tests/refund-requests-and-refund-due.sql
--       scripts/referrals/tests/customer-paging.sql

set lock_timeout = '5s';

do $mig$
declare
  -- ── resolve_invoice_action_v2: a rejected request puts the invoice back ────
  c_resolve_decl_a constant text :=
       E' v_waiting jsonb;  -- 393\n';
  c_resolve_decl_r constant text :=
       E' v_waiting jsonb;  -- 393\n'
    || E' v_restored public.invoice_status; v_settled boolean; v_held numeric; v_charge numeric;  -- 409\n';
  c_resolve_reject_a constant text :=
       E'  perform public.write_audit_ex(''approval_requests'',r.id,''invoice_action_rejected'',to_jsonb(r),\n'
    || E'    jsonb_build_object(''note'',p_note),''invoices'',coalesce(p_note,''Rejected''),i.store_id);\n'
    || E'  return jsonb_build_object(''request_id'',r.id,''status'',''rejected'');\n';
  c_resolve_reject_r constant text :=
       E'  -- 409: the retired request_invoice_action moved the invoice itself to\n'
    || E'  -- refund_requested or cancellation_requested, and rejecting left it there,\n'
    || E'  -- out of the Paid filter and the reports. Rejecting puts it back as its\n'
    || E'  -- payments say (181''s rule), but never settles it: an invoice settled\n'
    || E'  -- before the request (paid or FOC-confirmed since it was opened or last\n'
    || E'  -- reopened, 399''s rule) and still holding what it charges is paid again\n'
    || E'  -- (completed_foc when S$0 and FOC); otherwise partially_paid when it\n'
    || E'  -- holds something, else unpaid. Settling again re-runs what settling\n'
    || E'  -- does, and all of it finds its work done except taking the goods from\n'
    || E'  -- the fulfilling warehouse, so that one is refused, as is an invoice its\n'
    || E'  -- payments now cover that was never settled (only a payment or\n'
    || E'  -- confirm_foc_invoice settles, with their checks). A guided request never\n'
    || E'  -- changes the invoice, so this finds nothing to do.\n'
    || E'  if i.status in (''refund_requested'',''cancellation_requested'') then\n'
    || E'   v_held:=public.invoice_net_received(i.id);\n'
    || E'   v_charge:=public.invoice_charge_total(i.id);\n'
    || E'   v_settled:=(i.locked_at is not null and (i.reopened_at is null or i.locked_at>i.reopened_at))\n'
    || E'           or (i.paid_at is not null and (i.reopened_at is null or i.paid_at>i.reopened_at));\n'
    || E'   if v_settled and v_held>=v_charge then\n'
    || E'    if i.fulfil_warehouse_id is not null then\n'
    || E'     raise exception ''Rejecting this request would put % back to paid, which takes its goods from the fulfilling warehouse a second time. Nothing was changed: this request has to be resolved by hand.'', i.invoice_no; end if;\n'
    || E'    v_restored:=case when i.total_amount=0 and i.has_foc then ''completed_foc''::public.invoice_status\n'
    || E'                     else ''paid''::public.invoice_status end;\n'
    || E'   elsif v_held>0 and v_held>=v_charge then\n'
    || E'    raise exception ''Rejecting this request would settle %, which was not settled when the request was raised (its payments cover it now). Nothing was changed: this request has to be resolved by hand.'', i.invoice_no;\n'
    || E'   elsif v_held>0 then v_restored:=''partially_paid''::public.invoice_status;\n'
    || E'   else v_restored:=''unpaid''::public.invoice_status;\n'
    || E'   end if;\n'
    || E'   update public.invoices set status=v_restored where id=i.id;\n'
    || E'   perform public.write_audit_ex(''invoices'',i.id,''request_rejected_status_restored'',\n'
    || E'     jsonb_build_object(''status'',i.status),jsonb_build_object(''status'',v_restored,''request_id'',r.id),\n'
    || E'     ''invoices'',coalesce(p_note,''Rejected''),i.store_id);\n'
    || E'  end if;\n'
    || E'  perform public.write_audit_ex(''approval_requests'',r.id,''invoice_action_rejected'',to_jsonb(r),\n'
    || E'    jsonb_build_object(''note'',p_note,''invoice_status_restored'',v_restored),''invoices'',coalesce(p_note,''Rejected''),i.store_id);\n'
    || E'  return jsonb_build_object(''request_id'',r.id,''status'',''rejected'',''invoice_status_restored'',v_restored);\n';

  -- ── refund_invoice_recorded: the refund due on a closed invoice ────────────
  c_refund_a constant text :=
       E'     if v_amount>greatest(public.invoice_net_received(i.id)-i.total_amount,0) then raise exception ''Amount exceeds the correction refund due''; end if;\n';
  c_refund_r constant text :=
       E'     -- 409: a cancelled invoice charges nothing any more, so all it still\n'
    || E'     -- holds is the refund due (invoice_financial_position); a refunded one,\n'
    || E'     -- what it holds above what is still charged. That money going back is\n'
    || E'     -- this line. An open invoice is as before: only what was paid above\n'
    || E'     -- its total.\n'
    || E'     -- But a cancellation keeps what the customer already had (sessions\n'
    || E'     -- delivered, therapy started, vouchers redeemed, credit spent: the guided\n'
    || E'     -- cancellation leaves them out of its refund due), so on a cancelled\n'
    || E'     -- invoice with any of that, not all the money held is owed back, and how\n'
    || E'     -- much is has no rule yet: refused.\n'
    || E'     if i.status=''cancelled'' and cardinality(public.cancelled_invoice_used_value(i.id))>0 then\n'
    || E'       raise exception ''Part of what % sold has been used (%), so not all the money it still holds is owed back. It cannot be recorded here until the Owner decides how much goes back; nothing was recorded.'',\n'
    || E'         i.invoice_no, (select string_agg(case c when ''session_used'' then ''sessions delivered''\n'
    || E'                                         when ''therapy_activated'' then ''therapy started or its vouchers collected''\n'
    || E'                                         when ''voucher_redeemed'' then ''vouchers redeemed'' else ''credit spent'' end, '', '')\n'
    || E'                          from unnest(public.cancelled_invoice_used_value(i.id)) c); end if;\n'
    || E'     if v_amount>greatest(public.invoice_net_received(i.id)-case when i.status=''cancelled'' then 0\n'
    || E'          when i.status=''refunded'' then public.invoice_charge_total(i.id) else i.total_amount end,0) then\n'
    || E'       raise exception ''Amount exceeds the correction refund due''; end if;\n';

  -- ── invoice_list_page: nothing is owed on a closed invoice ─────────────────
  c_list_row_a constant text :=
       E'           greatest(coalesce(i.total_amount,0) - coalesce(i.paid_amount,0), 0) as outstanding,\n';
  c_list_row_r constant text :=
       E'           -- 409: as the invoice''s own view (invoice_financial_position) says:\n'
    || E'           -- a cancelled, refunded or FOC invoice owes nothing, and any other owes\n'
    || E'           -- what it still charges (its total less the lines refunded) less what\n'
    || E'           -- it holds, so a part refund is not shown as owed.\n'
    || E'           case when i.status in (''cancelled'',''refunded'',''completed_foc'') then 0::numeric\n'
    || E'                else greatest(public.invoice_charge_total(i.id) - coalesce(i.paid_amount,0), 0) end as outstanding,\n';
  c_list_sum_a constant text :=
       E'           coalesce(sum(paid_amount),0)  as sum_paid\n';
  c_list_sum_r constant text :=
       E'           coalesce(sum(paid_amount),0)  as sum_paid,\n'
    || E'           -- 409: how much of the total is cancelled or refunded.\n'
    || E'           coalesce(sum(total_amount) filter (where status in (''cancelled'',''refunded'')),0) as sum_closed,\n'
    || E'           count(*) filter (where status in (''cancelled'',''refunded'')) as closed_count\n';
  c_list_keys_a constant text :=
       E'                   ''outstanding'', sum_outstanding, ''paid'', sum_paid) from counted)\n';
  c_list_keys_r constant text :=
       E'                   ''outstanding'', sum_outstanding, ''paid'', sum_paid,\n'
    || E'                   ''closed_total'', sum_closed, ''closed_count'', closed_count) from counted)\n';

  -- ── search_customers and customer_survey_overview: one fixed order ─────────
  c_search_a constant text :=
       E'   order by m.created_at desc\n';
  c_search_r constant text :=
       E'   -- 409: most customers share an import timestamp, so the id settles the\n'
    || E'   -- order: every page and every export is then one slice of one list.\n'
    || E'   order by m.created_at desc, m.id desc\n';
  c_survey_a constant text :=
       E'   order by (f.survey_id is null), coalesce(f.last_remark_at, f.submitted_at) desc nulls last, f.full_name\n';
  c_survey_r constant text :=
       E'   -- 409: names repeat, so the customer and the survey settle the order.\n'
    || E'   order by (f.survey_id is null), coalesce(f.last_remark_at, f.submitted_at) desc nulls last, f.full_name,\n'
    || E'            f.id, f.survey_id\n';

  -- ── New, internal: what a cancelled invoice's customer already had ─────────
  c_used_def constant text := $def$
create or replace function public.cancelled_invoice_used_value(p_invoice_id uuid)
returns text[]
language sql
stable
security definer
set search_path = public
as $fn$
  -- 409: what the customer of a cancelled invoice already had from it, which
  -- the cancellation kept: the evidence the guided cancellation asks an
  -- override for (invoice_action_plan's session_used, therapy_activated,
  -- voucher_redeemed and credit_used, by the same tests), and paid credit
  -- released before full payment and spent (once the invoice is closed,
  -- writeoff_released_credit_on_close leaves only the spent part on the
  -- release record). Empty when nothing was used.
  select array_remove(array[
    case when exists (select 1 from public.customer_therapy_sessions s
                       where s.invoice_id = p_invoice_id and s.is_current and s.quantity_used > 0)
         then 'session_used' end,
    case when exists (select 1 from public.purchased_therapy_entitlements e
                        join public.invoice_items it on it.id = e.invoice_item_id
                       where it.invoice_id = p_invoice_id and public.therapy_unit_consumed(e.id))
         then 'therapy_activated' end,
    case when exists (select 1 from public.invoice_benefit_values b
                        left join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
                       where b.invoice_id = p_invoice_id and b.reward_voucher_id is not null
                         and coalesce(case when v.status = 'held' then v.quantity else 0 end, 0)
                             + b.cancelled_unused_value < b.granted_value)
         then 'voucher_redeemed' end,
    case when exists (select 1 from public.invoice_benefit_values b
                        left join public.customer_credit_lots l on l.id = b.lot_id
                       where b.invoice_id = p_invoice_id and b.reward_voucher_id is null
                         and coalesce(l.remaining_amount, 0) + b.cancelled_unused_value < b.granted_value)
           or exists (select 1 from public.credit_package_progress_lots pl
                       where pl.invoice_id = p_invoice_id and pl.released_amount > 0
                         and not exists (select 1 from public.invoice_benefit_values b
                                          where b.invoice_item_id = pl.invoice_item_id))
         then 'credit_used' end], null)
$fn$
$def$;
  c_used_fn constant text := 'cancelled_invoice_used_value(uuid)';
  c_used_after constant text := '70f684f1a8f0a4f42774394062e4df19';

  c_resolve_after constant text := '87c838d9ef9e23f8e2cc9ef8c60b0787';
  c_refund_after constant text := 'b0a99345c0f2e635391ac1c251634d95';
  c_list_after constant text := 'dffff0e40dc8874759b8f0160df7f6db';
  c_search_after constant text := '37cfdf902b98e800446211e9a4fdbabb';
  c_survey_after constant text := '900cfd200ddbdcb69ce87d3b6cdbc3e5';
  c_old_index constant text :=
    'CREATE INDEX idx_customers_created_at ON public.customers USING btree (created_at DESC) WHERE (deleted_at IS NULL)';
  c_new_index constant text :=
    'CREATE INDEX idx_customers_created_at_id ON public.customers USING btree (created_at DESC, id DESC) WHERE (deleted_at IS NULL)';
  -- The invoice statuses read on 9 Oct 2026; rule 2 names five of them.
  c_statuses constant text :=
    'draft,unpaid,partially_paid,paid,cancellation_requested,cancelled,refund_requested,refunded,completed_foc';
  c_fns constant text[] := array[
    'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)',
    'search_customers(text,text,integer,integer,text,date,date)',
    'customer_survey_overview(text,text,integer,integer)'];

  v_path text := current_setting('search_path');
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_defs text[] := '{}'; v_todo text[] := '{}'; v_acl text[];
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ─
  for r in select * from (values
    (c_fns[1], 'ff29fda79f9a5e0676bc023f2f5a06e0', c_resolve_after,
     array[[c_resolve_decl_a, c_resolve_decl_r], [c_resolve_reject_a, c_resolve_reject_r]]),
    (c_fns[2], '42de7a5ac079fe706968e90d038cd5a5', c_refund_after,
     array[[c_refund_a, c_refund_r]]),
    (c_fns[3], 'e41831aaf4be629986edd9495fd5b6d7', c_list_after,
     array[[c_list_row_a, c_list_row_r], [c_list_sum_a, c_list_sum_r], [c_list_keys_a, c_list_keys_r]]),
    (c_fns[4], 'df63c717eab1825017e2567679f3e135', c_search_after,
     array[[c_search_a, c_search_r]]),
    (c_fns[5], 'e84eb56b42505e2f8a34e6e7486cf6f9', c_survey_after,
     array[[c_survey_a, c_survey_r]])
  ) x(fn, before_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '409: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '409: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '409: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    for k in 1 .. array_length(r.edits, 1) loop
      n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
      if n <> 1 then
        raise exception '409: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
      d := replace(d, r.edits[k][1], r.edits[k][2]);
    end loop;
    v_todo := v_todo || r.fn;
    v_defs := v_defs || d;
  end loop;
  -- Relied on, not changed: the versions read on 9 Oct 2026 (the old request,
  -- the only thing that moves an invoice to a requested status; the guided
  -- request, which changes nothing on the invoice; the refund due; what is
  -- held; what is still charged; what counts as therapy used; what a closed
  -- invoice leaves on a credit release record).
  for r in select * from (values
    ('request_invoice_action(uuid,text,boolean,text)', 'ed5a3931855dab6e63004d51df008346'),
    ('request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)', '765a7a0629df4b591ca6718a6c171224'),
    ('invoice_financial_position(uuid)', '8751b7a8749452b0513e475b7fdb05ce'),
    ('invoice_net_received(uuid)', 'f256bea69b7defa38a950753bbc248da'),
    ('invoice_charge_total(uuid)', '8297147511ba285db2279598f3d727fb'),
    ('therapy_unit_consumed(uuid)', '7fe942b73bd10d566383d38c923162fe'),
    ('writeoff_released_credit_on_close(uuid,text,text)', '284a89cfb965e8028136b5f8a4f2bf08')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '409: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  if (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e
       where e.enumtypid = 'public.invoice_status'::regtype) is distinct from c_statuses then
    raise exception '409: the invoice statuses are not the ones read on 9 Oct 2026 (%). Ask the Owner what a rejected request should restore.',
      (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e
        where e.enumtypid = 'public.invoice_status'::regtype); end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'invoices' and column_name = 'has_foc') then
    raise exception '409: public.invoices has no has_foc column'; end if;
  -- New: absent, or already this version.
  if to_regprocedure('public.' || c_used_fn) is not null
     and md5(pg_get_functiondef(to_regprocedure('public.' || c_used_fn))) <> c_used_after then
    raise exception '409: a different public.% already exists (md5 %)', c_used_fn,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_used_fn))); end if;
  -- No other function takes these names (the API picks an overload by name).
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('resolve_invoice_action_v2', 'refund_invoice_recorded', 'invoice_list_page',
                                'search_customers', 'customer_survey_overview', 'request_invoice_action',
                                'cancelled_invoice_used_value')
              and p.oid::regprocedure::text <> all (c_fns || 'request_invoice_action(uuid,text,boolean,text)'::text
                                                          || c_used_fn)) then
    raise exception '409: another overload of resolve_invoice_action_v2, refund_invoice_recorded, invoice_list_page, search_customers, customer_survey_overview, request_invoice_action or cancelled_invoice_used_value exists'; end if;
  -- The index: the old one as read on 9 Oct 2026, the new one only as this
  -- migration makes it.
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_customers_created_at'
                and indexdef <> c_old_index) then
    raise exception '409: public.idx_customers_created_at is not the index read on 9 Oct 2026'; end if;
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_customers_created_at_id'
                and indexdef <> c_new_index) then
    raise exception '409: public.idx_customers_created_at_id already exists with another definition'; end if;
  select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text) into v_acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_fns);

  -- ── Install: the new helper first, then what calls it ──────────────────────
  execute c_used_def;
  revoke all on function public.cancelled_invoice_used_value(uuid) from public, anon, authenticated;
  grant execute on function public.cancelled_invoice_used_value(uuid) to service_role;
  for i in 1 .. coalesce(array_length(v_defs, 1), 0) loop
    execute v_defs[i];
  end loop;
  execute 'create index if not exists idx_customers_created_at_id on public.customers (created_at desc, id desc) where deleted_at is null';
  execute 'drop index if exists public.idx_customers_created_at';
  revoke all on function public.request_invoice_action(uuid,text,boolean,text) from public, anon, authenticated;
  grant execute on function public.request_invoice_action(uuid,text,boolean,text) to service_role;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    (c_fns[1], c_resolve_after), (c_fns[2], c_refund_after), (c_fns[3], c_list_after),
    (c_fns[4], c_search_after), (c_fns[5], c_survey_after), (c_used_fn, c_used_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '409: installed with md5s other than the tested ones: %', v_bad; end if;
  if (select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_fns))
     is distinct from v_acl then
    raise exception '409: the grants of the patched functions changed'; end if;
  foreach v in array c_fns loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '409: public.% is not signed-in logins'' and the service role''s alone', v; end if;
  end loop;
  foreach v in array array['request_invoice_action(uuid,text,boolean,text)', c_used_fn] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '409: public.% is not the service role''s alone', v; end if;
  end loop;
  if (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'idx_customers_created_at_id')
       is distinct from c_new_index
     or exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_customers_created_at') then
    raise exception '409: the customers index is not (created_at desc, id desc) alone'; end if;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
