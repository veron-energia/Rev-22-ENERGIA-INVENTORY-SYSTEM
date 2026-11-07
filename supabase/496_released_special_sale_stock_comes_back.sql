-- 496_released_special_sale_stock_comes_back.sql
--
-- A REFUND OR A CANCELLATION OF A SPECIAL SALE ALREADY RELEASED FROM A WAREHOUSE OR A
-- STORE ASKS WHAT CAME BACK, AND PUTS WHAT IS SELLABLE BACK WHERE IT LEFT
-- (the user, 6 Nov 2026: "yes, build it as its own change", to the finding below)
--
-- (The number 496 is this file's name, its errors' prefix, its self-test's error code
-- P0496, its suite's and its UNDO's; if it changes at commit, change it in these places
-- alone. 495, services hold no stock, went live on 6 Nov 2026 while this was being
-- finished, and patches refund_invoice_recorded too: see "WITH 495" below.)
--
-- WHAT WAS WRONG
--
--   Releasing a special sale from "Waiting for a warehouse" (fulfil_special_doc) takes its
--   unit out of a warehouse or a store and writes a stock movement that no invoice owns.
--   Everything that asks about stock when an invoice is refunded or cancelled starts from
--   the movements an invoice owns, and only for product and promotion lines. So a released
--   special sale was never asked about: a full refund, a part refund and a cancellation all
--   left its unit out of stock, whatever became of it, with nobody told. The Special page
--   went on saying "Released". And the refund's stock-return code could only put stock back
--   into a store, never a warehouse, where every released sale so far came from.
--   Found 6 Nov 2026 by reading, then run on copies of production (a full and a part refund,
--   a cancellation, a store release, an invoice of a special sale and a product).
--   Production, 6 Nov 2026, read only: 11 special sales, 8 released (all from a warehouse,
--   SPS-2026-0004 to 0011), none of them refunded or cancelled, so no stock figure is wrong
--   yet. The 3 sales on refunded invoices were still waiting and were cancelled (393), so
--   nothing had left.
--
-- WHAT THIS DOES
--
--   1. special_sales.release_movement_id (new): the stock movement that took the sale's
--      unit out. fulfil_special_doc sets it as it releases (it now learns the new
--      movement's id). A sale released before this is linked once, below
--      (link_released_special_movements), only where the movement's note, product,
--      quantity and shelf match that one sale and no other; it links, and changes no
--      quantity and no stock figure.
--   2. special_sale_returns (new table): for each released unit, what a refund or a
--      cancellation settled: sellable, damaged or not returned, who confirmed it, why, and
--      the movement written for the sellable ones. Staff read it for their stores (the rule
--      of invoice_stock_dispositions); it is written by the functions below alone.
--   3. The refund screens are offered the units. invoice_refund_options adds one row per
--      released unit of the invoice's special sales to its "stock" list (a product's fields,
--      plus the sale, its line and the shelf it left); invoice_action_plan lists them for
--      a special sale line as it lists a product's: all of them for a cancellation or a
--      full refund, as many as the units refunded for a part refund (less a waiting unit
--      the staff said "no" to, which is a unit refunded first), by sale number ("Return
--      1 x X to <the warehouse or store>, once the condition is confirmed"). The pages need
--      no change: they show whatever the list holds, the shelf in store_name.
--   4. refund_invoice_recorded asks a special sale's line what a product's is asked: a
--      refund of it with released units nobody has settled must carry the answer ("Record
--      the returned-and-sellable, damaged, or not-returned quantities for this special sale
--      refund"). A refund that takes the whole line must answer for every unsettled unit
--      (once the invoice is refunded nothing can ask again); a part refund must answer for
--      at least one, unless what it refunds is a waiting unit of the line that the staff
--      said the customer is not taking; and every answer must be a unit of a line the
--      refund is for. Sellable units go back on the shelf they left
--      (return_released_special_stock; a shelf since deleted is refused), damaged and not
--      returned add nothing; every answer is recorded and in the Audit Log.
--   5. A cancellation: record_invoice_stock_return (the guided cancellation's confirmed
--      conditions) takes the same answers, and cancel_invoice_recorded puts back the
--      released units nobody has settled (restore_released_special_stock), as
--      restore_invoice_stock does a product's: those its plan lists, on the invoice's lines
--      as they are now, up to each line's quantity. A correction does not: it also calls
--      restore_invoice_stock, and a correction must never take a released unit back.
--   6. A sale whose unit is back in stock is over: cancelled, stock back, with the note
--      "Cancelled (refunded)" or "Cancelled (invoice cancelled)", which the Sales tab
--      already reads as "Cancelled (refunded) · stock back". An invoice reopened and paid
--      again raises it afresh (create_special_docs_for_invoice: a sale whose stock came
--      back no longer counts, one for one, even when other units of the line still count),
--      so it is released, and taken from stock, again.
--   7. Damaged or not returned: the sale stays "Released" (its unit did not come back to
--      the shelf); the answer is in special_sale_returns and the Audit Log.
--   8. fulfil_special_doc takes the invoice first, shared, as a refund takes it for update,
--      so a release and a refund of one invoice wait for one another: they no longer meet on
--      the stock row (a deadlock, now that a refund moves special stock), and a unit can no
--      longer be released between a refund's plan and its recording and be left unsettled.
--
-- WHAT IT DOES NOT CHANGE
--
--   * Money: refund amounts and sources, commission, vouchers, credit, therapy, Reports.
--   * A product line's stock rules (its question at a refund, restore_invoice_stock, the
--     invoice stock maths, the stock reports). No special sale's movement carries an
--     invoice id and none is written with one, so none of them reads a special unit.
--   * A sale released to a supplier (494): it wrote no movement, so nothing is asked and
--     nothing returns, as before. A sale still waiting: cancelled as before (393).
--   * Rentals: a refund ends one and it waits for "Receive returned item", as before.
--   * The pages. Nothing is deployed for this.
--
-- KNOWN
--
--   * A line removed from a paid invoice by a correction still leaves a released item
--     alone, as before, and so does one lowered below the units released: a later
--     cancellation moves only the units on the lines it shows, so such a unit stays as
--     it was.
--   * A unit confirmed "not returned" cannot be put back later through the refund
--     screens (it is settled), as a product's cannot; an Owner puts it back with a stock
--     adjustment.
--   * Sales refunded or cancelled BEFORE this and released are not settled by it. None
--     exists on production (6 Nov 2026).
--   * Reopening an invoice whose unit was damaged or not returned raises nothing new, as
--     before: the item left and did not come back.
--
-- WITH 495 (services hold no stock, applied 6 Nov 2026, 12:53 UTC)
--
--   495 patches refund_invoice_recorded on two other lines (its product-refund question).
--   This patches it on two lines that 495 does not touch, so the two do not meet. This
--   file accepts the function as production has it now, with 495 in (the BEFORE below),
--   or as it was before 495 (the second set of md5s below, for a copy of production at
--   494), and refuses anything else. It was built, tested and run against both.
--   495 does not touch invoice_refund_options, only invoice_refund_options_before_sessions
--   (which this one reads and does not change), so its service rule is untouched:
--   services hold no stock, so a service has no stock row here to be asked about.
--
-- UNDO
--
--   scripts/special/undo-496.sql puts the seven functions back to their BEFORE texts and
--   drops the four it added. It keeps the column and the table, and what they hold: units
--   already settled stay settled. (After it, no refund asks about a released unit again.)
--   Undo this before 495: 495's own undo expects refund_invoice_recorded as 495 left it.
--
-- DEPLOY ORDER (each step with the user's go-ahead in chat)
--
--   1. Dry run on a copy of production as it is then: apply this file twice; the second
--      run changes nothing ("already this version").
--   2. Apply. It checks itself, links the sales released so far (production, 6 Nov 2026:
--      8, a link only: no quantity and no stock figure changes), and runs its self-test.
--   3. Nothing to deploy for the pages.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic whatever runs
--   it; every check comes before anything changes:
--   * each function patched is its BEFORE (patched; every patch's text found exactly once,
--     the text built having the tested md5) or its AFTER (left alone); anything else is
--     refused;
--   * the new functions' texts have their tested md5s, and no other function has either name;
--   * the columns read and the functions relied on are there;
--   * afterwards: the md5s are the AFTER ones, the patched functions' grants are as before
--     (compared as sets), only the service role may call the four new ones, and the
--     table's row-level security is on;
--   * then a self-test, in a block that is always undone (it ends by raising P0496, so it
--     leaves no row, writes its invoice straight to its table so no invoice number is
--     used, and names its sales itself): made-up records ("496 Check", @example.invalid, a
--     fictional +61 2 5550 phone). No real customer is read or written.
--   Locks: ACCESS EXCLUSIVE on special_sales (11 rows on 6 Nov 2026) for the column and its
--   index, and SHARE ROW EXCLUSIVE on the tables the new foreign keys point at (invoices,
--   profiles, stock_movements, special_sales), plus the functions' catalogue rows and the
--   self-test's own rows, all held until the one statement ends (about 0.1 s on an empty
--   copy), so a writer to those tables queues behind it for that moment. stock_movements is
--   not altered. The lock timeout gives up after 5 s and changes nothing.
--
-- BEFORE (production, 6 Nov 2026: head 20261106125302, 495; md5 of pg_get_functiondef
-- with search_path public; public function fingerprint 24e557bcaa6873c9b4c451243c63c05a 1420)
--   fulfil_special_doc(text,uuid,uuid,text) e2fd9fca6842b5193ec7020445a45189
--   invoice_refund_options(uuid) 689a71c246260d2c10ec44dd94eb7139
--   invoice_action_plan(uuid,text,jsonb) 383d618edb28c3c9a360242d038a022c
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid) 3280f4ed6afb93aed7366eaf100c6383
--   record_invoice_stock_return(uuid,jsonb,text,uuid) 6b125cb5df1eb103781662bef41e9417
--   cancel_invoice_recorded(uuid,text,uuid) de52d9dbaef8ab15163bef35cb9d733d
--   create_special_docs_for_invoice(uuid) 429f4ac315cb5d0557c2005807bad115
-- As it was before 495 (a copy at 494; the only difference), and what this makes of it:
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid) 804ecd829cfecf713783a09a05d93c7e (before) 3fb10ac55903b9346c4898d988b808ce (after)
-- AFTER (for later guards; public function fingerprint 410d562170930b034bf1068dc3923b83 1424, four added)
--   fulfil_special_doc(text,uuid,uuid,text) 9b4520efc9d06b04360bacc2c035215b
--   invoice_refund_options(uuid) 0a9276f8b967b24a040e486287182072
--   invoice_action_plan(uuid,text,jsonb) d8bf5ea6c92c49be3b53547e6f407278
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid) 49f6880e4e6395b1468f32e4126472eb
--   record_invoice_stock_return(uuid,jsonb,text,uuid) 065df9ace464185d8cf44aba7a12dec9
--   cancel_invoice_recorded(uuid,text,uuid) 5490e4b48dfdab63b6dc5a0aa78d4bc7
--   create_special_docs_for_invoice(uuid) 540b98385d9632abcc5fe35c23c00bb5
-- Added
--   special_release_rows(uuid) de901e68cc00979dd479a1807ff43f9a
--   return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text) 71c22eb51b75650836e09a95b827c0fe
--   restore_released_special_stock(uuid,text,uuid) 5f1b3d1d0c78a0c49d7fc2171301f5d1
--   link_released_special_movements() 3c07e0b8d84973c7bebb7df0f0f15ed7
--
-- Test: scripts/special/tests/released-return-496.sql (begin ... rollback; it installs
-- this file twice, or with -v skip_install=1 where it is in, and sells, pays, releases,
-- refunds, cancels and reopens through the app's own calls). Fixtures only (the
-- repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The functions patched: BEFORE (production now), AFTER, and the patches ══
  c_sig constant text[] := array['fulfil_special_doc(text,uuid,uuid,text)', 'invoice_refund_options(uuid)', 'invoice_action_plan(uuid,text,jsonb)', 'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', 'record_invoice_stock_return(uuid,jsonb,text,uuid)', 'cancel_invoice_recorded(uuid,text,uuid)', 'create_special_docs_for_invoice(uuid)'];
  c_before constant text[] := array['e2fd9fca6842b5193ec7020445a45189', '689a71c246260d2c10ec44dd94eb7139', '383d618edb28c3c9a360242d038a022c', '3280f4ed6afb93aed7366eaf100c6383', '6b125cb5df1eb103781662bef41e9417', 'de52d9dbaef8ab15163bef35cb9d733d', '429f4ac315cb5d0557c2005807bad115'];
  c_after constant text[] := array['9b4520efc9d06b04360bacc2c035215b', '0a9276f8b967b24a040e486287182072', 'd8bf5ea6c92c49be3b53547e6f407278', '49f6880e4e6395b1468f32e4126472eb', '065df9ace464185d8cf44aba7a12dec9', '5490e4b48dfdab63b6dc5a0aa78d4bc7', '540b98385d9632abcc5fe35c23c00bb5'];
  -- Before 495 (a copy of production at 494), refund_invoice_recorded is not production's: its BEFORE and AFTER there.
  c_before_alt constant text[] := array[null, null, null, '804ecd829cfecf713783a09a05d93c7e', null, null, null];
  c_after_alt constant text[] := array[null, null, null, '3fb10ac55903b9346c4898d988b808ce', null, null, null];
  -- Each patch: which function (its place in c_sig), the text found exactly once in it,
  -- and the text put in its place. The UNDO file swaps them back.
  c_fn constant int[] := array[1, 1, 1, 1, 1, 2, 3, 4, 4, 5, 6, 7, 7, 7, 7, 7];
  c_anchor constant text[] := array[
$a1$  v458_inv text; v458_owing numeric;  -- 458$a1$,
$a2$  if p_doc_kind = 'special_sale' then
    select special_product_id, quantity, sale_no into v_sp, v_qty, v_no$a2$,
$a3$      case when p_doc_kind = 'rental' then 'Rental released — ' else 'Special sale released — ' end || v_no,
      auth.uid());
  else$a3$,
$a4$        || ' (from store)',
      auth.uid());
  end if;$a4$,
$a5$           status = 'completed', fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;$a5$,
$a6$ return result||jsonb_build_object('therapy_sessions',(select coalesce(jsonb_agg(jsonb_build_object($a6$,
$a7$  -- ---- stock actually deducted for this line ----------------------------
  if it.line_kind::text in ('product','promotion') then
   for s in select * from jsonb_array_elements(coalesce(o->'stock','[]')) loop$a7$,
$a8$     raise exception 'Record the returned-and-sellable, damaged, or not-returned quantities for this product refund'; end if;
   v_total:=v_total+v_amount;$a8$,
$a9$   select * into sm from public.stock_movements where id=(x->>'movement_id')::uuid and invoice_id=i.id and movement_type::text='store_sale' for update;$a9$,
$a10$  select * into sm from public.stock_movements
   where id=(x->>'movement_id')::uuid and invoice_id=p_invoice_id and movement_type::text='store_sale' for update;$a10$,
$a11$ perform public.restore_invoice_stock(i.id,'Cancelled invoice: '||p_reason);$a11$,
$a12$  v458_units integer; v458_have integer; v458_cnt integer; v458_r public.rentals%rowtype;  -- 458$a12$,
$a13$    -- Already raised for this line: never duplicate on a re-run or a correction.$a13$,
$a14$                and (status <> 'cancelled' or warehouse_id is not null or source_store_id is not null$a14$,
$a15$                     or coalesce(cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity'))) then
      continue;
    end if;$a15$,
$a16$      for v_i in 1 .. greatest(coalesce(v_it.quantity,1), 1) loop$a16$];
  c_new constant text[] := array[
$n1$  v458_inv text; v458_owing numeric;  -- 458
  v496_mv uuid;  -- 496: the stock movement this release writes$n1$,
$n2$  -- 496 (the user, 6 Nov 2026): the invoice first, shared, as a refund takes it (for update), so a
  -- release and a refund of one invoice wait for one another instead of meeting on the stock row,
  -- or releasing what a refund has just taken back. A sale with no invoice waits for nothing.
  perform 1 from public.invoices v
   where v.id = (select d.invoice_id from (select s0.invoice_id from public.special_sales s0 where p_doc_kind = 'special_sale' and s0.id = p_doc_id
                                           union all
                                           select r0.invoice_id from public.rentals r0 where p_doc_kind = 'rental' and r0.id = p_doc_id) d limit 1)
     for share;
  if p_doc_kind = 'special_sale' then
    select special_product_id, quantity, sale_no into v_sp, v_qty, v_no$n2$,
$n3$      case when p_doc_kind = 'rental' then 'Rental released — ' else 'Special sale released — ' end || v_no,
      auth.uid())
    returning id into v496_mv;  -- 496
  else$n3$,
$n4$        || ' (from store)',
      auth.uid())
    returning id into v496_mv;  -- 496
  end if;$n4$,
$n5$           status = 'completed', fulfilled_at = now(), fulfilled_by = auth.uid(),
           release_movement_id = v496_mv  -- 496 (the user, 6 Nov 2026): a refund or a cancellation finds the unit by it
     where id = p_doc_id;$n5$,
$n6$ return result||jsonb_build_object(
  -- 496 (the user, 6 Nov 2026): the units released for this invoice's special sales are
  -- offered as stock to take back, as a product's deduction is (the same fields, and
  -- the sale, its line and the shelf it left, a warehouse or a store).
  'stock',coalesce(result->'stock','[]'::jsonb)||coalesce((select jsonb_agg(jsonb_build_object(
      'movement_id',r.movement_id,'product_id',r.product_id,'product_name',r.product_name,'store_id',r.store_id,
      'quantity',r.quantity,'resolved_quantity',r.resolved_quantity,'special_sale_id',r.special_sale_id,'sale_no',r.sale_no,
      'invoice_item_id',r.invoice_item_id,'location_type',r.location_type,'location_id',r.location_id,
      'location_name',r.location_name) order by r.sale_no)
    from public.special_release_rows(p_invoice_id) r),'[]'::jsonb),
  'therapy_sessions',(select coalesce(jsonb_agg(jsonb_build_object($n6$,
$n7$  -- ---- 496 (the user, 6 Nov 2026): the units released for this special sale line ----
  -- A special sale is one unit, and its stock was taken when it was released from a
  -- warehouse or a store, which no product line's deduction records. As many units as
  -- are being taken back (all of them for a cancellation or a full refund), by sale
  -- number, with the same fields as a product's deduction; store_name names the shelf
  -- it left, a store or a warehouse, so the screens need no change.
  if it.line_kind::text = 'special_product' then
   declare k496 int:=0; w496 int:=0;
   begin
    -- A part refund of some units while others of the line still wait: a waiting one the staff
    -- said "no" to (393's answers, carried on the lines as "waiting": the customer is not taking
    -- it) is a unit refunded first, so the released units asked about are the rest.
    if p_action='refund_partial' then
     select count(*) into w496
       from jsonb_array_elements(coalesce(p_lines,'[]')) pl,
            jsonb_array_elements(case when jsonb_typeof(pl->'waiting')='array' then pl->'waiting' else '[]'::jsonb end) q
      where jsonb_typeof(q->'still_taking')='boolean' and not (q->>'still_taking')::boolean
        and exists(select 1 from public.special_sales ws
                    where ws.id::text=lower(q->>'doc_id') and ws.invoice_item_id=it.id and ws.status='pending');
    end if;
    for s in select e.value from jsonb_array_elements(coalesce(o->'stock','[]')) e
              where e.value->>'invoice_item_id'=it.id::text and e.value->>'special_sale_id' is not null
              order by e.value->>'sale_no' loop
     exit when k496>=greatest(v_qty-w496,0);
     v_returnable:=coalesce((s->>'quantity')::int,0)-coalesce((s->>'resolved_quantity')::int,0);
     if v_returnable<=0 then continue; end if;
     v_returnable:=least(v_returnable,greatest(v_qty-w496,0)-k496);
     k496:=k496+v_returnable;
     v_stock:=v_stock||jsonb_build_array(jsonb_build_object(
       'movement_id',s->>'movement_id','product_name',s->>'product_name','store_id',s->>'store_id',
       'outstanding',coalesce((s->>'quantity')::int,0)-coalesce((s->>'resolved_quantity')::int,0),
       'proposed_sellable',v_returnable,'damaged_quantity',0,'not_returned_quantity',0,
       'store_name',s->>'location_name','location_type',s->>'location_type','location_id',s->>'location_id',
       'special_sale_id',s->>'special_sale_id','sale_no',s->>'sale_no'));
    end loop;
   end;
  end if;
  -- ---- stock actually deducted for this line ----------------------------
  if it.line_kind::text in ('product','promotion') then
   for s in select * from jsonb_array_elements(coalesce(o->'stock','[]')) loop
    continue when s->>'special_sale_id' is not null;  -- 496: a special sale's units are listed above, on their own line$n7$,
$n8$     raise exception 'Record the returned-and-sellable, damaged, or not-returned quantities for this product refund'; end if;
   -- 496 (the user, 6 Nov 2026): a special sale's line is asked what a product's is, for the units
   -- released for it that nobody has settled: back and sellable, damaged, or not returned. A refund
   -- that takes the whole of the line answers for every one of them (once the invoice is refunded
   -- nothing can ask again); a part refund answers for some at least, unless what it refunds is a
   -- waiting unit the staff said "no" to (the customer is not taking it).
   if it.id is not null and it.line_kind::text='special_product' then
    declare o496 int; u496 int; e496 boolean; bad496 boolean;
    begin
     select count(*) filter (where r.quantity>r.resolved_quantity),
            count(*) filter (where r.quantity>r.resolved_quantity
                              and not exists(select 1 from jsonb_array_elements(coalesce(p_stock,'[]')) ans where ans->>'movement_id'=r.movement_id::text))
       into o496,u496 from public.special_release_rows(i.id) r where r.invoice_item_id=it.id;
     e496:=exists(select 1 from jsonb_array_elements(coalesce(p_lines,'[]')) pl,
                        jsonb_array_elements(case when jsonb_typeof(pl->'waiting')='array' then pl->'waiting' else '[]'::jsonb end) q
                   where jsonb_typeof(q->'still_taking')='boolean' and not (q->>'still_taking')::boolean
                     and exists(select 1 from public.special_sales ws
                                 where ws.id::text=lower(q->>'doc_id') and ws.invoice_item_id=it.id and ws.status='pending'));
     bad496:=o496>0 and case when v_amount>=greatest(v_line_paid-v_refunded,0) then u496>0
                             else jsonb_array_length(coalesce(p_stock,'[]'))=0 and not e496 end;
     if bad496 then
       raise exception 'Record the returned-and-sellable, damaged, or not-returned quantities for this special sale refund'; end if;
    end;
   end if;
   v_total:=v_total+v_amount;$n8$,
$n9$   -- 496: a unit released for a special sale of this invoice goes back on the shelf it
   -- left, a warehouse or a store, by its own rule (special_sale_returns): only a unit of a
   -- line this refund is for, so a line still billed is never settled by another's answer.
   if exists(select 1 from public.special_release_rows(i.id) r where r.movement_id=(x->>'movement_id')::uuid) then
     if not exists(select 1 from public.special_release_rows(i.id) r
                    where r.movement_id=(x->>'movement_id')::uuid
                      and exists(select 1 from jsonb_array_elements(p_lines) pl where pl->>'invoice_item_id'=r.invoice_item_id::text)) then
       raise exception 'Answer for the units of the lines being refunded: that unit is on a line this refund does not cover'; end if;
     perform public.return_released_special_stock(i.id,(x->>'movement_id')::uuid,
       coalesce((x->>'sellable_quantity')::int,0),coalesce((x->>'damaged_quantity')::int,0),coalesce((x->>'not_returned_quantity')::int,0),
       p_request_id,p_reason,'refunded');
     continue;
   end if;
   select * into sm from public.stock_movements where id=(x->>'movement_id')::uuid and invoice_id=i.id and movement_type::text='store_sale' for update;$n9$,
$n10$  -- 496 (the user, 6 Nov 2026): a unit released for a special sale of this invoice goes
  -- back on the shelf it left by its own rule (special_sale_returns). This is the
  -- cancellation's step, taken before the cancellation puts back the rest.
  if exists(select 1 from public.special_release_rows(p_invoice_id) r where r.movement_id=(x->>'movement_id')::uuid) then
   perform public.return_released_special_stock(p_invoice_id,(x->>'movement_id')::uuid,
     coalesce((x->>'sellable_quantity')::int,0),coalesce((x->>'damaged_quantity')::int,0),coalesce((x->>'not_returned_quantity')::int,0),
     p_request_id,p_reason,'invoice cancelled');
   n:=n+1; continue;
  end if;
  select * into sm from public.stock_movements
   where id=(x->>'movement_id')::uuid and invoice_id=p_invoice_id and movement_type::text='store_sale' for update;$n10$,
$n11$ perform public.restore_invoice_stock(i.id,'Cancelled invoice: '||p_reason);
 -- 496 (the user, 6 Nov 2026): and the units released for its special sales, to the shelf they left.
 perform public.restore_released_special_stock(i.id,'Cancelled invoice: '||p_reason,p_request_id);$n11$,
$n12$  v458_units integer; v458_have integer; v458_cnt integer; v458_r public.rentals%rowtype;  -- 458
  v496_back integer := 0;  -- 496: units of a line whose stock came back, to raise again$n12$,
$n13$    v496_back := 0;  -- 496
    -- Already raised for this line: never duplicate on a re-run or a correction.$n13$,
$n14$                and (status <> 'cancelled' or ((warehouse_id is not null or source_store_id is not null) and not coalesce(stock_returned, false))  -- 496: one whose stock came back no longer counts$n14$,
$n15$                     or coalesce(cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity'))) then
      -- 496 (the user, 6 Nov 2026): the units of this line whose stock came back (a refund or a
      -- cancellation put them on the shelf) before the invoice was last reopened are raised again,
      -- as many as they are, but never more than the line holds beyond the units that still count:
      -- one damaged or not returned stays released and is not raised twice, nor is a unit raised
      -- again once it is. With none that came back, as before.
      if v_it.line_kind::text = 'special_product' and v_inv.reopened_at is not null then
        select least(count(*) filter (where status = 'cancelled' and coalesce(stock_returned, false) and cancelled_at <= v_inv.reopened_at),
                     greatest(coalesce(v_it.quantity, 1), 1)
                       - count(*) filter (where status <> 'cancelled'
                                             or ((warehouse_id is not null or source_store_id is not null) and not coalesce(stock_returned, false))
                                             or coalesce(cancelled_at, 'infinity') > v_inv.reopened_at))
          into v496_back from public.special_sales where invoice_item_id = v_it.id;
      end if;
      continue when coalesce(v496_back, 0) <= 0;
    end if;$n15$,
$n16$      for v_i in 1 .. (case when v496_back > 0 then v496_back else greatest(coalesce(v_it.quantity,1), 1) end) loop$n16$];
  -- ══ The functions added ══
  c_add_sig constant text[] := array['special_release_rows(uuid)', 'return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)', 'restore_released_special_stock(uuid,text,uuid)', 'link_released_special_movements()'];
  c_add_md5 constant text[] := array['de901e68cc00979dd479a1807ff43f9a', '71c22eb51b75650836e09a95b827c0fe', '5f1b3d1d0c78a0c49d7fc2171301f5d1', '3c07e0b8d84973c7bebb7df0f0f15ed7'];
  c_add_def constant text[] := array[
$d1$CREATE OR REPLACE FUNCTION public.special_release_rows(p_invoice_id uuid)
 RETURNS TABLE(movement_id uuid, special_sale_id uuid, sale_no text, invoice_item_id uuid, product_id uuid, product_name text, location_type text, location_id uuid, location_name text, store_id uuid, quantity integer, resolved_quantity integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 496 (the user, 6 Nov 2026): the units released for an invoice's special sales,
  -- one stock movement each (a sale is one unit), and how much of each a refund or
  -- a cancellation has settled (special_sale_returns). The refund and Cancel screens
  -- offer them as stock to take back, as they offer a product's deduction. A sale
  -- released to a supplier (494) wrote no movement, so it is not here. Internal:
  -- invoice_refund_options and the stock functions read it.
  select m.id, s.id, s.sale_no, s.invoice_item_id, m.product_id, public.special_product_name(s.special_product_id),
         case when m.from_warehouse_id is not null then 'warehouse' else 'store' end,
         coalesce(m.from_warehouse_id, m.from_store_id),
         coalesce(w.name, st.name),
         m.from_store_id,
         m.quantity,
         coalesce((select sum(r.sellable_quantity + r.damaged_quantity + r.not_returned_quantity)
                     from public.special_sale_returns r where r.movement_id = m.id), 0)::integer
    from public.special_sales s
    join public.stock_movements m on m.id = s.release_movement_id and m.movement_type::text = 'store_sale'
    left join public.warehouses w on w.id = m.from_warehouse_id
    left join public.stores st on st.id = m.from_store_id
   where s.invoice_id = p_invoice_id
$function$
$d1$,
$d2$CREATE OR REPLACE FUNCTION public.return_released_special_stock(p_invoice_id uuid, p_movement_id uuid, p_sellable integer, p_damaged integer, p_not_returned integer, p_request_id uuid, p_reason text, p_why text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 496 (the user, 6 Nov 2026): what became of the unit released for a special sale
-- of this invoice when the invoice was refunded or cancelled, as the Owner or
-- Manager confirmed it, as they confirm a product's: back and sellable (it goes
-- back on the shelf it left, a warehouse or a store), back but damaged, or not
-- returned (neither adds stock: the release stands). Recorded in
-- special_sale_returns. A sale whose whole unit is back in stock is over: it is
-- cancelled with its stock back, so an invoice reopened and paid again raises it
-- afresh, as a waiting one cancelled by a refund is (393). p_why is 'refunded' or
-- 'invoice cancelled'. Internal: refund_invoice_recorded, record_invoice_stock_return
-- and restore_released_special_stock call it, in the invoice's own transaction.
declare
  s public.special_sales%rowtype; m public.stock_movements%rowtype;
  v_sell integer := coalesce(p_sellable, 0); v_dam integer := coalesce(p_damaged, 0); v_nr integer := coalesce(p_not_returned, 0);
  v_done integer; v_back integer; v_loc text; v_ret uuid; v_note text;
  v_reason text := coalesce(nullif(btrim(p_reason), ''), 'no reason given');
begin
  if p_why is null or p_why not in ('refunded', 'invoice cancelled') then
    raise exception '496: stock comes back for a refund or a cancellation, not "%"', p_why; end if;
  select * into s from public.special_sales
   where invoice_id = p_invoice_id and release_movement_id = p_movement_id for update;
  if not found then raise exception 'Stock return must reference an actual invoice deduction'; end if;
  select * into m from public.stock_movements where id = s.release_movement_id for update;
  select coalesce(sum(r.sellable_quantity + r.damaged_quantity + r.not_returned_quantity), 0) into v_done
    from public.special_sale_returns r where r.movement_id = m.id;
  if v_sell < 0 or v_dam < 0 or v_nr < 0 or v_sell + v_dam + v_nr <= 0
     or v_sell + v_dam + v_nr > m.quantity - v_done then
    raise exception 'Stock disposition exceeds the unresolved deduction'; end if;
  v_loc := coalesce((select w.name from public.warehouses w where w.id = m.from_warehouse_id),
                    (select t.name from public.stores t where t.id = m.from_store_id));

  if v_sell > 0 then
    v_note := 'Special sale returned — ' || s.sale_no || ' (' || p_why || '): ' || v_reason;
    -- A shelf that has since been deleted shows no stock: not there.
    if exists (select 1 from public.warehouses w where w.id = m.from_warehouse_id and w.deleted_at is not null)
       or exists (select 1 from public.stores t where t.id = m.from_store_id and t.deleted_at is not null) then
      raise exception 'The % it left (%) has been deleted, so the unit cannot be put back there. Restore it first, or answer not returned and add the stock by an adjustment.',
        case when m.from_warehouse_id is not null then 'warehouse' else 'store' end, v_loc;
    end if;
    -- The shelf it left, a warehouse or a store.
    if m.from_warehouse_id is not null then
      insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
      values (m.from_warehouse_id, m.product_id, v_sell)
      on conflict (warehouse_id, product_id)
        do update set current_qty = public.warehouse_inventory.current_qty + excluded.current_qty, updated_at = now();
      insert into public.stock_movements (product_id, movement_type, to_warehouse_id, quantity, notes, created_by, reversed_sale_id)
      values (m.product_id, (case when p_why = 'refunded' then 'invoice_refund_return' else 'invoice_cancel_return' end)::stock_movement_type,
              m.from_warehouse_id, v_sell, v_note, auth.uid(), m.id)
      returning id into v_ret;
    else
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (m.from_store_id, m.product_id, v_sell)
      on conflict (store_id, product_id)
        do update set current_qty = public.store_inventory.current_qty + excluded.current_qty, updated_at = now();
      insert into public.stock_movements (product_id, movement_type, to_store_id, quantity, notes, created_by, reversed_sale_id)
      values (m.product_id, (case when p_why = 'refunded' then 'invoice_refund_return' else 'invoice_cancel_return' end)::stock_movement_type,
              m.from_store_id, v_sell, v_note, auth.uid(), m.id)
      returning id into v_ret;
    end if;
  end if;

  insert into public.special_sale_returns (special_sale_id, invoice_id, movement_id, return_movement_id, request_id, why,
                                           sellable_quantity, damaged_quantity, not_returned_quantity, reason, created_by)
  values (s.id, p_invoice_id, m.id, v_ret, p_request_id, p_why, v_sell, v_dam, v_nr, v_reason, auth.uid());

  select coalesce(sum(r.sellable_quantity), 0) into v_back from public.special_sale_returns r where r.special_sale_id = s.id;
  if v_back >= s.quantity then
    update public.special_sales
       set status = 'cancelled', cancelled_at = now(), stock_returned = true,
           notes = concat_ws(E'\n', notes, 'Cancelled (' || p_why || '): ' || v_reason)
     where id = s.id;
  end if;

  perform public.write_audit_ex('special_sale', s.id, 'special_sale_stock_returned',
    jsonb_build_object('status', s.status),
    jsonb_build_object('doc_no', s.sale_no, 'why', p_why, 'sellable', v_sell, 'damaged', v_dam, 'not_returned', v_nr,
      'location_type', case when m.from_warehouse_id is not null then 'warehouse' else 'store' end,
      'location', coalesce(m.from_warehouse_id, m.from_store_id), 'location_name', v_loc,
      'status', case when v_back >= s.quantity then 'cancelled' else s.status end,
      'invoice_id', p_invoice_id, 'request_id', p_request_id),
    'special', v_reason, s.store_id);
end $function$
$d2$,
$d3$CREATE OR REPLACE FUNCTION public.restore_released_special_stock(p_invoice_id uuid, p_note text, p_request_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n integer := 0;
begin
  -- 496 (the user, 6 Nov 2026): a cancellation puts back the units released for the
  -- invoice's special sales that nobody has settled yet, as restore_invoice_stock
  -- puts back a product's: sellable, on the shelf it left. A unit the Owner or
  -- Manager confirmed damaged or not returned first (record_invoice_stock_return)
  -- is settled and left alone. Only the units its plan lists, which are those on
  -- the invoice's lines as they are now, up to each line's quantity, by sale number
  -- (invoice_action_plan): a unit whose line a correction removed or lowered stays as
  -- it was, never moved without being shown. Returns how many units' sales it settled.
  -- Internal: cancel_invoice_recorded calls it, and not a correction
  -- (restore_invoice_stock is also that), which must never take a released unit back.
  -- (A unit this same request has just settled, in the guided cancellation's first step,
  -- still takes its place in the order, so the units after it are not moved in its stead.)
  for r in select q.* from (select x.*, row_number() over (partition by x.invoice_item_id order by x.sale_no) as rn,
                                   greatest(coalesce(it.quantity, 1), 1) as line_qty
                              from public.special_release_rows(p_invoice_id) x
                              join public.invoice_items it on it.id = x.invoice_item_id and it.invoice_id = p_invoice_id
                             where x.quantity > x.resolved_quantity
                                or exists (select 1 from public.special_sale_returns rr
                                            where rr.movement_id = x.movement_id and rr.request_id = p_request_id)) q
            where q.rn <= q.line_qty and q.quantity > q.resolved_quantity
            order by q.sale_no loop
    perform public.return_released_special_stock(p_invoice_id, r.movement_id, r.quantity - r.resolved_quantity, 0, 0,
                                                 p_request_id, p_note, 'invoice cancelled');
    n := n + 1;
  end loop;
  return n;
end $function$
$d3$,
$d4$CREATE OR REPLACE FUNCTION public.link_released_special_movements()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  -- 496 (the user, 6 Nov 2026): a sale released before 496 wrote its stock movement
  -- without the sale knowing which. This finds it again, only where it is certain:
  -- the movement's note is the one fulfil_special_doc writes for this sale number
  -- (and " (from store)" for a store), it is the same product and quantity, it left
  -- the same warehouse or store, and no invoice owns it; and only where that one
  -- movement and that one sale match each other alone. It links, nothing more: no
  -- quantity and no stock figure changes. Safe to run again. Returns how many it linked.
  with pairs as (
    select s.id as sale_id, m.id as movement_id
      from public.special_sales s
      join public.special_products sp on sp.id = s.special_product_id
      join public.stock_movements m
        on m.movement_type::text = 'store_sale' and m.invoice_id is null
       and m.product_id = sp.product_id and m.quantity = s.quantity
       and m.from_warehouse_id is not distinct from s.warehouse_id
       and m.from_store_id is not distinct from s.source_store_id
       and m.notes = 'Special sale released — ' || s.sale_no || case when s.source_store_id is not null then ' (from store)' else '' end
     where s.release_movement_id is null and (s.warehouse_id is not null or s.source_store_id is not null))
  update public.special_sales s set release_movement_id = p.movement_id
    from pairs p
   where s.id = p.sale_id
     and (select count(*) from pairs q where q.sale_id = p.sale_id) = 1
     and (select count(*) from pairs q where q.movement_id = p.movement_id) = 1;
  get diagnostics n = row_count;
  return n;
end $function$
$d4$];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[7]);
  v_make boolean[] := array_fill(false, array[7]);
  v_target text[] := array_fill(null::text, array[7]);
  v_acl text[] := array_fill(null::text, array[7]);
  v_add_make boolean[] := array_fill(false, array[4]);
  d text; m text; i int; n int;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_owner uuid; t_store uuid; t_wh uuid; t_cust uuid; t_prd uuid; t_sp uuid; t_inv uuid; t_item uuid;
  t_sale_a uuid; t_sale_b uuid; t_sale_c uuid; t_sale_d uuid; t_mv_a uuid; t_mv_b uuid; t_mv_c uuid; t_mv_d uuid; t_msg text; t_row record; t_n integer;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──
  select string_agg(x.t || '.' || x.c || ' ' || x.ty, ', ') into d
    from (values ('special_sales', 'id', 'uuid'), ('special_sales', 'sale_no', 'text'), ('special_sales', 'quantity', 'integer'),
                 ('special_sales', 'status', 'text'), ('special_sales', 'invoice_id', 'uuid'), ('special_sales', 'invoice_item_id', 'uuid'),
                 ('special_sales', 'warehouse_id', 'uuid'), ('special_sales', 'source_store_id', 'uuid'), ('special_sales', 'store_id', 'uuid'),
                 ('special_sales', 'special_product_id', 'uuid'), ('special_sales', 'cancelled_at', 'timestamp with time zone'),
                 ('special_sales', 'stock_returned', 'boolean'), ('special_sales', 'notes', 'text'),
                 ('special_products', 'product_id', 'uuid'),
                 ('stock_movements', 'reversed_sale_id', 'uuid'), ('stock_movements', 'to_warehouse_id', 'uuid'),
                 ('stock_movements', 'to_store_id', 'uuid'), ('stock_movements', 'from_warehouse_id', 'uuid'),
                 ('stock_movements', 'from_store_id', 'uuid'), ('stock_movements', 'invoice_id', 'uuid'),
                 ('warehouse_inventory', 'updated_at', 'timestamp with time zone'), ('store_inventory', 'updated_at', 'timestamp with time zone'),
                 ('invoices', 'store_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = ('public.' || x.t)::regclass and a.attname = x.c and not a.attisdropped
                        and format_type(a.atttypid, a.atttypmod) = x.ty);
  if d is not null then raise exception '496: these columns are missing or not of this type: %', d; end if;

  if (select count(*) from pg_enum e join pg_type t on t.oid = e.enumtypid
       where t.typname = 'stock_movement_type' and e.enumlabel in ('store_sale', 'invoice_refund_return', 'invoice_cancel_return')) <> 3 then
    raise exception '496: a stock movement type it uses is missing'; end if;

  select string_agg(f, ', ') into d
    from unnest(array['special_product_name(uuid)', 'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
                      'is_owner_or_admin()', 'current_user_store_ids()', 'special_doc_invoice_problem(uuid,uuid)',
                      'invoice_refund_options_before_sessions(uuid)', 'restore_invoice_stock(uuid,text)',
                      'upsert_special_product_from_product(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,boolean)']) f
   where to_regprocedure('public.' || f) is null;
  if d is not null then raise exception '496: these functions are missing: %', d; end if;

  -- The functions it adds: not there yet, or as tested; and no other function takes either name.
  for i in 1 .. cardinality(c_add_sig) loop
    if md5(c_add_def[i]) <> c_add_md5[i] then
      raise exception '496: the text of public.% is not the tested one (md5 %)', c_add_sig[i], md5(c_add_def[i]); end if;
    if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                and p.proname = split_part(c_add_sig[i], '(', 1)
                and p.oid::regprocedure::text <> c_add_sig[i]) then
      raise exception '496: another function takes the name of public.%', c_add_sig[i]; end if;
    if to_regprocedure('public.' || c_add_sig[i]) is null then
      v_add_make[i] := true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_add_sig[i]))) <> c_add_md5[i] then
      raise exception '496: public.% is there already and is not this version (md5 %)', c_add_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_add_sig[i]))); end if;
  end loop;

  -- The functions it patches: BEFORE (patched), or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '496: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    m := md5(d);
    -- its grants, to compare after (as sets: production lists them in another order than a local copy does)
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if m = c_after[i] or m = c_after_alt[i] then
      raise notice '496: public.% is already this version; left alone', c_sig[i];
    elsif m = c_before[i] then
      v_make[i] := true; v_def[i] := d; v_target[i] := c_after[i];
    elsif m = c_before_alt[i] then
      v_make[i] := true; v_def[i] := d; v_target[i] := c_after_alt[i];
    else
      raise exception '496: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], m;
    end if;
  end loop;
  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '496: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> v_target[i] then
      raise exception '496: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- ── 2. Install ──
  -- The sale knows which movement took its unit out.
  alter table public.special_sales add column if not exists release_movement_id uuid references public.stock_movements(id);
  comment on column public.special_sales.release_movement_id is
    '496: the stock movement that took this sale''s unit out of a warehouse or a store when it was released; what a refund or a cancellation puts back.';
  create unique index if not exists special_sales_release_movement_key
    on public.special_sales (release_movement_id) where release_movement_id is not null;
  -- What a refund or a cancellation settled for each released unit.
  create table if not exists public.special_sale_returns (
    id uuid primary key default gen_random_uuid(),
    special_sale_id uuid not null references public.special_sales(id),
    invoice_id uuid not null references public.invoices(id),
    movement_id uuid not null references public.stock_movements(id),
    return_movement_id uuid references public.stock_movements(id),
    request_id uuid not null,
    why text not null check (why in ('refunded', 'invoice cancelled')),
    sellable_quantity integer not null default 0 check (sellable_quantity >= 0),
    damaged_quantity integer not null default 0 check (damaged_quantity >= 0),
    not_returned_quantity integer not null default 0 check (not_returned_quantity >= 0),
    reason text not null,
    created_by uuid references public.profiles(id),
    created_at timestamptz not null default now(),
    check (sellable_quantity + damaged_quantity + not_returned_quantity > 0),
    unique (movement_id, request_id)
  );
  comment on table public.special_sale_returns is
    '496: what a refund or a cancellation settled for a unit released for a special sale: back and sellable (on the shelf it left), damaged, or not returned. Written by return_released_special_stock alone.';
  create index if not exists special_sale_returns_sale on public.special_sale_returns (special_sale_id);
  alter table public.special_sale_returns enable row level security;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'special_sale_returns'
                  and policyname = 'special_sale_returns_read') then
    create policy special_sale_returns_read on public.special_sale_returns for select to authenticated
      using (exists (select 1 from public.invoices i where i.id = special_sale_returns.invoice_id
                      and ((select public.is_owner_or_admin()) or i.store_id = any ((select public.current_user_store_ids())::uuid[]))));
  end if;

  -- What the patched functions call comes first. Functions are not endpoints (339):
  -- the four are internal, as the other stock helpers.
  for i in 1 .. cardinality(c_add_sig) loop
    if v_add_make[i] then
      execute c_add_def[i];
      execute format('revoke all on function public.%s from public, anon, authenticated', c_add_sig[i]);
      execute format('grant execute on function public.%s to service_role', c_add_sig[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- The sales released before this: linked where the match is certain.
  n := public.link_released_special_movements();
  raise notice '496: % released special sale(s) linked to the movement that took their unit out', n;
  select count(*) into i from public.special_sales
   where (warehouse_id is not null or source_store_id is not null) and release_movement_id is null;
  raise notice '496: % released special sale(s) could not be matched to one movement and stay as they were (a refund would not ask about them)', i;

  -- ── 3. Checks after installing ──
  for i in 1 .. cardinality(c_sig) loop
    m := md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i])));
    if m <> c_after[i] and m is distinct from c_after_alt[i] then
      raise exception '496: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '496: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_add_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_add_sig[i]))) <> c_add_md5[i] then
      raise exception '496: public.% was installed with an md5 other than the tested one', c_add_sig[i]; end if;
    if has_function_privilege('anon', to_regprocedure('public.' || c_add_sig[i]), 'execute')
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_add_sig[i]), 'execute')
       or not has_function_privilege('service_role', to_regprocedure('public.' || c_add_sig[i]), 'execute') then
      raise exception '496: the grants of public.% are not as written', c_add_sig[i]; end if;
  end loop;
  if not (select relrowsecurity from pg_class where oid = 'public.special_sale_returns'::regclass) then
    raise exception '496: row-level security is not on for special_sale_returns'; end if;

  -- ── 4. Self-test, in a block that is always undone ──
  -- Made-up records only ("496 Check", @example.invalid, a fictional +61 2 5550 phone);
  -- the invoice is written straight to its table with its own number, so no sequence is
  -- used, and nothing is paid. It ends by raising P0496, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- A fictional phone no customer holds, in use or deleted (range scans of the two partial phone indexes, as 486's)
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '496: the self-test found no free fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '496chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '496 Check Owner', '496chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);
    insert into public.stores (name, code, country_code) values ('496 Check ' || t_sfx, '496-' || t_sfx, 'SG') returning id into t_store;
    insert into public.warehouses (name, code) values ('496 Check ' || t_sfx, '496-' || t_sfx) returning id into t_wh;
    insert into public.customers (full_name, phone) values ('496 Check', '+6125550' || lpad(t_base::text, 4, '0')) returning id into t_cust;
    insert into public.products (name, sku, product_type) values ('496 Check ' || t_sfx, '496-P-' || t_sfx, 'third_party') returning id into t_prd;
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (t_wh, t_prd, 5);
    t_sp := public.upsert_special_product_from_product(null, t_prd, 100);
    insert into public.invoices (invoice_no, store_id, customer_id, created_by)
    values ('496-CHECK-' || t_sfx, t_store, t_cust, t_owner) returning id into t_inv;
    insert into public.invoice_items (invoice_id, line_kind, special_product_id, quantity, unit_price, line_total)
    values (t_inv, 'special_product', t_sp, 3, 100, 300) returning id into t_item;
    -- Three sales of one unit each (a line of three makes one per unit), named here so no sale number is used up.
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, sold_by)
    values ('496-CHECK-A-' || t_sfx, t_sp, 1, 100, 100, 'pending', '496 self-test', t_inv, t_item, t_store, t_owner) returning id into t_sale_a;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, sold_by)
    values ('496-CHECK-B-' || t_sfx, t_sp, 1, 100, 100, 'pending', '496 self-test', t_inv, t_item, t_store, t_owner) returning id into t_sale_b;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, sold_by)
    values ('496-CHECK-C-' || t_sfx, t_sp, 1, 100, 100, 'pending', '496 self-test', t_inv, t_item, t_store, t_owner) returning id into t_sale_c;

    -- Waiting units are not offered; a release links the sale to its movement and offers the unit.
    if exists (select 1 from public.special_release_rows(t_inv)) then raise exception '496: a waiting sale is offered as stock'; end if;
    perform public.fulfil_special_doc('special_sale', t_sale_a, t_wh, 'warehouse');
    perform public.fulfil_special_doc('special_sale', t_sale_b, t_wh, 'warehouse');
    perform public.fulfil_special_doc('special_sale', t_sale_c, t_wh, 'warehouse');
    select release_movement_id into t_mv_a from public.special_sales where id = t_sale_a;
    select release_movement_id into t_mv_b from public.special_sales where id = t_sale_b;
    select release_movement_id into t_mv_c from public.special_sales where id = t_sale_c;
    if t_mv_a is null or t_mv_b is null or t_mv_c is null or t_mv_a = t_mv_b or t_mv_b = t_mv_c then
      raise exception '496: a release did not link its sale to its movement'; end if;
    select * into t_row from public.stock_movements where id = t_mv_a;
    if t_row.movement_type::text <> 'store_sale' or t_row.from_warehouse_id is distinct from t_wh or t_row.quantity <> 1
       or t_row.product_id is distinct from t_prd or t_row.invoice_id is not null then
      raise exception '496: the linked movement is not the release: %', to_jsonb(t_row); end if;
    if (select count(*) from public.special_release_rows(t_inv) r where r.location_type = 'warehouse' and r.location_id = t_wh and r.resolved_quantity = 0) <> 3
       or jsonb_array_length((public.invoice_refund_options(t_inv))->'stock') <> 3
       or (select count(*) from jsonb_array_elements((public.invoice_refund_options(t_inv))->'stock') s where s->>'special_sale_id' is not null) <> 3 then
      raise exception '496: the refund screen is not offered the three released units'; end if;
    if (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 2 then
      raise exception '496: three releases did not leave 2 of 5'; end if;

    -- Damaged: nothing goes back, the sale stays released, the answer is kept, and it cannot be answered twice.
    perform public.return_released_special_stock(t_inv, t_mv_a, 0, 1, 0, gen_random_uuid(), '496 self-test', 'refunded');
    if (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 2
       or (select status from public.special_sales where id = t_sale_a) <> 'completed'
       or not exists (select 1 from public.special_sale_returns where movement_id = t_mv_a and damaged_quantity = 1 and return_movement_id is null) then
      raise exception '496: a damaged answer was not recorded as one'; end if;
    t_msg := null;
    begin perform public.return_released_special_stock(t_inv, t_mv_a, 1, 0, 0, gen_random_uuid(), '496 self-test', 'refunded');
    exception when others then t_msg := sqlerrm; end;
    if t_msg is distinct from 'Stock disposition exceeds the unresolved deduction' then
      raise exception '496: a settled unit was answered again: %', t_msg; end if;

    -- Sellable: the unit goes back on the warehouse it left, with a return movement, and the sale is over.
    perform public.return_released_special_stock(t_inv, t_mv_b, 1, 0, 0, gen_random_uuid(), '496 self-test', 'refunded');
    select * into t_row from public.special_sales where id = t_sale_b;
    if (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 3
       or t_row.status <> 'cancelled' or not coalesce(t_row.stock_returned, false) or t_row.notes not like '%Cancelled (refunded): 496 self-test%'
       or not exists (select 1 from public.stock_movements m where m.reversed_sale_id = t_mv_b and m.movement_type::text = 'invoice_refund_return'
                         and m.to_warehouse_id = t_wh and m.quantity = 1 and m.invoice_id is null) then
      raise exception '496: a sellable answer did not put the unit back: %', to_jsonb(t_row); end if;

    -- A cancellation puts back every unit nobody settled, and only those.
    t_n := public.restore_released_special_stock(t_inv, 'Cancelled invoice: 496 self-test', gen_random_uuid());
    if t_n <> 1 then raise exception '496: a cancellation settled % units, not the 1 nobody had', t_n; end if;
    if (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 4 then
      raise exception '496: a cancellation left % in the warehouse, not 4',
        (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd); end if;
    if (select status from public.special_sales where id = t_sale_c) <> 'cancelled'
       or (select status from public.special_sales where id = t_sale_a) <> 'completed' then
      raise exception '496: after a cancellation the sales are %, %', (select status from public.special_sales where id = t_sale_c),
        (select status from public.special_sales where id = t_sale_a); end if;
    t_n := public.restore_released_special_stock(t_inv, 'Cancelled invoice: 496 self-test', gen_random_uuid());
    if t_n <> 0 then raise exception '496: a second cancellation settled % units', t_n; end if;

    -- A sale released before this, with its movement and no link, is found again where the match is certain, and only then.
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, warehouse_id, fulfilled_at)
    values ('496-CHECK-D-' || t_sfx, t_sp, 1, 100, 100, 'completed', '496 self-test', t_wh, now()) returning id into t_sale_d;
    insert into public.stock_movements (product_id, movement_type, from_warehouse_id, quantity, notes)
    values (t_prd, 'store_sale', t_wh, 1, 'Special sale released — 496-CHECK-D-' || t_sfx) returning id into t_mv_d;
    insert into public.stock_movements (product_id, movement_type, from_warehouse_id, quantity, notes)
    values (t_prd, 'store_sale', t_wh, 1, 'Special sale released — 496-CHECK-D-' || t_sfx);
    t_n := public.link_released_special_movements();
    if t_n <> 0 then raise exception '496: two movements for one sale were linked (%)', t_n; end if;
    delete from public.stock_movements where notes = 'Special sale released — 496-CHECK-D-' || t_sfx and id <> t_mv_d;
    t_n := public.link_released_special_movements();
    if t_n <> 1 or (select release_movement_id from public.special_sales where id = t_sale_d) is distinct from t_mv_d then
      raise exception '496: a sale released before this was not linked (% linked)', t_n; end if;
    t_n := public.link_released_special_movements();
    if t_n <> 0 then raise exception '496: linking twice linked % more', t_n; end if;

    raise exception using errcode = 'P0496', message = '496: self-test done, undone';
  exception when sqlstate 'P0496' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
