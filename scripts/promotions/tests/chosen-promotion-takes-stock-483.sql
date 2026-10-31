-- A promotion picked in a choice group takes its products out of stock (483).
--
-- A blind box is a promotion whose one choice group offers promotions (its
-- prizes). 349 records which prize was picked; before 483 nothing turned that
-- pick into stock components, so paying for a box took nothing out of stock,
-- and the refund plan had no sale to give back. This sells, pays, refunds and
-- edits boxes through the app's own calls:
--   B1 a box with one prize, paid in full: the prize leaves the store, once
--   B2 its full refund lists the prize's stock and puts it back
--   B3 two boxes on one line, the prize picked twice: twice the stock
--   B4 a prize the store cannot cover: the payment is refused, nothing moves
--   B5 the prize changed on Edit Invoice before payment: the new prize is owed
--   B6 a product picked directly and inside the prize: owed once, summed
--
-- Disposable database only (a copy of production at 480 or later, with 483 not
-- yet applied or applied); everything is rolled back. From the repository root:
--   psql "$DB" -v ON_ERROR_STOP=1 -f scripts/promotions/tests/chosen-promotion-takes-stock-483.sql
\set ON_ERROR_STOP on
begin;
-- twice: the second run must leave it alone
\i supabase/483_chosen_promotion_takes_its_stock.sql
\i supabase/483_chosen_promotion_takes_its_stock.sql
do $$
declare
  own uuid := gen_random_uuid(); tag text := substr(md5(random()::text), 1, 6);
  st uuid; c uuid; pm uuid; corset uuid; knee uuid; socks uuid;
  pa uuid; pb uuid; box uuid; g uuid; box2 uuid; g2 uuid; gp uuid;
  inv uuid; plan jsonb; stock jsonb; req jsonb; res jsonb; n int; v text; v_msg text;
begin
  insert into auth.users(id,email) values (own,'cpt-'||tag||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'CPT Owner','cpt-'||tag||'@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into stores(name,code,country_code) values ('CPT '||tag,'CPT'||tag,'SG') returning id into st;
  insert into customers(full_name,phone)
    values ('CPT Buyer','+6598'||lpad((floor(random()*900000)+100000)::int::text,6,'0')) returning id into c;
  insert into payment_methods(name) values ('CPT Cash '||tag) returning id into pm;
  insert into products(name,sku,product_type) values ('CPT Corset','CPT-1-'||tag,'own') returning id into corset;
  insert into products(name,sku,product_type) values ('CPT Knee Brace','CPT-2-'||tag,'own') returning id into knee;
  insert into products(name,sku,product_type) values ('CPT Socks','CPT-3-'||tag,'own') returning id into socks;
  insert into store_inventory(store_id,product_id,current_qty) values (st,corset,10),(st,knee,10),(st,socks,1);

  -- The prizes, as the real boxes hold them, and the box offering them.
  insert into promotions(name,code) values ('CPT Corset + Knee Brace','CPT-A-'||tag) returning id into pa;
  insert into promotion_items(promotion_id,item_type,product_id,quantity) values (pa,'product',corset,1),(pa,'product',knee,1);
  insert into promotions(name,code) values ('CPT Socks x 2','CPT-B-'||tag) returning id into pb;
  insert into promotion_items(promotion_id,item_type,product_id,quantity) values (pb,'product',socks,2);
  insert into promotions(name,code) values ('CPT Blind Box','CPT-X-'||tag) returning id into box;
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (box,'Choose your blind box products','promotion',1) returning id into g;
  insert into promotion_choice_options(group_id,child_promotion_id) values (g,pa),(g,pb);
  perform set_promotion_prices(box, st, 500, 500, true);

  -- ---- B1: a box with prize A, paid in full ------------------------------------
  inv := create_invoice(st, c, null, jsonb_build_array(jsonb_build_object(
    'kind','promotion','promotion_id',box,'quantity',1,
    'selections', jsonb_build_array(jsonb_build_object('group_id', g,
      'options', jsonb_build_array(jsonb_build_object('child_promotion_id', pa, 'quantity', 1)))))));
  select string_agg(p.name||' '||r.quantity, ', ' order by p.name) into v
    from invoice_required_stock(inv) r join products p on p.id = r.item_id where r.kind = 'product';
  if v is distinct from 'CPT Corset 1, CPT Knee Brace 1' then
    raise exception 'FAIL B1: before payment the box owes % (wanted CPT Corset 1, CPT Knee Brace 1)', coalesce(v,'nothing'); end if;
  if exists (select 1 from stock_movements where invoice_id = inv) then
    raise exception 'FAIL B1: stock moved before the box was paid'; end if;
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then
    raise exception 'FAIL B1: the box is % after paying it in full', (select status from invoices where id = inv); end if;
  select string_agg(p.name||' '||si.current_qty, ', ' order by p.name) into v
    from store_inventory si join products p on p.id = si.product_id where si.store_id = st;
  if v is distinct from 'CPT Corset 9, CPT Knee Brace 9, CPT Socks 1' then
    raise exception 'FAIL B1: after payment the store holds % (wanted CPT Corset 9, CPT Knee Brace 9, CPT Socks 1)', v; end if;
  select count(*) into n from stock_movements where invoice_id = inv and movement_type::text = 'store_sale';
  if n <> 2 then raise exception 'FAIL B1: % sale movements for the box, wanted 2', n; end if;

  -- ---- B2: its full refund lists the prize's stock and puts it back ----------------
  plan := invoice_action_plan(inv,'refund_full');
  if jsonb_array_length(coalesce(plan->'stock','[]'::jsonb)) <> 2 then
    raise exception 'FAIL B2: the refund plan lists % stock rows for a box that took 2: %', jsonb_array_length(coalesce(plan->'stock','[]'::jsonb)), plan->'stock'; end if;
  select jsonb_agg(jsonb_build_object('movement_id',s->>'movement_id',
           'sellable_quantity',(s->>'proposed_sellable')::int,'damaged_quantity',0,'not_returned_quantity',0))
    into stock from jsonb_array_elements(plan->'stock') s;
  req := request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Changed her mind',null,gen_random_uuid());
  res := resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',null,'[]'::jsonb,stock,false);
  if res->>'status' <> 'approved' then raise exception 'FAIL B2: the box''s refund was not approved: %', res; end if;
  select string_agg(p.name||' '||si.current_qty, ', ' order by p.name) into v
    from store_inventory si join products p on p.id = si.product_id where si.store_id = st;
  if v is distinct from 'CPT Corset 10, CPT Knee Brace 10, CPT Socks 1' then
    raise exception 'FAIL B2: after the refund the store holds % (wanted CPT Corset 10, CPT Knee Brace 10, CPT Socks 1)', v; end if;

  -- ---- B3: two boxes on one line, prize A picked twice --------------------------
  inv := create_invoice(st, c, null, jsonb_build_array(jsonb_build_object(
    'kind','promotion','promotion_id',box,'quantity',2,
    'selections', jsonb_build_array(jsonb_build_object('group_id', g,
      'options', jsonb_build_array(jsonb_build_object('child_promotion_id', pa, 'quantity', 2)))))));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)), gen_random_uuid());
  select string_agg(p.name||' '||si.current_qty, ', ' order by p.name) into v
    from store_inventory si join products p on p.id = si.product_id where si.store_id = st;
  if v is distinct from 'CPT Corset 8, CPT Knee Brace 8, CPT Socks 1' then
    raise exception 'FAIL B3: after two boxes the store holds % (wanted CPT Corset 8, CPT Knee Brace 8, CPT Socks 1)', v; end if;

  -- ---- B4: a prize the store cannot cover: the payment is refused ----------------
  inv := create_invoice(st, c, null, jsonb_build_array(jsonb_build_object(
    'kind','promotion','promotion_id',box,'quantity',1,
    'selections', jsonb_build_array(jsonb_build_object('group_id', g,
      'options', jsonb_build_array(jsonb_build_object('child_promotion_id', pb, 'quantity', 1)))))));
  begin
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)), gen_random_uuid());
    raise exception 'FAIL B4: a box whose prize needs 2 socks was paid with 1 sock in the store';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL%' then raise; end if;
    if v_msg !~ 'Insufficient store stock for CPT Socks \(have 1, need 2' then
      raise exception 'FAIL B4: the payment was refused for another reason: %', v_msg; end if;
  end;
  if (select status::text from invoices where id = inv) = 'paid'
     or exists (select 1 from stock_movements where invoice_id = inv)
     or (select current_qty from store_inventory where store_id = st and product_id = socks) <> 1 then
    raise exception 'FAIL B4: the refused payment left the box paid or moved stock'; end if;

  -- ---- B5: the prize changed on Edit Invoice before payment -----------------------
  perform correct_invoice(inv, jsonb_build_array(jsonb_build_object(
    'kind','promotion','promotion_id',box,'quantity',1,
    'selections', jsonb_build_array(jsonb_build_object('group_id', g,
      'options', jsonb_build_array(jsonb_build_object('child_promotion_id', pa, 'quantity', 1)))))),
    '{}'::jsonb, 'Keyed the wrong prize', gen_random_uuid());
  select string_agg(p.name||' '||r.quantity, ', ' order by p.name) into v
    from invoice_required_stock(inv) r join products p on p.id = r.item_id where r.kind = 'product';
  if v is distinct from 'CPT Corset 1, CPT Knee Brace 1' then
    raise exception 'FAIL B5: after changing the prize to A the box owes % (wanted CPT Corset 1, CPT Knee Brace 1)', coalesce(v,'nothing'); end if;
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)), gen_random_uuid());
  select string_agg(p.name||' '||si.current_qty, ', ' order by p.name) into v
    from store_inventory si join products p on p.id = si.product_id where si.store_id = st;
  if v is distinct from 'CPT Corset 7, CPT Knee Brace 7, CPT Socks 1' then
    raise exception 'FAIL B5: after paying the edited box the store holds % (wanted CPT Corset 7, CPT Knee Brace 7, CPT Socks 1)', v; end if;

  -- ---- B6: a product picked directly and inside the prize ------------------------
  insert into promotions(name,code) values ('CPT Box With Extra','CPT-Y-'||tag) returning id into box2;
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (box2,'Choose your prize','promotion',1) returning id into g2;
  insert into promotion_choice_options(group_id,child_promotion_id) values (g2,pa);
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (box2,'Choose an extra','product',1) returning id into gp;
  insert into promotion_choice_options(group_id,product_id) values (gp,corset);
  perform set_promotion_prices(box2, st, 600, 600, true);
  perform set_product_prices(st, corset, 468, 468, 'available');
  inv := create_invoice(st, c, null, jsonb_build_array(jsonb_build_object(
    'kind','promotion','promotion_id',box2,'quantity',1,
    'selections', jsonb_build_array(
      jsonb_build_object('group_id', g2, 'options', jsonb_build_array(jsonb_build_object('child_promotion_id', pa, 'quantity', 1))),
      jsonb_build_object('group_id', gp, 'options', jsonb_build_array(jsonb_build_object('product_id', corset, 'quantity', 1)))))));
  select string_agg(p.name||' '||c2.quantity||' '||c2.component_source, ', ' order by p.name) into v
    from invoice_stock_components c2 join invoice_items it on it.id = c2.invoice_item_id join products p on p.id = c2.item_id
   where it.invoice_id = inv;
  if v is distinct from 'CPT Corset 2 selection, CPT Knee Brace 1 selection' then
    raise exception 'FAIL B6: the components are % (wanted CPT Corset 2 selection, CPT Knee Brace 1 selection)', coalesce(v,'none'); end if;

  raise notice 'PASS: a blind box''s prize is owed from the sale, leaves the store once when the box is paid (twice for two boxes), comes back on a full refund, is refused when the store cannot cover it, follows a prize changed on Edit Invoice, and is summed with the same product picked directly';
end $$;
rollback;
