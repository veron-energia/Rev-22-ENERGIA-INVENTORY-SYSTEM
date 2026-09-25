-- 354_every_invoice_line_has_a_name.sql
--
-- WHAT WAS WRONG
--
-- Some names did not show on invoices, on screen or in print (the PDF and the
-- WhatsApp/email copy share print's name function). On production, 30 invoices
-- had at least one blank item name:
--
--   * THERAPY lines printed a dash. The print name function had no therapy
--     branch and fell through to an empty product lookup. (14 lines, 9 invoices)
--   * RENTAL and SPECIAL-PRODUCT lines showed '—' on screen AND in print; no
--     name function handled special_product_id at all. (6 lines)
--   * A voucher or product that was later SOFT-DELETED went blank, because the
--     page only loads active, non-deleted catalogue items. (5 lines)
--   * A child promotion CHOSEN from a promotion's choice group showed '—' on
--     screen. (10 selections)
--   * The refund and cancel dialogs labelled those lines by their KIND —
--     "therapy", "rental" — instead of their name. (20 lines)
--
-- The root cause is that three separately written name functions on the page
-- each cover a different subset of line kinds, and all of them look names up in
-- lists that exclude anything inactive or deleted. Only credit packages, premium
-- bundles and on-screen therapy used a snapshot of the name taken at sale time.
--
-- WHAT THIS DOES
--
-- 1. Every invoice line now remembers the name it was sold under
--    (item_name_snapshot), captured by a trigger when the line is written.
--    A trigger rather than ten edited insert paths: there are ten places that
--    insert invoice lines, and a trigger cannot be forgotten by the eleventh.
--    It does nothing on an update that leaves the line's item unchanged, so a
--    line keeps its original name through corrections and credit stamping.
--
-- 2. invoice_display_names() resolves every name an invoice can show on the
--    server, ignoring whether the record is still active or deleted. The page
--    uses it as the single source for screen, print and PDF.
--
-- 3. The refund/cancel dialogs and the stock-history label prefer the snapshot.
--
-- NOT IN THIS MIGRATION
--
-- Filling item_name_snapshot on the lines that already exist is a separate,
-- dry-run-first step: scripts/invoices/backfill-item-names.sql. Existing
-- invoices display correctly without it, because invoice_display_names falls
-- back to the catalogue name; the backfill only freezes today's names so a
-- later rename cannot change what an old invoice says.
--
-- SAFETY
--
-- The only other trigger on invoice_items, capture_invoice_stock_components,
-- returns immediately on an update that changes neither the item nor the
-- quantity — verified before this was written — so writing a name never
-- touches stock. No function here declares a variable that a query alias could
-- collide with (plpgsql.variable_conflict is 'error' in this database).

-- Plain SQL: applies through the Supabase migration tool or the SQL editor as one
-- transaction. From psql, run with -v ON_ERROR_STOP=1.
set lock_timeout = '5s';

-- ── 1. the line remembers its name ──────────────────────────────────────────
alter table public.invoice_items add column if not exists item_name_snapshot text;

-- The catalogue name for a line, whatever state the record is in now: an
-- inactive or soft-deleted record keeps its name. Snapshots already on the line
-- (therapy, packages, bundles) win.
create or replace function public.invoice_item_catalogue_name(it public.invoice_items)
returns text
language sql
stable
security definer
set search_path = public
as $f$
  select nullif(btrim(case it.line_kind::text
    when 'product'         then (select p.name  from public.products p          where p.id  = it.product_id)
    when 'voucher'         then (select v.name  from public.vouchers v          where v.id  = it.voucher_id)
    when 'promotion'       then (select pr.name from public.promotions pr       where pr.id = it.promotion_id)
    when 'special_product' then (select sp.name from public.special_products sp where sp.id = it.special_product_id)
    when 'rental'          then (select sp.name from public.special_products sp where sp.id = it.special_product_id)
    -- A therapy line is either a session or an unlimited package. Editing a
    -- session into a package leaves the old session's name snapshot behind, so
    -- the id that is set decides which name is read.
    when 'therapy'         then case when it.therapy_package_id is not null
                                  then coalesce(nullif(btrim(it.plan_name_snapshot), ''),
                                                (select tp.name from public.unlimited_therapy_packages tp where tp.id = it.therapy_package_id),
                                                nullif(btrim(it.therapy_service_name_snapshot), ''))
                                  else coalesce(nullif(btrim(it.therapy_service_name_snapshot), ''),
                                                (select ts.name from public.therapy_services ts where ts.id = it.therapy_service_id),
                                                nullif(btrim(it.plan_name_snapshot), '')) end
    when 'credit_package'  then coalesce(nullif(btrim(it.plan_name_snapshot), ''),
                                         (select cp.name from public.credit_packages cp where cp.id = it.credit_package_id))
    when 'premium_bundle'  then coalesce(nullif(btrim(it.plan_name_snapshot), ''),
                                         (select pb.name from public.premium_bundles pb where pb.id = it.premium_bundle_id))
  end), '')
$f$;
revoke all on function public.invoice_item_catalogue_name(public.invoice_items) from public, anon, authenticated;
grant execute on function public.invoice_item_catalogue_name(public.invoice_items) to service_role;

create or replace function public.trg_invoice_item_name_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $f$
begin
  if tg_op = 'UPDATE'
     and (new.line_kind, new.product_id, new.voucher_id, new.promotion_id, new.special_product_id,
          new.therapy_service_id, new.therapy_package_id, new.credit_package_id, new.premium_bundle_id)
     is not distinct from
         (old.line_kind, old.product_id, old.voucher_id, old.promotion_id, old.special_product_id,
          old.therapy_service_id, old.therapy_package_id, old.credit_package_id, old.premium_bundle_id) then
    return new;                      -- same item: keep the name it was sold under
  end if;
  if tg_op = 'INSERT' and nullif(btrim(new.item_name_snapshot), '') is not null then
    return new;                      -- a caller that supplies the name keeps it
  end if;
  new.item_name_snapshot := public.invoice_item_catalogue_name(new);
  return new;
end
$f$;
revoke all on function public.trg_invoice_item_name_snapshot() from public, anon, authenticated;
grant execute on function public.trg_invoice_item_name_snapshot() to service_role;

drop trigger if exists invoice_item_name_snapshot on public.invoice_items;
create trigger invoice_item_name_snapshot
  before insert or update on public.invoice_items
  for each row execute function public.trg_invoice_item_name_snapshot();

-- ── 2. every name on an invoice, resolved on the server ─────────────────────
-- Neither RLS (which hides soft-deleted vouchers, promotions and customers from
-- staff) nor the page's active-only catalogue lists can blank a name here.
create or replace function public.invoice_display_names(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $f$
declare v_inv public.invoices%rowtype;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('found', false); end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'Invoice not accessible'; end if;
  return jsonb_build_object(
    'found', true,
    'customer_name', (select coalesce(nullif(btrim(public.join_person_name(c.first_name, c.last_name)), ''),
                                      nullif(btrim(c.full_name), ''))
                        from public.customers c where c.id = v_inv.customer_id),
    'store_name', (select s.name from public.stores s where s.id = v_inv.store_id),
    'created_by_name', (select nullif(btrim(pf.full_name), '') from public.profiles pf where pf.id = v_inv.created_by),
    'service_staff', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', ss.staff_id,
                 'name', coalesce(nullif(btrim(pf.full_name), ''), 'Former staff member'),
                 'work_phone', pf.work_phone))
          from public.invoice_service_staff ss
          left join public.profiles pf on pf.id = ss.staff_id
         where ss.invoice_id = v_inv.id), '[]'::jsonb),
    'lines', coalesce((
        select jsonb_object_agg(li.id::text,
                 coalesce(nullif(btrim(li.item_name_snapshot), ''), public.invoice_item_catalogue_name(li)))
          from public.invoice_items li where li.invoice_id = v_inv.id), '{}'::jsonb),
    -- Every catalogue id this invoice can print, named whatever its state now.
    'names', coalesce((select jsonb_object_agg(k.id::text, k.nm) from (
        select pr.id, pr.name nm from public.products pr where pr.id in (
          select pi.product_id from public.promotion_items pi
            join public.invoice_items li on li.promotion_id = pi.promotion_id where li.invoice_id = v_inv.id
          union select sel.product_id from public.invoice_promotion_selections sel
            join public.invoice_items li on li.id = sel.invoice_item_id where li.invoice_id = v_inv.id)
        union all
        select vo.id, vo.name from public.vouchers vo where vo.id in (
          select pi.voucher_id from public.promotion_items pi
            join public.invoice_items li on li.promotion_id = pi.promotion_id where li.invoice_id = v_inv.id
          union select sel.voucher_id from public.invoice_promotion_selections sel
            join public.invoice_items li on li.id = sel.invoice_item_id where li.invoice_id = v_inv.id
          union select li.line_voucher_id from public.invoice_items li where li.invoice_id = v_inv.id)
        union all
        select pm.id, pm.name from public.promotions pm where pm.id in (
          select pi.child_promotion_id from public.promotion_items pi
            join public.invoice_items li on li.promotion_id = pi.promotion_id where li.invoice_id = v_inv.id
          union select sel.child_promotion_id from public.invoice_promotion_selections sel
            join public.invoice_items li on li.id = sel.invoice_item_id where li.invoice_id = v_inv.id)
        union all
        select tp.id, tp.name from public.unlimited_therapy_packages tp where tp.id in (
          select pi.therapy_package_id from public.promotion_items pi
            join public.invoice_items li on li.promotion_id = pi.promotion_id where li.invoice_id = v_inv.id
          union select sel.therapy_package_id from public.invoice_promotion_selections sel
            join public.invoice_items li on li.id = sel.invoice_item_id where li.invoice_id = v_inv.id)
        union all
        select cp.id, cp.name from public.credit_packages cp where cp.id in (
          select pi.credit_package_id from public.promotion_items pi
            join public.invoice_items li on li.promotion_id = pi.promotion_id where li.invoice_id = v_inv.id
          union select sel.credit_package_id from public.invoice_promotion_selections sel
            join public.invoice_items li on li.id = sel.invoice_item_id where li.invoice_id = v_inv.id)
        union all
        select mt.id, mt.name from public.payment_methods mt where mt.id in (
          select ip.payment_method_id from public.invoice_payments ip where ip.invoice_id = v_inv.id)
      ) k where nullif(btrim(k.nm), '') is not null), '{}'::jsonb));
end
$f$;
revoke all on function public.invoice_display_names(uuid) from public, anon;
grant execute on function public.invoice_display_names(uuid) to authenticated, service_role;

-- ── 3. the dialogs and the stock label prefer the snapshot ──────────────────
-- ...and then the catalogue name, so lines written before 354 (no snapshot)
-- show their therapy, rental or special-product name instead of their kind,
-- whether or not scripts/invoices/backfill-item-names.sql has been run.
do $mig$
declare v_def text; v_anchor text; v_fn text;
begin
  -- a) Refund and cancel dialogs.
  v_fn := 'invoice_refund_options_before_sessions';
  v_anchor := 'coalesce(p.name,pr.name,v.name,it.plan_name_snapshot,it.line_kind::text)';
  select pg_get_functiondef(p.oid) into v_def from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = v_fn;
  if v_def is null then raise exception '354: % not found', v_fn; end if;
  if position('invoice_item_catalogue_name(it)' in v_def) > 0 then
    raise notice '354: % already prefers the snapshot; left alone.', v_fn;
  else
    if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
      raise exception '354: % anchor not found exactly once', v_fn; end if;
    execute replace(v_def, v_anchor,
      'coalesce(nullif(btrim(it.item_name_snapshot),''''),public.invoice_item_catalogue_name(it),p.name,pr.name,v.name,it.plan_name_snapshot,it.line_kind::text)');
  end if;

  -- b) The historical stock-review label.
  v_fn := 'invoice_line_label';
  v_anchor := 'coalesce(p.name,v.name,pr.name,it.line_kind::text)';
  select pg_get_functiondef(p.oid) into v_def from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = v_fn;
  if v_def is null then raise exception '354: % not found', v_fn; end if;
  if position('invoice_item_catalogue_name(it)' in v_def) > 0 then
    raise notice '354: % already prefers the snapshot; left alone.', v_fn;
  else
    if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
      raise exception '354: % anchor not found exactly once', v_fn; end if;
    execute replace(v_def, v_anchor,
      'coalesce(nullif(btrim(it.item_name_snapshot),''''),public.invoice_item_catalogue_name(it),p.name,v.name,pr.name,it.line_kind::text)');
  end if;
end $mig$;

-- ── 4. guards ────────────────────────────────────────────────────────────────
do $mig$
begin
  if not exists (select 1 from pg_trigger where tgname = 'invoice_item_name_snapshot'
                   and tgrelid = 'public.invoice_items'::regclass) then
    raise exception '354: the name trigger is not installed'; end if;

  -- 339's rule: nothing is an endpoint by default.
  if has_function_privilege('anon', 'public.invoice_display_names(uuid)', 'execute') then
    raise exception '354: invoice_display_names is reachable without signing in'; end if;
  if not has_function_privilege('authenticated', 'public.invoice_display_names(uuid)', 'execute') then
    raise exception '354: staff cannot call invoice_display_names'; end if;
  if has_function_privilege('authenticated', 'public.invoice_item_catalogue_name(public.invoice_items)', 'execute')
  or has_function_privilege('anon',          'public.invoice_item_catalogue_name(public.invoice_items)', 'execute')
  or has_function_privilege('authenticated', 'public.trg_invoice_item_name_snapshot()', 'execute')
  or has_function_privilege('anon',          'public.trg_invoice_item_name_snapshot()', 'execute') then
    raise exception '354: an internal name helper is reachable from the client'; end if;

  raise notice '354 applied: every invoice line has a name, on screen and in print.';
end $mig$;

notify pgrst, 'reload schema';
