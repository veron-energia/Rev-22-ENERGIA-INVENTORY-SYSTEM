begin;
-- =====================================================================
-- MONEY IS RECOGNISED ON THE DAY IT WAS RECEIVED
--
-- Until now a payment was reported against the INVOICE's business date, and an
-- invoice with no business date was left out of dated sales entirely. Two
-- consequences the business actually hit:
--
--   * an invoice raised in August and paid in September put the money in
--     AUGUST, which is not when it arrived;
--   * every historical invoice with no business date contributed nothing to any
--     dated report, which is why recovering those dates looked urgent.
--
-- The rule is now the one the business asked for: received money belongs to the
-- day it was received. Refunds already reduced sales on the refund date and are
-- unchanged, so both directions now follow actual movement of money.
--
-- This also removes the reporting pressure from invoices whose business date is
-- still unknown: their payments are dated, so they report correctly regardless.
-- business_date remains what it always was for the document itself — the
-- invoice's own date, shown, filtered and sorted on — it simply no longer
-- decides which period the cash lands in.
--
-- WHAT THIS CHANGES IN PAST REPORTS. Any invoice whose payment fell on a
-- different day from its invoice date moves, by the difference between those
-- dates. Totals over a long enough window are unchanged; period boundaries are
-- not. Run scripts/invoice-dates/report-totals.sql before and after to see the
-- exact movement on real data before anyone relies on the new figures.
--
-- Nothing here creates, alters or deletes a payment, refund, commission or
-- payout. It changes only which date existing money is reported under.
--
-- Requires 171. Where 290 is installed its preview is corrected too; where it
-- is not, that step is skipped. Additive and idempotent.
-- =====================================================================

-- One definition of "the day this money arrived", so nothing can drift.
-- effective_at is the corrected or backdated receipt date; created_at is when
-- the row was written. Singapore, explicitly.
create or replace function public.payment_sales_date(p_effective timestamptz, p_created timestamptz)
returns date language sql immutable as $$
 select (coalesce(p_effective, p_created) at time zone 'Asia/Singapore')::date
$$;
grant execute on function public.payment_sales_date(timestamptz,timestamptz) to authenticated;

-- ---------------------------------------------------------------------
-- The ledger every dated sales report reads.
-- ---------------------------------------------------------------------
create or replace function public.invoice_sales_ledger()
returns table(invoice_id uuid, event_id uuid, sales_date date, amount numeric, event_kind text)
language sql stable security definer set search_path to 'public' as $function$
 select i.id, p.id,
        -- The payment's own date, not the invoice's.
        public.payment_sales_date(p.effective_at, p.created_at),
        case when p.entry_kind='correction_reversal' then -p.amount else p.amount end, p.entry_kind
 from public.invoice_payments p join public.invoices i on i.id=p.invoice_id
 join public.payment_methods m on m.id=p.payment_method_id
 -- No business_date condition: a dated payment is reportable whether or not the
 -- invoice's own date has been established.
 where i.deleted_at is null and not coalesce(m.is_wallet_credit,false)
  and public.user_has_store_access(i.store_id)
 union all
 select i.id, r.id, (r.created_at at time zone 'Asia/Singapore')::date,
        -(r.amount-r.credit_returned), 'refund'
 from public.invoice_refunds r join public.invoices i on i.id=r.invoice_id
 where i.deleted_at is null and public.user_has_store_access(i.store_id) and r.payment_id is not null
$function$;

-- The per-invoice helpers follow the same basis.
create or replace function public.invoice_sales_at(p_invoice_id uuid)
returns timestamptz language sql stable security definer set search_path to 'public' as $function$
 select coalesce(
   -- When the money first arrived.
   (select min(public.payment_sales_date(p.effective_at,p.created_at))
      from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id
     where p.invoice_id=i.id and p.entry_kind<>'correction_reversal'
       and not coalesce(m.is_wallet_credit,false)),
   i.business_date,
   (i.created_at at time zone 'Asia/Singapore')::date)::timestamp at time zone 'Asia/Singapore'
 from public.invoices i
 where i.id=p_invoice_id and public.user_has_store_access(i.store_id)
$function$;

-- An unknown invoice date no longer hides received money.
create or replace function public.invoice_received_sales_amount(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
 select coalesce((select sum(case when p.entry_kind='correction_reversal' then -p.amount else p.amount end)
    from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id
   where p.invoice_id=i.id and not coalesce(m.is_wallet_credit,false)),0)
  -coalesce((select sum(r.amount-r.credit_returned) from public.invoice_refunds r
              where r.invoice_id=i.id and r.payment_id is not null),0)
 from public.invoices i where i.id=p_invoice_id
$function$;

-- ---------------------------------------------------------------------
-- Recording a payment on the day it actually happened.
--
-- Each payment row may carry payment_date. Omitted, it is today in Singapore,
-- exactly as before. A future date is refused; a past one is the whole point.
-- ---------------------------------------------------------------------
do $$
declare f text; v_anchor text;
begin
 select pg_get_functiondef('public.invoice_record_payments_internal(uuid,jsonb)'::regprocedure) into f;
 if position('payment_date' in f)>0 then
  raise notice 'the payment writer already records an effective date'; return; end if;
 v_anchor:='insert into public.invoice_payments (id, invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (coalesce(nullif(v_pay->>''payment_id'','''')::uuid,gen_random_uuid()), p_invoice_id, v_method, v_amount, v_pay->>''reference'', auth.uid());';
 if position(v_anchor in f)=0 then
  raise exception 'Unexpected payment insert; add effective_at by hand rather than guessing';
 end if;
 execute replace(f, v_anchor,
  'insert into public.invoice_payments (id, invoice_id, payment_method_id, amount, payment_reference, received_by, effective_at)
    values (coalesce(nullif(v_pay->>''payment_id'','''')::uuid,gen_random_uuid()), p_invoice_id, v_method, v_amount, v_pay->>''reference'', auth.uid(),
      case when nullif(v_pay->>''payment_date'','''') is null then null
           else (nullif(v_pay->>''payment_date'','''')::date)::timestamp at time zone ''Asia/Singapore'' end);');
 raise notice 'payments can now be recorded with the date they were received';
end $$;

do $$
declare f text; v_anchor text;
begin
 select pg_get_functiondef('public.record_invoice_payment(uuid,jsonb,uuid)'::regprocedure) into f;
 if position('is in the future' in f)>0 then
  raise notice 'the payment date is already validated'; return; end if;
 v_anchor:='if not found then raise exception ''Choose an active payment method''; end if;';
 if position(v_anchor in f)=0 then
  raise exception 'Unexpected payment validator; add the date check by hand';
 end if;
 execute replace(f, v_anchor, v_anchor || chr(10) ||
  '  if nullif(x->>''payment_date'','''') is not null then' || chr(10) ||
  '   if (x->>''payment_date'')::date > (now() at time zone ''Asia/Singapore'')::date then' || chr(10) ||
  '    raise exception ''A payment cannot be dated in the future''; end if;' || chr(10) ||
  '  end if;');
 raise notice 'a future payment date is refused';
end $$;

-- ---------------------------------------------------------------------
-- 290's preview predicted how much a recovery would ADD to dated sales.
-- Under this migration it adds nothing: the money was always reported, on the
-- day it arrived. A preview that still promised a sales movement would be
-- predicting something that cannot happen.
--
-- eligible_received_amount stays — knowing an invoice has taken S$150 is useful
-- when deciding its date. sales_to_add becomes zero, and the wording says why.
-- ---------------------------------------------------------------------
do $do$
declare f text; v_anchor text;
begin
 -- 290 is not a prerequisite for anything else here. A database that has not
 -- installed the date-recovery tooling simply has no preview to correct.
 if to_regprocedure('public.plan_invoice_date_recovery(jsonb)') is null then
  raise notice 'date-recovery tooling (290) is not installed; no preview to correct'; return; end if;
 select pg_get_functiondef('public.plan_invoice_date_recovery(jsonb)'::regprocedure) into f;
 if position('sales are reported on the payment date' in f)>0 then
  raise notice 'the preview already reports no sales movement'; return; end if;
 v_anchor:=$a$'sales_to_add',case when classification='eligible' and i->>'deleted_at' is null then amount else 0 end,$a$;
 if position(v_anchor in f)=0 then
  raise notice 'Unexpected preview shape; sales_to_add was left as it is.'; return; end if;
 execute replace(f,v_anchor,
  $b$'sales_to_add',0,
  'sales_note','Recovering this date moves no money: sales are reported on the payment date.',$b$);
 raise notice 'the preview no longer predicts a sales movement';
end $do$;

notify pgrst,'reload schema';
commit;
