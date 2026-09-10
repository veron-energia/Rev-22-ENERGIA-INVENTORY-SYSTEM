begin;
-- Affiliate portal ownership is enforced by its callers; this helper stays private.
create or replace function public._aff_settled_spend(p_customer uuid)
returns numeric language sql stable security definer set search_path=public as $$
 select coalesce(sum(public.invoice_received_sales_amount(i.id)),0) from public.invoices i
 where i.customer_id=p_customer and i.deleted_at is null
$$;
revoke all on function public._aff_settled_spend(uuid) from public,anon,authenticated;

do $$ declare f text; sig text; anchor text; begin
 select pg_get_functiondef('public.dashboard_sales(text,date,date,uuid)'::regprocedure) into f;
 anchor:='and i.business_date between r.date_from and r.date_to';
 if position(anchor in f)=0 then raise exception 'Unexpected dashboard date bounds'; end if;
 execute replace(f,anchor,'and i.deleted_at is null and i.business_date is not null and (r.date_from is null or i.business_date>=r.date_from) and (r.date_to is null or i.business_date<=r.date_to)');
 select pg_get_functiondef('public.dashboard_summary()'::regprocedure) into f;
 anchor:='''discount_today'', coalesce((select sum(discount_total) from public.invoices where status=''paid'' and paid_at::date = v_today),0)';
 if position(anchor in f)=0 then raise exception 'Unexpected dashboard discount metric'; end if;
 execute replace(f,anchor,'''discount_today'', coalesce((select sum(discount_total) from public.invoices where deleted_at is null and status in (''paid'',''partially_paid'',''completed_foc'') and business_date=v_today and public.user_has_store_access(store_id)),0)');
 foreach sig in array array['public.report_pricing()','public.report_discounts()'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  if position('i.paid_at::date' in f)=0 or position('where i.status = ''paid''' in f)=0 then raise exception 'Unexpected invoice detail report: %',sig; end if;
  f:=replace(f,'i.paid_at::date','i.business_date');
  f:=replace(f,'where i.status = ''paid''','where i.deleted_at is null and i.business_date is not null and public.user_has_store_access(i.store_id) and i.status in (''paid'',''partially_paid'',''completed_foc'')');
  f:=replace(f,'order by i.paid_at desc','order by i.business_date desc,i.id');
  -- Keep the paid_date return-column name for client compatibility. It now
  -- denotes the invoice business date; UI labels make the measure explicit.
  execute f;
 end loop;
 foreach sig in array array['public.report_foc_summary(date,date,uuid)','public.report_foc_lines(date,date,uuid)'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  if position('(i.paid_at at time zone ''Asia/Singapore'')::date' in f)=0 then raise exception 'Unexpected FOC report date: %',sig; end if;
  f:=replace(f,'(i.paid_at at time zone ''Asia/Singapore'')::date','i.business_date');
  f:=replace(f,'i.status in (''paid'',''completed_foc'')','public.user_has_store_access(i.store_id) and i.status in (''paid'',''partially_paid'',''completed_foc'')');
  if sig like '%summary%' then
   f:=replace(f,'v_from := coalesce(p_from, public.sg_today() - 30);','v_from := p_from;');
   f:=replace(f,'v_to   := coalesce(p_to,   public.sg_today());','v_to := p_to;');
   f:=replace(f,'i.business_date between v_from and v_to','i.business_date is not null and (v_from is null or i.business_date>=v_from) and (v_to is null or i.business_date<=v_to)');
  else
   anchor:='i.business_date'||chr(10)||'         between coalesce(p_from, public.sg_today() - 30) and coalesce(p_to, public.sg_today())';
   if position(anchor in f)=0 then raise exception 'Unexpected FOC line bounds'; end if;
   f:=replace(f,anchor,'i.business_date is not null and (p_from is null or i.business_date>=p_from) and (p_to is null or i.business_date<=p_to)');
   f:=replace(f,'pf.full_name, i.paid_at','pf.full_name, (i.business_date::timestamp at time zone ''Asia/Singapore'')');
   f:=replace(f,'order by i.paid_at desc','order by i.business_date desc');
  end if;
  execute f;
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
