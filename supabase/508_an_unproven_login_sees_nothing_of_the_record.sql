-- 508_an_unproven_login_sees_nothing_of_the_record.sql
--
-- A LOGIN WHOSE LINK TO A CUSTOMER IS NOT PROVEN SEES NOTHING OF THAT CUSTOMER'S RECORD
--
--   From the security audit of 17 Nov 2026 (finding H1).
--   The BEFORE md5s below were compared with production on 17 Nov 2026 (head 502): every
--   one matched. If production's text differs on the day, this file refuses and changes
--   nothing: re-read and re-test.
--   (The number 508 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- THE OWNER DECIDED THIS RULE on 17 Nov 2026 ("hide until proven"). On 20 and 21 Oct 2026
-- the Owner decided that a sign-up joins the customer who holds the phone number at once,
-- on the phone alone (437, point 7; AFF-SIGNUP-18). This file keeps that. It changes what
-- such a login is SHOWN until its link to the record is proven: only what the login itself
-- typed, never the record's stored details, referral tree, purchases, earnings or payouts.
--
-- WHAT WAS WRONG
--
--   The join page makes a login that is already confirmed (auth-signup-request,
--   email_confirm: true), and complete_affiliate_onboarding attaches it to the one customer
--   who holds the typed phone. Nothing is proven: not the phone, not the name, not the email.
--   The portal then showed that login the customer's name, phone and email on file, the
--   people under them with their spend and bookings, each commissionable purchase, earnings
--   and payouts. Anyone who knows a customer's mobile number could read that customer's
--   record. Tier 1 phone numbers and changing details already ask for a proven link
--   (484, 491); the rest of the portal did not.
--
-- WHAT THIS DOES
--
--   1. affiliate_portal_record_id() (new, internal): the record the portal may show. The
--      record when affiliate_login_link_proof says the link is proven; the nil id when the
--      login is joined but not proven; null when it is not a portal login.
--   2. The six pages' functions read through it: dashboard, earnings, payouts, purchases,
--      network, campaign progress. For an unproven login every list is empty and every
--      total zero, in the usual shape.
--   3. affiliate_portal_me: an unproven login gets the name it typed at sign-up, not the
--      record's, no count of referrals, no date the record became an affiliate, and
--      link_proven false (new key; true otherwise). The page shows a notice from it.
--   4. affiliate_portal_details: an unproven login gets the details it typed at sign-up,
--      not the record's, and link_proven false.
--   5. affiliate_portal_referral_info: an unproven login still gets the referral code and
--      links (referrals made with them go to the record's owner), but no count of the
--      record's referrals.
--   6. complete_affiliate_onboarding: every login joined to a record that was there before,
--      on the phone alone or on the phone and the name, is listed for an Owner or Manager
--      (it was listed only when the name differed). "Same person" on that list is what
--      proves the link. One joined on the phone and the record's email is not listed: it
--      proves itself when it verifies that email.
--   7. Logins joined before this migration whose link is not proven are listed the same way,
--      once, on the run that installs this (not on a re-run, so an entry staff closed as
--      Keep separate is not listed again). The NOTICE says how many.
--
-- BEFORE APPLYING: count who is affected. Every login this counts will see the "we are
-- checking your account" notice until an Owner or Manager presses Same person, or it
-- verifies an email that is the record's (10 on production on 17 Nov 2026):
--     select count(*) from public.affiliate_accounts a join public.customers c on c.id = a.customer_id
--      where a.status = 'claimed' and c.deleted_at is null
--        and public.affiliate_login_link_proof(a.auth_user_id, a.customer_id) is null;
--
-- WHAT THIS LEAVES ALONE
--
--   * The join itself, and the referral code and link, which an unproven login still gets.
--   * The staff list's wording for these entries ("may be someone else") and its reason code
--     'phone_other_name', now also used when the name is the same.
--   * A real customer whose record an impostor joined first still cannot join it until an
--     Owner unlinks the impostor (378).
--   * affiliate_portal_me still returns the record's id (customer_id) and referral code to
--     an unproven login; neither is a stored personal detail, and no portal function takes
--     an id from the browser.
--
-- LATER MIGRATIONS: 509 (a suspended affiliate's portal shows nothing) builds on this one.
-- It changes affiliate_portal_me, affiliate_portal_details, current_affiliate_customer_id
-- and affiliate_detail_state again; a re-run of this file after 509 finds 509's versions
-- (c_later, c_relied_later) and leaves everything alone.
--
-- UNDO: run the swap back by hand: each c_new text replaced by its c_anchor in the
-- function's definition (pg_get_functiondef), checked against c_before, then
-- drop function public.affiliate_portal_record_id(). The list entries of point 7 are
-- ordinary open entries: staff close them with Same person or Keep separate. Undo 509 first.
--
-- NO SELF-TEST INSIDE; the suite is scripts/affiliate-signup/tests/unproven-link-portal-508.sql.
--
-- One transaction with its history row, by the usual wrapper. It writes the list entries of
-- point 7 and nothing else.

do $mig$
declare
  -- The function(s) this patches: BEFORE (production on 17 Nov 2026) and AFTER md5s
  c_sig constant text[] := array[
    'affiliate_portal_dashboard()',
    'affiliate_portal_earnings()',
    'affiliate_portal_payouts()',
    'affiliate_portal_purchases()',
    'affiliate_portal_network()',
    'affiliate_portal_campaign_progress()',
    'affiliate_portal_me()',
    'affiliate_portal_details()',
    'complete_affiliate_onboarding(text,text,text,boolean)',
    'affiliate_portal_referral_info()'];
  c_before constant text[] := array[
    'c2b341ff3f06f4b59111d7d7c4e72c5b',
    'b3db0cbb15706d57b0b4726406a176b7',
    '4d0a55938ac39876c1a9cd94d4673991',
    'a5e5c99ae092d2fbea35f3f7d8dc90f0',
    '5506f7291146534551a25e52a1e7820b',
    'f80c238a0bcf14de9463a26db3b12bc1',
    'c1fdcd47e76de0b1188bd453d339e903',
    'ba9dc218a31682d40738480ac9d89d42',
    '1b9dfc819b860dcb19244063a4628f47',
    '42453f972e0349eb1353e231a659fa55'];
  c_after constant text[] := array[
    '7831d1cb5a40b59af9392a3ce279bb6a',
    '4937f6820287a09efebb8d3108265eb4',
    '45c08362698f38567ec7696851fa46b3',
    'f7c724ed4eaa6c81f1ce2e2d4e709bae',
    '74ab159218853fcf22e1ccd9d75dcded',
    'cc07104f1bda30a36468f615c9fbb410',
    'ac16da58b1c43324d6b56f4902133042',
    '80b6186a7cdd097eadbaa38d38abdf57',
    '0dd12d4c9cef8b86bb1bcc02a5344927',
    '7f20a8bfbdc31905266852edda2f5def'];
  -- A later migration's version of a function this patches (509), or null: found, this
  -- file has been applied and built on, and leaves it alone.
  c_later constant text[] := array[
    null, null, null, null, null, null,
    '8b4f230b27adb0acd0b0eb658412fe01',
    '505ad742085b0dda5eb6950522bd6356',
    null, null];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. An undo swaps them back.
  c_fn constant int[] := array[1, 2, 3, 4, 5, 6, 7, 7, 7, 7, 7, 8, 8, 9, 10];
  c_anchor constant text[] := array[
$a$v_me uuid := public.current_affiliate_customer_id()$a$,
$a$v_me uuid := public.current_affiliate_customer_id()$a$,
$a$v_me uuid := public.current_affiliate_customer_id()$a$,
$a$v_me uuid := public.current_affiliate_customer_id()$a$,
$a$v_me uuid := public.current_affiliate_customer_id()$a$,
$a$v_me uuid := public.current_affiliate_customer_id()$a$,
$a$v_acct public.affiliate_accounts%rowtype; v_email text;$a$,
$a$  select email into v_email from auth.users where id = v_acct.auth_user_id;
$a$,
$a$    'customer_id', v_me, 'name', v_c.full_name, 'email', v_email,$a$,
$a$    'joined_at', v_a.activated_at,$a$,
$a$    'direct_referrals', (select count(*) from public.customers where referred_by = v_me and deleted_at is null));$a$,
$a$declare v_uid uuid := auth.uid(); s jsonb; v_req jsonb;$a$,
$a$  return jsonb_build_object('route', s->'route', 'verified', s->'verified',
    'first_name', s->'first_name', 'last_name', s->'last_name', 'phone', s->'phone', 'email', s->'email',
    'login_email', s->'login_email', 'request', v_req);$a$,
$a$  elsif v_rule = 'phone'
        and not exists (select 1 from public.customers c
                         where c.id = v_cust
                           and ((public.normalize_customer_match_name(v_name) <> ''
                                 and public.normalize_customer_match_name(c.full_name) = public.normalize_customer_match_name(v_name))
                                or public.customer_names_match(c.full_name, v_name))) then$a$,
$a$    'direct_referrals', (select count(*) from public.customers where referred_by = v_me and deleted_at is null),$a$];
  c_new constant text[] := array[
$n$v_me uuid := public.affiliate_portal_record_id()$n$,
$n$v_me uuid := public.affiliate_portal_record_id()$n$,
$n$v_me uuid := public.affiliate_portal_record_id()$n$,
$n$v_me uuid := public.affiliate_portal_record_id()$n$,
$n$v_me uuid := public.affiliate_portal_record_id()$n$,
$n$v_me uuid := public.affiliate_portal_record_id()$n$,
$n$v_acct public.affiliate_accounts%rowtype; v_email text;
        v_proof text; v_typed text;  -- 508$n$,
$n$  select email into v_email from auth.users where id = v_acct.auth_user_id;
  -- 508: until the login's link to the record is proven, the page gets the
  -- name the login typed at sign-up, not the record's, and no count of the
  -- record's referrals. link_proven tells the page which it is.
  v_proof := public.affiliate_login_link_proof(auth.uid(), v_me);
  if v_proof is null then
    select i.full_name into v_typed from public.affiliate_signup_identities i
     where i.auth_user_id = auth.uid() order by i.created_at desc limit 1;
  end if;
$n$,
$n$    'customer_id', v_me, 'name', case when v_proof is null then v_typed else v_c.full_name end, 'email', v_email,
    'link_proven', v_proof is not null,$n$,
$n$    'joined_at', case when v_proof is null then null else v_a.activated_at end,$n$,
$n$    'direct_referrals', case when v_proof is null then 0
                             else (select count(*) from public.customers where referred_by = v_me and deleted_at is null) end);$n$,
$n$declare v_uid uuid := auth.uid(); s jsonb; v_req jsonb;
        v_i public.affiliate_signup_identities%rowtype;  -- 508$n$,
$n$  -- 508: until the login's link to the record is proven, the page gets the
  -- details the login typed at sign-up, not the record's.
  if s->>'proof' is null then
    select * into v_i from public.affiliate_signup_identities i
     where i.auth_user_id = v_uid order by i.created_at desc limit 1;
    return jsonb_build_object('route', s->'route', 'verified', s->'verified',
      'first_name', v_i.first_name, 'last_name', v_i.last_name, 'phone', v_i.phone, 'email', v_i.email,
      'login_email', s->'login_email', 'request', v_req, 'link_proven', false);
  end if;
  return jsonb_build_object('route', s->'route', 'verified', s->'verified',
    'first_name', s->'first_name', 'last_name', s->'last_name', 'phone', s->'phone', 'email', s->'email',
    'login_email', s->'login_email', 'request', v_req, 'link_proven', true);$n$,
$n$  elsif v_rule is distinct from 'phone_and_email' then
    -- 508: every login joined to a record that was there before is listed,
    -- on the phone alone or on the phone and the name, whatever name was
    -- typed. Until an Owner or Manager says Same person the portal shows that
    -- login nothing of the record (affiliate_portal_record_id). One joined on
    -- the phone and the record's email is not listed: it proves itself when
    -- it verifies that email. Before 508 only a different name was listed:$n$,
$n$    -- 508: no count of the record's referrals until the login's link is proven
    'direct_referrals', case when public.affiliate_login_link_proof(auth.uid(), v_me) is null then 0
                             else (select count(*) from public.customers where referred_by = v_me and deleted_at is null) end,$n$];
  -- Relied on, not changed. c_relied_later: a later migration's version (509), or null.
  c_relied constant text[] := array[
    'affiliate_login_link_proof(uuid,uuid)',
    'current_affiliate_customer_id()',
    'confirm_affiliate_signup_same_person(uuid,text)',
    'affiliate_detail_state(uuid)'];
  c_relied_md5 constant text[] := array[
    '2484fb464733c124213b96152837a660',
    '51695acf5f26ce3918d6003d0c980b0f',
    'a9a1f6c2d37284e1e19d898ebdd203e6',
    'afa1c2b4c6564d37de6bb0a42064e0ef'];
  c_relied_later constant text[] := array[
    null,
    '4f552894d48ef799c071d4b95c37745d',
    null,
    '42c84668858277a0355208541c0c4c5c'];
  -- The new helper, and its md5 once installed
  c_helper_def constant text := $def$CREATE OR REPLACE FUNCTION public.affiliate_portal_record_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 508: the customer record the portal may show to the login that asks.
  --   null        not a portal login (as current_affiliate_customer_id());
  --   the record  its link to this login is proven (affiliate_login_link_proof);
  --   the nil id  joined, not proven yet. No row has that id, so every list
  --               comes back empty and every total zero, in the usual shape.
  select case
           when a.customer_id is null then null::uuid
           when public.affiliate_login_link_proof(auth.uid(), a.customer_id) is not null then a.customer_id
           else '00000000-0000-0000-0000-000000000000'::uuid
         end
    from (select public.current_affiliate_customer_id() as customer_id) a
$function$
$def$;
  c_helper_md5 constant text := 'adac2cc661231357d044d2fb1c70a38a';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_n int := 10;
  v_def text[] := array_fill(null::text, array[10]);
  v_make boolean[] := array_fill(false, array[10]);
  v_acl text[] := array_fill(null::text, array[10]);
  v_helper_made boolean := false;
  d text; m text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null then
      raise exception '508: public.% is missing', c_relied[i]; end if;
    m := md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    if m <> c_relied_md5[i] and m is distinct from c_relied_later[i] then
      raise exception '508: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_relied[i], m;
    end if;
  end loop;

  -- The function(s) it patches: BEFORE (patched), AFTER or a later version (left alone).
  for i in 1 .. v_n loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '508: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '508: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) is not distinct from c_later[i] then
      raise notice '508: public.% is a later migration''s version (509); left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '508: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '508: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. v_n loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '508: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- The new helper: missing (made here), or already this version.
  if to_regprocedure('public.affiliate_portal_record_id()') is null then
    execute c_helper_def;
    v_helper_made := true;
  elsif md5(pg_get_functiondef('public.affiliate_portal_record_id()'::regprocedure)) <> c_helper_md5 then
    raise exception '508: public.affiliate_portal_record_id() exists and is not this migration''s version';
  else
    raise notice '508: public.affiliate_portal_record_id() is already this version; left alone';
  end if;
  execute 'revoke all on function public.affiliate_portal_record_id() from public, anon, authenticated';
  execute 'grant execute on function public.affiliate_portal_record_id() to service_role';

  -- 2. Install
  for i in 1 .. v_n loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. v_n loop
    m := md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i])));
    if m <> c_after[i] and m is distinct from c_later[i] then
      raise exception '508: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '508: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  if md5(pg_get_functiondef('public.affiliate_portal_record_id()'::regprocedure)) <> c_helper_md5 then
    raise exception '508: public.affiliate_portal_record_id() was installed with an md5 other than the tested one'; end if;
  if has_function_privilege('anon', 'public.affiliate_portal_record_id()', 'execute')
     or has_function_privilege('authenticated', 'public.affiliate_portal_record_id()', 'execute') then
    raise exception '508: affiliate_portal_record_id is callable by a client role'; end if;

  -- 4. Logins joined before 508 whose link is not proven: listed once, on the run that
  -- installs this, as a new join is, so an Owner or Manager can say Same person.
  if v_helper_made then
    insert into public.affiliate_signup_matches (auth_user_id, fresh_customer_id, entered_phone, entered_name, reason, candidate_ids)
    select a.auth_user_id, a.customer_id, c.phone, coalesce(t.full_name, c.full_name), 'phone_other_name', '{}'::uuid[]
      from public.affiliate_accounts a
      join public.customers c on c.id = a.customer_id
      left join lateral (select s.full_name from public.affiliate_signup_identities s
                          where s.auth_user_id = a.auth_user_id order by s.created_at desc limit 1) t on true
     where a.status = 'claimed' and c.deleted_at is null
       and public.affiliate_login_link_proof(a.auth_user_id, a.customer_id) is null
       and not exists (select 1 from public.affiliate_signup_matches m
                        where m.auth_user_id = a.auth_user_id and m.status = 'open')
    on conflict do nothing;
    get diagnostics i = row_count;
    raise notice '508: % login(s) joined before this migration with an unproven link were listed for an Owner or Manager', i;
  end if;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
