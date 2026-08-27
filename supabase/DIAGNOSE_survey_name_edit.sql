-- =====================================================================
-- DIAGNOSTIC — WHY A SURVEY NAME EDIT DOES NOT STICK
--
-- For the SUPABASE SQL EDITOR. No psql commands, no temporary tables.
--
-- My earlier versions failed because the editor may run each statement on a
-- different connection, so a temp table created by one statement is gone by the
-- next. This uses none.
--
-- SAFE. The test edit is made inside a plpgsql EXCEPTION block, which is a
-- subtransaction: raising at the end rolls the edit back while the values
-- already read into variables survive. Nothing is left changed.
--
-- HOW TO RUN
--   1. Run the whole file. It creates the function and calls it.
--   2. Change the survey number on the LAST LINE to one of yours.
-- =====================================================================

create or replace function public.diagnose_survey_name_edit(p_survey_no text)
returns table(step text, detail text, value text)
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_id uuid; v_cust uuid;
  v_fn text; v_ln text; v_full text;
  v_cfn text; v_cln text; v_cfull text;
  v_afn text; v_aln text; v_afull text;
  v_acfn text; v_acln text; v_acfull text;
  v_err text; r record;
begin
  -- ---- 1. How many versions of the function exist? ----
  for r in
    select pg_get_function_identity_arguments(p.oid) as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'update_survey_particulars'
  loop
    step := '1. FUNCTION VERSIONS';
    detail := case when r.sig like '%p_has_medical_condition%'
                   then 'FULL version'
                   else 'OLD SHORT VERSION — a call can land here' end;
    value := left(r.sig, 110);
    return next;
  end loop;

  -- ---- 2. Triggers that could rewrite the name ----
  for r in
    select c.relname as tbl, t.tgname as nm
      from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where c.relname in ('health_surveys', 'customers') and not t.tgisinternal
     order by c.relname, t.tgname
  loop
    step := '2. TRIGGERS'; detail := r.tbl; value := r.nm; return next;
  end loop;

  -- ---- 3. Find the survey ----
  select id, customer_id into v_id, v_cust
    from public.health_surveys where survey_no = p_survey_no;

  if v_id is null then
    step := '3. SURVEY'; detail := 'NOT FOUND';
    value := 'No survey numbered ' || coalesce(p_survey_no, '(null)');
    return next;
    return;
  end if;

  select first_name, last_name, full_name into v_fn, v_ln, v_full
    from public.health_surveys where id = v_id;
  step := '3. BEFORE survey'; detail := 'first / last';
  value := coalesce(v_fn, '(null)') || ' / ' || coalesce(v_ln, '(null)'); return next;
  detail := 'full_name'; value := coalesce(v_full, '(null)'); return next;

  if v_cust is not null then
    select first_name, last_name, full_name into v_cfn, v_cln, v_cfull
      from public.customers where id = v_cust;
    step := '4. BEFORE customer'; detail := 'first / last';
    value := coalesce(v_cfn, '(null)') || ' / ' || coalesce(v_cln, '(null)'); return next;
    detail := 'full_name'; value := coalesce(v_cfull, '(null)'); return next;
  else
    step := '4. BEFORE customer'; detail := 'none';
    value := 'This survey has no linked customer'; return next;
  end if;

  -- ---- 5. The test edit, rolled back by the exception below ----
  begin
    perform public.update_survey_particulars(
      v_id, 'DIAGTEST', 'NAMECHECK',
      (select phone from public.health_surveys where id = v_id),
      (select email from public.health_surveys where id = v_id),
      (select date_of_birth from public.health_surveys where id = v_id),
      (select sex from public.health_surveys where id = v_id),
      (select occupation from public.health_surveys where id = v_id),
      null);

    -- Read the result BEFORE unwinding: variables survive the rollback.
    select first_name, last_name, full_name into v_afn, v_aln, v_afull
      from public.health_surveys where id = v_id;
    if v_cust is not null then
      select first_name, last_name, full_name into v_acfn, v_acln, v_acfull
        from public.customers where id = v_cust;
    end if;

    -- Undo everything this block did.
    raise exception 'DIAG_ROLLBACK';
  exception when others then
    if sqlerrm <> 'DIAG_ROLLBACK' then
      v_err := sqlerrm;
    end if;
  end;

  if v_err is not null then
    step := '5. THE EDIT'; detail := 'RAISED AN ERROR'; value := v_err; return next;
  else
    step := '5. THE EDIT'; detail := 'called'; value := 'no error, and rolled back'; return next;

    step := '6. AFTER survey'; detail := 'first / last';
    value := coalesce(v_afn, '(null)') || ' / ' || coalesce(v_aln, '(null)'); return next;
    detail := 'full_name'; value := coalesce(v_afull, '(null)'); return next;

    if v_cust is not null then
      step := '7. AFTER customer'; detail := 'first / last';
      value := coalesce(v_acfn, '(null)') || ' / ' || coalesce(v_acln, '(null)'); return next;
      detail := 'full_name'; value := coalesce(v_acfull, '(null)'); return next;
    end if;
  end if;

  -- ---- 8. The verdict ----
  step := '8. VERDICT'; detail := '';
  value := case
    when v_err is not null
      then 'The call FAILED: ' || v_err
    when v_afn = 'DIAGTEST' and (v_cust is null or v_acfn = 'DIAGTEST')
      then 'DATABASE IS FINE — both rows updated. The fault is on screen.'
    when v_afn is distinct from 'DIAGTEST'
      then 'THE SURVEY WAS NOT UPDATED — something reverted it. See section 2.'
    when v_cust is not null and v_acfn is distinct from 'DIAGTEST'
      then 'Survey updated but the CUSTOMER did not.'
    else 'Unexpected — send me the rows above.'
  end;
  return next;
end $function$;

-- >>> PUT YOUR SURVEY NUMBER HERE, THEN RUN THE WHOLE FILE.
select * from public.diagnose_survey_name_edit('SURVEY-NUMBER-HERE');

-- When you are finished:
--   drop function public.diagnose_survey_name_edit(text);
