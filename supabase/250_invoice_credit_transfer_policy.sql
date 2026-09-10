begin;
-- A transferred lot keeps an auditable transfer source. Resolve its spending
-- policy through the recorded benefit chain, never through a user-supplied
-- policy label or an unrestricted default for the transfer source type.
create function public.invoice_credit_transfer_origin(p_lot_id uuid)
returns uuid language plpgsql stable security definer set search_path=public as $$
declare current_id uuid:=p_lot_id; visited uuid[]:='{}';
 child public.customer_credit_lots%rowtype; parent public.customer_credit_lots%rowtype;
 transfer public.invoice_benefit_transfers%rowtype;
 source_benefit public.invoice_benefit_values%rowtype; replacement_benefit public.invoice_benefit_values%rowtype;
begin
 loop
  if current_id is null or current_id=any(visited) then return null; end if;
  visited:=array_append(visited,current_id);
  select * into child from public.customer_credit_lots where id=current_id;
  if not found then return null; end if;
  if child.source_type<>'invoice_benefit_transfer' then return child.id; end if;
  select * into transfer from public.invoice_benefit_transfers where id=child.source_record_id;
  if not found then return null; end if;
  select * into replacement_benefit from public.invoice_benefit_values where id=transfer.replacement_benefit_id;
  if not found or replacement_benefit.lot_id is distinct from child.id
   or replacement_benefit.invoice_id is distinct from transfer.invoice_id
   or child.customer_id is distinct from transfer.customer_id
   or child.store_id is distinct from transfer.store_id
   or child.original_amount is distinct from transfer.transferred_value then return null; end if;
  select * into source_benefit from public.invoice_benefit_values where id=transfer.source_benefit_id;
  if not found or source_benefit.lot_id is null
   or source_benefit.invoice_id is distinct from transfer.invoice_id
   or source_benefit.invoice_item_id is distinct from replacement_benefit.invoice_item_id then return null; end if;
  select * into parent from public.customer_credit_lots where id=source_benefit.lot_id;
  if not found or parent.category is distinct from child.category
   or parent.usage_restrictions is distinct from child.usage_restrictions
   or child.original_amount>parent.original_amount then return null; end if;
  current_id:=parent.id;
 end loop;
end $$;
revoke all on function public.invoice_credit_transfer_origin(uuid) from public,anon,authenticated;

create or replace function public.credit_lot_policy_for(p_lot_id uuid)
returns text language plpgsql stable security definer set search_path=public as $$
declare original public.customer_credit_lots%rowtype;
begin
 -- Match the existing wallet visibility rule. The definer context is needed
 -- for a recipient's staff member to follow an origin at a different store;
 -- no source customer, balance or invoice details are returned to the caller.
 if not public.can_view_customer_credit() then return 'needs_review'; end if;
 select * into original from public.customer_credit_lots where id=public.invoice_credit_transfer_origin(p_lot_id);
 if not found then return 'needs_review'; end if;
 return public.credit_lot_policy(original.source_type,original.category,original.source_record_id is not null);
end $$;
revoke all on function public.credit_lot_policy_for(uuid) from public,anon;
grant execute on function public.credit_lot_policy_for(uuid) to authenticated;

-- Keep invoice allocation, direct spending and all eligibility/read models on
-- the same validated lot resolver. The underlying 242 policy matrix remains
-- unchanged, including its refusal to classify an arbitrary transfer as open.
do $$ declare f text; sig text; changed text; anchor text; begin
 foreach sig in array array[
  'public.customer_credit_eligibility(uuid)',
  'public.credit_eligibility_diagnostic()',
  'public.credit_lots_needing_review()'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  changed:=regexp_replace(f,$pattern$public\.credit_lot_policy\(\s*l\.source_type,\s*l\.category,\s*l\.source_record_id is not null\)$pattern$,
   'public.credit_lot_policy_for(l.id)','g');
  if changed=f then raise exception 'Unexpected source policy read model: %',sig; end if;
  if sig='public.customer_credit_eligibility(uuid)' then
   anchor:='    left join public.credit_packages cp';
   if position(anchor in changed)=0 then raise exception 'Unexpected eligibility source-name query'; end if;
   changed:=replace(changed,anchor,'    left join public.customer_credit_lots origin on origin.id=public.invoice_credit_transfer_origin(l.id)'||chr(10)||anchor);
   changed:=replace(changed,'on l.source_type = ''credit_package'' and cp.id = l.source_record_id','on origin.source_type = ''credit_package'' and cp.id = origin.source_record_id');
   changed:=replace(changed,'on l.source_type = ''premium_bundle'' and pb.id = l.source_record_id','on origin.source_type = ''premium_bundle'' and pb.id = origin.source_record_id');
   changed:=replace(changed,'where l.customer_id = p_customer_id and l.status',
    'where public.can_view_customer_credit() and l.customer_id = p_customer_id and l.status');
  elsif sig='public.credit_lots_needing_review()' then
   anchor:='case when l.source_record_id is null';
   if position(anchor in changed)=0 then raise exception 'Unexpected source review explanation'; end if;
   changed:=replace(changed,anchor,$patch$case when l.source_type='invoice_benefit_transfer' then
              'The recorded transfer chain is missing, inconsistent or cyclic. Review the original benefit links and restrictions before spending.'
              when l.source_record_id is null$patch$);
  end if;
  execute changed;
 end loop;
 select pg_get_functiondef('public.consume_customer_credit(uuid,numeric,text,uuid,uuid,text,text,text,uuid)'::regprocedure) into f;
 anchor:='public.credit_lot_policy(source_type, category, source_record_id is not null)';
 if position(anchor in f)=0 then raise exception 'Unexpected direct-spend policy filter'; end if;
 execute replace(f,anchor,'public.credit_lot_policy_for(id)');
end $$;
revoke all on function public.customer_credit_eligibility(uuid) from public,anon;
grant execute on function public.customer_credit_eligibility(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
