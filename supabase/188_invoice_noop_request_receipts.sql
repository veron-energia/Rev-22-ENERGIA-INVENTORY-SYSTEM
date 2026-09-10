begin;
-- Successful no-op requests need a receipt too. Otherwise a late retry after
-- another edit/reopening could execute the old request as a new mutation.
do $$ declare f text; anchor text; begin
 select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 anchor:=' if same_lines and same_header and coalesce(p_header->''payment_methods'',''[]'')=''[]''::jsonb then';
 if position(anchor in f)=0 then raise exception 'Unexpected unchanged correction branch'; end if;
 execute replace(f,anchor,anchor||$patch$
   if p_request_id is not null then
    select coalesce(max(revision_no),0)+1 into v_rev from public.invoice_revisions where invoice_id=i.id;
    insert into public.invoice_revisions(invoice_id,revision_no,snapshot,after_snapshot,edited_by,edit_reason,request_id,request_hash)
     values(i.id,v_rev,jsonb_build_object('invoice',to_jsonb(i),'unchanged',true),jsonb_build_object('invoice',to_jsonb(i),'unchanged',true),
      auth.uid(),p_reason,p_request_id,md5(jsonb_build_object('operation','correct','items',p_items,'header',p_header,'reason',p_reason)::text));
   end if;
$patch$);
 select pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure) into f;
 anchor:=' if i.status=''cancelled'' then';
 if position(anchor in f)=0 then raise exception 'Unexpected unchanged cancellation branch'; end if;
 execute replace(f,anchor,anchor||$patch$
   select coalesce(max(revision_no),0)+1 into v_rev from public.invoice_revisions where invoice_id=i.id;
   insert into public.invoice_revisions(invoice_id,revision_no,snapshot,after_snapshot,edited_by,edit_reason,request_id,request_hash)
    values(i.id,v_rev,jsonb_build_object('invoice',to_jsonb(i),'unchanged',true),jsonb_build_object('invoice',to_jsonb(i),'unchanged',true),
     auth.uid(),p_reason,p_request_id,md5(jsonb_build_object('operation','cancel','reason',p_reason)::text));
$patch$);
end $$;
notify pgrst,'reload schema';
commit;
