-- 548_class_page_for_the_four_class_vouchers.sql
--
-- A "CLASS" PAGE: THE FOUR CLASS VOUCHERS MOVE OFF THE VOUCHERS PAGE, WITH THEIR SCHEDULES, WHO BOUGHT
-- THEM, THE DATE EACH SEAT CHOSE AND WHO ATTENDED
--
--   The Owner, 27 Nov 2026: "Can you help me create another page which is class? The 4 voucher for class
--   should go to the class page." Nothing about how a class is sold, priced, paid or earns commission
--   changes: a class stays a voucher line on an invoice. This migration adds tables and functions and
--   changes NO existing function (the 1,471 functions of production after 549 are as they were; the
--   migration checks it). It makes ONE change to an existing table: two triggers on public.invoice_items
--   (class_line_voucher_changed, class_line_removed; see "A LINE CHANGED OR REMOVED" below). No column,
--   policy, grant or other trigger of any existing table changes. It pins the function fingerprint of production after 549:
--   da952c4a3e002f6fc20da3260b1cff95/1471; after: 96989a5a4588db9a5b1e17d7d828c61f/1481. It refuses on any other base and
--   changes nothing. (The number 548 is this file's name and its errors' prefix.)
--
-- THE OWNER'S ANSWERS (27 Nov 2026; the data contract)
--
--   1. The classes are four vouchers, found by vouchers.code (all voucher_kind normal, unlimited, no
--      expiry, reward-eligible on production):
--        EmiLymphatic  "Emi Foundation Lymphatic Zoom Class"  S$799   -> "Lymphatic Foundation Workshop 2027"
--        AdvancedZoom  "Emi Advanced Lymphatic Zoom Class"    S$1,441 -> "Lymphatic Advanced Workshop 2027"
--        KPopClass     "K Pop Facial Class"                   S$676   -> "Korea No.1 Skin Care Workshop"
--        L-C           "Lymphatic Class"                      S$399   keeps its name (one in-person day of
--                                                                      the Foundation class)
--      Prices stay. The renames are data changes in this file, in the Audit Log as every change to a
--      voucher is (trg_audit_voucher_change: voucher_updated, the old and the new name).
--   2. Off the Vouchers page: the four show on the new Class page. They are marked by a class table keyed
--      by voucher (class_vouchers), not by name.
--   3. The invoice form's item type gets a "Class" category listing them; like "Consignment" it is only
--      the page: the saved line stays a voucher line, priced, paid and paying commission as before, and
--      "Voucher" stops listing them.
--   4. The page: each class's details from its poster; who bought it, read from live invoices (a line's
--      quantity = seats; cancelled, refunded or deleted invoices do not count, nor do units refunded by
--      line); attendance per session, ticked by staff. The skin care workshop's seat chooses ONE date, at
--      most 6 seats per date, enforced here. The Lymphatic Class's seat chooses ONE in-person day, from a
--      date list on that class that Owners and Managers keep on the page; seeded EMPTY.
--   5. The skin care set (9 products) is handled separately: no stock moves with the class.
--   6. Who: all staff see the page and record attendance and chosen dates for invoices of the stores they
--      have access to (the app's normal store access, user_has_store_access, as the Invoices page and its
--      row rules: an Owner or Admin has every store, a Manager and Staff their assigned stores). Only
--      Owners and Managers change dates, schedules or class details, enforced here.
--   7. Menu: "Class" near Vouchers, route /classes.
--
-- HOW IT IS BUILT (the choices made, for the Owner to see)
--
--   * Tables (row-level security on, a login reads, only these functions write):
--       class_vouchers      the voucher is the key; seat_mode ('all_sessions': a seat attends every
--                           session, Foundation and Advanced; 'choose_date': a seat chooses one date,
--                           skin care and the Lymphatic Class), capacity_per_date (6 for skin care, none
--                           for the Lymphatic Class), a summary and the poster's details (jsonb).
--       class_sessions      a class's dates: title, kind (lesson, revision, graduation, class_day), date,
--                           times, Zoom or in person, venue, must-attend. For a choose-a-date class they
--                           are the dates a seat may choose from.
--       class_seat_dates    the date a seat chose: (invoice line, seat number) -> session.
--       class_attendance    who attended: (session, invoice line, seat number); a row is a tick.
--   * A seat is one unit of a voucher line: seats 1..n of line quantity n, less the units its refunds
--     paid back (class_line_units: a line's refunds, from invoice_refunds.outcome, over its discounted
--     value, whole units, as refund_invoice_recorded counts a line's refunded amount). The invoice must be
--     live: not deleted, and unpaid, part-paid, paid, completed FOC, or with a cancellation or refund
--     requested; a draft, a cancelled and a refunded invoice give no seats. A refunded or cancelled seat's
--     chosen date and ticks stay on record but do not count (the capacity frees at once).
--   * A class voucher given free as a reward, or inside a promotion or a bundle, is not a line of an
--     invoice: it is not read here (only voucher lines of live invoices are).
--   * The capacity is a trigger on class_seat_dates: it locks the session, counts the live seats that
--     chose it, and refuses a seventh with check_violation ("That date is full ..."), whoever writes.
--   * Buyers: name and phone of the invoice's customer (as the Invoices page shows them to staff, M13),
--     the invoice number, status, date and store. An Inventory Manager sees no page ("An Inventory
--     Manager works with stock only", 540).
--   * Seeded from the posters: Foundation 12 sessions + graduation, Advanced 12 + graduation, skin care 12
--     dates (max 6), the Lymphatic Class none.
--   * Old invoices keep their printed names: a line's item_name_snapshot is what an invoice prints
--     (invoice_display_names falls back to the voucher's NAME only where a line has no snapshot). So
--     before renaming, this freezes the old name into every line of these vouchers that has none (the
--     lines' ids are written to one Audit Log entry per voucher, class_lines_name_frozen, so the UNDO
--     takes exactly those back). Where the snapshots are all there (production's backfill, if it was run),
--     it freezes nothing. Only the three RENAMED vouchers are frozen and checked (Foundation, Advanced,
--     skin care). The Lymphatic Class keeps its name, so its lines that have no printed name of their own
--     are left exactly as they are: they print the voucher's name, which 548 does not change. A later
--     rename of it (Edit voucher on the Class page) would show on those lines, as on any old line of any
--     voucher without a printed name. That is the narrowing chosen; the stricter alternative (freezing the
--     Lymphatic Class's lines too) was not taken.
--   * Seat dates and ticks go with their invoice line (ON DELETE CASCADE): a line removed by an
--     invoice edit takes its seats with it (a line that gave vouchers cannot be removed anyway).
--
-- WHAT THIS DOES
--
--   Tables: class_vouchers, class_sessions, class_seat_dates, class_attendance.
--   New functions, for the page (signed-in; each refuses non-staff, 42501):
--     class_page_data()                         classes, sessions with the seats taken, the seats the
--                                               caller may see, whether the caller may edit
--     class_choose_date(item, seat, session)    a seat's one date (null clears it)         active staff
--     class_set_attendance(session, item, seat, attended)                                  active staff
--     class_save_session(voucher, session, data)  add / change a date                      Owner, Manager
--     class_remove_session(session)             remove a date nobody chose or attended      Owner, Manager
--     class_save_details(voucher, data)         summary, details, capacity per date        Owner, Manager
--   Internal (service_role only): class_line_units(uuid), class_live_seats(uuid), the capacity trigger
--     function trg_class_seat_date_capacity(), and trg_class_line_changed() (the two invoice_items triggers).
--   Triggers on public.invoice_items (the one change to an existing table): see below.
--   Data: the four vouchers marked and renamed; the poster schedules; old lines' names frozen.
--   Nothing else: no existing function, column, policy or grant is changed.
--
-- A LINE CHANGED OR REMOVED (the audit's finding on v2; the one change to an existing table)
--
--   correct_invoice keeps a line's id and may update its voucher_id (a skin care line corrected to the
--   Lymphatic Class or to Foundation, paid or not). The line's seat dates and ticks, which point at the OLD
--   class's dates, would stay: counted in the old date's "taken" count, listed under the new class with a
--   date and a tick that nobody can clear. And removing a class line from an unpaid invoice let ON DELETE
--   CASCADE take its dates and ticks without a trace. So, on public.invoice_items:
--     class_line_voucher_changed   AFTER UPDATE OF voucher_id, each row, when the voucher_id changed: deletes
--                                  the line's class_seat_dates and class_attendance rows and, if there were
--                                  any, writes ONE Audit Log entry (class_seats_cleared: the old voucher, the
--                                  dates and the ticks that went).
--     class_line_removed           BEFORE DELETE, each row, for a voucher line: writes the same kind of entry
--                                  when the line has class rows (the cascade then removes them); deletes
--                                  nothing itself and returns the old row. Its name sorts before the other
--                                  BEFORE DELETE triggers (invoice_item_exchange_hold, invoice_item_late_fee_
--                                  guard: each returns the row or raises, none returns NULL), so a delete they
--                                  refuse is rolled back with this entry.
--   Both call trg_class_line_changed() (owner rights, search_path public, pg_temp, not callable by a login).
--   Creating them takes a short lock on invoice_items (the 5 s lock_timeout applies).
--
-- OTHER RULES OF v3
--
--   * class_remove_session: a date is refused while a LIVE seat of its class chose it (the old sentence) or
--     while anyone was ticked at it; the dates only cancelled or refunded seats chose go with it, listed in
--     the class_session_removed entry. (Before, one cancelled seat's date made it impossible to remove.)
--   * The capacity cannot be raced: class_save_details locks the class's dates before it counts, and the
--     capacity trigger reads the limit in its own statement AFTER it has locked the date, so each sees what
--     the other committed (checked with two real connections, scripts/classes/tests/race548.py).
--
-- WHAT STAYS
--
--   * Everyone (Staff, Manager, Owner, Admin) sees buyers, chooses dates and ticks attendance only for the
--     invoices of the stores they have access to; an Owner or Admin has every store. Everyone sees the
--     number of seats taken per date across all stores (a count, no customer), so a full date is not offered.
--   * The four vouchers are not listed on the Vouchers page: their Edit voucher and Prices are on the Class
--     page (the Vouchers page's own window and store-price editor, for the same people).
--   * An Admin sees the page and ticks like staff, but does not edit dates or details (the Owner-level
--     routes exclude Admin, as in M13).
--   * A reopened invoice's seats count again with the date they chose, even if that date has since
--     filled (anyone with access to the invoice's store clears one by hand: class_choose_date with no
--     session). A ticked seat's date can be cleared only after its tick is removed.
--
-- SAFETY: one DO block after the lock timeout, so atomic however it is run. Every guard is checked
--   before anything is written. A database where 548 is in says so and changes nothing; one partly there
--   refuses. After installing, every existing function's text is checked unchanged, every new
--   function's md5 and search path, the tables' grants and rules, the seed, the renames, the prices, and
--   that invoice_items has exactly its old triggers (each as before) plus the two.
--
-- GO-LIVE: after 549 (production's head 20261128031702 when this was pinned; the order on production is 547, 549, then 548). Pages ship FIRST (src/pages/ClassPage.tsx, VouchersPage.tsx, InvoicesPage.tsx,
--   AppLayout.tsx, App.tsx): until 548 is in they read class_vouchers and get nothing, so the Vouchers
--   page lists all vouchers and the invoice form has no Class category (a failed read is shown as no
--   class vouchers); the Class page says it is not ready. Then this file; then check the Class page with
--   an Owner login.
--
-- UNDO: scripts/classes/undo-548.sql. It refuses once staff recorded a seat's date or a tick (decide with
--   the Owner what to keep first), puts the names back, takes back the frozen snapshots it made, drops
--   the two invoice_items triggers, the tables and the functions. Run it BEFORE any older UNDO.
--
-- TESTS: scripts/classes/tests/class-page-548.sql (the database, with real sign-ins); the pages:
--   scripts/classes/tests/class-page.test.mjs, vouchers-page-without-classes.test.mjs and class-line-browser.mjs
--   (the invoice form's Class category, in a real browser). scripts/classes/gen548.py rebuilds the pins above
--   after any change to a function text; scripts/classes/mutate548.py changes one rule at a time and checks the
--   suite notices. Because the new functions call 540's inventory_manager_guard (which 540's UNDO refuses while
--   any other function uses it), every older suite that runs an UNDO of 547, 540 or older first runs undo-548
--   where 548 is in (the t548_in block, as 547's t547_in).
--
-- NEW (AFTER; md5 of pg_get_functiondef):
--   class_line_units(uuid)                                                 7b1a847e37dd57acff2e0ecafda42db5
--   class_live_seats(uuid)                                                 1e1723f97d880bd3308c94b92502e490
--   trg_class_seat_date_capacity()                                         31219f6139047f835e32418052fc74de
--   class_page_data()                                                      5727df5de4fe1d7b7ecbad7b07a85532
--   class_choose_date(uuid,integer,uuid)                                   cc03742856ee4229893c6018ee06ed1c
--   class_set_attendance(uuid,uuid,integer,boolean)                        50837bc66f6696841751c19df6681fed
--   class_save_session(uuid,uuid,jsonb)                                    e0c6455dd0ba1edf5804659b42f6a6a2
--   class_remove_session(uuid)                                             5585fda03ea601809138c5193671e872
--   class_save_details(uuid,jsonb)                                         60e826b227ab3ccc98e24d5c684b7a25
--   trg_class_line_changed()                                               68bb63c4cf5a0dc44a7f7890898d7ec6

set lock_timeout = '5s';

do $mig$
declare
  c_fp_before constant text := 'da952c4a3e002f6fc20da3260b1cff95/1471';
  c_fp_after constant text := '96989a5a4588db9a5b1e17d7d828c61f/1481';
  c_new constant text[][] := array[
    ['class_line_units(uuid)', '7b1a847e37dd57acff2e0ecafda42db5'],
    ['class_live_seats(uuid)', '1e1723f97d880bd3308c94b92502e490'],
    ['trg_class_seat_date_capacity()', '31219f6139047f835e32418052fc74de'],
    ['class_page_data()', '5727df5de4fe1d7b7ecbad7b07a85532'],
    ['class_choose_date(uuid,integer,uuid)', 'cc03742856ee4229893c6018ee06ed1c'],
    ['class_set_attendance(uuid,uuid,integer,boolean)', '50837bc66f6696841751c19df6681fed'],
    ['class_save_session(uuid,uuid,jsonb)', 'e0c6455dd0ba1edf5804659b42f6a6a2'],
    ['class_remove_session(uuid)', '5585fda03ea601809138c5193671e872'],
    ['class_save_details(uuid,jsonb)', '60e826b227ab3ccc98e24d5c684b7a25'],
    ['trg_class_line_changed()', '68bb63c4cf5a0dc44a7f7890898d7ec6']
  ];
  c_codes constant text[][] := array[   -- code, old name, new name, price, seat mode, capacity, sort
    ['EmiLymphatic', 'Emi Foundation Lymphatic Zoom Class', 'Lymphatic Foundation Workshop 2027', '799.00', 'all_sessions', '', '1'],
    ['AdvancedZoom', 'Emi Advanced Lymphatic Zoom Class', 'Lymphatic Advanced Workshop 2027', '1441.00', 'all_sessions', '', '2'],
    ['KPopClass', 'K Pop Facial Class', 'Korea No.1 Skin Care Workshop', '676.00', 'choose_date', '6', '3'],
    ['L-C', 'Lymphatic Class', 'Lymphatic Class', '399.00', 'choose_date', '', '4']];
  v_path text := current_setting('search_path');
  v_fp text; v_md5 text; v_there integer := 0; v_tables integer; k integer; v_id uuid; v_ids uuid[];
  v_foundation uuid; v_advanced uuid; v_skin uuid; v_lc uuid; v_n integer; v_frozen uuid[];
begin
  perform set_config('search_path', 'public', true);

  -- 0. Already in?
  select count(*) into v_tables from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'
     and relname in ('class_vouchers', 'class_sessions', 'class_seat_dates', 'class_attendance');
  for k in 1 .. array_length(c_new, 1) loop
    if to_regprocedure('public.' || c_new[k][1]) is not null then
      v_there := v_there + 1;
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_new[k][1]))) <> c_new[k][2] then
        raise exception '548: public.% already exists with another text. Nothing was changed.', c_new[k][1]; end if;
    end if;
  end loop;
  select md5(string_agg(md5(pg_get_functiondef(oid)), '' order by oid::regprocedure::text)) || '/' || count(*) into v_fp
    from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f';
  if v_tables = 4 and v_there = array_length(c_new, 1) and v_fp = c_fp_after then
    raise notice '548 is already in on this database; nothing was changed.';
    perform set_config('search_path', v_path, true);
    return;
  end if;
  if v_tables > 0 or v_there > 0 then
    raise exception '548 is partly in on this database (% of 4 tables, % of % functions). Nothing was changed.',
      v_tables, v_there, array_length(c_new, 1); end if;

  -- 1. The base: production after 549, and the four vouchers as the Owner described them.
  if v_fp <> c_fp_before then
    raise exception '548: the functions are not the ones this was made from (fingerprint %). Is 549 in? Nothing was changed.', v_fp; end if;
  for k in 1 .. array_length(c_codes, 1) loop
    select count(*) into v_n from public.vouchers where code = c_codes[k][1] and deleted_at is null;
    if v_n <> 1 then
      raise exception '548: expected exactly one live voucher with code % and found %. Nothing was changed.', c_codes[k][1], v_n; end if;
    if not exists (select 1 from public.vouchers v
                    where v.code = c_codes[k][1] and v.deleted_at is null
                      and v.name = c_codes[k][2] and v.selling_price = c_codes[k][4]::numeric
                      and v.voucher_kind = 'normal' and v.qty_type = 'unlimited') then
      raise exception '548: voucher % is not as the Owner described it on 27 Nov 2026 (name "%", S$%, normal, unlimited). Nothing was changed.',
        c_codes[k][1], c_codes[k][2], c_codes[k][4]; end if;
  end loop;
  select id into v_foundation from public.vouchers where code = 'EmiLymphatic' and deleted_at is null;
  select id into v_advanced from public.vouchers where code = 'AdvancedZoom' and deleted_at is null;
  select id into v_skin from public.vouchers where code = 'KPopClass' and deleted_at is null;
  select id into v_lc from public.vouchers where code = 'L-C' and deleted_at is null;

  -- Every existing function, before: to prove none changed.
  create temp table fn_before_548 on commit drop as
    select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as def
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
  create temp table tg_before_548 on commit drop as
    select t.tgname, pg_get_triggerdef(t.oid) as def from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and not t.tgisinternal;
  create temp table price_before_548 on commit drop as
    select v.id, v.selling_price, v.voucher_kind, v.qty_type, v.is_active, v.valid_from, v.valid_until, v.reward_eligible,
           (select md5(coalesce(string_agg(s.store_id::text || ':' || coalesce(s.selling_price::text, '') || ':' || s.available_at_store::text,
                                           ',' order by s.store_id), ''))
              from public.voucher_store_prices s where s.voucher_id = v.id and s.deleted_at is null) as store_prices
      from public.vouchers v where v.code in ('EmiLymphatic', 'AdvancedZoom', 'KPopClass', 'L-C') and v.deleted_at is null;

  -- 2. Tables.
  execute $ddl$
    create table public.class_vouchers (
      voucher_id uuid primary key references public.vouchers(id),
      seat_mode text not null check (seat_mode in ('all_sessions', 'choose_date')),
      capacity_per_date integer check (capacity_per_date > 0),
      sort_order integer not null default 0,
      summary text,
      details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      updated_by uuid references public.profiles(id),
      constraint class_vouchers_capacity_for_choose_date check (capacity_per_date is null or seat_mode = 'choose_date'));
    comment on table public.class_vouchers is
      '548: the vouchers that are classes. They show on the Class page, not on the Vouchers page; on an invoice they are still voucher lines.';
    create table public.class_sessions (
      id uuid primary key default gen_random_uuid(),
      voucher_id uuid not null references public.class_vouchers(voucher_id),
      seq integer not null check (seq > 0),
      title text not null check (btrim(title) <> ''),
      kind text not null check (kind in ('lesson', 'revision', 'graduation', 'class_day')),
      session_date date not null,
      starts_at time,
      ends_at time,
      mode text not null check (mode in ('in_person', 'zoom')),
      venue text,
      must_attend boolean not null default false,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      updated_by uuid references public.profiles(id),
      constraint class_sessions_one_per_day unique (voucher_id, session_date),
      constraint class_sessions_times check (starts_at is null or ends_at is null or ends_at > starts_at));
    create index class_sessions_by_class on public.class_sessions (voucher_id, session_date);
    comment on table public.class_sessions is
      '548: a class''s dates (sessions). For a choose-a-date class they are the dates a seat may choose from.';
    create table public.class_seat_dates (
      invoice_item_id uuid not null references public.invoice_items(id) on delete cascade,
      seat_no integer not null check (seat_no > 0),
      session_id uuid not null references public.class_sessions(id),
      chosen_by uuid references public.profiles(id),
      chosen_at timestamptz not null default now(),
      primary key (invoice_item_id, seat_no));
    create index class_seat_dates_by_session on public.class_seat_dates (session_id);
    comment on table public.class_seat_dates is
      '548: the one date a seat of a choose-a-date class chose (seat = a unit of a voucher line). At most capacity_per_date live seats per date.';
    create table public.class_attendance (
      session_id uuid not null references public.class_sessions(id),
      invoice_item_id uuid not null references public.invoice_items(id) on delete cascade,
      seat_no integer not null check (seat_no > 0),
      marked_by uuid references public.profiles(id),
      marked_at timestamptz not null default now(),
      primary key (session_id, invoice_item_id, seat_no));
    create index class_attendance_by_seat on public.class_attendance (invoice_item_id, seat_no);
    comment on table public.class_attendance is
      '548: a row = the seat attended the session (ticked by staff).';
    alter table public.class_vouchers enable row level security;
    alter table public.class_sessions enable row level security;
    alter table public.class_seat_dates enable row level security;
    alter table public.class_attendance enable row level security;
    create policy class_vouchers_read on public.class_vouchers for select to authenticated
      using ((select public.current_user_role()) is not null);
    create policy class_sessions_read on public.class_sessions for select to authenticated
      using ((select public.current_user_role()) is not null);
    create policy class_seat_dates_read on public.class_seat_dates for select to authenticated
      using ((select public.current_user_role()) is not null
             and (select public.current_user_role()) is distinct from 'inventory_manager'::public.user_role
             and exists (select 1 from public.invoice_items it join public.invoices i on i.id = it.invoice_id
                          where it.id = class_seat_dates.invoice_item_id
                            and ((select public.is_owner_or_admin()) or i.store_id = any ((select public.current_user_store_ids())::uuid[]))));
    create policy class_attendance_read on public.class_attendance for select to authenticated
      using ((select public.current_user_role()) is not null
             and (select public.current_user_role()) is distinct from 'inventory_manager'::public.user_role
             and exists (select 1 from public.invoice_items it join public.invoices i on i.id = it.invoice_id
                          where it.id = class_attendance.invoice_item_id
                            and ((select public.is_owner_or_admin()) or i.store_id = any ((select public.current_user_store_ids())::uuid[]))));
    revoke all on table public.class_vouchers, public.class_sessions, public.class_seat_dates, public.class_attendance
      from public, anon, authenticated;
    grant select on table public.class_vouchers, public.class_sessions, public.class_seat_dates, public.class_attendance to authenticated;
    grant all on table public.class_vouchers, public.class_sessions, public.class_seat_dates, public.class_attendance to service_role;
  $ddl$;

  -- 3. Internal functions.
  execute $ddl$
    create function public.class_line_units(p_item_id uuid)
    returns integer
    language sql
    stable
    security definer
    set search_path = public, pg_temp
    as $fn$
      -- 548: the live seats of a voucher line: its quantity, less the whole units its refunds paid
      -- back (the refunded amount of the line over its discounted value, as refund_invoice_recorded
      -- counts a line's refunds: those since the invoice was last reopened). 0 for a line of an
      -- invoice that is deleted, a draft, cancelled or refunded. Internal.
      select case
               when i.deleted_at is null
                and i.status in ('unpaid', 'partially_paid', 'paid', 'completed_foc', 'cancellation_requested', 'refund_requested')
               then greatest(it.quantity - case when x.paid <= 0 then 0
                                                else least(it.quantity, floor(round(x.refunded * it.quantity / x.paid, 6)))::integer end, 0)
               else 0 end
        from public.invoice_items it
        join public.invoices i on i.id = it.invoice_id
        cross join lateral (
          select coalesce(public.invoice_discounted_line_value(it.id), 0) as paid,
                 coalesce((select sum((e->>'amount')::numeric)
                             from public.invoice_refunds r, jsonb_array_elements(coalesce(r.outcome->'lines', '[]'::jsonb)) e
                            where r.invoice_id = i.id
                              and (i.reopened_at is null or r.created_at > i.reopened_at)
                              and e->>'invoice_item_id' = it.id::text), 0) as refunded) x
       where it.id = p_item_id and it.line_kind = 'voucher'
    $fn$;
    create function public.class_live_seats(p_voucher_id uuid default null)
    returns table(voucher_id uuid, invoice_item_id uuid, seat_no integer, invoice_id uuid, store_id uuid, customer_id uuid)
    language sql
    stable
    security definer
    set search_path = public, pg_temp
    as $fn$
      -- 548: every live seat of the class vouchers (or of one): seat n of a voucher line of quantity
      -- units, for n up to class_line_units. Internal.
      select it.voucher_id, it.id, g.n, i.id, i.store_id, i.customer_id
        from public.class_vouchers c
        join public.invoice_items it on it.voucher_id = c.voucher_id and it.line_kind = 'voucher'
        join public.invoices i on i.id = it.invoice_id
        cross join lateral (select public.class_line_units(it.id) as u) x
        cross join lateral generate_series(1, x.u) g(n)
       where (p_voucher_id is null or c.voucher_id = p_voucher_id)
    $fn$;
    create function public.trg_class_seat_date_capacity()
    returns trigger
    language plpgsql
    security definer
    set search_path = public, pg_temp
    as $fn$
    declare v_vid uuid; v_cap integer; v_mode text; v_line_voucher uuid; v_taken integer;
    begin
      -- 548: the one date of a seat, at most capacity_per_date live seats per date, whoever writes.
      -- The session row is locked, so two seats choosing the last place at once are told one after
      -- the other.
      select s.voucher_id into v_vid from public.class_sessions s where s.id = new.session_id for update of s;
      if v_vid is null then raise exception 'That date does not exist.'; end if;
      -- The limit is read in a statement of its own, after the lock: a limit another login committed while
      -- this waited is seen (class_save_details locks the dates before it counts, so the two cannot cross).
      select c.capacity_per_date, c.seat_mode into v_cap, v_mode from public.class_vouchers c where c.voucher_id = v_vid;
      if v_mode <> 'choose_date' then
        raise exception 'This class has no date to choose: every seat attends every session.'; end if;
      select it.voucher_id into v_line_voucher from public.invoice_items it where it.id = new.invoice_item_id;
      if v_line_voucher is distinct from v_vid then
        raise exception 'That date belongs to another class than the one this invoice line bought.'; end if;
      if new.seat_no > coalesce(public.class_line_units(new.invoice_item_id), 0) then
        raise exception 'That seat is not on a live invoice (it was cancelled, refunded or never sold).'; end if;
      if v_cap is not null then
        select count(*) into v_taken
          from public.class_seat_dates d
          join public.class_live_seats(v_vid) ls on ls.invoice_item_id = d.invoice_item_id and ls.seat_no = d.seat_no
         where d.session_id = new.session_id
           and not (d.invoice_item_id = new.invoice_item_id and d.seat_no = new.seat_no);
        if v_taken >= v_cap then
          raise exception 'That date is full: % of % seats are taken.', v_taken, v_cap using errcode = '23514'; end if;
      end if;
      return new;
    end
    $fn$;
    create trigger class_seat_date_capacity before insert or update of session_id, invoice_item_id, seat_no
      on public.class_seat_dates for each row execute function public.trg_class_seat_date_capacity();
    create function public.trg_class_line_changed()
    returns trigger
    language plpgsql
    security definer
    set search_path = public, pg_temp
    as $fn$
    declare v_dates jsonb; v_ticks jsonb; v_store uuid;
    begin
      -- 548 v3 (the audit's finding): a voucher line whose voucher changed (correct_invoice keeps the line's id)
      -- or that is removed. Its seats' dates and ticks belong to the old class: on a change they are deleted
      -- here; on a removal the table's own ON DELETE CASCADE deletes them. Either way, if there were any, one
      -- Audit Log entry says which. Nothing is written for a line with no class rows. Internal.
      select coalesce(jsonb_agg(jsonb_build_object('seat_no', d.seat_no, 'session_id', d.session_id) order by d.seat_no), '[]'::jsonb)
        into v_dates from public.class_seat_dates d where d.invoice_item_id = old.id;
      select coalesce(jsonb_agg(jsonb_build_object('seat_no', a.seat_no, 'session_id', a.session_id) order by a.seat_no, a.session_id), '[]'::jsonb)
        into v_ticks from public.class_attendance a where a.invoice_item_id = old.id;
      if jsonb_array_length(v_dates) = 0 and jsonb_array_length(v_ticks) = 0 then
        if tg_op = 'DELETE' then return old; end if;
        return new;
      end if;
      select i.store_id into v_store from public.invoices i where i.id = old.invoice_id;
      if tg_op = 'UPDATE' then
        delete from public.class_attendance where invoice_item_id = old.id;
        delete from public.class_seat_dates where invoice_item_id = old.id;
        perform public.write_audit_ex('invoice_items', old.id, 'class_seats_cleared',
          jsonb_build_object('voucher_id', old.voucher_id, 'seat_dates', v_dates, 'ticks', v_ticks),
          jsonb_build_object('voucher_id', new.voucher_id), 'classes',
          'The line''s class was changed, so the dates its seats chose and their ticks no longer apply.', v_store);
        return new;
      end if;
      perform public.write_audit_ex('invoice_items', old.id, 'class_seats_cleared',
        jsonb_build_object('voucher_id', old.voucher_id, 'seat_dates', v_dates, 'ticks', v_ticks),
        jsonb_build_object('removed', true), 'classes',
        'The invoice line was removed with the dates its seats chose and their ticks.', v_store);
      return old;
    end
    $fn$;
    create trigger class_line_voucher_changed after update of voucher_id on public.invoice_items
      for each row when (old.voucher_id is distinct from new.voucher_id) execute function public.trg_class_line_changed();
    create trigger class_line_removed before delete on public.invoice_items
      for each row when (old.line_kind = 'voucher') execute function public.trg_class_line_changed();
  $ddl$;

  -- 4. Page functions.
  execute $ddl$
    create function public.class_page_data()
    returns jsonb
    language plpgsql
    stable
    security definer
    set search_path = public, pg_temp
    as $fn$
    declare v_out jsonb;
    begin
      perform public.require_active_staff();
      perform public.inventory_manager_guard('classes');
      -- 548 (the Owner, 27 Nov 2026): the Class page. All active staff but an Inventory Manager see
      -- the classes, their dates and how many seats each date has taken; the buyers (customer name and
      -- phone, as the Invoices page shows them) only of the invoices of the caller's stores (the app's
      -- store access: every store for an Owner or Admin).
      with seats as materialized (select * from public.class_live_seats(null))
      select jsonb_build_object(
        'can_edit', public.is_owner_or_manager(),
        'classes', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'voucher_id', c.voucher_id, 'code', v.code, 'name', v.name, 'price', v.selling_price,
                   'is_active', v.is_active, 'seat_mode', c.seat_mode, 'capacity_per_date', c.capacity_per_date,
                   'sort_order', c.sort_order, 'summary', c.summary, 'details', c.details,
                   'seats_sold', (select count(*) from seats s where s.voucher_id = c.voucher_id),
                   'sessions', coalesce((
                     select jsonb_agg(jsonb_build_object(
                              'id', s.id, 'seq', s.seq, 'title', s.title, 'kind', s.kind, 'session_date', s.session_date,
                              'starts_at', s.starts_at, 'ends_at', s.ends_at, 'mode', s.mode, 'venue', s.venue,
                              'must_attend', s.must_attend,
                              'taken', (select count(*) from public.class_seat_dates d
                                         join seats ls on ls.invoice_item_id = d.invoice_item_id and ls.seat_no = d.seat_no
                                        where d.session_id = s.id))
                            order by s.session_date, s.seq)
                       from public.class_sessions s where s.voucher_id = c.voucher_id), '[]'::jsonb))
                 order by c.sort_order, v.name)
            from public.class_vouchers c join public.vouchers v on v.id = c.voucher_id
           where v.deleted_at is null), '[]'::jsonb),
        'seats', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'voucher_id', ls.voucher_id, 'invoice_item_id', ls.invoice_item_id, 'seat_no', ls.seat_no,
                   'seats_on_line', ls.on_line,
                   'invoice_id', i.id, 'invoice_no', i.invoice_no, 'invoice_status', i.status,
                   'business_date', i.business_date, 'store_id', i.store_id, 'store_name', st.name,
                   'customer_id', cu.id, 'customer_name', cu.full_name, 'customer_phone', cu.phone,
                   'session_id', d.session_id,
                   'attended', coalesce((select jsonb_agg(a.session_id) from public.class_attendance a
                                          where a.invoice_item_id = ls.invoice_item_id and a.seat_no = ls.seat_no), '[]'::jsonb))
                 order by i.created_at, i.invoice_no, ls.seat_no)
            from (select x.*, count(*) over (partition by x.invoice_item_id) as on_line from seats x) ls
            join public.invoices i on i.id = ls.invoice_id
            join public.stores st on st.id = i.store_id
            left join public.customers cu on cu.id = i.customer_id
            left join public.class_seat_dates d on d.invoice_item_id = ls.invoice_item_id and d.seat_no = ls.seat_no
           where public.user_has_store_access(i.store_id)), '[]'::jsonb))
        into v_out;
      return v_out;
    end
    $fn$;
    create function public.class_choose_date(p_invoice_item_id uuid, p_seat_no integer, p_session_id uuid)
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, pg_temp
    as $fn$
    declare it public.invoice_items%rowtype; inv public.invoices%rowtype; c public.class_vouchers%rowtype;
            s public.class_sessions%rowtype; v_old uuid;
    begin
      perform public.require_active_staff();
      perform public.inventory_manager_guard('classes');
      -- 548: the one date a seat chooses (null clears it). Whoever has access to the invoice's store (every
      -- store for an Owner or Admin). Only a choose-a-date class; only a live seat; the capacity is
      -- the table's trigger's.
      if p_invoice_item_id is null or p_seat_no is null then raise exception 'Say which seat.'; end if;
      select * into it from public.invoice_items where id = p_invoice_item_id and line_kind = 'voucher';
      select * into inv from public.invoices where id = it.invoice_id;
      if not found or not exists (select 1 from public.class_vouchers x where x.voucher_id = it.voucher_id) then
        raise exception 'That is not a seat of a class.'; end if;
      if not public.user_has_store_access(inv.store_id) then
        raise exception 'That seat is on an invoice of a store you do not work at.' using errcode = '42501'; end if;
      select * into c from public.class_vouchers where voucher_id = it.voucher_id;
      if c.seat_mode <> 'choose_date' then
        raise exception 'This class has no date to choose: every seat attends every session.'; end if;
      if p_seat_no < 1 or p_seat_no > coalesce(public.class_line_units(it.id), 0) then
        raise exception 'That seat is not on a live invoice (it was cancelled or refunded).'; end if;
      select session_id into v_old from public.class_seat_dates where invoice_item_id = it.id and seat_no = p_seat_no for update;
      if p_session_id is not null then
        select * into s from public.class_sessions where id = p_session_id;
        if not found or s.voucher_id <> it.voucher_id then raise exception 'That date is not one of this class''s dates.'; end if;
      end if;
      if v_old is not distinct from p_session_id then
        return jsonb_build_object('session_id', p_session_id, 'changed', false); end if;
      if v_old is not null and exists (select 1 from public.class_attendance
                                        where invoice_item_id = it.id and seat_no = p_seat_no and session_id = v_old) then
        raise exception 'This seat is ticked as attended on its date. Remove the tick first.'; end if;
      if p_session_id is null then
        delete from public.class_seat_dates where invoice_item_id = it.id and seat_no = p_seat_no;
      else
        insert into public.class_seat_dates(invoice_item_id, seat_no, session_id, chosen_by)
          values (it.id, p_seat_no, p_session_id, auth.uid())
          on conflict (invoice_item_id, seat_no)
          do update set session_id = excluded.session_id, chosen_by = excluded.chosen_by, chosen_at = now();
      end if;
      perform public.write_audit_ex('invoice_items', it.id, case when p_session_id is null then 'class_date_cleared' else 'class_date_chosen' end,
        jsonb_build_object('seat_no', p_seat_no, 'session_id', v_old),
        jsonb_build_object('seat_no', p_seat_no, 'session_id', p_session_id, 'voucher_id', it.voucher_id, 'invoice_no', inv.invoice_no),
        'classes', null, inv.store_id);
      return jsonb_build_object('session_id', p_session_id, 'changed', true);
    end
    $fn$;
    create function public.class_set_attendance(p_session_id uuid, p_invoice_item_id uuid, p_seat_no integer, p_attended boolean)
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, pg_temp
    as $fn$
    declare it public.invoice_items%rowtype; inv public.invoices%rowtype; c public.class_vouchers%rowtype;
            s public.class_sessions%rowtype; v_chosen uuid; v_had boolean;
    begin
      perform public.require_active_staff();
      perform public.inventory_manager_guard('classes');
      -- 548: staff tick (or untick) that a seat attended a session. Whoever has access to the invoice's store
      -- (every store for an Owner or Admin). A choose-a-date class: only on the date the seat chose.
      if p_session_id is null or p_invoice_item_id is null or p_seat_no is null or p_attended is null then
        raise exception 'Say which session and which seat.'; end if;
      select * into s from public.class_sessions where id = p_session_id;
      if not found then raise exception 'That session does not exist.'; end if;
      select * into it from public.invoice_items where id = p_invoice_item_id and line_kind = 'voucher';
      select * into inv from public.invoices where id = it.invoice_id;
      if not found or it.voucher_id is distinct from s.voucher_id then
        raise exception 'That seat did not buy this class.'; end if;
      if not public.user_has_store_access(inv.store_id) then
        raise exception 'That seat is on an invoice of a store you do not work at.' using errcode = '42501'; end if;
      select * into c from public.class_vouchers where voucher_id = s.voucher_id;
      if p_seat_no < 1 or p_seat_no > coalesce(public.class_line_units(it.id), 0) then
        raise exception 'That seat is not on a live invoice (it was cancelled or refunded).'; end if;
      if c.seat_mode = 'choose_date' then
        select session_id into v_chosen from public.class_seat_dates where invoice_item_id = it.id and seat_no = p_seat_no;
        if v_chosen is distinct from p_session_id then
          raise exception 'This seat chose another date (or none yet): set its date first.'; end if;
      end if;
      v_had := exists (select 1 from public.class_attendance
                        where session_id = p_session_id and invoice_item_id = it.id and seat_no = p_seat_no);
      if p_attended and not v_had then
        insert into public.class_attendance(session_id, invoice_item_id, seat_no, marked_by)
          values (p_session_id, it.id, p_seat_no, auth.uid());
      elsif not p_attended and v_had then
        delete from public.class_attendance where session_id = p_session_id and invoice_item_id = it.id and seat_no = p_seat_no;
      else
        return jsonb_build_object('attended', p_attended, 'changed', false);
      end if;
      perform public.write_audit_ex('invoice_items', it.id, case when p_attended then 'class_attended' else 'class_attendance_removed' end,
        null, jsonb_build_object('seat_no', p_seat_no, 'session_id', p_session_id, 'voucher_id', it.voucher_id, 'invoice_no', inv.invoice_no),
        'classes', null, inv.store_id);
      return jsonb_build_object('attended', p_attended, 'changed', true);
    end
    $fn$;
    create function public.class_save_session(p_voucher_id uuid, p_session_id uuid, p_data jsonb)
    returns uuid
    language plpgsql
    security definer
    set search_path = public, pg_temp
    as $fn$
    declare c public.class_vouchers%rowtype; s public.class_sessions%rowtype; v_id uuid;
            v_title text; v_kind text; v_date date; v_start time; v_end time; v_mode text; v_venue text; v_must boolean; v_seq integer;
    begin
      perform public.require_active_staff('{owner,manager}');
      -- 548 (the Owner, 27 Nov 2026): only Owners and Managers add or change a class's dates. data:
      -- {"title", "kind", "session_date", "starts_at", "ends_at", "mode", "venue", "must_attend", "seq"}
      -- (a change keeps what is not named).
      select * into c from public.class_vouchers where voucher_id = p_voucher_id for update;
      if not found then raise exception 'That is not a class.'; end if;
      if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Say the date''s details.'; end if;
      if p_session_id is not null then
        select * into s from public.class_sessions where id = p_session_id for update;
        if not found or s.voucher_id <> p_voucher_id then raise exception 'That date does not belong to this class.'; end if;
      end if;
      v_title := btrim(coalesce(p_data->>'title', s.title, ''));
      v_kind := coalesce(p_data->>'kind', s.kind, case when c.seat_mode = 'choose_date' then 'class_day' else 'lesson' end);
      begin
        v_date := coalesce(nullif(p_data->>'session_date', '')::date, s.session_date);
        v_start := case when p_data ? 'starts_at' then nullif(p_data->>'starts_at', '')::time else s.starts_at end;
        v_end := case when p_data ? 'ends_at' then nullif(p_data->>'ends_at', '')::time else s.ends_at end;
      exception when others then raise exception 'The date or a time is not valid.'; end;
      v_mode := coalesce(p_data->>'mode', s.mode, 'in_person');
      v_venue := case when p_data ? 'venue' then nullif(btrim(p_data->>'venue'), '') else s.venue end;
      v_must := coalesce((p_data->>'must_attend')::boolean, s.must_attend, false);
      if v_date is null then raise exception 'A date needs its day.'; end if;
      if v_title = '' then raise exception 'A date needs a title.'; end if;
      if v_kind not in ('lesson', 'revision', 'graduation', 'class_day') then raise exception 'Unknown kind of date: %.', v_kind; end if;
      if v_mode not in ('in_person', 'zoom') then raise exception 'A date is in person or on Zoom.'; end if;
      if v_start is not null and v_end is not null and v_end <= v_start then raise exception 'A date must end after it starts.'; end if;
      begin
        if p_session_id is null then
          v_seq := coalesce(nullif(p_data->>'seq', '')::integer, (select coalesce(max(seq), 0) + 1 from public.class_sessions where voucher_id = p_voucher_id));
          insert into public.class_sessions(voucher_id, seq, title, kind, session_date, starts_at, ends_at, mode, venue, must_attend, updated_by)
            values (p_voucher_id, v_seq, v_title, v_kind, v_date, v_start, v_end, v_mode, v_venue, v_must, auth.uid())
            returning id into v_id;
          perform public.write_audit_ex('class_sessions', v_id, 'class_session_added', null,
            to_jsonb((select x from public.class_sessions x where x.id = v_id)) , 'classes', null, null);
        else
          v_id := p_session_id;
          v_seq := coalesce(nullif(p_data->>'seq', '')::integer, s.seq);
          update public.class_sessions set seq = v_seq, title = v_title, kind = v_kind, session_date = v_date, starts_at = v_start,
                 ends_at = v_end, mode = v_mode, venue = v_venue, must_attend = v_must, updated_at = now(), updated_by = auth.uid()
           where id = v_id;
          perform public.write_audit_ex('class_sessions', v_id, 'class_session_changed', to_jsonb(s),
            to_jsonb((select x from public.class_sessions x where x.id = v_id)), 'classes', null, null);
        end if;
      exception when unique_violation then
        raise exception 'This class already has a date on %.', v_date;
      end;
      return v_id;
    end
    $fn$;
    create function public.class_remove_session(p_session_id uuid)
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, pg_temp
    as $fn$
    declare s public.class_sessions%rowtype; v_cleared jsonb;
    begin
      perform public.require_active_staff('{owner,manager}');
      -- 548: only Owners and Managers remove a date. Refused while a LIVE seat of its class chose it or while
      -- anyone was ticked at it; the dates only cancelled or refunded seats chose go with it, listed in the entry.
      select * into s from public.class_sessions where id = p_session_id for update;
      if not found then raise exception 'That date does not exist.'; end if;
      if exists (select 1 from public.class_seat_dates d
                   join public.class_live_seats(s.voucher_id) ls on ls.invoice_item_id = d.invoice_item_id and ls.seat_no = d.seat_no
                  where d.session_id = s.id) then
        raise exception 'A seat chose this date or was ticked at it, so it stays. Move the seats to another date first, or change this date instead.'; end if;
      if exists (select 1 from public.class_attendance where session_id = s.id) then
        raise exception 'Someone was ticked as attended on this date, so it stays. Change this date instead.'; end if;
      with gone as (delete from public.class_seat_dates where session_id = s.id returning invoice_item_id, seat_no)
        select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id', invoice_item_id, 'seat_no', seat_no) order by invoice_item_id, seat_no), '[]'::jsonb)
          into v_cleared from gone;
      delete from public.class_sessions where id = s.id;
      perform public.write_audit_ex('class_sessions', s.id, 'class_session_removed',
        to_jsonb(s) || jsonb_build_object('cleared_seat_dates', v_cleared), null, 'classes', null, null);
      return jsonb_build_object('removed', s.id);
    end
    $fn$;
    create function public.class_save_details(p_voucher_id uuid, p_data jsonb)
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, pg_temp
    as $fn$
    declare c public.class_vouchers%rowtype; v_cap integer; v_max integer; v_summary text; v_details jsonb;
    begin
      perform public.require_active_staff('{owner,manager}');
      -- 548: only Owners and Managers edit a class's details. data: {"summary": text, "details": object,
      -- "capacity_per_date": number or null (a choose-a-date class only; not below the seats a date has taken)}.
      select * into c from public.class_vouchers where voucher_id = p_voucher_id for update;
      if not found then raise exception 'That is not a class.'; end if;
      if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Say what to change.'; end if;
      v_summary := case when p_data ? 'summary' then nullif(btrim(p_data->>'summary'), '') else c.summary end;
      v_details := case when p_data ? 'details' then p_data->'details' else c.details end;
      if jsonb_typeof(v_details) is distinct from 'object' then raise exception 'The details are a set of named entries.'; end if;
      v_cap := c.capacity_per_date;
      if p_data ? 'capacity_per_date' then
        if c.seat_mode <> 'choose_date' then raise exception 'Only a class whose seats choose a date has a capacity per date.'; end if;
        begin v_cap := nullif(p_data->>'capacity_per_date', '')::integer; exception when others then raise exception 'The capacity is a whole number.'; end;
        if v_cap is not null and v_cap < 1 then raise exception 'The capacity is at least 1 seat per date.'; end if;
        -- Lock the class's dates before counting: a seat being given a date right now (its trigger holds the
        -- date's row) finishes first and is counted; one that comes after reads the new limit.
        perform 1 from public.class_sessions where voucher_id = p_voucher_id for update;
        select coalesce(max(n), 0) into v_max from (
          select count(*) as n from public.class_seat_dates d
            join public.class_live_seats(p_voucher_id) ls on ls.invoice_item_id = d.invoice_item_id and ls.seat_no = d.seat_no
           group by d.session_id) x;
        if v_cap is not null and v_cap < v_max then
          raise exception 'A date already has % seats; the capacity cannot be below that.', v_max; end if;
      end if;
      update public.class_vouchers set summary = v_summary, details = v_details, capacity_per_date = v_cap,
             updated_at = now(), updated_by = auth.uid() where voucher_id = p_voucher_id;
      perform public.write_audit_ex('class_vouchers', p_voucher_id, 'class_details_changed',
        jsonb_build_object('summary', c.summary, 'details', c.details, 'capacity_per_date', c.capacity_per_date),
        jsonb_build_object('summary', v_summary, 'details', v_details, 'capacity_per_date', v_cap), 'classes', null, null);
      return jsonb_build_object('voucher_id', p_voucher_id, 'capacity_per_date', v_cap);
    end
    $fn$;
  $ddl$;

  -- 5. Grants: the page functions to signed-in logins, the internal ones to nobody but the server.
  revoke all on function public.class_line_units(uuid), public.class_live_seats(uuid), public.trg_class_seat_date_capacity(), public.trg_class_line_changed()
    from public, anon, authenticated;
  grant execute on function public.class_line_units(uuid), public.class_live_seats(uuid) to service_role;
  revoke all on function public.class_page_data(), public.class_choose_date(uuid, integer, uuid),
    public.class_set_attendance(uuid, uuid, integer, boolean), public.class_save_session(uuid, uuid, jsonb),
    public.class_remove_session(uuid), public.class_save_details(uuid, jsonb) from public, anon;
  grant execute on function public.class_page_data(), public.class_choose_date(uuid, integer, uuid),
    public.class_set_attendance(uuid, uuid, integer, boolean), public.class_save_session(uuid, uuid, jsonb),
    public.class_remove_session(uuid), public.class_save_details(uuid, jsonb) to authenticated, service_role;

  -- 6. Data: old invoices keep their names, the four vouchers are marked and renamed, the schedules seeded.
  for k in 1 .. array_length(c_codes, 1) loop
    select id into v_id from public.vouchers where code = c_codes[k][1] and deleted_at is null;
    if c_codes[k][2] <> c_codes[k][3] then
      with f as (update public.invoice_items set item_name_snapshot = c_codes[k][2]
                  where voucher_id = v_id and line_kind = 'voucher' and nullif(btrim(item_name_snapshot), '') is null
                  returning id)
      select array_agg(id order by id) into v_frozen from f;
      if v_frozen is not null then
        perform public.write_audit_ex('vouchers', v_id, 'class_lines_name_frozen', null,
          jsonb_build_object('name', c_codes[k][2], 'invoice_item_ids', to_jsonb(v_frozen)), 'catalogue',
          '548: the old name is kept on the invoice lines that had no name of their own, before the voucher is renamed', null);
      end if;
      update public.vouchers set name = c_codes[k][3] where id = v_id;
    end if;
    insert into public.class_vouchers(voucher_id, seat_mode, capacity_per_date, sort_order)
      values (v_id, c_codes[k][5], nullif(c_codes[k][6], '')::integer, c_codes[k][7]::integer);
  end loop;
  update public.class_vouchers set summary = 'Monthly Zoom workshop: 12 sessions and a graduation',
    details = jsonb_build_object(
      'fee_note', 'Early bird S$799 (usual S$4,788)',
      'time_text', 'Fridays, 8:00-10:00 PM',
      'format_text', 'Session 1 is in person at The Adelphi (must attend). Sessions 2 to 10 are on Zoom. Sessions 11 and 12 are revision and test, on Zoom.',
      'notes', jsonb_build_array('Graduation: Sat 1 Jan 2028, 10:00 AM-3:00 PM, in person (venue to be confirmed).'))
   where voucher_id = v_foundation;
  update public.class_vouchers set summary = 'Monthly Zoom workshop: 12 months and 1 graduation',
    details = jsonb_build_object(
      'fee_note', 'S$1,441, 12 months + 1 graduation (usual S$7,188)',
      'time_text', 'Thursdays, 8:00-10:00 PM',
      'format_text', 'Session 1 is in person at The Adelphi (must attend). Sessions 2 to 10 are on Zoom. Sessions 11 and 12 are revision and test, on Zoom.',
      'notes', jsonb_build_array('Graduation: Sat 1 Jan 2028, 10:00 AM-3:00 PM, in person (venue to be confirmed).'))
   where voucher_id = v_advanced;
  update public.class_vouchers set summary = '1-day course, in person, max 6 per class',
    details = jsonb_build_object(
      'fee_note', 'S$676 (usual S$1,174 = course S$499 + Skin Care Set S$675)',
      'time_text', '7:00-9:00 PM',
      'venue_text', 'The Adelphi, 1 Coleman Street #B1-37',
      'format_text', 'Each seat chooses one of the dates below. Vegan, alcohol-free, for all skin types.',
      'learn', jsonb_build_array('Deep Cleansing', 'Intense Hydration', 'Restore & Protect'),
      'notes', jsonb_build_array('The Skin Care Set (9 products) is handled separately: no stock moves with the class.'))
   where voucher_id = v_skin;
  update public.class_vouchers set summary = 'One in-person day of the Foundation class',
    details = jsonb_build_object(
      'fee_note', 'S$399',
      'format_text', 'In person. Each seat chooses one day from the dates an Owner or Manager sets below.',
      'notes', jsonb_build_array('The days to choose from are still to be set.'))
   where voucher_id = v_lc;
  insert into public.class_sessions(voucher_id, seq, title, kind, session_date, starts_at, ends_at, mode, venue, must_attend)
    select v_foundation, s.seq, s.title, s.kind, s.d, s.st, s.en, s.mode, s.venue, s.must
      from (values
        (1, 'Session 1', 'lesson', date '2027-01-29', time '20:00', time '22:00', 'in_person', 'The Adelphi', true),
        (2, 'Session 2', 'lesson', date '2027-02-26', time '20:00', time '22:00', 'zoom', null, false),
        (3, 'Session 3', 'lesson', date '2027-03-26', time '20:00', time '22:00', 'zoom', null, false),
        (4, 'Session 4', 'lesson', date '2027-04-30', time '20:00', time '22:00', 'zoom', null, false),
        (5, 'Session 5', 'lesson', date '2027-05-28', time '20:00', time '22:00', 'zoom', null, false),
        (6, 'Session 6', 'lesson', date '2027-06-25', time '20:00', time '22:00', 'zoom', null, false),
        (7, 'Session 7', 'lesson', date '2027-07-30', time '20:00', time '22:00', 'zoom', null, false),
        (8, 'Session 8', 'lesson', date '2027-08-27', time '20:00', time '22:00', 'zoom', null, false),
        (9, 'Session 9', 'lesson', date '2027-09-24', time '20:00', time '22:00', 'zoom', null, false),
        (10, 'Session 10', 'lesson', date '2027-10-29', time '20:00', time '22:00', 'zoom', null, false),
        (11, 'Revision & test', 'revision', date '2027-11-26', time '20:00', time '22:00', 'zoom', null, false),
        (12, 'Revision & test', 'revision', date '2027-12-30', time '20:00', time '22:00', 'zoom', null, false),
        (13, 'Graduation', 'graduation', date '2028-01-01', time '10:00', time '15:00', 'in_person', null, false)
      ) s(seq, title, kind, d, st, en, mode, venue, must);
  insert into public.class_sessions(voucher_id, seq, title, kind, session_date, starts_at, ends_at, mode, venue, must_attend)
    select v_advanced, s.seq, s.title, s.kind, s.d, s.st, s.en, s.mode, s.venue, s.must
      from (values
        (1, 'Session 1', 'lesson', date '2027-01-28', time '20:00', time '22:00', 'in_person', 'The Adelphi', true),
        (2, 'Session 2', 'lesson', date '2027-02-25', time '20:00', time '22:00', 'zoom', null, false),
        (3, 'Session 3', 'lesson', date '2027-03-25', time '20:00', time '22:00', 'zoom', null, false),
        (4, 'Session 4', 'lesson', date '2027-04-29', time '20:00', time '22:00', 'zoom', null, false),
        (5, 'Session 5', 'lesson', date '2027-05-27', time '20:00', time '22:00', 'zoom', null, false),
        (6, 'Session 6', 'lesson', date '2027-06-24', time '20:00', time '22:00', 'zoom', null, false),
        (7, 'Session 7', 'lesson', date '2027-07-29', time '20:00', time '22:00', 'zoom', null, false),
        (8, 'Session 8', 'lesson', date '2027-08-26', time '20:00', time '22:00', 'zoom', null, false),
        (9, 'Session 9', 'lesson', date '2027-09-23', time '20:00', time '22:00', 'zoom', null, false),
        (10, 'Session 10', 'lesson', date '2027-10-28', time '20:00', time '22:00', 'zoom', null, false),
        (11, 'Revision & test', 'revision', date '2027-11-25', time '20:00', time '22:00', 'zoom', null, false),
        (12, 'Revision & test', 'revision', date '2027-12-29', time '20:00', time '22:00', 'zoom', null, false),
        (13, 'Graduation', 'graduation', date '2028-01-01', time '10:00', time '15:00', 'in_person', null, false)
      ) s(seq, title, kind, d, st, en, mode, venue, must);
  insert into public.class_sessions(voucher_id, seq, title, kind, session_date, starts_at, ends_at, mode, venue, must_attend)
    select v_skin, row_number() over (order by d), 'Class day', 'class_day', d, time '19:00', time '21:00', 'in_person',
           'The Adelphi, 1 Coleman Street #B1-37', false
      from unnest(array[date '2027-01-27', date '2027-02-24', date '2027-03-24', date '2027-04-28', date '2027-05-26', date '2027-06-23',
                        date '2027-07-28', date '2027-08-25', date '2027-09-22', date '2027-10-27', date '2027-11-24', date '2027-12-28']) d;

  -- 7. Checks after: nothing else changed.
  select count(*) into v_n from fn_before_548 b
    join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as def
            from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') a using (fn)
   where a.def <> b.def;
  if v_n <> 0 then raise exception '548: % existing functions changed', v_n; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f')
       <> (select count(*) from fn_before_548) + array_length(c_new, 1) then
    raise exception '548: the number of functions is not the 1,471 plus the new ones'; end if;
  for k in 1 .. array_length(c_new, 1) loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure('public.' || c_new[k][1])));
    if v_md5 <> c_new[k][2] then raise exception '548: public.% is not the tested text (md5 %)', c_new[k][1], v_md5; end if;
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.' || c_new[k][1])
          and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig)) then
      raise exception '548: public.% does not search pg_temp last', c_new[k][1]; end if;
  end loop;
  if (select count(*) from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and not t.tgisinternal)
       <> (select count(*) from tg_before_548) + 2
     or exists (select 1 from tg_before_548 b where not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass
                  and t.tgname = b.tgname and pg_get_triggerdef(t.oid) = b.def))
     or (select count(*) from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and t.tgname in ('class_line_voucher_changed', 'class_line_removed')
            and t.tgenabled = 'O') <> 2 then
    raise exception '548: invoice_items has not exactly its old triggers plus the two class triggers'; end if;
  if has_function_privilege('anon', 'public.trg_class_line_changed()', 'execute')
     or has_function_privilege('authenticated', 'public.trg_class_line_changed()', 'execute') then
    raise exception '548: the class line trigger function is callable by a login'; end if;
  select md5(string_agg(md5(pg_get_functiondef(oid)), '' order by oid::regprocedure::text)) || '/' || count(*) into v_fp
    from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f';
  if v_fp <> c_fp_after then raise exception '548: the functions after are not the tested ones (fingerprint %)', v_fp; end if;
  if exists (select 1 from pg_class c where c.relnamespace = 'public'::regnamespace
               and c.relname in ('class_vouchers', 'class_sessions', 'class_seat_dates', 'class_attendance')
               and (not c.relrowsecurity
                    or has_table_privilege('anon', c.oid, 'select,insert,update,delete,truncate,references,trigger')
                    or has_table_privilege('authenticated', c.oid, 'insert,update,delete,truncate,references,trigger')
                    or not has_table_privilege('authenticated', c.oid, 'select'))) then
    raise exception '548: a class table is open to a client role or has no row rules'; end if;
  if (select count(*) from public.class_sessions where voucher_id = v_foundation) <> 13
     or (select count(*) from public.class_sessions where voucher_id = v_advanced) <> 13
     or (select count(*) from public.class_sessions where voucher_id = v_skin) <> 12
     or (select count(*) from public.class_sessions where voucher_id = v_lc) <> 0 then
    raise exception '548: the seeded dates are not 13, 13, 12 and 0'; end if;
  if exists (select 1 from price_before_548 b join public.vouchers v on v.id = b.id
              where (v.selling_price, v.voucher_kind, v.qty_type, v.is_active, v.valid_from, v.valid_until, v.reward_eligible)
                    is distinct from (b.selling_price, b.voucher_kind, b.qty_type, b.is_active, b.valid_from, b.valid_until, b.reward_eligible)
                 or (select md5(coalesce(string_agg(s.store_id::text || ':' || coalesce(s.selling_price::text, '') || ':' || s.available_at_store::text,
                                                    ',' order by s.store_id), ''))
                       from public.voucher_store_prices s where s.voucher_id = v.id and s.deleted_at is null) is distinct from b.store_prices) then
    raise exception '548: a class voucher''s price or terms changed'; end if;
  if (select count(*) from public.vouchers v where v.name in ('Lymphatic Foundation Workshop 2027', 'Lymphatic Advanced Workshop 2027',
        'Korea No.1 Skin Care Workshop', 'Lymphatic Class') and v.id in (v_foundation, v_advanced, v_skin, v_lc)) <> 4 then
    raise exception '548: the four vouchers are not named as the Owner said'; end if;
  -- Only the renamed vouchers: the Lymphatic Class's name does not change, so its lines with no printed name
  -- keep printing it and are left as they are.
  if exists (select 1 from public.invoice_items it where it.line_kind = 'voucher' and it.voucher_id in (v_foundation, v_advanced, v_skin)
              and nullif(btrim(it.item_name_snapshot), '') is null) then
    raise exception '548: an invoice line of a class voucher was left without its printed name'; end if;

  drop table fn_before_548, price_before_548, tg_before_548;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
