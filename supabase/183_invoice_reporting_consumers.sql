begin;
-- Every invoice sales channel reads the same receipt/refund events. TikTok
-- remains a separate channel with its existing settlement-date rules.
create or replace function public.report_sales_reconciliation(p_store_id uuid default null,p_from date default null,p_to date default null)
returns table(channel text,transactions bigint,amount numeric)
language sql stable security definer set search_path=public as $$
 select 'invoice_sales',count(distinct i.id),coalesce(sum(e.amount),0) from public.invoice_sales_ledger() e
 join public.invoices i on i.id=e.invoice_id where i.is_exchange is not true
 and (p_store_id is null or i.store_id=p_store_id) and (p_from is null or e.sales_date>=p_from) and (p_to is null or e.sales_date<=p_to)
 union all
 select 'exchange_invoices',count(distinct i.id),coalesce(sum(e.amount),0) from public.invoice_sales_ledger() e
 join public.invoices i on i.id=e.invoice_id where i.is_exchange is true
 and (p_store_id is null or i.store_id=p_store_id) and (p_from is null or e.sales_date>=p_from) and (p_to is null or e.sales_date<=p_to)
 union all
 select 'tiktok_settlement',count(*),coalesce(sum(r.settlement_amount),0) from public.tiktok_settlement_rows r
 where r.confirmed and r.is_current and public.user_has_store_access(r.store_id)
 and (p_store_id is null or r.store_id=p_store_id)
 and (p_from is null or coalesce(r.order_created_time,r.settled_time)::date>=p_from)
 and (p_to is null or coalesce(r.order_created_time,r.settled_time)::date<=p_to)
$$;
-- A private amount reader for the affiliate portal's separately scoped purchase
-- query. Affiliates have no general store access and cannot call this helper.
create or replace function public.invoice_received_sales_amount(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
 select case when i.business_date is null then null else
 coalesce((select sum(case when p.entry_kind='correction_reversal' then -p.amount else p.amount end)
 from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id
 where p.invoice_id=i.id and not coalesce(m.is_wallet_credit,false)),0)
 -coalesce((select sum(r.amount-r.credit_returned) from public.invoice_refunds r where r.invoice_id=i.id and r.payment_id is not null),0) end
 from public.invoices i where i.id=p_invoice_id
$$;
revoke all on function public.invoice_received_sales_amount(uuid) from public,anon,authenticated;
do $$ declare f text; begin
 select pg_get_functiondef('public.dashboard_summary()'::regprocedure) into f;
 if position('return v_out;' in f)=0 then raise exception 'Unexpected dashboard summary'; end if;
 execute replace(f,'return v_out;',
  'return v_out || jsonb_build_object(''today_sales'',public.sales_between(public.sg_today(),public.sg_today(),null),''today_count'',(select count(distinct invoice_id) from public.invoice_sales_ledger() where sales_date=public.sg_today()));');
 select pg_get_functiondef('public.affiliate_portal_purchases()'::regprocedure) into f;
 if position('i.created_at::date as purchase_date' in f)=0 then raise exception 'Unexpected affiliate purchase report'; end if;
 f:=replace(f,'i.created_at::date as purchase_date','i.business_date as purchase_date');
 f:=replace(f,'i.total_amount as purchase_amount','public.invoice_received_sales_amount(i.id) as purchase_amount');
 execute f;
end $$;
revoke all on function public.report_sales_reconciliation(uuid,date,date) from public,anon;
grant execute on function public.report_sales_reconciliation(uuid,date,date) to authenticated;
notify pgrst,'reload schema';
commit;
