begin;
-- =====================================================================
-- VOUCHERS A CUSTOMER IS OWED, CLAIMED WHEN THEY ARE READY
--
-- A credit package or premium bundle can carry reward vouchers. Until now the
-- customer had to take all of them at once: the premium bundle issued its
-- whole selection at the till, and claim_legacy_therapy refused anything but
-- the exact full quantity ("Select exactly N voucher(s)"). Someone entitled to
-- twelve who wanted three today had no way to say so.
--
-- What is added here is partial claiming. The entitlement carries the
-- quantity, the deadline and a SNAPSHOT of which vouchers were eligible when
-- the purchase happened, so redefining the package later cannot change what an
-- existing customer may choose from. Each claim is its own event against that
-- entitlement, and the three numbers people actually ask about -- entitled,
-- claimed, remaining -- are derived from the entitlement and its claims rather
-- than being stored and kept in step by hand.
--
-- Every claim produces a Voucher Claim invoice: its own document type, its own
-- reference series, and deliberately NOT a sale. It carries no payment, earns
-- no commission, grants no credit, counts toward no qualification, and does
-- not deduct stock -- the claim itself already did that, and doing it again
-- would take the same voucher out of the store twice.
-- =====================================================================

-- Referenced only inside function bodies below, never in top-level DDL in this
-- same transaction -- the rule migration 61 established for this enum.
do $$ begin
  alter type public.invoice_line_kind add value if not exists 'voucher_claim';
exception when others then null; end $$;

-- ---------------------------------------------------------------------
-- 1. What the entitlement now remembers.
--
-- eligible_voucher_ids is the snapshot. A package's voucher list is editable,
-- and an entitlement outlives the edit; without this, a customer who bought in
-- January could be offered -- or refused -- a different set in June.
-- ---------------------------------------------------------------------
alter table public.therapy_entitlements
  add column if not exists eligible_voucher_ids uuid[],
  add column if not exists claim_source_type text,
  add column if not exists claim_source_invoice_id uuid references public.invoices(id),
  add column if not exists revoked_qty integer not null default 0,
  add column if not exists revoked_at timestamptz,
  add column if not exists revoked_reason text;

comment on column public.therapy_entitlements.eligible_voucher_ids is
  'Which vouchers this entitlement may be claimed as, frozen at purchase.';
comment on column public.therapy_entitlements.revoked_qty is
  'Unclaimed units withdrawn by a refund or cancellation.';

-- ---------------------------------------------------------------------
-- 2. The claim events themselves.
--
-- Claimed quantity is not a column on the entitlement: it is the sum of these
-- rows. One place to write, one place to read, and no chance of the two
-- disagreeing after a failed partial update.
-- ---------------------------------------------------------------------
create table if not exists public.voucher_claims (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null references public.therapy_entitlements(id) on delete cascade,
  invoice_id uuid references public.invoices(id),
  customer_id uuid not null references public.customers(id),
  store_id uuid not null references public.stores(id),
  quantity integer not null check (quantity > 0),
  selections jsonb not null,
  claimed_by uuid references public.profiles(id),
  claimed_at timestamptz not null default now(),
  note text
);
create index if not exists voucher_claims_entitlement_idx on public.voucher_claims(entitlement_id);
create index if not exists voucher_claims_invoice_idx on public.voucher_claims(invoice_id);

-- ---------------------------------------------------------------------
-- 3. The Voucher Claim document type.
-- ---------------------------------------------------------------------
alter table public.invoices
  add column if not exists is_voucher_claim boolean not null default false,
  add column if not exists voucher_claim_entitlement_id uuid references public.therapy_entitlements(id);

create index if not exists invoices_voucher_claim_idx on public.invoices(voucher_claim_entitlement_id)
  where is_voucher_claim;

-- Its own reference series, shaped like the exchange series so the document
-- type is legible from the number alone.
create or replace function public.next_voucher_claim_invoice_no(p_store_id uuid)
returns text language plpgsql security definer set search_path to 'public' as $$
declare v_cc text; v_sc text; v_year text := to_char(now() at time zone 'Asia/Singapore','YYYY');
        v_prefix text; v_count integer; v_next text;
begin
  select upper(trim(country_code)), upper(trim(code)) into v_cc, v_sc
    from public.stores where id = p_store_id;
  if coalesce(v_cc,'') = '' then raise exception 'Store has no country code — set it before claiming vouchers'; end if;
  if coalesce(v_sc,'') = '' then raise exception 'Store has no store code — set it before claiming vouchers'; end if;
  v_prefix := v_cc||'-'||v_sc||'-VC-INV-'||v_year||'-';
  select count(*) into v_count from public.invoices
   where store_id = p_store_id and is_voucher_claim and invoice_no like v_prefix||'%';
  v_next := v_prefix||lpad((v_count+1)::text,5,'0');
  while exists (select 1 from public.invoices where invoice_no = v_next) loop
    v_count := v_count + 1;
    v_next := v_prefix||lpad((v_count+1)::text,5,'0');
  end loop;
  return v_next;
end $$;
grant execute on function public.next_voucher_claim_invoice_no(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Entitled, claimed, remaining.
--
-- The question every counter conversation starts with. Derived, never stored.
-- ---------------------------------------------------------------------
create or replace function public.entitlement_voucher_state(p_entitlement_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare e public.therapy_entitlements%rowtype; v_claimed integer; v_elig jsonb;
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
  if not found then raise exception 'Entitlement not found'; end if;
  if e.store_id is not null and not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;

  select coalesce(sum(quantity),0) into v_claimed
    from public.voucher_claims where entitlement_id = p_entitlement_id;

  -- The eligible list as it was at purchase. Names are read live so a renamed
  -- voucher still reads correctly; the SET of choices is what is frozen.
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
    'remaining', greatest(coalesce(e.voucher_qty,0) - v_claimed - coalesce(e.revoked_qty,0), 0),
    'claim_deadline', e.activation_deadline,
    'deadline_passed', e.activation_deadline is not null and public.sg_today() > e.activation_deadline,
    'status', e.status,
    'source', e.claim_source_type,
    'source_invoice_id', e.claim_source_invoice_id,
    'eligible', v_elig,
    'snapshot_present', e.eligible_voucher_ids is not null);
end $$;
grant execute on function public.entitlement_voucher_state(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 5. Claiming some of them.
--
-- The quantity rule is "at least one, never more than remaining" rather than
-- the old "exactly the whole entitlement". Everything else the old path
-- enforced still holds: the voucher must be one of the snapshotted choices,
-- must still be giveable as a reward, and must be in stock at this store.
--
-- Stock is taken HERE, once. The Voucher Claim invoice this writes is a
-- document, not a sale, and no issuer runs over it.
-- ---------------------------------------------------------------------
create or replace function public.claim_entitlement_vouchers(
  p_entitlement_id uuid, p_selections jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  e public.therapy_entitlements%rowtype;
  v_claimed integer; v_remaining integer; v_sum integer := 0;
  v_sel jsonb; v_vid uuid; v_q integer; v_stock integer;
  v_inv uuid; v_no text; v_claim uuid; v_issued jsonb := '[]'::jsonb;
begin
  -- for update: two tabs, or a retried request, must not both claim the last one.
  select * into e from public.therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Entitlement not found'; end if;
  if e.store_id is not null and not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;
  if coalesce(e.entitlement_kind,'') <> 'voucher' then
    raise exception 'This entitlement is not a voucher reward'; end if;
  if e.status = 'cancelled' then raise exception 'This entitlement has been cancelled'; end if;
  if e.activation_deadline is not null and public.sg_today() > e.activation_deadline then
    raise exception 'The claim deadline (%) has passed', e.activation_deadline; end if;

  select coalesce(sum(quantity),0) into v_claimed
    from public.voucher_claims where entitlement_id = p_entitlement_id;
  v_remaining := coalesce(e.voucher_qty,0) - v_claimed - coalesce(e.revoked_qty,0);
  if v_remaining <= 0 then raise exception 'Nothing left to claim on this entitlement'; end if;

  if p_selections is null or jsonb_array_length(p_selections) = 0 then
    raise exception 'Choose at least one voucher to claim'; end if;
  for v_sel in select * from jsonb_array_elements(p_selections) loop
    v_sum := v_sum + coalesce((v_sel->>'quantity')::integer,0);
  end loop;
  if v_sum <= 0 then raise exception 'Choose at least one voucher to claim'; end if;
  if v_sum > v_remaining then
    raise exception 'Only % left to claim on this entitlement; % chosen', v_remaining, v_sum; end if;

  -- The document. No payment, no items, no totals: this records a hand-over of
  -- something already paid for.
  v_no := public.next_voucher_claim_invoice_no(e.store_id);
  insert into public.invoices (invoice_no, store_id, customer_id, created_by, status,
                               subtotal, discount_total, total_amount, paid_amount,
                               is_voucher_claim, voucher_claim_entitlement_id, notes)
  values (v_no, e.store_id, e.customer_id, auth.uid(), 'paid',
          0, 0, 0, 0, true, e.id,
          'Voucher claim against ' || coalesce(e.entitlement_no,'entitlement'))
  returning id into v_inv;

  insert into public.voucher_claims (entitlement_id, invoice_id, customer_id, store_id,
                                     quantity, selections, claimed_by, note)
  values (p_entitlement_id, v_inv, e.customer_id, e.store_id, v_sum, p_selections, auth.uid(), p_note)
  returning id into v_claim;

  for v_sel in select * from jsonb_array_elements(p_selections) loop
    v_vid := (v_sel->>'voucher_id')::uuid;
    v_q   := coalesce((v_sel->>'quantity')::integer,0);
    if v_q <= 0 then continue; end if;

    -- Only from what this entitlement was sold with.
    if e.eligible_voucher_ids is not null
       and not (v_vid = any(e.eligible_voucher_ids)) then
      raise exception 'That voucher was not one of the choices for this entitlement'; end if;
    if not exists (select 1 from public.vouchers v
                    where v.id = v_vid and v.is_active and v.deleted_at is null
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

    insert into public.customer_reward_vouchers
      (customer_id, voucher_id, entitlement_id, store_id, quantity, issued_by, notes,
       source_type, source_id)
    values (e.customer_id, v_vid, e.id, e.store_id, v_q, auth.uid(),
            'Claimed on ' || v_no, 'voucher_claim', v_claim);

    v_issued := v_issued || jsonb_build_object('voucher_id', v_vid, 'quantity', v_q,
      'name', (select name from public.vouchers where id = v_vid));
  end loop;

  -- Claimed in full, or still owed some.
  update public.therapy_entitlements
     set status = case when v_claimed + v_sum >= coalesce(voucher_qty,0) - coalesce(revoked_qty,0)
                       then 'active' else 'pending_activation' end,
         claimed_by = auth.uid(), claimed_at = now(),
         activation_date = coalesce(activation_date, public.sg_today())
   where id = p_entitlement_id;

  perform public.write_audit_ex('voucher_claims', v_claim, 'vouchers_claimed',
    jsonb_build_object('claimed_before', v_claimed, 'remaining_before', v_remaining),
    jsonb_build_object('quantity', v_sum, 'invoice_no', v_no, 'issued', v_issued),
    'therapy', p_note, e.store_id);

  return jsonb_build_object('success', true, 'claim_id', v_claim,
    'invoice_id', v_inv, 'invoice_no', v_no, 'claimed_now', v_sum,
    'issued', v_issued, 'state', public.entitlement_voucher_state(p_entitlement_id));
end $$;
grant execute on function public.claim_entitlement_vouchers(uuid,jsonb,text) to authenticated;


-- ---------------------------------------------------------------------
-- 6. A refund or cancellation withdraws what was not claimed.
--
-- What the customer already took is theirs and is dealt with by the refund
-- engine's existing benefit handling. What they never claimed was never handed
-- over, so it simply stops being claimable.
--
-- Driven by the invoice's own status rather than patched into the refund and
-- cancellation engines: those are long, correct, and have enough to do. A
-- trigger also means a refund reached by any route revokes, and revoking twice
-- is harmless.
-- ---------------------------------------------------------------------
create or replace function public.revoke_unclaimed_entitlement_vouchers(
  p_invoice_id uuid, p_reason text)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare e record; v_claimed integer; v_remaining integer; v_total integer := 0;
begin
  for e in select * from public.therapy_entitlements
            where claim_source_invoice_id = p_invoice_id
              and coalesce(entitlement_kind,'') = 'voucher'
            for update
  loop
    select coalesce(sum(quantity),0) into v_claimed
      from public.voucher_claims where entitlement_id = e.id;
    v_remaining := coalesce(e.voucher_qty,0) - v_claimed - coalesce(e.revoked_qty,0);
    if v_remaining <= 0 then continue; end if;

    update public.therapy_entitlements
       set revoked_qty = coalesce(revoked_qty,0) + v_remaining,
           revoked_at = now(),
           revoked_reason = p_reason,
           -- Nothing claimed at all: the entitlement is simply gone. Partly
           -- claimed: it stays, closed, because those vouchers still exist.
           status = case when v_claimed = 0 then 'cancelled' else 'active' end
     where id = e.id;

    v_total := v_total + v_remaining;
    perform public.write_audit_ex('therapy_entitlements', e.id, 'unclaimed_vouchers_revoked',
      jsonb_build_object('entitled', e.voucher_qty, 'claimed', v_claimed),
      jsonb_build_object('revoked', v_remaining, 'reason', p_reason),
      'therapy', p_reason, e.store_id);
  end loop;
  return v_total;
end $$;
grant execute on function public.revoke_unclaimed_entitlement_vouchers(uuid,text) to authenticated;

create or replace function public.trg_revoke_unclaimed_on_close()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.status::text in ('refunded','cancelled')
     and coalesce(old.status::text,'') is distinct from new.status::text then
    perform public.revoke_unclaimed_entitlement_vouchers(new.id,
      'Purchase ' || new.status::text);
  end if;
  return new;
end $$;

drop trigger if exists revoke_unclaimed_on_close on public.invoices;
create trigger revoke_unclaimed_on_close
  after update of status on public.invoices
  for each row execute function public.trg_revoke_unclaimed_on_close();


-- ---------------------------------------------------------------------
-- 7. The purchase records what may be chosen, and from which invoice.
--
-- Patched in place by content rather than restated: these issuers are long and
-- their credit, commission and qualification handling is correct.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.issue_credit_package_invoice_item(uuid)'::regprocedure) into f;
  if position('claim_source_invoice_id' in f) = 0 then
    f := replace(f,
      '      created_by, qualification_group_id, earner_kind)',
      '      created_by, qualification_group_id, earner_kind,'||chr(10)||
      '      eligible_voucher_ids, claim_source_type, claim_source_invoice_id)');
    f := replace(f,
      $q$      'pending_activation', auth.uid(), md5('credit_pkg_item:' || v_it.id::text)::uuid, 'credit_package')$q$,
      $q$      'pending_activation', auth.uid(), md5('credit_pkg_item:' || v_it.id::text)::uuid, 'credit_package',$q$||chr(10)||
      $q$      v_vouchers, 'credit_package', v_inv.id)$q$);
    if position('claim_source_invoice_id' in f) = 0 then
      raise exception 'issue_credit_package_invoice_item does not match what 310 expects — align it by hand'; end if;
    execute f;
    raise notice 'issue_credit_package_invoice_item now snapshots the eligible vouchers';
  end if;
end $do$;

do $do$
declare f text; v_vouchers_decl text;
begin
  select pg_get_functiondef('public.issue_credit_package(uuid,uuid,uuid,numeric,uuid)'::regprocedure) into f;
  if position('claim_source_invoice_id' in f) = 0 then
    f := replace(f,
      '        created_by, qualification_group_id, earner_kind)',
      '        created_by, qualification_group_id, earner_kind,'||chr(10)||
      '        eligible_voucher_ids, claim_source_type, claim_source_invoice_id)');
    f := replace(f,
      $q$        'pending_activation', auth.uid(), v_group, 'credit_package');$q$,
      $q$        'pending_activation', auth.uid(), v_group, 'credit_package',$q$||chr(10)||
      $q$        v_vouchers, 'credit_package', p_invoice_id);$q$);
    if position('claim_source_invoice_id' in f) = 0 then
      raise exception 'issue_credit_package does not match what 310 expects — align it by hand'; end if;
    execute f;
    raise notice 'issue_credit_package now snapshots the eligible vouchers';
  end if;
end $do$;

-- A premium bundle issued whatever was chosen at the till and quietly dropped
-- the rest. What is not chosen now becomes an entitlement to claim later.
do $do$
declare f text;
begin
  select pg_get_functiondef('public.issue_premium_bundle_invoice_item(uuid)'::regprocedure) into f;
  if position('bundle_deferred_entitlement' in f) = 0 then
    f := replace(f,
      '  update public.premium_bundle_sales set vouchers_issued = v_issued where id = v_sale;',
      '  update public.premium_bundle_sales set vouchers_issued = v_issued where id = v_sale;'||chr(10)||chr(10)||
      '  -- bundle_deferred_entitlement: whatever was not chosen at the till is'||chr(10)||
      '  -- still owed, and is claimable until the deadline.'||chr(10)||
      '  if coalesce(v_vq,0) - v_issued > 0 then'||chr(10)||
      '    insert into public.therapy_entitlements ('||chr(10)||
      '      entitlement_no, customer_id, store_id, rule_id, package_name,'||chr(10)||
      '      entitlement_kind, duration_months, voucher_qty, qualifying_amount,'||chr(10)||
      '      qualified_value, forfeited_value, activation_deadline, status,'||chr(10)||
      '      created_by, qualification_group_id, earner_kind,'||chr(10)||
      '      eligible_voucher_ids, claim_source_type, claim_source_invoice_id)'||chr(10)||
      '    values (public.next_legacy_entitlement_no(), v_inv.customer_id, v_inv.store_id, null,'||chr(10)||
      '      ''Premium bundle reward — '' || b.name,'||chr(10)||
      '      ''voucher'', 1, coalesce(v_vq,0) - v_issued, coalesce(v_qual,0),'||chr(10)||
      '      coalesce(v_it.unit_price,0), 0,'||chr(10)||
      '      public.sg_today() + coalesce((select activation_deadline_days from public.therapy_package_rules'||chr(10)||
      '                                     where activation_deadline_days is not null'||chr(10)||
      '                                     order by activation_deadline_days limit 1), 365),'||chr(10)||
      '      ''pending_activation'', auth.uid(),'||chr(10)||
      '      md5(''bundle_item:'' || v_it.id::text)::uuid, ''premium_bundle'','||chr(10)||
      '      v_vouchers, ''premium_bundle'', v_inv.id);'||chr(10)||
      '  end if;');
    if position('bundle_deferred_entitlement' in f) = 0 then
      raise exception 'issue_premium_bundle_invoice_item does not match what 310 expects — align it by hand'; end if;
    execute f;
    raise notice 'issue_premium_bundle_invoice_item now defers what was not chosen';
  end if;
end $do$;


-- ---------------------------------------------------------------------
-- 8. What the purchases made before all this look like now. Read only.
--
-- Entitlements that predate the snapshot have no eligible list, so a claim
-- against them cannot be checked against what was sold. Rather than guess,
-- this reports them and says what could be adopted -- the source package's
-- current voucher list -- leaving the decision to a person. It writes nothing.
-- ---------------------------------------------------------------------
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
           coalesce((select sum(vc.quantity) from public.voucher_claims vc
                      where vc.entitlement_id = e.id), 0)::integer as claimed,
           e.activation_deadline, e.status, e.eligible_voucher_ids,
           e.earner_kind, e.claim_source_type
      from public.therapy_entitlements e
      join public.customers c on c.id = e.customer_id
     where coalesce(e.entitlement_kind,'') = 'voucher'
       and (p_store_id is null or e.store_id = p_store_id)
       and public.user_has_store_access(e.store_id)
  )
  select b.id, b.entitlement_no, b.customer_name, b.store_id, b.package_name,
         b.entitled, b.claimed,
         greatest(b.entitled - b.claimed, 0)::integer as remaining,
         b.activation_deadline,
         b.activation_deadline is not null and public.sg_today() > b.activation_deadline,
         b.status,
         b.eligible_voucher_ids is not null as has_snapshot,
         case
           when b.eligible_voucher_ids is not null then 'ready'
           when b.entitled - b.claimed <= 0 then 'nothing_outstanding'
           when b.activation_deadline is not null and public.sg_today() > b.activation_deadline
                then 'expired_unclaimed'
           else 'needs_eligible_list'
         end as classification,
         case when b.eligible_voucher_ids is null then (
           select coalesce(array_agg(cpv.voucher_id), '{}')
             from public.credit_package_sales s
             join public.credit_package_vouchers cpv on cpv.package_id = s.package_id
            where s.customer_id = (select customer_id from public.therapy_entitlements where id = b.id)
              and b.earner_kind = 'credit_package')
         end as suggested_eligible
    from base b
   order by b.activation_deadline nulls last, b.entitlement_no
$$;
grant execute on function public.voucher_claim_reconciliation(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 9. Everything a customer is still owed, for the counter.
-- ---------------------------------------------------------------------
create or replace function public.customer_outstanding_voucher_claims(p_customer_id uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(public.entitlement_voucher_state(e.id)
                            order by e.activation_deadline nulls last), '[]'::jsonb)
    from public.therapy_entitlements e
   where e.customer_id = p_customer_id
     and coalesce(e.entitlement_kind,'') = 'voucher'
     and e.status <> 'cancelled'
     and public.user_has_store_access(e.store_id)
     and coalesce(e.voucher_qty,0)
         - coalesce((select sum(vc.quantity) from public.voucher_claims vc where vc.entitlement_id = e.id),0)
         - coalesce(e.revoked_qty,0) > 0
$$;
grant execute on function public.customer_outstanding_voucher_claims(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 10. Access. Claims are readable where the store is, and only writable
--     through claim_entitlement_vouchers().
-- ---------------------------------------------------------------------
alter table public.voucher_claims enable row level security;
do $$ begin
  create policy "read voucher claims" on public.voucher_claims
    for select to authenticated using (public.user_has_store_access(store_id));
exception when duplicate_object then null; end $$;
grant select on public.voucher_claims to authenticated;

notify pgrst,'reload schema';
commit;
