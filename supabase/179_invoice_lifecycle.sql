begin;
alter table public.invoices add column if not exists reopened_at timestamptz;
alter table public.invoice_benefit_values add column if not exists cancelled_unused_value numeric(12,2) not null default 0 check(cancelled_unused_value>=0);
create table public.invoice_reopen_benefits(
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.invoices(id),
 source_ledger_id uuid not null unique references public.customer_credit_ledger(id),
 request_id uuid not null,amount numeric(12,2) not null check(amount>0),applied_at timestamptz,
 created_by uuid references public.profiles(id),created_at timestamptz not null default now());
alter table public.invoice_reopen_benefits enable row level security;
create policy reopen_benefits_read on public.invoice_reopen_benefits for select to authenticated using(
 exists(select 1 from public.invoices i where i.id=invoice_id and public.user_has_store_access(i.store_id)));

create or replace function public.invoice_reopen_preview(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare i public.invoices%rowtype; blockers text[]:='{}'; credits numeric;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can reopen invoices'; end if;
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if i.status not in ('cancelled','refunded') then blockers:=array_append(blockers,'Only cancelled or refunded invoices can be reopened'); end if;
 if i.status='refunded' and not exists(select 1 from public.invoice_refunds where invoice_id=i.id) then
  blockers:=array_append(blockers,'Historical refunded status has no payment-source refund evidence'); end if;
 if exists(select 1 from public.invoice_refunds where invoice_id=i.id and payment_id is null) then blockers:=array_append(blockers,'Resolve historical refund payment sources first'); end if;
 if i.stock_snapshot_version is null and exists(select 1 from public.invoice_items where invoice_id=i.id and line_kind in ('promotion','premium_bundle','voucher')) then
  blockers:=array_append(blockers,'Historical component/stock snapshots require review before reopening'); end if;
 if exists(select 1 from public.rentals where invoice_id=i.id and status::text in ('active','paid')) then
  blockers:=array_append(blockers,'Resolve the existing active rental in Rentals before reopening'); end if;
 if exists(select 1 from public.invoice_stock_dispositions where invoice_id=i.id and damaged_quantity>0) then
  blockers:=array_append(blockers,'Confirm replacement stock for damaged returns before reopening'); end if;
 if exists(select 1 from public.invoice_benefit_values b join public.customer_reward_vouchers v on v.id=b.reward_voucher_id where b.invoice_id=i.id and v.status='revoked') then
  blockers:=array_append(blockers,'Revoked voucher units need an explicit replacement allocation before reopening'); end if;
 select coalesce(sum(l.amount),0) into credits from public.customer_credit_ledger l
 where (l.source_type='invoice_cancel_benefit' and l.source_record_id=i.id
   or l.source_type='invoice_benefit_refund' and exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id and r.request_id=l.source_record_id))
   and not exists(select 1 from public.invoice_reopen_benefits b where b.source_ledger_id=l.id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('can_reopen',cardinality(blockers)=0,'blockers',to_jsonb(blockers),
   'credit_to_reinstate_after_settlement',credits,'stock_to_issue',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.invoice_stock_to_deduct(i.id) s where s.quantity>0),
   'explanation','Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. Previously revoked credit is reinstated once the reopened invoice is fully settled.');
end $$;

create or replace function public.apply_reopened_invoice_benefits()
returns trigger language plpgsql security definer set search_path=public as $$
declare r record; l public.customer_credit_lots%rowtype;
begin
 if new.status not in ('paid','completed_foc') then return new; end if;
 for r in select b.*,e.lot_id from public.invoice_reopen_benefits b join public.customer_credit_ledger e on e.id=b.source_ledger_id
   where b.invoice_id=new.id and b.applied_at is null order by b.id for update of b loop
   select * into l from public.customer_credit_lots where id=r.lot_id for update;
   update public.customer_credit_lots set remaining_amount=remaining_amount+r.amount,status='active',updated_at=now() where id=l.id;
   insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,reverses_entry_id,created_by,approved_by)
    values(l.wallet_id,l.customer_id,'reverse',l.category,r.amount,l.id,'invoice_reopen',r.request_id,l.store_id,'Reopened invoice settled',r.source_ledger_id,auth.uid(),auth.uid());
   update public.invoice_reopen_benefits set applied_at=now() where id=r.id;
   update public.invoice_benefit_values set cancelled_unused_value=greatest(0,cancelled_unused_value-r.amount) where lot_id=l.id;
 end loop;
 return new;
end $$;
create trigger invoice_reopen_benefits_settled after update of status on public.invoices for each row execute function public.apply_reopened_invoice_benefits();

create or replace function public.reopen_invoice(p_invoice_id uuid,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; p jsonb; n numeric; v_rev int; v_status invoice_status;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can reopen invoices'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'Reopening reason and request ID are required'; end if;
 select * into i from public.invoices where id=p_invoice_id for update;
 if exists(select 1 from public.invoice_revisions where invoice_id=i.id and request_id=p_request_id) then
  return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replayed',true); end if;
 p:=public.invoice_reopen_preview(i.id);
 if not (p->>'can_reopen')::boolean then raise exception 'Reopening requires resolution: %',p->'blockers'; end if;
 select coalesce(max(revision_no),0)+1 into v_rev from public.invoice_revisions where invoice_id=i.id;
 insert into public.invoice_revisions(invoice_id,revision_no,snapshot,edited_by,edit_reason,request_id)
  values(i.id,v_rev,jsonb_build_object('invoice',to_jsonb(i),'reopen_preview',p),auth.uid(),p_reason,p_request_id);
 insert into public.invoice_reopen_benefits(invoice_id,source_ledger_id,request_id,amount,created_by)
  select i.id,l.id,p_request_id,l.amount,auth.uid() from public.customer_credit_ledger l
  where (l.source_type='invoice_cancel_benefit' and l.source_record_id=i.id
    or l.source_type='invoice_benefit_refund' and exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id and r.request_id=l.source_record_id))
    and not exists(select 1 from public.invoice_reopen_benefits b where b.source_ledger_id=l.id);
 n:=public.invoice_net_received(i.id);
 v_status:=case when i.total_amount=0 and i.has_foc then 'completed_foc'::invoice_status
  when n>=i.total_amount then 'paid'::invoice_status when n>0 then 'partially_paid'::invoice_status else 'unpaid'::invoice_status end;
 if v_status in ('paid','completed_foc') then perform public.deduct_invoice_stock(i.id,'Explicit invoice reopening: '||p_reason); end if;
 update public.invoices set status=v_status,paid_amount=n,reopened_at=clock_timestamp(),edit_count=coalesce(edit_count,0)+1,edited_at=now(),edited_by=auth.uid() where id=i.id;
 perform public.reconcile_invoice_commissions(i.id,'Reopening: '||p_reason);
 update public.invoice_revisions set after_snapshot=(select to_jsonb(v) from public.invoices v where v.id=i.id) where invoice_id=i.id and revision_no=v_rev;
 perform public.write_audit_ex('invoices',i.id,'invoice_reopened',to_jsonb(i),p,'invoices',p_reason,i.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true);
end $$;

create or replace function public.cancel_invoice_recorded(p_invoice_id uuid,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; v_lot record; v_rev int; r record;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can cancel invoices'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'Cancellation reason and request ID are required'; end if;
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if i.status='cancelled' then return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'unchanged',true); end if;
 if exists(select 1 from public.rentals where invoice_id=i.id and status::text in ('active','paid')) then raise exception 'Return or resolve the active rental before cancelling this invoice'; end if;
 if exists(select 1 from public.invoice_items it where it.invoice_id=i.id and it.credit_issued_at is not null and not exists(select 1 from public.invoice_benefit_values b where b.invoice_item_id=it.id)) then
   raise exception 'Record the original benefit allocations before cancelling an issued credit/bundle invoice'; end if;
 select coalesce(max(revision_no),0)+1 into v_rev from public.invoice_revisions where invoice_id=i.id;
 insert into public.invoice_revisions(invoice_id,revision_no,snapshot,edited_by,edit_reason,request_id)
  values(i.id,v_rev,jsonb_build_object('invoice',to_jsonb(i)),auth.uid(),p_reason,p_request_id);
 for v_lot in select cl.* from public.customer_credit_lots cl join public.invoice_benefit_values b on b.lot_id=cl.id
  where b.invoice_id=i.id and cl.remaining_amount>0 order by cl.id for update of cl loop
  update public.invoice_benefit_values set cancelled_unused_value=cancelled_unused_value+v_lot.remaining_amount where lot_id=v_lot.id;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(v_lot.wallet_id,v_lot.customer_id,'adjust_decrease',v_lot.category,v_lot.remaining_amount,v_lot.id,'invoice_cancel_benefit',i.id,v_lot.store_id,p_reason,auth.uid(),auth.uid());
  update public.customer_credit_lots set remaining_amount=0,updated_at=now() where id=v_lot.id;
 end loop;
 for r in select v.* from public.customer_reward_vouchers v join public.invoice_benefit_values b on b.reward_voucher_id=v.id where b.invoice_id=i.id and v.status='held' for update of v loop
  update public.invoice_benefit_values set cancelled_unused_value=cancelled_unused_value+r.quantity where reward_voucher_id=r.id;
  update public.customer_reward_vouchers set status='revoked',notes=concat_ws(E'\n',notes,'Cancelled invoice: '||p_reason) where id=r.id;
  if exists(select 1 from public.vouchers where id=r.voucher_id and qty_type='limited') then
   update public.voucher_store_stock set current_qty=current_qty+r.quantity where store_id=r.store_id and voucher_id=r.voucher_id;
  end if;
 end loop;
 perform public.restore_invoice_stock(i.id,'Cancelled invoice: '||p_reason);
 for r in select store_id,voucher_id,sum(quantity)::int quantity from public.invoice_voucher_movements where invoice_id=i.id group by store_id,voucher_id having sum(quantity)>0 loop
  update public.voucher_store_stock set current_qty=current_qty+r.quantity where store_id=r.store_id and voucher_id=r.voucher_id;
  insert into public.invoice_voucher_movements(invoice_id,store_id,voucher_id,quantity,reason,created_by) values(i.id,r.store_id,r.voucher_id,-r.quantity,'Cancellation: '||p_reason,auth.uid());
 end loop;
 update public.purchased_therapy_entitlements set status='refunded',updated_at=now() where invoice_id=i.id and status in ('pending_activation','scheduled');
 update public.invoices set status='cancelled',edited_by=auth.uid(),edited_at=now(),edit_count=coalesce(edit_count,0)+1 where id=i.id;
 perform public.reconcile_invoice_commissions(i.id,'Cancellation: '||p_reason);
 update public.invoice_revisions set after_snapshot=(select to_jsonb(v) from public.invoices v where v.id=i.id) where invoice_id=i.id and revision_no=v_rev;
 perform public.write_audit_ex('invoices',i.id,'invoice_cancelled',to_jsonb(i),public.invoice_financial_position(i.id),'invoices',p_reason,i.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'note','Payments remain recorded. Record any actual refund separately.');
end $$;
revoke all on function public.apply_reopened_invoice_benefits() from public,anon,authenticated;
revoke all on function public.invoice_reopen_preview(uuid),public.reopen_invoice(uuid,text,uuid),public.cancel_invoice_recorded(uuid,text,uuid) from public,anon;
grant execute on function public.invoice_reopen_preview(uuid),public.reopen_invoice(uuid,text,uuid),public.cancel_invoice_recorded(uuid,text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
