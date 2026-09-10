-- Add business dates and instalment instructions without assigning invented dates
-- to historical invoices. Legacy dates remain NULL until reviewed.
begin;
alter table public.invoices add column if not exists affiliate_selection_explicit boolean not null default false;
alter table public.invoices add column if not exists business_date date;
alter table public.invoices alter column business_date set default (now() at time zone 'Asia/Singapore')::date;
alter table public.invoices add column if not exists instalment_category text;
alter table public.invoices add column if not exists instalment_method_id uuid references public.payment_methods(id);
alter table public.invoices add column if not exists instalment_months integer;
alter table public.invoice_revisions add column if not exists after_snapshot jsonb;
alter table public.invoice_revisions add column if not exists request_id uuid;
create unique index if not exists invoice_revision_request on public.invoice_revisions(invoice_id,request_id) where request_id is not null;
alter table public.invoices add constraint invoice_instalment_details check (
  (instalment_category is null and instalment_method_id is null and instalment_months is null)
  or (instalment_category in ('in_house','provider_funded') and instalment_method_id is not null and instalment_months > 0));

create or replace function public.validate_invoice_business_metadata()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.instalment_category is not null and (tg_op='INSERT' or
    (new.instalment_category,new.instalment_method_id,new.instalment_months) is distinct from
    (old.instalment_category,old.instalment_method_id,old.instalment_months)) then
    if not exists(select 1 from public.payment_methods where id=new.instalment_method_id
      and is_active and deleted_at is null and not coalesce(is_wallet_credit,false)) then
      raise exception 'Select an active external payment method for the instalment arrangement'; end if;
  end if;
  return new;
end $$;
create trigger invoice_business_metadata_valid before insert or update on public.invoices
for each row execute function public.validate_invoice_business_metadata();

-- The payment ledger stays append-only: a correction is represented by a
-- reversal/replacement pair, distinct from an actual customer refund.
alter table public.invoice_payments add column if not exists entry_kind text not null default 'receipt'
  check(entry_kind in ('receipt','correction_reversal','correction_replacement'));
alter table public.invoice_payments add column if not exists corrects_payment_id uuid references public.invoice_payments(id);
alter table public.invoice_payments add column if not exists correction_reason text;
alter table public.invoice_payments add column if not exists correction_request_id uuid;
create unique index if not exists invoice_payment_reversed_once on public.invoice_payments(corrects_payment_id)
  where entry_kind='correction_reversal';
create unique index if not exists invoice_payment_correction_retry on public.invoice_payments(invoice_id,correction_request_id,entry_kind)
  where correction_request_id is not null;
alter table public.invoice_payments add constraint invoice_payment_correction_evidence check(
  entry_kind='receipt' or (corrects_payment_id is not null and nullif(trim(correction_reason),'') is not null and correction_request_id is not null));

alter table public.invoice_refunds add column if not exists payment_id uuid references public.invoice_payments(id);
alter table public.invoice_refunds add column if not exists request_id uuid;
alter table public.invoice_refunds add column if not exists outcome jsonb not null default '{}'::jsonb;
alter table public.invoice_refunds add column if not exists credit_returned numeric(12,2) not null default 0 check(credit_returned>=0);
create unique index if not exists invoice_refund_request_source on public.invoice_refunds(invoice_id,request_id,payment_id)
  where request_id is not null;

create or replace function public.invoice_net_received(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
 select round(coalesce((select sum(case when entry_kind='correction_reversal' then -amount else amount end)
   from public.invoice_payments where invoice_id=p_invoice_id),0)
   -coalesce((select sum(amount) from public.invoice_refunds where invoice_id=p_invoice_id),0),2)
$$;
create or replace function public.invoice_financial_position(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare i public.invoices%rowtype; n numeric;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 n:=public.invoice_net_received(i.id);
 return jsonb_build_object('total',i.total_amount,'net_received',n,
   'outstanding',greatest(i.total_amount-n,0),'refund_due',greatest(n-i.total_amount,0),
   'refunded',coalesce((select sum(amount) from public.invoice_refunds where invoice_id=i.id),0),
   'status',i.status,'business_date',i.business_date);
end $$;
revoke all on function public.invoice_net_received(uuid) from public,anon,authenticated;
revoke all on function public.invoice_financial_position(uuid) from public,anon;
grant execute on function public.invoice_financial_position(uuid) to authenticated;

-- Read-only rollout diagnostic: no guessed date or refund-source allocation.
create or replace function public.invoice_reporting_date_review()
returns table(invoice_id uuid,invoice_no text,business_date date,created_date date,
  payment_date date,amount numeric,issue text)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can run this review'; end if;
 return query select i.id,i.invoice_no,i.business_date,(i.created_at at time zone 'Asia/Singapore')::date,
   (p.created_at at time zone 'Asia/Singapore')::date,
   case when p.entry_kind='correction_reversal' then -p.amount else p.amount end,
   case when i.business_date is null then 'Business date requires review; creation date shown only as a suggestion'
        when i.status='refunded' and not exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id)
        then 'Refunded status has no refund ledger evidence'
        when exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id and r.payment_id is null)
        then 'Historical refund payment source requires review'
        else 'Sales move from payment date to invoice business date; collections do not move' end
 from public.invoices i left join public.invoice_payments p on p.invoice_id=i.id
 left join public.payment_methods m on m.id=p.payment_method_id
 where not coalesce(m.is_wallet_credit,false)
 and (i.business_date is null or i.business_date is distinct from (p.created_at at time zone 'Asia/Singapore')::date
   or exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id and r.payment_id is null));
end $$;
revoke all on function public.invoice_reporting_date_review() from public,anon;
grant execute on function public.invoice_reporting_date_review() to authenticated;
notify pgrst,'reload schema';
commit;
