-- UNDO of 530 (with the user's go-ahead). It puts submit_health_survey back to its text before 530
-- (md5 a65183cd…, as 524 left it), drops public.request_sender() and public.health_survey_tries
-- (its rows, which hold only times, links and sender keys, go with it), and puts the comment on
-- public.referral_sender_salt back to 529's (the salt itself is not touched): the QR health form
-- has no limit per sender, per link or per phone again, takes ip_address, device_info,
-- signed_date and event_name from the payload, takes answers of any size and shape, and a form
-- found by phone and name (or phone and email) for a customer with no survey is theirs at once
-- and fills their empty details again (the security audit's M4 open again). The function's
-- grants stay as they are.
--
-- The check on health_survey_holds.reason goes back to its nine reasons only when no hold has
-- 'existing_customer' (a hold keeps its reason once dealt with); otherwise it is left widened,
-- which refuses nothing, and a notice says so. The forms held as 'existing_customer' while 530
-- was in stay, with no customer, until staff deal with them in To match.
--
-- The page needs no undo first: it checks the same sizes before calling, which only stops what
-- 530 would refuse; its date box shows the day, which the function before 530 also takes.
--
-- It refuses, with nothing changed, unless submit_health_survey is exactly 530's version and the
-- helper and the tries table are as 530 made them (so a later version is never overwritten). One
-- transaction, all or nothing; it waits at most 5 seconds for a lock. The 530 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row (found by
-- its name, 530_the_health_form_has_limits_and_holds_existing_customers) or record this UNDO
-- beside it.
--
-- scripts/survey/tests/forms-as-before-511.sql and scripts/affiliate-signup/tests/referral-limits-529.sql
-- run this inside their own rolled-back transactions where 530 is in.
-- The patch texts below are 530's, the other way round: each 530 text is found exactly once and
-- put back as it was.
do $undo$
declare
  c_sig constant text[] := array[
    'submit_health_survey(text,jsonb,jsonb,text)'];
  c_530 constant text[] := array[
    '6441159a66f5ca4424848710c90f2576'];
  c_before_530 constant text[] := array[
    'a65183cdcb48f2dd883a47c1c7aad7f3'];
  c_helper_md5 constant text := '6a399f5c3c62123def01e0f2fc764234';
  c_tries_cols constant text :=
    'id uuid NO,created_at timestamp with time zone NO,survey_link_id uuid NO,sender_key text YES,outcome text NO';
  c_check_before constant text :=
    'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, ''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text, ''repeat_form''::text, ''customer_has_survey''::text, ''legacy_survey_same_details''::text, ''unreadable_phone_same_name''::text])))';
  c_check_530 constant text :=
    'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, ''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text, ''repeat_form''::text, ''customer_has_survey''::text, ''legacy_survey_same_details''::text, ''unreadable_phone_same_name''::text, ''existing_customer''::text])))';
  c_salt_comment_529 constant text :=
    '529: the secret salt of referral_signup_events.sender_key (sha256 of it and the sender''s address), made at random when 529 ran. Never in a file; no API role reads it (row level security on, no policy, no grant). affiliate_referral_signup reads it; without it, it refuses.';
  c_fn constant int[] := array[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];
  c_anchor constant text[] := array[
-- 1 the declarations: the sender, the device, the event, what is wrong, the forms kept today
$a$  -- 524: an old customer with this name has a phone that cannot be read but could be this one.
  v_unreadable boolean := false;
begin
$a$,
-- 2 the checks, the limits per sender and per link, and 3 forms a day per phone
$a$  v_norm := public.normalize_customer_phone(v_phone);

  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm, 0));
$a$,
-- 3 a customer found by phone and name, or by phone and email, waits for staff
$a$    -- Fill ONLY currently-empty, safe fields. NEVER touch full_name, phone, or
    -- any referral attribution (referred_by / referred_at / referral_source /
    -- referral_code_used).
    -- 485 (the Owner, 2 Nov 2026): nor the email of a record that has a portal
    -- login or an affiliate record: 484's proof (d) takes a login whose
    -- verified email is its record's as proven, so a form must not put an
    -- email there. The form keeps the email typed; staff may copy it.
    -- 511: nor the email of any other customer who was there before this
    -- form. Since 508 a portal login is shown its record only once its link
    -- is proven, and one proof is that the login's verified email is the
    -- record's (484's proof (d)). The email on a form is whatever its sender
    -- typed, so it must not become the record's. It goes only on a customer
    -- this form itself makes (below). Staff add an email in Edit customer.
    update public.customers
       set date_of_birth     = coalesce(date_of_birth, nullif(p_payload->>'date_of_birth','')::date),
           gender            = coalesce(gender, v_gender),
           occupation        = coalesce(occupation, nullif(trim(p_payload->>'occupation'),'')),
           source_option_id  = coalesce(source_option_id, v_src.id),
           source_label      = coalesce(source_label, v_src.label),
           source_details    = coalesce(source_details, v_src_details),
           source_updated_at = case when source_option_id is null then now() else source_updated_at end,
           updated_at        = now()
     where id = v_cust_id
       -- 468 (the Owner, 24 Oct 2026): only when the name found them. A form
       -- found by the phone and the email alone fills none of the customer's
       -- details; the form keeps what was typed.
       and v_name_match is distinct from 'phone_and_email';
$a$,
-- 4 a consultant's record is no longer filled from the form itself
$a$  if v_into is not null then
    -- 419 (Q10): the customer's own answers go into the consultant's record
    -- they had not signed; the consultant's work stays.
$a$,
-- 5 the record's event (the link's first)
$a$    v_form.event_name := coalesce(nullif(trim(p_payload->>'event_name'),''), v_l.event_name);
$a$,
-- 6 the record's date, address and device (the server's)
$a$    v_form.signed_date := coalesce(nullif(p_payload->>'signed_date','')::date, public.sg_today());
    v_form.ip_address := nullif(p_payload->>'ip_address','');
    v_form.device_info := nullif(p_payload->>'device_info','');
$a$,
-- 7 the form's event (the link's first)
$a$      v_no, v_l.store_id, v_l.id, v_cust_id, coalesce(nullif(trim(p_payload->>'event_name'),''), v_l.event_name),
$a$,
-- 8 the form's date, address and device (the server's)
$a$      coalesce(nullif(p_payload->>'signed_date','')::date, public.sg_today()),
      nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''),
$a$,
-- 9 the audit row's address and device (the request's)
$a$          'health_survey', v_l.store_id,
          nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''));
$a$,
-- 10 the missing-PDF audit row's address and device (the request's)
$a$            'health_survey', v_l.store_id,
            nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''));
$a$,
-- 11 the form kept is counted for the sender and the link
$a$  return jsonb_build_object('success', true, 'survey_no', v_no, 'survey_id', v_id);
$a$];
  c_new constant text[] := array[
-- 1 the declarations: the sender, the device, the event, what is wrong, the forms kept today
$n$  -- 524: an old customer with this name has a phone that cannot be read but could be this one.
  v_unreadable boolean := false;
  -- 530 (security audit of 17 Nov 2026, M4): the request's address and its sender key
  -- (request_sender), the device the request names (its user-agent header), the event the
  -- form is for, what is wrong with the answers (if anything), a date of birth as checked,
  -- the forms kept today under this phone, and the symptoms already ticked.
  v_ip inet; v_sender text; v_device text; v_event text; v_bad text; v_dob date;
  v_kept int; v_opt uuid; v_opt_ids uuid[] := '{}'::uuid[];
begin
$n$,
-- 2 the checks, the limits per sender and per link, and 3 forms a day per phone
$n$  v_norm := public.normalize_customer_phone(v_phone);

  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;

  -- 530 (security audit of 17 Nov 2026, M4; the page checks the same before it calls): every
  -- answer has a size and a shape, well above the longest production has seen. Refused with a
  -- plain message (SURVEY_INPUT(<field>): ...), raised, before anything on file is read, so a
  -- refused try reads and keeps nothing (and is not counted by the limits below).
  v_bad := case
    when jsonb_typeof(p_payload) <> 'object' or octet_length(p_payload::text) > 150000 then
      'SURVEY_INPUT(form): This form is too large to send. Please shorten your answers and try again.'
    when char_length(v_name) > 100 then
      'SURVEY_INPUT(first_name): Please shorten your name: your first and last name together can be at most 100 characters.'
    when v_name ~ '[\u0001-\u001f\u007f-\u009f]' then
      'SURVEY_INPUT(first_name): Please enter your name without special characters.'
    when char_length(v_email) > 254 then
      'SURVEY_INPUT(email): Please enter an email address of at most 254 characters.'
    when v_email ~ '[\u0001-\u001f\u007f-\u009f]' then
      'SURVEY_INPUT(email): Please enter a valid email address, like name@example.com.'
    when v_sex is not null and v_sex not in ('male', 'female', 'other') then
      'SURVEY_INPUT(sex): Please choose Female or Male, or leave it blank.'
    when char_length(btrim(p_payload->>'occupation')) > 100 then
      'SURVEY_INPUT(occupation): Please shorten your occupation to at most 100 characters.'
    when (p_payload->>'occupation') ~ '[\u0001-\u001f\u007f-\u009f]' then
      'SURVEY_INPUT(occupation): Please enter your occupation without special characters.'
    when char_length(btrim(p_payload->>'event_name')) > 100 then
      'SURVEY_INPUT(event_name): Please shorten the event name to at most 100 characters.'
    when (p_payload->>'event_name') ~ '[\u0001-\u001f\u007f-\u009f]' then
      'SURVEY_INPUT(event_name): Please enter the event name without special characters.'
    when char_length(btrim(p_payload->>'source_details')) > 200 then
      'SURVEY_INPUT(source_details): Please shorten these details to at most 200 characters.'
    when (p_payload->>'source_details') ~ '[\u0001-\u001f\u007f-\u009f]' then
      'SURVEY_INPUT(source_details): Please enter these details without special characters.'
    when char_length(btrim(p_payload->>'treatment_list')) > 1000 then
      'SURVEY_INPUT(treatment_list): Please shorten the list of treatments to at most 1000 characters.'
    when (p_payload->>'treatment_list') ~ '[\u0001-\u001f\u007f-\u009f]' then
      'SURVEY_INPUT(treatment_list): Please enter the list of treatments without special characters.'
    when char_length(btrim(p_payload->>'others_text')) > 1000 then
      'SURVEY_INPUT(others_text): Please shorten "Others" to at most 1000 characters.'
    when (p_payload->>'others_text') ~ '[\u0001-\u001f\u007f-\u009f]' then
      'SURVEY_INPUT(others_text): Please enter "Others" without special characters.'
    when case when nullif(btrim(p_payload->>'age'), '') is null then false
              when btrim(p_payload->>'age') !~ '^[0-9]{1,3}$' then true
              else btrim(p_payload->>'age')::int > 120 end then
      'SURVEY_INPUT(age): Please enter an age from 0 to 120, or leave it blank.'
    when char_length(p_payload->>'signature_data') > 100000 then
      'SURVEY_INPUT(signature_data): Your signature is too large to save. Please clear it and sign again.'
    when (p_payload->>'signature_data') !~ '^data:image/png;base64,[A-Za-z0-9+/]+={0,2}$' then
      'SURVEY_INPUT(signature_data): Your signature could not be read. Please clear it and sign again.'
    when char_length(p_pdf_base64) > 4500000 then
      'SURVEY_INPUT(signature_data): Your signed form is too large to save. Please clear your signature and sign again.'
    when p_pdf_base64 <> '' and p_pdf_base64 !~ '^JVBERi0[A-Za-z0-9+/]*={0,2}$' then
      'SURVEY_INPUT(form): Your signed form could not be prepared. Please try again, or let our consultant know.'
  end;
  -- A date of birth: a real date from 1 January 1900 up to today in Singapore.
  if v_bad is null and nullif(p_payload->>'date_of_birth', '') is not null then
    begin
      v_dob := case when (p_payload->>'date_of_birth') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                    then (p_payload->>'date_of_birth')::date end;
    exception when others then v_dob := null;
    end;
    if v_dob is null or v_dob < date '1900-01-01' or v_dob > public.sg_today() then
      v_bad := 'SURVEY_INPUT(date_of_birth): Please enter a real date of birth from 1900 that is not in the future.';
    end if;
  end if;
  -- The symptoms: none, or a list of the options the page shows (each active, each once), each
  -- duration at most 60 characters with no special characters.
  if v_bad is null and p_symptoms is not null then
    if jsonb_typeof(p_symptoms) <> 'array'
       or jsonb_array_length(p_symptoms) > (select count(*) from public.health_symptom_options o where o.is_active) then
      v_bad := 'SURVEY_INPUT(symptoms): The list of symptoms has changed. Please reload the page and tick your symptoms again.';
    else
      for v_sym in select * from jsonb_array_elements(p_symptoms) loop
        v_opt := case when jsonb_typeof(v_sym) = 'object'
                       and (v_sym->>'option_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                      then (v_sym->>'option_id')::uuid end;
        if v_opt is null or not exists (select 1 from public.health_symptom_options o where o.id = v_opt and o.is_active) then
          v_bad := 'SURVEY_INPUT(symptoms): The list of symptoms has changed. Please reload the page and tick your symptoms again.';
          exit;
        end if;
        if v_opt = any (v_opt_ids) then
          v_bad := 'SURVEY_INPUT(symptoms): Please tick each symptom only once.';
          exit;
        end if;
        v_opt_ids := v_opt_ids || v_opt;
        if char_length(btrim(v_sym->>'duration_text')) > 60 or (v_sym->>'duration_text') ~ '[\u0001-\u001f\u007f-\u009f]' then
          v_bad := 'SURVEY_INPUT(symptoms): Please keep how long you have had each symptom to at most 60 characters, without special characters.';
          exit;
        end if;
      end loop;
    end if;
  end if;
  if v_bad is not null then raise exception '%', v_bad; end if;

  -- 530: the event the form is for: the link's, when it has one (the page shows no Event box
  -- then), else the one typed. The address and the device are the request's own (the
  -- payload's ip_address and device_info are ignored): the address Cloudflare puts in
  -- cf-connecting-ip, and the user-agent header without control characters, at most 250
  -- characters.
  v_event := case when nullif(btrim(v_l.event_name), '') is not null then v_l.event_name
                  else nullif(trim(p_payload->>'event_name'), '') end;
  select r.address, r.sender_key into v_ip, v_sender from public.request_sender() r;
  begin
    v_device := nullif(btrim(left(regexp_replace(current_setting('request.headers', true)::jsonb ->> 'user-agent',
                                                 '[\u0001-\u001f\u007f-\u009f]', ' ', 'g'), 250)), '');
  exception when others then v_device := null;
  end;

  -- 530 (the user, 19 Nov 2026, "10 per connection + 60 per link"): one connection sends at
  -- most 10 forms an hour, one QR link takes at most 60 an hour, counting every form kept and
  -- every form dropped by the day's limit for a phone (below); refused past either, raised so
  -- the page keeps the answers on screen and says to try again later. The sender is
  -- request_sender's key (cf-connecting-ip only, an IPv6 address as its /64, a salted sha256,
  -- as 529 counts the referral page's senders); no such header (a call from inside the
  -- database): no sender, and only the link's limit applies. Each sender's and each link's
  -- forms wait for each other, so the counts are exact; then the phone's lock, as before.
  if v_sender is not null then
    perform pg_advisory_xact_lock(hashtextextended('health-survey-sender:' || v_sender, 0));
    if (select count(*) from public.health_survey_tries t
         where t.sender_key = v_sender and t.created_at > now() - interval '1 hour') >= 10 then
      raise exception 'SURVEY_BUSY: Many forms have been sent from this connection in the last hour. Please try again later, or ask our consultant for help.';
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('health-survey-link:' || v_l.id::text, 0));
  if (select count(*) from public.health_survey_tries t
       where t.survey_link_id = v_l.id and t.created_at > now() - interval '1 hour') >= 60 then
    raise exception 'SURVEY_BUSY: This form link has received many forms in the last hour. Please try again later, or ask our consultant for help.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm, 0));

  -- 530 (the user, 19 Nov 2026, "3 a day per phone"): from the 4th form in one Singapore day
  -- under one phone (counting the forms kept through any link that day: the rows this form
  -- inserted, with a link and no staff member as their maker; a consultant's record a form was
  -- signed into is not counted again), nothing more is kept: no form, no hold, no audit row.
  -- The sender is thanked as for any form, without a survey number (none was made); the try is
  -- counted for the sender and the link.
  select count(*) into v_kept from public.health_surveys s
   where s.phone = v_norm and s.survey_link_id is not null and s.created_by is null
     and s.submitted_at >= (public.sg_today()::timestamp at time zone 'Asia/Singapore');
  if v_kept >= 3 then
    insert into public.health_survey_tries (survey_link_id, sender_key, outcome) values (v_l.id, v_sender, 'dropped');
    delete from public.health_survey_tries where created_at < now() - interval '1 day';
    return jsonb_build_object('success', true);
  end if;
$n$,
-- 3 a customer found by phone and name, or by phone and email, waits for staff
$n$    -- 530 (security audit of 17 Nov 2026, M4; the user, 19 Nov 2026, "Hold for staff"): a
    -- form found by its phone and name, or by its phone and email (468), is no longer theirs
    -- by itself: anyone with a link who knew a customer's phone and name made it their
    -- declaration and filled their empty date of birth, gender, occupation and source. It is
    -- kept with no customer and waits under To match with that customer as the candidate
    -- (existing_customer); it fills none of their details and goes into no consultant's record
    -- they have not signed (419's Q10). Staff who have checked it is the same person attach
    -- it (attach_held_health_survey: their empty details are filled from it then, and a record
    -- they have not signed takes its answers). A customer with a survey: as before (above).
    if v_hold is null then
      v_hold := 'existing_customer';
      v_candidates := array[v_cust_id];
      v_cust_id := null; v_matched := false; v_into := null;
    end if;
$n$,
-- 4 a consultant's record is no longer filled from the form itself
$n$  if v_into is not null then
    -- 530: no longer reached from the form (a customer found waits for staff, above); staff
    -- attaching a held form fill the record (attach_held_health_survey).
    -- 419 (Q10): the customer's own answers go into the consultant's record
    -- they had not signed; the consultant's work stays.
$n$,
-- 5 the record's event (the link's first)
$n$    v_form.event_name := v_event;
$n$,
-- 6 the record's date, address and device (the server's)
$n$    v_form.signed_date := public.sg_today();
    v_form.ip_address := host(v_ip);
    v_form.device_info := v_device;
$n$,
-- 7 the form's event (the link's first)
$n$      v_no, v_l.store_id, v_l.id, v_cust_id, v_event,
$n$,
-- 8 the form's date, address and device (the server's)
$n$      -- 530 ("Day it arrives"): the Singapore date the form arrives, whatever the page sent;
      -- the request's address and device, not the payload's.
      public.sg_today(),
      host(v_ip), v_device,
$n$,
-- 9 the audit row's address and device (the request's)
$n$          'health_survey', v_l.store_id,
          host(v_ip), v_device);
$n$,
-- 10 the missing-PDF audit row's address and device (the request's)
$n$            'health_survey', v_l.store_id,
            host(v_ip), v_device);
$n$,
-- 11 the form kept is counted for the sender and the link
$n$  -- 530: the form was kept; counted for the sender's and the link's limits (above). Tries
  -- older than a day are dropped: the limits read the last hour only.
  insert into public.health_survey_tries (survey_link_id, sender_key, outcome) values (v_l.id, v_sender, 'kept');
  delete from public.health_survey_tries where created_at < now() - interval '1 day';
  return jsonb_build_object('success', true, 'survey_no', v_no, 'survey_id', v_id);
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  v_check text;
  i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception 'UNDO 530: public.% is missing', c_sig[i]; end if;
    v_def[i] := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(v_def[i]) <> c_530[i] then
      raise exception 'UNDO 530: public.% is not 530''s version (md5 %). Nothing changed.', c_sig[i], md5(v_def[i]); end if;
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
  end loop;
  if to_regprocedure('public.request_sender()') is null
     or md5(pg_get_functiondef('public.request_sender()'::regprocedure)) <> c_helper_md5 then
    raise exception 'UNDO 530: public.request_sender() is missing or not 530''s version. Nothing changed.'; end if;
  if to_regclass('public.health_survey_tries') is null
     or (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
           from information_schema.columns where table_schema = 'public' and table_name = 'health_survey_tries') is distinct from c_tries_cols then
    raise exception 'UNDO 530: public.health_survey_tries is missing or not as 530 made it. Nothing changed.'; end if;
  -- Nothing else may use the helper or the table (a later migration would have to be undone first).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.prokind in ('f', 'p')
                and p.oid not in ('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure,
                                  'public.request_sender()'::regprocedure)
                and pg_get_functiondef(p.oid) ~ '(request_sender|health_survey_tries)') then
    raise exception 'UNDO 530: another function uses public.request_sender or public.health_survey_tries; undo that first. Nothing changed.'; end if;
  v_check := (select pg_get_constraintdef(c.oid) from pg_constraint c
               where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check');
  if v_check is distinct from c_check_530 then
    raise exception 'UNDO 530: health_survey_holds_reason_check is not 530''s (%). Nothing changed.', v_check; end if;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 530: patch % does not find 530''s text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before_530[i] then
      raise exception 'UNDO 530: the text put back for public.% is not the one before 530 (md5 %). Nothing changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Put the form back (it no longer calls the helper or writes the tries), then drop both,
  --    the salt's comment back, and the reasons back when no hold has the new one
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  drop function public.request_sender();
  drop table public.health_survey_tries;
  execute format('comment on table public.referral_sender_salt is %L', c_salt_comment_529);
  if exists (select 1 from public.health_survey_holds where reason = 'existing_customer') then
    raise notice 'UNDO 530: % hold(s) have the reason existing_customer, so health_survey_holds_reason_check is left widened (it refuses nothing)',
      (select count(*) from public.health_survey_holds where reason = 'existing_customer');
  else
    alter table public.health_survey_holds drop constraint health_survey_holds_reason_check;
    alter table public.health_survey_holds add constraint health_survey_holds_reason_check
      check (reason = any (array['phone_in_use', 'email_in_use', 'phone_and_email_in_use', 'several_name_matches',
                                 'phone_and_email_customer_has_survey', 'repeat_form', 'customer_has_survey',
                                 'legacy_survey_same_details', 'unreadable_phone_same_name']));
  end if;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before_530[i] then
      raise exception 'UNDO 530: public.% was put back with an md5 other than the one before 530', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception 'UNDO 530: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  if to_regprocedure('public.request_sender()') is not null or to_regclass('public.health_survey_tries') is not null then
    raise exception 'UNDO 530: public.request_sender() or public.health_survey_tries is still there'; end if;
  v_check := (select pg_get_constraintdef(c.oid) from pg_constraint c
               where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check');
  if v_check is distinct from c_check_before and v_check is distinct from c_check_530 then
    raise exception 'UNDO 530: health_survey_holds_reason_check is neither the one before 530 nor 530''s after the undo'; end if;
  if obj_description('public.referral_sender_salt'::regclass, 'pg_class') is distinct from c_salt_comment_529 then
    raise exception 'UNDO 530: the comment on public.referral_sender_salt is not 529''s after the undo'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
