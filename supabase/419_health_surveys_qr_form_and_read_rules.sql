-- 419_health_surveys_qr_form_and_read_rules.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026: CUSTOMERS-2, -4, -5, -8, -12,
-- -16, -K1, -M1, -M2, and the survey parts of -9 and -14; the page parts of
-- these, and of -6, -7 and -19, are in the front end)
--
--   1. Start survey on the Health Surveys page made an empty consultant record
--      as soon as a customer was opened (CUSTOMERS-5). The QR form then
--      refused that customer ("already done"), so their signature, consents
--      and signed PDF were never taken: on 18 Oct 2026, 90 consultant records,
--      none signed.
--   2. Edit details saved every field each time (CUSTOMERS-4). A question
--      never answered became "No" (26 consultant records show four "No"s only
--      because Save was pressed), the old values were not kept, and the date
--      of birth went onto the customer each time, so the Birthday discount's
--      date could be changed by anyone (CUSTOMERS-9).
--   3. A second press of Save Review, after the page had emptied its boxes,
--      saved the empty boxes over the review (CUSTOMERS-K1): 22 times from
--      6 Aug to 15 Oct 2026; 21 reviews are still blank.
--   4. upsert_consultant_survey marked a survey reviewed on any call, even
--      with nothing in it (CUSTOMERS-2), and left the store empty for Owners
--      or picked one at random from a person's two stores (CUSTOMERS-M1): 89
--      of 90 consultant records have no store, and their files sit in a
--      'null' folder. add_survey_attachment recorded any path and size the
--      browser sent; the files bucket had no limits.
--   5. Inventory Managers could read every health survey, symptom, consultant
--      note, consultation remark and signed PDF through the tables
--      (CUSTOMERS-M2), and the consultant's findings through the Health
--      Surveys list (customer_survey_overview), though the other survey
--      functions refuse them. The survey
--      window offered a signed PDF that the PDF's own rule then hid from staff
--      of another store (CUSTOMERS-14).
--   6. The QR form split the name at its first space ("Mary Ann" + "Tan"
--      became "Mary" + "Ann Tan"; CUSTOMERS-8); an event's link always
--      recorded "Event Name", never RoadShow (CUSTOMERS-12); and a form whose
--      signed PDF the phone could not build was stored without one, silently
--      (CUSTOMERS-16).
--
-- THE RULES
--
--   1. (the Owner, 9 Oct 2026, Q10 A) A customer whose survey is a
--      consultant's record they have not signed may fill in the QR form.
--      Their signed answers go into that record; the consultant's notes,
--      findings and files are kept; where the two differ, the customer's own
--      answers win (an answer they leave blank keeps the record's). Opening a
--      customer no longer makes a record. This holds too when staff attach a
--      form 433 held for them.
--   2. (the Owner, 9 Oct 2026, Q9 A) Staff fill in a missing date of birth;
--      changing or clearing one already filled in needs an Owner or a Manager
--      and a reason (418's assert_customer_dob_change). Every change is
--      recorded with the old and the new value.
--   3. (the Owner, 9 Oct 2026, Q8 A) The record tidy-ups a, b and c are a
--      script that runs only with the Owner's later go-ahead
--      (scripts/repairs/survey-repairs-419.sql); every change is recorded;
--      nothing is deleted. Part d is B04's (418), part e leaves the 17 past
--      event-link forms as they are.
--   4. Health data is for active Owners, Admins, Managers and Staff, not
--      Inventory Managers, as the survey functions already say. Staff keep
--      what they have; nothing becomes Owner-only.
--   5. (433, the Owner, 16 Oct 2026) A form the QR page is unsure about still
--      waits for staff; any active staff attach it or make a customer from
--      it.
--
-- WHAT THIS DOES
--
--   * health_survey_sign_into_record (new; internal, the server's alone):
--     rule 1. It writes the customer's answers, consents, signature, signed
--     date, link and signed PDF into their unsigned consultant record, and
--     replaces its symptoms with the ones they ticked; it keeps the record's
--     name, findings, notes, remarks and files, and its source snapshot when
--     it has one. One audit row, health_survey_signed_by_customer, holds the
--     old and new values. A record nobody wrote anything on (no finding, no
--     answer, no symptom, no note with text or a file, no file) becomes the
--     QR form it now is: source public_form, dated when the form was sent,
--     so the visit rule (customer_centre_visit_days, unchanged) and TikTok
--     attendance read it as any QR form. A record with the consultant's work
--     keeps source consultant and its date, so its visit stays dated by that
--     work.
--   * submit_health_survey (433's, patched): rule 1 for a customer found by
--     phone and name; the first and last name as typed for a customer the
--     form makes and for a held form (CUSTOMERS-8; a page from before 419
--     sends the whole name, split as before); an event link's own source,
--     with the event's name as the details, whatever the page sent
--     (CUSTOMERS-12); an audit row signed_pdf_missing, with the page's reason,
--     when no signed PDF came (CUSTOMERS-16); and the same person sending the
--     form again after staff put their held form into their record is told
--     they already did, as after any attach. Every 433 hold is kept.
--   * attach_held_health_survey (433's, patched): rule 1 for a held form:
--     a customer whose survey is unsigned and a consultant's takes the form's
--     answers, symptoms and PDF; the form itself stays as sent, with no
--     customer, its hold resolved as attached to them. Any other survey still
--     refuses, as before.
--   * health_survey_holds_list (433's, patched): says, per customer, whether
--     their survey can take the form (survey_takes_form).
--   * create_customer_from_held_survey (433's, patched): the customer it makes
--     keeps the form's name parts.
--   * diagnose_survey_name_edit (the server's diagnostic for the old name
--     fault, patched): it calls update_survey_particulars_v2, since the old
--     Edit details function is dropped.
--   * upsert_consultant_survey (rewritten): a new survey belongs to the store
--     chosen (staff must work there; Owners, Admins and Managers reach every
--     store, as the page's store list and the signed PDF's rule say), else
--     the caller's one store, else the business's one store; otherwise
--     "Choose the store for this survey." An existing survey changes only in
--     the fields sent, only an Owner's or Manager's finding marks it
--     reviewed, and its store is set only when it has none. Its audit row
--     keeps the old and new values. Acidity must be Red, Green or Blue.
--   * update_survey_particulars_v2(survey, changes, reason) (new; staff):
--     Edit details. Only the fields sent change, null included; the customer
--     follows for the fields changed, with rule 2 for the date of birth and a
--     reason for a new phone; the source is an Owner's or Manager's; a
--     deleted customer's survey is not edited; one audit row
--     survey_particulars_edited holds the old and new values (survey and
--     customer). It locks the customer before the survey, as a customer edit
--     does, so the two cannot deadlock. update_survey_particulars (17
--     arguments) is dropped: one Edit details function, as 386/388/390 did.
--   * review_health_survey(..., p_clear) (made again with p_clear, the old
--     five-argument one dropped): emptying all three texts of a saved review
--     needs p_clear, otherwise "Nothing to save"; a save that changes nothing
--     writes nothing. Owners and Managers, as before, through
--     require_active_staff.
--   * add_survey_attachment (rewritten): records a file only when it is in
--     storage in its survey's folder (<store>/<survey>/, or null/<survey>/
--     while the survey has no store), with storage's size and type; the same
--     file twice is recorded once. Owners and Managers, as before.
--   * health_survey_detail (rewritten): require_active_staff first; has_pdf
--     follows the PDF's read rule, and pdf_other_store says when it is
--     another store's.
--   * survey_link_info (rewritten): an event link's source (when still
--     offered), for the page.
--   * customer_survey_overview (418's, patched): the Health Surveys list
--     shows the consultant's findings, so it is for active Owners, Admins,
--     Managers and Staff (rule 4), as the other survey functions are.
--   * report_customer_sources (patched): a held form that staff put into a
--     customer's record counts once in Customer Sources (Dashboard and
--     Reports), by that record, as when the customer signs the record
--     straight from the QR form. The form kept as sent is not counted again.
--   * can_view_health_data() (new; answers about the caller only): rule 4.
--     The read rules "read surveys", "read survey symptoms", "read consultant
--     notes", "read customer remarks" and "read survey pdfs" use it, as
--     (select ...); the PDFs keep their store test.
--   * survey_links.source_option_id (new column): how an event link's
--     customers heard about us, chosen when the link is made.
--   * health_surveys_sex_check takes 'other' too (Edit details offers Other,
--     as a customer's gender does).
--   * The survey-attachments bucket: 10 MB at most, of the types the page
--     offers (photos, PDF, Word, Excel, CSV, text).
--
-- NOT CHANGED
--
--   * customer_centre_visit_days (the visit rule), 433's holds and close,
--     the TikTok engine, add_consultant_note, consultant_notes_for,
--     add_customer_remark, delete_survey_attachment and the storage rules.
--     Who may do what in every function changed, except that Inventory
--     Managers can no longer edit a survey's details (418's rule 3) or read
--     health data through the tables or the Health Surveys list, and that
--     staff start a survey only at a store they work at (Owners, Admins and
--     Managers at any store, as the page offers).
--   * A customer with a signed survey is still refused a second; a held form
--     still waits for staff.
--   * No row of the app's tables changes. The tidy-ups are the repair script.
--   * The Health Surveys menu item for Inventory Managers is B15's (429).
--   * The 141 files in the 'null' folder stay there.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic, and
--   every check comes before anything changes:
--   * the functions relied on and not changed must be the versions read on
--     18 Oct 2026, 418's assert_customer_dob_change among them (so 418 must
--     be in first); the nine built migrations (417, 418, 420, 422, 423, 424,
--     427, 429, 431) change none of them but that one, so 419 installs
--     before or after any of them;
--   * each function changed must be the production version read on 18 Oct
--     2026 (BEFORE: 433's AFTER for the four 433 functions, 418's AFTER for
--     customer_survey_overview) or already this
--     migration's (AFTER), which is left alone; each new one missing or
--     already this; no other function takes their names; each 433 anchor is
--     found exactly once; every text built has the tested md5;
--   * the two old versions must be as read (or gone, once their new ones are
--     there); health_surveys, survey_links, the one-survey-per-customer index,
--     the PDFs' key, the sex rule, the five read rules and the bucket must be
--     as read, or already this migration's.
--   * Afterwards: the AFTER md5s; the grants (changed functions keep theirs;
--     the new staff functions are signed-in users' and the server's; the
--     internal one the server's; the public form stays open to anon); the
--     read rules, the sex rule, the column and the bucket. Then, inside a
--     block that is always undone, made-up staff start a survey at their one
--     store and save one answer (the others stay Not answered), are refused a
--     filled-in date of birth and a review; a made-up Owner saves a review
--     and emptied boxes do not blank it; a made-up customer signs the QR form
--     into their consultant record (review kept, their answer wins, the
--     link's source recorded, no PDF flagged); and a made-up Inventory
--     Manager reads no survey and gets no survey list. Nothing is printed
--     and no row remains.
--   A second run changes nothing.
--
-- BEFORE -> AFTER (md5 of pg_get_functiondef, search_path public):
--   can_view_health_data()                                           (new)                              -> 5cccb54dd99d2c3d77548cd8242ea126
--   health_survey_sign_into_record(uuid,health_surveys,jsonb,text)   (new)                              -> ac2bbd3742f3b4364b289ddd29715215
--   update_survey_particulars_v2(uuid,jsonb,text)                    (new)                              -> 45ebc42b54405810b104d4c0c292dcf5
--   upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid) d653a0edddef3023b7dac7b0f97e0964   -> e5e6922d5fbe16ee81d44246cabd9d60
--   survey_link_info(text)                                           42224d4abc8e020c1beeef4758d209a4   -> 626e3bdd4d29e7508a8520fbae11b826
--   add_survey_attachment(uuid,text,text,text,integer,text)          8696f2795f7209baca8df5d5a23f96de   -> a856b3463d4e9c8784e2cf1e6d2b649b
--   health_survey_detail(uuid)                                       e04b50ad8507d77e9436e2a2a84766d1   -> 2aa7515661ea56171be26657a3ea7af5
--   review_health_survey(uuid,text,text,text,text,boolean)           (new)                              -> 46bddd90d9badfae99cff53379275e64
--   submit_health_survey(text,jsonb,jsonb,text)                      5a3f27a0b9a0bed619ac0c82c8c52aab   -> ad2a66909b663026911dff137ab12185
--   attach_held_health_survey(uuid,uuid,text)                        104370324b701192ba9710d515cc388f   -> 53aabcdd564da445131633c41bef8249
--   health_survey_holds_list()                                       c3f50d90ba0509935681e4446bcbb21b   -> 0487502f033b56452140c81e108a8ebc
--   create_customer_from_held_survey(uuid,text)                      d503d8b599f90768c8d909b91cd453e1   -> 733db65d708db7c64b5c4de03493d409
--   diagnose_survey_name_edit(text)                                  61dbfdce22e0db89b3cc527bf8d62e25   -> 06b97410274c13feec87ab83621877c1
--   customer_survey_overview(text,text,integer,integer)              35ca42db5c30258f0c4d0026334fed2c   -> d0301231179b3d05107e3309264692ff  (BEFORE is 418's AFTER)
--   report_customer_sources(date,date)                               de5b160f34a49ff254c8f93cdc0f5106   -> 285e5b21754cf3fecababe3058a8bf58
--   update_survey_particulars(uuid,text,text,text,text,date,text,text,text,uuid,text,boolean,boolean,boolean,boolean,text,jsonb)
--                                                                     a8ab6926b33045dfc8c714d3840fe0a3   -> dropped
--   review_health_survey(uuid,text,text,text,text)                    55a53371798b5c145d7f14cf6ba5d479   -> dropped
--   relied on, not changed: assert_customer_dob_change 3d9fc369 (418), require_active_staff 877b3aa7,
--   current_user_role 519b0a33, is_manager_or_above f12b9ed3,
--   is_owner_or_manager 125dec10, user_has_store_access 8c82c6bc, write_audit_ex c705c733,
--   join_person_name 50b6cd36, normalize_customer_phone b2bfac91, sg_today 1c1289f1,
--   trg_health_survey_guard 68234ede, trg_survey_inherit_customer 5b145a04,
--   trg_sync_customer_to_surveys a316d1e7, trg_sync_person_name bdfc01a2, trg_sync_survey_age a59e49b9,
--   audit_customer_phone_change 414b5857, customer_centre_visit_days 2129857d,
--   customer_phone_name_matches 1bdf8322, customer_names_match ef1af52e, customer_email_match_key be468815,
--   normalize_customer_match_name 05727647, require_resolved_customer_identity 5bde1a41
--   read rules: "read surveys", "read survey symptoms", "read consultant notes", "read customer remarks"
--   (current_user_role() IS NOT NULL) -> ( SELECT can_view_health_data() ...); "read survey pdfs" keeps
--   its store test inside the same.
--   public function fingerprint: production 18 Oct 2026 (after 433) ff637c8e7adc37a4892a6bf361290c4b;
--   with 418 53ee9dcef7c77fcfd1e365a3ff47fb22 -> with 418 and 419 3df01342664c71d01db4b95e803fa731;
--   with the nine built migrations in the planned order, then 419: 735af0ffdb2f0fb5fae4c3ef62e9cd3d
--
-- DEPLOY ORDER: after 418 (it refuses without 418's assert_customer_dob_change);
-- 433 is live. Then the front end at once: the Health Surveys page, the
-- survey window, the files, the To match panel, the public QR form and its
-- PDF. Until the front end is out, the old window's Edit details fails (no
-- update_survey_particulars), and the old Start survey, which sends no store,
-- fails for Owners and for staff at two stores ("Choose the store"); every
-- other page keeps working (the old Save Review and the old QR form call the
-- new functions as before). The new page against a database without 419
-- fails Edit details and new QR links (no source_option_id). Run the repair
-- script soon after, with the Owner's go-ahead: part a before the customers
-- concerned sign the QR form. Once 419 is in, 418 cannot run again: 419
-- changed 418's customer_survey_overview, so 418's guards refuse and nothing
-- changes (as 433's do). The 418 test files apply 418 only where it is not
-- in yet.
--
-- Test: scripts/survey/tests/health-surveys-419.sql (-v mig=this file; S, D,
-- R, Q, A, P, G), scripts/survey/tests/survey-repairs-419.sql (the repair),
-- scripts/survey/tests/qr-holds.sql (433's checks, on 419's versions),
-- scripts/permissions/tests/function-grants.sql and staff-only-functions.sql,
-- scripts/reports/tests/reports-367.sql (Customer Sources); the pages:
-- scripts/survey/tests/*.test.mjs.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New and rewritten functions, as pg_get_functiondef gives them back ────
  c_can_view_health_data_def constant text := $def$CREATE OR REPLACE FUNCTION public.can_view_health_data()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 419 (CUSTOMERS-M2): who may read customers' health data in the read
  -- rules of health surveys, their symptoms, the signed PDFs, consultant
  -- notes and consultation remarks: active Owners, Admins, Managers and
  -- Staff. Not an Inventory Manager, whose work is stock (as already in
  -- health_survey_detail and the survey files). It answers only about the
  -- caller.
  select coalesce(public.current_user_role()::text in ('owner', 'admin', 'manager', 'staff'), false)
$function$
$def$;
  c_health_survey_sign_into_record_def constant text := $def$CREATE OR REPLACE FUNCTION public.health_survey_sign_into_record(p_into uuid, p_form health_surveys, p_symptoms jsonb, p_pdf_base64 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_fields constant text[] := array['survey_link_id', 'event_name', 'store_id', 'date_of_birth', 'age', 'sex', 'phone',
                                    'email', 'occupation', 'has_medical_condition', 'drinks_alcohol', 'smokes',
                                    'on_treatment', 'treatment_list', 'others_text', 'consent_newsletter_email',
                                    'consent_marketing_email', 'consent_marketing_sms', 'consent_marketing_phone',
                                    'signed_date', 'source_option_id', 'source_label', 'source_details', 'source',
                                    'submitted_at', 'pdf_url'];
  v_old public.health_surveys%rowtype; v_new public.health_surveys%rowtype;
  v_empty boolean; v_has_source boolean; v_old_syms jsonb; v_new_syms jsonb; v_sym jsonb; v_key text;
  v_before jsonb := '{}'::jsonb; v_after jsonb := '{}'::jsonb;
begin
  -- 419: the Owner's answer to Q10 (9 Oct 2026). A customer whose survey is a
  -- consultant's record they have not signed may fill in the QR form; their
  -- signed answers go into that record. The consultant's findings, notes,
  -- remarks and files stay. Where the two differ the customer's own answers
  -- win; an answer they left blank keeps the record's. The record keeps its
  -- name (the customer's) and, once it has one, its source snapshot (only an
  -- Owner or Manager changes that). submit_health_survey (the form itself)
  -- and attach_held_health_survey (a held form staff attach) call this; it
  -- is internal, the server's alone.
  --
  -- A record nobody wrote anything on (no finding, no yes/no answer, no
  -- symptom, no consultant note with text or a file, no file: the empty
  -- record the Surveys page made when staff opened a customer) becomes the QR
  -- form it now is: source public_form, dated when the form was sent. So the
  -- visit rule (customer_centre_visit_days) and TikTok attendance read it as
  -- any QR form. A record with the consultant's work keeps source consultant
  -- and its date, so its visit stays dated by that work.
  select * into v_old from public.health_surveys where id = p_into for update;
  if not found or v_old.source <> 'consultant' or v_old.signature_data is not null then
    raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
  end if;
  if nullif(p_form.signature_data, '') is null then
    raise exception 'Signature is required.';
  end if;
  v_empty := coalesce(nullif(btrim(v_old.acidity_result), ''), nullif(btrim(v_old.remarks_condition), ''),
                      nullif(btrim(v_old.remarks_recommendation), ''), nullif(btrim(v_old.health_goals), ''),
                      nullif(btrim(v_old.treatment_list), ''), nullif(btrim(v_old.others_text), '')) is null
             and v_old.has_medical_condition is null and v_old.drinks_alcohol is null
             and v_old.smokes is null and v_old.on_treatment is null
             and not exists (select 1 from public.health_survey_symptoms y where y.survey_id = v_old.id)
             and not exists (select 1 from public.consultant_notes n
                              where n.survey_id = v_old.id
                                and (coalesce(nullif(btrim(n.acidity_result), ''), nullif(btrim(n.health_goals), ''),
                                              nullif(btrim(n.remarks_condition), ''),
                                              nullif(btrim(n.remarks_recommendation), '')) is not null
                                     or (jsonb_typeof(n.attachments) = 'array' and jsonb_array_length(n.attachments) > 0)))
             and not exists (select 1 from public.health_survey_attachments f where f.survey_id = v_old.id);
  v_has_source := v_old.source_option_id is not null or v_old.source_label is not null;
  select coalesce(jsonb_agg(jsonb_build_object('option_id', y.option_id, 'duration_text', y.duration_text)
                            order by y.option_id), '[]'::jsonb)
    into v_old_syms
    from public.health_survey_symptoms y where y.survey_id = v_old.id;

  update public.health_surveys hs set
    survey_link_id = coalesce(p_form.survey_link_id, hs.survey_link_id),
    event_name = coalesce(nullif(btrim(p_form.event_name), ''), hs.event_name),
    store_id = coalesce(hs.store_id, p_form.store_id),
    date_of_birth = coalesce(p_form.date_of_birth, hs.date_of_birth),
    age = coalesce(p_form.age, hs.age),
    sex = coalesce(nullif(btrim(p_form.sex), ''), hs.sex),
    phone = coalesce(nullif(btrim(p_form.phone), ''), hs.phone),
    email = coalesce(nullif(btrim(p_form.email), ''), hs.email),
    occupation = coalesce(nullif(btrim(p_form.occupation), ''), hs.occupation),
    has_medical_condition = coalesce(p_form.has_medical_condition, hs.has_medical_condition),
    drinks_alcohol = coalesce(p_form.drinks_alcohol, hs.drinks_alcohol),
    smokes = coalesce(p_form.smokes, hs.smokes),
    on_treatment = coalesce(p_form.on_treatment, hs.on_treatment),
    treatment_list = case when p_form.on_treatment is false then null
                          else coalesce(nullif(btrim(p_form.treatment_list), ''), hs.treatment_list) end,
    others_text = coalesce(nullif(btrim(p_form.others_text), ''), hs.others_text),
    consent_newsletter_email = coalesce(p_form.consent_newsletter_email, false),
    consent_marketing_email = coalesce(p_form.consent_marketing_email, false),
    consent_marketing_sms = coalesce(p_form.consent_marketing_sms, false),
    consent_marketing_phone = coalesce(p_form.consent_marketing_phone, false),
    signature_data = p_form.signature_data,
    signed_date = coalesce(p_form.signed_date, public.sg_today()),
    ip_address = coalesce(p_form.ip_address, hs.ip_address),
    device_info = coalesce(p_form.device_info, hs.device_info),
    source_option_id = case when v_has_source then hs.source_option_id else p_form.source_option_id end,
    source_label = case when v_has_source then hs.source_label else p_form.source_label end,
    source_details = case when v_has_source then hs.source_details else p_form.source_details end,
    source = case when v_empty then 'public_form' else hs.source end,
    submitted_at = case when v_empty then coalesce(p_form.submitted_at, now()) else hs.submitted_at end
  where hs.id = v_old.id;

  -- The symptoms the customer ticked are the record's (none ticked is an
  -- answer too). The list it had is kept in the audit row.
  if p_symptoms is not null then
    delete from public.health_survey_symptoms where survey_id = v_old.id;
    for v_sym in select * from jsonb_array_elements(p_symptoms) loop
      insert into public.health_survey_symptoms (survey_id, option_id, duration_text)
      values (v_old.id, (v_sym->>'option_id')::uuid, nullif(trim(v_sym->>'duration_text'),''))
      on conflict do nothing;
    end loop;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('option_id', y.option_id, 'duration_text', y.duration_text)
                            order by y.option_id), '[]'::jsonb)
    into v_new_syms
    from public.health_survey_symptoms y where y.survey_id = v_old.id;

  if p_pdf_base64 is not null and length(p_pdf_base64) > 0 then
    if length(p_pdf_base64) > 8000000 then raise exception 'The signed document is too large.'; end if;
    insert into public.health_survey_pdfs (survey_id, pdf_base64, byte_size)
    values (v_old.id, p_pdf_base64, length(p_pdf_base64))
    on conflict (survey_id) do update
      set pdf_base64 = excluded.pdf_base64, byte_size = excluded.byte_size, generated_at = now();
    update public.health_surveys set pdf_url = 'stored' where id = v_old.id;
  end if;

  select * into v_new from public.health_surveys where id = v_old.id;
  foreach v_key in array c_fields loop
    if (to_jsonb(v_new) -> v_key) is distinct from (to_jsonb(v_old) -> v_key) then
      v_before := v_before || jsonb_build_object(v_key, to_jsonb(v_old) -> v_key);
      v_after := v_after || jsonb_build_object(v_key, to_jsonb(v_new) -> v_key);
    end if;
  end loop;
  if v_new_syms is distinct from v_old_syms then
    v_before := v_before || jsonb_build_object('symptoms', v_old_syms);
    v_after := v_after || jsonb_build_object('symptoms', v_new_syms);
  end if;
  perform public.write_audit_ex('health_surveys', v_old.id, 'health_survey_signed_by_customer', v_before,
    v_after || jsonb_build_object('survey_no', v_old.survey_no, 'record_was_empty', v_empty,
                                  'signed_pdf', p_pdf_base64 is not null and length(p_pdf_base64) > 0),
    'health_survey', null, v_new.store_id, p_form.ip_address, p_form.device_info);
  return jsonb_build_object('survey_id', v_old.id, 'survey_no', v_old.survey_no, 'record_was_empty', v_empty);
end $function$
$def$;
  c_update_survey_particulars_v2_def constant text := $def$CREATE OR REPLACE FUNCTION public.update_survey_particulars_v2(p_survey_id uuid, p_changes jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_keys constant text[] := array['first_name', 'last_name', 'phone', 'email', 'date_of_birth', 'sex', 'occupation',
                                  'others_text', 'source_option_id', 'source_details', 'has_medical_condition',
                                  'drinks_alcohol', 'smokes', 'on_treatment', 'treatment_list', 'symptoms'];
  c_fields constant text[] := array['first_name', 'last_name', 'full_name', 'phone', 'email', 'date_of_birth', 'sex',
                                    'occupation', 'others_text', 'source_option_id', 'source_label', 'source_details',
                                    'has_medical_condition', 'drinks_alcohol', 'smokes', 'on_treatment',
                                    'treatment_list'];
  c_cust_fields constant text[] := array['first_name', 'last_name', 'full_name', 'phone', 'email', 'date_of_birth',
                                         'gender', 'occupation', 'source_option_id', 'source_label', 'source_details'];
  v_role public.user_role;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_old public.health_surveys%rowtype; v_new public.health_surveys%rowtype;
  v_cold public.customers%rowtype; v_cnew public.customers%rowtype; v_cid uuid;
  v_key text; v_label text;
  v_old_syms jsonb; v_new_syms jsonb;
  v_before jsonb := '{}'::jsonb; v_after jsonb := '{}'::jsonb;
  v_cbefore jsonb := '{}'::jsonb; v_cafter jsonb := '{}'::jsonb;
begin
  v_role := public.require_active_staff('{owner,admin,manager,staff}');  -- 406: active staff; not Inventory Managers
  -- 419 (CUSTOMERS-4, the survey part of CUSTOMERS-9): Edit details on a
  -- health survey. It replaces update_survey_particulars, which saved every
  -- field each time: a declaration never answered became "No", a date of
  -- birth already filled in could be changed by anyone, and the old values
  -- were not kept.
  --   * p_changes holds only the fields being changed. A field present is
  --     set, null included ("Not answered"); symptoms, when present,
  --     replaces the list.
  --   * Owners, Managers and Staff (and the old Admin role) edit, as before.
  --     How the customer heard about us is an Owner's or a Manager's, as the
  --     page and the survey's own rule say.
  --   * The customer's details follow the survey's, as before, but only for
  --     the fields changed. Their date of birth follows
  --     assert_customer_dob_change (the Owner, 9 Oct 2026, Q9 A: anyone fills
  --     in a missing one; changing or clearing one needs an Owner or Manager
  --     and a reason). A new phone for the customer needs a reason, as on the
  --     Customers page.
  --   * A deleted customer's survey is not edited.
  --   * One audit row, survey_particulars_edited, holds the old and the new
  --     value of every field that changed, the survey's and the customer's.
  if p_survey_id is null then raise exception 'A survey is required'; end if;
  if jsonb_typeof(p_changes) is distinct from 'object' then
    raise exception 'The changes must be a list of fields and their new values';
  end if;
  select k into v_key from jsonb_object_keys(p_changes) k where not (k = any (c_keys)) order by k limit 1;
  if v_key is not null then
    raise exception 'The field "%" cannot be changed here', v_key;
  end if;
  foreach v_key in array array['has_medical_condition', 'drinks_alcohol', 'smokes', 'on_treatment'] loop
    if p_changes ? v_key and jsonb_typeof(p_changes -> v_key) not in ('boolean', 'null') then
      raise exception 'Each declaration must be Yes, No or Not answered';
    end if;
  end loop;

  -- The customer is locked before the survey, as a customer edit does (its
  -- trigger then changes the survey), so the two never wait on each other.
  select hs.customer_id into v_cid from public.health_surveys hs where hs.id = p_survey_id;
  if not found then raise exception 'Submission not found'; end if;
  if v_cid is not null then
    select * into v_cold from public.customers where id = v_cid for update;
  end if;
  select * into v_old from public.health_surveys where id = p_survey_id for update;
  if not found then raise exception 'Submission not found'; end if;
  if v_old.customer_id is distinct from v_cid then
    raise exception 'The survey changed; open it again.';
  end if;
  if v_old.customer_id is not null and v_cold.deleted_at is not null then
    raise exception 'That customer has been deleted. Restore them before changing their details.';
  end if;

  v_new := v_old;
  if p_changes ? 'first_name' then
    v_new.first_name := nullif(btrim(coalesce(p_changes->>'first_name', '')), '');
  end if;
  if p_changes ? 'last_name' then
    v_new.last_name := nullif(btrim(coalesce(p_changes->>'last_name', '')), '');
  end if;
  if p_changes ? 'first_name' or p_changes ? 'last_name' then
    if nullif(btrim(coalesce(v_new.first_name, '')), '') is null then
      raise exception 'A first name is required';
    end if;
    v_new.full_name := public.join_person_name(v_new.first_name, v_new.last_name);
  end if;
  if p_changes ? 'phone' then
    v_new.phone := nullif(btrim(coalesce(p_changes->>'phone', '')), '');
  end if;
  if p_changes ? 'email' then
    v_new.email := nullif(btrim(coalesce(p_changes->>'email', '')), '');
  end if;
  if p_changes ? 'date_of_birth' then
    begin
      v_new.date_of_birth := nullif(btrim(coalesce(p_changes->>'date_of_birth', '')), '')::date;
    exception when invalid_datetime_format or datetime_field_overflow then
      raise exception 'The date of birth is not a valid date';
    end;
  end if;
  if p_changes ? 'sex' then
    v_new.sex := nullif(lower(btrim(coalesce(p_changes->>'sex', ''))), '');
    if v_new.sex is not null and v_new.sex not in ('female', 'male', 'other') then
      raise exception 'Sex must be Female, Male or Other';
    end if;
  end if;
  if p_changes ? 'occupation' then
    v_new.occupation := nullif(btrim(coalesce(p_changes->>'occupation', '')), '');
  end if;
  if p_changes ? 'others_text' then
    v_new.others_text := nullif(btrim(coalesce(p_changes->>'others_text', '')), '');
  end if;
  if p_changes ? 'source_option_id' then
    begin
      v_new.source_option_id := nullif(btrim(coalesce(p_changes->>'source_option_id', '')), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'That source is not available';
    end;
    if v_new.source_option_id is distinct from v_old.source_option_id then
      if v_role is not null and v_role not in ('owner', 'manager') then
        raise exception 'Only an Owner or Manager can change how the customer heard about us.'
          using errcode = '42501';
      end if;
      if v_new.source_option_id is null then
        raise exception 'Customer source is mandatory on a health survey and cannot be removed';
      end if;
      select o.label into v_label from public.customer_source_options o where o.id = v_new.source_option_id;
      if v_label is null then raise exception 'That source is not available'; end if;
      v_new.source_label := v_label;
    end if;
  end if;
  if p_changes ? 'source_details' then
    v_new.source_details := nullif(btrim(coalesce(p_changes->>'source_details', '')), '');
  end if;
  if p_changes ? 'has_medical_condition' then
    v_new.has_medical_condition := (p_changes->>'has_medical_condition')::boolean;
  end if;
  if p_changes ? 'drinks_alcohol' then
    v_new.drinks_alcohol := (p_changes->>'drinks_alcohol')::boolean;
  end if;
  if p_changes ? 'smokes' then
    v_new.smokes := (p_changes->>'smokes')::boolean;
  end if;
  if p_changes ? 'on_treatment' then
    v_new.on_treatment := (p_changes->>'on_treatment')::boolean;
  end if;
  if p_changes ? 'treatment_list' then
    v_new.treatment_list := nullif(btrim(coalesce(p_changes->>'treatment_list', '')), '');
  end if;
  if p_changes ? 'on_treatment' and v_new.on_treatment is false then
    v_new.treatment_list := null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('option_id', y.option_id, 'duration_text', y.duration_text)
                            order by y.option_id), '[]'::jsonb)
    into v_old_syms
    from public.health_survey_symptoms y where y.survey_id = v_old.id;
  v_new_syms := v_old_syms;
  if p_changes ? 'symptoms' then
    if jsonb_typeof(p_changes -> 'symptoms') is distinct from 'array' then
      raise exception 'The symptoms must be a list';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('option_id', x.option_id, 'duration_text', x.duration_text)
                              order by x.option_id), '[]'::jsonb)
      into v_new_syms
      from (select distinct on ((e->>'option_id')::uuid) (e->>'option_id')::uuid as option_id,
                   nullif(btrim(coalesce(e->>'duration_text', '')), '') as duration_text
              from jsonb_array_elements(p_changes -> 'symptoms') e
             order by (e->>'option_id')::uuid) x;
  end if;

  foreach v_key in array c_fields loop
    if (to_jsonb(v_new) -> v_key) is distinct from (to_jsonb(v_old) -> v_key) then
      v_before := v_before || jsonb_build_object(v_key, to_jsonb(v_old) -> v_key);
      v_after := v_after || jsonb_build_object(v_key, to_jsonb(v_new) -> v_key);
    end if;
  end loop;
  if v_new_syms is distinct from v_old_syms then
    v_before := v_before || jsonb_build_object('symptoms', v_old_syms);
    v_after := v_after || jsonb_build_object('symptoms', v_new_syms);
  end if;

  -- The customer follows the survey, for the fields changed.
  if v_old.customer_id is not null then
    v_cnew := v_cold;
    if v_after ? 'full_name' or v_after ? 'first_name' or v_after ? 'last_name' then
      v_cnew.first_name := v_new.first_name;
      v_cnew.last_name := v_new.last_name;
      v_cnew.full_name := v_new.full_name;
    end if;
    if v_after ? 'phone' and v_new.phone is not null then
      v_cnew.phone := coalesce(public.normalize_customer_phone(v_new.phone), v_new.phone);
    end if;
    if v_after ? 'email' and v_new.email is not null then
      v_cnew.email := v_new.email;
    end if;
    if v_after ? 'date_of_birth' then
      v_cnew.date_of_birth := v_new.date_of_birth;
    end if;
    if v_after ? 'sex' and v_new.sex is not null then
      v_cnew.gender := v_new.sex::public.customer_gender;
    end if;
    if v_after ? 'occupation' and v_new.occupation is not null then
      v_cnew.occupation := v_new.occupation;
    end if;
    if v_after ? 'source_option_id' then
      v_cnew.source_option_id := v_new.source_option_id;
      v_cnew.source_label := v_new.source_label;
    end if;
    if v_after ? 'source_details' and v_new.source_details is not null then
      v_cnew.source_details := v_new.source_details;
    end if;
    foreach v_key in array c_cust_fields loop
      if (to_jsonb(v_cnew) -> v_key) is distinct from (to_jsonb(v_cold) -> v_key) then
        v_cbefore := v_cbefore || jsonb_build_object(v_key, to_jsonb(v_cold) -> v_key);
        v_cafter := v_cafter || jsonb_build_object(v_key, to_jsonb(v_cnew) -> v_key);
      end if;
    end loop;
    if v_cafter ? 'date_of_birth' then
      perform public.assert_customer_dob_change(v_cold.id, v_cnew.date_of_birth, v_reason);
    end if;
    if v_cafter ? 'phone' then
      if v_reason is null then
        raise exception 'A reason is required to change a customer''s phone number';
      end if;
      perform set_config('energia.phone_change_reason', v_reason, true);
    end if;
  end if;

  if v_after = '{}'::jsonb then
    return jsonb_build_object('survey_id', v_old.id, 'changed', '[]'::jsonb, 'customer_changed', '[]'::jsonb);
  end if;

  update public.health_surveys hs set
    first_name = v_new.first_name, last_name = v_new.last_name, full_name = v_new.full_name,
    phone = v_new.phone, email = v_new.email, date_of_birth = v_new.date_of_birth, sex = v_new.sex,
    occupation = v_new.occupation, others_text = v_new.others_text,
    source_option_id = v_new.source_option_id, source_label = v_new.source_label,
    source_details = v_new.source_details,
    has_medical_condition = v_new.has_medical_condition, drinks_alcohol = v_new.drinks_alcohol,
    smokes = v_new.smokes, on_treatment = v_new.on_treatment, treatment_list = v_new.treatment_list
   where hs.id = v_old.id;
  if v_after ? 'symptoms' then
    delete from public.health_survey_symptoms where survey_id = v_old.id;
    insert into public.health_survey_symptoms (survey_id, option_id, duration_text)
    select v_old.id, (e->>'option_id')::uuid, e->>'duration_text'
      from jsonb_array_elements(v_new_syms) e;
  end if;
  if v_cafter <> '{}'::jsonb then
    update public.customers c set
      first_name = v_cnew.first_name, last_name = v_cnew.last_name, full_name = v_cnew.full_name,
      phone = v_cnew.phone, email = v_cnew.email, date_of_birth = v_cnew.date_of_birth,
      gender = v_cnew.gender, occupation = v_cnew.occupation,
      source_option_id = v_cnew.source_option_id, source_label = v_cnew.source_label,
      source_details = v_cnew.source_details,
      source_updated_at = case when v_cafter ? 'source_option_id' then now() else c.source_updated_at end
     where c.id = v_cold.id;
  end if;

  perform public.write_audit_ex('health_surveys', v_old.id, 'survey_particulars_edited',
    v_before || case when v_cbefore <> '{}'::jsonb then jsonb_build_object('customer', v_cbefore) else '{}'::jsonb end,
    v_after || jsonb_build_object('name', v_new.full_name)
            || case when v_cafter <> '{}'::jsonb then jsonb_build_object('customer', v_cafter) else '{}'::jsonb end,
    'survey', v_reason, v_old.store_id);
  return jsonb_build_object('survey_id', v_old.id,
                            'changed', (select jsonb_agg(k order by k) from jsonb_object_keys(v_after) k),
                            'customer_changed', coalesce((select jsonb_agg(k order by k) from jsonb_object_keys(v_cafter) k),
                                                         '[]'::jsonb));
end $function$
$def$;
  c_upsert_consultant_survey_def constant text := $def$CREATE OR REPLACE FUNCTION public.upsert_consultant_survey(p_customer_id uuid, p_remarks_condition text DEFAULT NULL::text, p_remarks_recommendation text DEFAULT NULL::text, p_acidity_result text DEFAULT NULL::text, p_health_goals text DEFAULT NULL::text, p_has_medical_condition boolean DEFAULT NULL::boolean, p_drinks_alcohol boolean DEFAULT NULL::boolean, p_smokes boolean DEFAULT NULL::boolean, p_on_treatment boolean DEFAULT NULL::boolean, p_treatment_list text DEFAULT NULL::text, p_store_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_fields constant text[] := array['store_id', 'remarks_condition', 'remarks_recommendation', 'acidity_result',
                                    'health_goals', 'has_medical_condition', 'drinks_alcohol', 'smokes',
                                    'on_treatment', 'treatment_list'];
  c public.customers%rowtype; v_no text; v_store uuid; v_role public.user_role;
  v_old public.health_surveys%rowtype; v_new public.health_surveys%rowtype;
  v_findings boolean; v_key text; v_before jsonb := '{}'::jsonb; v_after jsonb := '{}'::jsonb;
begin
  -- 406: active staff only, not Inventory Managers (health declarations are not
  -- their remit, as in health_survey_detail). The consultant's findings are an
  -- Owner's or a Manager's, as in review_health_survey.
  v_role := public.require_active_staff('{owner,admin,manager,staff}');
  v_findings := coalesce(p_remarks_condition, p_remarks_recommendation, p_acidity_result, p_health_goals) is not null;
  if v_role is not null and v_role not in ('owner', 'manager') and v_findings then
    raise exception 'Only an Owner or Manager can write the consultant''s findings'
      using errcode = '42501';
  end if;
  if p_acidity_result is not null and p_acidity_result not in ('red', 'green', 'blue') then
    raise exception 'Acidity result must be Red, Green or Blue';
  end if;
  -- 406: the row lock makes a second quick click wait and then find the first
  -- click's survey, instead of failing on the one-survey-per-customer rule.
  select * into c from public.customers where id = p_customer_id for update;
  if not found or c.deleted_at is not null then raise exception 'Customer not found'; end if;

  -- 419 (CUSTOMERS-M1): a new survey belongs to the store chosen when it is
  -- started (staff must work there; Owners, Admins and Managers reach every
  -- store, as the page's store list and the signed PDF's rule say), else to
  -- the caller's one store, else to the business's one store. Otherwise the
  -- store must be chosen. Before, it was left empty for Owners, or picked at
  -- random from a person's two stores, and the files went into a 'null'
  -- folder.
  if p_store_id is not null then
    if v_role is not null and not (public.is_manager_or_above() or public.user_has_store_access(p_store_id)) then
      raise exception 'That belongs to a store you are not assigned to.' using errcode = '42501';
    end if;
    if not exists (select 1 from public.stores s where s.id = p_store_id and s.deleted_at is null) then
      raise exception 'That store is not available.';
    end if;
    v_store := p_store_id;
  end if;

  select * into v_old from public.health_surveys where customer_id = p_customer_id for update;

  if v_old.id is null then
    if v_store is null then
      select case when count(*) = 1 then (array_agg(usa.store_id))[1] end into v_store
        from public.user_store_assignments usa
        join public.stores s on s.id = usa.store_id and s.deleted_at is null and coalesce(s.is_active, true)
       where usa.user_id = auth.uid();
    end if;
    if v_store is null then
      select case when count(*) = 1 then (array_agg(s.id))[1] end into v_store
        from public.stores s
       where s.deleted_at is null and coalesce(s.is_active, true);
    end if;
    if v_store is null then
      raise exception 'Choose the store for this survey.';
    end if;
    v_no := 'HS-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);  -- 406: the Singapore date
    insert into public.health_surveys (
      survey_no, store_id, customer_id, source, created_by,
      full_name, phone, email, date_of_birth, occupation,
      has_medical_condition, drinks_alcohol, smokes, on_treatment, treatment_list,
      acidity_result, remarks_condition, remarks_recommendation, health_goals,
      reviewed_by, reviewed_at, submitted_at)
    values (v_no, v_store, p_customer_id, 'consultant', auth.uid(),
      c.full_name,
      -- Legacy placeholder phones are not real numbers; store null instead.
      nullif(c.phone, ''), c.email, c.date_of_birth, c.occupation,
      p_has_medical_condition, p_drinks_alcohol, p_smokes, p_on_treatment, p_treatment_list,
      p_acidity_result, p_remarks_condition, p_remarks_recommendation, p_health_goals,
      case when v_findings then auth.uid() end, case when v_findings then now() end,
      now())
    returning * into v_new;
  else
    -- 419 (CUSTOMERS-2): an existing survey changes only in the fields sent (a
    -- field left out, or null, keeps its value), and only a finding written by
    -- an Owner or Manager marks it reviewed. Before, any call, even with
    -- nothing in it, marked a QR form reviewed. Its store is set only when it
    -- has none.
    update public.health_surveys hs set
      store_id = coalesce(hs.store_id, v_store),
      remarks_condition = coalesce(p_remarks_condition, hs.remarks_condition),
      remarks_recommendation = coalesce(p_remarks_recommendation, hs.remarks_recommendation),
      acidity_result = coalesce(p_acidity_result, hs.acidity_result),
      health_goals = coalesce(p_health_goals, hs.health_goals),
      has_medical_condition = coalesce(p_has_medical_condition, hs.has_medical_condition),
      drinks_alcohol = coalesce(p_drinks_alcohol, hs.drinks_alcohol),
      smokes = coalesce(p_smokes, hs.smokes),
      on_treatment = coalesce(p_on_treatment, hs.on_treatment),
      treatment_list = coalesce(p_treatment_list, hs.treatment_list),
      reviewed_by = case when v_findings then auth.uid() else hs.reviewed_by end,
      reviewed_at = case when v_findings then now() else hs.reviewed_at end
    where hs.id = v_old.id
    returning * into v_new;
  end if;

  -- 419: the history keeps the old and the new value of each field saved.
  foreach v_key in array c_fields loop
    if (to_jsonb(v_new) -> v_key) is distinct from (to_jsonb(v_old) -> v_key) then
      v_before := v_before || jsonb_build_object(v_key, to_jsonb(v_old) -> v_key);
      v_after := v_after || jsonb_build_object(v_key, to_jsonb(v_new) -> v_key);
    end if;
  end loop;
  if v_old.id is null or v_after <> '{}'::jsonb then
    perform public.write_audit_ex('health_surveys', v_new.id, 'consultant_survey_saved',
      case when v_old.id is not null then v_before end,
      jsonb_build_object('customer', p_customer_id) || v_after, 'survey', null, v_new.store_id);
  end if;
  return v_new.id;
end $function$
$def$;
  c_survey_link_info_def constant text := $def$CREATE OR REPLACE FUNCTION public.survey_link_info(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_l public.survey_links%rowtype; v_store public.stores%rowtype; v_src public.customer_source_options%rowtype;
begin
  select * into v_l from public.survey_links where token = p_token;
  if not found then return jsonb_build_object('valid', false, 'reason', 'This survey link is not recognised.'); end if;
  if not v_l.is_active then return jsonb_build_object('valid', false, 'reason', 'This survey link has been deactivated.'); end if;
  if v_l.expires_at is not null and v_l.expires_at < now() then
    return jsonb_build_object('valid', false, 'reason', 'This survey link has expired.'); end if;
  select * into v_store from public.stores where id = v_l.store_id;
  -- 419 (CUSTOMERS-12): an event's link says how its customers heard about
  -- us (chosen when the link was made, and still offered). The form then
  -- skips that question, and submit_health_survey records this source.
  if nullif(btrim(v_l.event_name), '') is not null and v_l.source_option_id is not null then
    select * into v_src from public.customer_source_options o where o.id = v_l.source_option_id and o.is_active;
  end if;
  return jsonb_build_object('valid', true, 'store_name', v_store.name, 'event_name', v_l.event_name,
                            'source_option_id', v_src.id, 'source_label', v_src.label);
end $function$
$def$;
  c_add_survey_attachment_def constant text := $def$CREATE OR REPLACE FUNCTION public.add_survey_attachment(p_survey_id uuid, p_path text, p_file_name text, p_mime text DEFAULT NULL::text, p_size integer DEFAULT NULL::integer, p_caption text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_s public.health_surveys%rowtype; v_id uuid; v_folder text; v_meta jsonb; v_size bigint; v_mime text;
begin
  perform public.require_active_staff('{owner,manager}');  -- 419: active Owners and Managers, as before
  -- 419 (CUSTOMERS-M1): a file is recorded only when it is in storage, in
  -- this survey's own folder (<store>/<survey>/, or null/<survey>/ while the
  -- survey has no store), and its size and type are the ones storage holds,
  -- not what the browser said (p_mime and p_size are no longer used). The
  -- same file sent twice is recorded once.
  select * into v_s from public.health_surveys where id = p_survey_id;
  if not found then raise exception 'Survey not found'; end if;
  v_folder := coalesce(v_s.store_id::text, 'null') || '/' || v_s.id::text || '/';
  if p_path is null or left(p_path, length(v_folder)) <> v_folder or length(p_path) <= length(v_folder)
     or position('/' in substr(p_path, length(v_folder) + 1)) > 0 then
    raise exception 'That file is not in this survey''s folder. Upload it again.';
  end if;
  select a.id into v_id from public.health_survey_attachments a where a.storage_path = p_path;
  if v_id is not null then
    return v_id;
  end if;
  select o.metadata into v_meta from storage.objects o where o.bucket_id = 'survey-attachments' and o.name = p_path;
  if not found then
    raise exception 'That file is not in storage. Upload it again.';
  end if;
  v_size := nullif(v_meta->>'size', '')::bigint;
  v_mime := nullif(v_meta->>'mimetype', '');
  if coalesce(v_size, 0) > 10485760 then raise exception 'Files must be 10 MB or smaller.'; end if;

  insert into public.health_survey_attachments
    (survey_id, storage_path, file_name, mime_type, byte_size, caption, uploaded_by)
  values (v_s.id, p_path, coalesce(nullif(btrim(p_file_name), ''), 'file'), v_mime, v_size::integer,
          nullif(trim(coalesce(p_caption,'')),''), auth.uid())
  returning id into v_id;

  perform public.write_audit_ex('health_survey_attachments', v_id, 'survey_attachment_added',
    null, jsonb_build_object('survey_no', v_s.survey_no, 'file_name', p_file_name, 'bytes', v_size, 'mime_type', v_mime),
    'surveys', null, v_s.store_id);
  return v_id;
end $function$
$def$;
  c_health_survey_detail_def constant text := $def$CREATE OR REPLACE FUNCTION public.health_survey_detail(p_survey_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_s public.health_surveys%rowtype; v_syms jsonb; v_atts jsonb; v_pdf boolean; v_pdf_ok boolean;
begin
  -- 419: active staff, first. Inventory managers stay excluded: stock is
  -- their remit, not customer health declarations.
  perform public.require_active_staff('{owner,admin,manager,staff}');
  select * into v_s from public.health_surveys where id = p_survey_id;
  if not found then return jsonb_build_object('found', false); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'option_id', x.option_id, 'category', o.category, 'label', o.label, 'duration_text', x.duration_text)
         order by o.category, o.sort_order), '[]'::jsonb)
    into v_syms
  from public.health_survey_symptoms x
  join public.health_symptom_options o on o.id = x.option_id
  where x.survey_id = p_survey_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'storage_path', a.storage_path, 'file_name', a.file_name,
           'mime_type', a.mime_type, 'byte_size', a.byte_size, 'caption', a.caption,
           'uploaded_at', a.uploaded_at, 'uploaded_by', a.uploaded_by,
           'uploaded_by_name', (select full_name from public.profiles p where p.id = a.uploaded_by))
         order by a.uploaded_at), '[]'::jsonb)
    into v_atts
  from public.health_survey_attachments a where a.survey_id = p_survey_id;

  -- 419 (CUSTOMERS-14): the signed PDF follows its read rule (Owners, Admins
  -- and Managers, or staff of the survey's store), so the page offers it only
  -- to those who can open it, and tells the others why.
  v_pdf := exists (select 1 from public.health_survey_pdfs p where p.survey_id = p_survey_id);
  v_pdf_ok := public.is_manager_or_above() or public.user_has_store_access(v_s.store_id);

  return jsonb_build_object(
    'found', true,
    'survey', to_jsonb(v_s),
    'symptoms', v_syms,
    'attachments', v_atts,
    'has_pdf', v_pdf and v_pdf_ok,
    'pdf_other_store', v_pdf and not v_pdf_ok,
    'reviewer', (select full_name from public.profiles where id = v_s.reviewed_by));
end $function$
$def$;
  c_review_health_survey_def constant text := $def$CREATE OR REPLACE FUNCTION public.review_health_survey(p_survey_id uuid, p_acidity text DEFAULT NULL::text, p_health_goals text DEFAULT NULL::text, p_condition text DEFAULT NULL::text, p_recommendation text DEFAULT NULL::text, p_clear boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_s public.health_surveys%rowtype; v_goals text; v_cond text; v_rec text;
begin
  perform public.require_active_staff('{owner,manager}');  -- 419: active Owners and Managers, as before

  select * into v_s from public.health_surveys where id = p_survey_id for update;
  if not found then raise exception 'Survey not found'; end if;
  if p_acidity is not null and p_acidity not in ('red','green','blue') then
    raise exception 'Acidity result must be Red, Green or Blue'; end if;
  v_goals := nullif(trim(coalesce(p_health_goals,'')), '');
  v_cond := nullif(trim(coalesce(p_condition,'')), '');
  v_rec := nullif(trim(coalesce(p_recommendation,'')), '');

  -- 419 (CUSTOMERS-K1): pressing Save Review again after the page had emptied
  -- its boxes saved the empty boxes over the review (22 times from 6 Aug to
  -- 15 Oct 2026). Emptying all three texts of a saved review now needs
  -- p_clear; otherwise nothing is saved and the review is kept.
  if not coalesce(p_clear, false) and v_goals is null and v_cond is null and v_rec is null
     and coalesce(nullif(btrim(v_s.health_goals), ''), nullif(btrim(v_s.remarks_condition), ''),
                  nullif(btrim(v_s.remarks_recommendation), '')) is not null then
    raise exception 'Nothing to save: the Goals, Condition and Recommendation boxes are empty, so the saved review is kept.';
  end if;
  -- A save that changes nothing is not saved again.
  if p_acidity is not distinct from v_s.acidity_result and v_goals is not distinct from v_s.health_goals
     and v_cond is not distinct from v_s.remarks_condition and v_rec is not distinct from v_s.remarks_recommendation then
    return;
  end if;

  update public.health_surveys set
    acidity_result = p_acidity,
    health_goals = v_goals,
    remarks_condition = v_cond,
    remarks_recommendation = v_rec,
    reviewed_by = auth.uid(),
    reviewed_at = now()
  where id = p_survey_id;

  perform public.write_audit_ex('health_surveys', p_survey_id, 'health_survey_reviewed',
    jsonb_build_object('acidity', v_s.acidity_result, 'condition', v_s.remarks_condition,
                       'recommendation', v_s.remarks_recommendation, 'health_goals', v_s.health_goals),
    jsonb_build_object('acidity', p_acidity, 'condition', p_condition,
                       'recommendation', p_recommendation, 'health_goals', p_health_goals)
      || case when coalesce(p_clear, false) then jsonb_build_object('cleared', true) else '{}'::jsonb end,
    'surveys', null, v_s.store_id);
end $function$
$def$;
  -- ── The 433 functions: each anchor becomes its patch ──────────────────────
  -- submit_health_survey(text,jsonb,jsonb,text): 9 anchor(s)
  c_submit_anchors constant text[] := array[
    $a$  v_hold text; v_candidates uuid[];
begin
$a$,
    $a$  v_name  := nullif(trim(p_payload->>'full_name'), '');
$a$,
    $a$  v_src_details := nullif(trim(p_payload->>'source_details'), '');
$a$,
    $a$                and ((h.resolved_at is null and s.customer_id is null)
                     or (s.customer_id is not null and c.deleted_at is null))) then
$a$,
    $a$    if exists (select 1 from public.health_surveys where customer_id = v_cust_id)
       or exists (select 1 from public.health_surveys
$a$,
    $a$    insert into public.customers (full_name, phone, email, date_of_birth, gender, occupation,
                                  source_option_id, source_label, source_details, source_updated_at)
    values (v_name, coalesce(v_norm, v_phone), v_email,
$a$,
    $a$  v_no := 'HS-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);

  insert into public.health_surveys (
    survey_no, store_id, survey_link_id, customer_id, event_name,
    full_name, date_of_birth, age, sex, phone, email, occupation,
    has_medical_condition, drinks_alcohol, smokes, on_treatment, treatment_list, others_text,
    consent_newsletter_email, consent_marketing_email, consent_marketing_sms, consent_marketing_phone,
    signature_data, signed_date, ip_address, device_info,
    source_option_id, source_label, source_details)
  values (
    v_no, v_l.store_id, v_l.id, v_cust_id, coalesce(nullif(trim(p_payload->>'event_name'),''), v_l.event_name),
    v_name, nullif(p_payload->>'date_of_birth','')::date, nullif(p_payload->>'age','')::integer,
    v_sex, coalesce(v_norm, v_phone), v_email, nullif(trim(p_payload->>'occupation'),''),
    (p_payload->>'has_medical_condition')::boolean, (p_payload->>'drinks_alcohol')::boolean,
    (p_payload->>'smokes')::boolean, (p_payload->>'on_treatment')::boolean,
    nullif(trim(p_payload->>'treatment_list'),''), nullif(trim(p_payload->>'others_text'),''),
    coalesce((p_payload->>'consent_newsletter_email')::boolean, false),
    coalesce((p_payload->>'consent_marketing_email')::boolean, false),
    coalesce((p_payload->>'consent_marketing_sms')::boolean, false),
    coalesce((p_payload->>'consent_marketing_phone')::boolean, false),
    p_payload->>'signature_data',
    coalesce(nullif(p_payload->>'signed_date','')::date, public.sg_today()),
    nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''),
    v_src.id, v_src.label, v_src_details)
  returning id into v_id;

  if p_symptoms is not null then
    for v_sym in select * from jsonb_array_elements(p_symptoms) loop
      insert into public.health_survey_symptoms (survey_id, option_id, duration_text)
      values (v_id, (v_sym->>'option_id')::uuid, nullif(trim(v_sym->>'duration_text'),''))
      on conflict do nothing;
    end loop;
  end if;

  if p_pdf_base64 is not null and length(p_pdf_base64) > 0 then
    if length(p_pdf_base64) > 8000000 then raise exception 'The signed document is too large.'; end if;
    insert into public.health_survey_pdfs (survey_id, pdf_base64, byte_size)
    values (v_id, p_pdf_base64, length(p_pdf_base64));
    update public.health_surveys set pdf_url = 'stored' where id = v_id;
  end if;
$a$,
    $a$                             'name_match', v_name_match, 'typed_name', v_name),
$a$,
    $a$  return jsonb_build_object('success', true, 'survey_no', v_no, 'survey_id', v_id);
$a$];
  c_submit_patches constant text[] := array[
    $r$  v_hold text; v_candidates uuid[];
  -- 419: the name as typed in two parts; the consultant's record the form goes
  -- into (Q10), the form's answers as a survey row, and what that gave back.
  v_first text; v_last text; v_into uuid; v_form public.health_surveys%rowtype; v_signed jsonb;
begin
$r$,
    $r$  v_name  := nullif(trim(p_payload->>'full_name'), '');
  -- 419 (CUSTOMERS-8): the form sends the first and the last name as typed. A
  -- customer the form makes, and a form held for staff, keep them as typed;
  -- before, the whole name was split at its first space. A page loaded before
  -- 419 sends only the whole name, which is split as before.
  v_first := nullif(trim(p_payload->>'first_name'), '');
  v_last  := nullif(trim(p_payload->>'last_name'), '');
  if v_first is not null then
    v_name := public.join_person_name(v_first, v_last);
  else
    v_last := null;
  end if;
$r$,
    $r$  v_src_details := nullif(trim(p_payload->>'source_details'), '');
  -- 419 (CUSTOMERS-12): an event's link names how its customers heard about us
  -- (Event or RoadShow, chosen when the link was made). That source, with the
  -- event's name as the details, is recorded, whatever the page sent. Older
  -- links, and a link whose source was later switched off, keep the
  -- customer's own answer.
  if nullif(btrim(v_l.event_name), '') is not null and v_l.source_option_id is not null
     and exists (select 1 from public.customer_source_options o where o.id = v_l.source_option_id and o.is_active) then
    v_src_id := v_l.source_option_id;
    v_src_details := btrim(v_l.event_name);
  end if;
$r$,
    $r$                and ((h.resolved_at is null and s.customer_id is null)
                     or (s.customer_id is not null and c.deleted_at is null)
                     -- 419: or staff attached it and its answers went into the
                     -- record of a customer in use (Q10).
                     or (h.resolution = 'attached' and s.customer_id is null
                         and exists (select 1 from public.customers x
                                      where x.id = h.resolved_customer_id and x.deleted_at is null)))) then
$r$,
    $r$    -- 419 (Q10, the Owner, 9 Oct 2026): a consultant's record the customer has
    -- not signed takes the form (health_survey_sign_into_record, below). Any
    -- other survey of theirs is their one survey, as before.
    select hs.id into v_into from public.health_surveys hs
     where hs.customer_id = v_cust_id and hs.source = 'consultant' and hs.signature_data is null;
    if exists (select 1 from public.health_surveys where customer_id = v_cust_id and id is distinct from v_into)
       or exists (select 1 from public.health_surveys
$r$,
    $r$    insert into public.customers (full_name, first_name, last_name, phone, email, date_of_birth, gender, occupation,
                                  source_option_id, source_label, source_details, source_updated_at)
    values (v_name, v_first, v_last, coalesce(v_norm, v_phone), v_email,
$r$,
    $r$  if v_into is not null then
    -- 419 (Q10): the customer's own answers go into the consultant's record
    -- they had not signed; the consultant's work stays.
    v_form.survey_link_id := v_l.id;
    v_form.store_id := v_l.store_id;
    v_form.event_name := coalesce(nullif(trim(p_payload->>'event_name'),''), v_l.event_name);
    v_form.date_of_birth := nullif(p_payload->>'date_of_birth','')::date;
    v_form.age := nullif(p_payload->>'age','')::integer;
    v_form.sex := v_sex;
    v_form.phone := coalesce(v_norm, v_phone);
    v_form.email := v_email;
    v_form.occupation := nullif(trim(p_payload->>'occupation'),'');
    v_form.has_medical_condition := (p_payload->>'has_medical_condition')::boolean;
    v_form.drinks_alcohol := (p_payload->>'drinks_alcohol')::boolean;
    v_form.smokes := (p_payload->>'smokes')::boolean;
    v_form.on_treatment := (p_payload->>'on_treatment')::boolean;
    v_form.treatment_list := nullif(trim(p_payload->>'treatment_list'),'');
    v_form.others_text := nullif(trim(p_payload->>'others_text'),'');
    v_form.consent_newsletter_email := coalesce((p_payload->>'consent_newsletter_email')::boolean, false);
    v_form.consent_marketing_email := coalesce((p_payload->>'consent_marketing_email')::boolean, false);
    v_form.consent_marketing_sms := coalesce((p_payload->>'consent_marketing_sms')::boolean, false);
    v_form.consent_marketing_phone := coalesce((p_payload->>'consent_marketing_phone')::boolean, false);
    v_form.signature_data := p_payload->>'signature_data';
    v_form.signed_date := coalesce(nullif(p_payload->>'signed_date','')::date, public.sg_today());
    v_form.ip_address := nullif(p_payload->>'ip_address','');
    v_form.device_info := nullif(p_payload->>'device_info','');
    v_form.source_option_id := v_src.id;
    v_form.source_label := v_src.label;
    v_form.source_details := v_src_details;
    v_form.submitted_at := now();
    v_signed := public.health_survey_sign_into_record(v_into, v_form, p_symptoms, p_pdf_base64);
    v_id := v_into;
    v_no := v_signed->>'survey_no';
  else
    v_no := 'HS-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);

    -- 419 (CUSTOMERS-8): a form with a customer of its own (made just now) or
    -- none yet (held for staff) keeps the name parts as typed; a form for a
    -- customer found takes theirs (trg_survey_inherit_customer), as before.
    insert into public.health_surveys (
      survey_no, store_id, survey_link_id, customer_id, event_name,
      full_name, first_name, last_name, date_of_birth, age, sex, phone, email, occupation,
      has_medical_condition, drinks_alcohol, smokes, on_treatment, treatment_list, others_text,
      consent_newsletter_email, consent_marketing_email, consent_marketing_sms, consent_marketing_phone,
      signature_data, signed_date, ip_address, device_info,
      source_option_id, source_label, source_details)
    values (
      v_no, v_l.store_id, v_l.id, v_cust_id, coalesce(nullif(trim(p_payload->>'event_name'),''), v_l.event_name),
      v_name, case when v_created or v_cust_id is null then v_first end,
      case when v_created or v_cust_id is null then v_last end,
      nullif(p_payload->>'date_of_birth','')::date, nullif(p_payload->>'age','')::integer,
      v_sex, coalesce(v_norm, v_phone), v_email, nullif(trim(p_payload->>'occupation'),''),
      (p_payload->>'has_medical_condition')::boolean, (p_payload->>'drinks_alcohol')::boolean,
      (p_payload->>'smokes')::boolean, (p_payload->>'on_treatment')::boolean,
      nullif(trim(p_payload->>'treatment_list'),''), nullif(trim(p_payload->>'others_text'),''),
      coalesce((p_payload->>'consent_newsletter_email')::boolean, false),
      coalesce((p_payload->>'consent_marketing_email')::boolean, false),
      coalesce((p_payload->>'consent_marketing_sms')::boolean, false),
      coalesce((p_payload->>'consent_marketing_phone')::boolean, false),
      p_payload->>'signature_data',
      coalesce(nullif(p_payload->>'signed_date','')::date, public.sg_today()),
      nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''),
      v_src.id, v_src.label, v_src_details)
    returning id into v_id;

    if p_symptoms is not null then
      for v_sym in select * from jsonb_array_elements(p_symptoms) loop
        insert into public.health_survey_symptoms (survey_id, option_id, duration_text)
        values (v_id, (v_sym->>'option_id')::uuid, nullif(trim(v_sym->>'duration_text'),''))
        on conflict do nothing;
      end loop;
    end if;

    if p_pdf_base64 is not null and length(p_pdf_base64) > 0 then
      if length(p_pdf_base64) > 8000000 then raise exception 'The signed document is too large.'; end if;
      insert into public.health_survey_pdfs (survey_id, pdf_base64, byte_size)
      values (v_id, p_pdf_base64, length(p_pdf_base64));
      update public.health_surveys set pdf_url = 'stored' where id = v_id;
    end if;
  end if;
$r$,
    $r$                             'name_match', v_name_match, 'typed_name', v_name,
                             -- 419: into a consultant's record (Q10), and
                             -- whether that record was empty.
                             'signed_into_record', v_into is not null,
                             'record_was_empty', (v_signed->>'record_was_empty')::boolean),
$r$,
    $r$  -- 419 (CUSTOMERS-16): the page could not build the signed PDF (it says why
  -- in pdf_error), so none is stored; staff see this row in the Audit Log.
  if p_pdf_base64 is null or length(p_pdf_base64) = 0 then
    insert into public.audit_logs (table_name, record_id, action, new_data, module, store_id, ip_address, device_info)
    values ('health_surveys', v_id, 'signed_pdf_missing',
            jsonb_build_object('survey_no', v_no, 'reason', left(nullif(trim(p_payload->>'pdf_error'), ''), 200)),
            'health_survey', v_l.store_id,
            nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''));
  end if;

  return jsonb_build_object('success', true, 'survey_no', v_no, 'survey_id', v_id);
$r$];
  -- attach_held_health_survey(uuid,uuid,text): 5 anchor(s)
  c_attach_anchors constant text[] := array[
    $a$        v_gender public.customer_gender; v_existing text;
$a$,
    $a$  select x.survey_no into v_existing from public.health_surveys x where x.customer_id = v_c.id;
  if v_existing is not null then
$a$,
    $a$  update public.health_surveys set
    customer_id = v_c.id,
    first_name  = case when nullif(trim(coalesce(v_c.full_name, '')), '') is not null then v_c.first_name else first_name end,
    last_name   = case when nullif(trim(coalesce(v_c.full_name, '')), '') is not null then v_c.last_name else last_name end,
    full_name   = coalesce(nullif(trim(coalesce(v_c.full_name, '')), ''), full_name)
   where id = v_s.id;
$a$,
    $a$                       'suggested_customer', v_c.id = any (v_h.candidate_customer_ids)),
$a$,
    $a$  return jsonb_build_object('ok', true, 'customer_id', v_c.id, 'survey_no', v_s.survey_no);
$a$];
  c_attach_patches constant text[] := array[
    $r$        v_gender public.customer_gender; v_existing text;
        -- 419: the customer's unsigned consultant record that takes the form (Q10).
        v_into uuid; v_syms jsonb; v_pdf text; v_signed jsonb;
$r$,
    $r$  -- 419 (Q10, the Owner, 9 Oct 2026): a consultant's record the customer has
  -- not signed takes the form's answers (health_survey_sign_into_record). Any
  -- other survey is their one survey, as before.
  select x.survey_no, case when x.source = 'consultant' and x.signature_data is null then x.id end
    into v_existing, v_into
    from public.health_surveys x where x.customer_id = v_c.id;
  if v_existing is not null and v_into is null then
$r$,
    $r$  if v_into is not null then
    -- 419 (Q10): the form's answers, symptoms and signed PDF go into the
    -- customer's record. The form itself is kept as it was sent, with no
    -- customer; its hold below says it was attached, and to whom.
    select coalesce(jsonb_agg(jsonb_build_object('option_id', y.option_id, 'duration_text', y.duration_text)), '[]'::jsonb)
      into v_syms
      from public.health_survey_symptoms y where y.survey_id = v_s.id;
    select p.pdf_base64 into v_pdf from public.health_survey_pdfs p where p.survey_id = v_s.id;
    v_signed := public.health_survey_sign_into_record(v_into, v_s, v_syms, v_pdf);
  else
    update public.health_surveys set
      customer_id = v_c.id,
      first_name  = case when nullif(trim(coalesce(v_c.full_name, '')), '') is not null then v_c.first_name else first_name end,
      last_name   = case when nullif(trim(coalesce(v_c.full_name, '')), '') is not null then v_c.last_name else last_name end,
      full_name   = coalesce(nullif(trim(coalesce(v_c.full_name, '')), ''), full_name)
     where id = v_s.id;
  end if;
$r$,
    $r$                       'suggested_customer', v_c.id = any (v_h.candidate_customer_ids),
                       -- 419: the record its answers went into (Q10).
                       'signed_into_survey_no', v_signed->>'survey_no'),
$r$,
    $r$  return jsonb_build_object('ok', true, 'customer_id', v_c.id, 'survey_no', v_s.survey_no,
                            'signed_into_survey_no', v_signed->>'survey_no');
$r$];
  -- health_survey_holds_list(): 1 anchor(s)
  c_list_anchors constant text[] := array[
    $a$                 'survey_no', (select x.survey_no from public.health_surveys x where x.customer_id = c.id))
$a$];
  c_list_patches constant text[] := array[
    $r$                 'survey_no', (select x.survey_no from public.health_surveys x where x.customer_id = c.id),
                 -- 419 (Q10): that survey is a consultant's record they have
                 -- not signed, so it can take this form's answers.
                 'survey_takes_form', (select x.source = 'consultant' and x.signature_data is null
                                         from public.health_surveys x where x.customer_id = c.id))
$r$];
  -- create_customer_from_held_survey(uuid,text): 1 anchor(s)
  c_create_anchors constant text[] := array[
    $a$  insert into public.customers (full_name, phone, email, date_of_birth, gender, occupation,
                                source_option_id, source_label, source_details, source_updated_at)
  values (v_s.full_name, v_s.phone, nullif(btrim(v_s.email), ''), v_s.date_of_birth, v_gender,
$a$];
  c_create_patches constant text[] := array[
    $r$  -- 419 (CUSTOMERS-8): with the form's name parts, as typed.
  insert into public.customers (full_name, first_name, last_name, phone, email, date_of_birth, gender, occupation,
                                source_option_id, source_label, source_details, source_updated_at)
  values (v_s.full_name, v_s.first_name, v_s.last_name, v_s.phone, nullif(btrim(v_s.email), ''), v_s.date_of_birth, v_gender,
$r$];
  -- diagnose_survey_name_edit(text): 2 anchor(s)
  c_diag_anchors constant text[] := array[
    $a$     where n.nspname = 'public' and p.proname = 'update_survey_particulars'
  loop
    step := '1. FUNCTION VERSIONS';
    detail := case when r.sig like '%p_has_medical_condition%'
                   then 'FULL version'
$a$,
    $a$    perform public.update_survey_particulars(
      v_id, 'DIAGTEST', 'NAMECHECK',
      (select phone from public.health_surveys where id = v_id),
      (select email from public.health_surveys where id = v_id),
      (select date_of_birth from public.health_surveys where id = v_id),
      (select sex from public.health_surveys where id = v_id),
      (select occupation from public.health_surveys where id = v_id),
      null);
$a$];
  c_diag_patches constant text[] := array[
    $r$     where n.nspname = 'public' and p.proname in ('update_survey_particulars', 'update_survey_particulars_v2')
  loop
    step := '1. FUNCTION VERSIONS';
    detail := case when r.sig like '%p_changes%'
                   then '419 version (only the fields changed)'
                   when r.sig like '%p_has_medical_condition%'
                   then 'FULL version'
$r$,
    $r$    -- 419: Edit details is update_survey_particulars_v2, which takes only the
    -- fields changed.
    perform public.update_survey_particulars_v2(
      v_id, jsonb_build_object('first_name', 'DIAGTEST', 'last_name', 'NAMECHECK'), null);
$r$];
  -- customer_survey_overview(text,text,integer,integer) (418's): 1 anchor(s)
  c_overview_anchors constant text[] := array[
    $a$  select public.require_active_staff();  -- 406: active staff only
$a$];
  c_overview_patches constant text[] := array[
    $r$  select public.require_active_staff('{owner,admin,manager,staff}');  -- 406: active staff only; 419: not Inventory Managers (health data)
$r$];
  -- report_customer_sources(date,date): 1 anchor(s)
  c_sources_anchors constant text[] := array[
    $a$             and (p_to is null or (s.submitted_at at time zone 'Asia/Singapore')::date <= p_to))
$a$];
  c_sources_patches constant text[] := array[
    $r$             and (p_to is null or (s.submitted_at at time zone 'Asia/Singapore')::date <= p_to)
             -- 419 (Q10): a held form that staff put into a customer's record
             -- is counted once, by that record. The form kept as sent (no
             -- customer, its hold attached) is not counted again.
             and not (s.customer_id is null
                      and exists (select 1 from public.health_survey_holds h
                                   where h.survey_id = s.id and h.resolution = 'attached')))
$r$];
  -- The functions this relies on and does not change (md5 of
  -- pg_get_functiondef, search_path public): production on 18 Oct 2026 and
  -- 418's assert_customer_dob_change. The nine built migrations (417, 418,
  -- 420, 422, 423, 424, 427, 429, 431) change none of them but that one.
  c_relied constant text[][] := array[
    ['assert_customer_dob_change(uuid,date,text)',                      '3d9fc369da08a6baf623f842999f0156'],
    ['require_active_staff(text[])',                                    '877b3aa74cea559881979bb161c450e2'],
    ['current_user_role()',                                             '519b0a33a3548f970c5d585b6e76a389'],
    ['is_manager_or_above()',                                           'f12b9ed342070fa4defa30e4da2ba655'],
    ['user_has_store_access(uuid)',                                     '8c82c6bcb64f496c5a05a2b8dafa95f8'],
    ['write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'],
    ['join_person_name(text,text)',                                     '50b6cd36ab0fd14be3acd549fec5edb8'],
    ['normalize_customer_phone(text)',                                  'b2bfac910e0c9eff402ba44e19750bee'],
    ['sg_today()',                                                      '1c1289f18e24d8370e9a6364c9c06fca'],
    ['trg_health_survey_guard()',                                       '68234ede2f09e5908490eec1eb501b1a'],
    ['trg_survey_inherit_customer()',                                   '5b145a044ea35d3a2237f0ff4e65b600'],
    ['trg_sync_customer_to_surveys()',                                  'a316d1e7d053de7e24ed45f19a652f0f'],
    ['trg_sync_person_name()',                                          'bdfc01a20c6d82672a24c694a0ea917b'],
    ['trg_sync_survey_age()',                                           'a59e49b9fc129c502adb24e6565fe3f6'],
    ['audit_customer_phone_change()',                                   '414b5857bccb5b06d7ef3278dc754617'],
    ['customer_centre_visit_days()',                                    '2129857d6ff9f29dcf2cbccc9f13e5bc'],
    ['is_owner_or_manager()',                                           '125dec10ce33b84ff5fb40a9bd455235'],
    ['customer_phone_name_matches(text,text)',                          '1bdf8322972b6671b7cbb08bc8211f8a'],
    ['customer_names_match(text,text)',                                 'ef1af52e4888cefb6037a2291f4e011d'],
    ['customer_email_match_key(text)',                                  'be468815c9626fff1728e2cfcd484b66'],
    ['normalize_customer_match_name(text)',                             '0572764712e179dc606c66f9f3dbaa03'],
    ['require_resolved_customer_identity(text,text)',                   '5bde1a418363442ec27e2944442f5874']];
  -- The read rules, before (production, 18 Oct 2026) and after.
  c_rule_before constant text := '(current_user_role() IS NOT NULL)';
  c_rule_after constant text := '( SELECT can_view_health_data() AS can_view_health_data)';
  c_pdf_rule_before constant text := $q$(EXISTS ( SELECT 1
   FROM health_surveys s
  WHERE ((s.id = health_survey_pdfs.survey_id) AND (is_manager_or_above() OR user_has_store_access(s.store_id)))))$q$;
  c_pdf_rule_after constant text := $q$(( SELECT can_view_health_data() AS can_view_health_data) AND (EXISTS ( SELECT 1
   FROM health_surveys s
  WHERE ((s.id = health_survey_pdfs.survey_id) AND (( SELECT is_manager_or_above() AS is_manager_or_above) OR user_has_store_access(s.store_id))))))$q$;
  c_rules constant text[][] := array[
    ['health_surveys', 'read surveys'], ['health_survey_symptoms', 'read survey symptoms'],
    ['consultant_notes', 'read consultant notes'], ['customer_remarks', 'read customer remarks']];
  c_sex_before constant text := $q$CHECK ((sex = ANY (ARRAY['male'::text, 'female'::text])))$q$;
  c_sex_after constant text := $q$CHECK ((sex = ANY (ARRAY['male'::text, 'female'::text, 'other'::text])))$q$;
  -- The survey files' bucket (CUSTOMERS-M1): 10 MB, and the types the page
  -- offers (photos and scans, PDF, Word, Excel, CSV, text).
  c_mimes constant text[] := array['image/*', 'application/pdf', 'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'text/csv', 'text/plain'];
  c_old_particulars constant text :=
    'update_survey_particulars(uuid,text,text,text,text,date,text,text,text,uuid,text,boolean,boolean,boolean,boolean,text,jsonb)';
  c_old_particulars_md5 constant text := 'a8ab6926b33045dfc8c714d3840fe0a3';
  c_old_review constant text := 'review_health_survey(uuid,text,text,text,text)';
  c_old_review_md5 constant text := '55a53371798b5c145d7f14cf6ba5d479';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; d text; n int; k int; v text; v_md5 text; v_acl text;
  v_install text[] := '{}'; v_defs text[] := '{}'; v_acls text[] := '{}';
  v_patch_sql text[] := '{}';
  v_add_column boolean := false; v_widen_sex boolean := false; v_drop_particulars boolean := false;
  v_drop_review boolean := false; v_rules boolean := false; v_bucket boolean := false;
  -- the behaviour check
  v_owner uuid; v_staff uuid; v_invman uuid; v_store uuid; v_cust uuid; v_src uuid; v_link uuid;
  v_survey uuid; v_out jsonb; v_seen int; v_token text;
  v_patch_fns text[] := '{}'; v_patch_acls text[] := '{}';
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 18 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is installed unless all pass ─────────────────────
  for k in 1 .. array_length(c_relied, 1) loop
    if to_regprocedure('public.' || c_relied[k][1]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[k][1]))) <> c_relied[k][2] then
      raise exception '419: public.% is missing or not the version this was tested against (418 must be applied first). Re-read it from production and re-test before applying.', c_relied[k][1];
    end if;
  end loop;

  -- The columns read and written, the one survey per customer index, 433's
  -- table of held forms, and the survey links.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.health_surveys'::regclass and a.attnum > 0 and not a.attisdropped;
  if v is distinct from 'acidity_result text|age integer|consent_marketing_email boolean|consent_marketing_phone boolean|consent_marketing_sms boolean|consent_newsletter_email boolean|created_by uuid|customer_id uuid|date_of_birth date|device_info text|drinks_alcohol boolean|email text|event_name text|first_name text|full_name text|has_medical_condition boolean|health_goals text|id uuid|ip_address text|last_name text|occupation text|on_treatment boolean|others_text text|pdf_url text|phone text|remarks_condition text|remarks_recommendation text|reviewed_at timestamp with time zone|reviewed_by uuid|sex text|signature_data text|signed_date date|smokes boolean|source text|source_details text|source_label text|source_option_id uuid|store_id uuid|submitted_at timestamp with time zone|survey_link_id uuid|survey_no text|treatment_list text' then
    raise exception '419: public.health_surveys is not shaped as read on 18 Oct 2026 (%)', v; end if;
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'health_surveys' and indexname = 'uq_health_survey_customer'
                    and indexdef = 'CREATE UNIQUE INDEX uq_health_survey_customer ON public.health_surveys USING btree (customer_id) WHERE (customer_id IS NOT NULL)') then
    raise exception '419: the index uq_health_survey_customer (one survey per customer) is missing or not as read on 18 Oct 2026'; end if;
  if to_regclass('public.health_survey_holds') is null then
    raise exception '419: public.health_survey_holds is missing (433 must be applied first)'; end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.health_survey_pdfs'::regclass and contype = 'p'
                    and pg_get_constraintdef(oid) = 'PRIMARY KEY (survey_id)') then
    raise exception '419: public.health_survey_pdfs is not keyed by survey as read on 18 Oct 2026'; end if;
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.survey_links'::regclass and a.attnum > 0 and not a.attisdropped;
  if v = 'created_at timestamp with time zone|created_by uuid|event_name text|expires_at timestamp with time zone|id uuid|is_active boolean|store_id uuid|token text' then
    v_add_column := true;
  elsif v = 'created_at timestamp with time zone|created_by uuid|event_name text|expires_at timestamp with time zone|id uuid|is_active boolean|source_option_id uuid|store_id uuid|token text' then
    raise notice '419: survey_links.source_option_id is already there; left alone';
  else
    raise exception '419: public.survey_links is not shaped as read on 18 Oct 2026 (%)', v; end if;

  -- Sex on a survey: female or male, or already Other too.
  select pg_get_constraintdef(c.oid) into v from pg_constraint c
   where c.conrelid = 'public.health_surveys'::regclass and c.conname = 'health_surveys_sex_check';
  if v = c_sex_before then v_widen_sex := true;
  elsif v is distinct from c_sex_after then
    raise exception '419: health_surveys_sex_check is not as read on 18 Oct 2026 (%)', v; end if;

  -- The five read rules: as read, or already this migration's.
  for k in 1 .. array_length(c_rules, 1) loop
    select pg_get_expr(p.polqual, p.polrelid) into v from pg_policy p
     where p.polrelid = ('public.' || c_rules[k][1])::regclass and p.polname = c_rules[k][2]
       and p.polcmd = 'r' and p.polroles = array['authenticated'::regrole]::oid[];
    if v = c_rule_before then v_rules := true;
    elsif v is distinct from c_rule_after then
      raise exception '419: the rule "%" on % is not as read on 18 Oct 2026 (%)', c_rules[k][2], c_rules[k][1], v; end if;
  end loop;
  select pg_get_expr(p.polqual, p.polrelid) into v from pg_policy p
   where p.polrelid = 'public.health_survey_pdfs'::regclass and p.polname = 'read survey pdfs'
     and p.polcmd = 'r' and p.polroles = array['authenticated'::regrole]::oid[];
  if v = c_pdf_rule_before then v_rules := true;
  elsif v is distinct from c_pdf_rule_after then
    raise exception '419: the rule "read survey pdfs" is not as read on 18 Oct 2026 (%)', v; end if;

  -- The survey files' bucket: no limits yet, or already these.
  select case when b.file_size_limit is null and b.allowed_mime_types is null then 'before'
              when b.file_size_limit = 10485760 and b.allowed_mime_types = c_mimes then 'after' end
    into v from storage.buckets b where b.id = 'survey-attachments';
  if v = 'before' then v_bucket := true;
  elsif v is distinct from 'after' then
    raise exception '419: the survey-attachments bucket is missing or not as read on 18 Oct 2026'; end if;

  -- Each function: missing (new), BEFORE (installed) or AFTER (left alone).
  -- The text built must be the tested one.
  for r in select * from (values
      ('can_view_health_data()', c_can_view_health_data_def, null::text, '5cccb54dd99d2c3d77548cd8242ea126'),
      ('health_survey_sign_into_record(uuid,health_surveys,jsonb,text)', c_health_survey_sign_into_record_def, null::text, 'ac2bbd3742f3b4364b289ddd29715215'),
      ('update_survey_particulars_v2(uuid,jsonb,text)', c_update_survey_particulars_v2_def, null::text, '45ebc42b54405810b104d4c0c292dcf5'),
      ('upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)', c_upsert_consultant_survey_def, 'd653a0edddef3023b7dac7b0f97e0964', 'e5e6922d5fbe16ee81d44246cabd9d60'),
      ('survey_link_info(text)', c_survey_link_info_def, '42224d4abc8e020c1beeef4758d209a4', '626e3bdd4d29e7508a8520fbae11b826'),
      ('add_survey_attachment(uuid,text,text,text,integer,text)', c_add_survey_attachment_def, '8696f2795f7209baca8df5d5a23f96de', 'a856b3463d4e9c8784e2cf1e6d2b649b'),
      ('health_survey_detail(uuid)', c_health_survey_detail_def, 'e04b50ad8507d77e9436e2a2a84766d1', '2aa7515661ea56171be26657a3ea7af5'),
      ('review_health_survey(uuid,text,text,text,text,boolean)', c_review_health_survey_def, null::text, '46bddd90d9badfae99cff53379275e64')) as x(fn, def, before_md5, after_md5)
  loop
    if md5(r.def) <> r.after_md5 then
      raise exception '419: the text of public.% is not the tested one (md5 %)', r.fn, md5(r.def); end if;
    if to_regprocedure('public.' || r.fn) is null then
      if r.before_md5 is not null then raise exception '419: public.% is missing', r.fn; end if;
      v_install := v_install || r.fn; v_defs := v_defs || r.def; v_acls := v_acls || ''::text;
    else
      v_md5 := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
      if v_md5 = r.after_md5 then
        raise notice '419: public.% is already this version; left alone', r.fn;
      elsif v_md5 is distinct from r.before_md5 then
        raise exception '419: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v_md5;
      else
        select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = to_regprocedure('public.' || r.fn);
        v_install := v_install || r.fn; v_defs := v_defs || r.def; v_acls := v_acls || v_acl;
      end if;
    end if;
  end loop;

  -- submit_health_survey(text,jsonb,jsonb,text): BEFORE (patched) or AFTER (left alone).
  if to_regprocedure('public.submit_health_survey(text,jsonb,jsonb,text)') is null then
    raise exception '419: public.submit_health_survey(text,jsonb,jsonb,text) is missing'; end if;
  d := pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure);
  if md5(d) = 'ad2a66909b663026911dff137ab12185' then
    raise notice '419: public.submit_health_survey(text,jsonb,jsonb,text) is already this version; left alone';
  elsif md5(d) <> '5a3f27a0b9a0bed619ac0c82c8c52aab' then
    raise exception '419: public.submit_health_survey(text,jsonb,jsonb,text) is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', md5(d);
  else
    for k in 1 .. cardinality(c_submit_anchors) loop
      n := (length(d) - length(replace(d, c_submit_anchors[k], ''))) / length(c_submit_anchors[k]);
      if n <> 1 then
        raise exception '419: anchor % of public.submit_health_survey(text,jsonb,jsonb,text) was found % times, not once', k, n; end if;
      d := replace(d, c_submit_anchors[k], c_submit_patches[k]);
    end loop;
    if md5(d) <> 'ad2a66909b663026911dff137ab12185' then
      raise exception '419: the text built for public.submit_health_survey(text,jsonb,jsonb,text) is not the tested one (md5 %)', md5(d); end if;
    select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = 'public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure;
    v_patch_fns := v_patch_fns || 'submit_health_survey(text,jsonb,jsonb,text)'::text; v_patch_sql := v_patch_sql || d; v_patch_acls := v_patch_acls || v_acl;
  end if;

  -- attach_held_health_survey(uuid,uuid,text): BEFORE (patched) or AFTER (left alone).
  if to_regprocedure('public.attach_held_health_survey(uuid,uuid,text)') is null then
    raise exception '419: public.attach_held_health_survey(uuid,uuid,text) is missing'; end if;
  d := pg_get_functiondef('public.attach_held_health_survey(uuid,uuid,text)'::regprocedure);
  if md5(d) = '53aabcdd564da445131633c41bef8249' then
    raise notice '419: public.attach_held_health_survey(uuid,uuid,text) is already this version; left alone';
  elsif md5(d) <> '104370324b701192ba9710d515cc388f' then
    raise exception '419: public.attach_held_health_survey(uuid,uuid,text) is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', md5(d);
  else
    for k in 1 .. cardinality(c_attach_anchors) loop
      n := (length(d) - length(replace(d, c_attach_anchors[k], ''))) / length(c_attach_anchors[k]);
      if n <> 1 then
        raise exception '419: anchor % of public.attach_held_health_survey(uuid,uuid,text) was found % times, not once', k, n; end if;
      d := replace(d, c_attach_anchors[k], c_attach_patches[k]);
    end loop;
    if md5(d) <> '53aabcdd564da445131633c41bef8249' then
      raise exception '419: the text built for public.attach_held_health_survey(uuid,uuid,text) is not the tested one (md5 %)', md5(d); end if;
    select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = 'public.attach_held_health_survey(uuid,uuid,text)'::regprocedure;
    v_patch_fns := v_patch_fns || 'attach_held_health_survey(uuid,uuid,text)'::text; v_patch_sql := v_patch_sql || d; v_patch_acls := v_patch_acls || v_acl;
  end if;

  -- health_survey_holds_list(): BEFORE (patched) or AFTER (left alone).
  if to_regprocedure('public.health_survey_holds_list()') is null then
    raise exception '419: public.health_survey_holds_list() is missing'; end if;
  d := pg_get_functiondef('public.health_survey_holds_list()'::regprocedure);
  if md5(d) = '0487502f033b56452140c81e108a8ebc' then
    raise notice '419: public.health_survey_holds_list() is already this version; left alone';
  elsif md5(d) <> 'c3f50d90ba0509935681e4446bcbb21b' then
    raise exception '419: public.health_survey_holds_list() is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', md5(d);
  else
    for k in 1 .. cardinality(c_list_anchors) loop
      n := (length(d) - length(replace(d, c_list_anchors[k], ''))) / length(c_list_anchors[k]);
      if n <> 1 then
        raise exception '419: anchor % of public.health_survey_holds_list() was found % times, not once', k, n; end if;
      d := replace(d, c_list_anchors[k], c_list_patches[k]);
    end loop;
    if md5(d) <> '0487502f033b56452140c81e108a8ebc' then
      raise exception '419: the text built for public.health_survey_holds_list() is not the tested one (md5 %)', md5(d); end if;
    select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = 'public.health_survey_holds_list()'::regprocedure;
    v_patch_fns := v_patch_fns || 'health_survey_holds_list()'::text; v_patch_sql := v_patch_sql || d; v_patch_acls := v_patch_acls || v_acl;
  end if;

  -- create_customer_from_held_survey(uuid,text): BEFORE (patched) or AFTER (left alone).
  if to_regprocedure('public.create_customer_from_held_survey(uuid,text)') is null then
    raise exception '419: public.create_customer_from_held_survey(uuid,text) is missing'; end if;
  d := pg_get_functiondef('public.create_customer_from_held_survey(uuid,text)'::regprocedure);
  if md5(d) = '733db65d708db7c64b5c4de03493d409' then
    raise notice '419: public.create_customer_from_held_survey(uuid,text) is already this version; left alone';
  elsif md5(d) <> 'd503d8b599f90768c8d909b91cd453e1' then
    raise exception '419: public.create_customer_from_held_survey(uuid,text) is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', md5(d);
  else
    for k in 1 .. cardinality(c_create_anchors) loop
      n := (length(d) - length(replace(d, c_create_anchors[k], ''))) / length(c_create_anchors[k]);
      if n <> 1 then
        raise exception '419: anchor % of public.create_customer_from_held_survey(uuid,text) was found % times, not once', k, n; end if;
      d := replace(d, c_create_anchors[k], c_create_patches[k]);
    end loop;
    if md5(d) <> '733db65d708db7c64b5c4de03493d409' then
      raise exception '419: the text built for public.create_customer_from_held_survey(uuid,text) is not the tested one (md5 %)', md5(d); end if;
    select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = 'public.create_customer_from_held_survey(uuid,text)'::regprocedure;
    v_patch_fns := v_patch_fns || 'create_customer_from_held_survey(uuid,text)'::text; v_patch_sql := v_patch_sql || d; v_patch_acls := v_patch_acls || v_acl;
  end if;

  -- diagnose_survey_name_edit(text): BEFORE (patched) or AFTER (left alone).
  if to_regprocedure('public.diagnose_survey_name_edit(text)') is null then
    raise exception '419: public.diagnose_survey_name_edit(text) is missing'; end if;
  d := pg_get_functiondef('public.diagnose_survey_name_edit(text)'::regprocedure);
  if md5(d) = '06b97410274c13feec87ab83621877c1' then
    raise notice '419: public.diagnose_survey_name_edit(text) is already this version; left alone';
  elsif md5(d) <> '61dbfdce22e0db89b3cc527bf8d62e25' then
    raise exception '419: public.diagnose_survey_name_edit(text) is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', md5(d);
  else
    for k in 1 .. cardinality(c_diag_anchors) loop
      n := (length(d) - length(replace(d, c_diag_anchors[k], ''))) / length(c_diag_anchors[k]);
      if n <> 1 then
        raise exception '419: anchor % of public.diagnose_survey_name_edit(text) was found % times, not once', k, n; end if;
      d := replace(d, c_diag_anchors[k], c_diag_patches[k]);
    end loop;
    if md5(d) <> '06b97410274c13feec87ab83621877c1' then
      raise exception '419: the text built for public.diagnose_survey_name_edit(text) is not the tested one (md5 %)', md5(d); end if;
    select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = 'public.diagnose_survey_name_edit(text)'::regprocedure;
    v_patch_fns := v_patch_fns || 'diagnose_survey_name_edit(text)'::text; v_patch_sql := v_patch_sql || d; v_patch_acls := v_patch_acls || v_acl;
  end if;

  -- customer_survey_overview(text,text,integer,integer): BEFORE (418's AFTER; patched) or AFTER (left alone).
  if to_regprocedure('public.customer_survey_overview(text,text,integer,integer)') is null then
    raise exception '419: public.customer_survey_overview(text,text,integer,integer) is missing'; end if;
  d := pg_get_functiondef('public.customer_survey_overview(text,text,integer,integer)'::regprocedure);
  if md5(d) = 'd0301231179b3d05107e3309264692ff' then
    raise notice '419: public.customer_survey_overview(text,text,integer,integer) is already this version; left alone';
  elsif md5(d) <> '35ca42db5c30258f0c4d0026334fed2c' then
    raise exception '419: public.customer_survey_overview(text,text,integer,integer) is not the version this was tested against (md5 %). 418 must be applied first; re-read it and re-test before applying.', md5(d);
  else
    for k in 1 .. cardinality(c_overview_anchors) loop
      n := (length(d) - length(replace(d, c_overview_anchors[k], ''))) / length(c_overview_anchors[k]);
      if n <> 1 then
        raise exception '419: anchor % of public.customer_survey_overview(text,text,integer,integer) was found % times, not once', k, n; end if;
      d := replace(d, c_overview_anchors[k], c_overview_patches[k]);
    end loop;
    if md5(d) <> 'd0301231179b3d05107e3309264692ff' then
      raise exception '419: the text built for public.customer_survey_overview(text,text,integer,integer) is not the tested one (md5 %)', md5(d); end if;
    select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = 'public.customer_survey_overview(text,text,integer,integer)'::regprocedure;
    v_patch_fns := v_patch_fns || 'customer_survey_overview(text,text,integer,integer)'::text; v_patch_sql := v_patch_sql || d; v_patch_acls := v_patch_acls || v_acl;
  end if;

  -- report_customer_sources(date,date): BEFORE (patched) or AFTER (left alone).
  if to_regprocedure('public.report_customer_sources(date,date)') is null then
    raise exception '419: public.report_customer_sources(date,date) is missing'; end if;
  d := pg_get_functiondef('public.report_customer_sources(date,date)'::regprocedure);
  if md5(d) = '285e5b21754cf3fecababe3058a8bf58' then
    raise notice '419: public.report_customer_sources(date,date) is already this version; left alone';
  elsif md5(d) <> 'de5b160f34a49ff254c8f93cdc0f5106' then
    raise exception '419: public.report_customer_sources(date,date) is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', md5(d);
  else
    for k in 1 .. cardinality(c_sources_anchors) loop
      n := (length(d) - length(replace(d, c_sources_anchors[k], ''))) / length(c_sources_anchors[k]);
      if n <> 1 then
        raise exception '419: anchor % of public.report_customer_sources(date,date) was found % times, not once', k, n; end if;
      d := replace(d, c_sources_anchors[k], c_sources_patches[k]);
    end loop;
    if md5(d) <> '285e5b21754cf3fecababe3058a8bf58' then
      raise exception '419: the text built for public.report_customer_sources(date,date) is not the tested one (md5 %)', md5(d); end if;
    select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = 'public.report_customer_sources(date,date)'::regprocedure;
    v_patch_fns := v_patch_fns || 'report_customer_sources(date,date)'::text; v_patch_sql := v_patch_sql || d; v_patch_acls := v_patch_acls || v_acl;
  end if;
  -- The two functions replaced by a new version: as read, or gone once their
  -- new version is in.
  if to_regprocedure('public.' || c_old_particulars) is not null then
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_old_particulars))) <> c_old_particulars_md5 then
      raise exception '419: public.% is not the version read on 18 Oct 2026', c_old_particulars; end if;
    v_drop_particulars := true;
  elsif to_regprocedure('public.update_survey_particulars_v2(uuid,jsonb,text)') is null then
    raise exception '419: public.% is missing, and its new version is not there', c_old_particulars; end if;
  if to_regprocedure('public.' || c_old_review) is not null then
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_old_review))) <> c_old_review_md5 then
      raise exception '419: public.% is not the version read on 18 Oct 2026', c_old_review; end if;
    v_drop_review := true;
  elsif to_regprocedure('public.review_health_survey(uuid,text,text,text,text,boolean)') is null then
    raise exception '419: public.% is missing, and its new version is not there', c_old_review; end if;
  -- No other function takes a name this installs.
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('can_view_health_data', 'health_survey_sign_into_record', 'update_survey_particulars_v2',
                       'review_health_survey', 'upsert_consultant_survey', 'survey_link_info', 'add_survey_attachment',
                       'health_survey_detail', 'submit_health_survey', 'attach_held_health_survey',
                       'health_survey_holds_list', 'create_customer_from_held_survey', 'update_survey_particulars',
                       'diagnose_survey_name_edit', 'customer_survey_overview', 'report_customer_sources')
     and p.oid::regprocedure::text not in ('can_view_health_data()', 'health_survey_sign_into_record(uuid,health_surveys,jsonb,text)', 'update_survey_particulars_v2(uuid,jsonb,text)', 'upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)', 'survey_link_info(text)', 'add_survey_attachment(uuid,text,text,text,integer,text)', 'health_survey_detail(uuid)', 'review_health_survey(uuid,text,text,text,text,boolean)', 'submit_health_survey(text,jsonb,jsonb,text)', 'attach_held_health_survey(uuid,uuid,text)', 'health_survey_holds_list()', 'create_customer_from_held_survey(uuid,text)', 'diagnose_survey_name_edit(text)', 'customer_survey_overview(text,text,integer,integer)', 'report_customer_sources(date,date)', c_old_particulars, c_old_review);
  if v is not null then
    raise exception '419: another function takes one of these names: %', v; end if;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  if v_add_column then
    alter table public.survey_links
      add column source_option_id uuid references public.customer_source_options(id);
    comment on column public.survey_links.source_option_id is
      '419: how the customers of an event''s link heard about us (Event or RoadShow), chosen when the link is made.';
  end if;
  if v_widen_sex then
    alter table public.health_surveys drop constraint health_surveys_sex_check;
    alter table public.health_surveys add constraint health_surveys_sex_check
      check (sex = any (array['male'::text, 'female'::text, 'other'::text]));
  end if;
  if v_drop_review then
    execute 'drop function public.' || c_old_review;
  end if;
  for k in 1 .. coalesce(cardinality(v_install), 0) loop
    execute v_defs[k];
    if v_acls[k] = '' then
      -- New: callable by signed-in users and the server (each checks the
      -- caller first), except the internal helper, which is the server's.
      execute format('revoke all on function public.%s from public, anon', v_install[k]);
      if v_install[k] = 'health_survey_sign_into_record(uuid,health_surveys,jsonb,text)' then
        execute format('revoke all on function public.%s from authenticated', v_install[k]);
        execute format('grant execute on function public.%s to service_role', v_install[k]);
      else
        execute format('grant execute on function public.%s to authenticated, service_role', v_install[k]);
      end if;
    end if;
  end loop;
  for k in 1 .. coalesce(cardinality(v_patch_sql), 0) loop
    execute v_patch_sql[k];
    if (select coalesce(p.proacl::text, '') from pg_proc p
         where p.oid = to_regprocedure('public.' || v_patch_fns[k])) is distinct from v_patch_acls[k] then
      raise exception '419: the grants of public.% changed', v_patch_fns[k]; end if;
  end loop;
  if v_drop_particulars then
    execute 'drop function public.' || c_old_particulars;
  end if;
  if v_rules then
    alter policy "read surveys" on public.health_surveys using ((select public.can_view_health_data()));
    alter policy "read survey symptoms" on public.health_survey_symptoms using ((select public.can_view_health_data()));
    alter policy "read consultant notes" on public.consultant_notes using ((select public.can_view_health_data()));
    alter policy "read customer remarks" on public.customer_remarks using ((select public.can_view_health_data()));
    alter policy "read survey pdfs" on public.health_survey_pdfs using (
      (select public.can_view_health_data())
      and exists (select 1 from public.health_surveys s
                   where s.id = health_survey_pdfs.survey_id
                     and ((select public.is_manager_or_above()) or public.user_has_store_access(s.store_id))));
  end if;
  if v_bucket then
    update storage.buckets set file_size_limit = 10485760, allowed_mime_types = c_mimes where id = 'survey-attachments';
  end if;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  for r in select * from (values
      ('can_view_health_data()', '5cccb54dd99d2c3d77548cd8242ea126'),
      ('health_survey_sign_into_record(uuid,health_surveys,jsonb,text)', 'ac2bbd3742f3b4364b289ddd29715215'),
      ('update_survey_particulars_v2(uuid,jsonb,text)', '45ebc42b54405810b104d4c0c292dcf5'),
      ('upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)', 'e5e6922d5fbe16ee81d44246cabd9d60'),
      ('survey_link_info(text)', '626e3bdd4d29e7508a8520fbae11b826'),
      ('add_survey_attachment(uuid,text,text,text,integer,text)', 'a856b3463d4e9c8784e2cf1e6d2b649b'),
      ('health_survey_detail(uuid)', '2aa7515661ea56171be26657a3ea7af5'),
      ('review_health_survey(uuid,text,text,text,text,boolean)', '46bddd90d9badfae99cff53379275e64'),
      ('submit_health_survey(text,jsonb,jsonb,text)', 'ad2a66909b663026911dff137ab12185'),
      ('attach_held_health_survey(uuid,uuid,text)', '53aabcdd564da445131633c41bef8249'),
      ('health_survey_holds_list()', '0487502f033b56452140c81e108a8ebc'),
      ('create_customer_from_held_survey(uuid,text)', '733db65d708db7c64b5c4de03493d409'),
      ('diagnose_survey_name_edit(text)', '06b97410274c13feec87ab83621877c1'),
      ('customer_survey_overview(text,text,integer,integer)', 'd0301231179b3d05107e3309264692ff'),
      ('report_customer_sources(date,date)', '285e5b21754cf3fecababe3058a8bf58')) as x(fn, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '419: public.% was installed with an md5 other than the tested one', r.fn; end if;
  end loop;
  for k in 1 .. coalesce(cardinality(v_install), 0) loop
    if v_acls[k] <> '' and (select coalesce(p.proacl::text, '') from pg_proc p
                             where p.oid = to_regprocedure('public.' || v_install[k])) is distinct from v_acls[k] then
      raise exception '419: the grants of public.% changed', v_install[k]; end if;
  end loop;
  if to_regprocedure('public.' || c_old_particulars) is not null or to_regprocedure('public.' || c_old_review) is not null then
    raise exception '419: an old version is still there'; end if;
  if not has_function_privilege('anon', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
     or not has_function_privilege('anon', 'public.survey_link_info(text)', 'execute') then
    raise exception '419: the public form can no longer be sent signed out'; end if;
  for r in select unnest(array['can_view_health_data()', 'update_survey_particulars_v2(uuid,jsonb,text)',
                               'review_health_survey(uuid,text,text,text,text,boolean)']) as fn
  loop
    if has_function_privilege('anon', 'public.' || r.fn, 'execute')
       or not has_function_privilege('authenticated', 'public.' || r.fn, 'execute') then
      raise exception '419: public.% is not callable by signed-in users alone', r.fn; end if;
  end loop;
  if has_function_privilege('anon', 'public.health_survey_sign_into_record(uuid,health_surveys,jsonb,text)', 'execute')
     or has_function_privilege('authenticated', 'public.health_survey_sign_into_record(uuid,health_surveys,jsonb,text)', 'execute')
     or not has_function_privilege('service_role', 'public.health_survey_sign_into_record(uuid,health_surveys,jsonb,text)', 'execute') then
    raise exception '419: health_survey_sign_into_record is not the server''s alone'; end if;
  for k in 1 .. array_length(c_rules, 1) loop
    if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
         where p.polrelid = ('public.' || c_rules[k][1])::regclass and p.polname = c_rules[k][2]) is distinct from c_rule_after then
      raise exception '419: the rule "%" is not as tested', c_rules[k][2]; end if;
  end loop;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.health_survey_pdfs'::regclass and p.polname = 'read survey pdfs') is distinct from c_pdf_rule_after then
    raise exception '419: the rule "read survey pdfs" is not as tested'; end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.health_surveys'::regclass and c.conname = 'health_surveys_sex_check') is distinct from c_sex_after
     or not exists (select 1 from storage.buckets b where b.id = 'survey-attachments'
                       and b.file_size_limit = 10485760 and b.allowed_mime_types = c_mimes)
     or (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
          where a.attrelid = 'public.survey_links'::regclass and a.attname = 'source_option_id' and not a.attisdropped) is distinct from 'uuid' then
    raise exception '419: the survey tables or the files bucket are not as tested'; end if;

  -- ── 4. Behaviour, inside a block that is always undone ──────────────────
  -- Made-up people (@sig.invalid), a made-up store, customer, source and
  -- event link, and a fictional phone number; nothing is printed and no row
  -- remains.
  begin
    insert into auth.users (id, email) values (gen_random_uuid(), '419-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '419-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into auth.users (id, email) values (gen_random_uuid(), '419-check-invman-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_invman;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '419 check', u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff'), (v_invman, 'inventory_manager')) x(id, role)
        on x.id = u.id;
    insert into public.stores (name, code, country_code) values ('419 check', '419CHK', 'SG') returning id into v_store;
    insert into public.user_store_assignments (user_id, store_id) values (v_staff, v_store);
    insert into public.customer_source_options (label) values ('419 check ' || gen_random_uuid()) returning id into v_src;
    perform set_config('request.jwt.claims', '', true);
    insert into public.customers (first_name, last_name, phone, email, date_of_birth)
    values ('Checkone', 'Four Nineteen', '+61491570006', '419-check-customer@sig.invalid', date '1980-01-02')
    returning id into v_cust;
    v_token := '419-check-' || gen_random_uuid();
    insert into public.survey_links (token, store_id, event_name, source_option_id)
    values (v_token, v_store, '419 check fair', v_src) returning id into v_link;

    -- Staff start a survey at their store, without a store being chosen (they
    -- work at one), and save one answer: the others stay Not answered. They
    -- may not change the date of birth already filled in, nor save the
    -- consultant's review.
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_survey := public.upsert_consultant_survey(v_cust);
    perform public.update_survey_particulars_v2(v_survey, '{"smokes": false}'::jsonb, null);
    begin
      perform public.update_survey_particulars_v2(v_survey, '{"date_of_birth": "1980-01-03"}'::jsonb, '419 check');
      raise exception '419: a member of staff changed a date of birth already filled in';
    exception when insufficient_privilege then null;
    end;
    begin
      perform public.review_health_survey(v_survey, null, '419 check', null, null);
      raise exception '419: a member of staff saved the consultant''s review';
    exception when insufficient_privilege then null;
    end;
    select count(*) into v_seen from public.health_surveys s where s.id = v_survey;
    execute 'reset role';
    if v_seen <> 1
       or not exists (select 1 from public.health_surveys s where s.id = v_survey and s.store_id = v_store
                         and s.smokes is false and s.has_medical_condition is null and s.drinks_alcohol is null
                         and s.on_treatment is null and s.reviewed_at is null)
       or not exists (select 1 from public.audit_logs a where a.record_id = v_survey and a.action = 'survey_particulars_edited'
                         and a.changed_by = v_staff and a.old_data ? 'smokes' and a.old_data->>'smokes' is null
                         and (a.new_data->>'smokes')::boolean is false) then
      raise exception '419: a staff edit of one answer was not saved alone, with its old and new value';
    end if;

    -- An Owner saves a review; the same boxes emptied are refused, not saved.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.review_health_survey(v_survey, 'green', '419 goals', '419 condition', '419 advice');
    begin
      perform public.review_health_survey(v_survey, 'green', '', ' ', null);
      raise exception '419: an emptied Save Review blanked the saved review';
    exception when raise_exception then
      if sqlerrm not like 'Nothing to save%' then raise; end if;
    end;
    execute 'reset role';

    -- The customer fills in the event's QR form, signed out: it goes into
    -- their consultant record, which keeps the review; their answers win;
    -- the link's source is recorded.
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    execute 'set local role anon';
    v_out := public.submit_health_survey(v_token,
      jsonb_build_object('first_name', 'Checkone', 'last_name', 'Four Nineteen', 'full_name', 'Checkone Four Nineteen',
                         'phone', '+61 491 570 006', 'email', '419-check-customer@sig.invalid',
                         'signature_data', 'data:image/png;base64,AAAA', 'smokes', true,
                         'has_medical_condition', false),
      '[]'::jsonb, null);
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    if (v_out->>'survey_id')::uuid is distinct from v_survey
       or (select count(*) from public.health_surveys s where s.customer_id = v_cust) <> 1
       or not exists (select 1 from public.health_surveys s where s.id = v_survey
                         and s.signature_data is not null and s.source = 'consultant' and s.survey_link_id = v_link
                         and s.smokes is true and s.has_medical_condition is false and s.drinks_alcohol is null
                         and s.remarks_condition = '419 condition' and s.health_goals = '419 goals'
                         and s.source_option_id = v_src and s.source_details = '419 check fair')
       or not exists (select 1 from public.audit_logs a where a.record_id = v_survey
                         and a.action = 'health_survey_signed_by_customer')
       or not exists (select 1 from public.audit_logs a where a.record_id = v_survey and a.action = 'signed_pdf_missing') then
      raise exception '419: the QR form did not go into the customer''s consultant record as tested';
    end if;

    -- An Inventory Manager reads no health data, neither through the tables
    -- nor through the survey list; staff still do.
    perform set_config('request.jwt.claims', json_build_object('sub', v_invman, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_seen from public.health_surveys s where s.id = v_survey;
    begin
      perform count(*) from public.customer_survey_overview(null, 'all', 1, 0);
      raise exception '419: an Inventory Manager can read the survey list';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
    if v_seen <> 0 then
      raise exception '419: an Inventory Manager can read health surveys';
    end if;
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_seen from public.health_surveys s where s.id = v_survey;
    execute 'reset role';
    if v_seen <> 1 then
      raise exception '419: staff can no longer read the survey of their store';
    end if;
    raise exception using errcode = 'P0419', message = '419: check done, undone';
  exception when sqlstate 'P0419' then null;
  end;

  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
