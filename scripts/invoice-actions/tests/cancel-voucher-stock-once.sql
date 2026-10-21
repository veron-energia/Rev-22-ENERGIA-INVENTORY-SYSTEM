-- 417: cancelling an invoice gives limited voucher stock back once.
--
-- Before 417, cancel_invoice_recorded gave the stock back twice for an
-- invoice paid through Record Payment: once with each voucher the customer
-- still held, and again for the invoice's voucher movements (2 sold: 10, 8
-- after payment, 12 after cancelling; it should be 10). The Owner wants
-- refunds and cancellations to be right, whichever way the vouchers were
-- issued:
--   1. Record Payment (stock taken by the invoice's voucher movements,
--      vouchers issued when it is paid): 10, 8, cancelled 10. Reopened, it
--      issues the units again and takes them again (8); cancelled again, 10.
--   2. One of two vouchers already used: only the unused one comes back (9).
--   3. A promotion's vouchers, paid through Record Payment: back once.
--   4. One unit refunded first (it came back then), then cancelled: the other
--      comes back, and nothing more (10).
--   5. Stock the invoice took with no voucher behind it (an extra movement,
--      as an older correction could leave): that comes back too, once.
--   6. Stock taken directly, as Confirm FOC does (no movement), with the
--      vouchers issued as 416 issues them on a completed FOC: back once.
--      Reopened (417 rule 5, the Owner, 9 Oct 2026), it gives the vouchers
--      again and takes their stock once (8, not 6); cancelled again 10;
--      reopened again 8; a third time 10 and 8; cancelled at the end 10. The
--      reopening's preview shows no stock to issue and the 2 units to give
--      again. invoice_voucher_stock_unrecorded is checked on its own: the 2
--      units before the first reopening, nothing once a row records them.
--   7. A completed FOC of two vouchers, one used: cancelled 9; reopened 8
--      (the used one stays out, the other is given again, once); cancelled
--      again 9; reopened again 8.
--   8. A free invoice cancelled before Confirm FOC (no stock taken):
--      reopened, it is completed FOC and takes the stock once (8).
--   9. (416 only) The FOC taken off a completed FOC invoice (416 takes the
--      unused vouchers back, 10), then cancelled, reopened and paid: the
--      vouchers are given again and their stock taken once (8, not 6). The
--      same with one of two used before the FOC came off: 9, then 8.
--  10. Reopened, then cancelled again before it was settled, then reopened
--      again: the units the first reopening queued are given once, not
--      again with the second (a paid sale, half the money paid back after
--      cancelling, so it reopens part paid): 2 vouchers and 8 once paid,
--      not 3 and 7. The preview before the second reopening says 2 units.
--      A paid sale's rows record every unit, so
--      invoice_voucher_stock_unrecorded finds nothing at any point.
--  11. (416 only) The same after the FOC was taken off: 2 vouchers and 8,
--      not 4 and 6.
--  12. A completed FOC whose 2 vouchers an Owner moved to another store
--      (transfer_invoice_unused_benefit), cancelled and reopened: the store
--      of the invoice stays at 10 (not 8) and the other store, where the
--      vouchers are given again, at 8. Cancelled again, both 10; reopened
--      again, 10 and 8. The reopening records its row at the other store,
--      where the vouchers are and their stock is taken.
--  12b. (416 only) The same move, then cancelled, reopened, the FOC taken
--      off and paid: the friend keeps the 2 vouchers, as in 12c (the FOC
--      off 18 with the friend's 2 held, paid 18, cancelled 20, not 22).
--      416 must count any voucher of the invoice another customer holds as
--      moved, whatever its source. 416's file of 10 Oct (md5 f79dc285...)
--      counts only an Owner's move ('invoice_benefit_transfer'), so after a
--      cancel and reopen the friend's vouchers (now 'invoice_reopen') were
--      taken back and the payment gave them to the buyer. That is B02's to
--      change in 416. While 416 has that text, this prints a KNOWN FAULT
--      notice and checks the old figures (the FOC off 20 and 0 held, paid
--      18 with 2 held, cancelled 20).
--  12c. (416 only) The same move, then the FOC taken off (the moved
--      vouchers stay with the friend), paid and cancelled: 18, then 20
--      (not 22).
--  12d. A completed FOC of 2 vouchers on two lines, one moved to another
--      store, cancelled and reopened: 9 and 9 each time it is reopened,
--      and the reopening records one unit at each store, where each
--      voucher is (before: both units at one store, picked by its id).
--  13. A paid sale corrected to another customer and store (correct_invoice,
--      benefit_action 'transfer'): the vouchers' stock moves with them (417:
--      10 and 8, not 8 and 10), then cancelled and reopened three times:
--      10 and 10, 10 and 8, each time, store by store (before: 8 and 12
--      after the first cancel, the first store 2 short and the other 2
--      over). Too little stock at the new store refuses the correction.
--  13b. (416 only) The FOC taken off and the invoice moved to another
--      customer and store in one save, then paid, cancelled, reopened and
--      cancelled: 10 and 10, 10 and 8 (not 8 and 12).
--  14. (416 only) A completed FOC cancelled, reopened, its vouchers then
--      moved to another store, the FOC taken off, paid and cancelled: 18,
--      then 20 (not 22). 416 counts its 'Taken at Confirm FOC' rows by
--      voucher (B02's file of 10 Oct); counted by store, it ended at 22.
--  15. (416 only) The FOC taken off with the quantity raised from 2 to 3 in
--      the same save, paid, cancelled: 7, then 10 (not 11); reopened 7,
--      cancelled 10. The third voucher is given as a replacement (416), and
--      the units counted never pass what the line holds.
--  15b. (416 only) The FOC taken off with the quantity lowered from 2 to 1,
--      paid, then cancelled and reopened three times: 9, 10, 9, 10, 9, 10,
--      9, 10 (the reopening counts only the units still waiting to be given
--      again, not those 416 already gave at payment).
--  16. Case 5's unit with no voucher behind it, after the 2 vouchers were
--      moved to another store: cancelled, it still comes back (20, not 19).
--  17. A paid sale of 2, its line lowered to 1 (the 2 vouchers stay held),
--      cancelled and reopened three times: 10 and 8 every time (not 11, 12,
--      13), and no 'Recorded on reopening' row on the paid invoice.
--  18. The same, then the extra unit refunded with its voucher (9, 1 held):
--      cancelled 10 (not 11).
--  19. A completed FOC of 2, its line lowered to 1 while it stays FOC,
--      cancelled and reopened three times: 10 and 8 every time (not 10, 11,
--      12 and 8, 9, 10).
--  20. A paid sale of 2, its line raised to 3 and the rest paid (7, 2
--      held: the third unit has no voucher), cancelled and reopened three
--      times: 10 and 7 every time (not 10, then 9 and 9).
--  21. A paid sale of 2 cancelled and reopened, then raised to 3 and paid,
--      then cancelled: 10 (not 9).
--
-- Needs 417 (run it in the same transaction first, on a copy of production's
-- schema); fails without it at case 1 (at case 6's reopening when only the
-- cancellation part of 417 is in; at case 10 without its queue rule; at
-- case 12 when the units are counted by store; at 12b when the reopening
-- records its row at the invoice's store; at 13 when the cancellation
-- counts by store; at 15 when it counts only sale and promotion vouchers;
-- at 16 when it counts more units than the lines hold; at 15b when the
-- reopening counts units already given again; at 12d when the reopening
-- records all its units at one store; at 13 store by store when
-- the correction moves no stock; at 17 to 21 when the units issued stop at
-- what the lines hold). Install 416 in the same
-- transaction, before or after 417, so a completed FOC invoice gives its
-- vouchers as it will; without 416, cases 6, 7, 12, 12d and 19 call the same
-- issuing function themselves, case 8 checks the stock only, and cases 9,
-- 11, 12b, 12c, 13b, 14, 15 and 15b are skipped.
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@tests.invalid); the phones are numbers kept for
-- fiction (ACMA).
\set ON_ERROR_STOP on
begin;

create temp table tvs(k text primary key, id uuid);
create function pg_temp.tvs_id(p_k text) returns uuid language sql as $f$ select id from tvs where k = p_k $f$;
create function pg_temp.tvs_stock(p_voucher text) returns int language sql as $f$
  select current_qty from voucher_store_stock
   where voucher_id = pg_temp.tvs_id(p_voucher) and store_id = pg_temp.tvs_id('store') $f$;
-- Stock at one store ('store' or 'store2'), in both, and the vouchers held.
create function pg_temp.tvs_at(p_voucher text, p_store text) returns int language sql as $f$
  select current_qty from voucher_store_stock
   where voucher_id = pg_temp.tvs_id(p_voucher) and store_id = pg_temp.tvs_id(p_store) $f$;
create function pg_temp.tvs_both(p_voucher text) returns int language sql as $f$
  select pg_temp.tvs_at(p_voucher, 'store') + pg_temp.tvs_at(p_voucher, 'store2') $f$;
create function pg_temp.tvs_held(p_voucher text) returns int language sql as $f$
  select coalesce(sum(quantity), 0)::int from customer_reward_vouchers
   where voucher_id = pg_temp.tvs_id(p_voucher) and status = 'held' $f$;
-- What invoice_voucher_stock_unrecorded (417) returns, as 'store:2' (empty:
-- nothing). plpgsql, so the suite still loads, and fails at case 1, without 417.
create function pg_temp.tvs_unrec(p_inv uuid, p_before boolean) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(coalesce((select k from tvs where id = u.store_id), '?') || ':' || u.quantity, ' '
                                     order by u.store_id), '')
            from invoice_voucher_stock_unrecorded(p_inv, p_before) u);
end $f$;
-- Where the invoice's voucher movement rows sit, net by store ('store2:2').
create function pg_temp.tvs_rows(p_inv uuid) returns text language sql as $f$
  select coalesce(string_agg(coalesce((select k from tvs where id = x.store_id), '?') || ':' || x.q, ' ' order by x.store_id), '')
    from (select store_id, sum(quantity) as q from invoice_voucher_movements where invoice_id = p_inv
           group by store_id having sum(quantity) <> 0) x $f$;
create function pg_temp.tvs_416() returns boolean language sql as $f$
  select pg_get_functiondef('public.trg_issue_sold_vouchers_on_paid()'::regprocedure) like '%completed_foc%' $f$;
-- A completed FOC of p_qty of one voucher at the first store.
create function pg_temp.tvs_foc(p_voucher text, p_qty int, p_reason text) returns uuid language plpgsql as $f$
declare inv uuid;
begin
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id(p_voucher), 'quantity', p_qty,
      'foc_quantity', p_qty, 'foc_reason', 'TVS goodwill')));
  perform confirm_foc_invoice(inv, p_reason);
  if not exists (select 1 from customer_reward_vouchers where voucher_id = pg_temp.tvs_id(p_voucher)) then
    perform issue_sold_vouchers_for_invoice(inv); end if;
  return inv;
end $f$;
-- The FOC taken off (416), the line now p_qty at S$40 each.
create function pg_temp.tvs_foc_off(p_inv uuid, p_qty int, p_reason text) returns jsonb language plpgsql as $f$
declare x jsonb;
begin
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', p_qty, 'unit_price', 40, 'foc_quantity', 0)) into x
    from invoice_items it where it.invoice_id = p_inv;
  return correct_invoice(p_inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv)),
    p_reason, gen_random_uuid());
end $f$;
-- An Owner moves the invoice's held vouchers to the friend at the other store.
create function pg_temp.tvs_move(p_inv uuid, p_reason text) returns void language plpgsql as $f$
begin
  perform transfer_invoice_unused_benefit(
    (select b.id from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
      where b.invoice_id = p_inv and v.status = 'held'),
    pg_temp.tvs_id('friend'), pg_temp.tvs_id('store2'), p_reason, gen_random_uuid());
end $f$;
create function pg_temp.tvs_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
-- A paid voucher sale (Record Payment) of p_lines lines of p_qty each.
create function pg_temp.tvs_paid_sale(p_voucher text, p_lines int, p_qty int) returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]';
begin
  for k in 1 .. p_lines loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id(p_voucher), 'quantity', p_qty));
  end loop;
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null, v_lines);
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'),
    'amount', (select total_amount from invoices where id = inv))));
  return inv;
end $f$;
-- The invoice's voucher line set to p_qty at S$40 each (correct_invoice);
-- p_foc keeps it free of charge (FOC on every unit).
create function pg_temp.tvs_set_qty(p_inv uuid, p_qty int, p_foc boolean, p_reason text) returns jsonb language plpgsql as $f$
declare x jsonb;
begin
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', p_qty, 'unit_price', 40)
         || case when p_foc then jsonb_build_object('foc_quantity', p_qty, 'foc_reason', it.foc_reason) else '{}'::jsonb end) into x
    from invoice_items it where it.invoice_id = p_inv;
  return correct_invoice(p_inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv)),
    p_reason, gen_random_uuid());
end $f$;
-- What is still due, paid.
create function pg_temp.tvs_pay_rest(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  select total_amount - invoice_net_received(id) into due from invoices where id = p_inv;
  if due > 0 then
    perform pay_invoice(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', due)));
  end if;
end $f$;
-- Stock at the two stores and the vouchers held, as '10/8 held 2'.
create function pg_temp.tvs_show(p_voucher text) returns text language sql as $f$
  select pg_temp.tvs_at(p_voucher, 'store') || '/' || coalesce(pg_temp.tvs_at(p_voucher, 'store2')::text, '-')
         || ' held ' || pg_temp.tvs_held(p_voucher) $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; c uuid; c2 uuid; pm uuid; v uuid; promo uuid; k text;
begin
  insert into auth.users(id, email) values (own, 'tvs-own@tests.invalid');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'TVS Owner', 'tvs-own@tests.invalid', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('TVS Store', 'TVS1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('TVS Store 2', 'TVS2', 'SG') returning id into st2;
  insert into customers(full_name, phone) values ('TVS Buyer', '+61491570006') returning id into c;
  insert into customers(full_name, phone) values ('TVS Friend', '+61491570156') returning id into c2;
  insert into payment_methods(name, is_active) values ('TVS PayNow', true) returning id into pm;
  insert into tvs values ('own', own), ('store', st), ('store2', st2), ('customer', c), ('friend', c2), ('pm', pm);
  -- One limited voucher per case, 10 in stock each, S$40; v13 to v19 and
  -- v26 to v28 also have 10 at the second store.
  foreach k in array array['v1', 'v2', 'v3', 'v4', 'v5', 'v6', 'v7', 'v8', 'v9', 'v10', 'v11', 'v12', 'v13',
                           'v14', 'v15', 'v16', 'v17', 'v18', 'v19', 'v20', 'v21', 'v22', 'v23', 'v24',
                           'v25', 'v26', 'v27', 'v28'] loop
    insert into vouchers(name, code, voucher_kind, selling_price, qty_type, is_active)
      values ('TVS ' || k, 'TVS-' || upper(k), 'normal', 40, 'limited', true) returning id into v;
    insert into voucher_store_stock(voucher_id, store_id, current_qty) values (v, st, 10);
    if k in ('v13', 'v14', 'v15', 'v16', 'v17', 'v18', 'v19', 'v26', 'v27', 'v28') then
      insert into voucher_store_stock(voucher_id, store_id, current_qty) values (v, st2, 10);
    end if;
    insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 40, true);
    -- v26 is sold at the second store once its invoice moves there (13b).
    if k = 'v26' then
      insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st2, 40, true);
    end if;
    insert into tvs values (k, v);
  end loop;
  -- A promotion holding 2 of v3.
  insert into promotions(name, code, promo_type, fixed_price, is_active)
    values ('TVS Promo', 'TVSP', 'bundle', 70, true) returning id into promo;
  insert into promotion_items(promotion_id, item_type, voucher_id, quantity) values (promo, 'voucher', pg_temp.tvs_id('v3'), 2);
  insert into promotion_store_prices(promotion_id, store_id, selling_price, available_at_store) values (promo, st, 70, true);
  insert into tvs values ('promo', promo);
end $$;

-- ===== 1. Record Payment, cancel, reopen, cancel again =====
do $$
declare inv uuid;
begin
  inv := pg_temp.tvs_paid_sale('v1', 1, 2);
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v1') = 8, '1 Record Payment took 2 (stock ' || pg_temp.tvs_stock('v1') || ')');
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v1') and status = 'held') = 2,
    '1 the 2 vouchers are held');
  perform cancel_invoice_recorded(inv, 'TVS 1 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v1') = 10, '1 cancelling gave the stock back ' ||
    case when pg_temp.tvs_stock('v1') = 12 then 'twice (12)' else 'wrongly (' || pg_temp.tvs_stock('v1') || ')' end || ', not once (10)');
  perform pg_temp.tvs_check(not exists (select 1 from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v1') and status <> 'revoked'),
    '1 the vouchers were not revoked');
  -- Reopened (the money is still held): the units are issued again and taken again, once.
  perform reopen_invoice(inv, 'TVS 1 reopen', gen_random_uuid());
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'paid', '1 reopened to paid');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v1') = 8, '1 reopening took the 2 units again, once (stock ' || pg_temp.tvs_stock('v1') || ')');
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v1') and status = 'held') = 2,
    '1 reopening issued the 2 vouchers again');
  perform cancel_invoice_recorded(inv, 'TVS 1 cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v1') = 10, '1 cancelling again gave back ' || pg_temp.tvs_stock('v1') - 8 || ', not 2');
  raise notice 'PASS 1: paid through Record Payment, 10 -> 8, cancelled 10 (not 12); reopened 8; cancelled again 10';
end $$;

-- ===== 2. One of two vouchers already used =====
do $$
declare inv uuid;
begin
  inv := pg_temp.tvs_paid_sale('v2', 2, 1);
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v2') = 8, '2 Record Payment took 2');
  update customer_reward_vouchers set status = 'redeemed'
   where id = (select v.id from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id = v.id
                where b.invoice_id = inv order by v.id limit 1);
  perform cancel_invoice_recorded(inv, 'TVS 2 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v2') = 9, '2 only the unused voucher comes back: stock ' || pg_temp.tvs_stock('v2') || ', not 9');
  perform pg_temp.tvs_check((select count(*) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v2') and status = 'redeemed') = 1,
    '2 the used voucher stays redeemed');
  raise notice 'PASS 2: one of two used: cancelling gives back the unused one only (9, not 11)';
end $$;

-- ===== 3. A promotion's vouchers, paid through Record Payment =====
do $$
declare inv uuid;
begin
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.tvs_id('promo'), 'quantity', 1)));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 70)));
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v3') = 8, '3 the promotion took 2 (stock ' || pg_temp.tvs_stock('v3') || ')');
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where source_type = 'invoice_promotion_voucher'
                               and voucher_id = pg_temp.tvs_id('v3') and status = 'held') = 2, '3 the promotion''s 2 vouchers are held');
  perform cancel_invoice_recorded(inv, 'TVS 3 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v3') = 10, '3 cancelling the promotion gave back ' || pg_temp.tvs_stock('v3') - 8 || ', not 2');
  raise notice 'PASS 3: a promotion''s vouchers: 10 -> 8, cancelled 10';
end $$;

-- ===== 4. One unit refunded, then the invoice cancelled =====
do $$
declare inv uuid; b record;
begin
  inv := pg_temp.tvs_paid_sale('v4', 1, 2);
  select * into b from invoice_benefit_values where invoice_id = inv;
  perform refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', b.invoice_item_id, 'amount', 40,
      'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', 40)))),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv), 'amount', 40)),
    '[]', 'TVS 4 one unit back', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v4') = 9, '4 the refunded unit came back (stock ' || pg_temp.tvs_stock('v4') || ')');
  perform cancel_invoice_recorded(inv, 'TVS 4 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v4') = 10, '4 cancelling after a part refund: stock ' || pg_temp.tvs_stock('v4') || ', not 10');
  raise notice 'PASS 4: one unit refunded (9), then cancelled: 10, not 12';
end $$;

-- ===== 5. Stock the invoice took with no voucher behind it =====
do $$
declare inv uuid;
begin
  inv := pg_temp.tvs_paid_sale('v5', 1, 2);
  -- One more unit out on the invoice's movements, never issued.
  update voucher_store_stock set current_qty = current_qty - 1 where voucher_id = pg_temp.tvs_id('v5') and store_id = pg_temp.tvs_id('store');
  insert into invoice_voucher_movements(invoice_id, store_id, voucher_id, quantity, reason, created_by)
    values (inv, pg_temp.tvs_id('store'), pg_temp.tvs_id('v5'), 1, 'TVS 5 taken, not issued', pg_temp.tvs_id('own'));
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v5') = 7, '5 fixture: 3 out');
  perform cancel_invoice_recorded(inv, 'TVS 5 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v5') = 10, '5 the 2 vouchers and the unit never issued come back, once: stock ' || pg_temp.tvs_stock('v5'));
  perform pg_temp.tvs_check((select sum(quantity) from invoice_voucher_movements where invoice_id = inv and quantity < 0) = -1,
    '5 the movements record only the unit never issued as given back');
  raise notice 'PASS 5: a unit taken with no voucher behind it comes back with the 2 vouchers, once (7 -> 10)';
end $$;

-- ===== 6. Stock taken directly (Confirm FOC), vouchers issued as 416 does =====
do $$
declare inv uuid; p jsonb;
begin
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v6'), 'quantity', 2,
      'foc_quantity', 2, 'foc_reason', 'TVS goodwill')));
  perform confirm_foc_invoice(inv, 'TVS 6 confirm');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v6') = 8, '6 Confirm FOC took 2 (stock ' || pg_temp.tvs_stock('v6') || ')');
  perform pg_temp.tvs_check(not exists (select 1 from invoice_voucher_movements where invoice_id = inv), '6 Confirm FOC wrote no movement');
  -- 416 issues a completed FOC's vouchers from the paid trigger; without it,
  -- the same issuing function is called here.
  if not exists (select 1 from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v6')) then
    perform issue_sold_vouchers_for_invoice(inv); end if;
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v6') and status = 'held') = 2,
    '6 the 2 vouchers are held');
  -- The helper on its own: Confirm FOC's 2 units are on no row yet.
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, false) = 'store:2',
    '6 before cancelling, the units not on a row: "' || pg_temp.tvs_unrec(inv, false) || '", not "store:2"');
  perform cancel_invoice_recorded(inv, 'TVS 6 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v6') = 10, '6 cancelling a completed FOC gave back ' || pg_temp.tvs_stock('v6') - 8 || ', not 2');
  -- Cancelled: the customer holds none, so nothing is missing from the rows;
  -- the reopening will give 2 again, so its preview counts 2.
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, false) = '',
    '6 cancelled, the units not on a row: "' || pg_temp.tvs_unrec(inv, false) || '", not none');
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, true) = 'store:2',
    '6 before the reopening, the units it gives again not on a row: "' || pg_temp.tvs_unrec(inv, true) || '", not "store:2"');
  -- 417 rule 5: the reopening's preview shows nothing to take but the 2 units given again.
  p := invoice_reopen_preview(inv);
  perform pg_temp.tvs_check(jsonb_array_length(p->'stock_to_issue') = 0,
    '6 the reopening preview shows stock to issue: ' || (p->'stock_to_issue')::text);
  perform pg_temp.tvs_check((p->>'voucher_units_to_reinstate_after_settlement')::int = 2, '6 the preview gives 2 units again');
  perform reopen_invoice(inv, 'TVS 6 reopen', gen_random_uuid());
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'completed_foc', '6 reopened to completed FOC');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v6') = 8, '6 reopening a completed FOC took its stock ' ||
    case when pg_temp.tvs_stock('v6') = 6 then 'twice (6)' else 'wrongly (' || pg_temp.tvs_stock('v6') || ')' end || ', not once (8)');
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v6') and status = 'held') = 2,
    '6 reopening gave the 2 vouchers again');
  perform pg_temp.tvs_check((select sum(quantity) from invoice_voucher_movements where invoice_id = inv) = 2,
    '6 the units Confirm FOC took are recorded on the movements');
  -- Recorded and settled: nothing is missing any more, now or for the next reopening.
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, false) = '' and pg_temp.tvs_unrec(inv, true) = '',
    '6 reopened, the units not on a row: "' || pg_temp.tvs_unrec(inv, false) || '" and "' || pg_temp.tvs_unrec(inv, true) || '", not none');
  perform cancel_invoice_recorded(inv, 'TVS 6 cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v6') = 10, '6 cancelling again gave back ' || pg_temp.tvs_stock('v6') - 8 || ', not 2');
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, true) = '',
    '6 before the second reopening, the units not on a row: "' || pg_temp.tvs_unrec(inv, true) || '", not none');
  perform reopen_invoice(inv, 'TVS 6 reopen again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v6') = 8, '6 reopening again: stock ' || pg_temp.tvs_stock('v6') || ', not 8');
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v6') and status = 'held') = 2,
    '6 reopening again gave the 2 vouchers again');
  -- A third time, and a last cancellation: 10 and 8 every time.
  perform cancel_invoice_recorded(inv, 'TVS 6 cancel a third time', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v6') = 10, '6 cancelling a third time: stock ' || pg_temp.tvs_stock('v6') || ', not 10');
  perform reopen_invoice(inv, 'TVS 6 reopen a third time', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v6') = 8, '6 reopening a third time: stock ' || pg_temp.tvs_stock('v6') || ', not 8');
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, false) = '' and pg_temp.tvs_unrec(inv, true) = '',
    '6 reopened a third time, the units not on a row: "' || pg_temp.tvs_unrec(inv, false) || '" and "' || pg_temp.tvs_unrec(inv, true) || '", not none');
  perform pg_temp.tvs_check((select sum(quantity) from invoice_voucher_movements where invoice_id = inv) = 2,
    '6 the rows record ' || (select sum(quantity) from invoice_voucher_movements where invoice_id = inv) || ' units, not 2');
  perform cancel_invoice_recorded(inv, 'TVS 6 cancel at the end', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v6') = 10, '6 cancelling at the end: stock ' || pg_temp.tvs_stock('v6') || ', not 10');
  raise notice 'PASS 6: stock taken directly (Confirm FOC) with the vouchers issued: 10 -> 8, cancelled 10, reopened 8 (not 6), cancelled 10, reopened 8, again 10 and 8, cancelled 10; the units missing from the rows are found once';
end $$;

-- ===== 7. A completed FOC of two vouchers, one used =====
do $$
declare inv uuid; p jsonb;
begin
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(
      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v7'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'TVS goodwill'),
      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v7'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'TVS goodwill')));
  perform confirm_foc_invoice(inv, 'TVS 7 confirm');
  if not exists (select 1 from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v7')) then
    perform issue_sold_vouchers_for_invoice(inv); end if;
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v7') = 8, '7 Confirm FOC took 2 (stock ' || pg_temp.tvs_stock('v7') || ')');
  update customer_reward_vouchers set status = 'redeemed'
   where id = (select v.id from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id = v.id
                where b.invoice_id = inv order by v.id limit 1);
  perform cancel_invoice_recorded(inv, 'TVS 7 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v7') = 9, '7 only the unused voucher comes back: stock ' || pg_temp.tvs_stock('v7'));
  p := invoice_reopen_preview(inv);
  perform pg_temp.tvs_check(jsonb_array_length(p->'stock_to_issue') = 0,
    '7 the reopening preview shows stock to issue: ' || (p->'stock_to_issue')::text);
  perform pg_temp.tvs_check((p->>'voucher_units_to_reinstate_after_settlement')::int = 1, '7 the preview gives 1 unit again');
  perform reopen_invoice(inv, 'TVS 7 reopen', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v7') = 8, '7 reopening took ' || 9 - pg_temp.tvs_stock('v7') || ', not 1 (the unused voucher given again)');
  perform pg_temp.tvs_check((select count(*) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v7') and status = 'held') = 1
                            and (select count(*) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v7') and status = 'redeemed') = 1,
    '7 the customer holds the used voucher and the one given again');
  perform cancel_invoice_recorded(inv, 'TVS 7 cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v7') = 9, '7 cancelling again: stock ' || pg_temp.tvs_stock('v7') || ', not 9');
  perform reopen_invoice(inv, 'TVS 7 reopen again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v7') = 8, '7 reopening again: stock ' || pg_temp.tvs_stock('v7') || ', not 8');
  raise notice 'PASS 7: completed FOC, one of two used: cancelled 9, reopened 8, cancelled 9, reopened 8';
end $$;

-- ===== 8. A free invoice cancelled before Confirm FOC =====
do $$
declare inv uuid; v_416 boolean;
begin
  v_416 := pg_get_functiondef('public.trg_issue_sold_vouchers_on_paid()'::regprocedure) like '%completed_foc%';
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v8'), 'quantity', 2,
      'foc_quantity', 2, 'foc_reason', 'TVS goodwill')));
  perform cancel_invoice_recorded(inv, 'TVS 8 cancel before Confirm FOC', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v8') = 10, '8 nothing was taken before Confirm FOC (stock ' || pg_temp.tvs_stock('v8') || ')');
  perform reopen_invoice(inv, 'TVS 8 reopen', gen_random_uuid());
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'completed_foc', '8 reopened to completed FOC');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v8') = 8, '8 reopening took ' || 10 - pg_temp.tvs_stock('v8') || ', not 2');
  if v_416 then
    perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v8') and status = 'held') = 2,
      '8 with 416 the reopened FOC gives its 2 vouchers');
  end if;
  raise notice 'PASS 8: a free invoice cancelled before Confirm FOC, reopened: takes 2 once (8)';
end $$;

-- ===== 9. The FOC taken off (416), then cancelled, reopened and paid =====
do $$
declare inv uuid; p jsonb; x jsonb;
begin
  if pg_get_functiondef('public.trg_issue_sold_vouchers_on_paid()'::regprocedure) not like '%completed_foc%' then
    raise notice 'SKIP 9: needs 416 (taking the FOC off a completed FOC invoice)';
    return;
  end if;
  -- 9a. Two vouchers, none used.
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v9'), 'quantity', 2,
      'foc_quantity', 2, 'foc_reason', 'TVS goodwill')));
  perform confirm_foc_invoice(inv, 'TVS 9 confirm');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v9') = 8, '9a Confirm FOC took 2');
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', 40, 'foc_quantity', 0)) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv)),
    'TVS 9 not a giveaway', gen_random_uuid());
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'unpaid', '9a the FOC came off');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v9') = 10, '9a taking the FOC off took the 2 unused vouchers back (stock ' || pg_temp.tvs_stock('v9') || ')');
  perform cancel_invoice_recorded(inv, 'TVS 9 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v9') = 10, '9a cancelling moved stock: ' || pg_temp.tvs_stock('v9'));
  p := invoice_reopen_preview(inv);
  perform pg_temp.tvs_check(jsonb_array_length(p->'stock_to_issue') = 0,
    '9a the reopening preview shows stock to issue: ' || (p->'stock_to_issue')::text);
  perform pg_temp.tvs_check((p->>'voucher_units_to_reinstate_after_settlement')::int = 2, '9a the preview gives 2 units again');
  perform reopen_invoice(inv, 'TVS 9 reopen', gen_random_uuid());
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'unpaid', '9a reopened unpaid');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v9') = 10, '9a reopening unpaid took stock: ' || pg_temp.tvs_stock('v9'));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 80)));
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v9') = 8, '9a paying took ' || 10 - pg_temp.tvs_stock('v9') || ' for the 2 vouchers given again, not 2');
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v9') and status = 'held') = 2,
    '9a paying gave the 2 vouchers again');
  perform cancel_invoice_recorded(inv, 'TVS 9 cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v9') = 10, '9a cancelling again: stock ' || pg_temp.tvs_stock('v9') || ', not 10');

  -- 9b. Two vouchers on two lines, one used before the FOC came off.
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(
      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v10'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'TVS goodwill'),
      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v10'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'TVS goodwill')));
  perform confirm_foc_invoice(inv, 'TVS 9b confirm');
  update customer_reward_vouchers set status = 'redeemed'
   where id = (select v.id from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id = v.id
                where b.invoice_id = inv order by v.id limit 1);
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', 40, 'foc_quantity', 0) order by it.id) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv)),
    'TVS 9b not a giveaway', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v10') = 9, '9b taking the FOC off took back the unused one (stock ' || pg_temp.tvs_stock('v10') || ')');
  perform cancel_invoice_recorded(inv, 'TVS 9b cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v10') = 9, '9b cancelling moved stock: ' || pg_temp.tvs_stock('v10'));
  perform reopen_invoice(inv, 'TVS 9b reopen', gen_random_uuid());
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 80)));
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v10') = 8, '9b paying took ' || 9 - pg_temp.tvs_stock('v10') || ', not 1');
  perform pg_temp.tvs_check((select count(*) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v10') and status = 'held') = 1
                            and (select count(*) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v10') and status = 'redeemed') = 1,
    '9b the customer holds the used voucher and the one given again');
  raise notice 'PASS 9: the FOC taken off, cancelled, reopened, paid: stock taken once (8, not 6); one used first: 9, then 8';
end $$;

-- ===== 10. Reopened, cancelled again before it was settled, reopened again =====
do $$
declare inv uuid; b record; p jsonb;
begin
  inv := pg_temp.tvs_paid_sale('v11', 1, 2);
  perform cancel_invoice_recorded(inv, 'TVS 10 cancel', gen_random_uuid());
  -- Half the money paid back after cancelling (one unit's worth).
  select * into b from invoice_benefit_values where invoice_id = inv;
  perform refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', b.invoice_item_id, 'amount', 40,
      'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', 40)))),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv), 'amount', 40)),
    '[]', 'TVS 10 half back', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v11') = 10, '10 fixture: cancelled, stock ' || pg_temp.tvs_stock('v11'));
  -- A paid sale's rows record every unit: nothing is missing from them.
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, true) = '' and pg_temp.tvs_unrec(inv, false) = '',
    '10 before the reopening, the units not on a row: "' || pg_temp.tvs_unrec(inv, true) || '", not none');
  perform reopen_invoice(inv, 'TVS 10 reopen', gen_random_uuid());
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'partially_paid', '10 reopened part paid');
  perform pg_temp.tvs_check((select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is null) = 2,
    '10 the reopening queued the 2 units');
  perform cancel_invoice_recorded(inv, 'TVS 10 cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v11') = 10, '10 cancelling again moved stock: ' || pg_temp.tvs_stock('v11'));
  p := invoice_reopen_preview(inv);
  perform pg_temp.tvs_check((p->>'voucher_units_to_reinstate_after_settlement')::int = 2,
    '10 the preview gives ' || (p->>'voucher_units_to_reinstate_after_settlement') || ' units again, not 2');
  perform pg_temp.tvs_check(jsonb_array_length(p->'stock_to_issue') = 0,
    '10 the reopening preview shows stock to issue: ' || (p->'stock_to_issue')::text);
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, true) = '' and pg_temp.tvs_unrec(inv, false) = '',
    '10 before the second reopening, the units not on a row: "' || pg_temp.tvs_unrec(inv, true) || '", not none');
  perform reopen_invoice(inv, 'TVS 10 reopen again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, false) = '',
    '10 reopened again, the units not on a row: "' || pg_temp.tvs_unrec(inv, false) || '", not none');
  perform pg_temp.tvs_check((select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is null) = 2,
    '10 the second reopening queued the units again: ' ||
    (select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is null) || ' waiting, not 2');
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 40)));
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'paid', '10 paid');
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v11') and status = 'held') = 2,
    '10 paying gave ' || (select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v11') and status = 'held') || ' vouchers, not 2');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v11') = 8, '10 paying took ' || 10 - pg_temp.tvs_stock('v11') || ', not 2');
  raise notice 'PASS 10: reopened, cancelled again before it was settled, reopened again, paid: 2 vouchers and 8 (not 3 and 7)';
end $$;

-- ===== 11. The same after the FOC was taken off (416) =====
do $$
declare inv uuid; x jsonb;
begin
  if pg_get_functiondef('public.trg_issue_sold_vouchers_on_paid()'::regprocedure) not like '%completed_foc%' then
    raise notice 'SKIP 11: needs 416 (taking the FOC off a completed FOC invoice)';
    return;
  end if;
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v12'), 'quantity', 2,
      'foc_quantity', 2, 'foc_reason', 'TVS goodwill')));
  perform confirm_foc_invoice(inv, 'TVS 11 confirm');
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', 40, 'foc_quantity', 0)) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv)),
    'TVS 11 not a giveaway', gen_random_uuid());
  perform cancel_invoice_recorded(inv, 'TVS 11 cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'TVS 11 reopen', gen_random_uuid());
  perform cancel_invoice_recorded(inv, 'TVS 11 cancel again', gen_random_uuid());
  perform reopen_invoice(inv, 'TVS 11 reopen again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v12') = 10, '11 reopened unpaid twice: stock ' || pg_temp.tvs_stock('v12'));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 80)));
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v12') and status = 'held') = 2,
    '11 paying gave ' || (select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v12') and status = 'held') || ' vouchers, not 2');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v12') = 8, '11 paying took ' || 10 - pg_temp.tvs_stock('v12') || ', not 2');
  raise notice 'PASS 11: the FOC taken off, then cancelled and reopened twice before it was paid: 2 vouchers and 8 (not 4 and 6)';
end $$;

-- ===== 12. A completed FOC whose vouchers were moved to another store =====
do $$
declare inv uuid; st2 uuid := pg_temp.tvs_id('store2'); c2 uuid := pg_temp.tvs_id('friend');
begin
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v13'), 'quantity', 2,
      'foc_quantity', 2, 'foc_reason', 'TVS goodwill')));
  perform confirm_foc_invoice(inv, 'TVS 12 confirm');
  if not exists (select 1 from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v13')) then
    perform issue_sold_vouchers_for_invoice(inv); end if;
  perform transfer_invoice_unused_benefit((select id from invoice_benefit_values where invoice_id = inv), c2, st2,
    'TVS 12 for a friend at the other store', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v13') = 10
      and (select current_qty from voucher_store_stock where voucher_id = pg_temp.tvs_id('v13') and store_id = st2) = 8,
    '12 fixture: moved, the other store holds the 2 out');
  perform cancel_invoice_recorded(inv, 'TVS 12 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v13') = 10
      and (select current_qty from voucher_store_stock where voucher_id = pg_temp.tvs_id('v13') and store_id = st2) = 10,
    '12 cancelling gave the 2 back at the other store');
  -- The 2 the reopening gives again are not on a row, at the other store,
  -- where they are given and their stock is taken.
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, true) = 'store2:2',
    '12 before the reopening, the units not on a row: "' || pg_temp.tvs_unrec(inv, true) || '", not "store2:2"');
  perform reopen_invoice(inv, 'TVS 12 reopen', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_rows(inv) = 'store2:2',
    '12 the reopening recorded its row at "' || pg_temp.tvs_rows(inv) || '", not at the other store ("store2:2")');
  perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, false) = '' and pg_temp.tvs_unrec(inv, true) = '',
    '12 reopened, the units not on a row: "' || pg_temp.tvs_unrec(inv, false) || '" and "' || pg_temp.tvs_unrec(inv, true) || '", not none');
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'completed_foc', '12 reopened to completed FOC');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v13') = 10,
    '12 reopening took ' || 10 - pg_temp.tvs_stock('v13') || ' at the invoice''s store, where nothing is out');
  perform pg_temp.tvs_check((select current_qty from voucher_store_stock where voucher_id = pg_temp.tvs_id('v13') and store_id = st2) = 8,
    '12 reopening gave the 2 again at the other store, taking its stock there');
  perform pg_temp.tvs_check((select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v13')
                               and status = 'held' and customer_id = c2 and store_id = st2) = 2,
    '12 the friend holds the 2 vouchers again');
  perform cancel_invoice_recorded(inv, 'TVS 12 cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v13') = 10
      and (select current_qty from voucher_store_stock where voucher_id = pg_temp.tvs_id('v13') and store_id = st2) = 10,
    '12 cancelling again: ' || pg_temp.tvs_stock('v13') || ' and ' ||
    (select current_qty from voucher_store_stock where voucher_id = pg_temp.tvs_id('v13') and store_id = st2) || ', not 10 and 10');
  perform reopen_invoice(inv, 'TVS 12 reopen again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v13') = 10
      and (select current_qty from voucher_store_stock where voucher_id = pg_temp.tvs_id('v13') and store_id = st2) = 8,
    '12 reopening again: ' || pg_temp.tvs_stock('v13') || ' and ' ||
    (select current_qty from voucher_store_stock where voucher_id = pg_temp.tvs_id('v13') and store_id = st2) || ', not 10 and 8');
  raise notice 'PASS 12: vouchers moved to another store: cancelled 10 and 10, reopened 10 and 8 (not 8 and 8), again the same';
end $$;

-- ===== 12b. (416 only) Moved, cancelled, reopened, the FOC taken off, paid =====
do $$
declare inv uuid; r jsonb; v_old boolean;
begin
  if not pg_temp.tvs_416() then
    raise notice 'SKIP 12b: needs 416 (taking the FOC off a completed FOC invoice)'; return; end if;
  -- 416's file of 10 Oct counts only an Owner's move as moved (B02's to change).
  v_old := pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)
           ~ 'crv\.source_type = ''invoice_benefit_transfer''\s+and crv\.customer_id is distinct from i\.customer_id';
  inv := pg_temp.tvs_foc('v14', 2, 'TVS 12b confirm');
  perform pg_temp.tvs_move(inv, 'TVS 12b for a friend at the other store');
  perform pg_temp.tvs_check(pg_temp.tvs_at('v14', 'store') = 10 and pg_temp.tvs_at('v14', 'store2') = 8, '12b fixture: moved');
  perform cancel_invoice_recorded(inv, 'TVS 12b cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_both('v14') = 20 and pg_temp.tvs_held('v14') = 0,
    '12b cancelled: ' || pg_temp.tvs_both('v14') || ' in the two stores, ' || pg_temp.tvs_held('v14') || ' held, not 20 and 0');
  perform reopen_invoice(inv, 'TVS 12b reopen', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_both('v14') = 18 and pg_temp.tvs_held('v14') = 2,
    '12b reopened: ' || pg_temp.tvs_both('v14') || ' and ' || pg_temp.tvs_held('v14') || ' held, not 18 and 2');
  perform pg_temp.tvs_check(pg_temp.tvs_rows(inv) = 'store2:2',
    '12b the reopening recorded its row at "' || pg_temp.tvs_rows(inv) || '", not at the other store ("store2:2")');
  r := pg_temp.tvs_foc_off(inv, 2, 'TVS 12b not a giveaway');
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'unpaid', '12b the FOC came off');
  if v_old then
    -- The old figures: the friend's vouchers taken back, then given to the buyer.
    perform pg_temp.tvs_check(pg_temp.tvs_both('v14') = 20 and pg_temp.tvs_held('v14') = 0,
      '12b the FOC off (416 of 10 Oct): ' || pg_temp.tvs_both('v14') || ' and ' || pg_temp.tvs_held('v14') || ' held, not 20 and 0');
  else
    -- The friend keeps them, as with no cancel and reopen first (12c).
    perform pg_temp.tvs_check(pg_temp.tvs_both('v14') = 18
        and (select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v14') and status = 'held'
              and customer_id = pg_temp.tvs_id('friend') and store_id = pg_temp.tvs_id('store2')) = 2,
      '12b the FOC off: ' || pg_temp.tvs_show('v14') || ', not 18 with the friend''s 2 held');
  end if;
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 80)));
  perform pg_temp.tvs_check(pg_temp.tvs_both('v14') = 18 and pg_temp.tvs_held('v14') = 2,
    '12b paid: ' || pg_temp.tvs_both('v14') || ' in the two stores with ' || pg_temp.tvs_held('v14') || ' held, not 18 and 2'
    || case when pg_temp.tvs_both('v14') = 20 then ' (vouchers given, no stock taken)' else '' end);
  perform pg_temp.tvs_check(v_old or (select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v14')
                                       and status = 'held' and customer_id = pg_temp.tvs_id('friend')) = 2,
    '12b paid: the friend no longer holds the 2 vouchers');
  perform cancel_invoice_recorded(inv, 'TVS 12b cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_both('v14') = 20 and pg_temp.tvs_held('v14') = 0,
    '12b cancelled again: ' || pg_temp.tvs_both('v14') || ' and ' || pg_temp.tvs_held('v14') || ' held, not 20 and 0');
  if v_old then
    raise notice 'KNOWN FAULT 12b (416, B02''s to change): after a cancel and reopen, taking the FOC off takes back the vouchers moved to the friend and the payment gives them to the buyer; stock stays right (20, 18, 20)';
  else
    raise notice 'PASS 12b: moved, cancelled 20, reopened 18, the FOC off 18 (the friend keeps them), paid 18, cancelled 20 (not 22)';
  end if;
end $$;

-- ===== 12c. (416 only) Moved, the FOC taken off (the friend keeps them), paid, cancelled =====
do $$
declare inv uuid; r jsonb;
begin
  if not pg_temp.tvs_416() then
    raise notice 'SKIP 12c: needs 416 (taking the FOC off a completed FOC invoice)'; return; end if;
  inv := pg_temp.tvs_foc('v15', 2, 'TVS 12c confirm');
  perform pg_temp.tvs_move(inv, 'TVS 12c for a friend at the other store');
  r := pg_temp.tvs_foc_off(inv, 2, 'TVS 12c not a giveaway');
  perform pg_temp.tvs_check(jsonb_array_length(coalesce(r#>'{foc_vouchers,kept_used}', '[]')) = 1,
    '12c the moved vouchers stay with the friend: ' || coalesce((r->'foc_vouchers')::text, '<none>'));
  perform pg_temp.tvs_check(pg_temp.tvs_both('v15') = 18 and pg_temp.tvs_held('v15') = 2,
    '12c the FOC off: ' || pg_temp.tvs_both('v15') || ' and ' || pg_temp.tvs_held('v15') || ' held, not 18 and 2');
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 80)));
  perform pg_temp.tvs_check(pg_temp.tvs_both('v15') = 18 and pg_temp.tvs_held('v15') = 2,
    '12c paid: ' || pg_temp.tvs_both('v15') || ' and ' || pg_temp.tvs_held('v15') || ' held, not 18 and 2');
  perform cancel_invoice_recorded(inv, 'TVS 12c cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_both('v15') = 20 and pg_temp.tvs_held('v15') = 0,
    '12c cancelled: ' || pg_temp.tvs_both('v15') || ' and ' || pg_temp.tvs_held('v15') || ' held, not 20 and 0');
  raise notice 'PASS 12c: moved, the FOC off (the friend keeps them), paid 18, cancelled 20 (not 22)';
end $$;

-- ===== 12d. Two vouchers of a completed FOC, one moved to another store =====
do $$
declare inv uuid;
begin
  inv := create_invoice(pg_temp.tvs_id('store'), pg_temp.tvs_id('customer'), null,
    jsonb_build_array(
      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v28'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'TVS goodwill'),
      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.tvs_id('v28'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'TVS goodwill')));
  perform confirm_foc_invoice(inv, 'TVS 12d confirm');
  if not exists (select 1 from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v28')) then
    perform issue_sold_vouchers_for_invoice(inv); end if;
  perform transfer_invoice_unused_benefit(
    (select b.id from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
      where b.invoice_id = inv and v.status = 'held' order by b.id limit 1),
    pg_temp.tvs_id('friend'), pg_temp.tvs_id('store2'), 'TVS 12d one for a friend at the other store', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_at('v28', 'store') = 9 and pg_temp.tvs_at('v28', 'store2') = 9 and pg_temp.tvs_held('v28') = 2,
    '12d fixture: one moved, ' || pg_temp.tvs_show('v28') || ', not 9/9 held 2');
  for k in 1 .. 2 loop
    perform cancel_invoice_recorded(inv, 'TVS 12d cancel ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_at('v28', 'store') = 10 and pg_temp.tvs_at('v28', 'store2') = 10 and pg_temp.tvs_held('v28') = 0,
      '12d cancelled (' || k || '): ' || pg_temp.tvs_show('v28') || ', not 10/10 held 0');
    perform reopen_invoice(inv, 'TVS 12d reopen ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_at('v28', 'store') = 9 and pg_temp.tvs_at('v28', 'store2') = 9 and pg_temp.tvs_held('v28') = 2,
      '12d reopened (' || k || '): ' || pg_temp.tvs_show('v28') || ', not 9/9 held 2');
    -- Each unit's row sits where its voucher is and its stock was taken.
    perform pg_temp.tvs_check(
      (select coalesce(sum(quantity), 0) from invoice_voucher_movements where invoice_id = inv and store_id = pg_temp.tvs_id('store')) = 1
      and (select coalesce(sum(quantity), 0) from invoice_voucher_movements where invoice_id = inv and store_id = pg_temp.tvs_id('store2')) = 1,
      '12d reopened (' || k || '): the rows are "' || pg_temp.tvs_rows(inv) || '", not one unit at each store');
  end loop;
  raise notice 'PASS 12d: one of two moved to another store: cancelled 10/10, reopened 9/9 with one unit recorded at each store, twice';
end $$;

-- ===== 13. A paid sale corrected to another customer and store =====
do $$
declare inv uuid; x jsonb;
begin
  inv := pg_temp.tvs_paid_sale('v16', 1, 2);
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', 40)) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
      'customer_id', pg_temp.tvs_id('friend'), 'store_id', pg_temp.tvs_id('store2'), 'benefit_action', 'transfer'),
    'TVS 13 wrong customer and store', gen_random_uuid());
  perform pg_temp.tvs_check((select store_id from invoices where id = inv) = pg_temp.tvs_id('store2')
      and (select sum(quantity) from customer_reward_vouchers where voucher_id = pg_temp.tvs_id('v16') and status = 'held'
            and customer_id = pg_temp.tvs_id('friend') and store_id = pg_temp.tvs_id('store2')) = 2,
    '13 fixture: the invoice and its 2 vouchers moved to the friend at the other store');
  -- 417: the vouchers' stock moved with them.
  perform pg_temp.tvs_check(pg_temp.tvs_at('v16', 'store') = 10 and pg_temp.tvs_at('v16', 'store2') = 8,
    '13 corrected: ' || pg_temp.tvs_show('v16') || ', not 10/8 (the stock did not move with the vouchers)');
  for k in 1 .. 3 loop
    perform cancel_invoice_recorded(inv, 'TVS 13 cancel ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_at('v16', 'store') = 10 and pg_temp.tvs_at('v16', 'store2') = 10 and pg_temp.tvs_held('v16') = 0,
      '13 cancelled (' || k || '): ' || pg_temp.tvs_show('v16') || ', not 10/10 held 0');
    perform reopen_invoice(inv, 'TVS 13 reopen ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_at('v16', 'store') = 10 and pg_temp.tvs_at('v16', 'store2') = 8 and pg_temp.tvs_held('v16') = 2,
      '13 reopened (' || k || '): ' || pg_temp.tvs_show('v16') || ', not 10/8 held 2');
  end loop;
  -- Too little stock at the new store: the correction is refused, nothing moves.
  inv := pg_temp.tvs_paid_sale('v27', 1, 2);
  update voucher_store_stock set current_qty = 1 where voucher_id = pg_temp.tvs_id('v27') and store_id = pg_temp.tvs_id('store2');
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', 40)) into x
    from invoice_items it where it.invoice_id = inv;
  begin
    perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', pg_temp.tvs_id('friend'), 'store_id', pg_temp.tvs_id('store2'), 'benefit_action', 'transfer'),
      'TVS 13 short at the new store', gen_random_uuid());
    raise exception 'FAIL 13 a correction moved 2 vouchers to a store holding 1';
  exception when others then
    if sqlerrm not like 'Not enough voucher stock at the destination store%' then raise; end if;
  end;
  perform pg_temp.tvs_check(pg_temp.tvs_at('v27', 'store') = 8 and pg_temp.tvs_at('v27', 'store2') = 1
      and (select store_id from invoices where id = inv) = pg_temp.tvs_id('store'),
    '13 refused, yet something moved: ' || pg_temp.tvs_show('v27'));
  raise notice 'PASS 13: a paid sale moved to another customer and store: its stock moves too (10/8), cancelled 10/10, reopened 10/8, three times; short at the new store, refused';
end $$;

-- ===== 13b. (416 only) The FOC taken off and the invoice moved in one save =====
do $$
declare inv uuid; x jsonb;
begin
  if not pg_temp.tvs_416() then
    raise notice 'SKIP 13b: needs 416 (taking the FOC off a completed FOC invoice)'; return; end if;
  inv := pg_temp.tvs_foc('v26', 2, 'TVS 13b confirm');
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', 40, 'foc_quantity', 0)) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
      'customer_id', pg_temp.tvs_id('friend'), 'store_id', pg_temp.tvs_id('store2'), 'benefit_action', 'transfer'),
    'TVS 13b not a giveaway, and the wrong customer and store', gen_random_uuid());
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'unpaid', '13b the FOC came off');
  perform pg_temp.tvs_check(pg_temp.tvs_both('v26') + pg_temp.tvs_held('v26') = 20 and pg_temp.tvs_at('v26', 'store') = 10,
    '13b the FOC off and moved: ' || pg_temp.tvs_show('v26') || ' (the first store not 10, or stock and vouchers apart)');
  perform pg_temp.tvs_pay_rest(inv);
  perform pg_temp.tvs_check(pg_temp.tvs_at('v26', 'store') = 10 and pg_temp.tvs_at('v26', 'store2') = 8 and pg_temp.tvs_held('v26') = 2,
    '13b paid: ' || pg_temp.tvs_show('v26') || ', not 10/8 held 2');
  perform cancel_invoice_recorded(inv, 'TVS 13b cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_at('v26', 'store') = 10 and pg_temp.tvs_at('v26', 'store2') = 10 and pg_temp.tvs_held('v26') = 0,
    '13b cancelled: ' || pg_temp.tvs_show('v26') || ', not 10/10 held 0 (before 417: 8/12)');
  perform reopen_invoice(inv, 'TVS 13b reopen', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_at('v26', 'store') = 10 and pg_temp.tvs_at('v26', 'store2') = 8 and pg_temp.tvs_held('v26') = 2,
    '13b reopened: ' || pg_temp.tvs_show('v26') || ', not 10/8 held 2');
  perform cancel_invoice_recorded(inv, 'TVS 13b cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_at('v26', 'store') = 10 and pg_temp.tvs_at('v26', 'store2') = 10 and pg_temp.tvs_held('v26') = 0,
    '13b cancelled again: ' || pg_temp.tvs_show('v26') || ', not 10/10 held 0');
  raise notice 'PASS 13b: the FOC off and moved in one save, paid 10/8, cancelled 10/10 (not 8/12), reopened 10/8, cancelled 10/10';
end $$;

-- ===== 14. Cancelled, reopened, then moved, the FOC taken off, paid, cancelled =====
do $$
declare inv uuid; r jsonb;
begin
  if not pg_temp.tvs_416() then
    raise notice 'SKIP 14: needs 416 (taking the FOC off a completed FOC invoice)'; return; end if;
  inv := pg_temp.tvs_foc('v17', 2, 'TVS 14 confirm');
  perform cancel_invoice_recorded(inv, 'TVS 14 cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'TVS 14 reopen', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_both('v17') = 18 and pg_temp.tvs_held('v17') = 2, '14 reopened: 18 and 2 held');
  perform pg_temp.tvs_move(inv, 'TVS 14 for a friend at the other store');
  r := pg_temp.tvs_foc_off(inv, 2, 'TVS 14 not a giveaway');
  perform pg_temp.tvs_check(pg_temp.tvs_both('v17') = 18 and pg_temp.tvs_held('v17') = 2,
    '14 moved and the FOC off: ' || pg_temp.tvs_both('v17') || ' and ' || pg_temp.tvs_held('v17') || ' held, not 18 and 2');
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 80)));
  perform pg_temp.tvs_check(pg_temp.tvs_both('v17') = 18 and pg_temp.tvs_held('v17') = 2,
    '14 paid: ' || pg_temp.tvs_both('v17') || ' and ' || pg_temp.tvs_held('v17') || ' held, not 18 and 2');
  perform cancel_invoice_recorded(inv, 'TVS 14 cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_both('v17') = 20 and pg_temp.tvs_held('v17') = 0,
    '14 cancelled again: ' || pg_temp.tvs_both('v17') || ' and ' || pg_temp.tvs_held('v17') || ' held, not 20 and 0');
  raise notice 'PASS 14: cancelled, reopened, moved, the FOC off, paid 18, cancelled 20 (not 22)';
end $$;

-- ===== 15. (416 only) The FOC taken off with the quantity raised from 2 to 3 =====
do $$
declare inv uuid;
begin
  if not pg_temp.tvs_416() then
    raise notice 'SKIP 15: needs 416 (taking the FOC off a completed FOC invoice)'; return; end if;
  inv := pg_temp.tvs_foc('v18', 2, 'TVS 15 confirm');
  perform pg_temp.tvs_foc_off(inv, 3, 'TVS 15 not a giveaway, and 3');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v18') = 10 and pg_temp.tvs_held('v18') = 0, '15 the FOC off: 10 and none held');
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 120)));
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v18') = 7 and pg_temp.tvs_held('v18') = 3,
    '15 paid: stock ' || pg_temp.tvs_stock('v18') || ' with ' || pg_temp.tvs_held('v18') || ' held, not 7 and 3');
  for k in 1 .. 2 loop
    perform cancel_invoice_recorded(inv, 'TVS 15 cancel ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_stock('v18') = 10 and pg_temp.tvs_held('v18') = 0,
      '15 cancelled (' || k || '): stock ' || pg_temp.tvs_stock('v18') || ', not 10');
    if k = 1 then
      perform reopen_invoice(inv, 'TVS 15 reopen', gen_random_uuid());
      perform pg_temp.tvs_check(pg_temp.tvs_stock('v18') = 7 and pg_temp.tvs_held('v18') = 3,
        '15 reopened: stock ' || pg_temp.tvs_stock('v18') || ' with ' || pg_temp.tvs_held('v18') || ' held, not 7 and 3');
    end if;
  end loop;
  raise notice 'PASS 15: the FOC off with 3, paid 7, cancelled 10 (not 11), reopened 7, cancelled 10';
end $$;

-- ===== 15b. (416 only) The FOC taken off with the quantity lowered from 2 to 1 =====
do $$
declare inv uuid;
begin
  if not pg_temp.tvs_416() then
    raise notice 'SKIP 15b: needs 416 (taking the FOC off a completed FOC invoice)'; return; end if;
  inv := pg_temp.tvs_foc('v20', 2, 'TVS 15b confirm');
  perform pg_temp.tvs_foc_off(inv, 1, 'TVS 15b not a giveaway, and 1');
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.tvs_id('pm'), 'amount', 40)));
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v20') = 9 and pg_temp.tvs_held('v20') = 1,
    '15b paid: stock ' || pg_temp.tvs_stock('v20') || ' with ' || pg_temp.tvs_held('v20') || ' held, not 9 and 1');
  for k in 1 .. 3 loop
    perform cancel_invoice_recorded(inv, 'TVS 15b cancel ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_stock('v20') = 10 and pg_temp.tvs_held('v20') = 0,
      '15b cancelled (' || k || '): stock ' || pg_temp.tvs_stock('v20') || ', not 10');
    perform reopen_invoice(inv, 'TVS 15b reopen ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_stock('v20') = 9 and pg_temp.tvs_held('v20') = 1,
      '15b reopened (' || k || '): stock ' || pg_temp.tvs_stock('v20') || ' with ' || pg_temp.tvs_held('v20') || ' held, not 9 and 1');
    perform pg_temp.tvs_check(pg_temp.tvs_unrec(inv, false) = '',
      '15b reopened (' || k || '), the units not on a row: "' || pg_temp.tvs_unrec(inv, false) || '", not none');
  end loop;
  perform cancel_invoice_recorded(inv, 'TVS 15b cancel at the end', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v20') = 10, '15b cancelled at the end: stock ' || pg_temp.tvs_stock('v20') || ', not 10');
  raise notice 'PASS 15b: the FOC off with 1, paid 9, then cancelled 10 and reopened 9 three times, cancelled 10';
end $$;

-- ===== 16. A unit with no voucher behind it, after the vouchers were moved =====
do $$
declare inv uuid;
begin
  inv := pg_temp.tvs_paid_sale('v19', 1, 2);
  update voucher_store_stock set current_qty = current_qty - 1 where voucher_id = pg_temp.tvs_id('v19') and store_id = pg_temp.tvs_id('store');
  insert into invoice_voucher_movements(invoice_id, store_id, voucher_id, quantity, reason, created_by)
    values (inv, pg_temp.tvs_id('store'), pg_temp.tvs_id('v19'), 1, 'TVS 16 taken, not issued', pg_temp.tvs_id('own'));
  perform pg_temp.tvs_move(inv, 'TVS 16 for a friend at the other store');
  perform pg_temp.tvs_check(pg_temp.tvs_both('v19') = 17, '16 fixture: 3 out in the two stores');
  perform cancel_invoice_recorded(inv, 'TVS 16 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_both('v19') = 20,
    '16 cancelled: ' || pg_temp.tvs_both('v19') || ' in the two stores, not 20 (the unit never issued did not come back)');
  perform pg_temp.tvs_check(pg_temp.tvs_at('v19', 'store') = 10,
    '16 the unit never issued came back at the store of its row: ' || pg_temp.tvs_at('v19', 'store'));
  raise notice 'PASS 16: a unit taken with no voucher behind it comes back once, after the vouchers were moved (17 -> 20)';
end $$;

-- ===== 17. A paid sale's voucher line lowered, cancelled and reopened three times =====
do $$
declare inv uuid;
begin
  inv := pg_temp.tvs_paid_sale('v21', 1, 2);
  perform pg_temp.tvs_set_qty(inv, 1, false, 'TVS 17 only 1');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v21') = 8 and pg_temp.tvs_held('v21') = 2,
    '17 fixture: lowered, ' || pg_temp.tvs_show('v21') || ', not 8 held 2');
  for k in 1 .. 3 loop
    perform cancel_invoice_recorded(inv, 'TVS 17 cancel ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_stock('v21') = 10 and pg_temp.tvs_held('v21') = 0,
      '17 cancelled (' || k || '): ' || pg_temp.tvs_show('v21') || ', not 10 held 0');
    perform reopen_invoice(inv, 'TVS 17 reopen ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_stock('v21') = 8 and pg_temp.tvs_held('v21') = 2,
      '17 reopened (' || k || '): ' || pg_temp.tvs_show('v21') || ', not 8 held 2');
  end loop;
  perform pg_temp.tvs_check(not exists (select 1 from invoice_voucher_movements where invoice_id = inv
                                         and reason like 'Recorded on reopening%'),
    '17 a paid invoice''s reopening wrote a ''Recorded on reopening'' row');
  raise notice 'PASS 17: a paid line lowered from 2 to 1: cancelled 10, reopened 8, three times (not 11, 12, 13)';
end $$;

-- ===== 18. Lowered, then the extra unit refunded with its voucher, then cancelled =====
do $$
declare inv uuid; b record;
begin
  inv := pg_temp.tvs_paid_sale('v22', 1, 2);
  perform pg_temp.tvs_set_qty(inv, 1, false, 'TVS 18 only 1');
  select * into b from invoice_benefit_values where invoice_id = inv order by id limit 1;
  perform refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', b.invoice_item_id, 'amount', 40,
      'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', 40)))),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv order by id limit 1), 'amount', 40)),
    '[]', 'TVS 18 the extra one back', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v22') = 9 and pg_temp.tvs_held('v22') = 1,
    '18 fixture: the extra unit refunded, ' || pg_temp.tvs_show('v22') || ', not 9 held 1');
  perform cancel_invoice_recorded(inv, 'TVS 18 cancel', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v22') = 10 and pg_temp.tvs_held('v22') = 0,
    '18 cancelled: ' || pg_temp.tvs_show('v22') || ', not 10 held 0');
  raise notice 'PASS 18: lowered, the extra unit refunded (9), cancelled 10 (not 11)';
end $$;

-- ===== 19. A completed FOC's voucher line lowered while it stays FOC =====
do $$
declare inv uuid;
begin
  inv := pg_temp.tvs_foc('v23', 2, 'TVS 19 confirm');
  perform pg_temp.tvs_set_qty(inv, 1, true, 'TVS 19 only 1');
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'completed_foc', '19 still FOC');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v23') = 8 and pg_temp.tvs_held('v23') = 2,
    '19 fixture: lowered, ' || pg_temp.tvs_show('v23') || ', not 8 held 2');
  for k in 1 .. 3 loop
    perform cancel_invoice_recorded(inv, 'TVS 19 cancel ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_stock('v23') = 10 and pg_temp.tvs_held('v23') = 0,
      '19 cancelled (' || k || '): ' || pg_temp.tvs_show('v23') || ', not 10 held 0');
    perform reopen_invoice(inv, 'TVS 19 reopen ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_stock('v23') = 8 and pg_temp.tvs_held('v23') = 2,
      '19 reopened (' || k || '): ' || pg_temp.tvs_show('v23') || ', not 8 held 2');
  end loop;
  raise notice 'PASS 19: a completed FOC lowered from 2 to 1: cancelled 10, reopened 8, three times (not 10, 11, 12)';
end $$;

-- ===== 20. A paid sale's voucher line raised, the rest paid, cancelled and reopened three times =====
do $$
declare inv uuid;
begin
  inv := pg_temp.tvs_paid_sale('v24', 1, 2);
  perform pg_temp.tvs_set_qty(inv, 3, false, 'TVS 20 one more');
  perform pg_temp.tvs_pay_rest(inv);
  perform pg_temp.tvs_check((select status from invoices where id = inv) = 'paid', '20 paid');
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v24') = 7 and pg_temp.tvs_held('v24') = 2,
    '20 fixture: raised and paid, ' || pg_temp.tvs_show('v24') || ', not 7 held 2');
  for k in 1 .. 3 loop
    perform cancel_invoice_recorded(inv, 'TVS 20 cancel ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_stock('v24') = 10 and pg_temp.tvs_held('v24') = 0,
      '20 cancelled (' || k || '): ' || pg_temp.tvs_show('v24') || ', not 10 held 0');
    perform reopen_invoice(inv, 'TVS 20 reopen ' || k, gen_random_uuid());
    perform pg_temp.tvs_check(pg_temp.tvs_stock('v24') = 7 and pg_temp.tvs_held('v24') = 2,
      '20 reopened (' || k || '): ' || pg_temp.tvs_show('v24') || ', not 7 held 2');
  end loop;
  raise notice 'PASS 20: a paid line raised from 2 to 3 and paid: cancelled 10, reopened 7, three times (not 10, then 9 and 9)';
end $$;

-- ===== 21. Cancelled and reopened, then raised and paid, then cancelled =====
do $$
declare inv uuid;
begin
  inv := pg_temp.tvs_paid_sale('v25', 1, 2);
  perform cancel_invoice_recorded(inv, 'TVS 21 cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'TVS 21 reopen', gen_random_uuid());
  perform pg_temp.tvs_set_qty(inv, 3, false, 'TVS 21 one more');
  perform pg_temp.tvs_pay_rest(inv);
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v25') = 7 and pg_temp.tvs_held('v25') = 2,
    '21 fixture: raised and paid, ' || pg_temp.tvs_show('v25') || ', not 7 held 2');
  perform cancel_invoice_recorded(inv, 'TVS 21 cancel again', gen_random_uuid());
  perform pg_temp.tvs_check(pg_temp.tvs_stock('v25') = 10 and pg_temp.tvs_held('v25') = 0,
    '21 cancelled again: ' || pg_temp.tvs_show('v25') || ', not 10 held 0');
  raise notice 'PASS 21: cancelled, reopened, raised to 3 and paid (7), cancelled 10 (not 9)';
end $$;

rollback;
