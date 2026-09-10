-- READ ONLY. Run with an approved read-only operator role on a review snapshot
-- after270–272. Contains operational IDs; keep the report private.
begin transaction read only;
select started_at complete_inventory_observations_begin_at,'Asia/Singapore' timezone from public.stock_history_observation;
-- These historical boundaries have no complete observation baseline. Never
-- interpret a first movement as proof of zero opening stock.
select p.id product_id,p.name,p.sku,x.location_key,min(coalesce(m.stock_history_recorded_at,m.created_at)) earliest_movement,o.started_at,
 'Opening balances before observation start require a verified historical baseline and complete intervening effects' review_reason
from public.stock_movements m join public.products p on p.id=m.product_id cross join public.stock_history_observation o
cross join lateral(values('store:'||m.from_store_id),('store:'||m.to_store_id),('warehouse:'||m.from_warehouse_id),('warehouse:'||m.to_warehouse_id)) x(location_key)
where x.location_key is not null and coalesce(m.stock_history_recorded_at,m.created_at)<o.started_at group by p.id,p.name,p.sku,x.location_key,o.started_at;
-- A difference here means inventory changed without the expected observation
-- evidence (for example a disabled trigger), not an instruction to adjust stock.
with actual as(select product_id,'store:'||store_id location_key,current_qty quantity from public.store_inventory
 union all select product_id,'warehouse:'||warehouse_id,current_qty from public.warehouse_inventory),
 evidence as(select product_id,location_key,sum(quantity) quantity from(
 select product_id,location_key,quantity from public.stock_history_baselines union all
 select product_id,location_key,delta from public.stock_history_inventory_changes) q group by product_id,location_key)
select coalesce(a.product_id,e.product_id) product_id,coalesce(a.location_key,e.location_key) location_key,
 coalesce(a.quantity,0) inventory_quantity,coalesce(e.quantity,0) observed_quantity,coalesce(a.quantity,0)-coalesce(e.quantity,0) difference
from actual a full join evidence e using(product_id,location_key) where coalesce(a.quantity,0)<>coalesce(e.quantity,0);
-- Known observation-versus-movement differences: independently recorded stock
-- deltas reveal missing/duplicate/unlinked movement effects without fixing them.
with deltas as(select product_id,location_key,sum(delta) actual_net,sum(greatest(delta,0)) actual_inbound,sum(greatest(-delta,0)) actual_outbound from public.stock_history_inventory_changes group by product_id,location_key),
 movements as(select m.product_id,x.location_key,sum(e.effect) movement_net,sum(greatest(e.effect,0)) movement_inbound,sum(greatest(-e.effect,0)) movement_outbound
 from public.stock_movements m cross join public.stock_history_observation o
 cross join lateral(values('store:'||m.from_store_id),('store:'||m.to_store_id),('warehouse:'||m.from_warehouse_id),('warehouse:'||m.to_warehouse_id)) x(location_key)
 cross join lateral(select public.stock_history_effect(m.id,x.location_key) effect) e
 where coalesce(m.stock_history_recorded_at,m.created_at)>=o.started_at and x.location_key is not null group by m.product_id,x.location_key)
select coalesce(d.product_id,m.product_id) product_id,coalesce(d.location_key,m.location_key) location_key,coalesce(d.actual_net,0) actual_net,coalesce(m.movement_net,0) movement_net,
 coalesce(d.actual_inbound,0) actual_inbound,coalesce(m.movement_inbound,0) movement_inbound,coalesce(d.actual_outbound,0) actual_outbound,coalesce(m.movement_outbound,0) movement_outbound
from deltas d full join movements m using(product_id,location_key) where coalesce(d.actual_net,0)<>coalesce(m.movement_net,0)
 or coalesce(d.actual_inbound,0)<>coalesce(m.movement_inbound,0) or coalesce(d.actual_outbound,0)<>coalesce(m.movement_outbound,0);
select r.id transfer_id,l.id line_id,l.product_id,l.approved_quantity,l.received_quantity,l.discrepancy_quantity,l.discrepancy_reason
from public.transfer_requests r join public.transfer_request_lines l on l.transfer_request_id=r.id
where coalesce(l.discrepancy_quantity,0)<>0 and l.discrepancy_resolved_at is null;
select id movement_id,product_id,movement_type,created_at,transfer_request_id,transfer_request_line_id,reversed_sale_id,
 case when movement_type in ('transfer_dispatch','transfer_receipt','transfer_discrepancy') then 'Transfer effect has no exact transfer/line link'
 else 'Historical stock return has no original sale link; verify actual sellable quantities' end reason
from public.stock_movements where (movement_type in ('transfer_dispatch','transfer_receipt','transfer_discrepancy') and (transfer_request_id is null or transfer_request_line_id is null))
 or (movement_type in ('invoice_cancel_return','invoice_refund_return') and reversed_sale_id is null);
select transfer_request_line_id,movement_type,from_store_id,from_warehouse_id,count(*) records,array_agg(id order by created_at,id) movement_ids
from public.stock_movements where transfer_request_line_id is not null and movement_type in ('transfer_dispatch','transfer_receipt')
group by transfer_request_line_id,movement_type,from_store_id,from_warehouse_id having count(*)>1;
rollback;
