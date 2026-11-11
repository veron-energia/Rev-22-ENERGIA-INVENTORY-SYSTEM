-- 502_legacy_therapy_retired.sql
--
-- LEGACY THERAPY AND QUALIFICATION RETIRED (the user, 10 Nov 2026: remove "Legacy Therapy" and
-- everything related to it, such as "Qualification"; earning stops at go-live for customers and
-- affiliates; unclaimed rewards are cancelled; every record stays as history; Credit Packages give
-- credit only from now on; Premium Bundle free vouchers stay exactly as they are; the refund guard
-- goes; only vouchers still owed stop a customer being deleted)
--
-- (The number 502 is this file's name, its errors' prefix, its self-test's error code P0502, its
-- suite's, its UNDO's and the go-live scripts'; if it changes at commit, change it in these places.)
--
-- WHAT THIS DOES
--   * Paying, part-paying, correcting, reopening, cancelling or refunding an invoice no longer
--     recounts the customer's or the affiliate's Legacy day (trg_create_therapy_on_paid). The
--     trigger still issues purchased therapy, Credit Packages and Premium Bundles, releases and
--     trims paid credit, and records the invoice's affiliate. Nothing new is earned from the
--     moment this commits: this is go-live.
--   * "Re-check paid days" (backfill_legacy_qualification) refuses.
--   * The refund guard is removed (the user): the trigger legacy_refund_guard on invoices is
--     dropped; its two functions stay, unattached. The one paid invoice it blocked (its day earned
--     the only free month ever used) can be refunded like any other, and the month already used is
--     not taken back.
--   * Vouchers to hand over: therapy_list_page('vouchers'), 'legacy' kept as its old name, without
--     Legacy rows. Customers (vouchers_to_hand_over replaces legacy_therapy), Reports, Dashboard
--     and the holdings card no longer show Legacy rows.
--   * Deleting a customer (the user): only vouchers still owed stop it, that is a Credit Package,
--     Premium Bundle or therapy-package reward still waiting with vouchers left, within its
--     collect-by date, on a sale not refunded, cancelled or deleted; or a live unlimited period.
--     A Legacy reward never does; nor does a reward fully handed over or withdrawn.
--   * A Credit Package's reward can only be switched off, and a new package starts with it off.
--   * The Credit Package reward-review texts no longer say "qualification".
--   * 13 functions only Legacy used are no longer callable by signed-in logins (their bodies stay),
--     and the 4 retired recounts carry a comment: do not run them by hand.
-- WHAT THIS LEAVES ALONE
--   * Every row: Legacy rewards, their invoice links, vouchers already handed over, audit rows.
--   * Credit Package rewards already given: their vouchers, deadlines, hand-over and refund review.
--   * Premium Bundles (a blank threshold still falls back to S$994 once the rules are off),
--     legacy_reward_voucher_options, the nightly status job, holiday calendars and the expiry
--     recalculation, the LEG- numbers (next_legacy_entitlement_no), the Legacy Credit wallet and
--     every other meaning of "legacy".
--
-- GO-LIVE ORDER (one quiet window, outside opening hours)
--   1. this migration;
--   2. scripts/therapy/credit-package-credit-only-502.sql: Credit Packages give credit only, and the
--      one earlier part-paid sale still owed its reward is recorded;
--   3. scripts/therapy/legacy-retired-golive-502.sql: the unclaimed Legacy rewards are cancelled and
--      the qualification rules switched off (it refuses unless step 2 has run);
--   4. the pages; then every till and office PC reloads the app.
-- ROLLBACK ORDER
--   revert the pages -> scripts/therapy/undo-legacy-retired-golive-502.sql ->
--   scripts/therapy/undo-credit-package-credit-only-502.sql -> scripts/therapy/undo-502.sql
--
-- UNDO: scripts/therapy/undo-502.sql (refuses unless every function is 502's version, and while the
-- go-live script's cancellations are in place). A later migration that changes one of these
-- functions must pin 502's AFTER md5s.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written. It waits at
-- most 5 seconds for a lock (dropping the trigger locks invoices), so it fails rather than holding
-- every sale behind it; then it can be run again.

do $mig$
declare
  -- The functions this patches: BEFORE (production now) and AFTER md5s
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
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO file swaps them back.
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

  -- The refund guard (the user, 10 Nov 2026: removed): the trigger is dropped, exactly as
  -- pg_get_triggerdef shows it with public alone on the search path. Its two functions stay.
  c_trigger_def constant text :=
    'CREATE TRIGGER legacy_refund_guard BEFORE UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_legacy_refund_guard()';
  -- Only Legacy used these: signed-in logins can no longer call them. Their bodies stay; the
  -- service role and the database's own functions (all SECURITY DEFINER) still can.
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
  -- The retired recounts: nothing calls them now, and one run by hand drops a day's record of
  -- which invoices earned a reward. They are commented, not changed (no md5 changes).
  c_retired constant text[] := array[
    'recompute_legacy_qualification(uuid,uuid,date)',
    'recompute_affiliate_legacy_qualification(uuid,date)',
    'recompute_affiliates_for_customer_day(uuid,date)',
    'recompute_legacy_qualification_for_invoice(uuid)'];
  c_retired_note constant text := 'Retired by 502 (10 Nov 2026). Do not run: it drops therapy_entitlement_invoices history.';

  -- Relied on, not changed (production now)
  c_relied constant text[] := array[
    'issue_credit_lines_for_invoice(uuid)',
    'issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)',
    'issue_credit_package_invoice_item(uuid)',
    'create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)',
    'credit_package_benefit_preview(uuid,uuid)',
    'invoice_reopen_preview_before_sessions(uuid)',
    'legacy_lowest_rule(uuid,date)',
    'invoice_credit_reward_entitlements(uuid,uuid)',
    'claim_entitlement_vouchers(uuid,jsonb,text)',
    'entitlement_voucher_state(uuid)',
    'entitlement_claimed_qty(uuid)',
    'legacy_reward_voucher_options(uuid)',
    'upsert_premium_bundle(uuid,text,numeric,numeric,numeric,integer,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,text,uuid[],uuid[])',
    'snapshot_invoice_affiliate(uuid)',
    'trg_legacy_refund_guard()',
    'assert_legacy_refund_allowed(uuid)',
    'run_therapy_status_refresh()',
    'refresh_legacy_therapy_statuses()',
    'upsert_legacy_rule(uuid,uuid,text,numeric,text,integer,integer,integer,boolean,date,text)',
    'legacy_rule_for_amount(uuid,date,numeric)',
    'invoice_qualifying_paid(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'is_owner_or_manager()',
    'require_active_staff(text[])',
    'sg_today()',
    'therapy_invoice_closed_reason(uuid)',
    -- the functions only Legacy used that are revoked below and not patched (upsert_legacy_rule is above)
    'affiliate_legacy_day_summary(date)',
    'claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)',
    'invoice_legacy_entitlements(uuid)',
    'invoice_therapy_summary(uuid)',
    'legacy_qualification_diagnose(uuid,uuid,date)',
    'legacy_qualification_group(uuid,uuid,date)',
    'legacy_reward_options(uuid)',
    'legacy_reward_options_diagnostic(uuid)',
    'legacy_setup_status()',
    'therapy_map_entitlement_tier(uuid,text,text)',
    'therapy_reward_mapping_preview()'];
  c_relied_md5 constant text[] := array[
    '303f45e12e88b8de58e95aa0f877b875',
    '5654ef9249cf5c6a943beb7890574f20',
    '08caec99c467334527af99eee5e6b00e',
    'd9219dc95c3f5f598085161d31744d16',
    '4a79692ddfb66374f352c9a6bf9fe565',
    'acbfc38a20a000e1af0e78d26fc7fc4c',
    '3549988e36b6696e43ac2a4f248bd326',
    '58af19ba437802ecdfc1d559091e8e5d',
    '5a2e078df74a2763b6975bb939847b7a',
    '712eaace0a70bcbed47186beb1cd6d7a',
    '89b08265d5303e890569e953d83d2440',
    '38a22dd0f89179f5412e575fa2cbd0a8',
    '2202746851bc5bdd424c1c52fda86056',
    'b9ba96ffe81e5666ad244871a09568bd',
    '089965ef41a18fe3c54dd622e743075a',
    '8c4ec71df7ab88e6ea90590bff3133fd',
    '0d10378270574e2ba7d15f9626b7300d',
    '6de4ab99525f70a282f2889b7694ac41',
    'a9f491260cb6317a7338633bd182f3fd',
    'bc4d5e4f0096a0157093b9fdb18fffc2',
    '98e1682550b467c90b7390ecb3aef7dc',
    'c705c733e213a27f0dc32d54322cc855',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '877b3aa74cea559881979bb161c450e2',
    '1c1289f18e24d8370e9a6364c9c06fca',
    '2286c0c92003643d56b76d8d8827315c',
    -- the functions only Legacy used that are revoked below and not patched
    'f0170fcb61ff1a40c07d532186669212',
    '164530713b7a52f9b80642bbd0e1ed00',
    '0cb40c6bf47d07e55dcda725d2e17c0c',
    'aa53b9ebea63c57f4b7c87253db8b21a',
    'e46813acdafbf7be537dffaa5fd3237b',
    '32edd0e5c43b22d2d3fc07ee77b378fe',
    '5d167cc1ac9d443f4b7d7d2566990770',
    'f99406c5ee8b9ce1587ed4190239da77',
    '613421e888aabd2920b27f4194c5ef9b',
    '79a1ba2c5e581801b89afcfa49d2e088',
    'dc3c1464138365192a055ff83d205e57'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[15]);
  v_make boolean[] := array_fill(false, array[15]);
  v_acl text[] := array_fill(null::text, array[15]);
  v_drop boolean := false;
  v_revoke boolean[] := array_fill(false, array[13]);
  v_note boolean[] := array_fill(false, array[4]);
  v_triggers text;
  d text; i int;
  -- the self-test's made-up records
  t_sfx text; t_owner uuid; t_store uuid; t_rule uuid; t_c1 uuid; t_c2 uuid; t_c3 uuid; t_c4 uuid; t_c5 uuid;
  t_inv uuid; t_sale uuid; t_closed uuid; t_v1 uuid; t_v2 uuid; t_pkg uuid; t_name text; t_got jsonb; t_msg text;
begin
  -- At most 5 seconds' wait for any lock: dropping the trigger needs invoices to itself, and a long
  -- wait would queue every sale behind this transaction.
  perform set_config('lock_timeout', '5s', true);
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '502: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The functions it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '502: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '502: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '502: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '502: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '502: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- The refund guard: on, exactly as read on production (dropped), or gone already (left alone).
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') then
    if (select pg_get_triggerdef(t.oid) from pg_trigger t
         where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') is distinct from c_trigger_def
       or (select t.tgenabled::text from pg_trigger t
            where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') is distinct from 'O' then
      raise exception '502: the trigger legacy_refund_guard on public.invoices is not the one this was tested against. Re-read it and re-test before applying.';
    end if;
    v_drop := true;
  else
    raise notice '502: the trigger legacy_refund_guard on public.invoices is already gone; left alone';
  end if;
  -- The other triggers on invoices, to show afterwards that they were not touched.
  v_triggers := (select coalesce(string_agg(t.tgname || ' ' || t.tgenabled::text || ' ' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname), '')
                   from pg_trigger t
                  where t.tgrelid = 'public.invoices'::regclass and not t.tgisinternal and t.tgname <> 'legacy_refund_guard');

  -- The functions only Legacy used: signed-in logins can call them (revoked), or no longer can (left
  -- alone). Rights are compared as sets.
  for i in 1 .. cardinality(c_revoke) loop
    if to_regprocedure('public.' || c_revoke[i]) is null then raise exception '502: public.% is missing', c_revoke[i]; end if;
    d := (select coalesce(string_agg(x::text, ',' order by x::text), '')
            from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_revoke[i]));
    if d = c_rights_before then
      v_revoke[i] := true;
    elsif d = c_rights_after then
      raise notice '502: signed-in logins already cannot call public.%; left alone', c_revoke[i];
    else
      raise exception '502: the rights on public.% are not the ones this was tested against (%). Re-read them and re-test before applying.', c_revoke[i], d;
    end if;
  end loop;

  -- The retired recounts: no comment yet (one is added), or 502's already (left alone).
  for i in 1 .. cardinality(c_retired) loop
    if to_regprocedure('public.' || c_retired[i]) is null then raise exception '502: public.% is missing', c_retired[i]; end if;
    d := obj_description(to_regprocedure('public.' || c_retired[i]), 'pg_proc');
    if d is null then
      v_note[i] := true;
    elsif d = c_retired_note then
      raise notice '502: public.% already says it is retired; left alone', c_retired[i];
    else
      raise exception '502: public.% has a comment this was not tested against: %', c_retired[i], d;
    end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;
  -- CREATE OR REPLACE keeps the grants. Compared as sets: production lists them in another order
  -- than a local copy. (backfill_legacy_qualification is compared here, before its revoke.)
  for i in 1 .. cardinality(c_sig) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '502: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  -- The refund guard goes; trg_legacy_refund_guard() and assert_legacy_refund_allowed(uuid) stay.
  if v_drop then
    drop trigger legacy_refund_guard on public.invoices;
  end if;
  for i in 1 .. cardinality(c_revoke) loop
    if v_revoke[i] then
      execute format('revoke execute on function public.%s from authenticated', c_revoke[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_retired) loop
    if v_note[i] then
      execute format('comment on function public.%s is %L', c_retired[i], c_retired_note);
    end if;
  end loop;

  -- The self-test, in a block that is always undone. Made-up records only ("502 Check",
  -- @example.invalid, phones +61 2 5550 05nn) and made-up numbers (502-CHK-...), never a numbering
  -- function: an undone transaction does not give a number back. It ends by raising P0502, which
  -- undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    insert into auth.users (id, email) values (gen_random_uuid(), '502chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '502 Check Owner', '502chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);
    insert into public.stores (name, code, country_code) values ('502 Check ' || t_sfx, '502-' || t_sfx, 'SG') returning id into t_store;
    insert into public.customers (full_name, phone) values ('502 Check Customer A ' || t_sfx, '+61 2 5550 0501') returning id into t_c1;
    insert into public.customers (full_name, phone) values ('502 Check Customer B ' || t_sfx, '+61 2 5550 0502') returning id into t_c2;
    insert into public.customers (full_name, phone) values ('502 Check Customer C ' || t_sfx, '+61 2 5550 0503') returning id into t_c3;
    insert into public.customers (full_name, phone) values ('502 Check Customer D ' || t_sfx, '+61 2 5550 0504') returning id into t_c4;
    insert into public.customers (full_name, phone) values ('502 Check Customer E ' || t_sfx, '+61 2 5550 0505') returning id into t_c5;

    -- S1. Paying no longer earns. A customer rule in reach (S$100, from yesterday) and a paid S$500
    -- day would have earned 5 units before 502. Now nothing is earned, the day is not recounted and
    -- keeps no record of its invoices; the invoice's affiliate is still recorded.
    t_rule := public.upsert_legacy_rule(null, t_store, '502 Check rule ' || t_sfx, 100, 'unlimited', 1, null, 365, true,
                                        public.sg_today() - 1, 'customer');
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount)
    values ('502-CHK-' || t_sfx || '-1', t_store, t_c1, t_owner, 'unpaid', 500, 500, 0) returning id into t_inv;
    update public.invoices set status = 'paid', paid_amount = 500, paid_at = now() where id = t_inv;
    if (public.legacy_rule_for_amount(t_store, public.sg_today(), 500)).id is null
       or public.invoice_qualifying_paid(t_inv) <> 500 then
      raise exception '502: the self-test''s paid day would not have earned anything before 502, so it proves nothing'; end if;
    if exists (select 1 from public.therapy_entitlements where customer_id = t_c1)
       or exists (select 1 from public.therapy_entitlement_invoices where invoice_id = t_inv)
       or exists (select 1 from public.audit_logs where action = 'legacy_qualification_recomputed'
                   and new_data->>'customer' = t_c1::text)
       or (select affiliate_active_on_paid from public.invoices where id = t_inv) is null
       or pg_get_functiondef('public.trg_create_therapy_on_paid()'::regprocedure)
            ~ '(recompute_legacy_qualification|recompute_affiliates_for_customer_day)' then
      raise exception '502: paying an invoice still earned or recounted a day, or no longer recorded its affiliate'; end if;

    -- S2. Vouchers to hand over lists only the reward that is not Legacy, under the list's new name
    -- and its old one, and opens on the open rewards; an unknown list is refused.
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount, paid_at)
    values ('502-CHK-' || t_sfx || '-2', t_store, t_c2, t_owner, 'paid', 5000, 5000, 5000, now()) returning id into t_sale;
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status, earner_kind,
        claim_source_type, claim_source_invoice_id)
    values ('502-CHK-' || t_sfx || '-L1', t_c2, t_store, t_rule, '502 Check month', 'unlimited', 1, null, 100, 500,
            public.sg_today() + 365, 'pending_activation', 'customer', null, null),
           ('502-CHK-' || t_sfx || '-L2', t_c2, t_store, null, '502 Check affiliate reward', 'voucher', null, 10, 100, 500,
            public.sg_today() + 365, 'pending_activation', 'affiliate', null, null);
    -- Its collect-by date is today, when a hand-over is still allowed.
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status, earner_kind,
        claim_source_type, claim_source_invoice_id)
    values ('502-CHK-' || t_sfx || '-V1', t_c2, t_store, null, '502 Check Credit Package reward', 'voucher', 1, 10, 994, 994,
            public.sg_today(), 'pending_activation', 'credit_package', 'credit_package', t_sale)
    returning id into t_v1;
    t_name := (select full_name from public.customers where id = t_c2);
    t_got := public.therapy_list_page('vouchers', t_name, 'all', 50, 0);
    if (t_got->>'total')::int is distinct from 1 or t_got->'rows'->0->>'id' is distinct from t_v1::text then
      raise exception '502: Vouchers to hand over did not list the reward that is not Legacy alone: %', t_got; end if;
    t_got := public.therapy_list_page('legacy', t_name, 'all', 50, 0);
    if (t_got->>'total')::int is distinct from 1 or t_got->'rows'->0->>'id' is distinct from t_v1::text then
      raise exception '502: the list''s old name did not read the same rows: %', t_got; end if;
    t_got := public.therapy_list_page('vouchers', t_name);
    if t_got->>'status' is distinct from 'open' or (t_got->>'total')::int is distinct from 1 then
      raise exception '502: Vouchers to hand over did not open on the open rewards: %', t_got; end if;
    t_msg := null;
    begin perform public.therapy_list_page('rewards', t_name);
    exception when others then t_msg := sqlerrm; end;
    if t_msg is distinct from 'Unknown list: rewards (purchased or vouchers)' then
      raise exception '502: an unknown list said: %', coalesce(t_msg, 'nothing'); end if;

    -- S3. Deleting a customer. One holding only Legacy rewards (one waiting, one handed over) is
    -- deleted. One still owed Credit Package vouchers, on the collect-by date itself, is refused.
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status, earner_kind,
        claim_source_type, claim_source_invoice_id)
    values ('502-CHK-' || t_sfx || '-L3', t_c3, t_store, t_rule, '502 Check month', 'unlimited', 1, null, 100, 500,
            public.sg_today() + 365, 'pending_activation', 'customer', null, null),
           ('502-CHK-' || t_sfx || '-L4', t_c3, t_store, t_rule, '502 Check vouchers', 'voucher', null, 10, 100, 500,
            public.sg_today() + 365, 'active', 'customer', null, null);
    perform public.delete_customer(t_c3, (select full_name from public.customers where id = t_c3), '502 self-test');
    if (select deleted_at from public.customers where id = t_c3) is null then
      raise exception '502: a customer holding only Legacy rewards was not deleted'; end if;
    t_msg := null;
    begin perform public.delete_customer(t_c2, t_name, '502 self-test');
    exception when others then t_msg := sqlerrm; end;
    if t_msg is distinct from 'This customer still has 1 reward(s) with vouchers to hand over (Therapy → Vouchers to hand over). Hand them over, or refund or cancel the sale they came from, first.' then
      raise exception '502: deleting a customer still owed vouchers said: %', coalesce(t_msg, 'nothing (deleted)'); end if;

    -- S3b. A reward fully handed over does not stop a delete.
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status, earner_kind,
        claim_source_type, claim_source_invoice_id)
    values ('502-CHK-' || t_sfx || '-V2', t_c4, t_store, null, '502 Check Premium Bundle reward', 'voucher', 1, 10, 0, 1000,
            public.sg_today() + 365, 'active', 'premium_bundle', 'premium_bundle', null)
    returning id into t_v2;
    insert into public.voucher_claims (entitlement_id, customer_id, store_id, quantity, selections, claimed_by)
    values (t_v2, t_c4, t_store, 10, '[]'::jsonb, t_owner);
    if public.entitlement_claimed_qty(t_v2) <> 10 then
      raise exception '502: the self-test''s hand-over was not counted'; end if;
    perform public.delete_customer(t_c4, (select full_name from public.customers where id = t_c4), '502 self-test');
    if (select deleted_at from public.customers where id = t_c4) is null then
      raise exception '502: a customer whose reward was fully handed over was not deleted'; end if;

    -- S3c. Nor does a reward past its collect-by date (yesterday), or one from a refunded sale.
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount)
    values ('502-CHK-' || t_sfx || '-3', t_store, t_c5, t_owner, 'refunded', 5000, 5000, 0) returning id into t_closed;
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status, earner_kind,
        claim_source_type, claim_source_invoice_id)
    values ('502-CHK-' || t_sfx || '-V3', t_c5, t_store, null, '502 Check Credit Package reward', 'voucher', 1, 10, 994, 994,
            public.sg_today() - 1, 'pending_activation', 'credit_package', 'credit_package', null),
           ('502-CHK-' || t_sfx || '-V4', t_c5, t_store, null, '502 Check Credit Package reward', 'voucher', 1, 10, 994, 994,
            public.sg_today() + 365, 'pending_activation', 'credit_package', 'credit_package', t_closed);
    perform public.delete_customer(t_c5, (select full_name from public.customers where id = t_c5), '502 self-test');
    if (select deleted_at from public.customers where id = t_c5) is null then
      raise exception '502: a customer whose rewards were past their date or from a refunded sale was not deleted'; end if;

    -- S4. The customer's page lists the vouchers still to hand over, and the Therapy report leaves
    -- the Legacy rewards out.
    t_got := public.customer_overview(t_c2);
    if t_got ? 'legacy_therapy'
       or jsonb_array_length(coalesce(t_got->'vouchers_to_hand_over', '[]'::jsonb)) <> 1
       or t_got->'vouchers_to_hand_over'->0->>'no' is distinct from '502-CHK-' || t_sfx || '-V1'
       or (t_got->'vouchers_to_hand_over'->0->>'left')::int is distinct from 10
       or (t_got->'vouchers_to_hand_over'->0->>'entitled')::int is distinct from 10
       or (t_got->'vouchers_to_hand_over'->0->>'deadline_passed')::boolean is distinct from false then
      raise exception '502: the customer''s vouchers to hand over were not as expected: %', t_got; end if;
    if not exists (select 1 from public.report_therapy() r where r.entitlement_no = '502-CHK-' || t_sfx || '-V1')
       or exists (select 1 from public.report_therapy() r where r.entitlement_no like '502-CHK-' || t_sfx || '-L%') then
      raise exception '502: the Therapy report did not leave out the Legacy rewards alone'; end if;

    -- S5. A new Credit Package gives credit only. Its reward can be switched off, never on, and an
    -- edit keeps it off.
    t_pkg := public.upsert_credit_package(null, '502 Check ' || t_sfx, 1000, 1000, true, public.sg_today(), null, 'third_party');
    if (select grants_reward from public.credit_packages where id = t_pkg) is distinct from false then
      raise exception '502: a new Credit Package was created with its reward on'; end if;
    t_msg := null;
    begin perform public.set_catalogue_reward('credit_package', t_pkg, true);
    exception when others then t_msg := sqlerrm; end;
    if t_msg is distinct from 'A Credit Package no longer grants reward vouchers; it gives credit only.'
       or (select grants_reward from public.credit_packages where id = t_pkg) is distinct from false then
      raise exception '502: switching a Credit Package''s reward on said: %', coalesce(t_msg, 'nothing (switched on)'); end if;
    perform public.set_catalogue_reward('credit_package', t_pkg, false);
    perform public.upsert_credit_package(t_pkg, '502 Check ' || t_sfx || ' edited', 1000, 1000, true, public.sg_today(), null, 'third_party');
    if (select grants_reward from public.credit_packages where id = t_pkg) is distinct from false then
      raise exception '502: editing a Credit Package switched its reward on'; end if;

    -- S6. "Re-check paid days" refuses.
    t_msg := null;
    begin perform public.backfill_legacy_qualification(null, null, null);
    exception when others then t_msg := sqlerrm; end;
    if t_msg is distinct from 'Legacy Therapy has been retired: paid days are no longer re-checked for rewards.' then
      raise exception '502: re-checking paid days said: %', coalesce(t_msg, 'nothing (it ran)'); end if;

    raise exception using errcode = 'P0502', message = '502: self-test done, undone';
  exception when sqlstate 'P0502' then null;
  end;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '502: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if not (c_sig[i] = any(c_revoke))
       and (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '502: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'legacy_refund_guard') then
    raise exception '502: the trigger legacy_refund_guard is still on public.invoices'; end if;
  if (select coalesce(string_agg(t.tgname || ' ' || t.tgenabled::text || ' ' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname), '')
        from pg_trigger t
       where t.tgrelid = 'public.invoices'::regclass and not t.tgisinternal and t.tgname <> 'legacy_refund_guard') is distinct from v_triggers then
    raise exception '502: the other triggers on public.invoices changed'; end if;
  for i in 1 .. cardinality(c_revoke) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_revoke[i])) is distinct from c_rights_after then
      raise exception '502: the rights on public.% are not postgres and service_role alone', c_revoke[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_retired) loop
    if obj_description(to_regprocedure('public.' || c_retired[i]), 'pg_proc') is distinct from c_retired_note then
      raise exception '502: public.% does not say it is retired', c_retired[i]; end if;
  end loop;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
