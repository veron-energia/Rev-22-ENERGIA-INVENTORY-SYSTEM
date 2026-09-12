-- Sales counts money the business actually made and kept.
--
-- Reported: "refunded, cancelled and not paid invoices are in the sale."
-- Only one of the three was: a cancelled invoice kept contributing its receipts
-- forever, because cancel_invoice_recorded deliberately leaves payments in
-- place and invoice_sales_ledger() never looked at the invoice's status.
--
-- These assertions state the rule so it cannot silently come back. Money that
-- was voided leaves Sales; money genuinely kept never does.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; p uuid;
 inv uuid; it uuid; pay uuid; mv jsonb; req uuid; reqj jsonb; mvid uuid; d jsonb; n numeric;
begin
 insert into auth.users(id,email) values(o,'ss-owner@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','ss-owner@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('SS Store','SSS','SG') returning id into st;
 insert into customers(full_name,phone) values('SS Buyer','+6598008888') returning id into c;
 insert into payment_methods(name,is_active) values('SS Cash',true) returning id into pm;
 insert into products(name,sku,product_type) values('SS Item','SSI','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,500);
 perform set_product_prices(st,p,100,100,'available');

 -- An invoice nobody has paid was never in Sales to begin with. The report was
 -- believed to include these; it does not, and must not start to.
 inv:=create_invoice_with_details(st,c,
   jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date','2026-07-02'));
 n:=coalesce((select sum(amount) from invoice_sales_ledger() where invoice_id=inv),0);
 if n<>0 then raise exception 'An unpaid invoice must contribute nothing to Sales, got %',n; end if;

 -- Paid, then cancelled. The payment stays in history by design; the sale does not.
 inv:=create_invoice_with_details(st,c,
   jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date','2026-07-03'));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object(
   'payment_method_id',pm,'amount',100,'payment_date','2026-07-03')),gen_random_uuid());
 n:=coalesce((select sum(amount) from invoice_sales_ledger() where invoice_id=inv),0);
 if n<>100 then raise exception 'A paid invoice must contribute its receipts, got %',n; end if;
 perform cancel_invoice_recorded(inv,'Cancelled after payment',gen_random_uuid());
 n:=coalesce((select sum(amount) from invoice_sales_ledger() where invoice_id=inv),0);
 if n<>0 then raise exception 'A cancelled invoice must leave Sales, got %',n; end if;
 -- The payment itself is untouched: cancelling reports, it does not delete money.
 if not exists(select 1 from invoice_payments where invoice_id=inv) then
  raise exception 'Cancelling must not remove the payment record'; end if;
 -- and money kept on a cancelled invoice is surfaced rather than quietly lost.
 -- Scoped to this fixture's own store: the report covers every store the
 -- caller can see, and an owner can see them all.
 if (select coalesce(sum(retained),0) from report_cancelled_retained_receipts(st))<>100 then
  raise exception 'Money kept on a cancelled invoice must be reported'; end if;

 -- Fully refunded: gone from the month it was received as well as the refund
 -- month, so a cross-month refund cannot leave a bare negative behind.
 inv:=create_invoice_with_details(st,c,
   jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date','2026-07-04'));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object(
   'payment_method_id',pm,'amount',100,'payment_date','2026-07-04')),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;
 select jsonb_build_array(jsonb_build_object('movement_id',id,'sellable_quantity',1)) into mv
   from stock_movements where invoice_id=inv and movement_type='store_sale' limit 1;
 perform refund_invoice_recorded(inv,
   jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',100)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',100)),mv,
   'Full refund',gen_random_uuid());
 n:=coalesce((select sum(amount) from invoice_sales_ledger()
              where invoice_id=inv and sales_date between '2026-07-01' and '2026-07-31'),0);
 if n<>0 then raise exception 'A fully refunded invoice must leave the month it was received, got %',n; end if;
 n:=coalesce((select sum(amount) from invoice_sales_ledger() where invoice_id=inv),0);
 if n<>0 then raise exception 'A fully refunded invoice must be nil overall, got %',n; end if;

 -- A PARTIAL refund keeps status 'paid'. The money still held is still a sale;
 -- this is the case a blunt status filter would have destroyed.
 inv:=create_invoice_with_details(st,c,
   jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',4)),
   jsonb_build_object('business_date','2026-07-05'));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object(
   'payment_method_id',pm,'amount',400,'payment_date','2026-07-05')),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;
 select jsonb_build_array(jsonb_build_object('movement_id',id,'sellable_quantity',1)) into mv
   from stock_movements where invoice_id=inv and movement_type='store_sale' limit 1;
 perform refund_invoice_recorded(inv,
   jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',100)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',100)),mv,
   'Partial refund',gen_random_uuid());
 n:=coalesce((select sum(amount) from invoice_sales_ledger() where invoice_id=inv),0);
 if n<>300 then raise exception 'A partly refunded invoice must keep the money still held, got %',n; end if;

 -- Part paid counts for what was received.
 inv:=create_invoice_with_details(st,c,
   jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',2)),
   jsonb_build_object('business_date','2026-07-06'));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object(
   'payment_method_id',pm,'amount',60,'payment_date','2026-07-06')),gen_random_uuid());
 n:=coalesce((select sum(amount) from invoice_sales_ledger() where invoice_id=inv),0);
 if n<>60 then raise exception 'A partly paid invoice must contribute what was received, got %',n; end if;

 -- A REQUEST is not a decision. Asking to cancel must not move a month's sales,
 -- and refusing the request must not move them back.
 -- Raised through the guided workflow (295/296/297), which is the supported
 -- path; the legacy resolve_invoice_action no longer approves directly because
 -- it cannot collect the confirmed goods or an override reason.
 reqj:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Customer undecided',null,gen_random_uuid());
 n:=coalesce((select sum(amount) from invoice_sales_ledger() where invoice_id=inv),0);
 if n<>60 then raise exception 'A pending cancellation request must not change Sales, got %',n; end if;
 perform resolve_invoice_action_v2((reqj->>'request_id')::uuid,false,'Refused');
 n:=coalesce((select sum(amount) from invoice_sales_ledger() where invoice_id=inv),0);
 if n<>60 then raise exception 'A refused request must leave Sales untouched, got %',n; end if;
 -- Approving it is the decision, and that does remove the sale.
 reqj:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Confirmed',null,gen_random_uuid());
 select movement_id into mvid from jsonb_to_recordset(invoice_action_plan(inv,'cancel')->'stock') as t(movement_id uuid) limit 1;
 perform resolve_invoice_action_v2((reqj->>'request_id')::uuid,true,'Approved',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',mvid,'sellable_quantity',2,'damaged_quantity',0,'not_returned_quantity',0)),false);
 n:=coalesce((select sum(amount) from invoice_sales_ledger() where invoice_id=inv),0);
 if n<>0 then raise exception 'An approved cancellation must remove the sale, got %',n; end if;

 -- The tiles beside the sales figure follow it. A cancelled invoice must not
 -- leave its items and its discount behind in a month it no longer sells in.
 d:=dashboard_sales('custom','2026-07-01','2026-07-31',st);
 -- 400 received in July. The partial refund is NOT deducted here: a refund
 -- belongs to the day it was given, which is why the 300 checked above is the
 -- all-time figure and July still shows the full receipt.
 if (d->>'sales')::numeric<>400 then
  raise exception 'July sales must be the 400 received that month, got %',d->>'sales'; end if;
 if (d->>'items_sold')::numeric<>4 then
  raise exception 'July items must come only from invoices still counted as sales, got %',d->>'items_sold'; end if;
 if (d->>'invoice_count')::int<>1 then
  raise exception 'July must count one selling invoice, got %',d->>'invoice_count'; end if;

 -- The refund reduces the month it was actually given, and nothing else in
 -- that month is disturbed by the cancellations above.
 d:=dashboard_sales('custom',(sg_today()-1),(sg_today()+1),st);
 if (d->>'sales')::numeric<>-100 then
  raise exception 'The refund must reduce the month it was given, got %',d->>'sales'; end if;

 raise notice 'Sales counts only invoices whose money is a sale.';
end $$;
rollback;
