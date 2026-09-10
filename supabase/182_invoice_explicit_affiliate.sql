begin;
-- NULL plus an explicit choice means no affiliate; untouched legacy NULL keeps
-- the established customer-referrer fallback.
do $$ declare f text; sig text; begin
 select pg_get_functiondef('public.earn_invoice_commission(uuid)'::regprocedure) into f;
 if position('if v_inv.affiliate_id is not null then' in f)=0 then raise exception 'Unexpected affiliate commission definition'; end if;
 execute replace(f,'if v_inv.affiliate_id is not null then',
 'if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return; end if;'||chr(10)||'  if v_inv.affiliate_id is not null then');
 select pg_get_functiondef('public.invoice_effective_affiliate(uuid)'::regprocedure) into f;
 execute replace(f,'if v_inv.affiliate_id is not null then',
 'if not public.user_has_store_access(v_inv.store_id) then raise exception ''Invoice not accessible''; end if;'||chr(10)||
 '  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return jsonb_build_object(''found'',true,''has_affiliate'',false,''source'',''none''); end if;'||chr(10)||
 '  if v_inv.affiliate_id is not null then');
 foreach sig in array array['public.earn_credit_package_commission(uuid)','public.earn_premium_bundle_commission(uuid)'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  if position('if v_inv.affiliate_id is not null then' in f)=0 then raise exception 'Unexpected credit affiliate function: %',sig; end if;
  execute replace(f,'if v_inv.affiliate_id is not null then','if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return jsonb_build_object(''skipped'',true,''reason'',''Affiliate explicitly cleared''); end if;'||chr(10)||'  if v_inv.affiliate_id is not null then');
 end loop;
 select pg_get_functiondef('public.set_invoice_affiliate(uuid,uuid)'::regprocedure) into f;
 if position('set affiliate_id = p_affiliate_id' in f)=0 then raise exception 'Unexpected invoice affiliate setter'; end if;
 execute replace(f,'set affiliate_id = p_affiliate_id','set affiliate_selection_explicit=true, affiliate_id = p_affiliate_id');
end $$;
notify pgrst,'reload schema';
commit;
