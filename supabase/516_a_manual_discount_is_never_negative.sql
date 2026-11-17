-- 516_a_manual_discount_is_never_negative.sql
--
-- A MANUAL DISCOUNT IS NEVER NEGATIVE
--
--   From the security audit of 17 Nov 2026 (finding L4).
--   The BEFORE md5s below were compared with production on 17 Nov 2026 (head 515) and match;
--   production then had no invoice with a negative manual discount. If production differs
--   when this is applied, it refuses and changes nothing.
--   (The number 516 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   New Invoice (create_invoice_with_details) took a negative manual discount. The page's
--   field says 0 or more but lets a minus sign be typed. A negative discount raised the
--   total, so a fixed-amount voucher could be used below its minimum spend. And the invoice
--   could not be corrected afterwards: Edit Invoice (correct_invoice) refuses a negative
--   discount, so every later save of it was refused ("Discount cannot be negative").
--
-- WHAT THIS DOES
--
--   * create_invoice_with_details refuses a negative manual discount before anything is
--     saved: "The manual discount cannot be negative."
--   * invoices gets the check invoices_manual_discount_not_negative (manual_discount >= 0;
--     an invoice with none passes), so no route can save one: New Invoice, Edit Invoice,
--     exchanges, split packages and bundles, late fees, the service role.
--
-- WHAT THIS LEAVES ALONE
--
--   * correct_invoice, which already refuses a negative discount with its own message.
--   * The page. It shows the refusal where it shows every other one.
--   * Every other amount on an invoice.
--
-- UNDO
--
--   alter table public.invoices drop constraint invoices_manual_discount_not_negative; then
--   run this block's function part with c_before and c_after swapped and c_anchor and c_new
--   swapped. A later migration changing create_invoice_with_details must pin 516's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/invoices/tests/manual-discount-not-negative-516.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function this patches: BEFORE (production, 17 Nov 2026) and AFTER md5s
  c_sig constant text[] := array[
    'create_invoice_with_details(uuid,uuid,jsonb,jsonb)'];
  c_before constant text[] := array[
    '0ac29c7aa909dd756ec572645ca86448'];
  c_after constant text[] := array[
    '7c37ac1d841d2c0c2a9cf9b54c563ead'];
  c_fn constant int[] := array[1];
  c_anchor constant text[] := array[
$a$ if coalesce((p_header->>'manual_discount')::numeric,0) > 0
    and nullif(btrim(coalesce(p_header->>'manual_discount_reason','')),'') is null then
   raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.'; end if;$a$];
  c_new constant text[] := array[
$n$ -- 516: never below zero (security audit of 17 Nov 2026, L4). A negative
 -- manual discount raised the total, let a fixed-amount voucher be used below
 -- its minimum spend, and left an invoice Edit Invoice would not save again.
 if coalesce((p_header->>'manual_discount')::numeric,0) < 0 then
   raise exception 'The manual discount cannot be negative.' using errcode = '22023'; end if;
 if coalesce((p_header->>'manual_discount')::numeric,0) > 0
    and nullif(btrim(coalesce(p_header->>'manual_discount_reason','')),'') is null then
   raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.'; end if;$n$];
  -- Relied on, not changed: Edit Invoice already refuses a negative discount.
  c_relied constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)'];
  c_relied_md5 constant text[] := array[
    'cea93a5dd73d429f6437f4c9a8fcaa52'];
  -- The check on invoices, as pg_get_constraintdef shows it.
  c_check_name constant text := 'invoices_manual_discount_not_negative';
  c_check_def constant text := 'CHECK ((manual_discount >= (0)::numeric))';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  v_add_check boolean := false;
  d text; i int; n bigint;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '516: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The check: missing (added, once no invoice breaks it), or 516's already (left alone).
  d := (select pg_get_constraintdef(c.oid) from pg_constraint c
         where c.conrelid = 'public.invoices'::regclass and c.conname = c_check_name);
  if d is null then
    select count(*) into n from public.invoices where manual_discount < 0;
    if n > 0 then
      raise exception '516: % invoice(s) have a negative manual discount. Correct them first; nothing was changed.', n;
    end if;
    v_add_check := true;
  elsif d = c_check_def then
    raise notice '516: the check % is already on public.invoices; left alone', c_check_name;
  else
    raise exception '516: a check named % is on public.invoices, but not 516''s (%). Re-read it before applying.', c_check_name, d;
  end if;

  -- The function it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '516: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '516: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '516: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '516: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '516: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;
  if v_add_check then
    execute format('alter table public.invoices add constraint %I check (manual_discount >= 0)', c_check_name);
  end if;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '516: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '516: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.invoices'::regclass and c.conname = c_check_name
                    and c.convalidated and pg_get_constraintdef(c.oid) = c_check_def) then
    raise exception '516: the check % is not on public.invoices as tested', c_check_name; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
