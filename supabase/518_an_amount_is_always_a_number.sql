-- 518_an_amount_is_always_a_number.sql
--
-- AN AMOUNT IS ALWAYS A NUMBER
--
--   From the security audit of 17 Nov 2026 (finding L21).
--   The BEFORE md5s below were compared with production on 18 Nov 2026 (head 517) and match;
--   production then held no "not a number" (NaN) or infinite amount in any of the columns
--   below. If production differs when this is applied, it refuses and changes nothing.
--   (The number 518 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   PostgreSQL counts NaN as larger than every number, and Infinity as larger than all of
--   them, so tests such as "below zero" and "zero or less" let both through, and so did the
--   checks manual_discount >= 0 (516) and amount > 0 on payments. No page sends either, but
--   a crafted request with the text "NaN" was saved:
--   * as an invoice's manual discount, on New Invoice and Edit Invoice: the invoice was
--     discounted in full, and the Discounts report then read NaN for it and for its total;
--   * as a corrected payment amount (an Owner or Manager): the invoice turned paid whatever
--     was received, its paid amount and the day's takings for that method read NaN, and the
--     app could not put it right.
--
-- WHAT THIS DOES
--
--   * New Invoice (create_invoice_with_details) refuses a manual discount that is not a
--     number: "The manual discount must be an amount in dollars and cents."
--   * Correct payment (correct_invoice_payment) refuses such an amount: "The corrected amount
--     must be an amount in dollars and cents." Split (split_invoice_payment) refuses such a
--     part: "Each part of a split needs an amount in dollars and cents".
--   * Seven tables get a check that every amount in them is a number, so no route can store
--     NaN or Infinity, whatever function it goes through: invoices, invoice_items,
--     invoice_payments, invoice_refunds, invoice_line_credit_allocations,
--     customer_credit_lots and commissions (<table>_amounts_are_numbers). Edit Invoice
--     (correct_invoice) is refused by the check on invoices, with the database's own words;
--     only a crafted request reaches it.
--   The test is the one four functions already use: the amount as text is not 'NaN',
--   'Infinity' or '-Infinity'.
--
-- WHAT THIS LEAVES ALONE
--
--   * correct_invoice and every other function. Amounts that only reach other tables
--     (prices, rates, payouts) are not checked here; four of those functions already refuse
--     NaN.
--   * Every number that is a number.
--
-- UNDO
--
--   Drop the seven checks <table>_amounts_are_numbers; then run this block's function part
--   with c_before and c_after swapped and c_anchor and c_new swapped. A later migration
--   changing any of the three functions must pin 518's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/invoices/tests/amounts-are-numbers-518.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  c_sig constant text[] := array[
    'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'split_invoice_payment(uuid,jsonb,text,uuid)'];
  c_before constant text[] := array[
    '7c37ac1d841d2c0c2a9cf9b54c563ead',
    '29c319b8306a39f940ccb3bb240336b6',
    '07c1b8191e2802e0ca388ab181ae4886'];
  c_after constant text[] := array[
    '0d60261bf337a1716dab9307b2f52fea',
    '088e2130d62a1dc4af8cd9417465c0b6',
    '236b86da67f77eb036592e1ce12ec366'];
  c_fn constant int[] := array[1, 2, 3];
  c_anchor constant text[] := array[
$a$ if coalesce((p_header->>'manual_discount')::numeric,0) < 0 then
   raise exception 'The manual discount cannot be negative.' using errcode = '22023'; end if;$a$,
$a$ if p_amount is null or p_amount<=0 or p_date is null then raise exception 'A positive corrected amount and actual payment date are required'; end if;$a$,
$a$    if coalesce((part.value->>'amount')::numeric, 0) <= 0 or nullif(part.value->>'date', '') is null then
      raise exception 'Each part of a split needs a positive amount and the date the money was received'; end if;$a$];
  c_new constant text[] := array[
$n$ -- 518: and a number (security audit of 17 Nov 2026, L21). PostgreSQL counts
 -- NaN as larger than every number, and Infinity as larger than all of them,
 -- so the test below let both through and the invoice was discounted in full.
 if coalesce((p_header->>'manual_discount')::numeric,0)::text in ('NaN','Infinity','-Infinity') then
   raise exception 'The manual discount must be an amount in dollars and cents.' using errcode = '22023'; end if;
 if coalesce((p_header->>'manual_discount')::numeric,0) < 0 then
   raise exception 'The manual discount cannot be negative.' using errcode = '22023'; end if;$n$,
$n$ -- 518: and a number (security audit of 17 Nov 2026, L21): NaN and Infinity
 -- pass "zero or less", and a NaN amount left the invoice paid with NaN.
 if p_amount::text in ('NaN','Infinity','-Infinity') then
   raise exception 'The corrected amount must be an amount in dollars and cents.' using errcode = '22023'; end if;
 if p_amount is null or p_amount<=0 or p_date is null then raise exception 'A positive corrected amount and actual payment date are required'; end if;$n$,
$n$    -- 518: and a number (security audit of 17 Nov 2026, L21): NaN and
    -- Infinity pass "zero or less".
    if coalesce((part.value->>'amount')::numeric, 0)::text in ('NaN', 'Infinity', '-Infinity') then
      raise exception 'Each part of a split needs an amount in dollars and cents' using errcode = '22023'; end if;
    if coalesce((part.value->>'amount')::numeric, 0) <= 0 or nullif(part.value->>'date', '') is null then
      raise exception 'Each part of a split needs a positive amount and the date the money was received'; end if;$n$];
  -- Relied on, not changed: Edit Invoice, which the check on invoices covers.
  c_relied constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)'];
  c_relied_md5 constant text[] := array[
    'cea93a5dd73d429f6437f4c9a8fcaa52'];
  -- The checks: each table, the amounts in it, and the check as pg_get_constraintdef shows it.
  c_table constant text[] := array[
    'invoices', 'invoice_items', 'invoice_payments', 'invoice_refunds',
    'invoice_line_credit_allocations', 'customer_credit_lots', 'commissions'];
  c_cols constant text[] := array[
    'subtotal,discount_total,total_amount,paid_amount,manual_discount,save_earth_amount,foc_total,exchange_credit_total,cancel_refund_owed',
    'unit_price,line_total,line_discount,topup_amount,original_price,member_price_snapshot,non_member_price_snapshot,foc_amount,foc_original_unit_price,credit_paid_snapshot,credit_bonus_snapshot,credit_split_ratio,credit_package_full_price_snapshot,bundle_split_ratio,premium_bundle_full_price_snapshot,line_discount_percent',
    'amount',
    'amount,credit_returned',
    'amount,reversed_amount',
    'original_amount,remaining_amount',
    'line_amount,rate,commission_amount'];
  c_check_def constant text[] := array[
    'CHECK ((((subtotal)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((discount_total)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((total_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((paid_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((manual_discount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((save_earth_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((foc_total)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((exchange_credit_total)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((cancel_refund_owed)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK ((((unit_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((line_total)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((line_discount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((topup_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((original_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((member_price_snapshot)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((non_member_price_snapshot)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((foc_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((foc_original_unit_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((credit_paid_snapshot)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((credit_bonus_snapshot)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((credit_split_ratio)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((credit_package_full_price_snapshot)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((bundle_split_ratio)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((premium_bundle_full_price_snapshot)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((line_discount_percent)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK (((amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK ((((amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((credit_returned)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK ((((amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((reversed_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK ((((original_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((remaining_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK ((((line_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((rate)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((commission_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[3]);
  v_make boolean[] := array_fill(false, array[3]);
  v_acl text[] := array_fill(null::text, array[3]);
  v_add boolean[] := array_fill(false, array[7]);
  v_expr text[] := array_fill(null::text, array[7]);
  v_bad text := '';
  d text; i int; n bigint;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '518: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The checks: missing (added, once no row breaks them), or 518's already (left alone).
  for i in 1 .. cardinality(c_table) loop
    if (select count(*) from information_schema.columns
         where table_schema = 'public' and table_name = c_table[i] and data_type = 'numeric'
           and column_name = any (string_to_array(c_cols[i], ','))) <> cardinality(string_to_array(c_cols[i], ',')) then
      raise exception '518: public.% does not have the amount columns this was tested against', c_table[i]; end if;
    v_expr[i] := (select string_agg(format('%I::text not in (''NaN'', ''Infinity'', ''-Infinity'')', c), ' and ' order by o)
                    from unnest(string_to_array(c_cols[i], ',')) with ordinality u(c, o));
    d := (select pg_get_constraintdef(c.oid) from pg_constraint c
           where c.conrelid = ('public.' || c_table[i])::regclass and c.conname = c_table[i] || '_amounts_are_numbers');
    if d is null then
      execute format('select count(*) from public.%I where not (%s)', c_table[i], v_expr[i]) into n;
      if n > 0 then
        raise exception '518: % row(s) of public.% hold an amount that is not a number. Correct them first; nothing was changed.', n, c_table[i];
      end if;
      v_add[i] := true;
    elsif d = c_check_def[i] then
      raise notice '518: the check %_amounts_are_numbers is already on public.%; left alone', c_table[i], c_table[i];
    else
      raise exception '518: a check named %_amounts_are_numbers is on public.%, but not 518''s (%). Re-read it before applying.', c_table[i], c_table[i], d;
    end if;
  end loop;

  -- The functions it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '518: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '518: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '518: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '518: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '518: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_table) loop
    if v_add[i] then
      execute format('alter table public.%I add constraint %I check (%s)', c_table[i], c_table[i] || '_amounts_are_numbers', v_expr[i]);
    end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '518: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '518: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_table) loop
    d := (select pg_get_constraintdef(c.oid) from pg_constraint c
           where c.conrelid = ('public.' || c_table[i])::regclass and c.conname = c_table[i] || '_amounts_are_numbers' and c.convalidated);
    if d is distinct from c_check_def[i] then
      v_bad := v_bad || format(E'\n  %s: %s', c_table[i], coalesce(d, '(missing or not validated)'));
    end if;
  end loop;
  if v_bad <> '' then
    raise exception '518: the checks are not as tested:%', v_bad; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
