-- UNDO of 527 (with the user's go-ahead). It puts earn_credit_package_commission,
-- earn_premium_bundle_commission and invoice_package_commission_preview back to their text before
-- 527 (md5 13ce59fd…, b75ffbea…, 5ed13af2…): package and bundle commission is booked 'earned'
-- again for every referrer, an eligible affiliate or not (the security audit's M2 open again).
-- Their grants stay as they are (the service role only). The rows 527's functions wrote stay as
-- they were written: a blocked row stays blocked (a correction, refund or reopening of its
-- invoice later earns it again, 'earned', through reconcile_invoice_commissions).
--
-- No page or function of the app has to be put back first: 527 changed no signature and no
-- caller.
--
-- It refuses, with nothing changed, unless the three functions are exactly 527's versions (so a
-- later version is never overwritten). One transaction, all or nothing; it waits at most 5
-- seconds for a lock. The 527 row in supabase_migrations.schema_migrations stays; with the
-- user's OK, remove that one row (found by its name, 527_package_commission_blocked_like_products)
-- or record this UNDO beside it.
--
-- The patch texts below are 527's, the other way round: each 527 text is found exactly once and
-- put back as it was.
do $undo$
declare
  c_sig constant text[] := array[
    'earn_credit_package_commission(uuid)',
    'earn_premium_bundle_commission(uuid)',
    'invoice_package_commission_preview(uuid)'];
  c_527 constant text[] := array[
    'ad9bbf2183d6e19da85e7f59ce4a4b6e',
    '39429d3a496274811dce3c3f5f7ca29b',
    '966e8b7166607aa1d986f20fbbbc1e52'];
  c_before_527 constant text[] := array[
    '13ce59fd892c027338a41de4113ae55d',
    'b75ffbea70fd020e75d1ddf4f7b06ba1',
    '5ed13af2d3104dd04b4739b3ab8507bc'];
  c_fn constant int[] := array[1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3];
  c_anchor constant text[] := array[
-- 1 earn_credit_package_commission
$a$  v_paid_date date;
begin
  select * into s from public.credit_package_sales where id = p_sale_id;
$a$,
$a$  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;
$a$,
$a$    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      'earned', v_paid_date);
$a$,
$a$        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          'earned', v_paid_date);
$a$,
-- 2 earn_premium_bundle_commission
$a$  v_paid_date date;
begin
  select * into s from public.premium_bundle_sales where id = p_sale_id;
$a$,
$a$  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;
$a$,
$a$    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      'earned', v_paid_date);
$a$,
$a$        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          'earned', v_paid_date);
$a$,
-- 3 invoice_package_commission_preview
$a$        v476_buyer uuid;  -- 476
begin
$a$,
$a$    -- 'earned', as the package functions record it today (they do not check activation).
    return query select v_it.item_id, v476_buyer, v_t1, 'tier1'::text, v_cls, v_base, v_r1, v_a1, 'earned'::text, null::text;
$a$,
$a$        return query select v_it.item_id, v476_buyer, v_t2, 'tier2'::text, v_cls, v_a1, v_r2, v_a2, 'earned'::text, null::text;
$a$];
  c_new constant text[] := array[
-- 1 earn_credit_package_commission
$n$  v_paid_date date;
  -- 527: each tier's status and, when blocked, its reason
  v_t1_status text; v_t1_block text; v_t2_status text; v_t2_block text;
begin
  select * into s from public.credit_package_sales where id = p_sale_id;
$n$,
$n$  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;
  -- 527 (security audit of 17 Nov 2026, M2; the user, 18 Nov 2026: "Block them like
  -- products"): each tier is judged on its own, exactly as earn_invoice_commission judges a
  -- product line. A referrer who is not an eligible affiliate (suspended, never activated,
  -- an inactive customer) still gets the row, but 'blocked' with its reason: shown in
  -- reports, never paid, never released later. A blocked tier 1 does not block tier 2, nor
  -- the other way round. An eligible referrer earns exactly as before.
  v_t1_status := case when public.is_eligible_affiliate(v_t1) then 'earned' else 'blocked' end;
  v_t1_block := case when v_t1_status = 'blocked' then public.affiliate_block_reason(v_t1) else null end;
  if v_t2 is not null then
    v_t2_status := case when public.is_eligible_affiliate(v_t2) then 'earned' else 'blocked' end;
    v_t2_block := case when v_t2_status = 'blocked' then public.affiliate_block_reason(v_t2) else null end;
  end if;
$n$,
$n$    -- 527 (security audit of 17 Nov 2026, M2; the user, 18 Nov 2026): tier 1's status and reason
    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
$n$,
$n$        -- 527 (security audit of 17 Nov 2026, M2; the user, 18 Nov 2026): tier 2's own status and reason
        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          v_t2_status::commission_status, v_t2_block, v_paid_date);
$n$,
-- 2 earn_premium_bundle_commission
$n$  v_paid_date date;
  -- 527: each tier's status and, when blocked, its reason
  v_t1_status text; v_t1_block text; v_t2_status text; v_t2_block text;
begin
  select * into s from public.premium_bundle_sales where id = p_sale_id;
$n$,
$n$  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;
  -- 527 (security audit of 17 Nov 2026, M2; the user, 18 Nov 2026: "Block them like
  -- products"): each tier is judged on its own, exactly as earn_invoice_commission judges a
  -- product line. A referrer who is not an eligible affiliate (suspended, never activated,
  -- an inactive customer) still gets the row, but 'blocked' with its reason: shown in
  -- reports, never paid, never released later. A blocked tier 1 does not block tier 2, nor
  -- the other way round. An eligible referrer earns exactly as before.
  v_t1_status := case when public.is_eligible_affiliate(v_t1) then 'earned' else 'blocked' end;
  v_t1_block := case when v_t1_status = 'blocked' then public.affiliate_block_reason(v_t1) else null end;
  if v_t2 is not null then
    v_t2_status := case when public.is_eligible_affiliate(v_t2) then 'earned' else 'blocked' end;
    v_t2_block := case when v_t2_status = 'blocked' then public.affiliate_block_reason(v_t2) else null end;
  end if;
$n$,
$n$    -- 527 (security audit of 17 Nov 2026, M2; the user, 18 Nov 2026): tier 1's status and reason
    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
$n$,
$n$        -- 527 (security audit of 17 Nov 2026, M2; the user, 18 Nov 2026): tier 2's own status and reason
        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          v_t2_status::commission_status, v_t2_block, v_paid_date);
$n$,
-- 3 invoice_package_commission_preview
$n$        v476_buyer uuid;  -- 476
        v_t1_status text; v_t1_block text; v_t2_status text; v_t2_block text;  -- 527
begin
$n$,
$n$    -- 527 (security audit of 17 Nov 2026, M2; the user, 18 Nov 2026: "Block them like
    -- products"): each tier's status as the package functions now record it, so the
    -- part-payment layer books a referrer who is not an eligible affiliate 'blocked', with
    -- its reason (never paid), as it does for a product line. Each tier is judged on its own.
    v_t1_status := case when public.is_eligible_affiliate(v_t1) then 'earned' else 'blocked' end;
    v_t1_block := case when v_t1_status = 'blocked' then public.affiliate_block_reason(v_t1) else null end;
    return query select v_it.item_id, v476_buyer, v_t1, 'tier1'::text, v_cls, v_base, v_r1, v_a1, v_t1_status, v_t1_block;
$n$,
$n$        v_t2_status := case when public.is_eligible_affiliate(v_t2) then 'earned' else 'blocked' end;  -- 527
        v_t2_block := case when v_t2_status = 'blocked' then public.affiliate_block_reason(v_t2) else null end;
        return query select v_it.item_id, v476_buyer, v_t2, 'tier2'::text, v_cls, v_a1, v_r2, v_a2, v_t2_status, v_t2_block;
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[3]);
  v_acl text[] := array_fill(null::text, array[3]);
  i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception 'UNDO 527: public.% is missing', c_sig[i]; end if;
    v_def[i] := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(v_def[i]) <> c_527[i] then
      raise exception 'UNDO 527: public.% is not 527''s version (md5 %). Nothing changed.', c_sig[i], md5(v_def[i]); end if;
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 527: patch % does not find 527''s text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before_527[i] then
      raise exception 'UNDO 527: the text put back for public.% is not the one before 527 (md5 %). Nothing changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Put back
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before_527[i] then
      raise exception 'UNDO 527: public.% was put back with an md5 other than the one before 527', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception 'UNDO 527: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
