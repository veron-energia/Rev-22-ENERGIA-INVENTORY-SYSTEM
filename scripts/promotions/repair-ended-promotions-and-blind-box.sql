-- Switch off the 12 promotions that ended on 1 Oct 2026, take the empty
-- "4 Vouchers x 2" out of the live S$50 blind box, and switch "4 Vouchers x 2"
-- off as well (goes with 424).
--
-- PROPOSED, NOT RUN. It changes live promotions: run it only with the Owner's
-- sign-off, after reading the dry run. 424 does not need it and does not do it.
--
-- WHY THIS EXISTS (the Owner, 9 Oct 2026, Q18 = A; and 18 Oct 2026,
-- W4-B10-4VOUCHERSX2: "switch '4 Vouchers x 2' off as well (with the Q18
-- repair at deploy)")
--
--   A. 12 promotions have an end date of 1 Oct 2026 but are still switched
--      on: the September 16th Anniversary bundles and their add-ons (codes
--      4xVouchers, B-C-(Corset3.0)-V, B-C(Corset3.0)-T,
--      Energia16BundleC&Vouchers, Energia16thBundleA&Vouchers,
--      Energia16thPromotionBundleB&Vouchers, EnergiaGloves, EnergiaSockB,
--      ENERGIASOCKW, NDBundle-A+THERAPY, NDBUNDLEB+THERAPY,
--      NDBUNDLEC+Therapy). The till and the exchange page offered them and the
--      server then refused them as ended. None of them is inside another
--      promotion (checked on 9 Oct 2026). They are switched off, not deleted:
--      past sales keep them, and the Owner can switch one on again.
--   B. "4 Vouchers x 2" (code 4VouchersX2, S$122) holds nothing, yet it is one
--      of the five prizes of the live S$50 blind box (code 50BB). A customer
--      who chose it would receive nothing. No sale has chosen it (9 Oct 2026).
--      Its option is removed from the box until the Owner says what it should
--      hold; the audit entry keeps the removed option, so it can be put back.
--      The deleted copy of the S$50 box (also code 50BB) is not touched.
--   C. "4 Vouchers x 2" itself is switched off too (W4-B10-4VOUCHERSX2, 18 Oct
--      2026). It has no dates and a price at 2 stores, so it is still on sale
--      on its own, holding nothing. Production on 18 Oct 2026: switched on, no
--      items, no choice groups, never sold, never chosen from a box, and inside
--      no live promotion but the S$50 box (B takes it out first; the deleted
--      copy of the box still lists it, and a deleted box does not count). It is
--      switched off only while it still holds nothing and is inside no live
--      promotion; if someone has given it items since, the script refuses and
--      the Owner is asked again. Switched off, not deleted: its prices stay,
--      and the Owner can switch it on again once it holds something.
--
-- NOT TOUCHED: any sale, any price, any other promotion or blind box.

-- ── STEP 1: DRY RUN — changes nothing ───────────────────────────────────────
-- Every row must say ok = true (14 rows: the 12 promotions, "4 Vouchers x 2"
-- itself, then its option in the S$50 box). After STEP 2 has run, the option's
-- row is gone (13 rows) and is_active says false.
select 'switch off' as what, p.code, p.is_active, p.end_date,
       p.deleted_at is null and p.end_date = date '2026-10-01'
       -- not inside a live promotion, as an item or a choice
       and not exists (select 1 from public.promotion_items i join public.promotions x on x.id = i.promotion_id
                        where i.child_promotion_id = p.id and x.deleted_at is null and x.is_active)
       and not exists (select 1 from public.promotion_choice_options o
                         join public.promotion_choice_groups g on g.id = o.group_id
                         join public.promotions x on x.id = g.promotion_id
                        where o.child_promotion_id = p.id and x.deleted_at is null and x.is_active) as ok
  from public.promotions p
 where p.id in ('1fea9651-8363-4417-947c-c68f7fb41d83', '83bfbf8d-9364-4d86-88ac-351078a5bdf8',
                '1e3c5fbe-e7ce-43f1-8e89-252013d3f3d2', '54210a7d-8e0f-4e79-8111-a711b75f053a',
                '40fd5be2-eed0-4fba-b29c-9692011939eb', '2da721e0-344a-41a2-aa07-027c58e4daa4',
                'c6541938-9d31-4620-bc88-78f7e2363a8d', '8cbc45d3-c976-468b-80fa-72bf8a971999',
                '30b5d1a5-3e1b-40f6-8f88-70ea52800b67', '3d025160-3518-45b6-b6b3-37fe30beee28',
                '257c6224-af66-4700-81f5-ece995007b62', 'f357964d-9570-4003-977c-3c8088257b20')
union all
select 'switch off (holds nothing)', c.code, c.is_active, c.end_date,
       c.deleted_at is null and c.code = '4VouchersX2'
       -- still holds nothing
       and not exists (select 1 from public.promotion_items i where i.promotion_id = c.id)
       and not exists (select 1 from public.promotion_choice_groups g2 where g2.promotion_id = c.id)
       -- not inside a live promotion, as an item or a choice, once its option
       -- in the S$50 box (below) is taken out: only that option, in that group
       -- of that box, is left out (if it has moved, this row says false)
       and not exists (select 1 from public.promotion_items i join public.promotions x on x.id = i.promotion_id
                        where i.child_promotion_id = c.id and x.deleted_at is null and x.is_active)
       and not exists (select 1 from public.promotion_choice_options o
                         join public.promotion_choice_groups g on g.id = o.group_id
                         join public.promotions x on x.id = g.promotion_id
                        where o.child_promotion_id = c.id and x.deleted_at is null and x.is_active
                          and not (o.id = '8e2f49cc-f502-4b4e-93e1-2525c5ce5f3c'
                                   and o.group_id = '274409ea-d88c-49e8-9952-7e9461a615e4'
                                   and x.id = '11f756e5-1144-415a-8052-717817acfda8')) as ok
  from public.promotions c
 where c.id = '6f3e8a76-2e0e-4552-bec6-f14ca0cb9cfb'
union all
select 'take out of the S$50 box', c.code, null, null,
       box.code = '50BB' and box.deleted_at is null and c.code = '4VouchersX2'
       and not exists (select 1 from public.promotion_items i where i.promotion_id = c.id)
       and not exists (select 1 from public.promotion_choice_groups g2 where g2.promotion_id = c.id)
       and not exists (select 1 from public.invoice_promotion_selections s
                        where s.group_id = g.id and s.child_promotion_id = c.id)
       -- the box keeps its other prizes
       and (select count(*) from public.promotion_choice_options o2 where o2.group_id = g.id) > 1 as ok
  from public.promotion_choice_options o
  join public.promotion_choice_groups g on g.id = o.group_id
  join public.promotions box on box.id = g.promotion_id
  join public.promotions c on c.id = o.child_promotion_id
 where o.id = '8e2f49cc-f502-4b4e-93e1-2525c5ce5f3c'
   and g.id = '274409ea-d88c-49e8-9952-7e9461a615e4'
   and box.id = '11f756e5-1144-415a-8052-717817acfda8'
   and c.id = '6f3e8a76-2e0e-4552-bec6-f14ca0cb9cfb'
 order by 1, 2;

-- ── STEP 2: APPLY — only after all 14 dry-run rows say ok = true ────────────
-- One transaction. It checks the same conditions again and refuses if
-- anything moved since the dry run. Each change writes an audit entry; a
-- second run changes nothing. Uncomment to run.
--
-- begin;
-- do $apply$
-- declare
--   c_ids constant uuid[] := array[
--     '1fea9651-8363-4417-947c-c68f7fb41d83', '83bfbf8d-9364-4d86-88ac-351078a5bdf8',
--     '1e3c5fbe-e7ce-43f1-8e89-252013d3f3d2', '54210a7d-8e0f-4e79-8111-a711b75f053a',
--     '40fd5be2-eed0-4fba-b29c-9692011939eb', '2da721e0-344a-41a2-aa07-027c58e4daa4',
--     'c6541938-9d31-4620-bc88-78f7e2363a8d', '8cbc45d3-c976-468b-80fa-72bf8a971999',
--     '30b5d1a5-3e1b-40f6-8f88-70ea52800b67', '3d025160-3518-45b6-b6b3-37fe30beee28',
--     '257c6224-af66-4700-81f5-ece995007b62', 'f357964d-9570-4003-977c-3c8088257b20']::uuid[];
--   c_reason constant text := 'Ended on 1 Oct 2026; switched off with the Owner''s sign-off (Q18 = A, 9 Oct 2026)';
--   r record; o record; e record; n int := 0;
-- begin
--   -- "4 Vouchers x 2" inside a live promotion other than its option in the S$50
--   -- box: checked before A switches the 12 off, so it sees what the dry run saw
--   -- (C checks again once the option is out)
--   if exists (select 1 from public.promotion_items i join public.promotions x on x.id = i.promotion_id
--               where i.child_promotion_id = '6f3e8a76-2e0e-4552-bec6-f14ca0cb9cfb' and x.deleted_at is null and x.is_active)
--      or exists (select 1 from public.promotion_choice_options co
--                   join public.promotion_choice_groups g on g.id = co.group_id
--                   join public.promotions x on x.id = g.promotion_id
--                  where co.child_promotion_id = '6f3e8a76-2e0e-4552-bec6-f14ca0cb9cfb' and x.deleted_at is null and x.is_active
--                    and not (co.id = '8e2f49cc-f502-4b4e-93e1-2525c5ce5f3c'
--                             and co.group_id = '274409ea-d88c-49e8-9952-7e9461a615e4'
--                             and x.id = '11f756e5-1144-415a-8052-717817acfda8')) then
--     raise exception '"4 Vouchers x 2" is now inside a live promotion; refusing'; end if;
--
--   -- A. the 12 promotions that ended on 1 Oct 2026
--   if (select count(*) from public.promotions where id = any (c_ids)) <> 12 then
--     raise exception 'Not all 12 promotions were found; refusing'; end if;
--   for r in select * from public.promotions where id = any (c_ids) order by code for update loop
--     if r.deleted_at is not null or r.end_date is distinct from date '2026-10-01' then
--       raise exception '% is no longer a live promotion that ended on 1 Oct 2026; refusing', r.code; end if;
--     if exists (select 1 from public.promotion_items i join public.promotions x on x.id = i.promotion_id
--                 where i.child_promotion_id = r.id and x.deleted_at is null and x.is_active)
--        or exists (select 1 from public.promotion_choice_options co
--                     join public.promotion_choice_groups g on g.id = co.group_id
--                     join public.promotions x on x.id = g.promotion_id
--                    where co.child_promotion_id = r.id and x.deleted_at is null and x.is_active) then
--       raise exception '% is now inside a live promotion; refusing', r.code; end if;
--     continue when not r.is_active;   -- already off
--     update public.promotions set is_active = false where id = r.id;
--     perform public.write_audit_ex('promotions', r.id, 'promotion_switched_off',
--       jsonb_build_object('code', r.code, 'is_active', true),
--       jsonb_build_object('code', r.code, 'is_active', false, 'end_date', r.end_date),
--       'promotions', c_reason, null);
--     n := n + 1;
--   end loop;
--   raise notice 'Switched off % of the 12 (the rest were already off)', n;
--
--   -- B. "4 Vouchers x 2" out of the live S$50 blind box
--   select co.*, g.promotion_id as box_id into o
--     from public.promotion_choice_options co join public.promotion_choice_groups g on g.id = co.group_id
--    where co.id = '8e2f49cc-f502-4b4e-93e1-2525c5ce5f3c' for update of co;
--   if not found then
--     raise notice 'The option is already gone from the S$50 box';
--   else
--     if o.group_id <> '274409ea-d88c-49e8-9952-7e9461a615e4' or o.box_id <> '11f756e5-1144-415a-8052-717817acfda8'
--        or o.child_promotion_id is distinct from '6f3e8a76-2e0e-4552-bec6-f14ca0cb9cfb' then
--       raise exception 'The option is no longer "4 Vouchers x 2" in the S$50 box; refusing'; end if;
--     if exists (select 1 from public.promotion_items where promotion_id = o.child_promotion_id)
--        or exists (select 1 from public.promotion_choice_groups where promotion_id = o.child_promotion_id) then
--       raise exception '"4 Vouchers x 2" holds something now; ask the Owner before taking it out; refusing'; end if;
--     if exists (select 1 from public.invoice_promotion_selections
--                 where group_id = o.group_id and child_promotion_id = o.child_promotion_id) then
--       raise exception 'A sale has chosen "4 Vouchers x 2" from the box since 9 Oct 2026; refusing'; end if;
--     if (select count(*) from public.promotion_choice_options where group_id = o.group_id) < 2 then
--       raise exception 'The S$50 box would have no prize left; refusing'; end if;
--     delete from public.promotion_choice_options where id = o.id;
--     perform public.write_audit_ex('promotion_choice_options', o.id, 'choice_option_removed',
--       jsonb_build_object('group_id', o.group_id, 'promotion_id', o.box_id, 'child_promotion_id', o.child_promotion_id,
--                          'created_at', o.created_at),
--       null, 'promotions',
--       '"4 Vouchers x 2" holds nothing; out of the S$50 blind box until the Owner says what it holds (Q18 = A, 9 Oct 2026)',
--       null);
--     raise notice 'Took "4 Vouchers x 2" out of the S$50 blind box';
--   end if;
--
--   -- C. "4 Vouchers x 2" itself, once it is out of the box (W4-B10-4VOUCHERSX2)
--   select * into e from public.promotions where id = '6f3e8a76-2e0e-4552-bec6-f14ca0cb9cfb' for update;
--   if not found or e.deleted_at is not null or e.code is distinct from '4VouchersX2' then
--     raise exception '"4 Vouchers x 2" is no longer a live promotion; refusing'; end if;
--   if exists (select 1 from public.promotion_items where promotion_id = e.id)
--      or exists (select 1 from public.promotion_choice_groups where promotion_id = e.id) then
--     raise exception '"4 Vouchers x 2" holds something now; ask the Owner before switching it off; refusing'; end if;
--   if exists (select 1 from public.promotion_items i join public.promotions x on x.id = i.promotion_id
--               where i.child_promotion_id = e.id and x.deleted_at is null and x.is_active)
--      or exists (select 1 from public.promotion_choice_options co
--                   join public.promotion_choice_groups g on g.id = co.group_id
--                   join public.promotions x on x.id = g.promotion_id
--                  where co.child_promotion_id = e.id and x.deleted_at is null and x.is_active) then
--     raise exception '"4 Vouchers x 2" is now inside a live promotion; refusing'; end if;
--   if not e.is_active then
--     raise notice '"4 Vouchers x 2" is already switched off';
--   else
--     update public.promotions set is_active = false where id = e.id;
--     perform public.write_audit_ex('promotions', e.id, 'promotion_switched_off',
--       jsonb_build_object('code', e.code, 'is_active', true),
--       jsonb_build_object('code', e.code, 'is_active', false),
--       'promotions',
--       'Holds nothing; switched off with the Owner''s sign-off (W4-B10-4VOUCHERSX2, 18 Oct 2026)',
--       null);
--     raise notice 'Switched off "4 Vouchers x 2"';
--   end if;
-- end $apply$;
-- commit;
