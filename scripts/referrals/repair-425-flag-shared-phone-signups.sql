-- Flag the referral sign-ups made before 425 that share an older customer's
-- phone under another name, so staff check them before they count in a
-- referral promotion (goes with 425; the Owner, Q19 = A, 9 Oct 2026).
--
-- PROPOSED, NOT RUN. It changes who counts in a running promotion: run it
-- only with the Owner's sign-off, after reading the dry run. 425 does not
-- need it and does not do it.
--
-- WHY THIS EXISTS
--
--   425 checks every new link sign-up on a phone a customer already has
--   under another name: it waits for an Owner or Manager on the Affiliates
--   page ("Check these sign-ups") before it counts. Sign-ups made before 425
--   are not flagged. On 18 Oct 2026 production had 49 customers made through
--   a link; 4 share the phone of an older customer, 2 of them under another
--   name (by 432's rule: not the same words). 1 of the 2 is listed in a
--   promotion, not counted. This flags those 2, as 425 would have.
--
--   The other 2 have the same words as the older customer: by 432's rule
--   they are the same person, and today a sign-up like them makes nothing.
--   They are left as they are; merging them is the Owner's decision.
--
--   As in 425, an older customer whose phone is stored as 8 digits that
--   could be Singapore or Malaysia has the phone when it could be the
--   sign-up's (the counts above stay the same with it, 18 Oct 2026).
--
-- NOT TOUCHED: any customer, referrer, visit, promotion reward or commission.
-- A sign-up already flagged is skipped, so a second run adds nothing.

-- ── STEP 1: DRY RUN, changes nothing ────────────────────────────────────────
-- One row for each sign-up that would be flagged (expected on 18 Oct 2026: 2).
with s as (
  select c.id, c.created_at, c.referred_by, c.referral_code_used, public.normalize_customer_phone(c.phone) as p, c.full_name
    from public.customers c
   where c.deleted_at is null and c.referral_source = 'affiliate_link'
)
select s.id as customer_id, s.created_at, s.referred_by,
       (select array_agg(o.id order by o.created_at, o.id) from public.customers o
         where o.deleted_at is null and o.id <> s.id and o.created_at < s.created_at
           and (public.normalize_customer_phone(o.phone) = s.p
                or (public.normalize_customer_phone(o.phone) is null and o.phone ~ '^[\s().0-9-]+$'
                    and (public.inspect_customer_phone(o.phone)->'candidates') ? s.p))) as phone_shared_with,
       exists (select 1 from public.referral_campaigns rc
                cross join lateral public.referral_campaign_friends(rc.id) f
               where f.friend_customer_id = s.id) as listed_in_a_promotion
  from s
 where s.p is not null
   and not exists (select 1 from public.referral_signup_checks k where k.customer_id = s.id)
   and exists (select 1 from public.customers o
                where o.deleted_at is null and o.id <> s.id and o.created_at < s.created_at
                  and (public.normalize_customer_phone(o.phone) = s.p
                       or (public.normalize_customer_phone(o.phone) is null and o.phone ~ '^[\s().0-9-]+$'
                           and (public.inspect_customer_phone(o.phone)->'candidates') ? s.p)))
   and not exists (select 1 from public.customers o
                    where o.deleted_at is null and o.id <> s.id and o.created_at < s.created_at
                      and (public.normalize_customer_phone(o.phone) = s.p
                           or (public.normalize_customer_phone(o.phone) is null and o.phone ~ '^[\s().0-9-]+$'
                               and (public.inspect_customer_phone(o.phone)->'candidates') ? s.p))
                      and public.customer_names_match(o.full_name, s.full_name))
 order by s.created_at;

-- ── STEP 2: FLAG THEM (only with the Owner's sign-off) ──────────────────────
-- begin;
-- with s as (
--   select c.id, c.created_at, c.referred_by, c.referral_code_used, public.normalize_customer_phone(c.phone) as p, c.full_name
--     from public.customers c
--    where c.deleted_at is null and c.referral_source = 'affiliate_link'
-- ), f as (
--   insert into public.referral_signup_checks(customer_id, referrer_customer_id, referral_code, normalized_phone, phone_shared_with, created_at)
--   select s.id, s.referred_by, s.referral_code_used, s.p,
--          (select array_agg(o.id order by o.created_at, o.id) from public.customers o
--            where o.deleted_at is null and o.id <> s.id and o.created_at < s.created_at
--              and (public.normalize_customer_phone(o.phone) = s.p
--                   or (public.normalize_customer_phone(o.phone) is null and o.phone ~ '^[\s().0-9-]+$'
--                       and (public.inspect_customer_phone(o.phone)->'candidates') ? s.p))),
--          s.created_at
--     from s
--    where s.p is not null
--      and not exists (select 1 from public.referral_signup_checks k where k.customer_id = s.id)
--      and exists (select 1 from public.customers o
--                   where o.deleted_at is null and o.id <> s.id and o.created_at < s.created_at
--                     and (public.normalize_customer_phone(o.phone) = s.p
--                          or (public.normalize_customer_phone(o.phone) is null and o.phone ~ '^[\s().0-9-]+$'
--                              and (public.inspect_customer_phone(o.phone)->'candidates') ? s.p)))
--      and not exists (select 1 from public.customers o
--                       where o.deleted_at is null and o.id <> s.id and o.created_at < s.created_at
--                         and (public.normalize_customer_phone(o.phone) = s.p
--                              or (public.normalize_customer_phone(o.phone) is null and o.phone ~ '^[\s().0-9-]+$'
--                                  and (public.inspect_customer_phone(o.phone)->'candidates') ? s.p))
--                         and public.customer_names_match(o.full_name, s.full_name))
--   returning id, customer_id
-- )
-- insert into public.audit_logs (table_name, record_id, action, old_data, new_data)
-- select 'referral_signup_checks', f.id, 'referral_signup_flagged', null,
--        jsonb_build_object('customer_id', f.customer_id, 'source', 'repair-425')
--   from f;
-- -- Check: as many rows as the dry run listed, all pending.
-- select count(*) as flagged from public.referral_signup_checks where status = 'pending';
-- commit;
