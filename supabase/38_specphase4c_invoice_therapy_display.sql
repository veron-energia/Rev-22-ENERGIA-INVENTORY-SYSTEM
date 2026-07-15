-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 4C: Invoice therapy display (spec 4.12)
--
-- Fixes a 4A gap first: source invoices are linked to only ONE entitlement
-- (the unique index uq_tei_invoice correctly enforces "an invoice can be
-- consumed once"). But a single qualification can create SEVERAL
-- entitlements (e.g. $5,000 -> 12-month + 1-month). Without grouping, an
-- invoice could only surface the first one.
--
-- Fix: qualification_group_id on therapy_entitlements. Every entitlement
-- created in one qualification shares a group. The invoice resolves:
--   invoice -> linked entitlement -> group -> ALL entitlements produced.
--
-- Then invoice_therapy_summary() returns everything spec 4.12 asks for.
--
-- Additive + idempotent. Run AFTER 37_specphase4b_date_change_permissions.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Grouping column. Existing rows become their own group (pre-migration
--    batches aren't retro-grouped; new qualifications group correctly).
-- ---------------------------------------------------------------------
alter table public.therapy_entitlements add column if not exists qualification_group_id uuid;
update public.therapy_entitlements set qualification_group_id = id where qualification_group_id is null;
create index if not exists idx_te_group on public.therapy_entitlements(qualification_group_id);

-- ---------------------------------------------------------------------
-- 2. Regenerate create_therapy_entitlements to stamp the group id.
--    (Same logic as 35, plus grouping.)
-- ---------------------------------------------------------------------
create or replace function public.create_therapy_entitlements(
  p_customer_id uuid,
  p_store_id uuid,
  p_invoice_ids uuid[],
  p_combination jsonb,
  p_topup_amount numeric default 0,
  p_topup_payments jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role user_role; v_eligible numeric := 0; v_inv record; v_sg date;
  v_combo jsonb; v_rule public.therapy_package_rules%rowtype; v_qty integer;
  v_need numeric := 0; v_used numeric := 0; v_created jsonb := '[]'::jsonb;
  v_ent_id uuid; v_no text; v_deadline date; v_pay_sum numeric := 0; v_topup_id uuid; k integer;
  v_group uuid := gen_random_uuid();
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(p_store_id) then raise exception 'No access to that store'; end if;
  if p_invoice_ids is null or array_length(p_invoice_ids,1) is null then raise exception 'Select at least one paid invoice'; end if;

  v_sg := null;
  for v_inv in
    select i.id, i.total_amount, (i.paid_at at time zone 'Asia/Singapore')::date d
    from public.invoices i where i.id = any(p_invoice_ids) for update
  loop
    if v_inv.d is null then raise exception 'An invoice is not paid'; end if;
    if v_sg is null then v_sg := v_inv.d; elsif v_sg <> v_inv.d then raise exception 'All invoices must share the same Singapore payment date'; end if;
    if exists (select 1 from public.therapy_entitlement_invoices t where t.invoice_id = v_inv.id) then
      raise exception 'An invoice has already been used for a therapy entitlement'; end if;
    v_eligible := v_eligible + v_inv.total_amount;
  end loop;

  if coalesce(p_topup_amount,0) > 0 then
    select coalesce(sum((x->>'amount')::numeric),0) into v_pay_sum from jsonb_array_elements(p_topup_payments) x;
    if round(v_pay_sum,2) <> round(p_topup_amount,2) then raise exception 'Top-up payment must equal the top-up amount'; end if;
    v_eligible := v_eligible + p_topup_amount;
  end if;

  for v_combo in select * from jsonb_array_elements(p_combination) loop
    select * into v_rule from public.therapy_package_rules where id = (v_combo->>'rule_id')::uuid;
    if not found then raise exception 'A selected package rule was not found'; end if;
    if v_rule.store_id <> p_store_id then raise exception 'A selected rule belongs to another store'; end if;
    v_qty := coalesce((v_combo->>'qty')::integer, 1);
    v_need := v_need + v_rule.qualifying_amount * v_qty;
  end loop;
  if v_need = 0 then raise exception 'Select at least one package'; end if;
  if round(v_need,2) > round(v_eligible,2) then
    raise exception 'Selected packages need %.2f but only %.2f is eligible', v_need, v_eligible; end if;

  if coalesce(p_topup_amount,0) > 0 then
    insert into public.therapy_qualification_topups (customer_id, store_id, amount, created_by)
    values (p_customer_id, p_store_id, p_topup_amount, auth.uid()) returning id into v_topup_id;
  end if;

  for v_combo in select * from jsonb_array_elements(p_combination) loop
    select * into v_rule from public.therapy_package_rules where id = (v_combo->>'rule_id')::uuid;
    v_qty := coalesce((v_combo->>'qty')::integer, 1);
    for k in 1..v_qty loop
      v_no := 'TE-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);
      v_deadline := public.sg_today() + coalesce(v_rule.activation_deadline_days, 365);
      insert into public.therapy_entitlements
        (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
         duration_months, voucher_qty, qualifying_amount, qualified_value, forfeited_value,
         activation_deadline, status, created_by, qualification_group_id)
      values (v_no, p_customer_id, p_store_id, v_rule.id, v_rule.name, v_rule.entitlement_kind,
         v_rule.duration_months, v_rule.voucher_qty, v_rule.qualifying_amount, v_rule.qualifying_amount, 0,
         v_deadline, 'pending_activation', auth.uid(), v_group)
      returning id into v_ent_id;
      v_used := v_used + v_rule.qualifying_amount;
      if v_topup_id is not null then update public.therapy_qualification_topups set entitlement_id = v_ent_id where id = v_topup_id and entitlement_id is null; end if;
      v_created := v_created || to_jsonb(v_ent_id);
    end loop;
  end loop;

  -- Source invoices link to the first entitlement; the GROUP ties the rest.
  v_ent_id := (v_created->>0)::uuid;
  for v_inv in select i.id, i.total_amount from public.invoices i where i.id = any(p_invoice_ids)
  loop
    insert into public.therapy_entitlement_invoices (entitlement_id, invoice_id, contributed_amount)
    values (v_ent_id, v_inv.id, v_inv.total_amount);
  end loop;
  update public.therapy_entitlements set forfeited_value = round(v_eligible - v_used, 2) where id = v_ent_id;

  perform public.write_audit_ex('therapy_entitlements', v_ent_id, 'therapy_entitlement_created', null,
    jsonb_build_object('eligible', v_eligible, 'used', v_used, 'forfeited', round(v_eligible - v_used,2),
      'count', jsonb_array_length(v_created), 'group', v_group),
    'therapy', null, p_store_id);

  return jsonb_build_object('success', true, 'eligible', v_eligible, 'used', v_used,
    'forfeited', round(v_eligible - v_used, 2), 'entitlement_ids', v_created, 'group_id', v_group);
end $$;

-- ---------------------------------------------------------------------
-- 3. Everything spec 4.12 wants to show on an invoice.
-- ---------------------------------------------------------------------
create or replace function public.invoice_therapy_summary(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_group uuid; v_inv public.invoices%rowtype;
  v_ents jsonb := '[]'::jsonb; v_e record;
  v_linked jsonb := '[]'::jsonb; v_topup numeric := 0;
  v_forfeited numeric := 0; v_eligible numeric := 0; v_qualified numeric := 0;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('found', false); end if;

  -- Which qualification (if any) consumed this invoice?
  select e.qualification_group_id into v_group
  from public.therapy_entitlement_invoices tei
  join public.therapy_entitlements e on e.id = tei.entitlement_id
  where tei.invoice_id = p_invoice_id
  limit 1;

  if v_group is null then
    -- Not used yet: report eligibility so staff know it can still qualify.
    return jsonb_build_object(
      'found', true, 'used', false,
      'eligible', (v_inv.status = 'paid' and v_inv.deleted_at is null),
      'invoice_total', v_inv.total_amount);
  end if;

  -- All invoices combined into this qualification.
  select coalesce(jsonb_agg(jsonb_build_object(
           'invoice_no', i.invoice_no, 'contributed_amount', tei.contributed_amount,
           'is_this_invoice', (i.id = p_invoice_id)) order by i.invoice_no), '[]'::jsonb),
         coalesce(sum(tei.contributed_amount), 0)
    into v_linked, v_eligible
  from public.therapy_entitlement_invoices tei
  join public.invoices i on i.id = tei.invoice_id
  join public.therapy_entitlements e on e.id = tei.entitlement_id
  where e.qualification_group_id = v_group;

  -- Qualification top-up recorded for this group.
  select coalesce(sum(t.amount), 0) into v_topup
  from public.therapy_qualification_topups t
  join public.therapy_entitlements e on e.id = t.entitlement_id
  where e.qualification_group_id = v_group;

  -- Forfeited is stored on the invoice-linked entitlement.
  select coalesce(sum(e.forfeited_value), 0) into v_forfeited
  from public.therapy_entitlements e where e.qualification_group_id = v_group;

  -- Every entitlement produced, with beneficiaries.
  for v_e in
    select e.* from public.therapy_entitlements e
    where e.qualification_group_id = v_group order by e.created_at, e.entitlement_no
  loop
    v_qualified := v_qualified + v_e.qualified_value;
    v_ents := v_ents || jsonb_build_object(
      'entitlement_no', v_e.entitlement_no,
      'package_name', v_e.package_name,
      'entitlement_kind', v_e.entitlement_kind,
      'duration_months', v_e.duration_months,
      'voucher_qty', v_e.voucher_qty,
      'qualifying_amount', v_e.qualifying_amount,
      'qualified_value', v_e.qualified_value,
      'forfeited_value', v_e.forfeited_value,
      'created_at', v_e.created_at,
      'activation_deadline', v_e.activation_deadline,
      'status', v_e.status,
      'beneficiaries', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'name', c.full_name, 'phone', c.phone,
          'portion_months', b.portion_months, 'portion_vouchers', b.portion_vouchers,
          'activation_date', b.activation_date, 'ending_date', b.ending_date,
          'status', public.therapy_effective_status(b.status, b.activation_date, b.ending_date, v_e.activation_deadline),
          'transferred_from', (select c2.full_name from public.customers c2 where c2.id = b.transferred_from)
        ) order by b.created_at), '[]'::jsonb)
        from public.therapy_entitlement_beneficiaries b
        join public.customers c on c.id = b.beneficiary_customer_id
        where b.entitlement_id = v_e.id)
    );
  end loop;

  return jsonb_build_object(
    'found', true, 'used', true, 'group_id', v_group,
    'entitlements', v_ents,
    'linked_invoices', v_linked,
    'invoices_total', v_eligible,
    'topup_amount', v_topup,
    'eligible_total', v_eligible + v_topup,
    'qualified_total', v_qualified,
    'forfeited_total', v_forfeited);
end $$;

notify pgrst, 'reload schema';
