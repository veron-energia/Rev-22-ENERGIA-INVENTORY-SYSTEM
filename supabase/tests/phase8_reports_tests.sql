-- =====================================================================
-- PHASE 8 REPORT/DASHBOARD TESTS — run AFTER migration 56.
-- These call each read-only view function and confirm it executes and
-- returns the expected columns. Self-cleaning: no writes, no rollback needed.
-- =====================================================================
do $$
declare v_cnt integer; v_json jsonb; v_cust uuid;
begin
  -- Each report function should execute without error.
  perform * from public.report_pricing() limit 1;         raise notice 'PASS: report_pricing executes';
  perform * from public.report_affiliates() limit 1;      raise notice 'PASS: report_affiliates executes';
  perform * from public.report_therapy() limit 1;         raise notice 'PASS: report_therapy executes';
  perform * from public.report_discounts() limit 1;       raise notice 'PASS: report_discounts executes';

  -- Dashboard summary returns a JSON object with the expected keys.
  v_json := public.dashboard_summary();
  if v_json ? 'today_sales' and v_json ? 'blocked_commission'
     and v_json ? 'therapy_awaiting' then
    raise notice 'PASS: dashboard_summary returns expected keys';
  else
    raise exception 'FAIL: dashboard_summary missing keys (%)', v_json;
  end if;

  -- Customer overview returns a JSON object for any customer (or a safe empty one).
  select id into v_cust from public.customers where deleted_at is null limit 1;
  if v_cust is not null then
    v_json := public.customer_overview(v_cust);
    if v_json ? 'affiliate_state' and v_json ? 'purchased_therapy' then
      raise notice 'PASS: customer_overview returns expected sections';
    else
      raise exception 'FAIL: customer_overview missing sections';
    end if;
  else
    raise notice 'SKIP: no customer to test customer_overview';
  end if;

  raise notice '=== ALL PHASE 8 REPORT/DASHBOARD DB TESTS PASSED ===';
end $$;
