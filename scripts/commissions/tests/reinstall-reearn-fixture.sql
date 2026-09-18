-- Fixtures for the reinstall + re-earn test. Isolated local database only.
--
-- The runner has already put the 5D2-era earn_invoice_commission in place, so
-- the rows written here are what production wrote: each shape below is one
-- that exists on production, named after the invoice it copies.
\set ON_ERROR_STOP on
begin;

create function pg_temp.person(p_name text, p_phone text, p_referred_by uuid default null)
returns uuid language sql as $$
  insert into public.customers(full_name, phone, referred_by) values (p_name, p_phone, p_referred_by) returning id
$$;
create function pg_temp.affiliate(p_customer uuid, p_store uuid)
returns uuid language sql as $$
  insert into public.customer_affiliates(customer_id, store_id, status, referral_code)
  values (p_customer, p_store, 'active', 'RE' || upper(substr(md5(p_customer::text), 1, 6))) returning id
$$;
-- A paid invoice with one or more lines. Lines: [{kind, amount, discount, promotion}].
create function pg_temp.paid_invoice(p_no text, p_store uuid, p_buyer uuid, p_by uuid,
  p_affiliate uuid, p_explicit boolean, p_lines jsonb, p_status text default 'paid')
returns uuid language plpgsql as $$
declare v_inv uuid; l jsonb; v_sub numeric := 0; v_disc numeric := 0;
begin
  select coalesce(sum((x->>'amount')::numeric), 0), coalesce(sum(coalesce((x->>'discount')::numeric, 0)), 0)
    into v_sub, v_disc from jsonb_array_elements(p_lines) x;
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, affiliate_id,
    affiliate_selection_explicit, subtotal, discount_total, total_amount, paid_amount, paid_at, locked_at)
  values (p_no, p_store, p_buyer, p_by, p_status::public.invoice_status, p_affiliate, p_explicit,
    v_sub, v_disc, v_sub - v_disc, case when p_status = 'paid' then v_sub - v_disc else 0 end,
    '2026-09-01 04:00+00', '2026-09-01 04:00+00')
  returning id into v_inv;
  for l in select * from jsonb_array_elements(p_lines) loop
    insert into public.invoice_items(invoice_id, line_kind, product_id, promotion_id, quantity, unit_price,
      line_total, line_discount)
    values (v_inv, (l->>'kind')::public.invoice_line_kind,
      case when l->>'kind' = 'product' then (l->>'product')::uuid end,
      case when l->>'kind' = 'promotion' then (l->>'promotion')::uuid end,
      1, (l->>'amount')::numeric, (l->>'amount')::numeric, coalesce((l->>'discount')::numeric, 0));
  end loop;
  return v_inv;
end $$;

do $$
declare
  owner_id uuid := gen_random_uuid(); st uuid; prod uuid; promo uuid; inv uuid;
  mariam uuid; marlinah uuid; marlinah_aff uuid;
  manjil uuid; alaric_dup uuid; alaric uuid; alaric_aff uuid;
  andrew uuid; chiao uuid; zoe uuid; zoe_aff uuid;
  pauline uuid; madalene uuid;
  bob uuid; carol uuid;
  dave uuid; erin uuid;
  fay uuid; gil uuid;
  hana uuid; ivy uuid; ivy_aff uuid;
begin
  insert into auth.users(id, email) values (owner_id, 'reearn-owner@tests.invalid');
  insert into public.profiles(id, full_name, email, role)
  values (owner_id, 'Reearn Owner', 'reearn-owner@tests.invalid', 'owner');
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  insert into public.stores(name, code, country_code) values ('Reearn tests', 'REEARN', 'SG') returning id into st;
  insert into public.products(name, sku) values ('Reearn own product', 'REEARN-OWN') returning id into prod;
  insert into public.promotions(name, code) values ('Reearn promotion', 'REEARN-PROMO') returning id into promo;
  -- Production's rates: tier 2 is 35, which the old build never read.
  update public.app_settings set commission_tier2_own_rate = 35, commission_tier2_third_rate = 35 where id = true;

  -- 0222: affiliate selected on the invoice, buyer has no referrer. Product
  -- with a voucher discount on the line. Old build: nothing at all.
  mariam := pg_temp.person('Reearn Mariam', '+6591118901');
  marlinah := pg_temp.person('Reearn Marlinah', '+6591118902');
  marlinah_aff := pg_temp.affiliate(marlinah, st);
  inv := pg_temp.paid_invoice('REEARN-0222', st, mariam, owner_id, marlinah_aff, true,
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product', prod, 'amount', 149, 'discount', 72)));
  perform public.earn_invoice_commission(inv);

  -- 0227: buyer's profile referrer is a duplicate record that is not an
  -- affiliate; the real affiliate is selected on the invoice. Old build: paid
  -- the duplicate.
  alaric_dup := pg_temp.person('Reearn Alaric (duplicate)', '+6591118903');
  alaric := pg_temp.person('Reearn Alaric Ong', '+6591118904');
  alaric_aff := pg_temp.affiliate(alaric, st);
  manjil := pg_temp.person('Reearn Manjil', '+6591118905', alaric_dup);
  inv := pg_temp.paid_invoice('REEARN-0227', st, manjil, owner_id, alaric_aff, false,
    jsonb_build_array(jsonb_build_object('kind', 'voucher', 'amount', 22)));
  perform public.earn_invoice_commission(inv);

  -- 0158: tier 1 is right, tier 2 goes to someone not activated at the fixed 5%.
  chiao := pg_temp.person('Reearn Chiao', '+6591118906');
  zoe := pg_temp.person('Reearn Zoe', '+6591118907', chiao);
  zoe_aff := pg_temp.affiliate(zoe, st);
  andrew := pg_temp.person('Reearn Andrew', '+6591118908', zoe);
  inv := pg_temp.paid_invoice('REEARN-0158', st, andrew, owner_id, zoe_aff, true,
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product', prod, 'amount', 747)));
  perform public.earn_invoice_commission(inv);

  -- 0215: profile referrer, active, nothing selected. Both builds agree.
  madalene := pg_temp.person('Reearn Madalene', '+6591118909');
  perform pg_temp.affiliate(madalene, st);
  pauline := pg_temp.person('Reearn Pauline', '+6591118910', madalene);
  inv := pg_temp.paid_invoice('REEARN-0215', st, pauline, owner_id, null, false,
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product', prod, 'amount', 259)));
  perform public.earn_invoice_commission(inv);

  -- PAID: the old build paid someone not activated, and the money went out.
  carol := pg_temp.person('Reearn Carol', '+6591118911');
  bob := pg_temp.person('Reearn Bob', '+6591118912', carol);
  inv := pg_temp.paid_invoice('REEARN-PAID', st, bob, owner_id, null, false,
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product', prod, 'amount', 100)));
  perform public.earn_invoice_commission(inv);
  update public.commissions set status = 'paid' where invoice_id = inv;

  -- NONE: an explicit "None" on the invoice; the old build paid the referrer anyway.
  erin := pg_temp.person('Reearn Erin', '+6591118913');
  perform pg_temp.affiliate(erin, st);
  dave := pg_temp.person('Reearn Dave', '+6591118914', erin);
  inv := pg_temp.paid_invoice('REEARN-NONE', st, dave, owner_id, null, true,
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product', prod, 'amount', 200)));
  perform public.earn_invoice_commission(inv);

  -- REFUNDED: out of scope whatever it holds.
  gil := pg_temp.person('Reearn Gil', '+6591118915');
  perform pg_temp.affiliate(gil, st);
  fay := pg_temp.person('Reearn Fay', '+6591118916', gil);
  inv := pg_temp.paid_invoice('REEARN-REFUNDED', st, fay, owner_id, null, false,
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product', prod, 'amount', 100)), 'refunded');

  -- 0220: two promotion lines, affiliate selected, buyer not referred. Old
  -- build: nothing.
  ivy := pg_temp.person('Reearn Ivy', '+6591118917');
  ivy_aff := pg_temp.affiliate(ivy, st);
  hana := pg_temp.person('Reearn Hana', '+6591118918');
  inv := pg_temp.paid_invoice('REEARN-0220', st, hana, owner_id, ivy_aff, true,
    jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion', promo, 'amount', 61),
                      jsonb_build_object('kind', 'promotion', 'promotion', promo, 'amount', 61)));
  perform public.earn_invoice_commission(inv);
end $$;

-- What the old build left behind, for the record.
select i.invoice_no, c.full_name as credited, x.tier, x.rate, x.commission_amount, x.status
  from public.commissions x
  join public.invoices i on i.id = x.invoice_id
  join public.customers c on c.id = x.referrer_customer_id
 where i.invoice_no like 'REEARN-%'
 order by i.invoice_no, x.tier;
commit;
