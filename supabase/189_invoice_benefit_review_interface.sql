begin;
-- Review data contains original source records and blank paid-value allocations.
-- It deliberately does not derive historical values from today's catalogue.
create function public.invoice_benefit_review_options(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can review historical benefit values'; end if;
 if not exists(select 1 from public.invoices where id=p_invoice_id and deleted_at is null and public.user_has_store_access(store_id)) then
  raise exception 'Invoice not accessible'; end if;
 return (
 with pending as (
  select it.* from public.invoice_items it where it.invoice_id=p_invoice_id and it.credit_issued_at is not null
  and it.line_kind in ('credit_package','premium_bundle') and not exists(select 1 from public.invoice_benefit_values b where b.invoice_item_id=it.id)
 ), sales as (
  select it.id item_id,c.id sale_id,c.external_paid,c.credit_lot_id paid_lot,c.bonus_credit_lot_id bonus_lot,'credit_package' kind
   from pending it join public.credit_package_sales c on c.invoice_id=it.invoice_id and c.package_id=it.credit_package_id
  union all select it.id,c.id,c.external_paid,c.paid_credit_lot_id,c.bonus_credit_lot_id,'premium_bundle'
   from pending it join public.premium_bundle_sales c on c.invoice_id=it.invoice_id and c.bundle_id=it.premium_bundle_id
 ), benefits as (
  select s.item_id,l.id lot_id,null::uuid reward_voucher_id,l.customer_id,l.category kind,l.original_amount granted_value
   from sales s join public.customer_credit_lots l on l.id in(s.paid_lot,s.bonus_lot)
  union all select s.item_id,null,v.id,v.customer_id,'voucher',v.quantity
   from sales s join public.customer_reward_vouchers v on v.source_id=s.sale_id where s.kind='premium_bundle'
 )
 select jsonb_build_object('lines',coalesce(jsonb_agg(jsonb_build_object(
  'invoice_item_id',it.id,'name',coalesce(it.plan_name_snapshot,it.line_kind::text),
  'external_paid',(select coalesce(sum(s.external_paid),0) from sales s where s.item_id=it.id),
  'review_note','Use the original receipt and grant records to allocate the actual amount paid across every original paid-credit, bonus-credit and voucher component. Zero paid value is allowed where supported by evidence. Do not use current catalogue prices.',
  'blocked_reason',case
   when exists(select 1 from public.invoice_items other where other.invoice_id=it.invoice_id and other.id<>it.id
    and (other.credit_package_id=it.credit_package_id or other.premium_bundle_id=it.premium_bundle_id))
    then 'Multiple lines share this package. The exact sale-to-line mapping needs review first.'
   when not exists(select 1 from sales s where s.item_id=it.id) then 'No original sale record is linked. Resolve the source record first.'
   when not exists(select 1 from benefits b where b.item_id=it.id) then 'No original grant IDs are linked. Resolve the original benefit sources first.'
   else null end,
  'benefits',(select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('lot_id',b.lot_id,'reward_voucher_id',b.reward_voucher_id,
    'customer_name',c.full_name,'kind',b.kind,'granted_value',b.granted_value)) order by b.kind,b.customer_id,b.lot_id,b.reward_voucher_id),'[]')
   from benefits b left join public.customers c on c.id=b.customer_id where b.item_id=it.id)
 ) order by it.id),'[]')) from pending it);
end $$;
revoke all on function public.invoice_benefit_review_options(uuid) from public,anon;
grant execute on function public.invoice_benefit_review_options(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
