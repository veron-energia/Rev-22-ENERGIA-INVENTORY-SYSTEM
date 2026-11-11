-- UNDO of the 502 go-live step 2b, scripts/therapy/legacy-retired-golive-502.sql (with the user's
-- go-ahead; the go-live suite runs it). It puts back the 103 Legacy rewards that step cancelled,
-- each exactly as it was (waiting to be claimed, with its claim-by date), and switches the 3
-- qualification rules it switched off back on, through the rule form's own function
-- (upsert_legacy_rule). One Audit Log row for each reward (legacy_reward_cancel_undone) and each
-- rule (legacy_rule_switched_on), and one for the whole (legacy_therapy_retired_undone).
--
-- It finds what to put back by that step's reason and its Audit Log rows, and refuses, with
-- nothing changed, unless it finds exactly the 103 rewards and 3 rules, as that step left them
-- (if vouchers were handed over from one of them since, or it changed otherwise, it names that
-- reward: ask the user).
-- Its constants are step 2b's: c_rewards = 2b's c_cust_rows + c_aff_rows, and c_rules. If 2b's
-- were changed at go-live, change these with them (the go-live suite checks that they agree).
-- It needs 502 in: with 502 in, paying an invoice never recounts a day, so nothing cancels the
-- rewards again or drops their invoice links while they are put back. (Undone after 502, the
-- recount would run with the rules off and drop the links of every day whose rewards are all
-- cancelled.)
--
-- What it does not undo: Credit Packages (scripts/therapy/undo-credit-package-credit-only-502.sql,
-- next), and what happened while the step was in (a customer deleted stays deleted).
--
-- ROLLBACK ORDER: revert the pages -> THIS FILE -> scripts/therapy/undo-credit-package-credit-only-502.sql
-- -> scripts/therapy/undo-502.sql.
-- HOW: one transaction, all or nothing, with the recording account (an active Owner or Manager)
-- set first in the same transaction, as in the step's own header. Run again, it refuses and
-- changes nothing.
do $undo$
declare
  c_reason constant text := 'Legacy Therapy retired (decision of 10 Nov 2026)';   -- step 2b's
  c_undo_reason constant text := 'Undone: Legacy Therapy retired (decision of 10 Nov 2026)';
  -- 502 is in: its AFTER md5, read with public alone on the search path.
  c_trg_after constant text := '7b63da063576a5c952cc5abe6c53f13d';   -- trg_create_therapy_on_paid()
  -- What step 2b changed, as it was planned on 10 Nov 2026
  c_rewards constant int := 103;   -- 102 one-month rewards and 1 affiliate reward
  c_rules constant int := 3;
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_who uuid;
  v_cancel jsonb; v_ids uuid[]; v_rules uuid[]; v_bad text;
  v_fp_keep text; v_fp_w text; v_fp_crv text; v_fp_links text; v_fp_bundles text; v_fp_pk text; v_fp_rules text;
  v_a_back int; v_a_on int; v_a_upsert int; v_a_sum int;
  r record; n int := 0; n_rules int := 0;
begin
  perform set_config('lock_timeout', '5s', true);
  perform set_config('search_path', 'public', true);   -- md5s are read with public alone

  -- 0. Who records it, and 502 is in.
  if coalesce(current_setting('request.jwt.claim.sub', true), '') = ''
     or coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')
          <> current_setting('request.jwt.claim.sub', true)
     or not public.is_owner_or_manager() then
    raise exception 'UNDO 502 go-live: set the recording account (an active Owner or Manager) first, in this transaction: request.jwt.claim.sub and request.jwt.claims. Nothing changed.'; end if;
  v_who := auth.uid();
  if md5(pg_get_functiondef('public.trg_create_therapy_on_paid()'::regprocedure)) <> c_trg_after then
    raise exception 'UNDO 502 go-live: migration 502 is not in, so paying an invoice would recount days while the rewards are put back. Run this before scripts/therapy/undo-502.sql. Nothing changed.'; end if;

  -- 1. What step 2b cancelled and has not been put back: its Audit Log rows, each on a reward
  --    still cancelled with its reason, one for each reward.
  v_cancel := (select coalesce(jsonb_agg(jsonb_build_object('audit_id', a.id, 'record_id', a.record_id, 'old_data', a.old_data)
                                          order by a.record_id), '[]'::jsonb)
                 from public.audit_logs a
                where a.action = 'legacy_reward_cancelled' and a.reason = c_reason
                  and not exists (select 1 from public.audit_logs u
                                   where u.action = 'legacy_reward_cancel_undone'
                                     and u.new_data ->> 'cancel_audit_id' = a.id::text));
  v_ids := array(select (x ->> 'record_id')::uuid from jsonb_array_elements(v_cancel) x);
  if cardinality(v_ids) <> c_rewards
     or (select count(distinct x ->> 'record_id') from jsonb_array_elements(v_cancel) x) <> c_rewards
     or (select count(*) from public.therapy_entitlements e where e.id = any(v_ids)
          and e.status = 'cancelled' and e.revoked_reason = c_reason) <> c_rewards
     or (select count(*) from public.therapy_entitlements where status = 'cancelled' and revoked_reason = c_reason) <> c_rewards then
    raise exception 'UNDO 502 go-live: found % rewards cancelled by the go-live step and not put back, not % as it left them. Nothing changed.', cardinality(v_ids), c_rewards; end if;
  -- Each as the step left it: what it was is in its Audit Log row, and nothing was handed over
  -- from it since.
  v_bad := (select string_agg(e.entitlement_no, ', ' order by e.entitlement_no)
              from jsonb_array_elements(v_cancel) x join public.therapy_entitlements e on e.id = (x ->> 'record_id')::uuid
             where x -> 'old_data' ->> 'status' is distinct from 'pending_activation'
                or x -> 'old_data' ->> 'entitlement_no' is distinct from e.entitlement_no
                or x -> 'old_data' ->> 'earner_kind' is distinct from e.earner_kind
                or (x -> 'old_data' ->> 'claim_by')::date is distinct from e.activation_deadline
                or not (x -> 'old_data' ? 'revoked_qty' and x -> 'old_data' ? 'revoked_at' and x -> 'old_data' ? 'revoked_reason')
                or e.revoked_qty is distinct from case when coalesce(e.entitlement_kind, '') = 'voucher' then coalesce(e.voucher_qty, 0)
                                                      else (x -> 'old_data' ->> 'revoked_qty')::int end
                or e.claimed_at is not null
                or public.entitlement_claimed_qty(e.id) <> 0);
  if v_bad is not null then
    raise exception 'UNDO 502 go-live: reward % is not as the go-live step left it (vouchers handed over from it, or changed since). Ask the user. Nothing changed.', v_bad; end if;

  -- The rules it switched off and are still off.
  v_rules := (select coalesce(array_agg(distinct a.record_id), '{}')
                from public.audit_logs a
               where a.action = 'legacy_rule_switched_off' and a.reason = c_reason
                 and not exists (select 1 from public.audit_logs u
                                  where u.action = 'legacy_rule_switched_on'
                                    and u.new_data ->> 'switched_off_audit_id' = a.id::text));
  if cardinality(v_rules) <> c_rules
     or (select count(*) from public.therapy_package_rules t
          where t.id = any(v_rules) and not t.is_active and t.deleted_at is null) <> c_rules then
    raise exception 'UNDO 502 go-live: found % rules switched off by the go-live step and still off, not %. Nothing changed.', cardinality(v_rules), c_rules; end if;

  -- What must not change: every other reward, the rest of each one put back, the vouchers handed
  -- over from Legacy rewards, the invoice links, Premium Bundles, Credit Packages, and the rules
  -- but for being on.
  v_fp_keep := (select md5(coalesce(string_agg(to_jsonb(e)::text, ',' order by e.id), ''))
                  from public.therapy_entitlements e where not (e.id = any(v_ids)));
  v_fp_w := (select md5(coalesce(string_agg((to_jsonb(e) - 'status' - 'revoked_qty' - 'revoked_at' - 'revoked_reason')::text, ',' order by e.id), ''))
               from public.therapy_entitlements e where e.id = any(v_ids));
  v_fp_crv := (select md5(coalesce(string_agg(to_jsonb(v)::text, ',' order by v.id), ''))
                 from public.customer_reward_vouchers v join public.therapy_entitlements e on e.id = v.entitlement_id
                where e.earner_kind in ('customer', 'affiliate'));
  v_fp_links := (select md5(coalesce(string_agg(to_jsonb(t)::text, ',' order by t.id), '')) from public.therapy_entitlement_invoices t);
  v_fp_bundles := (select md5(coalesce(string_agg(to_jsonb(b)::text, ',' order by b.id), '')) from public.premium_bundles b);
  v_fp_pk := (select md5(coalesce(string_agg(to_jsonb(p)::text, ',' order by p.id), '')) from public.credit_packages p);
  v_fp_rules := (select md5(coalesce(string_agg((to_jsonb(t) - 'is_active' - 'updated_at')::text, ',' order by t.id), ''))
                   from public.therapy_package_rules t);
  v_a_back := (select count(*) from public.audit_logs where action = 'legacy_reward_cancel_undone' and reason = c_undo_reason and changed_by = v_who);
  v_a_on := (select count(*) from public.audit_logs where action = 'legacy_rule_switched_on' and reason = c_undo_reason and changed_by = v_who);
  v_a_upsert := (select count(*) from public.audit_logs where action = 'legacy_rule_upserted' and changed_by = v_who);
  v_a_sum := (select count(*) from public.audit_logs where action = 'legacy_therapy_retired_undone' and reason = c_undo_reason and changed_by = v_who);

  -- 2. The rewards back as they were, one Audit Log row each.
  for r in select (x ->> 'audit_id')::uuid as audit_id, x -> 'old_data' as old_data, e.*
             from jsonb_array_elements(v_cancel) x join public.therapy_entitlements e on e.id = (x ->> 'record_id')::uuid
            order by e.created_at, e.id for update of e loop
    update public.therapy_entitlements
       set status = r.old_data ->> 'status',
           revoked_qty = (r.old_data ->> 'revoked_qty')::int,
           revoked_at = (r.old_data ->> 'revoked_at')::timestamptz,
           revoked_reason = r.old_data ->> 'revoked_reason'
     where id = r.id and status = 'cancelled' and revoked_reason = c_reason;
    if not found then raise exception 'UNDO 502 go-live: % changed while this ran. Nothing changed.', r.entitlement_no; end if;
    perform public.write_audit_ex('therapy_entitlements', r.id, 'legacy_reward_cancel_undone',
      jsonb_build_object('status', 'cancelled', 'reason', c_reason, 'revoked_qty', r.revoked_qty),
      jsonb_build_object('status', r.old_data ->> 'status', 'entitlement_no', r.entitlement_no,
                         'claim_by', r.activation_deadline, 'cancel_audit_id', r.audit_id),
      'therapy', c_undo_reason, r.store_id);
    n := n + 1;
  end loop;

  -- 3. The rules back on, through the rule form's own function, with their own values.
  for r in select a.id as audit_id, t.* from public.therapy_package_rules t
             join public.audit_logs a on a.record_id = t.id
            where t.id = any(v_rules)
              and a.action = 'legacy_rule_switched_off' and a.reason = c_reason
              and not exists (select 1 from public.audit_logs u
                               where u.action = 'legacy_rule_switched_on'
                                 and u.new_data ->> 'switched_off_audit_id' = a.id::text)
            order by t.applies_to, t.entitlement_kind, t.id loop
    perform public.upsert_legacy_rule(r.id, r.store_id, r.name, r.qualifying_amount, r.entitlement_kind,
      r.duration_months, r.voucher_qty, r.activation_deadline_days, true, null, r.applies_to);
    perform public.write_audit_ex('therapy_package_rules', r.id, 'legacy_rule_switched_on',
      jsonb_build_object('is_active', false),
      jsonb_build_object('is_active', true, 'name', r.name, 'applies_to', r.applies_to,
                         'qualifying_amount', r.qualifying_amount, 'switched_off_audit_id', r.audit_id),
      'therapy', c_undo_reason, null);
    n_rules := n_rules + 1;
  end loop;

  -- 4. One line for the Audit Log page.
  perform public.write_audit_ex('therapy_entitlements', null, 'legacy_therapy_retired_undone', null,
    jsonb_build_object('rewards_put_back', n, 'rules_switched_on', n_rules), 'therapy', c_undo_reason, null);

  -- 5. What it leaves: the 103 waiting again as they were, with their claim-by dates; the 3 rules
  --    on; nothing else changed.
  if n <> c_rewards or n_rules <> c_rules
     or exists (select 1 from public.therapy_entitlements where status = 'cancelled' and revoked_reason = c_reason)
     or exists (select 1 from jsonb_array_elements(v_cancel) x join public.therapy_entitlements e on e.id = (x ->> 'record_id')::uuid
                 where e.status is distinct from 'pending_activation'
                    or e.activation_deadline is distinct from (x -> 'old_data' ->> 'claim_by')::date
                    or e.revoked_qty is distinct from (x -> 'old_data' ->> 'revoked_qty')::int
                    or e.revoked_at is distinct from (x -> 'old_data' ->> 'revoked_at')::timestamptz
                    or e.revoked_reason is distinct from x -> 'old_data' ->> 'revoked_reason')
     or (select count(*) from public.therapy_package_rules t where t.id = any(v_rules) and t.is_active) <> c_rules
     or v_fp_keep is distinct from (select md5(coalesce(string_agg(to_jsonb(e)::text, ',' order by e.id), ''))
                                      from public.therapy_entitlements e where not (e.id = any(v_ids)))
     or v_fp_w is distinct from (select md5(coalesce(string_agg((to_jsonb(e) - 'status' - 'revoked_qty' - 'revoked_at' - 'revoked_reason')::text, ',' order by e.id), ''))
                                   from public.therapy_entitlements e where e.id = any(v_ids))
     or v_fp_crv is distinct from (select md5(coalesce(string_agg(to_jsonb(v)::text, ',' order by v.id), ''))
                                     from public.customer_reward_vouchers v join public.therapy_entitlements e on e.id = v.entitlement_id
                                    where e.earner_kind in ('customer', 'affiliate'))
     or v_fp_links is distinct from (select md5(coalesce(string_agg(to_jsonb(t)::text, ',' order by t.id), '')) from public.therapy_entitlement_invoices t)
     or v_fp_bundles is distinct from (select md5(coalesce(string_agg(to_jsonb(b)::text, ',' order by b.id), '')) from public.premium_bundles b)
     or v_fp_pk is distinct from (select md5(coalesce(string_agg(to_jsonb(p)::text, ',' order by p.id), '')) from public.credit_packages p)
     or v_fp_rules is distinct from (select md5(coalesce(string_agg((to_jsonb(t) - 'is_active' - 'updated_at')::text, ',' order by t.id), ''))
                                       from public.therapy_package_rules t)
     or (select count(*) from public.audit_logs where action = 'legacy_reward_cancel_undone' and reason = c_undo_reason and changed_by = v_who) <> v_a_back + c_rewards
     or (select count(*) from public.audit_logs where action = 'legacy_rule_switched_on' and reason = c_undo_reason and changed_by = v_who) <> v_a_on + c_rules
     or (select count(*) from public.audit_logs where action = 'legacy_rule_upserted' and changed_by = v_who) <> v_a_upsert + c_rules
     or (select count(*) from public.audit_logs where action = 'legacy_therapy_retired_undone' and reason = c_undo_reason and changed_by = v_who) <> v_a_sum + 1 then
    raise exception 'UNDO 502 go-live: what it left is not what was planned. Nothing changed.'; end if;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
end $undo$;
