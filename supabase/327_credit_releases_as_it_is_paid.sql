begin;
-- =====================================================================
-- A CREDIT PACKAGE RELEASES ITS PAID CREDIT AS IT IS PAID FOR
--
-- Until now a credit package gave nothing until the invoice was settled in
-- full: trg_create_therapy_on_paid fired once, on the move to 'paid', and
-- issue_credit_lines_for_invoice granted the paid credit, the bonus credit,
-- the vouchers, the sale record and any reward entitlement together. A customer
-- paying S$1,000 toward a S$5,000 package held nothing at all.
--
-- Paid credit is money the customer has handed over. It now becomes usable as
-- it arrives. Everything else is a reward for completing the purchase and still
-- waits for the last payment:
--
--   paid credit        -> released as it is paid for      (this migration)
--   bonus credit       -> full payment, unchanged
--   vouchers           -> full payment, unchanged
--   sale record        -> full payment, unchanged
--   commission         -> full payment, unchanged
--   reward entitlement -> full payment, unchanged
--
-- Leaving the sale record where it is matters: assert_invoice_credit_source_
-- evidence reads a sale with no bonus lot as unresolved provenance and refuses
-- to refund, reassign or allocate. Creating it early would trip that guard on
-- every part-paid package.
--
-- Scope. Ordinary single-customer packages only. A package split across several
-- customers (credit_split_allocation_id, or a legacy 141 invoice_credit_splits
-- row) keeps its full-payment issuance, because dividing one partial payment
-- between several people is a separate question about who is paid off first.
-- Premium bundles are untouched.
--
-- Additive where it can be, and every function is replaceable. Idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- The external money attributable to one line: its share of the invoice
-- after the manual discount. Both existing issuers compute this inline and
-- must agree with it, so it is named once here.
-- ---------------------------------------------------------------------
create or replace function public.invoice_item_external_value(p_invoice_item_id uuid)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_it public.invoice_items%rowtype; v_inv public.invoices%rowtype; v_ext numeric;
begin
  select * into v_it from public.invoice_items where id = p_invoice_item_id;
  if not found then return 0; end if;
  select * into v_inv from public.invoices where id = v_it.invoice_id;
  v_ext := round(coalesce(v_it.line_total,0)
    - case when coalesce(v_inv.subtotal,0) > 0
           then coalesce(v_inv.discount_total,0) * (coalesce(v_it.line_total,0) / v_inv.subtotal)
           else 0 end, 2);
  return greatest(v_ext, 0);
end $$;

-- ---------------------------------------------------------------------
-- How much of what has been received so far belongs to this credit package
-- line. Credit package lines are settled first, so a payment toward a package
-- releases credit rather than quietly paying off the products beside it, and
-- in id order so two packages on one invoice fill predictably.
-- ---------------------------------------------------------------------
create or replace function public.credit_package_money_toward_line(p_invoice_item_id uuid)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_it public.invoice_items%rowtype; v_received numeric; v_ahead numeric;
begin
  select * into v_it from public.invoice_items where id = p_invoice_item_id;
  if not found or v_it.line_kind <> 'credit_package' then return 0; end if;

  select greatest(coalesce(paid_amount,0),0) into v_received
    from public.invoices where id = v_it.invoice_id;

  select coalesce(sum(public.invoice_item_external_value(x.id)), 0) into v_ahead
    from public.invoice_items x
   where x.invoice_id = v_it.invoice_id
     and x.line_kind = 'credit_package'
     and x.id < v_it.id;

  return least(greatest(v_received - v_ahead, 0),
               public.invoice_item_external_value(p_invoice_item_id));
end $$;

-- ---------------------------------------------------------------------
-- Paid credit already released against this line. original_amount, not
-- remaining: credit the customer has since spent has still been released, and
-- counting what is left would release it a second time.
-- ---------------------------------------------------------------------
create or replace function public.credit_package_released_paid_credit(p_invoice_item_id uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.original_amount), 0)
    from public.customer_credit_lots l
   where l.source_type = 'credit_package_progress'
     and l.source_record_id = p_invoice_item_id
     and l.status <> 'reversed';
$$;

-- ---------------------------------------------------------------------
-- Release whatever the money received now justifies, and no more.
-- Safe to call repeatedly: it grants the difference, so a replayed payment
-- or a second call releases nothing.
-- ---------------------------------------------------------------------
create or replace function public.release_credit_package_paid_credit(p_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_it record; pk public.credit_packages%rowtype;
  v_entitled numeric; v_target numeric; v_already numeric; v_delta numeric;
  v_restrict jsonb; v_vouchers uuid[]; v_lot uuid; v_out jsonb := '[]'::jsonb;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('skipped', true, 'reason', 'no invoice'); end if;
  -- A cancelled or refunded invoice releases nothing further.
  if v_inv.status in ('cancelled','refunded') then
    return jsonb_build_object('skipped', true, 'reason', 'invoice ' || v_inv.status); end if;
  if v_inv.customer_id is null then
    return jsonb_build_object('skipped', true, 'reason', 'no customer'); end if;

  for v_it in
    select * from public.invoice_items
     where invoice_id = p_invoice_id
       and line_kind = 'credit_package'
       -- Once the full issuance has run, the line is settled and this must not
       -- add to it. Both branches of trg_create_therapy_on_paid fire on the
       -- final payment, and without this the last payment would be released
       -- twice: once by the issuer and again here.
       and credit_issued_at is null
       -- Split packages keep full-payment issuance; see the header.
       and credit_split_allocation_id is null
       and not exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = invoice_items.id)
     order by id
     for update
  loop
    select * into pk from public.credit_packages where id = v_it.credit_package_id;
    if not found then continue; end if;

    -- What the line grants in total, and what the money so far has earned.
    v_entitled := coalesce(v_it.credit_paid_snapshot, pk.paid_credit_amount, 0);
    if v_entitled <= 0 then continue; end if;
    v_target  := least(public.credit_package_money_toward_line(v_it.id), v_entitled);
    v_already := public.credit_package_released_paid_credit(v_it.id);
    v_delta   := round(v_target - v_already, 2);
    if v_delta <= 0 then continue; end if;

    -- The same restrictions the full issuer snapshots, so credit released early
    -- can buy exactly what credit released at the end could.
    select coalesce(array_agg(voucher_id), '{}') into v_vouchers
      from public.credit_package_vouchers where package_id = pk.id;
    v_restrict := jsonb_build_object('allowed_purposes', public.credit_package_purposes(pk.id),
                                     'source', 'credit_package');
    if array_length(v_vouchers, 1) is not null and not pk.allow_voucher then
      v_restrict := v_restrict || jsonb_build_object(
        'allowed_voucher_ids', (select jsonb_agg(v::text) from unnest(v_vouchers) v));
    end if;

    -- source_record_id is the invoice LINE, which is how invoice_credit_lot_ids
    -- already finds lots granted against an invoice, so refunds, reassignment
    -- and the benefit review see these without being taught anything new.
    v_lot := public.grant_customer_credit(
      v_inv.customer_id, 'paid', v_delta, 'credit_package_progress', v_it.id, v_inv.store_id,
      public.sg_today(), null,
      'Credit package (paid so far): ' || pk.name, null, null, auth.uid(), v_restrict);

    v_out := v_out || jsonb_build_object(
      'invoice_item_id', v_it.id, 'lot_id', v_lot, 'released', v_delta,
      'released_total', v_already + v_delta, 'entitled', v_entitled);
  end loop;

  return jsonb_build_object('released', v_out);
end $$;

revoke all on function public.release_credit_package_paid_credit(uuid) from public;
grant execute on function public.release_credit_package_paid_credit(uuid) to authenticated;

commit;

begin;
-- ---------------------------------------------------------------------
-- The full issuance now grants only what has NOT already been released, so a
-- package paid in instalments ends up with exactly its paid-credit amount and
-- not a penny more. Patched by anchored replacement because production carries
-- the installed definition, not this file's idea of it.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.issue_credit_package(uuid,uuid,uuid,numeric,uuid)'::regprocedure) into f;
  if position('credit_package_released_paid_credit' in f) = 0 then
    f := replace(f,
'  v_lot := public.grant_customer_credit(
    p_customer_id, ''paid'', pk.paid_credit_amount, ''credit_package'', p_package_id, p_store_id,
    public.sg_today(), null, ''Credit package: '' || pk.name, null, null, auth.uid(), v_restrict);',
'  -- 327: whatever this invoice already released as it was paid down is credit
  -- the customer is holding now. Grant the remainder only.
  declare v_released numeric := 0; v_remaining numeric;
  begin
    if p_invoice_id is not null then
      select coalesce(sum(public.credit_package_released_paid_credit(it.id)), 0) into v_released
        from public.invoice_items it
       where it.invoice_id = p_invoice_id
         and it.line_kind = ''credit_package''
         and it.credit_package_id = p_package_id
         and it.credit_split_allocation_id is null;
    end if;
    v_remaining := round(coalesce(pk.paid_credit_amount,0) - v_released, 2);
    if v_remaining > 0 then
      v_lot := public.grant_customer_credit(
        p_customer_id, ''paid'', v_remaining, ''credit_package'', p_package_id, p_store_id,
        public.sg_today(), null, ''Credit package: '' || pk.name, null, null, auth.uid(), v_restrict);
    end if;
  end;');
    if position('credit_package_released_paid_credit' in f) = 0 then
      raise exception 'issue_credit_package does not match what 327 expects — align it by hand'; end if;
    execute f;
  end if;
end $do$;

-- ---------------------------------------------------------------------
-- Release on every payment, not only on the last one.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.trg_create_therapy_on_paid()'::regprocedure) into f;
  if position('release_credit_package_paid_credit' in f) = 0 then
    f := replace(f,
'    v_day := (coalesce(new.paid_at, now()) at time zone ''Asia/Singapore'')::date;',
'    v_day := (coalesce(new.paid_at, now()) at time zone ''Asia/Singapore'')::date;

    -- 327: paid credit follows the money. Bonus credit, vouchers, the sale
    -- record and commission still wait for the invoice to be settled in full.
    if exists (select 1 from public.invoice_items
                where invoice_id = new.id and line_kind = ''credit_package'') then
      perform public.release_credit_package_paid_credit(new.id);
    end if;');
    if position('release_credit_package_paid_credit' in f) = 0 then
      raise exception 'trg_create_therapy_on_paid does not match what 327 expects — align it by hand'; end if;
    execute f;
  end if;
end $do$;

commit;

begin;
-- ---------------------------------------------------------------------
-- CLOSING AN INVOICE THAT ALREADY RELEASED CREDIT
--
-- Before 327 this could not happen: nothing was issued until the invoice was
-- settled, so a cancel or refund never met credit the customer was already
-- holding. Now it can, and the cancel path would not have seen it — it walks
-- invoice_benefit_values, and a progressively released lot has no row there
-- because the benefits are only captured at full issuance. The customer would
-- have kept the credit for a cancelled purchase.
--
-- What is left is taken back. What has already been spent is written off: the
-- goods are gone, reverse_credit_lot refuses a spent lot outright, and leaving
-- the cancel to fail would trap staff with no way through. The amount is named
-- in an audit entry so the loss is visible rather than silent.
-- ---------------------------------------------------------------------
create or replace function public.writeoff_released_credit_on_close(
  p_invoice_id uuid, p_reason text, p_event text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_lot record; v_reclaimed numeric := 0; v_written_off numeric := 0; v_store uuid;
begin
  select store_id into v_store from public.invoices where id = p_invoice_id;

  for v_lot in
    select cl.* from public.customer_credit_lots cl
     where cl.source_type = 'credit_package_progress'
       and cl.source_record_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
       and cl.status <> 'reversed'
     order by cl.id
     for update
  loop
    if v_lot.remaining_amount > 0 then
      insert into public.customer_credit_ledger(
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, reason, created_by, approved_by)
      values (v_lot.wallet_id, v_lot.customer_id, 'adjust_decrease', v_lot.category,
        v_lot.remaining_amount, v_lot.id, 'invoice_' || p_event || '_released_credit',
        p_invoice_id, v_lot.store_id, p_reason, auth.uid(), auth.uid());
      v_reclaimed := v_reclaimed + v_lot.remaining_amount;
    end if;
    -- Spent before the invoice closed. Nothing to take back.
    v_written_off := v_written_off + (v_lot.original_amount - v_lot.remaining_amount);
    update public.customer_credit_lots
       set remaining_amount = 0, status = 'reversed', is_locked = true, updated_at = now()
     where id = v_lot.id;
  end loop;

  if v_reclaimed > 0 or v_written_off > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'released_credit_' || p_event, null,
      jsonb_build_object('reclaimed', v_reclaimed, 'written_off', v_written_off,
                         'reason', p_reason),
      'credit', p_reason, v_store);
  end if;
  return jsonb_build_object('reclaimed', v_reclaimed, 'written_off', v_written_off);
end $$;

comment on function public.writeoff_released_credit_on_close(uuid, text, text) is
 'Close out paid credit released before an invoice was settled: take back what is unspent, write off what is gone, and say so in the audit trail.';

-- Cancel closes the whole invoice, so everything released is settled here.
do $do$
declare f text;
begin
  select pg_get_functiondef('public.cancel_invoice_recorded'::regproc) into f;
  if position('writeoff_released_credit_on_close' in f) = 0 then
    f := replace(f,
' for v_lot in select cl.* from public.customer_credit_lots cl join public.invoice_benefit_values b on b.lot_id=cl.id',
' -- 327: paid credit released before settlement has no invoice_benefit_values
 -- row, so it would survive this loop untouched and the customer would keep
 -- the credit for a cancelled purchase.
 perform public.writeoff_released_credit_on_close(i.id, p_reason, ''cancel'');
 for v_lot in select cl.* from public.customer_credit_lots cl join public.invoice_benefit_values b on b.lot_id=cl.id');
    if position('writeoff_released_credit_on_close' in f) = 0 then
      raise exception 'cancel_invoice_recorded does not match what 327 expects — align it by hand'; end if;
    execute f;
  end if;
end $do$;

-- A refund only settles released credit once nothing is left owing on the
-- invoice. A partial refund leaves the purchase standing, and the credit the
-- customer paid for with it stands too.
do $do$
declare f text;
begin
  select pg_get_functiondef('public.refund_invoice_recorded'::regproc) into f;
  if position('writeoff_released_credit_on_close' in f) = 0 then
    f := replace(f,
' perform public.reconcile_invoice_commissions(i.id,''Refund: ''||p_reason);',
' -- 327: only when the refund has closed the invoice out entirely.
 if (select status from public.invoices where id=i.id) in (''refunded'',''cancelled'') then
   perform public.writeoff_released_credit_on_close(i.id, p_reason, ''refund'');
 end if;
 perform public.reconcile_invoice_commissions(i.id,''Refund: ''||p_reason);');
    if position('writeoff_released_credit_on_close' in f) = 0 then
      raise exception 'refund_invoice_recorded does not match what 327 expects — align it by hand'; end if;
    execute f;
  end if;
end $do$;

commit;
