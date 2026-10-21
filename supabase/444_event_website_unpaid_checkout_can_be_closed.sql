-- 444_event_website_unpaid_checkout_can_be_closed.sql
--
-- AN ONLINE PAYMENT STARTED AND NOT PAID NO LONGER STOPS STAFF (the owner's
-- answer, 21 Oct 2026: "Staff can close it")
--
-- WHAT WAS WRONG / WHY
--
--   Seen in production, 21 Oct 2026: someone registered on the event website
--   was held under To match (their phone is on another customer's record),
--   opened the HitPay checkout for VIP and pressed back without paying. 436
--   keeps such a checkout as a VIP order "pending" for 70 minutes
--   (event_web_vip_checkout: expires_at = opened + 70 min; HitPay's own page
--   lasts 60) with no payment on it. Meanwhile:
--   * event_web_person_vip_state says 'pending', so event_registration_close
--     refused: "A VIP payment for <name> is waiting: deal with it on Website
--     orders first.";
--   * on Website orders, event_vip_order_dismiss refused every live HitPay
--     order ("A HitPay payment took money: ...", although none was taken) and
--     any status but recorded, needs_review or test;
--   * the Website orders list hides open checkouts by default;
--   * the To match panel said "VIP payment waiting" (436's vip_waiting counts
--     a checkout, even an expired one).
--   So an Owner or Manager could do nothing until the checkout expired.
--
-- THE RULES (binding)
--
--   The owner's answer, 21 Oct 2026: "Staff can close it." The page shows
--   "Online payment started, not paid" instead of "VIP payment waiting"; an
--   Owner or Manager can close the registration or the unpaid checkout; if
--   HitPay later reports money anyway, it lands in Website orders for a
--   refund.
--   The owner's answer, 22 Oct 2026: only an Owner or Manager may close an
--   unpaid HitPay checkout, not an Admin. (Closing a registration was
--   already an Owner's or Manager's, 436.)
--   Every earlier answer in 436's and 439's THE RULES stands as written there.
--   How it reads (this file, 21 Oct 2026):
--   * "An online payment started and not paid" (an unpaid checkout) is a VIP
--     order from HitPay still 'pending' with nothing of a payment on it: no
--     HitPay payment request id or payment id, no paid time, no amount paid
--     (event_web_vip_paid writes all four when HitPay reports a payment). It
--     is "open" until its expires_at.
--   * Closing one makes it 'dismissed' (the status the website's contract
--     already names: "a Manager set it aside (never paid, ...)"), with the
--     reason "Checkout closed: <reason>", its status before kept as
--     'pending' (that is how 444 knows a closed checkout), and an audit row
--     event_vip_checkout_closed. It is never reopened: the person starts a
--     new checkout on the website (their VIP link works again while they are
--     registered).
--   * Closing a registration (event_registration_close, an Owner or Manager,
--     as 436) whose only payment waiting is an unpaid checkout goes ahead and
--     closes each unpaid checkout of theirs (open or expired) in the same
--     step. A checkout for several people closes for all of them (the others
--     stay registered and may start a new one). Anything else waiting (money
--     taken, a transfer sent, a test key's payment, a VIP invoice not paid
--     again) still stops it, with 436's words.
--   * Website orders closes an unpaid checkout with a reason
--     (event_vip_order_dismiss on a pending HitPay order): an Owner or
--     Manager only (22 Oct 2026). An Admin is refused ("Only an Owner or
--     Manager can close an unpaid checkout.", 42501) and keeps what 436 gave
--     them there: dismissing and restoring transfers. An order with any part
--     of a payment on it is refused ("HitPay reported a payment for this
--     order: ...").
--   * HitPay reporting a payment for a closed checkout (vip_paid; a test key
--     the same, as its dry run, the close reason cleared): kept for a
--     Manager, needs_review, "The
--     checkout was closed before HitPay reported this payment: refund it in
--     HitPay, or create its invoices by hand if they should still have VIP";
--     never invoiced by itself (a closed person's invoices are refused
--     anyway: 436's "Person N on this order was closed by staff"), never an
--     error. A Manager then closes it as refunded (415's rule) or, for a
--     person still registered, creates its invoices.
--   * The page is told about an unpaid checkout still open (vip_checkout:
--     its order id, when it opened, expires_at, and people: how many it is
--     for) on each website guest and each To match entry, to say "Online
--     payment started, not paid (until HH:MM)", and, when closing a
--     registration, whether the checkout closes for others in their group
--     too. 436's vip_waiting and vip_payment and the website's VIP state
--     ('none' / 'pending' / 'paid' / 'refunded', the contract's) are
--     unchanged.
--
-- WHAT THIS DOES
--
--   1. event_registration_close (page): takes the person's pending orders
--      first (each order's lock, then its row, as event_web_vip_paid does);
--      an unpaid checkout no longer refuses; closing closes each unpaid
--      checkout of theirs as above (audited each); the answer adds
--      checkouts_closed [{order_id, people, open}] and the registration's
--      audit row names them.
--   2. event_vip_order_dismiss (page): the order's lock first; a pending
--      HitPay order with no payment on it is closed as above by an Owner or
--      Manager (answer {ok, checkout_closed: true}; an Admin is refused,
--      42501); one with any payment on it is refused;
--      a closed checkout is not closed again ("This checkout is already
--      closed.") or restored ("A closed checkout is not reopened: the person
--      can start a new one on the website."); a dismiss reason cannot start
--      "Checkout closed:". Everything else as 436.
--   3. event_web_vip_paid (the website's): a payment for a closed checkout is
--      kept for a Manager with the reason above (a test key: test_would
--      needs_review, with a note, and staff's close reason cleared), and the
--      order's status before is cleared.
--   4. event_web_guest_extras (page): vip_checkout {order_id, opened_at,
--      expires_at, people} on website guests and To match entries (null when
--      none is open).
--
-- NOT CHANGED
--
--   Every other function, table and grant. event_web_person_vip_state's
--   values (the site's contract), the contract itself, event_web_vip_checkout
--   (an unpaid checkout still counts as waiting for the website while it is
--   open: a second checkout for the same person is refused until it is
--   closed or expires), event_vip_orders_list (it already gives the page
--   status, expired and the payment fields), event_vip_order_close_refunded,
--   event_vip_make_invoices, 437's, 438's, 440's, 442's and 443's functions,
--   441's event_web_match_customer (not pinned: this file works with or
--   without 441), update_customer and the 432-family helpers.
--   436's, 439's and 441's own files refuse to run again after 444, as each
--   is live and none is run again: 436 refuses any of its functions that is
--   not its own version (event_registration_close, event_vip_order_dismiss,
--   event_web_vip_paid and event_web_guest_extras join those 439 and 441
--   already moved), and 439 and 441 pin event_web_guest_extras at 439's
--   BEFORE 0be416f6... and AFTER 18b56a28... (444's is below).
--
-- NOT COVERED (to tell the owner)
--
--   * Closing one person's registration closes a checkout they share with
--     others in their group (one HitPay checkout for several people): the
--     others stay registered and must start a new checkout to buy VIP.
--   * HitPay's page itself is not cancelled: someone who still pays on it
--     after staff closed the checkout pays, and the payment waits on Website
--     orders (needs review) for a refund in HitPay or invoices by hand. The
--     website's Pay button can take them back to it: for an order whose
--     HitPay page is still open the website goes there without asking the app
--     (src/lib/vip.ts startVipCheckout), and the app answers 'ok' again for an
--     order it already has (event_web_vip_checkout, unchanged; and
--     event_web_call replays an identical request's first answer for 7
--     days), so refusing it here would not stop it. Stopping it is the
--     website's to do (ask the app for the order, or treat a 'Dismissed' row
--     as a fresh start, before going back to HitPay), or the edge function's
--     (expire the HitPay payment request when staff close the checkout).
--
-- DEPLOY ORDER (each step with the owner's go-ahead)
--
--   After 441 (production d8bfc0b83af95d114f2d9f8f2489d3e0, 1370 functions,
--   21 Oct 2026, 441 applied 20261021141939 after 443). 444 pins nothing of
--   441's (441 changes event_web_match_customer alone), so it also applies
--   on 443 without 441 (checked: ends at 16f0f5e018621542467965a69648502b);
--   441 must come first, as it did, because 441 pins event_web_guest_extras
--   (and 436, 439 and 441 are not run again after 444: see NOT CHANGED).
--   1. Dry run on a copy of production as it is then: apply this file twice.
--      The first run ends with the fingerprint below; the second says
--      "already this version; left alone" for each function and changes
--      nothing. A refusal names the function that moved since 21 Oct 2026.
--   2. Apply this file (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself (every AFTER md5, the grants, its
--      self-test, which leaves no row).
--   3. Deploy the Event page (Guests: "Online payment started, not paid
--      (until HH:MM)"; To match: the same, and Close says the checkout closes
--      with it, for how many people; Website orders: "Close unpaid checkout"
--      for an Owner or Manager (not shown to an Admin), open checkouts shown
--      by default). The page before it keeps working with 444 (it ignores
--      vip_checkout; Close works; Dismiss is not offered on a checkout).
--
-- SAFETY
--
--   One DO block after "set lock_timeout", atomic whatever runs it; every check
--   before anything is changed:
--   * every function it relies on and does not change is as production had
--     it on 21 Oct 2026 (below); the columns and statuses it reads are.
--   * each of the four it changes is production's version (patched, each
--     anchor found once, the text built has the tested md5) or already this
--     file's AFTER (left alone); anything else is refused.
--   * afterwards every md5 is the AFTER one, the four keep their grants
--     (ACLs unchanged: the three page functions signed-in staff's, vip_paid
--     the service role's) and the page functions still check the caller
--     first (require_active_staff).
--   * a self-test, in a block that is always undone (it ends by raising
--     P0444, so it leaves no row): a made-up Owner, store, event with a VIP
--     ticket, live key; one form: A held on a customer's phone, B a new
--     customer; each opens a checkout and goes back; the page shows both as
--     started and not paid; a made-up Admin cannot close B's checkout; the
--     Owner closes A's registration (its checkout closes with it) and B's
--     checkout on Website orders (audited); B's
--     cannot be reopened; HitPay then reports a payment for each: both wait
--     for a Manager (needs review), nothing invoiced. A second run changes
--     nothing.
--
-- BEFORE (production, 21 Oct 2026, after 441; pg_get_functiondef with search_path public):
--   changed
--   event_registration_close(uuid,text)                            23baf63e59f00930214890759460a624  (page)
--   event_vip_order_dismiss(uuid,text,boolean)                     c5dd53c43bc64fe3731db16f7be5f24f  (page)
--   event_web_vip_paid(uuid,jsonb)                                 0628bdb6962349980eba6c74997c1a46
--   event_web_guest_extras(uuid)                                   18b56a28bb4965b2188cd73dde056209  (page)
--   relied on, not changed
--   require_active_staff(text[])                                   877b3aa74cea559881979bb161c450e2
--   event_can_run(uuid)                                            dac12d0086533bb528e847eb828809df
--   user_has_store_access(uuid)                                    708992afaa6c3951f6329239b742987c
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   event_web_call(text,uuid,text,jsonb)                           e114ba39de4923cc52ed426e27d9bfde
--   event_web_vip_checkout(uuid,jsonb)                             3b94aad78b7213e1af9261f326398153
--   event_web_person_vip_state(uuid)                               fc0a3c9ce094fe72e69cff7f420837b6
--   event_web_person_view(uuid)                                    e4cf4ae412699afb1f3fa1011cbe0165
--   event_vip_person_problems(uuid)                                dc4b811edcaaa4710a8a617e3f53b625
--   event_vip_dry_run(uuid)                                        85d165123d4a2149396308222a44c5bf
--   event_vip_make_invoices(uuid,boolean)                          026c6f301e6040d9954757ba559839ba
--   event_web_order_answer(uuid)                                   8489cc479d277bdaa702dacba4b152c4
--   event_vip_order_close_refunded(uuid,text,boolean)              e3c7156008dd05b2930f4781163fe286
--   event_vip_orders_list(uuid)                                    f3b2511da3a5baba6e44d507270925a9
--   public function fingerprint (production after 441)               d8bfc0b83af95d114f2d9f8f2489d3e0 (1370 functions)
-- AFTER (for later guards):
--   event_registration_close(uuid,text)                            ae3df7387a2057281778258ead3aa4df  (page)
--   event_vip_order_dismiss(uuid,text,boolean)                     d1b16a09f2376591688feb42585c8146  (page)
--   event_web_vip_paid(uuid,jsonb)                                 1e1e48047b36af39495ef767a37237c2
--   event_web_guest_extras(uuid)                                   369914bd689e9aa1d34e8e2d887b1d43  (page)
--   public function fingerprint (production after 441 + 444)         5fd445602b9c202c178e808ce6263098 (1370 functions)
--
-- Test: scripts/event-website/tests/event-website-444.sql (begin ... rollback; it applies this
-- file twice, or -v skip_install=1 where it is installed); 436's event-website.sql and
-- event-website-separate-tx.sql, and the 439 and 441 suites (each -v skip_install=1; these two
-- accept 444's event_web_guest_extras where it is applied) pass with it, and so do the
-- function-grants, staff-only-functions and client-RPC sweeps.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The four functions it changes: BEFORE (production's, 21 Oct 2026) and AFTER ──
  c_sigs constant text[] := array['event_registration_close(uuid,text)', 'event_vip_order_dismiss(uuid,text,boolean)', 'event_web_vip_paid(uuid,jsonb)', 'event_web_guest_extras(uuid)'];
  c_page constant boolean[] := array[true, true, false, true];
  c_before constant text[] := array['23baf63e59f00930214890759460a624', 'c5dd53c43bc64fe3731db16f7be5f24f', '0628bdb6962349980eba6c74997c1a46', '18b56a28bb4965b2188cd73dde056209'];
  c_after constant text[] := array['ae3df7387a2057281778258ead3aa4df', 'd1b16a09f2376591688feb42585c8146', '1e1e48047b36af39495ef767a37237c2', '369914bd689e9aa1d34e8e2d887b1d43'];
  -- each anchor (found once in its function's BEFORE text) and its patch, in order
  c_fn constant int[] := array[1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 3, 4, 4];
  c_anchor constant text[] := array[
$a01$declare p public.event_registration_people%rowtype; v_state text; v_inv_no text;
begin
  perform public.require_active_staff('{owner,manager}');
  select * into p from public.event_registration_people where id = p_person_id for update;
$a01$,
$a02$      raise exception '%''s VIP invoice % is waiting to be paid: cancel or refund it instead.', p.full_name, v_inv_no; end if;
    raise exception 'A VIP payment for % is waiting: deal with it on Website orders first.', p.full_name;
  end if;
$a02$,
$a03$   where id = p.id;
  perform public.write_audit_ex('event_registration_people', p.id, 'event_registration_closed',
    jsonb_build_object('match', p.match, 'hold_reason', p.hold_reason), jsonb_build_object('match', 'closed'),
    'events', btrim(p_reason), (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
  return jsonb_build_object('ok', true);
end $function$
$a03$,
$a04$  perform public.require_active_staff('{owner,admin,manager}');
  select * into o from public.event_vip_orders where id = p_order_id for update;
$a04$,
$a05$    raise exception 'You do not have access to this event''s store' using errcode = '42501'; end if;
  if o.provider = 'hitpay' and not o.is_test then
$a05$,
$a06$    if btrim(p_reason) ilike 'Refunded outside the app:%' then raise exception 'Use Close as refunded for a refund'; end if;
    update public.event_vip_orders
$a06$,
$a07$  v_unit integer; v_ids uuid[]; t text; i integer := 0; v_pid uuid; v_reasons text[] := '{}'; v_dry jsonb; x jsonb;
  v_missing integer; v_new boolean := false;
begin
$a07$,
$a08$  end if;
  if not found then
$a08$,
$a09$         paid_on = ((v->>'paid_at')::timestamptz at time zone 'Asia/Singapore')::date,
         reference = v->>'payment_request_id', updated_at = now()
   where id = o.id
$a09$,
$a10$    update public.event_vip_orders set status = 'test', test_would = v_dry->>'would', test_note = v_dry->>'note' where id = o.id;
  elsif s.mode = 'off' or e.deleted_at is not null then
$a10$,
$a11$  else
    if v_new and v_missing > 0 then
$a11$,
$a12$                                  where op.person_id = p.id and o.status in ('recorded', 'needs_review') order by o.created_at desc limit 1),
                 'hold', case when p.match = 'held' then jsonb_build_object('reason', p.hold_reason, 'held_at', p.created_at) end,
$a12$,
$a13$                                       where op.person_id = p.id and o.status in ('recorded', 'needs_review')),
               'candidates', coalesce((
$a13$];
  c_patch constant text[] := array[
$p01$declare p public.event_registration_people%rowtype; v_state text; v_inv_no text;
  v_closed jsonb := '[]'::jsonb; c record;
begin
  perform public.require_active_staff('{owner,manager}');
  -- 444 (the owner, 21 Oct 2026: "Staff can close it"): their checkouts not
  -- paid are taken first, as a HitPay payment takes them (the order's lock,
  -- then its row), so a payment arriving now is either seen below or waits
  -- until this is done (and then finds the checkout closed).
  perform pg_advisory_xact_lock(hashtextextended('event-vip-order:' || x.order_id, 0))
     from (select o.order_id from public.event_vip_order_people op
             join public.event_vip_orders o on o.id = op.order_ref
            where op.person_id = p_person_id and o.status = 'pending' order by o.order_id) x;
  perform 1 from public.event_vip_orders o
   where o.status = 'pending' and o.id in (select op.order_ref from public.event_vip_order_people op where op.person_id = p_person_id)
   order by o.id for update;
  select * into p from public.event_registration_people where id = p_person_id for update;
$p01$,
$p02$      raise exception '%''s VIP invoice % is waiting to be paid: cancel or refund it instead.', p.full_name, v_inv_no; end if;
    -- 444: an online payment started and not paid (a HitPay checkout HitPay
    -- has reported no payment for) does not stop it: it is closed with the
    -- registration, below. Anything else waiting (money taken, a transfer
    -- sent, a test's) is dealt with on Website orders first, as before.
    if exists (select 1 from public.event_vip_order_people op
                 join public.event_vip_orders o on o.id = op.order_ref
                where op.person_id = p.id
                  and ((o.status = 'pending' and o.expires_at > now()
                        and not (o.provider = 'hitpay' and o.hitpay_payment_id is null and o.hitpay_payment_request_id is null
                                 and o.paid_at is null and o.amount_paid_cents is null))
                       or o.status in ('recorded', 'needs_review')
                       or (o.status = 'test' and o.test_would in ('recorded', 'needs_review')))) then
      raise exception 'A VIP payment for % is waiting: deal with it on Website orders first.', p.full_name; end if;
  end if;
$p02$,
$p03$   where id = p.id;
  -- 444: each HitPay checkout of theirs not paid (open, or expired) is closed
  -- with it: dismissed, "Checkout closed: <reason>", and audited. A checkout
  -- for several people closes for all of them (the others may start a new
  -- one). A payment HitPay reports for it later waits on Website orders
  -- (needs review: refund it, or invoice it by hand), never invoiced by
  -- itself.
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
  perform public.write_audit_ex('event_registration_people', p.id, 'event_registration_closed',
    jsonb_build_object('match', p.match, 'hold_reason', p.hold_reason),
    jsonb_build_object('match', 'closed')
    || case when jsonb_array_length(v_closed) > 0 then jsonb_build_object('checkouts_closed', v_closed) else '{}'::jsonb end,
    'events', btrim(p_reason), (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
  return jsonb_build_object('ok', true, 'checkouts_closed', v_closed);
end $function$
$p03$,
$p04$  perform public.require_active_staff('{owner,admin,manager}');
  -- 444: the order's lock first, as a HitPay payment takes it, so a payment
  -- arriving while an unpaid checkout is closed finds it closed.
  perform pg_advisory_xact_lock(hashtextextended('event-vip-order:' || x.order_id, 0))
     from public.event_vip_orders x where x.id = p_order_id;
  select * into o from public.event_vip_orders where id = p_order_id for update;
$p04$,
$p05$    raise exception 'You do not have access to this event''s store' using errcode = '42501'; end if;
  -- 444 (the owner, 21 Oct 2026: "Staff can close it"): a HitPay checkout
  -- started and not paid (HitPay has reported no payment for it) is closed
  -- with a reason: dismissed, "Checkout closed: <reason>", and audited. A
  -- payment HitPay reports for it later waits here (needs review). A closed
  -- checkout is not restored: the person starts a new one.
  if o.provider = 'hitpay' and o.status = 'pending' and coalesce(p_dismiss, true) then
    if o.hitpay_payment_id is not null or o.hitpay_payment_request_id is not null or o.paid_at is not null
       or o.amount_paid_cents is not null then
      raise exception 'HitPay reported a payment for this order: create its invoices, or close it as refunded.'; end if;
    -- The owner, 22 Oct 2026: only an Owner or Manager closes an unpaid
    -- checkout, not an Admin. An Admin still dismisses and restores
    -- transfers below, as 436 lets them.
    if public.require_active_staff() not in ('owner', 'manager') then
      raise exception 'Only an Owner or Manager can close an unpaid checkout.' using errcode = '42501'; end if;
    if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason (at least 3 characters)'; end if;
    update public.event_vip_orders
       set status_before_dismiss = status, reason_before_dismiss = review_reason, status = 'dismissed',
           review_reason = 'Checkout closed: ' || btrim(p_reason), updated_at = now(), updated_by = auth.uid()
     where id = o.id;
    perform public.write_audit_ex('event_vip_orders', o.id, 'event_vip_checkout_closed',
      jsonb_build_object('status', o.status, 'expires_at', o.expires_at),
      jsonb_build_object('order_id', o.order_id, 'status', 'dismissed', 'review_reason', 'Checkout closed: ' || btrim(p_reason),
                         'people', o.quantity, 'open', o.expires_at > now()),
      'events', btrim(p_reason), (select s.store_id from public.event_web_settings s where s.event_id = o.event_id));
    return jsonb_build_object('ok', true, 'checkout_closed', true);
  end if;
  if o.status = 'dismissed' and o.status_before_dismiss = 'pending' then
    if coalesce(p_dismiss, true) then raise exception 'This checkout is already closed.'; end if;
    raise exception 'A closed checkout is not reopened: the person can start a new one on the website.';
  end if;
  if o.provider = 'hitpay' and not o.is_test then
$p05$,
$p06$    if btrim(p_reason) ilike 'Refunded outside the app:%' then raise exception 'Use Close as refunded for a refund'; end if;
    if btrim(p_reason) ilike 'Checkout closed:%' then raise exception 'Give the reason in your own words'; end if;
    update public.event_vip_orders
$p06$,
$p07$  v_unit integer; v_ids uuid[]; t text; i integer := 0; v_pid uuid; v_reasons text[] := '{}'; v_dry jsonb; x jsonb;
  v_missing integer; v_new boolean := false; v_closed text;
begin
$p07$,
$p08$  end if;
  -- 444 (the owner, 21 Oct 2026: "Staff can close it"): a checkout staff
  -- closed before HitPay reported its payment (event_registration_close or
  -- Website orders: dismissed from pending, "Checkout closed: ..."). Money was
  -- taken, so it is kept for a Manager (needs review: refund it in HitPay, or
  -- create its invoices by hand), never invoiced by itself.
  v_closed := case when o.status = 'dismissed' and o.status_before_dismiss = 'pending'
                   then coalesce(o.review_reason, 'Checkout closed') end;
  if not found then
$p08$,
$p09$         paid_on = ((v->>'paid_at')::timestamptz at time zone 'Asia/Singapore')::date,
         reference = v->>'payment_request_id', updated_at = now(),
         status_before_dismiss = case when v_closed is null then status_before_dismiss end,
         reason_before_dismiss = case when v_closed is null then reason_before_dismiss end
   where id = o.id
$p09$,
$p10$    update public.event_vip_orders set status = 'test', test_would = v_dry->>'would', test_note = v_dry->>'note' where id = o.id;
    -- 444: as a live key would: kept for a Manager (staff's close reason gives way to the note).
    if v_closed is not null then
      update public.event_vip_orders set test_would = 'needs_review', review_reason = null,
             test_note = 'A live key would have kept this for a Manager: the checkout was closed before HitPay reported this '
                         || 'payment (refund it in HitPay, or create its invoices by hand).'
       where id = o.id;
    end if;
  elsif s.mode = 'off' or e.deleted_at is not null then
$p10$,
$p11$  else
    if v_closed is not null then
      v_reasons := v_reasons || ('The checkout was closed before HitPay reported this payment: refund it in HitPay, or create '
                                 || 'its invoices by hand if they should still have VIP')::text; end if;
    if v_new and v_missing > 0 then
$p11$,
$p12$                                  where op.person_id = p.id and o.status in ('recorded', 'needs_review') order by o.created_at desc limit 1),
                 -- 444 (the owner, 21 Oct 2026): an online payment started and not paid: a HitPay
                 -- checkout still open that HitPay has reported no payment for (until expires_at; people: how
                 -- many it is for, all of whom it closes for)
                 'vip_checkout', (select jsonb_build_object('order_id', o.order_id,
                                           'opened_at', coalesce(o.checkout_opened_at, o.created_at), 'expires_at', o.expires_at,
                                           'people', o.quantity)
                                    from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
                                   where op.person_id = p.id and o.status = 'pending' and o.provider = 'hitpay' and o.expires_at > now()
                                     and o.hitpay_payment_id is null and o.hitpay_payment_request_id is null and o.paid_at is null
                                     and o.amount_paid_cents is null
                                   order by o.expires_at desc limit 1),
                 'hold', case when p.match = 'held' then jsonb_build_object('reason', p.hold_reason, 'held_at', p.created_at) end,
$p12$,
$p13$                                       where op.person_id = p.id and o.status in ('recorded', 'needs_review')),
               -- 444 (the owner, 21 Oct 2026): an online payment started and not paid (a HitPay checkout
               -- still open that HitPay has reported no payment for): it does not stop them being closed
               -- (it closes with them, for everyone on it: people)
               'vip_checkout', (select jsonb_build_object('order_id', o.order_id,
                                         'opened_at', coalesce(o.checkout_opened_at, o.created_at), 'expires_at', o.expires_at,
                                         'people', o.quantity)
                                  from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
                                 where op.person_id = p.id and o.status = 'pending' and o.provider = 'hitpay' and o.expires_at > now()
                                   and o.hitpay_payment_id is null and o.hitpay_payment_request_id is null and o.paid_at is null
                                   and o.amount_paid_cents is null
                                 order by o.expires_at desc limit 1),
               'candidates', coalesce((
$p13$];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; k int; i int;
  v_texts text[] := array[null, null, null, null]::text[];
  v_acls text[] := array[null, null, null, null]::text[];
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_admin uuid; t_store uuid; t_event uuid; t_opt uuid; t_live text; t_hash text;
  t_hold uuid; t_ans jsonb; t_a uuid; t_b uuid; t_ta text; t_tb text; t_oa text; t_ob text; t_x jsonb;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 21 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is installed unless all pass ─────────────────────
  -- What it relies on and does not change: as production had it on 21 Oct 2026 (after 441).
  for r in select * from (values
      ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
      ('event_can_run(uuid)', 'dac12d0086533bb528e847eb828809df'),
      ('user_has_store_access(uuid)', '708992afaa6c3951f6329239b742987c'),
      ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
      ('event_web_call(text,uuid,text,jsonb)', 'e114ba39de4923cc52ed426e27d9bfde'),
      ('event_web_vip_checkout(uuid,jsonb)', '3b94aad78b7213e1af9261f326398153'),
      ('event_web_person_vip_state(uuid)', 'fc0a3c9ce094fe72e69cff7f420837b6'),
      ('event_web_person_view(uuid)', 'e4cf4ae412699afb1f3fa1011cbe0165'),
      ('event_vip_person_problems(uuid)', 'dc4b811edcaaa4710a8a617e3f53b625'),
      ('event_vip_dry_run(uuid)', '85d165123d4a2149396308222a44c5bf'),
      ('event_vip_make_invoices(uuid,boolean)', '026c6f301e6040d9954757ba559839ba'),
      ('event_web_order_answer(uuid)', '8489cc479d277bdaa702dacba4b152c4'),
      ('event_vip_order_close_refunded(uuid,text,boolean)', 'e3c7156008dd05b2930f4781163fe286'),
      ('event_vip_orders_list(uuid)', 'f3b2511da3a5baba6e44d507270925a9')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '444: public.% is missing or not the version this was tested against (production, 21 Oct 2026). Re-read it and re-test before applying.', r.fn;
    end if;
  end loop;

  -- The columns 444 reads and writes, as read on 21 Oct 2026.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values
      ('public.event_vip_orders', 'id uuid'), ('public.event_vip_orders', 'event_id uuid'), ('public.event_vip_orders', 'order_id text'),
      ('public.event_vip_orders', 'provider text'), ('public.event_vip_orders', 'status text'), ('public.event_vip_orders', 'is_test boolean'),
      ('public.event_vip_orders', 'quantity integer'), ('public.event_vip_orders', 'amount_paid_cents integer'),
      ('public.event_vip_orders', 'checkout_opened_at timestamp with time zone'), ('public.event_vip_orders', 'expires_at timestamp with time zone'),
      ('public.event_vip_orders', 'hitpay_payment_request_id text'), ('public.event_vip_orders', 'hitpay_payment_id text'),
      ('public.event_vip_orders', 'paid_at timestamp with time zone'), ('public.event_vip_orders', 'review_reason text'),
      ('public.event_vip_orders', 'status_before_dismiss text'), ('public.event_vip_orders', 'reason_before_dismiss text'),
      ('public.event_vip_orders', 'test_would text'), ('public.event_vip_orders', 'test_note text'),
      ('public.event_vip_orders', 'created_at timestamp with time zone'), ('public.event_vip_orders', 'updated_at timestamp with time zone'),
      ('public.event_vip_orders', 'updated_by uuid'),
      ('public.event_vip_order_people', 'order_ref uuid'), ('public.event_vip_order_people', 'person_id uuid'),
      ('public.event_registration_people', 'match text'), ('public.event_registration_people', 'free_guest_id uuid'),
      ('public.event_registration_people', 'full_name text')) x(t, c)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass(x.t) and a.attnum > 0 and not a.attisdropped
                        and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.c);
  if v is not null then
    raise exception '444: these columns are missing or not as read on 21 Oct 2026 (is 436 applied?): %', v; end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.event_vip_orders'::regclass and c.conname = 'event_vip_orders_status_check')
     is distinct from 'CHECK ((status = ANY (ARRAY[''pending''::text, ''recorded''::text, ''invoiced''::text, ''needs_review''::text, ''refused''::text, ''dismissed''::text, ''test''::text])))' then
    raise exception '444: event_vip_orders'' statuses are not as read on 21 Oct 2026'; end if;

  -- The four: BEFORE (production's, 21 Oct 2026) patched, each anchor once; or AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    d := pg_get_functiondef(('public.' || c_sigs[k])::regprocedure);
    v_acls[k] := (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure);
    if md5(d) = c_after[k] then
      raise notice '444: public.% is already this version; left alone', c_sigs[k];
    elsif md5(d) <> c_before[k] then
      raise exception '444: public.% is not the version in production on 21 Oct 2026 (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d);
    else
      for i in 1 .. cardinality(c_fn) loop
        continue when c_fn[i] <> k;
        n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
        if n <> 1 then raise exception '444: anchor % of public.% was found % times, not once', i, c_sigs[k], n; end if;
        d := replace(d, c_anchor[i], c_patch[i]);
      end loop;
      if md5(d) <> c_after[k] then
        raise exception '444: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
      v_texts[k] := d;
    end if;
  end loop;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  for k in 1 .. cardinality(c_sigs) loop
    if v_texts[k] is not null then execute v_texts[k]; end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(('public.' || c_sigs[k])::regprocedure)) <> c_after[k] then
      raise exception '444: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_sigs[k], 'execute') is distinct from c_page[k]
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '444: the grants of public.% changed', c_sigs[k]; end if;
    if c_page[k] and pg_get_functiondef(('public.' || c_sigs[k])::regprocedure) !~ E'\nbegin\n  perform public\\.require_active_staff\\(' then
      raise exception '444: public.% does not check the caller first', c_sigs[k]; end if;
  end loop;

  -- ── 4. Behaviour, in a block that is always undone ──────────────────────
  -- Made-up records only ("444 check", @example.invalid, fictional phones);
  -- it ends by raising P0444, which undoes all it wrote.
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_sfx := upper(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(7000, 7999) g
             where not exists (select 1 from public.customers c
                                where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(g::text, 4, '0'))
             limit 3) y;
    insert into auth.users (id, email) values (gen_random_uuid(), '444-check-' || lower(t_sfx) || '@example.invalid')
      returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '444 check', u.email, 'owner', true from auth.users u where u.id = t_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '444-check-admin-' || lower(t_sfx) || '@example.invalid')
      returning id into t_admin;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '444 check admin', u.email, 'admin', true from auth.users u where u.id = t_admin;
    insert into public.stores (name, code, country_code) values ('444 check ' || t_sfx, '444-' || t_sfx, 'SG') returning id into t_store;
    insert into public.events (name, daily_start, daily_end, is_active) values ('444 check ' || t_sfx, '09:00', '19:00', true)
      returning id into t_event;
    insert into public.event_days (event_id, day) values (t_event, public.sg_today() + 30);
    insert into public.event_stores (event_id, store_id) values (t_event, t_store);
    insert into public.event_ticket_options (event_id, name, days_count, price, is_active) values (t_event, 'VIP', 1, 72, true)
      returning id into t_opt;
    insert into public.event_web_settings (event_id, code, mode, store_id, acting_profile_id, vip_option_id)
    values (t_event, 'CHECK444-' || t_sfx, 'live', t_store, t_owner, t_opt);
    t_live := 'evk_live_' || rpad(t_sfx, 43, 'L');
    t_hash := encode(extensions.digest(t_live, 'sha256'), 'hex');
    insert into public.event_web_keys (event_id, kind, key_hash, key_hint, created_by)
    values (t_event, 'live', t_hash, '444 check', t_owner);
    -- One form: A on a customer's phone under another name (held, To match), B on a new phone (a new customer).
    insert into public.customers (full_name, phone) values ('Check Holder', t_phones[1]) returning id into t_hold;
    t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK444-' || t_sfx, 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || t_sfx, 'submitted_at', now(),
        'referral_code', null, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Other', 'last_name', 'Person', 'phone', t_phones[1],
                             'email', 'other-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false),
          jsonb_build_object('position', 2, 'first_name', 'Second', 'last_name', 'Person', 'phone', t_phones[2],
                             'email', 'second-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false)))));
    t_a := (t_ans->'people'->0->>'person_id')::uuid; t_ta := t_ans->'people'->0->>'upgrade_token';
    t_b := (t_ans->'people'->1->>'person_id')::uuid; t_tb := t_ans->'people'->1->>'upgrade_token';
    t_oa := 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || substr(md5(t_sfx || 'a'), 1, 8);
    t_ob := 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || substr(md5(t_sfx || 'b'), 1, 8);
    t_oa := upper(t_oa); t_ob := upper(t_ob);
    -- Each opens a HitPay checkout and goes back without paying.
    foreach v in array array['a', 'b'] loop
      t_x := public.event_web_call(t_hash, gen_random_uuid(), 'vip_checkout', jsonb_build_object('type', 'vip_checkout',
        'event', 'CHECK444-' || t_sfx, 'order', jsonb_build_object('order_id', case v when 'a' then t_oa else t_ob end,
          'upgrade_tokens', jsonb_build_array(case v when 'a' then t_ta else t_tb end),
          'payer', jsonb_build_object('name', 'Check Payer', 'email', 'payer-' || lower(t_sfx) || '@example.invalid', 'phone', null),
          'livemode', true, 'checkout_opened_at', now() - interval '3 minutes')));
      if t_x->>'status' is distinct from 'ok' then raise exception '444: the self-test''s checkout was not opened: %', t_x; end if;
    end loop;
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    t_x := public.event_web_guest_extras(t_event);
    if (select p.match from public.event_registration_people p where p.id = t_a) is distinct from 'held'
       or public.event_web_person_vip_state(t_a) is distinct from 'pending'
       or (select h->'vip_checkout'->>'order_id' from jsonb_array_elements(t_x->'holds') h where (h->>'person_id')::uuid = t_a)
          is distinct from t_oa
       or (select g->'vip_checkout'->>'order_id' from jsonb_array_elements(t_x->'guests') g where (g->>'person_id')::uuid = t_b)
          is distinct from t_ob then
      raise exception '444: the self-test''s open checkouts are not shown as started and not paid: %', t_x->'holds'; end if;
    -- An Admin cannot close B's checkout (the owner, 22 Oct 2026: an Owner or Manager only).
    perform set_config('request.jwt.claim.sub', t_admin::text, true);
    begin
      perform public.event_vip_order_dismiss((select o.id from public.event_vip_orders o where o.order_id = t_ob), '444 check', true);
      raise exception '444: the self-test''s Admin closed an unpaid checkout';
    exception when insufficient_privilege then
      if sqlerrm <> 'Only an Owner or Manager can close an unpaid checkout.' then raise; end if;
    end;
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    -- The Owner closes A's registration (its checkout closes with it) and B's checkout on Website orders.
    t_x := public.event_registration_close(t_a, '444 check');
    perform public.event_vip_order_dismiss((select o.id from public.event_vip_orders o where o.order_id = t_ob), '444 check', true);
    if (select (o.status, o.status_before_dismiss, o.review_reason) is distinct from ('dismissed'::text, 'pending'::text, 'Checkout closed: 444 check'::text)
          from public.event_vip_orders o where o.order_id = t_oa)
       or (select (o.status, o.review_reason) is distinct from ('dismissed'::text, 'Checkout closed: 444 check'::text)
             from public.event_vip_orders o where o.order_id = t_ob)
       or (select p.match from public.event_registration_people p where p.id = t_a) is distinct from 'closed'
       or t_x->'checkouts_closed'->0->>'order_id' is distinct from t_oa
       or public.event_web_person_vip_state(t_b) is distinct from 'none'
       or (select count(*) from public.audit_logs l where l.action = 'event_vip_checkout_closed'
             and l.record_id in (select o.id from public.event_vip_orders o where o.order_id in (t_oa, t_ob))) <> 2 then
      raise exception '444: the self-test''s closed checkouts are not as tested: %', t_x; end if;
    begin
      perform public.event_vip_order_dismiss((select o.id from public.event_vip_orders o where o.order_id = t_ob), null, false);
      raise exception '444: the self-test''s closed checkout was reopened';
    exception when raise_exception then
      if sqlerrm not like 'A closed checkout is not reopened%' then raise; end if;
    end;
    -- HitPay reports a payment for each anyway: kept for a Manager, nothing invoiced.
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    foreach v in array array['a', 'b'] loop
      t_x := public.event_web_call(t_hash, gen_random_uuid(), 'vip_paid', jsonb_build_object('type', 'vip_paid',
        'event', 'CHECK444-' || t_sfx, 'payment', jsonb_build_object('order_id', case v when 'a' then t_oa else t_ob end,
          'provider', 'hitpay', 'payment_request_id', gen_random_uuid(), 'payment_id', gen_random_uuid(),
          'amount_cents', 7200, 'currency', 'SGD', 'livemode', true, 'paid_at', now() - interval '1 minute',
          'upgrade_tokens', jsonb_build_array(case v when 'a' then t_ta else t_tb end),
          'payer', jsonb_build_object('name', 'Check Payer', 'email', 'payer-' || lower(t_sfx) || '@example.invalid', 'phone', null))));
      if t_x->>'status' is distinct from 'needs_review'
         or t_x->>'review_reason' not like 'The checkout was closed before HitPay reported this payment%' then
        raise exception '444: the self-test''s late payment is not kept for a Manager: %', t_x; end if;
    end loop;
    if exists (select 1 from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
                where o.order_id in (t_oa, t_ob) and op.invoice_id is not null)
       or exists (select 1 from public.event_vip_orders o where o.order_id in (t_oa, t_ob)
                     and (o.status <> 'needs_review' or o.status_before_dismiss is not null)) then
      raise exception '444: the self-test''s late payments were invoiced, or not kept for a Manager'; end if;
    raise exception using errcode = 'P0444', message = '444: self-test done, undone';
  exception when sqlstate 'P0444' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
