begin;
-- =====================================================================
-- STAFF MAY LOOK UP AN AFFILIATE'S REFERRAL LINK
--
-- The Affiliates page was Owner/Manager territory: affiliate_admin_directory
-- returns commission, balances and referral counts, and refuses everyone else.
-- Staff at the till still need to find an affiliate, see whether their link
-- is usable, and hand over the QR code or the link. That is all this returns.
--
-- Role matrix
--   anonymous       refused
--   staff           this function: name, code, status, whether the link is
--                   usable. Nothing about money, purchases, health, claims,
--                   accounts or notes. Read only; every mutation elsewhere
--                   still checks is_owner_or_manager().
--   manager/owner   unchanged: affiliate_admin_directory and the mutations,
--                   within the scope they already have.
--
-- Server-side search and paging, because the directory is company-wide and
-- the API row limit would otherwise truncate it silently. Nothing here
-- creates an affiliate or rotates a referral code: it reads the code that is
-- already on the row, the same one the portal shows the affiliate.
--
-- Additive. Idempotent.
-- =====================================================================
create or replace function public.affiliate_staff_directory(
  p_search text default null,
  p_limit  integer default 50,
  p_offset integer default 0
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q text := nullif(btrim(coalesce(p_search, '')), '');
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_rows jsonb; v_total bigint;
begin
  -- An active staff login of any role. Not a public endpoint.
  if auth.uid() is null or not exists (
       select 1 from public.profiles p where p.id = auth.uid() and p.is_active and p.deleted_at is null) then
    raise exception 'Sign in to view the affiliate directory' using errcode = '42501';
  end if;

  with matched as (
    select ca.customer_id, c.full_name, ca.referral_code,
           case when ca.manually_suspended then 'suspended' else ca.status end as status,
           -- The same rule public_affiliate_referral_info applies when a
           -- customer opens the link: usable means it will register a referral.
           (ca.referral_code is not null and not ca.manually_suspended and ca.status = 'active') as link_usable
      from public.customer_affiliates ca
      join public.customers c on c.id = ca.customer_id and c.deleted_at is null
     where ca.deleted_at is null
       and (v_q is null or c.full_name ilike '%' || v_q || '%' or ca.referral_code ilike '%' || v_q || '%')
  )
  select count(*),
         coalesce((select jsonb_agg(to_jsonb(o)) from (
            select * from matched order by full_name, customer_id offset v_offset limit v_limit) o), '[]'::jsonb)
    into v_total, v_rows
    from matched;

  return jsonb_build_object('rows', v_rows, 'total', v_total, 'limit', v_limit, 'offset', v_offset);
end $$;

revoke all on function public.affiliate_staff_directory(text, integer, integer) from public, anon;
grant execute on function public.affiliate_staff_directory(text, integer, integer) to authenticated;
comment on function public.affiliate_staff_directory(text, integer, integer) is
 'Read-only affiliate lookup for any active staff login: name, referral code, status and whether the link is usable. No financial, purchase, claim or account detail.';
commit;
