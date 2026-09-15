begin;
-- =====================================================================
-- A STAFF LOGIN CANNOT MAKE ITSELF AN AFFILIATE
--
-- AuthContext states the rule the whole app is built on: a login is either
-- Staff (a profiles row) or an Affiliate (an affiliate_accounts row), never
-- both. complete_affiliate_onboarding never checked it. It confirmed the email
-- and parsed the phone, then created the account for whoever called it --
-- including an owner who already has a profiles row.
--
-- /affiliate/verify is a public route, so a signed-in staff member could reach
-- the form and submit it. That produced a live referral code held by a member
-- of staff, a duplicate customer row under their own work email, and a person
-- sitting in their own commission chain. Reproduced end to end: status active,
-- one affiliate_accounts row against the owner's login, one new customer.
--
-- The check belongs here rather than only on the page, because the RPC is
-- reachable with any signed-in token regardless of what the browser renders.
-- =====================================================================
do $do$
declare f text;
begin
  select pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure) into f;
  if position('is a staff login' in f) = 0 then
    f := replace(f,
      '  if v_uid is null then raise exception ''Not authenticated''; end if;',
      '  if v_uid is null then raise exception ''Not authenticated''; end if;
  -- Staff or Affiliate, never both. Checked before anything is written, so a
  -- refused attempt leaves no customer, membership or claim behind.
  if exists (select 1 from public.profiles where id = v_uid) then
    raise exception ''STAFF_ACCOUNT: This is a staff login, so it cannot also be an affiliate account. Sign out and use a personal email address, or ask an Owner to set the affiliate up against the right customer record.''
      using errcode = ''42501'';
  end if;');
    if position('is a staff login' in f) = 0 then
      raise exception 'complete_affiliate_onboarding does not match what 320 expects — align it by hand'; end if;
    execute f;
    raise notice 'complete_affiliate_onboarding now refuses a staff login';
  end if;
end $do$;

-- ---------------------------------------------------------------------
-- Existing accounts that already hold both, for review.
--
-- Read-only. Nothing is unlinked automatically: whether such an account is a
-- mistake to reverse or a real person who needs their records separated is a
-- decision about somebody's commission, not a migration's business.
-- ---------------------------------------------------------------------
create or replace function public.staff_logins_with_affiliate_accounts()
returns table (
  auth_user_id uuid, staff_name text, staff_email text, staff_role text,
  affiliate_customer_id uuid, affiliate_customer_name text, referral_code text,
  account_status text, claimed_at timestamptz, referrals_made bigint, commission_earned numeric)
language sql stable security definer set search_path to 'public' as $$
  select p.id, p.full_name, p.email, p.role::text,
         a.customer_id, c.full_name, ca.referral_code,
         a.status, a.created_at,
         (select count(*) from public.customers x where x.referred_by = a.customer_id and x.deleted_at is null),
         coalesce((select sum(k.commission_amount) from public.commissions k
                    where k.referrer_customer_id = a.customer_id and k.status = 'earned'), 0)
    from public.profiles p
    join public.affiliate_accounts a on a.auth_user_id = p.id
    join public.customers c on c.id = a.customer_id
    left join public.customer_affiliates ca on ca.id = a.affiliate_id
   where public.is_owner_or_manager()
   order by p.full_name
$$;
grant execute on function public.staff_logins_with_affiliate_accounts() to authenticated;

notify pgrst,'reload schema';
commit;
