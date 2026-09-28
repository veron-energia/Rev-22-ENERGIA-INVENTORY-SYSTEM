-- 366_therapy_report_for_managers_and_discounts_keep_the_applied_voucher.sql
--
-- WHAT WAS WRONG (Reports review, 28 Sep 2026)
--
-- 1. report_therapy() had no role check and no store filter. It is SECURITY
--    DEFINER and callable by every signed-in account (339 lists it as a client
--    function on the understanding that each one gates itself), so any login —
--    including every affiliate-portal login, which has no staff profile —
--    could read all purchased and legacy therapy with customers' names,
--    packages, stores, values and statuses. Simulated in production with an
--    affiliate login: all 119 rows. Staff could read every store's therapy.
--    Pricing, Discounts and FOC were scoped in 193; this one was missed.
-- 2. report_discounts() worked out the Voucher column by calling
--    voucher_discount_amount() again, a function built for the till: it raises
--    when the voucher is deleted, inactive, expired, not yet valid, or when the
--    amount is not above a fixed voucher's value. Retiring a voucher that an
--    invoice used would have made report_discounts fail for every period, and
--    with it the Pricing, Discounts, FOC and Sales Reconciliation tabs (they
--    load together). It also recalculated on the invoice subtotal, while the
--    till applies the voucher to what is left after line discounts.
--
-- WHAT THIS CHANGES
--
--   1. report_therapy returns a row only to an active Owner, Admin or Manager
--      (is_manager_or_above), and only for a store they may see
--      (user_has_store_access: Owners and Admins see every store, a Manager
--      the stores assigned to them). Anyone else gets no rows, as with the
--      store-scoped Pricing, Discounts and FOC reports. The Reports page is
--      its only caller and is already limited to those roles.
--   2. report_discounts reports the voucher discount the invoice was actually
--      given: the invoice's discount total less its manual, line and Save
--      Earth discounts — the parts the till adds the voucher to (create_invoice
--      and update_invoice_internal: discount_total = manual + line discounts +
--      voucher). It never goes below zero. On 28 Sep 2026 this equals the old
--      column on all 94 invoices the report lists (2 with a voucher).
--
-- NOT CHANGED: every other column and row of both reports, their signatures
-- and grants, and voucher_discount_amount itself (the till still uses it).
--
-- SAFETY: each function is guarded by the md5 of its production version
-- (28 Sep 2026) and by anchors that must occur once; a function already
-- carrying "366:" is left alone.

set lock_timeout = '5s';

-- ── 1. report_therapy: Owners, Admins and Managers, for their stores ────────
do $mig$
declare d text; n int; v_md5 text; a1 text; a2 text;
begin
  d := pg_get_functiondef('public.report_therapy()'::regprocedure);
  if position('366:' in d) > 0 then raise notice '366: report_therapy already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'bd559feb0e98bf5e7eee44de6ff017c7' then
    raise exception '366: report_therapy is not the version this was tested against (md5 %)', v_md5; end if;
  a1 := $a$  left join public.stores s on s.id = e.store_id
  union all
$a$;
  a2 := $a$  left join public.stores s on s.id = le.store_id
  order by 7 desc nulls last;
$a$;
  n := (length(d) - length(replace(d, a1, ''))) / length(a1);
  if n <> 1 then raise exception '366: report_therapy purchased anchor found % times', n; end if;
  n := (length(d) - length(replace(d, a2, ''))) / length(a2);
  if n <> 1 then raise exception '366: report_therapy legacy anchor found % times', n; end if;
  d := replace(d, a1, $r$  left join public.stores s on s.id = e.store_id
  -- 366: only an Owner, Admin or Manager, and only for stores they may see.
  where public.is_manager_or_above() and public.user_has_store_access(e.store_id)
  union all
$r$);
  d := replace(d, a2, $r$  left join public.stores s on s.id = le.store_id
  -- 366: only an Owner, Admin or Manager, and only for stores they may see.
  where public.is_manager_or_above() and public.user_has_store_access(le.store_id)
  order by 7 desc nulls last;
$r$);
  execute d;
end $mig$;

-- ── 2. report_discounts: the voucher discount the invoice was given ─────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.report_discounts()'::regprocedure);
  if position('366:' in d) > 0 then raise notice '366: report_discounts already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '6e13018a75aa3b991eb7c3e1fc7b910a' then
    raise exception '366: report_discounts is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$    case when i.discount_voucher_id is not null then public.voucher_discount_amount(i.discount_voucher_id, i.subtotal) else 0 end,
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '366: report_discounts voucher anchor found % times', n; end if;
  execute replace(d, a, $r$    -- 366: what the invoice was actually given, read from the invoice itself:
    -- its discount total less the manual, Save Earth and line discounts. Not
    -- recalculated through voucher_discount_amount, which refuses a voucher
    -- that has since been retired and would fail the whole report.
    case when i.discount_voucher_id is not null then
      greatest(round(coalesce(i.discount_total,0) - coalesce(i.manual_discount,0)
        - case when i.save_earth_applied then coalesce(i.save_earth_amount,0) else 0 end
        - coalesce((select sum(coalesce(ii.line_discount,0)) from public.invoice_items ii where ii.invoice_id = i.id), 0), 2), 0)
    else 0 end,
$r$);
end $mig$;

notify pgrst, 'reload schema';
