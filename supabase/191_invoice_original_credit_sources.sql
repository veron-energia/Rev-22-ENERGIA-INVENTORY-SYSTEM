begin;
-- NULL in the old bonus_lot column does not prove that no bonus was issued.
alter table public.credit_package_sales add column original_sources_verified_at timestamptz;
alter table public.credit_package_sales add column original_sources_evidence text;
do $$ declare f text; sig text; anchor text:='update public.credit_package_sales set bonus_credit_lot_id=v_bonus_lot where id=v_sale;'; begin
 foreach sig in array array['public.issue_credit_package(uuid,uuid,uuid,numeric,uuid)','public.issue_credit_package_invoice_item(uuid)'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  if position(anchor in f)=0 then raise exception 'Unexpected original credit issuer: %',sig; end if;
  execute replace(f,anchor,'update public.credit_package_sales set bonus_credit_lot_id=v_bonus_lot,original_sources_verified_at=now(),original_sources_evidence=''Exact paid/bonus lot IDs recorded by the issuing transaction'' where id=v_sale;');
 end loop;
end $$;

create function public.verify_invoice_credit_sale_sources(p_sale_id uuid,p_bonus_lot_id uuid,p_no_bonus boolean,p_evidence text)
returns void language plpgsql security definer set search_path=public as $$
declare s public.credit_package_sales%rowtype; i public.invoices%rowtype; l public.customer_credit_lots%rowtype;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can review original credit sources'; end if;
 if length(trim(coalesce(p_evidence,'')))<10 then raise exception 'Describe the original grant/receipt evidence supporting this decision'; end if;
 if (p_bonus_lot_id is null) is distinct from coalesce(p_no_bonus,false) then raise exception 'Select the original bonus lot or explicitly confirm that no bonus was issued'; end if;
 select * into s from public.credit_package_sales where id=p_sale_id;
 select * into i from public.invoices where id=s.invoice_id for update;
 if not found or i.deleted_at is not null or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 select * into s from public.credit_package_sales where id=p_sale_id for update;
 if s.original_sources_verified_at is not null or s.bonus_credit_lot_id is not null then
  if s.bonus_credit_lot_id is not distinct from p_bonus_lot_id then return; end if;
  raise exception 'This sale already has verified source evidence; retain it for an explicit historical repair review';
 end if;
 if exists(select 1 from public.invoice_benefit_values b where b.lot_id=s.credit_lot_id) then
  raise exception 'Existing paid-value allocations need a coordinated historical repair before changing their source evidence'; end if;
 if p_bonus_lot_id is not null then
  select * into l from public.customer_credit_lots where id=p_bonus_lot_id for update;
  if not found or l.category<>'bonus' or l.customer_id<>s.customer_id or l.store_id is distinct from s.store_id
   or l.source_type<>'credit_package' or l.source_record_id is distinct from s.package_id then
   raise exception 'The selected bonus lot is not an original package grant for this recipient and store'; end if;
  if exists(select 1 from public.credit_package_sales q where q.id<>s.id and q.bonus_credit_lot_id=l.id)
   or exists(select 1 from public.invoice_benefit_values b where b.lot_id=l.id) then
   raise exception 'This bonus lot is already assigned to another sale or recorded allocation'; end if;
 end if;
 update public.credit_package_sales set bonus_credit_lot_id=p_bonus_lot_id,original_sources_verified_at=now(),original_sources_evidence=p_evidence where id=s.id;
 perform public.write_audit_ex('credit_package_sales',s.id,'original_credit_sources_verified',to_jsonb(s),
  jsonb_build_object('bonus_lot_id',p_bonus_lot_id,'no_bonus',p_no_bonus,'evidence',p_evidence),'invoices',p_evidence,i.store_id);
end $$;
revoke all on function public.verify_invoice_credit_sale_sources(uuid,uuid,boolean,text) from public,anon;
grant execute on function public.verify_invoice_credit_sale_sources(uuid,uuid,boolean,text) to authenticated;

create function public.assert_invoice_credit_source_evidence(p_invoice_id uuid,p_item_id uuid default null)
returns void language plpgsql stable security definer set search_path=public as $$
begin
 if exists(select 1 from public.credit_package_sales s join public.invoice_items it on it.invoice_id=s.invoice_id and it.credit_package_id=s.package_id
  where s.invoice_id=p_invoice_id and (p_item_id is null or it.id=p_item_id) and s.bonus_credit_lot_id is null and s.original_sources_verified_at is null) then
  raise exception 'Historical bonus-credit provenance is unresolved. Review the original bonus lot or documented no-bonus decision before allocating, refunding or moving this purchase.';
 end if;
 if exists(select 1 from public.credit_package_sales s join public.invoice_items it on it.invoice_id=s.invoice_id and it.credit_package_id=s.package_id
  where s.invoice_id=p_invoice_id and (p_item_id is null or it.id=p_item_id) and (s.reward_units>0 or s.reward_voucher_qty>0)) then
  raise exception 'This package includes qualification rewards. Resolve their exact entitlement and redemption history before refunding, cancelling or moving the purchase; credit-only allocations are incomplete.';
 end if;
end $$;
revoke all on function public.assert_invoice_credit_source_evidence(uuid,uuid) from public,anon,authenticated;

do $$ declare f text; anchor text; begin
 select pg_get_functiondef('public.record_invoice_benefit_values(uuid,jsonb,text)'::regprocedure) into f;
 anchor:=' if exists(select 1 from public.invoice_benefit_values where invoice_item_id=it.id) then';
 if position(anchor in f)=0 then raise exception 'Unexpected historical allocation validator'; end if;
 execute replace(f,anchor,' perform public.assert_invoice_credit_source_evidence(i.id,it.id);'||chr(10)||anchor);
 select pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 anchor:='     if it.line_kind in (''credit_package'',''premium_bundle'') then';
 if position(anchor in f)=0 then raise exception 'Unexpected purchased benefit refund'; end if;
 execute replace(f,anchor,anchor||chr(10)||'       perform public.assert_invoice_credit_source_evidence(i.id,it.id);');
 select pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure) into f;
 anchor:=' if public.invoice_untracked_voucher(i.id)';
 if position(anchor in f)=0 then raise exception 'Unexpected invoice cancellation guard'; end if;
 execute replace(f,anchor,' perform public.assert_invoice_credit_source_evidence(i.id);'||chr(10)||anchor);
 select pg_get_functiondef('public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure) into f;
 anchor:=' if b.cancelled_unused_value>0 then';
 if position(anchor in f)=0 then raise exception 'Unexpected benefit transfer validator'; end if;
 execute replace(f,anchor,' perform public.assert_invoice_credit_source_evidence(i.id,b.invoice_item_id);'||chr(10)||anchor);
end $$;

-- Enrich the existing review screen with explicitly unresolved source decisions.
alter function public.invoice_benefit_review_options(uuid) rename to invoice_benefit_review_options_internal;
revoke all on function public.invoice_benefit_review_options_internal(uuid) from public,anon,authenticated;
create function public.invoice_benefit_review_options(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; lines jsonb:='[]'; x jsonb; sources jsonb; issue text;
begin
 result:=public.invoice_benefit_review_options_internal(p_invoice_id);
 for x in select * from jsonb_array_elements(result->'lines') loop
  select coalesce(jsonb_agg(jsonb_build_object('sale_id',s.id,'customer_name',c.full_name,'paid_lot_id',s.credit_lot_id,'bonus_lot_id',s.bonus_credit_lot_id,
   'verified',s.original_sources_verified_at is not null or s.bonus_credit_lot_id is not null,
   'candidates',(select coalesce(jsonb_agg(jsonb_build_object('lot_id',l.id,'granted_value',l.original_amount,'purchase_date',l.original_purchase_date) order by l.id),'[]')
    from public.customer_credit_lots l where l.customer_id=s.customer_id and l.store_id is not distinct from s.store_id and l.category='bonus'
    and l.source_type='credit_package' and l.source_record_id=s.package_id
    and not exists(select 1 from public.credit_package_sales other where other.id<>s.id and other.bonus_credit_lot_id=l.id)
    and not exists(select 1 from public.invoice_benefit_values b where b.lot_id=l.id))
  ) order by s.id),'[]') into sources from public.credit_package_sales s
  join public.invoice_items it on it.invoice_id=s.invoice_id and it.credit_package_id=s.package_id
  left join public.customers c on c.id=s.customer_id where it.id=(x->>'invoice_item_id')::uuid;
  issue:=x->>'blocked_reason';
  if issue is null and exists(select 1 from jsonb_array_elements(sources) src where not (src->>'verified')::boolean) then
   issue:='Verify each original bonus-credit source or documented no-bonus decision before allocating historical paid values.';
  end if;
  if exists(select 1 from public.credit_package_sales s join public.invoice_items it on it.invoice_id=s.invoice_id and it.credit_package_id=s.package_id
    where it.id=(x->>'invoice_item_id')::uuid and (s.reward_units>0 or s.reward_voucher_qty>0)) then
   issue:='Qualification rewards require original entitlement and redemption review; credit-only allocations cannot complete this purchase.';
  end if;
  lines:=lines||jsonb_build_array(x||jsonb_build_object('sources',sources,'blocked_reason',issue));
 end loop;
 return jsonb_build_object('lines',lines);
end $$;
revoke all on function public.invoice_benefit_review_options(uuid) from public,anon;
grant execute on function public.invoice_benefit_review_options(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
