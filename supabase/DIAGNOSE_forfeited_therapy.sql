-- =====================================================================
-- DIAGNOSTIC — THE FORFEITED THERAPY FIGURE. Read-only, changes nothing.
--
-- Reported:  Eligible S$7,094.00 | Applied S$6,352.00 | Forfeited S$5,936.00
-- Correct:   Forfeited = 7094 - 6352 = S$742.00
-- Shown is exactly 8 x 742, and that qualification produced 8 entitlements.
--
-- invoice_legacy_entitlements() SUMS forfeited_value across every entitlement
-- in the qualification group, but forfeiture belongs to the qualification as a
-- whole. One entitlement per group hides it; more than one multiplies it.
--
-- The screen now DERIVES the figure, so it reads correctly. These queries show
-- how the stored rows got that way, and how many groups are affected.
-- =====================================================================

-- 1. Every group where more than one entitlement carries a forfeited value.
--    Each of these overstates by roughly its entitlement count.
select e.qualification_group_id,
       count(*)                                              as entitlements,
       count(*) filter (where coalesce(e.forfeited_value,0) <> 0) as rows_with_forfeit,
       round(sum(e.qualified_value), 2)                      as applied,
       round(sum(e.forfeited_value), 2)                      as forfeited_as_summed,
       string_agg(distinct e.entitlement_no, ', ')           as entitlement_nos
  from public.therapy_entitlements e
 where e.qualification_group_id is not null
 group by e.qualification_group_id
having count(*) filter (where coalesce(e.forfeited_value,0) <> 0) > 1
 order by 5 desc;

-- 2. The individual rows for one group. Replace the id from section 1.
--    This shows whether the same value is repeated on every row.
-- select entitlement_no, package_name, qualified_value, forfeited_value, created_at
--   from public.therapy_entitlements
--  where qualification_group_id = 'PASTE-GROUP-ID-HERE'
--  order by created_at;

-- 3. What the corrected figure would be for each group.
--    applied + forfeited should equal the eligible total for that qualification.
select e.qualification_group_id,
       round(sum(e.qualified_value), 2)  as applied,
       round(sum(e.forfeited_value), 2)  as forfeited_as_summed,
       round(max(e.forfeited_value), 2)  as forfeited_probably_correct
  from public.therapy_entitlements e
 where e.qualification_group_id is not null
 group by e.qualification_group_id
having round(sum(e.forfeited_value), 2) <> round(max(e.forfeited_value), 2)
 order by 3 desc;
