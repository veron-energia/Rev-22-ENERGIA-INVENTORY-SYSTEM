-- Before 416: puts back, for one test run, the three functions 416 changes
-- that earlier suites pin to their pre-416 text.
--
-- Three suites replay a migration inside their own transaction, and that
-- migration (or the suite) refuses a function that is not the version it was
-- tested against. Once 416 is live they stop:
--   scripts/commissions/tests/clawbacks-carried-forward.sql and
--   scripts/therapy/tests/status-refresh.sql replay 410, whose guard takes
--   correct_invoice at 410's AFTER md5 only (5f3f317d...), not 416's
--   (8a126ade...);
--   scripts/xero/tests/sales-events.sql checks correct_invoice_payment
--   (63efea7e..., 416: f3c96d99...) and record_invoice_payment (95a02a16...,
--   416: c3da81f2...) before it replays 411.
-- Run any of them with this file as the prelude, which each runs right after
-- its "begin;":
--   psql -X -v ON_ERROR_STOP=1 -v prelude=scripts/invoices/tests/before-416-prelude.sql -f <suite>
-- On a database without 416 it changes nothing. Each function must be 416's
-- version (for correct_invoice, 416's or 434's) or already the one before
-- it; anything else is refused. The
-- texts are production's of 9 Oct 2026, before 416. Everything is undone
-- with the suite's own rollback. Never run this outside a test transaction.
do $b416$
declare
  r record; v text; v_path text := current_setting('search_path');
  c_correct_invoice constant text := $def$CREATE OR REPLACE FUNCTION public.correct_invoice(p_invoice_id uuid, p_items jsonb, p_header jsonb, p_reason text, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i public.invoices%rowtype; n public.invoices%rowtype; c record; same_lines boolean; same_header boolean; v356_prices jsonb; v356_worth jsonb;
 v_snapshot jsonb; v_rev int; v_paid numeric; v_status public.invoice_status; v_staff jsonb;
 v_operational boolean; v_stock_change boolean; v_had_stock boolean; v_after jsonb;
 v362_before jsonb; v362_therapy jsonb := '{}'::jsonb;
 v393_before uuid[];  -- 393: the lines before this correction
 v399_open boolean := false;  -- 399: not yet paid in full: stock moves only if this settles it
 -- 377: v377_staff, a staff member correcting a settled invoice they may
 -- (staff_may_correct_invoice). v377_ask, added to a refusal only an Owner or
 -- Manager can resolve, for any staff member (paid or unpaid); empty for
 -- every other role, whose messages stay word for word.
 v377_staff boolean := false;
 v377_ask text := case when public.current_user_role() = 'staff'
                       then '. Only an Owner or Manager can do this, so ask one to do it first' else '' end;
begin
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found or i.deleted_at is not null then raise exception 'Invoice not found'; end if;
 if not public.user_has_store_access(i.store_id) then raise exception 'No access to this invoice'; end if;
 if i.status not in ('draft','unpaid') or exists(select 1 from public.invoice_payments where invoice_id=i.id) then
   -- 377: staff correct a paid or part-paid invoice of their own store
   -- (staff_may_correct_invoice); the money in it stays with an Owner or
   -- Manager, through the payment and price checks further down.
   v377_staff := public.staff_may_correct_invoice(i.id);
   if not public.is_owner_or_manager() and not v377_staff then
     if public.current_user_role() = 'staff' then
       raise exception 'Only an Owner or Manager can correct this invoice. Staff can correct a paid or part-paid invoice of their own store while no refund or cancellation request is waiting on it'; end if;
     raise exception 'Only an Owner or Manager can correct this invoice'; end if;
   if nullif(trim(p_reason),'') is null then raise exception 'A correction reason is required'; end if;
 end if;
 if i.status in ('draft','unpaid') and not exists(select 1 from public.invoice_payments where invoice_id=i.id) and not public.can_edit_invoice(i.id) then raise exception 'You cannot edit this invoice'; end if;
 if public.invoice_revision_retry(i.id,p_request_id,jsonb_build_object('operation','correct','items',p_items,'header',p_header,'reason',p_reason)) then
   return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replayed',true); end if;
 if p_header ? 'expected_edit_count' and (p_header->>'expected_edit_count')::int<>coalesce(i.edit_count,0) then
   raise exception 'This invoice was changed by another user. Reload it before saving.'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0 then raise exception 'Keep at least one line'; end if;
 -- 370: the names of people on unchanged ticket lines.
 perform public.event_sync_ticket_names(i.id,p_items);
 same_lines:=public.invoice_all_lines_match(i.id,p_items);
 n:=i;
 if p_header ? 'customer_id' then n.customer_id:=nullif(p_header->>'customer_id','')::uuid; end if;
 if p_header ? 'store_id' then n.store_id:=nullif(p_header->>'store_id','')::uuid; end if;
 -- 377: a store move takes the sale, its stock and its commission to another
 -- store, so it stays with an Owner or Manager, even between two stores the
 -- staff member works at.
 if v377_staff and n.store_id is distinct from i.store_id then
   raise exception 'Only an Owner or Manager can move an invoice to another store'; end if;
 if p_header ? 'affiliate_id' then n.affiliate_id:=nullif(p_header->>'affiliate_id','')::uuid; n.affiliate_selection_explicit:=true; end if;
 if p_header ? 'notes' then n.notes:=p_header->>'notes'; end if;
 if p_header ? 'manual_discount' then n.manual_discount:=(p_header->>'manual_discount')::numeric; end if;
 if p_header ? 'manual_discount_reason' then n.manual_discount_reason:=nullif(btrim(p_header->>'manual_discount_reason'),''); end if;
 if coalesce(n.manual_discount,0) > 0 and n.manual_discount is distinct from i.manual_discount and n.manual_discount_reason is null then
   raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.'; end if;
 if coalesce(n.manual_discount,0) <= 0 then n.manual_discount_reason:=null; end if;
 if p_header ? 'discount_voucher_id' then n.discount_voucher_id:=nullif(p_header->>'discount_voucher_id','')::uuid; end if;
 if p_header ? 'business_date' then n.business_date:=(p_header->>'business_date')::date; end if;
 if p_header ? 'instalment_category' then
  n.instalment_category:=nullif(p_header->>'instalment_category','');
  n.instalment_method_id:=nullif(p_header->>'instalment_method_id','')::uuid;
  n.instalment_months:=nullif(p_header->>'instalment_months','')::int;
 end if;
 if p_header ? 'created_by' and nullif(p_header->>'created_by','')::uuid is distinct from i.created_by then
   if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct invoice attribution'; end if;
   n.created_by:=nullif(p_header->>'created_by','')::uuid;
 end if;
 if not exists(select 1 from public.customers where id=n.customer_id and deleted_at is null) then raise exception 'Choose a non-deleted customer'; end if;
 if not public.user_has_store_access(n.store_id) then raise exception 'No access to the selected store'; end if;
 if n.affiliate_id is not null and not exists(select 1 from public.customer_affiliates where id=n.affiliate_id and deleted_at is null) then raise exception 'Affiliate not found'; end if;
 -- 396: a rental's late fee has no affiliate, explicitly (the Owner, 6 Oct 2026).
 if n.affiliate_id is not null and public.invoice_is_late_fee(i.id) then
   raise exception 'This invoice is a rental''s late fee: it has no affiliate and earns no commission.'; end if;
 if n.manual_discount<0 or n.save_earth_amount<0 then raise exception 'Discount cannot be negative'; end if;
 select coalesce(jsonb_agg(staff_id order by staff_id),'[]') into v_staff from public.invoice_service_staff where invoice_id=i.id;
 same_header:=to_jsonb(n)=to_jsonb(i) and (not(p_header ? 'service_staff') or
   v_staff=(select coalesce(jsonb_agg(x order by x),'[]') from jsonb_array_elements(p_header->'service_staff') x));
 if same_lines and same_header and coalesce(p_header->'payment_methods','[]')='[]'::jsonb and coalesce(p_header->'payment_corrections','[]')='[]'::jsonb and coalesce(p_header->'payment_removals','[]')='[]'::jsonb then
   if p_request_id is not null then
    perform public.correct_invoice_therapy_sessions(i.id,p_items,n.customer_id,n.store_id,p_reason,p_request_id);
 select coalesce(max(revision_no),0)+1 into v_rev from public.invoice_revisions where invoice_id=i.id;
    insert into public.invoice_revisions(invoice_id,revision_no,snapshot,after_snapshot,edited_by,edit_reason,request_id,request_hash)
     values(i.id,v_rev,jsonb_build_object('invoice',to_jsonb(i),'unchanged',true),jsonb_build_object('invoice',to_jsonb(i),'unchanged',true),
      auth.uid(),p_reason,p_request_id,md5(jsonb_build_object('operation','correct','items',p_items,'header',p_header,'reason',p_reason)::text));
   end if;

   return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'unchanged',true); end if;
 v_stock_change:=not public.invoice_operational_lines_match(i.id,p_items) or n.store_id<>i.store_id;
 v_operational:=v_stock_change or n.customer_id<>i.customer_id;
 if v_operational and public.invoice_untracked_voucher(i.id) and exists(select 1 from public.invoice_payments where invoice_id=i.id) then
  raise exception 'Review the original issued voucher units before changing their customer, store or invoice allocation%', v377_ask;
 end if;
 if v_operational and i.stock_snapshot_version is null and exists(select 1 from public.invoice_items where invoice_id=i.id and line_kind in ('promotion','voucher')) then
   raise exception 'Historical component snapshots need review before changing stock or selections; metadata can still be corrected%', v377_ask; end if;
 -- 410: by its dates as well (the nightly refresh may not have run yet).
 if v_operational and exists(select 1 from public.purchased_therapy_entitlements where invoice_id=i.id
     and public.purchased_therapy_status_on(status,activation_date,expiry_date,activation_deadline,public.sg_today()) in ('active','expired')) then
   raise exception 'Resolve the consumed therapy entitlement before changing its customer, store or invoice lines%', v377_ask; end if;
 if v_operational and exists(select 1 from public.rentals where invoice_id=i.id and public.rental_is_outstanding(status::text)) then
   raise exception 'Return or resolve the outstanding rental before changing its invoice allocation'; end if;
 -- Issued identifiers survive metadata-only corrections. A changed entitlement
 -- must be reconciled before its defining line/customer can change.
 if not same_lines and exists(select 1 from public.invoice_items it where it.invoice_id=i.id
    and it.credit_issued_at is not null and (not exists(
      select 1 from jsonb_array_elements(p_items) x where public.invoice_line_matches(it.id,x) or public.invoice_benefit_price_only(it.id,x)))) then
   raise exception 'Issued credit allocation requires reconciliation before changing its line or recipient%', v377_ask; end if;
 -- Which of the two corrections is this? Required whenever the customer or
 -- store changes and this invoice actually issued something.
 -- Only when the CUSTOMER changes. That is the correction with two meanings;
 -- a store move keeps the behaviour it has always had rather than growing a
 -- question about benefits it was not asking.
 if n.customer_id is distinct from i.customer_id
   and exists(select 1 from public.invoice_transferable_benefits(i.id)) then
  if coalesce(p_header->>'benefit_action','') not in ('transfer','keep') then
   raise exception 'BENEFIT_ACTION_REQUIRED: This invoice issued benefits. Choose whether to move the unused ones to the new customer (transfer) or leave them with whoever holds them now (keep).';
  end if;
 end if;
 if n.customer_id<>i.customer_id and exists(select 1 from public.invoice_line_credit_allocations where invoice_id=i.id and amount>reversed_amount) then
   raise exception 'Restore the original customer’s wallet-funded payment before changing the invoice customer%', v377_ask; end if;
 perform public.correct_invoice_therapy_sessions(i.id,p_items,n.customer_id,n.store_id,p_reason,p_request_id);
 select coalesce(max(revision_no),0)+1 into v_rev from public.invoice_revisions where invoice_id=i.id;
 v_snapshot:=jsonb_build_object('invoice',to_jsonb(i),'edited_from_status',i.status,
  'items',(select coalesce(jsonb_agg(to_jsonb(it) order by id),'[]') from public.invoice_items it where invoice_id=i.id),
  'selections',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.invoice_promotion_selections s join public.invoice_items it on it.id=s.invoice_item_id where it.invoice_id=i.id));
 insert into public.invoice_revisions(invoice_id,revision_no,snapshot,edited_by,edit_reason,request_id)
 values(i.id,v_rev,v_snapshot,auth.uid(),p_reason,p_request_id);
 v_had_stock:=exists(select 1 from public.stock_movements where invoice_id=i.id and movement_type::text='store_sale');
 -- 399: an invoice not yet paid in full holds no sale to put back: any
 -- store_sale on it is goods the customer took before paying in full (the
 -- Owner, 6 Oct 2026), and they stay out. So nothing is put back on the
 -- shelf here; the corrected lines must keep every product the customer
 -- has (invoice_goods_kept_check, below); and the goods left this store,
 -- so the store cannot change while they are out.
 v399_open := public.invoice_before_full_payment(i.id);
 if v399_open and n.store_id is distinct from i.store_id
    and exists(select 1 from public.invoice_goods_out(i.id)) then
   raise exception 'GOODS_HANDED_OVER: Goods on this invoice were handed over from its store before full payment, so it cannot move to another store. Record them as returned first (Record items returned on the invoice, Owner or Manager).'; end if;
 if v_stock_change and i.status not in ('cancelled','refunded') and v_had_stock and not v399_open then
   perform public.restore_invoice_stock(i.id,'Invoice correction: '||p_reason); end if;
 update public.invoices set store_id=n.store_id,customer_id=n.customer_id,affiliate_id=n.affiliate_id,affiliate_selection_explicit=n.affiliate_selection_explicit,notes=n.notes,
  business_date=n.business_date,instalment_category=n.instalment_category,instalment_method_id=n.instalment_method_id,instalment_months=n.instalment_months,
  created_by=n.created_by,manual_discount_reason=n.manual_discount_reason,save_earth_applied=n.save_earth_applied,save_earth_label=n.save_earth_label,save_earth_amount=n.save_earth_amount
 where id=i.id;
 if not same_lines or (n.manual_discount,n.discount_voucher_id,n.save_earth_applied,n.save_earth_amount) is distinct from
   (i.manual_discount,i.discount_voucher_id,i.save_earth_applied,i.save_earth_amount)
   -- 384: when they change, not whenever the screen sends them, so a note,
   -- date, customer or payment correction leaves the invoice's money alone.
   or (p_header ? 'service_staff' and v_staff is distinct from
       (select coalesce(jsonb_agg(x order by x),'[]') from jsonb_array_elements(p_header->'service_staff') x)) then
  -- 396: a rental's late fee is set at its return and never rewritten here.
  if public.invoice_is_late_fee(i.id) then
    raise exception 'This invoice is a rental''s late fee, set at its Return: its line cannot be corrected. Correct a wrong payment on the payment itself (Correct amount / date); to give money back, refund or cancel the invoice.'; end if;
  perform set_config('invoice.manual_discount_reason',coalesce(n.manual_discount_reason,''),true);
  -- 356: settled credit lines' prices and worth before this correction.
  v356_prices := (select coalesce(jsonb_object_agg(x.id::text, x.unit_price), '{}'::jsonb) from public.invoice_items x
                   where x.invoice_id = i.id and x.line_kind in ('credit_package','premium_bundle')
                     and x.credit_issued_at is not null);
  v356_worth := (select coalesce(jsonb_object_agg(x.id::text, public.credit_line_paid_entitlement(x.id)), '{}'::jsonb)
                   from public.invoice_items x
                  where x.invoice_id = i.id and x.line_kind in ('credit_package','premium_bundle')
                    and x.credit_issued_at is not null);
  -- 362: the lines this correction removes or rewrites, and the therapy they
  -- issued, noted (and locked) before the lines are replaced.
  v362_before := public.therapy_units_before_correction(i.id,p_items);
  v393_before := array(select id from public.invoice_items where invoice_id = i.id);
  perform public.update_invoice_internal(i.id,n.customer_id,n.affiliate_id,p_items,n.manual_discount,n.notes,n.discount_voucher_id,
    coalesce(p_header->'service_staff',v_staff),p_reason,
    i.status not in ('draft','unpaid') or exists(select 1 from public.invoice_payments where invoice_id=i.id));
  perform set_config('invoice.manual_discount_reason','',true);
  -- 362: that therapy follows the corrected lines: kept, moved to a line this
  -- correction added, or closed if unused (refused if used).
  v362_therapy := public.settle_corrected_therapy_units(i.id,v362_before,p_reason,p_request_id);
  -- 355: a discount may not leave released paid credit above what the line is now worth.
  perform public.trim_released_paid_credit(i.id, coalesce(p_reason,'Invoice corrected'));
  -- 356: a settled credit line may not be made worth more than it was issued at:
  -- every settled line when the invoice's discounts changed, otherwise those
  -- whose own price went up.
  perform public.refuse_settled_credit_line_raise(i.id,
    case when (coalesce(n.manual_discount,0),n.discount_voucher_id,coalesce(n.save_earth_applied,false),coalesce(n.save_earth_amount,0))
              is distinct from
              (coalesce(i.manual_discount,0),i.discount_voucher_id,coalesce(i.save_earth_applied,false),coalesce(i.save_earth_amount,0)) then null
         else array(select x.id from public.invoice_items x
                     where x.invoice_id = i.id and x.credit_issued_at is not null
                       and x.unit_price > coalesce((v356_prices->>(x.id::text))::numeric, x.unit_price)) end,
    -- A discount cut (manual discount lowered, voucher changed or removed, Save
    -- Earth lowered) is held to what the line was issued at; otherwise a line
    -- already worth more after an allowed re-spread is held to that.
    case when coalesce(n.manual_discount,0) < coalesce(i.manual_discount,0)
              or n.discount_voucher_id is distinct from i.discount_voucher_id
              or coalesce(n.save_earth_amount,0) < coalesce(i.save_earth_amount,0)
              or (coalesce(i.save_earth_applied,false) and not coalesce(n.save_earth_applied,false))
         then '{}'::jsonb else v356_worth end);
  -- 356: money already received counts toward a credit line this correction added or swapped in.
  perform public.release_credit_package_paid_credit(i.id);
 end if;
 if p_header ? 'payment_methods' and jsonb_array_length(p_header->'payment_methods')>0 then
   perform public.correct_invoice_payment_methods(i.id,p_header->'payment_methods',p_reason); end if;
 -- 336: amount and date corrections and removals go through the same rules the
 -- per-payment buttons use, inside this transaction, each with a request id
 -- derived from this correction's so a replay cannot apply them twice.
 for c in select * from jsonb_array_elements(coalesce(p_header->'payment_corrections','[]'::jsonb)) loop
   -- 337: parts. One is the plain correction; two or more are a split.
   if jsonb_typeof(c.value->'parts') = 'array' and jsonb_array_length(c.value->'parts') > 1 then
     perform public.split_invoice_payment((c.value->>'payment_id')::uuid,c.value->'parts',coalesce(p_reason,'Invoice edited'),
       md5(coalesce(p_request_id::text,i.id::text)||'/split/'||(c.value->>'payment_id'))::uuid);
   else
     perform public.correct_invoice_payment((c.value->>'payment_id')::uuid,
       coalesce(c.value->'parts'->0->>'amount',c.value->>'amount')::numeric,
       coalesce(c.value->'parts'->0->>'date',c.value->>'date')::date,
       nullif(coalesce(c.value->'parts'->0->>'payment_method_id',c.value->>'payment_method_id'),'')::uuid,coalesce(p_reason,'Invoice edited'),
       md5(coalesce(p_request_id::text,i.id::text)||'/correct/'||(c.value->>'payment_id'))::uuid);
   end if;
 end loop;
 for c in select * from jsonb_array_elements_text(coalesce(p_header->'payment_removals','[]'::jsonb)) loop
   perform public.remove_invoice_payment(c.value::uuid,coalesce(p_reason,'Invoice edited'),
     md5(coalesce(p_request_id::text,i.id::text)||'/remove/'||c.value)::uuid);
 end loop;
 if (n.customer_id,n.store_id) is distinct from (i.customer_id,i.store_id) then
   if coalesce(p_header->>'benefit_action','') = 'transfer' then
   update public.purchased_therapy_entitlements set customer_id=n.customer_id,store_id=n.store_id,updated_at=now()
    where invoice_id=i.id and status in ('pending_activation','scheduled');
   end if;
   -- Only when asked. "keep" changes the invoice's customer and leaves the
   -- benefits where they are, which stays visible because the benefits are
   -- found through this invoice's own lines and sales rather than its customer.
   if coalesce(p_header->>'benefit_action','') = 'transfer' then
     perform public.move_invoice_benefits_to_customer(i.id,n.customer_id,n.store_id,
       coalesce(p_reason,'Invoice reassigned'));
   end if;
 end if;
 select * into n from public.invoices where id=i.id;
 -- 384: a Birthday discount is for this customer on this date, so a
 -- correction that moves either checks the invoice's birthday lines again.
 if (n.customer_id, n.business_date) is distinct from (i.customer_id, i.business_date) then
   perform public.invoice_birthday_lines_check(i.id); end if;
 v_paid:=public.invoice_net_received(i.id);
 v_status:=case when i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then i.status
  when n.total_amount=0 and n.has_foc then 'completed_foc'::public.invoice_status
  when v_paid>=public.invoice_charge_total(i.id) and v_paid>0 then 'paid'::public.invoice_status
  when v_paid>0 then 'partially_paid'::public.invoice_status else 'unpaid'::public.invoice_status end;
 -- 399: on an invoice not yet paid in full the corrected lines keep the
 -- goods the customer has, and stock is taken only if the correction
 -- settles it, then only what is not out already (deduct_invoice_stock is
 -- net). Before 399 every line was taken here, paid or not.
 if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
 if v_stock_change and i.status not in ('cancelled','refunded') and v_had_stock
    and (not v399_open or v_status in ('paid','completed_foc')) then
   perform public.deduct_invoice_stock(i.id,'Invoice correction: '||p_reason); end if;
 update public.invoices set status=v_status,paid_amount=v_paid,edit_count=coalesce(i.edit_count,0)+1,edited_by=auth.uid(),edited_at=now() where id=i.id;
 -- 393: a correction that makes the invoice paid raises its special and
 -- rental items, as paying does. On an invoice that was already paid,
 -- only the lines this correction added are raised; a line that was
 -- already there without an item is left alone (the Owner, 6 Oct 2026).
 -- A removed line's waiting item was cancelled as the line went.
 if v_status='paid' and i.status is distinct from 'paid' then
   perform public.create_special_docs_for_invoice(i.id);
 elsif v_status='paid' and not same_lines then
   perform set_config('energia.special_docs_only', coalesce((select string_agg(ii.id::text, ',')
     from public.invoice_items ii where ii.invoice_id = i.id
      and not (ii.id = any(coalesce(v393_before, '{}'::uuid[])))), ''), true);
   if current_setting('energia.special_docs_only', true) <> '' then
     perform public.create_special_docs_for_invoice(i.id); end if;
   perform set_config('energia.special_docs_only', '', true);
 end if;
 -- 362: therapy the added or rewritten lines grant, issued now if the invoice is paid.
 if v362_before is not null then
   v362_therapy := v362_therapy || public.issue_therapy_of_corrected_lines(i.id,v362_before); end if;
 if (n.affiliate_id,n.affiliate_selection_explicit,n.store_id,n.customer_id,n.total_amount) is distinct from (i.affiliate_id,i.affiliate_selection_explicit,i.store_id,i.customer_id,i.total_amount) or not same_lines then
   perform public.reconcile_invoice_commissions(i.id,coalesce(p_reason,'Invoice edited')); end if;
 select jsonb_build_object('invoice',to_jsonb(v),'items',(select jsonb_agg(to_jsonb(it)) from public.invoice_items it where it.invoice_id=i.id)) into v_after from public.invoices v where v.id=i.id;
 if v362_therapy <> '{}'::jsonb then v_after := v_after || jsonb_build_object('therapy',v362_therapy); end if;
 update public.invoice_revisions set request_hash=md5((jsonb_build_object('operation','correct','items',p_items,'header',p_header,'reason',p_reason))::text),after_snapshot=v_after where invoice_id=i.id and revision_no=v_rev;
 perform public.write_audit_ex('invoices',i.id,'invoice_corrected',v_snapshot,v_after,'invoices',p_reason,n.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'revision',v_rev,'therapy',v362_therapy);
end $function$
$def$;
  c_correct_invoice_payment constant text := $def$CREATE OR REPLACE FUNCTION public.correct_invoice_payment(p_payment_id uuid, p_amount numeric, p_date date, p_method_id uuid, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  when n>=public.invoice_charge_total(i.id) then 'paid'::invoice_status when n>0 then 'partially_paid'::invoice_status else 'unpaid'::invoice_status end where id=i.id;
 perform public.reconcile_invoice_commissions(i.id,'Payment correction: '||p_reason);
 perform public.write_audit_ex('invoice_payments',p.id,'payment_corrected',to_jsonb(p),jsonb_build_object('reversal',v_reverse,'replacement',v_replace,'amount',p_amount,'effective_date',p_date,'method_id',m.id),'payments',p_reason,i.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replacement_id',v_replace);
end $function$
$def$;
  c_record_invoice_payment constant text := $def$CREATE OR REPLACE FUNCTION public.record_invoice_payment(p_invoice_id uuid, p_payments jsonb, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if nullif(x->>'payment_date','') is not null then
   if (x->>'payment_date')::date > (now() at time zone 'Asia/Singapore')::date then
    raise exception 'A payment cannot be dated in the future'; end if;
  end if;
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
end $function$
$def$;
begin
  -- Read and compared with public alone on the search path, as 416 reads them.
  perform set_config('search_path', 'public', true);
  -- 434 changes correct_invoice again (422682d6...): it is put back the same way.
  for r in select * from (values
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', '5f3f317dfb226be09055142dc44bdec7',
     array['8a126ade5710d340378ac4e75931b05b', '422682d6e1ada0e5d98053e74ab9f007'], c_correct_invoice),
    ('correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', '63efea7ed4721721b598f2e1237b8f6c', array['f3c96d9916a95a68a9202cdb25d8017b'], c_correct_invoice_payment),
    ('record_invoice_payment(uuid,jsonb,uuid)', '95a02a1685af524ecf0201b4ed7f9a67', array['c3da81f28d5a24a1c5f336527cfc33a4'], c_record_invoice_payment)
  ) x(fn, before_md5, after_md5, def)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v = r.before_md5 then continue; end if;
    if not (v = any(r.after_md5)) then
      raise exception 'before-416 prelude: public.% is neither 416''s version nor the one before it (md5 %)', r.fn, v; end if;
    if md5(r.def) <> r.before_md5 then
      raise exception 'before-416 prelude: the text kept for public.% is not the one before 416', r.fn; end if;
    execute r.def;
    if md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.before_md5 then
      raise exception 'before-416 prelude: public.% did not install as the version before 416', r.fn; end if;
  end loop;
  perform set_config('search_path', v_path, true);
end $b416$;
