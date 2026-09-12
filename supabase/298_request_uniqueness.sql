begin;
-- =====================================================================
-- TWO GUARDS THAT ONLY HELD WHEN NOBODY WAS IN A HURRY
--
-- request_invoice_action_v2() checked, in ordinary SELECTs, that the same
-- request id had not already been used and that the invoice had no other
-- pending request. Both checks read without a lock, so simultaneous
-- submissions all saw "nothing there" and all inserted.
--
-- Found by scripts/invoice-actions/tests/concurrency.mjs: four sessions
-- submitting the same request id at the same instant produced FOUR approval
-- requests for one invoice. A double-tap on a phone with a slow connection is
-- enough to do it, and the result is two approvers acting on the same invoice.
--
-- Checks in application code cannot fix this; only the database can. Two
-- partial unique indexes make it impossible, and the function now treats a
-- unique violation as what it is -- a duplicate submission -- and returns the
-- request that won rather than an error.
--
-- Requires 295. Idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Existing duplicates are closed before the rule is imposed, not deleted.
--
-- A pending request has changed nothing by definition -- no refund, no stock,
-- no benefit -- so the extra copies can be closed as superseded, with a reason,
-- leaving the earliest one to be decided on its merits. Approved and rejected
-- requests are never touched: they are history.
-- ---------------------------------------------------------------------
with ranked as (
  select id, row_number() over (
           partition by payload->>'request_id' order by created_at, id) rn
    from public.approval_requests
   where request_type in ('invoice_cancel','invoice_refund')
     and status='pending' and payload->>'request_id' is not null)
update public.approval_requests a
   set status='rejected',
       rejection_reason='Superseded: a duplicate of the same submission, closed when duplicate submissions were made impossible.',
       response_note='Closed by migration 298'
  from ranked r where r.id=a.id and r.rn>1;

with ranked as (
  select id, row_number() over (
           partition by related_record_id order by created_at, id) rn
    from public.approval_requests
   where request_type in ('invoice_cancel','invoice_refund') and status='pending')
update public.approval_requests a
   set status='rejected',
       rejection_reason='Superseded: another request for the same invoice was already waiting; raise a fresh one if it is still needed.',
       response_note='Closed by migration 298'
  from ranked r where r.id=a.id and r.rn>1;

-- The same submission, however many times it is sent, is one LIVE request.
--
-- Scoped to pending rows deliberately. The race being closed is concurrent
-- INSERTs, and those are always pending; a resubmission after a decision is
-- caught by the function's ordinary lookup, which reads every status. Scoping
-- it this way also means the index never fights historical rows, which are
-- records of what happened and are not rewritten to suit a new rule.
create unique index if not exists approval_requests_invoice_request_id_key
  on public.approval_requests ((payload->>'request_id'))
  where request_type in ('invoice_cancel','invoice_refund')
    and status='pending' and payload->>'request_id' is not null;

-- One invoice, one thing waiting for a decision.
create unique index if not exists approval_requests_one_pending_per_invoice_key
  on public.approval_requests (related_record_id)
  where status='pending' and request_type in ('invoice_cancel','invoice_refund');

do $do$
declare f text; a text; b text;
begin
 select pg_get_functiondef('public.request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)'::regprocedure) into f;
 if position('unique_violation' in f)>0 then
  raise notice 'request submission already survives a race'; return; end if;

 -- Wrap ONLY the insert, so the handler cannot swallow anything else.
 a:=' insert into public.approval_requests(request_type,status,requested_by,related_record_id,reason,payload)';
 b:=' returning id into v_req;';
 if position(a in f)=0 or position(b in f)=0 then
  raise exception 'request_invoice_action_v2 does not match what 298 expects - align it by hand'; end if;

 f:=replace(f,a,' begin'||E'\n'||a);
 f:=replace(f,b,b||E'\n'||
'  exception when unique_violation then'||E'\n'||
'   -- An identical submission won the race. Return the one that landed.'||E'\n'||
'   select * into v_existing from public.approval_requests'||E'\n'||
'    where request_type in (''invoice_cancel'',''invoice_refund'') and status=''pending'''||E'\n'||
'      and (payload->>''request_id''=p_request_id::text or related_record_id=p_invoice_id)'||E'\n'||
'    order by case when payload->>''request_id''=p_request_id::text then 0 else 1 end, created_at limit 1;'||E'\n'||
'   if not found then raise; end if;'||E'\n'||
'   if v_existing.payload->>''request_id'' is distinct from p_request_id::text then'||E'\n'||
'    raise exception ''A request for this invoice is already waiting for approval''; end if;'||E'\n'||
'   return jsonb_build_object(''request_id'',v_existing.id,''status'',v_existing.status,'||E'\n'||
'     ''plan'',v_existing.payload->''plan'',''replayed'',true);'||E'\n'||
'  end;');
 execute f;
 raise notice 'duplicate submissions now resolve to one request instead of racing';
end $do$;

notify pgrst,'reload schema';
commit;
