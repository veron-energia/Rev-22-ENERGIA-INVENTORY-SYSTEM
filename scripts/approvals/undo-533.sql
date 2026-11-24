-- UNDO of 533 (with the user's go-ahead). It puts the eighteen functions 533 patched back exactly
-- as they were before 533 (md5s below), by taking 533's text out again; drops the two helpers 533
-- made (invoice_payment_lowered_by, invoice_taken_back); and grants EXECUTE on
-- cancel_invoice_recorded and on request_inventory_adjustment(location_type, uuid, uuid,
-- integer, text, text) to authenticated again. Afterwards a Manager can again approve their own
-- transfer (also one they edited, adding lines and raising quantities), stock correction and
-- invoice request, resolve a transfer they received, approve for any store, take back any amount
-- on an invoice, add or remove credit by hand, make a credit package or bundle free, move unused
-- credit or vouchers to another customer, and record payouts and repayments; and a signed-in
-- login can call the two closed functions straight (the security audit's M9 open again).
-- Nothing written while 533 was in changes.
--
-- FIRST put back the pages of before 533 if they were changed for it.
--
-- It refuses, with nothing changed, unless each of the eighteen functions and the two helpers is
-- exactly 533's (so a later version is never overwritten), no other function calls the helpers,
-- the grants are as tested, and the two closed functions' grants are 533's. One transaction, all
-- or nothing; it waits at most 5 seconds for a lock. The 533 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row (found by
-- its name, 533_approvals_need_another_person_and_owner_limits) or record this UNDO beside it.
do $undo$
declare
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
  c_533 constant text[] := array[
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
  c_before_533 constant text[] := array[
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
  c_new_sig constant text[] := array[
    'invoice_payment_lowered_by(uuid)',
    'invoice_taken_back(uuid)'];
  c_new_md5 constant text[] := array[
    '5502cb18da573d7b3132078bb0dbbde1',
    '7bc3edff2b0307ea2fca9d9b7e8fa58b'];
  c_closed constant text[] := array[
    'cancel_invoice_recorded(uuid,text,uuid)',
    'request_inventory_adjustment(location_type,uuid,uuid,integer,text,text)'];
  c_closed_acl_533 constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_closed_acl_before constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  -- The patches, as 533 made them: c_new is 533's text, c_anchor what it replaced.
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
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);
  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      raise exception 'undo 533: public.% is missing. Nothing was changed.', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_before_533[i] then
      raise exception 'undo 533: public.% is already its version of before 533; 533 is not in. Nothing was changed.', c_sig[i]; end if;
    if md5(d) <> c_533[i] then
      raise exception 'undo 533: public.% is not 533''s version (md5 %). Nothing was changed.', c_sig[i], md5(d); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo 533: the grants of public.% are not the tested ones. Nothing was changed.', c_sig[i]; end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception 'undo 533: public.% is missing or not 533''s. Nothing was changed.', c_new_sig[i]; end if;
  end loop;
  -- No function but 533's own calls the helpers.
  select string_agg(p.oid::regprocedure::text, ', ') into d
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (c_sig) and p.oid::regprocedure::text <> all (c_new_sig)
     and (position('invoice_taken_back' in pg_get_functiondef(p.oid)) > 0
          or position('invoice_payment_lowered_by' in pg_get_functiondef(p.oid)) > 0);
  if d is not null then
    raise exception 'undo 533: 533''s helpers are also used by %. Nothing was changed.', d; end if;
  for i in 1 .. cardinality(c_closed) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i])) is distinct from c_closed_acl_533 then
      raise exception 'undo 533: the grants of public.% are not 533''s. Nothing was changed.', c_closed[i]; end if;
  end loop;
  for i in reverse cardinality(c_fn) .. 1 loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'undo 533: 533''s text % is not found exactly once in public.%. Nothing was changed.', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before_533[i] then
      raise exception 'undo 533: public.% without 533''s text is not its version of before 533 (md5 %). Nothing was changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;
  -- 2. Put back, then drop the helpers (nothing calls them any more)
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    execute format('drop function public.%s', c_new_sig[i]);
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    execute format('grant execute on function public.%s to authenticated', c_closed[i]);
  end loop;
  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before_533[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo 533: public.% is not as before 533 after putting it back', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i])) is distinct from c_closed_acl_before then
      raise exception 'undo 533: the grants of public.% are not as before 533', c_closed[i]; end if;
  end loop;
  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
