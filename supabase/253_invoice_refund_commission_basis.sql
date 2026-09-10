begin;
-- Refunds reduce the source sale, not every sale sharing its invoice. Existing
-- payout rows and their separately linked future offsets remain immutable.
create or replace function public.assert_invoice_commission_refund_evidence(p_invoice_id uuid)
returns void language plpgsql stable security definer set search_path=public as $$
declare i public.invoices%rowtype; r record; lines jsonb; x jsonb; n integer; amount numeric;
begin
 select * into i from public.invoices where id=p_invoice_id;
 for r in select coalesce(q.request_id,q.id) request_key,sum(q.amount) total,
  bool_or(q.payment_id is null) missing_source
  from public.invoice_refunds q where q.invoice_id=i.id and (i.reopened_at is null or q.created_at>i.reopened_at)
  group by coalesce(q.request_id,q.id)
 loop
  select count(*) into n from public.invoice_refunds q where q.invoice_id=i.id
   and coalesce(q.request_id,q.id)=r.request_key and jsonb_typeof(q.outcome->'lines')='array';
  if r.missing_source or n<>1 then
   raise exception 'Commission review required: invoice % has a historical refund without one complete line allocation and original payment source. Review that refund before recalculating commissions.',i.invoice_no;
  end if;
  select q.outcome->'lines' into lines from public.invoice_refunds q where q.invoice_id=i.id
   and coalesce(q.request_id,q.id)=r.request_key and jsonb_typeof(q.outcome->'lines')='array';
  select sum((value->>'amount')::numeric) into amount from jsonb_array_elements(lines);
  if amount is distinct from r.total then raise exception 'Commission review required: refund line allocations do not reconcile on invoice %.',i.invoice_no; end if;
  for x in select value from jsonb_array_elements(lines) loop
   if nullif(x->>'invoice_item_id','') is null then continue; end if; -- Invoice-level overpayment, already capped by corrected prices.
   if not exists(select 1 from public.invoice_items it where it.id=(x->>'invoice_item_id')::uuid and it.invoice_id=i.id) then
    raise exception 'Commission review required: a refunded original invoice line is unavailable on invoice %.',i.invoice_no;
   end if;
   if exists(select 1 from public.invoice_items it where it.id=(x->>'invoice_item_id')::uuid and it.line_kind in ('credit_package','premium_bundle')) then
    if jsonb_typeof(x->'benefits') is distinct from 'array' then raise exception 'Commission review required: record the original benefit allocations for the refunded package on invoice %.',i.invoice_no; end if;
    select sum((value->>'amount')::numeric) into amount from jsonb_array_elements(x->'benefits');
    if amount is distinct from (x->>'amount')::numeric then raise exception 'Commission review required: package refund benefits do not reconcile on invoice %.',i.invoice_no; end if;
   end if;
  end loop;
 end loop;
end $$;

-- Follow explicit transfer/reopening provenance; no timestamp or customer-name
-- matching is used to decide which original package funded a refunded benefit.
create or replace function public.invoice_commission_benefit_source(p_benefit_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare b public.invoice_benefit_values%rowtype; current_id uuid:=p_benefit_id;
 parents uuid[]; visited uuid[]:='{}'; sources jsonb; original_line uuid;
begin
 loop
  if current_id=any(visited) or cardinality(visited)>64 then raise exception 'Commission review required: benefit provenance contains a cycle.'; end if;
  visited:=array_append(visited,current_id);
  select * into b from public.invoice_benefit_values where id=current_id;
  if not found then raise exception 'Commission review required: the original refunded benefit allocation is missing.'; end if;
  original_line:=coalesce(original_line,b.invoice_item_id);
  if b.invoice_item_id<>original_line then raise exception 'Commission review required: benefit provenance crosses invoice lines.'; end if;
  select array_agg(distinct parent_id) into parents from (
   select t.source_benefit_id parent_id from public.invoice_benefit_transfers t where t.replacement_benefit_id=b.id
   union select q.benefit_id from public.invoice_reopen_vouchers q where q.replacement_voucher_id=b.reward_voucher_id
  ) parent;
  if coalesce(cardinality(parents),0)=0 then exit; end if;
  if cardinality(parents)<>1 then raise exception 'Commission review required: the refunded benefit has multiple possible original sources.'; end if;
  current_id:=parents[1];
 end loop;
 select jsonb_agg(to_jsonb(s)) into sources from (
  select 'credit_package'::text sale_kind,c.id sale_id,b.invoice_item_id invoice_item_id
   from public.credit_package_sales c where c.invoice_id=b.invoice_id and b.lot_id in(c.credit_lot_id,c.bonus_credit_lot_id)
  union all
  select 'premium_bundle',p.id,b.invoice_item_id from public.premium_bundle_sales p
   where p.invoice_id=b.invoice_id and (b.lot_id in(p.paid_credit_lot_id,p.bonus_credit_lot_id)
    or exists(select 1 from public.customer_reward_vouchers v where v.id=b.reward_voucher_id and v.source_id=p.id))
 ) s;
 if coalesce(jsonb_array_length(sources),0)<>1 then
  raise exception 'Commission review required: resolve the original paid/bonus lot or voucher source for benefit % before recalculating this refund.',p_benefit_id;
 end if;
 return sources->0;
end $$;

create or replace function public.invoice_package_retained_commission_basis(p_kind text,p_sale_id uuid,p_original_paid numeric)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare invoice_id uuid; i public.invoices%rowtype; x jsonb; z jsonb; source jsonb; refunded numeric:=0;
begin
 if p_kind='credit_package' then select s.invoice_id into invoice_id from public.credit_package_sales s where s.id=p_sale_id;
 elsif p_kind='premium_bundle' then select s.invoice_id into invoice_id from public.premium_bundle_sales s where s.id=p_sale_id;
 else raise exception 'Unsupported package commission source'; end if;
 if invoice_id is null then return p_original_paid; end if;
 select * into i from public.invoices where id=invoice_id;
 for x in select l.value from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines','[]')) l
  where r.invoice_id=i.id and (i.reopened_at is null or r.created_at>i.reopened_at)
   and not coalesce((l.value->>'overpayment')::boolean,false)
 loop
  for z in select value from jsonb_array_elements(coalesce(x->'benefits','[]')) loop
   source:=public.invoice_commission_benefit_source((z->>'benefit_id')::uuid);
   if source->>'invoice_item_id' is distinct from x->>'invoice_item_id' then raise exception 'Commission review required: refund benefit does not belong to its recorded line.'; end if;
   if source->>'sale_kind'=p_kind and source->>'sale_id'=p_sale_id::text then refunded:=refunded+(z->>'amount')::numeric; end if;
  end loop;
 end loop;
 return greatest(0,round(p_original_paid-refunded,2));
end $$;

-- Apply pre-refund funding to ordinary lines, then their own charge reductions.
-- Wallet exclusions remain inside earn_invoice_commission; package functions
-- already receive actual external money and are not multiplied a second time.
create or replace function public.adjust_invoice_line_commission_refunds(p_invoice_id uuid,p_previous_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; line record; funding numeric; v_refunds numeric; target numeric; ratio numeric;
begin
 select * into i from public.invoices where id=p_invoice_id;
 select coalesce(sum(r.amount),0) into v_refunds from public.invoice_refunds r where r.invoice_id=i.id and (i.reopened_at is null or r.created_at>i.reopened_at);
 funding:=case when i.total_amount>0 then least(1,greatest(0,public.invoice_net_received(i.id)+v_refunds)/i.total_amount) else 0 end;
 for line in select c.invoice_item_id,sum(c.line_amount) amount from public.commissions c
  where c.invoice_id=i.id and not(c.id=any(coalesce(p_previous_ids,'{}'::uuid[]))) and c.tier='tier1'
   and c.invoice_item_id is not null group by c.invoice_item_id
 loop
  select coalesce(sum((l.value->>'amount')::numeric),0) into v_refunds
   from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines','[]')) l
   where r.invoice_id=i.id and l.value->>'invoice_item_id'=line.invoice_item_id::text
    and not coalesce((l.value->>'overpayment')::boolean,false) and (i.reopened_at is null or r.created_at>i.reopened_at);
  target:=greatest(0,round(line.amount*funding-v_refunds,2));
  ratio:=case when line.amount>0 then target/line.amount else 0 end;
  update public.commissions c set line_amount=round(c.line_amount*ratio,2),commission_amount=round(c.commission_amount*ratio,2)
   where c.invoice_id=i.id and c.invoice_item_id=line.invoice_item_id and not(c.id=any(coalesce(p_previous_ids,'{}'::uuid[])));
 end loop;
end $$;

do $$ declare f text; sig text; anchor text; patched text; begin
 -- Keep classification and numeric rate snapshots from the installed functions,
 -- including migration243's mandatory third-party package classification.
 foreach sig in array array['public.earn_credit_package_commission(uuid)','public.earn_premium_bundle_commission(uuid)'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  if position('invoice_package_retained_commission_basis' in f)>0 then continue; end if;
  anchor:='v_base := round(coalesce(s.external_paid,0), 2);';
  if position(anchor in f)=0 then raise exception 'Unexpected package earning definition: %',sig; end if;
  patched:=anchor||E'\n  v_base := public.invoice_package_retained_commission_basis('||quote_literal(case when sig like '%earn_credit_package%' then 'credit_package' else 'premium_bundle' end)||',s.id,v_base);';
  execute replace(f,anchor,patched);
 end loop;
 select pg_get_functiondef('public.reconcile_invoice_commissions(uuid,text)'::regprocedure) into f;
 if position('adjust_invoice_line_commission_refunds' in f)=0 then
  anchor:=' select array_agg(id) into v_before from public.commissions where invoice_id=i.id;';
  if position(anchor in f)=0 then raise exception 'Unexpected invoice commission snapshot anchor'; end if;
  f:=replace(f,anchor,' if i.status not in (''cancelled'',''refunded'') then perform public.assert_invoice_commission_refund_evidence(i.id); end if;'||E'\n'||anchor);
  anchor:='   v_share:=case when i.total_amount>0 then least(1,greatest(0,public.invoice_net_received(i.id))/i.total_amount) else 0 end;'||E'\n'||
   '   update public.commissions set commission_amount=round(commission_amount*v_share,2),line_amount=round(line_amount*v_share,2)'||E'\n'||
   '    where invoice_id=i.id and not(id=any(coalesce(v_before,''{}''::uuid[])));';
  if position(anchor in f)=0 then raise exception 'Unexpected invoice-wide commission scaling anchor'; end if;
  f:=replace(f,anchor,'   perform public.adjust_invoice_line_commission_refunds(i.id,v_before);');
  execute f;
 end if;
end $$;
revoke all on function public.assert_invoice_commission_refund_evidence(uuid),public.invoice_commission_benefit_source(uuid),
 public.invoice_package_retained_commission_basis(text,uuid,numeric),public.adjust_invoice_line_commission_refunds(uuid,uuid[]) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
