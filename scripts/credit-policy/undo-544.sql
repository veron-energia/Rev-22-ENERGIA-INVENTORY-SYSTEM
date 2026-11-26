-- undo-544.sql: takes supabase/544_wallet_credit_pays_special_and_consignment_products.sql out.
--
-- It refuses, changing nothing, unless every function 544 changed is exactly 544's with 544's
-- grants, purchase_category is 544's five-argument one (and the only one), and nothing but the
-- three functions that called it before (two changed by 544, and consume_customer_credit) calls
-- purchase_category, and no pay_special_with_credit is there. Then each function is put back
-- exactly as it was before 544 (production after 540), purchase_category with four arguments
-- again, with the same grants (signed-in logins and the service role; not anon), and
-- pay_special_with_credit, which 544 dropped, exactly as it was (the service role alone).
--
-- What stays: credit already spent on special and consignment lines stays spent, and a refund
-- still gives it back to its lot; it says how many such allocations there are. Package rules that
-- name special_product or consignment_product keep them (no credit pays those categories after
-- the undo; it says how many rule rows name them).
--
-- Run it as one transaction (psql -1 -v ON_ERROR_STOP=1 -f), with its own history note if wanted.

do $undo$
declare
  c_sig constant text[] := array[
    'credit_lot_line_allowed(uuid,uuid)',
    'credit_lot_line_reason(uuid,uuid)',
    'credit_lot_snapshot_allows(uuid,jsonb,text,uuid)',
    'credit_spendable_categories()',
    'customer_credit_eligibility(uuid)'];
  c_before constant text[] := array[
    '7d81252612104b1012b6d78513092091',
    'e5089d02f8c68bd36b6c8ff99dabf675',
    '1d78a592687366f98b52adcb655c51fb',
    'a3539af5c86c7abdb2bcff6d8d4f0611',
    'be6d5329add18038c24848c168db8785'];
  c_after constant text[] := array[
    '0f0d897d308247887577641b820aeeca',
    'be8cceed5351686edb119a4681e9fa56',
    'cd832a1758e45b4261b2f9058691d55c',
    'b25fcf7b6780171f904a3a652d93cbb6',
    '2bd2cf2f59028bc403b155f98929d719'];
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres'];
  c_def_before constant text[] := array[
$d$CREATE OR REPLACE FUNCTION public.credit_lot_line_allowed(p_lot_id uuid, p_invoice_item_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_policy text := public.credit_lot_policy_for(p_lot_id);
  v_it record; v_purpose text; v_cat text; v_components integer; v_bad integer;
begin
  if v_policy is null then return false; end if;

  select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
    into v_it from public.invoice_items ii where ii.id = p_invoice_item_id;
  if not found then return false; end if;
  v_purpose := v_it.purpose;

  if v_purpose <> 'promotion' then
    v_cat := public.purchase_category(v_purpose, v_it.product_id, v_it.voucher_id, v_it.therapy_service_id);
    return public.credit_lot_allows_category(p_lot_id, v_cat);
  end if;

  -- Composite. An unrestricted-enough policy still has to clear every part.
  select count(*),
         count(*) filter (where not public.credit_lot_allows_category(p_lot_id,
           public.purchase_category(
             case when s.product_id is not null then 'product'
                  when s.voucher_id is not null then 'voucher'
                  else 'unknown' end,
             s.product_id, s.voucher_id, null)))
    into v_components, v_bad
    from public.invoice_promotion_selections s
   where s.invoice_item_id = p_invoice_item_id;

  if coalesce(v_components, 0) = 0 then
    -- Nothing recorded to check. An 'open' or bundle policy keeps its existing
    -- freedom; a package-restricted one does not get the benefit of the doubt.
    return v_policy in ('open','bundle_any');
  end if;
  return v_bad = 0;
end $function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.credit_lot_line_reason(p_lot_id uuid, p_invoice_item_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_policy text := public.credit_lot_policy_for(p_lot_id);
  v_it record; v_cat text;
begin
  if public.credit_lot_line_allowed(p_lot_id, p_invoice_item_id) then return null; end if;
  select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
    into v_it from public.invoice_items ii where ii.id = p_invoice_item_id;
  if not found then return 'That invoice line no longer exists.'; end if;

  if v_it.purpose = 'promotion' then
    return case when v_policy in ('open','bundle_any')
      then 'This promotion contains items this balance cannot pay for, and the parts cannot be separated safely. Use another payment method for this line.'
      else public.credit_policy_reason(v_policy, 'promotion')
           || ' A promotion containing other items does not change that.' end;
  end if;
  v_cat := public.purchase_category(v_it.purpose, v_it.product_id, v_it.voucher_id, v_it.therapy_service_id);
  return public.credit_policy_reason(v_policy, v_cat);
end $function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.credit_lot_snapshot_allows(p_lot_id uuid, p_restrictions jsonb, p_purpose text, p_voucher_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare orig public.customer_credit_lots%rowtype; v_policy text; v_ids jsonb;
begin
 select * into orig from public.customer_credit_lots
  where id = public.invoice_credit_transfer_origin(p_lot_id);
 if not found then return public.credit_lot_allows(p_restrictions, p_purpose, p_voucher_id); end if;

 v_policy := public.credit_lot_policy(orig.source_type, orig.category, orig.source_record_id is not null);
 if v_policy not in ('package_paid','package_bonus') then
  return public.credit_lot_allows(p_restrictions, p_purpose, p_voucher_id);
 end if;

 -- Category is credit_lot_allows_category()'s decision now. Only an explicit
 -- voucher list still binds, and only when a voucher is what is being bought.
 v_ids := coalesce(p_restrictions->'allowed_voucher_ids', '[]'::jsonb);
 if p_purpose <> 'voucher' or jsonb_array_length(v_ids) = 0 then return true; end if;
 if p_voucher_id is null then return false; end if;
 return v_ids ? p_voucher_id::text;
end $function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.credit_spendable_categories()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
 select array['therapy_session','unlimited_therapy','session_voucher','money_voucher',
              'own_product','third_party_product','other_product','promotion',
              'event_ticket']::text[]  -- 370: event tickets
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.customer_credit_eligibility(p_customer_id uuid)
 RETURNS TABLE(lot_id uuid, category text, source_type text, source_name text, policy text, policy_label text, remaining numeric, needs_review boolean, allowed_categories text[], explanation text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.category, l.source_type,
         coalesce(cp.name, pb.name, l.reference_no, l.source_type),
         public.credit_lot_policy_for(l.id),
         case public.credit_lot_policy_for(l.id)
           when 'package_paid'  then 'Therapy sessions and therapy vouchers only'
           when 'package_bonus' then 'Own-brand products only'
           when 'bundle_any'    then 'Anything except new credit packages and premium bundles'
           when 'open'          then 'Anything except new credit packages and premium bundles'
           else 'Needs review before it can be spent' end,
         l.remaining_amount,
         public.credit_lot_policy_for(l.id) = 'needs_review',
         coalesce((select array_agg(c order by c) from unnest(array[
             'own_product','third_party_product','other_product','session_voucher',
             'money_voucher','therapy_session','unlimited_therapy','promotion',
             'event_ticket']) c  -- 370: event tickets
            -- The list a person sees must be the list that will actually
            -- be honoured, so it resolves the same way spending does.
            where public.credit_lot_allows_category(l.id, c)), '{}'),
         public.credit_policy_reason(
           public.credit_lot_policy_for(l.id), 'unknown')
    from public.customer_credit_lots l
    left join public.customer_credit_lots origin on origin.id=public.invoice_credit_transfer_origin(l.id)
    left join public.credit_packages cp
      on origin.source_type = 'credit_package' and cp.id = origin.source_record_id
    left join public.premium_bundles pb
      on origin.source_type = 'premium_bundle' and pb.id = origin.source_record_id
   where public.can_view_customer_credit() and l.customer_id = p_customer_id and l.status = 'active' and l.remaining_amount > 0
   order by l.category, l.effective_date
$function$
$d$];
  c_pc_old constant text := 'purchase_category(text,uuid,uuid,uuid)';
  c_pc_old_md5 constant text := '98902394fbeb61b8635044f7c82a9b42';
  c_pc_new constant text := 'purchase_category(text,uuid,uuid,uuid,uuid)';
  c_pc_new_md5 constant text := '6b66bb3fd20a6e1bc22f0918740052f7';
  c_pc_acl constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_pc_def_before constant text := $d$CREATE OR REPLACE FUNCTION public.purchase_category(p_purpose text, p_product_id uuid DEFAULT NULL::uuid, p_voucher_id uuid DEFAULT NULL::uuid, p_therapy_service_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select case p_purpose
    when 'product' then
      case (select p.product_type::text from public.products p where p.id = p_product_id)
        when 'own' then 'own_product'
        when 'third_party' then 'third_party_product'
        when 'no_commission' then 'other_product'
        else 'unknown' end
    when 'voucher' then
      case (select v.voucher_kind::text from public.vouchers v where v.id = p_voucher_id)
        when 'normal' then 'session_voucher'
        when 'fixed_discount' then 'money_voucher'
        when 'percentage_discount' then 'money_voucher'
        else 'unknown' end
    when 'therapy' then
      case when p_therapy_service_id is not null then 'therapy_session' else 'unlimited_therapy' end
    when 'credit_package' then 'credit_package'
    when 'premium_bundle' then 'premium_bundle'
    when 'promotion' then 'promotion'
    when 'event' then 'event_ticket'         -- 370: a ticket's category
    when 'event_ticket' then 'event_ticket'
    else 'unknown'
  end
$function$
$d$;
  c_pc_callers constant text[] := array['consume_customer_credit', 'credit_lot_line_allowed', 'credit_lot_line_reason'];
  c_pay constant text := 'pay_special_with_credit(text,uuid,uuid,numeric,uuid)';
  c_pay_md5 constant text := '5496ea7f657d49629653defc905c88f2';
  c_pay_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_pay_def_before constant text := $d$CREATE OR REPLACE FUNCTION public.pay_special_with_credit(p_doc_kind text, p_doc_id uuid, p_customer_id uuid, p_amount numeric, p_store_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_purpose text; v_res jsonb; v_a jsonb; v_total numeric := 0;
begin
  perform public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
  if p_customer_id is null then raise exception 'Wallet credit needs a customer'; end if;
  if round(coalesce(p_amount,0),2) <= 0 then return jsonb_build_object('funded', 0); end if;

  v_purpose := case p_doc_kind
    when 'special_sale' then 'special_product'
    when 'rental' then 'rental'
    when 'rental_late_fee' then 'rental'
    else null end;
  if v_purpose is null then raise exception 'Unknown document kind "%"', p_doc_kind; end if;

  v_res := public.consume_customer_credit(
    p_customer_id, round(p_amount,2), p_doc_kind, p_doc_id, p_store_id,
    null, 'Wallet payment: ' || replace(p_doc_kind,'_',' '), v_purpose, null);

  -- Mirror the exact per-lot split so a refund returns credit where it came from.
  for v_a in select * from jsonb_array_elements(coalesce(v_res->'allocations','[]'::jsonb))
  loop
    insert into public.special_credit_allocations
      (doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
    values (p_doc_kind, p_doc_id, p_customer_id,
      (v_a->>'lot_id')::uuid, v_a->>'category', (v_a->>'amount')::numeric, auth.uid());
    v_total := round(v_total + (v_a->>'amount')::numeric, 2);
  end loop;

  if p_doc_kind = 'special_sale' then
    update public.special_sales set credit_funded = credit_funded + v_total where id = p_doc_id;
  else
    update public.rentals set credit_funded = credit_funded + v_total where id = p_doc_id;
  end if;

  perform public.write_audit_ex(p_doc_kind, p_doc_id, 'paid_with_wallet_credit', null,
    jsonb_build_object('amount', v_total, 'purpose', v_purpose), 'credit', null, p_store_id);

  return jsonb_build_object('funded', v_total, 'allocations', v_res->'allocations');
end $function$
$d$;
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_bad text := ''; v_n int; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: every function is exactly 544's, with 544's grants
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception 'undo-544: public.% is not 544''s. Nothing was changed.', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo-544: the grants of public.% are not 544''s. Nothing was changed.', c_sig[i]; end if;
  end loop;
  if to_regprocedure('public.' || c_pc_new) is null
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_pc_new))) <> c_pc_new_md5
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'purchase_category') <> 1 then
    raise exception 'undo-544: public.% is not 544''s (or another purchase_category is there). Nothing was changed.', c_pc_new; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_pc_new)) is distinct from c_pc_acl then
    raise exception 'undo-544: the grants of public.% are not 544''s. Nothing was changed.', c_pc_new; end if;
  select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '') into v_bad
    from pg_proc p
   where p.prosrc ~ 'purchase_category\s*\('
     and p.proname <> all (c_pc_callers || array['purchase_category'])
     and p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace);
  if v_bad <> '' then
    raise exception 'undo-544: other functions call purchase_category now (%). Nothing was changed.', v_bad; end if;
  if exists (select 1 from pg_depend dp where dp.refobjid = to_regprocedure('public.' || c_pc_new) and dp.deptype = 'n') then
    raise exception 'undo-544: an object depends on public.%. Nothing was changed.', c_pc_new; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pay_special_with_credit') then
    raise exception 'undo-544: a public.pay_special_with_credit is there already. Nothing was changed.'; end if;

  -- What stays: credit already spent on special and consignment lines stays spent (and is given
  -- back by a refund as before); package rules that name the new categories keep them, but no
  -- credit pays those categories after the undo. Counted, not changed.
  select count(*) into v_n from public.invoice_line_credit_allocations a
    join public.invoice_items ii on ii.id = a.invoice_item_id where ii.line_kind::text = 'special_product';
  raise notice 'undo-544: % wallet allocation(s) on special and consignment lines stay as they are.', v_n;
  select count(*) into v_n from public.credit_package_spending_rules r
   where r.paid_categories && array['special_product','consignment_product']
      or r.bonus_categories && array['special_product','consignment_product'];
  raise notice 'undo-544: % package rule row(s) name special_product or consignment_product; they stay, and Rules will no longer offer those boxes (a save that keeps them is refused until they are unticked).', v_n;

  -- 2. Put back: the changed functions first (they stop calling purchase_category with five
  -- arguments), then purchase_category as it was, with the same grants
  for i in 1 .. cardinality(c_sig) loop
    execute c_def_before[i];
  end loop;
  execute format('drop function public.%s', c_pc_new);
  execute c_pc_def_before;
  execute format('revoke all on function public.%s from public, anon', c_pc_old);
  execute format('grant execute on function public.%s to authenticated, service_role', c_pc_old);
  -- pay_special_with_credit again, exactly, for the service role alone (as 406 and 426 left it)
  execute c_pay_def_before;
  execute format('revoke all on function public.%s from public, anon, authenticated', c_pay);
  execute format('grant execute on function public.%s to service_role', c_pay);

  -- 3. Checks
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo-544: public.% was not put back exactly', c_sig[i]; end if;
  end loop;
  if to_regprocedure('public.' || c_pc_old) is null
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_pc_old))) <> c_pc_old_md5
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_pc_old)) is distinct from c_pc_acl
     or to_regprocedure('public.' || c_pc_new) is not null then
    raise exception 'undo-544: public.% was not put back exactly', c_pc_old; end if;
  if to_regprocedure('public.' || c_pay) is null
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_pay))) <> c_pay_md5
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_pay)) is distinct from c_pay_acl then
    raise exception 'undo-544: public.% was not put back exactly', c_pay; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
