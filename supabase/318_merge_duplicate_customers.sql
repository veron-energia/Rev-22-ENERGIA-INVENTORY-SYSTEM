begin;
-- =====================================================================
-- MERGING TWO RECORDS OF THE SAME PERSON
--
-- A duplicate customer is not a row to delete. Forty-four tables reference
-- customers, including credit, vouchers, therapy, commissions on both sides of
-- a referral, and customers.referred_by pointing at itself. Everything the
-- duplicate owns has to move to the surviving record before the duplicate can
-- be retired, and two of those references cannot simply be repointed:
--
--   * customer_credit_wallets.customer_id is UNIQUE. If both records have a
--     wallet, the lots and ledger move into the survivor's wallet and the
--     duplicate's empty wallet is retired -- balances are carried, never
--     recreated.
--   * customer_affiliates.customer_id is UNIQUE. If BOTH are affiliates the
--     merge is refused, because which referral code and which payout history
--     survives is a decision about real money that belongs to a person, not
--     to a script.
--
-- The duplicate is soft-deleted, never hard-deleted: it is the evidence that
-- the older records were always this person.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. What a merge would do. Read-only.
-- ---------------------------------------------------------------------
create or replace function public.preview_customer_merge(p_keep uuid, p_merge uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare k public.customers%rowtype; m public.customers%rowtype;
        v_counts jsonb := '{}'::jsonb; v_blocks jsonb := '[]'::jsonb; n bigint;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can review a customer merge' using errcode='42501'; end if;
  if p_keep = p_merge then raise exception 'Those are the same record'; end if;
  select * into k from public.customers where id = p_keep;
  if not found then raise exception 'The record to keep was not found'; end if;
  select * into m from public.customers where id = p_merge;
  if not found then raise exception 'The duplicate record was not found'; end if;

  -- What the duplicate actually holds.
  select jsonb_build_object(
    'invoices',        (select count(*) from public.invoices where customer_id = p_merge and deleted_at is null),
    'credit_lots',     (select count(*) from public.customer_credit_lots where customer_id = p_merge),
    'credit_remaining',(select coalesce(sum(remaining_amount),0) from public.customer_credit_lots
                         where customer_id = p_merge and status = 'active'),
    'vouchers',        (select coalesce(sum(quantity),0) from public.customer_reward_vouchers
                         where customer_id = p_merge and status = 'held'),
    'therapy_units',   (select count(*) from public.purchased_therapy_entitlements where customer_id = p_merge),
    'entitlements',    (select count(*) from public.therapy_entitlements where customer_id = p_merge),
    'sessions',        (select count(*) from public.customer_therapy_sessions where customer_id = p_merge),
    'commissions_as_buyer',   (select count(*) from public.commissions where buyer_customer_id = p_merge),
    'commissions_as_referrer',(select count(*) from public.commissions where referrer_customer_id = p_merge),
    'referred_customers',     (select count(*) from public.customers where referred_by = p_merge and deleted_at is null),
    'surveys',         (select count(*) from public.health_surveys where customer_id = p_merge))
  into v_counts;

  -- Things a script must not decide.
  if m.deleted_at is not null then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','duplicate_already_deleted',
      'detail','The duplicate is already deleted; nothing would move.')); end if;
  if k.deleted_at is not null then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','keeper_deleted',
      'detail','The record to keep is deleted. Restore it first.')); end if;

  if exists (select 1 from public.customer_affiliates where customer_id = p_keep and deleted_at is null)
     and exists (select 1 from public.customer_affiliates where customer_id = p_merge and deleted_at is null) then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','two_affiliate_records',
      'detail','Both records are affiliates. Which referral code and payout history survives is a decision about real money — resolve the affiliate records first, then merge.')); end if;

  -- A referral between the two would become a person referring themselves.
  select count(*) into n from public.commissions
   where (buyer_customer_id = p_keep and referrer_customer_id = p_merge)
      or (buyer_customer_id = p_merge and referrer_customer_id = p_keep);
  if n > 0 then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','commission_between_the_two',
      'detail', n || ' commission row(s) have one of these records as buyer and the other as referrer. Merging would make the person their own referrer. Review those rows first.')); end if;

  return jsonb_build_object(
    'keep', jsonb_build_object('id',k.id,'name',k.full_name,'phone',k.phone,'email',k.email,
                               'created_at',k.created_at,'referred_by',k.referred_by),
    'merge', jsonb_build_object('id',m.id,'name',m.full_name,'phone',m.phone,'email',m.email,
                                'created_at',m.created_at,'referred_by',m.referred_by),
    'moving', v_counts,
    'wallets', jsonb_build_object(
      'keep_has',  exists(select 1 from public.customer_credit_wallets where customer_id = p_keep),
      'merge_has', exists(select 1 from public.customer_credit_wallets where customer_id = p_merge)),
    'blocking', v_blocks,
    'can_merge', jsonb_array_length(v_blocks) = 0);
end $$;
grant execute on function public.preview_customer_merge(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Doing it.
--
-- Every reference is repointed generically, from the catalogue rather than from
-- a hand-written list, so a table added later is carried too and cannot be
-- forgotten. The three references that need judgement are handled first and
-- excluded from the sweep.
-- ---------------------------------------------------------------------
create or replace function public.merge_customer_records(
  p_keep uuid, p_merge uuid, p_reason text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_preview jsonb; k public.customers%rowtype; m public.customers%rowtype;
        r record; r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
        v_moved jsonb := '{}'::jsonb; n bigint; v_keep_wallet uuid;
        v_sql text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can merge customer records' using errcode='42501'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Give a reason; it is kept with the merge'; end if;
  if p_request_id is null then raise exception 'A request id is required'; end if;

  -- A retry returns the original outcome instead of merging a second time.
  if exists (select 1 from public.audit_logs
              where action = 'customers_merged'
                and record_id = p_keep
                and new_data->>'request_id' = p_request_id::text) then
    return jsonb_build_object('success', true, 'replayed', true,
      'detail','This merge was already applied.'); end if;

  -- Lock both, keeper first, so two merges cannot interleave.
  select * into k from public.customers where id = least(p_keep,p_merge) for update;
  select * into m from public.customers where id = greatest(p_keep,p_merge) for update;
  select * into k from public.customers where id = p_keep;
  select * into m from public.customers where id = p_merge;

  v_preview := public.preview_customer_merge(p_keep, p_merge);
  if not (v_preview->>'can_merge')::boolean then
    raise exception 'This merge needs review first: %',
      (select string_agg(x->>'detail',' ') from jsonb_array_elements(v_preview->'blocking') x); end if;

  -- ---- credit: drawn down and reissued, never repointed -------------------
  --
  -- A posted lot is immutable -- customer, category, original amount, source
  -- and store cannot be edited -- and the ledger behind it is append-only. So
  -- the surviving record is granted a replacement carrying the same category,
  -- restrictions and dates, and the duplicate's lot is drawn down to nothing,
  -- with both movements written to the ledger. The balance is carried; it is
  -- never recreated, and bonus credit cannot become paid credit on the way.
  --
  -- The duplicate's wallet and its ledger entries stay as they are. Those
  -- entries record that, at the time, this credit moved under that record, and
  -- that remains true; the retired customer row keeps them resolvable.
  v_keep_wallet := public.ensure_customer_wallet(p_keep);
  for r_lot in
    select l.* from public.customer_credit_lots l
     where l.customer_id = p_merge and l.status = 'active' and l.remaining_amount > 0
     for update
  loop
    v_new_lot := gen_random_uuid();
    update public.customer_credit_lots
       set remaining_amount = 0, updated_at = now() where id = r_lot.id;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (r_lot.wallet_id, r_lot.customer_id, 'adjust_decrease', r_lot.category,
            r_lot.remaining_amount, r_lot.id, 'customer_merge_out', p_keep,
            r_lot.store_id, p_reason, auth.uid(), auth.uid());

    insert into public.customer_credit_lots
    select (jsonb_populate_record(null::public.customer_credit_lots, to_jsonb(r_lot) || jsonb_build_object(
      'id', v_new_lot, 'wallet_id', v_keep_wallet, 'customer_id', p_keep,
      'original_amount', r_lot.remaining_amount, 'remaining_amount', r_lot.remaining_amount,
      'source_type', 'customer_merge', 'source_record_id', p_merge,
      'reference_no', null, 'reason', p_reason, 'reversal_of_lot_id', null,
      'created_by', auth.uid(), 'approved_by', auth.uid(),
      'created_at', now(), 'updated_at', now()))).*;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (v_keep_wallet, p_keep, 'grant', r_lot.category, r_lot.remaining_amount,
            v_new_lot, 'customer_merge_in', p_merge, r_lot.store_id,
            p_reason, auth.uid(), auth.uid());
  end loop;

  -- ---- referrals go through the path that owns them -----------------------
  --
  -- customers.referred_by is protected by enforce_referral_ownership and by a
  -- no-self-referral trigger, and reassign_customer_referrer is what may change
  -- it: it locks the row, walks the chain for cycles and records the reason.
  -- Repointing it directly would be going round all of that.
  if k.referred_by = p_merge then
    perform public.reassign_customer_referrer(p_keep, null,
      'Merged duplicate ' || p_merge::text || ': ' || trim(p_reason));
  end if;
  for r in select id from public.customers
            where referred_by = p_merge and id <> p_keep and deleted_at is null
  loop
    perform public.reassign_customer_referrer(r.id, p_keep,
      'Referrer merged from duplicate ' || p_merge::text || ': ' || trim(p_reason));
  end loop;

  -- ---- affiliate record, when only the duplicate has one ------------------
  update public.customer_affiliates set customer_id = p_keep
   where customer_id = p_merge
     and not exists (select 1 from public.customer_affiliates where customer_id = p_keep);

  -- ---- everything else, from the catalogue --------------------------------
  for r in
    select c.relname as tbl, a.attname as col
      from pg_constraint kk
      join pg_class c on c.oid = kk.conrelid and c.relkind = 'r'
      join pg_attribute a on a.attrelid = kk.conrelid and a.attnum = any(kk.conkey)
      join pg_class f on f.oid = kk.confrelid
      join pg_namespace ns on ns.oid = c.relnamespace
     where kk.contype = 'f' and f.relname = 'customers' and ns.nspname = 'public'
       -- Handled above, or deliberately not moved:
       and not (c.relname = 'customer_credit_wallets')            -- UNIQUE per customer
       and not (c.relname = 'customer_credit_ledger')             -- append-only by design
       and not (c.relname = 'customer_credit_lots')               -- immutable; reissued above
       and not (c.relname = 'customers' and a.attname = 'referred_by') -- reassigned above
       and not (c.relname = 'customer_affiliates' and a.attname = 'customer_id')
     order by c.relname, a.attname
  loop
    v_sql := format('update public.%I set %I = $1 where %I = $2', r.tbl, r.col, r.col);
    execute v_sql using p_keep, p_merge;
    get diagnostics n = row_count;
    if n > 0 then
      v_moved := v_moved || jsonb_build_object(r.tbl || '.' || r.col, n);
    end if;
  end loop;

  -- The duplicate is retired, not destroyed: it is the evidence that those
  -- older records were always this person.
  update public.customers
     set deleted_at = now(),
         notes = coalesce(notes || E'\n', '') ||
                 'Merged into ' || coalesce(k.full_name, p_keep::text) ||
                 ' (' || p_keep::text || ') — ' || trim(p_reason)
   where id = p_merge;

  perform public.write_audit('customers', p_keep, 'customers_merged',
    jsonb_build_object('kept', to_jsonb(k), 'merged', to_jsonb(m)),
    jsonb_build_object('merged_from', p_merge, 'moved', v_moved,
                       'reason', trim(p_reason), 'request_id', p_request_id));

  return jsonb_build_object('success', true, 'kept', p_keep, 'retired', p_merge,
    'moved', v_moved);
end $$;
grant execute on function public.merge_customer_records(uuid,uuid,text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
