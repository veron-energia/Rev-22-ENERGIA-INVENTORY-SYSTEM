-- UNDO of 524 (with the user's go-ahead). It puts submit_health_survey back to its text before
-- 524 (md5 ddc02ed5…, as 511 left it): the QR health survey form refuses again, with
-- HEALTH_SURVEY_ALREADY_EXISTS or AMBIGUOUS_CUSTOMER_MATCH, a form sent again under a phone and
-- name, one whose customer already has a survey, one whose phone and name an old survey with no
-- customer has, and one beside an old customer of that name whose phone cannot be read but could
-- be this one. Its grants stay as they are.
--
-- The check on health_survey_holds.reason goes back to its five reasons only when no hold has
-- one of the four 524 added (a hold keeps its reason once dealt with); otherwise it is left
-- widened, which refuses nothing, and a notice says so. The forms kept while 524 was in stay,
-- with no customer, until staff deal with them in To match.
--
-- It refuses, with nothing changed, unless submit_health_survey is exactly 524's version (so a
-- later version is never overwritten). One transaction, all or nothing; it waits at most 5
-- seconds for a lock. The 524 row in supabase_migrations.schema_migrations stays; with the
-- user's OK, remove that one row (found by its name, 524_a_survey_form_is_never_refused_for_who_it_names)
-- or record this UNDO beside it.
--
-- scripts/survey/tests/forms-as-before-511.sql runs this inside 485's suite's transaction where
-- 524 is in (everything there is rolled back): that suite tests the form before 511.
-- The patch texts below are 524's, the other way round: each 524 text is found exactly once and
-- put back as it was.
do $undo$
declare
  c_sig constant text := 'submit_health_survey(text,jsonb,jsonb,text)';
  c_524 constant text := 'a65183cdcb48f2dd883a47c1c7aad7f3';
  c_before_524 constant text := 'ddc02ed5fa82aacde5f031d6d367b300';
  c_check_before constant text :=
    'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, ''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text])))';
  c_check_524 constant text :=
    'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, ''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text, ''repeat_form''::text, ''customer_has_survey''::text, ''legacy_survey_same_details''::text, ''unreadable_phone_same_name''::text])))';
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
  v_acl text; v_check text; v_narrow boolean := false;
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  if to_regprocedure('public.' || c_sig) is null then raise exception 'UNDO 524: public.% is missing', c_sig; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) <> c_524 then
    raise exception 'UNDO 524: public.% is not 524''s version (md5 %). Nothing changed.', c_sig, md5(d); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));
  for i in 1 .. cardinality(c_new) loop
    if (length(d) - length(replace(d, c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 524: patch % does not find 524''s text exactly once in public.%', i, c_sig; end if;
    d := replace(d, c_new[i], c_anchor[i]);
  end loop;
  if md5(d) <> c_before_524 then
    raise exception 'UNDO 524: the text put back is not the one before 524 (md5 %). Nothing changed.', md5(d); end if;
  v_check := (select pg_get_constraintdef(c.oid) from pg_constraint c
               where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check');
  if v_check = c_check_524 then
    if exists (select 1 from public.health_survey_holds
                where reason in ('repeat_form', 'customer_has_survey', 'legacy_survey_same_details', 'unreadable_phone_same_name')) then
      raise notice 'UNDO 524: some holds have a reason 524 added; health_survey_holds_reason_check is left widened';
    else
      v_narrow := true;
    end if;
  elsif v_check is distinct from c_check_before then
    raise exception 'UNDO 524: health_survey_holds_reason_check is not 524''s (%). Nothing changed.', coalesce(v_check, 'missing');
  end if;

  -- 2. Put back
  execute d;
  if v_narrow then
    alter table public.health_survey_holds
      drop constraint health_survey_holds_reason_check,
      add constraint health_survey_holds_reason_check check (reason = any (array[
        'phone_in_use', 'email_in_use', 'phone_and_email_in_use', 'several_name_matches',
        'phone_and_email_customer_has_survey']));
  end if;

  -- 3. Checks after
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_before_524 then
    raise exception 'UNDO 524: public.% was put back with an md5 other than the one before 524', c_sig; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception 'UNDO 524: the grants of public.% changed', c_sig; end if;
  if v_narrow and (select pg_get_constraintdef(c.oid) from pg_constraint c
                    where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check')
                  is distinct from c_check_before then
    raise exception 'UNDO 524: health_survey_holds_reason_check is not the one before 524 after narrowing it'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
