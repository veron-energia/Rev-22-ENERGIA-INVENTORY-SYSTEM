-- 359_packages_cover_services_and_claim_in_one_step.sql
--
-- WHAT THE OWNER ASKED FOR (25 Sep 2026)
--
--   * An unlimited-therapy package (Therapy -> Packages) can be linked to one or
--     more Therapy Services, as a voucher already can. A package linked to
--     services A and B lets the customer take A or B as often as they like
--     while the package runs. Each service's own limit still applies (Power
--     Recharge: at most once every 5 hours).
--   * Nothing records a visit yet, so the link is shown, not enforced: on the
--     package, the Purchased tab, the Claim window and the customer's page
--     ("Unlimited A and B until 25 Dec 2026").
--   * Each package decides what it grants: unlimited therapy, vouchers, or the
--     customer's choice of unlimited therapy OR a number of vouchers from a
--     list set on the package (session vouchers only, never discount vouchers).
--   * Purchased works like Legacy "Claim": one Claim window. Take unlimited
--     therapy with a start date, or take vouchers. Vouchers may be collected a
--     few at a time up to the number; an Owner or Manager can switch the choice
--     while nothing has been used (unchanged from 314).
--   * A unit taken as vouchers, once any voucher has been collected, is refunded
--     like therapy that has started: only through the invoice's authorized
--     termination (Owner or Manager, amount and reason). Vouchers not yet
--     collected are withdrawn.
--   * Packages sold inside a promotion are claimed later on Purchased (as
--     today). The 12 units already sold keep the terms they were sold with.
--
-- MOST OF THIS ALREADY EXISTED (314). WHAT THIS ADDS
--
--   1. therapy_services_coverage: the covered services with their limits.
--   2. therapy_unit_consumed: "has this unit been used" — started or finished
--      therapy, or vouchers collected. The refund rule keys on it.
--   3. save_therapy_package: one call saves a package of any kind with its
--      SKU, voucher list and services. Services may now be linked to a plain
--      unlimited package (before, only to a choice package). A vouchers-only
--      package takes its services from its voucher. Also fixes a SKU typed on a
--      NEW unlimited or voucher package being dropped.
--   4. claim_purchased_therapy: the one-step Claim. Chooses (if not chosen yet)
--      and then starts the therapy or hands over vouchers, in one transaction.
--      An overlap still asks for confirmation, and then nothing is recorded.
--      A scheduled unit can be claimed again to start it now or move its start
--      (the Activate button this replaces could do both); its own period does
--      not count as an overlap. Two units of the same package never share days,
--      also for a future start (the no-overlap constraint only sees a started one).
--   5. purchased_therapy_unit_state: services come with their limits; holiday
--      country is returned for the Claim window.
--   6. refund_invoice_recorded / invoice_action_plan / refund_purchased_therapy:
--      the refund rule above. The guided Refund / Cancel flow already lets an
--      Owner or Manager terminate started therapy with an amount and a reason;
--      it now asks for the same when vouchers have been collected.
--   7. therapy_customer_detail / therapy_customer_summary / customer_overview:
--      the customer's page shows what each unit covers; a unit taken as
--      vouchers is no longer listed as unlimited therapy (the holdings list
--      still shows it as unclaimed while vouchers are owed); an allowance with
--      nothing left to collect, or past its deadline, is no longer unclaimed.
--
-- NOT CHANGED
--
--   * Units already sold: they keep their frozen terms (no services, unlimited
--     only). create_purchased_therapy_for_invoice already copies a package's
--     services onto every unit it creates, whatever the package kind.
--   * Who may do what: choosing and starting therapy is ordinary store work;
--     switching is Owner or Manager; the server rules of 314 are unchanged.
--   * The till's Unlimited / Vouchers / Choose later buttons on a package sold
--     as its own line.
--   * The 245 booking read models (therapy_customer_entitlements and friends)
--     still say "any service": nothing calls them, and nothing books a visit.
--   * Promotion-line refunds still do not close their therapy units (an older
--     gap: INV-2026-0160 / UTP-0000006).
--   * Buying the same package again while a unit of it is current is still
--     refused, including a unit taken as vouchers. Whether that should change
--     is the owner's decision (and a vouchers-only unit's open-ended period
--     would also need the no-overlap constraint changed).
--   * Reschedule on the Purchased tab still moves only the scheduled date, not
--     a start already fixed by Claim; Claim is the way to move that.
--
-- SAFETY
--
-- Needs 314. Every patched function is guarded by the md5 of the production
-- version it was tested against (25 Sep 2026) and by an anchor that must occur
-- exactly once; a function already carrying "359:" is left alone.

-- Plain SQL: applies through the Supabase migration tool or the SQL editor as one
-- transaction. From psql, run with -v ON_ERROR_STOP=1.
set lock_timeout = '5s';

do $mig$
begin
  if to_regprocedure('public.choose_therapy_benefit(uuid,text,uuid,text)') is null
     or to_regprocedure('public.upsert_therapy_package_choice(uuid,text,text,text,boolean,integer,integer,uuid[],uuid[])') is null
     or to_regclass('public.therapy_package_services') is null then
    raise exception '359: apply 314 first'; end if;
end $mig$;

-- ── 1. the services a unit covers, with their own limits ────────────────────
create or replace function public.therapy_services_coverage(p_service_ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  -- 359: "limit" is null when the service has none. An archived service stays
  -- listed: a unit sold while it was offered still covers it.
  select coalesce(jsonb_agg(jsonb_build_object(
           'service_id', s.id,
           'name', s.name,
           'limit', case when s.frequency_kind = 'unrestricted' then null
                         else public.therapy_frequency_description(
                                s.frequency_kind, s.frequency_max_per_period, s.frequency_interval_hours) end,
           'archived', s.deleted_at is not null)
         order by s.name), '[]'::jsonb)
    from public.therapy_services s
   where s.id = any(coalesce(p_service_ids, '{}'::uuid[]))
$function$;

-- ── 2. has this unit been used? ─────────────────────────────────────────────
create or replace function public.therapy_unit_consumed(p_purchased_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  -- 359: therapy that started or ran out, or vouchers already collected.
  -- 'expired' counts as before: an unclaimed unit past its deadline cannot be
  -- refunded as if it were fresh either.
  select exists (
    select 1 from public.purchased_therapy_entitlements e
     where e.id = p_purchased_id
       and (e.status in ('active','expired')
            or (e.benefit_choice = 'voucher'
                and e.status not in ('cancelled','refunded')
                and e.voucher_entitlement_id is not null
                and public.entitlement_claimed_qty(e.voucher_entitlement_id) > 0)))
$function$;

-- ── 3. save a package of any kind ───────────────────────────────────────────
create or replace function public.save_therapy_package(
  p_id uuid,
  p_name text,
  p_sku text,
  p_description text,
  p_is_active boolean,
  p_kind text,
  p_duration_months integer,
  p_voucher_qty integer,
  p_voucher_id uuid,
  p_voucher_ids uuid[],
  p_service_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_id uuid; v_kind text := coalesce(nullif(trim(coalesce(p_kind,'')),''), 'unlimited');
        v_services uuid[]; v_vouchers uuid[]; v_before uuid[];
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage therapy packages'; end if;
  if v_kind not in ('unlimited','voucher','choice') then
    raise exception 'Choose what the package grants: unlimited therapy, vouchers, or the customer''s choice of either'; end if;

  select array_agg(distinct s) into v_services
    from unnest(coalesce(p_service_ids, '{}'::uuid[])) s where s is not null;
  select array_agg(distinct v) into v_vouchers
    from unnest(coalesce(p_voucher_ids, '{}'::uuid[])) v where v is not null;

  if v_kind = 'voucher' and v_services is not null then
    raise exception 'A vouchers-only package covers what its voucher covers. Set that on Therapy Services -> What a voucher gives, and leave the services here empty.'; end if;

  -- A service newly linked must be one still offered; one already linked may
  -- stay after it is archived, so saving an old package does not fail.
  if exists (select 1 from unnest(coalesce(v_services, '{}'::uuid[])) s
              where not exists (select 1 from public.therapy_services x
                                 where x.id = s and x.deleted_at is null)
                and not exists (select 1 from public.therapy_package_services ps
                                 where ps.package_id = p_id and ps.service_id = s)) then
    raise exception 'One of the chosen therapy services is archived or no longer exists'; end if;

  if v_kind = 'choice' then
    -- The customer picks sessions, so only session vouchers that can be given
    -- as a reward: a discount voucher is not a therapy, and claim_entitlement_vouchers
    -- refuses a voucher that is not reward-eligible.
    if exists (select 1 from unnest(coalesce(v_vouchers, '{}'::uuid[])) v
                where not exists (select 1 from public.vouchers x
                                   where x.id = v and x.voucher_kind = 'normal'
                                     and coalesce(x.reward_eligible, true)
                                     and x.is_active and x.deleted_at is null)) then
      raise exception 'The customer can choose only from active session vouchers that can be given as a reward, not discount vouchers'; end if;
    begin
      v_id := public.upsert_therapy_package_choice(p_id, p_name, p_sku, p_description, p_is_active,
                p_duration_months, p_voucher_qty, v_vouchers, v_services);
    exception when unique_violation then
      -- worded as set_catalogue_sku words it for the other kinds
      raise exception 'SKU "%" is already used by another item', nullif(trim(coalesce(p_sku,'')),'');
    end;
    return v_id;
  end if;

  v_id := public.upsert_unlimited_therapy_package(p_id, p_name, p_duration_months, p_description,
            p_is_active, v_kind, p_voucher_qty, p_voucher_id);
  perform public.set_catalogue_sku('therapy', v_id, p_sku);

  -- Lists belong to the kind: a choice package turned into another kind stops
  -- offering its vouchers, and a vouchers-only package holds no services.
  delete from public.therapy_package_vouchers where package_id = v_id;
  select array_agg(service_id order by service_id) into v_before
    from public.therapy_package_services where package_id = v_id;
  delete from public.therapy_package_services where package_id = v_id;
  if v_kind = 'unlimited' and v_services is not null then
    insert into public.therapy_package_services(package_id, service_id)
      select v_id, unnest(v_services) on conflict do nothing;
  end if;

  if v_before is distinct from (select array_agg(s order by s) from unnest(v_services) s) then
    perform public.write_audit('unlimited_therapy_packages', v_id, 'therapy_package_services_set',
      jsonb_build_object('services', to_jsonb(v_before)),
      jsonb_build_object('services', to_jsonb(v_services), 'kind', v_kind));
  end if;
  return v_id;
end $function$;

-- ── 4. Claim, in one step ───────────────────────────────────────────────────
create or replace function public.claim_purchased_therapy(
  p_purchased_id uuid,
  p_choice text,
  p_activation_date date default null,
  p_holiday_country text default null,
  p_holiday_region text default null,
  p_allow_overlap boolean default false,
  p_voucher_selections jsonb default null,
  p_request_id uuid default null,
  p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare e public.purchased_therapy_entitlements%rowtype;
        v_chose boolean := false; v_act jsonb; v_claim jsonb; v_ent uuid;
        v_label text;
begin
  if p_choice is null or p_choice not in ('unlimited','voucher') then
    raise exception 'Choose either unlimited therapy or vouchers'; end if;

  -- The unit first, so two tills cannot both claim it.
  select * into e from public.purchased_therapy_entitlements where id = p_purchased_id for update;
  if not found then raise exception 'Purchased package not found'; end if;
  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
  if e.status in ('cancelled','refunded') then
    raise exception 'This purchase was %; nothing can be claimed against it', e.status; end if;
  if e.benefit_choice is not null and e.benefit_choice <> p_choice then
    v_label := case e.benefit_choice when 'voucher' then 'vouchers' else 'unlimited therapy' end;
    raise exception 'This purchase was already taken as %. An Owner or Manager can switch it while nothing has been used.', v_label; end if;

  if p_choice = 'unlimited' then
    if e.status in ('active','expired') then
      raise exception 'Unlimited therapy on this purchase has already %',
        case e.status when 'active' then 'started' else 'ended' end; end if;

    -- Choosing and starting are one act. If the start date overlaps a period
    -- the customer already has, activate_purchased_therapy answers with a
    -- question instead of an error; everything done here is then undone, so a
    -- confirmation starts from the same place.
    begin
      if p_request_id is not null then
        begin
          insert into public.therapy_choice_requests(request_id, purchased_entitlement_id, action, requested_by)
          values (p_request_id, p_purchased_id, 'claim', auth.uid());
        exception when unique_violation then
          raise exception 'That claim has already been submitted'; end;
      end if;
      -- A scheduled unit is claimed again to start it now or move its start
      -- (as Activate could). It is started from scratch, so its own period is
      -- neither an overlap nor behind the suggested date.
      if e.status = 'scheduled' then
        update public.purchased_therapy_entitlements
           set status = 'pending_activation', scheduled_date = null,
               activation_date = null, expiry_date = null
         where id = p_purchased_id;
      end if;
      if e.benefit_choice is null then
        perform public.choose_therapy_benefit(p_purchased_id, 'unlimited', null, p_note);
        v_chose := true;
      end if;
      v_act := public.activate_purchased_therapy(p_purchased_id, p_activation_date, p_note,
                 p_holiday_country, p_holiday_region, coalesce(p_allow_overlap, false));
      if coalesce((v_act->>'activated')::boolean, true) = false then
        raise exception '359:overlap'; end if;
      -- Two units of the same package never share days, even when an overlap
      -- is confirmed. The no-overlap constraint only sees a unit once it has
      -- started, so a future start is checked here rather than failing on the
      -- day it begins.
      if exists (select 1 from public.purchased_therapy_entitlements p
                  where p.customer_id = e.customer_id and p.package_id = e.package_id and p.id <> e.id
                    and p.activation_date is not null and p.expiry_date is not null and p.status <> 'expired'
                    and daterange(p.activation_date, p.expiry_date, '[]')
                        && daterange((v_act->>'activation_date')::date, (v_act->>'expiry_date')::date, '[]')) then
        raise exception '359:same_package'; end if;
    exception
      when raise_exception then
        if sqlerrm = '359:overlap' then
          return v_act || jsonb_build_object('success', false, 'choice', p_choice, 'chose_now', false);
        end if;
        if sqlerrm <> '359:same_package' then raise; end if;
        raise exception 'This customer already has this same package on some of those days (a current, scheduled or ended purchase of it). Start it on % or later.',
          greatest(public.sg_today(), (select max(p.expiry_date) + 1 from public.purchased_therapy_entitlements p
            where p.customer_id = e.customer_id and p.package_id = e.package_id and p.id <> e.id
              and p.activation_date is not null and p.expiry_date is not null and p.status <> 'expired'));
      when exclusion_violation then
        raise exception 'This customer already has this same package on some of those days (a current, scheduled or ended purchase of it). Start it on % or later.',
          greatest(public.sg_today(), (select max(p.expiry_date) + 1 from public.purchased_therapy_entitlements p
            where p.customer_id = e.customer_id and p.package_id = e.package_id and p.id <> e.id
              and p.activation_date is not null and p.expiry_date is not null and p.status <> 'expired'));
    end;
  else
    if p_request_id is not null then
      begin
        insert into public.therapy_choice_requests(request_id, purchased_entitlement_id, action, requested_by)
        values (p_request_id, p_purchased_id, 'claim', auth.uid());
      exception when unique_violation then
        raise exception 'That claim has already been submitted'; end;
    end if;
    if e.status = 'scheduled' then
      if e.activation_date is not null then
        raise exception 'This purchase is scheduled to start unlimited therapy on %, so it cannot be taken as vouchers.',
          e.activation_date; end if;
      -- Reschedule marked it scheduled without starting anything (no choice
      -- was made); taking vouchers clears that date.
      update public.purchased_therapy_entitlements
         set status = 'pending_activation', scheduled_date = null
       where id = p_purchased_id;
    end if;
    if e.benefit_choice is null then
      perform public.choose_therapy_benefit(p_purchased_id, 'voucher', null, p_note);
      v_chose := true;
    end if;
    select voucher_entitlement_id into v_ent from public.purchased_therapy_entitlements where id = p_purchased_id;
    -- Nothing collected today is allowed: the vouchers are then owed, and can
    -- be collected a few at a time up to the deadline.
    if p_voucher_selections is not null and jsonb_typeof(p_voucher_selections) = 'array'
       and jsonb_array_length(p_voucher_selections) > 0 then
      if v_ent is null then raise exception 'This purchase has no voucher allowance to claim from'; end if;
      v_claim := public.claim_entitlement_vouchers(v_ent, p_voucher_selections, p_note);
    elsif not v_chose then
      raise exception 'Choose at least one voucher to collect';
    end if;
  end if;

  return jsonb_build_object('success', true, 'choice', p_choice, 'chose_now', v_chose,
    'activation', v_act, 'claim', v_claim,
    'state', public.purchased_therapy_unit_state(p_purchased_id));
end $function$;

-- ── 5. unit state: services with limits, holiday country ────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.purchased_therapy_unit_state(uuid)'::regprocedure);
  if position('359:' in d) > 0 then raise notice '359: purchased_therapy_unit_state already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'a59f9a8f393c3bbd3c379bf777b2fca0' then
    raise exception '359: purchased_therapy_unit_state is not the version this was tested against (md5 %)', v_md5; end if;

  a := $a$  select coalesce(jsonb_agg(jsonb_build_object('service_id', s.id, 'name', s.name) order by s.name), '[]'::jsonb)
    into v_svc from public.therapy_services s
   where s.id = any(coalesce(e.eligible_service_ids, '{}'::uuid[]));$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: purchased_therapy_unit_state services anchor found % times', n; end if;
  d := replace(d, a, $r$  -- 359: each covered service with its own limit, which still applies.
  v_svc := public.therapy_services_coverage(e.eligible_service_ids);$r$);

  a := $a$'switch_requires_role', 'owner_or_manager');$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: purchased_therapy_unit_state return anchor found % times', n; end if;
  d := replace(d, a, $r$'switch_requires_role', 'owner_or_manager',
    'holiday_country', e.holiday_country,
    'holiday_region', e.holiday_region);$r$);
  execute d;
end $mig$;

-- ── 6. refunds: collected vouchers count as used ────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure);
  if position('359:' in d) > 0 then raise notice '359: refund_invoice_recorded already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '2dbfc9080abb9510643c1736b55d50bf' then
    raise exception '359: refund_invoice_recorded is not the version this was tested against (md5 %)', v_md5; end if;

  a := $a$if exists(select 1 from public.purchased_therapy_entitlements where invoice_item_id=it.id and status in ('active','expired')) then$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: refund_invoice_recorded check anchor found % times', n; end if;
  d := replace(d, a, $r$-- 359: used = therapy started or ended, or vouchers already collected.
       if exists(select 1 from public.purchased_therapy_entitlements where invoice_item_id=it.id and public.therapy_unit_consumed(id)) then$r$);

  a := $a$where invoice_item_id=it.id and status in ('active','expired') for update loop$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: refund_invoice_recorded loop anchor found % times', n; end if;
  d := replace(d, a, $r$where invoice_item_id=it.id and public.therapy_unit_consumed(id) for update loop$r$);
  execute d;
end $mig$;

-- The guided Refund / Cancel flow asks for the same override, so it has to
-- know a unit is used before the refund engine is reached.
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.invoice_action_plan(uuid,text,jsonb)'::regprocedure);
  if position('359:' in d) > 0 then raise notice '359: invoice_action_plan already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '1613405970622418f9427c37f42e722c' then
    raise exception '359: invoice_action_plan is not the version this was tested against (md5 %)', v_md5; end if;

  a := $a$   if exists(select 1 from public.purchased_therapy_entitlements
              where invoice_item_id=it.id and status in ('active','expired')) then$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: invoice_action_plan check anchor found % times', n; end if;
  d := replace(d, a, $r$   -- 359: used = therapy started or ended, or vouchers already collected.
   if exists(select 1 from public.purchased_therapy_entitlements
              where invoice_item_id=it.id and public.therapy_unit_consumed(id)) then$r$);

  a := $a$'message','This therapy entitlement has been activated. Terminating it keeps its activation and usage history, and no unused-period valuation exists - an Owner or Manager must state the refund amount with a reason.'));$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: invoice_action_plan message anchor found % times', n; end if;
  d := replace(d, a, $r$'message','This therapy has been activated, or vouchers from it have already been collected. Terminating it keeps that history and withdraws any vouchers not yet collected, and no unused-period valuation exists - an Owner or Manager must state the refund amount with a reason.'));$r$);
  execute d;
end $mig$;

do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.refund_purchased_therapy(uuid,text)'::regprocedure);
  if position('359:' in d) > 0 then raise notice '359: refund_purchased_therapy already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'b19cc0e07784f02c27c7fc963f1e659f' then
    raise exception '359: refund_purchased_therapy is not the version this was tested against (md5 %)', v_md5; end if;

  a := $a$  if e.status in ('active','expired') then$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: refund_purchased_therapy anchor found % times', n; end if;
  d := replace(d, a, $r$  -- 359: vouchers already collected count as used, like started therapy.
  if e.benefit_choice = 'voucher' and e.voucher_entitlement_id is not null
     and e.status not in ('active','expired')
     and public.entitlement_claimed_qty(e.voucher_entitlement_id) > 0 then
    raise exception 'Vouchers from this purchase have already been collected, so it cannot be refunded from here. Use the invoice''s Refund / Cancel flow, where an Owner/Manager can authorize the termination and state the amount.';
  end if;
  if e.status in ('active','expired') then$r$);
  execute d;
end $mig$;

-- ── 7. the customer's page ──────────────────────────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.therapy_customer_detail(uuid)'::regprocedure);
  if position('359:' in d) > 0 then raise notice '359: therapy_customer_detail already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '0894639d5d9b13ce09b13e058c4b24ef' then
    raise exception '359: therapy_customer_detail is not the version this was tested against (md5 %)', v_md5; end if;

  -- (a) what each period covers
  a := $a$'holiday_country_source', u.holiday_country_source,$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: therapy_customer_detail covers anchor found % times', n; end if;
  d := replace(d, a, $r$'holiday_country_source', u.holiday_country_source,
          -- 359: the services this period covers, each with its own limit
          'covers', public.therapy_services_coverage(u.eligible_service_ids),$r$);

  -- (b) a purchased unit taken as vouchers is not unlimited therapy
  a := $a$                 p.holiday_country_source
            from public.purchased_therapy_entitlements p where p.customer_id = p_customer_id$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: therapy_customer_detail purchased anchor found % times', n; end if;
  d := replace(d, a, $r$                 p.holiday_country_source, p.eligible_service_ids
            from public.purchased_therapy_entitlements p where p.customer_id = p_customer_id
             and p.benefit_choice is distinct from 'voucher'$r$);

  a := $a$                 l.holiday_country_source
            from public.therapy_entitlements l$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: therapy_customer_detail legacy anchor found % times', n; end if;
  d := replace(d, a, $r$                 l.holiday_country_source, null::uuid[]
            from public.therapy_entitlements l$r$);

  -- (c) unclaimed: a choice still to be made says so; vouchers are listed
  --     through their own allowance, not as a pending unlimited period
  a := $a$          select 'purchased', p.entitlement_no, p.status, 'unlimited', null,
                 p.duration_months, p.activation_deadline
            from public.purchased_therapy_entitlements p
           where p.customer_id = p_customer_id and p.status = 'pending_activation'$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: therapy_customer_detail pending anchor found % times', n; end if;
  d := replace(d, a, $r$          select 'purchased', p.entitlement_no, p.status,
                 case when p.benefit_choice is null and coalesce(array_length(p.offered_choices,1),0) > 1
                      then 'choice' else 'unlimited' end,
                 case when p.benefit_choice is null and coalesce(array_length(p.offered_choices,1),0) > 1
                      then p.voucher_qty_snapshot end,
                 p.duration_months, p.activation_deadline
            from public.purchased_therapy_entitlements p
           where p.customer_id = p_customer_id and p.status = 'pending_activation'
             and p.benefit_choice is distinct from 'voucher'$r$);
  -- (d) a voucher allowance with nothing left to collect (all collected, or the
  --     rest withdrawn by a refund) is not an unclaimed benefit
  a := $a$            from public.therapy_entitlements l
           where l.customer_id = p_customer_id and l.status = 'pending_activation'$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: therapy_customer_detail legacy pending anchor found % times', n; end if;
  d := replace(d, a, $r$            from public.therapy_entitlements l
           where l.customer_id = p_customer_id and l.status = 'pending_activation'
             and not (coalesce(l.entitlement_kind,'') = 'voucher'
                      and coalesce(l.voucher_qty,0) - public.entitlement_claimed_qty(l.id)
                          - coalesce(l.revoked_qty,0) <= 0)
             and not (l.claim_source_type = 'therapy_package'
                      and l.activation_deadline < public.sg_today())$r$);
  execute d;
end $mig$;

do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.therapy_customer_summary(text,integer,integer,boolean)'::regprocedure);
  if position('359:' in d) > 0 then raise notice '359: therapy_customer_summary already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'b9728f94967801c7da5f2f502acc12f3' then
    raise exception '359: therapy_customer_summary is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$          from public.purchased_therapy_entitlements
        union all$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: therapy_customer_summary anchor found % times', n; end if;
  execute replace(d, a, $r$          from public.purchased_therapy_entitlements
         -- 359: a unit taken as vouchers holds no therapy period; it is listed
         -- (as unclaimed) only while vouchers are still owed on it
         where benefit_choice is distinct from 'voucher'
            or (status = 'pending_activation' and exists (
                  select 1 from public.therapy_entitlements te
                   where te.id = purchased_therapy_entitlements.voucher_entitlement_id and te.status <> 'cancelled'
                     and coalesce(te.voucher_qty,0) - public.entitlement_claimed_qty(te.id)
                         - coalesce(te.revoked_qty,0) > 0))
        union all$r$);
end $mig$;

do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.customer_overview(uuid)'::regprocedure);
  if position('359:' in d) > 0 then raise notice '359: customer_overview already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '9761f7c836f5b44706189502f619565b' then
    raise exception '359: customer_overview is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$'activation', e.activation_date, 'expiry', e.expiry_date) order by e.created_at desc)$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '359: customer_overview anchor found % times', n; end if;
  execute replace(d, a, $r$'activation', e.activation_date, 'expiry', e.expiry_date,
        -- 359: what the unit was taken as, and what its therapy covers
        'benefit', e.benefit_choice, 'offers_choice', coalesce(array_length(e.offered_choices,1),0) > 1,
        'covers', public.therapy_services_coverage(e.eligible_service_ids)) order by e.created_at desc)$r$);
end $mig$;

-- ── 8. who may call what (339: functions are not endpoints by default) ──────
revoke all on function public.therapy_services_coverage(uuid[]) from public, anon, authenticated;
revoke all on function public.therapy_unit_consumed(uuid) from public, anon, authenticated;
grant execute on function public.therapy_services_coverage(uuid[]) to service_role;
grant execute on function public.therapy_unit_consumed(uuid) to service_role;

revoke all on function public.save_therapy_package(uuid,text,text,text,boolean,text,integer,integer,uuid,uuid[],uuid[]) from public, anon;
grant execute on function public.save_therapy_package(uuid,text,text,text,boolean,text,integer,integer,uuid,uuid[],uuid[]) to authenticated, service_role;
revoke all on function public.claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text) from public, anon;
grant execute on function public.claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text) to authenticated, service_role;

notify pgrst, 'reload schema';
