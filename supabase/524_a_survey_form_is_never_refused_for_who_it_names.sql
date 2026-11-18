-- 524_a_survey_form_is_never_refused_for_who_it_names.sql
--
-- THE QR HEALTH SURVEY NEVER SAYS WHO HAS SENT ONE: IT IS KEPT AND WAITS FOR STAFF
--
--   From the security audit of 17 Nov 2026 (finding L9, part 3).
--   The BEFORE md5 below is that of production after 523 (the local copy of 18 Nov 2026).
--   If production differs when this is applied, it refuses and changes nothing.
--   (The number 524 is this file's name and its errors' prefix; if it changes at commit,
--   change it there, in the 524 comments it writes into submit_health_survey (and so its
--   AFTER md5, also in scripts/survey/undo-524.sql), in the name and path of its suite, and in
--   the suites that look for '524:' in submit_health_survey.)
--
-- WHAT WAS WRONG
--
--   The QR health survey form (submit_health_survey, which a signed-out page calls) refused a
--   form in four cases, and the page then said "A health survey has already been completed
--   for these details" or "More than one customer record matches this phone number and name".
--   So anyone with a survey link could learn, from a phone number and a name, that:
--     1. a form had been sent before under them, which waits for staff or is now a customer's
--        survey (HEALTH_SURVEY_ALREADY_EXISTS, 433);
--     2. the one customer with this phone and name already has a health survey
--        (HEALTH_SURVEY_ALREADY_EXISTS, before 433);
--     3. an older survey with no customer has this phone and name (AMBIGUOUS_CUSTOMER_MATCH);
--     4. an old customer record with this name has a phone that cannot be read as one number
--        but could be this one (AMBIGUOUS_CUSTOMER_MATCH, from require_resolved_customer_identity).
--   468 had already stopped one such refusal: a form found by the phone and email alone, whose
--   customer has a survey, is kept quietly for staff ('phone_and_email_customer_has_survey').
--
-- THE RULE (the user, 18 Nov 2026: "Accept and hold for staff": "Every form gets the same
-- thank-you. A repeat or unclear one waits in staff's 'To match' list.")
--
--   None of these is refused. The form is accepted with the same reply as any form (success,
--   its survey number, its id), kept with no customer (never attached, and it fills in no
--   customer's details) and waits for staff in Health Surveys > To match. Staff deal with it
--   as with any form there: attach it, make a new customer from it, or an Owner or Manager
--   closes it.
--
-- WHAT THIS DOES
--
--   * health_survey_holds may give four more reasons (its check is widened):
--       repeat_form                 case 1: the same phone and name sent a form before that
--                                   waits or is a customer's survey. It waits with the
--                                   customers of those earlier forms (the one each was
--                                   attached to or made into, or, for one still waiting, the
--                                   customers it waits for).
--       customer_has_survey         case 2: the one customer found by the phone and name
--                                   already has a survey. It waits with that customer.
--       legacy_survey_same_details  case 3: no customer has the phone and name, but an older
--                                   survey with no customer (not a held form) does. It waits
--                                   with none (To match also lists whoever has its phone or
--                                   email now); no customer is made.
--       unreadable_phone_same_name  case 4: an old customer with this name has a phone that
--                                   cannot be read but could be this one. It waits with those
--                                   old records and any customer with this phone and name;
--                                   no customer is made.
--   * submit_health_survey: those four cases set the hold (and its customers) where they
--     raised the error, and the form goes on as a held one does: no customer, the name parts,
--     phone and email as typed, the hold, the Audit Log row (held_for_staff, hold_reason),
--     the same reply. A form found by the phone and name whose customer has an unsigned
--     consultant record but also another survey waits too (it is not signed into the record).
--     Case 4 is caught from require_resolved_customer_identity (that error alone, as it raises
--     it; any other error goes on as it was) and comes first, as its refusal did: such a form
--     waits for it whatever else matches. Then case 1 (sent again), then the others, as before.
--
-- WHAT THIS LEAVES ALONE
--
--   * Every other form: a new person (a new customer), an existing customer's first survey
--     (attached, its empty details filled), the other holds (433, 468), a consultant's record
--     the customer has not signed (419, Q10).
--   * The other refusals: a bad link, a missing or invalid answer, CUSTOMER_PHONE_REVIEW.
--   * require_resolved_customer_identity itself: the affiliate sign-up and the event website
--     still refuse with it, as before; only the QR form catches it.
--   * health_survey_sign_into_record still raises HEALTH_SURVEY_ALREADY_EXISTS if the
--     consultant's record was signed between the form's look and its write (a race only).
--   * attach_held_health_survey, create_customer_from_held_survey, close_held_health_survey
--     and health_survey_holds_list: none of them chooses by reason (they copy it to the Audit
--     Log or the list), so they take the new holds as they are.
--   * The grants of submit_health_survey (anon may call it, as before).
--
-- UNDO
--
--   scripts/survey/undo-524.sql (it refuses unless submit_health_survey is 524's version). It
--   puts the check back to its five reasons only while no hold has one of the four new ones;
--   otherwise it leaves it widened (that refuses nothing). The forms kept while 524 was in
--   stay, with no customer, until staff deal with them. A later migration changing
--   submit_health_survey must pin 524's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/survey/tests/survey-never-refused-524.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  c_sig constant text[] := array[
    'submit_health_survey(text,jsonb,jsonb,text)'];
  c_before constant text[] := array[
    'ddc02ed5fa82aacde5f031d6d367b300'];
  c_after constant text[] := array[
    'a65183cdcb48f2dd883a47c1c7aad7f3'];
  -- The check on health_survey_holds.reason, before and after.
  c_check_before constant text :=
    'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, ''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text])))';
  c_check_after constant text :=
    'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, ''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text, ''repeat_form''::text, ''customer_has_survey''::text, ''legacy_survey_same_details''::text, ''unreadable_phone_same_name''::text])))';
  -- Eleven patches of the one function, each found exactly once.
  c_fn constant int[] := array[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];
  c_anchor constant text[] := array[
$a$  v_both uuid[];
begin
$a$,
$a$  perform public.require_resolved_customer_identity(v_norm,v_name);
$a$,
$a$  -- 433: the person sent this form before (this phone, this name as typed)
$a$,
$a$  if exists (select 1 from public.health_survey_holds h
$a$,
$a$  -- record by a merge). Refused as a customer's second survey is. One that
  -- was closed, or whose customer was deleted, is not the person's survey.$a$,
$a$                                      where x.id = h.resolved_customer_id and x.deleted_at is null)))) then
    raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
  end if;

  if v_match_count > 1 then$a$,
$a$      if v_name_match is distinct from 'phone_and_email' then
        raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
      end if;
$a$,
$a$      v_hold := 'phone_and_email_customer_has_survey';
$a$,
$a$      raise exception 'AMBIGUOUS_CUSTOMER_MATCH';
    end if;
$a$,
$a$    if cardinality(v_phone_holders) > 0 or cardinality(v_email_holders) > 0 then
$a$,
$a$                     -- waiting is refused above, and one an Owner or Manager$a$];
  c_new constant text[] := array[
$n$  v_both uuid[];
  -- 524: an old customer with this name has a phone that cannot be read but could be this one.
  v_unreadable boolean := false;
begin
$n$,
$n$  -- 524 (the user, 18 Nov 2026; security audit of 17 Nov 2026, L9): that check's refusal
  -- (an old customer with this name has a phone that cannot be read but could be this one)
  -- told anyone with the link that such a record exists. The form now waits for staff
  -- instead (below). Only that refusal is caught; any other error goes on as it was.
  begin
    perform public.require_resolved_customer_identity(v_norm,v_name);
  exception when raise_exception then
    if sqlerrm is distinct from 'AMBIGUOUS_CUSTOMER_MATCH' then raise; end if;
    v_unreadable := true;
  end;
$n$,
$n$  -- 524: first, a form beside an old record whose phone cannot be read (above) is kept
  -- with no customer and waits for staff, with those old records and any customer with
  -- this phone and name, whatever else matches (it was refused before anything else).
  if v_unreadable then
    v_hold := 'unreadable_phone_same_name';
    select coalesce(array_agg(distinct m.x order by m.x), '{}'::uuid[]) into v_candidates
      from (select c.id as x from public.customers c
             where c.deleted_at is null and public.normalize_customer_phone(c.phone) is null
               and public.normalize_customer_match_name(c.full_name) = public.normalize_customer_match_name(v_name)
               and (public.inspect_customer_phone(c.phone)->'candidates') ? v_norm
            union all
            select unnest(v_matches)) m;
  end if;

  -- 433: the person sent this form before (this phone, this name as typed)
$n$,
$n$  if v_hold is null and exists (select 1 from public.health_survey_holds h
$n$,
$n$  -- record by a merge). 524: it waits for staff (below). One that
  -- was closed, or whose customer was deleted, is not the person's survey.$n$,
$n$                                      where x.id = h.resolved_customer_id and x.deleted_at is null)))) then
    -- 524 (the user, 18 Nov 2026; security audit of 17 Nov 2026, L9): no
    -- longer refused, which told anyone with the link that a form had been
    -- sent under this phone and name. It is kept with no customer and waits
    -- for staff, with the customers of the earlier forms: the one each was
    -- attached to or made into, or, for one still waiting, those it waits
    -- for. The reply is the same as any form's.
    v_hold := 'repeat_form';
    select coalesce(array_agg(distinct c.id order by c.id), '{}'::uuid[]) into v_candidates
      from public.health_survey_holds h
      join public.health_surveys s on s.id = h.survey_id
      join public.customers c
        on c.deleted_at is null
       and (c.id = s.customer_id
            or (h.resolution = 'attached' and c.id = h.resolved_customer_id)
            or (h.resolved_at is null and s.customer_id is null and c.id = any (h.candidate_customer_ids)))
     where h.typed_phone = v_norm
       and h.reason <> 'phone_and_email_customer_has_survey'
       and (public.normalize_customer_match_name(h.typed_full_name) = public.normalize_customer_match_name(v_name)
            or public.customer_names_match(h.typed_full_name, v_name));
  end if;

  if v_hold is not null then
    -- 524: a form beside an old record whose phone cannot be read, or sent again (above),
    -- waits for staff, whoever else it matches.
    null;
  elsif v_match_count > 1 then$n$,
$n$      -- 524 (the user, 18 Nov 2026; security audit of 17 Nov 2026, L9): found
      -- by the phone and the name, it is not refused either (that told anyone
      -- with the link that this person has a survey): it is kept with no
      -- customer and waits for staff with them, as one found by the phone and
      -- the email alone does (468).
$n$,
$n$      v_hold := case when v_name_match = 'phone_and_email' then 'phone_and_email_customer_has_survey'
                     else 'customer_has_survey' end;
$n$,
$n$      -- 524 (the user, 18 Nov 2026; security audit of 17 Nov 2026, L9): no
      -- longer refused (that told anyone with the link that an old survey has
      -- this phone and name). It is kept with no customer and waits for
      -- staff; no customer is made.
      v_hold := 'legacy_survey_same_details';
      v_candidates := '{}'::uuid[];
    end if;
$n$,
$n$    if v_hold is not null then
      null; -- 524: the form above, like an old survey's, waits for staff.
    elsif cardinality(v_phone_holders) > 0 or cardinality(v_email_holders) > 0 then
$n$,
$n$                     -- waiting is held above (524), and one an Owner or Manager$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  v_check text;
  v_widen boolean := false;
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table or function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '524: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '524: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '524: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '524: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '524: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- The check on the hold's reason: the five reasons (widened), or 524's nine already (left alone).
  v_check := (select pg_get_constraintdef(c.oid) from pg_constraint c
               where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check');
  if v_check = c_check_before then
    v_widen := true;
  elsif v_check = c_check_after then
    raise notice '524: health_survey_holds_reason_check already has the four new reasons; left alone';
  else
    raise exception '524: health_survey_holds_reason_check is not as tested (%). Re-read it before applying.', coalesce(v_check, 'missing');
  end if;

  -- 2. Install
  if v_widen then
    alter table public.health_survey_holds
      drop constraint health_survey_holds_reason_check,
      add constraint health_survey_holds_reason_check check (reason = any (array[
        'phone_in_use', 'email_in_use', 'phone_and_email_in_use', 'several_name_matches',
        'phone_and_email_customer_has_survey',
        -- 524 (the user, 18 Nov 2026): the forms that were refused, now kept for staff.
        'repeat_form', 'customer_has_survey', 'legacy_survey_same_details', 'unreadable_phone_same_name']));
  end if;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check')
     is distinct from c_check_after then
    raise exception '524: health_survey_holds_reason_check is not the tested one after widening it'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '524: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '524: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
