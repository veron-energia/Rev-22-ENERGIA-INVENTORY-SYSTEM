-- 422: therapy claims, Legacy rewards and the Therapy page's lists.
--
-- Before 422 (the audit of 9 Oct 2026, section 7):
--   * a Legacy claim took 15 and -5 as 10 and issued 15, and took a voucher
--     reward whose vouchers were partly handed over and issued it all again
--     (THERAPY-4);
--   * discount vouchers were offered and taken as rewards (THERAPY-7);
--   * a reward with no voucher list offered none (THERAPY-8);
--   * a package or reward on a refunded sale could be claimed (THERAPY-20);
--   * a Legacy claim of unlimited therapy started on top of a running period
--     (THERAPY-M2);
--   * the Purchased tab's days left left out today (THERAPY-15);
--   * staff read every store's purchased packages (THERAPY-12);
--   * a member of staff's second store did not count for dates (X-9);
--   * a Manager could close a package of a store they do not work at with
--     Cancel package, and purchased_therapy_units gave a deleted customer's
--     name (rule 9);
--   * and, by the Owner's answers of 9 Oct 2026: any member of staff handed
--     over a reward with no sale and no voucher list (rule 10), new Legacy
--     and affiliate voucher rewards saved no voucher list (rule 11), and
--     Cancel package reversed the line's earned commission though no money
--     moved (rule 12).
-- Section 1 reproduces them (only on a database without 422), then 422 is
-- applied twice (the second run must change nothing) and section 2 checks
-- every rule, the page's list function (which never gives or searches a
-- deleted customer's name or phone), that the unused activate_legacy_therapy
-- wrapper is gone, and who may do what, including that a
-- login 407 does not count as staff is refused first, with 42501, by the five
-- purchased-package functions 422 gives 406's check.
--
-- Disposable local database only; everything is rolled back. The migration
-- is applied inside this transaction, so run the file on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/therapy/tests/claims-and-legacy-rewards.sql
-- On a database without production's reference rows (system wallet payment
-- methods, holiday countries), nothing here needs them. Every name, phone and
-- number is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
-- The error a statement raises, or null when it succeeds; rolled back either way.
create function pg_temp.refused(q text) returns text language plpgsql as $$
begin
  begin
    execute q;
    raise exception 'T422: accepted';
  exception when others then
    if sqlerrm = 'T422: accepted' then return null; end if;
    return sqlerrm;
  end;
end $$;
-- The same, with the error's SQLSTATE first ('42501 Only active ...').
create function pg_temp.refused_state(q text) returns text language plpgsql as $$
begin
  begin
    execute q;
    raise exception 'T422: accepted';
  exception when others then
    if sqlerrm = 'T422: accepted' then return null; end if;
    return sqlstate || ' ' || sqlerrm;
  end;
end $$;
-- Act as one of the fixture's logins (functions read auth.uid()), or as the
-- server (no request at all).
create function pg_temp.as_login(key text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(key), 'role', 'authenticated')::text, true),
         set_config('request.jwt.claim.sub', '', true)
$$;
create function pg_temp.as_server() returns void language sql as $$
  select set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true)
$$;
create function pg_temp.t(n int default 0) returns date language sql as $$ select public.sg_today() + n $$;
create function pg_temp.sel(voucher text, qty jsonb) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx(voucher), 'quantity', qty)) $$;
create function pg_temp.issued(ent text) returns int language sql as
$$ select coalesce(sum(quantity), 0)::int from public.customer_reward_vouchers where entitlement_id = pg_temp.fx(ent) $$;
-- A Legacy entitlement.
create function pg_temp.legacy(no text, kind text, qty int, st text, store text default 'store_a',
                               cust text default 'buyer', src text default null, src_inv text default null,
                               act date default null, exp date default null, tier text default null,
                               eligible uuid[] default null)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into public.therapy_entitlements(entitlement_no, customer_id, store_id, package_name, entitlement_kind,
      duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status,
      activation_date, expiry_date, claim_source_type, claim_source_invoice_id, reward_tier_key, eligible_voucher_ids)
    values ('T422-' || no, pg_temp.fx(cust), pg_temp.fx(store), 'T422 ' || no, kind,
            1, qty, 994, 994, pg_temp.t(60), st,
            act, exp, src, pg_temp.fx(src_inv), tier, eligible)
    returning id into v;
  insert into fx values (no, v);
  return v;
end $$;
-- A purchased unit.
create function pg_temp.unit(no text, st text, inv text, choice text default 'unlimited',
                             offered text[] default array['unlimited'], store text default 'store_a',
                             act date default null, exp date default null, cust text default 'buyer')
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into public.purchased_therapy_entitlements(entitlement_no, customer_id, store_id, package_id, invoice_id,
      package_name, duration_months, price_snapshot, purchase_date, activation_deadline, scheduled_date,
      activation_date, expiry_date, status, benefit_choice, offered_choices, voucher_qty_snapshot,
      eligible_voucher_ids, choice_deadline)
    values ('T422-' || no, pg_temp.fx(cust), pg_temp.fx(store), pg_temp.fx('pkg'), pg_temp.fx(inv),
            'T422 One Month', 1, 300, pg_temp.t(-10), pg_temp.t(300), act, act, exp, st, choice, offered,
            case when 'voucher' = any(offered) then 4 end,
            case when 'voucher' = any(offered) then array[pg_temp.fx('v_session')] end,
            case when 'voucher' = any(offered) then pg_temp.t(300) end)
    returning id into v;
  insert into fx values (no, v);
  return v;
end $$;

-- The Owner's answers of 9 Oct 2026 (rules 10 to 12): a store C with a
-- customer and an affiliate voucher rule and an unlimited one, and paid
-- sales today that reach them. Names start "W2", so the T422 searches below
-- never find these rows.
create function pg_temp.w2_fixtures() returns void language plpgsql as $$
declare v uuid; k text;
begin
  insert into public.stores(name, code, country_code) values ('W2 Store C', 'T422C', 'SG') returning id into v;
  insert into fx values ('store_c', v);
  foreach k in array array['w2_spender', 'w2_big', 'w2_quiet', 'w2_affiliate', 'w2_referred'] loop
    insert into public.customers(full_name, phone)
      values ('W2 ' || k, '+65914222' || lpad((array_position(array['w2_spender', 'w2_big', 'w2_quiet', 'w2_affiliate', 'w2_referred'], k))::text, 2, '0'))
      returning id into v;
    insert into fx values (k, v);
  end loop;
  insert into public.therapy_package_rules(name, qualifying_amount, entitlement_kind, voucher_qty, applies_to, store_id)
    values ('W2 C Vouchers', 995, 'voucher', 5, 'customer', pg_temp.fx('store_c')),
           ('W2 C Affiliate', 450, 'voucher', 10, 'affiliate', pg_temp.fx('store_c'));
  insert into public.therapy_package_rules(name, qualifying_amount, entitlement_kind, duration_months, applies_to, store_id)
    values ('W2 C Unlimited', 2000, 'unlimited', 1, 'customer', pg_temp.fx('store_c'));
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount, paid_at)
    values ('W2-INV-1', pg_temp.fx('store_c'), pg_temp.fx('w2_spender'), pg_temp.fx('owner'), 'paid', 1000, 1000, 1000, now()),
           ('W2-INV-2', pg_temp.fx('store_c'), pg_temp.fx('w2_big'), pg_temp.fx('owner'), 'paid', 2000, 2000, 2000, now()),
           ('W2-INV-3', pg_temp.fx('store_c'), pg_temp.fx('w2_quiet'), pg_temp.fx('owner'), 'paid', 1000, 1000, 1000, now());
  -- 900 reaches no customer rule, so all of it is the affiliate's residual.
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount, paid_at,
                              affiliate_snapshot_customer_id, affiliate_active_on_paid)
    values ('W2-INV-4', pg_temp.fx('store_c'), pg_temp.fx('w2_referred'), pg_temp.fx('owner'), 'paid', 900, 900, 900, now(),
            pg_temp.fx('w2_affiliate'), true);
end $$;
-- The voucher reward a customer's day of spending earned, as the server makes it.
create function pg_temp.w2_earned(cust text, store text default 'store_c') returns uuid[] language plpgsql as $$
declare v uuid[];
begin
  perform public.recompute_legacy_qualification(pg_temp.fx(cust), pg_temp.fx(store), public.sg_today());
  select eligible_voucher_ids into v from public.therapy_entitlements
   where customer_id = pg_temp.fx(cust) and status = 'pending_activation';
  if not found then raise exception 'T422: % earned nothing', cust; end if;
  return v;
end $$;
-- A purchased unit's invoice line, with an affiliate's earned commission on it.
create function pg_temp.w2_commission(unit text) returns uuid language plpgsql as $$
declare v_item uuid; v_com uuid; v_inv uuid;
begin
  select invoice_id into v_inv from public.purchased_therapy_entitlements where id = pg_temp.fx(unit);
  insert into public.invoice_items(invoice_id, quantity, unit_price, line_total, line_kind)
    values (v_inv, 1, 300, 300, 'therapy') returning id into v_item;
  update public.purchased_therapy_entitlements set invoice_item_id = v_item where id = pg_temp.fx(unit);
  insert into public.commissions(invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
                                 line_amount, rate, commission_amount, status)
    values (v_inv, v_item, pg_temp.fx('buyer'), pg_temp.fx('buyer2'), 'tier1', 300, 0.05, 15, 'earned')
    returning id into v_com;
  return v_com;
end $$;
-- The active free-session vouchers marked as rewards (what a Legacy claim offers).
create function pg_temp.on_offer() returns uuid[] language sql as $$
  select array_agg(v.id order by v.id) from public.vouchers v
   where v.is_active and v.deleted_at is null and coalesce(v.reward_eligible, true) and v.voucher_kind = 'normal'
$$;

-- ===== Fixtures =====
do $$
declare v uuid; k text;
begin
  perform pg_temp.as_server();
  foreach k in array array['owner', 'staff_a', 'staff_ab', 'manager'] loop
    insert into fx values (k, gen_random_uuid());
    insert into auth.users(id, email) values (pg_temp.fx(k), 't422-' || k || '@sig.invalid');
    insert into public.profiles(id, full_name, email, role, is_active)
      values (pg_temp.fx(k), 'T422 ' || k, 't422-' || k || '@sig.invalid',
              case k when 'owner' then 'owner' when 'manager' then 'manager' else 'staff' end::public.user_role, true);
  end loop;
  insert into public.stores(name, code, country_code) values ('T422 Store A', 'T422A', 'SG') returning id into v;
  insert into fx values ('store_a', v);
  insert into public.stores(name, code, country_code) values ('T422 Store B', 'T422B', 'SG') returning id into v;
  insert into fx values ('store_b', v);
  -- staff_a works at A only; staff_ab at A and then B (B is not their first
  -- store); the manager at A only.
  insert into public.user_store_assignments(user_id, store_id, created_at)
    values (pg_temp.fx('staff_a'), pg_temp.fx('store_a'), now() - interval '2 days'),
           (pg_temp.fx('staff_ab'), pg_temp.fx('store_a'), now() - interval '2 days'),
           (pg_temp.fx('staff_ab'), pg_temp.fx('store_b'), now() - interval '1 day'),
           (pg_temp.fx('manager'), pg_temp.fx('store_a'), now() - interval '2 days');
  insert into public.customers(full_name, phone) values ('T422 Buyer', '+6591422101') returning id into v;
  insert into fx values ('buyer', v);
  insert into public.customers(full_name, phone) values ('T422 Second Buyer', '+6591422102') returning id into v;
  insert into fx values ('buyer2', v);
  insert into public.customers(full_name, phone) values ('T422 Store B Buyer', '+6591422103') returning id into v;
  insert into fx values ('buyer_b', v);
  insert into public.customers(full_name, phone) values ('T422 Third Buyer', '+6591422104') returning id into v;
  insert into fx values ('buyer3', v);
  -- Deleted in section 2, after their rows are made.
  insert into public.customers(full_name, phone) values ('T422 Gone Buyer', '+6591422105') returning id into v;
  insert into fx values ('buyer_gone', v);

  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T422 Session', 'T422-SES', 'normal', 'limited', 50, true) returning id into v;
  insert into fx values ('v_session', v);
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T422 Massage', 'T422-MAS', 'normal', 'unlimited', 50, true) returning id into v;
  insert into fx values ('v_massage', v);
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T422 Not a reward', 'T422-NRW', 'normal', 'unlimited', 50, true) returning id into v;
  insert into fx values ('v_noreward', v);
  update public.vouchers set reward_eligible = false where id = v;
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active, discount_amount)
    values ('T422 Five Off', 'T422-FIX', 'fixed_discount', 'unlimited', 0, true, 5) returning id into v;
  insert into fx values ('v_fixed', v);
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active, discount_percent,
                              discount_category, birthday_rule)
    values ('T422 Birthday', 'T422-BDY', 'percentage_discount', 'unlimited', 0, true, 10, 'birthday', 'whole_month')
    returning id into v;
  insert into fx values ('v_birthday', v);
  insert into public.voucher_store_stock(voucher_id, store_id, current_qty)
    values (pg_temp.fx('v_session'), pg_temp.fx('store_a'), 100), (pg_temp.fx('v_session'), pg_temp.fx('store_b'), 100);

  -- Sales: paid, refunded, cancelled, deleted; and a paid one at store B.
  foreach k in array array['paid', 'refunded', 'cancelled', 'deleted'] loop
    insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, deleted_at)
      values ('T422-INV-' || upper(k), pg_temp.fx('store_a'), pg_temp.fx('buyer'), pg_temp.fx('owner'),
              case k when 'deleted' then 'unpaid' else k end::public.invoice_status,
              case when k = 'deleted' then now() end)
      returning id into v;
    insert into fx values ('inv_' || k, v);
  end loop;
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status)
    values ('T422-INV-B', pg_temp.fx('store_b'), pg_temp.fx('buyer_b'), pg_temp.fx('owner'), 'paid') returning id into v;
  insert into fx values ('inv_b', v);
  insert into public.unlimited_therapy_packages(name, duration_months) values ('T422 One Month', 1) returning id into v;
  insert into fx values ('pkg', v);

  -- A Legacy tier whose reward may be taken as 10 vouchers instead.
  insert into public.therapy_package_rules(name, qualifying_amount, entitlement_kind, voucher_qty, tier_key, applies_to)
    values ('T422 Ten Vouchers', 994, 'voucher', 10, 'T422-TIER', 'customer') returning id into v;
  insert into fx values ('rule_v', v);
  insert into public.therapy_package_rules(name, qualifying_amount, entitlement_kind, duration_months, tier_key, applies_to)
    values ('T422 One Month Unlimited', 994, 'unlimited', 1, 'T422-TIER', 'customer') returning id into v;
  insert into fx values ('rule_u', v);
end $$;

-- ===== 1. Before 422: the defects, reproduced =====
-- Only on a database without 422; everything here is rolled back.
savepoint before422;
do $$
declare e text; r jsonb;
begin
  if md5(coalesce(pg_get_functiondef(to_regprocedure('public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)')), ''))
     <> '3957f56f3ea9dc8df6789371a20add66' then
    raise notice 'SKIP  section 1: this database already has 422'; return; end if;
  perform pg_temp.as_login('owner');
  -- THERAPY-4: 15 and -5 against "exactly 10".
  perform pg_temp.legacy('B1', 'unlimited', null, 'pending_activation', tier => 'T422-TIER');
  perform public.claim_legacy_therapy(pg_temp.fx('B1'), null, pg_temp.fx('rule_v'),
    jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v_session'), 'quantity', 15),
                      jsonb_build_object('voucher_id', pg_temp.fx('v_massage'), 'quantity', -5)));
  perform pg_temp.check(pg_temp.issued('B1') = 15, 'before 422: 15 and -5 passed as 10 and issued 15 (the defect)');
  -- THERAPY-4: a credit-package reward with 3 of 10 handed over, claimed again whole.
  perform pg_temp.legacy('B2', 'voucher', 10, 'pending_activation', src => 'credit_package', src_inv => 'inv_paid');
  perform public.claim_entitlement_vouchers(pg_temp.fx('B2'), pg_temp.sel('v_session', '3'), null);
  perform public.claim_legacy_therapy(pg_temp.fx('B2'), null, null, pg_temp.sel('v_session', '10'));
  perform pg_temp.check(pg_temp.issued('B2') = 13, 'before 422: a reward with 3 of 10 handed over gave 10 more (the defect)');
  -- THERAPY-7: a discount voucher handed over as a reward.
  perform pg_temp.legacy('B3', 'voucher', 2, 'pending_activation');
  e := pg_temp.refused(format('select public.claim_entitlement_vouchers(%L, %L, null)', pg_temp.fx('B3'), pg_temp.sel('v_fixed', '1')));
  perform pg_temp.check(e is null, 'before 422: a discount voucher was taken as a reward (the defect)');
  -- THERAPY-8: no voucher list, nothing to choose.
  r := public.entitlement_voucher_state(pg_temp.fx('B3'));
  perform pg_temp.check(jsonb_array_length(r->'eligible') = 0, 'before 422: a reward with no voucher list offered none (the defect)');
  -- THERAPY-20: a unit on a refunded sale is claimed.
  perform pg_temp.unit('BU1', 'pending_activation', 'inv_refunded');
  e := pg_temp.refused(format('select public.claim_purchased_therapy(%L, ''unlimited'', %L)', pg_temp.fx('BU1'), pg_temp.t(0)));
  perform pg_temp.check(e is null, 'before 422: a package on a refunded sale was started (the defect)');
  -- THERAPY-15: an active unit ending in nine days showed 9 days left.
  perform pg_temp.unit('BU2', 'active', 'inv_paid', act => pg_temp.t(-20), exp => pg_temp.t(9), cust => 'buyer2');
  perform pg_temp.check((select days_remaining from public.purchased_therapy_units(null, null, false)
                          where purchased_id = pg_temp.fx('BU2')) = 9,
    'before 422: a unit ending in nine days showed 9 days left, today left out (the defect)');
  -- X-9: staff_ab's second store did not count.
  perform pg_temp.as_login('staff_ab');
  perform pg_temp.check(not public.can_change_therapy_dates(pg_temp.fx('store_b')),
    'before 422: a member of staff could not change dates at their second store (the defect)');
  -- Rule 10: any member of staff of the store handed over a reward that
  -- records no sale and no voucher list.
  perform pg_temp.as_login('staff_a');
  perform pg_temp.legacy('BN', 'voucher', 3, 'pending_activation');
  perform public.claim_entitlement_vouchers(pg_temp.fx('BN'), pg_temp.sel('v_session', '1'), null);
  perform pg_temp.check(pg_temp.issued('BN') = 1,
    'before 422: a member of staff handed over a reward with no sale and no voucher list (now an Owner or Manager does)');
  -- Rule 12: Cancel package reversed the line's earned commission, though no money moved.
  perform pg_temp.as_login('owner');
  perform pg_temp.unit('BU3', 'pending_activation', 'inv_paid', cust => 'buyer3');
  e := pg_temp.w2_commission('BU3')::text;
  perform public.refund_purchased_therapy(pg_temp.fx('BU3'), 'T422 before');
  perform pg_temp.check((select status = 'reversed' from public.commissions where id = e::uuid),
    'before 422: Cancel package reversed the earned commission with no money moved (the defect)');
  -- Cancel package did not check the package's store.
  perform pg_temp.unit('BXS', 'pending_activation', 'inv_b', store => 'store_b', cust => 'buyer_b');
  perform pg_temp.as_login('manager');
  perform public.refund_purchased_therapy(pg_temp.fx('BXS'), 'T422 before');
  perform pg_temp.check((select status from public.purchased_therapy_entitlements where id = pg_temp.fx('BXS')) = 'refunded',
    'before 422: a Manager of store A closed a package of store B (the defect)');
  -- Rule 9: purchased_therapy_units gave a deleted customer's name.
  perform pg_temp.as_login('owner');
  perform pg_temp.unit('BGONE', 'expired', 'inv_paid', act => pg_temp.t(-60), exp => pg_temp.t(-30), cust => 'buyer_gone');
  update public.customers set deleted_at = now() where id = pg_temp.fx('buyer_gone');
  perform pg_temp.check((select customer_name from public.purchased_therapy_units(null, null, false)
                          where purchased_id = pg_temp.fx('BGONE')) = 'T422 Gone Buyer',
    'before 422: purchased_therapy_units gave a deleted customer''s name (the defect)');
  -- Rule 11: a new Legacy or affiliate voucher reward saved no voucher list.
  perform pg_temp.as_server();
  perform pg_temp.w2_fixtures();
  perform pg_temp.check(pg_temp.w2_earned('w2_spender') is null,
    'before 422: a new Legacy voucher reward saved no voucher list (the defect)');
  perform public.recompute_affiliate_legacy_qualification(pg_temp.fx('w2_affiliate'), public.sg_today());
  perform pg_temp.check((select count(*) = 2 and bool_and(eligible_voucher_ids is null) from public.therapy_entitlements
                          where customer_id = pg_temp.fx('w2_affiliate') and earner_kind = 'affiliate'),
    'before 422: a new affiliate voucher reward saved no voucher list (the defect)');
end $$;
rollback to savepoint before422;

-- ===== The migration, twice =====
\ir ../../../supabase/422_therapy_claims_and_legacy_rewards.sql
\ir ../../../supabase/422_therapy_claims_and_legacy_rewards.sql
reset role;

-- ===== 2. After 422 =====
do $$
declare e text; r jsonb; n int; v_audits int; k text;
begin
  perform pg_temp.as_login('owner');

  -- ── The function set ──
  perform pg_temp.check(to_regprocedure('public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)') is null
                        and has_function_privilege('authenticated',
                              'public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)', 'execute')
                        and not has_function_privilege('anon',
                              'public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)', 'execute'),
    'claim_legacy_therapy has one signature, with p_allow_overlap, for staff and not anon');
  perform pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                                     and p.proname = 'activate_legacy_therapy'),
    'the unused activate_legacy_therapy wrapper is gone (it would return without claiming on an overlap)');
  perform pg_temp.check(not has_function_privilege('authenticated', 'public.therapy_invoice_closed_reason(uuid)', 'execute')
                        and has_function_privilege('authenticated', 'public.therapy_list_page(text,text,text,integer,integer)', 'execute'),
    'the sale check is internal; the list is for staff');

  -- ── THERAPY-4: quantities and voucher rewards ──
  perform pg_temp.legacy('L1', 'unlimited', null, 'pending_activation', tier => 'T422-TIER');
  e := pg_temp.refused(format('select public.claim_legacy_therapy(%L, null, %L, %L)', pg_temp.fx('L1'), pg_temp.fx('rule_v'),
         jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v_session'), 'quantity', 15),
                           jsonb_build_object('voucher_id', pg_temp.fx('v_massage'), 'quantity', -5))));
  perform pg_temp.check(e like 'A voucher quantity must be a whole number of at least one; got -5%' and pg_temp.issued('L1') = 0,
    'THERAPY-4: 15 and -5 are refused and nothing is issued');
  e := pg_temp.refused(format('select public.claim_legacy_therapy(%L, null, %L, %L)', pg_temp.fx('L1'), pg_temp.fx('rule_v'),
         jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v_session'), 'quantity', 10),
                           jsonb_build_object('voucher_id', pg_temp.fx('v_massage'), 'quantity', 0))));
  perform pg_temp.check(e like 'A voucher quantity must be a whole number of at least one; got 0%', 'THERAPY-4: a zero line is refused');
  e := pg_temp.refused(format('select public.claim_legacy_therapy(%L, null, %L, %L)', pg_temp.fx('L1'), pg_temp.fx('rule_v'),
         jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v_session'), 'quantity', 9.5),
                           jsonb_build_object('voucher_id', pg_temp.fx('v_massage'), 'quantity', 0.5))));
  perform pg_temp.check(e like 'A voucher quantity must be a whole number of at least one; got 9.5%', 'THERAPY-4: 9.5 and 0.5 are refused');
  e := pg_temp.refused(format('select public.claim_legacy_therapy(%L, null, %L, %L)', pg_temp.fx('L1'), pg_temp.fx('rule_v'),
         '{"voucher_id": "x"}'));
  perform pg_temp.check(e like 'Choose 10 voucher(s)%', 'THERAPY-4: a selection that is not a list is refused');
  -- Taken as vouchers by its rule, honestly: 6 and 4.
  r := public.claim_legacy_therapy(pg_temp.fx('L1'), null, pg_temp.fx('rule_v'),
         jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v_session'), 'quantity', 6),
                           jsonb_build_object('voucher_id', pg_temp.fx('v_massage'), 'quantity', '4')));
  perform pg_temp.check((r->>'claimed')::boolean and pg_temp.issued('L1') = 10
                        and (select status from public.therapy_entitlements where id = pg_temp.fx('L1')) = 'active',
    'THERAPY-4: an unlimited reward taken as exactly 10 vouchers by its rule issues 10 (a number written as text counts)');
  -- A voucher reward is never claimed here, handed over in part or not.
  perform pg_temp.legacy('L2', 'voucher', 10, 'pending_activation', src => 'credit_package', src_inv => 'inv_paid');
  perform public.claim_entitlement_vouchers(pg_temp.fx('L2'), pg_temp.sel('v_session', '3'), null);
  e := pg_temp.refused(format('select public.claim_legacy_therapy(%L, null, null, %L)', pg_temp.fx('L2'), pg_temp.sel('v_session', '10')));
  perform pg_temp.check(e like 'This is a voucher reward.%' and pg_temp.issued('L2') = 3,
    'THERAPY-4: a credit-package reward with 3 of 10 handed over is not claimed again whole');
  perform pg_temp.legacy('L3', 'voucher', 10, 'pending_activation');
  e := pg_temp.refused(format('select public.claim_legacy_therapy(%L, null, null, %L)', pg_temp.fx('L3'), pg_temp.sel('v_session', '10')));
  perform pg_temp.check(e like 'This is a voucher reward.%', 'THERAPY-4: a Legacy voucher reward goes to the Vouchers window too');
  -- An unlimited reward with vouchers already issued against it (before claim
  -- documents existed) is not taken as vouchers again.
  perform pg_temp.legacy('L4', 'unlimited', null, 'pending_activation', tier => 'T422-TIER');
  insert into public.customer_reward_vouchers(customer_id, voucher_id, entitlement_id, store_id, quantity, notes)
    values (pg_temp.fx('buyer'), pg_temp.fx('v_massage'), pg_temp.fx('L4'), pg_temp.fx('store_a'), 2, 'T422 handed over before');
  e := pg_temp.refused(format('select public.claim_legacy_therapy(%L, null, %L, %L)', pg_temp.fx('L4'), pg_temp.fx('rule_v'),
         pg_temp.sel('v_session', '10')));
  perform pg_temp.check(e like 'Vouchers were already handed over or withdrawn%', 'THERAPY-4: a reward with vouchers already out is not taken as vouchers again');
  -- In the Vouchers window: a voucher off the list it was sold with is refused.
  perform pg_temp.legacy('L5', 'voucher', 4, 'pending_activation', src => 'credit_package', src_inv => 'inv_paid',
                         eligible => array[pg_temp.fx('v_session')]);
  e := pg_temp.refused(format('select public.claim_entitlement_vouchers(%L, %L, null)', pg_temp.fx('L5'), pg_temp.sel('v_massage', '1')));
  perform pg_temp.check(e like 'That voucher was not one of the choices%', 'THERAPY-4: a voucher off the reward''s list is refused');
  e := pg_temp.refused(format('select public.claim_entitlement_vouchers(%L, %L, null)', pg_temp.fx('L5'), pg_temp.sel('v_session', '5')));
  perform pg_temp.check(e like 'Only 4 left to claim%', 'THERAPY-4: more than is left is refused');
  e := pg_temp.refused(format('select public.claim_entitlement_vouchers(%L, %L, null)', pg_temp.fx('L5'), pg_temp.sel('v_session', '1.5')));
  perform pg_temp.check(e like 'A voucher quantity must be a whole number of at least one; got 1.5%', 'THERAPY-4: 1.5 is refused in the Vouchers window, plainly');

  -- ── THERAPY-7: only free-session vouchers are rewards ──
  perform pg_temp.check(
    exists (select 1 from public.legacy_reward_voucher_options(pg_temp.fx('store_a')) o where o.voucher_id = pg_temp.fx('v_session'))
    and not exists (select 1 from public.legacy_reward_voucher_options(pg_temp.fx('store_a')) o
                     where o.voucher_id in (pg_temp.fx('v_fixed'), pg_temp.fx('v_birthday'), pg_temp.fx('v_noreward'))),
    'THERAPY-7: the reward list holds normal reward vouchers only');
  perform pg_temp.legacy('L6', 'voucher', 3, 'pending_activation',
                         eligible => array[pg_temp.fx('v_session'), pg_temp.fx('v_fixed')]);
  e := pg_temp.refused(format('select public.claim_entitlement_vouchers(%L, %L, null)', pg_temp.fx('L6'), pg_temp.sel('v_fixed', '1')));
  perform pg_temp.check(e like 'That voucher cannot be given as a reward%', 'THERAPY-7: a discount voucher on a reward''s list is still refused');
  r := public.entitlement_voucher_state(pg_temp.fx('L6'));
  perform pg_temp.check((select bool_and((x->>'still_offered')::boolean = ((x->>'voucher_id')::uuid = pg_temp.fx('v_session')))
                           from jsonb_array_elements(r->'eligible') x),
    'THERAPY-7: the Vouchers window marks the discount voucher as not offered');
  perform pg_temp.legacy('L7', 'unlimited', null, 'pending_activation', tier => 'T422-TIER');
  e := pg_temp.refused(format('select public.claim_legacy_therapy(%L, null, %L, %L)', pg_temp.fx('L7'), pg_temp.fx('rule_v'),
         jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v_session'), 'quantity', 9),
                           jsonb_build_object('voucher_id', pg_temp.fx('v_birthday'), 'quantity', 1))));
  perform pg_temp.check(e like 'That voucher cannot be given as a reward%' and pg_temp.issued('L7') = 0,
    'THERAPY-7: a Legacy claim refuses a discount voucher and issues nothing');

  -- ── THERAPY-8: no voucher list ──
  perform pg_temp.legacy('L8', 'voucher', 5, 'pending_activation');
  r := public.entitlement_voucher_state(pg_temp.fx('L8'));
  perform pg_temp.check(not (r->>'snapshot_present')::boolean
                        and (r->'eligible') @> jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v_session')),
                                                                 jsonb_build_object('voucher_id', pg_temp.fx('v_massage')))
                        and not (r->'eligible') @> jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v_fixed')))
                        and not (r->'eligible') @> jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('v_noreward'))),
    'THERAPY-8: a reward with no voucher list offers the normal reward vouchers, and says it has no list');
  perform public.claim_entitlement_vouchers(pg_temp.fx('L8'), pg_temp.sel('v_massage', '2'), null);
  perform pg_temp.check(pg_temp.issued('L8') = 2, 'THERAPY-8: and one of them can be handed over');

  -- ── THERAPY-20: refunded, cancelled and deleted sales ──
  perform pg_temp.unit('U_REF', 'pending_activation', 'inv_refunded');
  perform pg_temp.unit('U_CAN', 'pending_activation', 'inv_cancelled', cust => 'buyer2');
  perform pg_temp.unit('U_DEL', 'pending_activation', 'inv_deleted', null, array['unlimited', 'voucher']);
  perform pg_temp.unit('U_OK', 'pending_activation', 'inv_paid', null, array['unlimited', 'voucher'], cust => 'buyer2');
  perform pg_temp.unit('U_B', 'pending_activation', 'inv_b', store => 'store_b', cust => 'buyer_b');
  e := pg_temp.refused(format('select public.claim_purchased_therapy(%L, ''unlimited'', %L)', pg_temp.fx('U_REF'), pg_temp.t(0)));
  perform pg_temp.check(e = 'Invoice T422-INV-REFUNDED was refunded, so nothing can be claimed on this package.',
    'THERAPY-20: a package on a refunded sale is not started');
  e := pg_temp.refused(format('select public.claim_purchased_therapy(%L, ''unlimited'', %L)', pg_temp.fx('U_CAN'), pg_temp.t(0)));
  perform pg_temp.check(e = 'Invoice T422-INV-CANCELLED was cancelled, so nothing can be claimed on this package.',
    'THERAPY-20: nor on a cancelled one');
  e := pg_temp.refused(format('select public.claim_purchased_therapy(%L, ''voucher'', null)', pg_temp.fx('U_DEL')));
  perform pg_temp.check(e = 'Invoice T422-INV-DELETED was deleted, so nothing can be claimed on this package.',
    'THERAPY-20: nor as vouchers on a deleted one');
  e := pg_temp.refused(format('select public.choose_therapy_benefit(%L, ''voucher'')', pg_temp.fx('U_DEL')));
  perform pg_temp.check(e like 'Invoice T422-INV-DELETED was deleted, so no benefit can be chosen%', 'THERAPY-20: no benefit is chosen on it');
  e := pg_temp.refused(format('select public.activate_purchased_therapy(%L, %L)', pg_temp.fx('U_REF'), pg_temp.t(0)));
  perform pg_temp.check(e like 'Invoice T422-INV-REFUNDED was refunded, so therapy cannot start%', 'THERAPY-20: activate refuses too');
  update public.purchased_therapy_entitlements set benefit_choice = 'unlimited', offered_choices = array['unlimited', 'voucher'],
         voucher_qty_snapshot = 4, eligible_voucher_ids = array[pg_temp.fx('v_session')]
   where id = pg_temp.fx('U_REF');
  e := pg_temp.refused(format('select public.switch_therapy_benefit(%L, ''voucher'', ''T422'')', pg_temp.fx('U_REF')));
  perform pg_temp.check(e like 'Invoice T422-INV-REFUNDED was refunded, so this package cannot be switched%', 'THERAPY-20: switch refuses too');
  perform pg_temp.check((select count(*) from public.purchased_therapy_entitlements
                          where id in (pg_temp.fx('U_REF'), pg_temp.fx('U_CAN'), pg_temp.fx('U_DEL'))
                            and status = 'pending_activation' and activation_date is null) = 3,
    'THERAPY-20: none of them moved');
  r := public.claim_purchased_therapy(pg_temp.fx('U_OK'), 'unlimited', pg_temp.t(0));
  perform pg_temp.check((r->>'success')::boolean, 'THERAPY-20: a package on a paid sale still starts');
  perform pg_temp.legacy('L9', 'voucher', 4, 'pending_activation', src => 'credit_package', src_inv => 'inv_refunded');
  e := pg_temp.refused(format('select public.claim_entitlement_vouchers(%L, %L, null)', pg_temp.fx('L9'), pg_temp.sel('v_session', '1')));
  perform pg_temp.check(e = 'Invoice T422-INV-REFUNDED was refunded, so nothing can be claimed on this reward.' and pg_temp.issued('L9') = 0,
    'THERAPY-20: a reward on a refunded sale is not handed over');
  perform pg_temp.check(public.entitlement_voucher_state(pg_temp.fx('L9'))->>'blocked_reason' = 'Invoice T422-INV-REFUNDED was refunded',
    'THERAPY-20: the Vouchers window says why');
  -- The Owner or Manager closes it: Cancel package (refund_purchased_therapy).
  perform public.refund_purchased_therapy(pg_temp.fx('U_CAN'), 'T422 sale cancelled');
  perform pg_temp.check((select status from public.purchased_therapy_entitlements where id = pg_temp.fx('U_CAN')) = 'refunded',
    'THERAPY-20: an Owner closes a package on a cancelled sale');

  -- ── THERAPY-M2: overlaps ask first ──
  perform pg_temp.legacy('RUN', 'unlimited', null, 'active', cust => 'buyer3', act => pg_temp.t(-5), exp => pg_temp.t(20));
  perform pg_temp.legacy('L10', 'unlimited', null, 'pending_activation', cust => 'buyer3');
  select count(*) into v_audits from public.audit_logs where record_id = pg_temp.fx('L10');
  r := public.claim_legacy_therapy(pg_temp.fx('L10'), pg_temp.t(0));
  perform pg_temp.check((r->>'requires_confirmation')::boolean and not (r->>'claimed')::boolean
                        and (r->>'suggested_start')::date = pg_temp.t(21)
                        and (r->'existing') @> '[{"entitlement_no": "T422-RUN"}]',
    'THERAPY-M2: an overlapping claim asks first, names the running period and suggests the day after it ends');
  perform pg_temp.check((select status = 'pending_activation' and activation_date is null
                           from public.therapy_entitlements where id = pg_temp.fx('L10'))
                        and (select count(*) from public.audit_logs where record_id = pg_temp.fx('L10')) = v_audits,
    'THERAPY-M2: asking writes nothing');
  r := public.claim_legacy_therapy(pg_temp.fx('L10'), pg_temp.t(21));
  perform pg_temp.check((r->>'claimed')::boolean and not (r->>'overlapped')::boolean and r->>'status' = 'scheduled',
    'THERAPY-M2: the suggested start claims without asking, scheduled');
  perform pg_temp.legacy('L11', 'unlimited', null, 'pending_activation', cust => 'buyer3');
  r := public.claim_legacy_therapy(pg_temp.fx('L11'), pg_temp.t(0), null, null, null, null, true);
  perform pg_temp.check((r->>'claimed')::boolean and (r->>'overlapped')::boolean and r->>'status' = 'active'
                        and exists (select 1 from public.audit_logs where record_id = pg_temp.fx('L11')
                                     and action = 'legacy_therapy_claimed' and (new_data->>'overlap_confirmed')::boolean),
    'THERAPY-M2: a confirmed overlap claims and is recorded as confirmed');
  perform pg_temp.legacy('L12', 'unlimited', null, 'pending_activation', cust => 'buyer_b', store => 'store_b');
  r := public.claim_legacy_therapy(pg_temp.fx('L12'), pg_temp.t(0));
  perform pg_temp.check((r->>'claimed')::boolean and r->>'status' = 'active', 'THERAPY-M2: with nothing running it claims straight');

  -- ── THERAPY-15: days left ──
  perform pg_temp.unit('U_ACT', 'active', 'inv_paid', act => pg_temp.t(-20), exp => pg_temp.t(9), cust => 'buyer_b');
  perform pg_temp.unit('U_SCH', 'scheduled', 'inv_paid', act => pg_temp.t(10), exp => pg_temp.t(39), cust => 'buyer_b');
  perform pg_temp.check((select days_remaining from public.purchased_therapy_units(null, null, false) where purchased_id = pg_temp.fx('U_ACT')) = 10
                        and (select days_remaining from public.purchased_therapy_units(null, null, false) where purchased_id = pg_temp.fx('U_SCH')) = 30,
    'THERAPY-15: 10 days left for a unit ending in nine days (today counts), 30 for one starting in ten and running 30 days');

  -- ── THERAPY-5, -19: the page's list ──
  -- An old reward: 10 vouchers issued before claim documents existed.
  perform pg_temp.legacy('L13', 'voucher', 10, 'active');
  insert into public.customer_reward_vouchers(customer_id, voucher_id, entitlement_id, store_id, quantity, notes)
    values (pg_temp.fx('buyer'), pg_temp.fx('v_session'), pg_temp.fx('L13'), pg_temp.fx('store_a'), 10, 'T422 issued before 310');
  perform pg_temp.legacy('L14', 'voucher', 10, 'cancelled');
  r := public.therapy_list_page('legacy', 'T422-L13', null, 50, 0);
  perform pg_temp.check((r->>'total')::int = 1 and (r->'rows'->0->>'claimed_qty')::int = 10
                        and (r->'rows'->0->>'remaining')::int = 0,
    'THERAPY-5: an old reward shows all 10 handed over, none left');
  r := public.therapy_list_page('legacy', 'T422-L14', null, 50, 0);
  perform pg_temp.check((r->>'total')::int = 0 and r->>'status' = 'open', 'THERAPY-19: a cancelled reward is hidden by default');
  r := public.therapy_list_page('legacy', 'T422-L14', 'cancelled', 50, 0);
  perform pg_temp.check((r->>'total')::int = 1 and (r->'rows'->0->>'remaining')::int = 0,
    'THERAPY-5: shown on request, a cancelled reward has nothing left');
  r := public.therapy_list_page('legacy', '+6591422104', 'all', 50, 0);
  perform pg_temp.check((r->>'total')::int = (select count(*) from public.therapy_entitlements where customer_id = pg_temp.fx('buyer3'))
                        and (r->>'total')::int > 0
                        and (select bool_and(x->>'customer_name' = 'T422 Third Buyer') from jsonb_array_elements(r->'rows') x),
    'THERAPY-19: search by phone finds that customer''s rows, with the name');
  r := public.therapy_list_page('legacy', 'T422', 'all', 2, 2);
  perform pg_temp.check(jsonb_array_length(r->'rows') = 2
                        and (r->>'total')::int = (select count(*) from public.therapy_entitlements where entitlement_no like 'T422-%')
                        and (r->>'offset')::int = 2,
    'THERAPY-19: a page of two from the third row, with the full total');
  -- A page past the end (a claim took the only row of the last page): no
  -- rows, and still the full total, so the page can step back.
  r := public.therapy_list_page('legacy', 'T422', 'all', 2, 100000);
  perform pg_temp.check(jsonb_array_length(r->'rows') = 0
                        and (r->>'total')::int = (select count(*) from public.therapy_entitlements where entitlement_no like 'T422-%'),
    'THERAPY-19: a Legacy page past the end has no rows and the full total');
  r := public.therapy_list_page('purchased', 'T422', 'all', 50, 100000);
  perform pg_temp.check(jsonb_array_length(r->'rows') = 0
                        and (r->>'total')::int = (select count(*) from public.purchased_therapy_entitlements where entitlement_no like 'T422-%')
                        and (r->>'total')::int > 0,
    'THERAPY-19: a Purchased page past the end has no rows and the full total');
  r := public.therapy_list_page('legacy', 'T422-L11', 'active', 50, 0);
  perform pg_temp.check((r->>'total')::int = 1 and (r->'rows'->0->>'days_remaining')::int
                          = (select expiry_date - public.sg_today() + 1 from public.therapy_entitlements where id = pg_temp.fx('L11')),
    'THERAPY-15: a running Legacy period counts today in its days left');
  r := public.therapy_list_page('legacy', 'T422-L10', 'scheduled', 50, 0);
  perform pg_temp.check((r->>'total')::int = 1, 'THERAPY-19: the status filter reads the status');
  perform pg_temp.legacy('L15', 'unlimited', null, 'pending_activation', cust => 'buyer3');
  r := public.therapy_list_page('legacy', 'T422-L15', null, 50, 0);
  perform pg_temp.check((r->'rows'->0->>'next_free_start')::date
                          = (select max(expiry_date) + 1 from public.therapy_entitlements
                              where customer_id = pg_temp.fx('buyer3') and status in ('active', 'scheduled')),
    'THERAPY-M2: the list gives the next free start for an unclaimed unlimited reward');
  r := public.therapy_list_page('purchased', 'T422-INV-REFUNDED', null, 50, 0);
  perform pg_temp.check((r->>'total')::int = 1 and r->'rows'->0->>'invoice_closed_reason' = 'Invoice T422-INV-REFUNDED was refunded'
                        and r->'rows'->0->>'invoice_no' = 'T422-INV-REFUNDED',
    'THERAPY-20: the Purchased list says the sale was refunded (search by invoice number)');
  r := public.therapy_list_page('purchased', 'T422-U_SCH', null, 50, 0);
  perform pg_temp.check((r->'rows'->0->>'days_remaining')::int = 30 and r->'rows'->0->>'status_now' = 'scheduled',
    'THERAPY-15: the Purchased list counts a scheduled unit from its start');
  r := public.therapy_list_page('purchased', 'T422', 'closed', 50, 0);
  perform pg_temp.check((r->>'total')::int = 1 and r->'rows'->0->>'entitlement_no' = 'T422-U_CAN',
    'THERAPY-19: the closed filter lists the package an Owner closed');
  perform pg_temp.check(pg_temp.refused('select public.therapy_list_page(''everything'')') like 'Unknown list%'
                        and pg_temp.refused('select public.therapy_list_page(''legacy'', null, ''lost'')') like 'Unknown status filter%',
    'THERAPY-19: an unknown list or filter is refused');
  r := public.therapy_list_page('legacy', null, 'all', 100000, -5);
  perform pg_temp.check((r->>'limit')::int = 200 and (r->>'offset')::int = 0, 'THERAPY-19: a page is at most 200 rows');

  -- ── Rule 9: a deleted customer's name and phone ──
  -- The list is a SECURITY DEFINER read, so it must hide what the read rule
  -- on customers hides (deleted_at is null). delete_customer refuses open
  -- purchased units, so the unit here has ended.
  perform pg_temp.legacy('L_GONE', 'voucher', 2, 'active', cust => 'buyer_gone');
  perform pg_temp.unit('U_GONE', 'expired', 'inv_paid', act => pg_temp.t(-60), exp => pg_temp.t(-30), cust => 'buyer_gone');
  r := public.therapy_list_page('legacy', 'T422 Gone Buyer', 'all', 50, 0);
  perform pg_temp.check((r->>'total')::int = 1 and r->'rows'->0->>'customer_phone' = '+6591422105',
    'rule 9: before the customer is deleted, the list finds them by name, with the phone');
  update public.customers set deleted_at = now() where id = pg_temp.fx('buyer_gone');
  foreach k in array array['legacy', 'purchased'] loop
    r := public.therapy_list_page(k, case k when 'legacy' then 'T422-L_GONE' else 'T422-U_GONE' end, 'all', 50, 0);
    perform pg_temp.check((r->>'total')::int = 1 and r->'rows'->0->>'customer_name' is null
                          and r->'rows'->0->>'customer_phone' is null
                          and (r->'rows'->0->>'customer_id')::uuid = pg_temp.fx('buyer_gone'),
      format('rule 9: the %s list still shows a deleted customer''s row, with no name or phone', k));
    perform pg_temp.check(
      not exists (select 1 from jsonb_array_elements(public.therapy_list_page(k, 'T422 Gone Buyer', 'all', 200, 0)->'rows') x
                   where (x->>'customer_id')::uuid = pg_temp.fx('buyer_gone'))
      and not exists (select 1 from jsonb_array_elements(public.therapy_list_page(k, '91422105', 'all', 200, 0)->'rows') x
                       where (x->>'customer_id')::uuid = pg_temp.fx('buyer_gone')),
      format('rule 9: the %s list does not find a deleted customer by name or phone', k));
  end loop;
  perform pg_temp.check((select customer_name is null from public.purchased_therapy_units(null, null, false)
                          where purchased_id = pg_temp.fx('U_GONE'))
                        and (select customer_name from public.purchased_therapy_units(null, null, false)
                              where purchased_id = pg_temp.fx('U_OK')) = 'T422 Second Buyer',
    'rule 9: purchased_therapy_units gives no name for a deleted customer, and the name for a live one');

  -- ── THERAPY-12 (Q16 A) and X-9: who may ──
  -- Staff of store A hand over a credit-package reward's vouchers at A ...
  perform pg_temp.as_login('staff_a');
  r := public.claim_entitlement_vouchers(pg_temp.fx('L5'), pg_temp.sel('v_session', '2'), 'T422 staff');
  perform pg_temp.check((r->>'claimed_now')::int = 2, 'THERAPY-12: a member of staff hands over a credit-package reward''s vouchers');
  -- ... but no more than is left ...
  e := pg_temp.refused(format('select public.claim_entitlement_vouchers(%L, %L, null)', pg_temp.fx('L5'), pg_temp.sel('v_session', '3')));
  perform pg_temp.check(e like 'Only 2 left to claim%', 'THERAPY-12: and no more than the reward allows');
  -- ... and nothing at store B.
  perform pg_temp.legacy('LB', 'voucher', 4, 'pending_activation', store => 'store_b', cust => 'buyer_b',
                         src => 'premium_bundle', src_inv => 'inv_b');
  e := pg_temp.refused(format('select public.claim_entitlement_vouchers(%L, %L, null)', pg_temp.fx('LB'), pg_temp.sel('v_session', '1')));
  perform pg_temp.check(e = 'No access to this store', 'THERAPY-12: not at a store they do not work at');
  r := public.therapy_list_page('legacy', 'T422', 'all', 200, 0);
  perform pg_temp.check(not exists (select 1 from jsonb_array_elements(r->'rows') x where (x->>'store_id')::uuid = pg_temp.fx('store_b')),
    'THERAPY-12: their Legacy list holds only store A');
  r := public.therapy_list_page('purchased', 'T422', 'all', 200, 0);
  perform pg_temp.check(not exists (select 1 from jsonb_array_elements(r->'rows') x where (x->>'store_id')::uuid = pg_temp.fx('store_b'))
                        and (r->>'total')::int > 0,
    'THERAPY-12: their Purchased list holds only store A');
  perform pg_temp.check(not public.can_change_therapy_dates(pg_temp.fx('store_b')), 'X-9: not at a store they do not work at');
  -- staff_ab works at B second.
  perform pg_temp.as_login('staff_ab');
  perform pg_temp.check(public.can_change_therapy_dates(pg_temp.fx('store_b')), 'X-9: a member of staff''s second store counts');
  r := public.claim_entitlement_vouchers(pg_temp.fx('LB'), pg_temp.sel('v_session', '1'), null);
  perform pg_temp.check((r->>'claimed_now')::int = 1, 'THERAPY-12: a premium-bundle reward at their second store');
  perform pg_temp.check(position('user_has_store_access(v_ent.store_id)' in
                          pg_get_functiondef('public.activate_therapy_beneficiary(uuid,date,date)'::regprocedure)) > 0
                        and position('my_assigned_store_id' in
                          pg_get_functiondef('public.activate_therapy_beneficiary(uuid,date,date)'::regprocedure)) = 0,
    'X-9: activate_therapy_beneficiary reads every store the member of staff works at');

  -- ── Rule 10: no sale and no voucher list, an Owner or Manager hands it over ──
  perform pg_temp.as_server();
  perform pg_temp.legacy('N1', 'voucher', 3, 'pending_activation');
  perform pg_temp.legacy('N2', 'voucher', 3, 'pending_activation', eligible => array[pg_temp.fx('v_session')]);
  perform pg_temp.legacy('N3', 'voucher', 3, 'pending_activation', src => 'credit_package', src_inv => 'inv_paid');
  perform pg_temp.as_login('staff_a');
  e := pg_temp.refused_state(format('select public.claim_entitlement_vouchers(%L, %L, null)', pg_temp.fx('N1'), pg_temp.sel('v_session', '1')));
  perform pg_temp.check(e = '42501 No sale and no voucher list is recorded for this reward, so an Owner or Manager hands it over.'
                        and pg_temp.issued('N1') = 0,
    'rule 10: a member of staff does not hand over a reward with no sale and no voucher list');
  r := public.entitlement_voucher_state(pg_temp.fx('N1'));
  perform pg_temp.check((r->>'owner_or_manager_only')::boolean and r->>'blocked_reason' is null,
    'rule 10: the Vouchers window says it waits for an Owner or Manager');
  perform pg_temp.check(
    (select bool_and(((x->>'owner_or_manager_only')::boolean) = (x->>'entitlement_no' = 'T422-N1'))
       from jsonb_array_elements(public.therapy_list_page('legacy', 'T422-N', 'all', 50, 0)->'rows') x)
    and (public.therapy_list_page('legacy', 'T422-N', 'all', 50, 0)->>'total')::int = 3,
    'rule 10: the Legacy list marks that reward only, not one with a list or a sale');
  perform public.claim_entitlement_vouchers(pg_temp.fx('N2'), pg_temp.sel('v_session', '1'), null);
  perform public.claim_entitlement_vouchers(pg_temp.fx('N3'), pg_temp.sel('v_session', '1'), null);
  perform pg_temp.check(pg_temp.issued('N2') = 1 and pg_temp.issued('N3') = 1
                        and not (public.entitlement_voucher_state(pg_temp.fx('N2'))->>'owner_or_manager_only')::boolean
                        and not (public.entitlement_voucher_state(pg_temp.fx('N3'))->>'owner_or_manager_only')::boolean,
    'rule 10: a member of staff still hands over a reward with a voucher list, or with a sale (Q16 A)');
  perform pg_temp.as_login('manager');
  r := public.claim_entitlement_vouchers(pg_temp.fx('N1'), pg_temp.sel('v_session', '2'), 'T422 manager');
  perform pg_temp.check((r->>'claimed_now')::int = 2 and pg_temp.issued('N1') = 2,
    'rule 10: a Manager hands it over');
  perform pg_temp.as_login('owner');
  r := public.claim_entitlement_vouchers(pg_temp.fx('N1'), pg_temp.sel('v_massage', '1'), null);
  perform pg_temp.check((r->>'claimed_now')::int = 1 and pg_temp.issued('N1') = 3, 'rule 10: so does an Owner');

  -- ── Rule 12: Cancel package leaves commission alone ──
  perform pg_temp.unit('U_COM', 'pending_activation', 'inv_paid', cust => 'buyer3');
  e := pg_temp.w2_commission('U_COM')::text;
  perform pg_temp.as_login('manager');
  perform public.refund_purchased_therapy(pg_temp.fx('U_COM'), 'T422 customer changed their mind');
  perform pg_temp.check((select status = 'earned' and reversal_reason is null and reversed_at is null
                           from public.commissions where id = e::uuid)
                        and (select status from public.purchased_therapy_entitlements where id = pg_temp.fx('U_COM')) = 'refunded'
                        and exists (select 1 from public.audit_logs where record_id = pg_temp.fx('U_COM') and action = 'therapy_refunded'),
    'rule 12: Cancel package closes the package, with an audit row, and leaves the earned commission alone');
  perform pg_temp.as_login('staff_a');
  perform pg_temp.unit('U_COM2', 'pending_activation', 'inv_paid', cust => 'buyer3');
  e := pg_temp.refused(format('select public.refund_purchased_therapy(%L, ''T422'')', pg_temp.fx('U_COM2')));
  perform pg_temp.check(e = 'Only an Owner or Manager can refund therapy', 'rule 12: Cancel package is still Owners'' and Managers'' alone');
  -- Cancel package checks the package's store, as claim and activate do.
  perform pg_temp.as_server();
  perform pg_temp.unit('U_XS', 'pending_activation', 'inv_b', store => 'store_b', cust => 'buyer_b');
  perform pg_temp.as_login('manager');
  e := pg_temp.refused(format('select public.refund_purchased_therapy(%L, ''T422'')', pg_temp.fx('U_XS')));
  perform pg_temp.check(e = 'No access to this store'
                        and (select status from public.purchased_therapy_entitlements where id = pg_temp.fx('U_XS')) = 'pending_activation',
    'Cancel package: a Manager of store A does not close a package of store B');
  perform pg_temp.as_login('owner');
  perform public.refund_purchased_therapy(pg_temp.fx('U_XS'), 'T422 the Owner closes it');
  perform pg_temp.check((select status from public.purchased_therapy_entitlements where id = pg_temp.fx('U_XS')) = 'refunded',
    'Cancel package: an Owner closes it (every store)');
end $$;

-- ── Rule 11: new qualification voucher rewards save the voucher list ──
-- In its own savepoint: store C's sales and rules are undone after.
savepoint w2;
do $$
declare v_list uuid[];
begin
  perform pg_temp.as_server();
  perform pg_temp.w2_fixtures();
  v_list := pg_temp.w2_earned('w2_spender');
  perform pg_temp.check(v_list = pg_temp.on_offer()
                        and v_list @> array[pg_temp.fx('v_session'), pg_temp.fx('v_massage')]
                        and not v_list && array[pg_temp.fx('v_noreward'), pg_temp.fx('v_fixed'), pg_temp.fx('v_birthday')],
    'rule 11: a new Legacy voucher reward saves the reward vouchers on offer that day, free-session ones only');
  perform public.recompute_affiliate_legacy_qualification(pg_temp.fx('w2_affiliate'), public.sg_today());
  perform pg_temp.check((select count(*) = 2 and bool_and(eligible_voucher_ids = pg_temp.on_offer())
                           from public.therapy_entitlements
                          where customer_id = pg_temp.fx('w2_affiliate') and earner_kind = 'affiliate'),
    'rule 11: new affiliate voucher rewards save it too');
  v_list := pg_temp.w2_earned('w2_big');
  perform pg_temp.check(v_list is null
                        and (select entitlement_kind from public.therapy_entitlements
                              where customer_id = pg_temp.fx('w2_big') and status = 'pending_activation') = 'unlimited',
    'rule 11: an unlimited reward saves no list');
  -- With no reward voucher on offer, no list: an Owner or Manager hands it over (rule 10).
  update public.vouchers set reward_eligible = false where voucher_kind = 'normal';
  v_list := pg_temp.w2_earned('w2_quiet');
  perform pg_temp.as_login('owner');
  perform pg_temp.check(v_list is null
                        and (select (public.entitlement_voucher_state(e.id)->>'owner_or_manager_only')::boolean
                               from public.therapy_entitlements e
                              where e.customer_id = pg_temp.fx('w2_quiet') and e.status = 'pending_activation'),
    'rule 11: with no reward voucher on offer it saves no list, and waits for an Owner or Manager');
  perform pg_temp.as_server();
  -- A recompute that changes nothing leaves a saved list as it is.
  update public.vouchers set reward_eligible = true where voucher_kind = 'normal' and id <> pg_temp.fx('v_noreward');
  perform pg_temp.w2_earned('w2_spender');
  perform pg_temp.check((select count(*) = 1 and bool_and(eligible_voucher_ids @> array[pg_temp.fx('v_session')])
                           from public.therapy_entitlements
                          where customer_id = pg_temp.fx('w2_spender') and status = 'pending_activation'),
    'rule 11: recomputing the same day keeps the one reward and its list');
end $$;
rollback to savepoint w2;

-- The read rule on purchased packages, as signed-in staff (row level security).
do $$
declare n_a int; n_ab int; n_owner int; n_all int; n_invitee int; n_deleted int; e text; q text; v_who text;
begin
  if not has_table_privilege('authenticated', 'public.purchased_therapy_entitlements', 'select') then
    grant select on public.purchased_therapy_entitlements to authenticated;  -- rolled back
  end if;
  -- Two logins 407 does not count as staff, both marked active and assigned
  -- to store A: a pending invitee and a deleted profile.
  insert into fx values ('invitee', gen_random_uuid()), ('deleted', gen_random_uuid());
  insert into auth.users(id, email)
    values (pg_temp.fx('invitee'), 't422-invitee@sig.invalid'), (pg_temp.fx('deleted'), 't422-deleted@sig.invalid');
  insert into public.profiles(id, full_name, email, role, is_active, invitation_status, deleted_at)
    values (pg_temp.fx('invitee'), 'T422 invitee', 't422-invitee@sig.invalid', 'staff', true, 'pending', null),
           (pg_temp.fx('deleted'), 'T422 deleted', 't422-deleted@sig.invalid', 'staff', true, 'accepted', now());
  insert into public.user_store_assignments(user_id, store_id)
    values (pg_temp.fx('invitee'), pg_temp.fx('store_a')), (pg_temp.fx('deleted'), pg_temp.fx('store_a'));
  perform pg_temp.as_login('invitee');
  set local role authenticated;
  select count(*) into n_invitee from public.purchased_therapy_entitlements where entitlement_no like 'T422-%';
  reset role;
  perform pg_temp.as_login('deleted');
  set local role authenticated;
  select count(*) into n_deleted from public.purchased_therapy_entitlements where entitlement_no like 'T422-%';
  reset role;
  perform pg_temp.check(n_invitee = 0 and n_deleted = 0,
    'THERAPY-12: a pending invitee and a deleted profile at store A read no purchased package (as 407 has it)');

  -- 406's check, the first statement 422 gives the five purchased-package
  -- functions (Cancel package, refund_purchased_therapy, among them). Both logins are marked active and work at store A, so the
  -- store check alone (user_has_store_access reads is_active only) lets them
  -- by. Each function refuses them first, as not staff (42501), never with
  -- 'No access to this store' or a later message. claim_purchased_therapy
  -- calls the other functions, which refuse too, so it is also asked for
  -- vouchers on a unit already taken as unlimited therapy: there its own
  -- refusal would answer before it calls anything.
  perform pg_temp.as_server();
  perform pg_temp.unit('U_STAFF', 'pending_activation', 'inv_paid', null, array['unlimited', 'voucher'], cust => 'buyer3');
  perform pg_temp.unit('U_TAKEN', 'pending_activation', 'inv_paid', 'unlimited', array['unlimited', 'voucher'], cust => 'buyer3');
  foreach v_who in array array['deleted', 'invitee'] loop
    perform pg_temp.as_login(v_who);
    foreach q in array array[
        format('select public.claim_purchased_therapy(%L, ''unlimited'', %L)', pg_temp.fx('U_STAFF'), pg_temp.t(0)),
        format('select public.claim_purchased_therapy(%L, ''voucher'')', pg_temp.fx('U_TAKEN')),
        format('select public.activate_purchased_therapy(%L, %L)', pg_temp.fx('U_STAFF'), pg_temp.t(0)),
        format('select public.choose_therapy_benefit(%L, ''unlimited'')', pg_temp.fx('U_STAFF')),
        format('select public.switch_therapy_benefit(%L, ''voucher'', ''T422'')', pg_temp.fx('U_STAFF')),
        format('select public.refund_purchased_therapy(%L, ''T422'')', pg_temp.fx('U_STAFF'))] loop
      e := pg_temp.refused_state(q);
      perform pg_temp.check(e = '42501 Only active Energia staff can do this.',
        format('406 first: %s refuses the %s login as not staff (got: %s)',
               substring(q from 'public\.([a-z_]+)'), v_who, coalesce(e, 'accepted')));
    end loop;
  end loop;
  perform pg_temp.check((select status = 'pending_activation' and benefit_choice is null and activation_date is null
                           from public.purchased_therapy_entitlements where id = pg_temp.fx('U_STAFF')),
    '406 first: nothing moved on the unit');
  -- Active staff of store A still get through: they choose the benefit.
  perform pg_temp.as_login('staff_a');
  perform public.choose_therapy_benefit(pg_temp.fx('U_STAFF'), 'unlimited');
  perform pg_temp.check((select benefit_choice = 'unlimited' from public.purchased_therapy_entitlements
                          where id = pg_temp.fx('U_STAFF')),
    '406 first: active staff of the store still choose the benefit');
  select count(*) into n_all from public.purchased_therapy_entitlements where entitlement_no like 'T422-%';
  perform pg_temp.as_login('staff_a');
  set local role authenticated;
  select count(*) into n_a from public.purchased_therapy_entitlements where entitlement_no like 'T422-%';
  reset role;
  perform pg_temp.as_login('staff_ab');
  set local role authenticated;
  select count(*) into n_ab from public.purchased_therapy_entitlements where entitlement_no like 'T422-%';
  reset role;
  perform pg_temp.as_login('owner');
  set local role authenticated;
  select count(*) into n_owner from public.purchased_therapy_entitlements where entitlement_no like 'T422-%';
  reset role;
  perform pg_temp.check(n_a = (select count(*) from public.purchased_therapy_entitlements
                                where entitlement_no like 'T422-%' and store_id = pg_temp.fx('store_a'))
                        and n_a < n_all and n_ab = n_all and n_owner = n_all,
    'THERAPY-12: "read pte" shows staff the packages of their stores; an Owner sees all');
  perform pg_temp.as_server();
end $$;

rollback;
