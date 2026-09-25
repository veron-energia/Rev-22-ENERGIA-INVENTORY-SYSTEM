-- Every invoice line has a name, on screen and in print (354).
--
-- Before 354, 30 production invoices had at least one blank item name: therapy
-- lines printed a dash, rental and special-product lines showed '—' everywhere,
-- and a voucher or product soft-deleted after the sale went blank, because the
-- page resolved names from active-only catalogue lists and three separately
-- written name functions each covered a different set of line kinds.
--
-- T3 is the one that matters most. It switches to the real `authenticated`
-- role, confirms row-level security genuinely hides the deleted voucher and
-- promotion from a staff member, and only THEN checks the names still resolve.
-- A test run as the superuser would pass whether or not that worked.
--
-- T6 guards the backfill: naming a line must never touch stock components.
--
-- T8 and T9 are the round-2 regressions. T8: a therapy session edited into an
-- unlimited package (same invoice line) keeps the session's name snapshot on
-- the row, and the package name must still win everywhere, and the reverse.
-- T9: lines written before 354 (no item_name_snapshot) of kind therapy, rental
-- and special_product show their names, not their kind, in the refund/cancel
-- dialog and the stock-review label, for a staff member too.
--
-- Codes, SKUs, e-mails and the phone carry a per-run suffix, so a concurrent
-- run on a shared database never waits on the same unique key.
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

-- Every name a line can show: its snapshot, the catalogue fallback, the page
-- (invoice_display_names), the refund/cancel dialog and the stock-review label.
create function pg_temp.line_names(p_item uuid) returns jsonb language sql as $f$
  select jsonb_build_object(
    'kind', li.line_kind::text,
    'snapshot', li.item_name_snapshot,
    'catalogue', public.invoice_item_catalogue_name(li),
    'display', public.invoice_display_names(li.invoice_id)->'lines'->>(li.id::text),
    'refund', (select y->>'name' from jsonb_array_elements(public.invoice_refund_options_before_sessions(li.invoice_id)->'lines') y
                where y->>'invoice_item_id' = li.id::text),
    'label', public.invoice_line_label(li.id))
  from public.invoice_items li where li.id = p_item
$f$;

do $$
declare o uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid(); mgr uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; pa uuid; pb uuid; v uuid;
 promo uuid; child uuid; svc uuid; sp uuid; wh uuid; cpk uuid; bnd uuid;
 inv uuid; inv2 uuid; inv3 uuid; inv4 uuid; it uuid; x jsonb; r jsonb; n int; comps_before bigint; comps_after bigint; t text;
 sfx text:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
 tp uuid; pkg text; inv5 uuid; inv6 uuid; ev jsonb;
begin
 insert into auth.users(id,email) values(o,'names-owner-'||lower(sfx)||'@tests.invalid'),(stf,'names-staff-'||lower(sfx)||'@tests.invalid'),(mgr,'names-mgr-'||lower(sfx)||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values(mgr,'Names Leaver','names-mgr-'||lower(sfx)||'@tests.invalid','manager');
 insert into profiles(id,full_name,email,role) values(o,'Names Owner','names-owner-'||lower(sfx)||'@tests.invalid','owner');
 insert into profiles(id,full_name,email,role) values(stf,'Names Staff','names-staff-'||lower(sfx)||'@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Names Store','NMS'||sfx,'SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(stf,st);
 insert into customers(full_name,phone) values('Names Buyer','+6591'||lpad(floor(random()*1000000)::int::text,6,'0')) returning id into c;
 insert into payment_methods(name) values('Names Cash') returning id into pm;
 insert into products(name,sku,product_type) values('Product A','NM-A-'||sfx,'own') returning id into pa;
 insert into products(name,sku,product_type) values('Product B','NM-B-'||sfx,'own') returning id into pb;
 insert into store_inventory(store_id,product_id,current_qty) values(st,pa,100),(st,pb,100);
 perform set_product_prices(st,pa,100,100,'available');
 perform set_product_prices(st,pb,100,100,'available');
 insert into vouchers(name,code,qty_type) values('Names Voucher','NM-V-'||sfx,'limited') returning id into v;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v,st,100);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,st,20,true);
 insert into promotions(name,code) values('Child Promo','NM-CH-'||sfx) returning id into child;
 insert into promotions(name,code) values('Parent Promo','NM-PR-'||sfx) returning id into promo;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(promo,'product',pa,1);
 insert into promotion_items(promotion_id,item_type,voucher_id,quantity) values(promo,'voucher',v,1);
 insert into promotion_items(promotion_id,item_type,child_promotion_id,quantity) values(promo,'promotion',child,1);
 insert into promotion_store_prices(promotion_id,store_id,selling_price) values(promo,st,150);
 svc:=(upsert_therapy_service(null,'NM-S-'||sfx,'Names Session',60,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);
 insert into warehouses(name,code) values('Names WH','NMW'||sfx) returning id into wh;
 insert into special_products(name,sku,sale_price,rate_day,is_active) values('Names Mat','NM-M-'||sfx,200,20,true) returning id into sp;
 insert into special_product_stock(special_product_id,warehouse_id,current_qty) values(sp,wh,5);
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy) values('Names Credit 500',500,500,true,true) returning id into cpk;
 insert into credit_package_stores(package_id,store_id) values(cpk,st);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,free_voucher_qty,grants_reward) values('Names Bundle',140,100,0,false) returning id into bnd;
 insert into premium_bundle_stores(bundle_id,store_id) values(bnd,st);

 -- T1: every line kind is named at the moment it is written.
 perform set_config('request.jwt.claim.sub',mgr::text,true);   -- the invoice is raised by a manager who later leaves
 inv:=create_invoice(st, c, null::uuid, jsonb_build_array(
   jsonb_build_object('kind','product','product_id',pa,'quantity',1),
   jsonb_build_object('kind','voucher','voucher_id',v,'quantity',1),
   jsonb_build_object('kind','promotion','promotion_id',promo,'quantity',1),
   jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1),
   jsonb_build_object('kind','special_product','special_product_id',sp,'quantity',1),
   jsonb_build_object('kind','rental','special_product_id',sp,'quantity',1,'rental_rate_type','day','rental_periods',3)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
 inv2:=create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cpk,'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
 inv3:=create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',bnd,'quantity',1,'voucher_selection','[]'::jsonb)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
 select string_agg(line_kind::text||'='||coalesce(item_name_snapshot,'<NULL>'), ', ' order by line_kind::text) into t
   from (select line_kind,item_name_snapshot from invoice_items where invoice_id in (inv,inv2,inv3)) q;
 raise notice 'T1 snapshots: %', t;
 if exists(select 1 from invoice_items where invoice_id in (inv,inv2,inv3) and coalesce(item_name_snapshot,'')='') then
   raise exception 'FAIL T1: a line was written without a name'; end if;
 if (select item_name_snapshot from invoice_items where invoice_id=inv and line_kind='therapy') <>
    (select therapy_service_name_snapshot from invoice_items where invoice_id=inv and line_kind='therapy') then
   raise exception 'FAIL T1: therapy name differs from its existing snapshot'; end if;
 raise notice 'PASS T1: all 8 line kinds carry a name when written';

 -- T2: renaming / deleting catalogue records after the sale does not blank or rename the invoice.
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',(select total_amount from invoices where id=inv))));
 update products set name='Product A (renamed)' where id=pa;
 update vouchers set is_active=false, deleted_at=now() where id=v;
 update promotions set is_active=false, deleted_at=now() where id=child;
 perform set_config('request.jwt.claim.sub',o::text,true);
 update profiles set is_active=false where id=mgr;                 -- the creator leaves
 if (select item_name_snapshot from invoice_items where invoice_id=inv and line_kind='product')<>'Product A' then
   raise exception 'FAIL T2: rename reached a sold line'; end if;
 raise notice 'PASS T2: sold line keeps "Product A" after the product is renamed';

 -- T3: a staff member at the store sees every name, although RLS hides the deleted records.
 insert into invoice_service_staff(invoice_id,staff_id) values(inv,mgr) on conflict do nothing;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 execute 'set local role authenticated';
 select count(*) into n from vouchers where id=v;
 if n<>0 then raise exception 'setup: expected RLS to hide the deleted voucher from staff'; end if;
 select count(*) into n from promotions where id=child;
 if n<>0 then raise exception 'setup: expected RLS to hide the deleted promotion from staff'; end if;
 r:=invoice_display_names(inv);
 execute 'reset role';
 raise notice 'T3 names as staff: %', r;
 if r->'lines'->>((select id from invoice_items where invoice_id=inv and line_kind='voucher')::text) <> 'Names Voucher'
   or r->'names'->>(v::text) <> 'Names Voucher' or r->'names'->>(child::text) <> 'Child Promo'
   or r->>'created_by_name' <> 'Names Leaver' or (r->'service_staff'->0->>'name') <> 'Names Leaver'
   or r->'names'->>(pm::text) <> 'Names Cash' or r->>'customer_name' <> 'Names Buyer' then
   raise exception 'FAIL T3: %', r; end if;
 raise notice 'PASS T3: staff see deleted voucher/child promotion, inactive creator and server-resolved method/customer names; direct SELECT returns 0 rows under RLS';

 -- T4: a staff member from ANOTHER store cannot read names of this invoice.
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Other Store','NMO'||sfx,'SG') returning id into wh;
 delete from user_store_assignments where user_id=stf; insert into user_store_assignments(user_id,store_id) values(stf,wh);
 perform set_config('request.jwt.claim.sub',stf::text,true);
 begin perform invoice_display_names(inv); raise exception 'FAIL T4: other-store staff read names';
 exception when others then if sqlerrm not like '%not accessible%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',o::text,true);
 raise notice 'PASS T4: store access enforced';

 -- T5: a correction that swaps the item renames the line; an untouched line keeps its name.
 inv4:=create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','product','product_id',pb,'quantity',1),
   jsonb_build_object('kind','product','product_id',pa,'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
 select id into it from invoice_items where invoice_id=inv4 and product_id=pa;
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',pa,'quantity',1),
   jsonb_build_object('kind','product','product_id',pb,'quantity',2));
 perform correct_invoice(inv4,x,'{}','Swap line',gen_random_uuid());
 if (select item_name_snapshot from invoice_items where id=it) <> 'Product A (renamed)' then
   raise exception 'FAIL T5: kept line lost its name: %',(select item_name_snapshot from invoice_items where id=it); end if;
 if (select item_name_snapshot from invoice_items where invoice_id=inv4 and product_id=pb) <> 'Product B' then
   raise exception 'FAIL T5: new line not named'; end if;
 update invoice_items set product_id=pb where id=it;
 if (select item_name_snapshot from invoice_items where id=it) <> 'Product B' then raise exception 'FAIL T5: in-place swap kept stale name'; end if;
 raise notice 'PASS T5: correction names new lines, in-place item swap renames, untouched line kept';

 -- T6: backfill of legacy rows is name-only: no stock component or other row changes.
 update invoice_items set item_name_snapshot=null where invoice_id in (inv,inv2,inv3);  -- refs unchanged => trigger keeps NULL
 if exists(select 1 from invoice_items where invoice_id in (inv,inv2,inv3) and item_name_snapshot is not null) then
   raise exception 'FAIL T6 setup: trigger overwrote an explicit null on an unchanged row'; end if;
 select count(*)+coalesce(sum(quantity),0) into comps_before from invoice_stock_components;
 update invoice_items li set item_name_snapshot=invoice_item_catalogue_name(li) where li.item_name_snapshot is null and li.invoice_id in (inv,inv2,inv3);
 select count(*)+coalesce(sum(quantity),0) into comps_after from invoice_stock_components;
 if comps_before<>comps_after then raise exception 'FAIL T6: backfill touched stock components % -> %',comps_before,comps_after; end if;
 if exists(select 1 from invoice_items where invoice_id in (inv,inv2,inv3) and coalesce(item_name_snapshot,'')='') then raise exception 'FAIL T6: backfill left a blank'; end if;
 if (select item_name_snapshot from invoice_items where invoice_id=inv and line_kind='voucher')<>'Names Voucher' then raise exception 'FAIL T6: deleted voucher not recovered'; end if;
 raise notice 'PASS T6: backfill recovers deleted-record names and leaves stock components (% ) untouched', comps_after;

 -- T7: not callable by anon; trigger helpers not callable by clients.
 if has_function_privilege('anon','public.invoice_display_names(uuid)','execute') then raise exception 'FAIL T7 anon'; end if;
 if has_function_privilege('authenticated','public.invoice_item_catalogue_name(public.invoice_items)','execute') then raise exception 'FAIL T7 helper'; end if;
 raise notice 'PASS T7: grants';

 -- T8 (354, round 2): on an UNPAID invoice a therapy SESSION line is edited
 -- in correct_invoice, keeping its invoice_item_id, into an unlimited therapy
 -- PACKAGE. The update leaves the session's therapy_service_name_snapshot on
 -- the row; the package name must win in item_name_snapshot, on the page
 -- (invoice_display_names) and in the refund/cancel dialog
 -- (invoice_refund_options_before_sessions) -- and still win when the line
 -- has no item_name_snapshot, as a line written before 354. Then back again:
 -- the package's plan_name_snapshot stays behind and the session name wins.
 insert into unlimited_therapy_packages(name,duration_months,is_active,entitlement_kind)
   values('Names 6 Month '||sfx,6,true,'unlimited') returning id into tp;
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store) values(tp,st,600,true);
 pkg:='Names 6 Month '||sfx;
 inv5:=create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)),
   0::numeric, null::text, null::uuid, '[]'::jsonb);
 select id into it from invoice_items where invoice_id=inv5;
 if (select item_name_snapshot from invoice_items where id=it) is distinct from 'Names Session' then
   raise exception 'FAIL T8 setup: the session line was not written as "Names Session": %', pg_temp.line_names(it); end if;
 perform correct_invoice(inv5, jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','therapy','therapy_package_id',tp,'quantity',1)),
   '{}'::jsonb, 'Session edited into a package', gen_random_uuid());
 if (select count(*) from invoice_items where invoice_id=inv5)<>1
    or not exists(select 1 from invoice_items where id=it and therapy_package_id=tp and therapy_service_id is null)
    or (select status::text from invoices where id=inv5)<>'unpaid'
    or exists(select 1 from invoice_payments where invoice_id=inv5) then
   raise exception 'FAIL T8 setup: the line was not edited in place into the package on an unpaid invoice'; end if;
 raise notice 'T8 the edited line still carries therapy_service_name_snapshot=%',
   (select coalesce(therapy_service_name_snapshot,'<NULL>') from invoice_items where id=it);
 r:=pg_temp.line_names(it);
 if r->>'snapshot' is distinct from pkg or r->>'catalogue' is distinct from pkg or r->>'display' is distinct from pkg
    or r->>'refund' is distinct from pkg or r->>'label' is distinct from pkg then
   raise exception 'FAIL T8: a session edited into a package is not named "%" everywhere: %', pkg, r; end if;
 update invoice_items set item_name_snapshot=null where id=it;          -- as a line written before 354
 r:=pg_temp.line_names(it);
 if r->>'snapshot' is not null then raise exception 'FAIL T8 setup: the snapshot could not be cleared'; end if;
 if r->>'catalogue' is distinct from pkg or r->>'display' is distinct from pkg
    or r->>'refund' is distinct from pkg or r->>'label' is distinct from pkg then
   raise exception 'FAIL T8: without a snapshot the package line is not named "%" everywhere: %', pkg, r; end if;
 perform correct_invoice(inv5, jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','therapy','therapy_service_id',svc,'quantity',1)),
   '{}'::jsonb, 'Package edited back into a session', gen_random_uuid());
 if not exists(select 1 from invoice_items where id=it and invoice_id=inv5 and therapy_service_id=svc and therapy_package_id is null) then
   raise exception 'FAIL T8 setup: the line was not edited in place back into the session'; end if;
 r:=pg_temp.line_names(it);
 if r->>'snapshot' is distinct from 'Names Session' or r->>'catalogue' is distinct from 'Names Session'
    or r->>'display' is distinct from 'Names Session' or r->>'refund' is distinct from 'Names Session'
    or r->>'label' is distinct from 'Names Session' then
   raise exception 'FAIL T8: a package edited back into a session is not named "Names Session" everywhere: %', r; end if;
 update invoice_items set item_name_snapshot=null where id=it;
 r:=pg_temp.line_names(it);
 if r->>'catalogue' is distinct from 'Names Session' or r->>'display' is distinct from 'Names Session'
    or r->>'refund' is distinct from 'Names Session' or r->>'label' is distinct from 'Names Session' then
   raise exception 'FAIL T8: without a snapshot the line edited back is not named "Names Session" everywhere: %', r; end if;
 raise notice 'PASS T8: a session edited into a package (same line, unpaid) shows the package name in item_name_snapshot, invoice_display_names, the refund options and the label, with or without a snapshot; and back again';

 -- T9 (354, round 2): lines written before 354 carry no item_name_snapshot.
 -- A therapy session, a special product and a rental must show their NAMES,
 -- not "therapy" / "special_product" / "rental", in the refund/cancel dialog
 -- (invoice_refund_options_before_sessions) and the stock-review label
 -- (invoice_line_label) -- also once the session and the mat are deactivated,
 -- and also for a staff member through the client entry points
 -- (invoice_refund_options, invoice_stock_component_evidence).
 inv6:=create_invoice(st, c, null::uuid, jsonb_build_array(
   jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1),
   jsonb_build_object('kind','special_product','special_product_id',sp,'quantity',1),
   jsonb_build_object('kind','rental','special_product_id',sp,'quantity',1,'rental_rate_type','day','rental_periods',2)),
   0::numeric, null::text, null::uuid, '[]'::jsonb);
 update invoice_items set item_name_snapshot=null where invoice_id=inv6;  -- refs unchanged => the trigger keeps NULL
 if (select count(*) from invoice_items where invoice_id=inv6 and item_name_snapshot is null
       and line_kind::text in ('therapy','special_product','rental'))<>3
    or exists(select 1 from invoice_items where invoice_id=inv6 and item_name_snapshot is not null) then
   raise exception 'FAIL T9 setup: expected three pre-354 lines without a snapshot'; end if;
 update therapy_services set is_active=false where id=svc;
 update special_products set is_active=false where id=sp;
 select string_agg(q.nm::text, '; ') into t
   from (select pg_temp.line_names(li.id) nm,
                case li.line_kind::text when 'therapy' then 'Names Session' else 'Names Mat' end want
           from invoice_items li where li.invoice_id=inv6) q
  where q.nm->>'refund' is distinct from q.want or q.nm->>'label' is distinct from q.want
     or q.nm->>'display' is distinct from q.want;
 if t is not null then raise exception 'FAIL T9: a pre-354 line is not named by its item: %', t; end if;
 -- The same, as a staff member at the store, through what the page calls.
 insert into user_store_assignments(user_id,store_id) values(stf,st) on conflict do nothing;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 execute 'set local role authenticated';
 r:=invoice_refund_options(inv6);
 select jsonb_object_agg(e.invoice_item_id::text, e.description) into ev from invoice_stock_component_evidence(inv6) e;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',o::text,true);
 select string_agg(li.line_kind::text||': refund='||coalesce(y.value->>'name','<none>')||', evidence='||coalesce(ev->>(li.id::text),'<none>'), '; ') into t
   from invoice_items li
   left join lateral (select z.value from jsonb_array_elements(r->'lines') z where z.value->>'invoice_item_id'=li.id::text) y on true
  where li.invoice_id=inv6
    and (y.value->>'name' is distinct from case li.line_kind::text when 'therapy' then 'Names Session' else 'Names Mat' end
      or ev->>(li.id::text) is distinct from case li.line_kind::text when 'therapy' then 'Names Session' else 'Names Mat' end);
 if t is not null then raise exception 'FAIL T9 (staff): a pre-354 line is not named by its item: %', t; end if;
 raise notice 'PASS T9: pre-354 therapy, special-product and rental lines (no snapshot, catalogue item deactivated) are named, not labelled by kind, in the refund options and the line label, for staff too';

 raise notice 'PASS: every invoice line has a name on screen and in print, for staff too, and naming never touches stock.';
end $$;
rollback;

