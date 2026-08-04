-- =====================================================================
-- ENERGIA — RESTORE THE HEALTH SURVEY SYMPTOM CHECKLIST
--
-- The "Do you have the following symptoms or conditions?" section rendered its
-- heading and the Others box but no checkboxes, because the form draws them
-- from public.health_symptom_options and that table had no active rows.
--
-- The original seed in migration 39 is guarded with `where not exists`, so it
-- never re-inserted anything once the rows had been removed or deactivated.
-- This migration restores the full checklist from the paper form, reactivates
-- anything switched off, and corrects the ordering.
--
-- Safe to run whether the rows are missing, present or partly present: it
-- inserts only what is absent and never duplicates.
--
-- Additive and idempotent. Run AFTER 90.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- The checklist, exactly as printed on the Health & Wellness Survey Form.
-- ---------------------------------------------------------------------
with wanted(cat, lbl, ord) as (
  values
    -- Pain
    ('Pain','Headache / Migraine',1), ('Pain','Stiff Neck',2), ('Pain','Shoulder Pain',3),
    ('Pain','Backache',4), ('Pain','Knee Pain',5), ('Pain','Feet Pain',6),
    ('Pain','Menstrual Cramp',7), ('Pain','Joint Pain',8), ('Pain','Trigger Finger',9),
    ('Pain','Carpal Tunnel Syndrome',10),
    -- Sleep
    ('Sleep','Difficulty Dozing Off',1), ('Sleep','Interrupted Sleep',2),
    ('Sleep','Wake Up Tired',3), ('Sleep','Wake Up Too Early',4), ('Sleep','Fatigue',5),
    -- Stress
    ('Stress','Depression',1), ('Stress','Anxiety',2),
    ('Stress','Forgetfulness',3), ('Stress','Easily Irritated',4),
    -- Immune System & Other Health Issues
    ('Immune System & Other Health Issues','Frequent Cough & Cold',1),
    ('Immune System & Other Health Issues','Allergy',2),
    ('Immune System & Other Health Issues','Hypertension',3),
    ('Immune System & Other Health Issues','Diabetes',4),
    ('Immune System & Other Health Issues','Cholesterol',5),
    ('Immune System & Other Health Issues','Uric Acid',6),
    ('Immune System & Other Health Issues','Obesity',7),
    ('Immune System & Other Health Issues','Menopause',8),
    ('Immune System & Other Health Issues','Digestive Problem',9),
    ('Immune System & Other Health Issues','Asthma',10),
    ('Immune System & Other Health Issues','Cold Hand / Cold Feet',11),
    ('Immune System & Other Health Issues','Numbness',12)
)
insert into public.health_symptom_options (category, label, sort_order, is_active)
select w.cat, w.lbl, w.ord, true
  from wanted w
 where not exists (
   select 1 from public.health_symptom_options o
    where o.category = w.cat and o.label = w.lbl);

-- Anything switched off is switched back on, and the ordering corrected, so a
-- partially-edited table ends up matching the paper form.
with wanted(cat, lbl, ord) as (
  values
    ('Pain','Headache / Migraine',1), ('Pain','Stiff Neck',2), ('Pain','Shoulder Pain',3),
    ('Pain','Backache',4), ('Pain','Knee Pain',5), ('Pain','Feet Pain',6),
    ('Pain','Menstrual Cramp',7), ('Pain','Joint Pain',8), ('Pain','Trigger Finger',9),
    ('Pain','Carpal Tunnel Syndrome',10),
    ('Sleep','Difficulty Dozing Off',1), ('Sleep','Interrupted Sleep',2),
    ('Sleep','Wake Up Tired',3), ('Sleep','Wake Up Too Early',4), ('Sleep','Fatigue',5),
    ('Stress','Depression',1), ('Stress','Anxiety',2),
    ('Stress','Forgetfulness',3), ('Stress','Easily Irritated',4),
    ('Immune System & Other Health Issues','Frequent Cough & Cold',1),
    ('Immune System & Other Health Issues','Allergy',2),
    ('Immune System & Other Health Issues','Hypertension',3),
    ('Immune System & Other Health Issues','Diabetes',4),
    ('Immune System & Other Health Issues','Cholesterol',5),
    ('Immune System & Other Health Issues','Uric Acid',6),
    ('Immune System & Other Health Issues','Obesity',7),
    ('Immune System & Other Health Issues','Menopause',8),
    ('Immune System & Other Health Issues','Digestive Problem',9),
    ('Immune System & Other Health Issues','Asthma',10),
    ('Immune System & Other Health Issues','Cold Hand / Cold Feet',11),
    ('Immune System & Other Health Issues','Numbness',12)
)
update public.health_symptom_options o
   set is_active = true, sort_order = w.ord
  from wanted w
 where o.category = w.cat and o.label = w.lbl
   and (o.is_active is distinct from true or o.sort_order is distinct from w.ord);

-- The public form is unauthenticated, so the anon role must be able to read
-- these. Re-asserted here in case the grant was lost.
grant select on public.health_symptom_options to anon;
drop policy if exists "read symptom options" on public.health_symptom_options;
create policy "read symptom options" on public.health_symptom_options
  for select to public using (true);

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.health_symptom_options where is_active;
  raise notice 'Health survey checklist: % active option(s) across % category/ies', v_n,
    (select count(distinct category) from public.health_symptom_options where is_active);
  if v_n < 31 then
    raise warning 'Expected at least 31 options — the public form may still look incomplete';
  end if;
end $$;

notify pgrst, 'reload schema';
