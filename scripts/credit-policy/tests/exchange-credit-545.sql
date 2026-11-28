-- 545: a product exchange's credit can be spent (the owner, 27 Nov 2026).
-- supabase/545_exchange_credit_can_be_spent.sql
--
-- Run on a copy of production with 545 in (it reads, makes two exchange lots through the app's
-- own grant_exchange_credit, and rolls everything back):
--   psql -v ON_ERROR_STOP=1 -d <copy> -f scripts/credit-policy/tests/exchange-credit-545.sql
-- Without 545 the P checks fail (product exchange credit is 'needs_review' there).
--
--   P. The policy: 'product_exchange' is open; every other source keeps its policy.
--   L. A lot made by grant_exchange_credit with no purposes: open; it may pay products (own,
--      third-party, other), therapy, vouchers, promotions, event tickets, special and
--      consignment products (544); never a credit package, a premium bundle or 'unknown'
--      (rentals among them).
--   R. A lot made with purposes keeps them: ["product"] pays a product, not therapy.

\set ON_ERROR_STOP 1
begin;

create temp table t545 (n int generated always as identity, check_name text, ok boolean) on commit drop;

-- P. The policy.
insert into t545 (check_name, ok) values
  ('P1 product_exchange (with a source) is open', public.credit_lot_policy('product_exchange', 'exchange', true) = 'open'),
  ('P2 product_exchange (no source) is open', public.credit_lot_policy('product_exchange', 'exchange', false) = 'open'),
  ('P3 exchange stays open', public.credit_lot_policy('exchange', 'exchange', true) = 'open'),
  ('P4 manual sources stay open', public.credit_lot_policy('manual_legacy', 'legacy', false) = 'open'
                                  and public.credit_lot_policy('manual_adjustment', 'paid', false) = 'open'),
  ('P5 premium bundle stays bundle_any (and needs_review with no source)',
     public.credit_lot_policy('premium_bundle', 'paid', true) = 'bundle_any'
     and public.credit_lot_policy('premium_bundle', 'paid', false) = 'needs_review'),
  ('P6 credit package stays package_paid/bonus',
     public.credit_lot_policy('credit_package', 'paid', true) = 'package_paid'
     and public.credit_lot_policy('credit_package', 'bonus', true) = 'package_bonus'),
  ('P7 an unknown source stays needs_review',
     public.credit_lot_policy('credit_package_progress', 'paid', true) = 'needs_review'
     and public.credit_lot_policy('not_a_source', 'paid', true) = 'needs_review');

-- L and R. Two exchange lots through the app's own call, for a made-up customer, signed in as a
-- made-up Owner (both rolled back).
do $t$
declare v_own uuid := gen_random_uuid(); v_c uuid; v_s uuid; v_open uuid; v_restricted uuid;
begin
  insert into auth.users(id, email) values (v_own, 't545-owner@example.com');
  insert into public.profiles(id, full_name, email, role, is_active) values (v_own, 'T545 Owner', 't545-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into public.stores(name, code, country_code) values ('T545 Store', 'T545S1', 'SG') returning id into v_s;
  insert into public.customers(full_name, phone) values ('T545 Exchange Customer', '+61491570545') returning id into v_c;
  v_open := public.grant_exchange_credit(null, v_c, 50, v_s, null, null);
  v_restricted := public.grant_exchange_credit(null, v_c, 30, v_s, null, '["product"]'::jsonb);
  perform set_config('t545.open', v_open::text, true);
  perform set_config('t545.restricted', v_restricted::text, true);
end $t$;

insert into t545 (check_name, ok)
select 'L1 the lot is a product exchange lot of category exchange', l.source_type = 'product_exchange' and l.category = 'exchange'
  from public.customer_credit_lots l where l.id = current_setting('t545.open')::uuid;
insert into t545 (check_name, ok) values
  ('L2 the lot''s policy is open', public.credit_lot_policy_for(current_setting('t545.open')::uuid) = 'open');

insert into t545 (check_name, ok)
select 'L3 it may pay ' || c, public.credit_lot_allows_category(current_setting('t545.open')::uuid, c)
  from unnest(array['own_product','third_party_product','other_product','therapy_session','unlimited_therapy',
                    'session_voucher','money_voucher','promotion','event_ticket','special_product','consignment_product']) c;
insert into t545 (check_name, ok)
select 'L4 it may not pay ' || c, not public.credit_lot_allows_category(current_setting('t545.open')::uuid, c)
  from unnest(array['credit_package','premium_bundle','unknown']) c;
insert into t545 (check_name, ok) values
  ('L5 a rental is unknown, so it may not pay it',
     not public.credit_lot_allows_category(current_setting('t545.open')::uuid, public.purchase_category('rental'))),
  ('L6 no purposes given: its own list does not stop a product or therapy',
     public.credit_lot_snapshot_allows(current_setting('t545.open')::uuid,
       (select usage_restrictions from public.customer_credit_lots where id = current_setting('t545.open')::uuid), 'product', null)
     and public.credit_lot_snapshot_allows(current_setting('t545.open')::uuid,
       (select usage_restrictions from public.customer_credit_lots where id = current_setting('t545.open')::uuid), 'therapy', null));

insert into t545 (check_name, ok) values
  ('R1 a lot made with purposes ["product"] may pay a product',
     public.credit_lot_snapshot_allows(current_setting('t545.restricted')::uuid,
       (select usage_restrictions from public.customer_credit_lots where id = current_setting('t545.restricted')::uuid), 'product', null)),
  ('R2 ... and not therapy',
     not public.credit_lot_snapshot_allows(current_setting('t545.restricted')::uuid,
       (select usage_restrictions from public.customer_credit_lots where id = current_setting('t545.restricted')::uuid), 'therapy', null));

select count(*) filter (where ok) as passed, count(*) filter (where not ok or ok is null) as failed from t545;
select n, check_name from t545 where not ok or ok is null order by n;
-- A failed check stops the run with an error (exit code 3 under ON_ERROR_STOP), so a runner that
-- goes by the exit code never counts it as a pass (the audit's note, 27 Nov 2026).
do $done$
declare v_failed int := (select count(*) from t545 where not ok or ok is null);
begin
  if v_failed > 0 then raise exception '545 suite: % check(s) failed (listed above)', v_failed; end if;
end $done$;
rollback;
