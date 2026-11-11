-- 502 go-live: the data scripts run straight after migration 502, their UNDOs, and the later
-- script for the one Credit Package sold before go-live (the user, 10 Nov 2026: earning stops at
-- go-live; unclaimed Legacy rewards are cancelled; Credit Packages give credit only, the earlier
-- part-paid sale keeping its reward vouchers; every record stays).
--   scripts/therapy/credit-package-credit-only-502.sql         step 2a: Credit Packages give credit only,
--                                                              and the earlier sale's reward is kept
--   scripts/therapy/legacy-retired-golive-502.sql              step 2b: the 103 unclaimed Legacy rewards
--                                                              cancelled, the 3 rules switched off
--   scripts/therapy/credit-package-presale-reward-502.sql      later, with the user's OK: that sale's reward
--   scripts/therapy/undo-legacy-retired-golive-502.sql,
--   scripts/therapy/undo-credit-package-credit-only-502.sql,
--   scripts/therapy/undo-502.sql                               the UNDOs, in the rollback order
--
-- Each script is read from its file and run as on production: as the database owner, with the
-- recording account set in the same transaction. Every other step goes through the app's own
-- calls, as the person named, with their grants: the Credit Package and Premium Bundle windows
-- (upsert_credit_package, upsert_premium_bundle, set_catalogue_reward), the invoice form
-- (create_invoice_with_details), the Pay dialog (record_invoice_settlement), Vouchers to hand over
-- (therapy_list_page, entitlement_voucher_state, claim_entitlement_vouchers), Delete customer
-- (delete_customer), the Finance panel's refund and its reward review (invoice_refund_options,
-- refund_invoice_recorded, resolve_invoice_credit_rewards).
--
-- The fixture is production's shape on 10 Nov 2026, invented, so that the scripts' real constants
-- apply. First, inside this transaction, the rows the scripts count are cleared, in foreign-key
-- order; then, at 2 stores: 102 one-month Legacy rewards waiting (43 customers, 45 of them linked
-- to their day's invoice), 1 affiliate reward of 10 vouchers waiting, 53 cancelled and 1 used
-- month, 5 Legacy voucher rewards handed over (6 held vouchers, 50), 1 cancelled affiliate reward,
-- 67 invoice links in all; 3 rules (S$994, all stores); 3 Credit Packages (S$1,000, S$3,000,
-- S$5,000) with the reward on, 2 S$5,000 sales paid in full (10 rewards, 100 vouchers), 2 older
-- cancelled package rewards, and the S$1,000 package sold and part-paid through the
-- invoice form and the Pay dialog by staff; 4 Premium Bundles, 2 with the reward on.
--
--   C.  The scripts' constants. Those repeated across the files agree, as the files stand (what
--       would run on production). Then the suite writes its own fixture's figures into every
--       script's constants, each "c_name constant type := value;" exactly once (it stops if one is
--       missing, declared twice, or not one it sets), so a script whose constants were changed at
--       go-live, to production's figures then, is still tested here.
--       Not checked here: step 2b's lock on the rewards it cancels (a hand-over in another
--       session waits for it). One session cannot see a lock; it was rehearsed with two sessions.
--   F.  The fixture reads as production did: scripts/therapy/golive-preview-502.sql, run as it
--       stands, gives every constant the fixture's figure; every stop sign is clear.
--   G1. Refusals, each changing nothing: nobody recording it, staff, a Manager switched off, the
--       account half set; 502 not in (the refund guard back, a function not 502's) and an issuer
--       not as read; a second earlier sale, the earlier sale paid off, a fourth package, a deleted
--       one, a cheaper rule in reach (2 rewards), a sale split between 2 customers not yet paid
--       off with reward vouchers set aside (a split deleted, cancelled or paid off does not stop
--       it); step 2b before 2a; then, with 2a in: one more Legacy reward waiting, a month booked,
--       a fourth rule, one more voucher handed over, a hand-over while step 2b runs; the later
--       script and the UNDOs with nothing to do. The preview shows each of them.
--   G2. Step 2a: the packages give credit only; the earlier sale's values kept are what
--       issue_credit_package gives it when paid off with the reward on; the Audit Log; nothing
--       else changed; the preview's "2a in" rows.
--   G3. Step 2b: exactly the 103 cancelled; everything else byte for byte; the rules off; the
--       Audit Log and who recorded it; the checks after go-live.
--   G4. Afterwards (undone after): Vouchers to hand over shows the Credit Package rewards only;
--       a new Credit Package gives credit only; customers holding only Legacy rewards can be
--       deleted; the cancelled affiliate reward cannot be handed over; a Credit Package hand-over
--       works for staff.
--   G5. The earlier sale (undone after): the script refuses before it is paid off; paid off by
--       staff it gets credit only; the script gives exactly its 1 reward of 10 vouchers, the same
--       as the issuer gives, collected within 365 days; staff hand them over; a refund opens the
--       reward review (502's words) until it is settled; run again, it refuses.
--   G6. Run again: steps 2a and 2b refuse and change nothing.
--   G7. UNDO in the rollback order: undoing 2a refuses while 2b is in, and once the earlier sale
--       is paid off (its reward given, or still owed); undo 2b refuses, naming the reward, once
--       vouchers were handed over from one; undo 2b, undo 2a and undo-502.sql give back every row
--       and every function by fingerprint; each refuses a second run.
--
-- Run from the repository's root, on a copy of production's structure with 502 in and none of
-- production's rows (locally: a copy of lr502_with, which is rc501_live with 502 installed):
--   psql -X -v ON_ERROR_STOP=1 -d <copy> -f scripts/therapy/tests/legacy-retired-golive-502.sql
-- On a copy at 501 it installs supabase/502_legacy_therapy_retired.sql first, inside this
-- transaction. Disposable database only; everything is rolled back. Every name and code is
-- invented (T502G, @example.invalid); the phones are fictional (+61 2 5550 nnnn).
\set ON_ERROR_STOP on
\set t502g_mig `cat supabase/502_legacy_therapy_retired.sql`
\set t502g_undo502 `cat scripts/therapy/undo-502.sql`
\set t502g_cp `cat scripts/therapy/credit-package-credit-only-502.sql`
\set t502g_golive `cat scripts/therapy/legacy-retired-golive-502.sql`
\set t502g_undo_golive `cat scripts/therapy/undo-legacy-retired-golive-502.sql`
\set t502g_undo_cp `cat scripts/therapy/undo-credit-package-credit-only-502.sql`
\set t502g_presale `cat scripts/therapy/credit-package-presale-reward-502.sql`
\set t502g_preview `cat scripts/therapy/golive-preview-502.sql`
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';
select set_config('t502g.mig', :'t502g_mig', true), set_config('t502g.undo502', :'t502g_undo502', true),
       set_config('t502g.cp', :'t502g_cp', true), set_config('t502g.golive', :'t502g_golive', true),
       set_config('t502g.undo_golive', :'t502g_undo_golive', true), set_config('t502g.undo_cp', :'t502g_undo_cp', true),
       set_config('t502g.presale', :'t502g_presale', true), set_config('t502g.preview', :'t502g_preview', true) \g /dev/null
set local client_min_messages = warning;

create temp table t502g(k text primary key, id uuid);
create temp table t502g_kv(k text primary key, v jsonb);
create temp table t502g_res(n serial primary key, ok boolean, label text);
-- The checks are counted in sequences too: an undone savepoint (G4, G5) does not give a number
-- back, so their checks still count; a failed one is a FAIL warning when it happens.
create temp sequence t502g_pass;
create temp sequence t502g_fail;
create temp sequence t502g_phone start 2001;
create temp sequence t502g_inv start 1;
create function pg_temp.id(p_k text) returns uuid language sql as $f$ select id from t502g where k = p_k $f$;
create function pg_temp.put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t502g values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.kv(p_k text) returns jsonb language sql as $f$ select v from t502g_kv where k = p_k $f$;
create function pg_temp.setkv(p_k text, p_v jsonb) returns void language sql as $f$
  insert into t502g_kv values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.ok(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  insert into t502g_res(ok, label) values (coalesce(p_ok, false), p_label);
  if coalesce(p_ok, false) then perform nextval('t502g_pass');
  else perform nextval('t502g_fail'); raise warning 'FAIL %', p_label; end if;
end $f$;
-- The words the scripts and the app use.
create function pg_temp.txt(p_k text) returns text language sql immutable as $f$
  select case p_k
    when 'cp' then 'Credit Packages give credit only (decision of 10 Nov 2026)'
    when 'golive' then 'Legacy Therapy retired (decision of 10 Nov 2026)'
    when 'presale' then 'A Credit Package sold before go-live keeps its reward vouchers (decision of 10 Nov 2026)'
    when 'undo_golive' then 'Undone: Legacy Therapy retired (decision of 10 Nov 2026)'
    when 'undo_cp' then 'Undone: Credit Packages give credit only (decision of 10 Nov 2026)'
    when 'p13' then 'This Credit Package came with reward vouchers that are still outstanding. Review them and record what should happen to them, then refund or cancel. Vouchers not handed over yet are withdrawn; those already handed over stay with the customer.'
  end $f$;
-- Runs p_sql as this person, with their grants. 'ok:<answer>', or 'sqlstate:words' when refused.
create function pg_temp.try_as(p_who uuid, p_sql text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    perform set_config('request.jwt.claims', '', true);
    if p_who is not null then
      perform set_config('request.jwt.claims', json_build_object('sub', p_who, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    return s || ':' || m;
  end;
end $f$;
-- Runs one of the scripts as production does: as the database owner, with this person set as the
-- recording account in this transaction (nobody when null). 'ok', or 'sqlstate:words'.
create function pg_temp.run(p_who uuid, p_key text) returns text language plpgsql as $f$
declare s text; m text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
  perform set_config('request.jwt.claim.role', case when p_who is null then '' else 'authenticated' end, true);
  perform set_config('request.jwt.claims', case when p_who is null then '' else json_build_object('sub', p_who, 'role', 'authenticated')::text end, true);
  begin
    execute current_setting(p_key);
    return 'ok';
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    return s || ':' || m;
  end;
end $f$;
-- The invoice form: one Credit Package line for this customer at this store.
create function pg_temp.sell(p_who uuid, p_store uuid, p_customer uuid, p_package uuid) returns uuid language plpgsql as $f$
declare t text;
begin
  t := pg_temp.try_as(p_who, format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
    p_store, p_customer, jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', p_package, 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()::text)));
  if t not like 'ok:%' then raise exception 'T502G: the invoice form refused a Credit Package sale: %', t; end if;
  return substr(t, 4)::uuid;
end $f$;
-- The Pay dialog: one receipt of p_amount.
create function pg_temp.pay(p_who uuid, p_inv uuid, p_amount numeric) returns text language sql as $f$
  select pg_temp.try_as(p_who, format('select public.record_invoice_settlement(%L::uuid, %L::jsonb, %L::uuid)::text', p_inv,
    jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.id('pm'),
      'amount', p_amount, 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid())) $f$;
-- Vouchers to hand over: the hand-over window and its list.
create function pg_temp.claim(p_who uuid, p_ent uuid, p_voucher uuid, p_qty int) returns text language sql as $f$
  select pg_temp.try_as(p_who, format('select public.claim_entitlement_vouchers(%L::uuid, %L::jsonb, %L)::text', p_ent,
    jsonb_build_array(jsonb_build_object('voucher_id', p_voucher, 'quantity', p_qty)), 'T502G hand-over')) $f$;
create function pg_temp.state(p_who uuid, p_ent uuid) returns jsonb language plpgsql as $f$
declare t text;
begin
  t := pg_temp.try_as(p_who, format('select public.entitlement_voucher_state(%L::uuid)::text', p_ent));
  if t not like 'ok:%' then return jsonb_build_object('refused', t); end if;
  return substr(t, 4)::jsonb;
end $f$;
create function pg_temp.list(p_who uuid, p_tab text, p_search text, p_status text) returns jsonb language plpgsql as $f$
declare t text;
begin
  t := pg_temp.try_as(p_who, format('select public.therapy_list_page(%L, %L, %L, 200, 0)::text', p_tab, p_search, p_status));
  if t not like 'ok:%' then return jsonb_build_object('refused', t); end if;
  return substr(t, 4)::jsonb;
end $f$;
-- Invented records.
create function pg_temp.cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into public.customers (full_name, phone)
  values ('T502G Customer ' || p_k, '+61 2 5550 ' || lpad(nextval('t502g_phone')::text, 4, '0')) returning id into c;
  return pg_temp.put(p_k, c);
end $f$;
create function pg_temp.ent(p_no text, p_customer uuid, p_store uuid, p_rule uuid, p_name text, p_kind text, p_qty int,
                            p_status text, p_earner text, p_deadline date, p_qualified numeric default 994) returns uuid language plpgsql as $f$
declare e uuid;
begin
  insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
      duration_months, voucher_qty, qualifying_amount, qualified_value, forfeited_value, activation_deadline, status,
      created_by, qualification_group_id, earner_kind)
  values (p_no, p_customer, p_store, p_rule, p_name, p_kind,
      case when p_kind = 'unlimited' then 1 end, case when p_kind = 'voucher' then p_qty end, 994, p_qualified, 0, p_deadline, p_status,
      pg_temp.id('own'), md5('T502G day ' || p_no)::uuid, p_earner)
  returning id into e;
  return e;
end $f$;
-- A paid invoice of the reward's day, linked to it as the recount linked them.
create function pg_temp.link(p_ent uuid, p_customer uuid, p_store uuid) returns void language plpgsql as $f$
declare inv uuid;
begin
  insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount, paid_at)
  values ('T502G-DAY-' || lpad(nextval('t502g_inv')::text, 3, '0'), p_store, p_customer, pg_temp.id('own'), 'paid', 994, 994, 994, now())
  returning id into inv;
  insert into public.therapy_entitlement_invoices (entitlement_id, invoice_id, contributed_amount) values (p_ent, inv, 994);
end $f$;
-- Fingerprints: every row of a query (as jsonb), and every table the scripts read or write, a
-- whole row at a time, with how many Audit Log rows there are.
create function pg_temp.fp_q(p_sql text) returns text language plpgsql as $f$
declare v text;
begin
  execute format('select md5(coalesce(string_agg(j::text, %L order by j::text), %L)) from (%s) q(j)', ',', '', p_sql) into v;
  return v;
end $f$;
create function pg_temp.fp_parts() returns jsonb language plpgsql as $f$
declare t text; r jsonb := '{}'::jsonb;
begin
  foreach t in array array['therapy_entitlements', 'therapy_entitlement_invoices', 'customer_reward_vouchers', 'voucher_claims',
                           'therapy_package_rules', 'credit_packages', 'credit_package_vouchers', 'credit_package_sales',
                           'premium_bundles', 'invoices', 'invoice_items', 'invoice_payments', 'customers', 'customer_credit_lots'] loop
    r := r || jsonb_build_object(t, pg_temp.fp_q(format('select to_jsonb(x) from public.%I x', t)));
  end loop;
  return r || jsonb_build_object('audit_logs', (select count(*) from public.audit_logs));
end $f$;
create function pg_temp.fp_diff(a jsonb, b jsonb) returns text language sql as $f$
  select coalesce(string_agg(k, ', ' order by k), 'none')
    from (select jsonb_object_keys(a) union select jsonb_object_keys(b)) x(k) where a -> k is distinct from b -> k $f$;
-- Functions, read with public alone on the search path.
create function pg_temp.fp() returns text language sql set search_path = public as $f$
  select md5(string_agg(md5(pg_get_functiondef(oid)), '' order by oid::regprocedure::text)) || '/' || count(*)
    from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f' $f$;
create function pg_temp.md5_of(p_sig text) returns text language sql set search_path = public as $f$
  select md5(pg_get_functiondef(to_regprocedure('public.' || p_sig))) $f$;
create function pg_temp.acl_of(p_sig text) returns text language sql as $f$
  select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
create function pg_temp.audits(p_action text, p_reason text default null, p_by uuid default null) returns bigint language sql as $f$
  select count(*) from public.audit_logs
   where action = p_action and (p_reason is null or reason = p_reason) and (p_by is null or changed_by = p_by) $f$;
-- The scripts' constants, each declared once in its script as "c_name constant type := value;".
-- p_key: cp (step 2a), golive (step 2b), undo_golive (undo 2b), undo_cp (undo 2a), presale.
create function pg_temp.const_pat(p_name text) returns text language sql immutable as $f$
  select '\m' || p_name || '(\s+constant\s+)([a-z]+(\[\])?)(\s*:=\s*)([^;]*);' $f$;
create function pg_temp.const_count(p_key text, p_name text) returns int language sql as $f$
  select count(*)::int from regexp_matches(current_setting('t502g.' || p_key), pg_temp.const_pat(p_name), 'g') $f$;
create function pg_temp.const_of(p_key text, p_name text) returns text language plpgsql as $f$
declare n int := pg_temp.const_count(p_key, p_name);
begin
  if n <> 1 then
    raise exception 'T502G: % is declared % times in the script %, not once', p_name, n, p_key; end if;
  return btrim((regexp_match(current_setting('t502g.' || p_key), pg_temp.const_pat(p_name)))[5]);
end $f$;
-- Writes p_value into that constant, in this transaction's copy of the script only.
create function pg_temp.set_const(p_key text, p_name text, p_value text) returns void language plpgsql as $f$
declare n int := pg_temp.const_count(p_key, p_name);
begin
  if n <> 1 then
    raise exception 'T502G: % is declared % times in the script %, not once', p_name, n, p_key; end if;
  perform set_config('t502g.' || p_key,
    regexp_replace(current_setting('t502g.' || p_key), pg_temp.const_pat(p_name), p_name || '\1\2\4' || p_value || ';'), true);
  if pg_temp.const_of(p_key, p_name) is distinct from p_value then
    raise exception 'T502G: % in the script % could not be set to %', p_name, p_key, p_value; end if;
end $f$;
-- The go-live preview (scripts/therapy/golive-preview-502.sql): its one SELECT, as it stands, run
-- with public alone on the search path, as its own "set local" does. Its rows as jsonb; and the
-- figure ("now") of the row of that name.
create function pg_temp.preview() returns jsonb language plpgsql set search_path = public as $f$
declare t text := current_setting('t502g.preview'); q text; r jsonb;
begin
  q := (regexp_match(t, '\nbegin read only;\nset local search_path = public;[^\n]*\n(.*);\s*\nrollback;\s*$'))[1];
  if q is null or q !~ '^with\M' then
    raise exception 'T502G: scripts/therapy/golive-preview-502.sql is not "begin read only;", "set local search_path = public;", one SELECT and "rollback;"'; end if;
  execute format(E'select coalesce(jsonb_agg(to_jsonb(p) order by p.n), %L::jsonb) from (%s\n) p', '[]', q) into r;
  return r;
end $f$;
create function pg_temp.pv(p_rows jsonb, p_name text) returns text language sql as $f$
  select string_agg(x ->> 'now', ' | ') from jsonb_array_elements(p_rows) x where x ->> 'name' = p_name $f$;
-- The fixture's figures (production's on 10 Nov 2026), by constant, and the scripts holding each.
-- The suite writes them into those scripts' constants (C); the preview must give each (F).
create temp table t502g_fig(name text primary key, v text not null, files text[] not null);
insert into t502g_fig values
  ('c_packages', '3', '{cp,golive,undo_cp}'), ('c_kept_lines', '1', '{cp,golive,undo_cp,presale}'),
  ('c_kept_units', '1', '{cp,presale}'), ('c_threshold', '994', '{cp,presale}'), ('c_kept_price', '1000', '{cp,presale}'),
  ('c_vouchers_per_unit', '10', '{cp,presale}'),
  ('c_cust_rows', '102', '{golive}'), ('c_cust_people', '43', '{golive}'), ('c_aff_rows', '1', '{golive}'),
  ('c_aff_vouchers', '10', '{golive}'), ('c_rewards', '103', '{undo_golive}'), ('c_other', '60', '{golive}'),
  ('c_cp_rows', '10', '{golive}'), ('c_cp_vouchers', '100', '{golive}'), ('c_held_rows', '6', '{golive}'),
  ('c_held_qty', '50', '{golive}'), ('c_links', '67', '{golive}'), ('c_rules', '3', '{golive,undo_golive}'),
  ('c_rule_amount', '994', '{golive}'), ('c_bundles_on', '2', '{golive}'), ('c_bundles_off', '2', '{golive}');

-- ═════ C The scripts' constants ═════
-- As the files stand (what would run on production): the constants repeated across them agree.
do $c$
declare r record; vals text; same boolean;
begin
  for r in select * from t502g_fig where cardinality(files) > 1 order by name loop
    select string_agg(x || ' ' || pg_temp.const_of(x, r.name), ', ' order by x), count(distinct pg_temp.const_of(x, r.name)) = 1
      into vals, same from unnest(r.files) x;
    perform pg_temp.ok(same, 'C1 ' || r.name || ' is the same in every script holding it: ' || vals);
  end loop;
  perform pg_temp.ok(pg_temp.const_of('undo_golive', 'c_rewards')::int
                     = pg_temp.const_of('golive', 'c_cust_rows')::int + pg_temp.const_of('golive', 'c_aff_rows')::int,
    'C2 undo 2b''s c_rewards (' || pg_temp.const_of('undo_golive', 'c_rewards') || ') = step 2b''s c_cust_rows + c_aff_rows ('
    || pg_temp.const_of('golive', 'c_cust_rows') || ' + ' || pg_temp.const_of('golive', 'c_aff_rows') || ')');
  perform pg_temp.ok(pg_temp.const_of('cp', 'c_reason') = quote_literal(pg_temp.txt('cp'))
      and pg_temp.const_of('golive', 'c_cp_reason') = pg_temp.const_of('cp', 'c_reason')
      and pg_temp.const_of('presale', 'c_cp_reason') = pg_temp.const_of('cp', 'c_reason')
      and pg_temp.const_of('undo_cp', 'c_reason') = pg_temp.const_of('cp', 'c_reason')
      and pg_temp.const_of('golive', 'c_reason') = quote_literal(pg_temp.txt('golive'))
      and pg_temp.const_of('undo_golive', 'c_reason') = pg_temp.const_of('golive', 'c_reason')
      and pg_temp.const_of('undo_cp', 'c_golive_reason') = pg_temp.const_of('golive', 'c_reason')
      and pg_temp.const_of('golive', 'c_trg_after') = pg_temp.const_of('cp', 'c_trg_after')
      and pg_temp.const_of('undo_golive', 'c_trg_after') = pg_temp.const_of('cp', 'c_trg_after')
      and pg_temp.const_of('golive', 'c_cat_after') = pg_temp.const_of('cp', 'c_cat_after'),
    'C3 the reasons and 502''s md5s the scripts share are the same in each');
end $c$;
-- Then the fixture's figures go into every script's constants (here only): a constant missing or
-- declared twice, or a figure constant the suite does not set, stops the suite.
do $s$
declare r record; x text; extra text; n int := 0;
begin
  for r in select * from t502g_fig order by name loop
    foreach x in array r.files loop
      perform pg_temp.set_const(x, r.name, r.v);
      n := n + 1;
    end loop;
  end loop;
  foreach x in array array['cp', 'golive', 'undo_golive', 'undo_cp', 'presale'] loop
    select string_agg(m[1], ', ') into extra
      from regexp_matches(current_setting('t502g.' || x), '\m(c_[a-z0-9_]+)\s+constant\s+(int|integer|bigint|smallint|numeric)\M', 'g') m
     where not exists (select 1 from t502g_fig f where f.name = m[1] and x = any(f.files));
    if extra is not null then
      raise exception 'T502G: the script % declares figure constants the suite does not set: %', x, extra; end if;
  end loop;
  perform pg_temp.ok(n = 31, 'C4 the fixture''s figures are written into the scripts'' 31 figure constants, each declared once: ' || n);
end $s$;

-- ═════ 502 in ═════
-- On a copy at 501, 502 is installed here, inside this transaction.
do $in$
declare d text := pg_temp.md5_of('trg_create_therapy_on_paid()');
begin
  if d = '012ae4e305b9870fa5596f740c0427b9' then
    perform pg_temp.setkv('fp_before_502', to_jsonb(pg_temp.fp()));
    execute current_setting('t502g.mig');
  elsif d = '7b63da063576a5c952cc5abe6c53f13d' then
    -- production's functions at 501 (rc501_live), as undo-502.sql gives them back
    perform pg_temp.setkv('fp_before_502', to_jsonb('2a58a90a691a37a80b562ad41d546e98/1425'::text));
  else
    raise exception 'T502G: trg_create_therapy_on_paid() is neither 502''s nor the one before it (md5 %). Run this on a copy of production at 501, or with 502 in.', d;
  end if;
  if pg_temp.md5_of('trg_create_therapy_on_paid()') <> '7b63da063576a5c952cc5abe6c53f13d' then
    raise exception 'T502G: 502 is not in'; end if;
end $in$;

-- ═════ Clear what the scripts count ═════
-- In foreign-key order, inside this transaction only (the rollback brings it back). A copy of
-- lr502_with holds none of these rows.
do $clr$
begin
  -- Every Premium Bundle is counted; one already sold cannot be taken out here.
  if exists (select 1 from public.invoice_items where premium_bundle_id is not null)
     or exists (select 1 from public.premium_bundle_sales) or exists (select 1 from public.premium_bundle_split_groups) then
    raise exception 'T502G: this database holds sold Premium Bundles, which the go-live step counts. Run the suite on a copy of lr502_with.'; end if;
  -- The scripts' own Audit Log rows, which they read to know what has run.
  delete from public.audit_logs
   where action in ('credit_package_reward_switched_off', 'credit_package_reward_switched_on',
                    'credit_package_reward_kept_for_earlier_sale', 'credit_package_reward_kept_for_earlier_sale_undone',
                    'credit_package_earlier_sale_reward_given', 'legacy_reward_cancelled', 'legacy_reward_cancel_undone',
                    'legacy_rule_switched_off', 'legacy_rule_switched_on', 'legacy_therapy_retired', 'legacy_therapy_retired_undone');
  delete from public.therapy_entitlement_invoices;
  -- Vouchers handed over stay with their customers; they no longer point at a reward.
  update public.customer_reward_vouchers set entitlement_id = null where entitlement_id is not null;
  update public.invoices set voucher_claim_entitlement_id = null where voucher_claim_entitlement_id is not null;
  update public.purchased_therapy_entitlements set voucher_entitlement_id = null where voucher_entitlement_id is not null;
  update public.therapy_qualification_topups set entitlement_id = null where entitlement_id is not null;
  delete from public.therapy_entitlements;      -- their claims and beneficiaries go with them
  delete from public.therapy_package_rules;
  -- No package gives reward vouchers, so no line of one is an earlier sale owed a reward.
  update public.credit_packages set grants_reward = false where grants_reward;
  delete from public.premium_bundles;           -- their stores and voucher lists go with them
end $clr$;

-- ═════ Fixture: production's shape on 10 Nov 2026, invented ═════
do $fx$
declare
  r record; u uuid; t text; i int; j int; c uuid; e uuid; inv uuid; st uuid; k text; n int;
  own uuid; mgr uuid; stf uuid; sa uuid; sb uuid;
begin
  -- People: an Owner, a Manager, a member of staff, a Manager switched off.
  for r in select * from (values ('own', 'owner', true), ('mgr', 'manager', true), ('stf', 'staff', true), ('gone', 'manager', false)) as x(k, role, active) loop
    insert into auth.users (id, email) values (gen_random_uuid(), 't502g-' || r.k || '@example.invalid') returning id into u;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (u, 'T502G ' || r.k, 't502g-' || r.k || '@example.invalid', r.role::public.user_role, r.active);
    perform pg_temp.put(r.k, u);
  end loop;
  own := pg_temp.id('own'); mgr := pg_temp.id('mgr'); stf := pg_temp.id('stf');
  insert into public.stores (name, code, country_code) values ('T502G Store A', 'T502G-A', 'SG') returning id into sa;
  insert into public.stores (name, code, country_code) values ('T502G Store B', 'T502G-B', 'SG') returning id into sb;
  perform pg_temp.put('sa', sa); perform pg_temp.put('sb', sb);
  insert into public.user_store_assignments (user_id, store_id)
    select p, s from unnest(array[mgr, stf, pg_temp.id('gone')]) p, unnest(array[sa, sb]) s;
  insert into public.payment_methods (name, is_active) values ('T502G Cash', true) returning id into u; perform pg_temp.put('pm', u);
  for i in 1 .. 3 loop
    insert into public.vouchers (name, code, voucher_kind, qty_type, selling_price, is_active, reward_eligible)
    values ('T502G Voucher ' || i, 'T502G-V' || i, 'normal', 'unlimited', 40 + 10 * i, true, true) returning id into u;
    perform pg_temp.put('v' || i, u);
  end loop;

  -- The 3 qualification rules, all stores, S$994 (the rule form's function, as the Owner).
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform pg_temp.put('r1', public.upsert_legacy_rule(null, null, 'T502G one month', 994, 'unlimited', 1, null, 365, true, public.sg_today() - 400, 'customer'));
  perform pg_temp.put('r2', public.upsert_legacy_rule(null, null, 'T502G ten vouchers', 994, 'voucher', null, 10, 365, true, public.sg_today() - 300, 'customer'));
  perform pg_temp.put('r3', public.upsert_legacy_rule(null, null, 'T502G affiliate vouchers', 994, 'voucher', null, 10, 365, true, public.sg_today() - 300, 'affiliate'));

  -- The 3 Credit Packages (the Credit Package window, as the Owner), each to be taken as 2 vouchers.
  for r in select * from (values ('cp1000', 1000), ('cp3000', 3000), ('cp5000', 5000)) as x(k, price) loop
    t := pg_temp.try_as(own, format('select public.upsert_credit_package(null, %L, %s, %s, true, %L::date, null, %L, true, null, null, null, null, null, %L::uuid[], %L::uuid[], true)::text',
      'T502G Package ' || r.price, r.price, r.price, public.sg_today() - 200, 'third_party', array[sa, sb], array[pg_temp.id('v1'), pg_temp.id('v2')]));
    if t not like 'ok:%' then raise exception 'T502G fixture: the Credit Package window refused: %', t; end if;
    perform pg_temp.put(r.k, substr(t, 4)::uuid);
  end loop;
  -- Made before 502, they give reward vouchers (502 makes a new one without, and will not switch it on).
  update public.credit_packages set grants_reward = true where id in (pg_temp.id('cp1000'), pg_temp.id('cp3000'), pg_temp.id('cp5000'));

  -- The 4 Premium Bundles (the Premium Bundle window, as the Owner), S$994 each, 2 with the reward on.
  for r in select * from (values ('b15000', 15000, true), ('b30000', 30000, true), ('b2000', 2000, false), ('b8000', 8000, false)) as x(k, price, reward) loop
    t := pg_temp.try_as(own, format('select public.upsert_premium_bundle(null, %L, %s, %s, 0, null, 994, true, %L::date, null, %L, true, null, null, null, null, %L::uuid[], %L::uuid[])::text',
      'T502G Bundle ' || r.price, r.price, r.price, public.sg_today() - 100, 'third_party', array[sa, sb], array[pg_temp.id('v1'), pg_temp.id('v2')]));
    if t not like 'ok:%' then raise exception 'T502G fixture: the Premium Bundle window refused: %', t; end if;
    perform pg_temp.put(r.k, substr(t, 4)::uuid);
    t := pg_temp.try_as(own, format('select public.set_catalogue_reward(%L, %L::uuid, %L::boolean)::text', 'premium_bundle', pg_temp.id(r.k), r.reward));
    if t not like 'ok:%' then raise exception 'T502G fixture: the bundle''s reward setting refused: %', t; end if;
  end loop;

  -- W: 102 one-month rewards waiting, for 43 customers at 2 stores (L01 to L16 three each, the
  -- rest two each); 45 linked to their day's invoice (each customer's first, and L01's and L02's second).
  n := 0;
  for i in 1 .. 43 loop
    k := 'L' || lpad(i::text, 2, '0');
    c := pg_temp.cust(k);
    st := case when i <= 20 then sa else sb end;
    for j in 1 .. case when i <= 16 then 3 else 2 end loop
      n := n + 1;
      e := pg_temp.ent('T502G-W-' || lpad(n::text, 3, '0'), c, st, pg_temp.id('r1'), 'Unlimited Therapy (1 month)', 'unlimited', null,
                       'pending_activation', 'customer', public.sg_today() + 270 + n, 994 + 10 * j);
      if j = 1 or (j = 2 and i <= 2) then perform pg_temp.link(e, c, st); end if;
    end loop;
  end loop;
  -- The affiliate reward waiting: 10 vouchers, no voucher list, no sale.
  c := pg_temp.cust('AF1');
  perform pg_temp.put('af1_row', pg_temp.ent('T502G-AF-1', c, sa, pg_temp.id('r3'), 'Affiliate reward: 10 vouchers', 'voucher', 10,
                                             'pending_activation', 'affiliate', public.sg_today() + 344));
  -- 53 months cancelled, for 10 customers, 15 of them linked.
  n := 0;
  for i in 1 .. 10 loop
    k := 'C' || lpad(i::text, 2, '0');
    c := pg_temp.cust(k);
    st := case when i <= 5 then sa else sb end;
    for j in 1 .. case when i <= 3 then 6 else 5 end loop
      n := n + 1;
      e := pg_temp.ent('T502G-C-' || lpad(n::text, 2, '0'), c, st, pg_temp.id('r1'), 'Unlimited Therapy (1 month)', 'unlimited', null,
                       'cancelled', 'customer', public.sg_today() + 100 + n);
      if n <= 15 then perform pg_temp.link(e, c, st); end if;
    end loop;
  end loop;
  -- The only month ever used, its day's 2 invoices linked.
  c := pg_temp.cust('X1');
  e := pg_temp.ent('T502G-X-1', c, sa, pg_temp.id('r1'), 'Unlimited Therapy (1 month)', 'unlimited', null, 'expired', 'customer',
                   public.sg_today() + 300, 1131);
  update public.therapy_entitlements
     set activation_date = public.sg_today() - 57, expiry_date = public.sg_today() - 28, claimed_by = own, claimed_at = now() - interval '57 days'
   where id = e;
  perform pg_temp.put('x1_row', e);
  perform pg_temp.link(e, c, sa); perform pg_temp.link(e, c, sa);
  -- 5 voucher rewards handed over in August to 3 customers: 6 vouchers held, 50 in all; 5 linked.
  perform pg_temp.cust('H1'); perform pg_temp.cust('H2'); perform pg_temp.cust('H3');
  for r in select * from (values (1, 'H1', 10, 0), (2, 'H1', 5, 5), (3, 'H2', 10, 0), (4, 'H2', 10, 0), (5, 'H3', 10, 0)) as x(n, who, q1, q2) loop
    c := pg_temp.id(r.who);
    e := pg_temp.ent('T502G-H-' || r.n, c, sa, pg_temp.id('r2'), 'Reward: 10 vouchers', 'voucher', 10, 'active', 'customer', public.sg_today() + 280);
    update public.therapy_entitlements set activation_date = public.sg_today() - 90, claimed_by = own, claimed_at = now() - interval '90 days' where id = e;
    insert into public.customer_reward_vouchers (customer_id, voucher_id, entitlement_id, store_id, quantity, status, issued_by, notes, source_type, source_id)
    values (c, pg_temp.id('v1'), e, sa, r.q1, 'held', own, 'T502G handed over in August', 'legacy_entitlement', e);
    if r.q2 > 0 then
      insert into public.customer_reward_vouchers (customer_id, voucher_id, entitlement_id, store_id, quantity, status, issued_by, notes, source_type, source_id)
      values (c, pg_temp.id('v2'), e, sa, r.q2, 'held', own, 'T502G handed over in August', 'legacy_entitlement', e);
    end if;
    perform pg_temp.link(e, c, sa);
  end loop;
  -- An affiliate reward cancelled before.
  c := pg_temp.cust('AF2');
  perform pg_temp.ent('T502G-AF-2', c, sb, pg_temp.id('r3'), 'Affiliate reward: 10 vouchers', 'voucher', 10, 'cancelled', 'affiliate', public.sg_today() + 200);
  -- 2 older Credit Package rewards, cancelled, with no source recorded.
  foreach k in array array['Q1', 'Q2'] loop
    c := pg_temp.cust(k);
    perform pg_temp.ent('T502G-' || k, c, sa, null, 'Credit package reward — T502G Package 3000', 'voucher', 15, 'cancelled', 'credit_package', public.sg_today() + 150);
  end loop;

  -- 2 S$5,000 Credit Packages sold and paid in full by staff: 5 rewards of 10 vouchers each.
  foreach k in array array['P1', 'P2'] loop
    c := pg_temp.cust(k);
    inv := pg_temp.put('inv_' || k, pg_temp.sell(stf, case k when 'P1' then sa else sb end, c, pg_temp.id('cp5000')));
    t := pg_temp.pay(stf, inv, 5000);
    if t not like 'ok:%' then raise exception 'T502G fixture: paying % was refused: %', k, t; end if;
  end loop;
  -- The earlier sale: the S$1,000 package sold by staff, S$500 paid.
  c := pg_temp.cust('K1');
  inv := pg_temp.put('inv_K1', pg_temp.sell(stf, sa, c, pg_temp.id('cp1000')));
  t := pg_temp.pay(stf, inv, 500);
  if t not like 'ok:%' then raise exception 'T502G fixture: the part payment was refused: %', t; end if;
  perform pg_temp.put('line_K1', (select id from public.invoice_items where invoice_id = inv));
  -- For later: a new buyer (G4), and one who would buy a second package before go-live (G1).
  perform pg_temp.cust('N1'); perform pg_temp.cust('K2');
end $fx$;

-- ═════ F The fixture reads as production did on 10 Nov 2026 ═════
do $f$
declare inv uuid := pg_temp.id('inv_K1'); line uuid := pg_temp.id('line_K1'); pv jsonb; bad text;
  c_2a_in constant text[] := array['2a in: Credit Packages with the reward on', '2a in: packages step 2a switched off, not undone (= c_packages)',
                                   '2a in: earlier sales step 2a kept, not undone (= c_kept_lines)'];
begin
  -- The go-live preview (scripts/therapy/golive-preview-502.sql), as it is run just before go-live.
  pv := pg_temp.preview();
  bad := (select string_agg(f.name || ': ' || coalesce(pg_temp.pv(c.rows, f.name), 'no row') || ' (fixture ' || f.v || ')', '; ' order by f.name)
            from t502g_fig f
           cross join (select coalesce(jsonb_agg(x), '[]'::jsonb) as rows from jsonb_array_elements(pv) x where x ->> 'kind' = 'constant') c
           where (select count(*) from jsonb_array_elements(c.rows) y where y ->> 'name' = f.name) <> 1
              or pg_temp.pv(c.rows, f.name) is distinct from f.v);
  perform pg_temp.ok(bad is null, 'F1 the go-live preview gives each constant, in one row, the fixture''s figure (production''s on 10 Nov 2026): '
                                  || coalesce(bad, 'all ' || (select count(*) from t502g_fig) || ' do'));
  bad := (select string_agg(x ->> 'name', '; ') from jsonb_array_elements(pv) x
           where x ->> 'kind' = 'constant' and not exists (select 1 from t502g_fig f where f.name = x ->> 'name'));
  perform pg_temp.ok(bad is null, 'F1b and it has no constant row the scripts do not have: ' || coalesce(bad, 'none'));
  bad := (select string_agg((x ->> 'name') || ' = ' || (x ->> 'now'), '; ') from jsonb_array_elements(pv) x
           where x ->> 'kind' in ('stop', 'check') and (x ->> 'ok')::boolean is not true
             and not (x ->> 'name' = any(c_2a_in)) and x ->> 'name' <> 'newest migration in the history');
  perform pg_temp.ok(bad is null and (select count(*) from jsonb_array_elements(pv) x where x ->> 'kind' = 'stop') = 11,
    'F1c all 11 stop signs are clear, and every check holds but the "2a in" rows (502 in, the functions relied on, not run yet, an Owner or Manager): '
    || coalesce(bad, 'all'));
  perform pg_temp.ok(pg_temp.pv(pv, c_2a_in[1]) = '3' and pg_temp.pv(pv, c_2a_in[2]) = '0' and pg_temp.pv(pv, c_2a_in[3]) = '0'
      and pg_temp.pv(pv, 'therapy_entitlements rows') = '175'
      and pg_temp.pv(pv, 'earlier sale 1: sold on / paid / total / status / collect-by days / months / voucher choices')
          = public.sg_today()::text || ' / 500 / 1000 / partially_paid / 365 / 1 / 2',
    'F1d before step 2a, its "2a in" rows read 3 / 0 / 0; 175 reward rows; the earlier sale: S$500 of S$1,000 paid, 365 days, 1 month, 2 voucher choices');
  perform pg_temp.ok((select count(distinct store_id) from public.therapy_entitlements where status = 'pending_activation' and earner_kind = 'customer') = 2
      and (select count(*) from public.therapy_entitlements e where e.status = 'pending_activation' and e.earner_kind = 'customer'
             and exists (select 1 from public.therapy_entitlement_invoices t where t.entitlement_id = e.id)) = 45,
    'F2 the 102 are at 2 stores, 45 of them linked to their day''s invoice');
  perform pg_temp.ok((select status::text from public.invoices where id = inv) = 'partially_paid'
      and (select paid_amount from public.invoices where id = inv) = 500 and (select total_amount from public.invoices where id = inv) = 1000
      and (select credit_issued_at from public.invoice_items where id = line) is null
      and (select line_kind::text from public.invoice_items where id = line) = 'credit_package'
      and (select credit_split_group_id from public.invoice_items where id = line) is null,
    'F3 the earlier sale: an ordinary S$1,000 Credit Package line, S$500 paid, its credit not given yet');
  perform pg_temp.ok((select count(*) from public.credit_package_sales s where s.invoice_id in (pg_temp.id('inv_P1'), pg_temp.id('inv_P2')) and s.reward_units = 5) = 2
      and (select count(*) from public.therapy_entitlements e where e.earner_kind = 'credit_package' and e.status = 'pending_activation'
             and e.claim_source_invoice_id in (pg_temp.id('inv_P1'), pg_temp.id('inv_P2')) and cardinality(e.eligible_voucher_ids) = 2
             and e.qualifying_amount = 994 and e.voucher_qty = 10) = 10,
    'F4 the 2 paid S$5,000 sales gave 5 rewards each, each with its sale, 2 voucher choices and S$994');
end $f$;

-- ═════ G1 Refusals: each changes nothing ═════
do $g1$
declare
  own uuid := pg_temp.id('own'); stf uuid := pg_temp.id('stf'); gone uuid := pg_temp.id('gone');
  f jsonb := pg_temp.fp_parts(); f2 jsonb; e text; e2 text; e3 text; x text; d text; t text; inv uuid;
  pv jsonb; sp jsonb; t1 text; t2 text;
  c_split_row constant text := 'sales split between customers, not yet paid off, still carrying reward vouchers';
  -- The Credit Package window's split (as staff): the S$3,000 package between 2 customers, its 30
  -- reward vouchers set aside on their 2 invoices (20 and 10), none paid yet.
  c_split constant text := format('select public.create_split_credit_package_invoices(%L::uuid, %L::uuid, %L::jsonb, null, null, %L, gen_random_uuid())::text',
    pg_temp.id('sa'), pg_temp.id('cp3000'),
    jsonb_build_array(jsonb_build_object('customer_id', pg_temp.id('K2'), 'payment_amount', 2000, 'reward_voucher_qty', 20),
                      jsonb_build_object('customer_id', pg_temp.id('N1'), 'payment_amount', 1000, 'reward_voucher_qty', 10)),
    'T502G split');
begin
  -- Who records it.
  e := pg_temp.run(null, 't502g.cp');
  perform pg_temp.ok(e like 'P0001:502 credit only: set the recording account (an active Owner or Manager) first%', 'G1a nobody recording it: step 2a refuses: ' || e);
  e := pg_temp.run(stf, 't502g.cp');
  perform pg_temp.ok(e like 'P0001:502 credit only: set the recording account%', 'G1b a member of staff who is not an Owner or Manager: step 2a refuses: ' || e);
  e := pg_temp.run(gone, 't502g.cp');
  perform pg_temp.ok(e like 'P0001:502 credit only: set the recording account%', 'G1c a Manager switched off: step 2a refuses: ' || e);
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
    execute current_setting('t502g.cp');
    e := 'it ran';
  exception when others then e := sqlerrm; end;
  perform pg_temp.ok(e like '502 credit only: set the recording account%', 'G1d the Owner set in request.jwt.claims alone: step 2a refuses: ' || e);
  e := pg_temp.run(null, 't502g.golive'); e2 := pg_temp.run(stf, 't502g.golive');
  perform pg_temp.ok(e like 'P0001:502 go-live: set the recording account%' and e2 like 'P0001:502 go-live: set the recording account%',
    'G1e step 2b refuses nobody, and staff: ' || e || ' / ' || e2);
  e := pg_temp.run(stf, 't502g.presale'); e2 := pg_temp.run(stf, 't502g.undo_golive'); e3 := pg_temp.run(stf, 't502g.undo_cp');
  perform pg_temp.ok(e like 'P0001:502 earlier sale: set the recording account%' and e2 like 'P0001:UNDO 502 go-live: set the recording account%'
      and e3 like 'P0001:UNDO 502 credit only: set the recording account%',
    'G1f so do the earlier-sale script and the two UNDOs, for staff: ' || e || ' / ' || e2 || ' / ' || e3);
  perform pg_temp.ok(pg_temp.fp_parts() = f, 'G1g none of these changed anything (changed: ' || pg_temp.fp_diff(f, pg_temp.fp_parts()) || ')');

  -- 502 not in (each in a savepoint, undone).
  begin
    execute 'create trigger legacy_refund_guard before update on public.invoices for each row execute function public.trg_legacy_refund_guard()';
    e := pg_temp.run(own, 't502g.cp'); e2 := pg_temp.run(own, 't502g.golive');
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e like 'P0001:502 credit only: migration 502 is not in%' and e2 like 'P0001:502 go-live: migration 502 is not in%',
    'G1h the refund guard back on invoices: both steps refuse: ' || e || ' / ' || e2);
  begin
    d := pg_get_functiondef('public.trg_create_therapy_on_paid()'::regprocedure);
    if strpos(d, '-- 502 (the user, 10 Nov 2026): Legacy Therapy is retired.') = 0 then raise exception 'T502G: anchor not found'; end if;
    execute replace(d, '-- 502 (the user, 10 Nov 2026): Legacy Therapy is retired.', '-- changed since: Legacy Therapy is retired.');
    e := pg_temp.run(own, 't502g.cp'); e2 := pg_temp.run(own, 't502g.golive');
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e like 'P0001:502 credit only: migration 502 is not in%' and e2 like 'P0001:502 go-live: migration 502 is not in%',
    'G1i trg_create_therapy_on_paid() other than 502''s: both steps refuse: ' || e || ' / ' || e2);
  begin
    d := pg_get_functiondef('public.set_catalogue_reward(text,uuid,boolean)'::regprocedure);
    if strpos(d, '-- 502 (the user, 10 Nov 2026): a Credit Package gives credit only.') = 0 then raise exception 'T502G: anchor not found'; end if;
    execute replace(d, '-- 502 (the user, 10 Nov 2026): a Credit Package gives credit only.', '-- changed since: a Credit Package gives credit only.');
    e := pg_temp.run(own, 't502g.cp'); e2 := pg_temp.run(own, 't502g.golive');
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e like 'P0001:502 credit only: migration 502 is not in%' and e2 like 'P0001:502 go-live: migration 502 is not in%',
    'G1j set_catalogue_reward other than 502''s: both steps refuse: ' || e || ' / ' || e2);
  begin
    d := pg_get_functiondef('public.issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)'::regprocedure);
    if strpos(d, '-- Bonus Credit, spendable on everything ordinary.') = 0 then raise exception 'T502G: anchor not found'; end if;
    execute replace(d, '-- Bonus Credit, spendable on everything ordinary.', '-- Bonus Credit, spendable on anything ordinary.');
    e := pg_temp.run(own, 't502g.cp');
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e like 'P0001:502 credit only: public.issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid) is not the version this was tested against%',
    'G1k the Credit Package issuer other than as read: step 2a refuses: ' || e);

  -- Not as read on 10 Nov 2026 (each in a savepoint, undone).
  begin
    inv := pg_temp.sell(stf, pg_temp.id('sa'), pg_temp.id('K2'), pg_temp.id('cp3000'));
    t := pg_temp.pay(stf, inv, 1000);
    f2 := pg_temp.fp_parts(); e := pg_temp.run(own, 't502g.cp'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(t like 'ok:%' and e like 'P0001:502 credit only: found 2 Credit Package sales not yet paid off that would give reward vouchers, not 1%' and x = 'none',
    'G1l a second sale not yet paid off (S$1,000 of a S$3,000 package): step 2a refuses, changing nothing: ' || e || ' (changed: ' || x || ')');
  begin
    t := pg_temp.pay(stf, pg_temp.id('inv_K1'), 500);
    f2 := pg_temp.fp_parts(); e := pg_temp.run(own, 't502g.cp'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(t like 'ok:%' and e like 'P0001:502 credit only: found 0 Credit Package sales not yet paid off%' and x = 'none',
    'G1m the earlier sale paid off before go-live (its reward given the old way): step 2a refuses: ' || e || ' (changed: ' || x || ')');
  begin
    t := pg_temp.try_as(own, format('select public.upsert_credit_package(null, %L, 2000, 2000, true, %L::date, null, %L)::text',
                                    'T502G Package 2000', public.sg_today(), 'third_party'));
    update public.credit_packages set grants_reward = true where id = substr(t, 4)::uuid;
    f2 := pg_temp.fp_parts(); e := pg_temp.run(own, 't502g.cp'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(t like 'ok:%' and e like 'P0001:502 credit only: 4 Credit Packages give reward vouchers (0 of them deleted), not 3%' and x = 'none',
    'G1n a fourth package with the reward on: step 2a refuses: ' || e || ' (changed: ' || x || ')');
  begin
    update public.credit_packages set deleted_at = now() where id = pg_temp.id('cp3000');
    f2 := pg_temp.fp_parts(); e := pg_temp.run(own, 't502g.cp'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e like 'P0001:502 credit only: 3 Credit Packages give reward vouchers (1 of them deleted), not 3%' and x = 'none',
    'G1o a deleted package still with the reward on: step 2a refuses: ' || e || ' (changed: ' || x || ')');

  begin
    perform set_config('request.jwt.claim.sub', own::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
    perform public.upsert_legacy_rule(null, null, 'T502G cheaper rule', 500, 'unlimited', 1, null, 365, true, public.sg_today() - 1, 'customer');
    f2 := pg_temp.fp_parts(); e := pg_temp.run(own, 't502g.cp'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e like 'P0001:502 credit only: the earlier sale on invoice % would give 2 reward(s) for S$500.00 each on a S$1000.00 package, not 1 for S$994 on S$1000 as on 10 Nov 2026%' and x = 'none',
    'G1o2 a cheaper rule in reach (S$500): the earlier sale would give 2 rewards: step 2a refuses: ' || e || ' (changed: ' || x || ')');

  -- A sale split between 2 customers before go-live, not yet paid off: paid off later, each
  -- invoice would still give the vouchers set aside on it, whatever the package says (each in a
  -- savepoint, undone).
  begin
    t := pg_temp.try_as(stf, c_split);
    pv := pg_temp.preview();
    f2 := pg_temp.fp_parts(); e := pg_temp.run(own, 't502g.cp'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  sp := case when t like 'ok:%' then substr(t, 4)::jsonb end;
  perform pg_temp.ok(t like 'ok:%' and (sp ->> 'reward_voucher_total')::int = 30 and jsonb_array_length(sp -> 'invoices') = 2
      and e like 'P0001:502 credit only: 1 Credit Package sale(s) split between customers and not yet paid off still carry reward vouchers (on invoice(s) '
                 || (select string_agg(y ->> 'invoice_no', ', ' order by y ->> 'invoice_no') from jsonb_array_elements(sp -> 'invoices') y)
                 || '). Paid off after go-live, they would still give those vouchers. Ask the user what to do. Nothing changed.'
      and x = 'none' and pg_temp.pv(pv, c_split_row) = '1',
    'G1o3 a S$3,000 sale split between 2 customers, its 30 reward vouchers set aside, not yet paid off: step 2a refuses, counting 1 sale and naming both invoices, changing nothing; the preview shows 1: '
    || e || ' (changed: ' || x || ')');
  begin
    t := pg_temp.try_as(stf, c_split);
    sp := substr(t, 4)::jsonb;
    update public.invoices set deleted_at = now() where id = (sp -> 'invoices' -> 0 ->> 'invoice_id')::uuid;
    update public.invoices set status = 'cancelled' where id = (sp -> 'invoices' -> 1 ->> 'invoice_id')::uuid;
    pv := pg_temp.preview();
    e := pg_temp.run(own, 't502g.cp');
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(t like 'ok:%' and e = 'ok' and pg_temp.pv(pv, c_split_row) = '0'
      and pg_temp.pv(pv, 'sales split between customers, carrying reward vouchers, on deleted invoices') = '1',
    'G1o4 the same split with one invoice deleted and the other cancelled does not stop step 2a; the preview lists the deleted one for reading: ' || e);
  begin
    t := pg_temp.try_as(stf, c_split);
    sp := substr(t, 4)::jsonb;
    t1 := pg_temp.pay(stf, (sp -> 'invoices' -> 0 ->> 'invoice_id')::uuid, 2000);
    t2 := pg_temp.pay(stf, (sp -> 'invoices' -> 1 ->> 'invoice_id')::uuid, 1000);
    d := (select string_agg(te.voucher_qty::text, '+' order by te.voucher_qty) from public.therapy_entitlements te
           where te.customer_id in (pg_temp.id('K2'), pg_temp.id('N1')) and te.earner_kind = 'credit_package');
    e := pg_temp.run(own, 't502g.cp');
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(t like 'ok:%' and t1 like 'ok:%' and t2 like 'ok:%' and d = '10+20' and e = 'ok',
    'G1o5 the same split paid off before go-live (its 20 and 10 vouchers given the old way) does not stop step 2a: ' || e || ' (vouchers ' || coalesce(d, 'none') || ')');

  -- In the wrong order, or with nothing to do.
  e := pg_temp.run(own, 't502g.golive');
  perform pg_temp.ok(e like 'P0001:502 go-live: run scripts/therapy/credit-package-credit-only-502.sql first%', 'G1p step 2b before step 2a: refused: ' || e);
  e := pg_temp.run(own, 't502g.presale');
  perform pg_temp.ok(e like 'P0001:502 earlier sale: there is no earlier sale to give a reward to%', 'G1q the earlier-sale script before step 2a: refused: ' || e);
  e := pg_temp.run(own, 't502g.undo_golive'); e2 := pg_temp.run(own, 't502g.undo_cp');
  perform pg_temp.ok(e like 'P0001:UNDO 502 go-live: found 0 rewards cancelled by the go-live step%' and e2 like 'P0001:UNDO 502 credit only: found 0 Credit Packages%',
    'G1r the two UNDOs with nothing to undo: refused: ' || e || ' / ' || e2);

  -- Step 2b, with step 2a in, on what is not as read on 10 Nov 2026 (each in a savepoint, undone).
  begin
    e := pg_temp.run(own, 't502g.cp');
    perform pg_temp.ent('T502G-W-103', pg_temp.id('L01'), pg_temp.id('sa'), pg_temp.id('r1'), 'Unlimited Therapy (1 month)', 'unlimited', null,
                        'pending_activation', 'customer', public.sg_today() + 380);
    pv := pg_temp.preview();
    f2 := pg_temp.fp_parts(); e2 := pg_temp.run(own, 't502g.golive'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e = 'ok' and e2 like 'P0001:502 go-live: production is not as read on 10 Nov 2026%' and x = 'none'
      and pg_temp.pv(pv, 'c_cust_rows') = '103' and pg_temp.pv(pv, 'c_rewards') = '104',
    'G1s one more Legacy reward waiting: step 2b refuses, changing nothing; the preview shows c_cust_rows 103, c_rewards 104: ' || e2 || ' (changed: ' || x || ')');
  begin
    e := pg_temp.run(own, 't502g.cp');
    update public.therapy_entitlements set status = 'scheduled' where id = pg_temp.id('x1_row');
    pv := pg_temp.preview();
    f2 := pg_temp.fp_parts(); e2 := pg_temp.run(own, 't502g.golive'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e = 'ok' and e2 like 'P0001:502 go-live: production is not as read on 10 Nov 2026%' and x = 'none'
      and pg_temp.pv(pv, 'Legacy month booked (scheduled) or running (active)') = '1',
    'G1t a Legacy month booked (scheduled): step 2b refuses; the preview shows it as a stop sign: ' || e2 || ' (changed: ' || x || ')');
  begin
    e := pg_temp.run(own, 't502g.cp');
    perform public.upsert_legacy_rule(null, null, 'T502G fourth rule', 994, 'voucher', null, 5, 365, true, public.sg_today(), 'customer');
    pv := pg_temp.preview();
    f2 := pg_temp.fp_parts(); e2 := pg_temp.run(own, 't502g.golive'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e = 'ok' and e2 like 'P0001:502 go-live: production is not as read on 10 Nov 2026%' and x = 'none'
      and pg_temp.pv(pv, 'c_rules') = '4',
    'G1u a fourth rule on: step 2b refuses; the preview shows c_rules 4: ' || e2 || ' (changed: ' || x || ')');
  begin
    e := pg_temp.run(own, 't502g.cp');
    insert into public.customer_reward_vouchers (customer_id, voucher_id, entitlement_id, store_id, quantity, status, issued_by, notes, source_type, source_id)
    select h.customer_id, pg_temp.id('v1'), h.id, h.store_id, 1, 'held', own, 'T502G one more', 'legacy_entitlement', h.id
      from public.therapy_entitlements h where h.entitlement_no = 'T502G-H-1';
    pv := pg_temp.preview();
    f2 := pg_temp.fp_parts(); e2 := pg_temp.run(own, 't502g.golive'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e = 'ok' and e2 like 'P0001:502 go-live: production is not as read on 10 Nov 2026%' and x = 'none'
      and pg_temp.pv(pv, 'c_held_rows') = '7' and pg_temp.pv(pv, 'c_held_qty') = '51',
    'G1v one more voucher handed over from a Legacy reward: step 2b refuses; the preview shows c_held_rows 7, c_held_qty 51: ' || e2 || ' (changed: ' || x || ')');
  -- A hand-over recorded while step 2b runs, after it read the rewards and before it cancels the
  -- last of them (here: when it writes its first Audit Log row, a voucher is recorded as handed
  -- over from the reward it cancels last). Its cancel finds that reward changed and refuses.
  begin
    e := pg_temp.run(own, 't502g.cp');
    create function public.t502g_hand_over_meanwhile() returns trigger language plpgsql as $h$
    declare v record;
    begin
      if not exists (select 1 from public.voucher_claims where note = 'T502G meanwhile') then
        select te.id, te.customer_id, te.store_id into v from public.therapy_entitlements te
         where te.status = 'pending_activation' and te.earner_kind in ('customer', 'affiliate')
         order by te.created_at desc, te.id desc limit 1;
        insert into public.voucher_claims (entitlement_id, customer_id, store_id, quantity, selections, note)
        values (v.id, v.customer_id, v.store_id, 1, '[]'::jsonb, 'T502G meanwhile');
      end if;
      return null;
    end $h$;
    create trigger t502g_hand_over_meanwhile after insert on public.audit_logs for each row
      when (new.action = 'legacy_reward_cancelled') execute function public.t502g_hand_over_meanwhile();
    d := (select te.entitlement_no from public.therapy_entitlements te
           where te.status = 'pending_activation' and te.earner_kind in ('customer', 'affiliate')
           order by te.created_at desc, te.id desc limit 1);
    f2 := pg_temp.fp_parts(); e2 := pg_temp.run(own, 't502g.golive'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null; end;
  perform pg_temp.ok(e = 'ok' and e2 = 'P0001:502 go-live: ' || d || ' changed while this ran (claimed, or vouchers handed over from it). Nothing changed.'
      and x = 'none',
    'G1v2 a voucher handed over from a reward while step 2b runs: its cancel refuses, naming it, changing nothing: ' || e2 || ' (changed: ' || x || ')');

  perform pg_temp.ok(pg_temp.fp_parts() = f, 'G1w after every refusal, everything is as the fixture left it (changed: ' || pg_temp.fp_diff(f, pg_temp.fp_parts()) || ')');
end $g1$;

-- ═════ G2 Step 2a: Credit Packages give credit only; the earlier sale kept ═════
do $g2$
declare
  own uuid := pg_temp.id('own'); mgr uuid := pg_temp.id('mgr'); stf uuid := pg_temp.id('stf');
  cp1000 uuid := pg_temp.id('cp1000'); inv uuid := pg_temp.id('inv_K1'); line uuid := pg_temp.id('line_K1');
  f0 jsonb := pg_temp.fp_parts(); f1 jsonb; e text; t text; k public.audit_logs%rowtype; v jsonb; act jsonb; x jsonb; s jsonb; pv jsonb;
  pk_rest text := pg_temp.fp_q('select to_jsonb(p) - ''grants_reward'' - ''updated_at'' from public.credit_packages p');
begin
  perform pg_temp.setkv('S0', f0);
  e := pg_temp.run(mgr, 't502g.cp');
  perform pg_temp.ok(e = 'ok', 'G2a step 2a runs, recorded by a Manager: ' || e);
  f1 := pg_temp.fp_parts();
  perform pg_temp.setkv('S1', f1);
  perform pg_temp.ok(not exists (select 1 from public.credit_packages where grants_reward)
      and (select count(*) from public.credit_packages where id in (cp1000, pg_temp.id('cp3000'), pg_temp.id('cp5000')) and not grants_reward) = 3,
    'G2b none of the 3 Credit Packages gives reward vouchers now');
  perform pg_temp.ok(pk_rest = pg_temp.fp_q('select to_jsonb(p) - ''grants_reward'' - ''updated_at'' from public.credit_packages p'),
    'G2c nothing else in them changed');
  perform pg_temp.ok(pg_temp.fp_diff(f0, f1) = 'audit_logs, credit_packages',
    'G2d nothing else changed: no reward, rule, sale, invoice or credit (changed: ' || pg_temp.fp_diff(f0, f1) || ')');
  perform pg_temp.ok(pg_temp.audits('credit_package_reward_switched_off') = 3
      and pg_temp.audits('credit_package_reward_switched_off', pg_temp.txt('cp'), mgr) = 3
      and (select count(distinct record_id) from public.audit_logs where action = 'credit_package_reward_switched_off'
             and table_name = 'credit_packages' and module = 'catalogue'
             and record_id in (cp1000, pg_temp.id('cp3000'), pg_temp.id('cp5000'))) = 3,
    'G2e one Audit Log row for each package switched off, with the reason, by the Manager');
  select * into k from public.audit_logs where action = 'credit_package_reward_kept_for_earlier_sale';
  perform pg_temp.ok(pg_temp.audits('credit_package_reward_kept_for_earlier_sale') = 1 and k.table_name = 'invoice_items' and k.record_id = line
      and k.changed_by = mgr and k.reason = pg_temp.txt('cp') and k.module = 'invoices' and k.store_id = pg_temp.id('sa'),
    'G2f one Audit Log row keeps the earlier sale, on its invoice line, with the reason, by the Manager');
  perform pg_temp.setkv('kept', to_jsonb(k));
  v := k.new_data;
  perform pg_temp.ok((v ->> 'units')::int = 1 and (v ->> 'vouchers_per_unit')::int = 10 and (v ->> 'vouchers')::int = 10
      and (v ->> 'threshold')::numeric = 994 and (v ->> 'customer_price')::numeric = 1000 and (v ->> 'forfeited_value')::numeric = 6
      and (v ->> 'claim_window_days')::int = 365 and (v ->> 'duration_months')::int = 1
      and (v ->> 'package_id')::uuid = cp1000 and v ->> 'package' = 'T502G Package 1000'
      and v ->> 'reward_name' = 'Credit package reward — T502G Package 1000'
      and (v ->> 'invoice_id')::uuid = inv and (v ->> 'invoice_item_id')::uuid = line and (v ->> 'store_id')::uuid = pg_temp.id('sa')
      and (v ->> 'customer_id')::uuid = pg_temp.id('K1') and (v ->> 'paid_so_far')::numeric = 500 and (v ->> 'total')::numeric = 1000
      and (v ->> 'sold_on')::date = public.sg_today() and v ->> 'threshold_from' = 'rule'
      and (v ->> 'rule_id')::uuid in (pg_temp.id('r1'), pg_temp.id('r2'))
      and (select array_agg(y::uuid order by y::uuid) from jsonb_array_elements_text(v -> 'voucher_ids') y)
          = (select array_agg(u order by u) from unnest(array[pg_temp.id('v1'), pg_temp.id('v2')]) u),
    'G2g it keeps 1 reward of 10 vouchers for S$994 on the S$1,000 package, collected within 365 days, as one of the package''s 2 vouchers: ' || v::text);

  -- What the issuer itself gives the line when paid off with the reward on (in a savepoint, undone).
  begin
    update public.credit_packages set grants_reward = true where id = cp1000;
    t := pg_temp.pay(stf, inv, 500);
    act := (select jsonb_build_object('pay', t, 'sale', to_jsonb(cs),
                     'rows', (select coalesce(jsonb_agg(to_jsonb(te) order by te.entitlement_no), '[]'::jsonb) from public.therapy_entitlements te
                               where te.qualification_group_id = public.credit_package_reward_group(cs.id)),
                     'issued_on', (select (it.credit_issued_at at time zone 'Asia/Singapore')::date from public.invoice_items it where it.id = line))
              from public.credit_package_sales cs where cs.invoice_item_id = line);
    raise exception using errcode = 'T5022';
  exception when sqlstate 'T5022' then null; end;
  perform pg_temp.setkv('issued', act);
  x := act -> 'rows' -> 0; s := act -> 'sale';
  perform pg_temp.ok(act ->> 'pay' like 'ok:%' and jsonb_array_length(act -> 'rows') = (v ->> 'units')::int and (s ->> 'reward_units')::int = (v ->> 'units')::int,
    'G2h paid off with the reward on, issue_credit_package gives it as many rewards as kept (1): ' || coalesce(act::text, 'nothing'));
  perform pg_temp.ok(x ->> 'package_name' = v ->> 'reward_name' and (x ->> 'voucher_qty')::int = (v ->> 'vouchers_per_unit')::int
      and (x ->> 'qualifying_amount')::numeric = (v ->> 'threshold')::numeric and (x ->> 'qualified_value')::numeric = (v ->> 'threshold')::numeric
      and (x ->> 'forfeited_value')::numeric = (v ->> 'forfeited_value')::numeric and (x ->> 'duration_months')::int = (v ->> 'duration_months')::int
      and (x ->> 'activation_deadline')::date - (act ->> 'issued_on')::date = (v ->> 'claim_window_days')::int
      and (select array_agg(y::uuid order by y::uuid) from jsonb_array_elements_text(x -> 'eligible_voucher_ids') y)
          = (select array_agg(y::uuid order by y::uuid) from jsonb_array_elements_text(v -> 'voucher_ids') y)
      and x ->> 'customer_id' = v ->> 'customer_id' and x ->> 'store_id' = v ->> 'store_id' and x ->> 'claim_source_invoice_id' = v ->> 'invoice_id'
      and x ->> 'earner_kind' = 'credit_package' and x ->> 'claim_source_type' = 'credit_package' and x ->> 'entitlement_kind' = 'voucher'
      and x ->> 'status' = 'pending_activation' and x ->> 'rule_id' is null,
    'G2i its reward row is what step 2a kept: name, 10 vouchers, S$994, S$6 left over, 1 month, collect-by window, the 2 voucher choices, customer, store, sale');
  perform pg_temp.ok((s ->> 'reward_qualifying_snapshot')::numeric = (v ->> 'threshold')::numeric and (s ->> 'price_snapshot')::numeric = (v ->> 'customer_price')::numeric
      and s ->> 'package_id' = v ->> 'package_id' and s ->> 'customer_id' = v ->> 'customer_id' and s ->> 'store_id' = v ->> 'store_id'
      and (select array_agg(y::uuid order by y::uuid) from jsonb_array_elements_text(s -> 'eligible_voucher_ids') y)
          = (select array_agg(y::uuid order by y::uuid) from jsonb_array_elements_text(v -> 'voucher_ids') y),
    'G2j and its sale records the same threshold, price, package, customer, store and voucher choices');
  perform pg_temp.ok(pg_temp.fp_parts() = f1, 'G2k that savepoint left nothing (changed: ' || pg_temp.fp_diff(f1, pg_temp.fp_parts()) || ')');
  perform pg_temp.ok((select status::text from public.invoices where id = inv) = 'partially_paid'
      and (select credit_issued_at from public.invoice_items where id = line) is null,
    'G2l the earlier sale is as it was: S$500 paid, its credit not given yet');
  -- The go-live preview between the steps.
  pv := pg_temp.preview();
  perform pg_temp.ok(pg_temp.pv(pv, '2a in: Credit Packages with the reward on') = '0'
      and pg_temp.pv(pv, '2a in: packages step 2a switched off, not undone (= c_packages)') = '3'
      and pg_temp.pv(pv, '2a in: earlier sales step 2a kept, not undone (= c_kept_lines)') = '1'
      and pg_temp.pv(pv, 'not run already: step 2a''s switch-offs, not undone') = '3'
      and not exists (select 1 from jsonb_array_elements(pv) y join t502g_fig fg on fg.name = y ->> 'name'
                       where y ->> 'kind' = 'constant' and y ->> 'step' in ('2b', 'undo 2b') and y ->> 'now' is distinct from fg.v)
      and not exists (select 1 from jsonb_array_elements(pv) y where y ->> 'kind' = 'stop' and (y ->> 'ok')::boolean is not true),
    'G2m after step 2a the preview''s "2a in" rows read 0 / 3 / 1, every step 2b constant still has the fixture''s figure, every stop sign is clear');
end $g2$;

-- ═════ G3 Step 2b: the 103 cancelled, the rules off ═════
do $g3$
declare
  own uuid := pg_temp.id('own'); af1 uuid := pg_temp.id('af1_row');
  f1 jsonb := pg_temp.kv('S1'); f2 jsonb; e text; w uuid[]; p record;
  keep text; wrest text; rules text;
  a_cancel bigint := pg_temp.audits('legacy_reward_cancelled'); a_up bigint := pg_temp.audits('legacy_rule_upserted', null, own);
  a_off bigint := pg_temp.audits('legacy_rule_switched_off'); a_sum bigint := pg_temp.audits('legacy_therapy_retired');
begin
  w := array(select te.id from public.therapy_entitlements te
              where te.status = 'pending_activation' and te.earner_kind in ('customer', 'affiliate') order by te.id);
  keep := pg_temp.fp_q(format('select to_jsonb(te) from public.therapy_entitlements te where not (te.id = any(%L::uuid[]))', w));
  wrest := pg_temp.fp_q(format('select to_jsonb(te) - ''status'' - ''revoked_qty'' - ''revoked_at'' - ''revoked_reason'' from public.therapy_entitlements te where te.id = any(%L::uuid[])', w));
  rules := pg_temp.fp_q('select to_jsonb(t) - ''is_active'' - ''updated_at'' from public.therapy_package_rules t');
  e := pg_temp.run(own, 't502g.golive');
  perform pg_temp.ok(e = 'ok', 'G3a step 2b runs, recorded by the Owner: ' || e);
  f2 := pg_temp.fp_parts();
  perform pg_temp.setkv('S2', f2);
  perform pg_temp.ok(cardinality(w) = 103
      and (select count(*) from public.therapy_entitlements where id = any(w) and status = 'cancelled' and revoked_reason = pg_temp.txt('golive') and revoked_at = now()) = 103
      and (select count(*) from public.therapy_entitlements where status = 'cancelled' and revoked_reason = pg_temp.txt('golive')) = 103,
    'G3b exactly the 103 unclaimed Legacy rewards are cancelled, with the reason and the time');
  perform pg_temp.ok((select revoked_qty from public.therapy_entitlements where id = af1) = 10
      and not exists (select 1 from public.therapy_entitlements where id = any(w) and id <> af1 and revoked_qty <> 0),
    'G3c the affiliate reward''s 10 vouchers are withdrawn; the months withdraw nothing');
  perform pg_temp.ok(wrest = pg_temp.fp_q(format('select to_jsonb(te) - ''status'' - ''revoked_qty'' - ''revoked_at'' - ''revoked_reason'' from public.therapy_entitlements te where te.id = any(%L::uuid[])', w)),
    'G3d nothing else in them changed: number, customer, store, rule, claim-by date');
  perform pg_temp.ok(keep = pg_temp.fp_q(format('select to_jsonb(te) from public.therapy_entitlements te where not (te.id = any(%L::uuid[]))', w)),
    'G3e every other reward is as it was, byte for byte: the 10 Credit Package rewards, the 60 Legacy rewards claimed, used or cancelled, the 2 older package rewards');
  perform pg_temp.ok(pg_temp.fp_diff(f1, f2) = 'audit_logs, therapy_entitlements, therapy_package_rules',
    'G3f nothing else changed: the held vouchers, the 67 links, packages, bundles, sales, invoices, customers, credit (changed: ' || pg_temp.fp_diff(f1, f2) || ')');
  perform pg_temp.ok(not exists (select 1 from public.therapy_package_rules where is_active)
      and rules = pg_temp.fp_q('select to_jsonb(t) - ''is_active'' - ''updated_at'' from public.therapy_package_rules t'),
    'G3g the 3 rules are off; nothing else in them changed');
  perform pg_temp.ok(pg_temp.audits('legacy_reward_cancelled') = a_cancel + 103
      and pg_temp.audits('legacy_reward_cancelled', pg_temp.txt('golive'), own) = 103
      and (select count(distinct record_id) from public.audit_logs where action = 'legacy_reward_cancelled' and record_id = any(w) and module = 'therapy') = 103
      and pg_temp.audits('legacy_rule_upserted', null, own) = a_up + 3
      and pg_temp.audits('legacy_rule_switched_off') = a_off + 3 and pg_temp.audits('legacy_rule_switched_off', pg_temp.txt('golive'), own) = 3
      and pg_temp.audits('legacy_therapy_retired') = a_sum + 1 and pg_temp.audits('legacy_therapy_retired', pg_temp.txt('golive'), own) = 1,
    'G3h the Audit Log: 103 rewards cancelled, 3 rule saves and 3 rules switched off, 1 for the whole, each with the reason, by the Owner');
  perform pg_temp.ok((select new_data from public.audit_logs where action = 'legacy_therapy_retired')
        = jsonb_build_object('customer_rewards_cancelled', 102, 'customers', 43, 'affiliate_rewards_cancelled', 1, 'rules_switched_off', 3)
      and not exists (select 1 from public.audit_logs a join public.therapy_entitlements te on te.id = a.record_id
                       where a.action = 'legacy_reward_cancelled'
                         and (a.old_data ->> 'status' <> 'pending_activation' or (a.old_data ->> 'claim_by')::date <> te.activation_deadline
                              or a.old_data ->> 'entitlement_no' <> te.entitlement_no or (a.old_data ->> 'revoked_qty')::int <> 0
                              or a.old_data -> 'revoked_reason' <> 'null'::jsonb)),
    'G3i the whole step''s row has its figures, and each reward''s row keeps what it was (waiting, its claim-by date, nothing withdrawn)');
  select
   (select count(*) from public.therapy_entitlements where status = 'pending_activation' and earner_kind in ('customer', 'affiliate')) as legacy_waiting,
   (select count(*) from public.therapy_entitlements where status = 'cancelled' and revoked_reason = pg_temp.txt('golive')) as cancelled,
   (select count(*) from public.therapy_entitlements where status = 'pending_activation' and earner_kind = 'credit_package') as cp_rows,
   (select sum(voucher_qty) from public.therapy_entitlements where status = 'pending_activation' and earner_kind = 'credit_package') as cp_vouchers,
   (select count(*) from public.customer_reward_vouchers v join public.therapy_entitlements te on te.id = v.entitlement_id where te.earner_kind in ('customer', 'affiliate') and v.status = 'held') as held_rows,
   (select sum(v.quantity) from public.customer_reward_vouchers v join public.therapy_entitlements te on te.id = v.entitlement_id where te.earner_kind in ('customer', 'affiliate') and v.status = 'held') as held_qty,
   (select count(*) from public.therapy_entitlement_invoices) as links,
   (select count(*) from public.therapy_package_rules where is_active and deleted_at is null) as rules_on,
   (select count(*) from public.credit_packages where grants_reward) as packages_on,
   (select count(*) from public.premium_bundles where grants_reward) as bundles_on,
   (select count(*) from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'legacy_refund_guard') as guard
  into p;
  perform pg_temp.ok(p.legacy_waiting = 0 and p.cancelled = 103 and p.cp_rows = 10 and p.cp_vouchers = 100 and p.held_rows = 6 and p.held_qty = 50
      and p.links = 67 and p.rules_on = 0 and p.packages_on = 0 and p.bundles_on = 2 and p.guard = 0,
    'G3j the checks after go-live: ' || to_jsonb(p)::text);
end $g3$;

-- ═════ G4 Afterwards (undone after) ═════
savepoint g4;
do $g4$
declare
  mgr uuid := pg_temp.id('mgr'); stf uuid := pg_temp.id('stf'); af1 uuid := pg_temp.id('af1_row');
  l jsonb; l2 jsonb; t text; inv uuid; sale public.credit_package_sales%rowtype; ent uuid; s jsonb;
begin
  -- Vouchers to hand over, as staff.
  l := pg_temp.list(stf, 'vouchers', null, 'all');
  perform pg_temp.ok((l ->> 'total')::int = 12 and jsonb_array_length(l -> 'rows') = 12
      and not exists (select 1 from jsonb_array_elements(l -> 'rows') y where y ->> 'earner_kind' <> 'credit_package'),
    'G4a Vouchers to hand over, everything, for staff: the 12 Credit Package rewards and nothing Legacy: ' || coalesce(l ->> 'total', l::text));
  l := pg_temp.list(stf, 'vouchers', null, null);
  perform pg_temp.ok(l ->> 'status' = 'open' and (l ->> 'total')::int = 10
      and not exists (select 1 from jsonb_array_elements(l -> 'rows') y
                       where y ->> 'earner_kind' <> 'credit_package' or y ->> 'status' <> 'pending_activation' or (y ->> 'remaining')::int <> 10),
    'G4b it opens on the 10 still to hand over, 10 vouchers each: ' || coalesce(l ->> 'total', l::text));
  l2 := pg_temp.list(stf, 'legacy', null, null);
  perform pg_temp.ok(l2 -> 'rows' = l -> 'rows' and l2 ->> 'total' = l ->> 'total', 'G4c the old page''s list name reads the same');
  l := pg_temp.list(stf, 'vouchers', 'T502G Customer L01', 'all');
  l2 := pg_temp.list(stf, 'vouchers', 'T502G Customer AF1', 'all');
  perform pg_temp.ok((l ->> 'total')::int = 0 and (l2 ->> 'total')::int = 0, 'G4d a customer or an affiliate whose rewards were cancelled has nothing listed');

  -- A new Credit Package sale paid in full gives credit only.
  inv := pg_temp.sell(stf, pg_temp.id('sb'), pg_temp.id('N1'), pg_temp.id('cp3000'));
  t := pg_temp.pay(stf, inv, 3000);
  select * into sale from public.credit_package_sales where invoice_id = inv;
  perform pg_temp.ok(t like 'ok:%' and (select status::text from public.invoices where id = inv) = 'paid' and sale.reward_units = 0
      and not exists (select 1 from public.therapy_entitlements where qualification_group_id = public.credit_package_reward_group(sale.id))
      and not exists (select 1 from public.therapy_entitlements where customer_id = pg_temp.id('N1'))
      and (select sum(original_amount) from public.customer_credit_lots where customer_id = pg_temp.id('N1')) = 3000,
    'G4e a new S$3,000 Credit Package sold and paid in full by staff gives S$3,000 credit and no reward vouchers: ' || t);

  -- Deleting customers.
  t := pg_temp.try_as(mgr, format('select public.delete_customer(%L::uuid, %L, %L)::text', pg_temp.id('L01'), 'T502G Customer L01', 'T502G check'));
  perform pg_temp.ok(t like 'ok:%' and (select deleted_at from public.customers where id = pg_temp.id('L01')) is not null,
    'G4f a customer whose only rewards are Legacy ones, now cancelled, can be deleted: ' || t);
  t := pg_temp.try_as(mgr, format('select public.delete_customer(%L::uuid, %L, %L)::text', pg_temp.id('H1'), 'T502G Customer H1', 'T502G check'));
  perform pg_temp.ok(t like 'ok:%' and (select deleted_at from public.customers where id = pg_temp.id('H1')) is not null
      and (select count(*) from public.customer_reward_vouchers where customer_id = pg_temp.id('H1') and status = 'held') = 3,
    'G4g one holding only Legacy rewards handed over (the vouchers held) can be deleted; the vouchers stay as they were: ' || t);
  -- Control: a customer with no credit, still owed a Credit Package reward's 10 vouchers.
  perform pg_temp.ent('T502G-K2-1', pg_temp.id('K2'), pg_temp.id('sa'), null, 'Credit package reward — T502G Package 5000', 'voucher', 10,
                      'pending_activation', 'credit_package', public.sg_today() + 365);
  update public.therapy_entitlements set claim_source_type = 'credit_package', claim_source_invoice_id = pg_temp.id('inv_P1') where entitlement_no = 'T502G-K2-1';
  t := pg_temp.try_as(mgr, format('select public.delete_customer(%L::uuid, %L, %L)::text', pg_temp.id('K2'), 'T502G Customer K2', 'T502G check'));
  perform pg_temp.ok(t = 'P0001:This customer still has 1 reward(s) with vouchers to hand over (Therapy → Vouchers to hand over). Hand them over, or refund or cancel the sale they came from, first.'
      and (select deleted_at from public.customers where id = pg_temp.id('K2')) is null,
    'G4h control: a customer still owed Credit Package vouchers is refused, with 502''s words: ' || t);

  -- The cancelled affiliate reward cannot be handed over.
  t := pg_temp.claim(stf, af1, pg_temp.id('v1'), 1);
  s := pg_temp.state(stf, af1);
  perform pg_temp.ok(t = 'P0001:This entitlement has been cancelled' and (s ->> 'remaining')::int = 0 and (s ->> 'cancelled')::boolean,
    'G4i handing over the cancelled affiliate reward is refused; nothing is left on it: ' || t);

  -- A Credit Package hand-over still works for staff.
  ent := (select id from public.therapy_entitlements where customer_id = pg_temp.id('P1') and earner_kind = 'credit_package' order by entitlement_no limit 1);
  t := pg_temp.claim(stf, ent, pg_temp.id('v1'), 4);
  s := pg_temp.state(stf, ent);
  perform pg_temp.ok(t like 'ok:%' and (s ->> 'claimed')::int = 4 and (s ->> 'remaining')::int = 6 and s -> 'blocked_reason' = 'null'::jsonb,
    'G4j staff hand over 4 of a Credit Package reward''s 10 vouchers: ' || t);
  t := pg_temp.claim(stf, ent, pg_temp.id('v3'), 1);
  perform pg_temp.ok(t = 'P0001:That voucher was not one of the choices for this entitlement', 'G4k and only as one of its own voucher choices: ' || t);
end $g4$;
rollback to savepoint g4;

-- ═════ G5 The earlier sale (undone after) ═════
savepoint g5;
do $g5$
declare
  own uuid := pg_temp.id('own'); mgr uuid := pg_temp.id('mgr'); stf uuid := pg_temp.id('stf');
  inv uuid := pg_temp.id('inv_K1'); line uuid := pg_temp.id('line_K1');
  kept jsonb := pg_temp.kv('kept'); v jsonb; issued jsonb := pg_temp.kv('issued');
  e text; t text; f jsonb; sale public.credit_package_sales%rowtype; x public.therapy_entitlements%rowtype; s jsonb; l jsonb; o jsonb;
  ben jsonb; tot numeric; src jsonb; given public.audit_logs%rowtype; issued_on date;
  c_skip constant text[] := array['id', 'entitlement_no', 'created_at', 'created_by', 'qualification_group_id', 'eligible_voucher_ids'];
begin
  v := kept -> 'new_data';
  e := pg_temp.run(own, 't502g.presale');
  perform pg_temp.ok(e like 'P0001:502 earlier sale: invoice % is not paid off yet (it is partially_paid, its credit not given)%',
    'G5a before the invoice is paid off, the earlier-sale script refuses: ' || e);
  -- Meanwhile the Owner renames the package and changes its vouchers (the Credit Package window,
  -- then its reward switched off as the page does after every save): the reward keeps what was kept.
  t := pg_temp.try_as(own, format('select public.upsert_credit_package(%L::uuid, %L, 1000, 1000, true, %L::date, null, %L, true, null, null, null, null, null, %L::uuid[], %L::uuid[], true)::text',
    pg_temp.id('cp1000'), 'T502G Package 1000 renamed', public.sg_today() - 200, 'third_party', array[pg_temp.id('sa'), pg_temp.id('sb')], array[pg_temp.id('v3')]));
  e := pg_temp.try_as(own, format('select public.set_catalogue_reward(%L, %L::uuid, false)::text', 'credit_package', pg_temp.id('cp1000')));
  perform pg_temp.ok(t like 'ok:%' and e like 'ok:%' and (select name from public.credit_packages where id = pg_temp.id('cp1000')) = 'T502G Package 1000 renamed'
      and not (select grants_reward from public.credit_packages where id = pg_temp.id('cp1000')),
    'G5a2 the Owner renames the package and gives it other vouchers; it still gives credit only: ' || t || ' / ' || e);
  t := pg_temp.pay(stf, inv, 500);
  perform pg_temp.ok(t like 'ok:%' and (select status::text from public.invoices where id = inv) = 'paid', 'G5b staff take the last S$500 in the Pay dialog: ' || t);
  select * into sale from public.credit_package_sales where invoice_item_id = line;
  perform pg_temp.ok((select credit_issued_at from public.invoice_items where id = line) is not null and sale.id is not null and sale.reward_units = 0
      and not exists (select 1 from public.therapy_entitlements where qualification_group_id = public.credit_package_reward_group(sale.id))
      and not exists (select 1 from public.therapy_entitlements where customer_id = pg_temp.id('K1'))
      and (select sum(original_amount) from public.customer_credit_lots where customer_id = pg_temp.id('K1')) = 1000,
    'G5c paid off, it got its S$1,000 credit and no reward vouchers');
  -- The script runs days later: here the invoice was paid off 5 days ago, at 01:00 Singapore time
  -- (17:00 the day before in UTC), so its Singapore day is neither today nor the UTC date.
  update public.invoice_items
     set credit_issued_at = ((public.sg_today() - 5)::timestamp + interval '1 hour') at time zone 'Asia/Singapore'
   where id = line;
  issued_on := public.sg_today() - 5;
  perform pg_temp.ok((select (credit_issued_at at time zone 'UTC')::date from public.invoice_items where id = line) = issued_on - 1,
    'G5c2 (paid off on ' || issued_on || ' in Singapore, ' || (issued_on - 1) || ' in UTC)');

  f := pg_temp.fp_parts();
  e := pg_temp.run(own, 't502g.presale');
  perform pg_temp.ok(e = 'ok', 'G5d with the user''s OK, the earlier-sale script runs: ' || e);
  perform pg_temp.ok((select count(*) from public.therapy_entitlements where qualification_group_id = public.credit_package_reward_group(sale.id)) = 1,
    'G5e exactly 1 reward row, in the sale''s reward group');
  select * into x from public.therapy_entitlements where qualification_group_id = public.credit_package_reward_group(sale.id);
  perform pg_temp.ok(x.voucher_qty = 10 and x.entitlement_kind = 'voucher' and x.status = 'pending_activation' and x.earner_kind = 'credit_package'
      and x.claim_source_type = 'credit_package' and x.claim_source_invoice_id = inv and x.customer_id = pg_temp.id('K1') and x.store_id = pg_temp.id('sa')
      and x.package_name = v ->> 'reward_name' and x.qualifying_amount = 994 and x.qualified_value = 994 and x.forfeited_value = 6
      and x.duration_months = 1 and x.rule_id is null and x.created_by = own and x.entitlement_no like 'LEG-%'
      and (select array_agg(y order by y) from unnest(x.eligible_voucher_ids) y) = (select array_agg(u order by u) from unnest(array[pg_temp.id('v1'), pg_temp.id('v2')]) u),
    'G5f 10 vouchers, waiting, for K1 at Store A, from that sale, with the kept values (the name and the 2 vouchers as kept), numbered as every reward is (' || x.entitlement_no || ')');
  perform pg_temp.ok(x.activation_deadline = issued_on + 365, 'G5g collected by the Singapore day it was paid off plus 365 days: ' || x.activation_deadline);
  perform pg_temp.ok((to_jsonb(x) - c_skip - 'activation_deadline') = ((issued -> 'rows' -> 0) - c_skip - 'activation_deadline')
      and (select array_agg(y order by y) from unnest(x.eligible_voucher_ids) y)
          = (select array_agg(y::uuid order by y::uuid) from jsonb_array_elements_text(issued -> 'rows' -> 0 -> 'eligible_voucher_ids') y),
    'G5h the same row, field for field, as issue_credit_package made when the reward was on (G2): the kept name and vouchers, not the package''s new ones; but for its number, who made it and its collect-by date');
  select * into sale from public.credit_package_sales where id = sale.id;
  perform pg_temp.ok(sale.reward_units = 1 and sale.reward_qualifying_snapshot = 994
      and sale.reward_units = (issued -> 'sale' ->> 'reward_units')::int
      and sale.reward_qualifying_snapshot = (issued -> 'sale' ->> 'reward_qualifying_snapshot')::numeric,
    'G5i its sale records 1 reward for S$994, as the issuer would have');
  select * into given from public.audit_logs where action = 'credit_package_earlier_sale_reward_given';
  perform pg_temp.ok(pg_temp.audits('credit_package_earlier_sale_reward_given') = 1 and given.table_name = 'credit_package_sales' and given.record_id = sale.id
      and given.changed_by = own and given.reason = pg_temp.txt('presale') and given.new_data ->> 'kept_audit_id' = kept ->> 'id'
      and (given.new_data ->> 'collect_by')::date = issued_on + 365 and (given.new_data ->> 'vouchers')::int = 10
      and given.new_data -> 'rewards' -> 0 ->> 'no' = x.entitlement_no,
    'G5j one Audit Log row on the sale, with the reason, by the Owner, naming the kept row and the reward');
  perform pg_temp.ok(pg_temp.fp_diff(f, pg_temp.fp_parts()) = 'audit_logs, credit_package_sales, therapy_entitlements',
    'G5k nothing else changed: credit, invoices, the other rewards (changed: ' || pg_temp.fp_diff(f, pg_temp.fp_parts()) || ')');
  f := pg_temp.fp_parts();
  e := pg_temp.run(own, 't502g.presale');
  perform pg_temp.ok(e like 'P0001:502 earlier sale: there is no earlier sale to give a reward to%' and pg_temp.fp_parts() = f,
    'G5l run again, it refuses, changing nothing: ' || e);

  -- Staff hand them over, from Vouchers to hand over.
  l := pg_temp.list(stf, 'vouchers', 'T502G Customer K1', null);
  perform pg_temp.ok((l ->> 'total')::int = 1 and (l -> 'rows' -> 0 ->> 'remaining')::int = 10, 'G5m it is on Vouchers to hand over, 10 to hand over');
  t := pg_temp.claim(stf, x.id, pg_temp.id('v2'), 3);
  s := pg_temp.state(stf, x.id);
  perform pg_temp.ok(t like 'ok:%' and (s ->> 'claimed')::int = 3 and (s ->> 'remaining')::int = 7, 'G5n staff hand over 3 of them: ' || t);

  -- A refund opens the reward review first (the Finance panel's refund, as a Manager).
  t := pg_temp.try_as(mgr, format('select public.invoice_refund_options(%L::uuid)::text', inv));
  o := substr(t, 4)::jsonb;
  select jsonb_agg(jsonb_build_object('benefit_id', b ->> 'id', 'amount', (b ->> 'max_refund')::numeric)), sum((b ->> 'max_refund')::numeric)
    into ben, tot from jsonb_array_elements(o -> 'benefits') b where b ->> 'invoice_item_id' = line::text and (b ->> 'max_refund')::numeric > 0;
  select jsonb_agg(jsonb_build_object('payment_id', y ->> 'payment_id', 'amount', (y ->> 'remaining')::numeric) order by y ->> 'payment_id')
    into src from jsonb_array_elements(o -> 'sources') y where (y ->> 'remaining')::numeric > 0;
  t := pg_temp.try_as(mgr, format('select public.refund_invoice_recorded(%L::uuid, %L::jsonb, %L::jsonb, %L::jsonb, %L, %L::uuid)::text', inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', tot, 'benefits', ben)), src, '[]', 'T502G refund', gen_random_uuid()));
  perform pg_temp.ok(tot = 1000 and t = 'P0001:' || pg_temp.txt('p13'),
    'G5o refunding the S$1,000 is refused with 502''s words, which open the reward review: ' || t);
  t := pg_temp.try_as(mgr, format('select public.resolve_invoice_credit_rewards(%L::uuid, %L, null, true, %L::uuid)::text', inv, 'T502G review: 3 handed over stay', gen_random_uuid()));
  perform pg_temp.ok(t like 'ok:%' and (substr(t, 4)::jsonb ->> 'retained')::int = 1 and (substr(t, 4)::jsonb ->> 'withdrawn')::int = 0,
    'G5p the review settles it, keeping the reward with vouchers handed over: ' || t);
  t := pg_temp.try_as(mgr, format('select public.refund_invoice_recorded(%L::uuid, %L::jsonb, %L::jsonb, %L::jsonb, %L, %L::uuid)::text', inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', tot, 'benefits', ben)), src, '[]', 'T502G refund', gen_random_uuid()));
  perform pg_temp.ok(t like 'ok:%' and (select status::text from public.invoices where id = inv) = 'refunded', 'G5q then the refund goes through: ' || left(t, 120));
  select * into x from public.therapy_entitlements where id = x.id;
  perform pg_temp.ok(public.entitlement_claimed_qty(x.id) = 3 and x.revoked_qty = 7 and x.status = 'active',
    'G5r the 7 not handed over are withdrawn; the 3 handed over stay with the customer');
  e := pg_temp.run(own, 't502g.presale');
  perform pg_temp.ok(e like 'P0001:502 earlier sale: there is no earlier sale to give a reward to%', 'G5s and the script still refuses: ' || e);
end $g5$;
rollback to savepoint g5;

-- ═════ G6 Run again ═════
do $g6$
declare own uuid := pg_temp.id('own'); f jsonb := pg_temp.fp_parts(); e text; e2 text; e3 text;
begin
  perform pg_temp.ok(f = pg_temp.kv('S2'), 'G6a G4 and G5 left nothing (changed: ' || pg_temp.fp_diff(f, pg_temp.kv('S2')) || ')');
  e := pg_temp.run(own, 't502g.cp'); e2 := pg_temp.run(own, 't502g.golive'); e3 := pg_temp.run(own, 't502g.presale');
  perform pg_temp.ok(e like 'P0001:502 credit only: this has run already%', 'G6b step 2a again refuses: ' || e);
  perform pg_temp.ok(e2 like 'P0001:502 go-live: this has run already%', 'G6c step 2b again refuses: ' || e2);
  perform pg_temp.ok(e3 like 'P0001:502 earlier sale: invoice % is not paid off yet%', 'G6d the earlier-sale script refuses while the invoice is not paid off: ' || e3);
  perform pg_temp.ok(pg_temp.fp_parts() = f, 'G6e none of them changed anything (changed: ' || pg_temp.fp_diff(f, pg_temp.fp_parts()) || ')');
end $g6$;

-- ═════ G7 UNDO in the rollback order ═════
do $g7$
declare
  own uuid := pg_temp.id('own'); stf uuid := pg_temp.id('stf'); inv uuid := pg_temp.id('inv_K1');
  f jsonb := pg_temp.fp_parts(); f1 jsonb; f0 jsonb; f2 jsonb; e text; e1 text; e2 text; x text; t text; sig text;
  a_back bigint := pg_temp.audits('legacy_reward_cancel_undone'); a_on bigint := pg_temp.audits('legacy_rule_switched_on');
  a_up bigint := pg_temp.audits('legacy_rule_upserted', null, own);
begin
  -- Undoing step 2a first is refused.
  e := pg_temp.run(own, 't502g.undo_cp');
  perform pg_temp.ok(e like 'P0001:UNDO 502 credit only: the go-live step that cancelled the Legacy rewards is still in. Run scripts/therapy/undo-legacy-retired-golive-502.sql first%'
      and pg_temp.fp_parts() = f,
    'G7a undoing step 2a while step 2b is in refuses, changing nothing: ' || e);
  -- And once the earlier sale's reward has been given (in a savepoint, undone).
  begin
    t := pg_temp.pay(stf, inv, 500); e1 := pg_temp.run(own, 't502g.presale'); e2 := pg_temp.run(own, 't502g.undo_golive');
    f2 := pg_temp.fp_parts(); e := pg_temp.run(own, 't502g.undo_cp'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5027';
  exception when sqlstate 'T5027' then null; end;
  perform pg_temp.ok(t like 'ok:%' and e1 = 'ok' and e2 = 'ok' and e like 'P0001:UNDO 502 credit only: the earlier sale on invoice % has had its reward vouchers given%' and x = 'none',
    'G7b undoing step 2a after the earlier sale''s reward was given refuses, changing nothing: ' || e);
  -- Or once it is paid off, its reward still owed (in a savepoint, undone).
  begin
    t := pg_temp.pay(stf, inv, 500); e2 := pg_temp.run(own, 't502g.undo_golive');
    f2 := pg_temp.fp_parts(); e := pg_temp.run(own, 't502g.undo_cp'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5027';
  exception when sqlstate 'T5027' then null; end;
  perform pg_temp.ok(t like 'ok:%' and e2 = 'ok' and e like 'P0001:UNDO 502 credit only: the earlier sale on invoice % was paid off with credit only, and its reward vouchers are still owed%' and x = 'none',
    'G7c undoing step 2a after the earlier sale was paid off, its reward still owed, refuses: ' || e);
  -- Or once vouchers were handed over from one of the rewards it would put back (in a savepoint, undone).
  begin
    insert into public.voucher_claims (entitlement_id, customer_id, store_id, quantity, selections, note)
    select te.id, te.customer_id, te.store_id, 1, '[]'::jsonb, 'T502G after go-live'
      from public.therapy_entitlements te where te.id = pg_temp.id('af1_row');
    f2 := pg_temp.fp_parts(); e := pg_temp.run(own, 't502g.undo_golive'); x := pg_temp.fp_diff(f2, pg_temp.fp_parts());
    raise exception using errcode = 'T5027';
  exception when sqlstate 'T5027' then null; end;
  perform pg_temp.ok(e = 'P0001:UNDO 502 go-live: reward T502G-AF-1 is not as the go-live step left it (vouchers handed over from it, or changed since). Ask the user. Nothing changed.'
      and x = 'none',
    'G7c2 undoing step 2b once a voucher was handed over from a cancelled reward refuses, naming that reward, changing nothing: ' || e);
  perform pg_temp.ok(pg_temp.fp_parts() = f, 'G7d those savepoints left nothing (changed: ' || pg_temp.fp_diff(f, pg_temp.fp_parts()) || ')');

  -- 1. Undo step 2b.
  e := pg_temp.run(own, 't502g.undo_golive');
  perform pg_temp.ok(e = 'ok', 'G7e undo-legacy-retired-golive-502.sql runs: ' || e);
  f1 := pg_temp.fp_parts();
  perform pg_temp.ok((f1 - 'audit_logs') = (pg_temp.kv('S1') - 'audit_logs'),
    'G7f every row is back as it was after step 2a, byte for byte: the 103 waiting with their claim-by dates, the rules on (changed: '
    || pg_temp.fp_diff(f1 - 'audit_logs', pg_temp.kv('S1') - 'audit_logs') || ')');
  perform pg_temp.ok(pg_temp.audits('legacy_reward_cancel_undone', pg_temp.txt('undo_golive'), own) = a_back + 103
      and pg_temp.audits('legacy_rule_switched_on', pg_temp.txt('undo_golive'), own) = a_on + 3
      and pg_temp.audits('legacy_rule_upserted', null, own) = a_up + 3
      and pg_temp.audits('legacy_therapy_retired_undone', pg_temp.txt('undo_golive'), own) = 1,
    'G7g with its Audit Log rows: 103 rewards back, 3 rules on (and their 3 saves), 1 for the whole, by the Owner');
  e := pg_temp.run(own, 't502g.undo_golive');
  perform pg_temp.ok(e like 'P0001:UNDO 502 go-live: found 0 rewards cancelled by the go-live step%', 'G7h run again, it refuses: ' || e);
  perform pg_temp.ok(pg_temp.fp_parts() = f1, 'G7i changing nothing');

  -- 2. Undo step 2a.
  e := pg_temp.run(own, 't502g.undo_cp');
  perform pg_temp.ok(e = 'ok', 'G7j undo-credit-package-credit-only-502.sql runs: ' || e);
  f0 := pg_temp.fp_parts();
  perform pg_temp.ok((f0 - 'audit_logs') = (pg_temp.kv('S0') - 'audit_logs'),
    'G7k every row is back as it was before step 2a, byte for byte: the 3 packages give reward vouchers again (changed: '
    || pg_temp.fp_diff(f0 - 'audit_logs', pg_temp.kv('S0') - 'audit_logs') || ')');
  perform pg_temp.ok(pg_temp.audits('credit_package_reward_switched_on', pg_temp.txt('undo_cp'), own) = 3
      and pg_temp.audits('credit_package_reward_kept_for_earlier_sale_undone', pg_temp.txt('undo_cp'), own) = 1
      and (select new_data ->> 'kept_audit_id' from public.audit_logs where action = 'credit_package_reward_kept_for_earlier_sale_undone')
          = (select id::text from public.audit_logs where action = 'credit_package_reward_kept_for_earlier_sale'),
    'G7l with its Audit Log rows: 3 packages on, the earlier sale no longer kept, by the Owner');
  e := pg_temp.run(own, 't502g.undo_cp'); e2 := pg_temp.run(own, 't502g.presale');
  perform pg_temp.ok(e like 'P0001:UNDO 502 credit only: found 0 Credit Packages%' and pg_temp.fp_parts() = f0, 'G7m run again, it refuses, changing nothing: ' || e);
  perform pg_temp.ok(e2 like 'P0001:502 earlier sale: there is no earlier sale to give a reward to%', 'G7n the earlier-sale script now refuses: ' || e2);

  -- 3. Undo 502.
  e := pg_temp.run(own, 't502g.undo502');
  perform pg_temp.ok(e = 'ok', 'G7o undo-502.sql runs: ' || e);
  perform pg_temp.ok(pg_temp.fp() = pg_temp.kv('fp_before_502') #>> '{}', 'G7p every function is as before 502, by fingerprint: ' || pg_temp.fp());
  perform pg_temp.ok((select pg_get_triggerdef(t2.oid) || ' ' || t2.tgenabled::text from pg_trigger t2
                       where t2.tgrelid = 'public.invoices'::regclass and t2.tgname = 'legacy_refund_guard')
                     = 'CREATE TRIGGER legacy_refund_guard BEFORE UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_legacy_refund_guard() O',
    'G7q the refund guard is back on invoices, as it was');
  foreach sig in array array['backfill_legacy_qualification(date,date,uuid)', 'upsert_legacy_rule(uuid,uuid,text,numeric,text,integer,integer,integer,boolean,date,text)',
                             'claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)', 'legacy_setup_status()'] loop
    perform pg_temp.ok(pg_temp.acl_of(sig) = 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
      'G7r signed-in logins can call ' || sig || ' again: ' || pg_temp.acl_of(sig));
  end loop;
  perform pg_temp.ok(obj_description('public.recompute_legacy_qualification(uuid,uuid,date)'::regprocedure, 'pg_proc') is null,
    'G7s the retired recount carries no comment again');
  perform pg_temp.ok((pg_temp.fp_parts() - 'audit_logs') = (pg_temp.kv('S0') - 'audit_logs'), 'G7t and no row changed');
  e := pg_temp.run(own, 't502g.undo502'); e2 := pg_temp.run(own, 't502g.cp');
  perform pg_temp.ok(e like 'P0001:UNDO 502: public.trg_create_therapy_on_paid() is not 502''s version%', 'G7u undo-502.sql run again refuses: ' || e);
  perform pg_temp.ok(e2 like 'P0001:502 credit only: migration 502 is not in%', 'G7v step 2a now refuses: 502 is not in: ' || e2);
end $g7$;

-- ═════ Result ═════
do $res$
declare p bigint; f bigint;
begin
  select case when is_called then last_value else 0 end into p from t502g_pass;
  select case when is_called then last_value else 0 end into f from t502g_fail;
  if f > 0 then
    raise exception '% of % checks failed (each is a FAIL warning above): %', f, p + f,
      coalesce((select string_agg(label, ' | ' order by n) from t502g_res where not ok), 'in a section undone after (G4, G5)');
  end if;
  raise warning 'PASS all % checks', p;
end $res$;
rollback;
