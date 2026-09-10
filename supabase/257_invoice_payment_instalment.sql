begin;
-- =====================================================================
-- INSTALMENT DETAILS RECORDED WITH THE PAYMENT THAT USES THEM
--
-- The instalment arrangement used to be chosen at the top of the invoice
-- creation form and written by create_invoice_with_details. It now belongs
-- inside Record Payment, where the person actually taking the money chooses it.
--
-- Moving the control must not turn it into browser-only state, and it must not
-- become a second round trip that can succeed while the payment fails. This
-- wrapper sets the arrangement and records the payment in ONE transaction:
-- either the invoice carries the arrangement and the payment exists, or
-- neither happened.
--
-- The arrangement stays exactly what it was: invoice-level metadata, validated
-- by 171's constraint and trigger. Nothing here makes it a property of an
-- individual payment, and nothing here marks an invoice paid — that remains
-- record_invoice_payment's job, from the amounts actually recorded.
--
-- Requires 171 and the existing record_invoice_payment. Additive.
-- =====================================================================

create or replace function public.record_invoice_payment_with_instalment(
 p_invoice_id uuid, p_payments jsonb, p_request_id uuid, p_instalment jsonb default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; v_cat text; v_method uuid; v_months integer; v_changed boolean:=false;
begin
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found then raise exception 'Invoice not found'; end if;
 if not public.user_has_store_access(i.store_id) then
  raise exception 'No access to this invoice' using errcode='42501'; end if;

 if p_instalment is not null and jsonb_typeof(p_instalment)='object' then
  v_cat:=nullif(p_instalment->>'instalment_category','');
  v_method:=nullif(p_instalment->>'instalment_method_id','')::uuid;
  v_months:=nullif(p_instalment->>'instalment_months','')::integer;

  -- An arrangement is all three fields or none; 171's constraint says the same,
  -- and this gives the person a sentence rather than a constraint name.
  if v_cat is not null and (v_method is null or coalesce(v_months,0)<=0) then
   raise exception 'Choose the instalment payment method and a positive number of months';
  end if;
  if v_cat is null and (v_method is not null or v_months is not null) then
   raise exception 'Choose the instalment type, or clear the arrangement entirely';
  end if;

  v_changed:=(i.instalment_category,i.instalment_method_id,i.instalment_months)
             is distinct from (v_cat,v_method,v_months);
  if v_changed then
   update public.invoices
      set instalment_category=v_cat, instalment_method_id=v_method, instalment_months=v_months
    where id=p_invoice_id;
   perform public.write_audit_ex('invoices',p_invoice_id,'instalment_arrangement_set',
     jsonb_build_object('instalment_category',i.instalment_category,
       'instalment_method_id',i.instalment_method_id,'instalment_months',i.instalment_months),
     jsonb_build_object('instalment_category',v_cat,
       'instalment_method_id',v_method,'instalment_months',v_months),
     'invoices',null,i.store_id);
  end if;
 end if;

 -- The payment itself, unchanged: its own validation, request-id replay
 -- protection and status transitions all still belong to it.
 return public.record_invoice_payment(p_invoice_id,p_payments,p_request_id);
end $$;
grant execute on function public.record_invoice_payment_with_instalment(uuid,jsonb,uuid,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
