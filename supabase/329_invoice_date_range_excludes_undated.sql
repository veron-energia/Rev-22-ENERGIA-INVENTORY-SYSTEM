begin;
-- =====================================================================
-- A DATE RANGE MEANS DATED INVOICES INSIDE IT
--
-- 324 let an invoice with no business date through any From/To range, on the
-- reasoning that it was not "outside" a range it had no place in. But the list
-- shows every invoice a date — the Singapore day it was created, where none
-- was recorded — so an undated invoice created on 08/09 displayed 08/09 and
-- survived a range of 17/09 to 17/09. The filter and the column disagreed.
--
-- A range now admits only invoices whose recorded business date lies inside
-- it, both ends inclusive. Undated invoices are what "Date from creation only"
-- is for, and that mode cannot be combined with a range: the combination is
-- refused rather than quietly returning nothing. From after To is refused too;
-- the server never swaps the dates for the caller.
--
-- Patched by anchored replacement of the installed definition. Idempotent.
-- =====================================================================
do $do$
declare f text;
begin
  select pg_get_functiondef('public.invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)'::regprocedure) into f;
  if position('DATE_RANGE_INCOMPATIBLE' in f) > 0 then return; end if;

  f := replace(f,
'       -- A date range only constrains invoices that have a date; an undated one
       -- is not "outside" a range it has no place in.
       and (p_date_from is null or i.business_date is null or i.business_date >= p_date_from)
       and (p_date_to   is null or i.business_date is null or i.business_date <= p_date_to)',
'       -- A range admits dated invoices inside it, both ends inclusive. An
       -- undated invoice shows its creation day in the list, but that is not a
       -- business date and does not place it inside any range (329).
       and (p_date_from is null or (i.business_date is not null and i.business_date >= p_date_from))
       and (p_date_to   is null or (i.business_date is not null and i.business_date <= p_date_to))');

  f := replace(f,
'  if v_field not in (''invoice_no'',''created_at'',''business_date'',''customer'',''store'',
                     ''total'',''outstanding'',''status'') then
    raise exception ''Not a sortable field: %'', v_field; end if;',
'  if v_field not in (''invoice_no'',''created_at'',''business_date'',''customer'',''store'',
                     ''total'',''outstanding'',''status'') then
    raise exception ''Not a sortable field: %'', v_field; end if;
  -- Refused rather than swapped: the caller asked for something impossible.
  if p_date_from is not null and p_date_to is not null and p_date_from > p_date_to then
    raise exception ''DATE_RANGE_INVALID: The "from" date is after the "to" date.''; end if;
  -- Undated invoices have no business date to fall inside a range.
  if coalesce(p_date_mode,''all'') = ''pending'' and (p_date_from is not null or p_date_to is not null) then
    raise exception ''DATE_RANGE_INCOMPATIBLE: "Date from creation only" lists invoices with no business date, so a date range cannot apply to it.''; end if;');

  if position('DATE_RANGE_INCOMPATIBLE' in f) = 0 or position('business_date is not null and i.business_date >= p_date_from' in f) = 0 then
    raise exception 'invoice_list_page does not match what 329 expects — align it by hand'; end if;
  execute f;
end $do$;
commit;
