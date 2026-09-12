begin;
-- =====================================================================
-- THE PREVIEW DESCRIBED THE ACCOUNTING SPLIT, NOT THE CREDIT REMOVED
--
-- Reported on INV-2026-0210. A S$500 package granting S$500 paid credit and
-- S$25 bonus credit previewed as:
--
--     Remove S$476.19 paid credit
--     Remove S$23.81 bonus credit
--
-- Those two numbers are S$500 -- the money -- divided between the benefits in
-- proportion to what each was granted:
--
--     500 x 500/525 = 476.19        500 x 25/525 = 23.81
--
-- which is invoice_benefit_values.paid_value: the share of the PRICE carried by
-- each benefit, used to cap refunds at the unused portion. It is not, and was
-- never, the amount of credit taken off the customer. The execution removed
-- S$500 paid and S$25 bonus, which is correct, so the preview was describing a
-- different quantity from the one it was labelling.
--
-- Verified in an isolated database before changing anything: the preview
-- reproduced 476.19 / 23.81 exactly, and the execution then cleared both lots
-- to zero. Nothing about the deduction is changed here. Only the description.
--
-- Four quantities are now kept apart, because they are four different things:
--
--   money returned        what goes back to the customer, by payment source
--   accounting value      each benefit's share of the price (unchanged, and
--                         still what caps the refund)
--   credit removed        the actual paid / bonus face value taken back
--   units revoked         whole unused voucher units
--
-- Credit removed can exceed money returned, and legitimately does here:
-- S$525 of credit for S$500, because the bonus was a gift.
--
-- Derived with the same rule the engine applies -- including 299's exact
-- clearing when the whole refundable value is taken -- so preview,
-- approval-time revalidation and execution cannot disagree.
--
-- Requires 296 and 299. Idempotent.
-- =====================================================================
do $do$
declare f text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.invoice_action_plan(uuid,text,jsonb)'::regprocedure) into f;
 if position('credit_removed' in f)>0 then
  raise notice 'the plan already reports the credit actually removed'; return; end if;

 -- ---- 1. carry the real quantities on every benefit ----------------------
 v_old:=
'   if v_take>0 then'||E'\n'||
'    v_ben:=v_ben||jsonb_build_array(jsonb_build_object(''benefit_id'',b->>''id'',''amount'',v_take,'||E'\n'||
'      ''kind'',b->>''benefit_kind'',''holder'',b->>''customer_name'',''holder_id'',b->>''customer_id''));'||E'\n'||
'    v_left:=round(v_left-v_take,2);'||E'\n'||
'   end if;';
 v_new:=
'   if v_take>0 then'||E'\n'||
'    -- What actually comes off the customer, by the engine''s own rule: taking'||E'\n'||
'    -- the whole refundable value clears the balance exactly (299), otherwise'||E'\n'||
'    -- the money converts back to granted units.'||E'\n'||
'    if v_take>=round(coalesce((b->>''max_refund'')::numeric,0),2) then'||E'\n'||
'      v_removed:=coalesce((b->>''remaining_value'')::numeric,0);'||E'\n'||
'    else'||E'\n'||
'      v_removed:=least(coalesce((b->>''remaining_value'')::numeric,0),'||E'\n'||
'                 round(v_take*coalesce((b->>''granted_value'')::numeric,0)/nullif((b->>''paid_value'')::numeric,0),2));'||E'\n'||
'    end if;'||E'\n'||
'    v_ben:=v_ben||jsonb_build_array(jsonb_build_object(''benefit_id'',b->>''id'',''amount'',v_take,'||E'\n'||
'      ''kind'',b->>''benefit_kind'',''holder'',b->>''customer_name'',''holder_id'',b->>''customer_id'','||E'\n'||
'      -- amount        = this benefit''s share of the PRICE (accounting only)'||E'\n'||
'      -- credit_removed= the actual paid/bonus credit taken back'||E'\n'||
'      -- units_revoked = whole unused voucher units cancelled'||E'\n'||
'      ''accounting_value'',v_take,'||E'\n'||
'      ''credit_removed'',case when nullif(b->>''reward_voucher_id'','''') is null then round(v_removed,2) end,'||E'\n'||
'      ''units_revoked'',case when nullif(b->>''reward_voucher_id'','''') is not null then round(v_removed)::int end));'||E'\n'||
'    v_left:=round(v_left-v_take,2);'||E'\n'||
'   end if;';
 if position(v_old in f)=0 then
  raise exception 'The benefit allocation block of invoice_action_plan does not match what 303 expects — align it by hand'; end if;
 f:=replace(f,v_old,v_new);

 -- ---- 2. say it in the summary, separated by kind ------------------------
 v_old:=
'   v_sum:=v_sum||jsonb_build_array(case when b->>''kind''=''voucher'''||E'\n'||
'     then ''Cancel unused voucher units from ''||(x->>''name'')||''.'''||E'\n'||
'     else ''Remove S$''||to_char((b->>''amount'')::numeric,''FM999999990.00'')||'' of ''||coalesce(b->>''kind'','''')||'' credit''||'||E'\n'||
'          coalesce('' from ''||(b->>''holder''),'''')||''.'' end);';
 v_new:=
'   v_sum:=v_sum||jsonb_build_array(case when b->>''kind''=''voucher'''||E'\n'||
'     then ''Cancel ''||coalesce((b->>''units_revoked''),''0'')||'' unused voucher unit(s) from ''||(x->>''name'')||'''||E'\n'||
'          ''||coalesce(''for ''||(b->>''holder''),'''')||''.'''||E'\n'||
'     else ''Remove S$''||to_char(coalesce((b->>''credit_removed'')::numeric,0),''FM999999990.00'')||'' of ''||'||E'\n'||
'          coalesce(b->>''kind'','''')||'' credit''||coalesce('' from ''||(b->>''holder''),'''')||''.'' end);';
 if position(v_old in f)=0 then
  raise exception 'The benefit summary line of invoice_action_plan does not match what 303 expects — align it by hand'; end if;
 f:=replace(f,v_old,v_new);

 -- ---- 3. declare the working variable ------------------------------------
 v_old:=' v_new_sel jsonb; v_cap numeric; v_one numeric;';
 if position(v_old in f)=0 then
  raise exception 'The declare block of invoice_action_plan does not match what 303 expects — align it by hand'; end if;
 f:=replace(f,v_old,' v_new_sel jsonb; v_cap numeric; v_one numeric; v_removed numeric;');

 -- ---- 4. a structured block the interface can lay out --------------------
 v_old:='  ''requires_override'',jsonb_array_length(v_over)>0,''blocked'',jsonb_array_length(v_block)>0,';
 v_new:=
'  ''requires_override'',jsonb_array_length(v_over)>0,''blocked'',jsonb_array_length(v_block)>0,'||E'\n'||
'  -- The review''s sections, already separated, so the interface never has to'||E'\n'||
'  -- infer one quantity from another.'||E'\n'||
'  ''effects'',jsonb_build_object('||E'\n'||
'    ''money_returned'',jsonb_build_object('||E'\n'||
'      ''total'',case when p_action=''cancel'' then round(v_due,2) else v_total end,'||E'\n'||
'      ''destinations'',v_src),'||E'\n'||
'    ''benefits'',(select coalesce(jsonb_agg(q),''[]''::jsonb) from ('||E'\n'||
'        select jsonb_build_object('||E'\n'||
'          ''kind'',bb->>''kind'',''holder'',bb->>''holder'',''holder_id'',bb->>''holder_id'','||E'\n'||
'          ''credit_removed'',bb->''credit_removed'',''units_revoked'',bb->''units_revoked'','||E'\n'||
'          ''accounting_value'',bb->''accounting_value'',''line'',ll->>''name'') q'||E'\n'||
'        from jsonb_array_elements(v_sel) ll,'||E'\n'||
'             jsonb_array_elements(coalesce(ll->''benefits'',''[]''::jsonb)) bb) s),'||E'\n'||
'    ''stock_returned'',v_stock,'||E'\n'||
'    ''overrides'',v_over),';
 if position(v_old in f)=0 then
  raise exception 'The return object of invoice_action_plan does not match what 303 expects — align it by hand'; end if;
 f:=replace(f,v_old,v_new);

 execute f;
 raise notice 'the preview now reports the credit actually removed, apart from the money returned';
end $do$;

notify pgrst,'reload schema';
commit;
