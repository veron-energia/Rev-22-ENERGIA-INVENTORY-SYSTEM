-- 433_qr_survey_holds_unsure_forms_for_staff.sql
--
-- THE QR HEALTH SURVEY NO LONGER MAKES A SECOND CUSTOMER: A FORM IT IS UNSURE
-- ABOUT WAITS FOR STAFF (the owner's decision, 16 Oct 2026: "Apply the same
-- fix to the QR health survey", then "A: hold for staff" and "Any staff")
--
-- WHY
--
--   The public QR form (submit_health_survey, signed out) attaches a form to
--   a customer only when the phone and the name match one exactly. Otherwise
--   it makes a new customer, even when a customer already has the phone, or
--   the same email. Production, 1 Aug to 16 Oct 2026: 107 forms, 65 new
--   customers, about 10 of them most likely someone already on record:
--   5 on the same phone under a name written differently (a spelling, a
--   middle name, a short name; 4 of them with the same email), and 5 with
--   the same email inbox on another phone (the old record's phone is mostly
--   a legacy number that cannot be read). The name rule of 432 alone catches
--   none of them. The email is what gives them away, but the form's email is
--   not verified, and a form is a health declaration: attaching it to the
--   wrong person is worse than a second record.
--
-- WHAT THIS DOES
--
--   1. Same words. As at sign-up (432): when no customer with the phone has
--      the name exactly as typed, one whose name has the same words matches
--      too (customer_names_match: any order, unless there is a patronymic;
--      neighbouring words together or apart; case, punctuation and a note in
--      brackets left out). One such customer: the form is attached, as an
--      exact match is, and carries the customer's name (see 4).
--   2. Held for staff. When no customer matches the name, but a customer in
--      use has the phone, or the email's inbox (customer_email_match_key:
--      Gmail dots, +tags and googlemail.com read as one address), no customer
--      is made. The form is kept, with no customer, and waits for staff (new
--      table health_survey_holds), with whoever has the phone or the email as
--      the customers it may belong to, and the name, phone and email as
--      typed. So does a form whose name matches several customers on the
--      phone: it was refused (AMBIGUOUS_CUSTOMER_MATCH, "ask our consultant"),
--      and the signed form was lost. The person sees the usual thank-you. A
--      phone shared by 3 is no longer an error. The same person sending the
--      form again (the same phone, the name as typed) is answered
--      HEALTH_SURVEY_ALREADY_EXISTS, as a customer's second survey is, while
--      their form waits or once it is the survey of a customer in use
--      (attached, made into a customer, or moved by a merge).
--   3. Staff match a waiting form (the owner: any active staff, not an
--      inventory manager, as with health surveys):
--      * health_survey_holds_list(): the waiting forms, oldest first, with
--        what the person typed and the customers it may belong to: those it
--        was held for, and whoever has its phone or email now (whether each
--        has the phone, the email, the name, and a survey already);
--      * attach_held_health_survey(survey, customer, note): attaches the
--        form to a customer with no survey yet (one survey each). The
--        customer's empty details are filled from the form (email, date of
--        birth, sex, occupation, source; never the name or phone), as the
--        form does itself when it finds the customer. A note on how they
--        confirmed it is required;
--      * create_customer_from_held_survey(survey, note): makes a new customer
--        from the form, as the form itself would have (a family member
--        sharing the phone or email; up to 3 customers on a phone), and
--        attaches the form to them;
--      * close_held_health_survey(survey, reason), an Owner or Manager only:
--        takes a form off the list without attaching it (a test, a form sent
--        twice, a customer who already has a survey). The form is kept, with
--        no customer. The person may send the form again.
--      Each is written in the Audit Log (health_survey_matched with what was
--      typed, health_survey_customer_created, health_survey_hold_closed), and
--      the submission's own row says whether it was held, why, how the name
--      matched, and the name typed. The Surveys page lists the waiting forms
--      under "To match".
--   4. A form staff attach takes the customer's name parts exactly as they
--      are, as a form the form itself attaches already does (its insert takes
--      them, through trg_survey_inherit_customer and trg_sync_person_name),
--      and as every survey does once its customer's name is edited. Saving
--      its details (update_survey_particulars) writes the survey's name onto
--      the customer, so it would otherwise rename them to what the person
--      typed, dropping an old record's note. The phone and email typed stay
--      on the form: TikTok attendance reads them.
--   5. The form's reply no longer says whether a customer was found or made
--      (customer_created, customer_matched; the Audit Log row keeps both): a
--      held form would tell anyone with the link whether a phone or an email
--      is a customer's. The page reads only survey_no.
--   6. The TikTok no-show run (ads_rpc_no_show_run, 8:45pm) counts a form
--      held for staff that day from the lead's phone or email as attendance,
--      whatever became of it: while it waits it has no customer, so
--      ads_find_attendance cannot see it, and once closed it has none either;
--      the person who came would be sent "we missed you".
--
-- WHAT STAYS
--
--   * An exact phone + name match is attached as before, refused as before
--     when that customer already has a survey, and fills only the customer's
--     empty details. A form from a phone and email no customer has makes a
--     customer as before. Every field the form saves is unchanged.
--   * Who may send a form (anyone with a live link); the success, survey_no
--     and survey_id it answers.
--   * customer_phone_name_matches; require_resolved_customer_identity, which
--     still refuses a form whose name matches an old record whose phone
--     cannot be read but could be this one (AMBIGUOUS_CUSTOMER_MATCH, as
--     before); the referral sign-up; ads_find_attendance; and every grant of
--     submit_health_survey and ads_rpc_no_show_run.
--
-- NOT COVERED (told to the owner)
--
--   * Until staff attach it, a waiting form counts as no visit
--     (customer_centre_visit_days, the October promotion) and as no TikTok
--     attendance for the morning sync and the thank-you message
--     (ads_find_attendance reads only surveys with a customer); only the
--     no-show run allows for it (6). Staff should match forms the same day.
--   * A waiting form shows in no customer's survey list until it is
--     attached. Its PDF and answers are kept with it.
--   * After an attach, the form keeps the phone and email typed. Saving its
--     details writes them onto the customer (update_survey_particulars), as
--     for any survey whose details differ from its customer's.
--   * An old record whose phone cannot be read as one number (7,959 of the
--     12,970 customers in use, from the July import) does not count as
--     having a phone, here as before: with another name, a form beside one
--     still makes a customer. None of the 65 customers the form made since
--     1 Aug was such a case, and reading those phones for every form would
--     take longer than the form may.
--   * The email is compared by reading every customer's address (no index:
--     an index on customer_email_match_key would run with the rights of
--     whoever edits a customer, and 432 keeps that function the server's).
--     About 50 ms per form at today's 13,000 customers.
--   * The duplicates already made are left as they are; merging is the
--     owner's decision. B05 (the survey batch, not built) must build on this
--     version of submit_health_survey; its Q10 (QR answers going into an
--     empty consultant record) is not part of this.
--
-- DEPLOY: apply this first, then the Surveys page (it shows "To match" only
-- when the server answers health_survey_holds_list).
--
-- SAFETY
--
--   ONE statement (a single DO block), so it is atomic whatever runs it, and
--   every check comes before anything is created:
--   * submit_health_survey and ads_rpc_no_show_run must be the versions read
--     on 16 Oct 2026 (BEFORE), or already this migration's (AFTER, left
--     alone). Each anchor must occur exactly once, and each text built must
--     have the tested md5.
--   * The functions they rely on and do not change must be as read on 16
--     Oct 2026 (432's matching rules among them), and so must the columns of
--     health_surveys and customers they read and write, and the one survey
--     per customer index.
--   * health_survey_holds must be missing, or already this shape. The 4 new functions must be missing, or already
--     this version, and no other function may take their names.
--   * Afterwards all 6 functions have their AFTER md5s; submit_health_survey
--     and ads_rpc_no_show_run keep their grants (anon may send the form; the
--     no-show run stays the server's); the 4 new ones are callable by
--     signed-in users and the service role (each checks the caller), not
--     anon; the table is reachable by no client role (row level security on,
--     no policy; the service role may read it, as the no-show run does). A
--     second run changes nothing.
--
-- BEFORE (production, 16 Oct 2026, after 432; md5 of pg_get_functiondef with
-- search_path public):
--   changed
--   submit_health_survey(text,jsonb,jsonb,text)             67f3e558c2d7f20edabe51bf383aead1
--   ads_rpc_no_show_run(text,text,text,text)                69683c0a66ec56b5f0b82fdec341b8c0
--   relied on, not changed
--   customer_names_match(text,text)                         ef1af52e4888cefb6037a2291f4e011d  (432)
--   customer_name_words(text)                               a7507abf0f15abd923dff59508b269c1  (432)
--   customer_email_match_key(text)                          be468815c9626fff1728e2cfcd484b66  (432)
--   customer_phone_name_matches(text,text)                  1bdf8322972b6671b7cbb08bc8211f8a
--   normalize_customer_phone(text)                          b2bfac910e0c9eff402ba44e19750bee
--   normalize_customer_match_name(text)                     0572764712e179dc606c66f9f3dbaa03
--   require_resolved_customer_identity(text,text)           5bde1a418363442ec27e2944442f5874
--   ads_normalize_phone(text,text)                          a61154d7e66e01b273e8b9911a213a2c
--   require_active_staff(text[])                            877b3aa74cea559881979bb161c450e2
--   write_audit_ex(...)                                     c705c733e213a27f0dc32d54322cc855
--   trg_sync_customer_to_surveys()                          a316d1e7d053de7e24ed45f19a652f0f
--   trg_survey_inherit_customer()                           5b145a044ea35d3a2237f0ff4e65b600
--   trg_health_survey_guard()                               68234ede2f09e5908490eec1eb501b1a
--   enforce_customer_phone_policy()                         009273025173c6666a0ecf0408cb7ce1
--   public function fingerprint (production after 432)      b6757ec2f685e9756e59fa4014aa9a44
-- AFTER (for later guards):
--   submit_health_survey(text,jsonb,jsonb,text)             5a3f27a0b9a0bed619ac0c82c8c52aab
--   ads_rpc_no_show_run(text,text,text,text)                b0499ec3ab207e66e8c56e2f01ba3978
--   health_survey_holds_list()                (new)         c3f50d90ba0509935681e4446bcbb21b
--   attach_held_health_survey(uuid,uuid,text) (new)         104370324b701192ba9710d515cc388f
--   create_customer_from_held_survey(uuid,text) (new)       d503d8b599f90768c8d909b91cd453e1
--   close_held_health_survey(uuid,text)       (new)         ee4789b1d716e4fbf498a5f38e722735
--   public function fingerprint (after 432 + 433)           ff637c8e7adc37a4892a6bf361290c4b
--
-- Test: scripts/survey/tests/qr-holds.sql (begin ... rollback; it installs
-- this file itself, twice).

set lock_timeout = '5s';

do $mig$
declare
  c_fn constant text := 'public.submit_health_survey(text,jsonb,jsonb,text)';
  c_before constant text := '67f3e558c2d7f20edabe51bf383aead1';
  c_after constant text := '5a3f27a0b9a0bed619ac0c82c8c52aab';
  c_ns constant text := 'public.ads_rpc_no_show_run(text,text,text,text)';
  c_ns_before constant text := '69683c0a66ec56b5f0b82fdec341b8c0';
  c_ns_after constant text := 'b0499ec3ab207e66e8c56e2f01ba3978';

  -- ── The new functions, as pg_get_functiondef gives them back ────────────
  c_list_def constant text := $def$CREATE OR REPLACE FUNCTION public.health_survey_holds_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_rows jsonb;
begin
  -- 433: the QR forms waiting for staff, oldest first, with what the person
  -- typed and the customers the form may belong to: those it was held for
  -- (whoever had its phone or its email's inbox, or the several whose name
  -- matched), and whoever has the phone or the email now. Any active staff
  -- who may open health surveys (not inventory managers), as
  -- health_survey_detail.
  perform public.require_active_staff('{owner,admin,manager,staff}');
  -- Every customer's email as compared, worked out once for the whole list.
  with keys as materialized (
    select x.id, public.customer_email_match_key(x.email) as k
      from public.customers x
     where x.deleted_at is null and x.email is not null)
  select coalesce(jsonb_agg(jsonb_build_object(
      'survey_id', s.id, 'survey_no', s.survey_no, 'submitted_at', s.submitted_at,
      'store_name', (select st.name from public.stores st where st.id = s.store_id),
      'event_name', s.event_name,
      'full_name', s.full_name, 'date_of_birth', s.date_of_birth, 'sex', s.sex,
      'phone', s.phone, 'email', s.email, 'occupation', s.occupation, 'source_label', s.source_label,
      'reason', h.reason, 'held_at', h.held_at,
      'candidates', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'customer_id', c.id, 'full_name', c.full_name, 'phone', c.phone, 'email', c.email,
                 'date_of_birth', c.date_of_birth, 'created_at', c.created_at,
                 'deleted', c.deleted_at is not null,
                 'phone_matches', coalesce(public.normalize_customer_phone(c.phone) = h.typed_phone, false),
                 'email_matches', coalesce(public.customer_email_match_key(c.email) = public.customer_email_match_key(h.typed_email), false),
                 'name_matches', coalesce(public.normalize_customer_match_name(c.full_name) = public.normalize_customer_match_name(s.full_name)
                                          or public.customer_names_match(c.full_name, s.full_name), false),
                 'survey_no', (select x.survey_no from public.health_surveys x where x.customer_id = c.id))
               order by c.created_at)
          from public.customers c
         where c.id in (select unnest(h.candidate_customer_ids)
                        union
                        select x.id from public.customers x
                         where x.deleted_at is null and public.normalize_customer_phone(x.phone) = h.typed_phone
                        union
                        select keys.id from keys where keys.k = public.customer_email_match_key(h.typed_email))), '[]'::jsonb)
    ) order by h.held_at), '[]'::jsonb)
    into v_rows
    from public.health_survey_holds h
    join public.health_surveys s on s.id = h.survey_id
   where h.resolved_at is null and s.customer_id is null;
  return v_rows;
end $function$
$def$;
  c_attach_def constant text := $def$CREATE OR REPLACE FUNCTION public.attach_held_health_survey(p_survey_id uuid, p_customer_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_h public.health_survey_holds%rowtype; v_s public.health_surveys%rowtype; v_c public.customers%rowtype;
        v_gender public.customer_gender; v_existing text;
begin
  -- 433: staff attach a QR form waiting for them to the customer it belongs
  -- to (the owner, 16 Oct 2026: any staff). The customer's empty details are
  -- filled from the form, never their name or phone, as the form does itself
  -- when it finds the customer. Then the form is attached and carries the
  -- customer's name, as a survey does whenever its customer's name is edited
  -- (trg_sync_customer_to_surveys), so that saving its details never renames
  -- the customer; the phone and email typed stay on it (TikTok attendance
  -- reads them). What was typed is kept in the hold and the Audit Log row. A
  -- customer has one health survey.
  perform public.require_active_staff('{owner,admin,manager,staff}');
  if p_note is null or btrim(p_note) = '' then
    raise exception 'Add a short note on how you confirmed this is the same person.'; end if;

  select * into v_h from public.health_survey_holds where survey_id = p_survey_id for update;
  if not found then raise exception 'This form is not waiting to be matched.'; end if;
  if v_h.resolved_at is not null then raise exception 'This form has already been dealt with.'; end if;
  select * into v_s from public.health_surveys where id = p_survey_id for update;
  if v_s.customer_id is not null then raise exception 'This form is already attached to a customer.'; end if;

  select * into v_c from public.customers where id = p_customer_id for update;
  if not found or v_c.deleted_at is not null then raise exception 'Customer not found.'; end if;
  select x.survey_no into v_existing from public.health_surveys x where x.customer_id = v_c.id;
  if v_existing is not null then
    raise exception 'This customer already has a health survey (%). A customer can have only one.', v_existing; end if;

  v_gender := case when v_s.sex in ('male', 'female') then v_s.sex::public.customer_gender end;
  update public.customers
     set email             = coalesce(email, nullif(btrim(v_s.email), '')),
         date_of_birth     = coalesce(date_of_birth, v_s.date_of_birth),
         gender            = coalesce(gender, v_gender),
         occupation        = coalesce(occupation, nullif(btrim(v_s.occupation), '')),
         source_option_id  = coalesce(source_option_id, v_s.source_option_id),
         source_label      = coalesce(source_label, v_s.source_label),
         source_details    = coalesce(source_details, v_s.source_details),
         source_updated_at = case when source_option_id is null and v_s.source_option_id is not null
                                  then now() else source_updated_at end,
         updated_at        = now()
   where id = v_c.id;
  -- The customer's name parts exactly as they are (a one-word name has no
  -- last name), so the form's whole name is the customer's; a customer with
  -- no name at all leaves the form's.
  update public.health_surveys set
    customer_id = v_c.id,
    first_name  = case when nullif(trim(coalesce(v_c.full_name, '')), '') is not null then v_c.first_name else first_name end,
    last_name   = case when nullif(trim(coalesce(v_c.full_name, '')), '') is not null then v_c.last_name else last_name end,
    full_name   = coalesce(nullif(trim(coalesce(v_c.full_name, '')), ''), full_name)
   where id = v_s.id;
  update public.health_survey_holds
     set resolved_at = now(), resolved_by = auth.uid(), resolution = 'attached',
         resolved_customer_id = v_c.id, resolution_note = btrim(p_note)
   where survey_id = v_s.id;

  perform public.write_audit_ex('health_surveys', v_s.id, 'health_survey_matched',
    jsonb_build_object('typed_name', v_s.full_name, 'typed_phone', v_s.phone, 'typed_email', v_s.email),
    jsonb_build_object('customer_id', v_c.id, 'survey_no', v_s.survey_no, 'hold_reason', v_h.reason,
                       'suggested_customer', v_c.id = any (v_h.candidate_customer_ids)),
    'health_survey', btrim(p_note), v_s.store_id);
  return jsonb_build_object('ok', true, 'customer_id', v_c.id, 'survey_no', v_s.survey_no);
end $function$
$def$;
  c_create_def constant text := $def$CREATE OR REPLACE FUNCTION public.create_customer_from_held_survey(p_survey_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_h public.health_survey_holds%rowtype; v_s public.health_surveys%rowtype;
        v_gender public.customer_gender; v_cust uuid;
begin
  -- 433: staff make a new customer from a QR form waiting for them, when the
  -- person is not the customer it was held for (a family member sharing the
  -- phone or email), and attach the form to them (the owner, 16 Oct 2026: any
  -- staff). As the form itself makes a customer: from what the person typed,
  -- and up to 3 customers on one phone.
  perform public.require_active_staff('{owner,admin,manager,staff}');

  select * into v_h from public.health_survey_holds where survey_id = p_survey_id for update;
  if not found then raise exception 'This form is not waiting to be matched.'; end if;
  if v_h.resolved_at is not null then raise exception 'This form has already been dealt with.'; end if;
  select * into v_s from public.health_surveys where id = p_survey_id for update;
  if v_s.customer_id is not null then raise exception 'This form is already attached to a customer.'; end if;

  -- One person's record at a time per phone, as the form takes it.
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:'
            || coalesce(public.normalize_customer_phone(v_s.phone), v_s.phone, ''), 0));
  v_gender := case when v_s.sex in ('male', 'female') then v_s.sex::public.customer_gender end;
  insert into public.customers (full_name, phone, email, date_of_birth, gender, occupation,
                                source_option_id, source_label, source_details, source_updated_at)
  values (v_s.full_name, v_s.phone, nullif(btrim(v_s.email), ''), v_s.date_of_birth, v_gender,
          nullif(btrim(v_s.occupation), ''), v_s.source_option_id, v_s.source_label, v_s.source_details, now())
  returning id into v_cust;
  update public.health_surveys set customer_id = v_cust where id = v_s.id;
  update public.health_survey_holds
     set resolved_at = now(), resolved_by = auth.uid(), resolution = 'created',
         resolved_customer_id = v_cust, resolution_note = nullif(btrim(p_note), '')
   where survey_id = v_s.id;

  perform public.write_audit_ex('health_surveys', v_s.id, 'health_survey_customer_created', null,
    jsonb_build_object('customer_id', v_cust, 'survey_no', v_s.survey_no, 'hold_reason', v_h.reason,
                       'held_for', v_h.candidate_customer_ids),
    'health_survey', nullif(btrim(p_note), ''), v_s.store_id);
  return jsonb_build_object('ok', true, 'customer_id', v_cust, 'survey_no', v_s.survey_no);
end $function$
$def$;
  c_close_def constant text := $def$CREATE OR REPLACE FUNCTION public.close_held_health_survey(p_survey_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_h public.health_survey_holds%rowtype; v_s public.health_surveys%rowtype;
begin
  -- 433: an Owner or Manager takes a QR form off the waiting list without
  -- attaching it (a test, a form sent twice, a customer who already has a
  -- survey). The form itself is kept, with no customer; a reason is required.
  perform public.require_active_staff('{owner,manager}');
  if p_reason is null or btrim(p_reason) = '' then raise exception 'A reason is required.'; end if;

  select * into v_h from public.health_survey_holds where survey_id = p_survey_id for update;
  if not found then raise exception 'This form is not waiting to be matched.'; end if;
  if v_h.resolved_at is not null then raise exception 'This form has already been dealt with.'; end if;
  select * into v_s from public.health_surveys where id = p_survey_id for update;
  if v_s.customer_id is not null then raise exception 'This form is already attached to a customer.'; end if;

  update public.health_survey_holds
     set resolved_at = now(), resolved_by = auth.uid(), resolution = 'closed', resolution_note = btrim(p_reason)
   where survey_id = v_s.id;
  perform public.write_audit_ex('health_surveys', v_s.id, 'health_survey_hold_closed', null,
    jsonb_build_object('survey_no', v_s.survey_no, 'hold_reason', v_h.reason,
                       'held_for', v_h.candidate_customer_ids),
    'health_survey', btrim(p_reason), v_s.store_id);
  return jsonb_build_object('ok', true, 'survey_no', v_s.survey_no);
end $function$
$def$;

  -- ── submit_health_survey: each anchor becomes its patch ─────────────────
  c_anchors constant text[] := array[
    $a$  v_matches uuid[]; v_match_count int; v_matched boolean := false; v_created boolean := false;
$a$,
    $a$  v_matches := public.customer_phone_name_matches(v_norm,v_name);
  v_match_count := cardinality(v_matches);
$a$,
    $a$  if v_match_count > 1 then
    -- Legacy ambiguity: never attach private health data to a guessed record.
    raise exception 'AMBIGUOUS_CUSTOMER_MATCH';
$a$,
    $a$       or exists (select 1 from public.health_surveys
                   where customer_id is null
                     and public.normalize_customer_phone(phone) = v_norm
                     and public.normalize_customer_match_name(full_name) = public.normalize_customer_match_name(v_name)) then
      raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
$a$,
    $a$    if exists(select 1 from public.health_surveys where customer_id is null
      and public.normalize_customer_phone(phone)=v_norm
      and public.normalize_customer_match_name(full_name)=public.normalize_customer_match_name(v_name)) then
      raise exception 'AMBIGUOUS_CUSTOMER_MATCH';
$a$,
    $a$    -- No phone-plus-name match: create a new customer subject to capacity.
    insert into public.customers (full_name, phone, email, date_of_birth, gender, occupation,
                                  source_option_id, source_label, source_details, source_updated_at)
    values (v_name, coalesce(v_norm, v_phone), v_email,
            nullif(p_payload->>'date_of_birth','')::date, v_gender,
            nullif(trim(p_payload->>'occupation'), ''),
            v_src.id, v_src.label, v_src_details, now())
    returning id into v_cust_id;
    v_created := true;
  end if;
$a$,
    $a$  insert into public.audit_logs (table_name, record_id, action, new_data, module, store_id, ip_address, device_info)
  values ('health_surveys', v_id, 'health_survey_submitted',
          jsonb_build_object('survey_no', v_no, 'customer_id', v_cust_id, 'source', 'public_qr',
                             'customer_source', v_src.label,
                             'customer_created', v_created, 'customer_matched', v_matched),
$a$,
    $a$  return jsonb_build_object('success', true, 'survey_no', v_no, 'survey_id', v_id,
                            'customer_created', v_created, 'customer_matched', v_matched);
$a$];
  c_patches constant text[] := array[
    $r$  v_matches uuid[]; v_match_count int; v_matched boolean := false; v_created boolean := false;
  -- 433: how the name matched, the email as compared, the customers who have
  -- the phone or the email's inbox, and why the form waits for staff, for whom.
  v_name_match text; v_email_key text; v_phone_holders uuid[]; v_email_holders uuid[];
  v_hold text; v_candidates uuid[];
$r$,
    $r$  v_matches := public.customer_phone_name_matches(v_norm,v_name);
  -- 433: as at sign-up (432), when no customer with this phone has the name
  -- exactly as typed, one whose name has the same words counts too
  -- (customer_names_match): in any order (as written, with a patronymic such
  -- as bin or s/o), with neighbouring words together or apart, whatever the
  -- case and punctuation, and leaving out a note in brackets.
  if cardinality(v_matches) = 0 then
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_matches
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_norm
       and public.customer_names_match(c.full_name, v_name);
    if cardinality(v_matches) > 0 then v_name_match := 'same_words'; end if;
  else
    v_name_match := 'exact';
  end if;
  v_match_count := cardinality(v_matches);

  -- 433: the person sent this form before (this phone, this name as typed)
  -- and it was held: it still waits for staff, or it is now the survey of a
  -- customer in use (attached, made into a customer, or moved to the kept
  -- record by a merge). Refused as a customer's second survey is. One that
  -- was closed, or whose customer was deleted, is not the person's survey.
  if exists (select 1 from public.health_survey_holds h
               join public.health_surveys s on s.id = h.survey_id
               left join public.customers c on c.id = s.customer_id
              where h.typed_phone = v_norm
                and (public.normalize_customer_match_name(h.typed_full_name) = public.normalize_customer_match_name(v_name)
                     or public.customer_names_match(h.typed_full_name, v_name))
                and ((h.resolved_at is null and s.customer_id is null)
                     or (s.customer_id is not null and c.deleted_at is null))) then
    raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
  end if;
$r$,
    $r$  if v_match_count > 1 then
    -- Legacy ambiguity: never attach private health data to a guessed record.
    -- 433: the form is kept and held for staff, who attach it to the right
    -- one of them; it used to be refused, and the person sent to staff.
    v_hold := 'several_name_matches';
    v_candidates := v_matches;
$r$,
    $r$       or exists (select 1 from public.health_surveys
                   where customer_id is null
                     and public.normalize_customer_phone(phone) = v_norm
                     and public.normalize_customer_match_name(full_name) = public.normalize_customer_match_name(v_name)
                     -- 433: a form held for staff is not a legacy one: one still
                     -- waiting is refused above, and one an Owner or Manager
                     -- closed is no longer the person's survey.
                     and not exists (select 1 from public.health_survey_holds h
                                      where h.survey_id = health_surveys.id)) then
      raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
$r$,
    $r$    if exists(select 1 from public.health_surveys where customer_id is null
      and public.normalize_customer_phone(phone)=v_norm
      and public.normalize_customer_match_name(full_name)=public.normalize_customer_match_name(v_name)
      -- 433: a form held for staff is not a legacy one (see above).
      and not exists (select 1 from public.health_survey_holds h where h.survey_id = health_surveys.id)) then
      raise exception 'AMBIGUOUS_CUSTOMER_MATCH';
$r$,
    $r$    -- 433: no phone-plus-name match, but a customer in use has this phone, or
    -- this email's inbox (customer_email_match_key): the person may be them
    -- under another name, or someone sharing their phone or email. The form
    -- is kept and held for staff, who attach it or make a new customer from
    -- it (health_survey_holds); nothing is guessed. The email is not
    -- verified, so it never attaches a form by itself.
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_phone_holders
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_norm;
    v_email_key := public.customer_email_match_key(v_email);
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_email_holders
      from public.customers c
     where c.deleted_at is null and public.customer_email_match_key(c.email) = v_email_key;
    if cardinality(v_phone_holders) > 0 or cardinality(v_email_holders) > 0 then
      v_hold := case when cardinality(v_phone_holders) > 0 and cardinality(v_email_holders) > 0 then 'phone_and_email_in_use'
                     when cardinality(v_phone_holders) > 0 then 'phone_in_use'
                     else 'email_in_use' end;
      select coalesce(array_agg(distinct x order by x), '{}'::uuid[]) into v_candidates
        from unnest(v_phone_holders || v_email_holders) as x;
    else
    -- No phone-plus-name match: create a new customer subject to capacity.
    insert into public.customers (full_name, phone, email, date_of_birth, gender, occupation,
                                  source_option_id, source_label, source_details, source_updated_at)
    values (v_name, coalesce(v_norm, v_phone), v_email,
            nullif(p_payload->>'date_of_birth','')::date, v_gender,
            nullif(trim(p_payload->>'occupation'), ''),
            v_src.id, v_src.label, v_src_details, now())
    returning id into v_cust_id;
    v_created := true;
    end if;
  end if;
$r$,
    $r$  -- 433: a held form waits for staff, with the customers it may belong to and
  -- the phone and name as typed.
  if v_hold is not null then
    insert into public.health_survey_holds (survey_id, reason, candidate_customer_ids,
                                            typed_full_name, typed_phone, typed_email)
    values (v_id, v_hold, coalesce(v_candidates, '{}'::uuid[]), v_name, v_norm, v_email);
  end if;

  insert into public.audit_logs (table_name, record_id, action, new_data, module, store_id, ip_address, device_info)
  values ('health_surveys', v_id, 'health_survey_submitted',
          jsonb_build_object('survey_no', v_no, 'customer_id', v_cust_id, 'source', 'public_qr',
                             'customer_source', v_src.label,
                             'customer_created', v_created, 'customer_matched', v_matched,
                             -- 433: held for staff, why, how the name matched, and
                             -- the name as typed.
                             'held_for_staff', v_hold is not null, 'hold_reason', v_hold,
                             'name_match', v_name_match, 'typed_name', v_name),
$r$,
    $r$  -- 433: the reply no longer says whether a customer was found or made (the
  -- Audit Log row above does): a form held for staff would otherwise tell
  -- anyone with the link whether a phone or email is a customer's. The page
  -- reads only survey_no.
  return jsonb_build_object('success', true, 'survey_no', v_no, 'survey_id', v_id);
$r$];

  -- ── ads_rpc_no_show_run: its anchor and patch ───────────────────────────
  c_ns_anchor constant text := $a$        and not exists (select 1
                        from public.ads_find_attendance(l.phone_e164, l.email, l.first_name, l.last_name) f
                        where (f.survey_submitted_at at time zone 'Asia/Singapore')::date >= v_day)
$a$;
  c_ns_patch constant text := $r$        and not exists (select 1
                        from public.ads_find_attendance(l.phone_e164, l.email, l.first_name, l.last_name) f
                        where (f.survey_submitted_at at time zone 'Asia/Singapore')::date >= v_day)
        -- 433: a QR form from this phone or email that was held for staff that
        -- day is attendance too, whether it still waits (it has no customer,
        -- so ads_find_attendance cannot see it), was attached, or was closed:
        -- the person came.
        and not exists (select 1
                        from public.health_survey_holds h
                        join public.health_surveys hs on hs.id = h.survey_id
                        where (public.ads_normalize_phone(hs.phone) = l.phone_e164
                               or (nullif(trim(coalesce(l.email, '')), '') is not null
                                   and lower(trim(hs.email)) = lower(trim(l.email))))
                          and (hs.submitted_at at time zone 'Asia/Singapore')::date >= v_day)
$r$;

  -- The health_survey_holds table, as this migration makes it.
  c_holds_shape constant text := 'candidate_customer_ids uuid[] not null|held_at timestamp with time zone not null|reason text not null|resolution text|resolution_note text|resolved_at timestamp with time zone|resolved_by uuid|resolved_customer_id uuid|survey_id uuid not null|typed_email text|typed_full_name text not null|typed_phone text not null';

  v_path text := current_setting('search_path');
  r record; d text; d_ns text; n int; k int; v text;
  v_new text[] := '{}'; v_defs text[] := '{}';
  v_patch boolean := false; v_patch_ns boolean := false; v_acl text; v_acl_ns text;
  v_table_new boolean := false;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 16 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is installed unless all pass ─────────────────────
  for r in select * from (values
      ('customer_names_match(text,text)',               'ef1af52e4888cefb6037a2291f4e011d'),
      ('customer_name_words(text)',                     'a7507abf0f15abd923dff59508b269c1'),
      ('customer_email_match_key(text)',                'be468815c9626fff1728e2cfcd484b66'),
      ('customer_phone_name_matches(text,text)',        '1bdf8322972b6671b7cbb08bc8211f8a'),
      ('normalize_customer_phone(text)',                'b2bfac910e0c9eff402ba44e19750bee'),
      ('normalize_customer_match_name(text)',           '0572764712e179dc606c66f9f3dbaa03'),
      ('require_resolved_customer_identity(text,text)', '5bde1a418363442ec27e2944442f5874'),
      ('ads_normalize_phone(text,text)',                'a61154d7e66e01b273e8b9911a213a2c'),
      ('require_active_staff(text[])',                  '877b3aa74cea559881979bb161c450e2'),
      ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
      ('trg_sync_customer_to_surveys()',                'a316d1e7d053de7e24ed45f19a652f0f'),
      ('trg_survey_inherit_customer()',                 '5b145a044ea35d3a2237f0ff4e65b600'),
      ('trg_health_survey_guard()',                     '68234ede2f09e5908490eec1eb501b1a'),
      ('enforce_customer_phone_policy()',               '009273025173c6666a0ecf0408cb7ce1')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '433: public.% is missing or not the version this was tested against. Re-read it from production and re-test before applying.', r.fn;
    end if;
  end loop;

  -- The columns of health_surveys and customers this reads and writes.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.health_surveys'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('id', 'survey_no', 'store_id', 'customer_id', 'event_name', 'full_name', 'first_name',
                       'last_name', 'date_of_birth', 'sex', 'phone', 'email', 'occupation', 'source_option_id',
                       'source_label', 'source_details', 'submitted_at');
  if v is distinct from 'customer_id uuid|date_of_birth date|email text|event_name text|first_name text|full_name text|id uuid|last_name text|occupation text|phone text|sex text|source_details text|source_label text|source_option_id uuid|store_id uuid|submitted_at timestamp with time zone|survey_no text' then
    raise exception '433: public.health_surveys is not shaped as read on 16 Oct 2026 (%)', v; end if;
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.customers'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('id', 'full_name', 'first_name', 'last_name', 'phone', 'email', 'date_of_birth', 'gender',
                       'occupation', 'deleted_at', 'created_at', 'source_option_id', 'source_label', 'source_details',
                       'source_updated_at', 'updated_at');
  if v is distinct from 'created_at timestamp with time zone|date_of_birth date|deleted_at timestamp with time zone|email text|first_name text|full_name text|gender customer_gender|id uuid|last_name text|occupation text|phone text|source_details text|source_label text|source_option_id uuid|source_updated_at timestamp with time zone|updated_at timestamp with time zone' then
    raise exception '433: public.customers is not shaped as read on 16 Oct 2026 (%)', v; end if;
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'health_surveys' and indexname = 'uq_health_survey_customer'
                    and indexdef = 'CREATE UNIQUE INDEX uq_health_survey_customer ON public.health_surveys USING btree (customer_id) WHERE (customer_id IS NOT NULL)') then
    raise exception '433: the index uq_health_survey_customer (one survey per customer) is missing or not as read on 16 Oct 2026'; end if;

  -- health_survey_holds: missing, or already this shape.
  if to_regclass('public.health_survey_holds') is null then
    v_table_new := true;
  else
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                      '|' order by a.attname) into v
      from pg_attribute a where a.attrelid = 'public.health_survey_holds'::regclass and a.attnum > 0 and not a.attisdropped;
    if v is distinct from c_holds_shape then
      raise exception '433: public.health_survey_holds exists and is not this migration''s (%)', v; end if;
    raise notice '433: public.health_survey_holds is already this shape; left alone';
  end if;

  -- The new functions: missing, or already this version (left alone).
  for r in select * from (values
      (1, 'health_survey_holds_list()',         c_list_def,   'c3f50d90ba0509935681e4446bcbb21b'),
      (2, 'attach_held_health_survey(uuid,uuid,text)',        c_attach_def, '104370324b701192ba9710d515cc388f'),
      (3, 'create_customer_from_held_survey(uuid,text)', c_create_def, 'd503d8b599f90768c8d909b91cd453e1'),
      (4, 'close_held_health_survey(uuid,text)',         c_close_def,  'ee4789b1d716e4fbf498a5f38e722735')) x(i, fn, def, after_md5)
    order by x.i
  loop
    if md5(r.def) <> r.after_md5 then
      raise exception '433: the text of public.% is not the tested one (md5 %)', r.fn, md5(r.def); end if;
    if to_regprocedure('public.' || r.fn) is null then
      v_new := v_new || r.fn; v_defs := v_defs || r.def;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '433: public.% exists and is not this migration''s version', r.fn;
    else
      raise notice '433: public.% is already this version; left alone', r.fn;
    end if;
  end loop;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('health_survey_holds_list', 'attach_held_health_survey', 'create_customer_from_held_survey',
                       'close_held_health_survey')
     and p.oid::regprocedure::text not in ('health_survey_holds_list()', 'attach_held_health_survey(uuid,uuid,text)',
                                           'create_customer_from_held_survey(uuid,text)', 'close_held_health_survey(uuid,text)');
  if v is not null then
    raise exception '433: another function takes one of these names: %', v; end if;

  -- submit_health_survey: BEFORE (patched) or AFTER (left alone).
  if to_regprocedure(c_fn) is null then raise exception '433: % is missing', c_fn; end if;
  d := pg_get_functiondef(c_fn::regprocedure);
  if md5(d) = c_after then
    raise notice '433: % is already this version; left alone', c_fn;
  elsif md5(d) <> c_before then
    raise exception '433: % is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_fn, md5(d);
  else
    for k in 1 .. cardinality(c_anchors) loop
      n := (length(d) - length(replace(d, c_anchors[k], ''))) / length(c_anchors[k]);
      if n <> 1 then
        raise exception '433: anchor % of % was found % times, not once', k, c_fn, n; end if;
      d := replace(d, c_anchors[k], c_patches[k]);
    end loop;
    if md5(d) <> c_after then
      raise exception '433: the text built for % is not the tested one (md5 %)', c_fn, md5(d); end if;
    v_patch := true;
  end if;
  select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = c_fn::regprocedure;

  -- ads_rpc_no_show_run: BEFORE (patched) or AFTER (left alone).
  if to_regprocedure(c_ns) is null then raise exception '433: % is missing', c_ns; end if;
  d_ns := pg_get_functiondef(c_ns::regprocedure);
  if md5(d_ns) = c_ns_after then
    raise notice '433: % is already this version; left alone', c_ns;
  elsif md5(d_ns) <> c_ns_before then
    raise exception '433: % is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_ns, md5(d_ns);
  else
    n := (length(d_ns) - length(replace(d_ns, c_ns_anchor, ''))) / length(c_ns_anchor);
    if n <> 1 then
      raise exception '433: the anchor of % was found % times, not once', c_ns, n; end if;
    d_ns := replace(d_ns, c_ns_anchor, c_ns_patch);
    if md5(d_ns) <> c_ns_after then
      raise exception '433: the text built for % is not the tested one (md5 %)', c_ns, md5(d_ns); end if;
    v_patch_ns := true;
  end if;
  select coalesce(p.proacl::text, '') into v_acl_ns from pg_proc p where p.oid = c_ns::regprocedure;

  -- ── 2. Install: the table, the new functions, then the two patched ────
  if v_table_new then
    create table public.health_survey_holds (
      survey_id uuid primary key references public.health_surveys(id) on delete cascade,
      reason text not null
        constraint health_survey_holds_reason_check
          check (reason in ('phone_in_use', 'email_in_use', 'phone_and_email_in_use', 'several_name_matches')),
      candidate_customer_ids uuid[] not null default '{}'::uuid[],
      typed_full_name text not null,
      typed_phone text not null,
      typed_email text,
      held_at timestamptz not null default now(),
      resolved_at timestamptz,
      resolved_by uuid references public.profiles(id),
      resolution text
        constraint health_survey_holds_resolution_check check (resolution in ('attached', 'created', 'closed')),
      resolved_customer_id uuid,
      resolution_note text,
      constraint health_survey_holds_resolved_check check ((resolved_at is null) = (resolution is null)));
    comment on table public.health_survey_holds is
      '433: QR health survey forms waiting for staff to attach them to a customer (or make one from them).';
    create index health_survey_holds_waiting_idx on public.health_survey_holds (held_at) where resolved_at is null;
    create index health_survey_holds_typed_phone_idx on public.health_survey_holds (typed_phone);
    alter table public.health_survey_holds enable row level security;
    revoke all on table public.health_survey_holds from public, anon, authenticated, service_role;
    grant select on table public.health_survey_holds to service_role;
  end if;

  for k in 1 .. coalesce(cardinality(v_new), 0) loop
    execute v_defs[k];
    execute format('revoke all on function public.%s from public, anon', v_new[k]);
    execute format('grant execute on function public.%s to authenticated, service_role', v_new[k]);
  end loop;
  if v_patch then
    execute d;
  end if;
  if v_patch_ns then
    execute d_ns;
  end if;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  for r in select * from (values
      ('submit_health_survey(text,jsonb,jsonb,text)', c_after),
      ('ads_rpc_no_show_run(text,text,text,text)',    c_ns_after),
      ('health_survey_holds_list()',         'c3f50d90ba0509935681e4446bcbb21b'),
      ('attach_held_health_survey(uuid,uuid,text)',        '104370324b701192ba9710d515cc388f'),
      ('create_customer_from_held_survey(uuid,text)', 'd503d8b599f90768c8d909b91cd453e1'),
      ('close_held_health_survey(uuid,text)',         'ee4789b1d716e4fbf498a5f38e722735')) x(fn, after_md5)
  loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '433: public.% was installed with an md5 other than the tested one', r.fn; end if;
  end loop;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = c_fn::regprocedure) is distinct from v_acl then
    raise exception '433: the grants of % changed', c_fn; end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = c_ns::regprocedure) is distinct from v_acl_ns then
    raise exception '433: the grants of % changed', c_ns; end if;
  if not has_function_privilege('anon', c_fn, 'execute') then
    raise exception '433: % is no longer callable signed out', c_fn; end if;
  for r in select unnest(array['health_survey_holds_list()', 'attach_held_health_survey(uuid,uuid,text)',
                               'create_customer_from_held_survey(uuid,text)', 'close_held_health_survey(uuid,text)']) as fn
  loop
    if has_function_privilege('anon', 'public.' || r.fn, 'execute')
       or not has_function_privilege('authenticated', 'public.' || r.fn, 'execute') then
      raise exception '433: public.% is not callable by signed-in users alone', r.fn; end if;
  end loop;
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                    '|' order by a.attname) into v
    from pg_attribute a where a.attrelid = 'public.health_survey_holds'::regclass and a.attnum > 0 and not a.attisdropped;
  if v is distinct from c_holds_shape then
    raise exception '433: public.health_survey_holds is not as tested (%)', v; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.health_survey_holds'::regclass)
     or exists (select 1 from pg_policy where polrelid = 'public.health_survey_holds'::regclass)
     or has_table_privilege('anon', 'public.health_survey_holds', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.health_survey_holds', 'select,insert,update,delete')
     or not has_table_privilege('service_role', 'public.health_survey_holds', 'select') then
    raise exception '433: public.health_survey_holds is not reachable as tested'; end if;

  perform set_config('search_path', v_path, true);
end $mig$;
