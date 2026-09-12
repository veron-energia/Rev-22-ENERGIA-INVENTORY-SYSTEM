begin;
-- =====================================================================
-- THE APPROVALS PAGE REACHES THE VALIDATED WORKFLOW
--
-- ApprovalsPage called resolve_invoice_action() -- the pre-295 function. For a
-- cancellation that meant an Owner/Manager could approve from Approvals with
-- NO five-day check, NO override reason, NO confirmation of returned goods and
-- NO approval-time revalidation, all of which the invoice page enforces. The
-- same request approved from two places did two different things.
--
-- Two changes, both closing that gap rather than papering over it:
--
--   invoice_action_request_detail()  what an approver needs to decide, with
--                                    store scope enforced before anything is
--                                    returned -- resolved requests included
--   resolve_invoice_action()         now delegates to the v2 workflow instead
--                                    of being a second way in with weaker rules
--
-- Requires 295 and 296. Idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- What an approver is shown, and who may see it.
--
-- Authorization comes first: the request is only described to somebody with
-- access to the invoice's store. That holds for an already-resolved request
-- too -- its outcome is as sensitive as the decision was.
-- ---------------------------------------------------------------------
create or replace function public.invoice_action_request_detail(p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare r public.approval_requests%rowtype; i public.invoices%rowtype; v_now jsonb; v_legacy boolean;
begin
 select * into r from public.approval_requests where id=p_request_id;
 if not found or r.request_type not in ('invoice_cancel','invoice_refund') then
  raise exception 'Invoice request not found'; end if;
 select * into i from public.invoices where id=r.related_record_id;
 if not found or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice request not accessible'; end if;

 -- A request raised before the guided workflow carries no plan and no line
 -- selection. It is reported as such; nothing is guessed on its behalf.
 v_legacy:=r.payload->'plan' is null;
 if not v_legacy and r.status='pending' then
  v_now:=public.invoice_action_plan(i.id,r.payload->>'action',coalesce(r.payload->'lines','[]'::jsonb));
 end if;

 return jsonb_build_object(
  'request_id',r.id,'status',r.status,'request_type',r.request_type,
  'action',r.payload->>'action','reason',r.reason,'return_notes',r.payload->>'return_notes',
  'created_at',r.created_at,'approved_at',r.approved_at,
  'rejection_reason',r.rejection_reason,'response_note',r.response_note,
  'requested_by',(select full_name from public.profiles where id=r.requested_by),
  'approved_by',(select full_name from public.profiles where id=r.approved_by),
  'store_id',i.store_id,'store',(select name from public.stores where id=i.store_id),
  'invoice_id',i.id,'invoice_no',i.invoice_no,'invoice_status',i.status,
  'requested_lines',coalesce(r.payload->'lines','[]'::jsonb),
  'requested_amount',r.payload->>'requested_amount',
  'requested_plan',r.payload->'plan',
  'current_plan',v_now,
  -- Whether anything material moved between asking and now.
  'changed',case when v_now is null then null
                 else (v_now->>'plan_hash') is distinct from (r.payload->>'plan_hash') end,
  'legacy',v_legacy,
  'legacy_note',case when v_legacy then
    'This request predates the guided workflow: it records a reason but not which items, quantities or amount were meant. It cannot be approved as it stands. Reject it and raise it again from the invoice so the effects can be derived and reviewed.' end,
  -- Already-resolved requests report what actually happened.
  'refund',r.payload->'refund','cancellation',r.payload->'cancellation',
  'overrides',r.payload->'overrides','executed_plan',r.payload->'executed_plan');
end $$;
comment on function public.invoice_action_request_detail(uuid) is
 'Everything an Owner/Manager needs to decide an invoice request, re-derived at read time, with store scope enforced before any detail is returned.';
grant execute on function public.invoice_action_request_detail(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- THE LEGACY ENTRY POINT STOPS BEING A WEAKER SECOND DOOR
--
-- resolve_invoice_action() approved a cancellation directly. Everything 295
-- and 296 added -- the window, override reasons, confirmed goods, revalidation
-- -- was simply absent on that path. It now hands over to the same workflow,
-- so there is one set of rules however the approval is reached.
--
-- It is kept rather than dropped because pending requests and existing callers
-- still reference it.
-- ---------------------------------------------------------------------
create or replace function public.resolve_invoice_action(p_request_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.approval_requests%rowtype;
begin
 select * into r from public.approval_requests where id=p_request_id;
 if not found or r.request_type not in ('invoice_refund','invoice_cancel') then
  raise exception 'Pending invoice request not found'; end if;

 -- Rejection is identical either way, and safe: it changes no money.
 if not p_approve then
  return public.resolve_invoice_action_v2(p_request_id,false,p_note); end if;

 if r.payload->'plan' is null then
  raise exception 'This request predates the guided workflow and cannot be approved directly: it does not record which items, quantities or amount were intended. Reject it and raise it again from the invoice, where the effects are derived and reviewed.'; end if;

 -- Approval needs the things this function never asked for: the confirmed
 -- goods, and a reason for any override the plan requires. Those belong to the
 -- review screen, so send the approver there rather than quietly approving
 -- something narrower than the rules demand.
 raise exception 'Open this request from Approvals or the invoice to review its current effects, confirm the returned goods and give any override reason. Approving without that review is no longer possible.';
end $$;
grant execute on function public.resolve_invoice_action(uuid,boolean,text) to authenticated;

notify pgrst,'reload schema';
commit;
