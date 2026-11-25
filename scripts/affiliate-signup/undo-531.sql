-- UNDO of 531 (with the user's go-ahead). From the security audit of 17 Nov 2026 (finding M6).
-- It puts auth_email_reserve (md5 e391dd05...), confirm_affiliate_email (8a0a7036...),
-- affiliate_whatsapp_enqueue (c88ad745...) and complete_affiliate_onboarding (0dd12d4c...) back to
-- their text before 531, drops auth_email_take,
-- affiliate_email_code_issue, confirm_affiliate_email_code and public.affiliate_email_codes (codes
-- not yet typed are gone), deletes the four limit rows 531 added, puts ('signup','ip') back to 30
-- an hour and the checks of public.auth_email_limits back to their actions and scopes before 531.
-- After it: no limit for all sign-ups or for the emails sent, a link from the inbox verifies an
-- email again (on the Account page, and at onboarding, where Supabase's own confirmation of a
-- login counts again too), and the welcome WhatsApp greets by the sign-up's name again with no daily limit
-- (the security audit's M6 open again). The grants of the four functions stay as they are. The
-- rate events written while 531 was in stay (the old reserve never counts 'send', 'send_staff',
-- 'email_day' or 'all'); the outbox rows skipped as 'daily_limit' stay skipped.
--
-- Undo the Edge Functions and the pages that call the new functions with their own commit, first:
-- until then their calls fail (sign-up and emails stop, closed, rather than unlimited).
--
-- It refuses, with nothing changed, while another function or a view uses 531's new functions or
-- its codes table, and unless the four functions are exactly 531's versions, the
-- new functions are 531's with 531's grants, the codes table and the limits' checks are as 531
-- left them and ('signup','ip') is 10 (so a later version is never overwritten). One
-- transaction, all or nothing; it waits at most 5 seconds for a lock. The 531 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row (found by
-- its name, 531_the_affiliate_sign_up_limits_and_email_codes) or record this UNDO beside it.
--
-- It also refuses while affiliate_whatsapp_message or affiliate_whatsapp_settle is not 394's
-- version: 537 (the affiliate WhatsApp as two messages, 24 Nov 2026) replaced both and relies on
-- 531's affiliate_whatsapp_enqueue. Run scripts/affiliate-whatsapp/undo-537.sql first. Undone under
-- 537, 531 would leave 537's words and settle on 394's enqueue, a state no script gets out of
-- (undo-537 and 531 would both refuse there; the security audit's check of 24 Nov 2026).
--
-- It ends by printing the fingerprint of every public function (md5 of their md5s, by
-- signature, and their count), to compare with the one taken before 531.
do $undo$
declare
  c_sig constant text[] := array[
    'auth_email_reserve(text,text,text)',
    'confirm_affiliate_email()',
    'affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)',
    'complete_affiliate_onboarding(text,text,text,boolean)'];
  c_531 constant text[] := array[
    'b5fdd6ba83a77beddb370c2a0e8114a1',
    '701c2626748dd8ab80aa4e36a3d2c036',
    '1b52d84e2842ef7709b86e2cbd03718d',
    '15f677725266f658f552051ae61e6d71'];
  c_before_531 constant text[] := array[
    'e391dd051d05f0661c7924f24e04a1b2',
    '8a0a7036312cf5dc22dd2beb82b3ce09',
    'c88ad74525019c20254a6927f4a802a3',
    '0dd12d4c9cef8b86bb1bcc02a5344927'];
  c_def constant text[] := array[
$fn$CREATE OR REPLACE FUNCTION public.auth_email_reserve(p_action text, p_email_hash text, p_ip_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_bucket        record;
  v_limit         record;
  v_used          integer;
  v_oldest        timestamptz;
  v_retry         integer;
  v_buckets       jsonb := '[]'::jsonb;
begin
  if p_action is null or p_action not in ('signup','resend','recovery') then
    raise exception 'AUTH_EMAIL_UNKNOWN_ACTION';
  end if;
  if p_email_hash is null or length(btrim(p_email_hash)) = 0 then
    raise exception 'AUTH_EMAIL_MISSING_EMAIL_KEY';
  end if;
  -- 405: a paused action (the Owner, 9 Oct 2026: public affiliate sign-up
  -- paused until the security fix is live) is refused before any slot is
  -- taken. The edge functions fail closed on this: nothing is created or sent.
  if exists (select 1 from public.auth_email_pauses ps where ps.action = p_action) then
    raise exception 'AUTH_EMAIL_PAUSED: %', p_action;
  end if;

  perform pg_advisory_xact_lock(hashtext('public.auth_email_reserve'));

  -- The buckets this request must fit inside.
  v_buckets := jsonb_build_array(jsonb_build_object('action', p_action, 'scope', 'email', 'key', p_email_hash));
  if p_ip_hash is not null and length(btrim(p_ip_hash)) > 0 then
    v_buckets := v_buckets
      || jsonb_build_array(jsonb_build_object('action', p_action,   'scope', 'ip', 'key', p_ip_hash))
      || jsonb_build_array(jsonb_build_object('action', 'combined', 'scope', 'ip', 'key', p_ip_hash));
  end if;

  -- Check every bucket first; only insert once all of them pass.
  for v_bucket in select * from jsonb_to_recordset(v_buckets) as x(action text, scope text, key text) loop
    select * into v_limit from public.auth_email_limits l
     where l.action = v_bucket.action and l.scope = v_bucket.scope;
    if not found then
      raise exception 'AUTH_EMAIL_LIMIT_NOT_CONFIGURED: % / %', v_bucket.action, v_bucket.scope;
    end if;

    select count(*), min(e.occurred_at) into v_used, v_oldest
      from public.auth_email_rate_events e
     where e.action = v_bucket.action
       and e.scope  = v_bucket.scope
       and e.key_hash = v_bucket.key
       and e.occurred_at > now() - make_interval(secs => v_limit.window_seconds);

    if v_used >= v_limit.max_attempts then
      v_retry := greatest(1, ceil(extract(epoch from
                   (v_oldest + make_interval(secs => v_limit.window_seconds)) - now()))::integer);
      return jsonb_build_object(
        'allowed', false,
        'retry_after_seconds', v_retry,
        'scope', v_bucket.scope,
        'action', v_bucket.action);
    end if;
  end loop;

  insert into public.auth_email_rate_events (action, scope, key_hash)
  select x.action, x.scope, x.key
    from jsonb_to_recordset(v_buckets) as x(action text, scope text, key text);

  return jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
end
$function$
$fn$,
$fn$CREATE OR REPLACE FUNCTION public.confirm_affiliate_email()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid(); v_acct public.affiliate_accounts%rowtype;
begin
  -- 437 (the Owner, 20 Oct 2026): an affiliate verifies their email later,
  -- from the Account page. Its email holds a sign-in link to
  -- /affiliate/verify; a session opened from it in the last 30 minutes marks
  -- the email verified. Nothing waits on it: the portal, the referral link,
  -- commission and payouts work the same before.
  if v_uid is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid for update;
  if not found then return jsonb_build_object('verified', false, 'reason', 'not_affiliate'); end if;
  if v_acct.email_verified_at is not null then
    return jsonb_build_object('verified', true, 'already', true, 'verified_at', v_acct.email_verified_at);
  end if;
  if not public.affiliate_session_from_email_link() then
    return jsonb_build_object('verified', false, 'reason', 'not_from_email_link');
  end if;
  -- 491: a link sent before the login's email last changed proved the old
  -- inbox, not the one the login has now.
  if v_acct.login_email_changed_at is not null
     and coalesce((select max((e->>'timestamp')::numeric)
                     from jsonb_array_elements(case when jsonb_typeof(auth.jwt()->'amr') = 'array'
                                                    then auth.jwt()->'amr' else '[]'::jsonb end) e
                    where e->>'method' in ('magiclink', 'otp', 'recovery', 'invite', 'email/signup')), 0)
         < extract(epoch from v_acct.login_email_changed_at) then
    return jsonb_build_object('verified', false, 'reason', 'email_changed_since_link');
  end if;
  update public.affiliate_accounts set email_verified_at = now(), updated_at = now()
   where id = v_acct.id returning * into v_acct;
  -- Kept on the login too (app_metadata, which only the server writes), so
  -- the account made at its next sign-in after an Owner unlinks it (378)
  -- starts verified; and the login no longer counts as one the sign-up
  -- confirmed on an address nobody proved (invite_user_provisioned).
  update auth.users
     set raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified')
                             || jsonb_build_object('affiliate_email_verified_at', v_acct.email_verified_at)
   where id = v_uid;
  -- Written straight into audit_logs (an affiliate has no staff profile for
  -- write_audit_ex to record), as sign-up's own rows are (432).
  begin
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, module)
    values ('affiliate_accounts', v_acct.id, 'affiliate_email_verified',
      jsonb_build_object('email_verified_at', null),
      jsonb_build_object('auth_user_id', v_uid, 'customer_id', v_acct.customer_id,
                         'email_verified_at', v_acct.email_verified_at),
      'affiliate');
  exception when others then
    raise warning '437: the email verification audit row was not saved: %', sqlerrm;
  end;
  return jsonb_build_object('verified', true, 'already', false, 'verified_at', v_acct.email_verified_at);
end $function$
$fn$,
$fn$CREATE OR REPLACE FUNCTION public.affiliate_whatsapp_enqueue(p_kind text, p_auth_user_id uuid, p_customer_id uuid, p_affiliate_id uuid, p_key text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 394: queues one affiliate WhatsApp, composed now. One that must not go out
-- is kept as 'skipped' with the reason. p_key makes it once only: a second
-- call with the same key adds nothing and returns null.
declare
  v_c public.customers%rowtype; v_a public.customer_affiliates%rowtype; v_acct public.affiliate_accounts%rowtype;
  v_meta jsonb; v_app text; v_name text; v_first text; v_phone text; v_digits text; v_cc text; v_skip text; v_id bigint;
begin
  select * into v_c from public.customers where id = p_customer_id;
  if p_affiliate_id is not null then
    select * into v_a from public.customer_affiliates where id = p_affiliate_id;
  else
    select * into v_a from public.customer_affiliates where customer_id = p_customer_id;
  end if;
  select * into v_acct from public.affiliate_accounts where auth_user_id = p_auth_user_id;
  select raw_user_meta_data into v_meta from auth.users where id = p_auth_user_id;
  select s.app_url into v_app from public.affiliate_whatsapp_settings s where s.id;
  v_app := coalesce(v_app, 'https://rev-22-energia-inventory-system.vercel.app');

  -- The name they gave at sign-up, else the customer's first name, else the
  -- first word of the full name; never the notes staff keep in brackets. The
  -- sign-up name is whatever the person typed, so a name is used only if it
  -- looks like one: letters, spaces, an apostrophe or a hyphen, at most 30
  -- characters. No digits, dots, slashes or colons: no link or phone number
  -- goes out in the greeting. None that does: "Hi there".
  foreach v_name in array array[v_meta->>'first_name', v_c.first_name,
                                split_part(public.affiliate_calendar_label(v_c.full_name), ' ', 1)] loop
    v_name := public.affiliate_calendar_label(v_name);
    if v_name ~ E'^[[:alpha:]][[:alpha:]''\u2019 -]{0,29}$' then
      v_first := v_name;
      exit;
    end if;
  end loop;

  -- The customer's phone, else the one given at sign-up. WbizTool takes the
  -- WhatsApp country code and the number apart.
  v_phone := coalesce(public.normalize_customer_phone(v_c.phone),
                      public.normalize_customer_phone(v_meta->>'phone'));
  v_digits := ltrim(v_phone, '+');
  v_cc := public.ads_wa_country_code(v_digits);

  v_skip := case
    when v_a.id is null or v_a.deleted_at is not null then 'affiliate_missing'
    when v_a.manually_suspended then 'affiliate_suspended'
    when v_a.status is distinct from 'active' then 'affiliate_' || v_a.status
    when v_c.id is null or v_c.deleted_at is not null then 'customer_deleted'
    when v_acct.id is null or v_acct.status is distinct from 'claimed' then 'login_not_linked'
    when v_a.referral_code is null then 'no_referral_code'
    when v_phone is null or v_cc is null then 'no_phone'
  end;

  insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, customer_id, auth_user_id, affiliate_id,
      phone_e164, wa_country_code, wa_number, first_name, referral_code, message, status, skip_reason)
  values (p_kind, p_key, p_customer_id, p_auth_user_id, v_a.id,
      v_phone, v_cc, case when v_cc is not null then substr(v_digits, length(v_cc) + 1) end,
      v_first, v_a.referral_code, public.affiliate_whatsapp_message(p_kind, v_first, v_app, v_a.referral_code),
      case when v_skip is null then 'queued' else 'skipped' end, v_skip)
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  return v_id;
end $function$
$fn$,
$fn$CREATE OR REPLACE FUNCTION public.complete_affiliate_onboarding(p_first_name text, p_last_name text, p_phone text, p_agree boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_email text; v_confirmed timestamptz; v_app jsonb; v_meta jsonb;
  v_first text; v_last text; v_raw_phone text; v_name text; v_phone text;
  v_acct public.affiliate_accounts%rowtype; v_aff public.customer_affiliates%rowtype;
  v_code text; v_suspended boolean := false;
  -- 437: the customers in use with the phone, those whose stored number could
  -- be it, those the name picks, the customer joined and by which rule, why a
  -- fresh record is listed for staff and whom it may be, the pending claims
  -- closed, the list entry, and whether the email counts as verified.
  v_holders uuid[]; v_maybe uuid[]; v_named uuid[]; v_target uuid; v_rule text; v_reason text;
  v_cust uuid; v_created boolean := false; v_cands uuid[] := '{}'::uuid[]; v_claim_cands uuid[] := '{}'::uuid[];
  v_claims int := 0; v_match uuid; v_verified timestamptz;
  -- 469: the customers with the phone (or a stored number that could be it)
  -- and the login's email inbox; why the sign-up waits for staff instead of
  -- getting an account, whom the claim suggests, and the claim parked.
  v_pe uuid[] := '{}'::uuid[]; v_park text; v_suggest uuid; v_claim uuid;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  -- Staff or Affiliate, never both. Checked before anything is written.
  if exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'STAFF_ACCOUNT: This is a staff login, so it cannot also be an affiliate account. Sign out and use a personal email address, or ask an Owner to set the affiliate up against the right customer record.'
      using errcode = '42501';
  end if;
  if not coalesce(p_agree, false) then raise exception 'You must agree to the Affiliate terms to continue'; end if;

  select lower(btrim(u.email)), u.email_confirmed_at, coalesce(u.raw_app_meta_data, '{}'::jsonb),
         coalesce(u.raw_user_meta_data, '{}'::jsonb)
    into v_email, v_confirmed, v_app, v_meta
    from auth.users u where u.id = v_uid;
  if coalesce(v_email, '') = '' then raise exception 'No email on the authenticated account'; end if;
  -- 437: a login is confirmed before it can sign in at all ("Confirm email"
  -- stays on in Supabase Auth); the sign-up function creates it confirmed.
  -- Kept as a backstop.
  if v_confirmed is null then raise exception 'Please verify your email before completing signup'; end if;

  -- Already onboarded? Answer before asking for anything (333).
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id = v_acct.affiliate_id;
    return jsonb_build_object('status', case when v_aff.manually_suspended then 'suspended' else 'active' end,
      'customer_id', v_acct.customer_id, 'referral_code', v_aff.referral_code, 'already', true,
      'email_verified', v_acct.email_verified_at is not null);
  end if;

  -- 437: a login whose claim was rejected stays rejected, whatever it enters
  -- (before, a phone and an email no customer had still made it a customer).
  if exists (select 1 from public.affiliate_account_claims where auth_user_id = v_uid and status = 'rejected') then
    return jsonb_build_object('status', 'rejected',
      'message', 'Account verification was unsuccessful. Please contact Energia for assistance.');
  end if;

  -- Arguments first; otherwise what the sign-up stored on the account (333).
  v_first     := nullif(btrim(coalesce(p_first_name, '')), '');
  v_last      := nullif(btrim(coalesce(p_last_name,  '')), '');
  v_raw_phone := nullif(btrim(coalesce(p_phone,      '')), '');
  if v_first is null and v_last is null then
    v_first := nullif(btrim(coalesce(v_meta->>'first_name', '')), '');
    v_last  := nullif(btrim(coalesce(v_meta->>'last_name',  '')), '');
  end if;
  if v_raw_phone is null then v_raw_phone := nullif(btrim(coalesce(v_meta->>'phone', '')), ''); end if;

  v_name  := btrim(coalesce(v_first, '') || ' ' || coalesce(v_last, ''));
  v_phone := public.normalize_customer_phone(v_raw_phone);
  if v_name = '' or v_raw_phone is null then
    raise exception 'DETAILS_REQUIRED: Enter your name and a valid international phone number.'; end if;
  if v_phone is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;

  -- One sign-up at a time for this login, then for this phone; asked again
  -- under the lock, so a second press of Create Account answers "already".
  perform pg_advisory_xact_lock(hashtextextended('affiliate-onboarding:' || v_uid::text, 0));
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid;
  if found then
    select * into v_aff from public.customer_affiliates where id = v_acct.affiliate_id;
    return jsonb_build_object('status', case when v_aff.manually_suspended then 'suspended' else 'active' end,
      'customer_id', v_acct.customer_id, 'referral_code', v_aff.referral_code, 'already', true,
      'email_verified', v_acct.email_verified_at is not null);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_phone, 0));

  -- 437 (the Owner, 20 Oct 2026, 7): the customers in use with this phone,
  -- and those whose stored number could be it (an 8-digit number that could
  -- be Singapore or Malaysia, as 425 reads it). One customer has it, and no
  -- other may: join them on the phone alone.
  select coalesce(array_agg(c.id order by c.created_at, c.id), '{}'::uuid[]) into v_holders
    from public.customers c
   where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_phone;
  select coalesce(array_agg(c.id order by c.created_at, c.id), '{}'::uuid[]) into v_maybe
    from public.customers c
   where c.deleted_at is null and public.normalize_customer_phone(c.phone) is null
     and c.phone ~ '^[\s().0-9-]+$'
     and (public.inspect_customer_phone(c.phone) -> 'candidates') ? v_phone;

  if cardinality(v_holders) = 1 and cardinality(v_maybe) = 0 then
    v_target := v_holders[1]; v_rule := 'phone';
  elsif cardinality(v_holders) > 0 then
    -- 8: several may have it. Join the one with the name exactly as typed;
    -- failing that, the one whose name has the same words (432's
    -- customer_names_match). Otherwise a fresh record, listed for staff.
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_named
      from public.customers c
     where c.id = any (v_holders) and public.normalize_customer_match_name(v_name) <> ''
       and public.normalize_customer_match_name(c.full_name) = public.normalize_customer_match_name(v_name);
    if cardinality(v_named) = 1 then
      v_target := v_named[1]; v_rule := 'phone_and_name';
    elsif cardinality(v_named) = 0 then
      select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_named
        from public.customers c
       where c.id = any (v_holders) and public.customer_names_match(c.full_name, v_name);
      if cardinality(v_named) = 1 then v_target := v_named[1]; v_rule := 'phone_and_same_words'; end if;
    end if;
    if v_target is null then v_reason := 'shared_phone'; end if;
  elsif cardinality(v_maybe) > 0 then
    -- Only a stored number that could be this one: not joined on it.
    v_reason := 'phone_unconfirmed';
  end if;

  -- 469 (the Owner, 24 Oct 2026: "if both phone number and email are the
  -- same, the customer should not duplicate, it should lead to the same
  -- customer"): when the phone and the name picked no one (above), the
  -- customers with the phone, or a stored number that could be it, whose
  -- email is the login's (customer_email_match_key: a Gmail inbox however it
  -- is written) decide. Exactly one, with the phone itself: joined (rule
  -- 'phone_and_email'), with the safeguards below as for any join. Several,
  -- or one whose stored number only could be it (never joined by itself, as
  -- above): no fresh record; the sign-up waits on a claim for staff (below).
  -- When the name matched SEVERAL customers on the phone (the Owner, later
  -- the same day: as 468 reads it for the QR health form), all the customers
  -- with the phone and the email count, not only those: exactly one, and it
  -- is one of the namesakes: joined to it; one of another name, or several
  -- (a namesake among them or not): no fresh record, the sign-up waits on a
  -- claim for staff suggesting no one (reason 'several_name_matches'); none:
  -- as before (a fresh record, listed). No email match: as before.
  if public.customer_email_match_key(v_email) is not null and cardinality(v_holders || v_maybe) > 0 then
    select coalesce(array_agg(c.id order by c.created_at, c.id), '{}'::uuid[]) into v_pe
      from public.customers c
     where c.id = any (v_holders || v_maybe)
       and public.customer_email_match_key(c.email) = public.customer_email_match_key(v_email);
  end if;
  if v_target is null and cardinality(v_pe) = 1 and v_pe[1] = any (v_holders)
     and (coalesce(cardinality(v_named), 0) <= 1 or v_pe[1] = any (v_named)) then
    v_target := v_pe[1]; v_rule := 'phone_and_email';
  elsif v_target is null and cardinality(v_pe) > 0 then
    v_park := case when coalesce(cardinality(v_named), 0) > 1 then 'several_name_matches'
                   when cardinality(v_pe) > 1 then 'several_phone_and_email'
                   else 'phone_unconfirmed_and_email' end;
    v_suggest := case when cardinality(v_pe) = 1 and coalesce(cardinality(v_named), 0) <= 1 then v_pe[1] end;
  end if;

  -- The safeguards kept: never joined by itself to a customer who already
  -- has a portal login (one each), one an Owner unlinked a login from (378),
  -- one an Owner or Manager rejected a claim for (379), or one whose
  -- affiliate record was removed. A fresh record instead, listed for staff.
  if v_target is not null then
    v_reason := case
      when exists (select 1 from public.affiliate_accounts a where a.customer_id = v_target) then 'customer_has_login'
      when exists (select 1 from public.audit_logs l
                    where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
                      and l.actor_role = 'owner' and l.module = 'affiliate'
                      and l.old_data->>'customer_id' = v_target::text)
        or exists (select 1 from public.audit_logs l
                    where l.table_name = 'affiliate_account_claims' and l.action = 'affiliate_claim_rejected'
                      and l.actor_role in ('owner', 'manager') and l.module = 'affiliate'
                      and l.new_data->>'candidate_customer_id' = v_target::text) then 'protected_customer'
      when exists (select 1 from public.customer_affiliates ca
                    where ca.customer_id = v_target and ca.deleted_at is not null) then 'affiliate_removed'
    end;
    -- 469: a customer with a portal login who has this phone and this email
    -- is the person signing up again (466 sends most of them to Sign in
    -- first): not a second affiliate account on a fresh record, but a claim
    -- for staff (below), suggesting them. A protected customer (378, 379) or
    -- one whose affiliate record was removed: a fresh record, listed, as
    -- before (an Owner or Manager has already decided about them).
    if v_reason = 'customer_has_login' and v_target = any (v_pe) then
      v_park := 'customer_has_login'; v_suggest := v_target;
    end if;
    if v_reason is not null then v_target := null; v_rule := null; end if;
  end if;

  -- 469: waits for staff, nothing made: a pending claim of this login (one
  -- at a time: a second sign-in finds it and answers the same) suggesting
  -- the one customer (none when several could be the person, as 432: on a
  -- shared phone staff link only a suggested customer, 378; an Owner or
  -- Manager links one that suggests no one), and the first time the login's
  -- sign-up copy (440's, below) and an Audit Log entry
  -- ('affiliate_claim_parked', 432's), written straight into audit_logs
  -- with no one signed in recorded. The verify page shows "Identity
  -- verification needed"; on the Affiliates page staff resolve, reject or
  -- delete it as any claim (378 and 379 unchanged).
  if v_park is not null then
    insert into public.affiliate_account_claims (auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
      values (v_uid, v_phone, v_email, v_suggest, v_name)
      on conflict do nothing
      returning id into v_claim;
    if v_claim is not null then
      -- 440's copy of what this login signed up with (the name and phone
      -- this sign-up used, the login's email), as 440 copied a pending
      -- claim's login: no account yet (source 'backfill'). Once staff
      -- resolve the claim the login has an account on that record, and the
      -- no-self-referral checks read this copy (affiliate_login_signup_details),
      -- as for any affiliate login. One with each claim parked.
      insert into public.affiliate_signup_identities (auth_user_id, affiliate_account_id, customer_id, first_name, last_name,
          full_name, phone, email, source, name_from, phone_from)
        values (v_uid, null, null, v_first, v_last, v_name, v_raw_phone, v_email, 'backfill',
          case when nullif(btrim(coalesce(p_first_name, '')), '') is null and nullif(btrim(coalesce(p_last_name, '')), '') is null
               then 'user_metadata' else 'arguments' end,
          case when nullif(btrim(coalesce(p_phone, '')), '') is null then 'user_metadata' else 'arguments' end);
      begin
        insert into public.audit_logs (table_name, record_id, action, new_data, module)
        values ('affiliate_account_claims', v_claim, 'affiliate_claim_parked',
          jsonb_build_object('auth_user_id', v_uid, 'candidate_customer_id', v_suggest, 'reason', v_park,
            'phone_and_email_customers', to_jsonb(v_pe), 'name_matches', to_jsonb(coalesce(v_named, '{}'::uuid[])),
            'phone_holders', cardinality(v_holders),
            'phone_unconfirmed_holders', cardinality(v_maybe), 'version', 469),
          'affiliate');
      exception when others then
        raise warning '469: the parked claim''s audit row was not saved: %', sqlerrm;
      end;
    end if;
    return jsonb_build_object('status', 'pending_verification',
      'message', 'We found an existing Energia customer record that needs identity verification. Please contact Energia to complete account linking.');
  end if;

  if v_target is not null then
    v_cust := v_target;
  else
    -- A fresh record. When 3 customers already have the phone, the phone
    -- rule (CUSTOMER_PHONE_LIMIT) refuses it, and the person enters another.
    insert into public.customers (full_name, phone, email, is_active)
      values (v_name, v_phone, v_email, true)
      returning id into v_cust;
    v_created := true; v_rule := 'fresh';
  end if;

  select * into v_aff from public.customer_affiliates where customer_id = v_cust and deleted_at is null;
  if not found then
    v_code := public.generate_affiliate_referral_code();
    insert into public.customer_affiliates (customer_id, status, manually_suspended, activated_at, referral_code)
      values (v_cust, 'active', false, now(), v_code)
      returning * into v_aff;
  else
    v_suspended := v_aff.manually_suspended;
    if v_aff.referral_code is null then
      update public.customer_affiliates set referral_code = public.generate_affiliate_referral_code(), updated_at = now()
       where id = v_aff.id returning * into v_aff;
    end if;
  end if;

  -- 437 (2): the app's own "email verified". Yes, from that day, when the
  -- login says it was verified before (app_metadata
  -- affiliate_email_verified_at: an account an Owner unlinked, 378); yes
  -- when Supabase Auth confirmed the login through its email link (every
  -- login before 437); no when the sign-up function or the 437 repair
  -- confirmed it (app_metadata.affiliate_email_unverified; the server alone
  -- sets either); yes now when this session was opened from an emailed link,
  -- which the login then keeps too.
  v_verified := case
    when coalesce(v_app->>'affiliate_email_verified_at', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
      then (v_app->>'affiliate_email_verified_at')::timestamptz
    when coalesce(v_app->>'affiliate_email_unverified', '') = 'true' then null
    else v_confirmed end;
  if v_verified is null and public.affiliate_session_from_email_link() then
    v_verified := now();
    update auth.users
       set raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified')
                               || jsonb_build_object('affiliate_email_verified_at', v_verified)
     where id = v_uid;
  end if;

  -- An entry still open for this login is for a customer it is no longer on
  -- (an Owner unlinked it: it had no account until now). It goes; an entry
  -- made below takes its place.
  delete from public.affiliate_signup_matches where auth_user_id = v_uid and status = 'open';

  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status, last_login_at, email_verified_at)
    values (v_uid, v_cust, v_aff.id, 'claimed', now(), v_verified)
    returning * into v_acct;

  -- 440 (the Owner, 21 Oct 2026, A): the server's own copy of what this login
  -- signed up with, which she cannot edit (her raw_user_meta_data she can,
  -- with updateUser): the name and phone this sign-up used (the page's,
  -- else the account's, as above) and the login's email now. Written once,
  -- with the account, for a new customer, a phone join and a fresh record
  -- alike; nothing changes it (affiliate_signup_identities). The
  -- no-self-referral checks read it (affiliate_login_signup_details).
  insert into public.affiliate_signup_identities (auth_user_id, affiliate_account_id, customer_id, first_name, last_name,
      full_name, phone, email, source, name_from, phone_from)
    values (v_uid, v_acct.id, v_cust, v_first, v_last, v_name, v_raw_phone, v_email, 'onboarding',
      case when nullif(btrim(coalesce(p_first_name, '')), '') is null and nullif(btrim(coalesce(p_last_name, '')), '') is null
           then 'user_metadata' else 'arguments' end,
      case when nullif(btrim(coalesce(p_phone, '')), '') is null then 'user_metadata' else 'arguments' end);

  -- 437 (5): a pending claim of this login is settled the new way: closed,
  -- the person in. Whom it suggested is listed with a fresh record.
  with closed as (
    update public.affiliate_account_claims
       set status = 'resolved', resolved_at = now(),
           resolution_note = '437: let in at sign-in (the Owner, 20 Oct 2026)'
     where auth_user_id = v_uid and status = 'pending'
    returning candidate_customer_id)
  select count(*)::int, coalesce(array_agg(candidate_customer_id) filter (where candidate_customer_id is not null), '{}'::uuid[])
    into v_claims, v_claim_cands from closed;

  -- 437 (6): a fresh record that may be a customer already there is listed
  -- on the Affiliates page, for an Owner or Manager to link or keep apart.
  -- The person is not told, and never sees the other names.
  if v_created then
    v_cands := public.affiliate_signup_candidates(v_cust, v_phone, v_name, v_email);
    v_cands := v_cands || coalesce(array(
      select x from unnest(v_claim_cands) x
       where x <> all (v_cands) and x <> v_cust
         and exists (select 1 from public.customers c where c.id = x and c.deleted_at is null)), '{}'::uuid[]);
    if v_reason is null and cardinality(v_cands) > 0 then
      v_reason := case
        when exists (select 1 from public.customers c where c.id = any (v_cands)
                      and public.customer_email_match_key(c.email) = public.customer_email_match_key(v_email)) then 'email_match'
        when exists (select 1 from public.customers c where c.id = any (v_cands) and c.id <> all (v_claim_cands)) then 'name_match'
        else 'earlier_claim' end;
    end if;
    if v_reason is not null then
      insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, entered_phone, entered_name, reason, candidate_ids)
        values (v_uid, v_cust, v_phone, v_name, v_reason, v_cands)
        on conflict do nothing
        returning id into v_match;
    end if;
  elsif v_rule is distinct from 'phone_and_email' then
    -- 508: every login joined to a record that was there before is listed,
    -- on the phone alone or on the phone and the name, whatever name was
    -- typed. Until an Owner or Manager says Same person the portal shows that
    -- login nothing of the record (affiliate_portal_record_id). One joined on
    -- the phone and the record's email is not listed: it proves itself when
    -- it verifies that email. Before 508 only a different name was listed:
    -- AFF-SIGNUP-18 (the Owner, 21 Oct 2026): joined on the phone alone (7)
    -- under a name that is not the record's (not the same words): the join
    -- stays as it is, and it is listed for an Owner or Manager as "may be
    -- someone else" (a family member on the household phone, say), with the
    -- name typed and the record's. Same person closes the entry
    -- (confirm_affiliate_signup_same_person); someone else: an Owner unlinks
    -- the login (378) and the person gets a record of their own at their
    -- next sign-in. It is never linked (there is no new record to merge):
    -- the entry names the customer joined. The person is not told.
    v_reason := 'phone_other_name';
    insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, entered_phone, entered_name, reason, candidate_ids)
      values (v_uid, v_cust, v_phone, v_name, v_reason, '{}'::uuid[])
      on conflict do nothing
      returning id into v_match;
  end if;

  -- Written straight into audit_logs, with no one signed in recorded (432).
  -- It cannot stop the sign-up. It says which rule joined the customer or
  -- that a fresh record was made, and why it is listed.
  begin
    insert into public.audit_logs (table_name, record_id, action, new_data, module)
    values ('affiliate_accounts', v_acct.id, 'affiliate_portal_claimed',
      jsonb_build_object('customer_id', v_cust, 'affiliate_id', v_aff.id, 'auth_user_id', v_uid,
        'new_customer', v_created, 'rule', v_rule, 'listed_for_staff', v_reason, 'match_id', v_match,
        'claims_closed', v_claims, 'email_verified', v_verified is not null, 'version', 437),
      'affiliate');
  exception when others then
    raise warning '437: the sign-up audit row was not saved: %', sqlerrm;
  end;

  return jsonb_build_object('status', case when v_suspended then 'suspended' else 'active' end,
    'customer_id', v_cust, 'referral_code', v_aff.referral_code, 'already', false,
    'new_customer', v_created, 'email_verified', v_verified is not null);
end $function$
$fn$];
  c_acl constant text[] := array[
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_new_sig constant text[] := array[
    'auth_email_take(text,text,uuid,text,text)',
    'affiliate_email_code_issue(uuid)',
    'confirm_affiliate_email_code(text)'];
  c_new_md5 constant text[] := array[
    '17a3702da427e408526a184e06d4f662',
    '829da32b75af310c200fbbba20df03b7',
    'a56f471685007ee0dad071c9e98d633e'];
  c_new_acl constant text[] := array[
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_codes_cols constant text :=
    'id uuid NO,auth_user_id uuid NO,email text NO,code_hash text NO,created_at timestamp with time zone NO,expires_at timestamp with time zone NO,tries integer NO,used_at timestamp with time zone YES,retired_at timestamp with time zone YES';
  c_codes_idx constant text[] := array[
    'CREATE INDEX idx_affiliate_email_codes_login_time ON public.affiliate_email_codes USING btree (auth_user_id, created_at DESC)',
    'CREATE UNIQUE INDEX affiliate_email_codes_pkey ON public.affiliate_email_codes USING btree (id)'];
  c_codes_con constant text[] := array[
    'affiliate_email_codes_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE',
    'affiliate_email_codes_code_hash_is_a_hash CHECK ((code_hash ~ ''^[0-9a-f]{64}$''::text))',
    'affiliate_email_codes_pkey PRIMARY KEY (id)',
    'affiliate_email_codes_tries_check CHECK (((tries >= 0) AND (tries <= 5)))'];
  c_codes_acl constant text := 'postgres=arwdDxtm/postgres';
  c_lim_con_before constant text[] := array[
    'auth_email_limits_action_check CHECK ((action = ANY (ARRAY[''signup''::text, ''resend''::text, ''recovery''::text, ''combined''::text])))',
    'auth_email_limits_max_attempts_check CHECK ((max_attempts > 0))',
    'auth_email_limits_pkey PRIMARY KEY (action, scope)',
    'auth_email_limits_scope_check CHECK ((scope = ANY (ARRAY[''email''::text, ''ip''::text])))',
    'auth_email_limits_window_seconds_check CHECK ((window_seconds > 0))'];
  c_lim_con_after constant text[] := array[
    'auth_email_limits_action_check CHECK ((action = ANY (ARRAY[''signup''::text, ''resend''::text, ''recovery''::text, ''combined''::text, ''send''::text, ''send_staff''::text, ''email_day''::text])))',
    'auth_email_limits_max_attempts_check CHECK ((max_attempts > 0))',
    'auth_email_limits_pkey PRIMARY KEY (action, scope)',
    'auth_email_limits_scope_check CHECK ((scope = ANY (ARRAY[''email''::text, ''ip''::text, ''all''::text])))',
    'auth_email_limits_window_seconds_check CHECK ((window_seconds > 0))'];
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  -- 537 replaced 394's affiliate_whatsapp_message and affiliate_whatsapp_settle and relies on
  -- 531's enqueue, while 531 relies on 394's message: undo 537 (or whatever later replaced
  -- them) first.
  if md5(pg_get_functiondef('public.affiliate_whatsapp_message(text,text,text,text)'::regprocedure))
       <> '6cab1d437121fb0942f90dd7ec7c5310'
     or md5(pg_get_functiondef('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)'::regprocedure))
       <> '950a44ad565eada10199a3ccfc0e20bb' then
    raise exception 'undo-531: affiliate_whatsapp_message or affiliate_whatsapp_settle is not 394''s version (537 is in, or one of them was changed by hand). Run scripts/affiliate-whatsapp/undo-537.sql first. Nothing changed.'; end if;
  for i in 1 .. cardinality(c_def) loop
    if md5(c_def[i]) <> c_before_531[i] then
      raise exception 'undo-531: the text kept for public.% is not its version before 531', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_531[i] then
      raise exception 'undo-531: public.% is not 531''s version; nothing changed', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo-531: the grants of public.% are not 531''s; nothing changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i] then
      raise exception 'undo-531: public.% is not as 531 made it; nothing changed', c_new_sig[i]; end if;
  end loop;
  if to_regclass('public.affiliate_email_codes') is null
     or (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
           from information_schema.columns where table_schema = 'public' and table_name = 'affiliate_email_codes') is distinct from c_codes_cols
     or (select array_agg(pg_get_indexdef(x.indexrelid) order by pg_get_indexdef(x.indexrelid))
           from pg_index x where x.indrelid = 'public.affiliate_email_codes'::regclass) is distinct from c_codes_idx
     or (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
           from pg_constraint c where c.conrelid = 'public.affiliate_email_codes'::regclass) is distinct from c_codes_con
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_class c, unnest(c.relacl) x where c.oid = 'public.affiliate_email_codes'::regclass) is distinct from c_codes_acl then
    raise exception 'undo-531: public.affiliate_email_codes is not as 531 made it; nothing changed'; end if;
  -- Nothing else may call the new functions or read the codes table (a later migration, a view):
  -- undo that first.
  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
                and p.oid not in (select to_regprocedure('public.' || x) from unnest(c_sig || c_new_sig) x)
                and pg_get_functiondef(p.oid) ~ '(auth_email_take|affiliate_email_code_issue|confirm_affiliate_email_code|affiliate_email_codes)')
     or exists (select 1 from pg_views v where v.schemaname = 'public'
                   and v.definition ~ '(auth_email_take|affiliate_email_code_issue|confirm_affiliate_email_code|affiliate_email_codes)') then
    raise exception 'undo-531: another function or view uses auth_email_take, affiliate_email_code_issue, confirm_affiliate_email_code or public.affiliate_email_codes; undo that first. Nothing changed.'; end if;
  -- Nothing else may hang on the table (a view, a foreign key from another table).
  if exists (select 1 from pg_depend d where d.refobjid = 'public.affiliate_email_codes'::regclass
                and d.classid = 'pg_rewrite'::regclass)
     or exists (select 1 from pg_constraint c where c.confrelid = 'public.affiliate_email_codes'::regclass) then
    raise exception 'undo-531: something else uses public.affiliate_email_codes; nothing changed'; end if;
  if (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
        from pg_constraint c where c.conrelid = 'public.auth_email_limits'::regclass) is distinct from c_lim_con_after then
    raise exception 'undo-531: the checks of public.auth_email_limits are not 531''s; nothing changed'; end if;
  if (select l.max_attempts from public.auth_email_limits l where l.action = 'signup' and l.scope = 'ip') is distinct from 10 then
    raise exception 'undo-531: the limit (signup, ip) is not 531''s 10; nothing changed'; end if;
  if exists (select 1 from public.auth_email_limits l
              where (l.action in ('send', 'send_staff', 'email_day') or l.scope = 'all')
                and (l.action, l.scope) not in (('signup', 'all'), ('send', 'all'), ('send_staff', 'all'), ('email_day', 'email'))) then
    raise exception 'undo-531: public.auth_email_limits has a row with 531''s actions or scope that 531 did not add; nothing changed'; end if;

  -- 2. Undo
  for i in 1 .. cardinality(c_sig) loop
    execute c_def[i];
  end loop;
  drop function public.auth_email_take(text, text, uuid, text, text);
  drop function public.affiliate_email_code_issue(uuid);
  drop function public.confirm_affiliate_email_code(text);
  drop table public.affiliate_email_codes;
  delete from public.auth_email_limits
   where (action, scope) in (('signup', 'all'), ('send', 'all'), ('send_staff', 'all'), ('email_day', 'email'));
  update public.auth_email_limits set max_attempts = 30, updated_at = now()
   where action = 'signup' and scope = 'ip' and max_attempts = 10;
  alter table public.auth_email_limits drop constraint auth_email_limits_action_check;
  alter table public.auth_email_limits add constraint auth_email_limits_action_check
    check (action in ('signup', 'resend', 'recovery', 'combined'));
  alter table public.auth_email_limits drop constraint auth_email_limits_scope_check;
  alter table public.auth_email_limits add constraint auth_email_limits_scope_check
    check (scope in ('email', 'ip'));

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before_531[i] then
      raise exception 'undo-531: public.% is not its version before 531 after the undo', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo-531: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  if (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
        from pg_constraint c where c.conrelid = 'public.auth_email_limits'::regclass) is distinct from c_lim_con_before then
    raise exception 'undo-531: the checks of public.auth_email_limits are not as before 531 after the undo'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('auth_email_take', 'affiliate_email_code_issue', 'confirm_affiliate_email_code'))
     or to_regclass('public.affiliate_email_codes') is not null then
    raise exception 'undo-531: a function or the table 531 made is still there'; end if;

  raise notice 'undo-531: done; the public functions'' fingerprint is now %',
    (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p'));
  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
