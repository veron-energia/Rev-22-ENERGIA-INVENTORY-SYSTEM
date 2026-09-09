-- =====================================================================
-- ENERGIA — AN EARNED ENTITLEMENT STAYS CLAIMABLE WHEN THE RULES CHANGE
--
-- A customer who qualified at S$794 earned that entitlement. Raising the
-- threshold to S$994 changes who qualifies from then on; it does not take back
-- what was already granted. Until now a S$794 entitlement matched no current
-- rule, so the claim dialog had nothing to offer and the reward could not be
-- taken at all.
--
-- The entitlement itself already records what was earned — entitlement_kind,
-- duration_months, voucher_qty, package_name, all snapshotted at creation — and
-- claim_legacy_therapy has always been able to claim from that snapshot with no
-- rule at all. What was missing was the option list ever saying so.
--
-- Options are now resolved in this order, most authoritative first:
--
--   1. An explicit tier mapping, if an Owner or Manager made one.
--   2. The tier of the rule this entitlement was ACTUALLY created from
--      (therapy_entitlements.rule_id). This is a record, not a guess: it is the
--      rule that granted the entitlement, so its siblings are the alternatives
--      that were genuinely offered at the time — including ones since retired,
--      which are returned flagged rather than hidden.
--   3. Rules at the same qualifying amount, as before.
--   4. The entitlement's own snapshot, ALWAYS, as a final option.
--
-- Step 4 is what guarantees a claim is never blocked. Step 2 is what usually
-- restores the choice as well: raising a threshold by editing the existing rules
-- leaves rule_id pointing at them, so the alternatives come back on their own
-- with nothing to configure.
--
-- What this deliberately does NOT do: attach a historical entitlement to some
-- other tier because the amounts look close. A rule at a different threshold is
-- a different promise, and that still needs a person
-- (therapy_map_entitlement_tier) who gives a reason.
--
-- No qualifying amount is rewritten, no unit is granted, no claimed entitlement
-- is reopened, and no deadline moves.
--
-- Additive, idempotent. Run AFTER 221 and 225.
-- =====================================================================

set check_function_bodies = off;

-- The return columns gain the two fields the dialog needs to label an option, so
-- the old shape has to go: PostgreSQL will not change a function's output
-- columns in place.
drop function if exists public.legacy_reward_options(uuid);

create or replace function public.legacy_reward_options(p_entitlement_id uuid)
returns table (rule_id uuid, name text, entitlement_kind text,
               duration_months integer, voucher_qty integer,
               tier_key text, applies_to text, is_current_choice boolean,
               is_entitlement_snapshot boolean, availability text)
language plpgsql stable security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare
  e public.therapy_entitlements%rowtype;
  v_recipient text;
  v_tier text;
  v_snapshot_kind text;
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
  if not found then return; end if;

  v_recipient := case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end;
  v_snapshot_kind := coalesce(e.entitlement_kind, 'unlimited');

  -- 1 and 2: an explicit mapping, else the tier of the rule that granted this.
  v_tier := coalesce(
    e.reward_tier_key,
    (select r.tier_key from public.therapy_package_rules r where r.id = e.rule_id));

  return query
  with configured as (
    select r.id, r.name, r.entitlement_kind, r.duration_months, r.voucher_qty,
           r.tier_key, coalesce(r.applies_to, 'customer') as applies_to,
           -- A rule from the tier this was earned under is offered even if it has
           -- since been retired: it is what the customer was promised. Flagged,
           -- so the dialog can say so rather than pretending it is current.
           case when r.is_active and r.deleted_at is null then 'available'
                else 'retired' end as availability
      from public.therapy_package_rules r
     where coalesce(r.applies_to, 'customer') = v_recipient
       and (r.store_id = e.store_id or r.store_id is null)
       and (
         -- the tier this entitlement belongs to, retired rules included
         (v_tier is not null and r.tier_key = v_tier)
         -- or, with no tier to go on, the historical amount match
         or (v_tier is null and r.is_active and r.deleted_at is null
             and r.qualifying_amount = e.qualifying_amount)
       )
  ),
  snapshot as (
    -- What the entitlement itself says it is. Always claimable, with no rule,
    -- which is exactly what claim_legacy_therapy does when p_rule_id is null.
    select null::uuid as id,
           coalesce(e.package_name,
                    case when v_snapshot_kind = 'voucher'
                         then coalesce(e.voucher_qty, 0) || ' voucher(s)'
                         else coalesce(e.duration_months, 0) || ' month(s) unlimited therapy' end) as name,
           v_snapshot_kind as entitlement_kind,
           e.duration_months, e.voucher_qty,
           v_tier as tier_key, v_recipient as applies_to,
           'as_earned' as availability
     where not exists (
       -- Suppress it when a configured rule already offers the identical reward,
       -- so the same thing is not listed twice.
       select 1 from configured c
        where c.entitlement_kind = v_snapshot_kind
          and coalesce(c.duration_months, -1) = coalesce(e.duration_months, -1)
          and coalesce(c.voucher_qty, -1) = coalesce(e.voucher_qty, -1))
  )
  select u.id, u.name, u.entitlement_kind, u.duration_months, u.voucher_qty,
         u.tier_key, u.applies_to,
         (u.entitlement_kind = v_snapshot_kind
            and (e.rule_id is null or u.id is not distinct from e.rule_id
                 or u.id is null)) as is_current_choice,
         u.id is null as is_entitlement_snapshot,
         u.availability
    from (select * from configured union all select * from snapshot) u
   order by (u.availability = 'available') desc, u.entitlement_kind, u.name;
end $function$;

-- ---------------------------------------------------------------------
-- The diagnostic follows the same order, and no longer says "nothing matches"
-- when the entitlement's own reward is always available.
-- ---------------------------------------------------------------------
create or replace function public.legacy_reward_options_diagnostic(p_entitlement_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  e public.therapy_entitlements%rowtype;
  v_recipient text; v_count integer; v_configured integer;
  v_kinds text[]; v_configured_kinds text[];
  v_tier text; v_source text; v_reasons jsonb := '[]'::jsonb; v_rules jsonb;
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
  if not found then
    return jsonb_build_object('found', false,
      'reasons', jsonb_build_array('That entitlement no longer exists.'));
  end if;

  v_recipient := case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end;
  v_tier := coalesce(e.reward_tier_key,
                     (select r.tier_key from public.therapy_package_rules r where r.id = e.rule_id));
  v_source := case
    when e.reward_tier_key is not null then 'a tier an Owner or Manager mapped'
    when v_tier is not null then 'the tier this entitlement was created from'
    else 'rules at the same qualifying amount' end;

  select count(*), count(*) filter (where not o.is_entitlement_snapshot),
         coalesce(array_agg(distinct o.entitlement_kind), '{}'),
         -- Kinds from CONFIGURED rules only. The snapshot is always claimable,
         -- but it is not evidence that a rule exists — and the advice below is
         -- about a rule that has to be created.
         coalesce(array_agg(distinct o.entitlement_kind)
                  filter (where not o.is_entitlement_snapshot), '{}')
    into v_count, v_configured, v_kinds, v_configured_kinds
    from public.legacy_reward_options(p_entitlement_id) o;

  if v_configured = 0 then
    v_reasons := v_reasons || to_jsonb(format(
      'No configured rule matches this entitlement — it was earned at S$%s as a %s reward. '
      || 'It can still be claimed as what it was granted: %s.',
      e.qualifying_amount, v_recipient, coalesce(e.package_name, coalesce(e.entitlement_kind,'unlimited'))));
  end if;

  if array_length(v_kinds, 1) = 1 then
    v_reasons := v_reasons || to_jsonb(format(
      'Only one kind of reward (%s) is available at this tier, so there is nothing to choose between.',
      v_kinds[1]));
  end if;

  if v_recipient = 'affiliate' and not ('unlimited' = any (v_configured_kinds)) then
      v_reasons := v_reasons || to_jsonb(
        'To let affiliates choose unlimited therapy, add an affiliate rule of kind ''unlimited'' with the same tier key as the affiliate voucher rule.'::text);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rule', r.name, 'kind', r.entitlement_kind,
           'qualifying_amount', r.qualifying_amount,
           'applies_to', coalesce(r.applies_to, 'customer'),
           'tier_key', r.tier_key,
           'active', r.is_active and r.deleted_at is null)
         order by r.qualifying_amount desc, r.name), '[]'::jsonb)
    into v_rules
    from public.therapy_package_rules r
   where r.deleted_at is null;

  return jsonb_build_object(
    'found', true,
    'entitlement_no', e.entitlement_no,
    'status', e.status,
    'recipient', v_recipient,
    'qualifying_amount', e.qualifying_amount,
    'reward_tier_key', v_tier,
    'options_resolved_from', v_source,
    'current_kind', coalesce(e.entitlement_kind, 'unlimited'),
    'option_count', v_count,
    'configured_option_count', v_configured,
    'option_kinds', to_jsonb(v_kinds),
    'configured_option_kinds', to_jsonb(v_configured_kinds),
    'has_choice', v_count > 1,
    'claimable', v_count > 0,          -- always true: the snapshot is an option
    'reasons', v_reasons,
    'rules_considered', v_rules);
end $function$;

-- ---------------------------------------------------------------------
-- The mapping preview now lists what it is actually for: unclaimed entitlements
-- with no CHOICE. They are all claimable; some have only one reward available.
-- ---------------------------------------------------------------------
drop function if exists public.therapy_reward_mapping_preview();

create or replace function public.therapy_reward_mapping_preview()
returns table (entitlement_id uuid, entitlement_no text, customer_id uuid,
               customer_name text, recipient text, qualifying_amount numeric,
               current_kind text, current_months integer, current_qty integer,
               activation_deadline date, option_count integer,
               configured_option_count integer, claimable boolean,
               mapped_tier text, candidates jsonb)
language sql stable security definer set search_path to 'public' as $function$
  select e.id, e.entitlement_no, e.customer_id, c.full_name,
         case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end,
         e.qualifying_amount, coalesce(e.entitlement_kind, 'unlimited'),
         e.duration_months, e.voucher_qty, e.activation_deadline,
         (select count(*)::integer from public.legacy_reward_options(e.id)),
         (select count(*)::integer from public.legacy_reward_options(e.id) o
           where not o.is_entitlement_snapshot),
         -- Always true now. Returned anyway so the page states it rather than
         -- leaving a reader to infer it from a count.
         (select count(*) from public.legacy_reward_options(e.id)) > 0,
         coalesce(e.reward_tier_key,
                  (select r.tier_key from public.therapy_package_rules r where r.id = e.rule_id)),
         coalesce((
           select jsonb_agg(x order by x->>'closeness', x->>'tier_key')
             from (
               select jsonb_build_object(
                        'tier_key', r.tier_key,
                        'qualifying_amount', r.qualifying_amount,
                        'kinds', array_agg(distinct r.entitlement_kind),
                        'names', array_agg(distinct r.name),
                        'alternatives', count(*),
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
   where e.status = 'pending_activation'
     and public.is_manager_or_above()
   order by e.qualifying_amount, e.entitlement_no
$function$;

grant execute on function public.legacy_reward_options(uuid) to authenticated;
grant execute on function public.legacy_reward_options_diagnostic(uuid) to authenticated;
grant execute on function public.therapy_reward_mapping_preview() to authenticated;
