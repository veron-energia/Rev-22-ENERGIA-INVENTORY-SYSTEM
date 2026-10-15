-- Instalment terms stamped on an invoice (416: INVOICES-CREATE-M3).
--
--   I1 Staff stamp the terms after recording a payment, as Record Payment
--      does; the change is audited with the terms before and after.
--   I2 The same terms again (a later instalment paid) change nothing and
--      write no audit row.
--   I3 Staff may not change or clear terms already on the invoice; they are
--      told to use Correct Invoice or ask an Owner or Manager.
--   I4 A Manager may, and each change is audited.
--   I5 Correct Invoice still lets staff change the terms of a paid invoice of
--      their store, with a revision (377).
--   I6 No terms before a receipt; none on a cancelled, refunded or completed
--      FOC invoice; a deleted invoice is not found; another store's staff
--      have no access.
--
-- Needs 416 (psql -v mig=supabase/416_invoice_editing_foc_and_payment_guards.sql
-- installs it after "begin;"). Disposable database only; everything is rolled
-- back. Fixtures are invented.
\set ON_ERROR_STOP on
begin;
\if :{?prelude}
\i :prelude
\endif
\if :{?mig}
\i :mig
\endif
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.label(inv uuid, method text, months int) returns text language sql as
$$ select pg_temp.err(format('select public.set_invoice_instalment_label(%L, %L, %L)', inv, pg_temp.fx(method), months)) $$;
create function pg_temp.terms(inv uuid) returns text language sql as
$$ select concat_ws('/', i.instalment_category, (select k from fx where v = i.instalment_method_id), i.instalment_months)
     from public.invoices i where i.id = inv $$;
create function pg_temp.audits(inv uuid) returns int language sql as
$$ select count(*)::int from public.audit_logs where record_id = inv and action = 'instalment_terms_set' $$;
-- An invoice of one pair of socks at a store, by the Owner; paid (in full or
-- in part) unless paid is 0.
create function pg_temp.sale(st text, paid numeric) returns uuid language plpgsql as
$$declare inv uuid;
begin
  perform pg_temp.as_user('o');
  inv := public.create_invoice_with_details(pg_temp.fx(st), pg_temp.fx('c'),
    jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('socks'),'quantity',1)),
    jsonb_build_object('business_date', public.sg_today()::text));
  if paid > 0 then
    perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('atome'), 'amount', paid)), gen_random_uuid());
  end if;
  return inv;
end$$;
-- The audit row that set these months (one transaction: created_at does not order them).
create function pg_temp.audit_to(inv uuid, months int) returns jsonb language sql as
$$ select jsonb_build_object('old', old_data, 'new', new_data, 'by', changed_by) from public.audit_logs
    where record_id = inv and action = 'instalment_terms_set' and new_data->>'instalment_months' is not distinct from months::text limit 1 $$;

do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); s uuid := gen_random_uuid(); s2 uuid := gen_random_uuid();
  sfx text := left(md5(random()::text), 6); st_a uuid; st_b uuid; c uuid; p uuid; v uuid;
begin
  insert into auth.users(id,email) values (o,'il416-o-'||sfx||'@tests.invalid'),(m,'il416-m-'||sfx||'@tests.invalid'),
    (s,'il416-s-'||sfx||'@tests.invalid'),(s2,'il416-s2-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (o,'IL Owner','il416-o-'||sfx||'@tests.invalid','owner'),
    (m,'IL Manager','il416-m-'||sfx||'@tests.invalid','manager'),(s,'IL Staff','il416-s-'||sfx||'@tests.invalid','staff'),
    (s2,'IL Other Staff','il416-s2-'||sfx||'@tests.invalid','staff');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name,code,country_code) values ('IL Store A','ILA'||sfx,'SG') returning id into st_a;
  insert into stores(name,code,country_code) values ('IL Store B','ILB'||sfx,'SG') returning id into st_b;
  insert into user_store_assignments(user_id,store_id) values (m,st_a),(s,st_a),(s2,st_b);
  insert into customers(full_name,phone) values ('IL Buyer','+61491576801') returning id into c;
  insert into products(name,sku,product_type) values ('IL Socks','ILS-'||sfx,'own') returning id into p;
  insert into store_inventory(store_id,product_id,current_qty) values (st_a,p,100),(st_b,p,100);
  perform set_product_prices(st_a,p,600,600,'available');
  perform set_product_prices(st_b,p,600,600,'available');
  insert into fx values ('o',o),('m',m),('s',s),('s2',s2),('A',st_a),('B',st_b),('c',c),('socks',p);
  insert into payment_methods(name,is_active) values ('IL Atome '||sfx,true) returning id into v; insert into fx values ('atome',v);
  insert into payment_methods(name,is_active) values ('IL Card '||sfx,true) returning id into v; insert into fx values ('card',v);
end $$;

-- ═════ I1–I4 ═════
do $$
declare inv uuid := pg_temp.sale('A', 200); e text; a jsonb;
  ask text := 'This invoice already has instalment terms. To change them, use Correct Invoice, or ask an Owner or Manager.';
begin
  perform pg_temp.as_user('s');
  e := pg_temp.label(inv, 'atome', 3);
  a := pg_temp.audit_to(inv, 3);
  perform pg_temp.check(e is null and pg_temp.terms(inv) = 'in_house/atome/3' and pg_temp.audits(inv) = 1
      and a->'old' = jsonb_build_object('instalment_category', null, 'instalment_method_id', null, 'instalment_months', null)
      and a->'new'->>'instalment_months' = '3' and (a->>'by')::uuid = pg_temp.fx('s'),
    'I1 staff stamp the terms after a payment, audited with the terms before and after: ' || coalesce(e, pg_temp.terms(inv)));
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('atome'), 'amount', 200)), gen_random_uuid());
  e := pg_temp.label(inv, 'atome', 3);
  perform pg_temp.check(e is null and pg_temp.terms(inv) = 'in_house/atome/3' and pg_temp.audits(inv) = 1,
    'I2 the same terms with the next instalment change nothing and write no audit row: ' || coalesce(e, 'done'));
  e := pg_temp.label(inv, 'atome', 6);
  perform pg_temp.check(e = ask and pg_temp.terms(inv) = 'in_house/atome/3', 'I3 staff may not change them: ' || coalesce(e, 'done'));
  e := pg_temp.err(format('select public.set_invoice_instalment_label(%L, null, null)', inv));
  perform pg_temp.check(e = ask and pg_temp.terms(inv) = 'in_house/atome/3', 'I3 nor clear them: ' || coalesce(e, 'done'));
  perform pg_temp.as_user('m');
  e := pg_temp.label(inv, 'card', 6);
  a := pg_temp.audit_to(inv, 6);
  perform pg_temp.check(e is null and pg_temp.terms(inv) = 'in_house/card/6' and pg_temp.audits(inv) = 2
      and a->'old'->>'instalment_months' = '3' and a->'new'->>'instalment_months' = '6' and (a->>'by')::uuid = pg_temp.fx('m'),
    'I4 a Manager changes them, audited: ' || coalesce(e, pg_temp.terms(inv)));
  e := pg_temp.err(format('select public.set_invoice_instalment_label(%L, null, null)', inv));
  a := pg_temp.audit_to(inv, null);
  perform pg_temp.check(e is null and pg_temp.terms(inv) = '' and pg_temp.audits(inv) = 3
      and a->'old'->>'instalment_months' = '6' and (a->>'by')::uuid = pg_temp.fx('m'),
    'I4 and clears them, audited: ' || coalesce(e, 'done'));
end $$;

-- ═════ I5 Correct Invoice ═════
do $$
declare inv uuid := pg_temp.sale('A', 600); e text;
begin
  perform pg_temp.as_user('m');
  perform pg_temp.label(inv, 'atome', 3);
  perform pg_temp.as_user('s');
  e := pg_temp.err(format('select public.correct_invoice(%L, %L, %L, %L, %L)', inv,
         (select jsonb_agg(jsonb_build_object('invoice_item_id', id, 'kind', 'product', 'product_id', product_id, 'quantity', quantity, 'unit_price', unit_price))
            from public.invoice_items where invoice_id = inv),
         jsonb_build_object('instalment_category', 'in_house', 'instalment_method_id', pg_temp.fx('atome'), 'instalment_months', 12),
         'Customer chose 12 months', gen_random_uuid()));
  perform pg_temp.check(e is null and pg_temp.terms(inv) = 'in_house/atome/12' and exists (select 1 from public.invoice_revisions where invoice_id = inv),
    'I5 staff change the terms of a paid invoice with Correct Invoice, which keeps a revision: ' || coalesce(e, 'saved'));
end $$;

-- ═════ I6 Refused ═════
do $$
declare inv uuid; e text; st text;
begin
  inv := pg_temp.sale('A', 0);
  perform pg_temp.as_user('s');
  e := pg_temp.label(inv, 'atome', 3);
  perform pg_temp.check(e = 'Record a payment first. Instalment terms are set with the payment they belong to.' and pg_temp.terms(inv) = '',
    'I6 no terms before a receipt: ' || coalesce(e, 'done'));
  foreach st in array array['cancelled', 'refunded', 'completed_foc'] loop
    inv := pg_temp.sale('A', 600);
    update public.invoices set status = st::invoice_status where id = inv;
    perform pg_temp.as_user('m');
    e := pg_temp.label(inv, 'atome', 3);
    perform pg_temp.check(e = format('Instalment terms cannot be set on a %s invoice.', case st when 'completed_foc' then 'free (FOC)' else st end) and pg_temp.terms(inv) = '',
      format('I6 none on a %s invoice: %s', st, coalesce(e, 'done')));
  end loop;
  inv := pg_temp.sale('A', 600);
  update public.invoices set deleted_at = now() where id = inv;
  perform pg_temp.as_user('m');
  e := pg_temp.label(inv, 'atome', 3);
  perform pg_temp.check(e = 'Invoice not found', 'I6 a deleted invoice is not found: ' || coalesce(e, 'done'));
  inv := pg_temp.sale('A', 600);
  perform pg_temp.as_user('s2');
  e := pg_temp.label(inv, 'atome', 3);
  perform pg_temp.check(e = 'No access to this invoice' and pg_temp.terms(inv) = '', 'I6 another store''s staff have no access: ' || coalesce(e, 'done'));
end $$;

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All instalment term checks passed.';
end $$;
rollback;
