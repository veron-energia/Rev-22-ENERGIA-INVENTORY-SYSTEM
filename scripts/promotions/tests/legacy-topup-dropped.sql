-- The three-argument promotion_selections_topup is dropped (390).
--
--   C1 The overload installed below is production's, byte for byte (the md5
--      390 guards on), executable by service_role and by neither anon nor
--      staff, as it was.
--   C2 Beside the four-argument promotion_selections_topup no call reaches
--      it: three arguments, by position or by name, are refused as
--      ambiguous, while the callers' call (four arguments) reaches the
--      four-argument one.
--   C3 390 refuses a version of it that is not production's, and changes
--      nothing then.
--   C4 390 drops it, and only it: every other public function keeps its body
--      and its grants, and one promotion_selections_topup is left.
--   C5 A call with three arguments now reaches the four-argument function,
--      and the callers' call still does.
--   C6 Running 390 again changes nothing.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Works whether or not the database already has
-- 390: the old overload is installed after "begin;" either way.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
-- Every public function as signature, body and grants.
create function pg_temp.fns() returns table(fn text, h text) language sql as
$$ select p.oid::regprocedure::text, md5(p.prosrc) || ':' || coalesce(p.proacl::text, '')
     from pg_proc p where p.pronamespace = 'public'::regnamespace $$;
-- The SQLSTATE and message a call ends with ('' when it returns).
create function pg_temp.outcome(sql text) returns text language plpgsql as
$$begin execute sql; return '';
exception when others then return sqlstate || ' ' || sqlerrm; end$$;

-- Production's promotion_selections_topup(uuid,uuid,jsonb), read 3 Oct 2026,
-- with its grants.
create or replace function public.promotion_selections_topup(p_promotion_id uuid, p_store_id uuid, p_selections jsonb)
returns numeric language plpgsql stable security definer set search_path to 'public' as $legacy$
declare
  v_grp record; v_sel jsonb; v_opt jsonb; v_baseline numeric; v_price numeric;
  v_topup numeric := 0; v_qty integer;
begin
  for v_grp in select * from public.promotion_choice_groups
    where promotion_id = p_promotion_id and item_kind = 'product'
  loop
    select min(spp.selling_price) into v_baseline
    from public.promotion_choice_options o
    join public.store_product_prices spp
      on spp.product_id = o.product_id and spp.store_id = p_store_id
     and spp.is_active = true and spp.deleted_at is null
    where o.group_id = v_grp.id and o.product_id is not null;

    if v_baseline is null then continue; end if;

    for v_sel in select * from jsonb_array_elements(coalesce(p_selections,'[]'::jsonb))
    loop
      if (v_sel->>'group_id')::uuid <> v_grp.id then continue; end if;
      for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
      loop
        v_qty := coalesce((v_opt->>'quantity')::integer,0);
        if v_qty <= 0 or (v_opt->>'product_id') is null then continue; end if;
        -- LISTED options never pay a top-up: they are all covered by the
        -- bundle price, whatever their individual prices. Only products
        -- OUTSIDE the group's options pay the difference above the baseline.
        if exists (
          select 1 from public.promotion_choice_options o
          where o.group_id = v_grp.id and o.product_id = (v_opt->>'product_id')::uuid
        ) then continue; end if;
        select selling_price into v_price from public.store_product_prices
          where store_id = p_store_id and product_id = (v_opt->>'product_id')::uuid
            and is_active = true and deleted_at is null;
        if v_price is not null and v_price > v_baseline then
          v_topup := v_topup + (v_price - v_baseline) * v_qty;
        end if;
      end loop;
    end loop;
  end loop;
  return round(v_topup, 2);
end; $legacy$;
revoke all on function public.promotion_selections_topup(uuid,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.promotion_selections_topup(uuid,uuid,jsonb) to service_role;

select pg_temp.check(
  (select md5(prosrc) from pg_proc where oid = 'public.promotion_selections_topup(uuid,uuid,jsonb)'::regprocedure)
    = '96a78cad1688ca6d35a2fa36cf74d681'
  and has_function_privilege('service_role', 'public.promotion_selections_topup(uuid,uuid,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.promotion_selections_topup(uuid,uuid,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.promotion_selections_topup(uuid,uuid,jsonb)', 'execute'),
  'C1 the old promotion_selections_topup is production''s, executable by service_role and by neither staff nor anon');

-- A promotion with no product groups: every form returns 0, so a call's
-- outcome says only which function it reached.
create temp table calls(k text primary key, sql text);
insert into calls values
  ('three', $c$select public.promotion_selections_topup(gen_random_uuid(), gen_random_uuid(), '[]'::jsonb)$c$),
  ('named', $c$select public.promotion_selections_topup(p_promotion_id => gen_random_uuid(), p_store_id => gen_random_uuid(),
     p_selections => '[]'::jsonb)$c$);
-- What create_invoice, update_invoice_internal and reprice_invoice_lines send:
-- four arguments.
create temp table caller_call as select $c$select public.promotion_selections_topup(gen_random_uuid(), gen_random_uuid(),
  '[]'::jsonb, true)$c$ as sql;

select pg_temp.check(
  (select bool_and(pg_temp.outcome(sql) like '42725 function public.promotion_selections_topup(%) is not unique') from calls)
  and to_regproc('public.promotion_selections_topup') is null
  and (select pg_temp.outcome(sql) = '' from caller_call),
  'C2 beside the four-argument one, no call with three arguments, by position or by name, reaches it; the callers'' call reaches the four-argument one');

create temp table before390 as select * from pg_temp.fns();

-- C3: a version that is not production's.
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
savepoint c3;
do $$begin execute regexp_replace(pg_get_functiondef('public.promotion_selections_topup(uuid,uuid,jsonb)'::regprocedure),
  '\$function\$\s*$', E'-- changed\n$function$'); end$$;
\echo 'C3: the ERROR below is expected (390 refusing a changed promotion_selections_topup)'
\ir ../../../supabase/390_drop_legacy_promotion_selections_topup_overload.sql
\set c3_error :LAST_ERROR_MESSAGE
select count(*) = 2 as c3_both from pg_proc where pronamespace = 'public'::regnamespace and proname = 'promotion_selections_topup' \gset
rollback to savepoint c3;
release savepoint c3;
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP on
select pg_temp.check(:'c3_error' like '390: promotion_selections_topup(uuid,uuid,jsonb) is not the version this was tested against (md5 %)'
    and :'c3_both',
  'C3 390 refuses a promotion_selections_topup that is not production''s, and leaves both');

-- C4: the real thing.
set client_min_messages = warning;
\ir ../../../supabase/390_drop_legacy_promotion_selections_topup_overload.sql
reset client_min_messages;
select pg_temp.check(
  to_regprocedure('public.promotion_selections_topup(uuid,uuid,jsonb)') is null
  and (select array_agg(fn) from (select fn, h from before390 except select fn, h from pg_temp.fns()) gone)
      = array['promotion_selections_topup(uuid,uuid,jsonb)']
  and not exists (select fn, h from pg_temp.fns() except select fn, h from before390)
  and to_regproc('public.promotion_selections_topup')::oid = 'public.promotion_selections_topup(uuid,uuid,jsonb,boolean)'::regprocedure::oid,
  'C4 390 drops the old promotion_selections_topup and nothing else: every other public function keeps its body and grants, and one promotion_selections_topup is left');

select pg_temp.check(
  (select bool_and(pg_temp.outcome(sql) = '')
     from (select sql from calls union all select sql from caller_call) c),
  'C5 a call with three arguments, by position or by name, now reaches the four-argument promotion_selections_topup, and the callers'' call still does');

create temp table after390 as select * from pg_temp.fns();
set client_min_messages = warning;
\ir ../../../supabase/390_drop_legacy_promotion_selections_topup_overload.sql
reset client_min_messages;
select pg_temp.check(
  not exists ((select * from after390 except select * from pg_temp.fns())
              union all (select * from pg_temp.fns() except select * from after390)),
  'C6 running 390 again changes nothing');

do $$ begin
  if exists (select 1 from failed) then
    raise exception 'FAIL: % check(s) failed: %', (select count(*) from failed), (select string_agg(msg, ' | ' order by n) from failed); end if;
  raise notice 'ALL PASS: the three-argument promotion_selections_topup is dropped (390)';
end $$;
rollback;
