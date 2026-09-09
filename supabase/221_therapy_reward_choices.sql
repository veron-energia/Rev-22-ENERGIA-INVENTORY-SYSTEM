-- =====================================================================
-- ENERGIA — WHY THE CLAIM DIALOG ONLY EVER OFFERED UNLIMITED THERAPY
--
-- Reproduced before changing anything. legacy_reward_options() finds the
-- alternatives for an entitlement by matching today's rules on the exact
-- amount recorded on the entitlement:
--
--     and r.qualifying_amount = e.qualifying_amount
--
-- An entitlement earned under the old S$794 threshold therefore matches
-- nothing once the rules move to S$994, and the function returns zero rows.
-- The dialog then falls back to the kind stored on the entitlement itself —
-- 'unlimited' — so a customer who was entitled to choose 10 vouchers is shown
-- one option and told nothing is wrong. An empty list and a failed request look
-- identical from the frontend, which discards the error entirely.
--
-- Three separate causes, three separate fixes:
--
--   1. Alternatives are grouped by an explicit tier key, not by an amount that
--      changes underneath historical rows. Existing rules are backfilled to the
--      grouping they already had, so nothing moves today.
--   2. Entitlements whose tier no longer exists are REPORTED, with candidates,
--      and mapped only by a person who confirms it. Nothing is auto-attached: a
--      rule at a different threshold is a different promise.
--   3. Affiliates are no longer barred from unlimited rewards in code. Whether
--      an affiliate may choose one is a property of the configured rules, which
--      is what the specification asks for. Where no affiliate rule exists, the
--      diagnostic says so instead of silently offering one option.
--
-- Historical amounts are never rewritten, claimed units are never re-opened,
-- and no additional units are granted.
--
-- Additive. Run AFTER 74 and 220. Safe to run more than once.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. An explicit grouping for "these rewards are alternatives".
--
-- Display names were never a safe grouping — two tiers can both be called
-- "1 Month Unlimited" — and the amount is unstable across a threshold change.
-- ---------------------------------------------------------------------
alter table public.therapy_package_rules
  add column if not exists tier_key text;

alter table public.therapy_entitlements
  add column if not exists reward_tier_key text,
  add column if not exists reward_tier_mapped_by uuid references public.profiles(id),
  add column if not exists reward_tier_mapped_at timestamptz,
  add column if not exists reward_tier_mapping_reason text;

-- Backfill to exactly the grouping the old code implied: same recipient, same
-- amount, same store. This is a restatement of current behaviour, not a change
-- to it — every set of alternatives that resolved before still resolves now.
update public.therapy_package_rules
   set tier_key = coalesce(applies_to, 'customer') || ':' || qualifying_amount::text
                  || ':' || coalesce(store_id::text, 'all')
 where tier_key is null;

create index if not exists idx_therapy_rule_tier
  on public.therapy_package_rules (tier_key) where deleted_at is null;

-- ---------------------------------------------------------------------
-- 2. The options themselves.
--
-- Return columns change (the caller now needs to know which option the
-- entitlement currently holds, and what each one is worth), so the old function
-- is dropped rather than replaced — PostgreSQL refuses to change a function's
-- output columns in place.
-- ---------------------------------------------------------------------
drop function if exists public.legacy_reward_options(uuid);

create or replace function public.legacy_reward_options(p_entitlement_id uuid)
returns table (rule_id uuid, name text, entitlement_kind text,
               duration_months integer, voucher_qty integer,
               tier_key text, applies_to text, is_current_choice boolean)
language plpgsql stable security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare
  e public.therapy_entitlements%rowtype;
  v_recipient text;
  v_tier text;
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
  if not found then return; end if;

  v_recipient := case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end;
  -- An explicitly mapped tier wins. Without one, fall back to the historical
  -- behaviour of matching the amount, so nothing that worked before stops.
  v_tier := e.reward_tier_key;

  return query
    select r.id, r.name, r.entitlement_kind, r.duration_months, r.voucher_qty,
           r.tier_key, coalesce(r.applies_to, 'customer'),
           -- The option the entitlement is already carrying, so the dialog can
           -- preselect it without guessing from the display name.
           (r.entitlement_kind = coalesce(e.entitlement_kind, 'unlimited')
              and (e.rule_id is null or r.id = e.rule_id))
      from public.therapy_package_rules r
     where r.is_active = true and r.deleted_at is null
       and coalesce(r.applies_to, 'customer') = v_recipient
       and (r.store_id = e.store_id or r.store_id is null)
       and (case when v_tier is not null then r.tier_key = v_tier
                 else r.qualifying_amount = e.qualifying_amount end)
     order by r.entitlement_kind, r.name;
end $function$;

-- ---------------------------------------------------------------------
-- 3. When there are no options, say why.
--
-- This is the part that was missing. An empty dropdown and a broken query look
-- the same to a user; this function makes them different, and tells whoever is
-- configuring the system exactly which rule is absent.
-- ---------------------------------------------------------------------
create or replace function public.legacy_reward_options_diagnostic(p_entitlement_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  e public.therapy_entitlements%rowtype;
  v_recipient text; v_count integer; v_kinds text[];
  v_near jsonb; v_reasons jsonb := '[]'::jsonb;
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
  if not found then
    return jsonb_build_object('found', false,
      'reasons', jsonb_build_array('That entitlement no longer exists.'));
  end if;

  v_recipient := case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end;

  select count(*), coalesce(array_agg(distinct o.entitlement_kind), '{}')
    into v_count, v_kinds
    from public.legacy_reward_options(p_entitlement_id) o;

  -- Rules at the same recipient and store that were NOT offered, with the
  -- reason each was passed over. This is the setup path: it names the rule that
  -- has to be created or corrected.
  select coalesce(jsonb_agg(jsonb_build_object(
           'rule', r.name, 'kind', r.entitlement_kind,
           'qualifying_amount', r.qualifying_amount,
           'applies_to', coalesce(r.applies_to, 'customer'),
           'tier_key', r.tier_key,
           'excluded_because', case
             when not r.is_active or r.deleted_at is not null then 'the rule is inactive'
             when coalesce(r.applies_to, 'customer') <> v_recipient
               then format('it is configured for %s, not %s', coalesce(r.applies_to,'customer'), v_recipient)
             when r.store_id is not null and r.store_id <> e.store_id
               then 'it belongs to a different store'
             when e.reward_tier_key is not null and r.tier_key is distinct from e.reward_tier_key
               then 'it belongs to a different reward tier'
             when e.reward_tier_key is null and r.qualifying_amount <> e.qualifying_amount
               then format('its threshold is S$%s but this entitlement was earned at S$%s',
                           r.qualifying_amount, e.qualifying_amount)
             else 'offered' end)
         order by r.qualifying_amount desc, r.name), '[]'::jsonb)
    into v_near
    from public.therapy_package_rules r
   where r.deleted_at is null;

  if v_count = 0 then
    v_reasons := v_reasons || to_jsonb(format(
      'No reward rule matches this entitlement. It was earned at S$%s as a %s reward%s.',
      e.qualifying_amount, v_recipient,
      case when e.reward_tier_key is null then ', and no reward tier has been mapped to it'
           else format(' in tier %s', e.reward_tier_key) end));
  elsif array_length(v_kinds, 1) = 1 then
    v_reasons := v_reasons || to_jsonb(format(
      'Only one kind of reward (%s) is configured for %s at this tier, so there is nothing to choose between.',
      v_kinds[1], v_recipient));
    if v_recipient = 'affiliate' and not ('unlimited' = any (v_kinds)) then
      v_reasons := v_reasons || to_jsonb(
        'To let affiliates choose unlimited therapy, add an affiliate rule of kind ''unlimited'' with the same tier key as the affiliate voucher rule.'::text);
    end if;
  end if;

  return jsonb_build_object(
    'found', true,
    'entitlement_no', e.entitlement_no,
    'status', e.status,
    'recipient', v_recipient,
    'qualifying_amount', e.qualifying_amount,
    'reward_tier_key', e.reward_tier_key,
    'current_kind', coalesce(e.entitlement_kind, 'unlimited'),
    'option_count', v_count,
    'option_kinds', to_jsonb(v_kinds),
    'has_choice', v_count > 1,
    'reasons', v_reasons,
    'rules_considered', v_near);
end $function$;

-- ---------------------------------------------------------------------
-- 4. Historical entitlements whose tier no longer exists.
--
-- A preview, not a repair. Attaching a S$794 entitlement to a S$994 rule
-- changes what the customer was promised, so a person has to look at each one
-- and say yes. Candidates are ranked by how close the reward is to what the
-- entitlement already carries — same kind and same duration or quantity first.
-- ---------------------------------------------------------------------
create or replace function public.therapy_reward_mapping_preview()
returns table (entitlement_id uuid, entitlement_no text, customer_id uuid,
               customer_name text, recipient text, qualifying_amount numeric,
               current_kind text, current_months integer, current_qty integer,
               activation_deadline date, option_count integer,
               mapped_tier text, candidates jsonb)
language sql stable security definer set search_path to 'public' as $function$
  select e.id, e.entitlement_no, e.customer_id, c.full_name,
         case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end,
         e.qualifying_amount, coalesce(e.entitlement_kind, 'unlimited'),
         e.duration_months, e.voucher_qty, e.activation_deadline,
         (select count(*)::integer from public.legacy_reward_options(e.id)),
         e.reward_tier_key,
         coalesce((
           select jsonb_agg(x order by x->>'closeness', x->>'tier_key')
             from (
               select jsonb_build_object(
                        'tier_key', r.tier_key,
                        'qualifying_amount', r.qualifying_amount,
                        'kinds', array_agg(distinct r.entitlement_kind),
                        'names', array_agg(distinct r.name),
                        'alternatives', count(*),
                        -- 0 = the tier offers exactly what this entitlement
                        -- already carries; higher means a bigger leap.
                        'closeness', min(case
                           when r.entitlement_kind = coalesce(e.entitlement_kind,'unlimited')
                            and coalesce(r.duration_months, -1) = coalesce(e.duration_months, -1)
                            and coalesce(r.voucher_qty, -1) = coalesce(e.voucher_qty, -1) then 0
                           when r.entitlement_kind = coalesce(e.entitlement_kind,'unlimited') then 1
                           else 2 end),
                        'threshold_differs', r.qualifying_amount <> e.qualifying_amount) as x
                 from public.therapy_package_rules r
                where r.is_active and r.deleted_at is null
                  and coalesce(r.applies_to,'customer') =
                      (case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end)
                  and (r.store_id = e.store_id or r.store_id is null)
                group by r.tier_key, r.qualifying_amount
             ) s), '[]'::jsonb)
    from public.therapy_entitlements e
    left join public.customers c on c.id = e.customer_id
   where e.status = 'pending_activation'          -- unclaimed only
     and public.is_manager_or_above()
   order by e.qualifying_amount, e.entitlement_no
$function$;

-- Attach one entitlement to one tier, on the record, with a reason. Claimed
-- units are refused outright: a completed claim is history.
create or replace function public.therapy_map_entitlement_tier(
  p_entitlement_id uuid, p_tier_key text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare e public.therapy_entitlements%rowtype; v_n integer; v_recipient text;
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can map a reward tier'; end if;
  if coalesce(nullif(btrim(p_reason), ''), '') = '' then
    raise exception 'Mapping a historical entitlement to a reward tier requires a reason'; end if;

  select * into e from public.therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Entitlement not found'; end if;
  if e.status <> 'pending_activation' then
    raise exception 'This entitlement is already % and cannot be remapped', e.status; end if;

  v_recipient := case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end;
  select count(*) into v_n from public.therapy_package_rules r
   where r.tier_key = p_tier_key and r.is_active and r.deleted_at is null
     and coalesce(r.applies_to,'customer') = v_recipient
     and (r.store_id = e.store_id or r.store_id is null);
  if v_n = 0 then
    raise exception 'No active % rule exists in tier %', v_recipient, p_tier_key; end if;

  update public.therapy_entitlements
     set reward_tier_key = p_tier_key, reward_tier_mapped_by = auth.uid(),
         reward_tier_mapped_at = now(), reward_tier_mapping_reason = btrim(p_reason)
   where id = p_entitlement_id;

  -- The qualifying amount is NOT touched. What the customer spent is a fact.
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values ('therapy_entitlements', p_entitlement_id, 'reward_tier_mapped',
          jsonb_build_object('reward_tier_key', e.reward_tier_key,
                             'qualifying_amount', e.qualifying_amount),
          jsonb_build_object('reward_tier_key', p_tier_key, 'reason', btrim(p_reason),
                             'qualifying_amount_unchanged', e.qualifying_amount),
          auth.uid());

  return jsonb_build_object('success', true, 'entitlement_no', e.entitlement_no,
    'tier_key', p_tier_key, 'options',
    (select count(*) from public.legacy_reward_options(p_entitlement_id)));
end $function$;

-- ---------------------------------------------------------------------
-- 5. Claiming: the affiliate restriction becomes rule-driven, and an
--    unlimited reward now gets its closure extension like any other.
-- ---------------------------------------------------------------------
-- Migration 74's 4-argument form must go: with two more optional parameters,
-- an existing 4-argument call would match both and PostgreSQL would refuse it
-- as ambiguous. Same reason 74 itself dropped the 2-argument form.
drop function if exists public.claim_legacy_therapy(uuid, date, uuid, jsonb);

create or replace function public.claim_legacy_therapy(
  p_entitlement_id uuid, p_activation_date date default null,
  p_rule_id uuid default null, p_voucher_selections jsonb default null,
  p_holiday_country text default null, p_holiday_region text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  e public.therapy_entitlements%rowtype;
  r public.therapy_package_rules;
  v_today date := public.sg_today();
  v_act date; v_exp date; v_status text;
  -- Scalars with defaults rather than a record. PL/pgSQL evaluates every arm of
  -- a CASE in the UPDATE below, so a record left unassigned on the voucher path
  -- fails with "record is not assigned yet" even though that arm is never taken.
  v_calc record; v_base_expiry date; v_added integer := 0;
  v_kind text; v_months integer; v_qty integer; v_name text;
  v_sel jsonb; v_sum integer := 0; v_vid uuid; v_q integer; v_stock integer;
  v_recipient text; v_issued jsonb := '[]'::jsonb;
begin
  -- for update: two clicks, two tabs, or a retried request must not both claim.
  select * into e from public.therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Legacy entitlement not found'; end if;
  if e.store_id is not null and not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;
  if e.status <> 'pending_activation' then
    raise exception 'Only an unclaimed entitlement can be claimed (currently %)', e.status; end if;

  v_recipient := case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end;
  v_act := coalesce(p_activation_date, v_today);
  if v_act < v_today then raise exception 'The claim date cannot be in the past'; end if;
  if e.activation_deadline is not null and v_act > e.activation_deadline then
    raise exception 'The claim deadline (%) has passed', e.activation_deadline; end if;

  v_kind := coalesce(e.entitlement_kind,'unlimited');
  v_months := e.duration_months; v_qty := e.voucher_qty; v_name := e.package_name;

  if p_rule_id is not null then
    select * into r from public.therapy_package_rules where id = p_rule_id;
    if not found then raise exception 'That reward option no longer exists'; end if;

    -- The rule must be one of the alternatives for THIS unit. Checked against
    -- the same function the dialog reads, so the two cannot disagree.
    if not exists (select 1 from public.legacy_reward_options(p_entitlement_id) o
                    where o.rule_id = p_rule_id) then
      raise exception 'That reward is not an alternative for this entitlement'; end if;

    v_kind := r.entitlement_kind; v_months := r.duration_months;
    v_qty := r.voucher_qty; v_name := r.name;
  end if;

  if v_kind = 'unlimited' then
    -- Closure extension applies to a Legacy reward exactly as it does to a
    -- purchase. The country is frozen onto the entitlement here.
    select * into v_calc
      from public.therapy_adjusted_expiry(v_act, v_months, p_holiday_country, p_holiday_region, 'legacy');
    v_base_expiry := v_calc.base_expiry;
    v_added := coalesce(v_calc.added_days, 0);
    v_exp := coalesce(v_calc.adjusted_expiry, public.therapy_expiry(v_act, v_months));
    v_status := case when v_act > v_today then 'scheduled' else 'active' end;
  else
    if p_voucher_selections is null or jsonb_array_length(p_voucher_selections) = 0 then
      raise exception 'Choose % voucher(s) to claim this reward', coalesce(v_qty,0); end if;
    for v_sel in select * from jsonb_array_elements(p_voucher_selections) loop
      v_sum := v_sum + coalesce((v_sel->>'quantity')::integer, 0);
    end loop;
    if v_sum <> coalesce(v_qty,0) then
      raise exception 'Select exactly % voucher(s) — % chosen', coalesce(v_qty,0), v_sum; end if;

    for v_sel in select * from jsonb_array_elements(p_voucher_selections) loop
      v_vid := (v_sel->>'voucher_id')::uuid;
      v_q := coalesce((v_sel->>'quantity')::integer, 0);
      if v_q <= 0 then continue; end if;
      if not exists (select 1 from public.vouchers v
                      where v.id = v_vid and v.is_active = true and v.deleted_at is null
                        and coalesce(v.reward_eligible,true)) then
        raise exception 'That voucher cannot be given as a reward'; end if;

      if exists (select 1 from public.vouchers where id = v_vid and qty_type <> 'unlimited') then
        select current_qty into v_stock from public.voucher_store_stock
         where voucher_id = v_vid and store_id = e.store_id for update;
        if coalesce(v_stock,0) < v_q then
          raise exception 'Not enough stock of "%" at this store (% available)',
            (select name from public.vouchers where id = v_vid), coalesce(v_stock,0); end if;
        update public.voucher_store_stock set current_qty = current_qty - v_q, updated_at = now()
         where voucher_id = v_vid and store_id = e.store_id;
      end if;

      -- The beneficiary is the entitlement's customer, which for an affiliate
      -- reward is the affiliate's own customer record — the existing linkage.
      insert into public.customer_reward_vouchers
        (customer_id, voucher_id, entitlement_id, store_id, quantity, issued_by, notes)
      values (e.customer_id, v_vid, e.id, e.store_id, v_q, auth.uid(),
              'Legacy reward — never expires, not transferable');

      v_issued := v_issued || jsonb_build_object(
        'voucher_id', v_vid, 'quantity', v_q,
        'name', (select name from public.vouchers where id = v_vid));
    end loop;
    -- Claiming vouchers does not start a therapy period. There is no expiry
    -- date because nothing is running.
    v_exp := null; v_status := 'active';
  end if;

  update public.therapy_entitlements
     set status = v_status, activation_date = v_act, expiry_date = v_exp,
         entitlement_kind = v_kind, duration_months = v_months,
         voucher_qty = v_qty, package_name = v_name,
         rule_id = coalesce(p_rule_id, rule_id),
         holiday_country = case when v_kind = 'unlimited' then p_holiday_country else holiday_country end,
         holiday_region  = case when v_kind = 'unlimited' then p_holiday_region  else holiday_region end,
         holiday_country_source = case when v_kind = 'unlimited' and p_holiday_country is not null
                                       then 'manual' else holiday_country_source end,
         base_expiry_date = case when v_kind = 'unlimited' then v_base_expiry else base_expiry_date end,
         closure_days_added = case when v_kind = 'unlimited' then v_added else closure_days_added end,
         expiry_calculated_at = case when v_kind = 'unlimited' then now() else expiry_calculated_at end,
         claimed_by = auth.uid(), claimed_at = now()
   where id = p_entitlement_id;

  perform public.write_audit_ex('therapy_entitlements', p_entitlement_id, 'legacy_therapy_claimed',
    jsonb_build_object('status', e.status),
    jsonb_build_object('status', v_status, 'activation_date', v_act, 'expiry_date', v_exp,
                       'kind', v_kind, 'voucher_qty', v_qty, 'earner', e.earner_kind,
                       'rule_id', p_rule_id, 'holiday_country', p_holiday_country,
                       'base_expiry', v_base_expiry, 'closure_days_added', v_added),
    'therapy', 'legacy claim', e.store_id);

  return jsonb_build_object('success', true, 'status', v_status, 'kind', v_kind,
    'activation_date', v_act, 'expiry_date', v_exp,
    'base_expiry', v_base_expiry, 'closure_days_added', v_added,
    'entitlement_no', e.entitlement_no,
    'voucher_qty', case when v_kind = 'voucher' then v_qty else null end,
    -- What was actually written, so the confirmation can say "issued", not
    -- "will issue". By the time this returns, the rows exist.
    'issued_vouchers', case when v_kind = 'voucher' then v_issued else '[]'::jsonb end);
end $function$;

grant execute on function public.legacy_reward_options(uuid) to authenticated;
grant execute on function public.legacy_reward_options_diagnostic(uuid) to authenticated;
grant execute on function public.therapy_reward_mapping_preview() to authenticated;
grant execute on function public.therapy_map_entitlement_tier(uuid,text,text) to authenticated;
grant execute on function public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text) to authenticated;
