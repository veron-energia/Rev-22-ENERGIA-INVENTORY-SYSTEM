-- =====================================================================
-- ENERGIA — NAME THE PROMOTION IN STOCK HISTORY
--
-- Products inside a promotion DO come off the shelf and DO get a movement
-- written — that part works. But the note reads the same as a direct sale:
--
--     Sale — INV-2026-0060
--
-- So a pillow deducted because someone bought a promotion is indistinguishable
-- from a pillow sold on its own. Looking for the promotion in Stock History,
-- there is nothing to find it by.
--
-- invoice_required_stock() returns only (kind, item_id, quantity) — it does not
-- say which line an item came from. Rather than change its shape, which several
-- functions depend on, the note is built by asking a simpler question: is this
-- product a direct product line on the invoice? If not, it came from a
-- promotion or bundle, and those can be named.
--
--     Sale — INV-2026-0060 (via Weekend Bundle)
--
-- Additive and idempotent. Changes no stock and no quantity — only the text
-- recorded alongside it.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The note for one product on one invoice.
-- ---------------------------------------------------------------------
create or replace function public.invoice_stock_note(
  p_invoice_id uuid, p_product_id uuid, p_prefix text default 'Sale')
returns text language sql stable security definer set search_path to 'public' as $function$
  select p_prefix || ' — ' || coalesce(i.invoice_no, '?')
    || case
         -- A direct product line: nothing more to say.
         when exists (select 1 from public.invoice_items ii
                       where ii.invoice_id = p_invoice_id
                         and ii.line_kind::text = 'product'
                         and ii.product_id = p_product_id)
           then ''
         -- Otherwise it came from a promotion or bundle on this invoice.
         else coalesce(' (via ' || (
           select string_agg(distinct pm.name, ', ')
             from public.invoice_items ii
             join public.promotions pm on pm.id = ii.promotion_id
            where ii.invoice_id = p_invoice_id
              and ii.line_kind::text in ('promotion', 'premium_bundle')
         ) || ')', '')
       end
    from public.invoices i
   where i.id = p_invoice_id
$function$;

-- ---------------------------------------------------------------------
-- 2. Use it when a sale deducts stock.
--
--    Patched on whatever version is installed, since pay_invoice is defined in
--    thirteen files and the winner depends on deploy order.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text; v_n integer := 0;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'pay_invoice'
   limit 1;
  if v_def is null then raise exception 'pay_invoice not found'; end if;
  if position('invoice_stock_note' in v_def) > 0 then
    raise notice 'pay_invoice already names the promotion'; return;
  end if;

  v_new := replace(v_def,
    '''Sale — ''||v_inv.invoice_no',
    'public.invoice_stock_note(p_invoice_id, v_req.item_id, ''Sale'')');

  if v_new = v_def then
    raise notice 'pay_invoice does not use the expected note text — left unchanged';
    return;
  end if;
  execute v_new;
  raise notice 'a sale now records which promotion a product came from';
end $patch$;

-- ---------------------------------------------------------------------
-- 3. And when a paid invoice is corrected.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'deduct_invoice_stock';
  if v_def is null then raise notice 'deduct_invoice_stock not present'; return; end if;
  if position('invoice_stock_note' in v_def) > 0 then
    raise notice 'the correction path already names the promotion'; return;
  end if;

  v_new := replace(v_def,
    'coalesce(p_note, ''Stock deducted — paid invoice edited'')',
    'coalesce(p_note, public.invoice_stock_note(p_invoice_id, v_req.item_id, ''Corrected''))');

  if v_new = v_def then
    raise notice 'deduct_invoice_stock note text not matched — left unchanged';
  else
    execute v_new;
    raise notice 'a correction now records which promotion a product came from';
  end if;
end $patch$;

do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'restore_invoice_stock';
  if v_def is null then raise notice 'restore_invoice_stock not present'; return; end if;
  if position('invoice_stock_note' in v_def) > 0 then
    raise notice 'the restore path already names the promotion'; return;
  end if;

  v_new := replace(v_def,
    'coalesce(p_note, ''Stock returned — paid invoice edited'')',
    'coalesce(p_note, public.invoice_stock_note(p_invoice_id, v_req.item_id, ''Returned''))');

  if v_new = v_def then
    raise notice 'restore_invoice_stock note text not matched — left unchanged';
  else
    execute v_new;
    raise notice 'a stock return now records which promotion a product came from';
  end if;
end $patch$;

-- ---------------------------------------------------------------------
-- 4. Label movements ALREADY written, so past promotion sales are findable
--    too. Only rows whose note is the plain sale text, and only where the
--    product was not a direct line on that invoice.
-- ---------------------------------------------------------------------
do $$
declare v_n integer;
begin
  update public.stock_movements sm
     set notes = public.invoice_stock_note(sm.invoice_id, sm.product_id, 'Sale')
   where sm.invoice_id is not null
     and sm.product_id is not null
     and sm.notes like 'Sale — %'
     and sm.notes not like '% (via %'
     and not exists (select 1 from public.invoice_items ii
                      where ii.invoice_id = sm.invoice_id
                        and ii.line_kind::text = 'product'
                        and ii.product_id = sm.product_id)
     and exists (select 1 from public.invoice_items ii
                  where ii.invoice_id = sm.invoice_id
                    and ii.line_kind::text in ('promotion', 'premium_bundle'));
  get diagnostics v_n = row_count;
  raise notice 'Labelled % past movement(s) with the promotion they came from', v_n;
end $$;

notify pgrst, 'reload schema';
