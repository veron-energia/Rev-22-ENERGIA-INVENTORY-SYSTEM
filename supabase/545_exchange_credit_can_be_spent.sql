-- 545_exchange_credit_can_be_spent.sql
--
-- EXCHANGE CREDIT CAN BE SPENT
--
--   The owner (27 Nov 2026), after 544: "Fix the exchange credit too."
--
-- WHAT WAS WRONG
--
--   grant_exchange_credit (a product exchange's credit) makes its lot with source_type
--   'product_exchange' and category 'exchange'. Its own comment says that, with no purposes
--   given, the credit "behaves as unrestricted store credit". credit_lot_policy lists 'exchange'
--   among the sources that keep that open behaviour, but not 'product_exchange', so such a lot
--   fell to 'needs_review', which pays nothing (credit_policy_allows). Production, read only on
--   27 Nov 2026: 0 lots with source 'product_exchange', so no customer's credit was held up and
--   nothing needs repairing.
--
-- WHAT THIS DOES
--
--   credit_lot_policy lists 'product_exchange' with the open sources. An exchange lot then pays
--   what other open credit pays: everything except a credit package, a premium bundle and
--   anything 'unknown' (rentals among them); since 544 that includes special and consignment
--   products. A lot made with purposes (grant_exchange_credit's p_purposes) keeps them:
--   credit_lot_snapshot_allows still holds an open lot to its own usage_restrictions.
--
-- WHAT STAYS
--
--   Every other source and its policy; credit_lot_policy's arguments, language, volatility and
--   grants (postgres, service_role, authenticated; not anon); the lots themselves.
--
-- BEFORE: credit_lot_policy md5 d9a97af64871c4ebcff8d1f6c15f68a6, the same on production after
-- 544 and after 541 + 542 (head 20261126172814, function fingerprint
-- 8763c2671addf9c45a03b13a4f24ac3b/1462). If it differs, this refuses and changes nothing. A
-- second run refuses as "already in".
-- Undo: scripts/credit-policy/undo-545.sql. Suite: scripts/credit-policy/tests/exchange-credit-545.sql.

do $m545$
declare
  c_sig    constant regprocedure := 'public.credit_lot_policy(text,text,boolean)'::regprocedure;
  c_before constant text := 'd9a97af64871c4ebcff8d1f6c15f68a6';
  c_after  constant text := '9f9b8db1d996a6b06e702e45014a17f4';
  c_acl    constant text := '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}';
  v_md5 text; v_acl text;
begin
  perform set_config('lock_timeout', '5s', true);

  select md5(pg_get_functiondef(p.oid)), p.proacl::text into v_md5, v_acl from pg_proc p where p.oid = c_sig;
  if v_md5 = c_after then
    raise exception '545 is already in on this database; nothing was changed.'; end if;
  if v_md5 is distinct from c_before then
    raise exception '545: credit_lot_policy is not the one this was written for (md5 %). Nothing was changed.', v_md5; end if;
  if v_acl is distinct from c_acl then
    raise exception '545: credit_lot_policy''s grants are not as tested (%). Nothing was changed.', v_acl; end if;

  execute $d$CREATE OR REPLACE FUNCTION public.credit_lot_policy(p_source_type text, p_category text, p_has_source boolean)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when p_source_type = 'credit_package' and not p_has_source then 'needs_review'
    when p_source_type = 'premium_bundle' and not p_has_source then 'needs_review'
    when p_source_type = 'credit_package' and p_category = 'paid'  then 'package_paid'
    when p_source_type = 'credit_package' and p_category = 'bonus' then 'package_bonus'
    when p_source_type = 'premium_bundle' then 'bundle_any'
    -- Sources this system creates for reasons unrelated to packages keep the
    -- behaviour they have always had. Listed explicitly: an unrecognised value
    -- must not fall through to "unrestricted".
    -- 545 (the owner, 27 Nov 2026): 'product_exchange' is the source grant_exchange_credit
    -- gives a product exchange's credit, unrestricted store credit when no purposes are given.
    when p_source_type in ('manual','manual_legacy','manual_adjustment','manual_use','exchange',
                           'product_exchange',
                           'invoice_cancel_benefit','invoice_benefit_refund',
                           'adjustment','opening_balance','transfer')
      then 'open'
    else 'needs_review'
  end
$function$
$d$;

  select md5(pg_get_functiondef(p.oid)), p.proacl::text into v_md5, v_acl from pg_proc p where p.oid = c_sig;
  if v_md5 is distinct from c_after then
    raise exception '545: credit_lot_policy came out as md5 %, not %. Nothing was changed.', v_md5, c_after; end if;
  if v_acl is distinct from c_acl then
    raise exception '545: credit_lot_policy''s grants changed (%). Nothing was changed.', v_acl; end if;

  -- The rule now: product exchange credit is open; every other source as before.
  if public.credit_lot_policy('product_exchange', 'exchange', true) <> 'open'
     or public.credit_lot_policy('product_exchange', 'exchange', false) <> 'open' then
    raise exception '545: product exchange credit is not open. Nothing was changed.'; end if;
  if public.credit_lot_policy('exchange', 'exchange', true) <> 'open'
     or public.credit_lot_policy('manual_legacy', 'paid', false) <> 'open'
     or public.credit_lot_policy('premium_bundle', 'paid', true) <> 'bundle_any'
     or public.credit_lot_policy('premium_bundle', 'paid', false) <> 'needs_review'
     or public.credit_lot_policy('credit_package', 'paid', true) <> 'package_paid'
     or public.credit_lot_policy('credit_package', 'bonus', true) <> 'package_bonus'
     or public.credit_lot_policy('credit_package_progress', 'paid', true) <> 'needs_review'
     or public.credit_lot_policy('not_a_source', 'paid', true) <> 'needs_review' then
    raise exception '545: another source''s policy moved. Nothing was changed.'; end if;
end $m545$;
