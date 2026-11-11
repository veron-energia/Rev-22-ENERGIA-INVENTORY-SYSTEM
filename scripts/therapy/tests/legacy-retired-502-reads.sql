-- 502: Legacy Therapy and Qualification retired (the user, 10 Nov 2026). Part 2 of its suite:
-- what the pages read, deleting a customer, the rights, "Re-check paid days", the bundle
-- threshold, the nightly job, the UNDO, and the check that every reward writer names what
-- earned its reward. Part 1, scripts/therapy/tests/legacy-retired-502.sql, covers earning
-- stopping on every money path, the history kept, the rest of the paid-invoice trigger and
-- Credit Packages; the go-live scripts have scripts/therapy/tests/legacy-retired-golive-502.sql.
-- supabase/502_legacy_therapy_retired.sql and scripts/therapy/undo-502.sql.
--
-- Every step goes through the app's own calls, as the person named, with that person's rights:
-- the Therapy page's lists (therapy_list_page), its holdings card (therapy_customer_summary,
-- therapy_customer_detail), the Customers page (customer_overview, delete_customer), Reports
-- (report_therapy), the Dashboard (dashboard_alerts_summary), the hand-over window
-- (entitlement_voucher_state, claim_entitlement_vouchers), the invoice form, Pay and Refund
-- (create_invoice_with_details, record_invoice_settlement, refund_invoice_recorded) and the
-- Premium Bundle form (upsert_premium_bundle). What only the server runs is run as the database
-- owner: the nightly job (run_therapy_status_refresh), the withdrawal on a closed sale
-- (revoke_unclaimed_entitlement_vouchers), the go-live scripts' upsert_legacy_rule, and the two
-- retired functions called directly (backfill_legacy_qualification, assert_legacy_refund_allowed).
--
--   F. Vouchers to hand over: 'vouchers' reads as 'legacy' does; no status ever lists a Legacy
--      reward; search, paging and an unknown list; the Purchased list the same before and after.
--   G. Deleting a customer (the user, 10 Nov 2026): only vouchers still owed stop it.
--   H. The Customers page: vouchers_to_hand_over replaces legacy_therapy.
--   J. Reports → Therapy: no Legacy rows; the rest as before, in the stores each login sees.
--   K. The Dashboard's alert: a Legacy reward no longer holds a refunded sale; a Credit Package
--      reward still does.
--   L. The holdings card: Legacy rows left out; vouchers already handed over still count, as
--      "Earlier reward".
--   M. The refund guard is gone: the day of a used free month can be refunded; the month stays.
--   N. Rights: the 13 functions only Legacy used are closed to signed-in logins; the rest are
--      kept; every writer of a reward names what earned it.
--   O. "Re-check paid days" refuses and writes nothing.
--   P. Premium Bundles: a blank threshold falls back to S$994 once the rules are off.
--   Q. The nightly job as before; no Legacy row changes.
--   U. The UNDO (scripts/therapy/undo-502.sql), and 502 again after it.
--
-- Run from the repository's root, on a copy of production at 501 (502 is installed first, inside
-- this transaction), or with -v skip_install=1 where 502 is in:
--   psql -X -v ON_ERROR_STOP=1 -d <copy> -f scripts/therapy/tests/legacy-retired-502-reads.sql
-- Disposable database only; everything is rolled back. Every name, number and code is invented
-- (502R ..., @example.invalid); the phones are fictional (+61 2 5550 2nnn).
\set ON_ERROR_STOP on
\set t502r_mig `cat supabase/502_legacy_therapy_retired.sql`
\set t502r_undo `cat scripts/therapy/undo-502.sql`
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';
-- Definitions are read with public alone on the search path, as 502 reads them.
select set_config('t502r.mig', :'t502r_mig', true), set_config('t502r.undo', :'t502r_undo', true),
       set_config('search_path', 'public', true) \g /dev/null
set local client_min_messages = warning;

create temp table t502r(k text primary key, id uuid);
create temp table t502r_txt(k text primary key, v text);
create temp table t502r_res(n serial primary key, ok boolean, label text);
-- The reward rows made here: Legacy or not, their store, and the status the lists read from them.
create temp table t502r_row(k text primary key, id uuid, legacy boolean, store text, status_now text);
create temp sequence t502r_phone;
create function pg_temp.id(p_k text) returns uuid language sql as $f$ select id from t502r where k = p_k $f$;
create function pg_temp.put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t502r values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.txt(p_k text) returns text language sql as $f$ select v from t502r_txt where k = p_k $f$;
create function pg_temp.put_txt(p_k text, p_v text) returns text language sql as $f$
  insert into t502r_txt values (p_k, p_v) on conflict (k) do update set v = excluded.v returning v $f$;
create function pg_temp.ok(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  insert into t502r_res(ok, label) values (coalesce(p_ok, false), p_label);
  if not coalesce(p_ok, false) then raise warning 'FAIL %', p_label; end if;
end $f$;
-- Runs p_sql as this person, with their rights: 'ok:<answer>', or '<sqlstate>:<words>' when
-- refused. p_as: 'login' (signed in, the role authenticated), 'server' (the database owner: a
-- script or the SQL editor, recording as p_who when one is given), 'service' (the service role)
-- or 'anon' (signed out).
create function pg_temp.try_as(p_who uuid, p_sql text, p_as text default 'login') returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    perform set_config('request.jwt.claims', '', true);
    if p_as = 'login' then
      perform set_config('request.jwt.claims', json_build_object('sub', p_who, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    elsif p_as = 'service' then
      perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
      execute 'set local role service_role';
    elsif p_as = 'anon' then
      perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
      execute 'set local role anon';
    elsif p_as = 'server' then
      if p_who is not null then perform set_config('request.jwt.claim.sub', p_who::text, true); end if;
    else
      raise exception 'try_as: no such caller %', p_as;
    end if;
    execute p_sql into v;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    return s || ':' || m;
  end;
end $f$;
-- The answer of a call that must be accepted; a refusal stops the suite.
create function pg_temp.call(p_who uuid, p_sql text, p_as text default 'login') returns text language plpgsql as $f$
declare t text := pg_temp.try_as(p_who, p_sql, p_as);
begin
  if t not like 'ok:%' then raise exception '502R: refused (%): %', left(p_sql, 160), t; end if;
  return substr(t, 4);
end $f$;
-- One page of a Therapy list, as this login.
create function pg_temp.list(p_who uuid, p_tab text, p_search text default null, p_status text default null,
                             p_limit int default 200, p_offset int default 0) returns jsonb language sql as $f$
  select pg_temp.call(p_who, format('select public.therapy_list_page(%L, %L, %L, %s, %s)::text',
                                    p_tab, p_search, p_status, p_limit, p_offset))::jsonb $f$;
-- The ids on a list page, sorted.
create function pg_temp.ids(p_page jsonb) returns uuid[] language sql as $f$
  select coalesce(array_agg((r->>'id')::uuid order by (r->>'id')::uuid), '{}')
    from jsonb_array_elements(coalesce(p_page->'rows', '[]'::jsonb)) r $f$;
-- The rows made here with these keys, as sorted ids.
create function pg_temp.keys(p_keys text[]) returns uuid[] language sql as $f$
  select coalesce(array_agg(id order by id), '{}') from t502r where k = any(p_keys) $f$;
create function pg_temp.fp() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(oid)), '' order by oid::regprocedure::text)) || '/' || count(*)
    from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f' $f$;
create function pg_temp.md5_of(p_sig text) returns text language sql as $f$
  select md5(pg_get_functiondef(to_regprocedure('public.' || p_sig))) $f$;
-- Rights compared as sets.
create function pg_temp.acl_of(p_sig text) returns text language sql as $f$
  select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
   where p.oid = to_regprocedure('public.' || p_sig) $f$;
-- The triggers on invoices: name, whether on, definition; in name order, the order a BEFORE
-- UPDATE trigger runs in.
create function pg_temp.triggers() returns text language sql as $f$
  select coalesce(string_agg(t.tgname || ' ' || t.tgenabled::text || ' ' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname), '')
    from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and not t.tgisinternal $f$;
-- What 502 and its UNDO may change: every function, every right, every comment, the triggers.
create function pg_temp.state() returns text language sql as $f$
  select md5(concat_ws(E'\n', pg_temp.fp(),
    (select string_agg(p.oid::regprocedure::text || '=' || coalesce((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x), '<none>'),
                       E'\n' order by p.oid::regprocedure::text)
       from pg_proc p where p.pronamespace = 'public'::regnamespace),
    (select coalesce(string_agg(p.oid::regprocedure::text || '=' || obj_description(p.oid, 'pg_proc'), E'\n' order by p.oid::regprocedure::text), '')
       from pg_proc p where p.pronamespace = 'public'::regnamespace and obj_description(p.oid, 'pg_proc') is not null),
    pg_temp.triggers())) $f$;
-- The Legacy rewards made here as they stand: status, quantities, dates, invoice links, and the
-- vouchers held from them.
create function pg_temp.legacy_rows() returns text language sql as $f$
  select md5(coalesce((select string_agg(concat_ws('|', e.id, e.status, e.voucher_qty, e.revoked_qty, e.revoked_reason, e.activation_date,
                                                   e.expiry_date, e.activation_deadline, e.claimed_at, e.customer_id), ',' order by e.id)
                         from public.therapy_entitlements e join t502r_row r on r.id = e.id where r.legacy), '')
         || coalesce((select string_agg(concat_ws('|', t.entitlement_id, t.invoice_id), ',' order by t.entitlement_id, t.invoice_id)
                        from public.therapy_entitlement_invoices t join t502r_row r on r.id = t.entitlement_id), '')
         || coalesce((select string_agg(concat_ws('|', v.id, v.status, v.quantity), ',' order by v.id)
                        from public.customer_reward_vouchers v join t502r_row r on r.id = v.entitlement_id where r.legacy), '')) $f$;

-- The 15 functions 502 patches, as before and after it.
create temp table t502r_fn(i int primary key, sig text, before_md5 text, after_md5 text);
insert into t502r_fn values
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
-- The 13 functions only Legacy used, which signed-in logins can no longer call.
create temp table t502r_revoked(sig text primary key);
insert into t502r_revoked values
  ('affiliate_legacy_day_summary(date)'), ('backfill_legacy_qualification(date,date,uuid)'),
  ('claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)'), ('invoice_legacy_entitlements(uuid)'),
  ('invoice_therapy_summary(uuid)'), ('legacy_qualification_diagnose(uuid,uuid,date)'),
  ('legacy_qualification_group(uuid,uuid,date)'), ('legacy_reward_options(uuid)'),
  ('legacy_reward_options_diagnostic(uuid)'), ('legacy_setup_status()'),
  ('therapy_map_entitlement_tier(uuid,text,text)'), ('therapy_reward_mapping_preview()'),
  ('upsert_legacy_rule(uuid,uuid,text,numeric,text,integer,integer,integer,boolean,date,text)');
-- The 4 retired recounts, commented by 502.
create temp table t502r_retired(sig text primary key);
insert into t502r_retired values
  ('recompute_legacy_qualification(uuid,uuid,date)'), ('recompute_affiliate_legacy_qualification(uuid,date)'),
  ('recompute_affiliates_for_customer_day(uuid,date)'), ('recompute_legacy_qualification_for_invoice(uuid)');
select pg_temp.put_txt('c_note', 'Retired by 502 (10 Nov 2026). Do not run: it drops therapy_entitlement_invoices history.'),
       pg_temp.put_txt('c_reason', 'Legacy Therapy retired (decision of 10 Nov 2026)'),
       pg_temp.put_txt('c_guard', 'CREATE TRIGGER legacy_refund_guard BEFORE UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_legacy_refund_guard()'),
       pg_temp.put_txt('c_owed1', 'This customer still has 1 reward(s) with vouchers to hand over (Therapy → Vouchers to hand over). Hand them over, or refund or cancel the sale they came from, first.'),
       pg_temp.put_txt('c_owed2', 'This customer still has 2 reward(s) with vouchers to hand over (Therapy → Vouchers to hand over). Hand them over, or refund or cancel the sale they came from, first.'),
       pg_temp.put_txt('c_guard_says', 'This invoice cannot be refunded: the customer''s Legacy therapy from that day has already been activated. Cancel or complete the therapy first.') \g /dev/null

-- ═════ Fixture helpers (invented records) ═════
create function pg_temp.store(p_k text) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.stores (name, code, country_code)
  values ('502R Store ' || upper(p_k) || ' ' || pg_temp.txt('sfx'), '502R' || upper(p_k) || pg_temp.txt('sfx'), 'SG') returning id into v;
  return pg_temp.put(p_k, v);
end $f$;
create function pg_temp.person(p_k text, p_role text, p_stores text[] default '{}') returns uuid language plpgsql as $f$
declare v uuid; s text;
begin
  insert into auth.users (id, email) values (gen_random_uuid(), '502r-' || p_k || '-' || pg_temp.txt('sfx') || '@example.invalid') returning id into v;
  insert into public.profiles (id, full_name, email, role, is_active)
  values (v, '502R ' || p_k, '502r-' || p_k || '-' || pg_temp.txt('sfx') || '@example.invalid', p_role::public.user_role, true);
  foreach s in array p_stores loop
    insert into public.user_store_assignments (user_id, store_id) values (v, pg_temp.id(s));
  end loop;
  return pg_temp.put(p_k, v);
end $f$;
create function pg_temp.cust(p_k text, p_name text) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.customers (full_name, phone)
  values (p_name || ' ' || pg_temp.txt('sfx'), '+61 2 5550 2' || lpad(nextval('t502r_phone')::text, 3, '0')) returning id into v;
  return pg_temp.put(p_k, v);
end $f$;
create function pg_temp.cname(p_k text) returns text language sql as $f$ select full_name from public.customers where id = pg_temp.id(p_k) $f$;
-- A sale as it stands, written directly (it fires no payment trigger), with an invented number.
create function pg_temp.inv(p_k text, p_store text, p_cust text, p_status text, p_total numeric default 1000,
                            p_deleted boolean default false) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount, paid_at, deleted_at)
  values ('502R-' || pg_temp.txt('sfx') || '-' || upper(p_k), pg_temp.id(p_store), pg_temp.id(p_cust), pg_temp.id('own'),
          p_status::public.invoice_status, p_total, p_total, case when p_status = 'paid' then p_total else 0 end,
          case when p_status in ('paid', 'refunded', 'cancelled') then now() end, case when p_deleted then now() end)
  returning id into v;
  return pg_temp.put(p_k, v);
end $f$;
create function pg_temp.inv_no(p_k text) returns text language sql as $f$ select invoice_no from public.invoices where id = pg_temp.id(p_k) $f$;
-- A reward row as it stands. p_earner 'customer' or 'affiliate' is Legacy (earned by a paid day,
-- with its rule); 'credit_package', 'premium_bundle' and 'therapy_package' are vouchers owed
-- from a sale (p_sale), with a voucher list.
create function pg_temp.ent(p_k text, p_cust text, p_store text, p_earner text, p_kind text, p_status text,
                            p_qty int default 10, p_deadline date default null, p_sale text default null,
                            p_act date default null, p_exp date default null, p_created timestamptz default null,
                            p_revoked int default 0, p_group uuid default null) returns uuid language plpgsql as $f$
declare v uuid; v_legacy boolean := p_earner in ('customer', 'affiliate');
begin
  insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
      duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status, earner_kind,
      claim_source_type, claim_source_invoice_id, eligible_voucher_ids, activation_date, expiry_date, created_at,
      revoked_qty, revoked_at, revoked_reason, qualification_group_id, created_by)
  values ('502R-' || pg_temp.txt('sfx') || '-' || upper(p_k), pg_temp.id(p_cust), pg_temp.id(p_store),
          case when v_legacy then pg_temp.id('rule') end,
          case p_earner when 'customer' then '502R Legacy Month' when 'affiliate' then '502R Affiliate Reward'
                        when 'credit_package' then '502R Credit Package Reward' when 'premium_bundle' then '502R Bundle Reward'
                        else '502R Therapy Package Vouchers' end,
          p_kind, case when p_kind = 'unlimited' then 1 end, case when p_kind = 'voucher' then p_qty end,
          994, 994, coalesce(p_deadline, public.sg_today() + 300), p_status, p_earner,
          case when not v_legacy then p_earner end, pg_temp.id(p_sale),
          case when not v_legacy and p_kind = 'voucher' then array[pg_temp.id('v1'), pg_temp.id('v2')] end,
          p_act, p_exp, coalesce(p_created, now()), p_revoked, case when p_revoked > 0 then now() end,
          case when p_revoked > 0 then '502R check: withdrawn' end, p_group, pg_temp.id('own'))
  returning id into v;
  insert into t502r_row values (p_k, v, v_legacy, p_store, p_status);
  return pg_temp.put(p_k, v);
end $f$;
-- Vouchers handed over from a reward: a hand-over recorded by the hand-over window.
create function pg_temp.handed(p_ent text, p_qty int) returns void language sql as $f$
  insert into public.voucher_claims (entitlement_id, customer_id, store_id, quantity, selections, claimed_by)
  select e.id, e.customer_id, e.store_id, p_qty, jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.id('v1'), 'quantity', p_qty)), pg_temp.id('own')
    from public.therapy_entitlements e where e.id = pg_temp.id(p_ent) $f$;
-- Vouchers a customer holds from a reward, as the 50 handed over in August were written (no
-- source type), or with one.
create function pg_temp.held(p_ent text, p_qty int, p_status text default 'held', p_source text default null) returns uuid language sql as $f$
  insert into public.customer_reward_vouchers (customer_id, voucher_id, entitlement_id, store_id, quantity, status, source_type, issued_by)
  select e.customer_id, pg_temp.id('v1'), e.id, e.store_id, p_qty, p_status, p_source, pg_temp.id('own')
    from public.therapy_entitlements e where e.id = pg_temp.id(p_ent) returning id $f$;
-- A purchased unlimited-therapy unit (each on its own customer and sale).
create function pg_temp.unit(p_k text, p_cust text, p_store text, p_sale text, p_status text, p_deadline date,
                             p_act date default null, p_exp date default null, p_voucher_ent text default null) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.purchased_therapy_entitlements (entitlement_no, customer_id, store_id, package_id, invoice_id,
      package_name, duration_months, price_snapshot, purchase_date, activation_deadline, scheduled_date, activation_date,
      expiry_date, status, benefit_choice, offered_choices, voucher_qty_snapshot, voucher_entitlement_id, choice_deadline)
  values ('502R-' || pg_temp.txt('sfx') || '-' || upper(p_k), pg_temp.id(p_cust), pg_temp.id(p_store), pg_temp.id('utp'),
          pg_temp.id(p_sale), '502R Six Months', 6, 1000, public.sg_today() - 30, p_deadline,
          case when p_status = 'scheduled' then p_act end, p_act, p_exp, p_status,
          case when p_voucher_ent is not null then 'voucher' else 'unlimited' end,
          case when p_voucher_ent is not null then array['unlimited', 'voucher'] else array['unlimited'] end,
          case when p_voucher_ent is not null then 5 end, pg_temp.id(p_voucher_ent),
          case when p_voucher_ent is not null then public.sg_today() + 300 end)
  returning id into v;
  return pg_temp.put(p_k, v);
end $f$;
-- The Purchased list as staff of stores FA and FB see it: every status, a search, two pages.
create function pg_temp.purchased_all() returns jsonb language plpgsql as $f$
declare who uuid := pg_temp.id('stf_f'); out jsonb := '[]'::jsonb; s text;
begin
  foreach s in array array['', 'all', 'open', 'pending_activation', 'scheduled', 'active', 'expired', 'closed'] loop
    out := out || jsonb_build_array(pg_temp.list(who, 'purchased', null, nullif(s, '')));
  end loop;
  return out || jsonb_build_array(pg_temp.list(who, 'purchased', '502r purchased buyer 3'),
                                  pg_temp.list(who, 'purchased', '502R Purchased', 'all', 2, 0),
                                  pg_temp.list(who, 'purchased', '502R Purchased', 'all', 2, 2));
end $f$;

-- ═════ Fixtures (invented) ═════
do $fx$
declare k text; v uuid;
begin
  perform pg_temp.put_txt('sfx', lower(substr(md5(gen_random_uuid()::text), 1, 6)));
  foreach k in array array['fa', 'fb', 'g', 'h', 'ja', 'jb', 'k', 'l', 'm', 'o', 'q'] loop perform pg_temp.store(k); end loop;
  perform pg_temp.person('own', 'owner');
  perform pg_temp.person('stf_f', 'staff', array['fa', 'fb']);
  perform pg_temp.person('stf_fa', 'staff', array['fa']);
  perform pg_temp.person('stf', 'staff', array['g', 'h', 'l']);
  perform pg_temp.person('mgr_ja', 'manager', array['ja']);
  perform pg_temp.person('stf_ja', 'staff', array['ja']);
  perform pg_temp.person('mgr_k', 'manager', array['k']);
  insert into public.vouchers (name, code) values ('502R Voucher One ' || pg_temp.txt('sfx'), '502R-V1-' || pg_temp.txt('sfx')) returning id into v;
  perform pg_temp.put('v1', v);
  insert into public.vouchers (name, code) values ('502R Voucher Two ' || pg_temp.txt('sfx'), '502R-V2-' || pg_temp.txt('sfx')) returning id into v;
  perform pg_temp.put('v2', v);
  insert into public.unlimited_therapy_packages (name, duration_months) values ('502R Six Months ' || pg_temp.txt('sfx'), 6) returning id into v;
  perform pg_temp.put('utp', v);
  -- The rule the Legacy rewards were earned under, already off (as the go-live script leaves it).
  perform pg_temp.put('rule', pg_temp.call(pg_temp.id('own'),
    'select public.upsert_legacy_rule(null, null, ''502R rule'', 994, ''unlimited'', 1, null, 365, false, null, ''customer'')::text', 'server')::uuid);

  -- F: the Therapy page's lists, at stores FA and FB.
  perform pg_temp.cust('fc1', '502R List Customer One');
  perform pg_temp.cust('fc2', '502R List Customer Two');
  perform pg_temp.cust('fc3', '502R List Customer Three');
  perform pg_temp.cust('fc4', '502R List Customer Four');
  perform pg_temp.inv('fs1', 'fa', 'fc1', 'paid');
  perform pg_temp.inv('fs2', 'fa', 'fc2', 'paid');
  perform pg_temp.inv('fs3', 'fb', 'fc3', 'paid');
  -- Vouchers owed from a sale: waiting, handed over, withdrawn, and an older one marked expired.
  perform pg_temp.ent('f_cp1', 'fc1', 'fa', 'credit_package', 'voucher', 'pending_activation', p_sale => 'fs1');
  perform pg_temp.ent('f_ex1', 'fc1', 'fa', 'premium_bundle', 'voucher', 'expired', p_sale => 'fs1', p_deadline => public.sg_today() - 5);
  perform pg_temp.ent('f_pb1', 'fc2', 'fa', 'premium_bundle', 'voucher', 'pending_activation', p_sale => 'fs2', p_deadline => public.sg_today() + 200);
  perform pg_temp.ent('f_pb2', 'fc2', 'fa', 'premium_bundle', 'voucher', 'active', p_sale => 'fs2');
  perform pg_temp.handed('f_pb2', 10);
  perform pg_temp.ent('f_tp1', 'fc3', 'fb', 'therapy_package', 'voucher', 'pending_activation', p_qty => 5, p_sale => 'fs3');
  perform pg_temp.ent('f_cp2', 'fc3', 'fb', 'credit_package', 'voucher', 'cancelled', p_sale => 'fs3', p_revoked => 10);
  -- Legacy rewards in every status: waiting, booked to start, running, used, cancelled; an
  -- affiliate's; vouchers handed over from one.
  perform pg_temp.ent('f_l1', 'fc1', 'fa', 'customer', 'unlimited', 'pending_activation');
  perform pg_temp.ent('f_l2', 'fc2', 'fa', 'affiliate', 'voucher', 'pending_activation');
  perform pg_temp.ent('f_l3', 'fc2', 'fa', 'customer', 'unlimited', 'scheduled', p_act => public.sg_today() + 10, p_exp => public.sg_today() + 40);
  perform pg_temp.ent('f_l4', 'fc3', 'fb', 'customer', 'unlimited', 'active', p_act => public.sg_today() - 10, p_exp => public.sg_today() + 20);
  perform pg_temp.ent('f_l5', 'fc3', 'fb', 'customer', 'unlimited', 'expired', p_act => public.sg_today() - 60, p_exp => public.sg_today() - 30);
  perform pg_temp.ent('f_l6', 'fc3', 'fb', 'customer', 'unlimited', 'cancelled');
  perform pg_temp.ent('f_l7', 'fc4', 'fa', 'customer', 'voucher', 'active');
  perform pg_temp.held('f_l7', 10);
  perform pg_temp.ent('f_l8', 'fc4', 'fa', 'affiliate', 'voucher', 'cancelled', p_revoked => 10);
  -- The Purchased list: units in every status, and one taken as vouchers (2 of 5 handed over).
  for k in select unnest(array['1', '2', '3', '4', '5', '6', '7']) loop
    perform pg_temp.cust('fp' || k, '502R Purchased Buyer ' || k);
    perform pg_temp.inv('fpi' || k, case when k = '6' then 'fb' else 'fa' end, 'fp' || k, case when k = '6' then 'refunded' else 'paid' end);
  end loop;
  perform pg_temp.unit('fp_u1', 'fp1', 'fa', 'fpi1', 'pending_activation', public.sg_today() + 200);
  perform pg_temp.unit('fp_u2', 'fp2', 'fa', 'fpi2', 'scheduled', public.sg_today() + 200, public.sg_today() + 5, public.sg_today() + 185);
  perform pg_temp.unit('fp_u3', 'fp3', 'fa', 'fpi3', 'active', public.sg_today() + 200, public.sg_today() - 10, public.sg_today() + 170);
  perform pg_temp.unit('fp_u4', 'fp4', 'fa', 'fpi4', 'expired', public.sg_today() + 200, public.sg_today() - 200, public.sg_today() - 10);
  perform pg_temp.unit('fp_u5', 'fp5', 'fa', 'fpi5', 'cancelled', public.sg_today() + 200);
  perform pg_temp.unit('fp_u6', 'fp6', 'fb', 'fpi6', 'refunded', public.sg_today() + 200);
  perform pg_temp.ent('f_tpv', 'fp7', 'fa', 'therapy_package', 'voucher', 'pending_activation', p_qty => 5, p_sale => 'fpi7');
  perform pg_temp.handed('f_tpv', 2);
  perform pg_temp.unit('fp_u7', 'fp7', 'fa', 'fpi7', 'pending_activation', public.sg_today() + 200, p_voucher_ent => 'f_tpv');
end $fx$;

-- ═════ Install (skipped with -v skip_install=1) ═════
\if :{?skip_install}
do $$ begin raise notice 'NOTE  502 is in already: the Purchased list is compared before and after it in U'; end $$;
create temp table t502r_pre as select null::jsonb pre_list, null::text pre_state, null::text pre_trig;
\else
-- The Purchased list and what 502 may change, before it.
create temp table t502r_pre as select pg_temp.purchased_all() pre_list, pg_temp.state() pre_state, pg_temp.triggers() pre_trig;
do $i$ begin execute current_setting('t502r.mig'); end $i$;
\endif
do $i$
begin
  perform pg_temp.ok(not exists (select 1 from t502r_fn f where pg_temp.md5_of(f.sig) is distinct from f.after_md5)
      and not exists (select 1 from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'legacy_refund_guard'),
    'I0 502 is in: the 15 functions at its AFTER md5s, the refund guard gone');
  if exists (select 1 from t502r_fn f where pg_temp.md5_of(f.sig) is distinct from f.after_md5) then
    raise exception '502R: 502 is not in, so nothing here can be checked'; end if;
end $i$;
create temp table t502r_post as select pg_temp.state() post_state, pg_temp.triggers() post_trig, pg_temp.fp() post_fp;

-- ═════ F Vouchers to hand over ═════
do $t$
declare
  stf uuid := pg_temp.id('stf_f'); stf_a uuid := pg_temp.id('stf_fa');
  s text; p jsonb; q jsonb; want uuid[]; all_ok boolean := true; legacy_seen int := 0; n int; got uuid[] := '{}'; t text;
  v_phone text := (select phone from public.customers where id = pg_temp.id('fc2'));
begin
  -- F1-F3 Every status, under the new name and the old one, as staff of both stores and of one.
  foreach s in array array['', 'open', 'all', 'pending_activation', 'scheduled', 'active', 'expired', 'cancelled'] loop
    p := pg_temp.list(stf, 'vouchers', null, nullif(s, ''));
    q := pg_temp.list(stf, 'legacy', null, nullif(s, ''));
    legacy_seen := legacy_seen + (select count(*) from jsonb_array_elements(p->'rows') r where r->>'earner_kind' in ('customer', 'affiliate'))
                               + (select count(*) from jsonb_array_elements(q->'rows') r where r->>'earner_kind' in ('customer', 'affiliate'));
    want := (select coalesce(array_agg(id order by id), '{}') from t502r_row
              where not legacy and store in ('fa', 'fb')
                and (s = 'all' or (s in ('', 'open') and status_now <> 'cancelled') or status_now = s));
    if pg_temp.ids(p) is distinct from want or (p->>'total')::int is distinct from cardinality(want)
       or (p - 'tab') is distinct from (q - 'tab') or p->>'tab' is distinct from 'vouchers' or q->>'tab' is distinct from 'legacy'
       or p->>'status' is distinct from coalesce(nullif(s, ''), 'open') then
      all_ok := false; raise warning 'F status % gave % rows (wanted %): %', coalesce(nullif(s, ''), 'default'), p->>'total', cardinality(want), p;
    end if;
    p := pg_temp.list(stf_a, 'vouchers', null, nullif(s, ''));
    want := (select coalesce(array_agg(id order by id), '{}') from t502r_row
              where not legacy and store = 'fa'
                and (s = 'all' or (s in ('', 'open') and status_now <> 'cancelled') or status_now = s));
    legacy_seen := legacy_seen + (select count(*) from jsonb_array_elements(p->'rows') r where r->>'earner_kind' in ('customer', 'affiliate'));
    if pg_temp.ids(p) is distinct from want then all_ok := false; raise warning 'F status % at store FA alone: %', s, p; end if;
  end loop;
  perform pg_temp.ok(legacy_seen = 0, 'F1 no status (open, all, waiting, booked, running, used, cancelled) lists a Legacy reward, under either name, in either store');
  perform pg_temp.ok(all_ok, 'F2 each status lists exactly the vouchers owed from a sale in that status; ''legacy'' reads the same as ''vouchers''; the default is open');
  perform pg_temp.ok((select count(*) from t502r_row where legacy and store in ('fa', 'fb')) = 8
      and (select count(distinct status_now) from t502r_row where legacy and store in ('fa', 'fb')) = 5,
    'F3 (the fixture holds 8 Legacy rewards at these stores, in 5 statuses, so F1 means something)');

  -- F4 Search: by name, phone, number, package and the sale's number; a Legacy reward is never found.
  p := pg_temp.list(stf, 'vouchers', 'list customer one', 'all');
  perform pg_temp.ok(pg_temp.ids(p) = pg_temp.keys(array['f_cp1', 'f_ex1']), 'F4 search by name finds the customer''s vouchers owed and not their Legacy month: ' || (p->>'total'));
  p := pg_temp.list(stf, 'vouchers', v_phone, 'all');
  perform pg_temp.ok(pg_temp.ids(p) = pg_temp.keys(array['f_pb1', 'f_pb2']), 'F5 search by phone: the bundle rewards, not the Legacy ones: ' || (p->>'total'));
  p := pg_temp.list(stf, 'vouchers', '502R-' || pg_temp.txt('sfx') || '-F_CP1', null);
  perform pg_temp.ok(pg_temp.ids(p) = pg_temp.keys(array['f_cp1']), 'F6 search by number');
  p := pg_temp.list(stf, 'vouchers', '502R-' || pg_temp.txt('sfx') || '-F_L1', 'all');
  q := pg_temp.list(stf, 'vouchers', 'legacy month', 'all');
  perform pg_temp.ok((p->>'total')::int = 0 and (q->>'total')::int = 0 and p->'rows' = '[]'::jsonb,
    'F7 a Legacy reward''s own number, or its package, finds nothing');
  p := pg_temp.list(stf, 'vouchers', '502r bundle reward', 'all');
  perform pg_temp.ok(pg_temp.ids(p) = pg_temp.keys(array['f_pb1', 'f_pb2', 'f_ex1']), 'F8 search by package');
  p := pg_temp.list(stf, 'vouchers', pg_temp.inv_no('fs3'), 'all');
  perform pg_temp.ok(pg_temp.ids(p) = pg_temp.keys(array['f_tp1', 'f_cp2']), 'F9 search by the sale''s invoice number');

  -- F10 Paging: three to a page; every page says the same total; a page past the end is empty.
  n := (select count(*) from t502r_row where not legacy and store in ('fa', 'fb'));
  all_ok := true;
  for s in select x::text from generate_series(0, n + 2, 3) x loop
    p := pg_temp.list(stf, 'vouchers', null, 'all', 3, s::int);
    if (p->>'total')::int <> n or (p->>'limit')::int <> 3 or (p->>'offset')::int <> s::int
       or jsonb_array_length(p->'rows') <> greatest(least(3, n - s::int), 0) then all_ok := false; end if;
    got := got || pg_temp.ids(p);
  end loop;
  perform pg_temp.ok(all_ok and (select array_agg(x order by x) from unnest(got) x) = (select array_agg(id order by id) from t502r_row where not legacy and store in ('fa', 'fb')),
    'F10 paging three at a time: every page says ' || n || ', the pages hold each row once, the page past the end is empty');

  -- F11 An unknown list, and a status the list does not have.
  t := pg_temp.try_as(stf, 'select public.therapy_list_page(''rewards'')::text');
  perform pg_temp.ok(t = 'P0001:Unknown list: rewards (purchased or vouchers)', 'F11 an unknown list: ' || t);
  t := pg_temp.try_as(stf, 'select public.therapy_list_page(null)::text');
  perform pg_temp.ok(t = 'P0001:Unknown list: none (purchased or vouchers)', 'F12 no list named: ' || t);
  t := pg_temp.try_as(stf, 'select public.therapy_list_page(''vouchers'', null, ''closed'')::text');
  perform pg_temp.ok(t = 'P0001:Unknown status filter: closed', 'F13 a status the list does not have, as before: ' || t);

  -- F14 Each row as the page reads it: what is left, the deadline, the sale.
  p := pg_temp.list(stf, 'vouchers', '502R-' || pg_temp.txt('sfx') || '-F_PB2', 'all');
  q := pg_temp.list(stf, 'vouchers', '502R-' || pg_temp.txt('sfx') || '-F_TPV', 'all');
  perform pg_temp.ok(p->'rows'->0->>'earner_kind' = 'premium_bundle' and (p->'rows'->0->>'claimed_qty')::int = 10
      and (p->'rows'->0->>'remaining')::int = 0 and p->'rows'->0->>'status_now' = 'active'
      and (q->'rows'->0->>'claimed_qty')::int = 2 and (q->'rows'->0->>'remaining')::int = 3
      and q->'rows'->0->>'source_invoice_no' = pg_temp.inv_no('fpi7') and q->'rows'->0->'blocked_reason' = 'null'::jsonb
      and q->'rows'->0->'next_free_start' = 'null'::jsonb and q->'rows'->0->'days_remaining' = 'null'::jsonb
      and (select count(*) from jsonb_object_keys(q->'rows'->0)) = 31,
    'F14 a row reads as before: handed over 10 of 10 leaves 0; 2 of 5 leaves 3; its sale; the row keeps its 31 keys');
  t := pg_temp.try_as(pg_temp.id('own'), 'select public.therapy_list_page(''vouchers'')::text', 'anon');
  perform pg_temp.ok(t like '42501:%', 'F15 signed out: refused, as before: ' || t);

  -- F16 The Purchased list, before and after 502, on these units (in U too, with or without -v skip_install).
  if (select pre_list from t502r_pre) is not null then
    perform pg_temp.ok(pg_temp.purchased_all() = (select pre_list from t502r_pre),
      'F16 the Purchased list (8 statuses, a search, two pages) is the same before and after installing 502');
  end if;
  p := pg_temp.list(stf, 'purchased', '502R-' || pg_temp.txt('sfx') || '-FP_U7');
  perform pg_temp.ok((p->'rows'->0->>'voucher_entitled')::int = 5 and (p->'rows'->0->>'voucher_claimed')::int = 2
      and (p->'rows'->0->>'voucher_remaining')::int = 3 and (pg_temp.list(stf, 'purchased', '502R Purchased')->>'total')::int = 7,
    'F17 the Purchased list still shows every unit, and a unit taken as vouchers its allowance (5, 2 handed over, 3 left)');
end $t$;

-- ═════ G Deleting a customer (the user, 10 Nov 2026) ═════
create function pg_temp.del(p_cust text, p_who text default 'own', p_name text default null) returns text language sql as $f$
  select pg_temp.try_as(pg_temp.id(p_who), format('select public.delete_customer(%L::uuid, %L, %L)::text',
                        pg_temp.id(p_cust), coalesce(p_name, pg_temp.cname(p_cust)), '502R check')) $f$;
create function pg_temp.gone(p_cust text) returns boolean language sql as $f$
  select deleted_at is not null from public.customers where id = pg_temp.id(p_cust) $f$;
-- The hand-over window: these vouchers from this reward, as this login.
create function pg_temp.hand_over(p_who text, p_ent text, p_qty int) returns text language sql as $f$
  select pg_temp.try_as(pg_temp.id(p_who), format('select public.claim_entitlement_vouchers(%L::uuid, %L::jsonb, %L)::text', pg_temp.id(p_ent),
                        jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.id('v1'), 'quantity', p_qty)), '502R check')) $f$;
create function pg_temp.voucher_state(p_who text, p_ent text) returns jsonb language sql as $f$
  select pg_temp.call(pg_temp.id(p_who), format('select public.entitlement_voucher_state(%L::uuid)::text', pg_temp.id(p_ent)))::jsonb $f$;
do $t$
declare t text; st jsonb; owed1 text := pg_temp.txt('c_owed1'); v uuid;
begin
  -- G1 A customer whose rewards are all Legacy (waiting, booked, running, handed over, an
  -- affiliate's waiting vouchers) is deleted.
  perform pg_temp.cust('g1', '502R Delete Legacy Only');
  perform pg_temp.ent('g1_a', 'g1', 'g', 'customer', 'unlimited', 'pending_activation');
  perform pg_temp.ent('g1_b', 'g1', 'g', 'customer', 'unlimited', 'scheduled', p_act => public.sg_today() + 10, p_exp => public.sg_today() + 40);
  perform pg_temp.ent('g1_c', 'g1', 'g', 'customer', 'unlimited', 'active', p_act => public.sg_today() - 5, p_exp => public.sg_today() + 25);
  perform pg_temp.ent('g1_d', 'g1', 'g', 'customer', 'voucher', 'active');
  perform pg_temp.held('g1_d', 10);
  perform pg_temp.ent('g1_e', 'g1', 'g', 'affiliate', 'voucher', 'pending_activation');
  t := pg_temp.del('g1');
  perform pg_temp.ok(t like 'ok:%' and pg_temp.gone('g1'), 'G1 only Legacy rewards (waiting, booked, running, handed over, an affiliate''s): deleted: ' || t);

  -- G2 Vouchers still owed from a sale, within their date: refused, in the page's words.
  perform pg_temp.cust('g2', '502R Delete Owed');
  perform pg_temp.inv('g2_s', 'g', 'g2', 'paid');
  perform pg_temp.ent('g2_r', 'g2', 'g', 'credit_package', 'voucher', 'pending_activation', p_sale => 'g2_s', p_deadline => public.sg_today() + 30);
  perform pg_temp.ent('g2_l', 'g2', 'g', 'customer', 'unlimited', 'pending_activation');
  t := pg_temp.del('g2');
  perform pg_temp.ok(t = 'P0001:' || owed1 and not pg_temp.gone('g2'), 'G2 a Credit Package reward still owed: refused, exactly, counting 1 (its Legacy month is not counted): ' || t);
  perform pg_temp.cust('g2c', '502R Delete Owed Bundle');
  perform pg_temp.inv('g2c_s', 'g', 'g2c', 'paid');
  perform pg_temp.ent('g2c_r', 'g2c', 'g', 'premium_bundle', 'voucher', 'pending_activation', p_sale => 'g2c_s', p_deadline => public.sg_today() + 30);
  t := pg_temp.del('g2c');
  perform pg_temp.ok(t = 'P0001:' || owed1 and not pg_temp.gone('g2c'), 'G2b a Premium Bundle reward still owed: refused, exactly: ' || t);
  perform pg_temp.cust('g2b', '502R Delete Owed Two');
  perform pg_temp.inv('g2b_s', 'g', 'g2b', 'paid');
  perform pg_temp.ent('g2b_r1', 'g2b', 'g', 'premium_bundle', 'voucher', 'pending_activation', p_sale => 'g2b_s');
  perform pg_temp.ent('g2b_r2', 'g2b', 'g', 'therapy_package', 'voucher', 'pending_activation', p_qty => 5, p_sale => 'g2b_s');
  t := pg_temp.del('g2b');
  perform pg_temp.ok(t = 'P0001:' || pg_temp.txt('c_owed2'), 'G3 a Premium Bundle and a therapy-package reward still owed: refused, counting 2: ' || t);
  t := pg_temp.del('g2', 'stf');
  perform pg_temp.ok(t = 'P0001:Only an Owner or Manager can delete a customer', 'G4 staff still cannot delete anyone: ' || t);

  -- G5 On the collect-by date itself a hand-over is still allowed, so the delete is refused.
  perform pg_temp.cust('g3', '502R Delete Last Day');
  perform pg_temp.inv('g3_s', 'g', 'g3', 'paid');
  perform pg_temp.ent('g3_r', 'g3', 'g', 'credit_package', 'voucher', 'pending_activation', p_sale => 'g3_s', p_deadline => public.sg_today());
  st := pg_temp.voucher_state('stf', 'g3_r');
  t := pg_temp.hand_over('stf', 'g3_r', 1);
  perform pg_temp.ok((st->>'deadline_passed')::boolean = false and (st->>'remaining')::int = 10 and t like 'ok:%',
    'G5 on its collect-by date the hand-over window still hands over (1 of 10): ' || left(t, 60));
  t := pg_temp.del('g3');
  perform pg_temp.ok(t = 'P0001:' || owed1, 'G6 and the delete is refused that day (9 still owed): ' || t);
  -- G7 The day after, nothing can be handed over, so nothing blocks.
  perform pg_temp.cust('g4', '502R Delete Past Date');
  perform pg_temp.inv('g4_s', 'g', 'g4', 'paid');
  perform pg_temp.ent('g4_r', 'g4', 'g', 'credit_package', 'voucher', 'pending_activation', p_sale => 'g4_s', p_deadline => public.sg_today() - 1);
  st := pg_temp.voucher_state('stf', 'g4_r');
  t := pg_temp.hand_over('stf', 'g4_r', 1);
  perform pg_temp.ok((st->>'deadline_passed')::boolean and t = 'P0001:The claim deadline (' || (public.sg_today() - 1)::text || ') has passed',
    'G7 past its collect-by date the hand-over window refuses: ' || t);
  t := pg_temp.del('g4');
  perform pg_temp.ok(t like 'ok:%' and pg_temp.gone('g4'), 'G8 so a reward past its collect-by date does not stop the delete: ' || t);

  -- G9 Fully handed over, through the hand-over window (status active): deleted.
  perform pg_temp.cust('g5', '502R Delete Handed Over');
  perform pg_temp.inv('g5_s', 'g', 'g5', 'paid');
  perform pg_temp.ent('g5_r', 'g5', 'g', 'premium_bundle', 'voucher', 'pending_activation', p_sale => 'g5_s');
  t := pg_temp.hand_over('stf', 'g5_r', 6);
  t := t || ' / ' || pg_temp.hand_over('stf', 'g5_r', 4);
  perform pg_temp.ok((select status from public.therapy_entitlements where id = pg_temp.id('g5_r')) = 'active'
      and public.entitlement_claimed_qty(pg_temp.id('g5_r')) = 10, 'G9 handed over in two goes, 6 and 4: the reward is complete (active)');
  t := pg_temp.del('g5');
  perform pg_temp.ok(t like 'ok:%' and pg_temp.gone('g5'), 'G10 a reward fully handed over does not stop the delete: ' || t);

  -- G11 Part handed over, the rest withdrawn (as on a closed sale): deleted.
  perform pg_temp.cust('g6', '502R Delete Withdrawn');
  perform pg_temp.inv('g6_s', 'g', 'g6', 'paid');
  perform pg_temp.ent('g6_r', 'g6', 'g', 'credit_package', 'voucher', 'pending_activation', p_sale => 'g6_s');
  t := pg_temp.hand_over('stf', 'g6_r', 4);
  t := pg_temp.call(null, format('select public.revoke_unclaimed_entitlement_vouchers(%L::uuid, %L)::text', pg_temp.id('g6_s'), '502R check: withdrawn'), 'server');
  perform pg_temp.ok(t = '6' and (select status = 'active' and revoked_qty = 6 from public.therapy_entitlements where id = pg_temp.id('g6_r')),
    'G11 4 handed over, the other 6 withdrawn: the reward stays, closed (active)');
  t := pg_temp.del('g6');
  perform pg_temp.ok(t like 'ok:%' and pg_temp.gone('g6'), 'G12 so it does not stop the delete: ' || t);

  -- G13 Its sale refunded, cancelled or deleted: nothing can be handed over, so nothing blocks.
  perform pg_temp.cust('g7', '502R Delete Sale Refunded');
  perform pg_temp.inv('g7_s', 'g', 'g7', 'refunded');
  perform pg_temp.ent('g7_r', 'g7', 'g', 'credit_package', 'voucher', 'pending_activation', p_sale => 'g7_s');
  perform pg_temp.cust('g7b', '502R Delete Sale Cancelled');
  perform pg_temp.inv('g7b_s', 'g', 'g7b', 'cancelled');
  perform pg_temp.ent('g7b_r', 'g7b', 'g', 'premium_bundle', 'voucher', 'pending_activation', p_sale => 'g7b_s');
  perform pg_temp.cust('g8', '502R Delete Sale Deleted');
  perform pg_temp.inv('g8_s', 'g', 'g8', 'paid', 1000, true);
  perform pg_temp.ent('g8_r', 'g8', 'g', 'credit_package', 'voucher', 'pending_activation', p_sale => 'g8_s');
  perform pg_temp.ok(pg_temp.voucher_state('stf', 'g7_r')->>'blocked_reason' = 'Invoice ' || pg_temp.inv_no('g7_s') || ' was refunded'
      and pg_temp.voucher_state('stf', 'g7b_r')->>'blocked_reason' = 'Invoice ' || pg_temp.inv_no('g7b_s') || ' was cancelled'
      and pg_temp.voucher_state('stf', 'g8_r')->>'blocked_reason' = 'Invoice ' || pg_temp.inv_no('g8_s') || ' was deleted',
    'G13 (the hand-over window says each sale was refunded, cancelled or deleted)');
  t := pg_temp.del('g7') || ' / ' || pg_temp.del('g7b') || ' / ' || pg_temp.del('g8');
  perform pg_temp.ok(pg_temp.gone('g7') and pg_temp.gone('g7b') and pg_temp.gone('g8'),
    'G14 a reward from a refunded, a cancelled or a deleted sale does not stop the delete: ' || t);

  -- G15 Vouchers owed with no sale recorded: refused (an Owner or Manager can still hand them over).
  perform pg_temp.cust('g9', '502R Delete No Sale');
  perform pg_temp.ent('g9_r', 'g9', 'g', 'premium_bundle', 'voucher', 'pending_activation');
  t := pg_temp.del('g9');
  perform pg_temp.ok(t = 'P0001:' || owed1, 'G15 vouchers owed with no sale recorded: refused: ' || t);

  -- G16 A live unlimited period that is not Legacy (none is written today; the rule still holds).
  perform pg_temp.cust('g10', '502R Delete Live Period');
  perform pg_temp.ent('g10_r', 'g10', 'g', 'premium_bundle', 'unlimited', 'active', p_act => public.sg_today() - 5, p_exp => public.sg_today() + 25);
  perform pg_temp.cust('g10b', '502R Delete Waiting Period');
  perform pg_temp.ent('g10b_r', 'g10b', 'g', 'premium_bundle', 'unlimited', 'pending_activation');
  perform pg_temp.cust('g10c', '502R Delete Used Period');
  perform pg_temp.ent('g10c_r', 'g10c', 'g', 'premium_bundle', 'unlimited', 'expired', p_act => public.sg_today() - 60, p_exp => public.sg_today() - 30);
  t := pg_temp.del('g10') || ' / ' || pg_temp.del('g10b');
  perform pg_temp.ok(t = 'P0001:' || owed1 || ' / P0001:' || owed1 and not pg_temp.gone('g10') and not pg_temp.gone('g10b'),
    'G16 a live unlimited period that is not Legacy (running, or waiting): refused: ' || t);
  t := pg_temp.del('g10c');
  perform pg_temp.ok(t like 'ok:%', 'G17 one already used: deleted: ' || t);

  -- G18 A withdrawn reward (cancelled), and one waiting with nothing left: deleted.
  perform pg_temp.cust('g11', '502R Delete Nothing Left');
  perform pg_temp.inv('g11_s', 'g', 'g11', 'paid');
  perform pg_temp.ent('g11_a', 'g11', 'g', 'credit_package', 'voucher', 'cancelled', p_sale => 'g11_s', p_revoked => 10);
  perform pg_temp.ent('g11_b', 'g11', 'g', 'credit_package', 'voucher', 'pending_activation', p_sale => 'g11_s', p_revoked => 10);
  t := pg_temp.del('g11');
  perform pg_temp.ok(t like 'ok:%', 'G18 a reward cancelled, or waiting with nothing left to hand over: deleted: ' || t);

  -- G19 The other refusals come first, in their old order and words; owed vouchers come last.
  perform pg_temp.cust('g12', '502R Delete Everything');
  perform pg_temp.inv('g12_s', 'g', 'g12', 'paid');
  perform pg_temp.ent('g12_r', 'g12', 'g', 'credit_package', 'voucher', 'pending_activation', p_sale => 'g12_s');
  insert into public.customer_credit_wallets (customer_id) values (pg_temp.id('g12')) returning id into v;
  insert into public.customer_credit_lots (wallet_id, customer_id, category, original_amount, remaining_amount, source_type)
  values (v, pg_temp.id('g12'), 'paid', 100, 100, 'manual_adjustment') returning id into v;
  perform pg_temp.put('g12_lot', v);
  perform pg_temp.inv('g12_us', 'g', 'g12', 'paid');
  perform pg_temp.unit('g12_u', 'g12', 'g', 'g12_us', 'pending_activation', public.sg_today() + 100);
  perform pg_temp.inv('g12_unpaid', 'g', 'g12', 'unpaid');
  insert into public.special_products (name, sku) values ('502R Machine ' || pg_temp.txt('sfx'), '502R-MACH-' || pg_temp.txt('sfx')) returning id into v;
  insert into public.rentals (rental_no, special_product_id, customer_id, quantity, rate_type, periods, start_date, expected_return_date, status, store_id)
  values ('502R-' || pg_temp.txt('sfx') || '-RENT', v, pg_temp.id('g12'), 1, 'day', 1, public.sg_today(), public.sg_today() + 1, 'active', pg_temp.id('g'))
  returning id into v;
  perform pg_temp.put('g12_rent', v);
  insert into public.stock_loans (loan_no, location_type, store_id, customer_id, expected_return_date)
  values ('502R-' || pg_temp.txt('sfx') || '-LOAN', 'store', pg_temp.id('g'), pg_temp.id('g12'), public.sg_today() + 7) returning id into v;
  perform pg_temp.put('g12_loan', v);
  insert into public.customer_affiliates (customer_id) values (pg_temp.id('g12')) returning id into v;
  perform pg_temp.put('g12_aff', v);
  t := pg_temp.del('g12', 'own', 'Someone Else');
  perform pg_temp.ok(t = 'P0001:The name you typed does not match "' || pg_temp.cname('g12') || '"', 'G19 a wrong name first: ' || t);
  t := pg_temp.del('g12');
  perform pg_temp.ok(t = 'P0001:This customer still holds S$100.00 of wallet credit. Refund or transfer it first.', 'G20 then wallet credit: ' || t);
  update public.customer_credit_lots set status = 'reversed' where id = pg_temp.id('g12_lot');
  t := pg_temp.del('g12');
  perform pg_temp.ok(t = 'P0001:This customer has 1 therapy entitlement(s) not yet used. Settle them first.', 'G21 then purchased therapy not used: ' || t);
  delete from public.purchased_therapy_entitlements where id = pg_temp.id('g12_u');
  t := pg_temp.del('g12');
  perform pg_temp.ok(t = 'P0001:This customer has 1 unpaid or part-paid invoice(s). Settle or cancel them first.', 'G22 then an unpaid invoice: ' || t);
  delete from public.invoices where id = pg_temp.id('g12_unpaid');
  t := pg_temp.del('g12');
  perform pg_temp.ok(t = 'P0001:This customer has 1 rental(s) not yet returned or cancelled. Settle them first.', 'G23 then a rental out: ' || t);
  delete from public.rentals where id = pg_temp.id('g12_rent');
  t := pg_temp.del('g12');
  perform pg_temp.ok(t = 'P0001:This customer has 1 stock loan(s) still open. Close them first.', 'G24 then a stock loan: ' || t);
  delete from public.stock_loans where id = pg_temp.id('g12_loan');
  t := pg_temp.del('g12');
  perform pg_temp.ok(t = 'P0001:This customer is an affiliate (or has an affiliate login), so they cannot be deleted.', 'G25 then being an affiliate: ' || t);
  delete from public.customer_affiliates where id = pg_temp.id('g12_aff');
  t := pg_temp.del('g12');
  perform pg_temp.ok(t = 'P0001:' || owed1, 'G26 and last, the vouchers still owed: ' || t);
  update public.therapy_entitlements set status = 'cancelled' where id = pg_temp.id('g12_r');
  t := pg_temp.del('g12');
  perform pg_temp.ok(t like 'ok:%' and pg_temp.gone('g12'), 'G27 with nothing left: deleted: ' || t);
  -- The commission refusals sit between the affiliate's and the vouchers', as before (their
  -- fixtures are another suite's): the function's text keeps every refusal in its old order.
  t := pg_get_functiondef('public.delete_customer(uuid,text,text)'::regprocedure);
  perform pg_temp.ok(strpos(t, 'Only an Owner or Manager can delete a customer') < strpos(t, 'does not match')
      and strpos(t, 'does not match') < strpos(t, 'of wallet credit') and strpos(t, 'of wallet credit') < strpos(t, 'therapy entitlement(s) not yet used')
      and strpos(t, 'therapy entitlement(s) not yet used') < strpos(t, 'unpaid or part-paid invoice(s)')
      and strpos(t, 'unpaid or part-paid invoice(s)') < strpos(t, 'rental(s) not yet returned')
      and strpos(t, 'rental(s) not yet returned') < strpos(t, 'stock loan(s) still open')
      and strpos(t, 'stock loan(s) still open') < strpos(t, 'is an affiliate (or has an affiliate login)')
      and strpos(t, 'is an affiliate (or has an affiliate login)') < strpos(t, 'commission as a referrer')
      and strpos(t, 'commission as a referrer') < strpos(t, 'back from commission that was paid out')
      and strpos(t, 'back from commission that was paid out') < strpos(t, 'reward(s) with vouchers to hand over')
      and strpos(t, 'reward(s) with vouchers to hand over') < strpos(t, 'update public.customers')
      and strpos(t, 'legacy therapy entitlement') = 0,
    'G28 every other refusal keeps its place, the commission ones included; the old "legacy therapy entitlement(s)" words are gone');
end $t$;

-- ═════ H The Customers page: vouchers to hand over ═════
do $t$
declare o jsonb; l jsonb; want text[]; keys_ok boolean;
begin
  perform pg_temp.cust('h1', '502R Overview Customer');
  perform pg_temp.inv('h_s1', 'h', 'h1', 'paid');
  perform pg_temp.inv('h_s2', 'h', 'h1', 'refunded');
  perform pg_temp.ent('h_a', 'h1', 'h', 'credit_package', 'voucher', 'pending_activation', p_sale => 'h_s1',
                      p_deadline => public.sg_today() + 30, p_created => now() - interval '3 days');
  perform pg_temp.ent('h_b', 'h1', 'h', 'premium_bundle', 'voucher', 'pending_activation', p_sale => 'h_s1',
                      p_deadline => public.sg_today() + 10, p_created => now() - interval '2 days');
  perform pg_temp.handed('h_b', 4);
  perform pg_temp.ent('h_c', 'h1', 'h', 'therapy_package', 'voucher', 'pending_activation', p_qty => 5, p_sale => 'h_s1',
                      p_deadline => public.sg_today() + 10, p_created => now() - interval '1 day');
  perform pg_temp.ent('h_d', 'h1', 'h', 'credit_package', 'voucher', 'pending_activation', p_sale => 'h_s1', p_deadline => public.sg_today() - 1);
  perform pg_temp.ent('h_e', 'h1', 'h', 'credit_package', 'voucher', 'pending_activation', p_sale => 'h_s2', p_deadline => public.sg_today() + 60);
  -- Left out: fully handed over, withdrawn, nothing left, and Legacy (a month, an affiliate's
  -- vouchers, a customer's vouchers still waiting).
  perform pg_temp.ent('h_f', 'h1', 'h', 'premium_bundle', 'voucher', 'active', p_sale => 'h_s1');
  perform pg_temp.handed('h_f', 10);
  perform pg_temp.ent('h_g', 'h1', 'h', 'credit_package', 'voucher', 'cancelled', p_sale => 'h_s1', p_revoked => 10);
  perform pg_temp.ent('h_h', 'h1', 'h', 'credit_package', 'voucher', 'pending_activation', p_sale => 'h_s1', p_revoked => 10);
  perform pg_temp.ent('h_i', 'h1', 'h', 'customer', 'unlimited', 'pending_activation');
  perform pg_temp.ent('h_j', 'h1', 'h', 'affiliate', 'voucher', 'pending_activation');
  perform pg_temp.ent('h_k', 'h1', 'h', 'customer', 'voucher', 'pending_activation');
  o := pg_temp.call(pg_temp.id('stf'), format('select public.customer_overview(%L::uuid)::text', pg_temp.id('h1')))::jsonb;
  l := o->'vouchers_to_hand_over';
  perform pg_temp.ok(not (o ? 'legacy_therapy') and (select array_agg(k order by k) from jsonb_object_keys(o) k)
                       = array['affiliate_state', 'deleted_invoices', 'purchased_therapy', 'refunds', 'vouchers_to_hand_over'],
    'H1 the overview has vouchers_to_hand_over and no legacy_therapy; its other keys are as before');
  want := array['502R-' || pg_temp.txt('sfx') || '-H_D', '502R-' || pg_temp.txt('sfx') || '-H_B', '502R-' || pg_temp.txt('sfx') || '-H_C',
                '502R-' || pg_temp.txt('sfx') || '-H_A', '502R-' || pg_temp.txt('sfx') || '-H_E'];
  perform pg_temp.ok((select array_agg(e->>'no' order by n) from jsonb_array_elements(l) with ordinality x(e, n)) = want,
    'H2 the vouchers still owed, soonest collect-by date first, then oldest first; fully handed over, withdrawn, nothing left and Legacy are left out: '
    || (select string_agg(e->>'no', ', ') from jsonb_array_elements(l) e));
  keys_ok := not exists (select 1 from jsonb_array_elements(l) e
                          where (select array_agg(k order by k) from jsonb_object_keys(e) k)
                                is distinct from array['blocked_reason', 'deadline', 'deadline_passed', 'entitled', 'left', 'no', 'package']);
  perform pg_temp.ok(keys_ok, 'H3 each element is {no, package, left, entitled, deadline, deadline_passed, blocked_reason}');
  perform pg_temp.ok((l->1->>'left')::int = 6 and (l->1->>'entitled')::int = 10 and l->1->>'package' = '502R Bundle Reward'
      and (l->1->>'deadline')::date = public.sg_today() + 10 and (l->1->>'deadline_passed')::boolean = false and l->1->'blocked_reason' = 'null'::jsonb
      and (l->2->>'left')::int = 5 and (l->2->>'entitled')::int = 5,
    'H4 4 of 10 handed over leaves 6; a therapy package''s 5 untouched leaves 5');
  perform pg_temp.ok((l->0->>'deadline_passed')::boolean and (l->0->>'left')::int = 10
      and l->4->>'blocked_reason' = 'Invoice ' || pg_temp.inv_no('h_s2') || ' was refunded' and (l->4->>'deadline_passed')::boolean = false,
    'H5 one past its date says so; one on a refunded sale says why nothing can be handed over');
  o := pg_temp.call(pg_temp.id('stf'), format('select public.customer_overview(%L::uuid)::text', pg_temp.id('fc4')))::jsonb;
  perform pg_temp.ok(o->'vouchers_to_hand_over' = '[]'::jsonb, 'H6 a customer with only Legacy rewards: an empty list');
  perform pg_temp.ok((select is_nullable from information_schema.columns
                       where table_schema = 'public' and table_name = 'therapy_entitlements' and column_name = 'activation_deadline') = 'NO',
    'H7 (every reward has a collect-by date: the column is NOT NULL, so the list''s "no date last" never applies)');
end $t$;

-- ═════ J Reports → Therapy ═════
create function pg_temp.report(p_who text) returns jsonb language sql as $f$
  select pg_temp.call(pg_temp.id(p_who), 'select coalesce(jsonb_agg(jsonb_build_object(''no'', r.entitlement_no, ''legacy'', r.is_legacy, ''store'', r.store_name, ''status'', r.status)), ''[]'')::text from public.report_therapy() r')::jsonb $f$;
do $t$
declare r jsonb; mine text[]; pfx text := '502R-' || pg_temp.txt('sfx') || '-J';
begin
  perform pg_temp.cust('j1', '502R Report Customer A');
  perform pg_temp.cust('j2', '502R Report Customer B');
  perform pg_temp.inv('js1', 'ja', 'j1', 'paid');
  perform pg_temp.inv('js2', 'jb', 'j2', 'paid');
  perform pg_temp.unit('ju1', 'j1', 'ja', 'js1', 'pending_activation', public.sg_today() + 200);
  perform pg_temp.unit('ju2', 'j2', 'jb', 'js2', 'active', public.sg_today() + 200, public.sg_today() - 3, public.sg_today() + 177);
  perform pg_temp.ent('j_cp', 'j1', 'ja', 'credit_package', 'voucher', 'pending_activation', p_sale => 'js1');
  perform pg_temp.ent('j_pb', 'j2', 'jb', 'premium_bundle', 'voucher', 'active', p_sale => 'js2');
  perform pg_temp.ent('j_l1', 'j1', 'ja', 'customer', 'unlimited', 'pending_activation');
  perform pg_temp.ent('j_l2', 'j1', 'ja', 'affiliate', 'voucher', 'pending_activation');
  perform pg_temp.ent('j_l3', 'j2', 'jb', 'customer', 'unlimited', 'expired', p_act => public.sg_today() - 60, p_exp => public.sg_today() - 30);
  -- An Owner: every store.
  r := pg_temp.report('own');
  mine := (select array_agg((e->>'no') || ':' || (e->>'legacy') order by e->>'no' collate "C") from jsonb_array_elements(r) e where e->>'no' like pfx || '%');
  perform pg_temp.ok(mine = array[pfx || 'U1:false', pfx || 'U2:false', pfx || '_CP:true', pfx || '_PB:true'],
    'J1 an Owner: the purchased units (is_legacy false) and the vouchers owed from a sale (is_legacy true), no Legacy reward: ' || array_to_string(mine, ', '));
  perform pg_temp.ok(not exists (select 1 from jsonb_array_elements(r) e join public.therapy_entitlements te on te.entitlement_no = e->>'no'
                                  where te.earner_kind in ('customer', 'affiliate'))
      and jsonb_array_length(r) = (select count(*) from public.purchased_therapy_entitlements)
                                   + (select count(*) from public.therapy_entitlements where earner_kind not in ('customer', 'affiliate')),
    'J2 across the whole report: no Legacy row; every purchased unit and every reward that is not Legacy, in every store');
  -- A Manager at store JA: that store alone, as before.
  r := pg_temp.report('mgr_ja');
  mine := (select array_agg((e->>'no') || ':' || (e->>'legacy') order by e->>'no' collate "C") from jsonb_array_elements(r) e where e->>'no' like pfx || '%');
  perform pg_temp.ok(mine = array[pfx || 'U1:false', pfx || '_CP:true']
      and not exists (select 1 from jsonb_array_elements(r) e where e->>'store' is distinct from (select name from public.stores where id = pg_temp.id('ja'))),
    'J3 a Manager at one store: that store''s rows alone: ' || coalesce(array_to_string(mine, ', '), 'none'));
  r := pg_temp.report('stf_ja');
  perform pg_temp.ok(r = '[]'::jsonb, 'J4 staff: nothing, as before');
end $t$;

-- ═════ K The Dashboard's alert ═════
do $t$
declare a jsonb; it uuid; sale uuid; e uuid; v uuid;
begin
  perform pg_temp.cust('kc', '502R Dashboard Customer');
  insert into public.products (name, sku) values ('502R Item ' || pg_temp.txt('sfx'), '502R-ITEM-' || pg_temp.txt('sfx')) returning id into v;
  perform pg_temp.put('k_product', v);
  insert into public.credit_packages (name, customer_price, paid_credit_amount, grants_reward)
  values ('502R Package ' || pg_temp.txt('sfx'), 1000, 1000, false) returning id into v;
  perform pg_temp.put('k_package', v);
  -- K1 refunded; its only hold: a Legacy reward still waiting, linked to it as the recount linked them.
  perform pg_temp.inv('k1', 'k', 'kc', 'refunded');
  e := pg_temp.ent('k1_r', 'kc', 'k', 'customer', 'unlimited', 'pending_activation');
  insert into public.therapy_entitlement_invoices (entitlement_id, invoice_id, contributed_amount) values (e, pg_temp.id('k1'), 1000);
  -- K2 refunded; its only hold: vouchers held from a Legacy reward linked to it.
  perform pg_temp.inv('k2', 'k', 'kc', 'refunded');
  e := pg_temp.ent('k2_r', 'kc', 'k', 'customer', 'voucher', 'active');
  perform pg_temp.held('k2_r', 10);
  insert into public.therapy_entitlement_invoices (entitlement_id, invoice_id, contributed_amount) values (e, pg_temp.id('k2'), 1000);
  -- K3 refunded; a Credit Package reward still waiting, by its line (credit_pkg_item).
  perform pg_temp.inv('k3', 'k', 'kc', 'refunded');
  insert into public.invoice_items (invoice_id, product_id, quantity, unit_price, line_total, line_kind)
  values (pg_temp.id('k3'), pg_temp.id('k_product'), 1, 1000, 1000, 'product') returning id into it;
  perform pg_temp.ent('k3_r', 'kc', 'k', 'credit_package', 'voucher', 'pending_activation', p_sale => 'k3', p_group => md5('credit_pkg_item:' || it::text)::uuid);
  -- K4 cancelled; a Credit Package reward still waiting, by its sale (credit_pkg).
  perform pg_temp.inv('k4', 'k', 'kc', 'cancelled');
  insert into public.credit_package_sales (package_id, customer_id, store_id, invoice_id, package_name_snapshot, price_snapshot, credit_snapshot, classification_snapshot)
  values (pg_temp.id('k_package'), pg_temp.id('kc'), pg_temp.id('k'), pg_temp.id('k4'), '502R Package', 1000, 1000, 'third_party') returning id into sale;
  perform pg_temp.ent('k4_r', 'kc', 'k', 'credit_package', 'voucher', 'pending_activation', p_sale => 'k4', p_group => public.credit_package_reward_group(sale));
  -- K5 refunded; vouchers held from a Credit Package reward by its line, all handed over.
  perform pg_temp.inv('k5', 'k', 'kc', 'refunded');
  insert into public.invoice_items (invoice_id, product_id, quantity, unit_price, line_total, line_kind)
  values (pg_temp.id('k5'), pg_temp.id('k_product'), 1, 1000, 1000, 'product') returning id into it;
  perform pg_temp.ent('k5_r', 'kc', 'k', 'credit_package', 'voucher', 'active', p_sale => 'k5', p_group => md5('credit_pkg_item:' || it::text)::uuid);
  perform pg_temp.held('k5_r', 10, 'held', 'voucher_claim');
  -- K6 deleted; vouchers held from a Credit Package reward by its sale.
  perform pg_temp.inv('k6', 'k', 'kc', 'paid', 1000, true);
  insert into public.credit_package_sales (package_id, customer_id, store_id, invoice_id, package_name_snapshot, price_snapshot, credit_snapshot, classification_snapshot)
  values (pg_temp.id('k_package'), pg_temp.id('kc'), pg_temp.id('k'), pg_temp.id('k6'), '502R Package', 1000, 1000, 'third_party') returning id into sale;
  perform pg_temp.ent('k6_r', 'kc', 'k', 'credit_package', 'voucher', 'active', p_sale => 'k6', p_group => public.credit_package_reward_group(sale));
  perform pg_temp.held('k6_r', 10, 'held', 'voucher_claim');
  -- K7 refunded; both Legacy holds at once: an affiliate's reward linked to it (one link per
  -- invoice), still waiting, 4 of its 10 vouchers handed over and held.
  perform pg_temp.inv('k7', 'k', 'kc', 'refunded');
  e := pg_temp.ent('k7_r', 'kc', 'k', 'affiliate', 'voucher', 'pending_activation');
  perform pg_temp.held('k7_r', 4);
  insert into public.therapy_entitlement_invoices (entitlement_id, invoice_id, contributed_amount) values (e, pg_temp.id('k7'), 1000);
  -- K8 refunded; a Credit Package reward by its line, handed over and nothing still held: not counted, as before.
  perform pg_temp.inv('k8', 'k', 'kc', 'refunded');
  insert into public.invoice_items (invoice_id, product_id, quantity, unit_price, line_total, line_kind)
  values (pg_temp.id('k8'), pg_temp.id('k_product'), 1, 1000, 1000, 'product') returning id into it;
  perform pg_temp.ent('k8_r', 'kc', 'k', 'credit_package', 'voucher', 'active', p_sale => 'k8', p_group => md5('credit_pkg_item:' || it::text)::uuid);
  perform pg_temp.held('k8_r', 10, 'redeemed', 'voucher_claim');

  a := pg_temp.call(pg_temp.id('mgr_k'), 'select public.dashboard_alerts_summary()::text')::jsonb;
  perform pg_temp.ok((a->'sales'->>'holding_benefits')::int = 4
      and a->'sales'->'invoice_nos' = jsonb_build_array(pg_temp.inv_no('k3'), pg_temp.inv_no('k4'), pg_temp.inv_no('k5'), pg_temp.inv_no('k6')),
    'K1 at the Manager''s store: the 4 sales still holding a Credit Package reward or vouchers from one (by line and by sale) are listed; the 3 held only through a Legacy reward (waiting, vouchers held, both) are not: '
    || (a->'sales')::text);
  perform pg_temp.ok((select count(*) from jsonb_object_keys(a)) = 4 and a ? 'transfers' and a ? 'tiktok' and a ? 'surveys',
    'K2 the rest of the alerts are still there');
end $t$;

-- ═════ L The holdings card ═════
do $t$
declare s jsonb; d jsonb; b jsonb;
begin
  perform pg_temp.cust('l1', '502R Holdings Purchased');
  perform pg_temp.inv('l1_s', 'l', 'l1', 'paid');
  perform pg_temp.unit('l1_u', 'l1', 'l', 'l1_s', 'active', public.sg_today() + 200, public.sg_today() - 10, public.sg_today() + 20);
  perform pg_temp.ent('l1_a', 'l1', 'l', 'customer', 'unlimited', 'active', p_act => public.sg_today() - 5, p_exp => public.sg_today() + 40);
  perform pg_temp.ent('l1_b', 'l1', 'l', 'customer', 'unlimited', 'pending_activation');
  perform pg_temp.ent('l1_c', 'l1', 'l', 'customer', 'unlimited', 'scheduled', p_act => public.sg_today() + 50, p_exp => public.sg_today() + 80);
  perform pg_temp.cust('l2', '502R Holdings Legacy Only');
  perform pg_temp.ent('l2_a', 'l2', 'l', 'customer', 'unlimited', 'pending_activation');
  perform pg_temp.ent('l2_b', 'l2', 'l', 'customer', 'unlimited', 'expired', p_act => public.sg_today() - 60, p_exp => public.sg_today() - 30);
  perform pg_temp.cust('l3', '502R Holdings Earlier Vouchers');
  perform pg_temp.ent('l3_a', 'l3', 'l', 'customer', 'voucher', 'active');
  perform pg_temp.held('l3_a', 10);
  -- No writer makes an unlimited reward that is not Legacy today; this one shows its label.
  perform pg_temp.cust('l4', '502R Holdings Other Period');
  perform pg_temp.ent('l4_a', 'l4', 'l', 'premium_bundle', 'unlimited', 'active', p_act => public.sg_today() - 2, p_exp => public.sg_today() + 28);
  perform pg_temp.cust('l5', '502R Holdings Waiting');
  perform pg_temp.inv('l5_s', 'l', 'l5', 'paid');
  perform pg_temp.ent('l5_a', 'l5', 'l', 'credit_package', 'voucher', 'pending_activation', p_sale => 'l5_s');
  perform pg_temp.ent('l5_b', 'l5', 'l', 'customer', 'unlimited', 'pending_activation');
  perform pg_temp.ent('l5_c', 'l5', 'l', 'affiliate', 'voucher', 'pending_activation');

  s := pg_temp.call(pg_temp.id('stf'), format('select coalesce(jsonb_agg(to_jsonb(x) order by x.customer_name), ''[]'')::text from public.therapy_customer_summary(%L, 50, 0, false) x',
                                               '502R Holdings'))::jsonb;
  perform pg_temp.ok((select array_agg(e->>'customer_name' order by e->>'customer_name') from jsonb_array_elements(s) e)
                       = array[pg_temp.cname('l3'), pg_temp.cname('l4'), pg_temp.cname('l1')],
    'L1 the holdings list: a customer whose only holdings were Legacy months is not listed; one with vouchers handed over from a Legacy reward is: '
    || (select string_agg(e->>'customer_name', ', ') from jsonb_array_elements(s) e));
  perform pg_temp.ok((select (e->>'unlimited_active')::int = 1 and (e->>'unlimited_pending')::int = 0 and (e->>'unlimited_scheduled')::int = 0
                             and (e->>'unlimited_finished')::int = 0 and (e->>'current_unlimited_expiry')::date = public.sg_today() + 20
                        from jsonb_array_elements(s) e where e->>'customer_id' = pg_temp.id('l1')::text),
    'L2 the purchased unit counts; the running, waiting and booked Legacy months do not (the expiry shown is the unit''s)');
  perform pg_temp.ok((select (e->>'therapy_vouchers_issued')::int = 10 and (e->>'therapy_vouchers_remaining')::int = 10
                        from jsonb_array_elements(s) e where e->>'customer_id' = pg_temp.id('l3')::text)
      and (select (e->>'unlimited_active')::int = 1 from jsonb_array_elements(s) e where e->>'customer_id' = pg_temp.id('l4')::text),
    'L3 the 10 vouchers handed over from a Legacy reward still count as held; a period that is not Legacy still counts');
  s := pg_temp.call(pg_temp.id('stf'), format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'')::text from public.therapy_customer_summary(%L, 50, 0, true) x',
                                               '502R Holdings Legacy Only'))::jsonb;
  perform pg_temp.ok(s = '[]'::jsonb, 'L4 nor under "active only"');

  d := pg_temp.call(pg_temp.id('stf'), format('select public.therapy_customer_detail(%L::uuid)::text', pg_temp.id('l1')))::jsonb;
  perform pg_temp.ok(jsonb_array_length(d->'unlimited') = 1 and d->'unlimited'->0->>'kind' = 'purchased'
      and d->'unlimited'->0->>'entitlement_no' = '502R-' || pg_temp.txt('sfx') || '-L1_U' and d->'pending' = '[]'::jsonb,
    'L5 the card''s detail: the periods list holds the purchased unit alone; nothing Legacy is waiting');
  d := pg_temp.call(pg_temp.id('stf'), format('select public.therapy_customer_detail(%L::uuid)::text', pg_temp.id('l3')))::jsonb;
  perform pg_temp.ok(jsonb_array_length(d->'vouchers') = 1 and d->'vouchers'->0->>'source' = 'Earlier reward'
      and d->'vouchers'->0->>'source_type' = 'legacy_entitlement' and (d->'vouchers'->0->>'remaining')::int = 10 and d->'unlimited' = '[]'::jsonb,
    'L6 vouchers handed over from a Legacy reward: listed as "Earlier reward", 10 left');
  d := pg_temp.call(pg_temp.id('stf'), format('select public.therapy_customer_detail(%L::uuid)::text', pg_temp.id('l4')))::jsonb;
  perform pg_temp.ok(d->'unlimited'->0->>'source' = 'Earlier reward' and d->'unlimited'->0->>'entitlement_no' = '502R-' || pg_temp.txt('sfx') || '-L4_A',
    'L7 a period that is not a purchase reads "Earlier reward"');
  d := pg_temp.call(pg_temp.id('stf'), format('select public.therapy_customer_detail(%L::uuid)::text', pg_temp.id('l5')))::jsonb;
  perform pg_temp.ok(jsonb_array_length(d->'pending') = 1 and d->'pending'->0->>'entitlement_no' = '502R-' || pg_temp.txt('sfx') || '-L5_A'
      and d->'unlimited' = '[]'::jsonb,
    'L8 waiting: the Credit Package reward, not the Legacy month or the affiliate''s vouchers');
  b := pg_temp.call(pg_temp.id('own'), format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'')::text from public.therapy_customer_voucher_balances(%L::uuid) x', pg_temp.id('l3')), 'server')::jsonb;
  perform pg_temp.ok(jsonb_array_length(b) = 1 and b->0->>'source_label' = 'Earlier reward' and b->0->>'source_type' = 'legacy_entitlement'
      and (b->0->>'remaining_qty')::int = 10 and (b->0->>'issued_qty')::int = 10,
    'L9 therapy_customer_voucher_balances: "Earlier reward", 10 issued, 10 left');
  perform pg_temp.ok(strpos(pg_get_functiondef('public.therapy_customer_detail(uuid)'::regprocedure), 'Legacy qualification') = 0
      and strpos(pg_get_functiondef('public.therapy_customer_voucher_balances(uuid)'::regprocedure), 'Legacy qualification') = 0,
    'L10 neither function says "Legacy qualification" any more');
end $t$;

-- ═════ M The refund guard is gone ═════
do $t$
declare own uuid := pg_temp.id('own'); t text; inv uuid; item uuid; pay uuid; mv uuid; v uuid; fp text; aff uuid;
begin
  perform pg_temp.cust('mc', '502R Refund Customer');
  insert into public.payment_methods (name, is_active) values ('502R Cash ' || pg_temp.txt('sfx'), true) returning id into v;
  perform pg_temp.put('m_cash', v);
  insert into public.products (name, sku) values ('502R Massage Oil ' || pg_temp.txt('sfx'), '502R-OIL-' || pg_temp.txt('sfx')) returning id into v;
  perform pg_temp.put('m_product', v);
  insert into public.store_inventory (store_id, product_id, current_qty) values (pg_temp.id('m'), v, 10);
  perform pg_temp.call(own, format('select public.set_product_prices(%L::uuid, %L::uuid, 100, 100, %L)::text', pg_temp.id('m'), v, 'available'));
  -- Two sales on one day, made and paid through the invoice form and the Pay dialog.
  foreach t in array array['m1', 'm2'] loop
    inv := pg_temp.call(own, format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
      pg_temp.id('m'), pg_temp.id('mc'), jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.id('m_product'), 'quantity', 1)),
      jsonb_build_object('business_date', public.sg_today()::text)))::uuid;
    perform pg_temp.put(t, inv);
    perform pg_temp.call(own, format('select public.record_invoice_settlement(%L::uuid, %L::jsonb, %L::uuid)::text', inv,
      jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.id('m_cash'),
        'amount', (select total_amount from public.invoices where id = inv), 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb),
      gen_random_uuid()));
  end loop;
  -- That day earned a free month, which was used (as the S$1,131 invoice's day did).
  perform pg_temp.ent('m_month', 'mc', 'm', 'customer', 'unlimited', 'expired', p_act => public.sg_today() - 60, p_exp => public.sg_today() - 30,
                      p_group => public.legacy_qualification_group(pg_temp.id('mc'), pg_temp.id('m'), public.sg_today()));
  perform pg_temp.ok((select status::text from public.invoices where id = pg_temp.id('m1')) = 'paid'
      and not exists (select 1 from public.therapy_entitlements e where e.customer_id = pg_temp.id('mc') and e.id <> pg_temp.id('m_month')),
    'M1 the two sales are made and paid through the invoice form and the Pay dialog; no reward row was written for the customer');
  perform pg_temp.ok(not exists (select 1 from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'legacy_refund_guard')
      and not exists (select 1 from pg_trigger where tgfoid = 'public.trg_legacy_refund_guard()'::regprocedure),
    'M2 the trigger legacy_refund_guard is gone, and nothing else calls its function');
  t := pg_temp.try_as(null, format('select public.assert_legacy_refund_allowed(%L::uuid)::text', pg_temp.id('m1')), 'server');
  perform pg_temp.ok(t = 'P0001:' || pg_temp.txt('c_guard_says'), 'M3 the day is one the guard refused: its check, called directly, still says: ' || t);
  fp := pg_temp.legacy_rows();
  inv := pg_temp.id('m1');
  select id into item from public.invoice_items where invoice_id = inv;
  select id into pay from public.invoice_payments where invoice_id = inv;
  select id into mv from public.stock_movements where invoice_id = inv and movement_type::text = 'store_sale';
  t := pg_temp.try_as(own, format('select public.refund_invoice_recorded(%L::uuid, %L::jsonb, %L::jsonb, %L::jsonb, %L, %L::uuid)::text', inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', 100)), jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 100)),
    jsonb_build_array(jsonb_build_object('movement_id', mv, 'not_returned_quantity', 1)), '502R check: refund', gen_random_uuid()));
  perform pg_temp.ok(t like 'ok:%' and (select status::text from public.invoices where id = inv) = 'refunded',
    'M4 an Owner refunds a sale from that day through the Refund dialog: accepted: ' || left(t, 80));
  perform pg_temp.ok(pg_temp.legacy_rows() = fp and (select status from public.therapy_entitlements where id = pg_temp.id('m_month')) = 'expired',
    'M5 the month already used is not taken back; no Legacy reward or invoice link changed');
  t := pg_temp.try_as(null, format('select public.assert_legacy_refund_allowed(%L::uuid)::text', inv), 'server');
  perform pg_temp.ok(t = 'P0001:' || pg_temp.txt('c_guard_says'), 'M6 assert_legacy_refund_allowed, called by the database owner, still refuses as before: ' || t);
  -- Its other refusal: an affiliate's reward voucher from that day already redeemed.
  aff := pg_temp.cust('m_aff', '502R Refund Affiliate');
  perform pg_temp.cust('mc2', '502R Refund Referred');
  insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount, paid_at, affiliate_snapshot_customer_id)
  values ('502R-' || pg_temp.txt('sfx') || '-MA', pg_temp.id('m'), pg_temp.id('mc2'), own, 'paid', 1000, 1000, 1000, now(), aff) returning id into v;
  perform pg_temp.put('ma', v);
  perform pg_temp.ent('m_aff_r', 'm_aff', 'm', 'affiliate', 'voucher', 'active',
                      p_group => md5('legacy_aff:' || aff::text || ':' || public.sg_today()::text)::uuid);
  perform pg_temp.held('m_aff_r', 1, 'redeemed');
  t := pg_temp.try_as(null, format('select public.assert_legacy_refund_allowed(%L::uuid)::text', v), 'server');
  perform pg_temp.ok(t = 'P0001:This invoice cannot be refunded: an Affiliate reward voucher earned from that day has already been redeemed.',
    'M7 and its other refusal, as before: ' || t);
  perform pg_temp.ok(pg_temp.md5_of('assert_legacy_refund_allowed(uuid)') = '8c4ec71df7ab88e6ea90590bff3133fd'
      and pg_temp.md5_of('trg_legacy_refund_guard()') = '089965ef41a18fe3c54dd622e743075a'
      and pg_temp.acl_of('assert_legacy_refund_allowed(uuid)') = 'postgres=X/postgres,service_role=X/postgres'
      and pg_temp.acl_of('trg_legacy_refund_guard()') = 'postgres=X/postgres,service_role=X/postgres',
    'M8 both functions stay as they were (the UNDO attaches the trigger again; the refunds repair calls the check)');
end $t$;

-- ═════ N Rights ═════
-- A reward writer's insert into therapy_entitlements: its columns, and its values split at the
-- commas that separate them (not those inside brackets, quotes or a comment).
create function pg_temp.split_top(p text) returns text[] language plpgsql immutable as $f$
declare out text[] := '{}'; buf text := ''; depth int := 0; q boolean := false; c text; i int := 1; n int := length(p);
begin
  while i <= n loop
    c := substr(p, i, 1);
    if q then
      buf := buf || c;
      if c = '''' then q := false; end if;
    elsif c = '''' then q := true; buf := buf || c;
    elsif c = '-' and substr(p, i, 2) = '--' then
      while i <= n and substr(p, i, 1) <> E'\n' loop i := i + 1; end loop;
      buf := buf || ' ';
      continue;
    elsif c = '(' then depth := depth + 1; buf := buf || c;
    elsif c = ')' then depth := depth - 1; buf := buf || c;
    elsif c = ',' and depth = 0 then out := out || btrim(buf, E' \n\t\r'); buf := '';
    else buf := buf || c;
    end if;
    i := i + 1;
  end loop;
  return out || btrim(buf, E' \n\t\r');
end $f$;
create function pg_temp.te_inserts(p_def text) returns table(cols text[], vals text[]) language plpgsql as $f$
declare
  s text := p_def; pat text := 'insert\s+into\s+(?:public\.)?therapy_entitlements\s*\(([^)]*)\)\s*(values\s*\(|select\M)';
  m text[]; rest text; i int; depth int; q boolean; c text; buf text;
begin
  loop
    m := regexp_match(s, pat, 'i');
    exit when m is null;
    rest := substr(s, regexp_instr(s, pat, 1, 1, 1, 'i'));
    cols := (select array_agg(lower(btrim(x, E' \n\t\r')) order by n) from unnest(string_to_array(m[1], ',')) with ordinality u(x, n));
    if lower(m[2]) like 'select%' then
      vals := null;   -- insert ... select: its values cannot be read here, so it fails the check
      return next; s := rest; continue;
    end if;
    depth := 1; q := false; buf := ''; i := 1;
    while i <= length(rest) loop
      c := substr(rest, i, 1);
      if q then buf := buf || c; if c = '''' then q := false; end if;
      elsif c = '''' then q := true; buf := buf || c;
      elsif c = '-' and substr(rest, i, 2) = '--' then
        while i <= length(rest) and substr(rest, i, 1) <> E'\n' loop buf := buf || substr(rest, i, 1); i := i + 1; end loop;
        continue;
      elsif c = '(' then depth := depth + 1; buf := buf || c;
      elsif c = ')' then depth := depth - 1; exit when depth = 0; buf := buf || c;
      else buf := buf || c;
      end if;
      i := i + 1;
    end loop;
    vals := pg_temp.split_top(buf);
    return next;
    s := substr(rest, i + 1);
  end loop;
end $f$;
-- The earner_kind a writer gives: its literal, or why it gives none.
create function pg_temp.earner_of(p_cols text[], p_vals text[]) returns text language sql immutable as $f$
  select case when p_vals is null then '(insert ... select)'
              when array_position(p_cols, 'earner_kind') is null then '(no earner_kind)'
              when cardinality(p_cols) <> cardinality(p_vals) then '(columns and values do not match)'
              when p_vals[array_position(p_cols, 'earner_kind')] ~ '^''[a-z_]+''$'
                then btrim(p_vals[array_position(p_cols, 'earner_kind')], '''')
              else '(not a literal: ' || p_vals[array_position(p_cols, 'earner_kind')] || ')' end $f$;
do $t$
declare own uuid := pg_temp.id('own'); rec record; t text; bad text := ''; kept text[]; s text; writers text;
begin
  -- N1-N4 The 13 functions only Legacy used.
  for rec in select sig from t502r_revoked order by sig loop
    if has_function_privilege('authenticated', 'public.' || rec.sig, 'execute') then bad := bad || ' authenticated:' || rec.sig; end if;
    if has_function_privilege('anon', 'public.' || rec.sig, 'execute') then bad := bad || ' anon:' || rec.sig; end if;
    if not has_function_privilege('service_role', 'public.' || rec.sig, 'execute') then bad := bad || ' service_role:' || rec.sig; end if;
    if pg_temp.acl_of(rec.sig) <> 'postgres=X/postgres,service_role=X/postgres' then bad := bad || ' acl:' || rec.sig; end if;
    -- Called by a signed-in Owner, with nothing in its arguments: refused before it runs. The
    -- call is the query's own answer and its arguments are sub-selects, so the planner can
    -- neither drop it nor work it out in advance.
    t := pg_temp.try_as(own, format('select public.%s(%s)::text', split_part(rec.sig, '(', 1),
           (select coalesce(string_agg('(select null::' || a || ')', ', ' order by ord), '')
              from unnest(string_to_array(nullif(rtrim(split_part(rec.sig, '(', 2), ')'), ''), ',')) with ordinality u(a, ord))));
    if t not like '42501:permission denied for function ' || split_part(rec.sig, '(', 1) then bad := bad || ' call:' || rec.sig || '=' || t; end if;
  end loop;
  perform pg_temp.ok(bad = '' and (select count(*) from t502r_revoked) = 13,
    'N1 none of the 13 can be run by a signed-in login or by anon; each refuses a signed-in Owner with 42501; the service role keeps all 13; their rights are postgres and service_role alone' || bad);
  t := pg_temp.try_as(null, 'select public.legacy_setup_status()::text', 'service');
  s := pg_temp.try_as(null, 'select count(*)::text from public.therapy_reward_mapping_preview()', 'service');
  perform pg_temp.ok(t like 'ok:%' and s like 'ok:%', 'N2 the service role still runs them: ' || left(t, 60) || ' / ' || s);
  -- N3 Kept for signed-in logins: shared, not Legacy, and the pages' own.
  kept := array['legacy_reward_voucher_options(uuid)', 'set_catalogue_reward(text,uuid,boolean)', 'therapy_list_page(text,text,text,integer,integer)',
                'entitlement_voucher_state(uuid)', 'claim_entitlement_vouchers(uuid,jsonb,text)', 'credit_package_reward_group(uuid)',
                'invoice_credit_reward_entitlements(uuid,uuid)', 'resolve_invoice_credit_rewards(uuid,text,uuid,boolean,uuid)',
                'invoice_benefit_review_options(uuid)', 'customer_overview(uuid)', 'report_therapy()',
                'delete_customer(uuid,text,text)', 'dashboard_alerts_summary()', 'therapy_customer_summary(text,integer,integer,boolean)',
                'therapy_customer_detail(uuid)', 'upsert_credit_package(uuid,text,numeric,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,numeric,text,uuid[],uuid[],boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,numeric)',
                'upsert_premium_bundle(uuid,text,numeric,numeric,numeric,integer,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,text,uuid[],uuid[])'];
  bad := '';
  foreach s in array kept loop
    if pg_temp.acl_of(s) <> 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres' then bad := bad || ' ' || s || '=' || pg_temp.acl_of(s); end if;
  end loop;
  foreach s in array array['trg_create_therapy_on_paid()', 'therapy_customer_voucher_balances(uuid)', 'assert_invoice_credit_source_evidence(uuid,uuid)',
                           'run_therapy_status_refresh()', 'assert_legacy_refund_allowed(uuid)', 'trg_legacy_refund_guard()'] loop
    if pg_temp.acl_of(s) <> 'postgres=X/postgres,service_role=X/postgres' then bad := bad || ' ' || s || '=' || pg_temp.acl_of(s); end if;
  end loop;
  perform pg_temp.ok(bad = '', 'N3 the shared functions and the pages'' own keep their rights (signed-in logins, the owner, the service role; anon none); the server''s stay the server''s' || bad);
  t := pg_temp.call(pg_temp.id('stf'), format('select coalesce(jsonb_agg(x.name order by x.name), ''[]'')::text from public.legacy_reward_voucher_options(%L::uuid) x
                                                where x.name like ''502R Voucher%%''', pg_temp.id('g')));
  perform pg_temp.ok(t::jsonb = jsonb_build_array('502R Voucher One ' || pg_temp.txt('sfx'), '502R Voucher Two ' || pg_temp.txt('sfx')),
    'N4 the till''s Premium Bundle voucher picker still works for staff: ' || t);
  -- N5 The 4 retired recounts: the server's only, and they say not to run them.
  perform pg_temp.ok(not exists (select 1 from t502r_retired x
                                  where pg_temp.acl_of(x.sig) <> 'postgres=X/postgres,service_role=X/postgres'
                                     or obj_description(to_regprocedure('public.' || x.sig), 'pg_proc') is distinct from pg_temp.txt('c_note')),
    'N5 the 4 retired recounts: the server''s only, each commented "' || pg_temp.txt('c_note') || '"');
  perform pg_temp.ok(pg_temp.md5_of('recompute_legacy_qualification(uuid,uuid,date)') = '588fdaff42b49df16a051af839a2ff38'
      and pg_temp.md5_of('recompute_affiliate_legacy_qualification(uuid,date)') = '9b94f6008d92d15a61a3286672fdac00'
      and pg_temp.md5_of('recompute_affiliates_for_customer_day(uuid,date)') = '438e902c16c59d7445f4a80b18a5e445'
      and pg_temp.md5_of('recompute_legacy_qualification_for_invoice(uuid)') = 'cef49d3f382dffbffccf73d9eb6ea670',
    'N6 a comment does not change their text (md5s as before 502)');

  -- N7 Every function that writes a reward, other than the two retired recounts,
  -- names earner_kind with a literal that is not Legacy's, so no new reward can fall into the
  -- column's default ('customer') and vanish from Vouchers to hand over, the Customers page,
  -- Reports and the delete check.
  bad := ''; writers := '';
  for rec in select p.oid::regprocedure::text sig, x.cols, x.vals
             from pg_proc p, lateral pg_temp.te_inserts(pg_get_functiondef(p.oid)) x
            where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
              and pg_get_functiondef(p.oid) ~* 'insert\s+into\s+(public\.)?therapy_entitlements\M'
              and p.oid::regprocedure::text not in ('recompute_legacy_qualification(uuid,uuid,date)', 'recompute_affiliate_legacy_qualification(uuid,date)')
            order by 1 loop
    t := pg_temp.earner_of(rec.cols, rec.vals);
    writers := writers || ' ' || split_part(rec.sig, '(', 1) || '=' || t;
    if t like '(%' or t in ('customer', 'affiliate') then bad := bad || ' ' || rec.sig || ': ' || t; end if;
  end loop;
  perform pg_temp.ok(bad = '' and writers ~ 'issue_credit_package=credit_package' and writers ~ 'issue_credit_package_invoice_item=credit_package'
      and writers ~ 'sell_premium_bundle=premium_bundle' and writers ~ 'issue_premium_bundle_invoice_item=premium_bundle'
      and writers ~ 'choose_therapy_benefit=therapy_package' and writers ~ 'switch_therapy_benefit=therapy_package',
    'N7 every reward writer but the two retired recounts names earner_kind, and not as Legacy:' || writers || bad);
  perform pg_temp.ok((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                        and pg_get_functiondef(p.oid) ~* 'insert\s+into\s+(public\.)?therapy_entitlements\M') = 8
      and (select count(*) from pg_proc p, lateral pg_temp.te_inserts(pg_get_functiondef(p.oid)) x where p.pronamespace = 'public'::regnamespace
             and pg_get_functiondef(p.oid) ~* 'insert\s+into\s+(public\.)?therapy_entitlements\M') = 8,
    'N8 (8 functions write a reward, one insert each: the 6 above and the 2 retired recounts)');
  -- The check catches what it is for: the two retired recounts fail it.
  perform pg_temp.ok((select pg_temp.earner_of(x.cols, x.vals) from pg_temp.te_inserts(pg_get_functiondef('public.recompute_legacy_qualification(uuid,uuid,date)'::regprocedure)) x) = '(no earner_kind)'
      and (select pg_temp.earner_of(x.cols, x.vals) from pg_temp.te_inserts(pg_get_functiondef('public.recompute_affiliate_legacy_qualification(uuid,date)'::regprocedure)) x) = 'affiliate'
      and (select pg_temp.earner_of(x.cols, x.vals) from pg_temp.te_inserts('insert into therapy_entitlements (entitlement_no, earner_kind) select ''x'', ''credit_package''') x) = '(insert ... select)'
      and (select pg_temp.earner_of(x.cols, x.vals) from pg_temp.te_inserts('insert into public.therapy_entitlements (a, earner_kind) values (f(1, ''a,b''), v_kind)') x) = '(not a literal: v_kind)',
    'N9 (the check catches a writer that leaves earner_kind to its default, one that writes Legacy''s, an insert ... select, and a value that is not a literal)');
end $t$;

-- ═════ O "Re-check paid days" ═════
do $t$
declare own uuid := pg_temp.id('own'); t text; snap text;
begin
  perform pg_temp.cust('oc', '502R Recheck Customer');
  -- A rule in reach at this store (S$100 a month) and a S$500 day: the old re-check would earn 5 months.
  perform pg_temp.put('o_rule', pg_temp.call(own, format('select public.upsert_legacy_rule(null, %L::uuid, ''502R O rule'', 100, ''unlimited'', 1, null, 365, true, %L::date, ''customer'')::text',
                                                       pg_temp.id('o'), public.sg_today() - 1), 'server')::uuid);
  perform pg_temp.inv('o1', 'o', 'oc', 'paid', 500);
  snap := (select md5(concat_ws('|', (select count(*) from public.therapy_entitlements), (select count(*) from public.therapy_entitlement_invoices),
                                (select count(*) from public.audit_logs),
                                (select string_agg(concat_ws(',', i.id, i.affiliate_snapshot_customer_id, i.affiliate_active_on_paid), ';' order by i.id) from public.invoices i))));
  t := pg_temp.try_as(own, 'select public.backfill_legacy_qualification(null, null, null)::text', 'server');
  perform pg_temp.ok(t = 'P0001:Legacy Therapy has been retired: paid days are no longer re-checked for rewards.', 'O1 run by the database owner for an Owner: refused, in plain words: ' || t);
  t := pg_temp.try_as(null, format('select public.backfill_legacy_qualification(%L::date, %L::date, %L::uuid)::text', public.sg_today(), public.sg_today(), pg_temp.id('o')), 'server');
  perform pg_temp.ok(t = 'P0001:Legacy Therapy has been retired: paid days are no longer re-checked for rewards.', 'O2 with no one named, for one store and day: the same: ' || t);
  t := pg_temp.try_as(own, 'select public.backfill_legacy_qualification(null, null, null)::text');
  perform pg_temp.ok(t = '42501:permission denied for function backfill_legacy_qualification', 'O3 a signed-in Owner: refused (42501): ' || t);
  perform pg_temp.ok(snap = (select md5(concat_ws('|', (select count(*) from public.therapy_entitlements), (select count(*) from public.therapy_entitlement_invoices),
                                (select count(*) from public.audit_logs),
                                (select string_agg(concat_ws(',', i.id, i.affiliate_snapshot_customer_id, i.affiliate_active_on_paid), ';' order by i.id) from public.invoices i)))),
    'O4 nothing was written: no reward, invoice link, Audit Log row or affiliate record (U shows the old one would have earned)');
  -- The rule off again, as the go-live script switches them off.
  perform pg_temp.call(own, format('select public.upsert_legacy_rule(%L::uuid, %L::uuid, ''502R O rule'', 100, ''unlimited'', 1, null, 365, false, null, ''customer'')::text',
                                   pg_temp.id('o_rule'), pg_temp.id('o')), 'server');
end $t$;

-- ═════ P Premium Bundles: a blank threshold ═════
create function pg_temp.bundle(p_id uuid, p_name text, p_payment numeric, p_threshold numeric default null) returns text language sql as $f$
  select pg_temp.try_as(pg_temp.id('own'), format('select public.upsert_premium_bundle(%L::uuid, %L, %s, %s, 0, null, %s, true, null, null, ''third_party'', true, null, null, null, null, null, null)::text',
                        p_id, p_name, p_payment, p_payment, coalesce(p_threshold::text, 'null'))) $f$;
-- A bundle the form saved: its free vouchers and threshold, as [vouchers, threshold].
create function pg_temp.bundle_row(p_t text) returns jsonb language sql as $f$
  select case when p_t like 'ok:%' then (select jsonb_build_array(free_voucher_qty, reward_qualifying_amount)
                                           from public.premium_bundles where id = substr(p_t, 4)::uuid) end $f$;
do $t$
declare own uuid := pg_temp.id('own'); rule uuid; aff uuid; t text; b15 text; b30 text;
begin
  -- The local copy's own customer rules, if any, off (the go-live script switches production's off).
  for t in select r.id::text from public.therapy_package_rules r where r.is_active and r.deleted_at is null and coalesce(r.applies_to, 'customer') = 'customer' loop
    perform pg_temp.call(own, format('select public.upsert_legacy_rule(r.id, r.store_id, r.name, r.qualifying_amount, r.entitlement_kind, r.duration_months, r.voucher_qty, r.activation_deadline_days, false, null, r.applies_to)::text
                                       from public.therapy_package_rules r where r.id = %L::uuid', t), 'server');
  end loop;
  -- P1 A rule still on: a blank threshold takes the cheapest, as now.
  rule := pg_temp.call(own, 'select public.upsert_legacy_rule(null, null, ''502R P rule'', 500, ''unlimited'', 1, null, 365, true, null, ''customer'')::text', 'server')::uuid;
  t := pg_temp.bundle(null, '502R Bundle Rule ' || pg_temp.txt('sfx'), 15000);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.bundle_row(t) = '[300, 500]', 'P1 with a S$500 rule on, a S$15,000 bundle with a blank threshold gives 300 vouchers at S$500, as now: ' || coalesce(pg_temp.bundle_row(t)::text, t));
  -- P2 The rules off (the go-live script's way): S$994.
  perform pg_temp.call(own, format('select public.upsert_legacy_rule(%L::uuid, null, ''502R P rule'', 500, ''unlimited'', 1, null, 365, false, null, ''customer'')::text', rule), 'server');
  -- An affiliate's rule never counted for bundles.
  aff := pg_temp.call(own, 'select public.upsert_legacy_rule(null, null, ''502R P affiliate rule'', 100, ''voucher'', null, 10, 365, true, null, ''affiliate'')::text', 'server')::uuid;
  perform pg_temp.ok(not exists (select 1 from public.therapy_package_rules where is_active and deleted_at is null and coalesce(applies_to, 'customer') = 'customer'),
    'P2 no customer rule is on');
  b15 := pg_temp.bundle(null, '502R Bundle 15k ' || pg_temp.txt('sfx'), 15000);
  b30 := pg_temp.bundle(null, '502R Bundle 30k ' || pg_temp.txt('sfx'), 30000);
  perform pg_temp.ok(b15 like 'ok:%' and pg_temp.bundle_row(b15) = '[150, 994]', 'P3 S$15,000 with a blank threshold: 150 vouchers at S$994, no error: ' || coalesce(pg_temp.bundle_row(b15)::text, b15));
  perform pg_temp.ok(b30 like 'ok:%' and pg_temp.bundle_row(b30) = '[300, 994]', 'P4 S$30,000: 300 vouchers at S$994: ' || coalesce(pg_temp.bundle_row(b30)::text, b30));
  t := pg_temp.bundle(null, '502R Bundle Own Threshold ' || pg_temp.txt('sfx'), 15000, 1500);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.bundle_row(t) = '[100, 1500]', 'P5 a threshold given is kept: S$1,500 gives 100: ' || coalesce(pg_temp.bundle_row(t)::text, t));
  t := pg_temp.bundle(substr(b15, 4)::uuid, '502R Bundle 15k ' || pg_temp.txt('sfx'), 15000, 1500);
  t := pg_temp.bundle(substr(b15, 4)::uuid, '502R Bundle 15k ' || pg_temp.txt('sfx'), 15000);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.bundle_row(b15) = '[150, 994]', 'P6 an edit that blanks the threshold falls back to S$994 too: ' || coalesce(pg_temp.bundle_row(b15)::text, t));
  t := pg_temp.try_as(own, format('select public.set_catalogue_reward(''premium_bundle'', %L::uuid, false)::text', substr(b15, 4)))
       || ' / ' || pg_temp.try_as(own, format('select public.set_catalogue_reward(''premium_bundle'', %L::uuid, true)::text', substr(b15, 4)));
  perform pg_temp.ok(t = 'ok: / ok:' and (select grants_reward from public.premium_bundles where id = substr(b15, 4)::uuid),
    'P7 a bundle''s free vouchers can still be switched off and on: ' || t);
  perform pg_temp.ok(pg_temp.md5_of('upsert_premium_bundle(uuid,text,numeric,numeric,numeric,integer,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,text,uuid[],uuid[])') = '2202746851bc5bdd424c1c52fda86056'
      and pg_temp.md5_of('premium_bundle_voucher_entitlement(numeric,numeric)') = '1267e4c36509e4af2662b2b8eb8ca633',
    'P8 the bundle form''s functions are as before 502');
  perform pg_temp.call(own, format('select public.upsert_legacy_rule(%L::uuid, null, ''502R P affiliate rule'', 100, ''voucher'', null, 10, 365, false, null, ''affiliate'')::text', aff), 'server');
end $t$;

-- ═════ Q The nightly job ═════
do $t$
declare r jsonb; fp text;
begin
  perform pg_temp.cust('q1', '502R Nightly One');
  perform pg_temp.cust('q2', '502R Nightly Two');
  perform pg_temp.cust('q3', '502R Nightly Three');
  perform pg_temp.cust('q4', '502R Nightly Four');
  perform pg_temp.inv('q1_s', 'q', 'q1', 'paid');
  perform pg_temp.inv('q2_s', 'q', 'q2', 'paid');
  perform pg_temp.inv('q3_s', 'q', 'q3', 'paid');
  perform pg_temp.inv('q4_s', 'q', 'q4', 'paid');
  -- Booked to start yesterday; ended yesterday; never started and its deadline was yesterday; not due.
  perform pg_temp.unit('q_u1', 'q1', 'q', 'q1_s', 'scheduled', public.sg_today() + 100, public.sg_today() - 1, public.sg_today() + 179);
  perform pg_temp.unit('q_u2', 'q2', 'q', 'q2_s', 'active', public.sg_today() + 100, public.sg_today() - 181, public.sg_today() - 1);
  perform pg_temp.unit('q_u3', 'q3', 'q', 'q3_s', 'pending_activation', public.sg_today() - 1);
  perform pg_temp.unit('q_u4', 'q4', 'q', 'q4_s', 'pending_activation', public.sg_today() + 100);
  fp := pg_temp.legacy_rows();
  -- Run as pg_cron runs it: the database owner, no one signed in.
  r := pg_temp.call(null, 'select public.run_therapy_status_refresh()::text', 'server')::jsonb;
  perform pg_temp.ok((select array_agg(k order by k) from jsonb_object_keys(r) k) = array['legacy_expired', 'on', 'purchased_changed', 'purchased_left']
      and (r->>'on')::date = public.sg_today() and jsonb_typeof(r->'purchased_left') = 'array',
    'Q1 the nightly job answers with its four keys, today''s date: ' || r::text);
  perform pg_temp.ok((select status from public.purchased_therapy_entitlements where id = pg_temp.id('q_u1')) = 'active'
      and (select status from public.purchased_therapy_entitlements where id = pg_temp.id('q_u2')) = 'expired'
      and (select status from public.purchased_therapy_entitlements where id = pg_temp.id('q_u3')) = 'expired'
      and (select status from public.purchased_therapy_entitlements where id = pg_temp.id('q_u4')) = 'pending_activation'
      and (r->>'purchased_changed')::int >= 3
      and not (r->'purchased_left' ?| array['502R-' || pg_temp.txt('sfx') || '-Q_U1', '502R-' || pg_temp.txt('sfx') || '-Q_U2', '502R-' || pg_temp.txt('sfx') || '-Q_U3']),
    'Q2 purchased units move as before: booked yesterday starts, ended yesterday expires, past its deadline expires, the rest stay');
  perform pg_temp.ok(pg_temp.legacy_rows() = fp, 'Q3 none of the Legacy rewards made here changed (waiting, booked, running, used, cancelled, handed over), nor their invoice links or vouchers');
  perform pg_temp.ok(pg_temp.md5_of('run_therapy_status_refresh()') = '0d10378270574e2ba7d15f9626b7300d'
      and pg_temp.md5_of('refresh_purchased_therapy_statuses()') = '0f9076a6456eaf7cdc995d5b7fbbb8d2'
      and pg_temp.md5_of('refresh_legacy_therapy_statuses()') = '6de4ab99525f70a282f2889b7694ac41',
    'Q4 the job''s three functions are as before 502');
  r := pg_temp.call(null, 'select public.run_therapy_status_refresh()::text', 'server')::jsonb;
  perform pg_temp.ok(pg_temp.legacy_rows() = fp and (select count(*) from public.purchased_therapy_entitlements
                                                      where id in (pg_temp.id('q_u1'), pg_temp.id('q_u2'), pg_temp.id('q_u3')) and status in ('active', 'expired')) = 3,
    'Q5 a second night moves nothing more of these');
end $t$;

-- ═════ U The UNDO ═════
do $u$
declare
  own uuid := pg_temp.id('own'); e text; st text; f text; t text; d text; p_with jsonb; p_without jsonb; a jsonb;
  v_trig_others text; v_expected_trig text; inv uuid; item uuid; pay uuid; mv uuid; n int;
begin
  -- U1 The NOTICE that the pages must already be reverted is printed by every run that passes its checks.
  perform pg_temp.ok(strpos(current_setting('t502r.undo'), 'raise notice ''UNDO 502: the pages must already be reverted') > 0
      and strpos(current_setting('t502r.undo'), 'raise notice ''UNDO 502: the pages must already be reverted') > strpos(current_setting('t502r.undo'), '-- 1. Checks')
      and strpos(current_setting('t502r.undo'), 'raise notice ''UNDO 502: the pages must already be reverted') < strpos(current_setting('t502r.undo'), '-- 2. Put back'),
    'U1 the UNDO prints that the pages must already be reverted, after its checks and before it changes anything');

  -- U2 A function that is not 502's version: refused, nothing changed.
  d := pg_get_functiondef('public.report_therapy()'::regprocedure);
  execute replace(d, '-- 366: only an Owner, Admin or Manager', '-- 366 (changed since 502): only an Owner, Admin or Manager');
  st := pg_temp.state();
  e := null;
  begin execute current_setting('t502r.undo'); exception when others then e := sqlerrm; end;
  perform pg_temp.ok(e like 'UNDO 502: public.report_therapy() is not 502''s version (md5 %); nothing changed', 'U2 a function changed since 502: refused: ' || coalesce(e, 'it ran'));
  perform pg_temp.ok(pg_temp.state() = st, 'U3 and nothing changed');
  execute d;
  perform pg_temp.ok(pg_temp.md5_of('report_therapy()') = 'f43af7b0f6a8a80054808ab6fb672d59', '(report_therapy is 502''s again)');

  -- U4 A reward still cancelled by the go-live script: refused, nothing changed.
  update public.therapy_entitlements set status = 'cancelled', revoked_at = now(), revoked_reason = pg_temp.txt('c_reason') where id = pg_temp.id('f_l1');
  st := pg_temp.state(); f := pg_temp.legacy_rows();
  e := null;
  begin execute current_setting('t502r.undo'); exception when others then e := sqlerrm; end;
  perform pg_temp.ok(e = 'UNDO 502: 1 reward(s) are still cancelled by the go-live script ("' || pg_temp.txt('c_reason')
                         || '"). Run scripts/therapy/undo-legacy-retired-golive-502.sql first; nothing changed.',
    'U4 while a reward is still cancelled by the go-live script: refused: ' || coalesce(e, 'it ran'));
  perform pg_temp.ok(pg_temp.state() = st and pg_temp.legacy_rows() = f, 'U5 and nothing changed');
  update public.therapy_entitlements set status = 'pending_activation', revoked_at = null, revoked_reason = null where id = pg_temp.id('f_l1');

  -- U6 The UNDO itself.
  p_with := pg_temp.purchased_all();
  v_trig_others := (select coalesce(string_agg(tg.tgname || ' ' || tg.tgenabled::text || ' ' || pg_get_triggerdef(tg.oid), E'\n' order by tg.tgname), '')
                      from pg_trigger tg where tg.tgrelid = 'public.invoices'::regclass and not tg.tgisinternal);
  -- What it should come back to: the same triggers with the guard in its place by name.
  v_expected_trig := (select string_agg(x, E'\n' order by split_part(x, ' ', 1) collate "C")
                        from (select unnest(string_to_array(v_trig_others, E'\n')) x
                              union all select 'legacy_refund_guard O ' || pg_temp.txt('c_guard')) y);
  perform set_config('client_min_messages', 'notice', true);
  execute current_setting('t502r.undo');
  perform set_config('client_min_messages', 'warning', true);
  perform pg_temp.ok(not exists (select 1 from t502r_fn x where pg_temp.md5_of(x.sig) is distinct from x.before_md5),
    'U6 the UNDO puts the 15 functions back to their text before 502 (BEFORE md5s)');
  perform pg_temp.ok((select pg_get_triggerdef(tg.oid) = pg_temp.txt('c_guard') and tg.tgenabled = 'O' and tg.tgfoid = 'public.trg_legacy_refund_guard()'::regprocedure
                        from pg_trigger tg where tg.tgrelid = 'public.invoices'::regclass and tg.tgname = 'legacy_refund_guard'),
    'U7 the refund guard is attached again, with its exact definition, on');
  perform pg_temp.ok(pg_temp.triggers() = v_expected_trig
      and ((select pre_trig from t502r_pre) is null or pg_temp.triggers() = (select pre_trig from t502r_pre)),
    'U8 every trigger on invoices is as before 502, the guard in its place among the BEFORE UPDATE ones (they run in name order): '
    || (select string_agg(tg.tgname, ', ' order by tg.tgname) from pg_trigger tg
         where tg.tgrelid = 'public.invoices'::regclass and not tg.tgisinternal and tg.tgtype & 2 = 2 and tg.tgtype & 16 = 16));
  perform pg_temp.ok(not exists (select 1 from t502r_revoked r where pg_temp.acl_of(r.sig) <> 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres')
      and not exists (select 1 from t502r_fn x where x.sig not in (select sig from t502r_revoked)
                        and pg_temp.acl_of(x.sig) is distinct from case when x.sig in ('trg_create_therapy_on_paid()', 'therapy_customer_voucher_balances(uuid)', 'assert_invoice_credit_source_evidence(uuid,uuid)')
                                                                        then 'postgres=X/postgres,service_role=X/postgres'
                                                                        else 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres' end),
    'U9 signed-in logins can call the 13 again; the other functions'' rights are as they were');
  perform pg_temp.ok(not exists (select 1 from t502r_retired r where obj_description(to_regprocedure('public.' || r.sig), 'pg_proc') is not null),
    'U10 the 4 recounts carry no comment again');
  if (select pre_state from t502r_pre) is not null then
    perform pg_temp.ok(pg_temp.state() = (select pre_state from t502r_pre), 'U11 every function, right, comment and trigger is exactly as before 502 was installed here');
  end if;
  -- What it does again (so the pages must be reverted first, as its NOTICE says).
  t := pg_temp.try_as(pg_temp.id('stf_f'), 'select public.therapy_list_page(''vouchers'')::text');
  a := pg_temp.list(pg_temp.id('stf_f'), 'legacy', null, 'all');
  perform pg_temp.ok(t = 'P0001:Unknown list: vouchers (purchased or legacy)'
      and (select count(*) from jsonb_array_elements(a->'rows') r where r->>'earner_kind' in ('customer', 'affiliate')) = 8,
    'U12 after it, the new page''s list is refused again (' || t || ') and the old one lists the 8 Legacy rewards again');
  p_without := pg_temp.purchased_all();
  perform pg_temp.ok(p_with = p_without, 'U13 the Purchased list is the same with 502 and without it, on the same units');
  a := pg_temp.call(pg_temp.id('mgr_k'), 'select public.dashboard_alerts_summary()::text')::jsonb;
  perform pg_temp.ok((a->'sales'->>'holding_benefits')::int = 7
      and a->'sales'->'invoice_nos' = (select jsonb_agg(x order by x) from unnest(array[pg_temp.inv_no('k1'), pg_temp.inv_no('k2'), pg_temp.inv_no('k3'), pg_temp.inv_no('k4'),
                                                                                   pg_temp.inv_no('k5'), pg_temp.inv_no('k6'), pg_temp.inv_no('k7')]) x),
    'U14 the Dashboard counts the 3 sales held through a Legacy reward again, the 4 Credit Package ones as with 502 (K1)');
  t := pg_temp.del('fc4');
  perform pg_temp.ok(t = 'P0001:This customer has 1 legacy therapy entitlement(s) still open. Settle them first.' and not pg_temp.gone('fc4'),
    'U15 a customer with Legacy rewards cannot be deleted again: ' || t);
  -- The second sale of M's day: the guard refuses its refund again.
  inv := pg_temp.id('m2');
  select id into item from public.invoice_items where invoice_id = inv;
  select id into pay from public.invoice_payments where invoice_id = inv;
  select id into mv from public.stock_movements where invoice_id = inv and movement_type::text = 'store_sale';
  t := pg_temp.try_as(own, format('select public.refund_invoice_recorded(%L::uuid, %L::jsonb, %L::jsonb, %L::jsonb, %L, %L::uuid)::text', inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', 100)), jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 100)),
    jsonb_build_array(jsonb_build_object('movement_id', mv, 'not_returned_quantity', 1)), '502R check: refund', gen_random_uuid()));
  perform pg_temp.ok(t = 'P0001:' || pg_temp.txt('c_guard_says') and (select status::text from public.invoices where id = inv) = 'paid',
    'U16 the refund guard refuses a refund from that day again (so M4 was 502''s doing): ' || t);
  -- "Re-check paid days" would have earned on O's day (undone straight away).
  t := null;
  begin
    perform pg_temp.call(own, format('select public.upsert_legacy_rule(%L::uuid, %L::uuid, ''502R O rule'', 100, ''unlimited'', 1, null, 365, true, null, ''customer'')::text',
                                     pg_temp.id('o_rule'), pg_temp.id('o')), 'server');
    t := pg_temp.call(own, format('select public.backfill_legacy_qualification(null, null, %L::uuid)::text', pg_temp.id('o')), 'server');
    n := (select count(*) from public.therapy_entitlements where customer_id = pg_temp.id('oc'));
    raise exception using errcode = 'T5021';
  exception when sqlstate 'T5021' then null;
  end;
  perform pg_temp.ok((t::jsonb->>'customer_created')::int = 5 and n = 5
      and not exists (select 1 from public.therapy_entitlements where customer_id = pg_temp.id('oc')),
    'U17 the re-check put back would have earned 5 months on O''s S$500 day (so O4''s "nothing written" means something; undone): ' || coalesce(t, 'nothing'));

  -- U18 A second UNDO: refused, nothing changed.
  st := pg_temp.state();
  e := null;
  begin execute current_setting('t502r.undo'); exception when others then e := sqlerrm; end;
  perform pg_temp.ok(e like 'UNDO 502: public.trg_create_therapy_on_paid() is not 502''s version (md5 012ae4e305b9870fa5596f740c0427b9); nothing changed',
    'U18 a second UNDO refuses: ' || coalesce(e, 'it ran'));
  perform pg_temp.ok(pg_temp.state() = st, 'U19 and changes nothing');

  -- U20 502 again after the UNDO: the same as after the first install.
  p_without := pg_temp.purchased_all();
  execute current_setting('t502r.mig');
  perform pg_temp.ok(pg_temp.state() = (select post_state from t502r_post) and pg_temp.triggers() = (select post_trig from t502r_post),
    'U20 502 installed again after the UNDO: every function, right, comment and trigger as after the first install');
  perform pg_temp.ok(pg_temp.purchased_all() = p_without, 'U21 the Purchased list is the same before and after installing 502');
  a := pg_temp.call(pg_temp.id('mgr_k'), 'select public.dashboard_alerts_summary()::text')::jsonb;
  perform pg_temp.ok((a->'sales'->>'holding_benefits')::int = 4 and pg_temp.list(pg_temp.id('stf_f'), 'vouchers', null, 'all')->>'total' = '7',
    'U22 and the pages read as with 502 again (the Dashboard counts 4; Vouchers to hand over lists 7)');
end $u$;

-- ═════ Result ═════
do $res$
declare f int; n int;
begin
  select count(*) filter (where not ok), count(*) into f, n from t502r_res;
  if f > 0 then raise exception '% of % checks failed: %', f, n, (select string_agg(label, ' | ' order by t502r_res.n) from t502r_res where not ok); end if;
  raise warning 'PASS all % checks', n;
end $res$;
rollback;
