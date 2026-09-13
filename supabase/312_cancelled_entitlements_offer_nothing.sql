begin;
-- =====================================================================
-- A CANCELLED ENTITLEMENT OFFERS NOTHING
--
-- claim_entitlement_vouchers has always refused a cancelled entitlement, so
-- nothing could actually be taken. But the two things that REPORT what is
-- outstanding worked from quantities alone and ignored the status, so a
-- cancelled reward of ten still read as ten waiting to be claimed:
-- reconciliation listed it as needing an eligible list, and the claim panel
-- would draw the whole claim form before the server refused the click.
--
-- Remaining now means what a person can actually take. The entitled figure is
-- untouched, so nothing is hidden -- a cancelled reward still shows what it
-- was worth, next to a nil remainder and a status that explains why.
-- =====================================================================

create or replace function public.entitlement_voucher_state(p_entitlement_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare e public.therapy_entitlements%rowtype; v_claimed integer; v_remaining integer; v_elig jsonb;
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
  if not found then raise exception 'Entitlement not found'; end if;
  if e.store_id is not null and not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;

  v_claimed := public.entitlement_claimed_qty(p_entitlement_id);

  -- Cancelled means nothing can be taken, whatever the arithmetic says.
  v_remaining := case when e.status = 'cancelled' then 0
                 else greatest(coalesce(e.voucher_qty,0) - v_claimed - coalesce(e.revoked_qty,0), 0) end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'voucher_id', v.id, 'name', v.name,
           'available', case when v.qty_type = 'unlimited' then null
                             else coalesce((select current_qty from public.voucher_store_stock s
                                             where s.voucher_id = v.id and s.store_id = e.store_id),0) end,
           'still_offered', v.is_active and v.deleted_at is null and coalesce(v.reward_eligible,true))
         order by v.name), '[]'::jsonb)
    into v_elig
    from public.vouchers v
   where v.id = any(coalesce(e.eligible_voucher_ids,'{}'::uuid[]));

  return jsonb_build_object(
    'entitlement_id', e.id,
    'entitlement_no', e.entitlement_no,
    'customer_id', e.customer_id,
    'store_id', e.store_id,
    'package_name', e.package_name,
    'entitled', coalesce(e.voucher_qty,0),
    'claimed', v_claimed,
    'revoked', coalesce(e.revoked_qty,0),
    'remaining', v_remaining,
    'cancelled', e.status = 'cancelled',
    'claim_deadline', e.activation_deadline,
    'deadline_passed', e.activation_deadline is not null and public.sg_today() > e.activation_deadline,
    'status', e.status,
    'source', e.claim_source_type,
    'source_invoice_id', e.claim_source_invoice_id,
    'eligible', v_elig,
    'snapshot_present', e.eligible_voucher_ids is not null);
end $$;
grant execute on function public.entitlement_voucher_state(uuid) to authenticated;

create or replace function public.voucher_claim_reconciliation(p_store_id uuid default null)
returns table (
  entitlement_id uuid, entitlement_no text, customer_name text, store_id uuid,
  package_name text, entitled integer, claimed integer, remaining integer,
  claim_deadline date, deadline_passed boolean, status text,
  has_snapshot boolean, classification text, suggested_eligible uuid[])
language sql stable security definer set search_path to 'public' as $$
  with base as (
    select e.id, e.entitlement_no, c.full_name as customer_name, e.store_id,
           e.package_name, coalesce(e.voucher_qty,0) as entitled,
           public.entitlement_claimed_qty(e.id) as claimed,
           coalesce(e.revoked_qty,0) as revoked,
           e.activation_deadline, e.status, e.eligible_voucher_ids,
           e.earner_kind, e.customer_id
      from public.therapy_entitlements e
      join public.customers c on c.id = e.customer_id
     where coalesce(e.entitlement_kind,'') = 'voucher'
       and (p_store_id is null or e.store_id = p_store_id)
       and public.user_has_store_access(e.store_id)
  ), shaped as (
    select b.*,
           case when b.status = 'cancelled' then 0
                else greatest(b.entitled - b.claimed - b.revoked, 0) end as remaining
      from base b
  )
  select s.id, s.entitlement_no, s.customer_name, s.store_id, s.package_name,
         s.entitled, s.claimed, s.remaining::integer,
         s.activation_deadline,
         s.activation_deadline is not null and public.sg_today() > s.activation_deadline,
         s.status,
         s.eligible_voucher_ids is not null as has_snapshot,
         case
           -- Why there is nothing to arrange matters more than the fact of it.
           when s.status = 'cancelled' then 'cancelled'
           when s.remaining <= 0 then 'nothing_outstanding'
           when s.eligible_voucher_ids is not null then 'ready'
           when s.activation_deadline is not null and public.sg_today() > s.activation_deadline
                then 'expired_unclaimed'
           else 'needs_eligible_list'
         end as classification,
         case when s.eligible_voucher_ids is null and s.status <> 'cancelled' then (
           select coalesce(array_agg(distinct cpv.voucher_id), '{}')
             from public.credit_package_sales cs
             join public.credit_package_vouchers cpv on cpv.package_id = cs.package_id
            where cs.customer_id = s.customer_id and s.earner_kind = 'credit_package')
         end as suggested_eligible
    from shaped s
   order by s.activation_deadline nulls last, s.entitlement_no
$$;
grant execute on function public.voucher_claim_reconciliation(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
