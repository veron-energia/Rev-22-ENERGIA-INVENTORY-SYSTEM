-- 502, GO-LIVE STEP 2a: CREDIT PACKAGES GIVE CREDIT ONLY (the user, 10 Nov 2026: new Credit
-- Package sales give credit only; the one Credit Package sold before go-live and not yet paid off
-- keeps its old terms: when it is paid off it gets credit only, and its reward vouchers are given
-- afterwards by a separate script, run only with the user's fresh OK at that time).
--
-- WHAT IT DOES
--   * Records the one earlier sale still owed its reward vouchers: an ordinary Credit Package line
--     (not a split) on an invoice not yet paid off (one part-paid S$1,000 package). Its reward is
--     only made when the invoice is paid off, and with the reward
--     switched off it would then get credit only. One Audit Log row on the invoice line
--     (credit_package_reward_kept_for_earlier_sale) keeps what issue_credit_package would give it
--     if the invoice were paid off now: 1 reward of 10 vouchers for each S$994 of the package's
--     price, the package and its price, the collect-by window, the vouchers it may be taken as,
--     and everything else the reward is made from.
--   * Switches the reward off on the 3 Credit Packages, through the Credit Package window's own
--     function (set_catalogue_reward), with one Audit Log row each
--     (credit_package_reward_switched_off). From then on a Credit Package sale gives credit only.
--   Nothing else changes. The Credit Package rewards already given (10 rewards, 100 vouchers, for
--   2 customers) can still be handed over and keep their refund review.
--
-- WHEN: straight after supabase/502_legacy_therapy_retired.sql, in the same quiet window, outside
-- opening hours. No Credit Package may be paid between 502 and this step: one paid off in
-- between still gets reward vouchers, and step 2b then refuses. To be sure, run 502 (with its
-- history row), the recording account, this step and step 2b in ONE transaction, then commit:
-- nothing can fall between them, and any refusal undoes them all, 502 included.
-- GO-LIVE ORDER: 502 -> THIS FILE -> scripts/therapy/legacy-retired-golive-502.sql (it refuses
-- unless this has run) -> the pages; then every till and office PC reloads the app.
-- If this refuses, do not open with 502 alone: Credit Packages would still give reward vouchers.
-- Find out why, tell the user, and run it again once fixed, or undo 502
-- (scripts/therapy/undo-502.sql).
--
-- HOW: one transaction, all or nothing. Set the recording account first, in the same transaction:
-- an active Owner or Manager, whose name every Audit Log row carries.
--   select set_config('request.jwt.claim.sub', '<an active Owner''s or Manager''s profile id>', true),
--          set_config('request.jwt.claim.role', 'authenticated', true),
--          set_config('request.jwt.claims', '{"sub":"<the same id>","role":"authenticated"}', true);
-- It refuses, with nothing changed, unless what it finds is what was read on production on
-- 10 Nov 2026 (the constants below). Before the window, run scripts/therapy/golive-preview-502.sql
-- (read-only): it prints each figure next to its constant. If a figure has moved, tell the user
-- the new figures, and change the constant, in every file the preview names for it, only with
-- their OK; then run the go-live suite again. Run again, it refuses and changes nothing.
-- It also refuses while a Credit Package sale split between customers is not yet paid off and
-- still carries reward vouchers: paid off later, it would still give them, whatever the package
-- says (issue_credit_package_invoice_item gives the vouchers set aside at the sale). Ask the user.
--
-- LATER: once that invoice is paid off (it gets credit only), and only with the user's OK at that
-- time, scripts/therapy/credit-package-presale-reward-502.sql gives its reward vouchers from the
-- values kept here. Nothing about it is automatic.
--
-- UNDO: scripts/therapy/undo-credit-package-credit-only-502.sql.
-- ROLLBACK ORDER: revert the pages -> scripts/therapy/undo-legacy-retired-golive-502.sql ->
-- scripts/therapy/undo-credit-package-credit-only-502.sql -> scripts/therapy/undo-502.sql.
do $cp502$
declare
  c_reason constant text := 'Credit Packages give credit only (decision of 10 Nov 2026)';
  -- 502 is in: its AFTER md5s, read with public alone on the search path.
  c_trg_after constant text := '7b63da063576a5c952cc5abe6c53f13d';   -- trg_create_therapy_on_paid()
  c_cat_after constant text := 'a8a9c9ae3862a348217cc434185f9781';   -- set_catalogue_reward(text,uuid,boolean)
  -- How a Credit Package line is paid off and its reward worked out, as on production now (502
  -- leaves them alone). The values kept here copy them; changed, they may give something else.
  c_relied constant text[] := array[
    'issue_credit_lines_for_invoice(uuid)',
    'issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)',
    'legacy_lowest_rule(uuid,date)',
    'credit_line_benefits_holder(uuid)'];
  c_relied_md5 constant text[] := array[
    '303f45e12e88b8de58e95aa0f877b875',
    '5654ef9249cf5c6a943beb7890574f20',
    '3549988e36b6696e43ac2a4f248bd326',
    '45865ed52a5f24ebe6b8e435ba10e9e9'];
  -- As read on production on 10 Nov 2026. c_packages and c_kept_lines are repeated in step 2b and
  -- undo 2a, c_kept_lines and the four after it in the earlier-sale script: change them together
  -- (the go-live suite checks that they agree).
  c_packages constant int := 3;             -- Credit Packages with the reward on (S$1,000, S$3,000, S$5,000); no deleted one
  c_kept_lines constant int := 1;           -- earlier sales not yet paid off that are owed a reward (one part-paid S$1,000 package)
  c_kept_price constant numeric := 1000;    -- that package's price
  c_kept_units constant int := 1;           -- rewards it gives when paid off: S$1,000 / S$994, rounded down
  c_vouchers_per_unit constant int := 10;   -- vouchers in each reward (issue_credit_package)
  c_threshold constant numeric := 994;      -- spend for each reward (no package has its own; the rules say S$994)
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_who uuid;
  v_lines uuid[]; v_line uuid;
  v_it public.invoice_items%rowtype;
  v_inv public.invoices%rowtype;
  v_pk public.credit_packages%rowtype;
  v_rule public.therapy_package_rules;
  v_qual numeric; v_units integer;
  v_kept jsonb := '[]'::jsonb; k jsonb;
  v_fp_pk text; v_fp_lines text; v_n_off int; v_n_kept int;
  v_split int; v_split_nos text;
  r record; n int := 0; i int;
begin
  -- At most 5 seconds' wait for any lock: it fails rather than holding a sale behind it.
  perform set_config('lock_timeout', '5s', true);
  perform set_config('search_path', 'public', true);   -- md5s are read with public alone

  -- 0. Who records it: an active Owner or Manager, set in this transaction.
  if coalesce(current_setting('request.jwt.claim.sub', true), '') = ''
     or coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')
          <> current_setting('request.jwt.claim.sub', true)
     or not public.is_owner_or_manager() then
    raise exception '502 credit only: set the recording account (an active Owner or Manager) first, in this transaction: request.jwt.claim.sub and request.jwt.claims, as the header shows. Nothing changed.'; end if;
  v_who := auth.uid();

  -- 502 is in.
  if md5(pg_get_functiondef('public.trg_create_therapy_on_paid()'::regprocedure)) <> c_trg_after
     or md5(pg_get_functiondef('public.set_catalogue_reward(text,uuid,boolean)'::regprocedure)) <> c_cat_after
     or exists (select 1 from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'legacy_refund_guard') then
    raise exception '502 credit only: migration 502 is not in. Apply it first. Nothing changed.'; end if;
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '502 credit only: public.% is not the version this was tested against. Re-read it and re-test before running. Nothing changed.', c_relied[i]; end if;
  end loop;

  -- Not run already: its switch-offs are in the Audit Log and not undone.
  if exists (select 1 from public.audit_logs a
              where a.action = 'credit_package_reward_switched_off' and a.reason = c_reason
                and not exists (select 1 from public.audit_logs u
                                 where u.action = 'credit_package_reward_switched_on'
                                   and u.new_data ->> 'switched_off_audit_id' = a.id::text)) then
    raise exception '502 credit only: this has run already (its Audit Log rows are there, not undone). Nothing changed.'; end if;

  -- 1. What it finds is what was read on 10 Nov 2026.
  if (select count(*) from public.credit_packages where grants_reward and deleted_at is null) <> c_packages
     or exists (select 1 from public.credit_packages where grants_reward and deleted_at is not null) then
    raise exception '502 credit only: % Credit Packages give reward vouchers (% of them deleted), not % (none deleted) as on 10 Nov 2026. Tell the user the new figures and change the constants only with their OK. Nothing changed.',
      (select count(*) from public.credit_packages where grants_reward),
      (select count(*) from public.credit_packages where grants_reward and deleted_at is not null), c_packages; end if;

  -- No sale split between customers is still to be paid off with reward vouchers set aside: paid
  -- off, issue_credit_lines_for_invoice gives such a line through
  -- issue_credit_package_invoice_item, which gives the vouchers set aside at the sale
  -- (credit_voucher_qty_snapshot) whatever the package says now, so switching the reward off does
  -- not stop them, and they are not kept here. A line of a split without its allocation would be
  -- given credit only, losing them. Either way the user decides first. Live: the invoice is not
  -- deleted, cancelled or refunded.
  -- One sale split between customers is one split group, with a line on each customer's invoice.
  select count(distinct coalesce(it.credit_split_group_id, it.id)),
         string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into v_split, v_split_nos
    from public.invoice_items it
    join public.invoices iv on iv.id = it.invoice_id
   where it.line_kind = 'credit_package'
     and it.credit_issued_at is null
     and (it.credit_split_allocation_id is not null or it.credit_split_group_id is not null)
     and coalesce(it.credit_voucher_qty_snapshot, 0) > 0
     and iv.deleted_at is null
     and iv.status::text not in ('cancelled', 'refunded');
  if v_split > 0 then
    raise exception '502 credit only: % Credit Package sale(s) split between customers and not yet paid off still carry reward vouchers (on invoice(s) %). Paid off after go-live, they would still give those vouchers. Ask the user what to do. Nothing changed.',
      v_split, v_split_nos; end if;

  -- The earlier sales still owed their reward: a Credit Package line not split between customers,
  -- whose credit is not given yet, on an invoice not deleted and not yet paid off, whose package
  -- gives reward vouchers and would give it at least one reward if it were paid off now. Worked
  -- out as issue_credit_package works it out: the package's own threshold, else the cheapest
  -- customer rule's (legacy_lowest_rule), else S$994; rewards = the package's price / threshold,
  -- rounded down.
  select coalesce(array_agg(it.id order by it.id), '{}') into v_lines
    from public.invoice_items it
    join public.invoices iv on iv.id = it.invoice_id
    join public.credit_packages pk on pk.id = it.credit_package_id
   cross join lateral (select coalesce(pk.reward_qualifying_amount,
                                       (public.legacy_lowest_rule(iv.store_id, public.sg_today())).qualifying_amount,
                                       994) as threshold) q
   where it.line_kind = 'credit_package'
     and it.credit_issued_at is null
     and it.credit_split_group_id is null
     and iv.deleted_at is null
     and iv.status::text in ('unpaid', 'partially_paid')
     and pk.grants_reward
     and case when q.threshold > 0 then floor(coalesce(pk.customer_price, 0) / q.threshold) else 0 end >= 1;
  if cardinality(v_lines) <> c_kept_lines then
    raise exception '502 credit only: found % Credit Package sales not yet paid off that would give reward vouchers, not % as on 10 Nov 2026. Tell the user the new figures and change the constants only with their OK. Nothing changed.',
      cardinality(v_lines), c_kept_lines; end if;

  -- What each would get if paid off now, exactly as issue_credit_package makes it (frozen).
  foreach v_line in array v_lines loop
    select * into v_it from public.invoice_items where id = v_line;
    select * into v_inv from public.invoices where id = v_it.invoice_id;
    select * into v_pk from public.credit_packages where id = v_it.credit_package_id;
    -- An ordinary line: paid off, issue_credit_lines_for_invoice gives it through
    -- issue_credit_package with the line (not a share of a split, not a 141 split).
    if v_it.credit_split_allocation_id is not null
       or exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = v_it.id) then
      raise exception '502 credit only: the earlier sale on invoice % is split between customers, not an ordinary line as on 10 Nov 2026. Nothing changed.', v_inv.invoice_no; end if;
    v_rule := public.legacy_lowest_rule(v_inv.store_id, public.sg_today());
    v_qual := coalesce(v_pk.reward_qualifying_amount, v_rule.qualifying_amount, 994);
    v_units := case when not coalesce(v_pk.grants_reward, false) then 0
                    when v_qual > 0 then floor(coalesce(v_pk.customer_price, 0) / v_qual)::integer
                    else 0 end;
    if v_units <> c_kept_units or v_qual <> c_threshold or v_pk.customer_price <> c_kept_price then
      raise exception '502 credit only: the earlier sale on invoice % would give % reward(s) for S$% each on a S$% package, not % for S$% on S$% as on 10 Nov 2026. Nothing changed.',
        v_inv.invoice_no, v_units, v_qual, v_pk.customer_price, c_kept_units, c_threshold, c_kept_price; end if;
    v_kept := v_kept || jsonb_build_array(jsonb_build_object(
      'invoice_item_id', v_it.id,
      'invoice_id', v_inv.id,
      'invoice_no', v_inv.invoice_no,
      'sold_on', coalesce(v_inv.business_date, (v_inv.created_at at time zone 'Asia/Singapore')::date),
      'paid_so_far', v_inv.paid_amount,
      'total', v_inv.total_amount,
      'store_id', v_inv.store_id,
      -- whom the reward would go to now: whoever holds the package's benefits, else the invoice's customer
      'customer_id', coalesce(public.credit_line_benefits_holder(v_it.id), v_inv.customer_id),
      'package_id', v_pk.id,
      'package', v_pk.name,
      'reward_name', 'Credit package reward — ' || v_pk.name,
      'customer_price', v_pk.customer_price,
      'units', v_units,
      'vouchers_per_unit', c_vouchers_per_unit,
      'vouchers', v_units * c_vouchers_per_unit,
      'threshold', v_qual,
      'threshold_from', case when v_pk.reward_qualifying_amount is not null then 'package'
                             when v_rule.qualifying_amount is not null then 'rule' else 'default' end,
      'rule_id', v_rule.id,
      'forfeited_value', round(coalesce(v_pk.customer_price, 0) - (v_units * v_qual), 2),
      'claim_window_days', coalesce(v_rule.activation_deadline_days, 365),
      'duration_months', coalesce(v_rule.duration_months, 1),
      'voucher_ids', coalesce((select jsonb_agg(cv.voucher_id order by cv.voucher_id)
                                 from public.credit_package_vouchers cv where cv.package_id = v_pk.id), '[]'::jsonb)));
  end loop;

  -- What must not change: the packages but for the reward, the lines and their invoices.
  v_fp_pk := (select md5(coalesce(string_agg((to_jsonb(p) - 'grants_reward' - 'updated_at')::text, ',' order by p.id), ''))
                from public.credit_packages p);
  v_fp_lines := (select md5(coalesce(string_agg(to_jsonb(it)::text || to_jsonb(iv)::text, ',' order by it.id), ''))
                   from public.invoice_items it join public.invoices iv on iv.id = it.invoice_id
                  where it.id = any(v_lines));
  v_n_off := (select count(*) from public.audit_logs
               where action = 'credit_package_reward_switched_off' and reason = c_reason and changed_by = v_who);
  v_n_kept := (select count(*) from public.audit_logs
                where action = 'credit_package_reward_kept_for_earlier_sale' and reason = c_reason and changed_by = v_who);

  -- 2. The earlier sale's reward, kept in the Audit Log (read by credit-package-presale-reward-502.sql).
  for k in select * from jsonb_array_elements(v_kept) loop
    perform public.write_audit_ex('invoice_items', (k ->> 'invoice_item_id')::uuid,
      'credit_package_reward_kept_for_earlier_sale', null, k, 'invoices', c_reason, (k ->> 'store_id')::uuid);
  end loop;

  -- 3. Credit Packages give credit only, through the Credit Package window's own function (it
  --    writes no Audit Log row of its own).
  for r in select id, name from public.credit_packages where grants_reward order by id loop
    perform public.set_catalogue_reward('credit_package', r.id, false);
    perform public.write_audit_ex('credit_packages', r.id, 'credit_package_reward_switched_off',
      jsonb_build_object('grants_reward', true), jsonb_build_object('grants_reward', false, 'package', r.name),
      'catalogue', c_reason, null);
    n := n + 1;
  end loop;

  -- 4. What it leaves.
  if n <> c_packages
     or exists (select 1 from public.credit_packages where grants_reward)
     or v_fp_pk is distinct from (select md5(coalesce(string_agg((to_jsonb(p) - 'grants_reward' - 'updated_at')::text, ',' order by p.id), ''))
                                    from public.credit_packages p)
     or v_fp_lines is distinct from (select md5(coalesce(string_agg(to_jsonb(it)::text || to_jsonb(iv)::text, ',' order by it.id), ''))
                                       from public.invoice_items it join public.invoices iv on iv.id = it.invoice_id
                                      where it.id = any(v_lines))
     or (select count(*) from public.audit_logs
          where action = 'credit_package_reward_switched_off' and reason = c_reason and changed_by = v_who) <> v_n_off + c_packages
     or (select count(*) from public.audit_logs
          where action = 'credit_package_reward_kept_for_earlier_sale' and reason = c_reason and changed_by = v_who) <> v_n_kept + c_kept_lines
     or (select count(*) from public.audit_logs a
          where a.action = 'credit_package_reward_kept_for_earlier_sale' and a.reason = c_reason
            and a.record_id = any(v_lines)
            and not exists (select 1 from public.audit_logs u
                             where u.action = 'credit_package_reward_kept_for_earlier_sale_undone'
                               and u.new_data ->> 'kept_audit_id' = a.id::text)) <> c_kept_lines then
    raise exception '502 credit only: what it left is not what was planned. Nothing changed.'; end if;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
end $cp502$;
