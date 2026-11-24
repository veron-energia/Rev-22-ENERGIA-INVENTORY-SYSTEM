-- 533_approvals_need_another_person_and_owner_limits.sql
--
-- A MANAGER DOES NOT APPROVE WHAT THEY ASKED FOR OR SHAPED, APPROVES ONLY FOR THEIR OWN STORES,
-- TAKES BACK UP TO S$1,000 ON AN INVOICE, AND LEAVES CREDIT BY HAND, CREDIT GIVEN FREE OR MOVED,
-- AND PAYOUTS TO AN OWNER
--
--   From the security audit of 17 Nov 2026 (finding M9).
--   The BEFORE md5s and the relied-on md5s below are those of production after 529 (the local
--   copy of 20 Nov 2026). If production differs when this is applied, it refuses and changes
--   nothing.
--   (The number 533 is this file's name and its errors' prefix; if it changes at commit, change
--   it there, in the 533 comments it writes into the functions below (and so their AFTER md5s,
--   also in scripts/approvals/undo-533.sql and in the suites that know them), and in the name
--   and path of its suite.)
--
-- WHAT WAS WRONG
--
--   Only an Owner or a Manager can approve, but one of them alone could approve what they asked
--   for themselves: their own transfer (after editing it, or adding lines and raising quantities
--   while approving it), their own stock correction, their own invoice refund or cancellation
--   request, and the discrepancy of a transfer they received themselves. A Manager's approval of
--   a transfer or a stock correction was not tied to the stores they work at. A Manager could
--   add or remove a customer's credit by hand, make a credit package or bundle line free, move
--   an invoice's unused credit or vouchers to another customer, record and correct affiliate
--   payouts, affiliate repayments and staff commission payouts, and take back any amount on an
--   invoice, by refunds or by lowering, splitting or removing recorded payments. And
--   cancel_invoice_recorded and the old request_inventory_adjustment could be called straight by
--   any signed-in login.
--
-- THE RULE (the user, 20 Nov 2026)
--
--   1. "Another person approves": a Manager may not approve a request they made themselves: a
--      transfer (review and dispatch), a stock correction, an invoice refund or cancellation
--      request; nor resolve the discrepancy of a transfer they received themselves. An Owner, or
--      the other Manager, does it. Owners keep approving their own. A Manager may still reject or
--      withdraw their own.
--   2. "Own stores only": a Manager reviews, approves or rejects a transfer, resolves its
--      discrepancy, or approves a stock correction only when every STORE involved is one they
--      work at (current_user_store_ids(), as 520's rules use it). Warehouses stay open to every
--      Manager. An Owner: every store.
--   3. "Owners only": credit added or removed by hand; recording or correcting affiliate
--      payouts. Credit bought on an invoice, refunds into credit and every automatic credit stay
--      as they are. Managers keep reading credit and payouts.
--   4. and 7. "Up to S$1,000": for a Manager, on one invoice, the refunds recorded and the
--      amounts by which recorded payments were lowered (corrected, split or removed) come to at
--      most S$1,000 together, this change included; above that an Owner does it, and a Staff
--      request above it waits for an Owner.
--   5. A signed-in login can no longer call cancel_invoice_recorded straight.
--   6. "Credit without a sale: Owners only": making a credit package or premium bundle line free
--      (Make FOC); moving an invoice's unused credit or vouchers to another customer.
--   8. "Transfers the Manager shaped": a Manager does not approve or dispatch a transfer request
--      they edited (any edit by them), nor add lines or approve more than was requested while
--      approving it. Choosing the sources and lowering quantities stay as before.
--   9. "Owners only": recording or voiding an affiliate repayment (a deduction marked settled);
--      recording a staff commission payout.
--  10. "Owners only" (the user, 20 Nov 2026): only an Owner changes a recorded payment into or out
--      of wallet credit (correct_invoice_payment at the same amount, wallet to money or money to
--      wallet). Managers still correct amounts within the limit and change methods and dates
--      between money methods.
--   And, with no rule change: the old request_inventory_adjustment(location_type, …), which no
--   page calls, is closed to signed-in logins, as 513 closed old routes.
--
-- WHAT THIS DOES (every refusal is errcode 42501, in the words the pages show)
--
--   "Not an Owner" is current_user_role() is distinct from 'owner' (an Admin is not an Owner;
--   is_owner() is not executable by signed-in logins). Each test comes after the function's own
--   first check, which already refuses anyone but an active Owner or Manager (or, in
--   apply_line_foc, is inside its "signed in" branch), so the secret key and the server are
--   refused or let through exactly as before.
--
--   * review_and_dispatch_transfer (Review & Dispatch; approve_transfer and approve_transfer_multi
--     reach it too), once the request is found pending, for a caller who is not an Owner:
--       - asked for it (requested_by): "A Manager cannot approve their own transfer request. An
--         Owner or another Manager approves it.";
--       - edited it (edited_by, or edited_by of any of its transfer_request_revisions): "A
--         Manager who changed this transfer request cannot also approve it. An Owner or another
--         Manager approves it.";
--       - a store at its ends they do not work at, and later every store chosen as a source:
--         "A Manager approves only for the stores they work at.";
--       - a line added in this review, or a quantity approved above the one requested: "A
--         Manager cannot add lines or raise quantities while approving a transfer. An Owner or
--         another Manager approves such a change."
--   * reject_transfer: the store test on the request's ends (a Manager still rejects their own).
--   * resolve_transfer_discrepancy, for a caller who is not an Owner: received it themselves
--     (received_by): "A Manager cannot resolve a transfer they received themselves. An Owner or
--     another Manager resolves it."; then the store test on the request's ends and every store
--     its lines were sent from.
--   * resolve_inventory_adjustment, on an approval only, for a caller who is not an Owner: asked
--     for it (requested_by): "A Manager cannot approve their own stock correction. An Owner or
--     another Manager approves it."; then a correction at a store they do not work at: the store
--     sentence. A warehouse: open.
--   * resolve_invoice_action_v2, on an approval only, for a caller who is not an Owner: raised it
--     (requested_by): "A Manager cannot approve their own request. An Owner or another Manager
--     approves it." The money it moves goes through refund_invoice_recorded and its limit.
--   * The S$1,000 limit, measured in one place, two new helpers (no login can call them):
--       invoice_payment_lowered_by(payment): a recorded payment's reversal (correction_reversal,
--         corrects_payment_id = it) less every payment that replaced it (correction_replacement,
--         same corrects_payment_id; a split's parts included), when more, else 0. A payment is
--         reversed at most once, so this is what correcting, splitting or removing it took off.
--       invoice_taken_back(invoice): every invoice_refunds row of the invoice (refunds into
--         credit included) plus invoice_payment_lowered_by of every payment of it ever reversed.
--     Read with the invoice locked, by:
--       - refund_invoice_recorded (the invoice view's direct refund, and every refund an
--         approval records), before it writes: invoice_taken_back plus this refund above
--         S$1,000, for a caller who is not an Owner, refuses: "A Manager can take back up to
--         S$1,000 on an invoice, refunds and lowered payments together; an Owner does anything
--         above that." A retry with the same request id returns its first answer before this and
--         is not counted again.
--       - correct_invoice_payment (the invoice view's payment correction and Edit Invoice),
--         remove_invoice_payment and split_invoice_payment (Edit Invoice; no login calls them
--         straight), after they write: when this change lowered the payment and
--         invoice_taken_back is then above S$1,000, for a caller who is not an Owner, the same
--         sentence. A change of method or date alone, or a raise, lowers nothing and passes.
--       - correct_invoice_payment also refuses, for a caller who is not an Owner, a new method
--         whose is_wallet_credit differs from the old one's: "Only an Owner can change a payment
--         into or out of wallet credit." (decision 10). The other routes that set a payment's
--         method already refuse wallet credit both ways for everyone, Owners included, and are
--         left as they are: correct_invoice_payment_methods (Edit Invoice's method change) and
--         split_invoice_payment (a wallet payment, or a wallet part); remove_invoice_payment
--         refuses a wallet payment.
--   * Owner only, after each function's own Owner-or-Manager check:
--       adjust_customer_credit, add_legacy_credit, reverse_credit_lot (which no login can call;
--         kept with them): "Only an Owner can add or remove credit by hand.";
--       affiliate_payout_save (record_affiliate_payout and correct_affiliate_payout call it):
--         "Only an Owner can record or correct an affiliate payout.";
--       apply_line_foc on a credit_package or premium_bundle line (a voucher or therapy line
--         stays with an Owner or Manager, as 507 left it; products with anyone allowed): "Only an
--         Owner can make a credit package or premium bundle line free." A new invoice and Edit
--         Invoice already refuse FOC on those two kinds for everyone (355): unchanged;
--       transfer_invoice_unused_benefit: "Only an Owner can move unused credit or vouchers to
--         another customer.";
--       record_affiliate_deduction_settlement and void_affiliate_deduction_settlement: "Only an
--         Owner can record or void an affiliate repayment.";
--       create_staff_commission_payout: "Only an Owner can record a staff commission payout."
--   * EXECUTE revoked from authenticated on cancel_invoice_recorded (resolve_invoice_action_v2
--     reaches it as the owner) and on request_inventory_adjustment(location_type, uuid, uuid,
--     integer, text, text) (request_inventory_adjustments, the page's call, does not call it).
--     Their text is unchanged.
--
-- WHAT THIS LEAVES ALONE
--
--   * The helpers is_owner_or_manager(), can_manage_customer_credit() and
--     affiliate_payout_access(): unchanged (affiliate_payout_access(true) is also the read of
--     affiliate_admin_directory, which Managers keep). Each function above is patched instead.
--   * Requests are made as before; a Manager withdraws their own transfer
--     (cancel_transfer_request) and rejects their own requests as before; edits a pending
--     transfer as before.
--   * A cancellation records no money (the refund that pays it back is limited); reopen_invoice;
--     refund_purchased_therapy (it ends the entitlement and moves no money); receiving a
--     transfer; a split's parts may add up to less than the payment for an Owner (a Manager is
--     held by the limit); a Manager changes a payment's method or date alone, between two money
--     methods or between two wallet-credit methods (Bonus Credit to Paid Credit, say: both are
--     wallet credit, so decision 10 does not apply).
--   * web_order_close_refunded and event_vip_order_close_refunded (a website or VIP order
--     refunded in HitPay and only closed here, with no invoice): left for the user to decide.
--   * Credit bought on an invoice, refunds into credit and every automatic credit; every grant
--     but the two above; no data changes.
--
-- UNDO
--
--   scripts/approvals/undo-533.sql (it refuses unless every function here is exactly 533's and
--   the two grants are 533's): each function is put back exactly as it was, the two helpers are
--   dropped, and EXECUTE on the two closed functions is granted to authenticated again. A later
--   migration changing any of these must pin 533's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/approvals/tests/another-person-approves-533.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the patched ones rely on, as tested: the caller's role and stores, the
  -- Owner-or-Manager checks left in place, the server's pass, the two that already refuse a
  -- credit package or bundle made free (355), and the routes that reach the patched ones.
  c_relied constant text[] := array[
    'current_user_role()',
    'current_user_store_ids()',
    'is_owner_or_manager()',
    'can_manage_customer_credit()',
    'affiliate_payout_access(boolean)',
    'require_active_staff(text[])',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'request_inventory_adjustment(location_type,uuid,uuid,integer,text,text)',
    'approve_transfer(uuid,jsonb,text,uuid)',
    'approve_transfer_multi(uuid,jsonb,text,uuid,jsonb)',
    'record_affiliate_payout(uuid,date,numeric,uuid,date,text,text,uuid)',
    'correct_affiliate_payout(uuid,integer,numeric,uuid,date,text,text,text,uuid)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)'];
  c_relied_md5 constant text[] := array[
    '519b0a33a3548f970c5d585b6e76a389',
    '54191b973c31654b903d48bea01ce533',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    'a576249272a4c7fb68965d0f62649ed4',
    '90b7399378a7604afd4af97c059d0703',
    '877b3aa74cea559881979bb161c450e2',
    '5490e4b48dfdab63b6dc5a0aa78d4bc7',
    'f46897361f4d9f80694a8267e44d2cfa',
    'e1b937e88c380ccf9ca9eb0b1c7820e0',
    '54fa089c1a8e5897147bf290e1f95203',
    'e67ff1478637e77c379a18dcb8797a2b',
    'e69c904cd0d5f9b806dc2be97870c0ab',
    '42f00d595a40df157d28a7ea88fbe7ad',
    '09e1d77e450d50fc6195773f92e770e5',
    'aaf592490eb5d13ca2ccb0544f48f647',
    'd9cec0b343afaea0171952cbcda80b61'];
  -- The two new helpers: their signatures, text and grants (the owner and the service role).
  c_new_sig constant text[] := array[
    'invoice_payment_lowered_by(uuid)',
    'invoice_taken_back(uuid)'];
  c_new_def constant text[] := array[
$d$CREATE OR REPLACE FUNCTION public.invoice_payment_lowered_by(p_payment_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Up to S$1,000"): how much a
  -- recorded payment was lowered when it was corrected, split or removed: its reversal less every
  -- payment that replaced it (a split's parts included), when more, else 0. A payment is reversed
  -- at most once (each route refuses a payment already reversed), so this is what that change
  -- took off. 0 for a payment never reversed.
  select greatest(
           coalesce((select sum(q.amount) from public.invoice_payments q
                      where q.corrects_payment_id = p_payment_id and q.entry_kind = 'correction_reversal'), 0)
         - coalesce((select sum(q.amount) from public.invoice_payments q
                      where q.corrects_payment_id = p_payment_id and q.entry_kind = 'correction_replacement'), 0),
         0)
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.invoice_taken_back(p_invoice_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Up to S$1,000", refunds and
  -- lowered payments together): what has been taken back on an invoice: every refund recorded
  -- (invoice_refunds, refunds into credit included) and every recorded payment lowered by a
  -- correction, a split or a removal (invoice_payment_lowered_by). Read with the invoice locked.
  select coalesce((select sum(f.amount) from public.invoice_refunds f where f.invoice_id = p_invoice_id), 0)
       + coalesce((select sum(public.invoice_payment_lowered_by(r.payment_id))
                     from (select distinct q.corrects_payment_id as payment_id from public.invoice_payments q
                            where q.invoice_id = p_invoice_id and q.entry_kind = 'correction_reversal'
                              and q.corrects_payment_id is not null) r), 0)
$function$
$d$];
  c_new_md5 constant text[] := array[
    '5502cb18da573d7b3132078bb0dbbde1',
    '7bc3edff2b0307ea2fca9d9b7e8fa58b'];
  c_new_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  -- The functions patched.
  c_sig constant text[] := array[
    'review_and_dispatch_transfer(uuid,jsonb,text)',
    'reject_transfer(uuid,text)',
    'resolve_transfer_discrepancy(uuid,jsonb,text)',
    'resolve_inventory_adjustment(uuid,boolean,text)',
    'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)',
    'add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)',
    'reverse_credit_lot(uuid,text,text,text)',
    'affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)',
    'apply_line_foc(uuid,integer,uuid,text)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'remove_invoice_payment(uuid,text,uuid)',
    'split_invoice_payment(uuid,jsonb,text,uuid)',
    'record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)',
    'void_affiliate_deduction_settlement(uuid,text,uuid)',
    'create_staff_commission_payout(uuid,date,uuid,text,text)'];
  c_before constant text[] := array[
    '6db84d9ecca1d40b4858b4291401fbc0',
    '78942901accf9c2c6b49e48432833f33',
    '9e9e324415e20981b5b416a5a37bf951',
    '94c01092a241f8c441bfc9c13ca5cc7f',
    '201f08ebf14a64cd88d411a7cfb4c9c4',
    '49f6880e4e6395b1468f32e4126472eb',
    '34724253ceddb93c99279a3cb27ed445',
    '0351aa4ce473ce1309be1cfdff6ad613',
    '10c1a3d8e3bb003fbaf01cf879f97c5e',
    'dd2993318ffef5c8f60b1e8513ed1902',
    'a249b0e94d4280d6ff4e73fa8e1efbc8',
    '720d296a43524e7ac8843c6062030819',
    '088e2130d62a1dc4af8cd9417465c0b6',
    '8eb341eb5383430f676940be1de37def',
    '236b86da67f77eb036592e1ce12ec366',
    '70976b9267b703dc4899b518f46f7ec9',
    '6be0c40f6fbe4d6910e1fe749f733c0e',
    'e38ef66798b159c9b3f1f5ddbb7e8bcc'];
  c_after constant text[] := array[
    'd1fe2d8b84895951f6f86fc1a89436d7',
    'cf337eabea93d00ae052853a0ffac850',
    '00fadc33ac027da095483f22b6a6ed75',
    '6aaa8f4ff405de2dde4cbf09ed7b1bcd',
    'd1ab83e457684ad3d010dd5a92719570',
    '4f81d244db8f8c5b6d35143456fa8cc7',
    '91d8bc8893f2be5df7c79a304067714b',
    'c1fc53090470a4e61a07aaf5a922d82d',
    '62ea75384be87010919f21a5884d0186',
    'd348969eb1673fb204957c43673983fc',
    '4a0d20eccbdebaa9af74bd9c1eb362ef',
    '9e108d79e6212474397b7c9cacf0dc27',
    '5ac4a3ac99f5e5cbda370fcd8c9f9cd0',
    'ab2940828dffdd7aff007d036e88820b',
    'f66d4ba00406e50171afcf6b4b79c969',
    '66b37537ccdc44308e126889041f239f',
    '6ceaca7815ed23c12bf233ebfa91d770',
    '90c9d0ddd131fda739875bed4970e0e9'];
  -- Their grants, before and after (unchanged).
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  -- The two functions closed to signed-in logins, and their grants before and after.
  c_closed constant text[] := array[
    'cancel_invoice_recorded(uuid,text,uuid)',
    'request_inventory_adjustment(location_type,uuid,uuid,integer,text,text)'];
  c_closed_acl_before constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_closed_acl_after constant text := 'postgres=X/postgres,service_role=X/postgres';
  -- Twenty-two patches, each found exactly once in its function:
  --    1 review_and_dispatch_transfer: own, edited, the request's store ends
  --    2 review_and_dispatch_transfer: a line added in this review
  --    3 review_and_dispatch_transfer: a quantity raised
  --    4 review_and_dispatch_transfer: every store chosen as a source
  --    5 reject_transfer: the request's store ends
  --    6 resolve_transfer_discrepancy: received themselves, and every store involved
  --    7 resolve_inventory_adjustment: own correction, and its store (on an approval)
  --    8 resolve_invoice_action_v2: own request (on an approval)
  --    9 refund_invoice_recorded: the S$1,000 limit
  --   10 adjust_customer_credit: Owner only
  --   11 add_legacy_credit: Owner only
  --   12 reverse_credit_lot: Owner only
  --   13 affiliate_payout_save: Owner only
  --   14 apply_line_foc: a credit package or premium bundle made free, Owner only
  --   15 transfer_invoice_unused_benefit: Owner only
  --   16 correct_invoice_payment: the S$1,000 limit
  --   17 remove_invoice_payment: the S$1,000 limit
  --   18 split_invoice_payment: the S$1,000 limit
  --   19 record_affiliate_deduction_settlement: Owner only
  --   20 void_affiliate_deduction_settlement: Owner only
  --   21 create_staff_commission_payout: Owner only
  --   22 correct_invoice_payment: into or out of wallet credit, Owner only
  c_fn constant int[] := array[1, 1, 1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 13];
  c_anchor constant text[] := array[
-- 1 review_and_dispatch_transfer: own, edited, the request's store ends
$a$  if v_req.status <> 'pending' then raise exception 'This request is % and can no longer be approved',v_req.status; end if;
$a$,
-- 2 review_and_dispatch_transfer: a line added in this review
$a$    else
      v_kind:=coalesce(nullif(v_entry->>'line_kind',''),case when nullif(v_entry->>'product_id','') is null then 'manual' else 'product' end);
$a$,
-- 3 review_and_dispatch_transfer: a quantity raised
$a$    if v_approved < 0 then raise exception 'Approved quantity cannot be negative'; end if;
$a$,
-- 4 review_and_dispatch_transfer: every store chosen as a source
$a$        if not exists(select 1 from public.stores s where s.id=v_src.source_id and s.deleted_at is null and coalesce(s.is_active,true)) then raise exception 'Invalid source store'; end if;
$a$,
-- 5 reject_transfer: the request's store ends
$a$  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;
$a$,
-- 6 resolve_transfer_discrepancy: received themselves, and every store involved
$a$  if v_req.status<>'received_with_discrepancy' then raise exception 'This transfer has no unresolved receipt discrepancy'; end if;
$a$,
-- 7 resolve_inventory_adjustment: own correction, and its store (on an approval)
$a$    raise exception 'This request is incomplete. Reject it and count again.'; end if;
$a$,
-- 8 resolve_invoice_action_v2: own request (on an approval)
$a$ -- A request raised before 295 has no derived plan and no line selection.
$a$,
-- 9 refund_invoice_recorded: the S$1,000 limit
$a$     to_char(i.cancel_refund_owed,'FM999999990.00'), i.invoice_no; end if;
 for x in select * from jsonb_array_elements(p_sources) loop
$a$,
-- 10 adjust_customer_credit: Owner only
$a$    raise exception 'Only an Owner or Manager can adjust customer credit';
  end if;
$a$,
-- 11 add_legacy_credit: Owner only
$a$    raise exception 'Only an Owner or Manager can enter old-client balances';
  end if;
$a$,
-- 12 reverse_credit_lot: Owner only
$a$    raise exception 'Only an Owner or Manager can reverse credit';
  end if;
$a$,
-- 13 affiliate_payout_save: Owner only
$a$ if not public.affiliate_payout_access(true) then raise exception 'Only active Owners and Managers can record or correct affiliate payouts.' using errcode='42501'; end if;
$a$,
-- 14 apply_line_foc: a credit package or premium bundle made free, Owner only
$a$      raise exception 'Only an Owner or Manager can make a Credit Package, Premium Bundle, voucher or therapy line free of charge.'
        using errcode = '42501'; end if;
$a$,
-- 15 transfer_invoice_unused_benefit: Owner only
$a$ if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct benefit recipients'; end if;
$a$,
-- 16 correct_invoice_payment: the S$1,000 limit
$a$ if m.is_wallet_credit and p_amount>v_refunded then
  select array_agg(id) into v_ids$a$,
-- 17 remove_invoice_payment: the S$1,000 limit
$a$  n := public.invoice_net_received(i.id);
$a$,
-- 18 split_invoice_payment: the S$1,000 limit
$a$    v_ids := v_ids || v_id;
  end loop;
$a$,
-- 19 record_affiliate_deduction_settlement: Owner only
$a$    raise exception 'Sign in as an Owner or Manager to mark a deduction as settled.' using errcode = '42501'; end if;
$a$,
-- 20 void_affiliate_deduction_settlement: Owner only
$a$    raise exception 'Sign in as an Owner or Manager to void a settlement.' using errcode = '42501'; end if;
$a$,
-- 21 create_staff_commission_payout: Owner only
$a$  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can mark staff commission paid'; end if;
$a$,
-- 22 correct_invoice_payment: into or out of wallet credit, Owner only
$a$ select * into old_m from public.payment_methods where id=p.payment_method_id;
$a$];
  c_new constant text[] := array[
-- 1 review_and_dispatch_transfer: own, edited, the request's store ends
$n$  if v_req.status <> 'pending' then raise exception 'This request is % and can no longer be approved',v_req.status; end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Another person approves",
  -- "Own stores only", "Transfers the Manager shaped"): a Manager does not review or dispatch a
  -- transfer they asked for or edited (an Owner or the other Manager does; an Owner still
  -- approves their own), adds no line and raises no quantity while approving (below), and
  -- approves only when every store involved is one they work at: here the request's ends, below
  -- every store chosen as a source. Warehouses are open to every Manager.
  if public.current_user_role() is distinct from 'owner' then
    if v_req.requested_by = auth.uid() then
      raise exception 'A Manager cannot approve their own transfer request. An Owner or another Manager approves it.' using errcode = '42501'; end if;
    if v_req.edited_by = auth.uid()
       or exists (select 1 from public.transfer_request_revisions rv533
                   where rv533.transfer_request_id = v_req.id and rv533.edited_by = auth.uid()) then
      raise exception 'A Manager who changed this transfer request cannot also approve it. An Owner or another Manager approves it.' using errcode = '42501'; end if;
    if (v_req.source_type = 'store' and not coalesce(v_req.source_id = any (public.current_user_store_ids()), false))
       or (v_req.dest_type = 'store' and not coalesce(v_req.dest_id = any (public.current_user_store_ids()), false)) then
      raise exception 'A Manager approves only for the stores they work at.' using errcode = '42501'; end if;
  end if;
$n$,
-- 2 review_and_dispatch_transfer: a line added in this review
$n$    else
      -- 533 (security audit of 17 Nov 2026, M9; "Transfers the Manager shaped"): only an Owner
      -- adds a line while approving.
      if public.current_user_role() is distinct from 'owner' then
        raise exception 'A Manager cannot add lines or raise quantities while approving a transfer. An Owner or another Manager approves such a change.' using errcode = '42501'; end if;
      v_kind:=coalesce(nullif(v_entry->>'line_kind',''),case when nullif(v_entry->>'product_id','') is null then 'manual' else 'product' end);
$n$,
-- 3 review_and_dispatch_transfer: a quantity raised
$n$    if v_approved < 0 then raise exception 'Approved quantity cannot be negative'; end if;
    -- 533 (security audit of 17 Nov 2026, M9; "Transfers the Manager shaped"): only an Owner
    -- approves more than was requested; lowering a quantity stays open.
    if v_approved > v_line.quantity and not coalesce(v_line.added_by_approver, false)
       and public.current_user_role() is distinct from 'owner' then
      raise exception 'A Manager cannot add lines or raise quantities while approving a transfer. An Owner or another Manager approves such a change.' using errcode = '42501'; end if;
$n$,
-- 4 review_and_dispatch_transfer: every store chosen as a source
$n$        if not exists(select 1 from public.stores s where s.id=v_src.source_id and s.deleted_at is null and coalesce(s.is_active,true)) then raise exception 'Invalid source store'; end if;
        -- 533 (security audit of 17 Nov 2026, M9): a store a Manager takes stock from is one they work at.
        if public.current_user_role() is distinct from 'owner'
           and not coalesce(v_src.source_id = any (public.current_user_store_ids()), false) then
          raise exception 'A Manager approves only for the stores they work at.' using errcode = '42501'; end if;
$n$,
-- 5 reject_transfer: the request's store ends
$n$  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Own stores only"): a
  -- Manager rejects only when every store at the request's ends is one they work at (their own
  -- request too). Warehouses are open to every Manager; an Owner rejects any.
  if public.current_user_role() is distinct from 'owner'
     and ((v_req.source_type = 'store' and not coalesce(v_req.source_id = any (public.current_user_store_ids()), false))
          or (v_req.dest_type = 'store' and not coalesce(v_req.dest_id = any (public.current_user_store_ids()), false))) then
    raise exception 'A Manager approves only for the stores they work at.' using errcode = '42501'; end if;
$n$,
-- 6 resolve_transfer_discrepancy: received themselves, and every store involved
$n$  if v_req.status<>'received_with_discrepancy' then raise exception 'This transfer has no unresolved receipt discrepancy'; end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Another person approves",
  -- "Own stores only"): a Manager does not resolve a transfer they received themselves (extra
  -- stock waiting since 510, or a shortage; an Owner or the other Manager does; an Owner still
  -- resolves their own), and resolves only when every store involved is one they work at: the
  -- request's ends and every store its lines were sent from. Warehouses are open to every Manager.
  if public.current_user_role() is distinct from 'owner' then
    if v_req.received_by = auth.uid() then
      raise exception 'A Manager cannot resolve a transfer they received themselves. An Owner or another Manager resolves it.' using errcode = '42501'; end if;
    if exists (select 1
                 from (select v_req.source_id as store_id where v_req.source_type = 'store'
                       union all select v_req.dest_id where v_req.dest_type = 'store'
                       union all select ls.source_id from public.transfer_line_sources ls
                                   join public.transfer_request_lines rl on rl.id = ls.line_id
                                  where rl.transfer_request_id = v_req.id and ls.source_type = 'store') x533
                where not coalesce(x533.store_id = any (public.current_user_store_ids()), false)) then
      raise exception 'A Manager approves only for the stores they work at.' using errcode = '42501'; end if;
  end if;
$n$,
-- 7 resolve_inventory_adjustment: own correction, and its store (on an approval)
$n$    raise exception 'This request is incomplete. Reject it and count again.'; end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Another person approves",
  -- "Own stores only"): a Manager does not approve a correction they asked for (an Owner or the
  -- other Manager does; an Owner still approves their own; a rejection, above, is as before),
  -- and approves one at a store only when they work there. Warehouses are open to every Manager.
  if public.current_user_role() is distinct from 'owner' then
    if v_req.requested_by = auth.uid() then
      raise exception 'A Manager cannot approve their own stock correction. An Owner or another Manager approves it.' using errcode = '42501'; end if;
    if v_loc_type = 'store' and not coalesce(v_loc_id = any (public.current_user_store_ids()), false) then
      raise exception 'A Manager approves only for the stores they work at.' using errcode = '42501'; end if;
  end if;
$n$,
-- 8 resolve_invoice_action_v2: own request (on an approval)
$n$ -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Another person approves"):
 -- a Manager does not approve a refund or cancellation request they raised (an Owner or the
 -- other Manager does; an Owner still approves their own; a rejection, above, is as before).
 -- The money an approval moves goes through refund_invoice_recorded and its S$1,000 limit.
 if r.requested_by=auth.uid() and public.current_user_role() is distinct from 'owner' then
  raise exception 'A Manager cannot approve their own request. An Owner or another Manager approves it.' using errcode='42501'; end if;

 -- A request raised before 295 has no derived plan and no line selection.
$n$,
-- 9 refund_invoice_recorded: the S$1,000 limit
$n$     to_char(i.cancel_refund_owed,'FM999999990.00'), i.invoice_no; end if;
 -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Up to S$1,000"): a Manager
 -- records a refund (here, or by approving a request) only while what was already taken back on
 -- the invoice (invoice_taken_back: refunds and lowered payments) and this refund come to at
 -- most S$1,000; above that an Owner records it. A retry with the same request id returned
 -- above and is not counted again; the invoice is locked, so two at once are counted in turn.
 if public.current_user_role() is distinct from 'owner'
    and public.invoice_taken_back(i.id)+v_total>1000 then
   raise exception 'A Manager can take back up to S$1,000 on an invoice, refunds and lowered payments together; an Owner does anything above that.' using errcode='42501'; end if;
 for x in select * from jsonb_array_elements(p_sources) loop
$n$,
-- 10 adjust_customer_credit: Owner only
$n$    raise exception 'Only an Owner or Manager can adjust customer credit';
  end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Owners only"): credit is
  -- added or removed by hand by an Owner only. Managers keep reading it.
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can add or remove credit by hand.' using errcode = '42501'; end if;
$n$,
-- 11 add_legacy_credit: Owner only
$n$    raise exception 'Only an Owner or Manager can enter old-client balances';
  end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Owners only"): credit is
  -- added by hand by an Owner only. Managers keep reading it.
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can add or remove credit by hand.' using errcode = '42501'; end if;
$n$,
-- 12 reverse_credit_lot: Owner only
$n$    raise exception 'Only an Owner or Manager can reverse credit';
  end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Owners only"): credit is
  -- removed by hand by an Owner only.
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can add or remove credit by hand.' using errcode = '42501'; end if;
$n$,
-- 13 affiliate_payout_save: Owner only
$n$ if not public.affiliate_payout_access(true) then raise exception 'Only active Owners and Managers can record or correct affiliate payouts.' using errcode='42501'; end if;
 -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Owners only"): an affiliate
 -- payout is recorded or corrected by an Owner only. Managers keep reading payouts.
 if public.current_user_role() is distinct from 'owner' then
  raise exception 'Only an Owner can record or correct an affiliate payout.' using errcode='42501'; end if;
$n$,
-- 14 apply_line_foc: a credit package or premium bundle made free, Owner only
$n$      raise exception 'Only an Owner or Manager can make a Credit Package, Premium Bundle, voucher or therapy line free of charge.'
        using errcode = '42501'; end if;
    -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Credit without a sale:
    -- Owners only"): a credit package or premium bundle line is made free by an Owner only (a
    -- voucher or therapy line stays with an Owner or Manager, as above).
    if v_li.line_kind in ('credit_package', 'premium_bundle') and v_role is distinct from 'owner' then
      raise exception 'Only an Owner can make a credit package or premium bundle line free.' using errcode = '42501'; end if;
$n$,
-- 15 transfer_invoice_unused_benefit: Owner only
$n$ if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct benefit recipients'; end if;
 -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Credit without a sale:
 -- Owners only"): unused credit or vouchers are moved to another customer by an Owner only.
 if public.current_user_role() is distinct from 'owner' then
  raise exception 'Only an Owner can move unused credit or vouchers to another customer.' using errcode='42501'; end if;
$n$,
-- 16 correct_invoice_payment: the S$1,000 limit
$n$ -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Up to S$1,000", refunds
 -- and lowered payments together): a payment a Manager lowers counts with the refunds; past
 -- S$1,000 taken back on the invoice (invoice_taken_back, read with the invoice locked, this
 -- change included) an Owner does it. A change of method or date alone, or a raise, lowers
 -- nothing.
 if public.current_user_role() is distinct from 'owner'
    and public.invoice_payment_lowered_by(p.id)>0 and public.invoice_taken_back(i.id)>1000 then
  raise exception 'A Manager can take back up to S$1,000 on an invoice, refunds and lowered payments together; an Owner does anything above that.' using errcode='42501'; end if;
 if m.is_wallet_credit and p_amount>v_refunded then
  select array_agg(id) into v_ids$n$,
-- 17 remove_invoice_payment: the S$1,000 limit
$n$  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Up to S$1,000", refunds
  -- and lowered payments together): a payment a Manager removes counts whole with the refunds;
  -- past S$1,000 taken back on the invoice (invoice_taken_back, read with the invoice locked,
  -- this removal included) an Owner does it.
  if public.current_user_role() is distinct from 'owner'
     and public.invoice_payment_lowered_by(p.id) > 0 and public.invoice_taken_back(i.id) > 1000 then
    raise exception 'A Manager can take back up to S$1,000 on an invoice, refunds and lowered payments together; an Owner does anything above that.' using errcode = '42501'; end if;
  n := public.invoice_net_received(i.id);
$n$,
-- 18 split_invoice_payment: the S$1,000 limit
$n$    v_ids := v_ids || v_id;
  end loop;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Up to S$1,000", refunds
  -- and lowered payments together): parts that come to less than the payment lower it by the
  -- difference, which counts with the refunds; past S$1,000 taken back on the invoice
  -- (invoice_taken_back, read with the invoice locked, this split included) an Owner does it.
  -- Parts that come to the whole payment lower nothing.
  if public.current_user_role() is distinct from 'owner'
     and public.invoice_payment_lowered_by(p.id) > 0 and public.invoice_taken_back(i.id) > 1000 then
    raise exception 'A Manager can take back up to S$1,000 on an invoice, refunds and lowered payments together; an Owner does anything above that.' using errcode = '42501'; end if;
$n$,
-- 19 record_affiliate_deduction_settlement: Owner only
$n$    raise exception 'Sign in as an Owner or Manager to mark a deduction as settled.' using errcode = '42501'; end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Owners only"): an affiliate
  -- repayment is recorded by an Owner only. Managers keep reading.
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can record or void an affiliate repayment.' using errcode = '42501'; end if;
$n$,
-- 20 void_affiliate_deduction_settlement: Owner only
$n$    raise exception 'Sign in as an Owner or Manager to void a settlement.' using errcode = '42501'; end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Owners only"): an affiliate
  -- repayment is voided by an Owner only. Managers keep reading.
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can record or void an affiliate repayment.' using errcode = '42501'; end if;
$n$,
-- 21 create_staff_commission_payout: Owner only
$n$  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can mark staff commission paid'; end if;
  -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026: "Owners only"): a staff
  -- commission payout is recorded by an Owner only. Managers keep reading.
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can record a staff commission payout.' using errcode = '42501'; end if;
$n$,
-- 22 correct_invoice_payment: into or out of wallet credit, Owner only
$n$ select * into old_m from public.payment_methods where id=p.payment_method_id;
 -- 533 (security audit of 17 Nov 2026, M9; the user, 20 Nov 2026, decision 10: "Owners only"):
 -- only an Owner changes a recorded payment into or out of wallet credit (a method whose
 -- is_wallet_credit differs from the old one's). From wallet to money it would put the credit
 -- back by hand; from money to wallet it would take credit in place of money received; neither
 -- is counted by the S$1,000 limit. A change between two money methods, or between two wallet
 -- methods, is as before.
 if coalesce(m.is_wallet_credit,false) is distinct from coalesce(old_m.is_wallet_credit,false)
    and public.current_user_role() is distinct from 'owner' then
  raise exception 'Only an Owner can change a payment into or out of wallet credit.' using errcode='42501'; end if;
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[18]);
  v_done int := 0; v_new_done int := 0; v_closed_done int := 0;
  v_acl text;
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '533: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if to_regclass('public.invoice_refunds') is null or to_regclass('public.invoice_payments') is null
     or to_regclass('public.transfer_line_sources') is null or to_regclass('public.transfer_request_lines') is null
     or to_regclass('public.transfer_request_revisions') is null then
    raise exception '533: a table it reads (invoice_refunds, invoice_payments, transfer_line_sources, transfer_request_lines, transfer_request_revisions) is missing'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '533: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '533: the grants of public.% are not the tested ones. Re-read them before applying.', c_sig[i]; end if;
    if md5(d) = c_after[i] then
      v_done := v_done + 1;
    elsif md5(d) = c_before[i] then
      v_def[i] := d;
    else
      raise exception '533: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is not null then
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
        raise exception '533: a function public.% is there, but not 533''s. Re-read it before applying.', c_new_sig[i]; end if;
      v_new_done := v_new_done + 1;
    end if;
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i]));
    if v_acl = c_closed_acl_after then v_closed_done := v_closed_done + 1;
    elsif v_acl is distinct from c_closed_acl_before then
      raise exception '533: the grants of public.% are not the tested ones (%). Re-read them before applying.', c_closed[i], v_acl; end if;
  end loop;
  if v_done = cardinality(c_sig) and v_new_done = cardinality(c_new_sig) and v_closed_done = cardinality(c_closed) then
    raise exception '533 is already in on this database; nothing was changed.'; end if;
  if v_done > 0 or v_new_done > 0 or v_closed_done > 0 then
    raise exception '533: only part of it is in on this database (% of % functions patched, % of % helpers, % of % grants closed). Re-read them before applying; nothing was changed.',
      v_done, cardinality(c_sig), v_new_done, cardinality(c_new_sig), v_closed_done, cardinality(c_closed); end if;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
      raise exception '533: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_after[i] then
      raise exception '533: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
    if position('533 (security audit' in v_def[i]) = 0 then
      raise exception '533: the patched text of public.% has no 533 marker', c_sig[i]; end if;
  end loop;

  -- 2. Install: the helpers first (the patched functions call them)
  for i in 1 .. cardinality(c_new_sig) loop
    execute c_new_def[i];
    execute format('revoke all on function public.%s from public, anon, authenticated', c_new_sig[i]);
    execute format('grant execute on function public.%s to service_role', c_new_sig[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    execute format('revoke execute on function public.%s from authenticated', c_closed[i]);
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '533: public.% was made with an md5 other than the tested one (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_new_sig[i]), 'execute')
       or has_function_privilege('anon', to_regprocedure('public.' || c_new_sig[i]), 'execute') then
      raise exception '533: public.% can be called by a login', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '533: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '533: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i])) is distinct from c_closed_acl_after
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_closed[i]), 'execute')
       or has_function_privilege('anon', to_regprocedure('public.' || c_closed[i]), 'execute') then
      raise exception '533: public.% can still be called by a signed-in login', c_closed[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '533: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
