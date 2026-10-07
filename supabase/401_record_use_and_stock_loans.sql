-- 401_record_use_and_stock_loans.sql
--
-- WHAT WAS WRONG (found 6 Oct 2026)
--
--   * Record Use on the Store stock page called record_stock_use once per
--     product line, in a loop in the browser. It was not one transaction: when
--     line 3 of 4 was refused (not enough stock, say), lines 1 and 2 were
--     already saved, but the form kept all four lines, so pressing Record Use
--     again took lines 1 and 2 off the shelf a second time. A dropped
--     connection after a save had the same effect.
--   * The Warehouse stock page had no Record Use at all, although
--     record_stock_use has accepted a warehouse since 345 (for the warehouse
--     stock permission: Owner, Manager, Inventory Manager).
--   * Nothing recorded stock lent out: a demo set taken to a roadshow, a unit
--     a customer tries at home. Staff either left it on the shelf in the
--     system (where it could be sold) or wrote it off as a use or an
--     adjustment and wrote it back later, with no borrower, no due date and
--     no trace of what came back.
--
-- THE RULES (the Owner, 6 Oct 2026, final)
--
--   1. The Warehouse stock page gets a Record Use button like the Store
--      page's, for those the database lets use warehouse stock. Record use is
--      atomic on both pages: all its lines in one transaction, safe to retry.
--      record_stock_use keeps working for any other caller.
--   2. A "Lend" button (lend out and take back) on both stock pages. At a
--      store: any staff with access to that store, as Record use. At a
--      warehouse: Owner/Manager (the warehouse stock permission). No approval.
--   3. The borrower is a customer or affiliate picked from the system (the
--      loan then shows on that customer's profile on the Customers page) or a
--      typed name (a roadshow, an event, anyone); a purpose or note; an
--      expected return date, required; product lines with quantities. The
--      stock LEAVES the location's on-hand stock when it is lent (a new
--      movement, loan_out, from the location), so it cannot be sold; a line
--      with less stock than asked is refused.
--   4. An "On loan" list on both pages (the location's open loans: borrower,
--      items, date out, expected return, OVERDUE highlighted) and an "Out on
--      loan" figure per product on the stock tables.
--   5. Taking back: part returns allowed. For each line staff record the
--      quantity returned, into ANY store or warehouse they choose (into a
--      warehouse only with the warehouse stock permission), and close what
--      did not come back as "used / given away" or "lost / damaged". An item
--      that comes back damaged goes back into stock or is recorded as used,
--      as staff choose. Returned stock comes back with a loan_return movement
--      into the chosen location. Used and lost move no stock (it already
--      left) but account for the line. A loan closes when every line is fully
--      accounted for.
--   6. Stock History shows "Lent out" and "Loan returned", with the loan
--      number (LOAN-000001) in the note.
--   7. A typed borrower name is kept in the database; never in repository
--      fixtures.
--
-- WHAT THIS DOES
--
--   * stock_uses gains request_id: the form's id for one Record use, shared
--     by its lines, so a retry is recognised (rule 1).
--   * record_stock_uses(location_type, location_id, lines, reason, note,
--     request_id): Record use for several products in one transaction. Each
--     line goes through record_stock_use, unchanged, so a batch line is
--     exactly a single use (its checks, its USE- number, its
--     inventory_adjustment movement "Stock use USE-… — reason (note)", its
--     audit row and its permission), and a refused line refuses them all.
--     Products are taken in a fixed order (two batches at once lock the same
--     rows in the same order). A call with a request id already recorded by
--     the same person at the same location, with the same products,
--     quantities, reason and note, records nothing and answers with the uses
--     the first call recorded ("replayed"); one recorded by someone else or
--     elsewhere is refused, and so is the same form changed after a failed
--     save (the refusal names the uses it did record), so a retry never
--     answers "already recorded" for changes that were not kept. Granted to
--     staff.
--   * stock_loans (one row per loan: LOAN-000001 from stock_loan_no_seq; where
--     it was lent from, as stock_uses records a location; the customer or
--     the typed name, exactly one; purpose; expected return date; open or
--     closed; who lent it and when; the form's request id), stock_loan_lines
--     (product, quantity out, and how much of it has been returned, used and
--     lost, never more than went out) and stock_loan_events (every take-back
--     entry: returned, used or lost, the quantity, the condition, where a
--     return went and its movement, the note, who and when). Row-level
--     security lets staff read the loans of the stores they have access to,
--     and Owners, Admins and Managers (and the warehouse stock permission)
--     every loan; nobody writes them except through the functions below.
--   * lend_stock(location_type, location_id, lines, expected_return_date,
--     customer_id, borrower_name, purpose, request_id): rules 2 and 3. Takes
--     every line off the location's stock (refusing a line with less stock
--     than asked, so nothing is lent), with one loan_out movement per line
--     noted "LOAN-000001 — lent to <borrower> (<purpose>), due back <date>",
--     and an audit row (stock_lent). The expected return date is required and
--     not in the past (Singapore date). A retry with the same request id
--     answers with the loan already made when it is the same form (person,
--     place, borrower, purpose, date, products and quantities); a changed
--     one is refused, naming the loan. Granted to staff; it checks.
--   * return_stock_loan(loan, entries, note, request_id): rule 5. Each entry
--     names a line of the loan, an outcome (returned, used, lost) and a
--     quantity; a return names its condition (good or damaged) and the store
--     or warehouse it came back to; "used" may say "damaged" (it came back
--     damaged and is recorded as used). Entries for a line may not account
--     for more than is still out on it. A return puts the stock into the
--     chosen location (store_inventory or warehouse_inventory) with a
--     loan_return movement noted "LOAN-000001 — returned by <borrower>
--     (damaged)"; used and lost move no stock. When every line is accounted
--     for the loan closes. Acting on a loan needs what lending from its
--     location needs; returning into a warehouse also needs the warehouse
--     stock permission; returning into any active store needs nothing more
--     (the Owner: "to ANY store"). A retry with the same request id records
--     nothing again when its entries are the ones recorded; changed entries
--     are refused, naming what was recorded. Audit row:
--     stock_loan_taken_back. Granted to staff.
--   * stock_loans_at(location_type, location_id, include_closed): the "On
--     loan" list of rule 4, for a location the caller may see: its open
--     loans, oldest due first, each with lines, what is still out, the
--     take-back history and whether it is overdue (open and due before
--     today, Singapore date); and, asked for, its last 50 closed loans. The
--     pages add up what is still out per product for "Out on loan". It also
--     answers can_act: whether the caller may lend, take back and Record use
--     there (store access, or the warehouse stock permission), because
--     Owners, Admins and Managers see every location's list but act only
--     where those functions let them; the pages offer the buttons by it.
--   * customer_stock_loans(customer): a customer's loans (rule 3), those the
--     caller may see, open first. Granted to staff.
--   * stock_loan_access(location_type, location_id, act) and
--     stock_loan_json(loan): the rules of who may see and act, and one loan
--     as the screens read it. Internal (339).
--   * stock_history_type_label: "Lent out" for loan_out and "Loan returned"
--     for loan_return (rule 6). Before this they would have read "Loan Out"
--     and "Loan Return" through its catch-all.
--
-- WHY "USED" AND "LOST" WRITE NO stock_uses ROW
--
-- Every stock_uses row today is a use that took stock off a shelf, with its
-- own inventory_adjustment movement and audit row (production, 6 Oct 2026:
-- 84 of each). Lent stock left the shelf at lend-out, with its loan_out
-- movement; a used or lost loan item moves nothing more. A stock_uses row
-- for it would be a use with no movement, so anyone adding up stock_uses to
-- see what was consumed would count stock that never moved again, or count
-- the lent stock twice beside its loan_out. The loan's own event (outcome,
-- quantity, condition, who, when, note) and the audit row are its history;
-- the loan_out movement in Stock History carries the loan number.
--
-- MOVEMENT TYPES: THE REVIEW (production, 6 Oct 2026)
--
-- The 34 functions that read stock_movements or name a movement type were
-- read (no screen or edge function reads the table itself; the pages go
-- through these). None lists the types it accepts in a way a loan movement
-- could break:
--   * invoice stock (deduct_invoice_stock, ensure_invoice_stock_deducted,
--     invoice_stock_to_deduct, invoice_product_net_deducted,
--     restore_invoice_stock, record_invoice_stock_return,
--     refund_invoice_recorded, invoice_refund_options_before_sessions,
--     confirm_foc_invoice, correct_invoice, fulfil_special_doc,
--     promotion_stock_gaps, promotion_stock_history) names store_sale and the
--     two invoice returns and keys on invoice_id; a loan movement has none;
--   * transfers (review_and_dispatch_transfer, receive_transfer,
--     resolve_transfer_discrepancy) and the transfer integrity reports
--     (stock_private_report_transfer_stock_integrity,
--     stock_private_report_multi_source_stock_drift) and Stock History's
--     in-transit figures (stock_history_table) name the transfer types only;
--   * stock_history_effect counts any other movement by its source and
--     destination: minus at the source, plus at the destination. loan_out has
--     a source and loan_return a destination, exactly the inventory changes
--     the inventory triggers log, so Stock History's "Observed inventory
--     changes differ from linked movement totals" stays quiet;
--   * stock_history_rows, stock_history_options and search_stock_movements
--     show the type through stock_history_type_label (patched here) and
--     filter by any type;
--   * the rest write their own types (exchanges, Stock In, special stock-in,
--     TikTok, adjustments, rentals, record_stock_use).
--
-- NOT CHANGED
--
--   * record_stock_use: a batch calls it as it is (guarded below), so its
--     rules and its history are the same for one line or many.
--   * Stock In on the Warehouse page keeps its own loop over
--     warehouse_stock_in (adding stock twice on a retry is the same kind of
--     fault; the Owner's rules did not ask for it here).
--   * Reports' "stock by location" and Stock History's Balances tab: they show
--     on-hand stock, which lent stock has left; neither gains an "on loan"
--     figure here. The stock pages have one (rule 4).
--   * Rentals and their stock (396), transfers, adjustments, sales.
--   * merge_customer_records and delete_customer (production md5s
--     955179afeac18bbfe2218079258669c9 and 921fc8b248ed4bc72344440ae7368a71).
--     A merge carries a duplicate's loans to the record kept: its last step
--     moves every column with a foreign key to customers, which now includes
--     stock_loans.customer_id, so the loan shows on the kept customer's
--     profile (the loan_out movement notes keep the name lent to). Its
--     preview (preview_customer_merge) counts a fixed list of tables and
--     does not mention loans. delete_customer only marks the customer
--     deleted, so a loan stays on that record and still shows on the stock
--     pages with its name; it does not refuse a customer with open loans.
--   * No existing data: no past use, adjustment or movement is relabelled.
--
-- SAFETY
--
-- Needs 400 committed first (checked). Apart from the lock timeout, the
-- migration is one statement (a DO block), so it is atomic however it is
-- run. Every guard and anchor is checked, and every patched text built,
-- before anything is installed. md5(pg_get_functiondef) of the patched
-- function must be the production version read on 6 Oct 2026 (BEFORE), or
-- already this migration's version (AFTER), which is left alone so a re-run
-- changes nothing. The functions it relies on unchanged must be the versions
-- read. A new function that exists with any other text refuses. The anchor
-- must match exactly once. The patch is executed as CREATE OR REPLACE, which
-- keeps owner and grants. Tables, the column, indexes, the sequence and the
-- policies are created only if missing. The internal functions are revoked
-- from public, anon and authenticated and granted to service_role; the five
-- the pages call are revoked from public and anon and granted to
-- authenticated and service_role, and check the caller themselves (339).
-- The new tables and sequence are revoked from public, anon and
-- authenticated; staff get SELECT on the tables, under row-level security,
-- and nothing else. After installing, every function must have its AFTER
-- md5 and the grants are checked. No data changes.
--
-- The loan movement types are written as text everywhere here ('loan_out'
-- is never cast to the enum when a function is created), so nothing in this
-- file depends on 400's values being usable in the same transaction.
--
-- BEFORE (production, 6 Oct 2026, md5 of pg_get_functiondef):
--   stock_history_type_label(text)                           7df9ac5d4ce27fa6735f1e2c67bf66b6
--   (relied on, not changed)
--   record_stock_use(text,uuid,uuid,integer,text,text)       db278faba262b0a3801944cd821a62fd
--   stock_history_effect(uuid,text)                          fba6f63412970dbf6ac83e567c4d85e2
--   user_has_store_access(uuid)                              8c82c6bcb64f496c5a05a2b8dafa95f8
--   can_manage_warehouse_stock()                             b51c6f1c0e77a277d8757d824cb198dd
--   is_manager_or_above()                                    f12b9ed342070fa4defa30e4da2ba655
-- AFTER (for later guards):
--   stock_history_type_label(text)                           f8820dec2fa2db27419df0a08a3c6a07
--   stock_loan_access(text,uuid,boolean)                     09f68356afdabb88cade05af7859e158
--   stock_loan_json(uuid)                                    d9726b2be1578afc7915fe6995db5206
--   record_stock_uses(text,uuid,jsonb,text,text,uuid)        8cab37c88f3f46548d941cd100eb1a78
--   lend_stock(text,uuid,jsonb,date,uuid,text,text,uuid)     fcea544234f910ccecad12f185bdf753
--   return_stock_loan(uuid,jsonb,text,uuid)                  978c886b03ccae32d48de8bc78667975
--   stock_loans_at(text,uuid,boolean)                        4d40d09d2263c304f8de7ddc9686d72d
--   customer_stock_loans(uuid)                               72ea1935e18db21c6ee75d09568d9ecf
--
-- DEPLOY ORDER: 400, then 401, then the pages (they call the new functions;
-- the pages live before them keep working, record_stock_use being unchanged).
--
-- Test: scripts/stock-loans/tests/loans.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New functions ──────────────────────────────────────────────────────────
  c_access_def constant text := $def$
create or replace function public.stock_loan_access(p_location_type text, p_location_id uuid, p_act boolean)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  -- 401: who may see (p_act false) or lend from and take back a loan of
  -- (p_act true) a store or a warehouse. A store: staff with access to it
  -- (Owner and Admin: every store), as Record use. A warehouse: the warehouse
  -- stock permission (Owner, Manager, Inventory Manager), as Record use and
  -- Stock In. Owners, Admins and Managers see every location's loans.
  select case
    when p_location_id is null then false
    when p_location_type = 'store' then
      public.user_has_store_access(p_location_id) or (not coalesce(p_act, true) and public.is_manager_or_above())
    when p_location_type = 'warehouse' then
      public.can_manage_warehouse_stock() or (not coalesce(p_act, true) and public.is_manager_or_above())
    else false end
$fn$
$def$;

  c_json_def constant text := $def$
create or replace function public.stock_loan_json(p_loan_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  -- 401: one loan as the stock pages and the customer's profile show it.
  -- Overdue: still open and due before today (Singapore date).
  select jsonb_build_object(
    'id', l.id, 'loan_no', l.loan_no, 'status', l.status,
    'location_type', l.location_type, 'location_id', coalesce(l.store_id, l.warehouse_id),
    'location_name', coalesce(s.name, w.name),
    'customer_id', l.customer_id, 'borrower', coalesce(c.full_name, l.borrower_name),
    'borrower_phone', c.phone,
    'is_affiliate', l.customer_id is not null and exists (select 1 from public.customer_affiliates a
                      where a.customer_id = l.customer_id and a.deleted_at is null),
    'purpose', l.purpose, 'lent_at', l.lent_at, 'lent_by_name', pl.full_name,
    'expected_return_date', l.expected_return_date,
    'overdue', l.status = 'open' and l.expected_return_date < public.sg_today(),
    'days_overdue', case when l.status = 'open' then greatest(0, public.sg_today() - l.expected_return_date) else 0 end,
    'closed_at', l.closed_at,
    'outstanding', (select coalesce(sum(x.qty_out - x.qty_returned - x.qty_used - x.qty_lost), 0)
                      from public.stock_loan_lines x where x.loan_id = l.id),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'line_id', x.id, 'product_id', x.product_id, 'product_name', p.name, 'sku', p.sku,
                'qty_out', x.qty_out, 'qty_returned', x.qty_returned, 'qty_used', x.qty_used, 'qty_lost', x.qty_lost,
                'outstanding', x.qty_out - x.qty_returned - x.qty_used - x.qty_lost)
                order by p.name, x.id), '[]'::jsonb)
                from public.stock_loan_lines x join public.products p on p.id = x.product_id
               where x.loan_id = l.id),
    'events', (select coalesce(jsonb_agg(jsonb_build_object(
                'id', e.id, 'line_id', e.line_id, 'product_name', p.name, 'outcome', e.outcome,
                'quantity', e.quantity, 'condition', e.condition, 'location_type', e.location_type,
                'location_name', coalesce(es.name, ew.name), 'note', e.note,
                'recorded_at', e.recorded_at, 'recorded_by_name', pr.full_name)
                order by e.recorded_at, e.id), '[]'::jsonb)
                from public.stock_loan_events e
                join public.stock_loan_lines x on x.id = e.line_id
                join public.products p on p.id = x.product_id
                left join public.stores es on es.id = e.store_id
                left join public.warehouses ew on ew.id = e.warehouse_id
                left join public.profiles pr on pr.id = e.recorded_by
               where e.loan_id = l.id))
    from public.stock_loans l
    left join public.stores s on s.id = l.store_id
    left join public.warehouses w on w.id = l.warehouse_id
    left join public.customers c on c.id = l.customer_id
    left join public.profiles pl on pl.id = l.lent_by
   where l.id = p_loan_id
$fn$
$def$;

  c_uses_def constant text := $def$
create or replace function public.record_stock_uses(
  p_location_type text,
  p_location_id uuid,
  p_lines jsonb,
  p_reason text,
  p_note text default null,
  p_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
-- 401: Record use for several products at once, in one transaction (the
-- Owner, 6 Oct 2026): every line is recorded or none is. Each line goes
-- through record_stock_use, unchanged, so a line here is exactly a single use:
-- its checks, its USE- number, its movement, its audit row and its
-- permission (a store: staff with access to it; a warehouse: the warehouse
-- stock permission). p_lines is [{"product_id": "<uuid>", "quantity": n}],
-- each product once. A retry with the same p_request_id (the screen sends
-- one per form) records nothing again and answers with what was recorded,
-- but only when it is the same form: the same person, place, products,
-- quantities, reason and note. A form changed after a failed save is refused,
-- naming what was saved, rather than answered as if its changes were kept.
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  e jsonb; r record; v_res jsonb; v_uses jsonb := '[]'::jsonb; v_seen uuid[] := '{}'; v_pid uuid;
begin
  -- The form's own rules first. They depend on nothing saved, so the same
  -- form sent again passes them again.
  if p_location_type is null or p_location_type not in ('store', 'warehouse') then
    raise exception 'Location must be a store or a warehouse'; end if;
  if p_location_id is null then raise exception 'Choose where the stock was used'; end if;
  if v_reason = '' then raise exception 'A reason is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one product with a quantity'; end if;
  for e in select x from jsonb_array_elements(p_lines) x loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e->>'product_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Every line needs a product'; end if;
    if coalesce(e->>'quantity', '') !~ '^[0-9]{1,6}$' or (e->>'quantity')::integer <= 0 then
      raise exception 'Every product needs a whole quantity greater than zero'; end if;
    v_pid := (e->>'product_id')::uuid;
    if v_pid = any (v_seen) then raise exception 'The same product is listed more than once'; end if;
    v_seen := v_seen || v_pid;
  end loop;

  if p_request_id is not null then
    -- Two presses at once: the second waits here for the first, then finds it.
    perform pg_advisory_xact_lock(hashtextextended('record_stock_uses:' || p_request_id::text, 0));
    if exists (select 1 from public.stock_uses u where u.request_id = p_request_id) then
      if exists (select 1 from public.stock_uses u where u.request_id = p_request_id
                    and (u.used_by is distinct from auth.uid()
                         or u.location_type is distinct from p_location_type
                         or coalesce(u.store_id, u.warehouse_id) is distinct from p_location_id)) then
        raise exception 'This form was already used for another record. Close it and start again.'; end if;
      if (select jsonb_agg(jsonb_build_array(u.product_id, u.quantity) order by u.product_id)
            from public.stock_uses u where u.request_id = p_request_id)
         is distinct from
         (select jsonb_agg(jsonb_build_array(s.product_id, s.quantity) order by s.product_id)
            from (select (x->>'product_id')::uuid as product_id, (x->>'quantity')::integer as quantity
                    from jsonb_array_elements(p_lines) x) s)
         or exists (select 1 from public.stock_uses u where u.request_id = p_request_id
                       and (u.reason is distinct from v_reason or u.note is distinct from v_note)) then
        raise exception 'This form was already saved as %, and has been changed since: nothing more was recorded. Close it, and record anything else as a new use.',
          (select string_agg(u.use_no || ' (' || p.name || ' ×' || u.quantity || ')', ', ' order by u.use_no)
             from public.stock_uses u join public.products p on p.id = u.product_id
            where u.request_id = p_request_id); end if;
      return jsonb_build_object('success', true, 'replayed', true, 'uses',
        (select jsonb_agg(jsonb_build_object('use_no', u.use_no, 'product_id', u.product_id,
                  'quantity', u.quantity) order by u.use_no)
           from public.stock_uses u where u.request_id = p_request_id));
    end if;
  end if;

  -- In product order, so two batches at once lock the same rows in the same order.
  for r in select (x->>'product_id')::uuid as product_id, (x->>'quantity')::integer as quantity
             from jsonb_array_elements(p_lines) x order by 1
  loop
    v_res := public.record_stock_use(p_location_type, p_location_id, r.product_id, r.quantity, v_reason, v_note);
    if p_request_id is not null then
      update public.stock_uses set request_id = p_request_id where use_no = v_res->>'use_no';
    end if;
    v_uses := v_uses || jsonb_build_object('use_no', v_res->>'use_no', 'product_id', r.product_id,
      'quantity', r.quantity, 'remaining', (v_res->>'remaining')::integer);
  end loop;
  return jsonb_build_object('success', true, 'replayed', false, 'uses', v_uses);
end $fn$
$def$;

  c_lend_def constant text := $def$
create or replace function public.lend_stock(
  p_location_type text,
  p_location_id uuid,
  p_lines jsonb,
  p_expected_return_date date,
  p_customer_id uuid default null,
  p_borrower_name text default null,
  p_purpose text default null,
  p_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
-- 401: lends stock out of a store or a warehouse (the Owner, 6 Oct 2026). At
-- a store any staff with access to it, at a warehouse the warehouse stock
-- permission; no approval. The borrower is a customer (p_customer_id) or a
-- typed name (p_borrower_name), exactly one; the expected return date is
-- required and not in the past. Every line leaves the location's stock now,
-- with a loan_out movement, so it cannot be sold; a line with less stock
-- than asked refuses the loan. p_lines is [{"product_id": "<uuid>",
-- "quantity": n}], each product once. A retry with the same p_request_id
-- answers with the loan already made, but only when it is the same form (the
-- same person, place, borrower, purpose, date, products and quantities); a
-- form changed after a failed save is refused, naming the loan it made.
declare
  v_name text := nullif(regexp_replace(btrim(coalesce(p_borrower_name, '')), '\s+', ' ', 'g'), '');
  v_purpose text := nullif(btrim(coalesce(p_purpose, '')), '');
  v_today date := public.sg_today();
  v_where text := case when p_location_type = 'warehouse' then 'this warehouse' else 'this store' end;
  v_loc_name text; v_borrower text; e jsonb; r record; v_seen uuid[] := '{}'; v_pid uuid;
  v_have integer; v_prod text; v_loan public.stock_loans%rowtype; v_lines jsonb := '[]'::jsonb;
begin
  -- The form's own rules first. They depend on nothing saved, so the same
  -- form sent again passes them again.
  if p_location_type is null or p_location_type not in ('store', 'warehouse') then
    raise exception 'Location must be a store or a warehouse'; end if;
  if p_customer_id is not null and v_name is not null then
    raise exception 'Pick a customer or type a name, not both'; end if;
  if p_customer_id is null and v_name is null then
    raise exception 'Who is borrowing it? Pick a customer or type a name'; end if;
  if v_name is not null and length(v_name) > 120 then
    raise exception 'The borrower''s name is too long (120 characters at most)'; end if;
  if v_purpose is not null and length(v_purpose) > 500 then
    raise exception 'The purpose is too long (500 characters at most)'; end if;
  if p_expected_return_date is null then raise exception 'An expected return date is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one product with a quantity'; end if;
  for e in select x from jsonb_array_elements(p_lines) x loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e->>'product_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Every line needs a product'; end if;
    if coalesce(e->>'quantity', '') !~ '^[0-9]{1,6}$' or (e->>'quantity')::integer <= 0 then
      raise exception 'Every product needs a whole quantity greater than zero'; end if;
    v_pid := (e->>'product_id')::uuid;
    if v_pid = any (v_seen) then raise exception 'The same product is listed more than once'; end if;
    v_seen := v_seen || v_pid;
  end loop;

  if p_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('lend_stock:' || p_request_id::text, 0));
    select * into v_loan from public.stock_loans where request_id = p_request_id;
    if found then
      if v_loan.lent_by is distinct from auth.uid() then
        raise exception 'This form was already used for another loan. Close it and start again.'; end if;
      if v_loan.location_type is distinct from p_location_type
         or coalesce(v_loan.store_id, v_loan.warehouse_id) is distinct from p_location_id
         or v_loan.customer_id is distinct from p_customer_id
         or v_loan.borrower_name is distinct from (case when p_customer_id is null then v_name end)
         or v_loan.purpose is distinct from v_purpose
         or v_loan.expected_return_date is distinct from p_expected_return_date
         or (select jsonb_agg(jsonb_build_array(x.product_id, x.qty_out) order by x.product_id)
               from public.stock_loan_lines x where x.loan_id = v_loan.id)
            is distinct from
            (select jsonb_agg(jsonb_build_array(s.product_id, s.quantity) order by s.product_id)
               from (select (x->>'product_id')::uuid as product_id, (x->>'quantity')::integer as quantity
                       from jsonb_array_elements(p_lines) x) s) then
        raise exception 'This form was already saved as % (%), and has been changed since: nothing more was lent. Close it, and lend anything else as a new loan.',
          v_loan.loan_no,
          (select string_agg(p.name || ' ×' || x.qty_out, ', ' order by p.name)
             from public.stock_loan_lines x join public.products p on p.id = x.product_id
            where x.loan_id = v_loan.id); end if;
      return jsonb_build_object('success', true, 'replayed', true, 'loan_id', v_loan.id,
        'loan_no', v_loan.loan_no, 'loan', public.stock_loan_json(v_loan.id));
    end if;
  end if;

  if not public.stock_loan_access(p_location_type, p_location_id, true) then
    if p_location_type = 'warehouse' then
      raise exception 'You do not have permission to lend stock from a warehouse'; end if;
    raise exception 'No access to this store';
  end if;
  if p_location_type = 'store' then
    select s.name into v_loc_name from public.stores s where s.id = p_location_id and s.deleted_at is null;
  else
    select w.name into v_loc_name from public.warehouses w where w.id = p_location_id and w.deleted_at is null;
  end if;
  if v_loc_name is null then raise exception '% not found', initcap(p_location_type); end if;
  if p_customer_id is not null then
    select c.full_name into v_borrower from public.customers c where c.id = p_customer_id and c.deleted_at is null;
    if v_borrower is null then raise exception 'Customer not found'; end if;
  else
    v_borrower := v_name;
  end if;
  if p_expected_return_date < v_today then
    raise exception 'The expected return date cannot be in the past'; end if;

  insert into public.stock_loans (loan_no, location_type, store_id, warehouse_id, customer_id,
    borrower_name, purpose, expected_return_date, lent_by, request_id)
  values ('LOAN-' || lpad(nextval('public.stock_loan_no_seq')::text, 6, '0'), p_location_type,
    case when p_location_type = 'store' then p_location_id end,
    case when p_location_type = 'warehouse' then p_location_id end,
    p_customer_id, case when p_customer_id is null then v_name end, v_purpose,
    p_expected_return_date, auth.uid(), p_request_id)
  returning * into v_loan;

  -- In product order, so two loans or uses at once lock the same rows in the same order.
  for r in select (x->>'product_id')::uuid as product_id, (x->>'quantity')::integer as quantity
             from jsonb_array_elements(p_lines) x order by 1
  loop
    select p.name into v_prod from public.products p where p.id = r.product_id;
    if v_prod is null then raise exception 'Product not found'; end if;
    if p_location_type = 'store' then
      select i.current_qty into v_have from public.store_inventory i
       where i.store_id = p_location_id and i.product_id = r.product_id for update;
    else
      select i.current_qty into v_have from public.warehouse_inventory i
       where i.warehouse_id = p_location_id and i.product_id = r.product_id for update;
    end if;
    if coalesce(v_have, 0) < r.quantity then
      raise exception 'Only % of "%" in stock at %, so % cannot be lent',
        coalesce(v_have, 0), v_prod, v_where, r.quantity; end if;
    if p_location_type = 'store' then
      update public.store_inventory set current_qty = current_qty - r.quantity, updated_at = now()
       where store_id = p_location_id and product_id = r.product_id;
    else
      update public.warehouse_inventory set current_qty = current_qty - r.quantity, updated_at = now()
       where warehouse_id = p_location_id and product_id = r.product_id;
    end if;
    insert into public.stock_loan_lines (loan_id, product_id, qty_out)
    values (v_loan.id, r.product_id, r.quantity);
    insert into public.stock_movements
      (product_id, movement_type, from_store_id, from_warehouse_id, quantity, notes, created_by)
    values (r.product_id, 'loan_out',
      case when p_location_type = 'store' then p_location_id end,
      case when p_location_type = 'warehouse' then p_location_id end,
      r.quantity,
      v_loan.loan_no || ' — lent to ' || v_borrower || coalesce(' (' || v_purpose || ')', '')
        || ', due back ' || to_char(p_expected_return_date, 'DD Mon YYYY'),
      auth.uid());
    v_lines := v_lines || jsonb_build_object('product', v_prod, 'quantity', r.quantity,
      'remaining', coalesce(v_have, 0) - r.quantity);
  end loop;

  perform public.write_audit_ex('stock_loans', v_loan.id, 'stock_lent', null,
    jsonb_build_object('loan_no', v_loan.loan_no, 'location_type', p_location_type, 'location', v_loc_name,
      'customer_id', p_customer_id, 'borrower', v_borrower,
      'expected_return_date', p_expected_return_date, 'lines', v_lines),
    'inventory', v_purpose, case when p_location_type = 'store' then p_location_id end);

  return jsonb_build_object('success', true, 'replayed', false, 'loan_id', v_loan.id,
    'loan_no', v_loan.loan_no, 'loan', public.stock_loan_json(v_loan.id));
end $fn$
$def$;

  c_return_def constant text := $def$
create or replace function public.return_stock_loan(
  p_loan_id uuid,
  p_entries jsonb,
  p_note text default null,
  p_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
-- 401: takes back a loan, in part or in full (the Owner, 6 Oct 2026).
-- p_entries is [{"line_id": "<uuid>", "outcome": "returned"|"used"|"lost",
-- "quantity": n, "condition": "good"|"damaged", "location_type":
-- "store"|"warehouse", "location_id": "<uuid>"}]: a return names its condition
-- (good by default) and where it came back to, any active store, or a
-- warehouse with the warehouse stock permission; "used" (used / given away)
-- may say "damaged" (it came back damaged and is recorded as used); "lost"
-- (lost / damaged) says nothing more. A line's entries may not account for
-- more than is still out on it. A return goes back into stock with a
-- loan_return movement; used and lost move nothing (the stock left at
-- lend-out). The loan closes when every line is accounted for. Acting on a
-- loan needs what lending from its location needs. A retry with the same
-- p_request_id records nothing again, but only when it is the same form (the
-- same person, loan and entries); a form changed after a failed save is
-- refused, naming what was recorded.
declare
  l public.stock_loans%rowtype; v_line public.stock_loan_lines%rowtype;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  e jsonb; r record; v_borrower text; v_prod text; v_left integer; v_mv uuid;
  v_done jsonb := '[]'::jsonb; v_closed boolean;
begin
  if p_loan_id is null then raise exception 'Loan not found'; end if;
  -- The form's own rules first. They depend on nothing saved, so the same
  -- form sent again passes them again.
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) = 0 then
    raise exception 'Record what came back, or what was used or lost, for at least one item'; end if;
  for e in select x from jsonb_array_elements(p_entries) x loop
    if jsonb_typeof(e) <> 'object' or coalesce(e->>'line_id', '') !~* c_uuid then
      raise exception 'An entry names no item of the loan'; end if;
    if coalesce(e->>'outcome', '') not in ('returned', 'used', 'lost') then
      raise exception 'Say whether it was returned, used / given away, or lost / damaged'; end if;
    if coalesce(e->>'quantity', '') !~ '^[0-9]{1,6}$' or (e->>'quantity')::integer <= 0 then
      raise exception 'Every quantity must be a whole number greater than zero'; end if;
    if e->>'outcome' = 'returned' then
      if coalesce(e->>'condition', 'good') not in ('good', 'damaged') then
        raise exception 'A returned item is in good or damaged condition'; end if;
      if coalesce(e->>'location_type', '') not in ('store', 'warehouse')
         or coalesce(e->>'location_id', '') !~* c_uuid then
        raise exception 'Choose the store or warehouse it came back to'; end if;
    elsif e->>'outcome' = 'used' then
      if coalesce(e->>'condition', 'damaged') <> 'damaged' then
        raise exception 'Used / given away is recorded as it is, or as "damaged" for an item that came back damaged'; end if;
    elsif e->>'condition' is not null then
      raise exception 'Lost / damaged takes no condition';
    end if;
  end loop;

  if p_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('return_stock_loan:' || p_request_id::text, 0));
    if exists (select 1 from public.stock_loan_events v where v.request_id = p_request_id) then
      if exists (select 1 from public.stock_loan_events v where v.request_id = p_request_id
                    and (v.loan_id <> p_loan_id or v.recorded_by is distinct from auth.uid())) then
        raise exception 'This form was already used for another take-back. Close it and start again.'; end if;
      -- The entries as they are recorded (condition, place and note as below).
      if (select jsonb_agg(jsonb_build_array(s.line_id, s.outcome, s.quantity, s.condition, s.location_type, s.location_id, s.note)
                  order by s.line_id, s.outcome, s.quantity, s.condition, s.location_type, s.location_id, s.note)
            from (select v.line_id, v.outcome, v.quantity, v.condition, v.location_type,
                         coalesce(v.store_id, v.warehouse_id) as location_id, v.note
                    from public.stock_loan_events v where v.request_id = p_request_id) s)
         is distinct from
         (select jsonb_agg(jsonb_build_array(s.line_id, s.outcome, s.quantity, s.condition, s.location_type, s.location_id, s.note)
                  order by s.line_id, s.outcome, s.quantity, s.condition, s.location_type, s.location_id, s.note)
            from (select (x->>'line_id')::uuid as line_id, x->>'outcome' as outcome, (x->>'quantity')::integer as quantity,
                         case when x->>'outcome' = 'returned' then coalesce(x->>'condition', 'good')
                              when x->>'outcome' = 'used' and x->>'condition' = 'damaged' then 'damaged' end as condition,
                         case when x->>'outcome' = 'returned' then x->>'location_type' end as location_type,
                         case when x->>'outcome' = 'returned' then (x->>'location_id')::uuid end as location_id,
                         coalesce(nullif(btrim(coalesce(x->>'note', '')), ''), v_note) as note
                    from jsonb_array_elements(p_entries) x) s) then
        raise exception 'This form was already saved for % (%), and has been changed since: nothing more was recorded. Close it, and record anything else as a new take-back.',
          (select s.loan_no from public.stock_loans s where s.id = p_loan_id),
          (select string_agg(p.name || ' ×' || v.quantity || ' ' || v.outcome, ', ' order by p.name, v.outcome)
             from public.stock_loan_events v
             join public.stock_loan_lines x on x.id = v.line_id
             join public.products p on p.id = x.product_id
            where v.request_id = p_request_id); end if;
      return jsonb_build_object('success', true, 'replayed', true,
        'closed', (select s.status = 'closed' from public.stock_loans s where s.id = p_loan_id),
        'loan', public.stock_loan_json(p_loan_id));
    end if;
  end if;

  select * into l from public.stock_loans where id = p_loan_id for update;
  if not found then raise exception 'Loan not found'; end if;
  if not public.stock_loan_access(l.location_type, coalesce(l.store_id, l.warehouse_id), true) then
    if l.location_type = 'warehouse' then
      raise exception 'You do not have permission to take back a loan from a warehouse'; end if;
    raise exception 'No access to this store';
  end if;
  if l.status <> 'open' then
    raise exception '% is already closed: everything on it is accounted for', l.loan_no; end if;
  v_borrower := coalesce((select c.full_name from public.customers c where c.id = l.customer_id), l.borrower_name);

  -- What depends on the loan and the places: its own items, and where a
  -- return may go.
  for e in select x from jsonb_array_elements(p_entries) x loop
    if not exists (select 1 from public.stock_loan_lines x
                    where x.id = (e->>'line_id')::uuid and x.loan_id = l.id) then
      raise exception 'An entry names an item that is not on %', l.loan_no; end if;
    if e->>'outcome' = 'returned' then
      if e->>'location_type' = 'warehouse' then
        if not public.can_manage_warehouse_stock() then
          raise exception 'You do not have permission to take stock back into a warehouse'; end if;
        if not exists (select 1 from public.warehouses w where w.id = (e->>'location_id')::uuid
                          and w.deleted_at is null and w.is_active) then
          raise exception 'Warehouse not found'; end if;
      elsif not exists (select 1 from public.stores s where s.id = (e->>'location_id')::uuid
                           and s.deleted_at is null and s.is_active) then
        raise exception 'Store not found';
      end if;
    end if;
  end loop;

  -- No line accounts for more than is still out on it (lines locked in id order).
  for r in select (x->>'line_id')::uuid as line_id, sum((x->>'quantity')::integer) as quantity
             from jsonb_array_elements(p_entries) x group by 1 order by 1
  loop
    select * into v_line from public.stock_loan_lines where id = r.line_id for update;
    v_left := v_line.qty_out - v_line.qty_returned - v_line.qty_used - v_line.qty_lost;
    if r.quantity > v_left then
      select p.name into v_prod from public.products p where p.id = v_line.product_id;
      raise exception 'Only % of "%" still out on %, so % cannot be accounted for',
        v_left, v_prod, l.loan_no, r.quantity; end if;
  end loop;

  -- Returns first, by place and product, so two take-backs at once lock the
  -- same stock rows in the same order.
  for r in select (t.x->>'line_id')::uuid as line_id, t.x->>'outcome' as outcome,
                  (t.x->>'quantity')::integer as quantity, x2.product_id,
                  case when t.x->>'outcome' = 'returned' then coalesce(t.x->>'condition', 'good')
                       when t.x->>'outcome' = 'used' and t.x->>'condition' = 'damaged' then 'damaged' end as condition,
                  case when t.x->>'outcome' = 'returned' then t.x->>'location_type' end as location_type,
                  case when t.x->>'outcome' = 'returned' then (t.x->>'location_id')::uuid end as location_id,
                  coalesce(nullif(btrim(coalesce(t.x->>'note', '')), ''), v_note) as note
             from jsonb_array_elements(p_entries) with ordinality t(x, ord)
             join public.stock_loan_lines x2 on x2.id = (t.x->>'line_id')::uuid
            order by 6 nulls last, 7, x2.product_id, t.ord
  loop
    v_mv := null;
    if r.outcome = 'returned' then
      if r.location_type = 'store' then
        insert into public.store_inventory (store_id, product_id, current_qty)
        values (r.location_id, r.product_id, r.quantity)
        on conflict (store_id, product_id)
          do update set current_qty = public.store_inventory.current_qty + excluded.current_qty,
                        updated_at = now();
      else
        insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
        values (r.location_id, r.product_id, r.quantity)
        on conflict (warehouse_id, product_id)
          do update set current_qty = public.warehouse_inventory.current_qty + excluded.current_qty,
                        updated_at = now();
      end if;
      insert into public.stock_movements
        (product_id, movement_type, to_store_id, to_warehouse_id, quantity, notes, created_by)
      values (r.product_id, 'loan_return',
        case when r.location_type = 'store' then r.location_id end,
        case when r.location_type = 'warehouse' then r.location_id end,
        r.quantity,
        l.loan_no || ' — returned by ' || v_borrower
          || case when r.condition = 'damaged' then ' (damaged)' else '' end
          || coalesce(': ' || r.note, ''),
        auth.uid())
      returning id into v_mv;
    end if;
    insert into public.stock_loan_events (loan_id, line_id, outcome, quantity, condition,
      location_type, store_id, warehouse_id, movement_id, note, request_id, recorded_by)
    values (l.id, r.line_id, r.outcome, r.quantity, r.condition, r.location_type,
      case when r.location_type = 'store' then r.location_id end,
      case when r.location_type = 'warehouse' then r.location_id end,
      v_mv, r.note, p_request_id, auth.uid());
    update public.stock_loan_lines
       set qty_returned = qty_returned + case when r.outcome = 'returned' then r.quantity else 0 end,
           qty_used = qty_used + case when r.outcome = 'used' then r.quantity else 0 end,
           qty_lost = qty_lost + case when r.outcome = 'lost' then r.quantity else 0 end
     where id = r.line_id;
    v_done := v_done || jsonb_build_object('line_id', r.line_id, 'product_id', r.product_id,
      'outcome', r.outcome, 'quantity', r.quantity, 'condition', r.condition,
      'location_type', r.location_type, 'location_id', r.location_id);
  end loop;

  v_closed := not exists (select 1 from public.stock_loan_lines x
                           where x.loan_id = l.id and x.qty_returned + x.qty_used + x.qty_lost < x.qty_out);
  if v_closed then
    update public.stock_loans set status = 'closed', closed_at = now() where id = l.id;
  end if;

  perform public.write_audit_ex('stock_loans', l.id, 'stock_loan_taken_back',
    jsonb_build_object('status', l.status),
    jsonb_build_object('loan_no', l.loan_no, 'entries', v_done, 'closed', v_closed),
    'inventory', v_note, l.store_id);

  return jsonb_build_object('success', true, 'replayed', false, 'closed', v_closed,
    'loan', public.stock_loan_json(l.id));
end $fn$
$def$;

  c_at_def constant text := $def$
create or replace function public.stock_loans_at(
  p_location_type text,
  p_location_id uuid,
  p_include_closed boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
-- 401: the "On loan" list of a store or a warehouse (the Owner, 6 Oct 2026):
-- the loans lent from it that are still open, the oldest due first, and when
-- asked its last 50 closed ones. The pages add up each product's "Out on
-- loan" from the open loans' lines. can_act: whether the caller may lend
-- from here, take these loans back and Record use here (the rule the
-- functions that do it check), so a Manager who sees a store's list without
-- being assigned to it is not offered buttons that would be refused.
begin
  if p_location_type is null or p_location_type not in ('store', 'warehouse') then
    raise exception 'Location must be a store or a warehouse'; end if;
  if not public.stock_loan_access(p_location_type, p_location_id, false) then
    raise exception 'No access to this %', p_location_type; end if;
  return jsonb_build_object(
    'today', public.sg_today(),
    'can_act', public.stock_loan_access(p_location_type, p_location_id, true),
    'open', (select coalesce(jsonb_agg(public.stock_loan_json(x.id)
                     order by x.expected_return_date, x.lent_at, x.loan_no), '[]'::jsonb)
               from public.stock_loans x
              where x.status = 'open' and x.location_type = p_location_type
                and coalesce(x.store_id, x.warehouse_id) = p_location_id),
    'closed', case when coalesce(p_include_closed, false) then
             (select coalesce(jsonb_agg(public.stock_loan_json(y.id) order by y.closed_at desc, y.loan_no desc), '[]'::jsonb)
                from (select x.id, x.closed_at, x.loan_no from public.stock_loans x
                       where x.status = 'closed' and x.location_type = p_location_type
                         and coalesce(x.store_id, x.warehouse_id) = p_location_id
                       order by x.closed_at desc, x.loan_no desc limit 50) y)
             else '[]'::jsonb end);
end $fn$
$def$;

  c_customer_def constant text := $def$
create or replace function public.customer_stock_loans(p_customer_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  -- 401: a customer's loans for their profile (the Owner, 6 Oct 2026), the
  -- ones the caller may see (stock_loan_access), open first, newest first.
  select coalesce(jsonb_agg(public.stock_loan_json(l.id)
           order by (l.status = 'open') desc, l.lent_at desc, l.loan_no desc), '[]'::jsonb)
    from public.stock_loans l
   where l.customer_id = p_customer_id
     and public.stock_loan_access(l.location_type, coalesce(l.store_id, l.warehouse_id), false)
$fn$
$def$;

  -- ── The anchor and its replacement ────────────────────────────────────────
  c_label_a constant text :=
       E' when ''transfer_dispatch'' then ''Transfer Dispatch'' when ''transfer_receipt'' then ''Transfer Receipt'' when ''transfer_discrepancy'' then ''Transfer Discrepancy''\n'
    || E' else initcap(';
  c_label_r constant text :=
       E' when ''transfer_dispatch'' then ''Transfer Dispatch'' when ''transfer_receipt'' then ''Transfer Receipt'' when ''transfer_discrepancy'' then ''Transfer Discrepancy''\n'
    || E' -- 401: stock lent out and taken back (the Owner, 6 Oct 2026)\n'
    || E' when ''loan_out'' then ''Lent out'' when ''loan_return'' then ''Loan returned''\n'
    || E' else initcap(';

  c_new_fns constant text[] := array[
    'stock_loan_access(text,uuid,boolean)', 'stock_loan_json(uuid)',
    'record_stock_uses(text,uuid,jsonb,text,text,uuid)',
    'lend_stock(text,uuid,jsonb,date,uuid,text,text,uuid)',
    'return_stock_loan(uuid,jsonb,text,uuid)', 'stock_loans_at(text,uuid,boolean)',
    'customer_stock_loans(uuid)'];
  c_new_md5 constant text[] := array[
    '09f68356afdabb88cade05af7859e158', 'd9726b2be1578afc7915fe6995db5206', '8cab37c88f3f46548d941cd100eb1a78', 'fcea544234f910ccecad12f185bdf753', '978c886b03ccae32d48de8bc78667975', '4d40d09d2263c304f8de7ddc9686d72d', '72ea1935e18db21c6ee75d09568d9ecf'];
  c_internal constant text[] := array['stock_loan_access(text,uuid,boolean)', 'stock_loan_json(uuid)'];
  c_client constant text[] := array[
    'record_stock_uses(text,uuid,jsonb,text,text,uuid)',
    'lend_stock(text,uuid,jsonb,date,uuid,text,text,uuid)',
    'return_stock_loan(uuid,jsonb,text,uuid)', 'stock_loans_at(text,uuid,boolean)',
    'customer_stock_loans(uuid)'];
  c_label_before constant text := '7df9ac5d4ce27fa6735f1e2c67bf66b6';
  c_label_after constant text := 'f8820dec2fa2db27419df0a08a3c6a07';

  r record; d text; v text; n int; i int; v_bad text; v_label_def text;
begin
  -- ── 400 first ─────────────────────────────────────────────────────────────
  if (select count(*) from pg_enum e where e.enumtypid = 'public.stock_movement_type'::regtype
         and e.enumlabel in ('loan_out', 'loan_return')) <> 2 then
    raise exception '401: stock_movement_type has no loan_out and loan_return values. Apply 400 first.'; end if;

  -- ── Guards and the patched text: nothing is installed unless all pass ─────
  d := pg_get_functiondef('public.stock_history_type_label(text)'::regprocedure);
  v := md5(d);
  if v = c_label_after then
    raise notice '401: public.stock_history_type_label(text) is already this version; left alone';
  elsif v <> c_label_before then
    raise exception '401: public.stock_history_type_label(text) is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', v;
  else
    n := (length(d) - length(replace(d, c_label_a, ''))) / length(c_label_a);
    if n <> 1 then
      raise exception '401: the anchor of public.stock_history_type_label(text) was found % times, not once', n; end if;
    v_label_def := replace(d, c_label_a, c_label_r);
  end if;
  -- Relied on, not changed: the versions read on 6 Oct 2026.
  for r in select * from (values
    ('record_stock_use(text,uuid,uuid,integer,text,text)', 'db278faba262b0a3801944cd821a62fd'),
    ('stock_history_effect(uuid,text)', 'fba6f63412970dbf6ac83e567c4d85e2'),
    ('user_has_store_access(uuid)', '8c82c6bcb64f496c5a05a2b8dafa95f8'),
    ('can_manage_warehouse_stock()', 'b51c6f1c0e77a277d8757d824cb198dd'),
    ('is_manager_or_above()', 'f12b9ed342070fa4defa30e4da2ba655')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '401: public.% is missing or not the version read on 6 Oct 2026', r.fn; end if;
  end loop;
  for i in 1 .. array_length(c_new_fns, 1) loop
    if to_regprocedure('public.' || c_new_fns[i]) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || c_new_fns[i]))) <> c_new_md5[i] then
      raise exception '401: a different public.% already exists (md5 %)', c_new_fns[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_fns[i]))); end if;
  end loop;
  -- No other function of these names (the API picks an overload by its
  -- parameter names alone; 386, 388, 390).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('stock_loan_access', 'stock_loan_json', 'record_stock_uses', 'lend_stock',
                       'return_stock_loan', 'stock_loans_at', 'customer_stock_loans')
     and not (p.oid::regprocedure::text = any (c_new_fns));
  if v_bad is not null then raise exception '401: other functions of these names exist: %', v_bad; end if;

  -- ── Record use's request id ─────────────────────────────────────────────────
  alter table public.stock_uses add column if not exists request_id uuid;
  create index if not exists stock_uses_request on public.stock_uses (request_id) where request_id is not null;

  -- ── The loans ─────────────────────────────────────────────────────────────
  create sequence if not exists public.stock_loan_no_seq;
  create table if not exists public.stock_loans (
    id uuid primary key default gen_random_uuid(),
    loan_no text not null unique,
    location_type text not null check (location_type in ('store', 'warehouse')),
    store_id uuid references public.stores(id),
    warehouse_id uuid references public.warehouses(id),
    customer_id uuid references public.customers(id),
    borrower_name text,
    purpose text,
    expected_return_date date not null,
    status text not null default 'open' check (status in ('open', 'closed')),
    lent_by uuid references public.profiles(id),
    lent_at timestamptz not null default now(),
    closed_at timestamptz,
    request_id uuid unique,
    constraint stock_loans_location_present check (
      (location_type = 'store' and store_id is not null and warehouse_id is null)
      or (location_type = 'warehouse' and warehouse_id is not null and store_id is null)),
    constraint stock_loans_one_borrower check (
      (customer_id is not null) <> (nullif(btrim(coalesce(borrower_name, '')), '') is not null)),
    constraint stock_loans_closed_when check ((status = 'closed') = (closed_at is not null))
  );
  create table if not exists public.stock_loan_lines (
    id uuid primary key default gen_random_uuid(),
    loan_id uuid not null references public.stock_loans(id),
    product_id uuid not null references public.products(id),
    qty_out integer not null check (qty_out > 0),
    qty_returned integer not null default 0 check (qty_returned >= 0),
    qty_used integer not null default 0 check (qty_used >= 0),
    qty_lost integer not null default 0 check (qty_lost >= 0),
    constraint stock_loan_lines_accounted check (qty_returned + qty_used + qty_lost <= qty_out),
    constraint stock_loan_lines_product_once unique (loan_id, product_id)
  );
  create table if not exists public.stock_loan_events (
    id uuid primary key default gen_random_uuid(),
    loan_id uuid not null references public.stock_loans(id),
    line_id uuid not null references public.stock_loan_lines(id),
    outcome text not null check (outcome in ('returned', 'used', 'lost')),
    quantity integer not null check (quantity > 0),
    condition text check (condition in ('good', 'damaged')),
    location_type text check (location_type in ('store', 'warehouse')),
    store_id uuid references public.stores(id),
    warehouse_id uuid references public.warehouses(id),
    movement_id uuid references public.stock_movements(id),
    note text,
    request_id uuid,
    recorded_by uuid references public.profiles(id),
    recorded_at timestamptz not null default now(),
    constraint stock_loan_events_where check (case
      when outcome = 'returned' then condition is not null and movement_id is not null and (
        (location_type = 'store' and store_id is not null and warehouse_id is null)
        or (location_type = 'warehouse' and warehouse_id is not null and store_id is null))
      when outcome = 'used' then coalesce(condition, 'damaged') = 'damaged'
        and location_type is null and store_id is null and warehouse_id is null and movement_id is null
      else condition is null and location_type is null and store_id is null and warehouse_id is null
        and movement_id is null end)
  );
  create index if not exists stock_loans_open_store on public.stock_loans (store_id) where status = 'open';
  create index if not exists stock_loans_open_warehouse on public.stock_loans (warehouse_id) where status = 'open';
  create index if not exists stock_loans_customer on public.stock_loans (customer_id) where customer_id is not null;
  create index if not exists stock_loan_events_loan on public.stock_loan_events (loan_id);
  create index if not exists stock_loan_events_request on public.stock_loan_events (request_id) where request_id is not null;

  alter table public.stock_loans enable row level security;
  alter table public.stock_loan_lines enable row level security;
  alter table public.stock_loan_events enable row level security;
  revoke all on table public.stock_loans, public.stock_loan_lines, public.stock_loan_events
    from public, anon, authenticated;
  grant select on table public.stock_loans, public.stock_loan_lines, public.stock_loan_events to authenticated;
  grant all on table public.stock_loans, public.stock_loan_lines, public.stock_loan_events to service_role;
  revoke all on sequence public.stock_loan_no_seq from public, anon, authenticated;
  grant usage, select on sequence public.stock_loan_no_seq to service_role;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'stock_loans'
                   and policyname = 'read stock loans') then
    create policy "read stock loans" on public.stock_loans for select to authenticated
      using (public.is_manager_or_above()
             or (store_id is not null and public.user_has_store_access(store_id))
             or (warehouse_id is not null and public.can_manage_warehouse_stock()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'stock_loan_lines'
                   and policyname = 'read stock loan lines') then
    create policy "read stock loan lines" on public.stock_loan_lines for select to authenticated
      using (exists (select 1 from public.stock_loans l where l.id = loan_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'stock_loan_events'
                   and policyname = 'read stock loan events') then
    create policy "read stock loan events" on public.stock_loan_events for select to authenticated
      using (exists (select 1 from public.stock_loans l where l.id = loan_id));
  end if;
  comment on table public.stock_loans is
    '401: stock lent out of a store or a warehouse (LOAN-000001), to a customer or a typed name, due back on a date; open until every line is accounted for.';
  comment on table public.stock_loan_lines is
    '401: a product on a loan: how many went out, and how many have come back, been used or been lost.';
  comment on table public.stock_loan_events is
    '401: each take-back entry of a loan: returned (with condition, where to, and its loan_return movement), used, or lost.';
  comment on column public.stock_uses.request_id is
    '401: the Record use form that recorded this use, shared by its lines (record_stock_uses), so a retry records nothing twice.';

  -- ── Install: the helpers first, then the functions that call them ─────────
  execute c_access_def;
  execute c_json_def;
  execute c_uses_def;
  execute c_lend_def;
  execute c_return_def;
  execute c_at_def;
  execute c_customer_def;
  foreach v in array c_internal loop
    execute format('revoke all on function public.%s from public, anon, authenticated', v);
    execute format('grant execute on function public.%s to service_role', v);
  end loop;
  foreach v in array c_client loop
    execute format('revoke all on function public.%s from public, anon', v);
    execute format('grant execute on function public.%s to authenticated, service_role', v);
  end loop;
  if v_label_def is not null then
    execute v_label_def;
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  v := md5(pg_get_functiondef('public.stock_history_type_label(text)'::regprocedure));
  if v <> c_label_after then v_bad := concat_ws('; ', v_bad, 'stock_history_type_label(text) ' || v); end if;
  for i in 1 .. array_length(c_new_fns, 1) loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || c_new_fns[i])));
    if v <> c_new_md5[i] then v_bad := concat_ws('; ', v_bad, c_new_fns[i] || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '401: installed with md5s other than the tested ones: %', v_bad; end if;
  -- The pages reach what they call, signed in only; the helpers are endpoints for nobody.
  foreach v in array c_client || array['stock_history_type_label(text)', 'record_stock_use(text,uuid,uuid,integer,text,text)'] loop
    if not has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '401: public.% is not callable by staff', v; end if;
    if has_function_privilege('anon', 'public.' || v, 'execute') then
      raise exception '401: public.% is callable signed out', v; end if;
  end loop;
  foreach v in array c_internal loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '401: public.% is callable by a client role', v; end if;
  end loop;
  if has_table_privilege('anon', 'public.stock_loans', 'select')
     or has_table_privilege('authenticated', 'public.stock_loans', 'insert')
     or has_table_privilege('authenticated', 'public.stock_loan_lines', 'update')
     or has_table_privilege('authenticated', 'public.stock_loan_events', 'delete')
     or has_sequence_privilege('authenticated', 'public.stock_loan_no_seq', 'usage') then
    raise exception '401: a client role can write the loans or read them signed out'; end if;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
