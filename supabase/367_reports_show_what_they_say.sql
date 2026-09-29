-- 367_reports_show_what_they_say.sql
--
-- WHAT WAS WRONG (Reports review, 28-29 Sep 2026)
--
--  1. Sales Reconciliation's TikTok line summed Total settlement over every
--     confirmed row: TikTok income after fees AND after ad spend, with each ad
--     payment counted as a transaction (all time on 29 Sep 2026: 58
--     "transactions", S$3,225.63, where the 35 sales came to S$4,920.96). It was
--     dated by the order's creation, cast to a UTC date, so every row landed a
--     day early and on the order date rather than the day TikTok settled it.
--  2. The FOC cards summed every line of an invoice with any FOC, while the
--     table beneath lists only the FOC lines: Normal S$25,723 and Charged
--     S$17,957 over lines that total S$8,054 and S$288.
--  3. Pricing named 273 of 456 lines "item": every promotion, therapy, rental
--     and special-product line, although each has a name.
--  4. Every TikTok ad payment was a "reconciliation warning" (⚠ Off), because
--     the check ignores the Adjustment column, where TikTok puts the whole
--     amount of an ad payment. Staging still stores new ones that way.
--  5. The Therapy report showed "—" for a legacy entitlement's activation and
--     expiry dates, which exist since 72.
--  6. Exchange Invoices, Transfer receipts and Sources took a period as UTC
--     dates (00:00-08:00 Singapore time fell on the day before).
--  7. Sales by Service Staff's "wallet credit not counted" kept a purchase paid
--     with wallet credit in full after part of it was refunded to the wallet.
--  8. The Affiliate report counted deleted and merged-away customers as
--     referrals (58 where the live referred customers number 55).
--  9. Discrepancy Lines dropped manual (non-inventory) lines, so a receipt could
--     say "Open" with nothing listed under it.
-- 10. Transfer receipts named one source when the dispatch drew from several,
--     and added manual items (their own units of measure) to the stock units.
--
-- WHAT THIS CHANGES (as the owner decided, 29 Sep 2026)
--
--   1. report_sales_reconciliation, TikTok line: TikTok SALES only, the TikTok
--      tab's Settlement: revenue less TikTok's fees, on sale rows (sales and
--      refunds of sales), dated by the Singapore date TikTok settled the row.
--      Transactions are those rows. Ad payments, other expenses and balance
--      movements are not sales. Rows deselected at import are left out, as
--      everywhere else on the TikTok tab.
--   2. report_foc_summary: Normal, FOC, Charged and units are summed over the
--      FOC lines only, so the cards equal the FOC lines table for the same
--      filter. The invoice counts still count whole invoices.
--   3. report_pricing names a line by the first of: the name it was sold under,
--      product, promotion, special product, therapy service, plan, voucher;
--      "item" only when none exists.
--   4. A platform finance row with no order to match (match status "no match
--      needed": an ad payment, a subscription) reconciles when Settlement =
--      Revenue + Fees + Adjustment, within S$0.01. One internal rule,
--      tiktok_settlement_row_reconciled, is read by every report that shows or
--      counts reconciliation (the settlement list and so its summary, by store,
--      the exceptions list and the Dashboard's settlement mismatches), and
--      staging stores new rows by it. Stored rows are NOT rewritten: the reports
--      read the rule, so the 23 ad payments imported so far stop showing as
--      warnings without touching the data.
--   5. report_therapy returns a legacy entitlement's activation and expiry dates
--      (366's Owner/Admin/Manager and store filter unchanged).
--   6. A period on report_exchange_invoices, report_transfer_receipts and
--      report_customer_sources is compared with the Singapore date of the
--      exchange, the receipt and the survey submission.
--   7. report_sales_by_service_staff: wallet credit not counted is net of the
--      wallet credit refunds put back, on the refund's Singapore date, in the
--      same store and access filters. Nothing else in the report changes.
--   8. affiliate_directory (report_affiliates' referrals): direct referrals and
--      downline count live customers only, as referrer_list does.
--   9. Transfer discrepancies list manual lines, named "<item> (manual)".
--  10. report_transfer_receipts: the source lists every location the dispatch
--      drew stock from when there were several ("A, B"); units count catalogue
--      stock only.
--
-- NOT CHANGED: every other column, row and filter of these functions, their
-- signatures and grants; tiktok_settlement_reconciled; the stored rows of
-- tiktok_settlement_rows and voucher_redemptions; report_tiktok_settlement_daily
-- and report_tiktok_settlement_by_store's period (already Singapore settled
-- dates).
--
-- SAFETY: each patched function is guarded by the md5 of its production version
-- (29 Sep 2026) and by anchors that must occur exactly once; a function already
-- carrying "367:" is left alone. The new helper is internal: no client role can
-- call it.

set lock_timeout = '5s';

-- ── 0. one rule for a TikTok row's reconciliation ──────────────────────────
create or replace function public.tiktok_settlement_row_reconciled(
  p_stored boolean, p_txn_class text, p_match_status text,
  p_settlement numeric, p_revenue numeric, p_fees numeric, p_adjustment numeric)
returns boolean language sql immutable set search_path to 'public' as $f$
  -- 367: a platform finance row with no order to match (an ad payment, a
  -- subscription) carries its whole amount in Adjustment, with no revenue or
  -- fees (TIKTOK_SETTLEMENT_MAPPING.md §4), so it reconciles when Settlement =
  -- Revenue + Fees + Adjustment. A finance row with none of those three filled
  -- in (a bank transfer with only a Settlement cell) has nothing to reconcile
  -- against and keeps the verdict it was stored with, as does every other row.
  select case
    when p_txn_class = 'finance' and p_match_status = 'no_match_needed' then
      case when p_settlement is null then null
           when p_revenue is null and p_fees is null and p_adjustment is null then p_stored
           else abs(p_settlement - (coalesce(p_revenue, 0) + coalesce(p_fees, 0) + coalesce(p_adjustment, 0))) <= 0.01 end
    else p_stored
  end
$f$;
revoke all on function public.tiktok_settlement_row_reconciled(boolean, text, text, numeric, numeric, numeric, numeric)
  from public, anon, authenticated;
grant execute on function public.tiktok_settlement_row_reconciled(boolean, text, text, numeric, numeric, numeric, numeric)
  to service_role;

-- ── 1. report_sales_reconciliation: TikTok sales, by settled date ──────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.report_sales_reconciliation(uuid,date,date)'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: report_sales_reconciliation already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '3c952d399acae622c4b80497a5ab9a70' then
    raise exception '367: report_sales_reconciliation is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$ select 'tiktok_settlement',count(*),coalesce(sum(r.settlement_amount),0) from public.tiktok_settlement_rows r
 where r.confirmed and r.is_current and public.user_has_store_access(r.store_id)
 and (p_store_id is null or r.store_id=p_store_id)
 and (p_from is null or coalesce(r.order_created_time,r.settled_time)::date>=p_from)
 and (p_to is null or coalesce(r.order_created_time,r.settled_time)::date<=p_to)
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '367: report_sales_reconciliation TikTok anchor found % times', n; end if;
  execute replace(d, a, $r$ -- 367: TikTok SALES, as the TikTok tab's Settlement: revenue less TikTok's
 -- fees, on sale rows (sales and their refunds) only. Ad payments, other
 -- expenses and balance movements are not sales. Dated by the Singapore date
 -- TikTok settled the row.
 select 'tiktok_settlement',count(*),coalesce(sum(r.revenue_amount),0)+coalesce(sum(r.fee_amount),0) from public.tiktok_settlement_rows r
 where r.confirmed and r.is_current and not r.excluded and public.user_has_store_access(r.store_id)
 and public.tiktok_finance_category(r.transaction_type,r.adjustment_amount) in ('sale','sale_refund')
 and (p_store_id is null or r.store_id=p_store_id)
 and (p_from is null or (r.settled_time at time zone 'Asia/Singapore')::date>=p_from)
 and (p_to is null or (r.settled_time at time zone 'Asia/Singapore')::date<=p_to)
$r$);
end $mig$;

-- ── 2. report_foc_summary: the cards total the FOC lines ───────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.report_foc_summary(date,date,uuid)'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: report_foc_summary already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '642eeb8738073eb9cbd1c209ef35acd0' then
    raise exception '367: report_foc_summary is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$           'foc_value', coalesce(sum(ii.foc_amount),0),
           'charged_value', coalesce(sum(ii.line_total),0),
           'normal_value', coalesce(sum(ii.foc_amount + ii.line_total),0),
           'foc_units', coalesce(sum(ii.foc_quantity),0))
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '367: report_foc_summary headline anchor found % times', n; end if;
  execute replace(d, a, $r$           -- 367: values over the FOC lines only, as the FOC lines table lists
           -- them; the invoice counts above still count whole invoices.
           'foc_value', coalesce(sum(ii.foc_amount) filter (where ii.foc_quantity > 0),0),
           'charged_value', coalesce(sum(ii.line_total) filter (where ii.foc_quantity > 0),0),
           'normal_value', coalesce(sum(ii.foc_amount + ii.line_total) filter (where ii.foc_quantity > 0),0),
           'foc_units', coalesce(sum(ii.foc_quantity) filter (where ii.foc_quantity > 0),0))
$r$);
end $mig$;

-- ── 3. report_pricing: every line is named ─────────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a1 text; a2 text;
begin
  d := pg_get_functiondef('public.report_pricing()'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: report_pricing already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '6a157227810bab434f2608f13e119fc1' then
    raise exception '367: report_pricing is not the version this was tested against (md5 %)', v_md5; end if;
  a1 := $a$    coalesce(p.name, ii.plan_name_snapshot, v.name, 'item'),
$a$;
  a2 := $a$  left join public.vouchers v on v.id = ii.voucher_id
$a$;
  n := (length(d) - length(replace(d, a1, ''))) / length(a1);
  if n <> 1 then raise exception '367: report_pricing name anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a2, ''))) / length(a2);
  if n <> 1 then raise exception '367: report_pricing join anchor found % times', n; end if;
  d := replace(d, a1, $r$    -- 367: the name the line was sold under, then the catalogue's; "item"
    -- only when nothing names it.
    coalesce(nullif(btrim(ii.item_name_snapshot), ''), nullif(btrim(p.name), ''), nullif(btrim(pr.name), ''),
             nullif(btrim(sp.name), ''), nullif(btrim(ii.therapy_service_name_snapshot), ''),
             nullif(btrim(ii.plan_name_snapshot), ''), nullif(btrim(v.name), ''), 'item'),
$r$);
  d := replace(d, a2, a2 || $r$  left join public.promotions pr on pr.id = ii.promotion_id
  left join public.special_products sp on sp.id = ii.special_product_id
$r$);
  execute d;
end $mig$;

-- ── 4. an ad payment is not a reconciliation warning ───────────────────────
-- Staging: new rows are stored by the rule.
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.stage_tiktok_settlement(uuid,text,text,jsonb)'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: stage_tiktok_settlement already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '8eccdb1395a42e224cacfe07281b7577' then
    raise exception '367: stage_tiktok_settlement is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$      public.tiktok_settlement_reconciled(v_settle, v_rev, v_fees));
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '367: stage_tiktok_settlement reconciled anchor found % times', n; end if;
  execute replace(d, a, $r$      -- 367: a platform finance row (an ad payment) reconciles on Settlement =
      -- Revenue + Fees + Adjustment; see tiktok_settlement_row_reconciled.
      public.tiktok_settlement_row_reconciled(
        public.tiktok_settlement_reconciled(v_settle, v_rev, v_fees), v_class,
        case when v_match is not null then 'matched'
             when v_class = 'finance' then 'no_match_needed'
             else 'pending' end,
        v_settle, v_rev, v_fees, v_adj));
$r$);
end $mig$;

-- The settlement list (and so report_tiktok_settlement_summary, which counts
-- its rows), by store, the exceptions list and the Dashboard read the rule.
do $mig$
declare f record; d text; n int; v_md5 text;
begin
  for f in select * from (values
      ('public.report_tiktok_settlement(uuid,date,date)', '97c15fcfda5f61280cf6e2c80e77e17a',
       $a$         r.reconciled, r.version_no
$a$,
       $r$         -- 367: an ad payment is not a reconciliation warning.
         public.tiktok_settlement_row_reconciled(r.reconciled, r.txn_class, r.match_status,
           r.settlement_amount, r.revenue_amount, r.fee_amount, r.adjustment_amount), r.version_no
$r$),
      ('public.report_tiktok_settlement_by_store(date,date)', '52dbdd3ab57ea313f19aa64584f77cfd',
       $a$         count(*) filter (where reconciled is false)
$a$,
       $r$         -- 367: an ad payment is not a reconciliation warning.
         count(*) filter (where public.tiktok_settlement_row_reconciled(reconciled, txn_class, match_status,
           settlement_amount, revenue_amount, fee_amount, adjustment_amount) is false)
$r$),
      ('public.dashboard_alerts_summary()', 'ed77ac8f628c2efdbe64781e2b8d497f',
       $a$                                 where r.confirmed and r.is_current and r.reconciled is false),
$a$,
       $r$                                 -- 367: an ad payment is not a settlement mismatch.
                                 where r.confirmed and r.is_current
                                   and public.tiktok_settlement_row_reconciled(r.reconciled, r.txn_class, r.match_status,
                                         r.settlement_amount, r.revenue_amount, r.fee_amount, r.adjustment_amount) is false),
$r$)) v(sig, want, anchor, repl)
  loop
    d := pg_get_functiondef(f.sig::regprocedure);
    if position('367:' in d) > 0 then raise notice '367: % already patched; left alone.', f.sig; continue; end if;
    v_md5 := md5(d);
    if v_md5 <> f.want then raise exception '367: % is not the version this was tested against (md5 %)', f.sig, v_md5; end if;
    n := (length(d) - length(replace(d, f.anchor, ''))) / length(f.anchor);
    if n <> 1 then raise exception '367: % reconciled anchor found % times', f.sig, n; end if;
    execute replace(d, f.anchor, f.repl);
  end loop;
end $mig$;

-- ── 4b. the exceptions list: which rows, and the gap it shows ──────────────
do $mig$
declare d text; n int; v_md5 text; a1 text; a2 text;
begin
  d := pg_get_functiondef('public.report_tiktok_recon_exceptions(uuid)'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: report_tiktok_recon_exceptions already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '29e5ad3661db584b66a7853b38e81753' then
    raise exception '367: report_tiktok_recon_exceptions is not the version this was tested against (md5 %)', v_md5; end if;
  a1 := $a$         'settlement ' || r.settlement_amount::text || ' vs revenue+fees '
           || (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0))::text,
         r.settlement_amount - (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0))
$a$;
  a2 := $a$   where r.confirmed and r.is_current and r.reconciled is false
$a$;
  n := (length(d) - length(replace(d, a1, ''))) / length(a1);
  if n <> 1 then raise exception '367: report_tiktok_recon_exceptions detail anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a2, ''))) / length(a2);
  if n <> 1 then raise exception '367: report_tiktok_recon_exceptions filter anchor found % times', n; end if;
  d := replace(d, a1, $r$         -- 367: an ad payment is measured against Revenue + Fees + Adjustment,
         -- the same rule that flags it, so the gap shown is the gap it has.
         case when r.txn_class = 'finance' and r.match_status = 'no_match_needed'
           then 'settlement ' || r.settlement_amount::text || ' vs revenue+fees+adjustment '
             || (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0) + coalesce(r.adjustment_amount,0))::text
           else 'settlement ' || r.settlement_amount::text || ' vs revenue+fees '
             || (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0))::text end,
         r.settlement_amount - (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0)
           + case when r.txn_class = 'finance' and r.match_status = 'no_match_needed'
               then coalesce(r.adjustment_amount,0) else 0 end)
$r$);
  d := replace(d, a2, $r$   -- 367: an ad payment reconciles on its Adjustment; it is not an exception.
   where r.confirmed and r.is_current
     and public.tiktok_settlement_row_reconciled(r.reconciled, r.txn_class, r.match_status,
           r.settlement_amount, r.revenue_amount, r.fee_amount, r.adjustment_amount) is false
$r$);
  execute d;
end $mig$;

-- ── 5. report_therapy: legacy activation and expiry dates ──────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.report_therapy()'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: report_therapy already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '4260a58dddd740c2997fb77182ba9c50' then
    raise exception '367: report_therapy is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$    le.activation_deadline, null, null, le.status, true
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '367: report_therapy legacy anchor found % times', n; end if;
  execute replace(d, a, $r$    -- 367: a legacy entitlement's own activation and expiry dates (72).
    le.activation_deadline, le.activation_date, le.expiry_date, le.status, true
$r$);
end $mig$;

-- ── 6. periods are Singapore dates: exchanges, surveys ─────────────────────
do $mig$
declare f record; d text; n int; v_md5 text;
begin
  for f in select * from (values
      ('public.report_exchange_invoices(uuid,date,date)', '4d7d33d2bc18ff688a572ed6234d8bf2',
       $a$     and (p_from is null or e.created_at::date >= p_from)
     and (p_to is null or e.created_at::date <= p_to)
$a$,
       $r$     -- 367: the Singapore date of the exchange.
     and (p_from is null or (e.created_at at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to is null or (e.created_at at time zone 'Asia/Singapore')::date <= p_to)
$r$),
      ('public.report_customer_sources(date,date)', '8dbd9923127208c07a83edac7bfa2376',
       $a$             and (p_from is null or s.submitted_at::date >= p_from)
             and (p_to is null or s.submitted_at::date <= p_to))
$a$,
       $r$             -- 367: the Singapore date the survey was submitted.
             and (p_from is null or (s.submitted_at at time zone 'Asia/Singapore')::date >= p_from)
             and (p_to is null or (s.submitted_at at time zone 'Asia/Singapore')::date <= p_to))
$r$)) v(sig, want, anchor, repl)
  loop
    d := pg_get_functiondef(f.sig::regprocedure);
    if position('367:' in d) > 0 then raise notice '367: % already patched; left alone.', f.sig; continue; end if;
    v_md5 := md5(d);
    if v_md5 <> f.want then raise exception '367: % is not the version this was tested against (md5 %)', f.sig, v_md5; end if;
    n := (length(d) - length(replace(d, f.anchor, ''))) / length(f.anchor);
    if n <> 1 then raise exception '367: % period anchor found % times', f.sig, n; end if;
    execute replace(d, f.anchor, f.repl);
  end loop;
end $mig$;

-- ── 6 + 10. report_transfer_receipts: every source, stock units, SG dates ──
do $mig$
declare d text; n int; v_md5 text; a_src text; a_units text; a_date text;
begin
  d := pg_get_functiondef('public.report_transfer_receipts(date,date)'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: report_transfer_receipts already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '0c82eac2435af948c217c1a3bc8e0196' then
    raise exception '367: report_transfer_receipts is not the version this was tested against (md5 %)', v_md5; end if;
  a_src := $a$         coalesce(sw.name, ss.name), coalesce(dw.name, ds.name),
$a$;
  a_units := $a$         (select coalesce(sum(l.received_quantity),0) from public.transfer_request_lines l where l.transfer_request_id = t.id),
$a$;
  a_date := $a$     and (p_from is null or t.received_at::date >= p_from)
     and (p_to is null or t.received_at::date <= p_to)
$a$;
  n := (length(d) - length(replace(d, a_src, ''))) / length(a_src);
  if n <> 1 then raise exception '367: report_transfer_receipts source anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a_units, ''))) / length(a_units);
  if n <> 1 then raise exception '367: report_transfer_receipts units anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a_date, ''))) / length(a_date);
  if n <> 1 then raise exception '367: report_transfer_receipts period anchor found % times', n; end if;
  d := replace(d, a_src, $r$         -- 367: every location the dispatch drew stock from, when there were
         -- several; otherwise the source on the request.
         coalesce((select string_agg(coalesce(w.name, st.name), ', ' order by coalesce(w.name, st.name))
                     from (select distinct ls.source_type, ls.source_id
                             from public.transfer_request_lines l
                             join public.transfer_line_sources ls on ls.line_id = l.id
                            where l.transfer_request_id = t.id) x
                     left join public.warehouses w on x.source_type = 'warehouse' and w.id = x.source_id
                     left join public.stores st on x.source_type = 'store' and st.id = x.source_id
                   having count(*) > 1),
                  coalesce(sw.name, ss.name)),
         coalesce(dw.name, ds.name),
$r$);
  d := replace(d, a_units, $r$         -- 367: catalogue stock only; manual items carry their own units of measure.
         (select coalesce(sum(l.received_quantity),0) from public.transfer_request_lines l where l.transfer_request_id = t.id and l.line_kind = 'product'),
$r$);
  d := replace(d, a_date, $r$     -- 367: the Singapore date of the receipt.
     and (p_from is null or (t.received_at at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to is null or (t.received_at at time zone 'Asia/Singapore')::date <= p_to)
$r$);
  execute d;
end $mig$;

-- ── 7. report_sales_by_service_staff: wallet credit net of refunds ─────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.report_sales_by_service_staff(date,date,uuid)'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: report_sales_by_service_staff already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'cec67a101beccca106d28bc7e08e10f7' then
    raise exception '367: report_sales_by_service_staff is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$         and (p_to   is null or public.payment_sales_date(pay.effective_at, pay.created_at) <= p_to)),
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '367: report_sales_by_service_staff wallet anchor found % times', n; end if;
  execute replace(d, a, $r$         and (p_to   is null or public.payment_sales_date(pay.effective_at, pay.created_at) <= p_to))
      -- 367: less the wallet credit a refund put back in the wallet, on the
      -- refund's date (the part of a refund the sales ledger leaves out).
      - (select coalesce(sum(rf.credit_returned), 0)
           from public.invoice_refunds rf
           join public.invoices i on i.id = rf.invoice_id
          where rf.payment_id is not null
            and i.deleted_at is null and public.invoice_counts_as_sale(i.status::text)
            and public.user_has_store_access(i.store_id)
            and (p_store_id is null or i.store_id = p_store_id)
            and (p_from is null or (rf.created_at at time zone 'Asia/Singapore')::date >= p_from)
            and (p_to   is null or (rf.created_at at time zone 'Asia/Singapore')::date <= p_to)),
$r$);
end $mig$;

-- ── 8. affiliate_directory: live referred customers only ───────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.affiliate_directory()'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: affiliate_directory already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '194e8789cc4ebcfb715cb90f1c4b01a6' then
    raise exception '367: affiliate_directory is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$    (select count(*)::int from public.customers r where r.referred_by = c.id),
    (select count(*)::int from public.customers r1
      where r1.referred_by = c.id
         or r1.referred_by in (select id from public.customers r2 where r2.referred_by = c.id)),
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '367: affiliate_directory referrals anchor found % times', n; end if;
  execute replace(d, a, $r$    -- 367: live referred customers only, as referrer_list counts them; a deleted
    -- or merged-away customer is no longer a referral.
    (select count(*)::int from public.customers r where r.referred_by = c.id and r.deleted_at is null),
    (select count(*)::int from public.customers r1
      where r1.deleted_at is null
        and (r1.referred_by = c.id
             or r1.referred_by in (select id from public.customers r2 where r2.referred_by = c.id and r2.deleted_at is null))),
$r$);
end $mig$;

-- ── 9. transfer discrepancies: manual lines are listed ─────────────────────
do $mig$
declare d text; n int; v_md5 text; a1 text; a2 text;
begin
  d := pg_get_functiondef('public.stock_private_report_transfer_discrepancies()'::regprocedure);
  if position('367:' in d) > 0 then raise notice '367: stock_private_report_transfer_discrepancies already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '4a43d9fb0a868b6c104bf2b904e8d191' then
    raise exception '367: stock_private_report_transfer_discrepancies is not the version this was tested against (md5 %)', v_md5; end if;
  a1 := $a$    l.product_id, p.name,
$a$;
  a2 := $a$  join public.products p on p.id = l.product_id
$a$;
  n := (length(d) - length(replace(d, a1, ''))) / length(a1);
  if n <> 1 then raise exception '367: stock_private_report_transfer_discrepancies name anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a2, ''))) / length(a2);
  if n <> 1 then raise exception '367: stock_private_report_transfer_discrepancies join anchor found % times', n; end if;
  d := replace(d, a1, $r$    -- 367: a manual (non-inventory) line is listed, named as one.
    l.product_id, coalesce(p.name, coalesce(l.manual_item_name, 'Manual item') || ' (manual)'),
$r$);
  d := replace(d, a2, $r$  left join public.products p on p.id = l.product_id
$r$);
  execute d;
end $mig$;

notify pgrst, 'reload schema';
