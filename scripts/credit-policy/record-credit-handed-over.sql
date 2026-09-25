-- Record bundle credit that staff already handed over by hand (goes with 356).
--
-- WHY THIS EXISTS
--
-- Before 356, a part-paid premium bundle released no credit. On 23 Sep 2026
-- staff made up for it by hand, granting each customer an opening balance equal
-- to exactly what they had paid:
--
--   INV-2026-0292   received $1,963   opening balance $1,636 + $327 = $1,963 (all spent)
--   INV-2026-0293   received $2,280   opening balance $2,280            ($600 unspent)
--
-- Once 356 is live, the next payment on either invoice — and equally any
-- correction to it (lines, discount, even 'Served by') or any status change —
-- releases paid credit for everything received so far, handing that same money
-- over a SECOND time.
-- This records the hand-granted lots as the bundle line's already-released
-- credit, in the same table ordinary releases use (credit_package_progress_lots),
-- so every existing path counts them:
--
--   * the next payment releases only the NEW money;
--   * settlement grants the entitlement less what was released, so the total
--     comes out right;
--   * a later cancel or full refund takes back what is still unspent (0293's $600);
--   * moving the invoice to another customer carries them.
--
-- WHY NOT REVERSE THEM AND LET THE BUNDLE RE-GRANT
--
-- It would give the cleaner category — the bundle grants 'paid' credit, staff
-- granted 'legacy' — but INV-2026-0292's credit is already spent and cannot be
-- reversed. Linking works for both. The difference that remains: legacy credit
-- spends on anything, bundle credit on everything except other credit products.
-- On 0292 that is moot (spent); on 0293 it applies to the $600 still unspent.
--
-- The manual_adjustment lots on 0292 ($1,000 and $636) are NOT linked: a manager
-- removed them, so the customer never received them.
--
-- ORDER: right after 355 and 356 are applied, in the same sitting, before
-- anyone records a payment on, corrects, or changes the status of either
-- invoice. Owner sign-off required — it changes records on real customers. If
-- a release has already run, the dry run shows ok = false (released_now is not
-- 0) and the apply step refuses: stop and review the double credit by hand.

-- ── STEP 1: DRY RUN — changes nothing ───────────────────────────────────────
-- For each invoice: the bundle line, what was received, what is already
-- released, the opening-balance lots that would be linked, and whether they add
-- up to exactly what was received. Every row must say ok = true.
with target(invoice_no) as (values ('INV-2026-0292'), ('INV-2026-0293')),
line as (
  select i.invoice_no, i.id as invoice_id, i.customer_id, i.paid_amount, i.created_at,
         ii.id as invoice_item_id
    from target t
    join public.invoices i on i.invoice_no = t.invoice_no and i.deleted_at is null
    join public.invoice_items ii on ii.invoice_id = i.id and ii.line_kind = 'premium_bundle'
),
lots as (
  select l.*, cl.id as lot_id, cl.original_amount, cl.remaining_amount, cl.created_at as lot_created
    from line l
    join public.customer_credit_lots cl
      on cl.customer_id = l.customer_id
     and cl.source_type = 'manual_legacy'
     and cl.status <> 'reversed'
     and cl.created_at >= l.created_at
)
select l.invoice_no,
       l.paid_amount                                              as received,
       public.credit_package_released_paid_credit(l.invoice_item_id) as released_now,
       coalesce((select sum(original_amount) from lots x where x.invoice_no = l.invoice_no), 0) as to_link,
       (select string_agg('$'||original_amount||' (left $'||remaining_amount||')', ' + ' order by lot_created)
          from lots x where x.invoice_no = l.invoice_no)          as lots,
       public.credit_package_released_paid_credit(l.invoice_item_id) = 0
         and coalesce((select sum(original_amount) from lots x where x.invoice_no = l.invoice_no), 0) = l.paid_amount
                                                                  as ok
  from line l
 order by 1;

-- ── STEP 2: APPLY — only after every dry-run row says ok = true ─────────────
-- One transaction. It re-checks the same conditions and refuses if anything
-- moved since the dry run: a payment taken, a lot spent differently, or a
-- release already recorded. Uncomment to run.
--
-- begin;
-- do $apply$
-- declare r record; v_linked numeric;
-- begin
--   for r in
--     select i.invoice_no, i.id as invoice_id, i.customer_id, i.paid_amount, i.created_at,
--            ii.id as invoice_item_id
--       from public.invoices i
--       join public.invoice_items ii on ii.invoice_id = i.id and ii.line_kind = 'premium_bundle'
--      where i.invoice_no in ('INV-2026-0292','INV-2026-0293') and i.deleted_at is null
--      for update of i
--   loop
--     if public.credit_package_released_paid_credit(r.invoice_item_id) <> 0 then
--       raise exception '% already has released credit recorded; refusing to link twice', r.invoice_no; end if;
--
--     insert into public.credit_package_progress_lots (lot_id, invoice_item_id, invoice_id, released_amount)
--     select cl.id, r.invoice_item_id, r.invoice_id, cl.original_amount
--       from public.customer_credit_lots cl
--      where cl.customer_id = r.customer_id and cl.source_type = 'manual_legacy'
--        and cl.status <> 'reversed' and cl.created_at >= r.created_at;
--
--     v_linked := public.credit_package_released_paid_credit(r.invoice_item_id);
--     if v_linked <> r.paid_amount then
--       raise exception '% would record % as released but received %; refusing', r.invoice_no, v_linked, r.paid_amount; end if;
--
--     perform public.write_audit_ex('invoices', r.invoice_id, 'bundle_credit_handed_over_recorded', null,
--       jsonb_build_object('released', v_linked, 'reason',
--         'Opening balance granted by hand before 356 counted as this bundle''s released paid credit'),
--       'credit', 'Before 356 bundles released nothing on part payment',
--       (select store_id from public.invoices where id = r.invoice_id));
--     raise notice '% : recorded % as already released', r.invoice_no, v_linked;
--   end loop;
-- end $apply$;
-- commit;
