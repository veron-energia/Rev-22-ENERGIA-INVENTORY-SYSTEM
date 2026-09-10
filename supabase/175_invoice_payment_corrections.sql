begin;
alter table public.invoice_payments add column if not exists effective_at timestamptz;
alter table public.invoice_payments add column if not exists receipt_request_id uuid;
alter table public.invoice_payments add column if not exists receipt_request_hash text;

create or replace function public.invoice_payment_remaining(p_payment_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
 with recursive chain as (
  select p.id,p.corrects_payment_id,p.amount from public.invoice_payments p where p.id=p_payment_id
  union all select p.id,p.corrects_payment_id,p.amount from public.invoice_payments p join chain c on c.corrects_payment_id=p.id
 ) select greatest(0,(select amount from public.invoice_payments where id=p_payment_id)-
   coalesce((select sum(r.amount) from public.invoice_refunds r where r.payment_id in (select id from chain)),0))
$$;
create or replace function public.invoice_stock_to_deduct(p_invoice_id uuid)
returns table(kind text,item_id uuid,quantity integer) language sql stable security definer set search_path=public as $$
 select r.kind,r.item_id,greatest(0,r.quantity-case when r.kind='product' then coalesce((
  select sum(case when m.movement_type::text='store_sale' then m.quantity else -m.quantity end)
  from public.stock_movements m where m.invoice_id=p_invoice_id and m.product_id=r.item_id
   and m.movement_type::text in ('store_sale','invoice_cancel_return','invoice_refund_return','refund_return')),0) else 0 end)::int
 from public.invoice_required_stock(p_invoice_id) r
$$;
CREATE OR REPLACE FUNCTION public.invoice_record_payments_internal(p_invoice_id uuid, p_payments jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_req record; v_available integer; v_li record;
  v_is_member boolean := true; v_will_be_full boolean;
  v_old_total numeric; v_changes jsonb;
begin
  -- 1. Lock invoice.
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  -- 2. Role/store access.
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
  -- 3. Editable/payable + customer present.
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  -- Phase 12: a confirmed FOC invoice is closed; a fully-FOC invoice has no balance.
  if v_inv.status = 'completed_foc' then
    raise exception 'This invoice was completed as FOC and cannot take a payment'; end if;
  if coalesce(v_inv.is_full_foc,false) and coalesce(v_inv.total_amount,0) <= 0.001 then
    raise exception 'This invoice is fully FOC — use Confirm FOC Invoice instead of taking a payment'; end if;
  if v_inv.customer_id is null then raise exception 'Invoice has no customer'; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then raise exception 'At least one payment is required'; end if;

  -- Phase 19: Membership removed; every customer receives the normal price.

  -- Invoice prices are snapshots. A payment never silently adopts today's catalogue.
  -- 13. Validate payment amounts.
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;
  v_already_paid := public.invoice_net_received(p_invoice_id);
  v_new_paid := v_already_paid + v_total_paying;
  if v_new_paid > v_inv.total_amount + 0.001 then raise exception 'Payment exceeds remaining balance'; end if;
  v_will_be_full := v_new_paid >= v_inv.total_amount - 0.001;

  -- 12. Stock check (only matters when this payment completes the invoice).
  if v_will_be_full then
    for v_req in select * from public.invoice_stock_to_deduct(p_invoice_id)
    loop
      if v_req.kind = 'product' then
        select current_qty into v_available from public.store_inventory
          where store_id = v_inv.store_id and product_id = v_req.item_id for update;
        if coalesce(v_available,0) < v_req.quantity then
          raise exception 'Insufficient store stock for % (have %, need % incl. bundles). Payment blocked.',
            (select name from public.products where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
        end if;
      else
        select current_qty into v_available from public.voucher_store_stock
          where store_id = v_inv.store_id and voucher_id = v_req.item_id for update;
        if coalesce(v_available,0) < v_req.quantity then
          raise exception 'Insufficient voucher stock for % (have %, need % incl. bundles). Payment blocked.',
            (select name from public.vouchers where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
        end if;
      end if;
    end loop;
  end if;

  -- 14. Record payments.
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (id, invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (coalesce(nullif(v_pay->>'payment_id','')::uuid,gen_random_uuid()), p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  if v_will_be_full then
    -- 15. Deduct stock.
    for v_req in select * from public.invoice_stock_to_deduct(p_invoice_id)
    loop
      if v_req.kind = 'product' then
        update public.store_inventory set current_qty = current_qty - v_req.quantity, updated_at = now()
          where store_id = v_inv.store_id and product_id = v_req.item_id;
        insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
        values (v_req.item_id, 'store_sale', v_inv.store_id, p_invoice_id, v_req.quantity, public.invoice_stock_note(p_invoice_id, v_req.item_id, 'Sale'), auth.uid());
      else
        update public.voucher_store_stock set current_qty = current_qty - v_req.quantity, updated_at = now()
          where store_id = v_inv.store_id and voucher_id = v_req.item_id;
        perform public.write_audit('vouchers', v_req.item_id, 'voucher_sold', null,
          jsonb_build_object('invoice_no', v_inv.invoice_no, 'qty', v_req.quantity));
      end if;
    end loop;

    -- 16. Mark paid + lock.
    update public.invoices set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    -- Voucher redemptions (preserved).
    if v_inv.discount_voucher_id is not null then
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_inv.discount_voucher_id, p_invoice_id, v_inv.customer_id,
              v_inv.discount_total - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0),
              auth.uid());
      perform public.write_audit('vouchers', v_inv.discount_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no));
    end if;
    for v_li in select line_voucher_id, line_discount from public.invoice_items
      where invoice_id = p_invoice_id and line_voucher_id is not null
    loop
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_li.line_voucher_id, p_invoice_id, v_inv.customer_id, v_li.line_discount, auth.uid());
      perform public.write_audit('vouchers', v_li.line_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no, 'line_discount', v_li.line_discount));
    end loop;


    -- 19. Commissions.
    perform public.earn_invoice_commission(p_invoice_id);
    perform public.earn_staff_commission(p_invoice_id);
  -- Special products and rentals become documents awaiting a warehouse.
  perform public.create_special_docs_for_invoice(p_invoice_id);

    -- 20. Audit.
    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no,
                         'foc_total', coalesce(v_inv.foc_total,0),
                         'mixed_foc', coalesce(v_inv.has_foc,false)));
    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid);
  else
    -- Partial payment: money recorded, NOTHING activates, no stock moves.
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid' where id = p_invoice_id;
    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));
    return jsonb_build_object('success', true, 'status', 'partially_paid', 'paid_amount', v_new_paid,
                              'remaining', v_inv.total_amount - v_new_paid);
  end if;
end; $function$;

revoke all on function public.invoice_record_payments_internal(uuid,jsonb),public.invoice_payment_remaining(uuid),public.invoice_stock_to_deduct(uuid) from public,anon,authenticated;
create or replace function public.record_invoice_payment(p_invoice_id uuid,p_payments jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; x jsonb; m public.payment_methods%rowtype; v_id uuid; v_ids uuid[];
 v_all jsonb:='[]'; v_res jsonb; v_hash text:=md5(p_payments::text);
begin
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if p_request_id is null then raise exception 'Payment request ID is required'; end if;
 if exists(select 1 from public.invoice_payments where invoice_id=i.id and receipt_request_id=p_request_id) then
  if not exists(select 1 from public.invoice_payments where invoice_id=i.id and receipt_request_id=p_request_id and receipt_request_hash=v_hash) then
   raise exception 'Payment request ID was already used with different amounts'; end if;
  return jsonb_build_object('success',true,'replayed',true)||public.invoice_financial_position(i.id);
 end if;
 if i.status not in ('unpaid','draft','partially_paid') then raise exception 'Invoice is not open for payment'; end if;
 if jsonb_typeof(p_payments) is distinct from 'array' or jsonb_array_length(p_payments)=0 then raise exception 'Record at least one payment'; end if;
 for x in select * from jsonb_array_elements(p_payments) loop
  select * into m from public.payment_methods where id=(x->>'payment_method_id')::uuid and is_active and deleted_at is null;
  if not found then raise exception 'Choose an active payment method'; end if;
  v_id:=gen_random_uuid();
  if m.is_wallet_credit then
   select array_agg(id) into v_ids from public.invoice_line_credit_allocations where invoice_id=i.id;
   perform public.allocate_invoice_wallet_credit(i.id,(x->>'amount')::numeric,m.wallet_category);
   update public.invoice_line_credit_allocations set payment_id=v_id where invoice_id=i.id and not(id=any(coalesce(v_ids,'{}'::uuid[])));
  end if;
  v_all:=v_all||jsonb_build_array(x||jsonb_build_object('payment_id',v_id));
 end loop;
 v_res:=public.invoice_record_payments_internal(i.id,v_all);
 if v_res->>'success' is distinct from 'true' then raise exception 'Payment could not be recorded: %',v_res; end if;
 update public.invoice_payments set receipt_request_id=p_request_id,receipt_request_hash=v_hash
   where id in(select (j.value->>'payment_id')::uuid from jsonb_array_elements(v_all) j(value));
 return v_res;
end $$;
create or replace function public.pay_invoice_with_wallet(p_invoice_id uuid,p_payments jsonb)
returns jsonb language sql security definer set search_path=public as $$
 select public.record_invoice_payment(p_invoice_id,p_payments,gen_random_uuid())
$$;
create or replace function public.pay_invoice(p_invoice_id uuid,p_payments jsonb)
returns jsonb language sql security definer set search_path=public as $$
 select public.record_invoice_payment(p_invoice_id,p_payments,gen_random_uuid())
$$;

create or replace function public.correct_invoice_payment(p_payment_id uuid,p_amount numeric,p_date date,
 p_method_id uuid,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.invoice_payments%rowtype; i public.invoices%rowtype; m public.payment_methods%rowtype;
 old_m public.payment_methods%rowtype; a record; l public.customer_credit_lots%rowtype;
 v_refunded numeric; v_reverse uuid:=gen_random_uuid(); v_replace uuid:=gen_random_uuid(); v_ids uuid[]; n numeric;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct a payment'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'A payment correction reason and request ID are required'; end if;
 select * into p from public.invoice_payments where id=p_payment_id;
 if not found then raise exception 'Payment not found'; end if;
 select * into i from public.invoices where id=p.invoice_id for update;
 if not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if exists(select 1 from public.invoice_payments where invoice_id=i.id and correction_request_id=p_request_id) then
  if not exists(select 1 from public.invoice_payments q where q.invoice_id=i.id and q.correction_request_id=p_request_id
    and q.entry_kind='correction_replacement' and q.corrects_payment_id=p.id and q.amount=round(p_amount,2)
    and q.payment_method_id=p_method_id and (q.effective_at at time zone 'Asia/Singapore')::date=p_date and q.correction_reason=p_reason) then
    raise exception 'This correction request ID was already used for different payment details'; end if;
  return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replayed',true); end if;
 if p.entry_kind='correction_reversal' or exists(select 1 from public.invoice_payments where corrects_payment_id=p.id and entry_kind='correction_reversal') then raise exception 'Select the current replacement payment'; end if;
 if p_amount is null or p_amount<=0 or p_date is null then raise exception 'A positive corrected amount and actual payment date are required'; end if;
 select * into m from public.payment_methods where id=p_method_id and is_active and deleted_at is null;
 if not found then raise exception 'Choose an active payment method'; end if;
 select * into old_m from public.payment_methods where id=p.payment_method_id;
 v_refunded:=p.amount-public.invoice_payment_remaining(p.id);
 if p_amount<v_refunded then raise exception 'Corrected payment cannot be less than refunds already issued'; end if;
 if v_refunded>0 and (m.is_wallet_credit,m.wallet_category) is distinct from (old_m.is_wallet_credit,old_m.wallet_category) then
  raise exception 'A refunded wallet payment requires source review before changing its funding category'; end if;
 if old_m.is_wallet_credit then
  if (select coalesce(sum(amount-reversed_amount),0) from public.invoice_line_credit_allocations where payment_id=p.id)<>p.amount-v_refunded then
   raise exception 'Legacy wallet allocation is ambiguous; review exact source lots first'; end if;
  for a in select * from public.invoice_line_credit_allocations where payment_id=p.id and amount>reversed_amount order by id for update loop
   select * into l from public.customer_credit_lots where id=a.lot_id for update;
   update public.customer_credit_lots set remaining_amount=remaining_amount+a.amount-a.reversed_amount,status='active',updated_at=now() where id=l.id;
   insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,reverses_entry_id,created_by,approved_by)
    values(l.wallet_id,l.customer_id,'reverse',l.category,a.amount-a.reversed_amount,l.id,'payment_correction',p_request_id,l.store_id,p_reason,a.ledger_entry_id,auth.uid(),auth.uid());
   update public.invoice_line_credit_allocations set reversed_amount=amount where id=a.id;
  end loop;
 end if;
 -- These are bookkeeping ledger entries. Neither creates an invoice_refunds row.
 insert into public.invoice_payments(id,invoice_id,payment_method_id,amount,entry_kind,corrects_payment_id,correction_reason,correction_request_id,effective_at,received_by)
  values(v_reverse,i.id,p.payment_method_id,p.amount,'correction_reversal',p.id,p_reason,p_request_id,coalesce(p.effective_at,p.created_at),auth.uid());
 insert into public.invoice_payments(id,invoice_id,payment_method_id,amount,entry_kind,corrects_payment_id,correction_reason,correction_request_id,effective_at,received_by)
  values(v_replace,i.id,m.id,round(p_amount,2),'correction_replacement',p.id,p_reason,p_request_id,p_date::timestamp at time zone 'Asia/Singapore',auth.uid());
 if m.is_wallet_credit and p_amount>v_refunded then
  select array_agg(id) into v_ids from public.invoice_line_credit_allocations where invoice_id=i.id;
  -- Only the allocator needs a payable state. This header update does not settle
  -- or reissue benefits; the final state below restores terminal states.
  update public.invoices set status='partially_paid' where id=i.id;
  perform public.allocate_invoice_wallet_credit(i.id,p_amount-v_refunded,m.wallet_category);
  update public.invoice_line_credit_allocations set payment_id=v_replace where invoice_id=i.id and not(id=any(coalesce(v_ids,'{}'::uuid[])));
 end if;
 n:=public.invoice_net_received(i.id);
 update public.invoices set paid_amount=n,status=case when i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then i.status
  when n>=total_amount then 'paid'::invoice_status when n>0 then 'partially_paid'::invoice_status else 'unpaid'::invoice_status end where id=i.id;
 perform public.reconcile_invoice_commissions(i.id,'Payment correction: '||p_reason);
 perform public.write_audit_ex('invoice_payments',p.id,'payment_corrected',to_jsonb(p),jsonb_build_object('reversal',v_reverse,'replacement',v_replace,'amount',p_amount,'effective_date',p_date,'method_id',m.id),'payments',p_reason,i.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replacement_id',v_replace);
end $$;
-- The allocator is no longer a standalone public way to spend arbitrary credit.
revoke all on function public.allocate_invoice_wallet_credit(uuid,numeric,text) from public,anon,authenticated;
revoke all on function public.record_invoice_payment(uuid,jsonb,uuid),public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid),public.pay_invoice(uuid,jsonb),public.pay_invoice_with_wallet(uuid,jsonb) from public,anon;
grant execute on function public.record_invoice_payment(uuid,jsonb,uuid),public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid),public.pay_invoice(uuid,jsonb),public.pay_invoice_with_wallet(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
