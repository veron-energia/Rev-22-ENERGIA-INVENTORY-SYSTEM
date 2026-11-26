-- 542_refund_requests_read_by_their_rule_and_refund_stock_follows_its_lines.sql
--
-- A REFUND OR CANCELLATION REQUEST'S DETAILS ARE READ BY AN OWNER, A MANAGER OF THE INVOICE'S
-- STORE AND THE STAFF MEMBER WHO RAISED IT; THE STOCK ANSWERS GIVEN WITH A REFUND ARE FOR THE REFUNDED LINES; A WAITING REQUEST
-- APPROVED BY A DIRECT ACTION GETS ITS APPROVAL ENTRY IN THE AUDIT LOG
--
--   From the security audit of 17 Nov 2026 (Low finding L20). The BEFORE md5s and the relied-on
--   md5s below are those of production after 540 (head 20261125171841, function fingerprint
--   18fcffcae0f51cc09245231c3779585e/1462; 540's AFTER md5s of invoice_action_request_detail and
--   resolve_invoice_action_v2 are their BEFORE md5s here). 542 changes none of 541's functions and
--   needs only 540; apply it after 541.
--   If production differs when this is applied, it refuses and changes nothing.
--   (The number 542 is this file's name and its errors' prefix; if it changes at commit, change it
--   there, in the 542 comments it writes into the functions below (and so their AFTER md5s, also in
--   scripts/invoice-actions/undo-542.sql and in the suites that know them), and in the name and
--   path of its suite.)
--
-- GO-LIVE: any time after 540 (after 541 by number); no page needs to change. The pages ask for a
--   request's details only as an Owner or a Manager (ApprovalsPage, and the invoice's guided
--   action with canApprove); Staff are told a request is waiting by invoice_request_status, which
--   is not changed. The Approvals page reads approval_requests itself: after 542 a Manager's list
--   holds the invoice requests of their own stores (the only ones they can approve; the others
--   were refused at approval already), and the Dashboard's count of waiting requests follows. The
--   direct refund panel and the guided flow send stock answers only for the lines they refund.
--
-- WHAT WAS WRONG
--
--   1. invoice_action_request_detail (297) gives any staff login with access to the invoice's
--      store a refund or cancellation request's reason, return notes, plans and outcome. 297 states
--      the rule above the function ("What an approver is shown, and who may see it") and in its
--      COMMENT ("Everything an Owner/Manager needs to decide an invoice request ... with store scope
--      enforced"): an Owner, or a Manager with access to the invoice's store. The user, 26 Nov 2026
--      ("Requester sees own"): and the member of staff who raised the request sees that request.
--      Two other roads give the same details more widely: the read rule of approval_requests
--      ("read own or manager+", 407) gives an Admin and every Manager, of any store, every invoice
--      request's reason and payload (its lines, plan, outcome); and resolve_invoice_action_v2 tells
--      any Owner or Manager what a resolved request did before it checks the invoice's store.
--   2. refund_invoice_recorded (496) takes a stock answer for an ordinary product (an invoice's
--      store_sale deduction) whatever lines the refund is for, so refunding one line could put
--      back on the shelf, or write off, the stock of a line still billed. And a product or
--      promotion line refunded with no stock answer was refused while ANY product deduction of the
--      invoice was unanswered, also another line's, so the only way through was an answer for
--      that other line.
--   3. The trigger complete_invoice_finance_request (295) marks a waiting request approved when a
--      refund closes the invoice out, or when the invoice is cancelled, with no approval entry in
--      the Audit Log (resolve_invoice_action_v2 writes one when the request itself is approved).
--
-- WHAT THIS DOES
--
--   * invoice_action_request_detail: after 540's guard (still its first statement) and its store
--     check (kept: user_has_store_access, so a Manager only at their stores), an Owner, a Manager,
--     or the caller who raised this request (requested_by). Anyone else, other Staff of the store
--     and an Admin among them: "Invoice request not accessible", as for a store they cannot reach.
--     Its answer is unchanged.
--   * approval_requests, its read rule "read approval requests": for an invoice request
--     (invoice_cancel, invoice_refund) its requester while active staff, as before, an Owner, or a
--     Manager with access to the invoice's store; for every other request (transfers, stock
--     corrections, payouts and the rest) as before: its requester while active staff, or an Owner,
--     an Admin or a Manager.
--   * resolve_invoice_action_v2: for a request already resolved, the invoice's store is checked
--     before its outcome is returned ("Invoice not accessible"), as it already was for one still
--     waiting. Everything else in it word for word as before.
--   * A new helper only postgres can call, invoice_line_holds_stock(line, product): whether the
--     invoice's stock of that product is the line's to answer for. A product line holds its own
--     product; a promotion line the products of its promotion (invoice_line_stock_products, as
--     the guided plan offers them, 361); and a product or promotion line also holds a product that
--     no product or promotion line of the invoice holds (on production 9 unanswered deductions of
--     6 paid invoices and 1 refunded one are such: a promotion edited after the sale, say), so
--     such stock can still be answered for.
--   * refund_invoice_recorded:
--       - a stock answer for a store_sale deduction must be for a product held by a line of this
--         refund (p_lines with invoice_item_id, by the helper); otherwise: 'Answer for the stock of
--         the lines being refunded: "<product>" is not on a line this refund covers. Nothing was
--         recorded.' Special sale units keep 496's own rule, which already ties them to their
--         line; quantities keep their rule (at most what is still unanswered on the deduction).
--       - the matching half: a product or promotion line refunded with no stock answer at all is
--         refused only while a deduction of ITS OWN stock (by the helper) is unanswered, not
--         another line's. A call this refused before only because another line's stock was
--         unanswered now goes through; nothing else it accepts or refuses changes.
--   * complete_invoice_finance_request: the same requests marked approved, with the same note, and
--     for each one a direct action approved, one Audit Log entry invoice_action_approved (table
--     approval_requests, module invoices, the invoice's store), old_data the request as it was,
--     new_data {status approved, approved_by, response_note, direct_action refund (with the
--     refund's row and request id) or cancellation}. A request approved through its own approval
--     gets no second entry: a refund recorded under the request's own id, or a cancellation whose
--     invoice revision carries the request's id (cancel_invoice_recorded, called by
--     resolve_invoice_action_v2 with it).
--   * Every function this creates or replaces has search_path public, pg_temp.
--
-- WHAT STAYS
--
--   * invoice_request_status: Staff of the store still see that a request waits, by whom, and an
--     approver's rejection reason; it gives no requester's reason or plan (417).
--   * request_invoice_action_v2's replay of a repeated request id returns the plan that request
--     was raised with; any staff member of the store gets the same plan from invoice_action_plan,
--     so it is not narrowed. It returns no reason.
--   * The Audit Log's invoice_action_requested entries carry the requester's reason; who reads the
--     Audit Log is not changed here.
--   * Every correct refund: the guided plan's stock (each movement offered under a line of the
--     refund), the direct panel's answers for the refunded lines, replays of a request id.
--   * How many units an answer may cover (sellable, damaged and not returned together, at most
--     what is still unanswered on the deduction): not tied to the quantity refunded on the line.
--   * The trigger's tables, timing and the requests it approves.
--
-- UNDO
--
--   scripts/invoice-actions/undo-542.sql (it refuses unless every function here is exactly 542's
--   and nothing else calls the new helper): puts the four functions and the read rule of
--   approval_requests back exactly as they were and drops invoice_line_holds_stock. Audit Log entries written since 542 stay. Run it BEFORE
--   scripts/customers/undo-540.sql. A later migration changing any of these must pin 542's AFTER
--   md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/invoice-actions/tests/refund-request-rules-542.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions 542 relies on, as tested: the role and store tests, the audit writer, 540's guard,
  -- the promotion's products, the charge total the trigger reads, and cancel_invoice_recorded,
  -- whose invoice revision carries the request id the trigger counts on (resolve_invoice_action_v2,
  -- which writes the approval's own entry, is patched below and pinned there).
  c_relied constant text[] := array[
    'current_user_role()',
    'is_manager_or_above()',
    'user_has_store_access(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'inventory_manager_guard(text)',
    'invoice_line_stock_products(uuid)',
    'invoice_charge_total(uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)'];
  c_relied_md5 constant text[] := array[
    '519b0a33a3548f970c5d585b6e76a389',
    'e87f6da4a7284374f0e2bc5b55c502be',
    '708992afaa6c3951f6329239b742987c',
    'c705c733e213a27f0dc32d54322cc855',
    '6a2c8611ef58a1e6cdf4a91a0c662c9e',
    '5ed49163d183fa5ec05673a1bb85e863',
    '8297147511ba285db2279598f3d727fb',
    '5490e4b48dfdab63b6dc5a0aa78d4bc7'];
  -- The functions patched: BEFORE, AFTER, grants (unchanged).
  c_sig constant text[] := array[
    'invoice_action_request_detail(uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'complete_invoice_finance_request()',
    'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)'];
  c_before constant text[] := array[
    'c91613824dc7894cc3fc933898f5678c',
    '4f81d244db8f8c5b6d35143456fa8cc7',
    '9df7e408a0053d14a23e5b58ea9e5780',
    'd1ab83e457684ad3d010dd5a92719570'];
  c_after constant text[] := array[
    'd70250367385b0dec1ea5273d85e796c',
    '7802bc26966f422978e2b764b289944f',
    'ce65794aff1f9e1f3953a82012dc377e',
    'beb94a98887d55d8698a830f489e1225'];
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_sp_old constant text := E' SET search_path TO ''public''\n';
  c_sp_new constant text := E' SET search_path TO ''public'', ''pg_temp''\n';
  -- The two triggers that run complete_invoice_finance_request, relied on as they are.
  c_trg constant text[] := array[
    'CREATE TRIGGER invoice_refund_request_completed AFTER INSERT ON public.invoice_refunds FOR EACH ROW EXECUTE FUNCTION complete_invoice_finance_request()',
    'CREATE TRIGGER invoice_cancel_request_completed AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION complete_invoice_finance_request()'];
  -- The patches, each found exactly once in its function (c_fn: its place in c_sig).
  c_fn constant int[] := array[1, 2, 2, 3, 4];
  c_anchor constant text[] := array[
-- 1 invoice_action_request_detail: the request's rule
$a$ if not found or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice request not accessible'; end if;
$a$,
-- 2 refund_invoice_recorded: a line refunded with no answer waits only on its own stock
$a$    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'
$a$,
-- 3 refund_invoice_recorded: an answer is for a refunded line's stock
$a$   if not found then raise exception 'Stock return must reference an actual invoice deduction'; end if;
$a$,
-- 4 complete_invoice_finance_request
$a$begin
 if tg_table_name='invoice_refunds' then
  update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
    response_note='Refund recorded with line, payment-source and stock evidence; request '||new.request_id
    where related_record_id=new.invoice_id and request_type='invoice_refund' and status='pending'
      and (id=new.request_id or public.invoice_charge_total(new.invoice_id)<=0);
 elsif new.status='cancelled' then
  update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
    response_note='Audited cancellation recorded'
    where related_record_id=new.id and request_type='invoice_cancel' and status='pending';
 end if;
 return new;
$a$,
-- 5 resolve_invoice_action_v2: a resolved request's outcome, store first
$a$ if r.status<>'pending' then
  return jsonb_build_object('request_id',r.id,'status',r.status,'already_resolved',true,$a$];
  c_new constant text[] := array[
-- 1
$n$ if not found or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice request not accessible'; end if;
 -- 542 (security audit of 17 Nov 2026, L20; the user, 26 Nov 2026: "Requester sees own"): as
 -- 297 states it ("What an approver is shown, and who may see it"): an Owner, or a Manager with
 -- access to the invoice's store (above), and the member of staff who raised this request.
 -- Anyone else, other Staff of the store and an Admin among them, is refused.
 if coalesce(public.current_user_role()::text, '') not in ('owner', 'manager')
    and r.requested_by is distinct from auth.uid() then
  raise exception 'Invoice request not accessible'; end if;
$n$,
-- 2
$n$    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'
      -- 542 (security audit of 17 Nov 2026, L20): this line's own stock, as the answers below are
      -- held to it; another line's unanswered stock does not hold this line up.
      and public.invoice_line_holds_stock(it.id,qs.product_id)
$n$,
-- 3
$n$   if not found then raise exception 'Stock return must reference an actual invoice deduction'; end if;
   -- 542 (security audit of 17 Nov 2026, L20): an answer is for the stock of a line this refund is
   -- for (its product, its promotion's products, or stock no line holds), never a line still billed.
   if not exists(select 1 from jsonb_array_elements(p_lines) pl
                  where nullif(pl->>'invoice_item_id','') is not null
                    and public.invoice_line_holds_stock((pl->>'invoice_item_id')::uuid,sm.product_id)) then
     raise exception 'Answer for the stock of the lines being refunded: "%" is not on a line this refund covers. Nothing was recorded.',
       (select pr.name from public.products pr where pr.id=sm.product_id); end if;
$n$,
-- 4
$n$declare ar public.approval_requests%rowtype; v_note text;
begin
 -- 542 (security audit of 17 Nov 2026, L20): a waiting request marked approved here by a direct
 -- action (a refund that closes the invoice out, or a cancellation made outside the request) gets
 -- the approval's Audit Log entry, invoice_action_approved, as resolve_invoice_action_v2 writes
 -- one. The request's own approval writes its entry itself, so none here for it: a refund recorded
 -- under the request's id, or a cancellation whose invoice revision carries it.
 if tg_table_name='invoice_refunds' then
  v_note:='Refund recorded with line, payment-source and stock evidence; request '||new.request_id;
  for ar in select * from public.approval_requests
             where related_record_id=new.invoice_id and request_type='invoice_refund' and status='pending'
               and (id=new.request_id or public.invoice_charge_total(new.invoice_id)<=0)
             order by id for update loop
   update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
     response_note=v_note
    where id=ar.id;
   if ar.id is distinct from new.request_id then
    perform public.write_audit_ex('approval_requests',ar.id,'invoice_action_approved',to_jsonb(ar),
      jsonb_build_object('status','approved','approved_by',auth.uid(),'response_note',v_note,
        'direct_action','refund','invoice_refund_id',new.id,'refund_request_id',new.request_id),
      'invoices',v_note,(select iv.store_id from public.invoices iv where iv.id=new.invoice_id));
   end if;
  end loop;
 elsif new.status='cancelled' then
  v_note:='Audited cancellation recorded';
  for ar in select * from public.approval_requests
             where related_record_id=new.id and request_type='invoice_cancel' and status='pending'
             order by id for update loop
   update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
     response_note=v_note
    where id=ar.id;
   if not exists (select 1 from public.invoice_revisions rv where rv.invoice_id=new.id and rv.request_id=ar.id) then
    perform public.write_audit_ex('approval_requests',ar.id,'invoice_action_approved',to_jsonb(ar),
      jsonb_build_object('status','approved','approved_by',auth.uid(),'response_note',v_note,
        'direct_action','cancellation'),
      'invoices',v_note,new.store_id);
   end if;
  end loop;
 end if;
 return new;
$n$,
-- 5
$n$ if r.status<>'pending' then
  -- 542 (security audit of 17 Nov 2026, L20): what a resolved request did is told only to an Owner
  -- or a Manager with access to the invoice's store, as for one still waiting (below).
  if not public.user_has_store_access((select iv.store_id from public.invoices iv where iv.id=r.related_record_id)) then
   raise exception 'Invoice not accessible'; end if;
  return jsonb_build_object('request_id',r.id,'status',r.status,'already_resolved',true,$n$];
  -- approval_requests' read rule: before, the source given to alter policy, and after (as
  -- pg_get_expr prints it). Invoice requests follow 297's rule; other requests as before.
  c_pol_name constant text := 'read approval requests';
  c_pol_before constant text := '(((requested_by = ( SELECT auth.uid() AS uid)) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR ( SELECT is_manager_or_above() AS is_manager_or_above))';
  c_pol_src constant text := $p$((requested_by = (select auth.uid())) and ((select public.current_user_role()) is not null))
    or ((request_type <> all (array['invoice_cancel', 'invoice_refund'])) and (select public.is_manager_or_above()))
    or ((request_type = any (array['invoice_cancel', 'invoice_refund']))
        and (((select public.current_user_role()) = 'owner'::public.user_role)
             or (((select public.current_user_role()) = 'manager'::public.user_role)
                 and exists (select 1 from public.invoices iv
                              where iv.id = approval_requests.related_record_id and public.user_has_store_access(iv.store_id)))))$p$;
  c_pol_after constant text := $q$(((requested_by = ( SELECT auth.uid() AS uid)) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR ((request_type <> ALL (ARRAY['invoice_cancel'::text, 'invoice_refund'::text])) AND ( SELECT is_manager_or_above() AS is_manager_or_above)) OR ((request_type = ANY (ARRAY['invoice_cancel'::text, 'invoice_refund'::text])) AND ((( SELECT current_user_role() AS current_user_role) = 'owner'::user_role) OR ((( SELECT current_user_role() AS current_user_role) = 'manager'::user_role) AND (EXISTS ( SELECT 1
   FROM invoices iv
  WHERE ((iv.id = approval_requests.related_record_id) AND user_has_store_access(iv.store_id))))))))$q$;
  -- The new helper: postgres's alone (refund_invoice_recorded, a definer, calls it).
  c_new_sig constant text := 'invoice_line_holds_stock(uuid,uuid)';
  c_new_def constant text :=
$d$CREATE OR REPLACE FUNCTION public.invoice_line_holds_stock(p_invoice_item_id uuid, p_product_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 542 (security audit of 17 Nov 2026, L20): whether the invoice's stock of this product is this
  -- line's to answer for in a refund. A product line holds its own product; a promotion line the
  -- products of its promotion (invoice_line_stock_products, as the guided plan offers them, 361).
  -- A product that no product or promotion line of the invoice holds (stock taken for a promotion
  -- edited since, say) is held by each of its product and promotion lines, so it can still be
  -- answered for. Any other line holds no stock here.
  select exists (
    select 1 from public.invoice_items it
     where it.id = p_invoice_item_id
       and it.line_kind::text in ('product', 'promotion')
       and (   (it.line_kind::text = 'product' and it.product_id = p_product_id)
            or (it.line_kind::text = 'promotion' and p_product_id in (select public.invoice_line_stock_products(it.id)))
            or not exists (
                 select 1 from public.invoice_items o
                  where o.invoice_id = it.invoice_id
                    and (   (o.line_kind::text = 'product' and o.product_id = p_product_id)
                         or (o.line_kind::text = 'promotion'
                             and p_product_id in (select public.invoice_line_stock_products(o.id)))))))
$function$
$d$;
  c_new_md5 constant text := 'dbec8434a00e2969cf41c7145be440af';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[cardinality(c_sig)]);
  v_done int := 0; v_new_done int := 0; v_pol_done int := 0; v_bad text := ''; d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function or table waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '542: public.% is missing or not the version this was tested against (540 must be in). Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  for i in 1 .. cardinality(c_trg) loop
    if not exists (select 1 from pg_trigger t where not t.tgisinternal and t.tgenabled = 'O'
                    and pg_get_triggerdef(t.oid) = c_trg[i]) then
      raise exception '542: the trigger "%" is not there as tested. Re-read it before applying.', c_trg[i]; end if;
  end loop;
  if (select count(*) from pg_trigger t where not t.tgisinternal
       and t.tgfoid = to_regprocedure('public.complete_invoice_finance_request()')) <> cardinality(c_trg) then
    raise exception '542: complete_invoice_finance_request() runs from triggers other than the tested two. Re-read them before applying.'; end if;
  if to_regclass('public.invoice_revisions') is null
     or not exists (select 1 from pg_attribute a where a.attrelid = 'public.invoice_revisions'::regclass
                     and a.attname = 'request_id' and a.atttypid = 'uuid'::regtype and not a.attisdropped) then
    raise exception '542: public.invoice_revisions has no request_id uuid. Re-read it before applying.'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '542: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '542: the grants of public.% are not the tested ones. Re-read them before applying.', c_sig[i]; end if;
    if md5(d) = c_after[i] then
      v_done := v_done + 1;
    elsif md5(d) = c_before[i] then
      v_def[i] := d;
    else
      raise exception '542: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  if (select count(*) from pg_policy p where p.polrelid = 'public.approval_requests'::regclass and p.polcmd in ('r', '*')) <> 1
     or not exists (select 1 from pg_policy p where p.polrelid = 'public.approval_requests'::regclass and p.polname = c_pol_name
                     and p.polcmd = 'r' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid]
                     and pg_get_expr(p.polqual, p.polrelid) in (c_pol_before, c_pol_after)) then
    raise exception '542: the read rule of public.approval_requests is not the one this was tested against. Re-read it before applying.'; end if;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.approval_requests'::regclass and p.polname = c_pol_name) = c_pol_after then
    v_pol_done := 1; end if;
  if to_regprocedure('public.' || c_new_sig) is not null then
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig))) <> c_new_md5 then
      raise exception '542: a function public.% is there, but not 542''s. Re-read it before applying.', c_new_sig; end if;
    v_new_done := 1;
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'invoice_line_holds_stock'
              and p.oid::regprocedure::text <> c_new_sig) then
    raise exception '542: another function named invoice_line_holds_stock is there. Re-read it before applying.'; end if;
  if v_done = cardinality(c_sig) and v_new_done = 1 and v_pol_done = 1 then
    raise exception '542 is already in on this database; nothing was changed.'; end if;
  if v_done > 0 or v_new_done > 0 or v_pol_done > 0 then
    raise exception '542: only part of it is in on this database (% of % functions patched, % of 1 new function, % of 1 read rule). Re-read them before applying; nothing was changed.',
      v_done, cardinality(c_sig), v_new_done, v_pol_done; end if;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
      raise exception '542: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if (length(v_def[i]) - length(replace(v_def[i], c_sp_old, ''))) / length(c_sp_old) <> 1 then
      raise exception '542: public.% has no single search_path public', c_sig[i]; end if;
    v_def[i] := replace(v_def[i], c_sp_old, c_sp_new);
    if md5(v_def[i]) <> c_after[i] then v_bad := v_bad || format(E'\n%s=%s', c_sig[i], md5(v_def[i])); end if;
  end loop;
  if md5(c_new_def) <> c_new_md5 then v_bad := v_bad || format(E'\nnew:%s=%s', c_new_sig, md5(c_new_def)); end if;
  if v_bad <> '' then
    raise exception '542: the patched text is not the tested one:%', v_bad; end if;

  -- 2. Install: the helper first (refund_invoice_recorded calls it)
  execute c_new_def;
  execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig);
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  execute format('alter policy %I on public.approval_requests using (%s)', c_pol_name, c_pol_src);

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '542: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i]
       or (select p.proconfig from pg_proc p where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from array['search_path=public, pg_temp'] then
      raise exception '542: the grants or the search path of public.% are not the tested ones', c_sig[i]; end if;
  end loop;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig))) <> c_new_md5
     or (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
          where p.oid = to_regprocedure('public.' || c_new_sig)) is distinct from 'postgres=X/postgres'
     or has_function_privilege('anon', to_regprocedure('public.' || c_new_sig), 'execute')
     or has_function_privilege('authenticated', to_regprocedure('public.' || c_new_sig), 'execute') then
    raise exception '542: public.% was made other than tested', c_new_sig; end if;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.approval_requests'::regclass and p.polname = c_pol_name) is distinct from c_pol_after then
    raise exception '542: the read rule of public.approval_requests is not the tested one after installing: %',
      (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
        where p.polrelid = 'public.approval_requests'::regclass and p.polname = c_pol_name); end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '542: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
