-- Released paid credit stays right on the paths 356 section 3b and 355 fixed.
--
-- A regression test for the gaps a review of 355/356 found. Each scenario was
-- chosen because it failed against the behaviour before the fix:
--
--   1. Two lines of the SAME premium bundle settled in one payment: the second
--      line's benefit capture re-read the first line's sale and its vouchers
--      (duplicate key on invoice_benefit_voucher_unique; the payment rolled back).
--   2. Two lines of the SAME credit package: the second line's released lot was
--      valued inside the first line's sale (S$500 for 100 credit), the refund
--      options offered more than was ever received, and the commission source
--      of a released lot matched both sales ('Commission review required').
--   3. A line in the shape 328's repair left (old lot reversed, a replacement
--      lot holding the credit, a 0 progress row naming the old lot): the chain
--      follows it, removing the line reclaims the replacement (it used to try a
--      0 ledger row), cancel then reopen releases again (it used to hold 0), and
--      settlement puts the benefit on the replacement lot.
--   4. A correction ADDS a credit line while another already holds released
--      credit: the new line queues behind money already released (it used to
--      depend on uuid order, releasing the same 600 twice half the time).
--   5. A kept line switched to another package: the old package's released
--      credit, with its rules, goes back and the money is released under the
--      new package; refused if any of it was spent.
--   6. A SETTLED part-paid bundle moved to another customer, then cancelled:
--      the pre-settlement write-off must leave the released lot to the benefit
--      loops (it used to reclaim it through the release record). 6b measures a
--      KNOWN GAP that predates 355/356 and is listed under NOT CHANGED in 356's
--      header: those loops do not follow the move either, so the new customer
--      keeps everything. It is reported, not asserted, and not fixed here.
--   7. (355) A Make-FOC package kept in a correction: another FOC reason is
--      refused; the same reason goes through and the line stays free. 7c: a
--      Make-FOC bundle kept with its FOC and reason but another voucher choice
--      is refused (a line given free cannot be edited in a correction at all).
--      7d: a kept package that is not free cannot be made free in a correction;
--      a new package line keeps the create-time refusal.
--   8. (356) A credit line on a CANCELLED invoice whose released credit was
--      partly spent before the cancel: the release row keeps the spent part,
--      and a reopen relies on it. Removing the line, switching it to another
--      package, or removing it and adding the package back as a new line is
--      refused ('was spent before this invoice was cancelled'); it used to go
--      through, and a reopen then released the spent part again (2,300 for a
--      S$2,000 package, 8c). 8b is a control: nothing spent, the row back at
--      0, the removal goes through with an audit row.
--   9. (356) invoice_commission_benefit_source on a released-lot benefit whose
--      lot is an EARLIER lot on the chain (a settled invoice moved to another
--      customer: the benefit row stays on the emptied pre-move lot, the credit
--      is on the replacement): it resolves to the line's own sale (it used to
--      match only the current lot, and found no source).
--  10. (356) Money moving between credit lines without a payment (a discount
--      withdrawn, a line added): released credit above the money now counted
--      toward a line goes back before anything new is released, so released
--      credit never exceeds the money received (it used to: 1,900 released for
--      1,800). What was already spent stays, as credit ahead of payment.
--  11. (356) A correction that makes a SETTLED bundle or package worth more
--      paid credit than it was issued at (the discount withdrawn) is refused
--      with CREDIT_LINE_SETTLED (it used to go through, asking for more money
--      that bought nothing); correcting 'Served by' and the notes still works.
--      11b: changing ANOTHER line (a product quantity on a discounted invoice,
--      which re-spreads the discount) still goes through; raising the settled
--      line's own price is refused. The check lives in
--      refuse_settled_credit_line_raise, called by correct_invoice.
--  12. (356) A refund on an open invoice keeps its own rules: the trim that
--      caps released credit to the money (10) is skipped when a refund of the
--      invoice is recorded in the same transaction. 12a: refunding S$300 of a
--      settled bundle's unused benefit leaves another bundle's 500 released (it
--      used to trim it to 200). 12b: refunding the PRODUCT line of a part-paid
--      bundle + product leaves the bundle's released 1,000 (it used to trim it
--      to 200).
--  13. (356) The settled-line check of 11 refuses only a line made worth more
--      than BOTH what it was issued at and what it was worth before the
--      correction, and reads a NULL manual discount as none. 13a: after an
--      allowed re-spread (11b), raising the discount to 210 is accepted (it
--      used to be refused); withdrawing it is still refused. 13b: on an
--      invoice with manual_discount NULL and a discount voucher, the till's
--      header (manual_discount 0) with one more product is accepted (it used
--      to count as a discount change and be refused).
--
-- Scenarios 8-13 were checked against the functions as they were before the
-- fix, re-created inside a rolled-back transaction (the 356 change removed from
-- reclaim_released_credit_of_removed_lines, release_credit_package_paid_credit
-- and the settled-line check respectively; for 12, the refund exemption removed
-- from release_credit_package_paid_credit's leading trim; for 13a, correct_invoice
-- no longer passing the worth before to refuse_settled_credit_line_raise; for
-- 13b, correct_invoice comparing the raw discount columns): each fails there.
-- 8b, the 'Served by' correction in 11 and the discount withdrawal in 13a are
-- controls against refusing too much or too little; they pass before and after.
--
-- Checks raise 'FAIL <n>: ...' and stop the run. A behaviour the migrations
-- knowingly leave as it is (6b) prints 'KNOWN GAP <n> (...)' as a notice with
-- the measured numbers: it is not counted as a failure and the numbers are
-- not asserted as correct.
--
-- Everything goes through the real entry points (create_invoice,
-- create_invoice_with_details, record_invoice_payment, correct_invoice,
-- cancel_invoice_recorded, reopen_invoice, refund_invoice_recorded,
-- apply_line_foc), except the
-- 328-repaired shape, which is built with the statements of
-- repair_credit_package_progress_lots() because 327-style lots can no longer be
-- written, and 13b's NULL manual discount, set directly on the invoice before
-- it is paid (create_invoice saves 0; create_credit_purchase_invoice saves
-- NULL, but its invoices have no discount to re-spread). Fixture names, codes
-- and phones carry a random suffix; disposable
-- database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';

create function pg_temp.sfx() returns text language sql volatile as
$$ select substr(md5(random()::text || clock_timestamp()::text), 1, 8) $$;
-- A valid Singapore mobile: +659 then 7 digits, the first 0-8.
create function pg_temp.phone() returns text language sql volatile as
$$ select '+659' || floor(random() * 9)::int::text || lpad(floor(random() * 1000000)::int::text, 6, '0') $$;

create temp table rcp_fx(k text primary key, v uuid);
create function pg_temp.fx(p_key text) returns uuid language sql stable as
$$ select f.v from rcp_fx f where f.k = p_key $$;
-- Credit the customer can still spend, by category.
create function pg_temp.held(p_customer uuid, p_category text default 'paid') returns numeric language sql stable as
$$ select coalesce(sum(l.remaining_amount),0) from customer_credit_lots l
    where l.customer_id = p_customer and l.category = p_category and l.status <> 'reversed' $$;
-- Credit granted to the customer and not reversed, by category.
create function pg_temp.granted(p_customer uuid, p_category text default 'paid') returns numeric language sql stable as
$$ select coalesce(sum(l.original_amount),0) from customer_credit_lots l
    where l.customer_id = p_customer and l.category = p_category and l.status <> 'reversed' $$;
create function pg_temp.vouchers_held(p_customer uuid) returns numeric language sql stable as
$$ select coalesce(sum(r.quantity),0) from customer_reward_vouchers r where r.customer_id = p_customer and r.status = 'held' $$;
create function pg_temp.customer(p_name text) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into customers(full_name, phone) values (p_name, pg_temp.phone()) returning id into v_id;
  return v_id;
end $$;
create function pg_temp.bundle(p_price numeric, p_bonus numeric, p_vouchers int) returns uuid language plpgsql as $$
declare v_pb uuid;
begin
  insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
    values ('RCP bundle '||p_price||' '||pg_temp.sfx(), p_price, p_price, p_bonus, p_vouchers, p_vouchers > 0)
    returning id into v_pb;
  insert into premium_bundle_stores(bundle_id,store_id) values (v_pb, pg_temp.fx('st'));
  if p_vouchers > 0 then
    insert into premium_bundle_vouchers(bundle_id,voucher_id) values (v_pb, pg_temp.fx('v')); end if;
  return v_pb;
end $$;
create function pg_temp.package(p_price numeric, p_allow_product boolean default true, p_allow_therapy boolean default true)
returns uuid language plpgsql as $$
declare v_cp uuid;
begin
  insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
    values ('RCP package '||p_price||' '||pg_temp.sfx(), p_price, p_price, p_allow_product, p_allow_therapy) returning id into v_cp;
  insert into credit_package_stores(package_id,store_id) values (v_cp, pg_temp.fx('st'));
  return v_cp;
end $$;
create function pg_temp.bundle_line(p_pb uuid, p_vouchers int default 0) returns jsonb language sql stable as
$$ select jsonb_build_object('kind','premium_bundle','premium_bundle_id',p_pb,'quantity',1,
     'voucher_selection', case when p_vouchers > 0
       then jsonb_build_array(jsonb_build_object('voucher_id',pg_temp.fx('v'),'quantity',p_vouchers))
       else '[]'::jsonb end) $$;
create function pg_temp.package_line(p_cp uuid) returns jsonb language sql immutable as
$$ select jsonb_build_object('kind','credit_package','credit_package_id',p_cp,'quantity',1) $$;
create function pg_temp.product_line(p_product uuid, p_qty int default 1) returns jsonb language sql immutable as
$$ select jsonb_build_object('kind','product','product_id',p_product,'quantity',p_qty) $$;
create function pg_temp.invoice(p_customer uuid, p_lines jsonb) returns uuid language sql as
$$ select create_invoice(pg_temp.fx('st'), p_customer, null::uuid, p_lines, 0::numeric, null::text, null::uuid, '[]'::jsonb) $$;
create function pg_temp.pay(p_invoice uuid, p_amount numeric) returns void language plpgsql as $$
begin
  perform record_invoice_payment(p_invoice, jsonb_build_array(jsonb_build_object(
    'payment_method_id',pg_temp.fx('pm'),'amount',p_amount)), gen_random_uuid());
end $$;
-- The customer spends released credit for real: therapy at S$100 a session, paid from the wallet.
create function pg_temp.spend(p_customer uuid, p_sessions int) returns uuid language plpgsql as $$
declare v_inv uuid;
begin
  v_inv := pg_temp.invoice(p_customer, jsonb_build_array(jsonb_build_object(
             'kind','therapy','therapy_service_id',pg_temp.fx('svc'),'quantity',p_sessions)));
  perform record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id',pg_temp.fx('wpm'),'amount',100 * p_sessions)), gen_random_uuid());
  return v_inv;
end $$;
create function pg_temp.lines(p_invoice uuid, p_kind text) returns uuid[] language sql stable as
$$ select coalesce(array_agg(x.id order by x.id), '{}') from invoice_items x
    where x.invoice_id = p_invoice and x.line_kind::text = p_kind $$;
create function pg_temp.line(p_invoice uuid, p_kind text) returns uuid language sql stable as
$$ select (pg_temp.lines(p_invoice, p_kind))[1] $$;
create function pg_temp.progress_lot(p_item uuid) returns uuid language sql stable as
$$ select pl.lot_id from credit_package_progress_lots pl where pl.invoice_item_id = p_item
    order by pl.created_at, pl.lot_id limit 1 $$;
create function pg_temp.status(p_invoice uuid) returns text language sql stable as
$$ select i.status::text from invoices i where i.id = p_invoice $$;
-- The line's benefit rows: total paid value (what a refund values them at).
create function pg_temp.benefit_paid(p_item uuid) returns numeric language sql stable as
$$ select coalesce(sum(b.paid_value),0) from invoice_benefit_values b where b.invoice_item_id = p_item $$;
-- An invoice with a manual discount, and the reason the till asks for.
create function pg_temp.dinvoice(p_customer uuid, p_lines jsonb, p_discount numeric) returns uuid language sql as
$$ select create_invoice_with_details(pg_temp.fx('st'), p_customer, p_lines,
     jsonb_build_object('business_date', sg_today()::text, 'manual_discount', p_discount,
                        'manual_discount_reason', 'RCP loyalty')) $$;
-- Every saved line sent back exactly as it is, for a correction. Only for
-- invoices of packages, bundles without vouchers and products, none FOC.
create function pg_temp.kept(p_invoice uuid) returns jsonb language sql stable as
$$ select coalesce(jsonb_agg(case x.line_kind::text
          when 'credit_package' then pg_temp.package_line(x.credit_package_id)
          when 'premium_bundle' then pg_temp.bundle_line(x.premium_bundle_id)
          else pg_temp.product_line(x.product_id, x.quantity::int) end
        || jsonb_build_object('invoice_item_id', x.id) order by x.id), '[]')
     from invoice_items x where x.invoice_id = p_invoice $$;
-- Paid credit released for the invoice's lines, as the release records hold it.
create function pg_temp.released(p_invoice uuid) returns numeric language sql stable as
$$ select coalesce(sum(pl.released_amount),0) from credit_package_progress_lots pl where pl.invoice_id = p_invoice $$;
-- Each credit line: released, money counted toward it, paid-credit entitlement.
create function pg_temp.credit_lines(p_invoice uuid) returns jsonb language sql stable as
$$ select coalesce(jsonb_agg(jsonb_build_object('kind', x.line_kind,
          'released', credit_package_released_paid_credit(x.id), 'money', credit_package_money_toward_line(x.id),
          'entitled', credit_line_paid_entitlement(x.id)) order by x.id), '[]')
     from invoice_items x where x.invoice_id = p_invoice and x.line_kind in ('credit_package','premium_bundle') $$;
-- What a refused correction must leave alone: the invoice, its lines and
-- release records, and the customer's credit.
create function pg_temp.invoice_state(p_invoice uuid) returns jsonb language sql stable as
$$ select jsonb_build_object(
     'invoice', (select jsonb_build_object('status', i.status, 'total', i.total_amount, 'paid', i.paid_amount,
                   'manual_discount', i.manual_discount, 'notes', i.notes, 'edit_count', i.edit_count)
                   from invoices i where i.id = p_invoice),
     'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.line_kind, 'package', x.credit_package_id,
                 'bundle', x.premium_bundle_id, 'quantity', x.quantity, 'total', x.line_total) order by x.id), '[]')
                 from invoice_items x where x.invoice_id = p_invoice),
     'releases', (select coalesce(jsonb_agg(jsonb_build_object('lot', pl.lot_id, 'line', pl.invoice_item_id,
                    'released', pl.released_amount) order by pl.lot_id), '[]')
                    from credit_package_progress_lots pl where pl.invoice_id = p_invoice)) $$;
create function pg_temp.credit_state(p_customer uuid) returns jsonb language sql stable as
$$ select jsonb_build_object(
     'ledger', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'amount', g.amount, 'type', g.entry_type) order by g.id), '[]')
                  from customer_credit_ledger g where g.customer_id = p_customer),
     'lots', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'remaining', l.remaining_amount, 'status', l.status) order by l.id), '[]')
                from customer_credit_lots l where l.customer_id = p_customer)) $$;
-- Paid credit the customer has spent (wallet payments), from any lot.
create function pg_temp.used(p_customer uuid) returns numeric language sql stable as
$$ select coalesce(sum(g.amount),0) from customer_credit_ledger g
    where g.customer_id = p_customer and g.category = 'paid' and g.entry_type = 'use' $$;

-- The shape repair_credit_package_progress_lots() (328) leaves a released lot
-- in, made with its own statements: the old row keeps the release on record,
-- the old lot's unspent remainder is reversed through the ledger and locked,
-- and granted again as a replacement lot recorded with released_amount 0 and
-- replaces_lot_id = the old lot. Returns the replacement lot.
create function pg_temp.repair_328(p_item uuid) returns uuid language plpgsql as $$
declare r record; pk credit_packages%rowtype; v_new uuid; v_rem numeric;
begin
  select l.*, it.id as invoice_item_id, it.invoice_id, it.credit_package_id into r
    from credit_package_progress_lots pl
    join customer_credit_lots l on l.id = pl.lot_id
    join invoice_items it on it.id = pl.invoice_item_id
   where pl.invoice_item_id = p_item;
  select * into pk from credit_packages where id = r.credit_package_id;
  -- The old lot keeps its release on the record for the line.
  update credit_package_progress_lots set released_amount = r.original_amount where lot_id = r.id;
  v_rem := r.remaining_amount;
  -- Reverse the unspent remainder, exactly as reverse_credit_lot does.
  insert into customer_credit_ledger (
    wallet_id, customer_id, entry_type, category, amount, lot_id,
    source_type, source_record_id, store_id, effective_date,
    reason, created_by, approved_by)
  values (r.wallet_id, r.customer_id, 'reverse', r.category, v_rem, r.id,
    'credit_lot_provenance_repair', r.id, r.store_id, sg_today(),
    'Replaced by a lot that carries its package (328)', auth.uid(), auth.uid());
  update customer_credit_lots
     set remaining_amount = 0, status = 'reversed', is_locked = true, updated_at = now()
   where id = r.id;
  -- Grant it again with the package as its source.
  v_new := grant_customer_credit(
    r.customer_id, r.category, v_rem, 'credit_package', pk.id, r.store_id,
    r.effective_date, r.reference_no,
    'Credit package (paid so far): ' || pk.name,
    'Replaces lot ' || r.id || ', which carried the wrong source (328)',
    r.original_purchase_date, auth.uid(), r.usage_restrictions);
  insert into credit_package_progress_lots
    (lot_id, invoice_item_id, invoice_id, released_amount, replaces_lot_id)
  values (v_new, r.invoice_item_id, r.invoice_id, 0, r.id);
  return v_new;
end $$;

-- Fixtures: owner, store, cash, wallet method, a S$20 voucher, a S$100 session,
-- and products at S$100 and S$1,000.
do $$
declare own uuid := gen_random_uuid(); sfx text := pg_temp.sfx();
  st uuid; pm uuid; wpm uuid; v uuid; svc uuid; p100 uuid; p1000 uuid;
begin
  insert into auth.users(id,email) values (own,'rcp-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'RCP Owner','rcp-'||sfx||'@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name,code,country_code) values ('RCP Store '||sfx,'RCP-'||sfx,'SG') returning id into st;
  insert into payment_methods(name) values ('RCP Cash '||sfx) returning id into pm;
  select id into wpm from payment_methods where wallet_category = 'paid' and is_system limit 1;
  insert into vouchers(name,code,qty_type,reward_eligible) values ('RCP V '||sfx,'RCP-V-'||sfx,'limited',true) returning id into v;
  insert into voucher_store_stock(voucher_id,store_id,current_qty) values (v,st,500);
  insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values (v,st,20,true);
  svc := (upsert_therapy_service(null,'RCP-S-'||sfx,'RCP Session '||sfx,100,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  insert into products(name,sku,product_type) values ('RCP Item 100 '||sfx,'RCP-I100-'||sfx,'own') returning id into p100;
  insert into products(name,sku,product_type) values ('RCP Item 1000 '||sfx,'RCP-I1000-'||sfx,'own') returning id into p1000;
  insert into store_inventory(store_id,product_id,current_qty) values (st,p100,100),(st,p1000,100);
  perform set_product_prices(st,p100,100,100,'available');
  perform set_product_prices(st,p1000,1000,1000,'available');
  insert into rcp_fx(k,v) values ('own',own),('st',st),('pm',pm),('wpm',wpm),('v',v),('svc',svc),('p100',p100),('p1000',p1000);
end $$;

-- ── 1. two lines of the same premium bundle, settled by one payment ─────────
-- S$1,000 bundle, no bonus, 2 free vouchers, twice on one invoice; 1,200 then
-- 800. Before 356 d the second line's capture found the first line's sale too
-- (sales were matched by invoice and bundle only) and inserted its vouchers a
-- second time: duplicate key on invoice_benefit_voucher_unique, and the final
-- payment rolled back.
do $$
declare pb uuid; c uuid; inv uuid; its uuid[]; v_msg text; r record; n int;
begin
  pb := pg_temp.bundle(1000, 0, 2);
  c := pg_temp.customer('RCP 1');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pb, 2), pg_temp.bundle_line(pb, 2)));
  its := pg_temp.lines(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1200);
  if pg_temp.held(c) <> 1200 or credit_package_released_paid_credit(its[1]) + credit_package_released_paid_credit(its[2]) <> 1200 then
    raise exception 'FAIL 1 (fixture): after 1,200 the customer holds % (released % + %), expected 1,200',
      pg_temp.held(c), credit_package_released_paid_credit(its[1]), credit_package_released_paid_credit(its[2]); end if;
  begin
    perform pg_temp.pay(inv, 800);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 1: the final payment on two lines of the same bundle was refused: %', v_msg;
  end;
  if pg_temp.status(inv) <> 'paid' then raise exception 'FAIL 1: the invoice did not settle (status %)', pg_temp.status(inv); end if;
  raise notice 'PASS 1a: the final payment on two lines of the same bundle goes through (no duplicate voucher benefit)';

  for r in select x.id, invoice_item_external_value(x.id) as ext, pg_temp.benefit_paid(x.id) as paid
             from invoice_items x where x.id = any(its) loop
    if r.ext <> 1000 or r.paid <> r.ext then
      raise exception 'FAIL 1: line % has benefits worth % against its external value % (expected 1,000 each)', r.id, r.paid, r.ext; end if;
  end loop;
  if (select coalesce(sum(b.paid_value),0) from invoice_benefit_values b where b.invoice_id = inv) <> 2000 then
    raise exception 'FAIL 1: the invoice''s benefits are worth % in total, expected 2,000',
      (select sum(b.paid_value) from invoice_benefit_values b where b.invoice_id = inv); end if;
  raise notice 'PASS 1b: each line''s benefits are worth exactly its own 1,000 (2,000 in total)';

  select count(*) into n from premium_bundle_sales s where s.invoice_id = inv;
  if n <> 2 or (select count(distinct s.invoice_item_id) from premium_bundle_sales s where s.invoice_id = inv and s.invoice_item_id = any(its)) <> 2 then
    raise exception 'FAIL 1: expected two sales naming the two lines, got % sale(s): %', n,
      (select jsonb_agg(s.invoice_item_id) from premium_bundle_sales s where s.invoice_id = inv); end if;
  -- Every voucher benefit sits on the line whose sale issued the voucher.
  if exists (select 1 from invoice_benefit_values b
               join customer_reward_vouchers v on v.id = b.reward_voucher_id
               join premium_bundle_sales s on s.id = v.source_id
              where b.invoice_id = inv and s.invoice_item_id is distinct from b.invoice_item_id) then
    raise exception 'FAIL 1: a voucher benefit is recorded against the other line''s sale'; end if;
  if pg_temp.held(c) <> 2000 or pg_temp.granted(c) <> 2000 or pg_temp.vouchers_held(c) <> 4 then
    raise exception 'FAIL 1: the customer ends with % paid credit (granted %) and % vouchers, expected 2,000 and 4',
      pg_temp.held(c), pg_temp.granted(c), pg_temp.vouchers_held(c); end if;
  raise notice 'PASS 1c: each premium_bundle_sales row names its own line, its vouchers are benefits of that line; 2,000 paid + 4 vouchers';
end $$;

-- ── 2. two lines of the same credit package ─────────────────────────────────
-- S$500 / 500 credit, twice; 600 then 400. Line 1 releases 500, line 2 100.
-- Before 356 d/f: line 2's released 100 was valued inside line 1's sale (500
-- for 100 credit), the refund options offered 1,500 on 1,000 received, and the
-- commission source of a released lot matched both sales.
do $$
declare cp uuid; c uuid; inv uuid; its uuid[]; rel2 uuid; b record; src jsonb; v_msg text; opt jsonb;
  v_offer numeric; n int; v_total numeric; v_sources jsonb := '[]'::jsonb; v_left numeric; v_take numeric; s jsonb;
begin
  -- Part payments earn commission once the owner has switched it on (357):
  -- on here so the refund below recalculates commission the way production will.
  update app_settings set instalment_commission_from = sg_today() where id = true;
  cp := pg_temp.package(500);
  c := pg_temp.customer('RCP 2');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cp), pg_temp.package_line(cp)));
  its := pg_temp.lines(inv, 'credit_package');
  perform pg_temp.pay(inv, 600);
  if credit_package_released_paid_credit(its[1]) <> 500 or credit_package_released_paid_credit(its[2]) <> 100 then
    raise exception 'FAIL 2 (fixture): after 600 the lines released % and %, expected 500 and 100',
      credit_package_released_paid_credit(its[1]), credit_package_released_paid_credit(its[2]); end if;
  rel2 := pg_temp.progress_lot(its[2]);
  perform pg_temp.pay(inv, 400);
  if pg_temp.status(inv) <> 'paid' or pg_temp.held(c) <> 1000 or pg_temp.granted(c) <> 1000 then
    raise exception 'FAIL 2 (fixture): settled as % with % held (% granted), expected paid with exactly 1,000',
      pg_temp.status(inv), pg_temp.held(c), pg_temp.granted(c); end if;

  if (select coalesce(sum(x.paid_value),0) from invoice_benefit_values x where x.invoice_id = inv) <> 1000 then
    raise exception 'FAIL 2: the benefits are worth % in total, but 1,000 was received',
      (select sum(x.paid_value) from invoice_benefit_values x where x.invoice_id = inv); end if;
  if pg_temp.benefit_paid(its[1]) <> 500 or pg_temp.benefit_paid(its[2]) <> 500 then
    raise exception 'FAIL 2: the lines'' benefits are worth % and %, expected 500 each', pg_temp.benefit_paid(its[1]), pg_temp.benefit_paid(its[2]); end if;
  if not exists (select 1 from invoice_benefit_values x where x.lot_id = rel2 and x.invoice_item_id = its[2]
                   and x.granted_value = 100 and x.paid_value = 100) then
    raise exception 'FAIL 2: line 2''s released lot is not valued inside its own sale at 100 for 100 credit: %',
      (select jsonb_agg(jsonb_build_object('item', x.invoice_item_id = its[2], 'granted', x.granted_value, 'paid', x.paid_value))
         from invoice_benefit_values x where x.lot_id = rel2); end if;
  if (select count(*) from credit_package_sales s where s.invoice_id = inv and s.invoice_item_id = any(its)) <> 2
     or (select count(distinct s.invoice_item_id) from credit_package_sales s where s.invoice_id = inv) <> 2 then
    raise exception 'FAIL 2: expected two sales naming the two lines: %',
      (select jsonb_agg(s.invoice_item_id) from credit_package_sales s where s.invoice_id = inv); end if;
  raise notice 'PASS 2a: benefits total exactly the 1,000 received, 500 per line; line 2''s released lot is 100 for 100 in its own sale';

  -- Every benefit on a released lot resolves to exactly one sale: its own line's.
  n := 0;
  for b in select x.* from invoice_benefit_values x
            where x.invoice_id = inv
              and exists (select 1 from credit_package_progress_lots pl
                           where pl.invoice_item_id = x.invoice_item_id and credit_lot_current(pl.lot_id) = x.lot_id) loop
    begin
      src := invoice_commission_benefit_source(b.id);
    exception when others then
      get stacked diagnostics v_msg = message_text;
      raise exception 'FAIL 2: the commission source of line %''s released-lot benefit could not be resolved: %', b.invoice_item_id, v_msg;
    end;
    if (src->>'sale_id')::uuid is distinct from (select s.id from credit_package_sales s where s.invoice_item_id = b.invoice_item_id) then
      raise exception 'FAIL 2: the released-lot benefit of line % resolved to sale % instead of its own line''s sale', b.invoice_item_id, src; end if;
    n := n + 1;
  end loop;
  if n <> 2 then raise exception 'FAIL 2: expected 2 released-lot benefits, found %', n; end if;
  raise notice 'PASS 2b: invoice_commission_benefit_source resolves both released-lot benefits to exactly their own line''s sale';

  opt := invoice_refund_options_before_sessions(inv);
  select coalesce(sum((x->>'max_refund')::numeric),0), coalesce(sum((x->>'paid_value')::numeric),0)
    into v_offer, v_total from jsonb_array_elements(opt->'benefits') x;
  if v_offer > 1000 or v_total > 1000 then
    raise exception 'FAIL 2: the refund options offer % (benefits valued %) on an invoice that received 1,000', v_offer, v_total; end if;
  raise notice 'PASS 2c: the refund options never offer more than the 1,000 received (offered %)', v_offer;

  -- The real path: refund everything unused on line 2 (its released lot included).
  -- The refund recalculates commission through invoice_commission_benefit_source.
  select coalesce(sum((x->>'max_refund')::numeric),0) into v_total
    from jsonb_array_elements(opt->'benefits') x where (x->>'invoice_item_id')::uuid = its[2] and (x->>'max_refund')::numeric > 0;
  v_left := v_total;
  for s in select x from jsonb_array_elements(opt->'sources') x where not (x->>'wallet')::boolean
            order by (x->>'remaining')::numeric desc loop
    exit when v_left <= 0;
    v_take := least(v_left, (s->>'remaining')::numeric);
    v_sources := v_sources || jsonb_build_array(jsonb_build_object('payment_id', s->>'payment_id', 'amount', v_take));
    v_left := v_left - v_take;
  end loop;
  begin
    perform refund_invoice_recorded(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', its[2], 'amount', v_total,
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', x->>'id', 'amount', (x->>'max_refund')::numeric))
                       from jsonb_array_elements(opt->'benefits') x
                      where (x->>'invoice_item_id')::uuid = its[2] and (x->>'max_refund')::numeric > 0))),
      v_sources, '[]'::jsonb, 'Refund line 2', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 2: refunding line 2 (its released lot included) was refused: %', v_msg;
  end;
  if v_total <> 500 or (select l.remaining_amount from customer_credit_lots l where l.id = rel2) <> 0 or pg_temp.held(c) <> 500 then
    raise exception 'FAIL 2: refunding line 2 paid % (expected 500), its released lot holds %, the customer %; expected 0 and 500 (line 1)',
      v_total, (select l.remaining_amount from customer_credit_lots l where l.id = rel2), pg_temp.held(c); end if;
  raise notice 'PASS 2d: line 2 refunds for exactly 500, released lot included, with commission recalculated';
end $$;

-- ── 3. a line in the shape 328's repair left ────────────────────────────────
-- S$2,000 package, 800 received and released, then repaired as 328 does: old
-- lot reversed and locked (its row keeps released_amount 800), a replacement
-- lot holds the 800, its row holds 0 and replaces_lot_id = the old lot.
do $$
declare cp uuid; c uuid; inv uuid; it uuid; old_lot uuid; new_lot uuid; v_msg text; n int;
  k int := 0; n_before int := 0; n_after int := 0;
begin
  cp := pg_temp.package(2000);

  -- 3a + 3d: the chain, then settlement.
  c := pg_temp.customer('RCP 3ad');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cp)));
  it := pg_temp.line(inv, 'credit_package');
  perform pg_temp.pay(inv, 800);
  old_lot := pg_temp.progress_lot(it);
  new_lot := pg_temp.repair_328(it);
  if pg_temp.held(c) <> 800 or credit_package_released_paid_credit(it) <> 800
     or (select l.status from customer_credit_lots l where l.id = old_lot) <> 'reversed'
     or not exists (select 1 from credit_package_progress_lots pl where pl.lot_id = new_lot and pl.released_amount = 0 and pl.replaces_lot_id = old_lot) then
    raise exception 'FAIL 3 (fixture): the 328 shape was not built (held %, released %)', pg_temp.held(c), credit_package_released_paid_credit(it); end if;
  if credit_lot_current(old_lot) is distinct from new_lot then
    raise exception 'FAIL 3a: credit_lot_current(old lot) is %, expected the replacement lot', credit_lot_current(old_lot); end if;
  raise notice 'PASS 3a: credit_lot_current follows a 328-repaired lot to its replacement';

  perform pg_temp.pay(inv, 1200);
  if pg_temp.status(inv) <> 'paid' or pg_temp.held(c) <> 2000 or pg_temp.granted(c) <> 2000 then
    raise exception 'FAIL 3d: settled as % with % held (% granted), expected paid with exactly 2,000',
      pg_temp.status(inv), pg_temp.held(c), pg_temp.granted(c); end if;
  if exists (select 1 from invoice_benefit_values b where b.lot_id = old_lot) then
    raise exception 'FAIL 3d: the released-credit benefit was put on the reversed old lot'; end if;
  if not exists (select 1 from invoice_benefit_values b where b.lot_id = new_lot and b.invoice_item_id = it and b.granted_value = 800) then
    raise exception 'FAIL 3d: the replacement lot has no 800 benefit row: %',
      (select jsonb_agg(jsonb_build_object('lot', b.lot_id, 'granted', b.granted_value)) from invoice_benefit_values b where b.invoice_item_id = it); end if;
  if pg_temp.benefit_paid(it) <> 2000 then
    raise exception 'FAIL 3d: the line''s benefits are worth %, expected 2,000', pg_temp.benefit_paid(it); end if;
  begin
    if (invoice_commission_benefit_source((select b.id from invoice_benefit_values b where b.lot_id = new_lot))->>'sale_id')::uuid
       is distinct from (select s.id from credit_package_sales s where s.invoice_item_id = it) then
      raise exception 'FAIL 3d: the replacement lot''s benefit resolves to another sale'; end if;
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL%' then raise; end if;
    raise exception 'FAIL 3d: the commission source of the replacement lot''s benefit could not be resolved: %', v_msg;
  end;
  raise notice 'PASS 3d: settling puts the released-credit benefit on the replacement lot (800), not the reversed old lot, and it traces to the line''s sale';

  -- 3b: removing the line in a correction reclaims the replacement lot's 800.
  -- The reclaim walks the release rows in lot-id order, and the 0 row used to
  -- produce a 0 ledger row when it came first, so this runs until the
  -- replacement lot has sorted both before and after the old one.
  while k < 30 and (k < 4 or n_before = 0 or n_after = 0) loop
    k := k + 1;
    c := pg_temp.customer('RCP 3b #' || k);
    inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cp), pg_temp.product_line(pg_temp.fx('p1000'))));
    it := pg_temp.line(inv, 'credit_package');
    perform pg_temp.pay(inv, 800);
    if credit_package_released_paid_credit(it) <> 800 then
      raise exception 'FAIL 3b (fixture, run %): 800 received released % to the package', k, credit_package_released_paid_credit(it); end if;
    old_lot := pg_temp.progress_lot(it);
    new_lot := pg_temp.repair_328(it);
    if new_lot < old_lot then n_before := n_before + 1; else n_after := n_after + 1; end if;
    begin
      perform correct_invoice(inv,
        jsonb_build_array(pg_temp.product_line(pg_temp.fx('p1000')) || jsonb_build_object('invoice_item_id', pg_temp.line(inv, 'product'))),
        '{}'::jsonb, 'Customer no longer wants the package', gen_random_uuid());
    exception when others then
      get stacked diagnostics v_msg = message_text;
      raise exception 'FAIL 3b (run %, replacement lot sorts % the old one): removing a 328-repaired package line was refused: %',
        k, case when new_lot < old_lot then 'before' else 'after' end, v_msg;
    end;
    if exists (select 1 from invoice_items x where x.id = it) then raise exception 'FAIL 3b (run %): the package line survived', k; end if;
    select count(*) into n from credit_package_progress_lots pl where pl.invoice_item_id = it;
    if n <> 0 then raise exception 'FAIL 3b (run %): % release record(s) of the removed line survive', k, n; end if;
    if pg_temp.held(c) <> 0 or (select l.remaining_amount from customer_credit_lots l where l.id = new_lot) <> 0 then
      raise exception 'FAIL 3b (run %): after removing the line the customer holds % (replacement lot %), expected 0',
        k, pg_temp.held(c), (select l.remaining_amount from customer_credit_lots l where l.id = new_lot); end if;
    if not exists (select 1 from customer_credit_ledger g where g.lot_id = new_lot and g.amount = 800
                     and g.source_type = 'invoice_line_removed_released_credit') then
      raise exception 'FAIL 3b (run %): no ledger row reclaims the 800 from the replacement lot', k; end if;
    if exists (select 1 from customer_credit_ledger g where g.lot_id = old_lot and g.source_type = 'invoice_line_removed_released_credit') then
      raise exception 'FAIL 3b (run %): the reclaim touched the reversed old lot', k; end if;
  end loop;
  if n_before = 0 or n_after = 0 then
    raise exception 'FAIL 3b (fixture): in % runs the replacement lot sorted before the old one % times and after it % times; both orders are needed', k, n_before, n_after; end if;
  raise notice 'PASS 3b: removing the line reclaims the unspent 800 from the replacement lot and the correction succeeds (% runs: replacement sorted first % times, after % times)',
    k, n_before, n_after;

  -- 3c: cancel, then reopen.
  c := pg_temp.customer('RCP 3c');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cp)));
  it := pg_temp.line(inv, 'credit_package');
  perform pg_temp.pay(inv, 800);
  new_lot := pg_temp.repair_328(it);
  perform cancel_invoice_recorded(inv, 'Cancelled in error', gen_random_uuid());
  if pg_temp.held(c) <> 0 or (select l.status from customer_credit_lots l where l.id = new_lot) <> 'reversed' then
    raise exception 'FAIL 3c: after cancelling the customer holds % (replacement lot %), expected 0 and reversed',
      pg_temp.held(c), (select l.status from customer_credit_lots l where l.id = new_lot); end if;
  perform reopen_invoice(inv, 'The cancellation was a mistake', gen_random_uuid());
  if pg_temp.status(inv) <> 'partially_paid' then
    raise exception 'FAIL 3c: reopened as %, expected partially_paid', pg_temp.status(inv); end if;
  if pg_temp.held(c) <> 800 or credit_package_released_paid_credit(it) <> 800 then
    raise exception 'FAIL 3c: after reopening the customer holds % with % released on record; expected 800 for the 800 received',
      pg_temp.held(c), credit_package_released_paid_credit(it); end if;
  perform pg_temp.pay(inv, 1200);
  if pg_temp.status(inv) <> 'paid' or pg_temp.held(c) <> 2000 or pg_temp.granted(c) <> 2000 then
    raise exception 'FAIL 3c: after paying the rest the customer holds % (granted %), expected exactly 2,000', pg_temp.held(c), pg_temp.granted(c); end if;
  raise notice 'PASS 3c: cancel then reopen releases the 800 again (the release record matches the money), and settles at exactly 2,000';
end $$;

-- ── 4. a correction adds a credit line beside one holding released credit ───
-- S$1,000 bundle, 600 received and released; the owner adds a S$1,000
-- package. Before 356 (1) the money was queued by line id alone, so when the
-- package's id sorted first it took the 600 and released it a second time:
-- 1,200 held for 600 received, depending on uuid order. Repeated until both
-- orders have been seen.
do $$
declare pb uuid; cp uuid; c uuid; inv uuid; itb uuid; itp uuid; k int := 0; n_first int := 0; n_after int := 0;
begin
  pb := pg_temp.bundle(1000, 0, 0);
  cp := pg_temp.package(1000);
  while k < 40 and (k < 8 or n_first < 2 or n_after < 2) loop
    k := k + 1;
    c := pg_temp.customer('RCP 4 #' || k);
    inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pb)));
    itb := pg_temp.line(inv, 'premium_bundle');
    perform pg_temp.pay(inv, 600);
    if pg_temp.held(c) <> 600 then
      raise exception 'FAIL 4 (fixture, run %): 600 received released %', k, pg_temp.held(c); end if;
    perform correct_invoice(inv,
      jsonb_build_array(pg_temp.bundle_line(pb) || jsonb_build_object('invoice_item_id', itb), pg_temp.package_line(cp)),
      '{}'::jsonb, 'Customer adds a package', gen_random_uuid());
    itp := pg_temp.line(inv, 'credit_package');
    if itp is null then raise exception 'FAIL 4 (fixture, run %): the package line was not added', k; end if;
    if itp < itb then n_first := n_first + 1; else n_after := n_after + 1; end if;
    if pg_temp.held(c) > 600 or pg_temp.granted(c) > 600 then
      raise exception 'FAIL 4 (run %, package id sorts % the bundle): right after the correction the customer holds % paid credit (granted %) for 600 received',
        k, case when itp < itb then 'before' else 'after' end, pg_temp.held(c), pg_temp.granted(c); end if;
    if credit_package_released_paid_credit(itb) <> 600 or credit_package_released_paid_credit(itp) <> 0 then
      raise exception 'FAIL 4 (run %): released % to the bundle and % to the added package, expected 600 and 0',
        k, credit_package_released_paid_credit(itb), credit_package_released_paid_credit(itp); end if;
  end loop;
  if n_first = 0 then
    raise exception 'FAIL 4 (fixture): in % runs the added line never sorted before the bundle, so the risky order was not exercised', k; end if;
  raise notice 'PASS 4: in % corrections (the added package sorted first % times, after % times) the customer never held more than the 600 received',
    k, n_first, n_after;
end $$;

-- ── 5. a kept line switched to another package ──────────────────────────────
-- Package A is therapy-only (S$2,000), package B allows products (S$1,500);
-- 800 received toward A. The owner switches the same line to B.
do $$
declare cpa uuid; cpb uuid; c uuid; inv uuid; it uuid; lot_a uuid; lot_b uuid; v_msg text;
begin
  cpa := pg_temp.package(2000, false, true);
  cpb := pg_temp.package(1500, true, false);

  -- 5a: nothing spent: A's credit goes back, the money is released under B.
  c := pg_temp.customer('RCP 5a');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cpa)));
  it := pg_temp.line(inv, 'credit_package');
  perform pg_temp.pay(inv, 800);
  lot_a := pg_temp.progress_lot(it);
  if pg_temp.held(c) <> 800 or (select l.source_record_id from customer_credit_lots l where l.id = lot_a) <> cpa then
    raise exception 'FAIL 5a (fixture): expected 800 released under package A, customer holds %', pg_temp.held(c); end if;
  perform correct_invoice(inv, jsonb_build_array(pg_temp.package_line(cpb) || jsonb_build_object('invoice_item_id', it)),
    '{}'::jsonb, 'Customer wants the product package', gen_random_uuid());
  if (select x.credit_package_id from invoice_items x where x.id = it) is distinct from cpb then
    raise exception 'FAIL 5a (fixture): the kept line was not switched to package B'; end if;
  if not exists (select 1 from customer_credit_ledger g where g.lot_id = lot_a and g.amount = 800
                   and g.source_type = 'invoice_line_removed_released_credit') then
    raise exception 'FAIL 5a: package A''s released 800 was not reclaimed (no invoice_line_removed_released_credit row)'; end if;
  if (select l.remaining_amount from customer_credit_lots l where l.id = lot_a) <> 0 then
    raise exception 'FAIL 5a: package A''s lot still holds %', (select l.remaining_amount from customer_credit_lots l where l.id = lot_a); end if;
  lot_b := pg_temp.progress_lot(it);
  if lot_b is null or lot_b = lot_a
     or (select l.source_type || ':' || l.source_record_id from customer_credit_lots l where l.id = lot_b) <> 'credit_package:' || cpb
     or (select l.remaining_amount from customer_credit_lots l where l.id = lot_b) <> 800
     or credit_package_released_paid_credit(it) <> 800 then
    raise exception 'FAIL 5a: the 800 received is not released under package B (lot %, source %, released %)', lot_b,
      (select l.source_type || ':' || l.source_record_id from customer_credit_lots l where l.id = lot_b), credit_package_released_paid_credit(it); end if;
  if not ((select l.usage_restrictions->'allowed_purposes' from customer_credit_lots l where l.id = lot_b) ? 'product') then
    raise exception 'FAIL 5a: the credit released under B does not carry B''s rules (allowed %)',
      (select l.usage_restrictions->'allowed_purposes' from customer_credit_lots l where l.id = lot_b); end if;
  if pg_temp.held(c) <> 800 then
    raise exception 'FAIL 5a: after the switch the customer holds %, expected exactly 800', pg_temp.held(c); end if;
  perform pg_temp.pay(inv, 700);
  if pg_temp.status(inv) <> 'paid' or pg_temp.held(c) <> 1500 or pg_temp.granted(c) <> 1500 then
    raise exception 'FAIL 5a: package B settled as % with % held (% granted), expected exactly 1,500',
      pg_temp.status(inv), pg_temp.held(c), pg_temp.granted(c); end if;
  raise notice 'PASS 5a: switching the line reclaims A''s 800 and releases it under B (its product rules); B settles at exactly 1,500';

  -- 5b: 300 of A's released credit already spent: refused.
  c := pg_temp.customer('RCP 5b');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cpa)));
  it := pg_temp.line(inv, 'credit_package');
  perform pg_temp.pay(inv, 800);
  perform pg_temp.spend(c, 3);
  if pg_temp.held(c) <> 500 then raise exception 'FAIL 5b (fixture): expected 500 left after spending 300, got %', pg_temp.held(c); end if;
  begin
    perform correct_invoice(inv, jsonb_build_array(pg_temp.package_line(cpb) || jsonb_build_object('invoice_item_id', it)),
      '{}'::jsonb, 'Switch after spending', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if v_msg not like 'CREDIT_ALREADY_SPENT%' then
    raise exception 'FAIL 5b: switching a line whose released credit was partly spent should be refused with CREDIT_ALREADY_SPENT, got: %', v_msg; end if;
  if (select x.credit_package_id from invoice_items x where x.id = it) is distinct from cpa
     or credit_package_released_paid_credit(it) <> 800 or pg_temp.held(c) <> 500 then
    raise exception 'FAIL 5b: the refused correction still changed something (package A kept %, released %, held %)',
      (select x.credit_package_id from invoice_items x where x.id = it) = cpa, credit_package_released_paid_credit(it), pg_temp.held(c); end if;
  raise notice 'PASS 5b: switching the package after 300 of A''s credit was spent is refused (CREDIT_ALREADY_SPENT); nothing moved';
end $$;

-- ── 6. a SETTLED part-paid bundle moved to another customer, then cancelled ─
-- Moving a settled invoice empties each lot and issues a replacement to the
-- new customer; the benefit rows stay on the emptied lots. The pre-settlement
-- write-off (writeoff_released_credit_on_close) must leave the released lot to
-- the benefit loops: before 356 c it followed the release record to the
-- replacement and reclaimed it as if the line had never settled.
do $$
declare pb uuid; c1 uuid; c2 uuid; inv uuid; it uuid; rel uuid; repl uuid; ev jsonb;
begin
  pb := pg_temp.bundle(2000, 200, 0);
  c1 := pg_temp.customer('RCP 6 wrong');
  c2 := pg_temp.customer('RCP 6 right');
  inv := pg_temp.invoice(c1, jsonb_build_array(pg_temp.bundle_line(pb)));
  it := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 800);
  rel := pg_temp.progress_lot(it);
  perform pg_temp.pay(inv, 1200);
  if pg_temp.status(inv) <> 'paid' or pg_temp.held(c1) <> 2000 or pg_temp.held(c1, 'bonus') <> 200
     or not exists (select 1 from invoice_benefit_values b where b.lot_id = rel and b.granted_value = 800) then
    raise exception 'FAIL 6 (fixture): expected a settled bundle with 2,000 + 200 and the released 800 as a benefit (status %, held %)',
      pg_temp.status(inv), pg_temp.held(c1); end if;
  perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pb) || jsonb_build_object('invoice_item_id', it)),
    jsonb_build_object('customer_id', c2, 'benefit_action', 'transfer'), 'Sold to the wrong customer', gen_random_uuid());
  repl := credit_lot_current(rel);
  if repl = rel or (select l.customer_id from customer_credit_lots l where l.id = repl) <> c2
     or pg_temp.held(c2) <> 2000 or pg_temp.held(c1) <> 0 then
    raise exception 'FAIL 6 (fixture): the settled credit did not move (new customer holds %, old %)', pg_temp.held(c2), pg_temp.held(c1); end if;

  perform cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  select a.new_data into ev from audit_logs a
   where a.action = 'released_credit_cancel' and a.record_id = inv order by a.created_at desc limit 1;
  if coalesce((ev->>'reclaimed')::numeric, 0) <> 0 then
    raise exception 'FAIL 6: the pre-settlement write-off reclaimed % from a settled line (audit %)', ev->>'reclaimed', ev; end if;
  if exists (select 1 from customer_credit_ledger g where g.source_record_id = inv
               and g.source_type = 'invoice_cancel_released_credit') then
    raise exception 'FAIL 6: the pre-settlement write-off posted % to the ledger for a settled line',
      (select sum(g.amount) from customer_credit_ledger g where g.source_record_id = inv and g.source_type = 'invoice_cancel_released_credit'); end if;
  if coalesce((select pl.released_amount from credit_package_progress_lots pl where pl.lot_id = rel), 0) <> 800 then
    raise exception 'FAIL 6: the cancel changed the settled line''s release record to %',
      (select pl.released_amount from credit_package_progress_lots pl where pl.lot_id = rel); end if;
  raise notice 'PASS 6a: cancelling the moved, settled bundle leaves the released lot to the benefit loops (write-off reclaimed 0: audit %)',
    coalesce(ev::text, 'none written');

  -- What the benefit loops then do. They join invoice_benefit_values.lot_id,
  -- which after a move is the EMPTIED old lot, and do not follow the chain to
  -- the replacement the new customer holds. Not introduced by 355/356: a
  -- bundle paid in one payment, moved and cancelled, leaves the new customer
  -- all of its credit too. 356 c defers the released lot to this loop, so the
  -- released credit now shares the gap. 356's header lists it under NOT
  -- CHANGED (its fix belongs in those loops: follow credit_lot_current).
  -- KNOWN GAP: measured and printed, never asserted and not a failure. The
  -- numbers printed are the gap, not the intended result (which is 0 left with
  -- the new customer). Once the loops are fixed this prints PASS 6b; then make
  -- it a hard check again.
  if pg_temp.held(c2) <> 0 or pg_temp.held(c2, 'bonus') <> 0 then
    raise notice 'KNOWN GAP 6b (pre-existing, documented in 356 NOT CHANGED; not fixed here): after cancelling the moved, settled bundle the new customer still holds % paid (the released lot''s replacement holds % of it) and % bonus, where 0 is intended. cancel_invoice_recorded''s benefit loop reads the benefit rows'' own lots, which the move emptied, and does not follow credit_lot_current. Reported only; not counted as a failure.',
      pg_temp.held(c2), (select l.remaining_amount from customer_credit_lots l where l.id = repl), pg_temp.held(c2, 'bonus');
  else
    raise notice 'PASS 6b: the cancel took back everything the new customer held from the invoice (the 356 NOT CHANGED gap is closed: make this a hard check)';
  end if;
end $$;

-- ── 7. (355) a Make-FOC package kept in a correction keeps its FOC reason ───
-- A saved unpaid invoice: a S$500 package given away with Make FOC and a S$100
-- product. Before 355 round 2 only the presence of FOC was compared, so a
-- correction sending the package with another FOC reason stopped matching,
-- was rewritten at full price and re-charged a package that still said FOC.
do $$
declare cp uuid; c uuid; inv uuid; itp uuid; itx uuid; v_msg text; v_line invoice_items%rowtype;
begin
  cp := pg_temp.package(500);
  c := pg_temp.customer('RCP 7');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cp), pg_temp.product_line(pg_temp.fx('p100'))));
  itp := pg_temp.line(inv, 'credit_package');
  itx := pg_temp.line(inv, 'product');
  perform apply_line_foc(itp, 1, null, 'Staff welfare');
  if (select i.total_amount from invoices i where i.id = inv) <> 100
     or (select x.line_total from invoice_items x where x.id = itp) <> 0 then
    raise exception 'FAIL 7 (fixture): Make FOC did not give the package away'; end if;

  begin
    perform correct_invoice(inv, jsonb_build_array(
      pg_temp.package_line(cp) || jsonb_build_object('invoice_item_id', itp, 'unit_price', 500,
                                                     'foc_quantity', 1, 'foc_reason', 'Birthday gift'),
      pg_temp.product_line(pg_temp.fx('p100'), 2) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'Two of the product', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if position('FOC can only be changed with Make FOC or Undo FOC' in v_msg) = 0 then
    raise exception 'FAIL 7: a correction changing the kept package''s FOC reason should be refused with the Make FOC message, got: %', v_msg; end if;
  select * into v_line from invoice_items x where x.id = itp;
  if v_line.line_total <> 0 or v_line.foc_reason is distinct from 'Staff welfare'
     or (select i.total_amount from invoices i where i.id = inv) <> 100 then
    raise exception 'FAIL 7: the refused correction still changed the invoice (package charged %, reason %, total %)',
      v_line.line_total, v_line.foc_reason, (select i.total_amount from invoices i where i.id = inv); end if;
  raise notice 'PASS 7a: sending the Make-FOC package with another FOC reason is refused ("FOC can only be changed with Make FOC or Undo FOC")';

  begin
    perform correct_invoice(inv, jsonb_build_array(
      pg_temp.package_line(cp) || jsonb_build_object('invoice_item_id', itp, 'unit_price', 500,
                                                     'foc_quantity', 1, 'foc_reason', 'Staff welfare'),
      pg_temp.product_line(pg_temp.fx('p100'), 2) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'Two of the product', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 7: the same correction with the FOC reason unchanged was refused: %', v_msg;
  end;
  select * into v_line from invoice_items x where x.id = itp;
  if v_line.line_total <> 0 or v_line.foc_amount <> 500 or v_line.foc_reason is distinct from 'Staff welfare'
     or (select x.quantity from invoice_items x where x.id = itx) <> 2
     or (select i.total_amount from invoices i where i.id = inv) <> 200 then
    raise exception 'FAIL 7: after the correction the package is charged % (FOC %, reason %), the product quantity %, the invoice total %; expected 0, 500, Staff welfare, 2, 200',
      v_line.line_total, v_line.foc_amount, v_line.foc_reason, (select x.quantity from invoice_items x where x.id = itx),
      (select i.total_amount from invoices i where i.id = inv); end if;
  raise notice 'PASS 7b: the same correction with the reason unchanged goes through; the package stays free (line_total 0) and the invoice totals 200';
end $$;

-- 7c: a saved unpaid invoice with a S$1,000 bundle (2 free vouchers, chosen
-- from two eligible vouchers) given away with Make FOC, and a S$100 product.
-- A correction keeping the bundle's FOC and reason but choosing other vouchers
-- no longer matches the saved line, and a non-matching credit line is rewritten
-- at full price: 355 section 8 refuses any edit of a credit line given free.
-- 7d: a kept package that is NOT free, sent with foc_quantity 1: refused with
-- the same message (FOC changes only through Make FOC); sent as a NEW line it
-- keeps the create-time refusal.
do $$
declare sfx text := pg_temp.sfx(); v2 uuid; pb uuid; cp uuid; c uuid; inv uuid; itb uuid; itp uuid; itx uuid;
  v_msg text; v_line invoice_items%rowtype; v_sel jsonb; v_other jsonb;
begin
  -- A second voucher the bundle's free vouchers may be chosen from.
  insert into vouchers(name,code,qty_type,reward_eligible) values ('RCP V2 '||sfx,'RCP-V2-'||sfx,'limited',true) returning id into v2;
  insert into voucher_store_stock(voucher_id,store_id,current_qty) values (v2,pg_temp.fx('st'),500);
  insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values (v2,pg_temp.fx('st'),20,true);
  pb := pg_temp.bundle(1000, 0, 2);
  insert into premium_bundle_vouchers(bundle_id,voucher_id) values (pb, v2);

  c := pg_temp.customer('RCP 7c');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pb, 2), pg_temp.product_line(pg_temp.fx('p100'))));
  itb := pg_temp.line(inv, 'premium_bundle');
  itx := pg_temp.line(inv, 'product');
  perform apply_line_foc(itb, 1, null, 'Staff welfare');
  select * into v_line from invoice_items x where x.id = itb;
  v_sel := v_line.bundle_voucher_selection;
  if v_line.line_total <> 0 or coalesce(v_line.foc_quantity, 0) <> 1 or v_line.foc_reason is distinct from 'Staff welfare'
     or (select i.total_amount from invoices i where i.id = inv) <> 100 or jsonb_array_length(coalesce(v_sel, '[]'::jsonb)) = 0 then
    raise exception 'FAIL 7c (fixture): Make FOC did not give the bundle away with its voucher choice (line_total %, FOC %, selection %)',
      v_line.line_total, v_line.foc_quantity, v_sel; end if;
  -- The other choice is a complete, valid one: only the FOC rule can refuse it.
  v_other := jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v'), 'quantity', 1),
                               jsonb_build_object('voucher_id', v2, 'quantity', 1));
  if not coalesce((validate_bundle_voucher_selection(pb, pg_temp.fx('st'), v_other)->>'complete')::boolean, false) then
    raise exception 'FAIL 7c (fixture): the other voucher choice is not a complete selection: %',
      validate_bundle_voucher_selection(pb, pg_temp.fx('st'), v_other); end if;

  begin
    perform correct_invoice(inv, jsonb_build_array(
      pg_temp.bundle_line(pb) || jsonb_build_object('invoice_item_id', itb, 'unit_price', 1000,
                                                    'foc_quantity', 1, 'foc_reason', 'Staff welfare', 'voucher_selection', v_other),
      pg_temp.product_line(pg_temp.fx('p100')) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'Customer prefers the other voucher', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if position('FOC can only be changed with Make FOC or Undo FOC' in v_msg) = 0 then
    raise exception 'FAIL 7c: a correction changing the Make-FOC bundle''s voucher choice (FOC and reason unchanged) should be refused with the Make FOC message, got: %', v_msg; end if;
  select * into v_line from invoice_items x where x.id = itb;
  if v_line.line_total <> 0 or coalesce(v_line.foc_quantity, 0) <> 1 or v_line.foc_reason is distinct from 'Staff welfare'
     or v_line.bundle_voucher_selection is distinct from v_sel
     or (select i.total_amount from invoices i where i.id = inv) <> 100 then
    raise exception 'FAIL 7c: the refused correction still changed the invoice (bundle charged %, FOC %, selection %, total %)',
      v_line.line_total, v_line.foc_quantity, v_line.bundle_voucher_selection, (select i.total_amount from invoices i where i.id = inv); end if;

  -- Control: the bundle sent exactly as saved, only the product changed, goes through.
  begin
    perform correct_invoice(inv, jsonb_build_array(
      pg_temp.bundle_line(pb) || jsonb_build_object('invoice_item_id', itb, 'unit_price', 1000,
                                                    'foc_quantity', 1, 'foc_reason', 'Staff welfare', 'voucher_selection', v_sel),
      pg_temp.product_line(pg_temp.fx('p100'), 2) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'Two of the product', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 7c: the same correction with the bundle exactly as saved was refused: %', v_msg;
  end;
  select * into v_line from invoice_items x where x.id = itb;
  if v_line.line_total <> 0 or v_line.bundle_voucher_selection is distinct from v_sel
     or (select i.total_amount from invoices i where i.id = inv) <> 200 then
    raise exception 'FAIL 7c: after the control correction the bundle is charged % with selection % and the invoice totals %; expected 0, unchanged, 200',
      v_line.line_total, v_line.bundle_voucher_selection, (select i.total_amount from invoices i where i.id = inv); end if;
  raise notice 'PASS 7c: another voucher choice on the Make-FOC bundle (FOC and reason unchanged) is refused ("FOC can only be changed with Make FOC or Undo FOC") and changes nothing; the bundle sent as saved goes through and stays free';

  -- 7d: a kept package that is not free.
  cp := pg_temp.package(500);
  c := pg_temp.customer('RCP 7d');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cp), pg_temp.product_line(pg_temp.fx('p100'))));
  itp := pg_temp.line(inv, 'credit_package');
  itx := pg_temp.line(inv, 'product');
  if (select i.total_amount from invoices i where i.id = inv) <> 600 then
    raise exception 'FAIL 7d (fixture): the invoice totals %, expected 600', (select i.total_amount from invoices i where i.id = inv); end if;
  begin
    perform correct_invoice(inv, jsonb_build_array(
      pg_temp.package_line(cp) || jsonb_build_object('invoice_item_id', itp, 'unit_price', 500,
                                                     'foc_quantity', 1, 'foc_reason', 'Staff welfare'),
      pg_temp.product_line(pg_temp.fx('p100')) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'Give the package free', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if position('FOC can only be changed with Make FOC or Undo FOC' in v_msg) = 0 then
    raise exception 'FAIL 7d: making the kept, charged package FOC in a correction should be refused with the Make FOC message, got: %', v_msg; end if;
  select * into v_line from invoice_items x where x.id = itp;
  if v_line.line_total <> 500 or coalesce(v_line.foc_quantity, 0) <> 0 or (select i.total_amount from invoices i where i.id = inv) <> 600 then
    raise exception 'FAIL 7d: the refused correction still changed the invoice (package charged %, FOC %, total %)',
      v_line.line_total, v_line.foc_quantity, (select i.total_amount from invoices i where i.id = inv); end if;

  -- The same package sent as a NEW line (the saved one dropped).
  begin
    perform correct_invoice(inv, jsonb_build_array(
      pg_temp.package_line(cp) || jsonb_build_object('foc_quantity', 1, 'foc_reason', 'Staff welfare'),
      pg_temp.product_line(pg_temp.fx('p100')) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'Give the package free', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if position('cannot be made FOC when the invoice is created' in v_msg) = 0 then
    raise exception 'FAIL 7d: a NEW package line sent as FOC in a correction should keep the create-time refusal, got: %', v_msg; end if;
  if not exists (select 1 from invoice_items x where x.id = itp and x.line_total = 500)
     or (select count(*) from invoice_items x where x.invoice_id = inv) <> 2
     or (select i.total_amount from invoices i where i.id = inv) <> 600 then
    raise exception 'FAIL 7d: the refused new-line correction still changed the invoice (total %)', (select i.total_amount from invoices i where i.id = inv); end if;
  raise notice 'PASS 7d: a kept, charged package sent with foc_quantity 1 is refused ("FOC can only be changed with Make FOC or Undo FOC"); as a new line it keeps "cannot be made FOC when the invoice is created"; nothing changed';
end $$;

-- ── 8. a credit line on a CANCELLED invoice ─────────────────────────────────
-- S$2,000 package and a S$100 product, 800 received and released, 300 of it
-- spent, then cancelled: the cancel reclaims the unspent 500 and writes the
-- spent 300 off, and the release row keeps 300. That row is what a reopen
-- relies on: it releases only the 500 again. Deleting it with the line would
-- let a reopen release the 300 a second time, so 356 refuses:
--   8a. removing the line, or switching it to another package: refused
--       ('was spent before this invoice was cancelled'), nothing changes.
--       Before, the removal went through and the row was deleted.
--   8b. control: nothing spent before the cancel, which reclaimed all 800 and
--       left the row at 0. Removing the line goes through: its release rows go,
--       with an audit row, and the customer's credit is untouched.
--   8c. the reviewer's case: the line removed and the same package added back
--       as a new line is refused too. Reopened and paid in full, the customer
--       ends with exactly the package's 2,000, counting the 300 spent before
--       the cancel. Before, the new line had no release record, the reopen
--       released all 800 again, and the customer ended with 2,300.
do $$
declare cpa uuid; cpb uuid; c uuid; inv uuid; it uuid; itx uuid; lot uuid; ev jsonb; v_msg text; k int;
  v_inv jsonb; v_credit jsonb; v_items jsonb; v_what text;
begin
  cpa := pg_temp.package(2000);
  cpb := pg_temp.package(1500);

  -- 8a: 300 spent before the cancel.
  c := pg_temp.customer('RCP 8a');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cpa), pg_temp.product_line(pg_temp.fx('p100'))));
  it := pg_temp.line(inv, 'credit_package');
  itx := pg_temp.line(inv, 'product');
  perform pg_temp.pay(inv, 800);
  lot := pg_temp.progress_lot(it);
  if credit_package_released_paid_credit(it) <> 800 or pg_temp.held(c) <> 800 then
    raise exception 'FAIL 8a (fixture): 800 received released % (customer holds %), expected 800',
      credit_package_released_paid_credit(it), pg_temp.held(c); end if;
  perform pg_temp.spend(c, 3);
  if pg_temp.held(c) <> 500 then raise exception 'FAIL 8a (fixture): expected 500 left after spending 300, got %', pg_temp.held(c); end if;
  perform cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  select a.new_data into ev from audit_logs a
   where a.action = 'released_credit_cancel' and a.record_id = inv order by a.created_at desc limit 1;
  if pg_temp.status(inv) <> 'cancelled' or pg_temp.held(c) <> 0
     or coalesce((ev->>'reclaimed')::numeric, -1) <> 500 or coalesce((ev->>'written_off')::numeric, -1) <> 300
     or coalesce((select pl.released_amount from credit_package_progress_lots pl where pl.lot_id = lot), 0) <> 300 then
    raise exception 'FAIL 8a (fixture): expected a cancelled invoice that reclaimed 500 and wrote off 300, the release row keeping 300 (status %, held %, audit %, release row %)',
      pg_temp.status(inv), pg_temp.held(c), ev, (select pl.released_amount from credit_package_progress_lots pl where pl.lot_id = lot); end if;
  v_inv := pg_temp.invoice_state(inv);
  v_credit := pg_temp.credit_state(c);
  for k in 1..2 loop
    if k = 1 then
      v_what := 'removing the package line';
      v_items := jsonb_build_array(pg_temp.product_line(pg_temp.fx('p100')) || jsonb_build_object('invoice_item_id', itx));
    else
      v_what := 'switching the line to another package';
      v_items := jsonb_build_array(pg_temp.package_line(cpb) || jsonb_build_object('invoice_item_id', it),
                                   pg_temp.product_line(pg_temp.fx('p100')) || jsonb_build_object('invoice_item_id', itx));
    end if;
    begin
      perform correct_invoice(inv, v_items, '{}'::jsonb, 'Change the package on the cancelled invoice', gen_random_uuid());
      v_msg := 'accepted';
    exception when others then
      get stacked diagnostics v_msg = message_text;
    end;
    if position('was spent before this invoice was cancelled' in v_msg) = 0 then
      raise exception 'FAIL 8a: % on the cancelled invoice (300 spent before the cancel, the release row keeping it) should be refused with "was spent before this invoice was cancelled", got: %',
        v_what, v_msg; end if;
    if pg_temp.invoice_state(inv) <> v_inv or pg_temp.credit_state(c) <> v_credit then
      raise exception 'FAIL 8a: the refused % still changed something (invoice % -> %)', v_what, v_inv, pg_temp.invoice_state(inv); end if;
  end loop;
  raise notice 'PASS 8a: removing the package line from the cancelled invoice (300 spent before the cancel), or switching it to another package, is refused ("was spent before this invoice was cancelled"); the line, its 300 release row and the customer''s credit are unchanged';

  -- 8b: nothing spent before the cancel.
  c := pg_temp.customer('RCP 8b');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cpa), pg_temp.product_line(pg_temp.fx('p100'))));
  it := pg_temp.line(inv, 'credit_package');
  itx := pg_temp.line(inv, 'product');
  perform pg_temp.pay(inv, 800);
  lot := pg_temp.progress_lot(it);
  perform cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  select a.new_data into ev from audit_logs a
   where a.action = 'released_credit_cancel' and a.record_id = inv order by a.created_at desc limit 1;
  if pg_temp.status(inv) <> 'cancelled' or pg_temp.held(c) <> 0
     or coalesce((ev->>'reclaimed')::numeric, -1) <> 800 or coalesce((ev->>'written_off')::numeric, -1) <> 0
     or coalesce((select pl.released_amount from credit_package_progress_lots pl where pl.lot_id = lot), -1) <> 0 then
    raise exception 'FAIL 8b (fixture): expected a cancelled invoice that reclaimed all 800, the release row back at 0 (status %, held %, audit %, release row %)',
      pg_temp.status(inv), pg_temp.held(c), ev, (select pl.released_amount from credit_package_progress_lots pl where pl.lot_id = lot); end if;
  v_credit := pg_temp.credit_state(c);
  begin
    perform correct_invoice(inv, jsonb_build_array(pg_temp.product_line(pg_temp.fx('p100')) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'Remove the package from the cancelled invoice', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 8b: removing the package line from the cancelled invoice (nothing spent, release row at 0) was refused: %', v_msg;
  end;
  if exists (select 1 from invoice_items x where x.id = it) then raise exception 'FAIL 8b: the package line survived'; end if;
  if pg_temp.status(inv) <> 'cancelled' then raise exception 'FAIL 8b: the correction changed the status to %', pg_temp.status(inv); end if;
  if exists (select 1 from credit_package_progress_lots pl where pl.invoice_item_id = it) then
    raise exception 'FAIL 8b: % release row(s) of the removed line survive',
      (select count(*) from credit_package_progress_lots pl where pl.invoice_item_id = it); end if;
  if pg_temp.credit_state(c) <> v_credit then
    raise exception 'FAIL 8b: the removal changed the customer''s credit (held %, new ledger rows: %)', pg_temp.held(c),
      (select jsonb_agg(jsonb_build_object('type', g.source_type, 'amount', g.amount)) from customer_credit_ledger g
        where g.customer_id = c and not (v_credit->'ledger') @> jsonb_build_array(jsonb_build_object('id', g.id))); end if;
  select a.new_data into ev from audit_logs a
   where a.action = 'released_credit_reclaimed_line_removed' and a.record_id = inv order by a.created_at desc limit 1;
  if ev is null or coalesce((ev->>'reclaimed')::numeric, -1) <> 0 or not (ev->'lines') @> to_jsonb(array[it]) then
    raise exception 'FAIL 8b: expected an audit row released_credit_reclaimed_line_removed naming the line with reclaimed 0, got %', ev; end if;
  raise notice 'PASS 8b: with nothing spent before the cancel (release row at 0) the package line comes off the cancelled invoice; its release rows are gone, the customer''s credit is untouched, and the audit records it: %', ev;

  -- 8c: 300 spent; the line removed and the package added back as a new line.
  c := pg_temp.customer('RCP 8c');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.package_line(cpa), pg_temp.product_line(pg_temp.fx('p100'))));
  it := pg_temp.line(inv, 'credit_package');
  itx := pg_temp.line(inv, 'product');
  perform pg_temp.pay(inv, 800);
  perform pg_temp.spend(c, 3);
  perform cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  if pg_temp.status(inv) <> 'cancelled' or pg_temp.held(c) <> 0 or pg_temp.used(c) <> 300
     or credit_package_released_paid_credit(it) <> 300 then
    raise exception 'FAIL 8c (fixture): expected a cancelled invoice with 300 spent and on record (status %, held %, spent %, release record %)',
      pg_temp.status(inv), pg_temp.held(c), pg_temp.used(c), credit_package_released_paid_credit(it); end if;
  v_inv := pg_temp.invoice_state(inv);
  v_credit := pg_temp.credit_state(c);
  begin
    perform correct_invoice(inv, jsonb_build_array(pg_temp.package_line(cpa),
        pg_temp.product_line(pg_temp.fx('p100')) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'Re-enter the package line', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if position('was spent before this invoice was cancelled' in v_msg) = 0 then
    raise exception 'FAIL 8c: removing the package line and adding the same package back as a new line on the cancelled invoice should be refused with "was spent before this invoice was cancelled", got: %', v_msg; end if;
  if pg_temp.invoice_state(inv) <> v_inv or pg_temp.credit_state(c) <> v_credit then
    raise exception 'FAIL 8c: the refused correction still changed something (invoice % -> %)', v_inv, pg_temp.invoice_state(inv); end if;
  perform reopen_invoice(inv, 'The customer came back', gen_random_uuid());
  if pg_temp.status(inv) <> 'partially_paid' or pg_temp.held(c) <> 500 or credit_package_released_paid_credit(it) <> 800 then
    raise exception 'FAIL 8c: after reopening the customer holds % (status %, release record %); expected only the 500 reclaimed at the cancel released again, 800 on record',
      pg_temp.held(c), pg_temp.status(inv), credit_package_released_paid_credit(it); end if;
  perform pg_temp.pay(inv, 1300);
  if pg_temp.status(inv) <> 'paid' or pg_temp.held(c) + pg_temp.used(c) <> credit_line_paid_entitlement(it)
     or credit_line_paid_entitlement(it) <> 2000 or pg_temp.held(c) <> 1700 then
    raise exception 'FAIL 8c: paid in full (status %), the customer holds % and spent % of the line''s credit before the cancel: % in all, expected exactly the line''s % (1,700 held)',
      pg_temp.status(inv), pg_temp.held(c), pg_temp.used(c), pg_temp.held(c) + pg_temp.used(c), credit_line_paid_entitlement(it); end if;
  raise notice 'PASS 8c: removing the package and adding it back as a new line on the cancelled invoice is refused; reopened and paid in full, the customer ends with exactly 2,000 (1,700 held + the 300 spent before the cancel), not 2,300';
end $$;

-- ── 9. a released-lot benefit on an EARLIER lot of the chain ────────────────
-- Two lines of a S$500 package; 600 then 400, so line 1 releases 500 and line
-- 2 100 before settling. The settled invoice is then moved to another customer
-- with benefit_action 'transfer': every lot is emptied and replaced, and the
-- benefit rows stay on the emptied pre-move lots. The released-lot benefit's
-- lot is now the first lot of its chain, not the current one. Before 356 the
-- released-lot branch matched only credit_lot_current(release lot), found no
-- source, and a refund's commission recalculation stopped with 'Commission
-- review required'.
do $$
declare cp uuid; c1 uuid; c2 uuid; inv uuid; its uuid[]; b record; src jsonb; v_msg text; n int := 0;
begin
  cp := pg_temp.package(500);
  c1 := pg_temp.customer('RCP 9 wrong');
  c2 := pg_temp.customer('RCP 9 right');
  inv := pg_temp.invoice(c1, jsonb_build_array(pg_temp.package_line(cp), pg_temp.package_line(cp)));
  its := pg_temp.lines(inv, 'credit_package');
  perform pg_temp.pay(inv, 600);
  perform pg_temp.pay(inv, 400);
  if pg_temp.status(inv) <> 'paid' or pg_temp.held(c1) <> 1000
     or credit_package_released_paid_credit(its[1]) <> 500 or credit_package_released_paid_credit(its[2]) <> 100 then
    raise exception 'FAIL 9 (fixture): expected a settled invoice with 500 and 100 released before settling (status %, held %)',
      pg_temp.status(inv), pg_temp.held(c1); end if;
  perform correct_invoice(inv, jsonb_build_array(
      pg_temp.package_line(cp) || jsonb_build_object('invoice_item_id', its[1]),
      pg_temp.package_line(cp) || jsonb_build_object('invoice_item_id', its[2])),
    jsonb_build_object('customer_id', c2, 'benefit_action', 'transfer'), 'Sold to the wrong customer', gen_random_uuid());
  if pg_temp.held(c2) <> 1000 or pg_temp.held(c1) <> 0 then
    raise exception 'FAIL 9 (fixture): the settled credit did not move (new customer holds %, old %)', pg_temp.held(c2), pg_temp.held(c1); end if;

  for b in select x.*, pl.lot_id as release_lot from invoice_benefit_values x
             join credit_package_progress_lots pl on pl.invoice_item_id = x.invoice_item_id and pl.lot_id = x.lot_id
            where x.invoice_id = inv order by x.invoice_item_id loop
    -- The benefit sits on the pre-move lot; the credit has moved on along the chain.
    if credit_lot_current(b.lot_id) = b.lot_id
       or (select l.customer_id from customer_credit_lots l where l.id = credit_lot_current(b.lot_id)) <> c2 then
      raise exception 'FAIL 9 (fixture): line %''s released lot did not move on (current lot %)', b.invoice_item_id, credit_lot_current(b.lot_id); end if;
    begin
      src := invoice_commission_benefit_source(b.id);
    exception when others then
      get stacked diagnostics v_msg = message_text;
      raise exception 'FAIL 9: the commission source of line %''s released-lot benefit (on the pre-move lot) could not be resolved: %', b.invoice_item_id, v_msg;
    end;
    if (src->>'sale_id')::uuid is distinct from (select s.id from credit_package_sales s where s.invoice_item_id = b.invoice_item_id)
       or src->>'sale_kind' is distinct from 'credit_package'
       or (src->>'invoice_item_id')::uuid is distinct from b.invoice_item_id then
      raise exception 'FAIL 9: line %''s released-lot benefit resolved to % instead of its own line''s sale %',
        b.invoice_item_id, src, (select s.id from credit_package_sales s where s.invoice_item_id = b.invoice_item_id); end if;
    n := n + 1;
  end loop;
  if n <> 2 then raise exception 'FAIL 9: expected a released-lot benefit on each of the 2 lines, found %', n; end if;
  raise notice 'PASS 9: after moving the settled invoice, both released-lot benefits (left on the pre-move lots, credit now on the replacements) resolve to exactly their own line''s sale';
end $$;

-- ── 10. money moving between credit lines without a payment ─────────────────
-- Released credit follows the money counted toward each line, and that queue
-- can shift with no payment at all: a correction withdraws a discount or adds
-- a line. release_credit_package_paid_credit now first takes back the unspent
-- credit released above the money now counted toward its line
-- (trim_released_paid_credit, capped to money), then releases. Before, the
-- correction topped up the line at the head of the queue and left the other
-- line where it was: the same money released twice.
--   10a. S$1,000 package + S$1,000 bundle + S$1,000 product, manual discount
--        300 (900 a line); 900 + 900 received, each credit line releases 900.
--        Withdrawn, each line is 1,000: the head of the queue is owed 1,000,
--        the other 800. It used to end at 1,900 released for 1,800 received.
--   10b. package + bundle, discount 200 (900 each), 1,350 received (900 +
--        450); a correction adds a S$1,000 product, the discount unchanged:
--        each credit line is now 933.33, the head is owed 933.33, the other
--        416.67. It used to end at 1,383.33 released for 1,350.
--   10c. 10a, but the line that must give credit back has only 40 of its 900
--        unspent: the correction still goes through, the 40 comes back, and
--        the 60 already spent stays above the money (credit ahead of payment,
--        squared at settlement). It used to keep all 100 above the money.
do $$
declare cp uuid; pb uuid; c uuid; inv uuid; x record; v_msg text; q1 uuid; q2 uuid; lot2 uuid; t uuid;
begin
  cp := pg_temp.package(1000);
  pb := pg_temp.bundle(1000, 0, 0);

  -- 10a: the discount withdrawn.
  c := pg_temp.customer('RCP 10a');
  inv := pg_temp.dinvoice(c, jsonb_build_array(pg_temp.package_line(cp), pg_temp.bundle_line(pb),
                                               pg_temp.product_line(pg_temp.fx('p1000'))), 300);
  perform pg_temp.pay(inv, 900);
  perform pg_temp.pay(inv, 900);
  if (select i.total_amount from invoices i where i.id = inv) <> 2700 or pg_temp.held(c) <> 1800
     or credit_package_released_paid_credit(pg_temp.line(inv, 'credit_package')) <> 900
     or credit_package_released_paid_credit(pg_temp.line(inv, 'premium_bundle')) <> 900 then
    raise exception 'FAIL 10a (fixture): expected 2,700 due and 900 released to each credit line for 1,800 received (total %, held %, lines %)',
      (select i.total_amount from invoices i where i.id = inv), pg_temp.held(c), pg_temp.credit_lines(inv); end if;
  begin
    perform correct_invoice(inv, pg_temp.kept(inv), jsonb_build_object('manual_discount', 0), 'Discount withdrawn', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 10a: withdrawing the discount was refused: %', v_msg;
  end;
  if (select i.manual_discount from invoices i where i.id = inv) <> 0 or (select i.paid_amount from invoices i where i.id = inv) <> 1800 then
    raise exception 'FAIL 10a (fixture): the correction left manual discount % and % received, expected 0 and 1,800',
      (select i.manual_discount from invoices i where i.id = inv), (select i.paid_amount from invoices i where i.id = inv); end if;
  if pg_temp.released(inv) > 1800 or pg_temp.held(c) > 1800 then
    raise exception 'FAIL 10a: after withdrawing the discount % paid credit is released (the customer holds %) for 1,800 received: %',
      pg_temp.released(inv), pg_temp.held(c), pg_temp.credit_lines(inv); end if;
  for x in select ii.line_kind, credit_package_released_paid_credit(ii.id) as rel, credit_package_money_toward_line(ii.id) as money,
                  credit_line_paid_entitlement(ii.id) as entitled
             from invoice_items ii where ii.invoice_id = inv and ii.line_kind in ('credit_package','premium_bundle') loop
    if x.rel > x.money then
      raise exception 'FAIL 10a: the % line holds % released for % of money counted toward it: %', x.line_kind, x.rel, x.money, pg_temp.credit_lines(inv); end if;
    if x.rel <> least(x.money, x.entitled) then
      raise exception 'FAIL 10a: the % line holds % released, expected the % counted toward it: %', x.line_kind, x.rel, least(x.money, x.entitled), pg_temp.credit_lines(inv); end if;
  end loop;
  if pg_temp.released(inv) <> 1800 or pg_temp.held(c) <> 1800 then
    raise exception 'FAIL 10a: expected exactly the 1,800 received released and held, got % released, % held', pg_temp.released(inv), pg_temp.held(c); end if;
  raise notice 'PASS 10a: withdrawing the discount moves 100 from the line now owed 800 to the line owed 1,000; 1,800 released for 1,800 received: %', pg_temp.credit_lines(inv);

  -- 10b: a line added, the discount unchanged.
  c := pg_temp.customer('RCP 10b');
  inv := pg_temp.dinvoice(c, jsonb_build_array(pg_temp.package_line(cp), pg_temp.bundle_line(pb)), 200);
  perform pg_temp.pay(inv, 1350);
  if pg_temp.released(inv) <> 1350 or pg_temp.held(c) <> 1350 then
    raise exception 'FAIL 10b (fixture): 1,350 received released % (held %), expected 1,350: %', pg_temp.released(inv), pg_temp.held(c), pg_temp.credit_lines(inv); end if;
  begin
    perform correct_invoice(inv, pg_temp.kept(inv) || jsonb_build_array(pg_temp.product_line(pg_temp.fx('p1000'))),
      '{}'::jsonb, 'Customer adds a product', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 10b: adding a product line was refused: %', v_msg;
  end;
  if (select i.manual_discount from invoices i where i.id = inv) <> 200 or (select i.paid_amount from invoices i where i.id = inv) <> 1350
     or pg_temp.line(inv, 'product') is null then
    raise exception 'FAIL 10b (fixture): expected the product added with the discount 200 and 1,350 received unchanged'; end if;
  if pg_temp.released(inv) > 1350 or pg_temp.held(c) > 1350 then
    raise exception 'FAIL 10b: after adding the product % paid credit is released (the customer holds %) for 1,350 received: %',
      pg_temp.released(inv), pg_temp.held(c), pg_temp.credit_lines(inv); end if;
  for x in select ii.line_kind, credit_package_released_paid_credit(ii.id) as rel, credit_package_money_toward_line(ii.id) as money,
                  credit_line_paid_entitlement(ii.id) as entitled
             from invoice_items ii where ii.invoice_id = inv and ii.line_kind in ('credit_package','premium_bundle') loop
    if x.rel > x.money or x.rel <> least(x.money, x.entitled) then
      raise exception 'FAIL 10b: the % line holds % released for % of money counted toward it (entitled %): %',
        x.line_kind, x.rel, x.money, x.entitled, pg_temp.credit_lines(inv); end if;
  end loop;
  if pg_temp.released(inv) <> 1350 or pg_temp.held(c) <> 1350 then
    raise exception 'FAIL 10b: expected exactly the 1,350 received released and held, got % released, % held', pg_temp.released(inv), pg_temp.held(c); end if;
  raise notice 'PASS 10b: adding a product (each credit line now 933.33) moves 33.33 between the lines; 1,350 released for 1,350 received: %', pg_temp.credit_lines(inv);

  -- 10c: the line giving credit back has spent all but 40 of it.
  c := pg_temp.customer('RCP 10c');
  inv := pg_temp.dinvoice(c, jsonb_build_array(pg_temp.package_line(cp), pg_temp.bundle_line(pb),
                                               pg_temp.product_line(pg_temp.fx('p1000'))), 300);
  perform pg_temp.pay(inv, 900);
  -- The head of the queue took the first 900; all of it is spent.
  select pl.invoice_item_id into q1 from credit_package_progress_lots pl where pl.invoice_id = inv;
  perform pg_temp.spend(c, 9);
  perform pg_temp.pay(inv, 900);
  select ii.id into q2 from invoice_items ii
   where ii.invoice_id = inv and ii.line_kind in ('credit_package','premium_bundle') and ii.id <> q1;
  lot2 := pg_temp.progress_lot(q2);
  -- 860 of the second line's 900 spent: 800 in sessions, then 60 toward one more.
  perform pg_temp.spend(c, 8);
  t := pg_temp.invoice(c, jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',pg_temp.fx('svc'),'quantity',1)));
  perform record_invoice_payment(t, jsonb_build_array(jsonb_build_object('payment_method_id',pg_temp.fx('wpm'),'amount',60)), gen_random_uuid());
  if pg_temp.held(c) <> 40 or (select l.remaining_amount from customer_credit_lots l where l.id = lot2) <> 40
     or credit_package_released_paid_credit(q1) <> 900 or credit_package_released_paid_credit(q2) <> 900 or pg_temp.used(c) <> 1760 then
    raise exception 'FAIL 10c (fixture): expected 900 released to each line, 1,760 spent and 40 left on the second line''s lot (held %, lot %, spent %, lines %)',
      pg_temp.held(c), (select l.remaining_amount from customer_credit_lots l where l.id = lot2), pg_temp.used(c), pg_temp.credit_lines(inv); end if;
  begin
    perform correct_invoice(inv, pg_temp.kept(inv), jsonb_build_object('manual_discount', 0), 'Discount withdrawn', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 10c: withdrawing the discount after the released credit was spent was refused: %', v_msg;
  end;
  if credit_package_money_toward_line(q1) <> 1000 or credit_package_money_toward_line(q2) <> 800
     or (select i.paid_amount from invoices i where i.id = inv) <> 1800 then
    raise exception 'FAIL 10c (fixture): expected 1,000 and 800 of the 1,800 received counted toward the lines: %', pg_temp.credit_lines(inv); end if;
  if pg_temp.released(inv) - 1800 <> 60 or credit_package_released_paid_credit(q2) - credit_package_money_toward_line(q2) <> 60 then
    raise exception 'FAIL 10c: % stays released above the 1,800 received (the second line % above its money); expected exactly the 60 spent beyond its 800: %',
      pg_temp.released(inv) - 1800, credit_package_released_paid_credit(q2) - credit_package_money_toward_line(q2), pg_temp.credit_lines(inv); end if;
  if (select l.remaining_amount from customer_credit_lots l where l.id = lot2) <> 0
     or not exists (select 1 from customer_credit_ledger g where g.lot_id = lot2 and g.amount = 40
                      and g.entry_type = 'adjust_decrease' and g.source_type = 'invoice_payment_released_credit') then
    raise exception 'FAIL 10c: the unspent 40 was not taken back from the second line''s lot (it holds %)',
      (select l.remaining_amount from customer_credit_lots l where l.id = lot2); end if;
  if credit_package_released_paid_credit(q1) <> 1000 or pg_temp.held(c) <> 100 then
    raise exception 'FAIL 10c: the head of the queue holds % released (expected its 1,000) and the customer % (expected the 100 released to it)',
      credit_package_released_paid_credit(q1), pg_temp.held(c); end if;
  perform pg_temp.pay(inv, 1200);
  if pg_temp.status(inv) <> 'paid' or pg_temp.held(c) + pg_temp.used(c) <> 2000 then
    raise exception 'FAIL 10c: paid in full (status %), the customer holds % and spent %: % in all, expected exactly the two lines'' 2,000',
      pg_temp.status(inv), pg_temp.held(c), pg_temp.used(c), pg_temp.held(c) + pg_temp.used(c); end if;
  raise notice 'PASS 10c: with 860 of the second line''s 900 spent, withdrawing the discount still goes through: the unspent 40 comes back and exactly the 60 spent beyond its money stays ahead of payment; settled, the customer has exactly 2,000 (% held + % spent)',
    pg_temp.held(c), pg_temp.used(c);
end $$;

-- ── 11. a correction may not make a SETTLED credit line worth more ──────────
-- A S$1,000 bundle (bonus 100) with a manual discount of 200, paid 800: it
-- settles with 800 paid credit (premium_bundle_sales.paid_credit_snapshot)
-- and its 100 bonus. Withdrawing the discount would make the line worth 1,000
-- of paid credit and ask for 200 more, but a settled line is never issued
-- again, so that money would buy nothing: refused with CREDIT_LINE_SETTLED.
-- Before, it went through and left the invoice part-paid. A correction to the
-- notes and 'Served by' runs the same check (it rewrites the lines) and still
-- goes through, because the line is worth what it was issued at. The same for
-- a S$1,000 credit package (credit_package_sales.credit_snapshot).
do $$
declare pb uuid; cp uuid; c uuid; inv uuid; it uuid; k int; v_kind text; v_msg text; v_inv jsonb; v_credit jsonb; v_settled numeric;
begin
  pb := pg_temp.bundle(1000, 100, 0);
  cp := pg_temp.package(1000);
  for k in 1..2 loop
    v_kind := case k when 1 then 'premium_bundle' else 'credit_package' end;
    c := pg_temp.customer('RCP 11 ' || v_kind);
    inv := pg_temp.dinvoice(c, jsonb_build_array(case k when 1 then pg_temp.bundle_line(pb) else pg_temp.package_line(cp) end), 200);
    it := pg_temp.line(inv, v_kind);
    perform pg_temp.pay(inv, 800);
    v_settled := case k when 1 then (select s.paid_credit_snapshot from premium_bundle_sales s where s.invoice_item_id = it)
                        else (select s.credit_snapshot from credit_package_sales s where s.invoice_item_id = it) end;
    if pg_temp.status(inv) <> 'paid' or v_settled is distinct from 800 or credit_line_paid_entitlement(it) <> 800
       or pg_temp.held(c) <> 800 or pg_temp.held(c, 'bonus') <> (case k when 1 then 100 else 0 end) then
      raise exception 'FAIL 11 (% fixture): expected a settled line issued 800 paid credit (status %, sale snapshot %, entitled %, held %, bonus %)',
        v_kind, pg_temp.status(inv), v_settled, credit_line_paid_entitlement(it), pg_temp.held(c), pg_temp.held(c, 'bonus'); end if;
    v_inv := pg_temp.invoice_state(inv);
    v_credit := pg_temp.credit_state(c);

    begin
      perform correct_invoice(inv, pg_temp.kept(inv), jsonb_build_object('manual_discount', 0), 'Discount withdrawn', gen_random_uuid());
      v_msg := 'accepted';
    exception when others then
      get stacked diagnostics v_msg = message_text;
    end;
    if v_msg not like 'CREDIT_LINE_SETTLED%' then
      raise exception 'FAIL 11 (%): withdrawing the discount on the settled line (issued 800) should be refused with CREDIT_LINE_SETTLED, got: % (invoice now %)',
        v_kind, v_msg, pg_temp.invoice_state(inv)->'invoice'; end if;
    if pg_temp.invoice_state(inv) <> v_inv or pg_temp.credit_state(c) <> v_credit then
      raise exception 'FAIL 11 (%): the refused correction still changed something (invoice % -> %)', v_kind, v_inv, pg_temp.invoice_state(inv); end if;

    begin
      perform correct_invoice(inv, pg_temp.kept(inv),
        jsonb_build_object('notes', 'RCP served by corrected', 'service_staff', jsonb_build_array(pg_temp.fx('own'))),
        'Served by corrected', gen_random_uuid());
    exception when others then
      get stacked diagnostics v_msg = message_text;
      raise exception 'FAIL 11 (%): correcting the notes and Served by on the invoice with the settled line was refused: %', v_kind, v_msg;
    end;
    if (select i.notes from invoices i where i.id = inv) is distinct from 'RCP served by corrected'
       or not exists (select 1 from invoice_service_staff s where s.invoice_id = inv and s.staff_id = pg_temp.fx('own'))
       or (select i.manual_discount from invoices i where i.id = inv) <> 200
       or (select i.total_amount from invoices i where i.id = inv) <> 800
       or pg_temp.status(inv) <> 'paid' or pg_temp.credit_state(c) <> v_credit then
      raise exception 'FAIL 11 (%): after correcting Served by the invoice is % with % staff and the customer''s credit changed: %',
        v_kind, pg_temp.invoice_state(inv)->'invoice', (select count(*) from invoice_service_staff s where s.invoice_id = inv),
        pg_temp.credit_state(c) <> v_credit; end if;
  end loop;
  raise notice 'PASS 11: withdrawing the discount on a settled bundle and a settled package (each issued 800) is refused with CREDIT_LINE_SETTLED and changes nothing; correcting the notes and Served by on the same invoices still goes through';
end $$;

-- ── 11b. changing ANOTHER line is not refused; raising the settled line is ──
-- A S$1,000 bundle and 2 x S$100 product with a manual discount of 200, paid
-- in full, so the bundle settles at its share (833.33). Raising the product
-- quantity re-spreads the same discount, so the bundle's share grows a little
-- (846.15) though nothing about it or the discount changed: that correction
-- goes through (the check runs for every settled line only when the invoice's
-- discounts change). Raising the bundle's own price is still refused.
do $$
declare pb uuid; c uuid; inv uuid; it uuid; itx uuid; v_msg text; v_settled numeric;
begin
  pb := pg_temp.bundle(1000, 100, 0);
  c := pg_temp.customer('RCP 11b');
  inv := pg_temp.dinvoice(c, jsonb_build_array(pg_temp.bundle_line(pb), pg_temp.product_line(pg_temp.fx('p100'), 2)), 200);
  it := pg_temp.line(inv, 'premium_bundle'); itx := pg_temp.line(inv, 'product');
  perform pg_temp.pay(inv, (select i.total_amount from invoices i where i.id = inv));
  v_settled := (select s.paid_credit_snapshot from premium_bundle_sales s where s.invoice_item_id = it);
  if pg_temp.status(inv) <> 'paid' or v_settled is null then
    raise exception 'FAIL 11b fixture: expected a settled bundle (status %, snapshot %)', pg_temp.status(inv), v_settled; end if;

  begin
    perform correct_invoice(inv, jsonb_build_array(
        pg_temp.bundle_line(pb) || jsonb_build_object('invoice_item_id', it),
        pg_temp.product_line(pg_temp.fx('p100'), 3) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'One more product', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 11b: raising the product quantity (discount unchanged) was refused: %', v_msg;
  end;
  if (select i.quantity from invoice_items i where i.id = itx) <> 3 or credit_line_paid_entitlement(it) <= v_settled then
    raise exception 'FAIL 11b: expected the product at 3 and the bundle''s share above its settled % (now %)',
      v_settled, credit_line_paid_entitlement(it); end if;

  begin
    perform correct_invoice(inv, jsonb_build_array(
        pg_temp.bundle_line(pb) || jsonb_build_object('invoice_item_id', it, 'unit_price', 1100),
        pg_temp.product_line(pg_temp.fx('p100'), 3) || jsonb_build_object('invoice_item_id', itx)),
      '{}'::jsonb, 'Bundle price raised', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if v_msg not like 'CREDIT_LINE_SETTLED%' then
    raise exception 'FAIL 11b: raising the settled bundle''s own price should be refused with CREDIT_LINE_SETTLED, got: %', v_msg; end if;
  raise notice 'PASS 11b: raising another line''s quantity on a discounted invoice goes through (the settled bundle''s share moves from % to %); raising the settled bundle''s own price is refused',
    v_settled, credit_line_paid_entitlement(it);
end $$;

-- ── 12. a refund on an open invoice keeps its own rules ─────────────────────
-- release_credit_package_paid_credit first takes back released credit above
-- the money now counted toward each line (10), and a refund lowers the money
-- received too. But a refund keeps its own rules: refunding part of an open
-- invoice does not take released credit back (356 NOT CHANGED), so the leading
-- trim is skipped when a refund of the invoice is recorded in the same
-- transaction, exactly as the payment trigger's own trim is. Before, the refund
-- set off the trim, and the credit taken back came from ANOTHER credit line.
--   12a. Bundle A (S$1,000) paid in full and settled; a correction adds bundle
--        B (S$1,000) and 500 more is received, released to B. S$300 of A's
--        unused benefit is refunded: A's lot gives back its 300, B keeps its
--        500, and the customer holds 700 + 500. It used to trim B to the 200
--        then counted toward it (1,200 received, A's 1,000 ahead of it).
--   12b. Bundle (S$1,000) and a S$1,000 product, 1,200 received (the bundle,
--        first in the money queue, releases its 1,000); the PRODUCT line is
--        refunded (1,000). The bundle keeps its 1,000. It used to be trimmed to
--        the 200 left.
do $$
declare pa uuid; pb uuid; c uuid; inv uuid; ia uuid; ib uuid; ix uuid; lot_a uuid; lot_b uuid; opt jsonb; v_msg text;
  v_total numeric; v_left numeric; v_take numeric; v_sources jsonb := '[]'::jsonb; s jsonb; v_credit jsonb;
begin
  pa := pg_temp.bundle(1000, 0, 0);
  pb := pg_temp.bundle(1000, 0, 0);

  -- 12a: 300 of the settled bundle's benefit refunded.
  c := pg_temp.customer('RCP 12a');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pa)));
  ia := pg_temp.line(inv, 'premium_bundle');
  perform pg_temp.pay(inv, 1000);
  perform correct_invoice(inv, pg_temp.kept(inv) || jsonb_build_array(pg_temp.bundle_line(pb)),
    '{}'::jsonb, 'Customer adds a second bundle', gen_random_uuid());
  ib := (select x.id from invoice_items x where x.invoice_id = inv and x.line_kind = 'premium_bundle' and x.id <> ia);
  perform pg_temp.pay(inv, 500);
  lot_a := (select s.paid_credit_lot_id from premium_bundle_sales s where s.invoice_item_id = ia);
  lot_b := pg_temp.progress_lot(ib);
  if pg_temp.status(inv) <> 'partially_paid' or (select x.credit_issued_at from invoice_items x where x.id = ia) is null
     or credit_package_released_paid_credit(ib) <> 500 or pg_temp.held(c) <> 1500
     or (select l.remaining_amount from customer_credit_lots l where l.id = lot_a) <> 1000 then
    raise exception 'FAIL 12a (fixture): expected A settled (1,000 held on its lot) and B released 500 of the 500 received (status %, held %, lines %)',
      pg_temp.status(inv), pg_temp.held(c), pg_temp.credit_lines(inv); end if;

  -- The real path, as in 2: 300 of A's unused benefit, from the payments on record.
  opt := invoice_refund_options_before_sessions(inv);
  if (select count(*) from jsonb_array_elements(opt->'benefits') x
       where (x->>'invoice_item_id')::uuid = ia and (x->>'lot_id')::uuid = lot_a and (x->>'max_refund')::numeric >= 300) <> 1 then
    raise exception 'FAIL 12a (fixture): the refund options do not offer 300 of A''s benefit: %', opt->'benefits'; end if;
  v_total := 300; v_left := v_total;
  for s in select x from jsonb_array_elements(opt->'sources') x where not (x->>'wallet')::boolean
            order by (x->>'remaining')::numeric desc loop
    exit when v_left <= 0;
    v_take := least(v_left, (s->>'remaining')::numeric);
    v_sources := v_sources || jsonb_build_array(jsonb_build_object('payment_id', s->>'payment_id', 'amount', v_take));
    v_left := v_left - v_take;
  end loop;
  begin
    perform refund_invoice_recorded(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', ia, 'amount', v_total,
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', x->>'id', 'amount', v_total))
                       from jsonb_array_elements(opt->'benefits') x where (x->>'lot_id')::uuid = lot_a))),
      v_sources, '[]'::jsonb, 'Customer returns 300 of the first bundle', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 12a: refunding 300 of the settled bundle''s benefit was refused: %', v_msg;
  end;
  if (select i.paid_amount from invoices i where i.id = inv) <> 1200 or pg_temp.status(inv) <> 'partially_paid'
     or (select l.remaining_amount from customer_credit_lots l where l.id = lot_a) <> 700 then
    raise exception 'FAIL 12a (fixture): expected the refund to leave 1,200 received on an open invoice and A''s lot at 700 (received %, status %, A''s lot %)',
      (select i.paid_amount from invoices i where i.id = inv), pg_temp.status(inv),
      (select l.remaining_amount from customer_credit_lots l where l.id = lot_a); end if;
  if credit_package_released_paid_credit(ib) <> 500 or (select l.remaining_amount from customer_credit_lots l where l.id = credit_lot_current(lot_b)) <> 500
     or exists (select 1 from customer_credit_ledger g where g.lot_id = any(credit_lot_chain(lot_b)) and g.entry_type = 'adjust_decrease') then
    raise exception 'FAIL 12a: refunding 300 of A''s benefit took released credit back from B: B released %, its lot holds %, taken back % (expected 500, 500, 0): %',
      credit_package_released_paid_credit(ib), (select l.remaining_amount from customer_credit_lots l where l.id = credit_lot_current(lot_b)),
      (select coalesce(sum(g.amount),0) from customer_credit_ledger g where g.lot_id = any(credit_lot_chain(lot_b)) and g.entry_type = 'adjust_decrease'),
      pg_temp.credit_lines(inv); end if;
  if pg_temp.held(c) <> 1200 then
    raise exception 'FAIL 12a: after the refund the customer holds %, expected 700 (A) + 500 (B)', pg_temp.held(c); end if;
  raise notice 'PASS 12a: refunding 300 of the settled bundle A''s benefit takes back only A''s 300; B keeps its 500 released, the customer holds 700 + 500';

  -- 12b: the product line refunded on a part-paid invoice.
  c := pg_temp.customer('RCP 12b');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pb), pg_temp.product_line(pg_temp.fx('p1000'))));
  ib := pg_temp.line(inv, 'premium_bundle');
  ix := pg_temp.line(inv, 'product');
  perform pg_temp.pay(inv, 1200);
  lot_b := pg_temp.progress_lot(ib);
  if pg_temp.status(inv) <> 'partially_paid' or credit_package_released_paid_credit(ib) <> 1000 or pg_temp.held(c) <> 1000 then
    raise exception 'FAIL 12b (fixture): expected the bundle to release its 1,000 from the 1,200 received (status %, held %, lines %)',
      pg_temp.status(inv), pg_temp.held(c), pg_temp.credit_lines(inv); end if;
  opt := invoice_refund_options_before_sessions(inv);
  if coalesce((select (x->>'remaining')::numeric from jsonb_array_elements(opt->'lines') x where (x->>'invoice_item_id')::uuid = ix), 0) < 1000 then
    raise exception 'FAIL 12b (fixture): the refund options do not offer the product line''s 1,000: %', opt->'lines'; end if;
  v_credit := pg_temp.credit_state(c);
  begin
    perform refund_invoice_recorded(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', ix, 'amount', 1000)),
      jsonb_build_array(jsonb_build_object('payment_id', (select x->>'payment_id' from jsonb_array_elements(opt->'sources') x
                                                            where not (x->>'wallet')::boolean order by (x->>'remaining')::numeric desc limit 1),
                                           'amount', 1000)),
      '[]'::jsonb, 'Product returned', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 12b: refunding the product line was refused: %', v_msg;
  end;
  if (select i.paid_amount from invoices i where i.id = inv) <> 200 or pg_temp.status(inv) <> 'partially_paid' then
    raise exception 'FAIL 12b (fixture): expected the refund to leave 200 received on an open invoice (received %, status %)',
      (select i.paid_amount from invoices i where i.id = inv), pg_temp.status(inv); end if;
  if credit_package_released_paid_credit(ib) <> 1000 or pg_temp.held(c) <> 1000 or pg_temp.credit_state(c) <> v_credit then
    raise exception 'FAIL 12b: refunding the product line changed the bundle''s released credit: released %, held %, taken back % (expected 1,000, 1,000, 0): %',
      credit_package_released_paid_credit(ib), pg_temp.held(c),
      (select coalesce(sum(g.amount),0) from customer_credit_ledger g where g.customer_id = c and g.entry_type = 'adjust_decrease'),
      pg_temp.credit_lines(inv); end if;
  raise notice 'PASS 12b: refunding the product line of the part-paid invoice leaves the bundle''s 1,000 released and the customer''s credit untouched';
end $$;

-- ── 13. the settled-line check: worth before the correction, and NULL = 0 ────
-- refuse_settled_credit_line_raise refuses a settled line only when the
-- correction makes it worth more than BOTH what it was issued at and what it
-- was worth just before this correction (correct_invoice reads that before it
-- rewrites the lines); and correct_invoice's "did the discounts change" test
-- reads a missing manual discount, Save Earth flag or amount as none
-- (coalesce(manual_discount,0), coalesce(save_earth_applied,false),
-- coalesce(save_earth_amount,0)).
--   13a. 11b's fixture, then a third product added (accepted: the bundle's
--        share re-spreads from the 833.33 it was issued at to 846.15). Raising
--        the manual discount to 210 LOWERS the share to 838.46: above the
--        833.33 issued, but below the 846.15 it was worth before, so it goes
--        through. It used to be refused (CREDIT_LINE_SETTLED), because an
--        earlier, allowed re-spread already had the line above its issue value.
--        Withdrawing the discount entirely (share 1,000) is still refused.
--   13b. A S$1,000 package and 2 x S$100 product with a S$200 discount voucher
--        and manual_discount NULL (the column has no default; older invoices
--        and create_credit_purchase_invoice leave it NULL), paid in full: the
--        package settles at 833.33. The till sends the whole header back,
--        manual_discount 0 included. With the voucher unchanged, a correction
--        adding a product only re-spreads the discount (846.15) and goes
--        through, as in 11b. It used to be refused: NULL against 0 counted as
--        a discount change, so every settled line was checked against its
--        issue value.
do $$
declare pb uuid; cp uuid; vd uuid; c uuid; inv uuid; it uuid; itx uuid; v_msg text; v_settled numeric; v_before numeric;
  v_inv jsonb; v_credit jsonb;
begin
  -- 13a
  pb := pg_temp.bundle(1000, 100, 0);
  c := pg_temp.customer('RCP 13a');
  inv := pg_temp.dinvoice(c, jsonb_build_array(pg_temp.bundle_line(pb), pg_temp.product_line(pg_temp.fx('p100'), 2)), 200);
  it := pg_temp.line(inv, 'premium_bundle'); itx := pg_temp.line(inv, 'product');
  perform pg_temp.pay(inv, (select i.total_amount from invoices i where i.id = inv));
  v_settled := (select s.paid_credit_snapshot from premium_bundle_sales s where s.invoice_item_id = it);
  perform correct_invoice(inv, jsonb_build_array(
      pg_temp.bundle_line(pb) || jsonb_build_object('invoice_item_id', it),
      pg_temp.product_line(pg_temp.fx('p100'), 3) || jsonb_build_object('invoice_item_id', itx)),
    '{}'::jsonb, 'One more product', gen_random_uuid());
  v_before := credit_line_paid_entitlement(it);
  if v_settled <> 833.33 or round(v_before, 2) <> 846.15 or (select i.manual_discount from invoices i where i.id = inv) <> 200 then
    raise exception 'FAIL 13a (fixture): expected the bundle issued at 833.33 and worth 846.15 after the third product (issued %, worth %)',
      v_settled, v_before; end if;
  begin
    perform correct_invoice(inv, pg_temp.kept(inv), jsonb_build_object('manual_discount', 210), 'Discount raised to 210', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 13a: raising the manual discount to 210 (the settled bundle''s share falls from % to about 838.46) was refused: %', round(v_before, 2), v_msg;
  end;
  if (select i.manual_discount from invoices i where i.id = inv) <> 210 or round(credit_line_paid_entitlement(it), 2) <> 838.46
     or (select i.total_amount from invoices i where i.id = inv) <> 1090 then
    raise exception 'FAIL 13a: after raising the discount the invoice has discount % and total %, the bundle is worth %; expected 210, 1,090, 838.46',
      (select i.manual_discount from invoices i where i.id = inv), (select i.total_amount from invoices i where i.id = inv),
      credit_line_paid_entitlement(it); end if;

  v_inv := pg_temp.invoice_state(inv);
  v_credit := pg_temp.credit_state(c);
  begin
    perform correct_invoice(inv, pg_temp.kept(inv), jsonb_build_object('manual_discount', 0), 'Discount withdrawn', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if v_msg not like 'CREDIT_LINE_SETTLED%' then
    raise exception 'FAIL 13a: withdrawing the discount (the settled bundle worth 1,000, above both the 833.33 issued and the 838.46 before) should be refused with CREDIT_LINE_SETTLED, got: %', v_msg; end if;
  if pg_temp.invoice_state(inv) <> v_inv or pg_temp.credit_state(c) <> v_credit then
    raise exception 'FAIL 13a: the refused withdrawal still changed something (invoice % -> %)', v_inv, pg_temp.invoice_state(inv); end if;
  raise notice 'PASS 13a: after a re-spread took the settled bundle from % to %, raising the discount to 210 (worth 838.46, above the issue value but below the worth before) goes through; withdrawing the discount (1,000) is still refused',
    v_settled, round(v_before, 2);

  -- 13b
  insert into vouchers(name,code,voucher_kind,discount_amount,qty_type,is_active)
    values ('RCP 200 off','RCP-D-'||pg_temp.sfx(),'fixed_discount',200,'unlimited',true) returning id into vd;
  cp := pg_temp.package(1000);
  c := pg_temp.customer('RCP 13b');
  inv := create_invoice(pg_temp.fx('st'), c, null::uuid,
    jsonb_build_array(pg_temp.package_line(cp), pg_temp.product_line(pg_temp.fx('p100'), 2)), 0::numeric, null::text, vd, '[]'::jsonb);
  it := pg_temp.line(inv, 'credit_package'); itx := pg_temp.line(inv, 'product');
  -- No manual discount on record at all (NULL, not 0), before the invoice is paid.
  update invoices set manual_discount = null where id = inv;
  perform pg_temp.pay(inv, (select i.total_amount from invoices i where i.id = inv));
  v_settled := (select s.credit_snapshot from credit_package_sales s where s.invoice_item_id = it);
  if pg_temp.status(inv) <> 'paid' or (select i.manual_discount from invoices i where i.id = inv) is not null
     or (select i.discount_voucher_id from invoices i where i.id = inv) is distinct from vd
     or (select i.total_amount from invoices i where i.id = inv) <> 1000 or v_settled <> 833.33 then
    raise exception 'FAIL 13b (fixture): expected a settled package (833.33) on a S$1,000 invoice with the voucher and manual_discount NULL (status %, manual %, total %, issued %)',
      pg_temp.status(inv), (select i.manual_discount from invoices i where i.id = inv),
      (select i.total_amount from invoices i where i.id = inv), v_settled; end if;
  begin
    perform correct_invoice(inv, jsonb_build_array(
        pg_temp.package_line(cp) || jsonb_build_object('invoice_item_id', it),
        pg_temp.product_line(pg_temp.fx('p100'), 3) || jsonb_build_object('invoice_item_id', itx)),
      -- What the till sends: the whole header, manual_discount 0 when there is none.
      jsonb_build_object('customer_id', c, 'store_id', pg_temp.fx('st'), 'notes', null, 'manual_discount', 0,
                         'discount_voucher_id', vd, 'service_staff', '[]'::jsonb, 'manual_discount_reason', null),
      'One more product', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL 13b: adding a product with the till''s header (manual_discount 0 on a NULL invoice, the voucher unchanged) was refused: %', v_msg;
  end;
  if (select x.quantity from invoice_items x where x.id = itx) <> 3 or round(credit_line_paid_entitlement(it), 2) <> 846.15
     or (select i.discount_voucher_id from invoices i where i.id = inv) is distinct from vd
     or coalesce((select i.manual_discount from invoices i where i.id = inv), 0) <> 0
     or (select i.total_amount from invoices i where i.id = inv) <> 1100 then
    raise exception 'FAIL 13b: after the correction the product is at %, the package worth %, the invoice total % (voucher kept %, manual %); expected 3, 846.15, 1,100, the voucher, none',
      (select x.quantity from invoice_items x where x.id = itx), credit_line_paid_entitlement(it),
      (select i.total_amount from invoices i where i.id = inv),
      (select i.discount_voucher_id from invoices i where i.id = inv) = vd, (select i.manual_discount from invoices i where i.id = inv); end if;
  raise notice 'PASS 13b: on an invoice with manual_discount NULL and a discount voucher, the till''s header (manual_discount 0) with one more product only re-spreads the voucher (the settled package % -> 846.15) and goes through',
    v_settled;
end $$;

-- ── 12c. a refund's rule holds after its own transaction too ────────────────
-- The 12a and 12b shapes, with the refund made to look committed earlier (its
-- created_at moved back an hour). The next payment, and a correction that only
-- changes the notes and Served by, leave the released credit as it is: the
-- money queue does not know which line a refund was for, so it is not used to
-- take credit back until the invoice settles.
do $$
declare pa uuid; pb uuid; c uuid; inv uuid; ia uuid; ix uuid; lot_a uuid; opt jsonb; k int; h0 numeric;
begin
  pa := pg_temp.bundle(1000, 0, 0); pb := pg_temp.bundle(1000, 0, 0);
  for k in 1..2 loop
    c := pg_temp.customer('RCP 12c A' || k);
    inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pa)));
    ia := pg_temp.line(inv, 'premium_bundle');
    perform pg_temp.pay(inv, 1000);
    perform correct_invoice(inv, pg_temp.kept(inv) || jsonb_build_array(pg_temp.bundle_line(pb)), '{}'::jsonb, 'adds B', gen_random_uuid());
    perform pg_temp.pay(inv, 500);
    lot_a := (select s.paid_credit_lot_id from premium_bundle_sales s where s.invoice_item_id = ia);
    opt := invoice_refund_options_before_sessions(inv);
    perform refund_invoice_recorded(inv,
        jsonb_build_array(jsonb_build_object('invoice_item_id', ia, 'amount', 300,
          'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', x->>'id', 'amount', 300))
                         from jsonb_array_elements(opt->'benefits') x where (x->>'lot_id')::uuid = lot_a))),
        jsonb_build_array(jsonb_build_object('payment_id', (select x->>'payment_id' from jsonb_array_elements(opt->'sources') x
                                                             order by (x->>'remaining')::numeric desc limit 1), 'amount', 300)),
        '[]'::jsonb, 'refund 300 of A', gen_random_uuid());
    update invoice_refunds set created_at = created_at - interval '1 hour' where invoice_id = inv;
    h0 := pg_temp.held(c);
    if k = 1 then
      perform pg_temp.pay(inv, 100);
    else
      perform correct_invoice(inv, pg_temp.kept(inv),
        jsonb_build_object('notes', 'RCP 12c served by', 'service_staff', jsonb_build_array(pg_temp.fx('own'))),
        'Served by corrected', gen_random_uuid());
    end if;
    if pg_temp.held(c) <> h0 then
      raise exception 'FAIL 12c (%): after a refund committed earlier, % took credit back: held % -> %',
        case k when 1 then 'next payment' else 'Served-by correction' end,
        case k when 1 then 'paying 100 more' else 'a notes / Served-by correction' end, h0, pg_temp.held(c); end if;
  end loop;

  c := pg_temp.customer('RCP 12c B');
  inv := pg_temp.invoice(c, jsonb_build_array(pg_temp.bundle_line(pb), pg_temp.product_line(pg_temp.fx('p1000'))));
  ix := pg_temp.line(inv, 'product');
  perform pg_temp.pay(inv, 1200);
  opt := invoice_refund_options_before_sessions(inv);
  perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', ix, 'amount', 1000)),
      jsonb_build_array(jsonb_build_object('payment_id', (select x->>'payment_id' from jsonb_array_elements(opt->'sources') x limit 1), 'amount', 1000)),
      '[]'::jsonb, 'Product returned', gen_random_uuid());
  update invoice_refunds set created_at = created_at - interval '1 hour' where invoice_id = inv;
  h0 := pg_temp.held(c);
  perform pg_temp.pay(inv, 100);
  if pg_temp.held(c) <> h0 then
    raise exception 'FAIL 12c (product refund): paying 100 more after the product refund took bundle credit back: held % -> %', h0, pg_temp.held(c); end if;
  raise notice 'PASS 12c: after a refund committed in an earlier transaction, the next payment and a Served-by correction leave released credit as it is';
end $$;

-- ── 13c. a discount cut is held to what the line was issued at ──────────────
-- The 11b fixture. Adding 10 x S$1,000 products is an allowed re-spread and
-- lifts the settled bundle's share well above what it was issued. Removing them
-- and cutting the discount 200 -> 25 in one correction must not ride on that
-- lifted share: a discount cut is compared with what the line was issued at.
do $$
declare pb uuid; c uuid; inv uuid; it uuid; itx uuid; v_msg text;
begin
  pb := pg_temp.bundle(1000, 100, 0);
  c := pg_temp.customer('RCP 13c');
  inv := pg_temp.dinvoice(c, jsonb_build_array(pg_temp.bundle_line(pb), pg_temp.product_line(pg_temp.fx('p100'), 2)), 200);
  it := pg_temp.line(inv, 'premium_bundle'); itx := pg_temp.line(inv, 'product');
  perform pg_temp.pay(inv, (select i.total_amount from invoices i where i.id = inv));
  perform correct_invoice(inv, pg_temp.kept(inv) || jsonb_build_array(pg_temp.product_line(pg_temp.fx('p1000'), 10)),
    '{}'::jsonb, 'Added by mistake', gen_random_uuid());
  begin
    perform correct_invoice(inv, jsonb_build_array(pg_temp.bundle_line(pb) || jsonb_build_object('invoice_item_id', it),
                                                   pg_temp.product_line(pg_temp.fx('p100'), 2) || jsonb_build_object('invoice_item_id', itx)),
      jsonb_build_object('manual_discount', 25, 'manual_discount_reason', 'Loyalty'), 'Mistake removed; discount cut', gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if v_msg not like 'CREDIT_LINE_SETTLED%' then
    raise exception 'FAIL 13c: removing the re-spread lines and cutting the discount to 25 should be refused with CREDIT_LINE_SETTLED, got: %', v_msg; end if;
  raise notice 'PASS 13c: a discount cut after an allowed re-spread is still held to what the settled line was issued at';
end $$;

rollback;
