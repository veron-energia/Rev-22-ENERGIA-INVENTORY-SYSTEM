-- =====================================================================
-- ENERGIA — CORRECTING THE PAYMENT METHOD AND THE AFFILIATE
--
-- Two things a correction could not touch:
--
--   1. THE PAYMENT METHOD. A sale rung up as Cash when it was actually Master
--      Card is a real mistake, and the invoice was previously stuck with it.
--      The lock on invoice_payments exists for good reason and STAYS: it blocks
--      the AMOUNT and the invoice link, which are the parts that must never
--      drift from what was collected. Only the METHOD is correctable, and only
--      through this Owner/Manager path.
--
--   2. THE AFFILIATE. Adding one where there was none, changing one, or
--      removing it. Affiliate commission is derived from invoices.affiliate_id,
--      and edit_paid_invoice() already reverses and re-earns commission, so the
--      change flows through to what is owed.
--
-- Every change is written into the revision snapshot, so what the invoice said
-- before is preserved.
--
-- Additive and idempotent. Run AFTER 114.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Allow the METHOD to be corrected, never the amount.
--
--    The guard is relaxed only for an Owner or Manager, and only for the
--    payment_method_id column. Amount, invoice link and deletion stay locked
--    for everyone, so a settled payment can never be made to say a different
--    figure than was taken.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text; v_old_cond text; v_new_cond text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'trg_lock_invoice_payments';
  if v_def is null then raise exception 'trg_lock_invoice_payments not found'; end if;
  if position('is_owner_or_manager' in v_def) > 0 then
    raise notice 'the payment lock already allows a method correction'; return;
  end if;

  v_old_cond := '  if old.locked_at is not null' || chr(10)
    || '     and (new.amount is distinct from old.amount' || chr(10)
    || '          or new.payment_method_id is distinct from old.payment_method_id' || chr(10)
    || '          or new.invoice_id is distinct from old.invoice_id) then';

  -- The amount and the invoice link stay locked for everyone. The method may be
  -- corrected by an Owner or Manager: it records HOW the money arrived, not how
  -- much, so correcting it cannot misstate what was collected.
  v_new_cond := '  if old.locked_at is not null' || chr(10)
    || '     and (new.amount is distinct from old.amount' || chr(10)
    || '          or new.invoice_id is distinct from old.invoice_id' || chr(10)
    || '          or (new.payment_method_id is distinct from old.payment_method_id' || chr(10)
    || '              and not public.is_owner_or_manager())) then';

  v_new := replace(v_def, v_old_cond, v_new_cond);
  if position('is_owner_or_manager' in v_new) = 0 then
    raise exception 'Could not relax the payment method lock';
  end if;
  execute v_new;
  raise notice 'the payment method may now be corrected by an Owner or Manager';
end $patch$;

-- ---------------------------------------------------------------------
-- 2. Correct the payment methods on a settled invoice.
--
--    p_payments = [{ "payment_id": "...", "payment_method_id": "..." }]
--    The amounts are untouched; only which method each row is attributed to.
-- ---------------------------------------------------------------------
create or replace function public.correct_invoice_payment_methods(
  p_invoice_id uuid, p_payments jsonb, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_p jsonb; v_pay record; v_new_method uuid; v_n integer := 0; v_before jsonb;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can correct a payment method'; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then
    return jsonb_build_object('changed', 0);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'payment_id', ip.id, 'method', pm.name, 'amount', ip.amount)), '[]'::jsonb)
    into v_before
    from public.invoice_payments ip
    left join public.payment_methods pm on pm.id = ip.payment_method_id
   where ip.invoice_id = p_invoice_id;

  for v_p in select * from jsonb_array_elements(p_payments)
  loop
    v_new_method := nullif(v_p->>'payment_method_id','')::uuid;
    if v_new_method is null then continue; end if;

    select * into v_pay from public.invoice_payments
     where id = (v_p->>'payment_id')::uuid and invoice_id = p_invoice_id;
    if not found then
      raise exception 'That payment does not belong to this invoice'; end if;
    if v_pay.payment_method_id = v_new_method then continue; end if;

    if not exists (select 1 from public.payment_methods
                    where id = v_new_method and coalesce(is_active, true)) then
      raise exception 'That payment method is not available'; end if;

    -- A wallet-credit method cannot be introduced here: it would imply credit
    -- was consumed, which this correction does not do.
    if exists (select 1 from public.payment_methods
                where id = v_new_method and coalesce(is_wallet_credit, false)) then
      raise exception 'A wallet credit method cannot be set this way — refund and re-take the payment instead';
    end if;
    -- The CURRENT method being a wallet one means credit was consumed; changing
    -- it away would leave that consumption unexplained.
    if exists (select 1 from public.payment_methods
                where id = v_pay.payment_method_id and coalesce(is_wallet_credit,false)) then
      raise exception 'A wallet credit payment cannot be changed this way — it consumed credit from the wallet';
    end if;

    update public.invoice_payments
       set payment_method_id = v_new_method
     where id = v_pay.id;
    v_n := v_n + 1;
  end loop;

  if v_n > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'payment_method_corrected', v_before,
      (select coalesce(jsonb_agg(jsonb_build_object(
                'payment_id', ip.id, 'method', pm.name, 'amount', ip.amount)), '[]'::jsonb)
         from public.invoice_payments ip
         left join public.payment_methods pm on pm.id = ip.payment_method_id
        where ip.invoice_id = p_invoice_id),
      'invoices', p_reason, (select store_id from public.invoices where id = p_invoice_id));
  end if;

  return jsonb_build_object('changed', v_n);
end $function$;

-- ---------------------------------------------------------------------
-- 3. The correction may also set, change or clear the affiliate.
--
--    Applied BEFORE commission is re-earned, so the new affiliate is the one
--    the commission is calculated for.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'edit_paid_invoice';
  if v_def is null then raise exception 'edit_paid_invoice not found'; end if;
  if position('p_affiliate_id' in v_def) > 0 then
    raise notice 'edit_paid_invoice already accepts an affiliate'; return;
  end if;

  -- p_set_affiliate distinguishes "leave it alone" from "clear it": a null
  -- affiliate id would otherwise be indistinguishable from not supplied.
  v_new := replace(v_def,
    'p_store_id uuid DEFAULT NULL::uuid)',
    'p_store_id uuid DEFAULT NULL::uuid, p_affiliate_id uuid DEFAULT NULL::uuid, p_set_affiliate boolean DEFAULT false)');

  v_new := replace(v_new,
    '  update public.invoices set status = ''unpaid'' where id = p_invoice_id;',
    '  -- The affiliate is set BEFORE the lines are rebuilt and commission is' || chr(10)
    || '  -- re-earned, so the new affiliate is the one commission is calculated for.' || chr(10)
    || '  if p_set_affiliate then' || chr(10)
    || '    if p_affiliate_id is not null' || chr(10)
    || '       and not exists (select 1 from public.customer_affiliates ca' || chr(10)
    || '                        where ca.id = p_affiliate_id and ca.deleted_at is null) then' || chr(10)
    || '      raise exception ''That affiliate does not exist'';' || chr(10)
    || '    end if;' || chr(10)
    || '    update public.invoices set affiliate_id = p_affiliate_id where id = p_invoice_id;' || chr(10)
    || '    select * into v_inv from public.invoices where id = p_invoice_id;' || chr(10)
    || '  end if;' || chr(10)
    || '  update public.invoices set status = ''unpaid'' where id = p_invoice_id;');

  if position('That affiliate does not exist' in v_new) = 0 then
    raise exception 'Could not add the affiliate to edit_paid_invoice';
  end if;
  execute v_new;
  drop function if exists public.edit_paid_invoice(uuid, jsonb, text, numeric, uuid[], uuid);
  raise notice 'edit_paid_invoice can now set, change or clear the affiliate';
end $patch$;

notify pgrst, 'reload schema';
