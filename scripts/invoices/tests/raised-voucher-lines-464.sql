-- A voucher line raised or added by a correction on a paid invoice gives its extra vouchers, once (464).
--
-- 457's NOT COVERED: on an invoice already paid, a voucher line raised by a correction took the extra
-- unit (at the save with a product on the invoice, or at the payment that settled it again) but gave no
-- extra voucher, because the issuer gives a line once and runs only when an invoice turns paid. A line added
-- to a paid invoice the same. The rule kept: a voucher line gives as many vouchers as its quantity once
-- the invoice is paid in full; nothing is given twice; a save that keeps an invoice completed FOC gives no
-- more (416).
--
--   G  The AFTER md5s; the grants (correct_invoice: signed-in staff and the service role, never anon; the
--      trigger function and give_raised_voucher_units: the server's alone); customer_reward_vouchers.issue_no
--      and the widened issued-once index; what 464 relies on, unchanged.
--   A  A paid voucher-only invoice, kept paid: raised to two at a lower price (the second voucher given, issue
--      2, its unit taken with a row, valued at its share, one audit row); the same save replayed, and a note
--      changed, give nothing; raised to three (issue 3); lowered (nothing taken back, as before) and raised
--      again to three (nothing more).
--   B  Socks and a voucher, paid, the voucher raised at the same total by a Manager: the second voucher given;
--      its unit taken once (by the product's put-back-and-take-again, none by 464); the socks as they were.
--   C  A voucher line added to a paid invoice: on a voucher-only invoice (its unit taken by 464) and on a
--      socks invoice (taken once): its vouchers given.
--   D  Raised by staff so the invoice is part paid: nothing given or taken before the payment; staff take
--      the payment: the second voucher given once, its unit taken once; a later save gives nothing.
--   E  Later events give nothing twice: a cancel takes every voucher back and returns every unit; reopened and
--      paid, the vouchers are given again (no new sale), their units out once; one voucher refunded by line,
--      then the line raised: only the units above what it gave; a customer change moves every voucher.
--   F  A refund request of the retired kind (refund_requested): raised while it waits (nothing given), the
--      request rejected: paid again, the second voucher given and its unit taken.
--   H  416 kept: raised on a completed FOC invoice that stays FOC gives nothing more; the FOC then taken off
--      and the invoice paid: two vouchers, given again by 416, nothing by 464.
--   S  A line's voucher swapped at the same quantity on a paid invoice gives nothing new (as before; NOT
--      COVERED); raised as well, the extra unit is given as the new voucher.
--   R  Raised while cancelled, then reopened and paid: the reopening gives back one, 464 the other; two
--      units out.
--   M  464 twice changes nothing; its first run changes only its three functions (one added, none dropped);
--      each run leaves no row and uses no sequence (its self-test).
--
-- Disposable local database only (production as it is: 460, 461, 456, 457 and 458 in); everything is rolled
-- back. Every name and email is invented (@example.com); phones are ACMA's fictional range (+61 2 5550
-- ....). It installs 464 twice (run with -v skip_install=1 where 464 is already installed). Every check
-- runs, then the file fails if any did.
\set ON_ERROR_STOP on
begin;
create function pg_temp.row_counts() returns jsonb language plpgsql as
$$declare r record; n bigint; v jsonb := '{}'::jsonb;
begin
  for r in select c.oid::regclass::text as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname in ('public', 'auth') and c.relkind = 'r' order by 1 loop
    execute format('select count(*) from %s', r.t) into n;
    v := v || jsonb_build_object(r.t, n);
  end loop;
  return v;
end$$;
create function pg_temp.seqs() returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(sequencename, coalesce(last_value, 0)), '{}'::jsonb) from pg_sequences where schemaname = 'public' $$;
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language plpgsql as
$$begin
  perform set_config('search_path', 'public', true);
  return query select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
                 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
end$$;
\if :{?skip_install}
\else
create temp table b464 as select * from pg_temp.fn_md5s();
create temp table r464 as select pg_temp.row_counts() as before, pg_temp.seqs() as seq_before;
\ir ../../../supabase/464_raised_voucher_lines_give_their_vouchers.sql
create temp table m464 as select * from pg_temp.fn_md5s();
alter table r464 add column after1 jsonb, add column seq_after1 jsonb;
update r464 set after1 = pg_temp.row_counts(), seq_after1 = pg_temp.seqs();
\ir ../../../supabase/464_raised_voucher_lines_give_their_vouchers.sql
alter table r464 add column after2 jsonb, add column seq_after2 jsonb;
update r464 set after2 = pg_temp.row_counts(), seq_after2 = pg_temp.seqs();
\endif
set local search_path = public;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.putx(key text, val uuid) returns uuid language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v returning v $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true),
          set_config('request.jwt.claim.role', 'authenticated', true) $$;
-- One saved line as the correction form sends it back: its id, kind, item and saved price; the quantity,
-- price, FOC and voucher as given (null: as saved).
create function pg_temp.ln(item uuid, qty int default null, price numeric default null, foc int default null, vch uuid default null)
  returns jsonb language sql as
$$ select jsonb_strip_nulls(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text, 'product_id', product_id,
     'voucher_id', coalesce(vch, voucher_id), 'quantity', coalesce(qty, quantity), 'unit_price', coalesce(price, unit_price),
     'foc_quantity', coalesce(foc, foc_quantity, 0),
     'foc_reason', case when coalesce(foc, foc_quantity, 0) > 0 then coalesce(foc_reason, 'Test giveaway') end))
     from public.invoice_items where id = item $$;
-- A new voucher line, as the form sends it.
create function pg_temp.newv(key text, qty int, price numeric) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx(key), 'quantity', qty, 'unit_price', price) $$;
-- Every saved line as saved, but the voucher line (the first) as given.
create function pg_temp.vlines(inv uuid, qty int, price numeric default null, foc int default null, vch uuid default null)
  returns jsonb language sql as
$$ select jsonb_agg(case when it.line_kind = 'voucher' and it.id = (select min(x.id::text)::uuid from public.invoice_items x
                                                                     where x.invoice_id = inv and x.line_kind = 'voucher')
                         then pg_temp.ln(it.id, qty, price, foc, vch) else pg_temp.ln(it.id) end order by it.id)
     from public.invoice_items it where it.invoice_id = inv $$;
create function pg_temp.edits(inv uuid) returns int language sql as $$ select coalesce(edit_count, 0) from public.invoices where id = inv $$;
-- A correction as the page saves it; null when it was saved, else the refusal (which undoes all it did).
create function pg_temp.fix(inv uuid, items jsonb, reason text, hdr jsonb default '{}'::jsonb, req uuid default null) returns text language plpgsql as
$$begin
  perform public.correct_invoice(inv, items, jsonb_build_object('expected_edit_count', pg_temp.edits(inv)) || hdr, reason, coalesce(req, gen_random_uuid()));
  return null;
exception when others then return sqlerrm; end$$;
create function pg_temp.pay(inv uuid, amount numeric) returns text language plpgsql as
$$begin
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', amount)), gen_random_uuid());
  return null;
exception when others then return sqlerrm; end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.mk(lines jsonb, cust text default 'cust') returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx(cust), lines, jsonb_build_object('business_date', public.sg_today())) $$;
create function pg_temp.v1(key text default 'vch', qty int default 1) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx(key), 'quantity', qty)) $$;
create function pg_temp.st(inv uuid) returns text language sql as $$ select status::text from public.invoices where id = inv $$;
create function pg_temp.vline(inv uuid) returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = inv and line_kind = 'voucher' order by id limit 1 $$;
create function pg_temp.vstock(key text default 'vch') returns int language sql as
$$ select current_qty from public.voucher_store_stock where store_id = pg_temp.fx('A') and voucher_id = pg_temp.fx(key) $$;
create function pg_temp.shelf(key text) returns int language sql as
$$ select current_qty from public.store_inventory where store_id = pg_temp.fx('A') and product_id = pg_temp.fx(key) $$;
-- The vouchers the invoice gave that are held (unused), in units; of one voucher, or of one customer.
create function pg_temp.held(inv uuid, key text default null, cust text default null) returns int language sql as
$$ select coalesce(sum(v.quantity), 0)::int from public.customer_reward_vouchers v
     join public.invoice_benefit_values b on b.reward_voucher_id = v.id
    where b.invoice_id = inv and v.status = 'held' and (key is null or v.voucher_id = pg_temp.fx(key))
      and (cust is null or v.customer_id = pg_temp.fx(cust)) $$;
-- The line's sale vouchers ('invoice_voucher_sale'), by issue_no.
create function pg_temp.sales(item uuid) returns int[] language sql as
$$ select coalesce(array_agg(issue_no order by issue_no), '{}') from public.customer_reward_vouchers
    where source_type = 'invoice_voucher_sale' and source_id = item $$;
-- What each of the line's vouchers is worth (its value row's paid_value), by issue_no.
create function pg_temp.worth(item uuid) returns numeric[] language sql as
$$ select coalesce(array_agg(b.paid_value order by v.issue_no, v.issued_at, v.id), '{}') from public.invoice_benefit_values b
     join public.customer_reward_vouchers v on v.id = b.reward_voucher_id where b.invoice_item_id = item $$;
create function pg_temp.vmoves(inv uuid, key text default 'vch') returns int language sql as
$$ select coalesce(sum(quantity), 0)::int from public.invoice_voucher_movements where invoice_id = inv and voucher_id = pg_temp.fx(key) $$;
create function pg_temp.added_audits(inv uuid) returns int language sql as
$$ select count(*)::int from public.audit_logs where table_name = 'invoices' and record_id = inv and action = 'voucher_units_added_given' $$;
-- Where the invoice's vouchers and stock stand, for a failing check to show.
create function pg_temp.state(inv uuid, key text default 'vch') returns text language sql as
$$ select jsonb_build_object('status', pg_temp.st(inv), 'total', (select total_amount from public.invoices where id = inv),
     'held', pg_temp.held(inv), 'sales', pg_temp.sales(pg_temp.vline(inv)), 'worth', pg_temp.worth(pg_temp.vline(inv)), 'vstock', pg_temp.vstock(key), 'vmoves', pg_temp.vmoves(inv, key),
     'added_audits', pg_temp.added_audits(inv))::text $$;
-- The Finance panel's refund by line of p_units of the line's vouchers (paid back from its payments).
create function pg_temp.back(inv uuid, item uuid, p_units int, p_issue int default null) returns text language plpgsql as
$$declare opts jsonb; ben jsonb; tot numeric; src jsonb := '[]'; left_ numeric; p record;
begin
  opts := public.invoice_refund_options_before_sessions(inv);
  select jsonb_build_array(jsonb_build_object('benefit_id', b->>'id',
           'amount', round((b->>'paid_value')::numeric * p_units / (b->>'granted_value')::numeric, 2))),
         round((b->>'paid_value')::numeric * p_units / (b->>'granted_value')::numeric, 2)
    into ben, tot from jsonb_array_elements(opts->'benefits') b
   where b->>'invoice_item_id' = item::text and b->>'benefit_kind' = 'voucher'
     and (b->>'remaining_value')::numeric >= p_units and (b->>'max_refund')::numeric > 0
     and (p_issue is null or exists (select 1 from public.invoice_benefit_values bv join public.customer_reward_vouchers v on v.id = bv.reward_voucher_id
                                      where bv.id = (b->>'id')::uuid and v.issue_no = p_issue))
   order by (b->>'remaining_value')::numeric desc, b->>'id' limit 1;
  if ben is null then return 'nothing to refund'; end if;
  left_ := tot;
  for p in select id, public.invoice_payment_remaining(id) as rem from public.invoice_payments
            where invoice_id = inv and entry_kind = 'receipt' and public.invoice_payment_remaining(id) > 0 order by created_at, id loop
    exit when left_ <= 0;
    src := src || jsonb_build_array(jsonb_build_object('payment_id', p.id, 'amount', least(p.rem, left_)));
    left_ := left_ - least(p.rem, left_);
  end loop;
  perform public.refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    src, '[]'::jsonb, 'T464 by line', gen_random_uuid());
  return null;
exception when others then return sqlerrm;
end$$;

-- ═════ Fixtures (invented) ═════
insert into public.app_settings(id) values (true) on conflict do nothing;
do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); s uuid := gen_random_uuid();
  sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  st uuid; cash uuid; v uuid; ph text[]; pr record;
begin
  select array_agg(x order by x) into ph
    from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(4640, 4699) g) y
   where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = y.x);
  insert into auth.users(id, email) values (o, 'rv464-o-' || sfx || '@example.com'), (m, 'rv464-m-' || sfx || '@example.com'),
                                           (s, 'rv464-s-' || sfx || '@example.com');
  insert into public.profiles(id, full_name, email, role, is_active) values
    (o, 'Test Owner', 'rv464-o-' || sfx || '@example.com', 'owner', true),
    (m, 'Test Manager', 'rv464-m-' || sfx || '@example.com', 'manager', true),
    (s, 'Test Staff', 'rv464-s-' || sfx || '@example.com', 'staff', true);
  insert into fx values ('o', o), ('m', m), ('s', s);
  perform pg_temp.as_user('o');
  insert into public.stores(name, code, country_code) values ('RV464 Store A ' || sfx, 'RV464A' || sfx, 'SG') returning id into st;
  perform pg_temp.putx('A', st);
  insert into public.user_store_assignments(user_id, store_id) values (s, st), (m, st);
  insert into public.payment_methods(name, is_active) values ('RV464 Cash ' || sfx, true) returning id into cash;
  perform pg_temp.putx('cash', cash);
  insert into public.products(name, sku, product_type) values ('Test Socks', 'RV464-socks-' || sfx, 'own') returning id into v;
  perform pg_temp.putx('socks', v);
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, v, 50);
  perform public.set_product_prices(st, v, 100, 100, 'available');
  for pr in select * from (values ('vch', 'Test Voucher'), ('vchB', 'Test Voucher B')) y(k, n) loop
    insert into public.vouchers(name, code, voucher_kind, selling_price, qty_type, is_active)
      values (pr.n, 'RV464-' || pr.k || '-' || sfx, 'normal', 90, 'limited', true) returning id into v;
    perform pg_temp.putx(pr.k, v);
    insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (v, st, 100);
    insert into public.voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 90, true);
  end loop;
  insert into public.customers(full_name, phone) values ('Test Customer', ph[1]) returning id into v;
  perform pg_temp.putx('cust', v);
  insert into public.customers(full_name, phone) values ('Test Other Customer', ph[2]) returning id into v;
  perform pg_temp.putx('cust2', v);
end $$;

-- ═════ G The md5s, the grants, the table, what 464 relies on ═════
select pg_temp.check((select md5 from pg_temp.fn_md5s() where fn = 'correct_invoice(uuid,jsonb,jsonb,text,uuid)') = '04d647e13e9424a9375942e5812e91a2'
    and (select md5 from pg_temp.fn_md5s() where fn = 'trg_issue_sold_vouchers_on_paid()') = 'cf0b5610b77edfea2683751d5c25ca1d'
    and (select md5 from pg_temp.fn_md5s() where fn = 'give_raised_voucher_units(uuid,uuid[],boolean,text)') = '84d4c7bbd39a754d61cbe4f778777a33',
  'G1 correct_invoice, trg_issue_sold_vouchers_on_paid and give_raised_voucher_units have 464''s AFTER md5s');
select pg_temp.check(not has_function_privilege('anon', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'execute')
    and (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.trg_issue_sold_vouchers_on_paid()'::regprocedure) = array['postgres=X/postgres', 'service_role=X/postgres']
    and (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.give_raised_voucher_units(uuid,uuid[],boolean,text)'::regprocedure) = array['postgres=X/postgres', 'service_role=X/postgres'],
  'G2 correct_invoice: signed-in staff and the service role, never anon; the trigger function and give_raised_voucher_units: the server''s alone');
select pg_temp.check(
    (select format_type(a.atttypid, a.atttypmod) || ' ' || a.attnotnull || ' '
            || pg_get_expr((select ad.adbin from pg_attrdef ad where ad.adrelid = a.attrelid and ad.adnum = a.attnum), a.attrelid)
       from pg_attribute a where a.attrelid = 'public.customer_reward_vouchers'::regclass and a.attname = 'issue_no' and not a.attisdropped) = 'integer true 1'
    and pg_get_indexdef('public.customer_reward_vouchers_issued_once'::regclass) =
        'CREATE UNIQUE INDEX customer_reward_vouchers_issued_once ON public.customer_reward_vouchers USING btree (source_type, source_id, voucher_id, issue_no) WHERE ((source_id IS NOT NULL) AND (source_type = ANY (ARRAY[''invoice_voucher_sale''::text, ''invoice_promotion_voucher''::text])))'
    and exists (select 1 from pg_constraint c where c.conrelid = 'public.customer_reward_vouchers'::regclass
                  and c.conname = 'customer_reward_vouchers_issue_no_check' and pg_get_constraintdef(c.oid) = 'CHECK ((issue_no >= 1))')
    and not exists (select 1 from public.customer_reward_vouchers where issue_no < 1),
  'G3 customer_reward_vouchers.issue_no (integer, not null, default 1, at least 1); the issued-once index now per line, voucher and issue');
select pg_temp.check(coalesce((select md5 from pg_temp.fn_md5s() where fn = x.fn), 'missing') = x.md5, 'G4 relied on and unchanged: ' || x.fn)
  from (values ('issue_sold_vouchers_for_invoice(uuid)', '0dbb4bc74411b6d4f0535f661a8c09ee'),
               ('issue_promotion_vouchers_for_invoice(uuid)', 'e47e5f623b1fa3f6eafe83086f0c9776'),
               ('cancel_invoice_recorded(uuid,text,uuid)', 'de52d9dbaef8ab15163bef35cb9d733d'),
               ('apply_reopened_invoice_vouchers()', '28d3b7a69b91ddebcdb200559d96a0ef'),
               ('invoice_own_voucher_ids(uuid)', '9340840f1ce4e031ec3613198688ba2e'),
               ('invoice_voucher_stock_unrecorded(uuid,boolean)', '91c8f0fa69ef6337f323b7ac467a8c2b'),
               ('invoice_stock_to_deduct(uuid)', '6356494ccb8545d46c56b788f8f85f54'),
               ('invoice_required_stock(uuid)', 'c91dc1eb4f2b7b465de5fe4a8fb2ca0c'),
               ('deduct_invoice_stock(uuid,text)', '32183fe9e7c15ed0b11307c48289831a'),
               ('invoice_discounted_line_value(uuid)', 'ead4a430c3abd1e3f953912867ca4fe6'),
               ('snapshot_therapy_voucher_issue(uuid,boolean)', '12ba32611ad001781862d82b1ae13c8e'),
               ('update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)', '1f034561a461bdb46a1e6274e0d04606'),
               ('record_invoice_payment(uuid,jsonb,uuid)', '9c70097ed4da614fb9dcc66fdfcdb7d6'),
               ('invoice_record_payments_internal(uuid,jsonb)', '21890d84bcb0b9c00a2bc98aff313d0b'),
               ('create_invoice_with_details(uuid,uuid,jsonb,jsonb)', '770ee0129b0e9fe909259ad7ea95b8d0'),
               ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855')) x(fn, md5);

-- ═════ A A paid voucher-only invoice, kept paid ═════
do $$
declare inv uuid; it uuid; e text; e2 text; s0 int := pg_temp.vstock(); req uuid := gen_random_uuid(); b record;
begin
  perform pg_temp.as_user('o');
  inv := pg_temp.mk(pg_temp.v1()); it := pg_temp.vline(inv);
  e := pg_temp.pay(inv, 90);
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv) = 1 and pg_temp.sales(it) = '{1}' and pg_temp.vstock() = s0 - 1,
    'A0 one voucher, paid S$90: one held (issue 1), its unit taken: ' || coalesce(e, pg_temp.state(inv)));
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'Two at S$45', '{}'::jsonb, req);
  select bv.paid_value, bv.granted_value, bv.evidence, v.notes into b
    from public.invoice_benefit_values bv join public.customer_reward_vouchers v on v.id = bv.reward_voucher_id
   where bv.invoice_item_id = it and v.issue_no = 2;
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'paid' and (select total_amount from public.invoices where id = inv) = 90
      and pg_temp.held(inv) = 2 and pg_temp.sales(it) = '{1,2}' and pg_temp.vstock() = s0 - 2 and pg_temp.vmoves(inv) = 2
      and pg_temp.added_audits(inv) = 1 and pg_temp.worth(it) = '{45,45}'
      and (select a.new_data->'revalued'->0->>'from' || '>' || (a.new_data->'revalued'->0->>'to') from public.audit_logs a
            where a.record_id = inv and a.action = 'voucher_units_added_given') = '90.00>45.00'
      and b.paid_value = 45 and b.granted_value = 1 and b.evidence = 'Issued for units added to the line after its vouchers were given'
      and b.notes like 'Sold on invoice %: units added to the line after its vouchers were given',
    'A1 the Owner raises it to two at S$45 (still paid): the second voucher given (issue 2, worth S$45), the first now worth S$45 too (was S$90, in the audit row), its unit taken with a row (before 464: one voucher, nothing taken): '
      || coalesce(e, pg_temp.state(inv)));
  -- The same save again (the page retried it): replayed, nothing more.
  perform public.correct_invoice(inv, pg_temp.vlines(inv, 2, 45), jsonb_build_object('expected_edit_count', 0), 'Two at S$45', req);
  perform pg_temp.check(pg_temp.held(inv) = 2 and pg_temp.sales(it) = '{1,2}' and pg_temp.vstock() = s0 - 2 and pg_temp.added_audits(inv) = 1,
    'A2 the same save replayed gives nothing more: ' || pg_temp.state(inv));
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'A note', '{"notes": "T464 note"}'::jsonb);
  perform pg_temp.check(e is null and pg_temp.held(inv) = 2 and pg_temp.sales(it) = '{1,2}' and pg_temp.vstock() = s0 - 2 and pg_temp.added_audits(inv) = 1,
    'A3 a note changed gives nothing more: ' || coalesce(e, pg_temp.state(inv)));
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 3, 30), 'Three at S$30');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv) = 3 and pg_temp.sales(it) = '{1,2,3}'
      and pg_temp.vstock() = s0 - 3 and pg_temp.vmoves(inv) = 3
      and pg_temp.worth(it) = '{30,30,30}',
    'A4 raised to three at S$30: the third given (issue 3), once; each now worth S$30: ' || coalesce(e, pg_temp.state(inv)));
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'Back to two');
  e2 := pg_temp.fix(inv, pg_temp.vlines(inv, 3, 30), 'Three again');
  perform pg_temp.check(e is null and e2 is null and pg_temp.held(inv) = 3 and pg_temp.sales(it) = '{1,2,3}' and pg_temp.vstock() = s0 - 3,
    'A5 lowered to two (nothing taken back, as before) and raised to three again: nothing more: ' || coalesce(e, e2, pg_temp.state(inv)));
  perform pg_temp.putx('A_inv', inv);
end $$;

-- ═════ B Socks and a voucher, paid; the voucher raised at the same total ═════
do $$
declare inv uuid; it uuid; e text; s0 int := pg_temp.vstock(); sh int := pg_temp.shelf('socks');
begin
  perform pg_temp.as_user('o');
  inv := pg_temp.mk(jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('socks'), 'quantity', 1))
                    || pg_temp.v1()); it := pg_temp.vline(inv);
  e := pg_temp.pay(inv, 190);
  perform pg_temp.as_user('m');
  e := coalesce(e, pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'Two at S$45'));
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv) = 2 and pg_temp.sales(it) = '{1,2}'
      and pg_temp.vstock() = s0 - 2 and pg_temp.vmoves(inv) = 2 and pg_temp.shelf('socks') = sh - 1
      and (select count(*) from public.invoice_voucher_movements where invoice_id = inv and reason like 'Voucher units added after%') = 0,
    'B1 a Manager raises the voucher to two at the same total: the second voucher given; its unit taken once, by the socks'' put-back-and-take-again (none by 464); the socks as they were (before 464: one voucher, two units out): '
      || coalesce(e, pg_temp.state(inv)));
end $$;

-- ═════ C A voucher line added to a paid invoice ═════
do $$
declare inv uuid; e text; s0 int := pg_temp.vstock(); sb int := pg_temp.vstock('vchB'); sh int; it2 uuid;
begin
  perform pg_temp.as_user('o');
  inv := pg_temp.mk(pg_temp.v1());
  e := pg_temp.pay(inv, 90);
  e := coalesce(e, pg_temp.fix(inv, pg_temp.vlines(inv, 1) || jsonb_build_array(pg_temp.newv('vchB', 1, 0)), 'A free B'));
  select id into it2 from public.invoice_items where invoice_id = inv and voucher_id = pg_temp.fx('vchB');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv, 'vch') = 1 and pg_temp.held(inv, 'vchB') = 1
      and pg_temp.sales(it2) = '{1}' and pg_temp.vstock() = s0 - 1 and pg_temp.vstock('vchB') = sb - 1 and pg_temp.vmoves(inv, 'vchB') = 1
      and (select notes from public.customer_reward_vouchers where source_id = it2) like 'Sold on invoice %: a line added after it was paid',
    'C1 a free voucher B line added to a paid voucher-only invoice: its voucher given (issue 1), its unit taken by 464 with a row (before 464: neither): '
      || coalesce(e, pg_temp.state(inv, 'vchB')));
  s0 := pg_temp.vstock(); sh := pg_temp.shelf('socks');
  inv := pg_temp.mk(jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('socks'), 'quantity', 1)));
  e := pg_temp.pay(inv, 100);
  e := coalesce(e, pg_temp.fix(inv, (select jsonb_agg(pg_temp.ln(id)) from public.invoice_items where invoice_id = inv)
                                    || jsonb_build_array(pg_temp.newv('vch', 2, 0)), 'Two free vouchers'));
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv) = 2 and pg_temp.sales(pg_temp.vline(inv)) = '{1}'
      and pg_temp.vstock() = s0 - 2 and pg_temp.vmoves(inv) = 2 and pg_temp.shelf('socks') = sh - 1,
    'C2 a line of two free vouchers added to a paid socks invoice: both given (one sale of two), their units taken once (before 464: taken, not given): '
      || coalesce(e, pg_temp.state(inv)));
end $$;

-- ═════ D Raised by staff, part paid, then paid ═════
do $$
declare inv uuid; it uuid; e text; s0 int := pg_temp.vstock();
begin
  perform pg_temp.as_user('s');
  inv := pg_temp.mk(pg_temp.v1()); it := pg_temp.vline(inv);
  e := pg_temp.pay(inv, 90);
  e := coalesce(e, pg_temp.fix(inv, pg_temp.vlines(inv, 2), 'Customer wants two'));
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'partially_paid' and pg_temp.held(inv) = 1 and pg_temp.sales(it) = '{1}'
      and pg_temp.vstock() = s0 - 1 and pg_temp.vmoves(inv) = 1,
    'D1 staff raise it to two (S$180, part paid): nothing given or taken before the payment (457): ' || coalesce(e, pg_temp.state(inv)));
  e := pg_temp.pay(inv, 90);
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv) = 2 and pg_temp.sales(it) = '{1,2}'
      and pg_temp.vstock() = s0 - 2 and pg_temp.vmoves(inv) = 2 and pg_temp.added_audits(inv) = 1
      and (select count(*) from public.invoice_voucher_movements where invoice_id = inv and reason like 'Voucher units added after%') = 0,
    'D2 staff take the rest: paid; the second voucher given once (by the trigger), its unit taken once, by the payment (before 464: two units out, one voucher): '
      || coalesce(e, pg_temp.state(inv)));
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 2), 'A note', '{"notes": "T464 D"}'::jsonb);
  perform pg_temp.check(e is null and pg_temp.held(inv) = 2 and pg_temp.sales(it) = '{1,2}' and pg_temp.vstock() = s0 - 2,
    'D3 a later save gives nothing more: ' || coalesce(e, pg_temp.state(inv)));
end $$;

-- ═════ E Later events give nothing twice ═════
do $$
declare inv uuid; it uuid; e text; e2 text; s0 int := pg_temp.vstock(); n_sales int;
begin
  perform pg_temp.as_user('o');
  -- E1/E2: cancelled, then reopened and paid.
  inv := pg_temp.mk(pg_temp.v1()); it := pg_temp.vline(inv);
  e := pg_temp.pay(inv, 90);
  e := coalesce(e, pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'Two at S$45'));
  e2 := pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, gen_random_uuid())', inv, 'T464 cancel'));
  perform pg_temp.check(e is null and e2 is null and pg_temp.st(inv) = 'cancelled' and pg_temp.held(inv) = 0 and pg_temp.vstock() = s0,
    'E1 raised to two (paid), then cancelled: both vouchers taken back, both units back in stock: ' || coalesce(e, e2, pg_temp.state(inv)));
  n_sales := (select count(*) from public.customer_reward_vouchers where source_type = 'invoice_voucher_sale' and source_id = it);
  e := pg_temp.err(format('select public.reopen_invoice(%L, %L, gen_random_uuid())', inv, 'T464 reopen'));
  if e is null and pg_temp.st(inv) <> 'paid' then
    e := pg_temp.pay(inv, (select public.invoice_charge_total(inv) - public.invoice_net_received(inv)));
  end if;
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv) = 2
      and (select count(*) from public.customer_reward_vouchers where source_type = 'invoice_voucher_sale' and source_id = it) = n_sales
      and pg_temp.vstock() = s0 - 2 and pg_temp.added_audits(inv) = 1,
    'E2 reopened and paid: both vouchers given again by the reopening, no new sale, two units out: ' || coalesce(e, pg_temp.state(inv)));
  -- E3: one voucher refunded by line, then the line raised.
  s0 := pg_temp.vstock();
  inv := pg_temp.mk(pg_temp.v1()); it := pg_temp.vline(inv);
  e := pg_temp.pay(inv, 90);
  e := coalesce(e, pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'Two at S$45'));
  e2 := pg_temp.back(inv, it, 1, 1);
  perform pg_temp.check(e is null and e2 is null and pg_temp.held(inv) = 1 and pg_temp.st(inv) = 'paid'
      and (select coalesce(sum(r.amount), 0) from public.invoice_refunds r where r.invoice_id = inv) = 45,
    'E3 raised to two at S$45, then the first voucher refunded by line: S$45 back (its share, not the S$90 it was given at), the invoice still paid, one held: '
      || coalesce(e, e2, pg_temp.state(inv)));
  s0 := pg_temp.vstock();
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'A note', '{"notes": "T464 E3"}'::jsonb);
  perform pg_temp.check(e is null and pg_temp.held(inv) = 1 and pg_temp.sales(it) = '{1,2}' and pg_temp.vstock() = s0,
    'E4 a later save does not give the refunded voucher again: ' || coalesce(e, pg_temp.state(inv)));
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 3, 30), 'Three at S$30');
  perform pg_temp.check(e is null and pg_temp.held(inv) = 2 and pg_temp.sales(it) = '{1,2,3}' and pg_temp.vstock() = s0 - 1
      and pg_temp.worth(it) = '{45,30,30}',
    'E5 then raised to three at S$30: only the third given (the refunded one counts as given), one unit taken; the refunded one keeps its value, the others S$30: '
      || coalesce(e, pg_temp.state(inv)));
  -- E6: a customer change that takes the benefits along moves every voucher, the added ones too.
  inv := pg_temp.mk(pg_temp.v1()); it := pg_temp.vline(inv);
  e := pg_temp.pay(inv, 90);
  e := coalesce(e, pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'Two at S$45'));
  e2 := pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'Bought for a friend',
                    jsonb_build_object('customer_id', pg_temp.fx('cust2'), 'benefit_action', 'transfer'));
  perform pg_temp.check(e is null and e2 is null and pg_temp.held(inv, null, 'cust2') = 2 and pg_temp.held(inv, null, 'cust') = 0
      and pg_temp.sales(it) = '{1,2}',
    'E6 then moved to another customer, the benefits with it: both vouchers move, nothing more is given: ' || coalesce(e, e2, pg_temp.state(inv)));
end $$;

-- ═════ F A refund request of the retired kind, rejected ═════
do $$
declare inv uuid; it uuid; e text; e2 text; s0 int := pg_temp.vstock(); req uuid;
begin
  perform pg_temp.as_user('o');
  inv := pg_temp.mk(pg_temp.v1()); it := pg_temp.vline(inv);
  e := pg_temp.pay(inv, 90);
  -- What the retired request_invoice_action did (service role only today): the invoice waits as refund_requested.
  req := public.request_invoice_action(inv, 'invoice_refund', false, 'T464 refund request');
  e := coalesce(e, pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45), 'Two at S$45'));
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'refund_requested' and pg_temp.held(inv) = 1 and pg_temp.vstock() = s0 - 1,
    'F1 raised to two while a refund request waits: nothing given or taken yet: ' || coalesce(e, pg_temp.state(inv)));
  e2 := pg_temp.err(format('select public.resolve_invoice_action_v2(%L, false, %L)', req, 'T464 not refunded'));
  perform pg_temp.check(e2 is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv) = 2 and pg_temp.sales(it) = '{1,2}'
      and pg_temp.vstock() = s0 - 2 and pg_temp.vmoves(inv) = 2
      and (select count(*) from public.invoice_voucher_movements where invoice_id = inv and reason like 'Voucher units added after%') = 1,
    'F2 the request rejected: paid again; the second voucher given and its unit taken, with a row: ' || coalesce(e2, pg_temp.state(inv)));
end $$;

-- ═════ H 416 kept ═════
do $$
declare inv uuid; it uuid; e text; e2 text; s0 int := pg_temp.vstock();
begin
  perform pg_temp.as_user('o');
  inv := pg_temp.mk(pg_temp.v1()); it := pg_temp.vline(inv);
  perform public.apply_line_foc(it, null, null, 'Test giveaway');
  perform public.confirm_foc_invoice(inv, null);
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 2, null, 2), 'Two free');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'completed_foc' and pg_temp.held(inv) = 1 and pg_temp.vstock() = s0 - 1
      and pg_temp.added_audits(inv) = 0,
    'H1 a completed FOC invoice raised to two that stays FOC gives nothing more (416): ' || coalesce(e, pg_temp.state(inv)));
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 2, null, 0), 'Not free after all');
  e2 := pg_temp.pay(inv, 180);
  perform pg_temp.check(e is null and e2 is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv) = 2 and pg_temp.vstock() = s0 - 2
      and pg_temp.added_audits(inv) = 0 and pg_temp.sales(it) = '{1}',
    'H2 the FOC taken off, then paid: two vouchers, given again by 416 (no sale added by 464), two units out: ' || coalesce(e, e2, pg_temp.state(inv)));
end $$;

-- ═════ S A line's voucher swapped ═════
do $$
declare inv uuid; it uuid; e text; s0 int := pg_temp.vstock(); sb int := pg_temp.vstock('vchB');
begin
  perform pg_temp.as_user('o');
  inv := pg_temp.mk(pg_temp.v1()); it := pg_temp.vline(inv);
  e := pg_temp.pay(inv, 90);
  e := coalesce(e, pg_temp.fix(inv, pg_temp.vlines(inv, 1, 90, null, pg_temp.fx('vchB')), 'B instead'));
  perform pg_temp.check(e is null and pg_temp.held(inv, 'vch') = 1 and pg_temp.held(inv, 'vchB') = 0 and pg_temp.vstock('vchB') = sb,
    'S1 KNOWN (as before): the line swapped to voucher B at the same quantity gives no B; the customer keeps A: ' || coalesce(e, pg_temp.state(inv, 'vchB')));
  e := pg_temp.fix(inv, pg_temp.vlines(inv, 2, 45, null, pg_temp.fx('vchB')), 'Two B');
  perform pg_temp.check(e is null and pg_temp.held(inv, 'vch') = 1 and pg_temp.held(inv, 'vchB') = 1 and pg_temp.vstock('vchB') = sb - 1,
    'S2 then raised to two: the extra unit given as B (A counts as the first), its unit taken: ' || coalesce(e, pg_temp.state(inv, 'vchB')));
end $$;

-- ═════ R Raised while cancelled, reopened and paid ═════
do $$
declare inv uuid; it uuid; e text; e2 text; s0 int := pg_temp.vstock();
begin
  perform pg_temp.as_user('o');
  inv := pg_temp.mk(pg_temp.v1()); it := pg_temp.vline(inv);
  e := pg_temp.pay(inv, 90);
  e := coalesce(e, pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, gen_random_uuid())', inv, 'T464 cancel')));
  e2 := pg_temp.fix(inv, pg_temp.vlines(inv, 2), 'Two, as it should have been');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'cancelled' and pg_temp.held(inv) = 0 and pg_temp.vstock() = s0,
    'R1 paid, cancelled (stock back) and then corrected (' || coalesce(e2, 'saved: raised to two') || '): nothing given: ' || coalesce(e, pg_temp.state(inv)));
  if e2 is null then
    e := pg_temp.err(format('select public.reopen_invoice(%L, %L, gen_random_uuid())', inv, 'T464 reopen'));
    if e is null and pg_temp.st(inv) <> 'paid' then
      e := pg_temp.pay(inv, (select public.invoice_charge_total(inv) - public.invoice_net_received(inv)));
    end if;
    perform pg_temp.check(e is null and pg_temp.st(inv) = 'paid' and pg_temp.held(inv) = 2 and pg_temp.sales(it) = '{1,2}'
        and pg_temp.vstock() = s0 - 2,
      'R2 reopened and paid: one voucher given again by the reopening, the second by 464; two units out (before 464: two out, one given): '
        || coalesce(e, pg_temp.state(inv)));
  end if;
end $$;

-- ═════ M Installing 464 ═════
\if :{?skip_install}
select pg_temp.check(true, 'M (skipped: 464 was installed before this run)');
\else
select pg_temp.check(
    (select array_agg(coalesce(b.fn, m.fn) order by coalesce(b.fn, m.fn)) from b464 b full join m464 m on m.fn = b.fn where b.md5 is distinct from m.md5)
      = array['correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'give_raised_voucher_units(uuid,uuid[],boolean,text)', 'trg_issue_sold_vouchers_on_paid()']
    and (select count(*) from m464) = (select count(*) from b464) + 1,
  'M1 the first run changed only its three functions (one added, none dropped)');
select pg_temp.check((select count(*) from m464 m join pg_temp.fn_md5s() f on f.fn = m.fn and f.md5 = m.md5) = (select count(*) from m464)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m464),
  'M2 the second run changed no function');
select pg_temp.check(before = after1 and before = after2, 'M3 neither run (its self-test) left a row: ' || coalesce((select string_agg(k, ', ') from jsonb_object_keys(before) k
    where before->k is distinct from after1->k or before->k is distinct from after2->k), 'none')) from r464;
select pg_temp.check(seq_before = seq_after1 and seq_before = seq_after2, 'M4 neither run (its self-test) used a sequence: ' || coalesce((select string_agg(k, ', ') from jsonb_object_keys(seq_before) k
    where seq_before->k is distinct from seq_after1->k or seq_before->k is distinct from seq_after2->k), 'none')) from r464;
\endif

-- ═════ Result ═════
do $$begin
  if exists (select 1 from failed) then
    raise exception '% check(s) failed: %', (select count(*) from failed), (select string_agg(msg, E'\n' order by n) from failed);
  end if;
  raise notice 'ALL PASSED';
end$$;
rollback;
