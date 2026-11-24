-- 530_the_health_form_has_limits_and_holds_existing_customers.sql
--
-- THE QR HEALTH FORM LIMITS EACH SENDER, EACH LINK AND EACH PHONE, HOLDS A FORM FOR AN EXISTING
-- CUSTOMER FOR STAFF, DATES IT THE DAY IT ARRIVES, AND REFUSES ODD INPUT
--
--   From the security audit of 17 Nov 2026 (finding M4).
--   The BEFORE md5 and the relied-on md5s below are those of production after 529 (the local
--   copy of 19 Nov 2026). If production differs when this is applied, it refuses and changes
--   nothing.
--   (The number 530 is this file's name and its errors' prefix; if it changes at commit, change
--   it there, in the 530 comments it writes into submit_health_survey and request_sender (and so
--   their md5s, also in scripts/survey/undo-530.sql and in the suites that know them), and in
--   the name and path of its suite.)
--
-- WHAT WAS WRONG
--
--   The public QR health form /survey/<token> (src/pages/PublicSurveyPage.tsx) calls
--   submit_health_survey(text,jsonb,jsonb,text), which can be called signed out (the anon key)
--   and runs as its owner.
--   * No limit at all: anyone with a link could send forms without end, and each is kept (a
--     form, often a hold for staff, an audit row, a PDF).
--   * No caps on the answers: any length of name, email, occupation, event, details, treatments,
--     others and durations, any characters; any number of symptoms, the same one twice; any text
--     as the signature; the PDF up to 8,000,000 characters of anything.
--   * The payload chose the record's ip_address, device_info, signed_date and event_name.
--   * A form whose phone and name (or, since 468, phone and email) matched ONE existing customer
--     with no survey became that customer's declaration at once, and filled their empty date of
--     birth, gender, occupation and source; one with a consultant's record they had not signed
--     went into that record (419's Q10). So anyone with a QR link who knew a customer's phone
--     and name could sign a health declaration as them and set their details.
--
-- THE RULE (the user, 19 Nov 2026)
--
--   1. "10 per connection + 60 per link": one connection at most 10 forms an hour; one QR link at
--      most 60 forms an hour. Past either, the form says to try again later and the answers stay
--      on screen. The connection is the sender as in 529: cf-connecting-ip only, an IPv6 address
--      as its /64, a salted sha256 with the existing salt.
--   2. "Hold for staff": a form whose phone and name, or phone and email (468), matches an
--      existing customer waits under To match (health_survey_holds) with that customer as the
--      candidate. The public form copies nothing onto the record: no date of birth, gender,
--      occupation or source; no customer_id on the form; no automatic signing into a
--      consultant's unsigned record (419 Q10). Staff attaching it after checking is the intended
--      way. New customers (no match, phone and email not in use) are still made by the form.
--   3. "3 a day per phone": from the 4th form in one Singapore day for the same normalized
--      phone, counting forms kept on any link, nothing more is kept and the sender still sees
--      the thank-you. Such dropped tries still count toward the sender's 10 an hour.
--   4. "Day it arrives": the signed date is always the Singapore date the form arrives (server
--      side, ignoring the payload's). The page's date box shows that day and cannot be changed,
--      so the PDF built in the browser carries the same day.
--   And (told to the user, no objection): caps on every answer well above production's longest,
--   no control characters, the symptoms only the active options, each once; an age of 0-120 and
--   a date of birth from 1900 to today; the signature a PNG of at most 100,000 characters; the
--   PDF a PDF of at most 4,500,000 characters; the address and the device the request's own;
--   a link's event name over the one typed.
--
-- WHAT THIS DOES
--
--   * public.request_sender(), new, internal (no grant to public, anon, authenticated or the
--     service role; a function running as the owner calls it): (address inet, sender_key text)
--     of the request. address: the request header cf-connecting-ip (never x-forwarded-for), an
--     IPv4 address written as IPv6 as the IPv4 address; null without a single address there.
--     sender_key: the hex sha256 of public.referral_sender_salt's salt and the address (an IPv6
--     address as its /64), exactly as 529 keys referral_signup_events.sender_key, so one sender
--     has one key on both public forms. No salt: it refuses. 529's affiliate_referral_signup is
--     unchanged (it keeps its own copy of these lines; it could call this one later).
--   * public.health_survey_tries, new: one row for each form the QR form kept ('kept') or
--     dropped by the day's limit for a phone ('dropped'): when, the link, and the sender's key
--     (never an address, never a phone; a check allows 64 hex characters or null). Row level
--     security on, no policy, every privilege revoked from public, anon, authenticated and the
--     service role: only the owner (the form) reads and writes it. Rows older than a day are
--     deleted by the form as it writes (the limits read the last hour). Three indexes: by
--     sender and time, by link and time, by time.
--   * public.referral_sender_salt: its comment says it serves both forms now. Its shape (columns,
--     checks, one row, row level security with no policy, the owner's alone) is checked, not
--     changed; its salt is kept.
--   * health_survey_holds: the reasons check allows one more, 'existing_customer'.
--   * submit_health_survey, in this order (refusals are raised, as before, so the page keeps the
--     answers; nothing on file is read before them):
--       1. the link, the required answers and the source, as before;
--       2. new: the answers' sizes and shapes (SURVEY_INPUT(<field>): a plain message): the name
--          (first and last together) at most 100 characters, the email at most 254, the
--          occupation and the event at most 100, the source's details at most 200, the
--          treatments and Others at most 1000, no control characters in any of them; sex
--          female, male, other or blank; age blank or 0-120; date of birth blank or a real date
--          from 1900-01-01 to today in Singapore; the symptoms at most as many as the active
--          options, each an active option, none twice, each duration at most 60 characters with
--          no control characters; the signature 'data:image/png;base64,' and base64, at most
--          100,000 characters; the PDF blank (the page could not build it, as before) or base64
--          starting JVBERi0 (%PDF-), at most 4,500,000 characters; the whole payload a JSON
--          object of at most 150,000 bytes;
--       3. new: the sender (request_sender) and its lock, then its limit: 10 forms kept or
--          dropped from it in the last hour -> SURVEY_BUSY: try again later; then the link's lock
--          and limit: 60 in the last hour -> SURVEY_BUSY: try again later. No sender (a call with
--          no cf-connecting-ip, from inside the database): only the link's limit;
--       4. the phone's lock, as before; then new: 3 forms already kept today (Singapore) under
--          this phone through any link (the rows the form inserted; a consultant's record a form
--          was signed into is not counted again) -> nothing kept (no form, no hold, no audit row), the try
--          recorded ('dropped'), and the reply {success: true} (no survey number, as none was
--          made; the page thanks the sender either way);
--       5. matching as before; a form found by phone and name, or by phone and email, for a
--          customer with no survey, or with a consultant's record they have not signed, is now
--          held ('existing_customer', that customer the candidate): kept with no customer,
--          nothing filled on the customer, nothing signed into a record. One whose customer has
--          a survey waits as before (customer_has_survey, phone_and_email_customer_has_survey);
--          every other hold and a new customer as before;
--       6. the form and its audit rows: the event is the link's when it has one, else the one
--          typed; signed_date the Singapore date it arrives (sg_today()); ip_address the
--          request's cf-connecting-ip; device_info the request's user-agent header without
--          control characters, at most 250 characters (the payload's ip_address, device_info and
--          signed_date are ignored); then the try recorded ('kept'). The reply as before:
--          {success, survey_no, survey_id}.
--     Its grants (signed out, signed in, the service role) are unchanged.
--   * What staff attaching a held form copies (attach_held_health_survey, unchanged): onto the
--     customer, their EMPTY date of birth, gender (female/male), occupation and source (option,
--     label, details, with the source's date); never their name, phone or email. Then the form
--     takes the customer (and their name parts) - or, when the customer has a consultant's
--     record they have not signed, the form's answers, symptoms and signed PDF go into that
--     record (health_survey_sign_into_record) and the form stays with no customer, marked
--     attached. Refused for a customer who already has a signed survey.
--
-- WHAT THIS LEAVES ALONE
--
--   * The staff paths: attach_held_health_survey, create_customer_from_held_survey,
--     close_held_health_survey, health_survey_holds_list, health_survey_sign_into_record.
--   * 529's affiliate_referral_signup and referral_signup_events (the salt's comment aside).
--   * The forms and holds already there; every audit row. Forms held before 530 keep their
--     reasons; forms attached before 530 stay attached.
--   * Errors raised before 530 stay as they were (a link not recognised, deactivated or
--     expired; name, phone, email, signature or source missing; CUSTOMER_PHONE_REVIEW).
--
-- UNDO
--
--   scripts/survey/undo-530.sql (it refuses unless submit_health_survey is 530's version and the
--   helper and the tries table are as 530 made them): the function is put back exactly as it was
--   (each patch reversed), request_sender and health_survey_tries are dropped, the salt's comment
--   is put back, and the reasons check goes back to its nine reasons when no hold has
--   'existing_customer' (else it is left widened, which refuses nothing, with a notice, and 530
--   runs again over it). The
--   forms held as 'existing_customer' while 530 was in stay held, for staff. The page needs no
--   undo: it checks the same rules before calling. A later migration changing
--   submit_health_survey must pin 530's AFTER md5. scripts/affiliate-signup/undo-529.sql
--   refuses while 530 is in (request_sender reads 529's salt): undo 530 first.
--
-- NO SELF-TEST INSIDE; the suite is scripts/survey/tests/health-form-limits-530.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions relied on, as tested: those the patched form calls (the phone, the names, the
  -- emails, the identity check whose AMBIGUOUS_CUSTOMER_MATCH it catches, the record a form goes
  -- into, the date), the staff paths a held form goes on to (the list, attach, a new customer
  -- from it), and 529's sign-up, whose sender keys request_sender makes the same way.
  c_relied constant text[] := array[
    'normalize_customer_phone(text)',
    'require_resolved_customer_identity(text,text)',
    'customer_phone_name_matches(text,text)',
    'customer_names_match(text,text)',
    'customer_email_match_key(text)',
    'normalize_customer_match_name(text)',
    'join_person_name(text,text)',
    'inspect_customer_phone(text,text)',
    'sg_today()',
    'health_survey_sign_into_record(uuid,health_surveys,jsonb,text)',
    'health_survey_holds_list()',
    'attach_held_health_survey(uuid,uuid,text)',
    'create_customer_from_held_survey(uuid,text)',
    'affiliate_referral_signup(text,text,text,text,text,text)'];
  c_relied_md5 constant text[] := array[
    'b2bfac910e0c9eff402ba44e19750bee',
    '5bde1a418363442ec27e2944442f5874',
    '1bdf8322972b6671b7cbb08bc8211f8a',
    'ef1af52e4888cefb6037a2291f4e011d',
    'be468815c9626fff1728e2cfcd484b66',
    '0572764712e179dc606c66f9f3dbaa03',
    '50b6cd36ab0fd14be3acd549fec5edb8',
    '6672c4d1963996f3b601896f4a55916e',
    '1c1289f18e24d8370e9a6364c9c06fca',
    'ac2bbd3742f3b4364b289ddd29715215',
    '0487502f033b56452140c81e108a8ebc',
    '55b632c7e9289cb267516a26af97387b',
    '733db65d708db7c64b5c4de03493d409',
    '00d528c6f4cc9240b2cf2f82ea2bd487'];
  -- The function patched.
  c_sig constant text[] := array[
    'submit_health_survey(text,jsonb,jsonb,text)'];
  c_before constant text[] := array[
    'a65183cdcb48f2dd883a47c1c7aad7f3'];
  c_after constant text[] := array[
    '6441159a66f5ca4424848710c90f2576'];
  -- Its grants, before and after (signed out, signed in, the service role, as before).
  c_acl constant text := 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  -- The new helper: its text, its md5 and its grants (the owner's alone).
  c_helper_sig constant text := 'request_sender()';
  c_helper constant text := $fn$CREATE OR REPLACE FUNCTION public.request_sender(OUT address inet, OUT sender_key text)
 RETURNS record
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_salt text;
begin
  -- 530 (security audit of 17 Nov 2026, M4): who sent this request, for the limits per sender
  -- of the public forms (the QR health form since 530; the referral page counts the same way
  -- inside affiliate_referral_signup, 529, and could call this instead). Internal: no API role
  -- may call it; a function running as the owner does.
  --
  -- address: the address Cloudflare, in front of Supabase, puts in the request header
  -- cf-connecting-ip (PostgREST hands the headers over in the setting request.headers), never
  -- x-forwarded-for, whose first entry the sender writes. An IPv4 address written as IPv6
  -- (::ffff:a.b.c.d) is the IPv4 address. No such header, or one that is not a single address
  -- (a call from inside the database, a suite): null.
  -- sender_key: who sent it, as the hex sha256 of the secret salt (public.referral_sender_salt,
  -- which no API role reads) and the address; an IPv6 address counts as its /64 (one home or
  -- phone network gets a whole /64). Exactly as 529 keys referral_signup_events.sender_key, so
  -- one sender has one key on both forms. Null when there is no address. No salt: this refuses,
  -- rather than count nobody.
  select s.salt into v_salt from public.referral_sender_salt s where s.id;
  if v_salt is null or v_salt !~ '^[0-9a-f]{64}$' then
    raise exception '530: the sender salt (public.referral_sender_salt) is missing, so no sender can be counted. Run 529 again.';
  end if;
  begin
    address := nullif(btrim(current_setting('request.headers', true)::jsonb ->> 'cf-connecting-ip'), '')::inet;
    if family(address) = 6 and address <<= '::ffff:0.0.0.0/96'::inet then
      address := regexp_replace(host(address), '^::ffff:', '', 'i')::inet;
    end if;
    if masklen(address) <> (case family(address) when 4 then 32 else 128 end) then address := null; end if;
  exception when others then address := null;
  end;
  sender_key := case family(address)
    when 4 then encode(sha256(convert_to(v_salt || '|' || host(address), 'UTF8')), 'hex')
    when 6 then encode(sha256(convert_to(v_salt || '|' || host(network(set_masklen(address, 64))) || '/64', 'UTF8')), 'hex')
  end;
end
$function$
$fn$;
  c_helper_md5 constant text := '6a399f5c3c62123def01e0f2fc764234';
  c_helper_acl constant text := 'postgres=X/postgres';
  -- The new tries table, as 530 makes it.
  c_tries_cols constant text :=
    'id uuid NO,created_at timestamp with time zone NO,survey_link_id uuid NO,sender_key text YES,outcome text NO';
  c_tries_idx constant text[] := array[
    'CREATE INDEX idx_health_survey_tries_link_time ON public.health_survey_tries USING btree (survey_link_id, created_at)',
    'CREATE INDEX idx_health_survey_tries_sender_time ON public.health_survey_tries USING btree (sender_key, created_at) WHERE (sender_key IS NOT NULL)',
    'CREATE INDEX idx_health_survey_tries_time ON public.health_survey_tries USING btree (created_at)',
    'CREATE UNIQUE INDEX health_survey_tries_pkey ON public.health_survey_tries USING btree (id)'];
  c_tries_con constant text[] := array[
    'health_survey_tries_outcome_check CHECK ((outcome = ANY (ARRAY[''kept''::text, ''dropped''::text])))',
    'health_survey_tries_pkey PRIMARY KEY (id)',
    'health_survey_tries_sender_key_is_a_hash CHECK (((sender_key IS NULL) OR (sender_key ~ ''^[0-9a-f]{64}$''::text)))'];
  c_tries_acl constant text := 'postgres=arwdDxtm/postgres';
  -- The hold reasons, before 530 and after.
  c_check_before constant text :=
    'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, ''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text, ''repeat_form''::text, ''customer_has_survey''::text, ''legacy_survey_same_details''::text, ''unreadable_phone_same_name''::text])))';
  c_check_after constant text :=
    'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, ''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text, ''repeat_form''::text, ''customer_has_survey''::text, ''legacy_survey_same_details''::text, ''unreadable_phone_same_name''::text, ''existing_customer''::text])))';
  -- The salt table, as 529 made it (its shape is checked, never changed), and its comment
  -- before 530 and after.
  c_salt_cols constant text := 'id boolean NO,salt text NO,created_at timestamp with time zone NO';
  c_salt_con constant text[] := array[
    'referral_sender_salt_is_hex CHECK ((salt ~ ''^[0-9a-f]{64}$''::text))',
    'referral_sender_salt_one_row CHECK (id)',
    'referral_sender_salt_pkey PRIMARY KEY (id)'];
  c_salt_acl constant text := 'postgres=arwdDxtm/postgres';
  c_salt_comment_before constant text :=
    '529: the secret salt of referral_signup_events.sender_key (sha256 of it and the sender''s address), made at random when 529 ran. Never in a file; no API role reads it (row level security on, no policy, no grant). affiliate_referral_signup reads it; without it, it refuses.';
  c_salt_comment_after constant text :=
    '529: the secret salt of the public forms'' sender keys (sha256 of it and the sender''s address; an IPv6 address as its /64), made at random when 529 ran. Never in a file; no API role reads it (row level security on, no policy, no grant). affiliate_referral_signup reads it for referral_signup_events.sender_key (529), and 530''s request_sender for health_survey_tries.sender_key (the QR health form); without it, both refuse.';
  -- Eleven patches, each found exactly once in the function:
  --   1. the declarations: the sender, the device, the event, what is wrong, the forms kept today
  --   2. the checks, the limits per sender and per link, and 3 forms a day per phone
  --   3. a customer found by phone and name, or by phone and email, waits for staff
  --   4. a consultant's record is no longer filled from the form itself
  --   5. the record's event (the link's first)
  --   6. the record's date, address and device (the server's)
  --   7. the form's event (the link's first)
  --   8. the form's date, address and device (the server's)
  --   9. the audit row's address and device (the request's)
  --   10. the missing-PDF audit row's address and device (the request's)
  --   11. the form kept is counted for the sender and the link
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
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  v_add_helper boolean := false;
  v_add_tries boolean := false;
  v_widen boolean := false;
  v_comment boolean := false;
  v_check text; v_holds_acl text; v_holds_policies text;
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table or function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '530: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if to_regprocedure('pg_catalog.sha256(bytea)') is null then
    raise exception '530: pg_catalog.sha256(bytea) is missing'; end if;
  -- The salt table: as 529 made it, with its one row (read, never changed but its comment).
  if to_regclass('public.referral_sender_salt') is null
     or (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
           from information_schema.columns where table_schema = 'public' and table_name = 'referral_sender_salt') is distinct from c_salt_cols
     or (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
           from pg_constraint c where c.conrelid = 'public.referral_sender_salt'::regclass) is distinct from c_salt_con
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.referral_sender_salt'::regclass)
     or exists (select 1 from pg_policy p where p.polrelid = 'public.referral_sender_salt'::regclass)
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_class c, unnest(c.relacl) x where c.oid = 'public.referral_sender_salt'::regclass) is distinct from c_salt_acl
     or (select count(*) from public.referral_sender_salt) <> 1
     or not (select bool_and(s.id and s.salt ~ '^[0-9a-f]{64}$') from public.referral_sender_salt s) then
    raise exception '530: public.referral_sender_salt is missing or not as 529 made it (its columns, checks, one row, row level security with no policy, the owner''s alone). Re-read it before applying.';
  end if;
  if obj_description('public.referral_sender_salt'::regclass, 'pg_class') = c_salt_comment_before then
    v_comment := true;
  elsif obj_description('public.referral_sender_salt'::regclass, 'pg_class') is distinct from c_salt_comment_after then
    raise exception '530: the comment on public.referral_sender_salt is not 529''s or 530''s. Re-read it before applying.';
  end if;
  -- The helper: missing (made), or 530's (left alone).
  if to_regprocedure('public.' || c_helper_sig) is null then
    v_add_helper := true;
  elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_helper_sig))) <> c_helper_md5
        or (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_helper_sig)) is distinct from c_helper_acl then
    raise exception '530: a function public.request_sender() is there, but not 530''s (its text or its grants). Re-read it before applying.';
  else
    raise notice '530: public.request_sender() is already 530''s; left alone';
  end if;
  -- The tries table: missing (made), or as 530 made it (left alone).
  if to_regclass('public.health_survey_tries') is null then
    v_add_tries := true;
  elsif (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
           from information_schema.columns where table_schema = 'public' and table_name = 'health_survey_tries') is distinct from c_tries_cols
        or (select array_agg(pg_get_indexdef(x.indexrelid) order by pg_get_indexdef(x.indexrelid))
              from pg_index x where x.indrelid = 'public.health_survey_tries'::regclass) is distinct from c_tries_idx
        or (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
              from pg_constraint c where c.conrelid = 'public.health_survey_tries'::regclass) is distinct from c_tries_con
        or not (select c.relrowsecurity from pg_class c where c.oid = 'public.health_survey_tries'::regclass)
        or exists (select 1 from pg_policy p where p.polrelid = 'public.health_survey_tries'::regclass)
        or (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_class c, unnest(c.relacl) x where c.oid = 'public.health_survey_tries'::regclass) is distinct from c_tries_acl then
    raise exception '530: a table public.health_survey_tries is there, but not as 530 makes it. Re-read it before applying.';
  else
    raise notice '530: public.health_survey_tries is already as 530 made it; left alone';
  end if;
  -- The hold reasons: the nine before 530 (one is added), or the ten after (left alone).
  if to_regclass('public.health_survey_holds') is null then
    raise exception '530: public.health_survey_holds is missing'; end if;
  v_check := (select pg_get_constraintdef(c.oid) from pg_constraint c
               where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check');
  if v_check = c_check_before then
    v_widen := true;
  elsif v_check is distinct from c_check_after then
    raise exception '530: the check health_survey_holds_reason_check is not as tested (%). Re-read it before applying.', v_check;
  end if;
  v_holds_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                    from pg_class c, unnest(c.relacl) x where c.oid = 'public.health_survey_holds'::regclass);
  v_holds_policies := (select coalesce(string_agg(p.polname, ',' order by p.polname), '')
                         from pg_policy p where p.polrelid = 'public.health_survey_holds'::regclass);
  -- The form.
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '530: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if v_acl[i] is distinct from c_acl then
      raise exception '530: the grants of public.% are not the tested ones (%). Re-read them before applying.', c_sig[i], v_acl[i]; end if;
    if md5(d) = c_after[i] then
      raise notice '530: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '530: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  -- The form calls the helper, writes the tries and the new reason, so all are before 530 or all after.
  -- (The reasons check is left out: an UNDO leaves it widened while a hold has the new reason,
  -- which refuses nothing, and 530 then runs again over it.)
  if v_add_helper is distinct from v_make[1] or v_add_tries is distinct from v_make[1]
     or v_comment is distinct from v_make[1] then
    raise exception '530: public.submit_health_survey, public.request_sender, public.health_survey_tries and the salt''s comment are not all before 530 or all after it. Re-read them before applying.';
  end if;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '530: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '530: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install: the tries table, the helper and the reason first (the patched form uses them)
  if v_add_tries then
    create table public.health_survey_tries (
      id uuid primary key default gen_random_uuid(),
      created_at timestamp with time zone not null default now(),
      survey_link_id uuid not null,
      sender_key text constraint health_survey_tries_sender_key_is_a_hash check (sender_key is null or sender_key ~ '^[0-9a-f]{64}$'),
      outcome text not null constraint health_survey_tries_outcome_check check (outcome in ('kept', 'dropped')));
    alter table public.health_survey_tries enable row level security;
    revoke all on table public.health_survey_tries from public, anon, authenticated, service_role;
    create index idx_health_survey_tries_sender_time on public.health_survey_tries (sender_key, created_at)
      where sender_key is not null;
    create index idx_health_survey_tries_link_time on public.health_survey_tries (survey_link_id, created_at);
    create index idx_health_survey_tries_time on public.health_survey_tries (created_at);
    comment on table public.health_survey_tries is
      '530: each form the public QR health form kept (kept) or dropped by the day''s limit for a phone (dropped): when, through which link, and from which sender (the hex sha256 of the secret salt, public.referral_sender_salt, and the sender''s address, as request_sender makes it; never an address, never a phone). submit_health_survey counts them: 10 an hour from one sender, 60 an hour through one link; it deletes rows older than a day. No API role reads it.';
  end if;
  if v_add_helper then
    execute c_helper;
    revoke all on function public.request_sender() from public, anon, authenticated, service_role;
    comment on function public.request_sender() is
      '530: the request''s address (cf-connecting-ip) and its sender key (salted sha256; an IPv6 address as its /64), as 529 keys referral_signup_events.sender_key. Internal: called by submit_health_survey, which runs as the owner.';
  end if;
  if v_widen then
    alter table public.health_survey_holds drop constraint health_survey_holds_reason_check;
    alter table public.health_survey_holds add constraint health_survey_holds_reason_check
      check (reason = any (array['phone_in_use', 'email_in_use', 'phone_and_email_in_use', 'several_name_matches',
                                 'phone_and_email_customer_has_survey', 'repeat_form', 'customer_has_survey',
                                 'legacy_survey_same_details', 'unreadable_phone_same_name', 'existing_customer']));
  end if;
  if v_comment then
    execute format('comment on table public.referral_sender_salt is %L', c_salt_comment_after);
  end if;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_helper_sig))) is distinct from c_helper_md5
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_helper_sig)) is distinct from c_helper_acl
     or has_function_privilege('anon', 'public.request_sender()', 'execute')
     or has_function_privilege('authenticated', 'public.request_sender()', 'execute') then
    raise exception '530: public.request_sender() is not as tested after making it (its text, or the owner''s alone)'; end if;
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'health_survey_tries') is distinct from c_tries_cols
     or (select array_agg(pg_get_indexdef(x.indexrelid) order by pg_get_indexdef(x.indexrelid))
           from pg_index x where x.indrelid = 'public.health_survey_tries'::regclass) is distinct from c_tries_idx
     or (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
           from pg_constraint c where c.conrelid = 'public.health_survey_tries'::regclass) is distinct from c_tries_con
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.health_survey_tries'::regclass)
     or exists (select 1 from pg_policy p where p.polrelid = 'public.health_survey_tries'::regclass)
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_class c, unnest(c.relacl) x where c.oid = 'public.health_survey_tries'::regclass) is distinct from c_tries_acl
     or has_table_privilege('anon', 'public.health_survey_tries', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.health_survey_tries', 'select,insert,update,delete')
     or has_table_privilege('service_role', 'public.health_survey_tries', 'select,insert,update,delete') then
    raise exception '530: public.health_survey_tries is not as tested after making it (the owner''s alone)'; end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check') is distinct from c_check_after
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_class c, unnest(c.relacl) x where c.oid = 'public.health_survey_holds'::regclass) is distinct from v_holds_acl
     or (select coalesce(string_agg(p.polname, ',' order by p.polname), '')
           from pg_policy p where p.polrelid = 'public.health_survey_holds'::regclass) is distinct from v_holds_policies then
    raise exception '530: health_survey_holds is not as tested after widening its reasons'; end if;
  if obj_description('public.referral_sender_salt'::regclass, 'pg_class') is distinct from c_salt_comment_after
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_class c, unnest(c.relacl) x where c.oid = 'public.referral_sender_salt'::regclass) is distinct from c_salt_acl
     or (select count(*) from public.referral_sender_salt) <> 1 then
    raise exception '530: public.referral_sender_salt changed other than its comment'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '530: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '530: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '530: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
