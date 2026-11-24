-- For the suites written before 511, on a database where 511 is in (included by each right after its begin).
--
-- 511 (17 Nov 2026) stops a form putting an email on a customer who was there before it: the QR health form
-- (submit_health_survey), staff attaching a held QR form (attach_held_health_survey) and the event website's
-- registration, matched by the website or linked by staff (event_web_fill_customer). 485's own suite checks the
-- versions before it: a plain record's missing email is filled from the form or the registration (its Q, E and S),
-- and it undoes 485 and installs it again, which needs the three functions to be 485's (its P0, U and M). So for
-- its run, which is rolled back, the three functions are put back to their text before 511, as 511's UNDO does
-- (each of its replacements, reversed). Anywhere else (511 not in) this changes nothing.
-- What 511 changes is checked by scripts/survey/tests/form-email-existing-customer-511.sql.
--
-- Included by scripts/survey/tests/affiliate-email-485.sql.
-- Never run it on its own against a real database: it is only for a rolled-back test.
-- 524 (18 Nov 2026) changed submit_health_survey after 511 (the forms it refused wait for staff).
-- Where 524 is in, it is first put back as before 524 by its UNDO, scripts/survey/undo-524.sql
-- (inside the same rolled-back transaction), so that 511's own text is there to put back below.
-- 530 (19 Nov 2026) changed it after 524 (limits, held existing customers): where 530 is in, it is
-- put back first by its UNDO, scripts/survey/undo-530.sql, so that 524's text is there for 524's UNDO.
select position('-- 530 (security audit' in pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) > 0 as as511_m530 \gset
\if :as511_m530
\ir ../undo-530.sql
\endif
select position('524:' in pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) > 0 as as511_m524 \gset
\if :as511_m524
\ir ../undo-524.sql
\endif
do $as511$
declare
  v_path text := current_setting('search_path');
  c_sig constant text[] := array['submit_health_survey(text,jsonb,jsonb,text)', 'attach_held_health_survey(uuid,uuid,text)', 'event_web_fill_customer(uuid,uuid)'];
  c_511 constant text[] := array['ddc02ed5fa82aacde5f031d6d367b300', '55b632c7e9289cb267516a26af97387b', 'ca9957a62467c9f9ea574de86c8fd1bb'];
  c_before constant text[] := array['860743f4f2e92f669e257121de0a9308', '8a66d8e6d7008c79d94c5b20ffecb4df', '4cefb8a7ae96aa5836041cf57cb3f33f'];
  -- 511's c_new (found now) and c_anchor (put back), as in supabase/511_a_form_puts_no_email_on_an_existing_customer.sql
  c_new constant text[] := array[
$n$    -- email there. The form keeps the email typed; staff may copy it.
    -- 511: nor the email of any other customer who was there before this
    -- form. Since 508 a portal login is shown its record only once its link
    -- is proven, and one proof is that the login's verified email is the
    -- record's (484's proof (d)). The email on a form is whatever its sender
    -- typed, so it must not become the record's. It goes only on a customer
    -- this form itself makes (below). Staff add an email in Edit customer.
    update public.customers
       set date_of_birth     = coalesce(date_of_birth, nullif(p_payload->>'date_of_birth','')::date),$n$,
$n$  -- customer when it is theirs. The form keeps the email typed.
  -- 511: nor the email of any other customer. Since 508 the record's email
  -- decides whether a portal login is shown the record at all, and attaching
  -- decides whose form this is, not whose email. Staff add it in Edit customer.
  update public.customers
     set date_of_birth     = coalesce(date_of_birth, v_s.date_of_birth),$n$,
$n$  -- 511: every customer this fills was there before the registration (the
  -- website's own match, or staff linking a held one), so it leaves every
  -- such email as it is. Since 508 the record's email decides whether a
  -- portal login is shown the record at all, and the person registering
  -- chose the email typed. A customer the registration makes still takes it
  -- (event_web_new_customer).
  v_keep_email := true;$n$];
  c_anchor constant text[] := array[
$a$    -- email there. The form keeps the email typed; staff may copy it.
    update public.customers
       set email             = case when email is null
                                     and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
                                     and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
                                    then v_email else email end,
           date_of_birth     = coalesce(date_of_birth, nullif(p_payload->>'date_of_birth','')::date),$a$,
$a$  -- customer when it is theirs. The form keeps the email typed.
  update public.customers
     set email             = case when email is null
                                   and not exists (select 1 from public.affiliate_accounts a where a.customer_id = customers.id)
                                   and not exists (select 1 from public.customer_affiliates f where f.customer_id = customers.id)
                                  then nullif(btrim(v_s.email), '') else email end,
         date_of_birth     = coalesce(date_of_birth, v_s.date_of_birth),$a$,
$a$  v_keep_email := exists (select 1 from public.affiliate_accounts a where a.customer_id = p_customer_id)
                  or exists (select 1 from public.customer_affiliates f where f.customer_id = p_customer_id);$a$];
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  if md5(pg_get_functiondef('public.event_web_fill_customer(uuid,uuid)'::regprocedure)) = c_511[3] then
    for i in 1 .. 3 loop
      d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
      if md5(d) <> c_511[i] then raise exception 'forms-as-before-511: public.% is not 511''s version', c_sig[i]; end if;
      execute replace(d, c_new[i], c_anchor[i]);
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i] then
        raise exception 'forms-as-before-511: public.% is not its version before 511 after putting it back', c_sig[i]; end if;
    end loop;
    raise notice '511 is in: the three functions it changes are as before it for this run (rolled back at the end)';
  end if;
  perform set_config('search_path', v_path, true);
end $as511$;
