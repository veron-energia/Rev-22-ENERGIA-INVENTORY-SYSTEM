begin;
-- =====================================================================
-- SAYING WHAT A CORRECTION WILL DO, AND WHY A COMMISSION IS WHAT IT IS
--
-- Two things this workflow could not do.
--
-- It could not explain itself. correct_invoice takes a header and applies it;
-- if a field is absent the invoice keeps what it had, and the save reports
-- success either way. An affiliate the user believes they changed, in a payload
-- that never carried the field, is a successful no-op -- indistinguishable at
-- the screen from a change that worked. The preview below states the effects
-- BEFORE saving, so a no-op is visible as one.
--
-- And nothing could answer "why does this invoice credit that person, and why
-- is the commission that amount". The diagnosis resolves the whole chain --
-- explicit selection, fallback, eligibility, payout state -- for one invoice.
-- It writes nothing, so it is safe to run against a live record.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Why this invoice's affiliate commission is what it is.
--
-- Read-only. Run it on an invoice whose commission looks wrong and it will say
-- which of the four things is true: no affiliate resolves, an explicit choice
-- is in force, the customer's referrer is being used as a fallback, or the
-- affiliate resolves but is not eligible to be paid.
-- ---------------------------------------------------------------------
create or replace function public.diagnose_invoice_affiliate(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; v_t1 uuid; v_t2 uuid; v_src text;
        v_rows jsonb; v_paid jsonb; v_state jsonb; v_explain text;
begin
  select * into i from public.invoices where id = p_invoice_id;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(i.store_id) then
    raise exception 'No access to this store'; end if;

  -- The same resolution earn_invoice_commission performs.
  if i.affiliate_selection_explicit and i.affiliate_id is null then
    v_src := 'explicit_none';
  elsif i.affiliate_id is not null then
    v_src := 'explicit_affiliate';
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = i.affiliate_id;
    select c.referred_by into v_t2 from public.customers c where c.id = v_t1;
  else
    v_src := 'customer_profile_referrer';
    select tier1, tier2 into v_t1, v_t2 from public.customer_referrers(i.customer_id);
  end if;

  if v_t1 is not null then v_state := public.customer_affiliate_state(v_t1); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'tier', x.tier, 'status', x.status, 'amount', x.commission_amount,
           'rate', x.rate, 'line_amount', x.line_amount,
           'block_reason', x.block_reason,
           'referrer_customer_id', x.referrer_customer_id,
           'referrer_name', (select full_name from public.customers where id = x.referrer_customer_id),
           'payout_id', x.payout_id, 'adjusts', x.adjusts_commission_id,
           'reversal_reason', x.reversal_reason) order by x.created_at), '[]'::jsonb)
    into v_rows
    from public.commissions x where x.invoice_id = p_invoice_id;

  select jsonb_build_object(
           'earned', coalesce(sum(commission_amount) filter (where status = 'earned'), 0),
           'blocked', coalesce(sum(commission_amount) filter (where status = 'blocked'), 0),
           'paid_or_allocated', coalesce(sum(commission_amount) filter (where payout_id is not null), 0),
           'reversed', coalesce(sum(commission_amount) filter (where status = 'reversed'), 0))
    into v_paid
    from public.commissions where invoice_id = p_invoice_id;

  v_explain := case
    when v_src = 'explicit_none'
      then 'An explicit "None" is recorded on this invoice, so no affiliate commission is earned and the customer''s own referrer is deliberately not used.'
    when v_src = 'explicit_affiliate' and v_t1 is null
      then 'An affiliate is selected on this invoice but its customer record could not be resolved.'
    when v_src = 'explicit_affiliate' and v_t1 = i.customer_id
      then 'The selected affiliate is the buyer, and nobody earns commission on their own purchase.'
    when v_src = 'explicit_affiliate' and coalesce((v_state->>'eligible')::boolean, false)
      then 'The affiliate selected on this invoice is eligible, so tier 1 is earned for them.'
    when v_src = 'explicit_affiliate'
      then 'The affiliate selected on this invoice is not currently eligible, so the commission row exists but is blocked rather than payable.'
    when v_t1 is null
      then 'No affiliate is selected and the customer has no referrer, so no affiliate commission arises.'
    else 'No affiliate is selected on this invoice, so the customer''s own referrer is being credited. Selecting an affiliate here overrides that.'
  end;

  return jsonb_build_object(
    'invoice_id', i.id, 'invoice_no', i.invoice_no, 'status', i.status,
    'customer_id', i.customer_id,
    'customer_name', (select full_name from public.customers where id = i.customer_id),
    'invoice_affiliate_id', i.affiliate_id,
    'affiliate_selection_explicit', coalesce(i.affiliate_selection_explicit, false),
    'resolution', v_src,
    'tier1_customer_id', v_t1,
    'tier1_name', (select full_name from public.customers where id = v_t1),
    'tier1_eligible', coalesce((v_state->>'eligible')::boolean, false),
    'tier1_block_reason', case when v_t1 is not null and not coalesce((v_state->>'eligible')::boolean,false)
                               then public.affiliate_block_reason(v_t1) end,
    'tier2_customer_id', v_t2,
    'tier2_name', (select full_name from public.customers where id = v_t2),
    'customer_profile_referrer', (select referred_by from public.customers where id = i.customer_id),
    'commission_rows', v_rows,
    'totals', v_paid,
    'explanation', v_explain);
end $$;
grant execute on function public.diagnose_invoice_affiliate(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 2. What this correction would actually do.
--
-- Takes the same header the save will take, so what is previewed is what will
-- happen — including the case that matters most: a field the user believes
-- they changed which is not in the payload at all. That shows up here as
-- "unchanged", which is the whole point.
--
-- Read-only. It applies nothing.
-- ---------------------------------------------------------------------
create or replace function public.preview_invoice_correction(
  p_invoice_id uuid, p_header jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare i public.invoices%rowtype; v_effects jsonb := '[]'::jsonb; v_reviews jsonb := '[]'::jsonb;
        v_new_cust uuid; v_new_store uuid; v_new_aff uuid; v_aff_given boolean;
        v_moving jsonb; v_blocked jsonb; r record;
begin
  select * into i from public.invoices where id = p_invoice_id;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(i.store_id) then
    raise exception 'No access to this store'; end if;

  v_new_cust  := coalesce(nullif(p_header->>'customer_id','')::uuid, i.customer_id);
  v_new_store := coalesce(nullif(p_header->>'store_id','')::uuid, i.store_id);
  v_aff_given := p_header ? 'affiliate_id';
  v_new_aff   := case when v_aff_given then nullif(p_header->>'affiliate_id','')::uuid else i.affiliate_id end;

  -- ---- affiliate ----------------------------------------------------------
  if not v_aff_given then
    v_effects := v_effects || jsonb_build_array(jsonb_build_object(
      'area','affiliate','change','unchanged',
      'detail','No affiliate change is included in this save. The invoice keeps whoever it credits now.'));
  elsif v_new_aff is not distinct from i.affiliate_id
        and coalesce(i.affiliate_selection_explicit,false) then
    v_effects := v_effects || jsonb_build_array(jsonb_build_object(
      'area','affiliate','change','unchanged',
      'detail','The same affiliate is selected, so the commission is recalculated to the same result rather than duplicated.'));
  else
    v_effects := v_effects || jsonb_build_array(jsonb_build_object(
      'area','affiliate','change', case when v_new_aff is null then 'cleared' else 'changed' end,
      'from', (select c.full_name from public.customer_affiliates a join public.customers c on c.id=a.customer_id where a.id = i.affiliate_id),
      'to',   (select c.full_name from public.customer_affiliates a join public.customers c on c.id=a.customer_id where a.id = v_new_aff),
      'detail', case when v_new_aff is null
        then 'Affiliate commission on this invoice is reversed and none is re-earned. The customer''s own referrer is deliberately not used instead.'
        else 'Affiliate commission on this invoice is reversed and re-earned for the newly selected affiliate.' end));
    -- Money already paid out is adjusted, never quietly moved.
    if exists (select 1 from public.commissions
                where invoice_id = i.id and (payout_id is not null or status = 'paid')) then
      v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(
        'area','affiliate_payout',
        'detail','Some commission on this invoice has already been paid or allocated to a payout. That payment stays in the records; a balancing adjustment is raised instead. It is not recovered automatically and is not transferred to the new affiliate.'));
    end if;
  end if;

  -- ---- customer -----------------------------------------------------------
  if v_new_cust is distinct from i.customer_id then
    v_effects := v_effects || jsonb_build_array(jsonb_build_object(
      'area','customer','change','reassigned',
      'from',(select full_name from public.customers where id = i.customer_id),
      'to',(select full_name from public.customers where id = v_new_cust),
      'detail','The invoice keeps its number, payments and history. No new sale or payment is created.'));

    select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'what',description)), '[]'::jsonb)
      into v_moving from public.invoice_transferable_benefits(p_invoice_id) where movable;
    select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'what',description,'why',blocked_reason)), '[]'::jsonb)
      into v_blocked from public.invoice_transferable_benefits(p_invoice_id) where blocking;

    if jsonb_array_length(v_moving) > 0 then
      v_effects := v_effects || jsonb_build_array(jsonb_build_object(
        'area','benefits','change','transferring','items',v_moving,
        'detail','These unused benefits move to the new customer with their original source, deadlines and restrictions unchanged.'));
    end if;
    if jsonb_array_length(v_blocked) > 0 then
      v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(
        'area','benefits','items',v_blocked,
        'detail','These have already been used and will not move. The correction is refused until each is resolved through the benefit transfer review.'));
    end if;
  end if;

  -- ---- store --------------------------------------------------------------
  if v_new_store is distinct from i.store_id then
    v_effects := v_effects || jsonb_build_array(jsonb_build_object(
      'area','store','change','moved',
      'detail','Stock is returned at the original store and taken at the new one for the lines that hold stock.'));
  end if;

  -- ---- things that stop the save -----------------------------------------
  if (v_new_cust is distinct from i.customer_id or v_new_store is distinct from i.store_id)
     and public.invoice_untracked_voucher(i.id)
     and exists (select 1 from public.invoice_payments where invoice_id = i.id) then
    v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(
      'area','voucher_ownership',
      'detail','This invoice issued vouchers with no recorded owner, so the correction will be refused. An Owner or Manager can record the ownership from the invoice''s own captured contents first.',
      'action','reconcile_promotion_voucher_ownership'));
  end if;

  return jsonb_build_object(
    'invoice_id', i.id, 'invoice_no', i.invoice_no, 'status', i.status,
    'edit_count', coalesce(i.edit_count,0),
    'effects', v_effects,
    'needs_review', v_reviews,
    'blocking', jsonb_array_length(v_reviews) > 0,
    'affiliate', public.diagnose_invoice_affiliate(p_invoice_id));
end $$;
grant execute on function public.preview_invoice_correction(uuid,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
