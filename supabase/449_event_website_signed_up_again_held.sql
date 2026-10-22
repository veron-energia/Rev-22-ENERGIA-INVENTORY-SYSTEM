-- 449_event_website_signed_up_again_held.sql
--
-- SOMEONE STAFF TOOK OFF THE GUEST LIST WHO SIGNS UP AGAIN WAITS FOR STAFF
-- (the owner's answer, 22 Oct 2026: "Hold for staff to decide")
--
-- WHAT WAS WRONG / WHY
--
--   Seen in production, 22 Oct 2026: a website registration that staff took
--   off the guest list (reason "Cannot come") was sent again, twice, with the
--   same phone, name and email. 436 leaves such a person off the list (staff
--   put them back) and only writes an Audit Log row
--   (event_guest_register_again_refused). The website was answered as for
--   anyone already registered (their person id, VIP link token, the days of
--   the record staff cancelled, their VIP state), so it said "You're
--   registered!", sent its confirmation email and offered VIP, and their
--   answers for the day were refused (person_cancelled). Nothing told staff
--   where they look. VIP was not stopped either (read on 22 Oct 2026): 436's
--   person_cancelled check in event_vip_person_problems runs after the
--   checkout's own order makes them 'pending', so it reads payment_waiting
--   and the checkout is accepted; HitPay's payment would then be invoiced
--   (event_vip_make_invoices stops only a closed person), making them VIP
--   while staff had taken them off.
--
-- THE RULES (binding)
--
--   The owner's answer, 22 Oct 2026: "Hold for staff to decide: They show
--   under Registration holds on the Event page as 'signed up again after
--   being taken off'; staff put them back or close it. The website says their
--   place will be confirmed instead of 'You're registered!'."
--   Every earlier answer in 436's, 439's, 441's and 444's THE RULES stands as
--   written there.
--   Where the answer leaves a choice open, the safest was taken (each to
--   confirm with the owner):
--   * While held they cannot buy VIP: the website does not offer it, and the
--     app refuses a checkout for them (person_cancelled, the contract's "not
--     registered any more"); a payment or transfer that comes anyway waits
--     for a Manager (needs review, the reason says why).
--   * No normal confirmation email for them (the website's SendFox); their
--     page says their place will be confirmed by the team.
--   * The days they ask for while held are kept: putting them back adds them
--     (beside the days they had). Their answers for the day are saved once
--     they are back (the website keeps them as Answers To Send; its sync
--     saves the newest ones when the app says they are registered again, over
--     answers kept from before, unless the app's answers changed after that
--     sign-up: then the app's stand).
--   * Put back is one staff action for anyone who can run the event (Owner,
--     Admin, Manager or Staff at any of the event's stores, as the Guests
--     tab's Restore since 415; linking and Close under To match also need the
--     website's store, as they can make customers and invoices there): the
--     Guests tab's Restore, which "Put back on the list" calls. Close is an
--     Owner's or Manager's (event_registration_close, as 436) and leaves them
--     off; their unpaid HitPay checkouts close with it (as 444's Close).
--   * Signing up again while held updates the same hold: one per person, one
--     audit row per sign-up.
--   * Taken off as "Upgraded to VIP..." (their VIP record stands): as before.
--   * Signing up again with another email: as before ("already registered",
--     nothing of theirs given out, nothing held: anyone could type a phone and
--     a name).
--   How it reads (this file, 22 Oct 2026):
--   * "Registration holds" is the To match panel on the Guests tab
--     (RegistrationHoldsPanel, fed by event_web_guest_extras' holds). Such a
--     person is listed there with the reason signed_up_again ("Signed up again
--     after being taken off the list."), who took them off and why, and the
--     days they asked for; one who also waits to be matched is listed once,
--     as To match, with the same note and Put back.
--   * A hold is open from their first sign-up after staff took them off until
--     staff put them back or close it; a removal after that needs a new
--     sign-up to hold them again. After Close, signing up again holds them
--     again (nothing lets them back in by itself). While their VIP record
--     stands (a payment invoiced by hand while they were held) they are on
--     the list as VIP and no hold shows (as 436's sign-up treats a VIP); it
--     shows again if that VIP is cancelled.
--   * "The website says their place will be confirmed": the register answer
--     gives such a person no days (days: [], with their person id, VIP link
--     token, already_registered true and their VIP state, as before). No
--     other answer has none (a person always has a day), and the website reads
--     it as "Your place will be confirmed by our team". The contract is not
--     changed (c120786884a6ca208881acc90a339996: RegisteredPerson.days is
--     "the person's days now"); no edge function is deployed. So this
--     meaning of days: [] is written only here and in the website's
--     heldAgain(); the person read and the sync still give their days. At
--     the contract's next change, RegisteredPerson.days says it, in every
--     copy together (the app's two, the website's, the Event page's).
--
-- WHAT THIS DOES
--
--   0. event_registration_people gets three columns (no default, nothing
--      filled; the table stays the service role's alone):
--      signed_up_again_at (the open hold's start), signed_up_again_days
--      (every day asked for while held), signed_up_again_resolved_at (put
--      back or closed); check event_registration_people_signed_up_again_check
--      (at and days together, days not empty, resolved only with at).
--   1. event_web_register (the website's): the branch for someone taken off
--      the list holds them (or updates their open hold: the days asked are
--      added), keeps 436's audit row (same action, so earlier checks read it;
--      its reason now says held for staff, and it names the person and
--      whether the hold was opened or updated), and answers days: [] for
--      them. Their record, their guest record and its days stay as they were.
--      Their record is read again and locked (as a Close locks it): if staff
--      closed their registration while the sign-up waited, it signs them up
--      as someone new, as after a Close (no hold, no audit row). A hold
--      starts at the later of now() and the removal it answers, so a removal
--      that committed while the sign-up waited still leaves it open.
--   2. event_web_guest_extras (page): holds lists open signed-up-again holds
--      (reason signed_up_again unless they wait to be matched; held_at = the
--      hold's start; no candidates: they have their customer) with
--      signed_up_again {held_at, days, removed_reason, removed_at} (on To match
--      entries too: null when none); their free guest's row gets
--      signed_up_again {held_at, days}; holds are listed by when each started.
--      Not while their VIP record stands (registered VIP guest).
--   3. event_set_guest_cancelled (page): restoring the free guest of someone
--      with an open hold first adds the days they asked for that the event
--      still has, restores them as 415 does, adds those days to their chosen
--      days and resolves the hold; the event_guest_restored audit row adds
--      signed_up_again {person_id, held_at, days_asked, days_added}; the
--      answer adds days_added and signed_up_again. (Their VIP record standing:
--      no open hold, so Restore is 415's.)
--   4. event_registration_close (page): for an open signed-up-again hold of
--      someone not waiting to be matched: the hold is resolved, they stay off
--      (guest cancelled, registration as it was), and each HitPay checkout of
--      theirs not paid closes with it, as 444's Close (dismissed "Checkout
--      closed: <reason>", audited event_vip_checkout_closed; a payment HitPay
--      reports for it later waits on Website orders, never invoiced by
--      itself); audit event_registration_signed_up_again_closed (with
--      checkouts_closed when any), answer {ok, checkouts_closed,
--      signed_up_again: 'closed'}; a Close on such a hold already put back
--      or closed is refused ("This registration is not waiting for staff any
--      more."), so a Close from a page that did not see a Put back cannot undo
--      it. Waiting to be matched: as before. Their VIP record standing: no
--      hold, so 444's "is VIP: cancel or refund their VIP invoice instead".
--   5. event_vip_person_problems (the website's checkout, HitPay's payment and
--      a transfer use it): someone with an open hold is a problem,
--      person_cancelled, "Person N on this order signed up again after staff
--      took them off the list: put them back on the list first (Guests, To
--      match)": vip_checkout refuses it (nothing kept), vip_paid and
--      vip_transfer keep the payment for a Manager (needs review). Unlike
--      436's person_cancelled, it holds whatever VIP state the checkout's own
--      order gives them.
--
-- NOT CHANGED
--
--   Every other function, table, column, constraint and grant.
--   event_web_person_view and event_web_person_vip_state (the website still
--   reads can_upgrade false, reason 'cancelled', for them), event_web_vip_checkout,
--   event_web_vip_paid and event_web_vip_transfer (they read 449's problems),
--   event_vip_make_invoices, event_web_planning_answers (refused
--   person_cancelled while held), event_web_sync (status 'cancelled' while
--   held; 'registered' once put back), event_registration_attach and
--   event_registration_create_customer (they refuse someone not waiting to be
--   matched: "This registration is not waiting to be matched."), 433's
--   hold_reason column and its check, the contract.
--   415's, 436's, 439's, 441's and 444's own files refuse to run again after
--   449, as each is live and none is run again (each pins one of the five at
--   the version 449 changes: event_set_guest_cancelled is 415's, which 436
--   relies on; event_web_register is 436's, pinned by 439 and 441;
--   event_vip_person_problems is 436's, pinned by 441 and 444;
--   event_registration_close and event_web_guest_extras are 444's). The 439,
--   441 and 444 suites accept 449's AFTER md5s where it is applied.
--
-- NOT COVERED (to tell the owner)
--
--   * Nobody tells the person when staff put them back: the app sends nothing
--     and the website no confirmation email. The website's page says the team
--     will confirm their place on WhatsApp and send their personal link (for
--     VIP) then, and Put back reminds staff to (Guests tab: Copy VIP link).
--     A SendFox add on Put back would most likely send nothing (they are on
--     its lists from their first sign-up, and SendFox cannot carry the link):
--     not built.
--   * Answers for the day given while held are saved by the website's sync
--     once they are back: the newest form's, at the version the app keeps
--     (the timing of their other days kept), so answers staff changed after
--     that sign-up stand (refused changed_meanwhile). Until then the
--     Registrations row keeps showing them (Answers To Send).
--   * Someone taken off the list who signs up again while the app cannot be
--     reached sees the website's usual pending page ("Registered", "A
--     confirmation email is on its way"). When the website's sync sends the
--     form later, the app holds them; the row says "held for staff", SendFox
--     "Not added: held…", and no email goes out. Nothing tells them their
--     place is to be confirmed: staff see them under To match and contact
--     them (e.g. WhatsApp). The website cannot know it at sign-up.
--   * Their VIP link page says "Not registered any more" while held (the app's
--     reason 'cancelled', unchanged).
--   * A Close of a hold while a VIP payment of theirs waits (needs review:
--     paid while held) is not refused, unlike 444's Close of a registration:
--     the payment stays on Website orders (its reason: put them back first),
--     where a Manager refunds it, or invoices it by hand after all.
--   * A Manager can still invoice a payment that waits for a held person
--     (Website orders, Create invoices; 436's event_vip_order_invoice reads
--     no problems): they become VIP while their free record stays off the
--     list, and the hold stops showing (their VIP record stands).
--   * Someone taken off the list who has NOT signed up again (or whose
--     registration staff closed) can still start a VIP checkout through a
--     crafted request (436's check, above; the website offers them no VIP),
--     and their HitPay payment would be invoiced: not changed here (beyond
--     the owner's answer). Refusing them too is one more condition in
--     event_vip_person_problems.
--   * A Close from a stale page on a hold someone else has just put back is
--     refused, but a Put back from a stale page after a Close restores them
--     (the Guests tab's Restore does, as it always could; audited).
--
-- DEPLOY ORDER (each step with the owner's go-ahead)
--
--   After 445 (production 83a90dbfc238c7f6048c8dc9e435d876, 1370 functions,
--   22 Oct 2026, head 20261022010145). 446, 447 and 448 (another session's)
--   must not change any function this file changes or relies on (below), or
--   this file refuses to run: re-test then.
--   1. The website (rev22-healthtalk-seminar): it reads days: [] as "held";
--      before 449 the app never answers it, so nothing changes until step 4.
--      It also keeps a person's Answers To Send when the app refuses their
--      answers as person_cancelled (taken off the list), held or not, and a
--      held person's while the app says they are not registered, so its sync
--      saves them once staff put them back.
--      The live site (dc3115b on 22 Oct 2026; its sign-up code is 8156aa3's)
--      with 449 but not this step would say such a person is registered
--      (with no days) and add them to SendFox: so this step first, and a
--      gate: before step 3, check that the commit Vercel serves has
--      heldAgain() (src/lib/registration.ts).
--   2. The Event page: the To match panel lists such a hold with "Put back on
--      the list" and Close; the Guests tab marks the cancelled row "Signed up
--      again". Before 449 there are none, and the page before it shows 449's
--      holds with their reason as a code (Attach and New customer are refused
--      for them, Close leaves them off; Restore on the Guests tab puts them
--      back).
--   3. Dry run on a copy of production as it is then: apply this file twice.
--      The first run ends with the fingerprint below; the second says
--      "already this version; left alone" for each function and "the three
--      columns are already there" and changes nothing.
--   4. Apply this file (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself (every AFTER md5, the grants, the columns,
--      its self-test, which leaves no row).
--
-- SAFETY
--
--   One DO block after "set lock_timeout", atomic whatever runs it; every
--   check before anything is changed:
--   * every function it relies on and does not change is as production had
--     it on 22 Oct 2026 (below); the columns and statuses it reads are.
--   * the three columns are either all missing (added, with the check) or all
--     there exactly as this file adds them (left alone); anything else is
--     refused.
--   * each of the five it changes is production's version (patched, each
--     anchor found once, the text built has the tested md5) or already this
--     file's AFTER (left alone); anything else is refused.
--   * afterwards every md5 is the AFTER one, the five keep their grants (ACLs
--     unchanged: the three page functions signed-in staff's, register and
--     the problems the service role's), the page functions still check the
--     caller first (require_active_staff), and the table is still no
--     client's.
--   * a self-test, in a block that is always undone (it ends by raising
--     P0449, so it leaves no row): a made-up Owner, store and two-day event
--     with a VIP ticket and a live key. A registers, staff take A off ("Cannot
--     come"), A signs up again with a new day: held (days: [], already
--     registered, the guest still cancelled); again: the same hold, the days
--     added, two audit rows; a VIP checkout is refused person_cancelled; the
--     page lists one hold, signed_up_again; Put back: registered on both
--     days, the hold resolved, audited; a Close after it is refused. B is
--     taken off, signs up again and the Owner closes it: still off, the hold
--     resolved, not closed as a registration; B signs up again: held again.
--     A second run changes nothing.
--
-- BEFORE (production, 22 Oct 2026, after 445; pg_get_functiondef with search_path public):
--   changed
--   event_web_register(uuid,jsonb)                                 e3efd309e81d17c97f7984f7ecbaafff
--   event_web_guest_extras(uuid)                                   369914bd689e9aa1d34e8e2d887b1d43  (page)
--   event_set_guest_cancelled(uuid,boolean,text)                   f58e462efb1f14e604ee62a7feec6b09  (page)
--   event_registration_close(uuid,text)                            ae3df7387a2057281778258ead3aa4df  (page)
--   event_vip_person_problems(uuid)                                dc4b811edcaaa4710a8a617e3f53b625
--   relied on, not changed
--   require_active_staff(text[])                                   877b3aa74cea559881979bb161c450e2
--   event_can_run(uuid)                                            dac12d0086533bb528e847eb828809df
--   user_has_store_access(uuid)                                    708992afaa6c3951f6329239b742987c
--   is_owner_or_manager()                                          a98e50f1b6d3fa1e6c62cf52a8073cc8
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   event_web_call(text,uuid,text,jsonb)                           e114ba39de4923cc52ed426e27d9bfde
--   event_web_open_state(uuid)                                     ef87a22efbb62f69759838db2dfc0d0c
--   event_web_person_view(uuid)                                    e4cf4ae412699afb1f3fa1011cbe0165
--   event_web_person_vip_state(uuid)                               fc0a3c9ce094fe72e69cff7f420837b6
--   event_web_person(uuid,jsonb)                                   d23601d1d971b665f7f158cd0100319f
--   event_web_vip_checkout(uuid,jsonb)                             3b94aad78b7213e1af9261f326398153
--   event_web_planning_state(uuid)                                 67f23830517ff8753ac580e90d31225f
--   event_web_planning_answers(uuid,jsonb)                         104e2a5e640d882ff73762f56e2c4e38
--   event_web_sync(uuid,jsonb)                                     954db00575a61dd158c4457cfa235249
--   event_registration_attach(uuid,uuid,text)                      b31be4d82d20000df026e7cfa9b24095
--   event_registration_create_customer(uuid,text)                  23bc6941cd4b4db0fae101965292a324
--   event_web_referral_note(uuid)                                  d68893db63938cc774b157708bd341f1
--   event_day_load(uuid)                                           b353d9ca55be4fdc751ef4ca3771dfc5
--   trg_event_vip_guest_follow()                                   23ebf956a5ab203637588a4b9982956c
--   trg_event_vip_parked_guest()                                   b1cc2d78ed6aac5e76ff08d9a78a0bba
--   event_web_vip_paid(uuid,jsonb)                                 1e1e48047b36af39495ef767a37237c2
--   event_web_vip_transfer(uuid,jsonb)                             ec0aaa21b67316d71786e1f30456c183
--   public function fingerprint (production after 445)               83a90dbfc238c7f6048c8dc9e435d876 (1370 functions)
-- AFTER (for later guards):
--   event_web_register(uuid,jsonb)                                 3aad1ad2a8a91732d330b2ef149bf969
--   event_web_guest_extras(uuid)                                   03358fda2da1b4fda082e3f29b512a38  (page)
--   event_set_guest_cancelled(uuid,boolean,text)                   af22a3fad6232dad1a748b9cc1ddb2ae  (page)
--   event_registration_close(uuid,text)                            60f3dde4dc9f7d8cc33f5517e54eeed8  (page)
--   event_vip_person_problems(uuid)                                ec2fbe26fa116505cdd56910d17ce9ea
--   event_registration_people: + signed_up_again_at timestamptz, signed_up_again_days date[],
--     signed_up_again_resolved_at timestamptz, check event_registration_people_signed_up_again_check
--   public function fingerprint (production after 445 + 449)         6e368a7e6c22d186edc59798d1d31210 (1370 functions)
--
-- Test: scripts/event-website/tests/event-website-449.sql (begin ... rollback; it applies this
-- file twice, or -v skip_install=1 where it is installed); 436's event-website.sql and
-- event-website-separate-tx.sql, and the 439, 441 and 444 suites (each -v skip_install=1; these three
-- accept 449's AFTER md5s where it is applied) pass with it, and so do the function-grants,
-- staff-only-functions and client-RPC sweeps.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The five functions it changes: BEFORE (production's, 22 Oct 2026) and AFTER ──
  c_sigs constant text[] := array['event_web_register(uuid,jsonb)', 'event_web_guest_extras(uuid)', 'event_set_guest_cancelled(uuid,boolean,text)', 'event_registration_close(uuid,text)', 'event_vip_person_problems(uuid)'];
  c_page constant boolean[] := array[false, true, true, true, false];
  c_before constant text[] := array['e3efd309e81d17c97f7984f7ecbaafff', '369914bd689e9aa1d34e8e2d887b1d43', 'f58e462efb1f14e604ee62a7feec6b09', 'ae3df7387a2057281778258ead3aa4df', 'dc4b811edcaaa4710a8a617e3f53b625'];
  c_after constant text[] := array['3aad1ad2a8a91732d330b2ef149bf969', '03358fda2da1b4fda082e3f29b512a38', 'af22a3fad6232dad1a748b9cc1ddb2ae', '60f3dde4dc9f7d8cc33f5517e54eeed8', 'ec2fbe26fa116505cdd56910d17ce9ea'];
  -- each anchor (found once in its function's BEFORE text) and its patch, in order
  c_fn constant int[] := array[1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 4, 4, 5];
  c_anchor constant text[] := array[
$a01$  v_guest public.event_guests%rowtype; v_outcome text; v_mail_ok boolean; v_self boolean;
begin
$a01$,
$a02$        elsif v_guest.id is not null and coalesce(v_guest.cancelled_reason, '') not like 'Upgraded to VIP%' then
          perform public.write_audit_ex('event_guests', v_guest.id, 'event_guest_register_again_refused',
            jsonb_build_object('status', v_guest.status, 'cancelled_reason', v_guest.cancelled_reason),
            jsonb_build_object('event_id', e.id, 'source', 'website', 'registration_id', v_regid, 'days', to_jsonb(v_days)), 'events',
            'Registered again on the website after staff took them off the list: left off (restore them on the Guests tab if they may come)', null);
        end if;
$a02$,
$a03$      v_rows := v_rows || jsonb_build_object('position', i, 'person_id', v_prev.id, 'upgrade_token', v_prev.upgrade_token,
        'days', (public.event_web_person_view(v_prev.id))->'days', 'already_registered', true,
        'vip', public.event_web_person_vip_state(v_prev.id));
      v_prev := null;
      continue;
$a03$,
$a04$                 'closed', p.match = 'closed',
                 'match', p.match,
$a04$,
$a05$      select jsonb_agg(jsonb_build_object('person_id', p.id, 'guest_id', p.free_guest_id, 'registration_id', r.registration_id,
               'position', p.position, 'group_size', r.people_count, 'held_at', p.created_at, 'reason', p.hold_reason,
               'full_name', p.full_name, 'phone', p.phone, 'phone_norm', p.phone_norm, 'email', p.email, 'days', to_jsonb(p.days),
               'referral_note', public.event_web_referral_note(p.id),
               'vip_waiting', exists (select 1 from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
$a05$,
$a06$                                 order by o.expires_at desc limit 1),
               'candidates', coalesce((
                 select jsonb_agg(jsonb_build_object('customer_id', c.id, 'full_name', c.full_name, 'phone', c.phone,
$a06$,
$a07$                   join public.customers c on c.id = m.id
                  where c.deleted_at is null), '[]'::jsonb))
             order by p.created_at, p.position)
        from public.event_registration_people p
        join public.event_registrations r on r.id = p.registration_ref
       where p.event_id = p_event_id and p.match = 'held' and not p.is_test), '[]'::jsonb),
    'gift_choices', coalesce((select jsonb_agg(jsonb_build_object('product_id', pr.id, 'name', pr.name,
$a07$,
$a08$declare g public.event_guests%rowtype; v_dropped date[] := '{}';
begin
$a08$,
$a09$  else
    if g.status = 'cancelled' then
$a09$,
$a10$     where id = p_guest_id and status = 'cancelled';
  end if;
$a10$,
$a11$    jsonb_build_object('status', g.status), jsonb_build_object('event_id', g.event_id)
      || case when cardinality(v_dropped) > 0 then jsonb_build_object('days_dropped', to_jsonb(v_dropped)) else '{}'::jsonb end,
    'events', nullif(btrim(coalesce(p_reason, '')), ''), null);
$a11$,
$a12$    'days_dropped', to_jsonb(v_dropped),
    'over_capacity', case when p_cancelled then '[]'::jsonb else
$a12$,
$a13$declare p public.event_registration_people%rowtype; v_state text; v_inv_no text;
  v_closed jsonb := '[]'::jsonb; c record;
begin
$a13$,
$a14$  if p.match = 'closed' then raise exception 'This registration is already closed.'; end if;
  v_state := public.event_web_person_vip_state(p.id);
$a14$,
$a15$        'text', format('Person %s on this order has another VIP payment waiting (%s)', r.position, v_other));
    elsif v_view->>'reason' = 'cancelled' then
$a15$];
  c_patch constant text[] := array[
$p01$  v_guest public.event_guests%rowtype; v_outcome text; v_mail_ok boolean; v_self boolean;
  v_held boolean := false; v_hold_open boolean; v_now_closed boolean := false;
begin
$p01$,
$p02$        elsif v_guest.id is not null and coalesce(v_guest.cancelled_reason, '') not like 'Upgraded to VIP%' then
          -- 449 (the owner, 22 Oct 2026: "Hold for staff to decide"): still off
          -- the list, and held for staff under To match ("Signed up again after
          -- being taken off the list"): they put them back (with the days asked
          -- now) or an Owner or Manager closes it. Signing up again while held
          -- updates the same hold (the days asked are added); one audit row per
          -- sign-up. The website is told no days (days: []): their place is to
          -- be confirmed, nothing is confirmed by email, no VIP is offered.
          -- Their record is read again and locked (as a Close locks it): if
          -- staff closed their registration while this sign-up waited, they
          -- sign up as someone new (below), as after a Close. The hold starts
          -- no earlier than the removal it answers (a removal that committed
          -- while this sign-up waited is later than its now()), so it is
          -- always seen as open.
          select * into v_prev from public.event_registration_people where id = v_prev.id for update;
          if v_prev.match = 'closed' then
            v_now_closed := true;
          else
            v_hold_open := v_prev.signed_up_again_at is not null and v_prev.signed_up_again_resolved_at is null
                           and v_prev.signed_up_again_at >= coalesce(v_guest.cancelled_at, '-infinity'::timestamptz);
            update public.event_registration_people
               set signed_up_again_at = case when v_hold_open then signed_up_again_at else greatest(now(), v_guest.cancelled_at) end,
                   signed_up_again_days = case when v_hold_open
                                               then array(select distinct d from unnest(signed_up_again_days || v_days) d order by 1)
                                               else v_days end,
                   signed_up_again_resolved_at = null, updated_at = now()
             where id = v_prev.id;
            perform public.write_audit_ex('event_guests', v_guest.id, 'event_guest_register_again_refused',
              jsonb_build_object('status', v_guest.status, 'cancelled_reason', v_guest.cancelled_reason),
              jsonb_build_object('event_id', e.id, 'source', 'website', 'registration_id', v_regid, 'days', to_jsonb(v_days),
                                 'person_id', v_prev.id, 'hold', case when v_hold_open then 'updated' else 'opened' end), 'events',
              'Signed up again on the website after staff took them off the list: held for staff (To match: put them back on the list, or close it)', null);
            v_held := true;
          end if;
        end if;
$p02$,
$p03$      -- 449: closed while this sign-up waited (above): not them any more; a new sign-up, below.
      if not v_now_closed then
        v_rows := v_rows || jsonb_build_object('position', i, 'person_id', v_prev.id, 'upgrade_token', v_prev.upgrade_token,
          'days', case when v_held then '[]'::jsonb else (public.event_web_person_view(v_prev.id))->'days' end, 'already_registered', true,
          'vip', public.event_web_person_vip_state(v_prev.id));
        v_prev := null; v_held := false;
        continue;
      end if;
      v_prev := null; v_now_closed := false;
$p03$,
$p04$                 'closed', p.match = 'closed',
                 -- 449 (the owner, 22 Oct 2026): on their free record while they wait for staff after
                 -- signing up again once taken off the list (To match: put back, or closed)
                 'signed_up_again', case when g.id = p.free_guest_id and p.match <> 'closed' and not p.is_test
                                          and p.signed_up_again_at is not null and p.signed_up_again_resolved_at is null
                                          and g.status = 'cancelled' and coalesce(g.cancelled_reason, '') not like 'Upgraded to VIP%'
                                          and p.signed_up_again_at >= coalesce(g.cancelled_at, '-infinity'::timestamptz)
                                          and not exists (select 1 from public.event_guests vg
                                                           where vg.id = p.vip_guest_id and vg.status = 'registered')
                                    then jsonb_build_object('held_at', p.signed_up_again_at, 'days', to_jsonb(p.signed_up_again_days)) end,
                 'match', p.match,
$p04$,
$p05$      select jsonb_agg(jsonb_build_object('person_id', p.id, 'guest_id', p.free_guest_id, 'registration_id', r.registration_id,
               'position', p.position, 'group_size', r.people_count,
               -- 449 (the owner, 22 Oct 2026): someone staff took off the list who signed up again waits here
               -- too (reason signed_up_again, unless they also wait to be matched), until put back or closed
               'held_at', case when p.match = 'held' then p.created_at else p.signed_up_again_at end,
               'reason', case when p.match = 'held' then p.hold_reason else 'signed_up_again' end,
               'full_name', p.full_name, 'phone', p.phone, 'phone_norm', p.phone_norm, 'email', p.email, 'days', to_jsonb(p.days),
               'referral_note', public.event_web_referral_note(p.id),
               'signed_up_again', case when again.open then jsonb_build_object('held_at', p.signed_up_again_at,
                                    'days', to_jsonb(p.signed_up_again_days), 'removed_reason', fg.cancelled_reason,
                                    'removed_at', fg.cancelled_at) end,
               'vip_waiting', exists (select 1 from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
$p05$,
$p06$                                 order by o.expires_at desc limit 1),
               'candidates', case when p.match <> 'held' then '[]'::jsonb else coalesce((
                 select jsonb_agg(jsonb_build_object('customer_id', c.id, 'full_name', c.full_name, 'phone', c.phone,
$p06$,
$p07$                   join public.customers c on c.id = m.id
                  where c.deleted_at is null), '[]'::jsonb) end)
             order by case when p.match = 'held' then p.created_at else p.signed_up_again_at end, p.position)
        from public.event_registration_people p
        join public.event_registrations r on r.id = p.registration_ref
        -- 449: their free record, and whether they wait for staff after signing up again once taken off
        -- (not while their VIP record stands: they are on the list as VIP, as 436's sign-up has it)
        left join public.event_guests fg on fg.id = p.free_guest_id
        cross join lateral (select p.match <> 'closed' and p.signed_up_again_at is not null and p.signed_up_again_resolved_at is null
                                   and fg.status = 'cancelled' and coalesce(fg.cancelled_reason, '') not like 'Upgraded to VIP%'
                                   and p.signed_up_again_at >= coalesce(fg.cancelled_at, '-infinity'::timestamptz)
                                   and not exists (select 1 from public.event_guests vg
                                                    where vg.id = p.vip_guest_id and vg.status = 'registered') as open) again
       where p.event_id = p_event_id and not p.is_test and (p.match = 'held' or coalesce(again.open, false))), '[]'::jsonb),
    'gift_choices', coalesce((select jsonb_agg(jsonb_build_object('product_id', pr.id, 'name', pr.name,
$p07$,
$p08$declare g public.event_guests%rowtype; v_dropped date[] := '{}';
  v_p public.event_registration_people%rowtype; v_added date[] := '{}';
begin
$p08$,
$p09$  else
    -- 449 (the owner, 22 Oct 2026: "staff put them back or close it"): a
    -- website person's free guest who signed up again after being taken off
    -- the list (their hold under To match is open): putting them back (here,
    -- or "Put back on the list" there) first adds the days they asked for
    -- then that the event still has, and closes the hold.
    if g.status = 'cancelled' and coalesce(g.cancelled_reason, '') not like 'Upgraded to VIP%' then
      select * into v_p from public.event_registration_people
       where free_guest_id = p_guest_id and match <> 'closed' and not is_test
         and signed_up_again_at is not null and signed_up_again_resolved_at is null
         and signed_up_again_at >= coalesce(g.cancelled_at, '-infinity'::timestamptz)
         and not exists (select 1 from public.event_guests vg
                          where vg.id = event_registration_people.vip_guest_id and vg.status = 'registered')
       order by created_at limit 1
       for update;
      if v_p.id is not null then
        with ins as (
          insert into public.event_guest_days (guest_id, day)
          select p_guest_id, a.d from unnest(v_p.signed_up_again_days) a(d)
           where exists (select 1 from public.event_days ed where ed.event_id = g.event_id and ed.day = a.d)
          on conflict (guest_id, day) do nothing
          returning day)
        select coalesce(array_agg(ins.day order by ins.day), '{}') into v_added from ins;
      end if;
    end if;
    if g.status = 'cancelled' then
$p09$,
$p10$     where id = p_guest_id and status = 'cancelled';
    if v_p.id is not null then
      update public.event_registration_people
         set days = array(select distinct d from unnest(days || v_added) d order by 1),
             signed_up_again_resolved_at = now(), updated_at = now()
       where id = v_p.id;
    end if;
  end if;
$p10$,
$p11$    jsonb_build_object('status', g.status), jsonb_build_object('event_id', g.event_id)
      || case when cardinality(v_dropped) > 0 then jsonb_build_object('days_dropped', to_jsonb(v_dropped)) else '{}'::jsonb end
      || case when v_p.id is not null then jsonb_build_object('signed_up_again', jsonb_build_object('person_id', v_p.id,
           'held_at', v_p.signed_up_again_at, 'days_asked', to_jsonb(v_p.signed_up_again_days), 'days_added', to_jsonb(v_added)))
         else '{}'::jsonb end,
    'events', nullif(btrim(coalesce(p_reason, '')), ''), null);
$p11$,
$p12$    'days_dropped', to_jsonb(v_dropped),
    -- 449: put back after signing up again: the days they asked for then that were added
    'days_added', to_jsonb(v_added), 'signed_up_again', v_p.id is not null,
    'over_capacity', case when p_cancelled then '[]'::jsonb else
$p12$,
$p13$declare p public.event_registration_people%rowtype; v_state text; v_inv_no text;
  v_closed jsonb := '[]'::jsonb; c record; v_again boolean;
begin
$p13$,
$p14$  if p.match = 'closed' then raise exception 'This registration is already closed.'; end if;
  -- 449 (the owner, 22 Oct 2026: "staff put them back or close it"): someone
  -- staff took off the list who signed up again (not waiting to be matched):
  -- Close leaves them off. Their guest record stays cancelled and their
  -- registration as it is (so signing up again holds them again); the hold is
  -- closed, and each HitPay checkout of theirs not paid closes with it, as
  -- below (444). A Close from a page that did not see the hold dealt with
  -- (put back, or closed) changes nothing. While their VIP record stands they
  -- are not held (as below: "is VIP").
  if p.match <> 'held' and p.signed_up_again_at is not null then
    v_again := p.signed_up_again_resolved_at is null and not p.is_test
               and exists (select 1 from public.event_guests fg
                            where fg.id = p.free_guest_id and fg.status = 'cancelled'
                              and coalesce(fg.cancelled_reason, '') not like 'Upgraded to VIP%'
                              and p.signed_up_again_at >= coalesce(fg.cancelled_at, '-infinity'::timestamptz))
               and not exists (select 1 from public.event_guests vg where vg.id = p.vip_guest_id and vg.status = 'registered');
    if not v_again and p.signed_up_again_resolved_at is not null then
      raise exception 'This registration is not waiting for staff any more.'; end if;
    if v_again then
      update public.event_registration_people
         set signed_up_again_resolved_at = now(), updated_at = now()
       where id = p.id;
      -- 444's: their HitPay checkouts not paid (the order locks were taken above) are dismissed, audited.
      for c in
        update public.event_vip_orders o
           set status_before_dismiss = o.status, reason_before_dismiss = o.review_reason, status = 'dismissed',
               review_reason = 'Checkout closed: ' || btrim(p_reason), updated_at = now(), updated_by = auth.uid()
         where o.status = 'pending' and o.provider = 'hitpay' and o.hitpay_payment_id is null and o.hitpay_payment_request_id is null
           and o.paid_at is null and o.amount_paid_cents is null
           and o.id in (select op.order_ref from public.event_vip_order_people op where op.person_id = p.id)
        returning o.id, o.order_id, o.expires_at, o.quantity, o.is_test
      loop
        perform public.write_audit_ex('event_vip_orders', c.id, 'event_vip_checkout_closed',
          jsonb_build_object('status', 'pending', 'expires_at', c.expires_at),
          jsonb_build_object('order_id', c.order_id, 'status', 'dismissed', 'review_reason', 'Checkout closed: ' || btrim(p_reason),
                             'people', c.quantity, 'with_registration', p.id, 'open', c.expires_at > now()),
          'events', btrim(p_reason), (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
        v_closed := v_closed || jsonb_build_object('order_id', c.order_id, 'people', c.quantity, 'open', c.expires_at > now());
      end loop;
      perform public.write_audit_ex('event_registration_people', p.id, 'event_registration_signed_up_again_closed',
        jsonb_build_object('signed_up_again_at', p.signed_up_again_at, 'days_asked', to_jsonb(p.signed_up_again_days)),
        jsonb_build_object('left_off', true, 'guest_id', p.free_guest_id)
        || case when jsonb_array_length(v_closed) > 0 then jsonb_build_object('checkouts_closed', v_closed) else '{}'::jsonb end,
        'events', btrim(p_reason), (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
      return jsonb_build_object('ok', true, 'checkouts_closed', v_closed, 'signed_up_again', 'closed');
    end if;
  end if;
  v_state := public.event_web_person_vip_state(p.id);
$p14$,
$p15$        'text', format('Person %s on this order has another VIP payment waiting (%s)', r.position, v_other));
    -- 449 (the owner, 22 Oct 2026): someone held for staff after signing up again once taken off
    -- the list buys no VIP until staff put them back (a checkout is refused, as anyone no longer
    -- registered; a payment that comes anyway waits for a Manager, with this reason)
    elsif r.signed_up_again_at is not null and r.signed_up_again_resolved_at is null and r.match <> 'closed' and not r.is_test
          and exists (select 1 from public.event_guests fg
                       where fg.id = r.free_guest_id and fg.status = 'cancelled'
                         and coalesce(fg.cancelled_reason, '') not like 'Upgraded to VIP%'
                         and r.signed_up_again_at >= coalesce(fg.cancelled_at, '-infinity'::timestamptz)) then
      v := v || jsonb_build_object('position', r.position, 'person_id', r.id, 'code', 'person_cancelled',
        'text', format('Person %s on this order signed up again after staff took them off the list: put them back on the list first (Guests, To match)', r.position));
    elsif v_view->>'reason' = 'cancelled' then
$p15$];
  -- The three columns and their check, as this file adds them.
  c_cols constant text[] := array['signed_up_again_at timestamp with time zone', 'signed_up_again_days date[]',
                                  'signed_up_again_resolved_at timestamp with time zone'];
  c_con constant text := 'CHECK ((((signed_up_again_at IS NULL) = (signed_up_again_days IS NULL)) AND ((signed_up_again_days IS NULL) OR (cardinality(signed_up_again_days) >= 1)) AND ((signed_up_again_resolved_at IS NULL) OR (signed_up_again_at IS NOT NULL))))';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; k int; i int; v_have int;
  v_texts text[] := array[null, null, null, null, null]::text[];
  v_acls text[] := array[null, null, null, null, null]::text[];
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_event uuid; t_opt uuid; t_live text; t_hash text;
  t_d1 date; t_d2 date; t_ans jsonb; t_a uuid; t_b uuid; t_ga uuid; t_gb uuid; t_ta text; t_x jsonb; t_at timestamptz;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 22 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is changed unless all pass ─────────────────────────
  -- What it relies on and does not change: as production had it on 22 Oct 2026 (after 445).
  for r in select * from (values
      ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
      ('event_can_run(uuid)', 'dac12d0086533bb528e847eb828809df'),
      ('user_has_store_access(uuid)', '708992afaa6c3951f6329239b742987c'),
      ('is_owner_or_manager()', 'a98e50f1b6d3fa1e6c62cf52a8073cc8'),
      ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
      ('event_web_call(text,uuid,text,jsonb)', 'e114ba39de4923cc52ed426e27d9bfde'),
      ('event_web_open_state(uuid)', 'ef87a22efbb62f69759838db2dfc0d0c'),
      ('event_web_person_view(uuid)', 'e4cf4ae412699afb1f3fa1011cbe0165'),
      ('event_web_person_vip_state(uuid)', 'fc0a3c9ce094fe72e69cff7f420837b6'),
      ('event_web_person(uuid,jsonb)', 'd23601d1d971b665f7f158cd0100319f'),
      ('event_web_vip_checkout(uuid,jsonb)', '3b94aad78b7213e1af9261f326398153'),
      ('event_web_planning_state(uuid)', '67f23830517ff8753ac580e90d31225f'),
      ('event_web_planning_answers(uuid,jsonb)', '104e2a5e640d882ff73762f56e2c4e38'),
      ('event_web_sync(uuid,jsonb)', '954db00575a61dd158c4457cfa235249'),
      ('event_registration_attach(uuid,uuid,text)', 'b31be4d82d20000df026e7cfa9b24095'),
      ('event_registration_create_customer(uuid,text)', '23bc6941cd4b4db0fae101965292a324'),
      ('event_web_referral_note(uuid)', 'd68893db63938cc774b157708bd341f1'),
      ('event_day_load(uuid)', 'b353d9ca55be4fdc751ef4ca3771dfc5'),
      ('trg_event_vip_guest_follow()', '23ebf956a5ab203637588a4b9982956c'),
      ('trg_event_vip_parked_guest()', 'b1cc2d78ed6aac5e76ff08d9a78a0bba'),
      ('event_web_vip_paid(uuid,jsonb)', '1e1e48047b36af39495ef767a37237c2'),
      ('event_web_vip_transfer(uuid,jsonb)', 'ec0aaa21b67316d71786e1f30456c183')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '449: public.% is missing or not the version this was tested against (production, 22 Oct 2026). Re-read it and re-test before applying.', r.fn;
    end if;
  end loop;

  -- The columns 449 reads and writes, as read on 22 Oct 2026.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values
      ('public.event_registration_people', 'id uuid'), ('public.event_registration_people', 'event_id uuid'),
      ('public.event_registration_people', 'is_test boolean'), ('public.event_registration_people', 'match text'),
      ('public.event_registration_people', 'days date[]'), ('public.event_registration_people', 'free_guest_id uuid'),
      ('public.event_registration_people', 'vip_guest_id uuid'), ('public.event_registration_people', 'upgrade_token text'),
      ('public.event_registration_people', 'full_name text'), ('public.event_registration_people', 'email text'),
      ('public.event_registration_people', 'created_at timestamp with time zone'),
      ('public.event_registration_people', 'updated_at timestamp with time zone'),
      ('public.event_guests', 'id uuid'), ('public.event_guests', 'event_id uuid'), ('public.event_guests', 'source text'),
      ('public.event_guests', 'status text'), ('public.event_guests', 'cancelled_reason text'),
      ('public.event_guests', 'cancelled_at timestamp with time zone'),
      ('public.event_guest_days', 'guest_id uuid'), ('public.event_guest_days', 'day date'),
      ('public.event_days', 'event_id uuid'), ('public.event_days', 'day date')) x(t, c)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass(x.t) and a.attnum > 0 and not a.attisdropped
                        and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.c);
  if v is not null then
    raise exception '449: these columns are missing or not as read on 22 Oct 2026 (are 436 and 444 applied?): %', v; end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.event_guests'::regclass and c.conname = 'event_guests_status')
     is distinct from 'CHECK ((status = ANY (ARRAY[''registered''::text, ''cancelled''::text])))'
     or (select pg_get_constraintdef(c.oid) from pg_constraint c
          where c.conrelid = 'public.event_registration_people'::regclass and c.conname = 'event_registration_people_match_check')
        is distinct from 'CHECK ((match = ANY (ARRAY[''exact''::text, ''same_words''::text, ''new_customer''::text, ''held''::text, ''staff_attached''::text, ''staff_created''::text, ''closed''::text, ''test''::text])))'
     or not exists (select 1 from pg_index x where x.indrelid = 'public.event_guest_days'::regclass and x.indisunique
                      and (select array_agg(a.attname::text order by a.attname) from pg_attribute a
                            where a.attrelid = x.indrelid and a.attnum = any (x.indkey)) = array['day', 'guest_id']) then
    raise exception '449: event_guests'' statuses, event_registration_people''s matches or event_guest_days'' (guest_id, day) key are not as read on 22 Oct 2026'; end if;

  -- The three columns: all missing (added below), or all exactly this file's (left alone).
  select count(*) into v_have from pg_attribute a
   where a.attrelid = 'public.event_registration_people'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('signed_up_again_at', 'signed_up_again_days', 'signed_up_again_resolved_at');
  if v_have = 3 then
    if (select count(*) from pg_attribute a
         where a.attrelid = 'public.event_registration_people'::regclass and a.attnum > 0 and not a.attisdropped
           and not a.attnotnull and not a.atthasdef
           and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = any (c_cols)) <> 3
       or (select pg_get_constraintdef(c.oid) from pg_constraint c
            where c.conrelid = 'public.event_registration_people'::regclass
              and c.conname = 'event_registration_people_signed_up_again_check') is distinct from c_con then
      raise exception '449: event_registration_people has the three signed_up_again columns, but not as this file adds them'; end if;
    raise notice '449: the three columns are already there; left alone';
  elsif v_have <> 0
        or exists (select 1 from pg_constraint c where c.conrelid = 'public.event_registration_people'::regclass
                     and c.conname = 'event_registration_people_signed_up_again_check') then
    raise exception '449: event_registration_people has some of the signed_up_again columns (or their check) already: re-read it';
  end if;

  -- The five: BEFORE (production's, 22 Oct 2026) patched, each anchor once; or AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    d := pg_get_functiondef(('public.' || c_sigs[k])::regprocedure);
    v_acls[k] := (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure);
    if md5(d) = c_after[k] then
      raise notice '449: public.% is already this version; left alone', c_sigs[k];
    elsif md5(d) <> c_before[k] then
      raise exception '449: public.% is not the version in production on 22 Oct 2026 (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d);
    else
      for i in 1 .. cardinality(c_fn) loop
        continue when c_fn[i] <> k;
        n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
        if n <> 1 then raise exception '449: anchor % of public.% was found % times, not once', i, c_sigs[k], n; end if;
        d := replace(d, c_anchor[i], c_patch[i]);
      end loop;
      if md5(d) <> c_after[k] then
        raise exception '449: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
      v_texts[k] := d;
    end if;
  end loop;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  if v_have = 0 then
    alter table public.event_registration_people
      add column signed_up_again_at timestamptz,
      add column signed_up_again_days date[],
      add column signed_up_again_resolved_at timestamptz,
      add constraint event_registration_people_signed_up_again_check
        check ((signed_up_again_at is null) = (signed_up_again_days is null)
               and (signed_up_again_days is null or cardinality(signed_up_again_days) >= 1)
               and (signed_up_again_resolved_at is null or signed_up_again_at is not null));
    comment on column public.event_registration_people.signed_up_again_at is
      '449: when they signed up again on the website after staff took them off the guest list (the hold for staff started; null: never)';
    comment on column public.event_registration_people.signed_up_again_days is
      '449: every day they asked for while held (added to their guest record when staff put them back)';
    comment on column public.event_registration_people.signed_up_again_resolved_at is
      '449: when staff put them back or closed the hold (null while it waits)';
  end if;
  for k in 1 .. cardinality(c_sigs) loop
    if v_texts[k] is not null then execute v_texts[k]; end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(('public.' || c_sigs[k])::regprocedure)) <> c_after[k] then
      raise exception '449: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_sigs[k], 'execute') is distinct from c_page[k]
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '449: the grants of public.% changed', c_sigs[k]; end if;
    if c_page[k] and pg_get_functiondef(('public.' || c_sigs[k])::regprocedure) !~ E'\nbegin\n  perform public\\.require_active_staff\\(' then
      raise exception '449: public.% does not check the caller first', c_sigs[k]; end if;
  end loop;
  if (select count(*) from pg_attribute a
       where a.attrelid = 'public.event_registration_people'::regclass and a.attnum > 0 and not a.attisdropped
         and not a.attnotnull and not a.atthasdef
         and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = any (c_cols)) <> 3
     or (select pg_get_constraintdef(c.oid) from pg_constraint c
          where c.conrelid = 'public.event_registration_people'::regclass
            and c.conname = 'event_registration_people_signed_up_again_check') is distinct from c_con
     or has_any_column_privilege('anon', 'public.event_registration_people', 'select,insert,update,references')
     or has_any_column_privilege('authenticated', 'public.event_registration_people', 'select,insert,update,references')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.event_registration_people'::regclass) then
    raise exception '449: event_registration_people is not as this file leaves it (the three columns, their check, no client''s)'; end if;

  -- ── 4. Behaviour, in a block that is always undone ──────────────────────
  -- Made-up records only ("449 check", @example.invalid, fictional phones);
  -- it ends by raising P0449, which undoes all it wrote.
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_sfx := upper(substr(md5(gen_random_uuid()::text), 1, 8));
    t_d1 := public.sg_today() + 30; t_d2 := t_d1 + 1;
    select array_agg(x order by x) into t_phones
      from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(7000, 7999) g
             where not exists (select 1 from public.customers c
                                where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(g::text, 4, '0'))
             limit 2) y;
    insert into auth.users (id, email) values (gen_random_uuid(), '449-check-' || lower(t_sfx) || '@example.invalid')
      returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '449 check', u.email, 'owner', true from auth.users u where u.id = t_owner;
    insert into public.stores (name, code, country_code) values ('449 check ' || t_sfx, '449-' || t_sfx, 'SG') returning id into t_store;
    insert into public.events (name, daily_start, daily_end, is_active) values ('449 check ' || t_sfx, '09:00', '19:00', true)
      returning id into t_event;
    insert into public.event_days (event_id, day) values (t_event, t_d1), (t_event, t_d2);
    insert into public.event_stores (event_id, store_id) values (t_event, t_store);
    insert into public.event_ticket_options (event_id, name, days_count, price, is_active) values (t_event, 'VIP', 2, 72, true)
      returning id into t_opt;
    insert into public.event_web_settings (event_id, code, mode, store_id, acting_profile_id, vip_option_id)
    values (t_event, 'CHECK449-' || t_sfx, 'live', t_store, t_owner, t_opt);
    t_live := 'evk_live_' || rpad(t_sfx, 43, 'L');
    t_hash := encode(extensions.digest(t_live, 'sha256'), 'hex');
    insert into public.event_web_keys (event_id, kind, key_hash, key_hint, created_by)
    values (t_event, 'live', t_hash, '449 check', t_owner);
    -- A and B register (Day 1), each on a phone and email nobody has: new customers on the guest list.
    foreach v in array array['a', 'b'] loop
      t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
        jsonb_build_object('type', 'register', 'event', 'CHECK449-' || t_sfx, 'registration', jsonb_build_object(
          'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || v || '0'), 1, 8)),
          'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
            jsonb_build_object('position', 1, 'first_name', case v when 'a' then 'Ada' else 'Bea' end, 'last_name', 'Again',
                               'phone', t_phones[case v when 'a' then 1 else 2 end],
                               'email', v || '-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(t_d1), 'vip', false)))));
      if v = 'a' then t_a := (t_ans->'people'->0->>'person_id')::uuid; t_ta := t_ans->'people'->0->>'upgrade_token';
      else t_b := (t_ans->'people'->0->>'person_id')::uuid; end if;
    end loop;
    select p.free_guest_id into t_ga from public.event_registration_people p where p.id = t_a;
    select p.free_guest_id into t_gb from public.event_registration_people p where p.id = t_b;
    if t_ga is null or t_gb is null then raise exception '449: the self-test''s registrations were not made: %', t_ans; end if;
    -- Staff take both off the list.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform public.event_set_guest_cancelled(t_ga, true, 'Cannot come');
    perform public.event_set_guest_cancelled(t_gb, true, 'Cannot come');
    -- A signs up again (Day 2), then again (both days): held once, the days added, two audit rows.
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    foreach v in array array['1', '2'] loop
      t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
        jsonb_build_object('type', 'register', 'event', 'CHECK449-' || t_sfx, 'registration', jsonb_build_object(
          'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'a' || v), 1, 8)),
          'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
            jsonb_build_object('position', 1, 'first_name', 'Ada', 'last_name', 'Again', 'phone', t_phones[1],
                               'email', 'a-' || lower(t_sfx) || '@example.invalid',
                               'days', case v when '1' then jsonb_build_array(t_d2) else jsonb_build_array(t_d1, t_d2) end, 'vip', false)))));
      if t_ans->'people'->0 is distinct from jsonb_build_object('position', 1, 'person_id', t_a, 'upgrade_token', t_ta,
                                                                'days', '[]'::jsonb, 'already_registered', true, 'vip', 'none') then
        raise exception '449: the self-test''s sign-up after being taken off is not answered as held: %', t_ans; end if;
      if v = '1' then select p.signed_up_again_at into t_at from public.event_registration_people p where p.id = t_a; end if;
    end loop;
    if (select (g.status, g.cancelled_reason) is distinct from ('cancelled'::text, 'Cannot come'::text) from public.event_guests g where g.id = t_ga)
       or (select array_agg(gd.day order by gd.day) from public.event_guest_days gd where gd.guest_id = t_ga) is distinct from array[t_d1]
       or (select (p.days, p.signed_up_again_at, p.signed_up_again_days, p.signed_up_again_resolved_at)
                  is distinct from (array[t_d1], t_at, array[t_d1, t_d2], null::timestamptz)
             from public.event_registration_people p where p.id = t_a)
       or (select count(*) from public.audit_logs l where l.record_id = t_ga and l.action = 'event_guest_register_again_refused') <> 2 then
      raise exception '449: the self-test''s hold is not one hold with the days asked, the guest left as it was'; end if;
    -- While held, VIP is refused (nothing kept), as 436 refuses anyone taken off.
    t_x := public.event_web_call(t_hash, gen_random_uuid(), 'vip_checkout', jsonb_build_object('type', 'vip_checkout',
      'event', 'CHECK449-' || t_sfx, 'order', jsonb_build_object(
        'order_id', 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'vip'), 1, 8)),
        'upgrade_tokens', jsonb_build_array(t_ta),
        'payer', jsonb_build_object('name', 'Check Payer', 'email', 'payer-' || lower(t_sfx) || '@example.invalid', 'phone', null),
        'livemode', true, 'checkout_opened_at', now() - interval '1 minute')));
    if t_x->>'status' is distinct from 'refused' or t_x->>'reason' is distinct from 'person_cancelled'
       or exists (select 1 from public.event_vip_orders o where o.event_id = t_event) then
      raise exception '449: the self-test''s VIP checkout while held was not refused: %', t_x; end if;
    -- The page lists A once, as signed up again; Put back brings A back on both days and ends the hold.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    t_x := public.event_web_guest_extras(t_event);
    if (select count(*) from jsonb_array_elements(t_x->'holds') h where (h->>'person_id')::uuid = t_a) <> 1
       or (select h->>'reason' from jsonb_array_elements(t_x->'holds') h where (h->>'person_id')::uuid = t_a) is distinct from 'signed_up_again'
       or (select h->'signed_up_again'->'days' from jsonb_array_elements(t_x->'holds') h where (h->>'person_id')::uuid = t_a)
          is distinct from jsonb_build_array(t_d1, t_d2)
       or (select g->'signed_up_again'->>'held_at' from jsonb_array_elements(t_x->'guests') g where (g->>'guest_id')::uuid = t_ga) is null then
      raise exception '449: the self-test''s hold is not on the page: %', t_x->'holds'; end if;
    t_x := public.event_set_guest_cancelled(t_ga, false, '449 check');
    if t_x->'days_added' is distinct from jsonb_build_array(t_d2) or (t_x->>'signed_up_again')::boolean is distinct from true
       or (select g.status from public.event_guests g where g.id = t_ga) is distinct from 'registered'
       or (select array_agg(gd.day order by gd.day) from public.event_guest_days gd where gd.guest_id = t_ga) is distinct from array[t_d1, t_d2]
       or (select (p.days, p.signed_up_again_resolved_at is not null) is distinct from (array[t_d1, t_d2], true)
             from public.event_registration_people p where p.id = t_a)
       or not exists (select 1 from public.audit_logs l where l.record_id = t_ga and l.action = 'event_guest_restored'
                        and l.new_data->'signed_up_again'->'days_added' = jsonb_build_array(t_d2))
       or exists (select 1 from jsonb_array_elements(public.event_web_guest_extras(t_event)->'holds') h where (h->>'person_id')::uuid = t_a) then
      raise exception '449: the self-test''s Put back did not bring A back on both days and end the hold: %', t_x; end if;
    begin
      perform public.event_registration_close(t_a, '449 check');
      raise exception '449: the self-test''s Close after Put back was not refused';
    exception when raise_exception then
      if sqlerrm <> 'This registration is not waiting for staff any more.' then raise; end if;
    end;
    -- B signs up again and the Owner closes it: still off, the hold ended, not closed as a registration; again: held again.
    foreach v in array array['1', '2'] loop
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', 'service_role', true);
      t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
        jsonb_build_object('type', 'register', 'event', 'CHECK449-' || t_sfx, 'registration', jsonb_build_object(
          'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'b' || v), 1, 8)),
          'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
            jsonb_build_object('position', 1, 'first_name', 'Bea', 'last_name', 'Again', 'phone', t_phones[2],
                               'email', 'b-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(t_d2), 'vip', false)))));
      if t_ans->'people'->0->'days' is distinct from '[]'::jsonb then
        raise exception '449: the self-test''s B was not held: %', t_ans; end if;
      perform set_config('request.jwt.claim.sub', t_owner::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      if v = '1' then
        t_x := public.event_registration_close(t_b, '449 check');
        if t_x->>'signed_up_again' is distinct from 'closed'
           or (select (p.match, p.signed_up_again_resolved_at is not null) is distinct from ('new_customer'::text, true)
                 from public.event_registration_people p where p.id = t_b)
           or (select (g.status, g.cancelled_reason) is distinct from ('cancelled'::text, 'Cannot come'::text)
                 from public.event_guests g where g.id = t_gb)
           or (select count(*) from public.audit_logs l where l.record_id = t_b
                 and l.action = 'event_registration_signed_up_again_closed') <> 1 then
          raise exception '449: the self-test''s Close did not leave B off with the hold ended: %', t_x; end if;
      end if;
    end loop;
    if (select p.signed_up_again_resolved_at from public.event_registration_people p where p.id = t_b) is not null
       or (select h->>'reason' from jsonb_array_elements(public.event_web_guest_extras(t_event)->'holds') h
            where (h->>'person_id')::uuid = t_b) is distinct from 'signed_up_again' then
      raise exception '449: the self-test''s B was not held again after Close'; end if;
    raise exception using errcode = 'P0449', message = '449: self-test done, undone';
  exception when sqlstate 'P0449' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
