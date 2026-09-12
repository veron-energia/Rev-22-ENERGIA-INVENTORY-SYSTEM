begin;
-- =====================================================================
-- GUIDED REFUNDS AND CANCELLATIONS
--
-- The refund and cancellation ENGINES were already correct and complete:
-- refund_invoice_recorded() allocates to lines, original payment sources,
-- recorded benefit values and actual stock deductions, is idempotent on its
-- request id, and refuses to exceed what is still refundable.
-- cancel_invoice_recorded() clears the charge and leaves payments in history.
-- Neither is replaced here. Nothing about how money moves changes.
--
-- What was missing was everything AROUND them:
--
--   * Staff had to choose internal ledger records -- benefit value rows,
--     stock movement ids, payment source rows -- to describe a refund.
--   * A request captured only a reason and a return_stock boolean. It could
--     not say WHICH lines, how many, or how much.
--   * Submitting a request moved the invoice to 'refund_requested', changing
--     its financial status before anyone had approved anything.
--   * There was no five-day eligibility rule at all for refunds.
--   * An approver saw no preview and no revalidation: approving acted on
--     whatever the world looked like at that moment, with nothing to compare
--     against what the requester had actually asked for.
--
-- This migration adds the guided layer and leaves the engines alone:
--
--   invoice_action_window()   the five-day rule, from the invoice's own
--                             creation timestamp in Singapore
--   invoice_action_plan()     derives the whole effect set from the original
--                             invoice's evidence -- amount, stock, vouchers,
--                             entitlements, credits, overrides, blockers
--   request_invoice_action_v2()   captures a complete request and changes
--                             NOTHING about the invoice
--   resolve_invoice_action_v2()   re-derives the plan at approval time and
--                             refuses to act on a materially changed one
--                             without explicit confirmation
--
-- Additive. The existing request_invoice_action/resolve_invoice_action stay
-- installed so anything already pending continues to work. Idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- THE FIVE-DAY RULE
--
-- Measured from the invoice's own creation timestamp in Asia/Singapore, with
-- the creation day counting as day one: created 12 Sep -> through 16 Sep.
--
-- created_at is used precisely because it cannot be moved. Correcting the
-- invoice, recovering or backdating its business date, and reopening it all
-- leave created_at alone, so none of them restart the window -- which is the
-- stated requirement, enforced by the choice of column rather than by a rule
-- that could be forgotten.
--
-- Where the creation timestamp itself cannot be trusted, this does not invent
-- an eligibility date. It reuses the existing date-recovery evidence
-- machinery (290): if that classifies the invoice as manual_review, the window
-- is reported as unreliable and an explicit review is required.
-- ---------------------------------------------------------------------
create or replace function public.invoice_action_window(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; v_created date; v_deadline date; v_plan jsonb; v_reliable boolean; v_note text;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 v_created:=(i.created_at at time zone 'Asia/Singapore')::date;
 v_deadline:=v_created+4;                      -- the creation day is day one
 -- Trustworthiness of the creation timestamp, from the recovery evidence only.
 v_plan:=public.plan_invoice_date_recovery(public.invoice_date_evidence(i.id));
 v_reliable:=coalesce(v_plan->>'classification','') <> 'manual_review';
 if not v_reliable then
  v_note:='This invoice''s original creation date could not be established from its recorded evidence, so the five-day window cannot be judged from it. Review the invoice''s date history before relying on eligibility.';
 end if;
 return jsonb_build_object(
  'created_at',i.created_at,'created_on',v_created,'deadline',v_deadline,'today',public.sg_today(),
  'within',public.sg_today()<=v_deadline,
  'days_remaining',greatest(v_deadline-public.sg_today(),0),
  'override_required',public.sg_today()>v_deadline,
  'creation_reliable',v_reliable,'review_note',v_note,
  'basis','Five days from the invoice''s Singapore creation date, counting that date as day one. Business-date corrections, backdating and reopening do not restart it.');
end $$;
comment on function public.invoice_action_window(uuid) is
 'The five-day refund/cancellation window for an invoice, measured from its immutable creation timestamp in Asia/Singapore.';
grant execute on function public.invoice_action_window(uuid) to authenticated;

create or replace function public.invoice_action_plan(
  p_invoice_id uuid, p_action text, p_lines jsonb default '[]'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
 i public.invoices%rowtype; it public.invoice_items%rowtype;
 o jsonb; w jsonb; x jsonb; b jsonb; s jsonb;
 v_sel jsonb:='[]'; v_stock jsonb:='[]'; v_src jsonb:='[]'; v_over jsonb:='[]'; v_block jsonb:='[]'; v_sum jsonb:='[]';
 v_qty int; v_full_qty int; v_amount numeric; v_line_rem numeric; v_total numeric:=0;
 v_ben jsonb; v_take numeric; v_left numeric; v_units int; v_alloc numeric;
 v_held numeric; v_srem numeric; v_assigned numeric:=0; v_n int; v_idx int:=0;
 v_has_ben boolean; v_returnable int; v_sess jsonb;
begin
 if p_action not in ('cancel','refund_full','refund_partial') then
  raise exception 'Choose cancellation, a full refund or a partial refund'; end if;
 select * into i from public.invoices where id=p_invoice_id;
 if not found or i.deleted_at is not null or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice not accessible'; end if;

 o:=public.invoice_refund_options(i.id);
 w:=public.invoice_action_window(i.id);
 v_held:=public.invoice_net_received(i.id);

 -- Evidence that must be reviewed before any action, not overridden.
 if coalesce((o->>'review_required')::boolean,false) then
  v_block:=v_block||jsonb_build_array(jsonb_build_object('code','historical_refund_review',
   'message','An earlier refund on this invoice has no recorded payment source. Review it before recording another.')); end if;
 for x in select * from jsonb_array_elements(coalesce(o->'review_notes','[]')) loop
  v_block:=v_block||jsonb_build_array(jsonb_build_object('code','voucher_evidence_review','message',x#>>'{}'));
 end loop;

 -- The five-day rule applies to every item type except rental lines, which may
 -- be cancelled while the rental is still running.
 if coalesce((w->>'override_required')::boolean,false)
    and exists(select 1 from public.invoice_items q where q.invoice_id=i.id and q.line_kind::text<>'rental') then
  v_over:=v_over||jsonb_build_array(jsonb_build_object('code','time_window',
   'message','Outside the five-day window (created '||(w->>'created_on')||', through '||(w->>'deadline')||'). An Owner or Manager override with a reason is required.'));
 end if;
 if not coalesce((w->>'creation_reliable')::boolean,true) then
  v_block:=v_block||jsonb_build_array(jsonb_build_object('code','creation_date_review','message',w->>'review_note')); end if;

 -- ---- the lines this action touches -------------------------------------
 for x in select * from jsonb_array_elements(coalesce(o->'lines','[]')) loop
  select * into it from public.invoice_items where id=(x->>'invoice_item_id')::uuid;
  v_line_rem:=round(coalesce((x->>'remaining')::numeric,0),2);
  v_full_qty:=greatest(coalesce(it.quantity,1),1);
  if p_action='refund_partial' then
   v_qty:=coalesce((select (j->>'quantity')::int from jsonb_array_elements(coalesce(p_lines,'[]')) j
                     where j->>'invoice_item_id'=it.id::text),0);
   if v_qty<=0 then continue; end if;
   if v_qty>v_full_qty then raise exception 'Cannot refund more units than the line holds'; end if;
  else
   v_qty:=v_full_qty;
  end if;
  if v_line_rem<=0 and p_action<>'cancel' then continue; end if;

  -- Original saved value after discounts, shared pro rata across the line's
  -- units. Never today's catalogue price.
  v_amount:=least(round(coalesce(public.invoice_discounted_line_value(it.id),0)*v_qty/v_full_qty,2),v_line_rem);
  if v_amount<0 then v_amount:=0; end if;

  -- ---- benefits recorded against this line (credit lots, issued vouchers)
  v_ben:='[]'; v_left:=v_amount; v_has_ben:=false;
  for b in select * from jsonb_array_elements(coalesce(o->'benefits','[]')) loop
   continue when b->>'invoice_item_id'<>it.id::text;
   v_has_ben:=true;
   v_take:=least(v_left,round(coalesce((b->>'max_refund')::numeric,0),2));
   if nullif(b->>'reward_voucher_id','') is not null and coalesce((b->>'paid_value')::numeric,0)>0 then
    -- Voucher benefits refund in whole unused units at their allocated value.
    v_units:=floor(v_take*coalesce((b->>'granted_value')::numeric,0)/(b->>'paid_value')::numeric)::int;
    v_take:=case when v_units>0 then round(v_units*(b->>'paid_value')::numeric/(b->>'granted_value')::numeric,2) else 0 end;
   end if;
   if v_take>0 then
    v_ben:=v_ben||jsonb_build_array(jsonb_build_object('benefit_id',b->>'id','amount',v_take,
      'kind',b->>'benefit_kind','holder',b->>'customer_name','holder_id',b->>'customer_id'));
    v_left:=round(v_left-v_take,2);
   end if;
   -- Anything already spent or redeemed is an override, not a silent reduction.
   if coalesce((b->>'remaining_value')::numeric,0) < coalesce((b->>'granted_value')::numeric,0) then
    v_over:=v_over||jsonb_build_array(jsonb_build_object(
     'code',case when nullif(b->>'reward_voucher_id','') is not null then 'voucher_redeemed' else 'credit_used' end,
     'message',case when nullif(b->>'reward_voucher_id','') is not null
       then 'Voucher units from this purchase have been redeemed. Only unused units are revoked; an Owner/Manager override is required.'
       else 'Credit from this purchase has been spent. Only the remaining credit is removed; an Owner/Manager override is required.' end));
   end if;
  end loop;
  -- The engine requires a benefit-backed line's refund to equal its allocations.
  if v_has_ben or it.line_kind::text in ('credit_package','premium_bundle') then
   v_amount:=round(coalesce((select sum((q->>'amount')::numeric) from jsonb_array_elements(v_ben) q),0),2);
  end if;

  -- ---- purchased therapy and individual sessions -------------------------
  v_sess:=null;
  if it.line_kind::text='therapy' then
   if exists(select 1 from public.purchased_therapy_entitlements
              where invoice_item_id=it.id and status in ('active','expired')) then
    -- Reported as a blocker, not an override, because it is one TODAY: the
    -- refund engine still refuses an activated entitlement outright
    -- ('Consumed or activated therapy cannot be refunded') and has no
    -- termination path for one. Offering an override here would promise
    -- something that fails at execution. When the engine gains a termination
    -- path this becomes an override with a reason, and nothing else changes.
    v_block:=v_block||jsonb_build_array(jsonb_build_object('code','therapy_activated',
     'message','This therapy entitlement has been activated. Refunding an activated entitlement is not yet supported and needs an authorized review of the activation and usage history.'));
   end if;
  end if;
  if it.therapy_service_id is not null then
   select to_jsonb(q) into v_sess from (
    select (j->>'used')::int used,(j->>'unused')::int unused,(j->>'max_refund')::numeric max_refund
      from jsonb_array_elements(coalesce(o->'therapy_sessions','[]')) j
     where j->>'invoice_item_id'=it.id::text limit 1) q;
   if coalesce((v_sess->>'used')::int,0)>0 then
    v_over:=v_over||jsonb_build_array(jsonb_build_object('code','session_used',
     'message','Sessions from this purchase have been delivered. Only undelivered sessions are cancelled; an Owner/Manager override is required.'));
   end if;
   if v_sess is not null and coalesce((v_sess->>'max_refund')::numeric,0)<v_amount then
    v_amount:=round(coalesce((v_sess->>'max_refund')::numeric,0),2);
   end if;
  end if;

  -- ---- stock actually deducted for this line ----------------------------
  if it.line_kind::text in ('product','promotion') then
   for s in select * from jsonb_array_elements(coalesce(o->'stock','[]')) loop
    continue when coalesce(s->>'product_id','')<>coalesce(it.product_id::text,'');
    v_returnable:=coalesce((s->>'quantity')::int,0)-coalesce((s->>'resolved_quantity')::int,0);
    if v_returnable<=0 then continue; end if;
    v_returnable:=least(v_returnable,v_qty);
    v_stock:=v_stock||jsonb_build_array(jsonb_build_object(
      'movement_id',s->>'movement_id','product_name',s->>'product_name','store_id',s->>'store_id',
      'outstanding',coalesce((s->>'quantity')::int,0)-coalesce((s->>'resolved_quantity')::int,0),
      'proposed_sellable',v_returnable,'damaged_quantity',0,'not_returned_quantity',0,
      'store_name',(select name from public.stores where id=(s->>'store_id')::uuid)));
   end loop;
  end if;

  v_sel:=v_sel||jsonb_build_array(jsonb_build_object(
   'invoice_item_id',it.id,'name',x->>'name','line_kind',it.line_kind,
   'quantity',v_full_qty,'selected_quantity',v_qty,
   'remaining_value',v_line_rem,'amount',v_amount,'benefits',v_ben,'sessions',v_sess));
  v_total:=round(v_total+v_amount,2);
 end loop;

 -- ---- money that can actually go back ------------------------------------
 if p_action='cancel' then
  -- Cancelling clears the charge. Money already held is a refund DUE; it is
  -- only recorded as returned when somebody confirms it actually was.
  v_total:=0;
 end if;
 if v_total>v_held then v_total:=round(v_held,2); end if;

 -- Allocate across the original payment sources in proportion to what each
 -- still holds, so credit goes back to credit and cash back to cash.
 v_srem:=coalesce((select sum((j->>'remaining')::numeric) from jsonb_array_elements(coalesce(o->'sources','[]')) j),0);
 v_n:=jsonb_array_length(coalesce(o->'sources','[]'));
 if v_total>0 and v_srem>0 then
  for x in select * from jsonb_array_elements(o->'sources') loop
   v_idx:=v_idx+1;
   v_alloc:=case when v_idx=v_n then round(v_total-v_assigned,2)
                 else round(v_total*coalesce((x->>'remaining')::numeric,0)/v_srem,2) end;
   v_alloc:=least(v_alloc,round(coalesce((x->>'remaining')::numeric,0),2));
   if v_alloc>0 then
    v_src:=v_src||jsonb_build_array(jsonb_build_object('payment_id',x->>'payment_id','method',x->>'method',
      'wallet',coalesce((x->>'wallet')::boolean,false),'amount',v_alloc));
    v_assigned:=round(v_assigned+v_alloc,2);
   end if;
  end loop;
  if v_assigned<>v_total then v_total:=v_assigned; end if;
 end if;

 -- ---- a summary a person can check ---------------------------------------
 if p_action='cancel' then
  v_sum:=v_sum||jsonb_build_array('Cancel '||i.invoice_no||' and clear what is still owed.');
  if v_held>0 then v_sum:=v_sum||jsonb_build_array('Refund due: S$'||to_char(v_held,'FM999999990.00')||'. No money is recorded as returned until someone confirms it was.'); end if;
 elsif v_total>0 then
  v_sum:=v_sum||jsonb_build_array('Refund S$'||to_char(v_total,'FM999999990.00')||'.');
 end if;
 for x in select * from jsonb_array_elements(v_src) loop
  v_sum:=v_sum||jsonb_build_array('Return S$'||to_char((x->>'amount')::numeric,'FM999999990.00')||' to '||(x->>'method')||
   case when (x->>'wallet')::boolean then ' (restores the original credit)' else '' end||'.');
 end loop;
 for x in select * from jsonb_array_elements(v_stock) loop
  v_sum:=v_sum||jsonb_build_array('Return '||(x->>'proposed_sellable')||' x '||(x->>'product_name')||' to '||
   coalesce(x->>'store_name','the original store')||', once the condition is confirmed.');
 end loop;
 for x in select * from jsonb_array_elements(v_sel) loop
  for b in select * from jsonb_array_elements(coalesce(x->'benefits','[]')) loop
   v_sum:=v_sum||jsonb_build_array(case when b->>'kind'='voucher'
     then 'Cancel unused voucher units from '||(x->>'name')||'.'
     else 'Remove S$'||to_char((b->>'amount')::numeric,'FM999999990.00')||' of '||coalesce(b->>'kind','')||' credit'||
          coalesce(' from '||(b->>'holder'),'')||'.' end);
  end loop;
 end loop;
 for x in select * from jsonb_array_elements(v_over) loop
  v_sum:=v_sum||jsonb_build_array('Owner/Manager override required: '||(x->>'message'));
 end loop;

 return jsonb_build_object(
  'invoice_id',i.id,'invoice_no',i.invoice_no,'store_id',i.store_id,'status',i.status,
  'action',p_action,'window',w,'financial',o->'financial','net_held',v_held,
  'refund_amount',v_total,'refund_due',case when p_action='cancel' then round(v_held,2) else 0 end,
  'lines',v_sel,'sources',v_src,'stock',v_stock,
  'overrides_required',v_over,'blockers',v_block,'summary',v_sum,
  'requires_override',jsonb_array_length(v_over)>0,'blocked',jsonb_array_length(v_block)>0,
  -- Identifies this exact set of effects, so an approver can be shown that
  -- circumstances changed rather than silently approving something else.
  'plan_hash',md5(jsonb_build_object('a',p_action,'t',v_total,'l',v_sel,'s',v_src,'k',v_stock,'o',v_over)::text));
end $$;
comment on function public.invoice_action_plan(uuid,text,jsonb) is
 'Derives the complete effect set of a cancellation or refund from the original invoice evidence: amount, payment sources, stock returns, benefit reversals, required overrides and blockers.';
grant execute on function public.invoice_action_plan(uuid,text,jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- SUBMITTING A REQUEST CHANGES NOTHING
--
-- The old request_invoice_action() moved the invoice to 'refund_requested'
-- the moment staff asked. That changed the invoice's financial status before
-- anybody had approved anything, and a refused request had to put it back.
-- This records the request and touches the invoice not at all.
-- ---------------------------------------------------------------------
create or replace function public.request_invoice_action_v2(
  p_invoice_id uuid, p_action text, p_lines jsonb, p_reason text,
  p_return_notes text default null, p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; v_plan jsonb; v_req uuid; v_existing public.approval_requests%rowtype;
begin
 if nullif(trim(p_reason),'') is null then raise exception 'A reason is required'; end if;
 if p_request_id is null then raise exception 'A request ID is required'; end if;
 select * into i from public.invoices where id=p_invoice_id;
 if not found or i.deleted_at is not null or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice not accessible'; end if;
 if i.status in ('cancelled','refunded') then raise exception 'Invoice is already %',i.status; end if;

 -- Retrying the same submission returns the same request rather than a second one.
 select * into v_existing from public.approval_requests
  where request_type in ('invoice_cancel','invoice_refund') and payload->>'request_id'=p_request_id::text;
 if found then
  return jsonb_build_object('request_id',v_existing.id,'status',v_existing.status,
    'plan',v_existing.payload->'plan','replayed',true); end if;

 if exists(select 1 from public.approval_requests
            where related_record_id=p_invoice_id and status='pending'
              and request_type in ('invoice_cancel','invoice_refund')) then
  raise exception 'A request for this invoice is already waiting for approval'; end if;

 v_plan:=public.invoice_action_plan(p_invoice_id,p_action,coalesce(p_lines,'[]'::jsonb));
 if coalesce((v_plan->>'blocked')::boolean,false) then
  raise exception 'This invoice needs review before a request can be raised: %',
    coalesce(v_plan#>>'{blockers,0,message}','see the invoice''s evidence review'); end if;

 insert into public.approval_requests(request_type,status,requested_by,related_record_id,reason,payload)
 values(case when p_action='cancel' then 'invoice_cancel' else 'invoice_refund' end,'pending',auth.uid(),p_invoice_id,
   trim(p_reason),
   jsonb_build_object('request_id',p_request_id,'invoice_id',p_invoice_id,'invoice_no',i.invoice_no,
     'store_id',i.store_id,'action',p_action,'lines',coalesce(p_lines,'[]'::jsonb),
     'return_notes',nullif(trim(coalesce(p_return_notes,'')),''),
     'plan',v_plan,'plan_hash',v_plan->>'plan_hash',
     'requested_amount',v_plan->>'refund_amount',
     'override_required',v_plan->'requires_override',
     'submitted_at',now()))
 returning id into v_req;

 -- The invoice itself is deliberately untouched: no status change, no refund,
 -- no stock return, no entitlement or credit change.
 perform public.write_audit_ex('approval_requests',v_req,'invoice_action_requested',null,
   jsonb_build_object('action',p_action,'amount',v_plan->>'refund_amount','lines',p_lines),
   'invoices',trim(p_reason),i.store_id);
 return jsonb_build_object('request_id',v_req,'status','pending','plan',v_plan);
end $$;
comment on function public.request_invoice_action_v2(uuid,text,jsonb,text,text,uuid) is
 'Records a staff request for a cancellation or refund, with the derived plan. Changes nothing about the invoice.';
grant execute on function public.request_invoice_action_v2(uuid,text,jsonb,text,text,uuid) to authenticated;

-- ---------------------------------------------------------------------
-- APPROVAL RE-DERIVES THE PLAN
--
-- The world moves between asking and approving: credit gets spent, stock gets
-- returned another way, another refund lands. So the plan is computed again
-- here, from scratch, and if it no longer matches what was requested the
-- approver is shown the revised plan and must confirm THAT one by its hash.
-- Nothing is approved silently at a different amount or with different effects.
-- ---------------------------------------------------------------------
create or replace function public.resolve_invoice_action_v2(
  p_request_id uuid, p_approve boolean, p_note text default null,
  p_plan_hash text default null, p_overrides jsonb default '[]'::jsonb,
  p_stock jsonb default null, p_record_refund boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.approval_requests%rowtype; i public.invoices%rowtype; v_plan jsonb;
 v_lines jsonb:='[]'; v_sources jsonb:='[]'; v_stock jsonb; x jsonb; o jsonb;
 v_missing text; v_exec uuid; v_result jsonb; v_action text;
begin
 if not public.is_owner_or_manager() then
  raise exception 'Only an Owner or Manager can approve or reject an invoice request'; end if;
 select * into r from public.approval_requests where id=p_request_id for update;
 if not found or r.request_type not in ('invoice_cancel','invoice_refund') then
  raise exception 'Invoice request not found'; end if;
 if r.status<>'pending' then
  -- Repeat clicks report what already happened instead of doing it twice.
  return jsonb_build_object('request_id',r.id,'status',r.status,'already_resolved',true); end if;
 select * into i from public.invoices where id=r.related_record_id for update;
 if not found or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice not accessible'; end if;

 if not p_approve then
  update public.approval_requests set status='rejected',approved_by=auth.uid(),approved_at=now(),
    response_note=p_note,rejection_reason=p_note where id=r.id;
  perform public.write_audit_ex('approval_requests',r.id,'invoice_action_rejected',to_jsonb(r),
    jsonb_build_object('note',p_note),'invoices',coalesce(p_note,'Rejected'),i.store_id);
  return jsonb_build_object('request_id',r.id,'status','rejected');
 end if;

 v_action:=r.payload->>'action';
 -- Eligibility, balances and evidence are judged NOW, not when this was asked.
 v_plan:=public.invoice_action_plan(i.id,v_action,coalesce(r.payload->'lines','[]'::jsonb));
 if coalesce((v_plan->>'blocked')::boolean,false) then
  raise exception 'This invoice now needs review before the request can be approved: %',
    coalesce(v_plan#>>'{blockers,0,message}','see the invoice''s evidence review'); end if;

 if (v_plan->>'plan_hash') is distinct from coalesce(p_plan_hash,r.payload->>'plan_hash') then
  return jsonb_build_object('request_id',r.id,'status','pending','confirmation_required',true,
    'requested_plan',r.payload->'plan','revised_plan',v_plan,
    'message','What this request would do has changed since it was submitted. Review the revised effects and confirm them explicitly.');
 end if;

 -- Every override the plan asks for needs its own stated reason.
 for x in select * from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) loop
  if not exists(select 1 from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                 where q->>'code'=x->>'code' and nullif(trim(coalesce(q->>'reason','')),'') is not null) then
   v_missing:=coalesce(v_missing||' ','')||(x->>'code');
  end if;
 end loop;
 if v_missing is not null then
  raise exception 'An Owner/Manager override reason is required for: %',v_missing; end if;

 -- A refund or cancellation is not evidence that goods came back. The
 -- returned, damaged and not-returned quantities are stated by the approver.
 if jsonb_array_length(coalesce(v_plan->'stock','[]'))>0 then
  if p_stock is null or jsonb_array_length(p_stock)=0 then
   raise exception 'Confirm the returned, damaged and not-returned quantities for the goods on this invoice'; end if;
  v_stock:=p_stock;
 else v_stock:='[]'::jsonb; end if;

 if v_action='cancel' then
  -- One combined workflow: money only moves when somebody says it moved.
  if p_record_refund and coalesce((v_plan->>'refund_due')::numeric,0)>0 then
   v_exec:=r.id;
   select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id',l->>'invoice_item_id',
            'amount',(l->>'amount')::numeric,'benefits',coalesce(l->'benefits','[]'))),'[]')
     into v_lines from jsonb_array_elements(public.invoice_action_plan(i.id,'refund_full')->'lines') l
    where (l->>'amount')::numeric>0;
   select coalesce(jsonb_agg(jsonb_build_object('payment_id',s->>'payment_id','amount',(s->>'amount')::numeric)),'[]')
     into v_sources from jsonb_array_elements(public.invoice_action_plan(i.id,'refund_full')->'sources') s;
   if jsonb_array_length(v_lines)>0 and jsonb_array_length(v_sources)>0 then
    v_result:=public.refund_invoice_recorded(i.id,v_lines,v_sources,v_stock,
      coalesce(p_note,r.reason),v_exec);
   end if;
  end if;
  v_result:=public.cancel_invoice_recorded(i.id,coalesce(p_note,r.reason),r.id);
 else
  select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id',l->>'invoice_item_id',
           'amount',(l->>'amount')::numeric,'benefits',coalesce(l->'benefits','[]'))),'[]')
    into v_lines from jsonb_array_elements(v_plan->'lines') l where (l->>'amount')::numeric>0;
  select coalesce(jsonb_agg(jsonb_build_object('payment_id',s->>'payment_id','amount',(s->>'amount')::numeric)),'[]')
    into v_sources from jsonb_array_elements(v_plan->'sources') s;
  if jsonb_array_length(v_lines)=0 or jsonb_array_length(v_sources)=0 then
   raise exception 'There is nothing left to refund on this invoice'; end if;
  v_result:=public.refund_invoice_recorded(i.id,v_lines,v_sources,v_stock,coalesce(p_note,r.reason),r.id);
 end if;

 update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
   response_note=p_note,
   payload=payload||jsonb_build_object('executed_plan',v_plan,'overrides',coalesce(p_overrides,'[]'::jsonb),
     'stock_confirmed',v_stock,'refund_recorded',coalesce(p_record_refund,false),'outcome',v_result)
 where id=r.id;
 perform public.write_audit_ex('approval_requests',r.id,'invoice_action_approved',to_jsonb(r),
   jsonb_build_object('plan',v_plan,'overrides',p_overrides,'stock',v_stock,'outcome',v_result),
   'invoices',coalesce(p_note,r.reason),i.store_id);
 return jsonb_build_object('request_id',r.id,'status','approved','plan',v_plan,'outcome',v_result);
end $$;
comment on function public.resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) is
 'Approves or rejects an invoice cancellation/refund request, re-deriving the plan and refusing to act on a materially changed one without explicit confirmation.';
grant execute on function public.resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) to authenticated;

-- What the requesting staff member sees on their own invoice.
create or replace function public.invoice_pending_action_request(p_invoice_id uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
 select to_jsonb(q) from (
   select a.id request_id,a.request_type,a.status,a.reason,a.created_at,a.approved_at,
          a.rejection_reason,a.response_note,a.payload->>'action' action,
          (a.payload->>'requested_amount')::numeric requested_amount,
          p.full_name requested_by_name
     from public.approval_requests a
     left join public.profiles p on p.id=a.requested_by
     join public.invoices i on i.id=a.related_record_id
    where a.related_record_id=p_invoice_id
      and a.request_type in ('invoice_cancel','invoice_refund')
      and public.user_has_store_access(i.store_id)
    order by case when a.status='pending' then 0 else 1 end, a.created_at desc
    limit 1) q
$$;
grant execute on function public.invoice_pending_action_request(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- A REQUEST IS CLOSED BY THE ACTION THAT ANSWERS IT, NOT BY ANY ACTION
--
-- complete_invoice_finance_request() closed EVERY pending refund request on an
-- invoice whenever ANY refund row was inserted against it. So an Owner
-- refunding one unit directly would mark a staff member's pending request for
-- a full refund "approved" -- telling the requester their request had been
-- granted when nothing of the sort had happened, and leaving the rest of the
-- refund unmade.
--
-- It also made approval-time revalidation unreachable: the very change an
-- approver most needs to be warned about closed the request before they saw it.
--
-- A refund now closes the request it belongs to (its own request id), or any
-- pending request whose goal has actually been met -- the invoice has nothing
-- left to charge. Cancellation is unchanged: an invoice that is now cancelled
-- has fulfilled a pending cancellation request by definition.
-- ---------------------------------------------------------------------
create or replace function public.complete_invoice_finance_request()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
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
end $$;

notify pgrst,'reload schema';
commit;
