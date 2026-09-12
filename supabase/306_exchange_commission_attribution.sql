begin;
-- =====================================================================
-- THE EXCHANGE'S COMMISSION FOLLOWS WHO SERVED IT, NOT WHO TYPED IT
--
-- What was already right, and is not touched: the commission BASIS. Both
-- engines see the top-up only — affiliate on the allocated top-up per line,
-- staff on invoices.total_amount, which for a replacement invoice IS the
-- top-up. So an exchange where S$100 of value is carried forward and the
-- customer pays S$20 more can only ever earn commission on the S$20, and an
-- equal-value exchange earns none. That rule is left exactly as it is.
--
-- Two things were wrong with WHO it lands on:
--
-- 1. Service staff came from v_ex.created_by — whoever created the exchange
--    record. That is the document's issuer. With 305 recording who actually
--    served the exchange, crediting the issuer means changing who types the
--    document changes who is paid, which is precisely what must not happen.
--
-- 2. The affiliate was copied from product_exchanges.affiliate_id, which
--    references the LEGACY `affiliates` table, into invoices.affiliate_id,
--    which references customer_affiliates. The two can never hold the same
--    value, so either the insert failed or — because the column was in
--    practice always null — the exchange's affiliate silently never reached
--    the replacement invoice and earned nothing. 305 added
--    exchange_affiliate_id in the invoice's own model; this uses it.
--
-- Exchanges recorded before 305 have no service staff of their own, so they
-- keep falling back to created_by: their history is read as it was written,
-- not reinterpreted.
--
-- Requires 305. Idempotent.
-- =====================================================================
do $do$
declare f text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.create_exchange_invoice(uuid)'::regprocedure) into f;
 if position('product_exchange_service_staff' in f)>0 then
  raise notice 'the replacement invoice already follows the exchange''s own attribution'; return; end if;

 -- ---- 1. the affiliate the exchange actually recorded --------------------
 v_old:='    (v_no, v_ex.processing_store_id, v_ex.customer_id, v_ex.affiliate_id, v_ex.created_by, ''paid'',';
 v_new:='    (v_no, v_ex.processing_store_id, v_ex.customer_id,'||E'\n'||
        '     -- The exchange''s own affiliate, in the invoice''s model. The older'||E'\n'||
        '     -- affiliate_id column references the legacy affiliates table and'||E'\n'||
        '     -- cannot satisfy this column''s foreign key.'||E'\n'||
        '     v_ex.exchange_affiliate_id, v_ex.created_by, ''paid'',';
 if position(v_old in f)=0 then
  raise exception 'The invoice insert in create_exchange_invoice does not match what 306 expects — align it by hand'; end if;
 f:=replace(f,v_old,v_new);

 -- ---- 2. the people who served it ----------------------------------------
 v_old:=
'  -- The staff member who processed the exchange is its service staff, so'||E'\n'||
'  -- staff commission (based on total_amount = top-up) lands with them.'||E'\n'||
'  select role into v_creator_role from public.profiles where id = v_ex.created_by;'||E'\n'||
'  if v_creator_role in (''owner'',''manager'',''staff'') then'||E'\n'||
'    insert into public.invoice_service_staff (invoice_id, staff_id)'||E'\n'||
'    values (v_inv_id, v_ex.created_by) on conflict (invoice_id, staff_id) do nothing;'||E'\n'||
'  end if;';
 v_new:=
'  -- Whoever actually SERVED the exchange is its service staff, so the staff'||E'\n'||
'  -- commission on the top-up is split between them by the existing rules.'||E'\n'||
'  -- The person who raised the document earns nothing for having typed it.'||E'\n'||
'  insert into public.invoice_service_staff (invoice_id, staff_id)'||E'\n'||
'  select v_inv_id, s.staff_id'||E'\n'||
'    from public.product_exchange_service_staff s'||E'\n'||
'    join public.profiles p on p.id = s.staff_id'||E'\n'||
'   where s.exchange_id = v_ex.id'||E'\n'||
'     and p.role in (''owner'',''manager'',''staff'')'||E'\n'||
'  on conflict (invoice_id, staff_id) do nothing;'||E'\n'||
'  -- An exchange recorded before service staff existed keeps the attribution'||E'\n'||
'  -- it was written with, rather than being reinterpreted now.'||E'\n'||
'  if not exists (select 1 from public.product_exchange_service_staff where exchange_id = v_ex.id) then'||E'\n'||
'    select role into v_creator_role from public.profiles where id = v_ex.created_by;'||E'\n'||
'    if v_creator_role in (''owner'',''manager'',''staff'') then'||E'\n'||
'      insert into public.invoice_service_staff (invoice_id, staff_id)'||E'\n'||
'      values (v_inv_id, v_ex.created_by) on conflict (invoice_id, staff_id) do nothing;'||E'\n'||
'    end if;'||E'\n'||
'  end if;';
 if position(v_old in f)=0 then
  raise exception 'The service-staff block of create_exchange_invoice does not match what 306 expects — align it by hand'; end if;
 f:=replace(f,v_old,v_new);

 execute f;
 raise notice 'the replacement invoice now credits the staff and affiliate the exchange recorded';
end $do$;

notify pgrst,'reload schema';
commit;
