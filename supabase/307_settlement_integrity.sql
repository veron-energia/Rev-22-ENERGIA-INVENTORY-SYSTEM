begin;
-- =====================================================================
-- WHAT 304 GOT WRONG, MEASURED BEFORE CHANGING ANYTHING
--
-- Every one of these was reproduced in an isolated database first:
--
-- A. RECEIPT ASSOCIATION. 304 found the receipts it had just written with
--    `order by created_at, id` and applied receipt_index to that list. Two
--    receipts written in one statement share a created_at to the microsecond,
--    so the order fell back to uuid — and receipt_index 1 linked the WRONG
--    payment. An out-of-range index was silently ignored, leaving the
--    arrangement unlinked with no complaint.
--
-- B. REQUEST IDENTITY. Duplicates were detected by comparing business fields.
--    So two legitimate identical portions (two 6-month plans of 100 each) were
--    merged into one, and the same request id replayed with DIFFERENT terms
--    (6 months/100 changed to 24 months/500) was accepted as a new portion.
--    Business-field equality is not request identity.
--
-- C. COVERAGE. Only the new payload was compared with the invoice total, so a
--    1000 invoice happily accumulated 1500 of arrangements across calls.
--
-- D. LIFECYCLE. An arrangement could be added to a CANCELLED invoice.
--
-- The fixes, in order:
--
--   * every receipt carries a caller-supplied key and is written through its
--     own derived request id, so the payment it produced is found exactly
--     rather than guessed at by timestamp;
--   * arrangements carry (request_id, portion_key) with a unique index, and a
--     content hash, so a replay returns the same result and a changed payload
--     under the same identity is refused;
--   * coverage is checked against what is actually still owed, counting
--     existing arrangements net of what has been received under them;
--   * cancelled, refunded and fully settled invoices refuse new arrangements.
--
-- Also added, for §4: an arrangement may collect MANY receipts over time,
-- through invoice_arrangement_receipts. 304's single payment_id becomes the
-- first of those links and is no longer summed on its own, so a linked deposit
-- cannot be counted twice.
--
-- Requires 304. Idempotent.
-- =====================================================================

alter table public.invoice_payment_arrangements
  add column if not exists request_id uuid,
  add column if not exists portion_key text,
  add column if not exists content_hash text,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_reason text;

comment on column public.invoice_payment_arrangements.portion_key is
 'Caller-supplied identity for this portion within its request. With request_id it makes a replay idempotent and a changed payload detectable.';

-- One portion per (request, key). Partial so 304-era rows, which have neither,
-- are left alone.
create unique index if not exists invoice_payment_arrangements_request_portion_key
  on public.invoice_payment_arrangements (request_id, portion_key)
  where request_id is not null and portion_key is not null;

-- An arrangement collects receipts over time.
create table if not exists public.invoice_arrangement_receipts (
  arrangement_id uuid not null references public.invoice_payment_arrangements(id) on delete cascade,
  payment_id uuid not null references public.invoice_payments(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (arrangement_id, payment_id)
);
alter table public.invoice_arrangement_receipts enable row level security;
do $$
begin
 if not exists (select 1 from pg_policy where polrelid='public.invoice_arrangement_receipts'::regclass
                 and polname='read arrangement receipts') then
  create policy "read arrangement receipts" on public.invoice_arrangement_receipts
    for select using (exists (select 1 from public.invoice_payment_arrangements a
      join public.invoices i on i.id=a.invoice_id
     where a.id = invoice_arrangement_receipts.arrangement_id and public.user_has_store_access(i.store_id)));
 end if;
end $$;
grant select on public.invoice_arrangement_receipts to authenticated;

-- 304 linked one deposit through arrangements.payment_id. Carry those links
-- into the new table so allocations are computed from ONE place and the
-- deposit is never counted twice.
insert into public.invoice_arrangement_receipts(arrangement_id,payment_id)
select a.id, a.payment_id from public.invoice_payment_arrangements a
 where a.payment_id is not null
on conflict do nothing;

-- ---------------------------------------------------------------------
-- The four figures §4 asks to be kept apart, per arrangement and in total.
-- Receipts are counted net of refunds, through the existing helper.
-- ---------------------------------------------------------------------
create or replace function public.invoice_arrangement_balances(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; v_rows jsonb; v_cov numeric; v_alloc numeric;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice not accessible'; end if;

 select coalesce(jsonb_agg(jsonb_build_object(
          'arrangement_id',a.id,'category',a.category,'months',a.months,
          'method',m.name,'method_id',a.method_id,
          'covered_amount',a.covered_amount,
          'received_allocated',x.allocated,
          'remaining',greatest(a.covered_amount-x.allocated,0),
          'cancelled_at',a.cancelled_at,'cancelled_reason',a.cancelled_reason,
          'receipts',x.receipts,
          'recorded_at',a.created_at) order by a.created_at),'[]'::jsonb),
        coalesce(sum(a.covered_amount) filter (where a.cancelled_at is null),0),
        coalesce(sum(x.allocated),0)
   into v_rows, v_cov, v_alloc
   from public.invoice_payment_arrangements a
   left join public.payment_methods m on m.id=a.method_id
   cross join lateral (
     select coalesce(sum(public.invoice_payment_remaining(p.id)),0) allocated,
            coalesce(jsonb_agg(jsonb_build_object(
              'payment_id',p.id,'amount',p.amount,
              'net',public.invoice_payment_remaining(p.id),
              'method',(select name from public.payment_methods where id=p.payment_method_id),
              'reference',p.payment_reference,
              'received_on',public.payment_sales_date(p.effective_at,p.created_at))
              order by p.created_at) filter (where p.id is not null),'[]'::jsonb) receipts
       from public.invoice_arrangement_receipts r
       join public.invoice_payments p on p.id=r.payment_id
      where r.arrangement_id=a.id and p.entry_kind<>'correction_reversal') x
  where a.invoice_id=i.id;

 return jsonb_build_object(
   'invoice_total',i.total_amount,
   'money_received',public.invoice_net_received(i.id),
   'remaining_due',greatest(public.invoice_charge_total(i.id)-public.invoice_net_received(i.id),0),
   'instalment_covered',v_cov,
   'instalment_received',v_alloc,
   'instalment_remaining',greatest(v_cov-v_alloc,0),
   'arrangements',v_rows);
end $$;
grant execute on function public.invoice_arrangement_balances(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Settlement, rewritten around durable identity.
--
--   receipts:     [ { key, payment_method_id, amount, payment_date?, reference? } ]
--   arrangements: [ { key, category, method_id, months, covered_amount,
--                     receipt_key?, arrangement_id?, notes? } ]
--
-- `arrangement_id` on a receipt-bearing portion means "this money belongs to an
-- arrangement that already exists" — the way a later instalment is recorded
-- without inventing a second set of terms.
-- ---------------------------------------------------------------------
create or replace function public.record_invoice_settlement(
  p_invoice_id uuid, p_payload jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; v_receipts jsonb; v_arr jsonb; x jsonb;
 v_key text; v_derived uuid; v_pay uuid; v_ids jsonb:='{}'::jsonb;
 v_method uuid; v_hash text; v_existing public.invoice_payment_arrangements%rowtype;
 v_new int:=0; v_linked int:=0; v_outstanding numeric; v_proposed numeric:=0; v_open numeric;
 v_target uuid; v_amount numeric;
begin
 if p_request_id is null then raise exception 'A request ID is required'; end if;
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found then raise exception 'Invoice not found'; end if;
 if not public.user_has_store_access(i.store_id) then
  raise exception 'No access to this invoice' using errcode='42501'; end if;
 if not exists(select 1 from public.profiles
                where id=auth.uid() and coalesce(is_active,true) and deleted_at is null) then
  raise exception 'Only an active user can record a settlement' using errcode='42501'; end if;

 v_receipts:=coalesce(p_payload->'receipts','[]'::jsonb);
 v_arr:=coalesce(p_payload->'arrangements','[]'::jsonb);
 if jsonb_array_length(v_receipts)=0 and jsonb_array_length(v_arr)=0 then
  raise exception 'Record a payment, an instalment arrangement, or both'; end if;

 -- D. Lifecycle. A cancelled or fully refunded invoice takes no new terms.
 if jsonb_array_length(v_arr)>0 then
  if i.status in ('cancelled','refunded') then
   raise exception 'This invoice is %; it cannot take a new instalment arrangement',i.status; end if;
  if public.invoice_charge_total(i.id)<=public.invoice_net_received(i.id) then
   raise exception 'This invoice has nothing left to owe, so there is nothing for an instalment to cover'; end if;
 end if;

 -- ---- A. every receipt through its OWN derived request id ----------------
 for x in select * from jsonb_array_elements(v_receipts) loop
  v_key:=nullif(x->>'key','');
  if v_key is null then raise exception 'Every receipt needs a key so its arrangement can point at it'; end if;
  if v_ids ? v_key then raise exception 'Receipt keys must be unique within a request (% appears twice)',v_key; end if;
  -- Deterministic, so a replay finds the same payment instead of writing another.
  v_derived:=md5(p_request_id::text||':receipt:'||v_key)::uuid;
  perform public.record_invoice_payment(p_invoice_id,
    jsonb_build_array(x - 'key'), v_derived);
  select id into v_pay from public.invoice_payments
   where invoice_id=p_invoice_id and receipt_request_id=v_derived
   order by created_at, id limit 1;
  if v_pay is null then raise exception 'The receipt "%" could not be read back',v_key; end if;
  v_ids:=v_ids||jsonb_build_object(v_key,v_pay);
 end loop;

 -- ---- validate every NEW portion's fields before anything else, so a bad
 -- method or duration is reported as such rather than as a coverage problem.
 for x in select * from jsonb_array_elements(v_arr) loop
  if nullif(x->>'arrangement_id','') is not null then continue; end if;
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
  if nullif(x->>'key','') is null then
   raise exception 'Every instalment portion needs a key'; end if;
 end loop;

 -- ---- C. coverage against what is actually still owed --------------------
 -- Only NEW portions can increase coverage. A receipt being allocated to an
 -- arrangement that already exists reduces what is owed and what that
 -- arrangement still has to collect by the same amount, so including it here
 -- would count it on both sides and refuse a perfectly ordinary instalment
 -- payment.
 -- A portion already written under this request id is a replay, not new
 -- coverage; counting it again would refuse an ordinary retry.
 -- Net of any receipt taken under the portion in this same request: money the
 -- provider has already settled is not coverage still to come, and counting it
 -- both as a receipt and as coverage would refuse a fully funded arrangement.
 select coalesce(sum(greatest((q->>'covered_amount')::numeric
          - coalesce((select (rr->>'amount')::numeric
                        from jsonb_array_elements(v_receipts) rr
                       where rr->>'key' = q->>'receipt_key'),0),0)),0)
   into v_proposed
   from jsonb_array_elements(v_arr) q
  where nullif(q->>'arrangement_id','') is null
    and not exists(select 1 from public.invoice_payment_arrangements a
                    where a.request_id=p_request_id and a.portion_key=q->>'key');
 if v_proposed>0 then
  v_outstanding:=greatest(public.invoice_charge_total(i.id)-public.invoice_net_received(i.id),0);
  select coalesce(sum(greatest(a.covered_amount-coalesce((
           select sum(public.invoice_payment_remaining(p.id))
             from public.invoice_arrangement_receipts r join public.invoice_payments p on p.id=r.payment_id
            where r.arrangement_id=a.id and p.entry_kind<>'correction_reversal'),0),0)),0)
    into v_open
    from public.invoice_payment_arrangements a
   where a.invoice_id=i.id and a.cancelled_at is null;
  if round(v_open+v_proposed,2)>round(v_outstanding,2) then
   raise exception 'Instalments would cover %, but only % is still owed on this invoice',
     round(v_open+v_proposed,2),round(v_outstanding,2);
  end if;
 end if;

 -- ---- B. durable identity per portion ------------------------------------
 for x in select * from jsonb_array_elements(v_arr) loop
  v_target:=nullif(x->>'arrangement_id','')::uuid;

  -- A later receipt against an arrangement that already exists.
  if v_target is not null then
   select * into v_existing from public.invoice_payment_arrangements
    where id=v_target and invoice_id=i.id for update;
   if not found then raise exception 'That instalment arrangement does not belong to this invoice'; end if;
   if v_existing.cancelled_at is not null then
    raise exception 'That instalment arrangement has been cancelled'; end if;
   v_key:=nullif(x->>'receipt_key','');
   if v_key is null then raise exception 'A later instalment payment must say which receipt it is'; end if;
   if not (v_ids ? v_key) then
    raise exception 'Receipt "%" was not part of this request',v_key; end if;
   insert into public.invoice_arrangement_receipts(arrangement_id,payment_id)
    values(v_existing.id,(v_ids->>v_key)::uuid) on conflict do nothing;
   v_linked:=v_linked+1;
   continue;
  end if;

  -- A new portion. Its fields were validated in the pass above.
  v_method:=(x->>'method_id')::uuid;
  v_key:=x->>'key';
  v_hash:=md5(jsonb_build_object('c',x->>'category','m',x->>'method_id',
    'n',x->>'months','a',x->>'covered_amount','r',x->>'receipt_key')::text);

  select * into v_existing from public.invoice_payment_arrangements
   where request_id=p_request_id and portion_key=v_key;
  if found then
   -- Replaying the same request: same terms, same answer, no second write.
   if v_existing.content_hash is distinct from v_hash then
    raise exception 'Request % was already used for portion "%" with different details',p_request_id,v_key; end if;
   continue;
  end if;

  -- A receipt reference must resolve, or the caller hears about it.
  v_pay:=null;
  if nullif(x->>'receipt_key','') is not null then
   if not (v_ids ? (x->>'receipt_key')) then
    raise exception 'Instalment portion "%" refers to receipt "%", which is not in this request',
      v_key,x->>'receipt_key'; end if;
   v_pay:=(v_ids->>(x->>'receipt_key'))::uuid;
  end if;

  insert into public.invoice_payment_arrangements
    (invoice_id,payment_id,category,method_id,months,covered_amount,notes,created_by,
     request_id,portion_key,content_hash)
  values(p_invoice_id,v_pay,x->>'category',v_method,(x->>'months')::int,
         (x->>'covered_amount')::numeric,nullif(x->>'notes',''),auth.uid(),
         p_request_id,v_key,v_hash)
  returning id into v_target;
  if v_pay is not null then
   insert into public.invoice_arrangement_receipts(arrangement_id,payment_id)
    values(v_target,v_pay) on conflict do nothing;
  end if;
  v_new:=v_new+1;
 end loop;

 if v_new>0 or v_linked>0 then
  perform public.write_audit_ex('invoices',p_invoice_id,'instalment_settlement_recorded',null,
    jsonb_build_object('arrangements',v_arr,'receipts',jsonb_array_length(v_receipts),
      'request_id',p_request_id),'invoices',null,i.store_id);
 end if;

 return public.invoice_arrangement_balances(p_invoice_id)
   || jsonb_build_object('arrangements_recorded',v_new,'receipts_linked',v_linked,
                         'receipts_recorded',jsonb_array_length(v_receipts));
end $$;
grant execute on function public.record_invoice_settlement(uuid,jsonb,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
