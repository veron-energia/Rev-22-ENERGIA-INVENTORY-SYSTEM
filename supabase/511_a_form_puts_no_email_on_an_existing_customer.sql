-- 511_a_form_puts_no_email_on_an_existing_customer.sql
--
-- A FORM PUTS NO EMAIL ON A CUSTOMER WHO WAS THERE BEFORE IT
--
--   From the security audit of 17 Nov 2026 (finding M18, found while checking 508).
--   The BEFORE md5s below are 485's AFTER md5s, which production checked when it ran 485 on
--   2 Nov 2026; no migration since names these three functions. They were read again on a
--   rebuilt local copy with 504 to 510 in. If production's text differs when this is
--   applied, it refuses and changes nothing.
--   (The number 511 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   Since 508 a portal login is shown its customer record only when its link to the record
--   is proven. One proof (484's proof (d)) is that the login's verified email is the
--   record's email. 485 stopped a form putting an email on a record that has a portal login
--   or an affiliate record. On any other record a form still filled a missing email:
--     * the QR health form, signed out, for a customer it finds by phone and name;
--     * staff attaching a held QR form to a customer;
--     * the event website's registration, for a customer it matches itself or staff link.
--   So someone who knew a customer's name and phone could send the QR form with an email of
--   their own, sign up on the join page with that email and the customer's phone (437 joins
--   on the phone), open the verification link in their own inbox, and be proven. The portal
--   then showed them the customer's record and the people under it. It needed a customer
--   with no email, no health survey, no portal login and no affiliate record. Shown on a
--   local copy with 504 to 510 in, on 17 Nov 2026.
--
-- THE RULE
--
--   A form's email goes only on the customer that form itself makes. It never goes onto a
--   customer who was there before: not from the QR form, not when staff attach a held QR
--   form, not from the event website's registration and not when staff link a held
--   registration. This is 485's rule for an affiliate's record, now for every record.
--   Everything else these fill (date of birth, sex, occupation, how they heard about us,
--   the source an event names), they fill as before. The email typed stays where it always
--   was, on the form (health_surveys.email) and on the registration
--   (event_registration_people.email). Staff put it on the record in Edit customer when it
--   is the customer's: a decision about the email itself.
--
-- WHAT THIS DOES
--
--   Three patches, each the smallest edit of 485's text:
--   1. submit_health_survey: the update of a customer found by phone and name no longer
--      sets email. The insert of a new customer keeps the email typed.
--   2. attach_held_health_survey: the update of the customer no longer sets email.
--   3. event_web_fill_customer: it keeps every email (v_keep_email is always true), so an
--      email already there is no longer trimmed either. Both of its callers pass a customer
--      who was there before: event_web_register for its own match, event_registration_attach
--      for staff. A customer a registration makes takes the email typed through
--      event_web_new_customer, as before.
--
-- WHAT CHANGES FOR STAFF AND CUSTOMERS
--
--   * A customer with no email on record who fills in the QR form, or registers on the
--     event website, no longer gets that email on their record by itself. Staff see it on
--     the form or the registration and add it in Edit customer.
--   * A portal login whose only tie to its record would have been such an email is not
--     proven by it. It waits on the list for an Owner or Manager to say Same person, as
--     any other join does since 508.
--   * The two staff windows that say an empty email is filled (attaching a held form on
--     Surveys, linking a held registration on the Event page) need their sentence changed
--     with this, and their tests with them.
--
-- WHAT THIS LEAVES ALONE
--
--   * Emails a form put on a record before 511. To look at them, read-only: portal logins
--     proven only by their email, where a health form carried that email before the login
--     joined (account ids and two dates only):
--       select a.id, a.created_at, min(h.submitted_at)
--         from public.affiliate_accounts a
--         join public.customers c on c.id = a.customer_id
--         join public.health_surveys h on h.customer_id = c.id
--          and public.customer_email_match_key(h.email) = public.customer_email_match_key(c.email)
--          and h.submitted_at < a.created_at
--        where a.status = 'claimed'
--          and public.affiliate_login_link_proof(a.auth_user_id, a.customer_id) = 'verified_email'
--        group by a.id, a.created_at;
--     Most rows will be customers who typed their own email.
--   * Staff changing a customer's email in Edit customer (update_customer), or in a
--     survey's Edit details, which also decides proof (d).
--   * A customer a form or a registration makes: it still takes the email typed.
--   * The proofs themselves (affiliate_login_link_proof) and the join (437, 508).
--
-- UNDO
--
--   Run this block with c_before and c_after swapped and c_anchor and c_new swapped (it then
--   refuses unless each function is 511's version). A later migration changing one of the
--   three functions must pin 511's AFTER md5.
--
-- NO SELF-TEST INSIDE: it would have to make customers, a survey link, an event and a
-- portal login. The suite is scripts/survey/tests/form-email-existing-customer-511.sql,
-- for a local copy.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function(s) this patches: BEFORE (485's AFTER, as production has them) and AFTER md5s
  c_sig constant text[] := array[
    'submit_health_survey(text,jsonb,jsonb,text)',
    'attach_held_health_survey(uuid,uuid,text)',
    'event_web_fill_customer(uuid,uuid)'];
  c_before constant text[] := array[
    '860743f4f2e92f669e257121de0a9308',
    '8a66d8e6d7008c79d94c5b20ffecb4df',
    '4cefb8a7ae96aa5836041cf57cb3f33f'];
  c_after constant text[] := array[
    'ddc02ed5fa82aacde5f031d6d367b300',
    '55b632c7e9289cb267516a26af97387b',
    'ca9957a62467c9f9ea574de86c8fd1bb'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO swaps them back.
  c_fn constant int[] := array[1, 2, 3];
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
  -- Relied on, not changed: what proven means and who joins (484, 508), and the callers
  -- and the maker of a registration's customer (the reason patch 3 may keep every email)
  c_relied constant text[] := array[
    'affiliate_login_link_proof(uuid,uuid)',
    'affiliate_portal_record_id()',
    'complete_affiliate_onboarding(text,text,text,boolean)',
    'event_web_register(uuid,jsonb)',
    'event_registration_attach(uuid,uuid,text)',
    'event_web_new_customer(uuid)'];
  c_relied_md5 constant text[] := array[
    '2484fb464733c124213b96152837a660',
    'adac2cc661231357d044d2fb1c70a38a',
    '0dd12d4c9cef8b86bb1bcc02a5344927',
    'c188a2dc82b9eb08fc9d01f1e5c15e13',
    'b31be4d82d20000df026e7cfa9b24095',
    'a253f76a9db721212a9c110bc41ff483'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[3]);
  v_make boolean[] := array_fill(false, array[3]);
  v_acl text[] := array_fill(null::text, array[3]);
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '511: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The function(s) it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '511: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '511: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '511: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '511: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '511: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '511: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '511: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  -- The QR form stays a signed-out endpoint; the registration's fill stays the server's only.
  if not has_function_privilege('anon', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
     or has_function_privilege('anon', 'public.event_web_fill_customer(uuid,uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.event_web_fill_customer(uuid,uuid)', 'execute') then
    raise exception '511: the grants of the QR form or of the registration''s fill are not as tested'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
