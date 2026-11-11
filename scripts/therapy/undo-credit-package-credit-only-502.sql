-- UNDO of the 502 go-live step 2a, scripts/therapy/credit-package-credit-only-502.sql (with the
-- user's go-ahead; the go-live suite runs it). It switches the reward back on for exactly the 3
-- Credit Packages that step switched off, so a Credit Package sale paid off from then on gives
-- reward vouchers again, and marks the earlier sale that step recorded as no longer kept: paid off
-- with the reward back on, it gets its reward vouchers the usual way, so
-- scripts/therapy/credit-package-presale-reward-502.sql then refuses.
-- One Audit Log row for each package (credit_package_reward_switched_on) and for the earlier sale
-- (credit_package_reward_kept_for_earlier_sale_undone).
--
-- The reward is switched back on by a direct update: with 502 in, the Credit Package window's
-- own function (set_catalogue_reward) refuses to switch a Credit Package's reward on.
--
-- It refuses, with nothing changed:
--   * while step 2b is in (scripts/therapy/legacy-retired-golive-502.sql: rules it switched off and
--     not switched back on, or rewards it cancelled): undo that first;
--   * unless it finds exactly the 3 packages that step switched off, still off, and the 1 earlier
--     sale it recorded, not undone;
--   * once that earlier sale has been paid off: its reward vouchers were given by
--     credit-package-presale-reward-502.sql, or are still owed (it was paid off with credit only),
--     and undoing this step would lose the record of them. Those stay as they are; ask the user.
-- What happened while the step was in stays: Credit Package sales paid off meanwhile keep their
-- credit only.
--
-- ROLLBACK ORDER: revert the pages -> scripts/therapy/undo-legacy-retired-golive-502.sql ->
-- THIS FILE -> scripts/therapy/undo-502.sql.
-- HOW: one transaction, all or nothing, with the recording account (an active Owner or Manager)
-- set first in the same transaction, as in the step's own header. Run again, it refuses and
-- changes nothing.
do $undo$
declare
  c_reason constant text := 'Credit Packages give credit only (decision of 10 Nov 2026)';          -- step 2a's
  c_golive_reason constant text := 'Legacy Therapy retired (decision of 10 Nov 2026)';              -- step 2b's
  c_undo_reason constant text := 'Undone: Credit Packages give credit only (decision of 10 Nov 2026)';
  -- What step 2a changed, as it was planned on 10 Nov 2026: step 2a's c_packages and c_kept_lines.
  -- If those were changed at go-live, change these with them (the go-live suite checks that they
  -- agree).
  c_packages constant int := 3;
  c_kept_lines constant int := 1;
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_who uuid;
  v_off jsonb; v_kept jsonb; v_pk uuid[];
  v_fp_pk text; v_a_on int; v_a_kept int;
  r record; n int := 0; n_kept int := 0;
begin
  perform set_config('lock_timeout', '5s', true);
  perform set_config('search_path', 'public', true);

  -- 0. Who records it.
  if coalesce(current_setting('request.jwt.claim.sub', true), '') = ''
     or coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')
          <> current_setting('request.jwt.claim.sub', true)
     or not public.is_owner_or_manager() then
    raise exception 'UNDO 502 credit only: set the recording account (an active Owner or Manager) first, in this transaction: request.jwt.claim.sub and request.jwt.claims. Nothing changed.'; end if;
  v_who := auth.uid();

  -- Step 2b is undone first.
  if exists (select 1 from public.audit_logs a
              where a.action = 'legacy_rule_switched_off' and a.reason = c_golive_reason
                and not exists (select 1 from public.audit_logs u
                                 where u.action = 'legacy_rule_switched_on'
                                   and u.new_data ->> 'switched_off_audit_id' = a.id::text))
     or exists (select 1 from public.therapy_entitlements where status = 'cancelled' and revoked_reason = c_golive_reason) then
    raise exception 'UNDO 502 credit only: the go-live step that cancelled the Legacy rewards is still in. Run scripts/therapy/undo-legacy-retired-golive-502.sql first. Nothing changed.'; end if;

  -- 1. What step 2a switched off and has not been switched back on: one Audit Log row for each of
  --    the 3 packages, each package still off.
  v_off := (select coalesce(jsonb_agg(jsonb_build_object('audit_id', a.id, 'package_id', a.record_id) order by a.record_id), '[]'::jsonb)
              from public.audit_logs a
             where a.action = 'credit_package_reward_switched_off' and a.reason = c_reason
               and not exists (select 1 from public.audit_logs u
                                where u.action = 'credit_package_reward_switched_on'
                                  and u.new_data ->> 'switched_off_audit_id' = a.id::text));
  v_pk := array(select (x ->> 'package_id')::uuid from jsonb_array_elements(v_off) x);
  if cardinality(v_pk) <> c_packages
     or (select count(distinct x ->> 'package_id') from jsonb_array_elements(v_off) x) <> c_packages
     or (select count(*) from public.credit_packages p where p.id = any(v_pk) and not p.grants_reward) <> c_packages then
    raise exception 'UNDO 502 credit only: found % Credit Packages switched off by step 2a and still off, not %. Nothing changed.', cardinality(v_pk), c_packages; end if;

  -- The earlier sale it recorded, not undone.
  v_kept := (select coalesce(jsonb_agg(jsonb_build_object('audit_id', a.id, 'line_id', a.record_id, 'invoice_no', a.new_data ->> 'invoice_no',
                                                          'given', exists (select 1 from public.audit_logs g
                                                                            where g.action = 'credit_package_earlier_sale_reward_given'
                                                                              and g.new_data ->> 'kept_audit_id' = a.id::text),
                                                          'paid_off', coalesce((select it.credit_issued_at is not null from public.invoice_items it where it.id = a.record_id), false))
                                         order by a.record_id), '[]'::jsonb)
               from public.audit_logs a
              where a.action = 'credit_package_reward_kept_for_earlier_sale' and a.reason = c_reason
                and not exists (select 1 from public.audit_logs u
                                 where u.action = 'credit_package_reward_kept_for_earlier_sale_undone'
                                   and u.new_data ->> 'kept_audit_id' = a.id::text));
  if jsonb_array_length(v_kept) <> c_kept_lines then
    raise exception 'UNDO 502 credit only: found % earlier sales recorded by step 2a and not undone, not %. Nothing changed.', jsonb_array_length(v_kept), c_kept_lines; end if;
  if exists (select 1 from jsonb_array_elements(v_kept) x where (x ->> 'given')::boolean) then
    raise exception 'UNDO 502 credit only: the earlier sale on invoice % has had its reward vouchers given (credit-package-presale-reward-502.sql). They stay; this is not undone. Ask the user. Nothing changed.',
      (select string_agg(x ->> 'invoice_no', ', ') from jsonb_array_elements(v_kept) x where (x ->> 'given')::boolean); end if;
  if exists (select 1 from jsonb_array_elements(v_kept) x where (x ->> 'paid_off')::boolean) then
    raise exception 'UNDO 502 credit only: the earlier sale on invoice % was paid off with credit only, and its reward vouchers are still owed (credit-package-presale-reward-502.sql, with the user''s OK). Undoing this step would lose the record of them. Ask the user. Nothing changed.',
      (select string_agg(coalesce(x ->> 'invoice_no', x ->> 'line_id'), ', ') from jsonb_array_elements(v_kept) x where (x ->> 'paid_off')::boolean); end if;

  -- What must not change: the packages but for the reward.
  v_fp_pk := (select md5(coalesce(string_agg((to_jsonb(p) - 'grants_reward' - 'updated_at')::text, ',' order by p.id), ''))
                from public.credit_packages p);
  v_a_on := (select count(*) from public.audit_logs where action = 'credit_package_reward_switched_on' and reason = c_undo_reason and changed_by = v_who);
  v_a_kept := (select count(*) from public.audit_logs where action = 'credit_package_reward_kept_for_earlier_sale_undone' and reason = c_undo_reason and changed_by = v_who);

  -- 2. The reward back on for those 3 packages (a direct update: 502's set_catalogue_reward
  --    refuses to switch it on).
  for r in select (x ->> 'audit_id')::uuid as audit_id, p.id, p.name
             from jsonb_array_elements(v_off) x join public.credit_packages p on p.id = (x ->> 'package_id')::uuid
            order by p.id for update of p loop
    update public.credit_packages set grants_reward = true, updated_at = now() where id = r.id and not grants_reward;
    if not found then raise exception 'UNDO 502 credit only: the package % changed while this ran. Nothing changed.', r.name; end if;
    perform public.write_audit_ex('credit_packages', r.id, 'credit_package_reward_switched_on',
      jsonb_build_object('grants_reward', false),
      jsonb_build_object('grants_reward', true, 'package', r.name, 'switched_off_audit_id', r.audit_id),
      'catalogue', c_undo_reason, null);
    n := n + 1;
  end loop;

  -- 3. The earlier sale is no longer kept: paid off with the reward on, it gets its reward the
  --    usual way.
  for r in select (x ->> 'audit_id')::uuid as audit_id, (x ->> 'line_id')::uuid as line_id, x ->> 'invoice_no' as invoice_no
             from jsonb_array_elements(v_kept) x loop
    perform public.write_audit_ex('invoice_items', r.line_id, 'credit_package_reward_kept_for_earlier_sale_undone', null,
      jsonb_build_object('kept_audit_id', r.audit_id, 'invoice_no', r.invoice_no), 'invoices', c_undo_reason,
      (select i.store_id from public.invoice_items it join public.invoices i on i.id = it.invoice_id where it.id = r.line_id));
    n_kept := n_kept + 1;
  end loop;

  -- 4. What it leaves.
  if n <> c_packages or n_kept <> c_kept_lines
     or (select count(*) from public.credit_packages p where p.id = any(v_pk) and p.grants_reward) <> c_packages
     or exists (select 1 from public.credit_packages p where p.grants_reward and not (p.id = any(v_pk)))
     or v_fp_pk is distinct from (select md5(coalesce(string_agg((to_jsonb(p) - 'grants_reward' - 'updated_at')::text, ',' order by p.id), ''))
                                    from public.credit_packages p)
     or exists (select 1 from public.audit_logs a
                 where a.action in ('credit_package_reward_switched_off', 'credit_package_reward_kept_for_earlier_sale') and a.reason = c_reason
                   and not exists (select 1 from public.audit_logs u
                                    where (u.action = 'credit_package_reward_switched_on' and u.new_data ->> 'switched_off_audit_id' = a.id::text)
                                       or (u.action = 'credit_package_reward_kept_for_earlier_sale_undone' and u.new_data ->> 'kept_audit_id' = a.id::text)))
     or (select count(*) from public.audit_logs where action = 'credit_package_reward_switched_on' and reason = c_undo_reason and changed_by = v_who) <> v_a_on + c_packages
     or (select count(*) from public.audit_logs where action = 'credit_package_reward_kept_for_earlier_sale_undone' and reason = c_undo_reason and changed_by = v_who) <> v_a_kept + c_kept_lines then
    raise exception 'UNDO 502 credit only: what it left is not what was planned. Nothing changed.'; end if;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
end $undo$;
