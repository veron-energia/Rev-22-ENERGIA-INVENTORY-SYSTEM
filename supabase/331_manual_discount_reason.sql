begin;
-- =====================================================================
-- A MANUAL DISCOUNT CARRIES ITS REASON
--
-- Staff could take any amount off an invoice and leave nothing behind but the
-- number. A manual discount now needs an internal reason whenever it is
-- greater than zero: on creation, and on any correction that sets or changes
-- the amount. The reason is its own column — not the invoice notes the
-- customer may see, and not the correction reason that describes the edit.
--
-- The guard is a trigger, because there is more than one way to write the
-- column. create_invoice_with_details and correct_invoice say it in plain
-- words first; the trigger is what stops update_invoice, edit_paid_invoice
-- or a direct statement from setting a discount with no reason at all.
--
-- History is left alone. An invoice discounted before this column existed
-- stays viewable, and a correction that leaves its amount untouched is not
-- asked to invent one. Only a change to a positive amount demands a reason.
-- Removing the discount clears the reason from the invoice; the revision
-- snapshot and the audit row keep both as they were.
--
-- The reason is internal. The customer documents, the share messages and the
-- exports build their payloads field by field and do not include it.
--
-- Additive. Idempotent.
-- =====================================================================
alter table public.invoices add column if not exists manual_discount_reason text;
comment on column public.invoices.manual_discount_reason is
 'Internal reason for a manual discount. Required when manual_discount > 0 is set or changed. Never on customer-facing documents.';

create or replace function public.trg_invoice_manual_discount_reason()
returns trigger language plpgsql as $$
begin
  -- Whitespace is not a reason.
  new.manual_discount_reason := nullif(btrim(coalesce(new.manual_discount_reason, '')), '');

  if tg_op = 'INSERT' then
    -- create_invoice does not know the column; create_invoice_with_details
    -- hands the reason over for the same transaction. A caller that reaches
    -- the insert any other way has no reason to offer, and is refused.
    if new.manual_discount_reason is null then
      new.manual_discount_reason := nullif(btrim(coalesce(current_setting('invoice.manual_discount_reason', true), '')), '');
    end if;
    if coalesce(new.manual_discount, 0) > 0 and new.manual_discount_reason is null then
      raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.';
    end if;
    return new;
  end if;

  -- A correction that changes the amount to something positive needs a reason.
  -- One that leaves the amount alone does not, so history is never asked for.
  if coalesce(new.manual_discount, 0) > 0
     and new.manual_discount is distinct from old.manual_discount
     and new.manual_discount_reason is null then
    raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.';
  end if;
  -- No discount, no reason to keep on the row. The audit has the old pair.
  if coalesce(new.manual_discount, 0) <= 0 then new.manual_discount_reason := null; end if;
  return new;
end $$;

drop trigger if exists invoice_manual_discount_reason on public.invoices;
create trigger invoice_manual_discount_reason
  before insert or update of manual_discount, manual_discount_reason on public.invoices
  for each row execute function public.trg_invoice_manual_discount_reason();

do $do$
declare f text;
begin
  -- Creation: say it plainly before the insert, then hand the reason to the
  -- trigger for the row create_invoice writes, then keep it on the row.
  select pg_get_functiondef('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)'::regprocedure) into f;
  if position('manual_discount_reason' in f) = 0 then
    f := replace(f,
' if nullif(p_header->>''business_date'','''') is null then raise exception ''Invoice business date is required''; end if;',
' if nullif(p_header->>''business_date'','''') is null then raise exception ''Invoice business date is required''; end if;
 if coalesce((p_header->>''manual_discount'')::numeric,0) > 0
    and nullif(btrim(coalesce(p_header->>''manual_discount_reason'','''')),'''') is null then
   raise exception ''MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.''; end if;
 perform set_config(''invoice.manual_discount_reason'', coalesce(p_header->>''manual_discount_reason'',''''), true);');
    f := replace(f,
'  instalment_months=nullif(p_header->>''instalment_months'','''')::int where id=v_id;',
'  instalment_months=nullif(p_header->>''instalment_months'','''')::int,
  manual_discount_reason=case when coalesce((p_header->>''manual_discount'')::numeric,0) > 0
                              then nullif(btrim(p_header->>''manual_discount_reason''),'''') end
  where id=v_id;');
    if position('set_config(''invoice.manual_discount_reason''' in f) = 0 or position('manual_discount_reason=case' in f) = 0 then
      raise exception 'create_invoice_with_details does not match what 331 expects — align it by hand'; end if;
    execute f;
  end if;

  -- Correction: read the reason with the amount, validate in words, write it
  -- in the header update, which runs before update_invoice_internal changes
  -- the amount — so the trigger sees the reason already on the row.
  select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
  if position('manual_discount_reason' in f) = 0 then
    f := replace(f,
' if p_header ? ''manual_discount'' then n.manual_discount:=(p_header->>''manual_discount'')::numeric; end if;',
' if p_header ? ''manual_discount'' then n.manual_discount:=(p_header->>''manual_discount'')::numeric; end if;
 if p_header ? ''manual_discount_reason'' then n.manual_discount_reason:=nullif(btrim(p_header->>''manual_discount_reason''),''''); end if;
 if coalesce(n.manual_discount,0) > 0 and n.manual_discount is distinct from i.manual_discount and n.manual_discount_reason is null then
   raise exception ''MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.''; end if;
 if coalesce(n.manual_discount,0) <= 0 then n.manual_discount_reason:=null; end if;');
    f := replace(f,
'  created_by=n.created_by,',
'  created_by=n.created_by,manual_discount_reason=n.manual_discount_reason,');
    if position('n.manual_discount_reason:=nullif' in f) = 0 or position('manual_discount_reason=n.manual_discount_reason' in f) = 0 then
      raise exception 'correct_invoice does not match what 331 expects — align it by hand'; end if;
    execute f;
  end if;
end $do$;
commit;
