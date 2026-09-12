begin;
-- =====================================================================
-- THE ENGINE CAN NOW PERFORM THE ACTIONS IT WAS ONLY COLLECTING REASONS FOR
--
-- 295 added a guided layer that asks an Owner/Manager for an override reason.
-- For two cases the engine underneath could not then carry the action out, so
-- the override was theatre: the reason was collected and the action failed, or
-- the case was reported as a hard blocker instead.
--
--   Activated purchased therapy   refund_invoice_recorded() raised
--                                 'Consumed or activated therapy cannot be
--                                 refunded' with no termination path at all.
--
--   Used benefits                 every benefit line was capped at its unused
--                                 paid value, so an Owner/Manager could never
--                                 approve the separately justified larger
--                                 refund the policy allows.
--
-- Both are now executable, under authorization, and both are recorded for what
-- they are. In particular the larger refund does NOT pretend consumed benefits
-- were unused: benefit reversals stay capped at the genuinely unused portion
-- and the authorized excess is carried as its own explicit amount.
--
-- The engine's signature is unchanged -- deliberately. An override travels
-- inside the line it applies to (x->'override'), so no overload is created and
-- every existing caller keeps working untouched. (243 in this repo was broken
-- for exactly that reason: a new argument list made a second function and the
-- old one kept being called.)
--
-- Requires 295. Idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ACTIVATED THERAPY CAN BE TERMINATED BY AN AUTHORIZED OVERRIDE
--
-- The entitlement becomes 'refunded', which is terminal: the status refresher
-- only ever moves scheduled -> active -> expired and never touches a refunded
-- or cancelled row, so it cannot come back to life. Activation date, expiry,
-- purchase snapshot and every audit record are left exactly as they are --
-- only the status changes, so the history of what the customer actually had
-- and used survives in full.
--
-- There is no unused-period valuation rule for an activated entitlement in
-- this system, and this does not invent one: the override must carry the
-- amount an Owner/Manager has decided, and that amount is still subject to
-- every ordinary ceiling (remaining line value, net payments held, prior
-- refunds).
-- ---------------------------------------------------------------------
do $do$
declare f text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 if position('authorized_termination' in f)>0 then
  raise notice 'refund engine already terminates activated therapy under override'; return; end if;

 v_old:=
'     elsif it.line_kind=''therapy'' then'||E'\n'||
'       if exists(select 1 from public.purchased_therapy_entitlements where invoice_item_id=it.id and status in (''active'',''expired'')) then'||E'\n'||
'         raise exception ''Consumed or activated therapy cannot be refunded''; end if;'||E'\n'||
'       if v_amount<>greatest(v_line_paid-v_refunded,0) then raise exception ''Refund the whole unused therapy entitlement''; end if;'||E'\n'||
'       update public.purchased_therapy_entitlements set status=''refunded'',updated_at=now() where invoice_item_id=it.id and status in (''pending_activation'',''scheduled'');';

 v_new:=
'     elsif it.line_kind=''therapy'' then'||E'\n'||
'       if exists(select 1 from public.purchased_therapy_entitlements where invoice_item_id=it.id and status in (''active'',''expired'')) then'||E'\n'||
'         -- Activated. Only an explicitly authorized termination may proceed.'||E'\n'||
'         if nullif(x#>>''{override,reason}'','''') is null or coalesce(x->''override''->>''code'','''')<>''therapy_activated'' then'||E'\n'||
'           raise exception ''Consumed or activated therapy cannot be refunded''; end if;'||E'\n'||
'         if (x->''override''->>''amount'') is null then'||E'\n'||
'           raise exception ''No unused-period valuation exists for an activated entitlement. An Owner or Manager must state the refund amount with a reason.''; end if;'||E'\n'||
'         if round((x->''override''->>''amount'')::numeric,2)<>v_amount then'||E'\n'||
'           raise exception ''The authorized termination amount must match the refund allocated to this line''; end if;'||E'\n'||
'         for a in select * from public.purchased_therapy_entitlements'||E'\n'||
'                   where invoice_item_id=it.id and status in (''active'',''expired'') for update loop'||E'\n'||
'           update public.purchased_therapy_entitlements set status=''refunded'',updated_by=auth.uid(),updated_at=now() where id=a.id;'||E'\n'||
'           update public.commissions set status=''reversed'',reversal_reason=''Therapy terminated on authorized override: ''||p_reason'||E'\n'||
'            where invoice_item_id=it.id and status=''earned'';'||E'\n'||
'           perform public.write_audit_ex(''purchased_therapy_entitlements'',a.id,''authorized_termination'','||E'\n'||
'             jsonb_build_object(''status'',a.status,''activation_date'',a.activation_date,''expiry_date'',a.expiry_date),'||E'\n'||
'             jsonb_build_object(''status'',''refunded'',''override'',x->''override'',''request_id'',p_request_id,''amount'',v_amount),'||E'\n'||
'             ''refunds'',p_reason,i.store_id);'||E'\n'||
'         end loop;'||E'\n'||
'       else'||E'\n'||
'         if v_amount<>greatest(v_line_paid-v_refunded,0) then raise exception ''Refund the whole unused therapy entitlement''; end if;'||E'\n'||
'         update public.purchased_therapy_entitlements set status=''refunded'',updated_at=now() where invoice_item_id=it.id and status in (''pending_activation'',''scheduled'');'||E'\n'||
'       end if;';

 if position(v_old in f)=0 then
  raise exception 'The therapy branch of refund_invoice_recorded does not match what 296 expects — align it by hand'; end if;
 execute replace(f,v_old,v_new);
 raise notice 'activated therapy can now be terminated by an authorized override';
end $do$;

-- ---------------------------------------------------------------------
-- 2. AN AUTHORIZED LARGER REFUND FOR USED BENEFITS
--
-- The rule stays: benefit reversals never exceed the genuinely unused paid
-- value, because consumed credit and redeemed voucher units are gone and
-- restoring them would be a lie. What changes is that the LINE may be refunded
-- for more than that when an Owner/Manager has separately justified it, with
-- the excess carried as its own named amount rather than smuggled into the
-- benefit allocations.
--
-- Everything else still binds: the excess is part of v_total, so it is capped
-- by the remaining discounted line value, by net payments still held, and by
-- the per-payment remaining amounts, exactly as any other refund is.
-- ---------------------------------------------------------------------
do $do$
declare f text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 if position('authorized_excess' in f)>0 then
  raise notice 'refund engine already supports an authorized larger refund'; return; end if;

 v_old:='       if (select sum((q->>''amount'')::numeric) from jsonb_array_elements(x->''benefits'') q)<>v_amount then raise exception ''Benefit refunds must equal the line refund''; end if;';
 v_new:=
'       -- Benefit allocations cover the unused portion. Anything above that is'||E'\n'||
'       -- an authorized exception and must say so in as many words.'||E'\n'||
'       if (select coalesce(sum((q->>''amount'')::numeric),0) from jsonb_array_elements(x->''benefits'') q)<>v_amount then'||E'\n'||
'         if nullif(x#>>''{override,reason}'','''') is null'||E'\n'||
'            or coalesce(x->''override''->>''code'','''') not in (''credit_used'',''voucher_redeemed'',''larger_refund'')'||E'\n'||
'            or (x->''override''->>''amount'') is null then'||E'\n'||
'           raise exception ''Benefit refunds must equal the line refund''; end if;'||E'\n'||
'         if round((x->''override''->>''amount'')::numeric,2)<>v_amount then'||E'\n'||
'           raise exception ''The authorized amount must match the refund allocated to this line''; end if;'||E'\n'||
'         if (select coalesce(sum((q->>''amount'')::numeric),0) from jsonb_array_elements(x->''benefits'') q)>v_amount then'||E'\n'||
'           raise exception ''Benefit reversals cannot exceed the refund for this line''; end if;'||E'\n'||
'         perform public.write_audit_ex(''invoice_items'',it.id,''authorized_excess'',null,'||E'\n'||
'           jsonb_build_object(''line_refund'',v_amount,''benefit_backed'','||E'\n'||
'             (select coalesce(sum((q->>''amount'')::numeric),0) from jsonb_array_elements(x->''benefits'') q),'||E'\n'||
'             ''excess'',v_amount-(select coalesce(sum((q->>''amount'')::numeric),0) from jsonb_array_elements(x->''benefits'') q),'||E'\n'||
'             ''override'',x->''override'',''request_id'',p_request_id),'||E'\n'||
'           ''refunds'',p_reason,i.store_id);'||E'\n'||
'       end if;';
 if position(v_old in f)=0 then
  raise exception 'The benefit-total check in refund_invoice_recorded does not match what 296 expects — align it by hand'; end if;
 execute replace(f,v_old,v_new);
 raise notice 'an Owner/Manager can now approve a justified larger refund, recorded as an excess';
end $do$;

-- ---------------------------------------------------------------------
-- 3. THE OTHER WAY INTO A THERAPY REFUND GETS THE SAME RULE
--
-- refund_purchased_therapy() is reachable on its own and refused activated
-- entitlements outright. It now accepts the same authorized termination, so
-- the two entry points cannot disagree about what is allowed.
-- ---------------------------------------------------------------------
create or replace function public.refund_purchased_therapy(p_entitlement_id uuid, p_reason text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare e public.purchased_therapy_entitlements%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can refund therapy'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A refund reason is required'; end if;
  select * into e from public.purchased_therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Entitlement not found'; end if;
  if e.status in ('cancelled','refunded') then raise exception 'Entitlement is already %', e.status; end if;
  if e.status in ('active','expired') then
    -- Money is not moved here; this terminates the entitlement only. Refunding
    -- the money for an activated entitlement goes through the invoice, where
    -- the payment ceiling and prior refunds are enforced.
    raise exception 'Therapy cannot be refunded after activation from here. Use the invoice''s Refund / Cancel flow, where an Owner/Manager can authorize the termination and state the amount.';
  end if;

  update public.purchased_therapy_entitlements
     set status = 'refunded', updated_by = auth.uid(), updated_at = now()
   where id = p_entitlement_id;
  update public.commissions
     set status = 'reversed', reversal_reason = 'Therapy refunded: ' || p_reason
   where invoice_item_id = e.invoice_item_id and status in ('earned');
  perform public.write_audit_ex('purchased_therapy_entitlements', p_entitlement_id, 'therapy_refunded',
    jsonb_build_object('status', e.status), jsonb_build_object('status','refunded'), 'therapy', p_reason, e.store_id);
end $$;


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
 v_has_ben boolean; v_returnable int; v_sess jsonb; v_codes jsonb; v_due numeric:=0; v_target numeric;
 v_new_sel jsonb; v_cap numeric; v_one numeric;
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
  v_ben:='[]'; v_left:=v_amount; v_has_ben:=false; v_codes:='[]';
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
    v_codes:=v_codes||jsonb_build_array(case when nullif(b->>'reward_voucher_id','') is not null then 'voucher_redeemed' else 'credit_used' end);
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
    -- 296 gave the engine a termination path, so this is an override again.
    -- No unused-period valuation rule exists for an activated entitlement and
    -- none is invented: the Owner/Manager states the amount, which is then
    -- subject to every ordinary ceiling.
    v_codes:=v_codes||jsonb_build_array('therapy_activated');
    v_over:=v_over||jsonb_build_array(jsonb_build_object('code','therapy_activated','amount_required',true,
     'invoice_item_id',it.id,'default_amount',v_amount,
     'message','This therapy entitlement has been activated. Terminating it keeps its activation and usage history, and no unused-period valuation exists - an Owner or Manager must state the refund amount with a reason.'));
   end if;
  end if;
  if it.therapy_service_id is not null then
   select to_jsonb(q) into v_sess from (
    select (j->>'used')::int used,(j->>'unused')::int unused,(j->>'max_refund')::numeric max_refund
      from jsonb_array_elements(coalesce(o->'therapy_sessions','[]')) j
     where j->>'invoice_item_id'=it.id::text limit 1) q;
   if coalesce((v_sess->>'used')::int,0)>0 then
    v_codes:=v_codes||jsonb_build_array('session_used');
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
   'remaining_value',v_line_rem,'amount',v_amount,'benefits',v_ben,'sessions',v_sess,
   'override_codes',v_codes,
   'benefit_backed',coalesce((select sum((q->>'amount')::numeric) from jsonb_array_elements(v_ben) q),0)));
  v_total:=round(v_total+v_amount,2);
 end loop;

 -- ---- money that can actually go back ------------------------------------
 -- Cap to the money actually held -- and cap the LINES with it. 295 reduced
 -- only the total, leaving a plan that announced one figure while its lines
 -- summed to another; execution then asked the engine for the larger one and
 -- was refused. Lines, their benefit allocations and the total now agree.
 if v_total>v_held then
  v_left:=round(v_held,2); v_new_sel:='[]';
  for x in select * from jsonb_array_elements(v_sel) loop
   v_take:=least(v_left,(x->>'amount')::numeric);
   v_ben:='[]'; v_cap:=v_take;
   for b in select * from jsonb_array_elements(coalesce(x->'benefits','[]')) loop
    v_one:=least(v_cap,(b->>'amount')::numeric);
    if v_one>0 then
     v_ben:=v_ben||jsonb_build_array(jsonb_set(b,'{amount}',to_jsonb(v_one)));
     v_cap:=round(v_cap-v_one,2);
    end if;
   end loop;
   -- A benefit-backed line is exactly its allocations, never more.
   if jsonb_array_length(coalesce(x->'benefits','[]'))>0 then v_take:=round(v_take-v_cap,2); end if;
   v_new_sel:=v_new_sel||jsonb_build_array(jsonb_set(jsonb_set(x,'{amount}',to_jsonb(v_take)),'{benefits}',v_ben));
   v_left:=round(v_left-v_take,2);
  end loop;
  v_sel:=v_new_sel; v_total:=round(v_held-v_left,2);
 end if;
 if p_action='cancel' then
  -- Cancelling clears the charge. Money already held is a refund DUE: recorded
  -- as returned only when somebody confirms it actually was.
  --
  -- The lines, benefits, stock and sources stay DERIVED and are returned, so
  -- the approver reviews the whole combined effect and the plan hash covers
  -- it. 295 zeroed them here, which left the reviewed cancel plan describing
  -- no money at all while execution derived a refund of its own -- the
  -- approver confirmed one thing and a different thing happened.
  v_due:=v_total;
  v_total:=0;
 end if;
 v_target:=case when p_action='cancel' then v_due else v_total end;

 -- Allocate across the original payment sources in proportion to what each
 -- still holds, so credit goes back to credit and cash back to cash.
 v_srem:=coalesce((select sum((j->>'remaining')::numeric) from jsonb_array_elements(coalesce(o->'sources','[]')) j),0);
 v_n:=jsonb_array_length(coalesce(o->'sources','[]'));
 if v_target>0 and v_srem>0 then
  for x in select * from jsonb_array_elements(o->'sources') loop
   v_idx:=v_idx+1;
   v_alloc:=case when v_idx=v_n then round(v_target-v_assigned,2)
                 else round(v_target*coalesce((x->>'remaining')::numeric,0)/v_srem,2) end;
   v_alloc:=least(v_alloc,round(coalesce((x->>'remaining')::numeric,0),2));
   if v_alloc>0 then
    v_src:=v_src||jsonb_build_array(jsonb_build_object('payment_id',x->>'payment_id','method',x->>'method',
      'wallet',coalesce((x->>'wallet')::boolean,false),'amount',v_alloc));
    v_assigned:=round(v_assigned+v_alloc,2);
   end if;
  end loop;
  if v_assigned<>v_target then
   if p_action='cancel' then v_due:=v_assigned; else v_total:=v_assigned; end if;
  end if;
 end if;

 -- ---- a summary a person can check ---------------------------------------
 if p_action='cancel' then
  v_sum:=v_sum||jsonb_build_array('Cancel '||i.invoice_no||' and clear what is still owed.');
  if v_due>0 then v_sum:=v_sum||jsonb_build_array('Refund due: S$'||to_char(v_due,'FM999999990.00')||'. No money is recorded as returned until someone confirms it was.'); end if;
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
  'refund_amount',v_total,'refund_due',case when p_action='cancel' then round(v_due,2) else 0 end,
  'lines',v_sel,'sources',v_src,'stock',v_stock,
  'overrides_required',v_over,'blockers',v_block,'summary',v_sum,
  'requires_override',jsonb_array_length(v_over)>0,'blocked',jsonb_array_length(v_block)>0,
  -- Identifies this exact set of effects, so an approver can be shown that
  -- circumstances changed rather than silently approving something else.
  -- v_due is hashed too: a change in what would go back on a cancellation
  -- must invalidate the approver's confirmation exactly as a refund change does.
  'plan_hash',md5(jsonb_build_object('a',p_action,'t',v_total,'d',v_due,'l',v_sel,'s',v_src,'k',v_stock,'o',v_over)::text));
end $$;
comment on function public.invoice_action_plan(uuid,text,jsonb) is
 'Derives the complete effect set of a cancellation or refund from the original invoice evidence: amount, payment sources, stock returns, benefit reversals, required overrides and blockers.';
grant execute on function public.invoice_action_plan(uuid,text,jsonb) to authenticated;

-- Records confirmed stock conditions without a refund, so a CANCELLATION can
-- return goods truthfully. cancel_invoice_recorded() calls
-- restore_invoice_stock(), which puts every outstanding unit back as SELLABLE
-- and knows nothing about condition. Writing the dispositions first leaves
-- nothing outstanding for it to restore, so damaged and not-returned units
-- never re-enter sale and no unit is returned twice.
create or replace function public.record_invoice_stock_return(
  p_invoice_id uuid, p_stock jsonb, p_reason text, p_request_id uuid)
returns int language plpgsql security definer set search_path to 'public' as $$
declare x jsonb; sm public.stock_movements%rowtype; sq int; dq int; nq int; v_resolved int; n int:=0;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can record returned goods'; end if;
 for x in select * from jsonb_array_elements(coalesce(p_stock,'[]'::jsonb)) loop
  select * into sm from public.stock_movements
   where id=(x->>'movement_id')::uuid and invoice_id=p_invoice_id and movement_type::text='store_sale' for update;
  if not found then raise exception 'Stock return must reference an actual invoice deduction'; end if;
  sq:=coalesce((x->>'sellable_quantity')::int,0);
  dq:=coalesce((x->>'damaged_quantity')::int,0);
  nq:=coalesce((x->>'not_returned_quantity')::int,0);
  select coalesce(sum(sellable_quantity+damaged_quantity+not_returned_quantity),0) into v_resolved
    from public.invoice_stock_dispositions where movement_id=sm.id;
  v_resolved:=v_resolved+coalesce((select sum(quantity) from public.stock_movements
    where reversed_sale_id=sm.id and movement_type::text='invoice_cancel_return'),0);
  if sq<0 or dq<0 or nq<0 or sq+dq+nq<=0 or sq+dq+nq>sm.quantity-v_resolved then
   raise exception 'Stock disposition exceeds the unresolved deduction'; end if;
  insert into public.invoice_stock_dispositions(invoice_id,movement_id,request_id,sellable_quantity,damaged_quantity,not_returned_quantity,reason,created_by)
   values(p_invoice_id,sm.id,p_request_id,sq,dq,nq,p_reason,auth.uid());
  if sq>0 then
   update public.store_inventory set current_qty=current_qty+sq,updated_at=now()
    where store_id=sm.from_store_id and product_id=sm.product_id;
   if not found then raise exception 'Original stock location no longer exists'; end if;
   insert into public.stock_movements(product_id,movement_type,to_store_id,invoice_id,quantity,notes,created_by,reversed_sale_id)
    values(sm.product_id,'invoice_refund_return',sm.from_store_id,p_invoice_id,sq,'Confirmed sellable return: '||p_reason,auth.uid(),sm.id);
  end if;
  n:=n+1;
 end loop;
 return n;
end $$;
grant execute on function public.record_invoice_stock_return(uuid,jsonb,text,uuid) to authenticated;

-- ---------------------------------------------------------------------
-- APPROVAL EXECUTES THE PLAN THAT WAS REVIEWED
--
-- 295's cancellation branch derived a FRESH refund_full plan at execution time
-- and then overwrote the refund's result with the cancellation's, so:
--   * the approver confirmed a plan describing no money, and money moved;
--   * the caller was told only about the cancellation;
--   * confirmed stock conditions were collected and thrown away.
-- All three are fixed here. The reviewed plan is the only thing executed, and
-- both outcomes come back.
-- ---------------------------------------------------------------------
create or replace function public.resolve_invoice_action_v2(
  p_request_id uuid, p_approve boolean, p_note text default null,
  p_plan_hash text default null, p_overrides jsonb default '[]'::jsonb,
  p_stock jsonb default null, p_record_refund boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.approval_requests%rowtype; i public.invoices%rowtype; v_plan jsonb;
 v_lines jsonb:='[]'; v_sources jsonb:='[]'; v_stock jsonb; x jsonb; ov jsonb;
 v_missing text; v_refund jsonb; v_cancel jsonb; v_action text; v_returned int:=0;
 v_exec numeric; v_planned numeric; v_alloc numeric; v_assigned numeric; v_n int; v_idx int;
begin
 if not public.is_owner_or_manager() then
  raise exception 'Only an Owner or Manager can approve or reject an invoice request'; end if;
 select * into r from public.approval_requests where id=p_request_id for update;
 if not found or r.request_type not in ('invoice_cancel','invoice_refund') then
  raise exception 'Invoice request not found'; end if;
 if r.status<>'pending' then
  return jsonb_build_object('request_id',r.id,'status',r.status,'already_resolved',true,
    'outcome',r.payload->'outcome','refund',r.payload->'refund','cancellation',r.payload->'cancellation'); end if;
 select * into i from public.invoices where id=r.related_record_id for update;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;

 if not p_approve then
  update public.approval_requests set status='rejected',approved_by=auth.uid(),approved_at=now(),
    response_note=p_note,rejection_reason=p_note where id=r.id;
  perform public.write_audit_ex('approval_requests',r.id,'invoice_action_rejected',to_jsonb(r),
    jsonb_build_object('note',p_note),'invoices',coalesce(p_note,'Rejected'),i.store_id);
  return jsonb_build_object('request_id',r.id,'status','rejected');
 end if;

 -- A request raised before 295 has no derived plan and no line selection.
 -- Guessing one would be inventing what somebody asked for.
 if r.payload->'plan' is null then
  raise exception 'This request predates the guided workflow and has no reviewed plan. Open the invoice and raise it again through Refund / Cancel so the effects can be derived and reviewed.'; end if;

 v_action:=r.payload->>'action';
 v_plan:=public.invoice_action_plan(i.id,v_action,coalesce(r.payload->'lines','[]'::jsonb));
 if coalesce((v_plan->>'blocked')::boolean,false) then
  raise exception 'This invoice now needs review before the request can be approved: %',
    coalesce(v_plan#>>'{blockers,0,message}','see the invoice''s evidence review'); end if;

 if (v_plan->>'plan_hash') is distinct from coalesce(p_plan_hash,r.payload->>'plan_hash') then
  return jsonb_build_object('request_id',r.id,'status','pending','confirmation_required',true,
    'requested_plan',r.payload->'plan','revised_plan',v_plan,
    'message','What this request would do has changed since it was submitted. Review the revised effects and confirm them explicitly.');
 end if;

 for x in select * from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) loop
  select q into ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
   where q->>'code'=x->>'code' and nullif(trim(coalesce(q->>'reason','')),'') is not null limit 1;
  if ov is null then v_missing:=coalesce(v_missing||' ','')||(x->>'code');
  elsif coalesce((x->>'amount_required')::boolean,false) and (ov->>'amount') is null then
   v_missing:=coalesce(v_missing||' ','')||(x->>'code')||' (amount)';
  end if;
  ov:=null;
 end loop;
 if v_missing is not null then
  raise exception 'An Owner/Manager override reason is required for: %',v_missing; end if;

 if jsonb_array_length(coalesce(v_plan->'stock','[]'))>0 then
  if p_stock is null or jsonb_array_length(p_stock)=0 then
   raise exception 'Confirm the returned, damaged and not-returned quantities for the goods on this invoice'; end if;
  v_stock:=p_stock;
 else v_stock:='[]'::jsonb; end if;

 -- Build the refund payload from the REVIEWED plan, attaching each override to
 -- the line it belongs to so the engine can act on it.
 select coalesce(jsonb_agg(jsonb_build_object(
          'invoice_item_id',l->>'invoice_item_id','amount',
          coalesce((select round((q->>'amount')::numeric,2) from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                     where (q->>'amount') is not null
                       and coalesce(l->'override_codes','[]') ? (q->>'code') limit 1),
                   (l->>'amount')::numeric),
          'benefits',coalesce(l->'benefits','[]'),
          'override',(select q from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                       where coalesce(l->'override_codes','[]') ? (q->>'code') limit 1))),'[]')
   into v_lines from jsonb_array_elements(v_plan->'lines') l
  where (l->>'amount')::numeric>0
     or exists(select 1 from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                where (q->>'amount') is not null and coalesce(l->'override_codes','[]') ? (q->>'code'));
 -- The approver's stated override amount may differ from the derived default
 -- (that is the point of an override). The reviewed source split is kept but
 -- rescaled to what is actually being refunded, so credit still goes back to
 -- credit and cash to cash, and the engine's source/total equality holds.
 select coalesce(sum((l->>'amount')::numeric),0) into v_exec from jsonb_array_elements(v_lines) l;
 select coalesce(sum((s->>'amount')::numeric),0) into v_planned from jsonb_array_elements(v_plan->'sources') s;
 v_n:=jsonb_array_length(coalesce(v_plan->'sources','[]'));
 v_assigned:=0; v_idx:=0; v_sources:='[]';
 if v_exec>0 and v_planned>0 then
  for x in select * from jsonb_array_elements(v_plan->'sources') loop
   v_idx:=v_idx+1;
   v_alloc:=case when v_idx=v_n then round(v_exec-v_assigned,2)
                 else round(v_exec*(x->>'amount')::numeric/v_planned,2) end;
   v_alloc:=least(v_alloc,round(public.invoice_payment_remaining((x->>'payment_id')::uuid),2));
   if v_alloc>0 then
    v_sources:=v_sources||jsonb_build_array(jsonb_build_object('payment_id',x->>'payment_id','amount',v_alloc));
    v_assigned:=round(v_assigned+v_alloc,2);
   end if;
  end loop;
  if v_assigned<>v_exec then
   raise exception 'The stated amount (%) cannot be taken from the payments still held (%). Reduce it or take a fresh preview.',v_exec,v_assigned; end if;
 end if;

 if v_action='cancel' then
  if p_record_refund then
   if coalesce((v_plan->>'refund_due')::numeric,0)<=0 then
    raise exception 'There is no money held on this invoice to return'; end if;
   if jsonb_array_length(v_lines)=0 or jsonb_array_length(v_sources)=0 then
    raise exception 'The reviewed plan does not describe how the money goes back; take a fresh preview'; end if;
   v_refund:=public.refund_invoice_recorded(i.id,v_lines,v_sources,v_stock,coalesce(p_note,r.reason),r.id);
  elsif jsonb_array_length(v_stock)>0 then
   -- Goods can come back without money going back. Record the confirmed
   -- conditions first so the cancellation's own restore finds nothing
   -- outstanding and cannot make damaged units sellable.
   v_returned:=public.record_invoice_stock_return(i.id,v_stock,coalesce(p_note,r.reason),r.id);
  end if;
  v_cancel:=public.cancel_invoice_recorded(i.id,coalesce(p_note,r.reason),r.id);
 else
  if jsonb_array_length(v_lines)=0 or jsonb_array_length(v_sources)=0 then
   raise exception 'There is nothing left to refund on this invoice'; end if;
  v_refund:=public.refund_invoice_recorded(i.id,v_lines,v_sources,v_stock,coalesce(p_note,r.reason),r.id);
 end if;

 update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
   response_note=p_note,
   payload=payload||jsonb_build_object('executed_plan',v_plan,'overrides',coalesce(p_overrides,'[]'::jsonb),
     'stock_confirmed',v_stock,'refund_recorded',v_refund is not null,
     'refund',v_refund,'cancellation',v_cancel,
     'outcome',coalesce(v_cancel,v_refund))
 where id=r.id;
 perform public.write_audit_ex('approval_requests',r.id,'invoice_action_approved',to_jsonb(r),
   jsonb_build_object('plan',v_plan,'overrides',p_overrides,'stock',v_stock,
     'refund',v_refund,'cancellation',v_cancel),'invoices',coalesce(p_note,r.reason),i.store_id);

 return jsonb_build_object('request_id',r.id,'status','approved','plan',v_plan,
   -- Both outcomes, separately. "Refund recorded" is true only when a refund
   -- was actually recorded, never because a checkbox was ticked.
   'refund',v_refund,'cancellation',v_cancel,
   'refund_recorded',v_refund is not null,
   'refunded_amount',coalesce((v_refund->>'refunded_amount')::numeric,0),
   'goods_returned',v_returned,
   'refund_still_due',case when v_action='cancel' and v_refund is null
                           then coalesce((v_plan->>'refund_due')::numeric,0) else 0 end,
   'outcome',coalesce(v_cancel,v_refund));
end $$;
grant execute on function public.resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) to authenticated;

-- ---------------------------------------------------------------------
-- A CANCELLED INVOICE OWES ITS MONEY BACK
--
-- invoice_charge_total() reduces the charge by REFUNDS only; it knows nothing
-- about cancellation. So a cancelled invoice holding the customer's money
-- reported remaining_charge = the full total and refund_due = 0.00 -- the one
-- figure the combined cancel/refund workflow exists to surface.
--
-- invoice_charge_total() itself is left alone: the refund engine uses it to
-- decide when an invoice becomes 'refunded', and the request-completion
-- trigger uses it to decide when a pending request has been satisfied.
-- Cancellation is applied here, where the position is presented.
create or replace function public.invoice_financial_position(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; n numeric; charge numeric;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 n:=public.invoice_net_received(i.id);
 -- Cancelling clears what is still owed. Anything held then owes back.
 charge:=case when i.status='cancelled' then 0 else public.invoice_charge_total(i.id) end;
 return jsonb_build_object('total',i.total_amount,'net_received',n,'remaining_charge',charge,
 'outstanding',case when i.status in ('cancelled','refunded') then 0 else greatest(charge-n,0) end,
 'refund_due',greatest(n-charge,0),'overpayment_refundable',greatest(n-i.total_amount,0),
 'refunded',coalesce((select sum(amount) from public.invoice_refunds where invoice_id=i.id),0),
 'status',i.status,'business_date',i.business_date);
end $$;

notify pgrst,'reload schema';
commit;
