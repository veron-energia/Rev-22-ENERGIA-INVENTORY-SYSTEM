-- Untick "can be given as a reward" on the 5 discount vouchers (THERAPY-7).
-- Goes with 422.
--
-- NOT RUN. The Owner decided on 9 Oct 2026 that it runs at deploy: untick
-- the reward switch on BD-10, BD-AD, SAVE72, SD-10 and SD-50. Run STEP 1
-- first, read it, then STEP 2, after 422. It changes those 5 vouchers only,
-- never a customer record, and prints counts only.
--
-- WHY THIS EXISTS
--
--   vouchers.reward_eligible defaults to true, so every voucher, discount
--   vouchers included, was marked as a reward. Since 422 the reward checks
--   take free-session (normal) vouchers only, whatever this switch says, so
--   nothing here changes what can be handed over. It makes the switch say
--   what the server does, for the Vouchers page's "Can be given as a reward"
--   (423). On 9 Oct 2026 the 5 were the only discount vouchers, all live,
--   all marked as rewards, and none ever given as a reward.
--
-- SAFETY
--
--   STEP 2 is one statement, so it is atomic. It names the 5 codes and
--   refuses, changing nothing, unless 422 is in and each code is exactly one
--   voucher that is not deleted, is a discount voucher, and was never given
--   as a reward. Each voucher switched off gets an audit row. A voucher
--   already switched off is left alone, so a second run changes nothing and
--   writes no audit row. A discount voucher added later, under another code,
--   is not touched: it is listed in STEP 1 for the Owner to decide.

-- ── STEP 1: DRY RUN — changes nothing ───────────────────────────────────────
-- Expected on 9 Oct 2026: 5 rows, each in_list = true, found = 1,
-- discount = true, never_a_reward = true, to_switch_off = true. Any other
-- discount voucher still marked as a reward is listed with in_list = false.
with codes(code) as (values ('BD-10'), ('BD-AD'), ('SAVE72'), ('SD-10'), ('SD-50'))
select coalesce(c.code, v.code) as code,
       c.code is not null as in_list,
       count(v.id) over (partition by coalesce(c.code, v.code)) as found,
       v.voucher_kind::text as kind,
       v.voucher_kind is not null and v.voucher_kind <> 'normal' as discount,
       v.is_active, v.reward_eligible,
       not exists (select 1 from public.customer_reward_vouchers crv where crv.voucher_id = v.id) as never_a_reward,
       coalesce(v.reward_eligible, true) as to_switch_off
  from codes c
  full join (select * from public.vouchers
              where deleted_at is null
                and (code in ('BD-10', 'BD-AD', 'SAVE72', 'SD-10', 'SD-50')
                     or (voucher_kind <> 'normal' and coalesce(reward_eligible, true)))) v
    on v.code = c.code
 order by 2 desc, 1;

-- ── STEP 2: APPLY — only after STEP 1 reads as expected ─────────────────────
-- Uncomment to run, as the database owner (the SQL editor, the MCP
-- execute_sql tool, or psql as postgres).
--
-- do $repair$
-- declare
--   c_codes constant text[] := array['BD-10', 'BD-AD', 'SAVE72', 'SD-10', 'SD-50'];
--   v_code text; v_n int; v_kind text; v_used boolean; r record;
--   n_off int := 0; n_already int := 0;
-- begin
--   -- 422 in: the reward checks then take free-session vouchers only.
--   if to_regprocedure('public.therapy_invoice_closed_reason(uuid)') is null then
--     raise exception 'Repair: apply 422 first; before it, this switch still decides what can be a reward. Nothing was changed.'; end if;
--   -- Each code: one live discount voucher, never given as a reward.
--   foreach v_code in array c_codes loop
--     select count(*), min(v.voucher_kind::text),
--            bool_or(exists (select 1 from public.customer_reward_vouchers crv where crv.voucher_id = v.id))
--       into v_n, v_kind, v_used
--       from public.vouchers v where v.code = v_code and v.deleted_at is null;
--     if v_n <> 1 then
--       raise exception 'Repair: voucher % was found % times, not once. Nothing was changed.', v_code, v_n; end if;
--     if v_kind = 'normal' then
--       raise exception 'Repair: voucher % is a free-session voucher, not a discount. Nothing was changed.', v_code; end if;
--     if v_used then
--       raise exception 'Repair: voucher % was given as a reward; ask the Owner first. Nothing was changed.', v_code; end if;
--   end loop;
--   for r in select v.id, v.code
--              from public.vouchers v
--             where v.code = any (c_codes) and v.deleted_at is null
--             order by v.code
--               for update
--   loop
--     if (select coalesce(reward_eligible, true) from public.vouchers where id = r.id) then
--       update public.vouchers set reward_eligible = false where id = r.id;
--       perform public.write_audit_ex('vouchers', r.id, 'voucher_reward_switched_off',
--         jsonb_build_object('code', r.code, 'reward_eligible', true),
--         jsonb_build_object('code', r.code, 'reward_eligible', false),
--         'vouchers', 'A discount voucher is never a reward (the Owner, 9 Oct 2026; 422, THERAPY-7)', null);
--       n_off := n_off + 1;
--     else
--       n_already := n_already + 1;
--     end if;
--   end loop;
--   if exists (select 1 from public.vouchers v
--               where v.code = any (c_codes) and v.deleted_at is null and coalesce(v.reward_eligible, true)) then
--     raise exception 'Repair: a voucher is still marked as a reward. Nothing was changed.'; end if;
--   raise notice 'Repair: % discount voucher(s) switched off as rewards, % already off', n_off, n_already;
-- end $repair$;
--
-- Check afterwards (expected: 5 rows, reward_eligible = false, one audit row each):
--   select v.code, v.reward_eligible,
--          (select count(*) from public.audit_logs a
--            where a.record_id = v.id and a.action = 'voucher_reward_switched_off') as audit_rows
--     from public.vouchers v
--    where v.code in ('BD-10', 'BD-AD', 'SAVE72', 'SD-10', 'SD-50') and v.deleted_at is null
--    order by 1;
