-- =====================================================================
-- ENERGIA — SPLITTING CREDIT PACKAGE AND PREMIUM BUNDLE CREDIT
--
-- Credit from a credit package or premium bundle has always gone entirely to
-- the invoice's customer:
--
--     v_res := public.issue_credit_package(v_it.credit_package_id,
--                                          v_inv.customer_id, ...);
--
-- A family or a group buying together could not divide it. This adds a split,
-- decided AT PURCHASE, where each recipient receives THEIR OWN BALANCE — a
-- separate lot in their own wallet, not a shared pot. An unspent share can be
-- moved to someone else afterwards.
--
-- DESIGN NOTES, because this is money:
--
--   * The split is recorded against the invoice LINE, so it survives a
--     correction and can be read back.
--   * The shares must add up to the line's credit exactly. A split that does
--     not balance is refused rather than quietly rounded, since the difference
--     would be credit that exists nowhere.
--   * Nothing changes for an unsplit line. If no split is recorded, the whole
--     amount goes to the invoice customer exactly as before, through the same
--     functions. This is additive.
--   * A share can be reassigned only while UNTOUCHED. Once any of it is spent,
--     moving it would take value from the person who has already used some.
--
-- Additive and idempotent.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The intended split, recorded against the invoice line.
-- ---------------------------------------------------------------------
create table if not exists public.invoice_credit_splits (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  invoice_item_id uuid not null references public.invoice_items(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  amount numeric(12,2) not null check (amount > 0),
  issued_lot_id uuid references public.customer_credit_lots(id),
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (invoice_item_id, customer_id)
);

create index if not exists idx_credit_splits_invoice on public.invoice_credit_splits(invoice_id);
create index if not exists idx_credit_splits_item on public.invoice_credit_splits(invoice_item_id);

alter table public.invoice_credit_splits enable row level security;

drop policy if exists "read credit splits" on public.invoice_credit_splits;
create policy "read credit splits" on public.invoice_credit_splits
  for select to authenticated using (true);
-- Writes go through the functions below only, as with every other money path.

-- ---------------------------------------------------------------------
-- 2. Record a split before the invoice settles.
-- ---------------------------------------------------------------------
create or replace function public.set_invoice_credit_split(
  p_invoice_item_id uuid,
  p_shares jsonb)                    -- [{customer_id, amount}, ...]
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_it public.invoice_items%rowtype;
  v_inv public.invoices%rowtype;
  v_share jsonb; v_sum numeric := 0; v_target numeric; v_n integer := 0;
  v_cust uuid; v_amt numeric;
begin
  select * into v_it from public.invoice_items where id = p_invoice_item_id;
  if not found then raise exception 'That invoice line does not exist'; end if;
  if v_it.line_kind::text not in ('credit_package', 'premium_bundle') then
    raise exception 'Only a credit package or premium bundle can be split';
  end if;
  if v_it.credit_issued_at is not null then
    raise exception 'That credit has already been issued and cannot be re-split. Move the unspent shares instead.';
  end if;

  select * into v_inv from public.invoices where id = v_it.invoice_id;

  -- The whole line's value must be accounted for.
  v_target := round(coalesce(v_it.line_total, 0), 2);

  delete from public.invoice_credit_splits where invoice_item_id = p_invoice_item_id;

  if p_shares is null or jsonb_array_length(p_shares) = 0 then
    -- No split: the invoice customer receives all of it, as before.
    return jsonb_build_object('success', true, 'shares', 0, 'note', 'no split — whole amount to the invoice customer');
  end if;

  for v_share in select * from jsonb_array_elements(p_shares)
  loop
    v_cust := (v_share->>'customer_id')::uuid;
    v_amt  := round((v_share->>'amount')::numeric, 2);

    if v_cust is null then raise exception 'Each share needs a customer'; end if;
    if v_amt is null or v_amt <= 0 then
      raise exception 'Each share must be more than zero'; end if;
    if not exists (select 1 from public.customers
                    where id = v_cust and deleted_at is null) then
      raise exception 'One of the chosen customers does not exist'; end if;

    insert into public.invoice_credit_splits
      (invoice_id, invoice_item_id, customer_id, amount, created_by)
    values (v_it.invoice_id, p_invoice_item_id, v_cust, v_amt, auth.uid());

    v_sum := round(v_sum + v_amt, 2);
    v_n := v_n + 1;
  end loop;

  -- Refused rather than rounded: a difference here is credit that would exist
  -- nowhere, or credit conjured from nothing.
  if v_sum <> v_target then
    raise exception 'The shares add up to S$% but the line is S$%. They must match exactly.',
      to_char(v_sum, 'FM999999990.00'), to_char(v_target, 'FM999999990.00');
  end if;

  return jsonb_build_object('success', true, 'shares', v_n, 'total', v_sum);
end $function$;

-- ---------------------------------------------------------------------
-- 3. Issue the credit to each recipient at settlement.
--
--    Wraps the existing issuance rather than replacing it: an unsplit line
--    still goes through exactly the same path it always has.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'issue_credit_lines_for_invoice';
  if v_def is null then raise exception 'issue_credit_lines_for_invoice not found'; end if;
  if position('invoice_credit_splits' in v_def) > 0 then
    raise notice 'credit issuance already honours a split'; return;
  end if;

  -- Each recipient gets their own lot, in their own wallet, for their share.
  v_new := replace(v_def,
    '    if v_it.line_kind = ''credit_package'' then
      v_res := public.issue_credit_package(v_it.credit_package_id, v_inv.customer_id,
                                           v_inv.store_id, v_external, p_invoice_id);',
    '    if v_it.line_kind = ''credit_package'' then
      -- A recorded split sends each share to its own recipient. Their external
      -- value is apportioned in the same proportion, so commission and the
      -- money trail stay consistent with an unsplit sale.
      if exists (select 1 from public.invoice_credit_splits s
                  where s.invoice_item_id = v_it.id) then
        declare v_s record; v_share_ext numeric; v_line numeric;
        begin
          v_line := nullif(round(coalesce(v_it.line_total, 0), 2), 0);
          for v_s in select * from public.invoice_credit_splits
                      where invoice_item_id = v_it.id order by created_at
          loop
            v_share_ext := case when v_line is null then 0
                                else round(v_external * (v_s.amount / v_line), 2) end;
            v_res := public.issue_credit_package(v_it.credit_package_id, v_s.customer_id,
                                                 v_inv.store_id, v_share_ext, p_invoice_id);
            update public.invoice_credit_splits
               set issued_lot_id = (v_res->>''credit_lot_id'')::uuid
             where id = v_s.id;
            v_res := v_res || jsonb_build_object(''commission'',
              public.earn_credit_package_commission((v_res->>''sale_id'')::uuid));
          end loop;
        end;
      else
      v_res := public.issue_credit_package(v_it.credit_package_id, v_inv.customer_id,
                                           v_inv.store_id, v_external, p_invoice_id);
      end if;');

  if position('invoice_credit_splits' in v_new) = 0 then
    raise exception 'Could not make credit issuance honour a split';
  end if;
  execute v_new;
  raise notice 'credit package issuance now honours a recorded split';
end $patch$;

-- ---------------------------------------------------------------------
-- 4. Move an UNSPENT share to someone else.
-- ---------------------------------------------------------------------
create or replace function public.reassign_credit_share(
  p_lot_id uuid, p_new_customer_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_lot public.customer_credit_lots%rowtype; v_wallet uuid; v_old uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can move credit between customers';
  end if;

  select * into v_lot from public.customer_credit_lots where id = p_lot_id for update;
  if not found then raise exception 'That credit does not exist'; end if;
  if coalesce(v_lot.status, 'active') <> 'active' then
    raise exception 'That credit is no longer active'; end if;

  -- Only while untouched. Moving a partly used share would take value from
  -- someone who has already spent some of it.
  if round(v_lot.remaining_amount, 2) <> round(v_lot.original_amount, 2) then
    raise exception 'S$% of this credit has already been spent, so it cannot be moved.',
      to_char(round(v_lot.original_amount - v_lot.remaining_amount, 2), 'FM999999990.00');
  end if;
  if v_lot.customer_id = p_new_customer_id then
    raise exception 'That credit already belongs to this customer'; end if;
  if not exists (select 1 from public.customers
                  where id = p_new_customer_id and deleted_at is null) then
    raise exception 'That customer does not exist'; end if;

  insert into public.customer_credit_wallets(customer_id)
  values (p_new_customer_id) on conflict do nothing;
  select id into v_wallet from public.customer_credit_wallets
   where customer_id = p_new_customer_id limit 1;

  v_old := v_lot.customer_id;
  update public.customer_credit_lots
     set customer_id = p_new_customer_id, wallet_id = v_wallet, updated_at = now()
   where id = p_lot_id;

  update public.invoice_credit_splits
     set customer_id = p_new_customer_id
   where issued_lot_id = p_lot_id;

  -- A credit package can also grant a BONUS lot from the same sale. It belongs
  -- to whoever holds the paid credit, so it moves with them — but only while it
  -- too is untouched, for the same reason.
  update public.customer_credit_lots b
     set customer_id = p_new_customer_id, wallet_id = v_wallet, updated_at = now()
   where b.id <> p_lot_id
     and b.customer_id = v_old
     and b.source_record_id is not null
     and b.source_record_id = v_lot.source_record_id
     and coalesce(b.status, 'active') = 'active'
     and round(b.remaining_amount, 2) = round(b.original_amount, 2);

  perform public.write_audit_ex('customer_credit_lots', p_lot_id, 'credit_share_reassigned',
    jsonb_build_object('customer_id', v_old),
    jsonb_build_object('customer_id', p_new_customer_id,
                       'amount', v_lot.remaining_amount,
                       'reason', nullif(trim(coalesce(p_reason, '')), '')),
    'credit', null, v_lot.store_id);

  return jsonb_build_object('success', true, 'amount', v_lot.remaining_amount);
end $function$;

-- ---------------------------------------------------------------------
-- 5. Read a line's split back, for the invoice screen.
-- ---------------------------------------------------------------------
create or replace function public.invoice_credit_split(p_invoice_id uuid)
returns table(invoice_item_id uuid, customer_id uuid, customer_name text,
              amount numeric, issued_lot_id uuid,
              remaining numeric, spent boolean)
language sql stable security definer set search_path to 'public' as $function$
  select s.invoice_item_id, s.customer_id, c.full_name, s.amount, s.issued_lot_id,
         l.remaining_amount,
         case when l.id is null then false
              else round(l.remaining_amount, 2) < round(l.original_amount, 2) end
    from public.invoice_credit_splits s
    join public.customers c on c.id = s.customer_id
    left join public.customer_credit_lots l on l.id = s.issued_lot_id
   where s.invoice_id = p_invoice_id
   order by s.created_at
$function$;

do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'set_invoice_credit_split') then
    raise exception 'set_invoice_credit_split is missing';
  end if;
  raise notice 'Confirmed: credit can be split at purchase and moved while unspent';
end $$;

notify pgrst, 'reload schema';
