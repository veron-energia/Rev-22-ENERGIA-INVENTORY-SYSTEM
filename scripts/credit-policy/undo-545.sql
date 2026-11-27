-- undo-545.sql: puts credit_lot_policy back exactly as it was before 545
-- (supabase/545_exchange_credit_can_be_spent.sql). Product exchange credit is then 'needs_review'
-- again and pays nothing. It refuses, changing nothing, unless credit_lot_policy is exactly 545's.
-- Credit already spent from a product exchange lot stays spent; it does not come back.

do $u545$
declare
  c_sig    constant regprocedure := 'public.credit_lot_policy(text,text,boolean)'::regprocedure;
  c_before constant text := 'd9a97af64871c4ebcff8d1f6c15f68a6';  -- before 545
  c_after  constant text := '9f9b8db1d996a6b06e702e45014a17f4';  -- 545's
  c_acl    constant text := '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}';
  v_md5 text; v_acl text;
begin
  perform set_config('lock_timeout', '5s', true);
  select md5(pg_get_functiondef(p.oid)), p.proacl::text into v_md5, v_acl from pg_proc p where p.oid = c_sig;
  if v_md5 is distinct from c_after then
    raise exception 'undo-545: credit_lot_policy is not 545''s (md5 %). Nothing was changed.', v_md5; end if;

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
    when p_source_type in ('manual','manual_legacy','manual_adjustment','manual_use','exchange',
                           'invoice_cancel_benefit','invoice_benefit_refund',
                           'adjustment','opening_balance','transfer')
      then 'open'
    else 'needs_review'
  end
$function$
$d$;

  select md5(pg_get_functiondef(p.oid)), p.proacl::text into v_md5, v_acl from pg_proc p where p.oid = c_sig;
  if v_md5 is distinct from c_before then
    raise exception 'undo-545: credit_lot_policy came back as md5 %, not %. Nothing was changed.', v_md5, c_before; end if;
  if v_acl is distinct from c_acl then
    raise exception 'undo-545: credit_lot_policy''s grants changed (%). Nothing was changed.', v_acl; end if;
end $u545$;
