-- 502: Legacy Therapy and Qualification retired (the user, 10 Nov 2026), part 1: earning stops,
-- what was earned stays as history, the rest of the paid-invoice trigger is unchanged, and Credit
-- Packages give credit only while the rewards they already gave keep working.
-- supabase/502_legacy_therapy_retired.sql; its UNDO is scripts/therapy/undo-502.sql. Part 2,
-- what the pages read, is scripts/therapy/tests/legacy-retired-502-reads.sql; the go-live
-- scripts' suite is scripts/therapy/tests/legacy-retired-golive-502.sql.
--
-- Every step goes through the app's own calls, as the person named, with their grants: the
-- invoice form (create_invoice_with_details; correct_invoice to correct a paid invoice), the Pay
-- dialog (record_invoice_settlement), Correct payment (correct_invoice_payment), Cancel
-- (cancel_invoice_recorded), Reopen (invoice_reopen_preview, reopen_invoice), the Finance
-- panel's refund by line (invoice_refund_options, refund_invoice_recorded), the Therapy page's
-- list (therapy_list_page), the hand-over window (entitlement_voucher_state,
-- claim_entitlement_vouchers), the reward review (invoice_credit_reward_entitlements,
-- invoice_action_plan, resolve_invoice_credit_rewards, invoice_benefit_review_options), the
-- Credit Package window (upsert_credit_package, set_catalogue_reward,
-- credit_package_benefit_preview) and its split panel (create_split_credit_package_invoices).
-- What no page does is done as the database owner, as the go-live scripts do: the rule form's
-- function (upsert_legacy_rule, which 502 takes from signed-in logins) makes the qualification
-- rules with the Owner recorded; the retired recount (recompute_legacy_qualification,
-- recompute_affiliates_for_customer_day) writes a paid day as it did before 502; and a few
-- fixture rows stand for older records (a month already used, a package sold while its reward
-- was on, a sale from before benefit values were recorded).
--
--   S. Where it starts: without 502 (the 15 functions at their BEFORE, the refund guard on), or
--      with it (-v skip_install=1: the 15 at their AFTER, the guard gone, the 13 revoked, the 4
--      recounts commented). Anything else stops the suite.
--   R. Without 502 (skipped with -v skip_install=1): a paid day earns for the customer and for the
--      affiliate on the invoice, the list's old name and Delete customer see it, refunding the
--      day of a used month is refused, a new Credit Package starts with its reward on and the
--      reward can be switched on.
--   I. Install (skipped with -v skip_install=1): a patched function, a function relied on, the
--      trigger or the rights not as tested stop it with nothing changed; the trigger already gone
--      gives a notice; as tested; a second run gives notices only and changes nothing; the grants
--      of the 15, the 13 revoked, the 4 comments; its self-test leaves nothing.
--   A. Every money path earns nothing (paid in full, part-paid then settled, the payment
--      corrected, a correction raising the total, reopened straight to paid, reopened and settled
--      again, cancelled, refunded): no customer row, no affiliate row, no recount in the Audit Log,
--      no record of the invoices; the invoice still records its affiliate. Controls: the recount
--      called as the database owner earns from the same days, and the UNDO's trigger, put back in
--      a block that is undone, earns from a payment.
--   B. History stays: a paid day's months (one used) and its affiliate reward (part handed over)
--      with the record of its invoices stay byte for byte through a refund, a cancellation,
--      corrections and a reopening of those invoices.
--   C. The rest of the trigger is unchanged (the 476 suite's figures): purchased therapy, a
--      Credit Package's credit and Bonus, a Premium Bundle's vouchers chosen at the till and an
--      allowance for the rest, credit released as it is paid and trimmed when a payment goes down.
--   D. New Credit Package sales: a package starts with its reward off and an edit keeps it off;
--      it gives credit only; a split takes no reward vouchers; the previews show none; the
--      reward can be switched off, never on; a Premium Bundle's still switches both ways.
--   E. Older Credit Package units still work: issued, listed, shown and handed over by staff of
--      the store until their own date; a refund or cancellation is refused in the new words until
--      the review withdraws what was not handed over and keeps what was (an Owner or Manager);
--      the plan lists them; the review of an older sale shows the new words.
--
-- Run from the repository's root, on a copy of production at 501 (or with -v skip_install=1
-- where 502 is in already; -v nomig=1 is read the same way):
--   psql -X -v ON_ERROR_STOP=1 -d <copy> -f scripts/therapy/tests/legacy-retired-502.sql
-- Disposable database only; everything is rolled back. Every name and code is invented
-- (@example.invalid); the phones are fictional (+61 2 5550 nnnn).
\set ON_ERROR_STOP on
\if :{?nomig}
\set skip_install 1
\endif
\set t502_mig `cat supabase/502_legacy_therapy_retired.sql`
\set t502_undo `cat scripts/therapy/undo-502.sql`
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';
set local search_path = public;
select set_config('t502.mig', :'t502_mig', true), set_config('t502.undo', :'t502_undo', true) \g /dev/null
\if :{?skip_install}
select set_config('t502.skip', '1', true) \g /dev/null
\else
select set_config('t502.skip', '0', true) \g /dev/null
\endif
set local client_min_messages = warning;

create temp table t502(k text primary key, id uuid);
create temp table t502_res(n serial primary key, ok boolean, label text);
create temp sequence t502_phone;
create function pg_temp.id(p_k text) returns uuid language sql as $f$ select id from t502 where k = p_k $f$;
create function pg_temp.put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t502 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.ok(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  insert into t502_res(ok, label) values (coalesce(p_ok, false), p_label);
  if not coalesce(p_ok, false) then raise warning 'FAIL %', p_label; end if;
end $f$;
-- Runs p_sql as this person signed in, with their grants; with p_db, as the database owner with
-- this person recorded (how the go-live scripts run); with no person, as the database owner with
-- nobody signed in. 'ok:<answer>', or 'sqlstate:words' when refused.
create function pg_temp.try_as(p_who uuid, p_sql text, p_db boolean default false) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    perform set_config('request.jwt.claims', '', true);
    if p_who is not null then
      perform set_config('request.jwt.claims', json_build_object('sub', p_who, 'role', 'authenticated')::text, true);
      if not p_db then execute 'set local role authenticated'; end if;
    end if;
    execute p_sql into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    return s || ':' || m;
  end;
end $f$;
-- The same, when a refusal is not the point: a refusal stops the suite.
create function pg_temp.must(p_who uuid, p_sql text, p_db boolean default false) returns text language plpgsql as $f$
declare t text;
begin
  t := pg_temp.try_as(p_who, p_sql, p_db);
  if t not like 'ok:%' then raise exception 'T502: refused (%): %', t, left(p_sql, 300); end if;
  return substr(t, 4);
end $f$;

-- ── What 502 changes, and how it is read ─────────────────────────────────────────────────────
create temp table t502_sig(n int primary key, sig text, before_md5 text, after_md5 text);
insert into t502_sig values
  (1, 'trg_create_therapy_on_paid()', '012ae4e305b9870fa5596f740c0427b9', '7b63da063576a5c952cc5abe6c53f13d'),
  (2, 'backfill_legacy_qualification(date,date,uuid)', '00fe803a88ef5fd30acbfe151d87ae66', '40e44a1cdf43f336d765cdb2bd0f8235'),
  (3, 'therapy_list_page(text,text,text,integer,integer)', 'fa78a96f7fbb74d770b54a8b700ad4b4', '729ae2d27eadbf2a996dac13d608629c'),
  (4, 'delete_customer(uuid,text,text)', '5b407735574fc3cacd8067c4dc8213f4', 'b1f3b08c85ef55f54effa7830d87eed1'),
  (5, 'customer_overview(uuid)', '74e9cddfb699ed78369ee4d01578116e', '91912a72aab437420f16cd7fe3b67da2'),
  (6, 'report_therapy()', 'f3d9575eea995494c153240a3d9b72df', 'f43af7b0f6a8a80054808ab6fb672d59'),
  (7, 'dashboard_alerts_summary()', '2b632d0dcc23b82c6ef4e1438271debf', '71c01b0053937347a63b311b7eca5734'),
  (8, 'therapy_customer_summary(text,integer,integer,boolean)', '55b69d8530418f74416bce23e3bdaa66', 'af030b297c6ab5dc2c64bde101722279'),
  (9, 'therapy_customer_detail(uuid)', '80abbc0a7b61f91c0a4248f9b18d8f4e', '8c9143f82bfda412f26e743dbad47181'),
  (10, 'therapy_customer_voucher_balances(uuid)', '935a3268c6a9b46447d979f85eaa867e', '92e722a77520f3c2a8e6370816598a0e'),
  (11, 'set_catalogue_reward(text,uuid,boolean)', '0987f23df3fbb1863346c4c46c04fad2', 'a8a9c9ae3862a348217cc434185f9781'),
  (12, 'upsert_credit_package(uuid,text,numeric,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,numeric,text,uuid[],uuid[],boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,numeric)',
       '08f822f0e1c4ad41aa4b0e4b8582d0e5', 'a2e8ec73a38b60ae7c05f573fba25ea8'),
  (13, 'assert_invoice_credit_source_evidence(uuid,uuid)', '64059b05526f32239ce1e60c6de39508', 'fccb792813962e2aae95db9e4dc8d3b6'),
  (14, 'invoice_benefit_review_options(uuid)', 'a7ee838459a52741501d1c019fffcbee', '4e382ae362f077eed9ae941ad3c9e930'),
  (15, 'resolve_invoice_credit_rewards(uuid,text,uuid,boolean,uuid)', '828a4b535604aef1314f55453d67f6e2', 'faeb135e402b5b5d7bdfccadc19553fc');
create temp table t502_revoked(sig text primary key);
insert into t502_revoked values
  ('affiliate_legacy_day_summary(date)'), ('backfill_legacy_qualification(date,date,uuid)'),
  ('claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)'), ('invoice_legacy_entitlements(uuid)'),
  ('invoice_therapy_summary(uuid)'), ('legacy_qualification_diagnose(uuid,uuid,date)'),
  ('legacy_qualification_group(uuid,uuid,date)'), ('legacy_reward_options(uuid)'),
  ('legacy_reward_options_diagnostic(uuid)'), ('legacy_setup_status()'),
  ('therapy_map_entitlement_tier(uuid,text,text)'), ('therapy_reward_mapping_preview()'),
  ('upsert_legacy_rule(uuid,uuid,text,numeric,text,integer,integer,integer,boolean,date,text)');
create temp table t502_retired(sig text primary key);
insert into t502_retired values
  ('recompute_legacy_qualification(uuid,uuid,date)'), ('recompute_affiliate_legacy_qualification(uuid,date)'),
  ('recompute_affiliates_for_customer_day(uuid,date)'), ('recompute_legacy_qualification_for_invoice(uuid)');
select set_config('t502.note', 'Retired by 502 (10 Nov 2026). Do not run: it drops therapy_entitlement_invoices history.', true) \g /dev/null

create function pg_temp.fp() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(oid)), '' order by oid::regprocedure::text)) || '/' || count(*)
    from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f' $f$;
create function pg_temp.md5_of(p_sig text) returns text language sql as $f$
  select md5(pg_get_functiondef(to_regprocedure('public.' || p_sig))) $f$;
create function pg_temp.acl_of(p_sig text) returns text language sql as $f$
  select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
create function pg_temp.note_of(p_sig text) returns text language sql as $f$
  select obj_description(to_regprocedure('public.' || p_sig), 'pg_proc') $f$;
-- The triggers on invoices, but for the one named.
create function pg_temp.triggers(p_but text default '') returns text language sql as $f$
  select coalesce(string_agg(t.tgname || ' ' || t.tgenabled::text || ' ' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname), '')
    from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and not t.tgisinternal and t.tgname <> p_but $f$;
create function pg_temp.guard_on() returns boolean language sql as $f$
  select exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') $f$;
-- Everything a run of 502 could change: the functions, the triggers on invoices, every function's
-- rights and comment.
create function pg_temp.state() returns text language sql as $f$
  select md5(concat_ws(E'\n#\n', pg_temp.fp(), pg_temp.triggers(),
    (select string_agg(p.oid::regprocedure::text || ' ' || coalesce((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x), '')
                       || ' ' || coalesce(obj_description(p.oid, 'pg_proc'), ''), E'\n' order by p.oid::regprocedure::text)
       from pg_proc p where p.pronamespace = 'public'::regnamespace))) $f$;

-- ── The app's calls ──────────────────────────────────────────────────────────────────────────
create function pg_temp.cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into public.customers(full_name, phone)
  values ('T502 ' || p_k || ' Buyer', '+6125550' || lpad((5200 + nextval('t502_phone'))::text, 4, '0'))
  returning id into c;
  return pg_temp.put(p_k, c);
end $f$;
create function pg_temp.name_of(p_cust uuid) returns text language sql as $f$ select full_name from public.customers where id = p_cust $f$;
-- An affiliate: a customer with an active affiliate record (the record is what the invoice form names).
create function pg_temp.affiliate(p_k text) returns uuid language plpgsql as $f$
declare c uuid; a uuid;
begin
  c := pg_temp.cust(p_k);
  insert into public.customer_affiliates(customer_id, status, activated_at) values (c, 'active', now()) returning id into a;
  perform pg_temp.put(p_k || '_rec', a);
  return c;
end $f$;
-- Invoice lines: p_qty Facial vouchers (S$50 each), a Credit Package, the Premium Bundle with
-- p_chosen of its vouchers chosen at the till, a therapy package.
create function pg_temp.vline(p_qty int) returns jsonb language sql as $f$
  select jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.id('vf'), 'quantity', p_qty) $f$;
create function pg_temp.cpline(p_pkg uuid) returns jsonb language sql as $f$
  select jsonb_build_object('kind', 'credit_package', 'credit_package_id', p_pkg, 'quantity', 1) $f$;
create function pg_temp.pbline(p_pb uuid, p_chosen int) returns jsonb language sql as $f$
  select jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', p_pb, 'quantity', 1,
    'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.id('vf'), 'quantity', p_chosen))) $f$;
create function pg_temp.tpline(p_pkg uuid) returns jsonb language sql as $f$
  select jsonb_build_object('kind', 'therapy', 'therapy_package_id', p_pkg, 'quantity', 1) $f$;
-- The invoice form: these lines for this customer at this store, with the affiliate record named.
create function pg_temp.inv(p_who uuid, p_store uuid, p_cust uuid, p_line jsonb, p_aff uuid default null) returns uuid language sql as $f$
  select pg_temp.must(p_who, format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
    p_store, p_cust, jsonb_build_array(p_line), jsonb_build_object('business_date', public.sg_today()::text)
      || case when p_aff is null then '{}'::jsonb else jsonb_build_object('affiliate_id', p_aff) end))::uuid $f$;
create function pg_temp.outstanding(p_inv uuid) returns numeric language sql as $f$
  select greatest(public.invoice_charge_total(p_inv) - public.invoice_net_received(p_inv), 0) $f$;
-- The Pay dialog: p_amount in cash, or all that is owed.
create function pg_temp.pay(p_who uuid, p_inv uuid, p_amount numeric default null) returns void language plpgsql as $f$
begin
  perform pg_temp.must(p_who, format('select public.record_invoice_settlement(%L::uuid, %L::jsonb, gen_random_uuid())::text', p_inv,
    jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.id('pm'),
      'amount', coalesce(p_amount, pg_temp.outstanding(p_inv)), 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb)));
end $f$;
-- Correct payment on the invoice's current receipt: its amount becomes p_amount.
create function pg_temp.fix_pay(p_who uuid, p_inv uuid, p_amount numeric) returns void language plpgsql as $f$
begin
  perform pg_temp.must(p_who, format('select public.correct_invoice_payment(%L::uuid, %L::numeric, public.sg_today(), %L::uuid, %L, gen_random_uuid())::text',
    (select p.id from public.invoice_payments p where p.invoice_id = p_inv and p.entry_kind in ('receipt', 'correction_replacement')
        and not exists (select 1 from public.invoice_payments q where q.corrects_payment_id = p.id and q.entry_kind = 'correction_reversal')
      order by p.created_at desc, p.id desc limit 1),
    p_amount, pg_temp.id('pm'), 'T502 correct payment'));
end $f$;
-- The invoice form's correction of a paid invoice: its one line becomes p_qty.
create function pg_temp.raise_qty(p_who uuid, p_inv uuid, p_qty int) returns void language plpgsql as $f$
begin
  perform pg_temp.must(p_who, format('select public.correct_invoice(%L::uuid, %L::jsonb, %L::jsonb, %L, gen_random_uuid())::text', p_inv,
    (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind, 'voucher_id', it.voucher_id,
                        'quantity', p_qty, 'unit_price', it.unit_price)) order by it.id)
       from public.invoice_items it where it.invoice_id = p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = p_inv),
      'customer_id', (select customer_id from public.invoices where id = p_inv), 'store_id', (select store_id from public.invoices where id = p_inv)),
    'T502 one more'));
end $f$;
create function pg_temp.cancel(p_who uuid, p_inv uuid) returns text language sql as $f$
  select pg_temp.try_as(p_who, format('select public.cancel_invoice_recorded(%L::uuid, %L, gen_random_uuid())::text', p_inv, 'T502 cancelled')) $f$;
create function pg_temp.reopen(p_who uuid, p_inv uuid) returns text language sql as $f$
  select pg_temp.try_as(p_who, format('select public.reopen_invoice(%L::uuid, %L, gen_random_uuid())::text', p_inv, 'T502 reopened')) $f$;
-- The Finance panel's refund by line: every unused benefit of every line, from the receipts that
-- still hold the money.
create function pg_temp.refund(p_who uuid, p_inv uuid) returns text language plpgsql as $f$
declare opts jsonb; v_lines jsonb := '[]'; v_src jsonb := '[]'; v_tot numeric := 0; it record; ben jsonb; tot numeric; s jsonb; v_left numeric;
begin
  opts := pg_temp.must(p_who, format('select public.invoice_refund_options(%L::uuid)::text', p_inv))::jsonb;
  for it in select l->>'invoice_item_id' as item from jsonb_array_elements(opts->'lines') l loop
    select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric)), sum((b->>'max_refund')::numeric)
      into ben, tot from jsonb_array_elements(opts->'benefits') b where b->>'invoice_item_id' = it.item and (b->>'max_refund')::numeric > 0;
    if ben is null then continue; end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('invoice_item_id', it.item, 'amount', tot, 'benefits', ben));
    v_tot := v_tot + tot;
  end loop;
  v_left := v_tot;
  for s in select * from jsonb_array_elements(opts->'sources') loop
    exit when v_left <= 0;
    if (s->>'remaining')::numeric <= 0 then continue; end if;
    v_src := v_src || jsonb_build_array(jsonb_build_object('payment_id', s->>'payment_id', 'amount', least((s->>'remaining')::numeric, v_left)));
    v_left := v_left - least((s->>'remaining')::numeric, v_left);
  end loop;
  return pg_temp.try_as(p_who, format('select public.refund_invoice_recorded(%L::uuid, %L::jsonb, %L::jsonb, %L::jsonb, %L, gen_random_uuid())::text',
    p_inv, v_lines, v_src, '[]', 'T502 refunded'));
end $f$;
create function pg_temp.status(p_inv uuid) returns text language sql as $f$
  select status::text || ' ' || paid_amount::text || '/' || total_amount::text from public.invoices where id = p_inv $f$;
-- What a paid day earned the customer and the affiliate (rows earned by a customer's or an
-- affiliate's paid day: earner_kind customer or affiliate), whether the customer's day was
-- recounted (the Audit Log's legacy_qualification_recomputed), and the record of which invoices
-- earned it (therapy_entitlement_invoices).
create function pg_temp.earned(p_cust uuid, p_aff uuid, p_inv uuid) returns text language sql as $f$
  select concat_ws(' ',
    (select count(*) from public.therapy_entitlements where customer_id = p_cust and earner_kind in ('customer', 'affiliate')) || ' customer',
    (select count(*) from public.therapy_entitlements where customer_id = p_aff and earner_kind in ('customer', 'affiliate')) || ' affiliate',
    (select count(*) from public.audit_logs where action = 'legacy_qualification_recomputed' and new_data->>'customer' = p_cust::text) || ' recount',
    (select count(*) from public.therapy_entitlement_invoices where invoice_id = p_inv) || ' links') $f$;
-- A customer's and an affiliate's paid-day rewards, the record of their invoices, the vouchers
-- handed over from them and the hand-overs, byte for byte.
create function pg_temp.history(p_people uuid[]) returns text language sql as $f$
  select md5(concat_ws(E'\n#\n',
    (select string_agg(to_jsonb(e)::text, E'\n' order by e.id) from public.therapy_entitlements e
      where e.customer_id = any(p_people) and e.earner_kind in ('customer', 'affiliate')),
    (select string_agg(to_jsonb(t)::text, E'\n' order by t.entitlement_id, t.invoice_id) from public.therapy_entitlement_invoices t
      join public.therapy_entitlements e on e.id = t.entitlement_id where e.customer_id = any(p_people)),
    (select string_agg(to_jsonb(v)::text, E'\n' order by v.id) from public.customer_reward_vouchers v
      join public.therapy_entitlements e on e.id = v.entitlement_id where e.customer_id = any(p_people) and e.earner_kind in ('customer', 'affiliate')),
    (select string_agg(to_jsonb(c)::text, E'\n' order by c.id) from public.voucher_claims c
      join public.therapy_entitlements e on e.id = c.entitlement_id where e.customer_id = any(p_people) and e.earner_kind in ('customer', 'affiliate')),
    (select count(*)::text from public.audit_logs where action = 'legacy_qualification_recomputed'))) $f$;
-- A customer's credit by category ('paid 100.00 bonus 10.00'), from their lots.
create function pg_temp.credit(p_cust uuid) returns text language sql as $f$
  select coalesce(string_agg(category || ' ' || amt::text, ' ' order by category), 'none')
    from (select l.category::text as category, sum(l.remaining_amount) as amt from public.customer_credit_lots l
           where l.customer_id = p_cust and l.status = 'active' and l.remaining_amount > 0 group by 1) x $f$;
-- A sale's reward rows (a Credit Package's reward vouchers).
create function pg_temp.reward_rows(p_sale uuid) returns bigint language sql as $f$
  select count(*) from public.therapy_entitlements where qualification_group_id = public.credit_package_reward_group(p_sale) $f$;

-- ═════ Fixtures (invented) ═════
do $fx$
declare r record; u uuid;
begin
  for r in select * from (values ('own', 'owner'), ('mgr', 'manager'), ('stf', 'staff'), ('stfb', 'staff')) as t(k, role) loop
    insert into auth.users (id, email) values (gen_random_uuid(), 't502-' || r.k || '@example.invalid') returning id into u;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (u, 'T502 ' || r.k, 't502-' || r.k || '@example.invalid', r.role::public.user_role, true);
    perform pg_temp.put(r.k, u);
  end loop;
  -- Store L, where paid days earned (the rules are its own); store A, where Credit Packages and
  -- bundles are sold (no rule reaches it); store B, where stfb works alone.
  insert into public.stores (name, code, country_code) values ('T502 Store L', 'T502-L', 'SG') returning id into u; perform pg_temp.put('sl', u);
  insert into public.stores (name, code, country_code) values ('T502 Store A', 'T502-A', 'SG') returning id into u; perform pg_temp.put('sa', u);
  insert into public.stores (name, code, country_code) values ('T502 Store B', 'T502-B', 'SG') returning id into u; perform pg_temp.put('sb', u);
  insert into public.user_store_assignments(user_id, store_id)
  values (pg_temp.id('mgr'), pg_temp.id('sl')), (pg_temp.id('mgr'), pg_temp.id('sa')),
         (pg_temp.id('stf'), pg_temp.id('sl')), (pg_temp.id('stf'), pg_temp.id('sa')),
         (pg_temp.id('stfb'), pg_temp.id('sb'));
  insert into public.payment_methods (name, is_active) values ('T502 Cash', true) returning id into u; perform pg_temp.put('pm', u);
  -- Two free-session vouchers (normal, unlimited stock), the kind a reward hands over.
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('T502 Facial', 'T502-FAC', 'normal', 'unlimited', 50, true) returning id into u; perform pg_temp.put('vf', u);
  insert into public.voucher_store_prices(voucher_id, store_id, selling_price, available_at_store)
  values (u, pg_temp.id('sl'), 50, true), (u, pg_temp.id('sa'), 50, true);
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('T502 Massage', 'T502-MAS', 'normal', 'unlimited', 60, true) returning id into u; perform pg_temp.put('vm', u);
  insert into public.voucher_store_prices(voucher_id, store_id, selling_price, available_at_store)
  values (u, pg_temp.id('sa'), 60, true);
end $fx$;
-- The qualification rules at store L, through the rule form's own function, as the database owner
-- with the Owner recorded (502 takes it from signed-in logins): a customer's day of S$100 earns a
-- month; an affiliate's S$40 left over earns 10 vouchers. On a database that holds other rules,
-- they are switched off first, in this transaction, so only these count (a copy of production
-- has none).
update public.therapy_package_rules set is_active = false where is_active and deleted_at is null;
select pg_temp.put('rule_month', pg_temp.must(pg_temp.id('own'), format($q$select public.upsert_legacy_rule(null, %L::uuid, 'T502 month', 100, 'unlimited', 1, null, 365, true, public.sg_today() - 1, 'customer')::text$q$, pg_temp.id('sl')), true)::uuid) \g /dev/null
select pg_temp.put('rule_aff', pg_temp.must(pg_temp.id('own'), format($q$select public.upsert_legacy_rule(null, %L::uuid, 'T502 affiliate', 40, 'voucher', null, 10, 365, true, public.sg_today() - 1, 'affiliate')::text$q$, pg_temp.id('sl')), true)::uuid) \g /dev/null

-- ═════ S Where it starts ═════
do $s$
declare
  n_before int := (select count(*) from t502_sig where pg_temp.md5_of(sig) = before_md5);
  n_after int := (select count(*) from t502_sig where pg_temp.md5_of(sig) = after_md5);
  n_revoked int := (select count(*) from t502_revoked where not has_function_privilege('authenticated', to_regprocedure('public.' || sig), 'execute'));
  n_noted int := (select count(*) from t502_retired where pg_temp.note_of(sig) = current_setting('t502.note'));
begin
  if current_setting('t502.skip') = '1' then
    perform pg_temp.ok(n_after = 15 and not pg_temp.guard_on() and n_revoked = 13 and n_noted = 4,
      format('S1 502 is in: %s of 15 at their AFTER, refund guard %s, %s of 13 revoked, %s of 4 commented',
             n_after, case when pg_temp.guard_on() then 'on' else 'gone' end, n_revoked, n_noted));
    if not (n_after = 15 and not pg_temp.guard_on() and n_revoked = 13 and n_noted = 4) then
      raise exception 'T502: -v skip_install=1 was given, but 502 is not in as tested on this database. Nothing else was run.'; end if;
  else
    perform pg_temp.ok(n_before = 15 and pg_temp.guard_on() and n_revoked = 0 and n_noted = 0,
      format('S1 502 is not in: %s of 15 at their BEFORE, refund guard %s, %s of 13 revoked, %s of 4 commented',
             n_before, case when pg_temp.guard_on() then 'on' else 'gone' end, n_revoked, n_noted));
    if not (n_before = 15 and pg_temp.guard_on() and n_revoked = 0 and n_noted = 0) then
      raise exception 'T502: this database is neither production at 501 nor at 502 (load production''s bodies first, or add -v skip_install=1 where 502 is in). Nothing else was run.'; end if;
  end if;
end $s$;

-- ═════ R Without 502: a paid day earns ═════
\if :{?skip_install}
do $$ begin raise warning 'NOTE  R and I are skipped: 502 is in already'; end $$;
\else
do $r$
declare
  own uuid := pg_temp.id('own'); stf uuid := pg_temp.id('stf'); sl uuid := pg_temp.id('sl');
  c uuid; aff uuid; i uuid; t text; j jsonb; pkg uuid;
begin
  aff := pg_temp.affiliate('raff');
  c := pg_temp.cust('r1');
  i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), pg_temp.id('raff_rec'));
  perform pg_temp.pay(stf, i);
  perform pg_temp.ok((select count(*) = 1 and bool_and(entitlement_kind = 'unlimited' and status = 'pending_activation' and rule_id = pg_temp.id('rule_month'))
                        from public.therapy_entitlements where customer_id = c and earner_kind = 'customer'),
    'R1 without 502, S$150 paid by a customer at S$100 earns a month: ' || pg_temp.earned(c, aff, i));
  perform pg_temp.ok((select count(*) = 1 and bool_and(entitlement_kind = 'voucher' and voucher_qty = 10 and status = 'pending_activation')
                        from public.therapy_entitlements where customer_id = aff and earner_kind = 'affiliate'),
    'R2 and the S$50 left over earns the affiliate on the invoice 10 vouchers');
  perform pg_temp.ok(pg_temp.earned(c, aff, i) = '1 customer 1 affiliate 1 recount 1 links',
    'R3 the day is recounted in the Audit Log and records its invoice: ' || pg_temp.earned(c, aff, i));
  j := pg_temp.must(own, format('select public.therapy_list_page(%L, %L, %L, 50, 0)::text', 'legacy', pg_temp.name_of(c), 'all'))::jsonb;
  perform pg_temp.ok((j->>'total')::int = 1 and j->'rows'->0->>'earner_kind' = 'customer', 'R4 the list''s old name lists it: ' || j::text);
  t := pg_temp.try_as(own, format('select public.delete_customer(%L::uuid, %L, %L)::text', c, pg_temp.name_of(c), 'T502'));
  perform pg_temp.ok(t = 'P0001:This customer has 1 legacy therapy entitlement(s) still open. Settle them first.', 'R5 and Delete customer is refused by it: ' || t);
  -- The month is used (as the only free month ever used was): refunding its day is refused.
  update public.therapy_entitlements set status = 'expired', activation_date = public.sg_today() - 40, expiry_date = public.sg_today() - 10,
         claimed_at = now(), claimed_by = own
   where customer_id = c and earner_kind = 'customer';
  t := pg_temp.refund(own, i);
  perform pg_temp.ok(t = 'P0001:This invoice cannot be refunded: the customer''s Legacy therapy from that day has already been activated. Cancel or complete the therapy first.'
                     and pg_temp.status(i) = 'paid 150.00/150.00', 'R6 refunding the day of a used month is refused: ' || t);
  -- The Credit Package window.
  pkg := pg_temp.must(own, format('select public.upsert_credit_package(null, %L, 1000, 1000, true, public.sg_today(), null, %L, p_store_ids => array[%L]::uuid[])::text',
    'T502 Before', 'third_party', pg_temp.id('sa')))::uuid;
  perform pg_temp.ok((select grants_reward from public.credit_packages where id = pkg), 'R7 a new Credit Package starts with its reward on');
  perform pg_temp.must(own, format('select public.set_catalogue_reward(%L, %L::uuid, false)::text', 'credit_package', pkg));
  t := pg_temp.try_as(own, format('select public.set_catalogue_reward(%L, %L::uuid, true)::text', 'credit_package', pkg));
  perform pg_temp.ok(t like 'ok:%' and (select grants_reward from public.credit_packages where id = pkg), 'R8 and its reward can be switched off and on again: ' || t);
end $r$;

-- ═════ I Install ═════
create temp table i_before as
  select pg_temp.state() as s, pg_temp.fp() as f, pg_temp.triggers('legacy_refund_guard') as t,
         (select count(*) from public.audit_logs) as audits;
create temp table i_acl as select sig, pg_temp.acl_of(sig) as acl from t502_sig;
create temp table i_racl as select sig, pg_temp.acl_of(sig) as acl from t502_revoked;
create temp table i_md5 as
  select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as m from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
create temp table i_seq as select sequencename::text as name, last_value from pg_sequences where schemaname = 'public';

-- Not as tested: nothing changes. Each case is tried in a block that is then undone.
do $i$
declare e text; s0 text := (select s from i_before); a text;
begin
  -- A function it patches, changed since.
  begin
    execute replace(pg_get_functiondef('public.report_therapy()'::regprocedure), E'AS $function$\n', E'AS $function$\n-- T502: changed since\n');
    begin execute current_setting('t502.mig'); e := null; exception when others then e := sqlerrm; end;
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null;
  end;
  perform pg_temp.ok(e like '502: public.report_therapy() is not the version this was tested against (md5 %). Re-read it and re-test before applying.',
    'I1 a report_therapy other than the tested one stops it: ' || coalesce(e, 'it ran'));
  perform pg_temp.ok(pg_temp.state() = s0, 'I2 and nothing changed');
  -- A function it relies on, changed since.
  begin
    execute replace(pg_get_functiondef('public.legacy_lowest_rule(uuid,date)'::regprocedure), E'AS $function$\n', E'AS $function$\n-- T502: changed since\n');
    begin execute current_setting('t502.mig'); e := null; exception when others then e := sqlerrm; end;
    raise exception using errcode = 'T5022';
  exception when sqlstate 'T5022' then null;
  end;
  perform pg_temp.ok(e = '502: public.legacy_lowest_rule(uuid,date) is missing or not the version this was tested against. Re-read it and re-test before applying.'
                     and pg_temp.state() = s0, 'I3 a function it relies on, changed, stops it with nothing changed: ' || coalesce(e, 'it ran'));
  -- The refund guard switched off.
  begin
    alter table public.invoices disable trigger legacy_refund_guard;
    begin execute current_setting('t502.mig'); e := null; exception when others then e := sqlerrm; end;
    raise exception using errcode = 'T5023';
  exception when sqlstate 'T5023' then null;
  end;
  perform pg_temp.ok(e = '502: the trigger legacy_refund_guard on public.invoices is not the one this was tested against. Re-read it and re-test before applying.'
                     and pg_temp.state() = s0, 'I4 a refund guard not as tested stops it with nothing changed: ' || coalesce(e, 'it ran'));
  -- Rights not as tested on a function it revokes.
  begin
    grant execute on function public.legacy_setup_status() to anon;
    begin execute current_setting('t502.mig'); e := null; exception when others then e := sqlerrm; end;
    raise exception using errcode = 'T5024';
  exception when sqlstate 'T5024' then null;
  end;
  perform pg_temp.ok(e like '502: the rights on public.legacy_setup_status() are not the ones this was tested against (%). Re-read them and re-test before applying.'
                     and pg_temp.state() = s0, 'I5 rights not as tested stop it with nothing changed: ' || coalesce(e, 'it ran'));

  -- The refund guard already gone: a notice (made an error here, to read its words), and it installs.
  begin
    drop trigger legacy_refund_guard on public.invoices;
    begin
      execute replace(current_setting('t502.mig'), 'raise notice ''502: the trigger legacy_refund_guard', 'raise exception ''502: the trigger legacy_refund_guard');
      e := null;
    exception when others then e := sqlerrm; end;
    execute current_setting('t502.mig');
    a := (select count(*) filter (where pg_temp.md5_of(sig) = after_md5) from t502_sig)::text || ' at AFTER, guard '
         || case when pg_temp.guard_on() then 'on' else 'gone' end;
    raise exception using errcode = 'T5025';
  exception when sqlstate 'T5025' then null;
  end;
  perform pg_temp.ok(e = '502: the trigger legacy_refund_guard on public.invoices is already gone; left alone',
    'I6 with the refund guard already gone it says so: ' || coalesce(e, 'nothing'));
  perform pg_temp.ok(a = '15 at AFTER, guard gone', 'I7 and installs all the same: ' || coalesce(a, 'it did not'));
  perform pg_temp.ok(pg_temp.state() = s0, 'I8 (tried in a block that was undone)');
end $i$;

-- As tested.
do $i$
declare e text; s1 text; n int;
begin
  execute current_setting('t502.mig');
  n := (select count(*) from t502_sig where pg_temp.md5_of(sig) = after_md5);
  perform pg_temp.ok(n = 15, format('I9 installed as tested: %s of 15 at their AFTER', n));
  perform pg_temp.ok(not pg_temp.guard_on(), 'I10 the refund guard is gone');
  perform pg_temp.ok(pg_temp.triggers('legacy_refund_guard') = (select t from i_before), 'I11 the other triggers on invoices are as they were');
  perform pg_temp.ok(not exists (select 1 from i_acl b where b.sig <> 'backfill_legacy_qualification(date,date,uuid)' and pg_temp.acl_of(b.sig) is distinct from b.acl),
    'I12 the grants of the 14 patched functions not revoked are as they were');
  perform pg_temp.ok(not exists (select 1 from t502_revoked r where pg_temp.acl_of(r.sig) <> 'postgres=X/postgres,service_role=X/postgres'
                                    or has_function_privilege('authenticated', to_regprocedure('public.' || r.sig), 'execute')),
    'I13 the 13 functions only Legacy used are the database owner''s and the service role''s alone');
  perform pg_temp.ok(not exists (select 1 from i_racl r where r.acl <> 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'),
    'I14 (before, signed-in logins could call all 13)');
  perform pg_temp.ok(not exists (select 1 from t502_retired r where pg_temp.note_of(r.sig) is distinct from current_setting('t502.note')),
    'I15 the 4 retired recounts say not to run them');
  perform pg_temp.ok(not exists (select 1 from i_md5 b where not exists (select 1 from t502_sig s where s.sig = b.sig)
                                    and b.m is distinct from pg_temp.md5_of(b.sig))
                     and split_part(pg_temp.fp(), '/', 2) = split_part((select f from i_before), '/', 2),
    'I16 no other function changed, and none was added or dropped');
  -- A second run.
  s1 := pg_temp.state();
  execute current_setting('t502.mig');
  perform pg_temp.ok(pg_temp.state() = s1, 'I17 a second run changes nothing');
  begin
    execute replace(current_setting('t502.mig'), 'raise notice', 'raise exception');
    e := null;
  exception when others then e := sqlerrm; end;
  perform pg_temp.ok(e = '502: public.trg_create_therapy_on_paid() is already this version; left alone',
    'I18 and says so (its first notice, made an error here to read it): ' || coalesce(e, 'nothing'));
  -- Its self-test leaves nothing.
  perform pg_temp.ok(not exists (select 1 from auth.users where email like '502chk-%')
      and not exists (select 1 from public.profiles where email like '502chk-%')
      and not exists (select 1 from public.stores where code like '502-%')
      and not exists (select 1 from public.customers where full_name like '502 Check%')
      and not exists (select 1 from public.invoices where invoice_no like '502-CHK-%')
      and not exists (select 1 from public.therapy_entitlements where entitlement_no like '502-CHK-%')
      and not exists (select 1 from public.therapy_package_rules where name like '502 Check%')
      and not exists (select 1 from public.credit_packages where name like '502 Check%')
      and (select count(*) from public.audit_logs) = (select audits from i_before),
    'I19 its self-test left no login, store, customer, invoice, reward, rule, package or Audit Log entry');
  perform pg_temp.ok(not exists (select 1 from i_seq b left join pg_sequences s on s.schemaname = 'public' and s.sequencename = b.name
                                  where s.last_value is distinct from b.last_value),
    'I20 and used no number: every sequence is where it was');
end $i$;
\endif

-- ═════ A Every money path earns nothing ═════
-- Store L's rules are on (a customer's S$100 earns a month; an affiliate's S$40 left over, 10
-- vouchers), and every invoice names an active affiliate. Each path has its own customer.
create temp table a_base as
  select (select count(*) from public.audit_logs where action = 'legacy_qualification_recomputed') as recounts,
         (select count(*) from public.therapy_entitlement_invoices) as links,
         (select count(*) from public.therapy_entitlements where earner_kind in ('customer', 'affiliate')) as rows_;
do $a$
declare
  own uuid := pg_temp.id('own'); mgr uuid := pg_temp.id('mgr'); stf uuid := pg_temp.id('stf'); sl uuid := pg_temp.id('sl');
  aff uuid := pg_temp.affiliate('aaff'); rec uuid := pg_temp.id('aaff_rec');
  c uuid; i uuid; t text; nothing text := '0 customer 0 affiliate 0 recount 0 links';
begin
  -- A1 Paid in full.
  c := pg_temp.cust('a1'); i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec); perform pg_temp.put('ai1', i);
  perform pg_temp.pay(stf, i);
  perform pg_temp.ok(pg_temp.status(i) = 'paid 150.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A1 S$150 paid in full through the Pay dialog earns nothing: ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  perform pg_temp.ok((select affiliate_snapshot_customer_id = aff and affiliate_active_on_paid from public.invoices where id = i),
    'A2 the invoice still records its affiliate');
  -- A3 Part-paid, then settled.
  c := pg_temp.cust('a2'); i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec); perform pg_temp.put('ai2', i);
  perform pg_temp.pay(stf, i, 50);
  perform pg_temp.ok(pg_temp.status(i) = 'partially_paid 50.00/150.00' and pg_temp.earned(c, aff, i) = nothing
                     and (select affiliate_snapshot_customer_id = aff from public.invoices where id = i),
    'A3 S$50 of S$150 earns nothing (the affiliate is recorded): ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  perform pg_temp.pay(stf, i);
  perform pg_temp.ok(pg_temp.status(i) = 'paid 150.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A4 and settled, nothing: ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  -- A5 The payment corrected, down and up again.
  c := pg_temp.cust('a3'); i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec); perform pg_temp.put('ai3', i);
  perform pg_temp.pay(stf, i);
  perform pg_temp.fix_pay(mgr, i, 100);
  perform pg_temp.ok(pg_temp.status(i) = 'partially_paid 100.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A5 a Manager''s Correct payment to S$100 earns and cancels nothing: ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  perform pg_temp.fix_pay(mgr, i, 150);
  perform pg_temp.ok(pg_temp.status(i) = 'paid 150.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A6 and back to S$150, nothing: ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  -- A7 A correction that raises the total.
  c := pg_temp.cust('a4'); i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec); perform pg_temp.put('ai4', i);
  perform pg_temp.pay(stf, i);
  perform pg_temp.raise_qty(own, i, 4);
  perform pg_temp.ok(pg_temp.status(i) = 'partially_paid 150.00/200.00' and pg_temp.earned(c, aff, i) = nothing,
    'A7 an Owner''s correction to S$200 earns nothing: ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  perform pg_temp.pay(stf, i);
  perform pg_temp.ok(pg_temp.status(i) = 'paid 200.00/200.00' and pg_temp.earned(c, aff, i) = nothing,
    'A8 and settled at S$200, nothing: ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  -- A9 Cancelled with its money held, reopened straight to paid.
  c := pg_temp.cust('a5'); i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec); perform pg_temp.put('ai5', i);
  perform pg_temp.pay(stf, i);
  t := pg_temp.cancel(own, i);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i) = 'cancelled 150.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A9 cancelled, nothing: ' || left(t, 60) || ' ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  t := pg_temp.reopen(own, i);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i) = 'paid 150.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A10 reopened straight to paid, nothing: ' || left(t, 60) || ' ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  -- A11 Cancelled and its money refunded, reopened and settled again.
  c := pg_temp.cust('a6'); i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec); perform pg_temp.put('ai6', i);
  perform pg_temp.pay(stf, i);
  t := pg_temp.cancel(own, i);
  if t like 'ok:%' then t := pg_temp.refund(own, i); end if;
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i) = 'cancelled 0.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A11 cancelled and the S$150 refunded, nothing: ' || left(t, 60) || ' ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  t := pg_temp.reopen(own, i);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i) = 'unpaid 0.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A12 reopened, nothing: ' || left(t, 60) || ' ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  perform pg_temp.pay(stf, i);
  perform pg_temp.ok(pg_temp.status(i) = 'paid 150.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A13 and settled again, nothing: ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  -- A14 Cancelled.
  c := pg_temp.cust('a7'); i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec); perform pg_temp.put('ai7', i);
  perform pg_temp.pay(stf, i);
  t := pg_temp.cancel(own, i);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i) = 'cancelled 150.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A14 paid, then cancelled, nothing: ' || left(t, 60) || ' ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  -- A15 Refunded.
  c := pg_temp.cust('a8'); i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec); perform pg_temp.put('ai8', i);
  perform pg_temp.pay(stf, i);
  t := pg_temp.refund(own, i);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i) = 'refunded 0.00/150.00' and pg_temp.earned(c, aff, i) = nothing,
    'A15 paid, then refunded by line, nothing: ' || left(t, 60) || ' ' || pg_temp.status(i) || ', ' || pg_temp.earned(c, aff, i));
  perform pg_temp.ok((select count(*) from public.invoices x
                       where x.id in (select id from t502 where k like 'ai_') and x.affiliate_snapshot_customer_id = aff and x.affiliate_active_on_paid) = 8,
    'A16 every one of these invoices still records its affiliate');
  perform pg_temp.ok((select count(*) from public.audit_logs where action = 'legacy_qualification_recomputed') = (select recounts from a_base)
                     and (select count(*) from public.therapy_entitlement_invoices) = (select links from a_base)
                     and (select count(*) from public.therapy_entitlements where earner_kind in ('customer', 'affiliate')) = (select rows_ from a_base),
    'A17 nor anywhere else: no reward row, no recount, no record of invoices since these paths began');
end $a$;

-- Controls. The recount called as the database owner (no page calls it) earns from the same days,
-- so they would have earned; and the trigger as it was, put back by the UNDO in a block that is
-- then undone, earns from a payment. Both are undone.
do $a$
declare
  stf uuid := pg_temp.id('stf'); sl uuid := pg_temp.id('sl'); aff uuid := pg_temp.id('aaff'); rec uuid := pg_temp.id('aaff_rec');
  s0 text := pg_temp.state(); k text; units text; res numeric; aff_units bigint; link text; e text; c uuid; i uuid;
begin
  begin
    foreach k in array array['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8'] loop
      perform pg_temp.must(null, format('select public.recompute_legacy_qualification(%L::uuid, %L::uuid, public.sg_today())::text', pg_temp.id(k), sl));
    end loop;
    perform pg_temp.must(null, format('select public.recompute_affiliates_for_customer_day(%L::uuid, public.sg_today())::text', pg_temp.id('a1')));
    units := (select string_agg(x.nm || ' ' || (select count(*) from public.therapy_entitlements te
                                                 where te.customer_id = pg_temp.id(x.nm) and te.earner_kind = 'customer' and te.status = 'pending_activation'), ', ' order by x.nm)
                from unnest(array['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8']) x(nm));
    res := public.affiliate_residual_for_day(aff, public.sg_today());
    aff_units := (select count(*) from public.therapy_entitlements where customer_id = aff and earner_kind = 'affiliate' and status = 'pending_activation');
    link := (select string_agg(tei.contributed_amount::text, ',') from public.therapy_entitlement_invoices tei where tei.invoice_id = pg_temp.id('ai1'));
    raise exception using errcode = 'T502A';
  exception when sqlstate 'T502A' then null;
            when others then units := 'refused: ' || sqlerrm;
  end;
  perform pg_temp.ok(units = 'a1 1, a2 1, a3 1, a4 2, a5 1, a6 1, a7 0, a8 0',
    'A18 control: the recount, called as the database owner, earns from the paid days (S$150 a month, S$200 two; the cancelled and refunded none): ' || coalesce(units, 'nothing'));
  perform pg_temp.ok(res = 250 and aff_units = 6,
    format('A19 control: and the affiliate''s S$%s left over earns 6 rewards of 10 vouchers: %s', res, aff_units));
  perform pg_temp.ok(link = '150.00', 'A20 control: and records the invoice that earned it: ' || coalesce(link, 'none'));
  begin
    execute current_setting('t502.undo');
    c := pg_temp.cust('a9'); i := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec);
    perform pg_temp.pay(stf, i);
    e := pg_temp.earned(c, aff, i);
    raise exception using errcode = 'T502B';
  exception when sqlstate 'T502B' then null;
            when others then e := 'refused: ' || sqlerrm;
  end;
  perform pg_temp.ok(e like '1 customer % affiliate 1 recount 1 links' and split_part(e, ' ', 3) ~ '^[1-9][0-9]*$',
    'A21 control: with the trigger as it was before 502 (the UNDO, undone), the same payment earns: ' || coalesce(e, 'it failed'));
  perform pg_temp.ok(pg_temp.state() = s0 and (select count(*) from public.therapy_entitlements where customer_id = aff) = 0,
    'A22 (the controls were undone: 502 is in, and nothing was earned)');
end $a$;

-- ═════ B History stays ═════
-- A customer's paid day at store L as the recount left it before 502: three invoices (S$150,
-- S$100, S$100) earned 3 months, one of them used, and the S$50 left over earned the affiliate 10
-- vouchers, 4 of them handed over; the first month records the three invoices.
do $b$
declare
  own uuid := pg_temp.id('own'); mgr uuid := pg_temp.id('mgr'); stf uuid := pg_temp.id('stf'); sl uuid := pg_temp.id('sl');
  aff uuid := pg_temp.affiliate('baff'); rec uuid := pg_temp.id('baff_rec');
  c uuid := pg_temp.cust('b1'); i1 uuid; i2 uuid; i3 uuid; first_month uuid; aff_row uuid; h text; t text; j jsonb;
begin
  i1 := pg_temp.inv(stf, sl, c, pg_temp.vline(3), rec); perform pg_temp.pay(stf, i1);
  i2 := pg_temp.inv(stf, sl, c, pg_temp.vline(2), rec); perform pg_temp.pay(stf, i2);
  i3 := pg_temp.inv(stf, sl, c, pg_temp.vline(2), rec); perform pg_temp.pay(stf, i3);
  perform pg_temp.must(null, format('select public.recompute_legacy_qualification(%L::uuid, %L::uuid, public.sg_today())::text', c, sl));
  perform pg_temp.must(null, format('select public.recompute_affiliates_for_customer_day(%L::uuid, public.sg_today())::text', c));
  -- The month that records the day's invoices (the recount's first; one of the three made at once).
  select tei.entitlement_id into first_month from public.therapy_entitlement_invoices tei where tei.invoice_id = i1;
  select id into aff_row from public.therapy_entitlements where customer_id = aff and earner_kind = 'affiliate';
  perform pg_temp.ok((select count(*) from public.therapy_entitlements where customer_id = c and earner_kind = 'customer' and status = 'pending_activation') = 3
                     and (select count(*) from public.therapy_entitlement_invoices where entitlement_id = first_month) = 3
                     and aff_row is not null,
    'B1 the day as the recount left it: 3 months, the first recording the 3 invoices, and the affiliate''s reward');
  -- One month used (as the only free month ever used was), and 4 of the affiliate's vouchers
  -- handed over by staff.
  update public.therapy_entitlements set status = 'expired', activation_date = public.sg_today() - 40, expiry_date = public.sg_today() - 10,
         claimed_at = now(), claimed_by = own where id = first_month;
  j := pg_temp.must(stf, format('select public.claim_entitlement_vouchers(%L::uuid, %L::jsonb, %L)::text', aff_row,
    jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.id('vf'), 'quantity', 4)), 'T502 hand-over'))::jsonb;
  perform pg_temp.ok((j->>'claimed_now')::int = 4, 'B2 4 of the affiliate''s 10 vouchers are handed over');
  h := pg_temp.history(array[c, aff]);

  t := pg_temp.refund(own, i1);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i1) = 'refunded 0.00/150.00',
    'B3 the S$150 invoice of the day whose month was used is refunded (the refund guard is gone): ' || left(t, 80));
  perform pg_temp.ok(pg_temp.history(array[c, aff]) = h, 'B4 the months, the affiliate''s reward, its vouchers and the record of the invoices stay byte for byte');
  t := pg_temp.cancel(own, i2);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i2) = 'cancelled 100.00/100.00' and pg_temp.history(array[c, aff]) = h,
    'B5 a second invoice cancelled: all of it stays: ' || left(t, 80));
  perform pg_temp.fix_pay(mgr, i3, 60);
  perform pg_temp.ok(pg_temp.status(i3) = 'partially_paid 60.00/100.00' and pg_temp.history(array[c, aff]) = h,
    'B6 the third''s payment corrected to S$60: all of it stays: ' || pg_temp.status(i3));
  perform pg_temp.raise_qty(own, i3, 3);
  perform pg_temp.pay(stf, i3);
  perform pg_temp.ok(pg_temp.status(i3) = 'paid 150.00/150.00' and pg_temp.history(array[c, aff]) = h,
    'B7 corrected to S$150 and settled: all of it stays: ' || pg_temp.status(i3));
  t := pg_temp.reopen(own, i2);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i2) = 'paid 100.00/100.00' and pg_temp.history(array[c, aff]) = h,
    'B8 the cancelled one reopened: all of it stays: ' || left(t, 80));
  perform pg_temp.ok((select count(*) from public.therapy_entitlement_invoices where entitlement_id = first_month) = 3
                     and (select status from public.therapy_entitlements where id = first_month) = 'expired'
                     and (select count(*) from public.therapy_entitlements where customer_id = c and earner_kind = 'customer' and status = 'pending_activation') = 2
                     and (select status from public.therapy_entitlements where id = aff_row) = 'pending_activation',
    'B9 still 3 invoices recorded, the used month, 2 months waiting and the affiliate''s reward');
end $b$;

-- ═════ C The rest of the trigger (the 476 suite's figures) ═════
-- At store A (no rule reaches it): cp, a S$100 Credit Package of S$100 credit; cpb, the same with
-- a S$10 Bonus; pbv, a S$140 Premium Bundle of S$100 credit, S$40 Bonus and 2 free vouchers; and a
-- S$300 one-month therapy package.
do $c$
declare
  own uuid := pg_temp.id('own'); mgr uuid := pg_temp.id('mgr'); stf uuid := pg_temp.id('stf'); sa uuid := pg_temp.id('sa');
  cp uuid; cpb uuid; pbv uuid; tp uuid; c uuid; i uuid; it uuid; sale record; e record;
begin
  insert into public.credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
  values ('T502 S$100', 100, 100, false, true, true, false) returning id into cp;
  insert into public.credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
  values ('T502 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into public.credit_package_stores(package_id, store_id) values (cp, sa), (cpb, sa);
  insert into public.premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
  values ('T502 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into public.premium_bundle_stores(bundle_id, store_id) values (pbv, sa);
  insert into public.premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, pg_temp.id('vf'));
  insert into public.unlimited_therapy_packages(name, duration_months, is_active) values ('T502 One Month', 1, true) returning id into tp;
  insert into public.unlimited_therapy_store_prices(package_id, store_id, selling_price, available_at_store) values (tp, sa, 300, true);
  perform pg_temp.put('cp', cp); perform pg_temp.put('cpb', cpb); perform pg_temp.put('pbv', pbv);

  -- Purchased therapy.
  c := pg_temp.cust('c1'); i := pg_temp.inv(stf, sa, c, pg_temp.tpline(tp));
  perform pg_temp.pay(stf, i);
  perform pg_temp.ok((select count(*) = 1 and bool_and(p.status = 'pending_activation' and p.package_id = tp and p.customer_id = c)
                        from public.purchased_therapy_entitlements p where p.invoice_id = i),
    'C1 paying for a therapy package still creates its unit');
  -- A Credit Package with a Bonus.
  c := pg_temp.cust('c2'); i := pg_temp.inv(stf, sa, c, pg_temp.cpline(cpb));
  perform pg_temp.pay(stf, i);
  select * into sale from public.credit_package_sales where invoice_id = i;
  perform pg_temp.ok(pg_temp.credit(c) = 'bonus 10.00 paid 100.00', 'C2 a Credit Package still gives its S$100 credit and S$10 Bonus: ' || pg_temp.credit(c));
  perform pg_temp.ok(sale.reward_units = 0 and pg_temp.reward_rows(sale.id) = 0
                     and (select credit_issued_at is not null from public.invoice_items where invoice_id = i)
                     and (select count(*) from public.invoice_benefit_values where invoice_id = i) = 2,
    'C3 with its sale record, no reward, the line issued and both benefits recorded');
  -- The Premium Bundle, 1 of its 2 vouchers chosen at the till.
  c := pg_temp.cust('c3'); i := pg_temp.inv(stf, sa, c, pg_temp.pbline(pbv, 1));
  perform pg_temp.pay(stf, i);
  perform pg_temp.ok(pg_temp.credit(c) = 'bonus 40.00 paid 100.00', 'C4 a Premium Bundle still gives its S$100 credit and S$40 Bonus: ' || pg_temp.credit(c));
  perform pg_temp.ok((select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = c and source_type = 'premium_bundle' and status = 'held') = 1,
    'C5 and the voucher chosen at the till');
  select count(*) as n, min(voucher_qty) as q, bool_and(status = 'pending_activation' and claim_source_type = 'premium_bundle'
                                                        and claim_source_invoice_id = i and rule_id is null) as shape
    into e from public.therapy_entitlements where customer_id = c and earner_kind = 'premium_bundle';
  perform pg_temp.ok(e.n = 1 and e.q = 1 and e.shape, format('C6 and the other still to choose, on a reward row of its own (earner_kind premium_bundle): %s row(s) of %s', e.n, e.q));
  -- 'cp 40': S$40 of S$100 paid releases S$40 of credit before full payment.
  c := pg_temp.cust('c4'); i := pg_temp.inv(stf, sa, c, pg_temp.cpline(cp));
  perform pg_temp.pay(stf, i, 40);
  select id into it from public.invoice_items where invoice_id = i;
  perform pg_temp.ok(pg_temp.status(i) = 'partially_paid 40.00/100.00' and pg_temp.credit(c) = 'paid 40.00'
                     and public.credit_package_released_paid_credit(it) = 40,
    'C7 S$40 of S$100 paid still releases S$40 of credit: ' || pg_temp.credit(c));
  perform pg_temp.fix_pay(mgr, i, 30);
  perform pg_temp.ok(pg_temp.status(i) = 'partially_paid 30.00/100.00' and pg_temp.credit(c) = 'paid 30.00'
                     and public.credit_package_released_paid_credit(it) = 30,
    'C8 the payment corrected to S$30 still trims it to S$30: ' || pg_temp.credit(c));
  perform pg_temp.ok(exists (select 1 from public.audit_logs where record_id = i and action = 'released_credit_trimmed_to_money'),
    'C9 with its Audit Log entry');
  perform pg_temp.pay(stf, i);
  select * into sale from public.credit_package_sales where invoice_id = i;
  perform pg_temp.ok(pg_temp.status(i) = 'paid 100.00/100.00' and pg_temp.credit(c) = 'paid 100.00' and sale.reward_units = 0,
    'C10 settled, the rest is given: S$100 in all, and no reward: ' || pg_temp.credit(c));
  perform pg_temp.ok(not exists (select 1 from public.therapy_entitlements te join public.customers x on x.id = te.customer_id
                                  where x.full_name like 'T502 c% Buyer' and te.earner_kind in ('customer', 'affiliate')),
    'C11 none of it earned a paid-day reward');
end $c$;

-- ═════ D New Credit Package sales ═════
-- S$2,000 packages at store A: 'new' made in the Credit Package window now (its reward off), and
-- an older one with its reward on (fixture), which would give 2 units of 10 vouchers (S$994 each).
do $d$
declare
  own uuid := pg_temp.id('own'); mgr uuid := pg_temp.id('mgr'); stf uuid := pg_temp.id('stf'); sa uuid := pg_temp.id('sa');
  pkg uuid; old uuid; oldx uuid; c uuid; i uuid; t text; j jsonb; sale record;
  win text := 'select public.upsert_credit_package(%L::uuid, %L, 2000, 2000, true, public.sg_today(), null, %L, p_store_ids => array[%L]::uuid[], p_allow_product => true, p_allow_therapy => true)::text';
begin
  insert into public.credit_packages(name, customer_price, paid_credit_amount, allow_product, allow_therapy)
  values ('T502 Older S$2,000', 2000, 2000, true, true) returning id into old;   -- grants_reward: the column's default, on
  insert into public.credit_package_stores(package_id, store_id) values (old, sa);
  perform pg_temp.put('old2000', old);

  pkg := pg_temp.must(own, format(win, null, 'T502 New S$2,000', 'third_party', sa))::uuid;
  perform pg_temp.put('new2000', pkg);
  perform pg_temp.ok((select grants_reward from public.credit_packages where id = pkg) = false, 'D1 a Credit Package made now starts with its reward off');
  perform pg_temp.must(mgr, format(win, pkg, 'T502 New S$2,000 edited', 'third_party', sa));
  perform pg_temp.ok((select grants_reward from public.credit_packages where id = pkg) = false
                     and (select name from public.credit_packages where id = pkg) = 'T502 New S$2,000 edited',
    'D2 a Manager''s edit keeps it off');
  perform pg_temp.must(own, format(win, old, 'T502 Older S$2,000', 'third_party', sa));
  perform pg_temp.ok((select grants_reward from public.credit_packages where id = old),
    'D3 an edit leaves an older package''s reward as it is (the window then switches it off, below)');

  -- What the till shows before the sale.
  j := pg_temp.must(stf, format('select public.credit_package_benefit_preview(%L::uuid, %L::uuid)::text', pkg, sa))::jsonb;
  perform pg_temp.ok((j->>'grants_reward')::boolean = false and (j->>'reward_voucher_total')::int = 0 and (j->>'paid_credit_total')::numeric = 2000,
    'D4 the till''s preview: S$2,000 credit and no reward vouchers: ' || j::text);
  j := pg_temp.must(stf, format('select public.credit_package_benefit_preview(%L::uuid, %L::uuid)::text', old, sa))::jsonb;
  perform pg_temp.ok((j->>'reward_voucher_total')::int = 20, 'D5 control: the older package''s preview shows 20: ' || j::text);

  -- Sold and paid: credit only.
  c := pg_temp.cust('d1'); i := pg_temp.inv(stf, sa, c, pg_temp.cpline(pkg));
  perform pg_temp.pay(stf, i);
  select * into sale from public.credit_package_sales where invoice_id = i;
  perform pg_temp.ok(pg_temp.status(i) = 'paid 2000.00/2000.00' and pg_temp.credit(c) = 'paid 2000.00',
    'D6 sold and paid in full, it gives its S$2,000 credit: ' || pg_temp.credit(c));
  perform pg_temp.ok(sale.reward_units = 0 and pg_temp.reward_rows(sale.id) = 0
                     and not exists (select 1 from public.therapy_entitlements where customer_id = c),
    format('D7 and nothing else: reward units %s, no reward row', sale.reward_units));

  -- The split panel.
  c := pg_temp.cust('d2'); perform pg_temp.cust('d3');
  t := pg_temp.try_as(stf, format('select public.create_split_credit_package_invoices(%L::uuid, %L::uuid, %L::jsonb)::text', sa, pkg,
    jsonb_build_array(jsonb_build_object('customer_id', pg_temp.id('d2'), 'payment_amount', 1000, 'reward_voucher_qty', 10),
                      jsonb_build_object('customer_id', pg_temp.id('d3'), 'payment_amount', 1000, 'reward_voucher_qty', 10))));
  perform pg_temp.ok(t = 'P0001:This package grants no reward vouchers, so every allocation must be 0', 'D8 a split cannot share out reward vouchers: ' || t);
  j := pg_temp.must(stf, format('select public.create_split_credit_package_invoices(%L::uuid, %L::uuid, %L::jsonb)::text', sa, pkg,
    jsonb_build_array(jsonb_build_object('customer_id', pg_temp.id('d2'), 'payment_amount', 1000, 'reward_voucher_qty', 0),
                      jsonb_build_object('customer_id', pg_temp.id('d3'), 'payment_amount', 1000, 'reward_voucher_qty', 0))))::jsonb;
  perform pg_temp.pay(stf, (j->'invoices'->0->>'invoice_id')::uuid);
  perform pg_temp.pay(stf, (j->'invoices'->1->>'invoice_id')::uuid);
  perform pg_temp.ok((j->>'reward_voucher_total')::int = 0 and pg_temp.credit(pg_temp.id('d2')) = 'paid 1000.00' and pg_temp.credit(pg_temp.id('d3')) = 'paid 1000.00'
                     and not exists (select 1 from public.therapy_entitlements where customer_id in (pg_temp.id('d2'), pg_temp.id('d3')))
                     and (select sum(reward_units) from public.credit_package_sales where customer_id in (pg_temp.id('d2'), pg_temp.id('d3'))) = 0,
    'D9 with none it is made, and each paid half gives S$1,000 credit and no reward');
  t := pg_temp.try_as(stf, format('select public.create_split_credit_package_invoices(%L::uuid, %L::uuid, %L::jsonb)::text', sa, old,
    jsonb_build_array(jsonb_build_object('customer_id', pg_temp.id('d2'), 'payment_amount', 1000, 'reward_voucher_qty', 0),
                      jsonb_build_object('customer_id', pg_temp.id('d3'), 'payment_amount', 1000, 'reward_voucher_qty', 0))));
  perform pg_temp.ok(t = 'P0001:Reward vouchers allocated (0) must equal the package total (20)', 'D10 control: the older package''s split must share out 20: ' || t);

  -- The Reopen dialog: S$500 paid, cancelled; what reopening and settling would give.
  c := pg_temp.cust('d4'); i := pg_temp.inv(stf, sa, c, pg_temp.cpline(pkg));
  perform pg_temp.pay(stf, i, 500);
  t := pg_temp.cancel(own, i);
  j := pg_temp.must(own, format('select public.invoice_reopen_preview(%L::uuid)::text', i))::jsonb;
  perform pg_temp.ok(t like 'ok:%' and (j->>'can_reopen')::boolean and (j->>'reward_units_given_on_reopen')::int = 0 and (j->>'reward_units_from_settling_payment')::int = 0,
    format('D11 the Reopen dialog''s preview counts no reward units: %s on reopening, %s from the settling payment',
           j->>'reward_units_given_on_reopen', j->>'reward_units_from_settling_payment'));
  c := pg_temp.cust('d5'); i := pg_temp.inv(stf, sa, c, pg_temp.cpline(old));
  perform pg_temp.pay(stf, i, 500);
  t := pg_temp.cancel(own, i);
  j := pg_temp.must(own, format('select public.invoice_reopen_preview(%L::uuid)::text', i))::jsonb;
  perform pg_temp.ok((j->>'reward_units_from_settling_payment')::int = 2, 'D12 control: the older package''s counts 2: ' || coalesce(j->>'reward_units_from_settling_payment', 'none'));

  -- The reward setting.
  t := pg_temp.try_as(own, format('select public.set_catalogue_reward(%L, %L::uuid, true)::text', 'credit_package', pkg));
  perform pg_temp.ok(t = 'P0001:A Credit Package no longer grants reward vouchers; it gives credit only.'
                     and (select grants_reward from public.credit_packages where id = pkg) = false,
    'D13 an Owner cannot switch a Credit Package''s reward on, and it stays off: ' || t);
  insert into public.credit_packages(name, customer_price, paid_credit_amount, allow_product)
  values ('T502 Older S$3,000', 3000, 3000, true) returning id into oldx;
  t := pg_temp.try_as(mgr, format('select public.set_catalogue_reward(%L, %L::uuid, false)::text', 'credit_package', oldx));
  perform pg_temp.ok(t like 'ok:%' and (select grants_reward from public.credit_packages where id = oldx) = false,
    'D14 a Manager switches an older package''s reward off (what the window does after every save): ' || t);
  t := pg_temp.try_as(mgr, format('select public.set_catalogue_reward(%L, %L::uuid, true)::text', 'credit_package', oldx));
  perform pg_temp.ok(t = 'P0001:A Credit Package no longer grants reward vouchers; it gives credit only.'
                     and (select grants_reward from public.credit_packages where id = oldx) = false,
    'D15 and cannot switch it back on: ' || t);
  t := pg_temp.try_as(stf, format('select public.set_catalogue_reward(%L, %L::uuid, false)::text', 'credit_package', pkg));
  perform pg_temp.ok(t = 'P0001:Only an Owner or Manager can change the reward setting', 'D16 staff cannot change it, as before: ' || t);
  t := pg_temp.try_as(own, format('select public.set_catalogue_reward(%L, %L::uuid, false)::text', 'premium_bundle', pg_temp.id('pbv')));
  perform pg_temp.ok(t like 'ok:%' and (select grants_reward from public.premium_bundles where id = pg_temp.id('pbv')) = false,
    'D17 a Premium Bundle''s reward still switches off: ' || t);
  t := pg_temp.try_as(own, format('select public.set_catalogue_reward(%L, %L::uuid, true)::text', 'premium_bundle', pg_temp.id('pbv')));
  perform pg_temp.ok(t like 'ok:%' and (select grants_reward from public.premium_bundles where id = pg_temp.id('pbv')),
    'D18 and on: ' || t);
end $d$;

-- ═════ E Older Credit Package units ═════
-- Packages sold while their reward was on (fixture: grants_reward true, the column's default),
-- at store A, with 2 reward vouchers to choose from: S$2,000 gives 2 units of 10 vouchers, S$1,000
-- one (S$994 each, no rule reaching store A).
do $e$
declare
  own uuid := pg_temp.id('own'); mgr uuid := pg_temp.id('mgr'); stf uuid := pg_temp.id('stf'); stfb uuid := pg_temp.id('stfb');
  sa uuid := pg_temp.id('sa'); old uuid := pg_temp.id('old2000'); old1 uuid;
  c uuid; i uuid; i2 uuid; i3 uuid; sale record; u1 uuid; u2 uuid; no1 text; no2 text; t text; j jsonb; e record; u3 uuid;
  p13 text := 'This Credit Package came with reward vouchers that are still outstanding. Review them and record what should happen to them, then refund or cancel. Vouchers not handed over yet are withdrawn; those already handed over stay with the customer.';
begin
  insert into public.credit_package_vouchers(package_id, voucher_id) values (old, pg_temp.id('vf')), (old, pg_temp.id('vm'));
  insert into public.credit_packages(name, customer_price, paid_credit_amount, allow_product)
  values ('T502 Older S$1,000', 1000, 1000, true) returning id into old1;
  insert into public.credit_package_stores(package_id, store_id) values (old1, sa);
  insert into public.credit_package_vouchers(package_id, voucher_id) values (old1, pg_temp.id('vf')), (old1, pg_temp.id('vm'));

  -- Sold and paid: its units are issued.
  c := pg_temp.cust('e1'); i := pg_temp.inv(stf, sa, c, pg_temp.cpline(old));
  perform pg_temp.pay(stf, i);
  select * into sale from public.credit_package_sales where invoice_id = i;
  select count(*) as n, sum(voucher_qty) as q,
         bool_and(earner_kind = 'credit_package' and entitlement_kind = 'voucher' and status = 'pending_activation' and rule_id is null
                  and claim_source_type = 'credit_package' and claim_source_invoice_id = i and qualifying_amount = 994
                  and activation_deadline = public.sg_today() + 365
                  and eligible_voucher_ids @> array[pg_temp.id('vf'), pg_temp.id('vm')] and cardinality(eligible_voucher_ids) = 2) as shape
    into e from public.therapy_entitlements where qualification_group_id = public.credit_package_reward_group(sale.id);
  perform pg_temp.ok(sale.reward_units = 2 and e.n = 2 and e.q = 20 and e.shape and pg_temp.credit(c) = 'paid 2000.00',
    format('E1 an older package still gives its credit and its units: %s units, %s rows, %s vouchers', sale.reward_units, e.n, e.q));
  select id, entitlement_no into u1, no1 from public.therapy_entitlements where qualification_group_id = public.credit_package_reward_group(sale.id) order by entitlement_no limit 1;
  select id, entitlement_no into u2, no2 from public.therapy_entitlements where qualification_group_id = public.credit_package_reward_group(sale.id) order by entitlement_no offset 1 limit 1;

  -- Vouchers to hand over lists them, under the list's new name and its old one; for staff of
  -- the store only.
  t := pg_temp.try_as(stf, format('select public.therapy_list_page(%L, %L)::text', 'vouchers', pg_temp.name_of(c)));
  j := case when t like 'ok:%' then substr(t, 4)::jsonb end;
  perform pg_temp.ok(j->>'status' = 'open' and (j->>'total')::int = 2
                     and (select bool_and(r->>'earner_kind' = 'credit_package' and (r->>'remaining')::int = 10) from jsonb_array_elements(j->'rows') r),
    'E2 staff of the store see both on Vouchers to hand over, 10 left on each: ' || left(t, 120));
  t := pg_temp.try_as(stf, format('select public.therapy_list_page(%L, %L)::text', 'legacy', pg_temp.name_of(c)));
  perform pg_temp.ok(t like 'ok:%' and (substr(t, 4)::jsonb->>'total')::int = 2, 'E3 and under the list''s old name: ' || left(t, 120));
  t := pg_temp.try_as(stfb, format('select public.therapy_list_page(%L, %L)::text', 'vouchers', pg_temp.name_of(c)));
  perform pg_temp.ok(t like 'ok:%' and (substr(t, 4)::jsonb->>'total')::int = 0, 'E4 staff of another store do not: ' || left(t, 120));

  -- The hand-over window.
  j := pg_temp.must(stf, format('select public.entitlement_voucher_state(%L::uuid)::text', u1))::jsonb;
  perform pg_temp.ok((j->>'entitled')::int = 10 and (j->>'claimed')::int = 0 and (j->>'remaining')::int = 10 and j->>'blocked_reason' is null
                     and (j->>'deadline_passed')::boolean = false and jsonb_array_length(j->'eligible') = 2
                     and (select bool_and((v->>'still_offered')::boolean) from jsonb_array_elements(j->'eligible') v),
    'E5 a member of staff of the store sees it in the hand-over window: 10 to hand over, 2 vouchers to choose from');
  t := pg_temp.try_as(stfb, format('select public.entitlement_voucher_state(%L::uuid)::text', u1));
  perform pg_temp.ok(t = 'P0001:No access to this store', 'E6 staff of another store do not: ' || t);
  j := pg_temp.must(stf, format('select public.claim_entitlement_vouchers(%L::uuid, %L::jsonb, %L)::text', u1,
    jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.id('vf'), 'quantity', 2), jsonb_build_object('voucher_id', pg_temp.id('vm'), 'quantity', 1)),
    'T502 hand-over'))::jsonb;
  perform pg_temp.ok((j->>'claimed_now')::int = 3 and (j->'state'->>'remaining')::int = 7
                     and (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where entitlement_id = u1 and status = 'held') = 3
                     and (select status = 'pending_activation' and claimed_at is not null from public.therapy_entitlements where id = u1),
    'E7 and hands over 3 (2 Facials and a Massage): 7 left');

  -- Its own collect-by date: a reward whose date has passed hands nothing over; on the date, it does.
  c := pg_temp.cust('e2'); i2 := pg_temp.inv(stf, sa, c, pg_temp.cpline(old1));
  perform pg_temp.pay(stf, i2);
  select id into u3 from public.therapy_entitlements where customer_id = c and earner_kind = 'credit_package';
  update public.therapy_entitlements set activation_deadline = public.sg_today() - 1 where id = u3;
  t := pg_temp.try_as(stf, format('select public.claim_entitlement_vouchers(%L::uuid, %L::jsonb, null)::text', u3,
    jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.id('vf'), 'quantity', 1))));
  perform pg_temp.ok(t = format('P0001:The claim deadline (%s) has passed', public.sg_today() - 1)
                     and public.entitlement_claimed_qty(u3) = 0, 'E8 a hand-over after the reward''s own collect-by date is refused: ' || t);
  update public.therapy_entitlements set activation_deadline = public.sg_today() where id = u3;
  t := pg_temp.try_as(stf, format('select public.claim_entitlement_vouchers(%L::uuid, %L::jsonb, null)::text', u3,
    jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.id('vf'), 'quantity', 1))));
  perform pg_temp.ok(t like 'ok:%' and public.entitlement_claimed_qty(u3) = 1, 'E9 on the date itself it goes through: ' || left(t, 60));

  -- The refund and cancel review.
  t := pg_temp.refund(own, i);
  perform pg_temp.ok(t = 'P0001:' || p13, 'E10 refunding the package is refused in the new words: ' || t);
  perform pg_temp.ok(t like '%reward vouchers that are still outstanding%', 'E11 (the words the Invoices page opens the reward review on)');
  t := pg_temp.cancel(own, i);
  perform pg_temp.ok(t = 'P0001:' || p13 and pg_temp.status(i) = 'paid 2000.00/2000.00', 'E12 so is cancelling it, and it stays paid: ' || t);
  perform pg_temp.ok((select string_agg(r.entitlement_no || ' ' || r.disposition, ', ' order by r.entitlement_no)
                        from jsonb_to_recordset(pg_temp.must(own, format('select jsonb_agg(x)::text from public.invoice_credit_reward_entitlements(%L::uuid) x', i))::jsonb)
                             as r(entitlement_no text, disposition text))
                     = no1 || ' consumed, ' || no2 || ' withdrawable',
    'E13 the review lists the one partly handed over as kept and the other as to withdraw');
  j := pg_temp.must(own, format('select public.invoice_action_plan(%L::uuid, %L, %L::jsonb)::text', i, 'refund_full', '[]'))::jsonb;
  perform pg_temp.ok(j->'effects'->'rewards' = jsonb_build_object('withdrawn', jsonb_build_array(no2), 'kept', jsonb_build_array(no1)),
    'E14 the guided refund''s plan lists them under rewards: ' || coalesce((j->'effects'->'rewards')::text, 'none'));
  t := pg_temp.try_as(stf, format('select public.resolve_invoice_credit_rewards(%L::uuid, %L)::text', i, 'T502 returned'));
  perform pg_temp.ok(t = '42501:Only an Owner or Manager can settle reward vouchers', 'E15 staff cannot settle them, in the new words: ' || t);
  t := pg_temp.try_as(own, format('select public.resolve_invoice_credit_rewards(%L::uuid, %L)::text', i, 'T502 returned'));
  perform pg_temp.ok(t = 'P0001:This purchase has 1 reward entitlement(s) the customer has already activated or claimed. Confirm that their history stays before resolving.',
    'E16 an Owner is asked to confirm that the ones handed over stay, as before: ' || t);
  j := pg_temp.must(own, format('select public.resolve_invoice_credit_rewards(%L::uuid, %L, null, true)::text', i, 'T502 returned'))::jsonb;
  perform pg_temp.ok((j->>'withdrawn')::int = 1 and (j->>'retained')::int = 1
                     and (select status from public.therapy_entitlements where id = u2) = 'cancelled'
                     and (select status from public.therapy_entitlements where id = u1) = 'pending_activation'
                     and (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where entitlement_id = u1 and status = 'held') = 3
                     and (select rewards_resolved_at is not null from public.credit_package_sales where id = sale.id),
    'E17 confirmed: the one not handed over is withdrawn, the one partly handed over stays with its 3 vouchers: ' || j::text);
  t := pg_temp.refund(own, i);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.status(i) = 'refunded 0.00/2000.00' and pg_temp.credit(pg_temp.id('e1')) = 'none',
    'E18 then the refund goes through, and the credit goes back: ' || left(t, 80));
  -- The refund withdraws the 7 not handed over (as it always has: trg_revoke_unclaimed_on_close).
  j := pg_temp.must(stf, format('select public.entitlement_voucher_state(%L::uuid)::text', u1))::jsonb;
  t := pg_temp.try_as(stf, format('select public.claim_entitlement_vouchers(%L::uuid, %L::jsonb, null)::text', u1,
    jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.id('vf'), 'quantity', 1))));
  perform pg_temp.ok(t like 'P0001:%' and (j->>'claimed')::int = 3 and (j->>'revoked')::int = 7 and (j->>'remaining')::int = 0
                     and j->>'blocked_reason' = format('Invoice %s was refunded', (select invoice_no from public.invoices where id = i))
                     and (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where entitlement_id = u1 and status = 'held') = 3,
    'E19 after the refund the 7 not handed over are withdrawn and nothing more is handed over; the 3 handed over stay with the customer: ' || t);

  -- The review of an older sale with no benefit values recorded (as a sale from before they were;
  -- fixture, as original-credit-sources.sql makes one).
  c := pg_temp.cust('e3'); i3 := pg_temp.inv(stf, sa, c, pg_temp.cpline(old1));
  perform pg_temp.pay(stf, i3);
  delete from public.invoice_benefit_values where invoice_id = i3;
  j := pg_temp.must(own, format('select public.invoice_benefit_review_options(%L::uuid)::text', i3))::jsonb;
  perform pg_temp.ok(j->'lines'->0->>'blocked_reason' = 'This Credit Package came with reward vouchers. Review their original hand-over records first; credit-only allocations cannot complete this purchase.',
    'E20 the benefit review of an older sale shows the new words: ' || coalesce(j->'lines'->0->>'blocked_reason', j::text));
end $e$;

-- ═════ Result ═════
do $res$
declare f int; n int;
begin
  select count(*) filter (where not ok), count(*) into f, n from t502_res;
  if f > 0 then raise exception '% of % checks failed: %', f, n, (select string_agg(label, ' | ' order by t502_res.n) from t502_res where not ok); end if;
  raise warning 'PASS all % checks', n;
end $res$;
rollback;
