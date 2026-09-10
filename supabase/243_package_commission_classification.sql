-- =====================================================================
-- ENERGIA — CREDIT PACKAGES MUST COMMISSION AT THE THIRD-PARTY RATE
--
-- What I found, by reading the path rather than the dropdown.
--
-- Package sales do NOT go through earn_invoice_commission: migration 81
-- excludes credit lines from it, and the two dedicated functions book the
-- commission instead —
--
--   earn_credit_package_commission(sale_id)
--   earn_premium_bundle_commission(sale_id)
--
-- Both are already right about the basis, and worth stating so it is not
-- "fixed" later by someone who assumes otherwise:
--
--   * the basis is credit_package_sales.external_paid / premium_bundle_sales
--     .external_paid — money actually received, never issued credit face value
--     and never bonus credit;
--   * a sale with no external payment earns nothing at all;
--   * spending that credit later touches no commission path, so a second
--     commission on the same money is not possible;
--   * rates come from app_settings (commission_tier1_third_rate, default 4.5;
--     commission_tier2_third_rate, default 5), with the rate SNAPSHOT on the
--     sale row taking precedence — which is how an old sale keeps the rate it
--     was sold under when the setting changes.
--
-- The defect is the classification, and it is only on one of the two:
--
--   premium_bundles.commission_classification  default 'third_party'   correct
--   credit_packages.commission_classification  default 'own'           WRONG
--
-- earn_credit_package_commission reads
-- `coalesce(s.classification_snapshot, 'own')`, so a credit package created
-- without someone explicitly choosing third-party commissions at the OWN rate —
-- 15% instead of 4.5%, more than three times the intended amount.
--
-- The requirement is that both package types are third-party, always. So this
-- is not a better default: the choice is removed. A configuration option that
-- can contradict a mandatory rule is a defect waiting to recur.
--
-- Historical sales are NOT rewritten. Their commission was earned and may have
-- been paid; §11 of the brief is explicit that completed payouts stay. The
-- diagnostic at the end of this file lists what was affected so a repair can be
-- reviewed and decided by a person.
--
-- Additive. Changes no existing commission row and no payout. Run AFTER 79, 80
-- and 153/154.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The rule, in one place, so both tables and both functions agree.
-- ---------------------------------------------------------------------
create or replace function public.package_commission_classification()
returns text language sql immutable as $function$
  -- Credit packages and premium bundles are third-party sales for commission
  -- purposes. This is a business rule, not a setting.
  select 'third_party'::text
$function$;

comment on function public.package_commission_classification() is
  'The mandatory commission classification for credit-package and premium-bundle '
  'sales. Rates remain configurable in app_settings; the classification does not.';

-- ---------------------------------------------------------------------
-- 2. The catalogue cannot say anything else.
--
-- A check constraint rather than a default: a default is a suggestion, and the
-- upsert functions below accept a parameter that could override it.
--
-- The existing rows have to be corrected FIRST, and not for tidiness. A NOT
-- VALID check constraint skips the rows already in the table, but it still
-- binds every later INSERT **and UPDATE** — including an update to a row that
-- already violates it. Leaving a package classified 'own' behind the constraint
-- would make that package uneditable: renaming it or changing its price would
-- fail with a constraint violation, for a reason nobody at the counter could
-- possibly work out.
--
-- This corrects a SETTING, not money. classification_snapshot on past sales is
-- untouched, no commission row is read or written, and the commission functions
-- below no longer consult this column at all — so nothing about what was earned
-- or paid changes. Section 5's diagnostic still reports the historical effect.
-- ---------------------------------------------------------------------
alter table public.credit_packages
  alter column commission_classification set default 'third_party';
alter table public.premium_bundles
  alter column commission_classification set default 'third_party';

do $$
declare v_cp integer := 0; v_pb integer := 0; r record;
begin
  for r in select id, name, commission_classification from public.credit_packages
            where commission_classification is distinct from 'third_party' loop
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
    values ('credit_packages', r.id, 'commission_classification_corrected',
            jsonb_build_object('commission_classification', r.commission_classification),
            jsonb_build_object('commission_classification', 'third_party',
                               'reason', 'Package sales commission at the third-party rate by rule'),
            null);
    v_cp := v_cp + 1;
  end loop;
  update public.credit_packages set commission_classification = 'third_party'
   where commission_classification is distinct from 'third_party';

  for r in select id, name, commission_classification from public.premium_bundles
            where commission_classification is distinct from 'third_party' loop
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
    values ('premium_bundles', r.id, 'commission_classification_corrected',
            jsonb_build_object('commission_classification', r.commission_classification),
            jsonb_build_object('commission_classification', 'third_party',
                               'reason', 'Bundle sales commission at the third-party rate by rule'),
            null);
    v_pb := v_pb + 1;
  end loop;
  update public.premium_bundles set commission_classification = 'third_party'
   where commission_classification is distinct from 'third_party';

  if v_cp + v_pb > 0 then
    raise notice 'Catalogue classification corrected on % credit package(s) and % premium bundle(s). '
                 'Past sale snapshots and every commission row are unchanged.', v_cp, v_pb;
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'credit_packages_third_party_commission') then
    alter table public.credit_packages
      add constraint credit_packages_third_party_commission
      check (commission_classification = 'third_party');
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'premium_bundles_third_party_commission') then
    alter table public.premium_bundles
      add constraint premium_bundles_third_party_commission
      check (commission_classification = 'third_party');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. The upsert functions stop accepting a classification.
--
-- The parameter is kept so existing callers still compile, and ignored so they
-- cannot express something the rule forbids. A caller passing 'own' now gets a
-- third-party package rather than a silently wrong one.
-- ---------------------------------------------------------------------
do $$
declare r record; f text; v_patched integer := 0; v_seen integer := 0;
begin
  -- Found by NAME, across every overload. A hardcoded signature list was here
  -- before and it silently matched nothing: migration 94 redefines
  -- upsert_credit_package with twelve more arguments, and 96 does the same to
  -- upsert_premium_bundle, so the signatures from 79 and 80 no longer exist by
  -- the time this runs. The loop skipped both, the functions kept honouring the
  -- caller's classification, and the check constraint added above then rejected
  -- the save — so the Therapy page could not store a credit package at all.
  --
  -- Nothing here assumes a signature. Any overload that reads the parameter is
  -- patched; anything else is left alone.
  for r in
    select p.oid, p.oid::regprocedure::text as sig, pg_get_functiondef(p.oid) as def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('upsert_credit_package', 'upsert_premium_bundle')
     order by p.oid
  loop
    if position('p_commission_classification' in r.def) = 0 then continue; end if;
    v_seen := v_seen + 1;
    if position('public.package_commission_classification()' in r.def) > 0 then
      continue;                                  -- already patched
    end if;
    f := r.def;
    -- Replace every read of the parameter with the fixed rule.
    f := replace(f, 'coalesce(p_commission_classification,''own'')',
                    'public.package_commission_classification()');
    f := replace(f, 'coalesce(p_commission_classification,''third_party'')',
                    'public.package_commission_classification()');
    f := replace(f, 'p_commission_classification,',
                    'public.package_commission_classification(),');
    f := replace(f, 'commission_classification = p_commission_classification',
                    'commission_classification = public.package_commission_classification()');
    -- And neutralise the guard that used to reject anything but the two values,
    -- so passing 'own' is accepted and ignored rather than raising.
    f := replace(f,
      'if p_commission_classification not in (''own'',''third_party'') then',
      'if false then');
    if position('public.package_commission_classification()' in f) = 0 then
      -- Refusing to leave a function that still writes a value the constraint
      -- rejects: that combination is what broke saving a package.
      raise exception 'Could not neutralise the classification parameter in % — patch it by hand', r.sig;
    end if;
    execute f;
    v_patched := v_patched + 1;
    raise notice 'classification parameter neutralised in %', r.sig;
  end loop;

  if v_seen = 0 then
    raise notice 'No package upsert function takes a classification parameter here; nothing to neutralise.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. New sales use the rule even if an old catalogue row still says 'own'.
--
-- The snapshot is what the commission function reads, so this is the line that
-- actually changes what gets paid. Existing snapshots are untouched.
-- ---------------------------------------------------------------------
do $$
declare f text; sig text;
begin
  foreach sig in array array[
    'public.earn_credit_package_commission(uuid)',
    'public.earn_premium_bundle_commission(uuid)']
  loop
    select pg_get_functiondef(sig::regprocedure) into f;
    -- Already patched by an earlier run of this migration: nothing to do. The
    -- check has to come first, because after the patch the anchor below is gone
    -- and its absence would otherwise look like the function had been rewritten.
    if position('v_ptype := public.package_commission_classification()' in f) > 0 then
      continue;
    end if;
    if position('v_ptype := coalesce(s.classification_snapshot' in f) = 0 then
      raise exception 'Unexpected % definition — the classification line has moved', sig;
    end if;
    -- The snapshot is still recorded and still shown; it just cannot select a
    -- rate that the rule forbids.
    f := regexp_replace(f,
      'v_ptype := coalesce\(s\.classification_snapshot, ''(own|third_party)''\);',
      'v_ptype := public.package_commission_classification();');
    execute f;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. What the old default did, read-only.
--
-- One row per package sale that commissioned at the own-brand rate, with what
-- the third-party rate would have produced. Nothing here changes a commission,
-- a payout or an amount: it exists so a person can decide.
-- ---------------------------------------------------------------------
create or replace function public.package_commission_diagnostic()
returns table (
  sale_kind text, sale_id uuid, invoice_id uuid, invoice_no text,
  customer_name text, sold_on date,
  external_paid numeric, classification_used text,
  tier1_rate_used numeric, tier1_commission numeric,
  tier1_rate_expected numeric, tier1_commission_expected numeric,
  difference numeric, payout_status text)
language sql stable security definer set search_path = public as $function$
  with settings as (select commission_tier1_third_rate as third_rate from public.app_settings where id = true),
  sales as (
    select 'credit_package'::text as kind, s.id, s.invoice_id, s.customer_id,
           s.external_paid, coalesce(s.classification_snapshot,'own') as classification,
           s.created_at::date as sold_on
      from public.credit_package_sales s
    union all
    select 'premium_bundle', s.id, s.invoice_id, s.customer_id,
           s.external_paid, coalesce(s.classification_snapshot,'third_party'),
           s.created_at::date
      from public.premium_bundle_sales s
  )
  select sa.kind, sa.id, sa.invoice_id, i.invoice_no, c.full_name, sa.sold_on,
         sa.external_paid, sa.classification,
         co.rate, co.commission_amount,
         st.third_rate,
         round(coalesce(sa.external_paid,0) * st.third_rate / 100.0, 2),
         co.commission_amount - round(coalesce(sa.external_paid,0) * st.third_rate / 100.0, 2),
         -- A commission already grouped into a payout is history. It is
         -- reported, never proposed for editing.
         case when co.payout_id is not null then 'paid out'
              when co.status::text = 'reversed' then 'reversed'
              else 'not yet paid out' end
    from sales sa
    cross join settings st
    left join public.invoices i on i.id = sa.invoice_id
    left join public.customers c on c.id = sa.customer_id
    join public.commissions co on co.invoice_id = sa.invoice_id and co.tier = 'tier1'
   where sa.classification <> 'third_party'
     and public.is_manager_or_above()
   order by sa.sold_on desc
$function$;

-- Catalogue rows still carrying the old classification. Correcting one is a
-- single audited update, deliberately not done here.
create or replace function public.package_classification_gaps()
returns table (kind text, id uuid, name text, classification text, is_active boolean)
language sql stable security definer set search_path = public as $function$
  select 'credit_package', p.id, p.name, p.commission_classification, p.is_active
    from public.credit_packages p
   where p.deleted_at is null and p.commission_classification <> 'third_party'
     and public.is_manager_or_above()
  union all
  select 'premium_bundle', b.id, b.name, b.commission_classification, b.is_active
    from public.premium_bundles b
   where b.deleted_at is null and b.commission_classification <> 'third_party'
     and public.is_manager_or_above()
$function$;

grant execute on function public.package_commission_classification() to authenticated;
grant execute on function public.package_commission_diagnostic() to authenticated;
grant execute on function public.package_classification_gaps() to authenticated;

do $$
declare v_pkg integer; v_bundle integer;
begin
  select count(*) into v_pkg from public.credit_packages
   where deleted_at is null and commission_classification <> 'third_party';
  select count(*) into v_bundle from public.premium_bundles
   where deleted_at is null and commission_classification <> 'third_party';
  raise notice 'Catalogue rows still classified own: % credit package(s), % premium bundle(s).', v_pkg, v_bundle;
  raise notice 'New sales now commission at the third-party rate regardless. Run package_commission_diagnostic() to see historical effect.';
end $$;
