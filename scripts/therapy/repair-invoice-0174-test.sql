-- Clear what the refunded test sale INV-2026-0174 still left open (Q14 A,
-- the Owner, 9 Oct 2026; THERAPY-3).
--
-- PROPOSED, NOT RUN. It changes records on a real customer record: run it only
-- with the Owner's go-ahead (Q14 A gives it), after reading the dry run. It
-- prints document numbers, amounts and counts only.
--
-- WHEN: run STEP 1 and STEP 2 BEFORE the Therapy page of 422 is pushed. It
-- needs nothing from 422 (before or after it is fine). LEG-0000071 records no
-- sale and no voucher list, so 422's refund check cannot see that its sale
-- was refunded. Since 422 only an Owner or Manager may hand such a reward
-- over (the Owner, 9 Oct 2026), but until STEP 2 cancels it, they still
-- could hand its 20 vouchers over on screen.
--
-- WHY THIS EXISTS
--
--   INV-2026-0174 was a credit-package sale made as a test (reason "Testing")
--   and refunded on 3 Sep 2026 through the approval path used before the
--   guided Refund / Cancel. That path set the invoice to refunded and never
--   touched what the sale had issued. On 9 Oct 2026 the customer still held:
--     * Paid Credit of S$1,666.67 (lot 49b6c786…) and Bonus Credit of S$116.67
--       (lot 04e7a284…), both unspent, each with only its grant in the ledger
--       (the bonus lot was never linked on the sale);
--     * LEG-0000071, a reward of 20 vouchers from the same sale, unclaimed;
--     * and the sale's rewards were never marked resolved.
--   Its sister invoices INV-2026-0173 and INV-2026-0175 (unpaid, no payment)
--   were deleted on 3 Sep 2026. The Owner asked for them to be cancelled. A
--   deleted invoice no longer shows in the app, so it cannot be cancelled
--   there. This leaves them deleted (Owner to confirm) and only checks that
--   they are still deleted and unpaid (if either is not, it stops: cancel it
--   in the app with the guided Cancel).
--   OWNER TO CONFIRM: is leaving them deleted enough, or should STEP 2 also
--   cancel them? If they are to be cancelled, STEP 2 needs a guarded update
--   of each to 'cancelled', with an invoice_revisions row and write_audit_ex.
--   cancel_invoice_recorded cannot do it here: it needs a signed-in Owner or
--   Manager, which the SQL editor is not.
--
-- WHAT IT DOES (STEP 2, one transaction, re-checking everything first)
--
--   1. Each of the two lots is brought to 0 with a 'reverse' ledger entry, the
--      same writes reverse_credit_lot makes (that function asks for a signed-in
--      Owner or Manager, which the SQL editor is not), and an audit row.
--   2. LEG-0000071 is cancelled: its 20 vouchers withdrawn (revoked_qty), with
--      the date and the reason, and an audit row.
--   3. The sale's rewards are marked resolved, as resolve_invoice_credit_rewards
--      marks them, and an audit row is written.
--   Nothing else: no money (the refund was recorded on 3 Sep), no commission
--   (none was earned on this sale), no customer record.
--
-- STEP 3 is a read-only check for refunded, cancelled or deleted sales that
-- still hold package credit, rewards or therapy. Run it after STEP 2 (it
-- should list nothing for INV-2026-0174) and then each month before the stock
-- and credit review. It also lists an open voucher reward that records no
-- sale, from a credit package or bundle, when the customer has such a sale
-- that is closed (on 9 Oct 2026: LEG-0000071 alone). Check each one by hand.

-- ── STEP 1: DRY RUN — changes nothing ───────────────────────────────────────
-- Every row must say ok = true.
with inv as (
  select i.* from public.invoices i where i.invoice_no = 'INV-2026-0174'
), sale as (
  select s.* from public.credit_package_sales s join inv on inv.id = s.invoice_id
)
select 'invoice INV-2026-0174' as item, inv.status::text as state, null::numeric as amount,
       inv.status::text = 'refunded' and inv.deleted_at is null as ok
  from inv
union all
select 'sale rewards resolved', coalesce(sale.rewards_resolved_at::text, 'not resolved'), null,
       sale.rewards_resolved_at is null and (select count(*) from sale) = 1
  from sale
union all
select 'credit lot ' || left(l.id::text, 8) || ' (' || l.category || ')', l.status, l.remaining_amount,
       l.status = 'active' and l.remaining_amount = l.original_amount
       and l.remaining_amount = case l.category when 'paid' then 1666.67 when 'bonus' then 116.67 end
       and (select count(*) from public.customer_credit_ledger g where g.lot_id = l.id) = 1
       and exists (select 1 from public.customer_credit_ledger g where g.lot_id = l.id and g.entry_type = 'grant')
  from public.customer_credit_lots l, inv, sale
 where l.customer_id = inv.customer_id and l.source_type = 'credit_package'
   and l.source_record_id = sale.package_id
union all
select 'reward LEG-0000071', t.status, t.voucher_qty::numeric,
       t.status = 'pending_activation' and t.entitlement_kind = 'voucher' and t.voucher_qty = 20
       and coalesce(t.revoked_qty, 0) = 0 and t.earner_kind = 'credit_package'
       and t.qualified_value = sale.price_snapshot and t.store_id = inv.store_id
       and public.entitlement_claimed_qty(t.id) = 0
  from public.therapy_entitlements t, inv, sale
 where t.entitlement_no = 'LEG-0000071' and t.customer_id = inv.customer_id
union all
select 'sister ' || i.invoice_no, i.status::text || case when i.deleted_at is not null then ', deleted' else '' end, i.paid_amount,
       i.deleted_at is not null and i.status::text = 'unpaid' and i.paid_amount = 0
       and not exists (select 1 from public.invoice_payments p where p.invoice_id = i.id)
  from public.invoices i
 where i.invoice_no in ('INV-2026-0173', 'INV-2026-0175')
order by 1;
-- Expected on 9 Oct 2026: 7 rows, all ok (the invoice, the sale, two lots,
-- LEG-0000071, two sisters).

-- ── STEP 2: APPLY — only after every dry-run row says ok = true ──────────────
-- One transaction. It re-checks the same conditions and refuses if anything
-- moved since the dry run. Run a second time, it changes nothing and says so.
-- Uncomment to run.
--
-- begin;
-- do $apply$
-- declare
--   c_reason constant text := 'Test sale INV-2026-0174 refunded 3 Sep 2026: what it issued is withdrawn (Owner, 9 Oct 2026)';
--   i public.invoices%rowtype; s public.credit_package_sales%rowtype; t public.therapy_entitlements%rowtype;
--   l record; n int := 0; v_expected numeric;
-- begin
--   select * into i from public.invoices where invoice_no = 'INV-2026-0174' for update;
--   if not found or i.status::text <> 'refunded' or i.deleted_at is not null then
--     raise exception 'INV-2026-0174 is no longer a refunded invoice; refusing'; end if;
--   select * into s from public.credit_package_sales where invoice_id = i.id for update;
--   -- Run before: this repair marked the sale, so nothing changes now.
--   if found and s.rewards_resolution->>'repair' = 'refunded test sale (Q14)' then
--     if exists (select 1 from public.customer_credit_lots cl
--                 where cl.customer_id = i.customer_id and cl.source_type = 'credit_package'
--                   and cl.source_record_id = s.package_id and (cl.status <> 'reversed' or cl.remaining_amount <> 0))
--        or not exists (select 1 from public.therapy_entitlements te
--                        where te.entitlement_no = 'LEG-0000071' and te.status = 'cancelled') then
--       raise exception 'INV-2026-0174 was marked by this repair, but a lot or LEG-0000071 is open again; refusing'; end if;
--     raise notice 'INV-2026-0174 was already cleared by this repair; nothing changed';
--     return;
--   end if;
--   if not found or s.rewards_resolved_at is not null
--      or (select count(*) from public.credit_package_sales where invoice_id = i.id) <> 1 then
--     raise exception 'INV-2026-0174 no longer has one sale with unresolved rewards; refusing'; end if;
--   if exists (select 1 from public.invoices x where x.invoice_no in ('INV-2026-0173', 'INV-2026-0175')
--                and (x.deleted_at is null or x.status::text <> 'unpaid' or x.paid_amount <> 0
--                     or exists (select 1 from public.invoice_payments p where p.invoice_id = x.id)))
--      or (select count(*) from public.invoices x where x.invoice_no in ('INV-2026-0173', 'INV-2026-0175')) <> 2 then
--     raise exception 'INV-2026-0173 or INV-2026-0175 is no longer deleted and unpaid; cancel it in the app first; refusing'; end if;
--
--   -- 1. The two lots, as reverse_credit_lot writes it.
--   for l in select * from public.customer_credit_lots
--             where customer_id = i.customer_id and source_type = 'credit_package'
--               and source_record_id = s.package_id
--             order by category desc
--             for update
--   loop
--     v_expected := case l.category when 'paid' then 1666.67 when 'bonus' then 116.67 end;
--     if l.status <> 'active' or l.remaining_amount <> l.original_amount
--        or l.remaining_amount is distinct from v_expected
--        or (select count(*) from public.customer_credit_ledger g where g.lot_id = l.id) <> 1 then
--       raise exception 'A credit lot of INV-2026-0174 has moved since 9 Oct 2026; refusing'; end if;
--     insert into public.customer_credit_ledger (wallet_id, customer_id, entry_type, category, amount, lot_id,
--       source_type, source_record_id, store_id, effective_date, reference_no, reason, note, created_by, approved_by)
--     values (l.wallet_id, l.customer_id, 'reverse', l.category, l.remaining_amount, l.id,
--       'reversal', l.id, l.store_id, public.sg_today(), 'INV-2026-0174', c_reason, null, null, null);
--     update public.customer_credit_lots
--        set remaining_amount = 0, status = 'reversed', is_locked = true, updated_at = now()
--      where id = l.id;
--     perform public.write_audit_ex('customer_credit_lots', l.id, 'credit_reversed',
--       jsonb_build_object('remaining', l.remaining_amount), jsonb_build_object('reason', c_reason),
--       'credit', c_reason, l.store_id);
--     n := n + 1;
--   end loop;
--   if n <> 2 then raise exception 'Expected the paid and the bonus lot of INV-2026-0174, found %; refusing', n; end if;
--
--   -- 2. LEG-0000071.
--   select * into t from public.therapy_entitlements where entitlement_no = 'LEG-0000071' for update;
--   if not found or t.customer_id <> i.customer_id or t.status <> 'pending_activation'
--      or t.entitlement_kind <> 'voucher' or t.voucher_qty <> 20 or coalesce(t.revoked_qty, 0) <> 0
--      or t.earner_kind <> 'credit_package' or t.qualified_value <> s.price_snapshot
--      or public.entitlement_claimed_qty(t.id) <> 0 then
--     raise exception 'LEG-0000071 is no longer the unclaimed reward of INV-2026-0174; refusing'; end if;
--   update public.therapy_entitlements
--      set status = 'cancelled', revoked_qty = t.voucher_qty, revoked_at = now(), revoked_reason = c_reason
--    where id = t.id;
--   perform public.write_audit_ex('therapy_entitlements', t.id, 'reward_withdrawn_for_invoice_resolution',
--     jsonb_build_object('status', t.status, 'voucher_qty', t.voucher_qty, 'revoked_qty', t.revoked_qty),
--     jsonb_build_object('status', 'cancelled', 'revoked_qty', t.voucher_qty, 'invoice_no', 'INV-2026-0174', 'reason', c_reason),
--     'therapy', c_reason, t.store_id);
--
--   -- 3. The sale's rewards, as resolve_invoice_credit_rewards marks them.
--   update public.credit_package_sales
--      set rewards_resolved_at = now(), rewards_resolved_by = null,
--          rewards_resolution = jsonb_build_object('reason', c_reason, 'withdrawn', 1, 'retained', 0,
--            'voucher_units_returned', 0, 'request_id', null, 'repair', 'refunded test sale (Q14)')
--    where id = s.id;
--   perform public.write_audit_ex('credit_package_sales', s.id, 'qualification_rewards_resolved',
--     jsonb_build_object('rewards_resolved_at', null),
--     jsonb_build_object('invoice_no', 'INV-2026-0174', 'withdrawn', 'LEG-0000071', 'credit_reversed', 2),
--     'invoices', c_reason, s.store_id);
--   raise notice 'INV-2026-0174: 2 credit lots reversed, LEG-0000071 cancelled, rewards resolved; INV-2026-0173 and -0175 left deleted (not cancelled)';
-- end $apply$;
-- commit;

-- ── STEP 3: CHECK — read-only; run after STEP 2, then monthly ───────────────
-- A refunded, cancelled or deleted sale that still holds something usable.
-- Document numbers, amounts and counts only. Expected after STEP 2: no row for
-- INV-2026-0174; UTP-0000006 and UTP-0000012 until 417's repair closes them.
with closed as (
  select i.id, i.invoice_no, i.customer_id,
         case when i.deleted_at is not null then 'deleted' else i.status::text end as state
    from public.invoices i
   where i.deleted_at is not null or i.status::text in ('refunded', 'cancelled')
)
-- Package or bundle credit still spendable.
select c.invoice_no, c.state, 'credit lot (' || l.category || ')' as holds, l.remaining_amount as amount
  from closed c
  join public.credit_package_sales s on s.invoice_id = c.id
  join public.customer_credit_lots l on l.customer_id = s.customer_id and l.source_type = 'credit_package'
       and (l.id in (s.credit_lot_id, s.bonus_credit_lot_id) or l.source_record_id = s.package_id)
 where l.status = 'active' and l.remaining_amount > 0
union all
select c.invoice_no, c.state, 'credit lot (' || l.category || ')', l.remaining_amount
  from closed c
  join public.premium_bundle_sales b on b.invoice_id = c.id
  join public.customer_credit_lots l on l.id in (b.paid_credit_lot_id, b.bonus_credit_lot_id)
 where l.status = 'active' and l.remaining_amount > 0
union all
-- A credit-package sale whose rewards were never resolved.
select c.invoice_no, c.state, 'rewards not resolved', (coalesce(s.reward_voucher_qty, 0) + s.reward_units)::numeric
  from closed c join public.credit_package_sales s on s.invoice_id = c.id
 where s.rewards_resolved_at is null and (s.reward_units > 0 or coalesce(s.reward_voucher_qty, 0) > 0)
union all
-- A reward still owed on the sale.
select c.invoice_no, c.state, 'reward ' || t.entitlement_no,
       (coalesce(t.voucher_qty, 0) - public.entitlement_claimed_qty(t.id) - coalesce(t.revoked_qty, 0))::numeric
  from closed c join public.therapy_entitlements t on t.claim_source_invoice_id = c.id
 where t.status = 'pending_activation'
   and coalesce(t.voucher_qty, 0) - public.entitlement_claimed_qty(t.id) - coalesce(t.revoked_qty, 0) > 0
union all
-- A credit-package or bundle voucher reward that records no sale, for a
-- customer whose credit-package or bundle sale is closed. The reward may
-- belong to another sale of theirs: check it by hand.
select c.invoice_no, c.state, 'reward ' || t.entitlement_no || ' (no sale recorded; check it)',
       (coalesce(t.voucher_qty, 0) - public.entitlement_claimed_qty(t.id) - coalesce(t.revoked_qty, 0))::numeric
  from closed c
  join public.therapy_entitlements t
    on t.customer_id = c.customer_id and t.claim_source_invoice_id is null
   and t.earner_kind in ('credit_package', 'premium_bundle')
   and coalesce(t.entitlement_kind, 'unlimited') = 'voucher'
 where t.status = 'pending_activation'
   and coalesce(t.voucher_qty, 0) - public.entitlement_claimed_qty(t.id) - coalesce(t.revoked_qty, 0) > 0
   and (exists (select 1 from public.credit_package_sales s where s.invoice_id = c.id)
        or exists (select 1 from public.premium_bundle_sales b where b.invoice_id = c.id))
union all
-- A therapy package not started or not yet running.
select c.invoice_no, c.state, 'therapy ' || e.entitlement_no || ' (' || e.status || ')', null
  from closed c join public.purchased_therapy_entitlements e on e.invoice_id = c.id
 where e.status in ('pending_activation', 'scheduled')
order by 1, 3;
