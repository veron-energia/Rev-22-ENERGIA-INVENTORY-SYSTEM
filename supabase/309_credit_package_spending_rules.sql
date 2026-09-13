begin;
-- =====================================================================
-- WHAT A PACKAGE'S CREDIT MAY BUY IS THE OWNER'S DECISION, PER PACKAGE
--
-- 242 built the enforcement: purchase_category() classifies what is being
-- bought, credit_lot_policy() names the policy a balance falls under, and
-- credit_policy_allows() decides. All of that stays. What it could not do was
-- vary by package -- the allowed categories were written into the function, so
-- every credit package in the business shared one rule and only a migration
-- could change it.
--
-- Two of those built-in defaults also disagree with the approved policy:
--
--   paid   was  therapy_session + session_voucher
--          now  therapy_session only
--          "Paid credit must not buy therapy vouchers or unlimited therapy
--          packages by default."
--
--   bonus  was  own_product
--          now  own_product + third_party_product
--
-- Premium-bundle credit is untouched: bundle_any already permits everything
-- except another credit package or premium bundle, which is exactly the rule,
-- and those two are not offerable as package categories here either.
--
-- A balance whose source cannot be identified stays 'needs_review' and buys
-- nothing. That was 242's choice and it is kept: silently treating an unknown
-- source as unrestricted is how restricted credit escapes.
--
-- Additive. Idempotent. No existing balance, grant or past spend is altered.
-- =====================================================================

-- ---------------------------------------------------------------------
-- The categories an Owner may choose between.
--
-- credit_package and premium_bundle are deliberately absent: credit must not
-- buy more credit, and offering them as a choice would make that possible.
-- 'unknown' is absent because it is the absence of a classification.
-- ---------------------------------------------------------------------
create or replace function public.credit_spendable_categories()
returns text[] language sql immutable as $$
 select array['therapy_session','unlimited_therapy','session_voucher','money_voucher',
              'own_product','third_party_product','other_product','promotion']::text[]
$$;
comment on function public.credit_spendable_categories() is
 'Categories an Owner may allow a credit package''s balance to buy. Excludes credit_package and premium_bundle: credit may never buy more credit.';
grant execute on function public.credit_spendable_categories() to authenticated;

-- The approved defaults, in one place so the table and the resolver agree.
create or replace function public.credit_package_default_rules()
returns jsonb language sql immutable as $$
 select jsonb_build_object(
   'paid',  jsonb_build_array('therapy_session'),
   'bonus', jsonb_build_array('own_product','third_party_product'))
$$;
grant execute on function public.credit_package_default_rules() to authenticated;

create table if not exists public.credit_package_spending_rules (
  package_id uuid primary key references public.credit_packages(id) on delete cascade,
  paid_categories text[] not null,
  bonus_categories text[] not null,
  reason text,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);
comment on table public.credit_package_spending_rules is
 'Owner-set categories a package''s paid and bonus credit may buy. Absent means the approved defaults apply.';

create table if not exists public.credit_package_spending_rule_history (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.credit_packages(id) on delete cascade,
  before_rules jsonb,
  after_rules jsonb not null,
  affected_customers integer,
  affected_paid_credit numeric(12,2),
  affected_bonus_credit numeric(12,2),
  reason text not null,
  changed_by uuid references public.profiles(id),
  changed_at timestamptz not null default now()
);
comment on table public.credit_package_spending_rule_history is
 'Every policy change, so an auditor can tell which rules applied to a transaction when it was processed.';
create index if not exists credit_package_spending_rule_history_pkg_idx
  on public.credit_package_spending_rule_history(package_id, changed_at desc);

alter table public.credit_package_spending_rules enable row level security;
alter table public.credit_package_spending_rule_history enable row level security;
do $$
begin
 -- Staff and Managers may SEE the rules, so the payment screen can explain
 -- what a balance covers. Only the functions below may write them.
 if not exists (select 1 from pg_policy where polrelid='public.credit_package_spending_rules'::regclass
                 and polname='read credit package spending rules') then
  create policy "read credit package spending rules" on public.credit_package_spending_rules
    for select using (auth.uid() is not null);
 end if;
 if not exists (select 1 from pg_policy where polrelid='public.credit_package_spending_rule_history'::regclass
                 and polname='read credit package rule history') then
  create policy "read credit package rule history" on public.credit_package_spending_rule_history
    for select using (public.is_owner_or_manager());
 end if;
end $$;
grant select on public.credit_package_spending_rules to authenticated;
grant select on public.credit_package_spending_rule_history to authenticated;

-- ---------------------------------------------------------------------
-- The rules in force for a package right now.
-- ---------------------------------------------------------------------
create or replace function public.credit_package_effective_rules(p_package_id uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
 select case when r.package_id is null then
   public.credit_package_default_rules() || jsonb_build_object('source','default')
 else
   jsonb_build_object('paid',to_jsonb(r.paid_categories),'bonus',to_jsonb(r.bonus_categories),
                      'source','configured','updated_at',r.updated_at,
                      'updated_by',(select full_name from public.profiles where id=r.updated_by))
 end
 from (select p_package_id id) q
 left join public.credit_package_spending_rules r on r.package_id = q.id
$$;
grant execute on function public.credit_package_effective_rules(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Does THIS balance allow THIS purchase?
--
-- Resolved from the balance's own source package and the policy in force now,
-- so a rule change reaches existing unused credit without touching a single
-- balance amount or past spend.
-- ---------------------------------------------------------------------
create or replace function public.credit_lot_allows_category(p_lot_id uuid, p_category text)
returns boolean language plpgsql stable security definer set search_path to 'public' as $$
declare orig public.customer_credit_lots%rowtype; v_policy text; v_rules jsonb; v_list jsonb;
begin
 if not public.can_view_customer_credit() then return false; end if;
 select * into orig from public.customer_credit_lots
  where id = public.invoice_credit_transfer_origin(p_lot_id);
 if not found then return false; end if;

 v_policy := public.credit_lot_policy(orig.source_type, orig.category, orig.source_record_id is not null);

 -- A credit package's balance follows that package's own rules.
 if v_policy in ('package_paid','package_bonus') then
  v_rules := public.credit_package_effective_rules(orig.source_record_id);
  v_list  := case when v_policy = 'package_paid' then v_rules->'paid' else v_rules->'bonus' end;
  -- Credit may never buy more credit, whatever a rule row says.
  if p_category in ('credit_package','premium_bundle','unknown') then return false; end if;
  return coalesce(v_list ? p_category, false);
 end if;

 -- Everything else keeps the behaviour 242 gave it.
 return public.credit_policy_allows(v_policy, p_category);
end $$;
grant execute on function public.credit_lot_allows_category(uuid,text) to authenticated;

-- ---------------------------------------------------------------------
-- What changing a rule would actually affect, before anybody changes it.
-- ---------------------------------------------------------------------
create or replace function public.preview_credit_package_policy_change(
  p_package_id uuid, p_paid text[], p_bonus text[])
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_before jsonb; v_cust int; v_paid numeric; v_bonus numeric; v_bad text[];
begin
 if not public.is_owner() then
  raise exception 'Only an Owner can review credit package spending rules' using errcode='42501'; end if;
 if not exists(select 1 from public.credit_packages where id=p_package_id and deleted_at is null) then
  raise exception 'Credit package not found'; end if;

 select array_agg(c) into v_bad from unnest(coalesce(p_paid,'{}') || coalesce(p_bonus,'{}')) c
  where not (c = any(public.credit_spendable_categories()));
 if v_bad is not null then
  raise exception 'Not a category credit may be spent on: %', array_to_string(v_bad,', '); end if;

 v_before := public.credit_package_effective_rules(p_package_id);

 -- Balances that would follow the new rules: unused credit from this package.
 select count(distinct l.customer_id),
        coalesce(sum(l.remaining_amount) filter (where l.category='paid'),0),
        coalesce(sum(l.remaining_amount) filter (where l.category='bonus'),0)
   into v_cust, v_paid, v_bonus
   from public.customer_credit_lots l
  where l.source_type='credit_package' and l.source_record_id=p_package_id
    and l.status='active' and l.remaining_amount > 0;

 return jsonb_build_object(
   'package_id',p_package_id,
   'package',(select name from public.credit_packages where id=p_package_id),
   'before',v_before,
   'after',jsonb_build_object('paid',to_jsonb(coalesce(p_paid,'{}')),'bonus',to_jsonb(coalesce(p_bonus,'{}'))),
   'affected_customers',coalesce(v_cust,0),
   'affected_paid_credit',v_paid,
   'affected_bonus_credit',v_bonus,
   'note','Unused balances from this package and every future purchase of it will follow the new rules. No balance amount, past spend or original grant changes.');
end $$;
grant execute on function public.preview_credit_package_policy_change(uuid,text[],text[]) to authenticated;

-- ---------------------------------------------------------------------
-- Setting them. Owner only, reason required, every change kept.
-- ---------------------------------------------------------------------
create or replace function public.set_credit_package_spending_rules(
  p_package_id uuid, p_paid text[], p_bonus text[], p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_preview jsonb; v_before jsonb;
begin
 -- Enforced here, not by hiding a button: a direct API call meets the same rule.
 if not public.is_owner() then
  raise exception 'Only an Owner can change credit package spending rules' using errcode='42501'; end if;
 if nullif(trim(coalesce(p_reason,'')),'') is null then
  raise exception 'Give a reason for the policy change; it is kept in the history'; end if;

 v_preview := public.preview_credit_package_policy_change(p_package_id,p_paid,p_bonus);
 v_before  := v_preview->'before';

 insert into public.credit_package_spending_rules(package_id,paid_categories,bonus_categories,reason,updated_by,updated_at)
 values(p_package_id,coalesce(p_paid,'{}'),coalesce(p_bonus,'{}'),trim(p_reason),auth.uid(),now())
 on conflict (package_id) do update
   set paid_categories=excluded.paid_categories, bonus_categories=excluded.bonus_categories,
       reason=excluded.reason, updated_by=excluded.updated_by, updated_at=now();

 insert into public.credit_package_spending_rule_history
   (package_id,before_rules,after_rules,affected_customers,affected_paid_credit,affected_bonus_credit,reason,changed_by)
 values(p_package_id,v_before,v_preview->'after',
        (v_preview->>'affected_customers')::int,
        (v_preview->>'affected_paid_credit')::numeric,
        (v_preview->>'affected_bonus_credit')::numeric,
        trim(p_reason),auth.uid());

 perform public.write_audit('credit_package_spending_rules',p_package_id,
   'credit_spending_rules_changed',v_before,v_preview->'after');

 return v_preview || jsonb_build_object('saved',true);
end $$;
grant execute on function public.set_credit_package_spending_rules(uuid,text[],text[],text) to authenticated;

-- ---------------------------------------------------------------------
-- A read-only summary for the payment screen, for anyone who may see credit.
-- ---------------------------------------------------------------------
create or replace function public.credit_lot_spending_summary(p_lot_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare orig public.customer_credit_lots%rowtype; v_policy text; v_rules jsonb; v_list jsonb;
begin
 if not public.can_view_customer_credit() then raise exception 'Credit not visible'; end if;
 select * into orig from public.customer_credit_lots where id=public.invoice_credit_transfer_origin(p_lot_id);
 if not found then return jsonb_build_object('policy','needs_review','allowed','[]'::jsonb,
   'explanation','This balance''s source could not be identified, so it is held for review.'); end if;
 v_policy:=public.credit_lot_policy(orig.source_type,orig.category,orig.source_record_id is not null);
 if v_policy in ('package_paid','package_bonus') then
  v_rules:=public.credit_package_effective_rules(orig.source_record_id);
  v_list:=case when v_policy='package_paid' then v_rules->'paid' else v_rules->'bonus' end;
  return jsonb_build_object('policy',v_policy,'allowed',v_list,'rules_source',v_rules->>'source',
    'package',(select name from public.credit_packages where id=orig.source_record_id),
    'explanation','This balance may be spent on: '||
      coalesce(nullif((select string_agg(replace(x#>>'{}','_',' '),', ') from jsonb_array_elements(v_list) x),''),'nothing yet'));
 end if;
 return jsonb_build_object('policy',v_policy,
   'allowed',(select coalesce(jsonb_agg(c),'[]'::jsonb) from unnest(public.credit_spendable_categories()) c
               where public.credit_policy_allows(v_policy,c)),
   'explanation',case when v_policy='bundle_any'
     then 'Premium bundle credit: anything except another credit package or premium bundle.'
     when v_policy='open' then 'No category restriction, except buying more credit.'
     else 'Held for review.' end);
end $$;
grant execute on function public.credit_lot_spending_summary(uuid) to authenticated;

-- Owner, as its own predicate. is_owner_or_manager() already existed; this is
-- the narrower one the policy functions need.
create or replace function public.is_owner()
returns boolean language sql security definer set search_path to 'public' as $$
  select exists (select 1 from public.profiles
    where id = auth.uid() and role = 'owner' and is_active = true and deleted_at is null)
$$;
grant execute on function public.is_owner() to authenticated;

-- ---------------------------------------------------------------------
-- The three places that actually decide now resolve per package.
--
-- Patched in place, by content, rather than restated: these are long functions
-- and the surrounding logic (bonus-first ordering, composite promotions,
-- per-lot usage_restrictions) is correct and must not be disturbed.
-- ---------------------------------------------------------------------
do $do$
declare f text; v_n int := 0;
begin
 -- 1. consume_customer_credit: both the availability sum and the take loop.
 select pg_get_functiondef('public.consume_customer_credit(uuid,numeric,text,uuid,uuid,text,text,text,uuid)'::regprocedure) into f;
 if position('credit_lot_allows_category' in f) = 0 then
  f := replace(f,
    '       and public.credit_policy_allows('||chr(10)||
    '             public.credit_lot_policy_for(id),'||chr(10)||
    '             public.purchase_category(p_purpose, null, p_voucher_id, null));',
    '       and public.credit_lot_allows_category(id,'||chr(10)||
    '             public.purchase_category(p_purpose, null, p_voucher_id, null));');
  f := replace(f,
    '       and public.credit_policy_allows('||chr(10)||
    '             public.credit_lot_policy_for(id),'||chr(10)||
    '             public.purchase_category(p_purpose, null, p_voucher_id, null))',
    '       and public.credit_lot_allows_category(id,'||chr(10)||
    '             public.purchase_category(p_purpose, null, p_voucher_id, null))');
  if position('credit_lot_allows_category' in f) = 0 then
   raise exception 'consume_customer_credit does not match what 309 expects — align it by hand'; end if;
  execute f; v_n := v_n + 1;
  raise notice 'consume_customer_credit now resolves the package''s own rules';
 end if;
end $do$;

do $do$
declare f text;
begin
 -- 2. credit_lot_line_allowed: single lines and composite promotions.
 select pg_get_functiondef(p.oid) into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and p.proname='credit_lot_line_allowed';
 if f is null then raise notice 'credit_lot_line_allowed not installed'; return; end if;
 if position('credit_lot_allows_category' in f) > 0 then
  raise notice 'credit_lot_line_allowed already resolves per package'; return; end if;
 f := replace(f, 'return public.credit_policy_allows(v_policy, v_cat);',
                 'return public.credit_lot_allows_category(p_lot_id, v_cat);');
 f := replace(f, 'count(*) filter (where not public.credit_policy_allows(v_policy,',
                 'count(*) filter (where not public.credit_lot_allows_category(p_lot_id,');
 if position('credit_lot_allows_category' in f) = 0 then
  raise exception 'credit_lot_line_allowed does not match what 309 expects — align it by hand'; end if;
 execute f;
 raise notice 'credit_lot_line_allowed now resolves the package''s own rules';
end $do$;


do $do$
declare f text; v_old text; v_new text;
begin
 select pg_get_functiondef(p.oid) into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and p.proname='customer_credit_eligibility';
 if position('credit_lot_allows_category' in f) > 0 then
  raise notice 'customer_credit_eligibility already resolves per package'; return; end if;
 v_old := '            where public.credit_policy_allows('||chr(10)||
          '              public.credit_lot_policy_for(l.id), c)), ''{}''),';
 v_new := '            -- The list a person sees must be the list that will actually'||chr(10)||
          '            -- be honoured, so it resolves the same way spending does.'||chr(10)||
          '            where public.credit_lot_allows_category(l.id, c)), ''{}''),';
 if position(v_old in f) = 0 then
  raise exception 'customer_credit_eligibility does not match what 309 expects — align it by hand'; end if;
 execute replace(f, v_old, v_new);
 raise notice 'customer_credit_eligibility now shows the package''s own rules';
end $do$;

notify pgrst,'reload schema';


-- ---------------------------------------------------------------------
-- The snapshot must stop gating categories for package credit.
--
-- 94 froze a package's categories onto each lot at grant time, deliberately:
-- "editing the package later cannot change what already-issued credit is
-- allowed to buy." That is the opposite of what is wanted now — an Owner's
-- rule has to reach unused balances — and because the snapshot is ANDed with
-- the new rule, leaving it in place lets a rule only ever narrow. A package
-- that was voucher-only (which is what 94's backfill produced for every
-- package with nothing ticked) grants paid credit the default rule says may
-- buy a therapy session and the snapshot says may not: 0 usable, spendable on
-- nothing at all.
--
-- So for package credit the rules decide the category, and the snapshot keeps
-- only the narrower thing it alone knows — an explicit list of voucher ids,
-- which is about WHICH voucher rather than which category. Every other kind of
-- lot keeps 94's behaviour untouched.
-- ---------------------------------------------------------------------
create or replace function public.credit_lot_snapshot_allows(
  p_lot_id uuid, p_restrictions jsonb, p_purpose text, p_voucher_id uuid default null)
returns boolean language plpgsql stable security definer set search_path to 'public' as $$
declare orig public.customer_credit_lots%rowtype; v_policy text; v_ids jsonb;
begin
 select * into orig from public.customer_credit_lots
  where id = public.invoice_credit_transfer_origin(p_lot_id);
 if not found then return public.credit_lot_allows(p_restrictions, p_purpose, p_voucher_id); end if;

 v_policy := public.credit_lot_policy(orig.source_type, orig.category, orig.source_record_id is not null);
 if v_policy not in ('package_paid','package_bonus') then
  return public.credit_lot_allows(p_restrictions, p_purpose, p_voucher_id);
 end if;

 -- Category is credit_lot_allows_category()'s decision now. Only an explicit
 -- voucher list still binds, and only when a voucher is what is being bought.
 v_ids := coalesce(p_restrictions->'allowed_voucher_ids', '[]'::jsonb);
 if p_purpose <> 'voucher' or jsonb_array_length(v_ids) = 0 then return true; end if;
 if p_voucher_id is null then return false; end if;
 return v_ids ? p_voucher_id::text;
end $$;
grant execute on function public.credit_lot_snapshot_allows(uuid,jsonb,text,uuid) to authenticated;

do $do$
declare f text;
begin
 select pg_get_functiondef('public.consume_customer_credit(uuid,numeric,text,uuid,uuid,text,text,text,uuid)'::regprocedure) into f;
 if position('credit_lot_snapshot_allows' in f) = 0 then
  f := replace(f,
    'public.credit_lot_allows(usage_restrictions, p_purpose, p_voucher_id)',
    'public.credit_lot_snapshot_allows(id, usage_restrictions, p_purpose, p_voucher_id)');
  if position('credit_lot_snapshot_allows' in f) = 0 then
   raise exception 'consume_customer_credit snapshot check does not match what 309 expects — align it by hand'; end if;
  execute f;
  raise notice 'consume_customer_credit: snapshot no longer gates package categories';
 end if;
end $do$;

do $do$
declare f text;
begin
 select pg_get_functiondef(p.oid) into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and p.proname='allocate_invoice_wallet_credit';
 if f is null then raise notice 'allocate_invoice_wallet_credit not installed'; return; end if;
 if position('credit_lot_snapshot_allows' in f) > 0 then return; end if;
 f := replace(f,
   'public.credit_lot_allows(l.usage_restrictions, v_purpose, v_vid)',
   'public.credit_lot_snapshot_allows(l.id, l.usage_restrictions, v_purpose, v_vid)');
 if position('credit_lot_snapshot_allows' in f) = 0 then
  raise exception 'allocate_invoice_wallet_credit snapshot check does not match what 309 expects — align it by hand'; end if;
 execute f;
 raise notice 'allocate_invoice_wallet_credit: snapshot no longer gates package categories';
end $do$;

notify pgrst,'reload schema';
commit;
