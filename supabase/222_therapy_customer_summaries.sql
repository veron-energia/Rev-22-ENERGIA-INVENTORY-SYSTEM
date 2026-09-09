-- =====================================================================
-- ENERGIA — CUSTOMER-LINKED THERAPY AND VOUCHER READ MODELS
--
-- One question, asked properly: what does this customer actually hold?
--
-- There is already exactly one authoritative record of a customer's vouchers —
-- customer_reward_vouchers, with source_type/source_id saying where each came
-- from (Legacy reward, premium bundle, promotion, invoice reopening). Nothing
-- here creates a second balance, and nothing infers a balance from a package
-- quantity: a package says what was sold, not what is left.
--
-- Two counting rules that keep the totals honest:
--
--   * The balance comes from the held/redeemed/revoked status on the issued
--     rows. voucher_redemptions is history, shown but never added up, because
--     a redemption already shows as a redeemed issuance — counting both would
--     double count every use.
--   * An entitlement and the vouchers it issued are one grant, not two. The
--     entitlement is shown as the SOURCE of the vouchers, never as a separate
--     balance beside them.
--
-- Therapy vouchers and money-off vouchers are counted separately and labelled
-- with their unit. A session and a dollar are not addable.
--
-- Aggregation happens in SQL over the whole set, so a page limit can never
-- change a total. Read-only: nothing here redeems, issues or expires anything.
--
-- Additive. Run AFTER 220 and 221. Safe to run more than once.
-- =====================================================================

set check_function_bodies = off;

-- The unit a voucher is counted in. 'normal' vouchers buy a service; the
-- discount kinds are money off an invoice. Mixing them into one number would
-- be meaningless, so the read models keep them apart.
create or replace function public.voucher_unit(p_kind public.voucher_kind)
returns text language sql immutable as $function$
  select case when p_kind = 'normal' then 'session' else 'money' end
$function$;

-- ---------------------------------------------------------------------
-- 1. One customer's voucher holdings, by voucher and by source.
-- ---------------------------------------------------------------------
-- source_ref was added to the returned columns after the first draft of this
-- file, and PostgreSQL will not change a function's output columns in place. On
-- a database that has never seen this file these drop nothing; on one that has,
-- they are what makes it safe to run again. therapy_customer_detail is dropped
-- with it and recreated below, in that order.
drop function if exists public.therapy_customer_detail(uuid);
drop function if exists public.therapy_customer_voucher_balances(uuid);

create or replace function public.therapy_customer_voucher_balances(p_customer_id uuid)
returns table (
  voucher_id uuid, voucher_name text, voucher_kind text, unit text,
  source_type text, source_label text, source_ref uuid,
  issued_qty integer, redeemed_qty integer, revoked_qty integer, remaining_qty integer,
  first_issued_at timestamptz, last_issued_at timestamptz,
  valid_from date, valid_until date, is_voucher_active boolean)
language sql stable security definer set search_path = public as $function$
  -- The source is resolved per row first, then grouped. Older rows predate
  -- source_type and only carry an entitlement_id, so that stands in for one.
  with issued as (
    select crv.*,
           coalesce(crv.source_type,
                    case when crv.entitlement_id is not null
                         then 'legacy_entitlement' else 'unknown' end) as eff_source,
           -- Which grant this line came from. Two premium bundles are two lines,
           -- not one merged total, so a customer can see where each came from.
           coalesce(crv.source_id, crv.entitlement_id) as eff_ref
      from public.customer_reward_vouchers crv
     where crv.customer_id = p_customer_id
       and (public.is_manager_or_above()
            or crv.store_id is null or public.user_has_store_access(crv.store_id))
  )
  select v.id, v.name, v.voucher_kind::text, public.voucher_unit(v.voucher_kind),
         i.eff_source,
         case i.eff_source
           when 'legacy_entitlement' then 'Legacy qualification reward'
           when 'premium_bundle'     then 'Premium bundle'
           when 'invoice_reopen'     then 'Invoice correction'
           when 'promotion'          then 'Promotion'
           when 'credit_package'     then 'Credit package'
           else 'Source not recorded' end,
         i.eff_ref,
         sum(i.quantity)::integer,
         sum(case when i.status = 'redeemed' then i.quantity else 0 end)::integer,
         sum(case when i.status = 'revoked'  then i.quantity else 0 end)::integer,
         -- Only 'held' is spendable. Revoked and redeemed are shown, not counted.
         sum(case when i.status = 'held'     then i.quantity else 0 end)::integer,
         min(i.issued_at), max(i.issued_at),
         v.valid_from, v.valid_until, v.is_active and v.deleted_at is null
    from issued i
    join public.vouchers v on v.id = i.voucher_id
   group by v.id, v.name, v.voucher_kind, i.eff_source, i.eff_ref,
            v.valid_from, v.valid_until, v.is_active, v.deleted_at
   order by v.name
$function$;

-- ---------------------------------------------------------------------
-- 2. Every customer who holds anything, with their totals.
--
-- The totals are computed across the whole table and only then paged, so a
-- limit changes which customers are listed, never what any of them holds.
-- total_customers comes back on every row so the caller can show "showing 50
-- of 812" instead of quietly truncating.
-- ---------------------------------------------------------------------
create or replace function public.therapy_customer_summary(
  p_search text default null, p_limit integer default 50, p_offset integer default 0,
  p_only_active boolean default false)
returns table (
  customer_id uuid, customer_name text, customer_phone text, customer_no text,
  therapy_vouchers_issued integer, therapy_vouchers_redeemed integer,
  therapy_vouchers_remaining integer,
  money_vouchers_remaining integer,
  vouchers_revoked integer,
  unlimited_active integer, unlimited_scheduled integer,
  unlimited_pending integer, unlimited_finished integer,
  current_unlimited_expiry date, current_unlimited_days_remaining integer,
  next_unlimited_start date,
  needs_review boolean, total_customers bigint)
language sql stable security definer set search_path = public as $function$
  with vouchers as (
    select crv.customer_id,
           sum(case when v.voucher_kind = 'normal' then crv.quantity else 0 end) as t_issued,
           sum(case when v.voucher_kind = 'normal' and crv.status = 'redeemed' then crv.quantity else 0 end) as t_redeemed,
           sum(case when v.voucher_kind = 'normal' and crv.status = 'held' then crv.quantity else 0 end) as t_remaining,
           sum(case when v.voucher_kind <> 'normal' and crv.status = 'held' then crv.quantity else 0 end) as m_remaining,
           sum(case when crv.status = 'revoked' then crv.quantity else 0 end) as revoked
      from public.customer_reward_vouchers crv
      join public.vouchers v on v.id = crv.voucher_id
     group by crv.customer_id
  ),
  unlimited as (
    select u.customer_id,
           count(*) filter (where u.status = 'active')             as n_active,
           count(*) filter (where u.status = 'scheduled')          as n_scheduled,
           count(*) filter (where u.status = 'pending_activation') as n_pending,
           count(*) filter (where u.status in ('expired','cancelled','refunded')) as n_done,
           max(u.expiry_date) filter (where u.status = 'active')   as cur_expiry,
           min(u.activation_date) filter (where u.status = 'scheduled') as next_start,
           bool_or(u.status in ('active','scheduled') and u.holiday_country is null) as no_country
      from (
        select customer_id, status, activation_date, expiry_date, holiday_country
          from public.purchased_therapy_entitlements
        union all
        select customer_id, status, activation_date, expiry_date, holiday_country
          from public.therapy_entitlements
         where coalesce(entitlement_kind, 'unlimited') = 'unlimited'
      ) u
     group by u.customer_id
  ),
  joined as (
    select c.id, c.full_name, c.phone,
           coalesce(vo.t_issued, 0)::integer   as t_issued,
           coalesce(vo.t_redeemed, 0)::integer as t_redeemed,
           coalesce(vo.t_remaining, 0)::integer as t_remaining,
           coalesce(vo.m_remaining, 0)::integer as m_remaining,
           coalesce(vo.revoked, 0)::integer    as revoked,
           coalesce(un.n_active, 0)::integer   as n_active,
           coalesce(un.n_scheduled, 0)::integer as n_scheduled,
           coalesce(un.n_pending, 0)::integer  as n_pending,
           coalesce(un.n_done, 0)::integer     as n_done,
           un.cur_expiry, un.next_start, coalesce(un.no_country, false) as no_country
      from public.customers c
      left join vouchers vo on vo.customer_id = c.id
      left join unlimited un on un.customer_id = c.id
     where c.deleted_at is null
       and (vo.customer_id is not null or un.customer_id is not null)
       and (p_search is null or btrim(p_search) = ''
            or c.full_name ilike '%' || btrim(p_search) || '%'
            or c.phone ilike '%' || btrim(p_search) || '%')
       and (not p_only_active
            or coalesce(vo.t_remaining, 0) > 0 or coalesce(vo.m_remaining, 0) > 0
            or coalesce(un.n_active, 0) > 0 or coalesce(un.n_scheduled, 0) > 0)
  )
  select j.id, j.full_name, j.phone, null::text,
         j.t_issued, j.t_redeemed, j.t_remaining, j.m_remaining, j.revoked,
         j.n_active, j.n_scheduled, j.n_pending, j.n_done,
         j.cur_expiry,
         case when j.cur_expiry is null then null
              when j.cur_expiry < public.sg_today() then 0
              -- Inclusive of today and of the expiry day, matching the
              -- inclusive expiry convention. Calendar days, not visits.
              else (j.cur_expiry - public.sg_today()) + 1 end,
         j.next_start,
         j.no_country,
         count(*) over ()
    from joined j
   order by j.full_name
   limit  greatest(coalesce(p_limit, 50), 1)
  offset greatest(coalesce(p_offset, 0), 0)
$function$;

-- ---------------------------------------------------------------------
-- 3. One customer, expanded: where every benefit came from and what
--    happened to it.
-- ---------------------------------------------------------------------
create or replace function public.therapy_customer_detail(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $function$
declare v_today date := public.sg_today(); v_out jsonb;
begin
  select jsonb_build_object(
    'customer', (select jsonb_build_object('id', c.id, 'name', c.full_name, 'phone', c.phone)
                   from public.customers c where c.id = p_customer_id),
    'as_of', v_today,
    'expiry_is_inclusive', true,

    'vouchers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'voucher_id', b.voucher_id, 'name', b.voucher_name,
               'kind', b.voucher_kind, 'unit', b.unit,
               'source_type', b.source_type, 'source', b.source_label,
               'source_ref', b.source_ref,
               'issued', b.issued_qty, 'redeemed', b.redeemed_qty,
               'revoked', b.revoked_qty, 'remaining', b.remaining_qty,
               'first_issued_at', b.first_issued_at, 'last_issued_at', b.last_issued_at,
               'valid_from', b.valid_from, 'valid_until', b.valid_until,
               -- Expiry rules are the voucher's own and are not restated here.
               'expired', b.valid_until is not null and b.valid_until < v_today,
               'voucher_active', b.is_voucher_active)
             order by b.voucher_name, b.source_type)
        from public.therapy_customer_voucher_balances(p_customer_id) b), '[]'::jsonb),

    -- History, shown and never added into a balance.
    'redemptions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'at', vr.created_at, 'voucher', v.name, 'invoice_id', vr.invoice_id,
               'discount_applied', vr.discount_applied) order by vr.created_at desc)
        from public.voucher_redemptions vr
        join public.vouchers v on v.id = vr.voucher_id
       where vr.customer_id = p_customer_id), '[]'::jsonb),

    'revocations', coalesce((
      select jsonb_agg(jsonb_build_object(
               'voucher', v.name, 'quantity', crv.quantity, 'notes', crv.notes,
               'issued_at', crv.issued_at) order by crv.issued_at desc)
        from public.customer_reward_vouchers crv
        join public.vouchers v on v.id = crv.voucher_id
       where crv.customer_id = p_customer_id and crv.status = 'revoked'), '[]'::jsonb),

    'unlimited', coalesce((
      select jsonb_agg(x order by x->>'activation_date' desc nulls last) from (
        select jsonb_build_object(
          'kind', u.k, 'id', u.id, 'entitlement_no', u.entitlement_no,
          'package_name', u.package_name, 'months', u.duration_months,
          'source', case u.k when 'purchased' then 'Purchased' else 'Legacy qualification' end,
          'status', u.status,
          'scheduled_date', u.scheduled_date,
          'activation_date', u.activation_date,
          'base_expiry', u.base_expiry_date,
          'closure_days_added', u.closure_days_added,
          'expiry_date', u.expiry_date,
          'holiday_country', u.holiday_country, 'holiday_region', u.holiday_region,
          'holiday_country_source', u.holiday_country_source,
          'calendar_days_remaining',
             case when u.expiry_date is null or u.status <> 'active' then null
                  when u.expiry_date < v_today then 0
                  else (u.expiry_date - v_today) + 1 end,
          'coverage', public.therapy_calendar_gaps(u.activation_date, u.expiry_date,
                                                   u.holiday_country, u.holiday_region),
          'explanation', case when u.activation_date is null then null
                              else public.therapy_expiry_explanation(u.activation_date,
                                     u.duration_months, u.holiday_country, u.holiday_region) end,
          'adjustments', coalesce((
            select jsonb_agg(jsonb_build_object(
                     'at', a.created_at, 'action', a.action, 'reason', a.reason,
                     'old_expiry', a.old_expiry, 'new_expiry', a.new_expiry,
                     'old_country', a.old_country, 'new_country', a.new_country)
                   order by a.created_at desc)
              from public.therapy_expiry_adjustments a
             where a.entitlement_id = u.id), '[]'::jsonb)) as x
        from (
          select 'purchased'::text as k, p.id, p.entitlement_no, p.package_name, p.duration_months,
                 p.status, p.scheduled_date, p.activation_date, p.expiry_date,
                 p.base_expiry_date, p.closure_days_added, p.holiday_country, p.holiday_region,
                 p.holiday_country_source
            from public.purchased_therapy_entitlements p where p.customer_id = p_customer_id
          union all
          select 'legacy', l.id, l.entitlement_no, l.package_name, l.duration_months,
                 l.status, null::date, l.activation_date, l.expiry_date,
                 l.base_expiry_date, l.closure_days_added, l.holiday_country, l.holiday_region,
                 l.holiday_country_source
            from public.therapy_entitlements l
           where l.customer_id = p_customer_id
             and coalesce(l.entitlement_kind, 'unlimited') = 'unlimited'
        ) u
      ) s), '[]'::jsonb),

    -- Unclaimed and refunded benefits, kept apart from what is usable today.
    'pending', coalesce((
      select jsonb_agg(jsonb_build_object(
               'kind', e.k, 'entitlement_no', e.entitlement_no, 'status', e.status,
               'reward_kind', e.entitlement_kind, 'voucher_qty', e.voucher_qty,
               'months', e.duration_months, 'deadline', e.activation_deadline)
             order by e.activation_deadline)
        from (
          select 'legacy'::text as k, l.entitlement_no, l.status, l.entitlement_kind,
                 l.voucher_qty, l.duration_months, l.activation_deadline
            from public.therapy_entitlements l
           where l.customer_id = p_customer_id and l.status = 'pending_activation'
          union all
          select 'purchased', p.entitlement_no, p.status, 'unlimited', null,
                 p.duration_months, p.activation_deadline
            from public.purchased_therapy_entitlements p
           where p.customer_id = p_customer_id and p.status = 'pending_activation'
        ) e), '[]'::jsonb)
  ) into v_out;
  return v_out;
end $function$;

grant execute on function public.voucher_unit(public.voucher_kind) to authenticated;
grant execute on function public.therapy_customer_voucher_balances(uuid) to authenticated;
grant execute on function public.therapy_customer_summary(text,integer,integer,boolean) to authenticated;
grant execute on function public.therapy_customer_detail(uuid) to authenticated;
