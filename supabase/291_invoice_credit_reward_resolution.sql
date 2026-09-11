begin;
-- =====================================================================
-- REFUNDING OR CANCELLING A CREDIT PACKAGE THAT GRANTED REWARDS
--
-- Reported: refund and cancel are refused on credit-package invoices with
--
--   "This package includes qualification rewards. Resolve their exact
--    entitlement and redemption history before refunding, cancelling or moving
--    the purchase; credit-only allocations are incomplete."
--
-- Reproduced on a package sold and paid entirely under current code. The guard
-- in 191 raises whenever the sale has reward_units > 0, and NOTHING anywhere
-- clears that condition — unlike the bonus-lot condition beside it, which
-- verify_invoice_credit_sale_sources can satisfy. So it is not a review that
-- can be completed; it is a permanent block.
--
-- Why every package hits it: 87 switched grants_reward off, 88 deliberately
-- switched it back on (the invoice rewards were wanted; only the Legacy
-- qualification entitlements were not), and the column default is now true. A
-- package whose credit reaches the qualifying amount therefore records
-- reward_units >= 1 on every sale, and 191 blocks all of them.
--
-- The guard's INTENT is right. Those units are real: issue_credit_package
-- creates one therapy_entitlements row per unit, which a customer can activate
-- and claim. Refunding the purchase while they stand is a decision someone has
-- to make. What was missing is the way to make it.
--
-- This migration supplies that, and makes the guard evidence-based:
--
--   * the entitlements are found through the deterministic group id the issuer
--     writes, md5('credit_pkg:' || sale id) — not guessed from a name;
--   * unclaimed, unactivated units can be withdrawn, following 71's existing
--     pattern of cancelling pending_activation rows by group;
--   * activated or claimed units are NEVER touched. They are listed, and the
--     person resolving must acknowledge that their history stays;
--   * a sale whose units left no entitlement behind no longer blocks anything.
--
-- Requires 79, 88, 179 and 191. Additive and idempotent.
-- =====================================================================

alter table public.credit_package_sales
  add column if not exists rewards_resolved_at timestamptz,
  add column if not exists rewards_resolved_by uuid references public.profiles(id),
  add column if not exists rewards_resolution jsonb;

-- The link the issuer actually writes. Deterministic, so it is evidence.
create or replace function public.credit_package_reward_group(p_sale_id uuid)
returns uuid language sql immutable as $$
 select md5('credit_pkg:'||p_sale_id::text)::uuid
$$;
grant execute on function public.credit_package_reward_group(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- What this purchase's reward units actually became. Read-only.
--
--   withdrawable  — issued, never activated or claimed; can be taken back
--   consumed      — activated or claimed; stays, and must be acknowledged
--   already_closed— cancelled, expired or refunded already; nothing to do
-- ---------------------------------------------------------------------
create or replace function public.invoice_credit_reward_entitlements(
 p_invoice_id uuid, p_item_id uuid default null)
returns table(sale_id uuid, invoice_item_id uuid, package_name text, reward_units integer,
              entitlement_id uuid, entitlement_no text, status text,
              activation_date date, claimed_at timestamptz, disposition text,
              resolved_at timestamptz)
language sql stable security definer set search_path=public as $$
 select s.id, it.id, s.package_name_snapshot, s.reward_units,
        e.id, e.entitlement_no, e.status, e.activation_date, e.claimed_at,
        case
          when e.id is null then 'none_issued'
          when e.status in ('cancelled','expired','refunded') then 'already_closed'
          when e.status='pending_activation' and e.claimed_at is null then 'withdrawable'
          else 'consumed'
        end,
        s.rewards_resolved_at
   from public.credit_package_sales s
   join public.invoice_items it
     on it.invoice_id=s.invoice_id and it.credit_package_id=s.package_id
   left join public.therapy_entitlements e
     on e.qualification_group_id=public.credit_package_reward_group(s.id)
  where s.invoice_id=p_invoice_id and (p_item_id is null or it.id=p_item_id)
    and public.user_has_store_access(s.store_id)
  order by e.entitlement_no
$$;
grant execute on function public.invoice_credit_reward_entitlements(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Record the decision. Owner or Manager, reason required, replay-safe.
--
-- Withdraws what can be withdrawn and leaves everything else exactly as it is.
-- It issues nothing, refunds nothing and moves no credit: its only job is to
-- make the reward position explicit so the ordinary refund or cancellation can
-- proceed through its own checks.
-- ---------------------------------------------------------------------
create or replace function public.resolve_invoice_credit_rewards(
 p_invoice_id uuid, p_reason text, p_item_id uuid default null,
 p_acknowledge_consumed boolean default false, p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_sale record; v_ent record; i public.invoices%rowtype;
 v_withdrawn integer:=0; v_consumed integer:=0; v_vouchers integer:=0;
 v_detail jsonb:='[]'::jsonb; v_sales integer:=0;
begin
 if not public.is_owner_or_manager() then
  raise exception 'Only an Owner or Manager can resolve qualification rewards' using errcode='42501'; end if;
 if coalesce(btrim(p_reason),'')='' then raise exception 'A reason is required'; end if;

 select * into i from public.invoices where id=p_invoice_id;
 if not found then raise exception 'Invoice not found'; end if;
 if not public.user_has_store_access(i.store_id) then
  raise exception 'No access to this invoice' using errcode='42501'; end if;

 -- The loop variable must not share a name with the table alias: plpgsql
 -- substitutes its own variable into the query and the alias stops resolving.
 -- Distinct and FOR UPDATE cannot be combined, so the line match is an EXISTS
 -- and the row is locked on its own.
 for v_sale in
  select cps.* from public.credit_package_sales cps
  where cps.invoice_id=p_invoice_id
    and (cps.reward_units>0 or coalesce(cps.reward_voucher_qty,0)>0)
    and exists(select 1 from public.invoice_items it
                where it.invoice_id=cps.invoice_id and it.credit_package_id=cps.package_id
                  and (p_item_id is null or it.id=p_item_id))
  for update
 loop
  -- Already resolved: replaying must not withdraw anything a second time.
  if v_sale.rewards_resolved_at is not null then continue; end if;
  v_sales:=v_sales+1;

  -- Anything already activated or claimed is history and is only counted.
  select count(*) into v_consumed from public.therapy_entitlements e
   where e.qualification_group_id=public.credit_package_reward_group(v_sale.id)
     and e.status not in ('cancelled','expired','refunded','pending_activation');
  if v_consumed=0 then
   select count(*) into v_consumed from public.therapy_entitlements e
    where e.qualification_group_id=public.credit_package_reward_group(v_sale.id)
      and e.status='pending_activation' and e.claimed_at is not null;
  end if;
  if v_consumed>0 and not coalesce(p_acknowledge_consumed,false) then
   raise exception 'This purchase has % reward entitlement(s) the customer has already activated or claimed. '
     'Confirm that their history stays before resolving.', v_consumed;
  end if;

  for v_ent in
   select * from public.therapy_entitlements
    where qualification_group_id=public.credit_package_reward_group(v_sale.id)
      and status='pending_activation' and claimed_at is null
    for update
  loop
   -- 71 already cancels pending_activation rows by group; this follows it.
   update public.therapy_entitlements set status='cancelled' where id=v_ent.id;
   v_vouchers:=v_vouchers+coalesce(public.revoke_affiliate_reward_vouchers(v_ent.id),0);
   v_withdrawn:=v_withdrawn+1;
   perform public.write_audit_ex('therapy_entitlements',v_ent.id,'reward_withdrawn_for_invoice_resolution',
     to_jsonb(v_ent), jsonb_build_object('invoice_id',p_invoice_id,'sale_id',v_sale.id,'reason',btrim(p_reason)),
     'therapy',btrim(p_reason),v_sale.store_id);
  end loop;

  v_detail:=v_detail||jsonb_build_array(jsonb_build_object(
    'sale_id',v_sale.id,'package',v_sale.package_name_snapshot,'reward_units',v_sale.reward_units,
    'withdrawn',v_withdrawn,'retained',v_consumed,'voucher_units_returned',v_vouchers));

  update public.credit_package_sales
     set rewards_resolved_at=now(), rewards_resolved_by=auth.uid(),
         rewards_resolution=jsonb_build_object('reason',btrim(p_reason),
           'withdrawn',v_withdrawn,'retained',v_consumed,
           'voucher_units_returned',v_vouchers,'request_id',p_request_id)
   where id=v_sale.id;

  perform public.write_audit_ex('credit_package_sales',v_sale.id,'qualification_rewards_resolved',
    to_jsonb(v_sale), v_detail, 'invoices', btrim(p_reason), v_sale.store_id);
 end loop;

 return jsonb_build_object('success',true,'sales_resolved',v_sales,
   'withdrawn',v_withdrawn,'retained',v_consumed,'voucher_units_returned',v_vouchers,
   'detail',v_detail);
end $$;
grant execute on function public.resolve_invoice_credit_rewards(uuid,text,uuid,boolean,uuid) to authenticated;

-- ---------------------------------------------------------------------
-- The guard, now answerable.
--
-- Replaces 191's definition. The bonus-provenance half is unchanged. The reward
-- half raises only while rewards are UNRESOLVED and entitlements are still
-- standing, and it now says how to clear it.
-- ---------------------------------------------------------------------
create or replace function public.assert_invoice_credit_source_evidence(p_invoice_id uuid,p_item_id uuid default null)
returns void language plpgsql stable security definer set search_path=public as $$
begin
 if exists(select 1 from public.credit_package_sales s join public.invoice_items it on it.invoice_id=s.invoice_id and it.credit_package_id=s.package_id
  where s.invoice_id=p_invoice_id and (p_item_id is null or it.id=p_item_id) and s.bonus_credit_lot_id is null and s.original_sources_verified_at is null) then
  raise exception 'Historical bonus-credit provenance is unresolved. Review the original bonus lot or documented no-bonus decision before allocating, refunding or moving this purchase.';
 end if;
 if exists(select 1 from public.credit_package_sales s
   join public.invoice_items it on it.invoice_id=s.invoice_id and it.credit_package_id=s.package_id
  where s.invoice_id=p_invoice_id and (p_item_id is null or it.id=p_item_id)
    and (s.reward_units>0 or coalesce(s.reward_voucher_qty,0)>0)
    and s.rewards_resolved_at is null
    -- Only while something is actually outstanding. Units that never became an
    -- entitlement, or whose entitlements are already closed, block nothing.
    and exists(select 1 from public.therapy_entitlements e
                where e.qualification_group_id=public.credit_package_reward_group(s.id)
                  and e.status not in ('cancelled','expired','refunded'))) then
  raise exception 'This package granted qualification reward entitlements that are still outstanding. '
    'Review them and record what should happen to them, then refund or cancel — unclaimed ones are withdrawn and claimed ones keep their history.';
 end if;
end $$;
revoke all on function public.assert_invoice_credit_source_evidence(uuid,uuid) from public,anon,authenticated;

-- ---------------------------------------------------------------------
-- Why a premium bundle will not cancel.
--
-- Bundles do NOT hit the reward guard above — it reads credit_package_sales,
-- and a bundle line has no package id. They fail on 179's separate check:
--
--   "Record the original benefit allocations before cancelling an issued
--    credit/bundle invoice"
--
-- That check is correct. What it does not say is WHY the allocations are
-- missing, and the usual answer is specific: capture_invoice_benefit_values
-- refuses to value a reward voucher that has no documented price at the selling
-- store, records a benefit_allocation_review_required audit entry, and writes
-- nothing. Confirmed by reproducing both ways — the same bundle cancels cleanly
-- once its reward voucher has a store price.
--
-- The guard keeps refusing. It now names the cause, so the fix is findable
-- instead of being a dead end.
-- ---------------------------------------------------------------------
create or replace function public.invoice_missing_benefit_reason(p_invoice_id uuid)
returns text language sql stable security definer set search_path=public as $fn$
 select case
   when exists(
     select 1 from public.invoice_items it
      join public.premium_bundle_sales bs on bs.invoice_id=it.invoice_id and bs.bundle_id=it.premium_bundle_id
      join public.customer_reward_vouchers rv on rv.source_id=bs.id
     where it.invoice_id=p_invoice_id
       and not coalesce((public.voucher_price_for(rv.store_id,rv.voucher_id,true)->>'has_price')::boolean,false))
   then ' A reward voucher on this invoice has no recorded price at its store, so its share of the payment could not be valued. Set that voucher store price, then record the allocations.'
   when exists(select 1 from public.audit_logs a
                join public.invoice_items it on it.id=a.record_id
               where it.invoice_id=p_invoice_id and a.action='benefit_allocation_review_required')
   then ' A benefit component on this invoice could not be valued when it was issued; see the benefit_allocation_review_required audit entry for the component.'
   else ' Use the historical benefit review to record what was originally issued.' end
$fn$;
revoke all on function public.invoice_missing_benefit_reason(uuid) from public,anon;
grant execute on function public.invoice_missing_benefit_reason(uuid) to authenticated;

do $do$
declare f text; v_anchor text;
begin
 select pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure) into f;
 if position('invoice_missing_benefit_reason' in f)>0 then
  raise notice 'the cancellation guard already names the missing-benefit cause'; return; end if;
 v_anchor:=$a$raise exception 'Record the original benefit allocations before cancelling an issued credit/bundle invoice'$a$;
 if position(v_anchor in f)=0 then
  raise notice 'Unexpected benefit guard in cancel_invoice_recorded; its message was left as it is.'; return; end if;
 execute replace(f,v_anchor,
  $b$raise exception 'Record the original benefit allocations before cancelling an issued credit/bundle invoice.%', public.invoice_missing_benefit_reason(i.id)$b$);
 raise notice 'the cancellation guard now names why the allocations are missing';
end $do$;

notify pgrst,'reload schema';
commit;
