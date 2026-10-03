-- 383_package_commission_keeps_the_paid_date.sql
--
-- WHAT WAS WRONG
--
-- An affiliate's commission belongs to the month of
-- commissions.invoice_paid_date: affiliate_month_balances buckets on it, and
-- payouts are recorded against those months. earn_invoice_commission and
-- earn_staff_commission take that date from the invoice
-- (coalesce(paid_at, now())::date). earn_credit_package_commission and
-- earn_premium_bundle_commission wrote public.sg_today() instead: the day the
-- row was written, not the day the invoice was paid.
--
-- The first time a package or bundle earns, those are the same day. It is
-- issued, and its commission earned, by the update that settles the invoice
-- (trg_create_therapy_on_paid -> issue_credit_lines_for_invoice), in the
-- transaction that sets paid_at. They part when the commission is earned
-- again. reconcile_invoice_commissions (Correct Invoice; a payment corrected,
-- split or removed; a partial refund; a reopened invoice) reverses the unpaid
-- settlement rows and earns them again. On an invoice paid in an earlier
-- month, the invoice's own lines and its staff commission came back in the
-- paid month. So did the "Future payout adjustment" of a row already paid out,
-- which copies that row's date. Its package and bundle commission came back
-- dated the day of the correction, in the next month's commission and payouts.
--
-- On 3 Oct 2026 an affiliate change on three paid September invoices did
-- exactly that, and six rows had to be re-dated to September by hand (audited
-- as commission_month_corrected).
--
-- THE RULE
--
-- Package and bundle commission is dated the day the invoice was paid in full:
-- invoices.paid_at, on the Singapore calendar, every time it is earned.
--   * The first earning does not change. paid_at is set in that transaction,
--     so its Singapore date is today's.
--   * Earning it again keeps the date it was first earned on, and the month.
--   * An invoice with no paid date keeps today's date, as before.
--
-- PACKAGES AND BUNDLES PAID IN PARTS (355-357)
--
-- Paid credit is released as each payment arrives (327, 356). The sale record
-- and its settlement commission are still written once, when the invoice is
-- paid in full. Part payments earn on the instalment layer (357):
-- sync_instalment_commissions writes earning_basis 'instalment' rows dated the
-- day each payment is registered. At full payment it closes them with one
-- negative row dated that day, and settlement writes the full amount.
--
-- So the right date for the settlement row is the day the invoice was paid in
-- full, the day of the instalment close.
--   * That is what the first earning has always written. Part payments count
--     in their own months, and the rest in the month the package was paid off.
--   * Dating it at the first payment, or at any release, would count the part
--     payments twice in their months and leave the paid-off month negative.
--   * Dating it at a later correction (the bug) moved the full amount into the
--     correction's month, while the close row stayed in the paid-off month.
--
-- An invoice that falls back to part-paid and is paid in full again gets a new
-- paid_at, and both layers move to that day together, as before. The
-- instalment layer's own dates (the day money arrives or leaves) are the rule
-- for part payments and are not changed.
--
-- WHY THE SINGAPORE DATE
--
-- sg_today(), which these functions wrote, is the Singapore date, and so is the
-- instalment close. earn_invoice_commission's paid_at::date is the UTC date,
-- because the database runs in UTC. For a payment recorded between 00:00 and
-- 07:59 in Singapore that is the day before, and on the 1st of a month the
-- month before. Reading paid_at in UTC here would move such a first earning
-- out of the month it has always landed in and away from its close row (357
-- notes the same split for invoice lines), and earning it again would move it
-- a month back. The Singapore date of paid_at is always the date the first
-- earning wrote.
--
-- WHAT THIS DOES
--
-- Replaces the two functions. Each reads the invoice's paid date once and
-- writes it on its tier 1 and tier 2 rows in place of public.sg_today().
-- Nothing else in them changes: basis, referrers, rates, skips and the
-- returned summary are the same.
--
-- NOT CHANGED
--
--   * Rows already written. On 3 Oct 2026, after the hand correction, every
--     package and bundle settlement row in production is dated on its
--     invoice's paid date, so there is nothing to repair.
--   * earn_invoice_commission, earn_staff_commission and
--     reearn_invoice_staff_commission still date by the UTC day of paid_at.
--     One production invoice so far was paid in that window (29 Sep, mid-month,
--     so the same month either way). Changing them is a separate decision.
--   * The instalment layer (sync_instalment_commissions).
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block), so
-- it is atomic however it is run. Nothing is installed unless both functions
-- pass their guard: md5(pg_get_functiondef) must be the production version
-- read on 3 Oct 2026 (BEFORE), or already this migration's version (AFTER),
-- which is left alone so a re-run changes nothing. Anything else refuses.
-- After installing, both functions must have the AFTER md5. CREATE OR REPLACE
-- keeps their owner and grants. Functions only; no data changes.
--
-- BEFORE (production, 3 Oct 2026, md5 of pg_get_functiondef):
--   earn_credit_package_commission(uuid)   397476974e7483a3c806205f6bc73bac
--   earn_premium_bundle_commission(uuid)   022f0204692b878904c490c4587f03d5
-- AFTER (for later guards):
--   earn_credit_package_commission(uuid)   13ce59fd892c027338a41de4113ae55d
--   earn_premium_bundle_commission(uuid)   b75ffbea70fd020e75d1ddf4f7b06ba1
--
-- Test: scripts/commissions/tests/package-commission-paid-date.sql.

set lock_timeout = '5s';

do $mig$
declare
  r record; v text; v_install text[] := '{}';
begin
  -- ── Guards: nothing below is installed unless both pass ─────────────────
  for r in select * from (values
    ('earn_credit_package_commission(uuid)', '397476974e7483a3c806205f6bc73bac', '13ce59fd892c027338a41de4113ae55d'),
    ('earn_premium_bundle_commission(uuid)', '022f0204692b878904c490c4587f03d5', 'b75ffbea70fd020e75d1ddf4f7b06ba1')) x(fn, before_md5, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '383: public.% is missing', r.fn; end if;
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v = r.after_md5 then
      raise notice '383: public.% already dates by the invoice''s paid date; left alone', r.fn;
    elsif v <> r.before_md5 then
      raise exception '383: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    else
      v_install := v_install || r.fn;
    end if;
  end loop;

  -- ── Credit packages ───────────────────────────────────────────────────────
  if 'earn_credit_package_commission(uuid)' = any(v_install) then
    execute $fn$
CREATE OR REPLACE FUNCTION public.earn_credit_package_commission(p_sale_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.credit_package_sales%rowtype;
  v_inv public.invoices%rowtype;
  v_t1 uuid; v_t2 uuid; v_base numeric;
  v_r1 numeric; v_r2 numeric; v_a1 numeric; v_a2 numeric;
  v_ptype text;
  v_paid_date date;
begin
  select * into s from public.credit_package_sales where id = p_sale_id;
  if not found then raise exception 'Package sale not found'; end if;

  -- Basis: the money actually received, never the credit or free reward.
  v_base := round(coalesce(s.external_paid,0), 2);
  v_base := public.invoice_package_retained_commission_basis('credit_package',s.id,v_base);
  if v_base <= 0 then
    return jsonb_build_object('skipped', true, 'reason', 'no external payment');
  end if;
  -- Commission is always recorded against an invoice, so a sale booked without
  -- one earns nothing until it is invoiced.
  if s.invoice_id is null then
    return jsonb_build_object('skipped', true, 'reason', 'no invoice');
  end if;

  if s.invoice_id is not null then
    select * into v_inv from public.invoices where id = s.invoice_id;
  end if;
  -- 383: dated the day the invoice was paid in full (Singapore), so earning it
  -- again later (a correction, a refund, a reopen) keeps it in that month.
  -- That is today when the invoice settles now; today too without a paid date.
  v_paid_date := coalesce((v_inv.paid_at at time zone 'Asia/Singapore')::date, public.sg_today());

  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return jsonb_build_object('skipped',true,'reason','Affiliate explicitly cleared'); end if;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    select c.referred_by into v_t1 from public.customers c where c.id = s.customer_id;
  end if;
  if v_t1 is null or v_t1 = s.customer_id then
    return jsonb_build_object('skipped', true, 'reason', 'no eligible referrer');
  end if;
  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;

  v_ptype := public.package_commission_classification();
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;

  v_a1 := round(v_base * v_r1 / 100.0, 2);
  if v_a1 > 0 then
    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      'earned', v_paid_date);
    if v_t2 is not null then
      v_a2 := round(v_a1 * v_r2 / 100.0, 2);
      if v_a2 > 0 then
        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          'earned', v_paid_date);
      end if;
    end if;
  end if;

  return jsonb_build_object('basis', v_base, 'tier1', v_a1, 'tier2', coalesce(v_a2,0),
    'tier1_rate', v_r1, 'tier2_rate', v_r2);
end $function$
$fn$;
  end if;

  -- ── Premium bundles ───────────────────────────────────────────────────────
  if 'earn_premium_bundle_commission(uuid)' = any(v_install) then
    execute $fn$
CREATE OR REPLACE FUNCTION public.earn_premium_bundle_commission(p_sale_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.premium_bundle_sales%rowtype;
  v_inv public.invoices%rowtype;
  v_t1 uuid; v_t2 uuid; v_base numeric; v_ptype text;
  v_r1 numeric; v_r2 numeric; v_a1 numeric; v_a2 numeric;
  v_paid_date date;
begin
  select * into s from public.premium_bundle_sales where id = p_sale_id;
  if not found then raise exception 'Bundle sale not found'; end if;

  -- Only external money after discount and FOC. Never bonus credit, free
  -- voucher value, or any later redemption.
  v_base := round(coalesce(s.external_paid,0), 2);
  v_base := public.invoice_package_retained_commission_basis('premium_bundle',s.id,v_base);
  if v_base <= 0 then return jsonb_build_object('skipped', true, 'reason', 'no external payment'); end if;
  if s.invoice_id is null then return jsonb_build_object('skipped', true, 'reason', 'no invoice'); end if;

  select * into v_inv from public.invoices where id = s.invoice_id;
  -- 383: dated the day the invoice was paid in full (Singapore), so earning it
  -- again later (a correction, a refund, a reopen) keeps it in that month.
  -- That is today when the invoice settles now; today too without a paid date.
  v_paid_date := coalesce((v_inv.paid_at at time zone 'Asia/Singapore')::date, public.sg_today());
  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return jsonb_build_object('skipped',true,'reason','Affiliate explicitly cleared'); end if;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    select c.referred_by into v_t1 from public.customers c where c.id = s.customer_id;
  end if;
  if v_t1 is null or v_t1 = s.customer_id then
    return jsonb_build_object('skipped', true, 'reason', 'no eligible referrer'); end if;
  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;

  v_ptype := public.package_commission_classification();
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;

  v_a1 := round(v_base * v_r1 / 100.0, 2);
  if v_a1 > 0 then
    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      'earned', v_paid_date);
    if v_t2 is not null then
      v_a2 := round(v_a1 * v_r2 / 100.0, 2);
      if v_a2 > 0 then
        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          'earned', v_paid_date);
      end if;
    end if;
  end if;

  return jsonb_build_object('basis', v_base, 'classification', v_ptype,
    'tier1_rate', v_r1, 'tier2_rate', v_r2, 'tier1', v_a1, 'tier2', coalesce(v_a2,0));
end $function$
$fn$;
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('earn_credit_package_commission(uuid)', '13ce59fd892c027338a41de4113ae55d'),
    ('earn_premium_bundle_commission(uuid)', 'b75ffbea70fd020e75d1ddf4f7b06ba1')) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      raise exception '383: public.% was installed with md5 %, not the tested %', r.fn, v, r.after_md5; end if;
  end loop;
end $mig$;
