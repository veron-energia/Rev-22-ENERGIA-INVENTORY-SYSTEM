begin;
-- =====================================================================
-- CREATING A CUSTOMER WITHOUT LEAVING THE INVOICE
--
-- Staff had to abandon a half-built invoice, go to Customers, create the
-- person, and come back to a blank form. This adds the same creation to the
-- invoice screens — the same fields, the same validation, the same rules —
-- with two things the Customers page does not need and this does:
--
--   * A look for people already on file under that phone, so the answer to
--     "is this already someone?" is in front of staff before they add a
--     second record rather than after.
--   * Protection against the same creation arriving twice. A lost response
--     and a second click are the same thing from here, and a disabled button
--     does not survive either.
--
-- Nothing about the phone rules changes. Up to three non-deleted customers may
-- share a number, deleted customers and historical numbers do not count toward
-- it, and two different people on one phone stay two people.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Who is already on file under this phone.
--
-- Only what a person needs to recognise somebody: the name, a masked phone and
-- when they were added. Not their balances, spending or history — this answers
-- "is this the same person", not "tell me about them".
-- ---------------------------------------------------------------------
create or replace function public.customer_match_candidates(p_phone text, p_name text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_norm text; v_rows jsonb; v_used int;
begin
  -- Staff only. The Customers page sits behind the staff guard, and customer
  -- records are not an affiliate's to search; RLS on the table itself is open
  -- to any authenticated user, which is wider than this needs to be.
  if not exists (select 1 from public.profiles
                  where id = auth.uid() and is_active and deleted_at is null) then
    raise exception 'You do not have permission to look up customers' using errcode='42501'; end if;

  v_norm := public.normalize_customer_phone(p_phone);
  if coalesce(v_norm,'') = '' then
    return jsonb_build_object('candidates','[]'::jsonb,'used',0,'capacity',3,'remaining',3); end if;

  select count(*) into v_used from public.customers
   where deleted_at is null and public.normalize_customer_phone(phone) = v_norm;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'full_name', c.full_name,
           -- Masked: enough to confirm the number, not enough to harvest it.
           'phone_tail', right(coalesce(c.phone,''), 4),
           'created_at', c.created_at,
           'name_matches', c.id = any(public.customer_phone_name_matches(p_phone, coalesce(p_name,'')))
         ) order by c.created_at), '[]'::jsonb)
    into v_rows
    from public.customers c
   where c.deleted_at is null
     and public.normalize_customer_phone(c.phone) = v_norm;

  return jsonb_build_object(
    'candidates', v_rows,
    'used', v_used,
    'capacity', 3,
    'remaining', greatest(3 - v_used, 0),
    'normalized_phone', v_norm);
end $$;
grant execute on function public.customer_match_candidates(text,text) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Creating one, once.
--
-- The same columns the Customers page writes, so the two cannot drift apart.
-- The phone capacity rule is the trigger's, not this function's; it is left to
-- raise its own message.
--
-- A repeated request id returns the customer the first call created rather than
-- a second record. Two simultaneous requests race on the unique index, and the
-- loser reads the winner's row instead of failing.
-- ---------------------------------------------------------------------
create table if not exists public.customer_create_requests (
  request_id uuid primary key,
  customer_id uuid not null references public.customers(id) on delete cascade,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
alter table public.customer_create_requests enable row level security;

create or replace function public.create_customer_quick(
  p_first_name text, p_last_name text, p_phone text,
  p_email text default null, p_date_of_birth date default null,
  p_gender text default null, p_gender_other text default null,
  p_occupation text default null, p_notes text default null,
  p_referred_by uuid default null,
  p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid; v_existing uuid; v_full text;
begin
  if not exists (select 1 from public.profiles
                  where id = auth.uid() and is_active and deleted_at is null) then
    raise exception 'You do not have permission to add customers' using errcode='42501'; end if;

  -- A retry, or a second click, returns what the first call made.
  if p_request_id is not null then
    select customer_id into v_existing
      from public.customer_create_requests where request_id = p_request_id;
    if found then
      return jsonb_build_object('customer_id', v_existing, 'replayed', true); end if;
  end if;

  if coalesce(btrim(p_first_name),'') = '' then
    raise exception 'A first name is required'; end if;
  if coalesce(btrim(p_phone),'') = '' then
    raise exception 'Phone number is required. Up to 3 non-deleted customers may share a number.'; end if;

  v_full := public.join_person_name(p_first_name, p_last_name);

  insert into public.customers
    (first_name, last_name, full_name, phone, email, date_of_birth,
     gender, gender_other, occupation, notes, is_active, referred_by, is_referrer)
  values
    (btrim(p_first_name), nullif(btrim(coalesce(p_last_name,'')),''), v_full,
     btrim(p_phone), nullif(btrim(coalesce(p_email,'')),''), p_date_of_birth,
     nullif(btrim(coalesce(p_gender,'')),'')::public.customer_gender,
     case when p_gender = 'other' then nullif(btrim(coalesce(p_gender_other,'')),'') end,
     nullif(btrim(coalesce(p_occupation,'')),''),
     nullif(btrim(coalesce(p_notes,'')),''),
     true, p_referred_by, true)
  returning id into v_id;

  if p_request_id is not null then
    begin
      insert into public.customer_create_requests(request_id, customer_id, created_by)
      values (p_request_id, v_id, auth.uid());
    exception when unique_violation then
      -- Another call with this id won the race; keep its customer, not ours.
      select customer_id into v_existing
        from public.customer_create_requests where request_id = p_request_id;
      raise exception 'DUPLICATE_REQUEST: that customer was already created (%)', v_existing;
    end;
  end if;

  perform public.write_audit('customers', v_id, 'customer_created_from_invoice', null,
    jsonb_build_object('full_name', v_full, 'request_id', p_request_id));

  return jsonb_build_object('customer_id', v_id, 'full_name', v_full, 'replayed', false);
end $$;
grant execute on function public.create_customer_quick(text,text,text,text,date,text,text,text,text,uuid,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
