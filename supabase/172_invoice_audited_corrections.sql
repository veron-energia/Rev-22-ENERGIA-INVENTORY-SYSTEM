begin;
-- Keep the low-level builder private. It is always called inside an audited,
-- invoice-locked transaction by the public correction/ordinary-edit wrappers.
alter function public.update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) rename to update_invoice_internal;
revoke all on function public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) from public,anon,authenticated;

create or replace function public.invoice_all_lines_match(p_invoice_id uuid,p_items jsonb)
returns boolean language sql stable security definer set search_path=public as $$
 select jsonb_typeof(p_items)='array'
 and jsonb_array_length(p_items)=(select count(*) from public.invoice_items where invoice_id=p_invoice_id)
 and not exists(select 1 from jsonb_array_elements(p_items) x where not public.invoice_line_matches(nullif(x->>'invoice_item_id','')::uuid,x))
 and (select count(distinct x->>'invoice_item_id') from jsonb_array_elements(p_items) x)=jsonb_array_length(p_items)
$$;

-- Commission rows paid in a payout are immutable. Recalculating a correction
-- leaves them intact and offsets them with separately identifiable future rows.
alter table public.commissions add column if not exists adjusts_commission_id uuid references public.commissions(id);
alter table public.staff_commissions add column if not exists adjusts_commission_id uuid references public.staff_commissions(id);
create or replace function public.reconcile_invoice_commissions(p_invoice_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; c record; v_share numeric; v_before uuid[]; v_staff_before uuid[];
begin
 select * into i from public.invoices where id=p_invoice_id for update;
 select array_agg(id) into v_before from public.commissions where invoice_id=i.id;
 select array_agg(id) into v_staff_before from public.staff_commissions where invoice_id=i.id;
 update public.commissions set status='reversed',reversed_at=now(),reversal_reason=p_reason
 where invoice_id=i.id and payout_id is null and status in ('earned','blocked');
 update public.staff_commissions set status='reversed',reversed_at=now(),reversal_reason=p_reason
 where invoice_id=i.id and payout_id is null and status in ('earned','blocked');
 if i.status not in ('cancelled','refunded') then
   perform public.earn_invoice_commission(i.id);
   for c in select id from public.credit_package_sales where invoice_id=i.id loop
     perform public.earn_credit_package_commission(c.id);
   end loop;
   for c in select id from public.premium_bundle_sales where invoice_id=i.id loop
     perform public.earn_premium_bundle_commission(c.id);
   end loop;
   perform public.earn_staff_commission(i.id);
   v_share:=case when i.total_amount>0 then least(1,greatest(0,public.invoice_net_received(i.id))/i.total_amount) else 0 end;
   update public.commissions set commission_amount=round(commission_amount*v_share,2),line_amount=round(line_amount*v_share,2)
    where invoice_id=i.id and not(id=any(coalesce(v_before,'{}'::uuid[])));
 end if;
 for c in select * from public.commissions where invoice_id=i.id and (payout_id is not null or status='paid') loop
   insert into public.commissions select (jsonb_populate_record(null::public.commissions,to_jsonb(c)||jsonb_build_object(
    'id',gen_random_uuid(),'payout_id',null,'status','earned','commission_amount',-c.commission_amount,
    'line_amount',-c.line_amount,'adjusts_commission_id',c.id,'created_at',now(),
    'reversed_at',null,'reversal_reason','Future payout adjustment: '||p_reason))).*;
 end loop;
 for c in select * from public.staff_commissions where invoice_id=i.id and (payout_id is not null or status='paid') loop
   insert into public.staff_commissions select (jsonb_populate_record(null::public.staff_commissions,to_jsonb(c)||jsonb_build_object(
    'id',gen_random_uuid(),'payout_id',null,'status','earned','commission_amount',-c.commission_amount,
    'invoice_total',-c.invoice_total,'adjusts_commission_id',c.id,'created_at',now(),
    'reversed_at',null,'reversal_reason','Future payout adjustment: '||p_reason))).*;
 end loop;
end $$;

create or replace function public.invoice_commission_basis(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
 select round(least(greatest(i.total_amount,0),greatest(public.invoice_net_received(i.id),0)) *
   case when public.invoice_net_received(i.id)>0 then least(1,greatest(0,
     (coalesce((select sum(case when p.entry_kind='correction_reversal' then -p.amount else p.amount end)
       from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id
       where p.invoice_id=i.id and not coalesce(m.is_wallet_credit,false)),0)
      -coalesce((select sum(r.amount-r.credit_returned) from public.invoice_refunds r where r.invoice_id=i.id),0))
     /public.invoice_net_received(i.id))) else 0 end,2)
 from public.invoices i where i.id=p_invoice_id
$$;
revoke all on function public.invoice_commission_basis(uuid) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.earn_staff_commission(p_invoice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; v_rate numeric; v_n integer;
  v_share numeric; v_paid_date date; v_amt numeric; v_staff record;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  -- Credit spend is not new money; it was counted when the credit was bought.
  v_inv.total_amount := public.invoice_commission_basis(p_invoice_id);
  if not found then return; end if;

  -- Divided among the store's active staff, regardless of who served.
  v_n := public.store_commission_staff_count(v_inv.store_id);
  if v_n = 0 then
    -- Nobody to pay. Recorded rather than silently skipped, so an unassigned
    -- store is visible instead of quietly producing no commission.
    perform public.write_audit('staff_commissions', p_invoice_id,
      'staff_commission_skipped_no_staff', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'store_id', v_inv.store_id));
    return;
  end if;

  select staff_commission_rate into v_rate from public.app_settings where id = true;
  v_rate := coalesce(v_rate, 0);
  if v_rate <= 0 then return; end if;

  v_share := round(1.0 / v_n, 6);
  v_paid_date := coalesce(v_inv.paid_at, now())::date;

  for v_staff in select s.staff_id from public.store_commission_staff(v_inv.store_id) s
  loop
    v_amt := round(v_inv.total_amount * v_share * v_rate / 100.0, 2);
    if v_amt <= 0 then continue; end if;
    insert into public.staff_commissions
      (invoice_id, staff_id, store_id, invoice_total, share_ratio, rate,
       commission_amount, status, invoice_paid_date)
    values (p_invoice_id, v_staff.staff_id, v_inv.store_id, v_inv.total_amount,
       v_share, v_rate, v_amt, 'earned', v_paid_date);
  end loop;

  perform public.write_audit('staff_commissions', p_invoice_id, 'staff_commission_earned', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'staff_count', v_n,
      'rate', v_rate, 'basis', 'store active staff'));
end $function$;
-- Use movements at their original locations. Catalogue contents and the current
-- invoice store are not evidence of a historical stock deduction.
create or replace function public.restore_invoice_stock(p_invoice_id uuid,p_note text default null)
returns integer language plpgsql security definer set search_path=public as $$
declare r record; n integer:=0;
begin
 perform 1 from public.invoices where id=p_invoice_id for update;
 for r in select product_id,store_id,sum(qty)::int qty from (
   select product_id,from_store_id store_id,quantity qty from public.stock_movements
    where invoice_id=p_invoice_id and movement_type::text='store_sale'
   union all select product_id,to_store_id,-quantity from public.stock_movements
    where invoice_id=p_invoice_id and movement_type::text in ('invoice_cancel_return','invoice_refund_return','refund_return')
 ) x where store_id is not null and product_id is not null group by product_id,store_id having sum(qty)>0
 loop
  insert into public.store_inventory(store_id,product_id,current_qty) values(r.store_id,r.product_id,r.qty)
   on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+excluded.current_qty,updated_at=now();
  insert into public.stock_movements(product_id,movement_type,to_store_id,invoice_id,quantity,notes,created_by)
   values(r.product_id,'invoice_cancel_return',r.store_id,p_invoice_id,r.qty,coalesce(p_note,'Reversed outstanding invoice deduction'),auth.uid());
  n:=n+1;
 end loop;
 return n;
end $$;

create or replace function public.correct_invoice(
 p_invoice_id uuid,p_items jsonb,p_header jsonb,p_reason text,p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; n public.invoices%rowtype; same_lines boolean; same_header boolean;
 v_snapshot jsonb; v_rev int; v_paid numeric; v_status public.invoice_status; v_staff jsonb;
 v_operational boolean; v_stock_change boolean; v_had_stock boolean; v_after jsonb;
begin
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found or i.deleted_at is not null then raise exception 'Invoice not found'; end if;
 if not public.user_has_store_access(i.store_id) then raise exception 'No access to this invoice'; end if;
 if i.status not in ('draft','unpaid') or exists(select 1 from public.invoice_payments where invoice_id=i.id) then
   if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct this invoice'; end if;
   if nullif(trim(p_reason),'') is null then raise exception 'A correction reason is required'; end if;
 end if;
 if i.status in ('draft','unpaid') and not exists(select 1 from public.invoice_payments where invoice_id=i.id) and not public.can_edit_invoice(i.id) then raise exception 'You cannot edit this invoice'; end if;
 if p_request_id is not null and exists(select 1 from public.invoice_revisions where invoice_id=i.id and request_id=p_request_id) then
   return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replayed',true); end if;
 if p_header ? 'expected_edit_count' and (p_header->>'expected_edit_count')::int<>coalesce(i.edit_count,0) then
   raise exception 'This invoice was changed by another user. Reload it before saving.'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0 then raise exception 'Keep at least one line'; end if;
 same_lines:=public.invoice_all_lines_match(i.id,p_items);
 n:=i;
 if p_header ? 'customer_id' then n.customer_id:=nullif(p_header->>'customer_id','')::uuid; end if;
 if p_header ? 'store_id' then n.store_id:=nullif(p_header->>'store_id','')::uuid; end if;
 if p_header ? 'affiliate_id' then n.affiliate_id:=nullif(p_header->>'affiliate_id','')::uuid; n.affiliate_selection_explicit:=true; end if;
 if p_header ? 'notes' then n.notes:=p_header->>'notes'; end if;
 if p_header ? 'manual_discount' then n.manual_discount:=(p_header->>'manual_discount')::numeric; end if;
 if p_header ? 'discount_voucher_id' then n.discount_voucher_id:=nullif(p_header->>'discount_voucher_id','')::uuid; end if;
 if p_header ? 'business_date' then n.business_date:=(p_header->>'business_date')::date; end if;
 if p_header ? 'instalment_category' then
  n.instalment_category:=nullif(p_header->>'instalment_category','');
  n.instalment_method_id:=nullif(p_header->>'instalment_method_id','')::uuid;
  n.instalment_months:=nullif(p_header->>'instalment_months','')::int;
 end if;
 if p_header ? 'save_earth_applied' then
  n.save_earth_applied:=(p_header->>'save_earth_applied')::boolean;
  n.save_earth_label:=p_header->>'save_earth_label'; n.save_earth_amount:=(p_header->>'save_earth_amount')::numeric;
 end if;
 if p_header ? 'created_by' and nullif(p_header->>'created_by','')::uuid is distinct from i.created_by then
   if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct invoice attribution'; end if;
   n.created_by:=nullif(p_header->>'created_by','')::uuid;
 end if;
 if not exists(select 1 from public.customers where id=n.customer_id and deleted_at is null) then raise exception 'Choose a non-deleted customer'; end if;
 if not public.user_has_store_access(n.store_id) then raise exception 'No access to the selected store'; end if;
 if n.affiliate_id is not null and not exists(select 1 from public.customer_affiliates where id=n.affiliate_id and deleted_at is null) then raise exception 'Affiliate not found'; end if;
 if n.manual_discount<0 or n.save_earth_amount<0 then raise exception 'Discount cannot be negative'; end if;
 select coalesce(jsonb_agg(staff_id order by staff_id),'[]') into v_staff from public.invoice_service_staff where invoice_id=i.id;
 same_header:=to_jsonb(n)=to_jsonb(i) and (not(p_header ? 'service_staff') or
   v_staff=(select coalesce(jsonb_agg(x order by x),'[]') from jsonb_array_elements(p_header->'service_staff') x));
 if same_lines and same_header and coalesce(p_header->'payment_methods','[]')='[]'::jsonb then
   return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'unchanged',true); end if;
 v_stock_change:=not public.invoice_operational_lines_match(i.id,p_items) or n.store_id<>i.store_id;
 v_operational:=v_stock_change or n.customer_id<>i.customer_id;
 if v_operational and i.stock_snapshot_version is null and exists(select 1 from public.invoice_items where invoice_id=i.id and line_kind in ('promotion','voucher')) then
   raise exception 'Historical component snapshots need review before changing stock or selections; metadata can still be corrected'; end if;
 if v_operational and exists(select 1 from public.purchased_therapy_entitlements where invoice_id=i.id and status in ('active','expired')) then
   raise exception 'Resolve the consumed therapy entitlement before changing its customer, store or invoice lines'; end if;
 if v_operational and exists(select 1 from public.rentals where invoice_id=i.id and status::text in ('active','paid')) then
   raise exception 'Return or resolve the active rental before changing its invoice allocation'; end if;
 -- Issued identifiers survive metadata-only corrections. A changed entitlement
 -- must be reconciled before its defining line/customer can change.
 if (not same_lines or n.customer_id<>i.customer_id) and exists(select 1 from public.invoice_items it where it.invoice_id=i.id
    and it.credit_issued_at is not null and (n.customer_id<>i.customer_id or not exists(
      select 1 from jsonb_array_elements(p_items) x where public.invoice_line_matches(it.id,x)))) then
   raise exception 'Issued credit allocation requires reconciliation before changing its line or recipient'; end if;
 if n.customer_id<>i.customer_id and exists(select 1 from public.invoice_line_credit_allocations where invoice_id=i.id and amount>reversed_amount) then
   raise exception 'Restore the original customer’s wallet-funded payment before changing the invoice customer'; end if;
 select coalesce(max(revision_no),0)+1 into v_rev from public.invoice_revisions where invoice_id=i.id;
 v_snapshot:=jsonb_build_object('invoice',to_jsonb(i),'edited_from_status',i.status,
  'items',(select coalesce(jsonb_agg(to_jsonb(it) order by id),'[]') from public.invoice_items it where invoice_id=i.id),
  'selections',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.invoice_promotion_selections s join public.invoice_items it on it.id=s.invoice_item_id where it.invoice_id=i.id));
 insert into public.invoice_revisions(invoice_id,revision_no,snapshot,edited_by,edit_reason,request_id)
 values(i.id,v_rev,v_snapshot,auth.uid(),p_reason,p_request_id);
 v_had_stock:=exists(select 1 from public.stock_movements where invoice_id=i.id and movement_type::text='store_sale');
 if v_stock_change and i.status not in ('cancelled','refunded') and v_had_stock then
   perform public.restore_invoice_stock(i.id,'Invoice correction: '||p_reason); end if;
 update public.invoices set store_id=n.store_id,customer_id=n.customer_id,affiliate_id=n.affiliate_id,affiliate_selection_explicit=n.affiliate_selection_explicit,notes=n.notes,
  business_date=n.business_date,instalment_category=n.instalment_category,instalment_method_id=n.instalment_method_id,instalment_months=n.instalment_months,
  created_by=n.created_by,save_earth_applied=n.save_earth_applied,save_earth_label=n.save_earth_label,save_earth_amount=n.save_earth_amount
 where id=i.id;
 if not same_lines or (n.manual_discount,n.discount_voucher_id,n.save_earth_applied,n.save_earth_amount) is distinct from
   (i.manual_discount,i.discount_voucher_id,i.save_earth_applied,i.save_earth_amount) or p_header ? 'service_staff' then
  perform public.update_invoice_internal(i.id,n.customer_id,n.affiliate_id,p_items,n.manual_discount,n.notes,n.discount_voucher_id,
    coalesce(p_header->'service_staff',v_staff),p_reason,
    i.status not in ('draft','unpaid') or exists(select 1 from public.invoice_payments where invoice_id=i.id));
 end if;
 if p_header ? 'payment_methods' and jsonb_array_length(p_header->'payment_methods')>0 then
   perform public.correct_invoice_payment_methods(i.id,p_header->'payment_methods',p_reason); end if;
 if (n.customer_id,n.store_id) is distinct from (i.customer_id,i.store_id) then
   update public.purchased_therapy_entitlements set customer_id=n.customer_id,store_id=n.store_id,updated_at=now()
    where invoice_id=i.id and status in ('pending_activation','scheduled');
 end if;
 select * into n from public.invoices where id=i.id;
 v_paid:=public.invoice_net_received(i.id);
 v_status:=case when i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then i.status
  when n.total_amount=0 and n.has_foc then 'completed_foc'::public.invoice_status
  when v_paid>=public.invoice_charge_total(i.id) and v_paid>0 then 'paid'::public.invoice_status
  when v_paid>0 then 'partially_paid'::public.invoice_status else 'unpaid'::public.invoice_status end;
 if v_stock_change and i.status not in ('cancelled','refunded') and v_had_stock then
   perform public.deduct_invoice_stock(i.id,'Invoice correction: '||p_reason); end if;
 update public.invoices set status=v_status,paid_amount=v_paid,edit_count=coalesce(i.edit_count,0)+1,edited_by=auth.uid(),edited_at=now() where id=i.id;
 if (n.affiliate_id,n.affiliate_selection_explicit,n.store_id,n.customer_id,n.total_amount) is distinct from (i.affiliate_id,i.affiliate_selection_explicit,i.store_id,i.customer_id,i.total_amount) or not same_lines then
   perform public.reconcile_invoice_commissions(i.id,coalesce(p_reason,'Invoice edited')); end if;
 select jsonb_build_object('invoice',to_jsonb(v),'items',(select jsonb_agg(to_jsonb(it)) from public.invoice_items it where it.invoice_id=i.id)) into v_after from public.invoices v where v.id=i.id;
 update public.invoice_revisions set after_snapshot=v_after where invoice_id=i.id and revision_no=v_rev;
 perform public.write_audit_ex('invoices',i.id,'invoice_corrected',v_snapshot,v_after,'invoices',p_reason,n.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'revision',v_rev);
end $$;

-- Backward compatible public RPCs. The financial transaction is shared.
create or replace function public.edit_paid_invoice(p_invoice_id uuid,p_lines jsonb,p_reason text,
 p_discount numeric default null,p_service_staff uuid[] default null,p_store_id uuid default null,
 p_affiliate_id uuid default null,p_set_affiliate boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct this invoice'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'A correction reason is required'; end if;
 return public.correct_invoice(p_invoice_id,p_lines,
  jsonb_strip_nulls(jsonb_build_object('manual_discount',p_discount,'service_staff',to_jsonb(p_service_staff),'store_id',p_store_id))
  ||case when p_set_affiliate then jsonb_build_object('affiliate_id',p_affiliate_id) else '{}'::jsonb end,p_reason);
end $$;
create or replace function public.update_invoice(p_invoice_id uuid,p_customer_id uuid,p_affiliate_id uuid,
 p_items jsonb,p_discount_total numeric default 0,p_notes text default null,p_discount_voucher_id uuid default null,
 p_service_staff jsonb default '[]',p_edit_reason text default null)
returns uuid language plpgsql security definer set search_path=public as $$
begin
 if not public.can_edit_invoice(p_invoice_id) then raise exception 'Use the Owner/Manager correction workflow for this invoice'; end if;
 perform public.correct_invoice(p_invoice_id,p_items,jsonb_build_object('customer_id',p_customer_id,'affiliate_id',p_affiliate_id,
  'manual_discount',p_discount_total,'notes',p_notes,'discount_voucher_id',p_discount_voucher_id,'service_staff',p_service_staff),p_edit_reason);
 return p_invoice_id;
end $$;
revoke all on function public.invoice_all_lines_match(uuid,jsonb),public.reconcile_invoice_commissions(uuid,text),public.restore_invoice_stock(uuid,text) from public,anon,authenticated;
revoke all on function public.correct_invoice(uuid,jsonb,jsonb,text,uuid),public.update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text),public.edit_paid_invoice(uuid,jsonb,text,numeric,uuid[],uuid,uuid,boolean) from public,anon;
grant execute on function public.correct_invoice(uuid,jsonb,jsonb,text,uuid),public.update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text),public.edit_paid_invoice(uuid,jsonb,text,numeric,uuid[],uuid,uuid,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
