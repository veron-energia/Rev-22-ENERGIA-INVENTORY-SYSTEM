-- 453_staff_see_customer_profile_and_downline.sql
--
-- STAFF SEE A CUSTOMER'S FULL PROFILE AND THEIR DOWNLINE (the Owner's change
-- list of 22 Oct 2026, item 7: "Staff can see the full customer profile and
-- the downline from the Customers page")
--
-- WHAT WAS WRONG / WHY
--
--   The Customers page's Profile gave a Staff login the Limited view: phone,
--   email, date of birth, gender, occupation, first visit and stock loans,
--   with "Limited view — financial, commission, and audit history are
--   visible to Owners and Managers only." The figures (Paid purchases, Total
--   spend, Customers referred and its Downline button, Referred by), the
--   phone history and the purchase timeline were hidden, and the row's
--   Downline button was not there. The page did so to match the database,
--   which refused them on purpose:
--   * customer_profile_stats(uuid) and customer_purchase_timeline(uuid) begin
--     with require_active_staff('{owner,manager}') (406, the Owner's rule of
--     9 Oct 2026: "the customer profile's figures and purchase history" for
--     Owners and Managers): Staff got 42501 "Your role cannot do this.";
--   * customer_downline_visits(uuid) began with "if not
--     is_owner_or_manager()" (398, its rule 4, "Owner/Manager only"): Staff
--     got 42501 "Only an Owner or Manager can view a downline".
--   The old Admin role was refused the same way, although it adds and edits
--   customers (418). Row rules were not the cause: customers and
--   customer_phone_history are readable by any active staff (430), so the
--   phone history was hidden by the page alone.
--
-- THE RULES (binding: the Owner's answers, 22 Oct 2026, the recommendations
-- accepted, to the seven questions of item 7)
--
--   1. Who: "Owner, Admin, Manager and Staff, the same people who can add and
--      edit customers (418). Inventory Managers keep the Limited view." So do
--      a login that is not active staff (an affiliate, a deactivated
--      employee, a pending or cancelled invitee, no profile) and anyone
--      signed out: refused, 42501.
--   2. What: "everything Owners and Managers see": Paid purchases, Total
--      spend, each invoice's lines and totals in the Purchase timeline.
--   3. Which stores: "All stores, as Managers see it today." (Not only the
--      stores the staff member works at.)
--   4. Phone history: "Yes."
--   5. "Add the same Downline button to the staff list on the Affiliates
--      page." (The page; no database change.)
--   6. The Downline window's Excel export (Tier 1 and Tier 2 names and
--      phones): "Yes." (The page; no database change.)
--   7. Still not for Staff: "commission amounts (the Commissions page,
--      including the referrer's earnings and their downline's spend; the
--      Affiliates Lifetime/Unpaid/Blocked columns); the Referral promotion
--      tab and its rewards; Delete customer and Deleted Customers; credit
--      Opening balance/Adjust; Correct referrer and Suspend on affiliates."
--      None of these functions holds a commission figure.
--   Every other rule of 398, 406 and 418 stands as written there.
--
-- WHAT THIS DOES (three functions patched at their role check only; no
-- table, row, policy or grant changes; no function added or dropped)
--
--   * customer_profile_stats(uuid): require_active_staff('{owner,manager}')
--     becomes require_active_staff('{owner,admin,manager,staff}') (one
--     anchor; its comment says 453).
--   * customer_purchase_timeline(uuid): the same (one anchor).
--   * customer_downline_visits(uuid): its "Owner/Manager only" check (398)
--     becomes require_active_staff('{owner,admin,manager,staff}') (406's
--     check, as the two above), and its header comment says so (two
--     anchors). An Inventory Manager now reads "Your role cannot do this.",
--     a login that is not active staff "Only active Energia staff can do
--     this." (both 42501), in place of "Only an Owner or Manager can view a
--     downline".
--   What each returns, to whom it answers, is as before to the letter: the
--   suite compares the Staff and Admin answers with the Manager's.
--
-- NOT CHANGED
--
--   * Every other function: referrer_downline, referrer_earnings,
--     referrer_list and the Commissions page (commission amounts and a
--     downline's spend: Owner, Admin, Manager, as 398 has it),
--     affiliate_admin_directory, the referral promotion's functions,
--     delete_customer and the deleted list, the credit Opening balance and
--     Adjust, reassign_customer_referrer, suspend_affiliate,
--     customer_overview (View: every staff role, as before),
--     customer_centre_visits (the downline reads it; the service role's
--     alone, unchanged), require_active_staff and is_owner_or_manager
--     (used as they are).
--   * Grants: all three stay callable by signed-in logins and the service
--     role, not signed out (checked afterwards, as sets).
--   * The tables and their rules: invoices and invoice_items stay
--     store-scoped for direct reads (430); the two profile functions are
--     SECURITY DEFINER and return every store's invoices to whoever passes
--     their check, as they did for Managers (rule 3).
--
-- NOT COVERED (to tell the Owner)
--
--   1. The server: require_active_staff lets the server through (406's rule
--      4: the service role, pg_cron, migrations), as it does for the two
--      profile functions since 406. customer_downline_visits refused the
--      server before (is_owner_or_manager() has no login to read); it now
--      answers it. No Edge Function, job or trigger calls it.
--   2. Phone history is read from the table by the page (the rule: any
--      active staff, Inventory Managers too, 430); only the page keeps it
--      from an Inventory Manager, as it kept it from Staff before.
--   3. Staff see every store's invoices in a customer's timeline (rule 3),
--      while the Invoices page lists only their own stores' invoices.
--   4. The page (this file's frontend change) must go live after this file:
--      a page that offers the figures to Staff before it would show them
--      "The figures could not be loaded. Your role cannot do this." and the
--      Downline window "Only an Owner or Manager can view a downline".
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (... 448, 450: 63219bad, 1371 functions) -> 453, then the
--   page (CustomersPage.tsx, AffiliatesPage.tsx, DownlineModal.tsx,
--   src/lib/customers/customerRoles.mjs). The other files of the 22 Oct list
--   are built beside this one: before applying, re-check
--   supabase_migrations.schema_migrations and origin/main for number 453 and
--   for any file that changes one of these three functions (none did when
--   this was written).
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below (from 450's), the second
--      changes nothing ("already this version; left alone" three times).
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   3. Push the page.
--   Afterwards a re-run of 406 (it pins customer_profile_stats and
--   customer_purchase_timeline at 67c5770c / cb21b161) and of 398 and 404
--   (they pin customer_downline_visits at 1125dc56) refuses, changing
--   nothing; each already refuses today on other pins (398 on
--   search_customers, read 22 Oct 2026). All are applied, so nothing is lost.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the functions it relies on are as read on production (below);
--   * each patched function is its BEFORE (production, 22 Oct 2026; patched,
--     each anchor found once, the text built has the tested AFTER md5) or its
--     AFTER (left alone), so a second run changes nothing; no other function
--     takes the three names;
--   * afterwards: the three md5s are the AFTER ones; their grants are as
--     before (compared as sets), signed-in logins and the service role may
--     call them, signed out may not;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0453, so it leaves no row): made-up logins (Staff, Admin, Manager,
--     Inventory Manager, one with no profile; @example.invalid) and three
--     made-up customers (fictional ACMA phones no customer has), a referrer,
--     their Tier 1 friend and that friend's own friend. Staff and the Admin
--     get exactly the Manager's three answers (one referred, Tier 1 and Tier
--     2 of one each, no purchases); the Inventory Manager and the login with
--     no profile are refused all three with 42501.
--   The bodies are unchanged apart from the check, so no column is read
--   that was not read before. Locks: the three functions' catalogue rows, to
--   the end of the apply. A Profile or Downline opening at that moment
--   finishes on the text it started with.
--
-- BEFORE (production, 22 Oct 2026, at 450, read on its local copy s450;
-- md5 of pg_get_functiondef with search_path public)
--   changed
--   customer_profile_stats(uuid)                                   67c5770c7bc0be83899e5fde593fc851  (406)
--   customer_purchase_timeline(uuid)                               cb21b1612cc04f5da2e5f07c46f81d0d  (406)
--   customer_downline_visits(uuid)                                 1125dc56d3964c4b54a61ce88448ad65  (398)
--   relied on, not changed
--   require_active_staff(text[])                                   877b3aa74cea559881979bb161c450e2  (406)
--   customer_centre_visits()                                       c07a5a0cbbf52ba45e5dc911b20002da  (the downline calls it)
--   public function fingerprint, production now (450 in)           63219badeea67a5d401d5af2aeb88f19 (1371 functions)
-- AFTER (for later guards)
--   customer_profile_stats(uuid)                                   93c1a7b762b99c7e28fdad0facc17ac8
--   customer_purchase_timeline(uuid)                               9fdfb23164e62e6e9309e02470a3520e
--   customer_downline_visits(uuid)                                 5bee190a80a8e9624e7d15e16eb95ca1
--   public function fingerprint, worked out on a copy of production (22 Oct 2026):
--     production now (450 in) -> 453 (a second run the same)       20bc52e4d3e37d7c52376c17b7999621 (1371 functions: none added or dropped)
--
-- Test: scripts/customers/tests/staff-profile-453.sql (begin ... rollback; it
-- installs this file twice, or -v skip_install=1 where it is in): the three
-- functions, through the API's own roles, on fixture records (two paid
-- invoices and an unpaid one at two stores, a referral chain, an old phone
-- number): Owner, Admin, Manager and Staff (at one store) get the same
-- answers, every store's invoices included; the Inventory Manager, an
-- affiliate portal login, a deactivated employee, a pending and a cancelled
-- invitee, a login with no profile and a signed-out caller are refused with
-- 42501; the server passes; the answers keep their keys (no commission) and
-- referrer_downline still refuses Staff; the grants; a second run changes
-- nothing; the self-test leaves no row; a changed function is refused.
-- scripts/permissions/tests/staff-only-functions.sql holds the three at
-- "every role but Inventory Manager" ('notinv'; it held the two profile
-- functions at Owner and Manager before), and function-grants.sql passes with
-- it. scripts/referrals/tests/visits-and-october.sql still checks 398's own
-- version (it installs 398 on a database from before it). Fixtures only (the
-- repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The three functions this patches: BEFORE (production, 22 Oct 2026)
  -- and AFTER md5s ═════════════════════════════════════════════════════════
  c_ps constant text := 'customer_profile_stats(uuid)';
  c_pt constant text := 'customer_purchase_timeline(uuid)';
  c_dv constant text := 'customer_downline_visits(uuid)';
  c_ps_before constant text := '67c5770c7bc0be83899e5fde593fc851';
  c_ps_after  constant text := '93c1a7b762b99c7e28fdad0facc17ac8';
  c_pt_before constant text := 'cb21b1612cc04f5da2e5f07c46f81d0d';
  c_pt_after  constant text := '9fdfb23164e62e6e9309e02470a3520e';
  c_dv_before constant text := '1125dc56d3964c4b54a61ce88448ad65';
  c_dv_after  constant text := '5bee190a80a8e9624e7d15e16eb95ca1';

  -- ══ customer_profile_stats: its role check ══════════════════════════════
  c_ps_a constant text := $a$  perform public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
$a$;
  c_ps_r constant text := $r$  -- 453 (the Owner, 22 Oct 2026): Owners, Admins, Managers and Staff, the
  -- roles that add and edit customers (418); not an Inventory Manager. 406
  -- had Owners and Managers only.
  perform public.require_active_staff('{owner,admin,manager,staff}');
$r$;

  -- ══ customer_purchase_timeline: its role check ══════════════════════════
  c_pt_a constant text := $a$  select public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
$a$;
  c_pt_r constant text := $r$  -- 453 (the Owner, 22 Oct 2026): Owners, Admins, Managers and Staff, the
  -- roles that add and edit customers (418); not an Inventory Manager. Every
  -- store's invoices, as Managers saw them. 406 had Owners and Managers only.
  select public.require_active_staff('{owner,admin,manager,staff}');
$r$;

  -- ══ customer_downline_visits: its header comment and its role check ════
  c_dv_a1 constant text := $a$-- Owner/Manager only. Tier 1: customers they referred; Tier 2: customers
$a$;
  c_dv_r1 constant text := $r$-- for Owners, Admins, Managers and Staff (453; 398: Owner/Manager only).
-- Tier 1: customers they referred; Tier 2: customers
$r$;
  c_dv_a2 constant text := $a$  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can view a downline' using errcode = '42501'; end if;
$a$;
  c_dv_r2 constant text := $r$  -- 453 (the Owner, 22 Oct 2026): the roles that add and edit customers
  -- (418) see a downline, its phones and its export; an Inventory Manager, a
  -- login that is not active staff and a signed-out caller are refused
  -- (42501), as for the Profile's figures.
  perform public.require_active_staff('{owner,admin,manager,staff}');
$r$;

  -- ══ Relied on, not changed (production, 22 Oct 2026, at 450) ════════════
  c_relied constant text[] := array[
    'require_active_staff(text[])',
    'customer_centre_visits()'];
  c_relied_md5 constant text[] := array[
    '877b3aa74cea559881979bb161c450e2',
    'c07a5a0cbbf52ba45e5dc911b20002da'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; d2 text; n int; k int; i int;
  v_anchors text[]; v_patches text[]; v_before text; v_after text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[] := '{}';
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_staff uuid; t_admin uuid; t_mgr uuid; t_inv uuid; t_none uuid;
  t_top uuid; t_t1 uuid; t_t2 uuid; t_who uuid; t_want jsonb; t_got jsonb; t_state text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The functions relied on are as read on production (22 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '453: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('customer_profile_stats', 'customer_purchase_timeline', 'customer_downline_visits')
     and p.oid::regprocedure::text not in (c_ps, c_pt, c_dv);
  if v is not null then raise exception '453: another function takes the name of one this changes: %', v; end if;

  -- Each patched function: its BEFORE (patched; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  foreach v in array array[c_ps, c_pt, c_dv] loop
    if to_regprocedure('public.' || v) is null then raise exception '453: public.% is missing', v; end if;
    if v = c_ps then
      v_anchors := array[c_ps_a]; v_patches := array[c_ps_r]; v_before := c_ps_before; v_after := c_ps_after;
    elsif v = c_pt then
      v_anchors := array[c_pt_a]; v_patches := array[c_pt_r]; v_before := c_pt_before; v_after := c_pt_after;
    else
      v_anchors := array[c_dv_a1, c_dv_a2]; v_patches := array[c_dv_r1, c_dv_r2]; v_before := c_dv_before; v_after := c_dv_after;
    end if;
    d := pg_get_functiondef(to_regprocedure('public.' || v));
    if md5(d) = v_after then
      raise notice '453: public.% is already this version; left alone', v;
      continue;
    end if;
    d2 := d;
    for k in 1 .. cardinality(v_anchors) loop
      n := (length(d) - length(replace(d, v_anchors[k], ''))) / length(v_anchors[k]);
      if n <> 1 then
        raise exception '453: the anchor % of public.% is found % times, not once (md5 %). Re-read it and re-test before applying.', k, v, n, md5(d); end if;
      d2 := replace(d2, v_anchors[k], v_patches[k]);
    end loop;
    if md5(d) <> v_before then
      raise exception '453: public.% is not the version this was tested against (md5 %; patched it would be md5 %). Re-read it and re-test before applying.', v, md5(d), md5(d2); end if;
    if md5(d2) <> v_after then
      raise exception '453: the text built for public.% is not the tested one (md5 %)', v, md5(d2); end if;
    v_fns := v_fns || v;
    v_defs := v_defs || d2;
  end loop;

  -- The grants of the three, to compare after (as sets: production lists
  -- them in another order than a local copy does).
  foreach v in array array[c_ps, c_pt, c_dv] loop
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v));
  end loop;

  -- ── Install ───────────────────────────────────────────────────────────────
  for k in 1 .. coalesce(cardinality(v_fns), 0) loop
    execute v_defs[k];
  end loop;

  -- ── Afterwards: installed exactly as tested, grants as before ────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_ps))) <> c_ps_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_pt))) <> c_pt_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_dv))) <> c_dv_after then
    raise exception '453: public.%, public.% or public.% is not at its AFTER md5 (% / % / %)', c_ps, c_pt, c_dv,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_ps))), md5(pg_get_functiondef(to_regprocedure('public.' || c_pt))),
      md5(pg_get_functiondef(to_regprocedure('public.' || c_dv))); end if;
  k := 0;
  foreach v in array array[c_ps, c_pt, c_dv] loop
    k := k + 1;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v)) is distinct from v_acl[k] then
      raise exception '453: the grants of public.% changed', v; end if;
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '453: who may call public.% is not as before (signed-in staff and the service role, not signed out)', v; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("453 check", @example.invalid, fictional ACMA phones
  -- no customer uses); it ends by raising P0453, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(4530, 4999) g
             where not exists (select 1 from public.customers c
                                where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(g::text, 4, '0'))
             limit 3) y;
    if coalesce(cardinality(t_phones), 0) < 3 then raise exception '453: the self-test found no unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '453-check-staff-' || t_sfx || '@example.invalid') returning id into t_staff;
    insert into auth.users (id, email) values (gen_random_uuid(), '453-check-admin-' || t_sfx || '@example.invalid') returning id into t_admin;
    insert into auth.users (id, email) values (gen_random_uuid(), '453-check-manager-' || t_sfx || '@example.invalid') returning id into t_mgr;
    insert into auth.users (id, email) values (gen_random_uuid(), '453-check-invman-' || t_sfx || '@example.invalid') returning id into t_inv;
    insert into auth.users (id, email) values (gen_random_uuid(), '453-check-none-' || t_sfx || '@example.invalid') returning id into t_none;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '453 check ' || x.r, u.email, x.r::public.user_role, true
      from (values (t_staff, 'staff'), (t_admin, 'admin'), (t_mgr, 'manager'), (t_inv, 'inventory_manager')) x(id, r)
      join auth.users u on u.id = x.id;
    insert into public.customers (full_name, phone) values ('453 Check Referrer ' || t_sfx, t_phones[1]) returning id into t_top;
    insert into public.customers (full_name, phone, referred_by) values ('453 Check Friend ' || t_sfx, t_phones[2], t_top) returning id into t_t1;
    insert into public.customers (full_name, phone, referred_by) values ('453 Check Friend Two ' || t_sfx, t_phones[3], t_t1) returning id into t_t2;

    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    -- The Manager's answers (as before 453), then Staff's and the Admin's.
    perform set_config('request.jwt.claim.sub', t_mgr::text, true);
    t_want := jsonb_build_array(public.customer_profile_stats(t_top), public.customer_purchase_timeline(t_top),
                                public.customer_downline_visits(t_top));
    if (t_want->0->>'referred_count')::int <> 1 or (t_want->0->>'purchases')::int <> 0 or t_want->1 <> '[]'::jsonb
       or jsonb_array_length(t_want->2->'tier1') <> 1 or jsonb_array_length(t_want->2->'tier2') <> 1
       or t_want->2->'tier1'->0->>'customer_id' <> t_t1::text or t_want->2->'tier2'->0->>'customer_id' <> t_t2::text then
      raise exception '453: the Manager''s answers are not as tested (%)', t_want; end if;
    foreach t_who in array array[t_staff, t_admin] loop
      perform set_config('request.jwt.claim.sub', t_who::text, true);
      t_got := jsonb_build_array(public.customer_profile_stats(t_top), public.customer_purchase_timeline(t_top),
                                 public.customer_downline_visits(t_top));
      if t_got is distinct from t_want then
        raise exception '453: % does not get the Manager''s answers (% / %)',
          (select p.role from public.profiles p where p.id = t_who), t_got, t_want; end if;
    end loop;
    -- Refused: the Inventory Manager, a login with no profile; each call 42501.
    foreach t_who in array array[t_inv, t_none] loop
      perform set_config('request.jwt.claim.sub', t_who::text, true);
      foreach v in array array[c_ps, c_pt, c_dv] loop
        t_state := 'answered';
        begin
          execute format('select public.%s($1)', split_part(v, '(', 1)) using t_top;
        exception when others then t_state := sqlstate;
        end;
        if t_state <> '42501' then
          raise exception '453: public.% %, not 42501, for %', v, t_state,
            case when t_who = t_inv then 'an Inventory Manager' else 'a login with no profile' end; end if;
      end loop;
    end loop;

    raise exception using errcode = 'P0453', message = '453: self-test done, undone';
  exception when sqlstate 'P0453' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
