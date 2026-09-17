begin;
-- =====================================================================
-- AN INSTALMENT IS A LABEL ON MONEY THAT HAS ARRIVED
--
-- 304 modelled an instalment as a promise: invoice_payment_arrangements is
-- "a promise to pay, never a receipt", and the screen asked for two amounts —
-- what the arrangement covered, and what was actually received today. That is
-- the right shape when the shop collects the money itself over months.
--
-- It is not how this shop sells. The customer's instalment is with their bank
-- or card issuer; the shop is paid in full at the till and the duration is
-- reference information about the customer's own arrangement. Recording a
-- promise to collect money that has already arrived leaves an invoice owing a
-- balance nobody is waiting for.
--
-- So the payment screens now record an instalment as the receipt it is, under
-- the real method the money came through, and stamp the terms on the invoice
-- using the columns 171 already defined. No arrangement row is written.
--
-- This function is the stamp. The arrangement table, its checks and every
-- historical row are left exactly as they are: invoices recorded under the old
-- model keep their arrangements and keep displaying what they were saved with.
--
-- Additive. Idempotent.
-- =====================================================================

create or replace function public.set_invoice_instalment_label(
  p_invoice_id uuid,
  p_method_id  uuid,
  p_months     integer
) returns void
language plpgsql security definer set search_path = public as $$
declare v_store uuid;
begin
  select store_id into v_store from public.invoices
   where id = p_invoice_id and deleted_at is null;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_store) then
    raise exception 'No access to this invoice' using errcode = '42501'; end if;

  -- Clearing the label is a legitimate request: a payment corrected back to an
  -- ordinary method should not leave instalment terms behind.
  if p_method_id is null or p_months is null then
    update public.invoices
       set instalment_category = null, instalment_method_id = null, instalment_months = null
     where id = p_invoice_id;
    return;
  end if;

  if p_months <= 0 then
    raise exception 'An instalment needs a positive whole number of months'; end if;

  -- The same rule the metadata trigger enforces, raised here where it can be
  -- said in terms of the field the operator actually chose.
  if not exists (select 1 from public.payment_methods
                  where id = p_method_id and is_active and deleted_at is null
                    and not coalesce(is_wallet_credit, false)) then
    raise exception 'Choose an active payment method for the instalment'; end if;

  -- in_house is the only category these screens now offer. The column keeps its
  -- check constraint and provider_funded stays valid for the rows that carry it.
  update public.invoices
     set instalment_category  = 'in_house',
         instalment_method_id = p_method_id,
         instalment_months    = p_months
   where id = p_invoice_id;
end $$;

comment on function public.set_invoice_instalment_label(uuid, uuid, integer) is
 'Record which instalment terms an invoice was paid under. A label on money already received — it never creates an obligation to collect anything later.';

revoke all on function public.set_invoice_instalment_label(uuid, uuid, integer) from public;
grant execute on function public.set_invoice_instalment_label(uuid, uuid, integer) to authenticated;

commit;
