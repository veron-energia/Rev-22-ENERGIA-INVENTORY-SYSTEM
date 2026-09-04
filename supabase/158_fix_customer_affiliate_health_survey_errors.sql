-- =====================================================================
-- ENERGIA — FIX customers.updated_at + FINISH AFFILIATE ACCOUNT CLAIMS
--
-- Root cause of the two live errors: reassign_customer_referrer() (mig 155) and
-- the submit_health_survey() enrichment UPDATE (mig 157) both write
-- customers.updated_at, but the deployed customers table only has created_at —
-- so both fail with: column "updated_at" of relation "customers" does not exist.
--
-- This migration:
--   1. Adds customers.updated_at (idempotent) + a reusable set_updated_at()
--      BEFORE UPDATE trigger so timestamps are maintained automatically. Once the
--      column exists, the already-deployed 155/157 functions work unchanged.
--   2. Adds rejected_by / rejected_at / rejection_reason to affiliate_account_claims.
--   3. Completes the claims workflow: reject_affiliate_account_claim(),
--      delete_affiliate_account_claim(), affiliate_rejected_claims(); hardens
--      resolve_affiliate_account_claim() (row lock, idempotent, no rejected→resolved)
--      and reassign_customer_referrer() (row lock, validate new referrer); and makes
--      complete_affiliate_onboarding() honour a prior rejection instead of re-parking
--      a pending claim.
--
-- Preserves: the canonical-phone work (155/157), the existing Tier1/Tier2
-- commission engine, referral-ownership locking (first-valid-referral-wins), the
-- one-pending-claim index (156), and all financial history. Additive & idempotent.
-- Run AFTER 157.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. customers.updated_at + reusable trigger
-- =====================================================================
alter table public.customers add column if not exists updated_at timestamptz;
update public.customers set updated_at = coalesce(updated_at, created_at, now()) where updated_at is null;
alter table public.customers alter column updated_at set default now();
alter table public.customers alter column updated_at set not null;

-- Generic BEFORE UPDATE stamp (no equivalent existed in the schema). Reusable by
-- any table with an updated_at column.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $function$
begin
  new.updated_at := now();
  return new;
end $function$;

drop trigger if exists trg_customers_set_updated_at on public.customers;
create trigger trg_customers_set_updated_at
  before update on public.customers
  for each row execute function public.set_updated_at();

-- =====================================================================
-- 2. affiliate_account_claims: rejection bookkeeping
-- =====================================================================
alter table public.affiliate_account_claims add column if not exists rejected_by uuid references public.profiles(id);
alter table public.affiliate_account_claims add column if not exists rejected_at timestamptz;
alter table public.affiliate_account_claims add column if not exists rejection_reason text;

-- =====================================================================
-- 3. reassign_customer_referrer — hardened (row lock + validate new referrer).
--    Keeps: Owner/Manager only, reason required, first-valid-referral-wins
--    override, cycle protection, audit. updated_at now resolves correctly.
-- =====================================================================
create or replace function public.reassign_customer_referrer(
  p_customer_id uuid, p_new_referrer_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_old uuid; v_cur uuid; v_hops int := 0;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can correct a referrer'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'A reason is required'; end if;
  if p_customer_id = p_new_referrer_id then raise exception 'A customer cannot be referred by themselves'; end if;

  -- Lock the customer row so concurrent corrections can't race.
  select referred_by into v_old from public.customers where id = p_customer_id for update;
  if not found then raise exception 'Customer not found'; end if;

  if p_new_referrer_id is not null then
    if not exists (select 1 from public.customers where id = p_new_referrer_id and deleted_at is null) then
      raise exception 'The selected new referrer was not found or is inactive';
    end if;
    -- Cycle protection across the whole chain.
    v_cur := p_new_referrer_id;
    while v_cur is not null loop
      if v_cur = p_customer_id then raise exception 'That change would create a circular referral chain'; end if;
      v_hops := v_hops + 1; if v_hops > 100 then exit; end if;
      select referred_by into v_cur from public.customers where id = v_cur;
    end loop;
  end if;

  perform set_config('energia.allow_referrer_reassign', '1', true);
  update public.customers set referred_by = p_new_referrer_id where id = p_customer_id;  -- updated_at via trigger
  perform set_config('energia.allow_referrer_reassign', '0', true);

  perform public.write_audit_ex('customers', p_customer_id, 'referrer_corrected',
    jsonb_build_object('referred_by', v_old), jsonb_build_object('referred_by', p_new_referrer_id),
    'affiliate', p_reason, null);

  return jsonb_build_object('ok', true, 'old_referrer', v_old, 'new_referrer', p_new_referrer_id);
end $function$;

-- =====================================================================
-- 4. complete_affiliate_onboarding — honour a prior rejection; don't re-park a
--    pending claim for a rejected user. Otherwise identical to mig 155.
-- =====================================================================
create or replace function public.complete_affiliate_onboarding(
  p_first_name text, p_last_name text, p_phone text, p_agree boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_uid uuid := auth.uid();
  v_email text; v_confirmed timestamptz; v_phone text; v_name text;
  v_cust uuid; v_aff public.customer_affiliates%rowtype; v_acct public.affiliate_accounts%rowtype;
  v_email_matches int; v_phone_cust uuid; v_phone_email text; v_code text; v_suspended boolean := false;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if not coalesce(p_agree, false) then raise exception 'You must agree to the Affiliate terms to continue'; end if;

  select email, email_confirmed_at into v_email, v_confirmed from auth.users where id = v_uid;
  if v_email is null then raise exception 'No email on the authenticated account'; end if;
  if v_confirmed is null then raise exception 'Please verify your email before completing signup'; end if;

  v_email := lower(btrim(v_email));
  v_phone := public.normalize_customer_phone(p_phone);
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  if v_name = '' then v_name := split_part(v_email,'@',1); end if;

  -- Already onboarded? Idempotent.
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id = v_acct.affiliate_id;
    return jsonb_build_object('status', case when v_aff.manually_suspended then 'suspended' else 'active' end,
      'customer_id', v_acct.customer_id, 'referral_code', v_aff.referral_code, 'already', true);
  end if;

  -- Matching signals (canonical phone).
  select count(*) into v_email_matches from public.customers
   where lower(btrim(email)) = v_email and deleted_at is null and is_active = true;
  select id, lower(btrim(email)) into v_phone_cust, v_phone_email from public.customers
   where public.normalize_customer_phone(phone) = v_phone and deleted_at is null
   order by created_at limit 1;

  if v_email_matches = 0 and v_phone_cust is null then
    insert into public.customers (full_name, phone, email, is_active)
      values (v_name, coalesce(nullif(v_phone,''), 'AFF-'||substr(v_uid::text,1,8)), v_email, true)
      returning id into v_cust;
  elsif v_email_matches = 1 and v_phone_cust is not null and v_phone_email = v_email then
    v_cust := v_phone_cust;
  elsif v_email_matches = 1 and v_phone_cust is null then
    select id into v_cust from public.customers
     where lower(btrim(email)) = v_email and deleted_at is null and is_active = true limit 1;
  else
    -- Ambiguous. If this user was already rejected, do NOT re-park a pending
    -- claim — tell them it was unsuccessful. Otherwise park exactly one pending.
    if exists (select 1 from public.affiliate_account_claims where auth_user_id = v_uid and status = 'rejected') then
      return jsonb_build_object('status', 'rejected',
        'message', 'Account verification was unsuccessful. Please contact Energia for assistance.');
    end if;
    insert into public.affiliate_account_claims (auth_user_id, entered_phone, verified_email, candidate_customer_id)
      values (v_uid, v_phone, v_email, v_phone_cust)
      on conflict do nothing;                         -- one-pending index (mig 156)
    return jsonb_build_object('status', 'pending_verification',
      'message', 'We found an existing Energia customer record that needs identity verification. Please contact Energia to complete account linking.');
  end if;

  select * into v_aff from public.customer_affiliates where customer_id = v_cust and deleted_at is null;
  if not found then
    v_code := public.generate_affiliate_referral_code();
    insert into public.customer_affiliates (customer_id, status, manually_suspended, activated_at, referral_code)
      values (v_cust, 'active', false, now(), v_code)
      returning * into v_aff;
  else
    v_suspended := v_aff.manually_suspended;
    if v_aff.referral_code is null then
      update public.customer_affiliates set referral_code = public.generate_affiliate_referral_code(), updated_at = now()
       where id = v_aff.id returning * into v_aff;
    end if;
  end if;

  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status, last_login_at)
    values (v_uid, v_cust, v_aff.id, 'claimed', now())
    returning * into v_acct;

  begin
    perform public.write_audit_ex('affiliate_accounts', v_acct.id, 'affiliate_portal_claimed', null,
      jsonb_build_object('customer_id', v_cust, 'affiliate_id', v_aff.id, 'auth_user_id', v_uid,
        'new_customer', (v_email_matches = 0 and v_phone_cust is null)), 'affiliate', null, null);
  exception when others then null; end;

  return jsonb_build_object('status', case when v_suspended then 'suspended' else 'active' end,
    'customer_id', v_cust, 'referral_code', v_aff.referral_code, 'already', false);
end $function$;

-- =====================================================================
-- 5. resolve_affiliate_account_claim — hardened: lock the row, idempotent on a
--    double-click, only pending→resolved (never rejected→resolved).
-- =====================================================================
create or replace function public.resolve_affiliate_account_claim(
  p_claim_id uuid, p_customer_id uuid, p_note text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_claim public.affiliate_account_claims%rowtype; v_aff public.customer_affiliates%rowtype; v_acct uuid; v_code text;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can resolve account claims'; end if;
  if p_note is null or btrim(p_note) = '' then raise exception 'A verification note is required'; end if;

  select * into v_claim from public.affiliate_account_claims where id = p_claim_id for update;
  if not found then raise exception 'Claim not found'; end if;

  if v_claim.status = 'resolved' then
    return jsonb_build_object('ok', false, 'already', true, 'message', 'This claim has already been resolved.');
  end if;
  if v_claim.status = 'rejected' then
    raise exception 'This claim was rejected and cannot be resolved. Delete it to allow a fresh request.';
  end if;
  if exists (select 1 from public.affiliate_accounts where auth_user_id = v_claim.auth_user_id) then
    -- The login is already linked (e.g. resolved via another path). Mark the
    -- claim resolved for tidiness and report the safe state.
    update public.affiliate_account_claims
       set status='resolved', resolved_by=auth.uid(), resolved_at=now(),
           resolution_note=coalesce(resolution_note, p_note)
     where id = p_claim_id;
    return jsonb_build_object('ok', false, 'already', true, 'message', 'This login is already linked to an affiliate account.');
  end if;

  select * into v_aff from public.customer_affiliates where customer_id = p_customer_id and deleted_at is null;
  if not found then
    v_code := public.generate_affiliate_referral_code();
    insert into public.customer_affiliates (customer_id, status, manually_suspended, activated_at, referral_code)
      values (p_customer_id, 'active', false, now(), v_code) returning * into v_aff;
  elsif v_aff.referral_code is null then
    update public.customer_affiliates set referral_code = public.generate_affiliate_referral_code(), updated_at = now()
     where id = v_aff.id returning * into v_aff;
  end if;

  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status, last_login_at)
    values (v_claim.auth_user_id, p_customer_id, v_aff.id, 'claimed', now()) returning id into v_acct;

  update public.affiliate_account_claims
     set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolution_note = p_note
   where id = p_claim_id;

  perform public.write_audit_ex('affiliate_account_claims', p_claim_id, 'affiliate_claim_resolved', null,
    jsonb_build_object('customer_id', p_customer_id, 'affiliate_id', v_aff.id), 'affiliate', p_note, null);

  return jsonb_build_object('ok', true, 'customer_id', p_customer_id, 'affiliate_id', v_aff.id,
    'suspended', v_aff.manually_suspended);
end $function$;

-- =====================================================================
-- 6. reject_affiliate_account_claim — pending → rejected (Owner/Manager, reason).
--    Keeps the row for audit; blocks automatic re-parking (see onboarding).
-- =====================================================================
create or replace function public.reject_affiliate_account_claim(
  p_claim_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_claim public.affiliate_account_claims%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can reject account claims'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'A reason is required'; end if;

  select * into v_claim from public.affiliate_account_claims where id = p_claim_id for update;
  if not found then raise exception 'Claim not found'; end if;
  if v_claim.status = 'resolved' then raise exception 'A resolved claim cannot be rejected.'; end if;
  if v_claim.status = 'rejected' then
    return jsonb_build_object('ok', false, 'already', true, 'message', 'This claim has already been rejected.');
  end if;

  update public.affiliate_account_claims
     set status = 'rejected', rejected_by = auth.uid(), rejected_at = now(), rejection_reason = p_reason
   where id = p_claim_id;

  perform public.write_audit_ex('affiliate_account_claims', p_claim_id, 'affiliate_claim_rejected', null,
    jsonb_build_object('auth_user_id', v_claim.auth_user_id, 'candidate_customer_id', v_claim.candidate_customer_id),
    'affiliate', p_reason, null);

  return jsonb_build_object('ok', true);
end $function$;

-- =====================================================================
-- 7. delete_affiliate_account_claim — remove a pending/rejected request only.
--    Never a resolved claim; never touches customer / auth / affiliate / commissions.
-- =====================================================================
create or replace function public.delete_affiliate_account_claim(p_claim_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_claim public.affiliate_account_claims%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can delete account claims'; end if;
  select * into v_claim from public.affiliate_account_claims where id = p_claim_id for update;
  if not found then raise exception 'Claim not found'; end if;
  if v_claim.status = 'resolved' then
    raise exception 'A resolved claim cannot be deleted (it is part of the account history).';
  end if;

  perform public.write_audit_ex('affiliate_account_claims', p_claim_id, 'affiliate_claim_deleted',
    jsonb_build_object('status', v_claim.status, 'candidate_customer_id', v_claim.candidate_customer_id,
                       'auth_user_id', v_claim.auth_user_id), null, 'affiliate', null, null);

  delete from public.affiliate_account_claims where id = p_claim_id;
  return jsonb_build_object('ok', true);
end $function$;

-- =====================================================================
-- 8. affiliate_rejected_claims — Owner/Manager view of rejected requests.
-- =====================================================================
create or replace function public.affiliate_rejected_claims()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_rows jsonb;
begin
  if not public.is_owner_or_manager() then raise exception 'Owner or Manager only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'claim_id', cl.id, 'verified_email', cl.verified_email, 'entered_phone', cl.entered_phone,
    'candidate_customer_id', cl.candidate_customer_id,
    'candidate_name', (select full_name from public.customers where id = cl.candidate_customer_id),
    'rejected_at', cl.rejected_at, 'rejection_reason', cl.rejection_reason,
    'created_at', cl.created_at) order by cl.rejected_at desc nulls last, cl.created_at desc), '[]'::jsonb) into v_rows
  from public.affiliate_account_claims cl where cl.status = 'rejected';
  return v_rows;
end $function$;

-- =====================================================================
-- 9. Grants.
-- =====================================================================
grant execute on function public.reassign_customer_referrer(uuid,uuid,text) to authenticated;
grant execute on function public.complete_affiliate_onboarding(text,text,text,boolean) to authenticated;
grant execute on function public.resolve_affiliate_account_claim(uuid,uuid,text) to authenticated;
grant execute on function public.reject_affiliate_account_claim(uuid,text) to authenticated;
grant execute on function public.delete_affiliate_account_claim(uuid) to authenticated;
grant execute on function public.affiliate_rejected_claims() to authenticated;

-- =====================================================================
-- 10. Assertions.
-- =====================================================================
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='customers' and column_name='updated_at'
                    and is_nullable='NO') then
    raise exception 'customers.updated_at missing or nullable'; end if;
  if not exists (select 1 from pg_trigger where tgname='trg_customers_set_updated_at') then
    raise exception 'customers updated_at trigger missing'; end if;
  if not exists (select 1 from pg_proc where proname='reject_affiliate_account_claim') then
    raise exception 'reject_affiliate_account_claim missing'; end if;
  if not exists (select 1 from pg_proc where proname='delete_affiliate_account_claim') then
    raise exception 'delete_affiliate_account_claim missing'; end if;
  raise notice 'Confirmed: customers.updated_at + trigger installed; claim reject/delete/resolve hardened.';
end $$;

notify pgrst, 'reload schema';
