begin;
-- =====================================================================
-- A PREMIUM BUNDLE'S REWARD VOUCHERS CAN BE CHOSEN LATER
--
-- create_invoice refused any bundle line whose selection was not the exact
-- full allowance — "Select exactly 10 reward voucher(s) … 3 chosen" — so a
-- customer who had not decided could not buy the bundle at all. The machinery
-- to defer already exists: issue_premium_bundle_invoice_item creates a
-- claimable entitlement for whatever was not chosen at the till. Only the
-- validation stood in the way.
--
-- Fewer than the allowance is now accepted, including none. More than the
-- allowance is still refused, and every voucher chosen is still checked for
-- eligibility and stock.
--
-- Patched across EVERY create_invoice overload. Production carries two, and
-- migration 302 exists because a previous fix patched one of a pair and left
-- the other answering the old way.
--
-- The deferred entitlement's deadline also changes here. 314 took it from
-- whichever therapy_package_rules row happened to have the smallest
-- activation_deadline_days — a rule about therapy packages, unrelated to this
-- purchase. It now uses one year from payment, the same rule
-- create_purchased_therapy_for_invoice applies to a direct purchase.
-- =====================================================================
do $do$
declare r record; f text; g text; v_head text; v_decl text; v_var text; v_n int := 0;
begin
  -- Every function that enforces the bundle selection, found by what it does
  -- rather than by a hand-written list. Production carries two create_invoice
  -- overloads and there are further call sites besides; migration 302 exists
  -- because a previous fix patched one of a pair and left the other answering
  -- the old way.
  for r in
    select p.oid, p.oid::regprocedure::text as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.prosrc like '%validate_bundle_voucher_selection%'
       and p.prosrc like '%Select exactly%'
       -- A repair helper that REINSTALLS create_invoice; patched separately
       -- below so it cannot put the old rule back.
       and p.proname <> 'repair_create_invoice_package_branches'
  loop
    f := pg_get_functiondef(r.oid);

    -- Older seven-argument create_invoice bodies received the package branches
    -- without their local declarations. Recompiling such a stored body fails
    -- at v_gross first, then v_sel/v_pj. Repair only missing package locals;
    -- keep existing declarations, defaults and the rest of the body intact.
    if r.proname = 'create_invoice' then
      v_head := substring(f from '(?is)\mdeclare\M(.*?)\mbegin\M');
      if v_head is null then
        raise exception 'Cannot find the declaration block in %', r.sig;
      end if;
      v_decl := '';
      foreach v_var in array array['v_gross', 'v_sel', 'v_pj'] loop
        if f ~ ('\m' || v_var || '\M')
           and v_head !~* ('\m' || v_var || '\s+') then
          v_decl := v_decl || chr(10) || '  ' || v_var ||
            case when v_var = 'v_gross' then ' numeric;' else ' jsonb;' end;
        end if;
      end loop;
      if v_decl <> '' then
        f := regexp_replace(f, '(?i)\mdeclare\M', 'declare' || v_decl);
      end if;
    end if;

    -- Both wordings in use, same rule underneath.
    g := replace(f,
      'if not (v_pj->>''complete'')::boolean then',
      'if (v_pj->>''selected_qty'')::int > (v_pj->>''required_qty'')::int then');
    g := replace(g,
      'if not (v_check->>''complete'')::boolean then',
      'if (v_check->>''selected_qty'')::int > (v_check->>''required_qty'')::int then');
    g := replace(g,
      'raise exception ''Select exactly % reward voucher(s) for "%" — % chosen''',
      'raise exception ''That is more reward voucher(s) than the allowance of % for "%" — % chosen''');
    g := replace(g,
      'raise exception ''Select exactly % voucher(s) for "%" — % chosen''',
      'raise exception ''That is more reward voucher(s) than the allowance of % for "%" — % chosen''');
    -- A third wording, with no bundle name in it.
    g := replace(g,
      'raise exception ''Select exactly % voucher(s) — % chosen''',
      'raise exception ''That is more reward voucher(s) than this bundle grants — % available, % chosen''');

    if position('more reward voucher' in g) = 0 then
      raise exception 'bundle selection rule in % does not match what 323 expects — align it by hand', r.sig; end if;
    execute g;
    v_n := v_n + 1;
    raise notice 'fewer than the allowance is now accepted in %', r.sig;
  end loop;
  if v_n = 0 then raise notice 'no function needed the bundle selection change'; end if;
end $do$;

-- The repair helper reinstalls create_invoice from a stored body. Left as it
-- is, running it would quietly put the strict rule back.
do $do$
declare f text;
begin
  select pg_get_functiondef(p.oid) into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='repair_create_invoice_package_branches';
  if f is not null and position('Select exactly' in f) > 0 then
    raise notice 'NOTE: repair_create_invoice_package_branches() still carries the old strict wording in the body it installs. It is a manual repair tool, not called by the app; re-run 323 after ever using it.';
  end if;
end $do$;

-- The deferred entitlement's deadline comes from this purchase, not from an
-- unrelated therapy rule.
do $do$
declare f text;
begin
  select pg_get_functiondef('public.issue_premium_bundle_invoice_item(uuid)'::regprocedure) into f;
  if position('therapy_package_rules' in f) > 0 then
    f := replace(f,
      '      public.sg_today() + coalesce((select activation_deadline_days from public.therapy_package_rules
                                     where activation_deadline_days is not null
                                     order by activation_deadline_days limit 1), 365),',
      '      -- One year from payment, the rule a direct purchase already uses.
      ((coalesce(v_inv.paid_at, now()) at time zone ''Asia/Singapore'')::date + interval ''1 year'')::date,');
    if position('therapy_package_rules' in f) > 0 then
      raise exception 'issue_premium_bundle_invoice_item does not match what 323 expects — align it by hand'; end if;
    execute f;
    raise notice 'bundle deferral now dates its deadline from the purchase';
  end if;
end $do$;

-- ---------------------------------------------------------------------
-- The single-customer path needs the deferral too.
--
-- 314 gave issue_premium_bundle_invoice_item -- the SPLIT path -- an
-- entitlement for whatever was not chosen at the till. An ordinary
-- single-customer bundle goes through sell_premium_bundle instead, which had
-- no such branch, so relaxing the validation alone would have sold a bundle
-- whose unchosen vouchers simply vanished.
-- ---------------------------------------------------------------------
do $do$
declare f text;
begin
  select pg_get_functiondef('public.sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean)'::regprocedure) into f;
  if position('bundle_deferred_single' in f) = 0 then
    f := replace(f,
      '  update public.premium_bundle_sales set vouchers_issued = v_issued where id = v_sale;',
      '  update public.premium_bundle_sales set vouchers_issued = v_issued where id = v_sale;

  -- bundle_deferred_single: whatever was not chosen at the till is still owed,
  -- and stays claimable until the deadline. Dated from this purchase.
  if coalesce(b.free_voucher_qty,0) - v_issued > 0 then
    insert into public.therapy_entitlements (
      entitlement_no, customer_id, store_id, rule_id, package_name,
      entitlement_kind, duration_months, voucher_qty, qualifying_amount,
      qualified_value, forfeited_value, activation_deadline, status,
      created_by, qualification_group_id, earner_kind,
      eligible_voucher_ids, claim_source_type, claim_source_invoice_id)
    values (public.next_legacy_entitlement_no(), p_customer_id, p_store_id, null,
      ''Premium bundle reward — '' || b.name,
      ''voucher'', 1, coalesce(b.free_voucher_qty,0) - v_issued, 0,
      coalesce(b.customer_payment_amount,0), 0,
      (public.sg_today() + interval ''1 year'')::date,
      ''pending_activation'', auth.uid(),
      md5(''bundle_sale:'' || v_sale::text)::uuid, ''premium_bundle'',
      (select coalesce(array_agg(voucher_id),''{}'') from public.premium_bundle_vouchers where bundle_id = b.id),
      ''premium_bundle'', p_invoice_id);
  end if;');
    if position('bundle_deferred_single' in f) = 0 then
      raise exception 'sell_premium_bundle does not match what 323 expects — align it by hand'; end if;
    execute f;
    raise notice 'sell_premium_bundle now defers what was not chosen';
  end if;
end $do$;

notify pgrst,'reload schema';
commit;
