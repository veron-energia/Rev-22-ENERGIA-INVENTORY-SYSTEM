-- Every invoice has its correct path: a completed FOC invoice, and one once settled and unpaid again (457).
--
-- The Owner's answers, 22 Oct 2026 (item 9, the recommendations accepted): Owners and Managers (not staff)
-- get Correct Invoice on completed FOC invoices, with a reason and revision history, exactly like paid
-- invoices. After a correction takes the FOC off (the invoice becomes unpaid but was once settled, locked_at
-- set), it can be corrected again through Correct Invoice (Owners and Managers) instead of an Edit Invoice
-- that always fails. A corrected FOC that stays FOC issues no extra vouchers (416, kept). Cancelled and
-- refunded invoices stay correctable by Owners and Managers, with a plain message instead of the database's.
-- Exchange (replacement) invoices: header-only correction for Owners and Managers. Late fees stay uneditable.
--
--   G  The two AFTER md5s; their grants (correct_invoice: signed-in staff and the service role, never anon;
--      update_invoice_internal: the service role's, never signed-in staff's or anon's); what 457 relies on
--      unchanged.
--   F  A completed FOC invoice (two pairs of socks, a limited voucher and a therapy session, all FOC, a
--      referrer): staff are refused (377's words); a Manager needs a reason; the Owner corrects the header
--      (it stays completed FOC; one revision and one audit row; nothing moves); a Manager corrects the lines
--      while it stays FOC (a third pair taken from the shelf; the voucher raised to two gives nothing more and
--      keeps no more voucher stock: 416); the Owner takes the FOC off (unpaid, still locked, no payment; the
--      unused voucher taken back, its stock returned; the goods stay out; the therapy session kept).
--   X  The dead end closed: on that once-settled unpaid invoice staff are refused (377's words); the Owner
--      needs a reason ("You cannot edit this invoice" before 457, for everyone); the correction summary works
--      and changes nothing; with a reason the Owner corrects it again (still unpaid and locked, the printed
--      note set; as on a settled invoice its product stock is put back and taken again: a pair back on the
--      shelf; no voucher stock kept before the payment, which gives the vouchers and takes their units; a
--      revision and an audit row); and again (header only, a Manager); Make FOC is still refused on it
--      ("Invoice is locked").
--   P  Paid in full (by staff): paid; the two vouchers given, their stock taken once; the shelf as before;
--      the referrer's commission earned; the therapy session the same one, unchanged; no credit moved; then
--      staff may correct it (a paid invoice of their store).
--   V  Voucher stock on a once-settled invoice not paid in full comes back whole (the reviewer's three paths, and
--      two older ones): socks and a voucher, FOC confirmed then taken off, the voucher raised to two, then
--      cancelled before payment; the socks line removed, then deleted by staff; raised and lowered before
--      payment, then paid and cancelled; the FOC taken off and the voucher raised in one save, then
--      cancelled; part paid after the FOC came off, raised, then cancelled. Each ends with the voucher stock
--      and the shelf where they started; a save that stays FOC keeps 416's row wording.
--   E  A never-settled unpaid invoice: still an ordinary edit, no reason, staff too (as before).
--   R  Plain words, not the database's: on a refunded invoice, removing a line a refund row names (as the
--      older line refund, 55, wrote them); on a paid invoice, a line paid with the customer's credit, and on
--      it once cancelled; the header of a refunded or cancelled invoice still corrects (status kept, nothing
--      moves); staff are refused, as before.
--   Y  An exchange's replacement invoice with its top-up unpaid (no payment, locked), and a refund top-up
--      invoice (unpaid, no payment): header-only correction for an Owner with a reason (refused before 457:
--      "You cannot edit this invoice"); a line change refused (system-generated); staff refused; a reason
--      asked for.
--   M  457 twice changes nothing; its first run changes only the two functions (no function added or
--      dropped); its self-test leaves no row (when this file installs it).
--
-- Disposable local database only (456 installed); everything is rolled back. Every name and email is
-- invented (@example.com); phones are ACMA's fictional range (+61 2 5550 ....). It installs 457 twice (run
-- with -v skip_install=1 where 457 is already installed). Every check runs, then the file fails if any did.
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
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language plpgsql as
$$begin
  perform set_config('search_path', 'public', true);
  return query select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
                 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
end$$;
\if :{?skip_install}
\else
create temp table b457 as select * from pg_temp.fn_md5s();
create temp table r457 as select pg_temp.row_counts() as before;
\ir ../../../supabase/457_correct_foc_and_settled_invoices.sql
create temp table m457 as select * from pg_temp.fn_md5s();
alter table r457 add column after1 jsonb;
update r457 set after1 = pg_temp.row_counts();
\ir ../../../supabase/457_correct_foc_and_settled_invoices.sql
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
-- One saved line as the correction form sends it back: its id, kind, item and saved price; quantity and
-- FOC as given (null: as saved).
create function pg_temp.ln(item uuid, qty int default null, foc int default null) returns jsonb language sql as
$$ select jsonb_strip_nulls(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text, 'product_id', product_id,
     'voucher_id', voucher_id, 'therapy_service_id', therapy_service_id, 'quantity', coalesce(qty, quantity),
     'unit_price', unit_price, 'foc_quantity', coalesce(foc, foc_quantity, 0),
     'foc_reason', case when coalesce(foc, foc_quantity, 0) > 0 then coalesce(foc_reason, 'Test giveaway') end))
     from public.invoice_items where id = item $$;
-- Every saved line, as saved.
create function pg_temp.lines(inv uuid) returns jsonb language sql as
$$ select jsonb_agg(pg_temp.ln(id) order by id) from public.invoice_items where invoice_id = inv $$;
create function pg_temp.item(inv uuid, key text) returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = inv
      and (product_id = pg_temp.fx(key) or voucher_id = pg_temp.fx(key) or therapy_service_id = pg_temp.fx(key)) order by id limit 1 $$;
-- A correction as the page saves it; null when it was saved, else the refusal (which undoes all it did).
create function pg_temp.try(inv uuid, items jsonb, hdr jsonb, reason text) returns text language plpgsql as
$$begin perform public.correct_invoice(inv, items, hdr, reason, gen_random_uuid()); return null;
exception when others then return sqlerrm; end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.st(inv uuid) returns text language sql as $$ select status::text from public.invoices where id = inv $$;
create function pg_temp.shelf(key text) returns int language sql as
$$ select current_qty from public.store_inventory where store_id = pg_temp.fx('A') and product_id = pg_temp.fx(key) $$;
create function pg_temp.vstock() returns int language sql as
$$ select current_qty from public.voucher_store_stock where store_id = pg_temp.fx('A') and voucher_id = pg_temp.fx('vch') $$;
-- The vouchers the customer holds from the invoice (unused), in units.
create function pg_temp.held(inv uuid) returns int language sql as
$$ select coalesce(sum(v.quantity), 0)::int from public.customer_reward_vouchers v
     join public.invoice_benefit_values b on b.reward_voucher_id = v.id where b.invoice_id = inv and v.status = 'held' $$;
create function pg_temp.revs(inv uuid) returns int language sql as $$ select count(*)::int from public.invoice_revisions where invoice_id = inv $$;
create function pg_temp.audits(inv uuid) returns int language sql as
$$ select count(*)::int from public.audit_logs where table_name = 'invoices' and record_id = inv and action = 'invoice_corrected' $$;
create function pg_temp.edits(inv uuid) returns int language sql as $$ select coalesce(edit_count, 0) from public.invoices where id = inv $$;
create function pg_temp.earned(inv uuid) returns numeric language sql as
$$ select coalesce(sum(commission_amount), 0) from public.commissions where invoice_id = inv and status in ('earned', 'blocked') $$;
create function pg_temp.sessions(inv uuid) returns jsonb language sql as
$$ select coalesce(jsonb_agg(jsonb_build_object('id', id, 'qty', quantity_purchased, 'status', status) order by id), '[]'::jsonb)
     from public.customer_therapy_sessions where invoice_id = inv and is_current $$;
-- What a header-only correction must leave as it was.
create function pg_temp.moved(inv uuid) returns jsonb language sql as
$$ select jsonb_build_object(
     'invoice', (select jsonb_build_object('status', status, 'total', total_amount, 'paid', paid_amount, 'locked', locked_at,
                   'customer', customer_id, 'store', store_id) from public.invoices where id = inv),
     'items', (select jsonb_agg(jsonb_build_object('id', id, 'qty', quantity, 'foc', foc_quantity, 'total', line_total) order by id)
                 from public.invoice_items where invoice_id = inv),
     'payments', (select count(*) from public.invoice_payments where invoice_id = inv),
     'stock', (select jsonb_agg(jsonb_build_object('id', id, 'qty', quantity) order by id) from public.stock_movements where invoice_id = inv),
     'vmoves', (select jsonb_agg(jsonb_build_object('id', id, 'qty', quantity) order by id) from public.invoice_voucher_movements where invoice_id = inv),
     'vouchers', (select jsonb_agg(jsonb_build_object('id', v.id, 'status', v.status) order by v.id) from public.customer_reward_vouchers v
                    join public.invoice_benefit_values b on b.reward_voucher_id = v.id where b.invoice_id = inv),
     'commissions', (select jsonb_agg(to_jsonb(c) - 'updated_at' order by c.id) from public.commissions c where c.invoice_id = inv),
     'sessions', pg_temp.sessions(inv),
     'credit', (select count(*) from public.customer_credit_ledger)) $$;
-- Where the invoice's stock, vouchers and history stand, for a failing check to show.
create function pg_temp.state(inv uuid) returns text language sql as
$$ select jsonb_build_object('status', pg_temp.st(inv), 'socks', pg_temp.shelf('socks'), 'vstock', pg_temp.vstock(), 'held', pg_temp.held(inv),
     'vmoves', (select coalesce(sum(quantity), 0) from public.invoice_voucher_movements where invoice_id = inv),
     'revs', pg_temp.revs(inv), 'audits', pg_temp.audits(inv), 'earned', pg_temp.earned(inv),
     'total', (select total_amount from public.invoices where id = inv))::text $$;
-- The invoice's voucher movement rows, net (what they hold out).
create function pg_temp.vmoves(inv uuid) returns int language sql as
$$ select coalesce(sum(quantity), 0)::int from public.invoice_voucher_movements where invoice_id = inv $$;
-- A pair of socks and a voucher, both FOC, confirmed (completed FOC, locked), then the FOC taken off by
-- the Owner (unpaid, still locked, no payment; S$140; the socks out, the voucher taken back).
create function pg_temp.foc_off() returns uuid language plpgsql as
$$declare inv uuid; it record;
begin
  perform pg_temp.as_user('o');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('cust'),
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('socks'), 'quantity', 1),
                      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('vch'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()));
  for it in select id from public.invoice_items where invoice_id = inv order by id loop
    perform public.apply_line_foc(it.id, null, null, 'Test giveaway'); end loop;
  perform public.confirm_foc_invoice(inv, null);
  perform public.correct_invoice(inv, (select jsonb_agg(pg_temp.ln(id, null, 0) order by id) from public.invoice_items where invoice_id = inv),
    jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'Not a giveaway after all', gen_random_uuid());
  return inv;
end$$;
create function pg_temp.c377() returns text language sql as
$$ select 'Only an Owner or Manager can correct this invoice. Staff can correct a paid or part-paid invoice of their own store while no refund or cancellation request is waiting on it'::text $$;

-- ═════ Fixtures (invented) ═════
insert into public.app_settings(id) values (true) on conflict do nothing;
-- A wallet method that pays from the customer's own ("other") Bonus credit, as production has (82).
insert into public.payment_methods (name, is_active, is_wallet_credit, wallet_category, is_system)
select 'Wallet — Bonus Credit', true, true, 'bonus', true
 where not exists (select 1 from public.payment_methods m where m.name = 'Wallet — Bonus Credit' and m.deleted_at is null);
do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); s uuid := gen_random_uuid(); im uuid := gen_random_uuid();
  sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  st uuid; cash uuid; v uuid; cust uuid; ref uuid; ph text[]; pr record;
begin
  select array_agg(x order by x) into ph
    from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(4570, 4699) g) y
   where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = y.x);
  insert into auth.users(id, email) values (o, 'fc457-o-' || sfx || '@example.com'), (m, 'fc457-m-' || sfx || '@example.com'),
                                           (s, 'fc457-s-' || sfx || '@example.com'), (im, 'fc457-im-' || sfx || '@example.com');
  insert into public.profiles(id, full_name, email, role, is_active) values
    (o, 'Test Owner', 'fc457-o-' || sfx || '@example.com', 'owner', true),
    (m, 'Test Manager', 'fc457-m-' || sfx || '@example.com', 'manager', true),
    (s, 'Test Staff', 'fc457-s-' || sfx || '@example.com', 'staff', true),
    (im, 'Test Inventory Manager', 'fc457-im-' || sfx || '@example.com', 'inventory_manager', true);
  insert into fx values ('o', o), ('m', m), ('s', s), ('im', im);
  perform pg_temp.as_user('o');
  insert into public.stores(name, code, country_code) values ('FC457 Store A ' || sfx, 'FC457A' || sfx, 'SG') returning id into st;
  perform pg_temp.putx('A', st);
  insert into public.user_store_assignments(user_id, store_id) values (s, st), (m, st), (im, st);
  insert into public.payment_methods(name, is_active) values ('FC457 Cash ' || sfx, true) returning id into cash;
  perform pg_temp.putx('cash', cash);
  for pr in select * from (values ('socks', 'Test Socks', 100::numeric), ('belt', 'Test Belt', 50), ('mat', 'Test Mat', 20)) y(k, n, p) loop
    insert into public.products(name, sku, product_type) values (pr.n, 'FC457-' || pr.k || '-' || sfx, 'own') returning id into v;
    perform pg_temp.putx(pr.k, v);
    insert into public.store_inventory(store_id, product_id, current_qty) values (st, v, 50);
    perform public.set_product_prices(st, v, pr.p, pr.p, 'available');
  end loop;
  insert into public.vouchers(name, code, voucher_kind, selling_price, qty_type, is_active)
    values ('Test Voucher', 'FC457V-' || sfx, 'normal', 40, 'limited', true) returning id into v;
  perform pg_temp.putx('vch', v);
  insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (v, st, 10);
  insert into public.voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 40, true);
  insert into public.therapy_services(service_code, name, standard_price, duration_minutes, is_active)
    values ('FC457-' || sfx, 'Test Session', 60, 30, true) returning id into v;
  perform pg_temp.putx('svc', v);
  insert into public.therapy_service_stores(service_id, store_id) values (v, st);
  insert into public.customers(full_name, phone) values ('Test Customer', ph[1]) returning id into cust;
  perform pg_temp.putx('cust', cust);
  insert into public.customers(full_name, phone) values ('Test Referrer', ph[2]) returning id into ref;
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at) values (ref, 'active', st, now()) returning id into v;
  perform pg_temp.putx('aff', v);
  insert into public.customers(full_name, phone) values ('Test Other Customer', ph[3]) returning id into v;
  perform pg_temp.putx('cust2', v);
end $$;

-- ═════ G The md5s, the grants, what 457 relies on ═════
-- correct_invoice: 457's AFTER, or 458's (the next step of this round, which builds on it).
select pg_temp.check((select md5 from pg_temp.fn_md5s() where fn = 'correct_invoice(uuid,jsonb,jsonb,text,uuid)')
        in ('45e7f523e50a6b423b6e1d9f8836ebb6', 'af9451fa15c2cf790edd70f799bae336')
    and (select md5 from pg_temp.fn_md5s() where fn = 'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)') = '1f034561a461bdb46a1e6274e0d04606',
  'G1 correct_invoice and update_invoice_internal have 457''s AFTER md5s (correct_invoice: or 458''s)');
select pg_temp.check(not has_function_privilege('anon', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)', 'execute')
    and not has_function_privilege('authenticated', 'public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)', 'execute')
    and has_function_privilege('service_role', 'public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)', 'execute'),
  'G2 correct_invoice: signed-in staff and the service role, never anon; update_invoice_internal: the service role''s alone');
-- preview_invoice_correction: as read, or 458's AFTER (458 changes it and runs after 457).
select pg_temp.check(coalesce((select md5 from pg_temp.fn_md5s() where fn = x.fn), 'missing') = any (string_to_array(x.ok, '|')),
  'G3 relied on and unchanged: ' || x.fn)
  from (values ('can_edit_invoice(uuid)', '22f496c486ee4f0dfd45c68da6240ac2'),
               ('staff_may_correct_invoice(uuid)', '60cbe4859f1f1f43da02115c019fc4bf'),
               ('lock_settled_invoice(uuid)', 'ccc7016ac73d9a13142980386a5929dc'),
               ('trg_lock_on_settle()', '39c6478cdaec553c2ab8ceaf55058960'),
               ('invoice_before_full_payment(uuid)', '532d7690367fc674737b20420e7fb16c'),
               ('preview_invoice_correction(uuid,jsonb)', '2bb7c0a5769050d5b2f9247a3aa05ecd|3047239c7418179e84927f6f00e7f2eb'),
               ('invoice_revision_retry(uuid,uuid,jsonb)', '5c33c50a8f6870d8a66f74b63b782f24'),
               ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
               ('create_invoice_with_details(uuid,uuid,jsonb,jsonb)', '770ee0129b0e9fe909259ad7ea95b8d0'),
               ('apply_line_foc(uuid,integer,uuid,text)', '5fbd0b6feb36e11dea6be231ffa0e952'),
               ('confirm_foc_invoice(uuid,text)', 'ba8b1ce2a5671989b927891f0cb7b1a2'),
               ('record_invoice_payment(uuid,jsonb,uuid)', '9c70097ed4da614fb9dcc66fdfcdb7d6'),
               ('deduct_invoice_stock(uuid,text)', '32183fe9e7c15ed0b11307c48289831a'),
               ('invoice_stock_to_deduct(uuid)', '6356494ccb8545d46c56b788f8f85f54'),
               ('invoice_record_payments_internal(uuid,jsonb)', '21890d84bcb0b9c00a2bc98aff313d0b'),
               ('trg_issue_sold_vouchers_on_paid()', 'c840d0d2754e7a8e889848ea8269a293'),
               ('cancel_invoice_recorded(uuid,text,uuid)', 'de52d9dbaef8ab15163bef35cb9d733d'),
               ('delete_invoice(uuid,text)', '530b8217e94c9bbb0765c47da2d8d40e'),
               ('set_product_prices(uuid,uuid,numeric,numeric,text)', 'aef4792013bc3a56f8ee62bc1a7d686a')) x(fn, ok);

-- ═════ F A completed FOC invoice ═════
do $$
declare inv uuid; e text; before jsonb; r jsonb; it record; sk uuid; vl uuid; th uuid;
begin
  perform pg_temp.as_user('o');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('cust'),
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('socks'), 'quantity', 2),
                      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('vch'), 'quantity', 1),
                      jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.fx('svc'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today(), 'affiliate_id', pg_temp.fx('aff')));
  perform pg_temp.putx('foc', inv);
  for it in select id from public.invoice_items where invoice_id = inv order by id loop
    perform public.apply_line_foc(it.id, null, null, 'Test giveaway'); end loop;
  perform public.confirm_foc_invoice(inv, null);
  perform pg_temp.check(pg_temp.st(inv) = 'completed_foc' and (select locked_at is not null and total_amount = 0 from public.invoices where id = inv)
      and pg_temp.shelf('socks') = 48 and pg_temp.vstock() = 9 and pg_temp.held(inv) = 1
      and jsonb_array_length(pg_temp.sessions(inv)) = 1 and pg_temp.earned(inv) = 0,
    'F0 fixture: completed FOC and locked; two pairs off the shelf, one voucher given from stock, one therapy session, no commission');
  sk := pg_temp.item(inv, 'socks'); vl := pg_temp.item(inv, 'vch'); th := pg_temp.item(inv, 'svc');
  perform pg_temp.putx('foc_sk', sk); perform pg_temp.putx('foc_vl', vl); perform pg_temp.putx('foc_th', th);

  -- Staff are refused (377: paid and part-paid only); Inventory Managers too.
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('print_note', 'Staff note'), 'Staff try');
  perform pg_temp.check(e = pg_temp.c377() and (select print_note from public.invoices where id = inv) is null,
    'F1 staff of the invoice''s store cannot correct a completed FOC invoice: ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('im');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('print_note', 'IM note'), 'IM try');
  perform pg_temp.check(e is not null and pg_temp.revs(inv) = 0, 'F2 nor can an Inventory Manager: ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('print_note', 'No reason'), ' ');
  perform pg_temp.check(e = 'A correction reason is required' and pg_temp.revs(inv) = 0,
    'F3 a Manager must give a reason: ' || coalesce(e, 'saved'));

  -- The Owner corrects the header: it stays completed FOC, nothing moves, audited.
  perform pg_temp.as_user('o');
  before := pg_temp.moved(inv);
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('print_note', 'Thank you, Test Customer', 'notes', 'Event giveaway, checked',
                                                                'expected_edit_count', pg_temp.edits(inv)), 'Note for the customer');
  perform pg_temp.check(e is null and pg_temp.moved(inv) = before
      and (select (print_note, notes) = ('Thank you, Test Customer', 'Event giveaway, checked') from public.invoices where id = inv)
      and pg_temp.revs(inv) = 1 and pg_temp.audits(inv) = 1
      and exists (select 1 from public.invoice_revisions where invoice_id = inv and edit_reason = 'Note for the customer' and edited_by = pg_temp.fx('o')),
    'F4 the Owner corrects the header of a completed FOC invoice: still completed FOC, no stock, voucher, session, commission or credit moved; one revision, one audit row: ' || coalesce(e, 'saved'));

  -- A Manager corrects the lines while it stays FOC: a third pair, two vouchers, all FOC.
  perform pg_temp.as_user('m');
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk, 3, 3), pg_temp.ln(vl, 2, 2), pg_temp.ln(th)),
                   jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'Gave a third pair and a second voucher');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'completed_foc' and (select total_amount from public.invoices where id = inv) = 0
      and pg_temp.shelf('socks') = 47 and pg_temp.vstock() = 9 and pg_temp.held(inv) = 1
      and jsonb_array_length(pg_temp.sessions(inv)) = 1 and pg_temp.earned(inv) = 0 and pg_temp.revs(inv) = 2,
    'F5 a Manager corrects the lines while it stays FOC: the third pair taken from the shelf; the voucher raised to two gives nothing more and keeps no more voucher stock (416): ' || coalesce(e, 'saved'));

  -- The Owner takes the FOC off: unpaid, still locked, no payment.
  perform pg_temp.as_user('o');
  before := pg_temp.sessions(inv);
  begin
    r := public.correct_invoice(inv, jsonb_build_array(pg_temp.ln(sk, 3, 0), pg_temp.ln(vl, 2, 0), pg_temp.ln(th, null, 0)),
                                jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'Not a giveaway after all', gen_random_uuid());
    e := null;
  exception when others then e := sqlerrm;
  end;
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'unpaid'
      and (select locked_at is not null and total_amount = 440 and paid_amount = 0 from public.invoices where id = inv)
      and not exists (select 1 from public.invoice_payments where invoice_id = inv)
      and pg_temp.shelf('socks') = 47 and pg_temp.vstock() = 10 and pg_temp.held(inv) = 0
      and r->'foc_vouchers' = '{"taken_back":["Test Voucher × 1"],"kept_used":[]}'::jsonb
      and exists (select 1 from public.audit_logs where record_id = inv and action = 'foc_removed_vouchers')
      and pg_temp.sessions(inv) = before and pg_temp.revs(inv) = 3,
    'F6 the Owner takes the FOC off: unpaid (S$440), still locked, no payment; the unused voucher taken back and its stock returned; the socks stay out; the session kept: ' || coalesce(e, r::text));
end $$;

-- ═════ X The dead end closed: the once-settled invoice, unpaid again ═════
do $$
declare inv uuid := pg_temp.fx('foc'); sk uuid := pg_temp.fx('foc_sk'); vl uuid := pg_temp.fx('foc_vl'); th uuid := pg_temp.fx('foc_th');
  e text; before jsonb; pv jsonb; sess jsonb;
begin
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('print_note', 'Staff note'), null);
  perform pg_temp.check(e = pg_temp.c377() and pg_temp.revs(inv) = 3,
    'X1 staff cannot correct the once-settled unpaid invoice (377''s words; before 457: You cannot edit this invoice): ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk, 2), pg_temp.ln(vl), pg_temp.ln(th)), '{}'::jsonb, null);
  perform pg_temp.check(e = 'A correction reason is required' and pg_temp.revs(inv) = 3,
    'X2 the Owner is asked for a reason, as on a paid invoice (before 457: You cannot edit this invoice, for everyone): ' || coalesce(e, 'saved'));
  -- The correction summary works and changes nothing.
  before := pg_temp.moved(inv);
  begin
    pv := public.preview_invoice_correction(inv, jsonb_build_object('items', jsonb_build_array(pg_temp.ln(sk, 2), pg_temp.ln(vl), pg_temp.ln(th)),
                                                                     'reason', 'One pair back', 'expected_edit_count', pg_temp.edits(inv)));
    e := null;
  exception when others then e := sqlerrm;
  end;
  perform pg_temp.check(e is null and (pv->'outcome'->>'total_after')::numeric = 340 and pv->'outcome'->>'status_after' = 'unpaid'
      and pg_temp.moved(inv) = before and pg_temp.revs(inv) = 3,
    'X3 the correction summary shows S$340, still unpaid, and changes nothing: ' || coalesce(e, (pv->'outcome')::text));
  -- With a reason: a pair back on the shelf, the printed note set; still unpaid and locked.
  sess := pg_temp.sessions(inv);
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk, 2), pg_temp.ln(vl), pg_temp.ln(th)),
                   jsonb_build_object('print_note', 'Two pairs, one voucher and a session', 'expected_edit_count', pg_temp.edits(inv)), 'One pair back');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'unpaid'
      and (select locked_at is not null and total_amount = 340 and paid_amount = 0 and print_note = 'Two pairs, one voucher and a session'
             from public.invoices where id = inv)
      and pg_temp.shelf('socks') = 48 and pg_temp.vstock() = 10 and pg_temp.held(inv) = 0 and pg_temp.vmoves(inv) = 0
      and exists (select 1 from public.invoice_voucher_movements where invoice_id = inv and quantity = -2
                    and reason = 'Not paid in full, nothing given yet (taken at payment): One pair back')
      and pg_temp.sessions(inv) = sess and pg_temp.earned(inv) = 0
      and pg_temp.revs(inv) = 4 and pg_temp.audits(inv) = 4
      and exists (select 1 from public.invoice_revisions where invoice_id = inv and edit_reason = 'One pair back'
                    and snapshot->'invoice'->>'status' = 'unpaid' and after_snapshot->'invoice'->>'total_amount' = '340.00'),
    'X4 with a reason the Owner corrects it again: S$340, still unpaid and locked, the note set; as on a settled invoice its product stock is put back and taken again (a pair back on the shelf, 48); no voucher stock kept before the payment (still 10, the units taken given back with a row); a revision and an audit row: ' || coalesce(e, pg_temp.state(inv)));
  -- And again, the header only (a Manager; the referrer cleared and set back).
  perform pg_temp.as_user('m');
  before := pg_temp.moved(inv);
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'Checked by the Manager', 'expected_edit_count', pg_temp.edits(inv)), 'Internal note');
  perform pg_temp.check(e is null and pg_temp.moved(inv) = before and (select notes from public.invoices where id = inv) = 'Checked by the Manager'
      and pg_temp.revs(inv) = 5,
    'X5 and again, the header only, by a Manager: nothing moves: ' || coalesce(e, 'saved'));
  -- Make FOC is still refused on it (not covered: FOC changes through Correct Invoice).
  perform pg_temp.as_user('o');
  e := pg_temp.err(format('select public.apply_line_foc(%L, null, null, %L)', sk, 'Test giveaway'));
  perform pg_temp.check(e = 'Invoice is locked', 'X6 Make FOC is still refused on it (the page no longer offers it): ' || coalesce(e, 'made FOC'));
end $$;

-- ═════ P Paid in full ═════
do $$
declare inv uuid := pg_temp.fx('foc'); e text; sess jsonb; credit bigint;
begin
  sess := pg_temp.sessions(inv);
  credit := (select count(*) from public.customer_credit_ledger);
  perform pg_temp.as_user('s');
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 340)), gen_random_uuid());
  perform pg_temp.check(pg_temp.st(inv) = 'paid' and (select paid_amount from public.invoices where id = inv) = 340,
    'P1 staff take the payment in full: paid');
  perform pg_temp.check(pg_temp.vstock() = 8 and pg_temp.held(inv) = 2
      and (select coalesce(sum(quantity), 0) from public.invoice_voucher_movements where invoice_id = inv) = 2,
    'P2 the two vouchers are given and their stock taken at the payment, once (10 -> 8, two units recorded out, two held): ' || pg_temp.state(inv));
  perform pg_temp.check(pg_temp.shelf('socks') = 48
      and (select coalesce(sum(case when movement_type::text = 'store_sale' then quantity else 0 end), 0) from public.stock_movements
            where invoice_id = inv and product_id = pg_temp.fx('socks'))
          - (select coalesce(sum(quantity), 0) from public.stock_movements
              where invoice_id = inv and product_id = pg_temp.fx('socks') and movement_type::text <> 'store_sale') = 2,
    'P3 the socks: two out, net, the shelf as before (48)');
  perform pg_temp.check(pg_temp.earned(inv) > 0
      and exists (select 1 from public.commissions where invoice_id = inv and referrer_customer_id = (select customer_id from public.customer_affiliates where id = pg_temp.fx('aff'))),
    'P4 the referrer''s commission is earned on payment: ' || pg_temp.earned(inv));
  perform pg_temp.check(pg_temp.sessions(inv) = sess and jsonb_array_length(sess) = 1
      and (select count(*) from public.customer_credit_ledger) = credit,
    'P5 the therapy session is the same one, unchanged; no credit moved');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('print_note', 'Paid, thank you', 'expected_edit_count', pg_temp.edits(inv)), 'Note after payment');
  perform pg_temp.check(e is null and (select print_note from public.invoices where id = inv) = 'Paid, thank you' and pg_temp.st(inv) = 'paid',
    'P6 now paid, staff of its store may correct it (377): ' || coalesce(e, 'saved'));
end $$;

-- ═════ V Voucher stock on a once-settled invoice not paid in full comes back whole ═════
-- Each starts from where the shelf and the voucher stock stand (s0, v0) and must end there.
do $$
declare inv uuid; s0 int := pg_temp.shelf('socks'); v0 int := pg_temp.vstock(); e text; sk uuid; vl uuid;
begin
  inv := pg_temp.foc_off();
  sk := pg_temp.item(inv, 'socks'); vl := pg_temp.item(inv, 'vch');
  perform pg_temp.check(pg_temp.st(inv) = 'unpaid' and (select locked_at is not null and total_amount = 140 from public.invoices where id = inv)
      and pg_temp.shelf('socks') = s0 - 1 and pg_temp.vstock() = v0 and pg_temp.held(inv) = 0 and pg_temp.vmoves(inv) = 0,
    'V0 fixture: socks and a voucher, FOC confirmed then taken off: unpaid (S$140) and locked; the socks out; the voucher taken back, its stock returned: ' || pg_temp.state(inv));
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk), pg_temp.ln(vl, 2)), jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'Two vouchers');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'unpaid' and (select total_amount from public.invoices where id = inv) = 180
      and pg_temp.shelf('socks') = s0 - 1 and pg_temp.vstock() = v0 and pg_temp.vmoves(inv) = 0 and pg_temp.held(inv) = 0,
    'V1 the Owner raises the voucher to two before payment: the socks still out; no voucher stock kept (the first 457: two units out, no voucher): ' || coalesce(e, pg_temp.state(inv)));
  perform pg_temp.as_user('o');
  perform public.cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  perform pg_temp.check(pg_temp.st(inv) = 'cancelled' and pg_temp.shelf('socks') = s0 and pg_temp.vstock() = v0 and pg_temp.held(inv) = 0,
    'V2 then cancelled before payment: the socks back on the shelf, the voucher stock where it started (the first 457: one unit short): ' || pg_temp.state(inv));
end $$;

do $$
declare inv uuid; s0 int := pg_temp.shelf('socks'); v0 int := pg_temp.vstock(); e text;
begin
  inv := pg_temp.foc_off();
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(pg_temp.item(inv, 'vch'))), jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'The socks were not taken');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'unpaid' and (select total_amount from public.invoices where id = inv) = 40
      and pg_temp.shelf('socks') = s0 and pg_temp.vstock() = v0 and pg_temp.vmoves(inv) = 0
      and not exists (select 1 from public.invoice_goods_out(inv)),
    'V3 the Owner removes the socks line: the pair back on the shelf; no voucher stock kept (the first 457: one unit out, no voucher): ' || coalesce(e, pg_temp.state(inv)));
  perform pg_temp.as_user('s');
  e := pg_temp.err(format('select public.delete_invoice(%L, %L)', inv, 'Made by mistake'));
  perform pg_temp.check(e is null and (select deleted_at is not null from public.invoices where id = inv)
      and pg_temp.shelf('socks') = s0 and pg_temp.vstock() = v0,
    'V4 then staff delete it (unpaid, no payment, nothing out: 417''s rule): the voucher stock where it started (the first 457: one unit lost for good): ' || coalesce(e, pg_temp.state(inv)));
end $$;

do $$
declare inv uuid; s0 int := pg_temp.shelf('socks'); v0 int := pg_temp.vstock(); e text; e2 text; sk uuid; vl uuid;
begin
  inv := pg_temp.foc_off();
  sk := pg_temp.item(inv, 'socks'); vl := pg_temp.item(inv, 'vch');
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk), pg_temp.ln(vl, 2)), jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'Two vouchers');
  e2 := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk), pg_temp.ln(vl, 1)), jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'One voucher after all');
  perform pg_temp.check(e is null and e2 is null and (select total_amount from public.invoices where id = inv) = 140
      and pg_temp.vstock() = v0 and pg_temp.vmoves(inv) = 0,
    'V5 raised to two, then lowered to one, before payment: no voucher stock kept (the first 457: two units out): ' || coalesce(e, e2, pg_temp.state(inv)));
  perform pg_temp.as_user('s');
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 140)), gen_random_uuid());
  perform pg_temp.check(pg_temp.st(inv) = 'paid' and pg_temp.vstock() = v0 - 1 and pg_temp.held(inv) = 1 and pg_temp.vmoves(inv) = 1
      and pg_temp.shelf('socks') = s0 - 1,
    'V6 then paid in full: one voucher given, one unit taken (the first 457: two units out, one voucher): ' || pg_temp.state(inv));
  perform pg_temp.as_user('o');
  perform public.cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  perform pg_temp.check(pg_temp.st(inv) = 'cancelled' and pg_temp.vstock() = v0 and pg_temp.shelf('socks') = s0 and pg_temp.held(inv) = 0,
    'V7 then cancelled: the voucher and the socks back, the stock where it started: ' || pg_temp.state(inv));
end $$;

do $$
declare inv uuid; s0 int := pg_temp.shelf('socks'); v0 int := pg_temp.vstock(); e text; it record; sk uuid; vl uuid;
begin
  perform pg_temp.as_user('o');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('cust'),
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('socks'), 'quantity', 1),
                      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('vch'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()));
  for it in select id from public.invoice_items where invoice_id = inv order by id loop
    perform public.apply_line_foc(it.id, null, null, 'Test giveaway'); end loop;
  perform public.confirm_foc_invoice(inv, null);
  sk := pg_temp.item(inv, 'socks'); vl := pg_temp.item(inv, 'vch');
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk, null, 0), pg_temp.ln(vl, 2, 0)), jsonb_build_object('expected_edit_count', pg_temp.edits(inv)),
                   'Not a giveaway; two vouchers');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'unpaid' and (select total_amount from public.invoices where id = inv) = 180
      and pg_temp.shelf('socks') = s0 - 1 and pg_temp.vstock() = v0 and pg_temp.vmoves(inv) = 0 and pg_temp.held(inv) = 0,
    'V8 the FOC taken off and the voucher raised to two in one save: the voucher taken back, no voucher stock kept (before this file too: one unit out, no voucher): ' || coalesce(e, pg_temp.state(inv)));
  perform public.cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  perform pg_temp.check(pg_temp.st(inv) = 'cancelled' and pg_temp.shelf('socks') = s0 and pg_temp.vstock() = v0,
    'V9 then cancelled: the stock where it started (before this file too: one unit short): ' || pg_temp.state(inv));
end $$;

do $$
declare inv uuid; s0 int := pg_temp.shelf('socks'); v0 int := pg_temp.vstock(); e text; sk uuid; vl uuid;
begin
  inv := pg_temp.foc_off();
  sk := pg_temp.item(inv, 'socks'); vl := pg_temp.item(inv, 'vch');
  perform pg_temp.as_user('s');
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 50)), gen_random_uuid());
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk), pg_temp.ln(vl, 2)), jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'Two vouchers');
  perform pg_temp.check(e is null and pg_temp.st(inv) = 'partially_paid' and (select total_amount from public.invoices where id = inv) = 180
      and pg_temp.vstock() = v0 and pg_temp.vmoves(inv) = 0 and pg_temp.held(inv) = 0,
    'V10 part paid after the FOC came off, then the voucher raised to two: no voucher stock kept before full payment (before this file too: two units out): ' || coalesce(e, pg_temp.state(inv)));
  perform public.cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  perform pg_temp.check(pg_temp.st(inv) = 'cancelled' and pg_temp.shelf('socks') = s0 and pg_temp.vstock() = v0,
    'V11 then cancelled: the stock where it started (before this file too: one unit short): ' || pg_temp.state(inv));
end $$;

select pg_temp.check(exists (select 1 from public.invoice_voucher_movements where invoice_id = pg_temp.fx('foc') and quantity = -1
                               and reason = 'Still FOC, nothing given for the change: Gave a third pair and a second voucher'),
  'V12 a save that stays FOC gives its unit back with 416''s wording, as before');

-- ═════ E A never-settled unpaid invoice: an ordinary edit, as before ═════
do $$
declare inv uuid; e text;
begin
  perform pg_temp.as_user('s');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('cust'),
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('mat'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()));
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(pg_temp.item(inv, 'mat'), 2)), jsonb_build_object('expected_edit_count', 0), null);
  perform pg_temp.check(e is null and (select total_amount from public.invoices where id = inv) = 40 and pg_temp.st(inv) = 'unpaid'
      and (select locked_at from public.invoices where id = inv) is null and pg_temp.revs(inv) = 1,
    'E1 staff edit an unpaid invoice never settled without a reason (as before): ' || coalesce(e, 'saved'));
end $$;

-- ═════ R Plain words instead of the database's ═════
do $$
declare inv uuid; e text; pay uuid; sk uuid; bl uuid; before jsonb;
begin
  -- A paid invoice refunded in full; its belt line also carries a refund row naming it, as the older
  -- line refund (55) wrote them (production keeps such rows; today's refunds name the payment).
  perform pg_temp.as_user('o');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('cust'),
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('socks'), 'quantity', 1),
                      jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('belt'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()));
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 150)), gen_random_uuid());
  sk := pg_temp.item(inv, 'socks'); bl := pg_temp.item(inv, 'belt');
  select id into pay from public.invoice_payments where invoice_id = inv;
  perform public.refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', sk, 'amount', 100), jsonb_build_object('invoice_item_id', bl, 'amount', 50)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 150)),
    (select jsonb_agg(jsonb_build_object('movement_id', id, 'not_returned_quantity', quantity)) from public.stock_movements
      where invoice_id = inv and movement_type::text = 'store_sale'), 'Refunded in full', gen_random_uuid());
  insert into public.invoice_refunds(invoice_id, invoice_item_id, amount, reason, kind, return_stock, refunded_by)
    values (inv, bl, 0, 'Test line refund (older path)', 'product', false, pg_temp.fx('o'));
  perform pg_temp.check(pg_temp.st(inv) = 'refunded', 'R1 fixture: refunded in full, the belt line named by a refund row');
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk)), jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'Remove the belt');
  perform pg_temp.check(e = 'A line you removed has a refund recorded against it, so it stays on the invoice. Keep the line.'
      and exists (select 1 from public.invoice_items where id = bl),
    'R2 removing a line a refund is recorded against is refused in words (before 457: the database''s foreign-key error): ' || coalesce(e, 'saved'));
  before := pg_temp.moved(inv);
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('print_note', 'Refunded in full', 'expected_edit_count', pg_temp.edits(inv)), 'Note on the refund');
  perform pg_temp.check(e is null and pg_temp.moved(inv) = before and pg_temp.st(inv) = 'refunded'
      and (select print_note from public.invoices where id = inv) = 'Refunded in full',
    'R3 the header of the refunded invoice still corrects (Owners and Managers): status kept, nothing moves: ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('print_note', 'Staff'), 'Staff try');
  perform pg_temp.check(e = pg_temp.c377(), 'R4 staff cannot (as before): ' || coalesce(e, 'saved'));
end $$;

do $$
declare inv uuid; e text; sk uuid; mt uuid; before jsonb; wallet uuid;
begin
  -- Paid with the customer's own Bonus credit: the lines carry the credit's allocations.
  perform pg_temp.as_user('o');
  perform public.adjust_customer_credit(pg_temp.fx('cust2'), 'bonus', 'increase', 200, 'Test credit', 'FC457-ADJ', null, null, pg_temp.fx('A'), gen_random_uuid());
  select id into wallet from public.payment_methods where name = 'Wallet — Bonus Credit' and deleted_at is null;
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('cust2'),
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('socks'), 'quantity', 1),
                      jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('mat'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()));
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', wallet, 'amount', 120)), gen_random_uuid());
  sk := pg_temp.item(inv, 'socks'); mt := pg_temp.item(inv, 'mat');
  perform pg_temp.check(pg_temp.st(inv) = 'paid' and exists (select 1 from public.invoice_line_credit_allocations where invoice_item_id = mt),
    'R5 fixture: paid with the customer''s credit, allocated to its lines');
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk)), jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'Remove the mat');
  perform pg_temp.check(e = 'A line you removed was paid with the customer''s credit, which is recorded against it, so it stays on the invoice. Keep the line; to give the credit back, refund it.'
      and exists (select 1 from public.invoice_items where id = mt),
    'R6 removing a line paid with the customer''s credit is refused in words (before 457: the database''s foreign-key error): ' || coalesce(e, 'saved'));
  perform public.cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  perform pg_temp.check(pg_temp.st(inv) = 'cancelled', 'R7 fixture: cancelled');
  e := pg_temp.try(inv, jsonb_build_array(pg_temp.ln(sk)), jsonb_build_object('expected_edit_count', pg_temp.edits(inv)), 'Remove the mat');
  perform pg_temp.check(e = 'A line you removed was paid with the customer''s credit, which is recorded against it, so it stays on the invoice. Keep the line; to give the credit back, refund it.',
    'R8 and once the invoice is cancelled: ' || coalesce(e, 'saved'));
  before := pg_temp.moved(inv);
  e := pg_temp.try(inv, pg_temp.lines(inv), jsonb_build_object('notes', 'Cancelled at the counter', 'expected_edit_count', pg_temp.edits(inv)), 'Note on the cancellation');
  perform pg_temp.check(e is null and pg_temp.moved(inv) = before and pg_temp.st(inv) = 'cancelled',
    'R9 the header of the cancelled invoice still corrects: status kept, nothing moves: ' || coalesce(e, 'saved'));
end $$;

-- ═════ Y An exchange's replacement invoice, its top-up unpaid ═════
do $$
declare orig uuid; res jsonb; ex uuid; ei uuid; e text; before jsonb;
begin
  perform pg_temp.as_user('o');
  orig := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('cust'),
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('belt'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()));
  perform public.record_invoice_payment(orig, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 50)), gen_random_uuid());
  -- The belt (S$50) for a pair of socks (S$100): S$50 to pay, not taken yet.
  res := public.create_exchange_with_details('items', jsonb_build_object('original_invoice_id', orig, 'processing_store_id', pg_temp.fx('A'),
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.item(orig, 'belt'), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('socks'), 'quantity', 1)),
    'payments', '[]'::jsonb, 'reason', 'Wrong size', 'served_by', jsonb_build_array(pg_temp.fx('o')::text)));
  set constraints public.exchange_creates_invoice immediate;
  set constraints public.exchange_creates_invoice deferred;
  ex := (res->>'id')::uuid;
  select id into ei from public.invoices where exchange_id = ex and is_exchange;
  perform pg_temp.check(ei is not null and pg_temp.st(ei) = 'unpaid' and (select locked_at is not null from public.invoices where id = ei)
      and not exists (select 1 from public.invoice_payments where invoice_id = ei),
    'Y0 fixture: the replacement invoice is unpaid, locked, with no payment: ' || coalesce(pg_temp.st(ei), 'none'));
  before := pg_temp.moved(ei);
  e := pg_temp.try(ei, pg_temp.lines(ei), jsonb_build_object('print_note', 'Exchanged for the right size', 'expected_edit_count', pg_temp.edits(ei)), 'Note for the customer');
  perform pg_temp.check(e is null and pg_temp.moved(ei) = before and (select print_note from public.invoices where id = ei) = 'Exchanged for the right size'
      and pg_temp.revs(ei) = 1,
    'Y1 the Owner corrects its header with a reason (before 457: You cannot edit this invoice): ' || coalesce(e, 'saved'));
  e := pg_temp.try(ei, jsonb_build_array(pg_temp.ln((select id from public.invoice_items where invoice_id = ei order by id limit 1), 2)),
                   jsonb_build_object('expected_edit_count', pg_temp.edits(ei)), 'Two pairs');
  perform pg_temp.check(e = 'An exchange invoice is system-generated and cannot be edited',
    'Y2 its lines stay as the exchange made them: ' || coalesce(e, 'saved'));
  perform pg_temp.as_user('s');
  e := pg_temp.try(ei, pg_temp.lines(ei), jsonb_build_object('print_note', 'Staff'), 'Staff try');
  perform pg_temp.check(e = pg_temp.c377(), 'Y3 staff cannot correct it: ' || coalesce(e, 'saved'));
end $$;

-- A refund top-up invoice (is_topup): unpaid, no payment, never locked.
do $$
declare orig uuid; ti uuid; e text; before jsonb;
begin
  perform pg_temp.as_user('o');
  orig := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('cust'),
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('mat'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()));
  ti := public.create_topup_invoice(orig, 15, 'Test top-up');
  perform pg_temp.check(ti is not null and pg_temp.st(ti) = 'unpaid' and (select is_topup and locked_at is null from public.invoices where id = ti),
    'Y4 fixture: a refund top-up invoice, unpaid, no payment, not locked');
  before := pg_temp.moved(ti);
  e := pg_temp.try(ti, pg_temp.lines(ti), jsonb_build_object('print_note', 'Top-up for the refund', 'expected_edit_count', pg_temp.edits(ti)), 'Note for the customer');
  perform pg_temp.check(e is null and pg_temp.moved(ti) = before and (select print_note from public.invoices where id = ti) = 'Top-up for the refund',
    'Y5 the Owner corrects its header with a reason (before 457: You cannot edit this invoice): ' || coalesce(e, 'saved'));
  e := pg_temp.try(ti, jsonb_set(pg_temp.lines(ti), '{0,quantity}', '2'), jsonb_build_object('expected_edit_count', pg_temp.edits(ti)), 'Two');
  perform pg_temp.check(e = 'A refund top-up invoice is system-generated and cannot be edited',
    'Y6 its line stays as it was made: ' || coalesce(e, 'saved'));
  e := pg_temp.try(ti, pg_temp.lines(ti), jsonb_build_object('print_note', 'No reason'), null);
  perform pg_temp.check(e = 'A correction reason is required', 'Y7 and a reason is asked for: ' || coalesce(e, 'saved'));
end $$;

-- ═════ M 457 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m457 m left join pg_temp.fn_md5s() f on f.fn = m.fn where f.fn is null or f.md5 <> m.md5)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m457),
  'M1 running 457 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m457 m left join b457 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5)
                     = array['correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)']
    and (select count(*) from m457) = (select count(*) from b457),
  'M2 its first run changed correct_invoice and update_invoice_internal alone (no function added or dropped)');
select pg_temp.check((select before = after1 from r457),
  'M3 457''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 457 checks passed.';
end $$;
rollback;
