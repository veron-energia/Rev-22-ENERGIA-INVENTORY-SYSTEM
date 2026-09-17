begin;
-- =====================================================================
-- CREDIT RELEASED AS IT IS PAID FOR MUST LOOK LIKE CREDIT FROM ITS PACKAGE
--
-- 327 released paid credit progressively and stamped each lot with
-- source_type 'credit_package_progress' and source_record_id = the invoice
-- LINE, so that invoice_credit_lot_ids — and through it refunds, reassignment
-- and the benefit review — could find the lot without a sale record.
--
-- That broke spending. 242's credit_lot_policy recognises exactly two package
-- sources, 'credit_package' and 'premium_bundle'; anything else is
-- needs_review, and credit_lot_line_allowed refuses a lot it cannot place. And
-- 309 resolves a package's own spending rules through source_record_id, which
-- it expects to be the PACKAGE, not a line. A customer who had paid S$3,000
-- toward a package therefore held S$3,000 that could buy nothing:
-- "Only 0 of the requested 521.00 could be funded by eligible credit".
--
-- A lot cannot say both things in one column. So a released lot now carries
-- the same provenance as the full issuance — source_type 'credit_package',
-- source_record_id the package — and the tie back to its invoice line lives in
-- credit_package_progress_lots, which invoice_credit_lot_ids now seeds from.
-- The three 327 functions read that table instead of the invented source.
--
-- A posted lot cannot be re-keyed: credit_lot_immutable freezes source_type,
-- source_record_id, the amounts and the dates, and says to post a reversing
-- entry instead. So repair_credit_package_progress_lots() does what a person
-- would: it links the old lot so its release still counts toward the line,
-- reverses its unspent remainder through the ledger exactly as
-- reverse_credit_lot does, and grants that remainder again as a lot that
-- carries the package — same restrictions, same effective date, so it keeps
-- its place in the first-in-first-out queue. Spent credit stays spent on the
-- old lot. The old lot, its ledger row and the new grant are all left as
-- written, and an audit entry names the replacement.
--
-- Additive, replaceable, idempotent. Supersedes the three functions in 327.
-- =====================================================================

create table if not exists public.credit_package_progress_lots (
  lot_id          uuid primary key references public.customer_credit_lots(id) on delete cascade,
  invoice_item_id uuid not null references public.invoice_items(id) on delete cascade,
  invoice_id      uuid not null references public.invoices(id) on delete cascade,
  -- What this row adds to the line's released total. A fresh release adds its
  -- amount; a lot that merely replaces a reversed one adds nothing, because the
  -- money it carries was already counted when the original was released.
  released_amount numeric(12,2) not null default 0,
  replaces_lot_id uuid references public.customer_credit_lots(id),
  created_at      timestamptz not null default now()
);
-- The first cut of this migration created the table without these two.
alter table public.credit_package_progress_lots
  add column if not exists released_amount numeric(12,2) not null default 0;
alter table public.credit_package_progress_lots
  add column if not exists replaces_lot_id uuid references public.customer_credit_lots(id);
create index if not exists credit_package_progress_lots_item_idx
  on public.credit_package_progress_lots(invoice_item_id);
create index if not exists credit_package_progress_lots_invoice_idx
  on public.credit_package_progress_lots(invoice_id);
comment on table public.credit_package_progress_lots is
 'Which invoice line a progressively released paid-credit lot belongs to. The lot itself carries the package as its source, so the spending rules recognise it; this is the way back to the invoice.';

-- ---------------------------------------------------------------------
-- Released so far for a line: through the link, not through a source name.
-- ---------------------------------------------------------------------
-- Released so far is a fact about the line, not about which lot currently
-- holds the money: a replaced lot's release still counts, or the next payment
-- would release it a second time.
create or replace function public.credit_package_released_paid_credit(p_invoice_item_id uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(p.released_amount), 0)
    from public.credit_package_progress_lots p
   where p.invoice_item_id = p_invoice_item_id;
$$;

-- ---------------------------------------------------------------------
-- Release what the money justifies. Same body as 327 except the grant now
-- carries the package as its source and records the line in the link table.
-- ---------------------------------------------------------------------
create or replace function public.release_credit_package_paid_credit(p_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_it record; pk public.credit_packages%rowtype;
  v_entitled numeric; v_target numeric; v_already numeric; v_delta numeric;
  v_restrict jsonb; v_vouchers uuid[]; v_lot uuid; v_out jsonb := '[]'::jsonb;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('skipped', true, 'reason', 'no invoice'); end if;
  if v_inv.status in ('cancelled','refunded') then
    return jsonb_build_object('skipped', true, 'reason', 'invoice ' || v_inv.status); end if;
  if v_inv.customer_id is null then
    return jsonb_build_object('skipped', true, 'reason', 'no customer'); end if;

  for v_it in
    select * from public.invoice_items
     where invoice_id = p_invoice_id
       and line_kind = 'credit_package'
       -- Once the full issuance has run the line is settled; both branches of
       -- trg_create_therapy_on_paid fire on the final payment.
       and credit_issued_at is null
       -- Split packages keep full-payment issuance.
       and credit_split_allocation_id is null
       and not exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = invoice_items.id)
     order by id
     for update
  loop
    select * into pk from public.credit_packages where id = v_it.credit_package_id;
    if not found then continue; end if;

    v_entitled := coalesce(v_it.credit_paid_snapshot, pk.paid_credit_amount, 0);
    if v_entitled <= 0 then continue; end if;
    v_target  := least(public.credit_package_money_toward_line(v_it.id), v_entitled);
    v_already := public.credit_package_released_paid_credit(v_it.id);
    v_delta   := round(v_target - v_already, 2);
    if v_delta <= 0 then continue; end if;

    -- The same restrictions the full issuer snapshots.
    select coalesce(array_agg(voucher_id), '{}') into v_vouchers
      from public.credit_package_vouchers where package_id = pk.id;
    v_restrict := jsonb_build_object('allowed_purposes', public.credit_package_purposes(pk.id),
                                     'source', 'credit_package');
    if array_length(v_vouchers, 1) is not null and not pk.allow_voucher then
      v_restrict := v_restrict || jsonb_build_object(
        'allowed_voucher_ids', (select jsonb_agg(v::text) from unnest(v_vouchers) v));
    end if;

    -- Provenance identical to the full issuance: 242 places it as
    -- package_paid, and 309 finds the package's own rules through it.
    v_lot := public.grant_customer_credit(
      v_inv.customer_id, 'paid', v_delta, 'credit_package', pk.id, v_inv.store_id,
      public.sg_today(), null,
      'Credit package (paid so far): ' || pk.name, null, null, auth.uid(), v_restrict);

    insert into public.credit_package_progress_lots (lot_id, invoice_item_id, invoice_id, released_amount)
    values (v_lot, v_it.id, p_invoice_id, v_delta);

    v_out := v_out || jsonb_build_object(
      'invoice_item_id', v_it.id, 'lot_id', v_lot, 'released', v_delta,
      'released_total', v_already + v_delta, 'entitled', v_entitled);
  end loop;

  return jsonb_build_object('released', v_out);
end $$;

-- ---------------------------------------------------------------------
-- Closing an invoice: same behaviour as 327, found through the link.
-- ---------------------------------------------------------------------
create or replace function public.writeoff_released_credit_on_close(
  p_invoice_id uuid, p_reason text, p_event text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_lot record; v_reclaimed numeric := 0; v_written_off numeric := 0; v_store uuid;
begin
  select store_id into v_store from public.invoices where id = p_invoice_id;

  for v_lot in
    select cl.* from public.credit_package_progress_lots p
      join public.customer_credit_lots cl on cl.id = p.lot_id
     where p.invoice_id = p_invoice_id
       and cl.status <> 'reversed'
     order by cl.id
     for update of cl
  loop
    if v_lot.remaining_amount > 0 then
      insert into public.customer_credit_ledger(
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, reason, created_by, approved_by)
      values (v_lot.wallet_id, v_lot.customer_id, 'adjust_decrease', v_lot.category,
        v_lot.remaining_amount, v_lot.id, 'invoice_' || p_event || '_released_credit',
        p_invoice_id, v_lot.store_id, p_reason, auth.uid(), auth.uid());
      v_reclaimed := v_reclaimed + v_lot.remaining_amount;
    end if;
    v_written_off := v_written_off + (v_lot.original_amount - v_lot.remaining_amount);
    update public.customer_credit_lots
       set remaining_amount = 0, status = 'reversed', is_locked = true, updated_at = now()
     where id = v_lot.id;
  end loop;

  if v_reclaimed > 0 or v_written_off > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'released_credit_' || p_event, null,
      jsonb_build_object('reclaimed', v_reclaimed, 'written_off', v_written_off, 'reason', p_reason),
      'credit', p_reason, v_store);
  end if;
  return jsonb_build_object('reclaimed', v_reclaimed, 'written_off', v_written_off);
end $$;

-- ---------------------------------------------------------------------
-- Replace every lot 327 wrote under the invented source. Idempotent: a lot
-- already linked is skipped. Callable again if one is ever missed.
-- ---------------------------------------------------------------------
create or replace function public.repair_credit_package_progress_lots()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r record; pk public.credit_packages%rowtype; v_new uuid; v_rem numeric;
  n int := 0; n_regranted int := 0; v_amount numeric := 0; v_moved numeric := 0;
begin
  for r in
    select l.*, it.id as invoice_item_id, it.invoice_id, it.credit_package_id
      from public.customer_credit_lots l
      join public.invoice_items it on it.id = l.source_record_id
     where l.source_type = 'credit_package_progress'
       and not exists (select 1 from public.credit_package_progress_lots p where p.lot_id = l.id)
     order by l.created_at
     for update of l
  loop
    select * into pk from public.credit_packages where id = r.credit_package_id;
    if not found then continue; end if;

    -- The old lot keeps its release on the record for the line, whatever
    -- happens to the money it held.
    insert into public.credit_package_progress_lots (lot_id, invoice_item_id, invoice_id, released_amount)
    values (r.id, r.invoice_item_id, r.invoice_id, r.original_amount);
    n := n + 1; v_amount := v_amount + r.original_amount;

    v_new := null; v_rem := 0;
    if r.status = 'active' and r.remaining_amount > 0 then
      v_rem := r.remaining_amount;

      -- Reverse the unspent remainder, exactly as reverse_credit_lot does.
      insert into public.customer_credit_ledger (
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, effective_date,
        reason, created_by, approved_by)
      values (r.wallet_id, r.customer_id, 'reverse', r.category, v_rem, r.id,
        'credit_lot_provenance_repair', r.id, r.store_id, public.sg_today(),
        'Replaced by a lot that carries its package (328)', auth.uid(), auth.uid());
      update public.customer_credit_lots
         set remaining_amount = 0, status = 'reversed', is_locked = true, updated_at = now()
       where id = r.id;

      -- Grant it again with the package as its source. Same restrictions and
      -- the same effective date, so it spends exactly as before and in the
      -- same order among the customer's other lots.
      v_new := public.grant_customer_credit(
        r.customer_id, r.category, v_rem, 'credit_package', pk.id, r.store_id,
        r.effective_date, r.reference_no,
        'Credit package (paid so far): ' || pk.name,
        'Replaces lot ' || r.id || ', which carried the wrong source (328)',
        r.original_purchase_date, auth.uid(), r.usage_restrictions);
      insert into public.credit_package_progress_lots
        (lot_id, invoice_item_id, invoice_id, released_amount, replaces_lot_id)
      values (v_new, r.invoice_item_id, r.invoice_id, 0, r.id);
      n_regranted := n_regranted + 1; v_moved := v_moved + v_rem;
    end if;

    perform public.write_audit_ex('customer_credit_lots', r.id, 'credit_lot_provenance_repaired',
      jsonb_build_object('source_type', 'credit_package_progress', 'source_record_id', r.invoice_item_id,
                         'remaining', r.remaining_amount),
      jsonb_build_object('replacement_lot_id', v_new, 'regranted', v_rem,
                         'source_type', 'credit_package', 'source_record_id', pk.id,
                         'invoice_item_id', r.invoice_item_id, 'invoice_id', r.invoice_id),
      'credit', 'Released credit re-issued under its package so the spending rules recognise it (328)',
      r.store_id);
  end loop;
  return jsonb_build_object('linked', n, 'released_on_record', v_amount,
                            'regranted', n_regranted, 'regranted_amount', v_moved);
end $$;

revoke all on function public.repair_credit_package_progress_lots() from public;
-- Owner-run repair; not for the application role.

-- ---------------------------------------------------------------------
-- invoice_credit_lot_ids: refunds, reassignment and the benefit review all
-- find an invoice's credit through it. Seed it from the link table too, since
-- source_record_id no longer points at the line.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.invoice_credit_lot_ids(uuid)'::regprocedure) into f;
  if position('credit_package_progress_lots' in f) = 0 then
    f := replace(f,
'  ), walked as (',
'    union all
    -- Paid credit released as the invoice was paid down (327/328). The lot
    -- carries its package as source, so this link is how it is found.
    select p.lot_id, ''credit_package_progress_lots.lot_id''
      from public.credit_package_progress_lots p
     where p.invoice_id = p_invoice_id
  ), walked as (');
    if position('credit_package_progress_lots' in f) = 0 then
      raise exception 'invoice_credit_lot_ids does not match what 328 expects — align it by hand'; end if;
    execute f;
  end if;
end $do$;

-- Repair what 327 already wrote, wherever this runs.
do $do$
declare r jsonb;
begin
  r := public.repair_credit_package_progress_lots();
  raise notice '328: linked % old lot(s) (% released on record); re-granted % of them, % unspent',
    r->>'linked', r->>'released_on_record', r->>'regranted', r->>'regranted_amount';
end $do$;

commit;
