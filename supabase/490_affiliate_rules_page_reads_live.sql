-- 490_affiliate_rules_page_reads_live.sql
--
-- THE RULES AND REGULATIONS PAGE READS ITS RATES AND LISTS LIVE
-- (the user's answers in chat, 3 Nov 2026: the page is in the portal and
-- public, as the Energia Affiliate terms the sign-up page links to; its
-- rates and product lists are read live)
--
-- (The number 490 is this file's name, its errors' prefix and its
-- self-test's error code P0490; if it changes at commit, change it in these
-- places alone.)
--
-- WHAT THIS DOES
--
--   One new function, affiliate_rules_info(), that anyone may call, signed in
--   or not, and that returns only what the page states:
--   * rates: the four commission rates as the Commissions page sets them
--     (app_settings): Tier 1 own and third-party, Tier 2 own and
--     third-party (Tier 2 is a share of Tier 1);
--   * products: the names of the products in use (active, not deleted),
--     under own, third_party and no_commission, as each product's own
--     setting on the Products page says (not its brand);
--   * machines: the special products in use (sold or rented) and the type
--     they earn as since 489: their machine's (special_products.product_id),
--     ours when linked to none, ours for all when 489's cut-off is empty;
--   * machines_from: the Singapore day 489's rule began.
--   Nothing else: no price, cost, supplier, SKU, barcode or stock, and no
--   customer or affiliate data. It reads live, so the page follows any
--   change of a rate or of a product's setting at once.
--
-- WHAT IT DOES NOT DO
--
--   No table, row, trigger or other function changes. The page itself
--   (/affiliate/rules) and the sign-up page's link to it are page changes.
--
-- DEPLOY ORDER (each step with the user's go-ahead in chat)
--
--   489 first (this function reads its app_settings.machine_commission_from;
--   the checks refuse to run without it) -> 490 -> the pages.
--   1. Dry run on a copy of production with 489 in: apply this file twice;
--      the second run changes nothing.
--   2. Apply. It checks itself and runs its self-test.
--   3. Push the pages.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block):
--   * the columns it reads are there, 489's included;
--   * the function is absent (made) or exactly its AFTER (left alone);
--     anything else is refused;
--   * afterwards: its md5 is the AFTER one; anon, authenticated and
--     service_role may run it, PUBLIC may not; it is stable and a security
--     definer with search_path public;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0490): run as anon, as a visitor's browser does, the answer has
--     exactly these keys and only names and types in it.
--
-- AFTER (for later guards)
--   * affiliate_rules_info(): d0316e25c9f4cef2394b176a31cbd897
--   * public function fingerprint, production -> 489 -> 490 (a second run the
--     same): 04585b13626b2f4390f3153de4e8bb6f (1400 functions: one added);
--     grant list 687b8ae56f1818df171567dd5bbc5fd3. Worked out on a copy of
--     production at 481 (rc481_live) with 489 in (8cc90cc4).
--
-- UNDO: drop function public.affiliate_rules_info(); (the Rules page then
-- says it could not be loaded, with Try again).
--
-- Test: the page tests (scripts/affiliate-signup/tests/rules-page-490.test.mjs)
-- render the page against this answer's shape. Fixtures only (the repository
-- is public).

set lock_timeout = '5s';

do $mig$
declare
  c_sig constant text := 'affiliate_rules_info()';
  c_after constant text := 'd0316e25c9f4cef2394b176a31cbd897';
  c_def constant text :=
$d1$CREATE OR REPLACE FUNCTION public.affiliate_rules_info()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 490 (3 Nov 2026): what the Rules and regulations page shows, read live,
  -- for anyone (the page is the affiliate terms the sign-up page links to):
  -- the four commission rates; the products in use by commission type, names
  -- only; the machines sold or rented and what they earn as (489), with the
  -- day that rule began. Nothing else: no price, cost, supplier, SKU or stock.
  select jsonb_build_object(
    'rates', (select jsonb_build_object(
                       'tier1_own', a.commission_tier1_own_rate, 'tier1_third', a.commission_tier1_third_rate,
                       'tier2_own', a.commission_tier2_own_rate, 'tier2_third', a.commission_tier2_third_rate)
                from public.app_settings a where a.id = true),
    'machines_from', (select (a.machine_commission_from at time zone 'Asia/Singapore')::date
                        from public.app_settings a where a.id = true),
    'products', (select jsonb_build_object(
                          'own', coalesce(jsonb_agg(x.name order by lower(x.name), x.name) filter (where x.t = 'own'), '[]'::jsonb),
                          'third_party', coalesce(jsonb_agg(x.name order by lower(x.name), x.name) filter (where x.t = 'third_party'), '[]'::jsonb),
                          'no_commission', coalesce(jsonb_agg(x.name order by lower(x.name), x.name) filter (where x.t = 'no_commission'), '[]'::jsonb))
                   from (select btrim(p.name) as name, p.product_type::text as t from public.products p
                          where p.is_active is true and p.deleted_at is null and btrim(p.name) <> '') x),
    'machines', (select coalesce(jsonb_agg(jsonb_build_object(
                          'name', btrim(s.name),
                          'earns', case when a.machine_commission_from is null then 'own'
                                        else coalesce(m.product_type::text, 'own') end)
                        order by lower(btrim(s.name)), s.name), '[]'::jsonb)
                   from public.special_products s
                   left join public.products m on m.id = s.product_id
                   cross join public.app_settings a
                  where a.id = true and s.is_active is true and s.deleted_at is null and btrim(s.name) <> ''))
$function$
$d1$;
  v_path text := current_setting('search_path');
  v text; d text; v_make boolean := false; t_r jsonb;
begin
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──
  select string_agg(x.t || '.' || x.c || ' ' || x.ty, ', ') into v
    from (values ('app_settings', 'commission_tier1_own_rate', 'numeric'),
                 ('app_settings', 'commission_tier1_third_rate', 'numeric'),
                 ('app_settings', 'commission_tier2_own_rate', 'numeric'),
                 ('app_settings', 'commission_tier2_third_rate', 'numeric'),
                 ('app_settings', 'machine_commission_from', 'timestamp with time zone'),
                 ('products', 'name', 'text'),
                 ('products', 'product_type', 'product_type'),
                 ('products', 'is_active', 'boolean'),
                 ('products', 'deleted_at', 'timestamp with time zone'),
                 ('special_products', 'name', 'text'),
                 ('special_products', 'product_id', 'uuid'),
                 ('special_products', 'is_active', 'boolean'),
                 ('special_products', 'deleted_at', 'timestamp with time zone')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = ('public.' || x.t)::regclass and a.attname = x.c and not a.attisdropped
                        and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '490: these columns are missing or not of this type (489 must be in first): %', v; end if;
  if md5(c_def) <> c_after then
    raise exception '490: the text of public.% is not the tested one (md5 %)', c_sig, md5(c_def); end if;
  if to_regprocedure('public.' || c_sig) is null then
    v_make := true;
  else
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
    if md5(d) = c_after then
      raise notice '490: public.% is already this version; left alone', c_sig;
    else
      raise exception '490: public.% exists but is not this version (md5 %). Re-read it before applying.', c_sig, md5(d);
    end if;
  end if;

  -- ── 2. Install ──
  if v_make then
    execute c_def;
    execute 'revoke all on function public.affiliate_rules_info() from public';
    execute 'grant execute on function public.affiliate_rules_info() to anon, authenticated, service_role';
  end if;

  -- ── 3. Checks after installing ──
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '490: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if not (has_function_privilege('anon', 'public.' || c_sig, 'execute')
          and has_function_privilege('authenticated', 'public.' || c_sig, 'execute')
          and has_function_privilege('service_role', 'public.' || c_sig, 'execute'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) x
                 where p.oid = to_regprocedure('public.' || c_sig) and x.grantee = 0) then
    raise exception '490: public.% is not runnable by exactly anon, authenticated and service_role (and not PUBLIC)', c_sig; end if;
  if (select not p.prosecdef or p.provolatile <> 's'
             or coalesce(array_to_string(p.proconfig, ','), '') <> 'search_path=public'
        from pg_proc p where p.oid = to_regprocedure('public.' || c_sig)) then
    raise exception '490: public.% is not a stable security definer with search_path public', c_sig; end if;

  -- ── 4. Self-test, in a block that is always undone ──
  begin
    -- As a visitor's browser runs it (the anon role).
    execute 'set local role anon';
    t_r := public.affiliate_rules_info();
    execute 'reset role';
    if (select array_agg(k order by k) from jsonb_object_keys(t_r) k) is distinct from array['machines', 'machines_from', 'products', 'rates'] then
      raise exception '490: the answer has other keys than machines, machines_from, products, rates: %', t_r; end if;
    if (select array_agg(k order by k) from jsonb_object_keys(t_r->'rates') k) is distinct from array['tier1_own', 'tier1_third', 'tier2_own', 'tier2_third'] then
      raise exception '490: the rates are not the four rates: %', t_r->'rates'; end if;
    if (select array_agg(k order by k) from jsonb_object_keys(t_r->'products') k) is distinct from array['no_commission', 'own', 'third_party'] then
      raise exception '490: the products are not grouped by the three types: %', t_r->'products'; end if;
    if exists (select 1 from jsonb_each(t_r->'products') g, jsonb_array_elements(g.value) e where jsonb_typeof(e) <> 'string')
       or exists (select 1 from jsonb_array_elements(t_r->'machines') e
                   where (select array_agg(k order by k) from jsonb_object_keys(e) k) is distinct from array['earns', 'name']
                      or e->>'earns' not in ('own', 'third_party', 'no_commission')) then
      raise exception '490: the lists hold more than names and types'; end if;
    raise exception using errcode = 'P0490', message = '490: self-test done, undone';
  exception when sqlstate 'P0490' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
