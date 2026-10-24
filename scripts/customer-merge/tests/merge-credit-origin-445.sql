-- Credit carried over in a customer merge stays the credit it was (445; the
-- Owner's answer of 21 Oct 2026, CREDIT-SPLIT-14).
--
-- The record that goes (Mike) holds Credit Package Paid (partly taken back
-- by a part refund) and Bonus, Premium Bundle Paid and Bonus, a Legacy lot
-- linked to his bundle line (credit_package_progress_lots, as 443's
-- CREDIT-SPLIT-12 lots are), Paid credit released by a part-paid package
-- (credit_package_progress_lots, 356), credit moved to him from another
-- customer's package (Move, 186), opening balances (Paid, Legacy) and Adjust
-- credit (Bonus, Promotional, Exchange), and a second bundle whose Bonus an
-- Owner moved on to someone else. The record kept (Kilo) holds an opening
-- balance. Mike is merged into Kilo.
--
--   M  445 installs, a second run changes nothing, its self-test leaves no
--      row; the fingerprint moves by its two functions; an unknown version
--      of either, of a function it relies on, a new column naming a lot, a
--      trigger on a table it repoints, or a lot a Move granted that names a
--      lot it did not replace stops it.
--   N  Everything but the credit is as 425's merge leaves it, on the same
--      records: the answer, the audit rows, every other record naming either
--      customer, the customers, the wallets, the ledger rows (but for the
--      lot they name), the benefit values and sales (but for their lots),
--      and the new lots but for source_type, source_record_id and
--      reassigned_from_lot_id. (425 is run from its own text, as a
--      temporary function, and undone.)
--   Q  What 425 did, for the record: 'customer_merge' lots, held for review,
--      'Other', the refund options naming the retired record, and refund
--      and cancellation plans that are not what they were.
--   O  Each of Mike's lots with credit left: drawn down, and one new lot of
--      Kilo's, linked to it, with the same category, source, restrictions,
--      store and dates, and what was left; the same spending rule and the
--      same source group as before; no 'customer_merge' lot.
--   B  Kilo's balances are his and Mike's added up (categories, sources,
--      total; nothing counted twice); his purchases are his and Mike's
--      (moved credit still 'received'); Mike's are empty.
--   P  The purchase records name Kilo's lots: benefit values, sales,
--      invoice_credit_lot_ids; credit released before settlement is followed
--      along (credit_lot_chain / credit_lot_current), its record unchanged;
--      Charlie's moved credit is traced to his package; the refund options
--      name Kilo; the guided refund and cancellation plans of Mike's
--      invoices (and Charlie's) are what they were before the merge, Kilo in
--      Mike's place (compared as sets: a plan's benefits have no set order).
--   A  invoice_wallet_availability holds Kilo's merged credit under the
--      right method.
--   W  Each wallet method pays it, by the rules it had: Credit Package Paid
--      a therapy session, Credit Package Bonus an own-brand product (not a
--      session), Premium Bundle Paid and Bonus, Paid Credit and Bonus Credit
--      only from 'other' credit, Legacy (the bundle-linked lot too),
--      Promotional/FOC and Exchange.
--   (Mike's lots cannot be partly SPENT before the merge: a duplicate who has
--   spent wallet credit cannot be merged, X. They are partly taken back
--   instead (a part refund; a moved-out lot), and spent after it, W.)
--   R  A refund of a payment made after the merge puts the credit back on
--      Kilo's lot it came from; a full refund of Mike's package invoice
--      takes what is left of its credit back from Kilo (the value of the
--      Bonus Kilo spent is kept, the refund's own rule); a cancellation of Mike's bundle
--      invoice takes its credit back from Kilo, and writes off the Legacy
--      lot linked to its line.
--   S  Mike's part-paid package, settled by Kilo: no paid credit given twice;
--      the benefit values name Kilo's lots, the released one too; a full
--      refund takes all of it back from Kilo.
--   E  A lot whose benefit value an Owner moved on (Delta's) keeps its
--      records on Mike's lot; Delta's credit is still traced to the bundle.
--   C  A share of a shared package (a 141 split, invoice_credit_splits):
--      after Oscar is merged into Papa, the split names Papa's lot, unspent,
--      and the share's sale names it too.
--   V  Merged credit moved on (445's 3.): Victor's part-paid package (300
--      Paid released), Victor merged into Uniform, Uniform pays the rest, an
--      Owner moves the released credit to Zulu (Move). Zulu's lot has no
--      link; the released credit is still followed to Uniform's lot, not
--      Zulu's; both commission sources are found; a refund of part of
--      Zulu's credit goes through; the invoice reassigned to Yankee with its
--      credit leaves Zulu's credit with Zulu. With Move's old text (191's,
--      rebuilt and checked by its md5) the same steps go wrong as found in
--      review: the chain goes to Zulu's lot, the refund is refused and the
--      reassignment takes Zulu's credit (V has teeth).
--   X  A duplicate who has spent wallet credit cannot be merged, by 425 or
--      by 445 (customer_credit_allocations cannot be changed): unchanged,
--      nothing written.
--   K  Who may call each: merge_customer_records the server alone, Move
--      signed-in staff and the server, as before.
--
-- Disposable database only; everything is rolled back. Run from the
-- repository root on a copy of production:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/customer-merge/tests/merge-credit-origin-445.sql
-- (it installs 445 twice; with -v nomig=1 where 445 is in already). Every
-- name, phone and email below is invented: ACMA fictional mobile numbers
-- (+61491570840..+61491570853) and @example.com addresses. A copy without
-- production's five wallet methods gets them, as 82 seeds them, for the run.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
create function pg_temp.fp() returns text language sql as
$$ select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') $$;
create function pg_temp.md5_of(sig text) returns text language sql as
$$ select md5(pg_get_functiondef(to_regprocedure('public.' || sig))) $$;
-- Where 462 is in (move-merge-leftovers-462.sql): the merge also repoints
-- the records of a lot whose benefit value an Owner moved on (the Move's
-- credit is traced through the Move's own ledger rows): its AFTER of the
-- merge, and E1 the fixed way.
create function pg_temp.with_462() returns boolean language sql as
$$ select to_regprocedure('public.credit_given_back_follows(uuid)') is not null $$;
create function pg_temp.merge_md5() returns text language sql as
$$ select case when pg_temp.with_462() then 'ba05c2b1fb4c0e14d369c01d06a635b0' else '2e0c9852099ab88d8f27827b5f9a3846' end $$;
create function pg_temp.method(nm text) returns uuid language sql as
$$ select id from public.payment_methods where name = nm and deleted_at is null $$;
create function pg_temp.invoice(cust uuid, lines jsonb) returns uuid language sql as
$$ select public.create_invoice(pg_temp.fx('st'), cust, null::uuid, lines, 0::numeric, null::text, null::uuid, '[]'::jsonb) $$;
create function pg_temp.therapy(qty int) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.fx('svc'), 'quantity', qty)) $$;
create function pg_temp.product(key text) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx(key), 'quantity', 1)) $$;
create function pg_temp.pay(inv uuid, nm text, amount numeric) returns uuid language plpgsql as
$$declare before uuid[]; begin
  before := array(select id from public.invoice_payments where invoice_id = inv);
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id', pg_temp.method(nm), 'amount', amount)), gen_random_uuid());
  return (select id from public.invoice_payments where invoice_id = inv and not (id = any (before)));
end$$;
-- A payment's lots: 'group:category' of each, sorted, and their owner.
create function pg_temp.pay_lots(pay uuid) returns text language plpgsql as
$$begin return (select string_agg(distinct public.credit_lot_source_group(a.lot_id) || ':' || l.category, ',')
     from public.invoice_line_credit_allocations a join public.customer_credit_lots l on l.id = a.lot_id
    where a.payment_id = pay); end$$;
-- Kilo's lot that replaces one of Mike's (445's link).
create function pg_temp.kept(lot uuid) returns uuid language sql as
$$ select id from public.customer_credit_lots where reassigned_from_lot_id = lot and customer_id = pg_temp.fx('kilo') $$;
-- One method's entry in invoice_wallet_availability().
create function pg_temp.avail(inv uuid, nm text) returns jsonb language plpgsql as
$$begin return (select m from jsonb_array_elements(public.invoice_wallet_availability(inv) -> 'methods') m
    where m ->> 'name' = nm); end$$;
-- A guided refund or cancellation (request, then approve), giving every
-- override the plan asks for a reason (and, where it asks one, an amount).
create function pg_temp.guided(inv uuid, act text, record_refund boolean) returns jsonb language plpgsql as
$$declare req jsonb; res jsonb; begin
  req := public.request_invoice_action_v2(inv, act, '[]'::jsonb, 'T445 ' || act, null, gen_random_uuid());
  res := public.resolve_invoice_action_v2((req ->> 'request_id')::uuid, true, 'T445 agreed', null,
    coalesce((select jsonb_agg(jsonb_build_object('code', o ->> 'code', 'reason', 'T445 override')
                               || case when coalesce((o ->> 'amount_required')::boolean, false)
                                       then jsonb_build_object('amount', 0) else '{}'::jsonb end)
                from jsonb_array_elements(req -> 'plan' -> 'overrides_required') o), '[]'::jsonb),
    null, record_refund);
  return jsonb_build_object('plan', req -> 'plan', 'result', res);
end$$;
-- What a merge leaves, but for the credit's origin: see N in the header.
-- Every column naming a customer (but the credit lots, ledger and
-- allocations), row by row, without the lots they name; the two customers;
-- the wallets; the ledger rows without their id, number and lot; the lots
-- without their id, source and link; the benefit values without their lot;
-- the audit rows written since the marker (without their id).
create function pg_temp.world(p_k uuid, p_m uuid) returns text language plpgsql as
$$declare r record; v text; acc text := '';
  c_drop constant text := ' - ''credit_lot_id'' - ''bonus_credit_lot_id'' - ''paid_credit_lot_id'' - ''issued_lot_id'' - ''lot_id''';
begin
  for r in select c.relname as tbl, a.attname as col
             from pg_constraint kk
             join pg_class c on c.oid = kk.conrelid and c.relkind = 'r'
             join pg_attribute a on a.attrelid = kk.conrelid and a.attnum = any (kk.conkey)
             join pg_class f on f.oid = kk.confrelid
             join pg_namespace ns on ns.oid = c.relnamespace
            where kk.contype = 'f' and f.relname = 'customers' and ns.nspname = 'public'
              and c.relname not in ('customer_credit_lots', 'customer_credit_ledger', 'customer_credit_allocations')
            order by 1, 2 loop
    execute format('select coalesce(md5(string_agg(x, ''|'' order by x)), ''-'') from (select (to_jsonb(t)%s)::text x from public.%I t where %I in ($1, $2)) s',
                   c_drop, r.tbl, r.col) into v using p_k, p_m;
    acc := acc || r.tbl || '.' || r.col || '=' || v || ' ';
  end loop;
  select acc || 'customers=' || md5(string_agg(to_jsonb(c)::text, '|' order by c.id)) into acc
    from public.customers c where c.id in (p_k, p_m);
  select acc || ' ledger=' || md5(string_agg(x, '|' order by x)) into acc
    from (select (to_jsonb(e) - 'id' - 'entry_seq' - 'lot_id')::text x from public.customer_credit_ledger e
           where e.customer_id in (p_k, p_m)) s;
  select acc || ' lots=' || md5(string_agg(x, '|' order by x)) into acc
    from (select (to_jsonb(l) - 'id' - 'source_type' - 'source_record_id' - 'reassigned_from_lot_id')::text x
            from public.customer_credit_lots l where l.customer_id in (p_k, p_m)) s;
  select acc || ' benefits=' || coalesce(md5(string_agg(x, '|' order by x)), '-') into acc
    from (select (to_jsonb(b) - 'lot_id')::text x from public.invoice_benefit_values b
           where b.invoice_id in (select id from public.invoices where customer_id in (p_k, p_m))) s;
  select acc || ' audit=' || coalesce(md5(string_agg(x, '|' order by x)), '-') into acc
    from (select (to_jsonb(a) - 'id')::text x from public.audit_logs a
           where not exists (select 1 from audit_mark m where m.id = a.id)) s;
  return acc;
end$$;
create temp table audit_mark(id uuid primary key);
-- A jsonb value with every array's elements sorted (by their text), so two
-- plans compare as sets: the order of a plan's benefits follows no ORDER BY
-- (invoice_refund_options_before_sessions).
create function pg_temp.canon(j jsonb) returns jsonb language plpgsql immutable as
$$begin
  return case jsonb_typeof(j)
    when 'object' then (select coalesce(jsonb_object_agg(e.k, pg_temp.canon(e.v)), '{}'::jsonb) from jsonb_each(j) e(k, v))
    when 'array' then (select coalesce(jsonb_agg(s.c order by s.c::text), '[]'::jsonb)
                         from (select pg_temp.canon(x) c from jsonb_array_elements(j) x) s)
    else j end;
end$$;
-- The guided refund and cancellation plans an Owner would be shown for
-- Mike's invoices, and for Charlie's (whose Paid credit Mike holds), without
-- their hash; with p_as_kilo, Mike's id and name read as Kilo's (the plans
-- before the merge, as they should read after it). Mike's second bundle (x5)
-- is E's.
create function pg_temp.plans(p_as_kilo boolean) returns text language plpgsql as
$$declare v text; begin
  select string_agg(x.k || ' ' || x.a || ' ' || pg_temp.canon(public.invoice_action_plan(pg_temp.fx(x.k), x.a, '[]'::jsonb) - 'plan_hash')::text,
                    E'\n' order by x.k, x.a)
    into v
    from (values ('x1', 'refund_full'), ('x1', 'cancel'), ('x2', 'refund_full'), ('x2', 'cancel'),
                 ('x3', 'refund_full'), ('x3', 'cancel'), ('x4', 'cancel')) x(k, a);
  if p_as_kilo then
    v := replace(replace(v, pg_temp.fx('mike')::text, pg_temp.fx('kilo')::text), 'T445 Mike', 'T445 Kilo');
  end if;
  return v;
end$$;
-- Lots as they were before the merge (Mike's with credit left, and Kilo's).
create temp table snap(lot uuid primary key, who text, category text, source_type text, source_record_id uuid,
  usage_restrictions jsonb, store_id uuid, effective_date date, original_purchase_date date, remaining numeric,
  policy text, grp text);

-- 425's merge_customer_records, from its own text, as a temporary function
-- (for N: the same records merged by both).
do $t$
declare t text := $t425$CREATE OR REPLACE FUNCTION public.merge_customer_records(p_keep uuid, p_merge uuid, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_preview jsonb; k public.customers%rowtype; m public.customers%rowtype;
        r record; r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
        v_moved jsonb := '{}'::jsonb; n bigint; v_keep_wallet uuid;
        v_sql text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can merge customer records' using errcode='42501'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Give a reason; it is kept with the merge'; end if;
  if p_request_id is null then raise exception 'A request id is required'; end if;

  -- A retry returns the original outcome instead of merging a second time.
  if exists (select 1 from public.audit_logs
              where action = 'customers_merged'
                and record_id = p_keep
                and new_data->>'request_id' = p_request_id::text) then
    return jsonb_build_object('success', true, 'replayed', true,
      'detail','This merge was already applied.'); end if;

  -- Lock both, keeper first, so two merges cannot interleave.
  select * into k from public.customers where id = least(p_keep,p_merge) for update;
  select * into m from public.customers where id = greatest(p_keep,p_merge) for update;
  select * into k from public.customers where id = p_keep;
  select * into m from public.customers where id = p_merge;

  v_preview := public.preview_customer_merge(p_keep, p_merge);
  if not (v_preview->>'can_merge')::boolean then
    raise exception 'This merge needs review first: %',
      (select string_agg(x->>'detail',' ') from jsonb_array_elements(v_preview->'blocking') x); end if;

  -- ---- credit: drawn down and reissued, never repointed -------------------
  --
  -- A posted lot is immutable -- customer, category, original amount, source
  -- and store cannot be edited -- and the ledger behind it is append-only. So
  -- the surviving record is granted a replacement carrying the same category,
  -- restrictions and dates, and the duplicate's lot is drawn down to nothing,
  -- with both movements written to the ledger. The balance is carried; it is
  -- never recreated, and bonus credit cannot become paid credit on the way.
  --
  -- The duplicate's wallet and its ledger entries stay as they are. Those
  -- entries record that, at the time, this credit moved under that record, and
  -- that remains true; the retired customer row keeps them resolvable.
  v_keep_wallet := public.ensure_customer_wallet(p_keep);
  for r_lot in
    select l.* from public.customer_credit_lots l
     where l.customer_id = p_merge and l.status = 'active' and l.remaining_amount > 0
     for update
  loop
    v_new_lot := gen_random_uuid();
    update public.customer_credit_lots
       set remaining_amount = 0, updated_at = now() where id = r_lot.id;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (r_lot.wallet_id, r_lot.customer_id, 'adjust_decrease', r_lot.category,
            r_lot.remaining_amount, r_lot.id, 'customer_merge_out', p_keep,
            r_lot.store_id, p_reason, auth.uid(), auth.uid());

    insert into public.customer_credit_lots
    select (jsonb_populate_record(null::public.customer_credit_lots, to_jsonb(r_lot) || jsonb_build_object(
      'id', v_new_lot, 'wallet_id', v_keep_wallet, 'customer_id', p_keep,
      'original_amount', r_lot.remaining_amount, 'remaining_amount', r_lot.remaining_amount,
      'source_type', 'customer_merge', 'source_record_id', p_merge,
      'reference_no', null, 'reason', p_reason, 'reversal_of_lot_id', null,
      'created_by', auth.uid(), 'approved_by', auth.uid(),
      'created_at', now(), 'updated_at', now()))).*;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (v_keep_wallet, p_keep, 'grant', r_lot.category, r_lot.remaining_amount,
            v_new_lot, 'customer_merge_in', p_merge, r_lot.store_id,
            p_reason, auth.uid(), auth.uid());
  end loop;

  -- ---- referrals go through the path that owns them -----------------------
  --
  -- customers.referred_by is protected by enforce_referral_ownership and by a
  -- no-self-referral trigger, and reassign_customer_referrer is what may change
  -- it: it locks the row, walks the chain for cycles and records the reason.
  -- Repointing it directly would be going round all of that.
  if k.referred_by = p_merge then
    perform public.reassign_customer_referrer(p_keep, null,
      'Merged duplicate ' || p_merge::text || ': ' || trim(p_reason));
  end if;
  -- 398: the duplicate's friends are the same referrals, made when they
  -- were made: each keeps their referral date (tg_customers_referral_date).
  perform set_config('energia.keep_referral_date', '1', true);
  for r in select id from public.customers
            where referred_by = p_merge and id <> p_keep and deleted_at is null
  loop
    perform public.reassign_customer_referrer(r.id, p_keep,
      'Referrer merged from duplicate ' || p_merge::text || ': ' || trim(p_reason));
  end loop;
  perform set_config('energia.keep_referral_date', '0', true);

  -- ---- affiliate record, when only the duplicate has one ------------------
  update public.customer_affiliates set customer_id = p_keep
   where customer_id = p_merge
     and not exists (select 1 from public.customer_affiliates where customer_id = p_keep);

  -- ---- everything else, from the catalogue --------------------------------
  for r in
    select c.relname as tbl, a.attname as col
      from pg_constraint kk
      join pg_class c on c.oid = kk.conrelid and c.relkind = 'r'
      join pg_attribute a on a.attrelid = kk.conrelid and a.attnum = any(kk.conkey)
      join pg_class f on f.oid = kk.confrelid
      join pg_namespace ns on ns.oid = c.relnamespace
     where kk.contype = 'f' and f.relname = 'customers' and ns.nspname = 'public'
       -- Handled above, or deliberately not moved:
       and not (c.relname = 'customer_credit_wallets')            -- UNIQUE per customer
       and not (c.relname = 'customer_credit_ledger')             -- append-only by design
       and not (c.relname = 'customer_credit_lots')               -- immutable; reissued above
       and not (c.relname = 'customers' and a.attname = 'referred_by') -- reassigned above
       and not (c.relname = 'customer_affiliates' and a.attname = 'customer_id')
       -- 362: a phone-review capture describes its own record's phone (one row
       -- per customer); it stays with the retired record.
       and not (c.relname = 'customer_phone_migration_map')
       -- 425: a referral sign-up check stays with the sign-up it was made for.
       -- The retired record keeps it, so it no longer counts or waits; the kept
       -- customer keeps their own check, or none (one check per customer).
       and not (c.relname = 'referral_signup_checks' and a.attname = 'customer_id')
     order by c.relname, a.attname
  loop
    v_sql := format('update public.%I set %I = $1 where %I = $2', r.tbl, r.col, r.col);
    execute v_sql using p_keep, p_merge;
    get diagnostics n = row_count;
    if n > 0 then
      v_moved := v_moved || jsonb_build_object(r.tbl || '.' || r.col, n);
    end if;
  end loop;

  -- The duplicate is retired, not destroyed: it is the evidence that those
  -- older records were always this person.
  update public.customers
     set deleted_at = now(),
         notes = coalesce(notes || E'\n', '') ||
                 'Merged into ' || coalesce(k.full_name, p_keep::text) ||
                 ' (' || p_keep::text || ') — ' || trim(p_reason)
   where id = p_merge;

  perform public.write_audit('customers', p_keep, 'customers_merged',
    jsonb_build_object('kept', to_jsonb(k), 'merged', to_jsonb(m)),
    jsonb_build_object('merged_from', p_merge, 'moved', v_moved,
                       'reason', trim(p_reason), 'request_id', p_request_id));

  return jsonb_build_object('success', true, 'kept', p_keep, 'retired', p_merge,
    'moved', v_moved);
end $function$
$t425$;
begin
  if md5(t) <> '099ecf3aae30b5faaf8fb36bc15ce888' then
    raise exception 'FIXTURE: the text given as 425''s merge_customer_records is not 425''s (md5 %)', md5(t); end if;
  execute replace(t, 'CREATE OR REPLACE FUNCTION public.merge_customer_records(', 'CREATE FUNCTION pg_temp.merge_customer_records_425(');
end $t$;

-- ═════ Fixtures (before 445 is installed, where the suite installs it) ═════
-- The five wallet methods production has (82), where the copy has none.
insert into public.payment_methods (name, is_active, is_wallet_credit, wallet_category, is_system)
select v.name, true, true, v.cat, true
  from (values ('Wallet — Paid Credit', 'paid'), ('Wallet — Bonus Credit', 'bonus'),
               ('Wallet — Legacy Credit', 'legacy'), ('Wallet — Promotional/FOC Credit', 'promotional'),
               ('Wallet — Exchange Credit', 'exchange')) v(name, cat)
 where not exists (select 1 from public.payment_methods m where m.name = v.name and m.deleted_at is null);

do $$
declare o uuid := gen_random_uuid(); st uuid; svc uuid; own uuid; third uuid; pk uuid; pb uuid; c uuid; inv uuid;
  cash uuid; r jsonb; item uuid; pay uuid; b uuid;
begin
  if exists (select 1 from public.customers where phone like '+6149157084_') then
    raise exception 'FIXTURE: a customer already uses the test phones +6149157084x'; end if;
  insert into auth.users(id, email) values (o, 't445-owner@example.com');
  insert into public.profiles(id, full_name, email, role) values (o, 'T445 Owner', 't445-owner@example.com', 'owner');
  perform pg_temp.putx('owner', o);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into public.stores(name, code, country_code) values ('T445 Store', 'T445S', 'SG') returning id into st;
  perform pg_temp.putx('st', st);
  insert into public.payment_methods(name) values ('T445 Cash') returning id into cash;
  perform pg_temp.putx('cash', cash);
  svc := (public.upsert_therapy_service(null, 'T445-S', 'T445 Session', 100, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform public.set_therapy_service_store(svc, st, true, null);
  perform pg_temp.putx('svc', svc);
  insert into public.products(name, sku, product_type) values ('T445 Own Product', 'T445-OWN', 'own') returning id into own;
  insert into public.products(name, sku, product_type) values ('T445 Third Product', 'T445-THIRD', 'third_party') returning id into third;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, own, 50), (st, third, 50);
  perform public.set_product_prices(st, own, 40, 40, 'available');
  perform public.set_product_prices(st, third, 30, 30, 'available');
  perform pg_temp.putx('own', own); perform pg_temp.putx('third', third);
  insert into public.credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value,
                                     allow_product, allow_therapy, allow_voucher, grants_reward)
  values ('T445 Package', 1000, 1000, true, 100, true, true, true, false) returning id into pk;
  insert into public.credit_package_stores(package_id, store_id) values (pk, st);
  insert into public.premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
  values ('T445 Bundle', 500, 500, 50, 0, false) returning id into pb;
  insert into public.premium_bundle_stores(bundle_id, store_id) values (pb, st);
  perform pg_temp.putx('pk', pk); perform pg_temp.putx('pb', pb);

  foreach r in array array[
      jsonb_build_object('k', 'kilo', 'name', 'T445 Kilo', 'phone', '+61491570840'),
      jsonb_build_object('k', 'mike', 'name', 'T445 Mike', 'phone', '+61491570841'),
      jsonb_build_object('k', 'charlie', 'name', 'T445 Charlie', 'phone', '+61491570842'),
      jsonb_build_object('k', 'delta', 'name', 'T445 Delta', 'phone', '+61491570843'),
      jsonb_build_object('k', 'sierra', 'name', 'T445 Sierra', 'phone', '+61491570844'),
      jsonb_build_object('k', 'tango', 'name', 'T445 Tango', 'phone', '+61491570845'),
      jsonb_build_object('k', 'romeo', 'name', 'T445 Romeo', 'phone', '+61491570846'),
      jsonb_build_object('k', 'oscar', 'name', 'T445 Oscar', 'phone', '+61491570847'),
      jsonb_build_object('k', 'papa', 'name', 'T445 Papa', 'phone', '+61491570848'),
      jsonb_build_object('k', 'quebec', 'name', 'T445 Quebec', 'phone', '+61491570849')] loop
    insert into public.customers(full_name, phone) values (r ->> 'name', r ->> 'phone') returning id into c;
    perform pg_temp.putx(r ->> 'k', c);
  end loop;
  c := pg_temp.fx('mike');
  -- Mike referred Romeo, and is an affiliate (only he has a record).
  perform public.reassign_customer_referrer(pg_temp.fx('romeo'), c, 'T445 fixture: referred by Mike');
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at) values (c, 'active', st, now());

  -- X1 Mike buys the package (cash 1000): Paid 1000, Bonus 100. An Owner
  -- refunds 200 of it, taking back 220 of the Paid credit (part refund).
  inv := pg_temp.invoice(c, jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pk, 'quantity', 1)));
  pay := pg_temp.pay(inv, 'T445 Cash', 1000);
  perform pg_temp.putx('x1', inv);
  select id into item from public.invoice_items where invoice_id = inv;
  select v.id into b from public.invoice_benefit_values v join public.customer_credit_lots l on l.id = v.lot_id
   where v.invoice_id = inv and l.category = 'paid';
  perform public.refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', 200,
                                         'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b, 'amount', 200)))),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 200)), '[]'::jsonb, 'T445 part refund', gen_random_uuid());
  perform pg_temp.putx('p_paid', (select credit_lot_id from public.credit_package_sales where invoice_id = inv));
  perform pg_temp.putx('p_bonus', (select bonus_credit_lot_id from public.credit_package_sales where invoice_id = inv));

  -- X2 Mike buys the bundle (cash 500): Paid 500, Bonus 50; and a Legacy
  -- opening balance recorded as its line's released credit (as 443's three
  -- CREDIT-SPLIT-12 lots are; the one-off repair is not in the repo).
  inv := pg_temp.invoice(c, jsonb_build_array(jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pb,
           'quantity', 1, 'voucher_selection', '[]'::jsonb)));
  perform pg_temp.pay(inv, 'T445 Cash', 500);
  perform pg_temp.putx('x2', inv);
  perform pg_temp.putx('b_paid', (select paid_credit_lot_id from public.premium_bundle_sales where invoice_id = inv));
  perform pg_temp.putx('b_bonus', (select bonus_credit_lot_id from public.premium_bundle_sales where invoice_id = inv));
  perform public.add_legacy_credit(c, 'legacy', 45, public.sg_today() - 400, st, 'T445-OB-LINK', 'T445 linked legacy', public.sg_today(), gen_random_uuid());
  perform pg_temp.putx('link', (select id from public.customer_credit_lots where reference_no = 'T445-OB-LINK'));
  insert into public.credit_package_progress_lots(lot_id, invoice_item_id, invoice_id, released_amount)
  select pg_temp.fx('link'), ii.id, ii.invoice_id, 45 from public.invoice_items ii where ii.invoice_id = inv;

  -- X3 Charlie buys the package; an Owner moves its unused Paid credit to
  -- Mike (Move, 186).
  inv := pg_temp.invoice(pg_temp.fx('charlie'), jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pk, 'quantity', 1)));
  perform pg_temp.pay(inv, 'T445 Cash', 1000);
  perform pg_temp.putx('x3', inv);
  r := public.transfer_invoice_unused_benefit(
         (select v.id from public.invoice_benefit_values v join public.customer_credit_lots l on l.id = v.lot_id
           where v.invoice_id = inv and l.category = 'paid'),
         c, st, 'T445 move the unused paid credit to Mike', gen_random_uuid());
  perform pg_temp.putx('moved', (select lot_id from public.invoice_benefit_values where id = (r ->> 'benefit_id')::uuid));
  perform pg_temp.putx('moved_benefit', (r ->> 'benefit_id')::uuid);

  -- Mike's other credit: opening balances (Paid 70, Legacy 60), Adjust
  -- (Bonus 20, Promotional 15, Exchange 12).
  perform public.add_legacy_credit(c, 'paid', 70, public.sg_today() - 400, st, 'T445-OB-PAID', 'T445 opening paid', public.sg_today() - 30, gen_random_uuid());
  perform public.add_legacy_credit(c, 'legacy', 60, public.sg_today() - 400, st, 'T445-OB-LEG', 'T445 opening legacy', public.sg_today() - 60, gen_random_uuid());
  perform public.adjust_customer_credit(c, 'bonus', 'increase', 20, 'T445 adjust bonus', 'T445-ADJ-B', public.sg_today() - 30, null, st, gen_random_uuid());
  perform public.adjust_customer_credit(c, 'promotional', 'increase', 15, 'T445 adjust promo', 'T445-ADJ-P', null, null, st, gen_random_uuid());
  perform public.adjust_customer_credit(c, 'exchange', 'increase', 12, 'T445 adjust exchange', 'T445-ADJ-X', null, null, st, gen_random_uuid());
  perform pg_temp.putx('ob_paid', (select id from public.customer_credit_lots where reference_no = 'T445-OB-PAID'));

  -- X4 Mike buys the package and pays 300 of it: 300 Paid credit released
  -- (credit_package_progress_lots, 356).
  inv := pg_temp.invoice(c, jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pk, 'quantity', 1)));
  perform pg_temp.pay(inv, 'T445 Cash', 300);
  perform pg_temp.putx('x4', inv);
  perform pg_temp.putx('released', (select lot_id from public.credit_package_progress_lots where invoice_id = inv));

  -- X5 Mike buys the bundle again; an Owner moves its Bonus on to Delta.
  -- Then 20 of that Bonus is back on Mike's lot (rare in the app: credit put
  -- back on a lot after its Move; written here directly: the guard for it is
  -- E).
  inv := pg_temp.invoice(c, jsonb_build_array(jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pb,
           'quantity', 1, 'voucher_selection', '[]'::jsonb)));
  perform pg_temp.pay(inv, 'T445 Cash', 500);
  perform pg_temp.putx('x5', inv);
  perform pg_temp.putx('b2_paid', (select paid_credit_lot_id from public.premium_bundle_sales where invoice_id = inv));
  perform pg_temp.putx('b2_bonus', (select bonus_credit_lot_id from public.premium_bundle_sales where invoice_id = inv));
  r := public.transfer_invoice_unused_benefit(
         (select v.id from public.invoice_benefit_values v where v.lot_id = pg_temp.fx('b2_bonus')),
         pg_temp.fx('delta'), st, 'T445 move the bundle bonus to Delta', gen_random_uuid());
  perform pg_temp.putx('delta_lot', (select lot_id from public.invoice_benefit_values where id = (r ->> 'benefit_id')::uuid));
  update public.customer_credit_lots set remaining_amount = 20, updated_at = now() where id = pg_temp.fx('b2_bonus');
  insert into public.customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, store_id, reason, created_by)
  select l.wallet_id, l.customer_id, 'adjust_increase', 'bonus', 20, l.id, 't445_fixture', l.store_id, 'T445 fixture: 20 back on a moved-out lot', o
    from public.customer_credit_lots l where l.id = pg_temp.fx('b2_bonus');

  -- Kilo's own: an opening balance (Paid 25).
  perform public.add_legacy_credit(pg_temp.fx('kilo'), 'paid', 25, public.sg_today() - 400, st, 'T445-OB-K', 'T445 Kilo opening paid', public.sg_today() - 90, gen_random_uuid());
  perform pg_temp.putx('kilo_ob', (select id from public.customer_credit_lots where reference_no = 'T445-OB-K'));

  -- Sierra (for X) has spent wallet credit: an opening balance, 40 of it on a product.
  perform public.add_legacy_credit(pg_temp.fx('sierra'), 'paid', 50, public.sg_today() - 400, st, 'T445-OB-S', 'T445 Sierra opening', public.sg_today() - 5, gen_random_uuid());
  inv := pg_temp.invoice(pg_temp.fx('sierra'), pg_temp.product('own'));
  perform pg_temp.pay(inv, 'Wallet — Paid Credit', 40);
end $$;

-- ═════ M Install ═════
create temp table m445(fp_before text, n_lots int, n_ledger int, n_alloc int, n_cust int, n_inv int, n_benefit int,
                       n_audit int, lots_hash text, sales_hash text);
insert into m445 select pg_temp.fp(), (select count(*) from public.customer_credit_lots), (select count(*) from public.customer_credit_ledger),
                        (select count(*) from public.invoice_line_credit_allocations), (select count(*) from public.customers),
                        (select count(*) from public.invoices), (select count(*) from public.invoice_benefit_values),
                        (select count(*) from public.audit_logs),
                        (select md5(string_agg(to_jsonb(l)::text, '|' order by l.id)) from public.customer_credit_lots l),
                        (select md5(string_agg(to_jsonb(s)::text, '|' order by s.id)) from public.credit_package_sales s);
\if :{?nomig}
select pg_temp.check(pg_temp.md5_of('merge_customer_records(uuid,uuid,text,uuid)') = pg_temp.merge_md5()
    and pg_temp.md5_of('transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)') = '7aebd7120bc3928db46df0941cb20889',
  'M0 445 is installed (nomig; 462''s merge where 462 is in)');
\else
select pg_temp.check(pg_temp.md5_of('merge_customer_records(uuid,uuid,text,uuid)') = '099ecf3aae30b5faaf8fb36bc15ce888'
    and pg_temp.md5_of('transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)') = 'ea7e8ce0612752c75ba75748c9275c42',
  'M0 445 is not in yet: merge_customer_records is 425''s and transfer_invoice_unused_benefit 191''s (this suite installs it; use -v nomig=1 where it is in)');
-- M5 an unknown version of merge_customer_records stops it.
savepoint m5;
do $$ begin
  execute replace(pg_get_functiondef('public.merge_customer_records(uuid,uuid,text,uuid)'::regprocedure),
                  'declare v_preview jsonb;', 'declare /* another version */ v_preview jsonb;');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/445_merge_keeps_credit_origin.sql
\set m5_failed :ERROR
\set m5_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m5;
-- M6 an unknown version of a function it relies on stops it.
savepoint m6;
do $$ begin
  execute replace(pg_get_functiondef('public.credit_lot_chain(uuid)'::regprocedure), '-- 356', '-- 356 (another version)');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/445_merge_keeps_credit_origin.sql
\set m6_failed :ERROR
\set m6_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m6;
-- M7 a new column naming a lot stops it (a merge would have to decide it).
savepoint m7;
alter table public.invoice_items add column t445_lot uuid references public.customer_credit_lots(id);
\set ON_ERROR_STOP off
\ir ../../../supabase/445_merge_keeps_credit_origin.sql
\set m7_failed :ERROR
\set m7_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m7;
-- M8 a trigger on a table it repoints stops it.
savepoint m8;
create function pg_temp.t445_noop() returns trigger language plpgsql as $f$ begin return new; end $f$;
create trigger t445_noop before update on public.credit_package_sales for each row execute function pg_temp.t445_noop();
\set ON_ERROR_STOP off
\ir ../../../supabase/445_merge_keeps_credit_origin.sql
\set m8_failed :ERROR
\set m8_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m8;
-- M10 an unknown version of transfer_invoice_unused_benefit stops it.
savepoint m10;
do $$ begin
  execute replace(pg_get_functiondef('public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure),
                  'declare b public.invoice_benefit_values%rowtype;', 'declare /* another version */ b public.invoice_benefit_values%rowtype;');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/445_merge_keeps_credit_origin.sql
\set m10_failed :ERROR
\set m10_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m10;
-- M11 a lot a Move granted that names a lot it did not replace stops it
-- (Charlie's credit moved to Mike, X3, given a link here).
savepoint m11;
update public.customer_credit_lots set reassigned_from_lot_id = pg_temp.fx('p_paid') where id = pg_temp.fx('moved');
\set ON_ERROR_STOP off
\ir ../../../supabase/445_merge_keeps_credit_origin.sql
\set m11_failed :ERROR
\set m11_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m11;
select pg_temp.check(:'m5_failed' = 'true' and :'m5_msg' like '445: public.merge_customer_records(uuid,uuid,text,uuid) is not the version this was tested against%',
  'M5 an unknown version of merge_customer_records stops it: ' || :'m5_msg');
select pg_temp.check(:'m6_failed' = 'true' and :'m6_msg' like '445: public.credit_lot_chain(uuid) is missing or not the version this was tested against%',
  'M6 an unknown version of a function it relies on stops it: ' || :'m6_msg');
select pg_temp.check(:'m7_failed' = 'true' and :'m7_msg' like '445: the columns that name a credit lot are not as read%invoice_items.t445_lot%',
  'M7 a new column naming a lot stops it: ' || :'m7_msg');
select pg_temp.check(:'m8_failed' = 'true' and :'m8_msg' like '445: these tables have triggers they did not have on 21 Oct 2026: credit_package_sales t445_noop%',
  'M8 a trigger on a table it repoints stops it: ' || :'m8_msg');
select pg_temp.check(:'m10_failed' = 'true' and :'m10_msg' like '445: public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid) is not the version this was tested against%',
  'M10 an unknown version of transfer_invoice_unused_benefit stops it: ' || :'m10_msg');
select pg_temp.check(:'m11_failed' = 'true' and :'m11_msg' like '445: 1 lot(s) granted by a Move name a lot they did not replace%',
  'M11 a lot a Move granted that names a lot it did not replace stops it: ' || :'m11_msg');
select pg_temp.check(pg_temp.md5_of('merge_customer_records(uuid,uuid,text,uuid)') = '099ecf3aae30b5faaf8fb36bc15ce888'
    and pg_temp.md5_of('transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)') = 'ea7e8ce0612752c75ba75748c9275c42'
    and (select reassigned_from_lot_id from public.customer_credit_lots where id = pg_temp.fx('moved')) is null,
  'M9 a stopped run changed nothing (merge_customer_records is still 425''s, transfer_invoice_unused_benefit 191''s)');
\ir ../../../supabase/445_merge_keeps_credit_origin.sql
do $$ begin perform pg_temp.put('fp1', pg_temp.fp()); end $$;
\ir ../../../supabase/445_merge_keeps_credit_origin.sql
select pg_temp.check(pg_temp.fp() = pg_temp.tx('fp1') and pg_temp.fp() <> (select fp_before from m445)
    and split_part(pg_temp.fp(), ' ', 2) = split_part((select fp_before from m445), ' ', 2),
  'M1 445 installs (no function more or less) and a second run changes nothing: ' || pg_temp.fp());
select pg_temp.check((select count(*) from public.customer_credit_lots) = (select n_lots from m445)
    and (select md5(string_agg(to_jsonb(l)::text, '|' order by l.id)) from public.customer_credit_lots l) = (select lots_hash from m445)
    and (select md5(string_agg(to_jsonb(s)::text, '|' order by s.id)) from public.credit_package_sales s) = (select sales_hash from m445)
    and (select count(*) from public.customer_credit_ledger) = (select n_ledger from m445)
    and (select count(*) from public.invoice_line_credit_allocations) = (select n_alloc from m445)
    and (select count(*) from public.customers) = (select n_cust from m445)
    and (select count(*) from public.invoices) = (select n_inv from m445)
    and (select count(*) from public.invoice_benefit_values) = (select n_benefit from m445)
    and (select count(*) from public.audit_logs) = (select n_audit from m445),
  'M2 installing changes no record: no lot, ledger row, allocation, sale, benefit value, customer, invoice or audit row (its self-test, twice, left none)');
-- M12 who may call each is compared as a set: production lists Move's grants
-- in another order than a local copy does (the first apply refused on that,
-- 22 Oct 2026, changing nothing).
savepoint m12;
revoke execute on function public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid) from authenticated, service_role;
grant execute on function public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid) to service_role;
grant execute on function public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid) to authenticated;
select proacl::text as m12_acl from pg_proc where oid = 'public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure \gset
\set ON_ERROR_STOP off
\ir ../../../supabase/445_merge_keeps_credit_origin.sql
\set m12_failed :ERROR
\set m12_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m12;
select pg_temp.check(:'m12_failed' = 'false'
    and :'m12_acl' = '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
  'M12 the same grants listed in production''s order do not stop it: ' || :'m12_acl' || ' ' || :'m12_msg');
\endif
select pg_temp.check(pg_temp.md5_of('merge_customer_records(uuid,uuid,text,uuid)') = pg_temp.merge_md5()
    and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'merge_customer_records') = 1
    and pg_temp.md5_of('transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)') = '7aebd7120bc3928db46df0941cb20889'
    and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'transfer_invoice_unused_benefit') = 1,
  'M3 merge_customer_records is 445''s (2e0c9852099ab88d8f27827b5f9a3846) and transfer_invoice_unused_benefit 445''s (7aebd7120bc3928db46df0941cb20889), with no overload');
select pg_temp.check((select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = 'public.merge_customer_records(uuid,uuid,text,uuid)'::regprocedure)
      = (select array_agg(x::text order by x::text) from unnest('{postgres=X/postgres,service_role=X/postgres}'::aclitem[]) x)
    and not has_function_privilege('anon', 'public.merge_customer_records(uuid,uuid,text,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.merge_customer_records(uuid,uuid,text,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.merge_customer_records(uuid,uuid,text,uuid)', 'execute'),
  'K1 merge_customer_records is still the server''s alone (postgres, service_role)');
select pg_temp.check((select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = 'public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure)
      = (select array_agg(x::text order by x::text) from unnest('{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]) x)
    and not has_function_privilege('anon', 'public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)', 'execute'),
  'K2 transfer_invoice_unused_benefit is still signed-in staff''s and the server''s, not anon''s (as 339 left it)');

-- ═════ Before the merge ═════
do $$
declare b jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  insert into snap
  select l.id, case when l.customer_id = pg_temp.fx('mike') then 'mike' else 'kilo' end, l.category, l.source_type, l.source_record_id,
         l.usage_restrictions, l.store_id, l.effective_date, l.original_purchase_date, l.remaining_amount,
         public.credit_lot_policy_for(l.id), public.credit_lot_source_group(l.id)
    from public.customer_credit_lots l
   where l.customer_id in (pg_temp.fx('mike'), pg_temp.fx('kilo')) and l.status = 'active' and l.remaining_amount > 0;
  perform pg_temp.put('bal_mike', public.customer_credit_balances(pg_temp.fx('mike'))::text);
  perform pg_temp.put('bal_kilo', public.customer_credit_balances(pg_temp.fx('kilo'))::text);
  perform pg_temp.put('plans0', pg_temp.plans(true));
  b := public.customer_credit_balances(pg_temp.fx('mike'));
  perform pg_temp.check((select count(*) from snap where who = 'mike') = 14 and (select count(*) from snap where who = 'kilo') = 1
      and (select remaining from snap where lot = pg_temp.fx('p_paid')) = 780
      and (select remaining from snap where lot = pg_temp.fx('b2_bonus')) = 20
      and (select remaining from snap where lot = pg_temp.fx('released')) = 300
      and (select policy || '/' || grp from snap where lot = pg_temp.fx('moved')) = 'package_paid/credit_package'
      and (select policy || '/' || grp from snap where lot = pg_temp.fx('link')) = 'open/premium_bundle'
      and (b ->> 'available_total')::numeric = 3472
      and b -> 'sources' = jsonb_build_object(
            'credit_package', '{"paid": 2080, "bonus": 100, "legacy": 0, "promotional": 0, "exchange": 0, "total": 2180}'::jsonb,
            'premium_bundle', '{"paid": 1000, "bonus": 70, "legacy": 45, "promotional": 0, "exchange": 0, "total": 1115}'::jsonb,
            'other', '{"paid": 70, "bonus": 20, "legacy": 60, "promotional": 15, "exchange": 12, "total": 177}'::jsonb),
    'F1 the fixtures: Mike holds 14 lots with credit left (package Paid 780 after a part refund, Bonus 100, moved 1000, released 300; '
    || 'bundle Paid 500 + 500, Bonus 50 + 20, a linked Legacy 45; other 177; 3472 in all), Kilo an opening balance: ' || (b -> 'sources')::text);
end $$;
insert into audit_mark select id from public.audit_logs;

-- ═════ N / Q The same records merged by 425's text, then undone ═════
savepoint n425;
do $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  r := pg_temp.merge_customer_records_425(pg_temp.fx('kilo'), pg_temp.fx('mike'), 'T445 the same person', pg_temp.fx('owner'));
  perform pg_temp.put('ans425', r::text);
end $$;
select pg_temp.tx('ans425') as ans425,
       pg_temp.world(pg_temp.fx('kilo'), pg_temp.fx('mike')) as world425,
       (select count(*) from public.customer_credit_lots l where l.customer_id = pg_temp.fx('kilo') and l.source_type = 'customer_merge') as q_merge_lots,
       (select count(*) from public.customer_credit_lots l where l.customer_id = pg_temp.fx('kilo') and l.source_type = 'customer_merge'
           and public.credit_lot_policy_for(l.id) = 'needs_review' and public.credit_lot_source_group(l.id) = 'other') as q_review_other,
       (select string_agg(distinct x ->> 'customer_id', ',') from jsonb_array_elements(public.invoice_refund_options_before_sessions(pg_temp.fx('x1')) -> 'benefits') x) as q_x1_holder,
       (select sum((x ->> 'max_refund')::numeric) from jsonb_array_elements(public.invoice_refund_options_before_sessions(pg_temp.fx('x1')) -> 'benefits') x) as q_x1_max,
       pg_temp.plans(false) is distinct from pg_temp.tx('plans0') as q_plans_differ
\gset
rollback to savepoint n425;
select pg_temp.check(:q_merge_lots = 14 and :q_review_other = 14 and :'q_x1_holder' = pg_temp.fx('mike')::text and :q_x1_max = 0,
  'Q1 with 425''s text: Kilo''s 14 new lots are ''customer_merge'', held for review and Other, and the package''s refund options name the retired Mike with nothing to refund');
select pg_temp.check(:'q_plans_differ'::boolean,
  'Q2 with 425''s text the refund and cancellation plans of Mike''s invoices are not what they were (P7 has teeth)');

-- ═════ The merge (445) ═════
do $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  r := public.merge_customer_records(pg_temp.fx('kilo'), pg_temp.fx('mike'), 'T445 the same person', pg_temp.fx('owner'));
  perform pg_temp.put('ans445', r::text);
end $$;
select pg_temp.check(pg_temp.tx('ans445')::jsonb = :'ans425'::jsonb
    and (pg_temp.tx('ans445')::jsonb ->> 'success')::boolean
    and pg_temp.tx('ans445')::jsonb -> 'moved' ? 'invoices.customer_id',
  'N1 the merge''s answer is 425''s, to the letter: ' || pg_temp.tx('ans445'));
select pg_temp.check(pg_temp.world(pg_temp.fx('kilo'), pg_temp.fx('mike')) = :'world425',
  'N2 everything but the credit''s origin is as 425 leaves it: the audit rows, every record naming Kilo or Mike, the customers, the wallets, the ledger rows, the benefit values and sales but for their lots, the new lots but for source, record and link');
select pg_temp.check((select count(*) from public.audit_logs a where a.action = 'customers_merged' and a.record_id = pg_temp.fx('kilo')
                        and a.new_data ->> 'merged_from' = pg_temp.fx('mike')::text
                        and a.new_data ->> 'request_id' = pg_temp.fx('owner')::text) = 1
    and (pg_temp.err(format('select public.merge_customer_records(%L, %L, %L, %L)', pg_temp.fx('kilo'), pg_temp.fx('mike'),
                            'T445 the same person', pg_temp.fx('owner'))) = 'ok')
    and (public.merge_customer_records(pg_temp.fx('kilo'), pg_temp.fx('mike'), 'T445 the same person', pg_temp.fx('owner')) ->> 'replayed')::boolean,
  'N3 one customers_merged audit row; the same request again is a replay that changes nothing');

-- ═════ O Each lot carried over as the same credit ═════
do $$
declare n_bad int; v text;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  select count(*), string_agg(s.lot::text, ', ') into n_bad, v
    from snap s
    left join public.customer_credit_lots o on o.id = s.lot
    left join public.customer_credit_lots n on n.reassigned_from_lot_id = s.lot
   where s.who = 'mike'
     and not (o.remaining_amount = 0 and o.customer_id = pg_temp.fx('mike') and o.status = 'active'
              and n.customer_id = pg_temp.fx('kilo') and n.status = 'active'
              and n.category = s.category and n.source_type = s.source_type
              and n.source_record_id is not distinct from s.source_record_id
              and n.usage_restrictions = s.usage_restrictions and n.store_id is not distinct from s.store_id
              and n.effective_date = s.effective_date and n.original_purchase_date is not distinct from s.original_purchase_date
              and n.original_amount = s.remaining and n.remaining_amount = s.remaining
              and n.wallet_id = (select id from public.customer_credit_wallets where customer_id = pg_temp.fx('kilo'))
              and (select count(*) from public.customer_credit_lots x where x.reassigned_from_lot_id = s.lot) = 1);
  perform pg_temp.check(n_bad = 0,
    'O1 each of Mike''s 14 lots with credit left is drawn down, and Kilo has one new lot linked to it (reassigned_from_lot_id) with the same '
    || 'category, source_type, source_record_id, restrictions, store, effective and purchase dates, and what was left' || coalesce(': ' || v, ''));
  select count(*), string_agg(s.lot::text || ' ' || s.policy || '/' || s.grp || ' -> '
                              || public.credit_lot_policy_for(pg_temp.kept(s.lot)) || '/' || public.credit_lot_source_group(pg_temp.kept(s.lot)), '; ')
    into n_bad, v
    from snap s
   where s.who = 'mike'
     and (public.credit_lot_policy_for(pg_temp.kept(s.lot)) is distinct from s.policy
          or public.credit_lot_source_group(pg_temp.kept(s.lot)) is distinct from s.grp);
  perform pg_temp.check(n_bad = 0,
    'O2 each new lot has its original''s spending rule and source group (package Paid and Bonus, bundle, the linked Legacy as bundle, moved credit as its package, open other)'
    || coalesce(': ' || v, ''));
  perform pg_temp.check(not exists (select 1 from public.customer_credit_lots where source_type = 'customer_merge')
      and (select count(*) from public.customer_credit_lots where customer_id = pg_temp.fx('kilo')) = 15
      and (select count(*) from public.customer_credit_lots where customer_id = pg_temp.fx('mike') and remaining_amount > 0) = 0
      and (select remaining_amount from public.customer_credit_lots where id = pg_temp.fx('kilo_ob')) = 25,
    'O3 no ''customer_merge'' lot; Kilo holds his own lot and the 14 new ones; Mike holds none with credit left');
  perform pg_temp.check(
    (select count(*) from public.customer_credit_ledger e join snap s on s.lot = e.lot_id
      where e.customer_id = pg_temp.fx('mike') and e.entry_type = 'adjust_decrease' and e.source_type = 'customer_merge_out'
        and e.source_record_id = pg_temp.fx('kilo') and e.amount = s.remaining) = 14
    and (select count(*) from public.customer_credit_ledger e join snap s on pg_temp.kept(s.lot) = e.lot_id
          where e.customer_id = pg_temp.fx('kilo') and e.entry_type = 'grant' and e.source_type = 'customer_merge_in'
            and e.source_record_id = pg_temp.fx('mike') and e.amount = s.remaining and e.category = s.category) = 14,
    'O4 the ledger says what happened, as before: each lot drawn down at Mike (customer_merge_out) and granted at Kilo (customer_merge_in), same amounts');
end $$;

-- ═════ B Balances: Kilo's and Mike's added up, nothing counted twice ═════
do $$
declare bk jsonb; bm jsonb; b0k jsonb := pg_temp.tx('bal_kilo')::jsonb; b0m jsonb := pg_temp.tx('bal_mike')::jsonb;
  ok boolean := true; g text; c text; pk jsonb; pm jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  bk := public.customer_credit_balances(pg_temp.fx('kilo'));
  bm := public.customer_credit_balances(pg_temp.fx('mike'));
  foreach c in array array['paid', 'bonus', 'legacy', 'promotional', 'exchange'] loop
    ok := ok and (bk -> 'categories' ->> c)::numeric = (b0k -> 'categories' ->> c)::numeric + (b0m -> 'categories' ->> c)::numeric;
    foreach g in array array['credit_package', 'premium_bundle', 'other'] loop
      ok := ok and (bk -> 'sources' -> g ->> c)::numeric = (b0k -> 'sources' -> g ->> c)::numeric + (b0m -> 'sources' -> g ->> c)::numeric;
    end loop;
  end loop;
  perform pg_temp.check(ok and (bk ->> 'available_total')::numeric = 3497
      and (bk ->> 'available_total')::numeric = (b0k ->> 'available_total')::numeric + (b0m ->> 'available_total')::numeric
      and (bk -> 'sources' -> 'credit_package' ->> 'total')::numeric = 2180
      and (bk -> 'sources' -> 'premium_bundle' ->> 'total')::numeric = 1115
      and (bk -> 'sources' -> 'other' ->> 'total')::numeric = 202,
    'B1 Kilo''s balance is his and Mike''s added up, category by category and source by source (Credit Package 2180, Premium Bundle 1115, Other 202; 3497): ' || (bk -> 'sources')::text);
  perform pg_temp.check((bm ->> 'available_total')::numeric = 0 and jsonb_array_length(bm -> 'purchases') = 0
      and (bm -> 'sources' -> 'credit_package' ->> 'total')::numeric = 0,
    'B2 Mike''s balance is empty and lists no purchase');
  -- Kilo's purchases: Mike's, the same entries (invoice, name, kind, what is left).
  select jsonb_agg(x - 'invoice_id' - 'received' order by x::text) into pk from jsonb_array_elements(bk -> 'purchases') x;
  select jsonb_agg(x - 'invoice_id' - 'received' order by x::text) into pm from jsonb_array_elements(b0m -> 'purchases') x;
  perform pg_temp.check(pk = pm and jsonb_array_length(bk -> 'purchases') = 5
      and (select count(*) from jsonb_array_elements(bk -> 'purchases') x where (x ->> 'received')::boolean) = 1
      and (select x ->> 'invoice_no' from jsonb_array_elements(bk -> 'purchases') x where (x ->> 'received')::boolean)
          = (select invoice_no from public.invoices where id = pg_temp.fx('x3'))
      and (select (x ->> 'total')::numeric from jsonb_array_elements(bk -> 'purchases') x
            where x ->> 'invoice_no' = (select invoice_no from public.invoices where id = pg_temp.fx('x1'))) = 880
      and (select (x ->> 'total')::numeric from jsonb_array_elements(bk -> 'purchases') x
            where x ->> 'invoice_no' = (select invoice_no from public.invoices where id = pg_temp.fx('x2'))) = 595,
    'B3 Kilo''s purchases are Mike''s, each with what is left (the package 880, the bundle 595 with its linked Legacy, the part-paid package 300, '
    || 'the second bundle 520); Charlie''s package moved in is still ''received'': ' || (bk -> 'purchases')::text);
end $$;

-- ═════ P The purchase records name Kilo's lots ═════
do $$
declare k uuid := pg_temp.fx('kilo');
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform pg_temp.check(
    (select (s.credit_lot_id, s.bonus_credit_lot_id) from public.credit_package_sales s where s.invoice_id = pg_temp.fx('x1'))
      = (pg_temp.kept(pg_temp.fx('p_paid')), pg_temp.kept(pg_temp.fx('p_bonus')))
    and (select (s.paid_credit_lot_id, s.bonus_credit_lot_id) from public.premium_bundle_sales s where s.invoice_id = pg_temp.fx('x2'))
      = (pg_temp.kept(pg_temp.fx('b_paid')), pg_temp.kept(pg_temp.fx('b_bonus')))
    and (select s.paid_credit_lot_id from public.premium_bundle_sales s where s.invoice_id = pg_temp.fx('x5')) = pg_temp.kept(pg_temp.fx('b2_paid'))
    and (select s.customer_id from public.credit_package_sales s where s.invoice_id = pg_temp.fx('x1')) = k,
    'P1 the sales name Kilo''s lots (package Paid and Bonus, bundle Paid and Bonus)');
  perform pg_temp.check(
    (select count(*) from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id
      where b.invoice_id in (pg_temp.fx('x1'), pg_temp.fx('x2')) and l.customer_id = k
        and l.reassigned_from_lot_id in (pg_temp.fx('p_paid'), pg_temp.fx('p_bonus'), pg_temp.fx('b_paid'), pg_temp.fx('b_bonus'))) = 4
    and not exists (select 1 from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id
                     where b.invoice_id in (pg_temp.fx('x1'), pg_temp.fx('x2')) and l.customer_id = pg_temp.fx('mike'))
    and (select l.customer_id from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id
          where b.id = pg_temp.fx('moved_benefit')) = k,
    'P2 the benefit values name Kilo''s lots, Charlie''s moved one too (on Charlie''s invoice)');
  perform pg_temp.check(
    (select array_agg(lot_id order by lot_id) from public.invoice_credit_lot_ids(pg_temp.fx('x1')))
      = (select array_agg(x order by x) from unnest(array[pg_temp.kept(pg_temp.fx('p_paid')), pg_temp.kept(pg_temp.fx('p_bonus'))]) x)
    and (select bool_and(l.customer_id = k) from public.invoice_credit_lot_ids(pg_temp.fx('x2')) i
           join public.customer_credit_lots l on l.id = i.lot_id where l.remaining_amount > 0)
    and pg_temp.kept(pg_temp.fx('link')) in (select lot_id from public.invoice_credit_lot_ids(pg_temp.fx('x2'))),
    'P3 invoice_credit_lot_ids finds Kilo''s lots for Mike''s invoices (the linked Legacy lot through its link)');
  perform pg_temp.check(
    (select lot_id from public.credit_package_progress_lots where invoice_id = pg_temp.fx('x4')) = pg_temp.fx('released')
    and public.credit_lot_current(pg_temp.fx('released')) = pg_temp.kept(pg_temp.fx('released'))
    and public.credit_lot_chain(pg_temp.fx('released')) = array[pg_temp.fx('released'), pg_temp.kept(pg_temp.fx('released'))]
    and (select released_amount from public.credit_package_progress_lots where invoice_id = pg_temp.fx('x4')) = 300,
    'P4 credit released before settlement: its record still names the lot it released, and is followed along to Kilo''s (credit_lot_current)');
  perform pg_temp.check(
    public.invoice_credit_transfer_origin(pg_temp.kept(pg_temp.fx('moved')))
      = (select credit_lot_id from public.credit_package_sales where invoice_id = pg_temp.fx('x3'))
    and (select source_type from public.customer_credit_lots where id = pg_temp.kept(pg_temp.fx('moved'))) = 'invoice_benefit_transfer'
    and (select customer_id from public.invoice_benefit_transfers where id =
          (select source_record_id from public.customer_credit_lots where id = pg_temp.kept(pg_temp.fx('moved')))) = k,
    'P5 the moved credit is still moved credit, traced through its transfer to Charlie''s package lot');
  perform pg_temp.check(
    (select string_agg(distinct x ->> 'customer_id', ',') from jsonb_array_elements(public.invoice_refund_options_before_sessions(pg_temp.fx('x1')) -> 'benefits') x) = k::text
    and (select sum((x ->> 'max_refund')::numeric) from jsonb_array_elements(public.invoice_refund_options_before_sessions(pg_temp.fx('x1')) -> 'benefits') x) > 0
    and (select x ->> 'customer_id' from jsonb_array_elements(public.invoice_refund_options_before_sessions(pg_temp.fx('x3')) -> 'benefits') x
          where x ->> 'id' = pg_temp.fx('moved_benefit')::text) = k::text,
    'P6 the refund options of Mike''s package and of Charlie''s name Kilo as the holder, with credit to take back');
  perform pg_temp.check(pg_temp.plans(false) = pg_temp.tx('plans0'),
    'P7 the guided refund and cancellation plans of Mike''s invoices and of Charlie''s are what they were before the merge, '
    || 'Kilo in Mike''s place: the same credit to remove, money back, overrides and blockers'
    || coalesce(': first difference ' || (select left(a.l, 600) || ' WAS ' || left(b.l, 600)
                 from unnest(string_to_array(pg_temp.plans(false), E'\n')) with ordinality a(l, n)
                 join unnest(string_to_array(pg_temp.tx('plans0'), E'\n')) with ordinality b(l, n) on a.n = b.n
                where a.l is distinct from b.l order by a.n limit 1), ''));
end $$;

-- ═════ E A lot whose benefit value an Owner moved on keeps its records ═════
do $$
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  -- (Where 462 is in, the sale and the benefit value follow to Kilo's lot
  -- too, and Delta's credit is still traced to the bundle, through the
  -- Move's own ledger rows.)
  perform pg_temp.check(
    (select s.bonus_credit_lot_id from public.premium_bundle_sales s where s.invoice_id = pg_temp.fx('x5'))
      = case when pg_temp.with_462() then pg_temp.kept(pg_temp.fx('b2_bonus')) else pg_temp.fx('b2_bonus') end
    and exists (select 1 from public.invoice_benefit_values b
                 where b.lot_id = case when pg_temp.with_462() then pg_temp.kept(pg_temp.fx('b2_bonus')) else pg_temp.fx('b2_bonus') end)
    and (select remaining_amount from public.customer_credit_lots where id = pg_temp.kept(pg_temp.fx('b2_bonus'))) = 20
    and public.credit_lot_source_group(pg_temp.kept(pg_temp.fx('b2_bonus'))) = 'premium_bundle'
    and public.invoice_credit_transfer_origin(pg_temp.fx('delta_lot')) = pg_temp.fx('b2_bonus')
    and public.credit_lot_policy_for(pg_temp.fx('delta_lot')) = 'bundle_any'
    and public.credit_lot_source_group(pg_temp.fx('delta_lot')) = 'premium_bundle',
    'E1 the second bundle''s Bonus, moved on to Delta: its sale and benefit value stay on Mike''s lot (462: follow to Kilo''s), so Delta''s credit is still traced to the bundle; '
    || 'Kilo still gets the 20 left, as bundle credit');
end $$;

-- ═════ A / W Each wallet method pays the merged credit, by its rules ═════
do $$
declare k uuid := pg_temp.fx('kilo'); inv uuid; p uuid; a jsonb; v text;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  -- A therapy session and an own-brand product.
  inv := pg_temp.invoice(k, pg_temp.therapy(1) || pg_temp.product('own'));
  a := public.invoice_wallet_availability(inv);
  select string_agg((x ->> 'name') || '=' || trim_scale((x ->> 'available')::numeric) || '/' || trim_scale((x ->> 'held')::numeric),
                    '; ' order by (x ->> 'rank')::int) into v
    from jsonb_array_elements(a -> 'methods') x where x ->> 'name' like 'Wallet —%';
  perform pg_temp.check(v = 'Wallet — Credit Package Paid=100/2080; Wallet — Credit Package Bonus=40/100; '
      || 'Wallet — Premium Bundle Paid=140/1000; Wallet — Premium Bundle Bonus=70/70; Wallet — Paid Credit=95/95; '
      || 'Wallet — Bonus Credit=20/20; Wallet — Legacy Credit=105/105; Wallet — Promotional/FOC Credit=15/15; '
      || 'Wallet — Exchange Credit=12/12',
    'A1 Record Payment holds Kilo''s merged credit under its own methods (what each can pay of a session and a product / what it holds): ' || v);
  -- W1 Credit Package Paid pays the session (package Paid credit buys therapy sessions).
  p := pg_temp.pay(inv, 'Wallet — Credit Package Paid', 100);
  perform pg_temp.put('w1_pay', p::text); perform pg_temp.putx('w1_inv', inv);
  perform pg_temp.put('w1_lots', (select string_agg(a.lot_id::text || ':' || a.amount, ',' order by a.lot_id) from public.invoice_line_credit_allocations a where a.payment_id = p));
  perform pg_temp.check(pg_temp.pay_lots(p) = 'credit_package:paid'
      and (select bool_and(l.customer_id = k and l.reassigned_from_lot_id is not null) from public.invoice_line_credit_allocations a
             join public.customer_credit_lots l on l.id = a.lot_id where a.payment_id = p),
    'W1 Wallet — Credit Package Paid pays the session from Kilo''s merged package Paid credit');
  -- W2 Credit Package Bonus pays the product, not a session.
  p := pg_temp.pay(inv, 'Wallet — Credit Package Bonus', 40);
  perform pg_temp.check(pg_temp.pay_lots(p) = 'credit_package:bonus'
      and (select a.lot_id from public.invoice_line_credit_allocations a where a.payment_id = p) = pg_temp.kept(pg_temp.fx('p_bonus'))
      and (select status::text from public.invoices where id = inv) = 'paid',
    'W2 Wallet — Credit Package Bonus pays the own-brand product from the merged package Bonus');
  inv := pg_temp.invoice(k, pg_temp.therapy(1));
  perform pg_temp.check(pg_temp.err(format('select public.record_invoice_payment(%L, %L, %L)', inv,
      jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.method('Wallet — Credit Package Bonus'), 'amount', 1)),
      gen_random_uuid())) like '%could be funded by eligible credit%',
    'W3 the merged package Bonus still cannot pay a therapy session (its rule)');
  -- W4 Paid Credit (other Paid only): 95 = Kilo's 25 + Mike's opening 70; not a cent more.
  perform pg_temp.check(pg_temp.err(format('select public.record_invoice_payment(%L, %L, %L)', inv,
      jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.method('Wallet — Paid Credit'), 'amount', 95.01)),
      gen_random_uuid())) like '%Only 95.00 of the requested 95.01 could be funded by eligible credit%',
    'W4 Wallet — Paid Credit reaches other Paid credit only (95), never the merged package or bundle Paid');
  p := pg_temp.pay(inv, 'Wallet — Paid Credit', 95);
  perform pg_temp.check(pg_temp.pay_lots(p) = 'other:paid'
      and (select count(distinct a.lot_id) from public.invoice_line_credit_allocations a where a.payment_id = p) = 2,
    'W5 it pays 95 from Kilo''s own opening balance and Mike''s, carried over');
  -- W6 Premium Bundle Paid and Bonus, Bonus Credit, Promotional, Exchange, Legacy on products
  -- (150). Legacy 65: Mike's opening Legacy (60, the older) first, then 5 of
  -- the Legacy linked to his bundle line (Premium Bundle).
  inv := pg_temp.invoice(k, pg_temp.product('third') || pg_temp.product('own') || pg_temp.product('own') || pg_temp.product('own'));
  perform pg_temp.putx('w6_inv', inv);
  p := pg_temp.pay(inv, 'Wallet — Premium Bundle Paid', 18);
  v := pg_temp.pay_lots(p);
  p := pg_temp.pay(inv, 'Wallet — Premium Bundle Bonus', 20);
  v := v || ' ' || pg_temp.pay_lots(p);
  p := pg_temp.pay(inv, 'Wallet — Bonus Credit', 20);
  v := v || ' ' || pg_temp.pay_lots(p);
  p := pg_temp.pay(inv, 'Wallet — Promotional/FOC Credit', 15);
  v := v || ' ' || pg_temp.pay_lots(p);
  p := pg_temp.pay(inv, 'Wallet — Exchange Credit', 12);
  v := v || ' ' || pg_temp.pay_lots(p);
  p := pg_temp.pay(inv, 'Wallet — Legacy Credit', 65);
  v := v || ' ' || pg_temp.pay_lots(p);
  perform pg_temp.check(v = 'premium_bundle:paid premium_bundle:bonus other:bonus other:promotional other:exchange other:legacy,premium_bundle:legacy'
      and (select status::text from public.invoices where id = inv) = 'paid'
      and (select bool_and(l.customer_id = k) from public.invoice_line_credit_allocations a join public.customer_credit_lots l on l.id = a.lot_id
            where a.invoice_id = inv)
      and (select string_agg(a.amount::text, ',' order by a.amount) from public.invoice_line_credit_allocations a
            where a.payment_id = p and a.lot_id = pg_temp.kept(pg_temp.fx('link'))) = '5.00',
    'W6 Premium Bundle Paid and Bonus, Bonus Credit, Promotional/FOC, Exchange and Legacy each pay from Kilo''s merged credit of their kind: ' || v);
end $$;

-- ═════ R Refunds and cancellations ═════
do $$
declare k uuid := pg_temp.fx('kilo'); r jsonb; before jsonb; v text; n numeric;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  -- R1 the session's payment refunded: the credit goes back on the Kilo lots it came from.
  select jsonb_object_agg(l.id, l.remaining_amount) into before from public.customer_credit_lots l where l.customer_id = k;
  perform public.refund_invoice_recorded(pg_temp.fx('w1_inv'),
    jsonb_build_array(jsonb_build_object('invoice_item_id',
      (select id from public.invoice_items where invoice_id = pg_temp.fx('w1_inv') and line_kind::text = 'therapy'), 'amount', 100)),
    jsonb_build_array(jsonb_build_object('payment_id', pg_temp.tx('w1_pay')::uuid, 'amount', 100)), '[]'::jsonb, 'T445 refund the session', gen_random_uuid());
  select string_agg(l.id::text || ':' || (l.remaining_amount - (before ->> l.id::text)::numeric), ',' order by l.id) into v
    from public.customer_credit_lots l where l.customer_id = k and l.remaining_amount <> (before ->> l.id::text)::numeric;
  perform pg_temp.check(v = pg_temp.tx('w1_lots')
      and not exists (select 1 from public.customer_credit_lots l where l.customer_id = pg_temp.fx('mike') and l.remaining_amount > 0),
    'R1 a refund of a payment made after the merge puts the credit back on the very Kilo lots it came from (' || coalesce(v, 'none') || ')');
  -- R2 Mike's package invoice refunded in full. 40 of its Bonus was spent
  -- (W2) and 220 of its Paid taken back by the part refund (fixtures), so the
  -- plan asks an override for each, and the money kept for the spent Bonus
  -- stays (the refund's own rule): S$763.64 back of the S$800 held. What is
  -- left of its credit (Paid 780, Bonus 60) is taken back from Kilo's lots,
  -- and nothing from Mike's.
  r := pg_temp.guided(pg_temp.fx('x1'), 'refund_full', true);
  perform pg_temp.check((r -> 'result' ->> 'status') = 'approved' and (r -> 'result' ->> 'refund_recorded')::boolean
      and (r -> 'plan' ->> 'refund_amount')::numeric = 763.64
      and (select string_agg(x ->> 'kind' || ' ' || (x ->> 'credit_removed') || ' ' || (x ->> 'holder_id'), ', ' order by x ->> 'kind')
             from jsonb_array_elements(r -> 'plan' -> 'effects' -> 'benefits') x) = 'bonus 60.00 ' || k || ', paid 780.00 ' || k
      and (select remaining_amount from public.customer_credit_lots where id = pg_temp.kept(pg_temp.fx('p_paid'))) = 0
      and (select remaining_amount from public.customer_credit_lots where id = pg_temp.kept(pg_temp.fx('p_bonus'))) = 0
      and (select string_agg(e.category || ' ' || e.amount, ', ' order by e.category) from public.customer_credit_ledger e
            where e.customer_id = k and e.source_type = 'invoice_benefit_refund'
              and e.lot_id in (pg_temp.kept(pg_temp.fx('p_paid')), pg_temp.kept(pg_temp.fx('p_bonus')))) = 'bonus 60.00, paid 780.00'
      and (select count(*) from public.customer_credit_ledger e
            where e.customer_id = pg_temp.fx('mike') and e.source_type = 'invoice_benefit_refund') = 1
      and (select (x ->> 'total')::numeric from jsonb_array_elements(public.customer_credit_balances(k) -> 'purchases') x
            where x ->> 'invoice_no' = (select invoice_no from public.invoices where id = pg_temp.fx('x1'))) = 0,
    'R2 a full refund of Mike''s package invoice takes what is left of its credit (Paid 780, Bonus 60) back from Kilo''s lots, none from Mike''s '
    || '(the fixtures'' part refund is his one), S$763.64 back (the spent Bonus''s value kept); his purchases show it used up: '
    || coalesce(r -> 'result' ->> 'status', '?') || ' ' || coalesce(r -> 'plan' ->> 'refund_amount', '?') || ' '
    || coalesce((r -> 'plan' -> 'effects' -> 'benefits')::text, ''));
  -- R3 Mike's bundle invoice cancelled: its credit is taken back from Kilo, and the Legacy lot linked to its line is written off.
  n := (select remaining_amount from public.customer_credit_lots where id = pg_temp.kept(pg_temp.fx('b_paid')));
  r := pg_temp.guided(pg_temp.fx('x2'), 'cancel', false);
  perform pg_temp.check((select status::text from public.invoices where id = pg_temp.fx('x2')) = 'cancelled'
      and (select remaining_amount from public.customer_credit_lots where id = pg_temp.kept(pg_temp.fx('b_paid'))) = 0
      and (select remaining_amount from public.customer_credit_lots where id = pg_temp.kept(pg_temp.fx('b_bonus'))) = 0
      and (select remaining_amount || ' ' || status from public.customer_credit_lots where id = pg_temp.kept(pg_temp.fx('link'))) = '0.00 reversed'
      and (select remaining_amount from public.customer_credit_lots where id = pg_temp.fx('link')) = 0,
    'R3 a cancellation of Mike''s bundle invoice takes its credit back from Kilo (' || n || ' Paid left before), and writes off the Legacy lot linked to its line, at Kilo: '
    || coalesce(r -> 'result' ->> 'status', '?'));
end $$;

-- ═════ S Mike's part-paid package, settled by Kilo ═════
do $$
declare k uuid := pg_temp.fx('kilo'); inv uuid := pg_temp.fx('x4'); r jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform pg_temp.pay(inv, 'T445 Cash', 700);
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'paid'
      and (select coalesce(sum(l.original_amount), 0) from public.customer_credit_lots l
            where l.customer_id = k and l.category = 'paid' and l.status <> 'reversed'
              and l.id in (select lot_id from public.invoice_credit_lot_ids(inv))) = 1000
      and (select coalesce(sum(l.original_amount), 0) from public.customer_credit_lots l
            where l.customer_id = k and l.category = 'bonus'
              and l.id in (select lot_id from public.invoice_credit_lot_ids(inv))) = 100
      and (select count(*) from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id
            where b.invoice_id = inv and l.customer_id = k) = 3
      and exists (select 1 from public.invoice_benefit_values b where b.invoice_id = inv and b.lot_id = pg_temp.kept(pg_temp.fx('released'))),
    'S1 Kilo pays the rest of Mike''s part-paid package: Paid 1000 in all (the 300 released before the merge and 700 now, nothing given twice), Bonus 100, '
    || 'and its benefit values name Kilo''s lots, the released one too');
  r := pg_temp.guided(inv, 'refund_full', true);
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'refunded'
      and (select coalesce(sum(l.remaining_amount), 0) from public.customer_credit_lots l
            where l.id in (select lot_id from public.invoice_credit_lot_ids(inv))) = 0,
    'S2 a full refund of it takes all of its credit back from Kilo: ' || coalesce(r -> 'result' ->> 'status', '?'));
end $$;

-- ═════ C A share of a shared package (invoice_credit_splits, 141) ═════
do $$
declare o uuid := pg_temp.fx('oscar'); p uuid := pg_temp.fx('papa'); q uuid := pg_temp.fx('quebec');
  inv uuid; item uuid; v_lot uuid; v_new uuid; v_before text; r jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  -- Quebec buys the package and shares it with Oscar (400 / 600), paid in
  -- cash: a 141 split (set_invoice_credit_split, the server's alone now; the
  -- app splits with child lines since 153), as older invoices hold them.
  inv := pg_temp.invoice(q, jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.fx('pk'), 'quantity', 1)));
  select id into item from public.invoice_items where invoice_id = inv;
  perform public.set_invoice_credit_split(item, jsonb_build_array(jsonb_build_object('customer_id', q, 'amount', 400),
                                                                  jsonb_build_object('customer_id', o, 'amount', 600)));
  perform pg_temp.pay(inv, 'T445 Cash', 1000);
  select issued_lot_id into v_lot from public.invoice_credit_splits where invoice_id = inv and customer_id = o;
  select string_agg(trim_scale(x.amount) || '/' || trim_scale(x.remaining) || '/' || x.spent, ',' order by x.amount) into v_before
    from public.invoice_credit_split(inv) x;
  perform pg_temp.check(v_lot is not null and (select customer_id from public.customer_credit_lots where id = v_lot) = o
      and (select remaining_amount from public.customer_credit_lots where id = v_lot) > 0,
    'C0 the fixture: Oscar holds his share''s lot (' || coalesce(v_before, '?') || ')');
  r := public.merge_customer_records(p, o, 'T445 the same person (share)', gen_random_uuid());
  select id into v_new from public.customer_credit_lots where reassigned_from_lot_id = v_lot;
  perform pg_temp.check(
    (select string_agg(trim_scale(x.amount) || '/' || trim_scale(x.remaining) || '/' || x.spent, ',' order by x.amount)
       from public.invoice_credit_split(inv) x) = v_before
    and (select (x.customer_id, x.issued_lot_id, x.spent) from public.invoice_credit_split(inv) x where x.amount = 600) = (p, v_new, false)
    and (select customer_id from public.customer_credit_lots where id = v_new) = p
    and (select credit_lot_id from public.credit_package_sales where invoice_id = inv and customer_id = p) = v_new
    and public.credit_lot_policy_for(v_new) = 'package_paid' and public.credit_lot_source_group(v_new) = 'credit_package'
    and v_new in (select lot_id from public.invoice_credit_lot_ids(inv)),
    'C1 after Oscar is merged into Papa, the shared package''s split names Papa''s new lot, unspent, as it read before (' || coalesce(v_before, '?')
    || '); the share''s sale names it; it is package Paid credit');
end $$;

-- ═════ V Merged credit moved on (445's 3.) ═════
-- Victor buys the package and pays 300 (Paid 300 released before
-- settlement); Victor is merged into Uniform, who pays the other 700; an
-- Owner moves the released credit to Zulu (Move). Then, each undone after:
-- a refund of S$100 of Zulu's credit, and the invoice reassigned to Yankee
-- with its credit (correct_invoice, benefit_action 'transfer', 321).
create function pg_temp.v_run() returns jsonb language plpgsql as
$$declare v uuid; u uuid; z uuid; y uuid; inv uuid; item uuid; rel uuid; kept uuid; rel_b uuid; zb uuid; zl uuid;
  pay uuid; r jsonb; res jsonb; u_before numeric; v_refund text; v_reassign text;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  if exists (select 1 from public.customers where phone like '+6149157085_') then
    raise exception 'FIXTURE: a customer already uses the test phones +6149157085x'; end if;
  insert into public.customers(full_name, phone) values ('T445 Victor', '+61491570850') returning id into v;
  insert into public.customers(full_name, phone) values ('T445 Uniform', '+61491570851') returning id into u;
  insert into public.customers(full_name, phone) values ('T445 Zulu', '+61491570852') returning id into z;
  insert into public.customers(full_name, phone) values ('T445 Yankee', '+61491570853') returning id into y;
  inv := pg_temp.invoice(v, jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.fx('pk'), 'quantity', 1)));
  select id into item from public.invoice_items where invoice_id = inv;
  perform pg_temp.pay(inv, 'T445 Cash', 300);
  select lot_id into rel from public.credit_package_progress_lots where invoice_id = inv;
  perform public.merge_customer_records(u, v, 'T445 the same person (Move)', gen_random_uuid());
  pay := pg_temp.pay(inv, 'T445 Cash', 700);
  select id into kept from public.customer_credit_lots where reassigned_from_lot_id = rel and customer_id = u;
  select id into rel_b from public.invoice_benefit_values where invoice_id = inv and lot_id = kept;
  r := public.transfer_invoice_unused_benefit(rel_b, z, pg_temp.fx('st'), 'T445 move the released credit to Zulu', gen_random_uuid());
  zb := (r ->> 'benefit_id')::uuid;
  select lot_id into zl from public.invoice_benefit_values where id = zb;
  res := jsonb_build_object(
    'z_lot', (select l.category || ' ' || l.source_type || ' ' || l.original_amount || '/' || l.remaining_amount
                from public.customer_credit_lots l where l.id = zl and l.customer_id = z),
    'z_link_is_null', (select l.reassigned_from_lot_id is null from public.customer_credit_lots l where l.id = zl),
    'z_link_is_rel', (select l.reassigned_from_lot_id = rel from public.customer_credit_lots l where l.id = zl),
    'lots_linked_to_rel', (select count(*) from public.customer_credit_lots l where l.reassigned_from_lot_id = rel),
    'chain_to_kept', public.credit_lot_chain(rel) = array[rel, kept] and public.credit_lot_current(rel) = kept,
    'z_in_invoice_lots', zl in (select x.lot_id from public.invoice_credit_lot_ids(inv) x),
    'source_released', pg_temp.err(format('select public.invoice_commission_benefit_source(%L)', rel_b)),
    'source_moved', pg_temp.err(format('select public.invoice_commission_benefit_source(%L)', zb)));
  -- A refund of S$100 of Zulu's moved credit (from the S$700 payment): undone after.
  select sum(remaining_amount) into u_before from public.customer_credit_lots where customer_id = u;
  begin
    perform public.refund_invoice_recorded(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', 100,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', zb, 'amount', 100)))),
      jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 100)), '[]'::jsonb, 'T445 refund part of the moved credit', gen_random_uuid());
    v_refund := 'ok zulu ' || (select original_amount || '/' || remaining_amount from public.customer_credit_lots where id = zl)
      || ' uniform ' || case when (select sum(remaining_amount) from public.customer_credit_lots where customer_id = u) = u_before
                             then 'unchanged' else 'changed' end;
    raise exception using errcode = 'P0446', message = 'T445 undo the refund';
  exception when sqlstate 'P0446' then null;
            when others then v_refund := sqlstate || ' ' || sqlerrm;
  end;
  -- The invoice reassigned to Yankee with its credit: undone after.
  begin
    perform public.correct_invoice(inv,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.fx('pk'), 'quantity', 1, 'invoice_item_id', item)),
      jsonb_build_object('customer_id', y, 'store_id', pg_temp.fx('st'), 'benefit_action', 'transfer'), 'T445 wrong customer', gen_random_uuid());
    v_reassign := 'ok zulu ' || (select original_amount || '/' || remaining_amount from public.customer_credit_lots where id = zl)
      || ' yankee ' || coalesce((select string_agg(l.category || ' ' || l.source_type || ' ' || l.remaining_amount, ', '
                                                   order by l.category, l.source_type, l.remaining_amount)
                                   from public.customer_credit_lots l where l.customer_id = y), '-');
    raise exception using errcode = 'P0446', message = 'T445 undo the reassignment';
  exception when sqlstate 'P0446' then null;
            when others then v_reassign := sqlstate || ' ' || sqlerrm;
  end;
  return res || jsonb_build_object('refund', v_refund, 'reassign', v_reassign);
end$$;
-- With Move's old text (191's), rebuilt from 445's and checked by its md5: undone.
savepoint v_old;
do $$
declare t text := pg_get_functiondef('public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure);
  c445 constant text := $c$  -- 445: but not its link to a lot it replaced (reassigned_from_lot_id: an
  -- invoice reassignment's, 321, or a merge's): moved credit is traced through
  -- its transfer (invoice_credit_transfer_origin). A copied link made the
  -- recipient's lot read as the invoice's own credit (credit_lot_chain,
  -- invoice_credit_lot_ids).
$c$;
begin
  t := replace(replace(t, c445, ''), '''reversal_of_lot_id'',null,''reassigned_from_lot_id'',null,', '''reversal_of_lot_id'',null,');
  if md5(t) <> 'ea7e8ce0612752c75ba75748c9275c42' then
    raise exception 'FIXTURE: Move''s old text could not be rebuilt (md5 %)', md5(t); end if;
  execute t;
end $$;
select pg_temp.v_run()::text as v_old \gset
rollback to savepoint v_old;
do $$
declare r jsonb;
begin
  r := pg_temp.v_run();
  perform pg_temp.put('v_new', r::text);
  perform pg_temp.check(r ->> 'z_lot' = 'paid invoice_benefit_transfer 300.00/300.00' and (r ->> 'z_link_is_null')::boolean
      and (r ->> 'lots_linked_to_rel')::int = 1
      and (r ->> 'chain_to_kept')::boolean and not (r ->> 'z_in_invoice_lots')::boolean,
    'V1 merged credit released before settlement, moved on to Zulu: Zulu''s lot has no link, the released credit is still followed to Uniform''s lot '
    || '(credit_lot_chain / credit_lot_current), and Zulu''s lot is not counted as the invoice''s: ' || r::text);
  perform pg_temp.check(r ->> 'source_released' = 'ok' and r ->> 'source_moved' = 'ok',
    'V2 the commission source of the released credit and of Zulu''s moved credit is found (the package''s sale): '
    || (r ->> 'source_released') || ' / ' || (r ->> 'source_moved'));
  perform pg_temp.check(r ->> 'refund' = 'ok zulu 300.00/190.00 uniform unchanged',
    'V3 a refund of S$100 of Zulu''s moved credit goes through, taking it back from Zulu alone: ' || (r ->> 'refund'));
  perform pg_temp.check(r ->> 'reassign' = 'ok zulu 300.00/300.00 yankee bonus credit_package 100.00, paid credit_package 700.00',
    'V4 the invoice reassigned to Yankee with its credit: Yankee gets the unused 700 Paid and 100 Bonus, Zulu keeps the moved 300: ' || (r ->> 'reassign'));
end $$;
-- (Here every step is in one transaction, so Uniform's and Zulu's lots have
-- the same created_at and which one credit_lot_chain takes is down to their
-- random ids; staff's steps are separate transactions, where the newer,
-- Zulu's, is always taken, as the review found. So the chain is checked
-- through what it reads, two lots linked to Victor's, and the refund as
-- what follows when the chain takes Zulu's.)
select pg_temp.check((:'v_old'::jsonb ->> 'z_link_is_rel')::boolean and (:'v_old'::jsonb ->> 'lots_linked_to_rel')::int = 2
    and (:'v_old'::jsonb ->> 'z_in_invoice_lots')::boolean
    and ((:'v_old'::jsonb ->> 'chain_to_kept')::boolean
         or (:'v_old'::jsonb ->> 'source_moved' like 'P0001 Commission review required%'
             and :'v_old'::jsonb ->> 'refund' like 'P0001 Commission review required%'))
    and :'v_old'::jsonb ->> 'reassign' like 'ok zulu 300.00/0.00 yankee %paid invoice_benefit_transfer 300.00%',
  'V0 with Move''s old text the same steps go wrong as found in review (V1-V4 have teeth): Zulu''s lot names Victor''s, so two lots claim to replace it '
  || '(the chain takes the newer; when that is Zulu''s, the refund is refused), Zulu''s lot counts as the invoice''s, and the reassignment takes '
  || 'Zulu''s credit to Yankee: ' || :'v_old');

-- ═════ X A duplicate who has spent wallet credit cannot be merged ═════
do $$
declare e445 text; e425 text; n_before bigint; n_after bigint;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  select count(*) into n_before from public.customer_credit_lots where customer_id = pg_temp.fx('tango');
  e445 := pg_temp.err(format('select public.merge_customer_records(%L, %L, %L, %L)', pg_temp.fx('tango'), pg_temp.fx('sierra'), 'T445 same', gen_random_uuid()));
  e425 := pg_temp.err(format('select pg_temp.merge_customer_records_425(%L, %L, %L, %L)', pg_temp.fx('tango'), pg_temp.fx('sierra'), 'T445 same', gen_random_uuid()));
  select count(*) into n_after from public.customer_credit_lots where customer_id = pg_temp.fx('tango');
  perform pg_temp.check(e445 like '%Credit allocations cannot be changed once recorded%' and e445 = e425 and n_before = n_after
      and (select deleted_at from public.customers where id = pg_temp.fx('sierra')) is null,
    'X1 a duplicate who has spent wallet credit cannot be merged, by 445 as by 425 (unchanged; NOT COVERED): ' || e445);
end $$;

do $$
declare n int; m text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, m from failed;
  if n > 0 then raise exception E'merge-credit-origin-445: % check(s) failed:\n  %', n, m; end if;
  raise notice 'merge-credit-origin-445: all checks passed';
end $$;
rollback;
