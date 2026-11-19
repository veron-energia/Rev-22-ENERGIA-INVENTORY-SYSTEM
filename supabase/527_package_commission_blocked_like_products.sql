-- 527_package_commission_blocked_like_products.sql
--
-- PACKAGE AND BUNDLE COMMISSION IS BLOCKED, AS A PRODUCT LINE'S IS, WHEN THE REFERRER MAY NOT
-- EARN
--
--   From the security audit of 17 Nov 2026 (finding M2).
--   The BEFORE md5s and the relied-on md5s below are those of production after 526 (the local
--   copy of 18 Nov 2026). If production differs when this is applied, it refuses and changes
--   nothing.
--   (The number 527 is this file's name and its errors' prefix; if it changes at commit,
--   change it there, in the 527 comments it writes into the three functions (and so their
--   AFTER md5s, also in scripts/commissions/undo-527.sql and in the suites that know them), and
--   in the name and path of its suite.)
--
-- WHAT WAS WRONG
--
--   Every Credit Package or Premium Bundle sold to a referred customer booked commission for
--   tier 1 and tier 2 as 'earned', even when the referrer was suspended, had never been
--   activated as an affiliate, or was an inactive customer. A product line on the same invoice
--   books such a referrer's commission 'blocked' (earn_invoice_commission, Phase 5): shown in
--   reports, never paid. So a package or bundle sale could pay commission to someone who may
--   not earn any. Three functions wrote it so:
--     1. earn_credit_package_commission, at payment in full of a package line (and again on a
--        correction, refund or reopening, by reconcile_invoice_commissions);
--     2. earn_premium_bundle_commission, the same for a bundle line;
--     3. invoice_package_commission_preview, which tells the part-payment layer (357,
--        invoice_instalment_commission_targets, sync_instalment_commissions) what a package or
--        bundle line will earn, so an invoice paid in part booked 'earned' part-payment
--        commission for such a referrer as each part arrived. Its own comment said so: "'earned',
--        as the package functions record it today (they do not check activation)".
--
-- THE RULE (the user, 18 Nov 2026: "Block them like products")
--
--   From go-live, package and bundle commission for a referrer who is not an eligible affiliate
--   is recorded exactly as earn_invoice_commission records it for product lines: status
--   'blocked' with block_reason = public.affiliate_block_reason(<referrer>), visible in reports,
--   never paid, never released later. Tier 1 and tier 2 are judged separately: a blocked tier 1
--   does not block tier 2, and the other way round. An eligible referrer: no change at all (the
--   same amounts, rates, dates and rows).
--
-- WHAT THIS DOES
--
--   * earn_credit_package_commission and earn_premium_bundle_commission judge each tier as
--     earn_invoice_commission does (public.is_eligible_affiliate; when not, the reason from
--     public.affiliate_block_reason: 'Affiliate Not Activated', 'Affiliate Suspended',
--     'Customer Inactive') and write that status and block_reason into the row. The referrers,
--     the basis, the rates, the amounts, the date and what each returns are as before.
--   * invoice_package_commission_preview gives the same status and reason for each tier, so the
--     part-payment layer books such a referrer's share 'blocked' (information only, replaced
--     when it changes), as it already does for product lines (invoice_affiliate_commission_
--     preview). sync_instalment_commissions is unchanged: it pays only targets that say
--     'earned' and writes 'blocked' targets as blocked rows.
--   * Every caller follows with no change: reconcile_invoice_commissions (a correction, a
--     refund, a reopening) reverses the unpaid rows and earns again through these two
--     functions; issue_credit_lines_for_invoice, issue_premium_bundle_invoice_item,
--     sell_credit_package_with_vouchers, sell_premium_bundle and link_affiliate_signup call
--     them as before. No other function writes package or bundle commission (read on the copy
--     of 18 Nov 2026).
--
-- WHAT THIS LEAVES ALONE
--
--   * The rows already written. None needs repair: on production (18 Nov 2026) all 12 package
--     and bundle commission rows belong to referrers who are eligible now. This changes
--     functions only, no data.
--   * Eligible referrers: the same rows exactly. Product lines, staff commission, payouts and
--     their balances (affiliate_month_balances counts 'earned' and 'paid' only, so a blocked
--     row is never payable), reports, the rates, the pages.
--   * The grants of the three functions (the service role only, as before).
--   * The public Affiliate Rules page (clause 10 already says commission is paid to active
--     affiliates and a suspended period's is normally shown as Blocked).
--   * As for a product line already: when an invoice whose package commission was paid out is
--     worked out again (reconcile_invoice_commissions) after its referrer stopped being
--     eligible, the row earned again is blocked, so what was paid out is taken back from the
--     referrer's later commission ("Future payout adjustment", 410) instead of being netted
--     against a new earned row.
--
-- UNDO
--
--   scripts/commissions/undo-527.sql (it refuses unless the three functions are 527's
--   versions) puts the three functions back exactly as they were. Rows written blocked while
--   527 was in stay blocked. A later migration changing any of the three must pin 527's AFTER
--   md5 (scripts/invoices/tests/part-paid-change-same-as-paid-in-full-476.sql, -v nomig=1,
--   checks invoice_package_commission_preview's md5: with 527 in, it must accept 527's AFTER).
--
-- NO SELF-TEST INSIDE; the suite is scripts/commissions/tests/package-commission-blocked-527.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the patched ones rely on, as tested (eligibility and its reason).
  c_relied constant text[] := array[
    'is_eligible_affiliate(uuid)',
    'affiliate_block_reason(uuid)',
    'customer_affiliate_state(uuid)'];
  c_relied_md5 constant text[] := array[
    '2dfbe1cee8c2be5b5e14a0d19f0553c4',
    '8cd46c7a29ed2701de7d8358a4d3dc88',
    '887d0b58f4d1f6670adbaf10591e0f9c'];
  -- The functions patched.
  c_sig constant text[] := array[
    'earn_credit_package_commission(uuid)',
    'earn_premium_bundle_commission(uuid)',
    'invoice_package_commission_preview(uuid)'];
  c_before constant text[] := array[
    '13ce59fd892c027338a41de4113ae55d',
    'b75ffbea70fd020e75d1ddf4f7b06ba1',
    '5ed13af2d3104dd04b4739b3ab8507bc'];
  -- Their grants, before and after: the service role's only.
  c_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_after constant text[] := array[
    'ad9bbf2183d6e19da85e7f59ce4a4b6e',
    '39429d3a496274811dce3c3f5f7ca29b',
    '966e8b7166607aa1d986f20fbbbc1e52'];
  -- Eleven patches, each found exactly once in its function: four in each earn function
  -- (its variables, the judgement of each tier, the tier 1 row, the tier 2 row), three in the
  -- preview (its variables, the judgement and tier 1, tier 2).
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
  v_make boolean[] := array_fill(false, array[3]);
  v_acl text[] := array_fill(null::text, array[3]);
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table or function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '527: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  -- What the new rows are written with: the column and the status.
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'commissions' and column_name = 'block_reason')
     or not exists (select 1 from pg_enum e where e.enumtypid = 'public.commission_status'::regtype and e.enumlabel = 'blocked') then
    raise exception '527: public.commissions.block_reason or the commission status ''blocked'' is missing';
  end if;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '527: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if v_acl[i] is distinct from c_acl then
      raise exception '527: the grants of public.% are not the tested ones (%). Re-read them before applying.', c_sig[i], v_acl[i]; end if;
    if md5(d) = c_after[i] then
      raise notice '527: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '527: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '527: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '527: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '527: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '527: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '527: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
