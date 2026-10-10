-- 415_events_check_in_and_web_orders.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026, section 9: EVENTS-3, EVENTS-1,
-- EVENTS-6, EVENTS-M2, EVENTS-5, EVENTS-7, EVENTS-9, EVENTS-M1, EVENTS-8,
-- EVENTS-4)
--
--   The door check-in (EVENTS-3). The event runs on 19 and 20 Oct 2026 with
--   two door devices. event_check_in wrote the code every time, so a second
--   "Check in" from a device that had not refreshed erased the code (a
--   wristband or "CD n") typed on the first one. It returned no checker, so
--   the screen named whoever pressed the button. Undo cleared the time, the
--   checker and the code and left no record of them.
--
--   A guest whose registrar had left could not be edited (EVENTS-1):
--   event_save_guest checked the registrar on every save, even unchanged,
--   and refused a deactivated one. Choosing "Not recorded" kept the old
--   registrar (coalesce).
--
--   Cancelling and restoring a free guest (EVENTS-M2, EVENTS-6): a guest who
--   had checked in could be cancelled, and their attendance left the day's
--   "in" count and the report. Restoring did not look at the event's days or
--   capacity: a guest could come back on a day the event no longer has, and
--   every later edit of them was refused.
--
--   The event editor (EVENTS-5, EVENTS-9): a ticket on a deleted invoice
--   still held a day and an option's days covered, and the refusal said
--   "People are registered" whatever held the day. A decimal Order gave a
--   raw database error ("invalid input syntax for type integer"), and a
--   price with three decimals was rounded without a word.
--
--   A paid website order for a ticket taken off sale (EVENTS-7): the website
--   keeps selling (it never reads the app's On sale), and the invoice of a
--   paid order was refused ("... are not on sale"), so it sat in Needs review
--   and could never become an invoice, not even by hand.
--
--   Deleting an event (EVENTS-M1) did not look at its website channel: an
--   event could be deleted while the website still took payments for it.
--   And an order whose payment was refunded outside the app had no way to
--   be closed: only a staff-link registration could be dismissed.
--
--   Linking an order to an invoice made by hand (EVENTS-8):
--   web_order_can_link let a test payment (no money taken) be linked to a
--   real invoice, and a website payment refused because the channel was off
--   could never be linked (only a staff-link one could).
--
--   Which event a sale counts under (EVENTS-4): a ticket for one event,
--   sold on a day another event runs at that store, counted under the event
--   running that day (its Sales tab, the invoice list's badge, the Events
--   report), not the event the ticket is for.
--
-- THE RULES (the audit's fix plans of 9 Oct 2026, and the Owner's answers of
-- 9 Oct 2026 to its questions, marked "the Owner")
--
--   1. Check-in: a check-in never changes one already made. A second "Check
--      in" answers already_in with the time, who checked them in and the
--      code. Only "Save code" changes the code of a guest who is in (an
--      empty code clears it). Undo clears the check-in. Each change is in
--      the audit log with the check-in as it was before and after. The
--      answer names who checked the guest in.
--   2. A guest's registrar is checked only when it changes; an explicit
--      "Not recorded" clears it. A new free guest is still credited to the
--      person adding them unless another name is picked (unchanged).
--   3. A day someone attended stays (the rule event_save_guest already
--      has): a free guest who has checked in is not cancelled; the check-in
--      is undone first. A restored free guest loses the days the event no
--      longer has; with none left they stay cancelled. Restoring answers the
--      days over capacity, as adding a guest does (a full day warns, never
--      refuses).
--   4. A deleted invoice's tickets no longer hold a day or an option's days
--      covered (as event_delete already ignores them). They still hold the
--      option itself: its invoice line keeps it (a foreign key). Each
--      refusal names what holds the day or the option: how many free guests
--      are registered, and the invoices (by number at the person's stores;
--      the rest are counted). A ticket guest comes with their ticket, so
--      their invoice is named instead.
--   5. Order, capacity and days covered are whole numbers; a price is in
--      dollars and cents, and so is the early-bird percent (2 decimals).
--   6. Money already taken is honoured: an order web_order_make_invoice
--      invoices passes the On sale check of its ticket. The event's other
--      checks (deleted, ended) stay. Only web_order_make_invoice sets the
--      flag that says so, for its own order, around its own invoice; a
--      browser cannot set it (PostgREST runs public functions only, and no
--      public function sets a setting a caller names).
--   7. An event is not deleted while its website channel is not Off, or has
--      orders waiting for an invoice: recorded or in Needs review, or refused
--      because the channel was off after taking real money (rule 8 links
--      those to an invoice made by hand). The Owner agreed (9 Oct 2026): a
--      real website payment refused while the channel was Off blocks
--      deleting the event until it is linked to an invoice.
--   8. An order is linked to an invoice made by hand only when it took real
--      money (live mode): one recorded or waiting, or one refused because
--      the channel was off, from the website or the staff link alike.
--   9. The Owner (9 Oct 2026): an Owner or Manager may close an order whose
--      payment was refunded outside the app, with a reason (at least 3
--      characters), so its event can then be deleted. Any order rule 7
--      counts can be closed: recorded, in Needs review, or a real payment
--      refused while the channel was off. It is then Dismissed, its reason
--      "Refunded outside the app: <reason>"; no invoice, payment or stock is
--      touched. One closed by mistake is reopened by an Owner or Manager with
--      a reason (not while its event is deleted), and is put back as it was
--      before the close: a payment refused while the channel was off is
--      refused again (it is still only linked to an invoice made by hand, and
--      it holds its event again); any other waits in Needs review again (a
--      staff-link registration with the staff link's checks, as Restore gives
--      them). Both are audited. Admins and staff can do neither. The staff
--      link's Dismiss and Restore are unchanged, except that Restore does not
--      bring back an order closed as refunded (Reopen does), and a Dismiss
--      reason may not start "Refunded outside the app:", so a dismissed
--      registration is never taken for a closed one.
--  10. The Owner (9 Oct 2026): a ticket sale counts under the event the
--      ticket is for, not the event running that day. A sale holding no
--      ticket still counts under the event whose day and store it falls on,
--      and staff marking an invoice by hand still decides over both. An
--      invoice counts under one event, whole: as built, products on an
--      invoice holding a ticket count with the ticket (the Owner is asked
--      whether only the ticket lines should). An invoice holding tickets for
--      two events counts under the one running that day at that store, so
--      that event's own tickets count under it; otherwise under the older.
--  11. The Owner (9 Oct 2026): taking a ticket off sale in the app also
--      closes it on the seminar website; ticked back, it sells again. The
--      website asks the inventory (through the edge function web-ticket-order,
--      "tickets") which of its passes are on sale: a pass is on sale while
--      its ticket's On sale and its event's Tickets on sale are both ticked
--      and the event is not deleted. The website asks before it opens each
--      checkout; a checkout already open can still be paid for up to an hour,
--      and is invoiced (rule 6). If the website cannot ask, it keeps its own
--      closing times; an order paid meanwhile is still invoiced too.
--
-- WHAT THIS DOES
--
--   * event_check_in(uuid,date,boolean,text) is dropped and
--     event_check_in(uuid,date,boolean,text,boolean) is made: rule 1. The
--     last argument (p_save_code) defaults to false, so a page already open
--     keeps working. It starts with require_active_staff() (406). Executable
--     by authenticated and service_role only.
--   * event_set_guest_cancelled(uuid,boolean,text) is dropped and made again
--     returning jsonb (it returned nothing): rule 3. It starts with
--     require_active_staff(). The same grants.
--   * event_save_guest(jsonb) (patched): rule 2.
--   * event_save(jsonb) (patched): rules 4 and 5.
--   * event_delete(uuid,text) (patched): rule 7.
--   * event_ticket_line_check(jsonb,date,uuid,integer) (patched): rule 6.
--   * web_order_make_invoice(uuid,uuid,boolean,boolean) (patched): sets
--     energia.paid_web_order to its order's id around its
--     create_invoice_with_details call, and clears it after, on success and
--     on failure.
--   * web_order_can_link(web_orders) (replaced): rule 8.
--   * event_summary(uuid) (replaced): per day "ticket_lines" (the ticket
--     lines on invoices that are not deleted covering the day); per option
--     "sold" now means on an invoice that is not deleted, and
--     "on_any_invoice" (a deleted one too, so it cannot be removed);
--     "web_channel_mode" (the mode of the event's website channel, or
--     null). The editor locks what the server locks, and says while the
--     website sells that it follows On sale.
--   * event_invoice_membership(uuid[]) (patched): rule 10. Its "chosen"
--     step: the ticket's event first, then the event whose day and store the
--     invoice falls on; the source says 'event_day' when that is the same
--     event, 'ticket' otherwise, 'staff' when marked by hand. Of the events
--     running that day at that store, one whose ticket the invoice holds
--     comes first; of the tickets' events, the one running that day.
--     Everything that asks which event a sale is follows it: the Sales tab
--     (event_invoices), the invoice list's badge (invoice_events), an
--     invoice's event (invoice_event_guests) and the Events report
--     (report_events).
--   * web_order_close_refunded(uuid,text,boolean) (new): rule 9, for the
--     Website orders tab. p_close true closes, false reopens. It starts with
--     require_active_staff('{owner,manager}') (406), then
--     require_store_access on the channel's store. Reopen reads what the
--     close changed from the close's audit row. Executable by authenticated
--     and service_role only.
--   * web_order_dismiss(uuid,text,boolean) (patched): rule 9. Restore
--     refuses an order closed as refunded (its latest close or dismissal is
--     a close), and Dismiss refuses a reason that starts "Refunded outside
--     the app:". Nothing else changes: its own Owner, Admin or Manager check
--     stays first (scripts/permissions/tests/staff-only-functions.sql lists
--     it so), and its grants are kept.
--   * web_order_tickets(text) (new): rule 11, for the edge function
--     web-ticket-order's new "tickets" message: {status: 'ok', tickets:
--     {<pass>: true | false}} for each pass in the channel's ticket_map, or
--     {status: 'refused'} for a channel it does not know. Internal: the
--     service role's alone (as web_order_sync and web_order_staff).
--
-- NOT CHANGED
--
--   * The staff link's own Dismiss and Restore otherwise (for Owners, Admins
--     and Managers; a reason of at least 3 characters, as before; the page
--     now says so before it sends).
--   * web_order_link_target, web_orders_list (they call web_order_can_link
--     and follow it; the list already returns each order's reason, which
--     says when it was closed as refunded), web_order_paid, web_order_names
--     (a payment or names sent again for an order closed as refunded answer
--     its status, dismissed, which the edge function now passes back),
--     web_order_sync (it lists a closed order as dismissed, and the website
--     marks its rows so).
--   * event_candidate_invoices (it already offers every invoice holding the
--     event's ticket, and every one on its days at its stores),
--     set_invoice_event, clear_invoice_event, event_invoice_overrides.
--   * event_day_load, event_guest_list (it already returns who checked a
--     guest in), event_can_run, write_audit_ex, create_invoice_with_details
--     and every table, column and constraint. No row is changed.
--   * A deleted invoice restored by the service role (restore_record; no
--     page can) brings back its ticket guests on their days, as before.
--
-- OUTSIDE THE DATABASE (same release)
--
--   * supabase/functions/web-ticket-order: a "tickets" message (signed like
--     the others, the channel only) calls web_order_tickets; a "paid" or
--     "names" answered dismissed (an order closed as refunded) is passed back
--     instead of asking for a retry. Deploy it after this migration and
--     before the website (supabase functions deploy web-ticket-order
--     --no-verify-jwt).
--   * The seminar website (rev22-energia-seminar, branch events7-onsale):
--     the ticket page and checkout ask "tickets" and stop offering a pass
--     the app has taken off sale; so do the PayNow / bank transfer box and
--     the header's prices (with no pass on sale, the box says sales are
--     closed). If the inventory cannot be asked they keep their own closing
--     times.
--
-- SAFETY
--
--   Apart from the lock timeout, the migration is one statement (a DO
--   block), so it is atomic however it is run. Every guard and anchor is
--   checked, and every new text built and compared with its AFTER md5,
--   before anything is changed. Each changed function must be the
--   production version read on 9 Oct 2026 (BEFORE), or already this
--   migration's (AFTER), which is left alone so a re-run changes nothing;
--   the two functions dropped and made again must be wholly before or wholly
--   after; the two new ones must both be missing, or both already this
--   migration's. The functions relied on must be the versions read that
--   day, and the reason web_order_paid and web_order_door give a refusal
--   while off must still be the one rule 8 reads. Every anchor must match
--   exactly once. No other function may take these names (the API picks an
--   overload by name). The patched and replaced functions keep their owner
--   and grants (CREATE OR REPLACE, same arguments and result); the two made
--   again are granted to authenticated and service_role only, as before;
--   of the two new ones, web_order_close_refunded is granted to
--   authenticated and service_role, web_order_tickets to service_role
--   alone. After installing, every function must have its AFTER md5, and
--   the grants are checked from the catalogue. Then, inside a block that is
--   always undone, a made-up Owner and member of staff run the door:
--   check-in, a second check-in, Save code, cancel refused, Undo, the audit
--   rows, and a login that is not staff refused; a made-up channel answers
--   which pass is on sale, before and after its ticket goes off sale; a
--   made-up website order is closed as refunded (staff and an Admin
--   refused) and reopened, both audited; and a made-up staff-link payment
--   refused while off is closed, is not brought back by Restore, and is
--   reopened refused, as it was. No row remains. The definitions are read and
--   compared with the search path set to public.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef, search_path public):
--   event_check_in(uuid,date,boolean,text)                21e85a7781da54b9a653ca5172557b0f  (dropped)
--   event_check_in(uuid,date,boolean,text,boolean)        (missing)
--   event_set_guest_cancelled(uuid,boolean,text)          759515f5e1088e7eac03516687ffebc7  (returns void)
--   event_save_guest(jsonb)                               99c339989f7a94d6409965b50c2fba0c
--   event_save(jsonb)                                     00746dd1b67f4e46fe931665446d5fa1
--   event_delete(uuid,text)                               17a5f7b580cf6614059212d3968857e7
--   event_ticket_line_check(jsonb,date,uuid,integer)      c8f5c0727d4125447370909dd7528b98
--   event_summary(uuid)                                   7f9fafdf76ccd90cf8f4f002f8f41562
--   web_order_can_link(web_orders)                        969d0df96201dcb61877c7934d1560d2
--   web_order_make_invoice(uuid,uuid,boolean,boolean)     a89168963591c78841c5dc37c12162b8
--   event_invoice_membership(uuid[])                      500a0efff068532cccd8786e685975cb
--   web_order_dismiss(uuid,text,boolean)                  78d5e48896ec24a759db8e9752fec93e
--   web_order_close_refunded(uuid,text,boolean)           (missing)
--   web_order_tickets(text)                               (missing)
--   (relied on, not changed)
--   event_can_run(uuid)                                   dac12d0086533bb528e847eb828809df
--   event_day_load(uuid)                                  b353d9ca55be4fdc751ef4ca3771dfc5
--   event_guest_list(uuid)                                cbe2f3ef06fe97e59fc2e3b19fd35cac
--   require_active_staff(text[])                          877b3aa74cea559881979bb161c450e2
--   require_store_access(uuid)                            f9332fd2f0092337d64501d8a647c23f
--   user_has_store_access(uuid)                           8c82c6bcb64f496c5a05a2b8dafa95f8
--   web_order_door_review(web_orders,web_order_channels)  ea1a04a8ebd0705747724906c908ec0e
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)
--                                                         c705c733e213a27f0dc32d54322cc855
--   public function fingerprint (not a guard)             675ac22c631079b58f06813d0d463fa3 after 413;
--                                                         af220b17c3d38e0ac75375c31ed12f2b after 414;
--                                                         897ad364eff917861989315bb2fa0e43 after 414,
--                                                         421 and 428 (production at 19:00 on 9 Oct 2026)
--   (414 went live at 16:47 that day, 421 at 18:47 and 428 at 18:48
--   (20261009104732, 20261009104830); none changes a function above. Every
--   md5 here was read again from production after them.)
-- AFTER (for later guards):
--   event_check_in(uuid,date,boolean,text,boolean)        606cdbba5f8a6197fb1c5b216daf1e41
--   event_set_guest_cancelled(uuid,boolean,text)          f58e462efb1f14e604ee62a7feec6b09
--   event_save_guest(jsonb)                               f828b8558735696b392ae0f2e6c64a24
--   event_save(jsonb)                                     949bb31d24028424e2c2d554e6490f27
--   event_delete(uuid,text)                               c1741487cf111d0a65faec47e5b2ae18
--   event_ticket_line_check(jsonb,date,uuid,integer)      7f32dd2a6bf54bb147d6f8f728acb4f0
--   event_summary(uuid)                                   8d81aaf9d07ebff0ef435063c6344287
--   web_order_can_link(web_orders)                        b90b301cea066e15c1616685fa3dfec6
--   web_order_make_invoice(uuid,uuid,boolean,boolean)     9d4bd47df0bb803a5f7958249175979f
--   event_invoice_membership(uuid[])                      ef9db53cd73df1e19f623da8f7cef6f9
--   web_order_dismiss(uuid,text,boolean)                  a8a43d890dd5f86c4664a49bbfd5e343
--   web_order_close_refunded(uuid,text,boolean)           2449b8e0a0d3e764b1f7c279b7f428ec  (new)
--   web_order_tickets(text)                               84f73e226a310a198a0257bb915e1e2f  (new)
--   public function fingerprint                           91f4d8a799d8ae804c00688692bab7d4 on top of 413;
--                                                         af963e284ef29e811692d95117cca32b on top of 414;
--                                                         566e76f702c89c9846968e6fdd89cc45 on top of 414,
--                                                         421 and 428 (as production was at 19:00 on
--                                                         9 Oct 2026; tested, and worked out from
--                                                         production's md5s with these put in)
--
-- DEPLOY ORDER: this, then the edge function web-ticket-order, then the
-- seminar website, then the front end, by about 16 Oct 2026 so the door
-- team can rehearse; then reload the Events page on every door device. The
-- edge function and the website only add the "tickets" message: before
-- the edge function is deployed the website gets "invalid_request" and
-- keeps its own closing times. A page opened before this keeps working:
-- its Check in and Undo work as before, and its "Save code" no longer
-- changes a code (it shows the code
-- the server kept); reloading gives the new page. The new page against a
-- database without this checks in and undoes as before, and its "Save
-- code" is refused ("function not found"), so this goes first. The front
-- end of the same release also follows the Singapore date overnight
-- (EVENTS-2), asks before an Undo and before a check-in on another day,
-- reads the door list again every 25 seconds (EVENTS-3), labels the editor
-- on a phone (EVENTS-10), keeps a reason window open until it saves
-- (EVENTS-11), and lets only the window on top answer Escape.
--
-- Test: scripts/events/tests/door-check-in.sql (every rule here, a re-run,
-- the grants), scripts/events/tests/events.sql, scripts/web-orders/tests/
-- web-orders.sql, scripts/permissions/tests/function-grants.sql,
-- scripts/permissions/tests/staff-only-functions.sql;
-- npm run test:events (the page), node --test scripts/ui/tests/modal-escape.test.mjs,
-- npm run check:web-orders (the edge function), and in the website's
-- worktree npm test, npm run typecheck and npm run build.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New texts: the door ────────────────────────────────────────────────────
  c_check_in_def constant text := $def$CREATE OR REPLACE FUNCTION public.event_check_in(p_guest_id uuid, p_day date, p_attended boolean, p_code text DEFAULT NULL::text, p_save_code boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.event_guests%rowtype; r public.event_guest_days%rowtype; n public.event_guest_days%rowtype;
  v_code text := nullif(btrim(coalesce(p_code, '')), ''); v_action text;
begin
  perform public.require_active_staff();
  -- 415: two door devices may work on one guest. A check-in never changes one
  -- already made: it answers already_in, with the time, who checked the
  -- guest in and the code. Only Save code (p_save_code) changes the code of a
  -- guest who is in; an empty code clears it. Undo clears the check-in.
  -- Every change is in the audit log, as it was before and after.
  if p_attended is null then raise exception 'Say whether the guest is in'; end if;
  -- The guest is held while this runs, so a cancel waits for it.
  select * into g from public.event_guests where id = p_guest_id for share;
  if not found then raise exception 'Guest not found'; end if;
  if not public.event_can_run(g.event_id) then raise exception 'You do not have access to this event'; end if;
  if g.status <> 'registered' then raise exception '% is not registered (cancelled)', g.name; end if;
  select * into r from public.event_guest_days where guest_id = p_guest_id and day = p_day for update;
  if not found then raise exception '% is not registered for %', g.name, to_char(p_day, 'DD Mon YYYY'); end if;
  n := r;
  if coalesce(p_save_code, false) then
    if not p_attended then raise exception 'A code is saved with a check-in, not with an undo'; end if;
    if r.attended_at is null then
      raise exception '% is not checked in for % yet. Check them in first.', g.name, to_char(p_day, 'DD Mon YYYY'); end if;
    if r.check_in_code is distinct from v_code then
      update public.event_guest_days set check_in_code = v_code
       where guest_id = p_guest_id and day = p_day returning * into n;
      v_action := 'event_check_in_code_changed';
    end if;
  elsif p_attended then
    if r.attended_at is null then
      update public.event_guest_days set attended_at = now(), checked_in_by = auth.uid(), check_in_code = v_code
       where guest_id = p_guest_id and day = p_day returning * into n;
      v_action := 'event_checked_in';
    end if;
  elsif r.attended_at is not null or r.checked_in_by is not null or r.check_in_code is not null then
    update public.event_guest_days set attended_at = null, checked_in_by = null, check_in_code = null
     where guest_id = p_guest_id and day = p_day returning * into n;
    v_action := 'event_check_in_undone';
  end if;
  if v_action is not null then
    perform public.write_audit_ex('event_guest_days', p_guest_id, v_action,
      jsonb_build_object('event_id', g.event_id, 'day', r.day, 'attended_at', r.attended_at,
                         'checked_in_by', r.checked_in_by, 'check_in_code', r.check_in_code),
      jsonb_build_object('event_id', g.event_id, 'day', n.day, 'attended_at', n.attended_at,
                         'checked_in_by', n.checked_in_by, 'check_in_code', n.check_in_code),
      'events', null, null);
  end if;
  return jsonb_build_object('guest_id', n.guest_id, 'day', n.day, 'attended_at', n.attended_at,
    'check_in_code', n.check_in_code, 'checked_in_by', n.checked_in_by,
    'checked_in_by_name', (select p.full_name from public.profiles p where p.id = n.checked_in_by),
    'already_in', p_attended and not coalesce(p_save_code, false) and r.attended_at is not null,
    'changed', v_action is not null);
end $function$
$def$;

  c_cancelled_def constant text := $def$CREATE OR REPLACE FUNCTION public.event_set_guest_cancelled(p_guest_id uuid, p_cancelled boolean, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.event_guests%rowtype; v_dropped date[] := '{}';
begin
  perform public.require_active_staff();
  if p_cancelled is null then raise exception 'Say whether the guest is cancelled or restored'; end if;
  select * into g from public.event_guests where id = p_guest_id for update;
  if not found then raise exception 'Guest not found'; end if;
  if not public.event_can_run(g.event_id) then raise exception 'You do not have access to this event'; end if;
  if g.source <> 'free' then
    raise exception 'A ticket guest comes from an invoice. Cancel or correct the invoice to remove them.'; end if;
  if p_cancelled then
    -- 415: a day someone attended stays (as event_save_guest keeps it), so a
    -- guest who has checked in is not cancelled.
    if g.status = 'registered' and exists (select 1 from public.event_guest_days gd
                                             where gd.guest_id = p_guest_id and gd.attended_at is not null) then
      raise exception '% has already checked in. Undo the check-in first if they did not come.', g.name; end if;
    update public.event_guests set status = 'cancelled', cancelled_reason = nullif(btrim(coalesce(p_reason, '')), ''),
           cancelled_at = now(), updated_at = now(), updated_by = auth.uid()
     where id = p_guest_id and status = 'registered';
  else
    if g.status = 'cancelled' then
      -- 415: a day the event no longer has is dropped; with none left, the
      -- guest stays cancelled.
      select coalesce(array_agg(gd.day order by gd.day), '{}') into v_dropped
        from public.event_guest_days gd
       where gd.guest_id = p_guest_id
         and not exists (select 1 from public.event_days d where d.event_id = g.event_id and d.day = gd.day);
      if not exists (select 1 from public.event_guest_days gd join public.event_days d on d.event_id = g.event_id and d.day = gd.day
                      where gd.guest_id = p_guest_id) then
        raise exception 'None of %''s days are still days of this event. Add them again with the right day.', g.name; end if;
      delete from public.event_guest_days gd where gd.guest_id = p_guest_id and gd.day = any(v_dropped);
    end if;
    update public.event_guests set status = 'registered', cancelled_reason = null, cancelled_at = null,
           updated_at = now(), updated_by = auth.uid()
     where id = p_guest_id and status = 'cancelled';
  end if;
  perform public.write_audit_ex('event_guests', p_guest_id,
    case when p_cancelled then 'event_guest_cancelled' else 'event_guest_restored' end,
    jsonb_build_object('status', g.status), jsonb_build_object('event_id', g.event_id)
      || case when cardinality(v_dropped) > 0 then jsonb_build_object('days_dropped', to_jsonb(v_dropped)) else '{}'::jsonb end,
    'events', nullif(btrim(coalesce(p_reason, '')), ''), null);
  -- 415: as adding a guest answers: the days of theirs now over capacity.
  return jsonb_build_object('guest_id', g.id,
    'status', (select g2.status from public.event_guests g2 where g2.id = p_guest_id),
    'days_dropped', to_jsonb(v_dropped),
    'over_capacity', case when p_cancelled then '[]'::jsonb else
      coalesce((select jsonb_agg(jsonb_build_object('day', l.day, 'capacity', l.capacity, 'registered', l.registered) order by l.day)
                  from public.event_day_load(g.event_id) l
                 where l.capacity is not null and l.registered > l.capacity
                   and l.day in (select gd.day from public.event_guest_days gd where gd.guest_id = p_guest_id)), '[]') end);
end $function$
$def$;

  -- ── New texts: replaced whole ──────────────────────────────────────────────
  c_can_link_def constant text := $def$CREATE OR REPLACE FUNCTION public.web_order_can_link(p_order web_orders)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 415: only an order that took real money (live mode) is linked to an
  -- invoice made by hand: one recorded or waiting, or one refused because the
  -- channel was off, from the website or the staff link alike.
  select coalesce(p_order.livemode, false)
     and (p_order.status in ('recorded', 'needs_review')
          or (p_order.status = 'refused' and p_order.review_reason = 'The website channel is off'))
$function$
$def$;

  c_summary_def constant text := $def$CREATE OR REPLACE FUNCTION public.event_summary(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 415: per day, the ticket lines on invoices not deleted that cover it (they
  -- hold the day, as event_save checks); per option, 'sold' on an invoice not
  -- deleted (its days covered stay) and 'on_any_invoice', a deleted one too
  -- (it cannot be removed); and the mode of the event's website channel.
  select jsonb_build_object(
    'id', e.id, 'name', e.name, 'description', e.description,
    'daily_start', to_char(e.daily_start, 'HH24:MI'), 'daily_end', to_char(e.daily_end, 'HH24:MI'),
    'early_bird_until', e.early_bird_until, 'early_bird_percent', e.early_bird_percent,
    'is_active', e.is_active, 'notes', e.notes, 'created_at', e.created_at,
    'first_day', (select min(d.day) from public.event_days d where d.event_id = e.id),
    'last_day', (select max(d.day) from public.event_days d where d.event_id = e.id),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', l.day, 'capacity', l.capacity,
                        'registered', l.registered, 'attended', l.attended,
                        'ticket_lines', (select count(*)::int from public.invoice_items ii
                                           join public.event_ticket_options o on o.id = ii.event_ticket_option_id
                                           join public.invoices i on i.id = ii.invoice_id
                                          where o.event_id = e.id and i.deleted_at is null and l.day = any(ii.event_days)))
                        order by l.day)
                      from public.event_day_load(e.id) l), '[]'),
    'stores', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name)
                        from public.event_stores es join public.stores s on s.id = es.store_id
                       where es.event_id = e.id), '[]'),
    'options', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'days_count', o.days_count,
                          'price', o.price, 'is_active', o.is_active, 'sort_order', o.sort_order,
                          'early_bird_price', case when e.early_bird_until is not null
                             then round(o.price * (100 - e.early_bird_percent) / 100.0, 2) end,
                          'sold', (select exists (select 1 from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
                                                   where ii.event_ticket_option_id = o.id and i.deleted_at is null)),
                          'on_any_invoice', (select exists (select 1 from public.invoice_items ii where ii.event_ticket_option_id = o.id)))
                          order by o.sort_order, o.name)
                         from public.event_ticket_options o where o.event_id = e.id), '[]'),
    'guests', (select count(*) from public.event_guests g where g.event_id = e.id and g.status = 'registered'),
    'ticket_guests', (select count(*) from public.event_guests g where g.event_id = e.id and g.status = 'registered' and g.source = 'ticket'),
    'free_guests', (select count(*) from public.event_guests g where g.event_id = e.id and g.status = 'registered' and g.source = 'free'),
    'web_channel_mode', (select c.mode from public.web_order_channels c where c.event_id = e.id
                          order by case c.mode when 'live' then 0 when 'record_only' then 1 else 2 end, c.key limit 1),
    'can_manage', public.is_manager_or_above(),
    'can_run', public.event_can_run(e.id))
  from public.events e where e.id = p_event_id
$function$
$def$;

  -- ── New texts: made new (rules 9 and 11) ───────────────────────────────────
  c_close_def constant text := $def$CREATE OR REPLACE FUNCTION public.web_order_close_refunded(p_order_id uuid, p_reason text, p_close boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.web_orders%rowtype; ch public.web_order_channels%rowtype; n public.web_orders%rowtype;
  v_reason text := btrim(coalesce(p_reason, '')); v_old jsonb; v_review text;
begin
  perform public.require_active_staff('{owner,manager}');
  -- 415 (the Owner, 9 Oct 2026): an Owner or Manager closes an order whose
  -- payment was refunded outside the app, with a reason, so its event can be
  -- deleted. No invoice, payment or stock is touched. Reopen (p_close false)
  -- puts one closed by mistake back as it was before the close. Both are
  -- audited.
  if length(v_reason) < 3 then
    raise exception 'Give the reason (at least 3 characters)'; end if;
  select * into o from public.web_orders where id = p_order_id for update;
  if not found then raise exception 'Website order not found'; end if;
  select * into ch from public.web_order_channels where key = o.channel;
  perform public.require_store_access(ch.store_id);
  if coalesce(p_close, true) then
    -- What holds its event (event_delete): an order waiting for its invoice,
    -- or a real payment refused while the channel was off.
    if not (o.status in ('recorded', 'needs_review')
            or (o.status = 'refused' and coalesce(o.livemode, false) and o.review_reason = 'The website channel is off')) then
      raise exception 'Only an order waiting for its invoice, or a payment refused while the channel was off, can be closed'; end if;
    update public.web_orders
       set status = 'dismissed', review_reason = 'Refunded outside the app: ' || v_reason, updated_at = now()
     where id = o.id returning * into n;
  else
    -- The close's audit row keeps the order as it was before.
    select a.old_data into v_old from public.audit_logs a
     where a.table_name = 'web_orders' and a.record_id = o.id and a.action = 'web_order_closed_refunded'
     order by a.created_at desc limit 1;
    if o.status <> 'dismissed' or coalesce(o.review_reason, '') not like 'Refunded outside the app: %' or v_old is null then
      raise exception 'Only an order closed as refunded can be reopened'; end if;
    if exists (select 1 from public.events e where e.id = ch.event_id and e.deleted_at is not null) then
      raise exception 'Its event has been deleted, so the order cannot be reopened'; end if;
    if v_old->>'status' = 'refused' then
      -- A payment refused while the channel was off is refused again: it is
      -- linked to an invoice made by hand (never Create invoice), and it holds
      -- its event again.
      update public.web_orders set status = 'refused', review_reason = v_old->>'review_reason', updated_at = now()
       where id = o.id returning * into n;
    else
      -- Any other waits in Needs review again. A staff-link registration gets
      -- the staff link's checks too, as Restore gives them.
      if o.provider = 'door' then v_review := public.web_order_door_review(o, ch); end if;
      update public.web_orders
         set status = 'needs_review',
             review_reason = 'Reopened after it was closed as refunded. Check the payment, then create or link its invoice.'
                             || coalesce(' ' || v_review || '.', ''),
             updated_at = now()
       where id = o.id returning * into n;
    end if;
  end if;
  perform public.write_audit_ex('web_orders', o.id,
    case when coalesce(p_close, true) then 'web_order_closed_refunded' else 'web_order_reopened' end,
    jsonb_build_object('status', o.status, 'review_reason', o.review_reason),
    jsonb_build_object('status', n.status, 'review_reason', n.review_reason, 'order_id', o.stripe_session_id),
    'events', v_reason, ch.store_id);
  return jsonb_build_object('status', n.status, 'invoice_no', null, 'review_reason', n.review_reason);
end $function$
$def$;

  c_tickets_def constant text := $def$CREATE OR REPLACE FUNCTION public.web_order_tickets(p_channel text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 415 (the Owner, 9 Oct 2026): the website sells a pass only while the app
  -- has its ticket on sale. For each pass in the channel's ticket_map: true
  -- while that ticket's On sale and its event's Tickets on sale are both
  -- ticked and the event is not deleted; false otherwise, and for a pass
  -- whose ticket is not one of the channel's event. The edge function
  -- web-ticket-order asks it for the website ("tickets"); no login may.
  select case when ch.key is null then jsonb_build_object('status', 'refused', 'tickets', '{}'::jsonb)
    else jsonb_build_object('status', 'ok', 'tickets', coalesce((
      select jsonb_object_agg(m.key, exists (
               select 1 from public.event_ticket_options o join public.events e on e.id = o.event_id
                where jsonb_typeof(m.value) = 'object' and o.id::text = m.value->>'option_id'
                  and e.id = ch.event_id and o.is_active and e.is_active and e.deleted_at is null))
        from jsonb_each(ch.ticket_map) m), '{}'::jsonb)) end
    from (select 1) one left join public.web_order_channels ch on ch.key = p_channel
$function$
$def$;

  -- ── Anchors: event_save_guest (rule 2) ─────────────────────────────────────
  c_sg_by_a constant text := $q$  if v_by is not null and not exists (select 1 from public.profiles p where p.id = v_by and p.is_active
$q$;
  c_sg_by_r constant text := $q$  -- 415: the registrar is checked only when it changes, so a guest whose
  -- registrar has since left can still be edited; an explicit null (Not
  -- recorded) clears it below.
  if v_by is not null and v_by is distinct from g.registered_by
     and not exists (select 1 from public.profiles p where p.id = v_by and p.is_active
$q$;
  c_sg_set_a constant text := $q$registered_by = coalesce(v_by, registered_by), $q$;
  c_sg_set_r constant text := $q$registered_by = case when p_guest ? 'registered_by' then v_by else registered_by end, $q$;

  -- ── Anchors: event_save (rules 4 and 5) ────────────────────────────────────
  c_es_decl_a constant text := $q$  v_keep_opts uuid[] := '{}';
$q$;
  c_es_decl_r constant text := $q$  v_keep_opts uuid[] := '{}';
  -- 415
  v_day date; v_free integer; v_docs text; v_other integer; v_parts text[];
  v_people boolean := false; v_tickets boolean := false;
$q$;
  c_es_cap_a constant text := $q$  if exists (select 1 from jsonb_array_elements(p_event->'days') d
              where nullif(d->>'capacity', '') is not null and (d->>'capacity')::integer <= 0) then
    raise exception 'A day''s capacity must be more than zero, or left empty for no limit'; end if;
$q$;
  c_es_cap_r constant text := $q$  -- 415: a whole number, or a raw database error follows.
  if exists (select 1 from jsonb_array_elements(p_event->'days') d
              where nullif(d->>'capacity', '') is not null
                and case when d->>'capacity' ~ '^[0-9]{1,9}$' then (d->>'capacity')::integer <= 0 else true end) then
    raise exception 'A day''s capacity must be a whole number more than zero, or left empty for no limit'; end if;
$q$;
  c_es_opt_a constant text := $q$    if nullif(x->>'days_count', '') is null or (x->>'days_count')::integer < 1 or (x->>'days_count')::integer > v_n_days then
      raise exception 'The "%" ticket must cover between 1 and % day(s)', x->>'name', v_n_days; end if;
    if nullif(x->>'price', '') is null or (x->>'price')::numeric < 0 then
      raise exception 'The "%" ticket needs a price of zero or more', x->>'name'; end if;
$q$;
  c_es_opt_r constant text := $q$    -- 415: whole numbers, and a price in dollars and cents, checked before
    -- they are read, so no raw database error and no silent rounding.
    if (case when coalesce(x->>'days_count', '') ~ '^[0-9]{1,4}$'
             then (x->>'days_count')::integer < 1 or (x->>'days_count')::integer > v_n_days else true end) then
      raise exception 'The "%" ticket must cover between 1 and % day(s)', x->>'name', v_n_days; end if;
    if coalesce(x->>'price', '') !~ '^[0-9]{1,10}(\.[0-9]+)?$' then
      raise exception 'The "%" ticket needs a price of zero or more', x->>'name'; end if;
    if (x->>'price')::numeric <> round((x->>'price')::numeric, 2) then
      raise exception 'Prices are in dollars and cents: the "%" ticket''s price has more than 2 decimals', x->>'name'; end if;
    if x ? 'sort_order' and jsonb_typeof(x->'sort_order') <> 'null' and coalesce(x->>'sort_order', '') !~ '^-?[0-9]{1,9}$' then
      raise exception 'The order of the "%" ticket must be a whole number', x->>'name'; end if;
$q$;
  c_es_eb_a constant text := $q$    raise exception 'The early-bird discount must be more than 0%% and at most 100%%'; end if;
$q$;
  c_es_eb_r constant text := $q$    raise exception 'The early-bird discount must be more than 0%% and at most 100%%'; end if;
  -- 415: kept to 2 decimals, as it is stored.
  if nullif(p_event->>'early_bird_percent', '') is not null
     and (p_event->>'early_bird_percent')::numeric <> round((p_event->>'early_bird_percent')::numeric, 2) then
    raise exception 'The early-bird discount may have at most 2 decimals'; end if;
$q$;
  c_es_day_a constant text := $q$    -- A day that people are coming on, or that a ticket covers, stays.
    select string_agg(to_char(d.day, 'DD Mon YYYY'), ', ' order by d.day) into v_bad
      from public.event_days d
     where d.event_id = v_id and not (d.day = any(v_days))
       and (exists (select 1 from public.event_guest_days gd join public.event_guests g on g.id = gd.guest_id
                     where g.event_id = v_id and g.status = 'registered' and gd.day = d.day)
            or exists (select 1 from public.invoice_items ii join public.event_ticket_options o on o.id = ii.event_ticket_option_id
                        where o.event_id = v_id and d.day = any(ii.event_days)));
    if v_bad is not null then
      raise exception 'People are registered for %, so that day cannot be removed. Cancel or move them first.', v_bad; end if;
$q$;
  c_es_day_r constant text := $q$    -- A day that people are coming on, or that a ticket covers, stays. 415: a
    -- ticket on a deleted invoice no longer holds it (as in event_delete), and
    -- the refusal says what does: how many free guests, and which invoices (by
    -- number at the person's stores; the others are counted). A ticket guest
    -- comes with their ticket, so their invoice is named instead.
    v_bad := null;
    for v_day in select d.day from public.event_days d where d.event_id = v_id and not (d.day = any(v_days)) order by d.day loop
      select count(*)::int, count(*) filter (where g.source = 'free')::int into v_cnt, v_free
        from public.event_guest_days gd join public.event_guests g on g.id = gd.guest_id
       where g.event_id = v_id and g.status = 'registered' and gd.day = v_day;
      select string_agg(t.doc, ', ' order by t.doc) filter (where t.mine), count(*) filter (where not t.mine)
        into v_docs, v_other
        from (select distinct i.id,
                     i.invoice_no || case when i.status::text in ('cancelled', 'refunded') then ' (' || i.status::text || ')' else '' end as doc,
                     public.user_has_store_access(i.store_id) as mine
                from public.invoice_items ii join public.event_ticket_options o on o.id = ii.event_ticket_option_id
                join public.invoices i on i.id = ii.invoice_id
               where o.event_id = v_id and i.deleted_at is null and v_day = any(ii.event_days)) t;
      v_parts := array_remove(array[
        case when v_free = 1 then '1 free guest is registered for it' when v_free > 1 then v_free || ' free guests are registered for it' end,
        case when v_docs is not null then 'tickets on ' || v_docs || ' cover it' end,
        case when v_other = 1 then 'a ticket on an invoice of another store covers it'
             when v_other > 1 then 'tickets on ' || v_other || ' invoices of other stores cover it' end,
        -- A ticket guest whose ticket no live invoice holds (not expected).
        case when v_cnt > v_free and v_docs is null and coalesce(v_other, 0) = 0
             then (v_cnt - v_free) || ' ticket guest(s) are registered for it' end], null);
      if cardinality(v_parts) > 0 then
        v_people := v_people or v_free > 0;
        v_tickets := v_tickets or v_cnt > v_free or v_docs is not null or v_other > 0;
        v_bad := concat_ws(' ', v_bad, to_char(v_day, 'DD Mon YYYY') || ' cannot be removed: '
                                       || array_to_string(v_parts, ', and ') || '.');
      end if;
    end loop;
    if v_bad is not null then
      raise exception '% %', v_bad, case when v_people and v_tickets then 'Cancel or move those guests, and correct those invoices, first.'
                                         when v_people then 'Cancel or move them first.'
                                         else 'Correct those invoices first.' end; end if;
$q$;
  c_es_dc_a constant text := $q$      if exists (select 1 from public.invoice_items ii where ii.event_ticket_option_id = v_opt)
$q$;
  c_es_dc_r constant text := $q$      -- 415: a ticket on a deleted invoice no longer holds the days covered.
      if exists (select 1 from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
                  where ii.event_ticket_option_id = v_opt and i.deleted_at is null)
$q$;
  c_es_rm_a constant text := $q$  select string_agg(o.name, ', ') into v_bad from public.event_ticket_options o
   where o.event_id = v_id and not (o.id = any(v_keep_opts))
     and exists (select 1 from public.invoice_items ii where ii.event_ticket_option_id = o.id);
  if v_bad is not null then
    raise exception '"%" has been sold, so it cannot be removed. Take it off sale instead.', v_bad; end if;
$q$;
  c_es_rm_r constant text := $q$  -- 415: an option on any invoice, a deleted one too, stays (the invoice line
  -- keeps it); the refusal names the invoices.
  select string_agg(format('"%s" is on %s', b.name,
                           concat_ws(' and ', b.docs, case when b.other = 1 then 'an invoice of another store'
                                                           when b.other > 1 then b.other || ' invoices of other stores' end)),
                    '; ' order by b.name), count(*)
    into v_bad, v_cnt
    from (select t.name, string_agg(t.doc, ', ' order by t.doc) filter (where t.mine) as docs,
                 count(*) filter (where not t.mine) as other
            from (select distinct o.id as option_id, o.name, i.id,
                         i.invoice_no || case when i.deleted_at is not null then ' (deleted)' else '' end as doc,
                         public.user_has_store_access(i.store_id) as mine
                    from public.event_ticket_options o
                    join public.invoice_items ii on ii.event_ticket_option_id = o.id
                    join public.invoices i on i.id = ii.invoice_id
                   where o.event_id = v_id and not (o.id = any(v_keep_opts))) t
           group by t.option_id, t.name) b;
  if v_bad is not null then
    raise exception '%, so % cannot be removed. Take % off sale instead.', v_bad,
      case when v_cnt = 1 then 'it' else 'they' end, case when v_cnt = 1 then 'it' else 'them' end; end if;
$q$;

  -- ── Anchors: event_delete (rule 7) ─────────────────────────────────────────
  c_ed_decl_a constant text := $q$declare e public.events%rowtype;
$q$;
  c_ed_decl_r constant text := $q$declare e public.events%rowtype; v_live integer; v_open integer;
$q$;
  c_ed_web_a constant text := $q$    raise exception 'Tickets to "%" are on invoices, so it cannot be deleted. Take it off sale instead.', e.name; end if;
$q$;
  c_ed_web_r constant text := $q$    raise exception 'Tickets to "%" are on invoices, so it cannot be deleted. Take it off sale instead.', e.name; end if;
  -- 415: not while its website channel takes orders, or holds orders waiting
  -- for an invoice: they would have nowhere to show. A payment refused while
  -- the channel was off took real money and is linked to an invoice made by
  -- hand (web_order_can_link), so it waits too. A recorded test order counts
  -- as well.
  select count(*) into v_live from public.web_order_channels c where c.event_id = p_event_id and c.mode <> 'off';
  select count(*) into v_open from public.web_orders w join public.web_order_channels c on c.key = w.channel
   where c.event_id = p_event_id
     and (w.status in ('recorded', 'needs_review')
          or (w.status = 'refused' and coalesce(w.livemode, false) and w.review_reason = 'The website channel is off'));
  if v_live > 0 then
    raise exception 'The website still takes orders for "%". Switch its channel Off%, then delete the event.', e.name,
      case when v_open > 0 then ' and deal with its open orders' else '' end; end if;
  if v_open > 0 then
    raise exception 'The website channel of "%" has % order(s) waiting for an invoice. Create or link their invoices first.',
      e.name, v_open; end if;
$q$;

  -- ── Anchors: event_ticket_line_check (rule 6) ──────────────────────────────
  c_lc_a constant text := $q$    when not e.is_active or not o.is_active then format('"%s" tickets for "%s" are not on sale', o.name, e.name)
$q$;
  c_lc_r constant text := $q$    -- 415: money already taken is honoured. web_order_make_invoice alone sets
    -- energia.paid_web_order, to its own order, around its own invoice.
    when (not e.is_active or not o.is_active)
         and not exists (select 1 from public.web_orders w join public.web_order_channels c on c.key = w.channel
                          where w.id::text = current_setting('energia.paid_web_order', true)
                            and c.event_id = e.id and w.status in ('recorded', 'needs_review'))
      then format('"%s" tickets for "%s" are not on sale', o.name, e.name)
$q$;

  -- ── Anchors: event_invoice_membership (rule 10) ────────────────────────────
  c_mem_a constant text := $q$           case when ov.invoice_id is not null then ev.id else coalesce(d.event_id, t.event_id) end as event_id,
           case when ov.invoice_id is not null then 'staff'
                when d.event_id is not null then 'event_day' else 'ticket' end as source
$q$;
  c_mem_r constant text := $q$           -- 415 (the Owner, 9 Oct 2026): a ticket sale counts under the event
           -- the ticket is for, not the event running that day. The whole
           -- invoice, products included, follows its ticket (the Owner is
           -- asked about products). A sale with no ticket goes by its day and
           -- store; staff marking decides first.
           case when ov.invoice_id is not null then ev.id else coalesce(t.event_id, d.event_id) end as event_id,
           case when ov.invoice_id is not null then 'staff'
                when d.event_id is not null and d.event_id = coalesce(t.event_id, d.event_id) then 'event_day'
                else 'ticket' end as source
$q$;
  c_mem_day_a constant text := $q$     order by inv.id, e.created_at, e.id),
  by_ticket as (
$q$;
  c_mem_day_r constant text := $q$     -- 415: of the events running that day at that store, one whose ticket
     -- the invoice holds comes first.
     order by inv.id,
              not exists (select 1 from public.invoice_items ii
                            join public.event_ticket_options o on o.id = ii.event_ticket_option_id
                           where ii.invoice_id = inv.id and ii.line_kind = 'event_ticket' and o.event_id = e.id),
              e.created_at, e.id),
  by_ticket as (
$q$;
  c_mem_tk_a constant text := $q$     order by ii.invoice_id, e.created_at, e.id),
  chosen as (
$q$;
  c_mem_tk_r constant text := $q$     -- 415: of the tickets' events, the one running that day at that store
     -- comes first, so its own ticket counts under it.
     order by ii.invoice_id,
              not exists (select 1 from on_day d where d.invoice_id = ii.invoice_id and d.event_id = e.id),
              e.created_at, e.id),
  chosen as (
$q$;

  -- ── Anchors: web_order_dismiss (rule 9) ────────────────────────────────────
  c_wd_dis_a constant text := $q$    if length(btrim(coalesce(p_reason, ''))) < 3 then
      raise exception 'Give the reason for dismissing it (at least 3 characters)'; end if;
$q$;
  c_wd_dis_r constant text := $q$    if length(btrim(coalesce(p_reason, ''))) < 3 then
      raise exception 'Give the reason for dismissing it (at least 3 characters)'; end if;
    -- 415: that start marks an order closed as refunded, which Reopen undoes.
    if btrim(p_reason) like 'Refunded outside the app:%' then
      raise exception 'Start the reason another way. "Refunded outside the app:" marks an order closed as refunded.'; end if;
$q$;
  c_wd_res_a constant text := $q$    if o.status <> 'dismissed' then raise exception 'Only a dismissed registration can be restored'; end if;
$q$;
  c_wd_res_r constant text := $q$    if o.status <> 'dismissed' then raise exception 'Only a dismissed registration can be restored'; end if;
    -- 415 (the Owner, 9 Oct 2026): one closed as refunded is reopened only with
    -- Reopen (web_order_close_refunded): by an Owner or Manager, with a reason,
    -- not once its event is deleted, and as it was before the close.
    if coalesce(o.review_reason, '') like 'Refunded outside the app: %'
       and (select a.action from public.audit_logs a
             where a.table_name = 'web_orders' and a.record_id = o.id
               and a.action in ('web_order_closed_refunded', 'web_order_dismissed')
             order by a.created_at desc, a.action = 'web_order_closed_refunded' desc limit 1) = 'web_order_closed_refunded' then
      raise exception 'This order was closed as refunded. Use Reopen instead.'; end if;
$q$;

  -- ── Anchors: web_order_make_invoice (rule 6) ───────────────────────────────
  c_mi_set_a constant text := $q$    if v_door then
      -- 380: dated on the date paid (so the early bird follows it), never
$q$;
  c_mi_set_r constant text := $q$    -- 415: the money is taken, so this order's ticket passes the On sale
    -- check (event_ticket_line_check) while its invoice is made.
    perform set_config('energia.paid_web_order', o.id::text, true);
    if v_door then
      -- 380: dated on the date paid (so the early bird follows it), never
$q$;
  c_mi_clear_a constant text := $q$    select total_amount into v_total from public.invoices where id = v_inv;
$q$;
  c_mi_clear_r constant text := $q$    perform set_config('energia.paid_web_order', '', true);
    select total_amount into v_total from public.invoices where id = v_inv;
$q$;
  c_mi_exc_a constant text := $q$    get stacked diagnostics v_state = returned_sqlstate, v_reason = message_text;
$q$;
  c_mi_exc_r constant text := $q$    get stacked diagnostics v_state = returned_sqlstate, v_reason = message_text;
    perform set_config('energia.paid_web_order', '', true);
$q$;

  -- ── AFTER md5s ─────────────────────────────────────────────────────────────
  c_check_in_after constant text := '606cdbba5f8a6197fb1c5b216daf1e41';
  c_cancelled_after constant text := 'f58e462efb1f14e604ee62a7feec6b09';
  c_save_guest_after constant text := 'f828b8558735696b392ae0f2e6c64a24';
  c_save_after constant text := '949bb31d24028424e2c2d554e6490f27';
  c_delete_after constant text := 'c1741487cf111d0a65faec47e5b2ae18';
  c_line_check_after constant text := '7f32dd2a6bf54bb147d6f8f728acb4f0';
  c_summary_after constant text := '8d81aaf9d07ebff0ef435063c6344287';
  c_can_link_after constant text := 'b90b301cea066e15c1616685fa3dfec6';
  c_make_invoice_after constant text := '9d4bd47df0bb803a5f7958249175979f';
  c_membership_after constant text := 'ef9db53cd73df1e19f623da8f7cef6f9';
  c_close_after constant text := '2449b8e0a0d3e764b1f7c279b7f428ec';
  c_tickets_after constant text := '84f73e226a310a198a0257bb915e1e2f';
  c_dismiss_after constant text := 'a8a43d890dd5f86c4664a49bbfd5e343';
  -- BEFORE md5s of the two made again.
  c_check_in_before constant text := '21e85a7781da54b9a653ca5172557b0f';
  c_cancelled_before constant text := '759515f5e1088e7eac03516687ffebc7';
  -- What the page calls, and what only the server calls (grants as before).
  c_client constant text[] := array['event_check_in(uuid,date,boolean,text,boolean)',
    'event_set_guest_cancelled(uuid,boolean,text)', 'event_save_guest(jsonb)', 'event_save(jsonb)', 'event_delete(uuid,text)',
    'web_order_close_refunded(uuid,text,boolean)', 'web_order_dismiss(uuid,text,boolean)'];
  c_internal constant text[] := array['event_ticket_line_check(jsonb,date,uuid,integer)', 'event_summary(uuid)',
    'web_order_can_link(web_orders)', 'web_order_make_invoice(uuid,uuid,boolean,boolean)',
    'event_invoice_membership(uuid[])', 'web_order_tickets(text)'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_role text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
  v_check_in_new boolean; v_cancelled_new boolean; v_new_new boolean;
  v_owner uuid; v_staff uuid; v_admin uuid; v_store uuid; v_event uuid; v_guest uuid; v_out jsonb; v_err text;
  v_pm uuid; v_channel text; v_order uuid; v_door uuid;
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and new texts: nothing changes unless all pass ─────────
  -- Patched in place, or replaced whole: production's version, or already this.
  for r in select * from (values
    ('event_save_guest(jsonb)', '99c339989f7a94d6409965b50c2fba0c', c_save_guest_after, null::text,
     array[[c_sg_by_a, c_sg_by_r], [c_sg_set_a, c_sg_set_r]]),
    ('event_save(jsonb)', '00746dd1b67f4e46fe931665446d5fa1', c_save_after, null::text,
     array[[c_es_decl_a, c_es_decl_r], [c_es_cap_a, c_es_cap_r], [c_es_opt_a, c_es_opt_r], [c_es_eb_a, c_es_eb_r],
           [c_es_day_a, c_es_day_r], [c_es_dc_a, c_es_dc_r], [c_es_rm_a, c_es_rm_r]]),
    ('event_delete(uuid,text)', '17a5f7b580cf6614059212d3968857e7', c_delete_after, null::text,
     array[[c_ed_decl_a, c_ed_decl_r], [c_ed_web_a, c_ed_web_r]]),
    ('event_ticket_line_check(jsonb,date,uuid,integer)', 'c8f5c0727d4125447370909dd7528b98', c_line_check_after, null::text,
     array[[c_lc_a, c_lc_r]]),
    ('web_order_make_invoice(uuid,uuid,boolean,boolean)', 'a89168963591c78841c5dc37c12162b8', c_make_invoice_after, null::text,
     array[[c_mi_set_a, c_mi_set_r], [c_mi_clear_a, c_mi_clear_r], [c_mi_exc_a, c_mi_exc_r]]),
    ('event_summary(uuid)', '7f9fafdf76ccd90cf8f4f002f8f41562', c_summary_after, c_summary_def, null::text[]),
    ('web_order_can_link(web_orders)', '969d0df96201dcb61877c7934d1560d2', c_can_link_after, c_can_link_def, null::text[]),
    ('event_invoice_membership(uuid[])', '500a0efff068532cccd8786e685975cb', c_membership_after, null::text,
     array[[c_mem_day_a, c_mem_day_r], [c_mem_tk_a, c_mem_tk_r], [c_mem_a, c_mem_r]]),
    ('web_order_dismiss(uuid,text,boolean)', '78d5e48896ec24a759db8e9752fec93e', c_dismiss_after, null::text,
     array[[c_wd_dis_a, c_wd_dis_r], [c_wd_res_a, c_wd_res_r]])
  ) x(fn, before_md5, after_md5, whole, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '415: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '415: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '415: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    if r.edits is null then
      d := r.whole;
    else
      for k in 1 .. array_length(r.edits, 1) loop
        n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
        if n <> 1 then
          raise exception '415: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
        d := replace(d, r.edits[k][1], r.edits[k][2]);
      end loop;
    end if;
    if md5(d) <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || md5(d)); end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- Made again: wholly before (production's) or wholly after (this). Read
  -- through to_regprocedure, so a version that is not there reads as null.
  if to_regprocedure('public.event_check_in(uuid,date,boolean,text)') is not null
     and to_regprocedure('public.event_check_in(uuid,date,boolean,text,boolean)') is null
     and md5(pg_get_functiondef(to_regprocedure('public.event_check_in(uuid,date,boolean,text)'))) = c_check_in_before then
    v_check_in_new := true;
  elsif to_regprocedure('public.event_check_in(uuid,date,boolean,text)') is null
     and to_regprocedure('public.event_check_in(uuid,date,boolean,text,boolean)') is not null
     and md5(pg_get_functiondef(to_regprocedure('public.event_check_in(uuid,date,boolean,text,boolean)'))) = c_check_in_after then
    v_check_in_new := false;
    raise notice '415: public.event_check_in is already this version; left alone';
  else
    raise exception '415: public.event_check_in is neither production''s 4-argument version (md5 %) nor this migration''s. Re-read it and re-test before applying.', c_check_in_before;
  end if;
  if to_regprocedure('public.event_set_guest_cancelled(uuid,boolean,text)') is null then
    raise exception '415: public.event_set_guest_cancelled(uuid,boolean,text) is missing'; end if;
  v := md5(pg_get_functiondef('public.event_set_guest_cancelled(uuid,boolean,text)'::regprocedure));
  if v = c_cancelled_before then
    v_cancelled_new := true;
  elsif v = c_cancelled_after then
    v_cancelled_new := false;
    raise notice '415: public.event_set_guest_cancelled is already this version; left alone';
  else
    raise exception '415: public.event_set_guest_cancelled is not the version this was tested against (md5 %). Re-read it and re-test before applying.', v;
  end if;
  -- Made new: both missing, or both already this migration's.
  if to_regprocedure('public.web_order_close_refunded(uuid,text,boolean)') is null
     and to_regprocedure('public.web_order_tickets(text)') is null then
    v_new_new := true;
  elsif md5(coalesce(pg_get_functiondef(to_regprocedure('public.web_order_close_refunded(uuid,text,boolean)')), '')) = c_close_after
     and md5(coalesce(pg_get_functiondef(to_regprocedure('public.web_order_tickets(text)')), '')) = c_tickets_after then
    v_new_new := false;
    raise notice '415: public.web_order_close_refunded and public.web_order_tickets are already this version; left alone';
  else
    raise exception '415: public.web_order_close_refunded or public.web_order_tickets is there but not this migration''s. Re-read them and re-test before applying.';
  end if;
  if md5(c_close_def) <> c_close_after then
    v_bad := concat_ws('; ', v_bad, 'web_order_close_refunded(uuid,text,boolean) ' || md5(c_close_def)); end if;
  if md5(c_tickets_def) <> c_tickets_after then
    v_bad := concat_ws('; ', v_bad, 'web_order_tickets(text) ' || md5(c_tickets_def)); end if;
  if md5(c_check_in_def) <> c_check_in_after then
    v_bad := concat_ws('; ', v_bad, 'event_check_in(uuid,date,boolean,text,boolean) ' || md5(c_check_in_def)); end if;
  if md5(c_cancelled_def) <> c_cancelled_after then
    v_bad := concat_ws('; ', v_bad, 'event_set_guest_cancelled(uuid,boolean,text) ' || md5(c_cancelled_def)); end if;
  if v_bad is not null then
    raise exception '415: a built text is not the tested one: %', v_bad; end if;

  -- Relied on, not changed: the versions read on 9 Oct 2026.
  for r in select * from (values
    ('event_can_run(uuid)', 'dac12d0086533bb528e847eb828809df'),
    ('event_day_load(uuid)', 'b353d9ca55be4fdc751ef4ca3771dfc5'),
    ('event_guest_list(uuid)', 'cbe2f3ef06fe97e59fc2e3b19fd35cac'),
    ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
    ('require_store_access(uuid)', 'f9332fd2f0092337d64501d8a647c23f'),
    ('user_has_store_access(uuid)', '8c82c6bcb64f496c5a05a2b8dafa95f8'),
    ('web_order_door_review(web_orders,web_order_channels)', 'ea1a04a8ebd0705747724906c908ec0e'),
    ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '415: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  -- Rule 8 reads the reason a payment or a staff-link registration is
  -- refused with while the channel is off.
  foreach v in array array['web_order_paid(jsonb)', 'web_order_door(jsonb)'] loop
    if to_regprocedure('public.' || v) is null
       or position('''The website channel is off''' in pg_get_functiondef(to_regprocedure('public.' || v))) = 0 then
      raise exception '415: public.% no longer refuses with ''The website channel is off''; rule 8 reads that reason', v; end if;
  end loop;
  -- Rule 6 reaches the ticket check through the invoice it makes
  -- (create_invoice_with_details, then create_invoice). Read by content, not
  -- md5: other work changes these two, and only the call matters here.
  if to_regprocedure('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)') is null
     or to_regprocedure('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)') is null
     or position('public.create_invoice(' in coalesce(pg_get_functiondef(to_regprocedure('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)')), '')) = 0
     or position('event_ticket_line_check(' in coalesce(pg_get_functiondef(to_regprocedure('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)')), '')) = 0 then
    raise exception '415: an invoice no longer reaches event_ticket_line_check through create_invoice_with_details and create_invoice; re-read and re-test rule 6'; end if;
  -- The columns read.
  select string_agg(a.attrelid::regclass::text || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|'
                    order by a.attrelid::regclass::text, a.attname) into v
    from pg_attribute a
   where not a.attisdropped and (a.attrelid, a.attname) in (
     ('public.web_orders'::regclass, 'livemode'), ('public.web_orders'::regclass, 'status'),
     ('public.web_orders'::regclass, 'review_reason'), ('public.web_orders'::regclass, 'channel'),
     ('public.web_order_channels'::regclass, 'key'), ('public.web_order_channels'::regclass, 'event_id'),
     ('public.web_order_channels'::regclass, 'mode'), ('public.event_guest_days'::regclass, 'attended_at'),
     ('public.event_guest_days'::regclass, 'checked_in_by'), ('public.event_guest_days'::regclass, 'check_in_code'),
     ('public.invoice_items'::regclass, 'event_days'), ('public.invoices'::regclass, 'deleted_at'),
     ('public.web_order_channels'::regclass, 'store_id'), ('public.web_order_channels'::regclass, 'ticket_map'),
     ('public.event_ticket_options'::regclass, 'is_active'), ('public.events'::regclass, 'is_active'),
     ('public.events'::regclass, 'deleted_at'), ('public.audit_logs'::regclass, 'table_name'),
     ('public.audit_logs'::regclass, 'record_id'), ('public.audit_logs'::regclass, 'action'),
     ('public.audit_logs'::regclass, 'created_at'), ('public.audit_logs'::regclass, 'old_data'),
     ('public.web_orders'::regclass, 'provider'));
  if v is distinct from 'audit_logs.action text|audit_logs.created_at timestamp with time zone|audit_logs.old_data jsonb|audit_logs.record_id uuid|audit_logs.table_name text|event_guest_days.attended_at timestamp with time zone|event_guest_days.check_in_code text|event_guest_days.checked_in_by uuid|event_ticket_options.is_active boolean|events.deleted_at timestamp with time zone|events.is_active boolean|invoice_items.event_days date[]|invoices.deleted_at timestamp with time zone|web_order_channels.event_id uuid|web_order_channels.key text|web_order_channels.mode text|web_order_channels.store_id uuid|web_order_channels.ticket_map jsonb|web_orders.channel text|web_orders.livemode boolean|web_orders.provider text|web_orders.review_reason text|web_orders.status text' then
    raise exception '415: the columns read are not as read on 9 Oct 2026 (%)', v; end if;
  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('event_check_in', 'event_set_guest_cancelled', 'event_save_guest', 'event_save', 'event_delete',
                       'event_ticket_line_check', 'event_summary', 'web_order_can_link', 'web_order_make_invoice',
                       'event_invoice_membership', 'web_order_close_refunded', 'web_order_tickets', 'web_order_dismiss')
     and p.oid::regprocedure::text not in ('event_check_in(uuid,date,boolean,text)', 'event_check_in(uuid,date,boolean,text,boolean)',
       'event_set_guest_cancelled(uuid,boolean,text)', 'event_save_guest(jsonb)', 'event_save(jsonb)', 'event_delete(uuid,text)',
       'event_ticket_line_check(jsonb,date,uuid,integer)', 'event_summary(uuid)', 'web_order_can_link(web_orders)',
       'web_order_make_invoice(uuid,uuid,boolean,boolean)', 'event_invoice_membership(uuid[])',
       'web_order_close_refunded(uuid,text,boolean)', 'web_order_tickets(text)', 'web_order_dismiss(uuid,text,boolean)');
  if v_bad is not null then
    raise exception '415: another function takes one of these names: %', v_bad; end if;
  -- The grants of the functions patched in place, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (v_fns);

  -- ── Install ────────────────────────────────────────────────────────────────
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;
  if v_check_in_new then
    drop function public.event_check_in(uuid, date, boolean, text);
    execute c_check_in_def;
    revoke all on function public.event_check_in(uuid, date, boolean, text, boolean) from public, anon;
    grant execute on function public.event_check_in(uuid, date, boolean, text, boolean) to authenticated, service_role;
  end if;
  if v_cancelled_new then
    -- The result changes from void to jsonb, which CREATE OR REPLACE cannot do.
    drop function public.event_set_guest_cancelled(uuid, boolean, text);
    execute c_cancelled_def;
    revoke all on function public.event_set_guest_cancelled(uuid, boolean, text) from public, anon;
    grant execute on function public.event_set_guest_cancelled(uuid, boolean, text) to authenticated, service_role;
  end if;
  if v_new_new then
    -- Rule 9: the Website orders tab's Close as refunded and Reopen.
    execute c_close_def;
    revoke all on function public.web_order_close_refunded(uuid, text, boolean) from public, anon;
    grant execute on function public.web_order_close_refunded(uuid, text, boolean) to authenticated, service_role;
    -- Rule 11: the edge function's alone, as web_order_sync and web_order_staff.
    execute c_tickets_def;
    revoke all on function public.web_order_tickets(text) from public, anon, authenticated;
    grant execute on function public.web_order_tickets(text) to service_role;
  end if;

  -- ── Installed exactly as tested ────────────────────────────────────────────
  v_bad := null;
  for r in select * from (values
    ('event_check_in(uuid,date,boolean,text,boolean)', c_check_in_after),
    ('event_set_guest_cancelled(uuid,boolean,text)', c_cancelled_after),
    ('event_save_guest(jsonb)', c_save_guest_after), ('event_save(jsonb)', c_save_after),
    ('event_delete(uuid,text)', c_delete_after), ('event_ticket_line_check(jsonb,date,uuid,integer)', c_line_check_after),
    ('event_summary(uuid)', c_summary_after), ('web_order_can_link(web_orders)', c_can_link_after),
    ('web_order_make_invoice(uuid,uuid,boolean,boolean)', c_make_invoice_after),
    ('event_invoice_membership(uuid[])', c_membership_after),
    ('web_order_close_refunded(uuid,text,boolean)', c_close_after), ('web_order_tickets(text)', c_tickets_after),
    ('web_order_dismiss(uuid,text,boolean)', c_dismiss_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v is distinct from r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || coalesce(v, 'missing')); end if;
  end loop;
  if v_bad is not null then
    raise exception '415: installed with md5s other than the tested ones: %', v_bad; end if;
  if to_regprocedure('public.event_check_in(uuid,date,boolean,text)') is not null then
    raise exception '415: the 4-argument event_check_in is still there'; end if;

  -- ── Grants, by the catalogue ───────────────────────────────────────────────
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (v_fns))
     is distinct from v_acl then
    raise exception '415: the grants of the functions patched in place changed'; end if;
  foreach v in array c_client loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = to_regprocedure('public.' || v) and a.grantee = 0) then
      raise exception '415: public.% is not executable by authenticated and service_role only', v; end if;
  end loop;
  foreach v in array c_internal loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '415: public.% is not the service role''s alone', v; end if;
  end loop;

  -- ── Behaviour, at the door (nothing is printed, no row remains) ────────────
  -- A made-up Owner and member of staff (@sig.invalid), a store, an event
  -- today and a free guest; always undone. Who acts is set by the claims
  -- alone (a single-claim setting would take precedence), and put back after.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  begin
    insert into auth.users (id, email) values (gen_random_uuid(), '415-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '415-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into auth.users (id, email) values (gen_random_uuid(), '415-check-admin-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_admin;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '415 check ' || x.role, u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff'), (v_admin, 'admin')) x(id, role) on x.id = u.id;
    insert into public.stores (name, code, country_code)
    values ('415 check ' || v_owner, '415C' || upper(substr(md5(v_owner::text), 1, 8)), 'SG') returning id into v_store;
    insert into public.user_store_assignments (user_id, store_id) values (v_staff, v_store), (v_admin, v_store);

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    v_event := public.event_save(jsonb_build_object('name', '415 check',
      'days', jsonb_build_array(jsonb_build_object('day', public.sg_today())),
      'store_ids', jsonb_build_array(v_store),
      'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 5))));
    v_guest := (public.event_save_guest(jsonb_build_object('event_id', v_event, 'name', '415 Guest',
      'days', jsonb_build_array(public.sg_today())))->>'guest_id')::uuid;

    -- The member of staff checks the guest in with a code.
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_out := public.event_check_in(v_guest, public.sg_today(), true, ' W12 ');
    execute 'reset role';
    if not (v_out->>'changed')::boolean or (v_out->>'already_in')::boolean or v_out->>'check_in_code' is distinct from 'W12'
       or v_out->>'checked_in_by' is distinct from v_staff::text or v_out->>'checked_in_by_name' is distinct from '415 check staff' then
      raise exception '415: a check-in did not answer as tested (%)', v_out; end if;
    -- A second device: no code, no change.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    v_out := public.event_check_in(v_guest, public.sg_today(), true, null);
    if not (v_out->>'already_in')::boolean or (v_out->>'changed')::boolean or v_out->>'check_in_code' is distinct from 'W12'
       or v_out->>'checked_in_by' is distinct from v_staff::text then
      raise exception '415: a second check-in changed the first (%)', v_out; end if;
    -- Save code changes the code only.
    v_out := public.event_check_in(v_guest, public.sg_today(), true, 'W13', true);
    if v_out->>'check_in_code' is distinct from 'W13' or v_out->>'checked_in_by' is distinct from v_staff::text then
      raise exception '415: Save code did not change the code alone (%)', v_out; end if;
    -- Cancelling a guest who checked in is refused.
    begin
      perform public.event_set_guest_cancelled(v_guest, true, '415 check');
      v_err := null;
    exception when others then v_err := sqlerrm;
    end;
    if v_err is null or v_err !~ 'already checked in' then
      raise exception '415: a guest who checked in was cancelled (%)', coalesce(v_err, 'no refusal'); end if;
    -- Undo, and the three changes are in the audit log.
    v_out := public.event_check_in(v_guest, public.sg_today(), false);
    if v_out->>'attended_at' is not null or v_out->>'check_in_code' is not null or not (v_out->>'changed')::boolean then
      raise exception '415: Undo did not clear the check-in (%)', v_out; end if;
    if (select string_agg(a.action, ',' order by a.action) from public.audit_logs a
         where a.table_name = 'event_guest_days' and a.record_id = v_guest)
       is distinct from 'event_check_in_code_changed,event_check_in_undone,event_checked_in' then
      raise exception '415: the check-in, the code change and the undo are not all in the audit log'; end if;
    -- A login that is not staff is refused before anything is read.
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.event_check_in(v_guest, public.sg_today(), true);
      raise exception '415: a login that is not staff checked a guest in';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';

    -- Rule 11: a made-up channel says which of its passes is on sale, and
    -- follows the ticket's On sale; a channel it does not know is refused.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    insert into public.payment_methods (name, is_active) values ('415 check ' || v_owner, true) returning id into v_pm;
    v_channel := '415-check-' || v_owner;
    insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id, mode)
    select v_channel, v_event, jsonb_build_object('pass', jsonb_build_object('option_id', o.id),
                                                  'gone', jsonb_build_object('option_id', gen_random_uuid())),
           v_store, v_owner, v_pm, 'off'
      from public.event_ticket_options o where o.event_id = v_event;
    if public.web_order_tickets(v_channel) is distinct from '{"status": "ok", "tickets": {"pass": true, "gone": false}}'::jsonb
       or public.web_order_tickets(v_channel || '-none') is distinct from '{"status": "refused", "tickets": {}}'::jsonb then
      raise exception '415: web_order_tickets did not answer as tested (%)', public.web_order_tickets(v_channel); end if;
    update public.event_ticket_options set is_active = false where event_id = v_event;
    if public.web_order_tickets(v_channel)->'tickets'->'pass' is distinct from 'false'::jsonb then
      raise exception '415: a ticket taken off sale is still on sale for the website'; end if;

    -- Rule 9: a made-up website order waiting for its invoice. Staff may
    -- not close it; the Owner closes it as refunded, then reopens it.
    insert into public.web_orders (channel, stripe_session_id, livemode, status, ticket, quantity, unit_amount_cents,
                                   amount_total_cents, early_bird, buyer_name, checkout_opened_at, paid_at)
    values (v_channel, 'cs_live_415check' || replace(v_owner::text, '-', ''), true, 'needs_review', 'pass', 1, 500, 500,
            false, '415 Buyer', now(), now())
    returning id into v_order;
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.web_order_close_refunded(v_order, '415 check');
      raise exception '415: a member of staff closed a website order';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
    -- Nor may an Admin: an Owner or Manager only.
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.web_order_close_refunded(v_order, '415 check');
      raise exception '415: an Admin closed a website order';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_out := public.web_order_close_refunded(v_order, ' Refunded in Stripe ');
    execute 'reset role';
    if v_out->>'status' is distinct from 'dismissed'
       or v_out->>'review_reason' is distinct from 'Refunded outside the app: Refunded in Stripe' then
      raise exception '415: an order was not closed as refunded as tested (%)', v_out; end if;
    v_out := public.web_order_close_refunded(v_order, 'Closed by mistake', false);
    if v_out->>'status' is distinct from 'needs_review' then
      raise exception '415: an order closed as refunded was not reopened (%)', v_out; end if;
    if (select string_agg(a.action, ',' order by a.action) from public.audit_logs a
         where a.table_name = 'web_orders' and a.record_id = v_order)
       is distinct from 'web_order_closed_refunded,web_order_reopened' then
      raise exception '415: closing and reopening the order are not both in the audit log'; end if;
    -- A staff-link payment refused while the channel was off: closed, the
    -- staff link's Restore does not bring it back; Reopen makes it refused
    -- again, as it was, so it is still only linked to an invoice made by hand.
    insert into public.web_orders (channel, stripe_session_id, livemode, status, review_reason, ticket, quantity,
                                   unit_amount_cents, amount_total_cents, early_bird, buyer_name, checkout_opened_at,
                                   paid_at, provider, door_method, paid_on)
    values (v_channel, 'OFF-415CHECK-' || replace(v_owner::text, '-', ''), true, 'refused', 'The website channel is off',
            'pass', 1, 500, 500, false, '415 Door Buyer', now(), now(), 'door', 'cash', public.sg_today())
    returning id into v_door;
    execute 'set local role authenticated';
    v_out := public.web_order_close_refunded(v_door, 'Refunded in cash');
    begin
      perform public.web_order_dismiss(v_door, null, false);
      v_err := null;
    exception when others then v_err := sqlerrm;
    end;
    v_out := public.web_order_close_refunded(v_door, 'Closed by mistake', false);
    execute 'reset role';
    if v_err is distinct from 'This order was closed as refunded. Use Reopen instead.' then
      raise exception '415: Restore brought back an order closed as refunded (%)', coalesce(v_err, 'no refusal'); end if;
    if v_out->>'status' is distinct from 'refused' or v_out->>'review_reason' is distinct from 'The website channel is off' then
      raise exception '415: a payment refused while off was not put back as it was (%)', v_out; end if;
    raise exception using errcode = 'P0415', message = '415: check done, undone';
  exception when sqlstate 'P0415' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
