begin;
-- =====================================================================
-- A SIGNED-IN CUSTOMER IS NOT A MEMBER OF STAFF
--
-- Most read policies in this schema are written "to authenticated using
-- (true)". When they were written that was an accurate way to say "any member
-- of staff", because the only way to hold the authenticated role was to be one.
--
-- Migration 155 changed that. Affiliates now sign in for themselves, and an
-- affiliate session is an ordinary authenticated session — the whole
-- distinction the portal rests on is that they have no profiles row. Migration
-- 340 recognised this drift for FUNCTIONS, where eight role guards were letting
-- a null role through. The POLICIES were never revisited, so the set of people
-- reading "any member of staff" quietly grew to include every customer who has
-- ever claimed an affiliate login.
--
-- What that reaches today, with nothing but an affiliate password: every
-- customer's health survey and symptoms, consultant notes, phone history and
-- remarks, every invoice line, refund and revision, every credit package and
-- premium bundle sale, every therapy entitlement and voucher issue, and the
-- whole TikTok commercial record.
--
-- Two policies are worse than a read.
--
--   profiles / "insert profiles" — INSERT to authenticated with check (true).
--   The privilege guard on profiles is a BEFORE UPDATE trigger, so it does not
--   fire on INSERT, and profiles.role is caller-supplied. An affiliate has an
--   auth.users row and no profiles row, so it can insert its own profile with
--   role 'owner' and become one. Verified against the local Supabase stack:
--   the insert succeeds and current_user_role() then returns 'owner'.
--
--   customers / "update customers" — UPDATE to authenticated using (true) with
--   check (true). Any signed-in session may rewrite any customer's name, phone,
--   deleted_at, and referred_by. referred_by is the tier-1 referral chain that
--   earn_invoice_commission reads, so this is a money-affecting write.
--
-- THE FIX IS NOT TO NARROW WHAT STAFF CAN SEE. Every staff role keeps exactly
-- the access it has today: "true" becomes "has a staff role at all", which is
-- what the policies meant when they were written. No store scoping is added
-- here, so no branch loses sight of anything it can see now. The only sessions
-- that lose access are the ones that were never meant to have it.
--
-- Left alone deliberately:
--   * catalogue and reference tables (products, stores, prices, promotions,
--     therapy services, packages). An affiliate reading the product catalogue
--     is not a breach, and touching them is risk without benefit.
--   * health_symptom_options (role public) and customer_source_options (anon),
--     which the public survey form reads while signed out.
--   * profiles SELECT is scoped too: an affiliate could read the whole staff
--     directory. AffiliateLoginPage reads profiles for its own id to decide
--     where to send someone, and an affiliate has no row there either way, so
--     that routing is unchanged.
--
-- Store-level scoping of invoice_items and its siblings — so a staff member at
-- one branch cannot read another branch's invoice lines — is a real remaining
-- gap, but it is a narrowing of staff access and is left as a documented
-- recommendation rather than done silently here.
-- =====================================================================
do $$
declare
  f record;
  v_pred constant text := '(public.current_user_role() is not null)';
  v_changed int := 0;
  v_names text := '';
  -- Customer, medical, financial and operational records. Not the catalogue.
  v_tables constant text[] := array[
    'affiliates','consultant_notes','credit_package_sales','customer_affiliates',
    'customer_phone_history','customer_remarks','customer_reward_vouchers',
    'customer_therapy_sessions','customers','data_removal_reconciliation',
    'document_sends','health_survey_symptoms','health_surveys','invoice_credit_splits',
    'invoice_items','invoice_promotion_selections','invoice_refunds','invoice_revisions',
    'premium_bundle_sales','profiles','purchased_therapy_entitlements','rentals',
    'special_credit_allocations','special_sales','stock_uses',
    'therapy_date_change_requests','therapy_entitlement_invoices',
    'therapy_expiry_adjustments','therapy_qualification_topups','therapy_voucher_issues',
    'tiktok_corrections','tiktok_import_batches','tiktok_order_rows','tiktok_order_state',
    'tiktok_physical_returns','tiktok_settlement_rows','tiktok_sku_aliases',
    'tiktok_status_mappings','tiktok_voucher_sales',
    'transfer_line_sources','transfer_request_lines'
  ];
begin
  -- current_user_role() must bypass RLS, or a policy on profiles that calls it
  -- would recurse. It is SECURITY DEFINER and owned by the table owner.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'current_user_role' and p.prosecdef) then
    raise exception '343: current_user_role() is not SECURITY DEFINER; a policy calling it would recurse on profiles';
  end if;

  -- The privilege escalation. Nothing in the application inserts a profile:
  -- creation runs through invite_user_accept, a SECURITY DEFINER function that
  -- is not subject to policies at all.
  if exists (select 1 from pg_policies
              where schemaname='public' and tablename='profiles' and policyname='insert profiles') then
    drop policy "insert profiles" on public.profiles;
    raise notice '343: dropped the profiles INSERT policy that let a session create its own owner account';
  end if;

  for f in
    select c.relname as tbl, pol.polname as pol, pol.polcmd as cmd,
           pol.polqual is not null as has_qual,
           pol.polwithcheck is not null as has_check
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = any(v_tables)
       -- only policies that are open to everyone signed in, and only those
       -- granted to authenticated alone: anything reaching anon is public by
       -- design and is not ours to change here.
       and (pg_get_expr(pol.polqual, pol.polrelid) = 'true'
         or pg_get_expr(pol.polwithcheck, pol.polrelid) = 'true')
       and pol.polroles = array[(select oid from pg_roles where rolname='authenticated')]
     order by c.relname, pol.polname
  loop
    if f.has_qual and f.has_check then
      execute format('alter policy %I on public.%I using %s with check %s', f.pol, f.tbl, v_pred, v_pred);
    elsif f.has_check then
      execute format('alter policy %I on public.%I with check %s', f.pol, f.tbl, v_pred);
    else
      execute format('alter policy %I on public.%I using %s', f.pol, f.tbl, v_pred);
    end if;
    v_changed := v_changed + 1;
    v_names := v_names || f.tbl || '.' || f.pol || ' ';
  end loop;

  if v_changed = 0 then
    raise notice '343: no unrestricted policy left on the customer, financial or operational tables (already applied)';
  else
    raise notice '343: % policy/policies now require a staff role: %', v_changed, v_names;
  end if;
end $$;

-- Two more that are unscoped without literally saying "true", and so are not
-- caught by the sweep above. "read customers" excludes deleted rows and nothing
-- else, which means an affiliate login can read every customer's name, phone
-- and email. "read assignments" says who works at which branch.
do $$
begin
  if exists (select 1 from pg_policies where schemaname='public' and tablename='customers'
              and policyname='read customers' and qual = '(deleted_at IS NULL)') then
    alter policy "read customers" on public.customers
      using (deleted_at is null and public.current_user_role() is not null);
    raise notice '343: reading the customer list now requires a staff role';
  end if;

  if exists (select 1 from pg_policies where schemaname='public' and tablename='user_store_assignments'
              and policyname='read assignments' and qual = 'true') then
    alter policy "read assignments" on public.user_store_assignments
      using (public.current_user_role() is not null);
    raise notice '343: reading the store assignments now requires a staff role';
  end if;
end $$;

do $$
declare v_left text := '';
begin
  -- Nothing on the listed tables may still be open to any signed-in session.
  select string_agg(tablename || '.' || policyname, ', ' order by tablename)
    into v_left
    from pg_policies
   where schemaname = 'public'
     and tablename in ('customers','profiles','health_surveys','health_survey_symptoms',
                       'consultant_notes','customer_remarks','customer_phone_history',
                       'invoice_items','invoice_refunds','invoice_revisions',
                       'customer_reward_vouchers','purchased_therapy_entitlements',
                       'therapy_voucher_issues','credit_package_sales','premium_bundle_sales')
     and (qual = 'true' or with_check = 'true');
  if v_left is not null then
    raise exception '343: still open to any signed-in session: %', v_left;
  end if;

  if exists (select 1 from pg_policies where schemaname='public' and tablename='customers'
              and policyname='read customers' and qual !~ 'current_user_role') then
    raise exception '343: the customer list is still readable by any signed-in session';
  end if;

  -- And nobody may create their own profile row.
  if exists (select 1 from pg_policies
              where schemaname='public' and tablename='profiles' and cmd='INSERT') then
    raise exception '343: an INSERT policy on profiles is back; profiles are created by invite_user_accept, not by the caller';
  end if;
end $$;

commit;
