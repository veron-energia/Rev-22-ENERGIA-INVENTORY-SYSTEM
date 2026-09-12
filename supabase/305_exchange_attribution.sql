begin;
-- =====================================================================
-- AN EXCHANGE IS HANDLED BY SOMEBODY, AND IT IS NOT WHOEVER SOLD THE THING
--
-- product_exchanges recorded the processing store, an affiliate and created_by,
-- and nothing else about who did the work. So an exchange served by Staff C and
-- D was indistinguishable from the original sale served by Staff A and B, and
-- reporting had nothing to attribute today's handling to.
--
-- Added here, all on the EXCHANGE, leaving the original invoice's own
-- attribution and audit history untouched:
--
--   product_exchange_service_staff   who served this exchange (several people)
--   raised_by                        who issued the document. Kept apart from
--                                    served-by on purpose: changing the issuer
--                                    must not redirect commission.
--   exchange_date                    the Singapore day it happened. The
--                                    original invoice's date is never touched,
--                                    so its five-day window cannot restart.
--   affiliate_selection_explicit     mirrors the column invoices already has,
--                                    so an explicit "None" stays None instead
--                                    of quietly falling back to the customer's
--                                    referrer.
--
-- Nothing is copied from the original by default. An exchange that names no
-- staff is refused rather than inheriting yesterday's.
--
-- Additive. Idempotent.
-- =====================================================================

alter table public.product_exchanges
  add column if not exists raised_by uuid references public.profiles(id),
  add column if not exists exchange_date date,
  add column if not exists affiliate_selection_explicit boolean not null default false,
  -- product_exchanges.affiliate_id points at the LEGACY `affiliates` table,
  -- which the invoice flow stopped using: invoices.affiliate_id references
  -- customer_affiliates. They could never hold the same value, so an exchange
  -- could not be prefilled from, or compared with, its original sale. A second
  -- column matching the invoice model fixes that without touching the historical
  -- one, which keeps whatever it was saved with.
  add column if not exists exchange_affiliate_id uuid references public.customer_affiliates(id);

comment on column public.product_exchanges.raised_by is
 'Who issued the exchange document. Never used for commission attribution — that follows the service staff.';
comment on column public.product_exchanges.exchange_affiliate_id is
 'The affiliate credited for THIS exchange, referencing customer_affiliates exactly as invoices.affiliate_id does. The older affiliate_id column references the legacy affiliates table and is left as it was.';
comment on column public.product_exchanges.affiliate_selection_explicit is
 'True when a person actively chose the affiliate, including choosing None. Prevents a fallback to the customer''s referrer.';

create table if not exists public.product_exchange_service_staff (
  exchange_id uuid not null references public.product_exchanges(id) on delete cascade,
  staff_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (exchange_id, staff_id)
);
comment on table public.product_exchange_service_staff is
 'Who served THIS exchange. Separate from invoice_service_staff, which records who served the original sale.';

alter table public.product_exchange_service_staff enable row level security;
do $$
begin
 if not exists (select 1 from pg_policy where polrelid='public.product_exchange_service_staff'::regclass
                 and polname='read exchange service staff') then
  create policy "read exchange service staff" on public.product_exchange_service_staff
    for select using (exists (select 1 from public.product_exchanges e
      where e.id = product_exchange_service_staff.exchange_id
        and public.user_has_store_access(e.processing_store_id)));
 end if;
end $$;
grant select on public.product_exchange_service_staff to authenticated;

-- ---------------------------------------------------------------------
-- The original sale's own attribution, for display beside the exchange.
-- Read-only, and never used as a default.
-- ---------------------------------------------------------------------
create or replace function public.exchange_original_context(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare i public.invoices%rowtype;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice not accessible'; end if;
 return jsonb_build_object(
   'invoice_id',i.id,'invoice_no',i.invoice_no,
   'invoice_date',coalesce(i.business_date,(i.created_at at time zone 'Asia/Singapore')::date),
   'store',(select name from public.stores where id=i.store_id),
   'customer_id',i.customer_id,
   -- Read by id so a customer outside the interface's page of rows, or a
   -- historical one, still has a name.
   'customer',(select full_name from public.customers where id=i.customer_id),
   'customer_phone',(select phone from public.customers where id=i.customer_id),
   'served_by',(select coalesce(jsonb_agg(jsonb_build_object('staff_id',p.id,'name',p.full_name) order by p.full_name),'[]'::jsonb)
                  from public.invoice_service_staff s join public.profiles p on p.id=s.staff_id
                 where s.invoice_id=i.id),
   'affiliate_id',i.affiliate_id,
   'affiliate',(select full_name from public.customers where id=i.affiliate_id),
   'affiliate_still_eligible',case when i.affiliate_id is not null
                                   then public.is_eligible_affiliate(i.affiliate_id) end);
end $$;
grant execute on function public.exchange_original_context(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Applying the exchange's own details, with everything checked server-side.
-- ---------------------------------------------------------------------
create or replace function public.set_exchange_details(
  p_exchange_id uuid, p_staff jsonb, p_affiliate jsonb,
  p_raised_by uuid, p_exchange_date date, p_notes text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare e public.product_exchanges%rowtype; x jsonb; v_id uuid; v_role text;
 v_mode text; v_aff uuid; v_aff_customer uuid; v_explicit boolean:=false; v_raised uuid; v_date date; v_n int:=0;
begin
 select * into e from public.product_exchanges where id=p_exchange_id for update;
 if not found then raise exception 'Exchange not found'; end if;
 if not public.user_has_store_access(e.processing_store_id) then
  raise exception 'No access to this exchange''s store' using errcode='42501'; end if;

 -- ---- who served it. Never inherited from the original sale. -------------
 if p_staff is null or jsonb_typeof(p_staff)<>'array' or jsonb_array_length(p_staff)=0 then
  raise exception 'Choose the staff who handled this exchange'; end if;
 delete from public.product_exchange_service_staff where exchange_id=e.id;
 for x in select * from jsonb_array_elements(p_staff) loop
  v_id:=(x#>>'{}')::uuid;
  if v_id is null then continue; end if;
  select role into v_role from public.profiles
   where id=v_id and coalesce(is_active,true) and deleted_at is null;
  if v_role is null then raise exception 'A selected staff member was not found or is inactive'; end if;
  if v_role not in ('owner','manager','staff') then
   raise exception 'Service staff must be an Owner, Manager or Staff member (got %)',v_role; end if;
  -- Eligible for THIS store. Owners and managers reach every store already.
  if v_role='staff' and not exists(select 1 from public.user_store_assignments
                                    where user_id=v_id and store_id=e.processing_store_id) then
   raise exception '% is not assigned to the store processing this exchange',
     (select full_name from public.profiles where id=v_id); end if;
  insert into public.product_exchange_service_staff(exchange_id,staff_id)
   values(e.id,v_id) on conflict do nothing;
  v_n:=v_n+1;
 end loop;
 if v_n=0 then raise exception 'Choose the staff who handled this exchange'; end if;

 -- ---- the affiliate. "None" means none. ----------------------------------
 v_mode:=coalesce(p_affiliate->>'mode','inherit');
 if v_mode='none' then
  v_aff:=null; v_explicit:=true;
 elsif v_mode='set' then
  -- The id of a customer_affiliates row, as invoices use.
  v_aff:=nullif(p_affiliate->>'id','')::uuid;
  if v_aff is null then raise exception 'Choose an affiliate, or choose None'; end if;
  select customer_id into v_aff_customer from public.customer_affiliates
   where id=v_aff and deleted_at is null;
  if v_aff_customer is null then raise exception 'That affiliate was not found'; end if;
  if not public.is_eligible_affiliate(v_aff_customer) then
   raise exception 'That affiliate is not eligible'; end if;
  v_explicit:=true;
 else
  -- Nobody chose: leave whatever the exchange already had.
  v_aff:=e.exchange_affiliate_id; v_explicit:=e.affiliate_selection_explicit;
 end if;

 -- ---- who issued it ------------------------------------------------------
 v_raised:=coalesce(p_raised_by,auth.uid());
 if not exists(select 1 from public.profiles
                where id=v_raised and coalesce(is_active,true) and deleted_at is null
                  and role in ('owner','admin','manager','staff')) then
  raise exception 'The person raising this exchange is not an active user'; end if;

 -- ---- when ---------------------------------------------------------------
 v_date:=coalesce(p_exchange_date,public.sg_today());
 if v_date>public.sg_today() then
  raise exception 'An exchange cannot be dated in the future'; end if;

 update public.product_exchanges
    set exchange_affiliate_id=v_aff, affiliate_selection_explicit=v_explicit,
        raised_by=v_raised, exchange_date=v_date,
        notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes)
  where id=e.id;

 perform public.write_audit_ex('product_exchanges',e.id,'exchange_details_set',
   jsonb_build_object('affiliate_id',e.exchange_affiliate_id,'raised_by',e.raised_by,'exchange_date',e.exchange_date),
   jsonb_build_object('affiliate_id',v_aff,'affiliate_explicit',v_explicit,'raised_by',v_raised,
     'exchange_date',v_date,'served_by',p_staff),'exchanges',null,e.processing_store_id);

 return jsonb_build_object('exchange_id',e.id,'served_by_count',v_n,
   'affiliate_id',v_aff,'affiliate_explicit',v_explicit,
   'raised_by',v_raised,'exchange_date',v_date);
end $$;
grant execute on function public.set_exchange_details(uuid,jsonb,jsonb,uuid,date,text) to authenticated;

-- ---------------------------------------------------------------------
-- Create and attribute in ONE transaction.
--
-- A new name, taking a single payload, rather than extra arguments on the three
-- existing creators: adding arguments makes an overload, and this repository
-- has been broken twice by exactly that (243, and the live create_invoice 302
-- repairs). The existing creators are called unchanged.
-- ---------------------------------------------------------------------
create or replace function public.create_exchange_with_details(p_kind text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_res jsonb; v_id uuid;
begin
 if p_kind not in ('product','bundle','bundle_component') then
  raise exception 'Unknown exchange kind %',p_kind; end if;

 if p_kind='product' then
  v_res:=public.create_product_exchange(
    (p_payload->>'original_invoice_id')::uuid,(p_payload->>'processing_store_id')::uuid,
    coalesce(p_payload->'returned','[]'::jsonb),coalesce(p_payload->'replacement','[]'::jsonb),
    coalesce(p_payload->'payments','[]'::jsonb),p_payload->>'reason',p_payload->>'notes',
    coalesce((p_payload->>'foc')::boolean,false),
    nullif(p_payload->>'foc_reason_id','')::uuid,p_payload->>'foc_reason');
 elsif p_kind='bundle' then
  v_res:=public.create_bundle_exchange(
    (p_payload->>'original_invoice_id')::uuid,(p_payload->>'processing_store_id')::uuid,
    (p_payload->>'original_invoice_item_id')::uuid,(p_payload->>'new_promotion_id')::uuid,
    coalesce(p_payload->'payments','[]'::jsonb),p_payload->>'reason',p_payload->>'notes');
 else
  v_res:=public.create_bundle_component_exchange(
    (p_payload->>'original_invoice_id')::uuid,(p_payload->>'processing_store_id')::uuid,
    (p_payload->>'original_invoice_item_id')::uuid,(p_payload->>'component_product_id')::uuid,
    coalesce((p_payload->>'component_qty')::int,1),
    coalesce(p_payload->'replacement','[]'::jsonb),
    coalesce(p_payload->'payments','[]'::jsonb),p_payload->>'reason',p_payload->>'notes');
 end if;

 v_id:=coalesce(nullif(v_res->>'exchange_id','')::uuid,nullif(v_res->>'id','')::uuid);
 if v_id is null then
  raise exception 'The exchange was created but its id could not be read back'; end if;

 -- Same transaction: an exchange can never exist without its attribution.
 return v_res || public.set_exchange_details(v_id,
   coalesce(p_payload->'served_by','[]'::jsonb),
   coalesce(p_payload->'affiliate','{"mode":"inherit"}'::jsonb),
   nullif(p_payload->>'raised_by','')::uuid,
   nullif(p_payload->>'exchange_date','')::date,
   p_payload->>'notes');
end $$;
grant execute on function public.create_exchange_with_details(text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
