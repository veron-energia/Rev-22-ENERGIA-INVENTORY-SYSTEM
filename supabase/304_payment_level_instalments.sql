begin;
-- =====================================================================
-- AN INSTALMENT ARRANGEMENT BELONGS TO A PAYMENT, NOT TO THE WHOLE INVOICE
--
-- Today an invoice carries ONE arrangement, in three columns on `invoices`:
-- instalment_category, instalment_method_id, instalment_months. So an invoice
-- settled as S$100 cash now and S$900 over twelve months cannot be recorded:
-- whatever arrangement is chosen is imposed on the entire invoice, including
-- the part that was paid outright.
--
-- The fix is a separate record, because a promise and a receipt are different
-- things and conflating them is how an invoice ends up marked paid for money
-- nobody has:
--
--   invoice_payments              money that ACTUALLY arrived. Unchanged, and
--                                 still the only thing invoice_net_received
--                                 counts. Its payment_method_id stays the real
--                                 method the money came through.
--
--   invoice_payment_arrangements  the terms under which the rest is to come.
--                                 Carries the real underlying method, never a
--                                 fabricated "Instalment" cash account. Links
--                                 to a payment row when money has been received
--                                 under it, and to nothing when it has not.
--
-- An in-house arrangement with nothing received yet is one arrangement row and
-- no payment row, so the invoice stays unpaid — which is the truth.
--
-- The three columns on `invoices` are NOT dropped and NOT migrated onto
-- payments. Historical invoices keep displaying exactly the terms they were
-- saved with; inventing a payment-level association for them would be
-- fabricating a link that was never recorded.
--
-- Additive. Idempotent.
-- =====================================================================

create table if not exists public.invoice_payment_arrangements (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  -- Set once money has actually been received under this arrangement.
  payment_id uuid references public.invoice_payments(id) on delete set null,
  category text not null check (category in ('in_house','provider_funded')),
  -- The real method the money comes through. Instalment is an arrangement, so
  -- it can never be its own underlying method: the check below forbids it.
  method_id uuid not null references public.payment_methods(id),
  months integer not null check (months > 0),
  covered_amount numeric(12,2) not null check (covered_amount > 0),
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists invoice_payment_arrangements_invoice_idx
  on public.invoice_payment_arrangements(invoice_id);
create index if not exists invoice_payment_arrangements_payment_idx
  on public.invoice_payment_arrangements(payment_id);

comment on table public.invoice_payment_arrangements is
 'Instalment terms for part of an invoice. A promise to pay, never a receipt: money actually received is always an invoice_payments row.';
comment on column public.invoice_payment_arrangements.method_id is
 'The real payment method the money comes through. Never a synthetic "Instalment" method.';

alter table public.invoice_payment_arrangements enable row level security;
do $$
begin
 if not exists (select 1 from pg_policy where polrelid='public.invoice_payment_arrangements'::regclass
                 and polname='read invoice payment arrangements') then
  create policy "read invoice payment arrangements" on public.invoice_payment_arrangements
    for select using (exists (select 1 from public.invoices i
      where i.id = invoice_payment_arrangements.invoice_id and public.user_has_store_access(i.store_id)));
 end if;
end $$;
grant select on public.invoice_payment_arrangements to authenticated;

-- ---------------------------------------------------------------------
-- Recording receipts and arrangements together, atomically.
--
-- A new name rather than another argument on record_invoice_payment: adding
-- arguments to an existing function creates an OVERLOAD, and this repository
-- has twice been broken by exactly that (243, and the live create_invoice that
-- 302 repairs).
--
-- p_payload = {
--   "receipts":     [ { payment_method_id, amount, payment_date?, reference? } ],
--   "arrangements": [ { category, method_id, months, covered_amount, notes?,
--                       receipt_index? } ]
-- }
--
-- receipt_index links an arrangement to the receipt taken under it (a provider
-- settlement, or a deposit), by position in the receipts array.
-- ---------------------------------------------------------------------
create or replace function public.record_invoice_settlement(
  p_invoice_id uuid, p_payload jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; v_receipts jsonb; v_arr jsonb; x jsonb;
 v_result jsonb; v_ids uuid[]; v_idx int; v_method uuid; v_covered numeric; v_total numeric:=0;
 v_new_arrangements int:=0; v_pay uuid;
begin
 if p_request_id is null then raise exception 'A request ID is required'; end if;
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found then raise exception 'Invoice not found'; end if;
 if not public.user_has_store_access(i.store_id) then
  raise exception 'No access to this invoice' using errcode='42501'; end if;

 v_receipts:=coalesce(p_payload->'receipts','[]'::jsonb);
 v_arr:=coalesce(p_payload->'arrangements','[]'::jsonb);
 if jsonb_array_length(v_receipts)=0 and jsonb_array_length(v_arr)=0 then
  raise exception 'Record a payment, an instalment arrangement, or both'; end if;

 -- ---- validate the arrangements before any money is recorded -------------
 for x in select * from jsonb_array_elements(v_arr) loop
  if coalesce(x->>'category','') not in ('in_house','provider_funded') then
   raise exception 'Choose whether the instalment is in-house or provider-funded'; end if;
  v_method:=nullif(x->>'method_id','')::uuid;
  if v_method is null then
   raise exception 'Choose the payment method the instalment money actually comes through'; end if;
  if not exists(select 1 from public.payment_methods m
                 where m.id=v_method and m.deleted_at is null and m.is_active) then
   raise exception 'That instalment payment method is not available'; end if;
  if exists(select 1 from public.payment_methods m
             where m.id=v_method and coalesce(m.is_wallet_credit,false)) then
   raise exception 'Wallet credit cannot be the underlying method for an instalment arrangement'; end if;
  if coalesce((x->>'months')::int,0)<=0 then
   raise exception 'Choose a positive whole number of months for the instalment'; end if;
  if coalesce((x->>'covered_amount')::numeric,0)<=0 then
   raise exception 'State the amount the instalment arrangement covers'; end if;
  v_total:=v_total+(x->>'covered_amount')::numeric;
 end loop;

 -- The arrangement cannot cover more than the invoice is worth.
 if v_total>0 and v_total>i.total_amount then
  raise exception 'The instalment arrangement covers % but the invoice is only %',v_total,i.total_amount; end if;

 -- ---- money actually received, through the existing engine ---------------
 if jsonb_array_length(v_receipts)>0 then
  v_result:=public.record_invoice_payment(p_invoice_id,v_receipts,p_request_id);
  select array_agg(id order by created_at,id) into v_ids
    from public.invoice_payments where invoice_id=p_invoice_id and receipt_request_id=p_request_id;
 end if;

 -- ---- then the terms -----------------------------------------------------
 for x in select * from jsonb_array_elements(v_arr) loop
  v_idx:=nullif(x->>'receipt_index','')::int;
  v_pay:=case when v_idx is not null and v_ids is not null and v_idx+1 between 1 and array_length(v_ids,1)
              then v_ids[v_idx+1] end;
  -- Replaying the same request must not add the terms twice.
  if exists(select 1 from public.invoice_payment_arrangements a
             where a.invoice_id=p_invoice_id and a.category=x->>'category'
               and a.method_id=(x->>'method_id')::uuid
               and a.months=(x->>'months')::int
               and a.covered_amount=(x->>'covered_amount')::numeric
               and a.payment_id is not distinct from v_pay) then
   continue; end if;
  insert into public.invoice_payment_arrangements
    (invoice_id,payment_id,category,method_id,months,covered_amount,notes,created_by)
  values(p_invoice_id,v_pay,x->>'category',(x->>'method_id')::uuid,(x->>'months')::int,
         (x->>'covered_amount')::numeric,nullif(x->>'notes',''),auth.uid());
  v_new_arrangements:=v_new_arrangements+1;
 end loop;

 if v_new_arrangements>0 then
  perform public.write_audit_ex('invoices',p_invoice_id,'instalment_arrangement_recorded',null,
    jsonb_build_object('arrangements',v_arr,'request_id',p_request_id),'invoices',null,i.store_id);
 end if;

 return coalesce(v_result,'{}'::jsonb)
   || public.invoice_instalment_summary(p_invoice_id)
   || jsonb_build_object('arrangements_recorded',v_new_arrangements);
end $$;
grant execute on function public.record_invoice_settlement(uuid,jsonb,uuid) to authenticated;

-- ---------------------------------------------------------------------
-- The four figures kept apart, so no screen has to infer one from another.
-- ---------------------------------------------------------------------
create or replace function public.invoice_instalment_summary(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; v_recv numeric; v_cov numeric; v_terms jsonb; v_legacy jsonb;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice not accessible'; end if;
 v_recv:=public.invoice_net_received(i.id);
 select coalesce(sum(covered_amount),0) into v_cov
   from public.invoice_payment_arrangements where invoice_id=i.id;
 select coalesce(jsonb_agg(jsonb_build_object(
   'arrangement_id',a.id,'category',a.category,'months',a.months,
   'covered_amount',a.covered_amount,'method',m.name,'method_id',a.method_id,
   'payment_id',a.payment_id,'received_under_it',coalesce(p.amount,0),
   'notes',a.notes,'recorded_at',a.created_at) order by a.created_at),'[]'::jsonb)
   into v_terms
   from public.invoice_payment_arrangements a
   left join public.payment_methods m on m.id=a.method_id
   left join public.invoice_payments p on p.id=a.payment_id
  where a.invoice_id=i.id;

 -- A pre-304 invoice keeps showing the terms it was actually saved with. No
 -- payment-level link is invented for it.
 v_legacy:=case when i.instalment_category is not null then jsonb_build_object(
   'category',i.instalment_category,'months',i.instalment_months,
   'method',(select name from public.payment_methods where id=i.instalment_method_id),
   'method_id',i.instalment_method_id,
   'scope','whole invoice',
   'note','Recorded before instalments could be attached to a payment, so it applies to the invoice as a whole.') end;

 return jsonb_build_object(
   'invoice_total',i.total_amount,
   'money_received',v_recv,
   'remaining_due',greatest(public.invoice_charge_total(i.id)-v_recv,0),
   'instalment_covered',v_cov,
   'arrangements',v_terms,
   'legacy_arrangement',v_legacy);
end $$;
grant execute on function public.invoice_instalment_summary(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
