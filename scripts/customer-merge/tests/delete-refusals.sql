-- 418: a customer is not deleted while anything is still open on them
-- (CUSTOMERS-15).
--
-- delete_customer already refused wallet credit, purchased therapy not used
-- and unpaid invoices. It now also refuses a rental not returned or
-- cancelled, an open stock loan, an affiliate record not deleted or an
-- affiliate login, commission still owed to them as a referrer, commission
-- they owe back as a referrer (paid out, then taken back, and not settled:
-- the Owner, 9 Oct 2026), and legacy therapy active or waiting to start.
-- Both commission figures are netted as the Commissions page nets them, with
-- 414's settlements counted. A rental cancelled before it was returned does
-- not refuse. Blocked commission does not refuse: it is never paid, and
-- nothing in the app releases it. Nor does a commission row that only went
-- to recover a take-back, though it never goes in a payout. Each is shown
-- here on its own, then cleared, after which the same customer is deleted.
-- It takes the payouts' lock, then locks the customer's row without waiting
-- for it, starts with the 406 staff check, and is still Owner/Manager only.
--
-- Disposable database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own against a
-- database with production's schema (406 to 414 in; 418 refuses without
-- 414). On a copy of production from before 414, pass a file that applies
-- it (run right after the begin below):
--   psql -v ON_ERROR_STOP=1 [-v prelude=/path/to/414.sql] -f scripts/customer-merge/tests/delete-refusals.sql
-- Fixture names carry T418D, phones +659141 82xx, emails @sig.invalid.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif
\ir ../../../supabase/418_customer_edits_audited_and_phone_search.sql

create temp table t418d(k text primary key, id uuid not null);
create function pg_temp.id(p text) returns uuid language sql stable as $f$ select id from t418d where k = p $f$;
create function pg_temp.check(p_ok boolean, p_what text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL: %', p_what; end if;
end $f$;
create function pg_temp.try(p_who text, p_sql text) returns text language plpgsql as $f$
declare v_out text; v_state text; v_msg text;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', pg_temp.id(p_who), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    execute p_sql into v_out;
    execute 'reset role';
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || chr(9) || v_msg;
  end;
end $f$;
create function pg_temp.del(p_who text, p_key text) returns text language sql as $f$
  select pg_temp.try(p_who, format('select public.delete_customer(%L::uuid, %L, ''T418D test'')::text',
                                   pg_temp.id(p_key), (select full_name from public.customers where id = pg_temp.id(p_key))))
$f$;

-- ===== Fixture =====
do $$
declare k text; v uuid; st uuid; sp uuid; inv uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner', 'manager', 'staff', 'invman', 'nostaff', 'afflogin'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 't418d-' || k || '@sig.invalid') returning id into v;
    insert into t418d values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active)
  select pg_temp.id(x.k), 'T418D ' || x.k, 't418d-' || x.k || '@sig.invalid', x.role::public.user_role, true
    from (values ('owner', 'owner'), ('manager', 'manager'), ('staff', 'staff'), ('invman', 'inventory_manager')) x(k, role);
  insert into public.stores(name, code, country_code) values ('T418D Store', 'T418D', 'SG') returning id into st;
  insert into t418d values ('store', st);
  insert into public.special_products(name, sku) values ('T418D Rental Item', 'T418D-R') returning id into sp;
  insert into t418d values ('sp', sp);

  foreach k in array array['clean', 'rental', 'loan', 'affiliate', 'afflogin_c', 'commission', 'legacy', 'buyer', 'blocked'] loop
    insert into public.customers(first_name, last_name, phone)
    values ('T418D', initcap(replace(k, '_', ' ')), '+65914182' || lpad((select count(*) + 1 from t418d x where x.k like 'c:%')::text, 2, '0'))
    returning id into v;
    insert into t418d values ('c:' || k, v);
  end loop;

  insert into public.rentals(rental_no, special_product_id, customer_id, quantity, rate_type, periods, start_date, expected_return_date)
    values ('T418D-RNT-1', sp, pg_temp.id('c:rental'), 1, 'week', 1, current_date, current_date + 7) returning id into v;
  insert into t418d values ('rental', v);
  insert into public.stock_loans(loan_no, location_type, store_id, customer_id, expected_return_date, status)
    values ('T418D-LN-1', 'store', st, pg_temp.id('c:loan'), current_date + 7, 'open') returning id into v;
  insert into t418d values ('loan', v);
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at)
    values (pg_temp.id('c:affiliate'), 'active', st, now()) returning id into v;
  insert into t418d values ('aff', v);
  insert into public.affiliate_accounts(auth_user_id, customer_id, status)
    values (pg_temp.id('afflogin'), pg_temp.id('c:afflogin_c'), 'claimed') returning id into v;
  insert into t418d values ('acct', v);
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('T418D-INV-1', st, pg_temp.id('c:buyer'), pg_temp.id('owner'), 'paid', 100, 100, current_date) returning id into inv;
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, status, commission_amount,
                                 invoice_paid_date)
    values (inv, pg_temp.id('c:buyer'), pg_temp.id('c:commission'), 'tier1', 'earned', 5, public.sg_today()) returning id into v;
  insert into t418d values ('comm', v);
  insert into t418d values ('inv', inv);
  -- A referrer who is not an eligible affiliate: earn_invoice_commission
  -- records their friend's commission as blocked, never to be paid.
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, status, commission_amount,
                                 invoice_paid_date, block_reason)
    values (inv, pg_temp.id('c:buyer'), pg_temp.id('c:blocked'), 'tier1', 'blocked', 15, public.sg_today(), 'Affiliate Not Activated')
    returning id into v;
  insert into t418d values ('blockedcomm', v);
  insert into public.therapy_entitlements(entitlement_no, customer_id, store_id, package_name, entitlement_kind,
                                          qualifying_amount, qualified_value, activation_deadline, status)
    values ('T418D-LEG-1', pg_temp.id('c:legacy'), st, 'T418D Package', 'legacy', 100, 100, current_date + 30, 'pending_activation')
    returning id into v;
  insert into t418d values ('leg', v);
end $$;

-- ===== 1. Who may delete =====
do $$
declare v text;
begin
  v := pg_temp.del('staff', 'c:clean');
  perform pg_temp.check(v like 'P0001%Only an Owner or Manager can delete a customer%', '1 staff deleted a customer: ' || v);
  v := pg_temp.del('invman', 'c:clean');
  perform pg_temp.check(v like 'P0001%Only an Owner or Manager can delete a customer%', '1 an Inventory Manager deleted a customer: ' || v);
  v := pg_temp.del('nostaff', 'c:clean');
  perform pg_temp.check(v like '42501%', '1 a login with no staff profile reached delete_customer: ' || v);
  -- The payouts' lock first, then the customer's row (the order 414's Mark as
  -- settled takes them), so what they owe back cannot move while it checks.
  -- It never waits for the row while it holds the payouts' lock (a sale may
  -- hold the row and wait for that lock): a busy row asks staff to try again.
  perform pg_temp.check(pg_get_functiondef('public.delete_customer(uuid,text,text)'::regprocedure)
                          ~ ('perform public\.affiliate_payout_lock\(\);\s+begin\s+'
                             || 'select \* into v_c from public\.customers where id = p_customer_id for update nowait;\s+'
                             || 'exception when lock_not_available then\s+'
                             || 'raise exception ''This customer is being changed in another action right now\. Try again in a moment\.'';\s+'
                             || 'end;\s+if not found then raise exception ''That customer does not exist''; end if;'),
                        '1 delete_customer does not take the payouts'' lock, then lock the customer''s row without waiting');
  v := pg_temp.try('owner', format('select public.delete_customer(%L::uuid, ''T418D Nobody'', ''T418D test'')::text', gen_random_uuid()));
  perform pg_temp.check(v like 'P0001%That customer does not exist%', '1 a customer that does not exist: ' || v);
  v := pg_temp.del('manager', 'c:clean');
  perform pg_temp.check(v like 'ok%', '1 a Manager could not delete a customer with nothing open: ' || v);
  raise notice 'PASS 1: Owner/Manager only, after the 406 staff check; the row is locked without waiting; a customer with nothing open is deleted';
end $$;

-- ===== 2. Each open thing refuses, until it is settled =====
do $$
declare v text;
begin
  v := pg_temp.del('owner', 'c:rental');
  perform pg_temp.check(v like 'P0001%1 rental(s) not yet returned or cancelled%', '2a an open rental: ' || v);
  -- A rental cancelled before it was returned does not refuse (tried, then undone).
  begin
    update public.rentals set cancelled_at = now() where id = pg_temp.id('rental');
    v := pg_temp.del('owner', 'c:rental');
    raise exception using message = 'undo', detail = v;
  exception when others then
    get stacked diagnostics v = pg_exception_detail;
  end;
  perform pg_temp.check(v like 'ok%', '2a a cancelled rental, never returned, still blocks: ' || v);
  update public.rentals set returned_at = now() where id = pg_temp.id('rental');
  v := pg_temp.del('owner', 'c:rental');
  perform pg_temp.check(v like 'ok%', '2a a returned rental still blocks: ' || v);

  v := pg_temp.del('owner', 'c:loan');
  perform pg_temp.check(v like 'P0001%1 stock loan(s) still open%', '2b an open stock loan: ' || v);
  update public.stock_loans set status = 'closed', closed_at = now() where id = pg_temp.id('loan');
  v := pg_temp.del('owner', 'c:loan');
  perform pg_temp.check(v like 'ok%', '2b a closed loan still blocks: ' || v);

  v := pg_temp.del('owner', 'c:affiliate');
  perform pg_temp.check(v like 'P0001%is an affiliate%', '2c a live affiliate record: ' || v);
  update public.customer_affiliates set deleted_at = now(), status = 'soft_deleted' where id = pg_temp.id('aff');
  v := pg_temp.del('owner', 'c:affiliate');
  perform pg_temp.check(v like 'ok%', '2c a deleted affiliate record still blocks: ' || v);

  v := pg_temp.del('owner', 'c:afflogin_c');
  perform pg_temp.check(v like 'P0001%is an affiliate%', '2d an affiliate login: ' || v);
  update public.affiliate_accounts set status = 'disabled' where id = pg_temp.id('acct');
  v := pg_temp.del('owner', 'c:afflogin_c');
  perform pg_temp.check(v like 'ok%', '2d a disabled affiliate login still blocks: ' || v);

  -- Commission still owed to them refuses.
  v := pg_temp.del('owner', 'c:commission');
  perform pg_temp.check(v like 'P0001%still owed S$5.00 commission as a referrer%Record the payout%', '2e unpaid commission: ' || v);
  -- Blocked commission on its own does not: it is never paid, and nothing in
  -- the app releases it (a plain customer whose friend bought).
  perform pg_temp.check(not exists (select 1 from public.affiliate_referrer_balances() r where r.referrer = pg_temp.id('c:blocked')),
                        '2e blocked commission shows in the balances');
  v := pg_temp.del('owner', 'c:blocked');
  perform pg_temp.check(v like 'ok%', '2e a blocked row stops the delete: ' || v);
  -- The S$5 is paid out, then taken back (as 410 records it: a row below
  -- zero, which never gets a payout): they owe S$5 back (the Owner, 9 Oct
  -- 2026: refused until it is settled; 414's settlements count).
  insert into public.commission_payouts(payout_month, referrer_customer_id, total_tier1, total_amount, status, payment_date)
    values (date_trunc('month', public.sg_today())::date, pg_temp.id('c:commission'), 5, 5, 'paid', public.sg_today())
    returning id into v;
  insert into t418d values ('payout', v::uuid);
  update public.commissions set status = 'paid', payout_id = pg_temp.id('payout') where id = pg_temp.id('comm');
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, status, commission_amount,
                                 adjusts_commission_id, invoice_paid_date)
    values (pg_temp.id('inv'), pg_temp.id('c:buyer'), pg_temp.id('c:commission'), 'tier1', 'earned', -5, pg_temp.id('comm'), public.sg_today())
    returning id into v;
  insert into t418d values ('takeback', v::uuid);
  perform pg_temp.check((select r.deduction from public.affiliate_referrer_balances() r where r.referrer = pg_temp.id('c:commission')) = 5,
                        '2e the fixture does not owe S$5.00 back');
  v := pg_temp.del('owner', 'c:commission');
  perform pg_temp.check(v like 'P0001%still owes S$5.00 back from commission that was paid out and then taken back%Mark as settled%',
                        '2e commission owed back: ' || v);
  -- A later sale earns S$2, which goes to recover part of it. The S$2 row is
  -- never put in a payout, and is not owed to them: S$3 is still owed back.
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('T418D-INV-2', pg_temp.id('store'), pg_temp.id('c:buyer'), pg_temp.id('owner'), 'paid', 40, 40, current_date)
    returning id into v;
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, status, commission_amount,
                                 invoice_paid_date)
    values (v::uuid, pg_temp.id('c:buyer'), pg_temp.id('c:commission'), 'tier1', 'earned', 2, public.sg_today())
    returning id into v;
  insert into t418d values ('later', v::uuid);
  v := pg_temp.del('owner', 'c:commission');
  perform pg_temp.check(v like 'P0001%still owes S$3.00 back%', '2e a later sale recovered part: ' || v);
  -- Part settled: the rest still refuses.
  v := pg_temp.try('owner', format('select public.record_affiliate_deduction_settlement(%L, 1, %L, ''paid_back'', ''T418D part'', %L)::text',
                                   pg_temp.id('c:commission'), public.sg_today(), gen_random_uuid()));
  perform pg_temp.check(v like 'ok%', '2e a part could not be settled: ' || v);
  v := pg_temp.del('owner', 'c:commission');
  perform pg_temp.check(v like 'P0001%still owes S$2.00 back%', '2e part settled: ' || v);
  -- All settled: nothing is owed either way, though the S$2 row is still
  -- earned and in no payout (the Commissions page cannot clear it), and the
  -- delete goes through (tried, then undone).
  v := pg_temp.try('owner', format('select public.record_affiliate_deduction_settlement(%L, 2, %L, ''paid_outside_app'', ''T418D rest'', %L)::text',
                                   pg_temp.id('c:commission'), public.sg_today(), gen_random_uuid()));
  perform pg_temp.check(v like 'ok%', '2e the rest could not be settled: ' || v);
  insert into t418d values ('settle2', (split_part(v, chr(9), 2)::jsonb->>'id')::uuid);
  perform pg_temp.check((select r.unpaid = 0 and r.deduction = 0 from public.affiliate_referrer_balances() r
                          where r.referrer = pg_temp.id('c:commission'))
                        and (select status = 'earned' and payout_id is null from public.commissions where id = pg_temp.id('later')),
                        '2e the fixture is not settled with the S$2 row left earned');
  begin
    v := pg_temp.del('owner', 'c:commission');
    raise exception using message = 'undo', detail = v;
  exception when others then
    get stacked diagnostics v = pg_exception_detail;
  end;
  perform pg_temp.check(v like 'ok%', '2e settled in full, still refused: ' || v);
  -- A settlement voided: they owe it back again.
  v := pg_temp.try('owner', format('select public.void_affiliate_deduction_settlement(%L, ''T418D mistake'', %L)::text',
                                   pg_temp.id('settle2'), gen_random_uuid()));
  perform pg_temp.check(v like 'ok%', '2e the settlement could not be voided: ' || v);
  v := pg_temp.del('owner', 'c:commission');
  perform pg_temp.check(v like 'P0001%still owes S$2.00 back%', '2e a voided settlement still counts: ' || v);
  -- Written off: deleted.
  v := pg_temp.try('owner', format('select public.record_affiliate_deduction_settlement(%L, 2, %L, ''written_off'', ''T418D written off'', %L)::text',
                                   pg_temp.id('c:commission'), public.sg_today(), gen_random_uuid()));
  perform pg_temp.check(v like 'ok%', '2e the rest could not be written off: ' || v);
  v := pg_temp.del('owner', 'c:commission');
  perform pg_temp.check(v like 'ok%', '2e written off, still refused: ' || v);

  v := pg_temp.del('owner', 'c:legacy');
  perform pg_temp.check(v like 'P0001%1 legacy therapy entitlement(s) still open%', '2f legacy therapy waiting to start: ' || v);
  update public.therapy_entitlements set status = 'active' where id = pg_temp.id('leg');
  v := pg_temp.del('owner', 'c:legacy');
  perform pg_temp.check(v like 'P0001%legacy therapy%', '2f active legacy therapy: ' || v);
  update public.therapy_entitlements set status = 'cancelled' where id = pg_temp.id('leg');
  v := pg_temp.del('owner', 'c:legacy');
  perform pg_temp.check(v like 'ok%', '2f cancelled legacy therapy still blocks: ' || v);

  perform pg_temp.check((select count(*) from public.customers where id in (select id from t418d where k like 'c:%') and deleted_at is not null) = 8,
                        '2 the customers settled were not all deleted');
  perform pg_temp.check((select count(*) from public.audit_logs where action = 'customer_deleted'
                           and record_id in (select id from t418d where k like 'c:%')) = 8, '2 each deletion is recorded once');
  raise notice 'PASS 2: an open rental, an open stock loan, an affiliate record or login, commission still owed as referrer, commission owed back and not settled (a part, or a voided settlement, still refuses), and open legacy therapy each refuse; a cancelled rental, blocked commission and a row that only recovered a take-back do not; once settled, the customer is deleted';
end $$;

rollback;
