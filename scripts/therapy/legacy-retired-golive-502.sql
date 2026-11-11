-- 502, GO-LIVE STEP 2b: LEGACY REWARDS CANCELLED, QUALIFICATION RULES OFF (the user, 10 Nov 2026:
-- Legacy Therapy and Qualification removed; earning stops at go-live; the unclaimed rewards are
-- cancelled; every record stays as history).
--
-- WHAT IT DOES
--   * Cancels the 103 Legacy rewards not yet claimed: 102 one-month rewards (43 customers) and the
--     1 affiliate reward of 10 vouchers. Each row stays, with its number and its invoice links; it
--     is marked cancelled with the reason below, and gets one Audit Log row
--     (legacy_reward_cancelled) keeping what it was.
--   * Switches the 3 qualification rules off, through the rule form's own function
--     (upsert_legacy_rule, which writes legacy_rule_upserted), one Audit Log row each
--     (legacy_rule_switched_off). It is not what stops earning: that stopped when 502 committed.
--   * One Audit Log row for the whole step (legacy_therapy_retired).
--   Nothing else changes: the 50 vouchers already handed over stay with the 3 customers as
--   ordinary vouchers; the Credit Package rewards already given (10 rewards, 100 vouchers) can still
--   be handed over; claimed, used, expired and cancelled rewards, the invoice links, Credit
--   Packages and Premium Bundles stay as they are.
--
-- WHEN: straight after scripts/therapy/credit-package-credit-only-502.sql, in the same quiet
-- window, outside opening hours. It refuses unless 502 and that step are in. It locks the rewards
-- it cancels as it reads them: a voucher hand-over started after that waits for it and is then
-- refused (the reward is cancelled by then); one already under way when it reads them makes it
-- refuse, changing nothing (then read the preview again and ask the user). The lock needs two
-- sessions to show: it was rehearsed that way on a local copy (10 Nov 2026); the go-live suite
-- runs in one session, so it checks the re-check before each cancel, not the lock.
-- GO-LIVE ORDER: supabase/502_legacy_therapy_retired.sql ->
-- scripts/therapy/credit-package-credit-only-502.sql -> THIS FILE -> the pages; then every till and
-- office PC reloads the app. If this refuses on its own, the step before stands (Credit Packages
-- give credit only): find out why and tell the user. Run in one transaction with 502 and step 2a,
-- a refusal here undoes them too, 502 included.
--
-- HOW: one transaction, all or nothing. Set the recording account first, in the same transaction:
-- an active Owner or Manager, whose name every Audit Log row carries.
--   select set_config('request.jwt.claim.sub', '<an active Owner''s or Manager''s profile id>', true),
--          set_config('request.jwt.claim.role', 'authenticated', true),
--          set_config('request.jwt.claims', '{"sub":"<the same id>","role":"authenticated"}', true);
-- It refuses, with nothing changed, unless what it finds is what was read on production on
-- 10 Nov 2026 (the constants below). Before the window, run scripts/therapy/golive-preview-502.sql
-- (read-only): it prints each figure next to its constant. If a figure has moved, for example a
-- reward claimed after 10 Nov, tell the user the new figures, and change the constant, in every
-- file the preview names for it, only with their OK; then run the go-live suite again. Run again,
-- it refuses and changes nothing.
-- STOP SIGNS no constant can fix (the preview's "stop" rows; tell the user, the code must change):
-- a Legacy month booked or running; a waiting Legacy reward this step leaves out (part handed
-- over, no rule, from a sale); a waiting Legacy reward that is neither a customer's one-month
-- reward nor an affiliate's voucher reward, or affiliate rewards with different numbers of
-- vouchers; an active rule for one store only, rules with different amounts, or a rule the rule
-- form's function would refuse or change.
--
-- UNDO: scripts/therapy/undo-legacy-retired-golive-502.sql (while 502 is in).
-- ROLLBACK ORDER: revert the pages -> scripts/therapy/undo-legacy-retired-golive-502.sql ->
-- scripts/therapy/undo-credit-package-credit-only-502.sql -> scripts/therapy/undo-502.sql.
do $golive$
declare
  c_reason constant text := 'Legacy Therapy retired (decision of 10 Nov 2026)';
  c_cp_reason constant text := 'Credit Packages give credit only (decision of 10 Nov 2026)';   -- step 2a's
  -- 502 is in: its AFTER md5s, read with public alone on the search path.
  c_trg_after constant text := '7b63da063576a5c952cc5abe6c53f13d';   -- trg_create_therapy_on_paid()
  c_cat_after constant text := 'a8a9c9ae3862a348217cc434185f9781';   -- set_catalogue_reward(text,uuid,boolean)
  -- As read on production on 10 Nov 2026. Repeated elsewhere, to change together (the go-live
  -- suite checks that they agree): undo 2b's c_rewards = c_cust_rows + c_aff_rows; c_rules in
  -- undo 2b; c_packages in step 2a and undo 2a; c_kept_lines in step 2a, undo 2a and the
  -- earlier-sale script.
  c_cust_rows constant int := 102;  c_cust_people constant int := 43;   -- one-month rewards not claimed, and their customers
  c_aff_rows  constant int := 1;    c_aff_vouchers constant int := 10;  -- the affiliate reward not claimed, and its vouchers
  c_cp_rows   constant int := 10;   c_cp_vouchers  constant int := 100; -- Credit Package rewards still to hand over (not touched)
  c_other     constant int := 60;   -- Legacy rewards already claimed, used or cancelled (not touched)
  c_held_rows constant int := 6;    c_held_qty     constant int := 50;  -- vouchers handed over from Legacy rewards (not touched)
  c_links     constant int := 67;   -- invoice links (not touched)
  c_rules     constant int := 3;    c_rule_amount  constant numeric := 994;  -- active rules, all stores, S$994
  c_packages  constant int := 3;    c_kept_lines   constant int := 1;   -- what step 2a switched off and recorded
  c_bundles_on constant int := 2;   c_bundles_off  constant int := 2;   -- Premium Bundles with the reward on / off (not touched)
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_who uuid;
  v_ids uuid[];
  v_fp_keep text; v_fp_w text; v_fp_crv text; v_fp_links text; v_fp_bundles text; v_fp_pk text; v_fp_rules text;
  v_a_cancel int; v_a_upsert int; v_a_off int; v_a_sum int;
  r record; n_cust int := 0; n_aff int := 0; n_rules int := 0;
begin
  -- At most 5 seconds' wait for any lock: it fails rather than holding a hand-over behind it.
  perform set_config('lock_timeout', '5s', true);
  perform set_config('search_path', 'public', true);   -- md5s are read with public alone

  -- 0. Who records it: an active Owner or Manager, set in this transaction.
  if coalesce(current_setting('request.jwt.claim.sub', true), '') = ''
     or coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')
          <> current_setting('request.jwt.claim.sub', true)
     or not public.is_owner_or_manager() then
    raise exception '502 go-live: set the recording account (an active Owner or Manager) first, in this transaction: request.jwt.claim.sub and request.jwt.claims, as the header shows. Nothing changed.'; end if;
  v_who := auth.uid();

  -- 502 is in.
  if md5(pg_get_functiondef('public.trg_create_therapy_on_paid()'::regprocedure)) <> c_trg_after
     or md5(pg_get_functiondef('public.set_catalogue_reward(text,uuid,boolean)'::regprocedure)) <> c_cat_after
     or exists (select 1 from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'legacy_refund_guard') then
    raise exception '502 go-live: migration 502 is not in. Apply it first. Nothing changed.'; end if;

  -- Step 2a is in: no Credit Package gives reward vouchers, and its Audit Log rows are there, not
  -- undone (one switch-off for each of the 3 packages, and the earlier sale kept).
  if exists (select 1 from public.credit_packages where grants_reward)
     or (select count(distinct a.record_id) from public.audit_logs a
          where a.action = 'credit_package_reward_switched_off' and a.reason = c_cp_reason
            and not exists (select 1 from public.audit_logs u
                             where u.action = 'credit_package_reward_switched_on'
                               and u.new_data ->> 'switched_off_audit_id' = a.id::text)) <> c_packages
     or (select count(*) from public.audit_logs a
          where a.action = 'credit_package_reward_kept_for_earlier_sale' and a.reason = c_cp_reason
            and not exists (select 1 from public.audit_logs u
                             where u.action = 'credit_package_reward_kept_for_earlier_sale_undone'
                               and u.new_data ->> 'kept_audit_id' = a.id::text)) <> c_kept_lines then
    raise exception '502 go-live: run scripts/therapy/credit-package-credit-only-502.sql first (Credit Packages give credit only). Nothing changed.'; end if;

  -- Not run already.
  if exists (select 1 from public.therapy_entitlements where status = 'cancelled' and revoked_reason = c_reason) then
    raise exception '502 go-live: this has run already (rewards are cancelled with its reason). Nothing changed.'; end if;

  -- 1. What it finds is what was read on 10 Nov 2026.
  -- W: the unclaimed Legacy rewards (earned by a customer's or an affiliate's paid day), locked as
  -- they are read. A hand-over locks its reward first (claim_entitlement_vouchers), so one started
  -- after this waits until this step ends, and then finds the reward cancelled; one under way
  -- makes this wait for it (at most 5 seconds) and then leaves that reward out of W, so the
  -- figures below refuse.
  select coalesce(array_agg(s.id order by s.id), '{}') into v_ids
    from (select e.id from public.therapy_entitlements e
           where e.status = 'pending_activation' and e.earner_kind in ('customer', 'affiliate')
             and e.rule_id is not null and e.claim_source_invoice_id is null and e.claimed_at is null
             and public.entitlement_claimed_qty(e.id) = 0
           order by e.id
             for update) s;
  if (select count(*) from public.therapy_entitlements e where e.id = any(v_ids)
        and e.earner_kind = 'customer' and e.entitlement_kind = 'unlimited') <> c_cust_rows
     or (select count(distinct e.customer_id) from public.therapy_entitlements e where e.id = any(v_ids)
           and e.earner_kind = 'customer') <> c_cust_people
     or (select count(*) from public.therapy_entitlements e where e.id = any(v_ids)
           and e.earner_kind = 'affiliate' and e.entitlement_kind = 'voucher' and e.voucher_qty = c_aff_vouchers) <> c_aff_rows
     or cardinality(v_ids) <> c_cust_rows + c_aff_rows
     -- nothing Legacy and unclaimed escapes W
     or (select count(*) from public.therapy_entitlements e
          where e.status = 'pending_activation' and e.earner_kind in ('customer', 'affiliate')) <> c_cust_rows + c_aff_rows
     -- no Legacy month is running or booked
     or exists (select 1 from public.therapy_entitlements e where e.earner_kind in ('customer', 'affiliate')
                  and (e.status = 'scheduled' or (e.status = 'active' and coalesce(e.entitlement_kind, 'unlimited') = 'unlimited')))
     or (select count(*) from public.therapy_entitlements e
          where e.earner_kind in ('customer', 'affiliate') and e.status <> 'pending_activation') <> c_other
     or (select count(*) from public.therapy_entitlements e
          where e.earner_kind = 'credit_package' and e.status = 'pending_activation') <> c_cp_rows
     or (select coalesce(sum(e.voucher_qty), 0) from public.therapy_entitlements e
          where e.earner_kind = 'credit_package' and e.status = 'pending_activation') <> c_cp_vouchers
     or (select count(*) from public.customer_reward_vouchers v join public.therapy_entitlements e on e.id = v.entitlement_id
          where e.earner_kind in ('customer', 'affiliate')) <> c_held_rows
     or (select coalesce(sum(v.quantity), 0) from public.customer_reward_vouchers v join public.therapy_entitlements e on e.id = v.entitlement_id
          where e.earner_kind in ('customer', 'affiliate') and v.status = 'held') <> c_held_qty
     or (select count(*) from public.therapy_entitlement_invoices) <> c_links
     or (select count(*) from public.therapy_package_rules where is_active and deleted_at is null) <> c_rules
     or exists (select 1 from public.therapy_package_rules where is_active and deleted_at is null
                  and (qualifying_amount <> c_rule_amount or store_id is not null))
     or (select count(*) from public.premium_bundles where grants_reward) <> c_bundles_on
     or (select count(*) from public.premium_bundles where not grants_reward) <> c_bundles_off then
    raise exception '502 go-live: production is not as read on 10 Nov 2026. Run scripts/therapy/golive-preview-502.sql (read-only), tell the user the new figures, and change the constants only with their OK. Nothing changed.'; end if;

  -- What must not change: every reward it does not cancel (all of each row), the rest of each one
  -- it cancels, the vouchers handed over from Legacy rewards, the invoice links, Premium Bundles,
  -- Credit Packages, and the rules but for being on.
  v_fp_keep := (select md5(coalesce(string_agg(to_jsonb(e)::text, ',' order by e.id), ''))
                  from public.therapy_entitlements e where not (e.id = any(v_ids)));
  v_fp_w := (select md5(coalesce(string_agg((to_jsonb(e) - 'status' - 'revoked_qty' - 'revoked_at' - 'revoked_reason')::text, ',' order by e.id), ''))
               from public.therapy_entitlements e where e.id = any(v_ids));
  v_fp_crv := (select md5(coalesce(string_agg(to_jsonb(v)::text, ',' order by v.id), ''))
                 from public.customer_reward_vouchers v join public.therapy_entitlements e on e.id = v.entitlement_id
                where e.earner_kind in ('customer', 'affiliate'));
  v_fp_links := (select md5(coalesce(string_agg(to_jsonb(t)::text, ',' order by t.id), ''))
                   from public.therapy_entitlement_invoices t);
  v_fp_bundles := (select md5(coalesce(string_agg(to_jsonb(b)::text, ',' order by b.id), '')) from public.premium_bundles b);
  v_fp_pk := (select md5(coalesce(string_agg(to_jsonb(p)::text, ',' order by p.id), '')) from public.credit_packages p);
  v_fp_rules := (select md5(coalesce(string_agg((to_jsonb(t) - 'is_active' - 'updated_at')::text, ',' order by t.id), ''))
                   from public.therapy_package_rules t);
  v_a_cancel := (select count(*) from public.audit_logs where action = 'legacy_reward_cancelled' and reason = c_reason and changed_by = v_who);
  v_a_upsert := (select count(*) from public.audit_logs where action = 'legacy_rule_upserted' and changed_by = v_who);
  v_a_off := (select count(*) from public.audit_logs where action = 'legacy_rule_switched_off' and reason = c_reason and changed_by = v_who);
  v_a_sum := (select count(*) from public.audit_logs where action = 'legacy_therapy_retired' and reason = c_reason and changed_by = v_who);

  -- 2. The unclaimed Legacy rewards are cancelled, one Audit Log row each. Its old values are what
  --    the UNDO puts back.
  for r in select e.* from public.therapy_entitlements e where e.id = any(v_ids) order by e.created_at, e.id for update loop
    update public.therapy_entitlements
       set status = 'cancelled',
           -- as revoke_unclaimed_entitlement_vouchers does: a voucher reward's vouchers not handed over are withdrawn
           revoked_qty = case when coalesce(entitlement_kind, '') = 'voucher' then coalesce(voucher_qty, 0) else revoked_qty end,
           revoked_at = now(), revoked_reason = c_reason
     where id = r.id and status = 'pending_activation'
       -- still as read: not claimed, nothing handed over from it
       and claimed_at is null and public.entitlement_claimed_qty(id) = 0;
    if not found then raise exception '502 go-live: % changed while this ran (claimed, or vouchers handed over from it). Nothing changed.', r.entitlement_no; end if;
    perform public.write_audit_ex('therapy_entitlements', r.id, 'legacy_reward_cancelled',
      jsonb_build_object('status', r.status, 'entitlement_no', r.entitlement_no, 'earner_kind', r.earner_kind,
                         'entitlement_kind', r.entitlement_kind, 'voucher_qty', r.voucher_qty, 'claim_by', r.activation_deadline,
                         'revoked_qty', r.revoked_qty, 'revoked_at', r.revoked_at, 'revoked_reason', r.revoked_reason),
      jsonb_build_object('status', 'cancelled', 'reason', c_reason,
                         'revoked_qty', case when coalesce(r.entitlement_kind, '') = 'voucher' then coalesce(r.voucher_qty, 0) else r.revoked_qty end),
      'therapy', c_reason, r.store_id);
    if r.earner_kind = 'customer' then n_cust := n_cust + 1; else n_aff := n_aff + 1; end if;
  end loop;

  -- 3. The qualification rules off, through the rule form's own function (it writes
  --    legacy_rule_upserted, which does not say off; the second row does).
  for r in select * from public.therapy_package_rules where is_active and deleted_at is null order by applies_to, entitlement_kind, id loop
    perform public.upsert_legacy_rule(r.id, r.store_id, r.name, r.qualifying_amount, r.entitlement_kind,
      r.duration_months, r.voucher_qty, r.activation_deadline_days, false, null, r.applies_to);
    perform public.write_audit_ex('therapy_package_rules', r.id, 'legacy_rule_switched_off',
      jsonb_build_object('is_active', true),
      jsonb_build_object('is_active', false, 'name', r.name, 'applies_to', r.applies_to, 'qualifying_amount', r.qualifying_amount),
      'therapy', c_reason, null);
    n_rules := n_rules + 1;
  end loop;

  -- 4. One line for the Audit Log page.
  perform public.write_audit_ex('therapy_entitlements', null, 'legacy_therapy_retired', null,
    jsonb_build_object('customer_rewards_cancelled', n_cust, 'customers', c_cust_people,
                       'affiliate_rewards_cancelled', n_aff, 'rules_switched_off', n_rules),
    'therapy', c_reason, null);

  -- 5. What it leaves.
  if n_cust <> c_cust_rows or n_aff <> c_aff_rows or n_rules <> c_rules
     or exists (select 1 from public.therapy_entitlements e
                 where e.status = 'pending_activation' and e.earner_kind in ('customer', 'affiliate'))
     or (select count(*) from public.therapy_entitlements where status = 'cancelled' and revoked_reason = c_reason) <> c_cust_rows + c_aff_rows
     or exists (select 1 from public.therapy_entitlements e where e.id = any(v_ids)
                 and (e.status <> 'cancelled' or e.revoked_reason is distinct from c_reason or e.revoked_at is distinct from now()))
     or v_fp_keep is distinct from (select md5(coalesce(string_agg(to_jsonb(e)::text, ',' order by e.id), ''))
                                      from public.therapy_entitlements e where not (e.id = any(v_ids)))
     or v_fp_w is distinct from (select md5(coalesce(string_agg((to_jsonb(e) - 'status' - 'revoked_qty' - 'revoked_at' - 'revoked_reason')::text, ',' order by e.id), ''))
                                   from public.therapy_entitlements e where e.id = any(v_ids))
     or v_fp_crv is distinct from (select md5(coalesce(string_agg(to_jsonb(v)::text, ',' order by v.id), ''))
                                     from public.customer_reward_vouchers v join public.therapy_entitlements e on e.id = v.entitlement_id
                                    where e.earner_kind in ('customer', 'affiliate'))
     or v_fp_links is distinct from (select md5(coalesce(string_agg(to_jsonb(t)::text, ',' order by t.id), ''))
                                       from public.therapy_entitlement_invoices t)
     or v_fp_bundles is distinct from (select md5(coalesce(string_agg(to_jsonb(b)::text, ',' order by b.id), '')) from public.premium_bundles b)
     or v_fp_pk is distinct from (select md5(coalesce(string_agg(to_jsonb(p)::text, ',' order by p.id), '')) from public.credit_packages p)
     or v_fp_rules is distinct from (select md5(coalesce(string_agg((to_jsonb(t) - 'is_active' - 'updated_at')::text, ',' order by t.id), ''))
                                       from public.therapy_package_rules t)
     or exists (select 1 from public.therapy_package_rules where is_active and deleted_at is null)
     or (select count(*) from public.audit_logs where action = 'legacy_reward_cancelled' and reason = c_reason and changed_by = v_who) <> v_a_cancel + c_cust_rows + c_aff_rows
     or (select count(*) from public.audit_logs where action = 'legacy_rule_upserted' and changed_by = v_who) <> v_a_upsert + c_rules
     or (select count(*) from public.audit_logs where action = 'legacy_rule_switched_off' and reason = c_reason and changed_by = v_who) <> v_a_off + c_rules
     or (select count(*) from public.audit_logs where action = 'legacy_therapy_retired' and reason = c_reason and changed_by = v_who) <> v_a_sum + 1 then
    raise exception '502 go-live: what it left is not what was planned. Nothing changed.'; end if;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
end $golive$;
