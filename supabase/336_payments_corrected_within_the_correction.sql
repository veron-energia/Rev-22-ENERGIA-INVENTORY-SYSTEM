begin;
-- =====================================================================
-- A PAYMENT'S AMOUNT, DATE AND METHOD ARE CORRECTED INSIDE THE CORRECTION
--
-- The correction form could only change which method a payment came through.
-- Its amount and date were correctable from the invoice's payment list, one
-- payment at a time, through correct_invoice_payment (175): the original
-- receipt stays, a reversal and a replacement are recorded with a reason, the
-- invoice's paid amount and status are recomputed, commission is reconciled.
--
-- This lets the correction carry those changes, so one save with one reason
-- and one preview covers the lines, the header and the money:
--
--   header.payment_corrections = [{payment_id, amount, date, payment_method_id}]
--   header.payment_removals    = [payment_id, ...]
--
-- Corrections run through correct_invoice_payment unchanged. Removals are new:
-- a receipt recorded by mistake is reversed with the reason and nothing else —
-- no replacement, no refund record, because no money went back. Wallet-credit
-- payments are refused here as they are everywhere in the form: they consumed
-- credit, and the payment list's own button has the lot checks for that.
--
-- Each payment change gets a request id derived from the correction's own, so
-- replaying the correction (invoice_revision_retry) cannot apply them twice.
-- The preview describes each change and what the invoice looks like after:
-- still paid, back to partially paid, or overpaid with a refund due.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Removing a payment recorded by mistake.
-- ---------------------------------------------------------------------
create or replace function public.remove_invoice_payment(p_payment_id uuid, p_reason text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare p public.invoice_payments%rowtype; i public.invoices%rowtype; m public.payment_methods%rowtype;
        v_reverse uuid := gen_random_uuid(); n numeric;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can remove a payment'; end if;
  if nullif(trim(p_reason), '') is null or p_request_id is null then
    raise exception 'A reason and request ID are required to remove a payment'; end if;
  select * into p from public.invoice_payments where id = p_payment_id;
  if not found then raise exception 'Payment not found'; end if;
  select * into i from public.invoices where id = p.invoice_id for update;
  if not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;

  -- The same request again returns the same answer and writes nothing.
  if exists (select 1 from public.invoice_payments where invoice_id = i.id and correction_request_id = p_request_id) then
    if not exists (select 1 from public.invoice_payments q
                    where q.invoice_id = i.id and q.correction_request_id = p_request_id
                      and q.entry_kind = 'correction_reversal' and q.corrects_payment_id = p.id
                      and q.correction_reason = p_reason) then
      raise exception 'This correction request ID was already used for different payment details'; end if;
    return public.invoice_financial_position(i.id) || jsonb_build_object('success', true, 'replayed', true);
  end if;

  if p.entry_kind = 'correction_reversal'
     or exists (select 1 from public.invoice_payments where corrects_payment_id = p.id and entry_kind = 'correction_reversal') then
    raise exception 'Select the current replacement payment'; end if;
  select * into m from public.payment_methods where id = p.payment_method_id;
  if coalesce(m.is_wallet_credit, false) then
    raise exception 'A wallet credit payment consumed credit from the wallet; correct it from the invoice''s payment list or refund it'; end if;
  if public.invoice_payment_remaining(p.id) < p.amount then
    raise exception 'Refunds were issued against this payment, so it cannot be removed'; end if;

  -- A bookkeeping reversal only. Nothing was returned to the customer, so no
  -- invoice_refunds row.
  insert into public.invoice_payments(id, invoice_id, payment_method_id, amount, entry_kind, corrects_payment_id,
    correction_reason, correction_request_id, effective_at, received_by)
  values (v_reverse, i.id, p.payment_method_id, p.amount, 'correction_reversal', p.id,
    p_reason, p_request_id, coalesce(p.effective_at, p.created_at), auth.uid());

  n := public.invoice_net_received(i.id);
  update public.invoices
     set paid_amount = n,
         status = case when i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then i.status
                       when n >= public.invoice_charge_total(i.id) then 'paid'::public.invoice_status
                       when n > 0 then 'partially_paid'::public.invoice_status
                       else 'unpaid'::public.invoice_status end
   where id = i.id;
  perform public.reconcile_invoice_commissions(i.id, 'Payment removed: ' || p_reason);
  perform public.write_audit_ex('invoice_payments', p.id, 'payment_removed', to_jsonb(p),
    jsonb_build_object('reversal', v_reverse, 'amount', p.amount), 'payments', p_reason, i.store_id);
  return public.invoice_financial_position(i.id) || jsonb_build_object('success', true, 'reversal_id', v_reverse);
end $$;
revoke all on function public.remove_invoice_payment(uuid, text, uuid) from public, anon;
grant execute on function public.remove_invoice_payment(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 2. correct_invoice carries the payment changes. Anchored on the installed
--    body; refuses to guess.
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('payment_corrections' in f) > 0 then return; end if;  -- already done

  -- A loop variable for the payment changes.
  if position('declare i public.invoices%rowtype; n public.invoices%rowtype;' in f) = 0 then
    raise exception '336: correct_invoice declarations are not where 336 expects them'; end if;
  f := replace(f, 'declare i public.invoices%rowtype; n public.invoices%rowtype;',
                  'declare i public.invoices%rowtype; n public.invoices%rowtype; c record;');

  -- A save that only changes payments is not a no-op.
  if position('if same_lines and same_header and coalesce(p_header->''payment_methods'',''[]'')=''[]''::jsonb then' in f) = 0 then
    raise exception '336: correct_invoice no-op test is not where 336 expects it'; end if;
  f := replace(f, 'if same_lines and same_header and coalesce(p_header->''payment_methods'',''[]'')=''[]''::jsonb then',
    'if same_lines and same_header and coalesce(p_header->''payment_methods'',''[]'')=''[]''::jsonb'
    || ' and coalesce(p_header->''payment_corrections'',''[]'')=''[]''::jsonb'
    || ' and coalesce(p_header->''payment_removals'',''[]'')=''[]''::jsonb then');

  -- After the method-only corrections, before the paid amount and status are
  -- read back: the amount and date corrections, then the removals.
  if position('   perform public.correct_invoice_payment_methods(i.id,p_header->''payment_methods'',p_reason); end if;' in f) = 0 then
    raise exception '336: correct_invoice payment-method call is not where 336 expects it'; end if;
  f := replace(f, '   perform public.correct_invoice_payment_methods(i.id,p_header->''payment_methods'',p_reason); end if;',
'   perform public.correct_invoice_payment_methods(i.id,p_header->''payment_methods'',p_reason); end if;
 -- 336: amount and date corrections and removals go through the same rules the
 -- per-payment buttons use, inside this transaction, each with a request id
 -- derived from this correction''s so a replay cannot apply them twice.
 for c in select * from jsonb_array_elements(coalesce(p_header->''payment_corrections'',''[]''::jsonb)) loop
   perform public.correct_invoice_payment((c.value->>''payment_id'')::uuid,(c.value->>''amount'')::numeric,(c.value->>''date'')::date,
     nullif(c.value->>''payment_method_id'','''')::uuid,coalesce(p_reason,''Invoice edited''),
     md5(coalesce(p_request_id::text,i.id::text)||''/correct/''||(c.value->>''payment_id''))::uuid);
 end loop;
 for c in select * from jsonb_array_elements_text(coalesce(p_header->''payment_removals'',''[]''::jsonb)) loop
   perform public.remove_invoice_payment(c.value::uuid,coalesce(p_reason,''Invoice edited''),
     md5(coalesce(p_request_id::text,i.id::text)||''/remove/''||c.value)::uuid);
 end loop;');
  execute f;
end $$;

-- ---------------------------------------------------------------------
-- 3. The preview says what each payment change does, and what the invoice
--    looks like afterwards. Anything the rules would refuse is a review item.
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  select pg_get_functiondef('public.preview_invoice_correction(uuid,jsonb)'::regprocedure) into f;
  if position('payment_corrections' in f) > 0 then return; end if;  -- already done
  if position('v_moving jsonb; v_blocked jsonb; r record;' in f) = 0
     or position('  -- ---- things that stop the save -----------------------------------------' in f) = 0 then
    raise exception '336: preview_invoice_correction is not where 336 expects it'; end if;
  f := replace(f, 'v_moving jsonb; v_blocked jsonb; r record;',
    'v_moving jsonb; v_blocked jsonb; r record; v_net numeric; v_charge numeric; v_amount numeric; p public.invoice_payments%rowtype; pm public.payment_methods%rowtype;');
  f := replace(f, '  -- ---- things that stop the save -----------------------------------------',
'  -- ---- payments (336) ----------------------------------------------------
  -- The same checks correct_invoice_payment and remove_invoice_payment make,
  -- said here so the save is not refused after the operator confirmed it.
  if jsonb_array_length(coalesce(p_header->''payment_corrections'',''[]''::jsonb)) > 0
     or jsonb_array_length(coalesce(p_header->''payment_removals'',''[]''::jsonb)) > 0 then
    v_net := public.invoice_net_received(i.id);
    for r in select value from jsonb_array_elements(coalesce(p_header->''payment_corrections'',''[]''::jsonb)) loop
      select * into p from public.invoice_payments where id = nullif(r.value->>''payment_id'','''')::uuid and invoice_id = i.id;
      if not found then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',''A payment in this save does not belong to this invoice.''));
        continue; end if;
      select * into pm from public.payment_methods where id = p.payment_method_id;
      v_amount := coalesce((r.value->>''amount'')::numeric, 0);
      if p.entry_kind = ''correction_reversal'' or exists (select 1 from public.invoice_payments where corrects_payment_id = p.id and entry_kind = ''correction_reversal'') then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''The %s payment of S$%s was already corrected; the current replacement is the one to change.'', pm.name, to_char(p.amount,''FM999999990.00''))));
        continue; end if;
      if coalesce(pm.is_wallet_credit,false) then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''The %s payment of S$%s was made with wallet credit. It is corrected from the invoice''''s payment list, which checks the credit lots, not here.'', pm.name, to_char(p.amount,''FM999999990.00''))));
        continue; end if;
      if v_amount <= 0 then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''The %s payment needs a positive corrected amount. To take it out, mark it as recorded by mistake.'', pm.name)));
        continue; end if;
      if v_amount < p.amount - public.invoice_payment_remaining(p.id) then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''The %s payment cannot be corrected below S$%s, the refunds already issued against it.'', pm.name, to_char(p.amount - public.invoice_payment_remaining(p.id),''FM999999990.00''))));
        continue; end if;
      if nullif(r.value->>''date'','''') is null then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''The %s payment needs the date the money was actually received.'', pm.name)));
        continue; end if;
      v_net := v_net - public.invoice_payment_remaining(p.id) + v_amount;
      v_effects := v_effects || jsonb_build_array(jsonb_build_object(''area'',''payments'',''change'',''corrected'',
        ''from'', format(''%s S$%s on %s'', pm.name, to_char(p.amount,''FM999999990.00''), to_char(coalesce(p.effective_at,p.created_at) at time zone ''Asia/Singapore'',''DD Mon YYYY'')),
        ''to'', format(''%s S$%s on %s'', coalesce((select name from public.payment_methods where id = nullif(r.value->>''payment_method_id'','''')::uuid), pm.name), to_char(v_amount,''FM999999990.00''), to_char((r.value->>''date'')::date,''DD Mon YYYY'')),
        ''detail'',''The original receipt stays in history; a reversal and a replacement are recorded with this correction''''s reason. No customer refund is recorded.''));
    end loop;
    for r in select value from jsonb_array_elements_text(coalesce(p_header->''payment_removals'',''[]''::jsonb)) loop
      select * into p from public.invoice_payments where id = nullif(r.value,'''')::uuid and invoice_id = i.id;
      if not found then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',''A payment in this save does not belong to this invoice.''));
        continue; end if;
      select * into pm from public.payment_methods where id = p.payment_method_id;
      if p.entry_kind = ''correction_reversal'' or exists (select 1 from public.invoice_payments where corrects_payment_id = p.id and entry_kind = ''correction_reversal'') then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''The %s payment of S$%s was already corrected; the current replacement is the one to remove.'', pm.name, to_char(p.amount,''FM999999990.00''))));
        continue; end if;
      if coalesce(pm.is_wallet_credit,false) then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''The %s payment of S$%s was made with wallet credit and cannot be removed here. Refund it, or correct it from the invoice''''s payment list.'', pm.name, to_char(p.amount,''FM999999990.00''))));
        continue; end if;
      if public.invoice_payment_remaining(p.id) < p.amount then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''Refunds were issued against the %s payment of S$%s, so it cannot be removed.'', pm.name, to_char(p.amount,''FM999999990.00''))));
        continue; end if;
      v_net := v_net - public.invoice_payment_remaining(p.id);
      v_effects := v_effects || jsonb_build_array(jsonb_build_object(''area'',''payments'',''change'',''removed'',
        ''from'', format(''%s S$%s on %s'', pm.name, to_char(p.amount,''FM999999990.00''), to_char(coalesce(p.effective_at,p.created_at) at time zone ''Asia/Singapore'',''DD Mon YYYY'')),
        ''to'', null,
        ''detail'',''Recorded by mistake: the receipt is reversed with this correction''''s reason. No customer refund is recorded, because no money went back.''));
    end loop;
    -- What the invoice looks like afterwards, against its current total.
    v_charge := public.invoice_charge_total(i.id);
    v_effects := v_effects || jsonb_build_array(jsonb_build_object(''area'',''payments'',
      ''change'', case when v_net > 0 and v_net >= v_charge - 0.001 then ''still paid'' when v_net > 0 then ''partially paid'' else ''unpaid'' end,
      ''detail'', case
        when v_net > v_charge + 0.001 then format(''Payments will total S$%s against a total of S$%s: the invoice stays paid and S$%s is shown as refund due.'', to_char(v_net,''FM999999990.00''), to_char(v_charge,''FM999999990.00''), to_char(v_net - v_charge,''FM999999990.00''))
        when v_net > 0 and v_net >= v_charge - 0.001 then format(''Payments will total S$%s, which still settles the S$%s invoice.'', to_char(v_net,''FM999999990.00''), to_char(v_charge,''FM999999990.00''))
        when v_net > 0 then format(''Payments will total S$%s of S$%s: the invoice goes back to partially paid with S$%s outstanding. Benefits already issued at payment stay issued.'', to_char(v_net,''FM999999990.00''), to_char(v_charge,''FM999999990.00''), to_char(v_charge - v_net,''FM999999990.00''))
        else format(''No payment is left on the invoice: it goes back to unpaid with S$%s outstanding. Benefits already issued at payment stay issued.'', to_char(v_charge,''FM999999990.00'')) end));
  end if;

  -- ---- things that stop the save -----------------------------------------');
  execute f;
end $$;

do $$
declare f text;
begin
  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('remove_invoice_payment' in f) = 0 or position('payment_corrections' in f) = 0 then
    raise exception '336: the payment changes did not land in correct_invoice'; end if;
  select pg_get_functiondef('public.preview_invoice_correction(uuid,jsonb)'::regprocedure) into f;
  if position('payment_removals' in f) = 0 then
    raise exception '336: the payment changes did not land in preview_invoice_correction'; end if;
end $$;

notify pgrst, 'reload schema';
commit;
