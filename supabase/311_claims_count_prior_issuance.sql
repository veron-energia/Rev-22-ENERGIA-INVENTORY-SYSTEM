begin;
-- =====================================================================
-- VOUCHERS HANDED OVER BEFORE 310 STILL COUNT AS CLAIMED
--
-- 310 derived "claimed" from voucher_claims alone. Every claim made before it
-- existed went through claim_legacy_therapy, which issued the vouchers and
-- wrote no claim row -- so a reward that was taken in full came back as wholly
-- unclaimed, and the only guard in the way was a cancelled status.
--
-- On the live system that was five entitlements of ten, all already issued and
-- marked claimed, each offering another ten. Opening the panel on one of them
-- would have handed over a second set and taken the stock for it.
--
-- Claimed is now the claim rows PLUS anything issued against the entitlement
-- that did not come from a claim. Nothing is written to fix the old records:
-- the vouchers themselves are the evidence, and they were always there.
-- =====================================================================

-- ---------------------------------------------------------------------
-- One definition, used by every caller, so they cannot disagree again.
-- ---------------------------------------------------------------------
create or replace function public.entitlement_claimed_qty(p_entitlement_id uuid)
returns integer language sql stable security definer set search_path to 'public' as $$
  select coalesce((select sum(vc.quantity) from public.voucher_claims vc
                    where vc.entitlement_id = p_entitlement_id), 0)
       + coalesce((select sum(crv.quantity) from public.customer_reward_vouchers crv
                    where crv.entitlement_id = p_entitlement_id
                      and coalesce(crv.source_type,'') <> 'voucher_claim'), 0)
$$;
grant execute on function public.entitlement_claimed_qty(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- The three places that counted claims themselves.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.entitlement_voucher_state(uuid)'::regprocedure) into f;
  if position('entitlement_claimed_qty' in f) = 0 then
    f := replace(f,
      '  select coalesce(sum(quantity),0) into v_claimed'||chr(10)||
      '    from public.voucher_claims where entitlement_id = p_entitlement_id;',
      '  v_claimed := public.entitlement_claimed_qty(p_entitlement_id);');
    if position('entitlement_claimed_qty' in f) = 0 then
      raise exception 'entitlement_voucher_state does not match what 311 expects — align it by hand'; end if;
    execute f;
    raise notice 'entitlement_voucher_state now counts vouchers issued before 310';
  end if;
end $do$;

do $do$
declare f text;
begin
  select pg_get_functiondef('public.claim_entitlement_vouchers(uuid,jsonb,text)'::regprocedure) into f;
  if position('entitlement_claimed_qty' in f) = 0 then
    f := replace(f,
      '  select coalesce(sum(quantity),0) into v_claimed'||chr(10)||
      '    from public.voucher_claims where entitlement_id = p_entitlement_id;',
      '  v_claimed := public.entitlement_claimed_qty(p_entitlement_id);');
    if position('entitlement_claimed_qty' in f) = 0 then
      raise exception 'claim_entitlement_vouchers does not match what 311 expects — align it by hand'; end if;
    execute f;
    raise notice 'claim_entitlement_vouchers now counts vouchers issued before 310';
  end if;
end $do$;

do $do$
declare f text;
begin
  select pg_get_functiondef('public.revoke_unclaimed_entitlement_vouchers(uuid,text)'::regprocedure) into f;
  if position('entitlement_claimed_qty' in f) = 0 then
    f := replace(f,
      '    select coalesce(sum(quantity),0) into v_claimed'||chr(10)||
      '      from public.voucher_claims where entitlement_id = e.id;',
      '    v_claimed := public.entitlement_claimed_qty(e.id);');
    if position('entitlement_claimed_qty' in f) = 0 then
      raise exception 'revoke_unclaimed_entitlement_vouchers does not match what 311 expects — align it by hand'; end if;
    execute f;
    raise notice 'revoke_unclaimed_entitlement_vouchers now counts vouchers issued before 310';
  end if;
end $do$;

-- Restated rather than patched: the claimed figure appears twice in each.
create or replace function public.customer_outstanding_voucher_claims(p_customer_id uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(public.entitlement_voucher_state(e.id)
                            order by e.activation_deadline nulls last), '[]'::jsonb)
    from public.therapy_entitlements e
   where e.customer_id = p_customer_id
     and coalesce(e.entitlement_kind,'') = 'voucher'
     and e.status <> 'cancelled'
     and public.user_has_store_access(e.store_id)
     and coalesce(e.voucher_qty,0) - public.entitlement_claimed_qty(e.id)
         - coalesce(e.revoked_qty,0) > 0
$$;
grant execute on function public.customer_outstanding_voucher_claims(uuid) to authenticated;

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
  )
  select b.id, b.entitlement_no, b.customer_name, b.store_id, b.package_name,
         b.entitled, b.claimed,
         greatest(b.entitled - b.claimed - b.revoked, 0)::integer as remaining,
         b.activation_deadline,
         b.activation_deadline is not null and public.sg_today() > b.activation_deadline,
         b.status,
         b.eligible_voucher_ids is not null as has_snapshot,
         case
           when b.entitled - b.claimed - b.revoked <= 0 then 'nothing_outstanding'
           when b.eligible_voucher_ids is not null then 'ready'
           when b.activation_deadline is not null and public.sg_today() > b.activation_deadline
                then 'expired_unclaimed'
           else 'needs_eligible_list'
         end as classification,
         case when b.eligible_voucher_ids is null then (
           select coalesce(array_agg(distinct cpv.voucher_id), '{}')
             from public.credit_package_sales s
             join public.credit_package_vouchers cpv on cpv.package_id = s.package_id
            where s.customer_id = b.customer_id and b.earner_kind = 'credit_package')
         end as suggested_eligible
    from base b
   order by b.activation_deadline nulls last, b.entitlement_no
$$;
grant execute on function public.voucher_claim_reconciliation(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
