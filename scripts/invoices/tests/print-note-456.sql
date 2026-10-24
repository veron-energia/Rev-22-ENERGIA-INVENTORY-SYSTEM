-- The note printed on the invoice, apart from its internal Notes (456).
--
-- The Owner's answers, 22 Oct 2026 (item 6, the invoice half): a NEW field "Note printed on the invoice"
-- (up to 500 characters), separate from Notes, which becomes "Internal notes (not printed)" and never
-- prints. It is entered at create and at edit; on a paid invoice it changes through Correct Invoice (a
-- reason, the revision history, the audit log) like any other change, no new shortcut.
--
--   G  The column (text, nullable, no default, at most 500 characters), the two AFTER md5s, their grants
--      (signed-in staff and the service role, never anon), the functions 456 relies on unchanged.
--   C  New Invoice (create_invoice_with_details): the note is stored apart from Notes, less the spaces and
--      line breaks around it (the ones inside kept); blank or absent is none; 500 characters taken, 501
--      refused in words (and by the column's check); the same request again returns its invoice, the same
--      request id with another note is refused (416).
--   E  Edit Invoice on an unpaid invoice (no payment): staff set, change and clear the note without a
--      reason; each save is a revision and an audit row; a line and the note changed in one save both
--      save (the lines through update_invoice_internal, which leaves the note).
--   P  Correct Invoice on a paid invoice: refused without a reason; with one, the Owner changes the note
--      alone: the internal note, the lines, total, paid amount and status, stock, commission, payments and
--      credit as they were; one revision and one 'invoice_corrected' audit row hold the old and the new
--      note; staff of the invoice's store may (their name on the revision and the audit row); staff are
--      refused while a refund request waits, and staff of another store; a header without print_note (an
--      older page, update_invoice) keeps it, and so does a Notes-only correction; 501 characters refused;
--      the correction summary (preview_invoice_correction) takes a note-only change and leaves the
--      invoice as it was.
--   M  456 twice changes nothing; its first run changes only the two functions (no function added or
--      dropped); its self-test leaves no row (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (@example.com); phones are ACMA's fictional range (+61 2 5550 ....). It installs 456 twice (run with
-- -v skip_install=1 where 456 is already installed, and always once 457 is: 456's installer then refuses,
-- as it should, since 457 changed a function 456 pins). Every check runs, then the file fails if any did.
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
create temp table b456 as select * from pg_temp.fn_md5s();
create temp table r456 as select pg_temp.row_counts() as before;
\ir ../../../supabase/456_invoice_printed_note.sql
create temp table m456 as select * from pg_temp.fn_md5s();
alter table r456 add column after1 jsonb;
update r456 set after1 = pg_temp.row_counts();
\ir ../../../supabase/456_invoice_printed_note.sql
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
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true),
          set_config('request.jwt.claim.role', 'authenticated', true) $$;
-- The invoice's lines as the correction form sends them back: each saved line with its id and saved price.
create function pg_temp.lines(inv uuid) returns jsonb language sql as
$$ select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text,
     'product_id', product_id, 'quantity', quantity, 'unit_price', unit_price)) order by id)
     from public.invoice_items where invoice_id = inv $$;
-- A correction as the page saves it; null when it was saved, else the refusal (which undoes all it did).
create function pg_temp.try(inv uuid, hdr jsonb, reason text) returns text language plpgsql as
$$begin perform public.correct_invoice(inv, pg_temp.lines(inv), hdr, reason, gen_random_uuid()); return null;
exception when others then return sqlerrm; end$$;
-- New Invoice as the page sends it (one pair of socks at the store), by whoever is signed in.
create function pg_temp.make(st text, hdr jsonb) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx(st), pg_temp.fx('cust'),
     jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('prod'), 'quantity', 1)),
     jsonb_build_object('business_date', public.sg_today()) || hdr) $$;
create function pg_temp.make_err(st text, hdr jsonb) returns text language plpgsql as
$$begin perform pg_temp.make(st, hdr); return null; exception when others then return sqlerrm; end$$;
create function pg_temp.pn(inv uuid) returns text language sql as $$ select print_note from public.invoices where id = inv $$;
-- What a note-only change must leave as it was: the invoice's money, lines, payments, stock,
-- commission and credit.
create function pg_temp.money_and_stock(inv uuid) returns jsonb language sql as
$$ select jsonb_build_object(
     'invoice', (select jsonb_build_object('notes', notes, 'status', status, 'subtotal', subtotal, 'discount_total', discount_total,
                   'total', total_amount, 'paid', paid_amount, 'customer', customer_id, 'store', store_id, 'affiliate', affiliate_id,
                   'business_date', business_date) from public.invoices where id = inv),
     'items', (select jsonb_agg(jsonb_build_object('id', id, 'qty', quantity, 'unit', unit_price, 'total', line_total) order by id)
                 from public.invoice_items where invoice_id = inv),
     'payments', (select jsonb_agg(jsonb_build_object('id', id, 'amount', amount, 'kind', entry_kind) order by id)
                    from public.invoice_payments where invoice_id = inv),
     'stock', (select jsonb_agg(jsonb_build_object('id', id, 'type', movement_type, 'qty', quantity) order by id)
                 from public.stock_movements where invoice_id = inv),
     'shelf', (select current_qty from public.store_inventory where store_id = pg_temp.fx('A') and product_id = pg_temp.fx('prod')),
     'commissions', (select jsonb_agg(to_jsonb(c) - 'updated_at' order by c.id) from public.commissions c where c.invoice_id = inv),
     'credit', (select count(*) from public.customer_credit_ledger)) $$;
create function pg_temp.revs(inv uuid) returns int language sql as $$ select count(*)::int from public.invoice_revisions where invoice_id = inv $$;
create function pg_temp.audits(inv uuid) returns int language sql as
$$ select count(*)::int from public.audit_logs where table_name = 'invoices' and record_id = inv and action = 'invoice_corrected' $$;
create function pg_temp.edits(inv uuid) returns int language sql as $$ select coalesce(edit_count, 0) from public.invoices where id = inv $$;

-- ═════ Fixtures (invented) ═════
insert into public.app_settings(id) values (true) on conflict do nothing;
do $$
declare o uuid := gen_random_uuid(); s uuid := gen_random_uuid(); s2 uuid := gen_random_uuid();
  sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  st_a uuid; st_b uuid; cash uuid; prod uuid; cust uuid; ref uuid; aff uuid; ph text[];
begin
  select array_agg(x order by x) into ph
    from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(4560, 4699) g) y
   where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = y.x);
  insert into auth.users(id, email) values (o, 'pn456-o-' || sfx || '@example.com'), (s, 'pn456-s-' || sfx || '@example.com'),
                                           (s2, 'pn456-s2-' || sfx || '@example.com');
  insert into public.profiles(id, full_name, email, role, is_active) values
    (o, 'Test Owner', 'pn456-o-' || sfx || '@example.com', 'owner', true),
    (s, 'Test Staff', 'pn456-s-' || sfx || '@example.com', 'staff', true),
    (s2, 'Test Other Staff', 'pn456-s2-' || sfx || '@example.com', 'staff', true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into public.stores(name, code, country_code) values ('PN456 Store A ' || sfx, 'PN456A' || sfx, 'SG') returning id into st_a;
  insert into public.stores(name, code, country_code) values ('PN456 Store B ' || sfx, 'PN456B' || sfx, 'SG') returning id into st_b;
  insert into public.user_store_assignments(user_id, store_id) values (s, st_a), (s2, st_b);
  insert into public.payment_methods(name, is_active) values ('PN456 Cash ' || sfx, true) returning id into cash;
  insert into public.products(name, sku, product_type) values ('Test Socks', 'PN456-' || sfx, 'own') returning id into prod;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st_a, prod, 50), (st_b, prod, 50);
  perform public.set_product_prices(st_a, prod, 100, 100, 'available');
  perform public.set_product_prices(st_b, prod, 100, 100, 'available');
  insert into public.customers(full_name, phone) values ('Test Customer', ph[1]) returning id into cust;
  insert into public.customers(full_name, phone) values ('Test Referrer', ph[2]) returning id into ref;
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at) values (ref, 'active', st_a, now()) returning id into aff;
  insert into fx values ('o', o), ('s', s), ('s2', s2), ('A', st_a), ('B', st_b), ('cash', cash), ('prod', prod),
                        ('cust', cust), ('ref', ref), ('aff', aff);
end $$;

-- ═════ G The column, the md5s, the grants ═════
select pg_temp.check(
    (select format_type(a.atttypid, a.atttypmod) = 'text' and not a.attnotnull and not a.atthasdef
       from pg_attribute a where a.attrelid = 'public.invoices'::regclass and a.attname = 'print_note' and not a.attisdropped)
    and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.invoices'::regclass
          and c.conname = 'invoices_print_note_length') = 'CHECK (((print_note IS NULL) OR (char_length(print_note) <= 500)))'
    and has_column_privilege('authenticated', 'public.invoices', 'print_note', 'select'),
  'G1 invoices.print_note: text, nullable, no default, at most 500 characters, read like every other column');
-- correct_invoice: 456's AFTER, or 457's or 458's (the next steps of this round, which build on it), or 464's.
-- create_invoice_with_details: 456's AFTER, or 463's (after 462: it refuses a removed customer record).
select pg_temp.check((select md5 from pg_temp.fn_md5s() where fn = 'create_invoice_with_details(uuid,uuid,jsonb,jsonb)') in ('770ee0129b0e9fe909259ad7ea95b8d0', '0ac29c7aa909dd756ec572645ca86448')
    and (select md5 from pg_temp.fn_md5s() where fn = 'correct_invoice(uuid,jsonb,jsonb,text,uuid)')
        in ('e174a2fde4ad5bb158e6f306b0b944e5', '45e7f523e50a6b423b6e1d9f8836ebb6', 'af9451fa15c2cf790edd70f799bae336', '04d647e13e9424a9375942e5812e91a2'),
  'G2 create_invoice_with_details and correct_invoice have 456''s AFTER md5s (correct_invoice: or 457''s or 458''s or 464''s)');
select pg_temp.check(not has_function_privilege('anon', 'public.' || f, 'execute')
    and has_function_privilege('authenticated', 'public.' || f, 'execute')
    and has_function_privilege('service_role', 'public.' || f, 'execute'),
  'G3 ' || f || ': signed-in staff and the service role may call it, anon may not')
  from unnest(array['create_invoice_with_details(uuid,uuid,jsonb,jsonb)', 'correct_invoice(uuid,jsonb,jsonb,text,uuid)']) f;
-- update_invoice_internal: as at 416, or 457's AFTER (457 changes it and runs after 456);
-- preview_invoice_correction: as read, or 458's AFTER (458 changes it and runs after 457), or 463's.
select pg_temp.check(coalesce((select md5 from pg_temp.fn_md5s() where fn = x.fn), 'missing') = any (string_to_array(x.ok, '|')),
  'G4 relied on and unchanged: ' || x.fn)
  from (values ('create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)', '80c80d386a5241e63b353e35e13ef250'),
               ('update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)', '8e674fe0d5e35ed5c2e93d417f14c05a|1f034561a461bdb46a1e6274e0d04606'),
               ('preview_invoice_correction(uuid,jsonb)', '2bb7c0a5769050d5b2f9247a3aa05ecd|3047239c7418179e84927f6f00e7f2eb|f26752231c100461e11caddc03c98a33'),
               ('record_invoice_payment(uuid,jsonb,uuid)', '9c70097ed4da614fb9dcc66fdfcdb7d6'),
               ('staff_may_correct_invoice(uuid)', '60cbe4859f1f1f43da02115c019fc4bf'),
               ('can_edit_invoice(uuid)', '22f496c486ee4f0dfd45c68da6240ac2'),
               ('invoice_revision_retry(uuid,uuid,jsonb)', '5c33c50a8f6870d8a66f74b63b782f24'),
               ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855')) x(fn, ok);

-- ═════ C New Invoice ═════
do $$
declare inv uuid; inv2 uuid; e text; req uuid := gen_random_uuid();
begin
  perform pg_temp.as_user('s');
  inv := pg_temp.make('A', jsonb_build_object('notes', 'Website order cs_test_fixture (internal)',
                                              'print_note', E'  \n\tThank you, Test Customer.\n\nSee you on Monday.  \n '));
  perform pg_temp.check((select (print_note, notes) = (E'Thank you, Test Customer.\n\nSee you on Monday.', 'Website order cs_test_fixture (internal)')
                           from public.invoices where id = inv),
    'C1 staff make an invoice with a printed note: stored apart from the internal note, without the spaces and line breaks around it, the ones inside kept');
  inv := pg_temp.make('A', jsonb_build_object('print_note', E' \n\t '));
  inv2 := pg_temp.make('A', '{}'::jsonb);
  perform pg_temp.check(pg_temp.pn(inv) is null and pg_temp.pn(inv2) is null
      and (select notes from public.invoices where id = inv2) is null,
    'C2 a blank note, or none sent, is none');
  inv := pg_temp.make('A', jsonb_build_object('print_note', repeat('n', 499) || 'é'));
  e := pg_temp.make_err('A', jsonb_build_object('print_note', repeat('n', 500) || 'é'));
  perform pg_temp.check(char_length(pg_temp.pn(inv)) = 500
      and e = 'PRINT_NOTE_TOO_LONG: The note printed on the invoice can be at most 500 characters.',
    'C3 500 characters are taken (counted as characters), 501 refused in words: ' || coalesce(e, 'made'));
  begin
    update public.invoices set print_note = repeat('z', 501) where id = inv;
    e := null;
  exception when check_violation then e := sqlerrm;
  end;
  perform pg_temp.check(e like '%invoices_print_note_length%' and char_length(pg_temp.pn(inv)) = 500,
    'C4 and the column itself holds no more than 500: ' || coalesce(e, 'stored'));
  perform pg_temp.as_user('s');
  inv := pg_temp.make('A', jsonb_build_object('request_id', req, 'print_note', 'First note'));
  inv2 := pg_temp.make('A', jsonb_build_object('request_id', req, 'print_note', 'First note'));
  e := pg_temp.make_err('A', jsonb_build_object('request_id', req, 'print_note', 'Another note'));
  perform pg_temp.check(inv = inv2 and pg_temp.pn(inv) = 'First note'
      and e like 'This form already made %. Open that invoice to change it, instead of creating another.',
    'C5 the same request again returns its invoice; the same request id with another note is refused (416): ' || coalesce(e, 'made'));
end $$;

-- ═════ E Edit Invoice on an unpaid invoice ═════
do $$
declare inv uuid; e text;
begin
  perform pg_temp.as_user('s');
  inv := pg_temp.make('A', jsonb_build_object('notes', 'Internal only'));
  e := pg_temp.try(inv, jsonb_build_object('print_note', 'Collect on Friday', 'notes', 'Internal only', 'expected_edit_count', 0), null);
  perform pg_temp.check(e is null and pg_temp.pn(inv) = 'Collect on Friday' and (select notes from public.invoices where id = inv) = 'Internal only'
      and (select status::text from public.invoices where id = inv) = 'unpaid'
      and pg_temp.edits(inv) = 1 and pg_temp.revs(inv) = 1 and pg_temp.audits(inv) = 1,
    'E1 staff add a note to an unpaid invoice without a reason: one revision, one audit row: ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, jsonb_build_object('print_note', 'Collect on Saturday'), null);
  perform pg_temp.check(e is null and pg_temp.pn(inv) = 'Collect on Saturday' and pg_temp.edits(inv) = 2,
    'E2 and change it: ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, jsonb_build_object('print_note', ''), null);
  perform pg_temp.check(e is null and pg_temp.pn(inv) is null and pg_temp.edits(inv) = 3
      and (select notes from public.invoices where id = inv) = 'Internal only',
    'E3 and clear it (the internal note stays): ' || coalesce(e, 'saved'));
  -- A line and the note changed in one save: the lines go through update_invoice_internal, which sets
  -- named columns and so leaves the note correct_invoice wrote.
  begin
    perform public.correct_invoice(inv, jsonb_set(pg_temp.lines(inv), '{0,quantity}', '2'),
                                   jsonb_build_object('print_note', 'Two pairs, collect on Friday'), null, gen_random_uuid());
    e := null;
  exception when others then e := sqlerrm;
  end;
  perform pg_temp.check(e is null and pg_temp.pn(inv) = 'Two pairs, collect on Friday'
      and (select sum(quantity) from public.invoice_items where invoice_id = inv) = 2
      and (select total_amount from public.invoices where id = inv) = 200
      and (select notes from public.invoices where id = inv) = 'Internal only' and pg_temp.edits(inv) = 4,
    'E4 a line and the note changed in one save: both saved, the internal note kept: ' || coalesce(e, 'saved'));
end $$;

-- ═════ P Correct Invoice on a paid invoice ═════
do $$
declare inv uuid; e text; before jsonb; after jsonb; rv record; au record;
begin
  perform pg_temp.as_user('o');
  inv := pg_temp.make('A', jsonb_build_object('notes', 'Internal only', 'affiliate_id', pg_temp.fx('aff'),
                                              'print_note', 'Two-year warranty on the socks'));
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 100)));
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'paid'
      and exists (select 1 from public.stock_movements where invoice_id = inv)
      and exists (select 1 from public.commissions where invoice_id = inv),
    'P0 fixture: paid, the socks out of stock, a commission earned');
  before := pg_temp.money_and_stock(inv);
  e := pg_temp.try(inv, jsonb_build_object('print_note', 'Three-year warranty on the socks'), ' ');
  perform pg_temp.check(e = 'A correction reason is required' and pg_temp.pn(inv) = 'Two-year warranty on the socks' and pg_temp.edits(inv) = 0,
    'P1 a note change on a paid invoice needs a reason: ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, jsonb_build_object('print_note', 'Three-year warranty on the socks', 'expected_edit_count', 0), 'Owner asked for the warranty');
  after := pg_temp.money_and_stock(inv);
  perform pg_temp.check(e is null and pg_temp.pn(inv) = 'Three-year warranty on the socks' and after = before
      and pg_temp.edits(inv) = 1 and (select edited_by from public.invoices where id = inv) = pg_temp.fx('o'),
    'P2 with a reason the Owner changes the note alone: notes, lines, money, payments, stock, commission and credit as they were: ' || coalesce(e, 'saved'));
  select * into rv from public.invoice_revisions where invoice_id = inv;
  select * into au from public.audit_logs where table_name = 'invoices' and record_id = inv and action = 'invoice_corrected';
  perform pg_temp.check(pg_temp.revs(inv) = 1 and pg_temp.audits(inv) = 1
      and rv.edit_reason = 'Owner asked for the warranty' and rv.edited_by = pg_temp.fx('o')
      and rv.snapshot->'invoice'->>'print_note' = 'Two-year warranty on the socks'
      and rv.after_snapshot->'invoice'->>'print_note' = 'Three-year warranty on the socks'
      and au.reason = 'Owner asked for the warranty' and au.changed_by = pg_temp.fx('o')
      and au.old_data->'invoice'->>'print_note' = 'Two-year warranty on the socks'
      and au.new_data->'invoice'->>'print_note' = 'Three-year warranty on the socks'
      and (au.old_data->'invoice') - 'print_note' - 'edit_count' - 'edited_by' - 'edited_at' - 'updated_at'
          = (au.new_data->'invoice') - 'print_note' - 'edit_count' - 'edited_by' - 'edited_at' - 'updated_at',
    'P3 one revision and one invoice_corrected audit row, with the reason, hold the old and the new note, and nothing else of the invoice differs');
  -- Staff of the invoice's store, with a reason.
  perform pg_temp.as_user('s');
  before := pg_temp.money_and_stock(inv);
  e := pg_temp.try(inv, jsonb_build_object('print_note', 'Warranty card enclosed'), 'Customer asked');
  perform pg_temp.check(e is null and pg_temp.pn(inv) = 'Warranty card enclosed' and pg_temp.money_and_stock(inv) = before
      and pg_temp.revs(inv) = 2 and pg_temp.audits(inv) = 2
      and exists (select 1 from public.audit_logs where table_name = 'invoices' and record_id = inv and action = 'invoice_corrected'
                    and changed_by = pg_temp.fx('s') and reason = 'Customer asked'),
    'P4 staff of the invoice''s store change the note on a paid invoice, with a reason, audited as them: ' || coalesce(e, 'saved'));
  -- Staff of another store.
  perform pg_temp.as_user('s2');
  e := pg_temp.try(inv, jsonb_build_object('print_note', 'Not theirs'), 'Trying');
  perform pg_temp.check(e = 'No access to this invoice' and pg_temp.pn(inv) = 'Warranty card enclosed',
    'P5 staff of another store are refused: ' || coalesce(e, 'saved'));
  -- A refund request waiting.
  insert into public.approval_requests(request_type, status, requested_by, related_record_id, reason, payload)
    values ('invoice_refund', 'pending', pg_temp.fx('s'), inv, 'Customer wants a refund', jsonb_build_object('request_id', gen_random_uuid()));
  perform pg_temp.as_user('s');
  e := pg_temp.try(inv, jsonb_build_object('print_note', 'While the refund waits'), 'Customer asked');
  perform pg_temp.check(e like 'Only an Owner or Manager can correct this invoice. Staff can correct a paid or part-paid invoice of their own store while no refund or cancellation request is waiting on it'
      and pg_temp.pn(inv) = 'Warranty card enclosed' and pg_temp.revs(inv) = 2,
    'P6 staff are refused while a refund request waits: ' || coalesce(e, 'saved'));
  update public.approval_requests set status = 'rejected' where related_record_id = inv and status = 'pending';
  -- A header without print_note keeps it; a Notes-only correction too.
  perform pg_temp.as_user('o');
  e := pg_temp.try(inv, jsonb_build_object('notes', 'Internal only, checked'), 'Internal note');
  perform pg_temp.check(e is null and pg_temp.pn(inv) = 'Warranty card enclosed'
      and (select notes from public.invoices where id = inv) = 'Internal only, checked',
    'P7 a correction that does not name print_note (an older page) keeps it; the internal note changes alone: ' || coalesce(e, 'saved'));
  e := pg_temp.try(inv, jsonb_build_object('print_note', repeat('w', 501)), 'Too long');
  perform pg_temp.check(e = 'PRINT_NOTE_TOO_LONG: The note printed on the invoice can be at most 500 characters.'
      and pg_temp.pn(inv) = 'Warranty card enclosed' and pg_temp.edits(inv) = 3,
    'P8 501 characters are refused by the correction, in words: ' || coalesce(e, 'saved'));
  -- The correction summary takes a note-only change and changes nothing.
  before := pg_temp.money_and_stock(inv);
  begin
    after := public.preview_invoice_correction(inv, jsonb_build_object('print_note', 'Preview only', 'reason', 'Looking',
                                                                         'items', pg_temp.lines(inv)));
    e := null;
  exception when others then e := sqlerrm;
  end;
  perform pg_temp.check(e is null and after is not null and pg_temp.pn(inv) = 'Warranty card enclosed'
      and pg_temp.money_and_stock(inv) = before and pg_temp.edits(inv) = 3 and pg_temp.revs(inv) = 3,
    'P9 the correction summary takes a note-only change and leaves the invoice as it was: ' || coalesce(e, 'shown'));
end $$;

-- The legacy update_invoice (no print_note) keeps it on an unpaid invoice.
do $$
declare inv uuid; e text;
begin
  perform pg_temp.as_user('o');
  inv := pg_temp.make('A', jsonb_build_object('print_note', 'Kept by the old path'));
  begin
    perform public.update_invoice(inv, pg_temp.fx('cust'), null, pg_temp.lines(inv), 0, 'Internal from the old path', null, '[]'::jsonb, null);
    e := null;
  exception when others then e := sqlerrm;
  end;
  perform pg_temp.check(e is null and pg_temp.pn(inv) = 'Kept by the old path'
      and (select notes from public.invoices where id = inv) = 'Internal from the old path',
    'P10 update_invoice (no print_note) keeps the note: ' || coalesce(e, 'saved'));
end $$;

-- ═════ M 456 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m456 m left join pg_temp.fn_md5s() f on f.fn = m.fn where f.fn is null or f.md5 <> m.md5)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m456),
  'M1 running 456 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m456 m left join b456 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5)
                     = array['correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'create_invoice_with_details(uuid,uuid,jsonb,jsonb)']
    and (select count(*) from m456) = (select count(*) from b456),
  'M2 its first run changed create_invoice_with_details and correct_invoice alone (no function added or dropped)');
select pg_temp.check((select before = after1 from r456),
  'M3 456''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 456 checks passed.';
end $$;
rollback;
