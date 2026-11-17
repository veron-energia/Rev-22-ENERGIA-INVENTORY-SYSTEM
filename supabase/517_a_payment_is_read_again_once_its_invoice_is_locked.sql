-- 517_a_payment_is_read_again_once_its_invoice_is_locked.sql
--
-- A PAYMENT IS READ AGAIN ONCE ITS INVOICE IS LOCKED
--
--   From the security audit of 17 Nov 2026 (finding L5).
--   The BEFORE md5s below were compared with production on 17 Nov 2026 (head 516) and match.
--   If production's text differs when this is applied, it refuses and changes nothing.
--   (The number 517 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   Correcting a payment (correct_invoice_payment, the invoice's Correct payment), removing
--   one (remove_invoice_payment) and splitting one (split_invoice_payment) read the payment
--   first and only then locked its invoice, and went on with what they had read. Edit
--   Invoice (correct_invoice) changes a payment's method in place, under the invoice's lock
--   (correct_invoice_payment_methods). A Correct payment that read the payment just before
--   such a change waited for the lock and then booked its reversal under the method the
--   payment no longer had: one method's takings came out too low and another's too high.
--   Remove and split are reached only from Edit Invoice, which locks the invoice before it
--   calls them, so for them it was a trap left for a later caller.
--
-- WHAT THIS DOES
--
--   Each of the three reads the payment again once the invoice is locked, and locks it too
--   (the invoice first, then the payment, as refunds do). A payment that no longer belongs
--   to that invoice is refused: "This payment changed while it was being corrected. Reload
--   the invoice and try again."
--
-- WHAT THIS LEAVES ALONE
--
--   Everything else in the three, correct_invoice and correct_invoice_payment_methods.
--
-- UNDO
--
--   Run this block with c_before and c_after swapped and c_anchor and c_new swapped; it then
--   refuses unless the functions are 517's version. A later migration changing any of the
--   three must pin 517's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/invoices/tests/payment-read-after-lock-517.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  c_sig constant text[] := array[
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'remove_invoice_payment(uuid,text,uuid)',
    'split_invoice_payment(uuid,jsonb,text,uuid)'];
  c_before constant text[] := array[
    'af99337094edb6d73b9cc0ae00fbf138',
    '29abf78aed704abb31b3faefd4153a28',
    'e385a9958c78dc9dc2aa82737958689e'];
  c_after constant text[] := array[
    '29c319b8306a39f940ccb3bb240336b6',
    '8eb341eb5383430f676940be1de37def',
    '07c1b8191e2802e0ca388ab181ae4886'];
  c_fn constant int[] := array[1, 2, 3];
  c_anchor constant text[] := array[
$a$ select * into p from public.invoice_payments where id=p_payment_id;
 if not found then raise exception 'Payment not found'; end if;
 select * into i from public.invoices where id=p.invoice_id for update;$a$,
$a$  select * into p from public.invoice_payments where id = p_payment_id;
  if not found then raise exception 'Payment not found'; end if;
  select * into i from public.invoices where id = p.invoice_id for update;$a$,
$a$  select * into p from public.invoice_payments where id = p_payment_id;
  if not found then raise exception 'Payment not found'; end if;
  select * into i from public.invoices where id = p.invoice_id for update;$a$];
  c_new constant text[] := array[
$n$ select * into p from public.invoice_payments where id=p_payment_id;
 if not found then raise exception 'Payment not found'; end if;
 select * into i from public.invoices where id=p.invoice_id for update;
 -- 517: the payment again, now that its invoice is locked, and locked too
 -- (security audit of 17 Nov 2026, L5). Read only before the lock, it could
 -- be one Edit Invoice had just given another method, and the reversal below
 -- was then booked under the method it no longer had.
 select * into p from public.invoice_payments where id=p_payment_id for update;
 if not found or p.invoice_id is distinct from i.id then
   raise exception 'This payment changed while it was being corrected. Reload the invoice and try again.'; end if;$n$,
$n$  select * into p from public.invoice_payments where id = p_payment_id;
  if not found then raise exception 'Payment not found'; end if;
  select * into i from public.invoices where id = p.invoice_id for update;
  -- 517: the payment again, now that its invoice is locked, and locked too
  -- (security audit of 17 Nov 2026, L5), so what is removed is the payment
  -- as it now stands.
  select * into p from public.invoice_payments where id = p_payment_id for update;
  if not found or p.invoice_id is distinct from i.id then
    raise exception 'This payment changed while it was being corrected. Reload the invoice and try again.'; end if;$n$,
$n$  select * into p from public.invoice_payments where id = p_payment_id;
  if not found then raise exception 'Payment not found'; end if;
  select * into i from public.invoices where id = p.invoice_id for update;
  -- 517: the payment again, now that its invoice is locked, and locked too
  -- (security audit of 17 Nov 2026, L5), so what is split is the payment as
  -- it now stands.
  select * into p from public.invoice_payments where id = p_payment_id for update;
  if not found or p.invoice_id is distinct from i.id then
    raise exception 'This payment changed while it was being corrected. Reload the invoice and try again.'; end if;$n$];
  -- Relied on, not changed: Edit Invoice locks the invoice before it changes a method or
  -- calls the three; the method change it makes in place.
  c_relied constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'correct_invoice_payment_methods(uuid,jsonb,text)'];
  c_relied_md5 constant text[] := array[
    'cea93a5dd73d429f6437f4c9a8fcaa52',
    '898afdee6c3cf57893ac81654597dff0'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[3]);
  v_make boolean[] := array_fill(false, array[3]);
  v_acl text[] := array_fill(null::text, array[3]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '517: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '517: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '517: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '517: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '517: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '517: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '517: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '517: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
