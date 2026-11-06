-- 493_affiliate_email_change_without_current_inbox.sql
--
-- AN AFFILIATE WHO CANNOT OPEN THEIR CURRENT EMAIL CAN STILL CHANGE IT: A CODE
-- TO THE NEW EMAIL, THEN AN OWNER OR MANAGER APPROVES
-- (the user's answers in chat, 6 Nov 2026)
--
-- (491 asks for a code to the current email first, and tells an unverified
-- login joined to an existing record to verify that email first. Someone who
-- cannot open that inbox, a typo at sign-up say, was stuck: no code, and no way
-- for staff to change a login's email in the app.)
--
-- THE RULE
--
--   * A verified login (routes code and staff), and an unverified one on a
--     record its own sign-up did not make (route verify_first), may say they
--     cannot open their current email. The answer to "unverified too" was
--     "Yes, same route".
--   * The code then goes to the NEW email only, which must be another address
--     than the login's. The request always waits for an Owner or Manager
--     (route 'staff'), whatever the login's own route is; a free login changes
--     its email at once and needs none of this; a closed one is refused.
--   * On approval the login's email and the record's change together, as in
--     491, and the account is verified: the new inbox is proven by its code.
--   * Everything else is 491's: one open request, 5 requests a day, a code
--     lives 10 minutes with 5 tries, 5 sends a minute apart, an email another
--     login, customer or sign-up has is refused, a rejection needs a note the
--     affiliate sees, the Audit Log row, the notice to the old address. A staff
--     decision also tells the new address (the Edge Function), since the
--     affiliate signs in with it from then on.
--
-- WHAT THIS DOES
--
--   * New column affiliate_detail_changes.current_inbox_lost (boolean, not
--     null, default false; the one request so far stays false).
--   * New function affiliate_detail_change_start_lost_inbox(uuid, jsonb), the
--     service role's alone, as 491's start: the same first checks, then the
--     row and a code for the new email. affiliate_detail_change_start is not
--     changed, nor are verify, resend, cancel, decide and finish: a request on
--     route 'staff' whose code is for the new email already goes through them
--     to pending_staff, and new_proven_at already makes the account verified.
--   * Replaces affiliate_detail_change_requests() (491's, md5 932f6c44...): the
--     staff list also says current_inbox_lost. Nothing else in it changes.
--
-- WHAT THE PERSON SEES (the pages and the Edge Function go with this file)
--
--   Affiliates: an "I can't open ..." choice in Your details on the Account
--   page; a code to the new email; then Your details says it waits for Energia
--   staff, and which email to sign in with once approved. Owners and Managers:
--   such a request says so on the Affiliates page, so they check who it is.
--   Production, 6 Nov 2026 (read only, counts only): 89 logins: 75 code, 1 staff,
--   3 free, 10 verify_first; 1 request ever (a name, 3 Nov); 0 emails changed.
--
-- NOT CHANGED
--
--   * Every other function, table, trigger and grant; affiliate_portal_details
--     (it already sends the request's new_email and which email its code is for).
--
-- NOT COVERED (told to the user)
--
--   * Someone who cannot open the inbox and has forgotten their password cannot
--     sign in to ask: the password reset goes to that inbox. The user's answer:
--     not now; such a case is done by hand, one at a time.
--   * The old address is told only once a change is made, not when it is asked
--     for. Staff checking who it is stands between a stolen password and the
--     account (the panel says so).
--   * An address taken after the request and before the decision: a login with
--     it makes the change fail as nothing changed (491); a customer record with
--     it is not looked at again (as 491's staff route).
--
-- DEPLOY ORDER (each step with the user's go-ahead in chat)
--
--   This file -> the Edge Function affiliate-details -> the pages. Before the
--   Edge Function, nothing calls the new function; before the pages, nobody can
--   ask for it. Pages first would send a flag an old Edge Function ignores, and
--   the code would go to the inbox they cannot open: keep this order.
--   1. Before applying, re-read supabase_migrations.schema_migrations and
--      origin/main (parallel sessions): 492 is the head (20261103094203).
--   2. Dry run on a copy of production as it is then (rc492_live: its fingerprint
--      must equal production's): this file wrapped, then the plain file again;
--      then scripts/affiliate-details/tests/details-lost-inbox-493.sql with
--      -v skip_install=1, and details-491.sql.
--   3. Apply wrapped, as 492's header writes it; read the history row back.
--   4. Read-only checks: the AFTER md5s, the fingerprint, the grant list.
--
-- BEFORE (production now, 6 Nov 2026; md5 of pg_get_functiondef with search_path
-- public; head 20261103094203)
--   changed: affiliate_detail_change_requests(): 932f6c446fe375cde6d1bd7a0e601187
--   relied on, not changed: c_relied / c_relied_md5 below (11 functions)
--   public function fingerprint: e42b527b89bff668e886be7770063519 (1414)
--   grant list: a888e7b83372dc4a0b75e6f0f6980d96
-- AFTER (for later guards)
--   affiliate_detail_change_requests(): e9f550aecf6c16f3b6512eef000664a3
--   affiliate_detail_change_start_lost_inbox(uuid,jsonb): 9ebb75d3cd775feeaed55a6d60910ffe
--   public function fingerprint, worked out on a copy of production: 94df2f805bd9045a4effffb1abbf6097 (1415: one added, one replaced)
--   grant list: adc6d01f05fb448e05c440649d63b453 (the new function's added)
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic whatever runs it: every check comes
--   before anything changes (the two texts' md5s; the 11 relied-on functions; the staff list is 491's or this
--   file's; the new function is absent or this file's; no overload of its name). Afterwards: the md5s, the
--   grants. Then a self-test in a block that is always undone (it ends by raising P0493): made-up records ("493
--   Check", @example.invalid, fictional +61 2 5550 phones): an Owner and an unverified login joined to a record
--   made a month before: 491's start refuses it, a code goes to the new email, a wrong code is refused, the right
--   one makes it wait, the staff list says the inbox is lost, approval changes the login's email and the record's
--   and verifies it, and a free login is refused. Two writes run with session_replication_role = replica for
--   that statement only (491's reason: the welcome WhatsApp's sequence number).
--
-- UNDO
--
--   Re-apply 491's text of affiliate_detail_change_requests (md5 932f6c44...) and
--   drop affiliate_detail_change_start_lost_inbox. Keep the column: its rows say
--   how those requests were made. Requests waiting then go on through staff as
--   any other.
--
-- Test: scripts/affiliate-details/tests/details-lost-inbox-493.sql (begin ...
-- rollback). Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ── What this makes or changes ──
  -- The start of a change for someone who cannot open their current email: as affiliate_detail_change_start, but the
  -- code goes to the new email and the request waits for an Owner or Manager (route staff).
  c_start constant text := 'affiliate_detail_change_start_lost_inbox(uuid,jsonb)';
  c_start_after constant text := '9ebb75d3cd775feeaed55a6d60910ffe';
  c_start_def constant text :=
$d1$CREATE OR REPLACE FUNCTION public.affiliate_detail_change_start_lost_inbox(p_uid uuid, p_new jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s jsonb; chk jsonb; r public.affiliate_detail_changes%rowtype; v_code text;
begin
  perform pg_advisory_xact_lock(hashtext('affiliate_detail_change:' || p_uid::text));
  update public.affiliate_detail_changes set status = 'expired', updated_at = now()
   where auth_user_id = p_uid and status = 'awaiting_code' and code_expires_at < now();
  -- a change the server never finished (it stopped between the login and the record)
  update public.affiliate_detail_changes set status = 'failed', failure = 'interrupted', updated_at = now()
   where auth_user_id = p_uid and status = 'applying' and updated_at < now() - interval '10 minutes';
  if exists (select 1 from public.affiliate_detail_changes where auth_user_id = p_uid
                and status in ('awaiting_code', 'pending_staff', 'applying')) then
    return jsonb_build_object('error', 'open_request'); end if;
  if (select count(*) from public.affiliate_detail_changes
       where auth_user_id = p_uid and created_at > now() - interval '24 hours') >= 5 then
    return jsonb_build_object('error', 'too_many_requests'); end if;
  s := public.affiliate_detail_state(p_uid);
  -- A verified login (code, staff) or an unverified one on a record its sign-up did not make (verify_first). A free
  -- login changes its email at once and needs no help; a closed one changes nothing here.
  if coalesce(s->>'route', '') not in ('code', 'staff', 'verify_first') then
    return jsonb_build_object('error', 'not_allowed'); end if;
  chk := public.affiliate_detail_check(p_uid, p_new);
  if chk ? 'error' then return chk; end if;
  -- The new inbox is all a code can prove here, so there must be one.
  if chk->'changes'->>'email' is null or chk->'changes'->>'email' = lower(coalesce(s->>'login_email', '')) then
    return jsonb_build_object('error', 'new_email_required', 'field', 'email'); end if;
  insert into public.affiliate_detail_changes (auth_user_id, customer_id, route, status, current_inbox_lost,
      old_first_name, old_last_name, old_phone, old_email, old_login_email,
      new_first_name, new_last_name, new_phone, new_email)
  values (p_uid, (s->>'customer_id')::uuid, 'staff', 'awaiting_code', true,
      s->>'first_name', s->>'last_name', s->>'phone', s->>'email', s->>'login_email',
      chk->'changes'->>'first_name', chk->'changes'->>'last_name', chk->'changes'->>'phone', chk->'changes'->>'email')
  returning * into r;
  v_code := public.affiliate_detail_new_code(r.id, 'new');
  return jsonb_build_object('request_id', r.id, 'route', 'staff', 'next', 'code',
    'send', jsonb_build_object('to', r.new_email, 'code', v_code, 'purpose', 'new'));
end $function$
$d1$;
  -- Staff: the requests that wait for an Owner or Manager; also (493) whether they said they cannot open their current email.
  c_req constant text := 'affiliate_detail_change_requests()';
  c_req_before constant text := '932f6c446fe375cde6d1bd7a0e601187';
  c_req_after constant text := 'e9f550aecf6c16f3b6512eef000664a3';
  c_req_def constant text :=
$d2$CREATE OR REPLACE FUNCTION public.affiliate_detail_change_requests()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can review detail changes' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'created_at', d.created_at, 'customer_id', d.customer_id,
            'customer_name', c.full_name,
            'old', jsonb_build_object('first_name', d.old_first_name, 'last_name', d.old_last_name, 'phone', d.old_phone,
                                      'email', d.old_email, 'login_email', d.old_login_email),
            'new', jsonb_strip_nulls(jsonb_build_object('first_name', d.new_first_name, 'last_name', d.new_last_name,
                                                        'phone', d.new_phone, 'email', d.new_email)),
            'signed_up_with', (select jsonb_build_object('name', coalesce(i.full_name, btrim(coalesce(i.first_name, '') || ' ' || coalesce(i.last_name, ''))),
                                                         'phone', i.phone, 'email', i.email)
                                 from public.affiliate_signup_identities i where i.auth_user_id = d.auth_user_id
                                order by i.created_at limit 1),
            'new_email_proven', d.new_proven_at is not null,
            -- 493: they say they cannot open their current email, so only the new one was confirmed
            'current_inbox_lost', d.current_inbox_lost) order by d.created_at)
      from public.affiliate_detail_changes d join public.customers c on c.id = d.customer_id
     where d.status = 'pending_staff'), '[]'::jsonb);
end $function$
$d2$;

  -- ── Relied on, not changed (production, 6 Nov 2026) ──
  c_relied constant text[] := array['affiliate_detail_state(uuid)', 'affiliate_detail_check(uuid,jsonb)', 'affiliate_detail_new_code(uuid,text)',
    'affiliate_detail_apply_plan(uuid)', 'affiliate_detail_change_start(uuid,jsonb)', 'affiliate_detail_change_verify(uuid,uuid,text)',
    'affiliate_detail_change_resend(uuid,uuid)', 'affiliate_detail_change_cancel(uuid,uuid)', 'affiliate_detail_change_decide(uuid,uuid,boolean,text)',
    'affiliate_detail_change_finish(uuid,boolean,text)', 'is_owner_or_manager()'];
  c_relied_md5 constant text[] := array['afa1c2b4c6564d37de6bb0a42064e0ef', '3a14e2ee54bbecf459fb243adaefaffa', 'ca3b1e9ab11c68431c91211f6859dd6b',
    '720dce0a6249c8c4207ed5b3fcf1d178', '75fde04f411fb5f7aea80f00150af92a', '372bdd69a2126481dacafad978a5f797',
    'e75a7529be9fcf90bb035e6809a16790', 'baec4a3a72f2b23bd1da5f012894a03b', '4ec23b88eb3c301ca8425f3cf21c3c53',
    '062ba7a48d170bf829ffd2dc33ea7ab1', 'a98e50f1b6d3fa1e6c62cf52a8073cc8'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_md5 text; v_smd5 text;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_ph text[]; t_uid uuid; t_cust uuid; t_aff uuid; t_owner uuid; t_srr text;
  r jsonb; t_id uuid; t_mail text; t_new text; t_code text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──
  if md5(c_start_def) <> c_start_after then
    raise exception '493: the text of public.% is not the tested one (md5 %)', c_start, md5(c_start_def); end if;
  if md5(c_req_def) <> c_req_after then
    raise exception '493: the text of public.% is not the tested one (md5 %)', c_req, md5(c_req_def); end if;
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '493: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  v_md5 := md5(pg_get_functiondef(to_regprocedure('public.' || c_req)));
  if v_md5 is null or v_md5 not in (c_req_before, c_req_after) then
    raise exception '493: public.% is neither 491''s nor this file''s (found md5 %). Re-read it and re-test before applying.', c_req, coalesce(v_md5, 'missing');
  end if;
  v_smd5 := md5(pg_get_functiondef(to_regprocedure('public.' || c_start)));
  if v_smd5 is distinct from c_start_after and v_smd5 is not null then
    raise exception '493: public.affiliate_detail_change_start_lost_inbox exists and is not this file''s (found md5 %). Re-read it and re-test before applying.', v_smd5;
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'affiliate_detail_change_start_lost_inbox'
              and p.oid::regprocedure::text <> c_start) then
    raise exception '493: another function takes the name affiliate_detail_change_start_lost_inbox'; end if;

  -- ── Change (a second run changes nothing) ──
  alter table public.affiliate_detail_changes add column if not exists current_inbox_lost boolean not null default false;
  comment on column public.affiliate_detail_changes.current_inbox_lost is
    '493: the affiliate said they cannot open their current email: the code went to the new email only, and an Owner or Manager decides.';
  execute c_start_def;
  revoke all on function public.affiliate_detail_change_start_lost_inbox(uuid, jsonb) from public, anon, authenticated;
  grant execute on function public.affiliate_detail_change_start_lost_inbox(uuid, jsonb) to service_role;
  execute c_req_def;

  -- ── Afterwards ──
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_req))) <> c_req_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_start))) <> c_start_after then
    raise exception '493: a function was installed with an md5 other than the tested one'; end if;
  if has_function_privilege('anon', to_regprocedure('public.' || c_start), 'execute')
     or has_function_privilege('authenticated', to_regprocedure('public.' || c_start), 'execute')
     or not has_function_privilege('service_role', to_regprocedure('public.' || c_start), 'execute') then
    raise exception '493: the new function must be runnable by the service role alone'; end if;
  if has_function_privilege('anon', to_regprocedure('public.' || c_req), 'execute')
     or not has_function_privilege('authenticated', to_regprocedure('public.' || c_req), 'execute') then
    raise exception '493: the staff list''s grants are not as they were'; end if;

  -- ── Self-test, in a block that is always undone (it ends by raising P0493) ──
  -- Made-up records only ("493 Check", @example.invalid, fictional +61 2 5550 phones).
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- (range scans of the two partial phone indexes, as 486's; the sign-up copies' phones normalised once)
    with ids as materialized (select public.normalize_customer_phone(i.phone) as p from public.affiliate_signup_identities i)
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from ids
                        where ids.p between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '493: the self-test found no free fictional phones'; end if;
    t_ph := array(select '+6125550' || lpad((t_base + n)::text, 4, '0') from generate_series(0, 1) n);
    t_mail := '493chk-' || t_sfx || '@example.invalid';
    t_new := '493chk-new-' || t_sfx || '@example.invalid';
    -- An Owner; and an unverified login joined to a record made a month before (route verify_first).
    insert into auth.users (id, email) values (gen_random_uuid(), '493chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '493 Check Owner', '493chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    insert into auth.users (id, email) values (gen_random_uuid(), t_mail) returning id into t_uid;
    insert into public.customers (first_name, last_name, full_name, phone, email, created_at)
    values ('Check', 'Affiliate', 'Check Affiliate', t_ph[1], t_mail, now() - interval '30 days') returning id into t_cust;
    insert into public.customer_affiliates (customer_id, status, activated_at, referral_code)
    values (t_cust, 'active', now(), '493CHK' || upper(t_sfx)) returning id into t_aff;
    -- the portal account with triggers off for this statement only (its welcome WhatsApp takes a sequence number)
    t_srr := current_setting('session_replication_role');
    set local session_replication_role = replica;
    insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (t_uid, t_cust, t_aff, 'claimed');
    execute format('set local session_replication_role = %L', t_srr);
    if public.affiliate_detail_state(t_uid)->>'route' <> 'verify_first' then
      raise exception '493: the self-test''s login should have to verify first, not %', public.affiliate_detail_state(t_uid)->>'route'; end if;

    -- 1. 491's start still refuses it; here a new email is needed.
    if public.affiliate_detail_change_start(t_uid, jsonb_build_object('email', t_new))->>'error' is distinct from 'verify_first'
       or public.affiliate_detail_change_start_lost_inbox(t_uid, jsonb_build_object('first_name', 'Checked'))->>'error' is distinct from 'new_email_required' then
      raise exception '493: the self-test''s refusals are not as tested'; end if;

    -- 2. The code goes to the new email, and nothing changes yet.
    r := public.affiliate_detail_change_start_lost_inbox(t_uid, jsonb_build_object('email', t_new));
    if r->>'next' is distinct from 'code' or r->'send'->>'to' is distinct from t_new or r->'send'->>'purpose' is distinct from 'new'
       or r->'send'->>'code' !~ '^[0-9]{6}$' then
      raise exception '493: the code did not go to the new email: %', r - 'send'; end if;
    t_id := (r->>'request_id')::uuid; t_code := r->'send'->>'code';
    if public.affiliate_detail_change_verify(t_uid, t_id, case when t_code = '000000' then '111111' else '000000' end)->>'error' is distinct from 'wrong_code' then
      raise exception '493: a wrong code was not refused'; end if;

    -- 3. The right code: it waits for staff, and the staff list says why.
    r := public.affiliate_detail_change_verify(t_uid, t_id, t_code);
    if r->>'next' is distinct from 'pending_staff'
       or (select status from public.affiliate_detail_changes d where d.id = t_id) is distinct from 'pending_staff'
       or (select email from auth.users where id = t_uid) is distinct from t_mail
       or (select email from public.customers where id = t_cust) is distinct from t_mail then
      raise exception '493: the right code should only make it wait for staff: %', r; end if;
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);
    if not exists (select 1 from jsonb_array_elements(public.affiliate_detail_change_requests()) x
                    where x->>'id' = t_id::text and (x->'current_inbox_lost')::boolean and (x->'new_email_proven')::boolean) then
      raise exception '493: the staff list does not say the current inbox is lost'; end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);

    -- 4. Approved: the login's email (as Supabase Auth's admin API changes it) and the record's; verified.
    r := public.affiliate_detail_change_decide(t_owner, t_id, true, null);
    if r->'apply'->>'login_email' is distinct from t_new then raise exception '493: the plan does not change the login email: %', r; end if;
    update auth.users set email = t_new where id = t_uid;
    r := public.affiliate_detail_change_finish(t_id, true, null);
    if r->>'status' is distinct from 'applied' or r->'notify'->>'to' is distinct from t_mail
       or (select email from public.customers where id = t_cust) is distinct from t_new
       or (select email_verified_at is null or login_email_changed_at is null from public.affiliate_accounts where auth_user_id = t_uid) then
      raise exception '493: the approved change was not applied as verified: %', r; end if;

    -- 5. A free login has no need of it.
    update public.affiliate_accounts set email_verified_at = null where auth_user_id = t_uid;
    update public.customers set created_at = (select a.created_at from public.affiliate_accounts a where a.auth_user_id = t_uid) where id = t_cust;
    if public.affiliate_detail_state(t_uid)->>'route' <> 'free'
       or public.affiliate_detail_change_start_lost_inbox(t_uid, jsonb_build_object('email', t_mail))->>'error' is distinct from 'not_allowed' then
      raise exception '493: a free login should not need this'; end if;

    raise exception using errcode = 'P0493', message = '493: self-test done, undone';
  exception when sqlstate 'P0493' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform pg_notify('pgrst', 'reload schema');
  perform set_config('search_path', v_path, true);
end $mig$;
