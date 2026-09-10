begin;
create or replace function public.resolve_invoice_action(p_request_id uuid,p_approve boolean,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.approval_requests%rowtype; i public.invoices%rowtype; result jsonb;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can resolve invoice requests'; end if;
 -- Invoice first: same lock order as refund/cancellation operations.
 select * into r from public.approval_requests where id=p_request_id;
 select * into i from public.invoices where id=r.related_record_id for update;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 select * into r from public.approval_requests where id=p_request_id for update;
 if r.status<>'pending' or r.request_type not in ('invoice_refund','invoice_cancel') then raise exception 'Pending invoice request not found'; end if;
 if p_approve and r.request_type='invoice_refund' then
  raise exception 'Open the invoice to allocate the actual refund, original payment sources, and returned stock'; end if;
 if p_approve then
  result:=public.cancel_invoice_recorded(i.id,coalesce(nullif(trim(p_note),''),r.reason),r.id);
 else
  update public.invoices set status=case when public.invoice_net_received(i.id)>=public.invoice_charge_total(i.id) then
    case when total_amount=0 and has_foc then 'completed_foc'::invoice_status else 'paid'::invoice_status end
    when public.invoice_net_received(i.id)>0 then 'partially_paid'::invoice_status else 'unpaid'::invoice_status end
    where id=i.id and status in ('refund_requested','cancellation_requested');
 end if;
 update public.approval_requests set status=case when p_approve then 'approved'::approval_status else 'rejected'::approval_status end,
  approved_by=auth.uid(),approved_at=now(),response_note=p_note where id=r.id;
 perform public.write_audit_ex('approval_requests',r.id,'invoice_request_resolved',to_jsonb(r),jsonb_build_object('approved',p_approve),'invoices',p_note,i.store_id);
 return coalesce(result,'{}')||jsonb_build_object('success',true);
end $$;
-- Completing the detailed workflow also resolves a staff request atomically.
create or replace function public.complete_invoice_finance_request()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_table_name='invoice_refunds' then
  update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
    response_note='Refund recorded with line, payment-source and stock evidence; request '||new.request_id
    where related_record_id=new.invoice_id and request_type='invoice_refund' and status='pending';
 elsif new.status='cancelled' then
  update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),response_note='Audited cancellation recorded'
    where related_record_id=new.id and request_type='invoice_cancel' and status='pending';
 end if;
 return new;
end $$;
create trigger invoice_refund_request_completed after insert on public.invoice_refunds for each row execute function public.complete_invoice_finance_request();
create trigger invoice_cancel_request_completed after update of status on public.invoices for each row execute function public.complete_invoice_finance_request();
revoke all on function public.complete_invoice_finance_request() from public,anon,authenticated;
revoke all on function public.resolve_invoice_action(uuid,boolean,text) from public,anon;
grant execute on function public.resolve_invoice_action(uuid,boolean,text) to authenticated;
notify pgrst,'reload schema';
commit;
