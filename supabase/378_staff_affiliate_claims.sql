-- 378_staff_affiliate_claims.sql
--
-- STAFF HANDLE AFFILIATE ACCOUNT CLAIMS; AN OWNER CAN UNLINK A WRONG LINK
-- (the owner's decisions, 2 Oct 2026, final)
--
--   When someone signs up for the affiliate portal and the app cannot tell
--   for certain which customer they are, the sign-up is parked as an account
--   claim (155, 158, 162). Affiliates page → Pending Account Claims → Resolve
--   links that login to an existing customer. Until now only an Owner or a
--   Manager could see or settle a claim.
--
--   1. Staff (role 'staff', active, not deleted) see Pending Account Claims
--      and Rejected Account Claims, as Owners and Managers do.
--   2. Staff may Resolve a claim, but only to a customer whose phone is the
--      phone the person entered at sign-up. Both are compared through the
--      app's own normalize_customer_phone, so "+65 9123 4567", "6591234567"
--      and "91234567" are one number. A customer with no phone never matches.
--      An Owner or Manager may still link any customer. (25 of the 27 claims
--      resolved so far matched this way.) Staff are also refused, with these
--      words, when:
--        - the claim is their own: its phone is the staff member's work or
--          personal phone, or its email is their profile email or their
--          personal email, as their profile holds them at the time: "You
--          cannot resolve your own claim. Ask an Owner or Manager." (Their
--          login's email is compared too, but only as a backstop: sign-up
--          refuses a login that has a profile and keeps the claiming login's
--          own email, and no two logins share one, so no claim sign-up makes
--          can carry a staff login's email. A staff member who empties their
--          own profile's details, resolves their own claim and fills them in
--          again is not stopped; only the resolve audit row records it, see
--          4.)
--        - an Owner unlinked this login from this customer before (the
--          unlink's audit row, counted only when unlink_affiliate_account
--          wrote it for an Owner: actor_role 'owner', which write_audit and
--          write_audit_ex take from the writer's own profile, and module
--          'affiliate', which only write_audit_ex sets and signed-in users
--          cannot call it; a row anyone writes through write_audit does not
--          count): "An Owner unlinked this login from this customer. Only an
--          Owner or Manager can link it again.";
--        - an Owner unlinked any other login from this customer before: "An
--          Owner unlinked a login from this customer before. Only an Owner or
--          Manager can link a login to them.";
--        - the customer's phone was changed after the person signed up
--          (customer_phone_history since the person's login was made, or the
--          claim if earlier, so deleting the claim and letting the person sign
--          in again does not reset it; rewriting the same number in another
--          format does not count): "This customer's phone was changed after
--          the person signed up. Only an Owner or Manager can link this claim
--          to them.";
--        - more than one undeleted customer has the phone entered, or had it
--          at any time since the person signed up (so moving another
--          sharer's phone away does not help), and the chosen customer is not
--          the claim's suggested customer (candidate_customer_id): "Several
--          customers share this phone. Only an Owner or Manager can link it to
--          a customer other than the suggested one.";
--        - more than one customer shares the phone (as above), and an earlier
--          claim of this login that was deleted or rejected suggested a
--          different customer, or none (a rejected claim still kept, or the
--          audit row a deleted claim leaves). Editing customers'
--          names and deleting the claim would otherwise make the person's next
--          sign-up suggest the sharer staff want: "This person's earlier claim
--          suggested a different customer. Only an Owner or Manager can link
--          it."
--   3. Staff may Reject claims, and Delete pending claims and claims rejected
--      by a staff member. A rejection made by an Owner or Manager is theirs
--      to remove: "Only an Owner or Manager can remove a rejection they made."
--   4. Resolve now refuses, whoever asks:
--        - a deleted customer;
--        - a customer who already has a portal login, with a sentence
--          instead of the raw unique-constraint error it raised before;
--        - a claim whose login is a staff login (any profiles row for it).
--          320 refuses those at sign-up; a claim parked before 320 could
--          still carry one.
--      The verification note is still required. affiliate_claim_link_check
--      gives the same answer before Save, so the Resolve window can show the
--      two phones side by side and say why it cannot link. Resolve's audit
--      row records phones_match, phone_changed_since_claim,
--      previously_unlinked, customer_previously_unlinked,
--      customers_sharing_phone, suggested_customer,
--      earlier_claim_other_customer, own_claim and own_contact_match: whether
--      the claim's email was the resolver's login email, profile email or
--      personal email, and its phone their work or personal phone, each true
--      or false as it stood then. (A staff member can empty their own
--      profile's contact details, resolve their own claim, and fill them in
--      again; the row then shows false against a profile that matches. That
--      row is the only record of it.) A claim closed because its login is
--      already linked ("This login is already linked…") now writes an audit
--      row too.
--   5. An Owner (not a Manager) can unlink a login that was linked to the
--      wrong customer: unlink_affiliate_account(customer, reason).
--   6. Pending Account Claims flag a login an Owner unlinked before
--      (previously_unlinked, and the customers it was unlinked from), and a
--      claim whose likely customer had a login unlinked by an Owner
--      (suggested_customer_unlinked). Rejected Account Claims say whether a
--      staff member rejected the claim (rejected_by_staff), so the page
--      offers staff Delete only there.
--   7. Sign-up (complete_affiliate_onboarding) no longer links a login by
--      itself to a customer an Owner unlinked a login from. Where its
--      verified email, phone and name all match that one customer, which
--      used to link straight away, it now parks a pending claim suggesting
--      them (or, for a login with a rejected claim, answers "Account
--      verification was unsuccessful", as it does for any claim it cannot
--      settle). So the link goes through Resolve, where staff are refused for
--      that customer. For every other customer sign-up is unchanged.
--
-- Everything else stays as it is: staff keep the read-only directory;
-- Correct referrer, Suspend / Reactivate and the money columns stay with
-- Owners and Managers. Admin and Inventory Manager logins are refused claims,
-- as before. What an Owner or Manager may do with a claim is unchanged, apart
-- from the three refusals in 4 that apply to everyone.
--
-- WHAT THIS DOES NOT COVER (reported to the owner)
--
--   - Staff may edit a customer's email, name and phone from the Customers
--     page, and sign-up links a login by itself to the one customer whose
--     email, phone and name all match. So staff can still steer which
--     customer a sign-up is linked to automatically, for any customer an
--     Owner has not unlinked a login from (7 covers those), and nothing
--     records an email or name edit. This was so before 378. The same edits,
--     made before a sign-up, can also change which customer a new claim
--     suggests: where several customers share a phone, staff who swap their
--     names before the person signs up can then link the claim to the one
--     it now suggests (including a login an Owner unlinked from the other
--     sharer).
--   - Rows in audit_logs are scanned for the unlink and deleted-claim checks
--     (no index on action); fine at today's size. A sign-up that auto-links
--     within moments of an Owner's unlink of the same customer is not locked
--     against it.
--   - An Owner's or Manager's Reject applies to that one login: a new login
--     suggesting the same customer can be linked by staff, with no flag.
--
-- WHAT UNLINK DOES
--
--   It deletes the customer's affiliate_accounts row, the bridge between a
--   Supabase login and the customer (155), so the customer can be linked
--   again, by an Owner or Manager resolving a claim. A reason is required.
--   An audit row 'affiliate_login_unlinked' keeps who did it (changed_by,
--   actor_role), the customer, the login and its email, when it had been
--   linked, when it last signed in (auth.users.last_sign_in_at), the claims
--   that linked it, and the reason. That audit row is also what stops staff
--   linking any login, this one or another, to that customer again, and
--   sign-up linking one to them by itself (7).
--   Nothing else changes: the customer's customer_affiliates row with its
--   referral code, status and any suspension; the referral link (it is the
--   code's, not the login's); referred customers; commissions and payouts;
--   and every claim, resolved or rejected, stay as they are.
--
-- WHAT THE UNLINKED LOGIN CAN DO AFTERWARDS
--
--   The login is not deleted or disabled in Supabase Auth: the person can
--   still sign in. current_affiliate_customer_id() no longer finds a customer
--   for it, so every portal function answers "Not an affiliate account". The
--   app finds neither a staff profile nor an affiliate account for the login
--   and sends it to /affiliate/verify, which runs complete_affiliate_onboarding
--   again with the details saved at sign-up:
--     - no customer with that email or that phone and name: a new customer
--       and affiliate record, as for anyone new;
--     - verified email, phone and name all matching one other customer, one
--       no Owner unlinked a login from: linked to them, as before;
--     - a rejected claim of that login: "Account verification was
--       unsuccessful";
--     - otherwise a new pending claim, flagged "previously unlinked", even
--       when the verified email, phone and name all match the customer it
--       was unlinked from (that used to link it straight back; 7). Staff
--       cannot link it back to that customer, nor a new login the person
--       makes, whether or not staff first put that login's email on the
--       customer's record; an Owner or Manager can, or rejects it if the
--       person must not get back in.
--
-- SAFETY
--
-- Every patched function (complete_affiliate_onboarding among them) is
-- guarded by the md5 of its production prosrc (2 Oct 2026), and so are the
-- six it relies on (is_owner_or_manager, normalize_customer_phone and the
-- inspect_customer_phone under it, current_user_role, write_audit and
-- current_affiliate_customer_id); the phone-history trigger must be in
-- place; and each patch's anchors must each occur exactly once. The whole
-- migration is ONE statement (a single DO block) whose first part makes
-- every one of these checks, before anything is created. So a failed check
-- stops the run with nothing installed, whatever runs it: inside a
-- transaction or under autocommit, with or without psql's ON_ERROR_STOP. A
-- function already carrying "378:" is left alone, so a second run changes
-- nothing. Functions only; no table or row is changed.
--
-- AFTER (md5(prosrc) once applied, for later guards; checked on a local copy
-- whose guarded functions match production, 2 Oct 2026):
--   resolve_affiliate_account_claim(uuid,uuid,text)  2bf645318e225825a76a6a1ad1ff7446
--   reject_affiliate_account_claim(uuid,text)        433ef3304aeb8c929da82eebda461224
--   delete_affiliate_account_claim(uuid)             ccc26d0c9ab63b61ba9558b0d39f4330
--   affiliate_pending_claims()                       9e7f4adb02eab927a3f24c8388e0553d
--   affiliate_rejected_claims()                      b9b1536edf619a632393497cb83c5304
--   complete_affiliate_onboarding(text,text,text,boolean)  fe715c05db05ba2b34655ac9a519d0a4
--   affiliate_claim_staff()                          83b6916b704814ec818093b5b5c0247b
--   affiliate_claim_link_check(uuid,uuid)            ee5c2dd66f00355615ac6457190910f5
--   affiliate_portal_login(uuid)                     d4c9f8c4fcf456da2863346245c1e6d7
--   unlink_affiliate_account(uuid,text)              2b5247c2a68fd4f276d07f74b5e301fc

set lock_timeout = '5s';

-- The whole migration is ONE statement (a single DO block), so it is atomic
-- whatever runs it: in a transaction or under autocommit, with or without
-- psql's ON_ERROR_STOP. Every check comes first; nothing is created unless
-- all of them pass.
do $mig$
declare
  v record; d text; n int; k int;
  v_install text[] := '{}';
begin
  -- ── 0. The versions this was tested against ──────────────────────────────
  for v in select * from (values
      ('public.resolve_affiliate_account_claim(uuid,uuid,text)', 'c207d9cf81214433be2b5e4618c3537c'),
      ('public.reject_affiliate_account_claim(uuid,text)',       '5f0c429d4ceefefb42edd14bfe566848'),
      ('public.delete_affiliate_account_claim(uuid)',            'd24252b1dac42a0e24fdf145397960d6'),
      ('public.affiliate_pending_claims()',                      'efaa55792c0e84793e2549cbb435d7b1'),
      ('public.affiliate_rejected_claims()',                     'd0058135ca361e88585a1e5e916865bf'),
      ('public.complete_affiliate_onboarding(text,text,text,boolean)', 'b9dd0dece27ef111bca3bcf193abb7b4')) t(fn, ok)
  loop
    if to_regprocedure(v.fn) is null then raise exception '378: % is missing', v.fn; end if;
    if position('378:' in (select prosrc from pg_proc where oid = to_regprocedure(v.fn))) = 0
       and (select md5(prosrc) from pg_proc where oid = to_regprocedure(v.fn)) <> v.ok then
      raise exception '378: % is not the version this was tested against', v.fn; end if;
  end loop;
  -- Relied on, not patched: who is an Owner or Manager, what a phone is (and
  -- the parser under it), the role an audit row records (current_user_role,
  -- write_audit, which signed-in users may call: it takes the role from the
  -- caller's profile, never from the caller; and write_audit_ex, which only
  -- functions call and which alone sets the module an unlink row is trusted
  -- by), and which customer a login opens.
  for v in select * from (values
      ('public.is_owner_or_manager()',             '7f888d6df058283917622c3ad03ddd91'),
      ('public.normalize_customer_phone(text)',    '3c7cbf5bb745219b3c78c5d19666224a'),
      ('public.inspect_customer_phone(text,text)', '1881dfc5a828975c58d4c613a7437ee5'),
      ('public.current_user_role()',               '38683d3be39913aba404fa202d77f1c8'),
      ('public.write_audit(text,uuid,text,jsonb,jsonb)', 'b900ae6a263830edc721406da7c396c3'),
      ('public.write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', '711fa18ef5da361a191e12db3db313a5'),
      ('public.current_affiliate_customer_id()',   '42408d5f8939d58786c4531c96163ac7')) t(fn, ok)
  loop
    if coalesce((select md5(prosrc) from pg_proc where oid = to_regprocedure(v.fn)), 'missing') <> v.ok then
      raise exception '378: % is not the version this was tested against', v.fn; end if;
  end loop;
  -- The staff rule "the phone was changed after sign-up" reads the history
  -- the phone trigger (161) keeps.
  if to_regclass('public.customer_phone_history') is null
     or to_regprocedure('public.audit_customer_phone_change()') is null
     or not exists (select 1 from pg_trigger
                     where tgrelid = 'public.customers'::regclass and tgenabled <> 'D'
                       and tgfoid = to_regprocedure('public.audit_customer_phone_change()')) then
    raise exception '378: the customer phone history (161) is not in place'; end if;

  -- ── 1. The claim functions take staff: each patch is worked out, and its
  -- anchors checked (each must occur exactly once), before anything is
  -- created. A function already carrying "378:" is left alone.
  for v in select * from (values
    ('public.affiliate_pending_claims()',
  array[
    $a$  if not coalesce(public.is_owner_or_manager(),false) then raise exception 'Owner or Manager only'; end if;$a$,
    $a$    'created_at', cl.created_at) order by cl.created_at), '[]'::jsonb) into v_rows$a$,
    $a$  from public.affiliate_account_claims cl where cl.status = 'pending';$a$],
  array[
    $r$  -- 378: staff see the claims too.
  if not (coalesce(public.is_owner_or_manager(),false) or public.affiliate_claim_staff()) then
    raise exception 'Owner, Manager or Staff only'; end if;$r$,
    $r$    'created_at', cl.created_at,
    -- 378: a login an Owner unlinked before, and from which customers; and
    -- whether an Owner unlinked any login from the likely customer (staff
    -- cannot link a login to them).
    'previously_unlinked', u378.auth_user_id is not null,
    'unlinked_customer_ids', coalesce(u378.customer_ids, '[]'::jsonb),
    'suggested_customer_unlinked', uc378.customer_id is not null
    ) order by cl.created_at), '[]'::jsonb) into v_rows$r$,
    $r$  from public.affiliate_account_claims cl
  -- 378: the unlinks (their audit rows), read once for the whole list. Only
  -- rows unlink_affiliate_account wrote for an Owner count: actor_role is
  -- the writer's own role (current_user_role), and module 'affiliate' is set
  -- only through write_audit_ex, which signed-in users cannot call.
  left join (select l.old_data->>'auth_user_id' as auth_user_id,
                    jsonb_agg(distinct l.old_data->>'customer_id') as customer_ids
               from public.audit_logs l
              where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
                and l.actor_role = 'owner' and l.module = 'affiliate'
              group by 1) u378 on u378.auth_user_id = cl.auth_user_id::text
  left join (select distinct l.old_data->>'customer_id' as customer_id
               from public.audit_logs l
              where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
                and l.actor_role = 'owner' and l.module = 'affiliate') uc378
         on uc378.customer_id = cl.candidate_customer_id::text
  where cl.status = 'pending';$r$]),
    ('public.affiliate_rejected_claims()',
  array[
    $a$  if not public.is_owner_or_manager() then raise exception 'Owner or Manager only'; end if;$a$,
    $a$    'created_at', cl.created_at) order by cl.rejected_at desc nulls last$a$],
  array[
    $r$  -- 378: staff see the claims too.
  if not (public.is_owner_or_manager() or public.affiliate_claim_staff()) then
    raise exception 'Owner, Manager or Staff only'; end if;$r$,
    $r$    'created_at', cl.created_at,
    -- 378: whether a staff member rejected it (staff may delete only those).
    'rejected_by_staff', exists (select 1 from public.profiles p where p.id = cl.rejected_by and p.role = 'staff')
    ) order by cl.rejected_at desc nulls last$r$]),
    ('public.reject_affiliate_account_claim(uuid,text)',
  array[$a$  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can reject account claims'; end if;$a$],
  array[$r$  -- 378: staff may reject a claim too.
  if not (public.is_owner_or_manager() or public.affiliate_claim_staff()) then
    raise exception 'Only Owner, Manager or Staff can reject account claims'; end if;$r$]),
    ('public.delete_affiliate_account_claim(uuid)',
  array[
    $a$  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can delete account claims'; end if;$a$,
    $a$    raise exception 'A resolved claim cannot be deleted (it is part of the account history).';
  end if;$a$],
  array[
    $r$  -- 378: staff may delete a claim too (pending ones, and their own rejections).
  if not (public.is_owner_or_manager() or public.affiliate_claim_staff()) then
    raise exception 'Only Owner, Manager or Staff can delete account claims'; end if;$r$,
    $r$    raise exception 'A resolved claim cannot be deleted (it is part of the account history).';
  end if;
  -- 378: staff delete pending claims and claims a staff member rejected. A
  -- rejection made by an Owner or Manager (or by no one recorded) is theirs
  -- to remove.
  if not public.is_owner_or_manager() and v_claim.status = 'rejected'
     and not exists (select 1 from public.profiles p where p.id = v_claim.rejected_by and p.role = 'staff') then
    raise exception 'Only an Owner or Manager can remove a rejection they made.' using errcode = '42501';
  end if;$r$]),
    ('public.resolve_affiliate_account_claim(uuid,uuid,text)',
  array[
    $a$declare v_claim public.affiliate_account_claims%rowtype; v_aff public.customer_affiliates%rowtype; v_acct uuid; v_code text;$a$,
    $a$  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can resolve account claims'; end if;$a$,
    $a$    return jsonb_build_object('ok', false, 'already', true, 'message', 'This login is already linked to an affiliate account.');$a$,
    $a$  select * into v_aff from public.customer_affiliates where customer_id = p_customer_id and deleted_at is null;$a$,
    $a$    jsonb_build_object('customer_id', p_customer_id, 'affiliate_id', v_aff.id), 'affiliate', p_note, null);$a$],
  array[
    $r$declare v_claim public.affiliate_account_claims%rowtype; v_aff public.customer_affiliates%rowtype; v_acct uuid; v_code text;
        v378 jsonb;$r$,
    $r$  -- 378: staff may resolve too, but only to the customer whose phone is the
  -- one entered at sign-up (affiliate_claim_link_check, below).
  if not (public.is_owner_or_manager() or public.affiliate_claim_staff()) then
    raise exception 'Only Owner or Manager can resolve account claims (Staff can, to the customer whose phone was entered)'
      using errcode = '42501'; end if;$r$,
    $r$    -- 378: closing the claim this way is audited too.
    perform public.write_audit_ex('affiliate_account_claims', p_claim_id, 'affiliate_claim_resolved', null,
      jsonb_build_object('already_linked', true, 'chosen_customer_id', p_customer_id,
        'customer_id', (select a.customer_id from public.affiliate_accounts a where a.auth_user_id = v_claim.auth_user_id)),
      'affiliate', p_note, null);
    return jsonb_build_object('ok', false, 'already', true, 'message', 'This login is already linked to an affiliate account.');$r$,
    $r$  -- 378: the customer row is locked first, so two claims cannot both find
  -- the customer free, and an Owner's unlink waits for this. Then the checks
  -- the Resolve window showed: not a deleted customer, not a customer who
  -- already has a login, not a staff login, and for staff the rules on the
  -- phone, their own claims and logins an Owner unlinked.
  perform 1 from public.customers where id = p_customer_id for update;
  v378 := public.affiliate_claim_link_check(p_claim_id, p_customer_id);
  if v378->>'problem' is not null then raise exception '%', v378->>'problem'; end if;

  select * into v_aff from public.customer_affiliates where customer_id = p_customer_id and deleted_at is null;$r$,
    $r$    jsonb_build_object('customer_id', p_customer_id, 'affiliate_id', v_aff.id,
      'phones_match', (v378->>'phones_match')::boolean,
      'phone_changed_since_claim', (v378->>'phone_changed_since_claim')::boolean,
      'previously_unlinked', (v378->>'previously_unlinked')::boolean,
      'customer_previously_unlinked', (v378->>'customer_previously_unlinked')::boolean,
      -- How many customers had the phone, whether this one was the claim's
      -- suggested customer, and whether an earlier deleted or rejected claim
      -- of this login suggested someone else.
      'customers_sharing_phone', (v378->>'customers_sharing_phone')::int,
      'suggested_customer', (v378->>'suggested_customer')::boolean,
      'earlier_claim_other_customer', (v378->>'earlier_claim_other_customer')::boolean,
      -- Whether the claim was the resolver's own, each comparison as it stood
      -- at the time: a profile emptied for the resolve and filled in again
      -- later shows against it.
      'own_claim', (v378->>'own_claim')::boolean,
      'own_contact_match', v378->'own_contact_match'), 'affiliate', p_note, null);$r$]),
    ('public.complete_affiliate_onboarding(text,text,text,boolean)',
  array[
    $a$  elsif v_email_matches = 1 and v_phone_cust is not null and v_phone_email = v_email then$a$],
  array[
    $r$  elsif v_email_matches = 1 and v_phone_cust is not null and v_phone_email = v_email
        -- 378: not to a customer an Owner unlinked a login from (the unlink's
        -- audit row, as affiliate_claim_link_check reads it). That sign-up
        -- falls to the branch below and is parked as a pending claim
        -- suggesting the customer, so the link goes through Resolve, where
        -- staff are refused for them.
        and not exists (select 1 from public.audit_logs l
                         where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
                           and l.actor_role = 'owner' and l.module = 'affiliate'
                           and l.old_data->>'customer_id' = v_phone_cust::text) then$r$])
  ) t(fn, f, r)
  loop
    d := pg_get_functiondef(to_regprocedure(v.fn));
    if position('378:' in d) > 0 then raise notice '378: % already patched; left alone.', v.fn; continue; end if;
    for k in 1 .. cardinality(v.f) loop
      n := (length(d) - length(replace(d, v.f[k], ''))) / length(v.f[k]);
      if n <> 1 then raise exception '378: % anchor % found % times', v.fn, k, n; end if;
    end loop;
    for k in 1 .. cardinality(v.f) loop
      d := replace(d, v.f[k], v.r[k]);
    end loop;
    v_install := v_install || d;
  end loop;

  -- Every check has passed. From here on, the functions are created.

  -- ── 2. Who counts as staff here ────────────────────────────────────────────
  -- An active, undeleted login with the role 'staff'. Admin and Inventory
  -- Manager are not staff for this purpose: they keep what they had (nothing).
  execute $ddl$
create or replace function public.affiliate_claim_staff()
returns boolean language sql stable security definer set search_path to 'public' as $f$
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.role = 'staff'
                    and p.is_active = true and p.deleted_at is null)
$f$
$ddl$;

  -- ── 3. May this claim's login be linked to this customer, by this caller? ──
  -- One answer for the Resolve window and for resolve_affiliate_account_claim,
  -- so what the window says is what Save does. 'problem' is null when the link
  -- is allowed, otherwise the sentence resolve raises.
  execute $ddl$
create or replace function public.affiliate_claim_link_check(p_claim_id uuid, p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare
  v_any boolean := coalesce(public.is_owner_or_manager(), false);
  cl public.affiliate_account_claims%rowtype;
  c public.customers%rowtype;
  me public.profiles%rowtype;
  v_entered text; v_phone text; v_match boolean; v_has_login boolean; v_staff_login boolean;
  v_unlinked_at timestamptz; v_cust_unlinked_at timestamptz; v_since timestamptz;
  v_phone_changed boolean; v_sharing int; v_suggested boolean; v_earlier_other boolean;
  v_own boolean; v_own_match jsonb;
  v_hide boolean; v_problem text;
begin
  if not (v_any or public.affiliate_claim_staff()) then
    raise exception 'Only Owner or Manager can resolve account claims (Staff can, to the customer whose phone was entered)'
      using errcode = '42501'; end if;
  select * into cl from public.affiliate_account_claims where id = p_claim_id;
  if not found then raise exception 'Claim not found'; end if;
  select * into c from public.customers where id = p_customer_id;
  if not found then raise exception 'Customer not found'; end if;

  v_entered := public.normalize_customer_phone(cl.entered_phone);
  v_phone   := public.normalize_customer_phone(c.phone);
  -- No phone on either side is never a match.
  v_match := v_entered is not null and v_phone is not null and v_entered = v_phone;
  v_has_login := exists (select 1 from public.affiliate_accounts a where a.customer_id = c.id);
  -- A staff login is Staff, never an Affiliate (320): any profiles row counts,
  -- active or not, whatever its role.
  v_staff_login := exists (select 1 from public.profiles p where p.id = cl.auth_user_id);
  -- An Owner unlinked this login from this customer before: the unlink's
  -- audit row (unlink_affiliate_account, below), which nobody can edit. Only
  -- a row written for an Owner counts: actor_role is the writer's own role
  -- (current_user_role, never the caller's say), and module 'affiliate' is
  -- set only through write_audit_ex, which signed-in users cannot call, so a
  -- row anyone writes through write_audit does not count.
  select max(l.created_at) into v_unlinked_at from public.audit_logs l
   where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
     and l.actor_role = 'owner' and l.module = 'affiliate'
     and l.old_data->>'auth_user_id' = cl.auth_user_id::text
     and l.old_data->>'customer_id' = c.id::text;
  -- An Owner unlinked any login from this customer before: for staff, no
  -- login is linked to them again.
  select max(l.created_at) into v_cust_unlinked_at from public.audit_logs l
   where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
     and l.actor_role = 'owner' and l.module = 'affiliate'
     and l.old_data->>'customer_id' = c.id::text;
  -- "Since the person signed up": from when their login was made, or the
  -- claim if that is earlier. Staff cannot move this by deleting or rejecting
  -- the claim and letting the person sign in again. (Nothing known: every
  -- change counts.)
  v_since := coalesce(least(cl.created_at, (select u.created_at from auth.users u where u.id = cl.auth_user_id)),
                      '-infinity'::timestamptz);
  -- The customer's phone was changed since the person signed up: a phone the
  -- record held since then that is not the number it holds now. (Each change
  -- keeps the number it replaced. Rewriting the same number in another format
  -- is not a change; changing it away and back is.)
  v_phone_changed := exists (select 1 from public.customer_phone_history h
                              where h.customer_id = c.id and h.created_at >= v_since
                                and public.normalize_customer_phone(h.phone) is distinct from v_phone);
  -- How many customers in use have the phone entered, counting one whose
  -- phone was that number at any time since the person signed up (so moving
  -- another sharer's phone away does not make the chosen one the only one),
  -- and whether the chosen one is the customer sign-up suggested. Written as
  -- a UNION so the first half uses idx_customers_phone_norm.
  v_sharing := case when v_entered is null then 0 else
    (select count(*) from (
        select x.id from public.customers x
         where x.deleted_at is null and public.normalize_customer_phone(x.phone) = v_entered
        union
        select x.id from public.customer_phone_history h
          join public.customers x on x.id = h.customer_id and x.deleted_at is null
         where h.created_at >= v_since and public.normalize_customer_phone(h.phone) = v_entered) s) end;
  v_suggested := coalesce(cl.candidate_customer_id = c.id, false);
  -- An earlier claim of this login, deleted or rejected, suggested another
  -- customer (or none): editing customers' names and deleting a claim can
  -- make the person's next sign-up suggest a different sharer of the phone.
  -- A rejected claim stays in the table until it is deleted, and deleting
  -- any claim leaves the audit row delete_affiliate_account_claim writes,
  -- with the customer it suggested. (A row written by anyone else could only
  -- refuse staff more, so it is not filtered out.)
  v_earlier_other := exists (select 1 from public.affiliate_account_claims o
                              where o.auth_user_id = cl.auth_user_id and o.status = 'rejected'
                                and o.candidate_customer_id is distinct from cl.candidate_customer_id)
    or exists (select 1 from public.audit_logs l
                where l.table_name = 'affiliate_account_claims' and l.action = 'affiliate_claim_deleted'
                  and l.old_data->>'auth_user_id' = cl.auth_user_id::text
                  and (l.old_data->>'candidate_customer_id') is distinct from cl.candidate_customer_id::text);
  -- The caller's own claim: the phone entered is their work or personal
  -- phone, or the claim's email is their profile email or their personal
  -- email. Each comparison is kept in the resolve audit row, as it stood
  -- then; that row is the only record of a staff member who empties their
  -- own profile's details, resolves their own claim and fills them in again.
  -- The login-email comparison (auth_email) is kept as a backstop only: it
  -- cannot match a claim sign-up made, since sign-up refuses any login with a
  -- profile and keeps the claiming login's own email, and no two logins share
  -- an email.
  select * into me from public.profiles where id = auth.uid();
  v_own_match := jsonb_build_object(
    'auth_email', coalesce(nullif(lower(btrim(cl.verified_email)), '')
                             = (select lower(btrim(u.email)) from auth.users u where u.id = auth.uid()), false),
    'profile_email', coalesce(nullif(lower(btrim(cl.verified_email)), '') = lower(btrim(me.email)), false),
    'personal_email', coalesce(nullif(lower(btrim(cl.verified_email)), '') = lower(btrim(me.personal_email)), false),
    'work_phone', coalesce(v_entered = public.normalize_customer_phone(me.work_phone), false),
    'personal_phone', coalesce(v_entered = public.normalize_customer_phone(me.personal_phone), false));
  v_own := exists (select 1 from jsonb_each(v_own_match) e where e.value = 'true'::jsonb);

  v_problem := case
    when c.deleted_at is not null then
      'This customer record has been deleted. Link the claim to the customer record that is in use.'
    when v_staff_login then
      'This login belongs to a member of staff, so it cannot also be an affiliate account.'
    when v_has_login then
      'This customer already has an affiliate portal login. A customer can have only one; if that one is wrong, an Owner can unlink it first.'
    -- An Owner or Manager may link any other customer.
    when v_any then null
    when v_own then
      'You cannot resolve your own claim. Ask an Owner or Manager.'
    when v_unlinked_at is not null then
      'An Owner unlinked this login from this customer. Only an Owner or Manager can link it again.'
    when v_cust_unlinked_at is not null then
      'An Owner unlinked a login from this customer before. Only an Owner or Manager can link a login to them.'
    when not v_match then
      'Only an Owner or Manager can link this claim to a customer whose phone differs from the one entered.'
    when v_phone_changed then
      'This customer''s phone was changed after the person signed up. Only an Owner or Manager can link this claim to them.'
    when v_sharing > 1 and not v_suggested then
      'Several customers share this phone. Only an Owner or Manager can link it to a customer other than the suggested one.'
    when v_sharing > 1 and v_earlier_other then
      'This person''s earlier claim suggested a different customer. Only an Owner or Manager can link it.'
  end;

  -- Staff cannot see deleted customers (RLS); this does not show them either.
  v_hide := not v_any and c.deleted_at is not null;
  return jsonb_build_object(
    'claim_id', cl.id, 'entered_phone', cl.entered_phone,
    'customer_id', c.id,
    'customer_name', case when v_hide then null else c.full_name end,
    'customer_phone', case when v_hide then null else c.phone end,
    'phones_match', v_match, 'customer_deleted', c.deleted_at is not null,
    'customer_has_login', v_has_login, 'login_is_staff', v_staff_login,
    'previously_unlinked', v_unlinked_at is not null, 'unlinked_at', v_unlinked_at,
    'customer_previously_unlinked', v_cust_unlinked_at is not null, 'customer_unlinked_at', v_cust_unlinked_at,
    'phone_changed_since_claim', v_phone_changed,
    'customers_sharing_phone', v_sharing, 'suggested_customer', v_suggested,
    'earlier_claim_other_customer', v_earlier_other,
    'own_claim', v_own, 'own_contact_match', v_own_match,
    'any_customer', v_any, 'problem', v_problem);
end $f$
$ddl$;

  -- ── 4. Install the claim functions patched in 1 ──────────────────────────
  foreach d in array v_install loop
    execute d;
  end loop;

  -- ── 5. Which login a customer has (Owner) ──────────────────────────────────
  -- What the Unlink window shows: the login's email, when it was linked, when
  -- it last signed in (Supabase Auth's own record; affiliate_accounts'
  -- last_login_at is only set when the link is made), and how it was linked
  -- (the claims that linked it, with who resolved them and their note).
  execute $ddl$
create or replace function public.affiliate_portal_login(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare a public.affiliate_accounts%rowtype;
begin
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'owner'
                    and p.is_active = true and p.deleted_at is null) then
    raise exception 'Only an Owner can see or unlink an affiliate login' using errcode = '42501'; end if;
  select * into a from public.affiliate_accounts where customer_id = p_customer_id;
  if not found then return jsonb_build_object('linked', false); end if;
  return jsonb_build_object(
    'linked', true,
    'login_email', (select u.email from auth.users u where u.id = a.auth_user_id),
    'status', a.status, 'linked_at', a.created_at,
    'last_sign_in_at', (select u.last_sign_in_at from auth.users u where u.id = a.auth_user_id),
    'claims', coalesce((
      select jsonb_agg(jsonb_build_object(
               'claim_id', cl.id, 'entered_name', cl.entered_name, 'entered_phone', cl.entered_phone,
               'resolved_at', cl.resolved_at, 'resolution_note', cl.resolution_note,
               'resolved_by_name', (select p.full_name from public.profiles p where p.id = cl.resolved_by))
             order by cl.resolved_at desc nulls last)
        from public.affiliate_account_claims cl
       where cl.auth_user_id = a.auth_user_id and cl.status = 'resolved'), '[]'::jsonb));
end $f$
$ddl$;

  -- ── 6. Unlink (Owner) ──────────────────────────────────────────────────────
  execute $ddl$
create or replace function public.unlink_affiliate_account(p_customer_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare a public.affiliate_accounts%rowtype; v_name text; v_email text; v_signed_in timestamptz; v_claims jsonb;
begin
  -- An Owner only: not a Manager, and not a deactivated or deleted Owner.
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'owner'
                    and p.is_active = true and p.deleted_at is null) then
    raise exception 'Only an Owner can unlink an affiliate login' using errcode = '42501'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'A reason is required to unlink a login'; end if;

  -- The customer row first, as resolve locks it: an unlink and a resolve for
  -- one customer happen one after the other. A deleted customer can still be
  -- unlinked.
  select full_name into v_name from public.customers where id = p_customer_id for update;
  if not found then raise exception 'Customer not found'; end if;
  select * into a from public.affiliate_accounts where customer_id = p_customer_id for update;
  if not found then raise exception 'This customer has no portal login linked.'; end if;

  select u.email, u.last_sign_in_at into v_email, v_signed_in from auth.users u where u.id = a.auth_user_id;
  select coalesce(jsonb_agg(cl.id order by cl.resolved_at), '[]'::jsonb) into v_claims
    from public.affiliate_account_claims cl where cl.auth_user_id = a.auth_user_id and cl.status = 'resolved';

  -- Only the bridge goes. The affiliate record, its code, the commissions and
  -- the claims stay; the login stays in Supabase Auth.
  delete from public.affiliate_accounts where id = a.id;

  -- This row is also what keeps staff from linking this login, or any other,
  -- to this customer again (affiliate_claim_link_check), and sign-up from
  -- linking one to them by itself (complete_affiliate_onboarding). It counts
  -- because it is written here, for an Owner, through write_audit_ex.
  perform public.write_audit_ex('affiliate_accounts', a.id, 'affiliate_login_unlinked',
    jsonb_build_object('customer_id', a.customer_id, 'customer_name', v_name, 'affiliate_id', a.affiliate_id,
      'auth_user_id', a.auth_user_id, 'login_email', v_email, 'status', a.status,
      'linked_at', a.created_at, 'last_sign_in_at', v_signed_in, 'resolved_claim_ids', v_claims),
    null, 'affiliate', btrim(p_reason), null);

  return jsonb_build_object('ok', true, 'customer_id', p_customer_id, 'login_email', v_email);
end $f$
$ddl$;

  -- ── 7. Grants (339) ────────────────────────────────────────────────────────
  -- The patched functions keep theirs. The staff test is for these functions
  -- only; the other three are what the page calls, and check who is asking.
  execute $ddl$revoke all on function public.affiliate_claim_staff() from public, anon, authenticated$ddl$;
  execute $ddl$grant execute on function public.affiliate_claim_staff() to service_role$ddl$;
  execute $ddl$revoke all on function public.affiliate_claim_link_check(uuid,uuid),
                       public.affiliate_portal_login(uuid),
                       public.unlink_affiliate_account(uuid,text) from public, anon$ddl$;
  execute $ddl$grant execute on function public.affiliate_claim_link_check(uuid,uuid),
                         public.affiliate_portal_login(uuid),
                         public.unlink_affiliate_account(uuid,text) to authenticated, service_role$ddl$;
end $mig$;

notify pgrst, 'reload schema';
