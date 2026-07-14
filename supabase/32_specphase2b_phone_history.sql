-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 2B: Customer phone history
--
-- * customers.phone is already NOT NULL UNIQUE (global current-number
--   uniqueness — spec 2.4). We keep that.
-- * New customer_phone_history table: previous numbers, not unique, may
--   later be reused as another customer's current number.
-- * change_customer_phone(): moves the old number into history, sets the
--   new one, requires a reason, audited. Blocks if the new number is in
--   use as another customer's CURRENT number.
--
-- Additive + idempotent. Run AFTER 31_specphase1_foundation.sql.
-- =====================================================================

set check_function_bodies = off;

create table if not exists public.customer_phone_history (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  phone text not null,
  changed_by uuid references public.profiles(id),
  reason text,
  created_at timestamptz not null default now()
);
create index if not exists idx_cph_customer on public.customer_phone_history(customer_id);
create index if not exists idx_cph_phone on public.customer_phone_history(phone);

alter table public.customer_phone_history enable row level security;
drop policy if exists "read phone history" on public.customer_phone_history;
-- Staff/Admin operational read is fine (needed to find a customer by old
-- number); complete-profile gating is handled in the app for the richer view.
create policy "read phone history" on public.customer_phone_history for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- Change the current phone number. Old number -> history. Reason required.
-- ---------------------------------------------------------------------
create or replace function public.change_customer_phone(
  p_customer_id uuid, p_new_phone text, p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare v_old text; v_clash uuid;
begin
  if p_new_phone is null or length(trim(p_new_phone)) = 0 then
    raise exception 'New phone number is required'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required to change a customer phone number'; end if;

  select phone into v_old from public.customers where id = p_customer_id for update;
  if v_old is null then raise exception 'Customer not found'; end if;
  if trim(p_new_phone) = v_old then raise exception 'That is already the current number'; end if;

  -- New number must not be another customer's CURRENT number (global unique).
  select id into v_clash from public.customers
    where phone = trim(p_new_phone) and id <> p_customer_id and deleted_at is null limit 1;
  if v_clash is not null then
    raise exception 'That number is already in use as another customer''s current number'; end if;

  -- Move the old number into history, then set the new current number.
  insert into public.customer_phone_history (customer_id, phone, changed_by, reason)
  values (p_customer_id, v_old, auth.uid(), trim(p_reason));

  update public.customers set phone = trim(p_new_phone) where id = p_customer_id;

  perform public.write_audit_ex('customers', p_customer_id, 'customer_phone_changed',
    jsonb_build_object('phone', v_old), jsonb_build_object('phone', trim(p_new_phone)),
    'customers', trim(p_reason));
end; $$;

notify pgrst, 'reload schema';
