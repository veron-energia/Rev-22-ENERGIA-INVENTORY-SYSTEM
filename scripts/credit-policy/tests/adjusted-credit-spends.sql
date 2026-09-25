-- Credit added with "Adjust" can be spent (353).
--
-- Before 353, adjust_customer_credit stamped its lots 'manual_adjustment',
-- which credit_lot_policy() did not recognise, so they fell to 'needs_review'
-- and the till refused them with "Only 0 of the requested 60.00 could be funded
-- by eligible credit" — while the customer View showed the full balance.
--
-- Every check here goes through the real payment path (record_invoice_payment
-- with the paid-credit wallet method), because that is where staff hit it. A
-- check on the function's text would not have caught the original bug.
--
-- The second block covers 353's statement fix: once adjusted credit can be
-- spent it can also come back (a refund, a payment corrected away), and the
-- customer View's statement used to subtract that returned credit, ending at
-- -20.00 while the header said 100.00. It goes through refund_invoice_recorded,
-- correct_invoice_payment and reverse_credit_lot.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
do $$
declare
  own uuid := gen_random_uuid();
  st uuid; st2 uuid; c uuid; wpm uuid; svc uuid;
  adj uuid; lot uuid; inv uuid; v_drawn numeric; v_src text; v_msg text; v_before numeric;
begin
  insert into auth.users(id,email) values (own,'acs@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'ACS Owner','acs@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into stores(name,code,country_code) values ('ACS A','ACSA','SG') returning id into st;
  insert into stores(name,code,country_code) values ('ACS B','ACSB','SG') returning id into st2;
  insert into customers(full_name,phone) values ('ACS Buyer','+6598919353') returning id into c;
  select id into wpm from payment_methods where wallet_category = 'paid' and is_system limit 1;
  if wpm is null then raise exception 'FIXTURE: no system paid-credit wallet payment method'; end if;

  svc := (upsert_therapy_service(null,'ACS-S','ACS Session',60,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
  perform set_therapy_service_store(svc, st,  true, null);
  perform set_therapy_service_store(svc, st2, true, null);

  -- ── the reported symptom, now fixed ──────────────────────────────────────
  -- Store-scoped, like the production adjustments that failed.
  adj := adjust_customer_credit(c, 'paid', 'increase', 100, 'Test top-up', null, null, null, st, null);
  select lot_id into lot from customer_credit_adjustments where id = adj;

  if credit_lot_policy_for(lot) is distinct from 'open' then
    raise exception 'FAIL: an adjusted lot still resolves to policy %', credit_lot_policy_for(lot); end if;

  inv := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
  begin
    perform record_invoice_payment(inv,
      jsonb_build_array(jsonb_build_object('payment_method_id', wpm, 'amount', 60)), gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL: adjusted credit still cannot pay — the till said: %', v_msg;
  end;

  select coalesce(sum(a.amount),0), string_agg(distinct l.source_type, ',')
    into v_drawn, v_src
    from invoice_line_credit_allocations a join customer_credit_lots l on l.id = a.lot_id
   where a.invoice_id = inv;
  if v_drawn <> 60 or v_src <> 'manual_adjustment' then
    raise exception 'FAIL: expected 60 drawn from the adjusted lot, got % from %', v_drawn, v_src; end if;

  -- The View and the lot agree afterwards: 40 left.
  if (select remaining_amount from customer_credit_lots where id = lot) <> 40 then
    raise exception 'FAIL: the adjusted lot shows % left, expected 40',
      (select remaining_amount from customer_credit_lots where id = lot); end if;
  if (customer_credit_balances(c)->'categories'->>'paid')::numeric <> 40 then
    raise exception 'FAIL: the View shows % paid credit, the lot holds 40',
      customer_credit_balances(c)->'categories'->>'paid'; end if;

  -- Store scoping does not stop it being spent elsewhere, same as opening balance.
  inv := create_invoice(st2, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
  begin
    perform record_invoice_payment(inv,
      jsonb_build_array(jsonb_build_object('payment_method_id', wpm, 'amount', 40)), gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL: adjusted credit scoped to store A could not pay at store B: %', v_msg;
  end;

  -- ── what must not change ─────────────────────────────────────────────────
  -- Opening balance still works exactly as before.
  perform add_legacy_credit(c, 'paid', 50, sg_today(), st, null, 'Opening', null, null);
  inv := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
  begin
    perform record_invoice_payment(inv,
      jsonb_build_array(jsonb_build_object('payment_method_id', wpm, 'amount', 50)), gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL: opening balance no longer spends: %', v_msg;
  end;

  -- An ordinary decrease still works, and leaves the View and lots agreeing.
  adj := adjust_customer_credit(c, 'paid', 'increase', 30, 'Top-up', null, null, null, st, null);
  v_before := (customer_credit_balances(c)->'categories'->>'paid')::numeric;
  perform adjust_customer_credit(c, 'paid', 'decrease', 10, 'Correction', null, null, null, st, null);
  if (customer_credit_balances(c)->'categories'->>'paid')::numeric <> v_before - 10 then
    raise exception 'FAIL: a decrease of 10 moved the View from % to %',
      v_before, customer_credit_balances(c)->'categories'->>'paid'; end if;
  if (select coalesce(sum(remaining_amount),0) from customer_credit_lots
       where customer_id = c and category = 'paid' and status = 'active')
     <> (customer_credit_balances(c)->'categories'->>'paid')::numeric then
    raise exception 'FAIL: after a decrease the lots and the View disagree'; end if;

  -- A decrease larger than the balance is still refused cleanly.
  begin
    perform adjust_customer_credit(c, 'paid', 'decrease', 100000, 'Too much', null, null, null, st, null);
    raise exception 'FAIL: a decrease beyond the balance was accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'Cannot decrease' then
      raise exception 'FAIL: oversized decrease refused for the wrong reason: %', v_msg; end if;
  end;

  -- Package credit keeps its restriction: 353 opens manual adjustments only.
  if credit_lot_policy('credit_package','paid',true) <> 'package_paid' then
    raise exception 'FAIL: package credit lost its restriction'; end if;

  raise notice 'PASS: adjusted credit spends at the till like opening balance, and nothing else loosened.';
end $$;

-- ── 353: the customer View's statement agrees with the balance ─────────────
-- The statement's last running balance must equal what the customer's lots
-- hold, the header must say the same, and the running balance must never dip
-- below zero on the way (the reported symptom was -20.00).
create function pg_temp.acs_statement_agrees(p_customer uuid, p_when text) returns numeric
language plpgsql as $f$
declare v_last numeric; v_lots numeric; v_head numeric; v_min numeric;
begin
  select s.wallet_balance into v_last
    from public.customer_credit_statement(p_customer) with ordinality as s
   order by s.ordinality desc limit 1;
  select coalesce(sum(l.remaining_amount),0) into v_lots
    from public.customer_credit_lots l where l.customer_id = p_customer;
  if v_last is distinct from v_lots then
    raise exception 'FAIL: %: the statement ends at % but the customer''s lots hold %', p_when, v_last, v_lots; end if;
  v_head := (public.customer_credit_balances(p_customer)->'categories'->>'paid')::numeric;
  if v_head is distinct from v_lots then
    raise exception 'FAIL: %: the View''s header shows % paid credit but the lots hold %', p_when, v_head, v_lots; end if;
  select min(s.wallet_balance) into v_min from public.customer_credit_statement(p_customer) s;
  if v_min < 0 then
    raise exception 'FAIL: %: the statement''s running balance went down to %', p_when, v_min; end if;
  return v_last;
end $f$;

-- The newest statement row from p_source: 'returned' must sit in credit_added
-- as "Credit returned" and ADD to the running balance; 'reversed' must sit in
-- credit_reversed as "Credit reversed" and SUBTRACT.
create function pg_temp.acs_row_is(p_customer uuid, p_source text, p_kind text, p_amount numeric, p_when text) returns void
language plpgsql as $f$
declare r record; v_prev numeric;
begin
  select s.*, s.ordinality as pos into r
    from public.customer_credit_statement(p_customer) with ordinality as s
   where s.source = p_source
   order by s.ordinality desc limit 1;
  if not found then
    raise exception 'FAIL: %: no % row on the statement', p_when, p_source; end if;
  select s.wallet_balance into v_prev
    from public.customer_credit_statement(p_customer) with ordinality as s
   where s.ordinality = r.pos - 1;
  if p_kind = 'returned' then
    if r.credit_added is distinct from p_amount or r.credit_used is not null or r.credit_reversed is not null
       or r.description not like 'Credit returned%' then
      raise exception 'FAIL: %: the % row should show % under credit added as "Credit returned"; it reads "%" (added %, used %, reversed %)',
        p_when, p_source, p_amount, r.description, r.credit_added, r.credit_used, r.credit_reversed; end if;
    if r.wallet_balance is distinct from v_prev + p_amount then
      raise exception 'FAIL: %: returned credit of % should add to the running balance, which went % -> %',
        p_when, p_amount, v_prev, r.wallet_balance; end if;
  elsif p_kind = 'reversed' then
    if r.credit_reversed is distinct from p_amount or r.credit_added is not null or r.credit_used is not null
       or r.description not like 'Credit reversed%' then
      raise exception 'FAIL: %: the % row should show % under credit reversed as "Credit reversed"; it reads "%" (added %, used %, reversed %)',
        p_when, p_source, p_amount, r.description, r.credit_added, r.credit_used, r.credit_reversed; end if;
    if r.wallet_balance is distinct from v_prev - p_amount then
      raise exception 'FAIL: %: a reversal of % should subtract from the running balance, which went % -> %',
        p_when, p_amount, v_prev, r.wallet_balance; end if;
  else
    raise exception 'acs_row_is: unknown kind %', p_kind;
  end if;
end $f$;

do $$
declare
  own uuid := gen_random_uuid();
  sfx text := substr(md5(random()::text || clock_timestamp()::text), 1, 8);
  st uuid; c uuid; wpm uuid; cash uuid; svc uuid;
  adj uuid; lot uuid; lot25 uuid; inv uuid; v_item uuid; pay uuid; v_msg text; v_status text;
begin
  insert into auth.users(id,email) values (own, 'acs-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own, 'ACS Owner '||sfx, 'acs-'||sfx||'@tests.invalid', 'owner');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into stores(name,code,country_code) values ('ACS R '||sfx, 'ACSR'||sfx, 'SG') returning id into st;
  insert into customers(full_name,phone)
    values ('ACS Statement '||sfx, '+6591'||lpad(floor(random()*1000000)::int::text, 6, '0')) returning id into c;
  insert into payment_methods(name,is_active) values ('ACS Cash '||sfx, true) returning id into cash;
  select id into wpm from payment_methods where wallet_category = 'paid' and is_system limit 1;
  if wpm is null then raise exception 'FIXTURE: no system paid-credit wallet payment method'; end if;

  svc := (upsert_therapy_service(null,'ACSR-'||sfx,'ACS Statement Session '||sfx,60,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);

  adj := adjust_customer_credit(c, 'paid', 'increase', 100, 'Test top-up', null, null, null, st, null);
  select lot_id into lot from customer_credit_adjustments where id = adj;
  perform pg_temp.acs_statement_agrees(c, 'after the adjustment');

  -- ── a refund puts the credit back, and the statement adds it back ─────────
  inv := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform record_invoice_payment(inv,
    jsonb_build_array(jsonb_build_object('payment_method_id', wpm, 'amount', 60)), gen_random_uuid());
  if pg_temp.acs_statement_agrees(c, 'after spending 60') <> 40 then
    raise exception 'FAIL: spending 60 of 100 adjusted credit should leave 40 on the statement'; end if;

  select id into v_item from invoice_items where invoice_id = inv;
  select id into pay from invoice_payments where invoice_id = inv;
  begin
    perform refund_invoice_recorded(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', v_item, 'amount', 60)),
      jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 60)),
      '[]'::jsonb, 'Refund test', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL: an invoice paid with adjusted credit could not be refunded: %', v_msg;
  end;
  if (select remaining_amount from customer_credit_lots where id = lot) <> 100 then
    raise exception 'FAIL: the refund should put the adjusted lot back to 100, it holds %',
      (select remaining_amount from customer_credit_lots where id = lot); end if;
  -- The reported case: the lot and header said 100.00, the statement -20.00.
  if pg_temp.acs_statement_agrees(c, 'after the refund') <> 100 then
    raise exception 'FAIL: after the refund the statement should end at 100'; end if;
  perform pg_temp.acs_row_is(c, 'invoice_payment_refund', 'returned', 60, 'the refund');

  -- ── a wallet payment corrected away to cash puts the credit back too ──────
  inv := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform record_invoice_payment(inv,
    jsonb_build_array(jsonb_build_object('payment_method_id', wpm, 'amount', 60)), gen_random_uuid());
  select id into pay from invoice_payments where invoice_id = inv;
  begin
    perform correct_invoice_payment(pay, 60, sg_today(), cash, 'Paid in cash, not credit', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL: a wallet payment of adjusted credit could not be corrected to cash: %', v_msg;
  end;
  select status::text into v_status from invoices where id = inv;
  if v_status <> 'paid' then
    raise exception 'FAIL: corrected to the same amount in cash, the invoice should stay paid, it is %', v_status; end if;
  if (select remaining_amount from customer_credit_lots where id = lot) <> 100 then
    raise exception 'FAIL: correcting the payment away should put the adjusted lot back to 100, it holds %',
      (select remaining_amount from customer_credit_lots where id = lot); end if;
  if pg_temp.acs_statement_agrees(c, 'after correcting the payment to cash') <> 100 then
    raise exception 'FAIL: after correcting the payment away the statement should end at 100'; end if;
  perform pg_temp.acs_row_is(c, 'payment_correction', 'returned', 60, 'the payment corrected to cash');

  -- ── a wallet payment lowered by a correction: back 60, spent 20 again ─────
  inv := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
  perform record_invoice_payment(inv,
    jsonb_build_array(jsonb_build_object('payment_method_id', wpm, 'amount', 60)), gen_random_uuid());
  select id into pay from invoice_payments where invoice_id = inv;
  begin
    perform correct_invoice_payment(pay, 20, sg_today(), wpm, 'Only 20 was paid with credit', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL: a wallet payment of adjusted credit could not be lowered: %', v_msg;
  end;
  if (select remaining_amount from customer_credit_lots where id = lot) <> 80 then
    raise exception 'FAIL: lowering a 60 credit payment to 20 should leave the adjusted lot at 80, it holds %',
      (select remaining_amount from customer_credit_lots where id = lot); end if;
  if pg_temp.acs_statement_agrees(c, 'after lowering the credit payment') <> 80 then
    raise exception 'FAIL: after lowering the credit payment the statement should end at 80'; end if;
  perform pg_temp.acs_row_is(c, 'payment_correction', 'returned', 60, 'the lowered credit payment');
  if (select s.credit_used from customer_credit_statement(c) with ordinality as s
       order by s.ordinality desc limit 1) is distinct from 20::numeric then
    raise exception 'FAIL: the lowered payment should show 20 used again as the statement''s last row'; end if;

  -- ── a real reversal still subtracts ──────────────────────────────────────
  adj := adjust_customer_credit(c, 'paid', 'increase', 25, 'Entered twice', null, null, null, st, null);
  select lot_id into lot25 from customer_credit_adjustments where id = adj;
  if pg_temp.acs_statement_agrees(c, 'before the reversal') <> 105 then
    raise exception 'FAIL: a further 25 should bring the statement to 105'; end if;
  perform reverse_credit_lot(lot25, 'Duplicate top-up');
  if pg_temp.acs_statement_agrees(c, 'after reverse_credit_lot') <> 80 then
    raise exception 'FAIL: reversing the 25 lot should bring the statement back to 80'; end if;
  perform pg_temp.acs_row_is(c, 'reversal', 'reversed', 25, 'reverse_credit_lot');

  raise notice 'PASS: refunded and corrected-away adjusted credit shows as "Credit returned" and the statement agrees with the balance; a real reversal still subtracts.';
end $$;
rollback;
