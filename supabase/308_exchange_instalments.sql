begin;
-- =====================================================================
-- AN EXCHANGE'S ADDITIONAL PAYMENT CAN BE PAID OVER TIME
--
-- All three exchange creators demanded that the payments handed in equal the
-- whole top-up:
--
--     if round(v_pay_sum,2) <> v_topup then
--       raise exception 'Top-up payment (%.2f) must equal the amount due (%.2f)'
--
-- and create_exchange_invoice then wrote the replacement invoice as 'paid'
-- with paid_amount = the top-up, regardless of what had actually been
-- received. So an exchange could only ever be settled in full, in cash, on the
-- spot.
--
-- WHICH PAYMENT PATH (§3), and why
--
-- The replacement invoice, not a second model on the exchange. Three reasons:
--
--   * the receipts are ALREADY invoice_payments rows — create_exchange_invoice
--     projects product_exchange_payments into them — so the invoice is already
--     the authoritative record of money received;
--   * commission is computed on the replacement invoice, so the money and the
--     commission stay in one place;
--   * invoice_payment_arrangements, and everything 307 hardened around it,
--     applies unchanged.
--
-- product_exchange_payments keeps its role: what was taken at the counter when
-- the exchange was made. It is projected into the invoice exactly as before,
-- so there is still ONE authoritative receipt per payment, not two.
--
-- What changes here:
--   1. the three creators accept payments up to, not exactly, the top-up;
--   2. the replacement invoice's status and paid_amount follow the money that
--      actually arrived;
--   3. create_exchange_with_details takes arrangements and attaches them to the
--      replacement invoice, in the same transaction.
--
-- Operational completion stays separate from payment completion: the exchange
-- is 'completed' — stock moved, benefits settled — while its invoice may be
-- unpaid or partially paid. Recording a later instalment touches the invoice
-- only and re-runs no stock or benefit work.
--
-- Requires 305, 306 and 307. Idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Payments may fall short of the top-up; the balance is owed.
-- ---------------------------------------------------------------------
do $do$
declare r record; f text; v_old text; v_new text; v_n int:=0;
begin
 v_old:=
'      if round(v_pay_sum, 2) <> v_topup then'||E'\n'||
'        raise exception ''Top-up payment (%.2f) must equal the amount due (%.2f)'', v_pay_sum, v_topup;'||E'\n'||
'      end if;';
 v_new:=
'      -- Money handed over now may be less than the whole top-up: the rest is'||E'\n'||
'      -- owed on the replacement invoice, under an instalment arrangement or'||E'\n'||
'      -- simply as an outstanding balance. More than the top-up is still wrong.'||E'\n'||
'      if round(v_pay_sum, 2) > v_topup then'||E'\n'||
'        raise exception ''Top-up payment (%.2f) is more than the amount due (%.2f)'', v_pay_sum, v_topup;'||E'\n'||
'      end if;'||E'\n'||
'      if round(v_pay_sum, 2) < 0 then'||E'\n'||
'        raise exception ''Top-up payment cannot be negative'';'||E'\n'||
'      end if;';
 for r in select p.oid, p.oid::regprocedure::text sig, pg_get_functiondef(p.oid) def
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prokind='f'
             and p.proname in ('create_product_exchange','create_bundle_exchange','create_bundle_component_exchange')
 loop
  f:=r.def;
  if position('is more than the amount due' in f)>0 then continue; end if;
  -- Two of the three write the check on one line; normalise both shapes.
  if position(v_old in f)>0 then
   f:=replace(f,v_old,v_new);
  elsif position('if round(v_pay_sum,2) <> v_topup then raise exception ''Top-up payment (%.2f) must equal the amount due (%.2f)'', v_pay_sum, v_topup; end if;' in f)>0 then
   f:=replace(f,
     'if round(v_pay_sum,2) <> v_topup then raise exception ''Top-up payment (%.2f) must equal the amount due (%.2f)'', v_pay_sum, v_topup; end if;',
     'if round(v_pay_sum,2) > v_topup then raise exception ''Top-up payment (%.2f) is more than the amount due (%.2f)'', v_pay_sum, v_topup; end if;');
  else
   raise exception 'The top-up check in % is not in the expected shape — align it by hand', r.sig;
  end if;
  execute f; v_n:=v_n+1;
  raise notice 'accepts a part payment of the top-up: %', r.sig;
 end loop;
 if v_n=0 then raise notice 'the exchange creators already accept part payments'; end if;
end $do$;

-- ---------------------------------------------------------------------
-- 2. The replacement invoice says what was actually received.
-- ---------------------------------------------------------------------
do $do$
declare f text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.create_exchange_invoice(uuid)'::regprocedure) into f;
 if position('v_received' in f)>0 then
  raise notice 'the replacement invoice already reflects actual receipts'; return; end if;

 f:=replace(f,
   '  v_alloc numeric := 0; v_line_disc numeric; v_running numeric := 0;',
   '  v_alloc numeric := 0; v_line_disc numeric; v_running numeric := 0;'||E'\n'||
   '  v_received numeric := 0;   -- what was actually handed over at the counter');

 -- Compute it before the invoice row is written.
 v_old:='  insert into public.invoices'||E'\n'||
        '    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,';
 v_new:='  -- Money that actually arrived. An unpaid balance is owed, not assumed.'||E'\n'||
        '  select coalesce(sum(amount),0) into v_received'||E'\n'||
        '    from public.product_exchange_payments where exchange_id = p_exchange_id;'||E'\n'||E'\n'||
        '  insert into public.invoices'||E'\n'||
        '    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,';
 if position(v_old in f)=0 then
  raise exception 'The invoice insert in create_exchange_invoice is not in the expected shape'; end if;
 f:=replace(f,v_old,v_new);

 -- Status and paid_amount follow the money.
 v_old:='     v_ex.exchange_affiliate_id, v_ex.created_by, ''paid'','||E'\n'||
        '     v_repl_total, v_deduction, null, coalesce(v_ex.topup_amount,0), coalesce(v_ex.topup_amount,0),';
 v_new:='     v_ex.exchange_affiliate_id, v_ex.created_by,'||E'\n'||
        '     case when coalesce(v_ex.topup_amount,0) <= 0 then ''paid''::invoice_status'||E'\n'||
        '          when v_received >= coalesce(v_ex.topup_amount,0) then ''paid''::invoice_status'||E'\n'||
        '          when v_received > 0 then ''partially_paid''::invoice_status'||E'\n'||
        '          else ''unpaid''::invoice_status end,'||E'\n'||
        '     v_repl_total, v_deduction, null, coalesce(v_ex.topup_amount,0), v_received,';
 if position(v_old in f)=0 then
  raise exception 'The invoice status line in create_exchange_invoice is not in the expected shape'; end if;
 f:=replace(f,v_old,v_new);

 -- paid_at only once it is actually paid.
 v_old:='     v_ex.created_at, now(), v_ex.created_at)';
 v_new:='     case when coalesce(v_ex.topup_amount,0) <= 0 or v_received >= coalesce(v_ex.topup_amount,0)'||E'\n'||
        '          then v_ex.created_at end, now(), v_ex.created_at)';
 if position(v_old in f)=0 then
  raise exception 'The paid_at line in create_exchange_invoice is not in the expected shape'; end if;
 f:=replace(f,v_old,v_new);

 execute f;
 raise notice 'the replacement invoice now reports what was actually received';
end $do$;

-- ---------------------------------------------------------------------
-- 3. Arrangements, attached to the replacement invoice in one transaction.
--
-- The invoice is created by a DEFERRED constraint trigger, so it does not
-- exist yet when the wrapper returns from the creator. Forcing that trigger to
-- run now is what lets the arrangement be attached before commit, instead of
-- leaving a window where an exchange exists with terms nobody recorded.
-- ---------------------------------------------------------------------
create or replace function public.create_exchange_with_details(p_kind text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_res jsonb; v_id uuid; v_inv uuid; v_arr jsonb; v_settle jsonb;
begin
 if p_kind not in ('product','bundle','bundle_component') then
  raise exception 'Unknown exchange kind %',p_kind; end if;

 if p_kind='product' then
  v_res:=public.create_product_exchange(
    (p_payload->>'original_invoice_id')::uuid,(p_payload->>'processing_store_id')::uuid,
    coalesce(p_payload->'returned','[]'::jsonb),coalesce(p_payload->'replacement','[]'::jsonb),
    coalesce(p_payload->'payments','[]'::jsonb),p_payload->>'reason',p_payload->>'notes',
    coalesce((p_payload->>'foc')::boolean,false),
    nullif(p_payload->>'foc_reason_id','')::uuid,p_payload->>'foc_reason');
 elsif p_kind='bundle' then
  v_res:=public.create_bundle_exchange(
    (p_payload->>'original_invoice_id')::uuid,(p_payload->>'processing_store_id')::uuid,
    (p_payload->>'original_invoice_item_id')::uuid,(p_payload->>'new_promotion_id')::uuid,
    coalesce(p_payload->'payments','[]'::jsonb),p_payload->>'reason',p_payload->>'notes');
 else
  v_res:=public.create_bundle_component_exchange(
    (p_payload->>'original_invoice_id')::uuid,(p_payload->>'processing_store_id')::uuid,
    (p_payload->>'original_invoice_item_id')::uuid,(p_payload->>'component_product_id')::uuid,
    coalesce((p_payload->>'component_qty')::int,1),
    coalesce(p_payload->'replacement','[]'::jsonb),
    coalesce(p_payload->'payments','[]'::jsonb),p_payload->>'reason',p_payload->>'notes');
 end if;

 v_id:=coalesce(nullif(v_res->>'exchange_id','')::uuid,nullif(v_res->>'id','')::uuid);
 if v_id is null then
  raise exception 'The exchange was created but its id could not be read back'; end if;

 v_res:=v_res || public.set_exchange_details(v_id,
   coalesce(p_payload->'served_by','[]'::jsonb),
   coalesce(p_payload->'affiliate','{"mode":"inherit"}'::jsonb),
   nullif(p_payload->>'raised_by','')::uuid,
   nullif(p_payload->>'exchange_date','')::date,
   p_payload->>'notes');

 v_arr:=coalesce(p_payload->'arrangements','[]'::jsonb);
 if jsonb_array_length(v_arr)>0 then
  -- Bring the replacement invoice into existence now so its arrangement can be
  -- written in this same transaction.
  set constraints public.exchange_creates_invoice immediate;
  select id into v_inv from public.invoices where exchange_id=v_id and is_exchange;
  if v_inv is null then
   raise exception 'This exchange has no replacement invoice, so an instalment cannot be attached to it'; end if;
  v_settle:=public.record_invoice_settlement(v_inv,jsonb_build_object('arrangements',v_arr),
    coalesce(nullif(p_payload->>'request_id','')::uuid,v_id));
  v_res:=v_res||jsonb_build_object('exchange_invoice_id',v_inv,'settlement',v_settle);
 end if;

 return v_res;
end $$;
grant execute on function public.create_exchange_with_details(text,jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 4. What an exchange is owed, in the words §7 asks for.
-- ---------------------------------------------------------------------
create or replace function public.exchange_payment_position(p_exchange_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare e public.product_exchanges%rowtype; v_inv uuid; v_recv numeric; v_bal jsonb;
begin
 select * into e from public.product_exchanges where id=p_exchange_id;
 if not found then raise exception 'Exchange not found'; end if;
 if not public.user_has_store_access(e.processing_store_id) then
  raise exception 'Exchange not accessible' using errcode='42501'; end if;
 select id into v_inv from public.invoices where exchange_id=e.id and is_exchange;
 v_recv:=case when v_inv is not null then public.invoice_net_received(v_inv)
              else coalesce((select sum(amount) from public.product_exchange_payments where exchange_id=e.id),0) end;
 v_bal:=case when v_inv is not null then public.invoice_arrangement_balances(v_inv) end;
 return jsonb_build_object(
   'exchange_id',e.id,'exchange_no',e.exchange_no,
   'exchange_invoice_id',v_inv,
   -- Named for what they are. "Top-up paid" was a label on a figure that was
   -- only ever the CHARGE, whether or not a penny had been received.
   'additional_charge',coalesce(e.topup_amount,0),
   'received',v_recv,
   'outstanding',greatest(coalesce(e.topup_amount,0)-v_recv,0),
   'instalment_covered',coalesce((v_bal->>'instalment_covered')::numeric,0),
   'instalment_remaining',coalesce((v_bal->>'instalment_remaining')::numeric,0),
   'arrangements',coalesce(v_bal->'arrangements','[]'::jsonb),
   'nonrefundable',coalesce(e.nonrefundable_amount,0),
   'foc_waived',coalesce(e.foc_amount,0));
end $$;
grant execute on function public.exchange_payment_position(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Commission waits for the money, exactly as it already does elsewhere.
--
-- invoice_record_payments_internal earns commission ONLY in its fully-paid
-- branch; a partially paid invoice earns nothing. create_exchange_invoice
-- earned unconditionally, which was harmless while every exchange was settled
-- in full on the spot and is wrong the moment part of the top-up is owed: it
-- would pay commission on a promise.
--
-- Gating it on actual receipt also means a LATER instalment needs no new
-- commission machinery. The receipt goes through record_invoice_payment, which
-- earns on completion through the path that was already correct — which is the
-- strongest argument for routing exchange money through the invoice at all.
-- ---------------------------------------------------------------------
do $do$
declare f text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.create_exchange_invoice(uuid)'::regprocedure) into f;
 if position('commission waits for the money' in f)>0 then
  raise notice 'exchange commission already waits for the money'; return; end if;

 v_old:='  perform public.earn_invoice_commission(v_inv_id);'||chr(10)||
        '  perform public.earn_staff_commission(v_inv_id);';
 v_new:='  -- commission waits for the money: nothing is earned on an additional'||chr(10)||
        '  -- charge that has not been received. A later receipt earns it through'||chr(10)||
        '  -- record_invoice_payment, the same way every other invoice does.'||chr(10)||
        '  if coalesce(v_ex.topup_amount,0) <= 0 or v_received >= coalesce(v_ex.topup_amount,0) then'||chr(10)||
        '    perform public.earn_invoice_commission(v_inv_id);'||chr(10)||
        '    perform public.earn_staff_commission(v_inv_id);'||chr(10)||
        '  end if;';
 if position(v_old in f)=0 then
  raise exception 'The commission calls in create_exchange_invoice are not in the expected shape'; end if;
 execute replace(f,v_old,v_new);
 raise notice 'exchange commission now waits until the additional charge is received';
end $do$;

notify pgrst,'reload schema';
commit;
