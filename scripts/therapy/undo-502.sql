-- UNDO of 502 (with the user's go-ahead; the suite runs it). It puts the 15 functions 502 patched
-- back to their text before 502, attaches the refund guard trigger legacy_refund_guard to invoices
-- again (same definition, so it keeps its place among the BEFORE UPDATE triggers), lets signed-in
-- logins call the 13 functions only Legacy used again, and takes the "retired" comment off the 4
-- recounts. From then on paying an invoice recounts the customer's and the affiliate's day again.
--
-- It refuses, with nothing changed, unless every one of the 15 functions is exactly 502's version
-- (so a later version is never overwritten), and while the go-live script's cancellations are in
-- place: with them in place, the recount put back would drop the record of which invoices earned
-- a reward for every day whose rewards are all cancelled.
--
-- ROLLBACK ORDER: revert the pages -> scripts/therapy/undo-legacy-retired-golive-502.sql ->
-- scripts/therapy/undo-credit-package-credit-only-502.sql -> this file. The pages must already be
-- reverted: the new Therapy page asks for the list 'vouchers', which the version put back refuses.
-- What happened while 502 was in stays: sales, hand-overs, refunds and deletions.
-- One transaction, all or nothing. It waits at most 5 seconds for a lock.
--
-- AFTER A ROLLBACK, two things stay as 502 left them:
--   * Days paid, part-paid, refunded or cancelled while 502 was in were not recounted (with 502
--     in, nothing recounts a day), and this file does not recount them. Left alone, such a day is
--     recounted only when another invoice of it changes, so a reward may appear or go later, by
--     chance. With the user's OK, an Owner or Manager runs "Re-check paid days"
--     (backfill_legacy_qualification, which signed-in logins can call again once this has run)
--     from the go-live date to today, all stores. It recounts the days that still have a paid or
--     part-paid invoice; a day whose invoices were all refunded or cancelled meanwhile is not
--     among them, so list those days and ask the user.
--   * The 502 row in supabase_migrations.schema_migrations stays: the history still says 502 is
--     in, so applying 502 again with its history row is refused (it is already recorded). With
--     the user's OK, either remove that one row, found by its name (502_legacy_therapy_retired)
--     and the md5 of its stored statements (the md5 of supabase/502_legacy_therapy_retired.sql as
--     applied), or leave it and record this UNDO beside it.
do $undo$
declare
  -- The functions 502 patches: BEFORE (as before 502) and AFTER (502's) md5s
  c_sig constant text[] := array[
    'trg_create_therapy_on_paid()',
    'backfill_legacy_qualification(date,date,uuid)',
    'therapy_list_page(text,text,text,integer,integer)',
    'delete_customer(uuid,text,text)',
    'customer_overview(uuid)',
    'report_therapy()',
    'dashboard_alerts_summary()',
    'therapy_customer_summary(text,integer,integer,boolean)',
    'therapy_customer_detail(uuid)',
    'therapy_customer_voucher_balances(uuid)',
    'set_catalogue_reward(text,uuid,boolean)',
    'upsert_credit_package(uuid,text,numeric,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,numeric,text,uuid[],uuid[],boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,numeric)',
    'assert_invoice_credit_source_evidence(uuid,uuid)',
    'invoice_benefit_review_options(uuid)',
    'resolve_invoice_credit_rewards(uuid,text,uuid,boolean,uuid)'];
  c_before constant text[] := array[
    '012ae4e305b9870fa5596f740c0427b9',
    '00fe803a88ef5fd30acbfe151d87ae66',
    'fa78a96f7fbb74d770b54a8b700ad4b4',
    '5b407735574fc3cacd8067c4dc8213f4',
    '74e9cddfb699ed78369ee4d01578116e',
    'f3d9575eea995494c153240a3d9b72df',
    '2b632d0dcc23b82c6ef4e1438271debf',
    '55b69d8530418f74416bce23e3bdaa66',
    '80abbc0a7b61f91c0a4248f9b18d8f4e',
    '935a3268c6a9b46447d979f85eaa867e',
    '0987f23df3fbb1863346c4c46c04fad2',
    '08f822f0e1c4ad41aa4b0e4b8582d0e5',
    '64059b05526f32239ce1e60c6de39508',
    'a7ee838459a52741501d1c019fffcbee',
    '828a4b535604aef1314f55453d67f6e2'];
  c_after constant text[] := array[
    '7b63da063576a5c952cc5abe6c53f13d',
    '40e44a1cdf43f336d765cdb2bd0f8235',
    '729ae2d27eadbf2a996dac13d608629c',
    'b1f3b08c85ef55f54effa7830d87eed1',
    '91912a72aab437420f16cd7fe3b67da2',
    'f43af7b0f6a8a80054808ab6fb672d59',
    '71c01b0053937347a63b311b7eca5734',
    'af030b297c6ab5dc2c64bde101722279',
    '8c9143f82bfda412f26e743dbad47181',
    '92e722a77520f3c2a8e6370816598a0e',
    'a8a9c9ae3862a348217cc434185f9781',
    'a2e8ec73a38b60ae7c05f573fba25ea8',
    'fccb792813962e2aae95db9e4dc8d3b6',
    '4e382ae362f077eed9ae941ad3c9e930',
    'faeb135e402b5b5d7bdfccadc19553fc'];
  -- Each patch: which function (its place in c_sig), 502's anchor and the text 502 put in its
  -- place. This file swaps each text back for its anchor.
  c_fn constant int[] := array[1, 2, 3, 3, 3, 3, 3, 4, 5, 6, 7, 7, 8, 9, 9, 9, 10, 11, 12, 12, 13, 14, 15];
  c_anchor constant text[] := array[
  -- P1 trg_create_therapy_on_paid: the recount is no longer called
$a$    if new.customer_id is not null and new.store_id is not null then
      perform public.recompute_legacy_qualification(new.customer_id, new.store_id, v_day);
      perform public.recompute_affiliates_for_customer_day(new.customer_id, v_day);
    end if;$a$,
  -- P2 backfill_legacy_qualification: refuses
$a$  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can run the qualification backfill';
  end if;$a$,
  -- P3 therapy_list_page: Vouchers to hand over
$a$  --   p_tab     'purchased' or 'legacy'.$a$,
$a$  elsif p_tab = 'legacy' then$a$,
$a$        left join public.invoices si on si.id = te.claim_source_invoice_id
       where public.user_has_store_access(te.store_id)$a$,
$a$    raise exception 'Unknown list: % (purchased or legacy)', coalesce(p_tab, 'none');$a$,
$a$case when p_tab = 'legacy' then 'open' else 'all' end$a$,
  -- P4 delete_customer: only vouchers still owed stop a delete
$a$  select count(*) into v_open from public.therapy_entitlements t
   where t.customer_id = p_customer_id and t.status in ('active', 'pending_activation');
  if v_open > 0 then
    raise exception 'This customer has % legacy therapy entitlement(s) still open. Settle them first.', v_open;
  end if;$a$,
  -- P5 customer_overview: vouchers_to_hand_over replaces legacy_therapy
$a$    'legacy_therapy', coalesce((select jsonb_agg(jsonb_build_object(
        'no', le.entitlement_no, 'package', le.package_name, 'status', le.status,
        'deadline', le.activation_deadline) order by le.created_at desc)
      from public.therapy_entitlements le where le.customer_id = p_customer_id), '[]'::jsonb),$a$,
  -- P6 report_therapy: no Legacy rows
$a$  where public.is_manager_or_above() and public.user_has_store_access(le.store_id)$a$,
  -- P7 dashboard_alerts_summary: the two Legacy branches go
$a$
                                   or e.id in (select ti.entitlement_id from public.therapy_entitlement_invoices ti
                                                where ti.invoice_id = i.id)))$a$,
$a$
                                                               or e.id in (select ti.entitlement_id from public.therapy_entitlement_invoices ti
                                                                            where ti.invoice_id = i.id))))))$a$,
  -- P8 therapy_customer_summary: Legacy leaves the counts
$a$          from public.therapy_entitlements
         where coalesce(entitlement_kind, 'unlimited') = 'unlimited'$a$,
  -- P9 therapy_customer_detail: Legacy leaves both lists; the label is reworded
$a$            from public.therapy_entitlements l
           where l.customer_id = p_customer_id
             and coalesce(l.entitlement_kind, 'unlimited') = 'unlimited'$a$,
$a$           where l.customer_id = p_customer_id and l.status = 'pending_activation'$a$,
$a$          'source', case u.k when 'purchased' then 'Purchased' else 'Legacy qualification' end,$a$,
  -- P10 therapy_customer_voucher_balances: the source label
$a$           when 'legacy_entitlement' then 'Legacy qualification reward'$a$,
  -- P11 set_catalogue_reward: a Credit Package reward can only be switched off
$a$  if p_kind = 'credit_package' then
    update public.credit_packages set grants_reward = coalesce(p_grants,false), updated_at = now() where id = p_id;$a$,
  -- P12 upsert_credit_package: a new package starts with the reward off
$a$      bonus_enabled, bonus_mode, bonus_value)
    values (trim(p_name)$a$,
$a$      coalesce(p_bonus_enabled,false), coalesce(p_bonus_mode,'fixed'), coalesce(p_bonus_value,0))
    returning id into v_id;$a$,
  -- P13 assert_invoice_credit_source_evidence: the refund and cancel refusal
$a$  raise exception 'This package granted qualification reward entitlements that are still outstanding. '
    'Review them and record what should happen to them, then refund or cancel — unclaimed ones are withdrawn and claimed ones keep their history.';$a$,
  -- P14 invoice_benefit_review_options: the review note
$a$   issue:='Qualification rewards require original entitlement and redemption review; credit-only allocations cannot complete this purchase.';$a$,
  -- P15 resolve_invoice_credit_rewards: the permission refusal
$a$  raise exception 'Only an Owner or Manager can resolve qualification rewards' using errcode='42501'; end if;$a$];
  c_new constant text[] := array[
  -- P1 trg_create_therapy_on_paid: the recount is no longer called
$n$    -- 502 (the user, 10 Nov 2026): Legacy Therapy is retired. A payment, part-payment,
    -- correction, reopening, cancellation or refund no longer recounts the customer's day or the
    -- affiliate's day: nothing new is earned, nothing already earned is cancelled, and the record
    -- of which invoices earned a reward stays. (v_day, worked out above, is no longer read.)$n$,
  -- P2 backfill_legacy_qualification: refuses
$n$  -- 502 (the user, 10 Nov 2026): Legacy Therapy is retired, so no paid day is re-checked. A run
  -- would recount every paid day: it could earn or cancel rewards and drop the record of which
  -- invoices earned them.
  raise exception 'Legacy Therapy has been retired: paid days are no longer re-checked for rewards.';$n$,
  -- P3 therapy_list_page: Vouchers to hand over
$n$  --   p_tab     'purchased' or 'vouchers' (502; 'legacy', its old name, reads the same).$n$,
$n$  elsif p_tab in ('vouchers', 'legacy') then
    -- 502 (the user, 10 Nov 2026): Vouchers to hand over. Legacy rewards (earner_kind customer
    -- or affiliate, earned by a paid day) are history and are not listed; the rows left are the
    -- vouchers owed from a Credit Package, a Premium Bundle or a therapy package taken as
    -- vouchers. 'legacy' is the old page's name for this list and reads the same.$n$,
$n$        left join public.invoices si on si.id = te.claim_source_invoice_id
       where public.user_has_store_access(te.store_id)
         and te.earner_kind not in ('customer', 'affiliate')  -- 502: Legacy rewards are history$n$,
$n$    raise exception 'Unknown list: % (purchased or vouchers)', coalesce(p_tab, 'none');$n$,
$n$case when p_tab in ('vouchers', 'legacy') then 'open' else 'all' end$n$,
  -- P4 delete_customer: only vouchers still owed stop a delete
$n$  -- 502 (the user, 10 Nov 2026): only vouchers still owed stop a delete. A reward earned by a
  -- customer's or an affiliate's paid day (Legacy Therapy, retired) never does; nor does a
  -- reward fully handed over, withdrawn, past its collect-by date, or from a sale that was
  -- refunded or cancelled. A Credit Package, Premium Bundle or therapy-package reward with
  -- vouchers still to hand over does, and so does a live unlimited period.
  select count(*) into v_open from public.therapy_entitlements t
   where t.customer_id = p_customer_id
     and t.earner_kind not in ('customer', 'affiliate')
     and ((coalesce(t.entitlement_kind, '') = 'voucher' and t.status = 'pending_activation'
           and coalesce(t.voucher_qty, 0) - public.entitlement_claimed_qty(t.id) - coalesce(t.revoked_qty, 0) > 0
           and (t.activation_deadline is null or t.activation_deadline >= public.sg_today())
           and public.therapy_invoice_closed_reason(t.claim_source_invoice_id) is null)
       or (coalesce(t.entitlement_kind, 'unlimited') = 'unlimited'
           and t.status in ('pending_activation', 'scheduled', 'active')));
  if v_open > 0 then
    raise exception 'This customer still has % reward(s) with vouchers to hand over (Therapy → Vouchers to hand over). Hand them over, or refund or cancel the sale they came from, first.', v_open;
  end if;$n$,
  -- P5 customer_overview: vouchers_to_hand_over replaces legacy_therapy
$n$    -- 502 (the user, 10 Nov 2026): the vouchers still to hand over to this customer from a Credit
    -- Package, a Premium Bundle or a therapy package taken as vouchers, soonest deadline first.
    -- Legacy rewards are history and are not listed. (This replaces the key legacy_therapy.)
    'vouchers_to_hand_over', coalesce((select jsonb_agg(jsonb_build_object(
        'no', le.entitlement_no, 'package', le.package_name,
        'left', coalesce(le.voucher_qty, 0) - public.entitlement_claimed_qty(le.id) - coalesce(le.revoked_qty, 0),
        'entitled', coalesce(le.voucher_qty, 0),
        'deadline', le.activation_deadline,
        'deadline_passed', le.activation_deadline is not null and public.sg_today() > le.activation_deadline,
        'blocked_reason', public.therapy_invoice_closed_reason(le.claim_source_invoice_id))
        order by le.activation_deadline nulls last, le.created_at)
      from public.therapy_entitlements le where le.customer_id = p_customer_id
       and le.earner_kind not in ('customer', 'affiliate')
       and le.status = 'pending_activation'
       and coalesce(le.voucher_qty, 0) - public.entitlement_claimed_qty(le.id) - coalesce(le.revoked_qty, 0) > 0), '[]'::jsonb),$n$,
  -- P6 report_therapy: no Legacy rows
$n$  where public.is_manager_or_above() and public.user_has_store_access(le.store_id)
    -- 502 (the user, 10 Nov 2026): Legacy rewards are history and are not reported. The rows
    -- left are vouchers owed from a Credit Package, a Premium Bundle or a therapy package;
    -- is_legacy, a column name kept so the function keeps its shape, is true on them.
    and le.earner_kind not in ('customer', 'affiliate')$n$,
  -- P7 dashboard_alerts_summary: the two Legacy branches go
$n$))
                -- 502 (the user, 10 Nov 2026): a Legacy reward, linked to its invoices through
                -- therapy_entitlement_invoices, is history and holds nothing here.$n$,
$n$)))))
      -- 502 (the user, 10 Nov 2026): vouchers handed over from a Legacy reward are ordinary
      -- vouchers and no longer hold a refunded or cancelled sale in this alert.$n$,
  -- P8 therapy_customer_summary: Legacy leaves the counts
$n$          from public.therapy_entitlements
         where coalesce(entitlement_kind, 'unlimited') = 'unlimited'
           -- 502 (the user, 10 Nov 2026): Legacy rewards are history and are not counted.
           and earner_kind not in ('customer', 'affiliate')$n$,
  -- P9 therapy_customer_detail: Legacy leaves both lists; the label is reworded
$n$            from public.therapy_entitlements l
           where l.customer_id = p_customer_id
             and coalesce(l.entitlement_kind, 'unlimited') = 'unlimited'
             -- 502 (the user, 10 Nov 2026): Legacy rewards are history and are not shown.
             and l.earner_kind not in ('customer', 'affiliate')$n$,
$n$           where l.customer_id = p_customer_id and l.status = 'pending_activation'
             and l.earner_kind not in ('customer', 'affiliate')  -- 502: Legacy rewards are history$n$,
$n$          'source', case u.k when 'purchased' then 'Purchased' else 'Earlier reward' end,  -- 502 (the user, 10 Nov 2026)$n$,
  -- P10 therapy_customer_voucher_balances: the source label
$n$           -- 502 (the user, 10 Nov 2026): vouchers handed over from a Legacy reward stay as
           -- ordinary vouchers; their source no longer names Legacy.
           when 'legacy_entitlement' then 'Earlier reward'$n$,
  -- P11 set_catalogue_reward: a Credit Package reward can only be switched off
$n$  if p_kind = 'credit_package' then
    -- 502 (the user, 10 Nov 2026): a Credit Package gives credit only. Its reward can be
    -- switched off, never on; rewards already given keep their vouchers and refund review.
    if coalesce(p_grants, false) then
      raise exception 'A Credit Package no longer grants reward vouchers; it gives credit only.'; end if;
    update public.credit_packages set grants_reward = false, updated_at = now() where id = p_id;$n$,
  -- P12 upsert_credit_package: a new package starts with the reward off
$n$      bonus_enabled, bonus_mode, bonus_value, grants_reward)
    values (trim(p_name)$n$,
$n$      coalesce(p_bonus_enabled,false), coalesce(p_bonus_mode,'fixed'), coalesce(p_bonus_value,0),
      -- 502 (the user, 10 Nov 2026): a new Credit Package gives credit only, no reward vouchers.
      false)
    returning id into v_id;$n$,
  -- P13 assert_invoice_credit_source_evidence: the refund and cancel refusal
$n$  -- 502 (the user, 10 Nov 2026): no longer says qualification. The page opens the reward review
  -- on "reward vouchers that are still outstanding" (and on the old words).
  raise exception 'This Credit Package came with reward vouchers that are still outstanding. '
    'Review them and record what should happen to them, then refund or cancel. Vouchers not handed over yet are withdrawn; those already handed over stay with the customer.';$n$,
  -- P14 invoice_benefit_review_options: the review note
$n$   issue:='This Credit Package came with reward vouchers. Review their original hand-over records first; credit-only allocations cannot complete this purchase.';  -- 502 (the user, 10 Nov 2026)$n$,
  -- P15 resolve_invoice_credit_rewards: the permission refusal
$n$  raise exception 'Only an Owner or Manager can settle reward vouchers' using errcode='42501'; end if;  -- 502 (the user, 10 Nov 2026)$n$];

  -- The refund guard trigger 502 dropped, exactly as pg_get_triggerdef showed it with public alone
  -- on the search path; this file puts it back.
  c_trigger_def constant text :=
    'CREATE TRIGGER legacy_refund_guard BEFORE UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_legacy_refund_guard()';
  -- The 13 functions only Legacy used, which 502 took from signed-in logins; given back here.
  c_revoke constant text[] := array[
    'affiliate_legacy_day_summary(date)',
    'backfill_legacy_qualification(date,date,uuid)',
    'claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)',
    'invoice_legacy_entitlements(uuid)',
    'invoice_therapy_summary(uuid)',
    'legacy_qualification_diagnose(uuid,uuid,date)',
    'legacy_qualification_group(uuid,uuid,date)',
    'legacy_reward_options(uuid)',
    'legacy_reward_options_diagnostic(uuid)',
    'legacy_setup_status()',
    'therapy_map_entitlement_tier(uuid,text,text)',
    'therapy_reward_mapping_preview()',
    'upsert_legacy_rule(uuid,uuid,text,numeric,text,integer,integer,integer,boolean,date,text)'];
  c_rights_before constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_rights_after constant text := 'postgres=X/postgres,service_role=X/postgres';
  -- The 4 recounts 502 commented as retired; this file takes the comment off.
  c_retired constant text[] := array[
    'recompute_legacy_qualification(uuid,uuid,date)',
    'recompute_affiliate_legacy_qualification(uuid,date)',
    'recompute_affiliates_for_customer_day(uuid,date)',
    'recompute_legacy_qualification_for_invoice(uuid)'];
  c_retired_note constant text := 'Retired by 502 (10 Nov 2026). Do not run: it drops therapy_entitlement_invoices history.';
  c_reason constant text := 'Legacy Therapy retired (decision of 10 Nov 2026)';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[15]);
  v_acl text[] := array_fill(null::text, array[15]);
  v_triggers text;
  d text; i int; n int;
begin
  perform set_config('lock_timeout', '5s', true);
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      raise exception 'UNDO 502: public.% is missing; nothing changed', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_after[i] then
      raise exception 'UNDO 502: public.% is not 502''s version (md5 %); nothing changed', c_sig[i], md5(d); end if;
    v_def[i] := d;
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
  end loop;
  n := (select count(*) from public.therapy_entitlements where status = 'cancelled' and revoked_reason = c_reason);
  if n > 0 then
    raise exception 'UNDO 502: % reward(s) are still cancelled by the go-live script ("%"). Run scripts/therapy/undo-legacy-retired-golive-502.sql first; nothing changed.', n, c_reason; end if;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard')
     and ((select pg_get_triggerdef(t.oid) from pg_trigger t
            where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') is distinct from c_trigger_def
          or (select t.tgenabled::text from pg_trigger t
               where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') is distinct from 'O') then
    raise exception 'UNDO 502: a trigger legacy_refund_guard is on public.invoices, but not the one 502 dropped; nothing changed'; end if;
  v_triggers := (select coalesce(string_agg(t.tgname || ' ' || t.tgenabled::text || ' ' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname), '')
                   from pg_trigger t
                  where t.tgrelid = 'public.invoices'::regclass and not t.tgisinternal and t.tgname <> 'legacy_refund_guard');
  for i in 1 .. cardinality(c_revoke) loop
    if to_regprocedure('public.' || c_revoke[i]) is null then
      raise exception 'UNDO 502: public.% is missing; nothing changed', c_revoke[i]; end if;
    d := (select coalesce(string_agg(x::text, ',' order by x::text), '')
            from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_revoke[i]));
    if d not in (c_rights_after, c_rights_before) then
      raise exception 'UNDO 502: the rights on public.% are not 502''s (%); nothing changed', c_revoke[i], d; end if;
  end loop;
  for i in 1 .. cardinality(c_retired) loop
    if to_regprocedure('public.' || c_retired[i]) is null then
      raise exception 'UNDO 502: public.% is missing; nothing changed', c_retired[i]; end if;
    d := obj_description(to_regprocedure('public.' || c_retired[i]), 'pg_proc');
    if d is distinct from c_retired_note and d is not null then
      raise exception 'UNDO 502: public.% has a comment 502 did not write (%); nothing changed', c_retired[i], d; end if;
  end loop;
  -- Each new text is found exactly once, and the text worked back is the BEFORE one.
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 502: patch % is not found exactly once in public.%; nothing changed', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'UNDO 502: the text worked back for public.% is not the BEFORE one (md5 %); nothing changed', c_sig[i], md5(v_def[i]); end if;
  end loop;

  raise notice 'UNDO 502: the pages must already be reverted to their version before 502: from now on the list ''vouchers'' is refused, and the Credit Package window may switch the reward on again.';

  -- 2. Put back
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') then
    execute c_trigger_def;
  end if;
  for i in 1 .. cardinality(c_revoke) loop
    execute format('grant execute on function public.%s to authenticated', c_revoke[i]);
  end loop;
  -- 502 found no comment on them.
  for i in 1 .. cardinality(c_retired) loop
    execute format('comment on function public.%s is null', c_retired[i]);
  end loop;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i] then
      raise exception 'UNDO 502: public.% was put back with an md5 other than the BEFORE one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if not (c_sig[i] = any(c_revoke))
       and (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception 'UNDO 502: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t
       where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') is distinct from c_trigger_def
     or (select t.tgenabled::text from pg_trigger t
          where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') is distinct from 'O' then
    raise exception 'UNDO 502: the trigger legacy_refund_guard did not come back as it was'; end if;
  if (select coalesce(string_agg(t.tgname || ' ' || t.tgenabled::text || ' ' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname), '')
        from pg_trigger t
       where t.tgrelid = 'public.invoices'::regclass and not t.tgisinternal and t.tgname <> 'legacy_refund_guard') is distinct from v_triggers then
    raise exception 'UNDO 502: the other triggers on public.invoices changed'; end if;
  for i in 1 .. cardinality(c_revoke) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_revoke[i])) is distinct from c_rights_before then
      raise exception 'UNDO 502: the rights on public.% did not come back as they were', c_revoke[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_retired) loop
    if obj_description(to_regprocedure('public.' || c_retired[i]), 'pg_proc') is not null then
      raise exception 'UNDO 502: public.% still has a comment', c_retired[i]; end if;
  end loop;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
