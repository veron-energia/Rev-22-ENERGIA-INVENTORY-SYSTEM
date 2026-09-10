begin;
-- Sales: actual eligible receipts on invoice business date; external refunds on
-- the day returned. Cancellation never subtracts receipts a second time.
create or replace function public.invoice_sales_ledger()
returns table(invoice_id uuid,event_id uuid,sales_date date,amount numeric,event_kind text)
language sql stable security definer set search_path=public as $$
 select i.id,p.id,i.business_date,
  case when p.entry_kind='correction_reversal' then -p.amount else p.amount end,p.entry_kind
 from public.invoice_payments p join public.invoices i on i.id=p.invoice_id
 join public.payment_methods m on m.id=p.payment_method_id
 where i.deleted_at is null and i.business_date is not null and not coalesce(m.is_wallet_credit,false)
  and public.user_has_store_access(i.store_id)
 union all
 select i.id,r.id,(r.created_at at time zone 'Asia/Singapore')::date,-(r.amount-r.credit_returned),'refund'
 from public.invoice_refunds r join public.invoices i on i.id=r.invoice_id
 where i.deleted_at is null and public.user_has_store_access(i.store_id) and r.payment_id is not null
$$;
create or replace function public.invoice_net_sales_between(p_invoice_id uuid,p_from date,p_to date)
returns numeric language sql stable security definer set search_path=public as $$
 select round(coalesce(sum(e.amount),0),2) from public.invoice_sales_ledger() e where e.invoice_id=p_invoice_id
 and (p_from is null or e.sales_date>=p_from) and (p_to is null or e.sales_date<=p_to)
$$;
create or replace function public.invoice_net_sales(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
 select public.invoice_net_sales_between(p_invoice_id,null,null)
$$;
create or replace function public.invoice_sales_at(p_invoice_id uuid)
returns timestamptz language sql stable security definer set search_path=public as $$
 select business_date::timestamp at time zone 'Asia/Singapore' from public.invoices
 where id=p_invoice_id and public.user_has_store_access(store_id)
$$;
create or replace function public.sales_between(p_from date,p_to date,p_store_id uuid default null)
returns numeric language sql stable security definer set search_path=public as $$
 select round(coalesce(sum(e.amount),0),2) from public.invoice_sales_ledger() e join public.invoices i on i.id=e.invoice_id
 where (p_store_id is null or i.store_id=p_store_id) and (p_from is null or e.sales_date>=p_from) and (p_to is null or e.sales_date<=p_to)
$$;
create or replace function public.dashboard_sales(p_period text default 'day',p_from date default null,p_to date default null,p_store_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r record; v_sales numeric; v_prev numeric; v_count int; v_prev_count int;
begin
 if p_store_id is not null and not public.user_has_store_access(p_store_id) then raise exception 'No access to store'; end if;
 select * into r from public.resolve_period(p_period,p_from,p_to);
 v_sales:=public.sales_between(r.date_from,r.date_to,p_store_id);
 v_prev:=case when r.date_from is null then 0 else public.sales_between(r.prev_from,r.prev_to,p_store_id) end;
 select count(distinct e.invoice_id) into v_count from public.invoice_sales_ledger() e join public.invoices i on i.id=e.invoice_id
  where (p_store_id is null or i.store_id=p_store_id) and (r.date_from is null or e.sales_date>=r.date_from) and (r.date_to is null or e.sales_date<=r.date_to) and e.amount<>0;
 select count(distinct e.invoice_id) into v_prev_count from public.invoice_sales_ledger() e join public.invoices i on i.id=e.invoice_id
  where (p_store_id is null or i.store_id=p_store_id) and e.sales_date between r.prev_from and r.prev_to and e.amount<>0;
 return jsonb_build_object('period',p_period,'label',r.label,'date_from',r.date_from,'date_to',r.date_to,'sales',v_sales,
  'invoice_count',v_count,'items_sold',(select coalesce(sum(it.quantity),0) from public.invoice_items it join public.invoices i on i.id=it.invoice_id
    where public.user_has_store_access(i.store_id) and (p_store_id is null or i.store_id=p_store_id) and i.business_date between r.date_from and r.date_to
    and exists(select 1 from public.invoice_payments p where p.invoice_id=i.id)),
  'discount_total',(select coalesce(sum(i.discount_total),0) from public.invoices i where public.user_has_store_access(i.store_id)
    and (p_store_id is null or i.store_id=p_store_id) and i.business_date between r.date_from and r.date_to
    and exists(select 1 from public.invoice_payments p where p.invoice_id=i.id)),
  'average_invoice',case when v_count>0 then round(v_sales/v_count,2) else 0 end,
  'previous_sales',v_prev,'previous_count',v_prev_count,'change_percent',case when v_prev<>0 then round((v_sales-v_prev)/v_prev*100,1) end,
  'store_id',p_store_id,'basis','Actual eligible receipts by invoice business date; refunds by refund date',
  'pending_date_review',(select count(*) from public.invoices where business_date is null and public.user_has_store_access(store_id)));
end $$;
create or replace function public.dashboard_sales_by_store(p_period text default 'month',p_from date default null,p_to date default null)
returns table(store_id uuid,store_name text,sales numeric,invoice_count integer)
language plpgsql stable security definer set search_path=public as $$
declare r record;
begin
 select * into r from public.resolve_period(p_period,p_from,p_to);
 return query select s.id,s.name,public.sales_between(r.date_from,r.date_to,s.id),
  (select count(distinct e.invoice_id)::int from public.invoice_sales_ledger() e join public.invoices i on i.id=e.invoice_id where i.store_id=s.id
    and (r.date_from is null or e.sales_date>=r.date_from) and (r.date_to is null or e.sales_date<=r.date_to))
 from public.stores s where s.deleted_at is null and public.user_has_store_access(s.id) order by 3 desc,s.name;
end $$;
create or replace function public.dashboard_sales_series(p_period text default 'month',p_from date default null,p_to date default null,p_store_id uuid default null)
returns table(day date,sales numeric,invoice_count integer)
language plpgsql stable security definer set search_path=public as $$
declare r record; v_start date;
begin
 if p_store_id is not null and not public.user_has_store_access(p_store_id) then raise exception 'No access to store'; end if;
 select * into r from public.resolve_period(p_period,p_from,p_to);
 select coalesce(r.date_from,min(e.sales_date)) into v_start from public.invoice_sales_ledger() e;
 return query select d::date,public.sales_between(d::date,d::date,p_store_id),
  (select count(distinct e.invoice_id)::int from public.invoice_sales_ledger() e join public.invoices i on i.id=e.invoice_id where e.sales_date=d::date and (p_store_id is null or i.store_id=p_store_id))
 from generate_series(v_start,coalesce(r.date_to,public.sg_today()),interval '1 day') d order by d;
end $$;
-- Cash collection dates are unchanged. Reversal/replacement entries correct the
-- original collection date/method rather than fabricating a customer refund.
create or replace function public.daily_payments_by_method(p_from date default null,p_to date default null,p_store_id uuid default null)
returns table(pay_date date,payment_method_id uuid,method_name text,amount numeric,payment_count integer)
language sql stable security definer set search_path=public as $$
 select (coalesce(p.effective_at,p.created_at) at time zone 'Asia/Singapore')::date,m.id,m.name,
 round(sum(case when p.entry_kind='correction_reversal' then -p.amount else p.amount end),2),
 sum(case when p.entry_kind='correction_reversal' then -1 else 1 end)::int
 from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id join public.invoices i on i.id=p.invoice_id
 where public.user_has_store_access(i.store_id) and (p_store_id is null or i.store_id=p_store_id)
 and (p_from is null or (coalesce(p.effective_at,p.created_at) at time zone 'Asia/Singapore')::date>=p_from)
 and (p_to is null or (coalesce(p.effective_at,p.created_at) at time zone 'Asia/Singapore')::date<=p_to)
 group by 1,2,3 order by 1,3
$$;
create or replace function public.payment_methods_in_range(p_from date default null,p_to date default null,p_store_id uuid default null)
returns table(payment_method_id uuid,method_name text,is_wallet_credit boolean)
language sql stable security definer set search_path=public as $$
 select distinct d.payment_method_id,d.method_name,m.is_wallet_credit from public.daily_payments_by_method(p_from,p_to,p_store_id) d
 join public.payment_methods m on m.id=d.payment_method_id order by 3,2
$$;
revoke all on function public.invoice_sales_ledger() from public,anon;
grant execute on function public.invoice_sales_ledger() to authenticated;
notify pgrst,'reload schema';
commit;
