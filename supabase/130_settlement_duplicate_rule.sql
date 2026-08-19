-- =====================================================================
-- ENERGIA — A SETTLEMENT FILE MAY LIST THE SAME ORDER TWICE
--
-- stage_tiktok_settlement() rejected any row whose Order/adjustment ID had
-- already appeared in the same file:
--
--     v_dup := v_status is null and exists (
--       select 1 from public.tiktok_settlement_rows
--        where batch_id = v_batch and order_id = v_oaid);
--     if v_dup then v_status := 'Duplicate Row'; end if;
--
-- That assumed one settlement line per order, which TikTok does not guarantee.
-- A single order can settle across two lines — an order payment and a later
-- adjustment, or two instalments of the same order — and the second was thrown
-- away as a duplicate. Real money went unrecorded.
--
-- A row is now treated as a duplicate only when it repeats the SAME ORDER, THE
-- SAME TRANSACTION TYPE, THE SAME RELATED ORDER **and** THE SAME AMOUNT. That
-- still catches a file genuinely imported twice, or a row pasted twice by
-- accident, while letting two distinct settlement lines for one order through.
--
-- Additive and idempotent. Run AFTER 129.
-- =====================================================================

set check_function_bodies = off;

do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'stage_tiktok_settlement';
  if v_def is null then raise exception 'stage_tiktok_settlement not found'; end if;
  if position('same type, related order AND amount' in v_def) > 0 then
    raise notice 'settlement duplicate detection already allows legitimate repeats'; return;
  end if;

  v_new := replace(v_def,
    '    -- Duplicate inside THIS file (store + order/adjustment id): keep first.
    v_dup := v_status is null and exists (select 1 from public.tiktok_settlement_rows
              where batch_id = v_batch and order_id = v_oaid);',
    '    -- Duplicate inside THIS file. An order id ALONE is not enough: TikTok
    -- can settle one order across two lines (an order payment plus a later
    -- adjustment, or two instalments), and rejecting the second lost real money.
    -- A row counts as a duplicate only when it repeats the same order with the
    -- same type, related order AND amount.
    v_dup := v_status is null and exists (select 1 from public.tiktok_settlement_rows r
              where r.batch_id = v_batch
                and r.order_id = v_oaid
                and coalesce(r.transaction_type, '''') = coalesce(v_type, '''')
                and r.related_order_id is not distinct from v_related
                and coalesce(r.settlement_amount, 0) = coalesce(v_settle, 0));');

  if position('same type, related order AND amount' in v_new) = 0 then
    raise exception 'Could not widen the settlement duplicate check';
  end if;
  execute v_new;
  raise notice 'a settlement file may now list the same order on two distinct lines';
end $patch$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- NON-ORDER FINANCIAL TRANSACTIONS MUST NOT BE TREATED AS CUSTOMER ORDERS.
--
-- tiktok_txn_class() fell through to 'order' for anything it did not recognise
-- as a refund, return or adjustment. So "GMV payment for TikTok Ads" — an
-- advertising settlement with a transaction id, not an order id — was classed
-- as an order and matched against tiktok_order_state by that id.
--
-- Those ids are 19 digits and never match a real order, so nothing false has
-- been recorded. But the intent was wrong, and a coincidental collision would
-- attach an advertising charge to a customer's order.
--
-- A 'finance' class is added for them. They are still imported and still count
-- towards settlement reporting; they simply do not attempt an order match.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_txn_class(p_type text)
returns text language sql immutable as $function$
  select case
    when lower(coalesce(p_type,'')) like '%adjust%' then 'adjustment'
    when lower(coalesce(p_type,'')) like '%refund%'
      or lower(coalesce(p_type,'')) like '%return%' then 'refund'
    -- Platform-level money movements: advertising, subscriptions, penalties,
    -- deposits, loans and payouts. Real settlement lines, but not customer sales.
    when lower(coalesce(p_type,'')) like '%tiktok ads%'
      or lower(coalesce(p_type,'')) like '%gmv payment%'
      or lower(coalesce(p_type,'')) like '%advertis%'
      or lower(coalesce(p_type,'')) like '%subscription%'
      or lower(coalesce(p_type,'')) like '%penalt%'
      or lower(coalesce(p_type,'')) like '%deposit%'
      or lower(coalesce(p_type,'')) like '%loan%'
      or lower(coalesce(p_type,'')) like '%payout%'
      or lower(coalesce(p_type,'')) like '%transfer%' then 'finance'
    else 'order'
  end
$function$;

-- The matcher must not look up an order for a finance row.
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'tiktok_settlement_match';
  if v_def is null then raise exception 'tiktok_settlement_match not found'; end if;
  if position('''finance''' in v_def) > 0 then
    raise notice 'the matcher already skips finance rows'; return;
  end if;

  v_new := replace(v_def,
    '  select case' || chr(10) ||
    '    when p_class = ''order'' then',
    '  select case' || chr(10) ||
    '    -- A platform money movement has no customer order to match.' || chr(10) ||
    '    when p_class = ''finance'' then null::text' || chr(10) ||
    '    when p_class = ''order'' then');

  if position('''finance''' in v_new) = 0 then
    raise exception 'Could not make the matcher skip finance rows';
  end if;
  execute v_new;
  raise notice 'the matcher now leaves platform finance rows unmatched';
end $patch$;

notify pgrst, 'reload schema';
