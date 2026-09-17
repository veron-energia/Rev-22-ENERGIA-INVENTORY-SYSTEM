-- ROLLBACK FOR MIGRATIONS 329–332
--
-- Reverses, in reverse order, what 329–332 did: drops the staff directory
-- function, the discount-reason trigger and its function, restores the two
-- Save Earth functions, and reverts the three patched functions by the same
-- anchored-replacement technique the migrations used — so nothing is retyped
-- from memory and each step raises rather than guesses if the installed text
-- is not what it expects. invoices.manual_discount_reason is left in place:
-- dropping a column that may hold data is a decision for a person.
--
-- Idempotent: a step whose work is already undone is skipped.
begin;

-- 332 ---------------------------------------------------------------------
drop function if exists public.affiliate_staff_directory(text, integer, integer);

-- 331: guard off ----------------------------------------------------------
drop trigger if exists invoice_manual_discount_reason on public.invoices;
drop function if exists public.trg_invoice_manual_discount_reason();

-- 331 then 330: create_invoice_with_details -------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)'::regprocedure) into f;
  if position('manual_discount_reason' in f) > 0 then
    f := replace(f,
' if nullif(p_header->>''business_date'','''') is null then raise exception ''Invoice business date is required''; end if;
 if coalesce((p_header->>''manual_discount'')::numeric,0) > 0
    and nullif(btrim(coalesce(p_header->>''manual_discount_reason'','''')),'''') is null then
   raise exception ''MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.''; end if;
 perform set_config(''invoice.manual_discount_reason'', coalesce(p_header->>''manual_discount_reason'',''''), true);',
' if nullif(p_header->>''business_date'','''') is null then raise exception ''Invoice business date is required''; end if;');
    f := replace(f,
'  instalment_months=nullif(p_header->>''instalment_months'','''')::int,
  manual_discount_reason=case when coalesce((p_header->>''manual_discount'')::numeric,0) > 0
                              then nullif(btrim(p_header->>''manual_discount_reason''),'''') end
  where id=v_id;',
'  instalment_months=nullif(p_header->>''instalment_months'','''')::int where id=v_id;');
    if position('manual_discount_reason' in f) > 0 then
      raise exception 'create_invoice_with_details: 331 could not be reverted — align by hand'; end if;
  end if;
  if position('save_earth' in f) = 0 then
    f := replace(f,
' return v_id;',
' if coalesce((p_header->>''save_earth_applied'')::boolean,false) then
  perform public.set_invoice_save_earth(v_id,true,p_header->>''save_earth_label'',coalesce((p_header->>''save_earth_amount'')::numeric,0)); end if;
 return v_id;');
    if position('save_earth' in f) = 0 then
      raise exception 'create_invoice_with_details: 330 could not be reverted — align by hand'; end if;
  end if;
  execute f;
end $do$;

-- 331 then 330: correct_invoice -------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('manual_discount_reason' in f) > 0 then
    f := replace(f,
' if p_header ? ''manual_discount'' then n.manual_discount:=(p_header->>''manual_discount'')::numeric; end if;
 if p_header ? ''manual_discount_reason'' then n.manual_discount_reason:=nullif(btrim(p_header->>''manual_discount_reason''),''''); end if;
 if coalesce(n.manual_discount,0) > 0 and n.manual_discount is distinct from i.manual_discount and n.manual_discount_reason is null then
   raise exception ''MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.''; end if;
 if coalesce(n.manual_discount,0) <= 0 then n.manual_discount_reason:=null; end if;',
' if p_header ? ''manual_discount'' then n.manual_discount:=(p_header->>''manual_discount'')::numeric; end if;');
    f := replace(f, '  created_by=n.created_by,manual_discount_reason=n.manual_discount_reason,', '  created_by=n.created_by,');
    if position('manual_discount_reason' in f) > 0 then
      raise exception 'correct_invoice: 331 could not be reverted — align by hand'; end if;
  end if;
  if position('p_header ? ''save_earth_applied''' in f) = 0 then
    f := replace(f,
' if p_header ? ''created_by'' and nullif(p_header->>''created_by'','''')::uuid is distinct from i.created_by then',
' if p_header ? ''save_earth_applied'' then
  n.save_earth_applied:=(p_header->>''save_earth_applied'')::boolean;
  n.save_earth_label:=p_header->>''save_earth_label''; n.save_earth_amount:=(p_header->>''save_earth_amount'')::numeric;
 end if;
 if p_header ? ''created_by'' and nullif(p_header->>''created_by'','''')::uuid is distinct from i.created_by then');
    if position('p_header ? ''save_earth_applied''' in f) = 0 then
      raise exception 'correct_invoice: 330 could not be reverted — align by hand'; end if;
  end if;
  execute f;
end $do$;

-- 330: the two dropped functions, as they were installed ------------------
create or replace function public.set_invoice_save_earth(p_invoice_id uuid, p_applied boolean, p_label text default null, p_amount numeric default null)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_inv public.invoices%rowtype; v_def public.app_settings%rowtype; v_label text; v_amount numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this store'; end if;
  if v_inv.status in ('paid','partially_paid','cancelled','refunded') or coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'Discounts cannot be changed after payment'; end if;

  select * into v_def from public.app_settings where id = true;
  if p_applied then
    v_label := coalesce(nullif(trim(p_label),''), v_def.save_earth_label, 'Save Earth Project');
    v_amount := coalesce(p_amount, v_def.save_earth_amount, 1);
    if v_amount < 0 then raise exception 'Save Earth amount cannot be negative'; end if;
  else
    v_label := null; v_amount := 0;
  end if;

  update public.invoices
     set save_earth_applied = p_applied, save_earth_label = v_label, save_earth_amount = v_amount
   where id = p_invoice_id;
  -- Rebuild discount_total to include Save Earth (once) + existing discounts,
  -- then recompute total floored at 0.
  perform public.refresh_invoice_discount_total(p_invoice_id);
  update public.invoices i
     set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0))
   where i.id = p_invoice_id;
end $function$;

create or replace function public.set_save_earth_defaults(p_label text, p_amount numeric)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit the Save Earth defaults'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'Amount cannot be negative'; end if;
  update public.app_settings
     set save_earth_label = coalesce(nullif(trim(p_label),''), 'Save Earth Project'),
         save_earth_amount = p_amount, updated_at = now()
   where id = true;
  perform public.write_audit('app_settings', null, 'save_earth_defaults_set', null,
    jsonb_build_object('label', p_label, 'amount', p_amount));
end $function$;

-- 329: invoice_list_page --------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)'::regprocedure) into f;
  if position('DATE_RANGE_INCOMPATIBLE' in f) = 0 then return; end if;
  f := replace(f,
'       -- A range admits dated invoices inside it, both ends inclusive. An
       -- undated invoice shows its creation day in the list, but that is not a
       -- business date and does not place it inside any range (329).
       and (p_date_from is null or (i.business_date is not null and i.business_date >= p_date_from))
       and (p_date_to   is null or (i.business_date is not null and i.business_date <= p_date_to))',
'       -- A date range only constrains invoices that have a date; an undated one
       -- is not "outside" a range it has no place in.
       and (p_date_from is null or i.business_date is null or i.business_date >= p_date_from)
       and (p_date_to   is null or i.business_date is null or i.business_date <= p_date_to)');
  f := replace(f,
'
  -- Refused rather than swapped: the caller asked for something impossible.
  if p_date_from is not null and p_date_to is not null and p_date_from > p_date_to then
    raise exception ''DATE_RANGE_INVALID: The "from" date is after the "to" date.''; end if;
  -- Undated invoices have no business date to fall inside a range.
  if coalesce(p_date_mode,''all'') = ''pending'' and (p_date_from is not null or p_date_to is not null) then
    raise exception ''DATE_RANGE_INCOMPATIBLE: "Date from creation only" lists invoices with no business date, so a date range cannot apply to it.''; end if;', '');
  if position('DATE_RANGE_INCOMPATIBLE' in f) > 0 or position('business_date is null or i.business_date >= p_date_from' in f) = 0 then
    raise exception 'invoice_list_page: 329 could not be reverted — align by hand'; end if;
  execute f;
end $do$;

commit;
