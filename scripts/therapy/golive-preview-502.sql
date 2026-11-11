-- 502 GO-LIVE PREVIEW (read-only). For every constant of the two go-live steps
--   scripts/therapy/credit-package-credit-only-502.sql   step 2a
--   scripts/therapy/legacy-retired-golive-502.sql        step 2b
-- and of the same constants repeated in undo 2b (scripts/therapy/undo-legacy-retired-golive-502.sql),
-- undo 2a (scripts/therapy/undo-credit-package-credit-only-502.sql) and the later script for the
-- earlier sale (scripts/therapy/credit-package-presale-reward-502.sql), it prints the figure this
-- database has now, counted the way the scripts count it, next to the constant's name. It also
-- prints the stop signs no constant can fix, and what the steps check when they run.
--
-- WHEN: just before the go-live window, before 502; again between the steps if wanted.
-- It only reads: a READ ONLY transaction, counts and figures only, no names, phones or emails.
-- Run it with psql (psql -X -f scripts/therapy/golive-preview-502.sql), or paste only the SELECT
-- (from "with" to "order by n") into an SQL editor: the whole file ends in a rollback, which an
-- editor showing only the last statement's result shows as no rows.
--
-- HOW TO READ IT, by kind:
--   constant  When the scripts run, the constant "name" must equal "now", in every file the note
--             names. "expected" is the constant as written on 10 Nov 2026, so ok false means the
--             figure has moved since. Then tell the user the new figure, and change the constant
--             in every file named, only with their OK; then run the go-live suite
--             (scripts/therapy/tests/legacy-retired-golive-502.sql) again.
--   stop      Must be "expected" (ok true). If not, stop and tell the user: no constant can fix
--             it; the scripts refuse, or would do what was not decided, until the code changes.
--   check     What a step checks when it runs. Before 502 the "502 in" rows show 501's md5s, and
--             before step 2a the "2a in" rows read as before it: that is expected.
--   info      To read only.
-- The go-live suite runs the SELECT below as it stands (from "with" to "order by n") on its own
-- fixture, and checks each constant's figure against the fixture's.
begin read only;
set local search_path = public;   -- function md5s are read with public alone, as the scripts read them
with
w as (   -- step 2b's W, as it reads it (it also locks these rows, which a read-only query cannot)
  select e.* from public.therapy_entitlements e
   where e.status = 'pending_activation' and e.earner_kind in ('customer', 'affiliate')
     and e.rule_id is not null and e.claim_source_invoice_id is null and e.claimed_at is null
     and public.entitlement_claimed_qty(e.id) = 0),
lines as (   -- step 2a's earlier sales owed a reward (v_lines), as it reads them
  select it.id, it.invoice_id, it.credit_package_id, it.credit_split_allocation_id
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
     and case when q.threshold > 0 then floor(coalesce(pk.customer_price, 0) / q.threshold) else 0 end >= 1),
kept as (   -- what step 2a works out for each of them (v_rule, v_qual, v_units), as it works it out
  select row_number() over (order by l.id) as k,
         (l.credit_split_allocation_id is not null
          or exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = l.id)) as split,
         pk.customer_price, pk.reward_qualifying_amount as pk_threshold, pk.grants_reward,
         public.legacy_lowest_rule(iv.store_id, public.sg_today()) as rule,
         iv.paid_amount, iv.total_amount, iv.status::text as inv_status,
         coalesce(iv.business_date, (iv.created_at at time zone 'Asia/Singapore')::date) as sold_on,
         (select count(*) from public.credit_package_vouchers cv where cv.package_id = pk.id) as n_vouchers
    from lines l
    join public.invoices iv on iv.id = l.invoice_id
    join public.credit_packages pk on pk.id = l.credit_package_id),
kept2 as (select k.*, coalesce(k.pk_threshold, (k.rule).qualifying_amount, 994) as qual from kept k),
kept3 as (select k.*, case when not coalesce(k.grants_reward, false) then 0
                          when k.qual > 0 then floor(coalesce(k.customer_price, 0) / k.qual)::integer
                          else 0 end as units
            from kept2 k),
split as (   -- step 2a's refusal: sales split between customers, not yet paid off, carrying reward vouchers
  -- (a sale is its split group: one line on each customer's invoice)
  select it.id, coalesce(it.credit_split_group_id, it.id) as sale, iv.deleted_at is not null as deleted
    from public.invoice_items it
    join public.invoices iv on iv.id = it.invoice_id
   where it.line_kind = 'credit_package'
     and it.credit_issued_at is null
     and (it.credit_split_allocation_id is not null or it.credit_split_group_id is not null)
     and coalesce(it.credit_voucher_qty_snapshot, 0) > 0
     and iv.status::text not in ('cancelled', 'refunded')),
rules as (   -- the qualification rules on, as step 2b reads them
  select r.* from public.therapy_package_rules r where r.is_active and r.deleted_at is null),
fig(n, step, kind, name, now, expected, note) as (
  -- ── 502 in: step 2a, step 2b and undo 2b check these (before 502 they show 501's) ──
  select 1, '2a, 2b, undo 2b', 'check', 'c_trg_after: md5 of trg_create_therapy_on_paid()',
         md5(pg_get_functiondef(to_regprocedure('public.trg_create_therapy_on_paid()'))),
         '7b63da063576a5c952cc5abe6c53f13d', 'before 502: 012ae4e305b9870fa5596f740c0427b9'
  union all select 2, '2a, 2b', 'check', 'c_cat_after: md5 of set_catalogue_reward(text,uuid,boolean)',
         md5(pg_get_functiondef(to_regprocedure('public.set_catalogue_reward(text,uuid,boolean)'))),
         'a8a9c9ae3862a348217cc434185f9781', 'before 502: 0987f23df3fbb1863346c4c46c04fad2'
  union all select 3, '2a, 2b', 'check', 'the refund guard trigger legacy_refund_guard on invoices',
         (select count(*) from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'legacy_refund_guard')::text,
         '0', 'before 502: 1'
  -- ── what step 2a and the earlier-sale script rely on, as tested ──
  union all select 4, '2a', 'check', 'c_relied_md5: issue_credit_lines_for_invoice(uuid)',
         md5(pg_get_functiondef(to_regprocedure('public.issue_credit_lines_for_invoice(uuid)'))), '303f45e12e88b8de58e95aa0f877b875', ''
  union all select 5, '2a, presale', 'check', 'c_relied_md5: issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)',
         md5(pg_get_functiondef(to_regprocedure('public.issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)'))), '5654ef9249cf5c6a943beb7890574f20', ''
  union all select 6, '2a', 'check', 'c_relied_md5: legacy_lowest_rule(uuid,date)',
         md5(pg_get_functiondef(to_regprocedure('public.legacy_lowest_rule(uuid,date)'))), '3549988e36b6696e43ac2a4f248bd326', ''
  union all select 7, '2a', 'check', 'c_relied_md5: credit_line_benefits_holder(uuid)',
         md5(pg_get_functiondef(to_regprocedure('public.credit_line_benefits_holder(uuid)'))), '45865ed52a5f24ebe6b8e435ba10e9e9', ''
  union all select 8, 'presale', 'check', 'c_relied_md5: credit_package_reward_group(uuid)',
         md5(pg_get_functiondef(to_regprocedure('public.credit_package_reward_group(uuid)'))), '7f8ac1b8bdc369110be03c8e9d260942', ''
  union all select 9, 'presale', 'check', 'c_relied_md5: next_legacy_entitlement_no()',
         md5(pg_get_functiondef(to_regprocedure('public.next_legacy_entitlement_no()'))), 'b80297ed343c35bd214c117cdf29be6a', ''
  -- ── step 2a ──
  union all select 10, '2a', 'check', 'not run already: step 2a''s switch-offs, not undone',
         (select count(*) from public.audit_logs a
           where a.action = 'credit_package_reward_switched_off' and a.reason = 'Credit Packages give credit only (decision of 10 Nov 2026)'
             and not exists (select 1 from public.audit_logs u
                              where u.action = 'credit_package_reward_switched_on'
                                and u.new_data ->> 'switched_off_audit_id' = a.id::text))::text, '0', 'after step 2a: c_packages'
  union all select 11, '2a', 'constant', 'c_packages',
         (select count(*) from public.credit_packages where grants_reward and deleted_at is null)::text, '3',
         'Credit Packages with the reward on; also in step 2b and undo 2a. After step 2a this reads 0 (row 22 then counts them)'
  union all select 12, '2a', 'stop', 'Credit Packages with the reward on that are deleted',
         (select count(*) from public.credit_packages where grants_reward and deleted_at is not null)::text, '0', 'step 2a refuses'
  union all select 13, '2a', 'stop', 'sales split between customers, not yet paid off, still carrying reward vouchers',
         (select count(distinct sale) from split where not deleted)::text, '0', 'step 2a refuses: ask the user'
  union all select 14, '2a', 'constant', 'c_kept_lines', (select count(*) from lines)::text, '1',
         'earlier sales not paid off that are owed a reward; also in step 2b, undo 2a and the earlier-sale script'
  union all select 15, '2a', 'stop', 'of them, split between customers', (select count(*) from kept3 where split)::text, '0', 'step 2a refuses'
  union all select 16, '2a', 'stop', 'of them, differing in rewards, threshold or price (each constant takes one)',
         (select greatest(count(distinct (units, qual, customer_price)) - 1, 0) from kept3)::text, '0', 'step 2a refuses'
  union all select 17, '2a', 'constant', 'c_kept_units',
         (select string_agg(distinct units::text, ', ' order by units::text) from kept3), '1',
         'rewards each gives when paid off: price / threshold, rounded down; also in the earlier-sale script'
  union all select 18, '2a', 'constant', 'c_threshold',
         (select string_agg(distinct trim_scale(qual)::text, ', ' order by trim_scale(qual)::text) from kept3), '994',
         'from the package, else the cheapest rule, else S$994; also in the earlier-sale script'
  union all select 19, '2a', 'constant', 'c_kept_price',
         (select string_agg(distinct trim_scale(customer_price)::text, ', ' order by trim_scale(customer_price)::text) from kept3), '1000',
         'also in the earlier-sale script'
  union all select 20, '2a', 'constant', 'c_vouchers_per_unit',
         (regexp_match(pg_get_functiondef(to_regprocedure('public.issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)')),
                       '''voucher'', coalesce\(v_rule\.duration_months, 1\), ([0-9]+), v_qual,'))[1], '10',
         'the vouchers issue_credit_package writes in each reward; also in the earlier-sale script'
  -- ── step 2b: step 2a in (before step 2a these read c_packages / 0 / 0) ──
  union all select 21, '2b', 'check', '2a in: Credit Packages with the reward on',
         (select count(*) from public.credit_packages where grants_reward)::text, '0', 'before step 2a: c_packages'
  union all select 22, '2b', 'check', '2a in: packages step 2a switched off, not undone (= c_packages)',
         (select count(distinct a.record_id) from public.audit_logs a
           where a.action = 'credit_package_reward_switched_off' and a.reason = 'Credit Packages give credit only (decision of 10 Nov 2026)'
             and not exists (select 1 from public.audit_logs u
                              where u.action = 'credit_package_reward_switched_on'
                                and u.new_data ->> 'switched_off_audit_id' = a.id::text))::text, '3', 'before step 2a: 0'
  union all select 23, '2b', 'check', '2a in: earlier sales step 2a kept, not undone (= c_kept_lines)',
         (select count(*) from public.audit_logs a
           where a.action = 'credit_package_reward_kept_for_earlier_sale' and a.reason = 'Credit Packages give credit only (decision of 10 Nov 2026)'
             and not exists (select 1 from public.audit_logs u
                              where u.action = 'credit_package_reward_kept_for_earlier_sale_undone'
                                and u.new_data ->> 'kept_audit_id' = a.id::text))::text, '1', 'before step 2a: 0'
  union all select 24, '2b', 'check', 'not run already: rewards cancelled with step 2b''s reason',
         (select count(*) from public.therapy_entitlements
           where status = 'cancelled' and revoked_reason = 'Legacy Therapy retired (decision of 10 Nov 2026)')::text, '0', 'after step 2b: c_rewards'
  -- ── step 2b: the figures ──
  union all select 30, '2b', 'constant', 'c_cust_rows',
         (select count(*) from w where earner_kind = 'customer' and entitlement_kind = 'unlimited')::text, '102',
         'one-month rewards not claimed (W); undo 2b''s c_rewards = this + c_aff_rows'
  union all select 31, '2b', 'constant', 'c_cust_people',
         (select count(distinct customer_id) from w where earner_kind = 'customer')::text, '43', 'their customers'
  union all select 32, '2b', 'constant', 'c_aff_rows',
         (select count(*) from w where earner_kind = 'affiliate' and entitlement_kind = 'voucher')::text, '1',
         'affiliate rewards not claimed, each with c_aff_vouchers vouchers; undo 2b''s c_rewards = c_cust_rows + this'
  union all select 33, '2b', 'constant', 'c_aff_vouchers',
         (select string_agg(distinct voucher_qty::text, ', ' order by voucher_qty::text) from w
           where earner_kind = 'affiliate' and entitlement_kind = 'voucher'), '10', 'the vouchers in each of them'
  union all select 34, 'undo 2b', 'constant', 'c_rewards', (select count(*) from w)::text, '103',
         'in undo 2b: what step 2b cancels (= c_cust_rows + c_aff_rows)'
  union all select 35, '2b', 'stop', 'rewards not claimed that are neither a customer''s one-month reward nor an affiliate''s voucher reward',
         (select count(*) from w
           where not ((earner_kind = 'customer' and coalesce(entitlement_kind, '') = 'unlimited')
                      or (earner_kind = 'affiliate' and coalesce(entitlement_kind, '') = 'voucher')))::text, '0', 'step 2b refuses'
  union all select 36, '2b', 'stop', 'affiliate rewards not claimed without a voucher count, or with different counts',
         (select count(*) filter (where voucher_qty is null) + greatest(count(distinct voucher_qty) - 1, 0) from w
           where earner_kind = 'affiliate' and entitlement_kind = 'voucher')::text, '0', 'step 2b refuses'
  union all select 37, '2b', 'stop', 'Legacy rewards waiting that step 2b leaves out (part handed over, no rule, from a sale, claimed)',
         ((select count(*) from public.therapy_entitlements e
            where e.status = 'pending_activation' and e.earner_kind in ('customer', 'affiliate'))
          - (select count(*) from w))::text, '0', 'step 2b refuses'
  union all select 38, '2b', 'stop', 'Legacy month booked (scheduled) or running (active)',
         (select count(*) from public.therapy_entitlements e where e.earner_kind in ('customer', 'affiliate')
            and (e.status = 'scheduled' or (e.status = 'active' and coalesce(e.entitlement_kind, 'unlimited') = 'unlimited')))::text,
         '0', 'step 2b refuses'
  union all select 39, '2b', 'constant', 'c_other',
         (select count(*) from public.therapy_entitlements e
           where e.earner_kind in ('customer', 'affiliate') and e.status <> 'pending_activation')::text, '60',
         'Legacy rewards claimed, used, expired or cancelled'
  union all select 40, '2b', 'constant', 'c_cp_rows',
         (select count(*) from public.therapy_entitlements e where e.earner_kind = 'credit_package' and e.status = 'pending_activation')::text,
         '10', 'Credit Package rewards still to hand over (a reward handed over in full leaves this)'
  union all select 41, '2b', 'constant', 'c_cp_vouchers',
         (select coalesce(sum(e.voucher_qty), 0) from public.therapy_entitlements e
           where e.earner_kind = 'credit_package' and e.status = 'pending_activation')::text, '100', 'their vouchers'
  union all select 42, '2b', 'constant', 'c_held_rows',
         (select count(*) from public.customer_reward_vouchers v join public.therapy_entitlements e on e.id = v.entitlement_id
           where e.earner_kind in ('customer', 'affiliate'))::text, '6', 'voucher rows handed over from Legacy rewards, any status'
  union all select 43, '2b', 'constant', 'c_held_qty',
         (select coalesce(sum(v.quantity), 0) from public.customer_reward_vouchers v join public.therapy_entitlements e on e.id = v.entitlement_id
           where e.earner_kind in ('customer', 'affiliate') and v.status = 'held')::text, '50', 'of them held, in vouchers'
  union all select 44, '2b', 'constant', 'c_links', (select count(*) from public.therapy_entitlement_invoices)::text, '67',
         'invoice links (therapy_entitlement_invoices)'
  union all select 45, '2b', 'constant', 'c_rules', (select count(*) from rules)::text, '3', 'qualification rules on; also in undo 2b'
  union all select 46, '2b', 'constant', 'c_rule_amount',
         (select string_agg(distinct trim_scale(qualifying_amount)::text, ', ' order by trim_scale(qualifying_amount)::text) from rules),
         '994', 'their spend'
  union all select 47, '2b', 'stop', 'rules on for one store only, or with different amounts',
         (select count(*) filter (where store_id is not null) + greatest(count(distinct qualifying_amount) - 1, 0) from rules)::text,
         '0', 'step 2b refuses'
  union all select 48, '2b', 'stop', 'rules on that the rule form''s function would refuse or change',
         (select count(*) from rules r
           where coalesce(r.qualifying_amount, 0) <= 0
              or r.applies_to is distinct from coalesce(nullif(trim(r.applies_to), ''), 'customer')
              or r.applies_to not in ('customer', 'affiliate')
              or r.entitlement_kind not in ('unlimited', 'voucher')
              or (r.applies_to = 'affiliate' and r.entitlement_kind <> 'voucher')
              or (r.entitlement_kind = 'voucher' and coalesce(r.voucher_qty, 0) <= 0)
              or r.name is distinct from coalesce(nullif(trim(r.name), ''), 'Legacy Qualification'))::text,
         '0', 'step 2b and undo 2b refuse'
  union all select 49, '2b', 'constant', 'c_bundles_on', (select count(*) from public.premium_bundles where grants_reward)::text, '2',
         'Premium Bundles with the reward on'
  union all select 50, '2b', 'constant', 'c_bundles_off', (select count(*) from public.premium_bundles where not grants_reward)::text, '2',
         'Premium Bundles without'
  -- ── what the scripts do not count ──
  union all select 60, '2a', 'stop', 'Credit Package sales with the reward on, not paid off, on a draft or an invoice waiting for a cancel or refund',
         (select count(*) from public.invoice_items it
            join public.invoices iv on iv.id = it.invoice_id
            join public.credit_packages pk on pk.id = it.credit_package_id
           cross join lateral (select coalesce(pk.reward_qualifying_amount,
                                               (public.legacy_lowest_rule(iv.store_id, public.sg_today())).qualifying_amount,
                                               994) as threshold) q
           where it.line_kind = 'credit_package' and it.credit_issued_at is null and it.credit_split_group_id is null
             and iv.deleted_at is null and iv.status::text not in ('unpaid', 'partially_paid', 'cancelled', 'refunded')
             and pk.grants_reward
             and case when q.threshold > 0 then floor(coalesce(pk.customer_price, 0) / q.threshold) else 0 end >= 1)::text,
         '0', 'step 2a does not keep them: paid off after go-live they get credit only. Tell the user'
  union all select 61, '2a', 'info', 'sales split between customers, carrying reward vouchers, on deleted invoices',
         (select count(distinct sale) from split where deleted)::text, null,
         'only the database owner can restore a deleted invoice (restore_record); restored and paid off, it would still give them. Leave them deleted'
  union all select 62, 'all', 'check', 'active Owners and Managers (who can record the scripts)',
         (select count(*) from public.profiles p where p.is_active and p.deleted_at is null
            and coalesce(p.invitation_status, 'accepted') = 'accepted' and p.role in ('owner', 'manager'))::text, '>= 1', ''
  union all select 63, '502', 'check', 'newest migration in the history',
         case when to_regclass('supabase_migrations.schema_migrations') is null then 'no history table'
              else (xpath('/row/v/text()', query_to_xml('select max(version) as v from supabase_migrations.schema_migrations', false, true, '')))[1]::text end,
         '20261107085301', 'the newest before 502 (501''s); if it differs, another change has landed: re-check before going live'
  union all select 64, 'all', 'info', 'therapy_entitlements rows', (select count(*) from public.therapy_entitlements)::text, null, '175 on 10 Nov'
  -- ── each earlier sale step 2a keeps (to read) ──
  union all select 80 + k::int, '2a', 'info',
         'earlier sale ' || k || ': sold on / paid / total / status / collect-by days / months / voucher choices',
         sold_on || ' / ' || trim_scale(paid_amount) || ' / ' || trim_scale(total_amount) || ' / ' || inv_status || ' / '
           || coalesce((rule).activation_deadline_days, 365) || ' / ' || coalesce((rule).duration_months, 1) || ' / ' || n_vouchers,
         null, '10 Nov: one part-paid sale, total 1000, partially_paid / 365 / 1 / 2. The earlier-sale script needs over 0 days'
    from kept3
)
select n, step, kind, name, coalesce(now, 'none') as now, expected,
       case when kind = 'info' then null
            when expected like '>= %' then coalesce(now, '0')::numeric >= substr(expected, 4)::numeric
            else now is not distinct from expected end as ok,
       note
  from fig
 order by n;
rollback;
