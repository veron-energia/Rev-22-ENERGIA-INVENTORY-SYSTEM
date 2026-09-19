-- 338: invoices and their payments are published to realtime, and what a
-- subscriber may hear is bounded by the same row-level security the list
-- query uses. Disposable database only; the fixture rolls back.
\set ON_ERROR_STOP on
begin;
do $$
declare owner_id uuid := gen_random_uuid(); staff_id uuid := gen_random_uuid(); st_a uuid; st_b uuid; c uuid; inv_a uuid; inv_b uuid; n int;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then raise exception 'FAIL: publication missing'; end if;
  if (select count(*) from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename in ('invoices','invoice_payments')) <> 2 then
    raise exception 'FAIL: invoices and invoice_payments are not both published'; end if;
  -- Both stay under row-level security: the policy realtime applies per subscriber.
  if not (select relrowsecurity from pg_class where oid = 'public.invoices'::regclass) or not (select relrowsecurity from pg_class where oid = 'public.invoice_payments'::regclass) then
    raise exception 'FAIL: row-level security is not enabled on both tables'; end if;

  insert into auth.users(id, email) values (owner_id, 'pub-owner@tests.invalid'), (staff_id, 'pub-staff@tests.invalid');
  insert into profiles(id, full_name, email, role) values (owner_id, 'Pub Owner', 'pub-owner@tests.invalid', 'owner'), (staff_id, 'Pub Staff', 'pub-staff@tests.invalid', 'staff');
  insert into stores(name, code, country_code) values ('Pub A', 'PUBA', 'SG') returning id into st_a;
  insert into stores(name, code, country_code) values ('Pub B', 'PUBB', 'SG') returning id into st_b;
  insert into user_store_assignments(user_id, store_id) values (staff_id, st_a);
  insert into customers(full_name, phone) values ('Pub Customer', '+6591118941') returning id into c;
  insert into invoices(invoice_no, store_id, customer_id, created_by, status) values ('PUB-A', st_a, c, owner_id, 'unpaid') returning id into inv_a;
  insert into invoices(invoice_no, store_id, customer_id, created_by, status) values ('PUB-B', st_b, c, owner_id, 'unpaid') returning id into inv_b;
  insert into invoice_payments(invoice_id, payment_method_id, amount, received_by) select inv_b, id, 5, owner_id from payment_methods limit 1;

  -- The local plain-Postgres clusters give the authenticated role nothing by
  -- default; Supabase grants these at setup. Inside the rolled-back fixture.
  grant usage on schema public to authenticated;
  grant select on public.invoices, public.invoice_payments to authenticated;
  grant execute on function public.invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer) to authenticated;
  -- As the staff member of store A, under RLS: the store-B invoice and its
  -- payment are invisible, which is exactly what a realtime event for them
  -- would be checked against.
  perform set_config('request.jwt.claim.sub', staff_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', staff_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.invoices where id in (inv_a, inv_b);
  if n <> 1 then raise exception 'FAIL: staff of store A sees % of the two invoices under RLS', n; end if;
  select count(*) into n from public.invoice_payments where invoice_id = inv_b;
  if n <> 0 then raise exception 'FAIL: staff of store A can read a store-B payment'; end if;
  -- And the list query the browser refreshes with agrees.
  if (select count(*) from jsonb_array_elements((public.invoice_list_page(null, null, 'all', null, null, null, 'created_at', 'desc', 50, 0))->'rows') r where r->>'invoice_no' in ('PUB-A','PUB-B')) <> 1 then
    raise exception 'FAIL: invoice_list_page shows a store the staff member cannot access'; end if;
  reset role;
  raise notice 'PASS: invoices and invoice_payments are in the supabase_realtime publication with RLS on; a staff member of one store can neither read nor list another store''s invoice or payment';
end $$;
rollback;
