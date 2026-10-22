-- 450_event_vip_taken_off_and_hold_close_waits.sql
--
-- SOMEONE STAFF TOOK OFF THE GUEST LIST BUYS NO VIP UNTIL PUT BACK, AND A
-- SIGNED-UP-AGAIN HOLD IS NOT CLOSED WHILE THEIR VIP PAYMENT WAITS
-- (the owner's answer, 22 Oct 2026: "Small follow-up after 449")
--
-- WHAT WAS WRONG / WHY
--
--   Two loose ends 449 left (its NOT COVERED), read on 22 Oct 2026:
--   (a) 436's person_cancelled check in event_vip_person_problems reads
--       event_web_person_view's reason, which the order being checked masks:
--       the website's checkout inserts its own pending order before it checks
--       (event_web_vip_checkout), and a transfer its recorded order, so there
--       the person's VIP state reads 'pending' and the reason
--       'payment_waiting', not 'cancelled'. A hand-made VIP checkout for
--       someone staff took off the list (the website offers them none) was
--       accepted, and HitPay's payment for it invoiced
--       (event_vip_make_invoices stops only a closed registration), making
--       them VIP while off the list (so too a checkout opened before staff
--       took them off and paid after); a transfer was recorded for a Manager
--       to confirm as anyone's. 449 refused it only while their
--       signed-up-again hold is open, not for someone who never signed up
--       again, nor once their hold was closed.
--   (b) 449's Close of a signed-up-again hold did not look at their VIP
--       payments: it closed while a payment of theirs waited on Website orders
--       (paid while held: needs review), unlike 444's Close of a registration,
--       which refuses ("A VIP payment for % is waiting: deal with it on
--       Website orders first.").
--
-- THE RULES (binding)
--
--   The owner's answer, 22 Oct 2026 (chat), to (a) and (b) as put above:
--   "Small follow-up after 449". As put to the owner and answered:
--   * (a) A VIP checkout is refused for anyone whose free guest record staff
--     took off the list (cancelled, its reason not "Upgraded to VIP...") and
--     who has no VIP record standing (no registered VIP guest): the code
--     449 uses, person_cancelled (the contract's "not registered any more").
--     A payment or transfer that comes anyway for such a person waits for a
--     Manager (needs review, no invoice), as 449 does for a held person.
--   * (b) A signed-up-again hold is not closed while a VIP payment of theirs
--     waits (needs review or recorded, or a HitPay payment not invoiced yet),
--     with 444's words: "A VIP payment for <name> is waiting: deal with it on
--     Website orders first."
--   * Nothing else changes.
--   Every earlier answer in 436's, 439's, 441's, 444's and 449's THE RULES
--   stands as written there.
--   How it reads (this file, 22 Oct 2026):
--   * Taken off the list by staff: their free guest record cancelled by the
--     Guests tab's Cancel (whatever reason) or by a Close of their
--     registration (444: "Closed: <reason>"; one waiting to be matched is on
--     the list too, so its Close is the same). "Upgraded to VIP..." is the
--     app's own, when their VIP is invoiced (their VIP record stands). A test
--     key's person has no guest record: as before.
--   * Whether they signed up again or not, and whatever their VIP state reads
--     while the order is checked: read from their records.
--   * The reason a Manager reads on Website orders is 436's own for this
--     check: "Person N on this order is no longer registered (cancelled or
--     closed)" (449's, "... signed up again after staff took them off the
--     list: put them back on the list first (Guests, To match)", while their
--     hold is open). The website shows its person_cancelled words ("Someone
--     you chose is no longer registered. Please contact us."); it already
--     offers them no VIP (their VIP link reads can_upgrade false, cancelled).
--   * A payment for a checkout they opened while on the list, paid after
--     staff took them off, is one that "comes anyway": it waits too.
--   * Put back (the Guests tab's Restore, or "Put back on the list") lifts it.
--   * "Waits": recorded or needs review, or a HitPay order HitPay reported a
--     payment for that is not dealt with yet (still pending: paid but not
--     yet recorded, whatever its expiry). An online checkout not paid does
--     not stop the Close: it closes with the hold, as 449 (and 444) close it.
--
-- WHAT THIS DOES
--
--   1. event_vip_person_problems (the website's checkout, HitPay's payment
--      and a transfer use it): 436's last branch (person_cancelled, "Person N
--      on this order is no longer registered (cancelled or closed)") also
--      takes anyone, not a test person, whose free guest record is cancelled
--      with a reason not "Upgraded to VIP..." and whose VIP guest record (if
--      any) is not registered, read from their records. The branches before
--      it are as they were (already VIP, a VIP invoice waiting, another
--      payment waiting, 449's open hold with its own text). So
--      event_web_vip_checkout refuses (person_cancelled, nothing kept: it
--      deletes the order it made, as 436), event_web_vip_paid and
--      event_web_vip_transfer keep the payment for a Manager (needs review,
--      that reason; nothing invoiced).
--   2. event_registration_close (page; Owner or Manager, as 436/444/449): for
--      an open signed-up-again hold (449's branch), before anything changes:
--      a VIP payment of theirs that waits (recorded or needs review, or a
--      pending order that is not an online checkout without a payment)
--      refuses it with 444's words, which the Event page already explains.
--      With none waiting: as 449 (their unpaid HitPay checkouts close with
--      it). A Close of anyone else: as before.
--
-- NOT CHANGED
--
--   Every other function, table, column, constraint and grant.
--   event_web_vip_checkout, event_web_vip_paid and event_web_vip_transfer
--   (they read the problems), event_web_person_view and
--   event_web_person_vip_state (the website still reads can_upgrade false,
--   reason 'cancelled', for such a person), event_vip_make_invoices,
--   event_vip_order_invoice (a Manager may still invoice a waiting payment by
--   hand), event_set_guest_cancelled (Put back is not refused while a
--   payment waits), event_web_register, event_web_guest_extras, the contract,
--   the website (1322b22) and the Event page.
--   449's own file refuses to run again after 450 (it pins
--   event_vip_person_problems and event_registration_close at its AFTER), as
--   it is live and not run again (the earlier ones already refuse after
--   449). The 444 and 449 suites accept 450's AFTER md5s where it is
--   applied.
--
-- NOT COVERED (to tell the owner)
--
--   * Nothing already in production is repaired. Read on 22 Oct 2026 (14:15
--     Singapore time): no one there holds a signed-up-again hold or has a VIP
--     payment waiting while taken off; one person is taken off without a VIP
--     record (their free guest record cancelled by staff as "Test Data" at
--     14:11 that day, after 449), with four live HitPay checkouts, none paid,
--     the last one open until 14:30. 450 refuses them a new checkout; a
--     payment HitPay still reports for one of those checkouts waits for a
--     Manager (needs review), not invoiced.
--   * A Manager can still invoice a payment that waits for someone taken off
--     (Website orders, Create invoices; event_vip_order_invoice reads no
--     problems): they become VIP while their free record stays off (as 449's
--     NOT COVERED for a held person).
--   * A payment that came while they were still on the list and waited only
--     to be matched (Guests, To match: "It is invoiced once they are"), when
--     staff then took them off (the Guests tab's Cancel; Close is refused
--     while it waits), is still invoiced by itself when any staff member
--     attaches them to a customer or makes them one (event_registration_attach /
--     event_registration_create_customer -> event_vip_retry_after_match ->
--     event_vip_make_invoices, which reads no problems): they become VIP while
--     their free record stays off. As before 450 (449 the same); none in
--     production on 22 Oct 2026. Closing it needs a later migration:
--     event_vip_make_invoices, when not reviewed, keeping such a payment
--     (free guest cancelled, not "Upgraded to VIP...", no registered VIP
--     guest) for a Manager with 436's reason.
--   * Put back is not refused while a payment of theirs waits: once they are
--     back, the payment stays on Website orders for a Manager (as 449).
--   * A HitPay payment whose checkout the app never heard of (a new order,
--     made by the payment itself) that commits while a Close of their hold
--     runs is not seen by that Close; it then waits (needs review: they are
--     off the list). As 444's Close of a registration.
--   * The Event page's explanation of 444's words says "the registration
--     cannot be closed yet ... then close the registration" for a hold too.
--
-- DEPLOY ORDER (each step with the owner's go-ahead)
--
--   After 449 (20261022052511) and another session's 446 (20261022060748)
--   and 447 (20261022060812), which change no function this file changes or
--   relies on: production 9d2e2fdd5c26b214e5d1a0f867273aff, 1370 functions,
--   22 Oct 2026, head 20261022060812. A migration applied after that must
--   not change any function this file changes or relies on (below), or this
--   file refuses to run: re-test then.
--   1. Nothing to deploy first: the website (1322b22) already shows a
--      person_cancelled refusal ("Someone you chose is no longer registered.
--      Please contact us.") and offers such a person no VIP; the Event page
--      shows 444's words with its explanation.
--   2. Dry run on a copy of production as it is then: apply this file twice.
--      The first run ends with the fingerprint below; the second says
--      "already this version; left alone" for each function and changes
--      nothing.
--   3. Apply this file (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself (every AFTER md5, the grants, its
--      self-test, which leaves no row).
--
-- SAFETY
--
--   One DO block after "set lock_timeout", atomic whatever runs it; every
--   check before anything is changed:
--   * every function it relies on and does not change is as production had
--     it on 22 Oct 2026 (below); the columns, statuses and checks it reads
--     are.
--   * each of the two it changes is production's version (patched, each
--     anchor found once, the text built has the tested md5) or already this
--     file's AFTER (left alone); anything else is refused.
--   * afterwards every md5 is the AFTER one, the two keep their grants (ACLs
--     unchanged: the close signed-in staff's, the problems the service
--     role's alone), the close still checks the caller first
--     (require_active_staff).
--   * a self-test, in a block that is always undone (it ends by raising
--     P0450, so it leaves no row): a made-up Owner, store and two-day event
--     with a VIP ticket and a live key. A and B register; staff take both off
--     ("Cannot come"). A, who never signed up again: a VIP checkout is
--     refused person_cancelled and nothing is kept; a PayNow transfer for A
--     waits (needs review, 436's reason), nothing invoiced. B signs up again
--     (held) and sends a transfer (needs review, 449's reason): Close of B's
--     hold is refused with 444's words and changes nothing; the transfer
--     dismissed on Website orders, Close leaves B off; a checkout for B is
--     then refused person_cancelled. A's transfer dismissed and A put back: a
--     checkout for A is accepted.
--
-- BEFORE (production, 22 Oct 2026, after 449, 446 and 447; pg_get_functiondef with search_path public):
--   changed
--   event_vip_person_problems(uuid)                                ec2fbe26fa116505cdd56910d17ce9ea
--   event_registration_close(uuid,text)                            60f3dde4dc9f7d8cc33f5517e54eeed8  (page)
--   relied on, not changed
--   require_active_staff(text[])                                   877b3aa74cea559881979bb161c450e2
--   event_can_run(uuid)                                            dac12d0086533bb528e847eb828809df
--   user_has_store_access(uuid)                                    708992afaa6c3951f6329239b742987c
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   event_web_call(text,uuid,text,jsonb)                           e114ba39de4923cc52ed426e27d9bfde
--   event_web_open_state(uuid)                                     ef87a22efbb62f69759838db2dfc0d0c
--   event_web_person_view(uuid)                                    e4cf4ae412699afb1f3fa1011cbe0165
--   event_web_person_vip_state(uuid)                               fc0a3c9ce094fe72e69cff7f420837b6
--   event_web_vip_checkout(uuid,jsonb)                             3b94aad78b7213e1af9261f326398153
--   event_web_vip_paid(uuid,jsonb)                                 1e1e48047b36af39495ef767a37237c2
--   event_web_vip_transfer(uuid,jsonb)                             ec0aaa21b67316d71786e1f30456c183
--   event_web_register(uuid,jsonb)                                 3aad1ad2a8a91732d330b2ef149bf969
--   event_set_guest_cancelled(uuid,boolean,text)                   af22a3fad6232dad1a748b9cc1ddb2ae
--   event_vip_order_dismiss(uuid,text,boolean)                     d1b16a09f2376591688feb42585c8146
--   public function fingerprint (production after 449, 446 and 447)  9d2e2fdd5c26b214e5d1a0f867273aff (1370 functions)
--     (after 449 alone, before 446 and 447: 6e368a7e6c22d186edc59798d1d31210)
-- AFTER (for later guards):
--   event_vip_person_problems(uuid)                                add06a8aba39e4259bcf68bab4092027
--   event_registration_close(uuid,text)                            39436dab86aa00d5884fceab88cb2d09  (page)
--   public function fingerprint (production after 449, 446, 447 + 450) 46683a933775c18ee02261dafd3ffe47 (1370 functions)
--     (on a copy with 449 alone + 450: 5890d02a3277d55bcf6fb84acb087acd)
--
-- Test: scripts/event-website/tests/event-website-450.sql (begin ... rollback; it applies this
-- file twice, or -v skip_install=1 where it is installed); 436's event-website.sql and
-- event-website-separate-tx.sql, and the 439, 441, 444 and 449 suites (each -v skip_install=1; the 444
-- and 449 suites accept 450's AFTER md5s where it is applied) pass with it, and so do the
-- function-grants, staff-only-functions and client-RPC sweeps.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The two functions it changes: BEFORE (production's, 22 Oct 2026, after 449) and AFTER ──
  c_sigs constant text[] := array['event_vip_person_problems(uuid)', 'event_registration_close(uuid,text)'];
  c_page constant boolean[] := array[false, true];
  c_before constant text[] := array['ec2fbe26fa116505cdd56910d17ce9ea', '60f3dde4dc9f7d8cc33f5517e54eeed8'];
  c_after constant text[] := array['add06a8aba39e4259bcf68bab4092027', '39436dab86aa00d5884fceab88cb2d09'];
  -- each anchor (found once in its function's BEFORE text) and its patch, in order
  c_fn constant int[] := array[1, 2];
  c_anchor constant text[] := array[
$a01$    elsif v_view->>'reason' = 'cancelled' then
$a01$,
$a02$    if v_again then
      update public.event_registration_people
$a02$];
  c_patch constant text[] := array[
$p01$    -- 450 (the owner, 22 Oct 2026: "Small follow-up after 449"): anyone staff
    -- took off the list (their free guest record cancelled, not "Upgraded to
    -- VIP...") buys no VIP while no VIP record of theirs stands, whether or not
    -- they signed up again (or their hold was closed): a checkout is refused, a
    -- payment or transfer that comes anyway waits for a Manager. Read from
    -- their records, not their VIP state: the order checked here is theirs too
    -- (a checkout's own pending order, a transfer's recorded one), so the
    -- view's reason reads payment_waiting while it runs.
    elsif v_view->>'reason' = 'cancelled'
          or (not r.is_test
              and exists (select 1 from public.event_guests fg
                           where fg.id = r.free_guest_id and fg.status = 'cancelled'
                             and coalesce(fg.cancelled_reason, '') not like 'Upgraded to VIP%')
              and not exists (select 1 from public.event_guests vg
                               where vg.id = r.vip_guest_id and vg.status = 'registered')) then
$p01$,
$p02$    if v_again then
      -- 450 (the owner, 22 Oct 2026: "Small follow-up after 449"): as 444's
      -- Close of a registration (below), not while a VIP payment of theirs
      -- waits on Website orders (money taken or a transfer sent: needs review
      -- or recorded, or a HitPay payment not dealt with yet, whatever its
      -- expiry). Only an online checkout not paid does not stop it: it closes
      -- with the hold (below).
      if exists (select 1 from public.event_vip_order_people op
                   join public.event_vip_orders o on o.id = op.order_ref
                  where op.person_id = p.id
                    and (o.status in ('recorded', 'needs_review')
                         or (o.status = 'pending'
                             and not (o.provider = 'hitpay' and o.hitpay_payment_id is null and o.hitpay_payment_request_id is null
                                      and o.paid_at is null and o.amount_paid_cents is null)))) then
        raise exception 'A VIP payment for % is waiting: deal with it on Website orders first.', p.full_name; end if;
      update public.event_registration_people
$p02$];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; k int; i int;
  v_texts text[] := array[null, null]::text[];
  v_acls text[] := array[null, null]::text[];
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_event uuid; t_opt uuid; t_live text; t_hash text;
  t_d1 date; t_d2 date; t_ans jsonb; t_a uuid; t_b uuid; t_ga uuid; t_gb uuid; t_ta text; t_tb text; t_x jsonb;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 22 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is changed unless all pass ─────────────────────────
  -- What it relies on and does not change: as production had it on 22 Oct 2026 (after 449).
  for r in select * from (values
      ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
      ('event_can_run(uuid)', 'dac12d0086533bb528e847eb828809df'),
      ('user_has_store_access(uuid)', '708992afaa6c3951f6329239b742987c'),
      ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
      ('event_web_call(text,uuid,text,jsonb)', 'e114ba39de4923cc52ed426e27d9bfde'),
      ('event_web_open_state(uuid)', 'ef87a22efbb62f69759838db2dfc0d0c'),
      ('event_web_person_view(uuid)', 'e4cf4ae412699afb1f3fa1011cbe0165'),
      ('event_web_person_vip_state(uuid)', 'fc0a3c9ce094fe72e69cff7f420837b6'),
      ('event_web_vip_checkout(uuid,jsonb)', '3b94aad78b7213e1af9261f326398153'),
      ('event_web_vip_paid(uuid,jsonb)', '1e1e48047b36af39495ef767a37237c2'),
      ('event_web_vip_transfer(uuid,jsonb)', 'ec0aaa21b67316d71786e1f30456c183'),
      ('event_web_register(uuid,jsonb)', '3aad1ad2a8a91732d330b2ef149bf969'),
      ('event_set_guest_cancelled(uuid,boolean,text)', 'af22a3fad6232dad1a748b9cc1ddb2ae'),
      ('event_vip_order_dismiss(uuid,text,boolean)', 'd1b16a09f2376591688feb42585c8146')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '450: public.% is missing or not the version this was tested against (production, 22 Oct 2026). Re-read it and re-test before applying.', r.fn;
    end if;
  end loop;

  -- The columns 450 reads, as read on 22 Oct 2026.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values
      ('public.event_registration_people', 'id uuid'), ('public.event_registration_people', 'is_test boolean'),
      ('public.event_registration_people', 'match text'), ('public.event_registration_people', 'full_name text'),
      ('public.event_registration_people', 'free_guest_id uuid'), ('public.event_registration_people', 'vip_guest_id uuid'),
      ('public.event_registration_people', 'signed_up_again_at timestamp with time zone'),
      ('public.event_registration_people', 'signed_up_again_resolved_at timestamp with time zone'),
      ('public.event_guests', 'id uuid'), ('public.event_guests', 'status text'), ('public.event_guests', 'cancelled_reason text'),
      ('public.event_vip_orders', 'id uuid'), ('public.event_vip_orders', 'status text'), ('public.event_vip_orders', 'provider text'),
      ('public.event_vip_orders', 'hitpay_payment_id text'), ('public.event_vip_orders', 'hitpay_payment_request_id text'),
      ('public.event_vip_orders', 'paid_at timestamp with time zone'), ('public.event_vip_orders', 'amount_paid_cents integer'),
      ('public.event_vip_order_people', 'order_ref uuid'), ('public.event_vip_order_people', 'person_id uuid')) x(t, c)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass(x.t) and a.attnum > 0 and not a.attisdropped
                        and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.c);
  if v is not null then
    raise exception '450: these columns are missing or not as read on 22 Oct 2026 (are 436, 444 and 449 applied?): %', v; end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.event_guests'::regclass and c.conname = 'event_guests_status')
     is distinct from 'CHECK ((status = ANY (ARRAY[''registered''::text, ''cancelled''::text])))'
     or (select pg_get_constraintdef(c.oid) from pg_constraint c
          where c.conrelid = 'public.event_vip_orders'::regclass and c.conname = 'event_vip_orders_status_check')
        is distinct from 'CHECK ((status = ANY (ARRAY[''pending''::text, ''recorded''::text, ''invoiced''::text, ''needs_review''::text, ''refused''::text, ''dismissed''::text, ''test''::text])))'
     or (select pg_get_constraintdef(c.oid) from pg_constraint c
          where c.conrelid = 'public.event_vip_orders'::regclass and c.conname = 'event_vip_orders_provider_check')
        is distinct from 'CHECK ((provider = ANY (ARRAY[''hitpay''::text, ''paynow''::text, ''bank''::text])))' then
    raise exception '450: event_guests'' statuses or event_vip_orders'' statuses or providers are not as read on 22 Oct 2026'; end if;

  -- The two: BEFORE (production's, 22 Oct 2026) patched, each anchor once; or AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    d := pg_get_functiondef(('public.' || c_sigs[k])::regprocedure);
    v_acls[k] := (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure);
    if md5(d) = c_after[k] then
      raise notice '450: public.% is already this version; left alone', c_sigs[k];
    elsif md5(d) <> c_before[k] then
      raise exception '450: public.% is not the version in production on 22 Oct 2026 (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d);
    else
      for i in 1 .. cardinality(c_fn) loop
        continue when c_fn[i] <> k;
        n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
        if n <> 1 then raise exception '450: anchor % of public.% was found % times, not once', i, c_sigs[k], n; end if;
        d := replace(d, c_anchor[i], c_patch[i]);
      end loop;
      if md5(d) <> c_after[k] then
        raise exception '450: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
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
      raise exception '450: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_sigs[k], 'execute') is distinct from c_page[k]
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '450: the grants of public.% changed', c_sigs[k]; end if;
    if c_page[k] and pg_get_functiondef(('public.' || c_sigs[k])::regprocedure) !~ E'\nbegin\n  perform public\\.require_active_staff\\(' then
      raise exception '450: public.% does not check the caller first', c_sigs[k]; end if;
  end loop;

  -- ── 4. Behaviour, in a block that is always undone ──────────────────────
  -- Made-up records only ("450 check", @example.invalid, fictional phones);
  -- it ends by raising P0450, which undoes all it wrote.
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
    insert into auth.users (id, email) values (gen_random_uuid(), '450-check-' || lower(t_sfx) || '@example.invalid')
      returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '450 check', u.email, 'owner', true from auth.users u where u.id = t_owner;
    insert into public.stores (name, code, country_code) values ('450 check ' || t_sfx, '450-' || t_sfx, 'SG') returning id into t_store;
    insert into public.events (name, daily_start, daily_end, is_active) values ('450 check ' || t_sfx, '09:00', '19:00', true)
      returning id into t_event;
    insert into public.event_days (event_id, day) values (t_event, t_d1), (t_event, t_d2);
    insert into public.event_stores (event_id, store_id) values (t_event, t_store);
    insert into public.event_ticket_options (event_id, name, days_count, price, is_active) values (t_event, 'VIP', 2, 72, true)
      returning id into t_opt;
    insert into public.event_web_settings (event_id, code, mode, store_id, acting_profile_id, vip_option_id)
    values (t_event, 'CHECK450-' || t_sfx, 'live', t_store, t_owner, t_opt);
    t_live := 'evk_live_' || rpad(t_sfx, 43, 'L');
    t_hash := encode(extensions.digest(t_live, 'sha256'), 'hex');
    insert into public.event_web_keys (event_id, kind, key_hash, key_hint, created_by)
    values (t_event, 'live', t_hash, '450 check', t_owner);
    -- A and B register (Day 1), each on a phone and email nobody has: new customers on the guest list.
    foreach v in array array['a', 'b'] loop
      t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
        jsonb_build_object('type', 'register', 'event', 'CHECK450-' || t_sfx, 'registration', jsonb_build_object(
          'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || v || '0'), 1, 8)),
          'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
            jsonb_build_object('position', 1, 'first_name', case v when 'a' then 'Ada' else 'Bea' end, 'last_name', 'Offlist',
                               'phone', t_phones[case v when 'a' then 1 else 2 end],
                               'email', v || '-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(t_d1), 'vip', false)))));
      if v = 'a' then t_a := (t_ans->'people'->0->>'person_id')::uuid; t_ta := t_ans->'people'->0->>'upgrade_token';
      else t_b := (t_ans->'people'->0->>'person_id')::uuid; t_tb := t_ans->'people'->0->>'upgrade_token'; end if;
    end loop;
    select p.free_guest_id into t_ga from public.event_registration_people p where p.id = t_a;
    select p.free_guest_id into t_gb from public.event_registration_people p where p.id = t_b;
    if t_ga is null or t_gb is null then raise exception '450: the self-test''s registrations were not made: %', t_ans; end if;
    -- Staff take both off the list.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform public.event_set_guest_cancelled(t_ga, true, 'Cannot come');
    perform public.event_set_guest_cancelled(t_gb, true, 'Cannot come');
    -- (a) A never signed up again: a VIP checkout is refused (nothing kept); a transfer waits for a Manager, nothing invoiced.
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_x := public.event_web_call(t_hash, gen_random_uuid(), 'vip_checkout', jsonb_build_object('type', 'vip_checkout',
      'event', 'CHECK450-' || t_sfx, 'order', jsonb_build_object(
        'order_id', 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'co-a'), 1, 8)),
        'upgrade_tokens', jsonb_build_array(t_ta),
        'payer', jsonb_build_object('name', 'Check Payer', 'email', 'payer-' || lower(t_sfx) || '@example.invalid', 'phone', null),
        'livemode', true, 'checkout_opened_at', now() - interval '1 minute')));
    if t_x is distinct from jsonb_build_object('ok', true, 'test', false, 'status', 'refused', 'reason', 'person_cancelled',
                                               'person_ids', jsonb_build_array(t_a))
       or exists (select 1 from public.event_vip_orders o where o.event_id = t_event) then
      raise exception '450: the self-test''s VIP checkout for someone taken off was not refused: %', t_x; end if;
    foreach v in array array['a', 'b'] loop
      if v = 'b' then
        -- B signs up again (Day 2): held for staff (449).
        t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
          jsonb_build_object('type', 'register', 'event', 'CHECK450-' || t_sfx, 'registration', jsonb_build_object(
            'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'b1'), 1, 8)),
            'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
              jsonb_build_object('position', 1, 'first_name', 'Bea', 'last_name', 'Offlist', 'phone', t_phones[2],
                                 'email', 'b-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(t_d2), 'vip', false)))));
        if t_ans->'people'->0->'days' is distinct from '[]'::jsonb then
          raise exception '450: the self-test''s B was not held: %', t_ans; end if;
      end if;
      t_x := public.event_web_call(t_hash, gen_random_uuid(), 'vip_transfer', jsonb_build_object('type', 'vip_transfer',
        'event', 'CHECK450-' || t_sfx, 'order', jsonb_build_object(
          'order_id', 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'tr-' || v), 1, 8)),
          'upgrade_tokens', jsonb_build_array(case v when 'a' then t_ta else t_tb end),
          'payer', jsonb_build_object('name', 'Check Payer', 'email', 'payer-' || lower(t_sfx) || '@example.invalid', 'phone', null),
          'method', 'paynow', 'reference', 'PN-450-' || v, 'paid_on', public.sg_today(), 'amount_cents', 7200, 'submitted_at', now())));
      if t_x->>'status' is distinct from 'needs_review'
         or t_x->>'review_reason' is distinct from (case v
              when 'a' then 'Person 1 on this order is no longer registered (cancelled or closed)'
              else 'Person 1 on this order signed up again after staff took them off the list: put them back on the list first (Guests, To match)' end)
         or exists (select 1 from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
                     where o.event_id = t_event and op.invoice_id is not null) then
        raise exception '450: the self-test''s transfer for %, taken off, does not wait for a Manager: %', v, t_x; end if;
    end loop;
    -- (b) Close of B's hold while the transfer waits: refused with 444's words, nothing changed.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    begin
      perform public.event_registration_close(t_b, '450 check');
      raise exception '450: the self-test''s Close of a hold while a payment waits was not refused';
    exception when raise_exception then
      if sqlerrm <> 'A VIP payment for Bea Offlist is waiting: deal with it on Website orders first.' then raise; end if;
    end;
    if (select p.signed_up_again_resolved_at from public.event_registration_people p where p.id = t_b) is not null
       or exists (select 1 from public.audit_logs l where l.record_id = t_b and l.action = 'event_registration_signed_up_again_closed') then
      raise exception '450: the self-test''s refused Close changed B''s hold'; end if;
    -- Dealt with on Website orders (the transfer never arrived): Close now leaves B off; still off, a checkout is refused.
    perform public.event_vip_order_dismiss(o.id, '450 check: never arrived', true)
       from public.event_vip_orders o
      where o.order_id = 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'tr-b'), 1, 8));
    t_x := public.event_registration_close(t_b, '450 check');
    if t_x->>'signed_up_again' is distinct from 'closed'
       or (select p.signed_up_again_resolved_at from public.event_registration_people p where p.id = t_b) is null then
      raise exception '450: the self-test''s Close after the payment was dealt with did not close B''s hold: %', t_x; end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_x := public.event_web_call(t_hash, gen_random_uuid(), 'vip_checkout', jsonb_build_object('type', 'vip_checkout',
      'event', 'CHECK450-' || t_sfx, 'order', jsonb_build_object(
        'order_id', 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'co-b'), 1, 8)),
        'upgrade_tokens', jsonb_build_array(t_tb),
        'payer', jsonb_build_object('name', 'Check Payer', 'email', 'payer-' || lower(t_sfx) || '@example.invalid', 'phone', null),
        'livemode', true, 'checkout_opened_at', now() - interval '1 minute')));
    if t_x->>'status' is distinct from 'refused' or t_x->>'reason' is distinct from 'person_cancelled'
       or exists (select 1 from public.event_vip_orders o where o.event_id = t_event and o.status = 'pending') then
      raise exception '450: the self-test''s VIP checkout after B''s hold was closed was not refused: %', t_x; end if;
    -- A's transfer dealt with and A put back: A can buy VIP.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform public.event_vip_order_dismiss(o.id, '450 check: never arrived', true)
       from public.event_vip_orders o
      where o.order_id = 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'tr-a'), 1, 8));
    perform public.event_set_guest_cancelled(t_ga, false, '450 check');
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_x := public.event_web_call(t_hash, gen_random_uuid(), 'vip_checkout', jsonb_build_object('type', 'vip_checkout',
      'event', 'CHECK450-' || t_sfx, 'order', jsonb_build_object(
        'order_id', 'VIP-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(t_sfx || 'co-a2'), 1, 8)),
        'upgrade_tokens', jsonb_build_array(t_ta),
        'payer', jsonb_build_object('name', 'Check Payer', 'email', 'payer-' || lower(t_sfx) || '@example.invalid', 'phone', null),
        'livemode', true, 'checkout_opened_at', now() - interval '1 minute')));
    if t_x->>'status' is distinct from 'ok' then
      raise exception '450: the self-test''s VIP checkout for A put back was not accepted: %', t_x; end if;
    raise exception using errcode = 'P0450', message = '450: self-test done, undone';
  exception when sqlstate 'P0450' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
