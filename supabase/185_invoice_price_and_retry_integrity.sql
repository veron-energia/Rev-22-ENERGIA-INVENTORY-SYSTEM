begin;
-- A price correction does not redefine an already purchased credit entitlement.
create function public.invoice_benefit_price_only(p_item_id uuid,p_line jsonb)
returns boolean language sql stable security definer set search_path=public as $$
 select coalesce((select it.line_kind in ('credit_package','premium_bundle')
  and p_line ? 'unit_price' and (p_line->>'unit_price')::numeric>=0
  and public.invoice_line_matches(it.id,p_line||jsonb_build_object('unit_price',it.unit_price))
  from public.invoice_items it where it.id=p_item_id),false)
$$;
revoke all on function public.invoice_benefit_price_only(uuid,jsonb) from public,anon,authenticated;

do $$ declare f text; anchor text; replacement text; begin
 select pg_get_functiondef('public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'::regprocedure) into f;
 anchor:='    if found and public.invoice_line_matches(v_original_line.id,v_item) then';
 replacement:=$patch$    if found and public.invoice_benefit_price_only(v_original_line.id,v_item)
       and not public.invoice_line_matches(v_original_line.id,v_item) then
      if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct a package price'; end if;
      -- Only the charged amount changes. Grant, recipient and catalogue snapshots
      -- remain the original evidence, including when the catalogue was retired.
      v_original_line.line_total:=round((v_item->>'unit_price')::numeric*v_original_line.quantity,2);
    end if;
    if found and (public.invoice_line_matches(v_original_line.id,v_item)
      or public.invoice_benefit_price_only(v_original_line.id,v_item)) then$patch$;
 if position(anchor in f)=0 then raise exception 'Unexpected invoice pricing definition'; end if;
 f:=replace(f,anchor,replacement);
 anchor:='    if public.invoice_line_matches(nullif(v_item->>''invoice_item_id'','''')::uuid,v_item) then continue; end if;';
 replacement:=anchor||$patch$
    if public.invoice_benefit_price_only(nullif(v_item->>'invoice_item_id','')::uuid,v_item) then
      update public.invoice_items set unit_price=(v_item->>'unit_price')::numeric,
        line_total=round((v_item->>'unit_price')::numeric*quantity,2),
        price_overridden=true,override_reason=p_edit_reason,override_by=auth.uid(),override_at=now()
      where id=(v_item->>'invoice_item_id')::uuid and invoice_id=p_invoice_id;
      continue;
    end if;$patch$;
 if position(anchor in f)=0 then raise exception 'Unexpected invoice item writer'; end if;
 execute replace(f,anchor,replacement);
 select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 anchor:='where public.invoice_line_matches(it.id,x))))';
 if position(anchor in f)=0 then raise exception 'Unexpected issued-benefit correction guard'; end if;
 execute replace(f,anchor,'where public.invoice_line_matches(it.id,x) or public.invoice_benefit_price_only(it.id,x))))');
end $$;

-- Bind retry identifiers to the operation and exact submitted data, including
-- cancellation requests replayed after a subsequent reopening.
alter table public.invoice_revisions add column request_hash text;
create function public.invoice_revision_retry(p_invoice_id uuid,p_request_id uuid,p_payload jsonb)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare h text;
begin
 if p_request_id is null then return false; end if;
 select request_hash into h from public.invoice_revisions where invoice_id=p_invoice_id and request_id=p_request_id;
 if not found then return false; end if;
 if h is distinct from md5(p_payload::text) then
  raise exception 'This invoice request ID was already used for different details. Reload before starting another operation.';
 end if;
 return true;
end $$;
revoke all on function public.invoice_revision_retry(uuid,uuid,jsonb) from public,anon,authenticated;
do $$ declare f text; sig text; payload text; anchor text; begin
 foreach sig in array array['public.correct_invoice(uuid,jsonb,jsonb,text,uuid)',
  'public.reopen_invoice(uuid,text,uuid)','public.cancel_invoice_recorded(uuid,text,uuid)'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  payload:=case when sig like '%correct_invoice(%' then 'jsonb_build_object(''operation'',''correct'',''items'',p_items,''header'',p_header,''reason'',p_reason)'
    when sig like '%reopen_invoice(%' then 'jsonb_build_object(''operation'',''reopen'',''reason'',p_reason)'
    else 'jsonb_build_object(''operation'',''cancel'',''reason'',p_reason)' end;
  if sig like '%correct_invoice(%' then
   anchor:='p_request_id is not null and exists(select 1 from public.invoice_revisions where invoice_id=i.id and request_id=p_request_id)';
  elsif sig like '%reopen_invoice(%' then
   anchor:='exists(select 1 from public.invoice_revisions where invoice_id=i.id and request_id=p_request_id)';
   f:=replace(f,' if '||anchor,' if not found or not public.user_has_store_access(i.store_id) then raise exception ''Invoice not accessible''; end if;'||chr(10)||' if '||anchor);
  else
   anchor:=' if i.status=''cancelled'' then';
   if position(anchor in f)=0 then raise exception 'Unexpected cancellation retry definition'; end if;
   f:=replace(f,anchor,' if public.invoice_revision_retry(i.id,p_request_id,'||payload||') then return public.invoice_financial_position(i.id)||jsonb_build_object(''success'',true,''replayed'',true); end if;'||chr(10)||anchor);
  end if;
  if sig not like '%cancel_invoice_recorded(%' then
   if position(anchor in f)=0 then raise exception 'Unexpected invoice retry definition: %',sig; end if;
   f:=replace(f,anchor,'public.invoice_revision_retry(i.id,p_request_id,'||payload||')');
  end if;
  anchor:=' update public.invoice_revisions set after_snapshot=';
  if position(anchor in f)=0 then raise exception 'Unexpected invoice revision writer: %',sig; end if;
  execute replace(f,anchor,' update public.invoice_revisions set request_hash=md5(('||payload||')::text),after_snapshot=');
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
