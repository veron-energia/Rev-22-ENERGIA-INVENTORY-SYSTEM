begin;
-- =====================================================================
-- SAY WHICH OF THE TWO CORRECTIONS THIS IS
--
-- Changing an invoice's customer is two different operations wearing one name:
--
--   A. Change the customer AND move the unused benefits with it.
--   B. Change the customer and LEAVE the benefits with who holds them.
--
-- There was one boolean, preserve_issued_recipients, and it meant neither
-- cleanly. The checkbox told the operator that "recorded recipients remain
-- unchanged", and ticking it was what allowed the correction to proceed and
-- move the benefits anyway. The label and the behaviour said opposite things,
-- and there was no way at all to ask for B.
--
-- benefit_action names the operation. It is required rather than defaulted:
-- guessing which of two irreversible outcomes somebody meant is how the
-- previous version went wrong.
-- =====================================================================
do $do$
declare f text;
begin
  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('benefit_action' in f) = 0 then
    -- Replace the acknowledgement gate with an explicit choice.
    f := replace(f,
      ' if (n.customer_id,n.store_id) is distinct from (i.customer_id,i.store_id)
   and exists(select 1 from public.invoice_items where invoice_id=i.id and credit_issued_at is not null)
   and not coalesce((p_header->>''preserve_issued_recipients'')::boolean,false) then
  raise exception ''Review the issued recipients first. Move unused benefits in Invoice settlement if needed, then explicitly confirm that the recorded recipients and benefit stores should remain unchanged.'';
 end if;',
      ' -- Which of the two corrections is this? Required whenever the customer or
 -- store changes and this invoice actually issued something.
 -- Only when the CUSTOMER changes. That is the correction with two meanings;
 -- a store move keeps the behaviour it has always had rather than growing a
 -- question about benefits it was not asking.
 if n.customer_id is distinct from i.customer_id
   and exists(select 1 from public.invoice_transferable_benefits(i.id)) then
  if coalesce(p_header->>''benefit_action'','''') not in (''transfer'',''keep'') then
   raise exception ''BENEFIT_ACTION_REQUIRED: This invoice issued benefits. Choose whether to move the unused ones to the new customer (transfer) or leave them with whoever holds them now (keep).'';
  end if;
 end if;');

    -- And act on it where the move happens.
    f := replace(f,
      '   -- The vouchers, credit and allowances this invoice produced follow it. The
   -- call refuses the whole correction if any of them has been used.
   perform public.move_invoice_benefits_to_customer(i.id,n.customer_id,n.store_id,
     coalesce(p_reason,''Invoice reassigned''));',
      '   -- Only when asked. "keep" changes the invoice''s customer and leaves the
   -- benefits where they are, which stays visible because the benefits are
   -- found through this invoice''s own lines and sales rather than its customer.
   if coalesce(p_header->>''benefit_action'','''') = ''transfer'' then
     perform public.move_invoice_benefits_to_customer(i.id,n.customer_id,n.store_id,
       coalesce(p_reason,''Invoice reassigned''));
   end if;');

    if position('benefit_action' in f) = 0 or position('BENEFIT_ACTION_REQUIRED' in f) = 0 then
      raise exception 'correct_invoice does not match what 322 expects — align it by hand'; end if;
    execute f;
    raise notice 'correct_invoice now requires an explicit benefit action';
  end if;
end $do$;

-- The therapy units moved unconditionally alongside. They are benefits too, so
-- they follow the same choice.
do $do$
declare f text;
begin
  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('benefit_action'') = ''transfer'' then
   update public.purchased_therapy' in f) = 0 then
    f := replace(f,
      '   update public.purchased_therapy_entitlements set customer_id=n.customer_id,store_id=n.store_id,updated_at=now()
    where invoice_id=i.id and status in (''pending_activation'',''scheduled'');',
      '   if coalesce(p_header->>''benefit_action'','''') = ''transfer'' then
   update public.purchased_therapy_entitlements set customer_id=n.customer_id,store_id=n.store_id,updated_at=now()
    where invoice_id=i.id and status in (''pending_activation'',''scheduled'');
   end if;');
    execute f;
    raise notice 'therapy units now follow the same benefit action';
  end if;
end $do$;

-- ---------------------------------------------------------------------
-- The preview states which action it is describing.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.preview_invoice_correction(uuid,jsonb)'::regprocedure) into f;
  if position('benefit_action' in f) = 0 then
    f := replace(f,
      '    if jsonb_array_length(v_moving) > 0 then',
      '    -- The summary has to describe the operation that will actually run.
    if coalesce(p_header->>''benefit_action'','''') = ''keep'' then
      v_effects := v_effects || jsonb_build_array(jsonb_build_object(
        ''area'',''benefits'',''change'',''kept'',
        ''detail'',''The benefits stay with whoever holds them now. Only the invoice''''s customer changes, and the invoice still finds them for refunds and later corrections.''));
      v_moving := ''[]''::jsonb;
      v_blocked := ''[]''::jsonb;
    elsif coalesce(p_header->>''benefit_action'','''') = '''' then
      v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(
        ''area'',''benefits'',
        ''detail'',''Choose whether the unused benefits move to the new customer or stay with whoever holds them now.''));
    end if;
    if jsonb_array_length(v_moving) > 0 then');
    if position('benefit_action' in f) = 0 then
      raise exception 'preview_invoice_correction does not match what 322 expects — align it by hand'; end if;
    execute f;
    raise notice 'preview_invoice_correction now reflects the chosen action';
  end if;
end $do$;

notify pgrst,'reload schema';
commit;
