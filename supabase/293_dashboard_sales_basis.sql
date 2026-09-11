begin;
-- =====================================================================
-- THE DASHBOARD CONTRADICTED ITSELF
--
-- 292 moved received money onto the day it arrived, but only the money. The
-- tiles beside it on the same dashboard, under the same period selector, were
-- left on the invoice's own date:
--
--   sales, invoice_count      -> the day the money arrived      (292)
--   items_sold, discount_total-> the invoice's business_date    (unchanged)
--   discount_today            -> the invoice's business_date    (unchanged)
--
-- So for an invoice raised in August and paid in September, September showed
-- the sale and August showed the items and the discount. That is the reported
-- wrong figure, and it is a defect in 292 rather than in the dashboard.
--
-- A second problem, from the same change. Every one of those metrics also
-- required business_date IS NOT NULL, so an invoice whose date was never
-- recorded was dropped from them entirely — even though the interface now shows
-- that invoice dated by its creation day. The list showed a date; the reports
-- pretended the invoice did not exist.
--
-- Two dates are needed, and they answer different questions:
--
--   invoice_sales_day()      the day this invoice's money first arrived.
--                            Anything sitting beside a money figure uses it, so
--                            a period's sales, count, items and discounts all
--                            describe the same sales.
--
--   invoice_effective_date() the document's own date: what was recorded, or
--                            failing that the Singapore day it was created.
--                            Mirrors invoiceDate() in the interface exactly, so
--                            a listing and a report cannot disagree about which
--                            day an invoice belongs to.
--
-- No payment, refund, commission or payout is created, altered or deleted.
--
-- Requires 292. Additive and idempotent.
-- =====================================================================

-- The day the money first arrived. Falls back to the document's own date only
-- when nothing has been received, so an unpaid invoice still has somewhere to sit.
create or replace function public.invoice_sales_day(p_invoice_id uuid)
returns date language sql stable security definer set search_path to 'public' as $$
 select coalesce(
   (select min(public.payment_sales_date(p.effective_at,p.created_at))
      from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id
     where p.invoice_id=i.id and p.entry_kind<>'correction_reversal'
       and not coalesce(m.is_wallet_credit,false)),
   i.business_date,
   (i.created_at at time zone 'Asia/Singapore')::date)
 from public.invoices i where i.id=p_invoice_id
$$;
grant execute on function public.invoice_sales_day(uuid) to authenticated;

-- The document's own date. Never null for a real invoice, which is the point.
create or replace function public.invoice_effective_date(p_invoice_id uuid)
returns date language sql stable security definer set search_path to 'public' as $$
 select coalesce(i.business_date,(i.created_at at time zone 'Asia/Singapore')::date)
 from public.invoices i where i.id=p_invoice_id
$$;
grant execute on function public.invoice_effective_date(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- The dashboard tiles now describe the same sales as the sales figure.
-- ---------------------------------------------------------------------
do $do$
declare f text; v_old text; v_new text; v_hits int;
begin
 select pg_get_functiondef('public.dashboard_sales(text,date,date,uuid)'::regprocedure) into f;
 if position('invoice_sales_day' in f)>0 then
  raise notice 'dashboard_sales already shares one basis'; return; end if;

 v_old:='i.deleted_at is null and i.business_date is not null and (r.date_from is null or i.business_date>=r.date_from) and (r.date_to is null or i.business_date<=r.date_to)';
 v_new:='i.deleted_at is null and (r.date_from is null or public.invoice_sales_day(i.id)>=r.date_from) and (r.date_to is null or public.invoice_sales_day(i.id)<=r.date_to)';
 v_hits:=(length(f)-length(replace(f,v_old,'')))/length(v_old);
 if v_hits<>2 then
  raise exception 'Expected two business_date filters in dashboard_sales, found % — align them by hand', v_hits;
 end if;
 f:=replace(f,v_old,v_new);

 -- The stated basis has to match what the numbers now do.
 f:=replace(f,'Actual eligible receipts by invoice business date; refunds by refund date',
              'Actual eligible receipts by the day they were received; refunds by refund date');
 execute f;
 raise notice 'dashboard sales, count, items and discounts now share one basis';
end $do$;

do $do$
declare f text; v_old text;
begin
 select pg_get_functiondef('public.dashboard_summary()'::regprocedure) into f;
 if position('invoice_sales_day' in f)>0 then
  raise notice 'dashboard_summary already shares one basis'; return; end if;
 v_old:='business_date=v_today';
 if position(v_old in f)=0 then
  raise notice 'Unexpected discount_today filter; left as it is'; return; end if;
 execute replace(f,v_old,'public.invoice_sales_day(id)=v_today');
 raise notice 'today''s discount total follows the same basis';
end $do$;

-- ---------------------------------------------------------------------
-- Detail reports stop dropping invoices whose date was never recorded.
--
-- These describe the DOCUMENT — what was sold, at what price, with what
-- discount — so they keep the invoice's own date. What changes is that an
-- invoice with no recorded date now appears under its creation day, exactly as
-- the invoice list shows it, instead of vanishing.
-- ---------------------------------------------------------------------
do $do$
declare f text; r record; v_changed int:=0;
begin
 for r in select p.oid, p.oid::regprocedure::text sig, p.proname from pg_proc p
           join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public'
            and p.proname in ('report_pricing','report_discounts','report_foc_lines',
                              'report_foc_summary','affiliate_portal_purchases')
 loop
  f:=pg_get_functiondef(r.oid);
  if position('invoice_effective_date' in f)>0 then continue; end if;
  if position('i.business_date' in f)=0 and position('business_date' in f)=0 then continue; end if;
  -- Only the NULL exclusion and the column reference change; the date semantics
  -- are identical for every invoice that already has a recorded date.
  f:=replace(f,'i.business_date is not null and ','');
  f:=replace(f,'business_date is not null and ','');
  f:=replace(f,'i.business_date','public.invoice_effective_date(i.id)');
  f:=replace(f,'invoices.business_date','public.invoice_effective_date(invoices.id)');
  execute f;
  v_changed:=v_changed+1;
  raise notice 'detail report now dates undated invoices by their creation day: %', r.proname;
 end loop;
 if v_changed=0 then raise notice 'detail reports already use the effective date'; end if;
end $do$;

notify pgrst,'reload schema';
commit;
