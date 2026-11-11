-- 502, AFTER GO-LIVE: THE EARLIER CREDIT PACKAGE SALE'S REWARD VOUCHERS (the user, 10 Nov 2026: the
-- one Credit Package sold before go-live and not yet paid off keeps its old terms; once it is paid
-- off, with credit only, its reward vouchers are added by this separate script).
--
-- RUN IT ONLY WITH THE USER'S OK, GIVEN AT THAT TIME, AND ONLY AFTER THAT INVOICE IS PAID OFF.
-- Nothing about it is automatic. Run it once.
--
-- WHAT IT DOES
--   * Finds the earlier sale that go-live step 2a (scripts/therapy/credit-package-credit-only-502.sql)
--     recorded in the Audit Log (credit_package_reward_kept_for_earlier_sale), not undone and not
--     given yet: the one part-paid S$1,000 Credit Package sale.
--   * Gives it the reward issue_credit_package would have made when it was paid off, had the
--     reward still been on, from the values that step kept: 1 reward of 10 vouchers, to be taken
--     as the vouchers the package offered at go-live (kept, whatever the package offers now), its
--     name as it was then, collected by the Singapore day the invoice was paid off
--     plus the kept collect-by window (365 days), for the customer and store of its Credit Package
--     sale, in that sale's reward group, numbered as every reward is (next_legacy_entitlement_no).
--     The sale records it (reward_units, reward_qualifying_snapshot) as the issuer would.
--   * One Audit Log row (credit_package_earlier_sale_reward_given) on the sale.
--   From then on the vouchers appear on Therapy -> Vouchers to hand over, staff hand them over as
--   any other; a refund or cancellation of that invoice withdraws those not handed over (those
--   handed over stay with the customer).
--
-- It refuses, with nothing changed, unless that invoice is now paid in full (not deleted), the
-- line's credit has been given, its Credit Package sale exists with no reward vouchers and no
-- reward row, and the kept values are complete and as read on 10 Nov 2026. Run again, it refuses.
--
-- HOW: one transaction, all or nothing. Set the recording account first, in the same transaction:
-- an active Owner or Manager, whose name the Audit Log row carries.
--   select set_config('request.jwt.claim.sub', '<an active Owner''s or Manager''s profile id>', true),
--          set_config('request.jwt.claim.role', 'authenticated', true),
--          set_config('request.jwt.claims', '{"sub":"<the same id>","role":"authenticated"}', true);
-- UNDO: none as a file. If the vouchers were given by mistake, the reward review on that invoice
-- (resolve_invoice_credit_rewards, Owner or Manager) withdraws the reward while none of its vouchers
-- has been handed over (once any has, it keeps the reward); ask the user.
do $presale$
declare
  c_reason constant text := 'A Credit Package sold before go-live keeps its reward vouchers (decision of 10 Nov 2026)';
  c_cp_reason constant text := 'Credit Packages give credit only (decision of 10 Nov 2026)';   -- step 2a's
  -- What the reward is made by, as on production on 10 Nov 2026: this copies issue_credit_package's
  -- reward rows; if one of these has changed, re-read it and re-test before running.
  c_relied constant text[] := array[
    'issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)',
    'credit_package_reward_group(uuid)',
    'next_legacy_entitlement_no()'];
  c_relied_md5 constant text[] := array[
    '5654ef9249cf5c6a943beb7890574f20',
    '7f8ac1b8bdc369110be03c8e9d260942',
    'b80297ed343c35bd214c117cdf29be6a'];
  -- As read on production on 10 Nov 2026 (and kept by step 2a): step 2a's constants of the same
  -- names; if those were changed at go-live, change these with them (the go-live suite checks).
  c_kept_lines constant int := 1;           -- the one part-paid S$1,000 package sale
  c_kept_price constant numeric := 1000;
  c_kept_units constant int := 1;           -- rewards: S$1,000 / S$994, rounded down
  c_vouchers_per_unit constant int := 10;
  c_threshold constant numeric := 994;
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_who uuid;
  v_kept jsonb; k jsonb; v jsonb;
  v_it public.invoice_items%rowtype;
  v_inv public.invoices%rowtype;
  v_sale public.credit_package_sales%rowtype;
  v_group uuid; v_deadline date; v_vouchers uuid[]; v_ent uuid; v_no text;
  v_made jsonb; v_a_given int; v_given_total int := 0;
  i int;
begin
  perform set_config('lock_timeout', '5s', true);
  perform set_config('search_path', 'public', true);   -- md5s are read with public alone

  -- 0. Who records it: an active Owner or Manager, set in this transaction.
  if coalesce(current_setting('request.jwt.claim.sub', true), '') = ''
     or coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')
          <> current_setting('request.jwt.claim.sub', true)
     or not public.is_owner_or_manager() then
    raise exception '502 earlier sale: set the recording account (an active Owner or Manager) first, in this transaction: request.jwt.claim.sub and request.jwt.claims, as the header shows. Nothing changed.'; end if;
  v_who := auth.uid();
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '502 earlier sale: public.% is not the version this was tested against. Re-read it and re-test before running. Nothing changed.', c_relied[i]; end if;
  end loop;

  -- 1. The earlier sale kept by step 2a, not undone and not given yet.
  v_kept := (select coalesce(jsonb_agg(jsonb_build_object('audit_id', a.id, 'line_id', a.record_id, 'values', a.new_data) order by a.record_id), '[]'::jsonb)
               from public.audit_logs a
              where a.action = 'credit_package_reward_kept_for_earlier_sale' and a.reason = c_cp_reason
                and not exists (select 1 from public.audit_logs u
                                 where (u.action = 'credit_package_reward_kept_for_earlier_sale_undone'
                                        or u.action = 'credit_package_earlier_sale_reward_given')
                                   and u.new_data ->> 'kept_audit_id' = a.id::text));
  if jsonb_array_length(v_kept) = 0 then
    raise exception '502 earlier sale: there is no earlier sale to give a reward to: go-live step 2a recorded none, it was undone, or its reward was given already. Nothing changed.'; end if;
  if jsonb_array_length(v_kept) <> c_kept_lines then
    raise exception '502 earlier sale: found % earlier sales kept by go-live step 2a, not %. Nothing changed.', jsonb_array_length(v_kept), c_kept_lines; end if;

  -- Every check first, for each; nothing is written before all pass.
  for k in select * from jsonb_array_elements(v_kept) loop
    v := k -> 'values';
    -- The kept values are complete, and as read on 10 Nov 2026.
    if not (v ?& array['invoice_item_id', 'invoice_id', 'package_id', 'reward_name', 'customer_price', 'units',
                       'vouchers_per_unit', 'threshold', 'forfeited_value', 'claim_window_days', 'duration_months', 'voucher_ids'])
       or exists (select 1 from jsonb_each(v) e
                   where e.key in ('invoice_item_id', 'invoice_id', 'package_id', 'reward_name', 'customer_price', 'units',
                                   'vouchers_per_unit', 'threshold', 'forfeited_value', 'claim_window_days', 'duration_months', 'voucher_ids')
                     and jsonb_typeof(e.value) = 'null')
       or jsonb_typeof(v -> 'voucher_ids') <> 'array'
       or v ->> 'invoice_item_id' is distinct from k ->> 'line_id'
       or (v ->> 'units')::int <> c_kept_units
       or (v ->> 'vouchers_per_unit')::int <> c_vouchers_per_unit
       or (v ->> 'threshold')::numeric <> c_threshold
       or (v ->> 'customer_price')::numeric <> c_kept_price
       or (v ->> 'claim_window_days')::int <= 0
       or (v ->> 'forfeited_value')::numeric is distinct from round(c_kept_price - c_kept_units * c_threshold, 2) then
      raise exception '502 earlier sale: the values go-live step 2a kept are not complete, or not as read on 10 Nov 2026. Nothing changed.'; end if;

    -- That invoice is paid in full now, and the line's credit has been given.
    select * into v_it from public.invoice_items where id = (v ->> 'invoice_item_id')::uuid;
    if not found or v_it.line_kind <> 'credit_package' or v_it.invoice_id is distinct from (v ->> 'invoice_id')::uuid
       or v_it.credit_package_id is distinct from (v ->> 'package_id')::uuid then
      raise exception '502 earlier sale: the Credit Package line go-live step 2a kept (invoice %) is no longer on its invoice as it was. Ask the user. Nothing changed.', v ->> 'invoice_no'; end if;
    select * into v_inv from public.invoices where id = v_it.invoice_id;
    if v_inv.deleted_at is not null or v_inv.status::text <> 'paid' or v_it.credit_issued_at is null then
      raise exception '502 earlier sale: invoice % is not paid off yet (it is %). Run this only after it is paid in full, and with the user''s OK. Nothing changed.',
        v_inv.invoice_no, case when v_inv.deleted_at is not null then 'deleted' else v_inv.status::text end
                          || case when v_it.credit_issued_at is null then ', its credit not given' else '' end; end if;

    -- Its Credit Package sale: there, with no reward vouchers and no reward row.
    if (select count(*) from public.credit_package_sales s where s.invoice_item_id = v_it.id) <> 1 then
      raise exception '502 earlier sale: invoice % has % Credit Package sales for the line, not 1. Nothing changed.',
        v_inv.invoice_no, (select count(*) from public.credit_package_sales s where s.invoice_item_id = v_it.id); end if;
    select * into v_sale from public.credit_package_sales s where s.invoice_item_id = v_it.id;
    if v_sale.invoice_id is distinct from v_inv.id or v_sale.package_id is distinct from v_it.credit_package_id
       or v_sale.reward_units <> 0 or coalesce(v_sale.reward_voucher_qty, 0) <> 0 or v_sale.rewards_resolved_at is not null
       or exists (select 1 from public.therapy_entitlements e
                   where e.qualification_group_id = public.credit_package_reward_group(v_sale.id)) then
      raise exception '502 earlier sale: the Credit Package sale on invoice % already has reward vouchers, or a reward review. Nothing changed.', v_inv.invoice_no; end if;
  end loop;

  v_a_given := (select count(*) from public.audit_logs
                 where action = 'credit_package_earlier_sale_reward_given' and reason = c_reason and changed_by = v_who);

  -- 2. The reward, exactly as issue_credit_package makes it with the reward on, from the kept
  --    values: for the customer and store of the sale, in the sale's reward group, collected by
  --    the Singapore day the line was paid off plus the kept window.
  for k in select * from jsonb_array_elements(v_kept) loop
    v := k -> 'values';
    select * into v_it from public.invoice_items where id = (v ->> 'invoice_item_id')::uuid;
    select * into v_inv from public.invoices where id = v_it.invoice_id;
    select * into v_sale from public.credit_package_sales s where s.invoice_item_id = v_it.id for update;
    v_group := public.credit_package_reward_group(v_sale.id);
    v_deadline := (v_it.credit_issued_at at time zone 'Asia/Singapore')::date + (v ->> 'claim_window_days')::int;
    v_vouchers := array(select x::uuid from jsonb_array_elements_text(v -> 'voucher_ids') x);
    v_made := '[]'::jsonb;
    for i in 1 .. (v ->> 'units')::int loop
      v_no := public.next_legacy_entitlement_no();
      insert into public.therapy_entitlements (
        entitlement_no, customer_id, store_id, rule_id, package_name,
        entitlement_kind, duration_months, voucher_qty, qualifying_amount,
        qualified_value, forfeited_value, activation_deadline, status,
        created_by, qualification_group_id, earner_kind,
        eligible_voucher_ids, claim_source_type, claim_source_invoice_id)
      values (v_no, v_sale.customer_id, v_sale.store_id, null, v ->> 'reward_name',
        'voucher', (v ->> 'duration_months')::int, (v ->> 'vouchers_per_unit')::int, (v ->> 'threshold')::numeric,
        (v ->> 'threshold')::numeric, (v ->> 'forfeited_value')::numeric, v_deadline, 'pending_activation',
        v_who, v_group, 'credit_package',
        v_vouchers, 'credit_package', v_sale.invoice_id)
      returning id into v_ent;
      v_made := v_made || jsonb_build_array(jsonb_build_object('id', v_ent, 'no', v_no));
    end loop;
    update public.credit_package_sales
       set reward_units = (v ->> 'units')::int, reward_qualifying_snapshot = (v ->> 'threshold')::numeric
     where id = v_sale.id;
    perform public.write_audit_ex('credit_package_sales', v_sale.id, 'credit_package_earlier_sale_reward_given',
      jsonb_build_object('reward_units', v_sale.reward_units, 'reward_qualifying_snapshot', v_sale.reward_qualifying_snapshot),
      jsonb_build_object('kept_audit_id', k ->> 'audit_id', 'invoice_item_id', v_it.id, 'invoice_id', v_sale.invoice_id,
                         'invoice_no', v_inv.invoice_no, 'package', v ->> 'package', 'customer_id', v_sale.customer_id,
                         'reward_units', (v ->> 'units')::int, 'vouchers', (v ->> 'units')::int * (v ->> 'vouchers_per_unit')::int,
                         'threshold', (v ->> 'threshold')::numeric, 'collect_by', v_deadline, 'rewards', v_made),
      'credit', c_reason, v_sale.store_id);
    v_given_total := v_given_total + 1;

    -- 3. What it leaves, for this sale.
    if (select count(*) from public.therapy_entitlements e
         where e.qualification_group_id = v_group and e.earner_kind = 'credit_package' and e.status = 'pending_activation'
           and e.entitlement_kind = 'voucher' and e.voucher_qty = (v ->> 'vouchers_per_unit')::int
           and e.activation_deadline = v_deadline and e.customer_id = v_sale.customer_id
           and e.claim_source_invoice_id = v_sale.invoice_id
           and e.eligible_voucher_ids is not distinct from v_vouchers) <> (v ->> 'units')::int
       or (select count(*) from public.therapy_entitlements e where e.qualification_group_id = v_group) <> (v ->> 'units')::int
       or (select reward_units from public.credit_package_sales where id = v_sale.id) <> (v ->> 'units')::int then
      raise exception '502 earlier sale: what it left is not what was planned. Nothing changed.'; end if;
  end loop;

  if v_given_total <> c_kept_lines
     or (select count(*) from public.audit_logs
          where action = 'credit_package_earlier_sale_reward_given' and reason = c_reason and changed_by = v_who) <> v_a_given + c_kept_lines then
    raise exception '502 earlier sale: what it left is not what was planned. Nothing changed.'; end if;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
end $presale$;
