-- =====================================================================
-- ENERGIA — AFFILIATE SELF-SERVICE PORTAL (backend)
--
-- Turns the manually-activated affiliate programme into a self-service portal:
-- public signup with verified email, a login account distinct from Staff, a
-- permanent per-affiliate referral code/link, and sanitized read-only portal
-- RPCs for network / purchases / earnings / payouts.
--
-- REUSES the existing referral graph (customers.referred_by, customer_referrers)
-- and the existing Tier-1/Tier-2 commission + payout engine UNCHANGED. This
-- migration adds NO commission maths and redefines NO commission function — the
-- portal only READS commissions / commission_payouts. The only referral-graph
-- behaviour changed is protective (locking ownership; see the trigger below).
--
-- Identity model:
--   auth.users → affiliate_accounts → customers → customer_affiliates
-- Affiliates NEVER get a profiles row (profiles = Staff). Portal access is
-- through SECURITY DEFINER RPCs that derive identity from auth.uid(); no broad
-- affiliate SELECT policy is added to customers / commissions / invoices.
--
-- Additive and idempotent. Run AFTER 154.
-- =====================================================================

set check_function_bodies = off;
create extension if not exists pgcrypto;

-- =====================================================================
-- 1. Portal login account: the bridge from a Supabase Auth user to an
--    existing Customer + Affiliate. Passwords live ONLY in Supabase Auth.
-- =====================================================================
create table if not exists public.affiliate_accounts (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  customer_id uuid not null unique references public.customers(id),
  affiliate_id uuid unique references public.customer_affiliates(id),
  status text not null default 'claimed' check (status in ('claimed','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_login_at timestamptz
);
create index if not exists idx_affiliate_accounts_auth on public.affiliate_accounts(auth_user_id);
create index if not exists idx_affiliate_accounts_customer on public.affiliate_accounts(customer_id);
create index if not exists idx_affiliate_accounts_affiliate on public.affiliate_accounts(affiliate_id);

-- Identity that could NOT be safely auto-resolved during onboarding. Owner/
-- Manager verifies and links. This is identity verification, not programme
-- approval — a resolved claim activates the affiliate automatically unless
-- they are manually suspended.
create table if not exists public.affiliate_account_claims (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  entered_phone text,
  verified_email text,
  candidate_customer_id uuid references public.customers(id),
  status text not null default 'pending' check (status in ('pending','resolved','rejected')),
  created_at timestamptz not null default now(),
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  resolution_note text
);
create index if not exists idx_affiliate_claims_auth on public.affiliate_account_claims(auth_user_id);
create index if not exists idx_affiliate_claims_status on public.affiliate_account_claims(status);

-- Lightweight event log for public referral-signup throttling + audit.
create table if not exists public.referral_signup_events (
  id uuid primary key default gen_random_uuid(),
  referral_code text,
  referrer_customer_id uuid,
  new_customer_id uuid,
  normalized_phone text,
  outcome text not null,           -- 'created' | 'duplicate' | 'rejected' | 'honeypot'
  created_at timestamptz not null default now()
);
create index if not exists idx_referral_events_phone_time on public.referral_signup_events(normalized_phone, created_at);
create index if not exists idx_referral_events_code_time on public.referral_signup_events(referral_code, created_at);

-- =====================================================================
-- 2. Referral code on the affiliate record + referral metadata on customers.
-- =====================================================================
alter table public.customer_affiliates add column if not exists referral_code text;
create unique index if not exists uq_customer_affiliates_referral_code on public.customer_affiliates(referral_code) where referral_code is not null;

alter table public.customers add column if not exists referred_at timestamptz;
alter table public.customers add column if not exists referral_source text;
alter table public.customers add column if not exists referral_code_used text;

-- =====================================================================
-- 3. Secure, non-sequential referral code generator (Crockford base32,
--    ambiguous chars removed) + backfill for existing affiliate records.
-- =====================================================================
create or replace function public.generate_affiliate_referral_code()
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_alpha text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; v_code text; v_try int := 0;
begin
  loop
    v_try := v_try + 1;
    v_code := 'EN';
    for i in 1..6 loop
      v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
    end loop;
    exit when not exists (select 1 from public.customer_affiliates where referral_code = v_code);
    if v_try > 50 then raise exception 'Could not allocate a unique referral code'; end if;
  end loop;
  return v_code;
end $function$;

do $$
declare r record;
begin
  for r in select id from public.customer_affiliates where referral_code is null loop
    update public.customer_affiliates set referral_code = public.generate_affiliate_referral_code() where id = r.id;
  end loop;
end $$;

-- =====================================================================
-- 4. Referral-ownership integrity. Extends the old self-referral-only guard:
--    NULL → A is allowed; A → B is blocked (first valid referral wins);
--    self-referral and cycles are blocked. Owner/Manager corrections go
--    through reassign_customer_referrer, which sets a transaction-local
--    override so this trigger permits the change.
-- =====================================================================
create or replace function public.enforce_referral_ownership()
returns trigger language plpgsql set search_path to 'public' as $function$
declare v_cur uuid; v_hops int := 0; v_override boolean;
begin
  if new.referred_by is null then return new; end if;

  -- self-referral
  if new.referred_by = new.id then
    raise exception 'A customer cannot be referred by themselves';
  end if;

  -- immutability (first valid referral wins) unless an authorised reassign
  if tg_op = 'UPDATE' and old.referred_by is not null
     and new.referred_by is distinct from old.referred_by then
    v_override := coalesce(current_setting('energia.allow_referrer_reassign', true), '') = '1';
    if not v_override then
      raise exception 'This customer already has a referrer. Use Correct Referrer (Owner/Manager) to change it.';
    end if;
  end if;

  -- cycle detection: walk up from the proposed referrer; reaching new.id = cycle
  v_cur := new.referred_by;
  while v_cur is not null loop
    if v_cur = new.id then
      raise exception 'Referral change would create a circular referral chain';
    end if;
    v_hops := v_hops + 1;
    if v_hops > 100 then exit; end if;   -- safety valve
    select referred_by into v_cur from public.customers where id = v_cur;
  end loop;

  return new;
end $function$;

drop trigger if exists trg_enforce_referral_ownership on public.customers;
create trigger trg_enforce_referral_ownership
  before insert or update of referred_by on public.customers
  for each row execute function public.enforce_referral_ownership();

-- Owner/Manager audited referrer correction (the only sanctioned A → B path).
create or replace function public.reassign_customer_referrer(
  p_customer_id uuid, p_new_referrer_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_old uuid; v_cur uuid; v_hops int := 0;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can correct a referrer'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'A reason is required'; end if;
  if p_customer_id = p_new_referrer_id then raise exception 'A customer cannot be referred by themselves'; end if;

  select referred_by into v_old from public.customers where id = p_customer_id;
  if not found then raise exception 'Customer not found'; end if;

  if p_new_referrer_id is not null then
    v_cur := p_new_referrer_id;
    while v_cur is not null loop
      if v_cur = p_customer_id then raise exception 'That change would create a circular referral chain'; end if;
      v_hops := v_hops + 1; if v_hops > 100 then exit; end if;
      select referred_by into v_cur from public.customers where id = v_cur;
    end loop;
  end if;

  perform set_config('energia.allow_referrer_reassign', '1', true);
  update public.customers set referred_by = p_new_referrer_id, updated_at = now() where id = p_customer_id;
  perform set_config('energia.allow_referrer_reassign', '0', true);

  perform public.write_audit_ex('customers', p_customer_id, 'referrer_corrected',
    jsonb_build_object('referred_by', v_old), jsonb_build_object('referred_by', p_new_referrer_id),
    'affiliate', p_reason, null);

  return jsonb_build_object('ok', true, 'old_referrer', v_old, 'new_referrer', p_new_referrer_id);
end $function$;

-- =====================================================================
-- 5. Identity helper — the authoritative "who is this affiliate" used by every
--    portal RPC. Derived from auth.uid(); the frontend never supplies it.
-- =====================================================================
create or replace function public.current_affiliate_customer_id()
returns uuid language sql stable security definer set search_path to 'public' as $function$
  select a.customer_id
    from public.affiliate_accounts a
   where a.auth_user_id = auth.uid() and a.status = 'claimed'
   limit 1
$function$;

-- Programme-active predicate (independent of membership): active record, not
-- manually suspended, not deleted.
create or replace function public.affiliate_is_active(p_customer_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $function$
  select exists (
    select 1 from public.customer_affiliates ca
     where ca.customer_id = p_customer_id and ca.deleted_at is null
       and ca.manually_suspended = false and ca.status = 'active')
$function$;

-- =====================================================================
-- 6. Onboarding from a verified Auth session (the /affiliate/join completion).
--    The backend re-checks the Auth user's verified email — client claims are
--    never trusted. Matches existing customers safely; ambiguous identity is
--    parked as a claim for Owner/Manager. Suspended affiliates stay suspended.
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
  v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  if v_name = '' then v_name := split_part(v_email,'@',1); end if;

  -- Already onboarded? Idempotent.
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id = v_acct.affiliate_id;
    return jsonb_build_object('status', case when v_aff.manually_suspended then 'suspended' else 'active' end,
      'customer_id', v_acct.customer_id, 'referral_code', v_aff.referral_code, 'already', true);
  end if;

  -- Matching signals (normalized).
  select count(*) into v_email_matches from public.customers
   where lower(btrim(email)) = v_email and deleted_at is null and is_active = true;
  select id, lower(btrim(email)) into v_phone_cust, v_phone_email from public.customers
   where regexp_replace(coalesce(phone,''), '[^0-9+]', '', 'g') = v_phone and deleted_at is null
   order by created_at limit 1;

  if v_email_matches = 0 and v_phone_cust is null then
    -- (A) Brand-new person: create Customer + active Affiliate + account.
    insert into public.customers (full_name, phone, email, is_active)
      values (v_name, coalesce(nullif(v_phone,''), 'AFF-'||substr(v_uid::text,1,8)), v_email, true)
      returning id into v_cust;

  elsif v_email_matches = 1 and v_phone_cust is not null and v_phone_email = v_email then
    -- (B) Safe existing match: same verified email AND phone on the SAME record.
    v_cust := v_phone_cust;

  elsif v_email_matches = 1 and v_phone_cust is null then
    -- Email uniquely matches and phone unused elsewhere: safe to link by email.
    select id into v_cust from public.customers
     where lower(btrim(email)) = v_email and deleted_at is null and is_active = true limit 1;

  else
    -- Ambiguous: park a claim for Owner/Manager. No Customer created/changed.
    insert into public.affiliate_account_claims (auth_user_id, entered_phone, verified_email, candidate_customer_id)
      values (v_uid, v_phone, v_email, v_phone_cust)
      on conflict do nothing;
    return jsonb_build_object('status', 'pending_verification',
      'message', 'We found an existing Energia customer record that needs identity verification. Please contact Energia to complete account linking.');
  end if;

  -- Ensure an affiliate record for the resolved customer (reuse if present).
  select * into v_aff from public.customer_affiliates where customer_id = v_cust and deleted_at is null;
  if not found then
    v_code := public.generate_affiliate_referral_code();
    insert into public.customer_affiliates (customer_id, status, manually_suspended, activated_at, referral_code)
      values (v_cust, 'active', false, now(), v_code)
      returning * into v_aff;
  else
    v_suspended := v_aff.manually_suspended;   -- keep suspension; do NOT reactivate
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

-- Owner/Manager resolution of a pending identity claim.
create or replace function public.resolve_affiliate_account_claim(
  p_claim_id uuid, p_customer_id uuid, p_note text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_claim public.affiliate_account_claims%rowtype; v_aff public.customer_affiliates%rowtype; v_acct uuid; v_code text;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can resolve account claims'; end if;
  if p_note is null or btrim(p_note) = '' then raise exception 'A verification note is required'; end if;
  select * into v_claim from public.affiliate_account_claims where id = p_claim_id;
  if not found then raise exception 'Claim not found'; end if;
  if v_claim.status <> 'pending' then raise exception 'Claim already resolved'; end if;
  if exists (select 1 from public.affiliate_accounts where auth_user_id = v_claim.auth_user_id) then
    raise exception 'This login is already linked to an affiliate account'; end if;

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
-- 7. Public referral-code lookup (anon). Returns ONLY display-safe fields.
-- =====================================================================
create or replace function public.public_affiliate_referral_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_ca public.customer_affiliates%rowtype; v_name text; v_first text;
begin
  select * into v_ca from public.customer_affiliates where referral_code = btrim(p_code) and deleted_at is null;
  if not found then return jsonb_build_object('valid', false); end if;
  select full_name into v_name from public.customers where id = v_ca.customer_id and deleted_at is null;
  if v_name is null then return jsonb_build_object('valid', false); end if;
  v_first := split_part(v_name, ' ', 1);   -- first name only; no contact details
  return jsonb_build_object(
    'valid', true, 'affiliate_name', v_first,
    'accepting', (v_ca.manually_suspended = false and v_ca.status = 'active'));
end $function$;

-- =====================================================================
-- 8. Public referral signup (anon). Creates a CUSTOMER only (never an affiliate
--    or a login). Honeypot + simple server-side throttle. Existing phones are
--    never hijacked or re-parented from an anonymous form.
-- =====================================================================
create or replace function public.affiliate_referral_signup(
  p_code text, p_first_name text, p_last_name text, p_phone text, p_email text,
  p_honeypot text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_ca public.customer_affiliates%rowtype; v_ref_cust uuid; v_phone text; v_email text;
  v_name text; v_new uuid; v_recent int;
begin
  -- Honeypot: pretend success, record nothing real.
  if coalesce(btrim(p_honeypot),'') <> '' then
    insert into public.referral_signup_events(referral_code, outcome) values (p_code, 'honeypot');
    return jsonb_build_object('ok', true);
  end if;

  v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_email := nullif(lower(btrim(coalesce(p_email,''))), '');
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  if v_phone = '' or v_name = '' then raise exception 'Please enter your name and phone number'; end if;

  -- Throttle: max 3 attempts per phone / 10 minutes.
  select count(*) into v_recent from public.referral_signup_events
   where normalized_phone = v_phone and created_at > now() - interval '10 minutes';
  if v_recent >= 3 then
    return jsonb_build_object('ok', true, 'message', 'Registration received.');   -- neutral
  end if;

  select * into v_ca from public.customer_affiliates where referral_code = btrim(p_code) and deleted_at is null;
  if not found or v_ca.manually_suspended or v_ca.status <> 'active' then
    insert into public.referral_signup_events(referral_code, normalized_phone, outcome) values (p_code, v_phone, 'rejected');
    return jsonb_build_object('ok', false,
      'message', 'This referral link is not accepting new registrations right now. Please contact Energia.');
  end if;
  v_ref_cust := v_ca.customer_id;

  -- Self-referral by phone/email.
  if exists (select 1 from public.customers where id = v_ref_cust
              and (regexp_replace(coalesce(phone,''),'[^0-9+]','','g') = v_phone
                   or (v_email is not null and lower(btrim(email)) = v_email))) then
    return jsonb_build_object('ok', false, 'message', 'You cannot refer yourself.');
  end if;

  -- Existing phone: never hijack / re-parent from an anonymous form (first wins).
  if exists (select 1 from public.customers where regexp_replace(coalesce(phone,''),'[^0-9+]','','g') = v_phone) then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (p_code, v_ref_cust, v_phone, 'duplicate');
    return jsonb_build_object('ok', true,
      'message', 'This customer is already registered with Energia. Please contact us if you need help with your referral registration.');
  end if;

  insert into public.customers (full_name, phone, email, is_active, referred_by,
      referred_at, referral_source, referral_code_used)
    values (v_name, v_phone, v_email, true, v_ref_cust, now(), 'affiliate_link', btrim(p_code))
    returning id into v_new;

  insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, normalized_phone, outcome)
    values (p_code, v_ref_cust, v_new, v_phone, 'created');

  begin
    perform public.write_audit_ex('customers', v_new, 'referral_registered', null,
      jsonb_build_object('referred_by', v_ref_cust, 'referral_code', btrim(p_code), 'source', 'affiliate_link'),
      'affiliate', null, null);
  exception when others then null; end;

  return jsonb_build_object('ok', true, 'message', 'Registration successful.');
end $function$;

-- =====================================================================
-- 9. Portal read RPCs. Every one derives identity from auth.uid() via
--    current_affiliate_customer_id(); none accept an affiliate id argument.
--    Network is capped at Tier 1 + Tier 2. Purchase descriptions are always
--    the literal 'Purchase' — never product / therapy / voucher / promo names.
-- =====================================================================

-- shared: settled invoice statuses used for "amount spent"
create or replace function public._aff_settled_spend(p_customer uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  select coalesce(sum(total_amount),0) from public.invoices
   where customer_id = p_customer and deleted_at is null
     and status in ('paid','completed_foc','partially_paid')
$function$;

create or replace function public.affiliate_portal_me()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_c public.customers%rowtype;
        v_a public.customer_affiliates%rowtype; v_acct public.affiliate_accounts%rowtype; v_email text;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  select * into v_c from public.customers where id = v_me;
  select * into v_a from public.customer_affiliates where customer_id = v_me and deleted_at is null;
  select * into v_acct from public.affiliate_accounts where customer_id = v_me;
  select email into v_email from auth.users where id = v_acct.auth_user_id;
  return jsonb_build_object(
    'customer_id', v_me, 'name', v_c.full_name, 'email', v_email,
    'referral_code', v_a.referral_code,
    'status', case when v_a.manually_suspended then 'suspended' else 'active' end,
    'joined_at', v_a.activated_at, 'account_status', v_acct.status,
    'direct_referrals', (select count(*) from public.customers where referred_by = v_me and deleted_at is null));
end $function$;

create or replace function public.affiliate_portal_referral_info()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_a public.customer_affiliates%rowtype;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  select * into v_a from public.customer_affiliates where customer_id = v_me and deleted_at is null;
  return jsonb_build_object(
    'referral_code', v_a.referral_code,
    'accepting', (v_a.manually_suspended = false and v_a.status = 'active'),
    'direct_referrals', (select count(*) from public.customers where referred_by = v_me and deleted_at is null));
end $function$;

-- Tier 1 + Tier 2 network members (sanitized). Tier 2 = referrals of my Tier 1.
create or replace function public.affiliate_portal_network()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_t1 jsonb; v_t2 jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier1',
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id
                                  and cm.status in ('earned','paid'))
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t1
    from public.customers c where c.referred_by = v_me and c.deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier2',
           'parent_name', p.full_name,
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id)
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t2
    from public.customers c
    join public.customers p on p.id = c.referred_by
   where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null;

  return jsonb_build_object('tier1', v_t1, 'tier2', v_t2);
end $function$;

-- Aggregated per-purchase view (one row per invoice, description always 'Purchase').
create or replace function public.affiliate_portal_purchases()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_rows jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by (t.purchase_date) desc), '[]'::jsonb) into v_rows
  from (
    select
      c.full_name as customer_name,
      cm.tier::text as tier,
      i.created_at::date as purchase_date,
      'Purchase'::text as description,
      i.total_amount as purchase_amount,
      sum(cm.commission_amount) as your_commission,
      -- worst-ish status surfaced: paid if all paid, else earned/reversed present
      (array_agg(distinct cm.status::text))[1] as status
    from public.commissions cm
    join public.invoices i on i.id = cm.invoice_id
    join public.customers c on c.id = cm.buyer_customer_id
   where cm.referrer_customer_id = v_me
   group by c.full_name, cm.tier, i.id, i.created_at, i.total_amount
  ) t;
  return v_rows;
end $function$;

-- Earnings: summary + by tier + by month + by customer + by purchase. Reads
-- ONLY commissions for this referrer, so it reconciles exactly with Staff.
create or replace function public.affiliate_portal_earnings()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_me uuid := public.current_affiliate_customer_id();
        v_unpaid numeric; v_paid numeric; v_reversed numeric; v_blocked numeric; v_lifetime numeric;
        v_t1 numeric; v_t2 numeric; v_by_month jsonb; v_by_customer jsonb; v_by_purchase jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;

  select
    coalesce(sum(commission_amount) filter (where status='earned'),0),
    coalesce(sum(commission_amount) filter (where status='paid'),0),
    coalesce(sum(commission_amount) filter (where status='reversed'),0),
    coalesce(sum(commission_amount) filter (where status='cancelled'),0),
    coalesce(sum(commission_amount) filter (where status='paid' and tier='tier1'),0)
           + coalesce(sum(commission_amount) filter (where status='earned' and tier='tier1'),0),
    coalesce(sum(commission_amount) filter (where status='paid' and tier='tier2'),0)
           + coalesce(sum(commission_amount) filter (where status='earned' and tier='tier2'),0)
    into v_unpaid, v_paid, v_reversed, v_blocked, v_t1, v_t2
  from public.commissions where referrer_customer_id = v_me;
  v_lifetime := v_unpaid + v_paid;

  select coalesce(jsonb_agg(jsonb_build_object('month', m, 'tier1', t1, 'tier2', t2, 'total', t1+t2) order by m desc),'[]'::jsonb)
    into v_by_month from (
      select to_char(date_trunc('month', coalesce(invoice_paid_date, created_at::date)),'YYYY-MM') as m,
             coalesce(sum(commission_amount) filter (where tier='tier1' and status in ('earned','paid')),0) as t1,
             coalesce(sum(commission_amount) filter (where tier='tier2' and status in ('earned','paid')),0) as t2
        from public.commissions where referrer_customer_id = v_me group by 1) mm;

  select coalesce(jsonb_agg(jsonb_build_object('customer', cust, 'tier', tier, 'purchase_amount', spend, 'commission', comm) order by comm desc),'[]'::jsonb)
    into v_by_customer from (
      select c.full_name as cust, cm.tier::text as tier,
             public._aff_settled_spend(c.id) as spend,
             coalesce(sum(cm.commission_amount) filter (where cm.status in ('earned','paid')),0) as comm
        from public.commissions cm join public.customers c on c.id = cm.buyer_customer_id
       where cm.referrer_customer_id = v_me group by c.id, c.full_name, cm.tier) cc;

  v_by_purchase := public.affiliate_portal_purchases();

  return jsonb_build_object(
    'summary', jsonb_build_object('lifetime', v_lifetime, 'unpaid', v_unpaid, 'paid', v_paid,
      'reversed', v_reversed, 'blocked', v_blocked),
    'by_tier', jsonb_build_object('tier1', v_t1, 'tier2', v_t2),
    'by_month', v_by_month, 'by_customer', v_by_customer, 'by_purchase', v_by_purchase);
end $function$;

create or replace function public.affiliate_portal_payouts()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_rows jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'payout_month', to_char(payout_month,'YYYY-MM'),
           'tier1', total_tier1, 'tier2', total_tier2, 'total', total_amount,
           'paid_date', paid_at::date, 'status', status, 'reference', reference) order by payout_month desc), '[]'::jsonb)
    into v_rows from public.commission_payouts where referrer_customer_id = v_me;
  return v_rows;
end $function$;

create or replace function public.affiliate_portal_dashboard()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_me uuid := public.current_affiliate_customer_id();
        v_t1 int; v_t2 int; v_earn jsonb; v_recent jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  select count(*) into v_t1 from public.customers where referred_by = v_me and deleted_at is null;
  select count(*) into v_t2 from public.customers c join public.customers p on p.id = c.referred_by
    where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null;
  v_earn := public.affiliate_portal_earnings();
  select coalesce(jsonb_agg(e order by (e->>'purchase_date') desc), '[]'::jsonb)
    into v_recent from (select jsonb_array_elements(public.affiliate_portal_purchases()) e) x
    limit 10;
  return jsonb_build_object(
    'network', jsonb_build_object('tier1', v_t1, 'tier2', v_t2, 'total', v_t1 + v_t2),
    'earnings', v_earn->'summary', 'by_tier', v_earn->'by_tier', 'recent', v_recent);
end $function$;

-- =====================================================================
-- 10. RLS: affiliates may read only their OWN account/claim rows. Everything
--     else goes through the SECURITY DEFINER RPCs above. No broad affiliate
--     policy is added to customers / commissions / invoices / commission_payouts.
-- =====================================================================
alter table public.affiliate_accounts enable row level security;
alter table public.affiliate_account_claims enable row level security;
alter table public.referral_signup_events enable row level security;

drop policy if exists aff_accounts_self_read on public.affiliate_accounts;
create policy aff_accounts_self_read on public.affiliate_accounts for select
  using (auth_user_id = auth.uid() or public.is_owner_or_manager());

drop policy if exists aff_claims_self_read on public.affiliate_account_claims;
create policy aff_claims_self_read on public.affiliate_account_claims for select
  using (auth_user_id = auth.uid() or public.is_owner_or_manager());

drop policy if exists aff_events_mgr_read on public.referral_signup_events;
create policy aff_events_mgr_read on public.referral_signup_events for select
  using (public.is_owner_or_manager());

-- =====================================================================
-- 11. Manager directory: affiliate rows enriched with portal-account status +
--     referral code + quick counts (Owner/Manager only; SECURITY DEFINER).
-- =====================================================================
create or replace function public.affiliate_admin_directory()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_rows jsonb;
begin
  if not public.is_owner_or_manager() then raise exception 'Owner or Manager only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'customer_id', ca.customer_id, 'name', c.full_name,
    'status', case when ca.manually_suspended then 'suspended' else ca.status end,
    'manually_suspended', ca.manually_suspended,
    'referral_code', ca.referral_code,
    'portal_account', case when acc.id is null then 'not_claimed'
                           when acc.status = 'disabled' then 'disabled' else 'claimed' end,
    'direct_referrals', (select count(*) from public.customers x where x.referred_by = ca.customer_id and x.deleted_at is null),
    'tier2', (select count(*) from public.customers x join public.customers p on p.id = x.referred_by
               where p.referred_by = ca.customer_id and x.deleted_at is null and p.deleted_at is null),
    'lifetime', (select coalesce(sum(commission_amount),0) from public.commissions where referrer_customer_id = ca.customer_id and status in ('earned','paid')),
    'unpaid', (select coalesce(sum(commission_amount),0) from public.commissions where referrer_customer_id = ca.customer_id and status = 'earned'),
    'blocked', (select coalesce(sum(commission_amount),0) from public.commissions where referrer_customer_id = ca.customer_id and status = 'cancelled'),
    'last_commission', (select max(created_at) from public.commissions where referrer_customer_id = ca.customer_id)
  ) order by c.full_name), '[]'::jsonb) into v_rows
  from public.customer_affiliates ca
  join public.customers c on c.id = ca.customer_id
  left join public.affiliate_accounts acc on acc.customer_id = ca.customer_id
  where ca.deleted_at is null;
  return v_rows;
end $function$;

create or replace function public.affiliate_pending_claims()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_rows jsonb;
begin
  if not public.is_owner_or_manager() then raise exception 'Owner or Manager only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'claim_id', cl.id, 'verified_email', cl.verified_email, 'entered_phone', cl.entered_phone,
    'candidate_customer_id', cl.candidate_customer_id,
    'candidate_name', (select full_name from public.customers where id = cl.candidate_customer_id),
    'created_at', cl.created_at) order by cl.created_at), '[]'::jsonb) into v_rows
  from public.affiliate_account_claims cl where cl.status = 'pending';
  return v_rows;
end $function$;

-- =====================================================================
-- 12. Grants. Anon may only call the two public entry points; portal + admin
--     RPCs require an authenticated session (identity re-derived internally).
-- =====================================================================
grant execute on function public.public_affiliate_referral_info(text) to anon, authenticated;
grant execute on function public.affiliate_referral_signup(text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.complete_affiliate_onboarding(text,text,text,boolean) to authenticated;
grant execute on function public.current_affiliate_customer_id() to authenticated;
grant execute on function public.affiliate_portal_me() to authenticated;
grant execute on function public.affiliate_portal_referral_info() to authenticated;
grant execute on function public.affiliate_portal_network() to authenticated;
grant execute on function public.affiliate_portal_purchases() to authenticated;
grant execute on function public.affiliate_portal_earnings() to authenticated;
grant execute on function public.affiliate_portal_payouts() to authenticated;
grant execute on function public.affiliate_portal_dashboard() to authenticated;
grant execute on function public.reassign_customer_referrer(uuid,uuid,text) to authenticated;
grant execute on function public.resolve_affiliate_account_claim(uuid,uuid,text) to authenticated;
grant execute on function public.affiliate_admin_directory() to authenticated;
grant execute on function public.affiliate_pending_claims() to authenticated;

-- =====================================================================
-- 13. Assertions.
-- =====================================================================
do $$
begin
  if not exists (select 1 from information_schema.columns where table_name='customer_affiliates' and column_name='referral_code') then
    raise exception 'referral_code column missing'; end if;
  if not exists (select 1 from pg_proc where proname='current_affiliate_customer_id') then
    raise exception 'current_affiliate_customer_id missing'; end if;
  if not exists (select 1 from pg_proc where proname='complete_affiliate_onboarding') then
    raise exception 'complete_affiliate_onboarding missing'; end if;
  if not exists (select 1 from pg_trigger where tgname='trg_enforce_referral_ownership') then
    raise exception 'referral ownership trigger missing'; end if;
  if exists (select 1 from public.customer_affiliates where referral_code is null and deleted_at is null) then
    raise exception 'some affiliate records were not backfilled with a referral code'; end if;
  raise notice 'Confirmed: affiliate self-service portal backend installed; commission engine untouched.';
end $$;

notify pgrst, 'reload schema';
