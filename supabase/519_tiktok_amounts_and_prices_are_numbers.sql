-- 519_tiktok_amounts_and_prices_are_numbers.sql
--
-- TIKTOK ORDER AMOUNTS AND PRICES ARE NUMBERS
--
--   From the security audit of 17 Nov 2026 (finding L21), after 518.
--   The BEFORE md5 below was compared with production on 18 Nov 2026 (head 518) and matches;
--   production then held no "not a number" (NaN) in any of the columns below. If production
--   differs when this is applied, it refuses and changes nothing.
--   (The number 519 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   518 made the amounts on invoices, payments, refunds, credit and commissions numbers.
--   Two other ways in still stored NaN (PostgreSQL counts it as larger than every number, so
--   "below zero" tests let it through):
--   * TikTok order files (stage_tiktok_orders, any staff login of the store). A row's
--     subtotals and refund amount were read straight from the file, so "NaN" was staged and,
--     confirmed, kept; it then fed the order's financial difference and the settlement's
--     weighting. A spreadsheet writes "NaN" for an empty cell. The settlement file already
--     reads its amounts with tiktok_parse_amount, which treats one as missing.
--   * Prices and other definitions set by an Owner or Manager: product, promotion, voucher and
--     therapy prices, special products, credit packages, premium bundles, event tickets and
--     the early-bird percent, a store's GST rate, and the hours between a repeating therapy
--     voucher's uses. A NaN price was stored; since 518 a sale that used it is refused, but
--     the price stayed.
--
-- WHAT THIS DOES
--
--   * stage_tiktok_orders reads an amount that is not a number ("NaN", "Infinity") as a
--     missing one, as it reads an empty cell. Everything else it does is as before.
--   * Seventeen tables get a check that every amount in them is a number
--     (<table>_amounts_are_numbers): tiktok_order_rows, and store_product_prices,
--     promotion_store_prices, promotions, voucher_store_prices, vouchers,
--     therapy_service_stores, therapy_services, unlimited_therapy_store_prices,
--     therapy_voucher_definitions, special_products, credit_packages, premium_bundles,
--     event_ticket_options, events, products and stores. The functions that set them, and any direct write a rule allows,
--     are then refused with the database's own words; only a crafted request sends one.
--   The test is the one four functions already use: the amount as text is not 'NaN',
--   'Infinity' or '-Infinity'. These columns all have a precision, so Infinity was refused
--   already ("numeric field overflow"); NaN is what this stops.
--
-- WHAT THIS LEAVES ALONE
--
--   * The functions that set prices and definitions; their own tests are unchanged.
--   * Every number that is a number.
--
-- UNDO
--
--   Drop the seventeen checks <table>_amounts_are_numbers; then run this block's function part
--   with c_before and c_after swapped and c_anchor and c_new swapped. A later migration
--   changing stage_tiktok_orders must pin 519's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/tiktok/tests/amounts-are-numbers-519.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  c_sig constant text[] := array[
    'stage_tiktok_orders(uuid,text,text,jsonb)'];
  c_before constant text[] := array[
    '9cad8a716950fdaab791f6f42cdddf7c'];
  c_after constant text[] := array[
    'ac4c840689c50433504377aa63664188'];
  c_fn constant int[] := array[1, 1, 1];
  c_anchor constant text[] := array[
$a$  v_eval record; v_after numeric;$a$,
$a$    v_after := nullif(v_r->>'sku_subtotal_after','')::numeric;$a$,
$a$      nullif(v_r->>'sku_subtotal_before','')::numeric, v_after,
      nullif(v_r->>'refund_amount','')::numeric,$a$];
  c_new constant text[] := array[
$n$  v_eval record; v_after numeric;
  v519_before numeric; v519_refund numeric;  -- 519: the row's other two amounts, read once$n$,
$n$    v_after := nullif(v_r->>'sku_subtotal_after','')::numeric;
    v519_before := nullif(v_r->>'sku_subtotal_before','')::numeric;
    v519_refund := nullif(v_r->>'refund_amount','')::numeric;
    -- 519: an amount that is not a number ("NaN", or "Infinity") is a missing
    -- one, as an empty cell is (security audit of 17 Nov 2026, L21). A
    -- spreadsheet writes "NaN" for an empty cell; it used to be kept as NaN.
    if v_after::text in ('NaN', 'Infinity', '-Infinity') then v_after := null; end if;
    if v519_before::text in ('NaN', 'Infinity', '-Infinity') then v519_before := null; end if;
    if v519_refund::text in ('NaN', 'Infinity', '-Infinity') then v519_refund := null; end if;$n$,
$n$      v519_before, v_after,
      v519_refund,$n$];
  -- The checks: each table and the amounts in it.
  c_table constant text[] := array[
    'tiktok_order_rows', 'store_product_prices', 'promotion_store_prices', 'promotions',
    'voucher_store_prices', 'vouchers', 'therapy_service_stores', 'therapy_services',
    'unlimited_therapy_store_prices', 'special_products', 'credit_packages', 'premium_bundles',
    'event_ticket_options', 'events', 'products', 'stores', 'therapy_voucher_definitions'];
  c_cols constant text[] := array[
    'sku_subtotal_before,sku_subtotal_after,refund_amount,prev_sku_subtotal_after,financial_delta',
    'selling_price',
    'selling_price',
    'fixed_price',
    'selling_price',
    'discount_amount,discount_percent,max_discount_cap,selling_price',
    'price_override',
    'standard_price,frequency_interval_hours',
    'selling_price',
    'sale_price,rate_day,rate_week,rate_month,rate_year,late_fee_per_day',
    'customer_price,paid_credit_amount,staff_commission_rate,tier1_rate,tier2_rate,reward_qualifying_amount,bonus_value',
    'customer_payment_amount,paid_credit_amount,bonus_credit_amount,reward_qualifying_amount,staff_commission_rate,tier1_rate,tier2_rate',
    'price',
    'early_bird_percent',
    'default_cost_price',
    'gst_rate',
    'repeat_interval_hours'];
  c_check_def constant text[] := array[
    'CHECK ((((sku_subtotal_before)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((sku_subtotal_after)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((refund_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((prev_sku_subtotal_after)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((financial_delta)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK (((selling_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK (((selling_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK (((fixed_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK (((selling_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK ((((discount_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((discount_percent)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((max_discount_cap)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((selling_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK (((price_override)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK ((((standard_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((frequency_interval_hours)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK (((selling_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK ((((sale_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((rate_day)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((rate_week)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((rate_month)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((rate_year)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((late_fee_per_day)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK ((((customer_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((paid_credit_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((staff_commission_rate)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((tier1_rate)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((tier2_rate)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((reward_qualifying_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((bonus_value)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK ((((customer_payment_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((paid_credit_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((bonus_credit_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((reward_qualifying_amount)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((staff_commission_rate)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((tier1_rate)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])) AND ((tier2_rate)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text]))))',
    'CHECK (((price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK (((early_bird_percent)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK (((default_cost_price)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK (((gst_rate)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))',
    'CHECK (((repeat_interval_hours)::text <> ALL (ARRAY[''NaN''::text, ''Infinity''::text, ''-Infinity''::text])))'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  v_add boolean[] := array_fill(false, array[17]);
  v_expr text[] := array_fill(null::text, array[17]);
  v_bad text := '';
  d text; i int; n bigint;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  -- The checks: missing (added, once no row breaks them), or 519's already (left alone).
  for i in 1 .. cardinality(c_table) loop
    if (select count(*) from information_schema.columns
         where table_schema = 'public' and table_name = c_table[i] and data_type = 'numeric'
           and column_name = any (string_to_array(c_cols[i], ','))) <> cardinality(string_to_array(c_cols[i], ',')) then
      raise exception '519: public.% does not have the amount columns this was tested against', c_table[i]; end if;
    v_expr[i] := (select string_agg(format('%I::text not in (''NaN'', ''Infinity'', ''-Infinity'')', c), ' and ' order by o)
                    from unnest(string_to_array(c_cols[i], ',')) with ordinality u(c, o));
    d := (select pg_get_constraintdef(c.oid) from pg_constraint c
           where c.conrelid = ('public.' || c_table[i])::regclass and c.conname = c_table[i] || '_amounts_are_numbers');
    if d is null then
      execute format('select count(*) from public.%I where not (%s)', c_table[i], v_expr[i]) into n;
      if n > 0 then
        raise exception '519: % row(s) of public.% hold an amount that is not a number. Correct them first; nothing was changed.', n, c_table[i];
      end if;
      v_add[i] := true;
    elsif d = c_check_def[i] then
      raise notice '519: the check %_amounts_are_numbers is already on public.%; left alone', c_table[i], c_table[i];
    else
      raise exception '519: a check named %_amounts_are_numbers is on public.%, but not 519''s (%). Re-read it before applying.', c_table[i], c_table[i], d;
    end if;
  end loop;

  -- The function it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '519: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '519: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '519: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '519: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '519: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
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
      raise exception '519: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '519: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_table) loop
    d := (select pg_get_constraintdef(c.oid) from pg_constraint c
           where c.conrelid = ('public.' || c_table[i])::regclass and c.conname = c_table[i] || '_amounts_are_numbers' and c.convalidated);
    if d is distinct from c_check_def[i] then
      v_bad := v_bad || format(E'\n  %s: %s', c_table[i], coalesce(d, '(missing or not validated)'));
    end if;
  end loop;
  if v_bad <> '' then
    raise exception '519: the checks are not as tested:%', v_bad; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
