begin;
-- =====================================================================
-- SAVE EARTH IS WITHDRAWN
--
-- The Save Earth Project was a per-invoice deduction with a global default.
-- The feature is removed from the application: the two functions that set it
-- are dropped, and the create and correct paths no longer read it from the
-- header. What is kept:
--
--   invoices.save_earth_applied / save_earth_label / save_earth_amount
--     Historical. refresh_invoice_discount_total still counts the amount into
--     discount_total for invoices that carried it, so those invoices keep the
--     totals they were issued with; customer_purchase_timeline and
--     report_discounts still report it for the same reason. New invoices never
--     set it.
--   app_settings.save_earth_label / save_earth_amount
--     Retained only so the settings row keeps its shape. Nothing reads them.
--
-- Patched by anchored replacement. Idempotent.
-- =====================================================================
do $do$
declare f text;
begin
  select pg_get_functiondef('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)'::regprocedure) into f;
  if position('save_earth' in f) > 0 then
    f := replace(f,
' if coalesce((p_header->>''save_earth_applied'')::boolean,false) then
  perform public.set_invoice_save_earth(v_id,true,p_header->>''save_earth_label'',coalesce((p_header->>''save_earth_amount'')::numeric,0)); end if;
', '');
    if position('save_earth' in f) > 0 then
      raise exception 'create_invoice_with_details does not match what 330 expects — align it by hand'; end if;
    execute f;
  end if;

  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('p_header ? ''save_earth_applied''' in f) > 0 then
    f := replace(f,
' if p_header ? ''save_earth_applied'' then
  n.save_earth_applied:=(p_header->>''save_earth_applied'')::boolean;
  n.save_earth_label:=p_header->>''save_earth_label''; n.save_earth_amount:=(p_header->>''save_earth_amount'')::numeric;
 end if;
', '');
    if position('p_header ? ''save_earth_applied''' in f) > 0 then
      raise exception 'correct_invoice does not match what 330 expects — align it by hand'; end if;
    -- The historical columns are still carried through unchanged (n := i), so
    -- an invoice that had the deduction keeps it across a correction.
    execute f;
  end if;
end $do$;

drop function if exists public.set_invoice_save_earth(uuid, boolean, text, numeric);
drop function if exists public.set_save_earth_defaults(text, numeric);

comment on column public.invoices.save_earth_applied is
 'Historical (feature withdrawn in 330). Kept so invoices issued with the deduction keep their totals. Never set on new invoices.';
comment on column public.app_settings.save_earth_amount is
 'Historical (feature withdrawn in 330). Not read by anything.';
commit;
