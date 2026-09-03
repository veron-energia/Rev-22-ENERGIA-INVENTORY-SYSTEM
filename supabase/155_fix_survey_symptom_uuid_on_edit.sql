-- =====================================================================
-- ENERGIA — FIX "invalid input syntax for type uuid: undefined"
-- WHEN EDITING A HEALTH SURVEY
--
-- health_survey_detail() returned declared symptoms without option_id. The
-- React edit form therefore received x.option_id === undefined, converted it
-- to the string "undefined", and update_survey_particulars() later attempted
-- to cast that value to uuid.
--
-- Patch the existing function instead of redefining it wholesale, preserving
-- all later access-control changes while adding the missing UUID to the JSON.
-- =====================================================================

set check_function_bodies = off;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid)
    into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'health_survey_detail'
     and pg_get_function_identity_arguments(p.oid) = 'p_survey_id uuid';

  if v_def is null then
    raise exception 'health_survey_detail(uuid) not found';
  end if;

  if position('''option_id'', x.option_id' in v_def) > 0 then
    raise notice 'health_survey_detail already returns symptom option_id';
    return;
  end if;

  v_new := replace(
    v_def,
    '''category'', o.category, ''label'', o.label, ''duration_text'', x.duration_text',
    '''option_id'', x.option_id, ''category'', o.category, ''label'', o.label, ''duration_text'', x.duration_text'
  );

  if v_new = v_def then
    raise exception 'Could not patch health_survey_detail: symptom JSON shape was not recognised';
  end if;

  execute v_new;
  raise notice 'health_survey_detail now returns symptom option_id';
end
$patch$;

notify pgrst, 'reload schema';
