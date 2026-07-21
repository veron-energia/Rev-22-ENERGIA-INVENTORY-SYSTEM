-- =====================================================================
-- ENERGIA — 57: Customer purchase timeline + consultant notes log
--
-- 1. customer_purchase_timeline(customer) — invoice headers + line items for
--    the profile timeline (newest first).
-- 2. consultant_notes — a running, timestamped log of consultant entries per
--    health survey (and customer). Each submit adds a NEW row; the existing
--    review_health_survey "Save Review" flow is untouched.
--
-- Additive + idempotent. Run AFTER 56.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. Purchase timeline — one JSON array of invoices, each with its lines.
-- =====================================================================
create or replace function public.customer_purchase_timeline(p_customer_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(row order by row->>'date' desc nulls last), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'invoice_id', i.id,
      'invoice_no', i.invoice_no,
      'date', coalesce(i.paid_at, i.created_at),
      'status', i.status,
      'store', s.name,
      'total', i.total_amount,
      'paid', i.paid_amount,
      'is_topup', coalesce(i.is_topup, false),
      'save_earth', case when i.save_earth_applied then coalesce(i.save_earth_amount,0) else 0 end,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'kind', ii.line_kind,
          'name', coalesce(p.name, mp.name, ii.plan_name_snapshot, v.name, pr.name, 'item'),
          'qty', ii.quantity,
          'unit_price', ii.unit_price,
          'line_total', ii.line_total,
          'price_mode', ii.price_mode
        ) order by ii.created_at)
        from public.invoice_items ii
        left join public.products p on p.id = ii.product_id
        left join public.membership_plans mp on mp.id = ii.membership_plan_id
        left join public.vouchers v on v.id = ii.voucher_id
        left join public.promotions pr on pr.id = ii.promotion_id
        where ii.invoice_id = i.id), '[]'::jsonb)
    ) as row
    from public.invoices i
    left join public.stores s on s.id = i.store_id
    where i.customer_id = p_customer_id and i.deleted_at is null
  ) t;
$$;

-- =====================================================================
-- 2. Consultant notes — running timestamped log.
-- =====================================================================
create table if not exists public.consultant_notes (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid references public.health_surveys(id),
  customer_id uuid references public.customers(id),
  acidity_result text check (acidity_result in ('red','green','blue')),
  health_goals text,
  remarks_condition text,
  remarks_recommendation text,
  attachments jsonb not null default '[]'::jsonb,   -- [{name,url,size}] metadata
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_consultant_notes_survey on public.consultant_notes(survey_id);
create index if not exists idx_consultant_notes_customer on public.consultant_notes(customer_id);

alter table public.consultant_notes enable row level security;
drop policy if exists "read consultant notes" on public.consultant_notes;
create policy "read consultant notes" on public.consultant_notes for select to authenticated using (true);

-- Add a consultant note entry (Owner/Manager only). Each call = one new entry.
create or replace function public.add_consultant_note(
  p_survey_id uuid, p_customer_id uuid, p_acidity text,
  p_health_goals text, p_condition text, p_recommendation text,
  p_attachments jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_cust uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can add consultant notes'; end if;
  if p_acidity is not null and p_acidity not in ('red','green','blue') then
    raise exception 'Invalid acidity result'; end if;
  -- Resolve customer from the survey if not passed.
  v_cust := p_customer_id;
  if v_cust is null and p_survey_id is not null then
    select customer_id into v_cust from public.health_surveys where id = p_survey_id;
  end if;

  insert into public.consultant_notes (survey_id, customer_id, acidity_result,
    health_goals, remarks_condition, remarks_recommendation, attachments, created_by)
  values (p_survey_id, v_cust, p_acidity, p_health_goals, p_condition, p_recommendation,
    coalesce(p_attachments, '[]'::jsonb), auth.uid())
  returning id into v_id;

  perform public.write_audit_ex('consultant_notes', v_id, 'consultant_note_added',
    null, jsonb_build_object('survey', p_survey_id, 'acidity', p_acidity),
    'health_survey', null, null);
  return v_id;
end $$;

-- List consultant notes for a survey OR a customer (newest first), with author.
create or replace function public.consultant_notes_for(
  p_survey_id uuid default null, p_customer_id uuid default null
) returns table (
  id uuid, created_at timestamptz, author text, acidity_result text,
  health_goals text, remarks_condition text, remarks_recommendation text, attachments jsonb
) language sql stable security definer set search_path = public as $$
  select n.id, n.created_at, pr.full_name, n.acidity_result,
    n.health_goals, n.remarks_condition, n.remarks_recommendation, n.attachments
  from public.consultant_notes n
  left join public.profiles pr on pr.id = n.created_by
  where (p_survey_id is null or n.survey_id = p_survey_id)
    and (p_customer_id is null or n.customer_id = p_customer_id)
  order by n.created_at desc;
$$;

notify pgrst, 'reload schema';
