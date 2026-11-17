-- 509_a_suspended_affiliate_portal_shows_nothing.sql
--
-- A SUSPENDED AFFILIATE'S PORTAL SHOWS A "SUSPENDED" NOTICE AND NOTHING ELSE
--
--   From the security audit of 17 Nov 2026 (finding M1).
--   Builds on 508 (an unproven login sees nothing of the record): apply 508 first. The
--   BEFORE md5s of the functions 508 also changes are 508's AFTER md5s; the others were
--   compared with production on 17 Nov 2026 (head 502) and matched. If a text differs on
--   the day, this file refuses and changes nothing: re-read and re-test.
--   (The number 509 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- THE OWNER DECIDED THIS RULE on 17 Nov 2026 ("suspension closes the portal"): a suspended
-- affiliate, or an affiliate login whose account is not 'claimed', sees only a notice that
-- the account is suspended, and nothing else from the portal.
--
-- WHAT WAS WRONG
--
--   current_affiliate_customer_id(), which every portal function reads to find the
--   login's record, tested only that the login's account is 'claimed'. Suspending an
--   affiliate (suspend_affiliate, Owner or Manager) sets manually_suspended on the
--   affiliate's row and nothing on the login, so a suspended affiliate still read names,
--   spend, bookings, purchases, earnings and payouts. affiliate_portal_me said
--   "suspended" and answered everything else as before. A login whose account is not
--   'claimed' was refused with "Not an affiliate account", which the pages showed as an
--   error.
--
-- WHAT THIS DOES
--
--   1. current_affiliate_customer_id(): also null when the login's affiliate is suspended
--      (its live customer_affiliates row has manually_suspended). Every portal function
--      that reads it then refuses ("Not an affiliate account"): dashboard, earnings,
--      payouts, purchases, network, campaign progress (through 508's
--      affiliate_portal_record_id) and the referral code and links (referral_info).
--   2. affiliate_portal_me: a login that has an affiliate account but whose portal is
--      closed (suspended, or the account not 'claimed') gets {"status": "suspended",
--      "portal_closed": true} and nothing else. The pages show the suspended notice from it.
--   3. affiliate_portal_details: refuses a closed portal ("This affiliate account is
--      suspended."), so the record's name, phone and email are not shown.
--   4. affiliate_detail_state: a suspended affiliate's route is 'closed', so it cannot
--      start a change of its details or login email (affiliate-details Edge Function).
--   Reactivating the affiliate (reactivate_affiliate) opens the portal again as it was.
--
-- WHAT THIS LEAVES ALONE
--
--   * An affiliate whose status is 'inactive' (set by refresh_affiliate_statuses, not by
--     staff) or whose affiliate row was removed: their portal is not closed by this file.
--   * A change of details already waiting for its emailed code when the affiliate is
--     suspended can still be finished with that code (affiliate_detail_change_verify does
--     not read the route again). Codes last minutes.
--   * Commission: a suspended referrer still earns as before (finding M2, separate).
--   * No function sets an account to 'disabled' or ends the login's sessions; the audit's
--     Owner/Manager "switch off this login" function is not built. A suspended affiliate
--     stays signed in and sees the notice.
--   * The login can still sign in, and reads its own affiliate_accounts row (status).
--
-- UNDO: run the swap back by hand: each c_new text replaced by its c_anchor in the
-- function's definition (pg_get_functiondef), checked against c_before (508's AFTER for
-- me and details). Nothing else is written.
--
-- NO SELF-TEST INSIDE; the suite is scripts/affiliate-signup/tests/suspended-portal-509.sql.
--
-- One transaction with its history row, by the usual wrapper. It changes four functions
-- and writes no rows.

do $mig$
declare
  -- The function(s) this patches: BEFORE (production 502, or 508's AFTER) and AFTER md5s
  c_sig constant text[] := array[
    'current_affiliate_customer_id()',
    'affiliate_portal_me()',
    'affiliate_portal_details()',
    'affiliate_detail_state(uuid)'];
  c_before constant text[] := array[
    '51695acf5f26ce3918d6003d0c980b0f',
    'ac16da58b1c43324d6b56f4902133042',
    '80b6186a7cdd097eadbaa38d38abdf57',
    'afa1c2b4c6564d37de6bb0a42064e0ef'];
  c_after constant text[] := array[
    '4f552894d48ef799c071d4b95c37745d',
    '8b4f230b27adb0acd0b0eb658412fe01',
    '505ad742085b0dda5eb6950522bd6356',
    '42c84668858277a0355208541c0c4c5c'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. An undo swaps them back.
  c_fn constant int[] := array[1, 2, 3, 4];
  c_anchor constant text[] := array[
$a$   where a.auth_user_id = auth.uid() and a.status = 'claimed'$a$,
$a$  if v_me is null then raise exception 'Not an affiliate account'; end if;$a$,
$a$  if s->>'route' = 'not_affiliate' then raise exception 'Not an affiliate account'; end if;$a$,
$a$or a.status <> 'claimed'$a$];
  c_new constant text[] := array[
$n$   where a.auth_user_id = auth.uid() and a.status = 'claimed'
     -- 509: a suspended affiliate's portal is closed: no portal function answers it
     and not exists (select 1 from public.customer_affiliates ca
                      where ca.customer_id = a.customer_id and ca.deleted_at is null and ca.manually_suspended)$n$,
$n$  -- 509: a login whose portal is closed (its affiliate suspended, or its account
  -- not 'claimed') is told so, and nothing else.
  if v_me is null and exists (select 1 from public.affiliate_accounts where auth_user_id = auth.uid()) then
    return jsonb_build_object('status', 'suspended', 'portal_closed', true);
  end if;
  if v_me is null then raise exception 'Not an affiliate account'; end if;$n$,
$n$  if s->>'route' = 'not_affiliate' then raise exception 'Not an affiliate account'; end if;
  -- 509: a closed portal (suspended, or the account not 'claimed') shows none of the record's details
  if public.current_affiliate_customer_id() is null then
    raise exception 'This affiliate account is suspended.' using errcode = '42501'; end if;$n$,
$n$or a.status <> 'claimed'
         -- 509: a suspended affiliate changes nothing here either
         or exists (select 1 from public.customer_affiliates ca
                     where ca.customer_id = a.customer_id and ca.deleted_at is null and ca.manually_suspended)$n$];
  -- Relied on, not changed: 508's helper and the portal functions that refuse when it
  -- (or current_affiliate_customer_id) is null, at 508's AFTER md5s.
  c_relied constant text[] := array[
    'affiliate_portal_record_id()',
    'affiliate_login_link_proof(uuid,uuid)',
    'affiliate_portal_dashboard()',
    'affiliate_portal_earnings()',
    'affiliate_portal_payouts()',
    'affiliate_portal_purchases()',
    'affiliate_portal_network()',
    'affiliate_portal_campaign_progress()',
    'affiliate_portal_referral_info()'];
  c_relied_md5 constant text[] := array[
    'adac2cc661231357d044d2fb1c70a38a',
    '2484fb464733c124213b96152837a660',
    '7831d1cb5a40b59af9392a3ce279bb6a',
    '4937f6820287a09efebb8d3108265eb4',
    '45c08362698f38567ec7696851fa46b3',
    'f7c724ed4eaa6c81f1ce2e2d4e709bae',
    '74ab159218853fcf22e1ccd9d75dcded',
    'cc07104f1bda30a36468f615c9fbb410',
    '7f20a8bfbdc31905266852edda2f5def'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_n int := 4;
  v_def text[] := array_fill(null::text, array[4]);
  v_make boolean[] := array_fill(false, array[4]);
  v_acl text[] := array_fill(null::text, array[4]);
  d text; m text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null then
      raise exception '509: public.% is missing. Apply 508 first.', c_relied[i]; end if;
    m := md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    if m <> c_relied_md5[i] then
      raise exception '509: public.% is not the version this was tested against (md5 %). Apply 508 first, or re-read it and re-test.', c_relied[i], m;
    end if;
  end loop;

  -- The function(s) it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. v_n loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '509: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '509: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '509: public.% is not the version this was tested against (md5 %). Apply 508 first, or re-read it and re-test.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '509: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. v_n loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '509: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. v_n loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. v_n loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '509: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '509: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  -- the two internal helpers stay closed to the browser
  if has_function_privilege('authenticated', 'public.current_affiliate_customer_id()', 'execute')
     or has_function_privilege('anon', 'public.current_affiliate_customer_id()', 'execute')
     or has_function_privilege('authenticated', 'public.affiliate_detail_state(uuid)', 'execute')
     or has_function_privilege('anon', 'public.affiliate_detail_state(uuid)', 'execute') then
    raise exception '509: an internal helper is callable by a client role'; end if;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
