begin;
-- Manual evidence is not permission to omit a bonus lot or bypass store scope.
do $$ declare f text; anchor text; begin
 select pg_get_functiondef('public.record_invoice_benefit_values(uuid,jsonb,text)'::regprocedure) into f;
 anchor:=' if exists(select 1 from public.invoice_benefit_values where invoice_item_id=it.id) then';
 if position(anchor in f)=0 then raise exception 'Unexpected historical allocation validator'; end if;
 f:=replace(f,anchor,$patch$ if not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if exists(select 1 from public.invoice_items q where q.invoice_id=i.id and q.id<>it.id
  and (q.credit_package_id=it.credit_package_id or q.premium_bundle_id=it.premium_bundle_id)) then
  raise exception 'Multiple lines share this package. Resolve the exact sale-to-line mapping before recording historical benefit values.';
 end if;
$patch$||anchor);
 f:=replace(f,'c.credit_lot_id=l.id and c.package_id=it.credit_package_id',
  'l.id in(c.credit_lot_id,c.bonus_credit_lot_id) and c.package_id=it.credit_package_id');
 anchor:=' perform public.write_audit_ex(''invoice_items'',it.id,''benefit_values_reviewed''';
 if position(anchor in f)=0 then raise exception 'Unexpected historical allocation audit'; end if;
 f:=replace(f,anchor,$patch$ if exists(
  select 1 from (
   select unnest(array[c.credit_lot_id,c.bonus_credit_lot_id]) lot_id,null::uuid voucher_id
    from public.credit_package_sales c where c.invoice_id=i.id and c.package_id=it.credit_package_id
   union all select unnest(array[s.paid_credit_lot_id,s.bonus_credit_lot_id]),null::uuid
    from public.premium_bundle_sales s where s.invoice_id=i.id and s.bundle_id=it.premium_bundle_id
   union all select null::uuid,v.id from public.customer_reward_vouchers v
    join public.premium_bundle_sales s on s.id=v.source_id where s.invoice_id=i.id and s.bundle_id=it.premium_bundle_id
  ) expected where (expected.lot_id is not null or expected.voucher_id is not null) and not exists(
   select 1 from public.invoice_benefit_values recorded where recorded.invoice_item_id=it.id
   and (recorded.lot_id=expected.lot_id or recorded.reward_voucher_id=expected.voucher_id))) then
  raise exception 'Record every original paid-credit, bonus-credit and voucher allocation together; partial historical mappings are not accepted';
 end if;
 if total is distinct from (select coalesce(sum(s.external_paid),0) from (
  select c.external_paid from public.credit_package_sales c where c.invoice_id=i.id and c.package_id=it.credit_package_id
  union all select p.external_paid from public.premium_bundle_sales p where p.invoice_id=i.id and p.bundle_id=it.premium_bundle_id) s) then
  raise exception 'Historical allocations must reconcile to the original recorded external payment, including zero-paid bonus components';
 end if;
$patch$||anchor);
 execute f;
end $$;

-- The legacy catalogue-voucher path does not identify a customer's issued unit
-- or its redemption. A sale stock movement alone cannot prove unused entitlement.
-- Keep this case pending review instead of paying an unverifiable refund.
create function public.invoice_untracked_voucher(p_invoice_id uuid,p_item_id uuid default null)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.invoice_items it where it.invoice_id=p_invoice_id and (p_item_id is null or it.id=p_item_id)
  and (it.line_kind='voucher' or (it.line_kind='promotion' and (
   exists(select 1 from public.invoice_stock_components sc where sc.invoice_item_id=it.id and sc.kind='voucher')
   or exists(select 1 from public.invoice_promotion_selections s where s.invoice_item_id=it.id and s.voucher_id is not null)))))
$$;
revoke all on function public.invoice_untracked_voucher(uuid,uuid) from public,anon,authenticated;
do $$ declare f text; anchor text; begin
 select pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 anchor:='     v_line_paid:=coalesce(public.invoice_discounted_line_value(it.id),0);';
 if position(anchor in f)=0 then raise exception 'Unexpected refund line validator'; end if;
 f:=replace(f,anchor,$patch$     if public.invoice_untracked_voucher(i.id,it.id) then
      raise exception 'This sold voucher has no source-linked unused/redemption record. Review the original issued units before refunding this line; stock movement alone is insufficient evidence.';
     end if;
$patch$||anchor);
 anchor:='     if exists(select 1 from public.invoice_items where invoice_id=i.id and credit_issued_at is not null) then';
 if position(anchor in f)=0 then raise exception 'Unexpected unallocated refund validator'; end if;
 execute replace(f,anchor,'     if public.invoice_untracked_voucher(i.id) or exists(select 1 from public.invoice_items where invoice_id=i.id and credit_issued_at is not null) then');
 select pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure) into f;
 anchor:=' if exists(select 1 from public.rentals where invoice_id=i.id';
 if position(anchor in f)=0 then raise exception 'Unexpected cancellation validator'; end if;
 execute replace(f,anchor,$patch$ if public.invoice_untracked_voucher(i.id) and exists(select 1 from public.invoice_payments where invoice_id=i.id) then
  raise exception 'Review the original issued voucher units and redemption evidence before cancelling this invoice; unused voucher stock cannot be inferred from its sale.';
 end if;
$patch$||anchor);
 select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 anchor:=' if v_operational and i.stock_snapshot_version is null';
 if position(anchor in f)=0 then raise exception 'Unexpected operational correction validator'; end if;
 execute replace(f,anchor,$patch$ if v_operational and public.invoice_untracked_voucher(i.id) and exists(select 1 from public.invoice_payments where invoice_id=i.id) then
  raise exception 'Review the original issued voucher units before changing their customer, store or invoice allocation';
 end if;
$patch$||anchor);
 select pg_get_functiondef('public.invoice_refund_options(uuid)'::regprocedure) into f;
 anchor:='''review_required'',exists';
 if position(anchor in f)=0 then raise exception 'Unexpected refund review preview'; end if;
 execute replace(f,anchor,$patch$'review_notes',case when public.invoice_untracked_voucher(i.id) then
  jsonb_build_array('Sold vouchers on this invoice need original issuance and redemption evidence. Their refunds, cancellation and operational corrections stay pending review; other eligible lines can still be refunded.') else '[]'::jsonb end,
 'review_required',exists$patch$);
end $$;
notify pgrst,'reload schema';
commit;
