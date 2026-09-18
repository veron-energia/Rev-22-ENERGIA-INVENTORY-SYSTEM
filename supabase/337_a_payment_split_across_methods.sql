begin;
-- =====================================================================
-- ONE PAYMENT, SEVERAL METHODS
--
-- 22 was keyed as cash; it was really 20 by PayNow and 2 in cash. 336 could
-- correct the receipt to another amount, date or method, but only to one of
-- each. This lets a correction replace one receipt with several parts.
--
-- The model is 175's, unchanged: the original receipt stays, one reversal is
-- recorded against it, and each part is a correction_replacement pointing at
-- it. Net received sums them; the payment list shows them as the current
-- payments; a refund can name any of them as its source. History reads as
-- one correction of one payment, under the correction's reason.
--
-- Parts may total more or less than the original (the money received is what
-- it is); the preview says what that does to the invoice. A payment that has
-- refunds against it is not split — its refunds are anchored to one payment,
-- and splitting would count them against every part.
--
-- 171's retry index allows one entry per request id and kind, so the reversal
-- carries the request id and each part carries one derived from it; a replay
-- is recognised by the reversal and compared part by part.
--
-- In the correction's header, a payment_corrections entry may carry
--   parts: [{amount, date, payment_method_id}, ...]
-- One part is the plain correction of 336; two or more are a split.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The rule.
-- ---------------------------------------------------------------------
create or replace function public.split_invoice_payment(p_payment_id uuid, p_parts jsonb, p_reason text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare p public.invoice_payments%rowtype; i public.invoices%rowtype; old_m public.payment_methods%rowtype;
        m public.payment_methods%rowtype; part record; v_reverse uuid := gen_random_uuid(); v_id uuid;
        v_ids uuid[] := '{}'; v_total numeric := 0; n numeric; v_expected jsonb; v_recorded jsonb;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can split a payment'; end if;
  if nullif(trim(p_reason), '') is null or p_request_id is null then
    raise exception 'A reason and request ID are required to split a payment'; end if;
  if jsonb_typeof(p_parts) is distinct from 'array' or jsonb_array_length(p_parts) < 2 then
    raise exception 'A split needs at least two parts'; end if;
  select * into p from public.invoice_payments where id = p_payment_id;
  if not found then raise exception 'Payment not found'; end if;
  select * into i from public.invoices where id = p.invoice_id for update;
  if not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;

  -- What this request asks for, in a form that can be compared on replay.
  select coalesce(jsonb_agg(jsonb_build_object('amount', round((x->>'amount')::numeric, 2), 'method', x->>'payment_method_id', 'date', x->>'date')
                            order by round((x->>'amount')::numeric, 2), x->>'payment_method_id', x->>'date'), '[]'::jsonb)
    into v_expected from jsonb_array_elements(p_parts) x;
  if exists (select 1 from public.invoice_payments where invoice_id = i.id and correction_request_id = p_request_id) then
    select coalesce(jsonb_agg(jsonb_build_object('amount', q.amount, 'method', q.payment_method_id::text, 'date', to_char(q.effective_at at time zone 'Asia/Singapore', 'YYYY-MM-DD'))
                              order by q.amount, q.payment_method_id::text, to_char(q.effective_at at time zone 'Asia/Singapore', 'YYYY-MM-DD')), '[]'::jsonb)
      into v_recorded from public.invoice_payments q
     where q.invoice_id = i.id and q.entry_kind = 'correction_replacement' and q.corrects_payment_id = p.id and q.correction_reason = p_reason
       and q.correction_request_id in (select md5(p_request_id::text || '/part/' || k)::uuid from generate_series(1, jsonb_array_length(p_parts)) k)
       and exists (select 1 from public.invoice_payments v where v.invoice_id = i.id and v.correction_request_id = p_request_id
                    and v.entry_kind = 'correction_reversal' and v.corrects_payment_id = p.id);
    if v_recorded <> v_expected then
      raise exception 'This correction request ID was already used for different payment details'; end if;
    return public.invoice_financial_position(i.id) || jsonb_build_object('success', true, 'replayed', true);
  end if;

  if p.entry_kind = 'correction_reversal'
     or exists (select 1 from public.invoice_payments where corrects_payment_id = p.id and entry_kind = 'correction_reversal') then
    raise exception 'Select the current replacement payment'; end if;
  select * into old_m from public.payment_methods where id = p.payment_method_id;
  if coalesce(old_m.is_wallet_credit, false) then
    raise exception 'A wallet credit payment consumed credit from the wallet; correct it from the invoice''s payment list or refund it'; end if;
  if public.invoice_payment_remaining(p.id) < p.amount then
    raise exception 'Refunds were issued against this payment; correct its amount as one payment instead of splitting it'; end if;

  -- Every part: a positive amount, the date the money was received, an
  -- active method that is not wallet credit (a split never consumes credit).
  for part in select value from jsonb_array_elements(p_parts) loop
    if coalesce((part.value->>'amount')::numeric, 0) <= 0 or nullif(part.value->>'date', '') is null then
      raise exception 'Each part of a split needs a positive amount and the date the money was received'; end if;
    select * into m from public.payment_methods
     where id = nullif(part.value->>'payment_method_id', '')::uuid and is_active and deleted_at is null;
    if not found then raise exception 'Choose an active payment method for each part'; end if;
    if coalesce(m.is_wallet_credit, false) then
      raise exception 'A wallet credit method cannot be set this way — refund and re-take the payment instead'; end if;
    v_total := v_total + round((part.value->>'amount')::numeric, 2);
  end loop;

  -- Bookkeeping entries only; no invoice_refunds row.
  insert into public.invoice_payments(id, invoice_id, payment_method_id, amount, entry_kind, corrects_payment_id,
    correction_reason, correction_request_id, effective_at, received_by)
  values (v_reverse, i.id, p.payment_method_id, p.amount, 'correction_reversal', p.id,
    p_reason, p_request_id, coalesce(p.effective_at, p.created_at), auth.uid());
  -- Each part under its own derived request id (one entry per id and kind).
  for part in select value, ordinality from jsonb_array_elements(p_parts) with ordinality loop
    v_id := gen_random_uuid();
    insert into public.invoice_payments(id, invoice_id, payment_method_id, amount, entry_kind, corrects_payment_id,
      correction_reason, correction_request_id, effective_at, received_by)
    values (v_id, i.id, (part.value->>'payment_method_id')::uuid, round((part.value->>'amount')::numeric, 2), 'correction_replacement', p.id,
      p_reason, md5(p_request_id::text || '/part/' || part.ordinality)::uuid,
      (part.value->>'date')::date::timestamp at time zone 'Asia/Singapore', auth.uid());
    v_ids := v_ids || v_id;
  end loop;

  n := public.invoice_net_received(i.id);
  update public.invoices
     set paid_amount = n,
         status = case when i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then i.status
                       when n >= public.invoice_charge_total(i.id) then 'paid'::public.invoice_status
                       when n > 0 then 'partially_paid'::public.invoice_status
                       else 'unpaid'::public.invoice_status end
   where id = i.id;
  perform public.reconcile_invoice_commissions(i.id, 'Payment split: ' || p_reason);
  perform public.write_audit_ex('invoice_payments', p.id, 'payment_split', to_jsonb(p),
    jsonb_build_object('reversal', v_reverse, 'replacements', to_jsonb(v_ids), 'parts', p_parts, 'total', v_total),
    'payments', p_reason, i.store_id);
  return public.invoice_financial_position(i.id) || jsonb_build_object('success', true, 'replacement_ids', to_jsonb(v_ids));
end $$;
revoke all on function public.split_invoice_payment(uuid, jsonb, text, uuid) from public, anon;
grant execute on function public.split_invoice_payment(uuid, jsonb, text, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 2. correct_invoice: a correction with parts. One part is 336's plain
--    correction; two or more are a split. Anchored on 336's text.
-- ---------------------------------------------------------------------
do $$
declare f text; v_old text; v_new text;
begin
  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('split_invoice_payment' in f) > 0 then return; end if;  -- already done
  v_old := '   perform public.correct_invoice_payment((c.value->>''payment_id'')::uuid,(c.value->>''amount'')::numeric,(c.value->>''date'')::date,
     nullif(c.value->>''payment_method_id'','''')::uuid,coalesce(p_reason,''Invoice edited''),
     md5(coalesce(p_request_id::text,i.id::text)||''/correct/''||(c.value->>''payment_id''))::uuid);';
  if position(v_old in f) = 0 then
    raise exception '337: correct_invoice does not carry 336''s payment correction call where 337 expects it'; end if;
  v_new := '   -- 337: parts. One is the plain correction; two or more are a split.
   if jsonb_typeof(c.value->''parts'') = ''array'' and jsonb_array_length(c.value->''parts'') > 1 then
     perform public.split_invoice_payment((c.value->>''payment_id'')::uuid,c.value->''parts'',coalesce(p_reason,''Invoice edited''),
       md5(coalesce(p_request_id::text,i.id::text)||''/split/''||(c.value->>''payment_id''))::uuid);
   else
     perform public.correct_invoice_payment((c.value->>''payment_id'')::uuid,
       coalesce(c.value->''parts''->0->>''amount'',c.value->>''amount'')::numeric,
       coalesce(c.value->''parts''->0->>''date'',c.value->>''date'')::date,
       nullif(coalesce(c.value->''parts''->0->>''payment_method_id'',c.value->>''payment_method_id''),'''')::uuid,coalesce(p_reason,''Invoice edited''),
       md5(coalesce(p_request_id::text,i.id::text)||''/correct/''||(c.value->>''payment_id''))::uuid);
   end if;';
  execute replace(f, v_old, v_new);
end $$;

-- ---------------------------------------------------------------------
-- 3. The preview describes a split and checks each part. Anchored on 336's
--    text in preview_invoice_correction.
-- ---------------------------------------------------------------------
do $$
declare f text; a1 text; a2 text;
begin
  select pg_get_functiondef('public.preview_invoice_correction(uuid,jsonb)'::regprocedure) into f;
  if position('337: a payment split' in f) > 0 then return; end if;  -- already done
  a1 := '      select * into p from public.invoice_payments where id = nullif(r.value->>''payment_id'','''')::uuid and invoice_id = i.id;';
  a2 := '      if v_amount <= 0 then';
  if position(a1 in f) = 0 or position(a2 in f) = 0 then
    raise exception '337: preview_invoice_correction does not carry 336''s payment loop where 337 expects it'; end if;
  -- A single part is the plain correction: read it as one.
  f := replace(f, a1,
'      -- 337: a payment split across methods. One part is a plain correction.
      if jsonb_typeof(r.value->''parts'') = ''array'' and jsonb_array_length(r.value->''parts'') = 1 then
        r.value := (r.value - ''parts'') || (r.value->''parts''->0);
      end if;
' || a1);
  -- Two or more parts: each is checked, the total decides the consequence.
  f := replace(f, a2,
'      if jsonb_typeof(r.value->''parts'') = ''array'' then
        if public.invoice_payment_remaining(p.id) < p.amount then
          v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''Refunds were issued against the %s payment of S$%s; correct its amount as one payment instead of splitting it.'', pm.name, to_char(p.amount,''FM999999990.00''))));
          continue; end if;
        v_amount := 0;
        for part in select value from jsonb_array_elements(r.value->''parts'') loop
          if coalesce((part.value->>''amount'')::numeric, 0) <= 0 or nullif(part.value->>''date'','''') is null then
            v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',format(''Each part of the %s payment needs a positive amount and the date the money was received.'', pm.name)));
            v_amount := -1; exit; end if;
          if exists (select 1 from public.payment_methods where id = nullif(part.value->>''payment_method_id'','''')::uuid and coalesce(is_wallet_credit,false)) then
            v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(''area'',''payments'',''detail'',''A part of a split cannot be wallet credit: a correction never consumes credit. Refund and re-take the payment instead.''));
            v_amount := -1; exit; end if;
          v_amount := v_amount + (part.value->>''amount'')::numeric;
        end loop;
        if v_amount < 0 then continue; end if;
        v_net := v_net - public.invoice_payment_remaining(p.id) + v_amount;
        v_effects := v_effects || jsonb_build_array(jsonb_build_object(''area'',''payments'',''change'',''split'',
          ''from'', format(''%s S$%s on %s'', pm.name, to_char(p.amount,''FM999999990.00''), to_char(coalesce(p.effective_at,p.created_at) at time zone ''Asia/Singapore'',''DD Mon YYYY'')),
          ''to'', (select string_agg(format(''%s S$%s on %s'', (select name from public.payment_methods where id = nullif(x->>''payment_method_id'','''')::uuid), to_char((x->>''amount'')::numeric,''FM999999990.00''), to_char((x->>''date'')::date,''DD Mon YYYY'')), '' + '') from jsonb_array_elements(r.value->''parts'') x),
          ''detail'', format(''The original receipt stays in history; a reversal and %s replacements totalling S$%s are recorded with this correction''''s reason. No customer refund is recorded.'', jsonb_array_length(r.value->''parts''), to_char(v_amount,''FM999999990.00''))));
        continue;
      end if;
' || a2);
  f := replace(f, 'p public.invoice_payments%rowtype; pm public.payment_methods%rowtype;',
                  'p public.invoice_payments%rowtype; pm public.payment_methods%rowtype; part record;');
  execute f;
end $$;

-- ---------------------------------------------------------------------
-- 4. Wording: an invoice that is already partially paid does not "go back"
--    to it. Guarded on its own so it lands even where 3 already ran.
-- ---------------------------------------------------------------------
do $$
declare f text; v_old text;
begin
  select pg_get_functiondef('public.preview_invoice_correction(uuid,jsonb)'::regprocedure) into f;
  if position('stays partially paid' in f) > 0 then return; end if;
  v_old := '''Payments will total S$%s of S$%s: the invoice goes back to partially paid with S$%s outstanding. Benefits already issued at payment stay issued.''';
  if position(v_old in f) = 0 then
    raise exception '337: the partially-paid wording is not where 337 expects it'; end if;
  execute replace(f, v_old,
    '(case when i.status = ''partially_paid'' then ''Payments will total S$%s of S$%s: the invoice stays partially paid with S$%s outstanding. Benefits already issued at payment stay issued.'' else ''Payments will total S$%s of S$%s: the invoice goes back to partially paid with S$%s outstanding. Benefits already issued at payment stay issued.'' end)');
end $$;

do $$
declare f text;
begin
  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('split_invoice_payment' in f) = 0 then raise exception '337: the split did not land in correct_invoice'; end if;
  select pg_get_functiondef('public.preview_invoice_correction(uuid,jsonb)'::regprocedure) into f;
  if position('337: a payment split' in f) = 0 or position('''split''' in f) = 0 then
    raise exception '337: the split did not land in preview_invoice_correction'; end if;
end $$;

notify pgrst, 'reload schema';
commit;
