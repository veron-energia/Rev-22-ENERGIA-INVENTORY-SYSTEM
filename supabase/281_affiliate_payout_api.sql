begin;
create function public.affiliate_payout_allocation_snapshot(p_id uuid) returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(to_jsonb(x) order by x.invoice_paid_date,x.commission_id),'[]') from (
 select c.id commission_id,c.invoice_id,i.invoice_no,c.tier,c.invoice_paid_date,sum(a.amount) amount
 from public.commission_payout_allocations a join public.commissions c on c.id=a.commission_id
 join public.invoices i on i.id=c.invoice_id where a.payout_id=p_id
 group by c.id,i.invoice_no having sum(a.amount)<>0) x
$$;

create function public.affiliate_payout_save(p_id uuid,p_expected_version integer,p_referrer uuid,p_month date,p_amount numeric,
 p_method uuid,p_date date,p_reference text,p_notes text,p_reason text,p_request uuid) returns jsonb
language plpgsql volatile security definer set search_path=public as $$
declare old public.commission_payouts; current_row public.commission_payouts; method public.payment_methods;
 payload jsonb; prior public.commission_payout_operations; result jsonb; before_alloc jsonb; remaining numeric; piece numeric;
 available numeric; delta numeric; issue text; entry record; v_id uuid; v_referrer uuid; v_month date;
begin
 if not public.affiliate_payout_access(true) then raise exception 'Only active Owners and Managers can record or correct affiliate payouts.' using errcode='42501'; end if;
 if p_request is null then raise exception 'A request identifier is required. Refresh and try again.'; end if;
 perform public.affiliate_payout_lock();
 payload:=jsonb_build_object('id',p_id,'version',p_expected_version,'referrer',p_referrer,'month',p_month,'amount',p_amount,
  'method',p_method,'date',p_date,'reference',nullif(btrim(p_reference),''),'notes',nullif(btrim(p_notes),''),'reason',nullif(btrim(p_reason),''));
 select * into prior from public.commission_payout_operations where request_id=p_request;
 if found then
  if prior.actor_id<>auth.uid() or prior.payload<>payload then raise exception 'This request identifier was already used with different details. Refresh payout history before trying again.'; end if;
  return prior.result;
 end if;
 if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<=0 or p_amount>=10000000000 or round(p_amount,2)<>p_amount then
  raise exception 'Enter a positive payout amount with at most two decimal places.'; end if;
 if p_date is null or p_date>public.sg_today() then raise exception 'Payment date is required and cannot be after today in Singapore.'; end if;
 if length(coalesce(p_reference,''))>500 or length(coalesce(p_notes,''))>4000 or length(coalesce(p_reason,''))>2000 then raise exception 'Reference, notes or correction reason is too long.'; end if;
 if p_id is not null then
  select * into old from public.commission_payouts where id=p_id for update;
  if not found then raise exception 'Payout not found.'; end if;
  if old.status<>'paid' then raise exception 'This historical payout is not active and requires manual review.'; end if;
  if p_expected_version is distinct from old.version then raise exception 'This payout was changed by another user. Refresh its history before editing again.' using errcode='40001'; end if;
  if nullif(btrim(p_reason),'') is null then raise exception 'A correction reason is required.'; end if;
  v_referrer:=old.referrer_customer_id;v_month:=old.payout_month;v_id:=old.id;delta:=p_amount-old.total_amount;
 else
  if p_referrer is null or p_month is null or date_trunc('month',p_month)::date<>p_month then raise exception 'Choose an affiliate and a valid commission month.'; end if;
  v_referrer:=p_referrer;v_month:=p_month;v_id:=gen_random_uuid();delta:=p_amount;
 end if;
 select * into method from public.payment_methods where id=p_method;
 if not found or (p_method is distinct from old.payment_method_id and (not method.is_active or method.deleted_at is not null or method.is_wallet_credit)) then
  raise exception 'Choose an active supported payment method. Historical methods can only be retained on their existing payout.'; end if;
 if p_id is null and (not method.is_active or method.deleted_at is not null or method.is_wallet_credit) then raise exception 'Choose an active supported payment method.'; end if;
 if delta<>0 then
  issue:=public.affiliate_payout_review(v_referrer,v_month);
  if issue is not null then raise exception '%',issue; end if;
  if p_id is not null and (select coalesce(sum(amount),0) from public.commission_payout_allocations where payout_id=p_id)<>old.total_amount then
   raise exception 'The existing allocations do not reconcile with this payout. Review the original payment evidence first.'; end if;
  select b.balance into available from public.affiliate_month_balances() b where b.referrer=v_referrer and b.month=v_month;
  if delta>0 and delta>coalesce(available,0) then raise exception 'Amount exceeds the remaining payable balance of S$%. Refresh the summary.',greatest(coalesce(available,0),0); end if;
 end if;
 before_alloc:=public.affiliate_payout_allocation_snapshot(v_id);
 if p_id is null then
  insert into public.commission_payouts(id,payout_month,referrer_customer_id,total_tier1,total_tier2,total_amount,payment_method_id,
   payment_method_name,payment_date,reference,notes,paid_by)
  values(v_id,v_month,v_referrer,0,0,p_amount,p_method,method.name,p_date,nullif(btrim(p_reference),''),nullif(btrim(p_notes),''),auth.uid());
 end if;
 remaining:=abs(delta);
 if delta>0 then
  -- A refunded/replaced anchor keeps its historical allocation, but its linked
  -- active reversal removes its remaining eligibility for NEW payments.
  for entry in select c.id,c.commission_amount+coalesce((select sum(adj.commission_amount) from public.commissions adj where adj.adjusts_commission_id=c.id and adj.status in ('earned','paid')),0)-coalesce(sum(a.amount),0) available from public.commissions c
   left join public.commission_payout_allocations a on a.commission_id=c.id
   where c.referrer_customer_id=v_referrer and c.invoice_paid_date>=v_month and c.invoice_paid_date<(v_month+interval '1 month')
    and c.status in ('earned','paid') and c.commission_amount>0
   group by c.id having c.commission_amount+coalesce((select sum(adj.commission_amount) from public.commissions adj where adj.adjusts_commission_id=c.id and adj.status in ('earned','paid')),0)>coalesce(sum(a.amount),0)
   order by c.invoice_paid_date,c.created_at,c.id
  loop
   piece:=least(remaining,entry.available);
   insert into public.commission_payout_allocations(payout_id,commission_id,amount,operation_id) values(v_id,entry.id,piece,p_request);
   -- An anchor protects the ORIGINAL commission from invoice re-earning.
   -- Allocation events, not this legacy flag, measure the cash paid.
   update public.commissions set status='paid',payout_id=coalesce(payout_id,v_id) where id=entry.id;
   remaining:=remaining-piece;exit when remaining=0;
  end loop;
 elsif delta<0 then
  for entry in select commission_id,sum(amount) available,max(created_at) last_alloc from public.commission_payout_allocations
   where payout_id=v_id group by commission_id having sum(amount)>0 order by max(created_at) desc,commission_id desc
  loop
   piece:=least(remaining,entry.available);
   insert into public.commission_payout_allocations(payout_id,commission_id,amount,operation_id) values(v_id,entry.commission_id,-piece,p_request);
   remaining:=remaining-piece;exit when remaining=0;
  end loop;
 end if;
 if remaining<>0 then raise exception 'Eligible commission allocations do not reconcile with the balance. No changes were saved; review this affiliate and month.'; end if;
 update public.commission_payouts set total_amount=p_amount,
  total_tier1=case when delta=0 then total_tier1 else (select coalesce(sum(a.amount),0) from public.commission_payout_allocations a join public.commissions c on c.id=a.commission_id where a.payout_id=v_id and c.tier='tier1') end,
  total_tier2=case when delta=0 then total_tier2 else (select coalesce(sum(a.amount),0) from public.commission_payout_allocations a join public.commissions c on c.id=a.commission_id where a.payout_id=v_id and c.tier='tier2') end,
  payment_method_id=p_method,payment_method_name=case when p_method is not distinct from old.payment_method_id then coalesce(old.payment_method_name,method.name) else method.name end,
  payment_date=p_date,reference=nullif(btrim(p_reference),''),notes=nullif(btrim(p_notes),''),version=case when p_id is null then 1 else version+1 end
 where id=v_id returning * into current_row;
 if p_id is null then
  update public.commission_payouts set original_record=to_jsonb(current_row)-'original_record' where id=v_id returning * into current_row;
 end if;
 insert into public.commission_payout_changes(payout_id,version,reason,actor_id,old_record,new_record,old_allocations,new_allocations,request_id)
 values(v_id,current_row.version,case when p_id is null then 'Initial payout record' else btrim(p_reason) end,auth.uid(),
  case when p_id is not null then to_jsonb(old)-'original_record' end,to_jsonb(current_row)-'original_record',before_alloc,public.affiliate_payout_allocation_snapshot(v_id),p_request);
 result:=jsonb_build_object('id',v_id,'version',current_row.version,'amount',current_row.total_amount);
 insert into public.commission_payout_operations(request_id,payload,result,actor_id) values(p_request,payload,result,auth.uid());
 return result;
end $$;

create function public.record_affiliate_payout(p_referrer_customer_id uuid,p_month date,p_amount numeric,p_payment_method_id uuid,
 p_payment_date date,p_reference text,p_notes text,p_request_id uuid) returns jsonb language sql volatile security definer set search_path=public as $$
 select public.affiliate_payout_save(null,null,p_referrer_customer_id,p_month,p_amount,p_payment_method_id,p_payment_date,p_reference,p_notes,null,p_request_id)
$$;
create function public.correct_affiliate_payout(p_payout_id uuid,p_expected_version integer,p_amount numeric,p_payment_method_id uuid,
 p_payment_date date,p_reference text,p_notes text,p_reason text,p_request_id uuid) returns jsonb language sql volatile security definer set search_path=public as $$
 select public.affiliate_payout_save(p_payout_id,p_expected_version,null,null,p_amount,p_payment_method_id,p_payment_date,p_reference,p_notes,p_reason,p_request_id)
$$;
-- Old clients cannot provide a payment date or a stable request identifier.
-- Retain the signature with an actionable error, never an alternate writer.
create or replace function public.create_commission_payout(p_referrer_customer_id uuid,p_month date,p_payment_method_id uuid default null,p_reference text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
begin
 if not public.affiliate_payout_access(true) then raise exception 'Owner or Manager only' using errcode='42501'; end if;
 raise exception 'This payout screen needs an update. Refresh the application and use Record payout, with an amount and payment date.';
end $$;

create function public.affiliate_payout_overview() returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.affiliate_payout_access() then raise exception 'Commission access is restricted to active Owners, Managers and Admins.' using errcode='42501'; end if;
 return jsonb_build_object(
  'groups',(select coalesce(jsonb_agg(to_jsonb(b) order by month desc nulls last,referrer),'[]') from public.affiliate_month_balances() b),
  'payouts',(select coalesce(jsonb_agg(to_jsonb(p)-'original_record' order by payment_date desc,created_at desc,id),'[]') from public.commission_payouts p),
  'methods',(select coalesce(jsonb_agg(to_jsonb(m) order by name),'[]') from public.payment_methods m
   where (m.is_active and m.deleted_at is null and not m.is_wallet_credit) or exists(select 1 from public.commission_payouts p where p.payment_method_id=m.id)));
end $$;
create function public.affiliate_payout_history(p_payout_id uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.affiliate_payout_access() then raise exception 'Commission access is restricted to active Owners, Managers and Admins.' using errcode='42501'; end if;
 return jsonb_build_object('original',(select original_record from public.commission_payouts where id=p_payout_id),
 'allocations',public.affiliate_payout_allocation_snapshot(p_payout_id),
 'changes',(select coalesce(jsonb_agg(to_jsonb(h)||jsonb_build_object('editor',coalesce(p.full_name,'Unavailable · '||h.actor_id::text)) order by h.version desc),'[]')
 from public.commission_payout_changes h left join public.profiles p on p.id=h.actor_id where h.payout_id=p_payout_id));
end $$;

create or replace function public.commission_referrer_names(p_ids uuid[]) returns table(id uuid,full_name text,phone text,deleted_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.affiliate_payout_access() then raise exception 'Commission name lookup is restricted to active Owners, Managers and Admins.' using errcode='42501'; end if;
 return query select c.id,c.full_name,c.phone,c.deleted_at from public.customers c where c.id=any(p_ids)
 and (exists(select 1 from public.commissions cm where c.id in (cm.referrer_customer_id,cm.buyer_customer_id))
  or exists(select 1 from public.commission_payouts p where p.referrer_customer_id=c.id));
end $$;

revoke all on function public.affiliate_payout_allocation_snapshot(uuid),public.affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid) from public,anon,authenticated;
revoke all on function public.record_affiliate_payout(uuid,date,numeric,uuid,date,text,text,uuid),public.correct_affiliate_payout(uuid,integer,numeric,uuid,date,text,text,text,uuid),
 public.create_commission_payout(uuid,date,uuid,text,text),public.affiliate_payout_overview(),public.affiliate_payout_history(uuid),public.commission_referrer_names(uuid[]) from public,anon;
grant execute on function public.record_affiliate_payout(uuid,date,numeric,uuid,date,text,text,uuid),public.correct_affiliate_payout(uuid,integer,numeric,uuid,date,text,text,text,uuid),
 public.create_commission_payout(uuid,date,uuid,text,text),public.affiliate_payout_overview(),public.affiliate_payout_history(uuid),public.commission_referrer_names(uuid[]) to authenticated;
notify pgrst,'reload schema';
commit;
