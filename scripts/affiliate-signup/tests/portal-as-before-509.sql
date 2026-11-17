-- For the suites written before 509, on a database where 509 is in (included by each right after its begin).
--
-- 509 (17 Nov 2026) closes a suspended affiliate's portal: current_affiliate_customer_id() is null for them,
-- affiliate_portal_me says only "suspended", affiliate_portal_details refuses, and affiliate_detail_state routes them
-- 'closed'. The suites before it check the versions before it: a suspended affiliate's My Network still listed with
-- no numbers (484 N6, 492 N3), their referral code with accepting false (454 A1), and their own migration files run
-- again, which pin current_affiliate_customer_id or affiliate_detail_state as relied on (454 G3, 480 G3, 484 G1,
-- 493 G3-G5). So for their run, which is rolled back, the four functions are put back to their text before 509,
-- as 509's UNDO does (each of its replacements, reversed). Anywhere else (509 not in) this changes nothing.
-- What 509 changes is checked by scripts/affiliate-signup/tests/suspended-portal-509.sql.
--
-- Included by scripts/referrals/tests/affiliate-network-phone-484.sql, affiliate-network-phone-492.sql,
-- downline-booking-480.sql, portal-seminar-link-454.sql and scripts/affiliate-details/tests/details-lost-inbox-493.sql.
-- Never run it on its own against a real database: it is only for a rolled-back test.
do $as509$
declare
  v_path text := current_setting('search_path');
  c_sig constant text[] := array['current_affiliate_customer_id()', 'affiliate_portal_me()', 'affiliate_portal_details()', 'affiliate_detail_state(uuid)'];
  c_509 constant text[] := array['4f552894d48ef799c071d4b95c37745d', '8b4f230b27adb0acd0b0eb658412fe01', '505ad742085b0dda5eb6950522bd6356', '42c84668858277a0355208541c0c4c5c'];
  c_before constant text[] := array['51695acf5f26ce3918d6003d0c980b0f', 'ac16da58b1c43324d6b56f4902133042', '80b6186a7cdd097eadbaa38d38abdf57', 'afa1c2b4c6564d37de6bb0a42064e0ef'];
  -- 509's c_new (found now) and c_anchor (put back), as in supabase/509_a_suspended_affiliate_portal_shows_nothing.sql
  c_new constant text[] := array[
$n$   where a.auth_user_id = auth.uid() and a.status = 'claimed'
     -- 509: a suspended affiliate's portal is closed: no portal function answers it
     and not exists (select 1 from public.customer_affiliates ca
                      where ca.customer_id = a.customer_id and ca.deleted_at is null and ca.manually_suspended)$n$,
$n$  -- 509: a login whose portal is closed (its affiliate suspended, or its account
  -- not 'claimed') is told so, and nothing else.
  if v_me is null and exists (select 1 from public.affiliate_accounts where auth_user_id = auth.uid()) then
    return jsonb_build_object('status', 'suspended', 'portal_closed', true);
  end if;
  if v_me is null then raise exception 'Not an affiliate account'; end if;$n$,
$n$  if s->>'route' = 'not_affiliate' then raise exception 'Not an affiliate account'; end if;
  -- 509: a closed portal (suspended, or the account not 'claimed') shows none of the record's details
  if public.current_affiliate_customer_id() is null then
    raise exception 'This affiliate account is suspended.' using errcode = '42501'; end if;$n$,
$n$or a.status <> 'claimed'
         -- 509: a suspended affiliate changes nothing here either
         or exists (select 1 from public.customer_affiliates ca
                     where ca.customer_id = a.customer_id and ca.deleted_at is null and ca.manually_suspended)$n$];
  c_anchor constant text[] := array[
$a$   where a.auth_user_id = auth.uid() and a.status = 'claimed'$a$,
$a$  if v_me is null then raise exception 'Not an affiliate account'; end if;$a$,
$a$  if s->>'route' = 'not_affiliate' then raise exception 'Not an affiliate account'; end if;$a$,
$a$or a.status <> 'claimed'$a$];
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  if md5(pg_get_functiondef('public.current_affiliate_customer_id()'::regprocedure)) = c_509[1] then
    for i in 1 .. 4 loop
      d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
      if md5(d) <> c_509[i] then raise exception 'portal-as-before-509: public.% is not 509''s version', c_sig[i]; end if;
      execute replace(d, c_new[i], c_anchor[i]);
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i] then
        raise exception 'portal-as-before-509: public.% is not its version before 509 after putting it back', c_sig[i]; end if;
    end loop;
    raise notice '509 is in: the four functions it changes are as before it for this run (rolled back at the end)';
  end if;
  perform set_config('search_path', v_path, true);
end $as509$;
