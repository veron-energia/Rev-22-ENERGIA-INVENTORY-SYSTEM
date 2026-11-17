-- 504_a_deleted_invoice_takes_no_payment.sql
--
-- A DELETED INVOICE TAKES NO PAYMENT
--
--   From the security audit of 17 Nov 2026 (finding H2).
--   The BEFORE md5s below were compared with production on 17 Nov 2026 (head 502) and match.
--   If production's text differs when this is applied, it refuses and changes nothing.
--   (The number 504 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   delete_invoice (417) deletes a draft or unpaid invoice by setting deleted_at; the status
--   stays unpaid. Recording a payment never looked at deleted_at. So a payment could be
--   recorded on a deleted invoice: it became paid, stock left, vouchers, credit and therapy
--   were issued and commission was earned, and because every money report leaves deleted
--   invoices out, the payment was in no Sales figure, no payment summary and no Xero export.
--   It also happened without intent: one person taking payment while another deleted the
--   invoice. Shown on a local copy on 17 Nov 2026: delete, then settle: status paid,
--   deleted, stock 10 to 9, one payment row, nothing in invoice_sales_ledger().
--
-- WHAT THIS DOES
--
--   1. invoice_record_payments_internal refuses a deleted invoice, straight after it locks
--      the invoice row: "This invoice was deleted, so it cannot take a payment." Every route
--      that records a payment comes through it: record_invoice_settlement, record_invoice_payment,
--      pay_invoice, the instalment and wallet routes, website and VIP orders (through
--      record_invoice_payment) and return_rental_with_fee (directly). Because the test comes
--      after the row lock, a delete that committed while the payment waited is seen.
--   2. A backstop on the table: a new trigger, invoice_payment_not_on_deleted_invoice (before
--      insert on invoice_payments, function trg_invoice_payment_not_on_deleted_invoice),
--      refuses a new receipt (entry_kind 'receipt') on a deleted invoice, whoever writes it,
--      with the same message. It lets corrections through (a 'correction_reversal' or
--      'correction_replacement' of a payment already there): correcting, removing or splitting
--      a payment that reached a deleted invoice before 504 is how such an invoice is put right,
--      and must still work. The exchange invoice's top-up receipt goes on the new exchange
--      invoice, which is never deleted. Refunds are written to invoice_refunds, not here.
--      The trigger function can be run by the service role only, like its neighbour
--      trg_block_wallet_credit_on_credit_lines.
--
-- WHAT THIS LEAVES ALONE
--
--   * Invoices this already happened to. Find them first, read-only:
--       select i.invoice_no, i.status, i.deleted_at, i.paid_amount from public.invoices i
--        where i.deleted_at is not null
--          and (i.status::text not in ('draft','unpaid')
--               or exists (select 1 from public.invoice_payments p where p.invoice_id = i.id));
--     On 17 Nov 2026 production had 6: 5 cancelled with payment rows, 1 completed FOC with
--     none. Each one needs a decision (bring the invoice back, or reverse the payment).
--   * Payment corrections, removals and splits, which do not look at deleted_at (see 2).
--   * delete_invoice, FOC confirmation and hand-over, which already refuse a deleted invoice.
--
-- UNDO
--
--   Run this block with c_before and c_after swapped and c_anchor and c_new swapped (it then
--   refuses unless the function is 504's version), then:
--     drop trigger if exists invoice_payment_not_on_deleted_invoice on public.invoice_payments;
--     drop function if exists public.trg_invoice_payment_not_on_deleted_invoice();
--   A later migration changing invoice_record_payments_internal must pin 504's AFTER md5.
--
-- NO SELF-TEST INSIDE: it would have to raise an invoice, which uses up an invoice number
-- even when undone. The suite is scripts/invoices/tests/deleted-invoice-no-payment-504.sql,
-- for a local copy.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function(s) this patches: BEFORE (the rebuilt copy of production) and AFTER md5s
  c_sig constant text[] := array[
    'invoice_record_payments_internal(uuid,jsonb)'];
  c_before constant text[] := array[
    '21890d84bcb0b9c00a2bc98aff313d0b'];
  c_after constant text[] := array[
    '40b3f45fa283bd54b0f6422363f0e3a2'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO swaps them back.
  c_fn constant int[] := array[1];
  c_anchor constant text[] := array[
$a$  if not found then raise exception 'Invoice not found'; end if;
  -- 357: settled before (its sales or settlement commission exist), or money$a$];
  c_new constant text[] := array[
$n$  if not found then raise exception 'Invoice not found'; end if;
  -- 504: a deleted invoice takes no payment. Deleting only sets deleted_at and
  -- leaves the status unpaid, and every money report leaves deleted invoices
  -- out, so a payment taken here was in no report. Every route that records a
  -- payment comes through this function, after the row lock above.
  if v_inv.deleted_at is not null then
    raise exception 'This invoice was deleted, so it cannot take a payment.'; end if;
  -- 357: settled before (its sales or settlement commission exist), or money$n$];
  -- Relied on, not changed
  c_relied constant text[] := array[
    'record_invoice_payment(uuid,jsonb,uuid)',
    'record_invoice_settlement(uuid,jsonb,uuid)',
    'delete_invoice(uuid,text)'];
  c_relied_md5 constant text[] := array[
    '9c70097ed4da614fb9dcc66fdfcdb7d6',
    '8c8778af82899c6aaada62371d13802f',
    '530b8217e94c9bbb0765c47da2d8d40e'];

  -- The backstop: a new trigger function (absent, or already this version) and its trigger
  c_trg_fn constant text := 'trg_invoice_payment_not_on_deleted_invoice()';
  c_trg_md5 constant text := 'ea497754b2e76b553b89e0bcff7a2f0b';
  c_trg_def constant text := $t$CREATE OR REPLACE FUNCTION public.trg_invoice_payment_not_on_deleted_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 504: a backstop behind invoice_record_payments_internal. A new receipt on
  -- a deleted invoice is refused, whoever writes it. Corrections (a reversal or
  -- a replacement of a payment already there) are let through, so a payment
  -- that reached a deleted invoice before 504 can still be removed or put right.
  if new.entry_kind = 'receipt'
     and exists (select 1 from public.invoices i
                  where i.id = new.invoice_id and i.deleted_at is not null) then
    raise exception 'This invoice was deleted, so it cannot take a payment.';
  end if;
  return new;
end $function$
$t$;
  c_trg constant text := 'invoice_payment_not_on_deleted_invoice';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_trg_make boolean := false;
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy invoice_payments or function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '504: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The function(s) it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '504: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '504: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '504: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- The backstop's function: absent (made), or already this version (left alone).
  if to_regprocedure('public.' || c_trg_fn) is null then
    v_trg_make := true;
  elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_trg_fn))) <> c_trg_md5 then
    raise exception '504: public.% is there but not the tested version (md5 %)', c_trg_fn,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_trg_fn)));
  else
    raise notice '504: public.% is already this version; left alone', c_trg_fn;
  end if;
  -- Its trigger: absent, or exactly before insert, for each row, enabled, on this function.
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_payments'::regclass and t.tgname = c_trg
               and not (v_trg_make = false and t.tgfoid = to_regprocedure('public.' || c_trg_fn)
                        and t.tgtype = 7 and t.tgenabled = 'O')) then
    raise exception '504: a trigger % on invoice_payments is there but is not the tested one', c_trg; end if;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '504: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '504: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  if v_trg_make then
    execute c_trg_def;
    -- A trigger function is not for calling: the service role only, as its neighbour.
    revoke all on function public.trg_invoice_payment_not_on_deleted_invoice() from public, anon, authenticated;
    grant execute on function public.trg_invoice_payment_not_on_deleted_invoice() to service_role;
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_payments'::regclass and t.tgname = c_trg) then
    create trigger invoice_payment_not_on_deleted_invoice before insert on public.invoice_payments
      for each row execute function public.trg_invoice_payment_not_on_deleted_invoice();
  else
    raise notice '504: trigger % is already there; left alone', c_trg;
  end if;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '504: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '504: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  if md5(pg_get_functiondef(to_regprocedure('public.' || c_trg_fn))) <> c_trg_md5 then
    raise exception '504: public.% was installed with an md5 other than the tested one', c_trg_fn; end if;
  if has_function_privilege('anon', to_regprocedure('public.' || c_trg_fn), 'execute')
     or has_function_privilege('authenticated', to_regprocedure('public.' || c_trg_fn), 'execute')
     or not has_function_privilege('service_role', to_regprocedure('public.' || c_trg_fn), 'execute') then
    raise exception '504: public.% must be for the service role only', c_trg_fn; end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_payments'::regclass and t.tgname = c_trg
                   and t.tgfoid = to_regprocedure('public.' || c_trg_fn) and t.tgtype = 7 and t.tgenabled = 'O') then
    raise exception '504: trigger % is not in place as tested', c_trg; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
