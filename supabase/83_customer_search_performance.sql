-- =====================================================================
-- ENERGIA — CUSTOMER SEARCH PERFORMANCE
--
-- The Customers page was loading the entire customer table into the browser
-- and filtering it there. That is fine for a few hundred rows and hopeless at
-- tens of thousands — let alone a million. Searching moves to the database.
--
--   * pg_trgm GIN indexes so `ilike '%term%'` uses an index instead of
--     scanning every row. Without these, substring search is a sequential
--     scan and gets linearly slower as the table grows.
--   * search_customers() returns one page of matches plus the total count,
--     so the UI can paginate without ever holding the whole table.
--
-- Additive and idempotent. Run AFTER 82.
-- =====================================================================

create extension if not exists pg_trgm;

-- Trigram indexes for substring search on the fields staff actually search.
create index if not exists idx_customers_trgm_name
  on public.customers using gin (full_name gin_trgm_ops);
create index if not exists idx_customers_trgm_phone
  on public.customers using gin (phone gin_trgm_ops);
create index if not exists idx_customers_trgm_email
  on public.customers using gin (email gin_trgm_ops);
create index if not exists idx_customers_trgm_notes
  on public.customers using gin (notes gin_trgm_ops);
-- Old phone numbers are searchable too.
create index if not exists idx_cust_phone_hist_trgm
  on public.customer_phone_history using gin (phone gin_trgm_ops);
-- Supports the default (unsearched) listing order.
create index if not exists idx_customers_created_at
  on public.customers (created_at desc) where deleted_at is null;

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- One page of customers, searched in the database.
--   p_query  — matches name, phone, current or OLD phone, email, or the
--              legacy customer id held in notes
--   p_source — a source option id, or '__none' for "no source recorded"
-- Returns the page plus total_count so the caller can show "x of y".
-- ---------------------------------------------------------------------
-- The result type gained first_name and last_name in a later migration. Because
-- "83_" sorts AFTER "125_" as text, a filename-ordered deploy runs this file
-- last, and "create or replace" cannot change a return type — so it would abort
-- the deploy. The old definition is dropped first, and migration 126 adds the
-- name columns back afterwards whatever order things run in.
drop function if exists public.search_customers(text, text, integer, integer);

create or replace function public.search_customers(
  p_query text default null,
  p_source text default null,
  p_limit integer default 50,
  p_offset integer default 0)
returns table(
  id uuid, full_name text, phone text, email text, address text, notes text,
  is_active boolean, created_at timestamptz, referred_by uuid, is_referrer boolean,
  date_of_birth date, gender text, gender_other text, occupation text,
  source_option_id uuid, source_label text, source_details text,
  total_count bigint)
language sql stable security definer set search_path to 'public' as $function$
  with q as (
    select nullif(trim(coalesce(p_query,'')),'') as term
  ),
  matched as (
    select c.*
      from public.customers c, q
     where c.deleted_at is null
       and (p_source is null or p_source = ''
            or (p_source = '__none' and c.source_option_id is null)
            or (p_source <> '__none' and c.source_option_id = nullif(p_source,'')::uuid))
       and (q.term is null
            or c.full_name ilike '%' || q.term || '%'
            or c.phone     ilike '%' || q.term || '%'
            or c.email     ilike '%' || q.term || '%'
            or c.notes     ilike '%' || q.term || '%'
            or exists (select 1 from public.customer_phone_history h
                        where h.customer_id = c.id
                          and h.phone ilike '%' || q.term || '%'))
  )
  select m.id, m.full_name, m.phone, m.email, m.address, m.notes,
         m.is_active, m.created_at, m.referred_by, m.is_referrer,
         m.date_of_birth, m.gender::text, m.gender_other, m.occupation,
         m.source_option_id, m.source_label, m.source_details,
         count(*) over () as total_count
    from matched m
   order by m.created_at desc
   limit greatest(coalesce(p_limit, 50), 1)
  offset greatest(coalesce(p_offset, 0), 0)
$function$;

notify pgrst, 'reload schema';
