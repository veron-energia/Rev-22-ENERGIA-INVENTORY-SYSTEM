-- An Owner or Manager can withdraw a link sent to a customer (523).
--
-- Two invoices (store A, store B), a rental and a special sale, with PDF copies in the store
-- invoice-pdfs as the pages leave them: a copy each send made (407) and recorded in the send
-- log by a Staff login as the page records it, a copy sent before the send log was kept
-- (no send recorded; replaced on each send, before 407), and a copy of another document
-- whose name starts like the first invoice's number. An Owner and a Manager (of store A)
-- list each document's links; Staff, an Inventory Manager and an Admin are refused, as the
-- storage rule that deletes a copy refuses them. A copy is a document's when its name carries
-- the document's number: a send recorded (by any Staff login) for one document naming
-- another's copy changes neither list. A withdrawal is refused while its copy is still
-- stored; once the copy is deleted (as the page deletes it, through the storage API), it is
-- recorded in the send log and the Audit Log, and each time again; a copy stored again under
-- a withdrawn name is shown as such and can be withdrawn again; a copy of another document is
-- refused.
--
--   sh scripts/invoices/local-sql.sh -f scripts/permissions/tests/document-links-withdraw-523.sql
-- 523 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L523, @example.invalid, +61491570...).
\set ON_ERROR_STOP on
begin;
select to_regprocedure('public.withdraw_document_link(text,uuid,text)') is not null as m523_in \gset
\if :m523_in
\else
\ir ../../../supabase/523_a_sent_link_can_be_withdrawn.sql
\endif
-- A second run changes nothing.
\ir ../../../supabase/523_a_sent_link_can_be_withdrawn.sql

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l523(k text primary key, v text not null);
create function pg_temp.fx(p_k text) returns text language sql as $f$ select v from l523 where k = p_k $f$;
-- One statement as a signed-in login: its first column as text, or 'ERR <sqlstate> <message>'.
create function pg_temp.as_login(p_who text, q text) returns text language plpgsql as $f$
declare v text; u uuid := pg_temp.fx(p_who)::uuid;
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute q into v;
  execute 'reset role';
  return coalesce(v, 'ok');
exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $f$;
-- A document's links as a login sees them: each as "<copy key> <send|before-log> <state>",
-- in the order of the copy keys, "none", or the error. (The login reads the list; the copy
-- keys are looked up afterwards, as the database owner.)
create function pg_temp.links(p_who text, p_kind text, p_doc text) returns text language plpgsql as $f$
declare raw text; res text;
begin
  raw := pg_temp.as_login(p_who, format(
    $q$select coalesce(string_agg(l.pdf_path || '|' || case when l.send_id is null then 'before-log' else 'send' end
                       || '|' || case when l.withdrawn_at is not null and l.copy_present then 'stored-again'
                                      when l.withdrawn_at is not null then 'withdrawn-by-' || coalesce(l.withdrawn_by_name, '?')
                                      when l.copy_present then 'open' else 'gone' end, E'\n'), '')
         from public.document_links(%L, %L) l$q$, p_kind, pg_temp.fx(p_doc)));
  if raw like 'ERR %' then return raw; end if;
  if raw = '' then return 'none'; end if;
  select string_agg(coalesce(k.k, '?' || split_part(e, '|', 1)) || ' ' || split_part(e, '|', 2) || ' ' || split_part(e, '|', 3),
                    ', ' order by coalesce(k.k, split_part(e, '|', 1)))
    into res
    from unnest(string_to_array(raw, E'\n')) e left join l523 k on k.v = split_part(e, '|', 1) and k.k like 'c%';
  return res;
end $f$;
-- A withdrawal as a login: the reply, or the error.
create function pg_temp.withdraw(p_who text, p_kind text, p_doc text, p_copy text) returns text language sql as $f$
  select pg_temp.as_login(p_who, format('select public.withdraw_document_link(%L, %L, %L)::text',
    p_kind, pg_temp.fx(p_doc), pg_temp.fx(p_copy))) $f$;

do $$
declare own uuid := gen_random_uuid(); mgr uuid := gen_random_uuid(); adm uuid := gen_random_uuid();
        im uuid := gen_random_uuid(); stf uuid := gen_random_uuid();
        sa uuid; sb uuid; p uuid; sp uuid; cust uuid; i1 uuid; i2 uuid; r uuid; s uuid;
        n1 text; n2 text;
        sfx constant text := lower(substr(md5(gen_random_uuid()::text), 1, 6));
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l523-owner@example.invalid', now()), (mgr, 'l523-manager@example.invalid', now()),
    (adm, 'l523-admin@example.invalid', now()), (im, 'l523-invman@example.invalid', now()),
    (stf, 'l523-staff@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'L523 Owner', 'l523-owner@example.invalid', 'owner', true),
    (mgr, 'L523 Manager', 'l523-manager@example.invalid', 'manager', true),
    (adm, 'L523 Admin', 'l523-admin@example.invalid', 'admin', true),
    (im, 'L523 Inventory Manager', 'l523-invman@example.invalid', 'inventory_manager', true),
    (stf, 'L523 Staff', 'l523-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L523 Store A ' || sfx, 'L523A' || sfx, 'SG') returning id into sa;
  insert into public.stores(name, code, country_code) values ('L523 Store B ' || sfx, 'L523B' || sfx, 'SG') returning id into sb;
  -- Staff, the Inventory Manager and the Manager work at store A only.
  insert into public.user_store_assignments(user_id, store_id) values (stf, sa), (im, sa), (mgr, sa);
  insert into public.products(name, sku) values ('L523 Soap ' || sfx, 'L523P' || sfx) returning id into p;
  insert into public.store_inventory(store_id, product_id, current_qty) values (sa, p, 10), (sb, p, 10);
  perform public.set_product_prices(sa, p, 50, 50, 'available');
  perform public.set_product_prices(sb, p, 50, 50, 'available');
  insert into public.customers(full_name, phone) values ('L523 Customer', '+61491570523') returning id into cust;
  i1 := public.create_invoice(sa, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', p, 'quantity', 1)));
  i2 := public.create_invoice(sb, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', p, 'quantity', 1)));
  select invoice_no into n1 from public.invoices where id = i1;
  select invoice_no into n2 from public.invoices where id = i2;
  insert into public.special_products(name, sku, product_id) values ('L523 Chair ' || sfx, 'L523S' || sfx, p) returning id into sp;
  insert into public.rentals(rental_no, special_product_id, customer_id, quantity, rate_type, periods, start_date, expected_return_date, store_id, source_store_id)
    values ('L523R-' || sfx, sp, cust, 1, 'day', 1, current_date, current_date + 1, sa, sa) returning id into r;
  insert into public.special_sales(sale_no, special_product_id, quantity, store_id, source_store_id)
    values ('L523S/' || sfx, sp, 1, sa, sa) returning id into s;
  insert into l523 values ('owner', own::text), ('manager', mgr::text), ('admin', adm::text), ('invman', im::text), ('staff', stf::text),
    ('sa', sa::text), ('sb', sb::text), ('inv1', i1::text), ('inv2', i2::text), ('rental', r::text), ('sale', s::text),
    -- The copies, named as src/lib/sendDoc.ts names them (a special sale's "/" made a dash).
    ('c1', sa || '/invoice/' || n1 || '-' || gen_random_uuid() || '.pdf'),        -- invoice 1, sent and recorded
    ('c2', sa || '/invoice/' || n1 || '.pdf'),                                     -- invoice 1, sent before the send log
    ('c3', sb || '/invoice/' || n2 || '-' || gen_random_uuid() || '.pdf'),        -- invoice 2 (store B), sent and recorded
    ('c4', sa || '/invoice/' || n1 || '9-' || gen_random_uuid() || '.pdf'),       -- another number that starts like invoice 1's
    ('c5', sa || '/rental/L523R-' || sfx || '-' || gen_random_uuid() || '.pdf'),  -- the rental, sent and recorded
    ('c6', sa || '/special_sale/L523S-' || sfx || '.pdf');                         -- the special sale, before the send log
  insert into storage.objects(bucket_id, name)
    select 'invoice-pdfs', v from l523 where k in ('c1', 'c2', 'c3', 'c4', 'c5', 'c6');
end $$;

-- The sends, recorded by a Staff login as the page records them (and a failed send, with no copy).
select pg_temp.check(pg_temp.as_login('staff', format($q$select public.record_document_send('invoice', %L, 'whatsapp', %L, null, '+61491570523', %L, 'sent', null)::text$q$,
                       (select invoice_no from public.invoices where id = pg_temp.fx('inv1')::uuid), pg_temp.fx('inv1'), pg_temp.fx('c1'))) !~ '^ERR'
                     and pg_temp.as_login('staff', format($q$select public.record_document_send('invoice', %L, 'email', %L, null, 'l523-cust@example.invalid', %L, 'sent', null)::text$q$,
                       (select invoice_no from public.invoices where id = pg_temp.fx('inv2')::uuid), pg_temp.fx('inv2'), pg_temp.fx('c3'))) !~ '^ERR'
                     and pg_temp.as_login('staff', format($q$select public.record_document_send('rental', %L, 'whatsapp', %L, null, '+61491570523', %L, 'sent', null)::text$q$,
                       (select rental_no from public.rentals where id = pg_temp.fx('rental')::uuid), pg_temp.fx('rental'), pg_temp.fx('c5'))) !~ '^ERR'
                     and pg_temp.as_login('staff', format($q$select public.record_document_send('invoice', %L, 'whatsapp', %L, null, '+61491570523', null, 'failed', 'pop-up blocked')::text$q$,
                       (select invoice_no from public.invoices where id = pg_temp.fx('inv1')::uuid), pg_temp.fx('inv1'))) !~ '^ERR',
  '0 Staff record four sends as the page does (three with a copy, one failed with none)');

-- 1. The links of each document, for an Owner and a Manager
select pg_temp.check(pg_temp.links(w, 'invoice', 'inv1') = 'c1 send open, c2 before-log open',
  '1a ' || w || ': invoice 1''s links are its recorded send and its copy from before the log, not another number''s: ' || pg_temp.links(w, 'invoice', 'inv1'))
  from unnest(array['owner', 'manager']) w;
select pg_temp.check(pg_temp.links('manager', 'invoice', 'inv2') = 'c3 send open',
  '1b the Manager of store A sees store B''s invoice''s link too (Managers every store): ' || pg_temp.links('manager', 'invoice', 'inv2'));
select pg_temp.check(pg_temp.links('owner', 'rental', 'rental') = 'c5 send open' and pg_temp.links('owner', 'special_sale', 'sale') = 'c6 before-log open',
  '1c a rental''s recorded send, and a special sale''s copy from before the log (its "/" a dash in the name)');
select pg_temp.check(pg_temp.as_login('owner', format($q$select channel || ' ' || sent_to || ' ' || sent_by_name || ' ' || status from public.document_links('invoice', %L) where send_id is not null$q$,
                       pg_temp.fx('inv1'))) = 'whatsapp +61491570523 L523 Staff sent',
  '1d a send shows how, to whom and by whom');
-- Any Staff login writes the send log: a send recorded for one document naming another's copy
-- does not make the copy that document's (security audit of 17 Nov 2026, 523's pre-check).
select pg_temp.check(pg_temp.as_login('staff', format($q$select public.record_document_send('invoice', %L, 'whatsapp', %L, null, '+61491570524', %L, 'sent', null)::text$q$,
                       (select invoice_no from public.invoices where id = pg_temp.fx('inv1')::uuid), pg_temp.fx('inv1'), pg_temp.fx('c3'))) !~ '^ERR'
                     and pg_temp.as_login('staff', format($q$select public.record_document_send('invoice', %L, 'whatsapp', %L, null, '+61491570525', %L, 'sent', null)::text$q$,
                       (select invoice_no from public.invoices where id = pg_temp.fx('inv2')::uuid), pg_temp.fx('inv2'), pg_temp.fx('c2'))) !~ '^ERR',
  '1e Staff record a send of invoice 1 naming invoice 2''s copy, and one of invoice 2 naming invoice 1''s copy from before the log');
select pg_temp.check(pg_temp.links('owner', 'invoice', 'inv1') = 'c1 send open, c2 before-log open'
                     and pg_temp.links('owner', 'invoice', 'inv2') = 'c3 send open',
  '1f each document still lists its own copies only: ' || pg_temp.links('owner', 'invoice', 'inv1') || ' / ' || pg_temp.links('owner', 'invoice', 'inv2'));

-- 2. Everyone else is refused, as the storage rule that deletes a copy refuses them
select pg_temp.check(pg_temp.links(w, 'invoice', 'inv1') = 'ERR 42501 Your role cannot do this.'
                     and pg_temp.withdraw(w, 'invoice', 'inv1', 'c1') = 'ERR 42501 Your role cannot do this.',
  '2a ' || w || ' is refused the list and a withdrawal')
  from unnest(array['staff', 'invman', 'admin']) w;

-- 3. Withdrawing a recorded send
select pg_temp.check(pg_temp.withdraw('manager', 'invoice', 'inv1', 'c1') = 'ERR P0001 The PDF copy is still there, so its link still opens. Try Withdraw again.',
  '3a refused while the copy is still stored');
-- The page deletes the copy through the storage API (here, as the database owner).
delete from storage.objects where bucket_id = 'invoice-pdfs' and name = pg_temp.fx('c1');
select pg_temp.check(pg_temp.withdraw('manager', 'invoice', 'inv1', 'c1') = '{"again": false, "sends": 1, "success": true}',
  '3b once it is gone, the Manager''s withdrawal is recorded: one send');
select pg_temp.check((select ds.withdrawn_at is not null and ds.withdrawn_by = pg_temp.fx('manager')::uuid
                        from public.document_sends ds where ds.pdf_path = pg_temp.fx('c1'))
                     and (select count(*) from public.audit_logs a
                           where a.action = 'document_link_withdrawn' and a.table_name = 'invoices' and a.record_id = pg_temp.fx('inv1')::uuid
                             and a.changed_by = pg_temp.fx('manager')::uuid and a.store_id = pg_temp.fx('sa')::uuid
                             and public.audit_module(a.module, a.table_name) = 'invoices'
                             and a.new_data ->> 'pdf_path' = pg_temp.fx('c1') and (a.new_data ->> 'sends_marked')::int = 1) = 1,
  '3c the send log says who withdrew it and when; one Audit Log entry under Invoices, at store A');
select pg_temp.check(pg_temp.links('owner', 'invoice', 'inv1') = 'c1 send withdrawn-by-L523 Manager, c2 before-log open',
  '3d the list shows it withdrawn, by whom: ' || pg_temp.links('owner', 'invoice', 'inv1'));
select pg_temp.check(pg_temp.withdraw('owner', 'invoice', 'inv1', 'c1') = '{"again": true, "sends": 0, "success": true}',
  '3e asked again, it is recorded again');
select pg_temp.check((select count(*) from public.audit_logs a where a.action = 'document_link_withdrawn' and a.new_data ->> 'pdf_path' = pg_temp.fx('c1')) = 2
                     and (select ds.withdrawn_by = pg_temp.fx('manager')::uuid from public.document_sends ds where ds.pdf_path = pg_temp.fx('c1')),
  '3f an entry each time; the send keeps its first withdrawal, the Manager''s');
-- A copy stored again under the withdrawn name (a Staff login of the store may upload in its
-- folder; the pages never reuse a name): shown as stored again, and withdrawn again.
select pg_temp.check(pg_temp.as_login('staff', format($q$insert into storage.objects(bucket_id, name) values ('invoice-pdfs', %L) returning 'stored'$q$,
                       pg_temp.fx('c1'))) = 'stored',
  '3g Staff of store A can store a copy under the withdrawn name again (the storage rules allow it)');
select pg_temp.check(pg_temp.links('owner', 'invoice', 'inv1') = 'c1 send stored-again, c2 before-log open',
  '3h the list shows it stored again: ' || pg_temp.links('owner', 'invoice', 'inv1'));
select pg_temp.check(pg_temp.withdraw('owner', 'invoice', 'inv1', 'c1') = 'ERR P0001 The PDF copy is still there, so its link still opens. Try Withdraw again.',
  '3i its withdrawal is refused while it is stored');
delete from storage.objects where bucket_id = 'invoice-pdfs' and name = pg_temp.fx('c1');
select pg_temp.check(pg_temp.withdraw('owner', 'invoice', 'inv1', 'c1') = '{"again": true, "sends": 0, "success": true}',
  '3j once deleted again, the second withdrawal is recorded');
select pg_temp.check((select count(*) from public.audit_logs a where a.action = 'document_link_withdrawn' and a.new_data ->> 'pdf_path' = pg_temp.fx('c1')
                       and a.changed_by = pg_temp.fx('owner')::uuid) = 2
                     and pg_temp.links('owner', 'invoice', 'inv1') = 'c1 send withdrawn-by-L523 Manager, c2 before-log open',
  '3k with the Owner''s own entry; the list shows it withdrawn again');

-- 4. Only a copy of that document
select pg_temp.check(pg_temp.withdraw('owner', 'invoice', 'inv1', w) = 'ERR P0001 This link is not one sent for this document.',
  '4a invoice 1 refuses the copy ' || w || (case w when 'c3' then ' (invoice 2''s, though a send of invoice 1 names it)' when 'c4' then ' (a number that starts like its own)' else ' (the rental''s)' end))
  from unnest(array['c3', 'c4', 'c5']) w;
select pg_temp.check(pg_temp.as_login('owner', format($q$select public.withdraw_document_link('invoice', %L, null)::text$q$, pg_temp.fx('inv1')))
                       = 'ERR P0001 This link is not one sent for this document.'
                     and pg_temp.as_login('owner', format($q$select public.withdraw_document_link('receipt', %L, %L)::text$q$, pg_temp.fx('inv1'), pg_temp.fx('c1')))
                       = 'ERR P0001 This document was not found.',
  '4b no copy named, or a kind of document there is none of: refused');

-- 5. A copy sent before the send log was kept
delete from storage.objects where bucket_id = 'invoice-pdfs' and name = pg_temp.fx('c2');
select pg_temp.check(pg_temp.withdraw('owner', 'invoice', 'inv1', 'c2') = '{"again": false, "sends": 0, "success": true}',
  '5a its withdrawal is accepted: no send to mark');
select pg_temp.check((select count(*) from public.audit_logs a
                       where a.action = 'document_link_withdrawn' and a.record_id = pg_temp.fx('inv1')::uuid
                         and a.changed_by = pg_temp.fx('owner')::uuid and a.new_data ->> 'pdf_path' = pg_temp.fx('c2')
                         and (a.new_data ->> 'sends_marked')::int = 0) = 1,
  '5b and is recorded in the Audit Log alone, by the Owner');
select pg_temp.check(pg_temp.links('owner', 'invoice', 'inv1') = 'c1 send withdrawn-by-L523 Manager',
  '5c and it is no longer listed: ' || pg_temp.links('owner', 'invoice', 'inv1'));
select pg_temp.check((select bool_and(ds.withdrawn_at is null) from public.document_sends ds where ds.pdf_path = pg_temp.fx('c2')),
  '5d invoice 2''s send naming that copy is not marked: the copy is not invoice 2''s');

-- 6. The names a document's copies are stored under
select pg_temp.check((x.name ~ public.document_link_name_re(x.kind, x.no)) = x.ok,
  '6 ' || x.no || ' ' || case when x.ok then 'owns ' else 'does not own ' end || x.name)
  from (values ('invoice', 'INV-9001-0007', 's/invoice/INV-9001-0007.pdf', true),
               ('invoice', 'INV-9001-0007', 's/invoice/INV-9001-0007-0f8fad5b-d9cb-469f-a165-70867728950e.pdf', true),
               ('invoice', 'INV-9001-0007', 'no-store/invoice/INV-9001-0007-lzx1k2ab-a8b9c0d1e2.pdf', true),
               ('invoice', 'INV-9001-0007', 's/invoice/INV-9001-0007-1-2.pdf', false),
               ('invoice', 'INV-9001-0007', 's/invoice/INV-9001-00079.pdf', false),
               ('invoice', 'INV-9001-0007', 's/invoice/INV-9001-0007-0f8fad5b-d9cb-469f-a165-70867728950e-x.pdf', false),
               ('invoice', 'INV-9001-0007', 's/rental/INV-9001-0007.pdf', false),
               ('invoice', 'INV-9001-0007', 's/invoice/INV-9001-0007.pdf.pdf', false),
               ('invoice', 'INV-9001-0007', 's/x/invoice/INV-9001-0007.pdf', false),
               ('special_sale', 'SS/2026 01', 's/special_sale/SS-2026-01.pdf', true),
               ('rental', 'R.1', 's/rental/R.1.pdf', true),
               ('rental', 'R.1', 's/rental/RX1.pdf', false)) x(kind, no, name, ok);

-- 7. The send log's columns, the functions and who may call them
select pg_temp.check((select string_agg(column_name || ' ' || data_type, ',' order by ordinal_position)
                        from information_schema.columns where table_schema = 'public' and table_name = 'document_sends'
                         and column_name in ('withdrawn_at', 'withdrawn_by')) = 'withdrawn_at timestamp with time zone,withdrawn_by uuid',
  '7a the send log has withdrawn_at and withdrawn_by');
select pg_temp.check(md5(pg_get_functiondef(to_regprocedure('public.' || x.f))) = x.m
                     and has_function_privilege('authenticated', to_regprocedure('public.' || x.f), 'execute') = x.auth
                     and not has_function_privilege('anon', to_regprocedure('public.' || x.f), 'execute'),
  '7b ' || x.f || ' is 523''s; signed-in logins ' || case when x.auth then 'call it' else 'cannot call it' end || '; anon cannot')
  from (values ('document_link_name_re(text,text)', '398b65c5cf3ba45de47e9ee7c2949116', false),
               ('document_links(text,uuid)', '27a3c98cf91a74c8cefba02d253b2e6a', true),
               ('withdraw_document_link(text,uuid,text)', 'eacf6fd4498dcb0ca60d62f32a24bf82', true)) x(f, m, auth);
rollback;
