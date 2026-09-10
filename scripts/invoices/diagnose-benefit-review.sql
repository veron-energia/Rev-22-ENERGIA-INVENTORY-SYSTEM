-- READ ONLY. Run on an isolated snapshot after migrations 170–191 and 193.
-- This is evidence for review, never an automatic allocation or cleanup.
begin transaction read only;
select i.id invoice_id,i.invoice_no,i.customer_id,c.full_name customer_name,it.id invoice_item_id,
 it.line_kind,it.plan_name_snapshot,it.voucher_id,
 case when it.line_kind='voucher' then 'Sold voucher has no customer-unit redemption mapping'
 when it.line_kind='promotion' then 'Promotion includes voucher units without source-linked redemption evidence'
 else 'Issued package has no recorded paid-value allocation; inspect every original recipient, bonus lot and reward' end review_reason
from public.invoices i join public.invoice_items it on it.invoice_id=i.id
left join public.customers c on c.id=i.customer_id
where i.deleted_at is null and (
 it.line_kind='voucher' or (it.line_kind='promotion' and (
  exists(select 1 from public.invoice_stock_components s where s.invoice_item_id=it.id and s.kind='voucher')
  or exists(select 1 from public.invoice_promotion_selections s where s.invoice_item_id=it.id and s.voucher_id is not null)))
 or (it.credit_issued_at is not null and not exists(select 1 from public.invoice_benefit_values b where b.invoice_item_id=it.id)))
order by i.created_at,i.id,it.id;

-- Original source records; no inferred recipient or current catalogue values.
select i.id invoice_id,i.invoice_no,s.id sale_id,s.customer_id,c.full_name recipient_name,
 s.external_paid,s.credit_lot_id,s.bonus_credit_lot_id,s.original_sources_verified_at,s.original_sources_evidence,s.reward_units,s.reward_voucher_qty,
 (select count(*) from public.invoice_items it where it.invoice_id=i.id and it.credit_package_id=s.package_id) matching_package_lines,
 case when s.reward_units>0 or s.reward_voucher_qty>0 then 'Qualification reward provenance and consumption need review before refund, cancellation or transfer'
 when s.bonus_credit_lot_id is null and s.original_sources_verified_at is null then 'No bonus lot link or verified no-bonus evidence; verify whether an original bonus grant exists'
 else 'Review original paid and bonus grants together' end evidence_note
from public.credit_package_sales s join public.invoices i on i.id=s.invoice_id left join public.customers c on c.id=s.customer_id
where (s.bonus_credit_lot_id is null and s.original_sources_verified_at is null) or s.reward_units>0 or s.reward_voucher_qty>0
 or exists(select 1 from public.invoice_items it where it.invoice_id=i.id and it.credit_package_id=s.package_id
 and not exists(select 1 from public.invoice_benefit_values b where b.invoice_item_id=it.id))
order by i.id,s.id;

-- Candidate bonus lots are evidence only, including when several have the same
-- amount/date. A human must establish the original source; never choose the first.
select s.invoice_id,s.id sale_id,s.customer_id,c.full_name recipient_name,s.package_id,
 l.id candidate_bonus_lot_id,l.original_amount,l.remaining_amount,l.original_purchase_date,l.store_id
from public.credit_package_sales s join public.customer_credit_lots l
 on l.customer_id=s.customer_id and l.store_id is not distinct from s.store_id
 and l.category='bonus' and l.source_type='credit_package' and l.source_record_id=s.package_id
left join public.customers c on c.id=s.customer_id
where s.bonus_credit_lot_id is null and s.original_sources_verified_at is null
 and not exists(select 1 from public.credit_package_sales other where other.id<>s.id and other.bonus_credit_lot_id=l.id)
 and not exists(select 1 from public.invoice_benefit_values b where b.lot_id=l.id)
order by s.invoice_id,s.id,l.id;

-- Original grants and their transferred unused portions are separate historical
-- records. Do not sum their original amounts as new money or new purchases.
select t.id transfer_id,i.id invoice_id,i.invoice_no,t.source_benefit_id,t.replacement_benefit_id,
 t.before_snapshot->>'customer_id' original_customer_id,t.customer_id current_recipient_id,c.full_name current_recipient,
 t.before_snapshot->>'store_id' original_store_id,t.store_id destination_store_id,t.transferred_value,t.reason,t.created_at
from public.invoice_benefit_transfers t join public.invoices i on i.id=t.invoice_id
left join public.customers c on c.id=t.customer_id order by t.created_at,t.id;
rollback;
